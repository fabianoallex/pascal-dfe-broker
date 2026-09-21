# Usage and presentation guide

This guide is for anyone who wants to **understand, reproduce, and present** DFe Broker. The commands in section 4 were run end to end on 2026-09-20 (Windows, FPC), and the output shown is real. Anything **not** verified is marked as such; that matters more during a presentation than any feature.

- [1. In one minute](#1-in-one-minute)
- [2. Essential vocabulary](#2-essential-vocabulary)
- [3. How the pieces fit together](#3-how-the-pieces-fit-together)
- [4. Hands-on walkthrough: see everything working without a certificate](#4-hands-on-walkthrough-see-everything-working-without-a-certificate)
- [5. Features in detail](#5-features-in-detail)
- [6. Presentation outline and tough questions](#6-presentation-outline-and-tough-questions)
- [7. What has NOT been proven](#7-what-has-not-been-proven)
- [8. Where things live in the code](#8-where-things-live-in-the-code)

---

## 1. In one minute

**The problem.** Every company receives electronic invoices (NF-e) issued against its Brazilian tax ID (CNPJ). The Brazilian State Treasury Departments (SEFAZ) provide the DFe Distribution service to deliver these documents, but a client must identify itself with a **digital certificate**, query **at most once per hour**, and maintain the correct **NSU cursor**. An incorrect cursor can mean lost documents or a block. Today, companies choose between paying for a SaaS product and reimplementing the whole flow in their ERP.

**The proposal.** An **open source, self-hosted** program: you run it with *your* certificate, it queries SEFAZ, maintains the cursor, and **publishes each document as a message to an AMQP queue**. Any system (Delphi, Python, Java, Node, and others) can consume messages with a standard AMQP client, without knowing anything about SEFAZ, certificates, or ACBr.

**Key points to highlight:**

1. **No extra infrastructure** — the AMQP broker is embedded in the same process, though you can point it at RabbitMQ.
2. **Decoupled consumers** — consumers need only AMQP and the routing-key contract. They have no dependency on Pascal.
3. **Documents are not lost** — the cursor is persisted atomically, queues are durable, and delivery is at least once.
4. **Testable without a certificate** — the project includes a SEFAZ simulator that can also serve other projects.
5. **Extensible** — CT-e and MDF-e can be added as providers without changing the core.
6. **Cross-platform** — Delphi and FPC; Windows (console or service) and Linux (systemd).

---

## 2. Essential vocabulary

| Term | Meaning |
|---|---|
| **DFe Distribution** | SEFAZ service that returns tax documents associated with a CNPJ (as issuer, recipient, carrier, and so on). DFe means electronic tax document. |
| **NSU** | Unique sequential number assigned by SEFAZ to each document or event **per CNPJ**. A query asks, “What came after NSU 40?” |
| **Cursor** | The last NSU already processed. It is the highest-risk state: corruption can cause documents to be lost or processed again. |
| **`cStat`** | SEFAZ response code. **137** = nothing new; **138** = documents are available; **656** = improper use (queried too soon, resulting in a one-hour block); **108/109** = service unavailable. |
| **resNFe / procNFe** | `resNFe` is an NF-e summary (access key, issuer, amount). `procNFe` is the **complete** XML. |
| **Event** | Something that happened to an NF-e, such as cancellation, a correction letter, or recipient acknowledgement (`resEvento` / `procEventoNFe`). |
| **Access key** | The 44 digits that identify an NF-e. It is used for deduplication. |
| **Recipient acknowledgement (manifestação do destinatário)** | A **fiscal act** by the recipient concerning an NF-e: awareness, confirmation, non-recognition, or operation not performed. |
| **Exchange / routing key / queue** | AMQP terms: a producer publishes to an *exchange* with a *routing key*; the exchange routes the message to queues whose binding patterns match. |
| **ACBr** | A set of Brazilian components (LGPL) that communicates with SEFAZ, reads the certificate, and signs XML. |
| **Homologation / production** | SEFAZ staging and production environments. Their NSUs are **separate**. |

---

## 3. How the pieces fit together

```
                                  ┌──────────────────────────── DFeBrokerConsole / Windows Service ─────────────────────────┐
  Real SEFAZ  ◄──HTTPS+cert──┐    │                                                                                          │
                             ├────┤  Orchestrator (one unit per certificate)                                                 │
  DFeSimulator ◄──HTTP───────┘    │    ├─ ACBr client ── queries (by NSU), signs events                                      │
  (for tests)                     │    ├─ NSU cursor (file, atomic writes)                                                   │
                                  │    └─ NFe provider ── decodes docZip → document/event + routing key                     │
                                  │                          │                                                                │
                                  │                          ▼ publisher confirms                                            │
                                  │  AMQP publisher ──► Embedded AMQP broker (topic exchange "dfe") ──► queues             │
                                  │                                        ▲                                                  │
                                  │  Command source ◄── queue "dfe.comandos" (routing key comando.manifestacao)              │
                                  └──────────────────────────────────────────────────────────────────────────────────────────┘
                                                                     │
                     consumers in any language (pika, amqplib, RabbitMQ.Client…) ◄─┘
```

**One cycle, in order:**

1. Every *tick* (60 seconds by default), the host checks for configuration changes (hot reload), runs due cycles, and processes manual commands.
2. For each certificate, once the configured interval has passed (one hour by default), the client asks SEFAZ for everything after NSU *n*.
3. The response contains a batch of compressed XML `docZip` entries. The provider decodes each item and builds its routing key.
4. The publisher sends each item to the broker and **waits for confirmation**. The cursor advances only after **the whole batch** is confirmed.
5. If anything fails partway through, the cursor does **not** advance; the batch is retried. Consumers therefore deduplicate by access key.

**The most important public convention** (decision 4; it cannot be changed by an isolated PR):

```
exchange:     dfe   (topic, durable)
routing key:  <type>.<category>.<state>.<cnpj>
examples:     nfe.documento.rs.11222333000181
              nfe.evento.cancelamento.rs.11222333000181
              nfe.evento.manifestacaorejeitada.rs.11222333000181
patterns:     nfe.#   nfe.evento.#   nfe.documento.sp.*   #.11222333000181
```

`<cnpj>` is the CNPJ of the **certificate that made the query**, not necessarily the issuer. The message body is persistent UTF-8 XML.

---

## 4. Hands-on walkthrough: see everything working without a certificate

This walkthrough uses **DFeSimulator** (a server that responds like SEFAZ) and a **test** certificate already in the repository. Nothing contacts real SEFAZ.

### 4.1 Prerequisites

- Clone the repository with its submodules (see the README): `vendor/pascal-amqp-faa`, `vendor/ACBr` (`tools/init-acbr-submodule.sh`), and `vendor/horse` (for the simulator).
- **OpenSSL 3 and libxml2** must be available (ACBr needs them even to query). Run `DFeBrokerConsole --verificar-ambiente`; each line reports what is available or missing ([`runtime-dependencies.md`](dependencias-runtime.md)).
- Python 3 with `pip install pika` (only for the example consumers).
- **Windows x64 shortcut:** the [release package](https://github.com/fabianoallex/pascal-dfe-broker/releases/latest) already contains the executables, DLLs, and a ready-to-use `dfe.ini`; use the shortened walkthrough below. Otherwise, compile the applications:
- Compiled executables: `hosts/console/DFeBrokerConsole` and `simulador/DFeSimulador`. Exact commands (including `lazbuild --add-package-link`, without which you get `Broken dependency`, and `sh simulador/preparar-horse.sh`, for Windows/FPC only) are in “Building and running” in [`README.md`](../README.md); for Delphi, use `PascalDfeBroker.groupproj`. **On Windows, clone into a short path** (for example, `C:\dev\`).
- Ports **9200** (simulator) and **5672** (AMQP) must be free. If Docker/WSL already uses 5672, change `Porta=` in `dfe.ini` and pass `--porta` to the Python scripts.

The demo configuration is [`exemplos/demo-simulador/dfe.ini`](../exemplos/demo-simulador/dfe.ini); read it, it is short and each line is commented. Key settings: `Ambiente=homologacao` + `SimuladorURL=…`, ten-second intervals (demo only), two named queues, and a `matriz` certificate alias with test CNPJ `11222333000181`.

Open **four terminals** in the repository root.

### 4.2 Step 1 — start the “fake SEFAZ”

```
simulador/DFeSimulador --porta 9200
```

Check that `curl http://127.0.0.1:9200/ping` returns `ok`. This is the only component controlled over HTTP (admin API) to prepare scenarios.

### 4.3 Step 2 — start the broker

```
hosts/console/DFeBrokerConsole --config exemplos/demo-simulador/dfe.ini
```

Expected output (shortened):

```
[OK]  OpenSSL ...   [OK]  libxml2 ...   [OK]  XSDs ...
[INFO]  Broker embutido em 127.0.0.1:5672 (duravel em ...\broker)
[INFO]  Fila "documentos" ligada a exchange "dfe" (1 padrao(oes))
[INFO]  Fila "eventos" ligada a exchange "dfe" (1 padrao(oes))
[AVISO] [matriz] TRANSPORTE SIMULADO: as consultas vao para http://127.0.0.1:9200, NAO para a SEFAZ
[INFO]  Em execucao. Ctrl+C ou SIGTERM para parar.
```

**What to show:** the host checks its environment before starting and refuses to run partially; it also clearly warns that the transport is simulated. (If `Ambiente=producao` is combined with `SimuladorURL`, startup is refused to prevent real documents from reaching the simulator.)

It already made its first query: the simulator had nothing (`137`) and **started a one-hour block**, just as SEFAZ would.

### 4.4 Step 3 — any consumer

```
python exemplos/consumidor/python/consumir.py --padrao "nfe.#"
```

It declares its own queue bound to `nfe.#` and waits. This is **all** a consumer needs (about 120 lines, much of it comments and formatting); no tax-domain code is required. This shows that consumption is language-agnostic.

### 4.5 Step 4 — documents arrive (and “656 without waiting an hour”)

In a third terminal, publish two NF-e summaries and one cancellation event **to the simulator** (Git Bash / Linux; in PowerShell use `curl.exe` or `Invoke-RestMethod -Method Post -ContentType application/json -Body '{...}'`):

```bash
curl -s -X POST 127.0.0.1:9200/admin/documentos -H 'Content-Type: application/json' \
     -d '{"cnpj":"11222333000181","uf":"RS","tipo":"resNFe","quantidade":2}'
curl -s -X POST 127.0.0.1:9200/admin/documentos -H 'Content-Type: application/json' \
     -d '{"cnpj":"11222333000181","uf":"RS","tipo":"resEvento","tpEvento":"110111"}'
```

Nothing appears yet. The broker log explains why:

```
[AVISO] [matriz] Consumo indevido (cStat=656); proxima tentativa em 10s
```

The broker queried during the one-hour block and got **656**. This is real SEFAZ behavior, reproduced on demand. Rather than wait an hour, advance the simulator's **virtual clock**:

```bash
curl -s -X POST 127.0.0.1:9200/admin/relogio/avancar -H 'Content-Type: application/json' \
     -d '{"horas":1,"minutos":1}'
```

Within a few seconds the consumer prints:

```
novo      nfe.documento.rs.11222333000181  cnpj=11222333000181 uf=rs
          resNFe  chave=35260998765432000110550010000000011000079198
          xNome=EMITENTE SINTETICO LTDA, dhEmi=2026-09-10T14:30:05-03:00, vNF=150.00, nProt=143260000000001
novo      nfe.documento.rs.11222333000181  ...  chave=...0021000158389
novo      nfe.evento.cancelamento.rs.11222333000181  cnpj=11222333000181 uf=rs
          resEvento  chave=35260998765432000110550010000000031000237570
          tpEvento=110111, xEvento=Evento sintetico, nProt=891260000000001
```

**What to show:** the routing key carries type, category, state, and CNPJ. A consumer interested only in cancellations subscribes to `nfe.evento.cancelamento.#`. Also inspect the saved cursor (`exemplos/demo-simulador/cursores.dat`):

```
nfe/11222333000181/rs/homologacao=3
```

The `homologacao` suffix distinguishes the separate NSUs in the two environments.

### 4.6 Step 5 — “what if nobody is listening?” (named queue + crash)

Stop the consumer. Publish more documents and advance the clock again (repeat step 4). The broker keeps receiving messages. Now **kill the broker forcefully** (terminate the process: `Stop-Process -Name DFeBrokerConsole -Force` in PowerShell, or `kill -9` on Linux — not Ctrl+C, which is a clean shutdown) and restart step 2. Consume from the **named queue**:

```
python exemplos/consumidor/python/consumir.py --fila documentos
```

The documents are still there. This was tested: three messages accumulated with no consumer, the broker was killed using `Stop-Process -Force` and restarted, and all three arrived intact.

**What to show:** the difference between the two consumption modes.

| | **Exclusive** queue (`--padrao`) | **Named** queue (`--fila`) |
|---|---|---|
| Declared by | The consumer | `dfe.ini` (`[fila:documentos]`) |
| Retains messages while the consumer is away? | **No** — disappears on exit | **Yes**, durable (WAL in `DataDir`) |
| Multiple consumers | Each receives a **copy** | They share the work |
| Use for | Analysis tool, debugging | Real ERP integration |

Why queues declared by the host exist: **without a bound queue, the broker discards messages** (it is pub/sub), and the cursor has already advanced. A production `dfe.ini` should therefore always contain at least one `[fila:*]`.

### 4.7 Step 6 — recipient acknowledgement (a fiscal act, sent as a message)

Take an access key from a received document and send a command through the queue (the script builds `key=value` and publishes to `comando.manifestacao`):

```
python exemplos/consumidor/python/manifestar.py --alias matriz --tipo ciencia \
       --chave 35260998765432000110550010000000011000079198
```

On the next tick (up to 60 seconds; two seconds in this demo), the consumer receives the **result as a regular event**:

```
novo      nfe.evento.ciencia.rs.11222333000181  cnpj=11222333000181 uf=rs
          procEventoNFe  chave=...  tpEvento=210210, xEvento=ciencia da operacao, nProt=891000000000001
```

**What to show (and why):**

- The command is **validated before** it goes to SEFAZ (44-digit key, known type, and a 15–255 character justification where required). Invalid input is discarded and logged.
- It is **signed with the alias certificate**, and the event is validated against the official XSDs — this is why libxml2 is required.
- If SEFAZ rejects it (duplicate, sender is not the recipient, and so on), the result is published to `nfe.evento.manifestacaorejeitada.<uf>.<cnpj>` with `cStat`/`xMotivo`. A consumer subscribed to `evento.ciencia` never receives an acknowledgement that was not recorded.
- There is no RPC/`reply-to`: the result returns through the same exchange because the sender is already listening.
- **Automatic mode:** setting `ManifestacaoAutomatica=true` for a certificate makes the broker acknowledge each document automatically. The default is `false`; this is a fiscal act.

### 4.8 Extras (about one minute each)

| To show… | Do this |
|---|---|
| **Pagination** (batches of 50) | `DFeSimulador --cenario simulador/cenarios/paginacao.ini` (120 documents: 50, 50, and 20). |
| **Resilience to failures** | `--cenario simulador/cenarios/instavel.ini` (108, timeout, 500, and 656 on the first queries); watch the broker log continue. |
| **On-demand failure** | `curl -X POST 127.0.0.1:9200/admin/falhas -d '{"falha":"timeout","quantidade":2}'` (failure names are in [`simulador/LEIAME.md`](../simulador/LEIAME.md)). |
| **“SEFAZ” state** | `curl 127.0.0.1:9200/admin/estado` — accounts, current NSU, block, counters. |
| **Request-format check** | `curl 127.0.0.1:9200/admin/violacoes` — `(nenhuma)` means ACBr sent exactly the expected format. With `--estrito`, the simulator rejects invalid requests (400). |
| **Without installing Pascal** | `docker build -f simulador/Dockerfile -t dfe-simulador .` then `python simulador/exemplos/python/roteiro.py` — the simulator is useful even to people who do not use this project. |
| **Custom Pascal rule** | `simulador/exemplos/limite-consultas/` — limit N queries per CNPJ without touching the core. |
| **Very short demo, no external broker** | `tools/demo/DFeDemo --porta 5672 --intervalo 5`: publishes synthetic NF-e messages through the real path (provider → routing key → AMQP). |

### 4.9 Stop and clean up

Press Ctrl+C in the broker and simulator (the broker exits cleanly with code 0). To start over, delete `cursores.dat`, `broker/`, and `logs/` from `exemplos/demo-simulador/` (they are in `.gitignore`).

---

## 5. Features in detail

Evidence labels: **[demo]** = exercised by this guide on 2026-09-20; **[tests]** = covered by automated tests; **[not]** = not exercised against the real world.

### 5.1 DFe Distribution queries (poller per certificate)

One *work unit* per certificate/state. It respects the one-hour minimum interval **without adding backoff** (the Technical Note does not require it), handles 137/138/656/108/109, timeouts, and unreadable responses **without crashing the process** (each unit runs in an isolated `try/except`; one failure does not affect the others). A cycle may include multiple batches (pagination). **[demo] [tests]** against the simulator; **[not]** against SEFAZ.

*Why it matters:* most of the work in a hand-built implementation is dealing with exactly what can go wrong (improper-use blocks, cursors, partial batches).

### 5.2 Reliable NSU cursor

Plain-text `namespace=nsu` file (`nfe/<cnpj>/<uf>[/homologacao]=<nsu>`), written to a temporary file and replaced **atomically** — a crash midway never leaves a partial file. The cursor advances only **after** the entire batch has been published and confirmed. **[demo] [tests]**

*Design decision to explain:* SQLite and reusing the broker's WAL were considered and rejected as disproportionate (there are only dozens of lines). Production keeps the existing key; only homologation gets a suffix, so no migration was needed.

### 5.3 Providers by document type

`IDFeProvider` is the contract; `DFe.Provider.NFe` is the only implemented provider. It decodes `resNFe`, `procNFe`, `resEvento`, and `procEventoNFe`, and builds the routing key. It self-registers during `initialization` — **the core does not know about CT-e/MDF-e**: a contributor adds a unit and a `uses` entry. Unknown schemas are ignored so a new SEFAZ schema cannot stall the cursor. Event types without a mapped name use the **numeric code**. **[tests]** See [`CONTRIBUTING.md`](../CONTRIBUTING.md) to contribute.

### 5.4 Embedded or external AMQP broker

AMQP 0-9-1 broker runs inside the process (from `pascal-amqp-faa`, by the same author, MIT). `Modo=externo` points to an existing RabbitMQ. It is **durable by default** (`DataDir=broker`): the cursor has advanced by the time a message is queued, so a transient queue would lose the document on restart. It listens only on `127.0.0.1` with `guest/guest` — **change the password before exposing it to a network**. **[demo] [tests]**

### 5.5 At-least-once publishing guarantee

Synchronous *publisher confirms*: publishing returns only after the broker confirms. Any failure prevents the cursor from advancing. As a result, a document **may arrive twice**; the consumer deduplicates by access key (`consumir.py` prints `REPETIDO`). Connections are opened on demand and retried after a failure. **[tests]**

### 5.6 Recipient acknowledgement

See 4.7. It can be manual (queue command) or automatic (per alias). Rejections become `manifestacaorejeitada` events. `cOrgao=91` (National Environment) and the recipient's CNPJ are set explicitly because ACBr's defaults would be wrong. `xJust` is not used except for *operation not performed* (NT 2012/002). **[demo] [tests]**; **[not]** sent to real SEFAZ.

### 5.7 Multiple certificates, rotation without stopping, hot reload

One `[certificado:<alias>]` per CNPJ/state. **Two certificates for the same CNPJ** (rotated before expiry) share a cursor, but they must **never** both have `Ativo=true`; the configuration is rejected. While the service runs, edits to `dfe.ini` are detected on the next tick: a new alias is added, `Ativo` is synchronized, a removed alias is paused, and **an invalid config changes nothing** (the previous config remains active and the error is logged). The broker configuration and an alias's environment are not reloaded; they require a restart. **[tests]** *(To try it: with the demo running, set `Ativo=false` and watch the log.)*

### 5.8 Three ways to run it

| Host | Platform | Notes |
|---|---|---|
| `DFeBrokerConsole` | Windows and Linux, Delphi and FPC | On Linux this **is** the production host, under systemd (`hosts/console/systemd/`). Ctrl+C/SIGTERM exits with code 0. |
| `DFeBrokerServico` | Windows, Delphi | Windows Service: daily log with retention, startup failures in Event Log, `sc failure` for automatic restart ([`hosts/servico/LEIAME.md`](../hosts/servico/LEIAME.md)). |
| `DFeDemo` | FPC | Demonstration only. |

All are *thin* hosts: logic lives in `TDFeAplicacao`, which does **not** link ACBr — so the whole application can be tested against the simulator. **[demo]** console; **[tests]** plus manual service checks; **[not]** systemd on a real machine (only in a container).

### 5.9 Fail early and clearly

On startup, invalid configuration, unknown provider, occupied port, unreachable external broker, and incomplete environment (missing OpenSSL/libxml2/XSDs) terminate with a nonzero exit code — the application never runs “halfway.” `--verificar-ambiente` only checks and exits. **[demo]**

### 5.10 SEFAZ simulator (a product of its own)

HTTP server that speaks the Distribution and Event Reception SOAP protocols. It supports INI scenarios, an **admin API** (documents, failures, skipped NSUs, virtual clock, violations, last envelope), strict mode, Pascal rule extensions, a Docker image, and a Python walkthrough. It exists because SEFAZ requires a certificate even in homologation; without the simulator, nothing else could be tested. **[demo] [tests]**, including the **real ACBr client** against it.

*Honest limitation:* its fidelity reflects **our interpretation of the Technical Notes**. If that interpretation is wrong, the simulator repeats the same error.

### 5.11 Quality and portability

Dual-compiler from the start (Delphi and FPC), with mirrored DUnitX and FPCUnit suites. GitHub Actions CI on Linux runs the pure unit suite, ACBr × simulator integration, AMQP, host SIGTERM, and systemd checks. Delphi tests run only in the IDE. Current numbers are in [`CLAUDE.md`](../CLAUDE.md) (rerun before quoting; they change between phases). Real lessons are recorded there — for example, ACBr **silently swallowing** a `docZip` parse error and returning a truncated batch (which would skip documents), leading to `ConferirLoteCompleto`.

---

## 6. Presentation outline and tough questions

### 6.1 Suggested sequence (about 15 minutes)

| Min | Topic |
|---|---|
| 0–2 | Problem and proposal (section 1). Show the diagram in section 3. |
| 2–4 | Contract: exchange `dfe`, routing key, XML body. One slide, no code. |
| 4–12 | **Live demo:** steps 1 to 5 (simulator → broker → consumer → 656 → clock → documents). Finish by killing the broker and showing the durable queue. |
| 12–14 | Recipient acknowledgement (step 6) and its result returning as an event. |
| 14–15 | What is **not** proven (section 7) and how to help. |

**Stage tips:** have all four terminals open and rehearsed; put step 4 in a `.sh`/`.ps1` file so you do not type JSON in front of the audience; check beforehand whether port 5672 is occupied; and do not improvise with a company certificate — the README warning is there for a reason.

### 6.2 Questions you will hear

**“Does it work with the real SEFAZ?”** — Honestly, it has never been run against real SEFAZ; the author has no ICP-Brasil certificate. It works end to end with the **real ACBr component** against a simulator based on the Technical Notes. Please test it in **homologation** and report what you find (issue #1).

**“Why not RabbitMQ?”** — You can use it (`Modo=externo`). The embedded broker lets you download and run the application without operating another service; it speaks standard AMQP 0-9-1, so switching is straightforward.

**“Could I lose a document?”** — The cursor advances only after broker confirmation, is written atomically, and the queue is durable. The trade-off is *at-least-once* delivery: a message may repeat, and the access key is used for deduplication. If an acknowledgement command is accepted but the host crashes before processing it, it is lost; resend it and SEFAZ returns 573 (duplicate).

**“What if my ERP already queries SEFAZ?”** — **This is the real risk.** Different applications querying the same CNPJ must follow the same NSU sequence; otherwise this is improper use (656), and the **entire CNPJ** is blocked for one hour for everyone (NT 2014.002, section 3.11.4). Coordinate first; when in doubt, use homologation or a CNPJ nobody else queries.

**“Why ACBr?”** — It already handles certificates, SOAP, signing, and parsing, and is the de facto standard in the Brazilian Delphi/Lazarus ecosystem. The project started with ACBrLib and switched back to the classic components because the official ACBrLib binary requires a paid signature. The accepted cost is a larger dependency and less mature FPC/Lazarus support.

**“Only NFe?”** — In v1, yes. The provider contract and `CONTRIBUTING.md` were created before there was another provider so CT-e/MDF-e can be added consistently.

**“Does it scale?”** — SEFAZ is the bottleneck (one query per hour per CNPJ), not the broker. The volume per certificate is tens to thousands of messages per day — negligible for the broker.

**“Is it secure?”** — The `.pfx` password is supplied through `SenhaEnv` (an environment variable), never the config file; the broker listens on `127.0.0.1` by default; the simulator's admin API **has no authentication** (it is a test tool — when using Docker, publish its port only on `127.0.0.1`).

**“What is the license?”** — This project is MIT; ACBr is LGPLv3, and the integration preserves that separation (no ACBr code is included under this repository's MIT license).

---

## 7. What has NOT been proven

Say this before anyone asks:

- **It has never run against real SEFAZ**, including homologation; there is no certificate. SEFAZ-side behavior was checked against the Technical Notes and ACBr source.
- Real SEFAZ acceptance of accented `xJust` and a submitted acknowledgement has not been verified.
- **Delphi** does not run in CI (only in the IDE, by the user); the Delphi Win64 simulator and `THTTPClient` error paths have not been covered.
- systemd was checked in a **container**, not on a real machine. ARM has not been tested. Delphi for Linux has not been tested.
- Stopping the Windows Service **while a tick is in progress** (waits up to 60 seconds) has not been exercised.
- NFe only. **Distribution** and **recipient acknowledgement** only — the simulator does not cover issuing invoices, cancellation, and so on.
- Consumers other than the Python examples have not been tested (AMQP 0-9-1 itself is standard).

---

## 8. Where things live in the code

Suggested reading order to **learn** the project (from contract to implementation):

1. `src/DFe.Types.pas`, `DFe.Provider.pas`, `DFe.Errors.pas`, `DFe.Publicador.pas` — the **interfaces**, or project vocabulary.
2. `src/DFe.RoutingKey.pas` — the public convention (short and full of design decisions).
3. `src/DFe.Orquestrador.pas` — the heart: cycle, interval, cursor, failure isolation.
4. `src/DFe.CursorStore.Arquivo.pas` — atomic persistence.
5. `src/DFe.Provider.NFe.pas` — decoding batches into documents and events.
6. `src/DFe.Client.ACBrNFe.pas` — the **only** part that talks to ACBr (queries, `EnviarEvento`, batch validation).
7. `src/DFe.Publicador.AMQP.pas` and `DFe.ComandoFonte.AMQP.pas` — the two sides of the broker.
8. `src/DFe.Manifestacao.pas` — command → SEFAZ → result as an event.
9. `src/DFe.Config.pas`, `DFe.Host.Aplicacao.pas`, `DFe.Host.Loop.pas` — how everything is assembled from the INI and the *tick*.
10. `hosts/console/DFeBrokerConsole.dpr`, `hosts/servico/` — the intentionally thin hosts.
11. `src/DFe.Simulador*.pas` and `simulador/` — the simulator; note that **no production unit depends on it**.

Documents: [`architecture.md`](architecture.md) (the “why” behind decisions), [`../CLAUDE.md`](../CLAUDE.md) (locked decisions and pitfalls, in order), [`dependencias-runtime.md`](dependencias-runtime.md), [`simulador-standalone.md`](simulador-standalone.md), [`acbr-achados.md`](acbr-achados.md), [`referencias/`](referencias/README.md) (official Technical Notes — the source of truth for protocol rules).

**Exercises to check your understanding:**

1. Trigger a 656 and clear it **without** the virtual clock: what `IntervaloBaseSegundos` would be needed, and why can it not be lowered in production?
2. Set `ManifestacaoAutomatica=true` for an alias, publish an `resNFe`, and watch the `ciencia` event appear **without** sending a command.
3. Publish a `procEventoNFe` with `tpEvento` `110150` and see the numeric code used in the routing key. Why would mapping it to a name be a breaking change?
4. Configure a second alias for a **different** CNPJ and watch two work units run; then configure two `Ativo=true` aliases for the **same** CNPJ/state and observe the rejection.
5. Write a simulator rule (copy `limite-consultas`) that returns 108 on Thursdays.
