# Simulador da SEFAZ para testes — plano de execução

> Estado: **planejado, nada implementado** (2026-09-18). Este documento existe para uma sessão futura retomar sem depender do contexto em que o plano nasceu. O que está marcado **[verificado]** foi conferido lendo o fonte do ACBr em `vendor/ACBr`; **[hipótese]** ainda precisa ser confirmado por um spike (Fase 0).

## Por que

Não há certificado digital real disponível para o projeto, e isso não vai mudar em breve. Mas mesmo com certificado, a SEFAZ real é um péssimo alvo de teste para o que mais importa:

- consumo indevido (cStat 656) só acontece depois de consultar antes de 1h — não dá para provocar a pedido;
- serviço indisponível (108/109), `docZip` corrompido, timeout e salto de NSU não são reproduzíveis;
- a janela de 1h por consulta torna qualquer teste automatizado inviável.

Hoje, `DFe.Client.ACBrNFe` (`Consultar` e `EnviarEvento`) só tem **verificação de compilação** — nunca rodou. O simulador existe para mudar isso, e como bônus permite a qualquer pessoa experimentar o broker sem certificado (coerente com a meta de baixar fricção de adoção).

**Limite que não some**: o simulador codifica a *nossa leitura* das NTs. Se entendermos algo errado, ele replica o erro e o teste passa (risco de espelho). Mitigações: construir respostas a partir das NTs/XSDs em `docs/referencias/`; e, no futuro, um "modo gravação" para quem tiver certificado capturar respostas reais anonimizadas como fixtures (alinhado a `CONTRIBUTING.md`).

## A descoberta que muda o custo: `TACBrDFe.OnTransmit`

**[verificado]** `ACBrDFe.pas` declara:

```pascal
TACBrDFeOnTransmit = procedure(const Dados, URL, SoapAction, MimeType: String;
  var Resposta: String; var HTTPResultCode: Integer; var InternalErrorCode: Integer) of object;
```

e `ACBrDFeWebService.pas` (`TDFeWebService.EnviarDados`, ~linha 410) o chama **no lugar do HTTP** quando atribuído ("Envio por Evento... Aplicação cuidará do envio"). Se `InternalErrorCode <> 0` levanta `EACBrDFeException`; o código `10060` vira `EACBrDFeExceptionTimeOut` (é assim que se simula timeout).

Ou seja: o ACBr **real** roda inteiro — montagem do envelope SOAP e do `distDFeInt`, parse da resposta, cStat, descompactação do `docZip`, e a nossa `TratarFalhaDeChamada` — e só o transporte é substituído por um callback nosso. **Sem servidor HTTP, sem TLS, sem sobrescrever URL.**

O que **não** fica coberto: TLS/HTTP de verdade (só simulável via `HTTPResultCode`/`InternalErrorCode`), e o comportamento real da SEFAZ.

## Camadas

| # | O que | Cobre | Custo |
|---|---|---|---|
| 0 | `TDFeDistribuicaoClientFake` (já existe) | orquestrador/provider com respostas roteirizadas, sem estado | feito |
| 1 | **Client fake com estado** (`IDFeDistribuicaoClient`) | máquina de NSU, janela de 1h com relógio virtual, paginação por `maxNSU`, fixtures sintéticas de `resNFe`/`procNFe`/`resEvento` — orquestrador + provider + publicação, **sem ACBr** | pequeno |
| 2 | **Simulador via `OnTransmit`** | tudo da camada 1 **mais** o `DFe.Client.ACBrNFe` de verdade (parse do ACBr, docZip, exceções) | médio |
| 3 | Servidor HTTP/TLS mútuo com certificado de teste | só a configuração OpenSSL e `GarantirCertificadoValido` de ponta a ponta | grande — provavelmente nunca |

A camada 2 **reaproveita o núcleo da camada 1** (a máquina de estado que decide o que responder); por isso o núcleo deve ser escrito **independente do transporte**, atrás de uma interface, com duas casas: um adaptador `IDFeDistribuicaoClient` (camada 1) e um adaptador SOAP para `OnTransmit` (camada 2).

## Fases

### Fase 0 — spike descartável (fazer primeiro; decide o resto)

Objetivo: transformar as hipóteses abaixo em fatos antes de construir nada. Um programa FPC Win64 (`uses Interfaces` primeiro — ver gotcha do LCL em `CLAUDE.md`) que monta o `TDFeDistribuicaoClientACBrNFe`, liga `OnTransmit` a uma resposta fixa (cStat 137) e chama `Consultar`.

Hipóteses a confirmar:

1. **Certificado autoassinado é aceito.** Gerar um `.pfx` com CN no padrão ICP-Brasil (`RAZAO SOCIAL:12345678000199`) e/ou `otherName` OID `2.16.76.1.3.3` (CNPJ). Confirmar que `SSL.CarregarCertificadoSeNecessario` carrega e que `ValidarCNPJCertificado` extrai o CNPJ. Gerar com o OpenSSL do Git (`C:\Program Files\Git\mingw64\bin\openssl.exe`) ou com a imagem `alpine/openssl` do Docker.
2. **O ACBr carrega o OpenSSL 3 instalado.** Existe `libcrypto-3-x64.dll`/`libssl-3-x64.dll` no PATH desta máquina (vêm do Git) — serve para FPC **Win64**. O smoke do Delphi é **Win32** e precisaria das DLLs de 32 bits (**[hipótese]**: pode ser um bloqueio para o lado Delphi).
3. **`Executar` completa só com `OnTransmit`**, sem exigir rede nem resolver URL de forma que falhe antes. Conferir o que `InicializarServico`/`DefinirURL` precisam (ex.: localização de `ACBrNFeServicos.ini`).
4. **Formato exato da resposta que o ACBr espera**: `TDistribuicaoDFe.TratarResposta` usa `SeparaDadosArray([...])` sobre nomes de tag do envelope SOAP — ler `ACBrNFeWebServices.pas` para saber quais, e montar o envelope de resposta idêntico.

Se (1) ou (3) falharem de forma incontornável, o valor da camada 2 cai muito e a camada 1 sozinha passa a ser o plano.

### Fase 1 — costura de injeção no client

`TDFeDistribuicaoClientACBrNFe` ganha um transmissor opcional (interface ou tipo de método próprio, ex. `IDFeTransmissor.Transmitir(const AEnvelope, AURL, ASoapAction, AMimeType): TDFeRespostaTransmissao`) que, se presente, é ligado a `FACBrNFe.OnTransmit` no construtor. Sem transmissor, comportamento idêntico ao de hoje (produção não muda). O tipo de retorno carrega texto, `HTTPResultCode` e `InternalErrorCode`.

### Fase 2 — núcleo do simulador (puro, independente de transporte)

- Estado por (CNPJ, UF): NSU corrente, `maxNSU`, instante da última consulta.
- Relógio injetável (mesmo padrão de `TDFeOrquestrador.Agora`) — nunca `Sleep`/tempo real.
- Regras (todas já verificadas em `docs/referencias/README.md`): 138 com documentos, 137 sem novidade, **656** ao consultar antes de 1h, 108/109 quando "fora do ar" roteirizado.
- Cenários roteirizáveis: consumo indevido, indisponibilidade, `docZip` corrompido, salto de NSU, timeout (`InternalErrorCode = 10060`), HTTP 500, corpo ilegível, e — importante — **documento com acentos** (ver "Encoding" abaixo).
- Gerador de fixtures sintéticas: `resNFe`, `procNFe`, `resEvento`, `procEventoNFe`, com CNPJ/chave fictícios (regra de `CONTRIBUTING.md`); reaproveita os XMLs já usados em `tests/Unit/DFe.ProviderNFeTests.pas`.
- Construtor de `docZip`: gzip + base64. Para gzip, o ACBr já traz `GZIPUtils`/`ZLibExGZ` em `Fontes/Terceiros` (o sparse-checkout já os inclui) — mas **isso é código LGPL do ACBr**; reusar em código de teste está ok (não é incorporado ao repositório), só cuidar para não copiar fonte do ACBr para dentro de `src/`. Alternativa sem ACBr: `zstream` do FCL (deflate) com cabeçalho gzip manual.

### Fase 3 — adaptador SOAP + testes de integração

- Adaptador para `OnTransmit`: lê `ultNSU`/CNPJ/`cUFAutor` do envelope recebido (e **afirma** sobre o formato — isso pega erro de formato do que o ACBr envia) e devolve o envelope de resposta.
- Testes num projeto **separado** da suíte pura (`DFeUnitTestsFpc`), porque linkam ACBr+LCL — mesmo motivo de `tools/smoke/`. Sugestão: `tests/Integration/AcbrSim/` (FPC Win64 primeiro).
- Casos mínimos: 137, 138 com 1 e N itens, 656 → `dccConsumoIndevido`, 108, timeout → `EDFeComunicacaoFalhou`, HTTP 500 → `EDFeComunicacaoFalhou`, corpo ilegível com HTTP 200 → `EDFeRespostaInvalida`, certificado vencido/CNPJ divergente → `EDFeCertificadoInvalido`, e um teste de ponta a ponta com o orquestrador + provider NFe + publicador fake.

### Fase 4 — eventos de manifestação (depende de `libxmlsec1`)

Eventos são **assinados** (`xsXmlSec`); `libxmlsec` **não existe** nesta máquina Windows (verificado: nem `libxmlsec.dll` nem `libxmlsec1.dll` no PATH). A distribuição não assina, então as Fases 0–3 não dependem disso. Para o `EnviarEvento`: usar container Debian com `libxmlsec1` (parte do trabalho de Linux/Docker adiado — ver `CLAUDE.md`, "FPC/Linux via Docker"), ou instalar a DLL no Windows. Simular `RecepcaoEvento` AN: resposta com `retEnvEvento` (cStat 128 do lote + `retEvento` com 135/136 ou rejeição), exercitando `CStatEventoRegistrado` e o `TipoEvento` `manifestacaorejeitada`.

### Fase 5 (opcional) — HTTP/TLS mútuo

Só se surgir necessidade de validar a configuração OpenSSL/TLS. Servidor `fphttpserver` (FCL) com cadeia gerada por OpenSSL. Baixo retorno frente ao custo.

## Dois riscos já identificados que o simulador pode fechar

- **Encoding do `XmlPayload`**: o ACBr guarda XML como UTF-8 embutido em `String` (declaração `encoding="UTF-8"`, convenção própria — `ConverteXMLtoUTF8` em `ACBrUtil.XMLHTML`), e nós repassamos `docZip[I].XML`/`RetInfEvento.XML` sem conversão. Um fixture com acentos no `xNome` passando pelo `docZip` do simulador confirma (ou refuta) isso sem SEFAZ.
- **[hipótese, não verificado] `SSL.HTTPResultCode` pode estar velho** entre chamadas (o valor de uma chamada anterior persiste em falhas antes da rede) — afeta a distinção `EDFeRespostaInvalida` × `EDFeComunicacaoFalhou` em `TratarFalhaDeChamada`. Cenários de falha consecutivos no simulador expõem isso.

## Para retomar numa sessão nova

1. Ler este arquivo, `CLAUDE.md` (decisões 14, 16, 17, 18) e a seção "Implementação real de `IDFeDistribuicaoClient`" de `docs/architecture.md`.
2. Rodar as suítes para confirmar o ponto de partida: FPC `lazbuild -B -r tests/Unit/fpc/DFeUnitTestsFpc.lpi` (95/95 esperado); Delphi pela IDE.
3. Começar pela **Fase 0**. Não escrever o simulador antes de ela responder as hipóteses 1–4.
4. Ao terminar a Fase 0, registrar os fatos aqui (trocar **[hipótese]** por **[verificado]**) antes de seguir.
