unit DFe.ProviderNFeTests;

{$mode delphi}{$H+}

{ Fixtures 100% sinteticas (CNPJ/chave/nomes inventados) no formato dos
  schemas da Distribuicao de DFe -- ver CONTRIBUTING.md, "Certificados e
  dados sensiveis". Nenhum teste aqui toca ACBr, rede ou certificado. }

interface

uses
  fpcunit, testregistry,
  SysUtils,
  DFe.Types,
  DFe.Errors,
  DFe.Provider,
  DFe.Provider.NFe,
  DFe.TestDoubles;

type
  TDFeProviderNFeTests = class(TTestCase)
  private
    FProvider: IDFeProvider;
    FLote: TDFeLoteBruto;
    function Decodificar(const AItens: array of TDFeItemBruto): TDFeEventoNormalizadoArray;
    procedure DoDecodificarLoteInvalido;
    procedure AssertItemInvalidoLevanta(const AItem: TDFeItemBruto);
  published
    procedure Identificador_EhNfe;
    procedure CodigoConsumoIndevido_Eh656;
    procedure AutoRegistro_ProviderNfeDisponivelNoRegistry;
    procedure LoteSemItens_DevolveVazio;
    procedure ResNFe_ViraDocumentoComChaveEDataDeEmissao;
    procedure ResNFe_PreservaPayloadNSUUFECnpjConsultante;
    procedure ProcNFe_ChaveVemDoIdDeInfNFe;
    procedure ProcNFe_SemDhEmi_UsaDEmi;
    procedure ResEvento_Ciencia_ViraEventoCiencia;
    procedure ResEvento_Cancelamento_ViraEventoCancelamento;
    procedure ProcEventoNFe_UsaPrimeiroTpEventoDoInfEvento;
    procedure Evento_TipoSemNomeMapeado_UsaCodigoNumerico;
    procedure SchemaComNomeDeArquivoOficial_EhReconhecido;
    procedure SchemaDesconhecido_EhIgnoradoSemAfetarOsDemais;
    procedure VariosItens_PreservamOrdem;
    procedure ResNFe_SemChave_Levanta;
    procedure ResNFe_ChaveCom43Digitos_Levanta;
    procedure ResEvento_SemTpEvento_Levanta;
    procedure DataEmissaoIlegivel_Vira0;
    procedure NomeTipoEventoNFe_ManifestacaoUsaVocabularioDoManifestador;
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

procedure TDFeProviderNFeTests.DoDecodificarLoteInvalido;
begin
  FProvider.Decodificar(FLote, CertificadoTeste);
end;

procedure TDFeProviderNFeTests.AssertItemInvalidoLevanta(const AItem: TDFeItemBruto);
begin
  FProvider := TDFeProviderNFe.Create;
  FLote := LoteTeste(138, 1, 1);
  SetLength(FLote.Itens, 1);
  FLote.Itens[0] := AItem;
  AssertException(EDFeRespostaInvalida, DoDecodificarLoteInvalido);
end;

procedure TDFeProviderNFeTests.Identificador_EhNfe;
var
  LProvider: IDFeProvider;
begin
  LProvider := TDFeProviderNFe.Create;
  AssertEquals('nfe', LProvider.Identificador);
end;

procedure TDFeProviderNFeTests.CodigoConsumoIndevido_Eh656;
var
  LProvider: IDFeProvider;
begin
  LProvider := TDFeProviderNFe.Create;
  AssertEquals(656, LProvider.CodigoConsumoIndevido);
end;

procedure TDFeProviderNFeTests.AutoRegistro_ProviderNfeDisponivelNoRegistry;
var
  LProvider: IDFeProvider;
begin
  { So' o fato de DFe.Provider.NFe estar no uses deste programa basta --
    ver CONTRIBUTING.md e DFe.Provider, TDFeProviderRegistry.Registrar. }
  LProvider := TDFeProviderRegistry.ObterPorIdentificador('nfe');
  AssertTrue(Assigned(LProvider));
  AssertEquals(656, LProvider.CodigoConsumoIndevido);
end;

procedure TDFeProviderNFeTests.LoteSemItens_DevolveVazio;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([]);
  AssertEquals(0, Length(LEventos));
end;

procedure TDFeProviderNFeTests.ResNFe_ViraDocumentoComChaveEDataDeEmissao;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([Item(10, 'resNFe', XmlResNFe(CHAVE_1))]);

  AssertEquals(1, Length(LEventos));
  AssertEquals('nfe', LEventos[0].TipoDocumento);
  AssertEquals(Ord(dcDocumento), Ord(LEventos[0].Categoria));
  AssertEquals('', LEventos[0].TipoEvento);
  AssertEquals(CHAVE_1, LEventos[0].ChaveAcesso);
  // horario de parede escrito no documento, fuso descartado
  AssertEquals(Double(EncodeDate(2026, 9, 10) + EncodeTime(14, 30, 5, 0)), Double(LEventos[0].DataEmissao), 1 / 86400 / 2);
end;

procedure TDFeProviderNFeTests.ResNFe_PreservaPayloadNSUUFECnpjConsultante;
var
  LEventos: TDFeEventoNormalizadoArray;
  LXml: string;
begin
  LXml := XmlResNFe(CHAVE_1);
  LEventos := Decodificar([Item(777, 'resNFe', LXml)]);

  AssertEquals(LXml, LEventos[0].XmlPayload);
  AssertEquals(Int64(777), LEventos[0].NSU);
  // UF e CNPJ vem do certificado consultante, nao do XML do documento
  AssertEquals(CertificadoTeste.UF, LEventos[0].UF);
  AssertEquals(CertificadoTeste.CnpjCpf, LEventos[0].CnpjCpfConsultante);
end;

procedure TDFeProviderNFeTests.ProcNFe_ChaveVemDoIdDeInfNFe;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([Item(11, 'procNFe', XmlProcNFe(CHAVE_2, '<dhEmi>2026-09-09T08:00:00-03:00</dhEmi>'))]);

  AssertEquals(1, Length(LEventos));
  AssertEquals(Ord(dcDocumento), Ord(LEventos[0].Categoria));
  AssertEquals(CHAVE_2, LEventos[0].ChaveAcesso);
  AssertEquals(Double(EncodeDate(2026, 9, 9) + EncodeTime(8, 0, 0, 0)), Double(LEventos[0].DataEmissao), 1 / 86400 / 2);
end;

procedure TDFeProviderNFeTests.ProcNFe_SemDhEmi_UsaDEmi;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([Item(11, 'procNFe', XmlProcNFe(CHAVE_2, '<dEmi>2014-03-05</dEmi>'))]);

  AssertEquals(Double(EncodeDate(2014, 3, 5)), Double(LEventos[0].DataEmissao), 1 / 86400 / 2);
end;

procedure TDFeProviderNFeTests.ResEvento_Ciencia_ViraEventoCiencia;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([Item(20, 'resEvento', XmlResEvento(CHAVE_1, '210210'))]);

  AssertEquals(1, Length(LEventos));
  AssertEquals(Ord(dcEvento), Ord(LEventos[0].Categoria));
  AssertEquals('ciencia', LEventos[0].TipoEvento);
  AssertEquals(CHAVE_1, LEventos[0].ChaveAcesso);
  AssertEquals(Double(EncodeDate(2026, 9, 11) + EncodeTime(9, 15, 0, 0)), Double(LEventos[0].DataEmissao), 1 / 86400 / 2);
end;

procedure TDFeProviderNFeTests.ResEvento_Cancelamento_ViraEventoCancelamento;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([Item(21, 'resEvento', XmlResEvento(CHAVE_1, '110111'))]);

  AssertEquals('cancelamento', LEventos[0].TipoEvento);
end;

procedure TDFeProviderNFeTests.ProcEventoNFe_UsaPrimeiroTpEventoDoInfEvento;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([Item(22, 'procEventoNFe', XmlProcEventoNFe(CHAVE_3, '110111'))]);

  AssertEquals(1, Length(LEventos));
  AssertEquals(Ord(dcEvento), Ord(LEventos[0].Categoria));
  AssertEquals('cancelamento', LEventos[0].TipoEvento);
  AssertEquals(CHAVE_3, LEventos[0].ChaveAcesso);
  AssertEquals(Double(EncodeDate(2026, 9, 12) + EncodeTime(10, 0, 0, 0)), Double(LEventos[0].DataEmissao), 1 / 86400 / 2);
end;

procedure TDFeProviderNFeTests.Evento_TipoSemNomeMapeado_UsaCodigoNumerico;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([Item(23, 'resEvento', XmlResEvento(CHAVE_1, '110150'))]);

  AssertEquals('110150', LEventos[0].TipoEvento);
end;

procedure TDFeProviderNFeTests.SchemaComNomeDeArquivoOficial_EhReconhecido;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([Item(10, 'resNFe_v1.01.xsd', XmlResNFe(CHAVE_1))]);

  AssertEquals(1, Length(LEventos));
  AssertEquals(CHAVE_1, LEventos[0].ChaveAcesso);
end;

procedure TDFeProviderNFeTests.SchemaDesconhecido_EhIgnoradoSemAfetarOsDemais;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([
    Item(10, 'resNFe', XmlResNFe(CHAVE_1)),
    Item(11, 'schemaFuturoDaSefaz', '<qualquer/>'),
    Item(12, 'resNFe', XmlResNFe(CHAVE_2))]);

  AssertEquals(2, Length(LEventos));
  AssertEquals(CHAVE_1, LEventos[0].ChaveAcesso);
  AssertEquals(CHAVE_2, LEventos[1].ChaveAcesso);
end;

procedure TDFeProviderNFeTests.VariosItens_PreservamOrdem;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([
    Item(1, 'resNFe', XmlResNFe(CHAVE_1)),
    Item(2, 'resEvento', XmlResEvento(CHAVE_1, '210210')),
    Item(3, 'procNFe', XmlProcNFe(CHAVE_2, '<dhEmi>2026-09-09T08:00:00-03:00</dhEmi>'))]);

  AssertEquals(3, Length(LEventos));
  AssertEquals(Int64(1), LEventos[0].NSU);
  AssertEquals(Int64(2), LEventos[1].NSU);
  AssertEquals(Int64(3), LEventos[2].NSU);
end;

procedure TDFeProviderNFeTests.ResNFe_SemChave_Levanta;
begin
  AssertItemInvalidoLevanta(Item(10, 'resNFe', '<resNFe><dhEmi>2026-09-10T14:30:05-03:00</dhEmi></resNFe>'));
end;

procedure TDFeProviderNFeTests.ResNFe_ChaveCom43Digitos_Levanta;
begin
  AssertItemInvalidoLevanta(Item(10, 'resNFe', XmlResNFe(Copy(CHAVE_1, 1, 43))));
end;

procedure TDFeProviderNFeTests.ResEvento_SemTpEvento_Levanta;
begin
  AssertItemInvalidoLevanta(Item(10, 'resEvento', '<resEvento><chNFe>' + CHAVE_1 + '</chNFe></resEvento>'));
end;

procedure TDFeProviderNFeTests.DataEmissaoIlegivel_Vira0;
var
  LEventos: TDFeEventoNormalizadoArray;
begin
  LEventos := Decodificar([Item(10, 'resNFe',
    '<resNFe><chNFe>' + CHAVE_1 + '</chNFe><dhEmi>ontem</dhEmi></resNFe>')]);

  AssertEquals(Double(0), Double(LEventos[0].DataEmissao), 0.0);
end;

procedure TDFeProviderNFeTests.NomeTipoEventoNFe_ManifestacaoUsaVocabularioDoManifestador;
begin
  AssertEquals('confirmacao', NomeTipoEventoNFe('210200'));
  AssertEquals('ciencia', NomeTipoEventoNFe('210210'));
  AssertEquals('desconhecimento', NomeTipoEventoNFe('210220'));
  AssertEquals('operacaonaorealizada', NomeTipoEventoNFe('210240'));
end;

initialization
  RegisterTest(TDFeProviderNFeTests);

end.
