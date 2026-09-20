program DFeSimuladorLimite;

{ EXEMPLO de extensao do simulador (Fase C), versao Delphi: o DFeSimulador de
  sempre + uma regra do usuario, que se registra sozinha (initialization). Ver
  LEIAME.md. }

{$APPTYPE CONSOLE}

uses
  DFe.Simulador.Principal in '..\..\DFe.Simulador.Principal.pas',
  DFe.Simulador.Exemplo.LimiteConsultas in 'DFe.Simulador.Exemplo.LimiteConsultas.pas';

begin
  Executar;
end.
