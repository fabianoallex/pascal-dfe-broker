unit DFe.ManifestacaoTests;

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils,
  DFe.Types,
  DFe.Errors,
  DFe.Provider,
  DFe.Publicador,
  DFe.Orquestrador,
  DFe.Manifestacao,
  DFe.TestDoubles;

type
  TDFeManifestacaoTests = class(TTestCase)
  private
    FOrquestrador: TDFeOrquestrador;
    FPublicador: TDFePublicadorFake;
    FPayloadParaInterpretar: string;
    function MontarPayload(const ALinhas: array of string): string;
    procedure DoInterpretarComando;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure InterpretarComando_ComandoValido_PreencheCampos;
    procedure InterpretarComando_SemAlias_Levanta;
    procedure InterpretarComando_SemChaveAcesso_Levanta;
    procedure InterpretarComando_SemTipoEvento_Levanta;
    procedure InterpretarComando_DesconhecimentoSemJustificativa_Levanta;
    procedure InterpretarComando_OperacaoNaoRealizadaSemJustificativa_Levanta;
    procedure InterpretarComando_ConfirmacaoSemJustificativa_NaoLevanta;

    procedure ProcessarComando_AliasDesconhecido_RegistraErroNaoPublica;
    procedure ProcessarComando_ProviderSemManifestador_RegistraErroNaoPublica;
    procedure ProcessarComando_Sucesso_PublicaEventoDevolvido;
    procedure ProcessarComando_CertificadoInvalido_RegistraErroNaoPropaga;
    procedure ProcessarComando_ComunicacaoFalhou_RegistraErroNaoPropaga;
    procedure ProcessarComando_RespostaInvalida_RegistraErroNaoPropaga;
    procedure ProcessarTodos_DrenaFonteAteVazia;

    procedure AutoManifestador_UnidadeAutomatica_ProcessaComandoCiencia;
    procedure AutoManifestador_UnidadeNaoAutomatica_NaoProcessa;
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

procedure TDFeManifestacaoTests.DoInterpretarComando;
begin
  InterpretarComando(FPayloadParaInterpretar);
end;

procedure TDFeManifestacaoTests.SetUp;
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

  AssertEquals('matriz', LComando.Alias);
  AssertEquals('123', LComando.ChaveAcesso);
  AssertEquals('ciencia', LComando.TipoEvento);
end;

procedure TDFeManifestacaoTests.InterpretarComando_SemAlias_Levanta;
begin
  FPayloadParaInterpretar := MontarPayload(['ChaveAcesso=123', 'TipoEvento=ciencia']);
  AssertException(Exception, DoInterpretarComando);
end;

procedure TDFeManifestacaoTests.InterpretarComando_SemChaveAcesso_Levanta;
begin
  FPayloadParaInterpretar := MontarPayload(['Alias=matriz', 'TipoEvento=ciencia']);
  AssertException(Exception, DoInterpretarComando);
end;

procedure TDFeManifestacaoTests.InterpretarComando_SemTipoEvento_Levanta;
begin
  FPayloadParaInterpretar := MontarPayload(['Alias=matriz', 'ChaveAcesso=123']);
  AssertException(Exception, DoInterpretarComando);
end;

procedure TDFeManifestacaoTests.InterpretarComando_DesconhecimentoSemJustificativa_Levanta;
begin
  FPayloadParaInterpretar := MontarPayload(['Alias=matriz', 'ChaveAcesso=123', 'TipoEvento=desconhecimento']);
  AssertException(Exception, DoInterpretarComando);
end;

procedure TDFeManifestacaoTests.InterpretarComando_OperacaoNaoRealizadaSemJustificativa_Levanta;
begin
  FPayloadParaInterpretar := MontarPayload(['Alias=matriz', 'ChaveAcesso=123', 'TipoEvento=operacaonaorealizada']);
  AssertException(Exception, DoInterpretarComando);
end;

procedure TDFeManifestacaoTests.InterpretarComando_ConfirmacaoSemJustificativa_NaoLevanta;
var
  LComando: TDFeComandoManifestacao;
begin
  LComando := InterpretarComando(MontarPayload(['Alias=matriz', 'ChaveAcesso=123', 'TipoEvento=confirmacao']));

  AssertEquals('confirmacao', LComando.TipoEvento);
end;

procedure TDFeManifestacaoTests.ProcessarComando_AliasDesconhecido_RegistraErroNaoPublica;
var
  LProcessador: TDFeManifestacaoProcessadorTestavel;
begin
  LProcessador := TDFeManifestacaoProcessadorTestavel.Create(FOrquestrador, FPublicador);
  try
    LProcessador.ProcessarComando(ComandoTeste);

    AssertEquals(1, LProcessador.QuantidadeErros);
    AssertEquals(0, FPublicador.Quantidade);
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

    AssertEquals(1, LProcessador.QuantidadeErros);
    AssertEquals(0, FPublicador.Quantidade);
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

    AssertEquals(0, LProcessador.QuantidadeErros);
    AssertEquals(1, FPublicador.Quantidade);
    AssertEquals(1, LProvider.ChamadasEnviarEvento);
    AssertEquals('teste', LProvider.UltimoComandoRecebido.Alias);
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

    AssertEquals(1, LProcessador.QuantidadeErros);
    AssertEquals(0, FPublicador.Quantidade);
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

    AssertEquals(1, LProcessador.QuantidadeErros);
    AssertEquals(0, FPublicador.Quantidade);
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

    AssertEquals(1, LProcessador.QuantidadeErros);
    AssertEquals(0, FPublicador.Quantidade);
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

    AssertEquals(2, LProvider.ChamadasEnviarEvento);
    AssertEquals(2, FPublicador.Quantidade);
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

      AssertEquals(1, LProvider.ChamadasEnviarEvento);
      AssertEquals('ciencia', LProvider.UltimoComandoRecebido.TipoEvento);
      AssertEquals(1, FPublicador.Quantidade);
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

      AssertEquals(0, LProvider.ChamadasEnviarEvento);
      AssertEquals(0, FPublicador.Quantidade);
    finally
      LAutoManifestador.Free;
    end;
  finally
    LProcessador.Free;
  end;
end;

initialization
  RegisterTest(TDFeManifestacaoTests);

end.
