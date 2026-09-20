# Exemplo de extensão: limite de consultas por janela

> **Não é o comportamento da SEFAZ.** É uma política inventada, só para mostrar como o
> [`DFeSimulador`](../../LEIAME.md) é estendido **sem alterar o core**. Contrato dos ganchos em
> [`src/DFe.Simulador.Regras.pas`](../../../src/DFe.Simulador.Regras.pas); plano em
> [`docs/simulador-standalone.md`](../../../docs/simulador-standalone.md) (Fase C).

## O que a regra faz

O core bloqueia um CNPJ por 1 h depois de uma consulta sem novidade (137). Esta regra acrescenta uma
política de **taxa** que o core não tem: no máximo **N consultas por CNPJ numa janela de S segundos**
(padrão 3 em 600 s). A (N+1)-ésima consulta de Distribuição recebe **656** (consumo indevido) **sem tocar
no núcleo** — não consome NSU nem abre o bloqueio de 1 h. Serve para testar como o *seu* cliente reage a
ser barrado por excesso de chamadas.

A janela anda com o **relógio virtual** do simulador (`POST /admin/relogio/avancar`): dá para reproduzir
o "barrado" e o "liberado" em segundos.

## Rodar

```
lazbuild simulador\exemplos\limite-consultas\DFeSimuladorLimite.lpi     # FPC (antes: sh simulador/preparar-horse.sh, no Windows)
DFeSimuladorLimite --porta 9200
```

É o mesmo programa do `DFeSimulador` (mesmas opções, mesma API) com uma unit a mais. Ao subir ele lista
a regra: `Regra "limite-consultas" (True): exemplo: no maximo N consultas...`.

```
curl -X POST localhost:9200/admin/documentos -d '{"cnpj":"11222333000181","uf":"RS"}'
curl -X POST localhost:9200/ext/limite -d '{"maximo":2}'            # ajusta (rota própria da regra)
# ... o cliente consulta 2x: 138; a 3a: 656 "limite de 2 consulta(s) em 600 s" ...
curl localhost:9200/ext/limite                                       # {"maximo":2,...,"rejeitadas":1,...}
curl -X POST localhost:9200/admin/relogio/avancar -d '{"minutos":11}'   # a janela reabre
curl -X POST localhost:9200/admin/regras -d '{"nome":"limite-consultas","ativa":false}'   # desliga
```

## Como escrever a sua regra

Uma unit, uma classe, um `initialization` — e a unit na cláusula `uses` do seu programa:

```pascal
type
  TMinhaRegra = class(TDFeSimuladorRegra)
  public
    class function Nome: string; override;                 // único; aparece em /admin/regras
    function AntesDeAtender(const ARequisicao: TDFeSimRequisicao;
      var AResposta: TDFeSimHttpResposta): Boolean; override;
  end;

initialization
  RegistrarRegraSimulador(TMinhaRegra);
```

```pascal
program MeuSimulador;
uses DFe.Simulador.Principal, MinhaUnitDeRegra;   // <-- só existir aqui basta
begin Executar; end.
```

| Gancho | Quando | O que pode |
|---|---|---|
| `AntesDeAtender` | Antes do núcleo, nas duas rotas SOAP | Devolver `True` = "eu respondi" (o núcleo **não** é tocado; as regras seguintes nem são consultadas). `False` = deixa passar. |
| `DepoisDeAtender` | Só se ninguém respondeu antes | Alterar a resposta do núcleo (status, corpo). Todas as regras ativas rodam, na ordem. |
| `TratarRota` | Caminhos `/ext/...` (qualquer método) | Servir rotas próprias. A primeira regra ativa que devolver `True` responde; nenhuma → 404. |
| `AoZerar` | Depois de um `POST /admin/zerar` | Limpar o estado da regra. |

- A regra tem um estado **por servidor** (o registro guarda *classes*, não objetos), e os ganchos rodam
  **sob a trava** do servidor: dá para ler/mexer em `Simulador` (o núcleo) sem se preocupar com concorrência
  — e por isso a regra **não deve bloquear** (dormir, esperar rede): trava as demais requisições.
- `ARequisicao.Agora` é o relógio do **simulador** (o virtual, se houver), não o do sistema.
- Ajudas: `RespostaSoapDeDistribuicao(LoteRejeitado(cStat, xMotivo), tpAmb)` monta o envelope de uma
  rejeição; `ExtrairTag(ARequisicao.Corpo, 'CNPJ')` lê um campo do envelope (`DFe.Simulador.Soap`);
  `RespostaJson` para as rotas `/ext/`.
- Uma exceção num gancho vira **HTTP 500** com a mensagem (o defeito da regra aparece).
- As regras **não veem** `/admin` nem `/ping`: uma regra com defeito não tira do ar o controle do simulador.
- `GET /admin/regras` lista; `POST /admin/regras {"nome":"x","ativa":false}` liga/desliga (o `zerar` **não**
  religa: o estado ligado/desligado é como o "modo" estrito, não estado de teste). `AtivaPorPadrao` faz a
  regra nascer desligada.
- **Rotas Horse próprias** (fora de `/ext/`) em princípio também servem: o programa do usuário pode chamar
  `THorse.Get/Post` antes de `Executar`, pois o Horse é global (**não exercitado**). Só as rotas `/ext/*`
  passam pelo servidor puro (testável sem rede).

## Testes

- Pura: `tests/Unit/fpc/DFe.SimuladorRegrasTests.pas` (o mecanismo: curto-circuito, `DepoisDeAtender`,
  rotas, liga/desliga, registro) e `DFe.SimuladorExemploTests.pas` (esta regra, com o relógio virtual) —
  espelhos DUnitX em `tests/Unit/`.
- Integração: `Extensao_RegraDoUsuario_BarraOClientPorHttp` em `tests/Integration/AcbrSim/DFe.AcbrSimHttpTests.pas`
  sobe **este executável** e roda o client ACBr real por HTTP.
