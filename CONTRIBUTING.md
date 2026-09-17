# Contribuindo

Obrigado pelo interesse em contribuir com o DFe Broker. O projeto está em fase inicial e contribuições de qualquer tamanho ajudam — desde reportar uma ambiguidade neste documento até implementar um provider inteiro.

## Antes de tudo

Leia [`docs/architecture.md`](docs/architecture.md). Ele define as convenções que **todo** provider precisa seguir (routing-key, contrato de provider, formato do evento interno). Se sua contribuição diverge de alguma convenção documentada lá, abra uma issue de discussão *antes* do PR — mudar essas convenções depois que existem consumidores em produção quebra compatibilidade, então elas não mudam por decisão de um PR isolado.

## Adicionando um novo tipo de documento (CTe, MDFe, ...)

Este é o tipo de contribuição mais valioso e o mais sensível a ficar fora de padrão. Um novo provider só é aceito se:

1. **Segue o contrato de provider** descrito em `docs/architecture.md` (identidade, consulta, decodificação, publicação, cursor de NSU isolado) sem desvios não documentados.
2. **Produz o evento interno padronizado** — mesmo formato usado pelo provider de NFe, não um formato próprio "porque CTe é diferente". Se CTe/MDFe realmente exigirem um campo que NFe não tem, a extensão do formato é discutida antes, no core, não decidida dentro do provider.
3. **Usa a mesma convenção de routing-key** (`<tipo>.<categoria>.<uf>.<cnpj>`), só trocando `<tipo>`.
4. **Vem com testes contra fixtures gravadas** da resposta da SEFAZ — nunca contra o serviço de produção da SEFAZ (rate limit real, e além disso exigiria certificado de teste válido no CI, o que não é seguro de distribuir).
5. **Documenta qualquer limitação de compilador** — se algum componente ACBr necessário para aquele tipo de documento não funcionar (ou funcionar parcialmente) em Lazarus/FPC, isso vai documentado no README do provider, não silenciado.

Se você não tem certeza se seu approach atende esses pontos, abra uma issue descrevendo o plano antes de implementar — é mais barato ajustar o plano do que o PR pronto.

## Reportando problemas

Abra uma issue com: o que você esperava, o que aconteceu, e se envolve chamada à SEFAZ, o `statusCode`/mensagem de retorno (nunca cole XML de documento fiscal real de terceiro — anonimize CNPJ/chave de acesso, ou use dado de homologação).

## Certificados e dados sensíveis

Nunca inclua certificado digital (mesmo de teste real), senha, ou XML de documento fiscal real em issues, PRs ou fixtures de teste. Fixtures devem usar dados de homologação/sintéticos.
