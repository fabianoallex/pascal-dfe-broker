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
  DFe.Host.Loop in '..\..\src\DFe.Host.Loop.pas',
  DFe.Config in '..\..\src\DFe.Config.pas',
  DFe.Manifestacao in '..\..\src\DFe.Manifestacao.pas',
  DFe.Provider.NFe in '..\..\src\DFe.Provider.NFe.pas',
  DFe.Simulador.Codec in '..\..\src\DFe.Simulador.Codec.pas',
  DFe.Simulador.Fixtures in '..\..\src\DFe.Simulador.Fixtures.pas',
  DFe.Simulador in '..\..\src\DFe.Simulador.pas',
  DFe.Simulador.Client in '..\..\src\DFe.Simulador.Client.pas',
  DFe.Transmissor in '..\..\src\DFe.Transmissor.pas',
  DFe.Simulador.Soap in '..\..\src\DFe.Simulador.Soap.pas',
  DFe.TestDoubles in 'DFe.TestDoubles.pas',
  DFe.RoutingKeyTests in 'DFe.RoutingKeyTests.pas',
  DFe.TypesTests in 'DFe.TypesTests.pas',
  DFe.CursorStoreArquivoTests in 'DFe.CursorStoreArquivoTests.pas',
  DFe.ProviderRegistryTests in 'DFe.ProviderRegistryTests.pas',
  DFe.OrquestradorTests in 'DFe.OrquestradorTests.pas',
  DFe.HostLoopTests in 'DFe.HostLoopTests.pas',
  DFe.ConfigTests in 'DFe.ConfigTests.pas',
  DFe.ManifestacaoTests in 'DFe.ManifestacaoTests.pas',
  DFe.ProviderNFeTests in 'DFe.ProviderNFeTests.pas',
  DFe.SimuladorCodecTests in 'DFe.SimuladorCodecTests.pas',
  DFe.SimuladorFixturesTests in 'DFe.SimuladorFixturesTests.pas',
  DFe.SimuladorTests in 'DFe.SimuladorTests.pas',
  DFe.SimuladorClientTests in 'DFe.SimuladorClientTests.pas',
  DFe.SimuladorSoapTests in 'DFe.SimuladorSoapTests.pas';

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
