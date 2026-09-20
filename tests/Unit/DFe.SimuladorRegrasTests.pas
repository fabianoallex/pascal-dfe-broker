unit DFe.SimuladorRegrasTests;

{ Espelho DELPHI de tests/Unit/fpc/DFe.SimuladorRegrasTests.pas (mesmos casos, sintaxe DUnitX). }

{ Extensao do simulador em Pascal (DFe.Simulador.Regras + os ganchos de
  DFe.Simulador.Servidor): curto-circuito, alteracao da resposta, rotas /ext/,
  liga/desliga por /admin/regras, AoZerar e o registro por initialization. Tudo em
  processo, sem HTTP. }

interface

uses
  DUnitX.TestFramework, System.SysUtils,
  DFe.Simulador,
  DFe.Simulador.Servidor,
  DFe.Simulador.Regras;

type
  { Regra de teste que grava o que os ganchos recebem e se comporta como mandado. }
  TRegraGravadora = class(TDFeSimuladorRegra)
  public
    ChamadasAntes: Integer;
    ChamadasDepois: Integer;
    ChamadasRota: Integer;
    ChamadasZerar: Integer;
    UltimaAntes: TDFeSimRequisicao;
    UltimaRota: TDFeSimRequisicao;
    ResponderAntes: Boolean;     // curto-circuito com HTTP 418
    StatusDepois: Integer;       // <> 0 = troca o status da resposta do nucleo
    CaminhoDaRota: string;       // rota /ext/ que esta regra atende
    LevantarNoAntes: Boolean;
    class function Nome: string; override;
    class function Descricao: string; override;
    function AntesDeAtender(const ARequisicao: TDFeSimRequisicao;
      var AResposta: TDFeSimHttpResposta): Boolean; override;
    procedure DepoisDeAtender(const ARequisicao: TDFeSimRequisicao;
      var AResposta: TDFeSimHttpResposta); override;
    function TratarRota(const ARequisicao: TDFeSimRequisicao;
      var AResposta: TDFeSimHttpResposta): Boolean; override;
    procedure AoZerar; override;
    function SimuladorVisto: TDFeSimuladorSefaz;
  end;

  TRegraGravadoraB = class(TRegraGravadora)
  public
    class function Nome: string; override;
  end;

  TRegraNascidaDesligada = class(TDFeSimuladorRegra)
  public
    class function Nome: string; override;
    class function AtivaPorPadrao: Boolean; override;
  end;

  TRegraSemNome = class(TDFeSimuladorRegra)
  public
    class function Nome: string; override;
  end;

  [TestFixture]
  TDFeSimuladorRegrasTests = class
  private
    FSim: TDFeSimuladorSefaz;
    FServidor: TDFeSimuladorServidor;
    function NovaRegra: TRegraGravadora;
    function NovaRegraB: TRegraGravadoraB;
    function PostarDistribuicao: TDFeSimHttpResposta;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure SemRegras_TudoComoAntes;
    [Test] procedure Regra_QueNaoResponde_DeixaONucleoAtender;
    [Test] procedure Regra_RecebeARequisicaoCompleta;
    [Test] procedure Regra_RecebeOServicoDeEvento;
    [Test] procedure Regra_QueResponde_CurtoCircuitaONucleo;
    [Test] procedure Regra_QueResponde_DispensaAsSeguintes;
    [Test] procedure DepoisDeAtender_PodeAlterarARespostaDoNucleo;
    [Test] procedure Regra_Desligada_NaoEConsultada;
    [Test] procedure Regra_NascidaDesligada_ComecaDesligada;
    [Test] procedure Ganchos_NaoVeemPingNemAdmin;
    [Test] procedure Rota_Extensao_ChegaNaRegra;
    [Test] procedure Rota_Extensao_SemRegraQueAtenda_404;
    [Test] procedure Rota_Extensao_RegraDesligada_404;
    [Test] procedure Rota_Extensao_EscolheAPrimeiraQueResponde;
    [Test] procedure Zerar_AvisaAsRegras;
    [Test] procedure Zerar_ComFalha_NaoAvisa;
    [Test] procedure AdminRegras_Lista;
    [Test] procedure AdminRegras_LigaEDesliga;
    [Test] procedure AdminRegras_Desconhecida_404;
    [Test] procedure AdminRegras_Invalido_400;
    [Test] procedure AdminRegras_MetodoErrado_405;
    [Test] procedure AdicionarRegra_NomeRepetido_LevantaENaoAdota;
    [Test] procedure Excecao_NoGancho_Propaga;
    [Test] procedure Registro_AdicionaUmaInstanciaPorServidor;
    [Test] procedure Registro_NomeRepetido_Levanta;
    [Test] procedure Registro_NomeVazio_Levanta;
  end;

implementation

const
  CAMINHO_DIST = '/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx';
  CAMINHO_EVT = '/NFeRecepcaoEvento4/NFeRecepcaoEvento4.asmx';
  SOAP_DIST = 'http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe/nfeDistDFeInteresse';
  CNPJ_TESTE = '11222333000181';
  REQUISICAO = '<?xml version="1.0" encoding="UTF-8"?><soap12:Envelope ' +
    'xmlns:soap12="http://www.w3.org/2003/05/soap-envelope"><soap12:Body>' +
    '<nfeDistDFeInteresse xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe">' +
    '<nfeDadosMsg><distDFeInt xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.01">' +
    '<tpAmb>2</tpAmb><cUFAutor>43</cUFAutor><CNPJ>' + CNPJ_TESTE + '</CNPJ>' +
    '<distNSU><ultNSU>000000000000000</ultNSU></distNSU></distDFeInt></nfeDadosMsg>' +
    '</nfeDistDFeInteresse></soap12:Body></soap12:Envelope>';

{ TRegraGravadora }

class function TRegraGravadora.Nome: string;
begin
  Result := 'gravadora';
end;

class function TRegraGravadora.Descricao: string;
begin
  Result := 'grava as chamadas';
end;

function TRegraGravadora.AntesDeAtender(const ARequisicao: TDFeSimRequisicao;
  var AResposta: TDFeSimHttpResposta): Boolean;
begin
  Inc(ChamadasAntes);
  UltimaAntes := ARequisicao;
  if LevantarNoAntes then
    raise Exception.Create('defeito da regra');
  Result := ResponderAntes;
  if Result then
  begin
    AResposta.Status := 418;
    AResposta.ContentType := 'text/plain';
    AResposta.Corpo := 'respondido pela regra ' + Nome;
  end;
end;

procedure TRegraGravadora.DepoisDeAtender(const ARequisicao: TDFeSimRequisicao;
  var AResposta: TDFeSimHttpResposta);
begin
  Inc(ChamadasDepois);
  if StatusDepois <> 0 then
    AResposta.Status := StatusDepois;
end;

function TRegraGravadora.TratarRota(const ARequisicao: TDFeSimRequisicao;
  var AResposta: TDFeSimHttpResposta): Boolean;
begin
  Inc(ChamadasRota);
  UltimaRota := ARequisicao;
  Result := (CaminhoDaRota <> '') and SameText(ARequisicao.Caminho, CaminhoDaRota);
  if Result then
  begin
    AResposta.Status := 200;
    AResposta.ContentType := 'text/plain';
    AResposta.Corpo := 'rota da ' + Nome;
  end;
end;

procedure TRegraGravadora.AoZerar;
begin
  Inc(ChamadasZerar);
end;

function TRegraGravadora.SimuladorVisto: TDFeSimuladorSefaz;
begin
  Result := Simulador;
end;

class function TRegraGravadoraB.Nome: string;
begin
  Result := 'gravadora-b';
end;

class function TRegraNascidaDesligada.Nome: string;
begin
  Result := 'nascida-desligada';
end;

class function TRegraNascidaDesligada.AtivaPorPadrao: Boolean;
begin
  Result := False;
end;

class function TRegraSemNome.Nome: string;
begin
  Result := '';
end;

{ TDFeSimuladorRegrasTests }

procedure TDFeSimuladorRegrasTests.Setup;
begin
  FSim := TDFeSimuladorSefaz.Create;
  FServidor := TDFeSimuladorServidor.Create(FSim);
end;

procedure TDFeSimuladorRegrasTests.TearDown;
begin
  FServidor.Free; // libera as regras; antes do simulador
  FSim.Free;
end;

function TDFeSimuladorRegrasTests.NovaRegra: TRegraGravadora;
begin
  Result := TRegraGravadora.Create;
  FServidor.AdicionarRegra(Result); // o servidor passa a ser o dono
end;

function TDFeSimuladorRegrasTests.NovaRegraB: TRegraGravadoraB;
begin
  Result := TRegraGravadoraB.Create;
  FServidor.AdicionarRegra(Result);
end;

function TDFeSimuladorRegrasTests.PostarDistribuicao: TDFeSimHttpResposta;
begin
  Result := FServidor.Tratar('POST', CAMINHO_DIST, SOAP_DIST,
    'application/soap+xml; charset=utf-8', REQUISICAO);
end;

procedure TDFeSimuladorRegrasTests.SemRegras_TudoComoAntes;
var
  R: TDFeSimHttpResposta;
begin
  Assert.AreEqual(0, FServidor.Regras);
  R := PostarDistribuicao;
  Assert.AreEqual(200, R.Status);
  Assert.IsTrue(Pos('<cStat>137</cStat>', R.Corpo) > 0, '137');
  Assert.AreEqual(404, FServidor.Tratar('GET', '/ext/qualquer', '', '', '').Status);
end;

procedure TDFeSimuladorRegrasTests.Regra_QueNaoResponde_DeixaONucleoAtender;
var
  LRegra: TRegraGravadora;
  R: TDFeSimHttpResposta;
begin
  LRegra := NovaRegra;
  R := PostarDistribuicao;
  Assert.AreEqual(200, R.Status);
  Assert.IsTrue(Pos('<cStat>137</cStat>', R.Corpo) > 0, 'o nucleo respondeu 137');
  Assert.AreEqual(1, FSim.TotalConsultas);
  Assert.AreEqual(1, LRegra.ChamadasAntes);
  Assert.AreEqual(1, LRegra.ChamadasDepois);
end;

procedure TDFeSimuladorRegrasTests.Regra_RecebeARequisicaoCompleta;
var
  LRegra: TRegraGravadora;
begin
  LRegra := NovaRegra;
  PostarDistribuicao;
  Assert.IsTrue(LRegra.UltimaAntes.Servico = ssDistribuicao, 'servico distribuicao');
  Assert.AreEqual('POST', LRegra.UltimaAntes.Metodo);
  Assert.AreEqual(CAMINHO_DIST, LRegra.UltimaAntes.Caminho);
  Assert.AreEqual(SOAP_DIST, LRegra.UltimaAntes.SoapAction);
  Assert.AreEqual('application/soap+xml; charset=utf-8', LRegra.UltimaAntes.ContentType);
  Assert.AreEqual(REQUISICAO, LRegra.UltimaAntes.Corpo);
  Assert.IsTrue(Abs(LRegra.UltimaAntes.Agora - FSim.AgoraSimulado) < 1, 'Agora e o relogio do simulador');
  Assert.IsTrue(LRegra.SimuladorVisto = FSim, 'a regra enxerga o simulador do servidor');
end;

procedure TDFeSimuladorRegrasTests.Regra_RecebeOServicoDeEvento;
var
  LRegra: TRegraGravadora;
begin
  LRegra := NovaRegra;
  LRegra.ResponderAntes := True; // nao deixa o nucleo tentar interpretar um evento falso
  FServidor.Tratar('POST', CAMINHO_EVT, '', '', '<x/>');
  Assert.IsTrue(LRegra.UltimaAntes.Servico = ssEvento, 'servico evento');
end;

procedure TDFeSimuladorRegrasTests.Regra_QueResponde_CurtoCircuitaONucleo;
var
  LRegra: TRegraGravadora;
  R: TDFeSimHttpResposta;
begin
  LRegra := NovaRegra;
  LRegra.ResponderAntes := True;
  R := PostarDistribuicao;
  Assert.AreEqual(418, R.Status);
  Assert.AreEqual('respondido pela regra gravadora', R.Corpo);
  Assert.AreEqual(0, FSim.TotalConsultas, 'o nucleo nao foi tocado');
  Assert.AreEqual(0, FServidor.Requisicoes, 'o adaptador SOAP nem viu o request');
  Assert.AreEqual(0, LRegra.ChamadasDepois, 'DepoisDeAtender nao roda quando a regra respondeu');
end;

procedure TDFeSimuladorRegrasTests.Regra_QueResponde_DispensaAsSeguintes;
var
  LA: TRegraGravadora;
  LB: TRegraGravadoraB;
begin
  LA := NovaRegra;
  LB := NovaRegraB;
  LA.ResponderAntes := True;
  PostarDistribuicao;
  Assert.AreEqual(1, LA.ChamadasAntes);
  Assert.AreEqual(0, LB.ChamadasAntes, 'a seguinte nem foi consultada');
end;

procedure TDFeSimuladorRegrasTests.DepoisDeAtender_PodeAlterarARespostaDoNucleo;
var
  LA: TRegraGravadora;
  LB: TRegraGravadoraB;
  R: TDFeSimHttpResposta;
begin
  LA := NovaRegra;
  LB := NovaRegraB;
  LA.StatusDepois := 503;
  R := PostarDistribuicao;
  Assert.AreEqual(503, R.Status);
  Assert.IsTrue(Pos('<cStat>137</cStat>', R.Corpo) > 0, 'o corpo continua sendo o do nucleo');
  Assert.AreEqual(1, LB.ChamadasDepois, 'todas as regras rodam o Depois');
  Assert.AreEqual(1, FSim.TotalConsultas);
end;

procedure TDFeSimuladorRegrasTests.Regra_Desligada_NaoEConsultada;
var
  LRegra: TRegraGravadora;
begin
  LRegra := NovaRegra;
  LRegra.Ativa := False;
  LRegra.ResponderAntes := True;
  LRegra.CaminhoDaRota := '/ext/x';
  Assert.AreEqual(200, PostarDistribuicao.Status);
  Assert.AreEqual(404, FServidor.Tratar('GET', '/ext/x', '', '', '').Status);
  Assert.AreEqual(0, LRegra.ChamadasAntes + LRegra.ChamadasDepois + LRegra.ChamadasRota);
end;

procedure TDFeSimuladorRegrasTests.Regra_NascidaDesligada_ComecaDesligada;
var
  LRegra: TRegraNascidaDesligada;
begin
  LRegra := TRegraNascidaDesligada.Create;
  FServidor.AdicionarRegra(LRegra);
  Assert.IsFalse(LRegra.Ativa);
  Assert.IsTrue(Pos('"ativa":false', FServidor.Tratar('GET', '/admin/regras', '', '', '').Corpo) > 0, 'a lista mostra desligada');
end;

procedure TDFeSimuladorRegrasTests.Ganchos_NaoVeemPingNemAdmin;
var
  LRegra: TRegraGravadora;
begin
  LRegra := NovaRegra;
  LRegra.ResponderAntes := True;
  FServidor.Tratar('GET', '/ping', '', '', '');
  FServidor.Tratar('GET', '/admin/estado', '', '', '');
  FServidor.Tratar('POST', '/admin/falhas', '', '', '{"falha":"timeout"}');
  Assert.AreEqual(0, LRegra.ChamadasAntes);
  Assert.AreEqual(0, LRegra.ChamadasRota);
  Assert.AreEqual(1, FSim.FalhasPendentes, 'o /admin/falhas funcionou apesar da regra');
end;

procedure TDFeSimuladorRegrasTests.Rota_Extensao_ChegaNaRegra;
var
  LRegra: TRegraGravadora;
  R: TDFeSimHttpResposta;
begin
  LRegra := NovaRegra;
  LRegra.CaminhoDaRota := '/ext/oi';
  R := FServidor.Tratar('POST', '/ext/oi', '', 'application/json', '{"a":1}');
  Assert.AreEqual(200, R.Status);
  Assert.AreEqual('rota da gravadora', R.Corpo);
  Assert.IsTrue(LRegra.UltimaRota.Servico = ssExtensao, 'servico extensao');
  Assert.AreEqual('POST', LRegra.UltimaRota.Metodo);
  Assert.AreEqual('{"a":1}', LRegra.UltimaRota.Corpo);
end;

procedure TDFeSimuladorRegrasTests.Rota_Extensao_SemRegraQueAtenda_404;
var
  LRegra: TRegraGravadora;
  R: TDFeSimHttpResposta;
begin
  LRegra := NovaRegra; // nao atende nenhuma rota
  R := FServidor.Tratar('GET', '/ext/nada', '', '', '');
  Assert.AreEqual(404, R.Status);
  Assert.IsTrue(LRegra.ChamadasRota = 1, 'a regra foi perguntada');
  Assert.IsTrue(Pos('/ext/nada', R.Corpo) > 0, 'a mensagem diz qual caminho');
end;

procedure TDFeSimuladorRegrasTests.Rota_Extensao_RegraDesligada_404;
var
  LRegra: TRegraGravadora;
begin
  LRegra := NovaRegra;
  LRegra.CaminhoDaRota := '/ext/oi';
  Assert.AreEqual(200, FServidor.Tratar('GET', '/ext/oi', '', '', '').Status);
  LRegra.Ativa := False;
  Assert.AreEqual(404, FServidor.Tratar('GET', '/ext/oi', '', '', '').Status);
end;

procedure TDFeSimuladorRegrasTests.Rota_Extensao_EscolheAPrimeiraQueResponde;
var
  LA: TRegraGravadora;
  LB: TRegraGravadoraB;
begin
  LA := NovaRegra;
  LB := NovaRegraB;
  LB.CaminhoDaRota := '/ext/da-b';
  Assert.AreEqual('rota da gravadora-b', FServidor.Tratar('GET', '/ext/da-b', '', '', '').Corpo);
  Assert.AreEqual(1, LA.ChamadasRota);
  Assert.AreEqual(1, LB.ChamadasRota);
end;

procedure TDFeSimuladorRegrasTests.Zerar_AvisaAsRegras;
var
  LRegra: TRegraGravadora;
begin
  LRegra := NovaRegra;
  Assert.AreEqual(200, FServidor.Tratar('POST', '/admin/zerar', '', '', '').Status);
  Assert.AreEqual(1, LRegra.ChamadasZerar);
end;

procedure TDFeSimuladorRegrasTests.Zerar_ComFalha_NaoAvisa;
var
  LRegra: TRegraGravadora;
begin
  LRegra := NovaRegra;
  Assert.AreEqual(405, FServidor.Tratar('GET', '/admin/zerar', '', '', '').Status, 'metodo errado');
  Assert.AreEqual(0, LRegra.ChamadasZerar);
end;

procedure TDFeSimuladorRegrasTests.AdminRegras_Lista;
var
  R: TDFeSimHttpResposta;
  LVazio: TDFeSimuladorServidor;
begin
  NovaRegra;
  R := FServidor.Tratar('GET', '/admin/regras', '', '', '');
  Assert.AreEqual(200, R.Status);
  Assert.AreEqual('{"regras":[{"nome":"gravadora","descricao":"grava as chamadas","ativa":true}]}', R.Corpo);
  LVazio := TDFeSimuladorServidor.Create(FSim);
  try
    Assert.AreEqual('{"regras":[]}', LVazio.Tratar('GET', '/admin/regras', '', '', '').Corpo);
  finally
    LVazio.Free;
  end;
end;

procedure TDFeSimuladorRegrasTests.AdminRegras_LigaEDesliga;
var
  LRegra: TRegraGravadora;
  R: TDFeSimHttpResposta;
begin
  LRegra := NovaRegra;
  R := FServidor.Tratar('POST', '/admin/regras', '', 'application/json',
    '{"nome":"GRAVADORA","ativa":false}');
  Assert.AreEqual(200, R.Status);
  Assert.IsFalse(LRegra.Ativa);
  Assert.IsTrue(Pos('"ativa":false', R.Corpo) > 0, 'a resposta ja mostra o novo estado');
  FServidor.Tratar('POST', '/admin/regras', '', '', '{"nome":"gravadora","ativa":true}');
  Assert.IsTrue(LRegra.Ativa);
end;

procedure TDFeSimuladorRegrasTests.AdminRegras_Desconhecida_404;
begin
  NovaRegra;
  Assert.AreEqual(404, FServidor.Tratar('POST', '/admin/regras', '', '',
    '{"nome":"nao-existe","ativa":false}').Status);
end;

procedure TDFeSimuladorRegrasTests.AdminRegras_Invalido_400;
begin
  NovaRegra;
  Assert.AreEqual(400, FServidor.Tratar('POST', '/admin/regras', '', '', '{nome').Status, 'JSON quebrado');
  Assert.AreEqual(400, FServidor.Tratar('POST', '/admin/regras', '', '', '{"nome":"gravadora"}').Status, 'sem ativa');
  Assert.AreEqual(400, FServidor.Tratar('POST', '/admin/regras', '', '', '{"ativa":true}').Status, 'sem nome');
end;

procedure TDFeSimuladorRegrasTests.AdminRegras_MetodoErrado_405;
begin
  Assert.AreEqual(405, FServidor.Tratar('DELETE', '/admin/regras', '', '', '').Status);
end;

procedure TDFeSimuladorRegrasTests.AdicionarRegra_NomeRepetido_LevantaENaoAdota;
var
  LOutra: TRegraGravadora;
  LLevantou: Boolean;
begin
  NovaRegra;
  LOutra := TRegraGravadora.Create;
  try
    LLevantou := False;
    try
      FServidor.AdicionarRegra(LOutra);
    except
      on Exception do
        LLevantou := True;
    end;
    Assert.IsTrue(LLevantou, 'levantou');
    Assert.AreEqual(1, FServidor.Regras, 'so a primeira foi adotada');
  finally
    LOutra.Free; // quem chamou continua dono
  end;
end;

procedure TDFeSimuladorRegrasTests.Excecao_NoGancho_Propaga;
var
  LRegra: TRegraGravadora;
  LMsg: string;
begin
  LRegra := NovaRegra;
  LRegra.LevantarNoAntes := True;
  LMsg := '';
  try
    PostarDistribuicao;
  except
    on E: Exception do
      LMsg := E.Message;
  end;
  Assert.AreEqual('defeito da regra', LMsg); // a casca HTTP (Horse) a converte em 500
  LRegra.LevantarNoAntes := False;
  Assert.AreEqual(200, PostarDistribuicao.Status, 'o servidor continua respondendo depois do defeito');
end;

procedure TDFeSimuladorRegrasTests.Registro_AdicionaUmaInstanciaPorServidor;
var
  LSalvas: TDFeSimuladorRegraClasseArray;
  LOutro: TDFeSimuladorServidor;
  I: Integer;
begin
  LSalvas := RegrasSimuladorRegistradas;
  LimparRegrasSimuladorRegistradas;
  LOutro := TDFeSimuladorServidor.Create(FSim);
  try
    RegistrarRegraSimulador(TRegraGravadora);
    FServidor.AdicionarRegrasRegistradas;
    LOutro.AdicionarRegrasRegistradas;
    Assert.AreEqual(1, FServidor.Regras);
    Assert.AreEqual(1, LOutro.Regras);
    Assert.IsTrue(FServidor.Regra(0) <> LOutro.Regra(0), 'instancias distintas (estado por servidor)');
    Assert.IsTrue(TRegraGravadora(FServidor.Regra(0)).SimuladorVisto = FSim, 'e Anexar ja foi feito');
  finally
    LOutro.Free;
    LimparRegrasSimuladorRegistradas;
    for I := 0 to High(LSalvas) do
      RegistrarRegraSimulador(LSalvas[I]);
  end;
end;

procedure TDFeSimuladorRegrasTests.Registro_NomeRepetido_Levanta;
var
  LSalvas: TDFeSimuladorRegraClasseArray;
  LLevantou: Boolean;
  I: Integer;
begin
  LSalvas := RegrasSimuladorRegistradas;
  LimparRegrasSimuladorRegistradas;
  try
    RegistrarRegraSimulador(TRegraGravadora);
    LLevantou := False;
    try
      RegistrarRegraSimulador(TRegraGravadora);
    except
      on Exception do
        LLevantou := True;
    end;
    Assert.IsTrue(LLevantou);
    Assert.AreEqual(1, Integer(Length(RegrasSimuladorRegistradas)));
  finally
    LimparRegrasSimuladorRegistradas;
    for I := 0 to High(LSalvas) do
      RegistrarRegraSimulador(LSalvas[I]);
  end;
end;

procedure TDFeSimuladorRegrasTests.Registro_NomeVazio_Levanta;
var
  LLevantou: Boolean;
begin
  LLevantou := False;
  try
    RegistrarRegraSimulador(TRegraSemNome);
  except
    on Exception do
      LLevantou := True;
  end;
  Assert.IsTrue(LLevantou);
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeSimuladorRegrasTests);

end.
