unit DFe.SimuladorSoapTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  DFe.Transmissor,
  DFe.Simulador,
  DFe.Simulador.Soap,
  DFe.Simulador.Fixtures,
  DFe.TestDoubles;

type
  [TestFixture]
  TDFeSimuladorSoapTests = class
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
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

  public
    [Test] procedure ExtrairTag_DevolveConteudoOuVazio;
    [Test] procedure SiglaDaUF_ConhecidaEDesconhecida;
    [Test] procedure RequisicaoDoAcbr_NaoGeraViolacao;
    [Test] procedure Envelope137_TemOsCamposQueOAcbrLe;
    [Test] procedure Envelope138_TemDocZipComGzipEmBase64;
    [Test] procedure DocZipCorrompido_AfetaSoOPrimeiroItem;
    [Test] procedure UltNSUDaRequisicao_FiltraOsDocumentos;
    [Test] procedure CnpjEUfDaRequisicao_SelecionamAConta;
    [Test] procedure Timeout_DevolveCodigoInterno10060;
    [Test] procedure ErroHttp_Devolve500ComSoapFault;
    [Test] procedure CorpoIlegivel_Devolve200ComHtml;
    [Test] procedure Violacao_UrlSoapActionEForma;
    [Test] procedure Violacao_UltNSUCurtoEModoNaoSuportado;
    [Test] procedure Violacao_UfDesconhecidaECnpjCurto;
  end;

implementation

const
  RAIZ_SOAP = '<?xml version="1.0" encoding="UTF-8"?><soap12:Envelope ' +
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
    'xmlns:xsd="http://www.w3.org/2001/XMLSchema" ' +
    'xmlns:soap12="http://www.w3.org/2003/05/soap-envelope"><soap12:Body>';

{ TDFeSimuladorSoapTests }

procedure TDFeSimuladorSoapTests.Setup;
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
  Assert.AreEqual('123', ExtrairTag('<a><ultNSU>123</ultNSU></a>', 'ultNSU'));
  Assert.AreEqual('', ExtrairTag('<a></a>', 'ultNSU'));
  Assert.AreEqual('', ExtrairTag('<a><ultNSU>sem fecho', 'ultNSU'));
  Assert.AreEqual('1', ExtrairTag('<x><CNPJ>1</CNPJ><CNPJ>2</CNPJ></x>', 'CNPJ'));
end;

procedure TDFeSimuladorSoapTests.SiglaDaUF_ConhecidaEDesconhecida;
begin
  Assert.AreEqual('RS', SiglaDaUFPorCodigo('43'));
  Assert.AreEqual('SP', SiglaDaUFPorCodigo('35'));
  Assert.AreEqual('DF', SiglaDaUFPorCodigo('53'));
  Assert.AreEqual('', SiglaDaUFPorCodigo('99'));
  Assert.AreEqual('', SiglaDaUFPorCodigo(''));
end;

procedure TDFeSimuladorSoapTests.RequisicaoDoAcbr_NaoGeraViolacao;
begin
  Transmitir(Requisicao('000000000000000'));
  Assert.AreEqual(0, FTransmissor.QuantidadeViolacoes, FTransmissor.TodasViolacoes);
  Assert.AreEqual(1, FTransmissor.Requisicoes);
end;

procedure TDFeSimuladorSoapTests.Envelope137_TemOsCamposQueOAcbrLe;
var
  R: TDFeRespostaTransmissao;
begin
  R := Transmitir(Requisicao('000000000000000'));
  Assert.AreEqual(200, R.HTTPResultCode);
  Assert.AreEqual(0, R.InternalErrorCode);
  Assert.IsTrue(Pos('<nfeDistDFeInteresseResult>', R.Texto) > 0);
  Assert.IsTrue(Pos('<retDistDFeInt xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.01">', R.Texto) > 0);
  Assert.IsTrue(Pos('<cStat>137</cStat>', R.Texto) > 0);
  Assert.IsTrue(Pos('<tpAmb>2</tpAmb>', R.Texto) > 0);
  Assert.IsTrue(Pos('<ultNSU>000000000000000</ultNSU>', R.Texto) > 0);
  Assert.IsTrue(Pos('<maxNSU>000000000000000</maxNSU>', R.Texto) > 0);
  Assert.IsTrue(Pos('<loteDistDFeInt>', R.Texto) = 0);
end;

procedure TDFeSimuladorSoapTests.Envelope138_TemDocZipComGzipEmBase64;
var
  R: TDFeRespostaTransmissao;
begin
  FSim.PublicarDocumento('11222333000181', 'RS', DFE_SIM_SCHEMA_RESNFE,
    XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  R := Transmitir(Requisicao('000000000000000'));
  Assert.IsTrue(Pos('<cStat>138</cStat>', R.Texto) > 0);
  Assert.IsTrue(Pos('<docZip NSU="000000000000001" schema="resNFe_v1.01.xsd">H4sIAAAAAAAA', R.Texto) > 0);
  Assert.IsTrue(Pos('<ultNSU>000000000000001</ultNSU>', R.Texto) > 0);
  Assert.IsTrue(Pos('<maxNSU>000000000000001</maxNSU>', R.Texto) > 0);
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

  Assert.IsTrue(LCorrompido <> LNormal);
  // o segundo docZip e' identico nos dois; o primeiro difere
  Assert.IsTrue(Pos('NSU="000000000000002"', LCorrompido) > 0);
  Assert.IsTrue(Copy(LCorrompido, Pos('NSU="000000000000002"', LCorrompido), MaxInt) =
             Copy(LNormal, Pos('NSU="000000000000002"', LNormal), MaxInt));
end;

procedure TDFeSimuladorSoapTests.UltNSUDaRequisicao_FiltraOsDocumentos;
var
  R: TDFeRespostaTransmissao;
begin
  FSim.PublicarDocumento('11222333000181', 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  FSim.PublicarDocumento('11222333000181', 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 2)));
  R := Transmitir(Requisicao('000000000000001'));
  Assert.AreEqual(Int64(1), FSim.UltimoNSURecebido);
  Assert.IsTrue(Pos('NSU="000000000000001"', R.Texto) = 0);
  Assert.IsTrue(Pos('NSU="000000000000002"', R.Texto) > 0);
end;

procedure TDFeSimuladorSoapTests.CnpjEUfDaRequisicao_SelecionamAConta;
var
  R: TDFeRespostaTransmissao;
begin
  FSim.PublicarDocumento('11222333000181', 'SP', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  R := Transmitir(Requisicao('000000000000000', '11222333000181', '43')); // RS: conta vazia
  Assert.IsTrue(Pos('<cStat>137</cStat>', R.Texto) > 0);
  R := Transmitir(Requisicao('000000000000000', '11222333000181', '35')); // SP
  Assert.IsTrue(Pos('<cStat>138</cStat>', R.Texto) > 0);
end;

procedure TDFeSimuladorSoapTests.Timeout_DevolveCodigoInterno10060;
var
  R: TDFeRespostaTransmissao;
begin
  FSim.EnfileirarFalha(fsTimeout);
  R := Transmitir(Requisicao('000000000000000'));
  Assert.AreEqual(10060, R.InternalErrorCode);
  Assert.AreEqual(0, R.HTTPResultCode);
  Assert.AreEqual('', R.Texto);
end;

procedure TDFeSimuladorSoapTests.ErroHttp_Devolve500ComSoapFault;
var
  R: TDFeRespostaTransmissao;
begin
  FSim.EnfileirarFalha(fsErroHttp);
  R := Transmitir(Requisicao('000000000000000'));
  Assert.AreEqual(500, R.HTTPResultCode);
  Assert.AreEqual(0, R.InternalErrorCode);
  Assert.IsTrue(Pos('<soap:Fault>', R.Texto) > 0);
end;

procedure TDFeSimuladorSoapTests.CorpoIlegivel_Devolve200ComHtml;
var
  R: TDFeRespostaTransmissao;
begin
  FSim.EnfileirarFalha(fsCorpoIlegivel);
  R := Transmitir(Requisicao('000000000000000'));
  Assert.AreEqual(200, R.HTTPResultCode);
  Assert.IsTrue(Pos('<html>', R.Texto) > 0);
end;

procedure TDFeSimuladorSoapTests.Violacao_UrlSoapActionEForma;
begin
  Transmitir(Requisicao('000000000000000'), 'https://exemplo.invalido/outro.asmx', 'http://x/y');
  Assert.IsTrue(FTransmissor.QuantidadeViolacoes >= 2);
  Assert.IsTrue(Pos('URL', FTransmissor.TodasViolacoes) > 0);
  Assert.IsTrue(Pos('SoapAction', FTransmissor.TodasViolacoes) > 0);
end;

procedure TDFeSimuladorSoapTests.Violacao_UltNSUCurtoEModoNaoSuportado;
begin
  Transmitir(StringReplace(Requisicao('000000000000000'), '<distNSU><ultNSU>000000000000000</ultNSU></distNSU>',
    '<consNSU><NSU>1</NSU></consNSU>', []));
  Assert.IsTrue(Pos('consulta por NSU/chave', FTransmissor.TodasViolacoes) > 0);
  Assert.IsTrue(Pos('distNSU', FTransmissor.TodasViolacoes) > 0);

  Transmitir(Requisicao('123'));
  Assert.IsTrue(Pos('15 digitos', FTransmissor.TodasViolacoes) > 0);
end;

procedure TDFeSimuladorSoapTests.Violacao_UfDesconhecidaECnpjCurto;
begin
  Transmitir(Requisicao('000000000000000', '123', '99'));
  Assert.IsTrue(Pos('cUFAutor', FTransmissor.TodasViolacoes) > 0);
  Assert.IsTrue(Pos('CNPJ', FTransmissor.TodasViolacoes) > 0);
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeSimuladorSoapTests);

end.
