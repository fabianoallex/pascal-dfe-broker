program DFeSimulador;

{ Simulador da SEFAZ como aplicacao separada, por HTTP (Delphi). Ver
  simulador/LEIAME.md. A logica esta em DFe.Simulador.Principal, a mesma do FPC
  (ver DFeSimulador.lpr). }

{$APPTYPE CONSOLE}

uses
  DFe.Simulador.Principal in 'DFe.Simulador.Principal.pas';

begin
  Executar;
end.
