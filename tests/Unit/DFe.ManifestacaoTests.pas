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
    [Test] procedure InterpretarComando_DesconhecimentoSemJustificativa_Levanta;
    [Test] procedure InterpretarComando_OperacaoNaoRealizadaSemJustificativa_Levanta;
    [Test] procedure InterpretarComando_ConfirmacaoSemJustificativa_NaoLevanta;

    [Test] procedure ProcessarComando_AliasDesconhecido_RegistraErroNaoPublica;
    [Test] procedure ProcessarComando_ProviderSemManifestador_RegistraErroNaoPublica;
    [Test] procedure ProcessarComando_Sucesso_PublicaEventoDevolvido;
    [Test] procedure ProcessarComando_CertificadoInvalido_RegistraErroNaoPropaga;
    [Test] procedure ProcessarComando_ComunicacaoFalhou_RegistraErroNaoPropaga;
    [Test] procedure ProcessarComando_RespostaInvalida_RegistraErroNaoPropaga;
    [Test] procedure ProcessarTodos_DrenaFonteAteVazia;

    [Test] procedure AutoManifestador_UnidadeAutomatica_ProcessaComandoCiencia;
    [Test] procedure AutoManifestador_UnidadeNaoAutomatica_NaoProcessa;
  end;

implementation

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
  LComando := InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=123', 'TipoEvento=Ciencia']));

  Assert.AreEqual('matriz', LComando.Alias);
  Assert.AreEqual('123', LComando.ChaveAcesso);
  Assert.AreEqual('ciencia', LComando.TipoEvento);
end;

procedure TDFeManifestacaoTests.InterpretarComando_SemAlias_Levanta;
begin
  Assert.WillRaise(
    procedure
    begin
      InterpretarComando(MontarPayload(['ChaveAcesso=123', 'TipoEvento=ciencia']));
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
      InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=123']));
    end,
    Exception);
end;

procedure TDFeManifestacaoTests.InterpretarComando_DesconhecimentoSemJustificativa_Levanta;
begin
  Assert.WillRaise(
    procedure
    begin
      InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=123', 'TipoEvento=desconhecimento']));
    end,
    Exception);
end;

procedure TDFeManifestacaoTests.InterpretarComando_OperacaoNaoRealizadaSemJustificativa_Levanta;
begin
  Assert.WillRaise(
    procedure
    begin
      InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=123', 'TipoEvento=operacaonaorealizada']));
    end,
    Exception);
end;

procedure TDFeManifestacaoTests.InterpretarComando_ConfirmacaoSemJustificativa_NaoLevanta;
var
  LComando: TDFeComandoManifestacao;
begin
  LComando := InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=123', 'TipoEvento=confirmacao']));

  Assert.AreEqual('confirmacao', LComando.TipoEvento);
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

procedure TDFeManifestacaoTests.ProcessarComando_ProviderSemManifestador_RegistraErroNaoPublica;
var
  LProcessador: TDFeManifestacaoProcessadorTestavel;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), nil, CertificadoTeste, TDFeCursorStoreFake.Create);
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
  LProvider: TDFeProviderManifestadorFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LProvider := TDFeProviderManifestadorFake.Create('nfe');
  LProvider.EventoADevolver := EventoManifestacaoTeste;
  LUnidade := TDFeUnidadeTrabalho.Create(LProvider, nil, CertificadoTeste, TDFeCursorStoreFake.Create);
  FOrquestrador.AdicionarUnidade(LUnidade);

  LProcessador := TDFeManifestacaoProcessadorTestavel.Create(FOrquestrador, FPublicador);
  try
    LProcessador.ProcessarComando(ComandoTeste);

    Assert.AreEqual(0, LProcessador.QuantidadeErros);
    Assert.AreEqual(1, FPublicador.Quantidade);
    Assert.AreEqual(1, LProvider.ChamadasEnviarEvento);
    Assert.AreEqual('teste', LProvider.UltimoComandoRecebido.Alias);
  finally
    LProcessador.Free;
  end;
end;

procedure TDFeManifestacaoTests.ProcessarComando_CertificadoInvalido_RegistraErroNaoPropaga;
var
  LProcessador: TDFeManifestacaoProcessadorTestavel;
  LProvider: TDFeProviderManifestadorFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LProvider := TDFeProviderManifestadorFake.Create('nfe');
  LProvider.ExcecaoAEnviar := EDFeCertificadoInvalido;
  LUnidade := TDFeUnidadeTrabalho.Create(LProvider, nil, CertificadoTeste, TDFeCursorStoreFake.Create);
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
  LProvider: TDFeProviderManifestadorFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LProvider := TDFeProviderManifestadorFake.Create('nfe');
  LProvider.ExcecaoAEnviar := EDFeComunicacaoFalhou;
  LUnidade := TDFeUnidadeTrabalho.Create(LProvider, nil, CertificadoTeste, TDFeCursorStoreFake.Create);
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
  LProvider: TDFeProviderManifestadorFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LProvider := TDFeProviderManifestadorFake.Create('nfe');
  LProvider.ExcecaoAEnviar := EDFeRespostaInvalida;
  LUnidade := TDFeUnidadeTrabalho.Create(LProvider, nil, CertificadoTeste, TDFeCursorStoreFake.Create);
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
  LProvider: TDFeProviderManifestadorFake;
  LUnidade: TDFeUnidadeTrabalho;
  LFonteFake: TDFeComandoFonteFake;
  LFonte: IDFeComandoFonte;
begin
  LProvider := TDFeProviderManifestadorFake.Create('nfe');
  LProvider.EventoADevolver := EventoManifestacaoTeste;
  LUnidade := TDFeUnidadeTrabalho.Create(LProvider, nil, CertificadoTeste, TDFeCursorStoreFake.Create);
  FOrquestrador.AdicionarUnidade(LUnidade);

  LFonteFake := TDFeComandoFonteFake.Create;
  LFonteFake.AdicionarComando(ComandoTeste);
  LFonteFake.AdicionarComando(ComandoTeste);
  LFonte := LFonteFake;

  LProcessador := TDFeManifestacaoProcessadorTestavel.Create(FOrquestrador, FPublicador);
  try
    LProcessador.ProcessarTodos(LFonte);

    Assert.AreEqual(2, LProvider.ChamadasEnviarEvento);
    Assert.AreEqual(2, FPublicador.Quantidade);
  finally
    LProcessador.Free;
  end;
end;

procedure TDFeManifestacaoTests.AutoManifestador_UnidadeAutomatica_ProcessaComandoCiencia;
var
  LProcessador: TDFeManifestacaoProcessador;
  LAutoManifestador: TDFeAutoManifestador;
  LProvider: TDFeProviderManifestadorFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LProvider := TDFeProviderManifestadorFake.Create('nfe');
  LProvider.EventoADevolver := EventoManifestacaoTeste;
  LUnidade := TDFeUnidadeTrabalho.Create(LProvider, nil, CertificadoTeste, TDFeCursorStoreFake.Create);
  LUnidade.ManifestacaoAutomatica := True;
  FOrquestrador.AdicionarUnidade(LUnidade);

  LProcessador := TDFeManifestacaoProcessador.Create(FOrquestrador, FPublicador);
  try
    LAutoManifestador := TDFeAutoManifestador.Create(LProcessador);
    try
      LAutoManifestador.AoPublicarDocumento(LUnidade, EventoTeste);

      Assert.AreEqual(1, LProvider.ChamadasEnviarEvento);
      Assert.AreEqual('ciencia', LProvider.UltimoComandoRecebido.TipoEvento);
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
  LProvider: TDFeProviderManifestadorFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LProvider := TDFeProviderManifestadorFake.Create('nfe');
  LUnidade := TDFeUnidadeTrabalho.Create(LProvider, nil, CertificadoTeste, TDFeCursorStoreFake.Create);
  // ManifestacaoAutomatica nao setado -- default False
  FOrquestrador.AdicionarUnidade(LUnidade);

  LProcessador := TDFeManifestacaoProcessador.Create(FOrquestrador, FPublicador);
  try
    LAutoManifestador := TDFeAutoManifestador.Create(LProcessador);
    try
      LAutoManifestador.AoPublicarDocumento(LUnidade, EventoTeste);

      Assert.AreEqual(0, LProvider.ChamadasEnviarEvento);
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
