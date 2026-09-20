unit DFe.Simulador.Servidor;

{$I dfe.inc}

{ O simulador da SEFAZ visto de FORA, como um servidor HTTP -- sem o HTTP.

  TDFeSimuladorServidor recebe (metodo, caminho, cabecalhos, corpo) e devolve
  (status, content-type, corpo): e' a funcao pura que a casca HTTP (o Horse, em
  simulador/) so' liga a uma rota. Assim toda a logica do servidor e' testavel
  sem rede e a casca pode trocar (docs/simulador-standalone.md).

  - Thread-safe: uma trava serializa o nucleo (TDFeSimuladorSefaz nao e').
  - Texto: pela rede vai UTF-8; o adaptador SOAP trabalha na convencao do ACBr
    (DFe.XmlTexto). O corpo que chega e' texto NATIVO -> TextoParaAcbr antes do
    adaptador, TextoDoAcbr na resposta. E' o espelho exato de
    DFe.Transmissor.Http, do lado de la'.
  - Falha "sem resposta" do adaptador (timeout simulado) vira HTTP 504 sem
    corpo: para o client do broker (que so' ve o HTTP) o desfecho e' o mesmo
    do timeout em processo -- EDFeComunicacaoFalhou.
  - Rotas: GET /ping ou /health; POST em um caminho que contenha
    'NFeDistribuicaoDFe' ou 'NFeRecepcaoEvento4' (o mesmo criterio do adaptador,
    ver DFe.Simulador.Soap); /admin/* e' a API admin (DFe.Simulador.Admin); o
    resto e' 404. }

interface

uses
  SysUtils, SyncObjs,
  DFe.Transmissor,
  DFe.Simulador,
  DFe.Simulador.Soap,
  DFe.Simulador.Relogio,
  DFe.Simulador.Admin;

const
  DFE_SIM_CONTENT_TYPE_SOAP = 'application/soap+xml; charset=utf-8';

type
  { Definido em DFe.Simulador.Admin (a API admin devolve o mesmo tipo). }
  TDFeSimHttpResposta = DFe.Simulador.Admin.TDFeSimHttpResposta;

  TDFeSimuladorServidor = class
  private
    FSimulador: TDFeSimuladorSefaz;
    FTransmissor: TDFeSimuladorTransmissor;
    FTransmissorIntf: IDFeTransmissor; // dono do ciclo de vida do transmissor
    FLock: TCriticalSection;
    FAdmin: TDFeSimuladorAdmin;
    function GetEstrito: Boolean;
    procedure SetEstrito(const AValor: Boolean);
    function Resposta(const AStatus: Integer; const AContentType, ACorpo: string): TDFeSimHttpResposta;
  public
    { O simulador NAO e' possuido (mesma regra de DFe.Simulador.Soap): quem o
      criou o libera, DEPOIS do servidor. }
    { ARelogio (opcional, tambem NAO possuido): habilita as rotas /admin/relogio; o
      nucleo deve ter sido criado com ARelogio.Agora para o avanco valer. }
    constructor Create(const ASimulador: TDFeSimuladorSefaz;
      const ARelogio: TDFeRelogioVirtual = nil);
    destructor Destroy; override;

    { ACaminho: so' o caminho (sem esquema/host); ASoapAction e AContentType:
      valores dos cabecalhos SOAPAction e Content-Type ('' se ausentes). }
    function Tratar(const AMetodo, ACaminho, ASoapAction, AContentType,
      ACorpo: string): TDFeSimHttpResposta;

    { Violacoes do adaptador SOAP ate' agora (thread-safe); '' = nenhuma. }
    function Violacoes: string;
    function Requisicoes: Integer;
    { O ultimo envelope que o simulador RECEBEU, ja' na convencao de texto NATIVO
      (o que a rede levou). Serve a testes que provam o que chegou (ex.: acento). }
    function UltimoEnvelope: string;
    { Modo do adaptador SOAP: False (padrao) = leniente; True = estrito (recusa com
      HTTP 400 a requisicao com violacao, sem tocar o estado). Ver DFe.Simulador.Soap. }
    property Estrito: Boolean read GetEstrito write SetEstrito;
  end;

implementation

uses
  DFe.XmlTexto;

constructor TDFeSimuladorServidor.Create(const ASimulador: TDFeSimuladorSefaz;
  const ARelogio: TDFeRelogioVirtual);
begin
  inherited Create;
  FSimulador := ASimulador;
  FLock := TCriticalSection.Create;
  FTransmissor := TDFeSimuladorTransmissor.Create(FSimulador);
  FTransmissorIntf := FTransmissor;
  FAdmin := TDFeSimuladorAdmin.Create(FSimulador, FTransmissor, ARelogio);
end;

destructor TDFeSimuladorServidor.Destroy;
begin
  FAdmin.Free;
  FTransmissorIntf := nil; // libera o transmissor
  FTransmissor := nil;
  FLock.Free;
  inherited Destroy;
end;

function TDFeSimuladorServidor.Resposta(const AStatus: Integer;
  const AContentType, ACorpo: string): TDFeSimHttpResposta;
begin
  Result.Status := AStatus;
  Result.ContentType := AContentType;
  Result.Corpo := ACorpo;
end;

function TDFeSimuladorServidor.Tratar(const AMetodo, ACaminho, ASoapAction,
  AContentType, ACorpo: string): TDFeSimHttpResposta;
var
  LSoap: TDFeRespostaTransmissao;
  LContentType: string;
begin
  if SameText(ACaminho, '/ping') or SameText(ACaminho, '/health') then
  begin
    if SameText(AMetodo, 'GET') then
      Result := Resposta(200, 'text/plain; charset=utf-8', 'ok')
    else
      Result := Resposta(405, 'text/plain; charset=utf-8', 'metodo nao permitido');
    Exit;
  end;

  if Copy(LowerCase(ACaminho), 1, Length(CAMINHO_ADMIN)) = CAMINHO_ADMIN then
  begin
    FLock.Enter;
    try
      Result := FAdmin.Tratar(AMetodo, ACaminho, ACorpo);
    finally
      FLock.Leave;
    end;
    Exit;
  end;

  if (Pos('NFeDistribuicaoDFe', ACaminho) = 0) and (Pos('NFeRecepcaoEvento4', ACaminho) = 0) then
  begin
    Result := Resposta(404, 'text/plain; charset=utf-8', 'caminho desconhecido: ' + ACaminho);
    Exit;
  end;

  if not SameText(AMetodo, 'POST') then
  begin
    Result := Resposta(405, 'text/plain; charset=utf-8', 'metodo nao permitido');
    Exit;
  end;

  LContentType := AContentType;
  if LContentType = '' then
    LContentType := DFE_SIM_CONTENT_TYPE_SOAP;

  FLock.Enter;
  try
    LSoap := FTransmissorIntf.Transmitir(TextoParaAcbr(ACorpo), ACaminho, ASoapAction, AContentType);
  finally
    FLock.Leave;
  end;

  if LSoap.InternalErrorCode <> 0 then
    Result := Resposta(504, 'text/plain; charset=utf-8', '') // sem resposta (timeout simulado)
  else
    Result := Resposta(LSoap.HTTPResultCode, LContentType, TextoDoAcbr(LSoap.Texto));
end;

function TDFeSimuladorServidor.Violacoes: string;
begin
  FLock.Enter;
  try
    Result := FTransmissor.TodasViolacoes;
  finally
    FLock.Leave;
  end;
end;

function TDFeSimuladorServidor.UltimoEnvelope: string;
begin
  FLock.Enter;
  try
    Result := TextoDoAcbr(FTransmissor.UltimoEnvelope);
  finally
    FLock.Leave;
  end;
end;

function TDFeSimuladorServidor.GetEstrito: Boolean;
begin
  FLock.Enter;
  try
    Result := FTransmissor.Estrito;
  finally
    FLock.Leave;
  end;
end;

procedure TDFeSimuladorServidor.SetEstrito(const AValor: Boolean);
begin
  FLock.Enter;
  try
    FTransmissor.Estrito := AValor;
  finally
    FLock.Leave;
  end;
end;

function TDFeSimuladorServidor.Requisicoes: Integer;
begin
  FLock.Enter;
  try
    Result := FTransmissor.Requisicoes;
  finally
    FLock.Leave;
  end;
end;

end.
