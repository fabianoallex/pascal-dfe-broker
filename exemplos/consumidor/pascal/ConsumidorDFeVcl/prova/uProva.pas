unit uProva;

{ Prova do fechamento do ConsumidorDFeVcl com trabalho em andamento (F10 do
  plano da pascal-common-faa).

  A VCL e a LCL liberam as forms ANTES de qualquer finalizacao de unit, e o
  PcPool (um pool para o processo inteiro) so' e' liberado na finalizacao da
  PascalCommon.ThreadPool. Um item que a form enfileirou no pool e que ainda
  nao rodou quando ela fecha roda depois, com o ponteiro da form ja' liberada.

  Este programa sobe um broker embutido, deixa a form do consumidor conectar e
  consumir (--auto) e a fecha num de dois cenarios:

    --cenario=pool      o PcPool esta' ocupado por itens que bloqueiam; o broker
                        cai, a thread de reconexao enfileira o TConexaoEventoWork
                        da form (que fica na fila do pool) e a form e' fechada.
                        Os bloqueios sao soltos 4 s depois do pedido de fechar
                        (mais que os ~2 s que o Free da conexao leva
                        esperando a thread de reconexao).
                        Uma sentinela enfileirada logo atras do item da form
                        anota se a form ainda existia quando a fila andou.
    --cenario=entregas  2000 mensagens publicadas com a thread da UI ocupada
                        (os marshals das entregas se acumulam no TThread.Queue);
                        a form e' fechada logo que o broker confirma.

  O relatorio vai para prova-<cenario>.txt ao lado do executavel. }

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, SyncObjs, Forms, ExtCtrls,
  PascalCommon.Threading, PascalCommon.ThreadPool,
  AMQP.Connection, AMQP.Server.Broker,
  uConsumidorMain;

type
  TProva = class(TComponent)
  private
    FCenario: string;
    FPorta: Word;
    FBroker: TAMQPServer;
    FForm: TfrmConsumidor;
    FTimer: TTimer;
    FEstado: Integer;
    FInicio: UInt64;
    FPrazo: UInt64;
    FLiberar: TEvent;
    FSoltar: TThread;
    FLock: TCriticalSection;
    FRelatorio: TStringList;
    FFormDestroyOriginal: TNotifyEvent;
    // Publicador do cenario entregas. So' e' liberado depois do Close: no FPC
    // o Free de uma conexao, chamado da thread principal, junta threads com
    // WaitFor -- que roda CheckSynchronize e esvaziaria os marshals das
    // entregas antes de a form fechar (medido: 2000 de 2000 ja' recebidas).
    FPubConn: TAMQPConnection;
    FPubCanal: TAMQPChannel;
    procedure Tique(Sender: TObject);
    procedure FormDestroyEspiao(Sender: TObject);
    procedure Fechar;
    procedure PublicarLote;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Anotar(const ATexto: string);
    procedure Acompanhar(AForm: TfrmConsumidor);
    procedure Concluir;
  end;

var
  Prova: TProva;

implementation

const
  SOLTAR_APOS_MS = 4000;
  PRAZO_ESTADO_MS = 15000;
  MENSAGENS = 2000;

var
  // 1 depois que a form foi liberada (Notification opRemove).
  GFormLiberada: Integer = 0;
  // Itens desta prova (bloqueios e sentinela) ainda vivos: o Concluir espera
  // por zero antes de liberar o evento e o relatorio que eles usam.
  GItensVivos: Integer = 0;

type
  TBloqueio = class(TPcWorkItem)
  private
    FEvento: TEvent;
  public
    constructor Create(AEvento: TEvent);
    destructor Destroy; override;
    procedure Execute; override;
  end;

  TSentinela = class(TPcWorkItem)
  public
    constructor Create;
    destructor Destroy; override;
    procedure Execute; override;
  end;

  TSoltar = class(TThread)
  private
    FEvento: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(AEvento: TEvent);
  end;

constructor TBloqueio.Create(AEvento: TEvent);
begin
  inherited Create;
  FEvento := AEvento;
  PcAtomicInc(GItensVivos);
end;

destructor TBloqueio.Destroy;
begin
  PcAtomicDec(GItensVivos);
  inherited;
end;

procedure TBloqueio.Execute;
begin
  FEvento.WaitFor(30000);
end;

constructor TSentinela.Create;
begin
  inherited Create;
  PcAtomicInc(GItensVivos);
end;

destructor TSentinela.Destroy;
begin
  PcAtomicDec(GItensVivos);
  inherited;
end;

procedure TSentinela.Execute;
begin
  if PcAtomicGet(GFormLiberada) = 1 then
    Prova.Anotar('SENTINELA: a fila do pool andou com a form JA LIBERADA ' +
      '(o item da form, logo a frente, rodou depois dela)')
  else
    Prova.Anotar('sentinela: a fila do pool andou com a form ainda viva');
end;

constructor TSoltar.Create(AEvento: TEvent);
begin
  FEvento := AEvento;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TSoltar.Execute;
begin
  Sleep(SOLTAR_APOS_MS);
  Prova.Anotar('bloqueios do PcPool soltos');
  FEvento.SetEvent;
end;

{ TProva }

constructor TProva.Create(AOwner: TComponent);
var
  I: Integer;
begin
  inherited Create(AOwner);
  FLock := TCriticalSection.Create;
  FRelatorio := TStringList.Create;
  FLiberar := TEvent.Create(nil, True, False, '');
  FInicio := PcTickMs;
  FCenario := 'pool';
  FPorta := 5699;
  for I := 1 to ParamCount do
  begin
    if Copy(ParamStr(I), 1, 10) = '--cenario=' then
      FCenario := Copy(ParamStr(I), 11, MaxInt)
    else if Copy(ParamStr(I), 1, 8) = '--porta=' then
      FPorta := StrToIntDef(Copy(ParamStr(I), 9, MaxInt), FPorta);
  end;
  Anotar(Format('cenario=%s porta=%d PcPool.MaxWorkers=%d',
    [FCenario, FPorta, PcPool.MaxWorkers]));

  FBroker := TAMQPServer.Create;
  FBroker.BindAddress := '127.0.0.1';
  FBroker.Port := FPorta;
  FBroker.Start;
  Anotar('broker embutido no ar');
end;

destructor TProva.Destroy;
begin
  FPubCanal.Free;
  FPubConn.Free;
  FBroker.Free;
  FLiberar.Free;
  FRelatorio.Free;
  FLock.Free;
  inherited;
end;

procedure TProva.Anotar(const ATexto: string);
begin
  FLock.Enter;
  try
    FRelatorio.Add(Format('%6d ms  %s', [PcTickMs - FInicio, ATexto]));
  finally
    FLock.Leave;
  end;
end;

procedure TProva.Acompanhar(AForm: TfrmConsumidor);
begin
  FForm := AForm;
  FForm.FreeNotification(Self);
  FFormDestroyOriginal := FForm.OnDestroy;
  FForm.OnDestroy := FormDestroyEspiao;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 50;
  FTimer.OnTimer := Tique;
  FPrazo := PcTickMs + PRAZO_ESTADO_MS;
  FTimer.Enabled := True;
end;

procedure TProva.FormDestroyEspiao(Sender: TObject);
var
  I: Integer;
begin
  Anotar('FormDestroy; log da form:');
  for I := 0 to FForm.mmoLog.Lines.Count - 1 do
    Anotar('    | ' + FForm.mmoLog.Lines[I]);
  Anotar('    | ' + FForm.lblContadores.Caption);
  if Assigned(FFormDestroyOriginal) then
    FFormDestroyOriginal(Sender);
end;

procedure TProva.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FForm) then
  begin
    PcAtomicSet(GFormLiberada, 1);
    Anotar('form LIBERADA');
    FForm := nil;
  end;
end;

procedure TProva.Fechar;
begin
  FTimer.Enabled := False;
  Anotar('Close pedido; ' + FForm.lblContadores.Caption);
  FForm.Close;
  Anotar('Close voltou');
  FreeAndNil(FPubCanal);
  FreeAndNil(FPubConn);
end;

procedure TProva.PublicarLote;
var
  LParams: TAMQPConnectionParams;
  I: Integer;
begin
  LParams := TAMQPConnectionParams.Localhost;
  LParams.Host := '127.0.0.1';
  LParams.Port := FPorta;
  FPubConn := TAMQPConnection.Create(LParams);
  FPubConn.Open;
  FPubCanal := FPubConn.CreateChannel;
  FPubCanal.ConfirmSelect;
  for I := 1 to MENSAGENS do
    FPubCanal.PublishText('dfe', 'nfe.documento.sp.12345678000199',
      Format('<resNFe><chNFe>%.44d</chNFe></resNFe>', [I]));
  if FPubCanal.WaitForConfirms(30000) then
    Anotar(Format('%d mensagens confirmadas pelo broker', [MENSAGENS]))
  else
    Anotar('FALHA: o broker nao confirmou o lote');
end;

procedure TProva.Tique(Sender: TObject);
var
  I: Integer;
begin
  if PcTickMs > FPrazo then
  begin
    Anotar(Format('FALHA: estado %d passou do prazo', [FEstado]));
    Fechar;
    Exit;
  end;
  case FEstado of
    0:
      if FForm.btnConsumir.Caption = 'Parar consumo' then
      begin
        Anotar('form conectada e consumindo');
        FPrazo := PcTickMs + PRAZO_ESTADO_MS;
        if FCenario = 'entregas' then
        begin
          FTimer.Enabled := False;
          PublicarLote;
          Fechar;
        end
        else
        begin
          for I := 1 to PcPool.MaxWorkers + 1 do
            PcPool.Queue(TBloqueio.Create(FLiberar));
          FEstado := 1;
        end;
      end;
    1:
      if PcPool.QueueDepth >= 1 then
      begin
        Anotar(Format('PcPool ocupado: %d itens bloqueados, %d na fila',
          [PcPool.MaxWorkers, PcPool.QueueDepth]));
        FBroker.Stop;
        Anotar('broker parado (a conexao da form cai)');
        FPrazo := PcTickMs + PRAZO_ESTADO_MS;
        FEstado := 2;
      end;
    2:
      if PcPool.QueueDepth >= 2 then
      begin
        PcPool.Queue(TSentinela.Create);
        Anotar(Format('item da form (TConexaoEventoWork) na fila do PcPool; ' +
          'sentinela atras dele; QueueDepth=%d', [PcPool.QueueDepth]));
        FSoltar := TSoltar.Create(FLiberar);
        Fechar;
      end;
  end;
end;

procedure TProva.Concluir;
var
  LPrazo: UInt64;
  LArquivo: string;
begin
  Anotar('finalizacao de uProva');
  LArquivo := ExtractFilePath(ParamStr(0)) + 'prova-' + FCenario + '.txt';
  if not Assigned(FSoltar) then
    FLiberar.SetEvent;
  // Espera por polling, SEM bombear a fila do TThread.Queue: o que a prova
  // quer ver e' o que a fila do pool fez sozinha depois de a form sumir.
  LPrazo := PcTickMs + 10000;
  while (PcAtomicGet(GItensVivos) > 0) and (PcTickMs < LPrazo) do
    Sleep(10);
  Anotar(Format('itens da prova ainda vivos: %d; QueueDepth=%d',
    [PcAtomicGet(GItensVivos), PcPool.QueueDepth]));
  FBroker.Stop;
  FRelatorio.SaveToFile(LArquivo);
  if Assigned(FSoltar) then
  begin
    // No FPC, o WaitFor chamado da thread principal roda CheckSynchronize
    // (o Destroy do PcPool tambem, ao juntar os workers): um marshal que ainda
    // aponte para a form liberada roda aqui.
    Anotar('juntando a thread que soltou os bloqueios');
    FRelatorio.SaveToFile(LArquivo);
    FSoltar.WaitFor;
    FreeAndNil(FSoltar);
    Anotar('thread juntada');
    FRelatorio.SaveToFile(LArquivo);
  end;
end;

initialization

finalization
  if Assigned(Prova) then
  begin
    Prova.Concluir;
    FreeAndNil(Prova);
  end;

end.
