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
    FManifestacaoAutomatica: Boolean;
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
    { So' dado carregado pela config (ver DFe.Config) -- o orquestrador nao
      le nem age sobre isto, so' guarda e repassa via AoPublicarDocumento
      (ver TDFeOrquestrador). Quem decide o que fazer com isso e'
      DFe.Manifestacao.TDFeAutoManifestador, nao este unit. }
    property ManifestacaoAutomatica: Boolean read FManifestacaoAutomatica write FManifestacaoAutomatica;
  end;

  TDFeUnidadeTrabalhoArray = array of TDFeUnidadeTrabalho;

  { Monta a chave de namespace do cursor de NSU: '<tipo>/<cnpjCpf>/<uf>' (ver
    docs/architecture.md, "Persistencia do cursor de NSU"). E' o orquestrador
    quem monta essa chave, nunca o provider -- exportada como funcao pura
    para ser testavel isoladamente. }
  function MontarNamespaceCursor(const ATipoDocumento: string;
    const ACertificado: TDFeCertificado): string;

type
  { Chamado depois que um evento de CATEGORIA DOCUMENTO (nunca evento fiscal)
    e' publicado com sucesso -- ver TDFeOrquestrador.AoPublicarDocumento. O
    orquestrador nao sabe o que e' "manifestacao"; so' avisa "publiquei um
    documento desta unidade", e quem quiser reagir (ver
    DFe.Manifestacao.TDFeAutoManifestador) decide o que fazer. 'of object'
    (metodo ligado), nao 'reference to' -- closures nao existem no FPC 3.2. }
  TDFeEventoPublicadoNotify = procedure(const AUnidade: TDFeUnidadeTrabalho;
    const AEvento: TDFeEventoNormalizado) of object;

  { Liga uma lista de unidades de trabalho ao publicador. Nao possui thread
    nem timer proprio -- ver comentario de topo do unit. }
  TDFeOrquestrador = class
  private
    FPublicador: IDFePublicador;
    FUnidades: TDFeUnidadeTrabalhoArray;
    FAoPublicarDocumento: TDFeEventoPublicadoNotify;
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

    { Busca uma unidade pelo alias configurado (TDFeUnidadeTrabalho.
      Certificado.Identificador -- ver DFe.Config, onde o alias da secao
      'certificado:<alias>' vira esse campo). Devolve nil se nao
      encontrar. Usado por DFe.Config.RecarregarConfig para reconciliar a
      config com o orquestrador em execucao sem recriar unidades que ja
      existem (e sem perder o estado de agendamento/pausa delas). }
    function ObterUnidadePorAlias(const AAlias: string): TDFeUnidadeTrabalho;

    { Copia independente das unidades atuais -- quem chama nao pode
      corromper o estado interno do orquestrador escrevendo no array
      devolvido (mesmo cuidado de TDFeProviderRegistry.Todos, mas aqui sao
      referencias de objeto, nao interface -- nao ha refcount para
      corromper, so a lista em si). }
    function Unidades: TDFeUnidadeTrabalhoArray;

    { Hook opcional (nil por padrao = nenhuma mudanca de comportamento) --
      ver TDFeEventoPublicadoNotify. Propriedade em vez de metodo virtual
      de proposito: nao exige subclassificar TDFeOrquestrador so' para
      ligar manifestacao automatica (ou qualquer outra reacao futura). }
    property AoPublicarDocumento: TDFeEventoPublicadoNotify read FAoPublicarDocumento write FAoPublicarDocumento;

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

function TDFeOrquestrador.ObterUnidadePorAlias(const AAlias: string): TDFeUnidadeTrabalho;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to High(FUnidades) do
    if SameText(FUnidades[I].Certificado.Identificador, AAlias) then
    begin
      Result := FUnidades[I];
      Break;
    end;
end;

function TDFeOrquestrador.Unidades: TDFeUnidadeTrabalhoArray;
var
  I: Integer;
begin
  SetLength(Result, Length(FUnidades));
  for I := 0 to High(FUnidades) do
    Result[I] := FUnidades[I];
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
  begin
    { Isolamento por unidade: um host roda desassistido por longos periodos
      (ver DFe.Host.Loop) -- um bug numa unidade (ou uma excecao que
      ExecutarUnidade nao modela, ver DFe.Errors) nao pode derrubar o
      processo inteiro e parar de atender as outras unidades/certificados.
      Ainda assim NAO e' engolido em silencio: passa por RegistrarErro.

      A unidade TAMBEM e' reagendada: ExecutarUnidade so' move
      ProximaConsultaEm nos caminhos que completam, entao sem isto uma
      excecao depois de Consultar (Decodificar com item malformado, falha
      em Publicar, bug) deixaria a unidade elegivel no proximo tick e a
      mesma consulta se repetiria a cada DFE_HOST_TICK_SEGUNDOS_PADRAO --
      exatamente o consumo indevido (656) que o intervalo de 1h existe
      para evitar. O cursor nao avanca (so' avanca depois de publicar
      tudo), entao a proxima tentativa busca o mesmo lote de novo:
      entrega pelo menos uma vez, nunca perde documento. }
    try
      ExecutarUnidade(FUnidades[I]);
    except
      on E: Exception do
      begin
        FUnidades[I].ProximaConsultaEm := Agora + SegundosParaTimeDelta(FUnidades[I].IntervaloBaseSegundos);
        RegistrarErro(FUnidades[I], Format('Excecao nao tratada processando a unidade (reagendada; cursor nao avancou): %s: %s', [E.ClassName, E.Message]));
      end;
    end;
  end;
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
      // um caso modelado. Nao e' engolida em silencio (ExecutarCiclo loga
      // via RegistrarErro) nem derruba as outras unidades (isolamento por
      // unidade em ExecutarCiclo).
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
          begin
            FPublicador.Publicar(MontarRoutingKey(LEventos[I]), LEventos[I].XmlPayload);
            if (LEventos[I].Categoria = dcDocumento) and Assigned(FAoPublicarDocumento) then
              FAoPublicarDocumento(AUnidade, LEventos[I]);
          end;

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
