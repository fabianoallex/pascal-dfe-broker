unit DFe.Host.Aplicacao;

{$I dfe.inc}

{ A aplicacao inteira, montada a partir de UM arquivo de config: broker AMQP
  (embutido ou externo), publicador, filas do usuario, cursor, orquestrador,
  recarga a quente da config, manifestacao (automatica e manual) e o loop.

  Existe para os hosts (console, servico Windows -- decisao 9) serem finos de
  verdade: cada um so' decide como receber o pedido de parada (Ctrl+C, SIGTERM,
  Service Control Manager) e o que fazer com o log; nada de montagem duplicada.

  Deliberadamente NAO linka ACBr: a fabrica de clients (TDFeClientFactory) e' de
  quem hospeda. Assim a aplicacao inteira -- broker, publicador, filas,
  manifestacao manual, tick -- e' testada de ponta a ponta com o simulador da
  SEFAZ (tests/Integration/AmqpBroker), sem certificado nem DLL nenhuma.

  Cada tick (ver TDFeHostLoop) faz, nesta ordem:
    1. recarrega a config se o arquivo mudou (TDFeConfigWatcher);
    2. ExecutarCiclo do orquestrador (consulta a SEFAZ conforme o agendamento);
    3. drena os comandos de manifestacao manual pendentes.
  Tudo na MESMA thread: o client de uma unidade nao e' thread-safe (ver
  DFe.ComandoFonte.AMQP). Cada etapa e' isolada num try/except -- um erro numa
  nao impede as outras, e o processo nunca cai por causa de um tick.

  Caminhos relativos na config (CursorPath, DataDir) valem em relacao ao
  DIRETORIO DO ARQUIVO DE CONFIG, nao ao diretorio corrente: sob systemd ou como
  servico Windows o diretorio corrente e' imprevisivel.

  O provider NFe e' linkado por esta unit (uses DFe.Provider.NFe): o
  auto-registro por 'initialization' (decisao 10) so' acontece se a unit entra
  no programa. Um provider novo (CTe, MDFe) entra aqui, na lista de uses. }

interface

uses
  SysUtils, Classes,
  AMQP.Connection,
  AMQP.Server.Auth,
  AMQP.Server.Broker,
  DFe.Types,
  DFe.Errors,
  DFe.Provider,
  DFe.Provider.NFe,
  DFe.Publicador,
  DFe.Publicador.AMQP,
  DFe.ComandoFonte.AMQP,
  DFe.CursorStore.Arquivo,
  DFe.Orquestrador,
  DFe.Manifestacao,
  DFe.Host.Loop,
  DFe.Config;

type
  { ANivel: 'INFO', 'AVISO' ou 'ERRO'. Pode ser chamado de threads do pool do
    cliente AMQP (comando invalido), nao so' da thread do tick. }
  TDFeLogProc = procedure(const ANivel, AMensagem: string) of object;

  TDFeAplicacao = class
  private
    FCaminhoConfig: string;
    FClientFactory: TDFeClientFactory;
    FLog: TDFeLogProc;
    FConfig: TDFeConfig;
    FConfigBroker: TDFeConfigBroker;
    FBroker: TAMQPServer;
    FPublicador: IDFePublicador;
    FCursorStore: IDFeCursorStore;
    FOrquestrador: TDFeOrquestrador;
    FWatcher: TDFeConfigWatcher;
    FProcessador: TDFeManifestacaoProcessador;
    FAutoManifestador: TDFeAutoManifestador;
    FFonte: TDFeComandoFonteAMQP;
    FFonteIntf: IDFeComandoFonte;
    FLoop: TDFeHostLoop;
    FIniciada: Boolean;
    function ResolverCaminho(const ACaminho: string): string;
    function ParamsCliente: TAMQPConnectionParams;
    procedure IniciarBroker;
    procedure DeclararFilasDoUsuario;
    procedure AoComandoInvalido(const APayload, AMotivo: string);
    procedure Registrar(const ANivel, AMensagem: string);
    function GetPortaBroker: Integer;
  public
    constructor Create(const ACaminhoConfig: string;
      const AClientFactory: TDFeClientFactory; const ALog: TDFeLogProc = nil);
    destructor Destroy; override;

    { Carrega a config e sobe tudo. Levanta excecao (config invalida, provider
      nao registrado, porta ocupada, broker externo inalcancavel) -- falhar alto
      e cedo na subida, em vez de rodar pela metade. }
    procedure Iniciar;

    { Um tick, sem esperar. Exposto para os hosts que tem o proprio relogio
      (servico Windows) e para teste. }
    procedure ExecutarTick;

    { Loop bloqueante ate Parar. Uso do host console. }
    procedure Executar;

    { Seguro de handler de sinal/outra thread (so' seta um flag). }
    procedure Parar;

    { Porta efetiva do broker embutido (util com Porta=0); a configurada no modo externo. }
    property PortaBroker: Integer read GetPortaBroker;
    property Orquestrador: TDFeOrquestrador read FOrquestrador;
  end;

implementation

type
  { Os hooks de observabilidade do core (RegistrarAviso/RegistrarErro) ligados
    ao log da aplicacao. }
  TOrquestradorComLog = class(TDFeOrquestrador)
  private
    FApp: TDFeAplicacao;
  protected
    procedure RegistrarAviso(const AUnidade: TDFeUnidadeTrabalho; const AMensagem: string); override;
    procedure RegistrarErro(const AUnidade: TDFeUnidadeTrabalho; const AMensagem: string); override;
  end;

  TProcessadorComLog = class(TDFeManifestacaoProcessador)
  private
    FApp: TDFeAplicacao;
  protected
    procedure RegistrarErro(const AComando: TDFeComandoManifestacao; const AMensagem: string); override;
  end;

  { O tick do host: em vez de so' ExecutarCiclo, chama o da aplicacao. }
  TLoopDaAplicacao = class(TDFeHostLoop)
  private
    FApp: TDFeAplicacao;
  public
    procedure Tick; override;
  end;

{ TOrquestradorComLog / TProcessadorComLog / TLoopDaAplicacao }

procedure TOrquestradorComLog.RegistrarAviso(const AUnidade: TDFeUnidadeTrabalho; const AMensagem: string);
begin
  FApp.Registrar('AVISO', Format('[%s] %s', [AUnidade.Certificado.Identificador, AMensagem]));
end;

procedure TOrquestradorComLog.RegistrarErro(const AUnidade: TDFeUnidadeTrabalho; const AMensagem: string);
begin
  FApp.Registrar('ERRO', Format('[%s] %s', [AUnidade.Certificado.Identificador, AMensagem]));
end;

procedure TProcessadorComLog.RegistrarErro(const AComando: TDFeComandoManifestacao; const AMensagem: string);
begin
  FApp.Registrar('ERRO', Format('[manifestacao %s %s] %s', [AComando.Alias, AComando.TipoEvento, AMensagem]));
end;

procedure TLoopDaAplicacao.Tick;
begin
  FApp.ExecutarTick;
end;

{ TDFeAplicacao }

constructor TDFeAplicacao.Create(const ACaminhoConfig: string;
  const AClientFactory: TDFeClientFactory; const ALog: TDFeLogProc);
begin
  inherited Create;
  FCaminhoConfig := ExpandFileName(ACaminhoConfig);
  FClientFactory := AClientFactory;
  FLog := ALog;
end;

destructor TDFeAplicacao.Destroy;
begin
  // ordem inversa da montagem; cada etapa so' existe se Iniciar chegou nela
  if FFonte <> nil then
    FFonte.Parar;
  FFonteIntf := nil;
  FFonte := nil;
  FLoop.Free;
  FWatcher.Free;
  FAutoManifestador.Free;
  FProcessador.Free;
  FOrquestrador.Free;
  FPublicador := nil; // fecha a conexao do publicador antes do broker parar
  FCursorStore := nil;
  if FBroker <> nil then
  begin
    FBroker.Stop;
    FBroker.Free;
  end;
  inherited Destroy;
end;

procedure TDFeAplicacao.Registrar(const ANivel, AMensagem: string);
begin
  if Assigned(FLog) then
    FLog(ANivel, AMensagem);
end;

{ Absoluto: comeca com separador (Unix, UNC) ou tem letra de unidade (Windows). }
function CaminhoAbsoluto(const ACaminho: string): Boolean;
begin
  Result := (ACaminho <> '')
    and ((ACaminho[1] = '/') or (ACaminho[1] = PathDelim) or (ACaminho[1] = '\')
      or ((Length(ACaminho) > 1) and (ACaminho[2] = ':')));
end;

function TDFeAplicacao.ResolverCaminho(const ACaminho: string): string;
begin
  if ACaminho = '' then
    Exit('');
  if not CaminhoAbsoluto(ACaminho) then
    Result := IncludeTrailingPathDelimiter(ExtractFilePath(FCaminhoConfig)) + ACaminho
  else
    Result := ACaminho;
end;

function TDFeAplicacao.GetPortaBroker: Integer;
begin
  if FBroker <> nil then
    Result := FBroker.Port
  else
    Result := FConfigBroker.Porta;
end;

function TDFeAplicacao.ParamsCliente: TAMQPConnectionParams;
begin
  Result := TAMQPConnectionParams.Localhost;
  Result.User := FConfigBroker.Usuario;
  Result.Password := FConfigBroker.Senha;
  Result.VirtualHost := FConfigBroker.VirtualHost;
  Result.Port := Word(GetPortaBroker);
  if FConfigBroker.Modo = mbExterno then
    Result.Host := FConfigBroker.Host
  else if (FConfigBroker.BindAddress = '') or (FConfigBroker.BindAddress = '0.0.0.0') then
    Result.Host := '127.0.0.1' // escutando em todas as interfaces: o proprio processo usa o loopback
  else
    Result.Host := FConfigBroker.BindAddress;
end;

procedure TDFeAplicacao.IniciarBroker;
var
  LDataDir, LDurabilidade: string;
begin
  FBroker := TAMQPServer.Create;
  try
    FBroker.BindAddress := FConfigBroker.BindAddress;
    FBroker.Port := Word(FConfigBroker.Porta);
    FBroker.Authenticator := TAMQPStaticAuthenticator.Create([FConfigBroker.Usuario, FConfigBroker.Senha]);

    LDataDir := ResolverCaminho(FConfigBroker.DataDir);
    if LDataDir <> '' then
    begin
      ForceDirectories(LDataDir);
      FBroker.DataDir := LDataDir;
    end
    else
      Registrar('AVISO', 'Broker embutido TRANSIENTE (DataDir vazio): o que estiver em fila se perde ao reiniciar');

    FBroker.Start;
  except
    FreeAndNil(FBroker);
    raise;
  end;
  if LDataDir <> '' then
    LDurabilidade := 'duravel em ' + LDataDir
  else
    LDurabilidade := 'transiente';
  Registrar('INFO', Format('Broker embutido em %s:%d (%s)',
    [FConfigBroker.BindAddress, FBroker.Port, LDurabilidade]));
end;

procedure TDFeAplicacao.DeclararFilasDoUsuario;
var
  LConexao: TAMQPConnection;
  LCanal: TAMQPChannel;
  I: Integer;
begin
  // Conexao propria e curta: declarar topologia e' idempotente, e assim tanto o
  // publicador quanto a fonte de comando ja' encontram tudo pronto.
  LConexao := TAMQPConnection.Create(ParamsCliente);
  try
    LConexao.Open;
    LCanal := LConexao.CreateChannel;
    try
      DeclararExchangeDfe(LCanal);
      for I := 0 to High(FConfigBroker.Filas) do
      begin
        DeclararFilaLigada(LCanal, FConfigBroker.Filas[I].Nome, FConfigBroker.Filas[I].Padroes);
        Registrar('INFO', Format('Fila "%s" ligada a exchange "%s" (%d padrao(oes))',
          [FConfigBroker.Filas[I].Nome, DFE_EXCHANGE_NOME, Length(FConfigBroker.Filas[I].Padroes)]));
      end;
    finally
      LCanal.Free;
    end;
  finally
    LConexao.Free;
  end;
end;

procedure TDFeAplicacao.AoComandoInvalido(const APayload, AMotivo: string);
begin
  Registrar('ERRO', 'Comando de manifestacao descartado: ' + AMotivo);
end;

procedure TDFeAplicacao.Iniciar;
var
  LOrquestrador: TOrquestradorComLog;
  LProcessador: TProcessadorComLog;
  LLoop: TLoopDaAplicacao;
begin
  if FIniciada then
    Exit;

  FConfig := CarregarConfig(FCaminhoConfig);
  FConfigBroker := CarregarConfigBroker(FCaminhoConfig);

  if FConfigBroker.Modo = mbEmbutido then
    IniciarBroker
  else
    Registrar('INFO', Format('Broker externo em %s:%d', [FConfigBroker.Host, FConfigBroker.Porta]));

  DeclararFilasDoUsuario;
  FPublicador := TDFePublicadorAMQP.Create(ParamsCliente);
  FCursorStore := TDFeCursorStoreArquivo.Create(ResolverCaminho(FConfig.CursorPath));

  LOrquestrador := TOrquestradorComLog.Create(FPublicador);
  LOrquestrador.FApp := Self;
  FOrquestrador := LOrquestrador;

  // Ja' faz a carga inicial: alias novo cria a unidade via a fabrica do host.
  FWatcher := TDFeConfigWatcher.Create(FCaminhoConfig, FOrquestrador, FCursorStore, FClientFactory);
  Registrar('INFO', Format('%d certificado(s) na config', [Length(FConfig.Certificados)]));

  LProcessador := TProcessadorComLog.Create(FOrquestrador, FPublicador);
  LProcessador.FApp := Self;
  FProcessador := LProcessador;
  FAutoManifestador := TDFeAutoManifestador.Create(FProcessador);
  FOrquestrador.AoPublicarDocumento := FAutoManifestador.AoPublicarDocumento;

  FFonte := TDFeComandoFonteAMQP.Create(ParamsCliente);
  FFonteIntf := FFonte;
  FFonte.AoComandoInvalido := AoComandoInvalido;
  FFonte.Iniciar;

  LLoop := TLoopDaAplicacao.Create(FOrquestrador, FConfig.TickSegundos);
  LLoop.FApp := Self;
  FLoop := LLoop;

  FIniciada := True;
end;

procedure TDFeAplicacao.ExecutarTick;
begin
  // 1. config recarregada a quente. Uma edicao com erro NAO derruba nada: a
  //    config anterior segue valendo, e o erro aparece no log.
  try
    FWatcher.VerificarRecarregar;
  except
    on E: Exception do
      Registrar('ERRO', 'Config nao recarregada (a anterior segue valendo): ' + E.Message);
  end;

  // 2. consultas. ExecutarCiclo ja' isola cada unidade; este try e' so' o cinto.
  try
    FOrquestrador.ExecutarCiclo;
  except
    on E: Exception do
      Registrar('ERRO', 'Falha no ciclo: ' + E.ClassName + ': ' + E.Message);
  end;

  // 3. manifestacao manual
  try
    FProcessador.ProcessarTodos(FFonteIntf);
  except
    on E: Exception do
      Registrar('ERRO', 'Falha ao processar comandos de manifestacao: ' + E.ClassName + ': ' + E.Message);
  end;
end;

procedure TDFeAplicacao.Executar;
begin
  if not FIniciada then
    raise EDFeError.Create('TDFeAplicacao.Executar chamado antes de Iniciar');
  FLoop.Executar;
end;

procedure TDFeAplicacao.Parar;
begin
  if FLoop <> nil then
    FLoop.Parar;
end;

end.
