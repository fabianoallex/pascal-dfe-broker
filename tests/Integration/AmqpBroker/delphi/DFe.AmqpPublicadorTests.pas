unit DFe.AmqpPublicadorTests;

{ Espelho DUnitX de ..\DFe.AmqpPublicadorTests.pas (FPCUnit) -- mantenha os dois
  em sincronia (mesmos nomes de teste, mesmas asserções).

  TDFePublicadorAMQP (o IDFePublicador real) contra o broker AMQP EMBUTIDO do
  pascal-amqp-faa, in-process. Prova que a mensagem chega de verdade a uma fila
  ligada a exchange 'dfe', com o XML em UTF-8 integro (acentos) na routing-key
  certa, e que a falha do broker vira EDFePublicacaoFalhou. }

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  AMQP.Wire,
  AMQP.Basic.Methods,
  AMQP.Queue.Methods,
  AMQP.Connection,
  AMQP.Server.Broker,
  DFe.Errors,
  DFe.Publicador,
  DFe.Publicador.AMQP;

type
  [TestFixture]
  TDFeAmqpPublicadorTests = class
  private
    FBroker: TAMQPServer;
    FConexao: TAMQPConnection;
    FCanal: TAMQPChannel;
    function Params: TAMQPConnectionParams;
    procedure IniciarBroker(const APorta: Word);
    procedure PararBroker;
    procedure LigarFila(const AFila, APadrao: string);
    procedure AbrirCliente;
    function NovoPublicador: IDFePublicador;
    function EsperarMensagem(const AFila: string; out AResultado: TAMQPGetResult): Boolean;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure Publicar_ChegaNaFilaLigada_ComAcentoIntegro;
    [Test] procedure Publicar_UsaContentTypeXmlEPersistente;
    [Test] procedure Publicar_TopicFiltraPelaRoutingKey;
    [Test] procedure Publicar_SemFilaLigada_NaoEErro;
    [Test] procedure Publicar_BrokerForaDoAr_LevantaPublicacaoFalhou;
    [Test] procedure Publicar_DepoisQueOBrokerReinicia_Reconecta;
  end;

implementation

const
  // Delphi: a String e' Unicode -- o caractere de verdade (no FPC sao os bytes UTF-8).
  XML_COM_ACENTO =
    '<?xml version="1.0" encoding="UTF-8"?><resNFe><xNome>JOS' + #$00C9 +
    ' A' + #$00C7 + 'OUGUE LTDA</resNFe>';

procedure TDFeAmqpPublicadorTests.Setup;
begin
  FBroker := nil;
  FConexao := nil;
  FCanal := nil;
  IniciarBroker(0);
end;

procedure TDFeAmqpPublicadorTests.TearDown;
begin
  FreeAndNil(FCanal);
  FreeAndNil(FConexao);
  PararBroker;
end;

procedure TDFeAmqpPublicadorTests.IniciarBroker(const APorta: Word);
begin
  FBroker := TAMQPServer.Create;
  FBroker.BindAddress := '127.0.0.1';
  FBroker.Port := APorta;
  FBroker.Start;
end;

procedure TDFeAmqpPublicadorTests.PararBroker;
begin
  if FBroker <> nil then
  begin
    FBroker.Stop;
    FreeAndNil(FBroker);
  end;
end;

function TDFeAmqpPublicadorTests.Params: TAMQPConnectionParams;
begin
  Result := TAMQPConnectionParams.Localhost;
  Result.Host := '127.0.0.1';
  Result.Port := FBroker.Port;
end;

procedure TDFeAmqpPublicadorTests.AbrirCliente;
begin
  FConexao := TAMQPConnection.Create(Params);
  FConexao.Open;
  FCanal := FConexao.CreateChannel;
  DeclararExchangeDfe(FCanal);
end;

procedure TDFeAmqpPublicadorTests.LigarFila(const AFila, APadrao: string);
var
  LBind: TAMQPQueueBind;
begin
  FCanal.DeclareQueue(TAMQPQueueDeclare.Create(AFila, False));
  LBind := Default(TAMQPQueueBind);
  LBind.QueueName := AFila;
  LBind.ExchangeName := DFE_EXCHANGE_NOME;
  LBind.RoutingKey := APadrao;
  FCanal.BindQueue(LBind);
end;

function TDFeAmqpPublicadorTests.NovoPublicador: IDFePublicador;
begin
  Result := TDFePublicadorAMQP.Create(Params);
end;

function TDFeAmqpPublicadorTests.EsperarMensagem(const AFila: string;
  out AResultado: TAMQPGetResult): Boolean;
var
  I: Integer;
begin
  for I := 1 to 50 do
  begin
    AResultado := FCanal.BasicGet(AFila, True);
    if AResultado.Found then
      Exit(True);
    Sleep(20);
  end;
  Result := False;
end;

procedure TDFeAmqpPublicadorTests.Publicar_ChegaNaFilaLigada_ComAcentoIntegro;
var
  LPublicador: IDFePublicador;
  LMsg: TAMQPGetResult;
begin
  AbrirCliente;
  LigarFila('t.doc', 'nfe.documento.#');
  LPublicador := NovoPublicador;

  LPublicador.Publicar('nfe.documento.sp.12345678000190', XML_COM_ACENTO);

  Assert.IsTrue(EsperarMensagem('t.doc', LMsg), 'mensagem chegou');
  Assert.AreEqual('nfe.documento.sp.12345678000190', LMsg.RoutingKey, 'routing-key');
  Assert.AreEqual(DFE_EXCHANGE_NOME, LMsg.Exchange, 'exchange');
  Assert.AreEqual(XML_COM_ACENTO, AmqpUtf8Decode(LMsg.Body), 'corpo integro em UTF-8');
end;

procedure TDFeAmqpPublicadorTests.Publicar_UsaContentTypeXmlEPersistente;
var
  LPublicador: IDFePublicador;
  LMsg: TAMQPGetResult;
begin
  AbrirCliente;
  LigarFila('t.props', '#');
  LPublicador := NovoPublicador;

  LPublicador.Publicar('nfe.documento.sp.12345678000190', '<a/>');

  Assert.IsTrue(EsperarMensagem('t.props', LMsg), 'mensagem chegou');
  Assert.AreEqual('application/xml', LMsg.Properties.ContentType, 'content-type');
  Assert.AreEqual(2, Integer(LMsg.Properties.DeliveryMode), 'delivery-mode persistente');
end;

procedure TDFeAmqpPublicadorTests.Publicar_TopicFiltraPelaRoutingKey;
var
  LPublicador: IDFePublicador;
  LMsg: TAMQPGetResult;
begin
  AbrirCliente;
  LigarFila('t.eventos', 'nfe.evento.#');
  LigarFila('t.docs', 'nfe.documento.#');
  LPublicador := NovoPublicador;

  LPublicador.Publicar('nfe.evento.ciencia.sp.12345678000190', '<ev/>');
  LPublicador.Publicar('nfe.documento.sp.12345678000190', '<doc/>');

  Assert.IsTrue(EsperarMensagem('t.eventos', LMsg), 'evento na fila de eventos');
  Assert.AreEqual('nfe.evento.ciencia.sp.12345678000190', LMsg.RoutingKey);
  Assert.IsFalse(FCanal.BasicGet('t.eventos', True).Found, 'so uma mensagem em t.eventos');

  Assert.IsTrue(EsperarMensagem('t.docs', LMsg), 'documento na fila de documentos');
  Assert.AreEqual('nfe.documento.sp.12345678000190', LMsg.RoutingKey);
  Assert.IsFalse(FCanal.BasicGet('t.docs', True).Found, 'so uma mensagem em t.docs');
end;

procedure TDFeAmqpPublicadorTests.Publicar_SemFilaLigada_NaoEErro;
var
  LPublicador: IDFePublicador;
begin
  // pub/sub: sem consumidor configurado a mensagem e' descartada pelo broker;
  // isso nao pode travar o cursor de NSU.
  LPublicador := NovoPublicador;
  LPublicador.Publicar('nfe.documento.sp.12345678000190', '<a/>');
  Assert.IsTrue(True);
end;

procedure TDFeAmqpPublicadorTests.Publicar_BrokerForaDoAr_LevantaPublicacaoFalhou;
var
  LPublicador: IDFePublicador;
  LLevantou: Boolean;
begin
  LPublicador := NovoPublicador;
  PararBroker;

  LLevantou := False;
  try
    LPublicador.Publicar('nfe.documento.sp.12345678000190', '<a/>');
  except
    on EDFePublicacaoFalhou do
      LLevantou := True;
  end;
  Assert.IsTrue(LLevantou, 'EDFePublicacaoFalhou com o broker fora do ar');
end;

procedure TDFeAmqpPublicadorTests.Publicar_DepoisQueOBrokerReinicia_Reconecta;
var
  LPublicador: IDFePublicador;
  LPorta: Word;
  LLevantou: Boolean;
begin
  LPublicador := NovoPublicador;
  LPublicador.Publicar('nfe.documento.sp.12345678000190', '<antes/>');

  LPorta := FBroker.Port;
  PararBroker;

  LLevantou := False;
  try
    LPublicador.Publicar('nfe.documento.sp.12345678000190', '<durante/>');
  except
    on EDFePublicacaoFalhou do
      LLevantou := True;
  end;
  Assert.IsTrue(LLevantou, 'falha enquanto o broker esta fora');

  IniciarBroker(LPorta);
  // a conexao velha foi descartada na falha; esta chamada reabre sozinha
  LPublicador.Publicar('nfe.documento.sp.12345678000190', '<depois/>');
  Assert.IsTrue(True);
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeAmqpPublicadorTests);

end.
