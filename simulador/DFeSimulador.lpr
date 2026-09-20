program DFeSimulador;

{ Simulador da SEFAZ como aplicacao separada, por HTTP. Ver simulador/LEIAME.md
  e docs/simulador-standalone.md. A logica esta em DFe.Simulador.Principal (a
  mesma para o Delphi, ver DFeSimulador.dpr). }

{$MODE DELPHI}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  DFe.Simulador.Principal;

begin
  Executar;
end.
