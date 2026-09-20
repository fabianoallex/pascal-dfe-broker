unit DFe.TransmissorHttpTests;

{ Espelho DELPHI de tests/Unit/fpc/DFe.TransmissorHttpTests.pas -- NAO e' 1:1:
  no Delphi TextoDoAcbr/TextoParaAcbr fazem conversao de verdade (o envelope
  chega do ACBr como bytes UTF-8 vistos como caracteres ANSI; o
  IDFeHttpPost recebe e devolve o texto NATIVO). O teste de acentos abaixo
  monta o mojibake do MESMO jeito que o ACBr o produz (ver
  DFe.XmlTextoTests.ComoOAcbrEntrega). }

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  DFe.Transmissor,
  DFe.Transmissor.Http;

type
  TDFeHttpPostFake = class(TInterfacedObject, IDFeHttpPost)
  public
    Chamadas: Integer;
    UltimaURL, UltimoMime, UltimaSoapAction, UltimoCorpo: string;
    Resposta: TDFeHttpResposta;
    function Postar(const AURL, AMimeType, ASoapAction,
      ACorpo: string): TDFeHttpResposta;
  end;

  [TestFixture]
  TDFeTransmissorHttpTests = class
  private
    FFake: TDFeHttpPostFake;
    FPost: IDFeHttpPost;
    function Novo(const ABase: string = 'http://127.0.0.1:9200'): IDFeTransmissor;
    function ComoOAcbrEntrega(const ATexto: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure URL_TrocaHostEPortaMantemCaminho;
    [Test] procedure URL_MantemQuery;
    [Test] procedure URL_BaseComBarraFinal;
    [Test] procedure URL_BaseComPrefixo;
    [Test] procedure URL_OriginalSemEsquema_EhCaminho;
    [Test] procedure URL_OriginalSoHost_ViraRaiz;
    [Test] procedure Create_BaseVazia_Levanta;
    [Test] procedure Create_BaseSemEsquema_Levanta;
    [Test] procedure Create_PostNil_Levanta;
    [Test] procedure Transmitir_RepassaURLMimeSoapActionECorpo;
    [Test] procedure Transmitir_Resposta200_DevolveTextoEStatus;
    [Test] procedure Transmitir_Http500_PassaStatusETextoSemErroInterno;
    [Test] procedure Transmitir_ErroDeRede_DevolveErroInternoSemStatus;
    [Test] procedure Transmitir_ContaRequisicoes;
    [Test] procedure Transmitir_Acentos_EnvelopeDoAcbrViraTextoNativoENaVolta;
  end;

implementation

const
  URL_DIST = 'https://www1.nfe.fazenda.gov.br/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx';
  TEXTO_ACENTUADO = 'JOS' + #$00C9 + ' A' + #$00C7 + 'A' + #$00CD + ' LTDA';

function TDFeHttpPostFake.Postar(const AURL, AMimeType, ASoapAction,
  ACorpo: string): TDFeHttpResposta;
begin
  Inc(Chamadas);
  UltimaURL := AURL;
  UltimoMime := AMimeType;
  UltimaSoapAction := ASoapAction;
  UltimoCorpo := ACorpo;
  Result := Resposta;
end;

procedure TDFeTransmissorHttpTests.Setup;
begin
  FFake := TDFeHttpPostFake.Create;
  FFake.Resposta.Status := 200;
  FFake.Resposta.Corpo := '<ok/>';
  FPost := FFake; // a interface e' quem mantem o fake vivo
end;

procedure TDFeTransmissorHttpTests.TearDown;
begin
  FPost := nil;
  FFake := nil;
end;

function TDFeTransmissorHttpTests.Novo(const ABase: string): IDFeTransmissor;
begin
  Result := TDFeTransmissorHttp.Create(ABase, FPost);
end;

function TDFeTransmissorHttpTests.ComoOAcbrEntrega(const ATexto: string): string;
var
  LBytes: TBytes;
  LAnsi: AnsiString;
begin
  LBytes := TEncoding.UTF8.GetBytes(ATexto);
  SetString(LAnsi, PAnsiChar(@LBytes[0]), Length(LBytes)); // bytes crus, pagina ANSI
  Result := string(LAnsi);
end;

procedure TDFeTransmissorHttpTests.URL_TrocaHostEPortaMantemCaminho;
begin
  Assert.AreEqual('http://127.0.0.1:9200/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx',
    MontarURLDestino('http://127.0.0.1:9200', URL_DIST));
end;

procedure TDFeTransmissorHttpTests.URL_MantemQuery;
begin
  Assert.AreEqual('http://sim:1/a/b.asmx?wsdl',
    MontarURLDestino('http://sim:1', 'https://x.gov.br:443/a/b.asmx?wsdl'));
end;

procedure TDFeTransmissorHttpTests.URL_BaseComBarraFinal;
begin
  Assert.AreEqual('http://sim:1/a', MontarURLDestino('http://sim:1/', 'https://x/a'));
  Assert.AreEqual('http://sim:1/a', MontarURLDestino('http://sim:1///', 'https://x/a'));
end;

procedure TDFeTransmissorHttpTests.URL_BaseComPrefixo;
begin
  Assert.AreEqual('http://sim:1/sefaz/a/b',
    MontarURLDestino('http://sim:1/sefaz', 'https://x/a/b'));
end;

procedure TDFeTransmissorHttpTests.URL_OriginalSemEsquema_EhCaminho;
begin
  Assert.AreEqual('http://sim:1/a/b', MontarURLDestino('http://sim:1', '/a/b'));
  Assert.AreEqual('http://sim:1/a/b', MontarURLDestino('http://sim:1', 'a/b'));
end;

procedure TDFeTransmissorHttpTests.URL_OriginalSoHost_ViraRaiz;
begin
  Assert.AreEqual('http://sim:1/', MontarURLDestino('http://sim:1', 'https://x.gov.br'));
end;

procedure TDFeTransmissorHttpTests.Create_BaseVazia_Levanta;
begin
  Assert.WillRaise(
    procedure
    begin
      Novo('   ');
    end, Exception);
end;

procedure TDFeTransmissorHttpTests.Create_BaseSemEsquema_Levanta;
begin
  Assert.WillRaise(
    procedure
    begin
      Novo('127.0.0.1:9200');
    end, Exception);
end;

procedure TDFeTransmissorHttpTests.Create_PostNil_Levanta;
var
  LNulo: IDFeHttpPost;
begin
  LNulo := nil;
  Assert.WillRaise(
    procedure
    begin
      TDFeTransmissorHttp.Create('http://x:1', LNulo);
    end, Exception);
end;

procedure TDFeTransmissorHttpTests.Transmitir_RepassaURLMimeSoapActionECorpo;
var
  LTransmissor: IDFeTransmissor;
begin
  LTransmissor := Novo;
  LTransmissor.Transmitir('<env/>', URL_DIST, '"urn:nfeDistDFeInteresse"',
    'application/soap+xml; charset=utf-8');
  Assert.AreEqual('http://127.0.0.1:9200/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx', FFake.UltimaURL);
  Assert.AreEqual('application/soap+xml; charset=utf-8', FFake.UltimoMime);
  Assert.AreEqual('"urn:nfeDistDFeInteresse"', FFake.UltimaSoapAction);
  Assert.AreEqual('<env/>', FFake.UltimoCorpo);
end;

procedure TDFeTransmissorHttpTests.Transmitir_Resposta200_DevolveTextoEStatus;
var
  LTransmissor: IDFeTransmissor;
  LResp: TDFeRespostaTransmissao;
begin
  FFake.Resposta.Corpo := '<resp>x</resp>';
  LTransmissor := Novo;
  LResp := LTransmissor.Transmitir('<env/>', URL_DIST, 'a', 'text/xml');
  Assert.AreEqual('<resp>x</resp>', LResp.Texto);
  Assert.AreEqual(200, LResp.HTTPResultCode);
  Assert.AreEqual(0, LResp.InternalErrorCode);
end;

procedure TDFeTransmissorHttpTests.Transmitir_Http500_PassaStatusETextoSemErroInterno;
var
  LTransmissor: IDFeTransmissor;
  LResp: TDFeRespostaTransmissao;
begin
  FFake.Resposta.Status := 500;
  FFake.Resposta.Corpo := '<soap:Fault/>';
  LTransmissor := Novo;
  LResp := LTransmissor.Transmitir('<env/>', URL_DIST, 'a', 'text/xml');
  Assert.AreEqual(500, LResp.HTTPResultCode);
  Assert.AreEqual(0, LResp.InternalErrorCode);
  Assert.AreEqual('<soap:Fault/>', LResp.Texto);
end;

procedure TDFeTransmissorHttpTests.Transmitir_ErroDeRede_DevolveErroInternoSemStatus;
var
  LTransmissor: IDFeTransmissor;
  LResp: TDFeRespostaTransmissao;
begin
  FFake.Resposta.Erro := 'connection refused';
  FFake.Resposta.Status := 200;
  FFake.Resposta.Corpo := '<lixo/>';
  LTransmissor := Novo;
  LResp := LTransmissor.Transmitir('<env/>', URL_DIST, 'a', 'text/xml');
  Assert.AreEqual(DFE_TRANSMISSAO_ERRO_REDE, LResp.InternalErrorCode);
  Assert.AreEqual(0, LResp.HTTPResultCode);
  Assert.AreEqual('', LResp.Texto);
end;

procedure TDFeTransmissorHttpTests.Transmitir_ContaRequisicoes;
var
  LTransmissor: TDFeTransmissorHttp;
  LIntf: IDFeTransmissor;
begin
  LTransmissor := TDFeTransmissorHttp.Create('http://127.0.0.1:9200', FPost);
  LIntf := LTransmissor; // a interface assume a posse
  LIntf.Transmitir('<a/>', URL_DIST, 's', 'm');
  LIntf.Transmitir('<b/>', URL_DIST, 's', 'm');
  Assert.AreEqual(2, LTransmissor.Requisicoes);
  Assert.AreEqual(2, FFake.Chamadas);
end;

procedure TDFeTransmissorHttpTests.Transmitir_Acentos_EnvelopeDoAcbrViraTextoNativoENaVolta;
var
  LTransmissor: IDFeTransmissor;
  LResp: TDFeRespostaTransmissao;
begin
  // resposta do simulador chega como texto nativo; o ACBr a espera na convencao dele
  FFake.Resposta.Corpo := '<r>' + TEXTO_ACENTUADO + '</r>';
  LTransmissor := Novo;
  LResp := LTransmissor.Transmitir('<e>' + ComoOAcbrEntrega(TEXTO_ACENTUADO) + '</e>',
    URL_DIST, 'a', 'm');
  // o IDFeHttpPost recebe o texto de VERDADE (a rede leva UTF-8 correto)...
  Assert.AreEqual('<e>' + TEXTO_ACENTUADO + '</e>', FFake.UltimoCorpo);
  // ...e a resposta volta na convencao do ACBr
  Assert.AreEqual('<r>' + ComoOAcbrEntrega(TEXTO_ACENTUADO) + '</r>', LResp.Texto);
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeTransmissorHttpTests);

end.
