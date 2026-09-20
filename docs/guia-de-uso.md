# Guia de uso e apresentação

Para quem quer **entender, reproduzir e apresentar** o DFe Broker. Os comandos da parte 4 foram executados
de ponta a ponta em 2026-09-20 (Windows, FPC) e a saída mostrada é a real. O que **não** foi verificado está
marcado como tal — isso importa mais na hora de apresentar do que qualquer funcionalidade.

- [1. Em um minuto](#1-em-um-minuto)
- [2. Vocabulário mínimo](#2-vocabulário-mínimo)
- [3. Como as peças se encaixam](#3-como-as-peças-se-encaixam)
- [4. Roteiro prático: ver tudo funcionando sem certificado](#4-roteiro-prático-ver-tudo-funcionando-sem-certificado)
- [5. Funcionalidades em detalhe](#5-funcionalidades-em-detalhe)
- [6. Roteiro de apresentação e perguntas difíceis](#6-roteiro-de-apresentação-e-perguntas-difíceis)
- [7. O que NÃO está provado](#7-o-que-não-está-provado)
- [8. Onde está cada coisa no código](#8-onde-está-cada-coisa-no-código)

---

## 1. Em um minuto

**O problema.** Toda empresa recebe NF-e emitidas contra o seu CNPJ. A SEFAZ oferece um serviço,
a *Distribuição de DFe*, que entrega esses documentos — mas só a quem se identifica com **certificado
digital**, consulta **no máximo uma vez por hora** e mantém um **cursor (NSU)** correto. Errar o cursor
significa perder documento ou ser bloqueado. Hoje a escolha é pagar um SaaS ou reimplementar tudo dentro do ERP.

**A proposta.** Um programa **open source e auto-hospedado**: você roda com o *seu* certificado, ele consulta a
SEFAZ, cuida do cursor, e **publica cada documento como uma mensagem numa fila AMQP**. Qualquer sistema
(Delphi, Python, Java, Node…) consome com um cliente AMQP comum — **sem saber nada de SEFAZ, certificado ou ACBr**.

**Diferenciais para dizer em voz alta:**

1. **Sem infraestrutura extra** — o broker AMQP vem embutido no mesmo processo (mas pode apontar para um RabbitMQ).
2. **Desacoplado** — quem consome só precisa de AMQP + o contrato de routing-key. Zero acoplamento com Pascal.
3. **Não perde documento** — cursor persistido com escrita atômica, fila durável, entrega "pelo menos uma vez".
4. **Testável sem certificado** — vem com um simulador da SEFAZ (que também serve a outros projetos).
5. **Extensível** — CTe/MDFe entram como *providers* sem tocar no core.
6. **Multiplataforma** — Delphi e FPC; Windows (console ou serviço) e Linux (systemd).

---

## 2. Vocabulário mínimo

| Termo | O que é |
|---|---|
| **Distribuição de DFe** | Serviço da SEFAZ que devolve os documentos fiscais em que o seu CNPJ aparece (emitente, destinatário, transportador…). |
| **NSU** | Número sequencial único que a SEFAZ atribui a cada documento/evento **por CNPJ**. Você pergunta "o que veio depois do NSU 40?". |
| **Cursor** | O último NSU que já processamos. É o ponto de maior risco: se corromper, perde-se ou repete-se documento. |
| **`cStat`** | Código de resposta da SEFAZ. **137** = "nada novo", **138** = "há documentos", **656** = "consumo indevido" (consultou cedo demais → bloqueio de 1 h), **108/109** = serviço indisponível. |
| **resNFe / procNFe** | `resNFe` = *resumo* da NF-e (chave, emitente, valor). `procNFe` = o XML **completo**. |
| **Evento** | Algo que aconteceu com uma NF-e: cancelamento, carta de correção, manifestação… (`resEvento` / `procEventoNFe`). |
| **Chave de acesso** | Os 44 dígitos que identificam uma NF-e. É o ID para deduplicar. |
| **Manifestação do destinatário** | Ato **fiscal** do destinatário sobre uma NF-e: *ciência*, *confirmação*, *desconhecimento*, *operação não realizada*. |
| **Exchange / routing-key / fila** | Vocabulário do AMQP: o produtor publica numa *exchange* com uma *routing-key*; a exchange encaminha às *filas* cujo padrão casa. |
| **ACBr** | Conjunto de componentes brasileiros (LGPL) que fala com a SEFAZ, lê o certificado e assina XML. |
| **Homologação × produção** | Dois ambientes da SEFAZ, com NSUs **separados**. |

---

## 3. Como as peças se encaixam

```
                                  ┌──────────────────────────── DFeBrokerConsole / Serviço Windows ───────────────────────────┐
  SEFAZ real  ◄──HTTPS+cert──┐    │                                                                                           │
                             ├────┤  Orquestrador (1 unidade por certificado)                                                 │
  DFeSimulador ◄──HTTP───────┘    │    ├─ Client ACBr ── consulta (por NSU), assina eventos                                    │
  (para testes)                   │    ├─ Cursor de NSU (arquivo, escrita atômica)                                             │
                                  │    └─ Provider NFe ── decodifica docZip → documento/evento + routing-key                   │
                                  │                          │                                                                 │
                                  │                          ▼   publisher confirms                                            │
                                  │  Publicador AMQP ──► Broker AMQP embutido (exchange topic "dfe") ──► filas                 │
                                  │                                        ▲                                                   │
                                  │  Fonte de comandos ◄── fila "dfe.comandos" (routing-key comando.manifestacao)              │
                                  └───────────────────────────────────────────────────────────────────────────────────────────┘
                                                                     │
                     consumidores em qualquer linguagem (pika, amqplib, RabbitMQ.Client…) ◄─┘
```

**Um ciclo, em ordem:**

1. A cada *tick* (60 s por padrão) o host verifica se a config mudou (recarga a quente), executa os ciclos vencidos e processa comandos manuais.
2. Para cada certificado, se já passou o intervalo (1 h por padrão), o client consulta a SEFAZ pedindo "tudo depois do NSU *n*".
3. A resposta traz um lote de `docZip` (XML comprimido). O provider decodifica cada item e monta a routing-key.
4. O publicador manda cada item ao broker e **espera a confirmação**. Só depois de **todo o lote** confirmado o cursor avança.
5. Se algo falhar no meio, o cursor **não** avança: o lote é repetido (por isso o consumidor deduplica pela chave).

**A convenção pública mais importante** (decisão 4 — não muda por PR isolado):

```
exchange:     dfe   (topic, durável)
routing-key:  <tipo>.<categoria>.<uf>.<cnpj>
exemplos:     nfe.documento.rs.11222333000181
              nfe.evento.cancelamento.rs.11222333000181
              nfe.evento.manifestacaorejeitada.rs.11222333000181
padrões:      nfe.#   nfe.evento.#   nfe.documento.sp.*   #.11222333000181
```

`<cnpj>` é o do **certificado que consultou**, não necessariamente o emitente. O corpo é o XML, UTF-8, persistente.

---

## 4. Roteiro prático: ver tudo funcionando sem certificado

Este roteiro usa o **DFeSimulador** (um servidor que responde como a SEFAZ) e um certificado de **teste** que
já está no repositório. Nada toca a SEFAZ real.

### 4.1 Pré-requisitos

- Repositório com os submódulos (ver o README): `vendor/pascal-amqp-faa`, `vendor/ACBr` (`tools/init-acbr-submodule.sh`) e `vendor/horse` (para o simulador).
- **OpenSSL 3 e libxml2** acessíveis (o ACBr precisa até para consultar). Confira com `DFeBrokerConsole --verificar-ambiente`; cada linha diz o que está ok ou o que falta ([`dependencias-runtime.md`](dependencias-runtime.md)).
- Python 3 com `pip install pika` (só para os consumidores de exemplo).
- Executáveis compilados: `hosts/console/DFeBrokerConsole` e `simulador/DFeSimulador`. Os comandos exatos (inclusive `lazbuild --add-package-link`, sem o qual dá `Broken dependency`, e `sh simulador/preparar-horse.sh`, só no Windows/FPC) estão em "Como compilar e rodar" no [`README.md`](../README.md); no Delphi, pelo `PascalDfeBroker.groupproj`. **No Windows, clone num caminho curto** (ex.: `C:\dev\`).
- Portas **9200** (simulador) e **5672** (AMQP) livres. Se o Docker/WSL já usa a 5672, troque `Porta=` no `dfe.ini` e use `--porta` nos scripts Python.

A configuração da demo está em [`exemplos/demo-simulador/dfe.ini`](../exemplos/demo-simulador/dfe.ini) (leia-a: é curta e cada linha está comentada). Pontos-chave dela: `Ambiente=homologacao` + `SimuladorURL=…`, intervalos de 10 s (só para demo), duas filas nomeadas e um certificado `matriz` com o CNPJ de teste `11222333000181`.

Abra **quatro terminais** na raiz do repositório.

### 4.2 Passo 1 — ligar o "SEFAZ de mentira"

```
simulador/DFeSimulador --porta 9200
```

Confira: `curl http://127.0.0.1:9200/ping` responde `ok`. Este é o único componente que você controla por HTTP (API admin) para preparar cenários.

### 4.3 Passo 2 — ligar o broker

```
hosts/console/DFeBrokerConsole --config exemplos/demo-simulador/dfe.ini
```

Saída esperada (resumida):

```
[OK]  OpenSSL ...   [OK]  libxml2 ...   [OK]  XSDs ...
[INFO]  Broker embutido em 127.0.0.1:5672 (duravel em ...\broker)
[INFO]  Fila "documentos" ligada a exchange "dfe" (1 padrao(oes))
[INFO]  Fila "eventos" ligada a exchange "dfe" (1 padrao(oes))
[AVISO] [matriz] TRANSPORTE SIMULADO: as consultas vao para http://127.0.0.1:9200, NAO para a SEFAZ
[INFO]  Em execucao. Ctrl+C ou SIGTERM para parar.
```

**O que mostrar:** o host verifica o ambiente **antes** de subir e recusa rodar pela metade; e avisa em
letras grandes que o transporte é simulado. (Se `Ambiente=producao` junto com `SimuladorURL`, ele
**se recusa a subir** — proteção para os documentos reais nunca chegarem.)

Ele já fez a primeira consulta: o simulador não tinha nada (`137`) e **abriu um bloqueio de 1 hora**, como a SEFAZ faria.

### 4.4 Passo 3 — um consumidor qualquer

```
python exemplos/consumidor/python/consumir.py --padrao "nfe.#"
```

Ele declara uma fila própria ligada a `nfe.#` e fica esperando. Este é **todo** o código que um consumidor
precisa (~120 linhas, boa parte comentário e formatação; sem nada de fiscal): é a prova de que o consumo é agnóstico de linguagem.

### 4.5 Passo 4 — chegam documentos (e o "656 sem esperar uma hora")

Em um terceiro terminal, publique dois resumos de NF-e e um evento de cancelamento **no simulador**
(Git Bash / Linux; em PowerShell use `curl.exe` ou `Invoke-RestMethod -Method Post -ContentType application/json -Body '{...}'`):

```bash
curl -s -X POST 127.0.0.1:9200/admin/documentos -H 'Content-Type: application/json' \
     -d '{"cnpj":"11222333000181","uf":"RS","tipo":"resNFe","quantidade":2}'
curl -s -X POST 127.0.0.1:9200/admin/documentos -H 'Content-Type: application/json' \
     -d '{"cnpj":"11222333000181","uf":"RS","tipo":"resEvento","tpEvento":"110111"}'
```

Nada aparece ainda — e o log do broker mostra o motivo:

```
[AVISO] [matriz] Consumo indevido (cStat=656); proxima tentativa em 10s
```

O broker tentou consultar dentro da hora de bloqueio e levou **656**. Isso é o comportamento real da SEFAZ,
reproduzido sob demanda. Em vez de esperar uma hora, avance o **relógio virtual** do simulador:

```bash
curl -s -X POST 127.0.0.1:9200/admin/relogio/avancar -H 'Content-Type: application/json' \
     -d '{"horas":1,"minutos":1}'
```

Em poucos segundos o consumidor imprime:

```
novo      nfe.documento.rs.11222333000181  cnpj=11222333000181 uf=rs
          resNFe  chave=35260998765432000110550010000000011000079198
          xNome=EMITENTE SINTETICO LTDA, dhEmi=2026-09-10T14:30:05-03:00, vNF=150.00, nProt=143260000000001
novo      nfe.documento.rs.11222333000181  ...  chave=...0021000158389
novo      nfe.evento.cancelamento.rs.11222333000181  cnpj=11222333000181 uf=rs
          resEvento  chave=35260998765432000110550010000000031000237570
          tpEvento=110111, xEvento=Evento sintetico, nProt=891260000000001
```

**O que mostrar:** a routing-key carrega tipo, categoria, UF e CNPJ — quem só quer cancelamentos assina
`nfe.evento.cancelamento.#`. Veja também o cursor gravado (`exemplos/demo-simulador/cursores.dat`):

```
nfe/11222333000181/rs/homologacao=3
```

Note o sufixo `homologacao`: os NSUs dos dois ambientes são separados, e o cursor os distingue sozinho.

### 4.6 Passo 5 — "e se ninguém estiver ouvindo?" (fila nomeada + queda)

Pare o consumidor. Publique mais documentos e avance o relógio de novo (repita o passo 4). O broker
continua recebendo. Agora **mate o broker à força** (finalize o processo: `Stop-Process -Name DFeBrokerConsole -Force` no PowerShell, ou `kill -9` no Linux — não um Ctrl+C, que é a parada limpa) e religue
o Passo 2. Consuma da **fila nomeada**:

```
python exemplos/consumidor/python/consumir.py --fila documentos
```

Os documentos estão lá. Isso foi ensaiado: três mensagens acumuladas sem consumidor, broker morto com
`Stop-Process -Force`, religado — as três chegaram intactas.

**O que mostrar:** a diferença entre os dois modos de consumo.

| | Fila **própria** (`--padrao`) | Fila **nomeada** (`--fila`) |
|---|---|---|
| Quem declara | o consumidor | o `dfe.ini` (`[fila:documentos]`) |
| Guarda enquanto o consumidor está fora? | **Não** — some ao sair | **Sim**, durável (WAL em `DataDir`) |
| Vários consumidores | cada um recebe uma **cópia** | dividem o trabalho |
| Use quando | ferramenta de análise, debug | integração de verdade com o ERP |

E o motivo de existirem filas declaradas pelo host: **sem fila ligada, o broker descarta** (é pub/sub) e o
cursor já teria avançado. Por isso o `dfe.ini` de produção sempre deve ter ao menos uma `[fila:*]`.

### 4.7 Passo 6 — manifestação do destinatário (ato fiscal, por mensagem)

Pegue a chave de um documento recebido e mande um comando pela fila (o script monta `chave=valor` e publica
em `comando.manifestacao`):

```
python exemplos/consumidor/python/manifestar.py --alias matriz --tipo ciencia \
       --chave 35260998765432000110550010000000011000079198
```

No próximo tick (até 60 s; 2 s nesta demo) o consumidor recebe o **resultado como um evento normal**:

```
novo      nfe.evento.ciencia.rs.11222333000181  cnpj=11222333000181 uf=rs
          procEventoNFe  chave=...  tpEvento=210210, xEvento=ciencia da operacao, nProt=891000000000001
```

**O que mostrar (e por quê):**

- O comando é **validado antes** de ir à SEFAZ (chave de 44 dígitos, tipo conhecido, justificativa de 15 a 255 caracteres onde exigida). Lixo é descartado e vai ao log.
- Foi **assinado com o certificado** do alias e o evento validado contra os XSDs oficiais — por isso a libxml2 é obrigatória.
- Se a SEFAZ rejeitar (duplicidade, autor ≠ destinatário…), o resultado sai em `nfe.evento.manifestacaorejeitada.<uf>.<cnpj>` com o `cStat`/`xMotivo` — quem assina `evento.ciencia` nunca recebe uma ciência que não foi registrada.
- Não há RPC/`reply-to`: o resultado volta pela mesma exchange, porque quem mandou o comando já está ouvindo.
- **Automática**: `ManifestacaoAutomatica=true` num certificado faz o broker dar ciência sozinho a cada documento. Padrão `false`; é um ato fiscal.

### 4.8 Extras (cada um leva ~1 minuto)

| Quero mostrar… | Faça |
|---|---|
| **Paginação** (lotes de 50) | `DFeSimulador --cenario simulador/cenarios/paginacao.ini` (120 documentos: 50, 50 e 20). |
| **Resiliência a falhas** | `--cenario simulador/cenarios/instavel.ini` (108, timeout, 500 e 656 nas primeiras consultas) e veja o log do broker seguindo em frente. |
| **Falha sob demanda** | `curl -X POST 127.0.0.1:9200/admin/falhas -d '{"falha":"timeout","quantidade":2}'` (nomes em [`simulador/LEIAME.md`](../simulador/LEIAME.md)). |
| **Estado do "SEFAZ"** | `curl 127.0.0.1:9200/admin/estado` — contas, NSU atual, bloqueio, contadores. |
| **Conferência do formato** | `curl 127.0.0.1:9200/admin/violacoes` — `(nenhuma)` prova que o ACBr mandou exatamente o formato esperado. Com `--estrito` o simulador recusa (400) o que estiver fora. |
| **Sem instalar Pascal** | `docker build -f simulador/Dockerfile -t dfe-simulador .` e `python simulador/exemplos/python/roteiro.py` — o simulador serve quem nem usa este projeto. |
| **Regra própria em Pascal** | `simulador/exemplos/limite-consultas/` — limite de N consultas por CNPJ sem tocar no núcleo. |
| **Demo curtíssima, sem broker externo** | `tools/demo/DFeDemo --porta 5672 --intervalo 5`: publica NF-es sintéticas pelo caminho real (provider → routing-key → AMQP). |

### 4.9 Encerrar e limpar

Ctrl+C no broker e no simulador (o broker sai limpo com código 0). Para recomeçar do zero, apague de
`exemplos/demo-simulador/`: `cursores.dat`, `broker/` e `logs/` (estão no `.gitignore`).

---

## 5. Funcionalidades em detalhe

Legenda de evidência: **[demo]** = ensaiado por mim em 2026-09-20 neste guia; **[testes]** = coberto por
testes automatizados; **[não]** = não exercitado contra o mundo real.

### 5.1 Consulta à Distribuição de DFe (poller por certificado)

Uma *unidade de trabalho* por certificado/UF. Respeita o intervalo mínimo de 1 h **sem escalonar backoff** (a NT
não pede), trata 137/138/656/108/109, timeout e resposta ilegível **sem derrubar o processo** (cada unidade
roda isolada num `try/except`; uma com problema não afeta as outras). Um ciclo pode ter vários lotes (paginação).
**[demo] [testes]** — contra o simulador; **[não]** contra a SEFAZ.

*Por que importa:* a maior parte do trabalho de quem implementa isso na unha é justamente o que dá errado
(bloqueio por consumo indevido, cursor, lote parcial).

### 5.2 Cursor de NSU confiável

Arquivo texto `namespace=nsu` (`nfe/<cnpj>/<uf>[/homologacao]=<nsu>`), gravado em arquivo temporário e trocado
de forma **atômica** — um crash no meio nunca deixa arquivo pela metade. O cursor só avança **depois** que o
lote inteiro foi publicado e confirmado. **[demo] [testes]**

*Decisões que dá para contar:* SQLite e reuso do WAL do broker foram avaliados e rejeitados por desproporção
(o volume é de dezenas de linhas). Produção mantém a chave "de sempre"; só homologação ganha o sufixo, então não
houve migração.

### 5.3 Providers por tipo de documento

`IDFeProvider` é o contrato; `DFe.Provider.NFe` é o único implementado. Decodifica `resNFe`, `procNFe`,
`resEvento`, `procEventoNFe` e monta a routing-key. Auto-registra-se por `initialization` — **o core não conhece
CTe/MDFe**: um contribuidor adiciona uma unit e um `uses`. Schema desconhecido é ignorado (um schema novo da SEFAZ não
pode travar o cursor). Tipos de evento sem nome mapeado saem com o **código numérico**. **[testes]**
Como contribuir: [`CONTRIBUTING.md`](../CONTRIBUTING.md).

### 5.4 Broker AMQP embutido ou externo

Broker AMQP 0-9-1 dentro do processo (do `pascal-amqp-faa`, mesmo autor, MIT). `Modo=externo` aponta para um
RabbitMQ existente. **Durável por padrão** (`DataDir=broker`): o cursor já avançou quando a mensagem entra na
fila, então fila transiente perderia documento num restart. Escuta só em `127.0.0.1` com `guest/guest` —
**ao abrir para a rede, troque a senha**. **[demo] [testes]**

### 5.5 Publicação com garantia (pelo menos uma vez)

*Publisher confirms*, síncronos: só retorna depois que o broker confirmou. Qualquer falha impede o avanço do
cursor. Consequência: um documento **pode chegar duas vezes** — o consumidor deduplica pela chave de acesso
(o `consumir.py` mostra `REPETIDO`). Conexão sob demanda, refeita após falha. **[testes]**

### 5.6 Manifestação do destinatário

Ver 4.7. Manual (comando por fila) e automática (por alias). Rejeição vira evento `manifestacaorejeitada`.
`cOrgao=91` (Ambiente Nacional) e `CNPJ` do destinatário são fixados porque os defaults do ACBr estariam
errados. Não há `xJust` fora de *operação não realizada* (NT 2012/002). **[demo] [testes]**; **[não]** enviada à SEFAZ real.

### 5.7 Vários certificados, troca sem parar, recarga a quente

Um `[certificado:<alias>]` por CNPJ/UF; **dois certificados do mesmo CNPJ** (troca antes do vencimento)
compartilham o cursor, mas **nunca** podem estar `Ativo=true` juntos — a config é recusada. Editar o
`dfe.ini` com o serviço rodando é detectado no próximo tick: alias novo entra, `Ativo` é sincronizado, removido é
pausado, e **config com erro não derruba nada** (a anterior continua valendo, o erro vai ao log).
A config do **broker** e o **ambiente** de um alias em execução não são recarregados — exigem reiniciar. **[testes]**
*(Sugestão para ensaiar: com a demo no ar, mude `Ativo=false` e observe o log.)*

### 5.8 Três formas de rodar

| Host | Plataforma | Notas |
|---|---|---|
| `DFeBrokerConsole` | Windows e Linux, Delphi e FPC | No Linux **é** o host de produção, sob systemd (`hosts/console/systemd/`). Sai com código 0 em Ctrl+C/SIGTERM. |
| `DFeBrokerServico` | Windows, Delphi | Serviço Windows: log diário com retenção, falha de subida no Event Log, `sc failure` para reinício automático ([`hosts/servico/LEIAME.md`](../hosts/servico/LEIAME.md)). |
| `DFeDemo` | FPC | Só demonstração. |

Todos são *finos*: a lógica está em `TDFeAplicacao`, que **não linka ACBr** — por isso a aplicação inteira roda contra o simulador em teste.
**[demo]** console; **[testes]** + verificação manual do serviço; **[não]** systemd em máquina real (só em contêiner).

### 5.9 Falhar alto, cedo e com mensagem clara

Na subida: config inválida, provider desconhecido, porta ocupada, broker externo inalcançável e ambiente
incompleto (falta OpenSSL/libxml2/XSDs) terminam com código ≠ 0 — nunca "rodando pela metade".
`--verificar-ambiente` só confere e sai. **[demo]**

### 5.10 Simulador da SEFAZ (produto à parte)

Servidor HTTP que fala o SOAP da Distribuição e da Recepção de Evento. Cenário por arquivo INI, **API admin**
(documentos, falhas, NSU pulado, relógio virtual, violações, último envelope), modo estrito, extensão em Pascal
por regras, imagem Docker e roteiro em Python. Existe porque a SEFAZ exige certificado até em homologação — sem
o simulador, nada do resto seria testável. **[demo] [testes]** — inclusive o **client ACBr real** contra ele.
*Limite honesto:* a fidelidade é a **nossa leitura das NTs**; se ela estiver errada, o simulador repete o erro.

### 5.11 Qualidade e portabilidade

Dual-compiler desde o início (Delphi e FPC), com suítes espelhadas em DUnitX e FPCUnit; CI no GitHub Actions
(Linux) roda a suíte pura, a integração ACBr×simulador, o AMQP, o host com SIGTERM e o systemd. O Delphi só roda
pela IDE. Números atuais no [`CLAUDE.md`](../CLAUDE.md) (rodar de novo antes de citá-los: mudam a cada fase).
Lições reais estão registradas ali — p.ex. o ACBr **engolir** erro de `docZip` e devolver lote truncado
(o cursor pularia documentos), o que originou a conferência `ConferirLoteCompleto`.

---

## 6. Roteiro de apresentação e perguntas difíceis

### 6.1 Sequência sugerida (≈15 min)

| Min | O quê |
|---|---|
| 0–2 | Problema e proposta (seção 1). Mostre o diagrama da seção 3. |
| 2–4 | O contrato: exchange `dfe`, routing-key, corpo XML. Um slide, sem código. |
| 4–12 | **Demo ao vivo**: passos 1 a 5 (simulador → broker → consumidor → 656 → relógio → documentos). Termine matando o broker e mostrando a fila durável. |
| 12–14 | Manifestação (passo 6) e o resultado voltando como evento. |
| 14–15 | O que **não** está provado (seção 7) e como ajudar. |

**Dicas de palco:** deixe os 4 terminais abertos e ensaiados; tenha o passo 4 em um arquivo `.sh`/`.ps1` para não digitar
JSON diante da plateia; se a porta 5672 estiver ocupada, descubra **antes**; e não improvise com certificado
de empresa — o aviso do README existe por um motivo.

### 6.2 Perguntas que vão aparecer

**"Funciona com a SEFAZ de verdade?"** — Honestamente: nunca foi executado contra a SEFAZ real; o autor
não tem certificado ICP-Brasil. Funciona de ponta a ponta com o **componente ACBr real** contra um simulador
baseado nas NTs. O convite é: teste em **homologação** e conte o que encontrou (issue #1).

**"Por que não RabbitMQ?"** — Pode usar (`Modo=externo`). O embutido existe para "baixar e rodar" sem
operar mais um serviço; fala AMQP 0-9-1 padrão, então é reversível.

**"Posso perder documento?"** — O cursor só avança depois da confirmação do broker, com escrita atômica, e a fila é
durável. O preço é a entrega *pelo menos uma vez*: pode repetir, e a chave de acesso deduplica. Um comando de
manifestação aceito (ack) e o host cair antes de processar é perdido — basta reenviar; a SEFAZ devolve 573 (duplicidade).

**"E se o meu ERP já consulta a SEFAZ?"** — **Este é o risco real.** Aplicações diferentes consultando o mesmo
CNPJ devem seguir a mesma sequência de NSU; senão é uso indevido (656) e o **CNPJ inteiro** fica bloqueado por 1 h
para todos (NT 2014.002, seção 3.11.4). Combine antes; em dúvida, homologação ou um CNPJ que ninguém consulta.

**"Por que ACBr?"** — Já resolve certificado, SOAP, assinatura e parsing, e é o padrão de fato no Delphi/Lazarus
brasileiro. Começou como ACBrLib e foi revertido para os componentes clássicos: o binário oficial da ACBrLib exige assinatura
paga. Preço aceito: dependência maior, e a maturidade em FPC/Lazarus é menor.

**"Só NFe?"** — Na v1, sim. O contrato de provider e o `CONTRIBUTING.md` existem *antes* de haver outro provider
justamente para que CTe/MDFe entrem por contribuição.

**"Escala?"** — O gargalo é a SEFAZ (uma consulta por hora por CNPJ), não o broker. Volume por certificado é de
dezenas a milhares de mensagens por dia — irrisório para o broker.

**"Segurança?"** — Senha do `.pfx` por `SenhaEnv` (variável de ambiente), nunca no arquivo; o broker escuta em
`127.0.0.1` por padrão; a API admin do simulador **não tem autenticação** (é ferramenta de teste — no Docker,
publique a porta só em `127.0.0.1:`).

**"Licença?"** — MIT aqui; o ACBr é LGPLv3 e a integração preserva a separação (não incorporamos código ACBr sob MIT).

---

## 7. O que NÃO está provado

Diga isto antes que perguntem:

- **Nunca rodou contra a SEFAZ real** (nem homologação): sem certificado. Tudo do lado SEFAZ foi verificado lendo as NTs e o fonte do ACBr.
- A aceitação pela SEFAZ real do `xJust` com acento e da manifestação enviada não foi verificada.
- **Delphi** não roda no CI (só pela IDE, e pelo usuário); o Delphi Win64 do simulador e caminhos de erro do `THTTPClient` não foram cobertos.
- systemd: verificado em **contêiner**, não em máquina real. ARM: não testado. Delphi para Linux: não testado.
- A parada do Serviço Windows **com um tick em andamento** (espera de até 60 s) não foi exercitada.
- Só a NFe. Só **Distribuição** e **manifestação** — o simulador não cobre emissão, cancelamento etc.
- Fora do Python, os consumidores não foram testados (mas AMQP 0-9-1 é padrão).

---

## 8. Onde está cada coisa no código

Ordem de leitura sugerida para **aprender** o projeto (do contrato para a implementação):

1. `src/DFe.Types.pas`, `DFe.Provider.pas`, `DFe.Errors.pas`, `DFe.Publicador.pas` — as **interfaces**: o vocabulário do projeto.
2. `src/DFe.RoutingKey.pas` — a convenção pública (curta e cheia de decisões).
3. `src/DFe.Orquestrador.pas` — o coração: ciclo, intervalo, cursor, isolamento de falha.
4. `src/DFe.CursorStore.Arquivo.pas` — persistência atômica.
5. `src/DFe.Provider.NFe.pas` — decodificação do lote em documento/evento.
6. `src/DFe.Client.ACBrNFe.pas` — **única** peça que fala com o ACBr (consulta, `EnviarEvento`, conferência do lote).
7. `src/DFe.Publicador.AMQP.pas` e `DFe.ComandoFonte.AMQP.pas` — os dois lados do broker.
8. `src/DFe.Manifestacao.pas` — comando → SEFAZ → resultado como evento.
9. `src/DFe.Config.pas`, `DFe.Host.Aplicacao.pas`, `DFe.Host.Loop.pas` — como tudo é montado a partir do INI e o *tick*.
10. `hosts/console/DFeBrokerConsole.dpr`, `hosts/servico/` — os hosts (finos de propósito).
11. `src/DFe.Simulador*.pas` e `simulador/` — o simulador; note que **nenhuma unit de produção depende dele**.

Documentos: [`architecture.md`](architecture.md) (o "porquê" de cada decisão), [`../CLAUDE.md`](../CLAUDE.md) (decisões travadas e
armadilhas encontradas, em ordem), [`dependencias-runtime.md`](dependencias-runtime.md), [`simulador-standalone.md`](simulador-standalone.md),
[`acbr-achados.md`](acbr-achados.md), [`referencias/`](referencias/README.md) (as NTs oficiais — fonte de verdade para qualquer regra de protocolo).

**Exercícios para fixar** (cada um responde a "entendi de verdade?"):

1. Provoque um 656 e desfaça-o **sem** o relógio virtual: qual `IntervaloBaseSegundos` seria preciso, e por que em produção não se pode baixá-lo?
2. Ligue `ManifestacaoAutomatica=true` no alias, publique um `resNFe` e observe o evento `ciencia` aparecer **sem** enviar comando.
3. Publique um `procEventoNFe` com `tpEvento` `110150` e veja a routing-key sair com o código numérico. Por que promover isso a nome é uma mudança incompatível?
4. Configure um segundo alias de **outro** CNPJ e veja duas unidades correndo; depois configure dois `Ativo=true` no **mesmo** CNPJ/UF e leia a recusa.
5. Escreva uma regra do simulador (copie `limite-consultas`) que responda 108 nas quintas-feiras.
