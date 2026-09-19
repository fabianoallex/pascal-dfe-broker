unit DFe.Config;

{$I dfe.inc}

{ Formato de configuracao: INI, sem dependencia externa -- mesma filosofia
  de DFe.CursorStore.Arquivo (ver docs/architecture.md, "Integracao com
  ACBr"). JSON/YAML foram descartados
  de proposito: JSON tem API diferente entre Delphi (System.JSON) e FPC
  (fpjson), exigiria uma camada de abstracao; YAML nao tem suporte nativo
  em nenhum dos dois, exigiria biblioteca de terceiros. INI e' RTL padrao
  identica nos dois compiladores (unit IniFiles), legivel a olho nu.

  Formato:

    [dfe]
    IntervaloBaseSegundos=3600   ; opcional
    TickSegundos=60              ; opcional
    CursorPath=cursores.dat      ; opcional

    [certificado:matriz]
    Provider=nfe
    CnpjCpf=12345678000199
    UF=RS
    Ativo=true                  ; opcional, default true
    ManifestacaoAutomatica=false ; opcional, default false -- ver DFe.Manifestacao

    [broker]                     ; tudo opcional -- ver CarregarConfigBroker
    Modo=embutido                ; ou 'externo' (RabbitMQ etc.)
    BindAddress=127.0.0.1        ; embutido: onde escuta
    Host=127.0.0.1               ; externo: onde conecta
    Porta=5672
    Usuario=guest
    Senha=guest
    VirtualHost=/
    DataDir=broker               ; embutido: WAL; vazio = transiente

    [fila:fiscal]                ; fila declarada pelo host, ligada a exchange 'dfe'
    RoutingKey=nfe.documento.#,nfe.evento.#

  Cada secao 'certificado:<alias>' vira uma TDFeUnidadeTrabalho. Campos de
  certificado digital "de verdade" (caminho do .pfx, senha) ficam FORA
  deste arquivo de proposito -- pertencem a implementacao real de
  IDFeDistribuicaoClient (componentes ACBr, ainda nao escrita), nunca ao core, que
  so precisa saber CnpjCpf/UF/qual provider usar.

  MAIS DE UM CERTIFICADO PARA O MESMO CNPJ (troca antes do vencimento):
  o NSU da Distribuicao de DFe pertence ao CNPJ/UF consultado, nao ao
  certificado que autentica a chamada -- dois certificados do mesmo CNPJ
  compartilham o mesmo cursor (namespace e' <tipo>/<cnpjCpf>/<uf>, nunca o
  alias, ver DFe.Orquestrador.MontarNamespaceCursor). Isso permite
  configurar um certificado novo antes do antigo vencer, sem duplicar nem
  perder documento na troca -- MAS os dois nunca podem estar Ativo=true ao
  mesmo tempo: a SEFAZ limita consulta por CNPJ, nao por certificado, e
  dois certificados consultando o mesmo (tipo, CnpjCpf, UF) ativamente
  dobra a taxa de consulta e arrisca consumo indevido (656/678). Por isso
  CarregarConfig recusa a config se dois certificados ATIVOS compartilham
  (Provider, CnpjCpf, UF) -- a troca e' sempre "ativa o novo e desativa o
  velho", nunca os dois ligados. Ativacao automatica por vencimento do
  certificado foi cogitada e adiada -- exigiria inspecionar o certificado
  digital de verdade, que so a implementacao real via componentes ACBr
  (ainda nao escrita) podera fazer. ManifestacaoAutomatica e' por certificado/alias e
  NAO entra nessa colisao -- dois certificados do mesmo CNPJ podem ter
  valores diferentes, ja que so' um dos dois estara Ativo por vez de
  qualquer forma.

  RECARREGAR SEM REINICIAR: RecarregarConfig reconcilia uma TDFeConfig com
  um TDFeOrquestrador ja em execucao -- alias novo vira unidade nova; alias
  existente so tem Pausada sincronizado com Ativo (nunca recriado, para nao
  perder o estado de agendamento); alias que sumiu da config e' pausado,
  nunca removido/destruido. TDFeConfigWatcher embrulha isso: chamado a cada
  tick do host (ver DFe.Host.Loop), detecta se o arquivo mudou (data de
  modificacao) e recarrega sozinho quando muda. }

interface

uses
  SysUtils, Classes, IniFiles,
  DFe.Types,
  DFe.Provider,
  DFe.Orquestrador,
  DFe.Host.Loop;

type
  { Uma linha de configuracao de certificado, antes de virar
    TDFeUnidadeTrabalho. }
  TDFeConfigCertificado = record
    Alias: string;              // nome da secao (sem o prefixo 'certificado:') -- tambem vira Certificado.Identificador, usado por RecarregarConfig para reconciliar
    ProviderIdentificador: string;
    Certificado: TDFeCertificado;
    Ativo: Boolean;              // false = configurado mas dormente (ver comentario de topo, troca de certificado)
    ManifestacaoAutomatica: Boolean; // false = exige comando externo (ver DFe.Manifestacao); default false, opt-in explicito
  end;

  TDFeConfigCertificadoArray = array of TDFeConfigCertificado;

  TDFeConfig = record
    IntervaloBaseSegundos: Integer;
    TickSegundos: Integer;
    CursorPath: string;
    Certificados: TDFeConfigCertificadoArray;
  end;

  TDFeModoBroker = (mbEmbutido, mbExterno);

  { Uma fila que o proprio host declara e liga a exchange 'dfe' na subida (ver
    [fila:<nome>] no formato acima). Sem isto, o que for publicado antes de um
    consumidor declarar a sua fila e' DESCARTADO pelo broker (pub/sub) -- e o
    cursor de NSU ja' teria avancado. }
  TDFeConfigFila = record
    Nome: string;
    Padroes: array of string; // routing-keys/padroes topic, ex. 'nfe.documento.#'
  end;

  TDFeConfigBroker = record
    Modo: TDFeModoBroker;
    { Embutido: onde o broker escuta (BindAddress:Porta). Externo: onde o
      cliente conecta (Host:Porta). }
    Host: string;
    BindAddress: string;
    Porta: Integer;
    Usuario: string;
    Senha: string;
    VirtualHost: string;
    { So' embutido: pasta do WAL do broker. Vazia = broker TRANSIENTE (o que
      estiver em fila se perde ao reiniciar). Relativa = relativa ao arquivo
      de config, resolvida por quem hospeda. }
    DataDir: string;
    Filas: array of TDFeConfigFila;
  end;

  { Fabrica de IDFeDistribuicaoClient para um certificado -- quem monta o
    orquestrador de verdade passa aqui a implementacao real (componentes
    ACBr); testes passam uma fabrica que devolve fakes. 'of object' (metodo
    ligado), nao 'reference to' -- closures nao existem no FPC 3.2 (ver
    CLAUDE.md do pascal-amqp-faa, regra que vale aqui tambem). Isolado
    assim porque "como construir um client" (certificado, componentes ACBr)
    e' decisao de quem hospeda, nao do parser de config. }
  TDFeClientFactory = function(const ACertificado: TDFeConfigCertificado): IDFeDistribuicaoClient of object;

{ Le e valida o arquivo de configuracao. Levanta excecao com o nome da
  secao problematica se uma secao 'certificado:*' estiver sem Provider,
  CnpjCpf ou UF, ou se dois certificados ATIVOS compartilharem
  (Provider, CnpjCpf, UF) -- ver comentario de topo do unit. Falha alto e
  cedo, na inicializacao do host, em vez de criar uma unidade de trabalho
  quebrada (ou duas competindo pelo mesmo CNPJ) em silencio. }
function CarregarConfig(const ACaminho: string): TDFeConfig;

{ Le a secao [broker] e as secoes [fila:<nome>] do MESMO arquivo. Separada de
  CarregarConfig porque o que o orquestrador precisa (certificados, cursor) e o
  que o host precisa (broker, filas) mudam por motivos diferentes -- so' o
  primeiro e' recarregado a quente (ver TDFeConfigWatcher). Levanta excecao para
  Modo desconhecido, Porta fora de 0..65535, fila sem RoutingKey ou com o nome
  reservado da fila de comandos. }
function CarregarConfigBroker(const ACaminho: string): TDFeConfigBroker;

{ Reconcilia a config com um TDFeOrquestrador ja em execucao, sem recriar
  nem remover unidades existentes:
    - alias novo (nao encontrado por ObterUnidadePorAlias) -- cria a
      unidade via AClientFactory e adiciona ao orquestrador, ja com
      Pausada = not Ativo;
    - alias existente -- so sincroniza Pausada (com Ativo) e
      ManifestacaoAutomatica com a config atual (nunca recria, preserva
      ProximaConsultaEm/estado);
    - alias que existia no orquestrador mas sumiu desta config -- pausado
      (nunca destruido: destruir uma unidade em potencial uso por outra
      thread/callback seria mais arriscado que so pausa-la).
  Usada tanto na carga inicial (orquestrador recem-criado, sem unidades --
  todo alias e' "novo") quanto no recarregamento a quente (ver
  TDFeConfigWatcher). Levanta excecao se um alias novo referenciar um
  provider nao registrado. }
procedure RecarregarConfig(const AConfig: TDFeConfig;
  const AOrquestrador: TDFeOrquestrador;
  const ACursorStore: IDFeCursorStore;
  const AClientFactory: TDFeClientFactory);

type
  { Chamado periodicamente por quem hospeda (por exemplo, de dentro de um
    TDFeHostLoop.Tick sobrescrito -- ver DFe.Host.Loop). Detecta se o
    arquivo de config mudou desde a ultima leitura (data de modificacao) e,
    se mudou, recarrega e reconcilia via RecarregarConfig. Nao sabe nada
    sobre console/servico/sinal do SO, mesmo espirito de TDFeHostLoop. }
  TDFeConfigWatcher = class
  private
    FCaminho: string;
    FOrquestrador: TDFeOrquestrador;
    FCursorStore: IDFeCursorStore;
    FClientFactory: TDFeClientFactory;
    FUltimaModificacao: TDateTime;
  protected
    { Data de modificacao do arquivo de config -- injetavel para teste
      (mesmo padrao de Agora em TDFeOrquestrador e Esperar em
      TDFeHostLoop), em vez de depender de FileAge de verdade e ter que
      esperar o relogio do sistema mudar de fato num teste. }
    function ObterDataModificacao: TDateTime; virtual;
  public
    { Ja faz a carga inicial (chama Recarregar) -- um host so precisa
      disto para ter carga inicial + observacao continua num so lugar. }
    constructor Create(const ACaminho: string;
      const AOrquestrador: TDFeOrquestrador;
      const ACursorStore: IDFeCursorStore;
      const AClientFactory: TDFeClientFactory);

    { Le e reconcilia incondicionalmente, atualizando a data de
      modificacao observada. Virtual so' para teste (ver
      DFe.TestDoubles.TDFeConfigWatcherTestavel), que conta quantas vezes
      isto rodou de verdade em vez de inferir pelo numero de chamadas da
      fabrica de client (que so' e' chamada para alias novo). }
    procedure Recarregar; virtual;

    { So' recarrega se a data de modificacao do arquivo mudou desde a
      ultima vez (carga inicial ou ultimo Recarregar). Chamar isto com
      mais frequencia do que necessario e' seguro: sem mudanca no
      arquivo, e' um FileAge/comparacao so, sem I/O de parsing. }
    procedure VerificarRecarregar;
  end;

implementation

const
  SECAO_GLOBAL = 'dfe';
  PREFIXO_CERTIFICADO = 'certificado:';

{ Le e interpreta um booleano na mao, em vez de usar TCustomIniFile.ReadBool
  -- medido (2026-09-18, achado pelo usuario rodando o Delphi real): no
  Delphi, ReadBool delega para ReadInteger/StrToIntDef, que nao entende o
  texto "false"/"true" (so' numero) -- "Ativo=false" virava o DEFAULT
  passado a ReadBool (True) em vez de False, silenciosamente. O FPC
  interpreta o texto direto e nao tem esse problema, o que escondeu o bug
  ate' rodar no Delphi de verdade. Interpretar a string aqui mesmo garante
  o mesmo resultado nos dois compiladores, sem depender de qual RTL
  entende o que. }
function LerBooleano(const AValor: string; const ADefault: Boolean): Boolean;
begin
  if AValor = '' then
    Result := ADefault
  else
    Result := SameText(AValor, 'true') or (AValor = '1');
end;

function CarregarConfig(const ACaminho: string): TDFeConfig;
var
  LIni: TMemIniFile;
  LSecoes: TStringList;
  I, J, LIndice: Integer;
  LNomeSecao: string;
begin
  LIni := TMemIniFile.Create(ACaminho);
  try
    Result.IntervaloBaseSegundos := LIni.ReadInteger(SECAO_GLOBAL, 'IntervaloBaseSegundos', DFE_INTERVALO_BASE_SEGUNDOS_PADRAO);
    Result.TickSegundos := LIni.ReadInteger(SECAO_GLOBAL, 'TickSegundos', DFE_HOST_TICK_SEGUNDOS_PADRAO);
    Result.CursorPath := LIni.ReadString(SECAO_GLOBAL, 'CursorPath', 'cursores.dat');

    SetLength(Result.Certificados, 0);
    LSecoes := TStringList.Create;
    try
      LIni.ReadSections(LSecoes);
      for I := 0 to LSecoes.Count - 1 do
      begin
        LNomeSecao := LSecoes[I];
        if Pos(PREFIXO_CERTIFICADO, LowerCase(LNomeSecao)) <> 1 then
          Continue;

        LIndice := Length(Result.Certificados);
        SetLength(Result.Certificados, LIndice + 1);

        Result.Certificados[LIndice].Alias := Copy(LNomeSecao, Length(PREFIXO_CERTIFICADO) + 1, MaxInt);
        Result.Certificados[LIndice].ProviderIdentificador := LIni.ReadString(LNomeSecao, 'Provider', '');
        Result.Certificados[LIndice].Certificado.Identificador := Result.Certificados[LIndice].Alias;
        Result.Certificados[LIndice].Certificado.CnpjCpf := LIni.ReadString(LNomeSecao, 'CnpjCpf', '');
        Result.Certificados[LIndice].Certificado.UF := LIni.ReadString(LNomeSecao, 'UF', '');
        Result.Certificados[LIndice].Ativo := LerBooleano(LIni.ReadString(LNomeSecao, 'Ativo', ''), True);
        Result.Certificados[LIndice].ManifestacaoAutomatica := LerBooleano(LIni.ReadString(LNomeSecao, 'ManifestacaoAutomatica', ''), False);

        if Result.Certificados[LIndice].ProviderIdentificador = '' then
          raise Exception.CreateFmt('Config: secao "%s" sem "Provider"', [LNomeSecao]);
        if Result.Certificados[LIndice].Certificado.CnpjCpf = '' then
          raise Exception.CreateFmt('Config: secao "%s" sem "CnpjCpf"', [LNomeSecao]);
        if Result.Certificados[LIndice].Certificado.UF = '' then
          raise Exception.CreateFmt('Config: secao "%s" sem "UF"', [LNomeSecao]);
      end;
    finally
      LSecoes.Free;
    end;

    { Dois certificados ATIVOS para o mesmo (Provider, CnpjCpf, UF)
      consultariam a mesma "posicao de leitura" na SEFAZ de forma
      independente -- risco real de consumo indevido (ver comentario de
      topo do unit). So' um dos dois pode estar Ativo por vez. }
    for I := 0 to High(Result.Certificados) do
    begin
      if not Result.Certificados[I].Ativo then
        Continue;
      for J := I + 1 to High(Result.Certificados) do
      begin
        if not Result.Certificados[J].Ativo then
          Continue;
        if SameText(Result.Certificados[I].ProviderIdentificador, Result.Certificados[J].ProviderIdentificador)
          and (Result.Certificados[I].Certificado.CnpjCpf = Result.Certificados[J].Certificado.CnpjCpf)
          and SameText(Result.Certificados[I].Certificado.UF, Result.Certificados[J].Certificado.UF) then
          raise Exception.CreateFmt(
            'Config: certificados "%s" e "%s" estao ambos Ativo=true para o mesmo provider/CnpjCpf/UF (%s/%s/%s) -- apenas um pode estar ativo por vez (ver DFe.Config, comentario sobre troca de certificado)',
            [Result.Certificados[I].Alias, Result.Certificados[J].Alias,
             Result.Certificados[I].ProviderIdentificador, Result.Certificados[I].Certificado.CnpjCpf, Result.Certificados[I].Certificado.UF]);
      end;
    end;
  finally
    LIni.Free;
  end;
end;

function CarregarConfigBroker(const ACaminho: string): TDFeConfigBroker;
const
  SECAO_BROKER = 'broker';
  PREFIXO_FILA = 'fila:';
  FILA_RESERVADA = 'dfe.comandos'; // fila de comandos de manifestacao (DFe.ComandoFonte.AMQP)
var
  LIni: TMemIniFile;
  LSecoes, LPadroes: TStringList;
  LModo: string;
  I, J, LIndice: Integer;
  LNomeSecao, LNomeFila: string;
begin
  LIni := TMemIniFile.Create(ACaminho);
  try
    LModo := LowerCase(Trim(LIni.ReadString(SECAO_BROKER, 'Modo', 'embutido')));
    if LModo = 'embutido' then
      Result.Modo := mbEmbutido
    else if LModo = 'externo' then
      Result.Modo := mbExterno
    else
      raise Exception.CreateFmt('Config: [broker] Modo="%s" desconhecido (use "embutido" ou "externo")', [LModo]);

    Result.Host := LIni.ReadString(SECAO_BROKER, 'Host', '127.0.0.1');
    Result.BindAddress := LIni.ReadString(SECAO_BROKER, 'BindAddress', '127.0.0.1');
    Result.Porta := LIni.ReadInteger(SECAO_BROKER, 'Porta', 5672);
    Result.Usuario := LIni.ReadString(SECAO_BROKER, 'Usuario', 'guest');
    Result.Senha := LIni.ReadString(SECAO_BROKER, 'Senha', 'guest');
    Result.VirtualHost := LIni.ReadString(SECAO_BROKER, 'VirtualHost', '/');
    // padrao DURAVEL: com o cursor ja' avancado, uma fila transiente perderia
    // documento num restart. Desligar e' explicito: "DataDir=" (vazio).
    Result.DataDir := LIni.ReadString(SECAO_BROKER, 'DataDir', 'broker');

    if (Result.Porta < 0) or (Result.Porta > 65535) then
      raise Exception.CreateFmt('Config: [broker] Porta=%d fora de 0..65535', [Result.Porta]);

    SetLength(Result.Filas, 0);
    LSecoes := TStringList.Create;
    LPadroes := TStringList.Create;
    try
      LIni.ReadSections(LSecoes);
      for I := 0 to LSecoes.Count - 1 do
      begin
        LNomeSecao := LSecoes[I];
        if Pos(PREFIXO_FILA, LowerCase(LNomeSecao)) <> 1 then
          Continue;

        LNomeFila := Copy(LNomeSecao, Length(PREFIXO_FILA) + 1, MaxInt);
        if LNomeFila = '' then
          raise Exception.CreateFmt('Config: secao "%s" sem nome de fila', [LNomeSecao]);
        if SameText(LNomeFila, FILA_RESERVADA) then
          raise Exception.CreateFmt('Config: a fila "%s" e'' reservada (comandos de manifestacao)', [FILA_RESERVADA]);

        LPadroes.Clear;
        LPadroes.Delimiter := ',';
        LPadroes.StrictDelimiter := True;
        LPadroes.DelimitedText := LIni.ReadString(LNomeSecao, 'RoutingKey', '');

        LIndice := Length(Result.Filas);
        SetLength(Result.Filas, LIndice + 1);
        Result.Filas[LIndice].Nome := LNomeFila;
        SetLength(Result.Filas[LIndice].Padroes, 0);
        for J := 0 to LPadroes.Count - 1 do
          if Trim(LPadroes[J]) <> '' then
          begin
            SetLength(Result.Filas[LIndice].Padroes, Length(Result.Filas[LIndice].Padroes) + 1);
            Result.Filas[LIndice].Padroes[High(Result.Filas[LIndice].Padroes)] := Trim(LPadroes[J]);
          end;

        if Length(Result.Filas[LIndice].Padroes) = 0 then
          raise Exception.CreateFmt('Config: secao "%s" sem "RoutingKey"', [LNomeSecao]);
      end;
    finally
      LPadroes.Free;
      LSecoes.Free;
    end;
  finally
    LIni.Free;
  end;
end;

procedure RecarregarConfig(const AConfig: TDFeConfig;
  const AOrquestrador: TDFeOrquestrador;
  const ACursorStore: IDFeCursorStore;
  const AClientFactory: TDFeClientFactory);
var
  I, J: Integer;
  LUnidade: TDFeUnidadeTrabalho;
  LProvider: IDFeProvider;
  LClient: IDFeDistribuicaoClient;
  LUnidadesAtuais: TDFeUnidadeTrabalhoArray;
  LAindaNaConfig: Boolean;
begin
  for I := 0 to High(AConfig.Certificados) do
  begin
    LUnidade := AOrquestrador.ObterUnidadePorAlias(AConfig.Certificados[I].Alias);

    if not Assigned(LUnidade) then
    begin
      LProvider := TDFeProviderRegistry.ObterPorIdentificador(AConfig.Certificados[I].ProviderIdentificador);
      if not Assigned(LProvider) then
        raise Exception.CreateFmt(
          'Config: certificado "%s" usa provider "%s", que nao esta registrado (a unit do provider foi linkada ao programa?)',
          [AConfig.Certificados[I].Alias, AConfig.Certificados[I].ProviderIdentificador]);

      LClient := AClientFactory(AConfig.Certificados[I]);
      LUnidade := TDFeUnidadeTrabalho.Create(LProvider, LClient,
        AConfig.Certificados[I].Certificado, ACursorStore, AConfig.IntervaloBaseSegundos);
      LUnidade.Pausada := not AConfig.Certificados[I].Ativo;
      LUnidade.ManifestacaoAutomatica := AConfig.Certificados[I].ManifestacaoAutomatica;
      AOrquestrador.AdicionarUnidade(LUnidade);
    end
    else
    begin
      LUnidade.Pausada := not AConfig.Certificados[I].Ativo;
      LUnidade.ManifestacaoAutomatica := AConfig.Certificados[I].ManifestacaoAutomatica;
    end;
  end;

  { Alias que existia no orquestrador mas sumiu desta config: pausar (ver
    comentario da declaracao -- nunca destruir). }
  LUnidadesAtuais := AOrquestrador.Unidades;
  for I := 0 to High(LUnidadesAtuais) do
  begin
    LAindaNaConfig := False;
    for J := 0 to High(AConfig.Certificados) do
      if SameText(LUnidadesAtuais[I].Certificado.Identificador, AConfig.Certificados[J].Alias) then
      begin
        LAindaNaConfig := True;
        Break;
      end;
    if not LAindaNaConfig then
      LUnidadesAtuais[I].Pausada := True;
  end;
end;

{ TDFeConfigWatcher }

constructor TDFeConfigWatcher.Create(const ACaminho: string;
  const AOrquestrador: TDFeOrquestrador;
  const ACursorStore: IDFeCursorStore;
  const AClientFactory: TDFeClientFactory);
begin
  inherited Create;
  FCaminho := ACaminho;
  FOrquestrador := AOrquestrador;
  FCursorStore := ACursorStore;
  FClientFactory := AClientFactory;
  Recarregar;
end;

function TDFeConfigWatcher.ObterDataModificacao: TDateTime;
begin
  if not FileAge(FCaminho, Result) then
    Result := 0;
end;

procedure TDFeConfigWatcher.Recarregar;
begin
  RecarregarConfig(CarregarConfig(FCaminho), FOrquestrador, FCursorStore, FClientFactory);
  FUltimaModificacao := ObterDataModificacao;
end;

procedure TDFeConfigWatcher.VerificarRecarregar;
begin
  if ObterDataModificacao <> FUltimaModificacao then
    Recarregar;
end;

end.
