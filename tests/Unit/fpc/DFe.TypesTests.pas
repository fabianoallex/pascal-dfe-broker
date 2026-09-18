unit DFe.TypesTests;

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry,
  DFe.Types;

type
  TDFeClassificarCStatTests = class(TTestCase)
  published
    procedure DocumentosLocalizados_138;
    procedure NenhumDocumento_137;
    procedure ServicoParalisadoMomentaneamente_108;
    procedure ServicoParalisadoSemPrevisao_109;
    procedure ConsumoIndevido_UsaCodigoDoProvider_Nfe_656;
    procedure ConsumoIndevido_UsaCodigoDoProvider_Mdfe_678;
    procedure CodigoDeOutroTipoDeDocumento_NaoConfundeComConsumoIndevido;
    procedure CodigoDesconhecido_NaoAssumeSucesso;
  end;

implementation

{ TDFeClassificarCStatTests }

procedure TDFeClassificarCStatTests.DocumentosLocalizados_138;
begin
  AssertEquals(Ord(dccDocumentosLocalizados), Ord(ClassificarCStat(138, 656)));
end;

procedure TDFeClassificarCStatTests.NenhumDocumento_137;
begin
  AssertEquals(Ord(dccNenhumDocumento), Ord(ClassificarCStat(137, 656)));
end;

procedure TDFeClassificarCStatTests.ServicoParalisadoMomentaneamente_108;
begin
  AssertEquals(Ord(dccServicoIndisponivel), Ord(ClassificarCStat(108, 656)));
end;

procedure TDFeClassificarCStatTests.ServicoParalisadoSemPrevisao_109;
begin
  AssertEquals(Ord(dccServicoIndisponivel), Ord(ClassificarCStat(109, 656)));
end;

procedure TDFeClassificarCStatTests.ConsumoIndevido_UsaCodigoDoProvider_Nfe_656;
begin
  AssertEquals(Ord(dccConsumoIndevido), Ord(ClassificarCStat(656, 656)));
end;

procedure TDFeClassificarCStatTests.ConsumoIndevido_UsaCodigoDoProvider_Mdfe_678;
begin
  AssertEquals(Ord(dccConsumoIndevido), Ord(ClassificarCStat(678, 678)));
end;

procedure TDFeClassificarCStatTests.CodigoDeOutroTipoDeDocumento_NaoConfundeComConsumoIndevido;
begin
  // Regressao do achado verificado contra as NTs oficiais -- ver o
  // comentario equivalente em ../DFe.TypesTests.pas (DUnitX).
  AssertEquals(Ord(dccDesconhecido), Ord(ClassificarCStat(678, 656)));
end;

procedure TDFeClassificarCStatTests.CodigoDesconhecido_NaoAssumeSucesso;
begin
  AssertEquals(Ord(dccDesconhecido), Ord(ClassificarCStat(999, 656)));
end;

initialization
  RegisterTest(TDFeClassificarCStatTests);

end.
