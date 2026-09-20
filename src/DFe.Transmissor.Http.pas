unit DFe.Transmissor.Http;

{$I dfe.inc}

{ IDFeTransmissor que leva o envelope a um SIMULADOR da SEFAZ em OUTRO
  PROCESSO, por HTTP (ver docs/simulador-standalone.md, Fase A).

  O ACBr continua montando o envelope com a URL OFICIAL da SEFAZ; aqui essa
  URL vira so' o CAMINHO sob a base do simulador (a base e' o que o usuario
  configura). O simulador roteia por caminho, entao o adaptador SOAP dele
  funciona sem mudanca.

  Esta unit e' PURA: a logica (URL, traducao de falha, texto) fica aqui e o
  HTTP de verdade fica atras de IDFeHttpPost (DFe.Transmissor.Http.Cliente),
  o que a torna testavel sem rede.

  Texto: o envelope chega na convencao do ACBr (no Delphi, bytes UTF-8 vistos
  como caracteres ANSI). IDFeHttpPost trabalha com texto NATIVO e cuida de
  UTF-8 na rede; a conversao e' feita aqui com TextoDoAcbr/TextoParaAcbr
  (DFe.XmlTexto), a unica fronteira com o ACBr. }

interface

uses
  SysUtils,
  DFe.Types,
  DFe.Transmissor;

const
  { Codigo de falha "sem resposta HTTP" (recusa/queda de conexao etc.) que o
    transmissor devolve em InternalErrorCode -- qualquer valor <> 0 faz o ACBr
    levantar excecao (que o client traduz em EDFeComunicacaoFalhou). Nao e' o
    10060 (timeout) de proposito: esse so' quando o cliente HTTP souber que foi
    timeout. Ver DFe.Client.ACBrNFe.TratarFalhaDeChamada. }
  DFE_TRANSMISSAO_ERRO_REDE = 10061;

type
  { Resultado de um POST HTTP. Erro <> '' = nao houve resposta HTTP (conexao
    recusada, timeout, DNS...); Status e Corpo sao entao ignorados. }
  TDFeHttpResposta = record
    Status: Integer;
    Corpo: string;   // texto NATIVO (UTF-8 ja' decodificado no Delphi; bytes UTF-8 no FPC)
    Erro: string;
  end;

  { POST de um corpo de texto NATIVO; a codificacao em UTF-8 na rede e' da
    implementacao. NAO levanta excecao para falha de rede: devolve Erro. }
  IDFeHttpPost = interface
    ['{2D9A4B1C-7E63-4F58-A0C1-5B8E3D6F9A21}']
    function Postar(const AURL, AMimeType, ASoapAction,
      ACorpo: string): TDFeHttpResposta;
  end;

  TDFeTransmissorHttp = class(TInterfacedObject, IDFeTransmissor)
  private
    FBase: string;
    FPost: IDFeHttpPost;
    FRequisicoes: Integer;
    FUltimaURL: string;
  public
    { ABaseURL: esquema+host[:porta][/prefixo], ex. 'http://127.0.0.1:9200'.
      Levanta se vazia ou sem esquema, ou se APost = nil. }
    constructor Create(const ABaseURL: string; const APost: IDFeHttpPost);

    function Transmitir(const AEnvelope, AURL, ASoapAction,
      AMimeType: string): TDFeRespostaTransmissao;

    property Requisicoes: Integer read FRequisicoes;
    { URL efetivamente usada na ultima chamada (para log e teste). }
    property UltimaURL: string read FUltimaURL;
  end;

type
  TDFeUsoSimulador = (usNaoUsado, usPermitido, usRecusado);

{ Decide o que fazer com [dfe] SimuladorURL (ver docs/simulador-standalone.md,
  "Salvaguardas"). Um broker apontado para o simulador NAO conversa com a SEFAZ:
  em producao os documentos simplesmente nao chegariam, e sem nada visivel.
  - URL vazia: usNaoUsado (comportamento de sempre, AMensagem vazia);
  - homologacao: usPermitido, com um AVISO de que o transporte e' simulado;
  - producao: usRecusado, a menos que APermitirProducao (opcao explicita) --
    ai usPermitido, com um AVISO mais forte.
  AMensagem e' o texto para o log (AVISO) ou para a excecao (recusa). }
function DecidirUsoDoSimulador(const ASimuladorURL: string;
  const AAmbiente: TDFeAmbiente; const APermitirProducao: Boolean;
  out AMensagem: string): TDFeUsoSimulador;

{ A URL oficial (AURLOriginal) sob a base do simulador: descarta esquema, host
  e porta da original e mantem caminho + query. Uma original sem esquema ja' e'
  tratada como caminho. A barra final da base e' ignorada. }
function MontarURLDestino(const ABaseURL, AURLOriginal: string): string;

implementation

uses
  DFe.XmlTexto;

function MontarURLDestino(const ABaseURL, AURLOriginal: string): string;
var
  LBase, LCaminho: string;
  LPos: Integer;
begin
  LBase := ABaseURL;
  while (LBase <> '') and (LBase[Length(LBase)] = '/') do
    Delete(LBase, Length(LBase), 1);

  LCaminho := AURLOriginal;
  LPos := Pos('://', LCaminho);
  if LPos > 0 then
  begin
    Delete(LCaminho, 1, LPos + 2);
    LPos := Pos('/', LCaminho);
    if LPos > 0 then
      Delete(LCaminho, 1, LPos - 1)  // fica '/caminho?query'
    else
      LCaminho := '/';               // so' host
  end
  else if (LCaminho = '') or (LCaminho[1] <> '/') then
    LCaminho := '/' + LCaminho;

  Result := LBase + LCaminho;
end;

function DecidirUsoDoSimulador(const ASimuladorURL: string;
  const AAmbiente: TDFeAmbiente; const APermitirProducao: Boolean;
  out AMensagem: string): TDFeUsoSimulador;
begin
  AMensagem := '';
  if Trim(ASimuladorURL) = '' then
  begin
    Result := usNaoUsado;
    Exit;
  end;
  if AAmbiente = daHomologacao then
  begin
    Result := usPermitido;
    AMensagem := 'TRANSPORTE SIMULADO: as consultas vao para ' + Trim(ASimuladorURL) +
      ', NAO para a SEFAZ (SimuladorURL)';
  end
  else if APermitirProducao then
  begin
    Result := usPermitido;
    AMensagem := 'TRANSPORTE SIMULADO EM PRODUCAO (SimuladorPermitirProducao=true): as consultas vao para ' +
      Trim(ASimuladorURL) + ', NAO para a SEFAZ -- nenhum documento real chegara';
  end
  else
  begin
    Result := usRecusado;
    AMensagem := 'SimuladorURL esta definido, mas o ambiente e producao: o simulador substitui a SEFAZ e ' +
      'nenhum documento real chegaria. Use Ambiente=homologacao ou, se for de proposito, ' +
      'SimuladorPermitirProducao=true';
  end;
end;

constructor TDFeTransmissorHttp.Create(const ABaseURL: string;
  const APost: IDFeHttpPost);
begin
  inherited Create;
  if Trim(ABaseURL) = '' then
    raise Exception.Create('TDFeTransmissorHttp: URL base do simulador vazia');
  if Pos('://', ABaseURL) = 0 then
    raise Exception.CreateFmt(
      'TDFeTransmissorHttp: URL base "%s" sem esquema (esperado http://host:porta)', [ABaseURL]);
  if APost = nil then
    raise Exception.Create('TDFeTransmissorHttp: IDFeHttpPost nao informado');
  FBase := Trim(ABaseURL);
  FPost := APost;
end;

function TDFeTransmissorHttp.Transmitir(const AEnvelope, AURL, ASoapAction,
  AMimeType: string): TDFeRespostaTransmissao;
var
  LResp: TDFeHttpResposta;
begin
  Inc(FRequisicoes);
  FUltimaURL := MontarURLDestino(FBase, AURL);
  LResp := FPost.Postar(FUltimaURL, AMimeType, ASoapAction, TextoDoAcbr(AEnvelope));

  if LResp.Erro <> '' then
  begin
    Result.Texto := '';
    Result.HTTPResultCode := 0;
    Result.InternalErrorCode := DFE_TRANSMISSAO_ERRO_REDE;
    Exit;
  end;

  // Resposta HTTP de verdade (inclusive 500): o texto e o codigo seguem para o
  // ACBr, que decide o que fazer (o client traduz em DFe.Errors).
  Result.Texto := TextoParaAcbr(LResp.Corpo);
  Result.HTTPResultCode := LResp.Status;
  Result.InternalErrorCode := 0;
end;

end.
