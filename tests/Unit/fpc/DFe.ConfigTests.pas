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
    FConfigParaMontar: TDFeConfig;
    FCursorStoreParaMontar: IDFeCursorStore;
    FFactoryParaMontar: TDFeClientFactoryFake;
    procedure EscreverArquivo(const ALinhas: array of string);
    procedure DoCarregarConfig;
    procedure DoMontarUnidades;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure CarregarConfig_UsaPadroesQuandoSecaoDfeAusente;
    procedure CarregarConfig_LeConfiguracoesGlobais;
    procedure CarregarConfig_LeCertificados;
    procedure CarregarConfig_CertificadoSemProvider_Levanta;
    procedure CarregarConfig_CertificadoSemCnpjCpf_Levanta;
    procedure CarregarConfig_CertificadoSemUF_Levanta;
    procedure MontarUnidades_ProviderNaoRegistrado_Levanta;
    procedure MontarUnidades_CriaUmaUnidadePorCertificadoEChamaFactory;
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

procedure TDFeConfigTests.DoMontarUnidades;
begin
  MontarUnidades(FConfigParaMontar, FCursorStoreParaMontar, FFactoryParaMontar.Fabricar);
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

procedure TDFeConfigTests.MontarUnidades_ProviderNaoRegistrado_Levanta;
begin
  EscreverArquivo(['[certificado:x]', 'Provider=teste-config-provider-inexistente-xyz', 'CnpjCpf=12345678000199', 'UF=RS']);
  FConfigParaMontar := CarregarConfig(FCaminho);
  FCursorStoreParaMontar := TDFeCursorStoreFake.Create;
  FFactoryParaMontar := TDFeClientFactoryFake.Create;
  try
    AssertException(Exception, DoMontarUnidades);
  finally
    FFactoryParaMontar.Free;
  end;
end;

procedure TDFeConfigTests.MontarUnidades_CriaUmaUnidadePorCertificadoEChamaFactory;
var
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

  LCursorStore := TDFeCursorStoreFake.Create;
  LFactory := TDFeClientFactoryFake.Create;
  try
    LUnidades := MontarUnidades(CarregarConfig(FCaminho), LCursorStore, LFactory.Fabricar);

    AssertEquals(2, Length(LUnidades));
    AssertEquals(2, LFactory.Chamadas);
    AssertEquals('teste-config-nfe', LUnidades[0].Provider.Identificador);
    AssertEquals('12345678000199', LUnidades[0].Certificado.CnpjCpf);
  finally
    for I := 0 to High(LUnidades) do
      LUnidades[I].Free;
    LFactory.Free;
  end;
end;

initialization
  RegisterTest(TDFeConfigTests);

end.
