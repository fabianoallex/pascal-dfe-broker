# DFe Broker

[![Linux (FPC)](https://github.com/fabianoallex/pascal-dfe-broker/actions/workflows/linux.yml/badge.svg)](https://github.com/fabianoallex/pascal-dfe-broker/actions/workflows/linux.yml)

> ⚠️ **Estado (setembro/2026): funciona de ponta a ponta contra um simulador da SEFAZ, mas nunca foi executado contra a SEFAZ real** — o autor não tem certificado digital ICP-Brasil. Testado em Delphi (Win32/Win64) e FPC (Windows e Linux/Docker); o host console sobe e para limpo nos dois compiladores. Não use em produção sem validar com o seu certificado (em homologação primeiro) e, se puder, [conte o que encontrou](https://github.com/fabianoallex/pascal-dfe-broker/issues/1). As decisões de projeto estão registradas em [`docs/architecture.md`](docs/architecture.md).

**Consulta a Distribuição de DFe da SEFAZ (NFe na v1; CTe e MDFe planejados) e publica cada documento e evento como uma mensagem numa fila AMQP.** Qualquer sistema — Delphi, Python, Node, PHP, Java, C# — consome com um cliente AMQP comum, sem saber nada de SEFAZ, certificado ou ACBr. Auto-hospedado, open source (MIT), sem exigir infraestrutura de mensageria externa.

```
   SEFAZ ──(certificado, NSU, 1 consulta/hora)──►  DFe Broker  ──►  broker AMQP embutido  ──►  seus sistemas
                                                   (cursor, ACBr,      exchange "dfe"           (qualquer linguagem)
                                                    manifestação)      nfe.documento.rs.<cnpj>
                                                                       nfe.evento.cancelamento.rs.<cnpj>
```

O que um consumidor recebe (saída real do exemplo em Python, com dados sintéticos):

```
novo      nfe.documento.rs.11222333000181  cnpj=11222333000181 uf=rs
          resNFe  chave=35260998765432000110550010000000011000079198
          xNome=EMITENTE SINTETICO LTDA, dhEmi=2026-09-10T14:30:05-03:00, vNF=150.00
novo      nfe.evento.cancelamento.rs.11222333000181  cnpj=11222333000181 uf=rs
          resEvento  chave=35260998765432000110550010000000031000237570  tpEvento=110111
```

## Veja funcionando, sem certificado

O projeto inclui um **simulador da SEFAZ**. O [`docs/guia-de-uso.md`](docs/guia-de-uso.md) leva você, passo a passo, de "acabei de compilar" a ver documentos chegando numa fila, reproduzir o bloqueio de consumo indevido (656) em segundos e mandar uma manifestação do destinatário; a configuração da demo está em [`exemplos/demo-simulador/`](exemplos/demo-simulador/dfe.ini). Não conhece o vocabulário (NSU, cStat, resNFe…)? O guia tem um glossário, e há um [FAQ](docs/faq.md).

## Por quê

Automatizar a consulta de documentos fiscais que envolvem sua empresa (Distribuição de DFe) hoje significa, na prática, escolher entre pagar por um SaaS fechado ou implementar o fluxo inteiro (NSU, certificado, XML, manifestação) na unha dentro do próprio ERP. O DFe Broker propõe uma terceira via: uma ferramenta **open source e auto-hospedada**, que qualquer empresa ou dev roda com o próprio certificado digital, entregando os documentos como mensagens numa fila — para que qualquer sistema consuma via um cliente AMQP padrão, sem nenhum acoplamento com Object Pascal.

## O que ele faz

- **Poller por certificado** — consulta periodicamente a Distribuição de DFe, respeitando o intervalo mínimo da SEFAZ (1 h), e mantém o **cursor de NSU** persistido com escrita atômica: é o ponto de maior risco (um cursor corrompido significa documento perdido ou reconsultado para sempre). O cursor só avança depois que o lote inteiro foi publicado e confirmado pelo broker — entrega *pelo menos uma vez*, então deduplique pela chave de acesso.
- **Broker AMQP 0-9-1 embutido** — do [pascal-amqp-faa](https://github.com/fabianoallex/pascal-amqp-faa), dentro do próprio processo, **durável** por padrão. Não exige RabbitMQ, mas fala o protocolo padrão: dá para apontar para um externo.
- **Contrato público de routing-key** — exchange `dfe` (topic), routing-key `<tipo>.<categoria>.<uf>.<cnpj>`. Quem só quer cancelamentos assina `nfe.evento.cancelamento.#`. Consumidores de exemplo (Python) em [`exemplos/consumidor/`](exemplos/consumidor/README.md).
- **Manifestação do destinatário** — ciência, confirmação, desconhecimento e operação não realizada, por um comando na fila; o resultado (ou a rejeição da SEFAZ) volta como evento. Há modo automático por certificado, **desligado por padrão** (é um ato fiscal).
- **Vários certificados** (inclusive troca antes do vencimento) e **recarga a quente** do arquivo de configuração.
- **Providers por tipo de documento** — NFe na v1; CTe e MDFe entram sem tocar no core (ver [`CONTRIBUTING.md`](CONTRIBUTING.md)).
- **Formas de rodar** — console (Windows e Linux; sob systemd em produção no Linux) e Serviço Windows (Delphi).
- **Simulador da SEFAZ** — servidor HTTP com API de administração, relógio virtual, injeção de falhas e extensão em Pascal; serve também como ferramenta independente ([`simulador/LEIAME.md`](simulador/LEIAME.md)).
- **Integração fiscal via ACBr** — os componentes do [projeto ACBr](https://www.acbr.com.br/) cuidam da comunicação com a SEFAZ, do certificado e do XML.

Detalhes de design — convenção de exchange/routing-key, contrato de provider, persistência do cursor, modelo de execução — estão em [`docs/architecture.md`](docs/architecture.md).

> Nota técnica: os web services da SEFAZ exigem certificado digital ICP-Brasil real mesmo em homologação. Por isso, só o adaptador que fala com a SEFAZ depende de certificado; o restante é testado contra o **simulador da SEFAZ** do projeto, com o componente ACBr real, e a suíte automatizada não precisa de certificado nenhum. A fidelidade do simulador é a leitura que o projeto faz das Notas Técnicas — validar com um certificado real é exatamente o que falta ([issue #1](https://github.com/fabianoallex/pascal-dfe-broker/issues/1)).

## Compiladores suportados

Delphi e FPC/Lazarus, **desde o início** — mesmo padrão dual-compiler do pascal-amqp-faa. Onde o suporte do ACBr a Lazarus for uma limitação real, o limite fica documentado explicitamente.

| Compilador | Versão usada pelo autor | Observação |
|---|---|---|
| **FPC/Lazarus** | Lazarus 4.0 (FPC 3.2.2) no Windows; FPC 3.2.2 no Linux (Debian 12) | Windows e Linux x86_64. Não testado: ARM, macOS. |
| **Delphi** | Delphi 12 (Athens), Win32 e Win64 | Versões anteriores não foram testadas. O Serviço Windows é só Delphi. |

## Como compilar e rodar

Depende de submódulos em `vendor/`: o broker [pascal-amqp-faa](https://github.com/fabianoallex/pascal-amqp-faa) (~4 MB), o ACBr (clone parcial de ~75 MB) e, só para o simulador, o [Horse](https://github.com/HashLoad/horse). **Não use `--recurse-submodules`**: ele baixaria o monorepo inteiro do ACBr (~1,3 GB).

> **Windows:** clone num caminho **curto** (ex.: `C:\dev\`). O ACBr tem pastas profundas, e um caminho longo faz o Git recusar o clone do submódulo (`Filename too long`).

Estes comandos foram executados num clone limpo e funcionam (Git Bash no Windows, ou shell Linux):

```
git clone https://github.com/fabianoallex/pascal-dfe-broker
cd pascal-dfe-broker
git submodule update --init vendor/pascal-amqp-faa
sh tools/init-acbr-submodule.sh                                  # ~2 min na 1a vez
```

**Broker (host console) com FPC/Lazarus:**

```
lazbuild --add-package-link packages/pascal_dfe_broker.lpk       # uma vez por máquina; sem isso: "Broken dependency"
lazbuild hosts/console/DFeBrokerConsole.lpi
```

**Simulador da SEFAZ** (para a demo e para testes):

```
git submodule update --init vendor/horse
sh simulador/preparar-horse.sh                                   # só Windows/FPC: contorno de 1 linha no Horse
lazbuild simulador/DFeSimulador.lpi
```

**Delphi:** abra `PascalDfeBroker.groupproj` e compile `DFeBrokerConsole` (Win64) e, se quiser, `DFeSimulador`.

**Executar:** `DFeBrokerConsole --config dfe.ini` (modelo comentado em `hosts/console/dfe.exemplo.ini`).

**Dependências de execução — não vêm no repositório:** OpenSSL 3 (`libssl` + `libcrypto`), **libxml2** e os XSDs da NFe (estes já vêm no submódulo do ACBr). Faltar algo só aparece em execução, por isso existe `DFeBrokerConsole --config dfe.ini --verificar-ambiente`: confere tudo e diz o que falta e como obter ([`docs/dependencias-runtime.md`](docs/dependencias-runtime.md)).

**Mais:** demo sintética `tools/demo/DFeDemo` · Serviço Windows em [`hosts/servico/LEIAME.md`](hosts/servico/LEIAME.md) · Linux/systemd em [`docs/linux.md`](docs/linux.md) · testes em [`docs/testes.md`](docs/testes.md).

## Notas Técnicas de referência

Este projeto segue as seguintes versões das Notas Técnicas oficiais (cópias e citações literais em [`docs/referencias/`](docs/referencias/README.md)):

| Documento | Versão | Baixado em |
|---|---|---|
| NT 2014.002 (NFe, Distribuição de DFe) | 1.02d, março/2021 | 2026-09-17 |
| NT 2015/002 (CT-e, Distribuição de DFe) | 1.00a, agosto/2016 | 2026-09-17 |
| NT 2015/002 (MDF-e, Distribuição de DFe) | 1.00b, março/2016 | 2026-09-17 |
| NT 2012/002 (Manifestação do Destinatário) | 1.02, março/2012 | 2026-09-18 |

Se a versão vigente no [Portal Nacional da NF-e](https://www.nfe.fazenda.gov.br/portal) for mais recente que a listada aqui, esta tabela e `docs/referencias/` estão desatualizados — trate como um bug e abra uma issue.

## Antes de usar com o certificado de uma empresa

- **Outro sistema já consulta a Distribuição de DFe desse CNPJ?** (ERP, contador, outro serviço.) A NT 2014.002 (seção 3.11.4, p. 14) diz que aplicações diferentes consultando o **mesmo CNPJ** devem seguir a mesma sequência de NSU, senão a consulta vira **uso indevido** e o **CNPJ** (não o certificado) fica bloqueado por **1 hora** — para todos que consultam. O bloqueio é automático e temporário, mas pode derrubar o sistema de quem já usa. Combine antes; em dúvida, use **homologação** ou um CNPJ que ninguém consulta.
- **Manifestação do destinatário é um ato fiscal**: registra evento na NF-e da empresa (ciência, confirmação, *desconhecimento*, *operação não realizada*). O padrão é `ManifestacaoAutomatica=false`; **não a use em produção sem o aval de quem responde pelo fiscal**.
- O certificado é a identidade digital (e assinatura com valor legal) da empresa: tenha autorização para usá-lo, guarde o `.pfx` e a senha como segredo (`SenhaEnv`, nunca no repositório) e leia a política interna.

## Documentação

| Para… | Leia |
|---|---|
| Ver funcionando, entender e apresentar | [`docs/guia-de-uso.md`](docs/guia-de-uso.md) |
| Tirar dúvidas comuns | [`docs/faq.md`](docs/faq.md) |
| Entender as decisões de projeto | [`docs/architecture.md`](docs/architecture.md) |
| Consumir os documentos em outra linguagem | [`exemplos/consumidor/`](exemplos/consumidor/README.md) |
| Preparar o ambiente (OpenSSL, libxml2, XSDs) | [`docs/dependencias-runtime.md`](docs/dependencias-runtime.md) |
| Rodar como serviço / no Linux | [`hosts/servico/LEIAME.md`](hosts/servico/LEIAME.md) · [`docs/linux.md`](docs/linux.md) |
| Usar o simulador da SEFAZ | [`simulador/LEIAME.md`](simulador/LEIAME.md) |
| Rodar os testes | [`docs/testes.md`](docs/testes.md) |
| Contribuir | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| Reportar um problema de segurança | [`SECURITY.md`](SECURITY.md) |
| English | [`README.en.md`](README.en.md) |

## Licença

Este projeto é licenciado sob [MIT](LICENSE). Os componentes ACBr usados como dependência são licenciados sob **LGPLv3** — a integração é feita preservando a separação de licenciamento (o projeto não incorpora código-fonte ACBr sob a licença MIT deste repositório).

## Contribuindo

Contribuições são muito bem-vindas, especialmente de devs brasileiros com experiência em SEFAZ, ACBr, AMQP ou Lazarus/FPC. **A ajuda mais valiosa hoje é validar em homologação com um certificado real** ([issue #1](https://github.com/fabianoallex/pascal-dfe-broker/issues/1)). Antes de abrir um PR que adicione um novo tipo de documento (CTe, MDFe etc.), leia [`CONTRIBUTING.md`](CONTRIBUTING.md) — a uniformidade entre providers é um requisito do projeto, não um detalhe de estilo.
