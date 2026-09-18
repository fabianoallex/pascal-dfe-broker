unit DFe.Manifestacao;

{$I dfe.inc}

{ Manifestacao do destinatario (Confirmacao/Ciencia/Desconhecimento/
  Operacao nao Realizada, no caso da NFe): configuravel por certificado
  para ser automatica ou exigir comando externo (ver DFe.Config,
  TDFeConfigCertificado.ManifestacaoAutomatica).

  Decisao (2026-09-18): comando simples + resultado como evento normal na
  exchange 'dfe', em vez de RPC classico (reply-to/correlation-id). O
  broker inteiro ja e' pub/sub -- quem manda o comando ja esta ouvindo a
  exchange, entao o resultado sai la, reaproveitando MontarRoutingKey.
  Menos maquinaria do lado do chamador (sem fila de resposta temporaria,
  sem correlacao, sem timeout).

  Duas pecas independentes de onde o comando vem:
  - IDFeComandoFonte: abstrai "de onde chegam os comandos" (fila AMQP de
    comando, na implementacao real -- ainda nao escrita) para
    TDFeManifestacaoProcessador ser testavel sem broker nenhum, mesmo
    espirito de IDFeDistribuicaoClient/IDFePublicador.
  - TDFeAutoManifestador: reage a TDFeOrquestrador.AoPublicarDocumento
    (ver DFe.Orquestrador) gerando um comando de "ciencia" sozinho quando
    a unidade que publicou tem ManifestacaoAutomatica = True. Automatico e
    manual chegam ao MESMO TDFeManifestacaoProcessador, so' o gatilho
    difere.

  IDFeManifestador e' uma capacidade OPCIONAL de provider (nem todo tipo
  de documento tem "manifestacao do destinatario") -- verificada em tempo
  de execucao via Supports(provider, IDFeManifestador, ...), nao faz parte
  de IDFeProvider (ver DFe.Provider). }

interface

uses
  SysUtils, Classes,
  DFe.Types,
  DFe.Errors,
  DFe.Provider,
  DFe.Publicador,
  DFe.RoutingKey,
  DFe.Orquestrador;

const
  { Tipos de evento de manifestacao conhecidos (NFe) -- os dois abaixo
    exigem Justificativa por regra da SEFAZ (conferir texto/tamanho minimo
    exato quando a implementacao real via componentes ACBr existir; o que importa
    aqui e' nao aceitar o comando sem NENHUMA justificativa). }
  DFE_EVENTO_MANIFESTACAO_DESCONHECIMENTO = 'desconhecimento';
  DFE_EVENTO_MANIFESTACAO_OPERACAO_NAO_REALIZADA = 'operacaonaorealizada';

type
  { Um comando de manifestacao, ja interpretado (ver InterpretarComando) --
    formato de origem (chave=valor no corpo da mensagem AMQP, mesmo estilo
    do arquivo de config) e' detalhe de quem produz isto, nao deste tipo. }
  TDFeComandoManifestacao = record
    Alias: string;          // qual certificado/unidade deve manifestar (ver TDFeOrquestrador.ObterUnidadePorAlias)
    ChaveAcesso: string;
    TipoEvento: string;     // 'confirmacao' | 'ciencia' | 'desconhecimento' | 'operacaonaorealizada'
    Justificativa: string;  // obrigatorio para os dois tipos acima, ver DFE_EVENTO_MANIFESTACAO_*
  end;

{ Interpreta o corpo de uma mensagem de comando (formato chave=valor, uma
  por linha -- mesmo estilo do arquivo de config). Levanta excecao se
  faltar Alias, ChaveAcesso ou TipoEvento, ou se TipoEvento exigir
  Justificativa e ela vier vazia -- falha alto e cedo, antes de tentar
  falar com qualquer provider. }
function InterpretarComando(const APayload: string): TDFeComandoManifestacao;

type
  { Capacidade OPCIONAL de provider -- ver comentario de topo do unit.
    Envia o evento de manifestacao para a SEFAZ e devolve o evento ja
    normalizado, pronto para publicar (mesmo formato de
    IDFeProvider.Decodificar). So' levanta excecao (ver DFe.Errors) quando
    a CHAMADA em si falha antes de existir uma resposta interpretavel --
    mesmo espirito de IDFeDistribuicaoClient: a semantica de protocolo da
    SEFAZ (evento aceito, rejeitado) vem no evento devolvido, nao como
    excecao. }
  IDFeManifestador = interface
    ['{7A3F9C2E-4B1D-4E6A-9C2E-4B1D4E6A9C2E}']
    function EnviarEvento(const ACertificado: TDFeCertificado;
      const AComando: TDFeComandoManifestacao): TDFeEventoNormalizado;
  end;

  { Fonte de comandos -- a implementacao real embrulha um consumidor AMQP
    (ainda nao escrita); testes usam uma fila de comandos pre-carregada.
    Devolve False quando nao ha comando pendente agora (nao bloqueia). }
  IDFeComandoFonte = interface
    ['{2D8E5A1F-6C3B-4D7E-A1F6-C3B4D7EA1F6C}']
    function ObterProximoComando(out AComando: TDFeComandoManifestacao): Boolean;
  end;

  { Processa comandos de manifestacao: resolve o alias na unidade do
    orquestrador, verifica se o provider dela suporta IDFeManifestador,
    envia o evento e publica o resultado como evento normal na mesma
    exchange (MontarRoutingKey). Nao sabe de onde o comando veio -- serve
    tanto o caminho manual (IDFeComandoFonte) quanto o automatico
    (TDFeAutoManifestador), ver comentario de topo do unit. }
  TDFeManifestacaoProcessador = class
  private
    FOrquestrador: TDFeOrquestrador;
    FPublicador: IDFePublicador;
  protected
    { Hook de observabilidade -- no-op por padrao, mesmo espirito de
      TDFeOrquestrador.RegistrarErro. Usado quando o comando nao pode ser
      processado (alias desconhecido, provider sem suporte) ou quando
      EnviarEvento levanta uma das excecoes modeladas em DFe.Errors. }
    procedure RegistrarErro(const AComando: TDFeComandoManifestacao; const AMensagem: string); virtual;
  public
    constructor Create(const AOrquestrador: TDFeOrquestrador; const APublicador: IDFePublicador);

    { Processa um unico comando ja interpretado. Nunca levanta -- qualquer
      falha (alias desconhecido, provider sem IDFeManifestador, excecao de
      DFe.Errors) e' reportada via RegistrarErro, nao propagada, pelo
      mesmo motivo de isolamento de TDFeOrquestrador.ExecutarCiclo: uma
      falha aqui nao pode travar quem estiver drenando varios comandos. }
    procedure ProcessarComando(const AComando: TDFeComandoManifestacao);

    { Drena AFonte ate ela nao ter mais comando pendente, processando cada
      um via ProcessarComando. }
    procedure ProcessarTodos(const AFonte: IDFeComandoFonte);
  end;

  { Reage a TDFeOrquestrador.AoPublicarDocumento: se a unidade que acabou
    de publicar um documento tem ManifestacaoAutomatica = True, gera um
    comando de "ciencia" e entrega ao mesmo TDFeManifestacaoProcessador
    que atende comando externo. Um host real liga isto assim:

      LAutoManifestador := TDFeAutoManifestador.Create(LProcessador);
      LOrquestrador.AoPublicarDocumento := LAutoManifestador.AoPublicarDocumento; }
  TDFeAutoManifestador = class
  private
    FProcessador: TDFeManifestacaoProcessador;
  public
    constructor Create(const AProcessador: TDFeManifestacaoProcessador);
    procedure AoPublicarDocumento(const AUnidade: TDFeUnidadeTrabalho;
      const AEvento: TDFeEventoNormalizado);
  end;

implementation

function InterpretarComando(const APayload: string): TDFeComandoManifestacao;
var
  LLinhas: TStringList;
begin
  LLinhas := TStringList.Create;
  try
    LLinhas.NameValueSeparator := '=';
    LLinhas.Text := APayload;

    Result.Alias := LLinhas.Values['Alias'];
    Result.ChaveAcesso := LLinhas.Values['ChaveAcesso'];
    Result.TipoEvento := LowerCase(LLinhas.Values['TipoEvento']);
    Result.Justificativa := LLinhas.Values['Justificativa'];
  finally
    LLinhas.Free;
  end;

  if Result.Alias = '' then
    raise Exception.Create('Comando de manifestacao sem "Alias"');
  if Result.ChaveAcesso = '' then
    raise Exception.Create('Comando de manifestacao sem "ChaveAcesso"');
  if Result.TipoEvento = '' then
    raise Exception.Create('Comando de manifestacao sem "TipoEvento"');

  if ((Result.TipoEvento = DFE_EVENTO_MANIFESTACAO_DESCONHECIMENTO)
    or (Result.TipoEvento = DFE_EVENTO_MANIFESTACAO_OPERACAO_NAO_REALIZADA))
    and (Result.Justificativa = '') then
    raise Exception.CreateFmt('Comando de manifestacao "%s" exige "Justificativa"', [Result.TipoEvento]);
end;

{ TDFeManifestacaoProcessador }

constructor TDFeManifestacaoProcessador.Create(const AOrquestrador: TDFeOrquestrador; const APublicador: IDFePublicador);
begin
  inherited Create;
  FOrquestrador := AOrquestrador;
  FPublicador := APublicador;
end;

procedure TDFeManifestacaoProcessador.RegistrarErro(const AComando: TDFeComandoManifestacao; const AMensagem: string);
begin
  // no-op por padrao -- ver comentario da declaracao
end;

procedure TDFeManifestacaoProcessador.ProcessarComando(const AComando: TDFeComandoManifestacao);
var
  LUnidade: TDFeUnidadeTrabalho;
  LManifestador: IDFeManifestador;
  LEvento: TDFeEventoNormalizado;
begin
  LUnidade := FOrquestrador.ObterUnidadePorAlias(AComando.Alias);
  if not Assigned(LUnidade) then
  begin
    RegistrarErro(AComando, Format('Alias "%s" nao encontrado no orquestrador', [AComando.Alias]));
    Exit;
  end;

  if not Supports(LUnidade.Provider, IDFeManifestador, LManifestador) then
  begin
    RegistrarErro(AComando, Format('Provider "%s" (alias "%s") nao suporta manifestacao', [LUnidade.Provider.Identificador, AComando.Alias]));
    Exit;
  end;

  try
    LEvento := LManifestador.EnviarEvento(LUnidade.Certificado, AComando);
  except
    on E: EDFeCertificadoInvalido do
    begin
      RegistrarErro(AComando, 'Certificado invalido: ' + E.Message);
      Exit;
    end;
    on E: EDFeComunicacaoFalhou do
    begin
      RegistrarErro(AComando, 'Falha de comunicacao: ' + E.Message);
      Exit;
    end;
    on E: EDFeRespostaInvalida do
    begin
      RegistrarErro(AComando, 'Resposta invalida: ' + E.Message);
      Exit;
    end;
    // qualquer outra excecao (bug, falha inesperada) propaga -- nao e' um
    // caso modelado, mesmo criterio de DFe.Orquestrador.
  end;

  FPublicador.Publicar(MontarRoutingKey(LEvento), LEvento.XmlPayload);
end;

procedure TDFeManifestacaoProcessador.ProcessarTodos(const AFonte: IDFeComandoFonte);
var
  LComando: TDFeComandoManifestacao;
begin
  while AFonte.ObterProximoComando(LComando) do
    ProcessarComando(LComando);
end;

{ TDFeAutoManifestador }

constructor TDFeAutoManifestador.Create(const AProcessador: TDFeManifestacaoProcessador);
begin
  inherited Create;
  FProcessador := AProcessador;
end;

procedure TDFeAutoManifestador.AoPublicarDocumento(const AUnidade: TDFeUnidadeTrabalho;
  const AEvento: TDFeEventoNormalizado);
var
  LComando: TDFeComandoManifestacao;
begin
  if not AUnidade.ManifestacaoAutomatica then
    Exit;

  LComando.Alias := AUnidade.Certificado.Identificador;
  LComando.ChaveAcesso := AEvento.ChaveAcesso;
  LComando.TipoEvento := 'ciencia';
  LComando.Justificativa := '';
  FProcessador.ProcessarComando(LComando);
end;

end.
