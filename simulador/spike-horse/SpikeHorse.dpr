program SpikeHorse;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Horse,
  SpikeHorseRotas in 'SpikeHorseRotas.pas';

var
  Porta: Integer;
begin
  Porta := StrToIntDef(ParamStr(1), 9100);
  RegistrarRotas;
  Writeln('SpikeHorse (Delphi) na porta ', Porta);
  THorse.Listen(Porta);
  while THorse.IsRunning do
    Sleep(1000);
end.
