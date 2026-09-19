unit DFe.Fuso;

{$I dfe.inc}

{ Hora do EVENTO (dhEvento) da manifestacao -- independente do fuso do sistema.

  ACHADO (2026-09-18, medido): o ACBr formata dhEvento com a hora LOCAL do
  sistema e o sufixo de fuso do sistema (modo padrao tzSistema). Isso e'
  coerente enquanto o RTL acerta o fuso local -- mas no FPC 3.2.2 em Linux
  (Docker, Debian 12) `Now` IGNORA /etc/localtime e a variavel TZ e devolve UTC,
  e o evento saia como "...T09:28:31+00:00". O XSD (TDateTimeUTC) aceita
  qualquer +-hh:00, entao nao e' rejeitado localmente; mas a NT 2012/002
  (campo HP13, p. 4) lista so' -02:00, -03:00 e -04:00 e todos os exemplos sao
  -03:00 (Brasilia) -- aceitar +00:00 na SEFAZ nao esta verificado.

  DECISAO: o broker calcula o instante em UTC (LocalTimeToUniversal, que usa
  o MESMO deslocamento que Now, entao o resultado esta certo mesmo quando o
  RTL erra o fuso) e o escreve como hora de Brasilia com sufixo -03:00, fixo. O
  Brasil nao tem horario de verao desde 2019. Vale para qualquer autor de
  qualquer UF: e' um instante correto, no formato dos exemplos da NT. }

interface

const
  { Sufixo TZD escrito no dhEvento. }
  DFE_FUSO_BRASILIA = '-03:00';

{ Instante atual em UTC. }
function AgoraUtc: TDateTime;

{ UTC -> hora de parede de Brasilia (UTC-3). Pura, testavel. }
function UtcParaBrasilia(const AUtc: TDateTime): TDateTime;

{ Agora, como hora de parede de Brasilia: e' o que vai em dhEvento junto de
  DFE_FUSO_BRASILIA. }
function AgoraDeBrasilia: TDateTime;

implementation

uses
  SysUtils,
  DateUtils;

function AgoraUtc: TDateTime;
begin
  {$IFDEF FPC}
  Result := LocalTimeToUniversal(Now);
  {$ELSE}
  Result := TTimeZone.Local.ToUniversalTime(Now);
  {$ENDIF}
end;

function UtcParaBrasilia(const AUtc: TDateTime): TDateTime;
begin
  Result := AUtc - 3 / 24;
end;

function AgoraDeBrasilia: TDateTime;
begin
  Result := UtcParaBrasilia(AgoraUtc);
end;

end.
