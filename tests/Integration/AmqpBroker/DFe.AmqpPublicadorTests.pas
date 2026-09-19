unit DFe.AmqpPublicadorTests;

{ TDFePublicadorAMQP (o IDFePublicador real) contra o broker AMQP EMBUTIDO do
  pascal-amqp-faa, in-process. O que estes testes provam e a suite pura nao
  consegue: que a mensagem chega de verdade a uma fila ligada a exchange
  'dfe', com o XML em UTF-8 integro (acentos), na routing-key certa, e que a
  falha do broker vira EDFePublicacaoFalhou (o que impede o orquestrador de
  avancar o cursor de NSU). }

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils,
  AMQP.Wire,
  AMQP.Basic.Methods,
  AMQP.Queue.Methods,
  AMQP.Connection,
  AMQP.Server.Broker,
  DFe.Errors,
  DFe.Publicador,
  DFe.Publicador.AMQP;

type
  TDFeAmqpPublicadorTests = class(TTestCase)
  private
    FBroker: TAMQPServer;
    FConexao: TAMQPConnection;
    FCanal: TAMQPChannel;
    function Params: TAMQPConnectionParams;
    procedure IniciarBroker(const APorta: Word);
    procedure PararBroker;
    { Fila de teste, ligada a exchange dfe pelo padrao dado. }
    procedure LigarFila(const AFila, APadrao: string);
    procedure AbrirCliente;
    function NovoPublicador: IDFePublicador;
    function EsperarMensagem(const AFila: string; out AResultado: TAMQPGetResult): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Publicar_ChegaNaFilaLigada_ComAcentoIntegro;
    procedure Publicar_UsaContentTypeXmlEPersistente;
    procedure Publicar_TopicFiltraPelaRoutingKey;
    procedure Publicar_SemFilaLigada_NaoEErro;
    procedure Publicar_BrokerForaDoAr_LevantaPublicacaoFalhou;
    procedure Publicar_DepoisQueOBrokerReinicia_Reconecta;
  end;

implementation

const
  XML_COM_ACENTO =
    '<?xml version="1.0" encoding="UTF-8"?><resNFe><xNome>JOS' + #$C3#$89 +
    ' A' + #$C3#$87 + 'OUGUE LTDA</resNFe>';

procedure TDFeAmqpPublicadorTests.SetUp;
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
  // a exchange e' declarada pelo publicador, mas o teste precisa dela ANTES
  // do primeiro publish para ligar a fila -- mesma declaracao, idempotente.
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
  // Publicar so' retorna depois do confirm do broker, entao a mensagem ja esta
  // na fila; a espera curta cobre so' a latencia de entrega ao Basic.Get.
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

  AssertTrue('mensagem chegou', EsperarMensagem('t.doc', LMsg));
  AssertEquals('routing-key', 'nfe.documento.sp.12345678000190', LMsg.RoutingKey);
  AssertEquals('exchange', DFE_EXCHANGE_NOME, LMsg.Exchange);
  AssertEquals('corpo integro em UTF-8', XML_COM_ACENTO, AmqpUtf8Decode(LMsg.Body));
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

  AssertTrue('mensagem chegou', EsperarMensagem('t.props', LMsg));
  AssertEquals('content-type', 'application/xml', LMsg.Properties.ContentType);
  AssertEquals('delivery-mode persistente', 2, Integer(LMsg.Properties.DeliveryMode));
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

  AssertTrue('evento na fila de eventos', EsperarMensagem('t.eventos', LMsg));
  AssertEquals('nfe.evento.ciencia.sp.12345678000190', LMsg.RoutingKey);
  AssertFalse('so uma mensagem em t.eventos', FCanal.BasicGet('t.eventos', True).Found);

  AssertTrue('documento na fila de documentos', EsperarMensagem('t.docs', LMsg));
  AssertEquals('nfe.documento.sp.12345678000190', LMsg.RoutingKey);
  AssertFalse('so uma mensagem em t.docs', FCanal.BasicGet('t.docs', True).Found);
end;

procedure TDFeAmqpPublicadorTests.Publicar_SemFilaLigada_NaoEErro;
var
  LPublicador: IDFePublicador;
begin
  // pub/sub: sem consumidor configurado a mensagem e' descartada pelo broker;
  // isso nao pode travar o cursor de NSU.
  LPublicador := NovoPublicador;
  LPublicador.Publicar('nfe.documento.sp.12345678000190', '<a/>');
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
  AssertTrue('EDFePublicacaoFalhou com o broker fora do ar', LLevantou);
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
  AssertTrue('falha enquanto o broker esta fora', LLevantou);

  IniciarBroker(LPorta);
  // a conexao velha foi descartada na falha; esta chamada reabre sozinha
  LPublicador.Publicar('nfe.documento.sp.12345678000190', '<depois/>');
end;

initialization
  RegisterTest(TDFeAmqpPublicadorTests);

end.
