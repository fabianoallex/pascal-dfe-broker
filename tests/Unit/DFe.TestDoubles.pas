unit DFe.TestDoubles;

interface

uses
  SysUtils,
  DFe.Types,
  DFe.Provider,
  DFe.Publicador,
  DFe.Orquestrador;

type
  { Provider fake: Identificador e CodigoConsumoIndevido fixos no
    construtor; Decodificar devolve o que estiver em EventosADevolver
    (vazio por padrao) e guarda o lote recebido, pra teste inspecionar. }
  TDFeProviderFake = class(TInterfacedObject, IDFeProvider)
  private
    FIdentificador: string;
    FCodigoConsumoIndevido: Integer;
    FEventosADevolver: TDFeEventoNormalizadoArray;
    FUltimoLoteRecebido: TDFeLoteBruto;
  public
    constructor Create(const AIdentificador: string; const ACodigoConsumoIndevido: Integer = 656);
    function Identificador: string;
    function CodigoConsumoIndevido: Integer;
    function Decodificar(const ALote: TDFeLoteBruto; const ACertificado: TDFeCertificado): TDFeEventoNormalizadoArray;
    property EventosADevolver: TDFeEventoNormalizadoArray read FEventosADevolver write FEventosADevolver;
    property UltimoLoteRecebido: TDFeLoteBruto read FUltimoLoteRecebido;
  end;

  { Client fake: uma fila de respostas (lote OU classe de excecao a
    levantar), consumida uma por chamada de Consultar, na ordem em que
    foram adicionadas com AdicionarLote/AdicionarExcecao. }
  TDFeDistribuicaoClientFake = class(TInterfacedObject, IDFeDistribuicaoClient)
  private
    FLotes: array of TDFeLoteBruto;
    FExcecoes: array of ExceptClass;
    FIndiceProximo: Integer;
    FUltimoNSURecebido: Int64;
    FChamadas: Integer;
  public
    procedure AdicionarLote(const ALote: TDFeLoteBruto);
    procedure AdicionarExcecao(const AClasse: ExceptClass);
    function Consultar(const ACertificado: TDFeCertificado; const AUltimoNSU: Int64): TDFeLoteBruto;
    property UltimoNSURecebido: Int64 read FUltimoNSURecebido;
    property Chamadas: Integer read FChamadas;
  end;

  { CursorStore fake: dicionario em memoria, sem tocar disco. }
  TDFeCursorStoreFake = class(TInterfacedObject, IDFeCursorStore)
  private
    FNamespaces: array of string;
    FValores: array of Int64;
    function IndiceDe(const ANamespace: string): Integer;
  public
    function ObterUltimoNSU(const ANamespace: string): Int64;
    procedure GravarUltimoNSU(const ANamespace: string; const ANSU: Int64);
  end;

  { Publicador fake: acumula tudo que foi publicado, na ordem. }
  TDFePublicadorFake = class(TInterfacedObject, IDFePublicador)
  private
    FRoutingKeys: array of string;
    FPayloads: array of string;
  public
    procedure Publicar(const ARoutingKey: string; const APayload: string);
    function Quantidade: Integer;
    function RoutingKey(const AIndice: Integer): string;
  end;

  { Subclasse de teste de TDFeOrquestrador: substitui Agora por um relogio
    controlavel (sem depender de Sleep de verdade) e captura o que
    RegistrarAviso/RegistrarErro receberiam, pra teste inspecionar sem
    precisar de log real nenhum. }
  TDFeOrquestradorTestavel = class(TDFeOrquestrador)
  private
    FAgoraSimulado: TDateTime;
    FAvisos: array of string;
    FErros: array of string;
  protected
    function Agora: TDateTime; override;
    procedure RegistrarAviso(const AUnidade: TDFeUnidadeTrabalho; const AMensagem: string); override;
    procedure RegistrarErro(const AUnidade: TDFeUnidadeTrabalho; const AMensagem: string); override;
  public
    property AgoraSimulado: TDateTime read FAgoraSimulado write FAgoraSimulado;
    function QuantidadeAvisos: Integer;
    function QuantidadeErros: Integer;
    function UltimoErro: string;
  end;

implementation

{ TDFeProviderFake }

constructor TDFeProviderFake.Create(const AIdentificador: string; const ACodigoConsumoIndevido: Integer);
begin
  inherited Create;
  FIdentificador := AIdentificador;
  FCodigoConsumoIndevido := ACodigoConsumoIndevido;
end;

function TDFeProviderFake.Identificador: string;
begin
  Result := FIdentificador;
end;

function TDFeProviderFake.CodigoConsumoIndevido: Integer;
begin
  Result := FCodigoConsumoIndevido;
end;

function TDFeProviderFake.Decodificar(const ALote: TDFeLoteBruto; const ACertificado: TDFeCertificado): TDFeEventoNormalizadoArray;
begin
  FUltimoLoteRecebido := ALote;
  Result := FEventosADevolver;
end;

{ TDFeDistribuicaoClientFake }

procedure TDFeDistribuicaoClientFake.AdicionarLote(const ALote: TDFeLoteBruto);
var
  LIndice: Integer;
begin
  LIndice := Length(FLotes);
  SetLength(FLotes, LIndice + 1);
  SetLength(FExcecoes, LIndice + 1);
  FLotes[LIndice] := ALote;
end;

procedure TDFeDistribuicaoClientFake.AdicionarExcecao(const AClasse: ExceptClass);
var
  LIndice: Integer;
begin
  LIndice := Length(FLotes);
  SetLength(FLotes, LIndice + 1); // elemento novo ja vem zerado
  SetLength(FExcecoes, LIndice + 1);
  FExcecoes[LIndice] := AClasse;
end;

function TDFeDistribuicaoClientFake.Consultar(const ACertificado: TDFeCertificado; const AUltimoNSU: Int64): TDFeLoteBruto;
var
  LIndice: Integer;
begin
  Inc(FChamadas);
  FUltimoNSURecebido := AUltimoNSU;
  if FIndiceProximo > High(FLotes) then
    raise Exception.Create('TDFeDistribuicaoClientFake: sem resposta enfileirada para esta chamada');
  LIndice := FIndiceProximo;
  Inc(FIndiceProximo);
  if Assigned(FExcecoes[LIndice]) then
    raise FExcecoes[LIndice].Create('Falha simulada por TDFeDistribuicaoClientFake');
  Result := FLotes[LIndice];
end;

{ TDFeCursorStoreFake }

function TDFeCursorStoreFake.IndiceDe(const ANamespace: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(FNamespaces) do
    if FNamespaces[I] = ANamespace then
    begin
      Result := I;
      Break;
    end;
end;

function TDFeCursorStoreFake.ObterUltimoNSU(const ANamespace: string): Int64;
var
  LIndice: Integer;
begin
  LIndice := IndiceDe(ANamespace);
  if LIndice = -1 then
    Result := 0
  else
    Result := FValores[LIndice];
end;

procedure TDFeCursorStoreFake.GravarUltimoNSU(const ANamespace: string; const ANSU: Int64);
var
  LIndice: Integer;
begin
  LIndice := IndiceDe(ANamespace);
  if LIndice = -1 then
  begin
    LIndice := Length(FNamespaces);
    SetLength(FNamespaces, LIndice + 1);
    SetLength(FValores, LIndice + 1);
    FNamespaces[LIndice] := ANamespace;
  end;
  FValores[LIndice] := ANSU;
end;

{ TDFePublicadorFake }

procedure TDFePublicadorFake.Publicar(const ARoutingKey: string; const APayload: string);
var
  LIndice: Integer;
begin
  LIndice := Length(FRoutingKeys);
  SetLength(FRoutingKeys, LIndice + 1);
  SetLength(FPayloads, LIndice + 1);
  FRoutingKeys[LIndice] := ARoutingKey;
  FPayloads[LIndice] := APayload;
end;

function TDFePublicadorFake.Quantidade: Integer;
begin
  Result := Length(FRoutingKeys);
end;

function TDFePublicadorFake.RoutingKey(const AIndice: Integer): string;
begin
  Result := FRoutingKeys[AIndice];
end;

{ TDFeOrquestradorTestavel }

function TDFeOrquestradorTestavel.Agora: TDateTime;
begin
  Result := FAgoraSimulado;
end;

procedure TDFeOrquestradorTestavel.RegistrarAviso(const AUnidade: TDFeUnidadeTrabalho; const AMensagem: string);
var
  LIndice: Integer;
begin
  LIndice := Length(FAvisos);
  SetLength(FAvisos, LIndice + 1);
  FAvisos[LIndice] := AMensagem;
end;

procedure TDFeOrquestradorTestavel.RegistrarErro(const AUnidade: TDFeUnidadeTrabalho; const AMensagem: string);
var
  LIndice: Integer;
begin
  LIndice := Length(FErros);
  SetLength(FErros, LIndice + 1);
  FErros[LIndice] := AMensagem;
end;

function TDFeOrquestradorTestavel.QuantidadeAvisos: Integer;
begin
  Result := Length(FAvisos);
end;

function TDFeOrquestradorTestavel.QuantidadeErros: Integer;
begin
  Result := Length(FErros);
end;

function TDFeOrquestradorTestavel.UltimoErro: string;
begin
  if Length(FErros) = 0 then
    Result := ''
  else
    Result := FErros[High(FErros)];
end;

end.
