unit DFe.Simulador.Json;

{$I dfe.inc}

{ JSON PLANO para a API admin do simulador: leitura de UM objeto cujos valores
  sao texto, numero, true/false, null ou uma lista desses -- sem objetos
  aninhados -- e um escape para montar respostas.

  Existe para nao depender de System.JSON (Delphi) x fpjson (FPC), que tem
  APIs diferentes (docs/simulador-standalone.md, decisao 3). O corpo das
  requisicoes admin e' deliberadamente plano, entao um leitor pequeno basta.

  Texto: nativo do compilador (FPC: bytes UTF-8, Delphi: UnicodeString). Os
  caracteres fora do ASCII passam como estao; \uXXXX (e o par substituto) vira o
  caractere nativo. }

interface

uses
  SysUtils, Classes;

type
  TDFeJsonLista = array of string;

  TDFeJsonPlano = class
  private
    FChaves: TStringList;
    FValores: TStringList;      // texto do valor; lista = itens unidos por #31
    FEhLista: TStringList;      // '1' se a chave e' uma lista
    function Indice(const AChave: string): Integer;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Definir(const AChave, AValor: string; const AEhLista: Boolean);

    function Tem(const AChave: string): Boolean;
    function Texto(const AChave: string; const APadrao: string = ''): string;
    { True se a chave existe E e' um inteiro (sem fracao nem expoente). }
    function EInteiro(const AChave: string): Boolean;
    function Inteiro(const AChave: string; const APadrao: Int64): Int64;
    function Booleano(const AChave: string; const APadrao: Boolean): Boolean;
    { Itens de uma lista; um valor escalar vira lista de 1 item; ausente = vazia. }
    function Lista(const AChave: string): TDFeJsonLista;
  end;

{ Le um objeto JSON plano. False (com AErro) se malformado ou aninhado; AObj = nil
  nesse caso. O chamador libera AObj. Texto vazio = objeto vazio. }
function LerJsonPlano(const ATexto: string; out AObj: TDFeJsonPlano;
  out AErro: string): Boolean;

{ Escapa para dentro de aspas de uma string JSON (sem as aspas). }
function JsonEscape(const ATexto: string): string;

{ '"' + JsonEscape + '"'. }
function JsonTexto(const ATexto: string): string;

implementation

const
  SEP_LISTA = #31;

function JsonEscape(const ATexto: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(ATexto) do
  begin
    C := ATexto[I];
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8: Result := Result + '\b';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if Ord(C) < 32 then
        Result := Result + '\u' + IntToHex(Ord(C), 4)
      else
        Result := Result + C;
    end;
  end;
end;

function JsonTexto(const ATexto: string): string;
begin
  Result := '"' + JsonEscape(ATexto) + '"';
end;

{ TDFeJsonPlano }

constructor TDFeJsonPlano.Create;
begin
  inherited Create;
  FChaves := TStringList.Create;
  FValores := TStringList.Create;
  FEhLista := TStringList.Create;
end;

destructor TDFeJsonPlano.Destroy;
begin
  FEhLista.Free;
  FValores.Free;
  FChaves.Free;
  inherited Destroy;
end;

function TDFeJsonPlano.Indice(const AChave: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FChaves.Count - 1 do
    if SameText(FChaves[I], AChave) then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

procedure TDFeJsonPlano.Definir(const AChave, AValor: string; const AEhLista: Boolean);
var
  I: Integer;
  LMarca: string;
begin
  if AEhLista then
    LMarca := '1'
  else
    LMarca := '0';
  I := Indice(AChave);
  if I < 0 then
  begin
    FChaves.Add(AChave);
    FValores.Add(AValor);
    FEhLista.Add(LMarca);
  end
  else
  begin
    FValores[I] := AValor;
    FEhLista[I] := LMarca;
  end;
end;

function TDFeJsonPlano.Tem(const AChave: string): Boolean;
begin
  Result := Indice(AChave) >= 0;
end;

function TDFeJsonPlano.Texto(const AChave, APadrao: string): string;
var
  I: Integer;
begin
  I := Indice(AChave);
  if I < 0 then
    Result := APadrao
  else
    Result := StringReplace(FValores[I], SEP_LISTA, ',', [rfReplaceAll]);
end;

function TDFeJsonPlano.EInteiro(const AChave: string): Boolean;
var
  I: Integer;
  LValor: Int64;
begin
  I := Indice(AChave);
  Result := (I >= 0) and (FEhLista[I] = '0') and TryStrToInt64(FValores[I], LValor);
end;

function TDFeJsonPlano.Inteiro(const AChave: string; const APadrao: Int64): Int64;
begin
  if EInteiro(AChave) then
    Result := StrToInt64(FValores[Indice(AChave)])
  else
    Result := APadrao;
end;

function TDFeJsonPlano.Booleano(const AChave: string; const APadrao: Boolean): Boolean;
var
  I: Integer;
begin
  I := Indice(AChave);
  if I < 0 then
    Result := APadrao
  else
    Result := SameText(FValores[I], 'true') or (FValores[I] = '1');
end;

function TDFeJsonPlano.Lista(const AChave: string): TDFeJsonLista;
var
  I, N, LIni, K: Integer;
  LValor: string;
begin
  SetLength(Result, 0);
  I := Indice(AChave);
  if I < 0 then
    Exit;
  LValor := FValores[I];
  if FEhLista[I] = '0' then
  begin
    SetLength(Result, 1);
    Result[0] := LValor;
    Exit;
  end;
  if LValor = '' then
    Exit;
  N := 0;
  LIni := 1;
  for K := 1 to Length(LValor) + 1 do
    if (K > Length(LValor)) or (LValor[K] = SEP_LISTA) then
    begin
      SetLength(Result, N + 1);
      Result[N] := Copy(LValor, LIni, K - LIni);
      Inc(N);
      LIni := K + 1;
    end;
end;

{ Leitor }

type
  TLeitor = class
  private
    FT: string;
    FP: Integer;
    FErro: string;
    procedure Erro(const AMensagem: string);
    procedure PularEspacos;
    function Proximo: Char;
    function LerHex4(out ACodigo: Cardinal): Boolean;
    procedure AnexarCodigo(var S: string; const ACodigo: Cardinal);
    function LerString(out AValor: string): Boolean;
    function LerLiteral(out AValor: string): Boolean;
    function LerEscalar(out AValor: string; out AEhNulo: Boolean): Boolean;
  public
    function LerObjeto(const AObj: TDFeJsonPlano): Boolean;
    property Mensagem: string read FErro;
  end;

procedure TLeitor.Erro(const AMensagem: string);
begin
  if FErro = '' then
    FErro := AMensagem + ' (posicao ' + IntToStr(FP) + ')';
end;

procedure TLeitor.PularEspacos;
begin
  while (FP <= Length(FT)) and ((FT[FP] = ' ') or (FT[FP] = #9) or (FT[FP] = #10) or (FT[FP] = #13)) do
    Inc(FP);
end;

function TLeitor.Proximo: Char;
begin
  if FP <= Length(FT) then
    Result := FT[FP]
  else
    Result := #0;
end;

function TLeitor.LerHex4(out ACodigo: Cardinal): Boolean;
var
  I: Integer;
  C: Char;
begin
  ACodigo := 0;
  Result := False;
  if FP + 3 > Length(FT) then
    Exit;
  for I := 0 to 3 do
  begin
    C := FT[FP + I];
    ACodigo := ACodigo shl 4;
    if (C >= '0') and (C <= '9') then
      Inc(ACodigo, Ord(C) - Ord('0'))
    else if (C >= 'a') and (C <= 'f') then
      Inc(ACodigo, Ord(C) - Ord('a') + 10)
    else if (C >= 'A') and (C <= 'F') then
      Inc(ACodigo, Ord(C) - Ord('A') + 10)
    else
      Exit;
  end;
  Inc(FP, 4);
  Result := True;
end;

procedure TLeitor.AnexarCodigo(var S: string; const ACodigo: Cardinal);
begin
  {$IFDEF FPC}
  // texto nativo = bytes UTF-8
  if ACodigo < $80 then
    S := S + Chr(ACodigo)
  else if ACodigo < $800 then
    S := S + Chr($C0 or (ACodigo shr 6)) + Chr($80 or (ACodigo and $3F))
  else if ACodigo < $10000 then
    S := S + Chr($E0 or (ACodigo shr 12)) + Chr($80 or ((ACodigo shr 6) and $3F)) +
      Chr($80 or (ACodigo and $3F))
  else
    S := S + Chr($F0 or (ACodigo shr 18)) + Chr($80 or ((ACodigo shr 12) and $3F)) +
      Chr($80 or ((ACodigo shr 6) and $3F)) + Chr($80 or (ACodigo and $3F));
  {$ELSE}
  if ACodigo < $10000 then
    S := S + Char(ACodigo)
  else
    S := S + Char($D800 + ((ACodigo - $10000) shr 10)) +
      Char($DC00 + ((ACodigo - $10000) and $3FF));
  {$ENDIF}
end;

function TLeitor.LerString(out AValor: string): Boolean;
var
  C: Char;
  LCodigo, LBaixo: Cardinal;
begin
  Result := False;
  AValor := '';
  if Proximo <> '"' then
  begin
    Erro('esperava "');
    Exit;
  end;
  Inc(FP);
  while FP <= Length(FT) do
  begin
    C := FT[FP];
    Inc(FP);
    if C = '"' then
    begin
      Result := True;
      Exit;
    end;
    if C = '\' then
    begin
      if FP > Length(FT) then
        Break;
      C := FT[FP];
      Inc(FP);
      case C of
        '"': AValor := AValor + '"';
        '\': AValor := AValor + '\';
        '/': AValor := AValor + '/';
        'b': AValor := AValor + #8;
        'f': AValor := AValor + #12;
        'n': AValor := AValor + #10;
        'r': AValor := AValor + #13;
        't': AValor := AValor + #9;
        'u':
          begin
            if not LerHex4(LCodigo) then
            begin
              Erro('\u invalido');
              Exit;
            end;
            // par substituto (dois escapes, alto e baixo) vira UM ponto de codigo
            if (LCodigo >= $D800) and (LCodigo <= $DBFF) and (FP + 1 <= Length(FT)) and
               (FT[FP] = '\') and (FT[FP + 1] = 'u') then
            begin
              Inc(FP, 2);
              if LerHex4(LBaixo) and (LBaixo >= $DC00) and (LBaixo <= $DFFF) then
                LCodigo := $10000 + ((LCodigo - $D800) shl 10) + (LBaixo - $DC00)
              else
              begin
                Erro('par substituto invalido');
                Exit;
              end;
            end;
            AnexarCodigo(AValor, LCodigo);
          end;
      else
        begin
          Erro('escape invalido \' + C);
          Exit;
        end;
      end;
    end
    else if Ord(C) < 32 then
    begin
      Erro('caractere de controle sem escape na string');
      Exit;
    end
    else
      AValor := AValor + C;
  end;
  Erro('string sem fechamento');
end;

function TLeitor.LerLiteral(out AValor: string): Boolean;
var
  LIni: Integer;
begin
  LIni := FP;
  while (FP <= Length(FT)) and not ((FT[FP] = ',') or (FT[FP] = '}') or (FT[FP] = ']') or
    (FT[FP] = ' ') or (FT[FP] = #9) or (FT[FP] = #10) or (FT[FP] = #13)) do
    Inc(FP);
  AValor := Copy(FT, LIni, FP - LIni);
  Result := AValor <> '';
  if not Result then
    Erro('valor esperado');
end;

{ Escalar: string, numero, true, false ou null. AEhNulo = literal null (nao a
  string "null"). }
function TLeitor.LerEscalar(out AValor: string; out AEhNulo: Boolean): Boolean;
begin
  AEhNulo := False;
  if Proximo = '"' then
    Result := LerString(AValor)
  else if Proximo = '{' then
  begin
    Erro('objeto aninhado nao suportado (o corpo admin e'' plano)');
    AValor := '';
    Result := False;
  end
  else
  begin
    Result := LerLiteral(AValor);
    if not Result then
      Exit;
    if AValor = 'null' then
      AEhNulo := True
    else if (AValor <> 'true') and (AValor <> 'false') and
            not ((AValor[1] = '-') or ((AValor[1] >= '0') and (AValor[1] <= '9'))) then
    begin
      Erro('valor invalido "' + AValor + '"');
      Result := False;
    end;
  end;
end;

function TLeitor.LerObjeto(const AObj: TDFeJsonPlano): Boolean;
var
  LChave, LValor, LJunto: string;
  LPrimeiro, LEhNulo: Boolean;
begin
  Result := False;
  PularEspacos;
  if FP > Length(FT) then
  begin
    Result := True; // texto vazio = objeto vazio
    Exit;
  end;
  if Proximo <> '{' then
  begin
    Erro('esperava {');
    Exit;
  end;
  Inc(FP);
  PularEspacos;
  if Proximo = '}' then
    Inc(FP)
  else
    repeat
      PularEspacos;
      if not LerString(LChave) then
        Exit;
      PularEspacos;
      if Proximo <> ':' then
      begin
        Erro('esperava :');
        Exit;
      end;
      Inc(FP);
      PularEspacos;
      if Proximo = '[' then
      begin
        Inc(FP);
        LJunto := '';
        LPrimeiro := True;
        PularEspacos;
        if Proximo = ']' then
          Inc(FP)
        else
          repeat
            PularEspacos;
            if Proximo = '[' then
            begin
              Erro('lista aninhada nao suportada');
              Exit;
            end;
            if not LerEscalar(LValor, LEhNulo) then
              Exit;
            if not LPrimeiro then
              LJunto := LJunto + SEP_LISTA;
            LJunto := LJunto + LValor;
            LPrimeiro := False;
            PularEspacos;
            if Proximo = ',' then
              Inc(FP)
            else if Proximo = ']' then
            begin
              Inc(FP);
              Break;
            end
            else
            begin
              Erro('esperava , ou ]');
              Exit;
            end;
          until False;
        AObj.Definir(LChave, LJunto, True);
      end
      else
      begin
        if not LerEscalar(LValor, LEhNulo) then
          Exit;
        if not LEhNulo then
          AObj.Definir(LChave, LValor, False);
      end;
      PularEspacos;
      if Proximo = ',' then
        Inc(FP)
      else if Proximo = '}' then
      begin
        Inc(FP);
        Break;
      end
      else
      begin
        Erro('esperava , ou }');
        Exit;
      end;
    until False;
  PularEspacos;
  if FP <= Length(FT) then
  begin
    Erro('texto apos o objeto');
    Exit;
  end;
  Result := True;
end;

function LerJsonPlano(const ATexto: string; out AObj: TDFeJsonPlano;
  out AErro: string): Boolean;
var
  LLeitor: TLeitor;
begin
  AErro := '';
  AObj := TDFeJsonPlano.Create;
  LLeitor := TLeitor.Create;
  try
    LLeitor.FT := ATexto;
    LLeitor.FP := 1;
    Result := LLeitor.LerObjeto(AObj);
    if not Result then
    begin
      AErro := LLeitor.Mensagem;
      if AErro = '' then
        AErro := 'JSON invalido';
      FreeAndNil(AObj);
    end;
  finally
    LLeitor.Free;
  end;
end;

end.
