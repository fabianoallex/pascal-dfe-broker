# Simulador da SEFAZ como aplicação separada — plano

> Estado: **proposta (2026-09-20). Nenhuma linha de código de produto escrita**; só o spike do Horse (`simulador/spike-horse/`) foi feito e está confirmado em FPC/Linux, FPC/Windows (com contorno) e Delphi Win32. Este documento existe para uma sessão futura retomar sem depender da conversa em que o plano nasceu. Complementa `docs/simulador-sefaz.md` (que descreve o simulador **em processo**, fases 0–4, todas feitas).

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

- **Um broker apontado para o simulador nunca conversa com a SEFAZ** — em produção isso seria silencioso e perigoso (documentos não chegam). Portanto: `SimuladorURL` **recusado** quando o ambiente do certificado é `producao`, a menos de um `SimuladorPermitirProducao=true` explícito; log de **AVISO em toda subida** e a cada ciclo dizendo que o transporte é simulado.
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

1. `TDFeTransmissorHttp` (broker; `IDFeTransmissor` sobre um cliente HTTP dual: `fphttpclient` no FPC, `System.Net.HttpClient` no Delphi, atrás de IFDEF; **bytes/encoding** conforme o achado do spike: FPC entrega bytes UTF-8, Delphi `UnicodeString`, ver `DFe.XmlTexto`).
2. Opção `[dfe] SimuladorURL=` em `DFe.Host.ACBr` + as salvaguardas.
3. `simulador/`: executável `DFeSimulador` (Horse) com o handler puro chamando `TDFeSimuladorTransmissor`; trava (lock) em volta do núcleo, que não é thread-safe; cenário mínimo por arquivo.
4. **Pronto quando:** testes automáticos (não à mão) em que o **client ACBr real** consulta o simulador por HTTP e o resultado é idêntico ao do simulador em processo (mesmos casos de `tests/Integration/AcbrSim`), rodando FPC Linux/Docker e Windows; e o `DFeBrokerConsole` sobe, consulta o simulador e publica na fila (teste de aplicação com dois processos).

### Fase B — controle e reprodutibilidade

API admin completa, **relógio virtual**, violações consultáveis, estado, modo leniente/estrito.
**Pronto quando:** o 656 é reproduzido por HTTP em segundos (avanço do relógio), e as violações do ACBr aparecem em `/admin/violacoes`.

### Fase C — extensão

Registro de regras (`initialization`), rotas próprias, um exemplo completo em `simulador/exemplos/`.
**Pronto quando:** o exemplo (uma regra que o core não tem) compila **sem alterar o core**, e há teste que a exercita.

### Fase D — distribuição

Imagem Docker (binário Linux estático do FPC), README para quem não usa Pascal (curl/Python contra a API admin), exemplos de cenário, HTTPS opcional se houver demanda, entrada no CI.
**Pronto quando:** `docker run` + um script Python (pika/requests) reproduzem o roteiro do README sem instalar Pascal.

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
