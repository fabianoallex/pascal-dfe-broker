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

{ O inverso de TextoDoAcbr: texto nativo -> como o ACBr o guarda/espera. Serve
  a quem FALA COM o ACBr por fora dele (o transporte HTTP do simulador,
  DFe.Transmissor.Http, e o servidor do simulador): o adaptador SOAP do
  simulador trabalha com o texto na convencao do ACBr, mas pela rede trafegam
  bytes UTF-8 de verdade. No FPC e' a identidade; no Delphi, os bytes UTF-8 do
  texto viram caracteres pela pagina ANSI do sistema (o mesmo mojibake que o
  ACBr produz), de modo que TextoDoAcbr(TextoParaAcbr(X)) = X. }
function TextoParaAcbr(const ATextoNativo: string): string;

{ Numero de CARACTERES (nao de bytes) do texto nativo do compilador. No FPC a
  String carrega bytes UTF-8, entao Length superconta acentos ('nao' com til =
  4 bytes, 3 caracteres) e um limite como o "15 a 255 caracteres" do xJust
  seria medido errado. No Delphi e' Length. }
function TamanhoEmCaracteres(const ATexto: string): Integer;

{ True se TODOS os caracteres estao em U+0020..U+00FF -- o que o tipo TMotivo do
  XSD (xJust) aceita ("[ -U+00FF]"). Fora disso (aspas curvas, travessao, emoji,
  quebra de linha, tab) o XSD REJEITA o evento; como o broker mantem os acentos
  (Geral.RetirarAcentos = False, ver DFe.Client.ACBrNFe), a recusa precisa vir
  antes, com mensagem clara. No FPC, decodifica o UTF-8 (so' ASCII imprimivel e
  as sequencias C2/C3 cabem). }
function TextoAceitoPeloXsdDeMotivo(const ATexto: string): Boolean;

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

function TextoParaAcbr(const ATextoNativo: string): string;
{$IFNDEF FPC}
var
  LBytes: TBytes;
  LAnsi: AnsiString;
{$ENDIF}
begin
  {$IFDEF FPC}
  Result := ATextoNativo;
  {$ELSE}
  if ATextoNativo = '' then
  begin
    Result := '';
    Exit;
  end;
  // Bytes UTF-8 crus num AnsiString com a pagina ANSI -- NAO AnsiString(UTF8Encode(...)),
  // que converteria TEXTO (ver o comentario de ComoOAcbrEntrega nos testes).
  LBytes := TEncoding.UTF8.GetBytes(ATextoNativo);
  SetString(LAnsi, PAnsiChar(@LBytes[0]), Length(LBytes));
  Result := string(LAnsi);
  {$ENDIF}
end;

function TamanhoEmCaracteres(const ATexto: string): Integer;
{$IFDEF FPC}
var
  I: Integer;
{$ENDIF}
begin
  {$IFDEF FPC}
  Result := 0;
  for I := 1 to Length(ATexto) do
    if (Ord(ATexto[I]) and $C0) <> $80 then // nao e' byte de continuacao
      Inc(Result);
  {$ELSE}
  Result := Length(ATexto);
  {$ENDIF}
end;

function TextoAceitoPeloXsdDeMotivo(const ATexto: string): Boolean;
var
  I, B: Integer;
begin
  Result := False;
  {$IFDEF FPC}
  I := 1;
  while I <= Length(ATexto) do
  begin
    B := Ord(ATexto[I]);
    if B < $20 then
      Exit
    else if B < $80 then
      Inc(I)
    else if (B = $C2) or (B = $C3) then // U+0080..U+00FF em 2 bytes
    begin
      if (I + 1 > Length(ATexto)) or ((Ord(ATexto[I + 1]) and $C0) <> $80) then
        Exit;
      Inc(I, 2);
    end
    else
      Exit;
  end;
  {$ELSE}
  for I := 1 to Length(ATexto) do
  begin
    B := Ord(ATexto[I]);
    if (B < $20) or (B > $FF) then
      Exit;
  end;
  {$ENDIF}
  Result := True;
end;

end.
