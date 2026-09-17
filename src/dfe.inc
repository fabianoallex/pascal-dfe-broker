{ Diretivas de compilacao compartilhadas (dual Delphi / Free Pascal).

  Cada unit do projeto inclui este arquivo logo apos o 'unit ...;', no mesmo
  padrao do amqp.inc do projeto-base (pascal-amqp-faa). No Delphi ele nao tem
  efeito; no FPC ativa o mode Delphi (strings longas, advanced records,
  generics estilo Delphi, type helpers).

  DFE_WINDOWS: definido quando o alvo e' Windows, em qualquer compilador
  (Delphi define MSWINDOWS; FPC define WINDOWS). }

{$IFDEF FPC}
  {$MODE DELPHI}
  {$H+}
{$ENDIF}

{$IFDEF MSWINDOWS}
  {$DEFINE DFE_WINDOWS}
{$ENDIF}
{$IFDEF WINDOWS}
  {$IFNDEF DFE_WINDOWS}
    {$DEFINE DFE_WINDOWS}
  {$ENDIF}
{$ENDIF}
