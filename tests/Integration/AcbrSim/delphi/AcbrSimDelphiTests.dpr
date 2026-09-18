program AcbrSimDelphiTests;

{ Testes de INTEGRACAO do client ACBr real contra o simulador da SEFAZ --
  versao DELPHI (DUnitX) do projeto FPC tests\Integration\AcbrSim
  (AcbrSimTests.lpr): mesmos 31 testes, ver docs\simulador-sefaz.md.

  POR QUE EXISTE: o Servico Windows e' Delphi-only (CLAUDE.md, decisao 9), e
  o ACBr se comporta diferente por compilador -- em especial String: no
  Delphi e' UnicodeString e o ACBr mistura String e AnsiString na leitura do
  XML (docZip.XML e' String; RetInfEvento.XML e' AnsiString), enquanto no FPC
  os bytes UTF-8 passam sem conversao. So' rodando aqui se sabe qual
  encoding chega em XmlDecodificado/XmlPayload.

  PLATAFORMA: use Win64 -- as DLLs de OpenSSL e libxml2 desta maquina sao
  x64 (Win32 exigiria as de 32 bits). O executavel e' gerado em
  tests\Integration\AcbrSim\ (pasta pai), ao lado de cert-teste\ e
  Schemas\, como o do FPC.

  Requisitos em execucao: os mesmos de AcbrSimTests.lpr (OpenSSL 3 e, para os
  14 testes de evento, libxml2 + XSDs; sem eles esses FALHAM com o prefixo AMBIENTE NAO PREPARADO, pois o DUnitX nao ignora em execucao). }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  DFe.TestDoubles in '..\..\..\Unit\DFe.TestDoubles.pas',
  DFe.AcbrSimTests in 'DFe.AcbrSimTests.pas',
  DFe.AcbrSimEventoTests in 'DFe.AcbrSimEventoTests.pas';

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
