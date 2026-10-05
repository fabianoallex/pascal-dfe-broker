# F10 (pascal-dfe-broker): achados para a pascal-common-faa e o pascal-amqp-faa

Migracao do pascal-dfe-broker para o pascal-amqp-faa v0.1.0 (que depende da
pascal-common-faa), feita em 2026-10-05. `vendor/pascal-amqp-faa` saiu de
`615b397` para a tag `v0.1.0` (`2e6e768`); `vendor/pascal-common-faa` entrou na
tag `v1.1.1` (`db7005c`), sem `--recursive`. Nada foi alterado nas duas libs; o
que segue e' para levar de volta. Mais importante primeiro.

## Para a pascal-common-faa

### 1. `migrating.md`: o item que so' posta `TThread.Queue` tambem morde, e quem dispara e' o `Destroy` do `PcPool`

O texto atual (achado do redis na F8) descreve itens que **rodam** contra a
form liberada. No consumidor do broker (`ConsumidorDFeVcl`) o item do pool
(`TConexaoEventoWork`) nao toca a form: ele so' cria um marshal e o posta com
`TThread.Queue`. Mesmo assim houve use-after-free, por outro caminho.

**Medido** (FPC 3.2.2 / LCL win32, Win64, `prova/ProvaFechamento --cenario=pool`):
`PcPool` ocupado com `MaxWorkers` itens que bloqueiam; o broker cai; a thread de
reconexao enfileira o item da form; a form e' fechada; os bloqueios sao soltos
4 s depois do pedido de fechar.

- Linha do tempo: form liberada em 2344 ms; a fila do pool andou em 4265 ms
  (uma sentinela enfileirada logo atras do item da form anotou "form JA
  LIBERADA").
- O marshal postado pelo item nao rodou enquanto ninguem bombeou a fila. Quem
  bombeou foi o `TPcThreadPool.Destroy` na finalizacao da
  `PascalCommon.ThreadPool`: no FPC, o `TThread.WaitFor` chamado da thread
  principal roda `CheckSynchronize`. Pilha do AV (gdb):
  `TfrmConsumidor.ConexaoCaiu` (`this` do `TLabel` = `0xf0f0f0f0f0f0f0f0`, o
  preenchimento do heaptrc para memoria liberada) <- marshal `Execute` <-
  `CheckSynchronize` <- `TThread.WaitFor` <- `TPcThreadPool.Destroy`
  (`PascalCommon.ThreadPool.pas:295`).
- Mesmo sem o AV, o marshal que nao roda vaza (heaptrc: o bloco alocado no
  `Execute` do item).

**Sugestao** para "Behavior to know about": (a) contar tambem os objetos que o
item posta com `TThread.Queue` (o pascal-dfe-broker conta item e marshals no
mesmo contador da form; o item cria o marshal antes de se descontar no proprio
destrutor, entao a conta nunca passa por zero no meio do caminho); (b) dizer que
"depois do laco de mensagens ninguem bombeia" vale ate' a finalizacao da
`PascalCommon.ThreadPool`, que bombeia no FPC, e e' ali que o marshal antigo
roda contra a form liberada.

**Com o padrao aplicado** (contar do construtor ao destrutor, `OnCloseQuery`
espera bombeando `CheckSynchronize(10)`, nenhum item le controle): o mesmo
cenario fecha em 4 s, a sentinela anota "form ainda viva", o `ConexaoCaiu` sai no
log da form antes do `FormDestroy`, heaptrc `0 unfreed memory blocks`. Um segundo
cenario (2000 entregas em voo, thread da UI ocupada, fechar logo apos o confirm)
fecha limpo antes e depois da mudanca (o `ProcessMessages` antigo ja' dava conta
dos marshals das entregas).

### 2. `migrating.md`, passo 3: num projeto que usa o `src` de uma lib (nao o `.lpk` dela), o pacote basta no FPC

Os projetos do broker compilam o amqp pelo `src` (search path), nao pelo
`pascal_amqp_faa.lpk`. Medido com `lazbuild` 4.0: listar `pascal_common_faa`
primeiro, com `DefaultFilename` em `vendor/pascal-common-faa/packages` e
`Prefer="True"`, ja' resolve tudo; as 6 units da common sao compiladas so' em
`vendor/pascal-common-faa/packages/lib`, nenhuma na pasta do projeto, e o log
mostra `-Fu...vendor\pascal-common-faa\packages\lib\x86_64-win64`. Por-lhe tambem
o `src` da common no search path seria redundante (e arriscaria compilar as units
duas vezes). Onde o `src` **e'** necessario: no Delphi (`.dproj`), e quando o
`fpc` e' chamado direto, sem `lazbuild` (os scripts Docker do broker: `-Fu` e
`-Fi` de `vendor/pascal-common-faa/src`). Talvez valha uma linha em "For
application authors".

### 3. Gotcha 5 (heaptrc mudo no Debian): mais um consumidor que nunca tinha medido

O `tools/docker/testar-linux.sh` do broker procurava `unfreed` na saida da suite
e **nao compilava com `-gh`** em nenhum passo. Os "0 vazamento no Linux" que o
`CLAUDE.md` do broker registrava nunca foram vistos. Agora: `-gh -gl` na suite
pura, na integracao ACBr x simulador, na integracao AMQP, no host e no demo, com
`HEAPTRC=log=<arquivo>` e conferencia da linha `0 unfreed memory blocks` no
arquivo. A integracao ACBr x simulador tambem nunca tinha tido `UseHeaptrc` no
`.lpi` (Windows): ligado agora, mediu 0.

## Para o pascal-amqp-faa

### 4. `Close`/`Free` da conexao durante a reconexao espera ate' `ReconnectDelayMs`

`TAMQPConnection.RunReconnect` dorme `Sleep(LDelay)` entre tentativas e so' olha
`FDeliberateClose` depois; `WaitReconnectStopped` espera por polling (ate' 12 s).
Medido: fechar a form do consumidor logo depois de o broker cair levou
**2,0-2,1 s** dentro do `FreeAndNil(FConn)` (com o `ReconnectDelayMs = 2000` do
sample). Com um `ReconnectDelayMs` alto, fechar a aplicacao durante uma queda
espera esse tempo todo. Sugestao: esperar num evento sinalizado pelo `Close`, em
vez de `Sleep`.

### 5. D37 confirmada do lado de um consumidor (nenhuma acao)

O broker roda broker embutido e cliente no mesmo processo. Teste novo
`Publicar_ComPcPoolSaturado_NaoDependeDoPool`
(`tests/Integration/AmqpBroker`, FPC e espelho DUnitX): `PcPool` saturado com
`MaxWorkers + 1` itens bloqueados; declarar fila, publicar pelo publicador do host
(confirm sincrono), e `Basic.Get`. Com o v0.1.0: **45 ms**. Com uma copia
descartavel do `src` em que `FEngine.Pool := FActorPool` foi removido (atores no
`PcPool`, como em `615b397`): **15,2 s**, e a conexao cai no `CallRpc`
(`end of stream while reading frame`). O `vendor` nao foi tocado.

### 6. `DrainInFlight` sem prazo depende do `PcPool` andar (lido, nao medido)

O `Free` de um canal com consumidor espera os callbacks em voo contados desde o
enfileiramento, sem prazo. Com o `PcPool` saturado por outra lib, parar um
consumidor espera a fila compartilhada chegar aos itens dele. No broker isso so'
acontece na parada (fonte de comando `dfe.comandos`), e nada mais no processo usa
o `PcPool`. Nao medido; registrado por ser a unica espera sincrona do host por
trabalho do `PcPool`.

### 7. Comandos fora de ordem ao subir a common para 1.2.0 (defeito do BROKER, nao do amqp; corrigido)

**Correcao da atribuicao**: a primeira versao deste item culpou o despacho do
amqp. Errado. Paralelismo dentro do canal e' o comportamento **documentado** do
pascal-amqp-faa (README, "Concorrencia e ordenacao de mensagens": "paralelismo
por padrao, ordem por opt-in"), e a ordem se pede com `CreateChannel(True)`.
O defeito era do `DFe.ComandoFonte.AMQP`, que consumia num canal comum e contava
com a ordem do `Enqueue` na fila propria (opcao 3 do README).

Mecanismo: cada `Basic.Deliver` vira um item independente no `PcPool`. Ate' a
common 1.1.2, o `Queue` so' abria worker com `FIdle = 0`, entao duas entregas
seguidas caiam no mesmo worker e saiam em ordem por acaso; a 1.1.3 (`73767ad`,
correta) abre worker quando `FQueue.Count > FIdle`.

**Medido** (FPC 3.2.2, Windows x64, suite AMQP inteira em laco):
`DoisComandos_SaemNaOrdem` falhou em 3/20 com common `v1.2.0` + amqp `v0.1.0`
e em 0/20 com a `v1.1.1`. Corrigido com `FCanal := FConexao.CreateChannel(True)`
na fonte, e subidos juntos amqp `v0.1.2` + common `v1.2.0`: 0/30 (20 testes,
0 vazamento). Teste novo `RajadaDeComandos_SaemNaOrdemDoBroker` (40 comandos,
FPC + espelho DUnitX); com a linha revertida (mutante) a suite falha em 9/10.

**Para o pascal-amqp-faa (so' documentacao)**: a opcao 3 do README diz que a
thread dedicada processa "em ordem de chegada", sem avisar que, num canal comum,
a ordem de chegada na fila da aplicacao ja' nao e' a do broker. Foi essa a
armadilha. Sugestao: dizer que a opcao 3 so' preserva a ordem com
`CreateChannel(True)` ou `Qos(1)` (README.md e README.en.md).

## O que funcionou como documentado (nenhuma acao)

- `.lpi` com `pascal_common_faa` primeiro, `DefaultFilename` + `Prefer="True"`:
  todos os projetos do broker compilaram contra a copia do `vendor` (conferido no
  log do `lazbuild`).
- Renomes com `perl -pi` e `\b`: so' o sample tocava nomes antigos
  (`AmqpPool`, `TAMQPWorkItem`, `AMQP.Threading`); o `src` do broker nao usava
  nenhum.
- `git submodule add` no Windows falhou com `could not open '.../.git' for
  writing: Permission denied` **depois** de clonar (o arquivo `.git` existia);
  completar `.gitmodules` e `git add` a mao deixou o gitlink correto (modo
  160000). Nao investigado (antivirus?).
