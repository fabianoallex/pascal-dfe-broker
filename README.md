# DFe Broker

[![Linux (FPC)](https://github.com/fabianoallex/pascal-dfe-broker/actions/workflows/linux.yml/badge.svg)](https://github.com/fabianoallex/pascal-dfe-broker/actions/workflows/linux.yml)

> ⚠️ **Estado (setembro/2026): funciona de ponta a ponta contra um simulador da SEFAZ, mas nunca foi executado contra a SEFAZ real** — o autor não tem certificado digital ICP-Brasil. Testado em Delphi (Win32/Win64) e FPC (Windows e Linux/Docker); o host console sobe e para limpo nos dois compiladores. Não use em produção sem validar com o seu certificado (em homologação primeiro) e, se puder, [conte o que encontrou](https://github.com/fabianoallex/pascal-dfe-broker/issues/1). Decisões de design ficam registradas em [`CLAUDE.md`](CLAUDE.md) e [`docs/architecture.md`](docs/architecture.md).

Ferramenta open source para consulta e distribuição de Documentos Fiscais Eletrônicos brasileiros (NFe na v1; CTe, MDFe e demais DFe planejados) via serviço de **Distribuição de DFe** da SEFAZ, publicando os documentos e eventos recebidos em filas AMQP configuráveis pelo usuário — sem exigir infraestrutura de mensageria externa para funcionar.

## Por quê

Automatizar a consulta de documentos fiscais que envolvem sua empresa (Distribuição de DFe) hoje significa, na prática, escolher entre pagar por um SaaS fechado ou implementar o fluxo inteiro (NSU, certificado, XML, manifestação) na unha dentro do próprio ERP. O DFe Broker propõe uma terceira via: uma ferramenta **open source e auto-hospedada**, que qualquer empresa ou dev roda com o próprio certificado digital, entregando os documentos como mensagens numa fila — para que qualquer sistema (Delphi, Python, Node, Java, o que for) consuma via um cliente AMQP padrão, sem nenhum acoplamento com Object Pascal.

## Visão geral da arquitetura

- **Poller por certificado** — para cada certificado digital configurado, consulta periodicamente o serviço de Distribuição de DFe da SEFAZ correspondente, respeitando os intervalos mínimos exigidos pela própria SEFAZ (consulta fora do intervalo é rejeitada), e mantém o cursor de NSU persistido de forma confiável — é o ponto de maior risco técnico do projeto: um cursor corrompido significa documento perdido ou reconsultado para sempre.
- **Providers por tipo de documento** — a lógica específica de cada tipo de DFe (NFe na v1; CTe e MDFe planejados, idealmente via contribuição da comunidade) fica isolada atrás de um contrato comum, para que novos tipos entrem sem tocar no core do broker. Ver [`CONTRIBUTING.md`](CONTRIBUTING.md).
- **Broker AMQP embutido** — usa o broker AMQP 0-9-1 embutido do [pascal-amqp-faa](https://github.com/fabianoallex/pascal-amqp-faa) rodando dentro do próprio processo. Não exige RabbitMQ (ou outro broker) externo para funcionar, mas continua compatível com um, por falar o protocolo AMQP 0-9-1 padrão — quem já tem infraestrutura de mensageria pode apontar para ela.
- **Integração fiscal via ACBr** — os componentes do [projeto ACBr](https://www.acbr.com.br/) cuidam da comunicação com a SEFAZ, do certificado digital e do parsing dos XMLs de retorno.

Detalhes de design — convenção de exchange/routing-key, contrato de provider, persistência do cursor de NSU, modelo de execução (serviço Windows, console, daemon Linux) — estão em [`docs/architecture.md`](docs/architecture.md).

> Nota técnica: os web services da SEFAZ exigem certificado digital ICP-Brasil real mesmo em homologação. Por isso, apenas o adaptador que fala com a SEFAZ depende de certificado — o resto do sistema (poller, cursor de NSU, contrato de provider, publicação AMQP) é desenvolvido e testado contra fixtures gravadas, sem precisar de certificado nenhum. Ver "Fronteira testável sem certificado real" em `docs/architecture.md`.

## Compiladores suportados

Delphi e FPC/Lazarus, **desde o início** — mesmo padrão dual-compiler do pascal-amqp-faa. Onde o suporte do ACBr a Lazarus for uma limitação real, o limite fica documentado explicitamente, não escondido nem contornado às custas de funcionalidade.

## Notas Técnicas de referência

Este projeto segue as seguintes versões das Notas Técnicas oficiais de Distribuição de DFe (cópias e citações literais em [`docs/referencias/`](docs/referencias/README.md)):

| Documento | Versão | Baixado em |
|---|---|---|
| NT 2014.002 (NFe) | 1.02d, março/2021 | 2026-09-17 |
| NT 2015/002 (CT-e) | 1.00a, agosto/2016 | 2026-09-17 |
| NT 2015/002 (MDF-e) | 1.00b, março/2016 | 2026-09-17 |

Se a versão vigente no [Portal Nacional da NF-e](https://www.nfe.fazenda.gov.br/portal) for mais recente que a listada aqui, esta tabela e `docs/referencias/` estão desatualizados — trate como um bug e abra uma issue.

## Como compilar e rodar

Depende de dois submódulos em `vendor/`: o broker [pascal-amqp-faa](https://github.com/fabianoallex/pascal-amqp-faa) (~2 MB) e o ACBr (clone parcial de ~70 MB). **Não use `--recurse-submodules`**: ele baixaria o monorepo inteiro do ACBr (~1,3 GB). Depois de clonar:

```
git submodule update --init vendor/pascal-amqp-faa
./tools/init-acbr-submodule.sh
```

- **FPC/Lazarus:** `lazbuild hosts/console/DFeBrokerConsole.lpi`
- **Delphi:** abrir `PascalDfeBroker.groupproj` e compilar `DFeBrokerConsole` (Win64).
- **Executar:** `DFeBrokerConsole --config dfe.ini` (modelo em `hosts/console/dfe.exemplo.ini`); `--verificar-ambiente` só confere OpenSSL, libxml2 e XSDs ([`docs/dependencias-runtime.md`](docs/dependencias-runtime.md)).
- **Ver funcionando sem certificado / consumir os documentos:** `tools/demo/DFeDemo` e os exemplos em Python em [`exemplos/consumidor/`](exemplos/consumidor/README.md).
- **Testes:** ver "Como recompilar/rodar os testes" no [`CLAUDE.md`](CLAUDE.md); em Linux, `tools/docker/testar-linux.sh`.

## Licença

Este projeto é licenciado sob [MIT](LICENSE). Os componentes ACBr usados como dependência são licenciados sob **LGPLv3** — a integração é feita preservando a separação de licenciamento (o projeto não incorpora código-fonte ACBr sob a licença MIT deste repositório).

## Contribuindo

Contribuições são muito bem-vindas, especialmente de devs brasileiros com experiência em SEFAZ, ACBr, AMQP ou Lazarus/FPC. Antes de abrir um PR que adicione um novo tipo de documento (CTe, MDFe, etc.), leia [`CONTRIBUTING.md`](CONTRIBUTING.md) — a uniformidade entre providers é um requisito do projeto, não um detalhe de estilo.
