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
  tem valor invalido. O cenario e' VALIDADO POR INTEIRO antes de aplicar: um erro
  nao deixa o simulador com so' metade do cenario. E' ACUMULATIVO: aplica por
  cima do estado atual (use TDFeSimuladorSefaz.Zerar antes para recomecar). }
function CarregarCenario(const ACaminho: string;
  const ASimulador: TDFeSimuladorSefaz): TDFeCenarioResumo;

{ O mesmo, com o conteudo do INI em texto (usado por POST /admin/cenario). }
function CarregarCenarioDeTexto(const ATexto: string;
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

type
  TPlanoConta = record
    Cnpj: string;
    UF: string;
    ResNFe: Integer;
    ProcNFe: Integer;
    Pular: Integer;
  end;

{ Fase 1: interpreta e VALIDA tudo; levanta antes de qualquer efeito. }
procedure Interpretar(const AIni: TCustomIniFile; var AContas: array of TPlanoConta;
  out AQtdContas: Integer; var AFalhas: array of TDFeFalhaSimulada; out AQtdFalhas: Integer);
var
  LSecoes, LFalhas: TStringList;
  I: Integer;
  LSecao: string;
  LFalha: TDFeFalhaSimulada;
begin
  AQtdContas := 0;
  AQtdFalhas := 0;
  LSecoes := TStringList.Create;
  LFalhas := TStringList.Create;
  try
    AIni.ReadSections(LSecoes);
    for I := 0 to LSecoes.Count - 1 do
    begin
      LSecao := LSecoes[I];
      if Copy(LowerCase(LSecao), 1, Length(PREFIXO_CONTA)) <> PREFIXO_CONTA then
        Continue;
      if AQtdContas > High(AContas) then
        raise Exception.Create('Cenario: contas demais (o maximo e'' ' + IntToStr(Length(AContas)) + ')');

      AContas[AQtdContas].Cnpj := Trim(AIni.ReadString(LSecao, 'Cnpj', ''));
      AContas[AQtdContas].UF := UpperCase(Trim(AIni.ReadString(LSecao, 'UF', '')));
      if not SoDigitos(AContas[AQtdContas].Cnpj) then
        raise Exception.CreateFmt('Cenario: secao "%s": "Cnpj" ausente ou nao numerico', [LSecao]);
      if Length(AContas[AQtdContas].UF) <> 2 then
        raise Exception.CreateFmt('Cenario: secao "%s": "UF" ausente ou invalida (2 letras)', [LSecao]);
      AContas[AQtdContas].ResNFe := LerContagem(AIni, LSecao, 'ResNFe');
      AContas[AQtdContas].ProcNFe := LerContagem(AIni, LSecao, 'ProcNFe');
      AContas[AQtdContas].Pular := LerContagem(AIni, LSecao, 'PularNSU');
      Inc(AQtdContas);
    end;

    LFalhas.CommaText := Trim(AIni.ReadString(SECAO_SIMULADOR, 'Falhas', ''));
    for I := 0 to LFalhas.Count - 1 do
    begin
      if Trim(LFalhas[I]) = '' then
        Continue;
      if not FalhaPorNome(LFalhas[I], LFalha) then
        raise Exception.CreateFmt('Cenario: falha desconhecida "%s" (validas: %s)',
          [LFalhas[I], NomesDeFalhaValidos]);
      if AQtdFalhas > High(AFalhas) then
        raise Exception.Create('Cenario: falhas demais (o maximo e'' ' + IntToStr(Length(AFalhas)) + ')');
      AFalhas[AQtdFalhas] := LFalha;
      Inc(AQtdFalhas);
    end;
  finally
    LFalhas.Free;
    LSecoes.Free;
  end;
end;

{ Fase 2: aplica o plano ja' validado. }
function Aplicar(const AContas: array of TPlanoConta; const AQtdContas: Integer;
  const AFalhas: array of TDFeFalhaSimulada; const AQtdFalhas: Integer;
  const ASimulador: TDFeSimuladorSefaz): TDFeCenarioResumo;
var
  I, N, LNota: Integer;
  LChave: string;
begin
  Result.Contas := 0;
  Result.Documentos := 0;
  Result.Falhas := 0;
  for I := 0 to AQtdContas - 1 do
  begin
    LNota := 0;
    for N := 1 to AContas[I].ResNFe do
    begin
      Inc(LNota);
      LChave := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, LNota);
      ASimulador.PublicarDocumento(AContas[I].Cnpj, AContas[I].UF, DFE_SIM_SCHEMA_RESNFE, XmlResNFe(LChave));
      Inc(Result.Documentos);
    end;
    for N := 1 to AContas[I].ProcNFe do
    begin
      Inc(LNota);
      LChave := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, LNota);
      ASimulador.PublicarDocumento(AContas[I].Cnpj, AContas[I].UF, DFE_SIM_SCHEMA_PROCNFE, XmlProcNFe(LChave));
      Inc(Result.Documentos);
    end;
    if AContas[I].Pular > 0 then
      ASimulador.PularNSU(AContas[I].Cnpj, AContas[I].UF, AContas[I].Pular);
    Inc(Result.Contas);
  end;
  for I := 0 to AQtdFalhas - 1 do
  begin
    ASimulador.EnfileirarFalha(AFalhas[I]);
    Inc(Result.Falhas);
  end;
end;

const
  MAX_CONTAS = 200;
  MAX_FALHAS = 1000;

function AplicarIni(const AIni: TCustomIniFile;
  const ASimulador: TDFeSimuladorSefaz): TDFeCenarioResumo;
var
  LContas: array of TPlanoConta;
  LFalhas: array of TDFeFalhaSimulada;
  LQtdContas, LQtdFalhas: Integer;
begin
  SetLength(LContas, MAX_CONTAS);
  SetLength(LFalhas, MAX_FALHAS);
  Interpretar(AIni, LContas, LQtdContas, LFalhas, LQtdFalhas);
  Result := Aplicar(LContas, LQtdContas, LFalhas, LQtdFalhas, ASimulador);
end;

function CarregarCenario(const ACaminho: string;
  const ASimulador: TDFeSimuladorSefaz): TDFeCenarioResumo;
var
  LIni: TMemIniFile;
begin
  if not FileExists(ACaminho) then
    raise Exception.CreateFmt('Cenario: arquivo "%s" nao existe', [ACaminho]);
  LIni := TMemIniFile.Create(ACaminho);
  try
    Result := AplicarIni(LIni, ASimulador);
  finally
    LIni.Free;
  end;
end;

function CarregarCenarioDeTexto(const ATexto: string;
  const ASimulador: TDFeSimuladorSefaz): TDFeCenarioResumo;
var
  LIni: TMemIniFile;
  LLinhas: TStringList;
begin
  LLinhas := TStringList.Create;
  LIni := TMemIniFile.Create('');
  try
    LLinhas.Text := ATexto;
    LIni.SetStrings(LLinhas);
    Result := AplicarIni(LIni, ASimulador);
  finally
    LIni.Free;
    LLinhas.Free;
  end;
end;

end.
