program ConsumidorDFeVcl;

{ Consumidor Pascal do pascal-dfe-broker (GUI): so' o lado CLIENTE da lib
  pascal-amqp-faa. Veja o comentario de topo de uConsumidorMain.pas.

  Compila nos dois mundos a partir do MESMO fonte:
    FPC:    lazbuild ConsumidorDFeVcl.lpi
    Delphi: abrir ConsumidorDFeVcl.dproj no IDE }

uses
  {$IFDEF FPC}
    {$IFDEF UNIX}
  cthreads, // threads reais no Unix: sem isso os eventos/condvars da lib falham em runtime
    {$ENDIF}
  Interfaces,
  {$ENDIF}
  Forms,
  uConsumidorMain in 'uConsumidorMain.pas' {frmConsumidor},
  uDFeDocumento in 'uDFeDocumento.pas';

begin
  {$IFNDEF FPC}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}

  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmConsumidor, frmConsumidor);
  Application.Run;
end.
