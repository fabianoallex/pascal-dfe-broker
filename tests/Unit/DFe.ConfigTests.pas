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
    [Test] procedure CarregarConfig_CertificadoSemProvider_Levanta;
    [Test] procedure CarregarConfig_CertificadoSemCnpjCpf_Levanta;
    [Test] procedure CarregarConfig_CertificadoSemUF_Levanta;
    [Test] procedure MontarUnidades_ProviderNaoRegistrado_Levanta;
    [Test] procedure MontarUnidades_CriaUmaUnidadePorCertificadoEChamaFactory;
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

  Assert.AreEqual(2, Length(LConfig.Certificados));
  Assert.AreEqual('matriz', LConfig.Certificados[0].Alias);
  Assert.AreEqual('nfe', LConfig.Certificados[0].ProviderIdentificador);
  Assert.AreEqual('12345678000199', LConfig.Certificados[0].Certificado.CnpjCpf);
  Assert.AreEqual('RS', LConfig.Certificados[0].Certificado.UF);
  Assert.AreEqual('filial-sp', LConfig.Certificados[1].Alias);
  Assert.AreEqual('cte', LConfig.Certificados[1].ProviderIdentificador);
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

procedure TDFeConfigTests.MontarUnidades_ProviderNaoRegistrado_Levanta;
var
  LConfig: TDFeConfig;
  LCursorStore: IDFeCursorStore; // tipo de interface de proposito: variavel local com finalizacao garantida, mesmo se MontarUnidades levantar (ver CLAUDE.md, gotcha de interface temporaria em unwind de excecao)
  LFactory: TDFeClientFactoryFake;
begin
  EscreverArquivo(['[certificado:x]', 'Provider=teste-config-provider-inexistente-xyz', 'CnpjCpf=12345678000199', 'UF=RS']);
  LConfig := CarregarConfig(FCaminho);
  LCursorStore := TDFeCursorStoreFake.Create;
  LFactory := TDFeClientFactoryFake.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        MontarUnidades(LConfig, LCursorStore, LFactory.Fabricar);
      end,
      Exception);
  finally
    LFactory.Free;
  end;
end;

procedure TDFeConfigTests.MontarUnidades_CriaUmaUnidadePorCertificadoEChamaFactory;
var
  LConfig: TDFeConfig;
  LCursorStore: IDFeCursorStore;
  LFactory: TDFeClientFactoryFake;
  LUnidades: TDFeUnidadeTrabalhoArray;
  I: Integer;
begin
  TDFeProviderRegistry.Registrar(TDFeProviderFake.Create('teste-config-nfe'));
  TDFeProviderRegistry.Registrar(TDFeProviderFake.Create('teste-config-cte'));

  EscreverArquivo([
    '[certificado:matriz]',
    'Provider=teste-config-nfe',
    'CnpjCpf=12345678000199',
    'UF=RS',
    '[certificado:filial]',
    'Provider=teste-config-cte',
    'CnpjCpf=98765432000188',
    'UF=SP']);
  LConfig := CarregarConfig(FCaminho);

  LCursorStore := TDFeCursorStoreFake.Create;
  LFactory := TDFeClientFactoryFake.Create;
  try
    LUnidades := MontarUnidades(LConfig, LCursorStore, LFactory.Fabricar);

    Assert.AreEqual(2, Length(LUnidades));
    Assert.AreEqual(2, LFactory.Chamadas);
    Assert.AreEqual('teste-config-nfe', LUnidades[0].Provider.Identificador);
    Assert.AreEqual('12345678000199', LUnidades[0].Certificado.CnpjCpf);
  finally
    for I := 0 to High(LUnidades) do
      LUnidades[I].Free;
    LFactory.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeConfigTests);

end.
