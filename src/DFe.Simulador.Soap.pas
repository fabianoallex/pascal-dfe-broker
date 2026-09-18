unit DFe.Simulador.Soap;

{$I dfe.inc}

{ Camada 2 do simulador (docs/simulador-sefaz.md, Fase 3): um
  IDFeTransmissor que fala SOAP com o client ACBr REAL, no lugar do
  HTTP/TLS, a partir de TDFeSimuladorSefaz.

  Dois papeis:
  1. RESPONDER: transforma TDFeRespostaSimulada no envelope SOAP que a
     SEFAZ devolveria (formato conferido em execucao na Fase 0, achado 4)
     ou na falha de transporte equivalente.
  2. AFIRMAR sobre o REQUEST: le do envelope que o ACBr montou o CNPJ, a UF
     (cUFAutor), o ultNSU e confere URL, SoapAction e forma do corpo. O
     que nao bate vira uma VIOLACAO registrada (nao excecao -- excecao
     dentro de OnTransmit seria mascarada pela traducao de erros do
     client); os testes exigem QuantidadeViolacoes = 0. E' isto que pega
     erro de formato do que o ACBr envia.

  Puro (sem ACBr): testavel na suite normal. So' cobre a Distribuicao de
  DFe por ultNSU -- consulta por NSU/chave e RecepcaoEvento (Fase 4) sao
  registradas como violacao "nao suportado".

  Nao valida o request contra o XSD (o simulador nao carrega XSDs). }

interface

uses
  SysUtils,
  DFe.Transmissor,
  DFe.Simulador,
  DFe.Simulador.Codec;

type
  TDFeSimuladorTransmissor = class(TInterfacedObject, IDFeTransmissor)
  private
    FSimulador: TDFeSimuladorSefaz;
    FViolacoes: array of string;
    FRequisicoes: Integer;
    FUltimoEnvelope: string;
    procedure Violar(const AMensagem: string);
    procedure ConferirRequisicao(const AEnvelope, AURL, ASoapAction: string;
      out ACnpjCpf, AUF: string; out AUltimoNSU: Int64; out ATpAmb: string);
  public
    { O simulador NAO e' possuido (mesma regra de DFe.Simulador.Client). }
    constructor Create(const ASimulador: TDFeSimuladorSefaz);

    function Transmitir(const AEnvelope, AURL, ASoapAction,
      AMimeType: string): TDFeRespostaTransmissao;

    function QuantidadeViolacoes: Integer;
    function Violacao(const AIndice: Integer): string;
    { Todas as violacoes numa string, para mensagem de falha de teste. }
    function TodasViolacoes: string;
    property Requisicoes: Integer read FRequisicoes;
    property UltimoEnvelope: string read FUltimoEnvelope;
  end;

{ Conteudo do primeiro elemento <ATag>...</ATag> (sem atributos) de um XML;
  vazio se nao houver. Busca simples, sem parser -- mesmo criterio de
  DFe.Provider.NFe para folhas de schema fiscal fixo. }
function ExtrairTag(const AXml, ATag: string): string;

{ Sigla da UF a partir do codigo IBGE de cUFAutor; vazio se desconhecido. }
function SiglaDaUFPorCodigo(const ACodigo: string): string;

{ Envelope SOAP de resposta da Distribuicao de DFe para um lote. }
function MontarEnvelopeResposta(const AResposta: TDFeRespostaSimulada;
  const ATpAmb: string): string;

implementation

const
  NS_WSDL = 'http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe';
  NS_NFE = 'http://www.portalfiscal.inf.br/nfe';
  DH_RESP_FIXO = '2026-09-18T10:00:00-03:00';

function ExtrairTag(const AXml, ATag: string): string;
var
  LIni, LFim: Integer;
begin
  Result := '';
  LIni := Pos('<' + ATag + '>', AXml);
  if LIni = 0 then
    Exit;
  Inc(LIni, Length(ATag) + 2);
  LFim := Pos('</' + ATag + '>', Copy(AXml, LIni, MaxInt));
  if LFim = 0 then
    Exit;
  Result := Copy(AXml, LIni, LFim - 1);
end;

function SiglaDaUFPorCodigo(const ACodigo: string): string;
const
  CODIGOS: array[0..26] of string = (
    '11', '12', '13', '14', '15', '16', '17', '21', '22', '23', '24', '25',
    '26', '27', '28', '29', '31', '32', '33', '35', '41', '42', '43', '50',
    '51', '52', '53');
  SIGLAS: array[0..26] of string = (
    'RO', 'AC', 'AM', 'RR', 'PA', 'AP', 'TO', 'MA', 'PI', 'CE', 'RN', 'PB',
    'PE', 'AL', 'SE', 'BA', 'MG', 'ES', 'RJ', 'SP', 'PR', 'SC', 'RS', 'MS',
    'MT', 'GO', 'DF');
var
  I: Integer;
begin
  Result := '';
  for I := Low(CODIGOS) to High(CODIGOS) do
    if CODIGOS[I] = ACodigo then
    begin
      Result := SIGLAS[I];
      Exit;
    end;
end;

function Nsu15(const ANSU: Int64): string;
begin
  Result := Format('%.15d', [ANSU]);
end;

function EnvelopeSoap(const ACorpo: string): string;
begin
  Result := '<?xml version="1.0" encoding="utf-8"?>' +
    '<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" ' +
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
    'xmlns:xsd="http://www.w3.org/2001/XMLSchema"><soap:Body>' + ACorpo +
    '</soap:Body></soap:Envelope>';
end;

function MontarEnvelopeResposta(const AResposta: TDFeRespostaSimulada;
  const ATpAmb: string): string;
var
  I: Integer;
  LLote, LDocZip: string;
begin
  LLote := '';
  if Length(AResposta.Lote.Itens) > 0 then
  begin
    LLote := '<loteDistDFeInt>';
    for I := 0 to High(AResposta.Lote.Itens) do
    begin
      if AResposta.DocZipCorrompido and (I = 0) then
        LDocZip := MontarDocZipCorrompido(AResposta.Lote.Itens[I].XmlDecodificado)
      else
        LDocZip := MontarDocZip(AResposta.Lote.Itens[I].XmlDecodificado);
      LLote := LLote + '<docZip NSU="' + Nsu15(AResposta.Lote.Itens[I].NSU) +
        '" schema="' + AResposta.Lote.Itens[I].Schema + '">' + LDocZip + '</docZip>';
    end;
    LLote := LLote + '</loteDistDFeInt>';
  end;

  Result := EnvelopeSoap(
    '<nfeDistDFeInteresseResponse xmlns="' + NS_WSDL + '">' +
    '<nfeDistDFeInteresseResult>' +
    '<retDistDFeInt xmlns="' + NS_NFE + '" versao="1.01">' +
    '<tpAmb>' + ATpAmb + '</tpAmb><verAplic>SIMULADOR-1.0</verAplic>' +
    '<cStat>' + IntToStr(AResposta.Lote.CStat) + '</cStat>' +
    '<xMotivo>' + AResposta.Lote.XMotivo + '</xMotivo>' +
    '<dhResp>' + DH_RESP_FIXO + '</dhResp>' +
    '<ultNSU>' + Nsu15(AResposta.Lote.UltimoNSU) + '</ultNSU>' +
    '<maxNSU>' + Nsu15(AResposta.Lote.MaxNSU) + '</maxNSU>' +
    LLote + '</retDistDFeInt>' +
    '</nfeDistDFeInteresseResult></nfeDistDFeInteresseResponse>');
end;

{ TDFeSimuladorTransmissor }

constructor TDFeSimuladorTransmissor.Create(const ASimulador: TDFeSimuladorSefaz);
begin
  inherited Create;
  FSimulador := ASimulador;
end;

procedure TDFeSimuladorTransmissor.Violar(const AMensagem: string);
begin
  SetLength(FViolacoes, Length(FViolacoes) + 1);
  FViolacoes[High(FViolacoes)] := AMensagem;
end;

function TDFeSimuladorTransmissor.QuantidadeViolacoes: Integer;
begin
  Result := Length(FViolacoes);
end;

function TDFeSimuladorTransmissor.Violacao(const AIndice: Integer): string;
begin
  Result := FViolacoes[AIndice];
end;

function TDFeSimuladorTransmissor.TodasViolacoes: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(FViolacoes) do
  begin
    if I > 0 then
      Result := Result + '; ';
    Result := Result + FViolacoes[I];
  end;
end;

procedure TDFeSimuladorTransmissor.ConferirRequisicao(const AEnvelope, AURL,
  ASoapAction: string; out ACnpjCpf, AUF: string; out AUltimoNSU: Int64;
  out ATpAmb: string);
var
  LUltNSU, LCUF, LSufixo: string;
begin
  ACnpjCpf := '';
  AUF := '';
  AUltimoNSU := 0;
  ATpAmb := '2';

  if Pos('NFeDistribuicaoDFe', AURL) = 0 then
    Violar('URL inesperada para Distribuicao de DFe: ' + AURL);

  LSufixo := '/nfeDistDFeInteresse';
  if (Length(ASoapAction) < Length(LSufixo)) or
     (Copy(ASoapAction, Length(ASoapAction) - Length(LSufixo) + 1, MaxInt) <> LSufixo) then
    Violar('SoapAction inesperada: ' + ASoapAction);

  if Pos('<nfeDistDFeInteresse xmlns="' + NS_WSDL + '">', AEnvelope) = 0 then
    Violar('corpo SOAP sem <nfeDistDFeInteresse xmlns=".../wsdl/NFeDistribuicaoDFe">');
  if Pos('<distDFeInt xmlns="' + NS_NFE + '" versao="1.01">', AEnvelope) = 0 then
    Violar('sem <distDFeInt xmlns=".../nfe" versao="1.01">');

  if (Pos('<consNSU>', AEnvelope) > 0) or (Pos('<consChNFe>', AEnvelope) > 0) then
    Violar('consulta por NSU/chave: nao suportada pelo simulador');
  if Pos('<envEvento', AEnvelope) > 0 then
    Violar('RecepcaoEvento: nao suportada pelo simulador (Fase 4)');

  ATpAmb := ExtrairTag(AEnvelope, 'tpAmb');
  if (ATpAmb <> '1') and (ATpAmb <> '2') then
  begin
    Violar('tpAmb invalido: "' + ATpAmb + '"');
    ATpAmb := '2';
  end;

  LCUF := ExtrairTag(AEnvelope, 'cUFAutor');
  AUF := SiglaDaUFPorCodigo(LCUF);
  if AUF = '' then
    Violar('cUFAutor desconhecido: "' + LCUF + '"');

  ACnpjCpf := ExtrairTag(AEnvelope, 'CNPJ');
  if Length(ACnpjCpf) <> 14 then
    Violar('CNPJ nao tem 14 digitos: "' + ACnpjCpf + '"');

  if Pos('<distNSU>', AEnvelope) = 0 then
    Violar('sem <distNSU>');
  LUltNSU := ExtrairTag(AEnvelope, 'ultNSU');
  if Length(LUltNSU) <> 15 then
    Violar('ultNSU deveria ter 15 digitos: "' + LUltNSU + '"');
  AUltimoNSU := StrToInt64Def(LUltNSU, 0);
end;

function TDFeSimuladorTransmissor.Transmitir(const AEnvelope, AURL, ASoapAction,
  AMimeType: string): TDFeRespostaTransmissao;
var
  LCnpj, LUF, LTpAmb: string;
  LUltimoNSU: Int64;
  LResposta: TDFeRespostaSimulada;
begin
  Inc(FRequisicoes);
  FUltimoEnvelope := AEnvelope;
  ConferirRequisicao(AEnvelope, AURL, ASoapAction, LCnpj, LUF, LUltimoNSU, LTpAmb);

  Result.Texto := '';
  Result.HTTPResultCode := 200;
  Result.InternalErrorCode := 0;

  LResposta := FSimulador.Consultar(LCnpj, LUF, LUltimoNSU);
  case LResposta.Tipo of
    trsLote:
      Result.Texto := MontarEnvelopeResposta(LResposta, LTpAmb);
    trsTimeout:
      begin
        // sem resposta HTTP; 10060 = WSAETIMEDOUT (ver ACBrDFeWebService.EnviarDados)
        Result.HTTPResultCode := 0;
        Result.InternalErrorCode := 10060;
      end;
    trsErroHttp:
      begin
        // HTTP 500 com SOAP Fault, como um servidor ASMX com defeito
        Result.HTTPResultCode := 500;
        Result.Texto := EnvelopeSoap('<soap:Fault><soap:Code><soap:Value>soap:Receiver' +
          '</soap:Value></soap:Code><soap:Reason><soap:Text>Simulado: erro interno' +
          '</soap:Text></soap:Reason></soap:Fault>');
      end;
    trsCorpoIlegivel:
      Result.Texto := '<html><body>Bad Gateway (simulado)</body></html>';
  end;
end;

end.
