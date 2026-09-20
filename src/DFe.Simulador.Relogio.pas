unit DFe.Simulador.Relogio;

{$I dfe.inc}

{ Relogio VIRTUAL do simulador: o relogio real mais um deslocamento que a API
  admin avanca (ver docs/simulador-standalone.md). Sem ele o 656 (bloqueio de
  1 hora) so' se reproduz esperando 1 hora de verdade.

  Liga-se ao nucleo como TDFeAgoraFunc: TDFeSimuladorSefaz.Create(Relogio.Agora).
  Thread-safe (a casca HTTP chama de varias threads).

  So' AVANCA (ou volta a zero): voltar no tempo confundiria o bloqueio de 1 h e
  nao tem uso real num teste. }

interface

uses
  SysUtils, SyncObjs;

type
  TDFeRelogioVirtual = class
  private
    FLock: TCriticalSection;
    FDeslocamentoSegundos: Int64;
  public
    constructor Create;
    destructor Destroy; override;

    { Now + o deslocamento. Compativel com TDFeAgoraFunc (of object). }
    function Agora: TDateTime;
    { ASegundos <= 0 nao faz nada. }
    procedure Avancar(const ASegundos: Int64);
    procedure Zerar;
    function DeslocamentoSegundos: Int64;
  end;

implementation

constructor TDFeRelogioVirtual.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
end;

destructor TDFeRelogioVirtual.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

function TDFeRelogioVirtual.Agora: TDateTime;
begin
  FLock.Enter;
  try
    Result := Now + FDeslocamentoSegundos / 86400;
  finally
    FLock.Leave;
  end;
end;

procedure TDFeRelogioVirtual.Avancar(const ASegundos: Int64);
begin
  if ASegundos <= 0 then
    Exit;
  FLock.Enter;
  try
    Inc(FDeslocamentoSegundos, ASegundos);
  finally
    FLock.Leave;
  end;
end;

procedure TDFeRelogioVirtual.Zerar;
begin
  FLock.Enter;
  try
    FDeslocamentoSegundos := 0;
  finally
    FLock.Leave;
  end;
end;

function TDFeRelogioVirtual.DeslocamentoSegundos: Int64;
begin
  FLock.Enter;
  try
    Result := FDeslocamentoSegundos;
  finally
    FLock.Leave;
  end;
end;

end.
