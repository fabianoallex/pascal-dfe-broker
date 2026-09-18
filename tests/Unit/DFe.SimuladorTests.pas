unit DFe.SimuladorTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  DFe.Types,
  DFe.Simulador,
  DFe.Simulador.Fixtures,
  DFe.TestDoubles;

const
  CNPJ_A = '12345678000199';
  CNPJ_B = '11222333000181';
  UF_RS = 'RS';

type
  [TestFixture]
  TDFeSimuladorTests = class
  private
    FRelogio: TDFeRelogioFake;
    FSim: TDFeSimuladorSefaz;
    procedure PublicarNFes(const ACnpj: string; const AQuantidade: Integer);
    function Consultar(const AUltimoNSU: Int64; const ACnpj: string = CNPJ_A): TDFeRespostaSimulada;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure SemDocumentos_137ComNsuZero;
    [Test] procedure ComDocumentos_138EntregaEmOrdemAPartirDoCursor;
    [Test] procedure MaisDeCinquentaDocumentos_PaginaEmLotesDeCinquenta;
    [Test] procedure Apos137_ConsultaImediataEhConsumoIndevido;
    [Test] procedure Bloqueio_LiberaExatamenteApos1Hora;
    [Test] procedure Bloqueio_NaoEstendeNemEscalonaComConsultasRejeitadas;
    [Test] procedure Lote138_NaoBloqueia;
    [Test] procedure ConsumoIndevido_UsaCodigoConfiguravel_678Mdfe;
    [Test] procedure ContasSaoIndependentesPorCnpjEUf;
    [Test] procedure PularNSU_NoMeio_DeixaLacunaSemQuebrarMaxNSU;
    [Test] procedure PularNSU_NoFim_137AvancaCursorAteMaxNSU;
    [Test] procedure Falha_Indisponivel108e109_NaoBloqueiaNemAlteraEstado;
    [Test] procedure Falha_ConsumoIndevidoForcado_ForaDoBloqueio;
    [Test] procedure Falha_TimeoutErroHttpECorpoIlegivel_TiposDeTransporte;
    [Test] procedure Falhas_SaoConsumidasUmaPorConsultaNaOrdem;
    [Test] procedure Falha_DocZipCorrompido_ProcessaNormalEMarcaOFlagUmaVez;
    [Test] procedure Falha_NaoConsomeNsuNemAbreBloqueio;
    [Test] procedure Contadores_ConsultasEUltimoNsuRecebido;
  end;

implementation

{ TDFeSimuladorTests }

procedure TDFeSimuladorTests.Setup;
begin
  FRelogio := TDFeRelogioFake.Create;
  FRelogio.Agora := EncodeDate(2026, 9, 18) + EncodeTime(10, 0, 0, 0);
  FSim := TDFeSimuladorSefaz.Create(FRelogio.ObterAgora);
end;

procedure TDFeSimuladorTests.TearDown;
begin
  FSim.Free;
  FRelogio.Free;
end;

procedure TDFeSimuladorTests.PublicarNFes(const ACnpj: string; const AQuantidade: Integer);
var
  I: Integer;
begin
  for I := 1 to AQuantidade do
    FSim.PublicarDocumento(ACnpj, UF_RS, DFE_SIM_SCHEMA_RESNFE,
      XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, I)));
end;

function TDFeSimuladorTests.Consultar(const AUltimoNSU: Int64; const ACnpj: string): TDFeRespostaSimulada;
begin
  Result := FSim.Consultar(ACnpj, UF_RS, AUltimoNSU);
end;

procedure TDFeSimuladorTests.SemDocumentos_137ComNsuZero;
var
  R: TDFeRespostaSimulada;
begin
  R := Consultar(0);
  Assert.IsTrue(R.Tipo = trsLote);
  Assert.AreEqual(137, R.Lote.CStat);
  Assert.AreEqual(0, Integer(Length(R.Lote.Itens)));
  Assert.AreEqual(Int64(0), R.Lote.UltimoNSU);
  Assert.AreEqual(Int64(0), R.Lote.MaxNSU);
end;

procedure TDFeSimuladorTests.ComDocumentos_138EntregaEmOrdemAPartirDoCursor;
var
  R: TDFeRespostaSimulada;
begin
  PublicarNFes(CNPJ_A, 3);

  R := Consultar(0);
  Assert.AreEqual(138, R.Lote.CStat);
  Assert.AreEqual(3, Integer(Length(R.Lote.Itens)));
  Assert.AreEqual(Int64(1), R.Lote.Itens[0].NSU);
  Assert.AreEqual(Int64(3), R.Lote.Itens[2].NSU);
  Assert.AreEqual(Int64(3), R.Lote.UltimoNSU);
  Assert.AreEqual(Int64(3), R.Lote.MaxNSU);
  Assert.AreEqual(DFE_SIM_SCHEMA_RESNFE, R.Lote.Itens[0].Schema);

  R := Consultar(1); // cursor em 1: entrega 2 e 3
  Assert.AreEqual(2, Integer(Length(R.Lote.Itens)));
  Assert.AreEqual(Int64(2), R.Lote.Itens[0].NSU);
end;

procedure TDFeSimuladorTests.MaisDeCinquentaDocumentos_PaginaEmLotesDeCinquenta;
var
  R: TDFeRespostaSimulada;
begin
  PublicarNFes(CNPJ_A, 120);

  R := Consultar(0);
  Assert.AreEqual(138, R.Lote.CStat);
  Assert.AreEqual(50, Integer(Length(R.Lote.Itens)));
  Assert.AreEqual(Int64(50), R.Lote.UltimoNSU);
  Assert.AreEqual(Int64(120), R.Lote.MaxNSU); // UltimoNSU < MaxNSU => ha mais lotes

  R := Consultar(50);
  Assert.AreEqual(50, Integer(Length(R.Lote.Itens)));
  Assert.AreEqual(Int64(100), R.Lote.UltimoNSU);

  R := Consultar(100);
  Assert.AreEqual(20, Integer(Length(R.Lote.Itens)));
  Assert.AreEqual(Int64(120), R.Lote.UltimoNSU);

  R := Consultar(120);
  Assert.AreEqual(137, R.Lote.CStat);
end;

procedure TDFeSimuladorTests.Apos137_ConsultaImediataEhConsumoIndevido;
var
  R: TDFeRespostaSimulada;
begin
  Assert.AreEqual(137, Consultar(0).Lote.CStat);

  R := Consultar(0);
  Assert.IsTrue(R.Tipo = trsLote);
  Assert.AreEqual(656, R.Lote.CStat);
  Assert.AreEqual(0, Integer(Length(R.Lote.Itens)));
end;

procedure TDFeSimuladorTests.Bloqueio_LiberaExatamenteApos1Hora;
begin
  Assert.AreEqual(137, Consultar(0).Lote.CStat);

  FRelogio.Agora := FRelogio.Agora + 59 / 1440; // +59 min
  Assert.AreEqual(656, Consultar(0).Lote.CStat);

  FRelogio.Agora := FRelogio.Agora + 1 / 1440; // +60 min desde o 137
  Assert.AreEqual(137, Consultar(0).Lote.CStat);
end;

procedure TDFeSimuladorTests.Bloqueio_NaoEstendeNemEscalonaComConsultasRejeitadas;
begin
  Assert.AreEqual(137, Consultar(0).Lote.CStat); // bloqueio abre em T0

  FRelogio.Agora := FRelogio.Agora + 30 / 1440;
  Assert.AreEqual(656, Consultar(0).Lote.CStat); // rejeitada em T0+30

  // Se a rejeicao reiniciasse o bloqueio, T0+60 ainda estaria bloqueado.
  FRelogio.Agora := FRelogio.Agora + 30 / 1440;
  Assert.AreEqual(137, Consultar(0).Lote.CStat);
end;

procedure TDFeSimuladorTests.Lote138_NaoBloqueia;
begin
  PublicarNFes(CNPJ_A, 1);
  Assert.AreEqual(138, Consultar(0).Lote.CStat);

  FSim.PublicarDocumento(CNPJ_A, UF_RS, DFE_SIM_SCHEMA_RESNFE,
    XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 2)));
  // sem avancar o relogio: 138 nao abre bloqueio
  Assert.AreEqual(138, Consultar(1).Lote.CStat);
end;

procedure TDFeSimuladorTests.ConsumoIndevido_UsaCodigoConfiguravel_678Mdfe;
begin
  FSim.CodigoConsumoIndevido := 678;
  Assert.AreEqual(137, Consultar(0).Lote.CStat);
  Assert.AreEqual(678, Consultar(0).Lote.CStat);
end;

procedure TDFeSimuladorTests.ContasSaoIndependentesPorCnpjEUf;
var
  R: TDFeRespostaSimulada;
begin
  PublicarNFes(CNPJ_A, 2);

  Assert.AreEqual(137, Consultar(0, CNPJ_B).Lote.CStat); // bloqueia so' a conta B
  Assert.AreEqual(656, Consultar(0, CNPJ_B).Lote.CStat);

  R := Consultar(0, CNPJ_A); // A nao foi afetada e tem o proprio NSU
  Assert.AreEqual(138, R.Lote.CStat);
  Assert.AreEqual(Int64(2), R.Lote.MaxNSU);

  // mesmo CNPJ, outra UF, e' outra conta
  Assert.AreEqual(137, FSim.Consultar(CNPJ_A, 'SP', 0).Lote.CStat);
  Assert.AreEqual(Int64(0), FSim.NsuAtual(CNPJ_A, 'SP'));
end;

procedure TDFeSimuladorTests.PularNSU_NoMeio_DeixaLacunaSemQuebrarMaxNSU;
var
  R: TDFeRespostaSimulada;
begin
  FSim.PublicarDocumento(CNPJ_A, UF_RS, DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  FSim.PularNSU(CNPJ_A, UF_RS, 3); // NSU 2, 3 e 4 nao sao entregues
  FSim.PublicarDocumento(CNPJ_A, UF_RS, DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 2)));

  R := Consultar(0);
  Assert.AreEqual(2, Integer(Length(R.Lote.Itens)));
  Assert.AreEqual(Int64(1), R.Lote.Itens[0].NSU);
  Assert.AreEqual(Int64(5), R.Lote.Itens[1].NSU);
  Assert.AreEqual(Int64(5), R.Lote.UltimoNSU);
  Assert.AreEqual(Int64(5), R.Lote.MaxNSU);
end;

procedure TDFeSimuladorTests.PularNSU_NoFim_137AvancaCursorAteMaxNSU;
var
  R: TDFeRespostaSimulada;
begin
  PublicarNFes(CNPJ_A, 1);
  FSim.PularNSU(CNPJ_A, UF_RS, 2);

  R := Consultar(0);
  Assert.AreEqual(138, R.Lote.CStat);
  Assert.AreEqual(Int64(1), R.Lote.UltimoNSU);
  Assert.AreEqual(Int64(3), R.Lote.MaxNSU);

  R := Consultar(1);
  Assert.AreEqual(137, R.Lote.CStat);
  Assert.AreEqual(Int64(3), R.Lote.UltimoNSU); // o cursor salta os NSU sem documento
end;

procedure TDFeSimuladorTests.Falha_Indisponivel108e109_NaoBloqueiaNemAlteraEstado;
var
  R: TDFeRespostaSimulada;
begin
  PublicarNFes(CNPJ_A, 1);

  FSim.EnfileirarFalha(fsIndisponivelCurtoPrazo);
  R := Consultar(0);
  Assert.IsTrue(R.Tipo = trsLote);
  Assert.AreEqual(108, R.Lote.CStat);
  Assert.AreEqual(0, Integer(Length(R.Lote.Itens)));

  FSim.EnfileirarFalha(fsIndisponivelSemPrevisao);
  Assert.AreEqual(109, Consultar(0).Lote.CStat);

  // nada foi consumido nem bloqueado: a consulta seguinte ve o documento
  Assert.AreEqual(138, Consultar(0).Lote.CStat);
end;

procedure TDFeSimuladorTests.Falha_ConsumoIndevidoForcado_ForaDoBloqueio;
begin
  PublicarNFes(CNPJ_A, 1);
  FSim.EnfileirarFalha(fsConsumoIndevido);
  Assert.AreEqual(656, Consultar(0).Lote.CStat);
  Assert.AreEqual(138, Consultar(0).Lote.CStat); // nao abriu bloqueio real
end;

procedure TDFeSimuladorTests.Falha_TimeoutErroHttpECorpoIlegivel_TiposDeTransporte;
begin
  FSim.EnfileirarFalha(fsTimeout);
  FSim.EnfileirarFalha(fsErroHttp);
  FSim.EnfileirarFalha(fsCorpoIlegivel);
  Assert.IsTrue(Consultar(0).Tipo = trsTimeout);
  Assert.IsTrue(Consultar(0).Tipo = trsErroHttp);
  Assert.IsTrue(Consultar(0).Tipo = trsCorpoIlegivel);
  Assert.IsTrue(Consultar(0).Tipo = trsLote);
end;

procedure TDFeSimuladorTests.Falhas_SaoConsumidasUmaPorConsultaNaOrdem;
begin
  FSim.EnfileirarFalha(fsIndisponivelCurtoPrazo);
  FSim.EnfileirarFalha(fsConsumoIndevido);
  Assert.AreEqual(108, Consultar(0).Lote.CStat);
  Assert.AreEqual(656, Consultar(0).Lote.CStat);
  Assert.AreEqual(137, Consultar(0).Lote.CStat); // fila esgotada: comportamento normal
end;

procedure TDFeSimuladorTests.Falha_DocZipCorrompido_ProcessaNormalEMarcaOFlagUmaVez;
var
  R: TDFeRespostaSimulada;
begin
  PublicarNFes(CNPJ_A, 2);
  FSim.EnfileirarFalha(fsDocZipCorrompido);

  R := Consultar(0);
  Assert.AreEqual(138, R.Lote.CStat);
  Assert.AreEqual(2, Integer(Length(R.Lote.Itens)));
  Assert.IsTrue(R.DocZipCorrompido);

  R := Consultar(0);
  Assert.IsFalse(R.DocZipCorrompido);
end;

procedure TDFeSimuladorTests.Falha_NaoConsomeNsuNemAbreBloqueio;
begin
  FSim.EnfileirarFalha(fsTimeout);
  Assert.IsTrue(Consultar(0).Tipo = trsTimeout);
  Assert.AreEqual(Int64(0), FSim.NsuAtual(CNPJ_A, UF_RS));
  Assert.AreEqual(137, Consultar(0).Lote.CStat); // primeiro 137 de verdade, nao 656
end;

procedure TDFeSimuladorTests.Contadores_ConsultasEUltimoNsuRecebido;
begin
  FSim.EnfileirarFalha(fsTimeout);
  Consultar(7);
  Consultar(9);
  Assert.AreEqual(2, FSim.TotalConsultas);
  Assert.AreEqual(Int64(9), FSim.UltimoNSURecebido);
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeSimuladorTests);

end.
