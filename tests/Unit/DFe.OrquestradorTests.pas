unit DFe.OrquestradorTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  DFe.Types,
  DFe.Errors,
  DFe.Provider,
  DFe.Orquestrador,
  DFe.TestDoubles;

const
  NAMESPACE_TESTE = 'nfe/12345678000199/rs';

type
  [TestFixture]
  TDFeOrquestradorTests = class
  private
    FOrquestrador: TDFeOrquestradorTestavel;
    FPublicador: TDFePublicadorFake;
    FCursorStore: TDFeCursorStoreFake;
    { Referencia de interface que segura o FCursorStore vivo durante o teste inteiro e
      o libera no TearDown: sem ela, um teste que nao entrega FCursorStore a nenhuma
      unidade deixaria o objeto com refcount 0 e ele vazaria (ver CLAUDE.md, gotchas). }
    FCursorStoreRef: IDFeCursorStore;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure UnidadePausada_NaoConsulta;
    [Test] procedure ProximaConsultaNoFuturo_NaoConsulta;
    [Test] procedure DocumentosLocalizados_PublicaEAvancaCursorEReagenda;
    [Test] procedure NenhumDocumento_NaoPublicaMasAvancaEReagenda;
    [Test] procedure ConsumoIndevido_ReagendaSemAvancarCursor;
    [Test] procedure ComunicacaoFalhou_ReagendaSemPausarNemAvancarCursor;
    [Test] procedure CertificadoInvalido_Pausa;
    [Test] procedure RespostaInvalida_NaoPausaERegistraErro;
    [Test] procedure AmbienteIndisponivel_RegistraErroReagendaEMantemUnidadeAtiva;
    [Test] procedure MultiplosLotes_ContinuaAteAlcancarMaxNSU;
    [Test] procedure UnidadeComExcecaoNaoModelada_NaoDerrubaOutrasUnidades;
    [Test] procedure DecodificarLevanta_ReagendaSemAvancarCursorNemRepetirConsulta;
    [Test] procedure MontarNamespaceCursor_Producao_MantemAChaveDeSempre;
    [Test] procedure MontarNamespaceCursor_Homologacao_GanhaSufixo;
    [Test] procedure UnidadeDeHomologacao_UsaOCursorDeHomologacao_ENaoTocaOdeProducao;
  end;

implementation

// CertificadoTeste/LoteTeste/EventoTeste vem de DFe.TestDoubles (helpers
// de fixture compartilhados com DFe.HostLoopTests).

{ TDFeOrquestradorTests }

procedure TDFeOrquestradorTests.Setup;
begin
  FPublicador := TDFePublicadorFake.Create;
  FCursorStore := TDFeCursorStoreFake.Create;
  FCursorStoreRef := FCursorStore;
  FOrquestrador := TDFeOrquestradorTestavel.Create(FPublicador);
  FOrquestrador.AgoraSimulado := EncodeDate(2026, 1, 1);
end;

procedure TDFeOrquestradorTests.TearDown;
begin
  FOrquestrador.Free;
  FCursorStoreRef := nil;
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

  Assert.AreEqual(0, LClient.Chamadas);
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

  Assert.AreEqual(0, LClient.Chamadas);
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

  Assert.AreEqual(1, FPublicador.Quantidade);
  Assert.AreEqual('nfe.documento.rs.12345678000199', FPublicador.RoutingKey(0));
  Assert.AreEqual(Int64(500), FCursorStore.ObterUltimoNSU(NAMESPACE_TESTE));
  Assert.AreEqual(LAgoraAntes + (DFE_INTERVALO_BASE_SEGUNDOS_PADRAO / SecsPerDay), LUnidade.ProximaConsultaEm, 1 / SecsPerDay);
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

  Assert.AreEqual(0, FPublicador.Quantidade);
  Assert.AreEqual(1, LClient.Chamadas);
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

  Assert.AreEqual(Int64(999), FCursorStore.ObterUltimoNSU(NAMESPACE_TESTE));
  Assert.AreEqual(0, FPublicador.Quantidade);
  Assert.AreEqual(LAgoraAntes + (DFE_INTERVALO_BASE_SEGUNDOS_PADRAO / SecsPerDay), LUnidade.ProximaConsultaEm, 1 / SecsPerDay);
  Assert.IsTrue(FOrquestrador.QuantidadeAvisos > 0);
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

  Assert.IsFalse(LUnidade.Pausada);
  Assert.AreEqual(Int64(111), FCursorStore.ObterUltimoNSU(NAMESPACE_TESTE));
  Assert.IsTrue(FOrquestrador.QuantidadeAvisos > 0);
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

  Assert.IsTrue(LUnidade.Pausada);
  Assert.AreNotEqual('', LUnidade.MotivoPausa);
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

  Assert.IsFalse(LUnidade.Pausada);
  Assert.IsTrue(FOrquestrador.QuantidadeErros > 0);
end;

{ Servidor sem DLL/XSD (DFe.Ambiente): erro para o operador, mas a unidade NAO
  e' pausada -- consertado o ambiente, a proxima tentativa funciona sozinha
  (ao contrario de EDFeCertificadoInvalido, que pausa). }
procedure TDFeOrquestradorTests.AmbienteIndisponivel_RegistraErroReagendaEMantemUnidadeAtiva;
var
  LClient: TDFeDistribuicaoClientFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LClient := TDFeDistribuicaoClientFake.Create;
  LClient.AdicionarExcecao(EDFeAmbienteIndisponivel);
  LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), LClient, CertificadoTeste, FCursorStore);
  FOrquestrador.AdicionarUnidade(LUnidade);

  FOrquestrador.ExecutarCiclo;

  Assert.IsFalse(LUnidade.Pausada);
  Assert.AreEqual(1, FOrquestrador.QuantidadeErros);
  Assert.IsTrue(LUnidade.ProximaConsultaEm > FOrquestrador.AgoraSimulado);
  Assert.AreEqual(Int64(0), FCursorStore.ObterUltimoNSU(NAMESPACE_TESTE));
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

  Assert.AreEqual(3, LClient.Chamadas);
  Assert.AreEqual(3, FPublicador.Quantidade);
  Assert.AreEqual(Int64(300), FCursorStore.ObterUltimoNSU(NAMESPACE_TESTE));
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
  Assert.AreEqual(1, FPublicador.Quantidade);
  Assert.IsTrue(FOrquestrador.QuantidadeErros > 0);
end;

procedure TDFeOrquestradorTests.DecodificarLevanta_ReagendaSemAvancarCursorNemRepetirConsulta;
var
  LClient: TDFeDistribuicaoClientFake;
  LProvider: TDFeProviderFake;
  LUnidade: TDFeUnidadeTrabalho;
  LAgoraAntes: TDateTime;
begin
  LClient := TDFeDistribuicaoClientFake.Create;
  LClient.AdicionarLote(LoteTeste(138, 500, 500));
  LProvider := TDFeProviderFake.Create('nfe');
  LProvider.ExcecaoADecodificar := EDFeRespostaInvalida;
  LUnidade := TDFeUnidadeTrabalho.Create(LProvider, LClient, CertificadoTeste, FCursorStore);
  FOrquestrador.AdicionarUnidade(LUnidade);
  LAgoraAntes := FOrquestrador.AgoraSimulado;

  FOrquestrador.ExecutarCiclo;

  Assert.IsTrue(FOrquestrador.QuantidadeErros > 0);
  Assert.AreEqual(0, FPublicador.Quantidade);
  Assert.AreEqual(Int64(0), FCursorStore.ObterUltimoNSU(NAMESPACE_TESTE));
  Assert.IsFalse(LUnidade.Pausada);
  Assert.AreEqual(LAgoraAntes + (DFE_INTERVALO_BASE_SEGUNDOS_PADRAO / SecsPerDay), LUnidade.ProximaConsultaEm, 1 / SecsPerDay);

  // Regressao: antes, ProximaConsultaEm nao mudava e o proximo tick
  // consultava a SEFAZ de novo (consumo indevido). Agora, mesmo no
  // "proximo tick" (sem o relogio andar), a unidade nao e' reconsultada.
  FOrquestrador.ExecutarCiclo;
  Assert.AreEqual(1, LClient.Chamadas);
end;

procedure TDFeOrquestradorTests.MontarNamespaceCursor_Producao_MantemAChaveDeSempre;
begin
  // a chave de producao e' a que ja' existia antes de o ambiente entrar: sem migracao
  Assert.AreEqual('nfe/12345678000199/rs', MontarNamespaceCursor('nfe', CertificadoTeste));
  Assert.AreEqual('nfe/12345678000199/rs', MontarNamespaceCursor('nfe', CertificadoTeste, daProducao));
end;

procedure TDFeOrquestradorTests.MontarNamespaceCursor_Homologacao_GanhaSufixo;
begin
  Assert.AreEqual('nfe/12345678000199/rs/homologacao', MontarNamespaceCursor('nfe', CertificadoTeste, daHomologacao));
end;

procedure TDFeOrquestradorTests.UnidadeDeHomologacao_UsaOCursorDeHomologacao_ENaoTocaOdeProducao;
var
  LClient: TDFeDistribuicaoClientFake;
  LUnidade: TDFeUnidadeTrabalho;
begin
  LClient := TDFeDistribuicaoClientFake.Create;
  LClient.AdicionarLote(LoteTeste(137, 700, 700));
  LUnidade := TDFeUnidadeTrabalho.Create(TDFeProviderFake.Create('nfe'), LClient, CertificadoTeste, FCursorStore);
  LUnidade.Ambiente := daHomologacao;
  FOrquestrador.AdicionarUnidade(LUnidade);

  FOrquestrador.ExecutarCiclo;

  Assert.AreEqual(Int64(700), FCursorStore.ObterUltimoNSU(NAMESPACE_TESTE + '/homologacao'));
  Assert.AreEqual(Int64(0), FCursorStore.ObterUltimoNSU(NAMESPACE_TESTE), 'o cursor de producao nao foi tocado');
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeOrquestradorTests);

end.
