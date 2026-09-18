unit DFe.TestDoubles;

{$mode delphi}{$H+}

interface

uses
  SysUtils,
  DFe.Types,
  DFe.Errors,
  DFe.Provider,
  DFe.Publicador,
  DFe.Orquestrador,
  DFe.Host.Loop,
  DFe.Config,
  DFe.Manifestacao;

{ Helpers de fixture, compartilhados entre os arquivos de teste que
  precisam de um TDFeCertificado/TDFeLoteBruto/TDFeEventoNormalizado
  minimo e valido -- centralizados aqui para nao duplicar entre
  DFe.OrquestradorTests e DFe.HostLoopTests. }
function CertificadoTeste: TDFeCertificado;
function LoteTeste(const ACStat: Integer; const AUltimoNSU, AMaxNSU: Int64): TDFeLoteBruto;
function EventoTeste: TDFeEventoNormalizado;

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
    FExcecaoADecodificar: ExceptClass;
  public
    constructor Create(const AIdentificador: string; const ACodigoConsumoIndevido: Integer = 656);
    function Identificador: string;
    function CodigoConsumoIndevido: Integer;
    function Decodificar(const ALote: TDFeLoteBruto; const ACertificado: TDFeCertificado): TDFeEventoNormalizadoArray;
    { Quando atribuida, Decodificar levanta esta excecao (depois de guardar o lote). }
    property ExcecaoADecodificar: ExceptClass read FExcecaoADecodificar write FExcecaoADecodificar;
    property EventosADevolver: TDFeEventoNormalizadoArray read FEventosADevolver write FEventosADevolver;
    property UltimoLoteRecebido: TDFeLoteBruto read FUltimoLoteRecebido;
  end;

  { Client fake que TAMBEM implementa IDFeManifestador -- ao contrario de
    TDFeDistribuicaoClientFake (que representa "client sem suporte a
    manifestacao", caso testado via Supports devolvendo False).
    EnviarEvento devolve EventoADevolver ou levanta ExcecaoAEnviar (classe
    de excecao de DFe.Errors), com um unico slot -- nenhum teste ate agora
    precisou de sequencia. Consultar nao e' usado pelos testes de
    manifestacao. }
  TDFeClientManifestadorFake = class(TInterfacedObject, IDFeDistribuicaoClient, IDFeManifestador)
  private
    FEventoADevolver: TDFeEventoNormalizado;
    FExcecaoAEnviar: ExceptClass;
    FUltimoComandoRecebido: TDFeComandoManifestacao;
    FChamadasEnviarEvento: Integer;
  public
    function Consultar(const ACertificado: TDFeCertificado; const AUltimoNSU: Int64): TDFeLoteBruto;
    function EnviarEvento(const ACertificado: TDFeCertificado; const AComando: TDFeComandoManifestacao): TDFeEventoNormalizado;
    property EventoADevolver: TDFeEventoNormalizado read FEventoADevolver write FEventoADevolver;
    property ExcecaoAEnviar: ExceptClass read FExcecaoAEnviar write FExcecaoAEnviar;
    property UltimoComandoRecebido: TDFeComandoManifestacao read FUltimoComandoRecebido;
    property ChamadasEnviarEvento: Integer read FChamadasEnviarEvento;
  end;

  { Fonte de comando fake: fila FIFO pre-carregada, sem broker nenhum. }
  TDFeComandoFonteFake = class(TInterfacedObject, IDFeComandoFonte)
  private
    FComandos: array of TDFeComandoManifestacao;
    FIndiceProximo: Integer;
  public
    procedure AdicionarComando(const AComando: TDFeComandoManifestacao);
    function ObterProximoComando(out AComando: TDFeComandoManifestacao): Boolean;
  end;

  { Subclasse de teste de TDFeManifestacaoProcessador: captura o que
    RegistrarErro receberia, mesmo padrao de TDFeOrquestradorTestavel. }
  TDFeManifestacaoProcessadorTestavel = class(TDFeManifestacaoProcessador)
  private
    FErros: array of string;
  protected
    procedure RegistrarErro(const AComando: TDFeComandoManifestacao; const AMensagem: string); override;
  public
    function QuantidadeErros: Integer;
    function UltimoErro: string;
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

  { Subclasse de teste de TDFeHostLoop: Esperar vira no-op (Executar nao
    depende de tempo real nenhum) e Tick conta quantas vezes rodou,
    podendo se auto-parar apos N chamadas -- pra testar o loop e a parada
    de forma deterministica. }
  TDFeHostLoopTestavel = class(TDFeHostLoop)
  private
    FTicks: Integer;
    FPararAposTicks: Integer;
  protected
    procedure Esperar(const AMilissegundos: Integer); override;
  public
    procedure Tick; override;
    property Ticks: Integer read FTicks;
    property PararAposTicks: Integer read FPararAposTicks write FPararAposTicks;
  end;

  { Fabrica fake de IDFeDistribuicaoClient (ver DFe.Config.TDFeClientFactory)
    -- devolve um TDFeDistribuicaoClientFake novo a cada chamada e conta
    quantas vezes foi chamada, pra teste verificar que MontarUnidades
    chamou a fabrica uma vez por certificado. }
  TDFeClientFactoryFake = class
  private
    FChamadas: Integer;
  public
    function Fabricar(const ACertificado: TDFeConfigCertificado): IDFeDistribuicaoClient;
    property Chamadas: Integer read FChamadas;
  end;

  { Subclasse de teste de TDFeConfigWatcher: ObterDataModificacao vira
    controlavel (sem depender do mtime real de um arquivo -- mesmo padrao
    de Agora/Esperar) e Recarregar conta quantas vezes rodou de verdade,
    pra teste distinguir "recarregou" de "nao recarregou" sem depender do
    numero de chamadas da fabrica de client (que so' e' chamada para
    alias novo, nao para um alias ja existente sendo apenas sincronizado). }
  TDFeConfigWatcherTestavel = class(TDFeConfigWatcher)
  private
    FDataSimulada: TDateTime;
    FRecargas: Integer;
  protected
    function ObterDataModificacao: TDateTime; override;
  public
    procedure Recarregar; override;
    property DataSimulada: TDateTime read FDataSimulada write FDataSimulada;
    property Recargas: Integer read FRecargas;
  end;

implementation

function CertificadoTeste: TDFeCertificado;
begin
  Result.Identificador := 'teste';
  Result.CnpjCpf := '12345678000199';
  Result.UF := 'RS';
end;

function LoteTeste(const ACStat: Integer; const AUltimoNSU, AMaxNSU: Int64): TDFeLoteBruto;
begin
  Result.CStat := ACStat;
  Result.XMotivo := '';
  Result.UltimoNSU := AUltimoNSU;
  Result.MaxNSU := AMaxNSU;
  Result.Itens := nil;
end;

function EventoTeste: TDFeEventoNormalizado;
begin
  Result.TipoDocumento := 'nfe';
  Result.Categoria := dcDocumento;
  Result.TipoEvento := '';
  Result.ChaveAcesso := '';
  Result.CnpjCpfConsultante := '12345678000199';
  Result.UF := 'RS';
  Result.NSU := 0;
  Result.XmlPayload := '<xml/>';
  Result.DataEmissao := 0;
end;

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
  if Assigned(FExcecaoADecodificar) then
    raise FExcecaoADecodificar.Create('Falha simulada por TDFeProviderFake.Decodificar');
  Result := FEventosADevolver;
end;

{ TDFeClientManifestadorFake }

function TDFeClientManifestadorFake.Consultar(const ACertificado: TDFeCertificado; const AUltimoNSU: Int64): TDFeLoteBruto;
begin
  Result := LoteTeste(137, AUltimoNSU, AUltimoNSU);
end;

function TDFeClientManifestadorFake.EnviarEvento(const ACertificado: TDFeCertificado; const AComando: TDFeComandoManifestacao): TDFeEventoNormalizado;
begin
  Inc(FChamadasEnviarEvento);
  FUltimoComandoRecebido := AComando;
  if Assigned(FExcecaoAEnviar) then
    raise FExcecaoAEnviar.Create('Falha simulada por TDFeClientManifestadorFake');
  Result := FEventoADevolver;
end;

{ TDFeComandoFonteFake }

procedure TDFeComandoFonteFake.AdicionarComando(const AComando: TDFeComandoManifestacao);
var
  LIndice: Integer;
begin
  LIndice := Length(FComandos);
  SetLength(FComandos, LIndice + 1);
  FComandos[LIndice] := AComando;
end;

function TDFeComandoFonteFake.ObterProximoComando(out AComando: TDFeComandoManifestacao): Boolean;
begin
  if FIndiceProximo > High(FComandos) then
  begin
    Result := False;
    Exit;
  end;
  AComando := FComandos[FIndiceProximo];
  Inc(FIndiceProximo);
  Result := True;
end;

{ TDFeManifestacaoProcessadorTestavel }

procedure TDFeManifestacaoProcessadorTestavel.RegistrarErro(const AComando: TDFeComandoManifestacao; const AMensagem: string);
var
  LIndice: Integer;
begin
  LIndice := Length(FErros);
  SetLength(FErros, LIndice + 1);
  FErros[LIndice] := AMensagem;
end;

function TDFeManifestacaoProcessadorTestavel.QuantidadeErros: Integer;
begin
  Result := Length(FErros);
end;

function TDFeManifestacaoProcessadorTestavel.UltimoErro: string;
begin
  if Length(FErros) = 0 then
    Result := ''
  else
    Result := FErros[High(FErros)];
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

{ TDFeHostLoopTestavel }

procedure TDFeHostLoopTestavel.Esperar(const AMilissegundos: Integer);
begin
  // no-op de proposito -- ver comentario da declaracao
end;

procedure TDFeHostLoopTestavel.Tick;
begin
  inherited Tick;
  Inc(FTicks);
  if (FPararAposTicks > 0) and (FTicks >= FPararAposTicks) then
    Parar;
end;

{ TDFeClientFactoryFake }

function TDFeClientFactoryFake.Fabricar(const ACertificado: TDFeConfigCertificado): IDFeDistribuicaoClient;
begin
  Inc(FChamadas);
  Result := TDFeDistribuicaoClientFake.Create;
end;

{ TDFeConfigWatcherTestavel }

function TDFeConfigWatcherTestavel.ObterDataModificacao: TDateTime;
begin
  Result := FDataSimulada;
end;

procedure TDFeConfigWatcherTestavel.Recarregar;
begin
  inherited Recarregar;
  Inc(FRecargas);
end;

end.
