# pascal-dfe-broker — contexto do projeto

Ferramenta open source para consulta e distribuição de Documentos Fiscais Eletrônicos brasileiros (NFe na v1; CTe, MDFe e demais DFe planejados, idealmente via contribuição de terceiros) via serviço de **Distribuição de DFe** da SEFAZ. Usa componentes **ACBr** (LGPLv3) para a comunicação fiscal e o broker AMQP embutido do projeto-irmão `../pascal-amqp-faa` (MIT, mesmo autor) para distribuir os documentos como mensagens em filas configuráveis pelo usuário. MIT.

**Estado em 2026-09-17: fase de concepção, sem código ainda.** Este arquivo, o README e `docs/architecture.md` são o produto desta fase — as decisões abaixo são o que já está travado; o resto é proposital deixado em aberto para a implementação da v1 (NFe) decidir com componentes de verdade na mão, não adivinhado num documento de design.

## Decisões travadas

1. **Escopo v1 = NFe apenas.** CTe/MDFe vêm depois, com preferência explícita por virem de contribuição de terceiros — por isso o contrato de provider (`docs/architecture.md`) e o `CONTRIBUTING.md` existem antes de haver qualquer provider implementado: a uniformidade entre tipos de documento é requisito de design, não polimento posterior.
2. **Dual-compiler Delphi + FPC/Lazarus desde o início**, mesmo padrão do `pascal-amqp-faa` (`{$I ...inc}`, `MODE DELPHI` no FPC). Motivo do autor: pretende eventualmente usar o projeto com Lazarus em algo próprio, mas sem comprometer funcionalidade por causa disso — onde o ACBr for uma limitação real em Lazarus, documentar o limite, não forçar.
3. **Broker AMQP embutido** (reusa o submódulo server do `pascal-amqp-faa`, que já roda dentro do processo hospedeiro sem exigir infraestrutura externa), com compatibilidade para apontar a um AMQP externo (RabbitMQ etc.) por falar o protocolo 0-9-1 padrão.
4. **Convenção de routing-key fixada**: `<tipo>.<categoria>.<uf>.<cnpj>` numa exchange topic única `dfe` (ver `docs/architecture.md`). É a interface pública mais importante do projeto — não muda por decisão de PR isolado depois de haver consumidores reais.
5. **Licenciamento**: MIT neste repositório; ACBr como dependência LGPLv3, integração preservando a separação (sem incorporar código ACBr sob a licença MIT deste repo).
6. **Integração com ACBr via ACBrLib** (API estilo C, DLL/`.so`), não os componentes clássicos — confirmado Windows+Linux 32/64 bits, expõe `NFE_DistribuicaoDFePorUltNSU`/`CTE_DistribuicaoDFe`/`MDFE_DistribuicaoDFePorUltNSU`, resposta em INI já com o XML embutido por seção (parseável com `TIniFile` da RTL, dual-compiler). Ver `docs/architecture.md`, "Integração com ACBr — decidido: ACBrLib", para as fontes e o trade-off aceito (dependência de binário compilado). Maturidade prática do build Linux/FPC ainda não testada.
7. **Regras de Distribuição de DFe verificadas contra as NTs oficiais** (não mais suposição): intervalo mínimo 1h sem escalonamento de backoff; código de cStat de consumo indevido NÃO é universal (656 NFe/CT-e, 678 MDF-e) — ver `docs/referencias/README.md`.
8. **Cursor de NSU persistido em arquivo próprio** (`src/DFe.CursorStore.Arquivo.pas`, `TDFeCursorStoreArquivo`) — texto plano `namespace=nsu`, sem cache em memória (sempre lê/escreve o arquivo inteiro; volume é irrisório), escrita sempre via arquivo temporário + substituição atômica. SQLite e reuso do WAL do `pascal-amqp-faa` foram avaliados e rejeitados por desproporção — ver `docs/architecture.md`, "Persistência do cursor de NSU", para a justificativa completa. **Não é thread-safe para escritas concorrentes** — assume o orquestrador sequencial atual.
9. **Formato de entrega: mais de um host fino, mesmo core.** Console (dual-compiler, Windows/Linux — no Linux **é** o host de produção, rodado sob systemd, sem daemonização própria) + Serviço Windows (Delphi/VCL `TService`, Delphi-only de propósito — Serviço Windows é uma noção inerentemente Windows). Ambos usam `TDFeHostLoop` (`src/DFe.Host.Loop.pas`) para a cadência de tick (60s padrão, configurável) sobre `TDFeOrquestrador.ExecutarCiclo`. Consequência: `ExecutarCiclo` agora isola cada unidade de trabalho num `try/except` (uma unidade com bug não derruba as demais nem o processo). Os `.dpr`/`.lpr` dos hosts em si ainda não existem (dependem da integração ACBrLib real). Ver `docs/architecture.md`, "Modelo de execução".

## Gotchas dual-compiler já encontrados

- **`SysUtils.RenameFile` NÃO se comporta igual nos dois compiladores/plataformas.** No Windows (Delphi e FPC), falha em vez de sobrescrever um destino já existente — diferente do `rename()` POSIX. Para substituição atômica de arquivo no Windows, usar `MoveFileEx` com `MOVEFILE_REPLACE_EXISTING` (unit `Windows`, sob `{$IFDEF DFE_WINDOWS}`) — `RenameFile` sozinho não serve para o padrão "grava em .tmp, substitui atômico" que `TDFeCursorStoreArquivo` depende. No Unix, `RenameFile` é o `rename()` POSIX de verdade e já substitui atomicamente.

## Explicitamente em aberto (decidir na implementação, não aqui)

- **Mecanismo de auto-registro de provider** (unit initialization vs. registro explícito em config).

## Onde procurar mais contexto

- `docs/architecture.md`: fluxo completo, contrato de provider, convenção de routing-key, riscos técnicos do cursor de NSU, decisão de integração com ACBr.
- `docs/referencias/`: cópias e citações literais das NTs oficiais de Distribuição de DFe — fonte de verdade para qualquer regra de protocolo (cStat, intervalos, formato de lote).
- `CONTRIBUTING.md`: o que é exigido de um PR que adiciona um novo tipo de documento.
- `../pascal-amqp-faa/CLAUDE.md`: arquitetura e regras dual-compiler do broker AMQP que serve de base (regras de "o que não usar no FPC" valem aqui igual, uma vez que o código comece a ser escrito).
