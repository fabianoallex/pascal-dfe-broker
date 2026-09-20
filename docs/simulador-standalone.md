# Simulador da SEFAZ como aplicação separada — plano

> Estado (2026-09-20): **Fases A, B e C feitas** (ver cada uma abaixo; a C também confirmada no Delphi Win32); D pendente. O texto original ("proposta, nenhuma linha escrita") ficou abaixo por histórico. Este documento existe para uma sessão futura retomar sem depender da conversa em que o plano nasceu. Complementa `docs/simulador-sefaz.md` (que descreve o simulador **em processo**, fases 0–4, todas feitas).

## Objetivo

Hoje o simulador vive dentro do processo de teste: o `TDFeSimuladorTransmissor` é injetado no client ACBr (`IDFeTransmissor`) e responde no lugar do HTTP. Queremos também uma **aplicação própria**, que suba sozinha, escute HTTP e responda como a Distribuição de DFe / RecepcaoEvento da SEFAZ, para que:

1. o **`DFeBrokerConsole` / serviço** rode contra ela, em outro processo (ou outra máquina, ou contêiner), sem certificado real nem SEFAZ;
2. **quem usa a lib** possa **estendê-la** com cenários e regras próprios, para os próprios testes e simulações;
3. **projetos de terceiros**, inclusive fora do Pascal, possam usá-la como mock de SEFAZ (hoje só a Distribuição de DFe da NFe existe, ver "Limites").

**Não é objetivo:** substituir a SEFAZ de homologação; emular autorização/cancelamento/inutilização de NFe; validar XML contra XSD; TLS mútuo (Fase 5 opcional do plano original).

## O que já temos e serve como está

| Peça | Papel |
|---|---|
| `DFe.Simulador` | Núcleo: NSU por CNPJ/UF, janela de 1h, 137/138/656/108/109, falhas roteirizáveis, manifestação (135/136/573/575/594/655…), relógio injetável (`TDFeAgoraFunc`). Puro, dual-compiler. |
| `DFe.Simulador.Soap` | Recebe o envelope, **afirma sobre o request**, devolve o envelope de resposta. A URL vem no parâmetro `AURL` e o adaptador já a identifica por `NFeDistribuicaoDFe` / `NFeRecepcaoEvento4`. |
| `DFe.Simulador.Fixtures` / `.Codec` | Geram `resNFe`/`procNFe`/`resEvento`/`procEventoNFe` e o `docZip` (gzip+base64). |
| `IDFeTransmissor` (`DFe.Transmissor`) | Costura no client ACBr: recebe o envelope pronto, devolve texto + `HTTPResultCode` + `InternalErrorCode`. **É por aqui que o broker fala com um simulador remoto, sem tocar no ACBr.** |
| Certificados sintéticos (`tests/Integration/AcbrSim/cert-teste/`) | Permitem ao broker subir com um `.pfx` de teste. |
| Docker + CI Linux | Base para a imagem de distribuição. |
| Horse (`vendor/horse`, spike) | Casca HTTP dual-compiler. |

## Arquitetura proposta

```
 ┌──────────────────────── processo do broker ────────────────────────┐
 │ TDFeAplicacao → client ACBr real → IDFeTransmissor                 │
 │                                    └─ TDFeTransmissorHttp (NOVO) ──┼──► HTTP POST
 └────────────────────────────────────────────────────────────────────┘        │
                                                                                ▼
 ┌──────────────────────── processo do simulador (NOVO) ──────────────────────────────┐
 │ Horse (rotas)                                                                        │
 │   POST <caminho da URL real>  ──► TDFeSimuladorTransmissor ──► TDFeSimuladorSefaz    │
 │   /admin/...                  ──► controle (relógio, cenários, violações, estado)    │
 │ extensões registradas (Pascal)  ·  cenários carregados de arquivo                    │
 └──────────────────────────────────────────────────────────────────────────────────────┘
```

Duas decisões que mantêm isso simples:

- **O broker não sabe que fala com um simulador.** Ele ganha só uma opção de config que troca o transmissor (`[dfe] SimuladorURL=http://127.0.0.1:9200`). O ACBr continua montando o envelope com a **URL oficial** da SEFAZ, e o `TDFeTransmissorHttp` a reaproveita como *caminho* sob a base do simulador. Assim o simulador roteia por caminho e o adaptador SOAP existente funciona sem mudança.
- **O handler é uma função pura `(caminho, corpo, cabeçalhos) → (status, corpo)`**, testável sem rede; o Horse é só a casca. Se um dia o Horse não servir, troca-se a casca.

### Regras de dependência (para poder extrair depois)

1. Tudo novo do simulador vive em **`simulador/`** (fontes, testes, docs, README próprio). As units `DFe.Simulador*` existentes migram para lá quando o pacote próprio (`.lpk`) existir; `DFe.Simulador.Client` (o único acoplado ao broker) pode ficar do lado do broker.
2. O simulador **só** pode depender de `DFe.Types` (`TDFeLoteBruto`), `DFe.Transmissor` e `DFe.XmlTexto`. **Nunca** de orquestrador, config, ACBr, AMQP ou hosts.
3. O código de **produção** do broker **nunca** depende do simulador (só testes e o transmissor HTTP, que depende só de `DFe.Transmissor`).
4. Um check no CI (grep nas `uses`) garante 2 e 3.
5. Extrair = `git filter-repo` da pasta; o contrato compartilhado são as três units do item 2 (o repositório novo as consome como submódulo do broker, ou elas viram um pacote comum minúsculo — decidir na hora).

## Contrato HTTP

**Rotas SOAP** — as mesmas do serviço real, pelo caminho da URL que o ACBr usa (o simulador casa por trecho, como o adaptador já faz): Distribuição de DFe (`…/NFeDistribuicaoDFe…`) e RecepcaoEvento (`…/NFeRecepcaoEvento4…`). O corpo é o envelope SOAP; a resposta também.

**API admin** (JSON, `/admin/…`; escuta só em `127.0.0.1` por padrão):

| Rota | Efeito |
|---|---|
| `POST /admin/documentos` | Publica documento numa conta (CNPJ/UF): `PublicarDocumento` (com fixture pronta ou XML fornecido). |
| `POST /admin/pular-nsu` | `PularNSU`. |
| `POST /admin/falhas` | `EnfileirarFalha` (108/109/656/timeout/500/corpo ilegível/docZip corrompido/evento rejeitado). |
| `POST /admin/relogio/avancar` · `GET /admin/relogio` | **Relógio virtual** (abaixo). |
| `GET /admin/violacoes` · `DELETE /admin/violacoes` | O que o adaptador SOAP registrou de divergente no request. |
| `GET /admin/estado` | Contas, NSU, bloqueios, eventos registrados, total de consultas. |
| `POST /admin/cenario` | Carrega um cenário (abaixo). |
| `POST /admin/zerar` | Volta ao estado inicial. |

Corpos deliberadamente **planos** (objeto de campos simples), para não depender de `System.JSON` × `fpjson` — leitura/escrita própria pequena, ou IFDEF pontual (decisão em aberto 3).

### Relógio virtual

O núcleo já recebe `TDFeAgoraFunc`. No processo separado o relógio é **real + deslocamento** ajustável por `/admin/relogio/avancar`. Sem isso o 656 (bloqueio de 1h) só se reproduz esperando 1h. O broker também tem seu relógio (o cadenciamento por `IntervaloBaseSegundos`); para um teste ponta a ponta reproduzível, ou se avança os dois, ou se configura o intervalo do broker pequeno — a documentar na fase B.

## Cenários e extensão

Dois níveis, para não prender o projeto ao Pascal:

1. **Cenário declarativo (arquivo, qualquer linguagem).** INI (mesma filosofia de `DFe.Config`), lido na subida ou por `POST /admin/cenario`: contas, documentos a publicar (fixture por parâmetro: schema, emitente, número, acento…), falhas na ordem, saltos de NSU. É o que atende quem só quer "ter 3 NFes e depois um 656".
2. **Extensão em Pascal (registro por `initialization`, decisão 10).** Uma unit do usuário registra uma **regra** — classe com ganchos (`AntesDeConsultar`, `AoReceberEvento`, `AoResponder`…) que pode alterar a resposta ou injetar falha — sem tocar no core; o usuário compila o próprio executável do simulador com a unit dele. Também pode registrar **rotas Horse próprias** (o modelo de extensão natural do Horse).
3. *(depois, só se houver demanda)* **webhook**: a regra chama uma URL do usuário, o que abre a extensão a outras linguagens.

O contrato dos ganchos só se fixa depois da Fase B, com uso real; antes disso é interface interna.

## Salvaguardas

- **Um broker apontado para o simulador nunca conversa com a SEFAZ** — em produção isso seria silencioso e perigoso (documentos não chegam). Portanto: `SimuladorURL` **recusado** quando o ambiente do certificado é `producao`, a menos de um `SimuladorPermitirProducao=true` explícito; **AVISO** no log a cada client criado (subida e recarga a quente) dizendo que o transporte é simulado. *(Implementado assim; "a cada ciclo" seria ruído.)*
- O simulador escuta em `127.0.0.1` por padrão; qualquer outro *bind* é opção explícita (e sem autenticação na v1 — documentar).
- O README do simulador declara, no topo, o mesmo que o do broker: **codifica a nossa leitura das NTs**, não é a SEFAZ.

## Limites (para o público fora do Pascal)

- **Escopo**: só a Distribuição de DFe e a manifestação da **NFe**. Consulta por NSU/chave, CT-e/MDF-e, status de serviço, autorização e o resto que um ERP consulta **não** existem.
- **Fidelidade**: risco de espelho (ver `simulador-sefaz.md`, item 7 das pendências). cStat 494/573/999 vêm de memória do Manual de Orientação; a rejeição por consumo indevido não reinicia o bloqueio; prazos 596/650/651 não modelados.
- **Modo do request**: hoje o adaptador registra "violação" para qualquer divergência do que o ACBr envia (útil para o nosso client). Para terceiros o padrão deve ser **leniente** (aceitar e registrar), com modo estrito opcional.
- **TLS**: um cliente de terceiros só usa o simulador se a biblioteca dele permitir trocar a URL e falar HTTP (ou aceitar certificado de teste). Um modo HTTPS opcional entra na Fase D se houver demanda.
- **Estado em memória**, sem persistência, na v1.

## Fases

Cada fase termina com **testes verdes** e o critério abaixo; nada de "pronto" sem rodar (FPC/Linux via Docker; Delphi pela IDE, colado por você).

### Fase A — o simulador roda separado e o broker fala com ele

> **Fase B concluída em 2026-09-20 no FPC (Windows/Linux); falta o Delphi** (ver CLAUDE.md). API admin, relógio virtual e modo leniente/estrito prontos; o JSON plano é próprio (decisão em aberto 3 resolvida). Nota: `GET /admin/violacoes` e `/admin/ultimo-envelope` devolvem texto, não JSON, para ler num `curl`. **Fase A concluída em 2026-09-20 (FPC Windows/Linux e Delphi; ver CLAUDE.md para o que ficou sem cobertura no Delphi).** Resumo abaixo do que foi feito. **Andamento:** item 1 feito no FPC (`DFe.Transmissor.Http`, `DFe.Transmissor.Http.Cliente`, `TextoParaAcbr`; suíte pura 270/270 e Linux verdes, cliente exercitado por HTTP real contra o servidor do spike). Item 2 também feito (`[dfe] SimuladorURL`/`SimuladorPermitirProducao` + `DecidirUsoDoSimulador`; salvaguarda verificada no executável do host console). Falta confirmar os dois no Delphi. **Item 3 feito:** `DFeSimulador` (Horse) + `DFe.Simulador.Servidor`/`Cenario` (puras, em `src/` junto das demais `DFe.Simulador*` até a migração para `simulador/`), `simulador/LEIAME.md`; integração `DFe.AcbrSimHttpTests` (10 testes, Windows e Linux verdes). Desvio do plano: o Horse roteia por caminho *exato* (as duas rotas SOAP), não por trecho — o servidor puro é que casa por trecho.

1. `TDFeTransmissorHttp` (broker; `IDFeTransmissor` sobre um cliente HTTP dual: `fphttpclient` no FPC, `System.Net.HttpClient` no Delphi, atrás de IFDEF; **bytes/encoding** conforme o achado do spike: FPC entrega bytes UTF-8, Delphi `UnicodeString`, ver `DFe.XmlTexto`).
2. Opção `[dfe] SimuladorURL=` em `DFe.Host.ACBr` + as salvaguardas.
3. `simulador/`: executável `DFeSimulador` (Horse) com o handler puro chamando `TDFeSimuladorTransmissor`; trava (lock) em volta do núcleo, que não é thread-safe; cenário mínimo por arquivo.
4. **Pronto quando:** testes automáticos (não à mão) em que o **client ACBr real** consulta o simulador por HTTP e o resultado é idêntico ao do simulador em processo (mesmos casos de `tests/Integration/AcbrSim`), rodando FPC Linux/Docker e Windows; e o `DFeBrokerConsole` sobe, consulta o simulador e publica na fila (teste de aplicação com dois processos).

### Fase B — controle e reprodutibilidade — **FEITA (2026-09-20, FPC)**

Implementada como descrito abaixo; detalhes e contrato final em `simulador/LEIAME.md` (rotas, corpos, o exemplo do 656 e o modo estrito). Texto do plano original:

API admin completa, **relógio virtual**, violações consultáveis, estado, modo leniente/estrito.
**Pronto quando:** o 656 é reproduzido por HTTP em segundos (avanço do relógio), e as violações do ACBr aparecem em `/admin/violacoes`.

### Fase C — extensão — **FEITA (2026-09-20, FPC Windows e Linux; Delphi Win32 verificado)**

Registro de regras (`initialization`), rotas próprias, um exemplo completo em `simulador/exemplos/`.
**Pronto quando:** o exemplo (uma regra que o core não tem) compila **sem alterar o core**, e há teste que a exercita.

Implementada: `src/DFe.Simulador.Regras.pas` (a classe `TDFeSimuladorRegra`, o registro de **classes** e as
ajudas), ganchos em `DFe.Simulador.Servidor` (`AdicionarRegra`/`AdicionarRegrasRegistradas`, `/ext/*`,
`/admin/regras`) e o exemplo `simulador/exemplos/limite-consultas/` (limite de consultas por CNPJ numa janela,
que responde 656 **sem tocar no núcleo**; usa o relógio virtual, estado próprio, rota própria e `AoZerar`).
Contrato completo no `LEIAME.md` do exemplo. Decisões tomadas (o plano dizia "só se fixa depois da Fase B, com
uso real"; foi fixado enxuto, e pode crescer):

- **Regra = classe, registro guarda classes** (não objetos): cada servidor instancia a sua, então o estado é
  por servidor e os testes ficam isolados. `Nome` é `class function` para o registro recusar duplicata sem
  instanciar. O registro **não** instala nada sozinho: `AdicionarRegrasRegistradas` (chamado por
  `DFe.Simulador.Principal`) é que o faz — assim um teste que monta um servidor não herda as regras que outras
  units da suíte registraram.
- **Quatro ganchos**: `AntesDeAtender` (curto-circuito; só as duas rotas SOAP), `DepoisDeAtender` (só se
  ninguém respondeu antes), `TratarRota` (`/ext/*`), `AoZerar`. Todos **sob a trava** do servidor. A resposta
  de uma regra que curto-circuita é final: o `DepoisDeAtender` das outras não roda.
- **As regras não veem `/admin` nem `/ping`** (uma regra com defeito não tira o controle do ar).
- **Liga/desliga** por `POST /admin/regras`; o `zerar` não religa (é como o modo estrito: configuração, não
  estado de teste).
- **Rotas próprias só sob `/ext/`**: o Horse casa um segmento por curinga, então `/ext/*`, `/ext/*/*` e
  `/ext/*/*/*` (3 níveis). Rotas Horse fora daí, registradas pelo programa do usuário, não passam pelo servidor
  puro — servem em princípio, **não exercitado**.
- **Ficou de fora, de propósito**: webhook (extensão a outras linguagens) — só com demanda; ganchos sobre os
  eventos de manifestação além do `AntesDeAtender` genérico; regras carregadas de arquivo/DLL.
- Exceção num gancho propaga do servidor puro e a casca (Horse) a converte em **HTTP 500** com a mensagem.

Verificado: pura FPC **400/400** (+40: 26 do mecanismo, 14 do exemplo; 0 vazamento), integração
`AcbrSimTests` 61/61 (+1: o client ACBr real por HTTP contra o **executável do exemplo**, com a regra, a rota
`/ext/limite`, o relógio virtual e o liga/desliga), e por `curl` no `.exe` do Windows (rotas `/ext/*`, 656 da
regra, janela reaberta pelo relógio virtual, desligar). Delphi Win32 (usuário recompilou; eu rodei
os `.exe`): `DFe.UnitTests` **404/404** (0 vazamento) e o `DFeSimuladorLimite` do Delphi se comporta como o do FPC
por `curl`. O `.dproj` do exemplo precisou de `..\..` no caminho de busca. Não coberto no Delphi: a suíte HTTP
de integração contra o exemplo Delphi e o Win64.

### Fase D — distribuição — **FEITA (2026-09-20, exceto HTTPS)**

Imagem Docker (binário Linux estático do FPC), README para quem não usa Pascal (curl/Python contra a API admin), exemplos de cenário, HTTPS opcional se houver demanda, entrada no CI.
**Pronto quando:** `docker run` + um script Python (pika/requests) reproduzem o roteiro do README sem instalar Pascal.

Implementada: `simulador/Dockerfile` (build em contêiner Debian 12 + FPC 3.2.2, runtime `debian:bookworm-slim`, usuário
comum, `ENTRYPOINT` = o executável, `CMD` = `--bind 0.0.0.0 --porta 9200`; contexto = raiz do repo, com `.dockerignore`),
cenários `simulador/cenarios/` (`basico`, `paginacao`, `instavel`; vão em `/cenarios/`), o roteiro
`simulador/exemplos/python/roteiro.py` (**só biblioteca padrão**, sem pika/requests — decisão: menos dependência para quem só quer ver
funcionar; o pika continua nos exemplos do consumidor do broker) e `tools/docker/testar-simulador-docker.sh`, que também é o job
`testar-simulador-docker` do CI. Seção "Sem instalar Pascal" no `simulador/LEIAME.md`.
Desvios do plano: o binário **não é estático** (liga só a `libc`, e a imagem de runtime a tem); HTTPS **não** foi feito (sem demanda).
Verificado localmente (Docker no Windows): build, `docker run`, o roteiro inteiro contra o contêiner, os três cenários carregando
(o log confirma; **o comportamento de `paginacao` e `instavel` é exercitado só no roteiro por API, não pelos arquivos**), usuário não-root
e `docker stop` rápido. **O job do CI ainda não rodou** no GitHub.

## Decisões em aberto

1. **Contorno do Horse no FPC/Windows** (`Horse.FPC.inc`, `const` × `constref`): por ora só documentado (`simulador/spike-horse/LEIAME.md`); avaliar PR upstream depois. Enquanto isso o build Windows/FPC do simulador precisa do contorno (script que copia `src` com o ajuste) — resolver na Fase A.
2. **Repositório definitivo e nome**: fica aqui até maturar; nome próprio (sem "broker") na extração.
3. **JSON**: leitor/escritor plano próprio × `System.JSON`/`fpjson` com IFDEF.
4. **Delphi Win64** do Horse (spike só Win32) e **Linux/Delphi**: fora do escopo até haver demanda.
5. **Persistência de estado** e **autenticação da API admin**: fora da v1.

## Riscos

- **Dependência do Horse** (terceiro, e o caminho FPC é o menos usado): mitigado pelo handler puro e pelo spike; o contorno de Windows mostra que erro de build pode surgir a cada atualização — por isso o submódulo fica pinado.
- **Escopo escorregar** para "mock geral de SEFAZ": mitigado pela seção "Limites" e por só aceitar novos serviços com fixtures a partir das NTs (`docs/referencias/`).
- **Fidelidade vendida como certeza**: mitigado pelo aviso no topo do README e pelo modo gravação (planejado em `simulador-sefaz.md`).

## Para retomar numa sessão nova

1. Ler este arquivo, `docs/simulador-sefaz.md` (pendências), `simulador/spike-horse/LEIAME.md` e a entrada "Simulador standalone" em `CLAUDE.md`.
2. Confirmar o ponto de partida: suítes puras FPC/Delphi, `tests/Integration/AcbrSim`, e `sh simulador/spike-horse/testar-linux.sh`.
3. Começar pela **Fase A, item 1** (`TDFeTransmissorHttp`), com teste antes do executável.
