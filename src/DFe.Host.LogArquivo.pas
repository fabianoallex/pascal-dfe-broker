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
  Retencao (apagar logs antigos) nao e' feita aqui. }

interface

uses
  SysUtils, Classes, SyncObjs;

type
  TDFeLogArquivo = class
  private
    FDiretorio: string;
    FPrefixo: string;
    FLock: TCriticalSection;
  protected
    { Injetavel para teste: o instante (em hora de Brasilia) que vai na linha e
      no nome do arquivo. }
    function Agora: TDateTime; virtual;
  public
    constructor Create(const ADiretorio: string; const APrefixo: string = 'dfe');
    destructor Destroy; override;

    procedure Registrar(const ANivel, AMensagem: string);

    { Caminho do arquivo do dia corrente. }
    function CaminhoDoDia: string;
  end;

implementation

uses
  DFe.Fuso;

constructor TDFeLogArquivo.Create(const ADiretorio, APrefixo: string);
begin
  inherited Create;
  FDiretorio := IncludeTrailingPathDelimiter(ADiretorio);
  FPrefixo := APrefixo;
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
    except
      // logar nunca derruba quem esta sendo logado
    end;
  finally
    FLock.Leave;
  end;
end;

end.
