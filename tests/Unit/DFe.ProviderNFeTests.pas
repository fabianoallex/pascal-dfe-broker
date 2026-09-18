unit DFe.ProviderNFeTests;

{ Fixtures 100% sinteticas (CNPJ/chave/nomes inventados) no formato dos
  schemas da Distribuicao de DFe -- ver CONTRIBUTING.md, "Certificados e
  dados sensiveis". Nenhum teste aqui toca ACBr, rede ou certificado. }

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  DFe.Types,
  DFe.Errors,
  DFe.Provider,
  DFe.Provider.NFe,
  DFe.TestDoubles;

type
  [TestFixture]
  TDFeProviderNFeTests = class
  private
    function Decodificar(const AItens: array of TDFeItemBruto): TDFeEventoNormalizadoArray;
  public
    [Test] procedure Identificador_EhNfe;
    [Test] procedure CodigoConsumoIndevido_Eh656;
    [Test] procedure AutoRegistro_ProviderNfeDisponivelNoRegistry;
    [Test] procedure LoteSemItens_DevolveVazio;
    [Test] procedure ResNFe_ViraDocumentoComChaveEDataDeEmissao;
    [Test] procedure ResNFe_PreservaPayloadNSUUFECnpjConsultante;
    [Test] procedure ProcNFe_ChaveVemDoIdDeInfNFe;
    [Test] procedure ProcNFe_SemDhEmi_UsaDEmi;
    [Test] procedure ResEvento_Ciencia_ViraEventoCiencia;
    [Test] procedure ResEvento_Cancelamento_ViraEventoCancelamento;
    [Test] procedure ProcEventoNFe_UsaPrimeiroTpEventoDoInfEvento;
    [Test] procedure Evento_TipoSemNomeMapeado_UsaCodigoNumerico;
    [Test] procedure SchemaComNomeDeArquivoOficial_EhReconhecido;
    [Test] procedure SchemaDesconhecido_EhIgnoradoSemAfetarOsDemais;
    [Test] procedure VariosItens_PreservamOrdem;
    [Test] procedure ResNFe_SemChave_Levanta;
    [Test] procedure ResNFe_ChaveCom43Digitos_Levanta;
    [Test] procedure ResEvento_SemTpEvento_Levanta;
    [Test] procedure DataEmissaoIlegivel_Vira0;
    [Test] procedure NomeTipoEventoNFe_ManifestacaoUsaVocabularioDoManifestador;
  end;

implementation

const
  CHAVE_1 = '35260912345678000199550010000001231000001238';
  CHAVE_2 = '35260912345678000199550010000001241000001245';
  CHAVE_3 = '35260912345678000199550010000001251000001252';

function XmlResNFe(const AChave: string): string;
begin
  Result :=
    '<resNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.01">' +
    '<chNFe>' + AChave + '</chNFe>' +
    '<CNPJ>98765432000110</CNPJ>' +
    '<xNome>EMITENTE SINTETICO LTDA</xNome>' +
    '<IE>1234567890</IE>' +
    '<dhEmi>2026-09-10T14:30:05-03:00</dhEmi>' +
    '<tpNF>1</tpNF><vNF>150.00</vNF>' +
    '<digVal>AAAAAAAAAAAAAAAAAAAAAAAAAAA=</digVal>' +
    '<dhRecbto>2026-09-10T14:31:00-03:00</dhRecbto>' +
    '<nProt>143260000000001</nProt><cSitNFe>1</cSitNFe>' +
    '</resNFe>';
end;

function XmlProcNFe(const AChave, ATagData: string): string;
begin
  Result :=
    '<nfeProc xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">' +
    '<NFe><infNFe versao="4.00" Id="NFe' + AChave + '">' +
    '<ide><cUF>35</cUF><natOp>VENDA</natOp><mod>55</mod>' + ATagData + '</ide>' +
    '<emit><CNPJ>98765432000110</CNPJ><xNome>EMITENTE SINTETICO LTDA</xNome></emit>' +
    '</infNFe></NFe>' +
    '<protNFe versao="4.00"><infProt><tpAmb>2</tpAmb><chNFe>' + AChave + '</chNFe>' +
    '<cStat>100</cStat></infProt></protNFe>' +
    '</nfeProc>';
end;

function XmlResEvento(const AChave, ATpEvento: string): string;
begin
  Result :=
    '<resEvento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.01">' +
    '<cOrgao>91</cOrgao><CNPJ>12345678000199</CNPJ>' +
    '<chNFe>' + AChave + '</chNFe>' +
    '<dhEvento>2026-09-11T09:15:00-03:00</dhEvento>' +
    '<tpEvento>' + ATpEvento + '</tpEvento>' +
    '<nSeqEvento>1</nSeqEvento><xEvento>Evento sintetico</xEvento>' +
    '<dhRecbto>2026-09-11T09:15:30-03:00</dhRecbto><nProt>891260000000001</nProt>' +
    '</resEvento>';
end;

function XmlProcEventoNFe(const AChave, ATpEvento: string): string;
begin
  Result :=
    '<procEventoNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00">' +
    '<evento versao="1.00"><infEvento Id="ID' + ATpEvento + AChave + '01">' +
    '<cOrgao>35</cOrgao><tpAmb>2</tpAmb><CNPJ>98765432000110</CNPJ>' +
    '<chNFe>' + AChave + '</chNFe>' +
    '<dhEvento>2026-09-12T10:00:00-03:00</dhEvento>' +
    '<tpEvento>' + ATpEvento + '</tpEvento><nSeqEvento>1</nSeqEvento>' +
    '</infEvento></evento>' +
    '<retEvento versao="1.00"><infEvento><tpAmb>2</tpAmb><cStat>135</cStat>' +
    '<chNFe>' + AChave + '</chNFe><tpEvento>' + ATpEvento + '</tpEvento></infEvento></retEvento>' +
    '</procEventoNFe>';
end;

function Item(const ANSU: Int64; const ASchema, AXml: string): TDFeItemBruto;
begin
  Result.NSU := ANSU;
  Result.Schema := ASchema;
  Result.XmlDecodificado := AXml;
end;

{ TDFeProviderNFeTests }

function TDFeProviderNFeTests.Decodificar(const AItens: array of TDFeItemBruto): TDFeEventoNormalizadoArray;
var
  LProvider: IDFeProvider;
  LLote: TDFeLoteBruto;
  I: Integer;
begin
  LProvider := TDFeProviderNFe.Create;
  LLote := LoteTeste(138, 1, 1);
  SetLength(LLote.Itens, Length(AItens));
  for I := 0 to High(AItens) do
    LLote.Itens[I] := AItens[I];
  Result := LProvider.Decodificar(LLote, CertificadoTeste);
end;

procedure TDFeProviderNFeTests.Identificador_EhNfe;
var
  LProvider: IDFeProvider;
begin
  LProvider := TDFeProviderNFe.Create;
  Assert.AreEqual('nfe', LProvider.Identificador);
end;

procedure TDFeProviderNFeTests.CodigoConsumoIndevido_Eh656;
var
  LProvider: IDFeProvider;
begin
  LProvider := TDFeProviderNFe.Create;
  Assert.AreEqual(656, LProvider.CodigoConsumoIndevido);
end;

procedure TDFeProviderNFeTests.AutoRegistro_ProviderNfeDisponivelNoRegistry;
var
  LProvider: IDFeProvider;
begin
  { So' o fato de DFe.Provider.NFe estar no uses deste programa basta --
    ver CONTRIBUTING.md e DFe.Provider, TDFeProviderRegistry.Registrar. }
  LProvider := TDFeProviderRegistry.ObterPorIdentificador('nfe');
  Assert.IsTrue(Assigned(LProvider));
  Assert.AreEqual(656, LProvider.CodigoConsumoIndevido);
end;

procedure TDFeProviderNFeTests.LoteSemItens_DevolveVazio;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([]);
  Assert.AreEqual(0, Length(LEventos));
end;

procedure TDFeProviderNFeTests.ResNFe_ViraDocumentoComChaveEDataDeEmissao;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([Item(10, 'resNFe', XmlResNFe(CHAVE_1))]);

  Assert.AreEqual(1, Length(LEventos));
  Assert.AreEqual('nfe', LEventos[0].TipoDocumento);
  Assert.AreEqual(Ord(dcDocumento), Ord(LEventos[0].Categoria));
  Assert.AreEqual('', LEventos[0].TipoEvento);
  Assert.AreEqual(CHAVE_1, LEventos[0].ChaveAcesso);
  // horario de parede escrito no documento, fuso descartado
  Assert.AreEqual(EncodeDate(2026, 9, 10) + EncodeTime(14, 30, 5, 0), LEventos[0].DataEmissao, 1 / 86400 / 2);
end;

procedure TDFeProviderNFeTests.ResNFe_PreservaPayloadNSUUFECnpjConsultante;
var
  LEventos: TDFeEventoNormalizadoArray;
  LXml: string;
begin
  LXml := XmlResNFe(CHAVE_1);
  LEventos := Decodificar([Item(777, 'resNFe', LXml)]);

  Assert.AreEqual(LXml, LEventos[0].XmlPayload);
  Assert.AreEqual(Int64(777), LEventos[0].NSU);
  // UF e CNPJ vem do certificado consultante, nao do XML do documento
  Assert.AreEqual(CertificadoTeste.UF, LEventos[0].UF);
  Assert.AreEqual(CertificadoTeste.CnpjCpf, LEventos[0].CnpjCpfConsultante);
end;

procedure TDFeProviderNFeTests.ProcNFe_ChaveVemDoIdDeInfNFe;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([Item(11, 'procNFe', XmlProcNFe(CHAVE_2, '<dhEmi>2026-09-09T08:00:00-03:00</dhEmi>'))]);

  Assert.AreEqual(1, Length(LEventos));
  Assert.AreEqual(Ord(dcDocumento), Ord(LEventos[0].Categoria));
  Assert.AreEqual(CHAVE_2, LEventos[0].ChaveAcesso);
  Assert.AreEqual(EncodeDate(2026, 9, 9) + EncodeTime(8, 0, 0, 0), LEventos[0].DataEmissao, 1 / 86400 / 2);
end;

procedure TDFeProviderNFeTests.ProcNFe_SemDhEmi_UsaDEmi;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([Item(11, 'procNFe', XmlProcNFe(CHAVE_2, '<dEmi>2014-03-05</dEmi>'))]);

  Assert.AreEqual(EncodeDate(2014, 3, 5), LEventos[0].DataEmissao, 1 / 86400 / 2);
end;

procedure TDFeProviderNFeTests.ResEvento_Ciencia_ViraEventoCiencia;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([Item(20, 'resEvento', XmlResEvento(CHAVE_1, '210210'))]);

  Assert.AreEqual(1, Length(LEventos));
  Assert.AreEqual(Ord(dcEvento), Ord(LEventos[0].Categoria));
  Assert.AreEqual('ciencia', LEventos[0].TipoEvento);
  Assert.AreEqual(CHAVE_1, LEventos[0].ChaveAcesso);
  Assert.AreEqual(EncodeDate(2026, 9, 11) + EncodeTime(9, 15, 0, 0), LEventos[0].DataEmissao, 1 / 86400 / 2);
end;

procedure TDFeProviderNFeTests.ResEvento_Cancelamento_ViraEventoCancelamento;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([Item(21, 'resEvento', XmlResEvento(CHAVE_1, '110111'))]);

  Assert.AreEqual('cancelamento', LEventos[0].TipoEvento);
end;

procedure TDFeProviderNFeTests.ProcEventoNFe_UsaPrimeiroTpEventoDoInfEvento;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([Item(22, 'procEventoNFe', XmlProcEventoNFe(CHAVE_3, '110111'))]);

  Assert.AreEqual(1, Length(LEventos));
  Assert.AreEqual(Ord(dcEvento), Ord(LEventos[0].Categoria));
  Assert.AreEqual('cancelamento', LEventos[0].TipoEvento);
  Assert.AreEqual(CHAVE_3, LEventos[0].ChaveAcesso);
  Assert.AreEqual(EncodeDate(2026, 9, 12) + EncodeTime(10, 0, 0, 0), LEventos[0].DataEmissao, 1 / 86400 / 2);
end;

procedure TDFeProviderNFeTests.Evento_TipoSemNomeMapeado_UsaCodigoNumerico;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([Item(23, 'resEvento', XmlResEvento(CHAVE_1, '110150'))]);

  Assert.AreEqual('110150', LEventos[0].TipoEvento);
end;

procedure TDFeProviderNFeTests.SchemaComNomeDeArquivoOficial_EhReconhecido;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([Item(10, 'resNFe_v1.01.xsd', XmlResNFe(CHAVE_1))]);

  Assert.AreEqual(1, Length(LEventos));
  Assert.AreEqual(CHAVE_1, LEventos[0].ChaveAcesso);
end;

procedure TDFeProviderNFeTests.SchemaDesconhecido_EhIgnoradoSemAfetarOsDemais;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([
    Item(10, 'resNFe', XmlResNFe(CHAVE_1)),
    Item(11, 'schemaFuturoDaSefaz', '<qualquer/>'),
    Item(12, 'resNFe', XmlResNFe(CHAVE_2))]);

  Assert.AreEqual(2, Length(LEventos));
  Assert.AreEqual(CHAVE_1, LEventos[0].ChaveAcesso);
  Assert.AreEqual(CHAVE_2, LEventos[1].ChaveAcesso);
end;

procedure TDFeProviderNFeTests.VariosItens_PreservamOrdem;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([
    Item(1, 'resNFe', XmlResNFe(CHAVE_1)),
    Item(2, 'resEvento', XmlResEvento(CHAVE_1, '210210')),
    Item(3, 'procNFe', XmlProcNFe(CHAVE_2, '<dhEmi>2026-09-09T08:00:00-03:00</dhEmi>'))]);

  Assert.AreEqual(3, Length(LEventos));
  Assert.AreEqual(Int64(1), LEventos[0].NSU);
  Assert.AreEqual(Int64(2), LEventos[1].NSU);
  Assert.AreEqual(Int64(3), LEventos[2].NSU);
end;

procedure TDFeProviderNFeTests.ResNFe_SemChave_Levanta;
var
  LProvider: IDFeProvider;
  LLote: TDFeLoteBruto;
begin
  LProvider := TDFeProviderNFe.Create;
  LLote := LoteTeste(138, 1, 1);
  SetLength(LLote.Itens, 1);
  LLote.Itens[0] := Item(10, 'resNFe', '<resNFe><dhEmi>2026-09-10T14:30:05-03:00</dhEmi></resNFe>');

  Assert.WillRaise(
    procedure
    begin
      LProvider.Decodificar(LLote, CertificadoTeste);
    end,
    EDFeRespostaInvalida);
end;

procedure TDFeProviderNFeTests.ResNFe_ChaveCom43Digitos_Levanta;
var
  LProvider: IDFeProvider;
  LLote: TDFeLoteBruto;
begin
  LProvider := TDFeProviderNFe.Create;
  LLote := LoteTeste(138, 1, 1);
  SetLength(LLote.Itens, 1);
  LLote.Itens[0] := Item(10, 'resNFe', XmlResNFe(Copy(CHAVE_1, 1, 43)));

  Assert.WillRaise(
    procedure
    begin
      LProvider.Decodificar(LLote, CertificadoTeste);
    end,
    EDFeRespostaInvalida);
end;

procedure TDFeProviderNFeTests.ResEvento_SemTpEvento_Levanta;
var
  LProvider: IDFeProvider;
  LLote: TDFeLoteBruto;
begin
  LProvider := TDFeProviderNFe.Create;
  LLote := LoteTeste(138, 1, 1);
  SetLength(LLote.Itens, 1);
  LLote.Itens[0] := Item(10, 'resEvento', '<resEvento><chNFe>' + CHAVE_1 + '</chNFe></resEvento>');

  Assert.WillRaise(
    procedure
    begin
      LProvider.Decodificar(LLote, CertificadoTeste);
    end,
    EDFeRespostaInvalida);
end;

procedure TDFeProviderNFeTests.DataEmissaoIlegivel_Vira0;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([Item(10, 'resNFe',
    '<resNFe><chNFe>' + CHAVE_1 + '</chNFe><dhEmi>ontem</dhEmi></resNFe>')]);

  Assert.AreEqual(0.0, LEventos[0].DataEmissao, 0.0);
end;

procedure TDFeProviderNFeTests.NomeTipoEventoNFe_ManifestacaoUsaVocabularioDoManifestador;
begin
  Assert.AreEqual('confirmacao', NomeTipoEventoNFe('210200'));
  Assert.AreEqual('ciencia', NomeTipoEventoNFe('210210'));
  Assert.AreEqual('desconhecimento', NomeTipoEventoNFe('210220'));
  Assert.AreEqual('operacaonaorealizada', NomeTipoEventoNFe('210240'));
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeProviderNFeTests);

end.
