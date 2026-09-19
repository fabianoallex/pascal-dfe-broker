unit DFe.Ambiente.ACBr;

{$I dfe.inc}

{ Verificador de AMBIENTE DE EXECUCAO do client ACBr -- ver DFe.Ambiente e
  docs/dependencias-runtime.md.

  Carrega de verdade (pelos mesmos carregadores que o ACBr usa, entao o
  resultado vale para o que o client vai encontrar): OpenSSL, libxml2, e
  confere os XSDs em disco. Nao precisa de certificado nem de rede.

  Depende do fonte do ACBr (OpenSSLExt, ACBrLibXml2Ext), por isso NAO esta no
  pacote Lazarus -- mesma regra de DFe.Client.ACBrNFe. }

interface

uses
  SysUtils,
  DFe.Ambiente;

const
  { Pasta que o ACBr usa quando nao ha PathSchemas explicito: 'Schemas' ao lado
    do executavel. }
  DFE_PASTA_SCHEMAS_PADRAO = 'Schemas';

  { XSDs que a MANIFESTACAO usa -- o fecho MINIMO, conferido em execucao
    (2026-09-18, tests/Integration/AcbrSim, "PastaMinimaDeXsds"): so' com estes
    11 arquivos o EnviarEvento dos 4 tipos monta, assina, valida e registra; sem
    qualquer um o ACBr falha ("Arquivo ... nao encontrado" ou schema invalido).
    O ACBr valida o LOTE contra envEvento e cada EVENTO contra confRecebto +
    o detEvento do tipo (e2102xx); os demais sao o fecho de xs:include/
    xs:import desses. NOTE que "envConfRecebto" sozinho NAO basta (a primeira
    versao desta lista, com 5 arquivos, estava errada -- o teste pegou). }
  DFE_XSDS_MANIFESTACAO: array[0..10] of string = (
    'envEvento_v1.00.xsd',
    'leiauteEvento_v1.00.xsd',
    'envConfRecebto_v1.00.xsd',
    'confRecebto_v1.00.xsd',
    'leiauteConfRecebto_v1.00.xsd',
    'e210200_v1.00.xsd',
    'e210210_v1.00.xsd',
    'e210220_v1.00.xsd',
    'e210240_v1.00.xsd',
    'tiposBasico_v1.03.xsd',
    'xmldsig-core-schema_v1.01.xsd');

{ MASCARA as excecoes de ponto flutuante da THREAD ATUAL (FPC; no Delphi e' no-op).
  O FPC deixa habilitadas as excecoes de FPU (x87 e SSE) e as bibliotecas
  nativas em C (libxml2, OpenSSL) fazem operacoes que as disparam -- no Linux
  x86_64 a libxml2 derrubava a inicializacao com "EInvalidOp: Invalid floating
  point operation" (achado em 2026-09-18 rodando os testes de integracao no
  Docker). E' o mesmo que o Lazarus faz para o GTK. A mascara vale POR THREAD:
  chame em toda thread que va usar o client/verificador (o client ja chama a
  cada operacao; VerificarAmbienteACBr tambem). Efeito colateral aceito:
  divisao por zero em ponto flutuante passa a dar Inf/NaN em vez de excecao --
  nada neste projeto depende dessa excecao. }
procedure PrepararParaBibliotecasNativas;

{ AUsos so' muda o que se exige dos XSDs: a manifestacao pede tambem os XSDs do
  evento. OpenSSL e libxml2 sao obrigatorios em qualquer uso.

  APathSchemas vazio = DFE_PASTA_SCHEMAS_PADRAO ao lado do executavel (o mesmo
  padrao do ACBr). Carrega OpenSSL e libxml2 como efeito colateral: e' o que
  se quer verificar. }
function VerificarAmbienteACBr(const APathSchemas: string;
  const AUsos: TDFeUsosAmbiente): TDFeRelatorioAmbiente;

implementation

uses
  {$IFDEF FPC}Math,{$ENDIF}
  OpenSSLExt,
  ACBrLibXml2Ext;

procedure PrepararParaBibliotecasNativas;
begin
  {$IFDEF FPC}
  SetExceptionMask(GetExceptionMask +
    [exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  {$ENDIF}
end;

function BitsDoExecutavel: string;
begin
  Result := IntToStr(SizeOf(Pointer) * 8);
end;

{ OpenSSL 3.0.x (Debian 12, Ubuntu 22.04): neste processo o PROVIDER PADRAO nao
  vem ativo -- OSSL_PROVIDER_available('default') = 0 -- e entao toda operacao
  de PKCS12 falha: PKCS12_parse devolve 0 com "digital envelope routines::
  unsupported / key gen error / mac generation error", e o ACBr reporta
  "Erro ao ler informacoes do Certificado" para um .pfx PERFEITAMENTE valido
  (o openssl da linha de comando le o mesmo arquivo). Achado em 2026-09-18
  rodando a integracao no Linux (Docker); no Windows, com OpenSSL 3.2/3.5, o
  provider ja vem ativo, por isso nunca apareceu. Carregar 'default'
  explicitamente resolve (PKCS12_parse -> 1) e e' idempotente. }
procedure GarantirProviderPadraoDoOpenSSL3;
begin
  if OpenSSLVersionNum >= $30000000 then
    if OSSL_PROVIDER_available(nil, 'default') = 0 then
      OSSL_PROVIDER_load(nil, 'default');
end;

procedure VerificarOpenSSL(var R: TDFeRelatorioAmbiente);
var
  LDetalhe: string;
begin
  if InitSSLInterface then
  begin
    GarantirProviderPadraoDoOpenSSL3;
    LDetalhe := string(OpenSSLVersion(0));
    { libssl e libcrypto podem vir de PASTAS diferentes (a primeira de cada nome
      no PATH) -- versoes misturadas sao fonte de erro dificil; mostrar as duas. }
    if SSLLibFile <> '' then
      LDetalhe := LDetalhe + ' [libssl: ' + SSLLibFile + ']';
    if (SSLUtilFile <> '') and (SSLUtilFile <> SSLLibFile) then
      LDetalhe := LDetalhe + ' [libcrypto: ' + SSLUtilFile + ']';
    AdicionarDependencia(R, 'OpenSSL (certificado e TLS)', True, True, LDetalhe, '');
  end
  else
    AdicionarDependencia(R, 'OpenSSL (certificado e TLS)', True, False,
      'nao foi possivel carregar libcrypto/libssl',
      {$IFDEF DFE_WINDOWS}
      'Copie libcrypto-3-x64.dll e libssl-3-x64.dll (OpenSSL 3) para a pasta do executavel; ' +
      'se o executavel for de 32 bits, libcrypto-3.dll e libssl-3.dll. Este executavel e de ' +
      BitsDoExecutavel + ' bits e a arquitetura das DLLs precisa ser a mesma.'
      {$ELSE}
      'Instale o OpenSSL 3 (Debian/Ubuntu: apt install libssl3).'
      {$ENDIF}
      );
end;

{ OBRIGATORIA SEMPRE, inclusive so' para consultar documentos: o ACBrXmlDocument
  (que o ACBr usa para interpretar TODA resposta, em qualquer compilador) e' um
  invólucro da libxml2. Sem ela, TRetDistDFeInt.LerXml engole o erro e o lote
  sai com cStat = 0 -- falha silenciosa (achado em 2026-09-18 ao tirar a libxml2
  do PATH; antes eu supunha que so' a manifestacao a usava). }
procedure VerificarLibXml2(var R: TDFeRelatorioAmbiente);
var
  LDetalhe: string;
begin
  if InitLibXml2Interface then
  begin
    LDetalhe := 'carregada';
    if LibXml2File <> '' then
      LDetalhe := LDetalhe + ' [' + LibXml2File + ']';
    AdicionarDependencia(R, 'libxml2 (ler toda resposta; assinar e validar eventos)', True, True, LDetalhe, '');
  end
  else
    AdicionarDependencia(R, 'libxml2 (ler toda resposta; assinar e validar eventos)', True, False,
      'nao foi possivel carregar ' + LIBXML2_SO,
      {$IFDEF DFE_WINDOWS}
      'Copie ' + LIBXML2_SO + ' (com zlib1.dll ao lado) para a pasta do executavel, na mesma ' +
      'arquitetura (' + BitsDoExecutavel + ' bits). Nao ha binario oficial para Windows; ver ' +
      'docs/dependencias-runtime.md.'
      {$ELSE}
      'O ACBr procura exatamente "' + LIBXML2_SO + '" (o link do pacote -dev): instale ' +
      'libxml2-dev, ou crie o link libxml2.so -> libxml2.so.2.'
      {$ENDIF}
      );
end;

procedure VerificarSchemas(var R: TDFeRelatorioAmbiente; const APathSchemas: string;
  const AManifestacao: Boolean);
var
  LPath, LFaltam: string;
  LBusca: TSearchRec;
  LTotal, I: Integer;
  LCorrecao: string;
begin
  LPath := APathSchemas;
  if LPath = '' then
    LPath := ExtractFilePath(ParamStr(0)) + DFE_PASTA_SCHEMAS_PADRAO;
  LPath := IncludeTrailingPathDelimiter(LPath);

  LCorrecao := 'Copie os XSDs oficiais de NFe para "' + LPath + '" (no repositorio: ' +
    'vendor/ACBr/Exemplos/ACBrDFe/Schemas/NFe, depois de tools/init-acbr-submodule.sh; ou o ' +
    'pacote de schemas do portal da NF-e) ou informe outra pasta em PathSchemas.';

  LTotal := 0;
  if DirectoryExists(LPath) then
    if FindFirst(LPath + '*.xsd', faAnyFile, LBusca) = 0 then
    begin
      repeat
        Inc(LTotal);
      until FindNext(LBusca) <> 0;
      FindClose(LBusca);
    end;

  if not DirectoryExists(LPath) then
    AdicionarDependencia(R, 'XSDs oficiais (pasta de schemas)', True, False,
      'pasta inexistente: ' + LPath, LCorrecao)
  else if LTotal = 0 then
    AdicionarDependencia(R, 'XSDs oficiais (pasta de schemas)', True, False,
      'nenhum .xsd em ' + LPath, LCorrecao)
  else
    AdicionarDependencia(R, 'XSDs oficiais (pasta de schemas)', True, True,
      IntToStr(LTotal) + ' arquivo(s) .xsd em ' + LPath, '');

  LFaltam := '';
  for I := Low(DFE_XSDS_MANIFESTACAO) to High(DFE_XSDS_MANIFESTACAO) do
    if not FileExists(LPath + DFE_XSDS_MANIFESTACAO[I]) then
    begin
      if LFaltam <> '' then
        LFaltam := LFaltam + ', ';
      LFaltam := LFaltam + DFE_XSDS_MANIFESTACAO[I];
    end;
  if LFaltam = '' then
    AdicionarDependencia(R, 'XSDs da manifestacao (evento)', AManifestacao, True,
      'os ' + IntToStr(Length(DFE_XSDS_MANIFESTACAO)) + ' arquivos necessarios estao presentes', '')
  else
    AdicionarDependencia(R, 'XSDs da manifestacao (evento)', AManifestacao, False,
      'faltam: ' + LFaltam, LCorrecao);
end;

function VerificarAmbienteACBr(const APathSchemas: string;
  const AUsos: TDFeUsosAmbiente): TDFeRelatorioAmbiente;
begin
  PrepararParaBibliotecasNativas;
  Result.Itens := nil;
  VerificarOpenSSL(Result);
  VerificarLibXml2(Result);
  VerificarSchemas(Result, APathSchemas, uaManifestacao in AUsos);
end;

end.
