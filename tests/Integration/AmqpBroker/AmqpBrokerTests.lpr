program AmqpBrokerTests;

{ Testes de INTEGRACAO das pecas do projeto que falam AMQP de verdade
  (DFe.Publicador.AMQP, DFe.ComandoFonte.AMQP) contra o broker EMBUTIDO do
  pascal-amqp-faa, in-process, em porta efemera. Projeto separado da suite
  pura (tests/Unit) de proposito: linka o cliente e o servidor AMQP, que a
  suite pura nao deve arrastar. Nao precisa de ACBr, certificado, OpenSSL nem
  rede alem do loopback.

  Requer o submodulo vendor/pascal-amqp-faa (git submodule update --init vendor/pascal-amqp-faa).

  Uso: .\AmqpBrokerTests.exe --all --format=plain }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, consoletestrunner, testregistry,
  DFe.AmqpPublicadorTests,
  DFe.AmqpComandoFonteTests,
  DFe.AmqpAplicacaoTests;

var
  ConsoleApp: TTestRunner;
begin
  SetMultiByteConversionCodePage(CP_UTF8);

  DefaultFormat := fPlain;
  DefaultRunAllTests := True;
  ConsoleApp := TTestRunner.Create(nil);
  try
    ConsoleApp.Initialize;
    ConsoleApp.Title := 'pascal-dfe-broker - integracao AMQP embutido';
    ConsoleApp.Run;
  finally
    ConsoleApp.Free;
  end;
end.
