# Dependências de execução

O broker depende de coisas que **não estão no binário**: bibliotecas nativas e arquivos XSD. Faltar qualquer uma não aparece na compilação. Este documento diz o que é necessário, como obter, e como verificar — antes de a falta virar um erro enganoso em produção.

> Estado (2026-09-18): verificado em **Windows 11, FPC Win64 e Delphi Win64**. **Linux e Delphi Win32 não foram testados** — o que consta para eles vem da leitura do fonte do ACBr e está marcado.

## O que é necessário

| Dependência | Para quê | Obrigatória |
|---|---|---|
| **OpenSSL** (`libcrypto` + `libssl`) | carregar o certificado `.pfx`, TLS | sempre |
| **libxml2** (+ `zlib1.dll` no Windows) | o ACBr lê **toda** resposta da SEFAZ com ela (`ACBrXmlDocument`) e assina/valida eventos | **sempre** |
| **XSDs oficiais de NFe** | o ACBr consulta a pasta de schemas até para a distribuição (resolve a versão do serviço); a manifestação valida o XML contra eles | sempre (≥ 1 `.xsd`); a manifestação exige os 11 abaixo |

> **A libxml2 é obrigatória mesmo para só consultar documentos.** Uma versão anterior deste projeto (e deste documento) dizia que só a manifestação a usava — errado. Sem ela o ACBr **engole o erro de leitura** e o lote volta com `cStat = 0`, sem exceção. O client agora verifica o ambiente antes e recusa `cStat = 0` (ver "Como o broker reage").

### Como o ACBr acha as bibliotecas

Por **nome fixo**, pelo mecanismo do sistema operacional (não por caminho):

- **OpenSSL, Windows 64 bits**: `libssl-3-x64.dll` / `libcrypto-3-x64.dll` (ou as `-1_1-x64`); **32 bits**: `libssl-3.dll` / `libcrypto-3.dll` (ou `-1_1`); nomes antigos (`ssleay32`/`libeay32`) também são tentados. **Linux**: `libssl.so`, `libssl.so.3`, `libssl.so.1.1`… e `libcrypto.so.3`… *(lido do fonte, `OpenSSLExt.pas`; não testado em Linux)*.
- **libxml2**: Windows `libxml2.dll`; Linux **`libxml2.so`** — o link *sem versão*, que no Debian/Ubuntu só o pacote `-dev` cria (o pacote de runtime traz `libxml2.so.2`). *(`ACBrLibXml2Ext.pas`; não testado em Linux.)*
- **Arquitetura**: as DLLs precisam ter os **mesmos bits do executável**. Um executável de 64 bits com DLLs de 32 (ou o contrário) falha ao carregar.
- **Onde procurar (Windows)**: primeiro a **pasta do executável**, depois o `PATH`. **Recomendado: copie as DLLs para a pasta do executável** do broker — assim o resultado não depende do `PATH` do usuário/serviço que o inicia. `libssl` e `libcrypto` são procurados **separadamente**: podem vir de pastas diferentes (e de versões diferentes!) se estiverem em várias entradas do `PATH`; o verificador mostra o caminho de cada uma.

## Como obter

**Nada disto é distribuído neste repositório.** Origens que funcionaram *nesta máquina* (não são canais oficiais nem recomendação de suporte — confira licença e procedência, e mantenha atualizado por segurança):

- **OpenSSL 3 (Windows x64)**: os binários `libcrypto-3-x64.dll` e `libssl-3-x64.dll` do **Git for Windows** (`mingw64\bin`, 3.2.4) e do **PostgreSQL 18** (3.5.4) funcionaram. O OpenSSL 3 é Apache-2.0.
- **libxml2 (Windows x64)**: o `libxml2.dll` do **PostgreSQL 18** (`bin`) funcionou; ele importa só `zlib1.dll` e o runtime do Visual C++ (`VCRUNTIME140`, UCRT), então copie o `zlib1.dll` junto. O projeto libxml2 (MIT) distribui código-fonte; binários para Windows vêm de terceiros (por exemplo vcpkg, conda-forge, ou embarcados por outros produtos como o PostgreSQL). **Não verificado** além do caso do PostgreSQL.
- **Linux (Debian/Ubuntu)** *(não testado)*: `apt install libssl3 libxml2` e, para o nome que o ACBr procura, `apt install libxml2-dev` **ou** `ln -s libxml2.so.2 libxml2.so` na pasta das bibliotecas.
- **XSDs**: no repositório, `vendor/ACBr/Exemplos/ACBrDFe/Schemas/NFe` (depois de rodar `tools/init-acbr-submodule.sh`, que já inclui essa pasta, ~2 MB), ou o pacote de schemas do portal da NF-e. Copie para uma pasta e aponte `PathSchemas` (`TDFeCredencialCertificado.PathSchemas`); sem isso o ACBr usa `Schemas\` ao lado do executável.
  - **Só distribuição**: basta **um** `.xsd` (um arquivo vazio serviu nos testes; use os reais).
  - **Manifestação**: estes **11** arquivos (o fecho mínimo, conferido enviando os 4 tipos de manifestação; ver `DFE_XSDS_MANIFESTACAO`): `envEvento_v1.00.xsd`, `leiauteEvento_v1.00.xsd`, `envConfRecebto_v1.00.xsd`, `confRecebto_v1.00.xsd`, `leiauteConfRecebto_v1.00.xsd`, `e210200_v1.00.xsd`, `e210210_v1.00.xsd`, `e210220_v1.00.xsd`, `e210240_v1.00.xsd`, `tiposBasico_v1.03.xsd`, `xmldsig-core-schema_v1.01.xsd`.

## Como verificar

**Ferramenta**: `tools/verificar-ambiente` (FPC; compile com `lazbuild tools/verificar-ambiente/VerificarAmbiente.lpi`). Rode **no servidor, com o mesmo usuário e a pasta do executável do broker** — o que importa é o que aquele processo enxerga:

```
VerificarAmbiente [pasta-de-schemas] [--distribuicao]
```

Exemplo de saída (ambiente sem a libxml2):

```
Executavel de 64 bits: C:\...\VerificarAmbiente.exe
[OK]       OpenSSL (certificado e TLS) -- OpenSSL 3.2.4 ... [libssl: C:\Program Files\Git\mingw64\bin\libssl-3-x64.dll]
[FALTA]    libxml2 (ler toda resposta; assinar e validar eventos) -- nao foi possivel carregar libxml2.dll
           -> Copie libxml2.dll (com zlib1.dll ao lado) para a pasta do executavel, ...
[OK]       XSDs oficiais (pasta de schemas) -- 201 arquivo(s) .xsd em ...
[OK]       XSDs da manifestacao (evento) -- os 11 arquivos necessarios estao presentes
Ambiente INCOMPLETO: 1 dependencia(s) obrigatoria(s) ausente(s).
```

Código de saída: `0` completo, `1` falta algo obrigatório, `2` uso.

**No código**: `DFe.Ambiente.ACBr.VerificarAmbienteACBr(PathSchemas, [uaDistribuicao, uaManifestacao])` devolve o relatório (`DFe.Ambiente` tem `AmbienteCompleto`, `FormatarRelatorio`). **O host real deve chamá-lo na inicialização, registrar o relatório e recusar subir** (ou subir avisando) se `AmbienteCompleto` for falso — os hosts ainda não existem (ver `CLAUDE.md`, "Próximos marcos").

## Como o broker reage a um ambiente incompleto

`TDFeDistribuicaoClientACBrNFe` verifica o ambiente **antes de tocar no certificado ou na rede** e levanta `EDFeAmbienteIndisponivel` (`DFe.Errors`) com o que falta e como corrigir. O orquestrador e o processador de manifestação **registram o erro e mantêm a unidade agendada** (não pausam): consertado o servidor, a próxima tentativa funciona sozinha, **sem reiniciar** (só o sucesso da verificação é guardado). Antes disto:

- DLL do OpenSSL ausente saía como **certificado inválido** — e a unidade era **pausada**;
- libxml2 ou XSD ausente saía como **falha de comunicação** (parecia transitório) ou, na leitura da resposta, como um lote com **`cStat = 0` silencioso**.

Além disso o client recusa um `retDistDFeInt` sem `cStat` (`EDFeRespostaInvalida`), porque o ACBr engole erros de leitura em vez de levantá-los.

## Fora do escopo deste documento

O **certificado digital** (`.pfx`, validade, CNPJ) é verificado pelo client a cada chamada (`EDFeCertificadoInvalido`), não aqui. **TLS/HTTP reais com a SEFAZ nunca foram testados** (sem certificado ICP-Brasil real; ver `docs/simulador-sefaz.md`, Fase 5).
