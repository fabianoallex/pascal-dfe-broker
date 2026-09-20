unit SpikeHorseRotas;

{ SPIKE DESCARTAVEL (simulador/spike-horse): responde as perguntas que decidem
  se o Horse serve de casca HTTP do simulador da SEFAZ nos DOIS compiladores.
  Nada aqui e' codigo do simulador. Rotas:

    GET  /ping          -> 'pong'
    POST /eco           -> devolve o corpo exatamente como chegou (acentos!)
    POST /lento         -> dorme 1 s e devolve o id da thread (concorrencia)
    POST /erro          -> HTTP 500 com corpo
    POST /grande        -> corpo de ~300 KB (docZip grande)
    POST /tipo          -> devolve o Content-Type que o cliente mandou }

{$IFDEF FPC}
  {$MODE DELPHI}{$H+}
{$ENDIF}

interface

procedure RegistrarRotas;

implementation

uses
  {$IFDEF FPC}
  SysUtils, Classes,
  {$ELSE}
  System.SysUtils, System.Classes,
  {$ENDIF}
  Horse;

procedure Ping(Req: THorseRequest; Res: THorseResponse);
begin
  Res.Send('pong');
end;

procedure Eco(Req: THorseRequest; Res: THorseResponse);
begin
  Res.ContentType('text/xml; charset=utf-8').Send(Req.Body);
end;

procedure Lento(Req: THorseRequest; Res: THorseResponse);
begin
  {$IFDEF FPC}
  Sleep(1000);
  Res.Send('thread=' + IntToStr(PtrUInt(TThread.CurrentThread.ThreadID)));
  {$ELSE}
  TThread.Sleep(1000);
  Res.Send('thread=' + IntToStr(NativeUInt(TThread.CurrentThread.ThreadID)));
  {$ENDIF}
end;

procedure Erro(Req: THorseRequest; Res: THorseResponse);
begin
  Res.Status(500).ContentType('text/xml; charset=utf-8').Send('<erro>falha</erro>');
end;

procedure Grande(Req: THorseRequest; Res: THorseResponse);
var
  S: string;
  I: Integer;
begin
  S := '';
  for I := 1 to 6000 do
    S := S + '<item>0123456789012345678901234567890123456789012345</item>'#10;
  Res.ContentType('text/xml; charset=utf-8').Send(S);
end;

procedure Tipo(Req: THorseRequest; Res: THorseResponse);
begin
  Res.Send('ct=' + Req.Headers['Content-Type'] +
    ' soapaction=' + Req.Headers['SOAPAction'] +
    ' len=' + IntToStr(Length(Req.Body)));
end;

procedure RegistrarRotas;
begin
  THorse.Get('/ping', Ping);
  THorse.Post('/eco', Eco);
  THorse.Post('/lento', Lento);
  THorse.Post('/erro', Erro);
  THorse.Post('/grande', Grande);
  THorse.Post('/tipo', Tipo);
end;

end.
