unit DFe.Host.ACBr;

{$I dfe.inc}

{ O que o host precisa do ACBr e o core (DFe.Host.Aplicacao) nao pode ter: a
  fabrica de clients reais e a verificacao do ambiente de execucao. Fica numa
  unit propria, fora do pacote, para a aplicacao continuar testavel sem ACBr.

  Credenciais do certificado digital (.pfx, senha) NUNCA passam por
  DFe.Config -- o core so' sabe CnpjCpf/UF. Aqui elas sao lidas do MESMO
  arquivo INI, das chaves que o parser do core ignora:

    [dfe]
    Ambiente=producao            ; ou homologacao (padrao: producao); pode ser sobrescrito por [certificado:*]
    PathSchemas=Schemas          ; XSDs oficiais (padrao: 'Schemas' ao lado do exe)
    SimuladorURL=http://127.0.0.1:9200   ; opcional: leva as consultas a um SIMULADOR da SEFAZ
                                 ; (outro processo) em vez de a SEFAZ -- ver
                                 ; docs/simulador-standalone.md. RECUSADO com
                                 ; Ambiente=producao, salvo SimuladorPermitirProducao=true
    SimuladorPermitirProducao=false

    [certificado:matriz]
    ArquivoPFX=matriz.pfx        ; relativo = relativo a pasta do INI
    Senha=...                    ; ou:
    SenhaEnv=DFE_SENHA_MATRIZ    ; nome de variavel de ambiente (preferivel: o
                                 ; arquivo de config nao guarda segredo)

  Os NSUs de producao e de homologacao sao SEPARADOS na SEFAZ; o cursor os
  distingue pelo namespace (homologacao ganha o sufixo '/homologacao', ver
  DFe.Orquestrador.MontarNamespaceCursor), entao um mesmo arquivo de cursor serve
  aos dois ambientes. }

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
  DFe.Transmissor,
  DFe.Transmissor.Http,
  DFe.Transmissor.Http.Cliente,
  DFe.Host.Aplicacao,
  DFe.Client.ACBrNFe;

type
  TDFeFabricaClientesACBr = class
  private
    FCaminhoConfig: string;
    FLog: TDFeLogProc;
    function Resolver(const ACaminho: string): string;
    function PathSchemas: string;
  public
    constructor Create(const ACaminhoConfig: string);

    { Onde o AVISO de transporte simulado vai (o host liga ao log dele). Sem
      isto o aviso nao aparece -- por isso os hosts SEMPRE ligam. }
    property AoLog: TDFeLogProc read FLog write FLog;

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

function TDFeFabricaClientesACBr.CriarClient(const ACertificado: TDFeConfigCertificado): IDFeDistribuicaoClient;
var
  LIni: TMemIniFile;
  LSecao, LSenhaEnv: string;
  LCredencial: TDFeCredencialCertificado;
  LSimuladorURL, LMensagem: string;
  LPermitirProducao: Boolean;
  LTransmissor: IDFeTransmissor;
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
    LSimuladorURL := Trim(LIni.ReadString('dfe', 'SimuladorURL', ''));
    LPermitirProducao := LerBooleano(LIni.ReadString('dfe', 'SimuladorPermitirProducao', ''), False);
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

  // Transporte simulado (outro processo), com as salvaguardas de DecidirUsoDoSimulador.
  LTransmissor := nil;
  case DecidirUsoDoSimulador(LSimuladorURL, ACertificado.Ambiente, LPermitirProducao, LMensagem) of
    usRecusado:
      raise Exception.CreateFmt('Config: certificado "%s": %s', [ACertificado.Alias, LMensagem]);
    usPermitido:
      begin
        LTransmissor := TDFeTransmissorHttp.Create(LSimuladorURL, TDFeHttpPostPadrao.Create);
        if Assigned(FLog) then
          FLog('AVISO', Format('[%s] %s', [ACertificado.Alias, LMensagem]));
      end;
  end;

  // O ambiente vem da config ja' interpretada (DFe.Config): e' o MESMO valor que
  // a unidade usa para escolher o cursor, entao client e cursor nao divergem.
  if ACertificado.Ambiente = daHomologacao then
    Result := TDFeDistribuicaoClientACBrNFe.Create(LCredencial, taHomologacao, LTransmissor)
  else
    Result := TDFeDistribuicaoClientACBrNFe.Create(LCredencial, taProducao, LTransmissor);
end;

function TDFeFabricaClientesACBr.VerificarAmbiente: TDFeRelatorioAmbiente;
begin
  Result := VerificarAmbienteACBr(PathSchemas, [uaDistribuicao, uaManifestacao]);
end;

end.
