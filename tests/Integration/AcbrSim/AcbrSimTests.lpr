program AcbrSimTests;

{ Testes de INTEGRACAO do client ACBr real contra o simulador da SEFAZ
  (docs/simulador-sefaz.md, Fase 3). Projeto SEPARADO da suite pura
  (tests/Unit) de proposito: linka ACBr + LCL (ver CLAUDE.md, gotchas --
  'uses Interfaces' e vendor/ACBr), o que a suite pura nao deve arrastar.

  Requisitos em execucao: OpenSSL 3 no PATH (libcrypto-3-x64.dll; o do Git
  for Windows serve), pasta Schemas\ com ao menos um *.xsd ao lado do
  executavel e os certificados sinteticos em cert-teste\ (ver
  cert-teste\gerar-certificados.sh). FPC Win64 por enquanto; Delphi Win32
  precisaria das DLLs OpenSSL de 32 bits.

  Uso: .\AcbrSimTests.exe --all --format=plain }

{$mode delphi}{$H+}

uses
  Interfaces, // widgetset LCL: TACBrNFe arrasta LCL transitivamente
  Classes, consoletestrunner, testregistry,
  DFe.AcbrSimTests,
  DFe.AcbrSimEventoTests,
  DFe.AcbrSimHttpTests;

var
  ConsoleApp: TTestRunner;
begin
  SetMultiByteConversionCodePage(CP_UTF8);

  DefaultFormat := fPlain;
  DefaultRunAllTests := True;
  ConsoleApp := TTestRunner.Create(nil);
  try
    ConsoleApp.Initialize;
    ConsoleApp.Title := 'pascal-dfe-broker - integracao ACBr x simulador';
    ConsoleApp.Run;
  finally
    ConsoleApp.Free;
  end;
end.
