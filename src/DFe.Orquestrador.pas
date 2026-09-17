unit DFe.Orquestrador;

{$I dfe.inc}

{ O core que liga as pontas: consulta -> classifica cStat -> decodifica ->
  publica -> so entao avanca o cursor de NSU. Ver docs/architecture.md,
  "Visao geral do fluxo" e "Persistencia do cursor de NSU".

  Agnostico de modelo de execucao de proposito (ver "Modelo de execucao" em
  docs/architecture.md, ainda em aberto): nao cria thread nem timer nenhum.
  Quem hospeda (console, servico Windows, daemon Linux -- decisao futura)
  chama ExecutarCiclo periodicamente; este unit so decide SE cada unidade de
  trabalho deve rodar agora (via ProximaConsultaEm) e o que fazer com o
  resultado. }

interface

uses
  SysUtils,
  DFe.Types,
  DFe.Errors,
  DFe.Provider,
  DFe.Publicador,
  DFe.RoutingKey;

const
  { 1 hora -- confirmado (nao mais suposicao) contra as NTs oficiais em
    2026-09-17, ver docs/referencias/README.md. E' tambem o intervalo de
    "desbloqueio automatico" apos consumo indevido: a SEFAZ nao escalona o
    bloqueio a cada violacao repetida, entao o orquestrador nao escalona
    tambem -- ver ExecutarUnidade, caso dccConsumoIndevido. }
  DFE_INTERVALO_BASE_SEGUNDOS_PADRAO = 3600;
  { Trava de seguranca contra loop indefinido caso MaxNSU nunca alcance
    UltimoNSU por algum defeito de interpretacao do retorno da SEFAZ. }
  DFE_MAX_LOTES_POR_CICLO = 20;

type
  { Uma combinacao (provider, certificado) habilitada na configuracao, com o
    proprio estado de agendamento -- cada unidade decide sozinha quando
    rodar de novo, porque consumo indevido ou pausa de um certificado nao
    deve afetar os demais. }
  TDFeUnidadeTrabalho = class
  private
    FProvider: IDFeProvider;
    FClient: IDFeDistribuicaoClient;
    FCertificado: TDFeCertificado;
    FCursorStore: IDFeCursorStore;
    FIntervaloBaseSegundos: Integer;
    FProximaConsultaEm: TDateTime;
    FPausada: Boolean;
    FMotivoPausa: string;
  public
    constructor Create(const AProvider: IDFeProvider;
      const AClient: IDFeDistribuicaoClient;
      const ACertificado: TDFeCertificado;
      const ACursorStore: IDFeCursorStore;
      const AIntervaloBaseSegundos: Integer = DFE_INTERVALO_BASE_SEGUNDOS_PADRAO);

    property Provider: IDFeProvider read FProvider;
    property Client: IDFeDistribuicaoClient read FClient;
    property Certificado: TDFeCertificado read FCertificado;
    property CursorStore: IDFeCursorStore read FCursorStore;
    { Cadencia fixa da unidade -- sem escalonamento (ver comentario de
      DFE_INTERVALO_BASE_SEGUNDOS_PADRAO): tanto o ciclo normal quanto a
      recuperacao apos consumo indevido usam este mesmo intervalo. }
    property IntervaloBaseSegundos: Integer read FIntervaloBaseSegundos;
    property ProximaConsultaEm: TDateTime read FProximaConsultaEm write FProximaConsultaEm;
    property Pausada: Boolean read FPausada write FPausada;
    property MotivoPausa: string read FMotivoPausa write FMotivoPausa;
  end;

  TDFeUnidadeTrabalhoArray = array of TDFeUnidadeTrabalho;

  { Monta a chave de namespace do cursor de NSU: '<tipo>/<cnpjCpf>/<uf>' (ver
    docs/architecture.md, "Persistencia do cursor de NSU"). E' o orquestrador
    quem monta essa chave, nunca o provider -- exportada como funcao pura
    para ser testavel isoladamente. }
  function MontarNamespaceCursor(const ATipoDocumento: string;
    const ACertificado: TDFeCertificado): string;

type
  { Liga uma lista de unidades de trabalho ao publicador. Nao possui thread
    nem timer proprio -- ver comentario de topo do unit. }
  TDFeOrquestrador = class
  private
    FPublicador: IDFePublicador;
    FUnidades: TDFeUnidadeTrabalhoArray;
  protected
    { Relogio injetavel para tornar o agendamento testavel sem Sleep --
      mesmo padrao do NowTick/NowWall do submodulo server do
      pascal-amqp-faa. }
    function Agora: TDateTime; virtual;

    { Hooks de observabilidade -- no-op por padrao. Conectar a um mecanismo
      de log/observabilidade real e' decisao futura (o pascal-amqp-faa tem
      um modelo pronto para isso na Fase 4.1, opt-in e read-only; avaliar
      reuso quando chegar a hora). }
    procedure RegistrarAviso(const AUnidade: TDFeUnidadeTrabalho; const AMensagem: string); virtual;
    procedure RegistrarErro(const AUnidade: TDFeUnidadeTrabalho; const AMensagem: string); virtual;

    { Ponto de extensao para teste/composicao: roda uma unidade de trabalho
      isolada. Publica de ExecutarCiclo, que so itera FUnidades. }
    procedure ExecutarUnidade(const AUnidade: TDFeUnidadeTrabalho); virtual;
  public
    constructor Create(const APublicador: IDFePublicador);
    destructor Destroy; override;

    procedure AdicionarUnidade(const AUnidade: TDFeUnidadeTrabalho);

    { Chamado periodicamente por quem hospeda o orquestrador. Cada unidade
      decide sozinha (via ProximaConsultaEm) se e' a vez dela rodar --
      chamar isto com mais frequencia do que o necessario e' seguro e nao
      gera consultas extras a SEFAZ. }
    procedure ExecutarCiclo;
  end;

implementation

function MontarNamespaceCursor(const ATipoDocumento: string;
  const ACertificado: TDFeCertificado): string;
begin
  Result := LowerCase(ATipoDocumento) + '/' + ACertificado.CnpjCpf + '/' + LowerCase(ACertificado.UF);
end;

function SegundosParaTimeDelta(const ASegundos: Integer): TDateTime;
begin
  Result := ASegundos / SecsPerDay;
end;

{ TDFeUnidadeTrabalho }

constructor TDFeUnidadeTrabalho.Create(const AProvider: IDFeProvider;
  const AClient: IDFeDistribuicaoClient;
  const ACertificado: TDFeCertificado;
  const ACursorStore: IDFeCursorStore;
  const AIntervaloBaseSegundos: Integer);
begin
  inherited Create;
  FProvider := AProvider;
  FClient := AClient;
  FCertificado := ACertificado;
  FCursorStore := ACursorStore;
  FIntervaloBaseSegundos := AIntervaloBaseSegundos;
  FProximaConsultaEm := 0; // 0 = liberada para rodar assim que ExecutarCiclo for chamado
  FPausada := False;
end;

{ TDFeOrquestrador }

constructor TDFeOrquestrador.Create(const APublicador: IDFePublicador);
begin
  inherited Create;
  FPublicador := APublicador;
end;

destructor TDFeOrquestrador.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(FUnidades) do
    FUnidades[I].Free;
  inherited Destroy;
end;

procedure TDFeOrquestrador.AdicionarUnidade(const AUnidade: TDFeUnidadeTrabalho);
var
  LIndiceNovo: Integer;
begin
  LIndiceNovo := Length(FUnidades);
  SetLength(FUnidades, LIndiceNovo + 1);
  FUnidades[LIndiceNovo] := AUnidade;
end;

function TDFeOrquestrador.Agora: TDateTime;
begin
  Result := SysUtils.Now;
end;

procedure TDFeOrquestrador.RegistrarAviso(const AUnidade: TDFeUnidadeTrabalho; const AMensagem: string);
begin
  // no-op por padrao -- ver comentario da declaracao
end;

procedure TDFeOrquestrador.RegistrarErro(const AUnidade: TDFeUnidadeTrabalho; const AMensagem: string);
begin
  // no-op por padrao -- ver comentario da declaracao
end;

procedure TDFeOrquestrador.ExecutarCiclo;
var
  I: Integer;
begin
  for I := 0 to High(FUnidades) do
    ExecutarUnidade(FUnidades[I]);
end;

procedure TDFeOrquestrador.ExecutarUnidade(const AUnidade: TDFeUnidadeTrabalho);
var
  LNamespace: string;
  LUltimoNSU: Int64;
  LLote: TDFeLoteBruto;
  LEventos: TDFeEventoNormalizadoArray;
  LClassificacao: TDFeClassificacaoCStat;
  LLotesProcessados: Integer;
  LContinuar: Boolean;
  LFalhouChamada: Boolean;
  I: Integer;
begin
  if AUnidade.Pausada then
    Exit;

  if Agora < AUnidade.ProximaConsultaEm then
    Exit;

  LNamespace := MontarNamespaceCursor(AUnidade.Provider.Identificador, AUnidade.Certificado);
  LLotesProcessados := 0;
  LContinuar := True;

  while LContinuar do
  begin
    Inc(LLotesProcessados);
    LUltimoNSU := AUnidade.CursorStore.ObterUltimoNSU(LNamespace);
    LFalhouChamada := False;

    try
      LLote := AUnidade.Client.Consultar(AUnidade.Certificado, LUltimoNSU);
    except
      on E: EDFeCertificadoInvalido do
      begin
        AUnidade.Pausada := True;
        AUnidade.MotivoPausa := E.Message;
        RegistrarErro(AUnidade, 'Certificado invalido, unidade pausada: ' + E.Message);
        LFalhouChamada := True;
      end;
      on E: EDFeComunicacaoFalhou do
      begin
        RegistrarAviso(AUnidade, 'Falha de comunicacao: ' + E.Message);
        LFalhouChamada := True;
      end;
      on E: EDFeRespostaInvalida do
      begin
        RegistrarErro(AUnidade, 'Resposta invalida, ciclo ignorado: ' + E.Message);
        LFalhouChamada := True;
      end;
      // qualquer outra excecao (bug, falha inesperada) propaga -- nao e'
      // um caso modelado, entao nao deve ser engolida em silencio.
    end;

    if LFalhouChamada then
    begin
      if not AUnidade.Pausada then
        AUnidade.ProximaConsultaEm := Agora + SegundosParaTimeDelta(AUnidade.IntervaloBaseSegundos);
      Exit;
    end;

    LClassificacao := ClassificarCStat(LLote.CStat, AUnidade.Provider.CodigoConsumoIndevido);

    case LClassificacao of
      dccConsumoIndevido:
        begin
          // Sem escalonamento: a SEFAZ desbloqueia automaticamente apos 1h,
          // sempre a mesma janela -- ver DFE_INTERVALO_BASE_SEGUNDOS_PADRAO
          // e docs/referencias/README.md.
          AUnidade.ProximaConsultaEm := Agora + SegundosParaTimeDelta(AUnidade.IntervaloBaseSegundos);
          RegistrarAviso(AUnidade, Format('Consumo indevido (cStat=%d); proxima tentativa em %ds', [LLote.CStat, AUnidade.IntervaloBaseSegundos]));
          Exit;
        end;
      dccServicoIndisponivel, dccDesconhecido:
        begin
          RegistrarAviso(AUnidade, Format('cStat=%d (%s) nao processado; mantendo agendamento atual', [LLote.CStat, LLote.XMotivo]));
          AUnidade.ProximaConsultaEm := Agora + SegundosParaTimeDelta(AUnidade.IntervaloBaseSegundos);
          Exit;
        end;
      dccNenhumDocumento, dccDocumentosLocalizados:
        begin
          LEventos := AUnidade.Provider.Decodificar(LLote, AUnidade.Certificado);
          for I := 0 to High(LEventos) do
            FPublicador.Publicar(MontarRoutingKey(LEventos[I]), LEventos[I].XmlPayload);

          // cursor so avanca depois de publicar tudo com sucesso -- ver
          // docs/architecture.md, "Persistencia do cursor de NSU".
          AUnidade.CursorStore.GravarUltimoNSU(LNamespace, LLote.UltimoNSU);

          LContinuar := (LLote.UltimoNSU < LLote.MaxNSU) and (LLotesProcessados < DFE_MAX_LOTES_POR_CICLO);
          if not LContinuar then
            AUnidade.ProximaConsultaEm := Agora + SegundosParaTimeDelta(AUnidade.IntervaloBaseSegundos);
        end;
    else
      // qualquer valor futuro de TDFeClassificacaoCStat que este case nao
      // liste explicitamente ainda -- tratar como dccDesconhecido em vez de
      // nao fazer nada em silencio.
      begin
        RegistrarAviso(AUnidade, Format('Classificacao de cStat nao tratada (cStat=%d); mantendo agendamento atual', [LLote.CStat]));
        AUnidade.ProximaConsultaEm := Agora + SegundosParaTimeDelta(AUnidade.IntervaloBaseSegundos);
      end;
    end;
  end;
end;

end.
