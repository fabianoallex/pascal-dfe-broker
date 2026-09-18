unit DFe.AcbrSimEventoTests;

{ Fase 4 do simulador (docs/simulador-sefaz.md): EnviarEvento -- a
  manifestacao do destinatario -- do client ACBr REAL contra o simulador
  (RecepcaoEvento via OnTransmit). Roda de verdade: montagem do envEvento,
  ASSINATURA XMLDSig (libxml2 + OpenSSL), validacao contra os XSDs oficiais,
  parse do retEnvEvento e traducao para TDFeEventoNormalizado.

  Requisitos alem dos de DFe.AcbrSimTests: libxml2 nativa acessivel (ver
  docs/simulador-sefaz.md, "Sonda da Fase 4") e os XSDs oficiais de NFe em
  vendor\ACBr\Exemplos\ACBrDFe\Schemas\NFe (tools\init-acbr-submodule.sh).
  Sem eles os testes sao IGNORADOS no FPC (nao passam em silencio: o runner
  conta os ignorados). No Delphi o DUnitX nao ignora em execucao, entao eles
  FALHAM com o prefixo 'AMBIENTE NAO PREPARADO'. }

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  ACBrDFe.Conversao,
  ACBrDFeSSL,
  ACBrNFe,
  ACBrLibXml2Ext,
  DFe.Types,
  DFe.Errors,
  DFe.Provider,
  DFe.Provider.NFe,
  DFe.Orquestrador,
  DFe.Manifestacao,
  DFe.Transmissor,
  DFe.Simulador,
  DFe.Simulador.Soap,
  DFe.Simulador.Fixtures,
  DFe.Client.ACBrNFe,
  DFe.TestDoubles;

type
  [TestFixture]
  TDFeAcbrSimEventoTests = class
  private
    FRelogio: TDFeRelogioFake;
    FSim: TDFeSimuladorSefaz;
    FTransmissor: TDFeSimuladorTransmissor;
    FTransmissorIntf: IDFeTransmissor;
    FChave: string;
    function DiretorioBase: string;
    function DiretorioSchemas: string;
    function Certificado: TDFeCertificado;
    procedure ExigirAmbiente;
    function NovoClient(const APfx: string = 'valido.pfx'): IDFeDistribuicaoClient;
    function Manifestador(const AClient: IDFeDistribuicaoClient): IDFeManifestador;
    function Comando(const ATipo: string; const AJustificativa: string = ''): TDFeComandoManifestacao;
    procedure PublicarNFeDoDestinatario;
    procedure AssertSemViolacoes;
    function AssinaturaValida(const AEnvelope: string; out AMsg: string): Boolean;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure Ciencia_Registrada_SaiComTipoEventoDoComando;
    [Test] procedure OsQuatroTiposDeManifestacao_RegistramSemViolacoes;
    [Test] procedure Assinatura_ECriptograficamenteValida_ETampering_Invalida;
    [Test] procedure Duplicidade_ViraManifestacaoRejeitada573;
    [Test] procedure ChaveInexistente_ViraManifestacaoRejeitada494;
    [Test] procedure EventoRejeitadoForcado_ViraManifestacaoRejeitada;
    [Test] procedure LoteRejeitado_ViraManifestacaoRejeitadaComRetEnvEvento;
    [Test] procedure ServicoIndisponivel108_ViraManifestacaoRejeitada;
    [Test] procedure Timeout_ViraComunicacaoFalhou;
    [Test] procedure ErroHttp500_ViraComunicacaoFalhou;
    [Test] procedure CorpoIlegivelComHttp200_ViraRespostaInvalida;
    [Test] procedure CertificadoVencido_ViraCertificadoInvalidoSemChamarATransmissao;
    [Test] procedure JustificativaAcentuada_AcbrRemoveOsAcentosSilenciosamente;
    [Test] procedure FimAFim_CienciaAutomatica_PublicaDocumentoEEventoDeCiencia;
  end;

implementation

const
  CNPJ_CERT = '11222333000181';
  SENHA_CERT = 'teste123';


{ "Mercadoria nao foi entregue no prazo combinado" com "a" til. Mesmo motivo
  de XNomeAcentuado em DFe.AcbrSimTests: bytes UTF-8 no FPC, caractere no Delphi. }
function JustificativaComTil: string;
begin
  {$IFDEF FPC}
  Result := 'Mercadoria n' + #$C3#$A3 + 'o foi entregue no prazo combinado';
  {$ELSE}
  Result := 'Mercadoria n' + #$00E3 + 'o foi entregue no prazo combinado';
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

{ TDFeAcbrSimEventoTests }

procedure TDFeAcbrSimEventoTests.Setup;
begin
  FRelogio := TDFeRelogioFake.Create;
  FRelogio.Agora := EncodeDate(2026, 9, 18) + EncodeTime(10, 0, 0, 0);
  FSim := TDFeSimuladorSefaz.Create(FRelogio.ObterAgora);
  FTransmissor := TDFeSimuladorTransmissor.Create(FSim);
  FTransmissorIntf := FTransmissor;
  FChave := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1);
end;

procedure TDFeAcbrSimEventoTests.TearDown;
begin
  FTransmissorIntf := nil;
  FTransmissor := nil;
  FSim.Free;
  FRelogio.Free;
end;

function TDFeAcbrSimEventoTests.DiretorioBase: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

function TDFeAcbrSimEventoTests.DiretorioSchemas: string;
begin
  Result := ExpandFileName(DiretorioBase + '..' + PathDelim + '..' + PathDelim + '..' + PathDelim +
    'vendor' + PathDelim + 'ACBr' + PathDelim + 'Exemplos' + PathDelim + 'ACBrDFe' + PathDelim +
    'Schemas' + PathDelim + 'NFe') + PathDelim;
end;

function TDFeAcbrSimEventoTests.Certificado: TDFeCertificado;
begin
  Result.Identificador := 'teste';
  Result.CnpjCpf := CNPJ_CERT;
  Result.UF := 'RS';
end;

procedure TDFeAcbrSimEventoTests.ExigirAmbiente;
begin
  if not FileExists(DiretorioSchemas + 'envEvento_v1.00.xsd') then
    Assert.Fail('AMBIENTE NAO PREPARADO (o DUnitX nao ignora em execucao): ' + 'XSDs oficiais de NFe nao encontrados em ' + DiretorioSchemas +
      ' (rode tools/init-acbr-submodule.sh)');
  if not InitLibXml2Interface then
    Assert.Fail('AMBIENTE NAO PREPARADO (o DUnitX nao ignora em execucao): ' + 'libxml2 nativa nao encontrada (libxml2.dll x64 no PATH) -- ver docs/simulador-sefaz.md, "Sonda da Fase 4"');
end;

function TDFeAcbrSimEventoTests.NovoClient(const APfx: string): IDFeDistribuicaoClient;
var
  LCred: TDFeCredencialCertificado;
begin
  ExigirAmbiente;
  LCred.ArquivoPFX := DiretorioBase + 'cert-teste' + PathDelim + APfx;
  LCred.Senha := SENHA_CERT;
  LCred.PathSchemas := DiretorioSchemas;
  Result := TDFeDistribuicaoClientACBrNFe.Create(LCred, taHomologacao, FTransmissorIntf);
end;

function TDFeAcbrSimEventoTests.Manifestador(const AClient: IDFeDistribuicaoClient): IDFeManifestador;
begin
  Assert.IsTrue(Supports(AClient, IDFeManifestador, Result), 'o client real deve implementar IDFeManifestador');
end;

function TDFeAcbrSimEventoTests.Comando(const ATipo, AJustificativa: string): TDFeComandoManifestacao;
begin
  Result.Alias := 'teste';
  Result.ChaveAcesso := FChave;
  Result.TipoEvento := ATipo;
  Result.Justificativa := AJustificativa;
end;

procedure TDFeAcbrSimEventoTests.PublicarNFeDoDestinatario;
begin
  FSim.PublicarDocumento(CNPJ_CERT, 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(FChave));
end;

procedure TDFeAcbrSimEventoTests.AssertSemViolacoes;
begin
  Assert.AreEqual(0, FTransmissor.QuantidadeViolacoes, 'violacoes no request do ACBr: ' + FTransmissor.TodasViolacoes);
end;

{ Confere a assinatura do envEvento que o ACBr produziu, com o PROPRIO ACBr
  (libxml2 + OpenSSL): recalcula o digest c14n e verifica o RSA contra o
  X509Certificate embutido. }
function TDFeAcbrSimEventoTests.AssinaturaValida(const AEnvelope: string; out AMsg: string): Boolean;
var
  LACBr: TACBrNFe;
  LXml: string;
  LIni, LFim: Integer;
begin
  LIni := Pos('<envEvento', AEnvelope);
  LFim := Pos('</envEvento>', AEnvelope);
  LXml := '<?xml version="1.0" encoding="UTF-8"?>' + Copy(AEnvelope, LIni, LFim - LIni + Length('</envEvento>'));
  LACBr := TACBrNFe.Create(nil);
  try
    LACBr.Configuracoes.Geral.SSLCryptLib := cryOpenSSL;
    LACBr.Configuracoes.Geral.SSLHttpLib := httpOpenSSL;
    LACBr.Configuracoes.Geral.SSLXmlSignLib := xsLibXml2;
    Result := LACBr.SSL.VerificarAssinatura(LXml, AMsg, 'infEvento');
  finally
    LACBr.Free;
  end;
end;

procedure TDFeAcbrSimEventoTests.Ciencia_Registrada_SaiComTipoEventoDoComando;
var
  LEv: TDFeEventoNormalizado;
begin
  PublicarNFeDoDestinatario;
  LEv := Manifestador(NovoClient).EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA));

  Assert.AreEqual(DFE_TIPO_DOCUMENTO_NFE, LEv.TipoDocumento);
  Assert.IsTrue(LEv.Categoria = dcEvento);
  Assert.AreEqual(DFE_EVENTO_MANIFESTACAO_CIENCIA, LEv.TipoEvento);
  Assert.AreEqual(FChave, LEv.ChaveAcesso);
  Assert.AreEqual(CNPJ_CERT, LEv.CnpjCpfConsultante);
  Assert.AreEqual('RS', LEv.UF);
  Assert.IsTrue(Pos('<procEventoNFe', LEv.XmlPayload) > 0, 'payload e o procEventoNFe montado pelo ACBr');
  Assert.IsTrue(Pos('<nProt>891000000000001</nProt>', LEv.XmlPayload) > 0, 'payload traz o protocolo do simulador');
  Assert.IsTrue(Pos('<retEvento', LEv.XmlPayload) > 0, 'payload traz o retEvento');
  Assert.IsTrue(Pos('<SignatureValue>', LEv.XmlPayload) > 0, 'payload traz a assinatura');
  Assert.AreEqual(1, FSim.EventosRegistrados);
  AssertSemViolacoes;
end;

procedure TDFeAcbrSimEventoTests.OsQuatroTiposDeManifestacao_RegistramSemViolacoes;
var
  LManif: IDFeManifestador;
begin
  PublicarNFeDoDestinatario;
  LManif := Manifestador(NovoClient);
  Assert.AreEqual(DFE_EVENTO_MANIFESTACAO_CONFIRMACAO,
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CONFIRMACAO)).TipoEvento);
  Assert.AreEqual(DFE_EVENTO_MANIFESTACAO_CIENCIA,
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA)).TipoEvento);
  Assert.AreEqual(DFE_EVENTO_MANIFESTACAO_DESCONHECIMENTO,
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_DESCONHECIMENTO,
      'Desconhecemos esta operacao comercial')).TipoEvento);
  Assert.AreEqual(DFE_EVENTO_MANIFESTACAO_OPERACAO_NAO_REALIZADA,
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_OPERACAO_NAO_REALIZADA,
      'Mercadoria nao foi entregue no prazo')).TipoEvento);
  Assert.AreEqual(4, FSim.EventosRegistrados);
  Assert.AreEqual(4, FTransmissor.Requisicoes);
  AssertSemViolacoes;
end;

procedure TDFeAcbrSimEventoTests.Assinatura_ECriptograficamenteValida_ETampering_Invalida;
var
  LMsg, LAdulterado: string;
  LOk: Boolean;
begin
  PublicarNFeDoDestinatario;
  Manifestador(NovoClient).EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA));

  LOk := AssinaturaValida(FTransmissor.UltimoEnvelope, LMsg);
  Assert.IsTrue(LOk, 'assinatura do envEvento deveria verificar: ' + LMsg);

  // controle negativo: mudar um digito da chave dentro do infEvento invalida o digest
  LAdulterado := StringReplace(FTransmissor.UltimoEnvelope, '<nSeqEvento>1</nSeqEvento>',
    '<nSeqEvento>2</nSeqEvento>', []);
  Assert.IsTrue(LAdulterado <> FTransmissor.UltimoEnvelope, 'o envelope adulterado precisa diferir do original');
  Assert.IsFalse(AssinaturaValida(LAdulterado, LMsg), 'assinatura de envelope adulterado NAO pode verificar');
end;

procedure TDFeAcbrSimEventoTests.Duplicidade_ViraManifestacaoRejeitada573;
var
  LManif: IDFeManifestador;
  LEv: TDFeEventoNormalizado;
begin
  PublicarNFeDoDestinatario;
  LManif := Manifestador(NovoClient);
  Assert.AreEqual(DFE_EVENTO_MANIFESTACAO_CIENCIA,
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA)).TipoEvento);

  LEv := LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA));
  Assert.AreEqual(DFE_EVENTO_MANIFESTACAO_REJEITADA, LEv.TipoEvento);
  Assert.IsTrue(Pos('<retEnvEvento', LEv.XmlPayload) > 0, 'payload e o retEnvEvento bruto');
  Assert.IsTrue(Pos('<cStat>573</cStat>', LEv.XmlPayload) > 0, 'payload traz o cStat 573');
  Assert.IsTrue(Pos(FChave, LEv.XmlPayload) > 0, 'payload traz a chave');
  Assert.AreEqual(1, FSim.EventosRegistrados);
end;

procedure TDFeAcbrSimEventoTests.ChaveInexistente_ViraManifestacaoRejeitada494;
var
  LEv: TDFeEventoNormalizado;
begin
  LEv := Manifestador(NovoClient).EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA));
  Assert.AreEqual(DFE_EVENTO_MANIFESTACAO_REJEITADA, LEv.TipoEvento);
  Assert.IsTrue(Pos('<cStat>494</cStat>', LEv.XmlPayload) > 0);
  Assert.AreEqual(0, FSim.EventosRegistrados);
end;

procedure TDFeAcbrSimEventoTests.EventoRejeitadoForcado_ViraManifestacaoRejeitada;
var
  LEv: TDFeEventoNormalizado;
begin
  PublicarNFeDoDestinatario;
  FSim.EnfileirarFalha(fsEventoRejeitado);
  LEv := Manifestador(NovoClient).EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA));
  Assert.AreEqual(DFE_EVENTO_MANIFESTACAO_REJEITADA, LEv.TipoEvento);
  Assert.IsTrue(Pos('<cStat>999</cStat>', LEv.XmlPayload) > 0);
end;

procedure TDFeAcbrSimEventoTests.LoteRejeitado_ViraManifestacaoRejeitadaComRetEnvEvento;
var
  LEv: TDFeEventoNormalizado;
begin
  PublicarNFeDoDestinatario;
  FSim.EnfileirarFalha(fsLoteEventoRejeitado);
  LEv := Manifestador(NovoClient).EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA));
  Assert.AreEqual(DFE_EVENTO_MANIFESTACAO_REJEITADA, LEv.TipoEvento);
  Assert.IsTrue(Pos('<retEnvEvento', LEv.XmlPayload) > 0, 'sem retEvento: o payload e o retEnvEvento do lote');
  Assert.IsTrue(Pos('<cStat>999</cStat>', LEv.XmlPayload) > 0);
  Assert.IsTrue(Pos('<retEvento', LEv.XmlPayload) = 0);
end;

procedure TDFeAcbrSimEventoTests.ServicoIndisponivel108_ViraManifestacaoRejeitada;
var
  LEv: TDFeEventoNormalizado;
begin
  PublicarNFeDoDestinatario;
  FSim.EnfileirarFalha(fsIndisponivelCurtoPrazo);
  LEv := Manifestador(NovoClient).EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA));
  Assert.AreEqual(DFE_EVENTO_MANIFESTACAO_REJEITADA, LEv.TipoEvento);
  Assert.IsTrue(Pos('<cStat>108</cStat>', LEv.XmlPayload) > 0);
  Assert.AreEqual(0, FSim.EventosRegistrados);
end;

procedure TDFeAcbrSimEventoTests.Timeout_ViraComunicacaoFalhou;
var
  LManif: IDFeManifestador;
begin
  PublicarNFeDoDestinatario;
  FSim.EnfileirarFalha(fsTimeout);
  LManif := Manifestador(NovoClient);
  try
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA));
    Assert.Fail('esperava EDFeComunicacaoFalhou');
  except
    on EDFeComunicacaoFalhou do ;
  end;
end;

procedure TDFeAcbrSimEventoTests.ErroHttp500_ViraComunicacaoFalhou;
var
  LManif: IDFeManifestador;
begin
  PublicarNFeDoDestinatario;
  FSim.EnfileirarFalha(fsErroHttp);
  LManif := Manifestador(NovoClient);
  try
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA));
    Assert.Fail('esperava EDFeComunicacaoFalhou');
  except
    on EDFeComunicacaoFalhou do ;
  end;
end;

procedure TDFeAcbrSimEventoTests.CorpoIlegivelComHttp200_ViraRespostaInvalida;
var
  LManif: IDFeManifestador;
begin
  PublicarNFeDoDestinatario;
  FSim.EnfileirarFalha(fsCorpoIlegivel);
  LManif := Manifestador(NovoClient);
  try
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA));
    Assert.Fail('esperava EDFeRespostaInvalida');
  except
    on EDFeRespostaInvalida do ;
  end;
end;

procedure TDFeAcbrSimEventoTests.CertificadoVencido_ViraCertificadoInvalidoSemChamarATransmissao;
var
  LManif: IDFeManifestador;
begin
  PublicarNFeDoDestinatario;
  LManif := Manifestador(NovoClient('vencido.pfx'));
  try
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA));
    Assert.Fail('esperava EDFeCertificadoInvalido');
  except
    on EDFeCertificadoInvalido do ;
  end;
  Assert.AreEqual(0, FTransmissor.Requisicoes);
end;

{ ACHADO (Fase 4): o ACBr REMOVE os acentos do texto livre do evento antes
  de enviar (Geral.RetirarAcentos, padrao True) -- a justificativa 'nao' com
  til chega a SEFAZ como 'nao'. Nao ha erro nem aviso. O XSD da SEFAZ ate'
  aceita Latin-1 em xJust, mas o ACBr optou por nao arriscar encoding. Este
  teste FIXA o comportamento real; se um dia o client passar a preservar os
  acentos (decisao a tomar, ver docs/simulador-sefaz.md), ele deve mudar
  junto. }
procedure TDFeAcbrSimEventoTests.JustificativaAcentuada_AcbrRemoveOsAcentosSilenciosamente;
var
  LJust, LSemAcento: string;
  LEv: TDFeEventoNormalizado;
begin
  LJust := JustificativaComTil;
  LSemAcento := 'Mercadoria nao foi entregue no prazo combinado';
  PublicarNFeDoDestinatario;
  LEv := Manifestador(NovoClient).EnviarEvento(Certificado,
    Comando(DFE_EVENTO_MANIFESTACAO_OPERACAO_NAO_REALIZADA, LJust));
  Assert.AreEqual(DFE_EVENTO_MANIFESTACAO_OPERACAO_NAO_REALIZADA, LEv.TipoEvento);
  Assert.AreEqual(LSemAcento, ExtrairTag(FTransmissor.UltimoEnvelope, 'xJust'), 'xJust sai sem acentos (chegou: ' + HexDe(ExtrairTag(FTransmissor.UltimoEnvelope, 'xJust')) + ')');
  Assert.IsTrue(Pos(LJust, FTransmissor.UltimoEnvelope) = 0, 'o texto original com acento NAO esta no envelope');
  AssertSemViolacoes;
end;

procedure TDFeAcbrSimEventoTests.FimAFim_CienciaAutomatica_PublicaDocumentoEEventoDeCiencia;
var
  LPublicador: TDFePublicadorFake;
  LCursor: TDFeCursorStoreFake;
  LOrq: TDFeOrquestradorTestavel;
  LProcessador: TDFeManifestacaoProcessador;
  LAuto: TDFeAutoManifestador;
  LClient: IDFeDistribuicaoClient;
  LUnidade: TDFeUnidadeTrabalho;
begin
  PublicarNFeDoDestinatario;
  LPublicador := TDFePublicadorFake.Create;
  LCursor := TDFeCursorStoreFake.Create;
  LOrq := TDFeOrquestradorTestavel.Create(LPublicador);
  LProcessador := nil;
  LAuto := nil;
  try
    LOrq.AgoraSimulado := FRelogio.Agora;
    LClient := NovoClient;
    LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderNFe.Create, LClient, Certificado, LCursor);
    LUnidade.ManifestacaoAutomatica := True;
    LOrq.AdicionarUnidade(LUnidade);
    LProcessador := TDFeManifestacaoProcessador.Create(LOrq, LPublicador);
    LAuto := TDFeAutoManifestador.Create(LProcessador);
    LOrq.AoPublicarDocumento := LAuto.AoPublicarDocumento;

    LOrq.ExecutarCiclo;

    // 1 documento (da distribuicao) + 1 evento de ciencia (da manifestacao)
    Assert.AreEqual(2, LPublicador.Quantidade);
    Assert.AreEqual('nfe.documento.rs.' + CNPJ_CERT, LPublicador.RoutingKey(0));
    Assert.AreEqual('nfe.evento.ciencia.rs.' + CNPJ_CERT, LPublicador.RoutingKey(1));
    Assert.IsTrue(Pos('<procEventoNFe', LPublicador.Payload(1)) > 0);
    Assert.AreEqual(1, FSim.EventosRegistrados);
    Assert.AreEqual(0, LOrq.QuantidadeErros);
    AssertSemViolacoes;
  finally
    LAuto.Free;
    LProcessador.Free;
    LOrq.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeAcbrSimEventoTests);

end.
