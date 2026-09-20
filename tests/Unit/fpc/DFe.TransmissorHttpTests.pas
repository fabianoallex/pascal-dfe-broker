unit DFe.TransmissorHttpTests;

{ Camada pura do transporte HTTP do simulador (DFe.Transmissor.Http): URL de
  destino, traducao de falha e texto, com um IDFeHttpPost FALSO -- sem rede.
  O cliente HTTP de verdade (DFe.Transmissor.Http.Cliente) e' coberto pela
  integracao com o simulador. No FPC TextoDoAcbr/TextoParaAcbr sao a
  identidade; a conversao do Delphi mora no espelho (tests/Unit/), que NAO e'
  1:1 com este arquivo. }

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils,
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

  TDFeTransmissorHttpTests = class(TTestCase)
  private
    FFake: TDFeHttpPostFake;
    FPost: IDFeHttpPost;
    function Novo(const ABase: string = 'http://127.0.0.1:9200'): IDFeTransmissor;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure URL_TrocaHostEPortaMantemCaminho;
    procedure URL_MantemQuery;
    procedure URL_BaseComBarraFinal;
    procedure URL_BaseComPrefixo;
    procedure URL_OriginalSemEsquema_EhCaminho;
    procedure URL_OriginalSoHost_ViraRaiz;
    procedure Create_BaseVazia_Levanta;
    procedure Create_BaseSemEsquema_Levanta;
    procedure Create_PostNil_Levanta;
    procedure Transmitir_RepassaURLMimeSoapActionECorpo;
    procedure Transmitir_Resposta200_DevolveTextoEStatus;
    procedure Transmitir_Http500_PassaStatusETextoSemErroInterno;
    procedure Transmitir_ErroDeRede_DevolveErroInternoSemStatus;
    procedure Transmitir_ContaRequisicoes;
    procedure Transmitir_BytesUtf8_PassamIntactosNosDoisSentidos;
  end;

implementation

const
  URL_DIST = 'https://www1.nfe.fazenda.gov.br/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx';

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

procedure TDFeTransmissorHttpTests.SetUp;
begin
  FFake := TDFeHttpPostFake.Create;
  FFake.Resposta.Status := 200;
  FFake.Resposta.Corpo := '<ok/>';
  FPost := FFake; // a interface e' quem mantem o fake vivo (ver CLAUDE.md, gotcha de refcount)
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

procedure TDFeTransmissorHttpTests.URL_TrocaHostEPortaMantemCaminho;
begin
  AssertEquals('http://127.0.0.1:9200/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx',
    MontarURLDestino('http://127.0.0.1:9200', URL_DIST));
end;

procedure TDFeTransmissorHttpTests.URL_MantemQuery;
begin
  AssertEquals('http://sim:1/a/b.asmx?wsdl',
    MontarURLDestino('http://sim:1', 'https://x.gov.br:443/a/b.asmx?wsdl'));
end;

procedure TDFeTransmissorHttpTests.URL_BaseComBarraFinal;
begin
  AssertEquals('http://sim:1/a',
    MontarURLDestino('http://sim:1/', 'https://x/a'));
  AssertEquals('http://sim:1/a',
    MontarURLDestino('http://sim:1///', 'https://x/a'));
end;

procedure TDFeTransmissorHttpTests.URL_BaseComPrefixo;
begin
  AssertEquals('http://sim:1/sefaz/a/b',
    MontarURLDestino('http://sim:1/sefaz', 'https://x/a/b'));
end;

procedure TDFeTransmissorHttpTests.URL_OriginalSemEsquema_EhCaminho;
begin
  AssertEquals('http://sim:1/a/b', MontarURLDestino('http://sim:1', '/a/b'));
  AssertEquals('http://sim:1/a/b', MontarURLDestino('http://sim:1', 'a/b'));
end;

procedure TDFeTransmissorHttpTests.URL_OriginalSoHost_ViraRaiz;
begin
  AssertEquals('http://sim:1/', MontarURLDestino('http://sim:1', 'https://x.gov.br'));
end;

procedure TDFeTransmissorHttpTests.Create_BaseVazia_Levanta;
var
  LLevantou: Boolean;
begin
  LLevantou := False;
  try
    Novo('   ');
  except
    on Exception do
      LLevantou := True;
  end;
  AssertTrue('base vazia deve levantar', LLevantou);
end;

procedure TDFeTransmissorHttpTests.Create_BaseSemEsquema_Levanta;
var
  LLevantou: Boolean;
begin
  LLevantou := False;
  try
    Novo('127.0.0.1:9200');
  except
    on Exception do
      LLevantou := True;
  end;
  AssertTrue('base sem esquema deve levantar', LLevantou);
end;

procedure TDFeTransmissorHttpTests.Create_PostNil_Levanta;
var
  LLevantou: Boolean;
  LNulo: IDFeHttpPost;
  LTransmissor: IDFeTransmissor;
begin
  LLevantou := False;
  LNulo := nil; // variavel local, nao temporario inline (ver CLAUDE.md, gotcha do heaptrc)
  try
    LTransmissor := TDFeTransmissorHttp.Create('http://x:1', LNulo);
  except
    on Exception do
      LLevantou := True;
  end;
  AssertTrue('IDFeHttpPost nil deve levantar', LLevantou);
end;

procedure TDFeTransmissorHttpTests.Transmitir_RepassaURLMimeSoapActionECorpo;
var
  LTransmissor: IDFeTransmissor;
begin
  LTransmissor := Novo;
  LTransmissor.Transmitir('<env/>', URL_DIST, '"urn:nfeDistDFeInteresse"',
    'application/soap+xml; charset=utf-8');
  AssertEquals('http://127.0.0.1:9200/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx', FFake.UltimaURL);
  AssertEquals('application/soap+xml; charset=utf-8', FFake.UltimoMime);
  AssertEquals('"urn:nfeDistDFeInteresse"', FFake.UltimaSoapAction);
  AssertEquals('<env/>', FFake.UltimoCorpo);
end;

procedure TDFeTransmissorHttpTests.Transmitir_Resposta200_DevolveTextoEStatus;
var
  LTransmissor: IDFeTransmissor;
  LResp: TDFeRespostaTransmissao;
begin
  FFake.Resposta.Corpo := '<resp>x</resp>';
  LTransmissor := Novo;
  LResp := LTransmissor.Transmitir('<env/>', URL_DIST, 'a', 'text/xml');
  AssertEquals('<resp>x</resp>', LResp.Texto);
  AssertEquals(200, LResp.HTTPResultCode);
  AssertEquals(0, LResp.InternalErrorCode);
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
  // HTTP 500 e' uma RESPOSTA: quem decide e' o ACBr/client, nao o transporte.
  AssertEquals(500, LResp.HTTPResultCode);
  AssertEquals(0, LResp.InternalErrorCode);
  AssertEquals('<soap:Fault/>', LResp.Texto);
end;

procedure TDFeTransmissorHttpTests.Transmitir_ErroDeRede_DevolveErroInternoSemStatus;
var
  LTransmissor: IDFeTransmissor;
  LResp: TDFeRespostaTransmissao;
begin
  FFake.Resposta.Erro := 'connection refused';
  FFake.Resposta.Status := 200; // lixo que deve ser ignorado
  FFake.Resposta.Corpo := '<lixo/>';
  LTransmissor := Novo;
  LResp := LTransmissor.Transmitir('<env/>', URL_DIST, 'a', 'text/xml');
  AssertEquals(DFE_TRANSMISSAO_ERRO_REDE, LResp.InternalErrorCode);
  AssertEquals(0, LResp.HTTPResultCode);
  AssertEquals('', LResp.Texto);
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
  AssertEquals(2, LTransmissor.Requisicoes);
  AssertEquals(2, FFake.Chamadas);
end;

procedure TDFeTransmissorHttpTests.Transmitir_BytesUtf8_PassamIntactosNosDoisSentidos;
const
  // 'Acao' com cedilha e til em UTF-8, como o FPC guarda a String
  ACAO = 'A'#$C3#$A7#$C3#$A3'o';
var
  LTransmissor: IDFeTransmissor;
  LResp: TDFeRespostaTransmissao;
begin
  FFake.Resposta.Corpo := '<r>' + ACAO + '</r>';
  LTransmissor := Novo;
  LResp := LTransmissor.Transmitir('<e>' + ACAO + '</e>', URL_DIST, 'a', 'm');
  AssertEquals('<e>' + ACAO + '</e>', FFake.UltimoCorpo);
  AssertEquals('<r>' + ACAO + '</r>', LResp.Texto);
end;

initialization
  RegisterTest(TDFeTransmissorHttpTests);

end.
