unit DFe.SimuladorEventoTests;

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
  { Fase 4: manifestacao do destinatario (RecepcaoEvento) -- nucleo. }
  [TestFixture]
  TDFeSimuladorEventoNucleoTests = class
  private
    FRelogio: TDFeRelogioFake;
    FSim: TDFeSimuladorSefaz;
    FChave: string;
    procedure PublicarNFeDoDestinatario;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure ChaveVisivel_Registra135ComProtocoloEHorario;
    [Test] procedure ChaveDesconhecida_Rejeita494SemProtocolo;
    [Test] procedure ChaveDeOutroCnpj_Rejeita494;
    [Test] procedure MesmoEvento_Rejeita573ComoDuplicidade;
    [Test] procedure OutroTipoOuOutraSequencia_NaoEDuplicidade;
    [Test] procedure ProtocolosSaoSequenciaisEUnicos;
    [Test] procedure Falha_TransporteDevolveOTipo;
    [Test] procedure Falha_Indisponivel108e109_SemEvento;
    [Test] procedure Falha_LoteRejeitado_SemEvento;
    [Test] procedure Falha_EventoRejeitado_LoteProcessado;
    [Test] procedure FalhaDeDistribuicao_EmEvento_LevantaExcecao;
    [Test] procedure FalhaDeEvento_EmConsulta_LevantaExcecao;
    [Test] procedure Falhas_ConsumidasUmaPorChamada;
    [Test] procedure Contadores_TotalEEventosRegistrados;
  end;

  { Fase 4: manifestacao do destinatario -- adaptador SOAP. }
  [TestFixture]
  TDFeSimuladorEventoSoapTests = class
  private
    FRelogio: TDFeRelogioFake;
    FSim: TDFeSimuladorSefaz;
    FTransmissor: TDFeSimuladorTransmissor;
    FIntf: IDFeTransmissor;
    FChave: string;
    function Requisicao(const ATpEvento: string = '210210'; const ADesc: string = 'Ciencia da Operacao';
      const AOrgao: string = '91'; const ANSeq: Integer = 1; const AComAssinatura: Boolean = True;
      const AXJust: string = ''): string;
    function Transmitir(const AEnvelope: string;
      const AURL: string = 'https://hom1.nfe.fazenda.gov.br/NFeRecepcaoEvento4/NFeRecepcaoEvento4.asmx'): TDFeRespostaTransmissao;
    procedure PublicarNFeDoDestinatario;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure ExtrairAtributo_LeAtributoDoPrimeiroElemento;
    [Test] procedure RequisicaoDoAcbr_NaoGeraViolacao;
    [Test] procedure Registrado_RespondeRetEnvEventoComProtocolo;
    [Test] procedure ChaveDesconhecida_RespondeRejeicaoSemProtocolo;
    [Test] procedure LoteRejeitado_RespondeSemRetEvento;
    [Test] procedure Timeout_ErroHttp_CorpoIlegivel_TiposDeTransporte;
    [Test] procedure OperacaoNaoRealizada_ExigeXJust;
    [Test] procedure Violacao_OrgaoDiferenteDe91;
    [Test] procedure Violacao_IdDoEventoIncoerente;
    [Test] procedure Violacao_SemAssinatura;
    [Test] procedure Violacao_ReferenceUriDiferenteDoId;
    [Test] procedure Violacao_TipoDeEventoQueNaoEManifestacao;
    [Test] procedure Violacao_DhEventoForaDoFormato;
    [Test] procedure Violacao_UrlESoapActionDeEvento;
  end;

implementation

const
  CNPJ_DEST = '11222333000181';

function ChaveDoTeste: string;
begin
  Result := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1);
end;

{ TDFeSimuladorEventoNucleoTests }

procedure TDFeSimuladorEventoNucleoTests.Setup;
begin
  FRelogio := TDFeRelogioFake.Create;
  FRelogio.Agora := EncodeDate(2026, 9, 18) + EncodeTime(10, 0, 0, 0);
  FSim := TDFeSimuladorSefaz.Create(FRelogio.ObterAgora);
  FChave := ChaveDoTeste;
end;

procedure TDFeSimuladorEventoNucleoTests.TearDown;
begin
  FSim.Free;
  FRelogio.Free;
end;

procedure TDFeSimuladorEventoNucleoTests.PublicarNFeDoDestinatario;
begin
  FSim.PublicarDocumento(CNPJ_DEST, 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(FChave));
end;

procedure TDFeSimuladorEventoNucleoTests.ChaveVisivel_Registra135ComProtocoloEHorario;
var
  R: TDFeRespostaEventoSimulada;
begin
  PublicarNFeDoDestinatario;
  R := FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1);
  Assert.IsTrue(R.Tipo = trsLote);
  Assert.AreEqual(128, R.CStatLote);
  Assert.IsTrue(R.TemEvento);
  Assert.AreEqual(135, R.CStat);
  Assert.AreEqual('891000000000001', R.NProt);
  Assert.IsTrue(R.DhRegEvento = FRelogio.Agora);
end;

procedure TDFeSimuladorEventoNucleoTests.ChaveDesconhecida_Rejeita494SemProtocolo;
var
  R: TDFeRespostaEventoSimulada;
begin
  R := FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1);
  Assert.AreEqual(128, R.CStatLote);
  Assert.AreEqual(494, R.CStat);
  Assert.AreEqual('', R.NProt);
  Assert.AreEqual(0, FSim.EventosRegistrados);
end;

procedure TDFeSimuladorEventoNucleoTests.ChaveDeOutroCnpj_Rejeita494;
begin
  PublicarNFeDoDestinatario;
  // a NFe existe, mas e' visivel so' ao CNPJ_DEST
  Assert.AreEqual(494, FSim.ReceberEvento('11444777000161', FChave, '210210', 1).CStat);
end;

procedure TDFeSimuladorEventoNucleoTests.MesmoEvento_Rejeita573ComoDuplicidade;
begin
  PublicarNFeDoDestinatario;
  Assert.AreEqual(135, FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).CStat);
  Assert.AreEqual(573, FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).CStat);
  Assert.AreEqual(1, FSim.EventosRegistrados);
end;

procedure TDFeSimuladorEventoNucleoTests.OutroTipoOuOutraSequencia_NaoEDuplicidade;
begin
  PublicarNFeDoDestinatario;
  Assert.AreEqual(135, FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).CStat);
  Assert.AreEqual(135, FSim.ReceberEvento(CNPJ_DEST, FChave, '210200', 1).CStat);
  Assert.AreEqual(135, FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 2).CStat);
  Assert.AreEqual(3, FSim.EventosRegistrados);
end;

procedure TDFeSimuladorEventoNucleoTests.ProtocolosSaoSequenciaisEUnicos;
begin
  PublicarNFeDoDestinatario;
  Assert.AreEqual('891000000000001', FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).NProt);
  Assert.AreEqual('891000000000002', FSim.ReceberEvento(CNPJ_DEST, FChave, '210200', 1).NProt);
end;

procedure TDFeSimuladorEventoNucleoTests.Falha_TransporteDevolveOTipo;
begin
  FSim.EnfileirarFalha(fsTimeout);
  FSim.EnfileirarFalha(fsErroHttp);
  FSim.EnfileirarFalha(fsCorpoIlegivel);
  Assert.IsTrue(FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).Tipo = trsTimeout);
  Assert.IsTrue(FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).Tipo = trsErroHttp);
  Assert.IsTrue(FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).Tipo = trsCorpoIlegivel);
end;

procedure TDFeSimuladorEventoNucleoTests.Falha_Indisponivel108e109_SemEvento;
var
  R: TDFeRespostaEventoSimulada;
begin
  FSim.EnfileirarFalha(fsIndisponivelCurtoPrazo);
  R := FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1);
  Assert.AreEqual(108, R.CStatLote);
  Assert.IsFalse(R.TemEvento);

  FSim.EnfileirarFalha(fsIndisponivelSemPrevisao);
  Assert.AreEqual(109, FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).CStatLote);
  Assert.AreEqual(0, FSim.EventosRegistrados);
end;

procedure TDFeSimuladorEventoNucleoTests.Falha_LoteRejeitado_SemEvento;
var
  R: TDFeRespostaEventoSimulada;
begin
  FSim.EnfileirarFalha(fsLoteEventoRejeitado);
  R := FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1);
  Assert.AreEqual(999, R.CStatLote);
  Assert.IsFalse(R.TemEvento);
end;

procedure TDFeSimuladorEventoNucleoTests.Falha_EventoRejeitado_LoteProcessado;
var
  R: TDFeRespostaEventoSimulada;
begin
  PublicarNFeDoDestinatario;
  FSim.EnfileirarFalha(fsEventoRejeitado);
  R := FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1);
  Assert.AreEqual(128, R.CStatLote);
  Assert.IsTrue(R.TemEvento);
  Assert.AreEqual(999, R.CStat);
  Assert.AreEqual('', R.NProt);
  // a falha forcada nao registrou nada: a proxima tentativa vale
  Assert.AreEqual(135, FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).CStat);
end;

procedure TDFeSimuladorEventoNucleoTests.FalhaDeDistribuicao_EmEvento_LevantaExcecao;
var
  LLevantou: Boolean;
begin
  FSim.EnfileirarFalha(fsConsumoIndevido);
  LLevantou := False;
  try
    FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1);
  except
    on Exception do LLevantou := True;
  end;
  Assert.IsTrue(LLevantou, 'fsConsumoIndevido nao se aplica a evento');

  FSim.EnfileirarFalha(fsDocZipCorrompido);
  LLevantou := False;
  try
    FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1);
  except
    on Exception do LLevantou := True;
  end;
  Assert.IsTrue(LLevantou, 'fsDocZipCorrompido nao se aplica a evento');
end;

procedure TDFeSimuladorEventoNucleoTests.FalhaDeEvento_EmConsulta_LevantaExcecao;
var
  LLevantou: Boolean;
begin
  FSim.EnfileirarFalha(fsEventoRejeitado);
  LLevantou := False;
  try
    FSim.Consultar(CNPJ_DEST, 'RS', 0);
  except
    on Exception do LLevantou := True;
  end;
  Assert.IsTrue(LLevantou, 'fsEventoRejeitado nao se aplica a Consultar');
end;

procedure TDFeSimuladorEventoNucleoTests.Falhas_ConsumidasUmaPorChamada;
begin
  FSim.EnfileirarFalha(fsTimeout);
  Assert.IsTrue(FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).Tipo = trsTimeout);
  Assert.IsTrue(FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).Tipo = trsLote);
end;

procedure TDFeSimuladorEventoNucleoTests.Contadores_TotalEEventosRegistrados;
begin
  PublicarNFeDoDestinatario;
  FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1);
  FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1); // duplicidade
  Assert.AreEqual(2, FSim.TotalEventos);
  Assert.AreEqual(1, FSim.EventosRegistrados);
end;

{ TDFeSimuladorEventoSoapTests }

procedure TDFeSimuladorEventoSoapTests.Setup;
begin
  FRelogio := TDFeRelogioFake.Create;
  FRelogio.Agora := EncodeDate(2026, 9, 18) + EncodeTime(10, 0, 0, 0);
  FSim := TDFeSimuladorSefaz.Create(FRelogio.ObterAgora);
  FTransmissor := TDFeSimuladorTransmissor.Create(FSim);
  FIntf := FTransmissor;
  FChave := ChaveDoTeste;
end;

procedure TDFeSimuladorEventoSoapTests.TearDown;
begin
  FIntf := nil;
  FTransmissor := nil;
  FSim.Free;
  FRelogio.Free;
end;

procedure TDFeSimuladorEventoSoapTests.PublicarNFeDoDestinatario;
begin
  FSim.PublicarDocumento(CNPJ_DEST, 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(FChave));
end;

{ Requisicao no formato que o ACBr emitiu na sonda da Fase 4 (assinatura com
  valores ficticios -- a validade criptografica e' assunto do teste de
  integracao). }
function TDFeSimuladorEventoSoapTests.Requisicao(const ATpEvento, ADesc, AOrgao: string;
  const ANSeq: Integer; const AComAssinatura: Boolean; const AXJust: string): string;
var
  LId, LAssinatura, LDet: string;
begin
  LId := 'ID' + ATpEvento + FChave + Format('%.2d', [ANSeq]);
  LDet := '<descEvento>' + ADesc + '</descEvento>';
  if AXJust <> '' then
    LDet := LDet + '<xJust>' + AXJust + '</xJust>';
  LAssinatura := '';
  if AComAssinatura then
    LAssinatura := '<Signature xmlns="http://www.w3.org/2000/09/xmldsig#"><SignedInfo>' +
      '<CanonicalizationMethod Algorithm="http://www.w3.org/TR/2001/REC-xml-c14n-20010315"></CanonicalizationMethod>' +
      '<SignatureMethod Algorithm="http://www.w3.org/2000/09/xmldsig#rsa-sha1"></SignatureMethod>' +
      '<Reference URI="#' + LId + '"><DigestMethod Algorithm="http://www.w3.org/2000/09/xmldsig#sha1"></DigestMethod>' +
      '<DigestValue>ZmFrZQ==</DigestValue></Reference></SignedInfo><SignatureValue>ZmFrZQ==</SignatureValue>' +
      '<KeyInfo><X509Data><X509Certificate>ZmFrZQ==</X509Certificate></X509Data></KeyInfo></Signature>';
  Result := '<?xml version="1.0" encoding="UTF-8"?><soap12:Envelope ' +
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" ' +
    'xmlns:soap12="http://www.w3.org/2003/05/soap-envelope"><soap12:Body>' +
    '<nfeDadosMsg xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeRecepcaoEvento4">' +
    '<envEvento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00"><idLote>1</idLote>' +
    '<evento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00"><infEvento Id="' + LId + '">' +
    '<cOrgao>' + AOrgao + '</cOrgao><tpAmb>2</tpAmb><CNPJ>' + CNPJ_DEST + '</CNPJ>' +
    '<chNFe>' + FChave + '</chNFe><dhEvento>2026-09-18T18:44:03-03:00</dhEvento>' +
    '<tpEvento>' + ATpEvento + '</tpEvento><nSeqEvento>' + IntToStr(ANSeq) + '</nSeqEvento>' +
    '<verEvento>1.00</verEvento><detEvento versao="1.00">' + LDet + '</detEvento></infEvento>' +
    LAssinatura + '</evento></envEvento></nfeDadosMsg></soap12:Body></soap12:Envelope>';
end;

function TDFeSimuladorEventoSoapTests.Transmitir(const AEnvelope, AURL: string): TDFeRespostaTransmissao;
begin
  Result := FIntf.Transmitir(AEnvelope, AURL,
    'http://www.portalfiscal.inf.br/nfe/wsdl/NFeRecepcaoEvento4/nfeRecepcaoEvento', '');
end;

procedure TDFeSimuladorEventoSoapTests.ExtrairAtributo_LeAtributoDoPrimeiroElemento;
begin
  Assert.AreEqual('ID1', ExtrairAtributo('<a><infEvento Id="ID1" x="2"><b/></infEvento></a>', 'infEvento', 'Id'));
  Assert.AreEqual('2', ExtrairAtributo('<infEvento Id="ID1" x="2">', 'infEvento', 'x'));
  Assert.AreEqual('', ExtrairAtributo('<infEvento Id="ID1">', 'infEvento', 'y'));
  Assert.AreEqual('', ExtrairAtributo('<a y="1"><infEvento Id="ID1">', 'infEvento', 'y'));
  Assert.AreEqual('', ExtrairAtributo('<a/>', 'infEvento', 'Id'));
end;

procedure TDFeSimuladorEventoSoapTests.RequisicaoDoAcbr_NaoGeraViolacao;
begin
  PublicarNFeDoDestinatario;
  Transmitir(Requisicao);
  Assert.AreEqual(0, FTransmissor.QuantidadeViolacoes, FTransmissor.TodasViolacoes);
  Assert.AreEqual(1, FTransmissor.Requisicoes);
end;

procedure TDFeSimuladorEventoSoapTests.Registrado_RespondeRetEnvEventoComProtocolo;
var
  R: TDFeRespostaTransmissao;
begin
  PublicarNFeDoDestinatario;
  R := Transmitir(Requisicao);
  Assert.AreEqual(200, R.HTTPResultCode);
  Assert.IsTrue(Pos('<nfeResultMsg xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeRecepcaoEvento4">', R.Texto) > 0);
  Assert.IsTrue(Pos('<retEnvEvento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00"><idLote>1</idLote>', R.Texto) > 0);
  Assert.IsTrue(Pos('<cStat>128</cStat>', R.Texto) > 0);
  Assert.IsTrue(Pos('<cStat>135</cStat>', R.Texto) > 0);
  Assert.IsTrue(Pos('<chNFe>' + FChave + '</chNFe>', R.Texto) > 0);
  Assert.IsTrue(Pos('<tpEvento>210210</tpEvento>', R.Texto) > 0);
  Assert.IsTrue(Pos('<nProt>891000000000001</nProt>', R.Texto) > 0);
  Assert.IsTrue(Pos('<dhRegEvento>2026-09-18T10:00:00-03:00</dhRegEvento>', R.Texto) > 0);
  Assert.IsTrue(Pos('<CNPJDest>' + CNPJ_DEST + '</CNPJDest>', R.Texto) > 0);
end;

procedure TDFeSimuladorEventoSoapTests.ChaveDesconhecida_RespondeRejeicaoSemProtocolo;
var
  R: TDFeRespostaTransmissao;
begin
  R := Transmitir(Requisicao); // nada publicado
  Assert.IsTrue(Pos('<cStat>128</cStat>', R.Texto) > 0);
  Assert.IsTrue(Pos('<cStat>494</cStat>', R.Texto) > 0);
  Assert.IsTrue(Pos('<nProt>', R.Texto) = 0);
  Assert.IsTrue(Pos('<dhRegEvento>', R.Texto) = 0);
end;

procedure TDFeSimuladorEventoSoapTests.LoteRejeitado_RespondeSemRetEvento;
var
  R: TDFeRespostaTransmissao;
begin
  FSim.EnfileirarFalha(fsLoteEventoRejeitado);
  R := Transmitir(Requisicao);
  Assert.IsTrue(Pos('<cStat>999</cStat>', R.Texto) > 0);
  Assert.IsTrue(Pos('<retEvento', R.Texto) = 0);
end;

procedure TDFeSimuladorEventoSoapTests.Timeout_ErroHttp_CorpoIlegivel_TiposDeTransporte;
var
  R: TDFeRespostaTransmissao;
begin
  FSim.EnfileirarFalha(fsTimeout);
  FSim.EnfileirarFalha(fsErroHttp);
  FSim.EnfileirarFalha(fsCorpoIlegivel);
  R := Transmitir(Requisicao);
  Assert.AreEqual(10060, R.InternalErrorCode);
  R := Transmitir(Requisicao);
  Assert.AreEqual(500, R.HTTPResultCode);
  Assert.IsTrue(Pos('<soap:Fault>', R.Texto) > 0);
  R := Transmitir(Requisicao);
  Assert.AreEqual(200, R.HTTPResultCode);
  Assert.IsTrue(Pos('<html>', R.Texto) > 0);
end;

procedure TDFeSimuladorEventoSoapTests.OperacaoNaoRealizada_ExigeXJust;
begin
  Transmitir(Requisicao('210240', 'Operacao nao Realizada'));
  Assert.IsTrue(Pos('exige xJust', FTransmissor.TodasViolacoes) > 0);

  Transmitir(Requisicao('210240', 'Operacao nao Realizada', '91', 2, True, 'mercadoria nao foi entregue no prazo'));
  // a segunda requisicao (com xJust) nao acrescenta violacao de xJust
  Assert.AreEqual(1, FTransmissor.QuantidadeViolacoes);
end;

procedure TDFeSimuladorEventoSoapTests.Violacao_OrgaoDiferenteDe91;
begin
  Transmitir(Requisicao('210210', 'Ciencia da Operacao', '43'));
  Assert.IsTrue(Pos('cOrgao', FTransmissor.TodasViolacoes) > 0);
end;

procedure TDFeSimuladorEventoSoapTests.Violacao_IdDoEventoIncoerente;
begin
  Transmitir(StringReplace(Requisicao, 'Id="ID210210' + FChave + '01"', 'Id="IDerrado"', []));
  Assert.IsTrue(Pos('infEvento/@Id', FTransmissor.TodasViolacoes) > 0);
end;

procedure TDFeSimuladorEventoSoapTests.Violacao_SemAssinatura;
begin
  Transmitir(Requisicao('210210', 'Ciencia da Operacao', '91', 1, False));
  Assert.IsTrue(Pos('sem <Signature>', FTransmissor.TodasViolacoes) > 0);
end;

procedure TDFeSimuladorEventoSoapTests.Violacao_ReferenceUriDiferenteDoId;
begin
  Transmitir(StringReplace(Requisicao, 'Reference URI="#ID', 'Reference URI="#XX', []));
  Assert.IsTrue(Pos('Reference/@URI', FTransmissor.TodasViolacoes) > 0);
end;

procedure TDFeSimuladorEventoSoapTests.Violacao_TipoDeEventoQueNaoEManifestacao;
begin
  Transmitir(Requisicao('110111', 'Cancelamento'));
  Assert.IsTrue(Pos('nao e'' manifestacao', FTransmissor.TodasViolacoes) > 0);
end;

procedure TDFeSimuladorEventoSoapTests.Violacao_DhEventoForaDoFormato;
begin
  Transmitir(StringReplace(Requisicao, '2026-09-18T18:44:03-03:00', '18/09/2026 18:44', []));
  Assert.IsTrue(Pos('dhEvento', FTransmissor.TodasViolacoes) > 0);
end;

procedure TDFeSimuladorEventoSoapTests.Violacao_UrlESoapActionDeEvento;
begin
  Transmitir(Requisicao, 'https://exemplo.invalido/outro.asmx');
  Assert.IsTrue(Pos('URL inesperada para RecepcaoEvento', FTransmissor.TodasViolacoes) > 0);
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeSimuladorEventoNucleoTests);
  TDUnitX.RegisterTestFixture(TDFeSimuladorEventoSoapTests);

end.
