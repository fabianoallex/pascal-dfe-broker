unit DFe.Host.Sinais;

{$I dfe.inc}

{ Pedido de parada vindo do sistema operacional, para o host console (ver
  DFe.Host.Aplicacao): Ctrl+C / fechar o console no Windows, SIGINT / SIGTERM no
  Unix (systemd manda SIGTERM). Nao sabe nada sobre a aplicacao: so' chama o
  metodo que o host passou, de dentro do tratador.

  O tratador roda numa thread/contexto do proprio SO, entao AAoParar precisa ser
  seguro nesse contexto -- TDFeAplicacao.Parar so' seta um Boolean.

  Delphi: so' Windows. FPC: Windows e Unix. (Delphi para Linux nao foi
  testado -- ver CLAUDE.md.) }

interface

type
  TDFeParadaProc = procedure of object;

{ Instala o tratador (uma vez por processo; chamadas seguintes trocam o alvo). }
procedure InstalarTratadorDeParada(const AAoParar: TDFeParadaProc);

implementation

uses
  {$IFDEF DFE_WINDOWS}
  {$IFDEF FPC}Windows{$ELSE}Winapi.Windows{$ENDIF}
  {$ELSE}
  ctypes, BaseUnix
  {$ENDIF};

var
  GAoParar: TDFeParadaProc;

{$IFDEF DFE_WINDOWS}
function TratadorConsole(ACtrlType: DWORD): BOOL; stdcall;
begin
  case ACtrlType of
    CTRL_C_EVENT, CTRL_BREAK_EVENT, CTRL_CLOSE_EVENT, CTRL_SHUTDOWN_EVENT:
    begin
      if Assigned(GAoParar) then
        GAoParar;
      Result := True;
    end;
  else
    Result := False;
  end;
end;

procedure InstalarTratadorDeParada(const AAoParar: TDFeParadaProc);
begin
  GAoParar := AAoParar;
  SetConsoleCtrlHandler(@TratadorConsole, True);
end;
{$ELSE}
procedure TratadorSinal(ASinal: cint); cdecl;
begin
  if Assigned(GAoParar) then
    GAoParar;
end;

procedure InstalarTratadorDeParada(const AAoParar: TDFeParadaProc);
begin
  GAoParar := AAoParar;
  fpSignal(SIGINT, @TratadorSinal);
  fpSignal(SIGTERM, @TratadorSinal);
end;
{$ENDIF}

end.
