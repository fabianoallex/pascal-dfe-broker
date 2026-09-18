# Arquitetura

> Estado: design inicial (2026-09-17), ainda sem código. Este documento fixa as convenções que qualquer provider (NFe, e futuramente CTe/MDFe) precisa seguir, para que o projeto fique uniforme mesmo recebendo contribuições de terceiros.

## Visão geral do fluxo

```
[Certificado digital] --(agenda por certificado+UF)--> [Poller]
                                                            |
                                                  consulta Distribuição de DFe
                                                     (via componente ACBr)
                                                            |
                                                  decodifica docZip (gzip+base64)
                                                            |
                                                    [Provider do tipo de documento]
                                                    (resNFe / resEvento / procDFe)
                                                            |
                                              publica no broker AMQP embutido
                                              (exchange topic, routing-key padronizada)
                                                            |
                                            +-------------------------------+
                                            |     consumidores externos     |
                                            | (qualquer cliente AMQP 0-9-1) |
                                            +-------------------------------+
```

## Contrato de provider (por tipo de documento)

Cada tipo de DFe (NFe, CTe, MDFe, ...) é implementado como um **provider** isolado, para permitir que a comunidade contribua com novos tipos sem tocar no core. Um provider é responsável por:

1. **Identidade**: um código curto e estável (`nfe`, `cte`, `mdfe`, ...) usado em routing-key, namespace de configuração e namespace de persistência de cursor.
2. **Consulta à SEFAZ**: encapsular a chamada ao serviço de Distribuição de DFe correspondente via componente ACBr, recebendo certificado + UF + cursor de NSU atual, devolvendo o lote bruto de retorno.
3. **Decodificação**: extrair do lote os documentos individuais (`resNFe`/equivalente, `resEvento`/equivalente, `procDFe` completo quando presente), normalizando para um evento interno comum (ver "Evento interno padronizado" abaixo).
4. **Publicação**: publicar cada evento decodificado no broker seguindo a convenção de exchange/routing-key (abaixo). O provider não decide *como* publicar (isso é responsabilidade do core), só fornece os dados já normalizados.
5. **Cursor de NSU isolado**: cada provider persiste seu próprio cursor, namespaced por `(tipo de documento, certificado, UF)` — nunca compartilha estado de cursor com outro provider.
6. **Testes com fixtures**: testes de um provider rodam contra respostas gravadas (fixtures) da SEFAZ, nunca contra o ambiente de produção da SEFAZ. Isso é obrigatório para CI de contribuição externa.

**Decidido: auto-registro via `initialization` de unit** (`TDFeProviderRegistry` em `DFe.Provider.pas`) — o core não precisa conhecer `CTe`/`MDFe` em tempo de compilação para que eles existam:

```pascal
initialization
  TDFeProviderRegistry.Registrar(TDFeProviderNfe.Create);
end.
```

Basta a unit do provider estar no `uses` (direto ou indireto) do programa final para o provider ficar disponível — nenhum arquivo central precisa ser editado para adicionar um novo tipo de documento. Isso foi preferido a um registro explícito numa config central porque a alternativa exigiria o core (ou pelo menos um arquivo compartilhado) conhecendo cada tipo de documento de antemão — exatamente o oposto do que o projeto quer para contribuição de terceiros (ver `CONTRIBUTING.md`).

`Registrar` levanta exceção se o `Identificador` já estiver registrado — colisão de nome entre dois providers falha alto e cedo (na inicialização do programa), em vez de um simplesmente sombrear o outro em silêncio. `Todos` devolve uma cópia independente do array interno, para quem chama não conseguir corromper o estado do registry.

**Nota de correção sobre concorrência**: `initialization` de unit roda inteiramente antes do código da aplicação começar, em thread única — não há cenário real de leitura/escrita concorrente no registro, e a implementação não tenta lock nenhum por isso.

### Evento interno padronizado

Formato ainda a definir em detalhe na primeira implementação (NFe), mas precisa carregar no mínimo: tipo de documento, tipo de evento (documento normal vs. evento tipo X), chave de acesso, CNPJ/CPF do detentor da consulta, UF, NSU do item, payload XML (resumo e/ou completo conforme disponível no retorno da distribuição), timestamp de emissão quando disponível. Qualquer provider novo deve produzir esse mesmo formato — é o que garante que um consumidor genérico funcione para NFe, CTe e MDFe sem mudança.

## Fronteira testável sem certificado real

Restrição de domínio que vale registrar explicitamente: os web services da SEFAZ — produção **e** homologação — exigem TLS mútuo com certificado ICP-Brasil válido (e-CNPJ ou e-CPF). Não existe "modo de teste" que dispense certificado real; isso não é uma limitação de implementação, é como o protocolo funciona.

Consequência de design: a única peça do sistema que realmente precisa de um certificado real é o adaptador fino que fala com a SEFAZ (chamada ACBr + parse do retorno bruto). Tudo o resto — scheduler do poller, persistência do cursor de NSU, contrato de provider, normalização pro evento interno, publicação AMQP, convenção de routing-key — é escrito e testado contra uma interface de "cliente de distribuição" (algo como `IDFeDistribuicaoClient`, com um método do tipo `Consultar(Certificado, UF, UltimoNSU): retorno bruto`), da qual:

- a implementação real usa ACBr e um certificado de verdade;
- a implementação de teste (stub) devolve XML de resposta gravado (fixture), sem tocar rede nem certificado nenhum.

Isso mantém a maior parte do projeto desenvolvível e testável em CI sem exigir certificado, CNPJ ou CPF de ninguém — só a implementação real do adaptador e sua validação contra a SEFAZ de verdade dependem disso.

## Convenção de exchange / routing-key

- **Exchange**: topic exchange única, nome `dfe`.
- **Routing-key**: `<tipo>.<categoria>.<uf>.<cnpj>`
  - `<tipo>`: código do provider (`nfe`, `cte`, `mdfe`, ...).
  - `<categoria>`: `documento` para resumo/documento normal, ou `evento.<tipo-evento>` para eventos (ex.: `evento.cancelamento`, `evento.ciencia`).
  - `<uf>`: UF do documento (código IBGE ou sigla — a definir na implementação).
  - `<cnpj>`: CNPJ/CPF (sem máscara) do certificado que fez a consulta — é o "dono" da fila de distribuição, não necessariamente emitente/destinatário do documento.
- Exemplos: `nfe.documento.rs.12345678000199`, `nfe.evento.cancelamento.rs.12345678000199`, `mdfe.documento.sp.98765432000188`.
- Consumidores fazem binding com wildcards (`nfe.evento.#`, `#.rs.#`, `mdfe.#`) — isso é o motivo da routing-key ser hierárquica em vez de um único token.

Esta convenção é a interface pública mais importante do projeto (é o que um consumidor externo depende). Mudá-la depois de haver consumidores em produção é uma mudança que quebra compatibilidade — tratar como tal.

## Persistência do cursor de NSU

Ponto de maior risco técnico do projeto: a SEFAZ rejeita consulta de Distribuição de DFe fora do intervalo mínimo de 1 hora (cStat 656 para NFe/CT-e, 678 para MDF-e — códigos confirmados em `docs/referencias/README.md`), e um cursor de NSU corrompido/perdido causa perda de documento (se avançar sem confirmar entrega) ou reconsulta infinita (se não avançar). Requisitos:

- Persistência tem que sobreviver a crash do processo no meio de uma consulta (sem perder o cursor anterior nem gravar um cursor que não foi de fato consumido).
- Escrita do novo cursor só depois que os documentos daquele lote foram publicados com sucesso no broker — nunca antes.

**Decidido: arquivo próprio** (`src/DFe.CursorStore.Arquivo.pas`, `TDFeCursorStoreArquivo`), não SQLite nem reuso do WAL do pascal-amqp-faa:

- **SQLite** rejeitado por desproporção: traria uma dependência binária nativa (mesmo tipo de complicação de bitness/plataforma que a ACBrLib já traz) para persistir o que na prática são dezenas de pares `(namespace, NSU)`, escritos algumas vezes por hora no máximo.
- **Reuso do WAL do pascal-amqp-faa** rejeitado porque ele foi desenhado para um problema bem mais difícil (durabilidade de mensagens com group commit, segmentos, compactação, milhares de escritas/segundo) — reaproveitá-lo aqui acoplaria o ciclo de vida deste cursor ao ciclo de vida do WAL do broker para um volume de escrita irrisório. Errado tamanho de martelo para o prego.
- **Arquivo próprio**: um arquivo texto plano `namespace=nsu` (uma linha por namespace), sem dependência externa, inspecionável por qualquer um com um editor de texto (valor real para um projeto que quer atrair contribuidor/operador iniciante). Escrita é sempre **grava tudo num arquivo temporário, depois substitui o arquivo real de forma atômica** — nunca escreve no arquivo final diretamente, então um crash a qualquer momento deixa o arquivo real intacto no seu último estado válido.
  - No Windows, `RenameFile` da RTL **não sobrescreve um destino existente** (falha em vez de substituir — comportamento confirmado, diferente do `rename()` POSIX) — por isso a implementação usa `MoveFileEx` com `MOVEFILE_REPLACE_EXISTING` diretamente via `{$IFDEF DFE_WINDOWS}`.
  - No Unix, `RenameFile` já é a substituição atômica de verdade (`rename()` POSIX garante isso quando origem e destino estão na mesma partição).
- **Limitação conhecida e aceita**: não é thread-safe para escritas concorrentes ao mesmo arquivo por múltiplas threads/processos — o orquestrador hoje processa unidades de trabalho sequencialmente (`TDFeOrquestrador.ExecutarCiclo`), então isso não é um problema real ainda. Se o modelo de execução mudar para paralelo, este ponto precisa ser revisitado.

## Modelo de erro e orquestrador

Esboçado em `src/DFe.Errors.pas`, `src/DFe.Types.pas` (classificação de cStat) e `src/DFe.Orquestrador.pas`.

- **Exceção é "a chamada falhou"; cStat é "a chamada funcionou e a SEFAZ respondeu isto".** `IDFeDistribuicaoClient.Consultar` só levanta exceção quando a chamada em si não produz um `TDFeLoteBruto` interpretável: `EDFeComunicacaoFalhou` (rede/TLS/timeout, transitório), `EDFeCertificadoInvalido` (certificado expirado/senha errada/revogado, não transitório — pausa a unidade de trabalho até correção manual) e `EDFeRespostaInvalida` (resposta recebida mas ilegível). A semântica de protocolo da SEFAZ (nenhum documento, documentos localizados, consumo indevido, serviço indisponível) fica no campo `CStat`, interpretado por uma função pura só (`DFe.Types.ClassificarCStat`) — misturar os dois impediria distinguir uma rejeição de protocolo de uma falha de rede olhando só o tipo da exceção.
  **Verificado em 2026-09-17 contra as NTs oficiais** (cópias e citações em `docs/referencias/README.md`): 137/138/108/109 são idênticos entre NFe, CT-e e MDF-e. **O código de "Consumo Indevido" NÃO é universal** — 656 para NFe e CT-e, **678 para MDF-e**. Por isso `ClassificarCStat` recebe o código como parâmetro, e `IDFeProvider.CodigoConsumoIndevido` é quem informa qual é, por tipo de documento.
- **`TDFeOrquestrador` é agnóstico do modelo de execução.** Não cria thread nem timer — expõe `ExecutarCiclo`, que quem hospeda (console/serviço/daemon, ainda em aberto) chama periodicamente. Cada `TDFeUnidadeTrabalho` (par provider+certificado) guarda seu próprio estado de agendamento (`ProximaConsultaEm`), para que consumo indevido ou pausa de um certificado não afete os demais.
- **Sem backoff exponencial — a NT documenta bloqueio fixo de 1 hora com desbloqueio automático**, não escalonamento por violação repetida (ver `docs/referencias/README.md`). Consumo indevido reagenda para `Agora + IntervaloBaseSegundos` (1h), a mesma cadência do ciclo normal — nenhuma penalidade extra inventada além do que a SEFAZ já impõe.
- **Cursor só avança depois de publicar todos os eventos do lote com sucesso**, e o orquestrador continua buscando lotes seguintes no mesmo ciclo enquanto `UltimoNSU < MaxNSU` (até um teto de segurança `DFE_MAX_LOTES_POR_CICLO`, contra loop indevido por bug de interpretação do retorno).
- **Observabilidade é só um hook no-op por enquanto** (`RegistrarAviso`/`RegistrarErro`, protected virtual) — conectar a um mecanismo real é decisão futura; o pascal-amqp-faa já tem um modelo pronto (Fase 4.1, opt-in e read-only) que vale avaliar reaproveitar.

## Modelo de execução

Broker AMQP roda **embutido** no processo (reusa o submódulo server do pascal-amqp-faa) — não há dependência obrigatória de RabbitMQ externo, mas o projeto continua compatível com apontar para um broker externo, por falar AMQP 0-9-1 padrão.

**Decidido: mais de um formato de entrega, todos hosts finos sobre o mesmo core** (`TDFeOrquestrador` + `TDFeHostLoop`, em `src/DFe.Host.Loop.pas`) — mesmo padrão que o pascal-amqp-faa já usa para seus hosts de teste/exemplo (programas separados reusando as mesmas units de core), em vez de escolher um único formato:

- **Console (Windows/Linux, dual-compiler)** — o host universal: bom para desenvolvimento, e também **é** o formato de produção no Linux, rodado sob **systemd** (`Type=simple`, `Restart=on-failure`). Deliberadamente **sem** nenhuma lógica de "virar daemon" (fork duplo, PID file) escrita à mão — isso é exatamente o que o systemd já resolve por fora do processo; escrever essa lógica de novo seria complexidade sem necessidade real.
- **Serviço Windows (Delphi/VCL, `Vcl.SvcMgr.TService`)** — necessário para operação "esqueça e funcione" em ambiente Windows corporativo, onde a maior parte dos ERPs Delphi já roda. É **Delphi-only de propósito**: um Serviço Windows é uma noção inerentemente Windows, e o Lazarus não tem um `TService` equivalente pronto — não há perda real de portabilidade em deixar esse host específico fora do FPC (quem usa Lazarus/Windows tem o host console como alternativa). Mesmo padrão de "sample `Vcl`" que o pascal-amqp-faa já usa (`AutorizadorSimVcl`, `RetaguardaVcl`, etc.).
- **`TDFeHostLoop`** encapsula só a cadência (chama `TDFeOrquestrador.ExecutarCiclo` a cada `DFE_HOST_TICK_SEGUNDOS_PADRAO` = 60s, configurável) — nenhum dos dois hosts reimplementa esse laço. 60s de tick não gera nenhuma consulta extra a SEFAZ: o orquestrador só age de verdade quando `ProximaConsultaEm` permite (cadência real de 1h por unidade); o tick do host só decide com que atraso máximo o processo reage a uma janela que acabou de abrir.
- Consequência direta no orquestrador: como um host roda desassistido por longos períodos, `TDFeOrquestrador.ExecutarCiclo` agora isola cada unidade de trabalho num `try/except` — uma exceção não modelada numa unidade (bug, falha inesperada) é logada via `RegistrarErro` e não derruba o processamento das demais unidades/certificados, nem o processo inteiro.

Ainda **não escritos**: os `.dpr`/`.lpr` dos dois hosts em si (dependem da integração real com ACBrLib e da inicialização do broker embutido, que ainda não existem) — o que existe agora é a mecânica de loop (`DFe.Host.Loop.pas`), testável isoladamente sem nenhuma dessas dependências.

## Integração com ACBr — decidido: ACBrLib

Duas opções de fronteira de integração com ACBr foram avaliadas:

1. **Componentes ACBr clássicos** (VCL/LCL, ex. `TACBrNFe`) — unidades Object Pascal nativas, compiladas direto no binário, sem DLL/SO. Suporte a Lazarus/FPC existe mas é uma árvore de componentes grande, construída Delphi-first; maturidade específica para Distribuição de DFe em Lazarus não foi testada na prática. Para o nosso caso de uso (só consultar distribuição) essa opção importa uma superfície de dependência bem maior do que o necessário — o componente também faz emissão, DANFE, etc.
2. **ACBrLib** — biblioteca compartilhada (DLL/`.so`) que expõe os mesmos componentes por trás de uma API estilo C, desenhada explicitamente para uso cross-platform/cross-linguagem. **Escolhida.**

**Decisão (2026-09-17): usar ACBrLib.** Motivos verificados contra a documentação oficial (não apenas conhecimento de domínio — ver fontes abaixo):

- Confirmada Windows **e Linux**, 32 e 64 bits — é uma característica de design da própria lib, não algo que dependa da maturidade variável dos componentes clássicos no Lazarus.
- Expõe exatamente as funções de Distribuição de DFe que este projeto precisa, para os três tipos de documento: `NFE_DistribuicaoDFePorUltNSU`, `CTE_DistribuicaoDFe`, `MDFE_DistribuicaoDFePorUltNSU` (e as variantes por NSU específico / por chave, espelhando as tags `distNSU`/`consNSU`/`consChNFe` das NTs).
- **A resposta vem em formato INI** — uma seção por documento/evento (`[ResDFe001]`, `[ResEve001]`, ...) com o XML (resumo ou completo) já embutido como campo dentro da seção. Isso é parseável com `TIniFile`/`TMemIniFile` (RTL padrão, dual-compiler) em vez de exigir parsing manual de SOAP + gzip + base64 + XML — simplifica bastante a implementação real de `IDFeDistribuicaoClient`.
- Superfície de integração pequena e ABI-estável: `Inicializar`, `ConfigLerValor`, `DistribuicaoDFePorUltNSU`, `UltimoRetorno`, `Finalizar` — a implementação real de `IDFeDistribuicaoClient` só precisa desse punhado de funções, não do modelo de objetos interno do ACBr.

**Trade-off aceito conscientemente**: passa a existir uma dependência de binário compilado (bitness/plataforma certa) ao lado da aplicação, e a chamada exige o "ritual" de API C em Pascal (buffer `PAnsiChar` pré-alocado, marshaling manual) — mitigado por um wrapper fino que a própria ACBrLib já distribui pronto para Delphi/Lazarus.

**Não verificado ainda** (avaliar quando a implementação real começar): maturidade prática do build Linux/FPC da ACBrLib especificamente para NFe/CTe/MDFe, e o tamanho real de binário/dependências (ex. OpenSSL) que ela carrega consigo.

Fontes: [Sobre o Projeto ACBr](https://projetoacbr.com.br/sobre/), documentação oficial da ACBrLib em `acbr.sourceforge.io/ACBrLib/` (páginas `NFE_DistribuicaoDFePorUltNSU`, `CTE_DistribuicaoDFe`) e do ACBrMonitor (`ModeloRespostaDistribuicaoDFePor.html`), consultadas em 2026-09-17.

## Estrutura de projeto/pacote e framework de teste — decidido

Mesma convenção do `pascal-amqp-faa`, ponto a ponto:

- **Pacote Lazarus** (`packages/pascal_dfe_broker.lpk`) reunindo as units de `src/`, com `RequiredPkgs` só `FCL` — nenhuma dependência de LCL/GUI no core. **Sem pacote Delphi (`.dpk`)**: o `pascal-amqp-faa` também não tem um, porque no Delphi um pacote runtime é só uma forma a mais de gerenciar o quê já é resolvido com uma entrada de "Search Path" apontando pra `src/` — o `.lpk` existe porque o Lazarus usa o próprio mecanismo de pacote para isso, não porque as duas IDEs precisem do mesmo artefato.
- **Testes: dual DUnitX (Delphi) + FPCUnit (FPC), mirados 1:1** — mesmo padrão do `pascal-amqp-faa` (ver `CLAUDE.md` de lá, "Regras da codebase dual"). `tests/Unit/*.pas` são os testes DUnitX com um runner (`DFe.UnitTests.dpr`/`.dproj`); `tests/Unit/fpc/*.pas` são a mesma cobertura portada para FPCUnit, com seu próprio runner (`DFeUnitTestsFpc.lpr`/`.lpi`, console-only — o runner gráfico do `pascal-amqp-faa` não se justifica ainda para uma suite pequena).
- **Primeira suíte real** cobre só o que já é puro/testável sem ACBr nem broker: `DFe.RoutingKeyTests` (convenção de routing-key, incluindo o caso de erro de `TipoEvento` vazio), `DFe.TypesTests` (`ClassificarCStat` — inclui um teste de regressão explícito para o achado real de que 678 não é consumo indevido para um provider configurado com o código do NFe/CT-e) e `DFe.CursorStoreArquivoTests` (round-trip, namespaces isolados, e que a escrita atômica não deixa `.tmp` para trás). Nenhum teste toca ACBr, broker ou rede — todos rodam isolados, sem infraestrutura.
- **Gotcha de FPCUnit herdado do `pascal-amqp-faa`**: `AssertException` do FPCUnit espera um `TRunMethod` (`procedure of object`), não um método anônimo — por isso os testes de FPCUnit que verificam exceção usam um campo + método privado em vez de uma closure (ver `DFe.RoutingKeyTests.Evento_SemTipoEvento_Levanta` em `tests/Unit/fpc/`).

**Atualização (2026-09-18): os dois lados foram compilados e rodados de verdade.** FPC via `lazbuild` (linha de comando) e Delphi via a IDE (linha de comando não funciona nesta máquina) — **17/17 testes passando nos dois compiladores**, 0 erros, 0 falhas, 0 vazamento de memória. A compilação real do lado FPC corrigiu dois defeitos que só apareceram ali: `MOVEFILE_WRITE_THROUGH` não existe na unit `Windows` do FPC 3.2.2, e um warning de variável de retorno gerenciada não inicializada em `TDFeProviderRegistry.Todos` (ver `CLAUDE.md`, "Gotchas dual-compiler", para os detalhes e o comando exato de build). O usuário criou `PascalDfeBroker.groupproj` na raiz (mesmo papel do `AMQP.groupproj` do projeto-base) — todo novo projeto Delphi entra nesse grupo.
