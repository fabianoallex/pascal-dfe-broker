unit DFe.LogArquivoTests;

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils, Classes,
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

  TDFeLogArquivoTests = class(TTestCase)
  private
    FPasta: string;
    FLog: TDFeLogArquivoTestavel;
    function LerArquivo(const ACaminho: string): string;
    function LerBytes(const ACaminho: string): TBytes;
    procedure CriarArquivo(const ANome: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Registrar_CriaOArquivoDoDiaComALinhaFormatada;
    procedure Registrar_AnexaSemSobrescrever;
    procedure Registrar_DiaDiferente_UsaOutroArquivo;
    procedure Registrar_AcentoSaiEmUtf8;
    procedure Registrar_CriaAPastaSeNaoExiste;
    procedure Registrar_NaoConseguindoEscrever_NaoLevanta;
    procedure Retencao_ApagaOsArquivosComNDiasOuMais;
    procedure Retencao_Zero_NaoApagaNada;
    procedure Retencao_NaoMexeEmArquivosQueNaoSaoDoLog;
    procedure Retencao_SoLimpaUmaVezPorDia;
  end;

implementation

const
  // texto NATIVO do compilador (ver DFe.XmlTexto): no FPC, bytes UTF-8
  E_AGUDO_MAIUSCULO = #$C3#$89;

function TDFeLogArquivoTestavel.Agora: TDateTime;
begin
  Result := FInstante;
end;

procedure ApagarPasta(const APasta: string);
var
  LBusca: TSearchRec;
begin
  if not DirectoryExists(APasta) then
    Exit;
  if FindFirst(IncludeTrailingPathDelimiter(APasta) + '*', faAnyFile, LBusca) = 0 then
  try
    repeat
      if (LBusca.Name = '.') or (LBusca.Name = '..') then
        Continue;
      if (LBusca.Attr and faDirectory) <> 0 then
        ApagarPasta(IncludeTrailingPathDelimiter(APasta) + LBusca.Name)
      else
        DeleteFile(IncludeTrailingPathDelimiter(APasta) + LBusca.Name);
    until FindNext(LBusca) <> 0;
  finally
    FindClose(LBusca);
  end;
  RemoveDir(APasta);
end;

procedure TDFeLogArquivoTests.SetUp;
begin
  FPasta := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'dfe_log_' + IntToStr(GetTickCount64) + PathDelim;
  FLog := TDFeLogArquivoTestavel.Create(FPasta);
  FLog.Instante := EncodeDate(2026, 9, 19) + EncodeTime(7, 49, 9, 0);
end;

procedure TDFeLogArquivoTests.TearDown;
begin
  FLog.Free;
  ApagarPasta(FPasta);
end;

function TDFeLogArquivoTests.LerBytes(const ACaminho: string): TBytes;
var
  LArquivo: TFileStream;
begin
  LArquivo := TFileStream.Create(ACaminho, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, LArquivo.Size);
    if LArquivo.Size > 0 then
      LArquivo.ReadBuffer(Result[0], LArquivo.Size);
  finally
    LArquivo.Free;
  end;
end;

function TDFeLogArquivoTests.LerArquivo(const ACaminho: string): string;
var
  LBytes: TBytes;
begin
  LBytes := LerBytes(ACaminho);
  SetLength(Result, Length(LBytes));
  if Length(LBytes) > 0 then
    Move(LBytes[0], Result[1], Length(LBytes));
end;

procedure TDFeLogArquivoTests.CriarArquivo(const ANome: string);
var
  LLista: TStringList;
begin
  ForceDirectories(FPasta);
  LLista := TStringList.Create;
  try
    LLista.SaveToFile(FPasta + ANome);
  finally
    LLista.Free;
  end;
end;

procedure TDFeLogArquivoTests.Registrar_CriaOArquivoDoDiaComALinhaFormatada;
begin
  FLog.Registrar('INFO', 'Em execucao');

  AssertEquals(FPasta + 'dfe-20260919.log', FLog.CaminhoDoDia);
  AssertTrue('arquivo criado', FileExists(FLog.CaminhoDoDia));
  AssertEquals('2026-09-19 07:49:09-03:00 [INFO] Em execucao' + sLineBreak, LerArquivo(FLog.CaminhoDoDia));
end;

procedure TDFeLogArquivoTests.Registrar_AnexaSemSobrescrever;
begin
  FLog.Registrar('INFO', 'primeira');
  FLog.Registrar('ERRO', 'segunda');

  AssertEquals(
    '2026-09-19 07:49:09-03:00 [INFO] primeira' + sLineBreak +
    '2026-09-19 07:49:09-03:00 [ERRO] segunda' + sLineBreak,
    LerArquivo(FLog.CaminhoDoDia));
end;

procedure TDFeLogArquivoTests.Registrar_DiaDiferente_UsaOutroArquivo;
begin
  FLog.Registrar('INFO', 'dia 19');
  FLog.Instante := EncodeDate(2026, 9, 20) + EncodeTime(0, 0, 1, 0);
  FLog.Registrar('INFO', 'dia 20');

  AssertTrue(FileExists(FPasta + 'dfe-20260919.log'));
  AssertTrue(FileExists(FPasta + 'dfe-20260920.log'));
  AssertEquals('2026-09-20 00:00:01-03:00 [INFO] dia 20' + sLineBreak, LerArquivo(FPasta + 'dfe-20260920.log'));
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
  AssertTrue('E agudo (C3 89) no arquivo', LAchou);
end;

procedure TDFeLogArquivoTests.Registrar_CriaAPastaSeNaoExiste;
begin
  AssertFalse(DirectoryExists(FPasta));
  FLog.Registrar('INFO', 'x');
  AssertTrue(DirectoryExists(FPasta));
end;

procedure TDFeLogArquivoTests.Registrar_NaoConseguindoEscrever_NaoLevanta;
var
  LArquivoNoLugarDaPasta: string;
  LLog: TDFeLogArquivoTestavel;
  LLista: TStringList;
begin
  // o "diretorio" do log e' um ARQUIVO comum: ForceDirectories/criar falha
  ForceDirectories(FPasta);
  LArquivoNoLugarDaPasta := FPasta + 'bloqueio';
  LLista := TStringList.Create;
  try
    LLista.SaveToFile(LArquivoNoLugarDaPasta);
  finally
    LLista.Free;
  end;

  LLog := TDFeLogArquivoTestavel.Create(LArquivoNoLugarDaPasta);
  try
    LLog.Instante := Now;
    LLog.Registrar('ERRO', 'nao pode levantar'); // se levantasse, o teste falharia aqui
  finally
    LLog.Free;
  end;
  AssertTrue(True);
end;

procedure TDFeLogArquivoTests.Retencao_ApagaOsArquivosComNDiasOuMais;
begin
  // hoje = 19/09; "3 dias" = 19, 18 e 17; o de 16 (3 dias antes) sai
  FLog.RetencaoDias := 3;
  CriarArquivo('dfe-20260919.log');
  CriarArquivo('dfe-20260918.log');
  CriarArquivo('dfe-20260917.log');
  CriarArquivo('dfe-20260916.log');
  CriarArquivo('dfe-20250101.log');

  FLog.Registrar('INFO', 'gatilho da limpeza');

  AssertTrue('dfe-20260919.log existe', FileExists(FPasta + 'dfe-20260919.log'));
  AssertTrue('dfe-20260918.log existe', FileExists(FPasta + 'dfe-20260918.log'));
  AssertTrue('dfe-20260917.log existe', FileExists(FPasta + 'dfe-20260917.log'));
  AssertFalse('dfe-20260916.log apagado', FileExists(FPasta + 'dfe-20260916.log'));
  AssertFalse('dfe-20250101.log apagado', FileExists(FPasta + 'dfe-20250101.log'));
end;

procedure TDFeLogArquivoTests.Retencao_Zero_NaoApagaNada;
begin
  CriarArquivo('dfe-20200101.log');

  FLog.Registrar('INFO', 'gatilho');

  AssertTrue('dfe-20200101.log existe', FileExists(FPasta + 'dfe-20200101.log'));
end;

procedure TDFeLogArquivoTests.Retencao_NaoMexeEmArquivosQueNaoSaoDoLog;
begin
  FLog.RetencaoDias := 1;
  CriarArquivo('outro.log');
  CriarArquivo('dfe-antigo.log');        // nao tem 8 digitos
  CriarArquivo('dfe-2020010A.log');      // 8 caracteres, mas nao so' digitos
  CriarArquivo('dfe-20200101.txt');      // extensao diferente
  CriarArquivo('x-20200101.log');        // outro prefixo
  CriarArquivo('dfe-20261399.log');      // 8 digitos, mas nao e' uma data

  FLog.Registrar('INFO', 'gatilho');

  AssertTrue('outro.log existe', FileExists(FPasta + 'outro.log'));
  AssertTrue('dfe-antigo.log existe', FileExists(FPasta + 'dfe-antigo.log'));
  AssertTrue('dfe-2020010A.log existe', FileExists(FPasta + 'dfe-2020010A.log'));
  AssertTrue('dfe-20200101.txt existe', FileExists(FPasta + 'dfe-20200101.txt'));
  AssertTrue('x-20200101.log existe', FileExists(FPasta + 'x-20200101.log'));
  AssertTrue('dfe-20261399.log existe', FileExists(FPasta + 'dfe-20261399.log'));
end;

procedure TDFeLogArquivoTests.Retencao_SoLimpaUmaVezPorDia;
begin
  FLog.RetencaoDias := 2;
  FLog.Registrar('INFO', 'primeira do dia'); // limpa
  CriarArquivo('dfe-20200101.log');          // aparece DEPOIS da limpeza do dia

  FLog.Registrar('INFO', 'segunda do dia');  // mesmo dia: nao varre de novo

  AssertTrue('dfe-20200101.log existe', FileExists(FPasta + 'dfe-20200101.log'));

  FLog.Instante := EncodeDate(2026, 9, 20) + EncodeTime(0, 0, 1, 0);
  FLog.Registrar('INFO', 'dia seguinte');    // dia novo: varre

  AssertFalse('dfe-20200101.log apagado', FileExists(FPasta + 'dfe-20200101.log'));
end;

initialization
  RegisterTest(TDFeLogArquivoTests);

end.
