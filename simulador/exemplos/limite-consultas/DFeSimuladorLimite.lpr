program DFeSimuladorLimite;

{ EXEMPLO de extensao do simulador (Fase C): o DFeSimulador de sempre + uma regra
  do usuario. O programa e' o mesmo (DFe.Simulador.Principal); so' ganha uma unit
  na clausula uses, que se registra sozinha (initialization). Nada do core foi
  alterado. Ver LEIAME.md. }

{$MODE DELPHI}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  DFe.Simulador.Principal,
  DFe.Simulador.Exemplo.LimiteConsultas; // <-- a extensao: so' existir aqui basta

begin
  Executar;
end.
