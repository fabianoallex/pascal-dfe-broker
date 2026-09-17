# pascal-dfe-broker — contexto do projeto

Ferramenta open source para consulta e distribuição de Documentos Fiscais Eletrônicos brasileiros (NFe na v1; CTe, MDFe e demais DFe planejados, idealmente via contribuição de terceiros) via serviço de **Distribuição de DFe** da SEFAZ. Usa componentes **ACBr** (LGPLv3) para a comunicação fiscal e o broker AMQP embutido do projeto-irmão `../pascal-amqp-faa` (MIT, mesmo autor) para distribuir os documentos como mensagens em filas configuráveis pelo usuário. MIT.

**Estado em 2026-09-17: fase de concepção, sem código ainda.** Este arquivo, o README e `docs/architecture.md` são o produto desta fase — as decisões abaixo são o que já está travado; o resto é proposital deixado em aberto para a implementação da v1 (NFe) decidir com componentes de verdade na mão, não adivinhado num documento de design.

## Decisões travadas

1. **Escopo v1 = NFe apenas.** CTe/MDFe vêm depois, com preferência explícita por virem de contribuição de terceiros — por isso o contrato de provider (`docs/architecture.md`) e o `CONTRIBUTING.md` existem antes de haver qualquer provider implementado: a uniformidade entre tipos de documento é requisito de design, não polimento posterior.
2. **Dual-compiler Delphi + FPC/Lazarus desde o início**, mesmo padrão do `pascal-amqp-faa` (`{$I ...inc}`, `MODE DELPHI` no FPC). Motivo do autor: pretende eventualmente usar o projeto com Lazarus em algo próprio, mas sem comprometer funcionalidade por causa disso — onde o ACBr for uma limitação real em Lazarus, documentar o limite, não forçar.
3. **Broker AMQP embutido** (reusa o submódulo server do `pascal-amqp-faa`, que já roda dentro do processo hospedeiro sem exigir infraestrutura externa), com compatibilidade para apontar a um AMQP externo (RabbitMQ etc.) por falar o protocolo 0-9-1 padrão.
4. **Convenção de routing-key fixada**: `<tipo>.<categoria>.<uf>.<cnpj>` numa exchange topic única `dfe` (ver `docs/architecture.md`). É a interface pública mais importante do projeto — não muda por decisão de PR isolado depois de haver consumidores reais.
5. **Licenciamento**: MIT neste repositório; ACBr como dependência LGPLv3, integração preservando a separação (sem incorporar código ACBr sob a licença MIT deste repo).

## Explicitamente em aberto (decidir na implementação, não aqui)

- **Fronteira de integração com ACBr**: componentes clássicos (VCL/LCL) vs. ACBrLib (API estilo C, mais cross-platform). Decidir com os componentes instalados e testados de verdade.
- **Formato de entrega/hospedagem**: console, Windows Service, daemon Linux — provavelmente mais de um, com um core sem dependência de GUI/serviço por baixo (mesmo padrão de múltiplos hosts finos que o `pascal-amqp-faa` já usa).
- **Mecanismo de persistência do cursor de NSU**: arquivo próprio vs. reuso do WAL do `pascal-amqp-faa` vs. SQLite. Requisito fixo: nunca avançar o cursor antes de os documentos daquele lote terem sido publicados com sucesso no broker.
- **Mecanismo de auto-registro de provider** (unit initialization vs. registro explícito em config).

## Onde procurar mais contexto

- `docs/architecture.md`: fluxo completo, contrato de provider, convenção de routing-key, riscos técnicos do cursor de NSU.
- `CONTRIBUTING.md`: o que é exigido de um PR que adiciona um novo tipo de documento.
- `../pascal-amqp-faa/CLAUDE.md`: arquitetura e regras dual-compiler do broker AMQP que serve de base (regras de "o que não usar no FPC" valem aqui igual, uma vez que o código comece a ser escrito).
