unit DFe.SimuladorExemploTests;

{ Espelho DELPHI de tests/Unit/fpc/DFe.SimuladorExemploTests.pas (mesmos casos, sintaxe DUnitX). }

{ O EXEMPLO de extensao (simulador/exemplos/limite-consultas): uma regra que o
  core nao tem, exercitada de ponta a ponta pelo servidor -- inclusive com o
  relogio virtual. Prova que o exemplo compila e funciona SEM alterar o core
  (criterio de pronto da Fase C, docs/simulador-standalone.md). }

interface

uses
  DUnitX.TestFramework, System.SysUtils,
  DFe.Simulador,
  DFe.Simulador.Fixtures,
  DFe.Simulador.Relogio,
  DFe.Simulador.Servidor,
  DFe.Simulador.Regras,
  DFe.Simulador.Exemplo.LimiteConsultas;

const
  CNPJ_CONTA = '11222333000181';

type
  [TestFixture]
  TDFeSimuladorExemploTests = class
  private
    FRelogio: TDFeRelogioVirtual;
    FSim: TDFeSimuladorSefaz;
    FServidor: TDFeSimuladorServidor;
    FRegra: TRegraLimiteConsultas;
    function Consultar(const ACnpj: string = CNPJ_CONTA): TDFeSimHttpResposta;
    function Rota(const AMetodo, ACorpo: string): TDFeSimHttpResposta;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure AbaixoDoLimite_OsPedidosPassam;
    [Test] procedure AcimaDoLimite_Responde656SemTocarONucleo;
    [Test] procedure Mensagem_DizOLimiteEAJanela;
    [Test] procedure OutroCnpj_TemContagemPropria;
    [Test] procedure RelogioVirtual_ReabreAJanela;
    [Test] procedure RelogioVirtual_QueVoltaAZero_NaoTrancaParaSempre;
    [Test] procedure Evento_NaoEContado;
    [Test] procedure Rota_Get_MostraOEstado;
    [Test] procedure Rota_Post_AjustaOLimite;
    [Test] procedure Rota_Post_ValoresInvalidos_400;
    [Test] procedure Rota_Metodo_405;
    [Test] procedure Zerar_LimpaContagemELimite;
    [Test] procedure Desligada_NaoLimita;
    [Test] procedure Registrada_PorInitialization;
  end;

implementation

const
  CAMINHO_DIST = '/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx';
  CAMINHO_EVT = '/NFeRecepcaoEvento4/NFeRecepcaoEvento4.asmx';
  SOAP_DIST = 'http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe/nfeDistDFeInteresse';
  ESTA_NO_138 = '<cStat>138</cStat>';
  ESTA_NO_656 = '<cStat>656</cStat>';

function Requisicao(const ACnpj: string): string;
begin
  Result := '<?xml version="1.0" encoding="UTF-8"?><soap12:Envelope ' +
    'xmlns:soap12="http://www.w3.org/2003/05/soap-envelope"><soap12:Body>' +
    '<nfeDistDFeInteresse xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe">' +
    '<nfeDadosMsg><distDFeInt xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.01">' +
    '<tpAmb>2</tpAmb><cUFAutor>43</cUFAutor><CNPJ>' + ACnpj + '</CNPJ>' +
    '<distNSU><ultNSU>000000000000000</ultNSU></distNSU></distDFeInt></nfeDadosMsg>' +
    '</nfeDistDFeInteresse></soap12:Body></soap12:Envelope>';
end;

procedure TDFeSimuladorExemploTests.Setup;
begin
  FRelogio := TDFeRelogioVirtual.Create;
  FSim := TDFeSimuladorSefaz.Create(FRelogio.Agora);
  FServidor := TDFeSimuladorServidor.Create(FSim, FRelogio);
  FRegra := TRegraLimiteConsultas.Create;
  FServidor.AdicionarRegra(FRegra);
  // um documento na conta: com ultNSU 0 o nucleo responde SEMPRE 138 (nunca abre
  // o bloqueio de 1 h), entao um 656 aqui so' pode ser da regra
  FSim.PublicarDocumento(CNPJ_CONTA, 'RS', DFE_SIM_SCHEMA_RESNFE,
    XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
end;

procedure TDFeSimuladorExemploTests.TearDown;
begin
  FServidor.Free; // antes do simulador
  FSim.Free;
  FRelogio.Free;
end;

function TDFeSimuladorExemploTests.Consultar(const ACnpj: string): TDFeSimHttpResposta;
begin
  Result := FServidor.Tratar('POST', CAMINHO_DIST, SOAP_DIST,
    'application/soap+xml; charset=utf-8', Requisicao(ACnpj));
end;

function TDFeSimuladorExemploTests.Rota(const AMetodo, ACorpo: string): TDFeSimHttpResposta;
begin
  Result := FServidor.Tratar(AMetodo, '/ext/limite', '', 'application/json', ACorpo);
end;

procedure TDFeSimuladorExemploTests.AbaixoDoLimite_OsPedidosPassam;
var
  I: Integer;
begin
  for I := 1 to LIMITE_PADRAO do
    Assert.IsTrue(Pos(ESTA_NO_138, Consultar.Corpo) > 0, 'o nucleo respondeu 138');
  Assert.AreEqual(LIMITE_PADRAO, FSim.TotalConsultas);
  Assert.AreEqual(0, FRegra.Rejeitadas);
end;

procedure TDFeSimuladorExemploTests.AcimaDoLimite_Responde656SemTocarONucleo;
var
  I: Integer;
  R: TDFeSimHttpResposta;
begin
  for I := 1 to LIMITE_PADRAO do
    Consultar;
  R := Consultar;
  Assert.AreEqual(200, R.Status);
  Assert.IsTrue(Pos(ESTA_NO_656, R.Corpo) > 0, '656');
  Assert.AreEqual(LIMITE_PADRAO, FSim.TotalConsultas, 'o nucleo nao viu a consulta barrada');
  Assert.AreEqual(1, FRegra.Rejeitadas);
  Assert.AreEqual(LIMITE_PADRAO, FServidor.Requisicoes, 'nem o adaptador SOAP');
  Assert.AreEqual('', FServidor.Violacoes, 'sem violacoes: a resposta da regra e um envelope valido');
end;

procedure TDFeSimuladorExemploTests.Mensagem_DizOLimiteEAJanela;
var
  I: Integer;
begin
  for I := 1 to LIMITE_PADRAO do
    Consultar;
  Assert.IsTrue(Pos('limite de 3 consulta(s) em 600 s', Consultar.Corpo) > 0);
end;

procedure TDFeSimuladorExemploTests.OutroCnpj_TemContagemPropria;
var
  I: Integer;
begin
  for I := 1 to LIMITE_PADRAO do
    Consultar;
  Assert.IsTrue(Pos(ESTA_NO_656, Consultar.Corpo) > 0, 'o primeiro CNPJ esta barrado');
  Assert.IsTrue(Pos('<cStat>137</cStat>', Consultar('99888777000166').Corpo) > 0, 'o outro nao (o nucleo responde 137, conta vazia)');
end;

procedure TDFeSimuladorExemploTests.RelogioVirtual_ReabreAJanela;
var
  I: Integer;
begin
  for I := 1 to LIMITE_PADRAO do
    Consultar;
  Assert.IsTrue(Pos(ESTA_NO_656, Consultar.Corpo) > 0, 'barrada');
  FRelogio.Avancar(JANELA_PADRAO_SEGUNDOS + 1); // sem esperar 10 minutos de verdade
  Assert.IsTrue(Pos(ESTA_NO_138, Consultar.Corpo) > 0, 'liberada');
  Assert.AreEqual(LIMITE_PADRAO + 1, FSim.TotalConsultas);
end;

procedure TDFeSimuladorExemploTests.RelogioVirtual_QueVoltaAZero_NaoTrancaParaSempre;
var
  I: Integer;
begin
  FRelogio.Avancar(3600);
  for I := 1 to LIMITE_PADRAO do
    Consultar;
  FRelogio.Zerar; // as consultas ficaram "no futuro" e devem ser esquecidas
  Assert.IsTrue(Pos(ESTA_NO_138, Consultar.Corpo) > 0, 'liberada');
end;

procedure TDFeSimuladorExemploTests.Evento_NaoEContado;
var
  I: Integer;
begin
  for I := 1 to LIMITE_PADRAO + 2 do
    FServidor.Tratar('POST', CAMINHO_EVT, '', '', '<x/>');
  Assert.AreEqual(0, FRegra.Rejeitadas);
  Assert.IsTrue(Pos(ESTA_NO_138, Consultar.Corpo) > 0, 'as consultas de distribuicao seguem livres');
end;

procedure TDFeSimuladorExemploTests.Rota_Get_MostraOEstado;
var
  R: TDFeSimHttpResposta;
begin
  Consultar;
  Consultar;
  R := Rota('GET', '');
  Assert.AreEqual(200, R.Status);
  Assert.AreEqual('{"maximo":3,"janelaSegundos":600,"rejeitadas":0,' +
    '"contas":[{"cnpj":"11222333000181","consultasNaJanela":2}]}', R.Corpo);
end;

procedure TDFeSimuladorExemploTests.Rota_Post_AjustaOLimite;
var
  R: TDFeSimHttpResposta;
begin
  R := Rota('POST', '{"maximo":1}');
  Assert.AreEqual(200, R.Status);
  Assert.AreEqual(1, FRegra.Maximo);
  Assert.AreEqual(JANELA_PADRAO_SEGUNDOS, FRegra.JanelaSegundos, 'a janela nao mudou');
  Consultar;
  Assert.IsTrue(Pos('<cStat>656</cStat>', Consultar.Corpo) > 0, 'a 2a ja e barrada');
  Rota('POST', '{"janelaSegundos":30}');
  Assert.AreEqual(30, FRegra.JanelaSegundos);
  Assert.AreEqual(1, FRegra.Maximo, 'o maximo ficou');
end;

procedure TDFeSimuladorExemploTests.Rota_Post_ValoresInvalidos_400;
begin
  Assert.AreEqual(400, Rota('POST', '{"maximo":0}').Status);
  Assert.AreEqual(400, Rota('POST', '{"maximo":"tres"}').Status);
  Assert.AreEqual(400, Rota('POST', '{"janelaSegundos":999999}').Status);
  Assert.AreEqual(400, Rota('POST', '{maximo').Status);
  Assert.AreEqual(LIMITE_PADRAO, FRegra.Maximo, 'nada mudou');
end;

procedure TDFeSimuladorExemploTests.Rota_Metodo_405;
begin
  Assert.AreEqual(405, Rota('DELETE', '').Status);
  Assert.AreEqual(404, FServidor.Tratar('GET', '/ext/outra', '', '', '').Status, 'outra rota /ext/ nao e desta regra');
end;

procedure TDFeSimuladorExemploTests.Zerar_LimpaContagemELimite;
var
  I: Integer;
begin
  Rota('POST', '{"maximo":1,"janelaSegundos":10}');
  Consultar;
  Consultar; // barrada
  Assert.AreEqual(1, FRegra.Rejeitadas);
  Assert.AreEqual(200, FServidor.Tratar('POST', '/admin/zerar', '', '', '').Status);
  Assert.AreEqual(0, FRegra.Rejeitadas);
  Assert.AreEqual(LIMITE_PADRAO, FRegra.Maximo);
  Assert.AreEqual(JANELA_PADRAO_SEGUNDOS, FRegra.JanelaSegundos);
  for I := 1 to LIMITE_PADRAO do
    Consultar;
  Assert.AreEqual(LIMITE_PADRAO, FSim.TotalConsultas, 'as 3 passaram: a contagem foi limpa');
end;

procedure TDFeSimuladorExemploTests.Desligada_NaoLimita;
var
  I: Integer;
begin
  FServidor.Tratar('POST', '/admin/regras', '', '', '{"nome":"limite-consultas","ativa":false}');
  for I := 1 to LIMITE_PADRAO * 2 do
    Consultar;
  Assert.AreEqual(LIMITE_PADRAO * 2, FSim.TotalConsultas);
  Assert.AreEqual(0, FRegra.Rejeitadas);
end;

procedure TDFeSimuladorExemploTests.Registrada_PorInitialization;
var
  LClasses: TDFeSimuladorRegraClasseArray;
  I: Integer;
  LAchou: Boolean;
begin
  LClasses := RegrasSimuladorRegistradas;
  LAchou := False;
  for I := 0 to High(LClasses) do
    if LClasses[I] = TRegraLimiteConsultas then
      LAchou := True;
  Assert.IsTrue(LAchou, 'so por a unit no programa, a regra se registra');
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeSimuladorExemploTests);

end.
