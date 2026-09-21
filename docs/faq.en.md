# Frequently asked questions

Short answers. For the step-by-step guide, see [`guia-de-uso.md`](guia-de-uso.md) (Portuguese); for the reasons behind the design decisions, see [`architecture.md`](architecture.md) (Portuguese).

## About the project

**Does it work with the real SEFAZ?**
We do not know. The author does not have an ICP-Brasil certificate, so the project has never been run against the real SEFAZ, even in its homologation environment. It works end to end with the **real** ACBr component against a simulator built from the Technical Notes; the simulator reflects our interpretation of those notes. If you have a certificate, [issue #1](https://github.com/fabianoallex/pascal-dfe-broker/issues/1) provides a homologation validation procedure.

**Who is it for?**
For anyone who needs to receive fiscal documents addressed to their company's CNPJ (NF-e issued to the company) and deliver them to one or more systems—ERP, BI, reconciliation, or archiving—without paying for a SaaS or reimplementing NSU tracking, certificates, and recipient manifestation in each system.

**How is it different from an invoice lookup SaaS?**
You run it on your own infrastructure with your own certificate, which never leaves your machine. There is no per-CNPJ subscription, and the code is open source. The tradeoff is that **you operate it**. There is no paid support, and the project has not yet been validated against the real SEFAZ.

**Does it support only NF-e?**
In v1, yes. The provider contract and [`CONTRIBUTING.md`](../CONTRIBUTING.md) are designed to let contributors add CT-e and MDF-e. Note that the "improper use" status code differs by document type (656 for NF-e and CT-e; 678 for MDF-e).

**Can it issue invoices?**
That is out of scope. It handles only *DFe Distribution* (receiving documents) and recipient manifestation.

**What is the license?**
This repository is MIT licensed. ACBr is LGPLv3, and the integration keeps the projects separate: this project does not incorporate ACBr code under the MIT license. Because ACBr is compiled into the binary, **review the LGPL before distributing a commercial binary**. This answer is not legal advice.

## Usage

**Do I need Delphi?**
No. The project builds with **FPC/Lazarus**, which is free and available for Windows and Linux. Delphi is also supported. The Windows Service is the only Delphi-only component; on Linux, the console application under systemd serves the same purpose.

**My system is not written in Pascal. How do I consume messages?**
Use any AMQP 0-9-1 client (pika, amqplib, RabbitMQ.Client, Bunny, and others). Connect to the `dfe` exchange and use the routing key. Two Python consumer examples are in [`exemplos/consumidor/`](../exemplos/consumidor/README.md). Consumers in other languages have not been tested yet, but the protocol is standard.

**My system is written in Delphi. How do I consume messages?**
Use the AMQP client from [pascal-amqp-faa](https://github.com/fabianoallex/pascal-amqp-faa), the same embedded broker, or any AMQP 0-9-1 client. This repository does not yet include a Delphi consumer example.

**Do I need to install RabbitMQ?**
No. The broker is embedded. If you already have RabbitMQ, set `Modo=externo` in `dfe.ini`.

**Can I lose a document?**
The NSU cursor advances only after the broker confirms the entire batch, using an atomic write, and queues are durable. Delivery is **at least once**, so the same document may arrive more than once; deduplicate by the **access key** (44 digits). If a consumer stops after receiving a message but before acknowledging it (`ack`), it will receive the message again. A queue with no consumer and no bound queue discards messages (pub/sub behavior), so `dfe.ini` must declare at least one `[fila:*]` queue.

**What is the difference between an exclusive queue and a named queue?**
An **exclusive** queue is declared by the consumer, receives a copy of each message, and disappears when the consumer disconnects. A **named** queue is declared in `dfe.ini`, is durable, and stores messages while no one is reading; multiple consumers of the same queue share the work. Use a named queue to integrate with an ERP.

**How often does it query SEFAZ?**
When there are no new documents, it queries at most once per hour per certificate, which is the minimum interval required by SEFAZ. Do not lower `IntervaloBaseSegundos`: querying sooner triggers status 656 (improper use) and blocks the CNPJ for one hour. If there are still documents to receive, it continues fetching batches during the same cycle.

**My ERP already queries DFe Distribution. Can I run this alongside it?**
This is the main risk. Separate applications querying the **same CNPJ** must follow the same NSU sequence. Otherwise, SEFAZ returns status 656 and blocks the **entire CNPJ** for one hour for all applications (Technical Note 2014.002, section 3.11.4). Coordinate first; if in doubt, use homologation or a CNPJ that no one else queries.

**Is recipient manifestation safe?**
It is a **fiscal act**: it registers an event on the company's NF-e. For this reason, `ManifestacaoAutomatica` defaults to `false`. Do not enable it in production without approval from the person responsible for tax matters. Manual manifestation (through a queue command) is your decision, one document at a time.

**How do I replace a certificate before it expires?**
Add the new certificate as `[certificado:outro]` with the **same CNPJ**, then switch `Ativo` (`false` for the old certificate and `true` for the new one); the broker reloads the file automatically. The cursor belongs to the CNPJ/state (UF), not the certificate, so this causes no loss or duplication. Never set both certificates to `Ativo=true`; the configuration will be rejected.

**Where should I store the certificate password?**
In an environment variable (`SenhaEnv=NAME` in `dfe.ini`), not in the file. For a Windows Service, the variable must be a **system** environment variable.

## Operations and security

**Which dependencies do I need to install?**
OpenSSL 3 and **libxml2** are both required, even for querying, as are the NF-e XSDs (already included in the ACBr submodule). `DFeBrokerConsole --config dfe.ini --verificar-ambiente` reports missing dependencies. See [`dependencias-runtime.md`](dependencias-runtime.md) (Portuguese).

**Is the embedded broker secure?**
By default, it listens only on `127.0.0.1` and uses `guest/guest`. If you expose it to the network (`BindAddress=0.0.0.0`), **change the username and password** and protect the port. `dfe.ini` currently has no TLS option for the embedded AMQP broker. For encrypted network connections, keep `BindAddress` at `127.0.0.1` and use a VPN or tunnel.

**Does it scale?**
The limit is SEFAZ (one query per hour per CNPJ), not the broker. The volume per certificate is tens to a few thousand messages per day, which is trivial for the broker.

**Where is data stored?**
Next to `dfe.ini`: the cursor (`cursores.dat`), the broker WAL (`broker/`), and, when running as a service, logs (`logs/`). Relative paths are resolved against the configuration file's directory.

**Can I run it in Docker?**
The simulator has a `Dockerfile` (`simulador/`). There is no official broker image yet; the broker runs on Linux under systemd, and the test suite runs in a container. Contributions are welcome.

## Simulator

**Is the simulator the SEFAZ?**
No. It responds according to the project's interpretation of the Technical Notes and is for testing only. If that interpretation is wrong, the simulator repeats the error.

**Can I use the simulator in another project?**
Yes. It is an HTTP server; your client only needs to allow changing the service URL and to speak HTTP (without TLS). A Python walkthrough using only the standard library is in [`simulador/LEIAME.md`](../simulador/LEIAME.md) (Portuguese).

**Why do I need a certificate even in homologation?**
Because SEFAZ web services require a real ICP-Brasil certificate in every environment. The simulator does not: the project uses a self-signed test certificate that is public in the repository. **Never use it outside testing.**
