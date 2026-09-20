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

  Puro (sem ACBr): testavel na suite normal. Cobre a Distribuicao de DFe
  por ultNSU e a RecepcaoEvento da MANIFESTACAO DO DESTINATARIO (Fase 4:
  lote de um evento, os 4 tpEvento 210200/210210/210220/210240); consulta
  por NSU/chave e outros eventos sao registrados como violacao "nao
  suportado". Para o evento tambem afirma que a assinatura esta PRESENTE e
  bem formada (Signature depois de infEvento, Reference URI = Id,
  DigestValue/SignatureValue/X509Certificate nao vazios) -- a validade
  CRIPTOGRAFICA e' conferida nos testes de integracao, com o proprio ACBr
  (TDFeSSL.VerificarAssinatura), porque aqui nao ha OpenSSL.

  Nao valida o request contra o XSD (o simulador nao carrega XSDs). }

interface

uses
  SysUtils,
  StrUtils,
  DFe.Transmissor,
  DFe.Simulador,
  DFe.Simulador.Codec,
  DFe.XmlTexto;

type
  TDFeSimuladorTransmissor = class(TInterfacedObject, IDFeTransmissor)
  private
    FSimulador: TDFeSimuladorSefaz;
    FViolacoes: array of string;
    FRequisicoes: Integer;
    FUltimoEnvelope: string;
    FEstrito: Boolean;
    procedure Violar(const AMensagem: string);
    { Modo estrito: se a conferencia acabou de registrar violacao, a resposta e' a
      recusa (HTTP 400) e o estado do simulador NAO e' tocado. }
    function RecusaEstrita(const AViolacoesAntes: Integer;
      out AResposta: TDFeRespostaTransmissao): Boolean;
    procedure ConferirRequisicao(const AEnvelope, AURL, ASoapAction: string;
      out ACnpjCpf, AUF: string; out AUltimoNSU: Int64; out ATpAmb: string);
    procedure ConferirEvento(const AEnvelope, AURL, ASoapAction: string;
      out ACnpjDest, AChave, ATpEvento, ATpAmb, AIdLote: string; out ANSeq: Integer);
    function TransmitirEvento(const AEnvelope, AURL, ASoapAction: string): TDFeRespostaTransmissao;
  public
    { O simulador NAO e' possuido (mesma regra de DFe.Simulador.Client). }
    constructor Create(const ASimulador: TDFeSimuladorSefaz);

    function Transmitir(const AEnvelope, AURL, ASoapAction,
      AMimeType: string): TDFeRespostaTransmissao;

    { Padrao (False) = LENIENTE: a violacao so' e' registrada e a requisicao e'
      atendida -- o certo para um cliente de terceiros, que nao e' o ACBr.
      True = ESTRITO: requisicao com violacao e' recusada com HTTP 400 e nao
      consome NSU nem abre bloqueio -- para testar que o cliente manda o formato certo. }
    property Estrito: Boolean read FEstrito write FEstrito;
    { Esquece as violacoes registradas (nao zera o contador de requisicoes). }
    procedure LimparViolacoes;

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

{ Valor do atributo AAtributo do primeiro elemento <ATag ...>; vazio se
  nao houver. }
function ExtrairAtributo(const AXml, ATag, AAtributo: string): string;

{ Sigla da UF a partir do codigo IBGE de cUFAutor; vazio se desconhecido. }
function SiglaDaUFPorCodigo(const ACodigo: string): string;

{ Envelope SOAP de resposta da RecepcaoEvento (retEnvEvento) para o lote de
  um evento de manifestacao. }
function MontarEnvelopeRespostaEvento(const AResposta: TDFeRespostaEventoSimulada;
  const AIdLote, ATpAmb, AChave, ATpEvento: string; const ANSeq: Integer;
  const ACnpjDest: string): string;

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

function ExtrairAtributo(const AXml, ATag, AAtributo: string): string;
var
  LIni, LFim: Integer;
  LResto: string;
begin
  Result := '';
  LIni := Pos('<' + ATag + ' ', AXml);
  if LIni = 0 then
    Exit;
  LResto := Copy(AXml, LIni, MaxInt);
  LIni := Pos(' ' + AAtributo + '="', LResto);
  if (LIni = 0) or (LIni > Pos('>', LResto)) then
    Exit;
  Inc(LIni, Length(AAtributo) + 3);
  LFim := Pos('"', Copy(LResto, LIni, MaxInt));
  if LFim = 0 then
    Exit;
  Result := Copy(LResto, LIni, LFim - 1);
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
    Violar('envEvento enviado para a Distribuicao de DFe');

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

procedure TDFeSimuladorTransmissor.LimparViolacoes;
begin
  SetLength(FViolacoes, 0);
end;

function TDFeSimuladorTransmissor.RecusaEstrita(const AViolacoesAntes: Integer;
  out AResposta: TDFeRespostaTransmissao): Boolean;
var
  I: Integer;
  LTexto: string;
begin
  Result := FEstrito and (Length(FViolacoes) > AViolacoesAntes);
  if not Result then
    Exit;
  LTexto := '';
  for I := AViolacoesAntes to High(FViolacoes) do
  begin
    if LTexto <> '' then
      LTexto := LTexto + '; ';
    LTexto := LTexto + FViolacoes[I];
  end;
  AResposta.Texto := 'Requisicao recusada (modo estrito): ' + LTexto;
  AResposta.HTTPResultCode := 400;
  AResposta.InternalErrorCode := 0;
end;

function TDFeSimuladorTransmissor.Transmitir(const AEnvelope, AURL, ASoapAction,
  AMimeType: string): TDFeRespostaTransmissao;
var
  LCnpj, LUF, LTpAmb: string;
  LUltimoNSU: Int64;
  LResposta: TDFeRespostaSimulada;
  LAntes: Integer;
begin
  Inc(FRequisicoes);
  FUltimoEnvelope := AEnvelope;
  if Pos('<envEvento', AEnvelope) > 0 then
  begin
    Result := TransmitirEvento(AEnvelope, AURL, ASoapAction);
    Exit;
  end;
  LAntes := Length(FViolacoes);
  ConferirRequisicao(AEnvelope, AURL, ASoapAction, LCnpj, LUF, LUltimoNSU, LTpAmb);
  if RecusaEstrita(LAntes, Result) then
    Exit;

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

function DescEventoEsperado(const ATpEvento: string): string;
begin
  if ATpEvento = '210200' then Result := 'confirmacao da operacao'
  else if ATpEvento = '210210' then Result := 'ciencia da operacao'
  else if ATpEvento = '210220' then Result := 'desconhecimento da operacao'
  else if ATpEvento = '210240' then Result := 'operacao nao realizada'
  else Result := '';
end;

function SoDigitos(const S: string): Boolean;
var
  I: Integer;
begin
  Result := S <> '';
  for I := 1 to Length(S) do
    if (S[I] < '0') or (S[I] > '9') then
      Result := False;
end;

function FusoDaNT(const ADhEvento: string): Boolean;
var
  LFuso: string;
begin
  LFuso := Copy(ADhEvento, Length(ADhEvento) - 5, 6);
  Result := (LFuso = '-02:00') or (LFuso = '-03:00') or (LFuso = '-04:00');
end;

function DhEventoValido(const S: string): Boolean;
begin
  // 2026-09-18T18:44:03-03:00
  Result := (Length(S) = 25) and (S[5] = '-') and (S[8] = '-') and (S[11] = 'T') and
    (S[14] = ':') and (S[17] = ':') and ((S[20] = '-') or (S[20] = '+')) and (S[23] = ':') and
    SoDigitos(Copy(S, 1, 4) + Copy(S, 6, 2) + Copy(S, 9, 2) + Copy(S, 12, 2) +
      Copy(S, 15, 2) + Copy(S, 18, 2) + Copy(S, 21, 2) + Copy(S, 24, 2));
end;

procedure TDFeSimuladorTransmissor.ConferirEvento(const AEnvelope, AURL,
  ASoapAction: string; out ACnpjDest, AChave, ATpEvento, ATpAmb, AIdLote: string;
  out ANSeq: Integer);
var
  LId, LSeq, LDesc, LSig, LUri, LOrgao, LEsperadoId, LSufixo, LXJust: string;
  LPosInfFim, LPosSig, LN, LPos: Integer;
begin
  if Pos('NFeRecepcaoEvento4', AURL) = 0 then
    Violar('URL inesperada para RecepcaoEvento: ' + AURL);

  LSufixo := '/nfeRecepcaoEvento';
  if (Length(ASoapAction) < Length(LSufixo)) or
     (Copy(ASoapAction, Length(ASoapAction) - Length(LSufixo) + 1, MaxInt) <> LSufixo) then
    Violar('SoapAction de evento inesperada: ' + ASoapAction);

  if Pos('<nfeDadosMsg xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeRecepcaoEvento4">', AEnvelope) = 0 then
    Violar('sem <nfeDadosMsg xmlns=".../wsdl/NFeRecepcaoEvento4">');
  if Pos('<envEvento xmlns="' + NS_NFE + '" versao="1.00">', AEnvelope) = 0 then
    Violar('sem <envEvento xmlns=".../nfe" versao="1.00">');

  AIdLote := ExtrairTag(AEnvelope, 'idLote');
  if not SoDigitos(AIdLote) then
  begin
    Violar('idLote invalido: "' + AIdLote + '"');
    AIdLote := '1';
  end;

  // lote de UM evento (e' assim que o client envia a manifestacao)
  LN := 0;
  LPos := Pos('<evento ', AEnvelope);
  while LPos > 0 do
  begin
    Inc(LN);
    LPos := PosEx('<evento ', AEnvelope, LPos + 1);
  end;
  if LN <> 1 then
    Violar('esperava 1 <evento> no lote, achei ' + IntToStr(LN));

  LOrgao := ExtrairTag(AEnvelope, 'cOrgao');
  if LOrgao <> '91' then
    Violar('manifestacao vai ao Ambiente Nacional: cOrgao deveria ser 91, veio "' + LOrgao + '"');

  ATpAmb := ExtrairTag(AEnvelope, 'tpAmb');
  if (ATpAmb <> '1') and (ATpAmb <> '2') then
  begin
    Violar('tpAmb invalido: "' + ATpAmb + '"');
    ATpAmb := '2';
  end;

  ACnpjDest := ExtrairTag(AEnvelope, 'CNPJ');
  if (Length(ACnpjDest) <> 14) or not SoDigitos(ACnpjDest) then
    Violar('CNPJ do destinatario (certificado) deveria ter 14 digitos: "' + ACnpjDest + '"');

  AChave := ExtrairTag(AEnvelope, 'chNFe');
  if (Length(AChave) <> 44) or not SoDigitos(AChave) then
    Violar('chNFe deveria ter 44 digitos: "' + AChave + '"');

  ATpEvento := ExtrairTag(AEnvelope, 'tpEvento');
  LDesc := DescEventoEsperado(ATpEvento);
  if LDesc = '' then
    Violar('tpEvento nao e'' manifestacao do destinatario: "' + ATpEvento + '"');

  LSeq := ExtrairTag(AEnvelope, 'nSeqEvento');
  ANSeq := StrToIntDef(LSeq, 0);
  if ANSeq < 1 then
  begin
    Violar('nSeqEvento invalido: "' + LSeq + '"');
    ANSeq := 1;
  end;

  if ExtrairTag(AEnvelope, 'verEvento') <> '1.00' then
    Violar('verEvento deveria ser 1.00');
  if not DhEventoValido(ExtrairTag(AEnvelope, 'dhEvento')) then
    Violar('dhEvento fora do formato AAAA-MM-DDThh:mm:ss+-hh:mm: "' +
      ExtrairTag(AEnvelope, 'dhEvento') + '"')
  else if not FusoDaNT(ExtrairTag(AEnvelope, 'dhEvento')) then
    // O XSD (TDateTimeUTC) aceitaria +-hh:00 qualquer; a NT 2012/002 (HP13) so' lista
    // -02:00/-03:00/-04:00. "+00:00" (UTC) e' o que o ACBr escreve num sistema cujo
    // relogio e' UTC (FPC/Linux) -- a SEFAZ real pode recusar; nao verificado.
    Violar('dhEvento com fuso fora da lista da NT 2012/002 (-02:00, -03:00, -04:00): "' +
      ExtrairTag(AEnvelope, 'dhEvento') + '"');

  // descEvento coerente com o tpEvento (o ACBr manda sem acento)
  if (LDesc <> '') and (LowerCase(ExtrairTag(AEnvelope, 'descEvento')) <> LDesc) then
    Violar('descEvento "' + ExtrairTag(AEnvelope, 'descEvento') + '" nao bate com tpEvento ' + ATpEvento);

  // xJust (NT 2012/002, HP20): "deve ser informado SOMENTE no evento de Operacao
  // nao Realizada" (210240), com 15 a 255 CARACTERES (nao bytes: o client preserva
  // os acentos, e no FPC um acento sao 2 bytes); o tipo TMotivo do XSD so' admite
  // U+0020..U+00FF. Nos demais tipos nao pode ir. TextoDoAcbr: o envelope e' o que
  // o ACBr entregou (no Delphi, UTF-8 embutido em String).
  LXJust := TextoDoAcbr(ExtrairTag(AEnvelope, 'xJust'));
  if ATpEvento = '210240' then
  begin
    if LXJust = '' then
      Violar('210240 (Operacao nao Realizada) exige xJust (rejeicao 595 na SEFAZ)')
    else if (TamanhoEmCaracteres(LXJust) < 15) or (TamanhoEmCaracteres(LXJust) > 255) then
      Violar('xJust deve ter de 15 a 255 caracteres, tem ' + IntToStr(TamanhoEmCaracteres(LXJust)))
    else if not TextoAceitoPeloXsdDeMotivo(LXJust) then
      Violar('xJust tem caractere fora de U+0020..U+00FF (o XSD TMotivo rejeita)');
  end
  else if LXJust <> '' then
    Violar('xJust so'' pode ser informado em 210240 (Operacao nao Realizada), veio em ' + ATpEvento);

  // Id = "ID" + tpEvento + chNFe + nSeqEvento com 2 digitos
  LId := ExtrairAtributo(AEnvelope, 'infEvento', 'Id');
  LEsperadoId := 'ID' + ATpEvento + AChave + Format('%.2d', [ANSeq]);
  if LId <> LEsperadoId then
    Violar('infEvento/@Id "' + LId + '" deveria ser "' + LEsperadoId + '"');

  // assinatura presente e bem formada (validade criptografica: teste de integracao)
  LPosInfFim := Pos('</infEvento>', AEnvelope);
  LPosSig := Pos('<Signature xmlns="http://www.w3.org/2000/09/xmldsig#">', AEnvelope);
  if LPosSig = 0 then
    Violar('evento sem <Signature> XMLDSig')
  else
  begin
    if (LPosInfFim = 0) or (LPosSig < LPosInfFim) then
      Violar('<Signature> deveria vir depois de </infEvento>');
    LSig := Copy(AEnvelope, LPosSig, MaxInt);
    LUri := ExtrairAtributo(LSig, 'Reference', 'URI');
    if LUri <> '#' + LEsperadoId then
      Violar('Reference/@URI "' + LUri + '" deveria apontar para "#' + LEsperadoId + '"');
    if ExtrairTag(LSig, 'DigestValue') = '' then Violar('assinatura sem DigestValue');
    if ExtrairTag(LSig, 'SignatureValue') = '' then Violar('assinatura sem SignatureValue');
    if ExtrairTag(LSig, 'X509Certificate') = '' then Violar('assinatura sem X509Certificate');
    if Pos('rsa-sha1', LSig) = 0 then Violar('SignatureMethod deveria ser rsa-sha1 (exigido pela SEFAZ)');
  end;
end;

function DhRegFormatado(const ADh: TDateTime): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', ADh) + '-03:00';
end;

function MontarEnvelopeRespostaEvento(const AResposta: TDFeRespostaEventoSimulada;
  const AIdLote, ATpAmb, AChave, ATpEvento: string; const ANSeq: Integer;
  const ACnpjDest: string): string;
var
  LRetEvento, LNProt, LDh: string;
begin
  LRetEvento := '';
  if AResposta.TemEvento then
  begin
    LNProt := '';
    LDh := '';
    if AResposta.NProt <> '' then // registrado (135/136)
    begin
      LNProt := '<nProt>' + AResposta.NProt + '</nProt>';
      LDh := '<dhRegEvento>' + DhRegFormatado(AResposta.DhRegEvento) + '</dhRegEvento>';
    end;
    LRetEvento := '<retEvento versao="1.00"><infEvento><tpAmb>' + ATpAmb + '</tpAmb>' +
      '<verAplic>SIMULADOR-1.0</verAplic><cOrgao>91</cOrgao>' +
      '<cStat>' + IntToStr(AResposta.CStat) + '</cStat>' +
      '<xMotivo>' + AResposta.XMotivo + '</xMotivo>' +
      '<chNFe>' + AChave + '</chNFe><tpEvento>' + ATpEvento + '</tpEvento>' +
      '<xEvento>' + DescEventoEsperado(ATpEvento) + '</xEvento>' +
      '<nSeqEvento>' + IntToStr(ANSeq) + '</nSeqEvento>' +
      '<CNPJDest>' + ACnpjDest + '</CNPJDest>' + LDh + LNProt +
      '</infEvento></retEvento>';
  end;

  Result := EnvelopeSoap(
    '<nfeResultMsg xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeRecepcaoEvento4">' +
    '<retEnvEvento xmlns="' + NS_NFE + '" versao="1.00"><idLote>' + AIdLote + '</idLote>' +
    '<tpAmb>' + ATpAmb + '</tpAmb><verAplic>SIMULADOR-1.0</verAplic><cOrgao>91</cOrgao>' +
    '<cStat>' + IntToStr(AResposta.CStatLote) + '</cStat>' +
    '<xMotivo>' + AResposta.XMotivoLote + '</xMotivo>' + LRetEvento +
    '</retEnvEvento></nfeResultMsg>');
end;

function TDFeSimuladorTransmissor.TransmitirEvento(const AEnvelope, AURL,
  ASoapAction: string): TDFeRespostaTransmissao;
var
  LCnpj, LChave, LTpEvento, LTpAmb, LIdLote: string;
  LNSeq: Integer;
  LResposta: TDFeRespostaEventoSimulada;
  LAntes: Integer;
begin
  LAntes := Length(FViolacoes);
  ConferirEvento(AEnvelope, AURL, ASoapAction, LCnpj, LChave, LTpEvento, LTpAmb, LIdLote, LNSeq);
  if RecusaEstrita(LAntes, Result) then
    Exit;

  Result.Texto := '';
  Result.HTTPResultCode := 200;
  Result.InternalErrorCode := 0;

  LResposta := FSimulador.ReceberEvento(LCnpj, LChave, LTpEvento, LNSeq);
  case LResposta.Tipo of
    trsLote:
      Result.Texto := MontarEnvelopeRespostaEvento(LResposta, LIdLote, LTpAmb, LChave,
        LTpEvento, LNSeq, LCnpj);
    trsTimeout:
      begin
        Result.HTTPResultCode := 0;
        Result.InternalErrorCode := 10060;
      end;
    trsErroHttp:
      begin
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
