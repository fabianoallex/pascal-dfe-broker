# DFe Broker

> ⚠️ Project in the design/conception stage (September 2026). There is no functional code yet — this README describes the intended vision and architecture. Design decisions are tracked in [`CLAUDE.md`](CLAUDE.md) and [`docs/architecture.md`](docs/architecture.md). Portuguese is the primary language for this project (see [`README.md`](README.md)); this file is a mirror for non-Portuguese-speaking contributors.

Open source tool to query and distribute Brazilian electronic fiscal documents (NFe in v1; CTe, MDFe and other DFe types planned) through SEFAZ's **DFe Distribution** web service, publishing the received documents and events to user-configurable AMQP queues — with no external messaging infrastructure required to run it.

## Why

Automating the query of fiscal documents that involve your company (DFe Distribution) today means, in practice, choosing between paying for a closed SaaS or implementing the whole flow (NSU cursor, digital certificate, XML parsing, manifestation) by hand inside your own ERP. DFe Broker proposes a third way: an **open source, self-hosted** tool that any company or developer runs with their own digital certificate, delivering documents as queue messages — so any system (Delphi, Python, Node, Java, anything) can consume them through a standard AMQP client, with zero coupling to Object Pascal.

## Architecture overview

- **Poller per certificate** — for each configured digital certificate, periodically queries the corresponding SEFAZ DFe Distribution service, respecting the minimum intervals SEFAZ enforces (querying too often gets rejected), and keeps the NSU cursor reliably persisted — this is the project's highest-risk piece: a corrupted cursor means a lost or endlessly re-fetched document.
- **Providers per document type** — the logic specific to each DFe type (NFe in v1; CTe and MDFe planned, ideally as community contributions) sits behind a common contract, so new types can be added without touching the broker core. See [`CONTRIBUTING.md`](CONTRIBUTING.md).
- **Embedded AMQP broker** — uses the embedded AMQP 0-9-1 broker from [pascal-amqp-faa](https://github.com/fabianoallex/pascal-amqp-faa), running inside the same process. No external RabbitMQ (or other broker) is required to run it, but it stays compatible with one, since it speaks standard AMQP 0-9-1 — anyone with existing messaging infrastructure can point at it instead.
- **Fiscal integration via ACBr** — [ACBr](https://www.acbr.com.br/) components handle SEFAZ communication, the digital certificate, and XML parsing.

Design details — exchange/routing-key convention, provider contract, NSU cursor persistence, execution model (Windows service, console, Linux daemon) — live in [`docs/architecture.md`](docs/architecture.md).

> Technical note: SEFAZ web services require a real ICP-Brasil digital certificate even in the staging (homologação) environment. Because of that, only the SEFAZ-facing adapter depends on a certificate — the rest of the system (poller, NSU cursor, provider contract, AMQP publishing) is developed and tested against recorded fixtures, with no certificate required. See "Fronteira testável sem certificado real" in `docs/architecture.md`.

## Supported compilers

Delphi and FPC/Lazarus, **from day one** — the same dual-compiler pattern as pascal-amqp-faa. Where ACBr's Lazarus support is a real limitation, that limit is documented explicitly rather than hidden or worked around at the cost of functionality.

## Reference Technical Notes

This project follows these versions of the official DFe Distribution Technical Notes (copies and literal citations in [`docs/referencias/`](docs/referencias/README.md)):

| Document | Version | Downloaded on |
|---|---|---|
| NT 2014.002 (NFe) | 1.02d, March 2021 | 2026-09-17 |
| NT 2015/002 (CT-e) | 1.00a, August 2016 | 2026-09-17 |
| NT 2015/002 (MDF-e) | 1.00b, March 2016 | 2026-09-17 |

If the current version on the [Portal Nacional da NF-e](https://www.nfe.fazenda.gov.br/portal) is newer than what's listed here, this table and `docs/referencias/` are out of date — treat that as a bug and open an issue.

## License

This project is licensed under [MIT](LICENSE). The ACBr components used as a dependency are licensed under **LGPLv3** — the integration preserves that licensing separation (no ACBr source is incorporated under this repository's MIT license).

## Contributing

Contributions are very welcome, especially from Brazilian developers with experience in SEFAZ, ACBr, AMQP, or Lazarus/FPC. Before opening a PR that adds a new document type (CTe, MDFe, etc.), read [`CONTRIBUTING.md`](CONTRIBUTING.md) — uniformity across providers is a project requirement, not a style detail.
