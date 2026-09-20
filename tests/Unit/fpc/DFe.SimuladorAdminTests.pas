unit DFe.SimuladorAdminTests;

{ Fase B do simulador standalone (docs/simulador-standalone.md): as adicoes ao
  nucleo (Zerar, Contas, FalhasPendentes), o modo estrito do adaptador SOAP, o
  relogio virtual, o JSON plano, o cenario atomico e a API admin -- tudo sem
  HTTP (a API admin e' uma funcao metodo/caminho/corpo -> status/corpo). }

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils, Classes,
  DFe.Types,
  DFe.Transmissor,
  DFe.Simulador,
  DFe.Simulador.Soap,
  DFe.Simulador.Fixtures,
  DFe.Simulador.Relogio,
  DFe.Simulador.Json,
  DFe.Simulador.Cenario,
  DFe.Simulador.Servidor,
  DFe.TestDoubles;

type
  TDFeSimuladorNucleoFaseBTests = class(TTestCase)
  private
    FRelogio: TDFeRelogioFake;
    FSim: TDFeSimuladorSefaz;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Zerar_LimpaContasFalhasEContadores;
    procedure Zerar_PermiteRecomecar;
    procedure Contas_ListaSemCriarConta;
    procedure Contas_ReportaBloqueio;
    procedure FalhasPendentes_ContaEConsome;
    procedure AgoraSimulado_UsaORelogioInjetado;
  end;

  TDFeSimuladorEstritoTests = class(TTestCase)
  private
    FSim: TDFeSimuladorSefaz;
    FTransmissor: TDFeSimuladorTransmissor;
    FIntf: IDFeTransmissor; // dono do ciclo de vida do transmissor
    function Requisicao: string;
    function Transmitir(const ASoapAction: string): TDFeRespostaTransmissao;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Leniente_EOPadrao;
    procedure Leniente_ViolacaoRegistraEAtende;
    procedure Estrito_ViolacaoRecusaComHttp400ENaoTocaOEstado;
    procedure Estrito_RequisicaoValida_Atende;
    procedure LimparViolacoes_EsquecePeloMenosAsRegistradas;
  end;

  TDFeRelogioVirtualTests = class(TTestCase)
  published
    procedure Comeca_SemDeslocamento;
    procedure Avancar_SomaESeReflete;
    procedure Avancar_NaoPositivo_NaoFazNada;
    procedure Zerar_VoltaAZero;
  end;

  TDFeJsonPlanoTests = class(TTestCase)
  private
    function Ler(const ATexto: string): TDFeJsonPlano;
    function Invalido(const ATexto: string): string;
  published
    procedure ObjetoSimples_TextoNumeroBooleano;
    procedure ChavesNaoDiferenciamMaiusculas;
    procedure Ausente_UsaPadrao;
    procedure Null_EquivaleAAusente;
    procedure Lista_DeTextos;
    procedure Lista_Vazia;
    procedure Escalar_ViraListaDeUm;
    procedure Vazio_EObjetoVazio;
    procedure Escapes_Basicos;
    procedure EscapeUnicode_ViraCaractereNativo;
    procedure ParSubstituto_ViraUmPontoDeCodigo;
    procedure Acento_PassaComoEsta;
    procedure Aninhado_Recusa;
    procedure Malformados_ViramErroComPosicao;
    procedure Inteiro_RecusaFracaoETexto;
    procedure JsonEscape_EscapaAspasBarraEControle;
  end;

  TDFeCenarioAtomicoTests = class(TTestCase)
  private
    FSim: TDFeSimuladorSefaz;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure DeTexto_Aplica;
    procedure Invalido_NaoAplicaNada;
    procedure Acumulativo_AplicaPorCimaDoEstado;
  end;

  TDFeSimuladorAdminTests = class(TTestCase)
  private
    FRelogio: TDFeRelogioVirtual;
    FSim: TDFeSimuladorSefaz;
    FServidor: TDFeSimuladorServidor;
    function Admin(const AMetodo, ACaminho: string; const ACorpo: string = ''): TDFeSimHttpResposta;
    function Consultar: TDFeSimHttpResposta;
    function ComRelogio: Boolean;
    procedure CriarServidor(const ARelogio: TDFeRelogioVirtual);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Estado_Inicial_Vazio;
    procedure Documentos_Sintetico_PublicaEDevolveNsu;
    procedure Documentos_DepoisDeConsultar_CStat138;
    procedure Documentos_TipoDesconhecido_400;
    procedure Documentos_CnpjInvalido_400;
    procedure Documentos_QuantidadeForaDoLimite_400;
    procedure Documentos_Literal_Publica;
    procedure Documentos_LiteralSemXml_400;
    procedure Documentos_XNomeComAcento_ViaEscape;
    procedure Documentos_TiposDeEvento;
    procedure PularNsu_AvancaOMaximo;
    procedure Falhas_Enfileira;
    procedure Falhas_Lista;
    procedure Falhas_Desconhecida_400_ENaoEnfileiraNada;
    procedure Falhas_TimeoutViraHttp504;
    procedure Relogio_ReproduzOConsumoIndevidoESaiDeleSemEsperar;
    procedure Relogio_Avancar_Invalido_400;
    procedure Relogio_Zerar;
    procedure Relogio_SemRelogio_501;
    procedure Modo_PadraoLeniente_EAlterna;
    procedure Modo_SemCampo_400;
    procedure Violacoes_GetEDelete;
    procedure UltimoEnvelope_DevolveOQueChegou;
    procedure Cenario_Valido_Aplica;
    procedure Cenario_Invalido_400_ENaoAplicaNada;
    procedure Zerar_LimpaTudoInclusiveORelogio;
    procedure JsonInvalido_400;
    procedure RotaDesconhecida_404;
    procedure MetodoErrado_405;
    procedure CaminhoComBarraFinalEQuery_Funciona;
  end;

implementation

const
  CAMINHO_DIST = '/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx';
  SOAP_DIST = 'http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe/nfeDistDFeInteresse';
  CNPJ_A = '11222333000181';
  NSU_ZERO = '000000000000000';
  RAIZ_SOAP = '<?xml version="1.0" encoding="UTF-8"?><soap12:Envelope ' +
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
    'xmlns:xsd="http://www.w3.org/2001/XMLSchema" ' +
    'xmlns:soap12="http://www.w3.org/2003/05/soap-envelope"><soap12:Body>';

function RequisicaoDistribuicao: string;
begin
  Result := RAIZ_SOAP +
    '<nfeDistDFeInteresse xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe">' +
    '<nfeDadosMsg><distDFeInt xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.01">' +
    '<tpAmb>2</tpAmb><cUFAutor>43</cUFAutor><CNPJ>' + CNPJ_A + '</CNPJ>' +
    '<distNSU><ultNSU>' + NSU_ZERO + '</ultNSU></distNSU></distDFeInt></nfeDadosMsg>' +
    '</nfeDistDFeInteresse></soap12:Body></soap12:Envelope>';
end;

{ ---------------- nucleo ---------------- }

procedure TDFeSimuladorNucleoFaseBTests.SetUp;
begin
  FRelogio := TDFeRelogioFake.Create;
  FRelogio.Agora := EncodeDate(2026, 9, 20) + EncodeTime(10, 0, 0, 0);
  FSim := TDFeSimuladorSefaz.Create(FRelogio.ObterAgora);
end;

procedure TDFeSimuladorNucleoFaseBTests.TearDown;
begin
  FSim.Free;
  FRelogio.Free;
end;

procedure TDFeSimuladorNucleoFaseBTests.Zerar_LimpaContasFalhasEContadores;
begin
  FSim.PublicarDocumento(CNPJ_A, 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  FSim.EnfileirarFalha(fsTimeout);
  FSim.Consultar(CNPJ_A, 'RS', 0); // consome a falha
  FSim.EnfileirarFalha(fsErroHttp);
  FSim.Zerar;
  AssertEquals(0, Length(FSim.Contas));
  AssertEquals(0, FSim.FalhasPendentes);
  AssertEquals(0, FSim.TotalConsultas);
  AssertEquals(0, FSim.EventosRegistrados);
end;

procedure TDFeSimuladorNucleoFaseBTests.Zerar_PermiteRecomecar;
var
  R: TDFeRespostaSimulada;
begin
  FSim.PublicarDocumento(CNPJ_A, 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  FSim.Consultar(CNPJ_A, 'RS', 0); // 138: abre o bloqueio? (so' 137 abre) -- de qualquer modo zera
  FSim.Zerar;
  R := FSim.Consultar(CNPJ_A, 'RS', 0);
  AssertEquals(137, R.Lote.CStat); // conta nova, sem documentos e sem bloqueio
end;

procedure TDFeSimuladorNucleoFaseBTests.Contas_ListaSemCriarConta;
var
  L: TDFeSimContaResumoArray;
begin
  AssertEquals(0, Length(FSim.Contas));
  FSim.PublicarDocumento(CNPJ_A, 'rs', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  FSim.PublicarDocumento(CNPJ_A, 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 2)));
  FSim.PularNSU('12345678000199', 'SP', 5);
  L := FSim.Contas;
  AssertEquals(2, Length(L));
  AssertEquals(CNPJ_A, L[0].Cnpj);
  AssertEquals('RS', L[0].UF);
  AssertEquals(2, L[0].NsuAtual);
  AssertEquals(2, L[0].Documentos);
  AssertEquals('SP', L[1].UF);
  AssertEquals(5, L[1].NsuAtual);
  AssertEquals(0, L[1].Documentos);
  FSim.Contas; // ler nao cria
  AssertEquals(2, Length(FSim.Contas));
end;

procedure TDFeSimuladorNucleoFaseBTests.Contas_ReportaBloqueio;
var
  L: TDFeSimContaResumoArray;
begin
  FSim.PublicarDocumento(CNPJ_A, 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  L := FSim.Contas;
  AssertTrue('livre', L[0].BloqueadoAte = 0);
  FSim.Consultar(CNPJ_A, 'RS', 1); // sem novidade (ja' viu o 1): 137, abre o bloqueio de 1 h
  L := FSim.Contas;
  AssertTrue('bloqueada ate 1 h depois', L[0].BloqueadoAte > FRelogio.Agora);
end;

procedure TDFeSimuladorNucleoFaseBTests.FalhasPendentes_ContaEConsome;
begin
  AssertEquals(0, FSim.FalhasPendentes);
  FSim.EnfileirarFalha(fsTimeout);
  FSim.EnfileirarFalha(fsErroHttp);
  AssertEquals(2, FSim.FalhasPendentes);
  FSim.Consultar(CNPJ_A, 'RS', 0);
  AssertEquals(1, FSim.FalhasPendentes);
end;

procedure TDFeSimuladorNucleoFaseBTests.AgoraSimulado_UsaORelogioInjetado;
begin
  AssertTrue(FRelogio.Agora = FSim.AgoraSimulado);
  FRelogio.Agora := FRelogio.Agora + 1;
  AssertTrue(FRelogio.Agora = FSim.AgoraSimulado);
end;

{ ---------------- estrito ---------------- }

procedure TDFeSimuladorEstritoTests.SetUp;
begin
  FSim := TDFeSimuladorSefaz.Create;
  FTransmissor := TDFeSimuladorTransmissor.Create(FSim);
  FIntf := FTransmissor;
end;

procedure TDFeSimuladorEstritoTests.TearDown;
begin
  FIntf := nil;
  FTransmissor := nil;
  FSim.Free;
end;

function TDFeSimuladorEstritoTests.Requisicao: string;
begin
  Result := RequisicaoDistribuicao;
end;

function TDFeSimuladorEstritoTests.Transmitir(const ASoapAction: string): TDFeRespostaTransmissao;
begin
  Result := FIntf.Transmitir(Requisicao, CAMINHO_DIST, ASoapAction, '');
end;

procedure TDFeSimuladorEstritoTests.Leniente_EOPadrao;
begin
  AssertFalse(FTransmissor.Estrito);
end;

procedure TDFeSimuladorEstritoTests.Leniente_ViolacaoRegistraEAtende;
var
  R: TDFeRespostaTransmissao;
begin
  R := Transmitir('http://errada/acao');
  AssertEquals(200, R.HTTPResultCode);
  AssertEquals(1, FTransmissor.QuantidadeViolacoes);
  AssertEquals(1, FSim.TotalConsultas); // atendeu de verdade
end;

procedure TDFeSimuladorEstritoTests.Estrito_ViolacaoRecusaComHttp400ENaoTocaOEstado;
var
  R: TDFeRespostaTransmissao;
begin
  FTransmissor.Estrito := True;
  R := Transmitir('http://errada/acao');
  AssertEquals(400, R.HTTPResultCode);
  AssertEquals(0, R.InternalErrorCode);
  AssertTrue('a recusa diz o motivo', Pos('SoapAction', R.Texto) > 0);
  AssertTrue('e diz que e o modo estrito', Pos('estrito', R.Texto) > 0);
  AssertEquals(1, FTransmissor.QuantidadeViolacoes);
  // o ponto: a requisicao recusada NAO consumiu NSU nem abriu bloqueio
  AssertEquals(0, FSim.TotalConsultas);
  AssertEquals(0, Length(FSim.Contas));
end;

procedure TDFeSimuladorEstritoTests.Estrito_RequisicaoValida_Atende;
var
  R: TDFeRespostaTransmissao;
begin
  FTransmissor.Estrito := True;
  R := Transmitir(SOAP_DIST);
  AssertEquals(200, R.HTTPResultCode);
  AssertEquals(0, FTransmissor.QuantidadeViolacoes);
  AssertEquals(1, FSim.TotalConsultas);
end;

procedure TDFeSimuladorEstritoTests.LimparViolacoes_EsquecePeloMenosAsRegistradas;
begin
  Transmitir('http://errada/acao');
  AssertEquals(1, FTransmissor.QuantidadeViolacoes);
  FTransmissor.LimparViolacoes;
  AssertEquals(0, FTransmissor.QuantidadeViolacoes);
  AssertEquals('', FTransmissor.TodasViolacoes);
  AssertEquals(1, FTransmissor.Requisicoes); // o contador de requisicoes fica
end;

{ ---------------- relogio ---------------- }

procedure TDFeRelogioVirtualTests.Comeca_SemDeslocamento;
var
  R: TDFeRelogioVirtual;
begin
  R := TDFeRelogioVirtual.Create;
  try
    AssertEquals(0, Int64(R.DeslocamentoSegundos));
  finally
    R.Free;
  end;
end;

procedure TDFeRelogioVirtualTests.Avancar_SomaESeReflete;
var
  R: TDFeRelogioVirtual;
  LAntes, LDepois: TDateTime;
begin
  R := TDFeRelogioVirtual.Create;
  try
    LAntes := Now;
    R.Avancar(3600);
    R.Avancar(60);
    LDepois := R.Agora;
    AssertEquals(3660, Int64(R.DeslocamentoSegundos));
    // Agora ~ Now + 3660 s (tolerancia de 5 s para a execucao do teste)
    AssertTrue('avancou ~3660 s', (LDepois - LAntes) * 86400 > 3655);
    AssertTrue('e nao muito mais', (LDepois - LAntes) * 86400 < 3670);
  finally
    R.Free;
  end;
end;

procedure TDFeRelogioVirtualTests.Avancar_NaoPositivo_NaoFazNada;
var
  R: TDFeRelogioVirtual;
begin
  R := TDFeRelogioVirtual.Create;
  try
    R.Avancar(0);
    R.Avancar(-500);
    AssertEquals(0, Int64(R.DeslocamentoSegundos));
  finally
    R.Free;
  end;
end;

procedure TDFeRelogioVirtualTests.Zerar_VoltaAZero;
var
  R: TDFeRelogioVirtual;
begin
  R := TDFeRelogioVirtual.Create;
  try
    R.Avancar(999);
    R.Zerar;
    AssertEquals(0, Int64(R.DeslocamentoSegundos));
  finally
    R.Free;
  end;
end;

{ ---------------- json ---------------- }

function TDFeJsonPlanoTests.Ler(const ATexto: string): TDFeJsonPlano;
var
  LErro: string;
begin
  if not LerJsonPlano(ATexto, Result, LErro) then
    Fail('JSON deveria ser valido: ' + LErro);
end;

function TDFeJsonPlanoTests.Invalido(const ATexto: string): string;
var
  LObj: TDFeJsonPlano;
begin
  if LerJsonPlano(ATexto, LObj, Result) then
  begin
    LObj.Free;
    Fail('JSON deveria ser recusado: ' + ATexto);
  end;
  AssertTrue('sem objeto quando falha', LObj = nil);
end;

procedure TDFeJsonPlanoTests.ObjetoSimples_TextoNumeroBooleano;
var
  J: TDFeJsonPlano;
begin
  J := Ler('{"cnpj":"11222333000181","quantidade":3,"estrito":true,"nao":false,"neg":-7}');
  try
    AssertEquals('11222333000181', J.Texto('cnpj'));
    AssertEquals(3, Integer(J.Inteiro('quantidade', 0)));
    AssertEquals(-7, Integer(J.Inteiro('neg', 0)));
    AssertTrue(J.Booleano('estrito', False));
    AssertFalse(J.Booleano('nao', True));
  finally
    J.Free;
  end;
end;

procedure TDFeJsonPlanoTests.ChavesNaoDiferenciamMaiusculas;
var
  J: TDFeJsonPlano;
begin
  J := Ler('{"CNPJ":"1"}');
  try
    AssertEquals('1', J.Texto('cnpj'));
    AssertTrue(J.Tem('Cnpj'));
  finally
    J.Free;
  end;
end;

procedure TDFeJsonPlanoTests.Ausente_UsaPadrao;
var
  J: TDFeJsonPlano;
begin
  J := Ler('{}');
  try
    AssertEquals('pad', J.Texto('x', 'pad'));
    AssertEquals(9, Integer(J.Inteiro('x', 9)));
    AssertTrue(J.Booleano('x', True));
    AssertFalse(J.Tem('x'));
    AssertFalse(J.EInteiro('x'));
  finally
    J.Free;
  end;
end;

procedure TDFeJsonPlanoTests.Null_EquivaleAAusente;
var
  J: TDFeJsonPlano;
begin
  J := Ler('{"a":null,"b":"null"}');
  try
    AssertFalse(J.Tem('a'));
    AssertEquals('null', J.Texto('b')); // a STRING "null" nao e' o literal
  finally
    J.Free;
  end;
end;

procedure TDFeJsonPlanoTests.Lista_DeTextos;
var
  J: TDFeJsonPlano;
  L: TDFeJsonLista;
begin
  J := Ler('{"falhas":["timeout", "consumo-indevido","a,b"]}');
  try
    L := J.Lista('falhas');
    AssertEquals(3, Length(L));
    AssertEquals('timeout', L[0]);
    AssertEquals('consumo-indevido', L[1]);
    AssertEquals('a,b', L[2]); // virgula dentro do item nao separa
  finally
    J.Free;
  end;
end;

procedure TDFeJsonPlanoTests.Lista_Vazia;
var
  J: TDFeJsonPlano;
begin
  J := Ler('{"f":[]}');
  try
    AssertEquals(0, Length(J.Lista('f')));
    AssertTrue(J.Tem('f'));
  finally
    J.Free;
  end;
end;

procedure TDFeJsonPlanoTests.Escalar_ViraListaDeUm;
var
  J: TDFeJsonPlano;
  L: TDFeJsonLista;
begin
  J := Ler('{"falha":"timeout"}');
  try
    L := J.Lista('falha');
    AssertEquals(1, Length(L));
    AssertEquals('timeout', L[0]);
    AssertEquals(0, Length(J.Lista('ausente')));
  finally
    J.Free;
  end;
end;

procedure TDFeJsonPlanoTests.Vazio_EObjetoVazio;
var
  J: TDFeJsonPlano;
begin
  J := Ler('   ');
  try
    AssertFalse(J.Tem('x'));
  finally
    J.Free;
  end;
end;

procedure TDFeJsonPlanoTests.Escapes_Basicos;
var
  J: TDFeJsonPlano;
begin
  J := Ler('{"t":"a\"b\\c\/d\ne\tf"}');
  try
    AssertEquals('a"b\c/d' + #10 + 'e' + #9 + 'f', J.Texto('t'));
  finally
    J.Free;
  end;
end;

procedure TDFeJsonPlanoTests.EscapeUnicode_ViraCaractereNativo;
var
  J: TDFeJsonPlano;
begin
  // ã = a-til. No FPC o texto nativo e' UTF-8 (C3 A3).
  J := Ler('{"t":"não"}');
  try
    AssertEquals('n' + #$C3#$A3 + 'o', J.Texto('t'));
  finally
    J.Free;
  end;
end;

procedure TDFeJsonPlanoTests.ParSubstituto_ViraUmPontoDeCodigo;
var
  J: TDFeJsonPlano;
begin
  // U+1F600 = 😀 -> F0 9F 98 80 em UTF-8
  J := Ler('{"t":"😀"}');
  try
    AssertEquals(#$F0#$9F#$98#$80, J.Texto('t'));
  finally
    J.Free;
  end;
end;

procedure TDFeJsonPlanoTests.Acento_PassaComoEsta;
var
  J: TDFeJsonPlano;
  LTexto: string;
begin
  LTexto := 'JOS' + #$C3#$89 + ' A' + #$C3#$87 + 'AI'; // UTF-8 (FPC)
  J := Ler('{"xNome":"' + LTexto + '"}');
  try
    AssertEquals(LTexto, J.Texto('xNome'));
  finally
    J.Free;
  end;
end;

procedure TDFeJsonPlanoTests.Aninhado_Recusa;
begin
  AssertTrue(Pos('aninhado', Invalido('{"a":{"b":1}}')) > 0);
  AssertTrue(Pos('aninhada', Invalido('{"a":[[1]]}')) > 0);
end;

procedure TDFeJsonPlanoTests.Malformados_ViramErroComPosicao;
begin
  AssertTrue(Pos('posicao', Invalido('{"a":1')) > 0);       // sem fechar
  Invalido('{"a" 1}');                                        // sem :
  Invalido('{a:1}');                                          // chave sem aspas
  Invalido('{"a":1,}');                                       // virgula sobrando
  Invalido('{"a":"x}');                                       // string sem fechamento
  Invalido('{"a":1} lixo');                                   // texto apos o objeto
  Invalido('[1,2]');                                          // nao e' objeto
  Invalido('{"a":"\x"}');                                     // escape invalido
  Invalido('{"a":"\u12"}');                                   // \u curto
  Invalido('{"a":tru}');                                      // literal invalido
end;

procedure TDFeJsonPlanoTests.Inteiro_RecusaFracaoETexto;
var
  J: TDFeJsonPlano;
begin
  J := Ler('{"a":1.5,"b":"7","c":1e3,"d":12}');
  try
    AssertFalse('fracao nao e inteiro', J.EInteiro('a'));
    AssertTrue('"7" (string) converte', J.EInteiro('b'));
    AssertFalse('expoente nao e inteiro', J.EInteiro('c'));
    AssertTrue(J.EInteiro('d'));
    AssertEquals(-1, Integer(J.Inteiro('a', -1)));
  finally
    J.Free;
  end;
end;

procedure TDFeJsonPlanoTests.JsonEscape_EscapaAspasBarraEControle;
begin
  AssertEquals('a\"b\\c\nd\u0001', JsonEscape('a"b\c' + #10 + 'd' + #1));
  AssertEquals('"x"', JsonTexto('x'));
  AssertEquals('', JsonEscape(''));
end;

{ ---------------- cenario atomico ---------------- }

procedure TDFeCenarioAtomicoTests.SetUp;
begin
  FSim := TDFeSimuladorSefaz.Create;
end;

procedure TDFeCenarioAtomicoTests.TearDown;
begin
  FSim.Free;
end;

procedure TDFeCenarioAtomicoTests.DeTexto_Aplica;
var
  R: TDFeCenarioResumo;
begin
  R := CarregarCenarioDeTexto('[simulador]' + #10 + 'Falhas=timeout' + #10 +
    '[conta:a]' + #10 + 'Cnpj=11222333000181' + #10 + 'UF=RS' + #10 + 'ResNFe=2', FSim);
  AssertEquals(1, R.Contas);
  AssertEquals(2, R.Documentos);
  AssertEquals(1, R.Falhas);
  AssertEquals(1, FSim.FalhasPendentes);
  AssertEquals(1, Length(FSim.Contas));
end;

procedure TDFeCenarioAtomicoTests.Invalido_NaoAplicaNada;
var
  LLevantou: Boolean;
begin
  LLevantou := False;
  try
    // 1a conta valida, 2a com Cnpj ruim, e uma falha valida: NADA pode ser aplicado
    CarregarCenarioDeTexto('[conta:a]' + #10 + 'Cnpj=11222333000181' + #10 + 'UF=RS' + #10 + 'ResNFe=2' + #10 +
      '[conta:b]' + #10 + 'Cnpj=xx' + #10 + 'UF=SP' + #10 +
      '[simulador]' + #10 + 'Falhas=timeout', FSim);
  except
    on Exception do
      LLevantou := True;
  end;
  AssertTrue(LLevantou);
  AssertEquals(0, Length(FSim.Contas));
  AssertEquals(0, FSim.FalhasPendentes);
end;

procedure TDFeCenarioAtomicoTests.Acumulativo_AplicaPorCimaDoEstado;
begin
  CarregarCenarioDeTexto('[conta:a]' + #10 + 'Cnpj=11222333000181' + #10 + 'UF=RS' + #10 + 'ResNFe=1', FSim);
  CarregarCenarioDeTexto('[conta:a]' + #10 + 'Cnpj=11222333000181' + #10 + 'UF=RS' + #10 + 'ResNFe=1', FSim);
  AssertEquals(2, FSim.Contas[0].Documentos);
end;

{ ---------------- API admin ---------------- }

procedure TDFeSimuladorAdminTests.SetUp;
begin
  FRelogio := nil;
  FSim := nil;
  FServidor := nil;
end;

procedure TDFeSimuladorAdminTests.TearDown;
begin
  FServidor.Free; // antes do simulador
  FSim.Free;
  FRelogio.Free;
end;

procedure TDFeSimuladorAdminTests.CriarServidor(const ARelogio: TDFeRelogioVirtual);
begin
  FRelogio := ARelogio;
  if Assigned(FRelogio) then
    FSim := TDFeSimuladorSefaz.Create(FRelogio.Agora)
  else
    FSim := TDFeSimuladorSefaz.Create;
  FServidor := TDFeSimuladorServidor.Create(FSim, FRelogio);
end;

function TDFeSimuladorAdminTests.ComRelogio: Boolean;
begin
  Result := Assigned(FRelogio);
end;

function TDFeSimuladorAdminTests.Admin(const AMetodo, ACaminho, ACorpo: string): TDFeSimHttpResposta;
begin
  if FServidor = nil then
    CriarServidor(TDFeRelogioVirtual.Create); // padrao: com relogio virtual
  Result := FServidor.Tratar(AMetodo, ACaminho, '', 'application/json', ACorpo);
end;

function TDFeSimuladorAdminTests.Consultar: TDFeSimHttpResposta;
begin
  if FServidor = nil then
    CriarServidor(TDFeRelogioVirtual.Create);
  Result := FServidor.Tratar('POST', CAMINHO_DIST, SOAP_DIST, 'application/soap+xml; charset=utf-8',
    RequisicaoDistribuicao);
end;

procedure TDFeSimuladorAdminTests.Estado_Inicial_Vazio;
var
  R: TDFeSimHttpResposta;
begin
  R := Admin('GET', '/admin/estado');
  AssertEquals(200, R.Status);
  AssertTrue(Pos('json', R.ContentType) > 0);
  AssertTrue('sem contas', Pos('"contas":[]', R.Corpo) > 0);
  AssertTrue('leniente', Pos('"estrito":false', R.Corpo) > 0);
  AssertTrue(Pos('"falhasPendentes":0', R.Corpo) > 0);
  AssertTrue(Pos('"deslocamentoSegundos":0', R.Corpo) > 0);
end;

procedure TDFeSimuladorAdminTests.Documentos_Sintetico_PublicaEDevolveNsu;
var
  R: TDFeSimHttpResposta;
begin
  R := Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"rs","quantidade":3}');
  AssertEquals(200, R.Status);
  AssertTrue(Pos('"publicados":3', R.Corpo) > 0);
  AssertTrue(Pos('"ultimoNsu":3', R.Corpo) > 0);
  R := Admin('GET', '/admin/estado');
  AssertTrue('a conta aparece', Pos('"documentos":3', R.Corpo) > 0);
  AssertTrue(Pos('"uf":"RS"', R.Corpo) > 0);
end;

procedure TDFeSimuladorAdminTests.Documentos_DepoisDeConsultar_CStat138;
var
  R: TDFeSimHttpResposta;
begin
  Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"RS","tipo":"procNFe","quantidade":2}');
  R := Consultar;
  AssertEquals(200, R.Status);
  AssertTrue('cStat 138', Pos('<cStat>138</cStat>', R.Corpo) > 0);
  AssertTrue(Pos('<docZip', R.Corpo) > 0);
end;

procedure TDFeSimuladorAdminTests.Documentos_TipoDesconhecido_400;
var
  R: TDFeSimHttpResposta;
begin
  R := Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"RS","tipo":"xyz"}');
  AssertEquals(400, R.Status);
  AssertTrue(Pos('xyz', R.Corpo) > 0);
end;

procedure TDFeSimuladorAdminTests.Documentos_CnpjInvalido_400;
begin
  AssertEquals(400, Admin('POST', '/admin/documentos', '{"cnpj":"abc","uf":"RS"}').Status);
  AssertEquals(400, Admin('POST', '/admin/documentos', '{"cnpj":"11222333000181","uf":"R"}').Status);
  AssertEquals(400, Admin('POST', '/admin/documentos', '{"uf":"RS"}').Status);
end;

procedure TDFeSimuladorAdminTests.Documentos_QuantidadeForaDoLimite_400;
begin
  AssertEquals(400, Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"RS","quantidade":0}').Status);
  AssertEquals(400, Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"RS","quantidade":100000}').Status);
  AssertEquals(400, Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"RS","quantidade":"muitos"}').Status);
  AssertEquals(0, Length(FSim.Contas)); // nada foi publicado
end;

procedure TDFeSimuladorAdminTests.Documentos_Literal_Publica;
var
  R: TDFeSimHttpResposta;
begin
  R := Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"RS","schema":"resNFe_v1.01.xsd",' +
    '"xml":"<resNFe xmlns=\"http://www.portalfiscal.inf.br/nfe\"><chNFe>1</chNFe></resNFe>"}');
  AssertEquals(200, R.Status);
  AssertTrue(Pos('"publicados":1', R.Corpo) > 0);
  AssertEquals(1, FSim.Contas[0].Documentos);
end;

procedure TDFeSimuladorAdminTests.Documentos_LiteralSemXml_400;
begin
  AssertEquals(400, Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"RS","schema":"x"}').Status);
end;

procedure TDFeSimuladorAdminTests.Documentos_XNomeComAcento_ViaEscape;
var
  R: TDFeSimHttpResposta;
begin
  // É = E acentuado; & precisa sair escapado no XML
  R := Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"RS","xNome":"JOSÉ & FILHOS"}');
  AssertEquals(200, R.Status);
  R := Consultar;
  AssertEquals(200, R.Status);
  AssertTrue(Pos('<cStat>138</cStat>', R.Corpo) > 0);
end;

procedure TDFeSimuladorAdminTests.Documentos_TiposDeEvento;
begin
  AssertEquals(200, Admin('POST', '/admin/documentos',
    '{"cnpj":"' + CNPJ_A + '","uf":"RS","tipo":"resEvento","tpEvento":"110111","quantidade":2}').Status);
  AssertEquals(200, Admin('POST', '/admin/documentos',
    '{"cnpj":"' + CNPJ_A + '","uf":"RS","tipo":"procEventoNFe","tpEvento":"110110"}').Status);
  AssertEquals(3, FSim.Contas[0].Documentos);
end;

procedure TDFeSimuladorAdminTests.PularNsu_AvancaOMaximo;
var
  R: TDFeSimHttpResposta;
begin
  Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"RS"}');
  R := Admin('POST', '/admin/pular-nsu', '{"cnpj":"' + CNPJ_A + '","uf":"RS","quantidade":4}');
  AssertEquals(200, R.Status);
  AssertTrue(Pos('"nsuAtual":5', R.Corpo) > 0);
  AssertEquals(400, Admin('POST', '/admin/pular-nsu', '{"cnpj":"' + CNPJ_A + '","uf":"RS"}').Status);
end;

procedure TDFeSimuladorAdminTests.Falhas_Enfileira;
var
  R: TDFeSimHttpResposta;
begin
  R := Admin('POST', '/admin/falhas', '{"falha":"timeout","quantidade":2}');
  AssertEquals(200, R.Status);
  AssertTrue(Pos('"falhasPendentes":2', R.Corpo) > 0);
  AssertEquals(2, FSim.FalhasPendentes);
end;

procedure TDFeSimuladorAdminTests.Falhas_Lista;
begin
  AssertEquals(200, Admin('POST', '/admin/falhas', '{"falhas":["timeout","consumo-indevido"]}').Status);
  AssertEquals(2, FSim.FalhasPendentes);
end;

procedure TDFeSimuladorAdminTests.Falhas_Desconhecida_400_ENaoEnfileiraNada;
var
  R: TDFeSimHttpResposta;
begin
  R := Admin('POST', '/admin/falhas', '{"falhas":["timeout","explodir"]}');
  AssertEquals(400, R.Status);
  AssertTrue('lista as validas', Pos('consumo-indevido', R.Corpo) > 0);
  AssertEquals(0, FSim.FalhasPendentes); // nem a "timeout", que era valida
  AssertEquals(400, Admin('POST', '/admin/falhas', '{}').Status);
end;

procedure TDFeSimuladorAdminTests.Falhas_TimeoutViraHttp504;
begin
  Admin('POST', '/admin/falhas', '{"falha":"timeout"}');
  AssertEquals(504, Consultar.Status);
end;

procedure TDFeSimuladorAdminTests.Relogio_ReproduzOConsumoIndevidoESaiDeleSemEsperar;
var
  R: TDFeSimHttpResposta;
begin
  // 1a consulta sem novidade: 137 e o simulador abre o bloqueio de 1 h
  R := Consultar;
  AssertTrue('137', Pos('<cStat>137</cStat>', R.Corpo) > 0);
  // 2a, na hora: consumo indevido (656) -- o que "so' se reproduz esperando 1 h"
  R := Consultar;
  AssertTrue('656', Pos('<cStat>656</cStat>', R.Corpo) > 0);
  // avanca o relogio VIRTUAL em 1 h e 1 minuto: sem esperar
  R := Admin('POST', '/admin/relogio/avancar', '{"horas":1,"minutos":1}');
  AssertEquals(200, R.Status);
  AssertTrue(Pos('"deslocamentoSegundos":3660', R.Corpo) > 0);
  R := Consultar;
  AssertTrue('liberou: 137 de novo', Pos('<cStat>137</cStat>', R.Corpo) > 0);
end;

procedure TDFeSimuladorAdminTests.Relogio_Avancar_Invalido_400;
begin
  AssertEquals(400, Admin('POST', '/admin/relogio/avancar', '{}').Status);
  AssertEquals(400, Admin('POST', '/admin/relogio/avancar', '{"segundos":0}').Status);
  AssertEquals(400, Admin('POST', '/admin/relogio/avancar', '{"segundos":-5}').Status);
  AssertEquals(400, Admin('POST', '/admin/relogio/avancar', '{"horas":"muitas"}').Status);
end;

procedure TDFeSimuladorAdminTests.Relogio_Zerar;
var
  R: TDFeSimHttpResposta;
begin
  Admin('POST', '/admin/relogio/avancar', '{"segundos":100}');
  R := Admin('POST', '/admin/relogio/zerar');
  AssertEquals(200, R.Status);
  AssertTrue(Pos('"deslocamentoSegundos":0', R.Corpo) > 0);
  AssertTrue(Pos('"agora"', Admin('GET', '/admin/relogio').Corpo) > 0);
end;

procedure TDFeSimuladorAdminTests.Relogio_SemRelogio_501;
begin
  CriarServidor(nil);
  AssertEquals(501, Admin('POST', '/admin/relogio/avancar', '{"segundos":10}').Status);
  AssertEquals(501, Admin('POST', '/admin/relogio/zerar').Status);
  AssertEquals(200, Admin('GET', '/admin/relogio').Status); // ler o "agora" segue valendo
  AssertTrue(Pos('"deslocamentoSegundos":null', Admin('GET', '/admin/relogio').Corpo) > 0);
end;

procedure TDFeSimuladorAdminTests.Modo_PadraoLeniente_EAlterna;
begin
  AssertTrue(Pos('"estrito":false', Admin('GET', '/admin/modo').Corpo) > 0);
  AssertTrue(Pos('"estrito":true', Admin('POST', '/admin/modo', '{"estrito":true}').Corpo) > 0);
  AssertTrue(FServidor.Estrito);
  AssertTrue(Pos('"estrito":false', Admin('POST', '/admin/modo', '{"estrito":false}').Corpo) > 0);
  AssertFalse(FServidor.Estrito);
end;

procedure TDFeSimuladorAdminTests.Modo_SemCampo_400;
begin
  AssertEquals(400, Admin('POST', '/admin/modo', '{}').Status);
end;

procedure TDFeSimuladorAdminTests.Violacoes_GetEDelete;
var
  R: TDFeSimHttpResposta;
begin
  Admin('GET', '/admin/estado'); // cria o servidor
  AssertEquals('(nenhuma)', Admin('GET', '/admin/violacoes').Corpo);
  FServidor.Tratar('POST', CAMINHO_DIST, 'http://errada/acao', '', RequisicaoDistribuicao);
  R := Admin('GET', '/admin/violacoes');
  AssertTrue('registrou', Pos('SoapAction', R.Corpo) > 0);
  AssertTrue(Pos('"removidas":1', Admin('DELETE', '/admin/violacoes').Corpo) > 0);
  AssertEquals('(nenhuma)', Admin('GET', '/admin/violacoes').Corpo);
end;

procedure TDFeSimuladorAdminTests.UltimoEnvelope_DevolveOQueChegou;
var
  R: TDFeSimHttpResposta;
begin
  Admin('GET', '/admin/estado');
  Consultar;
  R := Admin('GET', '/admin/ultimo-envelope');
  AssertEquals(200, R.Status);
  AssertTrue(Pos('<distDFeInt', R.Corpo) > 0);
  AssertTrue(Pos('xml', R.ContentType) > 0);
end;

procedure TDFeSimuladorAdminTests.Cenario_Valido_Aplica;
var
  R: TDFeSimHttpResposta;
begin
  R := Admin('POST', '/admin/cenario', '[conta:a]'#10'Cnpj=' + CNPJ_A + #10'UF=RS'#10'ResNFe=2'#10'[simulador]'#10'Falhas=timeout');
  AssertEquals(200, R.Status);
  AssertTrue(Pos('"contas":1', R.Corpo) > 0);
  AssertTrue(Pos('"documentos":2', R.Corpo) > 0);
  AssertTrue(Pos('"falhas":1', R.Corpo) > 0);
end;

procedure TDFeSimuladorAdminTests.Cenario_Invalido_400_ENaoAplicaNada;
var
  R: TDFeSimHttpResposta;
begin
  R := Admin('POST', '/admin/cenario', '[conta:a]'#10'Cnpj=' + CNPJ_A + #10'UF=RS'#10'ResNFe=2'#10'[simulador]'#10'Falhas=explodir');
  AssertEquals(400, R.Status);
  AssertTrue(Pos('explodir', R.Corpo) > 0);
  AssertEquals(0, Length(FSim.Contas)); // a conta valida NAO foi aplicada
end;

procedure TDFeSimuladorAdminTests.Zerar_LimpaTudoInclusiveORelogio;
var
  R: TDFeSimHttpResposta;
begin
  Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"RS"}');
  Admin('POST', '/admin/falhas', '{"falha":"erro-http"}');
  Admin('POST', '/admin/relogio/avancar', '{"segundos":500}');
  FServidor.Tratar('POST', CAMINHO_DIST, 'http://errada/acao', '', RequisicaoDistribuicao); // violacao
  Admin('POST', '/admin/falhas', '{"falha":"erro-http"}');
  R := Admin('POST', '/admin/zerar');
  AssertEquals(200, R.Status);
  R := Admin('GET', '/admin/estado');
  AssertTrue(Pos('"contas":[]', R.Corpo) > 0);
  AssertTrue(Pos('"falhasPendentes":0', R.Corpo) > 0);
  AssertTrue(Pos('"violacoes":0', R.Corpo) > 0);
  AssertTrue(Pos('"deslocamentoSegundos":0', R.Corpo) > 0);
end;

procedure TDFeSimuladorAdminTests.JsonInvalido_400;
var
  R: TDFeSimHttpResposta;
begin
  R := Admin('POST', '/admin/documentos', '{"cnpj":');
  AssertEquals(400, R.Status);
  AssertTrue(Pos('JSON invalido', R.Corpo) > 0);
  AssertEquals(400, Admin('POST', '/admin/falhas', 'nao e json').Status);
end;

procedure TDFeSimuladorAdminTests.RotaDesconhecida_404;
begin
  AssertEquals(404, Admin('GET', '/admin/nada').Status);
end;

procedure TDFeSimuladorAdminTests.MetodoErrado_405;
begin
  AssertEquals(405, Admin('GET', '/admin/documentos').Status);
  AssertEquals(405, Admin('POST', '/admin/estado').Status);
  AssertEquals(405, Admin('PUT', '/admin/violacoes').Status);
end;

procedure TDFeSimuladorAdminTests.CaminhoComBarraFinalEQuery_Funciona;
begin
  AssertEquals(200, Admin('GET', '/admin/estado/').Status);
  AssertEquals(200, Admin('GET', '/ADMIN/Estado?x=1').Status);
end;

initialization
  RegisterTest(TDFeSimuladorNucleoFaseBTests);
  RegisterTest(TDFeSimuladorEstritoTests);
  RegisterTest(TDFeRelogioVirtualTests);
  RegisterTest(TDFeJsonPlanoTests);
  RegisterTest(TDFeCenarioAtomicoTests);
  RegisterTest(TDFeSimuladorAdminTests);

end.
