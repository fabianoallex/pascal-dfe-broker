unit DFe.Publicador.AMQP;

{$I dfe.inc}

{ Implementacao real de IDFePublicador sobre o cliente do pascal-amqp-faa
  (../pascal-amqp-faa). Fala AMQP 0-9-1 padrao, entao serve tanto para o
  broker EMBUTIDO (TAMQPServer, no mesmo processo, em 127.0.0.1) quanto para
  um RabbitMQ externo -- so' muda TAMQPConnectionParams (decisao 3).

  Contrato que o orquestrador exige (ver DFe.Orquestrador, ExecutarUnidade):
  o cursor de NSU so' avanca depois de Publicar retornar para TODOS os
  eventos do lote. Por isso Publicar e' SINCRONO e so' retorna depois do
  broker CONFIRMAR a mensagem (publisher confirms); qualquer falha --
  conexao caida, nack, timeout -- vira EDFePublicacaoFalhou e o lote inteiro
  e' refeito no proximo ciclo (entrega pelo menos uma vez; o consumidor pode
  ver o mesmo documento duas vezes, e a chave de acesso serve para deduplicar).

  Reconexao: a conexao e' aberta sob demanda e refeita na primeira chamada
  depois de uma falha. O orquestrador so' publica de hora em hora por
  unidade, entao a conexao passa a maior parte do tempo ociosa -- reabrir
  preguicosamente e' mais simples e mais robusto do que manter a reconexao
  automatica do cliente em segundo plano (que continua disponivel, opt-in, em
  TAMQPConnectionParams.AutoReconnect, para quem quiser).

  Mensagem publicada: corpo = o XML em UTF-8 (ver "Encoding do XML" em
  docs/architecture.md), content-type application/xml, persistente
  (delivery-mode 2). NAO e' 'mandatory': sem nenhuma fila ligada a exchange
  a mensagem e' descartada pelo broker, que e' o comportamento esperado de
  um pub/sub -- as filas sao configuradas por quem consome. }

interface

uses
  SysUtils, SyncObjs,
  AMQP.Wire,
  AMQP.Basic.Methods,
  AMQP.Exchange.Methods,
  AMQP.Queue.Methods,
  AMQP.Connection,
  DFe.Errors,
  DFe.Publicador;

const
  { Exchange topic unica do projeto (decisao 4, docs/architecture.md). }
  DFE_EXCHANGE_NOME = 'dfe';

  DFE_PUBLICADOR_CONFIRMACAO_TIMEOUT_MS = 10000;

type
  TDFePublicadorAMQP = class(TInterfacedObject, IDFePublicador)
  private
    FParams: TAMQPConnectionParams;
    FExchange: string;
    FConfirmacaoTimeoutMs: Cardinal;
    FLock: TCriticalSection;
    FConexao: TAMQPConnection;
    FCanal: TAMQPChannel;
    procedure Desconectar;
    procedure GarantirConexao;
  public
    constructor Create(const AParams: TAMQPConnectionParams;
      const AExchange: string = DFE_EXCHANGE_NOME);
    destructor Destroy; override;

    { Levanta EDFePublicacaoFalhou se o broker nao confirmar. }
    procedure Publicar(const ARoutingKey: string; const APayload: string);

    property ConfirmacaoTimeoutMs: Cardinal read FConfirmacaoTimeoutMs write FConfirmacaoTimeoutMs;
  end;

{ Declara a exchange topic duravel do projeto (idempotente). Exposta porque o
  consumidor de comandos (DFe.ComandoFonte.AMQP) e os testes precisam da mesma
  declaracao, com os mesmos argumentos -- declarar de novo com argumentos
  diferentes e' erro no broker (PRECONDITION_FAILED). }
procedure DeclararExchangeDfe(const ACanal: TAMQPChannel;
  const AExchange: string = DFE_EXCHANGE_NOME);

{ Declara uma fila duravel e a liga a exchange pelos padroes topic dados
  (idempotente). E' o que faz o host para as filas de [fila:<nome>] da config:
  sem uma fila ligada, o broker DESCARTA o que for publicado (pub/sub), e o
  cursor de NSU ja' teria avancado. }
procedure DeclararFilaLigada(const ACanal: TAMQPChannel; const AFila: string;
  const APadroes: array of string; const AExchange: string = DFE_EXCHANGE_NOME);

implementation

procedure DeclararExchangeDfe(const ACanal: TAMQPChannel; const AExchange: string);
var
  LDeclare: TAMQPExchangeDeclare;
begin
  LDeclare := TAMQPExchangeDeclare.Create(AExchange, AMQP_EXCHANGE_TYPE_TOPIC, True);
  ACanal.DeclareExchange(LDeclare);
end;

procedure DeclararFilaLigada(const ACanal: TAMQPChannel; const AFila: string;
  const APadroes: array of string; const AExchange: string);
var
  LBind: TAMQPQueueBind;
  I: Integer;
begin
  ACanal.DeclareQueue(TAMQPQueueDeclare.Create(AFila, True));
  for I := 0 to High(APadroes) do
  begin
    LBind := Default(TAMQPQueueBind);
    LBind.QueueName := AFila;
    LBind.ExchangeName := AExchange;
    LBind.RoutingKey := APadroes[I];
    ACanal.BindQueue(LBind);
  end;
end;

constructor TDFePublicadorAMQP.Create(const AParams: TAMQPConnectionParams;
  const AExchange: string);
begin
  inherited Create;
  FParams := AParams;
  FExchange := AExchange;
  FConfirmacaoTimeoutMs := DFE_PUBLICADOR_CONFIRMACAO_TIMEOUT_MS;
  FLock := TCriticalSection.Create;
end;

destructor TDFePublicadorAMQP.Destroy;
begin
  Desconectar;
  FLock.Free;
  inherited Destroy;
end;

procedure TDFePublicadorAMQP.Desconectar;
begin
  // Cada Free e' isolado: um canal/conexao ja quebrados podem levantar ao
  // fechar, e isso nao pode impedir a proxima tentativa de reconectar.
  if FCanal <> nil then
  begin
    try
      FCanal.Free;
    except
    end;
    FCanal := nil;
  end;
  if FConexao <> nil then
  begin
    try
      FConexao.Free;
    except
    end;
    FConexao := nil;
  end;
end;

procedure TDFePublicadorAMQP.GarantirConexao;
begin
  if (FConexao <> nil) and FConexao.IsOpen and (FCanal <> nil) and FCanal.IsOpen then
    Exit;

  Desconectar;
  FConexao := TAMQPConnection.Create(FParams);
  try
    FConexao.Open;
    FCanal := FConexao.CreateChannel;
    DeclararExchangeDfe(FCanal, FExchange);
    FCanal.ConfirmSelect;
  except
    Desconectar;
    raise;
  end;
end;

procedure TDFePublicadorAMQP.Publicar(const ARoutingKey: string; const APayload: string);
var
  LProps: TAMQPBasicProperties;
  LSeq: UInt64;
begin
  FLock.Enter;
  try
    try
      GarantirConexao;

      LProps := TAMQPBasicProperties.Empty;
      LProps.SetContentType('application/xml');
      LProps.SetPersistent;

      LSeq := FCanal.Publish(FExchange, ARoutingKey, AmqpUtf8Encode(APayload), LProps);
      if not FCanal.WaitForConfirm(LSeq, FConfirmacaoTimeoutMs) then
        raise EDFePublicacaoFalhou.CreateFmt(
          'Broker nao confirmou a mensagem (routing-key %s): nack, timeout ou conexao perdida', [ARoutingKey]);
    except
      on E: EDFePublicacaoFalhou do
      begin
        Desconectar; // estado incerto: a proxima chamada reabre do zero
        raise;
      end;
      on E: Exception do
      begin
        Desconectar;
        raise EDFePublicacaoFalhou.CreateFmt(
          'Falha ao publicar (routing-key %s): %s: %s', [ARoutingKey, E.ClassName, E.Message]);
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

end.
