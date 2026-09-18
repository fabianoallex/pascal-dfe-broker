unit DFe.XmlTextoTests;

{ No FPC, TextoDoAcbr e' a identidade: String ja carrega os bytes UTF-8 e o
  contrato do projeto E' esse (ver DFe.XmlTexto). O comportamento de
  conversao mora no espelho Delphi (tests/Unit/DFe.XmlTextoTests.pas), que
  NAO e' 1:1 com este arquivo de proposito. }

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils,
  DFe.XmlTexto;

type
  TDFeXmlTextoTests = class(TTestCase)
  published
    procedure Ascii_Inalterado;
    procedure BytesUtf8_PassamSemConversao;
    procedure Vazio_Inalterado;
  end;

implementation

procedure TDFeXmlTextoTests.Ascii_Inalterado;
begin
  AssertEquals('<xNome>ACME LTDA</xNome>', TextoDoAcbr('<xNome>ACME LTDA</xNome>'));
end;

procedure TDFeXmlTextoTests.BytesUtf8_PassamSemConversao;
var
  LUtf8: string;
begin
  // "JOSE" com E acentuado, como bytes UTF-8 (C3 89)
  LUtf8 := 'JOS' + #$C3#$89;
  AssertEquals(LUtf8, TextoDoAcbr(LUtf8));
end;

procedure TDFeXmlTextoTests.Vazio_Inalterado;
begin
  AssertEquals('', TextoDoAcbr(''));
end;

initialization
  RegisterTest(TDFeXmlTextoTests);

end.
