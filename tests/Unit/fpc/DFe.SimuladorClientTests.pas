unit DFe.SimuladorClientTests;

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils,
  DFe.Types,
  DFe.Errors,
  DFe.Provider,
  DFe.Provider.NFe,
  DFe.Orquestrador,
  DFe.Simulador,
  DFe.Simulador.Client,
  DFe.Simulador.Fixtures,
  DFe.TestDoubles;

type
  { Camada 1: o client do simulador isolado -- traducao do que o nucleo
    decide para o contrato de IDFeDistribuicaoClient / DFe.Errors. }
  TDFeSimuladorClientTests = class(TTestCase)
  private
    FRelogio: TDFeRelogioFake;
    FSim: TDFeSimuladorSefaz;
    function NovoClient: IDFeDistribuicaoClient;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure LoteNormal_PassaDireto;
    procedure Timeout_ViraComunicacaoFalhou;
    procedure ErroHttp_ViraComunicacaoFalhou;
    procedure CorpoIlegivel_ViraRespostaInvalida;
    procedure DocZipCorrompidoComItens_ViraRespostaInvalida;
    procedure DocZipCorrompidoSemItens_NaoAfetaOLote;
    procedure ConsumoIndevido_NaoEExcecao_EhLoteComCStat;
  end;

  { Ponta a ponta sem ACBr: orquestrador real + provider NFe real +
    publicador/cursor fakes, contra o simulador com estado e relogio
    virtual (o do simulador e o do orquestrador andam juntos). }
  TDFeSimuladorFimAFimTests = class(TTestCase)
  private
    FRelogio: TDFeRelogioFake;
    FSim: TDFeSimuladorSefaz;
    FPublicador: TDFePublicadorFake;
    FCursorStore: TDFeCursorStoreFake;
    FOrquestrador: TDFeOrquestradorTestavel;
    procedure AvancarMinutos(const AMinutos: Integer);
    procedure AdicionarUnidade;
    function CursorAtual: Int64;
    procedure PublicarNFes(const AQuantidade: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure PrimeiroCiclo_PublicaDocumentosEEventosComRoutingKeys;
    procedure CicloApos1h_Recebe137_NaoPublicaEMantemCursor;
    procedure AntesDe1h_OrquestradorNaoConsulta;
    procedure CentoEVinteDocumentos_TresLotesEmUmCicloSo;
    procedure ConsumoIndevido_ReagendaSemAvancarCursorEDepoisRecupera;
    procedure ServicoIndisponivel108_ReagendaSemAvancarCursor;
    procedure Timeout_ReagendaSemAvancarCursor;
    procedure CorpoIlegivel_RegistraErroEReagenda;
    procedure DocZipCorrompido_CursorIntactoEProximoCicloEntregaOsDocumentos;
    procedure SaltoDeNSU_CursorAcompanhaOUltimoNSUDoLote;
  end;

implementation

{ TDFeSimuladorClientTests }

procedure TDFeSimuladorClientTests.SetUp;
begin
  FRelogio := TDFeRelogioFake.Create;
  FRelogio.Agora := EncodeDate(2026, 9, 18) + EncodeTime(10, 0, 0, 0);
  FSim := TDFeSimuladorSefaz.Create(FRelogio.ObterAgora);
end;

procedure TDFeSimuladorClientTests.TearDown;
begin
  FSim.Free;
  FRelogio.Free;
end;

function TDFeSimuladorClientTests.NovoClient: IDFeDistribuicaoClient;
begin
  Result := TDFeSimuladorClient.Create(FSim);
end;

procedure TDFeSimuladorClientTests.LoteNormal_PassaDireto;
var
  LClient: IDFeDistribuicaoClient;
  LLote: TDFeLoteBruto;
begin
  FSim.PublicarDocumento(CertificadoTeste.CnpjCpf, 'RS', DFE_SIM_SCHEMA_RESNFE,
    XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  LClient := NovoClient;
  LLote := LClient.Consultar(CertificadoTeste, 0);
  AssertEquals(138, LLote.CStat);
  AssertEquals(1, Length(LLote.Itens));
  AssertEquals(Int64(1), LLote.UltimoNSU);
end;

procedure TDFeSimuladorClientTests.Timeout_ViraComunicacaoFalhou;
var
  LClient: IDFeDistribuicaoClient;
begin
  FSim.EnfileirarFalha(fsTimeout);
  LClient := NovoClient;
  try
    LClient.Consultar(CertificadoTeste, 0);
    Fail('esperava EDFeComunicacaoFalhou');
  except
    on EDFeComunicacaoFalhou do ;
  end;
end;

procedure TDFeSimuladorClientTests.ErroHttp_ViraComunicacaoFalhou;
var
  LClient: IDFeDistribuicaoClient;
begin
  FSim.EnfileirarFalha(fsErroHttp);
  LClient := NovoClient;
  try
    LClient.Consultar(CertificadoTeste, 0);
    Fail('esperava EDFeComunicacaoFalhou');
  except
    on EDFeComunicacaoFalhou do ;
  end;
end;

procedure TDFeSimuladorClientTests.CorpoIlegivel_ViraRespostaInvalida;
var
  LClient: IDFeDistribuicaoClient;
begin
  FSim.EnfileirarFalha(fsCorpoIlegivel);
  LClient := NovoClient;
  try
    LClient.Consultar(CertificadoTeste, 0);
    Fail('esperava EDFeRespostaInvalida');
  except
    on EDFeRespostaInvalida do ;
  end;
end;

procedure TDFeSimuladorClientTests.DocZipCorrompidoComItens_ViraRespostaInvalida;
var
  LClient: IDFeDistribuicaoClient;
begin
  FSim.PublicarDocumento(CertificadoTeste.CnpjCpf, 'RS', DFE_SIM_SCHEMA_RESNFE,
    XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  FSim.EnfileirarFalha(fsDocZipCorrompido);
  LClient := NovoClient;
  try
    LClient.Consultar(CertificadoTeste, 0);
    Fail('esperava EDFeRespostaInvalida');
  except
    on EDFeRespostaInvalida do ;
  end;
end;

procedure TDFeSimuladorClientTests.DocZipCorrompidoSemItens_NaoAfetaOLote;
var
  LClient: IDFeDistribuicaoClient;
begin
  FSim.EnfileirarFalha(fsDocZipCorrompido);
  LClient := NovoClient;
  AssertEquals(137, LClient.Consultar(CertificadoTeste, 0).CStat);
end;

procedure TDFeSimuladorClientTests.ConsumoIndevido_NaoEExcecao_EhLoteComCStat;
var
  LClient: IDFeDistribuicaoClient;
begin
  LClient := NovoClient;
  AssertEquals(137, LClient.Consultar(CertificadoTeste, 0).CStat);
  AssertEquals(656, LClient.Consultar(CertificadoTeste, 0).CStat);
end;

{ TDFeSimuladorFimAFimTests }

procedure TDFeSimuladorFimAFimTests.SetUp;
begin
  FRelogio := TDFeRelogioFake.Create;
  FRelogio.Agora := EncodeDate(2026, 9, 18) + EncodeTime(10, 0, 0, 0);
  FSim := TDFeSimuladorSefaz.Create(FRelogio.ObterAgora);
  FPublicador := TDFePublicadorFake.Create;
  FCursorStore := TDFeCursorStoreFake.Create;
  FOrquestrador := TDFeOrquestradorTestavel.Create(FPublicador);
  FOrquestrador.AgoraSimulado := FRelogio.Agora;
end;

procedure TDFeSimuladorFimAFimTests.TearDown;
begin
  FOrquestrador.Free;
  FSim.Free;
  FRelogio.Free;
  // FPublicador/FCursorStore: interfaces seguradas pelo orquestrador/unidade.
end;

procedure TDFeSimuladorFimAFimTests.AvancarMinutos(const AMinutos: Integer);
begin
  FRelogio.Agora := FRelogio.Agora + AMinutos / 1440;
  FOrquestrador.AgoraSimulado := FRelogio.Agora;
end;

procedure TDFeSimuladorFimAFimTests.AdicionarUnidade;
var
  LClient: IDFeDistribuicaoClient;
begin
  LClient := TDFeSimuladorClient.Create(FSim);
  FOrquestrador.AdicionarUnidade(TDFeUnidadeTrabalho.Create(
    TDFeProviderNFe.Create, LClient, CertificadoTeste, FCursorStore));
end;

function TDFeSimuladorFimAFimTests.CursorAtual: Int64;
begin
  Result := FCursorStore.ObterUltimoNSU(MontarNamespaceCursor('nfe', CertificadoTeste));
end;

procedure TDFeSimuladorFimAFimTests.PublicarNFes(const AQuantidade: Integer);
var
  I: Integer;
begin
  for I := 1 to AQuantidade do
    FSim.PublicarDocumento(CertificadoTeste.CnpjCpf, 'RS', DFE_SIM_SCHEMA_RESNFE,
      XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, I)));
end;

procedure TDFeSimuladorFimAFimTests.PrimeiroCiclo_PublicaDocumentosEEventosComRoutingKeys;
var
  LCnpj: string;
begin
  LCnpj := CertificadoTeste.CnpjCpf;
  FSim.PublicarDocumento(LCnpj, 'RS', DFE_SIM_SCHEMA_RESNFE, XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  FSim.PublicarDocumento(LCnpj, 'RS', DFE_SIM_SCHEMA_PROCNFE, XmlProcNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 2)));
  FSim.PublicarDocumento(LCnpj, 'RS', DFE_SIM_SCHEMA_RESEVENTO, XmlResEvento(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1), '110111'));
  FSim.PublicarDocumento(LCnpj, 'RS', DFE_SIM_SCHEMA_PROCEVENTONFE, XmlProcEventoNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 2), '210210'));
  AdicionarUnidade;

  FOrquestrador.ExecutarCiclo;

  AssertEquals(4, FPublicador.Quantidade);
  AssertEquals('nfe.documento.rs.' + LCnpj, FPublicador.RoutingKey(0));
  AssertEquals('nfe.documento.rs.' + LCnpj, FPublicador.RoutingKey(1));
  AssertEquals('nfe.evento.cancelamento.rs.' + LCnpj, FPublicador.RoutingKey(2));
  AssertEquals('nfe.evento.ciencia.rs.' + LCnpj, FPublicador.RoutingKey(3));
  AssertEquals(Int64(4), CursorAtual);
  AssertEquals(1, FSim.TotalConsultas);
end;

procedure TDFeSimuladorFimAFimTests.CicloApos1h_Recebe137_NaoPublicaEMantemCursor;
begin
  PublicarNFes(2);
  AdicionarUnidade;
  FOrquestrador.ExecutarCiclo;
  AssertEquals(2, FPublicador.Quantidade);

  AvancarMinutos(60);
  FOrquestrador.ExecutarCiclo; // a SEFAZ responde 137 e abre o bloqueio de 1h

  AssertEquals(2, FSim.TotalConsultas);
  AssertEquals(2, FPublicador.Quantidade);
  AssertEquals(Int64(2), CursorAtual);
  AssertEquals(0, FOrquestrador.QuantidadeAvisos);

  // O orquestrador reagenda +1h a partir do 137; o bloqueio da SEFAZ
  // expira no mesmo instante -- nao deve haver consumo indevido.
  AvancarMinutos(60);
  FOrquestrador.ExecutarCiclo;
  AssertEquals(3, FSim.TotalConsultas);
  AssertEquals(0, FOrquestrador.QuantidadeAvisos);
end;

procedure TDFeSimuladorFimAFimTests.AntesDe1h_OrquestradorNaoConsulta;
begin
  PublicarNFes(1);
  AdicionarUnidade;
  FOrquestrador.ExecutarCiclo;

  AvancarMinutos(59);
  FOrquestrador.ExecutarCiclo;
  AssertEquals(1, FSim.TotalConsultas);
end;

procedure TDFeSimuladorFimAFimTests.CentoEVinteDocumentos_TresLotesEmUmCicloSo;
begin
  PublicarNFes(120);
  AdicionarUnidade;

  FOrquestrador.ExecutarCiclo;

  AssertEquals(3, FSim.TotalConsultas);
  AssertEquals(120, FPublicador.Quantidade);
  AssertEquals(Int64(120), CursorAtual);
end;

procedure TDFeSimuladorFimAFimTests.ConsumoIndevido_ReagendaSemAvancarCursorEDepoisRecupera;
begin
  PublicarNFes(2);
  AdicionarUnidade;
  FSim.EnfileirarFalha(fsConsumoIndevido);

  FOrquestrador.ExecutarCiclo;
  AssertEquals(0, FPublicador.Quantidade);
  AssertEquals(Int64(0), CursorAtual);
  AssertEquals(1, FOrquestrador.QuantidadeAvisos);

  AvancarMinutos(59);
  FOrquestrador.ExecutarCiclo;
  AssertEquals(1, FSim.TotalConsultas); // reagendado: nao consultou

  AvancarMinutos(1);
  FOrquestrador.ExecutarCiclo;
  AssertEquals(2, FPublicador.Quantidade);
  AssertEquals(Int64(2), CursorAtual);
end;

procedure TDFeSimuladorFimAFimTests.ServicoIndisponivel108_ReagendaSemAvancarCursor;
begin
  PublicarNFes(1);
  AdicionarUnidade;
  FSim.EnfileirarFalha(fsIndisponivelCurtoPrazo);

  FOrquestrador.ExecutarCiclo;
  AssertEquals(0, FPublicador.Quantidade);
  AssertEquals(Int64(0), CursorAtual);
  AssertEquals(1, FOrquestrador.QuantidadeAvisos);

  AvancarMinutos(60);
  FOrquestrador.ExecutarCiclo;
  AssertEquals(1, FPublicador.Quantidade);
end;

procedure TDFeSimuladorFimAFimTests.Timeout_ReagendaSemAvancarCursor;
begin
  PublicarNFes(1);
  AdicionarUnidade;
  FSim.EnfileirarFalha(fsTimeout);

  FOrquestrador.ExecutarCiclo;
  AssertEquals(0, FPublicador.Quantidade);
  AssertEquals(Int64(0), CursorAtual);
  AssertEquals(1, FOrquestrador.QuantidadeAvisos);
  AssertEquals(0, FOrquestrador.QuantidadeErros);

  AvancarMinutos(60);
  FOrquestrador.ExecutarCiclo;
  AssertEquals(1, FPublicador.Quantidade);
end;

procedure TDFeSimuladorFimAFimTests.CorpoIlegivel_RegistraErroEReagenda;
begin
  PublicarNFes(1);
  AdicionarUnidade;
  FSim.EnfileirarFalha(fsCorpoIlegivel);

  FOrquestrador.ExecutarCiclo;
  AssertEquals(0, FPublicador.Quantidade);
  AssertEquals(1, FOrquestrador.QuantidadeErros);

  AvancarMinutos(60);
  FOrquestrador.ExecutarCiclo;
  AssertEquals(1, FPublicador.Quantidade);
end;

procedure TDFeSimuladorFimAFimTests.DocZipCorrompido_CursorIntactoEProximoCicloEntregaOsDocumentos;
begin
  PublicarNFes(3);
  AdicionarUnidade;
  FSim.EnfileirarFalha(fsDocZipCorrompido);

  FOrquestrador.ExecutarCiclo;
  AssertEquals(0, FPublicador.Quantidade);
  AssertEquals(Int64(0), CursorAtual); // nada perdido: o cursor nao andou
  AssertEquals(1, FOrquestrador.QuantidadeErros);

  AvancarMinutos(60);
  FOrquestrador.ExecutarCiclo;
  AssertEquals(3, FPublicador.Quantidade);
  AssertEquals(Int64(3), CursorAtual);
end;

procedure TDFeSimuladorFimAFimTests.SaltoDeNSU_CursorAcompanhaOUltimoNSUDoLote;
begin
  FSim.PublicarDocumento(CertificadoTeste.CnpjCpf, 'RS', DFE_SIM_SCHEMA_RESNFE,
    XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1)));
  FSim.PularNSU(CertificadoTeste.CnpjCpf, 'RS', 3);
  FSim.PublicarDocumento(CertificadoTeste.CnpjCpf, 'RS', DFE_SIM_SCHEMA_RESNFE,
    XmlResNFe(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 2)));
  AdicionarUnidade;

  FOrquestrador.ExecutarCiclo;

  AssertEquals(2, FPublicador.Quantidade);
  AssertEquals(Int64(5), CursorAtual);
end;

initialization
  RegisterTest(TDFeSimuladorClientTests);
  RegisterTest(TDFeSimuladorFimAFimTests);

end.
