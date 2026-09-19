unit DFe.FusoTests;

{ DFe.Fuso: hora do evento independente do fuso do sistema. Espelho DUnitX em
  tests/Unit/DFe.FusoTests.pas (mesmos casos). }

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils, DateUtils,
  DFe.Fuso;

type
  TDFeFusoTests = class(TTestCase)
  published
    procedure Sufixo_EBrasilia;
    procedure UtcParaBrasilia_SubtraiTresHoras;
    procedure UtcParaBrasilia_AtravessaMeiaNoite;
    procedure UtcParaBrasilia_AtravessaViradaDeAno;
    procedure AgoraDeBrasilia_EAgoraUtcMenosTresHoras;
    procedure AgoraUtc_DifereDeNowPorUmFusoValido;
  end;

implementation

procedure TDFeFusoTests.Sufixo_EBrasilia;
begin
  AssertEquals('-03:00', DFE_FUSO_BRASILIA);
end;

procedure TDFeFusoTests.UtcParaBrasilia_SubtraiTresHoras;
begin
  AssertTrue(SameDateTime(EncodeDateTime(2026, 9, 18, 9, 28, 31, 0),
    UtcParaBrasilia(EncodeDateTime(2026, 9, 18, 12, 28, 31, 0))));
end;

procedure TDFeFusoTests.UtcParaBrasilia_AtravessaMeiaNoite;
begin
  // 01:30 UTC de 19/09 ainda e' 22:30 de 18/09 em Brasilia
  AssertTrue(SameDateTime(EncodeDateTime(2026, 9, 18, 22, 30, 0, 0),
    UtcParaBrasilia(EncodeDateTime(2026, 9, 19, 1, 30, 0, 0))));
end;

procedure TDFeFusoTests.UtcParaBrasilia_AtravessaViradaDeAno;
begin
  AssertTrue(SameDateTime(EncodeDateTime(2026, 12, 31, 23, 0, 0, 0),
    UtcParaBrasilia(EncodeDateTime(2027, 1, 1, 2, 0, 0, 0))));
end;

procedure TDFeFusoTests.AgoraDeBrasilia_EAgoraUtcMenosTresHoras;
var
  LUtc, LBr: TDateTime;
begin
  LUtc := AgoraUtc;
  LBr := AgoraDeBrasilia;
  // duas leituras do relogio: tolera alguns segundos entre elas
  AssertTrue(Abs((LUtc - 3 / 24) - LBr) < 5 / 86400);
end;

procedure TDFeFusoTests.AgoraUtc_DifereDeNowPorUmFusoValido;
var
  LMinutos: Int64;
begin
  // Now - AgoraUtc e' o deslocamento do sistema: multiplo de 15 min, |x| <= 14h.
  // (Nao afirma QUAL fuso -- o RTL do FPC/Linux pode dar 0; so' que e' um fuso.)
  LMinutos := Round((Now - AgoraUtc) * 24 * 60);
  AssertTrue('multiplo de 15 min', (LMinutos mod 15) = 0);
  AssertTrue('dentro de +-14h', Abs(LMinutos) <= 14 * 60);
end;

initialization
  RegisterTest(TDFeFusoTests);

end.
