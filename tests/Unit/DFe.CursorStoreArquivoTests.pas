unit DFe.CursorStoreArquivoTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  DFe.Provider,
  DFe.CursorStore.Arquivo;

type
  [TestFixture]
  TDFeCursorStoreArquivoTests = class
  private
    FCaminho: string;
    FStore: IDFeCursorStore;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure ObterUltimoNSU_ArquivoNaoExiste_RetornaZero;
    [Test] procedure GravarEDepoisObter_RoundTrip;
    [Test] procedure GravarDuasVezes_SobrescreveValorAnterior;
    [Test] procedure NamespacesDiferentes_NaoSeMisturam;
    [Test] procedure GravarUltimoNSU_NaoDeixaArquivoTemporario;
  end;

implementation

{ TDFeCursorStoreArquivoTests }

procedure TDFeCursorStoreArquivoTests.Setup;
begin
  FCaminho := ExtractFilePath(ParamStr(0)) + 'dfe_cursor_teste.cursores';
  if FileExists(FCaminho) then
    DeleteFile(FCaminho);
  if FileExists(FCaminho + '.tmp') then
    DeleteFile(FCaminho + '.tmp');
  FStore := TDFeCursorStoreArquivo.Create(FCaminho);
end;

procedure TDFeCursorStoreArquivoTests.TearDown;
begin
  FStore := nil;
  if FileExists(FCaminho) then
    DeleteFile(FCaminho);
  if FileExists(FCaminho + '.tmp') then
    DeleteFile(FCaminho + '.tmp');
end;

procedure TDFeCursorStoreArquivoTests.ObterUltimoNSU_ArquivoNaoExiste_RetornaZero;
begin
  Assert.AreEqual(Int64(0), FStore.ObterUltimoNSU('nfe/12345678000199/rs'));
end;

procedure TDFeCursorStoreArquivoTests.GravarEDepoisObter_RoundTrip;
begin
  FStore.GravarUltimoNSU('nfe/12345678000199/rs', 123456);
  Assert.AreEqual(Int64(123456), FStore.ObterUltimoNSU('nfe/12345678000199/rs'));
end;

procedure TDFeCursorStoreArquivoTests.GravarDuasVezes_SobrescreveValorAnterior;
begin
  FStore.GravarUltimoNSU('nfe/12345678000199/rs', 100);
  FStore.GravarUltimoNSU('nfe/12345678000199/rs', 200);
  Assert.AreEqual(Int64(200), FStore.ObterUltimoNSU('nfe/12345678000199/rs'));
end;

procedure TDFeCursorStoreArquivoTests.NamespacesDiferentes_NaoSeMisturam;
begin
  FStore.GravarUltimoNSU('nfe/12345678000199/rs', 111);
  FStore.GravarUltimoNSU('mdfe/98765432000188/sp', 222);
  Assert.AreEqual(Int64(111), FStore.ObterUltimoNSU('nfe/12345678000199/rs'));
  Assert.AreEqual(Int64(222), FStore.ObterUltimoNSU('mdfe/98765432000188/sp'));
end;

procedure TDFeCursorStoreArquivoTests.GravarUltimoNSU_NaoDeixaArquivoTemporario;
begin
  FStore.GravarUltimoNSU('nfe/12345678000199/rs', 1);
  Assert.IsFalse(FileExists(FCaminho + '.tmp'), 'arquivo .tmp nao deveria sobreviver a uma escrita bem-sucedida');
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeCursorStoreArquivoTests);

end.
