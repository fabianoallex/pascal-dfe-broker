# Contribuindo

Obrigado pelo interesse em contribuir com o DFe Broker. O projeto está em fase inicial e contribuições de qualquer tamanho ajudam — desde reportar uma ambiguidade neste documento até implementar um provider inteiro.

## Onde a ajuda é mais valiosa hoje

Dúvidas e ideias: [Discussions](https://github.com/fabianoallex/pascal-dfe-broker/discussions). Issues para quem quer começar: rótulo [good first issue](https://github.com/fabianoallex/pascal-dfe-broker/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22).

1. **Validar em homologação com um certificado real** — o projeto nunca foi executado contra a SEFAZ. A [issue #1](https://github.com/fabianoallex/pascal-dfe-broker/issues/1) é um roteiro; mesmo um "consultei em homologação e voltou 137" já é informação valiosa. Comece pela demo com o simulador ([`docs/guia-de-uso.md`](docs/guia-de-uso.md)) para confirmar que o seu ambiente está certo antes de usar o certificado.
2. **Novos tipos de documento** — CT-e e MDF-e (seção abaixo).
3. **Consumidores de exemplo** em outras linguagens (Node, C#, Java, PHP…) — hoje há Python e Pascal (Delphi/Lazarus, com tela).
4. **Uma imagem Docker do broker** (só o simulador tem `Dockerfile`).
5. **Documentação** — dúvida que você teve e que o texto não respondeu é um bug de documentação; abra uma issue ou um PR. Traduções são bem-vindas.

## Antes de tudo

Leia [`docs/architecture.md`](docs/architecture.md). Ele define as convenções que **todo** provider precisa seguir (routing-key, contrato de provider, formato do evento interno). Se sua contribuição diverge de alguma convenção documentada lá, abra uma issue de discussão *antes* do PR — mudar essas convenções depois que existem consumidores em produção quebra compatibilidade, então elas não mudam por decisão de um PR isolado.

## Preparando o ambiente e rodando os testes

Compilar: siga "Como compilar e rodar" no [`README.md`](README.md) (em particular: `lazbuild --add-package-link packages/pascal_dfe_broker.lpk` uma vez por máquina). Rodar os testes: [`docs/testes.md`](docs/testes.md) — nenhum precisa de certificado nem de SEFAZ.

O projeto é **dual-compiler** (Delphi e FPC/Lazarus). Regras que já custaram caro e que um PR precisa respeitar:

- **Os dois compiladores.** Se possível rode os dois antes de abrir o PR. Se você só tem um, diga qual no PR: o outro é conferido depois. O Delphi não roda no CI; o Linux/FPC roda.
- **Teste espelhado.** Toda unit pura nova ganha um teste em DUnitX (`tests/Unit/`) **e** em FPCUnit (`tests/Unit/fpc/`), e é registrada nos projetos de teste (`.dpr`/`.dproj` e `.lpr`/`.lpi`).
- **Novo `.dproj`** entra em `PascalDfeBroker.groupproj`.
- **Fonte só em ASCII.** O Delphi lê fonte sem BOM como ANSI: acento ou emoji num literal vira mojibake. Use `#$00E3` ou monte o texto com constantes.
- **Sem `Sleep` e sem relógio real nos testes** — use os dublês de `tests/Unit/DFe.TestDoubles.pas`.
- **Sem recursos que só um compilador tem** (closures/métodos anônimos, `System.JSON`): o FPC 3.2.2 não os tem. Use métodos `of object`. Veja a lista de gotchas em [`CLAUDE.md`](CLAUDE.md), "Gotchas dual-compiler".
- **Nada de certificado real, senha ou XML fiscal real** em código, testes, issues ou fixtures (mais abaixo).

## Adicionando um novo tipo de documento (CT-e, MDF-e, ...)

Este é o tipo de contribuição mais valioso e o mais sensível a ficar fora de padrão. Um novo provider só é aceito se:

1. **Segue o contrato de provider** descrito em `docs/architecture.md` (identidade, consulta, decodificação, publicação, cursor de NSU isolado) sem desvios não documentados.
2. **Produz o evento interno padronizado** — mesmo formato usado pelo provider de NFe, não um formato próprio "porque CTe é diferente". Se CTe/MDFe realmente exigirem um campo que NFe não tem, a extensão do formato é discutida antes, no core, não decidida dentro do provider.
3. **Usa a mesma convenção de routing-key** (`<tipo>.<categoria>.<uf>.<cnpj>`), só trocando `<tipo>`.
4. **Vem com testes sem certificado**: o provider é testado com fixtures sintéticas (veja `tests/Unit/DFe.ProviderNFeTests.pas` e `src/DFe.Simulador.Fixtures.pas`), e o client, contra o **simulador da SEFAZ** — nunca contra o serviço real (rate limit real, e exigiria certificado válido no CI). Fixtures precisam satisfazer o **parser real do ACBr**, não só o do provider.
5. **Documenta qualquer limitação de compilador** — se o componente ACBr para aquele tipo de documento não tiver build Linux/FPC maduro, isso vai documentado, não silenciado.
6. **Confere o lote completo.** O ACBr engole erros de interpretação do `docZip` e devolve um lote truncado; `DFe.Client.ACBrNFe.ConferirLoteCompleto` existe para isso, e todo client novo precisa de defesa equivalente (o cursor pularia documentos).
7. **Usa o código de consumo indevido correto do tipo** (656 na NF-e e no CT-e; **678 no MDF-e**) — ver `docs/referencias/README.md`.

### O que um novo tipo toca

O provider se auto-registra, mas **um tipo de documento completo tem três pontos de contato**:

**(a) A unit do provider** — o auto-registro dispensa editar o registry:

```pascal
initialization
  TDFeProviderRegistry.Registrar(TDFeProviderCte.Create);
end.
```

Escolha um `Identificador` (`'cte'`, `'mdfe'`, ...) que ainda não exista — `Registrar` levanta exceção em caso de colisão, então um identificador repetido é pego na hora, não em produção.

**(b) Um client** (`IDFeDistribuicaoClient`) para o tipo, análogo a `src/DFe.Client.ACBrNFe.pas` — é a única peça que fala com o componente ACBr (`TACBrCTe`, `TACBrMDFe`).

**(c) Dois pequenos ajustes em units do host** (o auto-registro não os dispensa): o provider entra no `uses` de `src/DFe.Host.Aplicacao.pas` (senão o `initialization` nunca roda), e `src/DFe.Host.ACBr.pas` hoje aceita **só** o provider `nfe` — é ali que a fábrica passa a devolver o client do novo tipo.

Se você não tem certeza se seu approach atende esses pontos, abra uma issue descrevendo o plano antes de implementar — é mais barato ajustar o plano do que o PR pronto.

## Reportando problemas

Abra uma issue com: o que você esperava, o que aconteceu, a versão/commit, o sistema operacional, o compilador (Delphi/FPC + versão) e se foi console ou serviço. Se envolve chamada à SEFAZ, o `cStat`/`xMotivo` de retorno e um trecho do log (nunca cole XML de documento fiscal real de terceiro — anonimize CNPJ/chave de acesso, ou use dado de homologação).

## Certificados e dados sensíveis

Nunca inclua certificado digital (mesmo de teste real), senha, ou XML de documento fiscal real em issues, PRs ou fixtures de teste. Fixtures devem usar dados de homologação/sintéticos. (O certificado em `tests/Integration/AcbrSim/cert-teste/` é sintético e autoassinado, gerado para os testes.)

Se você encontrou uma **falha de segurança** (por exemplo, vazamento de senha em log), não abra uma issue pública: veja [`SECURITY.md`](SECURITY.md).
