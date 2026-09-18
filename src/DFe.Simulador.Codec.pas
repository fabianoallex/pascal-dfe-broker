unit DFe.Simulador.Codec;

{$I dfe.inc}

{ Codec do envelope de transporte do docZip (gzip + base64) para o
  simulador da SEFAZ -- ver docs/simulador-sefaz.md, Fase 2.

  Puro Pascal, sem zlib e sem ACBr, identico nos dois compiladores: o gzip
  produzido usa blocos deflate ARMAZENADOS (BTYPE=00, sem compressao).
  E' gzip valido (qualquer gunzip/zlib le), so' nao e' menor que o
  original -- irrelevante para simular a SEFAZ, e evita depender de
  zstream (so' FPC) ou de System.ZLib (API diferente no Delphi).

  Convencao de encoding do projeto: XML e' UTF-8 EMBUTIDO em String (ver
  CLAUDE.md, decisao 18 e docs/simulador-sefaz.md, achado de encoding). No
  FPC (String = bytes) os bytes sao usados como estao; no Delphi
  (UnicodeString) a string e' codificada em UTF-8. }

interface

uses
  SysUtils;

function CRC32Bytes(const ADados: TBytes): Cardinal;

function StringParaBytesUtf8(const AXml: string): TBytes;

{ gzip completo (cabecalho + blocos armazenados + CRC32 + ISIZE). }
function GzipArmazenado(const ADados: TBytes): TBytes;

{ Devolve um gzip INVALIDO derivado de um valido: cabecalho intacto,
  corpo cortado ao meio e sem trailer -- para simular docZip corrompido. }
function CorromperGzip(const AGzip: TBytes): TBytes;

function Base64Codificar(const ADados: TBytes): string;

{ XML -> UTF-8 -> gzip -> base64: o conteudo de um elemento <docZip>. }
function MontarDocZip(const AXml: string): string;
function MontarDocZipCorrompido(const AXml: string): string;

implementation

const
  TAMANHO_MAX_BLOCO = 65535;
  ALFABETO_BASE64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

var
  TabelaCRC: array[0..255] of Cardinal;
  TabelaCRCPronta: Boolean = False;

procedure PrepararTabelaCRC;
var
  I, K: Integer;
  C: Cardinal;
begin
  for I := 0 to 255 do
  begin
    C := Cardinal(I);
    for K := 1 to 8 do
      if (C and 1) <> 0 then
        C := (C shr 1) xor $EDB88320
      else
        C := C shr 1;
    TabelaCRC[I] := C;
  end;
  TabelaCRCPronta := True;
end;

function CRC32Bytes(const ADados: TBytes): Cardinal;
var
  I: Integer;
begin
  if not TabelaCRCPronta then
    PrepararTabelaCRC;
  Result := $FFFFFFFF;
  for I := 0 to High(ADados) do
    Result := TabelaCRC[(Result xor ADados[I]) and $FF] xor (Result shr 8);
  Result := Result xor $FFFFFFFF;
end;

function StringParaBytesUtf8(const AXml: string): TBytes;
begin
  {$IFDEF FPC}
  SetLength(Result, Length(AXml));
  if Length(AXml) > 0 then
    Move(AXml[1], Result[0], Length(AXml));
  {$ELSE}
  Result := TEncoding.UTF8.GetBytes(AXml);
  {$ENDIF}
end;

procedure Anexar(var ADestino: TBytes; var AUsado: Integer; const AByte: Byte);
begin
  ADestino[AUsado] := AByte;
  Inc(AUsado);
end;

procedure AnexarLE32(var ADestino: TBytes; var AUsado: Integer; const AValor: Cardinal);
begin
  Anexar(ADestino, AUsado, AValor and $FF);
  Anexar(ADestino, AUsado, (AValor shr 8) and $FF);
  Anexar(ADestino, AUsado, (AValor shr 16) and $FF);
  Anexar(ADestino, AUsado, (AValor shr 24) and $FF);
end;

function GzipArmazenado(const ADados: TBytes): TBytes;
var
  LBlocos, LUsado, LPos, LTam, I: Integer;
  LFinal: Boolean;
begin
  { Sempre ao menos um bloco (final), mesmo para entrada vazia. }
  LBlocos := (Length(ADados) + TAMANHO_MAX_BLOCO - 1) div TAMANHO_MAX_BLOCO;
  if LBlocos = 0 then
    LBlocos := 1;

  SetLength(Result, 10 + LBlocos * 5 + Length(ADados) + 8);
  LUsado := 0;

  // cabecalho: magic, CM=8 (deflate), FLG=0, MTIME=0, XFL=0, OS=255 (desconhecido)
  Anexar(Result, LUsado, $1F);
  Anexar(Result, LUsado, $8B);
  Anexar(Result, LUsado, $08);
  Anexar(Result, LUsado, $00);
  AnexarLE32(Result, LUsado, 0);
  Anexar(Result, LUsado, $00);
  Anexar(Result, LUsado, $FF);

  LPos := 0;
  repeat
    LTam := Length(ADados) - LPos;
    if LTam > TAMANHO_MAX_BLOCO then
      LTam := TAMANHO_MAX_BLOCO;
    LFinal := (LPos + LTam) >= Length(ADados);

    // BFINAL (bit 0) + BTYPE=00 (armazenado); alinhado a byte
    if LFinal then
      Anexar(Result, LUsado, $01)
    else
      Anexar(Result, LUsado, $00);
    Anexar(Result, LUsado, LTam and $FF);
    Anexar(Result, LUsado, (LTam shr 8) and $FF);
    Anexar(Result, LUsado, (not LTam) and $FF);
    Anexar(Result, LUsado, ((not LTam) shr 8) and $FF);
    for I := 0 to LTam - 1 do
      Anexar(Result, LUsado, ADados[LPos + I]);
    Inc(LPos, LTam);
  until LFinal;

  AnexarLE32(Result, LUsado, CRC32Bytes(ADados));
  AnexarLE32(Result, LUsado, Cardinal(Length(ADados)));
end;

function CorromperGzip(const AGzip: TBytes): TBytes;
var
  LCorte: Integer;
begin
  if Length(AGzip) <= 10 then
    LCorte := Length(AGzip)
  else
    LCorte := 10 + (Length(AGzip) - 10) div 2;
  SetLength(Result, LCorte);
  if LCorte > 0 then
    Move(AGzip[0], Result[0], LCorte);
end;

function Base64Codificar(const ADados: TBytes): string;
var
  I, N, P: Integer;
  B0, B1, B2: Cardinal;
begin
  N := Length(ADados);
  SetLength(Result, ((N + 2) div 3) * 4);
  I := 0;
  P := 1;
  while I < N do
  begin
    B0 := ADados[I];
    if I + 1 < N then B1 := ADados[I + 1] else B1 := 0;
    if I + 2 < N then B2 := ADados[I + 2] else B2 := 0;

    Result[P] := ALFABETO_BASE64[1 + (B0 shr 2)];
    Result[P + 1] := ALFABETO_BASE64[1 + (((B0 and 3) shl 4) or (B1 shr 4))];
    if I + 1 < N then
      Result[P + 2] := ALFABETO_BASE64[1 + (((B1 and 15) shl 2) or (B2 shr 6))]
    else
      Result[P + 2] := '=';
    if I + 2 < N then
      Result[P + 3] := ALFABETO_BASE64[1 + (B2 and 63)]
    else
      Result[P + 3] := '=';
    Inc(I, 3);
    Inc(P, 4);
  end;
end;

function MontarDocZip(const AXml: string): string;
begin
  Result := Base64Codificar(GzipArmazenado(StringParaBytesUtf8(AXml)));
end;

function MontarDocZipCorrompido(const AXml: string): string;
begin
  Result := Base64Codificar(CorromperGzip(GzipArmazenado(StringParaBytesUtf8(AXml))));
end;

end.
