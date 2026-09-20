# Achados sobre o ACBr (para propor ao projeto ACBr no momento certo)

> **Não é para enviar agora.** Decisão de 2026-09-20: acumular aqui tudo o que descobrimos sobre o ACBr
> enquanto o projeto é construído e só propor ao projeto ACBr **depois** que o pascal-dfe-broker estiver
> viabilizado e, de preferência, com uso na comunidade. Uma sugestão feita junto com algo pronto e usado
> pesa mais do que uma sugestão isolada no meio do caminho.

## Como manter este arquivo

- **Ao encontrar um comportamento surpreendente do ACBr, registre aqui na hora** (com a evidência), mesmo que
  já esteja nos gotchas do `CLAUDE.md` — lá é o que precisamos saber para trabalhar; aqui é o que *eles*
  poderiam mudar.
- Cada item traz: o que acontece, como reproduzimos (teste ou ferramenta deste repositório), o contorno que
  usamos, o que sugeriríamos e o quanto achamos que vale a pena (**A** = defeito ou perda de dados;
  **B** = documentação/API que evita armadilha; **C** = conveniência).
- **Antes de propor, reverificar contra o trunk atual do ACBr.** Tudo abaixo foi observado na revisão
  **`578954903fdbe5c8ca57fe1a35b79c6c49e1ec79` (SVN `trunk2@48289`, 2026-09-17)**, a que `vendor/ACBr`
  aponta; o comportamento pode ter mudado. Cada item diz se foi **testado** (rodando) ou só **lido** no fonte.
- O `vendor/ACBr` é um **espelho** do repositório oficial (SVN); PR no espelho provavelmente não chega a
  ninguém. O canal certo é o oficial do projeto (não verificado qual é hoje).

## Como apresentar (quando chegar a hora)

1. O que criamos: um broker de Distribuição de DFe e um **simulador da SEFAZ** que roda o ACBr real sem
   certificado e sem rede — o ambiente de teste que o projeto ACBr não tem.
2. O que aprendemos usando o ACBr nesse cenário, em ordem de valor (abaixo), cada item com reprodução automática.
3. Oferecer o simulador como ajuda para os testes deles, se fizer sentido.

---

## A — Defeito ou risco de perda de dados

### A1. Erro ao interpretar um `docZip` é engolido: o lote sai truncado, com o `ultNSU` do cabeçalho

- **O que acontece** (testado): `TRetDistDFeInt.LerXml` captura a exceção ao interpretar um item do `docZip` e
  devolve `False`; `TDistribuicaoDFe.TratarResposta` ignora esse retorno. O resultado é um lote **com menos
  itens do que a SEFAZ mandou**, ou com item de XML vazio, mas com `ultNSU`/`maxNSU` do cabeçalho. Quem usa o
  `ultNSU` como cursor (o normal) **pula os documentos perdidos e nunca os recebe**.
- **Reprodução:** lote `[resNFe, procNFe sem <tpNF>, resEvento]` chega como 2 itens com `ultNSU=3`. Teste
  `LoteTruncadoPeloAcbr_ViraRespostaInvalidaEmVezDePerderDocumentos` em
  `tests/Integration/AcbrSim/DFe.AcbrSimTests.pas` (roda o ACBr real por `OnTransmit`).
- **Nosso contorno:** `ConferirLoteCompleto` em `src/DFe.Client.ACBrNFe.pas` compara o número de `<docZip` da
  resposta bruta com o que foi interpretado e recusa item de XML vazio.
- **Sugestão:** propagar a falha de `LerXml` (levantar exceção ou devolver o status de erro) em vez de ignorá-la;
  no mínimo, não avançar `ultNSU` quando algum item não pôde ser lido.
- **Nota:** o mesmo padrão "engole a falha" aparece quando a libxml2 não carrega (item A2).

### A2. Sem libxml2, toda resposta é interpretada como vazia — `cStat = 0`, sem exceção

- **O que acontece** (testado): `ACBrXmlDocument`, usado para interpretar **toda** resposta (não só eventos),
  é um invólucro da libxml2 em qualquer compilador. Sem a biblioteca, `LerXml` engole a falha e o resultado é
  `retDistDFeInt.cStat = 0`, sem erro visível.
- **Nosso contorno:** verificamos o ambiente antes (`DFe.Ambiente.ACBr`) e recusamos `cStat = 0`.
- **Sugestão:** falhar alto e com mensagem clara quando a libxml2 não puder ser carregada; documentar que ela é
  obrigatória para qualquer uso dos serviços DFe.

### A3. OpenSSL 3.0.x: o provider `default` não é ativado, e nenhum `.pfx` é lido

- **O que acontece** (testado em Linux, Debian 12 e Ubuntu 22.04): com o OpenSSL 3.0.x, sem o provider `default`
  carregado explicitamente, todo `PKCS12_parse` falha (`unsupported` / `mac generation error`) e o ACBr diz
  "Erro ao ler informações do Certificado" para um `.pfx` **válido**.
- **Nosso contorno:** `GarantirProviderPadraoDoOpenSSL3` em `DFe.Ambiente.ACBr`.
- **Sugestão:** ativar o provider `default` (e `legacy` se necessário) ao inicializar o OpenSSL 3, ou
  documentar o requisito. Mensagem de erro mais específica ajudaria muito.

## B — Documentação e API que evitam armadilha

### B1. `OnTransmit`: o contrato só se descobre lendo o fonte

- **O que existe** (lido e testado): `TACBrDFe.OnTransmit(Dados, URL, SoapAction, MimeType, var Resposta,
  var HTTPResultCode, var InternalErrorCode)` substitui o HTTP/TLS; `InternalErrorCode <> 0` vira
  `EACBrDFeException`; `10060` vira `EACBrDFeExceptionTimeOut`. É o que permite rodar o ACBr real inteiro sem
  rede e sem certificado aceito pela SEFAZ — a base de todo o simulador.
- **Detalhe que morde** (testado): com `OnTransmit` ligado, `SSL.HTTPResultCode` **não** é populado; quem
  precisa distinguir "respondeu mas ilegível" de "não respondeu" tem de guardar o código devolvido. Hipótese
  **não verificada**: `SSL.HTTPResultCode` pode ficar velho entre chamadas.
- **Sugestão:** documentar `OnTransmit` como ponto de extensão suportado e estável, com esses casos, e
  popular `SSL.HTTPResultCode` também nesse caminho.

### B2. O wrapper `DistribuicaoDFePorUltNSU` levanta exceção para qualquer `cStat` que não seja 137/138

- **O que acontece** (lido): `TratarResposta` só considera sucesso 137/138; o wrapper de conveniência levanta
  exceção nos demais — inclusive **consumo indevido (656)** e serviço indisponível (108/109), que são respostas
  normais do protocolo.
- **Nosso contorno:** chamamos `WebServices.DistribuicaoDFe.Executar` direto (devolve só `Boolean`) e lemos
  `retDistDFeInt`.
- **Sugestão:** documentar; ou oferecer um método que devolva o lote e o `cStat` sem levantar.

### B3. No Delphi, o XML é "UTF-8 embutido em String": cada byte vira um caractere pela página ANSI

- **O que acontece** (testado no Delphi Win64): `docZip.XML` e `RetInfEvento.XML` chegam com os bytes UTF-8
  reinterpretados pela página de código ANSI (`É` chega como `Ã‰`). No FPC é invisível (String = bytes). Quem
  publica ou exibe o XML no Delphi sem converter mostra mojibake.
- **Nosso contorno:** `TextoDoAcbr` / `TextoParaAcbr` em `src/DFe.XmlTexto.pas`, na única fronteira com o ACBr.
- **Sugestão:** documentar a convenção (é conhecida por quem convive com o ACBr, mas não está escrita) e, se
  possível, oferecer uma propriedade que devolva o texto decodificado.

### B4. `Geral.RetirarAcentos = True` remove os acentos do texto livre do evento (`xJust`) em silêncio

- **O que acontece** (testado): "não" sai como "nao", sem erro nem aviso. O XSD da SEFAZ (`TMotivo`) aceita
  U+0020..U+00FF, então o acento seria válido.
- **Nosso contorno:** ligamos `RetirarAcentos := False` e tratamos comprimento em caracteres, `Trim` e a recusa
  do que o XSD rejeita. **Não sabemos se a SEFAZ real aceita** (sem certificado).
- **Sugestão:** documentar a interação com `xJust`; considerar tratar por campo em vez de global.

### B5. Manifestação: valores padrão que produzem um evento errado sem avisar

- **O que acontece** (lido e testado): a manifestação vai ao Ambiente Nacional, mas `infEvento.cOrgao` tem
  por padrão a UF da chave, que o AN rejeita (o correto é **91**); e `infEvento.CNPJ` vazio faz o ACBr usar o
  CNPJ **da chave**, isto é, o do emitente — o correto para manifestação é o do **destinatário**.
- **Nosso contorno:** fixamos `cOrgao = 91` e o CNPJ do destinatário em `EnviarEvento`.
- **Sugestão:** documentar; ou um método de conveniência para manifestação que já faça isso.

### B6. Requisitos de execução escondidos

- **Pasta `Schemas\*.xsd`** (testado): o ACBr exige a pasta configurada em `PathSchemas` **até para a
  distribuição**, que não valida nada; um `.xsd` vazio basta. Sem ela, falha sem uma mensagem que aponte a causa.
- **`ACBr.inc` define `DFE_SEM_XMLSEC` por padrão** (testado): `SSLXmlSignLib := xsXmlSec` levanta exceção em
  tempo de execução; o caminho suportado é `xsLibXml2`. Para assinar evento é preciso libxml2 (não libxmlsec1).
- **Nome único da libxml2** (testado): o ACBr carrega `libxml2.dll` (Windows) / `libxml2.so` (Linux) — este é
  o link do pacote `-dev`; o pacote de runtime do Debian só traz `libxml2.so.2`, então "instalei a libxml2"
  não basta. Ver `docs/dependencias-runtime.md`.
- **Sugestão:** documentar esses requisitos num lugar só, e/ou tentar também o nome versionado (`.so.2`).

## C — Conveniência

### C1. Grava XMLs em disco por padrão

- **O que acontece** (testado): `Geral.Salvar` e `Arquivos.Salvar` são `True` por padrão. Num serviço que
  consulta de hora em hora isso enche o disco sem ninguém pedir.
- **Nosso contorno:** desligamos as duas no construtor do client.
- **Sugestão:** documentar, ou um padrão mais conservador para os usos só de consulta.

### C2. O componente arrasta a LCL transitivamente, mesmo num programa console sem interface

- **O que acontece** (testado, FPC): a árvore de units passa por relatório/DANFE; sem `uses Interfaces` o link
  falha com dezenas de `Undefined symbol: WSRegisterCustomPanel...`; em Linux exige um widgetset `nogui`.
- **Nosso contorno:** `uses Interfaces` e, no Linux, `-dLCLnogui` (ver `docs/linux.md`).
- **Sugestão:** separar o que é DFe "puro" (consulta/manifestação) do que é relatório, para dispensar a LCL
  em serviços.

### C3. `dhEvento` em Linux/FPC

- **O que acontece** (testado): com o FPC 3.2.2 em Linux, `Now` devolve UTC (ignora `TZ`); o ACBr escreve
  `+00:00`, fora da lista da NT 2012/002 (`-02:00/-03:00/-04:00`). Este é mais um limite do FPC do que do
  ACBr, mas o ACBr não protege contra isso.
- **Nosso contorno:** calculamos o instante em UTC e configuramos `TimeZoneConf` em modo manual (`-03:00`),
  com `ModoDeteccao` **antes** de `TimeZoneStr`, senão o ACBr zera a string (`src/DFe.Fuso.pas`).
- **Sugestão:** documentar a ordem das propriedades de fuso; opcionalmente validar o offset escrito.

---

## Possíveis pedidos que dependem de demanda (não fizemos nada aqui)

- **Sobrescrever a URL de um serviço por configuração** (para apontar a um simulador sem `OnTransmit`). Só teria
  valor para quem usa a **ACBrLib** de outra linguagem, onde não há `OnTransmit`. Não verificamos se a ACBrLib
  já oferece algo assim. No fonte que temos há suporte a proxy e uma tabela de URLs compilada
  (`ACBrNFeServicos.rc`), nada de sobrescrita.
