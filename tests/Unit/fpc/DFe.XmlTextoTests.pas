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
    procedure TextoParaAcbr_EIdentidadeEInverso;
    procedure Tamanho_ContaCaracteresNaoBytes;
    procedure Motivo_AceitaAcentosLatin1;
    procedure Motivo_RecusaForaDeLatin1;
    procedure Motivo_RecusaControleEUtf8Truncado;
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

procedure TDFeXmlTextoTests.TextoParaAcbr_EIdentidadeEInverso;
var
  LUtf8: string;
begin
  LUtf8 := 'JOS' + #$C3#$89;
  AssertEquals(LUtf8, TextoParaAcbr(LUtf8));
  AssertEquals(LUtf8, TextoDoAcbr(TextoParaAcbr(LUtf8)));
  AssertEquals('', TextoParaAcbr(''));
end;

procedure TDFeXmlTextoTests.Vazio_Inalterado;
begin
  AssertEquals('', TextoDoAcbr(''));
end;

procedure TDFeXmlTextoTests.Tamanho_ContaCaracteresNaoBytes;
begin
  AssertEquals(0, TamanhoEmCaracteres(''));
  AssertEquals(3, TamanhoEmCaracteres('abc'));
  // a-til (C3 A3): n + a-til + o = 4 bytes, 3 caracteres
  AssertEquals(3, TamanhoEmCaracteres('n' + #$C3#$A3 + 'o'));
  // travessao U+2014 = E2 80 94: 3 bytes, 1 caractere
  AssertEquals(1, TamanhoEmCaracteres(#$E2#$80#$94));
end;

procedure TDFeXmlTextoTests.Motivo_AceitaAcentosLatin1;
begin
  AssertTrue(TextoAceitoPeloXsdDeMotivo(''));
  AssertTrue(TextoAceitoPeloXsdDeMotivo('Operacao nao realizada'));
  AssertTrue(TextoAceitoPeloXsdDeMotivo('Opera' + #$C3#$A7 + #$C3#$A3 + 'o n' + #$C3#$A3 + 'o realizada'));
  AssertTrue(TextoAceitoPeloXsdDeMotivo(#$C3#$BF)); // U+00FF, o limite
  AssertTrue(TextoAceitoPeloXsdDeMotivo(#$C2#$A0)); // U+00A0
end;

procedure TDFeXmlTextoTests.Motivo_RecusaForaDeLatin1;
begin
  AssertFalse(TextoAceitoPeloXsdDeMotivo(#$E2#$80#$94));       // travessao U+2014
  AssertFalse(TextoAceitoPeloXsdDeMotivo(#$E2#$80#$9C + 'x')); // aspas curvas
  AssertFalse(TextoAceitoPeloXsdDeMotivo(#$C4#$80));           // U+0100, logo acima do limite
  AssertFalse(TextoAceitoPeloXsdDeMotivo(#$F0#$9F#$98#$80));   // emoji
end;

procedure TDFeXmlTextoTests.Motivo_RecusaControleEUtf8Truncado;
begin
  AssertFalse(TextoAceitoPeloXsdDeMotivo('a' + #10 + 'b'));
  AssertFalse(TextoAceitoPeloXsdDeMotivo('a' + #9 + 'b'));
  AssertFalse(TextoAceitoPeloXsdDeMotivo('a' + #$C3));  // lead sem continuacao
  AssertFalse(TextoAceitoPeloXsdDeMotivo(#$C3 + 'a'));  // continuacao invalida
end;

initialization
  RegisterTest(TDFeXmlTextoTests);

end.
