unit DFe.SimuladorRegrasTests;

{ Extensao do simulador em Pascal (DFe.Simulador.Regras + os ganchos de
  DFe.Simulador.Servidor): curto-circuito, alteracao da resposta, rotas /ext/,
  liga/desliga por /admin/regras, AoZerar e o registro por initialization. Tudo em
  processo, sem HTTP. }

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils,
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

  TDFeSimuladorRegrasTests = class(TTestCase)
  private
    FSim: TDFeSimuladorSefaz;
    FServidor: TDFeSimuladorServidor;
    function NovaRegra: TRegraGravadora;
    function NovaRegraB: TRegraGravadoraB;
    function PostarDistribuicao: TDFeSimHttpResposta;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure SemRegras_TudoComoAntes;
    procedure Regra_QueNaoResponde_DeixaONucleoAtender;
    procedure Regra_RecebeARequisicaoCompleta;
    procedure Regra_RecebeOServicoDeEvento;
    procedure Regra_QueResponde_CurtoCircuitaONucleo;
    procedure Regra_QueResponde_DispensaAsSeguintes;
    procedure DepoisDeAtender_PodeAlterarARespostaDoNucleo;
    procedure Regra_Desligada_NaoEConsultada;
    procedure Regra_NascidaDesligada_ComecaDesligada;
    procedure Ganchos_NaoVeemPingNemAdmin;
    procedure Rota_Extensao_ChegaNaRegra;
    procedure Rota_Extensao_SemRegraQueAtenda_404;
    procedure Rota_Extensao_RegraDesligada_404;
    procedure Rota_Extensao_EscolheAPrimeiraQueResponde;
    procedure Zerar_AvisaAsRegras;
    procedure Zerar_ComFalha_NaoAvisa;
    procedure AdminRegras_Lista;
    procedure AdminRegras_LigaEDesliga;
    procedure AdminRegras_Desconhecida_404;
    procedure AdminRegras_Invalido_400;
    procedure AdminRegras_MetodoErrado_405;
    procedure AdicionarRegra_NomeRepetido_LevantaENaoAdota;
    procedure Excecao_NoGancho_Propaga;
    procedure Registro_AdicionaUmaInstanciaPorServidor;
    procedure Registro_NomeRepetido_Levanta;
    procedure Registro_NomeVazio_Levanta;
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

procedure TDFeSimuladorRegrasTests.SetUp;
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
  AssertEquals(0, FServidor.Regras);
  R := PostarDistribuicao;
  AssertEquals(200, R.Status);
  AssertTrue('137', Pos('<cStat>137</cStat>', R.Corpo) > 0);
  AssertEquals(404, FServidor.Tratar('GET', '/ext/qualquer', '', '', '').Status);
end;

procedure TDFeSimuladorRegrasTests.Regra_QueNaoResponde_DeixaONucleoAtender;
var
  LRegra: TRegraGravadora;
  R: TDFeSimHttpResposta;
begin
  LRegra := NovaRegra;
  R := PostarDistribuicao;
  AssertEquals(200, R.Status);
  AssertTrue('o nucleo respondeu 137', Pos('<cStat>137</cStat>', R.Corpo) > 0);
  AssertEquals(1, FSim.TotalConsultas);
  AssertEquals(1, LRegra.ChamadasAntes);
  AssertEquals(1, LRegra.ChamadasDepois);
end;

procedure TDFeSimuladorRegrasTests.Regra_RecebeARequisicaoCompleta;
var
  LRegra: TRegraGravadora;
begin
  LRegra := NovaRegra;
  PostarDistribuicao;
  AssertTrue('servico distribuicao', LRegra.UltimaAntes.Servico = ssDistribuicao);
  AssertEquals('POST', LRegra.UltimaAntes.Metodo);
  AssertEquals(CAMINHO_DIST, LRegra.UltimaAntes.Caminho);
  AssertEquals(SOAP_DIST, LRegra.UltimaAntes.SoapAction);
  AssertEquals('application/soap+xml; charset=utf-8', LRegra.UltimaAntes.ContentType);
  AssertEquals(REQUISICAO, LRegra.UltimaAntes.Corpo);
  AssertTrue('Agora e o relogio do simulador', Abs(LRegra.UltimaAntes.Agora - FSim.AgoraSimulado) < 1);
  AssertTrue('a regra enxerga o simulador do servidor', LRegra.SimuladorVisto = FSim);
end;

procedure TDFeSimuladorRegrasTests.Regra_RecebeOServicoDeEvento;
var
  LRegra: TRegraGravadora;
begin
  LRegra := NovaRegra;
  LRegra.ResponderAntes := True; // nao deixa o nucleo tentar interpretar um evento falso
  FServidor.Tratar('POST', CAMINHO_EVT, '', '', '<x/>');
  AssertTrue('servico evento', LRegra.UltimaAntes.Servico = ssEvento);
end;

procedure TDFeSimuladorRegrasTests.Regra_QueResponde_CurtoCircuitaONucleo;
var
  LRegra: TRegraGravadora;
  R: TDFeSimHttpResposta;
begin
  LRegra := NovaRegra;
  LRegra.ResponderAntes := True;
  R := PostarDistribuicao;
  AssertEquals(418, R.Status);
  AssertEquals('respondido pela regra gravadora', R.Corpo);
  AssertEquals('o nucleo nao foi tocado', 0, FSim.TotalConsultas);
  AssertEquals('o adaptador SOAP nem viu o request', 0, FServidor.Requisicoes);
  AssertEquals('DepoisDeAtender nao roda quando a regra respondeu', 0, LRegra.ChamadasDepois);
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
  AssertEquals(1, LA.ChamadasAntes);
  AssertEquals('a seguinte nem foi consultada', 0, LB.ChamadasAntes);
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
  AssertEquals(503, R.Status);
  AssertTrue('o corpo continua sendo o do nucleo', Pos('<cStat>137</cStat>', R.Corpo) > 0);
  AssertEquals('todas as regras rodam o Depois', 1, LB.ChamadasDepois);
  AssertEquals(1, FSim.TotalConsultas);
end;

procedure TDFeSimuladorRegrasTests.Regra_Desligada_NaoEConsultada;
var
  LRegra: TRegraGravadora;
begin
  LRegra := NovaRegra;
  LRegra.Ativa := False;
  LRegra.ResponderAntes := True;
  LRegra.CaminhoDaRota := '/ext/x';
  AssertEquals(200, PostarDistribuicao.Status);
  AssertEquals(404, FServidor.Tratar('GET', '/ext/x', '', '', '').Status);
  AssertEquals(0, LRegra.ChamadasAntes + LRegra.ChamadasDepois + LRegra.ChamadasRota);
end;

procedure TDFeSimuladorRegrasTests.Regra_NascidaDesligada_ComecaDesligada;
var
  LRegra: TRegraNascidaDesligada;
begin
  LRegra := TRegraNascidaDesligada.Create;
  FServidor.AdicionarRegra(LRegra);
  AssertFalse(LRegra.Ativa);
  AssertTrue('a lista mostra desligada',
    Pos('"ativa":false', FServidor.Tratar('GET', '/admin/regras', '', '', '').Corpo) > 0);
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
  AssertEquals(0, LRegra.ChamadasAntes);
  AssertEquals(0, LRegra.ChamadasRota);
  AssertEquals('o /admin/falhas funcionou apesar da regra', 1, FSim.FalhasPendentes);
end;

procedure TDFeSimuladorRegrasTests.Rota_Extensao_ChegaNaRegra;
var
  LRegra: TRegraGravadora;
  R: TDFeSimHttpResposta;
begin
  LRegra := NovaRegra;
  LRegra.CaminhoDaRota := '/ext/oi';
  R := FServidor.Tratar('POST', '/ext/oi', '', 'application/json', '{"a":1}');
  AssertEquals(200, R.Status);
  AssertEquals('rota da gravadora', R.Corpo);
  AssertTrue('servico extensao', LRegra.UltimaRota.Servico = ssExtensao);
  AssertEquals('POST', LRegra.UltimaRota.Metodo);
  AssertEquals('{"a":1}', LRegra.UltimaRota.Corpo);
end;

procedure TDFeSimuladorRegrasTests.Rota_Extensao_SemRegraQueAtenda_404;
var
  LRegra: TRegraGravadora;
  R: TDFeSimHttpResposta;
begin
  LRegra := NovaRegra; // nao atende nenhuma rota
  R := FServidor.Tratar('GET', '/ext/nada', '', '', '');
  AssertEquals(404, R.Status);
  AssertTrue('a regra foi perguntada', LRegra.ChamadasRota = 1);
  AssertTrue('a mensagem diz qual caminho', Pos('/ext/nada', R.Corpo) > 0);
end;

procedure TDFeSimuladorRegrasTests.Rota_Extensao_RegraDesligada_404;
var
  LRegra: TRegraGravadora;
begin
  LRegra := NovaRegra;
  LRegra.CaminhoDaRota := '/ext/oi';
  AssertEquals(200, FServidor.Tratar('GET', '/ext/oi', '', '', '').Status);
  LRegra.Ativa := False;
  AssertEquals(404, FServidor.Tratar('GET', '/ext/oi', '', '', '').Status);
end;

procedure TDFeSimuladorRegrasTests.Rota_Extensao_EscolheAPrimeiraQueResponde;
var
  LA: TRegraGravadora;
  LB: TRegraGravadoraB;
begin
  LA := NovaRegra;
  LB := NovaRegraB;
  LB.CaminhoDaRota := '/ext/da-b';
  AssertEquals('rota da gravadora-b', FServidor.Tratar('GET', '/ext/da-b', '', '', '').Corpo);
  AssertEquals(1, LA.ChamadasRota);
  AssertEquals(1, LB.ChamadasRota);
end;

procedure TDFeSimuladorRegrasTests.Zerar_AvisaAsRegras;
var
  LRegra: TRegraGravadora;
begin
  LRegra := NovaRegra;
  AssertEquals(200, FServidor.Tratar('POST', '/admin/zerar', '', '', '').Status);
  AssertEquals(1, LRegra.ChamadasZerar);
end;

procedure TDFeSimuladorRegrasTests.Zerar_ComFalha_NaoAvisa;
var
  LRegra: TRegraGravadora;
begin
  LRegra := NovaRegra;
  AssertEquals('metodo errado', 405, FServidor.Tratar('GET', '/admin/zerar', '', '', '').Status);
  AssertEquals(0, LRegra.ChamadasZerar);
end;

procedure TDFeSimuladorRegrasTests.AdminRegras_Lista;
var
  R: TDFeSimHttpResposta;
  LVazio: TDFeSimuladorServidor;
begin
  NovaRegra;
  R := FServidor.Tratar('GET', '/admin/regras', '', '', '');
  AssertEquals(200, R.Status);
  AssertEquals('{"regras":[{"nome":"gravadora","descricao":"grava as chamadas","ativa":true}]}', R.Corpo);
  LVazio := TDFeSimuladorServidor.Create(FSim);
  try
    AssertEquals('{"regras":[]}', LVazio.Tratar('GET', '/admin/regras', '', '', '').Corpo);
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
  AssertEquals(200, R.Status);
  AssertFalse(LRegra.Ativa);
  AssertTrue('a resposta ja mostra o novo estado', Pos('"ativa":false', R.Corpo) > 0);
  FServidor.Tratar('POST', '/admin/regras', '', '', '{"nome":"gravadora","ativa":true}');
  AssertTrue(LRegra.Ativa);
end;

procedure TDFeSimuladorRegrasTests.AdminRegras_Desconhecida_404;
begin
  NovaRegra;
  AssertEquals(404, FServidor.Tratar('POST', '/admin/regras', '', '',
    '{"nome":"nao-existe","ativa":false}').Status);
end;

procedure TDFeSimuladorRegrasTests.AdminRegras_Invalido_400;
begin
  NovaRegra;
  AssertEquals('JSON quebrado', 400, FServidor.Tratar('POST', '/admin/regras', '', '', '{nome').Status);
  AssertEquals('sem ativa', 400, FServidor.Tratar('POST', '/admin/regras', '', '', '{"nome":"gravadora"}').Status);
  AssertEquals('sem nome', 400, FServidor.Tratar('POST', '/admin/regras', '', '', '{"ativa":true}').Status);
end;

procedure TDFeSimuladorRegrasTests.AdminRegras_MetodoErrado_405;
begin
  AssertEquals(405, FServidor.Tratar('DELETE', '/admin/regras', '', '', '').Status);
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
    AssertTrue('levantou', LLevantou);
    AssertEquals('so a primeira foi adotada', 1, FServidor.Regras);
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
  AssertEquals('defeito da regra', LMsg); // a casca HTTP (Horse) a converte em 500
  LRegra.LevantarNoAntes := False;
  AssertEquals('o servidor continua respondendo depois do defeito', 200, PostarDistribuicao.Status);
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
    AssertEquals(1, FServidor.Regras);
    AssertEquals(1, LOutro.Regras);
    AssertTrue('instancias distintas (estado por servidor)', FServidor.Regra(0) <> LOutro.Regra(0));
    AssertTrue('e Anexar ja foi feito', TRegraGravadora(FServidor.Regra(0)).SimuladorVisto = FSim);
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
    AssertTrue(LLevantou);
    AssertEquals(1, Length(RegrasSimuladorRegistradas));
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
  AssertTrue(LLevantou);
end;

initialization
  RegisterTest(TDFeSimuladorRegrasTests);

end.
