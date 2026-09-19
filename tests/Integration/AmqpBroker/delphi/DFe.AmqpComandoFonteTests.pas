unit DFe.AmqpComandoFonteTests;

{ Espelho DUnitX de ..\DFe.AmqpComandoFonteTests.pas (FPCUnit) -- mantenha os dois
  em sincronia (mesmos nomes de teste, mesmas asserções).

  TDFeComandoFonteAMQP (o IDFeComandoFonte real) contra o broker AMQP EMBUTIDO.
  O ultimo teste fecha o circuito da manifestacao manual inteira: comando na
  exchange -> fonte -> TDFeManifestacaoProcessador -> client (fake) -> resultado
  publicado por TDFePublicadorAMQP -> fila de quem assina a routing-key. }

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  AMQP.Wire,
  AMQP.Basic.Methods,
  AMQP.Queue.Methods,
  AMQP.Connection,
  AMQP.Server.Broker,
  DFe.Types,
  DFe.Publicador,
  DFe.Publicador.AMQP,
  DFe.ComandoFonte.AMQP,
  DFe.Manifestacao,
  DFe.Orquestrador,
  DFe.TestDoubles;

type
  [TestFixture]
  TDFeAmqpComandoFonteTests = class
  private
    FBroker: TAMQPServer;
    FConexao: TAMQPConnection;
    FCanal: TAMQPChannel;
    FInvalidos: Integer;
    FUltimoMotivo: string;
    function Params: TAMQPConnectionParams;
    procedure EnviarComando(const ACorpo: string);
    function EsperarComando(const AFonte: IDFeComandoFonte;
      out AComando: TDFeComandoManifestacao): Boolean;
    procedure AoInvalido(const APayload, AMotivo: string);
    function Corpo(const ATipo, AJustificativa: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure ComandoValido_ChegaInterpretado;
    [Test] procedure ComandoComAcento_ChegaIntegro;
    [Test] procedure DoisComandos_SaemNaOrdem;
    [Test] procedure SemComando_NaoBloqueiaEDevolveFalso;
    [Test] procedure ComandoInvalido_EDescartadoEAvisado;
    [Test] procedure ManifestacaoManual_PontaAPonta_ResultadoSaiNaExchange;
  end;

implementation

const
  CHAVE = '35260112345678000199550010000000011000000010';
  // Delphi: caracteres de verdade (no FPC, os bytes UTF-8).
  JUSTIFICATIVA_ACENTUADA = 'Opera' + #$00E7 + #$00E3 + 'o n' + #$00E3 +
    'o realizada pelo destinat' + #$00E1 + 'rio';

procedure TDFeAmqpComandoFonteTests.Setup;
begin
  FInvalidos := 0;
  FUltimoMotivo := '';
  FBroker := TAMQPServer.Create;
  FBroker.BindAddress := '127.0.0.1';
  FBroker.Port := 0;
  FBroker.Start;

  FConexao := TAMQPConnection.Create(Params);
  FConexao.Open;
  FCanal := FConexao.CreateChannel;
  DeclararExchangeDfe(FCanal);
end;

procedure TDFeAmqpComandoFonteTests.TearDown;
begin
  FreeAndNil(FCanal);
  FreeAndNil(FConexao);
  FBroker.Stop;
  FreeAndNil(FBroker);
end;

function TDFeAmqpComandoFonteTests.Params: TAMQPConnectionParams;
begin
  Result := TAMQPConnectionParams.Localhost;
  Result.Host := '127.0.0.1';
  Result.Port := FBroker.Port;
end;

procedure TDFeAmqpComandoFonteTests.AoInvalido(const APayload, AMotivo: string);
begin
  Inc(FInvalidos);
  FUltimoMotivo := AMotivo;
end;

function TDFeAmqpComandoFonteTests.Corpo(const ATipo, AJustificativa: string): string;
begin
  Result := 'Alias=teste' + sLineBreak + 'ChaveAcesso=' + CHAVE + sLineBreak +
    'TipoEvento=' + ATipo;
  if AJustificativa <> '' then
    Result := Result + sLineBreak + 'Justificativa=' + AJustificativa;
end;

procedure TDFeAmqpComandoFonteTests.EnviarComando(const ACorpo: string);
begin
  FCanal.PublishText(DFE_EXCHANGE_NOME, DFE_COMANDO_ROUTING_KEY_MANIFESTACAO, ACorpo);
end;

function TDFeAmqpComandoFonteTests.EsperarComando(const AFonte: IDFeComandoFonte;
  out AComando: TDFeComandoManifestacao): Boolean;
var
  I: Integer;
begin
  for I := 1 to 100 do
  begin
    if AFonte.ObterProximoComando(AComando) then
      Exit(True);
    Sleep(20);
  end;
  Result := False;
end;

procedure TDFeAmqpComandoFonteTests.ComandoValido_ChegaInterpretado;
var
  LFonte: TDFeComandoFonteAMQP;
  LIntf: IDFeComandoFonte;
  LComando: TDFeComandoManifestacao;
begin
  LFonte := TDFeComandoFonteAMQP.Create(Params);
  LIntf := LFonte;
  LFonte.Iniciar;

  EnviarComando(Corpo('Ciencia', ''));

  Assert.IsTrue(EsperarComando(LIntf, LComando), 'comando chegou');
  Assert.AreEqual('teste', LComando.Alias);
  Assert.AreEqual(CHAVE, LComando.ChaveAcesso);
  Assert.AreEqual('ciencia', LComando.TipoEvento, 'TipoEvento normalizado');
end;

procedure TDFeAmqpComandoFonteTests.ComandoComAcento_ChegaIntegro;
var
  LFonte: TDFeComandoFonteAMQP;
  LIntf: IDFeComandoFonte;
  LComando: TDFeComandoManifestacao;
begin
  LFonte := TDFeComandoFonteAMQP.Create(Params);
  LIntf := LFonte;
  LFonte.Iniciar;

  EnviarComando(Corpo('operacaonaorealizada', JUSTIFICATIVA_ACENTUADA));

  Assert.IsTrue(EsperarComando(LIntf, LComando), 'comando chegou');
  Assert.AreEqual(JUSTIFICATIVA_ACENTUADA, LComando.Justificativa);
end;

procedure TDFeAmqpComandoFonteTests.DoisComandos_SaemNaOrdem;
var
  LFonte: TDFeComandoFonteAMQP;
  LIntf: IDFeComandoFonte;
  LComando: TDFeComandoManifestacao;
begin
  LFonte := TDFeComandoFonteAMQP.Create(Params);
  LIntf := LFonte;
  LFonte.Iniciar;

  EnviarComando(Corpo('ciencia', ''));
  EnviarComando(Corpo('confirmacao', ''));

  Assert.IsTrue(EsperarComando(LIntf, LComando), 'primeiro chegou');
  Assert.AreEqual('ciencia', LComando.TipoEvento);
  Assert.IsTrue(EsperarComando(LIntf, LComando), 'segundo chegou');
  Assert.AreEqual('confirmacao', LComando.TipoEvento);
end;

procedure TDFeAmqpComandoFonteTests.SemComando_NaoBloqueiaEDevolveFalso;
var
  LFonte: TDFeComandoFonteAMQP;
  LIntf: IDFeComandoFonte;
  LComando: TDFeComandoManifestacao;
begin
  LFonte := TDFeComandoFonteAMQP.Create(Params);
  LIntf := LFonte;
  LFonte.Iniciar;

  Assert.IsFalse(LIntf.ObterProximoComando(LComando));
end;

procedure TDFeAmqpComandoFonteTests.ComandoInvalido_EDescartadoEAvisado;
var
  LFonte: TDFeComandoFonteAMQP;
  LIntf: IDFeComandoFonte;
  LComando: TDFeComandoManifestacao;
  I: Integer;
begin
  LFonte := TDFeComandoFonteAMQP.Create(Params);
  LIntf := LFonte;
  LFonte.AoComandoInvalido := AoInvalido;
  LFonte.Iniciar;

  // chave com 3 digitos: InterpretarComando recusa
  EnviarComando('Alias=teste' + sLineBreak + 'ChaveAcesso=123' + sLineBreak + 'TipoEvento=ciencia');

  for I := 1 to 100 do
  begin
    if FInvalidos > 0 then
      Break;
    Sleep(20);
  end;
  Assert.AreEqual(1, FInvalidos, 'avisou uma vez');
  Assert.IsTrue(Pos('ChaveAcesso', FUltimoMotivo) > 0, 'motivo cita a chave: ' + FUltimoMotivo);
  Assert.IsFalse(LIntf.ObterProximoComando(LComando), 'nao entrou na fila de pendentes');
  // descartado, nao reenfileirado: nada sobra na fila do broker
  Sleep(100);
  Assert.IsFalse(FCanal.BasicGet(DFE_COMANDO_FILA_NOME, True).Found, 'sem requeue');
end;

procedure TDFeAmqpComandoFonteTests.ManifestacaoManual_PontaAPonta_ResultadoSaiNaExchange;
var
  LFonte: TDFeComandoFonteAMQP;
  LIntfFonte: IDFeComandoFonte;
  LPublicador: IDFePublicador;
  LOrquestrador: TDFeOrquestrador;
  LProcessador: TDFeManifestacaoProcessador;
  LClient: TDFeClientManifestadorFake;
  LEvento: TDFeEventoNormalizado;
  LMsg: TAMQPGetResult;
  LBind: TAMQPQueueBind;
  I: Integer;
begin
  // quem assina o resultado da ciencia
  FCanal.DeclareQueue(TAMQPQueueDeclare.Create('t.resultado', False));
  LBind := Default(TAMQPQueueBind);
  LBind.QueueName := 't.resultado';
  LBind.ExchangeName := DFE_EXCHANGE_NOME;
  LBind.RoutingKey := 'nfe.evento.ciencia.#';
  FCanal.BindQueue(LBind);

  LPublicador := TDFePublicadorAMQP.Create(Params);
  LOrquestrador := TDFeOrquestrador.Create(LPublicador);
  try
    LEvento := EventoTeste;
    LEvento.Categoria := dcEvento;
    LEvento.TipoEvento := 'ciencia';
    LEvento.ChaveAcesso := CHAVE;
    LEvento.XmlPayload := '<procEventoNFe/>';

    LClient := TDFeClientManifestadorFake.Create;
    LClient.EventoADevolver := LEvento;
    LOrquestrador.AdicionarUnidade(
      TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), LClient, CertificadoTeste, TDFeCursorStoreFake.Create));

    LProcessador := TDFeManifestacaoProcessador.Create(LOrquestrador, LPublicador);
    try
      LFonte := TDFeComandoFonteAMQP.Create(Params);
      LIntfFonte := LFonte;
      LFonte.Iniciar;

      EnviarComando(Corpo('ciencia', ''));

      // o host faria isto no tick; aqui esperamos o comando chegar e drenamos
      for I := 1 to 100 do
      begin
        LProcessador.ProcessarTodos(LIntfFonte);
        if LClient.ChamadasEnviarEvento > 0 then
          Break;
        Sleep(20);
      end;
      Assert.AreEqual(1, LClient.ChamadasEnviarEvento, 'client recebeu o comando');
      Assert.AreEqual(CHAVE, LClient.UltimoComandoRecebido.ChaveAcesso);

      LMsg.Found := False;
      for I := 1 to 50 do
      begin
        LMsg := FCanal.BasicGet('t.resultado', True);
        if LMsg.Found then
          Break;
        Sleep(20);
      end;
      Assert.IsTrue(LMsg.Found, 'resultado chegou a quem assina');
      Assert.AreEqual('nfe.evento.ciencia.rs.12345678000199', LMsg.RoutingKey);
      Assert.AreEqual('<procEventoNFe/>', AmqpUtf8Decode(LMsg.Body));
    finally
      LProcessador.Free;
    end;
  finally
    LOrquestrador.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeAmqpComandoFonteTests);

end.
