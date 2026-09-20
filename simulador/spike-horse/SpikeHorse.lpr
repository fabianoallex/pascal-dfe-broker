program SpikeHorse;

{$MODE DELPHI}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Horse, SpikeHorseRotas;

var
  Porta: Integer;
begin
  Porta := StrToIntDef(ParamStr(1), 9100);
  RegistrarRotas;
  Writeln('SpikeHorse na porta ', Porta);
  THorse.Listen(Porta);
end.
