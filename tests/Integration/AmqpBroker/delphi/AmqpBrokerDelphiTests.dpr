program AmqpBrokerDelphiTests;

{ Testes de INTEGRACAO das pecas que falam AMQP (publicador, fonte de comando,
  aplicacao inteira) contra o broker EMBUTIDO -- versao DELPHI (DUnitX) do
  projeto FPC tests\Integration\AmqpBroker (AmqpBrokerTests.lpr): mesmos 17
  testes. Nao precisa de ACBr, certificado, OpenSSL nem rede alem do loopback,
  entao roda em Win32 e Win64. Requer o repositorio irmao ..\pascal-amqp-faa. }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  DFe.TestDoubles in '..\..\..\Unit\DFe.TestDoubles.pas',
  DFe.AmqpPublicadorTests in 'DFe.AmqpPublicadorTests.pas',
  DFe.AmqpComandoFonteTests in 'DFe.AmqpComandoFonteTests.pas',
  DFe.AmqpAplicacaoTests in 'DFe.AmqpAplicacaoTests.pas';

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
