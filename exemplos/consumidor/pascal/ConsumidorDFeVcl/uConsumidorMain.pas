unit uConsumidorMain;

{ Consumidor Pascal dos documentos do pascal-dfe-broker, usando SO' o lado
  CLIENTE da lib pascal-amqp-faa -- nada do broker e' linkado aqui. E' o
  equivalente visual de exemplos/consumidor/python/consumir.py + manifestar.py.

  O que este sample mostra, na ordem em que o codigo acontece:

  1. CONECTAR: TAMQPConnection com reconexao automatica; um canal so' para
     publicar (o comando de manifestacao).
  2. CONSUMIR, de dois jeitos (o contrato esta em exemplos/consumidor/README.md):
     - fila PROPRIA: exclusiva + auto-delete, ligada a exchange 'dfe' por um
       padrao topic (ex.: nfe.#). Cada consumidor recebe uma COPIA; a fila
       some quando ele sai, entao nao guarda nada enquanto ele esta fora.
     - fila NOMEADA (a do [fila:*] do dfe.ini, duravel): so' le. Acumula o
       que chegou com o consumidor fora do ar; varios consumidores da mesma
       fila dividem o trabalho.
  3. PROCESSAR e so' DEPOIS confirmar (Ack): "salvar o XML numa pasta" e' o
     processamento de verdade deste sample. Se falhar, NAO confirma -- a
     mensagem volta para a fila quando o consumo parar. Sem pasta, o
     processamento e' so' ler e listar.
  4. DEDUPLICAR pela chave de acesso: a entrega e' "pelo menos uma vez".
  5. MANIFESTAR: publica o comando na exchange 'dfe' (routing-key
     comando.manifestacao); o resultado volta como um evento normal.

  Compila nos dois mundos a partir do MESMO fonte (padrao dos samples GUI da
  lib): callbacks nomeados ('of object'), marshals descartaveis + TThread.Queue
  para a UI, e eventos de conexao saltando pelo AmqpPool (gotcha do
  TThread.Queue descartado no FPC; ver uEventosMain, no sample EventosTopicVcl
  da lib). }

interface

uses
  // No FPC, a camada de emulacao da LCL (LCLIntf/LCLType/LMessages) cobre as
  // chamadas WinAPI do autoscroll em qualquer widgetset (win32, gtk2...).
  {$IFDEF FPC}
  LCLIntf, LCLType, LMessages,
  {$ELSE}
  Windows, Messages,
  {$ENDIF}
  SysUtils, Classes, Contnrs,
  Graphics, Controls, Forms, Dialogs, StdCtrls, ComCtrls, ExtCtrls,
  AMQP.Wire, AMQP.Threading, AMQP.Connection,
  AMQP.Exchange.Methods, AMQP.Queue.Methods, AMQP.Basic.Methods,
  uDFeDocumento;

type
  { Dono do XML de uma linha da lista (o TListItem so' guarda o ponteiro).
    Criado e destruido SOMENTE na thread da UI. }
  TDocItem = class
    Xml: string;
    Info: TDFeInfo;
  end;

  TfrmConsumidor = class(TForm)
    pnlTopo: TPanel;
    gbConexao: TGroupBox;
    lblHost: TLabel;
    edtHost: TEdit;
    lblPorta: TLabel;
    edtPorta: TEdit;
    lblVHost: TLabel;
    edtVHost: TEdit;
    lblUsuario: TLabel;
    edtUsuario: TEdit;
    lblSenha: TLabel;
    edtSenha: TEdit;
    btnConectar: TButton;
    lblStatus: TLabel;
    gbOrigem: TGroupBox;
    rbPropria: TRadioButton;
    edtPadrao: TEdit;
    rbNomeada: TRadioButton;
    edtFila: TEdit;
    chkSalvar: TCheckBox;
    edtPasta: TEdit;
    btnConsumir: TButton;
    pnlContadores: TPanel;
    lblContadores: TLabel;
    btnLimparLista: TButton;
    lvDocs: TListView;
    pnlBaixo: TPanel;
    gbManifestacao: TGroupBox;
    lblAlias: TLabel;
    edtAlias: TEdit;
    lblChave: TLabel;
    edtChave: TEdit;
    lblTipo: TLabel;
    cboTipo: TComboBox;
    lblJustificativa: TLabel;
    edtJustificativa: TEdit;
    btnManifestar: TButton;
    mmoLog: TMemo;
    mmoXml: TMemo;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormDestroy(Sender: TObject);
    procedure btnConectarClick(Sender: TObject);
    procedure btnConsumirClick(Sender: TObject);
    procedure btnManifestarClick(Sender: TObject);
    procedure btnLimparListaClick(Sender: TObject);
    procedure rbOrigemClick(Sender: TObject);
    procedure lvDocsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
  private
    FConn: TAMQPConnection;
    FCanalPub: TAMQPChannel;   // so' publica (comando de manifestacao)
    FCanal: TAMQPChannel;      // so' consome; criado a cada "Iniciar consumo"
    FTag: string;              // consumer-tag do consumo em andamento
    FFilaPropria: string;      // nome da fila exclusiva (vazio no modo nomeado)
    FPadrao: string;           // binding key da fila propria
    // Lidos pela thread do callback; fixados ao iniciar o consumo e so'
    // mudam com o consumo parado (os controles ficam desabilitados).
    FSalvar: Boolean;
    FPasta: string;
    // So' na thread da UI:
    FVistas: TStringList;      // chaves de dedup ja' vistas (ordenada)
    FDocs: TObjectList;        // TDocItem, na mesma ordem das linhas de lvDocs
    FRecebidas, FNovas, FRepetidas, FIlegiveis, FSalvas: Integer;
    function ScrollAtBottom(AHandle: HWND): Boolean;
    procedure Log(const AMsg: string);
    procedure AtualizarControles;
    procedure AtualizarContadores;
    function BuildParams: TAMQPConnectionParams;
    procedure IniciarConsumo;
    procedure PararConsumo;
    procedure Desconectar;
    function SalvarXml(const ABody: TBytes; const AInfo: TDFeInfo): string;
    // Atualizacoes de UI (thread da UI, via marshals):
    procedure DocumentoRecebido(const ARoutingKey, AXml, AArquivo: string;
      const AInfo: TDFeInfo; ARedelivered: Boolean);
    procedure ComandoDevolvido(const ARoutingKey: string);
    procedure ConexaoCaiu;
    procedure ConexaoVoltou;
    procedure ConexaoFalhou;
    // Callbacks da lib (threads do pool / de reconexao):
    procedure OnDocumento(AChannel: TAMQPChannel; const ADelivery: TAMQPDelivery);
    procedure OnDevolvida(AChannel: TAMQPChannel; const AReturned: TAMQPReturnedMessage);
    procedure OnDesconectado(AConnection: TAMQPConnection);
    procedure OnReconectado(AConnection: TAMQPConnection);
    procedure OnReconexaoFalhou(AConnection: TAMQPConnection);
    procedure QueueLog(const ATexto: string);
  end;

var
  frmConsumidor: TfrmConsumidor;

implementation

{$IFDEF FPC}
  {$R *.lfm}
{$ELSE}
  {$R *.dfm}
{$ENDIF}

{$IFDEF FPC}
const
  // A LCL nao tem a unit Messages; LM_VSCROLL tem o mesmo valor do WM_VSCROLL.
  WM_VSCROLL = LM_VSCROLL;
{$ENDIF}

const
  MAX_LINHAS = 1000;  // a lista guarda as ultimas; o que passar disso sai pela ponta
  PREFETCH = 20;      // nao confirmadas em voo por vez

function NovoSufixo: string;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  Result := Copy(GUIDToString(LGuid), 2, 8);
end;

type
  // Um objeto por chamada: TThread.Queue no FPC so' aceita 'procedure of
  // object' SEM PARAMETROS, entao os dados viajam num objeto descartavel (nao
  // num campo da form, que teria corrida entre callbacks concorrentes). Se
  // autodestroi apos rodar.
  TLogMarshal = class
    Form: TfrmConsumidor;
    Texto: string;
    procedure Execute;
  end;

  TDocMarshal = class
    Form: TfrmConsumidor;
    RoutingKey, Xml, Arquivo: string;
    Info: TDFeInfo;
    Redelivered: Boolean;
    procedure Execute;
  end;

  TDevolvidoMarshal = class
    Form: TfrmConsumidor;
    RoutingKey: string;
    procedure Execute;
  end;

  TConexaoEvento = (ceCaiu, ceVoltou, ceFalhou);

  TConexaoMarshal = class
    Form: TfrmConsumidor;
    Evento: TConexaoEvento;
    procedure Execute;
  end;

  { Eventos de conexao rodam na thread de RECONEXAO da lib, que morre logo apos
    o OnReconnect -- no FPC um TThread.Queue postado por thread que morre antes
    do bombeio e' DESCARTADO. Salto por um worker persistente do AmqpPool. }
  TConexaoEventoWork = class(TAMQPWorkItem)
  private
    FForm: TfrmConsumidor;
    FEvento: TConexaoEvento;
  public
    constructor Create(AForm: TfrmConsumidor; AEvento: TConexaoEvento);
    procedure Execute; override;
  end;

procedure TLogMarshal.Execute;
begin
  Form.Log(Texto);
  Free;
end;

procedure TDocMarshal.Execute;
begin
  Form.DocumentoRecebido(RoutingKey, Xml, Arquivo, Info, Redelivered);
  Free;
end;

procedure TDevolvidoMarshal.Execute;
begin
  Form.ComandoDevolvido(RoutingKey);
  Free;
end;

procedure TConexaoMarshal.Execute;
begin
  case Evento of
    ceCaiu:   Form.ConexaoCaiu;
    ceVoltou: Form.ConexaoVoltou;
    ceFalhou: Form.ConexaoFalhou;
  end;
  Free;
end;

constructor TConexaoEventoWork.Create(AForm: TfrmConsumidor; AEvento: TConexaoEvento);
begin
  inherited Create;
  FForm := AForm;
  FEvento := AEvento;
end;

procedure TConexaoEventoWork.Execute;
var
  LMarshal: TConexaoMarshal;
begin
  LMarshal := TConexaoMarshal.Create;
  LMarshal.Form := FForm;
  LMarshal.Evento := FEvento;
  TThread.Queue(nil, LMarshal.Execute);
end;

{ TfrmConsumidor }

procedure TfrmConsumidor.FormCreate(Sender: TObject);
var
  I: Integer;
begin
  FVistas := TStringList.Create;
  FVistas.Sorted := True;
  FVistas.Duplicates := dupIgnore;
  FDocs := TObjectList.Create(True);
  for I := Low(DFE_TIPOS_MANIFESTACAO) to High(DFE_TIPOS_MANIFESTACAO) do
    cboTipo.Items.Add(DFE_TIPOS_MANIFESTACAO[I]);
  cboTipo.ItemIndex := 0;
  AtualizarContadores;
  AtualizarControles;
end;

procedure TfrmConsumidor.FormShow(Sender: TObject);
var
  I: Integer;
  LParam: string;
  LAuto: Boolean;
begin
  // Linha de comando (para demonstrar sem clicar): --auto conecta e comeca a
  // consumir com o que estiver nos campos; --host=, --porta=, --fila=nome
  // (fila nomeada) e --salvar=pasta preenchem os campos antes disso.
  LAuto := False;
  for I := 1 to ParamCount do
  begin
    LParam := ParamStr(I);
    if LParam = '--auto' then
      LAuto := True
    else if Copy(LParam, 1, 7) = '--host=' then
      edtHost.Text := Copy(LParam, 8, MaxInt)
    else if Copy(LParam, 1, 8) = '--porta=' then
      edtPorta.Text := Copy(LParam, 9, MaxInt)
    else if Copy(LParam, 1, 7) = '--fila=' then
    begin
      edtFila.Text := Copy(LParam, 8, MaxInt);
      rbNomeada.Checked := True;
    end
    else if Copy(LParam, 1, 9) = '--salvar=' then
    begin
      edtPasta.Text := Copy(LParam, 10, MaxInt);
      chkSalvar.Checked := True;
    end;
  end;
  AtualizarControles;
  if LAuto then
  begin
    btnConectarClick(nil);
    if Assigned(FConn) then
      btnConsumirClick(nil);
  end;
end;

procedure TfrmConsumidor.FormDestroy(Sender: TObject);
begin
  FDocs.Free;
  FVistas.Free;
end;

procedure TfrmConsumidor.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  // Cancela o consumo primeiro (drena os callbacks em voo); depois os canais.
  PararConsumo;
  FreeAndNil(FCanalPub);
  // Os marshals que os callbacks postaram ainda estao na fila do
  // TThread.Queue -- bombear aqui os drena com a form ainda viva.
  Application.ProcessMessages;
  FreeAndNil(FConn);
  // O Free da conexao encerra a thread de reconexao; um TConexaoEventoWork ja
  // enfileirado no pool pode estar postando o ultimo marshal NESTE instante.
  Sleep(100);
  Application.ProcessMessages;
end;

function TfrmConsumidor.ScrollAtBottom(AHandle: HWND): Boolean;
var
  LInfo: TScrollInfo;
begin
  FillChar(LInfo, SizeOf(LInfo), 0);
  LInfo.cbSize := SizeOf(LInfo);
  LInfo.fMask := SIF_ALL;
  if not GetScrollInfo(AHandle, SB_VERT, LInfo) then
    Exit(True); // sem scrollbar ainda (conteudo cabe todo) = considera "no fim"
  Result := (LInfo.nPos + Integer(LInfo.nPage)) >= LInfo.nMax;
end;

procedure TfrmConsumidor.Log(const AMsg: string);
var
  LAtBottom: Boolean;
begin
  LAtBottom := ScrollAtBottom(mmoLog.Handle);
  mmoLog.Lines.Add(FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + AMsg);
  if LAtBottom then
    SendMessage(mmoLog.Handle, WM_VSCROLL, SB_BOTTOM, 0);
end;

// De qualquer thread (callbacks da lib): leva o texto ate' o log da UI.
procedure TfrmConsumidor.QueueLog(const ATexto: string);
var
  LMarshal: TLogMarshal;
begin
  LMarshal := TLogMarshal.Create;
  LMarshal.Form := Self;
  LMarshal.Texto := ATexto;
  TThread.Queue(nil, LMarshal.Execute);
end;

procedure TfrmConsumidor.AtualizarContadores;
begin
  lblContadores.Caption := Format(
    'Recebidas: %d    novas: %d    repetidas: %d    ilegiveis: %d    XML salvos: %d',
    [FRecebidas, FNovas, FRepetidas, FIlegiveis, FSalvas]);
end;

procedure TfrmConsumidor.AtualizarControles;
var
  LConectado, LConsumindo: Boolean;
begin
  LConectado := Assigned(FConn);
  LConsumindo := FTag <> '';

  if LConectado then
  begin
    btnConectar.Caption := 'Desconectar';
    lblStatus.Caption := 'Conectado';
    lblStatus.Font.Color := clGreen;
  end
  else
  begin
    btnConectar.Caption := 'Conectar';
    lblStatus.Caption := 'Desconectado';
    lblStatus.Font.Color := clRed;
  end;
  edtHost.Enabled := not LConectado;
  edtPorta.Enabled := not LConectado;
  edtVHost.Enabled := not LConectado;
  edtUsuario.Enabled := not LConectado;
  edtSenha.Enabled := not LConectado;

  if LConsumindo then
    btnConsumir.Caption := 'Parar consumo'
  else
    btnConsumir.Caption := 'Iniciar consumo';
  btnConsumir.Enabled := LConectado;
  rbPropria.Enabled := not LConsumindo;
  rbNomeada.Enabled := not LConsumindo;
  edtPadrao.Enabled := (not LConsumindo) and rbPropria.Checked;
  edtFila.Enabled := (not LConsumindo) and rbNomeada.Checked;
  chkSalvar.Enabled := not LConsumindo;
  edtPasta.Enabled := not LConsumindo;

  btnManifestar.Enabled := LConectado;
end;

procedure TfrmConsumidor.rbOrigemClick(Sender: TObject);
begin
  AtualizarControles;
end;

procedure TfrmConsumidor.btnLimparListaClick(Sender: TObject);
begin
  lvDocs.Items.Clear;
  FDocs.Clear;
  mmoXml.Clear;
  FVistas.Clear; // recomeca a deduplicacao junto com a lista
  FRecebidas := 0;
  FNovas := 0;
  FRepetidas := 0;
  FIlegiveis := 0;
  FSalvas := 0;
  AtualizarContadores;
end;

function TfrmConsumidor.BuildParams: TAMQPConnectionParams;
begin
  Result := TAMQPConnectionParams.Localhost;
  Result.Host := Trim(edtHost.Text);
  Result.Port := StrToIntDef(Trim(edtPorta.Text), Result.Port);
  Result.VirtualHost := edtVHost.Text;
  Result.User := edtUsuario.Text;
  Result.Password := edtSenha.Text;
  // Se o broker cair e voltar, a lib reabre a conexao e refaz a topologia
  // gravada (fila propria, binding e consumer) sozinha.
  Result.AutoReconnect := True;
  Result.ReconnectDelayMs := 2000;
  Result.MaxReconnectAttempts := 0;
  Result.ConnectionName := 'ConsumidorDFeVcl';
end;

{ --- conexao ----------------------------------------------------------------- }

procedure TfrmConsumidor.Desconectar;
begin
  PararConsumo;
  FreeAndNil(FCanalPub);
  FreeAndNil(FConn);
end;

procedure TfrmConsumidor.btnConectarClick(Sender: TObject);
var
  LParams: TAMQPConnectionParams;
begin
  if Assigned(FConn) then
  begin
    try
      Desconectar;
      Log('Desconectado.');
    except
      on E: Exception do
        Log('Erro ao desconectar: ' + E.Message);
    end;
    AtualizarControles;
    Exit;
  end;

  LParams := BuildParams;
  try
    FConn := TAMQPConnection.Create(LParams);
    FConn.OnDisconnect := OnDesconectado;
    FConn.OnReconnect := OnReconectado;
    FConn.OnReconnectFailed := OnReconexaoFalhou;
    FConn.Open;

    // Canal so' para publicar. Declarar a exchange e' idempotente desde que
    // igual (topic, duravel) -- o host declara a mesma.
    FCanalPub := FConn.CreateChannel;
    FCanalPub.OnBasicReturn := OnDevolvida;
    FCanalPub.DeclareExchange(TAMQPExchangeDeclare.Create(DFE_EXCHANGE, AMQP_EXCHANGE_TYPE_TOPIC));

    Log(Format('Conectado a %s:%d (vhost "%s"). Exchange topic "%s" declarada.',
      [LParams.Host, LParams.Port, LParams.VirtualHost, DFE_EXCHANGE]));
  except
    on E: Exception do
    begin
      Log('Falha ao conectar: ' + E.Message);
      FreeAndNil(FCanalPub);
      FreeAndNil(FConn);
    end;
  end;
  AtualizarControles;
end;

// Os tres eventos de conexao saltam pelo AmqpPool em vez de postar direto
// (ver o comentario de TConexaoEventoWork).
procedure TfrmConsumidor.OnDesconectado(AConnection: TAMQPConnection);
begin
  AmqpPool.Queue(TConexaoEventoWork.Create(Self, ceCaiu));
end;

procedure TfrmConsumidor.OnReconectado(AConnection: TAMQPConnection);
begin
  AmqpPool.Queue(TConexaoEventoWork.Create(Self, ceVoltou));
end;

procedure TfrmConsumidor.OnReconexaoFalhou(AConnection: TAMQPConnection);
begin
  AmqpPool.Queue(TConexaoEventoWork.Create(Self, ceFalhou));
end;

procedure TfrmConsumidor.ConexaoCaiu;
begin
  lblStatus.Caption := 'Conexao caiu - reconectando...';
  lblStatus.Font.Color := clMaroon;
  Log('Conexao caiu. Reconexao automatica em andamento; a fila propria, o ' +
    'binding e o consumer serao recriados no recovery. Documentos publicados ' +
    'enquanto isso so'' chegam se a fila for NOMEADA (duravel).');
end;

procedure TfrmConsumidor.ConexaoVoltou;
begin
  lblStatus.Caption := 'Conectado';
  lblStatus.Font.Color := clGreen;
  Log('Reconectado: topologia e consumer restaurados.');
end;

procedure TfrmConsumidor.ConexaoFalhou;
begin
  lblStatus.Caption := 'Reconexao esgotada';
  lblStatus.Font.Color := clRed;
  Log('Reconexao desistiu (MaxReconnectAttempts atingido).');
end;

{ --- consumo ----------------------------------------------------------------- }

procedure TfrmConsumidor.btnConsumirClick(Sender: TObject);
begin
  if not Assigned(FConn) then
    Exit;
  if FTag <> '' then
  begin
    PararConsumo;
    AtualizarControles;
  end
  else
  begin
    IniciarConsumo;
    AtualizarControles;
  end;
end;

procedure TfrmConsumidor.IniciarConsumo;
var
  LDeclare: TAMQPQueueDeclare;
  LOk: TAMQPQueueDeclareOk;
  LBind: TAMQPQueueBind;
  LFila: string;
begin
  FSalvar := chkSalvar.Checked and (Trim(edtPasta.Text) <> '');
  FPasta := Trim(edtPasta.Text);
  if chkSalvar.Checked and (FPasta = '') then
    Log('"Salvar XML" marcado sem pasta: nada sera salvo (so'' leitura e lista).');
  if FSalvar then
  begin
    try
      ForceDirectories(FPasta);
    except
      on E: Exception do
      begin
        Log('Nao consegui criar a pasta "' + FPasta + '": ' + E.Message);
        Exit;
      end;
    end;
  end;

  // Canal proprio do consumo: se a declaracao passiva de uma fila que nao
  // existe falhar (404), o broker FECHA o canal -- descartar so' este mantem o
  // de publicacao (e a conexao) intactos.
  FCanal := FConn.CreateChannel;
  try
    FCanal.Qos(PREFETCH);

    if rbPropria.Checked then
    begin
      FPadrao := Trim(edtPadrao.Text);
      if FPadrao = '' then
      begin
        Log('Informe o padrao (binding key), ex.: nfe.#  nfe.documento.sp.*  nfe.evento.#');
        FreeAndNil(FCanal);
        Exit;
      end;
      FFilaPropria := 'dfe-consumidor-' + NovoSufixo;

      // Fila descartavel: exclusiva (so' esta conexao) e auto-delete.
      LDeclare := TAMQPQueueDeclare.Create(FFilaPropria, False);
      LDeclare.Exclusive := True;
      LDeclare.AutoDelete := True;
      FCanal.DeclareQueue(LDeclare);

      LBind := Default(TAMQPQueueBind);
      LBind.QueueName := FFilaPropria;
      LBind.ExchangeName := DFE_EXCHANGE;
      LBind.RoutingKey := FPadrao; // '*' = uma palavra; '#' = zero ou mais
      FCanal.BindQueue(LBind);
      LFila := FFilaPropria;
      Log(Format('Fila propria "%s" ligada a "%s". Recebe uma copia do que casar, ' +
        'a partir de agora.', [FFilaPropria, FPadrao]));
    end
    else
    begin
      LFila := Trim(edtFila.Text);
      FFilaPropria := '';
      FPadrao := '';
      // Passiva: a fila e' do dfe.ini (o host a declara); aqui so' se confere
      // que existe e quantas mensagens ja' esperam.
      LDeclare := TAMQPQueueDeclare.Create(LFila, True);
      LDeclare.Passive := True;
      LOk := FCanal.DeclareQueue(LDeclare);
      Log(Format('Fila nomeada "%s": %d mensagem(ns) aguardando, %d consumidor(es) ja'' ligado(s).',
        [LFila, LOk.MessageCount, LOk.ConsumerCount]));
    end;

    // ANoAck=False (padrao): o Ack e' NOSSO, depois de processar.
    FTag := FCanal.Consume(LFila, OnDocumento);
    if FSalvar then
      Log('Consumindo "' + LFila + '", salvando os XML em ' + FPasta + '.')
    else
      Log('Consumindo "' + LFila + '".');
  except
    on E: Exception do
    begin
      Log('Erro ao iniciar o consumo: ' + E.Message);
      FTag := '';
      FFilaPropria := '';
      FreeAndNil(FCanal);
    end;
  end;
end;

procedure TfrmConsumidor.PararConsumo;
var
  LUnbind: TAMQPQueueUnbind;
  LDelete: TAMQPQueueDelete;
begin
  if FCanal = nil then
    Exit;
  try
    if FTag <> '' then
      FCanal.Cancel(FTag); // para as entregas e drena os callbacks em voo
    // Fila propria: desfaz na ordem inversa e tira da topologia de recovery --
    // sem isto, uma reconexao replayaria o bind de uma fila que nao existe mais.
    if FFilaPropria <> '' then
    begin
      LUnbind := Default(TAMQPQueueUnbind);
      LUnbind.QueueName := FFilaPropria;
      LUnbind.ExchangeName := DFE_EXCHANGE;
      LUnbind.RoutingKey := FPadrao;
      FCanal.UnbindQueue(LUnbind);
      LDelete := Default(TAMQPQueueDelete);
      LDelete.QueueName := FFilaPropria;
      FCanal.DeleteQueue(LDelete);
    end;
  except
    on E: Exception do
      Log('Erro ao parar o consumo: ' + E.Message);
  end;
  // Fechar o canal devolve a fila nomeada o que foi entregue e nao confirmado.
  FreeAndNil(FCanal);
  if FTag <> '' then
    Log('Consumo parado.');
  FTag := '';
  FFilaPropria := '';
  FPadrao := '';
end;

// Grava o corpo (ja' e' UTF-8: o que o broker publica) numa pasta e devolve o
// caminho. Levanta se falhar -- quem chama NAO confirma a mensagem.
function TfrmConsumidor.SalvarXml(const ABody: TBytes; const AInfo: TDFeInfo): string;
var
  LArquivo: TFileStream;
begin
  Result := IncludeTrailingPathDelimiter(FPasta) + AInfo.NomeDeArquivo;
  LArquivo := TFileStream.Create(Result, fmCreate);
  try
    if Length(ABody) > 0 then
      LArquivo.WriteBuffer(ABody[0], Length(ABody));
  finally
    LArquivo.Free;
  end;
end;

// Roda numa thread do POOL da lib, uma mensagem por vez por callback (varios
// callbacks podem rodar juntos). Nada de tocar a UI daqui: so' marshal.
procedure TfrmConsumidor.OnDocumento(AChannel: TAMQPChannel; const ADelivery: TAMQPDelivery);
var
  LMarshal: TDocMarshal;
begin
  LMarshal := TDocMarshal.Create;
  LMarshal.Form := Self;
  LMarshal.RoutingKey := ADelivery.RoutingKey;
  LMarshal.Xml := ADelivery.BodyAsText;      // UTF-8 -> texto nativo
  LMarshal.Info := LerXml(LMarshal.Xml);
  LMarshal.Redelivered := ADelivery.Redelivered;

  // PROCESSAR: e' aqui que o seu sistema gravaria no banco. So' depois vem o Ack.
  if FSalvar and LMarshal.Info.Legivel then
  begin
    try
      LMarshal.Arquivo := SalvarXml(ADelivery.Body, LMarshal.Info);
    except
      on E: Exception do
      begin
        // Sem Ack e sem Nack: a mensagem fica pendente e o broker a devolve
        // quando este canal fechar (Parar consumo). Um Nack com requeue voltaria
        // na hora e giraria em laco enquanto o disco estiver com problema.
        QueueLog('FALHA ao salvar ' + LMarshal.Info.NomeDeArquivo + ': ' + E.Message +
          ' -- nao confirmada; volta para a fila quando o consumo parar.');
        LMarshal.Free;
        Exit;
      end;
    end;
  end;

  TThread.Queue(nil, LMarshal.Execute);
  // Confirma DEPOIS de processar: se o processo cair antes desta linha, o
  // broker entrega de novo (e a deduplicacao pela chave absorve a repeticao).
  AChannel.Ack(ADelivery.DeliveryTag);
end;

procedure TfrmConsumidor.DocumentoRecebido(const ARoutingKey, AXml, AArquivo: string;
  const AInfo: TDFeInfo; ARedelivered: Boolean);
var
  LDoc: TDocItem;
  LItem: TListItem;
  LAtBottom: Boolean;
  LSituacao: string;
  LRk: TDFeRoutingKey;
begin
  Inc(FRecebidas);
  LRk := LerRoutingKey(ARoutingKey);

  if not AInfo.Legivel then
  begin
    // Igual ao consumir.py: XML ilegivel e' confirmado e descartado (reenviar
    // nao o consertaria).
    Inc(FIlegiveis);
    LSituacao := 'ILEGIVEL';
  end
  else if FVistas.IndexOf(AInfo.ChaveDeDedup) >= 0 then
  begin
    Inc(FRepetidas);
    LSituacao := 'REPETIDO';
  end
  else
  begin
    FVistas.Add(AInfo.ChaveDeDedup);
    Inc(FNovas);
    LSituacao := 'novo';
  end;
  if ARedelivered then
    LSituacao := LSituacao + ' (redelivered)';
  if AArquivo <> '' then
    Inc(FSalvas);
  AtualizarContadores;

  LDoc := TDocItem.Create;
  LDoc.Xml := AXml;
  LDoc.Info := AInfo;
  FDocs.Add(LDoc);

  LAtBottom := ScrollAtBottom(lvDocs.Handle);
  LItem := lvDocs.Items.Add;
  LItem.Caption := FormatDateTime('hh:nn:ss', Now);
  LItem.SubItems.Add(LSituacao);
  LItem.SubItems.Add(ARoutingKey);
  LItem.SubItems.Add(AInfo.TipoXml);
  LItem.SubItems.Add(AInfo.Chave);
  if LRk.Valida then
    LItem.SubItems.Add('uf=' + LRk.UF + ' cnpj=' + LRk.Cnpj + '  ' + AInfo.Resumo)
  else
    LItem.SubItems.Add(AInfo.Resumo);
  LItem.Data := LDoc;
  if LAtBottom then
    LItem.MakeVisible(False);

  // Sem teto a lista cresceria para sempre. Tira a linha mais antiga e o XML dela.
  while lvDocs.Items.Count > MAX_LINHAS do
  begin
    lvDocs.Items[0].Delete;
    FDocs.Delete(0); // TObjectList dono: libera o TDocItem
  end;
end;

procedure TfrmConsumidor.lvDocsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
var
  LDoc: TDocItem;
begin
  if (not Selected) or (Item = nil) or (Item.Data = nil) then
    Exit;
  LDoc := TDocItem(Item.Data);
  // O XML chega numa linha so'; quebra entre as tags so' para ler.
  mmoXml.Text := StringReplace(LDoc.Xml, '><', '>' + #13#10 + '<', [rfReplaceAll]);
  // Deixa a chave pronta para manifestar.
  if LDoc.Info.Chave <> '' then
    edtChave.Text := LDoc.Info.Chave;
end;

{ --- manifestacao -------------------------------------------------------------- }

procedure TfrmConsumidor.btnManifestarClick(Sender: TObject);
var
  LCorpo, LErro: string;
  LProps: TAMQPBasicProperties;
begin
  if not Assigned(FCanalPub) then
    Exit;
  LCorpo := MontarComandoManifestacao(edtAlias.Text, Trim(edtChave.Text),
    cboTipo.Text, edtJustificativa.Text, LErro);
  if LCorpo = '' then
  begin
    Log(LErro);
    Exit;
  end;

  LProps := TAMQPBasicProperties.Empty;
  LProps.SetContentType('text/plain');
  LProps.SetPersistent;
  try
    // mandatory=True: se ninguem ligou a fila de comandos (host fora do ar, ou
    // nunca subiu), o broker devolve a mensagem -- vira aviso no log.
    FCanalPub.Publish(DFE_EXCHANGE, DFE_RK_COMANDO_MANIFESTACAO, AmqpUtf8Encode(LCorpo), LProps, True);
    Log(Format('Comando "%s" enviado para %s. O host valida, fala com a SEFAZ no proximo ' +
      'tick e o resultado volta como evento (nfe.evento.<tipo>.<uf>.<cnpj>).',
      [cboTipo.Text, DFE_RK_COMANDO_MANIFESTACAO]));
  except
    on E: Exception do
      Log('Erro ao publicar o comando: ' + E.Message);
  end;
end;

procedure TfrmConsumidor.OnDevolvida(AChannel: TAMQPChannel; const AReturned: TAMQPReturnedMessage);
var
  LMarshal: TDevolvidoMarshal;
begin
  LMarshal := TDevolvidoMarshal.Create;
  LMarshal.Form := Self;
  LMarshal.RoutingKey := AReturned.RoutingKey;
  TThread.Queue(nil, LMarshal.Execute);
end;

procedure TfrmConsumidor.ComandoDevolvido(const ARoutingKey: string);
begin
  Log('Comando DEVOLVIDO pelo broker (' + ARoutingKey + '): nenhuma fila esta ligada a ' +
    'ele -- o host do pascal-dfe-broker nao esta rodando neste broker.');
end;

end.
