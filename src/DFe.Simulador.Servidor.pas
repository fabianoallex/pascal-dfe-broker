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
    ver DFe.Simulador.Soap); /admin/* e' a API admin (DFe.Simulador.Admin, mais
    /admin/regras, daqui); /ext/* e' das regras do usuario
    (DFe.Simulador.Regras); o resto e' 404.
  - Regras (extensao em Pascal): AdicionarRegra/AdicionarRegrasRegistradas. Os
    ganchos rodam sob a mesma trava do nucleo. Ver DFe.Simulador.Regras. }

interface

uses
  SysUtils, SyncObjs,
  DFe.Transmissor,
  DFe.Simulador,
  DFe.Simulador.Soap,
  DFe.Simulador.Relogio,
  DFe.Simulador.Admin,
  DFe.Simulador.Regras;

const
  { Definido em DFe.Simulador.Regras (as regras respondem SOAP com o mesmo tipo). }
  DFE_SIM_CONTENT_TYPE_SOAP = DFe.Simulador.Regras.DFE_SIM_CONTENT_TYPE_SOAP;

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
    FRegras: array of TDFeSimuladorRegra; // possuidas
    function GetEstrito: Boolean;
    procedure SetEstrito(const AValor: Boolean);
    function Resposta(const AStatus: Integer; const AContentType, ACorpo: string): TDFeSimHttpResposta;
    function RequisicaoDe(const AServico: TDFeSimServico; const AMetodo, ACaminho,
      ASoapAction, AContentType, ACorpo: string): TDFeSimRequisicao;
    function CaminhoLimpo(const ACaminho: string): string;
    function JsonDasRegras: string;
    function TratarRegras(const AMetodo, ACorpo: string): TDFeSimHttpResposta;
    function TratarExtensao(const AMetodo, ACaminho, ACorpo: string): TDFeSimHttpResposta;
    function TratarSoap(const AServico: TDFeSimServico; const AMetodo, ACaminho,
      ASoapAction, AContentType, ACorpo: string): TDFeSimHttpResposta;
    function TratarAdmin(const AMetodo, ACaminho, ACorpo: string): TDFeSimHttpResposta;
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

    { Extensao (DFe.Simulador.Regras). O servidor PASSA A POSSUIR a regra (libera
      no destrutor). Nome repetido levanta excecao e a regra NAO e' adotada
      (quem chamou continua dono dela). }
    procedure AdicionarRegra(const ARegra: TDFeSimuladorRegra);
    { Instancia e adota todas as regras registradas por initialization
      (RegistrarRegraSimulador); sem nenhuma registrada, nao faz nada. }
    procedure AdicionarRegrasRegistradas;
    function Regras: Integer;
    function Regra(const AIndice: Integer): TDFeSimuladorRegra;

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
  DFe.XmlTexto,
  DFe.Simulador.Json;

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
var
  I: Integer;
begin
  for I := 0 to High(FRegras) do
    FRegras[I].Free;
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

function TDFeSimuladorServidor.CaminhoLimpo(const ACaminho: string): string;
var
  I: Integer;
begin
  Result := LowerCase(ACaminho);
  I := Pos('?', Result);
  if I > 0 then
    Result := Copy(Result, 1, I - 1);
  while (Length(Result) > 1) and (Result[Length(Result)] = '/') do
    Delete(Result, Length(Result), 1);
end;

function TDFeSimuladorServidor.RequisicaoDe(const AServico: TDFeSimServico; const AMetodo,
  ACaminho, ASoapAction, AContentType, ACorpo: string): TDFeSimRequisicao;
begin
  Result.Servico := AServico;
  Result.Metodo := AMetodo;
  Result.Caminho := ACaminho;
  Result.SoapAction := ASoapAction;
  Result.ContentType := AContentType;
  Result.Corpo := ACorpo;
  Result.Agora := FSimulador.AgoraSimulado;
end;

{ ---- regras ---- }

procedure TDFeSimuladorServidor.AdicionarRegra(const ARegra: TDFeSimuladorRegra);
var
  I: Integer;
begin
  FLock.Enter;
  try
    for I := 0 to High(FRegras) do
      if SameText(FRegras[I].Nome, ARegra.Nome) then
        raise Exception.Create('Ja existe uma regra "' + ARegra.Nome + '" neste simulador');
    ARegra.Anexar(FSimulador);
    SetLength(FRegras, Length(FRegras) + 1);
    FRegras[High(FRegras)] := ARegra;
  finally
    FLock.Leave;
  end;
end;

procedure TDFeSimuladorServidor.AdicionarRegrasRegistradas;
var
  LClasses: TDFeSimuladorRegraClasseArray;
  LRegra: TDFeSimuladorRegra;
  I: Integer;
begin
  LClasses := RegrasSimuladorRegistradas;
  for I := 0 to High(LClasses) do
  begin
    LRegra := LClasses[I].Create;
    try
      AdicionarRegra(LRegra);
    except
      LRegra.Free;
      raise;
    end;
  end;
end;

function TDFeSimuladorServidor.Regras: Integer;
begin
  Result := Length(FRegras);
end;

function TDFeSimuladorServidor.Regra(const AIndice: Integer): TDFeSimuladorRegra;
begin
  Result := FRegras[AIndice];
end;

function TDFeSimuladorServidor.JsonDasRegras: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(FRegras) do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + '{"nome":' + JsonTexto(FRegras[I].Nome) +
      ',"descricao":' + JsonTexto(FRegras[I].Descricao) +
      ',"ativa":' + LowerCase(BoolToStr(FRegras[I].Ativa, True)) + '}';
  end;
  Result := '{"regras":[' + Result + ']}';
end;

(* GET /admin/regras lista; POST {"nome":"x","ativa":true|false} liga/desliga. *)
function TDFeSimuladorServidor.TratarRegras(const AMetodo, ACorpo: string): TDFeSimHttpResposta;
var
  LJson: TDFeJsonPlano;
  LErro, LNome: string;
  I: Integer;
begin
  if SameText(AMetodo, 'GET') then
  begin
    Result := RespostaJson(200, JsonDasRegras);
    Exit;
  end;
  if not SameText(AMetodo, 'POST') then
  begin
    Result := RespostaJson(405, '{"erro":"metodo nao permitido para esta rota"}');
    Exit;
  end;
  if not LerJsonPlano(ACorpo, LJson, LErro) then
  begin
    Result := RespostaJson(400, '{"erro":' + JsonTexto('JSON invalido: ' + LErro) + '}');
    Exit;
  end;
  try
    LNome := Trim(LJson.Texto('nome'));
    if (LNome = '') or not LJson.Tem('ativa') then
    begin
      Result := RespostaJson(400, '{"erro":' +
        JsonTexto('informe "nome" e "ativa" (true ou false)') + '}');
      Exit;
    end;
    for I := 0 to High(FRegras) do
      if SameText(FRegras[I].Nome, LNome) then
      begin
        FRegras[I].Ativa := LJson.Booleano('ativa', True);
        Result := RespostaJson(200, JsonDasRegras);
        Exit;
      end;
    Result := RespostaJson(404, '{"erro":' + JsonTexto('regra desconhecida: ' + LNome) + '}');
  finally
    LJson.Free;
  end;
end;

function TDFeSimuladorServidor.TratarExtensao(const AMetodo, ACaminho,
  ACorpo: string): TDFeSimHttpResposta;
var
  LReq: TDFeSimRequisicao;
  I: Integer;
begin
  LReq := RequisicaoDe(ssExtensao, AMetodo, ACaminho, '', '', ACorpo);
  for I := 0 to High(FRegras) do
    if FRegras[I].Ativa and FRegras[I].TratarRota(LReq, Result) then
      Exit;
  Result := Resposta(404, 'text/plain; charset=utf-8', 'rota de extensao desconhecida: ' + ACaminho);
end;

function TDFeSimuladorServidor.TratarAdmin(const AMetodo, ACaminho,
  ACorpo: string): TDFeSimHttpResposta;
var
  LLimpo: string;
  I: Integer;
begin
  LLimpo := CaminhoLimpo(ACaminho);
  if LLimpo = '/admin/regras' then
  begin
    Result := TratarRegras(AMetodo, ACorpo);
    Exit;
  end;
  Result := FAdmin.Tratar(AMetodo, ACaminho, ACorpo);
  if (LLimpo = '/admin/zerar') and SameText(AMetodo, 'POST') and (Result.Status = 200) then
    for I := 0 to High(FRegras) do
      FRegras[I].AoZerar;
end;

function TDFeSimuladorServidor.TratarSoap(const AServico: TDFeSimServico; const AMetodo,
  ACaminho, ASoapAction, AContentType, ACorpo: string): TDFeSimHttpResposta;
var
  LSoap: TDFeRespostaTransmissao;
  LContentType: string;
  LReq: TDFeSimRequisicao;
  I: Integer;
begin
  LContentType := AContentType;
  if LContentType = '' then
    LContentType := DFE_SIM_CONTENT_TYPE_SOAP;

  LReq := RequisicaoDe(AServico, AMetodo, ACaminho, ASoapAction, AContentType, ACorpo);
  Result := Resposta(0, '', '');
  for I := 0 to High(FRegras) do
    if FRegras[I].Ativa and FRegras[I].AntesDeAtender(LReq, Result) then
      Exit; // a regra respondeu: o nucleo nao e' tocado

  LSoap := FTransmissorIntf.Transmitir(TextoParaAcbr(ACorpo), ACaminho, ASoapAction, AContentType);
  if LSoap.InternalErrorCode <> 0 then
    Result := Resposta(504, 'text/plain; charset=utf-8', '') // sem resposta (timeout simulado)
  else
    Result := Resposta(LSoap.HTTPResultCode, LContentType, TextoDoAcbr(LSoap.Texto));

  for I := 0 to High(FRegras) do
    if FRegras[I].Ativa then
      FRegras[I].DepoisDeAtender(LReq, Result);
end;

function TDFeSimuladorServidor.Tratar(const AMetodo, ACaminho, ASoapAction,
  AContentType, ACorpo: string): TDFeSimHttpResposta;
var
  LMinusculo: string;
begin
  if SameText(ACaminho, '/ping') or SameText(ACaminho, '/health') then
  begin
    if SameText(AMetodo, 'GET') then
      Result := Resposta(200, 'text/plain; charset=utf-8', 'ok')
    else
      Result := Resposta(405, 'text/plain; charset=utf-8', 'metodo nao permitido');
    Exit;
  end;

  LMinusculo := LowerCase(ACaminho);

  if Copy(LMinusculo, 1, Length(CAMINHO_ADMIN)) = CAMINHO_ADMIN then
  begin
    FLock.Enter;
    try
      Result := TratarAdmin(AMetodo, ACaminho, ACorpo);
    finally
      FLock.Leave;
    end;
    Exit;
  end;

  if Copy(LMinusculo, 1, Length(CAMINHO_EXTENSAO)) = CAMINHO_EXTENSAO then
  begin
    FLock.Enter;
    try
      Result := TratarExtensao(AMetodo, ACaminho, ACorpo);
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

  FLock.Enter;
  try
    if Pos('NFeDistribuicaoDFe', ACaminho) > 0 then
      Result := TratarSoap(ssDistribuicao, AMetodo, ACaminho, ASoapAction, AContentType, ACorpo)
    else
      Result := TratarSoap(ssEvento, AMetodo, ACaminho, ASoapAction, AContentType, ACorpo);
  finally
    FLock.Leave;
  end;
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
