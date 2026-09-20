unit DFe.SimuladorServidorTests;

{ O simulador visto de fora (DFe.Simulador.Servidor) e o cenario declarativo
  (DFe.Simulador.Cenario). Tudo em processo, sem HTTP: o servidor e' uma funcao
  (metodo, caminho, cabecalhos, corpo) -> (status, corpo). O HTTP de verdade e'
  coberto pela integracao com o executavel (simulador/). }

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils, Classes,
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
  TDFeSimuladorServidorTests = class(TTestCase)
  private
    FSim: TDFeSimuladorSefaz;
    FServidor: TDFeSimuladorServidor;
    function Requisicao(const AUltNSU: string = NSU_ZERO): string;
    function Postar(const ACorpo: string; const ASoapAction: string = SOAP_DIST;
      const ACaminho: string = CAMINHO_DIST): TDFeSimHttpResposta;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Ping_Get_200;
    procedure Ping_Post_405;
    procedure CaminhoDesconhecido_404;
    procedure CaminhoSoapComGet_405;
    procedure Distribuicao_SemDocumentos_137;
    procedure Distribuicao_ComDocumento_138ComDocZip;
    procedure Falha_Timeout_504SemCorpo;
    procedure Falha_ErroHttp_500;
    procedure Falha_ConsumoIndevido_DevolveCStat656;
    procedure SoapActionErrada_RegistraViolacaoMasResponde;
    procedure ContentTypeDaResposta_EspelhaORequest;
    procedure Requisicoes_SaoContadas;
  end;

  TDFeSimuladorCenarioTests = class(TTestCase)
  private
    FSim: TDFeSimuladorSefaz;
    FCaminho: string;
    procedure Escrever(const ALinhas: array of string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Contas_PublicaResNFeEProcNFe;
    procedure PularNSU_CriaSaltoSemDocumentos;
    procedure Falhas_SaoEnfileiradasNaOrdem;
    procedure DuasContas_SaoIndependentes;
    procedure FalhaDesconhecida_Levanta;
    procedure CnpjAusente_Levanta;
    procedure UfInvalida_Levanta;
    procedure ContagemInvalida_Levanta;
    procedure ArquivoInexistente_Levanta;
    procedure FalhaPorNome_NaoDiferenciaMaiusculas;
  end;

implementation

const
  RAIZ_SOAP = '<?xml version="1.0" encoding="UTF-8"?><soap12:Envelope ' +
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
    'xmlns:xsd="http://www.w3.org/2001/XMLSchema" ' +
    'xmlns:soap12="http://www.w3.org/2003/05/soap-envelope"><soap12:Body>';

{ TDFeSimuladorServidorTests }

procedure TDFeSimuladorServidorTests.SetUp;
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
  AssertEquals(200, R.Status);
  AssertEquals('ok', R.Corpo);
  AssertEquals(200, FServidor.Tratar('GET', '/health', '', '', '').Status);
end;

procedure TDFeSimuladorServidorTests.Ping_Post_405;
begin
  AssertEquals(405, FServidor.Tratar('POST', '/ping', '', '', '').Status);
end;

procedure TDFeSimuladorServidorTests.CaminhoDesconhecido_404;
var
  R: TDFeSimHttpResposta;
begin
  R := FServidor.Tratar('POST', '/qualquer/coisa', '', '', '<x/>');
  AssertEquals(404, R.Status);
  AssertTrue('a mensagem diz qual caminho', Pos('/qualquer/coisa', R.Corpo) > 0);
end;

procedure TDFeSimuladorServidorTests.CaminhoSoapComGet_405;
begin
  AssertEquals(405, FServidor.Tratar('GET', CAMINHO_DIST, '', '', '').Status);
end;

procedure TDFeSimuladorServidorTests.Distribuicao_SemDocumentos_137;
var
  R: TDFeSimHttpResposta;
begin
  R := Postar(Requisicao);
  AssertEquals(200, R.Status);
  AssertTrue('cStat 137', Pos('<cStat>137</cStat>', R.Corpo) > 0);
  AssertEquals('', FServidor.Violacoes);
end;

procedure TDFeSimuladorServidorTests.Distribuicao_ComDocumento_138ComDocZip;
var
  R: TDFeSimHttpResposta;
begin
  FSim.PublicarDocumento(CNPJ_TESTE, 'RS', DFE_SIM_SCHEMA_RESNFE,
    XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  R := Postar(Requisicao);
  AssertEquals(200, R.Status);
  AssertTrue('cStat 138', Pos('<cStat>138</cStat>', R.Corpo) > 0);
  AssertTrue('docZip presente', Pos('<docZip', R.Corpo) > 0);
end;

procedure TDFeSimuladorServidorTests.Falha_Timeout_504SemCorpo;
var
  R: TDFeSimHttpResposta;
begin
  FSim.EnfileirarFalha(fsTimeout);
  R := Postar(Requisicao);
  AssertEquals(504, R.Status);
  AssertEquals('', R.Corpo);
end;

procedure TDFeSimuladorServidorTests.Falha_ErroHttp_500;
var
  R: TDFeSimHttpResposta;
begin
  FSim.EnfileirarFalha(fsErroHttp);
  R := Postar(Requisicao);
  AssertEquals(500, R.Status);
end;

procedure TDFeSimuladorServidorTests.Falha_ConsumoIndevido_DevolveCStat656;
var
  R: TDFeSimHttpResposta;
begin
  FSim.EnfileirarFalha(fsConsumoIndevido);
  R := Postar(Requisicao);
  AssertEquals(200, R.Status);
  AssertTrue('cStat 656', Pos('<cStat>656</cStat>', R.Corpo) > 0);
end;

procedure TDFeSimuladorServidorTests.SoapActionErrada_RegistraViolacaoMasResponde;
var
  R: TDFeSimHttpResposta;
begin
  R := Postar(Requisicao, 'http://errada/acao');
  AssertEquals(200, R.Status);
  AssertTrue('violacao registrada', Pos('SoapAction', FServidor.Violacoes) > 0);
end;

procedure TDFeSimuladorServidorTests.ContentTypeDaResposta_EspelhaORequest;
var
  R: TDFeSimHttpResposta;
begin
  R := FServidor.Tratar('POST', CAMINHO_DIST, SOAP_DIST, 'text/xml; charset=utf-8', Requisicao);
  AssertEquals('text/xml; charset=utf-8', R.ContentType);
  R := FServidor.Tratar('POST', CAMINHO_DIST, SOAP_DIST, '', Requisicao(NSU_ZERO));
  AssertEquals(DFE_SIM_CONTENT_TYPE_SOAP, R.ContentType);
end;

procedure TDFeSimuladorServidorTests.Requisicoes_SaoContadas;
begin
  AssertEquals(0, FServidor.Requisicoes);
  Postar(Requisicao);
  Postar(Requisicao);
  AssertEquals(2, FServidor.Requisicoes);
end;

{ TDFeSimuladorCenarioTests }

procedure TDFeSimuladorCenarioTests.SetUp;
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
  AssertEquals(1, LResumo.Contas);
  AssertEquals(3, LResumo.Documentos);
  LResp := FSim.Consultar('11222333000181', 'RS', 0);
  AssertEquals(3, Length(LResp.Lote.Itens));
  AssertEquals(DFE_SIM_SCHEMA_RESNFE, LResp.Lote.Itens[0].Schema);
  AssertEquals(DFE_SIM_SCHEMA_PROCNFE, LResp.Lote.Itens[2].Schema);
end;

procedure TDFeSimuladorCenarioTests.PularNSU_CriaSaltoSemDocumentos;
var
  LResp: TDFeRespostaSimulada;
begin
  Escrever(['[conta:a]', 'Cnpj=11222333000181', 'UF=RS', 'ResNFe=1', 'PularNSU=2']);
  CarregarCenario(FCaminho, FSim);
  LResp := FSim.Consultar('11222333000181', 'RS', 0);
  AssertEquals(1, Length(LResp.Lote.Itens));
  AssertEquals(3, LResp.Lote.MaxNSU);
end;

procedure TDFeSimuladorCenarioTests.Falhas_SaoEnfileiradasNaOrdem;
var
  LResumo: TDFeCenarioResumo;
  LResp: TDFeRespostaSimulada;
begin
  Escrever(['[simulador]', 'Falhas=timeout, erro-http']);
  LResumo := CarregarCenario(FCaminho, FSim);
  AssertEquals(2, LResumo.Falhas);
  LResp := FSim.Consultar('11222333000181', 'RS', 0);
  AssertTrue('1a consulta: timeout', LResp.Tipo = trsTimeout);
  LResp := FSim.Consultar('11222333000181', 'RS', 0);
  AssertTrue('2a consulta: erro http', LResp.Tipo = trsErroHttp);
end;

procedure TDFeSimuladorCenarioTests.DuasContas_SaoIndependentes;
var
  LResumo: TDFeCenarioResumo;
begin
  Escrever(['[conta:a]', 'Cnpj=11222333000181', 'UF=RS', 'ResNFe=2',
            '[conta:b]', 'Cnpj=12345678000199', 'UF=SP', 'ResNFe=5']);
  LResumo := CarregarCenario(FCaminho, FSim);
  AssertEquals(2, LResumo.Contas);
  AssertEquals(7, LResumo.Documentos);
  AssertEquals(2, Length(FSim.Consultar('11222333000181', 'RS', 0).Lote.Itens));
  AssertEquals(5, Length(FSim.Consultar('12345678000199', 'SP', 0).Lote.Itens));
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
  AssertTrue('levanta citando a falha', Pos('explodir', LMsg) > 0);
  AssertTrue('lista as validas', Pos('consumo-indevido', LMsg) > 0);
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
  AssertTrue(LLevantou);
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
  AssertTrue(LLevantou);
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
  AssertTrue(LLevantou);
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
  AssertTrue(LLevantou);
end;

procedure TDFeSimuladorCenarioTests.FalhaPorNome_NaoDiferenciaMaiusculas;
var
  F: TDFeFalhaSimulada;
begin
  AssertTrue(FalhaPorNome('Consumo-Indevido', F));
  AssertTrue(F = fsConsumoIndevido);
  AssertTrue(FalhaPorNome('  TIMEOUT ', F));
  AssertTrue(F = fsTimeout);
  AssertFalse(FalhaPorNome('nada', F));
end;

initialization
  RegisterTest(TDFeSimuladorServidorTests);
  RegisterTest(TDFeSimuladorCenarioTests);

end.
