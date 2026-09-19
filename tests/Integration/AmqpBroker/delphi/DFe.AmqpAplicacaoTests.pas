unit DFe.AmqpAplicacaoTests;

{ Espelho DUnitX de ..\DFe.AmqpAplicacaoTests.pas (FPCUnit) -- mantenha os dois
  em sincronia (mesmos nomes de teste, mesmas asserções).

  TDFeAplicacao (a montagem inteira dos hosts) de ponta a ponta, sem ACBr: o
  client e' o do simulador da SEFAZ, o broker e' o EMBUTIDO de verdade (porta
  efemera, WAL em pasta temporaria), o provider NFe, o cursor em arquivo e as
  filas do usuario (secoes [fila:*]) sao os reais. }

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  AMQP.Wire,
  AMQP.Basic.Methods,
  AMQP.Connection,
  DFe.Types,
  DFe.Provider,
  DFe.Config,
  DFe.Simulador,
  DFe.Simulador.Client,
  DFe.Simulador.Fixtures,
  DFe.Host.Aplicacao;

type
  [TestFixture]
  TDFeAmqpAplicacaoTests = class
  private
    FPasta: string;
    FCaminhoConfig: string;
    FSim: TDFeSimuladorSefaz;
    FApp: TDFeAplicacao;
    FLogs: TStringList;
    FConexao: TAMQPConnection;
    FCanal: TAMQPChannel;
    function FabricarClient(const ACertificado: TDFeConfigCertificado): IDFeDistribuicaoClient;
    procedure AoLog(const ANivel, AMensagem: string);
    procedure EscreverConfig(const ADataDir: string);
    function NovaApp: TDFeAplicacao;
    procedure AbrirClienteNoBrokerDaApp;
    function ContarMensagens(const AFila: string): Integer;
    procedure PublicarNFes(const AQuantidade: Integer);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure Tick_PublicaNasFilasDeclaradasSoPelaConfig;
    [Test] procedure Tick_CursorGravadoEmRelacaoAPastaDaConfig;
    [Test] procedure SegundoTickAntesDe1h_NaoConsultaDeNovo;
    [Test] procedure Reinicio_PreservaAMensagemEmFila_ENaoReconsultaDocumentosJaEntregues;
    [Test] procedure ConfigInvalida_IniciarLevanta_ENaoVaza;
  end;

implementation

const
  CNPJ = '12345678000199';

procedure TDFeAmqpAplicacaoTests.Setup;
begin
  FPasta := IncludeTrailingPathDelimiter(TPath.GetTempPath) + 'dfe_app_' +
    TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '') + PathDelim;
  ForceDirectories(FPasta);
  FCaminhoConfig := FPasta + 'dfe.ini';
  FSim := TDFeSimuladorSefaz.Create;
  FLogs := TStringList.Create;
  FApp := nil;
  FConexao := nil;
  FCanal := nil;
end;

procedure TDFeAmqpAplicacaoTests.TearDown;
begin
  FreeAndNil(FCanal);
  FreeAndNil(FConexao);
  FreeAndNil(FApp);
  FLogs.Free;
  FSim.Free;
  if TDirectory.Exists(FPasta) then
    TDirectory.Delete(FPasta, True);
end;

function TDFeAmqpAplicacaoTests.FabricarClient(const ACertificado: TDFeConfigCertificado): IDFeDistribuicaoClient;
begin
  Result := TDFeSimuladorClient.Create(FSim);
end;

procedure TDFeAmqpAplicacaoTests.AoLog(const ANivel, AMensagem: string);
begin
  FLogs.Add(ANivel + ' ' + AMensagem);
end;

procedure TDFeAmqpAplicacaoTests.EscreverConfig(const ADataDir: string);
var
  LIni: TStringList;
begin
  LIni := TStringList.Create;
  try
    LIni.Add('[dfe]');
    LIni.Add('CursorPath=cursores.dat');
    LIni.Add('[broker]');
    LIni.Add('Porta=0');
    LIni.Add('DataDir=' + ADataDir);
    LIni.Add('[fila:docs]');
    LIni.Add('RoutingKey=nfe.documento.#');
    LIni.Add('[fila:eventos]');
    LIni.Add('RoutingKey=nfe.evento.#');
    LIni.Add('[certificado:matriz]');
    LIni.Add('Provider=nfe');
    LIni.Add('CnpjCpf=' + CNPJ);
    LIni.Add('UF=RS');
    LIni.SaveToFile(FCaminhoConfig);
  finally
    LIni.Free;
  end;
end;

function TDFeAmqpAplicacaoTests.NovaApp: TDFeAplicacao;
begin
  Result := TDFeAplicacao.Create(FCaminhoConfig, FabricarClient, AoLog);
end;

procedure TDFeAmqpAplicacaoTests.AbrirClienteNoBrokerDaApp;
var
  LParams: TAMQPConnectionParams;
begin
  LParams := TAMQPConnectionParams.Localhost;
  LParams.Host := '127.0.0.1';
  LParams.Port := Word(FApp.PortaBroker);
  FConexao := TAMQPConnection.Create(LParams);
  FConexao.Open;
  FCanal := FConexao.CreateChannel;
end;

function TDFeAmqpAplicacaoTests.ContarMensagens(const AFila: string): Integer;
var
  LMsg: TAMQPGetResult;
begin
  Result := 0;
  repeat
    LMsg := FCanal.BasicGet(AFila, True);
    if LMsg.Found then
      Inc(Result);
  until not LMsg.Found;
end;

procedure TDFeAmqpAplicacaoTests.PublicarNFes(const AQuantidade: Integer);
var
  I: Integer;
begin
  for I := 1 to AQuantidade do
    FSim.PublicarDocumento(CNPJ, 'RS', DFE_SIM_SCHEMA_RESNFE,
      XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, I)));
end;

procedure TDFeAmqpAplicacaoTests.Tick_PublicaNasFilasDeclaradasSoPelaConfig;
var
  LMsg: TAMQPGetResult;
begin
  EscreverConfig('');
  PublicarNFes(2);
  FSim.PublicarDocumento(CNPJ, 'RS', DFE_SIM_SCHEMA_RESEVENTO,
    XmlResEvento(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1), '110111'));

  FApp := NovaApp;
  FApp.Iniciar;
  AbrirClienteNoBrokerDaApp;
  FApp.ExecutarTick;

  LMsg := FCanal.BasicGet('eventos', True);
  Assert.IsTrue(LMsg.Found, 'evento na fila de eventos');
  Assert.AreEqual('nfe.evento.cancelamento.rs.' + CNPJ, LMsg.RoutingKey);
  Assert.AreEqual(0, ContarMensagens('eventos'), 'so um evento');
  Assert.AreEqual(2, ContarMensagens('docs'), 'dois documentos na fila de documentos');
end;

procedure TDFeAmqpAplicacaoTests.Tick_CursorGravadoEmRelacaoAPastaDaConfig;
begin
  EscreverConfig('');
  PublicarNFes(3);

  FApp := NovaApp;
  FApp.Iniciar;
  FApp.ExecutarTick;

  // 'cursores.dat' relativo => ao lado do dfe.ini, nao no diretorio corrente
  Assert.IsTrue(FileExists(FPasta + 'cursores.dat'), 'cursor ao lado da config');
end;

procedure TDFeAmqpAplicacaoTests.SegundoTickAntesDe1h_NaoConsultaDeNovo;
begin
  EscreverConfig('');
  PublicarNFes(1);

  FApp := NovaApp;
  FApp.Iniciar;
  AbrirClienteNoBrokerDaApp;
  FApp.ExecutarTick;
  Assert.AreEqual(1, ContarMensagens('docs'));

  // chegou documento novo, mas a janela de 1h da SEFAZ ainda nao abriu
  PublicarNFes(2);
  FApp.ExecutarTick;
  Assert.AreEqual(0, ContarMensagens('docs'), 'nao consultou antes de 1h');
end;

procedure TDFeAmqpAplicacaoTests.Reinicio_PreservaAMensagemEmFila_ENaoReconsultaDocumentosJaEntregues;
begin
  EscreverConfig('broker'); // duravel, em <pasta da config>\broker
  PublicarNFes(2);

  FApp := NovaApp;
  FApp.Iniciar;
  FApp.ExecutarTick;
  FreeAndNil(FApp); // "reinicia": derruba broker, publicador, tudo

  Assert.IsTrue(TDirectory.Exists(FPasta + 'broker'), 'WAL criado ao lado da config');

  FApp := NovaApp;
  FApp.Iniciar;
  FApp.ExecutarTick; // orquestrador novo consulta de novo -- mas o cursor persistiu
  AbrirClienteNoBrokerDaApp;

  Assert.AreEqual(2, ContarMensagens('docs'),
    'as 2 mensagens sobreviveram ao restart, sem duplicar');
end;

procedure TDFeAmqpAplicacaoTests.ConfigInvalida_IniciarLevanta_ENaoVaza;
var
  LIni: TStringList;
begin
  LIni := TStringList.Create;
  try
    LIni.Add('[broker]');
    LIni.Add('Modo=nuvem');
    LIni.SaveToFile(FCaminhoConfig);
  finally
    LIni.Free;
  end;

  Assert.WillRaise(
    procedure
    begin
      FApp := NovaApp;
      FApp.Iniciar;
    end,
    Exception);
  // o destrutor de uma app que nao chegou a subir nao pode levantar nem vazar
  // (o TearDown libera FApp; ReportMemoryLeaksOnShutdown acusa qualquer vazamento)
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeAmqpAplicacaoTests);

end.
