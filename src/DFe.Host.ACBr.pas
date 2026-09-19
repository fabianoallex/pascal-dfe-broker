unit DFe.Host.ACBr;

{$I dfe.inc}

{ O que o host precisa do ACBr e o core (DFe.Host.Aplicacao) nao pode ter: a
  fabrica de clients reais e a verificacao do ambiente de execucao. Fica numa
  unit propria, fora do pacote, para a aplicacao continuar testavel sem ACBr.

  Credenciais do certificado digital (.pfx, senha) NUNCA passam por
  DFe.Config -- o core so' sabe CnpjCpf/UF. Aqui elas sao lidas do MESMO
  arquivo INI, das chaves que o parser do core ignora:

    [dfe]
    Ambiente=producao            ; ou homologacao (padrao: producao)
    PathSchemas=Schemas          ; XSDs oficiais (padrao: 'Schemas' ao lado do exe)

    [certificado:matriz]
    ArquivoPFX=matriz.pfx        ; relativo = relativo a pasta do INI
    Senha=...                    ; ou:
    SenhaEnv=DFE_SENHA_MATRIZ    ; nome de variavel de ambiente (preferivel: o
                                 ; arquivo de config nao guarda segredo)

  ATENCAO com o cursor: os NSUs de producao e de homologacao sao SEPARADOS na
  SEFAZ, mas o namespace do cursor (DFe.Orquestrador.MontarNamespaceCursor) nao
  inclui o ambiente. Trocar Ambiente exige apontar CursorPath para outro
  arquivo. }

interface

uses
  SysUtils, IniFiles,
  ACBrDFe.Conversao,
  DFe.Types,
  DFe.Errors,
  DFe.Ambiente,
  DFe.Ambiente.ACBr,
  DFe.Provider,
  DFe.Config,
  DFe.Client.ACBrNFe;

type
  TDFeFabricaClientesACBr = class
  private
    FCaminhoConfig: string;
    function Resolver(const ACaminho: string): string;
    function PathSchemas: string;
    function Ambiente: TACBrTipoAmbiente;
  public
    constructor Create(const ACaminhoConfig: string);

    { E' a TDFeClientFactory do host (of object). Le o INI a cada chamada, entao
      um alias novo numa recarga a quente ja' traz o proprio .pfx. }
    function CriarClient(const ACertificado: TDFeConfigCertificado): IDFeDistribuicaoClient;

    { OpenSSL, libxml2 e XSDs -- ver docs/dependencias-runtime.md. O host chama
      isto na subida e recusa iniciar se faltar algo obrigatorio. }
    function VerificarAmbiente: TDFeRelatorioAmbiente;
  end;

implementation

constructor TDFeFabricaClientesACBr.Create(const ACaminhoConfig: string);
begin
  inherited Create;
  FCaminhoConfig := ExpandFileName(ACaminhoConfig);
end;

function TDFeFabricaClientesACBr.Resolver(const ACaminho: string): string;
begin
  if (ACaminho = '') or (ACaminho[1] = '/') or (ACaminho[1] = '\')
    or ((Length(ACaminho) > 1) and (ACaminho[2] = ':')) then
    Result := ACaminho
  else
    Result := IncludeTrailingPathDelimiter(ExtractFilePath(FCaminhoConfig)) + ACaminho;
end;

function TDFeFabricaClientesACBr.PathSchemas: string;
var
  LIni: TMemIniFile;
begin
  LIni := TMemIniFile.Create(FCaminhoConfig);
  try
    // vazio = padrao do ACBr ('Schemas' ao lado do executavel)
    Result := Resolver(LIni.ReadString('dfe', 'PathSchemas', ''));
  finally
    LIni.Free;
  end;
end;

function TDFeFabricaClientesACBr.Ambiente: TACBrTipoAmbiente;
var
  LIni: TMemIniFile;
  LValor: string;
begin
  LIni := TMemIniFile.Create(FCaminhoConfig);
  try
    LValor := LowerCase(Trim(LIni.ReadString('dfe', 'Ambiente', 'producao')));
  finally
    LIni.Free;
  end;
  if LValor = 'producao' then
    Result := taProducao
  else if LValor = 'homologacao' then
    Result := taHomologacao
  else
    raise Exception.CreateFmt('Config: [dfe] Ambiente="%s" desconhecido (use "producao" ou "homologacao")', [LValor]);
end;

function TDFeFabricaClientesACBr.CriarClient(const ACertificado: TDFeConfigCertificado): IDFeDistribuicaoClient;
var
  LIni: TMemIniFile;
  LSecao, LSenhaEnv: string;
  LCredencial: TDFeCredencialCertificado;
begin
  if not SameText(ACertificado.ProviderIdentificador, 'nfe') then
    raise Exception.CreateFmt(
      'Config: certificado "%s" usa o provider "%s", que ainda nao tem client ACBr (so'' "nfe")',
      [ACertificado.Alias, ACertificado.ProviderIdentificador]);

  LSecao := 'certificado:' + ACertificado.Alias;
  LIni := TMemIniFile.Create(FCaminhoConfig);
  try
    LCredencial.ArquivoPFX := Resolver(LIni.ReadString(LSecao, 'ArquivoPFX', ''));
    LCredencial.Senha := LIni.ReadString(LSecao, 'Senha', '');
    LSenhaEnv := LIni.ReadString(LSecao, 'SenhaEnv', '');
  finally
    LIni.Free;
  end;

  if LCredencial.ArquivoPFX = '' then
    raise Exception.CreateFmt('Config: secao "%s" sem "ArquivoPFX"', [LSecao]);
  if LSenhaEnv <> '' then
  begin
    LCredencial.Senha := GetEnvironmentVariable(LSenhaEnv);
    if LCredencial.Senha = '' then
      raise Exception.CreateFmt(
        'Config: secao "%s": a variavel de ambiente "%s" (SenhaEnv) esta vazia ou nao existe', [LSecao, LSenhaEnv]);
  end;
  if not FileExists(LCredencial.ArquivoPFX) then
    raise Exception.CreateFmt('Config: secao "%s": arquivo "%s" nao existe', [LSecao, LCredencial.ArquivoPFX]);

  LCredencial.PathSchemas := PathSchemas;
  Result := TDFeDistribuicaoClientACBrNFe.Create(LCredencial, Ambiente);
end;

function TDFeFabricaClientesACBr.VerificarAmbiente: TDFeRelatorioAmbiente;
begin
  Result := VerificarAmbienteACBr(PathSchemas, [uaDistribuicao, uaManifestacao]);
end;

end.
