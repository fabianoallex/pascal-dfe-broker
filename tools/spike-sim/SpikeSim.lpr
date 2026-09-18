program SpikeSim;

{ FASE 0 do simulador da SEFAZ (docs/simulador-sefaz.md) -- SPIKE DESCARTAVEL.
  Objetivo: transformar as hipoteses 1-4 em fatos. Liga TACBrNFe.OnTransmit
  (dentro do TDFeDistribuicaoClientACBrNFe REAL) a respostas roteirizadas e
  chama Consultar. Nao e' o simulador -- nada aqui e' reaproveitavel como
  esta (gzip via ACBrCompress, cenarios soltos). Desde a Fase 1 usa a
  costura oficial IDFeTransmissor (DFe.Transmissor) em vez do acesso ao
  campo privado por offset da primeira versao.

  Uso: SpikeSim <arquivo.pfx> <senha> }

{$mode delphi}{$H+}

uses
  Interfaces,
  SysUtils,
  ACBrCompress,
  ACBrDFe.Conversao,
  synacode,
  DFe.Transmissor,
  DFe.Types,
  DFe.Errors,
  DFe.Provider,
  DFe.Client.ACBrNFe;

type
  TCenario = (cenSemNovidade, cenComDocumento, cenConsumoIndevido, cenTimeout,
    cenHttp500, cenCorpoIlegivel);

  TSpike = class(TInterfacedObject, IDFeTransmissor)
    Cenario: TCenario;
    function Transmitir(const AEnvelope, AURL, ASoapAction,
      AMimeType: string): TDFeRespostaTransmissao;
  end;

const
  NS_WSDL = 'http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe';
  CNPJ_TESTE = '11222333000181';

function Envelope(const ARetDist: string): string;
begin
  Result := '<?xml version="1.0" encoding="utf-8"?>' +
    '<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" ' +
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
    'xmlns:xsd="http://www.w3.org/2001/XMLSchema"><soap:Body>' +
    '<nfeDistDFeInteresseResponse xmlns="' + NS_WSDL + '">' +
    '<nfeDistDFeInteresseResult>' + ARetDist +
    '</nfeDistDFeInteresseResult></nfeDistDFeInteresseResponse>' +
    '</soap:Body></soap:Envelope>';
end;

function RetDist(const ACStat, AMotivo, AUlt, AMax, ALote: string): string;
begin
  Result := '<retDistDFeInt xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.01">' +
    '<tpAmb>2</tpAmb><verAplic>1.7.6</verAplic><cStat>' + ACStat + '</cStat>' +
    '<xMotivo>' + AMotivo + '</xMotivo><dhResp>2026-09-18T10:00:00-03:00</dhResp>' +
    '<ultNSU>' + AUlt + '</ultNSU><maxNSU>' + AMax + '</maxNSU>' + ALote +
    '</retDistDFeInt>';
end;

function DocZip: string;
var
  LXml: AnsiString;
begin
  { xNome com acentos, em bytes UTF-8 explicitos (E = C3 89, C = C3 87, I = C3 8D) }
  LXml := '<resNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.01">' +
    '<chNFe>35260911222333000181550010000000011000000019</chNFe>' +
    '<CNPJ>11222333000181</CNPJ><xNome>JOS'#$C3#$89' A'#$C3#$87'A'#$C3#$8D' LTDA</xNome>' +
    '<IE>123456789</IE><dhEmi>2026-09-17T09:30:00-03:00</dhEmi><tpNF>1</tpNF>' +
    '<vNF>100.00</vNF><digVal>abc=</digVal><dhRecbto>2026-09-17T09:31:00-03:00</dhRecbto>' +
    '<nProt>135260000000001</nProt><cSitNFe>1</cSitNFe></resNFe>';
  Result := '<loteDistDFeInt><docZip NSU="000000000000001" schema="resNFe_v1.01.xsd">' +
    string(EncodeBase64(GZipCompress(LXml))) + '</docZip></loteDistDFeInt>';
end;

function TSpike.Transmitir(const AEnvelope, AURL, ASoapAction,
  AMimeType: string): TDFeRespostaTransmissao;
begin
  WriteLn('  [Transmitir] URL=', AURL);
  WriteLn('  [Transmitir] SoapAction=', ASoapAction, '  MimeType="', AMimeType, '"');
  WriteLn('  [Transmitir] Envelope=', AEnvelope);
  Result.Texto := '';
  Result.HTTPResultCode := 200;
  Result.InternalErrorCode := 0;
  case Cenario of
    cenSemNovidade:
      Result.Texto := Envelope(RetDist('137', 'Nenhum documento localizado', '000000000000000', '000000000000000', ''));
    cenComDocumento:
      Result.Texto := Envelope(RetDist('138', 'Documento localizado', '000000000000001', '000000000000001', DocZip));
    cenConsumoIndevido:
      Result.Texto := Envelope(RetDist('656', 'Rejeicao: Consumo Indevido', '000000000000000', '000000000000000', ''));
    cenTimeout:
      begin
        Result.HTTPResultCode := 0;
        Result.InternalErrorCode := 10060;
      end;
    cenHttp500:
      begin
        Result.HTTPResultCode := 500;
        Result.InternalErrorCode := 12345; // erro interno qualquer, sem corpo
      end;
    cenCorpoIlegivel:
      Result.Texto := '<html><body>Bad Gateway</body></html>';
  end;
end;

function HexDump(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    Result := Result + IntToHex(Ord(S[I]), 2) + ' ';
end;

procedure Rodar(const AClient: IDFeDistribuicaoClient; ASpike: TSpike;
  ACenario: TCenario; const ANome: string; const ACert: TDFeCertificado);
var
  LLote: TDFeLoteBruto;
  I, P: Integer;
  LX: string;
begin
  WriteLn;
  WriteLn('=== ', ANome, ' ===');
  ASpike.Cenario := ACenario;
  try
    LLote := AClient.Consultar(ACert, 0);
    WriteLn('  Consultar OK: cStat=', LLote.CStat, ' xMotivo="', LLote.XMotivo,
      '" ultNSU=', LLote.UltimoNSU, ' maxNSU=', LLote.MaxNSU, ' itens=', Length(LLote.Itens));
    for I := 0 to High(LLote.Itens) do
    begin
      LX := LLote.Itens[I].XmlDecodificado;
      WriteLn('  item NSU=', LLote.Itens[I].NSU, ' schema=', LLote.Itens[I].Schema);
      WriteLn('  xml=', LX);
      P := Pos('<xNome>', LX);
      if P > 0 then
        WriteLn('  bytes de xNome: ', HexDump(Copy(LX, P, 22)));
    end;
  except
    on E: Exception do
      WriteLn('  EXCECAO ', E.ClassName, ': ', E.Message);
  end;
end;

var
  LClient: IDFeDistribuicaoClient;
  LSpike: TSpike;
  LTransmissor: IDFeTransmissor;
  LCred: TDFeCredencialCertificado;
  LCert: TDFeCertificado;
begin
  if ParamCount < 2 then
  begin
    WriteLn('uso: SpikeSim <arquivo.pfx> <senha>');
    Halt(2);
  end;

  LCred.ArquivoPFX := ParamStr(1);
  LCred.Senha := ParamStr(2);
  LCert.Identificador := 'teste';
  LCert.CnpjCpf := CNPJ_TESTE;
  LCert.UF := 'RS';

  LSpike := TSpike.Create;
  LTransmissor := LSpike; // dono do ciclo de vida (contagem de referencia)
  LClient := TDFeDistribuicaoClientACBrNFe.Create(LCred, taHomologacao, LTransmissor);
  begin
    Rodar(LClient, LSpike, cenSemNovidade, '137 sem novidade', LCert);
    Rodar(LClient, LSpike, cenComDocumento, '138 com 1 docZip (xNome acentuado)', LCert);
    Rodar(LClient, LSpike, cenConsumoIndevido, '656 consumo indevido', LCert);
    Rodar(LClient, LSpike, cenTimeout, 'timeout (10060)', LCert);
    Rodar(LClient, LSpike, cenHttp500, 'HTTP 500 / erro interno', LCert);
    Rodar(LClient, LSpike, cenCorpoIlegivel, 'HTTP 200 com corpo ilegivel', LCert);
    { repete um sucesso apos falhas: mostra se HTTPResultCode/estado ficou velho }
    Rodar(LClient, LSpike, cenSemNovidade, '137 de novo (apos falhas)', LCert);

    { certificado com CNPJ divergente }
    LCert.CnpjCpf := '11444777000161';
    Rodar(LClient, LSpike, cenSemNovidade, 'CNPJ divergente do certificado', LCert);
  end;
end.
