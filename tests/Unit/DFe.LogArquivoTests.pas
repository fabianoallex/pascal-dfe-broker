unit DFe.LogArquivoTests;

{ Espelho DUnitX de fpc\DFe.LogArquivoTests.pas (FPCUnit) -- mantenha os dois em
  sincronia (mesmos nomes de teste, mesmas asserções). }

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  DFe.Host.LogArquivo;

type
  { Log com o instante fixo, para o nome do arquivo e a linha serem deterministicos. }
  TDFeLogArquivoTestavel = class(TDFeLogArquivo)
  private
    FInstante: TDateTime;
  protected
    function Agora: TDateTime; override;
  public
    property Instante: TDateTime read FInstante write FInstante;
  end;

  [TestFixture]
  TDFeLogArquivoTests = class
  private
    FPasta: string;
    FLog: TDFeLogArquivoTestavel;
    function LerBytes(const ACaminho: string): TBytes;
    function LerArquivo(const ACaminho: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure Registrar_CriaOArquivoDoDiaComALinhaFormatada;
    [Test] procedure Registrar_AnexaSemSobrescrever;
    [Test] procedure Registrar_DiaDiferente_UsaOutroArquivo;
    [Test] procedure Registrar_AcentoSaiEmUtf8;
    [Test] procedure Registrar_CriaAPastaSeNaoExiste;
    [Test] procedure Registrar_NaoConseguindoEscrever_NaoLevanta;
  end;

implementation

const
  // Delphi: o caractere de verdade (no FPC, os bytes UTF-8)
  E_AGUDO_MAIUSCULO = #$00C9;

function TDFeLogArquivoTestavel.Agora: TDateTime;
begin
  Result := FInstante;
end;

procedure TDFeLogArquivoTests.Setup;
begin
  FPasta := IncludeTrailingPathDelimiter(TPath.GetTempPath) + 'dfe_log_' +
    TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '') + PathDelim;
  FLog := TDFeLogArquivoTestavel.Create(FPasta);
  FLog.Instante := EncodeDate(2026, 9, 19) + EncodeTime(7, 49, 9, 0);
end;

procedure TDFeLogArquivoTests.TearDown;
begin
  FLog.Free;
  if TDirectory.Exists(FPasta) then
    TDirectory.Delete(FPasta, True);
end;

function TDFeLogArquivoTests.LerBytes(const ACaminho: string): TBytes;
begin
  Result := TFile.ReadAllBytes(ACaminho);
end;

function TDFeLogArquivoTests.LerArquivo(const ACaminho: string): string;
begin
  Result := TEncoding.UTF8.GetString(LerBytes(ACaminho));
end;

procedure TDFeLogArquivoTests.Registrar_CriaOArquivoDoDiaComALinhaFormatada;
begin
  FLog.Registrar('INFO', 'Em execucao');

  Assert.AreEqual(FPasta + 'dfe-20260919.log', FLog.CaminhoDoDia);
  Assert.IsTrue(FileExists(FLog.CaminhoDoDia), 'arquivo criado');
  Assert.AreEqual('2026-09-19 07:49:09-03:00 [INFO] Em execucao' + sLineBreak, LerArquivo(FLog.CaminhoDoDia));
end;

procedure TDFeLogArquivoTests.Registrar_AnexaSemSobrescrever;
begin
  FLog.Registrar('INFO', 'primeira');
  FLog.Registrar('ERRO', 'segunda');

  Assert.AreEqual(
    '2026-09-19 07:49:09-03:00 [INFO] primeira' + sLineBreak +
    '2026-09-19 07:49:09-03:00 [ERRO] segunda' + sLineBreak,
    LerArquivo(FLog.CaminhoDoDia));
end;

procedure TDFeLogArquivoTests.Registrar_DiaDiferente_UsaOutroArquivo;
begin
  FLog.Registrar('INFO', 'dia 19');
  FLog.Instante := EncodeDate(2026, 9, 20) + EncodeTime(0, 0, 1, 0);
  FLog.Registrar('INFO', 'dia 20');

  Assert.IsTrue(FileExists(FPasta + 'dfe-20260919.log'));
  Assert.IsTrue(FileExists(FPasta + 'dfe-20260920.log'));
  Assert.AreEqual('2026-09-20 00:00:01-03:00 [INFO] dia 20' + sLineBreak, LerArquivo(FPasta + 'dfe-20260920.log'));
end;

procedure TDFeLogArquivoTests.Registrar_AcentoSaiEmUtf8;
var
  LBytes: TBytes;
  I: Integer;
  LAchou: Boolean;
begin
  FLog.Registrar('INFO', 'JOS' + E_AGUDO_MAIUSCULO);

  LBytes := LerBytes(FLog.CaminhoDoDia);
  LAchou := False;
  for I := 0 to Length(LBytes) - 2 do
    if (LBytes[I] = $C3) and (LBytes[I + 1] = $89) then
      LAchou := True;
  Assert.IsTrue(LAchou, 'E agudo (C3 89) no arquivo');
end;

procedure TDFeLogArquivoTests.Registrar_CriaAPastaSeNaoExiste;
begin
  Assert.IsFalse(TDirectory.Exists(FPasta));
  FLog.Registrar('INFO', 'x');
  Assert.IsTrue(TDirectory.Exists(FPasta));
end;

procedure TDFeLogArquivoTests.Registrar_NaoConseguindoEscrever_NaoLevanta;
var
  LArquivoNoLugarDaPasta: string;
  LLog: TDFeLogArquivoTestavel;
begin
  // o "diretorio" do log e' um ARQUIVO comum: ForceDirectories/criar falha
  ForceDirectories(FPasta);
  LArquivoNoLugarDaPasta := FPasta + 'bloqueio';
  TFile.WriteAllText(LArquivoNoLugarDaPasta, '');

  LLog := TDFeLogArquivoTestavel.Create(LArquivoNoLugarDaPasta);
  try
    LLog.Instante := Now;
    LLog.Registrar('ERRO', 'nao pode levantar'); // se levantasse, o teste falharia aqui
  finally
    LLog.Free;
  end;
  Assert.IsTrue(True);
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeLogArquivoTests);

end.
