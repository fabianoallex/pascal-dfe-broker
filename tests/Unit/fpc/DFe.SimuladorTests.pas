unit DFe.SimuladorTests;

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils,
  DFe.Types,
  DFe.Simulador,
  DFe.Simulador.Fixtures,
  DFe.TestDoubles;

const
  CNPJ_A = '12345678000199';
  CNPJ_B = '11222333000181';
  UF_RS = 'RS';

type
  TDFeSimuladorTests = class(TTestCase)
  private
    FRelogio: TDFeRelogioFake;
    FSim: TDFeSimuladorSefaz;
    procedure PublicarNFes(const ACnpj: string; const AQuantidade: Integer);
    function Consultar(const AUltimoNSU: Int64; const ACnpj: string = CNPJ_A): TDFeRespostaSimulada;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure SemDocumentos_137ComNsuZero;
    procedure ComDocumentos_138EntregaEmOrdemAPartirDoCursor;
    procedure MaisDeCinquentaDocumentos_PaginaEmLotesDeCinquenta;
    procedure Apos137_ConsultaImediataEhConsumoIndevido;
    procedure Bloqueio_LiberaExatamenteApos1Hora;
    procedure Bloqueio_NaoEstendeNemEscalonaComConsultasRejeitadas;
    procedure Lote138_NaoBloqueia;
    procedure ConsumoIndevido_UsaCodigoConfiguravel_678Mdfe;
    procedure ContasSaoIndependentesPorCnpjEUf;
    procedure PularNSU_NoMeio_DeixaLacunaSemQuebrarMaxNSU;
    procedure PularNSU_NoFim_137AvancaCursorAteMaxNSU;
    procedure Falha_Indisponivel108e109_NaoBloqueiaNemAlteraEstado;
    procedure Falha_ConsumoIndevidoForcado_ForaDoBloqueio;
    procedure Falha_TimeoutErroHttpECorpoIlegivel_TiposDeTransporte;
    procedure Falhas_SaoConsumidasUmaPorConsultaNaOrdem;
    procedure Falha_DocZipCorrompido_ProcessaNormalEMarcaOFlagUmaVez;
    procedure Falha_NaoConsomeNsuNemAbreBloqueio;
    procedure Contadores_ConsultasEUltimoNsuRecebido;
  end;

implementation

{ TDFeSimuladorTests }

procedure TDFeSimuladorTests.SetUp;
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
  AssertTrue(R.Tipo = trsLote);
  AssertEquals(137, R.Lote.CStat);
  AssertEquals(0, Length(R.Lote.Itens));
  AssertEquals(Int64(0), R.Lote.UltimoNSU);
  AssertEquals(Int64(0), R.Lote.MaxNSU);
end;

procedure TDFeSimuladorTests.ComDocumentos_138EntregaEmOrdemAPartirDoCursor;
var
  R: TDFeRespostaSimulada;
begin
  PublicarNFes(CNPJ_A, 3);

  R := Consultar(0);
  AssertEquals(138, R.Lote.CStat);
  AssertEquals(3, Length(R.Lote.Itens));
  AssertEquals(Int64(1), R.Lote.Itens[0].NSU);
  AssertEquals(Int64(3), R.Lote.Itens[2].NSU);
  AssertEquals(Int64(3), R.Lote.UltimoNSU);
  AssertEquals(Int64(3), R.Lote.MaxNSU);
  AssertEquals(DFE_SIM_SCHEMA_RESNFE, R.Lote.Itens[0].Schema);

  R := Consultar(1); // cursor em 1: entrega 2 e 3
  AssertEquals(2, Length(R.Lote.Itens));
  AssertEquals(Int64(2), R.Lote.Itens[0].NSU);
end;

procedure TDFeSimuladorTests.MaisDeCinquentaDocumentos_PaginaEmLotesDeCinquenta;
var
  R: TDFeRespostaSimulada;
begin
  PublicarNFes(CNPJ_A, 120);

  R := Consultar(0);
  AssertEquals(138, R.Lote.CStat);
  AssertEquals(50, Length(R.Lote.Itens));
  AssertEquals(Int64(50), R.Lote.UltimoNSU);
  AssertEquals(Int64(120), R.Lote.MaxNSU); // UltimoNSU < MaxNSU => ha mais lotes

  R := Consultar(50);
  AssertEquals(50, Length(R.Lote.Itens));
  AssertEquals(Int64(100), R.Lote.UltimoNSU);

  R := Consultar(100);
  AssertEquals(20, Length(R.Lote.Itens));
  AssertEquals(Int64(120), R.Lote.UltimoNSU);

  R := Consultar(120);
  AssertEquals(137, R.Lote.CStat);
end;

procedure TDFeSimuladorTests.Apos137_ConsultaImediataEhConsumoIndevido;
var
  R: TDFeRespostaSimulada;
begin
  AssertEquals(137, Consultar(0).Lote.CStat);

  R := Consultar(0);
  AssertTrue(R.Tipo = trsLote);
  AssertEquals(656, R.Lote.CStat);
  AssertEquals(0, Length(R.Lote.Itens));
end;

procedure TDFeSimuladorTests.Bloqueio_LiberaExatamenteApos1Hora;
begin
  AssertEquals(137, Consultar(0).Lote.CStat);

  FRelogio.Agora := FRelogio.Agora + 59 / 1440; // +59 min
  AssertEquals(656, Consultar(0).Lote.CStat);

  FRelogio.Agora := FRelogio.Agora + 1 / 1440; // +60 min desde o 137
  AssertEquals(137, Consultar(0).Lote.CStat);
end;

procedure TDFeSimuladorTests.Bloqueio_NaoEstendeNemEscalonaComConsultasRejeitadas;
begin
  AssertEquals(137, Consultar(0).Lote.CStat); // bloqueio abre em T0

  FRelogio.Agora := FRelogio.Agora + 30 / 1440;
  AssertEquals(656, Consultar(0).Lote.CStat); // rejeitada em T0+30

  // Se a rejeicao reiniciasse o bloqueio, T0+60 ainda estaria bloqueado.
  FRelogio.Agora := FRelogio.Agora + 30 / 1440;
  AssertEquals(137, Consultar(0).Lote.CStat);
end;

procedure TDFeSimuladorTests.Lote138_NaoBloqueia;
begin
  PublicarNFes(CNPJ_A, 1);
  AssertEquals(138, Consultar(0).Lote.CStat);

  FSim.PublicarDocumento(CNPJ_A, UF_RS, DFE_SIM_SCHEMA_RESNFE,
    XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 2)));
  // sem avancar o relogio: 138 nao abre bloqueio
  AssertEquals(138, Consultar(1).Lote.CStat);
end;

procedure TDFeSimuladorTests.ConsumoIndevido_UsaCodigoConfiguravel_678Mdfe;
begin
  FSim.CodigoConsumoIndevido := 678;
  AssertEquals(137, Consultar(0).Lote.CStat);
  AssertEquals(678, Consultar(0).Lote.CStat);
end;

procedure TDFeSimuladorTests.ContasSaoIndependentesPorCnpjEUf;
var
  R: TDFeRespostaSimulada;
begin
  PublicarNFes(CNPJ_A, 2);

  AssertEquals(137, Consultar(0, CNPJ_B).Lote.CStat); // bloqueia so' a conta B
  AssertEquals(656, Consultar(0, CNPJ_B).Lote.CStat);

  R := Consultar(0, CNPJ_A); // A nao foi afetada e tem o proprio NSU
  AssertEquals(138, R.Lote.CStat);
  AssertEquals(Int64(2), R.Lote.MaxNSU);

  // mesmo CNPJ, outra UF, e' outra conta
  AssertEquals(137, FSim.Consultar(CNPJ_A, 'SP', 0).Lote.CStat);
  AssertEquals(Int64(0), FSim.NsuAtual(CNPJ_A, 'SP'));
end;

procedure TDFeSimuladorTests.PularNSU_NoMeio_DeixaLacunaSemQuebrarMaxNSU;
var
  R: TDFeRespostaSimulada;
begin
  FSim.PublicarDocumento(CNPJ_A, UF_RS, DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  FSim.PularNSU(CNPJ_A, UF_RS, 3); // NSU 2, 3 e 4 nao sao entregues
  FSim.PublicarDocumento(CNPJ_A, UF_RS, DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 2)));

  R := Consultar(0);
  AssertEquals(2, Length(R.Lote.Itens));
  AssertEquals(Int64(1), R.Lote.Itens[0].NSU);
  AssertEquals(Int64(5), R.Lote.Itens[1].NSU);
  AssertEquals(Int64(5), R.Lote.UltimoNSU);
  AssertEquals(Int64(5), R.Lote.MaxNSU);
end;

procedure TDFeSimuladorTests.PularNSU_NoFim_137AvancaCursorAteMaxNSU;
var
  R: TDFeRespostaSimulada;
begin
  PublicarNFes(CNPJ_A, 1);
  FSim.PularNSU(CNPJ_A, UF_RS, 2);

  R := Consultar(0);
  AssertEquals(138, R.Lote.CStat);
  AssertEquals(Int64(1), R.Lote.UltimoNSU);
  AssertEquals(Int64(3), R.Lote.MaxNSU);

  R := Consultar(1);
  AssertEquals(137, R.Lote.CStat);
  AssertEquals(Int64(3), R.Lote.UltimoNSU); // o cursor salta os NSU sem documento
end;

procedure TDFeSimuladorTests.Falha_Indisponivel108e109_NaoBloqueiaNemAlteraEstado;
var
  R: TDFeRespostaSimulada;
begin
  PublicarNFes(CNPJ_A, 1);

  FSim.EnfileirarFalha(fsIndisponivelCurtoPrazo);
  R := Consultar(0);
  AssertTrue(R.Tipo = trsLote);
  AssertEquals(108, R.Lote.CStat);
  AssertEquals(0, Length(R.Lote.Itens));

  FSim.EnfileirarFalha(fsIndisponivelSemPrevisao);
  AssertEquals(109, Consultar(0).Lote.CStat);

  // nada foi consumido nem bloqueado: a consulta seguinte ve o documento
  AssertEquals(138, Consultar(0).Lote.CStat);
end;

procedure TDFeSimuladorTests.Falha_ConsumoIndevidoForcado_ForaDoBloqueio;
begin
  PublicarNFes(CNPJ_A, 1);
  FSim.EnfileirarFalha(fsConsumoIndevido);
  AssertEquals(656, Consultar(0).Lote.CStat);
  AssertEquals(138, Consultar(0).Lote.CStat); // nao abriu bloqueio real
end;

procedure TDFeSimuladorTests.Falha_TimeoutErroHttpECorpoIlegivel_TiposDeTransporte;
begin
  FSim.EnfileirarFalha(fsTimeout);
  FSim.EnfileirarFalha(fsErroHttp);
  FSim.EnfileirarFalha(fsCorpoIlegivel);
  AssertTrue(Consultar(0).Tipo = trsTimeout);
  AssertTrue(Consultar(0).Tipo = trsErroHttp);
  AssertTrue(Consultar(0).Tipo = trsCorpoIlegivel);
  AssertTrue(Consultar(0).Tipo = trsLote);
end;

procedure TDFeSimuladorTests.Falhas_SaoConsumidasUmaPorConsultaNaOrdem;
begin
  FSim.EnfileirarFalha(fsIndisponivelCurtoPrazo);
  FSim.EnfileirarFalha(fsConsumoIndevido);
  AssertEquals(108, Consultar(0).Lote.CStat);
  AssertEquals(656, Consultar(0).Lote.CStat);
  AssertEquals(137, Consultar(0).Lote.CStat); // fila esgotada: comportamento normal
end;

procedure TDFeSimuladorTests.Falha_DocZipCorrompido_ProcessaNormalEMarcaOFlagUmaVez;
var
  R: TDFeRespostaSimulada;
begin
  PublicarNFes(CNPJ_A, 2);
  FSim.EnfileirarFalha(fsDocZipCorrompido);

  R := Consultar(0);
  AssertEquals(138, R.Lote.CStat);
  AssertEquals(2, Length(R.Lote.Itens));
  AssertTrue(R.DocZipCorrompido);

  R := Consultar(0);
  AssertFalse(R.DocZipCorrompido);
end;

procedure TDFeSimuladorTests.Falha_NaoConsomeNsuNemAbreBloqueio;
begin
  FSim.EnfileirarFalha(fsTimeout);
  AssertTrue(Consultar(0).Tipo = trsTimeout);
  AssertEquals(Int64(0), FSim.NsuAtual(CNPJ_A, UF_RS));
  AssertEquals(137, Consultar(0).Lote.CStat); // primeiro 137 de verdade, nao 656
end;

procedure TDFeSimuladorTests.Contadores_ConsultasEUltimoNsuRecebido;
begin
  FSim.EnfileirarFalha(fsTimeout);
  Consultar(7);
  Consultar(9);
  AssertEquals(2, FSim.TotalConsultas);
  AssertEquals(Int64(9), FSim.UltimoNSURecebido);
end;

initialization
  RegisterTest(TDFeSimuladorTests);

end.
