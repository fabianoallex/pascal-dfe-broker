unit DFe.Simulador.Horse;

{ A CASCA HTTP do simulador (Horse). So' liga rotas ao servidor puro
  (DFe.Simulador.Servidor); toda a logica esta' la', testada sem rede.

  Handlers como procedimentos simples (Req, Res): e' a forma que compila nos
  dois compiladores (no FPC 3.2.2 nao ha closures; ver simulador/spike-horse).
  Por isso o servidor e' uma variavel da unit e nao um campo. }

{$IFDEF FPC}
  {$MODE DELPHI}{$H+}
{$ENDIF}

interface

uses
  DFe.Simulador.Servidor;

const
  CAMINHO_DISTRIBUICAO = '/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx';
  CAMINHO_EVENTO = '/NFeRecepcaoEvento4/NFeRecepcaoEvento4.asmx';

{ Registra as rotas no Horse. O servidor NAO e' possuido (quem o criou o libera,
  depois de parar o Horse). }
procedure RegistrarRotas(const AServidor: TDFeSimuladorServidor);

implementation

uses
  {$IFDEF FPC}
  SysUtils, SyncObjs,
  {$ELSE}
  System.SysUtils, System.SyncObjs,
  {$ENDIF}
  Horse;

var
  GServidor: TDFeSimuladorServidor;
  GLogLock: TCriticalSection;

procedure Registrar(const AMetodo, ACaminho: string; const AStatus: Integer);
begin
  GLogLock.Enter;
  try
    Writeln(FormatDateTime('hh:nn:ss', Now), ' ', AMetodo, ' ', ACaminho, ' -> ', AStatus);
    Flush(Output);
  finally
    GLogLock.Leave;
  end;
end;

procedure Responder(const Res: THorseResponse; const R: TDFeSimHttpResposta);
begin
  Res.Status(R.Status).ContentType(R.ContentType).Send(R.Corpo);
end;

{ Uma excecao do nucleo (ex.: falha de evento enfileirada e consumida por uma
  consulta de distribuicao -- ver DFe.Simulador) vira HTTP 500 com a mensagem,
  em vez de depender do tratamento de erro do Horse. }
procedure TratarPost(const Req: THorseRequest; const Res: THorseResponse; const ACaminho: string);
var
  R: TDFeSimHttpResposta;
begin
  try
    R := GServidor.Tratar('POST', ACaminho, Req.Headers['SOAPAction'],
      Req.Headers['Content-Type'], Req.Body);
  except
    on E: Exception do
    begin
      R.Status := 500;
      R.ContentType := 'text/plain; charset=utf-8';
      R.Corpo := 'simulador: ' + E.Message;
    end;
  end;
  Registrar('POST', ACaminho, R.Status);
  Responder(Res, R);
end;

procedure Distribuicao(Req: THorseRequest; Res: THorseResponse);
begin
  TratarPost(Req, Res, CAMINHO_DISTRIBUICAO);
end;

procedure Evento(Req: THorseRequest; Res: THorseResponse);
begin
  TratarPost(Req, Res, CAMINHO_EVENTO);
end;

procedure Ping(Req: THorseRequest; Res: THorseResponse);
begin
  Responder(Res, GServidor.Tratar('GET', '/ping', '', '', ''));
end;

procedure Violacoes(Req: THorseRequest; Res: THorseResponse);
var
  LTexto: string;
begin
  LTexto := GServidor.Violacoes;
  if LTexto = '' then
    LTexto := '(nenhuma)';
  Res.Status(200).ContentType('text/plain; charset=utf-8').Send(LTexto);
end;

procedure UltimoEnvelope(Req: THorseRequest; Res: THorseResponse);
begin
  Res.Status(200).ContentType('text/xml; charset=utf-8').Send(GServidor.UltimoEnvelope);
end;

procedure RegistrarRotas(const AServidor: TDFeSimuladorServidor);
begin
  GServidor := AServidor;
  THorse.Get('/ping', Ping);
  THorse.Get('/health', Ping);
  THorse.Get('/admin/violacoes', Violacoes);
  THorse.Get('/admin/ultimo-envelope', UltimoEnvelope);
  THorse.Post(CAMINHO_DISTRIBUICAO, Distribuicao);
  THorse.Post(CAMINHO_EVENTO, Evento);
end;

initialization
  GLogLock := TCriticalSection.Create;

finalization
  GLogLock.Free;

end.
