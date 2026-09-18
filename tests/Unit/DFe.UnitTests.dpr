program DFe.UnitTests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  DFe.Types in '..\..\src\DFe.Types.pas',
  DFe.Errors in '..\..\src\DFe.Errors.pas',
  DFe.Provider in '..\..\src\DFe.Provider.pas',
  DFe.RoutingKey in '..\..\src\DFe.RoutingKey.pas',
  DFe.CursorStore.Arquivo in '..\..\src\DFe.CursorStore.Arquivo.pas',
  DFe.Orquestrador in '..\..\src\DFe.Orquestrador.pas',
  DFe.TestDoubles in 'DFe.TestDoubles.pas',
  DFe.RoutingKeyTests in 'DFe.RoutingKeyTests.pas',
  DFe.TypesTests in 'DFe.TypesTests.pas',
  DFe.CursorStoreArquivoTests in 'DFe.CursorStoreArquivoTests.pas',
  DFe.ProviderRegistryTests in 'DFe.ProviderRegistryTests.pas',
  DFe.OrquestradorTests in 'DFe.OrquestradorTests.pas';

var
  runner: ITestRunner;
  results: IRunResults;
  logger: ITestLogger;
  nunitLogger: ITestLogger;
begin
  ReportMemoryLeaksOnShutdown := True;
  try
    TDUnitX.CheckCommandLine;

    if TDUnitX.Options.Include = '' then
      TDUnitX.Options.Include := '.';

    runner := TDUnitX.CreateRunner;
    runner.UseRTTI := True;
    runner.FailsOnNoAsserts := False;

    if TDUnitX.Options.ConsoleMode <> TDunitXConsoleMode.Off then
    begin
      logger := TDUnitXConsoleLogger.Create(
        TDUnitX.Options.ConsoleMode = TDunitXConsoleMode.Quiet);
      runner.AddLogger(logger);
    end;

    nunitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    runner.AddLogger(nunitLogger);

    results := runner.Execute;

    if not results.AllPassed then
      System.ExitCode := EXIT_ERRORS;

    if (TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause) and IsConsole then
    begin
      System.Write('Done.. press <Enter> key to quit.');
      System.Readln;
    end;
  except
    on E: Exception do
      System.Writeln(E.ClassName, ': ', E.Message);
  end;
end.
