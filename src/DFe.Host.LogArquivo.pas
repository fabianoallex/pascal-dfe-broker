unit DFe.Host.LogArquivo;

{$I dfe.inc}

{ Log em arquivo para hosts sem console (Servico Windows, decisao 9): um arquivo
  por DIA, 'dfe-aaaammdd.log' na pasta dada, UTF-8, uma linha por registro:

    2026-09-19 07:49:09-03:00 [INFO] mensagem

  Mesmo formato do log do host console (hora de Brasilia com sufixo explicito,
  ver DFe.Fuso) e mesma assinatura de Registrar (TDFeLogProc), entao trocar um
  pelo outro no TDFeAplicacao e' so' passar outro metodo.

  Abre e fecha o arquivo a CADA linha: o volume e' baixo (o orquestrador age de
  hora em hora) e assim o arquivo pode ser lido, copiado ou apagado enquanto o
  servico roda, e a virada do dia nao exige nenhuma logica de rotacao.

  Registrar NUNCA levanta excecao: falhar ao escrever o log (disco cheio, pasta
  sem permissao) nao pode derrubar quem esta sendo logado. Chamado de threads
  diferentes (tick do host e pool do cliente AMQP); serializado por lock.
  RETENCAO: com RetencaoDias > 0, os arquivos '<prefixo>-aaaammdd.log' mais antigos
  que isso sao APAGADOS, uma vez por dia (na primeira escrita do dia). Conta-se pela
  DATA NO NOME do arquivo (nao pela data de modificacao: deterministico e
  testavel), e '3' significa "hoje e os 2 dias anteriores". So' apaga arquivos que
  casam exatamente com o padrao do log -- nunca outro arquivo da pasta. 0 (padrao)
  = nao apaga nada. }

interface

uses
  SysUtils, Classes, SyncObjs;

type
  TDFeLogArquivo = class
  private
    FDiretorio: string;
    FPrefixo: string;
    FRetencaoDias: Integer;
    FUltimaLimpeza: Integer; // Trunc(data) da ultima limpeza; 0 = nunca
    FLock: TCriticalSection;
    procedure LimparAntigos(const AHoje: TDateTime);
  protected
    { Injetavel para teste: o instante (em hora de Brasilia) que vai na linha e
      no nome do arquivo. }
    function Agora: TDateTime; virtual;
  public
    constructor Create(const ADiretorio: string; const APrefixo: string = 'dfe';
      const ARetencaoDias: Integer = 0);
    destructor Destroy; override;

    procedure Registrar(const ANivel, AMensagem: string);

    { Caminho do arquivo do dia corrente. }
    function CaminhoDoDia: string;

    { Quantos dias de log manter (0 = todos). Ver o comentario de topo. }
    property RetencaoDias: Integer read FRetencaoDias write FRetencaoDias;
  end;

implementation

uses
  DFe.Fuso;

constructor TDFeLogArquivo.Create(const ADiretorio, APrefixo: string;
  const ARetencaoDias: Integer);
begin
  inherited Create;
  FDiretorio := IncludeTrailingPathDelimiter(ADiretorio);
  FPrefixo := APrefixo;
  FRetencaoDias := ARetencaoDias;
  FLock := TCriticalSection.Create;
end;

destructor TDFeLogArquivo.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

function TDFeLogArquivo.Agora: TDateTime;
begin
  Result := AgoraDeBrasilia;
end;

function TDFeLogArquivo.CaminhoDoDia: string;
begin
  Result := FDiretorio + FPrefixo + '-' + FormatDateTime('yyyymmdd', Agora) + '.log';
end;

procedure TDFeLogArquivo.LimparAntigos(const AHoje: TDateTime);
var
  LBusca: TSearchRec;
  LDigitos: string;
  LData: TDateTime;
  LAno, LMes, LDia, I: Integer;
  LSoDigitos: Boolean;
begin
  if (FRetencaoDias <= 0) or (FUltimaLimpeza = Trunc(AHoje)) then
    Exit;
  FUltimaLimpeza := Trunc(AHoje);

  // '<prefixo>-' + 8 digitos + '.log': o padrao do coringa e' so' um filtro grosso;
  // o nome e' conferido abaixo, digito a digito, antes de apagar qualquer coisa.
  if FindFirst(FDiretorio + FPrefixo + '-????????.log', faAnyFile, LBusca) = 0 then
  try
    repeat
      if (LBusca.Attr and faDirectory) <> 0 then
        Continue;
      LDigitos := Copy(LBusca.Name, Length(FPrefixo) + 2, 8);
      LSoDigitos := Length(LDigitos) = 8;
      for I := 1 to Length(LDigitos) do
        if not ((LDigitos[I] >= '0') and (LDigitos[I] <= '9')) then
          LSoDigitos := False;
      if not LSoDigitos then
        Continue;
      LAno := StrToInt(Copy(LDigitos, 1, 4));
      LMes := StrToInt(Copy(LDigitos, 5, 2));
      LDia := StrToInt(Copy(LDigitos, 7, 2));
      if not TryEncodeDate(LAno, LMes, LDia, LData) then
        Continue;
      // "N dias" = hoje e os N-1 anteriores; apaga quem tem N dias ou mais
      if Trunc(AHoje) - Trunc(LData) >= FRetencaoDias then
        DeleteFile(FDiretorio + LBusca.Name);
    until FindNext(LBusca) <> 0;
  finally
    FindClose(LBusca);
  end;
end;

procedure TDFeLogArquivo.Registrar(const ANivel, AMensagem: string);
var
  LAgora: TDateTime;
  LLinha, LCaminho: string;
  LArquivo: TFileStream;
  {$IFNDEF FPC}
  LBytes: TBytes;
  {$ENDIF}
begin
  FLock.Enter;
  try
    try
      LAgora := Agora;
      LLinha := FormatDateTime('yyyy-mm-dd hh:nn:ss', LAgora) + DFE_FUSO_BRASILIA +
        ' [' + ANivel + '] ' + AMensagem + sLineBreak;
      LCaminho := FDiretorio + FPrefixo + '-' + FormatDateTime('yyyymmdd', LAgora) + '.log';

      ForceDirectories(FDiretorio);
      if FileExists(LCaminho) then
      begin
        LArquivo := TFileStream.Create(LCaminho, fmOpenReadWrite or fmShareDenyNone);
        LArquivo.Seek(0, soEnd);
      end
      else
        LArquivo := TFileStream.Create(LCaminho, fmCreate or fmShareDenyNone);
      try
        {$IFDEF FPC}
        // FPC: a String ja' e' UTF-8 (ver "Encoding do XML", docs/architecture.md)
        if LLinha <> '' then
          LArquivo.WriteBuffer(LLinha[1], Length(LLinha));
        {$ELSE}
        LBytes := TEncoding.UTF8.GetBytes(LLinha);
        if Length(LBytes) > 0 then
          LArquivo.WriteBuffer(LBytes[0], Length(LBytes));
        {$ENDIF}
      finally
        LArquivo.Free;
      end;
      LimparAntigos(LAgora);
    except
      // logar nunca derruba quem esta sendo logado
    end;
  finally
    FLock.Leave;
  end;
end;

end.
