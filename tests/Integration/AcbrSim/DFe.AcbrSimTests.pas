unit DFe.AcbrSimTests;

{ O client ACBr REAL (TDFeDistribuicaoClientACBrNFe) contra o simulador da
  SEFAZ, com o transporte substituido por TDFeSimuladorTransmissor
  (OnTransmit) -- ver docs/simulador-sefaz.md. Roda de verdade: montagem do
  envelope SOAP, parse da resposta, cStat, gunzip do docZip, carga do
  certificado (OpenSSL) e traducao de erros para DFe.Errors.

  NAO cobre: TLS/HTTP reais, a SEFAZ de verdade, EnviarEvento (Fase 4). }

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils,
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
  TDFeAcbrSimTests = class(TTestCase)
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
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Consultar137_NenhumDocumento;
    procedure Consultar138_QuatroSchemasDaDistribuicao;
    procedure Consultar138_UltimoNSUEnviadoChegaNoRequest;
    procedure Acentos_ChegamComoUtf8AoLote;
    procedure ConsumoIndevido656_ELoteNaoExcecao;
    procedure Indisponivel108_ELoteNaoExcecao;
    procedure Timeout_ViraComunicacaoFalhou;
    procedure ErroHttp500_ViraComunicacaoFalhou;
    procedure CorpoIlegivelComHttp200_ViraRespostaInvalida;
    procedure DocZipCorrompido_NaoPassaDespercebido;
    procedure LoteTruncadoPeloAcbr_ViraRespostaInvalidaEmVezDePerderDocumentos;
    procedure LoteTruncadoPeloAcbr_OrquestradorNaoAvancaOCursor;
    procedure ClientRecuperaAposFalha_SemEstadoSujo;
    procedure CertificadoVencido_ViraCertificadoInvalidoSemChamarATransmissao;
    procedure CnpjDivergenteDoCertificado_ViraCertificadoInvalido;
    procedure FimAFim_OrquestradorProviderNFeEPublicador;
    procedure FimAFim_AcentosChegamAoPayloadPublicado;
  end;

implementation

const
  CNPJ_CERT = '11222333000181'; // o do certificado sintetico cert-teste\valido.pfx
  SENHA_CERT = 'teste123';

{ TDFeAcbrSimTests }

procedure TDFeAcbrSimTests.SetUp;
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
  AssertTrue('certificado de teste nao encontrado: ' + LCred.ArquivoPFX, FileExists(LCred.ArquivoPFX));
  Result := TDFeDistribuicaoClientACBrNFe.Create(LCred, taHomologacao, FTransmissorIntf);
end;

procedure TDFeAcbrSimTests.PublicarNFe(const ANumero: Integer; const AXNome: string);
begin
  FSim.PublicarDocumento(CNPJ_CERT, 'RS', DFE_SIM_SCHEMA_RESNFE,
    XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, ANumero), DFE_SIM_CNPJ_EMITENTE, AXNome));
end;

procedure TDFeAcbrSimTests.AssertSemViolacoes;
begin
  AssertEquals('violacoes no request do ACBr: ' + FTransmissor.TodasViolacoes,
    0, FTransmissor.QuantidadeViolacoes);
end;

procedure TDFeAcbrSimTests.Consultar137_NenhumDocumento;
var
  LLote: TDFeLoteBruto;
begin
  LLote := NovoClient.Consultar(Certificado, 0);
  AssertEquals(137, LLote.CStat);
  AssertEquals(0, Length(LLote.Itens));
  AssertEquals(1, FTransmissor.Requisicoes);
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

  AssertEquals(138, LLote.CStat);
  AssertEquals(4, Length(LLote.Itens));
  AssertEquals(Int64(4), LLote.UltimoNSU);
  AssertEquals(Int64(4), LLote.MaxNSU);
  AssertEquals('resNFe', LLote.Itens[0].Schema);
  AssertEquals('procNFe', LLote.Itens[1].Schema);
  AssertEquals('resEvento', LLote.Itens[2].Schema);
  AssertEquals('procEventoNFe', LLote.Itens[3].Schema);
  AssertEquals(Int64(1), LLote.Itens[0].NSU);
  AssertEquals(Int64(4), LLote.Itens[3].NSU);
  AssertTrue('resNFe traz a chave', Pos(LChave, LLote.Itens[0].XmlDecodificado) > 0);
  AssertTrue('resEvento traz o tpEvento', Pos('<tpEvento>110111</tpEvento>', LLote.Itens[2].XmlDecodificado) > 0);
  AssertSemViolacoes;
end;

procedure TDFeAcbrSimTests.Consultar138_UltimoNSUEnviadoChegaNoRequest;
begin
  PublicarNFe(1);
  PublicarNFe(2);
  NovoClient.Consultar(Certificado, 1);
  AssertEquals(Int64(1), FSim.UltimoNSURecebido);
  AssertTrue('envelope leva o ultNSU de 15 digitos',
    Pos('<ultNSU>000000000000001</ultNSU>', FTransmissor.UltimoEnvelope) > 0);
  AssertTrue('envelope leva o CNPJ do certificado',
    Pos('<CNPJ>' + CNPJ_CERT + '</CNPJ>', FTransmissor.UltimoEnvelope) > 0);
  AssertTrue('cUFAutor de RS = 43', Pos('<cUFAutor>43</cUFAutor>', FTransmissor.UltimoEnvelope) > 0);
  AssertTrue('homologacao', Pos('<tpAmb>2</tpAmb>', FTransmissor.UltimoEnvelope) > 0);
  AssertSemViolacoes;
end;

procedure TDFeAcbrSimTests.Acentos_ChegamComoUtf8AoLote;
var
  LLote: TDFeLoteBruto;
  LXNome: string;
begin
  // "JOSE ACAI LTDA" com E, C e I acentuados, em bytes UTF-8 explicitos
  LXNome := 'JOS' + #$C3#$89 + ' A' + #$C3#$87 + 'A' + #$C3#$8D + ' LTDA';
  PublicarNFe(1, LXNome);
  LLote := NovoClient.Consultar(Certificado, 0);
  AssertEquals(1, Length(LLote.Itens));
  AssertTrue('bytes UTF-8 do xNome intactos (nao Latin-1, nao duplo-encode)',
    Pos('<xNome>' + LXNome + '</xNome>', LLote.Itens[0].XmlDecodificado) > 0);
end;

procedure TDFeAcbrSimTests.ConsumoIndevido656_ELoteNaoExcecao;
var
  LClient: IDFeDistribuicaoClient;
  LLote: TDFeLoteBruto;
begin
  LClient := NovoClient;
  AssertEquals(137, LClient.Consultar(Certificado, 0).CStat);
  LLote := LClient.Consultar(Certificado, 0);
  AssertEquals(656, LLote.CStat);
  AssertEquals(0, Length(LLote.Itens));
  AssertTrue(ClassificarCStat(LLote.CStat, 656) = dccConsumoIndevido);
end;

procedure TDFeAcbrSimTests.Indisponivel108_ELoteNaoExcecao;
var
  LLote: TDFeLoteBruto;
begin
  FSim.EnfileirarFalha(fsIndisponivelCurtoPrazo);
  LLote := NovoClient.Consultar(Certificado, 0);
  AssertEquals(108, LLote.CStat);
  AssertTrue(ClassificarCStat(LLote.CStat, 656) = dccServicoIndisponivel);
end;

procedure TDFeAcbrSimTests.Timeout_ViraComunicacaoFalhou;
var
  LClient: IDFeDistribuicaoClient;
begin
  FSim.EnfileirarFalha(fsTimeout);
  LClient := NovoClient;
  try
    LClient.Consultar(Certificado, 0);
    Fail('esperava EDFeComunicacaoFalhou');
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
    Fail('esperava EDFeComunicacaoFalhou');
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
    Fail('esperava EDFeRespostaInvalida');
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
    Fail(Format('docZip corrompido virou lote "valido": cStat=%d itens=%d xml0="%s"',
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
    Fail('esperava EDFeRespostaInvalida: o lote truncado nao pode ser entregue como valido');
  except
    on E: EDFeRespostaInvalida do
      AssertTrue('mensagem explica o truncamento: ' + E.Message, Pos('truncado', E.Message) > 0);
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

    AssertEquals(0, LPublicador.Quantidade);
    AssertEquals(Int64(0), LCursor.ObterUltimoNSU(MontarNamespaceCursor('nfe', Certificado)));
    AssertEquals(1, LOrq.QuantidadeErros);
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
  AssertEquals(137, LClient.Consultar(Certificado, 0).CStat);
end;

procedure TDFeAcbrSimTests.CertificadoVencido_ViraCertificadoInvalidoSemChamarATransmissao;
var
  LClient: IDFeDistribuicaoClient;
begin
  LClient := NovoClient('vencido.pfx');
  try
    LClient.Consultar(Certificado, 0);
    Fail('esperava EDFeCertificadoInvalido');
  except
    on EDFeCertificadoInvalido do ;
  end;
  AssertEquals(0, FTransmissor.Requisicoes);
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
    Fail('esperava EDFeCertificadoInvalido');
  except
    on EDFeCertificadoInvalido do ;
  end;
  AssertEquals(0, FTransmissor.Requisicoes);
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

    AssertEquals(4, LPublicador.Quantidade);
    AssertEquals('nfe.documento.rs.' + CNPJ_CERT, LPublicador.RoutingKey(0));
    AssertEquals('nfe.documento.rs.' + CNPJ_CERT, LPublicador.RoutingKey(1));
    AssertEquals('nfe.evento.cancelamento.rs.' + CNPJ_CERT, LPublicador.RoutingKey(2));
    AssertEquals('nfe.evento.ciencia.rs.' + CNPJ_CERT, LPublicador.RoutingKey(3));
    AssertEquals(Int64(4), LCursor.ObterUltimoNSU(MontarNamespaceCursor('nfe', Certificado)));
    AssertEquals(0, LOrq.QuantidadeErros);
    AssertEquals(0, LOrq.QuantidadeAvisos);

    // +1h: 137, sem publicar e sem consumo indevido (janela igual nos dois lados)
    FRelogio.Agora := FRelogio.Agora + 1 / 24;
    LOrq.AgoraSimulado := FRelogio.Agora;
    LOrq.ExecutarCiclo;
    AssertEquals(4, LPublicador.Quantidade);
    AssertEquals(0, LOrq.QuantidadeAvisos);
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
  LXNome := 'JOS' + #$C3#$89 + ' A' + #$C3#$87 + 'A' + #$C3#$8D + ' LTDA';
  PublicarNFe(1, LXNome);

  LPublicador := TDFePublicadorFake.Create;
  LCursor := TDFeCursorStoreFake.Create;
  LOrq := TDFeOrquestradorTestavel.Create(LPublicador);
  try
    LOrq.AgoraSimulado := FRelogio.Agora;
    LClient := NovoClient;
    LOrq.AdicionarUnidade(TDFeUnidadeTrabalho.Create(TDFeProviderNFe.Create, LClient, Certificado, LCursor));
    LOrq.ExecutarCiclo;

    AssertEquals(1, LPublicador.Quantidade);
    AssertTrue('payload publicado preserva os bytes UTF-8',
      Pos('<xNome>' + LXNome + '</xNome>', LPublicador.Payload(0)) > 0);
  finally
    LOrq.Free;
  end;
end;

initialization
  RegisterTest(TDFeAcbrSimTests);

end.
