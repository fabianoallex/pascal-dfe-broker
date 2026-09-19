unit DFe.SimuladorEventoTests;

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
  { Fase 4: manifestacao do destinatario (RecepcaoEvento) -- nucleo. }
  TDFeSimuladorEventoNucleoTests = class(TTestCase)
  private
    FRelogio: TDFeRelogioFake;
    FSim: TDFeSimuladorSefaz;
    FChave: string;
    procedure PublicarNFeDoDestinatario;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ChaveVisivel_Registra135ComProtocoloEHorario;
    procedure ChaveDesconhecida_Registra136SemVinculo;
    procedure ChaveDeOutroCnpj_Rejeita575;
    procedure MesmoEvento_Rejeita573ComoDuplicidade;
    procedure OutroTipo_NaoEDuplicidade;
    procedure SequenciaDiferenteDe1_Rejeita594;
    procedure CienciaAposManifestacaoFinal_Rejeita655;
    procedure ManifestacaoFinalAposCiencia_Registra;
    procedure Regra655_SoAplicaAMesmaChave;
    procedure Ordem_DuplicidadeAntesDeAutorEDeSequencia;
    procedure ProtocolosSaoSequenciaisEUnicos;
    procedure Falha_TransporteDevolveOTipo;
    procedure Falha_Indisponivel108e109_SemEvento;
    procedure Falha_LoteRejeitado_SemEvento;
    procedure Falha_EventoRejeitado_LoteProcessado;
    procedure FalhaDeDistribuicao_EmEvento_LevantaExcecao;
    procedure FalhaDeEvento_EmConsulta_LevantaExcecao;
    procedure Falhas_ConsumidasUmaPorChamada;
    procedure Contadores_TotalEEventosRegistrados;
  end;

  { Fase 4: manifestacao do destinatario -- adaptador SOAP. }
  TDFeSimuladorEventoSoapTests = class(TTestCase)
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
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ExtrairAtributo_LeAtributoDoPrimeiroElemento;
    procedure RequisicaoDoAcbr_NaoGeraViolacao;
    procedure Registrado_RespondeRetEnvEventoComProtocolo;
    procedure ChaveDesconhecida_RespondeRegistradoNaoVinculado136ComProtocolo;
    procedure LoteRejeitado_RespondeSemRetEvento;
    procedure Timeout_ErroHttp_CorpoIlegivel_TiposDeTransporte;
    procedure OperacaoNaoRealizada_ExigeXJust;
    procedure XJust_EmTipoQueNaoAceita_EViolacao;
    procedure XJust_TamanhoForaDe15a255_EViolacao;
    procedure Violacao_OrgaoDiferenteDe91;
    procedure Violacao_IdDoEventoIncoerente;
    procedure Violacao_SemAssinatura;
    procedure Violacao_ReferenceUriDiferenteDoId;
    procedure Violacao_TipoDeEventoQueNaoEManifestacao;
    procedure Violacao_DhEventoForaDoFormato;
    procedure Violacao_UrlESoapActionDeEvento;
  end;

implementation

const
  CNPJ_DEST = '11222333000181';

function ChaveDoTeste: string;
begin
  Result := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1);
end;

{ TDFeSimuladorEventoNucleoTests }

procedure TDFeSimuladorEventoNucleoTests.SetUp;
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
  AssertTrue(R.Tipo = trsLote);
  AssertEquals(128, R.CStatLote);
  AssertTrue(R.TemEvento);
  AssertEquals(135, R.CStat);
  AssertEquals('891000000000001', R.NProt);
  AssertTrue(R.DhRegEvento = FRelogio.Agora);
end;

{ NT 2012/002, 4.9.9: evento para NF-e que a SEFAZ ainda nao conhece NAO e'
  rejeitado -- e' registrado com cStat 136 ("registrado, mas nao vinculado"). }
procedure TDFeSimuladorEventoNucleoTests.ChaveDesconhecida_Registra136SemVinculo;
var
  R: TDFeRespostaEventoSimulada;
begin
  R := FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1);
  AssertEquals(128, R.CStatLote);
  AssertTrue(R.TemEvento);
  AssertEquals(136, R.CStat);
  AssertEquals('891000000000001', R.NProt);
  AssertTrue(R.DhRegEvento = FRelogio.Agora);
  AssertEquals(1, FSim.EventosRegistrados);
end;

{ G09: autor do evento diverge do destinatario da NF-e (que EXISTE): 575. }
procedure TDFeSimuladorEventoNucleoTests.ChaveDeOutroCnpj_Rejeita575;
var
  R: TDFeRespostaEventoSimulada;
begin
  PublicarNFeDoDestinatario;
  R := FSim.ReceberEvento('11444777000161', FChave, '210210', 1);
  AssertEquals(575, R.CStat);
  AssertEquals('', R.NProt);
  AssertEquals(0, FSim.EventosRegistrados);
end;

procedure TDFeSimuladorEventoNucleoTests.MesmoEvento_Rejeita573ComoDuplicidade;
begin
  PublicarNFeDoDestinatario;
  AssertEquals(135, FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).CStat);
  AssertEquals(573, FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).CStat);
  AssertEquals(1, FSim.EventosRegistrados);
end;

procedure TDFeSimuladorEventoNucleoTests.OutroTipo_NaoEDuplicidade;
begin
  PublicarNFeDoDestinatario;
  AssertEquals(135, FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).CStat);
  AssertEquals(135, FSim.ReceberEvento(CNPJ_DEST, FChave, '210200', 1).CStat);
  AssertEquals(2, FSim.EventosRegistrados);
end;

{ H02: nSeqEvento deve ser 1 (HP15 "informar 1"). }
procedure TDFeSimuladorEventoNucleoTests.SequenciaDiferenteDe1_Rejeita594;
begin
  PublicarNFeDoDestinatario;
  AssertEquals(594, FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 2).CStat);
  AssertEquals(0, FSim.EventosRegistrados);
end;

{ H06: ciencia informada apos a manifestacao final (confirmacao, operacao nao
  realizada ou desconhecimento). }
procedure TDFeSimuladorEventoNucleoTests.CienciaAposManifestacaoFinal_Rejeita655;

  { uma NF-e distinta por tipo final, para os casos nao se contaminarem }
  procedure Verificar(const ATipoFinal: string; const ANumeroNota: Integer);
  var
    LChave: string;
  begin
    LChave := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, ANumeroNota);
    FSim.PublicarDocumento(CNPJ_DEST, 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(LChave));
    AssertEquals(135, FSim.ReceberEvento(CNPJ_DEST, LChave, ATipoFinal, 1).CStat);
    AssertEquals(655, FSim.ReceberEvento(CNPJ_DEST, LChave, '210210', 1).CStat);
  end;

begin
  Verificar('210200', 11); // confirmacao
  Verificar('210220', 12); // desconhecimento
  Verificar('210240', 13); // operacao nao realizada
end;

procedure TDFeSimuladorEventoNucleoTests.ManifestacaoFinalAposCiencia_Registra;
begin
  PublicarNFeDoDestinatario;
  AssertEquals(135, FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).CStat);
  AssertEquals(135, FSim.ReceberEvento(CNPJ_DEST, FChave, '210200', 1).CStat);
end;

procedure TDFeSimuladorEventoNucleoTests.Regra655_SoAplicaAMesmaChave;
var
  LOutraChave: string;
begin
  LOutraChave := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 2);
  PublicarNFeDoDestinatario;
  FSim.PublicarDocumento(CNPJ_DEST, 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(LOutraChave));
  AssertEquals(135, FSim.ReceberEvento(CNPJ_DEST, FChave, '210200', 1).CStat);
  AssertEquals(135, FSim.ReceberEvento(CNPJ_DEST, LOutraChave, '210210', 1).CStat);
end;

{ Ordem das regras (NT: G07 antes de G09, antes das H): a duplicidade vem
  primeiro. }
procedure TDFeSimuladorEventoNucleoTests.Ordem_DuplicidadeAntesDeAutorEDeSequencia;
begin
  PublicarNFeDoDestinatario;
  AssertEquals(135, FSim.ReceberEvento(CNPJ_DEST, FChave, '210200', 1).CStat);
  AssertEquals(573, FSim.ReceberEvento(CNPJ_DEST, FChave, '210200', 1).CStat);
  // outro autor com o MESMO (chave, tpEvento, nSeq): tambem e' duplicidade e
  // vem ANTES da regra do autor (G07 antes de G09), entao 573 e nao 575
  AssertEquals(573, FSim.ReceberEvento('11444777000161', FChave, '210200', 1).CStat);
  // ja um evento NOVO de outro autor cai na G09: 575
  AssertEquals(575, FSim.ReceberEvento('11444777000161', FChave, '210220', 1).CStat);
end;

procedure TDFeSimuladorEventoNucleoTests.ProtocolosSaoSequenciaisEUnicos;
begin
  PublicarNFeDoDestinatario;
  AssertEquals('891000000000001', FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).NProt);
  AssertEquals('891000000000002', FSim.ReceberEvento(CNPJ_DEST, FChave, '210200', 1).NProt);
end;

procedure TDFeSimuladorEventoNucleoTests.Falha_TransporteDevolveOTipo;
begin
  FSim.EnfileirarFalha(fsTimeout);
  FSim.EnfileirarFalha(fsErroHttp);
  FSim.EnfileirarFalha(fsCorpoIlegivel);
  AssertTrue(FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).Tipo = trsTimeout);
  AssertTrue(FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).Tipo = trsErroHttp);
  AssertTrue(FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).Tipo = trsCorpoIlegivel);
end;

procedure TDFeSimuladorEventoNucleoTests.Falha_Indisponivel108e109_SemEvento;
var
  R: TDFeRespostaEventoSimulada;
begin
  FSim.EnfileirarFalha(fsIndisponivelCurtoPrazo);
  R := FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1);
  AssertEquals(108, R.CStatLote);
  AssertFalse(R.TemEvento);

  FSim.EnfileirarFalha(fsIndisponivelSemPrevisao);
  AssertEquals(109, FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).CStatLote);
  AssertEquals(0, FSim.EventosRegistrados);
end;

procedure TDFeSimuladorEventoNucleoTests.Falha_LoteRejeitado_SemEvento;
var
  R: TDFeRespostaEventoSimulada;
begin
  FSim.EnfileirarFalha(fsLoteEventoRejeitado);
  R := FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1);
  AssertEquals(999, R.CStatLote);
  AssertFalse(R.TemEvento);
end;

procedure TDFeSimuladorEventoNucleoTests.Falha_EventoRejeitado_LoteProcessado;
var
  R: TDFeRespostaEventoSimulada;
begin
  PublicarNFeDoDestinatario;
  FSim.EnfileirarFalha(fsEventoRejeitado);
  R := FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1);
  AssertEquals(128, R.CStatLote);
  AssertTrue(R.TemEvento);
  AssertEquals(999, R.CStat);
  AssertEquals('', R.NProt);
  // a falha forcada nao registrou nada: a proxima tentativa vale
  AssertEquals(135, FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).CStat);
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
  AssertTrue('fsConsumoIndevido nao se aplica a evento', LLevantou);

  FSim.EnfileirarFalha(fsDocZipCorrompido);
  LLevantou := False;
  try
    FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1);
  except
    on Exception do LLevantou := True;
  end;
  AssertTrue('fsDocZipCorrompido nao se aplica a evento', LLevantou);
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
  AssertTrue('fsEventoRejeitado nao se aplica a Consultar', LLevantou);
end;

procedure TDFeSimuladorEventoNucleoTests.Falhas_ConsumidasUmaPorChamada;
begin
  FSim.EnfileirarFalha(fsTimeout);
  AssertTrue(FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).Tipo = trsTimeout);
  AssertTrue(FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1).Tipo = trsLote);
end;

procedure TDFeSimuladorEventoNucleoTests.Contadores_TotalEEventosRegistrados;
begin
  PublicarNFeDoDestinatario;
  FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1);
  FSim.ReceberEvento(CNPJ_DEST, FChave, '210210', 1); // duplicidade
  AssertEquals(2, FSim.TotalEventos);
  AssertEquals(1, FSim.EventosRegistrados);
end;

{ TDFeSimuladorEventoSoapTests }

procedure TDFeSimuladorEventoSoapTests.SetUp;
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
  AssertEquals('ID1', ExtrairAtributo('<a><infEvento Id="ID1" x="2"><b/></infEvento></a>', 'infEvento', 'Id'));
  AssertEquals('2', ExtrairAtributo('<infEvento Id="ID1" x="2">', 'infEvento', 'x'));
  AssertEquals('', ExtrairAtributo('<infEvento Id="ID1">', 'infEvento', 'y'));
  AssertEquals('', ExtrairAtributo('<a y="1"><infEvento Id="ID1">', 'infEvento', 'y'));
  AssertEquals('', ExtrairAtributo('<a/>', 'infEvento', 'Id'));
end;

procedure TDFeSimuladorEventoSoapTests.RequisicaoDoAcbr_NaoGeraViolacao;
begin
  PublicarNFeDoDestinatario;
  Transmitir(Requisicao);
  AssertEquals(FTransmissor.TodasViolacoes, 0, FTransmissor.QuantidadeViolacoes);
  AssertEquals(1, FTransmissor.Requisicoes);
end;

procedure TDFeSimuladorEventoSoapTests.Registrado_RespondeRetEnvEventoComProtocolo;
var
  R: TDFeRespostaTransmissao;
begin
  PublicarNFeDoDestinatario;
  R := Transmitir(Requisicao);
  AssertEquals(200, R.HTTPResultCode);
  AssertTrue(Pos('<nfeResultMsg xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeRecepcaoEvento4">', R.Texto) > 0);
  AssertTrue(Pos('<retEnvEvento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00"><idLote>1</idLote>', R.Texto) > 0);
  AssertTrue(Pos('<cStat>128</cStat>', R.Texto) > 0);
  AssertTrue(Pos('<cStat>135</cStat>', R.Texto) > 0);
  AssertTrue(Pos('<chNFe>' + FChave + '</chNFe>', R.Texto) > 0);
  AssertTrue(Pos('<tpEvento>210210</tpEvento>', R.Texto) > 0);
  AssertTrue(Pos('<nProt>891000000000001</nProt>', R.Texto) > 0);
  AssertTrue(Pos('<dhRegEvento>2026-09-18T10:00:00-03:00</dhRegEvento>', R.Texto) > 0);
  AssertTrue(Pos('<CNPJDest>' + CNPJ_DEST + '</CNPJDest>', R.Texto) > 0);
end;

procedure TDFeSimuladorEventoSoapTests.ChaveDesconhecida_RespondeRegistradoNaoVinculado136ComProtocolo;
var
  R: TDFeRespostaTransmissao;
begin
  R := Transmitir(Requisicao); // nada publicado: NT 4.9.9, registrado mas nao vinculado
  AssertTrue(Pos('<cStat>128</cStat>', R.Texto) > 0);
  AssertTrue(Pos('<cStat>136</cStat>', R.Texto) > 0);
  AssertTrue(Pos('<nProt>891000000000001</nProt>', R.Texto) > 0);
  AssertTrue(Pos('<dhRegEvento>', R.Texto) > 0);
end;

procedure TDFeSimuladorEventoSoapTests.LoteRejeitado_RespondeSemRetEvento;
var
  R: TDFeRespostaTransmissao;
begin
  FSim.EnfileirarFalha(fsLoteEventoRejeitado);
  R := Transmitir(Requisicao);
  AssertTrue(Pos('<cStat>999</cStat>', R.Texto) > 0);
  AssertTrue(Pos('<retEvento', R.Texto) = 0);
end;

procedure TDFeSimuladorEventoSoapTests.Timeout_ErroHttp_CorpoIlegivel_TiposDeTransporte;
var
  R: TDFeRespostaTransmissao;
begin
  FSim.EnfileirarFalha(fsTimeout);
  FSim.EnfileirarFalha(fsErroHttp);
  FSim.EnfileirarFalha(fsCorpoIlegivel);
  R := Transmitir(Requisicao);
  AssertEquals(10060, R.InternalErrorCode);
  R := Transmitir(Requisicao);
  AssertEquals(500, R.HTTPResultCode);
  AssertTrue(Pos('<soap:Fault>', R.Texto) > 0);
  R := Transmitir(Requisicao);
  AssertEquals(200, R.HTTPResultCode);
  AssertTrue(Pos('<html>', R.Texto) > 0);
end;

procedure TDFeSimuladorEventoSoapTests.OperacaoNaoRealizada_ExigeXJust;
begin
  Transmitir(Requisicao('210240', 'Operacao nao Realizada'));
  AssertTrue(Pos('exige xJust', FTransmissor.TodasViolacoes) > 0);

  Transmitir(Requisicao('210240', 'Operacao nao Realizada', '91', 2, True, 'mercadoria nao foi entregue no prazo'));
  // a segunda requisicao (com xJust) nao acrescenta violacao de xJust
  AssertEquals(1, FTransmissor.QuantidadeViolacoes);
end;

procedure TDFeSimuladorEventoSoapTests.XJust_EmTipoQueNaoAceita_EViolacao;
begin
  // NT 2012/002, HP20: xJust "deve ser informado somente no evento de Operacao nao Realizada"
  Transmitir(Requisicao('210220', 'Desconhecimento da Operacao', '91', 1, True,
    'Desconhecemos esta operacao comercial'));
  AssertTrue(Pos('so'' pode ser informado em 210240', FTransmissor.TodasViolacoes) > 0);
end;

procedure TDFeSimuladorEventoSoapTests.XJust_TamanhoForaDe15a255_EViolacao;
begin
  Transmitir(Requisicao('210240', 'Operacao nao Realizada', '91', 1, True, 'curto'));
  AssertTrue(Pos('15 a 255', FTransmissor.TodasViolacoes) > 0);
end;

procedure TDFeSimuladorEventoSoapTests.Violacao_OrgaoDiferenteDe91;
begin
  Transmitir(Requisicao('210210', 'Ciencia da Operacao', '43'));
  AssertTrue(Pos('cOrgao', FTransmissor.TodasViolacoes) > 0);
end;

procedure TDFeSimuladorEventoSoapTests.Violacao_IdDoEventoIncoerente;
begin
  Transmitir(StringReplace(Requisicao, 'Id="ID210210' + FChave + '01"', 'Id="IDerrado"', []));
  AssertTrue(Pos('infEvento/@Id', FTransmissor.TodasViolacoes) > 0);
end;

procedure TDFeSimuladorEventoSoapTests.Violacao_SemAssinatura;
begin
  Transmitir(Requisicao('210210', 'Ciencia da Operacao', '91', 1, False));
  AssertTrue(Pos('sem <Signature>', FTransmissor.TodasViolacoes) > 0);
end;

procedure TDFeSimuladorEventoSoapTests.Violacao_ReferenceUriDiferenteDoId;
begin
  Transmitir(StringReplace(Requisicao, 'Reference URI="#ID', 'Reference URI="#XX', []));
  AssertTrue(Pos('Reference/@URI', FTransmissor.TodasViolacoes) > 0);
end;

procedure TDFeSimuladorEventoSoapTests.Violacao_TipoDeEventoQueNaoEManifestacao;
begin
  Transmitir(Requisicao('110111', 'Cancelamento'));
  AssertTrue(Pos('nao e'' manifestacao', FTransmissor.TodasViolacoes) > 0);
end;

procedure TDFeSimuladorEventoSoapTests.Violacao_DhEventoForaDoFormato;
begin
  Transmitir(StringReplace(Requisicao, '2026-09-18T18:44:03-03:00', '18/09/2026 18:44', []));
  AssertTrue(Pos('dhEvento', FTransmissor.TodasViolacoes) > 0);
end;

procedure TDFeSimuladorEventoSoapTests.Violacao_UrlESoapActionDeEvento;
begin
  Transmitir(Requisicao, 'https://exemplo.invalido/outro.asmx');
  AssertTrue(Pos('URL inesperada para RecepcaoEvento', FTransmissor.TodasViolacoes) > 0);
end;

initialization
  RegisterTest(TDFeSimuladorEventoNucleoTests);
  RegisterTest(TDFeSimuladorEventoSoapTests);

end.
