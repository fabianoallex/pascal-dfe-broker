unit DFe.XmlTexto;

{$I dfe.inc}

{ Fronteira de ENCODING com o ACBr -- ver docs/architecture.md, "Encoding do
  XML (XmlDecodificado / XmlPayload)".

  ACHADO (teste de integracao em Delphi Win64, 2026-09-18): o ACBr guarda XML
  como "UTF-8 embutido em String". No FPC (String = bytes) isso e' invisivel:
  os bytes UTF-8 passam sem conversao. No DELPHI (String = UnicodeString) cada
  BYTE do UTF-8 vira um CARACTERE pela pagina de codigo ANSI do sistema -- "E"
  acentuado (UTF-8 C3 89) chega como U+00C3 U+2030 (o byte 89 e' "por mil" em
  Windows-1252), "C" cedilha como U+00C3 U+2021, etc. Publicado assim, o
  consumidor veria "JOSÃ‰" em vez de "JOSE" acentuado.

  O CONTRATO do projeto e' o texto NATIVO de cada compilador:
  - Delphi: UnicodeString com o texto de verdade (quem publica codifica em UTF-8);
  - FPC: String com os bytes UTF-8 (quem publica usa como esta).
  TextoDoAcbr converte o que vem do ACBr para esse contrato. E' a UNICA
  fronteira: so' DFe.Client.ACBrNFe a chama. }

interface

{ Converte texto de XML vindo do ACBr (docZip.XML, RetInfEvento.XML) para o
  texto nativo do compilador. No FPC e' a identidade. No Delphi: a volta pela
  pagina de codigo ANSI (a mesma usada na ida) devolve os bytes UTF-8
  originais, que sao entao decodificados. Se esses bytes NAO forem UTF-8 valido
  (ex.: uma versao futura do ACBr que ja devolva Unicode de verdade), devolve
  a entrada intacta em vez de corromper. }
function TextoDoAcbr(const ATextoDoAcbr: string): string;

implementation

{$IFNDEF FPC}
uses
  SysUtils;
{$ENDIF}

function TextoDoAcbr(const ATextoDoAcbr: string): string;
{$IFNDEF FPC}
var
  LAnsi: AnsiString;
  LBytes: TBytes;
{$ENDIF}
begin
  {$IFDEF FPC}
  Result := ATextoDoAcbr;
  {$ELSE}
  LAnsi := AnsiString(ATextoDoAcbr); // pagina ANSI do sistema: a mesma da ida
  SetLength(LBytes, Length(LAnsi));
  if Length(LAnsi) > 0 then
    Move(LAnsi[1], LBytes[0], Length(LAnsi));
  try
    Result := TEncoding.UTF8.GetString(LBytes);
  except
    on EEncodingError do // GetString LEVANTA (nao devolve U+FFFD) para UTF-8 invalido
    begin
      Result := ATextoDoAcbr;
      Exit;
    end;
  end;
  if Pos(#$FFFD, Result) > 0 then // U+FFFD no proprio texto: nao era o formato do ACBr
    Result := ATextoDoAcbr;
  {$ENDIF}
end;

end.
