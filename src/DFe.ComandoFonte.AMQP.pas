unit DFe.ComandoFonte.AMQP;

{$I dfe.inc}

{ Implementacao real de IDFeComandoFonte: consome comandos de manifestacao
  manual de uma fila AMQP (ver DFe.Manifestacao).

  Quem quer manifestar publica na exchange 'dfe' (a mesma do resto do
  projeto) com routing-key 'comando.manifestacao' e, no corpo, o texto
  chave=valor que InterpretarComando entende (Alias, ChaveAcesso, TipoEvento,
  Justificativa). A routing-key 'comando.*' nao colide com as de documento/
  evento (<tipo>.<categoria>.<uf>.<cnpj>, decisao 4): nenhum padrao 'nfe.#'
  a alcanca. O resultado sai como evento normal na mesma exchange (decisao 14).

  Concorrencia -- o ponto que mais importa aqui. O consumidor AMQP roda em
  threads do pool do cliente, mas quem PROCESSA o comando (enviar o evento a
  SEFAZ pelo client ACBr) tem de ser a thread do host, a mesma do orquestrador:
  o client de uma unidade nao e' thread-safe e nao pode falar com a SEFAZ em
  duas threads ao mesmo tempo. Entao a callback so' interpreta e ENFILEIRA;
  ObterProximoComando (chamado pelo tick do host, ver DFe.Host.Loop) desenfileira.
  Custo: um comando espera, no maximo, o proximo tick (60s por padrao).

  Ack: assim que o comando e' interpretado e enfileirado em memoria. Se o
  processo cair entre o ack e o processamento, o comando se perde -- aceito:
  a IDFeComandoFonte nao tem "processei" e a manifestacao e' idempotente do
  lado de quem manda (basta reenviar; a SEFAZ rejeita a duplicidade, cStat 573,
  que sai como 'manifestacaorejeitada'). Comando ilegivel (InterpretarComando
  levanta) e' descartado com nack SEM requeue -- reentregar nao o consertaria
  -- e avisado por AoComandoInvalido.

  Reconexao: o consumo e' de longa duracao, entao a conexao liga a reconexao
  automatica do cliente (que recupera o consumer), ao contrario do publicador,
  que reabre sob demanda (ver DFe.Publicador.AMQP). }

interface

uses
  SysUtils, SyncObjs,
  Generics.Collections,
  AMQP.Basic.Methods,
  AMQP.Queue.Methods,
  AMQP.Connection,
  DFe.Manifestacao,
  DFe.Publicador.AMQP;

const
  DFE_COMANDO_FILA_NOME = 'dfe.comandos';
  DFE_COMANDO_ROUTING_KEY_MANIFESTACAO = 'comando.manifestacao';

type
  { Chamado quando uma mensagem da fila de comandos nao pode ser interpretada.
    ATENCAO: roda numa thread do pool do cliente AMQP, nao na do host. }
  TDFeComandoInvalidoEvent = procedure(const APayload, AMotivo: string) of object;

  TDFeComandoFonteAMQP = class(TInterfacedObject, IDFeComandoFonte)
  private
    FParams: TAMQPConnectionParams;
    FExchange: string;
    FFila: string;
    FLock: TCriticalSection;
    FPendentes: TQueue<TDFeComandoManifestacao>;
    FConexao: TAMQPConnection;
    FCanal: TAMQPChannel;
    FAoComandoInvalido: TDFeComandoInvalidoEvent;
    procedure AoReceber(AChannel: TAMQPChannel; const ADelivery: TAMQPDelivery);
  public
    constructor Create(const AParams: TAMQPConnectionParams;
      const AExchange: string = DFE_EXCHANGE_NOME;
      const AFila: string = DFE_COMANDO_FILA_NOME);
    destructor Destroy; override;

    { Conecta, declara a exchange/fila/binding (idempotente) e comeca a
      consumir. Levanta a excecao do cliente AMQP se o broker estiver fora do
      ar -- e' o host quem decide se a falta do broker impede a subida. }
    procedure Iniciar;
    procedure Parar;

    { Nao bloqueia. Devolve False quando nao ha comando pendente agora. }
    function ObterProximoComando(out AComando: TDFeComandoManifestacao): Boolean;

    property AoComandoInvalido: TDFeComandoInvalidoEvent read FAoComandoInvalido write FAoComandoInvalido;
  end;

implementation

constructor TDFeComandoFonteAMQP.Create(const AParams: TAMQPConnectionParams;
  const AExchange, AFila: string);
begin
  inherited Create;
  FParams := AParams;
  FParams.AutoReconnect := True;
  FParams.MaxReconnectAttempts := 0; // infinitas: o host nao deve ficar surdo a comando por uma queda
  FExchange := AExchange;
  FFila := AFila;
  FLock := TCriticalSection.Create;
  FPendentes := TQueue<TDFeComandoManifestacao>.Create;
end;

destructor TDFeComandoFonteAMQP.Destroy;
begin
  Parar;
  FPendentes.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TDFeComandoFonteAMQP.Iniciar;
var
  LBind: TAMQPQueueBind;
begin
  if FConexao <> nil then
    Exit;

  FConexao := TAMQPConnection.Create(FParams);
  try
    FConexao.Open;
    FCanal := FConexao.CreateChannel;
    DeclararExchangeDfe(FCanal, FExchange);
    FCanal.DeclareQueue(TAMQPQueueDeclare.Create(FFila, True));

    LBind := Default(TAMQPQueueBind);
    LBind.QueueName := FFila;
    LBind.ExchangeName := FExchange;
    LBind.RoutingKey := DFE_COMANDO_ROUTING_KEY_MANIFESTACAO;
    FCanal.BindQueue(LBind);

    FCanal.Consume(FFila, AoReceber, False);
  except
    Parar;
    raise;
  end;
end;

procedure TDFeComandoFonteAMQP.Parar;
begin
  // Cada Free e' isolado: um canal/conexao quebrados podem levantar ao fechar.
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

procedure TDFeComandoFonteAMQP.AoReceber(AChannel: TAMQPChannel;
  const ADelivery: TAMQPDelivery);
var
  LPayload: string;
  LComando: TDFeComandoManifestacao;
begin
  LPayload := ADelivery.BodyAsText;
  try
    LComando := InterpretarComando(LPayload);
  except
    on E: Exception do
    begin
      AChannel.Nack(ADelivery.DeliveryTag, False);
      if Assigned(FAoComandoInvalido) then
        FAoComandoInvalido(LPayload, E.Message);
      Exit;
    end;
  end;

  FLock.Enter;
  try
    FPendentes.Enqueue(LComando);
  finally
    FLock.Leave;
  end;
  AChannel.Ack(ADelivery.DeliveryTag);
end;

function TDFeComandoFonteAMQP.ObterProximoComando(out AComando: TDFeComandoManifestacao): Boolean;
begin
  FLock.Enter;
  try
    Result := FPendentes.Count > 0;
    if Result then
      AComando := FPendentes.Dequeue;
  finally
    FLock.Leave;
  end;
end;

end.
