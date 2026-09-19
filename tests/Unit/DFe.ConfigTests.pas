unit DFe.ConfigTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Classes,
  DFe.Types,
  DFe.Provider,
  DFe.Orquestrador,
  DFe.Host.Loop,
  DFe.Config,
  DFe.TestDoubles;

type
  [TestFixture]
  TDFeConfigTests = class
  private
    FCaminho: string;
    procedure EscreverArquivo(const ALinhas: array of string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure CarregarConfig_UsaPadroesQuandoSecaoDfeAusente;
    [Test] procedure CarregarConfig_LeConfiguracoesGlobais;
    [Test] procedure CarregarConfig_LeCertificados;
    [Test] procedure CarregarConfig_AtivoOmitido_DefaultTrue;
    [Test] procedure CarregarConfig_AtivoFalse_LeCorretamente;
    [Test] procedure CarregarConfig_CertificadoSemProvider_Levanta;
    [Test] procedure CarregarConfig_CertificadoSemCnpjCpf_Levanta;
    [Test] procedure CarregarConfig_CertificadoSemUF_Levanta;
    [Test] procedure CarregarConfig_DoisAtivosMesmoProviderCnpjUF_Levanta;
    [Test] procedure CarregarConfig_UmAtivoUmInativoMesmoProviderCnpjUF_NaoLevanta;

    [Test] procedure RecarregarConfig_CriaUnidadeParaCadaCertificadoAtivo;
    [Test] procedure RecarregarConfig_CertificadoInativo_CriaUnidadePausada;
    [Test] procedure RecarregarConfig_ProviderNaoRegistrado_Levanta;
    [Test] procedure RecarregarConfig_AliasExistente_NaoRecriaSoSincronizaPausada;
    [Test] procedure RecarregarConfig_AliasRemovidoDaConfig_Pausa;

    [Test] procedure ConfigWatcher_Create_FazCargaInicial;
    [Test] procedure ConfigWatcher_VerificarRecarregar_SoRecarregaSeDataMudou;

    [Test] procedure CarregarConfigBroker_SemSecao_UsaPadroes;
    [Test] procedure CarregarConfigBroker_LeModoExternoEParametros;
    [Test] procedure CarregarConfigBroker_DataDirVazioExplicito_FicaVazio;
    [Test] procedure CarregarConfigBroker_ModoDesconhecido_Levanta;
    [Test] procedure CarregarConfigBroker_PortaInvalida_Levanta;
    [Test] procedure CarregarConfigBroker_LeFilasComVariosPadroes;
    [Test] procedure CarregarConfigBroker_FilaSemRoutingKey_Levanta;
    [Test] procedure CarregarConfigBroker_FilaComNomeReservado_Levanta;

    [Test] procedure CarregarConfig_AmbienteAusente_EProducao;
    [Test] procedure CarregarConfig_AmbienteGlobalHomologacao_EHerdadoPeloCertificado;
    [Test] procedure CarregarConfig_AmbienteDoCertificado_SobrescreveOGlobal;
    [Test] procedure CarregarConfig_AmbienteInvalido_Levanta;
    [Test] procedure CarregarConfig_ProducaoEHomologacaoDoMesmoCnpjUF_AmbosAtivos_NaoLevanta;
    [Test] procedure RecarregarConfig_AmbienteNaUnidadeNova_ENaoMudaNaExistente;
  end;

implementation

{ TDFeConfigTests }

procedure TDFeConfigTests.Setup;
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

procedure TDFeConfigTests.CarregarConfig_UsaPadroesQuandoSecaoDfeAusente;
var
  LConfig: TDFeConfig;
begin
  EscreverArquivo(['[certificado:x]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS']);

  LConfig := CarregarConfig(FCaminho);

  Assert.AreEqual(DFE_INTERVALO_BASE_SEGUNDOS_PADRAO, LConfig.IntervaloBaseSegundos);
  Assert.AreEqual(DFE_HOST_TICK_SEGUNDOS_PADRAO, LConfig.TickSegundos);
  Assert.AreEqual('cursores.dat', LConfig.CursorPath);
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

  Assert.AreEqual(100, LConfig.IntervaloBaseSegundos);
  Assert.AreEqual(10, LConfig.TickSegundos);
  Assert.AreEqual('outro.dat', LConfig.CursorPath);
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

  Assert.AreEqual(2, Integer(Length(LConfig.Certificados)));
  Assert.AreEqual('matriz', LConfig.Certificados[0].Alias);
  Assert.AreEqual('nfe', LConfig.Certificados[0].ProviderIdentificador);
  Assert.AreEqual('12345678000199', LConfig.Certificados[0].Certificado.CnpjCpf);
  Assert.AreEqual('RS', LConfig.Certificados[0].Certificado.UF);
  Assert.AreEqual('filial-sp', LConfig.Certificados[1].Alias);
  Assert.AreEqual('cte', LConfig.Certificados[1].ProviderIdentificador);
end;

procedure TDFeConfigTests.CarregarConfig_AtivoOmitido_DefaultTrue;
var
  LConfig: TDFeConfig;
begin
  EscreverArquivo(['[certificado:x]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS']);

  LConfig := CarregarConfig(FCaminho);

  Assert.IsTrue(LConfig.Certificados[0].Ativo);
end;

procedure TDFeConfigTests.CarregarConfig_AtivoFalse_LeCorretamente;
var
  LConfig: TDFeConfig;
begin
  EscreverArquivo(['[certificado:x]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS', 'Ativo=false']);

  LConfig := CarregarConfig(FCaminho);

  Assert.IsFalse(LConfig.Certificados[0].Ativo);
end;

procedure TDFeConfigTests.CarregarConfig_CertificadoSemProvider_Levanta;
begin
  EscreverArquivo(['[certificado:x]', 'CnpjCpf=12345678000199', 'UF=RS']);

  Assert.WillRaise(
    procedure
    begin
      CarregarConfig(FCaminho);
    end,
    Exception);
end;

procedure TDFeConfigTests.CarregarConfig_CertificadoSemCnpjCpf_Levanta;
begin
  EscreverArquivo(['[certificado:x]', 'Provider=nfe', 'UF=RS']);

  Assert.WillRaise(
    procedure
    begin
      CarregarConfig(FCaminho);
    end,
    Exception);
end;

procedure TDFeConfigTests.CarregarConfig_CertificadoSemUF_Levanta;
begin
  EscreverArquivo(['[certificado:x]', 'Provider=nfe', 'CnpjCpf=12345678000199']);

  Assert.WillRaise(
    procedure
    begin
      CarregarConfig(FCaminho);
    end,
    Exception);
end;

procedure TDFeConfigTests.CarregarConfig_DoisAtivosMesmoProviderCnpjUF_Levanta;
begin
  // Mesmo provider/CnpjCpf/UF, os dois Ativo (default true) -- risco real
  // de consumo indevido (ver DFe.Config, comentario de topo).
  EscreverArquivo([
    '[certificado:antigo]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS',
    '[certificado:novo]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS']);

  Assert.WillRaise(
    procedure
    begin
      CarregarConfig(FCaminho);
    end,
    Exception);
end;

procedure TDFeConfigTests.CarregarConfig_UmAtivoUmInativoMesmoProviderCnpjUF_NaoLevanta;
var
  LConfig: TDFeConfig;
begin
  // Cenario de troca de certificado antes do vencimento: o novo ja
  // configurado mas ainda inativo -- nao deve ser rejeitado.
  EscreverArquivo([
    '[certificado:antigo]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS',
    '[certificado:novo]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS', 'Ativo=false']);

  LConfig := CarregarConfig(FCaminho);

  Assert.AreEqual(2, Integer(Length(LConfig.Certificados)));
end;

procedure TDFeConfigTests.RecarregarConfig_CriaUnidadeParaCadaCertificadoAtivo;
var
  LConfig: TDFeConfig;
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
  LConfig := CarregarConfig(FCaminho);

  LOrquestrador := TDFeOrquestrador.Create(TDFePublicadorFake.Create);
  LCursorStore := TDFeCursorStoreFake.Create;
  LFactory := TDFeClientFactoryFake.Create;
  try
    RecarregarConfig(LConfig, LOrquestrador, LCursorStore, LFactory.Fabricar);

    Assert.AreEqual(2, Integer(Length(LOrquestrador.Unidades)));
    Assert.AreEqual(2, LFactory.Chamadas);
    LUnidade := LOrquestrador.ObterUnidadePorAlias('matriz');
    Assert.IsTrue(Assigned(LUnidade));
    Assert.IsFalse(LUnidade.Pausada);
  finally
    LOrquestrador.Free;
    LFactory.Free;
  end;
end;

procedure TDFeConfigTests.RecarregarConfig_CertificadoInativo_CriaUnidadePausada;
var
  LConfig: TDFeConfig;
  LOrquestrador: TDFeOrquestrador;
  LCursorStore: IDFeCursorStore;
  LFactory: TDFeClientFactoryFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  TDFeProviderRegistry.Registrar(TDFeProviderFake.Create('teste-config-nfe-b'));

  EscreverArquivo(['[certificado:x]', 'Provider=teste-config-nfe-b', 'CnpjCpf=12345678000199', 'UF=RS', 'Ativo=false']);
  LConfig := CarregarConfig(FCaminho);

  LOrquestrador := TDFeOrquestrador.Create(TDFePublicadorFake.Create);
  LCursorStore := TDFeCursorStoreFake.Create;
  LFactory := TDFeClientFactoryFake.Create;
  try
    RecarregarConfig(LConfig, LOrquestrador, LCursorStore, LFactory.Fabricar);

    LUnidade := LOrquestrador.ObterUnidadePorAlias('x');
    Assert.IsTrue(Assigned(LUnidade));
    Assert.IsTrue(LUnidade.Pausada);
  finally
    LOrquestrador.Free;
    LFactory.Free;
  end;
end;

procedure TDFeConfigTests.RecarregarConfig_ProviderNaoRegistrado_Levanta;
var
  LConfig: TDFeConfig;
  LOrquestrador: TDFeOrquestrador;
  LCursorStore: IDFeCursorStore;
  LFactory: TDFeClientFactoryFake;
begin
  EscreverArquivo(['[certificado:x]', 'Provider=teste-config-provider-inexistente-xyz', 'CnpjCpf=12345678000199', 'UF=RS']);
  LConfig := CarregarConfig(FCaminho);

  LOrquestrador := TDFeOrquestrador.Create(TDFePublicadorFake.Create);
  LCursorStore := TDFeCursorStoreFake.Create;
  LFactory := TDFeClientFactoryFake.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        RecarregarConfig(LConfig, LOrquestrador, LCursorStore, LFactory.Fabricar);
      end,
      Exception);
  finally
    LOrquestrador.Free;
    LFactory.Free;
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
    Assert.IsFalse(LUnidade1.Pausada);
    Assert.AreEqual(1, LFactory.Chamadas);

    EscreverArquivo(['[certificado:x]', 'Provider=teste-config-nfe-c', 'CnpjCpf=12345678000199', 'UF=RS', 'Ativo=false']);
    RecarregarConfig(CarregarConfig(FCaminho), LOrquestrador, LCursorStore, LFactory.Fabricar);
    LUnidade2 := LOrquestrador.ObterUnidadePorAlias('x');

    Assert.IsTrue(LUnidade1 = LUnidade2, 'RecarregarConfig nao deveria recriar a unidade para um alias ja existente');
    Assert.IsTrue(LUnidade2.Pausada);
    Assert.AreEqual(1, LFactory.Chamadas); // fabrica nao chamada de novo
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
    Assert.IsFalse(LUnidadeA.Pausada);
    Assert.IsTrue(Assigned(LUnidadeB), 'unidade removida da config nao deveria ser destruida, so pausada');
    Assert.IsTrue(LUnidadeB.Pausada);
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
      Assert.AreEqual(1, LWatcher.Recargas);
      Assert.IsTrue(Assigned(LOrquestrador.ObterUnidadePorAlias('x')));
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
      Assert.AreEqual(1, LWatcher.Recargas);

      LWatcher.VerificarRecarregar; // DataSimulada nao mudou (continua no default)
      Assert.AreEqual(1, LWatcher.Recargas);

      LWatcher.DataSimulada := EncodeDate(2026, 1, 1);
      LWatcher.VerificarRecarregar;
      Assert.AreEqual(2, LWatcher.Recargas);

      LWatcher.VerificarRecarregar; // chamado de novo sem mudar DataSimulada
      Assert.AreEqual(2, LWatcher.Recargas);
    finally
      LWatcher.Free;
    end;
  finally
    LOrquestrador.Free;
    LFactory.Free;
  end;
end;

procedure TDFeConfigTests.CarregarConfigBroker_SemSecao_UsaPadroes;
var
  LConfig: TDFeConfigBroker;
begin
  EscreverArquivo(['[dfe]']);

  LConfig := CarregarConfigBroker(FCaminho);

  Assert.AreEqual(Ord(mbEmbutido), Ord(LConfig.Modo));
  Assert.AreEqual('127.0.0.1', LConfig.BindAddress);
  Assert.AreEqual(5672, LConfig.Porta);
  Assert.AreEqual('guest', LConfig.Usuario);
  Assert.AreEqual('/', LConfig.VirtualHost);
  Assert.AreEqual('broker', LConfig.DataDir);
  Assert.AreEqual(0, Integer(Length(LConfig.Filas)));
end;

procedure TDFeConfigTests.CarregarConfigBroker_LeModoExternoEParametros;
var
  LConfig: TDFeConfigBroker;
begin
  EscreverArquivo(['[broker]', 'Modo=Externo', 'Host=rabbit.local', 'Porta=5673', 'Usuario=dfe', 'Senha=segredo', 'VirtualHost=fiscal']);

  LConfig := CarregarConfigBroker(FCaminho);

  Assert.AreEqual(Ord(mbExterno), Ord(LConfig.Modo));
  Assert.AreEqual('rabbit.local', LConfig.Host);
  Assert.AreEqual(5673, LConfig.Porta);
  Assert.AreEqual('dfe', LConfig.Usuario);
  Assert.AreEqual('segredo', LConfig.Senha);
  Assert.AreEqual('fiscal', LConfig.VirtualHost);
end;

procedure TDFeConfigTests.CarregarConfigBroker_DataDirVazioExplicito_FicaVazio;
var
  LConfig: TDFeConfigBroker;
begin
  EscreverArquivo(['[broker]', 'DataDir=']);

  LConfig := CarregarConfigBroker(FCaminho);

  Assert.AreEqual('', LConfig.DataDir);
end;

procedure TDFeConfigTests.CarregarConfigBroker_ModoDesconhecido_Levanta;
begin
  EscreverArquivo(['[broker]', 'Modo=nuvem']);
  Assert.WillRaise(
    procedure
    begin
      CarregarConfigBroker(FCaminho);
    end,
    Exception);
end;

procedure TDFeConfigTests.CarregarConfigBroker_PortaInvalida_Levanta;
begin
  EscreverArquivo(['[broker]', 'Porta=70000']);
  Assert.WillRaise(
    procedure
    begin
      CarregarConfigBroker(FCaminho);
    end,
    Exception);
end;

procedure TDFeConfigTests.CarregarConfigBroker_LeFilasComVariosPadroes;
var
  LConfig: TDFeConfigBroker;
begin
  EscreverArquivo([
    '[fila:fiscal]', 'RoutingKey=nfe.documento.#, nfe.evento.#',
    '[fila:so-ciencia]', 'RoutingKey=nfe.evento.ciencia.#']);

  LConfig := CarregarConfigBroker(FCaminho);

  Assert.AreEqual(2, Integer(Length(LConfig.Filas)));
  Assert.AreEqual('fiscal', LConfig.Filas[0].Nome);
  Assert.AreEqual(2, Integer(Length(LConfig.Filas[0].Padroes)));
  Assert.AreEqual('nfe.documento.#', LConfig.Filas[0].Padroes[0]);
  Assert.AreEqual('nfe.evento.#', LConfig.Filas[0].Padroes[1]);
  Assert.AreEqual('so-ciencia', LConfig.Filas[1].Nome);
  Assert.AreEqual(1, Integer(Length(LConfig.Filas[1].Padroes)));
end;

procedure TDFeConfigTests.CarregarConfigBroker_FilaSemRoutingKey_Levanta;
begin
  EscreverArquivo(['[fila:x]']);
  Assert.WillRaise(
    procedure
    begin
      CarregarConfigBroker(FCaminho);
    end,
    Exception);
end;

procedure TDFeConfigTests.CarregarConfigBroker_FilaComNomeReservado_Levanta;
begin
  EscreverArquivo(['[fila:dfe.comandos]', 'RoutingKey=#']);
  Assert.WillRaise(
    procedure
    begin
      CarregarConfigBroker(FCaminho);
    end,
    Exception);
end;

procedure TDFeConfigTests.CarregarConfig_AmbienteAusente_EProducao;
var
  LConfig: TDFeConfig;
begin
  EscreverArquivo(['[certificado:x]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS']);

  LConfig := CarregarConfig(FCaminho);

  Assert.AreEqual(Ord(daProducao), Ord(LConfig.Ambiente));
  Assert.AreEqual(Ord(daProducao), Ord(LConfig.Certificados[0].Ambiente));
end;

procedure TDFeConfigTests.CarregarConfig_AmbienteGlobalHomologacao_EHerdadoPeloCertificado;
var
  LConfig: TDFeConfig;
begin
  EscreverArquivo(['[dfe]', 'Ambiente=Homologacao', '[certificado:x]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS']);

  LConfig := CarregarConfig(FCaminho);

  Assert.AreEqual(Ord(daHomologacao), Ord(LConfig.Ambiente));
  Assert.AreEqual(Ord(daHomologacao), Ord(LConfig.Certificados[0].Ambiente));
end;

procedure TDFeConfigTests.CarregarConfig_AmbienteDoCertificado_SobrescreveOGlobal;
var
  LConfig: TDFeConfig;
begin
  EscreverArquivo([
    '[dfe]', 'Ambiente=homologacao',
    '[certificado:prod]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS', 'Ambiente=producao',
    '[certificado:hom]', 'Provider=nfe', 'CnpjCpf=98765432000188', 'UF=SP']);

  LConfig := CarregarConfig(FCaminho);

  Assert.AreEqual(Ord(daProducao), Ord(LConfig.Certificados[0].Ambiente));
  Assert.AreEqual(Ord(daHomologacao), Ord(LConfig.Certificados[1].Ambiente), 'herda o global');
end;

procedure TDFeConfigTests.CarregarConfig_AmbienteInvalido_Levanta;
begin
  EscreverArquivo(['[dfe]', 'Ambiente=nuvem', '[certificado:x]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS']);
  Assert.WillRaise(
    procedure
    begin
      CarregarConfig(FCaminho);
    end,
    Exception);
end;

procedure TDFeConfigTests.CarregarConfig_ProducaoEHomologacaoDoMesmoCnpjUF_AmbosAtivos_NaoLevanta;
var
  LConfig: TDFeConfig;
begin
  // cursores distintos (producao x homologacao): nao ha' risco de consumo indevido cruzado
  EscreverArquivo([
    '[certificado:prod]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS', 'Ambiente=producao',
    '[certificado:hom]', 'Provider=nfe', 'CnpjCpf=12345678000199', 'UF=RS', 'Ambiente=homologacao']);

  LConfig := CarregarConfig(FCaminho);

  Assert.AreEqual(2, Integer(Length(LConfig.Certificados)));
end;

procedure TDFeConfigTests.RecarregarConfig_AmbienteNaUnidadeNova_ENaoMudaNaExistente;
var
  LOrquestrador: TDFeOrquestrador;
  LCursorStore: IDFeCursorStore;
  LFactory: TDFeClientFactoryFake;
begin
  TDFeProviderRegistry.Registrar(TDFeProviderFake.Create('teste-config-amb-a'));

  EscreverArquivo(['[dfe]', 'Ambiente=homologacao', '[certificado:x]', 'Provider=teste-config-amb-a', 'CnpjCpf=12345678000199', 'UF=RS']);

  LOrquestrador := TDFeOrquestrador.Create(TDFePublicadorFake.Create);
  LCursorStore := TDFeCursorStoreFake.Create;
  LFactory := TDFeClientFactoryFake.Create;
  try
    RecarregarConfig(CarregarConfig(FCaminho), LOrquestrador, LCursorStore, LFactory.Fabricar);
    Assert.AreEqual(Ord(daHomologacao), Ord(LOrquestrador.ObterUnidadePorAlias('x').Ambiente), 'unidade nova recebe o ambiente');

    // editar o ambiente com a unidade ja' em execucao NAO a muda: o client foi criado com o antigo
    EscreverArquivo(['[dfe]', 'Ambiente=producao', '[certificado:x]', 'Provider=teste-config-amb-a', 'CnpjCpf=12345678000199', 'UF=RS']);
    RecarregarConfig(CarregarConfig(FCaminho), LOrquestrador, LCursorStore, LFactory.Fabricar);
    Assert.AreEqual(Ord(daHomologacao), Ord(LOrquestrador.ObterUnidadePorAlias('x').Ambiente), 'unidade existente segue igual');
  finally
    LOrquestrador.Free;
    LFactory.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeConfigTests);

end.
