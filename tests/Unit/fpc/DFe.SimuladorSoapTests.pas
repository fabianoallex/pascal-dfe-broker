unit DFe.SimuladorSoapTests;

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils,
  DFe.Transmissor,
  DFe.Simulador,
  DFe.Simulador.Soap,
  DFe.Simulador.Fixtures,
  DFe.TestDoubles;

type
  TDFeSimuladorSoapTests = class(TTestCase)
  private
    FRelogio: TDFeRelogioFake;
    FSim: TDFeSimuladorSefaz;
    FTransmissor: TDFeSimuladorTransmissor;
    FIntf: IDFeTransmissor; // dono do ciclo de vida do transmissor
    function Requisicao(const AUltNSU: string; const ACnpj: string = '11222333000181';
      const ACUF: string = '43'): string;
    function Transmitir(const AEnvelope: string;
      const AURL: string = 'https://hom1.nfe.fazenda.gov.br/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx';
      const ASoapAction: string = 'http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe/nfeDistDFeInteresse'): TDFeRespostaTransmissao;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ExtrairTag_DevolveConteudoOuVazio;
    procedure SiglaDaUF_ConhecidaEDesconhecida;
    procedure RequisicaoDoAcbr_NaoGeraViolacao;
    procedure Envelope137_TemOsCamposQueOAcbrLe;
    procedure Envelope138_TemDocZipComGzipEmBase64;
    procedure DocZipCorrompido_AfetaSoOPrimeiroItem;
    procedure UltNSUDaRequisicao_FiltraOsDocumentos;
    procedure CnpjEUfDaRequisicao_SelecionamAConta;
    procedure Timeout_DevolveCodigoInterno10060;
    procedure ErroHttp_Devolve500ComSoapFault;
    procedure CorpoIlegivel_Devolve200ComHtml;
    procedure Violacao_UrlSoapActionEForma;
    procedure Violacao_UltNSUCurtoEModoNaoSuportado;
    procedure Violacao_UfDesconhecidaECnpjCurto;
  end;

implementation

const
  RAIZ_SOAP = '<?xml version="1.0" encoding="UTF-8"?><soap12:Envelope ' +
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
    'xmlns:xsd="http://www.w3.org/2001/XMLSchema" ' +
    'xmlns:soap12="http://www.w3.org/2003/05/soap-envelope"><soap12:Body>';

{ TDFeSimuladorSoapTests }

procedure TDFeSimuladorSoapTests.SetUp;
begin
  FRelogio := TDFeRelogioFake.Create;
  FRelogio.Agora := EncodeDate(2026, 9, 18) + EncodeTime(10, 0, 0, 0);
  FSim := TDFeSimuladorSefaz.Create(FRelogio.ObterAgora);
  FTransmissor := TDFeSimuladorTransmissor.Create(FSim);
  FIntf := FTransmissor;
end;

procedure TDFeSimuladorSoapTests.TearDown;
begin
  FIntf := nil; // libera o transmissor antes do simulador
  FTransmissor := nil;
  FSim.Free;
  FRelogio.Free;
end;

{ Requisicao no formato exato que o ACBr emitiu no spike da Fase 0. }
function TDFeSimuladorSoapTests.Requisicao(const AUltNSU, ACnpj, ACUF: string): string;
begin
  Result := RAIZ_SOAP +
    '<nfeDistDFeInteresse xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe">' +
    '<nfeDadosMsg><distDFeInt xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.01">' +
    '<tpAmb>2</tpAmb><cUFAutor>' + ACUF + '</cUFAutor><CNPJ>' + ACnpj + '</CNPJ>' +
    '<distNSU><ultNSU>' + AUltNSU + '</ultNSU></distNSU></distDFeInt></nfeDadosMsg>' +
    '</nfeDistDFeInteresse></soap12:Body></soap12:Envelope>';
end;

function TDFeSimuladorSoapTests.Transmitir(const AEnvelope, AURL, ASoapAction: string): TDFeRespostaTransmissao;
begin
  Result := FIntf.Transmitir(AEnvelope, AURL, ASoapAction, '');
end;

procedure TDFeSimuladorSoapTests.ExtrairTag_DevolveConteudoOuVazio;
begin
  AssertEquals('123', ExtrairTag('<a><ultNSU>123</ultNSU></a>', 'ultNSU'));
  AssertEquals('', ExtrairTag('<a></a>', 'ultNSU'));
  AssertEquals('', ExtrairTag('<a><ultNSU>sem fecho', 'ultNSU'));
  AssertEquals('1', ExtrairTag('<x><CNPJ>1</CNPJ><CNPJ>2</CNPJ></x>', 'CNPJ'));
end;

procedure TDFeSimuladorSoapTests.SiglaDaUF_ConhecidaEDesconhecida;
begin
  AssertEquals('RS', SiglaDaUFPorCodigo('43'));
  AssertEquals('SP', SiglaDaUFPorCodigo('35'));
  AssertEquals('DF', SiglaDaUFPorCodigo('53'));
  AssertEquals('', SiglaDaUFPorCodigo('99'));
  AssertEquals('', SiglaDaUFPorCodigo(''));
end;

procedure TDFeSimuladorSoapTests.RequisicaoDoAcbr_NaoGeraViolacao;
begin
  Transmitir(Requisicao('000000000000000'));
  AssertEquals(FTransmissor.TodasViolacoes, 0, FTransmissor.QuantidadeViolacoes);
  AssertEquals(1, FTransmissor.Requisicoes);
end;

procedure TDFeSimuladorSoapTests.Envelope137_TemOsCamposQueOAcbrLe;
var
  R: TDFeRespostaTransmissao;
begin
  R := Transmitir(Requisicao('000000000000000'));
  AssertEquals(200, R.HTTPResultCode);
  AssertEquals(0, R.InternalErrorCode);
  AssertTrue(Pos('<nfeDistDFeInteresseResult>', R.Texto) > 0);
  AssertTrue(Pos('<retDistDFeInt xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.01">', R.Texto) > 0);
  AssertTrue(Pos('<cStat>137</cStat>', R.Texto) > 0);
  AssertTrue(Pos('<tpAmb>2</tpAmb>', R.Texto) > 0);
  AssertTrue(Pos('<ultNSU>000000000000000</ultNSU>', R.Texto) > 0);
  AssertTrue(Pos('<maxNSU>000000000000000</maxNSU>', R.Texto) > 0);
  AssertTrue(Pos('<loteDistDFeInt>', R.Texto) = 0);
end;

procedure TDFeSimuladorSoapTests.Envelope138_TemDocZipComGzipEmBase64;
var
  R: TDFeRespostaTransmissao;
begin
  FSim.PublicarDocumento('11222333000181', 'RS', DFE_SIM_SCHEMA_RESNFE,
    XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  R := Transmitir(Requisicao('000000000000000'));
  AssertTrue(Pos('<cStat>138</cStat>', R.Texto) > 0);
  AssertTrue(Pos('<docZip NSU="000000000000001" schema="resNFe_v1.01.xsd">H4sIAAAAAAAA', R.Texto) > 0);
  AssertTrue(Pos('<ultNSU>000000000000001</ultNSU>', R.Texto) > 0);
  AssertTrue(Pos('<maxNSU>000000000000001</maxNSU>', R.Texto) > 0);
end;

procedure TDFeSimuladorSoapTests.DocZipCorrompido_AfetaSoOPrimeiroItem;
var
  R: TDFeRespostaSimulada;
  LNormal, LCorrompido: string;
begin
  FSim.PublicarDocumento('11222333000181', 'RS', DFE_SIM_SCHEMA_RESNFE,
    XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  FSim.PublicarDocumento('11222333000181', 'RS', DFE_SIM_SCHEMA_RESNFE,
    XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 2)));
  FSim.EnfileirarFalha(fsDocZipCorrompido);
  R := FSim.Consultar('11222333000181', 'RS', 0);
  LCorrompido := MontarEnvelopeResposta(R, '2');
  R.DocZipCorrompido := False;
  LNormal := MontarEnvelopeResposta(R, '2');

  AssertTrue(LCorrompido <> LNormal);
  // o segundo docZip e' identico nos dois; o primeiro difere
  AssertTrue(Pos('NSU="000000000000002"', LCorrompido) > 0);
  AssertTrue(Copy(LCorrompido, Pos('NSU="000000000000002"', LCorrompido), MaxInt) =
             Copy(LNormal, Pos('NSU="000000000000002"', LNormal), MaxInt));
end;

procedure TDFeSimuladorSoapTests.UltNSUDaRequisicao_FiltraOsDocumentos;
var
  R: TDFeRespostaTransmissao;
begin
  FSim.PublicarDocumento('11222333000181', 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  FSim.PublicarDocumento('11222333000181', 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 2)));
  R := Transmitir(Requisicao('000000000000001'));
  AssertEquals(Int64(1), FSim.UltimoNSURecebido);
  AssertTrue(Pos('NSU="000000000000001"', R.Texto) = 0);
  AssertTrue(Pos('NSU="000000000000002"', R.Texto) > 0);
end;

procedure TDFeSimuladorSoapTests.CnpjEUfDaRequisicao_SelecionamAConta;
var
  R: TDFeRespostaTransmissao;
begin
  FSim.PublicarDocumento('11222333000181', 'SP', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  R := Transmitir(Requisicao('000000000000000', '11222333000181', '43')); // RS: conta vazia
  AssertTrue(Pos('<cStat>137</cStat>', R.Texto) > 0);
  R := Transmitir(Requisicao('000000000000000', '11222333000181', '35')); // SP
  AssertTrue(Pos('<cStat>138</cStat>', R.Texto) > 0);
end;

procedure TDFeSimuladorSoapTests.Timeout_DevolveCodigoInterno10060;
var
  R: TDFeRespostaTransmissao;
begin
  FSim.EnfileirarFalha(fsTimeout);
  R := Transmitir(Requisicao('000000000000000'));
  AssertEquals(10060, R.InternalErrorCode);
  AssertEquals(0, R.HTTPResultCode);
  AssertEquals('', R.Texto);
end;

procedure TDFeSimuladorSoapTests.ErroHttp_Devolve500ComSoapFault;
var
  R: TDFeRespostaTransmissao;
begin
  FSim.EnfileirarFalha(fsErroHttp);
  R := Transmitir(Requisicao('000000000000000'));
  AssertEquals(500, R.HTTPResultCode);
  AssertEquals(0, R.InternalErrorCode);
  AssertTrue(Pos('<soap:Fault>', R.Texto) > 0);
end;

procedure TDFeSimuladorSoapTests.CorpoIlegivel_Devolve200ComHtml;
var
  R: TDFeRespostaTransmissao;
begin
  FSim.EnfileirarFalha(fsCorpoIlegivel);
  R := Transmitir(Requisicao('000000000000000'));
  AssertEquals(200, R.HTTPResultCode);
  AssertTrue(Pos('<html>', R.Texto) > 0);
end;

procedure TDFeSimuladorSoapTests.Violacao_UrlSoapActionEForma;
begin
  Transmitir(Requisicao('000000000000000'), 'https://exemplo.invalido/outro.asmx', 'http://x/y');
  AssertTrue(FTransmissor.QuantidadeViolacoes >= 2);
  AssertTrue(Pos('URL', FTransmissor.TodasViolacoes) > 0);
  AssertTrue(Pos('SoapAction', FTransmissor.TodasViolacoes) > 0);
end;

procedure TDFeSimuladorSoapTests.Violacao_UltNSUCurtoEModoNaoSuportado;
begin
  Transmitir(StringReplace(Requisicao('000000000000000'), '<distNSU><ultNSU>000000000000000</ultNSU></distNSU>',
    '<consNSU><NSU>1</NSU></consNSU>', []));
  AssertTrue(Pos('consulta por NSU/chave', FTransmissor.TodasViolacoes) > 0);
  AssertTrue(Pos('distNSU', FTransmissor.TodasViolacoes) > 0);

  Transmitir(Requisicao('123'));
  AssertTrue(Pos('15 digitos', FTransmissor.TodasViolacoes) > 0);
end;

procedure TDFeSimuladorSoapTests.Violacao_UfDesconhecidaECnpjCurto;
begin
  Transmitir(Requisicao('000000000000000', '123', '99'));
  AssertTrue(Pos('cUFAutor', FTransmissor.TodasViolacoes) > 0);
  AssertTrue(Pos('CNPJ', FTransmissor.TodasViolacoes) > 0);
end;

initialization
  RegisterTest(TDFeSimuladorSoapTests);

end.
