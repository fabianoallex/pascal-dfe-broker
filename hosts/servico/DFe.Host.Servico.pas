unit DFe.Host.Servico;

{ Servico Windows do pascal-dfe-broker (decisao 9): Delphi-only de proposito --
  um Servico Windows e' uma nocao inerentemente Windows, e o Lazarus nao tem um
  TService pronto. Quem usa Lazarus/Windows tem o host console.

  E' FINO, como o host console: toda a montagem esta em TDFeAplicacao
  (DFe.Host.Aplicacao) e a fabrica de clients reais em DFe.Host.ACBr. Aqui so'
  ficam as diferencas de um servico:

  - sem console: o log vai para arquivo (DFe.Host.LogArquivo, um por dia, na
    pasta 'logs' ao lado do arquivo de config); a falha de SUBIDA vai tambem
    para o Event Log do Windows, que e' onde o operador olha quando o servico
    "nao inicia";
  - OnStart nao pode bloquear: o ambiente e' verificado, a aplicacao sobe
    (Iniciar) e o loop (Executar) roda numa thread propria;
  - OnStop pede Parar e espera o tick em andamento terminar (ate 60 s,
    avisando o SCM que ainda esta parando).

  Configuracao: o arquivo INI vem de '--config <caminho>' na linha de comando do
  servico (ImagePath), senao 'dfe.ini' ao lado do executavel. Use caminho
  ABSOLUTO: o diretorio corrente de um servico e' C:\Windows\System32. Ver
  LEIAME.md desta pasta (instalacao, conta, senha do certificado, recuperacao).

  NAO testado em execucao pelo autor ao escrever isto (Delphi so' pela IDE, e
  nao havia sessao de servico): ver CLAUDE.md, decisao 20, para o que foi e o
  que nao foi verificado. }

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, Vcl.SvcMgr,
  DFe.Ambiente,
  DFe.Host.ACBr,
  DFe.Host.Aplicacao,
  DFe.Host.LogArquivo;

type
  { Roda TDFeAplicacao.Executar (loop bloqueante) fora da thread do servico. }
  TDFeExecutorThread = class(TThread)
  private
    FApp: TDFeAplicacao;
    FLog: TDFeLogArquivo;
  protected
    procedure Execute; override;
  public
    constructor Create(const AApp: TDFeAplicacao; const ALog: TDFeLogArquivo);
  end;

  TDFeBrokerService = class(TService)
    procedure ServiceStart(Sender: TService; var Started: Boolean);
    procedure ServiceStop(Sender: TService; var Stopped: Boolean);
  private
    FLog: TDFeLogArquivo;
    FFabrica: TDFeFabricaClientesACBr;
    FApp: TDFeAplicacao;
    FExecutor: TDFeExecutorThread;
    function CaminhoConfig: string;
    procedure Liberar;
  public
    function GetServiceController: TServiceController; override;
  end;

var
  DFeBrokerService: TDFeBrokerService;

implementation

{$R *.dfm}

const
  // quanto tempo o Stop espera o tick em andamento (uma consulta a SEFAZ pode demorar)
  ESPERA_MAXIMA_PARADA_MS = 60000;

procedure ServiceController(CtrlCode: DWord); stdcall;
begin
  DFeBrokerService.Controller(CtrlCode);
end;

{ TDFeExecutorThread }

constructor TDFeExecutorThread.Create(const AApp: TDFeAplicacao; const ALog: TDFeLogArquivo);
begin
  inherited Create(False);
  FApp := AApp;
  FLog := ALog;
end;

procedure TDFeExecutorThread.Execute;
begin
  try
    FApp.Executar;
  except
    on E: Exception do
      FLog.Registrar('ERRO', 'Loop encerrado por excecao: ' + E.ClassName + ': ' + E.Message);
  end;
end;

{ TDFeBrokerService }

function TDFeBrokerService.GetServiceController: TServiceController;
begin
  Result := ServiceController;
end;

function TDFeBrokerService.CaminhoConfig: string;
var
  I: Integer;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'dfe.ini';
  for I := 1 to ParamCount - 1 do
    if SameText(ParamStr(I), '--config') then
    begin
      Result := ParamStr(I + 1);
      Break;
    end;
  Result := ExpandFileName(Result);
end;

procedure TDFeBrokerService.Liberar;
begin
  FreeAndNil(FExecutor);
  FreeAndNil(FApp);
  FreeAndNil(FFabrica);
  FreeAndNil(FLog);
end;

procedure TDFeBrokerService.ServiceStart(Sender: TService; var Started: Boolean);
var
  LConfig: string;
  LRelatorio: TDFeRelatorioAmbiente;
begin
  Started := False;
  LConfig := CaminhoConfig;
  FLog := TDFeLogArquivo.Create(ExtractFilePath(LConfig) + 'logs');
  try
    FLog.Registrar('INFO', 'Servico iniciando. Config: ' + LConfig);
    if not FileExists(LConfig) then
      raise Exception.Create('Arquivo de configuracao nao encontrado: ' + LConfig);

    FFabrica := TDFeFabricaClientesACBr.Create(LConfig);
    LRelatorio := FFabrica.VerificarAmbiente;
    FLog.Registrar('INFO', 'Ambiente de execucao:' + sLineBreak + FormatarRelatorio(LRelatorio));
    if not AmbienteCompleto(LRelatorio) then
      raise Exception.Create('Ambiente de execucao incompleto: ' + MensagemAmbienteIncompleto(LRelatorio));

    FApp := TDFeAplicacao.Create(LConfig, FFabrica.CriarClient, FLog.Registrar);
    FApp.Iniciar;
    FExecutor := TDFeExecutorThread.Create(FApp, FLog);
    Started := True;
    FLog.Registrar('INFO', 'Servico em execucao.');
  except
    on E: Exception do
    begin
      // o operador olha o Event Log quando o servico "nao inicia"
      LogMessage('pascal-dfe-broker nao iniciou: ' + E.ClassName + ': ' + E.Message + ' (detalhes em ' +
        ExtractFilePath(LConfig) + 'logs)', EVENTLOG_ERROR_TYPE);
      FLog.Registrar('ERRO', 'Falha na subida: ' + E.ClassName + ': ' + E.Message);
      Liberar;
    end;
  end;
end;

procedure TDFeBrokerService.ServiceStop(Sender: TService; var Stopped: Boolean);
var
  LEsperado: Integer;
begin
  if FLog <> nil then
    FLog.Registrar('INFO', 'Servico parando.');

  if FApp <> nil then
    FApp.Parar;

  LEsperado := 0;
  while (FExecutor <> nil) and (not FExecutor.Finished) and (LEsperado < ESPERA_MAXIMA_PARADA_MS) do
  begin
    ReportStatus; // avisa o SCM que ainda esta parando
    Sleep(500);
    Inc(LEsperado, 500);
  end;

  if (FExecutor <> nil) and (not FExecutor.Finished) then
  begin
    // tick preso (SEFAZ lenta): nao da' para destruir a aplicacao por baixo da
    // thread; deixa o processo encerrar e o SO recolhe tudo.
    if FLog <> nil then
      FLog.Registrar('AVISO', 'O loop nao terminou em ' + IntToStr(ESPERA_MAXIMA_PARADA_MS div 1000) +
        ' s; encerrando o processo mesmo assim.');
    Stopped := True;
    Exit;
  end;

  if FLog <> nil then
    FLog.Registrar('INFO', 'Servico parado.');
  Liberar;
  Stopped := True;
end;

end.
