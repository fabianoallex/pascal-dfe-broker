unit DFe.FusoTests;

{ Espelho DUnitX de tests/Unit/fpc/DFe.FusoTests.pas (mesmos casos). }

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.DateUtils,
  DFe.Fuso;

type
  [TestFixture]
  TDFeFusoTests = class
  public
    [Test] procedure Sufixo_EBrasilia;
    [Test] procedure UtcParaBrasilia_SubtraiTresHoras;
    [Test] procedure UtcParaBrasilia_AtravessaMeiaNoite;
    [Test] procedure UtcParaBrasilia_AtravessaViradaDeAno;
    [Test] procedure AgoraDeBrasilia_EAgoraUtcMenosTresHoras;
    [Test] procedure AgoraUtc_DifereDeNowPorUmFusoValido;
  end;

implementation

procedure TDFeFusoTests.Sufixo_EBrasilia;
begin
  Assert.AreEqual('-03:00', DFE_FUSO_BRASILIA);
end;

procedure TDFeFusoTests.UtcParaBrasilia_SubtraiTresHoras;
begin
  Assert.IsTrue(SameDateTime(EncodeDateTime(2026, 9, 18, 9, 28, 31, 0),
    UtcParaBrasilia(EncodeDateTime(2026, 9, 18, 12, 28, 31, 0))));
end;

procedure TDFeFusoTests.UtcParaBrasilia_AtravessaMeiaNoite;
begin
  Assert.IsTrue(SameDateTime(EncodeDateTime(2026, 9, 18, 22, 30, 0, 0),
    UtcParaBrasilia(EncodeDateTime(2026, 9, 19, 1, 30, 0, 0))));
end;

procedure TDFeFusoTests.UtcParaBrasilia_AtravessaViradaDeAno;
begin
  Assert.IsTrue(SameDateTime(EncodeDateTime(2026, 12, 31, 23, 0, 0, 0),
    UtcParaBrasilia(EncodeDateTime(2027, 1, 1, 2, 0, 0, 0))));
end;

procedure TDFeFusoTests.AgoraDeBrasilia_EAgoraUtcMenosTresHoras;
var
  LUtc, LBr: TDateTime;
begin
  LUtc := AgoraUtc;
  LBr := AgoraDeBrasilia;
  Assert.IsTrue(Abs((LUtc - 3 / 24) - LBr) < 5 / 86400);
end;

procedure TDFeFusoTests.AgoraUtc_DifereDeNowPorUmFusoValido;
var
  LMinutos: Int64;
begin
  LMinutos := Round((Now - AgoraUtc) * 24 * 60);
  Assert.IsTrue((LMinutos mod 15) = 0, 'multiplo de 15 min');
  Assert.IsTrue(Abs(LMinutos) <= 14 * 60, 'dentro de +-14h');
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeFusoTests);

end.
