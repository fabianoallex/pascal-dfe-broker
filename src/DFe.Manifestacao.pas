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

  IDFeManifestador e' uma capacidade OPCIONAL do CLIENT da unidade (nem
  todo tipo de documento tem "manifestacao do destinatario") -- verificada
  em tempo de execucao via Supports(unidade.Client, IDFeManifestador, ...),
  nao faz parte de IDFeDistribuicaoClient nem de IDFeProvider. Fica no
  client, e nao no provider, porque enviar o evento exige o certificado
  digital REAL (.pfx/senha) da unidade -- que so' o client tem; o provider
  e' um singleton do registry (ver DFe.Provider), sem credencial nenhuma.
  Corrigido em 2026-09-18 ao implementar a versao real
  (DFe.Client.ACBrNFe): a decisao original, "capacidade de provider", nao
  tinha como chegar ao certificado. }

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
  { Tipos de evento de manifestacao conhecidos (NFe) -- mesmo vocabulario
    de DFe.Provider.NFe.NomeTipoEventoNFe, para o resultado de uma
    manifestacao sair na mesma routing-key do evento equivalente vindo da
    distribuicao. SO' a Operacao nao Realizada tem Justificativa (xJust, 15 a
    255 caracteres): a NT 2012/002 v1.02, campo HP20 e regra H01 (rejeicao
    595), manda informa-la SOMENTE nesse evento -- nao no desconhecimento.
    Corrigido em 2026-09-18 ao conferir a NT (antes exigia tambem no
    desconhecimento). }
  DFE_EVENTO_MANIFESTACAO_CONFIRMACAO = 'confirmacao';
  DFE_EVENTO_MANIFESTACAO_CIENCIA = 'ciencia';
  DFE_EVENTO_MANIFESTACAO_DESCONHECIMENTO = 'desconhecimento';
  DFE_EVENTO_MANIFESTACAO_OPERACAO_NAO_REALIZADA = 'operacaonaorealizada';

  { TipoEvento do resultado quando a SEFAZ NAO registrou a manifestacao
    (rejeicao do evento ou do lote). E' um TipoEvento proprio, e nao o do
    comando, para o resultado sair numa routing-key diferente
    (<tipo>.evento.manifestacaorejeitada.<uf>.<cnpj>) -- quem assina
    "evento.ciencia" so' recebe ciencia de fato registrada. O payload de
    uma rejeicao e' o retorno bruto da SEFAZ (retEnvEvento), que traz a
    chave, o tpEvento e o cStat/xMotivo. Decidido pelo usuario em
    2026-09-18 (ver CLAUDE.md, decisao 18). }
  DFE_EVENTO_MANIFESTACAO_REJEITADA = 'manifestacaorejeitada';

  DFE_MANIFESTACAO_JUSTIFICATIVA_MIN = 15;
  DFE_MANIFESTACAO_JUSTIFICATIVA_MAX = 255;

type
  { Um comando de manifestacao, ja interpretado (ver InterpretarComando) --
    formato de origem (chave=valor no corpo da mensagem AMQP, mesmo estilo
    do arquivo de config) e' detalhe de quem produz isto, nao deste tipo. }
  TDFeComandoManifestacao = record
    Alias: string;          // qual certificado/unidade deve manifestar (ver TDFeOrquestrador.ObterUnidadePorAlias)
    ChaveAcesso: string;
    TipoEvento: string;     // 'confirmacao' | 'ciencia' | 'desconhecimento' | 'operacaonaorealizada'
    Justificativa: string;  // so' operacaonaorealizada (obrigatoria); nos demais e' ignorada
  end;

{ Interpreta o corpo de uma mensagem de comando (formato chave=valor, uma
  por linha -- mesmo estilo do arquivo de config). Levanta excecao se
  faltar Alias, ChaveAcesso ou TipoEvento; se TipoEvento nao for um dos
  quatro conhecidos; se ChaveAcesso nao tiver 44 digitos; ou se for
  operacaonaorealizada e a Justificativa vier vazia ou fora de 15..255
  caracteres. Nos outros tres tipos a Justificativa, se vier, e' DESCARTADA
  (a NT nao a aceita ali; descartar em vez de recusar mantem compativel quem
  ja mandava, pois a versao anterior a exigia no desconhecimento) --
  falha alto e cedo, antes de tentar falar com a SEFAZ (que rejeitaria o
  evento, ou o ACBr levantaria uma excecao generica de validacao de
  schema, dificil de distinguir de falha de comunicacao). }
function InterpretarComando(const APayload: string): TDFeComandoManifestacao;

{ True quando o cStat de UM evento (retEvento, nao o do lote) significa que a
  SEFAZ registrou a manifestacao: 135 (registrado e vinculado a NFe), 136
  (registrado, nao vinculado) e 155 (o mesmo criterio que o ACBr usa para
  montar o procEventoNFe, ver TNFeEnvEvento.TratarResposta). Qualquer outro
  valor -- inclusive 128, que e' cStat do LOTE -- e' rejeicao. Pura, para o
  criterio aceito/rejeitado ser testavel sem ACBr. }
function CStatEventoRegistrado(const ACStat: Integer): Boolean;

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
    orquestrador, verifica se o client dela suporta IDFeManifestador,
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
      processado (alias desconhecido, client sem suporte) ou quando
      EnviarEvento levanta uma das excecoes modeladas em DFe.Errors. }
    procedure RegistrarErro(const AComando: TDFeComandoManifestacao; const AMensagem: string); virtual;
  public
    constructor Create(const AOrquestrador: TDFeOrquestrador; const APublicador: IDFePublicador);

    { Processa um unico comando ja interpretado. Nunca levanta -- qualquer
      falha (alias desconhecido, client sem IDFeManifestador, excecao de
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
  I: Integer;
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

  if (Result.TipoEvento <> DFE_EVENTO_MANIFESTACAO_CONFIRMACAO)
    and (Result.TipoEvento <> DFE_EVENTO_MANIFESTACAO_CIENCIA)
    and (Result.TipoEvento <> DFE_EVENTO_MANIFESTACAO_DESCONHECIMENTO)
    and (Result.TipoEvento <> DFE_EVENTO_MANIFESTACAO_OPERACAO_NAO_REALIZADA) then
    raise Exception.CreateFmt('Comando de manifestacao com "TipoEvento" desconhecido: "%s"', [Result.TipoEvento]);

  if Length(Result.ChaveAcesso) <> 44 then
    raise Exception.Create('Comando de manifestacao com "ChaveAcesso" fora do formato de 44 digitos');
  for I := 1 to 44 do
    if not CharInSet(Result.ChaveAcesso[I], ['0'..'9']) then
      raise Exception.Create('Comando de manifestacao com "ChaveAcesso" fora do formato de 44 digitos');

  if Result.TipoEvento <> DFE_EVENTO_MANIFESTACAO_OPERACAO_NAO_REALIZADA then
    Result.Justificativa := ''
  else
  begin
    if Result.Justificativa = '' then
      raise Exception.CreateFmt('Comando de manifestacao "%s" exige "Justificativa"', [Result.TipoEvento]);
    if (Length(Result.Justificativa) < DFE_MANIFESTACAO_JUSTIFICATIVA_MIN)
      or (Length(Result.Justificativa) > DFE_MANIFESTACAO_JUSTIFICATIVA_MAX) then
      raise Exception.CreateFmt('"Justificativa" de "%s" deve ter de %d a %d caracteres',
        [Result.TipoEvento, DFE_MANIFESTACAO_JUSTIFICATIVA_MIN, DFE_MANIFESTACAO_JUSTIFICATIVA_MAX]);
  end;
end;

function CStatEventoRegistrado(const ACStat: Integer): Boolean;
begin
  Result := (ACStat = 135) or (ACStat = 136) or (ACStat = 155);
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

  if not Supports(LUnidade.Client, IDFeManifestador, LManifestador) then
  begin
    RegistrarErro(AComando, Format('Client do alias "%s" (provider "%s") nao suporta manifestacao', [AComando.Alias, LUnidade.Provider.Identificador]));
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
    on E: EDFeAmbienteIndisponivel do
    begin
      RegistrarErro(AComando, 'Ambiente de execucao incompleto: ' + E.Message);
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
  LComando.TipoEvento := DFE_EVENTO_MANIFESTACAO_CIENCIA;
  LComando.Justificativa := '';
  FProcessador.ProcessarComando(LComando);
end;

end.
