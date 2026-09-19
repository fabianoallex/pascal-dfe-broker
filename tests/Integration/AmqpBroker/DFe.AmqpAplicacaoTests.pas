unit DFe.AmqpAplicacaoTests;

{ TDFeAplicacao (a montagem inteira dos hosts) de ponta a ponta, sem ACBr: o
  client e' o do simulador da SEFAZ, o broker e' o EMBUTIDO de verdade (porta
  efemera, WAL em pasta temporaria), o provider NFe, o cursor em arquivo e as
  filas do usuario (secoes [fila:*]) sao os reais.

  O que estes testes provam e nenhum outro prova: que um documento que a SEFAZ
  (simulada) entrega chega, pelo broker, a uma fila declarada so' pela config;
  que o cursor e o broker sao resolvidos em relacao a pasta da config; e que o
  que estava em fila sobrevive a um restart da aplicacao (o motivo de o
  DataDir ser duravel por padrao). }

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils, Classes,
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
  TDFeAmqpAplicacaoTests = class(TTestCase)
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
    procedure EscreverConfig(const ADataDir: string; const AAmbiente: string = '');
    procedure DoIniciarComModoInvalido;
    function NovaApp: TDFeAplicacao;
    procedure AbrirClienteNoBrokerDaApp;
    function ContarMensagens(const AFila: string): Integer;
    procedure PublicarNFes(const AQuantidade: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Tick_PublicaNasFilasDeclaradasSoPelaConfig;
    procedure Tick_CursorGravadoEmRelacaoAPastaDaConfig;
    procedure Ambiente_Homologacao_GravaOCursorNoNamespaceDeHomologacao;
    procedure SegundoTickAntesDe1h_NaoConsultaDeNovo;
    procedure Reinicio_PreservaAMensagemEmFila_ENaoReconsultaDocumentosJaEntregues;
    procedure ConfigInvalida_IniciarLevanta_ENaoVaza;
  end;

implementation

const
  CNPJ = '12345678000199';

procedure ApagarPasta(const APasta: string);
var
  LBusca: TSearchRec;
begin
  if not DirectoryExists(APasta) then
    Exit;
  if FindFirst(IncludeTrailingPathDelimiter(APasta) + '*', faAnyFile, LBusca) = 0 then
  try
    repeat
      if (LBusca.Name = '.') or (LBusca.Name = '..') then
        Continue;
      if (LBusca.Attr and faDirectory) <> 0 then
        ApagarPasta(IncludeTrailingPathDelimiter(APasta) + LBusca.Name)
      else
        DeleteFile(IncludeTrailingPathDelimiter(APasta) + LBusca.Name);
    until FindNext(LBusca) <> 0;
  finally
    FindClose(LBusca);
  end;
  RemoveDir(APasta);
end;

procedure TDFeAmqpAplicacaoTests.SetUp;
begin
  FPasta := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'dfe_app_' + IntToStr(GetTickCount64) + PathDelim;
  ForceDirectories(FPasta);
  FCaminhoConfig := FPasta + 'dfe.ini';
  FSim := TDFeSimuladorSefaz.Create;
  FLogs := TStringList.Create;
end;

procedure TDFeAmqpAplicacaoTests.TearDown;
begin
  FreeAndNil(FCanal);
  FreeAndNil(FConexao);
  FreeAndNil(FApp);
  FLogs.Free;
  FSim.Free;
  ApagarPasta(FPasta);
end;

function TDFeAmqpAplicacaoTests.FabricarClient(const ACertificado: TDFeConfigCertificado): IDFeDistribuicaoClient;
begin
  Result := TDFeSimuladorClient.Create(FSim);
end;

procedure TDFeAmqpAplicacaoTests.AoLog(const ANivel, AMensagem: string);
begin
  FLogs.Add(ANivel + ' ' + AMensagem);
end;

procedure TDFeAmqpAplicacaoTests.EscreverConfig(const ADataDir: string; const AAmbiente: string);
var
  LIni: TStringList;
begin
  LIni := TStringList.Create;
  try
    LIni.Add('[dfe]');
    LIni.Add('CursorPath=cursores.dat');
    if AAmbiente <> '' then
      LIni.Add('Ambiente=' + AAmbiente);
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
  AssertTrue('evento na fila de eventos', LMsg.Found);
  AssertEquals('nfe.evento.cancelamento.rs.' + CNPJ, LMsg.RoutingKey);
  AssertEquals('so um evento', 0, ContarMensagens('eventos'));
  AssertEquals('dois documentos na fila de documentos', 2, ContarMensagens('docs'));
end;

procedure TDFeAmqpAplicacaoTests.Tick_CursorGravadoEmRelacaoAPastaDaConfig;
begin
  EscreverConfig('');
  PublicarNFes(3);

  FApp := NovaApp;
  FApp.Iniciar;
  FApp.ExecutarTick;

  // 'cursores.dat' relativo => ao lado do dfe.ini, nao no diretorio corrente
  AssertTrue('cursor ao lado da config', FileExists(FPasta + 'cursores.dat'));
end;

procedure TDFeAmqpAplicacaoTests.Ambiente_Homologacao_GravaOCursorNoNamespaceDeHomologacao;
var
  LCursor: TStringList;
begin
  EscreverConfig('', 'homologacao');
  PublicarNFes(2);

  FApp := NovaApp;
  FApp.Iniciar;
  FApp.ExecutarTick;

  LCursor := TStringList.Create;
  try
    LCursor.LoadFromFile(FPasta + 'cursores.dat');
    AssertTrue('cursor de homologacao gravado', LCursor.Values['nfe/' + CNPJ + '/rs/homologacao'] <> '');
    AssertEquals('producao intocada', '', LCursor.Values['nfe/' + CNPJ + '/rs']);
  finally
    LCursor.Free;
  end;
end;

procedure TDFeAmqpAplicacaoTests.SegundoTickAntesDe1h_NaoConsultaDeNovo;
begin
  EscreverConfig('');
  PublicarNFes(1);

  FApp := NovaApp;
  FApp.Iniciar;
  AbrirClienteNoBrokerDaApp;
  FApp.ExecutarTick;
  AssertEquals(1, ContarMensagens('docs'));

  // chegou documento novo, mas a janela de 1h da SEFAZ ainda nao abriu
  PublicarNFes(2);
  FApp.ExecutarTick;
  AssertEquals('nao consultou antes de 1h', 0, ContarMensagens('docs'));
end;

procedure TDFeAmqpAplicacaoTests.Reinicio_PreservaAMensagemEmFila_ENaoReconsultaDocumentosJaEntregues;
begin
  EscreverConfig('broker'); // duravel, em <pasta da config>\broker
  PublicarNFes(2);

  FApp := NovaApp;
  FApp.Iniciar;
  FApp.ExecutarTick;
  FreeAndNil(FApp); // "reinicia": derruba broker, publicador, tudo

  AssertTrue('WAL criado ao lado da config', DirectoryExists(FPasta + 'broker'));

  FApp := NovaApp;
  FApp.Iniciar;
  FApp.ExecutarTick; // orquestrador novo consulta de novo -- mas o cursor persistiu
  AbrirClienteNoBrokerDaApp;

  AssertEquals('as 2 mensagens sobreviveram ao restart, sem duplicar',
    2, ContarMensagens('docs'));
end;

procedure TDFeAmqpAplicacaoTests.DoIniciarComModoInvalido;
begin
  FApp := NovaApp;
  FApp.Iniciar;
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
  AssertException(Exception, DoIniciarComModoInvalido);
  // o destrutor de uma app que nao chegou a subir nao pode levantar nem vazar
  // (o TearDown libera FApp; o heaptrc do runner acusa qualquer vazamento)
end;

initialization
  RegisterTest(TDFeAmqpAplicacaoTests);

end.
