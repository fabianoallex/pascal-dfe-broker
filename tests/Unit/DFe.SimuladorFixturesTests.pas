unit DFe.SimuladorFixturesTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  DFe.Types,
  DFe.Provider,
  DFe.Provider.NFe,
  DFe.Simulador.Fixtures,
  DFe.TestDoubles;

type
  { Valida o gerador de fixtures pelo TDFeProviderNFe REAL: o simulador
    nao pode gerar nada que o provider nao entenda. }
  [TestFixture]
  TDFeSimuladorFixturesTests = class
  private
    function Decodificar(const ASchema, AXml: string): TDFeEventoNormalizadoArray;
  public
    [Test] procedure Chave_Tem44Digitos;
    [Test] procedure Chave_DigitoVerificadorModulo11;
    [Test] procedure Chave_EhDeterministicaEDistintaPorNumero;
    [Test] procedure ResNFe_ProviderVeDocumentoComAChave;
    [Test] procedure ProcNFe_ProviderVeDocumentoComAChave;
    [Test] procedure ResEvento_ProviderVeEventoComTipoMapeado;
    [Test] procedure ProcEventoNFe_ProviderVeEventoComTipoMapeado;
  end;

implementation

{ TDFeSimuladorFixturesTests }

function TDFeSimuladorFixturesTests.Decodificar(const ASchema, AXml: string): TDFeEventoNormalizadoArray;
var
  LProvider: IDFeProvider;
  LLote: TDFeLoteBruto;
begin
  LProvider := TDFeProviderNFe.Create;
  LLote := LoteTeste(138, 1, 1);
  SetLength(LLote.Itens, 1);
  LLote.Itens[0].NSU := 1;
  LLote.Itens[0].Schema := ASchema;
  LLote.Itens[0].XmlDecodificado := AXml;
  Result := LProvider.Decodificar(LLote, CertificadoTeste);
end;

procedure TDFeSimuladorFixturesTests.Chave_Tem44Digitos;
var
  LChave: string;
  I: Integer;
begin
  LChave := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 123);
  Assert.AreEqual(44, Length(LChave));
  for I := 1 to Length(LChave) do
    Assert.IsTrue((LChave[I] >= '0') and (LChave[I] <= '9'), 'so digitos');
end;

procedure TDFeSimuladorFixturesTests.Chave_DigitoVerificadorModulo11;
var
  LChave: string;
  I, LPeso, LSoma, LResto, LDV: Integer;
begin
  LChave := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 42);
  // recalcula o DV por fora, do jeito da NT: pesos 2..9 da direita p/ esquerda
  LSoma := 0;
  LPeso := 2;
  for I := 43 downto 1 do
  begin
    LSoma := LSoma + (Ord(LChave[I]) - Ord('0')) * LPeso;
    Inc(LPeso);
    if LPeso > 9 then LPeso := 2;
  end;
  LResto := LSoma mod 11;
  if LResto < 2 then LDV := 0 else LDV := 11 - LResto;
  Assert.AreEqual(LDV, Ord(LChave[44]) - Ord('0'));
end;

procedure TDFeSimuladorFixturesTests.Chave_EhDeterministicaEDistintaPorNumero;
begin
  Assert.AreEqual(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 7), ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 7));
  Assert.IsTrue(ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 7) <> ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 8));
end;

procedure TDFeSimuladorFixturesTests.ResNFe_ProviderVeDocumentoComAChave;
var
  LChave: string;
  LEv: TDFeEventoNormalizadoArray;
begin
  LChave := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1);
  LEv := Decodificar(DFE_SIM_SCHEMA_RESNFE, XmlResNFe(LChave));
  Assert.AreEqual(1, Length(LEv));
  Assert.IsTrue(LEv[0].Categoria = dcDocumento);
  Assert.AreEqual(LChave, LEv[0].ChaveAcesso);
  Assert.IsTrue(LEv[0].DataEmissao > 0);
end;

procedure TDFeSimuladorFixturesTests.ProcNFe_ProviderVeDocumentoComAChave;
var
  LChave: string;
  LEv: TDFeEventoNormalizadoArray;
begin
  LChave := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 2);
  LEv := Decodificar(DFE_SIM_SCHEMA_PROCNFE, XmlProcNFe(LChave));
  Assert.AreEqual(1, Length(LEv));
  Assert.IsTrue(LEv[0].Categoria = dcDocumento);
  Assert.AreEqual(LChave, LEv[0].ChaveAcesso);
  Assert.IsTrue(LEv[0].DataEmissao > 0);
end;

procedure TDFeSimuladorFixturesTests.ResEvento_ProviderVeEventoComTipoMapeado;
var
  LChave: string;
  LEv: TDFeEventoNormalizadoArray;
begin
  LChave := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 3);
  LEv := Decodificar(DFE_SIM_SCHEMA_RESEVENTO, XmlResEvento(LChave, '110111'));
  Assert.AreEqual(1, Length(LEv));
  Assert.IsTrue(LEv[0].Categoria = dcEvento);
  Assert.AreEqual('cancelamento', LEv[0].TipoEvento);
  Assert.AreEqual(LChave, LEv[0].ChaveAcesso);
end;

procedure TDFeSimuladorFixturesTests.ProcEventoNFe_ProviderVeEventoComTipoMapeado;
var
  LChave: string;
  LEv: TDFeEventoNormalizadoArray;
begin
  LChave := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 4);
  LEv := Decodificar(DFE_SIM_SCHEMA_PROCEVENTONFE, XmlProcEventoNFe(LChave, '210210'));
  Assert.AreEqual(1, Length(LEv));
  Assert.IsTrue(LEv[0].Categoria = dcEvento);
  Assert.AreEqual('ciencia', LEv[0].TipoEvento);
  Assert.AreEqual(LChave, LEv[0].ChaveAcesso);
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeSimuladorFixturesTests);

end.
