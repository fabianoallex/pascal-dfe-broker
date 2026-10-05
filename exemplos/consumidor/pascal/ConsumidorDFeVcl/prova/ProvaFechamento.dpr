program ProvaFechamento;

{ Prova do fechamento do ConsumidorDFeVcl com trabalho em andamento. Ver o
  comentario de topo de uProva.pas.

    FPC:    lazbuild ProvaFechamento.lpi
            ProvaFechamento.exe --auto --host=127.0.0.1 --porta=5699 --cenario=pool
    Delphi: abrir ProvaFechamento.dproj no IDE }

uses
  {$IFDEF FPC}
    {$IFDEF UNIX}
  cthreads,
    {$ENDIF}
  Interfaces,
  {$ENDIF}
  Forms,
  uConsumidorMain in '..\uConsumidorMain.pas' {frmConsumidor},
  uDFeDocumento in '..\uDFeDocumento.pas',
  uProva in 'uProva.pas';

begin
  Application.Initialize;
  Prova := TProva.Create(nil);
  try
    Application.CreateForm(TfrmConsumidor, frmConsumidor);
    Prova.Acompanhar(frmConsumidor);
    Application.Run;
  except
    Prova.Free;
    Prova := nil;
    raise;
  end;
  // O relatorio sai na finalizacao de uProva: a form so' e' liberada DEPOIS
  // do Run voltar (num exit procedure da VCL/LCL), antes das finalizacoes.
end.
