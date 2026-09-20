# DFeSimulador — simulador da SEFAZ como aplicação separada

> **Não é a SEFAZ.** Responde conforme a *leitura que este projeto faz* das Notas Técnicas
> (`docs/referencias/`), só para teste. Se essa leitura estiver errada, o simulador repete o erro.
> Plano, decisões e limites em [`docs/simulador-standalone.md`](../docs/simulador-standalone.md).

Um servidor HTTP que responde como a **Distribuição de DFe** e a **manifestação do destinatário**
(RecepcaoEvento) da NFe. O `DFeBrokerConsole` (ou o serviço) pode ser apontado para ele e roda de
ponta a ponta — ACBr real, certificado de teste, publicação na fila — sem certificado da empresa e
sem tocar na SEFAZ. Um cliente de outra linguagem também pode usá-lo, se a biblioteca dele aceitar
trocar a URL do serviço.

**Estado:** Fases A e B do plano: cenário por arquivo, **API admin** (`/admin`) para preparar e consultar
o simulador em execução, **relógio virtual** e modo **leniente/estrito**. Só a NFe (Distribuição e
manifestação).

## Rodar

```
DFeSimulador --porta 9200 --cenario cenario.exemplo.ini
```

| Opção | Efeito |
|---|---|
| `--porta <n>` | Porta HTTP (padrão 9200). |
| `--bind <endereço>` | Endereço de escuta (padrão `127.0.0.1`). `0.0.0.0` expõe a rede toda, **sem autenticação**. |
| `--cenario <ini>` | Cenário declarativo inicial (abaixo). Sem ele o simulador sobe vazio. |
| `--estrito` | Modo estrito desde o início (abaixo). |

Rotas SOAP (o envelope como o ACBr envia): `POST /NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx` e
`POST /NFeRecepcaoEvento4/NFeRecepcaoEvento4.asmx`. `GET /ping` para saber se está de pé.

## API admin

JSON **plano** (um objeto de campos simples; sem objetos aninhados). Sem autenticação. Erros: `{"erro":"..."}`
com 400 (corpo inválido), 404 (rota) ou 405 (método).

O corpo deve ser **UTF-8**. Mande `-H 'Content-Type: application/json'`: no executável compilado com Delphi, um
corpo *não-ASCII* sem esse cabeçalho (o `curl -d` manda `x-www-form-urlencoded`) é decodificado de outro jeito e
recusado com 400. No executável FPC (o do Docker) não importa. Texto com acento também pode ir como escape JSON.

| Rota | Efeito |
|---|---|
| `GET /admin/estado` | Contas (CNPJ/UF, NSU, documentos, bloqueio), falhas pendentes, contadores, modo e "agora". |
| `POST /admin/documentos` | Publica documentos. Sintético: `{"cnpj":"11222333000181","uf":"RS","tipo":"resNFe","quantidade":3}`. `tipo`: `resNFe` (padrão), `procNFe`, `resEvento`, `procEventoNFe` (estes com `"tpEvento":"110111"`). Opcionais: `numero` (1ª nota), `emitente`, `xNome`, `dhEmi`, `chave` (quantidade 1). Literal: `{"cnpj","uf","schema":"resNFe_v1.01.xsd","xml":"<resNFe>...</resNFe>"}`. Devolve `{"publicados":3,"ultimoNsu":3}`. |
| `POST /admin/pular-nsu` | `{"cnpj","uf","quantidade":2}` — NSUs atribuídos mas não entregues (salto). |
| `POST /admin/falhas` | Enfileira falhas que as PRÓXIMAS consultas sofrem, na ordem: `{"falha":"timeout","quantidade":2}` ou `{"falhas":["timeout","consumo-indevido"]}`. Nomes: `indisponivel-curto` (108), `indisponivel-longo` (109), `consumo-indevido` (656), `timeout` (vira HTTP 504), `erro-http` (500), `corpo-ilegivel`, `doczip-corrompido`, `evento-rejeitado`, `lote-evento-rejeitado`. Nome desconhecido → 400 e **nada** é enfileirado. |
| `POST /admin/relogio/avancar` | **Relógio virtual**: `{"horas":1,"minutos":1}` (também `segundos`, `dias`). Ver abaixo. |
| `GET /admin/relogio` · `POST /admin/relogio/zerar` | Lê / volta o relógio ao real. |
| `GET /admin/modo` · `POST /admin/modo` | `{"estrito":true}`. Ver abaixo. |
| `GET /admin/violacoes` · `DELETE /admin/violacoes` | O que os requests recebidos têm de diferente do formato esperado (texto; `(nenhuma)` se nada) / esquece. |
| `GET /admin/ultimo-envelope` | O último envelope recebido (XML). |
| `POST /admin/cenario` | O corpo é o INI do cenário. **Validado por inteiro antes de aplicar** (erro = nada muda); acumula sobre o estado atual. |
| `POST /admin/zerar` | Estado, falhas, violações e relógio voltam ao início (o modo continua). |

### O 656 sem esperar uma hora

O simulador abre um bloqueio de 1 h depois de uma consulta sem novidade (137); consultar antes disso é
"consumo indevido" (656). Para reproduzir e desfazer isso sem esperar:

```
curl -X POST localhost:9200/admin/documentos -d '{"cnpj":"11222333000181","uf":"RS"}'
# ... o broker consulta e recebe o documento; consulta de novo, sem novidade: 137, bloqueia 1 h ...
# ... consulta de novo, na hora: 656 ...
curl -X POST localhost:9200/admin/relogio/avancar -d '{"horas":1,"minutos":1}'
# ... a próxima consulta já é liberada.
```

O relógio virtual é o relógio real **mais um deslocamento** (só avança, ou volta a zero). O broker tem o
relógio *dele*; para um teste reproduzível configure `IntervaloBaseSegundos` pequeno no `dfe.ini`.

### Leniente × estrito

- **Leniente (padrão):** um request fora do formato que o ACBr envia é *atendido e registrado* em
  `/admin/violacoes`. É o certo para um cliente de terceiros, que não é o ACBr.
- **Estrito** (`--estrito` ou `{"estrito":true}`): esse request é **recusado com HTTP 400** e o estado **não é
  tocado** (não consome NSU nem abre bloqueio) — para testar que o seu cliente manda o formato certo.

## Cenário (`cenario.exemplo.ini`)

```ini
[simulador]
Falhas=consumo-indevido,timeout       ; as PRÓXIMAS consultas sofrem isto, na ordem

[conta:exemplo]                        ; uma seção por CNPJ/UF
Cnpj=11222333000181
UF=RS
ResNFe=3                               ; resNFe sintéticas (notas 1..N)
ProcNFe=1                              ; procNFe sintéticas (notas seguintes)
PularNSU=2                             ; NSUs atribuídos mas não entregues (salto)
```

Erro de digitação no cenário **derruba a subida** (ou devolve 400 em `POST /admin/cenario`) com a linha do problema.

## Apontar o broker para ele

No `dfe.ini` do broker, com **`Ambiente=homologacao`**:

```ini
[dfe]
Ambiente=homologacao
SimuladorURL=http://127.0.0.1:9200
```

- O log avisa `TRANSPORTE SIMULADO` a cada certificado. O broker **recusa subir** com `SimuladorURL` e
  `Ambiente=producao` (os documentos reais nunca chegariam), salvo `SimuladorPermitirProducao=true`.
- O certificado do broker precisa casar com o CNPJ da conta (o de teste
  `tests/Integration/AcbrSim/cert-teste/valido.pfx`, senha `teste123`, é o CNPJ `11222333000181`).

## Compilar

- **FPC/Linux:** `fpc -Mdelphi -dUseCThreads -Fu src -Fu vendor/horse/src simulador/DFeSimulador.lpr`
  (ou `lazbuild simulador/DFeSimulador.lpi` depois de `sh simulador/preparar-horse.sh`).
- **FPC/Windows:** `sh simulador/preparar-horse.sh` (copia o Horse para `simulador/build/` com o contorno de
  uma linha em `Horse.FPC.inc`, ver `simulador/spike-horse/LEIAME.md`) e `lazbuild simulador\DFeSimulador.lpi`.
- **Delphi:** projeto `DFeSimulador` no `PascalDfeBroker.groupproj` (usa `vendor/horse/src` direto).

Requer `git submodule update --init vendor/horse`.

## Testes

- Pura (`tests/Unit`): `DFe.SimuladorServidorTests` (servidor e cenário), `DFe.SimuladorAdminTests` (núcleo,
  estrito, relógio, JSON, cenário atômico e a API admin), `DFe.TransmissorHttpTests` (o lado do broker) — sem HTTP.
- Integração (`tests/Integration/AcbrSim`, `DFe.AcbrSimHttpTests`): sobe este executável como processo e
  roda o client ACBr real por HTTP — 137/138, 656, timeout, 500, corpo ilegível, docZip corrompido,
  simulador fora do ar, manifestação (com acento, provado no que o simulador recebeu) e a API admin
  (publicar, falhas, **656 reproduzido e desfeito pelo relógio virtual**, violações, estrito, zerar).
  Requer o executável compilado; sem ele o teste **falha** dizendo como compilar.
