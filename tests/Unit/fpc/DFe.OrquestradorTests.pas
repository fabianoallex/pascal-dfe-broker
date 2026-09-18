unit DFe.OrquestradorTests;

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils,
  DFe.Types,
  DFe.Errors,
  DFe.Provider,
  DFe.Orquestrador,
  DFe.TestDoubles;

const
  NAMESPACE_TESTE = 'nfe/12345678000199/rs';

type
  TDFeOrquestradorTests = class(TTestCase)
  private
    FOrquestrador: TDFeOrquestradorTestavel;
    FPublicador: TDFePublicadorFake;
    FCursorStore: TDFeCursorStoreFake;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure UnidadePausada_NaoConsulta;
    procedure ProximaConsultaNoFuturo_NaoConsulta;
    procedure DocumentosLocalizados_PublicaEAvancaCursorEReagenda;
    procedure NenhumDocumento_NaoPublicaMasAvancaEReagenda;
    procedure ConsumoIndevido_ReagendaSemAvancarCursor;
    procedure ComunicacaoFalhou_ReagendaSemPausarNemAvancarCursor;
    procedure CertificadoInvalido_Pausa;
    procedure RespostaInvalida_NaoPausaERegistraErro;
    procedure MultiplosLotes_ContinuaAteAlcancarMaxNSU;
    procedure UnidadeComExcecaoNaoModelada_NaoDerrubaOutrasUnidades;
  end;

implementation

function CertificadoTeste: TDFeCertificado;
begin
  Result.Identificador := 'teste';
  Result.CnpjCpf := '12345678000199';
  Result.UF := 'RS';
end;

function LoteTeste(const ACStat: Integer; const AUltimoNSU, AMaxNSU: Int64): TDFeLoteBruto;
begin
  Result.CStat := ACStat;
  Result.XMotivo := '';
  Result.UltimoNSU := AUltimoNSU;
  Result.MaxNSU := AMaxNSU;
  Result.Itens := nil;
end;

function EventoTeste: TDFeEventoNormalizado;
begin
  Result.TipoDocumento := 'nfe';
  Result.Categoria := dcDocumento;
  Result.TipoEvento := '';
  Result.ChaveAcesso := '';
  Result.CnpjCpfConsultante := '12345678000199';
  Result.UF := 'RS';
  Result.NSU := 0;
  Result.XmlPayload := '<xml/>';
  Result.DataEmissao := 0;
end;

{ TDFeOrquestradorTests }

procedure TDFeOrquestradorTests.SetUp;
begin
  FPublicador := TDFePublicadorFake.Create;
  FCursorStore := TDFeCursorStoreFake.Create;
  FOrquestrador := TDFeOrquestradorTestavel.Create(FPublicador);
  FOrquestrador.AgoraSimulado := EncodeDate(2026, 1, 1);
end;

procedure TDFeOrquestradorTests.TearDown;
begin
  FOrquestrador.Free;
  // FPublicador/FCursorStore sao interfaces (IDFePublicador/IDFeCursorStore)
  // seguradas tambem pelo orquestrador/unidades -- liberadas por refcount.
end;

procedure TDFeOrquestradorTests.UnidadePausada_NaoConsulta;
var
  LClient: TDFeDistribuicaoClientFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LClient := TDFeDistribuicaoClientFake.Create;
  LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), LClient, CertificadoTeste, FCursorStore);
  LUnidade.Pausada := True;
  FOrquestrador.AdicionarUnidade(LUnidade);

  FOrquestrador.ExecutarCiclo;

  AssertEquals(0, LClient.Chamadas);
end;

procedure TDFeOrquestradorTests.ProximaConsultaNoFuturo_NaoConsulta;
var
  LClient: TDFeDistribuicaoClientFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LClient := TDFeDistribuicaoClientFake.Create;
  LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), LClient, CertificadoTeste, FCursorStore);
  LUnidade.ProximaConsultaEm := FOrquestrador.AgoraSimulado + 1;
  FOrquestrador.AdicionarUnidade(LUnidade);

  FOrquestrador.ExecutarCiclo;

  AssertEquals(0, LClient.Chamadas);
end;

procedure TDFeOrquestradorTests.DocumentosLocalizados_PublicaEAvancaCursorEReagenda;
var
  LClient: TDFeDistribuicaoClientFake;
  LProvider: TDFeProviderFake;
  LUnidade: TDFeUnidadeTrabalho;
  LAgoraAntes: TDateTime;
  LEventos: TDFeEventoNormalizadoArray;
begin
  LClient := TDFeDistribuicaoClientFake.Create;
  LClient.AdicionarLote(LoteTeste(138, 500, 500));
  LProvider := TDFeProviderFake.Create('nfe');
  SetLength(LEventos, 1);
  LEventos[0] := EventoTeste;
  LProvider.EventosADevolver := LEventos;
  LUnidade := TDFeUnidadeTrabalho.Create(LProvider, LClient, CertificadoTeste, FCursorStore);
  FOrquestrador.AdicionarUnidade(LUnidade);
  LAgoraAntes := FOrquestrador.AgoraSimulado;

  FOrquestrador.ExecutarCiclo;

  AssertEquals(1, FPublicador.Quantidade);
  AssertEquals('nfe.documento.rs.12345678000199', FPublicador.RoutingKey(0));
  AssertEquals(Int64(500), FCursorStore.ObterUltimoNSU(NAMESPACE_TESTE));
  AssertEquals(Double(LAgoraAntes + (DFE_INTERVALO_BASE_SEGUNDOS_PADRAO / SecsPerDay)), Double(LUnidade.ProximaConsultaEm), 1 / SecsPerDay);
end;

procedure TDFeOrquestradorTests.NenhumDocumento_NaoPublicaMasAvancaEReagenda;
var
  LClient: TDFeDistribuicaoClientFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LClient := TDFeDistribuicaoClientFake.Create;
  LClient.AdicionarLote(LoteTeste(137, 0, 0));
  LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), LClient, CertificadoTeste, FCursorStore);
  FOrquestrador.AdicionarUnidade(LUnidade);

  FOrquestrador.ExecutarCiclo;

  AssertEquals(0, FPublicador.Quantidade);
  AssertEquals(1, LClient.Chamadas);
end;

procedure TDFeOrquestradorTests.ConsumoIndevido_ReagendaSemAvancarCursor;
var
  LClient: TDFeDistribuicaoClientFake;
  LProvider: TDFeProviderFake;
  LUnidade: TDFeUnidadeTrabalho;
  LAgoraAntes: TDateTime;
begin
  FCursorStore.GravarUltimoNSU(NAMESPACE_TESTE, 999);
  LClient := TDFeDistribuicaoClientFake.Create;
  LClient.AdicionarLote(LoteTeste(656, 0, 0));
  LProvider := TDFeProviderFake.Create('nfe', 656);
  LUnidade := TDFeUnidadeTrabalho.Create(LProvider, LClient, CertificadoTeste, FCursorStore);
  FOrquestrador.AdicionarUnidade(LUnidade);
  LAgoraAntes := FOrquestrador.AgoraSimulado;

  FOrquestrador.ExecutarCiclo;

  AssertEquals(Int64(999), FCursorStore.ObterUltimoNSU(NAMESPACE_TESTE));
  AssertEquals(0, FPublicador.Quantidade);
  AssertEquals(Double(LAgoraAntes + (DFE_INTERVALO_BASE_SEGUNDOS_PADRAO / SecsPerDay)), Double(LUnidade.ProximaConsultaEm), 1 / SecsPerDay);
  AssertTrue(FOrquestrador.QuantidadeAvisos > 0);
end;

procedure TDFeOrquestradorTests.ComunicacaoFalhou_ReagendaSemPausarNemAvancarCursor;
var
  LClient: TDFeDistribuicaoClientFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  FCursorStore.GravarUltimoNSU(NAMESPACE_TESTE, 111);
  LClient := TDFeDistribuicaoClientFake.Create;
  LClient.AdicionarExcecao(EDFeComunicacaoFalhou);
  LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), LClient, CertificadoTeste, FCursorStore);
  FOrquestrador.AdicionarUnidade(LUnidade);

  FOrquestrador.ExecutarCiclo;

  AssertFalse(LUnidade.Pausada);
  AssertEquals(Int64(111), FCursorStore.ObterUltimoNSU(NAMESPACE_TESTE));
  AssertTrue(FOrquestrador.QuantidadeAvisos > 0);
end;

procedure TDFeOrquestradorTests.CertificadoInvalido_Pausa;
var
  LClient: TDFeDistribuicaoClientFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LClient := TDFeDistribuicaoClientFake.Create;
  LClient.AdicionarExcecao(EDFeCertificadoInvalido);
  LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), LClient, CertificadoTeste, FCursorStore);
  FOrquestrador.AdicionarUnidade(LUnidade);

  FOrquestrador.ExecutarCiclo;

  AssertTrue(LUnidade.Pausada);
  AssertTrue(LUnidade.MotivoPausa <> '');
end;

procedure TDFeOrquestradorTests.RespostaInvalida_NaoPausaERegistraErro;
var
  LClient: TDFeDistribuicaoClientFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LClient := TDFeDistribuicaoClientFake.Create;
  LClient.AdicionarExcecao(EDFeRespostaInvalida);
  LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), LClient, CertificadoTeste, FCursorStore);
  FOrquestrador.AdicionarUnidade(LUnidade);

  FOrquestrador.ExecutarCiclo;

  AssertFalse(LUnidade.Pausada);
  AssertTrue(FOrquestrador.QuantidadeErros > 0);
end;

procedure TDFeOrquestradorTests.MultiplosLotes_ContinuaAteAlcancarMaxNSU;
var
  LClient: TDFeDistribuicaoClientFake;
  LProvider: TDFeProviderFake;
  LUnidade: TDFeUnidadeTrabalho;
  LEventos: TDFeEventoNormalizadoArray;
begin
  LClient := TDFeDistribuicaoClientFake.Create;
  LClient.AdicionarLote(LoteTeste(138, 100, 300));
  LClient.AdicionarLote(LoteTeste(138, 200, 300));
  LClient.AdicionarLote(LoteTeste(138, 300, 300));
  LProvider := TDFeProviderFake.Create('nfe');
  SetLength(LEventos, 1);
  LEventos[0] := EventoTeste;
  LProvider.EventosADevolver := LEventos;
  LUnidade := TDFeUnidadeTrabalho.Create(LProvider, LClient, CertificadoTeste, FCursorStore);
  FOrquestrador.AdicionarUnidade(LUnidade);

  FOrquestrador.ExecutarCiclo;

  AssertEquals(3, LClient.Chamadas);
  AssertEquals(3, FPublicador.Quantidade);
  AssertEquals(Int64(300), FCursorStore.ObterUltimoNSU(NAMESPACE_TESTE));
end;

procedure TDFeOrquestradorTests.UnidadeComExcecaoNaoModelada_NaoDerrubaOutrasUnidades;
var
  LClientA, LClientB: TDFeDistribuicaoClientFake;
  LProviderB: TDFeProviderFake;
  LUnidadeA, LUnidadeB: TDFeUnidadeTrabalho;
  LEventos: TDFeEventoNormalizadoArray;
begin
  LClientA := TDFeDistribuicaoClientFake.Create;
  LClientA.AdicionarExcecao(Exception); // nao modelada -- nenhum dos 3 handlers de DFe.Errors captura
  LUnidadeA := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), LClientA, CertificadoTeste, FCursorStore);

  LClientB := TDFeDistribuicaoClientFake.Create;
  LClientB.AdicionarLote(LoteTeste(138, 42, 42));
  LProviderB := TDFeProviderFake.Create('cte');
  SetLength(LEventos, 1);
  LEventos[0] := EventoTeste;
  LProviderB.EventosADevolver := LEventos;
  LUnidadeB := TDFeUnidadeTrabalho.Create(LProviderB, LClientB, CertificadoTeste, FCursorStore);

  FOrquestrador.AdicionarUnidade(LUnidadeA);
  FOrquestrador.AdicionarUnidade(LUnidadeB);

  FOrquestrador.ExecutarCiclo;

  // A quebrou (excecao nao modelada) mas nao impediu B de ser processada:
  AssertEquals(1, FPublicador.Quantidade);
  AssertTrue(FOrquestrador.QuantidadeErros > 0);
end;

initialization
  RegisterTest(TDFeOrquestradorTests);

end.
