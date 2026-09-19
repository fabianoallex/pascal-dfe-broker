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

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils,
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
  DFe.Ambiente,
  DFe.Ambiente.ACBr,
  DFe.AcbrSimPastas,
  DFe.TestDoubles;

type
  TDFeAcbrSimEventoTests = class(TTestCase)
  private
    FRelogio: TDFeRelogioFake;
    FSim: TDFeSimuladorSefaz;
    FTransmissor: TDFeSimuladorTransmissor;
    FTransmissorIntf: IDFeTransmissor;
    FPastas: TPastasTemporarias;
    FChave: string;
    function DiretorioBase: string;
    function DiretorioSchemas: string;
    function Certificado: TDFeCertificado;
    procedure ExigirAmbiente;
    function NovoClient(const APfx: string = 'valido.pfx'; const APathSchemas: string = ''): IDFeDistribuicaoClient;
    function Manifestador(const AClient: IDFeDistribuicaoClient): IDFeManifestador;
    function Comando(const ATipo: string; const AJustificativa: string = ''): TDFeComandoManifestacao;
    procedure PublicarNFeDoDestinatario;
    procedure AssertSemViolacoes;
    function AssinaturaValida(const AEnvelope: string; out AMsg: string): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Ciencia_Registrada_SaiComTipoEventoDoComando;
    procedure OsQuatroTiposDeManifestacao_RegistramSemViolacoes;
    procedure Assinatura_ECriptograficamenteValida_ETampering_Invalida;
    procedure Duplicidade_ViraManifestacaoRejeitada573;
    procedure ChaveInexistente_RegistraNaoVinculado136;
    procedure AutorDivergenteDoDestinatario_ViraManifestacaoRejeitada575;
    procedure CienciaAposConfirmacao_ViraManifestacaoRejeitada655;
    procedure EventoRejeitadoForcado_ViraManifestacaoRejeitada;
    procedure LoteRejeitado_ViraManifestacaoRejeitadaComRetEnvEvento;
    procedure ServicoIndisponivel108_ViraManifestacaoRejeitada;
    procedure Timeout_ViraComunicacaoFalhou;
    procedure ErroHttp500_ViraComunicacaoFalhou;
    procedure CorpoIlegivelComHttp200_ViraRespostaInvalida;
    procedure CertificadoVencido_ViraCertificadoInvalidoSemChamarATransmissao;
    procedure JustificativaAcentuada_AcbrRemoveOsAcentosSilenciosamente;
    procedure FimAFim_CienciaAutomatica_PublicaDocumentoEEventoDeCiencia;
    procedure VerificacaoDeAmbiente_DestaMaquina_Manifestacao_EstaCompleta;
    procedure PastaMinimaDeXsds_BastaParaEnviarEvento;
    procedure SemXsdsDeEvento_EnviarEvento_LevantaAmbienteIndisponivel;
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

procedure TDFeAcbrSimEventoTests.SetUp;
begin
  FRelogio := TDFeRelogioFake.Create;
  FRelogio.Agora := EncodeDate(2026, 9, 18) + EncodeTime(10, 0, 0, 0);
  FSim := TDFeSimuladorSefaz.Create(FRelogio.ObterAgora);
  FTransmissor := TDFeSimuladorTransmissor.Create(FSim);
  FTransmissorIntf := FTransmissor;
  FPastas := TPastasTemporarias.Create;
  FChave := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1);
end;

procedure TDFeAcbrSimEventoTests.TearDown;
begin
  FTransmissorIntf := nil;
  FTransmissor := nil;
  FSim.Free;
  FRelogio.Free;
  FPastas.Free;
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
    Ignore('XSDs oficiais de NFe nao encontrados em ' + DiretorioSchemas +
      ' (rode tools/init-acbr-submodule.sh)');
  if not InitLibXml2Interface then
    Ignore('libxml2 nativa nao encontrada (libxml2.dll x64 no PATH) -- ver docs/simulador-sefaz.md, "Sonda da Fase 4"');
end;

function TDFeAcbrSimEventoTests.NovoClient(const APfx, APathSchemas: string): IDFeDistribuicaoClient;
var
  LCred: TDFeCredencialCertificado;
begin
  ExigirAmbiente;
  LCred.ArquivoPFX := DiretorioBase + 'cert-teste' + PathDelim + APfx;
  LCred.Senha := SENHA_CERT;
  if APathSchemas <> '' then
    LCred.PathSchemas := APathSchemas
  else
    LCred.PathSchemas := DiretorioSchemas;
  Result := TDFeDistribuicaoClientACBrNFe.Create(LCred, taHomologacao, FTransmissorIntf);
end;

function TDFeAcbrSimEventoTests.Manifestador(const AClient: IDFeDistribuicaoClient): IDFeManifestador;
begin
  AssertTrue('o client real deve implementar IDFeManifestador', Supports(AClient, IDFeManifestador, Result));
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
  AssertEquals('violacoes no request do ACBr: ' + FTransmissor.TodasViolacoes,
    0, FTransmissor.QuantidadeViolacoes);
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

  AssertEquals(DFE_TIPO_DOCUMENTO_NFE, LEv.TipoDocumento);
  AssertTrue(LEv.Categoria = dcEvento);
  AssertEquals(DFE_EVENTO_MANIFESTACAO_CIENCIA, LEv.TipoEvento);
  AssertEquals(FChave, LEv.ChaveAcesso);
  AssertEquals(CNPJ_CERT, LEv.CnpjCpfConsultante);
  AssertEquals('RS', LEv.UF);
  AssertTrue('payload e o procEventoNFe montado pelo ACBr', Pos('<procEventoNFe', LEv.XmlPayload) > 0);
  AssertTrue('payload traz o protocolo do simulador', Pos('<nProt>891000000000001</nProt>', LEv.XmlPayload) > 0);
  AssertTrue('payload traz o retEvento', Pos('<retEvento', LEv.XmlPayload) > 0);
  AssertTrue('payload traz a assinatura', Pos('<SignatureValue>', LEv.XmlPayload) > 0);
  AssertEquals(1, FSim.EventosRegistrados);
  AssertSemViolacoes;
end;

{ Ordem: a ciencia vem PRIMEIRO -- depois de uma manifestacao final a NT
  rejeita a ciencia (H06, 655; ver CienciaAposConfirmacao_...). Desconhecimento
  e' enviado COM justificativa de proposito: o client deve DESCARTA-LA (a NT,
  HP20, so' admite xJust em Operacao nao Realizada) e o adaptador acusaria
  violacao se ela fosse no envelope. }
procedure TDFeAcbrSimEventoTests.OsQuatroTiposDeManifestacao_RegistramSemViolacoes;
var
  LManif: IDFeManifestador;
begin
  PublicarNFeDoDestinatario;
  LManif := Manifestador(NovoClient);
  AssertEquals(DFE_EVENTO_MANIFESTACAO_CIENCIA,
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA)).TipoEvento);
  AssertEquals(DFE_EVENTO_MANIFESTACAO_CONFIRMACAO,
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CONFIRMACAO)).TipoEvento);
  AssertEquals(DFE_EVENTO_MANIFESTACAO_DESCONHECIMENTO,
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_DESCONHECIMENTO,
      'Desconhecemos esta operacao comercial')).TipoEvento);
  AssertTrue('desconhecimento nao leva xJust', Pos('<xJust>', FTransmissor.UltimoEnvelope) = 0);
  AssertEquals(DFE_EVENTO_MANIFESTACAO_OPERACAO_NAO_REALIZADA,
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_OPERACAO_NAO_REALIZADA,
      'Mercadoria nao foi entregue no prazo')).TipoEvento);
  AssertTrue('operacao nao realizada leva xJust', Pos('<xJust>', FTransmissor.UltimoEnvelope) > 0);
  AssertEquals(4, FSim.EventosRegistrados);
  AssertEquals(4, FTransmissor.Requisicoes);
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
  AssertTrue('assinatura do envEvento deveria verificar: ' + LMsg, LOk);

  // controle negativo: mudar um digito da chave dentro do infEvento invalida o digest
  LAdulterado := StringReplace(FTransmissor.UltimoEnvelope, '<nSeqEvento>1</nSeqEvento>',
    '<nSeqEvento>2</nSeqEvento>', []);
  AssertTrue('o envelope adulterado precisa diferir do original', LAdulterado <> FTransmissor.UltimoEnvelope);
  AssertFalse('assinatura de envelope adulterado NAO pode verificar', AssinaturaValida(LAdulterado, LMsg));
end;

procedure TDFeAcbrSimEventoTests.Duplicidade_ViraManifestacaoRejeitada573;
var
  LManif: IDFeManifestador;
  LEv: TDFeEventoNormalizado;
begin
  PublicarNFeDoDestinatario;
  LManif := Manifestador(NovoClient);
  AssertEquals(DFE_EVENTO_MANIFESTACAO_CIENCIA,
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA)).TipoEvento);

  LEv := LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA));
  AssertEquals(DFE_EVENTO_MANIFESTACAO_REJEITADA, LEv.TipoEvento);
  AssertTrue('payload e o retEnvEvento bruto', Pos('<retEnvEvento', LEv.XmlPayload) > 0);
  AssertTrue('payload traz o cStat 573', Pos('<cStat>573</cStat>', LEv.XmlPayload) > 0);
  AssertTrue('payload traz a chave', Pos(FChave, LEv.XmlPayload) > 0);
  AssertEquals(1, FSim.EventosRegistrados);
end;

{ NT 2012/002, 4.9.9: evento para NF-e que a SEFAZ ainda nao conhece e'
  REGISTRADO (136, "registrado, mas nao vinculado"), nao rejeitado -- entao sai
  com o TipoEvento do comando e o procEventoNFe. (A versao anterior do
  simulador rejeitava com 494, sem base na NT.) }
procedure TDFeAcbrSimEventoTests.ChaveInexistente_RegistraNaoVinculado136;
var
  LEv: TDFeEventoNormalizado;
begin
  LEv := Manifestador(NovoClient).EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA));
  AssertEquals(DFE_EVENTO_MANIFESTACAO_CIENCIA, LEv.TipoEvento);
  AssertTrue('payload traz o cStat 136', Pos('<cStat>136</cStat>', LEv.XmlPayload) > 0);
  AssertTrue('payload e o procEventoNFe', Pos('<procEventoNFe', LEv.XmlPayload) > 0);
  AssertEquals(1, FSim.EventosRegistrados);
  AssertSemViolacoes;
end;

{ G09: a NF-e existe mas e' de OUTRO destinatario -> 575. }
procedure TDFeAcbrSimEventoTests.AutorDivergenteDoDestinatario_ViraManifestacaoRejeitada575;
var
  LEv: TDFeEventoNormalizado;
begin
  FSim.PublicarDocumento('11444777000161', 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(FChave));
  LEv := Manifestador(NovoClient).EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA));
  AssertEquals(DFE_EVENTO_MANIFESTACAO_REJEITADA, LEv.TipoEvento);
  AssertTrue(Pos('<cStat>575</cStat>', LEv.XmlPayload) > 0);
  AssertEquals(0, FSim.EventosRegistrados);
end;

{ H06: ciencia depois da manifestacao final do destinatario -> 655. }
procedure TDFeAcbrSimEventoTests.CienciaAposConfirmacao_ViraManifestacaoRejeitada655;
var
  LManif: IDFeManifestador;
  LEv: TDFeEventoNormalizado;
begin
  PublicarNFeDoDestinatario;
  LManif := Manifestador(NovoClient);
  AssertEquals(DFE_EVENTO_MANIFESTACAO_CONFIRMACAO,
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CONFIRMACAO)).TipoEvento);
  LEv := LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA));
  AssertEquals(DFE_EVENTO_MANIFESTACAO_REJEITADA, LEv.TipoEvento);
  AssertTrue(Pos('<cStat>655</cStat>', LEv.XmlPayload) > 0);
  AssertEquals(1, FSim.EventosRegistrados);
end;

procedure TDFeAcbrSimEventoTests.EventoRejeitadoForcado_ViraManifestacaoRejeitada;
var
  LEv: TDFeEventoNormalizado;
begin
  PublicarNFeDoDestinatario;
  FSim.EnfileirarFalha(fsEventoRejeitado);
  LEv := Manifestador(NovoClient).EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA));
  AssertEquals(DFE_EVENTO_MANIFESTACAO_REJEITADA, LEv.TipoEvento);
  AssertTrue(Pos('<cStat>999</cStat>', LEv.XmlPayload) > 0);
end;

procedure TDFeAcbrSimEventoTests.LoteRejeitado_ViraManifestacaoRejeitadaComRetEnvEvento;
var
  LEv: TDFeEventoNormalizado;
begin
  PublicarNFeDoDestinatario;
  FSim.EnfileirarFalha(fsLoteEventoRejeitado);
  LEv := Manifestador(NovoClient).EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA));
  AssertEquals(DFE_EVENTO_MANIFESTACAO_REJEITADA, LEv.TipoEvento);
  AssertTrue('sem retEvento: o payload e o retEnvEvento do lote', Pos('<retEnvEvento', LEv.XmlPayload) > 0);
  AssertTrue(Pos('<cStat>999</cStat>', LEv.XmlPayload) > 0);
  AssertTrue(Pos('<retEvento', LEv.XmlPayload) = 0);
end;

procedure TDFeAcbrSimEventoTests.ServicoIndisponivel108_ViraManifestacaoRejeitada;
var
  LEv: TDFeEventoNormalizado;
begin
  PublicarNFeDoDestinatario;
  FSim.EnfileirarFalha(fsIndisponivelCurtoPrazo);
  LEv := Manifestador(NovoClient).EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA));
  AssertEquals(DFE_EVENTO_MANIFESTACAO_REJEITADA, LEv.TipoEvento);
  AssertTrue(Pos('<cStat>108</cStat>', LEv.XmlPayload) > 0);
  AssertEquals(0, FSim.EventosRegistrados);
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
    Fail('esperava EDFeComunicacaoFalhou');
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
    Fail('esperava EDFeComunicacaoFalhou');
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
    Fail('esperava EDFeRespostaInvalida');
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
    Fail('esperava EDFeCertificadoInvalido');
  except
    on EDFeCertificadoInvalido do ;
  end;
  AssertEquals(0, FTransmissor.Requisicoes);
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
  AssertEquals(DFE_EVENTO_MANIFESTACAO_OPERACAO_NAO_REALIZADA, LEv.TipoEvento);
  AssertEquals('xJust sai sem acentos (chegou: ' + HexDe(ExtrairTag(FTransmissor.UltimoEnvelope, 'xJust')) + ')',
    LSemAcento, ExtrairTag(FTransmissor.UltimoEnvelope, 'xJust'));
  AssertTrue('o texto original com acento NAO esta no envelope',
    Pos(LJust, FTransmissor.UltimoEnvelope) = 0);
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
    AssertEquals(2, LPublicador.Quantidade);
    AssertEquals('nfe.documento.rs.' + CNPJ_CERT, LPublicador.RoutingKey(0));
    AssertEquals('nfe.evento.ciencia.rs.' + CNPJ_CERT, LPublicador.RoutingKey(1));
    AssertTrue(Pos('<procEventoNFe', LPublicador.Payload(1)) > 0);
    AssertEquals(1, FSim.EventosRegistrados);
    AssertEquals(0, LOrq.QuantidadeErros);
    AssertSemViolacoes;
  finally
    LAuto.Free;
    LProcessador.Free;
    LOrq.Free;
  end;
end;

procedure TDFeAcbrSimEventoTests.VerificacaoDeAmbiente_DestaMaquina_Manifestacao_EstaCompleta;
var
  R: TDFeRelatorioAmbiente;
begin
  ExigirAmbiente;
  R := VerificarAmbienteACBr(DiretorioSchemas, [uaDistribuicao, uaManifestacao]);
  AssertTrue('ambiente da manifestacao deveria estar completo:' + sLineBreak + FormatarRelatorio(R),
    AmbienteCompleto(R));
end;

{ Prova que DFE_XSDS_MANIFESTACAO (DFe.Ambiente.ACBr) e' SUFICIENTE: numa pasta
  so' com esses arquivos o EnviarEvento dos QUATRO tipos monta, assina, valida
  contra o XSD e registra (cada tipo valida um e2102xx diferente). Se o ACBr
  passar a exigir outro, este teste quebra -- foi ele que mostrou que a
  primeira versao da lista (5 arquivos) estava incompleta. }
procedure TDFeAcbrSimEventoTests.PastaMinimaDeXsds_BastaParaEnviarEvento;
var
  LPasta: string;
  I: Integer;
  LManif: IDFeManifestador;
begin
  ExigirAmbiente;
  LPasta := FPastas.Nova;
  for I := Low(DFE_XSDS_MANIFESTACAO) to High(DFE_XSDS_MANIFESTACAO) do
    CopiarArquivo(DiretorioSchemas + DFE_XSDS_MANIFESTACAO[I], LPasta + DFE_XSDS_MANIFESTACAO[I]);

  PublicarNFeDoDestinatario;
  LManif := Manifestador(NovoClient('valido.pfx', LPasta));
  AssertEquals(DFE_EVENTO_MANIFESTACAO_CIENCIA,
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA)).TipoEvento);
  AssertEquals(DFE_EVENTO_MANIFESTACAO_CONFIRMACAO,
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CONFIRMACAO)).TipoEvento);
  AssertEquals(DFE_EVENTO_MANIFESTACAO_DESCONHECIMENTO,
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_DESCONHECIMENTO)).TipoEvento);
  AssertEquals(DFE_EVENTO_MANIFESTACAO_OPERACAO_NAO_REALIZADA,
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_OPERACAO_NAO_REALIZADA,
      'Mercadoria nao foi entregue no prazo')).TipoEvento);
  AssertEquals(4, FSim.EventosRegistrados);
  AssertSemViolacoes;
end;

procedure TDFeAcbrSimEventoTests.SemXsdsDeEvento_EnviarEvento_LevantaAmbienteIndisponivel;
var
  LManif: IDFeManifestador;
  LPasta: string;
begin
  ExigirAmbiente;
  LPasta := FPastas.Nova;
  CriarArquivoVazio(LPasta + 'distDFeInt_v1.01.xsd'); // basta para a distribuicao, nao para o evento
  PublicarNFeDoDestinatario;
  LManif := Manifestador(NovoClient('valido.pfx', LPasta));
  try
    LManif.EnviarEvento(Certificado, Comando(DFE_EVENTO_MANIFESTACAO_CIENCIA));
    Fail('esperava EDFeAmbienteIndisponivel');
  except
    on E: EDFeAmbienteIndisponivel do
      AssertTrue('diz o que falta: ' + E.Message, Pos('faltam: envEvento_v1.00.xsd', E.Message) > 0);
  end;
  AssertEquals(0, FTransmissor.Requisicoes);
end;

initialization
  RegisterTest(TDFeAcbrSimEventoTests);

end.
