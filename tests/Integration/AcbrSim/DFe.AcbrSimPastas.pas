unit DFe.AcbrSimPastas;

{ Pastas temporarias para os testes de ambiente (DFe.Ambiente): montar uma pasta
  de XSDs "incompleta" de proposito, sem tocar nos arquivos de verdade.

  UNICO fonte, compartilhado pelo projeto FPC e pelo Delphi (nao ha atributo
  de teste aqui, entao nao precisa de espelho). As pastas ficam ao lado do
  executavel (tests\Integration\AcbrSim\tmp-amb-*, ignoradas pelo git) e sao
  apagadas no destrutor. }

{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}

interface

uses
  Classes, SysUtils;

type
  TPastasTemporarias = class
  private
    FPastas: array of string;
  public
    destructor Destroy; override;
    { Cria uma pasta nova (vazia) e devolve o caminho COM barra final. }
    function Nova: string;
    { Nome inexistente dentro da area temporaria (a pasta NAO e' criada). }
    function CaminhoInexistente: string;
  end;

{ Cria um arquivo vazio (serve de placeholder de .xsd para a distribuicao). }
procedure CriarArquivoVazio(const ACaminho: string);
procedure CopiarArquivo(const AOrigem, ADestino: string);
procedure RemoverPasta(const APasta: string);

implementation

var
  ContadorPastas: Integer = 0;

function BaseTemporaria: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

procedure CriarArquivoVazio(const ACaminho: string);
var
  LArquivo: TFileStream;
begin
  LArquivo := TFileStream.Create(ACaminho, fmCreate);
  LArquivo.Free;
end;

procedure CopiarArquivo(const AOrigem, ADestino: string);
var
  LOrigem, LDestino: TFileStream;
begin
  LOrigem := TFileStream.Create(AOrigem, fmOpenRead or fmShareDenyNone);
  try
    LDestino := TFileStream.Create(ADestino, fmCreate);
    try
      LDestino.CopyFrom(LOrigem, 0);
    finally
      LDestino.Free;
    end;
  finally
    LOrigem.Free;
  end;
end;

procedure RemoverPasta(const APasta: string);
var
  LBusca: TSearchRec;
  LPasta: string;
begin
  LPasta := IncludeTrailingPathDelimiter(APasta);
  if not DirectoryExists(LPasta) then
    Exit;
  if FindFirst(LPasta + '*', faAnyFile, LBusca) = 0 then
  begin
    repeat
      if (LBusca.Name <> '.') and (LBusca.Name <> '..') then
        DeleteFile(LPasta + LBusca.Name);
    until FindNext(LBusca) <> 0;
    FindClose(LBusca);
  end;
  RemoveDir(APasta);
end;

{ TPastasTemporarias }

function TPastasTemporarias.CaminhoInexistente: string;
begin
  Inc(ContadorPastas);
  Result := BaseTemporaria + 'tmp-amb-' + IntToStr(ContadorPastas) + '-' +
    IntToStr(Random(1000000)) + PathDelim;
end;

function TPastasTemporarias.Nova: string;
begin
  Result := CaminhoInexistente;
  ForceDirectories(Result);
  SetLength(FPastas, Length(FPastas) + 1);
  FPastas[High(FPastas)] := Result;
end;

destructor TPastasTemporarias.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(FPastas) do
    RemoverPasta(FPastas[I]);
  inherited Destroy;
end;

end.
