unit DFe.Host.Loop;

{$I dfe.inc}

{ Mecanica de loop compartilhada entre os hosts (console, servico Windows;
  ver docs/architecture.md, "Modelo de execucao"). Deliberadamente nao sabe
  nada sobre console, servico ou sinal do SO -- cada host decide como
  chamar Executar/Tick e como reagir a pedido de parada (Ctrl+C, SIGTERM,
  Service Control Manager); esta unit so garante que ExecutarCiclo roda na
  cadencia configurada ate alguem chamar Parar. }

interface

uses
  SysUtils,
  DFe.Orquestrador;

const
  { O orquestrador so faz uma consulta de verdade a SEFAZ quando
    ProximaConsultaEm permite (tipicamente de hora em hora, por unidade --
    ver DFe.Orquestrador). Rodar o tick a cada minuto so decide com que
    atraso maximo o host reage a uma janela que acabou de abrir; nao gera
    nenhuma consulta extra a SEFAZ. }
  DFE_HOST_TICK_SEGUNDOS_PADRAO = 60;

type
  TDFeHostLoop = class
  private
    FOrquestrador: TDFeOrquestrador;
    FTickSegundos: Integer;
    FParando: Boolean;
  public
    constructor Create(const AOrquestrador: TDFeOrquestrador;
      const ATickSegundos: Integer = DFE_HOST_TICK_SEGUNDOS_PADRAO);

    { Um passo do loop -- chamar isto de um timer de servico Windows, por
      exemplo, em vez de usar Executar. Virtual para permitir teste sem
      orquestrador real (ver DFe.TestDoubles.TDFeHostLoopTestavel). }
    procedure Tick; virtual;

    { Loop bloqueante: chama Tick a cada TickSegundos ate Parar ser chamado
      (tipicamente de um handler de sinal do host, ver comentario de topo).
      Uso previsto: um host console. }
    procedure Executar;

    { Seguro o bastante para ser chamado de um handler de sinal/thread
      diferente da que roda Executar: so seta um Boolean sem lock -- pior
      caso e' Executar levar ate 1s a mais para perceber, o que e'
      aceitavel para um processo de cadencia horaria. }
    procedure Parar;
  protected
    { Espera entre verificacoes de tick, sempre 1000ms -- injetavel para
      teste (mesmo padrao do Agora de TDFeOrquestrador: torna Executar
      testavel sem depender de tempo real nenhum). }
    procedure Esperar(const AMilissegundos: Integer); virtual;
  end;

implementation

constructor TDFeHostLoop.Create(const AOrquestrador: TDFeOrquestrador;
  const ATickSegundos: Integer);
begin
  inherited Create;
  FOrquestrador := AOrquestrador;
  FTickSegundos := ATickSegundos;
  FParando := False;
end;

procedure TDFeHostLoop.Tick;
begin
  FOrquestrador.ExecutarCiclo;
end;

procedure TDFeHostLoop.Esperar(const AMilissegundos: Integer);
begin
  Sleep(AMilissegundos);
end;

procedure TDFeHostLoop.Executar;
var
  LSegundosDesdeUltimoTick: Integer;
begin
  LSegundosDesdeUltimoTick := FTickSegundos; // dispara o 1o tick imediatamente ao entrar no loop
  while not FParando do
  begin
    if LSegundosDesdeUltimoTick >= FTickSegundos then
    begin
      Tick;
      LSegundosDesdeUltimoTick := 0;
    end;
    Esperar(1000);
    Inc(LSegundosDesdeUltimoTick);
  end;
end;

procedure TDFeHostLoop.Parar;
begin
  FParando := True;
end;

end.
