unit DFe.Simulador.Cenario;

{$I dfe.inc}

{ Cenario DECLARATIVO do simulador, num arquivo INI (mesma filosofia de
  DFe.Config; ver docs/simulador-standalone.md, "Cenarios e extensao").
  Serve a quem so' quer "ter 3 NFes e depois um 656", em qualquer linguagem.

    [simulador]
    ; falhas que as PROXIMAS consultas vao sofrer, na ordem (uma por consulta):
    ; indisponivel-curto (108), indisponivel-longo (109), consumo-indevido,
    ; timeout, erro-http, corpo-ilegivel, doczip-corrompido,
    ; evento-rejeitado, lote-evento-rejeitado
    Falhas=consumo-indevido,timeout

    [conta:qualquer-rotulo]       ; uma secao por conta (CNPJ + UF)
    Cnpj=11222333000181
    UF=RS
    ResNFe=3                      ; resNFe sinteticas (notas 1..N)
    ProcNFe=1                     ; procNFe sinteticas (notas seguintes)
    PularNSU=2                    ; NSUs atribuidos mas nao entregues (salto)

  Falha alto: numero invalido, UF/CNPJ ausente ou nome de falha desconhecido
  levantam Exception com a secao e o valor -- um cenario com erro de digitacao
  que "roda" mentindo e' pior do que nao rodar.

  Falhas de evento (evento-rejeitado, lote-evento-rejeitado) so' cabem em
  RecepcaoEvento; se a primeira consulta for de distribuicao o simulador
  levanta (DFe.Simulador) -- enfileire-as so' quando for manifestar. }

interface

uses
  SysUtils, Classes, IniFiles,
  DFe.Simulador;

type
  TDFeCenarioResumo = record
    Contas: Integer;
    Documentos: Integer;
    Falhas: Integer;
  end;

{ Interpreta o nome de uma falha (sem diferenciar maiusculas). }
function FalhaPorNome(const ANome: string; out AFalha: TDFeFalhaSimulada): Boolean;

function NomesDeFalhaValidos: string;

{ Le o INI e aplica ao simulador. Levanta Exception se o arquivo nao existe ou
  tem valor invalido. }
function CarregarCenario(const ACaminho: string;
  const ASimulador: TDFeSimuladorSefaz): TDFeCenarioResumo;

implementation

uses
  DFe.Simulador.Fixtures;

const
  SECAO_SIMULADOR = 'simulador';
  PREFIXO_CONTA = 'conta:';

  NOMES_FALHA: array[TDFeFalhaSimulada] of string = (
    'indisponivel-curto',
    'indisponivel-longo',
    'consumo-indevido',
    'timeout',
    'erro-http',
    'corpo-ilegivel',
    'doczip-corrompido',
    'evento-rejeitado',
    'lote-evento-rejeitado');

function FalhaPorNome(const ANome: string; out AFalha: TDFeFalhaSimulada): Boolean;
var
  F: TDFeFalhaSimulada;
begin
  for F := Low(TDFeFalhaSimulada) to High(TDFeFalhaSimulada) do
    if SameText(Trim(ANome), NOMES_FALHA[F]) then
    begin
      AFalha := F;
      Result := True;
      Exit;
    end;
  Result := False;
end;

function NomesDeFalhaValidos: string;
var
  F: TDFeFalhaSimulada;
begin
  Result := '';
  for F := Low(TDFeFalhaSimulada) to High(TDFeFalhaSimulada) do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + NOMES_FALHA[F];
  end;
end;

function SoDigitos(const AValor: string): Boolean;
var
  I: Integer;
begin
  Result := AValor <> '';
  for I := 1 to Length(AValor) do
    if (AValor[I] < '0') or (AValor[I] > '9') then
    begin
      Result := False;
      Exit;
    end;
end;

function LerContagem(const AIni: TCustomIniFile; const ASecao, AChave: string): Integer;
var
  LTexto: string;
begin
  LTexto := Trim(AIni.ReadString(ASecao, AChave, '0'));
  if (not SoDigitos(LTexto)) or (Length(LTexto) > 6) then
    raise Exception.CreateFmt('Cenario: secao "%s": "%s=%s" nao e'' um inteiro >= 0', [ASecao, AChave, LTexto]);
  Result := StrToInt(LTexto);
end;

function CarregarCenario(const ACaminho: string;
  const ASimulador: TDFeSimuladorSefaz): TDFeCenarioResumo;
var
  LIni: TMemIniFile;
  LSecoes: TStringList;
  LFalhas: TStringList;
  I, N, LNota: Integer;
  LSecao, LCnpj, LUF: string;
  LFalha: TDFeFalhaSimulada;
  LChave: string;
begin
  if not FileExists(ACaminho) then
    raise Exception.CreateFmt('Cenario: arquivo "%s" nao existe', [ACaminho]);

  Result.Contas := 0;
  Result.Documentos := 0;
  Result.Falhas := 0;

  LIni := TMemIniFile.Create(ACaminho);
  LSecoes := TStringList.Create;
  LFalhas := TStringList.Create;
  try
    LIni.ReadSections(LSecoes);

    for I := 0 to LSecoes.Count - 1 do
    begin
      LSecao := LSecoes[I];
      if Copy(LowerCase(LSecao), 1, Length(PREFIXO_CONTA)) <> PREFIXO_CONTA then
        Continue;

      LCnpj := Trim(LIni.ReadString(LSecao, 'Cnpj', ''));
      LUF := UpperCase(Trim(LIni.ReadString(LSecao, 'UF', '')));
      if not SoDigitos(LCnpj) then
        raise Exception.CreateFmt('Cenario: secao "%s": "Cnpj" ausente ou nao numerico', [LSecao]);
      if Length(LUF) <> 2 then
        raise Exception.CreateFmt('Cenario: secao "%s": "UF" ausente ou invalida (2 letras)', [LSecao]);

      LNota := 0;
      N := LerContagem(LIni, LSecao, 'ResNFe');
      while N > 0 do
      begin
        Inc(LNota);
        LChave := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, LNota);
        ASimulador.PublicarDocumento(LCnpj, LUF, DFE_SIM_SCHEMA_RESNFE, XmlResNFe(LChave));
        Inc(Result.Documentos);
        Dec(N);
      end;
      N := LerContagem(LIni, LSecao, 'ProcNFe');
      while N > 0 do
      begin
        Inc(LNota);
        LChave := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, LNota);
        ASimulador.PublicarDocumento(LCnpj, LUF, DFE_SIM_SCHEMA_PROCNFE, XmlProcNFe(LChave));
        Inc(Result.Documentos);
        Dec(N);
      end;
      N := LerContagem(LIni, LSecao, 'PularNSU');
      if N > 0 then
        ASimulador.PularNSU(LCnpj, LUF, N);
      Inc(Result.Contas);
    end;

    LFalhas.CommaText := Trim(LIni.ReadString(SECAO_SIMULADOR, 'Falhas', ''));
    for I := 0 to LFalhas.Count - 1 do
    begin
      if Trim(LFalhas[I]) = '' then
        Continue;
      if not FalhaPorNome(LFalhas[I], LFalha) then
        raise Exception.CreateFmt('Cenario: falha desconhecida "%s" (validas: %s)',
          [LFalhas[I], NomesDeFalhaValidos]);
      ASimulador.EnfileirarFalha(LFalha);
      Inc(Result.Falhas);
    end;
  finally
    LFalhas.Free;
    LSecoes.Free;
    LIni.Free;
  end;
end;

end.
