program DFeUnitTestsFpc;

{ Runner FPCUnit dos testes unitarios (mesma cobertura de tests/Unit/*.pas
  DUnitX/Delphi, portada para FPCUnit). Console-only de proposito: ainda
  nao ha motivo para o runner grafico que o pascal-amqp-faa tem (poucos
  testes, sem necessidade de inspecionar arvore de testes interativamente
  ainda) -- revisitar se a suite crescer a ponto de precisar disso.

  Uso: .\DFeUnitTestsFpc.exe --all --format=plain }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, consoletestrunner, testregistry,
  DFe.TestDoubles,
  DFe.RoutingKeyTests,
  DFe.TypesTests,
  DFe.CursorStoreArquivoTests,
  DFe.ProviderRegistryTests,
  DFe.OrquestradorTests,
  DFe.HostLoopTests,
  DFe.ConfigTests,
  DFe.ManifestacaoTests,
  DFe.ProviderNFeTests,
  DFe.SimuladorCodecTests,
  DFe.SimuladorFixturesTests,
  DFe.SimuladorTests,
  DFe.SimuladorClientTests,
  DFe.SimuladorSoapTests,
  DFe.SimuladorEventoTests,
  DFe.XmlTextoTests,
  DFe.AmbienteTests,
  DFe.FusoTests;

var
  ConsoleApp: TTestRunner;
begin
  // Mesma razao do pascal-amqp-faa: console FPC puro nasce com codepage
  // 1252 (ou equivalente), nao UTF-8 -- strings acentuadas nos testes
  // seriam transcodificadas errado sem isto. Ver CLAUDE.md do
  // pascal-amqp-faa, "Gotchas de FPC ja encontrados".
  SetMultiByteConversionCodePage(CP_UTF8);

  DefaultFormat := fPlain;
  DefaultRunAllTests := True;
  ConsoleApp := TTestRunner.Create(nil);
  try
    ConsoleApp.Initialize;
    ConsoleApp.Title := 'pascal-dfe-broker - testes unitarios (FPCUnit)';
    ConsoleApp.Run;
  finally
    ConsoleApp.Free;
  end;
end.
