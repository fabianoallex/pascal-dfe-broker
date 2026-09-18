unit DFe.Simulador.Fixtures;

{$I dfe.inc}

{ Gerador de fixtures 100% SINTETICAS (CNPJ/chave/nomes inventados) dos 4
  schemas da Distribuicao de DFe de NFe, para o simulador da SEFAZ --
  ver docs/simulador-sefaz.md, Fase 2, e CONTRIBUTING.md ("Certificados e
  dados sensiveis"). Nenhum dado real, nunca.

  Construidas a partir dos layouts dos schemas oficiais, so' com os
  campos que o provider (DFe.Provider.NFe) e a distribuicao usam -- NAO sao
  documentos completos/validos contra o XSD (por isso nao servem para
  testar validacao de schema, so' o caminho de distribuicao). Os testes
  passam estas fixtures pelo TDFeProviderNFe REAL para garantir que o
  simulador nao gera nada que o provider nao entenda. }

interface

const
  { Nomes de schema exatamente como a SEFAZ os declara no atributo
    schema="" de <docZip> (o client real devolve a forma curta, 'resNFe';
    o provider aceita as duas -- ver DFe.Provider.NFe.SchemaDoItem). }
  DFE_SIM_SCHEMA_RESNFE = 'resNFe_v1.01.xsd';
  DFE_SIM_SCHEMA_PROCNFE = 'procNFe_v4.00.xsd';
  DFE_SIM_SCHEMA_RESEVENTO = 'resEvento_v1.01.xsd';
  DFE_SIM_SCHEMA_PROCEVENTONFE = 'procEventoNFe_v1.00.xsd';

  DFE_SIM_CNPJ_EMITENTE = '98765432000110';
  DFE_SIM_XNOME_EMITENTE = 'EMITENTE SINTETICO LTDA';

{ Chave de acesso de 44 digitos com DIGITO VERIFICADOR correto (modulo 11):
  UF 35, AAMM 2609, CNPJ do emitente, modelo 55, serie 001, ANumero como
  numero da nota, tpEmis 1, cNF derivado de ANumero. Determinística. }
function ChaveNFeSintetica(const ACnpjEmitente: string; const ANumero: Integer): string;

function XmlResNFe(const AChave: string;
  const ACnpjEmitente: string = DFE_SIM_CNPJ_EMITENTE;
  const AXNome: string = DFE_SIM_XNOME_EMITENTE): string;

{ ADhEmi no formato do schema, ex.: '2026-09-10T14:30:05-03:00'. }
function XmlProcNFe(const AChave: string;
  const ACnpjEmitente: string = DFE_SIM_CNPJ_EMITENTE;
  const ADhEmi: string = '2026-09-10T14:30:05-03:00'): string;

function XmlResEvento(const AChave, ATpEvento: string): string;

function XmlProcEventoNFe(const AChave, ATpEvento: string): string;

implementation

uses
  SysUtils;

function DigitoVerificadorChave(const AChave43: string): Char;
var
  I, LPeso, LSoma, LResto: Integer;
begin
  LSoma := 0;
  LPeso := 2;
  for I := Length(AChave43) downto 1 do
  begin
    LSoma := LSoma + (Ord(AChave43[I]) - Ord('0')) * LPeso;
    Inc(LPeso);
    if LPeso > 9 then
      LPeso := 2;
  end;
  LResto := LSoma mod 11;
  if LResto < 2 then
    Result := '0'
  else
    Result := Chr(Ord('0') + (11 - LResto));
end;

function ChaveNFeSintetica(const ACnpjEmitente: string; const ANumero: Integer): string;
var
  LChave43: string;
begin
  LChave43 := '35' + '2609' + ACnpjEmitente + '55' + '001' +
    Format('%.9d', [ANumero]) + '1' + Format('%.8d', [(ANumero * 7919) mod 100000000]);
  Result := LChave43 + DigitoVerificadorChave(LChave43);
end;

function XmlResNFe(const AChave, ACnpjEmitente, AXNome: string): string;
begin
  Result :=
    '<resNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.01">' +
    '<chNFe>' + AChave + '</chNFe>' +
    '<CNPJ>' + ACnpjEmitente + '</CNPJ>' +
    '<xNome>' + AXNome + '</xNome>' +
    '<IE>1234567890</IE>' +
    '<dhEmi>2026-09-10T14:30:05-03:00</dhEmi>' +
    '<tpNF>1</tpNF><vNF>150.00</vNF>' +
    '<digVal>AAAAAAAAAAAAAAAAAAAAAAAAAAA=</digVal>' +
    '<dhRecbto>2026-09-10T14:31:00-03:00</dhRecbto>' +
    '<nProt>143260000000001</nProt><cSitNFe>1</cSitNFe>' +
    '</resNFe>';
end;

function XmlProcNFe(const AChave, ACnpjEmitente, ADhEmi: string): string;
begin
  Result :=
    '<nfeProc xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">' +
    '<NFe><infNFe versao="4.00" Id="NFe' + AChave + '">' +
    '<ide><cUF>35</cUF><natOp>VENDA</natOp><mod>55</mod>' +
    '<dhEmi>' + ADhEmi + '</dhEmi></ide>' +
    '<emit><CNPJ>' + ACnpjEmitente + '</CNPJ><xNome>' + DFE_SIM_XNOME_EMITENTE + '</xNome></emit>' +
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

end.
