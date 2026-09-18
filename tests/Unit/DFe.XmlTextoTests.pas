unit DFe.XmlTextoTests;

{ Espelho DELPHI de tests/Unit/fpc/DFe.XmlTextoTests.pas -- NAO e' 1:1: no
  FPC TextoDoAcbr e' a identidade; aqui esta' a conversao de verdade (ver
  DFe.XmlTexto). O mojibake de entrada e' montado do MESMO jeito que o ACBr o
  produz: bytes UTF-8 tratados como texto ANSI do sistema. }

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  DFe.XmlTexto;

type
  [TestFixture]
  TDFeXmlTextoTests = class
  private
    function ComoOAcbrEntrega(const ATexto: string): string;
  public
    [Test] procedure Ascii_Inalterado;
    [Test] procedure Vazio_Inalterado;
    [Test] procedure Mojibake_VoltaAoTextoDeVerdade;
    [Test] procedure Mojibake_ExigeMesmoAConversao;
    [Test] procedure TextoUnicodeDeVerdade_NaoEUtf8Valido_FicaIntacto;
    [Test] procedure XmlCompleto_ComAcentos_VoltaIgual;
  end;

implementation

const
  TEXTO_ACENTUADO = 'JOS' + #$00C9 + ' A' + #$00C7 + 'A' + #$00CD + ' LTDA'; // JOSE ACAI LTDA com acentos

{ ACBr no Delphi: os bytes UTF-8 do documento viram caracteres pela pagina
  ANSI do sistema. ATENCAO: nao usar AnsiString(UTF8Encode(...)) -- o
  RawByteString de UTF8Encode e' MARCADO como UTF-8, e a conversao para
  AnsiString seria de TEXTO (E -> C9 -> E), nao a reinterpretacao de BYTES
  que o ACBr faz (ele tem os bytes crus num AnsiString com a pagina ANSI). }
function TDFeXmlTextoTests.ComoOAcbrEntrega(const ATexto: string): string;
var
  LBytes: TBytes;
  LAnsi: AnsiString;
begin
  LBytes := TEncoding.UTF8.GetBytes(ATexto);
  SetString(LAnsi, PAnsiChar(@LBytes[0]), Length(LBytes)); // bytes crus, pagina ANSI
  Result := string(LAnsi);
end;

procedure TDFeXmlTextoTests.Ascii_Inalterado;
begin
  Assert.AreEqual('<xNome>ACME LTDA</xNome>', TextoDoAcbr('<xNome>ACME LTDA</xNome>'));
end;

procedure TDFeXmlTextoTests.Vazio_Inalterado;
begin
  Assert.AreEqual('', TextoDoAcbr(''));
end;

procedure TDFeXmlTextoTests.Mojibake_VoltaAoTextoDeVerdade;
begin
  Assert.AreEqual(TEXTO_ACENTUADO, TextoDoAcbr(ComoOAcbrEntrega(TEXTO_ACENTUADO)));
end;

procedure TDFeXmlTextoTests.Mojibake_ExigeMesmoAConversao;
begin
  // pre-condicao: sem TextoDoAcbr o texto acentuado NAO e' o original (e' o bug que o teste de integracao achou)
  Assert.AreNotEqual(TEXTO_ACENTUADO, ComoOAcbrEntrega(TEXTO_ACENTUADO));
end;

procedure TDFeXmlTextoTests.TextoUnicodeDeVerdade_NaoEUtf8Valido_FicaIntacto;
begin
  // "E" acentuado sozinho: byte C9 em ANSI, que nao e' UTF-8 valido -- nao era o formato do ACBr
  Assert.AreEqual('JOS' + #$00C9, TextoDoAcbr('JOS' + #$00C9));
end;

procedure TDFeXmlTextoTests.XmlCompleto_ComAcentos_VoltaIgual;
const
  XML = '<?xml version="1.0" encoding="UTF-8"?><resNFe><xNome>' + TEXTO_ACENTUADO + '</xNome></resNFe>';
begin
  Assert.AreEqual(XML, TextoDoAcbr(ComoOAcbrEntrega(XML)));
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeXmlTextoTests);

end.
