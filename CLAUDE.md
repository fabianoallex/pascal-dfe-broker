# pascal-dfe-broker — contexto do projeto

Ferramenta open source para consulta e distribuição de Documentos Fiscais Eletrônicos brasileiros (NFe na v1; CTe, MDFe e demais DFe planejados, idealmente via contribuição de terceiros) via serviço de **Distribuição de DFe** da SEFAZ. Usa componentes **ACBr** (LGPLv3) para a comunicação fiscal e o broker AMQP embutido do projeto-irmão `../pascal-amqp-faa` (MIT, mesmo autor) para distribuir os documentos como mensagens em filas configuráveis pelo usuário. MIT.

**Estado em 2026-09-18: os dois compiladores compilam e os testes passam de verdade nos dois.** FPC 3.2.2 via `lazbuild` (linha de comando, `C:\lazarus4.0`) **e** Delphi via a IDE (linha de comando não funciona nesta máquina, confirmado pelo usuário) — **17/17 testes passando nos dois lados**, 0 falhas, 0 erros, 0 vazamento de memória (heaptrc no FPC; "Tests Leaked: 0" no DUnitX). A compilação real (não só leitura) já pegou dois defeitos reais só no lado FPC (ver "Gotchas dual-compiler"). Existem interfaces completas (`DFe.Types`, `DFe.Provider`, `DFe.Errors`, `DFe.Publicador`) e implementações reais e testadas de verdade nos dois compiladores de tudo que independe de ACBr/broker: `DFe.RoutingKey`, `DFe.CursorStore.Arquivo`; `DFe.Orquestrador` + `DFe.Host.Loop` compilam mas ainda não têm teste próprio. O que falta para ter um binário de verdade está em "Próximos marcos" no final deste arquivo.

**Grupo de projeto Delphi na raiz: `PascalDfeBroker.groupproj`** (criado pelo usuário em 2026-09-18, mesmo papel do `AMQP.groupproj` do `pascal-amqp-faa`). **Todo novo projeto Delphi (`.dproj`) deve ser adicionado a esse grupo** — é o que permite compilar tudo de uma vez pela IDE nesta máquina. Hoje só tem `tests\Unit\DFe.UnitTests.dproj`; os hosts (console, serviço Windows) entram aqui quando forem escritos.

**Como recompilar/rodar os testes:**
- **FPC** (linha de comando funciona nesta máquina):
  ```
  "C:\lazarus4.0\lazbuild.exe" --add-package-link packages\pascal_dfe_broker.lpk   # so' na 1a vez
  "C:\lazarus4.0\lazbuild.exe" tests\Unit\fpc\DFeUnitTestsFpc.lpi
  tests\Unit\fpc\DFeUnitTestsFpc.exe --all --format=plain
  ```
- **Delphi** (só pela IDE nesta máquina — linha de comando não funciona): abrir `PascalDfeBroker.groupproj`, compilar e rodar `DFe.UnitTests`.

**Nota sobre `tests\Unit\DFe.UnitTests.dproj`**: a IDE reescreveu esse arquivo ao abrir (expandiu para a matriz completa de plataformas que o Delphi 23 gerencia por padrão — Android/iOS/OSX/etc. — em vez da versão enxuta Win32/Win64 que foi escrita à mão nesta sessão). Isso é comportamento normal da IDE, não um erro; a versão no disco é a que compila e passa os 17 testes, então é ela quem vale.

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
10. **Auto-registro de provider via `initialization` de unit** (`TDFeProviderRegistry` em `DFe.Provider.pas`) — preferido a registro explícito numa config central porque essa alternativa exigiria o core conhecendo cada tipo de documento de antemão, o oposto do que o projeto quer para contribuição de terceiros. `Registrar` levanta exceção em colisão de `Identificador`. Ver o snippet exato em `CONTRIBUTING.md`.
11. **Estrutura de projeto: pacote Lazarus (`packages/pascal_dfe_broker.lpk`), sem pacote Delphi** (mesma assimetria do `pascal-amqp-faa`: Delphi resolve via Search Path direto em `src/`, não precisa de um `.dpk` pra isso). **Framework de teste: dual DUnitX + FPCUnit espelhados**, mesmo padrão do `pascal-amqp-faa` — `tests/Unit/*.pas` (DUnitX) e `tests/Unit/fpc/*.pas` (FPCUnit), cobrindo por enquanto só o que é puro/testável sem ACBr nem broker (`DFe.RoutingKey`, `DFe.Types.ClassificarCStat` — com teste de regressão explícito do achado 656≠678 —, `DFe.CursorStore.Arquivo`). Ver `docs/architecture.md`, "Estrutura de projeto/pacote e framework de teste".

Com isso, todas as decisões que ficaram em aberto ao longo da concepção e da estruturação inicial estão fechadas.

## Gotchas dual-compiler já encontrados

- **`SysUtils.RenameFile` NÃO se comporta igual nos dois compiladores/plataformas.** No Windows (Delphi e FPC), falha em vez de sobrescrever um destino já existente — diferente do `rename()` POSIX. Para substituição atômica de arquivo no Windows, usar `MoveFileEx` com `MOVEFILE_REPLACE_EXISTING` (unit `Windows`, sob `{$IFDEF DFE_WINDOWS}`) — `RenameFile` sozinho não serve para o padrão "grava em .tmp, substitui atômico" que `TDFeCursorStoreArquivo` depende. No Unix, `RenameFile` é o `rename()` POSIX de verdade e já substitui atomicamente.
- **`MOVEFILE_WRITE_THROUGH` não existe na unit `Windows` do FPC 3.2.2** (erro de compilação real, achado em 2026-09-18) — só `MOVEFILE_REPLACE_EXISTING` está declarada. Não era essencial pra garantia que importa (substituição atômica de conteúdo, não fsync de hardware), então foi removida em vez de contornada.
- **Nunca usar `Move`/`CopyMemory` sobre um array de interfaces (ou qualquer tipo gerenciado)** — copia os bytes sem incrementar refcount, deixando as duas cópias com contagem errada (destruição prematura). Copiar elemento a elemento (ver `TDFeProviderRegistry.Todos`).
- **`lazbuild` exige o `.lpk` registrado antes do primeiro build** (`Error: Broken dependency`) — rodar `lazbuild --add-package-link packages\pascal_dfe_broker.lpk` uma vez resolve; depois disso builds normais funcionam.
- **`packages/pascal_dfe_broker.pas` é gerado pelo Lazarus na primeira compilação do `.lpk`** (container que só lista as units do pacote) — é versionado no git, igual ao `pascal_amqp_faa.pas` do projeto-base, porque o `.lpk` depende dele existir pra compilar sem reabrir a IDE.

## Próximos marcos (nenhum decidido ainda, nem discutido em detalhe)

- **Testes para `DFe.Orquestrador` e `DFe.Host.Loop`** — compilam, mas ainda não têm suíte própria (precisam de um `IDFeDistribuicaoClient`/`IDFePublicador`/`IDFeCursorStore`/`IDFeProvider` fake para testar isolado).
- **Formato de configuração** (INI/JSON/YAML?) para certificados, UFs e tipos de documento habilitados — é o que vai efetivamente instanciar `TDFeUnidadeTrabalho` e decidir quais providers registrados ficam ativos.
- **Implementação real de `IDFeDistribuicaoClient` via ACBrLib** (o adaptador que efetivamente fala com a SEFAZ) e do provider NFe (`IDFeProvider.Decodificar` para `resNFe`/`resEvento`/`procNFe`).
- **Manifestação automática do destinatário**: cogitada, nunca decidida se entra na v1 ou fica para depois.

## Onde procurar mais contexto

- `docs/architecture.md`: fluxo completo, contrato de provider, convenção de routing-key, riscos técnicos do cursor de NSU, decisão de integração com ACBr, estrutura de projeto/teste.
- `tests/Unit/` (DUnitX) e `tests/Unit/fpc/` (FPCUnit): suíte de testes atual, mirrored 1:1 — olhar aqui antes de mudar qualquer unit pura (`DFe.RoutingKey`, `DFe.Types`, `DFe.CursorStore.Arquivo`) pra saber o que já está coberto.
- `docs/referencias/`: cópias e citações literais das NTs oficiais de Distribuição de DFe — fonte de verdade para qualquer regra de protocolo (cStat, intervalos, formato de lote).
- `CONTRIBUTING.md`: o que é exigido de um PR que adiciona um novo tipo de documento.
- `../pascal-amqp-faa/CLAUDE.md`: arquitetura e regras dual-compiler do broker AMQP que serve de base (regras de "o que não usar no FPC" valem aqui igual, uma vez que o código comece a ser escrito).
