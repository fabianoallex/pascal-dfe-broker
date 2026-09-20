unit DFe.SimuladorAdminTests;

{ Espelho DELPHI de tests/Unit/fpc/DFe.SimuladorAdminTests.pas (mesmos casos,
  sintaxe DUnitX; os literais de texto nao-ASCII sao caracteres de verdade, nao
  bytes UTF-8 como no FPC). Fase B do simulador standalone (docs/simulador-standalone.md): as adicoes ao
  nucleo (Zerar, Contas, FalhasPendentes), o modo estrito do adaptador SOAP, o
  relogio virtual, o JSON plano, o cenario atomico e a API admin -- tudo sem
  HTTP (a API admin e' uma funcao metodo/caminho/corpo -> status/corpo). }

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes,
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
  [TestFixture]
  TDFeSimuladorNucleoFaseBTests = class
  private
    FRelogio: TDFeRelogioFake;
    FSim: TDFeSimuladorSefaz;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure Zerar_LimpaContasFalhasEContadores;
    [Test] procedure Zerar_PermiteRecomecar;
    [Test] procedure Contas_ListaSemCriarConta;
    [Test] procedure Contas_ReportaBloqueio;
    [Test] procedure FalhasPendentes_ContaEConsome;
    [Test] procedure AgoraSimulado_UsaORelogioInjetado;
  end;

  [TestFixture]
  TDFeSimuladorEstritoTests = class
  private
    FSim: TDFeSimuladorSefaz;
    FTransmissor: TDFeSimuladorTransmissor;
    FIntf: IDFeTransmissor; // dono do ciclo de vida do transmissor
    function Requisicao: string;
    function Transmitir(const ASoapAction: string): TDFeRespostaTransmissao;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure Leniente_EOPadrao;
    [Test] procedure Leniente_ViolacaoRegistraEAtende;
    [Test] procedure Estrito_ViolacaoRecusaComHttp400ENaoTocaOEstado;
    [Test] procedure Estrito_RequisicaoValida_Atende;
    [Test] procedure LimparViolacoes_EsquecePeloMenosAsRegistradas;
  end;

  [TestFixture]
  TDFeRelogioVirtualTests = class
  public
    [Test] procedure Comeca_SemDeslocamento;
    [Test] procedure Avancar_SomaESeReflete;
    [Test] procedure Avancar_NaoPositivo_NaoFazNada;
    [Test] procedure Zerar_VoltaAZero;
  end;

  [TestFixture]
  TDFeJsonPlanoTests = class
  private
    function Ler(const ATexto: string): TDFeJsonPlano;
    function Invalido(const ATexto: string): string;
  public
    [Test] procedure ObjetoSimples_TextoNumeroBooleano;
    [Test] procedure ChavesNaoDiferenciamMaiusculas;
    [Test] procedure Ausente_UsaPadrao;
    [Test] procedure Null_EquivaleAAusente;
    [Test] procedure Lista_DeTextos;
    [Test] procedure Lista_Vazia;
    [Test] procedure Escalar_ViraListaDeUm;
    [Test] procedure Vazio_EObjetoVazio;
    [Test] procedure Escapes_Basicos;
    [Test] procedure EscapeUnicode_ViraCaractereNativo;
    [Test] procedure ParSubstituto_ViraUmPontoDeCodigo;
    [Test] procedure Acento_PassaComoEsta;
    [Test] procedure Aninhado_Recusa;
    [Test] procedure Malformados_ViramErroComPosicao;
    [Test] procedure Inteiro_RecusaFracaoETexto;
    [Test] procedure JsonEscape_EscapaAspasBarraEControle;
  end;

  [TestFixture]
  TDFeCenarioAtomicoTests = class
  private
    FSim: TDFeSimuladorSefaz;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure DeTexto_Aplica;
    [Test] procedure Invalido_NaoAplicaNada;
    [Test] procedure Acumulativo_AplicaPorCimaDoEstado;
  end;

  [TestFixture]
  TDFeSimuladorAdminTests = class
  private
    FRelogio: TDFeRelogioVirtual;
    FSim: TDFeSimuladorSefaz;
    FServidor: TDFeSimuladorServidor;
    function Admin(const AMetodo, ACaminho: string; const ACorpo: string = ''): TDFeSimHttpResposta;
    function Consultar: TDFeSimHttpResposta;
    function ComRelogio: Boolean;
    procedure CriarServidor(const ARelogio: TDFeRelogioVirtual);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure Estado_Inicial_Vazio;
    [Test] procedure Documentos_Sintetico_PublicaEDevolveNsu;
    [Test] procedure Documentos_DepoisDeConsultar_CStat138;
    [Test] procedure Documentos_TipoDesconhecido_400;
    [Test] procedure Documentos_CnpjInvalido_400;
    [Test] procedure Documentos_QuantidadeForaDoLimite_400;
    [Test] procedure Documentos_Literal_Publica;
    [Test] procedure Documentos_LiteralSemXml_400;
    [Test] procedure Documentos_XNomeComAcento_ViaEscape;
    [Test] procedure Documentos_TiposDeEvento;
    [Test] procedure PularNsu_AvancaOMaximo;
    [Test] procedure Falhas_Enfileira;
    [Test] procedure Falhas_Lista;
    [Test] procedure Falhas_Desconhecida_400_ENaoEnfileiraNada;
    [Test] procedure Falhas_TimeoutViraHttp504;
    [Test] procedure Relogio_ReproduzOConsumoIndevidoESaiDeleSemEsperar;
    [Test] procedure Relogio_Avancar_Invalido_400;
    [Test] procedure Relogio_Zerar;
    [Test] procedure Relogio_SemRelogio_501;
    [Test] procedure Modo_PadraoLeniente_EAlterna;
    [Test] procedure Modo_SemCampo_400;
    [Test] procedure Violacoes_GetEDelete;
    [Test] procedure UltimoEnvelope_DevolveOQueChegou;
    [Test] procedure Cenario_Valido_Aplica;
    [Test] procedure Cenario_Invalido_400_ENaoAplicaNada;
    [Test] procedure Zerar_LimpaTudoInclusiveORelogio;
    [Test] procedure JsonInvalido_400;
    [Test] procedure RotaDesconhecida_404;
    [Test] procedure MetodoErrado_405;
    [Test] procedure CaminhoComBarraFinalEQuery_Funciona;
  end;

implementation

const
  BARRA = '\'; // evita escrever a sequencia de escape no fonte
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

procedure TDFeSimuladorNucleoFaseBTests.Setup;
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
  Assert.AreEqual(0, Integer(Length(FSim.Contas)));
  Assert.AreEqual(0, FSim.FalhasPendentes);
  Assert.AreEqual(0, FSim.TotalConsultas);
  Assert.AreEqual(0, FSim.EventosRegistrados);
end;

procedure TDFeSimuladorNucleoFaseBTests.Zerar_PermiteRecomecar;
var
  R: TDFeRespostaSimulada;
begin
  FSim.PublicarDocumento(CNPJ_A, 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  FSim.Consultar(CNPJ_A, 'RS', 0); // 138: abre o bloqueio? (so' 137 abre) -- de qualquer modo zera
  FSim.Zerar;
  R := FSim.Consultar(CNPJ_A, 'RS', 0);
  Assert.AreEqual(137, R.Lote.CStat); // conta nova, sem documentos e sem bloqueio
end;

procedure TDFeSimuladorNucleoFaseBTests.Contas_ListaSemCriarConta;
var
  L: TDFeSimContaResumoArray;
begin
  Assert.AreEqual(0, Integer(Length(FSim.Contas)));
  FSim.PublicarDocumento(CNPJ_A, 'rs', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  FSim.PublicarDocumento(CNPJ_A, 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 2)));
  FSim.PularNSU('12345678000199', 'SP', 5);
  L := FSim.Contas;
  Assert.AreEqual(2, Integer(Length(L)));
  Assert.AreEqual(CNPJ_A, L[0].Cnpj);
  Assert.AreEqual('RS', L[0].UF);
  Assert.AreEqual(Int64(2), L[0].NsuAtual);
  Assert.AreEqual(2, L[0].Documentos);
  Assert.AreEqual('SP', L[1].UF);
  Assert.AreEqual(Int64(5), L[1].NsuAtual);
  Assert.AreEqual(0, L[1].Documentos);
  FSim.Contas; // ler nao cria
  Assert.AreEqual(2, Integer(Length(FSim.Contas)));
end;

procedure TDFeSimuladorNucleoFaseBTests.Contas_ReportaBloqueio;
var
  L: TDFeSimContaResumoArray;
begin
  FSim.PublicarDocumento(CNPJ_A, 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  L := FSim.Contas;
  Assert.IsTrue(L[0].BloqueadoAte = 0, 'livre');
  FSim.Consultar(CNPJ_A, 'RS', 1); // sem novidade (ja' viu o 1): 137, abre o bloqueio de 1 h
  L := FSim.Contas;
  Assert.IsTrue(L[0].BloqueadoAte > FRelogio.Agora, 'bloqueada ate 1 h depois');
end;

procedure TDFeSimuladorNucleoFaseBTests.FalhasPendentes_ContaEConsome;
begin
  Assert.AreEqual(0, FSim.FalhasPendentes);
  FSim.EnfileirarFalha(fsTimeout);
  FSim.EnfileirarFalha(fsErroHttp);
  Assert.AreEqual(2, FSim.FalhasPendentes);
  FSim.Consultar(CNPJ_A, 'RS', 0);
  Assert.AreEqual(1, FSim.FalhasPendentes);
end;

procedure TDFeSimuladorNucleoFaseBTests.AgoraSimulado_UsaORelogioInjetado;
begin
  Assert.IsTrue(FRelogio.Agora = FSim.AgoraSimulado);
  FRelogio.Agora := FRelogio.Agora + 1;
  Assert.IsTrue(FRelogio.Agora = FSim.AgoraSimulado);
end;

{ ---------------- estrito ---------------- }

procedure TDFeSimuladorEstritoTests.Setup;
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
  Assert.IsFalse(FTransmissor.Estrito);
end;

procedure TDFeSimuladorEstritoTests.Leniente_ViolacaoRegistraEAtende;
var
  R: TDFeRespostaTransmissao;
begin
  R := Transmitir('http://errada/acao');
  Assert.AreEqual(200, R.HTTPResultCode);
  Assert.AreEqual(1, FTransmissor.QuantidadeViolacoes);
  Assert.AreEqual(1, FSim.TotalConsultas); // atendeu de verdade
end;

procedure TDFeSimuladorEstritoTests.Estrito_ViolacaoRecusaComHttp400ENaoTocaOEstado;
var
  R: TDFeRespostaTransmissao;
begin
  FTransmissor.Estrito := True;
  R := Transmitir('http://errada/acao');
  Assert.AreEqual(400, R.HTTPResultCode);
  Assert.AreEqual(0, R.InternalErrorCode);
  Assert.IsTrue(Pos('SoapAction', R.Texto) > 0, 'a recusa diz o motivo');
  Assert.IsTrue(Pos('estrito', R.Texto) > 0, 'e diz que e o modo estrito');
  Assert.AreEqual(1, FTransmissor.QuantidadeViolacoes);
  // o ponto: a requisicao recusada NAO consumiu NSU nem abriu bloqueio
  Assert.AreEqual(0, FSim.TotalConsultas);
  Assert.AreEqual(0, Integer(Length(FSim.Contas)));
end;

procedure TDFeSimuladorEstritoTests.Estrito_RequisicaoValida_Atende;
var
  R: TDFeRespostaTransmissao;
begin
  FTransmissor.Estrito := True;
  R := Transmitir(SOAP_DIST);
  Assert.AreEqual(200, R.HTTPResultCode);
  Assert.AreEqual(0, FTransmissor.QuantidadeViolacoes);
  Assert.AreEqual(1, FSim.TotalConsultas);
end;

procedure TDFeSimuladorEstritoTests.LimparViolacoes_EsquecePeloMenosAsRegistradas;
begin
  Transmitir('http://errada/acao');
  Assert.AreEqual(1, FTransmissor.QuantidadeViolacoes);
  FTransmissor.LimparViolacoes;
  Assert.AreEqual(0, FTransmissor.QuantidadeViolacoes);
  Assert.AreEqual('', FTransmissor.TodasViolacoes);
  Assert.AreEqual(1, FTransmissor.Requisicoes); // o contador de requisicoes fica
end;

{ ---------------- relogio ---------------- }

procedure TDFeRelogioVirtualTests.Comeca_SemDeslocamento;
var
  R: TDFeRelogioVirtual;
begin
  R := TDFeRelogioVirtual.Create;
  try
    Assert.AreEqual(Int64(0), R.DeslocamentoSegundos);
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
    Assert.AreEqual(Int64(3660), R.DeslocamentoSegundos);
    // Agora ~ Now + 3660 s (tolerancia de 5 s para a execucao do teste)
    Assert.IsTrue((LDepois - LAntes) * 86400 > 3655, 'avancou ~3660 s');
    Assert.IsTrue((LDepois - LAntes) * 86400 < 3670, 'e nao muito mais');
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
    Assert.AreEqual(Int64(0), R.DeslocamentoSegundos);
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
    Assert.AreEqual(Int64(0), R.DeslocamentoSegundos);
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
    Assert.Fail('JSON deveria ser valido: ' + LErro);
end;

function TDFeJsonPlanoTests.Invalido(const ATexto: string): string;
var
  LObj: TDFeJsonPlano;
begin
  if LerJsonPlano(ATexto, LObj, Result) then
  begin
    LObj.Free;
    Assert.Fail('JSON deveria ser recusado: ' + ATexto);
  end;
  Assert.IsTrue(LObj = nil, 'sem objeto quando falha');
end;

procedure TDFeJsonPlanoTests.ObjetoSimples_TextoNumeroBooleano;
var
  J: TDFeJsonPlano;
begin
  J := Ler('{"cnpj":"11222333000181","quantidade":3,"estrito":true,"nao":false,"neg":-7}');
  try
    Assert.AreEqual('11222333000181', J.Texto('cnpj'));
    Assert.AreEqual(3, Integer(J.Inteiro('quantidade', 0)));
    Assert.AreEqual(-7, Integer(J.Inteiro('neg', 0)));
    Assert.IsTrue(J.Booleano('estrito', False));
    Assert.IsFalse(J.Booleano('nao', True));
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
    Assert.AreEqual('1', J.Texto('cnpj'));
    Assert.IsTrue(J.Tem('Cnpj'));
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
    Assert.AreEqual('pad', J.Texto('x', 'pad'));
    Assert.AreEqual(9, Integer(J.Inteiro('x', 9)));
    Assert.IsTrue(J.Booleano('x', True));
    Assert.IsFalse(J.Tem('x'));
    Assert.IsFalse(J.EInteiro('x'));
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
    Assert.IsFalse(J.Tem('a'));
    Assert.AreEqual('null', J.Texto('b')); // a STRING "null" nao e' o literal
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
    Assert.AreEqual(3, Integer(Length(L)));
    Assert.AreEqual('timeout', L[0]);
    Assert.AreEqual('consumo-indevido', L[1]);
    Assert.AreEqual('a,b', L[2]); // virgula dentro do item nao separa
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
    Assert.AreEqual(0, Integer(Length(J.Lista('f'))));
    Assert.IsTrue(J.Tem('f'));
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
    Assert.AreEqual(1, Integer(Length(L)));
    Assert.AreEqual('timeout', L[0]);
    Assert.AreEqual(0, Integer(Length(J.Lista('ausente'))));
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
    Assert.IsFalse(J.Tem('x'));
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
    Assert.AreEqual('a"b\c/d' + #10 + 'e' + #9 + 'f', J.Texto('t'));
  finally
    J.Free;
  end;
end;

procedure TDFeJsonPlanoTests.EscapeUnicode_ViraCaractereNativo;
var
  J: TDFeJsonPlano;
begin
  // a-til (U+00E3) escrito na entrada como escape, montado com BARRA para o fonte ficar ASCII.
  J := Ler('{"t":"n' + BARRA + 'u00e3o"}');
  try
    Assert.AreEqual('n' + #$00E3 + 'o', J.Texto('t'));
  finally
    J.Free;
  end;
end;

procedure TDFeJsonPlanoTests.ParSubstituto_ViraUmPontoDeCodigo;
var
  J: TDFeJsonPlano;
begin
  // U+1F600 = par substituto D83D DE00 (montado com BARRA; o fonte fica ASCII).
  J := Ler('{"t":"' + BARRA + 'uD83D' + BARRA + 'uDE00"}');
  try
    Assert.AreEqual(#$D83D#$DE00, J.Texto('t'));
  finally
    J.Free;
  end;
end;

procedure TDFeJsonPlanoTests.Acento_PassaComoEsta;
var
  J: TDFeJsonPlano;
  LTexto: string;
begin
  LTexto := 'JOS' + #$00C9 + ' A' + #$00C7 + 'AI';
  J := Ler('{"xNome":"' + LTexto + '"}');
  try
    Assert.AreEqual(LTexto, J.Texto('xNome'));
  finally
    J.Free;
  end;
end;

procedure TDFeJsonPlanoTests.Aninhado_Recusa;
begin
  Assert.IsTrue(Pos('aninhado', Invalido('{"a":{"b":1}}')) > 0);
  Assert.IsTrue(Pos('aninhada', Invalido('{"a":[[1]]}')) > 0);
end;

procedure TDFeJsonPlanoTests.Malformados_ViramErroComPosicao;
begin
  Assert.IsTrue(Pos('posicao', Invalido('{"a":1')) > 0);       // sem fechar
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
    Assert.IsFalse(J.EInteiro('a'), 'fracao nao e inteiro');
    Assert.IsTrue(J.EInteiro('b'), '"7" (string) converte');
    Assert.IsFalse(J.EInteiro('c'), 'expoente nao e inteiro');
    Assert.IsTrue(J.EInteiro('d'));
    Assert.AreEqual(-1, Integer(J.Inteiro('a', -1)));
  finally
    J.Free;
  end;
end;

procedure TDFeJsonPlanoTests.JsonEscape_EscapaAspasBarraEControle;
begin
  Assert.AreEqual('a\"b\\c\nd\u0001', JsonEscape('a"b\c' + #10 + 'd' + #1));
  Assert.AreEqual('"x"', JsonTexto('x'));
  Assert.AreEqual('', JsonEscape(''));
end;

{ ---------------- cenario atomico ---------------- }

procedure TDFeCenarioAtomicoTests.Setup;
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
  Assert.AreEqual(1, R.Contas);
  Assert.AreEqual(2, R.Documentos);
  Assert.AreEqual(1, R.Falhas);
  Assert.AreEqual(1, FSim.FalhasPendentes);
  Assert.AreEqual(1, Integer(Length(FSim.Contas)));
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
  Assert.IsTrue(LLevantou);
  Assert.AreEqual(0, Integer(Length(FSim.Contas)));
  Assert.AreEqual(0, FSim.FalhasPendentes);
end;

procedure TDFeCenarioAtomicoTests.Acumulativo_AplicaPorCimaDoEstado;
begin
  CarregarCenarioDeTexto('[conta:a]' + #10 + 'Cnpj=11222333000181' + #10 + 'UF=RS' + #10 + 'ResNFe=1', FSim);
  CarregarCenarioDeTexto('[conta:a]' + #10 + 'Cnpj=11222333000181' + #10 + 'UF=RS' + #10 + 'ResNFe=1', FSim);
  Assert.AreEqual(2, FSim.Contas[0].Documentos);
end;

{ ---------------- API admin ---------------- }

procedure TDFeSimuladorAdminTests.Setup;
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
  Assert.AreEqual(200, R.Status);
  Assert.IsTrue(Pos('json', R.ContentType) > 0);
  Assert.IsTrue(Pos('"contas":[]', R.Corpo) > 0, 'sem contas');
  Assert.IsTrue(Pos('"estrito":false', R.Corpo) > 0, 'leniente');
  Assert.IsTrue(Pos('"falhasPendentes":0', R.Corpo) > 0);
  Assert.IsTrue(Pos('"deslocamentoSegundos":0', R.Corpo) > 0);
end;

procedure TDFeSimuladorAdminTests.Documentos_Sintetico_PublicaEDevolveNsu;
var
  R: TDFeSimHttpResposta;
begin
  R := Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"rs","quantidade":3}');
  Assert.AreEqual(200, R.Status);
  Assert.IsTrue(Pos('"publicados":3', R.Corpo) > 0);
  Assert.IsTrue(Pos('"ultimoNsu":3', R.Corpo) > 0);
  R := Admin('GET', '/admin/estado');
  Assert.IsTrue(Pos('"documentos":3', R.Corpo) > 0, 'a conta aparece');
  Assert.IsTrue(Pos('"uf":"RS"', R.Corpo) > 0);
end;

procedure TDFeSimuladorAdminTests.Documentos_DepoisDeConsultar_CStat138;
var
  R: TDFeSimHttpResposta;
begin
  Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"RS","tipo":"procNFe","quantidade":2}');
  R := Consultar;
  Assert.AreEqual(200, R.Status);
  Assert.IsTrue(Pos('<cStat>138</cStat>', R.Corpo) > 0, 'cStat 138');
  Assert.IsTrue(Pos('<docZip', R.Corpo) > 0);
end;

procedure TDFeSimuladorAdminTests.Documentos_TipoDesconhecido_400;
var
  R: TDFeSimHttpResposta;
begin
  R := Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"RS","tipo":"xyz"}');
  Assert.AreEqual(400, R.Status);
  Assert.IsTrue(Pos('xyz', R.Corpo) > 0);
end;

procedure TDFeSimuladorAdminTests.Documentos_CnpjInvalido_400;
begin
  Assert.AreEqual(400, Admin('POST', '/admin/documentos', '{"cnpj":"abc","uf":"RS"}').Status);
  Assert.AreEqual(400, Admin('POST', '/admin/documentos', '{"cnpj":"11222333000181","uf":"R"}').Status);
  Assert.AreEqual(400, Admin('POST', '/admin/documentos', '{"uf":"RS"}').Status);
end;

procedure TDFeSimuladorAdminTests.Documentos_QuantidadeForaDoLimite_400;
begin
  Assert.AreEqual(400, Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"RS","quantidade":0}').Status);
  Assert.AreEqual(400, Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"RS","quantidade":100000}').Status);
  Assert.AreEqual(400, Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"RS","quantidade":"muitos"}').Status);
  Assert.AreEqual(0, Integer(Length(FSim.Contas))); // nada foi publicado
end;

procedure TDFeSimuladorAdminTests.Documentos_Literal_Publica;
var
  R: TDFeSimHttpResposta;
begin
  R := Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"RS","schema":"resNFe_v1.01.xsd",' +
    '"xml":"<resNFe xmlns=\"http://www.portalfiscal.inf.br/nfe\"><chNFe>1</chNFe></resNFe>"}');
  Assert.AreEqual(200, R.Status);
  Assert.IsTrue(Pos('"publicados":1', R.Corpo) > 0);
  Assert.AreEqual(1, FSim.Contas[0].Documentos);
end;

procedure TDFeSimuladorAdminTests.Documentos_LiteralSemXml_400;
begin
  Assert.AreEqual(400, Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"RS","schema":"x"}').Status);
end;

procedure TDFeSimuladorAdminTests.Documentos_XNomeComAcento_ViaEscape;
var
  R: TDFeSimHttpResposta;
begin
  // u00c9 = E acentuado (escape montado com BARRA); & precisa sair escapado no XML
  R := Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"RS","xNome":"JOS' + BARRA + 'u00c9 & FILHOS"}');
  Assert.AreEqual(200, R.Status);
  R := Consultar;
  Assert.AreEqual(200, R.Status);
  Assert.IsTrue(Pos('<cStat>138</cStat>', R.Corpo) > 0);
end;

procedure TDFeSimuladorAdminTests.Documentos_TiposDeEvento;
begin
  Assert.AreEqual(200, Admin('POST', '/admin/documentos',
    '{"cnpj":"' + CNPJ_A + '","uf":"RS","tipo":"resEvento","tpEvento":"110111","quantidade":2}').Status);
  Assert.AreEqual(200, Admin('POST', '/admin/documentos',
    '{"cnpj":"' + CNPJ_A + '","uf":"RS","tipo":"procEventoNFe","tpEvento":"110110"}').Status);
  Assert.AreEqual(3, FSim.Contas[0].Documentos);
end;

procedure TDFeSimuladorAdminTests.PularNsu_AvancaOMaximo;
var
  R: TDFeSimHttpResposta;
begin
  Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_A + '","uf":"RS"}');
  R := Admin('POST', '/admin/pular-nsu', '{"cnpj":"' + CNPJ_A + '","uf":"RS","quantidade":4}');
  Assert.AreEqual(200, R.Status);
  Assert.IsTrue(Pos('"nsuAtual":5', R.Corpo) > 0);
  Assert.AreEqual(400, Admin('POST', '/admin/pular-nsu', '{"cnpj":"' + CNPJ_A + '","uf":"RS"}').Status);
end;

procedure TDFeSimuladorAdminTests.Falhas_Enfileira;
var
  R: TDFeSimHttpResposta;
begin
  R := Admin('POST', '/admin/falhas', '{"falha":"timeout","quantidade":2}');
  Assert.AreEqual(200, R.Status);
  Assert.IsTrue(Pos('"falhasPendentes":2', R.Corpo) > 0);
  Assert.AreEqual(2, FSim.FalhasPendentes);
end;

procedure TDFeSimuladorAdminTests.Falhas_Lista;
begin
  Assert.AreEqual(200, Admin('POST', '/admin/falhas', '{"falhas":["timeout","consumo-indevido"]}').Status);
  Assert.AreEqual(2, FSim.FalhasPendentes);
end;

procedure TDFeSimuladorAdminTests.Falhas_Desconhecida_400_ENaoEnfileiraNada;
var
  R: TDFeSimHttpResposta;
begin
  R := Admin('POST', '/admin/falhas', '{"falhas":["timeout","explodir"]}');
  Assert.AreEqual(400, R.Status);
  Assert.IsTrue(Pos('consumo-indevido', R.Corpo) > 0, 'lista as validas');
  Assert.AreEqual(0, FSim.FalhasPendentes); // nem a "timeout", que era valida
  Assert.AreEqual(400, Admin('POST', '/admin/falhas', '{}').Status);
end;

procedure TDFeSimuladorAdminTests.Falhas_TimeoutViraHttp504;
begin
  Admin('POST', '/admin/falhas', '{"falha":"timeout"}');
  Assert.AreEqual(504, Consultar.Status);
end;

procedure TDFeSimuladorAdminTests.Relogio_ReproduzOConsumoIndevidoESaiDeleSemEsperar;
var
  R: TDFeSimHttpResposta;
begin
  // 1a consulta sem novidade: 137 e o simulador abre o bloqueio de 1 h
  R := Consultar;
  Assert.IsTrue(Pos('<cStat>137</cStat>', R.Corpo) > 0, '137');
  // 2a, na hora: consumo indevido (656) -- o que "so' se reproduz esperando 1 h"
  R := Consultar;
  Assert.IsTrue(Pos('<cStat>656</cStat>', R.Corpo) > 0, '656');
  // avanca o relogio VIRTUAL em 1 h e 1 minuto: sem esperar
  R := Admin('POST', '/admin/relogio/avancar', '{"horas":1,"minutos":1}');
  Assert.AreEqual(200, R.Status);
  Assert.IsTrue(Pos('"deslocamentoSegundos":3660', R.Corpo) > 0);
  R := Consultar;
  Assert.IsTrue(Pos('<cStat>137</cStat>', R.Corpo) > 0, 'liberou: 137 de novo');
end;

procedure TDFeSimuladorAdminTests.Relogio_Avancar_Invalido_400;
begin
  Assert.AreEqual(400, Admin('POST', '/admin/relogio/avancar', '{}').Status);
  Assert.AreEqual(400, Admin('POST', '/admin/relogio/avancar', '{"segundos":0}').Status);
  Assert.AreEqual(400, Admin('POST', '/admin/relogio/avancar', '{"segundos":-5}').Status);
  Assert.AreEqual(400, Admin('POST', '/admin/relogio/avancar', '{"horas":"muitas"}').Status);
end;

procedure TDFeSimuladorAdminTests.Relogio_Zerar;
var
  R: TDFeSimHttpResposta;
begin
  Admin('POST', '/admin/relogio/avancar', '{"segundos":100}');
  R := Admin('POST', '/admin/relogio/zerar');
  Assert.AreEqual(200, R.Status);
  Assert.IsTrue(Pos('"deslocamentoSegundos":0', R.Corpo) > 0);
  Assert.IsTrue(Pos('"agora"', Admin('GET', '/admin/relogio').Corpo) > 0);
end;

procedure TDFeSimuladorAdminTests.Relogio_SemRelogio_501;
begin
  CriarServidor(nil);
  Assert.AreEqual(501, Admin('POST', '/admin/relogio/avancar', '{"segundos":10}').Status);
  Assert.AreEqual(501, Admin('POST', '/admin/relogio/zerar').Status);
  Assert.AreEqual(200, Admin('GET', '/admin/relogio').Status); // ler o "agora" segue valendo
  Assert.IsTrue(Pos('"deslocamentoSegundos":null', Admin('GET', '/admin/relogio').Corpo) > 0);
end;

procedure TDFeSimuladorAdminTests.Modo_PadraoLeniente_EAlterna;
begin
  Assert.IsTrue(Pos('"estrito":false', Admin('GET', '/admin/modo').Corpo) > 0);
  Assert.IsTrue(Pos('"estrito":true', Admin('POST', '/admin/modo', '{"estrito":true}').Corpo) > 0);
  Assert.IsTrue(FServidor.Estrito);
  Assert.IsTrue(Pos('"estrito":false', Admin('POST', '/admin/modo', '{"estrito":false}').Corpo) > 0);
  Assert.IsFalse(FServidor.Estrito);
end;

procedure TDFeSimuladorAdminTests.Modo_SemCampo_400;
begin
  Assert.AreEqual(400, Admin('POST', '/admin/modo', '{}').Status);
end;

procedure TDFeSimuladorAdminTests.Violacoes_GetEDelete;
var
  R: TDFeSimHttpResposta;
begin
  Admin('GET', '/admin/estado'); // cria o servidor
  Assert.AreEqual('(nenhuma)', Admin('GET', '/admin/violacoes').Corpo);
  FServidor.Tratar('POST', CAMINHO_DIST, 'http://errada/acao', '', RequisicaoDistribuicao);
  R := Admin('GET', '/admin/violacoes');
  Assert.IsTrue(Pos('SoapAction', R.Corpo) > 0, 'registrou');
  Assert.IsTrue(Pos('"removidas":1', Admin('DELETE', '/admin/violacoes').Corpo) > 0);
  Assert.AreEqual('(nenhuma)', Admin('GET', '/admin/violacoes').Corpo);
end;

procedure TDFeSimuladorAdminTests.UltimoEnvelope_DevolveOQueChegou;
var
  R: TDFeSimHttpResposta;
begin
  Admin('GET', '/admin/estado');
  Consultar;
  R := Admin('GET', '/admin/ultimo-envelope');
  Assert.AreEqual(200, R.Status);
  Assert.IsTrue(Pos('<distDFeInt', R.Corpo) > 0);
  Assert.IsTrue(Pos('xml', R.ContentType) > 0);
end;

procedure TDFeSimuladorAdminTests.Cenario_Valido_Aplica;
var
  R: TDFeSimHttpResposta;
begin
  R := Admin('POST', '/admin/cenario', '[conta:a]'#10'Cnpj=' + CNPJ_A + #10'UF=RS'#10'ResNFe=2'#10'[simulador]'#10'Falhas=timeout');
  Assert.AreEqual(200, R.Status);
  Assert.IsTrue(Pos('"contas":1', R.Corpo) > 0);
  Assert.IsTrue(Pos('"documentos":2', R.Corpo) > 0);
  Assert.IsTrue(Pos('"falhas":1', R.Corpo) > 0);
end;

procedure TDFeSimuladorAdminTests.Cenario_Invalido_400_ENaoAplicaNada;
var
  R: TDFeSimHttpResposta;
begin
  R := Admin('POST', '/admin/cenario', '[conta:a]'#10'Cnpj=' + CNPJ_A + #10'UF=RS'#10'ResNFe=2'#10'[simulador]'#10'Falhas=explodir');
  Assert.AreEqual(400, R.Status);
  Assert.IsTrue(Pos('explodir', R.Corpo) > 0);
  Assert.AreEqual(0, Integer(Length(FSim.Contas))); // a conta valida NAO foi aplicada
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
  Assert.AreEqual(200, R.Status);
  R := Admin('GET', '/admin/estado');
  Assert.IsTrue(Pos('"contas":[]', R.Corpo) > 0);
  Assert.IsTrue(Pos('"falhasPendentes":0', R.Corpo) > 0);
  Assert.IsTrue(Pos('"violacoes":0', R.Corpo) > 0);
  Assert.IsTrue(Pos('"deslocamentoSegundos":0', R.Corpo) > 0);
end;

procedure TDFeSimuladorAdminTests.JsonInvalido_400;
var
  R: TDFeSimHttpResposta;
begin
  R := Admin('POST', '/admin/documentos', '{"cnpj":');
  Assert.AreEqual(400, R.Status);
  Assert.IsTrue(Pos('JSON invalido', R.Corpo) > 0);
  Assert.AreEqual(400, Admin('POST', '/admin/falhas', 'nao e json').Status);
end;

procedure TDFeSimuladorAdminTests.RotaDesconhecida_404;
begin
  Assert.AreEqual(404, Admin('GET', '/admin/nada').Status);
end;

procedure TDFeSimuladorAdminTests.MetodoErrado_405;
begin
  Assert.AreEqual(405, Admin('GET', '/admin/documentos').Status);
  Assert.AreEqual(405, Admin('POST', '/admin/estado').Status);
  Assert.AreEqual(405, Admin('PUT', '/admin/violacoes').Status);
end;

procedure TDFeSimuladorAdminTests.CaminhoComBarraFinalEQuery_Funciona;
begin
  Assert.AreEqual(200, Admin('GET', '/admin/estado/').Status);
  Assert.AreEqual(200, Admin('GET', '/ADMIN/Estado?x=1').Status);
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeSimuladorNucleoFaseBTests);
  TDUnitX.RegisterTestFixture(TDFeSimuladorEstritoTests);
  TDUnitX.RegisterTestFixture(TDFeRelogioVirtualTests);
  TDUnitX.RegisterTestFixture(TDFeJsonPlanoTests);
  TDUnitX.RegisterTestFixture(TDFeCenarioAtomicoTests);
  TDUnitX.RegisterTestFixture(TDFeSimuladorAdminTests);

end.
