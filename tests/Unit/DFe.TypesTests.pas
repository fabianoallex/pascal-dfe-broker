unit DFe.TypesTests;

interface

uses
  DUnitX.TestFramework,
  DFe.Types;

type
  [TestFixture]
  TDFeClassificarCStatTests = class
  public
    [Test] procedure DocumentosLocalizados_138;
    [Test] procedure NenhumDocumento_137;
    [Test] procedure ServicoParalisadoMomentaneamente_108;
    [Test] procedure ServicoParalisadoSemPrevisao_109;
    [Test] procedure ConsumoIndevido_UsaCodigoDoProvider_Nfe_656;
    [Test] procedure ConsumoIndevido_UsaCodigoDoProvider_Mdfe_678;
    [Test] procedure CodigoDeOutroTipoDeDocumento_NaoConfundeComConsumoIndevido;
    [Test] procedure CodigoDesconhecido_NaoAssumeSucesso;
  end;

implementation

{ TDFeClassificarCStatTests }

procedure TDFeClassificarCStatTests.DocumentosLocalizados_138;
begin
  Assert.AreEqual(Ord(dccDocumentosLocalizados), Ord(ClassificarCStat(138, 656)));
end;

procedure TDFeClassificarCStatTests.NenhumDocumento_137;
begin
  Assert.AreEqual(Ord(dccNenhumDocumento), Ord(ClassificarCStat(137, 656)));
end;

procedure TDFeClassificarCStatTests.ServicoParalisadoMomentaneamente_108;
begin
  Assert.AreEqual(Ord(dccServicoIndisponivel), Ord(ClassificarCStat(108, 656)));
end;

procedure TDFeClassificarCStatTests.ServicoParalisadoSemPrevisao_109;
begin
  Assert.AreEqual(Ord(dccServicoIndisponivel), Ord(ClassificarCStat(109, 656)));
end;

procedure TDFeClassificarCStatTests.ConsumoIndevido_UsaCodigoDoProvider_Nfe_656;
begin
  Assert.AreEqual(Ord(dccConsumoIndevido), Ord(ClassificarCStat(656, 656)));
end;

procedure TDFeClassificarCStatTests.ConsumoIndevido_UsaCodigoDoProvider_Mdfe_678;
begin
  Assert.AreEqual(Ord(dccConsumoIndevido), Ord(ClassificarCStat(678, 678)));
end;

procedure TDFeClassificarCStatTests.CodigoDeOutroTipoDeDocumento_NaoConfundeComConsumoIndevido;
begin
  // Regressao do achado verificado contra as NTs oficiais (ver
  // docs/referencias/README.md): 678 e' consumo indevido para MDF-e, mas
  // NAO para um provider configurado com o codigo do NFe/CT-e (656) --
  // ClassificarCStat nao pode assumir um numero universal de consumo
  // indevido entre tipos de documento.
  Assert.AreEqual(Ord(dccDesconhecido), Ord(ClassificarCStat(678, 656)));
end;

procedure TDFeClassificarCStatTests.CodigoDesconhecido_NaoAssumeSucesso;
begin
  Assert.AreEqual(Ord(dccDesconhecido), Ord(ClassificarCStat(999, 656)));
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeClassificarCStatTests);

end.
