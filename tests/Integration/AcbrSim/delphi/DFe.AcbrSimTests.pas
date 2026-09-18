unit DFe.AcbrSimTests;

{ O client ACBr REAL (TDFeDistribuicaoClientACBrNFe) contra o simulador da
  SEFAZ, com o transporte substituido por TDFeSimuladorTransmissor
  (OnTransmit) -- ver docs/simulador-sefaz.md. Roda de verdade: montagem do
  envelope SOAP, parse da resposta, cStat, gunzip do docZip, carga do
  certificado (OpenSSL) e traducao de erros para DFe.Errors.

  NAO cobre: TLS/HTTP reais, a SEFAZ de verdade, EnviarEvento (Fase 4). }

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  ACBrDFe.Conversao,
  DFe.Types,
  DFe.Errors,
  DFe.Provider,
  DFe.Provider.NFe,
  DFe.Orquestrador,
  DFe.Transmissor,
  DFe.Simulador,
  DFe.Simulador.Soap,
  DFe.Simulador.Fixtures,
  DFe.Client.ACBrNFe,
  DFe.TestDoubles;

type
  [TestFixture]
  TDFeAcbrSimTests = class
  private
    FRelogio: TDFeRelogioFake;
    FSim: TDFeSimuladorSefaz;
    FTransmissor: TDFeSimuladorTransmissor;
    FTransmissorIntf: IDFeTransmissor;
    function DiretorioBase: string;
    function Certificado: TDFeCertificado;
    function NovoClient(const APfx: string = 'valido.pfx'): IDFeDistribuicaoClient;
    procedure PublicarNFe(const ANumero: Integer; const AXNome: string = DFE_SIM_XNOME_EMITENTE);
    procedure AssertSemViolacoes;
    procedure PublicarLoteQueOAcbrTrunca;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure Consultar137_NenhumDocumento;
    [Test] procedure Consultar138_QuatroSchemasDaDistribuicao;
    [Test] procedure Consultar138_UltimoNSUEnviadoChegaNoRequest;
    [Test] procedure Acentos_ChegamComoUtf8AoLote;
    [Test] procedure ConsumoIndevido656_ELoteNaoExcecao;
    [Test] procedure Indisponivel108_ELoteNaoExcecao;
    [Test] procedure Timeout_ViraComunicacaoFalhou;
    [Test] procedure ErroHttp500_ViraComunicacaoFalhou;
    [Test] procedure CorpoIlegivelComHttp200_ViraRespostaInvalida;
    [Test] procedure DocZipCorrompido_NaoPassaDespercebido;
    [Test] procedure LoteTruncadoPeloAcbr_ViraRespostaInvalidaEmVezDePerderDocumentos;
    [Test] procedure LoteTruncadoPeloAcbr_OrquestradorNaoAvancaOCursor;
    [Test] procedure ClientRecuperaAposFalha_SemEstadoSujo;
    [Test] procedure CertificadoVencido_ViraCertificadoInvalidoSemChamarATransmissao;
    [Test] procedure CnpjDivergenteDoCertificado_ViraCertificadoInvalido;
    [Test] procedure FimAFim_OrquestradorProviderNFeEPublicador;
    [Test] procedure FimAFim_AcentosChegamAoPayloadPublicado;
  end;

implementation

const
  CNPJ_CERT = '11222333000181'; // o do certificado sintetico cert-teste\valido.pfx
  SENHA_CERT = 'teste123';


{ "JOSE ACAI LTDA" com E, C e I acentuados. No FPC, String carrega BYTES UTF-8
  (convencao do projeto); no Delphi, String e' UnicodeString e o mesmo texto
  sao os proprios caracteres. Este helper e' o que deixa o mesmo teste rodar
  nos dois -- e o teste no Delphi e' o experimento que mostra QUE forma o
  ACBr devolve la'. }
function XNomeAcentuado: string;
begin
  {$IFDEF FPC}
  Result := 'JOS' + #$C3#$89 + ' A' + #$C3#$87 + 'A' + #$C3#$8D + ' LTDA';
  {$ELSE}
  Result := 'JOS' + #$00C9 + ' A' + #$00C7 + 'A' + #$00CD + ' LTDA';
  {$ENDIF}
end;

{ Diagnostico: ordinais dos caracteres (2 digitos se cabem num byte, 4 se
  nao) -- para a mensagem de falha mostrar EXATAMENTE que codificacao chegou. }
function HexDe(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    if Ord(S[I]) < 256 then
      Result := Result + IntToHex(Ord(S[I]), 2) + ' '
    else
      Result := Result + IntToHex(Ord(S[I]), 4) + ' ';
end;

{ Trecho de AXml (ate 60 chars) a partir de ATag -- para mensagens de falha. }
function TrechoDe(const AXml, ATag: string): string;
var
  P: Integer;
begin
  P := Pos(ATag, AXml);
  if P = 0 then
    Result := '(' + ATag + ' ausente)'
  else
    Result := Copy(AXml, P, 60);
end;


function MsgAcento(const AEsperado, AXml, ATag: string): string;
begin
  Result := 'texto acentuado deveria chegar intacto (esperado ' + HexDe(AEsperado) +
    '; chegou ' + HexDe(TrechoDe(AXml, ATag)) + ')';
end;

{ TDFeAcbrSimTests }

procedure TDFeAcbrSimTests.Setup;
begin
  FRelogio := TDFeRelogioFake.Create;
  FRelogio.Agora := EncodeDate(2026, 9, 18) + EncodeTime(10, 0, 0, 0);
  FSim := TDFeSimuladorSefaz.Create(FRelogio.ObterAgora);
  FTransmissor := TDFeSimuladorTransmissor.Create(FSim);
  FTransmissorIntf := FTransmissor;
end;

procedure TDFeAcbrSimTests.TearDown;
begin
  FTransmissorIntf := nil; // solta o transmissor (e o client que o segura) antes do simulador
  FTransmissor := nil;
  FSim.Free;
  FRelogio.Free;
end;

function TDFeAcbrSimTests.DiretorioBase: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

function TDFeAcbrSimTests.Certificado: TDFeCertificado;
begin
  Result.Identificador := 'teste';
  Result.CnpjCpf := CNPJ_CERT;
  Result.UF := 'RS';
end;

function TDFeAcbrSimTests.NovoClient(const APfx: string): IDFeDistribuicaoClient;
var
  LCred: TDFeCredencialCertificado;
begin
  LCred.ArquivoPFX := DiretorioBase + 'cert-teste' + PathDelim + APfx;
  LCred.Senha := SENHA_CERT;
  LCred.PathSchemas := DiretorioBase + 'Schemas' + PathDelim;
  Assert.IsTrue(FileExists(LCred.ArquivoPFX), 'certificado de teste nao encontrado: ' + LCred.ArquivoPFX);
  Result := TDFeDistribuicaoClientACBrNFe.Create(LCred, taHomologacao, FTransmissorIntf);
end;

procedure TDFeAcbrSimTests.PublicarNFe(const ANumero: Integer; const AXNome: string);
begin
  FSim.PublicarDocumento(CNPJ_CERT, 'RS', DFE_SIM_SCHEMA_RESNFE,
    XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, ANumero), DFE_SIM_CNPJ_EMITENTE, AXNome));
end;

procedure TDFeAcbrSimTests.AssertSemViolacoes;
begin
  Assert.AreEqual(0, FTransmissor.QuantidadeViolacoes, 'violacoes no request do ACBr: ' + FTransmissor.TodasViolacoes);
end;

procedure TDFeAcbrSimTests.Consultar137_NenhumDocumento;
var
  LLote: TDFeLoteBruto;
begin
  LLote := NovoClient.Consultar(Certificado, 0);
  Assert.AreEqual(137, LLote.CStat);
  Assert.AreEqual(0, Length(LLote.Itens));
  Assert.AreEqual(1, FTransmissor.Requisicoes);
  AssertSemViolacoes;
end;

procedure TDFeAcbrSimTests.Consultar138_QuatroSchemasDaDistribuicao;
var
  LLote: TDFeLoteBruto;
  LChave: string;
begin
  LChave := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1);
  FSim.PublicarDocumento(CNPJ_CERT, 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(LChave));
  FSim.PublicarDocumento(CNPJ_CERT, 'RS', DFE_SIM_SCHEMA_PROCNFE, XmlProcNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 2)));
  FSim.PublicarDocumento(CNPJ_CERT, 'RS', DFE_SIM_SCHEMA_RESEVENTO, XmlResEvento(LChave, '110111'));
  FSim.PublicarDocumento(CNPJ_CERT, 'RS', DFE_SIM_SCHEMA_PROCEVENTONFE, XmlProcEventoNFe(LChave, '210210'));

  LLote := NovoClient.Consultar(Certificado, 0);

  Assert.AreEqual(138, LLote.CStat);
  Assert.AreEqual(4, Length(LLote.Itens));
  Assert.AreEqual(Int64(4), LLote.UltimoNSU);
  Assert.AreEqual(Int64(4), LLote.MaxNSU);
  Assert.AreEqual('resNFe', LLote.Itens[0].Schema);
  Assert.AreEqual('procNFe', LLote.Itens[1].Schema);
  Assert.AreEqual('resEvento', LLote.Itens[2].Schema);
  Assert.AreEqual('procEventoNFe', LLote.Itens[3].Schema);
  Assert.AreEqual(Int64(1), LLote.Itens[0].NSU);
  Assert.AreEqual(Int64(4), LLote.Itens[3].NSU);
  Assert.IsTrue(Pos(LChave, LLote.Itens[0].XmlDecodificado) > 0, 'resNFe traz a chave');
  Assert.IsTrue(Pos('<tpEvento>110111</tpEvento>', LLote.Itens[2].XmlDecodificado) > 0, 'resEvento traz o tpEvento');
  AssertSemViolacoes;
end;

procedure TDFeAcbrSimTests.Consultar138_UltimoNSUEnviadoChegaNoRequest;
begin
  PublicarNFe(1);
  PublicarNFe(2);
  NovoClient.Consultar(Certificado, 1);
  Assert.AreEqual(Int64(1), FSim.UltimoNSURecebido);
  Assert.IsTrue(Pos('<ultNSU>000000000000001</ultNSU>', FTransmissor.UltimoEnvelope) > 0, 'envelope leva o ultNSU de 15 digitos');
  Assert.IsTrue(Pos('<CNPJ>' + CNPJ_CERT + '</CNPJ>', FTransmissor.UltimoEnvelope) > 0, 'envelope leva o CNPJ do certificado');
  Assert.IsTrue(Pos('<cUFAutor>43</cUFAutor>', FTransmissor.UltimoEnvelope) > 0, 'cUFAutor de RS = 43');
  Assert.IsTrue(Pos('<tpAmb>2</tpAmb>', FTransmissor.UltimoEnvelope) > 0, 'homologacao');
  AssertSemViolacoes;
end;

procedure TDFeAcbrSimTests.Acentos_ChegamComoUtf8AoLote;
var
  LLote: TDFeLoteBruto;
  LXNome: string;
begin
  LXNome := XNomeAcentuado;
  PublicarNFe(1, LXNome);
  LLote := NovoClient.Consultar(Certificado, 0);
  Assert.AreEqual(1, Length(LLote.Itens));
  Assert.IsTrue(Pos('<xNome>' + LXNome + '</xNome>', LLote.Itens[0].XmlDecodificado) > 0, MsgAcento(LXNome, LLote.Itens[0].XmlDecodificado, '<xNome>'));
end;

procedure TDFeAcbrSimTests.ConsumoIndevido656_ELoteNaoExcecao;
var
  LClient: IDFeDistribuicaoClient;
  LLote: TDFeLoteBruto;
begin
  LClient := NovoClient;
  Assert.AreEqual(137, LClient.Consultar(Certificado, 0).CStat);
  LLote := LClient.Consultar(Certificado, 0);
  Assert.AreEqual(656, LLote.CStat);
  Assert.AreEqual(0, Length(LLote.Itens));
  Assert.IsTrue(ClassificarCStat(LLote.CStat, 656) = dccConsumoIndevido);
end;

procedure TDFeAcbrSimTests.Indisponivel108_ELoteNaoExcecao;
var
  LLote: TDFeLoteBruto;
begin
  FSim.EnfileirarFalha(fsIndisponivelCurtoPrazo);
  LLote := NovoClient.Consultar(Certificado, 0);
  Assert.AreEqual(108, LLote.CStat);
  Assert.IsTrue(ClassificarCStat(LLote.CStat, 656) = dccServicoIndisponivel);
end;

procedure TDFeAcbrSimTests.Timeout_ViraComunicacaoFalhou;
var
  LClient: IDFeDistribuicaoClient;
begin
  FSim.EnfileirarFalha(fsTimeout);
  LClient := NovoClient;
  try
    LClient.Consultar(Certificado, 0);
    Assert.Fail('esperava EDFeComunicacaoFalhou');
  except
    on EDFeComunicacaoFalhou do ;
  end;
end;

procedure TDFeAcbrSimTests.ErroHttp500_ViraComunicacaoFalhou;
var
  LClient: IDFeDistribuicaoClient;
begin
  FSim.EnfileirarFalha(fsErroHttp);
  LClient := NovoClient;
  try
    LClient.Consultar(Certificado, 0);
    Assert.Fail('esperava EDFeComunicacaoFalhou');
  except
    on EDFeComunicacaoFalhou do ;
  end;
end;

procedure TDFeAcbrSimTests.CorpoIlegivelComHttp200_ViraRespostaInvalida;
var
  LClient: IDFeDistribuicaoClient;
begin
  FSim.EnfileirarFalha(fsCorpoIlegivel);
  LClient := NovoClient;
  try
    LClient.Consultar(Certificado, 0);
    Assert.Fail('esperava EDFeRespostaInvalida');
  except
    on EDFeRespostaInvalida do ;
  end;
end;

procedure TDFeAcbrSimTests.DocZipCorrompido_NaoPassaDespercebido;
var
  LClient: IDFeDistribuicaoClient;
  LLote: TDFeLoteBruto;
begin
  PublicarNFe(1);
  FSim.EnfileirarFalha(fsDocZipCorrompido);
  LClient := NovoClient;
  try
    LLote := LClient.Consultar(Certificado, 0);
    Assert.Fail(Format('docZip corrompido virou lote "valido": cStat=%d itens=%d xml0="%s"',
      [LLote.CStat, Length(LLote.Itens), Copy(LLote.Itens[0].XmlDecodificado, 1, 60)]));
  except
    on EDFeRespostaInvalida do ;
  end;
end;

{ Publica [resNFe ok, procNFe SEM <tpNF> (o parser do ACBr rejeita e ENGOLE o
  erro), resEvento ok]: sem a conferencia do client o lote sairia com so' 2
  itens e ultNSU=3 no cabecalho -- o resEvento seria perdido para sempre. }
procedure TDFeAcbrSimTests.PublicarLoteQueOAcbrTrunca;
var
  LChave: string;
begin
  LChave := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1);
  FSim.PublicarDocumento(CNPJ_CERT, 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(LChave));
  FSim.PublicarDocumento(CNPJ_CERT, 'RS', DFE_SIM_SCHEMA_PROCNFE,
    StringReplace(XmlProcNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 2)), '<tpNF>1</tpNF>', '', []));
  FSim.PublicarDocumento(CNPJ_CERT, 'RS', DFE_SIM_SCHEMA_RESEVENTO, XmlResEvento(LChave, '110111'));
end;

procedure TDFeAcbrSimTests.LoteTruncadoPeloAcbr_ViraRespostaInvalidaEmVezDePerderDocumentos;
var
  LClient: IDFeDistribuicaoClient;
begin
  PublicarLoteQueOAcbrTrunca;
  LClient := NovoClient;
  try
    LClient.Consultar(Certificado, 0);
    Assert.Fail('esperava EDFeRespostaInvalida: o lote truncado nao pode ser entregue como valido');
  except
    on E: EDFeRespostaInvalida do
      Assert.IsTrue(Pos('truncado', E.Message) > 0, 'mensagem explica o truncamento: ' + E.Message);
  end;
end;

procedure TDFeAcbrSimTests.LoteTruncadoPeloAcbr_OrquestradorNaoAvancaOCursor;
var
  LPublicador: TDFePublicadorFake;
  LCursor: TDFeCursorStoreFake;
  LOrq: TDFeOrquestradorTestavel;
  LClient: IDFeDistribuicaoClient;
begin
  PublicarLoteQueOAcbrTrunca;
  LPublicador := TDFePublicadorFake.Create;
  LCursor := TDFeCursorStoreFake.Create;
  LOrq := TDFeOrquestradorTestavel.Create(LPublicador);
  try
    LOrq.AgoraSimulado := FRelogio.Agora;
    LClient := NovoClient;
    LOrq.AdicionarUnidade(TDFeUnidadeTrabalho.Create(TDFeProviderNFe.Create, LClient, Certificado, LCursor));
    LOrq.ExecutarCiclo;

    Assert.AreEqual(0, LPublicador.Quantidade);
    Assert.AreEqual(Int64(0), LCursor.ObterUltimoNSU(MontarNamespaceCursor('nfe', Certificado)));
    Assert.AreEqual(1, LOrq.QuantidadeErros);
  finally
    LOrq.Free;
  end;
end;

procedure TDFeAcbrSimTests.ClientRecuperaAposFalha_SemEstadoSujo;
var
  LClient: IDFeDistribuicaoClient;
begin
  LClient := NovoClient;
  FSim.EnfileirarFalha(fsCorpoIlegivel);
  try
    LClient.Consultar(Certificado, 0);
  except
    on EDFeRespostaInvalida do ;
  end;
  FSim.EnfileirarFalha(fsTimeout);
  try
    LClient.Consultar(Certificado, 0);
  except
    on EDFeComunicacaoFalhou do ;
  end;
  // depois de duas falhas seguidas, a mesma instancia consulta normalmente
  Assert.AreEqual(137, LClient.Consultar(Certificado, 0).CStat);
end;

procedure TDFeAcbrSimTests.CertificadoVencido_ViraCertificadoInvalidoSemChamarATransmissao;
var
  LClient: IDFeDistribuicaoClient;
begin
  LClient := NovoClient('vencido.pfx');
  try
    LClient.Consultar(Certificado, 0);
    Assert.Fail('esperava EDFeCertificadoInvalido');
  except
    on EDFeCertificadoInvalido do ;
  end;
  Assert.AreEqual(0, FTransmissor.Requisicoes);
end;

procedure TDFeAcbrSimTests.CnpjDivergenteDoCertificado_ViraCertificadoInvalido;
var
  LClient: IDFeDistribuicaoClient;
  LCert: TDFeCertificado;
begin
  LCert := Certificado;
  LCert.CnpjCpf := '11444777000161'; // CNPJ valido, raiz diferente da do certificado
  LClient := NovoClient;
  try
    LClient.Consultar(LCert, 0);
    Assert.Fail('esperava EDFeCertificadoInvalido');
  except
    on EDFeCertificadoInvalido do ;
  end;
  Assert.AreEqual(0, FTransmissor.Requisicoes);
end;

procedure TDFeAcbrSimTests.FimAFim_OrquestradorProviderNFeEPublicador;
var
  LPublicador: TDFePublicadorFake;
  LCursor: TDFeCursorStoreFake;
  LOrq: TDFeOrquestradorTestavel;
  LClient: IDFeDistribuicaoClient;
  LChave: string;
begin
  LChave := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1);
  FSim.PublicarDocumento(CNPJ_CERT, 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(LChave));
  FSim.PublicarDocumento(CNPJ_CERT, 'RS', DFE_SIM_SCHEMA_PROCNFE, XmlProcNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 2)));
  FSim.PublicarDocumento(CNPJ_CERT, 'RS', DFE_SIM_SCHEMA_RESEVENTO, XmlResEvento(LChave, '110111'));
  FSim.PublicarDocumento(CNPJ_CERT, 'RS', DFE_SIM_SCHEMA_PROCEVENTONFE, XmlProcEventoNFe(LChave, '210210'));

  LPublicador := TDFePublicadorFake.Create;
  LCursor := TDFeCursorStoreFake.Create;
  LOrq := TDFeOrquestradorTestavel.Create(LPublicador);
  try
    LOrq.AgoraSimulado := FRelogio.Agora;
    LClient := NovoClient;
    LOrq.AdicionarUnidade(TDFeUnidadeTrabalho.Create(TDFeProviderNFe.Create, LClient, Certificado, LCursor));

    LOrq.ExecutarCiclo;

    Assert.AreEqual(4, LPublicador.Quantidade);
    Assert.AreEqual('nfe.documento.rs.' + CNPJ_CERT, LPublicador.RoutingKey(0));
    Assert.AreEqual('nfe.documento.rs.' + CNPJ_CERT, LPublicador.RoutingKey(1));
    Assert.AreEqual('nfe.evento.cancelamento.rs.' + CNPJ_CERT, LPublicador.RoutingKey(2));
    Assert.AreEqual('nfe.evento.ciencia.rs.' + CNPJ_CERT, LPublicador.RoutingKey(3));
    Assert.AreEqual(Int64(4), LCursor.ObterUltimoNSU(MontarNamespaceCursor('nfe', Certificado)));
    Assert.AreEqual(0, LOrq.QuantidadeErros);
    Assert.AreEqual(0, LOrq.QuantidadeAvisos);

    // +1h: 137, sem publicar e sem consumo indevido (janela igual nos dois lados)
    FRelogio.Agora := FRelogio.Agora + 1 / 24;
    LOrq.AgoraSimulado := FRelogio.Agora;
    LOrq.ExecutarCiclo;
    Assert.AreEqual(4, LPublicador.Quantidade);
    Assert.AreEqual(0, LOrq.QuantidadeAvisos);
    AssertSemViolacoes;
  finally
    LOrq.Free;
  end;
end;

procedure TDFeAcbrSimTests.FimAFim_AcentosChegamAoPayloadPublicado;
var
  LPublicador: TDFePublicadorFake;
  LCursor: TDFeCursorStoreFake;
  LOrq: TDFeOrquestradorTestavel;
  LClient: IDFeDistribuicaoClient;
  LXNome: string;
begin
  LXNome := XNomeAcentuado;
  PublicarNFe(1, LXNome);

  LPublicador := TDFePublicadorFake.Create;
  LCursor := TDFeCursorStoreFake.Create;
  LOrq := TDFeOrquestradorTestavel.Create(LPublicador);
  try
    LOrq.AgoraSimulado := FRelogio.Agora;
    LClient := NovoClient;
    LOrq.AdicionarUnidade(TDFeUnidadeTrabalho.Create(TDFeProviderNFe.Create, LClient, Certificado, LCursor));
    LOrq.ExecutarCiclo;

    Assert.AreEqual(1, LPublicador.Quantidade);
    Assert.IsTrue(Pos('<xNome>' + LXNome + '</xNome>', LPublicador.Payload(0)) > 0, MsgAcento(LXNome, LPublicador.Payload(0), '<xNome>'));
  finally
    LOrq.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeAcbrSimTests);

end.
