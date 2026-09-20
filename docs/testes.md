# Como rodar os testes

Nenhum teste precisa de certificado digital, de SEFAZ ou de infraestrutura externa. Há três camadas:

| Camada | O que cobre | Onde |
|---|---|---|
| **Pura** | Toda a lógica que independe de ACBr e de broker: cursor, orquestrador, providers, routing-key, configuração, manifestação, o núcleo do simulador. Sem `Sleep`, sem relógio real, sem rede. | `tests/Unit/` |
| **Integração ACBr × simulador** | O client ACBr **real** (consulta e manifestação, com assinatura e validação XSD) contra o simulador da SEFAZ, inclusive por HTTP. | `tests/Integration/AcbrSim/` |
| **Integração AMQP** | Publicador, fonte de comandos e a aplicação inteira contra o broker embutido e o simulador. | `tests/Integration/AmqpBroker/` |

Os números atuais (que mudam a cada fase) ficam no [`CLAUDE.md`](../CLAUDE.md), no cabeçalho. **Rode de novo antes de citá-los.**

## Pré-requisitos

- Os submódulos inicializados (ver o README): `vendor/pascal-amqp-faa`, `vendor/ACBr` e, para o simulador, `vendor/horse`.
- O pacote Lazarus registrado, uma vez por máquina: `lazbuild --add-package-link packages/pascal_dfe_broker.lpk`.
- Para a integração com o ACBr: **OpenSSL 3, libxml2 e os XSDs** ([`dependencias-runtime.md`](dependencias-runtime.md)). Sem eles, os testes que exigem libxml2 e XSDs são **ignorados** (14 deles) e os de distribuição falham dizendo o que falta.
- Para os testes HTTP de integração: o executável do simulador compilado (`simulador/DFeSimulador`, ver o README). Sem ele o teste **falha** e diz como compilar.

## FPC/Lazarus (linha de comando)

```
lazbuild tests/Unit/fpc/DFeUnitTestsFpc.lpi
tests/Unit/fpc/DFeUnitTestsFpc --all --format=plain                 # pura

lazbuild tests/Integration/AcbrSim/AcbrSimTests.lpi
tests/Integration/AcbrSim/AcbrSimTests --all --format=plain         # ACBr x simulador

lazbuild tests/Integration/AmqpBroker/AmqpBrokerTests.lpi
tests/Integration/AmqpBroker/AmqpBrokerTests --all --format=plain   # AMQP
```

(No Windows os executáveis têm `.exe`.) O `heaptrc` está ligado nas suítes pura e AMQP: um vazamento aparece no relatório do fim da execução, e o resultado esperado é **0 vazamento**.

Se um build parecer usar código antigo depois de você mudar um arquivo de `src/`, force: `lazbuild -B -r tests/Unit/fpc/DFeUnitTestsFpc.lpi`.

## Linux, com Docker

Sem instalar nada além do Docker:

```
tools/docker/testar-linux.sh              # pura + ACBr x simulador + AMQP; compila e sobe o host e o derruba com SIGTERM
tools/docker/testar-linux.sh --so-pura    # só a suíte pura
tools/docker/testar-systemd.sh            # a unit de systemd, num contêiner com systemd
tools/docker/testar-simulador-docker.sh   # a imagem Docker do simulador + o roteiro Python
```

É o que o CI (GitHub Actions) executa. Detalhes em [`linux.md`](linux.md).

## Delphi (DUnitX, pela IDE)

Abra `PascalDfeBroker.groupproj` e rode os projetos de teste:

- `tests/Unit/DFe.UnitTests.dproj` — a suíte pura (espelho da FPC, **não** 1:1: o Delphi tem testes próprios);
- `tests/Integration/AcbrSim/delphi/AcbrSimDelphiTests.dproj` — ACBr × simulador (Win64);
- `tests/Integration/AmqpBroker/delphi/` — AMQP.

O Delphi **não roda no CI**: só pela IDE. Por isso vale rodar os dois compiladores antes de confiar em qualquer mudança — o `ReadBool` do Delphi e o FPC discordaram em silêncio uma vez ([`CLAUDE.md`](../CLAUDE.md), "Gotchas dual-compiler").

## Regras para escrever testes

- **Toda unit pura nova ganha os dois espelhos**: DUnitX em `tests/Unit/` e FPCUnit em `tests/Unit/fpc/`. Cada projeto de teste precisa listar a unit (`.dpr`/`.dproj` e `.lpr`/`.lpi`).
- **Sem `Sleep` e sem relógio real**: use os dublês de `DFe.TestDoubles.pas` (relógio controlável, fonte de comando fake, client fake…).
- **Fonte só em ASCII**: o Delphi lê fonte sem BOM como ANSI. Acento ou emoji em literal vira mojibake; use `#$00E3` ou monte com constante. Depois de gravar, confira que não há byte > 126 nos `.pas` novos.
- **Não construa um objeto inline como argumento de uma chamada que levanta exceção** (vaza no FPC 3.2.2): atribua antes a uma variável de tipo interface.
- **Fixture criado no `Setup` mas usado por só parte dos testes** vaza no `heaptrc`: crie dentro do teste que precisa.
- Fixtures de XML precisam satisfazer o **parser real do ACBr**, não só o nosso provider (por exemplo, um `procNFe` sem `<tpNF>` é engolido em silêncio).
- Nunca use certificado real, senha ou XML fiscal real em fixture. O certificado de teste do repositório (`tests/Integration/AcbrSim/cert-teste/`, CNPJ `11222333000181`, senha `teste123`) é sintético.
