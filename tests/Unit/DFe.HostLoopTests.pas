unit DFe.HostLoopTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  DFe.Orquestrador,
  DFe.Host.Loop,
  DFe.TestDoubles;

type
  [TestFixture]
  TDFeHostLoopTests = class
  private
    FOrquestrador: TDFeOrquestrador;
    FPublicador: TDFePublicadorFake;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure Tick_ChamaExecutarCicloDoOrquestrador;
    [Test] procedure Executar_ChamaTickImediatamenteAoEntrar;
    [Test] procedure Executar_ParaAposPararSerChamado;
  end;

implementation

{ TDFeHostLoopTests }

procedure TDFeHostLoopTests.Setup;
begin
  FPublicador := TDFePublicadorFake.Create;
  FOrquestrador := TDFeOrquestrador.Create(FPublicador);
end;

procedure TDFeHostLoopTests.TearDown;
begin
  FOrquestrador.Free;
end;

procedure TDFeHostLoopTests.Tick_ChamaExecutarCicloDoOrquestrador;
var
  LClient: TDFeDistribuicaoClientFake;
  LCursorStore: TDFeCursorStoreFake;
  LUnidade: TDFeUnidadeTrabalho;
  LLoop: TDFeHostLoop;
begin
  LClient := TDFeDistribuicaoClientFake.Create;
  LClient.AdicionarLote(LoteTeste(137, 0, 0));
  LCursorStore := TDFeCursorStoreFake.Create;
  LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), LClient, CertificadoTeste, LCursorStore);
  FOrquestrador.AdicionarUnidade(LUnidade);

  LLoop := TDFeHostLoop.Create(FOrquestrador);
  try
    LLoop.Tick;
  finally
    LLoop.Free;
  end;

  Assert.AreEqual(1, LClient.Chamadas);
end;

procedure TDFeHostLoopTests.Executar_ChamaTickImediatamenteAoEntrar;
var
  LLoop: TDFeHostLoopTestavel;
begin
  LLoop := TDFeHostLoopTestavel.Create(FOrquestrador, 60);
  try
    LLoop.PararAposTicks := 1;
    LLoop.Executar;

    Assert.AreEqual(1, LLoop.Ticks);
  finally
    LLoop.Free;
  end;
end;

procedure TDFeHostLoopTests.Executar_ParaAposPararSerChamado;
var
  LLoop: TDFeHostLoopTestavel;
begin
  LLoop := TDFeHostLoopTestavel.Create(FOrquestrador, 1);
  try
    LLoop.PararAposTicks := 3;
    LLoop.Executar;

    Assert.AreEqual(3, LLoop.Ticks);
  finally
    LLoop.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeHostLoopTests);

end.
