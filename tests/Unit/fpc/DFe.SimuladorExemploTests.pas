unit DFe.SimuladorExemploTests;

{ O EXEMPLO de extensao (simulador/exemplos/limite-consultas): uma regra que o
  core nao tem, exercitada de ponta a ponta pelo servidor -- inclusive com o
  relogio virtual. Prova que o exemplo compila e funciona SEM alterar o core
  (criterio de pronto da Fase C, docs/simulador-standalone.md). }

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils,
  DFe.Simulador,
  DFe.Simulador.Fixtures,
  DFe.Simulador.Relogio,
  DFe.Simulador.Servidor,
  DFe.Simulador.Regras,
  DFe.Simulador.Exemplo.LimiteConsultas;

const
  CNPJ_CONTA = '11222333000181';

type
  TDFeSimuladorExemploTests = class(TTestCase)
  private
    FRelogio: TDFeRelogioVirtual;
    FSim: TDFeSimuladorSefaz;
    FServidor: TDFeSimuladorServidor;
    FRegra: TRegraLimiteConsultas;
    function Consultar(const ACnpj: string = CNPJ_CONTA): TDFeSimHttpResposta;
    function Rota(const AMetodo, ACorpo: string): TDFeSimHttpResposta;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure AbaixoDoLimite_OsPedidosPassam;
    procedure AcimaDoLimite_Responde656SemTocarONucleo;
    procedure Mensagem_DizOLimiteEAJanela;
    procedure OutroCnpj_TemContagemPropria;
    procedure RelogioVirtual_ReabreAJanela;
    procedure RelogioVirtual_QueVoltaAZero_NaoTrancaParaSempre;
    procedure Evento_NaoEContado;
    procedure Rota_Get_MostraOEstado;
    procedure Rota_Post_AjustaOLimite;
    procedure Rota_Post_ValoresInvalidos_400;
    procedure Rota_Metodo_405;
    procedure Zerar_LimpaContagemELimite;
    procedure Desligada_NaoLimita;
    procedure Registrada_PorInitialization;
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

procedure TDFeSimuladorExemploTests.SetUp;
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
    AssertTrue('o nucleo respondeu 138', Pos(ESTA_NO_138, Consultar.Corpo) > 0);
  AssertEquals(LIMITE_PADRAO, FSim.TotalConsultas);
  AssertEquals(0, FRegra.Rejeitadas);
end;

procedure TDFeSimuladorExemploTests.AcimaDoLimite_Responde656SemTocarONucleo;
var
  I: Integer;
  R: TDFeSimHttpResposta;
begin
  for I := 1 to LIMITE_PADRAO do
    Consultar;
  R := Consultar;
  AssertEquals(200, R.Status);
  AssertTrue('656', Pos(ESTA_NO_656, R.Corpo) > 0);
  AssertEquals('o nucleo nao viu a consulta barrada', LIMITE_PADRAO, FSim.TotalConsultas);
  AssertEquals(1, FRegra.Rejeitadas);
  AssertEquals('nem o adaptador SOAP', LIMITE_PADRAO, FServidor.Requisicoes);
  AssertEquals('sem violacoes: a resposta da regra e um envelope valido', '', FServidor.Violacoes);
end;

procedure TDFeSimuladorExemploTests.Mensagem_DizOLimiteEAJanela;
var
  I: Integer;
begin
  for I := 1 to LIMITE_PADRAO do
    Consultar;
  AssertTrue(Pos('limite de 3 consulta(s) em 600 s', Consultar.Corpo) > 0);
end;

procedure TDFeSimuladorExemploTests.OutroCnpj_TemContagemPropria;
var
  I: Integer;
begin
  for I := 1 to LIMITE_PADRAO do
    Consultar;
  AssertTrue('o primeiro CNPJ esta barrado', Pos(ESTA_NO_656, Consultar.Corpo) > 0);
  AssertTrue('o outro nao (o nucleo responde 137, conta vazia)',
    Pos('<cStat>137</cStat>', Consultar('99888777000166').Corpo) > 0);
end;

procedure TDFeSimuladorExemploTests.RelogioVirtual_ReabreAJanela;
var
  I: Integer;
begin
  for I := 1 to LIMITE_PADRAO do
    Consultar;
  AssertTrue('barrada', Pos(ESTA_NO_656, Consultar.Corpo) > 0);
  FRelogio.Avancar(JANELA_PADRAO_SEGUNDOS + 1); // sem esperar 10 minutos de verdade
  AssertTrue('liberada', Pos(ESTA_NO_138, Consultar.Corpo) > 0);
  AssertEquals(LIMITE_PADRAO + 1, FSim.TotalConsultas);
end;

procedure TDFeSimuladorExemploTests.RelogioVirtual_QueVoltaAZero_NaoTrancaParaSempre;
var
  I: Integer;
begin
  FRelogio.Avancar(3600);
  for I := 1 to LIMITE_PADRAO do
    Consultar;
  FRelogio.Zerar; // as consultas ficaram "no futuro" e devem ser esquecidas
  AssertTrue('liberada', Pos(ESTA_NO_138, Consultar.Corpo) > 0);
end;

procedure TDFeSimuladorExemploTests.Evento_NaoEContado;
var
  I: Integer;
begin
  for I := 1 to LIMITE_PADRAO + 2 do
    FServidor.Tratar('POST', CAMINHO_EVT, '', '', '<x/>');
  AssertEquals(0, FRegra.Rejeitadas);
  AssertTrue('as consultas de distribuicao seguem livres', Pos(ESTA_NO_138, Consultar.Corpo) > 0);
end;

procedure TDFeSimuladorExemploTests.Rota_Get_MostraOEstado;
var
  R: TDFeSimHttpResposta;
begin
  Consultar;
  Consultar;
  R := Rota('GET', '');
  AssertEquals(200, R.Status);
  AssertEquals('{"maximo":3,"janelaSegundos":600,"rejeitadas":0,' +
    '"contas":[{"cnpj":"11222333000181","consultasNaJanela":2}]}', R.Corpo);
end;

procedure TDFeSimuladorExemploTests.Rota_Post_AjustaOLimite;
var
  R: TDFeSimHttpResposta;
begin
  R := Rota('POST', '{"maximo":1}');
  AssertEquals(200, R.Status);
  AssertEquals(1, FRegra.Maximo);
  AssertEquals('a janela nao mudou', JANELA_PADRAO_SEGUNDOS, FRegra.JanelaSegundos);
  Consultar;
  AssertTrue('a 2a ja e barrada', Pos('<cStat>656</cStat>', Consultar.Corpo) > 0);
  Rota('POST', '{"janelaSegundos":30}');
  AssertEquals(30, FRegra.JanelaSegundos);
  AssertEquals('o maximo ficou', 1, FRegra.Maximo);
end;

procedure TDFeSimuladorExemploTests.Rota_Post_ValoresInvalidos_400;
begin
  AssertEquals(400, Rota('POST', '{"maximo":0}').Status);
  AssertEquals(400, Rota('POST', '{"maximo":"tres"}').Status);
  AssertEquals(400, Rota('POST', '{"janelaSegundos":999999}').Status);
  AssertEquals(400, Rota('POST', '{maximo').Status);
  AssertEquals('nada mudou', LIMITE_PADRAO, FRegra.Maximo);
end;

procedure TDFeSimuladorExemploTests.Rota_Metodo_405;
begin
  AssertEquals(405, Rota('DELETE', '').Status);
  AssertEquals('outra rota /ext/ nao e desta regra', 404,
    FServidor.Tratar('GET', '/ext/outra', '', '', '').Status);
end;

procedure TDFeSimuladorExemploTests.Zerar_LimpaContagemELimite;
var
  I: Integer;
begin
  Rota('POST', '{"maximo":1,"janelaSegundos":10}');
  Consultar;
  Consultar; // barrada
  AssertEquals(1, FRegra.Rejeitadas);
  AssertEquals(200, FServidor.Tratar('POST', '/admin/zerar', '', '', '').Status);
  AssertEquals(0, FRegra.Rejeitadas);
  AssertEquals(LIMITE_PADRAO, FRegra.Maximo);
  AssertEquals(JANELA_PADRAO_SEGUNDOS, FRegra.JanelaSegundos);
  for I := 1 to LIMITE_PADRAO do
    Consultar;
  AssertEquals('as 3 passaram: a contagem foi limpa', LIMITE_PADRAO, FSim.TotalConsultas);
end;

procedure TDFeSimuladorExemploTests.Desligada_NaoLimita;
var
  I: Integer;
begin
  FServidor.Tratar('POST', '/admin/regras', '', '', '{"nome":"limite-consultas","ativa":false}');
  for I := 1 to LIMITE_PADRAO * 2 do
    Consultar;
  AssertEquals(LIMITE_PADRAO * 2, FSim.TotalConsultas);
  AssertEquals(0, FRegra.Rejeitadas);
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
  AssertTrue('so por a unit no programa, a regra se registra', LAchou);
end;

initialization
  RegisterTest(TDFeSimuladorExemploTests);

end.
