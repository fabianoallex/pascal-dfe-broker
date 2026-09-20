# DFe Broker

[![Linux (FPC)](https://github.com/fabianoallex/pascal-dfe-broker/actions/workflows/linux.yml/badge.svg)](https://github.com/fabianoallex/pascal-dfe-broker/actions/workflows/linux.yml)

> ⚠️ **Status (September 2026): works end to end against a SEFAZ simulator, but has never been run against the real SEFAZ** — the author has no ICP-Brasil digital certificate. Tested on Delphi (Win32/Win64) and FPC (Windows and Linux/Docker); the console host starts and stops cleanly on both compilers. Do not use in production without validating with your own certificate (homologation first) and, if you can, [report what you find](https://github.com/fabianoallex/pascal-dfe-broker/issues/1). Design decisions are recorded in [`docs/architecture.md`](docs/architecture.md). Portuguese is the primary language of this project (see [`README.md`](README.md)); this file is a mirror for non-Portuguese-speaking contributors, and most linked documents are in Portuguese.

**Queries the Brazilian tax authority's (SEFAZ) DFe Distribution service (NFe in v1; CT-e and MDF-e planned) and publishes each fiscal document and event as a message on an AMQP queue.** Any system — Delphi, Python, Node, PHP, Java, C# — consumes them with a standard AMQP client, knowing nothing about SEFAZ, digital certificates or ACBr. Self-hosted, open source (MIT), no external messaging infrastructure required.

```
   SEFAZ ──(certificate, NSU, 1 query/hour)──►  DFe Broker  ──►  embedded AMQP broker  ──►  your systems
                                                (cursor, ACBr,     exchange "dfe"            (any language)
                                                 manifestation)    nfe.documento.rs.<cnpj>
                                                                   nfe.evento.cancelamento.rs.<cnpj>
```

What a consumer receives (real output of the Python example, with synthetic data):

```
novo      nfe.documento.rs.11222333000181  cnpj=11222333000181 uf=rs
          resNFe  chave=35260998765432000110550010000000011000079198
          xNome=EMITENTE SINTETICO LTDA, dhEmi=2026-09-10T14:30:05-03:00, vNF=150.00
novo      nfe.evento.cancelamento.rs.11222333000181  cnpj=11222333000181 uf=rs
          resEvento  chave=35260998765432000110550010000000031000237570  tpEvento=110111
```

## See it working, no certificate needed

**Without building anything (Windows x64):** download the package from the [v0.1.0 release](https://github.com/fabianoallex/pascal-dfe-broker/releases/latest) — executables, the simulator, the DLLs, a test certificate and a 6-step `LEIAME.md` (Portuguese).

The project ships a **SEFAZ simulator**. [`docs/guia-de-uso.md`](docs/guia-de-uso.md) (Portuguese) walks you from "I just built it" to watching documents arrive on a queue, reproducing the "improper use" block (cStat 656) in seconds, and sending a recipient manifestation. The demo configuration is in [`exemplos/demo-simulador/`](exemplos/demo-simulador/dfe.ini). See also the [FAQ](docs/faq.en.md).

## Why

Automating the query of fiscal documents that involve your company (DFe Distribution) today means, in practice, choosing between paying for a closed SaaS or implementing the whole flow (NSU cursor, digital certificate, XML parsing, manifestation) by hand inside your own ERP. DFe Broker proposes a third way: an **open source, self-hosted** tool that any company or developer runs with their own digital certificate, delivering documents as queue messages — so any system can consume them through a standard AMQP client, with zero coupling to Object Pascal.

## What it does

- **Poller per certificate** — periodically queries DFe Distribution, respecting SEFAZ's minimum interval (1 h), and keeps the **NSU cursor** persisted with atomic writes: the project's highest-risk piece (a corrupted cursor means a lost or endlessly re-fetched document). The cursor advances only after the whole batch was published and confirmed by the broker — *at-least-once* delivery, so consumers deduplicate by access key.
- **Embedded AMQP 0-9-1 broker** — from [pascal-amqp-faa](https://github.com/fabianoallex/pascal-amqp-faa), inside the same process, **durable** by default. No RabbitMQ required, but it speaks the standard protocol: you can point at an external one.
- **Public routing-key contract** — topic exchange `dfe`, routing-key `<type>.<category>.<uf>.<cnpj>`. Whoever wants only cancellations subscribes to `nfe.evento.cancelamento.#`. Python consumer examples in [`exemplos/consumidor/`](exemplos/consumidor/README.md).
- **Recipient manifestation** — acknowledgement, confirmation, non-recognition and operation-not-performed, by a command on the queue; the result (or SEFAZ's rejection) comes back as an event. An automatic mode per certificate exists, **off by default** (it is a fiscal act).
- **Multiple certificates** (including swapping before expiry) and **hot reload** of the configuration file.
- **Providers per document type** — NFe in v1; CT-e and MDF-e plug in without touching the core (see [`CONTRIBUTING.md`](CONTRIBUTING.md)).
- **Ways to run** — console (Windows and Linux; under systemd in production on Linux) and Windows Service (Delphi).
- **SEFAZ simulator** — HTTP server with an admin API, virtual clock, failure injection and Pascal extensions; also usable as a standalone tool ([`simulador/LEIAME.md`](simulador/LEIAME.md)).
- **Fiscal integration via ACBr** — the [ACBr project](https://www.acbr.com.br/) components handle SEFAZ communication, the certificate and XML.

> Technical note: SEFAZ web services require a real ICP-Brasil digital certificate even in the staging (homologação) environment. So only the SEFAZ-facing adapter depends on a certificate; the rest is tested against the project's **SEFAZ simulator**, with the real ACBr component, and the automated test suite needs no certificate. The simulator's fidelity is this project's reading of the Technical Notes — validating with a real certificate is exactly what is missing ([issue #1](https://github.com/fabianoallex/pascal-dfe-broker/issues/1)).

## Supported compilers

Delphi and FPC/Lazarus, **from day one** — the same dual-compiler pattern as pascal-amqp-faa. Where ACBr's Lazarus support is a real limitation, that limit is documented explicitly.

| Compiler | Version used by the author | Notes |
|---|---|---|
| **FPC/Lazarus** | Lazarus 4.0 (FPC 3.2.2) on Windows; FPC 3.2.2 on Linux (Debian 12) | Windows and Linux x86_64. Not tested: ARM, macOS. |
| **Delphi** | Delphi 12 (Athens), Win32 and Win64 | Earlier versions not tested. The Windows Service is Delphi-only. |

## Building and running

Depends on submodules under `vendor/`: the [pascal-amqp-faa](https://github.com/fabianoallex/pascal-amqp-faa) broker (~4 MB), ACBr (~75 MB partial clone) and, for the simulator only, [Horse](https://github.com/HashLoad/horse). **Do not use `--recurse-submodules`**: it would download the whole ACBr monorepo (~1.3 GB).

> **Windows:** clone into a **short** path (e.g. `C:\dev\`). ACBr has deep folders, and a long path makes Git refuse the submodule clone (`Filename too long`).

These commands were run on a clean clone and work (Git Bash on Windows, or a Linux shell):

```
git clone https://github.com/fabianoallex/pascal-dfe-broker
cd pascal-dfe-broker
git submodule update --init vendor/pascal-amqp-faa
sh tools/init-acbr-submodule.sh                                  # ~2 min the first time
```

**Broker (console host) with FPC/Lazarus:**

```
lazbuild --add-package-link packages/pascal_dfe_broker.lpk       # once per machine; without it: "Broken dependency"
lazbuild hosts/console/DFeBrokerConsole.lpi
```

**SEFAZ simulator** (for the demo and for tests):

```
git submodule update --init vendor/horse
sh simulador/preparar-horse.sh                                   # Windows/FPC only: a 1-line workaround in Horse
lazbuild simulador/DFeSimulador.lpi
```

**Delphi:** open `PascalDfeBroker.groupproj` and build `DFeBrokerConsole` (Win64) and, optionally, `DFeSimulador`.

**Run:** `DFeBrokerConsole --config dfe.ini` (commented template in `hosts/console/dfe.exemplo.ini`).

**Runtime dependencies — not in the repository:** OpenSSL 3 (`libssl` + `libcrypto`), **libxml2** and the NFe XSDs (the latter come with the ACBr submodule). A missing one only shows up at run time, which is why `DFeBrokerConsole --config dfe.ini --verificar-ambiente` exists: it checks everything and says what is missing and how to get it ([`docs/dependencias-runtime.md`](docs/dependencias-runtime.md), Portuguese).

**More:** synthetic demo `tools/demo/DFeDemo` · Windows Service in [`hosts/servico/LEIAME.md`](hosts/servico/LEIAME.md) · Linux/systemd in [`docs/linux.md`](docs/linux.md) · tests in [`docs/testes.md`](docs/testes.md) (all in Portuguese).

## Reference Technical Notes

This project follows these versions of the official Technical Notes (copies and literal citations in [`docs/referencias/`](docs/referencias/README.md)):

| Document | Version | Downloaded on |
|---|---|---|
| NT 2014.002 (NFe, DFe Distribution) | 1.02d, March 2021 | 2026-09-17 |
| NT 2015/002 (CT-e, DFe Distribution) | 1.00a, August 2016 | 2026-09-17 |
| NT 2015/002 (MDF-e, DFe Distribution) | 1.00b, March 2016 | 2026-09-17 |
| NT 2012/002 (Recipient Manifestation) | 1.02, March 2012 | 2026-09-18 |

If the current version on the [Portal Nacional da NF-e](https://www.nfe.fazenda.gov.br/portal) is newer than what's listed here, this table and `docs/referencias/` are out of date — treat that as a bug and open an issue.

## Before using a company's certificate

- **Does another system already query DFe Distribution for that CNPJ?** (ERP, accountant, another service.) Technical Note NT 2014.002 (section 3.11.4, p. 14) says different applications querying the **same CNPJ** must follow the same NSU sequence, otherwise the query counts as **misuse** and the **CNPJ** (not the certificate) is blocked for **1 hour** — for everyone querying it. The block is automatic and temporary, but it can take down a system somebody else relies on. Coordinate first; when in doubt, use **homologation** or a CNPJ nobody queries.
- **Recipient manifestation is a fiscal act**: it records an event on the company's NF-e. The default is `ManifestacaoAutomatica=false`; **do not enable it in production without sign-off from whoever is accountable for tax matters**.
- The certificate is the company's digital identity (and a legally binding signature): make sure you are authorised to use it, keep the `.pfx` and its password secret, and check internal policy.

## Documentation

| To… | Read |
|---|---|
| See it working, understand and present it | [`docs/guia-de-uso.md`](docs/guia-de-uso.md) (pt) |
| Common questions | [`docs/faq.en.md`](docs/faq.en.md) |
| Design decisions | [`docs/architecture.md`](docs/architecture.md) (pt) |
| Consume documents from another language | [`exemplos/consumidor/`](exemplos/consumidor/README.md) (pt) |
| Prepare the environment (OpenSSL, libxml2, XSDs) | [`docs/dependencias-runtime.md`](docs/dependencias-runtime.md) (pt) |
| Use the SEFAZ simulator | [`simulador/LEIAME.md`](simulador/LEIAME.md) (pt) |
| Run the tests | [`docs/testes.md`](docs/testes.md) (pt) |
| Contribute | [`CONTRIBUTING.md`](CONTRIBUTING.md) (pt) |
| Report a security issue | [`SECURITY.md`](SECURITY.md) (pt) |

## License

This project is licensed under [MIT](LICENSE). The ACBr components used as a dependency are licensed under **LGPLv3** — the integration preserves that licensing separation (no ACBr source is incorporated under this repository's MIT license).

## Contributing

Contributions are very welcome, especially from Brazilian developers with experience in SEFAZ, ACBr, AMQP, or Lazarus/FPC. **The most valuable help right now is validating in homologation with a real certificate** ([issue #1](https://github.com/fabianoallex/pascal-dfe-broker/issues/1)). Questions and ideas: [Discussions](https://github.com/fabianoallex/pascal-dfe-broker/discussions); there are [open issues for newcomers](https://github.com/fabianoallex/pascal-dfe-broker/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22). Before opening a PR that adds a new document type (CT-e, MDF-e, etc.), read [`CONTRIBUTING.md`](CONTRIBUTING.md) — uniformity across providers is a project requirement, not a style detail.
