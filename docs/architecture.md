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
- **Suíte real (35 testes)** cobre tudo que já é puro/testável sem ACBr nem broker: `DFe.RoutingKeyTests` (convenção de routing-key, incluindo o caso de erro de `TipoEvento` vazio), `DFe.TypesTests` (`ClassificarCStat` — inclui um teste de regressão explícito para o achado real de que 678 não é consumo indevido para um provider configurado com o código do NFe/CT-e), `DFe.CursorStoreArquivoTests` (round-trip, namespaces isolados, e que a escrita atômica não deixa `.tmp` para trás), `DFe.ProviderRegistryTests` (colisão de identificador, cópia independente em `Todos`), `DFe.OrquestradorTests` (agendamento, os 3 tipos de exceção modelada, consumo indevido, loop multi-lote, isolamento por unidade) e `DFe.HostLoopTests` (delegação para `ExecutarCiclo`, primeiro tick imediato ao entrar em `Executar`, parada determinística). Tudo via dublês de teste em `DFe.TestDoubles.pas`, incluindo uma subclasse de `TDFeOrquestrador` com relógio controlável e uma de `TDFeHostLoop` com `Esperar` no-op — nenhum teste depende de `Sleep`/tempo real. Nenhum teste toca ACBr, broker ou rede — todos rodam isolados, sem infraestrutura.
- **Gotcha de FPCUnit herdado do `pascal-amqp-faa`**: `AssertException` do FPCUnit espera um `TRunMethod` (`procedure of object`), não um método anônimo — por isso os testes de FPCUnit que verificam exceção usam um campo + método privado em vez de uma closure (ver `DFe.RoutingKeyTests.Evento_SemTipoEvento_Levanta` em `tests/Unit/fpc/`).

**Atualização (2026-09-18): compilado e rodado de verdade nos dois lados.** FPC via `lazbuild` (linha de comando) e Delphi via a IDE (linha de comando não funciona nesta máquina, `PascalDfeBroker.groupproj`) — **35/35 nos dois compiladores** (nesse ponto), 0 erros, 0 falhas, 0 vazamento de memória. A compilação real corrigiu defeitos reais que só apareceram assim: `MOVEFILE_WRITE_THROUGH` não existe na unit `Windows` do FPC 3.2.2; um warning de variável de retorno gerenciada não inicializada em `TDFeProviderRegistry.Todos`; um vazamento de memória real (heaptrc) quando um objeto é construído inline como argumento de interface numa chamada que levanta exceção; e outro vazamento real por um fixture de teste (`FCursorStore`) criado no `Setup` mas usado só por parte dos testes de uma fixture — ver `CLAUDE.md`, "Gotchas dual-compiler", para os detalhes e o comando exato de build. O usuário criou `PascalDfeBroker.groupproj` na raiz (mesmo papel do `AMQP.groupproj` do projeto-base) — todo novo projeto Delphi entra nesse grupo.

## Formato de configuração — decidido: INI

Mesma filosofia de `DFe.CursorStore.Arquivo` e da própria resposta da ACBrLib: texto plano, sem dependência externa. JSON foi descartado porque Delphi (`System.JSON`) e FPC (`fpjson`) têm APIs diferentes — exigiria uma camada de abstração só para isso; YAML não tem suporte nativo em nenhum dos dois compiladores, exigiria biblioteca de terceiros. INI usa a unit `IniFiles` da RTL, idêntica nos dois.

```ini
[dfe]
IntervaloBaseSegundos=3600   ; opcional, default DFE_INTERVALO_BASE_SEGUNDOS_PADRAO
TickSegundos=60              ; opcional, default DFE_HOST_TICK_SEGUNDOS_PADRAO
CursorPath=cursores.dat      ; opcional

[certificado:matriz]
Provider=nfe
CnpjCpf=12345678000199
UF=RS
Ativo=true                  ; opcional, default true
ManifestacaoAutomatica=false ; opcional, default false -- ver "Manifestação do destinatário"
```

Implementado em `src/DFe.Config.pas`:

- **`CarregarConfig`** lê o arquivo e valida cada seção `certificado:*` — levanta exceção nomeando a seção se faltar `Provider`, `CnpjCpf` ou `UF`. Falha alto e cedo, na inicialização do host, em vez de criar uma unidade de trabalho quebrada em silêncio.
- **Campos de certificado digital "de verdade" (caminho do `.pfx`, senha) ficam FORA deste arquivo de propósito** — pertencem à implementação real de `IDFeDistribuicaoClient` (ACBrLib, ainda não escrita), nunca ao core, que só precisa saber `CnpjCpf`/`UF`/qual provider usar.
- `TDFeClientFactory` é `of object` (método ligado), não `reference to` — closures não existem no FPC 3.2 (mesma regra herdada do `pascal-amqp-faa`).

### Mais de um certificado, inclusive do mesmo CNPJ — decidido

Cenário motivador: um certificado prestes a vencer, com um novo já configurado para assumir sem reiniciar a aplicação. Duas descobertas moldaram o desenho:

1. **O NSU da Distribuição de DFe pertence ao CNPJ/UF consultado, não ao certificado que autentica a chamada.** Dois certificados do mesmo CNPJ compartilham a mesma "posição de leitura" na SEFAZ — e como o namespace do cursor já era `<tipo>/<cnpjCpf>/<uf>` (nunca o alias, ver `MontarNamespaceCursor`), a troca de certificado **já não duplica nem perde documento**, sem nenhuma mudança de código.
2. **Mas os dois nunca podem estar ativos ao mesmo tempo**: a SEFAZ limita consulta por CNPJ, não por certificado — dois certificados consultando o mesmo `(tipo, CnpjCpf, UF)` simultaneamente dobra a taxa de consulta e arrisca consumo indevido (656/678).

Daí o campo **`Ativo`** (default `true`) por seção `[certificado:*]`, e uma validação nova em `CarregarConfig`: **recusa a config se dois certificados ativos compartilharem `(Provider, CnpjCpf, UF)`**. A troca de certificado é sempre "ativa o novo e desativa o velho" via config, nunca os dois ligados ao mesmo tempo.

**Correção real (2026-09-18, achada pelo usuário rodando o Delphi):** `Ativo` é interpretado por uma função própria (`DFe.Config.LerBooleano`), não por `TCustomIniFile.ReadBool` — no Delphi, `ReadBool` delega para `ReadInteger`/`StrToIntDef`, que não entende o texto `"false"`, e `Ativo=false` virava silenciosamente `True` (o default passado). O FPC interpreta o texto direto e não tem esse problema — os testes passaram de primeira no FPC e esconderam o bug até rodar no Delphi de verdade. Ver `CLAUDE.md`, "Gotchas dual-compiler", para os detalhes.

**Ativação manual via config, não detecção automática de vencimento** — cogitado e adiado: inspecionar a validade real de um certificado X.509 exige a implementação real via ACBrLib, que ainda não existe (ACBrLib não está instalada nesta máquina de desenvolvimento). Revisitar quando essa peça existir.

### Recarregar sem reiniciar — decidido: polling no tick do host

`MontarUnidades` foi **substituída por `RecarregarConfig`**, que reconcilia uma `TDFeConfig` com um `TDFeOrquestrador` **já em execução**, em vez de só construir um array de unidades do zero:

- alias novo → cria a unidade (via `AClientFactory`) e adiciona ao orquestrador, já com `Pausada = not Ativo`;
- alias existente → **nunca recriado** — só sincroniza `Pausada` com o `Ativo` atual (preserva `ProximaConsultaEm` e todo o resto do estado de agendamento);
- alias que sumiu da config → **pausado, nunca destruído** (destruir uma unidade em potencial uso seria mais arriscado que só pausá-la).

Carga inicial e recarga a quente usam a mesma função: um orquestrador recém-criado (sem unidades) trata todo alias como "novo", produzindo o mesmo resultado que `MontarUnidades` produzia antes.

**`TDFeConfigWatcher`** embrulha isso para o host: no construtor já faz a carga inicial (chama `Recarregar`), e expõe `VerificarRecarregar` — chamado periodicamente (a decisão foi **reaproveitar o tick do `TDFeHostLoop`**, sem mecanismo de sinalização novo) — que só recarrega de fato se a data de modificação do arquivo mudou desde a última vez. Como `TDFeHostLoop.Tick` já é virtual (ver seção "Modelo de execução"), um host real conecta isso sobrescrevendo `Tick` para chamar `inherited Tick` seguido de `ConfigWatcher.VerificarRecarregar` — nenhuma mudança adicional em `TDFeHostLoop` foi necessária.

Gatilho explícito (sinal do SO, comando externo) foi cogitado e descartado por enquanto: reaproveitar o tick já existente não pede nenhuma infraestrutura nova.

**Testado de verdade (2026-09-18): 52/52 no FPC** (`DFe.ConfigTests`, incluindo `RecarregarConfig` — cria/sincroniza/pausa — e `TDFeConfigWatcher`, com data de modificação controlável via `TDFeConfigWatcherTestavel` em vez de depender do mtime real de um arquivo). 0 erros, 0 falhas, 0 vazamento de memória. Lado Delphi ainda não recompilado com esses testes (arquivos `.dpr`/`.dproj` já referenciam os mesmos arquivos, que só cresceram de conteúdo — não precisam de nova edição, só recompilar).

## Manifestação do destinatário — decidido: comando simples, não RPC clássico

Cenário motivador: a manifestação (Confirmação/Ciência/Desconhecimento/Operação não Realizada, no caso da NFe) precisa ser configurável por certificado para ser automática ou exigir autorização externa — e, com múltiplos CNPJ configurados, um pode querer automática enquanto outro exige manual. Implementado em `src/DFe.Manifestacao.pas`.

**Desacoplamento do orquestrador**: `TDFeOrquestrador` não sabe o que é "manifestação". Ganhou só um hook opcional, `AoPublicarDocumento` (`nil` por padrão — nenhuma mudança de comportamento para quem não usa), chamado depois que um evento de **categoria documento** (nunca evento fiscal) é publicado com sucesso. É uma `property` de tipo `procedure(...) of object`, não um método virtual — conectar manifestação automática (ou qualquer reação futura) não exige subclassificar `TDFeOrquestrador`.

**`IDFeManifestador` é uma capacidade opcional de provider**, verificada em runtime via `Supports(provider, IDFeManifestador, ...)` — não faz parte de `IDFeProvider`, porque nem todo tipo de documento tem "manifestação do destinatário" (é um conceito específico de NFe). Simétrica a `IDFeDistribuicaoClient`/`IDFeProvider`: só levanta exceção (`DFe.Errors`) quando a chamada em si falha antes de existir uma resposta interpretável — rejeição de protocolo da SEFAZ (evento não aceito) vem no evento normalizado devolvido, não como exceção.

**Comando simples publicado como evento normal, em vez de RPC clássico (reply-to/correlation-id)**: o broker inteiro já é pub/sub, e quem manda um comando de manifestação já está ouvindo a exchange `dfe` — o resultado sai lá, reaproveitando `MontarRoutingKey`, sem exigir fila de resposta temporária, correlação nem timeout do lado de quem chama.

- **`TDFeManifestacaoProcessador`** resolve o `Alias` do comando na unidade do orquestrador (`ObterUnidadePorAlias`), verifica se o provider dela suporta `IDFeManifestador`, envia o evento e publica o resultado. Nunca propaga exceção — qualquer falha (alias desconhecido, provider sem suporte, ou uma das 3 exceções de `DFe.Errors`) é reportada via `RegistrarErro` (hook no-op, mesmo padrão do orquestrador), porque uma falha não pode travar quem estiver drenando vários comandos.
- **`IDFeComandoFonte`** abstrai de onde vem o comando manual — a implementação real embrulha um consumidor AMQP (ainda não escrita); testes usam uma fila pré-carregada. `ProcessarTodos` drena a fonte até não haver mais comando pendente.
- **`TDFeAutoManifestador`** liga o hook do orquestrador ao processador: reage a `AoPublicarDocumento`, e se a unidade que publicou tem `ManifestacaoAutomatica = True` (novo campo em `TDFeUnidadeTrabalho` e em `TDFeConfigCertificado`/`ManifestacaoAutomatica=` no INI, default `false`, sincronizado em `CarregarConfig`/`RecarregarConfig` do mesmo jeito que `Ativo`/`Pausada`), gera sozinho um comando de "ciência" e entrega ao mesmo processador. **Automático e manual convergem no mesmo `TDFeManifestacaoProcessador` — só o gatilho difere**, o que resolve o caso de múltiplos CNPJ com políticas diferentes sem exigir nada além de um `Boolean` por alias (já que `ManifestacaoAutomatica` não participa da colisão de `Ativo`/`Provider`/`CnpjCpf`/`UF` — dois certificados do mesmo CNPJ podem ter valores diferentes, dado que só um dos dois estará `Ativo` por vez de qualquer forma).

**Formato do comando** (`TDFeComandoManifestacao`, via `InterpretarComando`): texto chave=valor, uma por linha (mesmo estilo do arquivo de config) — `Alias`, `ChaveAcesso`, `TipoEvento` (`confirmacao`/`ciencia`/`desconhecimento`/`operacaonaorealizada`) e `Justificativa` (obrigatória para os dois últimos tipos, por regra da SEFAZ — `InterpretarComando` valida e levanta exceção alto e cedo, antes de tentar falar com qualquer provider).

**Testado de verdade (2026-09-18): 68/68 nos dois compiladores** (FPC via `lazbuild`, Delphi via a IDE) — 16 testes novos em `DFe.ManifestacaoTests` (parsing/validação de comando, sucesso/erro do processador incluindo as 3 exceções de `DFe.Errors`, drenagem de fila, disparo/não-disparo do auto-manifestador conforme o flag), 0 erros, 0 falhas, 0 vazamento de memória. Dublês novos em `DFe.TestDoubles.pas`: `TDFeProviderManifestadorFake` (implementa `IDFeProvider` **e** `IDFeManifestador`, ao contrário do `TDFeProviderFake` existente, que representa "provider sem suporte a manifestação") e `TDFeComandoFonteFake` (fila FIFO pré-carregada).

**Ainda não escrita**: a implementação real de `IDFeComandoFonte` (consumidor AMQP de comando manual) — depende do broker embutido estar de fato ligado a um host, que por sua vez depende dos `.dpr`/`.lpr` dos hosts (ver "Modelo de execução"), ainda não escritos.
