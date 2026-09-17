# DFe Broker

> ⚠️ Projeto em fase de concepção (setembro/2026). Ainda não há código funcional — este README descreve a visão e a arquitetura planejada. Decisões de design ficam registradas em [`CLAUDE.md`](CLAUDE.md) e [`docs/architecture.md`](docs/architecture.md).

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

## Licença

Este projeto é licenciado sob [MIT](LICENSE). Os componentes ACBr usados como dependência são licenciados sob **LGPLv3** — a integração é feita preservando a separação de licenciamento (o projeto não incorpora código-fonte ACBr sob a licença MIT deste repositório).

## Contribuindo

Contribuições são muito bem-vindas, especialmente de devs brasileiros com experiência em SEFAZ, ACBr, AMQP ou Lazarus/FPC. Antes de abrir um PR que adicione um novo tipo de documento (CTe, MDFe, etc.), leia [`CONTRIBUTING.md`](CONTRIBUTING.md) — a uniformidade entre providers é um requisito do projeto, não um detalhe de estilo.
