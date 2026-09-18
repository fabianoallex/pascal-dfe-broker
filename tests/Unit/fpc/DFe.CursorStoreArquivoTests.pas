unit DFe.CursorStoreArquivoTests;

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils,
  DFe.Provider,
  DFe.CursorStore.Arquivo;

type
  TDFeCursorStoreArquivoTests = class(TTestCase)
  private
    FCaminho: string;
    FStore: IDFeCursorStore;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ObterUltimoNSU_ArquivoNaoExiste_RetornaZero;
    procedure GravarEDepoisObter_RoundTrip;
    procedure GravarDuasVezes_SobrescreveValorAnterior;
    procedure NamespacesDiferentes_NaoSeMisturam;
    procedure GravarUltimoNSU_NaoDeixaArquivoTemporario;
  end;

implementation

{ TDFeCursorStoreArquivoTests }

procedure TDFeCursorStoreArquivoTests.SetUp;
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
  AssertEquals(Int64(0), FStore.ObterUltimoNSU('nfe/12345678000199/rs'));
end;

procedure TDFeCursorStoreArquivoTests.GravarEDepoisObter_RoundTrip;
begin
  FStore.GravarUltimoNSU('nfe/12345678000199/rs', 123456);
  AssertEquals(Int64(123456), FStore.ObterUltimoNSU('nfe/12345678000199/rs'));
end;

procedure TDFeCursorStoreArquivoTests.GravarDuasVezes_SobrescreveValorAnterior;
begin
  FStore.GravarUltimoNSU('nfe/12345678000199/rs', 100);
  FStore.GravarUltimoNSU('nfe/12345678000199/rs', 200);
  AssertEquals(Int64(200), FStore.ObterUltimoNSU('nfe/12345678000199/rs'));
end;

procedure TDFeCursorStoreArquivoTests.NamespacesDiferentes_NaoSeMisturam;
begin
  FStore.GravarUltimoNSU('nfe/12345678000199/rs', 111);
  FStore.GravarUltimoNSU('mdfe/98765432000188/sp', 222);
  AssertEquals(Int64(111), FStore.ObterUltimoNSU('nfe/12345678000199/rs'));
  AssertEquals(Int64(222), FStore.ObterUltimoNSU('mdfe/98765432000188/sp'));
end;

procedure TDFeCursorStoreArquivoTests.GravarUltimoNSU_NaoDeixaArquivoTemporario;
begin
  FStore.GravarUltimoNSU('nfe/12345678000199/rs', 1);
  AssertFalse('arquivo .tmp nao deveria sobreviver a uma escrita bem-sucedida', FileExists(FCaminho + '.tmp'));
end;

initialization
  RegisterTest(TDFeCursorStoreArquivoTests);

end.
