unit DFe.ConfigTests;

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils, Classes,
  DFe.Types,
  DFe.Provider,
  DFe.Orquestrador,
  DFe.Host.Loop,
  DFe.Config,
  DFe.TestDoubles;

type
  TDFeConfigTests = class(TTestCase)
  private
    FCaminho: string;
    FConfigParaRecarregar: TDFeConfig;
    FOrquestradorParaRecarregar: TDFeOrquestrador;
    FCursorStoreParaRecarregar: IDFeCursorStore;
    FFactoryParaRecarregar: TDFeClientFactoryFake;
    procedure EscreverArquivo(const ALinhas: array of string);
    procedure DoCarregarConfig;
    procedure DoRecarregarConfig;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure CarregarConfig_UsaPadroesQuandoSecaoDfeAusente;
    procedure CarregarConfig_LeConfiguracoesGlobais;
    procedure CarregarConfig_LeCertificados;
    procedure CarregarConfig_AtivoOmitido_DefaultTrue;
    procedure CarregarConfig_AtivoFalse_LeCorretamente;
    procedure CarregarConfig_CertificadoSemProvider_Levanta;
    procedure CarregarConfig_CertificadoSemCnpjCpf_Levanta;
    procedure CarregarConfig_CertificadoSemUF_Levanta;
    procedure CarregarConfig_DoisAtivosMesmoProviderCnpjUF_Levanta;
    procedure CarregarConfig_UmAtivoUmInativoMesmoProviderCnpjUF_NaoLevanta;

    procedure RecarregarConfig_CriaUnidadeParaCadaCertificadoAtivo;
    procedure RecarregarConfig_CertificadoInativo_CriaUnidadePausada;
    procedure RecarregarConfig_ProviderNaoRegistrado_Levanta;
    procedure RecarregarConfig_AliasExistente_NaoRecriaSoSincronizaPausada;
    procedure RecarregarConfig_AliasRemovidoDaConfig_Pausa;

    procedure ConfigWatcher_Create_FazCargaInicial;
    procedure ConfigWatcher_VerificarRecarregar_SoRecarregaSeDataMudou;
  end;

implementation

{ TDFeConfigTests }

procedure TDFeConfigTests.SetUp;
begin
  FCaminho := ExtractFilePath(ParamStr(0)) + 'dfe_config_teste.ini';
  if FileExists(FCaminho) then
    DeleteFile(FCaminho);
end;

procedure TDFeConfigTests.TearDown;
begin
  if FileExists(FCaminho) then
    DeleteFile(FCaminho);
end;

procedure TDFeConfigTests.EscreverArquivo(const ALinhas: array of string);
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

procedure TDFeConfigTests.DoCarregarConfig;
begin
  CarregarConfig(FCaminho);
end;

procedure TDFeConfigTests.DoRecarregarConfig;
begin
  RecarregarConfig(FConfigParaRecarregar, FOrquestradorParaRecarregar, FCursorStoreParaRecarregar, FFactoryParaRecarregar.Fabricar);
end;

procedure TDFeConfigTests.CarregarConfig_UsaPadroesQuandoSecaoDfeAusente;
var
  LConfig: TDFeConfig;
begin
  EscreverArquivo(['[certificado:x]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS']);

  LConfig := CarregarConfig(FCaminho);

  AssertEquals(DFE_INTERVALO_BASE_SEGUNDOS_PADRAO, LConfig.IntervaloBaseSegundos);
  AssertEquals(DFE_HOST_TICK_SEGUNDOS_PADRAO, LConfig.TickSegundos);
  AssertEquals('cursores.dat', LConfig.CursorPath);
end;

procedure TDFeConfigTests.CarregarConfig_LeConfiguracoesGlobais;
var
  LConfig: TDFeConfig;
begin
  EscreverArquivo([
    '[dfe]',
    'IntervaloBaseSegundos=100',
    'TickSegundos=10',
    'CursorPath=outro.dat']);

  LConfig := CarregarConfig(FCaminho);

  AssertEquals(100, LConfig.IntervaloBaseSegundos);
  AssertEquals(10, LConfig.TickSegundos);
  AssertEquals('outro.dat', LConfig.CursorPath);
end;

procedure TDFeConfigTests.CarregarConfig_LeCertificados;
var
  LConfig: TDFeConfig;
begin
  EscreverArquivo([
    '[certificado:matriz]',
    'Provider=nfe',
    'CnpjCpf=12345678000199',
    'UF=RS',
    '[certificado:filial-sp]',
    'Provider=cte',
    'CnpjCpf=98765432000188',
    'UF=SP']);

  LConfig := CarregarConfig(FCaminho);

  AssertEquals(2, Length(LConfig.Certificados));
  AssertEquals('matriz', LConfig.Certificados[0].Alias);
  AssertEquals('nfe', LConfig.Certificados[0].ProviderIdentificador);
  AssertEquals('12345678000199', LConfig.Certificados[0].Certificado.CnpjCpf);
  AssertEquals('RS', LConfig.Certificados[0].Certificado.UF);
  AssertEquals('filial-sp', LConfig.Certificados[1].Alias);
  AssertEquals('cte', LConfig.Certificados[1].ProviderIdentificador);
end;

procedure TDFeConfigTests.CarregarConfig_AtivoOmitido_DefaultTrue;
var
  LConfig: TDFeConfig;
begin
  EscreverArquivo(['[certificado:x]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS']);

  LConfig := CarregarConfig(FCaminho);

  AssertTrue(LConfig.Certificados[0].Ativo);
end;

procedure TDFeConfigTests.CarregarConfig_AtivoFalse_LeCorretamente;
var
  LConfig: TDFeConfig;
begin
  EscreverArquivo(['[certificado:x]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS', 'Ativo=false']);

  LConfig := CarregarConfig(FCaminho);

  AssertFalse(LConfig.Certificados[0].Ativo);
end;

procedure TDFeConfigTests.CarregarConfig_CertificadoSemProvider_Levanta;
begin
  EscreverArquivo(['[certificado:x]', 'CnpjCpf=12345678000199', 'UF=RS']);
  AssertException(Exception, DoCarregarConfig);
end;

procedure TDFeConfigTests.CarregarConfig_CertificadoSemCnpjCpf_Levanta;
begin
  EscreverArquivo(['[certificado:x]', 'Provider=nfe', 'UF=RS']);
  AssertException(Exception, DoCarregarConfig);
end;

procedure TDFeConfigTests.CarregarConfig_CertificadoSemUF_Levanta;
begin
  EscreverArquivo(['[certificado:x]', 'Provider=nfe', 'CnpjCpf=12345678000199']);
  AssertException(Exception, DoCarregarConfig);
end;

procedure TDFeConfigTests.CarregarConfig_DoisAtivosMesmoProviderCnpjUF_Levanta;
begin
  EscreverArquivo([
    '[certificado:antigo]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS',
    '[certificado:novo]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS']);
  AssertException(Exception, DoCarregarConfig);
end;

procedure TDFeConfigTests.CarregarConfig_UmAtivoUmInativoMesmoProviderCnpjUF_NaoLevanta;
var
  LConfig: TDFeConfig;
begin
  EscreverArquivo([
    '[certificado:antigo]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS',
    '[certificado:novo]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS', 'Ativo=false']);

  LConfig := CarregarConfig(FCaminho);

  AssertEquals(2, Length(LConfig.Certificados));
end;

procedure TDFeConfigTests.RecarregarConfig_CriaUnidadeParaCadaCertificadoAtivo;
var
  LOrquestrador: TDFeOrquestrador;
  LCursorStore: IDFeCursorStore;
  LFactory: TDFeClientFactoryFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  TDFeProviderRegistry.Registrar(TDFeProviderFake.Create('teste-config-nfe-a'));
  TDFeProviderRegistry.Registrar(TDFeProviderFake.Create('teste-config-cte-a'));

  EscreverArquivo([
    '[certificado:matriz]', 'Provider=teste-config-nfe-a', 'CnpjCpf=12345678000199', 'UF=RS',
    '[certificado:filial]', 'Provider=teste-config-cte-a', 'CnpjCpf=98765432000188', 'UF=SP']);

  LOrquestrador := TDFeOrquestrador.Create(TDFePublicadorFake.Create);
  LCursorStore := TDFeCursorStoreFake.Create;
  LFactory := TDFeClientFactoryFake.Create;
  try
    RecarregarConfig(CarregarConfig(FCaminho), LOrquestrador, LCursorStore, LFactory.Fabricar);

    AssertEquals(2, Length(LOrquestrador.Unidades));
    AssertEquals(2, LFactory.Chamadas);
    LUnidade := LOrquestrador.ObterUnidadePorAlias('matriz');
    AssertTrue(Assigned(LUnidade));
    AssertFalse(LUnidade.Pausada);
  finally
    LOrquestrador.Free;
    LFactory.Free;
  end;
end;

procedure TDFeConfigTests.RecarregarConfig_CertificadoInativo_CriaUnidadePausada;
var
  LOrquestrador: TDFeOrquestrador;
  LCursorStore: IDFeCursorStore;
  LFactory: TDFeClientFactoryFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  TDFeProviderRegistry.Registrar(TDFeProviderFake.Create('teste-config-nfe-b'));

  EscreverArquivo(['[certificado:x]', 'Provider=teste-config-nfe-b', 'CnpjCpf=12345678000199', 'UF=RS', 'Ativo=false']);

  LOrquestrador := TDFeOrquestrador.Create(TDFePublicadorFake.Create);
  LCursorStore := TDFeCursorStoreFake.Create;
  LFactory := TDFeClientFactoryFake.Create;
  try
    RecarregarConfig(CarregarConfig(FCaminho), LOrquestrador, LCursorStore, LFactory.Fabricar);

    LUnidade := LOrquestrador.ObterUnidadePorAlias('x');
    AssertTrue(Assigned(LUnidade));
    AssertTrue(LUnidade.Pausada);
  finally
    LOrquestrador.Free;
    LFactory.Free;
  end;
end;

procedure TDFeConfigTests.RecarregarConfig_ProviderNaoRegistrado_Levanta;
begin
  EscreverArquivo(['[certificado:x]', 'Provider=teste-config-provider-inexistente-xyz', 'CnpjCpf=12345678000199', 'UF=RS']);
  FConfigParaRecarregar := CarregarConfig(FCaminho);

  FOrquestradorParaRecarregar := TDFeOrquestrador.Create(TDFePublicadorFake.Create);
  FCursorStoreParaRecarregar := TDFeCursorStoreFake.Create;
  FFactoryParaRecarregar := TDFeClientFactoryFake.Create;
  try
    AssertException(Exception, DoRecarregarConfig);
  finally
    FOrquestradorParaRecarregar.Free;
    FFactoryParaRecarregar.Free;
  end;
end;

procedure TDFeConfigTests.RecarregarConfig_AliasExistente_NaoRecriaSoSincronizaPausada;
var
  LOrquestrador: TDFeOrquestrador;
  LCursorStore: IDFeCursorStore;
  LFactory: TDFeClientFactoryFake;
  LUnidade1, LUnidade2: TDFeUnidadeTrabalho;
begin
  TDFeProviderRegistry.Registrar(TDFeProviderFake.Create('teste-config-nfe-c'));

  EscreverArquivo(['[certificado:x]', 'Provider=teste-config-nfe-c', 'CnpjCpf=12345678000199', 'UF=RS']);

  LOrquestrador := TDFeOrquestrador.Create(TDFePublicadorFake.Create);
  LCursorStore := TDFeCursorStoreFake.Create;
  LFactory := TDFeClientFactoryFake.Create;
  try
    RecarregarConfig(CarregarConfig(FCaminho), LOrquestrador, LCursorStore, LFactory.Fabricar);
    LUnidade1 := LOrquestrador.ObterUnidadePorAlias('x');
    AssertFalse(LUnidade1.Pausada);
    AssertEquals(1, LFactory.Chamadas);

    EscreverArquivo(['[certificado:x]', 'Provider=teste-config-nfe-c', 'CnpjCpf=12345678000199', 'UF=RS', 'Ativo=false']);
    RecarregarConfig(CarregarConfig(FCaminho), LOrquestrador, LCursorStore, LFactory.Fabricar);
    LUnidade2 := LOrquestrador.ObterUnidadePorAlias('x');

    AssertTrue('RecarregarConfig nao deveria recriar a unidade para um alias ja existente', LUnidade1 = LUnidade2);
    AssertTrue(LUnidade2.Pausada);
    AssertEquals(1, LFactory.Chamadas); // fabrica nao chamada de novo
  finally
    LOrquestrador.Free;
    LFactory.Free;
  end;
end;

procedure TDFeConfigTests.RecarregarConfig_AliasRemovidoDaConfig_Pausa;
var
  LOrquestrador: TDFeOrquestrador;
  LCursorStore: IDFeCursorStore;
  LFactory: TDFeClientFactoryFake;
  LUnidadeA, LUnidadeB: TDFeUnidadeTrabalho;
begin
  TDFeProviderRegistry.Registrar(TDFeProviderFake.Create('teste-config-nfe-d'));
  TDFeProviderRegistry.Registrar(TDFeProviderFake.Create('teste-config-cte-d'));

  EscreverArquivo([
    '[certificado:a]', 'Provider=teste-config-nfe-d', 'CnpjCpf=12345678000199', 'UF=RS',
    '[certificado:b]', 'Provider=teste-config-cte-d', 'CnpjCpf=98765432000188', 'UF=SP']);

  LOrquestrador := TDFeOrquestrador.Create(TDFePublicadorFake.Create);
  LCursorStore := TDFeCursorStoreFake.Create;
  LFactory := TDFeClientFactoryFake.Create;
  try
    RecarregarConfig(CarregarConfig(FCaminho), LOrquestrador, LCursorStore, LFactory.Fabricar);

    EscreverArquivo(['[certificado:a]', 'Provider=teste-config-nfe-d', 'CnpjCpf=12345678000199', 'UF=RS']);
    RecarregarConfig(CarregarConfig(FCaminho), LOrquestrador, LCursorStore, LFactory.Fabricar);

    LUnidadeA := LOrquestrador.ObterUnidadePorAlias('a');
    LUnidadeB := LOrquestrador.ObterUnidadePorAlias('b');
    AssertFalse(LUnidadeA.Pausada);
    AssertTrue('unidade removida da config nao deveria ser destruida, so pausada', Assigned(LUnidadeB));
    AssertTrue(LUnidadeB.Pausada);
  finally
    LOrquestrador.Free;
    LFactory.Free;
  end;
end;

procedure TDFeConfigTests.ConfigWatcher_Create_FazCargaInicial;
var
  LOrquestrador: TDFeOrquestrador;
  LCursorStore: IDFeCursorStore;
  LFactory: TDFeClientFactoryFake;
  LWatcher: TDFeConfigWatcherTestavel;
begin
  TDFeProviderRegistry.Registrar(TDFeProviderFake.Create('teste-watcher-nfe-a'));
  EscreverArquivo(['[certificado:x]', 'Provider=teste-watcher-nfe-a', 'CnpjCpf=12345678000199', 'UF=RS']);

  LOrquestrador := TDFeOrquestrador.Create(TDFePublicadorFake.Create);
  LCursorStore := TDFeCursorStoreFake.Create;
  LFactory := TDFeClientFactoryFake.Create;
  try
    LWatcher := TDFeConfigWatcherTestavel.Create(FCaminho, LOrquestrador, LCursorStore, LFactory.Fabricar);
    try
      AssertEquals(1, LWatcher.Recargas);
      AssertTrue(Assigned(LOrquestrador.ObterUnidadePorAlias('x')));
    finally
      LWatcher.Free;
    end;
  finally
    LOrquestrador.Free;
    LFactory.Free;
  end;
end;

procedure TDFeConfigTests.ConfigWatcher_VerificarRecarregar_SoRecarregaSeDataMudou;
var
  LOrquestrador: TDFeOrquestrador;
  LCursorStore: IDFeCursorStore;
  LFactory: TDFeClientFactoryFake;
  LWatcher: TDFeConfigWatcherTestavel;
begin
  TDFeProviderRegistry.Registrar(TDFeProviderFake.Create('teste-watcher-nfe-b'));
  EscreverArquivo(['[certificado:x]', 'Provider=teste-watcher-nfe-b', 'CnpjCpf=12345678000199', 'UF=RS']);

  LOrquestrador := TDFeOrquestrador.Create(TDFePublicadorFake.Create);
  LCursorStore := TDFeCursorStoreFake.Create;
  LFactory := TDFeClientFactoryFake.Create;
  try
    LWatcher := TDFeConfigWatcherTestavel.Create(FCaminho, LOrquestrador, LCursorStore, LFactory.Fabricar);
    try
      AssertEquals(1, LWatcher.Recargas);

      LWatcher.VerificarRecarregar; // DataSimulada nao mudou (continua no default)
      AssertEquals(1, LWatcher.Recargas);

      LWatcher.DataSimulada := EncodeDate(2026, 1, 1);
      LWatcher.VerificarRecarregar;
      AssertEquals(2, LWatcher.Recargas);

      LWatcher.VerificarRecarregar; // chamado de novo sem mudar DataSimulada
      AssertEquals(2, LWatcher.Recargas);
    finally
      LWatcher.Free;
    end;
  finally
    LOrquestrador.Free;
    LFactory.Free;
  end;
end;

initialization
  RegisterTest(TDFeConfigTests);

end.
