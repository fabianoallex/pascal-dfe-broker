# DFeSimulador — simulador da SEFAZ como aplicação separada

> **Não é a SEFAZ.** Responde conforme a *leitura que este projeto faz* das Notas Técnicas
> (`docs/referencias/`), só para teste. Se essa leitura estiver errada, o simulador repete o erro.
> Plano, decisões e limites em [`docs/simulador-standalone.md`](../docs/simulador-standalone.md).

Um servidor HTTP que responde como a **Distribuição de DFe** e a **manifestação do destinatário**
(RecepcaoEvento) da NFe. O `DFeBrokerConsole` (ou o serviço) pode ser apontado para ele e roda de
ponta a ponta — ACBr real, certificado de teste, publicação na fila — sem certificado da empresa e
sem tocar na SEFAZ.

**Estado:** Fase A do plano. Cenários por arquivo INI; controle por API (`/admin`) e relógio virtual
são a Fase B. Só a NFe (Distribuição e manifestação).

## Rodar

```
DFeSimulador --porta 9200 --cenario cenario.exemplo.ini
```

| Opção | Efeito |
|---|---|
| `--porta <n>` | Porta HTTP (padrão 9200). |
| `--bind <endereço>` | Endereço de escuta (padrão `127.0.0.1`). `0.0.0.0` expõe a rede toda, **sem autenticação**. |
| `--cenario <ini>` | Cenário declarativo (abaixo). Sem ele o simulador sobe vazio. |

Rotas: `POST /NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx` e `POST /NFeRecepcaoEvento4/NFeRecepcaoEvento4.asmx`
(envelope SOAP, como o ACBr envia); `GET /ping`; `GET /admin/violacoes` (o que o request recebido tem de
diferente do formato esperado, `(nenhuma)` se nada); `GET /admin/ultimo-envelope` (o último envelope recebido).

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

Falhas: `indisponivel-curto` (108), `indisponivel-longo` (109), `consumo-indevido` (656), `timeout`
(vira HTTP 504), `erro-http` (500), `corpo-ilegivel`, `doczip-corrompido`, `evento-rejeitado`,
`lote-evento-rejeitado`. Erro de digitação no cenário **derruba a subida** com a linha do problema.

## Apontar o broker para ele

No `dfe.ini` do broker, com **`Ambiente=homologacao`**:

```ini
[dfe]
Ambiente=homologacao
SimuladorURL=http://127.0.0.1:9200
```

- O log avisa `TRANSPORTE SIMULADO` a cada certificado. O broker **recusa subir** com `SimuladorURL` e
  `Ambiente=producao` (os documentos reais nunca chegariam), salvo `SimuladorPermitirProducao=true`.
- O certificado do broker precisa casar com o CNPJ da conta do cenário (o de teste
  `tests/Integration/AcbrSim/cert-teste/valido.pfx`, senha `teste123`, é o CNPJ `11222333000181`).

## Compilar

- **FPC/Linux:** `fpc -Mdelphi -dUseCThreads -Fu src -Fu vendor/horse/src simulador/DFeSimulador.lpr`
  (ou `lazbuild simulador/DFeSimulador.lpi` depois de `sh simulador/preparar-horse.sh`).
- **FPC/Windows:** `sh simulador/preparar-horse.sh` (copia o Horse para `simulador/build/` com o contorno de
  uma linha em `Horse.FPC.inc`, ver `simulador/spike-horse/LEIAME.md`) e `lazbuild simulador\DFeSimulador.lpi`.
- **Delphi:** projeto `DFeSimulador` no `PascalDfeBroker.groupproj` (usa `vendor/horse/src` direto).

Requer `git submodule update --init vendor/horse`.

## Testes

- Pura (`tests/Unit`): `DFe.SimuladorServidorTests` (servidor e cenário, sem HTTP),
  `DFe.TransmissorHttpTests` (o lado do broker).
- Integração (`tests/Integration/AcbrSim`, `DFe.AcbrSimHttpTests`): sobe este executável como processo e
  roda o client ACBr real por HTTP — 137/138, 656, timeout, 500, corpo ilegível, docZip corrompido,
  simulador fora do ar e manifestação (com acento, provado no que o simulador recebeu).
  Requer o executável compilado; sem ele o teste **falha** dizendo como compilar.
