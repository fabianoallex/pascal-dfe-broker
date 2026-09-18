unit DFe.SimuladorCodecTests;

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils,
  DFe.Simulador.Codec;

type
  TDFeSimuladorCodecTests = class(TTestCase)
  published
    procedure Crc32_VetorConhecido;
    procedure Crc32_Vazio_EhZero;
    procedure Base64_VetoresDaRfc4648;
    procedure Gzip_CabecalhoTrailerETamanho;
    procedure Gzip_RoundTrip_Pequeno;
    procedure Gzip_RoundTrip_Vazio;
    procedure Gzip_MaiorQueUmBloco_UsaDoisBlocosEFazRoundTrip;
    procedure Gzip_Corrompido_NaoDecodifica;
    procedure Utf8_AsciiPreservado;
    procedure DocZip_ComecaComMagicDoGzipEmBase64;
  end;

implementation

function Bytes(const S: string): TBytes;
begin
  Result := StringParaBytesUtf8(S);
end;

function BytesComoString(const B: TBytes): string;
begin
  SetLength(Result, Length(B));
  if Length(B) > 0 then
    Move(B[0], Result[1], Length(B));
end;

{ Decodificador independente (do lado do teste) de gzip com blocos
  armazenados: confere cabecalho, encadeia os blocos, confere NLEN, CRC32 e
  ISIZE. Devolve False em qualquer inconsistencia. So' entende BTYPE=00 --
  suficiente, pois e' o unico que o codec produz. }
function DecodificarGzipArmazenado(const AGz: TBytes; out ADados: TBytes;
  out ABlocos: Integer): Boolean;
var
  LPos, LTam, LNTam, LUsado: Integer;
  LFinal: Boolean;
  LCrc, LIsize: Cardinal;
begin
  Result := False;
  ABlocos := 0;
  ADados := nil;
  if Length(AGz) < 18 then Exit;
  if (AGz[0] <> $1F) or (AGz[1] <> $8B) or (AGz[2] <> 8) or (AGz[3] <> 0) then Exit;

  LPos := 10;
  LUsado := 0;
  SetLength(ADados, Length(AGz));
  repeat
    if LPos + 5 > Length(AGz) then Exit;
    LFinal := (AGz[LPos] and 1) = 1;
    if (AGz[LPos] and $FE) <> 0 then Exit; // BTYPE deve ser 00
    LTam := AGz[LPos + 1] or (AGz[LPos + 2] shl 8);
    LNTam := AGz[LPos + 3] or (AGz[LPos + 4] shl 8);
    if LNTam <> ((not LTam) and $FFFF) then Exit;
    Inc(LPos, 5);
    if LPos + LTam > Length(AGz) then Exit;
    if LTam > 0 then
      Move(AGz[LPos], ADados[LUsado], LTam);
    Inc(LUsado, LTam);
    Inc(LPos, LTam);
    Inc(ABlocos);
  until LFinal;

  if LPos + 8 <> Length(AGz) then Exit;
  LCrc := AGz[LPos] or (AGz[LPos + 1] shl 8) or (AGz[LPos + 2] shl 16) or (Cardinal(AGz[LPos + 3]) shl 24);
  LIsize := AGz[LPos + 4] or (AGz[LPos + 5] shl 8) or (AGz[LPos + 6] shl 16) or (Cardinal(AGz[LPos + 7]) shl 24);
  SetLength(ADados, LUsado);
  Result := (LIsize = Cardinal(LUsado)) and (LCrc = CRC32Bytes(ADados));
end;

{ TDFeSimuladorCodecTests }

procedure TDFeSimuladorCodecTests.Crc32_VetorConhecido;
begin
  // vetor padrao de verificacao do CRC-32 (IEEE 802.3): "123456789"
  AssertTrue(CRC32Bytes(Bytes('123456789')) = $CBF43926);
end;

procedure TDFeSimuladorCodecTests.Crc32_Vazio_EhZero;
begin
  AssertTrue(CRC32Bytes(Bytes('')) = 0);
end;

procedure TDFeSimuladorCodecTests.Base64_VetoresDaRfc4648;
begin
  AssertEquals('', Base64Codificar(Bytes('')));
  AssertEquals('Zg==', Base64Codificar(Bytes('f')));
  AssertEquals('Zm8=', Base64Codificar(Bytes('fo')));
  AssertEquals('Zm9v', Base64Codificar(Bytes('foo')));
  AssertEquals('Zm9vYg==', Base64Codificar(Bytes('foob')));
  AssertEquals('Zm9vYmE=', Base64Codificar(Bytes('fooba')));
  AssertEquals('Zm9vYmFy', Base64Codificar(Bytes('foobar')));
end;

procedure TDFeSimuladorCodecTests.Gzip_CabecalhoTrailerETamanho;
var
  LGz: TBytes;
begin
  LGz := GzipArmazenado(Bytes('abc'));
  AssertEquals(Integer($1F), Integer(LGz[0]));
  AssertEquals(Integer($8B), Integer(LGz[1]));
  AssertEquals(Integer(8), Integer(LGz[2]));
  // 10 (cabecalho) + 5 (bloco) + 3 (dados) + 8 (trailer)
  AssertEquals(26, Length(LGz));
  // ISIZE = 3, little-endian, nos 4 ultimos bytes
  AssertEquals(Integer(3), Integer(LGz[22]));
  AssertEquals(Integer(0), Integer(LGz[23]));
end;

procedure TDFeSimuladorCodecTests.Gzip_RoundTrip_Pequeno;
var
  LDados: TBytes;
  LBlocos: Integer;
begin
  AssertTrue(DecodificarGzipArmazenado(GzipArmazenado(Bytes('<resNFe>ola</resNFe>')), LDados, LBlocos));
  AssertEquals('<resNFe>ola</resNFe>', BytesComoString(LDados));
  AssertEquals(1, LBlocos);
end;

procedure TDFeSimuladorCodecTests.Gzip_RoundTrip_Vazio;
var
  LDados: TBytes;
  LBlocos: Integer;
begin
  AssertTrue(DecodificarGzipArmazenado(GzipArmazenado(Bytes('')), LDados, LBlocos));
  AssertEquals(0, Length(LDados));
  AssertEquals(1, LBlocos);
end;

procedure TDFeSimuladorCodecTests.Gzip_MaiorQueUmBloco_UsaDoisBlocosEFazRoundTrip;
var
  LOriginal, LDados: TBytes;
  LGz: TBytes;
  LBlocos, I: Integer;
begin
  SetLength(LOriginal, 70000);
  for I := 0 to High(LOriginal) do
    LOriginal[I] := Byte(I mod 251);

  LGz := GzipArmazenado(LOriginal);
  AssertTrue(DecodificarGzipArmazenado(LGz, LDados, LBlocos));
  AssertEquals(2, LBlocos);
  AssertEquals(70000, Length(LDados));
  AssertTrue(CompareMem(@LOriginal[0], @LDados[0], 70000));
end;

procedure TDFeSimuladorCodecTests.Gzip_Corrompido_NaoDecodifica;
var
  LDados: TBytes;
  LBlocos: Integer;
begin
  AssertFalse(DecodificarGzipArmazenado(
    CorromperGzip(GzipArmazenado(Bytes('<resNFe>conteudo qualquer para cortar</resNFe>'))),
    LDados, LBlocos));
end;

procedure TDFeSimuladorCodecTests.Utf8_AsciiPreservado;
var
  LB: TBytes;
begin
  LB := StringParaBytesUtf8('abc');
  AssertEquals(3, Length(LB));
  AssertEquals(Integer(Ord('a')), Integer(LB[0]));
  AssertEquals(Integer(Ord('c')), Integer(LB[2]));
end;

procedure TDFeSimuladorCodecTests.DocZip_ComecaComMagicDoGzipEmBase64;
begin
  // 1F 8B 08 00 | 00 00 00 00 (mtime) | 00 (xfl) | FF (os) -> "H4sIAAAAAAAA..."
  AssertEquals('H4sIAAAAAAAA', Copy(MontarDocZip('<x/>'), 1, 12));
  AssertEquals('H4sIAAAAAAAA', Copy(MontarDocZipCorrompido('<x/>' + '<y>algum conteudo</y>'), 1, 12));
end;

initialization
  RegisterTest(TDFeSimuladorCodecTests);

end.
