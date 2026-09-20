unit DFe.SimuladorServidorTests;

{ Espelho DELPHI de tests/Unit/fpc/DFe.SimuladorServidorTests.pas (mesmos casos,
  sintaxe DUnitX). O simulador visto de fora (DFe.Simulador.Servidor) e o cenario declarativo
  (DFe.Simulador.Cenario). Tudo em processo, sem HTTP: o servidor e' uma funcao
  (metodo, caminho, cabecalhos, corpo) -> (status, corpo). O HTTP de verdade e'
  coberto pela integracao com o executavel (simulador/). }

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes,
  DFe.Types,
  DFe.Simulador,
  DFe.Simulador.Fixtures,
  DFe.Simulador.Servidor,
  DFe.Simulador.Cenario;

const
  CAMINHO_DIST = '/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx';
  SOAP_DIST = 'http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe/nfeDistDFeInteresse';
  CNPJ_TESTE = '11222333000181';
  NSU_ZERO = '000000000000000'; // o ACBr sempre manda o ultNSU com 15 digitos

type
  [TestFixture]
  TDFeSimuladorServidorTests = class
  private
    FSim: TDFeSimuladorSefaz;
    FServidor: TDFeSimuladorServidor;
    function Requisicao(const AUltNSU: string = NSU_ZERO): string;
    function Postar(const ACorpo: string; const ASoapAction: string = SOAP_DIST;
      const ACaminho: string = CAMINHO_DIST): TDFeSimHttpResposta;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure Ping_Get_200;
    [Test] procedure Ping_Post_405;
    [Test] procedure CaminhoDesconhecido_404;
    [Test] procedure CaminhoSoapComGet_405;
    [Test] procedure Distribuicao_SemDocumentos_137;
    [Test] procedure Distribuicao_ComDocumento_138ComDocZip;
    [Test] procedure Falha_Timeout_504SemCorpo;
    [Test] procedure Falha_ErroHttp_500;
    [Test] procedure Falha_ConsumoIndevido_DevolveCStat656;
    [Test] procedure SoapActionErrada_RegistraViolacaoMasResponde;
    [Test] procedure ContentTypeDaResposta_EspelhaORequest;
    [Test] procedure Requisicoes_SaoContadas;
  end;

  [TestFixture]
  TDFeSimuladorCenarioTests = class
  private
    FSim: TDFeSimuladorSefaz;
    FCaminho: string;
    procedure Escrever(const ALinhas: array of string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure Contas_PublicaResNFeEProcNFe;
    [Test] procedure PularNSU_CriaSaltoSemDocumentos;
    [Test] procedure Falhas_SaoEnfileiradasNaOrdem;
    [Test] procedure DuasContas_SaoIndependentes;
    [Test] procedure FalhaDesconhecida_Levanta;
    [Test] procedure CnpjAusente_Levanta;
    [Test] procedure UfInvalida_Levanta;
    [Test] procedure ContagemInvalida_Levanta;
    [Test] procedure ArquivoInexistente_Levanta;
    [Test] procedure FalhaPorNome_NaoDiferenciaMaiusculas;
  end;

implementation

const
  RAIZ_SOAP = '<?xml version="1.0" encoding="UTF-8"?><soap12:Envelope ' +
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
    'xmlns:xsd="http://www.w3.org/2001/XMLSchema" ' +
    'xmlns:soap12="http://www.w3.org/2003/05/soap-envelope"><soap12:Body>';

{ TDFeSimuladorServidorTests }

procedure TDFeSimuladorServidorTests.Setup;
begin
  FSim := TDFeSimuladorSefaz.Create;
  FServidor := TDFeSimuladorServidor.Create(FSim);
end;

procedure TDFeSimuladorServidorTests.TearDown;
begin
  FServidor.Free; // antes do simulador
  FSim.Free;
end;

function TDFeSimuladorServidorTests.Requisicao(const AUltNSU: string): string;
begin
  Result := RAIZ_SOAP +
    '<nfeDistDFeInteresse xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe">' +
    '<nfeDadosMsg><distDFeInt xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.01">' +
    '<tpAmb>2</tpAmb><cUFAutor>43</cUFAutor><CNPJ>' + CNPJ_TESTE + '</CNPJ>' +
    '<distNSU><ultNSU>' + AUltNSU + '</ultNSU></distNSU></distDFeInt></nfeDadosMsg>' +
    '</nfeDistDFeInteresse></soap12:Body></soap12:Envelope>';
end;

function TDFeSimuladorServidorTests.Postar(const ACorpo, ASoapAction,
  ACaminho: string): TDFeSimHttpResposta;
begin
  Result := FServidor.Tratar('POST', ACaminho, ASoapAction,
    'application/soap+xml; charset=utf-8', ACorpo);
end;

procedure TDFeSimuladorServidorTests.Ping_Get_200;
var
  R: TDFeSimHttpResposta;
begin
  R := FServidor.Tratar('GET', '/ping', '', '', '');
  Assert.AreEqual(200, R.Status);
  Assert.AreEqual('ok', R.Corpo);
  Assert.AreEqual(200, FServidor.Tratar('GET', '/health', '', '', '').Status);
end;

procedure TDFeSimuladorServidorTests.Ping_Post_405;
begin
  Assert.AreEqual(405, FServidor.Tratar('POST', '/ping', '', '', '').Status);
end;

procedure TDFeSimuladorServidorTests.CaminhoDesconhecido_404;
var
  R: TDFeSimHttpResposta;
begin
  R := FServidor.Tratar('POST', '/qualquer/coisa', '', '', '<x/>');
  Assert.AreEqual(404, R.Status);
  Assert.IsTrue(Pos('/qualquer/coisa', R.Corpo) > 0, 'a mensagem diz qual caminho');
end;

procedure TDFeSimuladorServidorTests.CaminhoSoapComGet_405;
begin
  Assert.AreEqual(405, FServidor.Tratar('GET', CAMINHO_DIST, '', '', '').Status);
end;

procedure TDFeSimuladorServidorTests.Distribuicao_SemDocumentos_137;
var
  R: TDFeSimHttpResposta;
begin
  R := Postar(Requisicao);
  Assert.AreEqual(200, R.Status);
  Assert.IsTrue(Pos('<cStat>137</cStat>', R.Corpo) > 0, 'cStat 137');
  Assert.AreEqual('', FServidor.Violacoes);
end;

procedure TDFeSimuladorServidorTests.Distribuicao_ComDocumento_138ComDocZip;
var
  R: TDFeSimHttpResposta;
begin
  FSim.PublicarDocumento(CNPJ_TESTE, 'RS', DFE_SIM_SCHEMA_RESNFE,
    XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  R := Postar(Requisicao);
  Assert.AreEqual(200, R.Status);
  Assert.IsTrue(Pos('<cStat>138</cStat>', R.Corpo) > 0, 'cStat 138');
  Assert.IsTrue(Pos('<docZip', R.Corpo) > 0, 'docZip presente');
end;

procedure TDFeSimuladorServidorTests.Falha_Timeout_504SemCorpo;
var
  R: TDFeSimHttpResposta;
begin
  FSim.EnfileirarFalha(fsTimeout);
  R := Postar(Requisicao);
  Assert.AreEqual(504, R.Status);
  Assert.AreEqual('', R.Corpo);
end;

procedure TDFeSimuladorServidorTests.Falha_ErroHttp_500;
var
  R: TDFeSimHttpResposta;
begin
  FSim.EnfileirarFalha(fsErroHttp);
  R := Postar(Requisicao);
  Assert.AreEqual(500, R.Status);
end;

procedure TDFeSimuladorServidorTests.Falha_ConsumoIndevido_DevolveCStat656;
var
  R: TDFeSimHttpResposta;
begin
  FSim.EnfileirarFalha(fsConsumoIndevido);
  R := Postar(Requisicao);
  Assert.AreEqual(200, R.Status);
  Assert.IsTrue(Pos('<cStat>656</cStat>', R.Corpo) > 0, 'cStat 656');
end;

procedure TDFeSimuladorServidorTests.SoapActionErrada_RegistraViolacaoMasResponde;
var
  R: TDFeSimHttpResposta;
begin
  R := Postar(Requisicao, 'http://errada/acao');
  Assert.AreEqual(200, R.Status);
  Assert.IsTrue(Pos('SoapAction', FServidor.Violacoes) > 0, 'violacao registrada');
end;

procedure TDFeSimuladorServidorTests.ContentTypeDaResposta_EspelhaORequest;
var
  R: TDFeSimHttpResposta;
begin
  R := FServidor.Tratar('POST', CAMINHO_DIST, SOAP_DIST, 'text/xml; charset=utf-8', Requisicao);
  Assert.AreEqual('text/xml; charset=utf-8', R.ContentType);
  R := FServidor.Tratar('POST', CAMINHO_DIST, SOAP_DIST, '', Requisicao(NSU_ZERO));
  Assert.AreEqual(DFE_SIM_CONTENT_TYPE_SOAP, R.ContentType);
end;

procedure TDFeSimuladorServidorTests.Requisicoes_SaoContadas;
begin
  Assert.AreEqual(0, FServidor.Requisicoes);
  Postar(Requisicao);
  Postar(Requisicao);
  Assert.AreEqual(2, FServidor.Requisicoes);
end;

{ TDFeSimuladorCenarioTests }

procedure TDFeSimuladorCenarioTests.Setup;
begin
  FSim := TDFeSimuladorSefaz.Create;
  FCaminho := ExtractFilePath(ParamStr(0)) + 'dfe_cenario_teste.ini';
  if FileExists(FCaminho) then
    DeleteFile(FCaminho);
end;

procedure TDFeSimuladorCenarioTests.TearDown;
begin
  FSim.Free;
  if FileExists(FCaminho) then
    DeleteFile(FCaminho);
end;

procedure TDFeSimuladorCenarioTests.Escrever(const ALinhas: array of string);
var
  LConteudo: TStringList;
  I: Integer;
begin
  LConteudo := TStringList.Create;
  try
    for I := 0 to High(ALinhas) do
      LConteudo.Add(ALinhas[I]);
    LConteudo.SaveToFile(FCaminho);
  finally
    LConteudo.Free;
  end;
end;

procedure TDFeSimuladorCenarioTests.Contas_PublicaResNFeEProcNFe;
var
  LResumo: TDFeCenarioResumo;
  LResp: TDFeRespostaSimulada;
begin
  Escrever(['[conta:a]', 'Cnpj=11222333000181', 'UF=rs', 'ResNFe=2', 'ProcNFe=1']);
  LResumo := CarregarCenario(FCaminho, FSim);
  Assert.AreEqual(1, LResumo.Contas);
  Assert.AreEqual(3, LResumo.Documentos);
  LResp := FSim.Consultar('11222333000181', 'RS', 0);
  Assert.AreEqual(3, Integer(Length(LResp.Lote.Itens)));
  Assert.AreEqual(DFE_SIM_SCHEMA_RESNFE, LResp.Lote.Itens[0].Schema);
  Assert.AreEqual(DFE_SIM_SCHEMA_PROCNFE, LResp.Lote.Itens[2].Schema);
end;

procedure TDFeSimuladorCenarioTests.PularNSU_CriaSaltoSemDocumentos;
var
  LResp: TDFeRespostaSimulada;
begin
  Escrever(['[conta:a]', 'Cnpj=11222333000181', 'UF=RS', 'ResNFe=1', 'PularNSU=2']);
  CarregarCenario(FCaminho, FSim);
  LResp := FSim.Consultar('11222333000181', 'RS', 0);
  Assert.AreEqual(1, Integer(Length(LResp.Lote.Itens)));
  Assert.AreEqual(3, LResp.Lote.MaxNSU);
end;

procedure TDFeSimuladorCenarioTests.Falhas_SaoEnfileiradasNaOrdem;
var
  LResumo: TDFeCenarioResumo;
  LResp: TDFeRespostaSimulada;
begin
  Escrever(['[simulador]', 'Falhas=timeout, erro-http']);
  LResumo := CarregarCenario(FCaminho, FSim);
  Assert.AreEqual(2, LResumo.Falhas);
  LResp := FSim.Consultar('11222333000181', 'RS', 0);
  Assert.IsTrue(LResp.Tipo = trsTimeout, '1a consulta: timeout');
  LResp := FSim.Consultar('11222333000181', 'RS', 0);
  Assert.IsTrue(LResp.Tipo = trsErroHttp, '2a consulta: erro http');
end;

procedure TDFeSimuladorCenarioTests.DuasContas_SaoIndependentes;
var
  LResumo: TDFeCenarioResumo;
begin
  Escrever(['[conta:a]', 'Cnpj=11222333000181', 'UF=RS', 'ResNFe=2',
            '[conta:b]', 'Cnpj=12345678000199', 'UF=SP', 'ResNFe=5']);
  LResumo := CarregarCenario(FCaminho, FSim);
  Assert.AreEqual(2, LResumo.Contas);
  Assert.AreEqual(7, LResumo.Documentos);
  Assert.AreEqual(2, Integer(Length(FSim.Consultar('11222333000181', 'RS', 0).Lote.Itens)));
  Assert.AreEqual(5, Integer(Length(FSim.Consultar('12345678000199', 'SP', 0).Lote.Itens)));
end;

procedure TDFeSimuladorCenarioTests.FalhaDesconhecida_Levanta;
var
  LMsg: string;
begin
  Escrever(['[simulador]', 'Falhas=timeout,explodir']);
  LMsg := '';
  try
    CarregarCenario(FCaminho, FSim);
  except
    on E: Exception do
      LMsg := E.Message;
  end;
  Assert.IsTrue(Pos('explodir', LMsg) > 0, 'levanta citando a falha');
  Assert.IsTrue(Pos('consumo-indevido', LMsg) > 0, 'lista as validas');
end;

procedure TDFeSimuladorCenarioTests.CnpjAusente_Levanta;
var
  LLevantou: Boolean;
begin
  Escrever(['[conta:a]', 'UF=RS', 'ResNFe=1']);
  LLevantou := False;
  try
    CarregarCenario(FCaminho, FSim);
  except
    on Exception do
      LLevantou := True;
  end;
  Assert.IsTrue(LLevantou);
end;

procedure TDFeSimuladorCenarioTests.UfInvalida_Levanta;
var
  LLevantou: Boolean;
begin
  Escrever(['[conta:a]', 'Cnpj=11222333000181', 'UF=RSX', 'ResNFe=1']);
  LLevantou := False;
  try
    CarregarCenario(FCaminho, FSim);
  except
    on Exception do
      LLevantou := True;
  end;
  Assert.IsTrue(LLevantou);
end;

procedure TDFeSimuladorCenarioTests.ContagemInvalida_Levanta;
var
  LLevantou: Boolean;
begin
  Escrever(['[conta:a]', 'Cnpj=11222333000181', 'UF=RS', 'ResNFe=abc']);
  LLevantou := False;
  try
    CarregarCenario(FCaminho, FSim);
  except
    on Exception do
      LLevantou := True;
  end;
  Assert.IsTrue(LLevantou);
end;

procedure TDFeSimuladorCenarioTests.ArquivoInexistente_Levanta;
var
  LLevantou: Boolean;
begin
  LLevantou := False;
  try
    CarregarCenario(FCaminho, FSim); // nao foi escrito
  except
    on Exception do
      LLevantou := True;
  end;
  Assert.IsTrue(LLevantou);
end;

procedure TDFeSimuladorCenarioTests.FalhaPorNome_NaoDiferenciaMaiusculas;
var
  F: TDFeFalhaSimulada;
begin
  Assert.IsTrue(FalhaPorNome('Consumo-Indevido', F));
  Assert.IsTrue(F = fsConsumoIndevido);
  Assert.IsTrue(FalhaPorNome('  TIMEOUT ', F));
  Assert.IsTrue(F = fsTimeout);
  Assert.IsFalse(FalhaPorNome('nada', F));
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeSimuladorServidorTests);
  TDUnitX.RegisterTestFixture(TDFeSimuladorCenarioTests);

end.
