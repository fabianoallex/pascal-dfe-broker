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
    ver DFe.Simulador.Soap); o resto e' 404. }

interface

uses
  SysUtils, SyncObjs,
  DFe.Transmissor,
  DFe.Simulador,
  DFe.Simulador.Soap;

const
  DFE_SIM_CONTENT_TYPE_SOAP = 'application/soap+xml; charset=utf-8';

type
  TDFeSimHttpResposta = record
    Status: Integer;
    ContentType: string;
    Corpo: string; // texto NATIVO (a casca codifica em UTF-8)
  end;

  TDFeSimuladorServidor = class
  private
    FSimulador: TDFeSimuladorSefaz;
    FTransmissor: TDFeSimuladorTransmissor;
    FTransmissorIntf: IDFeTransmissor; // dono do ciclo de vida do transmissor
    FLock: TCriticalSection;
    function Resposta(const AStatus: Integer; const AContentType, ACorpo: string): TDFeSimHttpResposta;
  public
    { O simulador NAO e' possuido (mesma regra de DFe.Simulador.Soap): quem o
      criou o libera, DEPOIS do servidor. }
    constructor Create(const ASimulador: TDFeSimuladorSefaz);
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
  end;

implementation

uses
  DFe.XmlTexto;

constructor TDFeSimuladorServidor.Create(const ASimulador: TDFeSimuladorSefaz);
begin
  inherited Create;
  FSimulador := ASimulador;
  FLock := TCriticalSection.Create;
  FTransmissor := TDFeSimuladorTransmissor.Create(FSimulador);
  FTransmissorIntf := FTransmissor;
end;

destructor TDFeSimuladorServidor.Destroy;
begin
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
