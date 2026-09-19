unit DFe.ManifestacaoTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  DFe.Types,
  DFe.Errors,
  DFe.Provider,
  DFe.Publicador,
  DFe.Orquestrador,
  DFe.Manifestacao,
  DFe.XmlTexto,
  DFe.TestDoubles;

type
  [TestFixture]
  TDFeManifestacaoTests = class
  private
    FOrquestrador: TDFeOrquestrador;
    FPublicador: TDFePublicadorFake;
    function MontarPayload(const ALinhas: array of string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure InterpretarComando_ComandoValido_PreencheCampos;
    [Test] procedure InterpretarComando_SemAlias_Levanta;
    [Test] procedure InterpretarComando_SemChaveAcesso_Levanta;
    [Test] procedure InterpretarComando_SemTipoEvento_Levanta;
    [Test] procedure InterpretarComando_DesconhecimentoSemJustificativa_NaoLevanta;
    [Test] procedure InterpretarComando_JustificativaForaDeOperacaoNaoRealizada_EDescartada;
    [Test] procedure InterpretarComando_OperacaoNaoRealizadaSemJustificativa_Levanta;
    [Test] procedure InterpretarComando_ConfirmacaoSemJustificativa_NaoLevanta;
    [Test] procedure InterpretarComando_TipoEventoDesconhecido_Levanta;
    [Test] procedure InterpretarComando_ChaveAcessoFora44Digitos_Levanta;
    [Test] procedure InterpretarComando_JustificativaCurta_Levanta;
    [Test] procedure InterpretarComando_JustificativaValida_NaoLevanta;
    [Test] procedure InterpretarComando_JustificativaAcentuada_ContaCaracteresNaoBytes;
    [Test] procedure InterpretarComando_JustificativaComAspasCurvas_Levanta;
    [Test] procedure InterpretarComando_JustificativaComQuebraDeLinha_Levanta;
    [Test] procedure InterpretarComando_JustificativaComEspacosNasPontas_EAparada;
    [Test] procedure CStatEventoRegistrado_135_136_155_Registrado;
    [Test] procedure CStatEventoRegistrado_RejeicoesELote_NaoRegistrado;

    [Test] procedure ProcessarComando_AliasDesconhecido_RegistraErroNaoPublica;
    [Test] procedure ProcessarComando_ClientSemManifestador_RegistraErroNaoPublica;
    [Test] procedure ProcessarComando_Sucesso_PublicaEventoDevolvido;
    [Test] procedure ProcessarComando_CertificadoInvalido_RegistraErroNaoPropaga;
    [Test] procedure ProcessarComando_ComunicacaoFalhou_RegistraErroNaoPropaga;
    [Test] procedure ProcessarComando_RespostaInvalida_RegistraErroNaoPropaga;
    [Test] procedure ProcessarComando_AmbienteIndisponivel_RegistraErroNaoPropaga;
    [Test] procedure ProcessarTodos_DrenaFonteAteVazia;

    [Test] procedure AutoManifestador_UnidadeAutomatica_ProcessaComandoCiencia;
    [Test] procedure AutoManifestador_UnidadeNaoAutomatica_NaoProcessa;
  end;

implementation

const
  CHAVE_TESTE = '35260112345678000199550010000000011000000010';
  // Letras acentuadas no texto NATIVO (Delphi: o proprio caractere). No FPC sao bytes
  // UTF-8 -- ver o espelho em tests/Unit/fpc.
  CH_CCEDILHA = #$00E7;
  CH_ATIL = #$00E3;
  ASPAS_ESQ = #$201C;
  ASPAS_DIR = #$201D;

// CertificadoTeste/EventoTeste vem de DFe.TestDoubles.

function ComandoTeste(const ATipoEvento: string = 'ciencia'; const AJustificativa: string = ''): TDFeComandoManifestacao;
begin
  Result.Alias := 'teste';
  Result.ChaveAcesso := '35260112345678000199550010000000011000000010';
  Result.TipoEvento := ATipoEvento;
  Result.Justificativa := AJustificativa;
end;

function EventoManifestacaoTeste: TDFeEventoNormalizado;
begin
  Result := EventoTeste;
  Result.Categoria := dcEvento;
  Result.TipoEvento := 'cienciaoperacao';
  Result.ChaveAcesso := '35260112345678000199550010000000011000000010';
end;

{ TDFeManifestacaoTests }

function TDFeManifestacaoTests.MontarPayload(const ALinhas: array of string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(ALinhas) do
  begin
    if I > 0 then
      Result := Result + sLineBreak;
    Result := Result + ALinhas[I];
  end;
end;

procedure TDFeManifestacaoTests.Setup;
begin
  FPublicador := TDFePublicadorFake.Create;
  FOrquestrador := TDFeOrquestrador.Create(FPublicador);
end;

procedure TDFeManifestacaoTests.TearDown;
begin
  FOrquestrador.Free;
end;

procedure TDFeManifestacaoTests.InterpretarComando_ComandoValido_PreencheCampos;
var
  LComando: TDFeComandoManifestacao;
begin
  LComando := InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=' + CHAVE_TESTE, 'TipoEvento=Ciencia']));

  Assert.AreEqual('matriz', LComando.Alias);
  Assert.AreEqual(CHAVE_TESTE, LComando.ChaveAcesso);
  Assert.AreEqual('ciencia', LComando.TipoEvento);
end;

procedure TDFeManifestacaoTests.InterpretarComando_SemAlias_Levanta;
begin
  Assert.WillRaise(
    procedure
    begin
      InterpretarComando(MontarPayload(['ChaveAcesso=' + CHAVE_TESTE, 'TipoEvento=ciencia']));
    end,
    Exception);
end;

procedure TDFeManifestacaoTests.InterpretarComando_SemChaveAcesso_Levanta;
begin
  Assert.WillRaise(
    procedure
    begin
      InterpretarComando(MontarPayload(['Alias=matriz', 'TipoEvento=ciencia']));
    end,
    Exception);
end;

procedure TDFeManifestacaoTests.InterpretarComando_SemTipoEvento_Levanta;
begin
  Assert.WillRaise(
    procedure
    begin
      InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=' + CHAVE_TESTE]));
    end,
    Exception);
end;

{ NT 2012/002, HP20/H01: xJust e' obrigatorio SO' na Operacao nao Realizada. }
procedure TDFeManifestacaoTests.InterpretarComando_DesconhecimentoSemJustificativa_NaoLevanta;
var
  LComando: TDFeComandoManifestacao;
begin
  LComando := InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=' + CHAVE_TESTE, 'TipoEvento=desconhecimento']));
  Assert.AreEqual('desconhecimento', LComando.TipoEvento);
  Assert.AreEqual('', LComando.Justificativa);
end;

{ A NT manda informar xJust SOMENTE na Operacao nao Realizada; nos outros tipos
  ele e' descartado (versao anterior o exigia no desconhecimento: quem ja
  mandava continua funcionando). }
procedure TDFeManifestacaoTests.InterpretarComando_JustificativaForaDeOperacaoNaoRealizada_EDescartada;
var
  LComando: TDFeComandoManifestacao;
begin
  LComando := InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=' + CHAVE_TESTE,
    'TipoEvento=desconhecimento', 'Justificativa=Desconhecemos esta operacao comercial']));
  Assert.AreEqual('desconhecimento', LComando.TipoEvento);
  Assert.AreEqual('', LComando.Justificativa);

  LComando := InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=' + CHAVE_TESTE,
    'TipoEvento=ciencia', 'Justificativa=texto que nao cabe aqui']));
  Assert.AreEqual('', LComando.Justificativa);
end;

procedure TDFeManifestacaoTests.InterpretarComando_OperacaoNaoRealizadaSemJustificativa_Levanta;
begin
  Assert.WillRaise(
    procedure
    begin
      InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=' + CHAVE_TESTE, 'TipoEvento=operacaonaorealizada']));
    end,
    Exception);
end;

procedure TDFeManifestacaoTests.InterpretarComando_ConfirmacaoSemJustificativa_NaoLevanta;
var
  LComando: TDFeComandoManifestacao;
begin
  LComando := InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=' + CHAVE_TESTE, 'TipoEvento=confirmacao']));

  Assert.AreEqual('confirmacao', LComando.TipoEvento);
end;

procedure TDFeManifestacaoTests.InterpretarComando_TipoEventoDesconhecido_Levanta;
begin
  Assert.WillRaise(
    procedure
    begin
      InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=' + CHAVE_TESTE, 'TipoEvento=foo']));
    end,
    Exception);
end;

procedure TDFeManifestacaoTests.InterpretarComando_ChaveAcessoFora44Digitos_Levanta;
begin
  Assert.WillRaise(
    procedure
    begin
      InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=123', 'TipoEvento=ciencia']));
    end,
    Exception);
end;

procedure TDFeManifestacaoTests.InterpretarComando_JustificativaCurta_Levanta;
begin
  Assert.WillRaise(
    procedure
    begin
      InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=' + CHAVE_TESTE, 'TipoEvento=operacaonaorealizada', 'Justificativa=curta demais']));
    end,
    Exception);
end;

procedure TDFeManifestacaoTests.InterpretarComando_JustificativaValida_NaoLevanta;
var
  LComando: TDFeComandoManifestacao;
begin
  LComando := InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=' + CHAVE_TESTE, 'TipoEvento=operacaonaorealizada', 'Justificativa=Fornecedor nao reconhecido pela empresa']));
  Assert.AreEqual('operacaonaorealizada', LComando.TipoEvento);
end;

procedure TDFeManifestacaoTests.InterpretarComando_JustificativaAcentuada_ContaCaracteresNaoBytes;
var
  LComando: TDFeComandoManifestacao;
  LJust: string;
begin
  // 14 caracteres: RECUSADA (no FPC seriam 16 bytes -- o mesmo caso la' prova que se conta caractere)
  LJust := 'Opera' + CH_CCEDILHA + CH_ATIL + 'o errad';
  Assert.AreEqual(14, TamanhoEmCaracteres(LJust));
  Assert.WillRaise(
    procedure
    begin
      InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=' + CHAVE_TESTE, 'TipoEvento=operacaonaorealizada', 'Justificativa=' + LJust]));
    end,
    Exception);
  // 15 caracteres: aceita e preserva os acentos
  LJust := 'Opera' + CH_CCEDILHA + CH_ATIL + 'o errada';
  LComando := InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=' + CHAVE_TESTE, 'TipoEvento=operacaonaorealizada', 'Justificativa=' + LJust]));
  Assert.AreEqual(LJust, LComando.Justificativa);
end;

procedure TDFeManifestacaoTests.InterpretarComando_JustificativaComAspasCurvas_Levanta;
begin
  Assert.WillRaise(
    procedure
    begin
      InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=' + CHAVE_TESTE, 'TipoEvento=operacaonaorealizada',
        'Justificativa=Recusado pelo ' + ASPAS_ESQ + 'gerente' + ASPAS_DIR + ' da loja']));
    end,
    Exception);
end;

procedure TDFeManifestacaoTests.InterpretarComando_JustificativaComQuebraDeLinha_Levanta;
begin
  Assert.WillRaise(
    procedure
    begin
      InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=' + CHAVE_TESTE, 'TipoEvento=operacaonaorealizada',
        'Justificativa=Fornecedor' + #9 + 'nao reconhecido pela empresa']));
    end,
    Exception);
end;

procedure TDFeManifestacaoTests.InterpretarComando_JustificativaComEspacosNasPontas_EAparada;
var
  LComando: TDFeComandoManifestacao;
begin
  LComando := InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=' + CHAVE_TESTE, 'TipoEvento=operacaonaorealizada',
    'Justificativa=   Fornecedor nao reconhecido pela empresa   ']));
  Assert.AreEqual('Fornecedor nao reconhecido pela empresa', LComando.Justificativa);
end;

procedure TDFeManifestacaoTests.CStatEventoRegistrado_135_136_155_Registrado;
begin
  Assert.IsTrue(CStatEventoRegistrado(135));
  Assert.IsTrue(CStatEventoRegistrado(136));
  Assert.IsTrue(CStatEventoRegistrado(155));
end;

procedure TDFeManifestacaoTests.CStatEventoRegistrado_RejeicoesELote_NaoRegistrado;
begin
  // 128 e' cStat do LOTE (processado), nao de registro do evento; 573 = duplicidade; 0 = sem resposta
  Assert.IsFalse(CStatEventoRegistrado(128));
  Assert.IsFalse(CStatEventoRegistrado(573));
  Assert.IsFalse(CStatEventoRegistrado(0));
end;

procedure TDFeManifestacaoTests.ProcessarComando_AliasDesconhecido_RegistraErroNaoPublica;
var
  LProcessador: TDFeManifestacaoProcessadorTestavel;
begin
  LProcessador := TDFeManifestacaoProcessadorTestavel.Create(FOrquestrador, FPublicador);
  try
    LProcessador.ProcessarComando(ComandoTeste);

    Assert.AreEqual(1, LProcessador.QuantidadeErros);
    Assert.AreEqual(0, FPublicador.Quantidade);
  finally
    LProcessador.Free;
  end;
end;

procedure TDFeManifestacaoTests.ProcessarComando_ClientSemManifestador_RegistraErroNaoPublica;
var
  LProcessador: TDFeManifestacaoProcessadorTestavel;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), TDFeDistribuicaoClientFake.Create, CertificadoTeste, TDFeCursorStoreFake.Create);
  FOrquestrador.AdicionarUnidade(LUnidade);

  LProcessador := TDFeManifestacaoProcessadorTestavel.Create(FOrquestrador, FPublicador);
  try
    LProcessador.ProcessarComando(ComandoTeste);

    Assert.AreEqual(1, LProcessador.QuantidadeErros);
    Assert.AreEqual(0, FPublicador.Quantidade);
  finally
    LProcessador.Free;
  end;
end;

procedure TDFeManifestacaoTests.ProcessarComando_Sucesso_PublicaEventoDevolvido;
var
  LProcessador: TDFeManifestacaoProcessadorTestavel;
  LClient: TDFeClientManifestadorFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LClient := TDFeClientManifestadorFake.Create;
  LClient.EventoADevolver := EventoManifestacaoTeste;
  LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), LClient, CertificadoTeste, TDFeCursorStoreFake.Create);
  FOrquestrador.AdicionarUnidade(LUnidade);

  LProcessador := TDFeManifestacaoProcessadorTestavel.Create(FOrquestrador, FPublicador);
  try
    LProcessador.ProcessarComando(ComandoTeste);

    Assert.AreEqual(0, LProcessador.QuantidadeErros);
    Assert.AreEqual(1, FPublicador.Quantidade);
    Assert.AreEqual(1, LClient.ChamadasEnviarEvento);
    Assert.AreEqual('teste', LClient.UltimoComandoRecebido.Alias);
  finally
    LProcessador.Free;
  end;
end;

procedure TDFeManifestacaoTests.ProcessarComando_CertificadoInvalido_RegistraErroNaoPropaga;
var
  LProcessador: TDFeManifestacaoProcessadorTestavel;
  LClient: TDFeClientManifestadorFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LClient := TDFeClientManifestadorFake.Create;
  LClient.ExcecaoAEnviar := EDFeCertificadoInvalido;
  LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), LClient, CertificadoTeste, TDFeCursorStoreFake.Create);
  FOrquestrador.AdicionarUnidade(LUnidade);

  LProcessador := TDFeManifestacaoProcessadorTestavel.Create(FOrquestrador, FPublicador);
  try
    LProcessador.ProcessarComando(ComandoTeste);

    Assert.AreEqual(1, LProcessador.QuantidadeErros);
    Assert.AreEqual(0, FPublicador.Quantidade);
  finally
    LProcessador.Free;
  end;
end;

procedure TDFeManifestacaoTests.ProcessarComando_ComunicacaoFalhou_RegistraErroNaoPropaga;
var
  LProcessador: TDFeManifestacaoProcessadorTestavel;
  LClient: TDFeClientManifestadorFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LClient := TDFeClientManifestadorFake.Create;
  LClient.ExcecaoAEnviar := EDFeComunicacaoFalhou;
  LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), LClient, CertificadoTeste, TDFeCursorStoreFake.Create);
  FOrquestrador.AdicionarUnidade(LUnidade);

  LProcessador := TDFeManifestacaoProcessadorTestavel.Create(FOrquestrador, FPublicador);
  try
    LProcessador.ProcessarComando(ComandoTeste);

    Assert.AreEqual(1, LProcessador.QuantidadeErros);
    Assert.AreEqual(0, FPublicador.Quantidade);
  finally
    LProcessador.Free;
  end;
end;

procedure TDFeManifestacaoTests.ProcessarComando_RespostaInvalida_RegistraErroNaoPropaga;
var
  LProcessador: TDFeManifestacaoProcessadorTestavel;
  LClient: TDFeClientManifestadorFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LClient := TDFeClientManifestadorFake.Create;
  LClient.ExcecaoAEnviar := EDFeRespostaInvalida;
  LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), LClient, CertificadoTeste, TDFeCursorStoreFake.Create);
  FOrquestrador.AdicionarUnidade(LUnidade);

  LProcessador := TDFeManifestacaoProcessadorTestavel.Create(FOrquestrador, FPublicador);
  try
    LProcessador.ProcessarComando(ComandoTeste);

    Assert.AreEqual(1, LProcessador.QuantidadeErros);
    Assert.AreEqual(0, FPublicador.Quantidade);
  finally
    LProcessador.Free;
  end;
end;

procedure TDFeManifestacaoTests.ProcessarComando_AmbienteIndisponivel_RegistraErroNaoPropaga;
var
  LProcessador: TDFeManifestacaoProcessadorTestavel;
  LClient: TDFeClientManifestadorFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LClient := TDFeClientManifestadorFake.Create;
  LClient.ExcecaoAEnviar := EDFeAmbienteIndisponivel;
  LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), LClient, CertificadoTeste, TDFeCursorStoreFake.Create);
  FOrquestrador.AdicionarUnidade(LUnidade);

  LProcessador := TDFeManifestacaoProcessadorTestavel.Create(FOrquestrador, FPublicador);
  try
    LProcessador.ProcessarComando(ComandoTeste);

    Assert.AreEqual(1, LProcessador.QuantidadeErros);
    Assert.AreEqual(0, FPublicador.Quantidade);
  finally
    LProcessador.Free;
  end;
end;

procedure TDFeManifestacaoTests.ProcessarTodos_DrenaFonteAteVazia;
var
  LProcessador: TDFeManifestacaoProcessadorTestavel;
  LClient: TDFeClientManifestadorFake;
  LUnidade: TDFeUnidadeTrabalho;
  LFonteFake: TDFeComandoFonteFake;
  LFonte: IDFeComandoFonte;
begin
  LClient := TDFeClientManifestadorFake.Create;
  LClient.EventoADevolver := EventoManifestacaoTeste;
  LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), LClient, CertificadoTeste, TDFeCursorStoreFake.Create);
  FOrquestrador.AdicionarUnidade(LUnidade);

  LFonteFake := TDFeComandoFonteFake.Create;
  LFonteFake.AdicionarComando(ComandoTeste);
  LFonteFake.AdicionarComando(ComandoTeste);
  LFonte := LFonteFake;

  LProcessador := TDFeManifestacaoProcessadorTestavel.Create(FOrquestrador, FPublicador);
  try
    LProcessador.ProcessarTodos(LFonte);

    Assert.AreEqual(2, LClient.ChamadasEnviarEvento);
    Assert.AreEqual(2, FPublicador.Quantidade);
  finally
    LProcessador.Free;
  end;
end;

procedure TDFeManifestacaoTests.AutoManifestador_UnidadeAutomatica_ProcessaComandoCiencia;
var
  LProcessador: TDFeManifestacaoProcessador;
  LAutoManifestador: TDFeAutoManifestador;
  LClient: TDFeClientManifestadorFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LClient := TDFeClientManifestadorFake.Create;
  LClient.EventoADevolver := EventoManifestacaoTeste;
  LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), LClient, CertificadoTeste, TDFeCursorStoreFake.Create);
  LUnidade.ManifestacaoAutomatica := True;
  FOrquestrador.AdicionarUnidade(LUnidade);

  LProcessador := TDFeManifestacaoProcessador.Create(FOrquestrador, FPublicador);
  try
    LAutoManifestador := TDFeAutoManifestador.Create(LProcessador);
    try
      LAutoManifestador.AoPublicarDocumento(LUnidade, EventoTeste);

      Assert.AreEqual(1, LClient.ChamadasEnviarEvento);
      Assert.AreEqual('ciencia', LClient.UltimoComandoRecebido.TipoEvento);
      Assert.AreEqual(1, FPublicador.Quantidade);
    finally
      LAutoManifestador.Free;
    end;
  finally
    LProcessador.Free;
  end;
end;

procedure TDFeManifestacaoTests.AutoManifestador_UnidadeNaoAutomatica_NaoProcessa;
var
  LProcessador: TDFeManifestacaoProcessador;
  LAutoManifestador: TDFeAutoManifestador;
  LClient: TDFeClientManifestadorFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LClient := TDFeClientManifestadorFake.Create;
  LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), LClient, CertificadoTeste, TDFeCursorStoreFake.Create);
  // ManifestacaoAutomatica nao setado -- default False
  FOrquestrador.AdicionarUnidade(LUnidade);

  LProcessador := TDFeManifestacaoProcessador.Create(FOrquestrador, FPublicador);
  try
    LAutoManifestador := TDFeAutoManifestador.Create(LProcessador);
    try
      LAutoManifestador.AoPublicarDocumento(LUnidade, EventoTeste);

      Assert.AreEqual(0, LClient.ChamadasEnviarEvento);
      Assert.AreEqual(0, FPublicador.Quantidade);
    finally
      LAutoManifestador.Free;
    end;
  finally
    LProcessador.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeManifestacaoTests);

end.
