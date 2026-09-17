unit DFe.CursorStore.Arquivo;

{$I dfe.inc}

{ Implementacao real de IDFeCursorStore (ver DFe.Provider) usando um arquivo
  texto plano 'namespace=nsu', uma linha por namespace. Decisao e
  justificativa completas em docs/architecture.md, "Persistencia do cursor
  de NSU" -- resumo: o volume de escrita e' irrisorio (algumas vezes por
  hora), entao SQLite e reuso do WAL do pascal-amqp-faa seriam desproporcao;
  arquivo proprio e' inspecionavel a olho nu e nao traz dependencia externa.

  Sem cache em memoria de proposito: cada chamada le/escreve o arquivo
  inteiro. Dado o volume (dezenas de linhas, poucas escritas por hora), isso
  e' irrelevante em performance e elimina toda uma classe de bug de
  cache-invalidation -- o arquivo em disco e' sempre a unica fonte de
  verdade, nunca ha estado em memoria que possa ficar dessincronizado dele.

  NAO e' thread-safe para escritas concorrentes ao mesmo arquivo -- ver
  docs/architecture.md para o porque de isso ainda nao ser um problema. }

interface

uses
  SysUtils, Classes,
  {$IFDEF DFE_WINDOWS}
  Windows,
  {$ENDIF}
  DFe.Provider;

type
  TDFeCursorStoreArquivo = class(TInterfacedObject, IDFeCursorStore)
  private
    FCaminho: string;
    function CarregarLinhas: TStringList;
    procedure SubstituirArquivoAtomicamente(const ALinhas: TStringList);
  public
    constructor Create(const ACaminho: string);

    function ObterUltimoNSU(const ANamespace: string): Int64;
    procedure GravarUltimoNSU(const ANamespace: string; const ANSU: Int64);
  end;

implementation

constructor TDFeCursorStoreArquivo.Create(const ACaminho: string);
begin
  inherited Create;
  FCaminho := ACaminho;
end;

function TDFeCursorStoreArquivo.CarregarLinhas: TStringList;
begin
  Result := TStringList.Create;
  Result.NameValueSeparator := '=';
  if FileExists(FCaminho) then
    Result.LoadFromFile(FCaminho);
end;

procedure TDFeCursorStoreArquivo.SubstituirArquivoAtomicamente(const ALinhas: TStringList);
var
  LCaminhoTemp: string;
begin
  LCaminhoTemp := FCaminho + '.tmp';
  ALinhas.SaveToFile(LCaminhoTemp);

  {$IFDEF DFE_WINDOWS}
  { RenameFile da RTL NAO sobrescreve um destino existente (falha em vez de
    substituir) -- diferente do rename() POSIX. MoveFileEx com
    MOVEFILE_REPLACE_EXISTING e' o jeito correto de fazer substituicao
    atomica no Windows. }
  if not MoveFileEx(PChar(LCaminhoTemp), PChar(FCaminho),
    MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
    RaiseLastOSError;
  {$ELSE}
  { No Unix, RenameFile e' o rename() POSIX -- ja substitui o destino de
    forma atomica quando origem e destino estao na mesma particao. }
  if not RenameFile(LCaminhoTemp, FCaminho) then
    raise Exception.CreateFmt('Falha ao substituir "%s" por "%s"', [FCaminho, LCaminhoTemp]);
  {$ENDIF}
end;

function TDFeCursorStoreArquivo.ObterUltimoNSU(const ANamespace: string): Int64;
var
  LLinhas: TStringList;
  LValor: string;
begin
  LLinhas := CarregarLinhas;
  try
    LValor := LLinhas.Values[ANamespace];
    if not TryStrToInt64(LValor, Result) then
      Result := 0;
  finally
    LLinhas.Free;
  end;
end;

procedure TDFeCursorStoreArquivo.GravarUltimoNSU(const ANamespace: string; const ANSU: Int64);
var
  LLinhas: TStringList;
begin
  LLinhas := CarregarLinhas;
  try
    LLinhas.Values[ANamespace] := IntToStr(ANSU);
    SubstituirArquivoAtomicamente(LLinhas);
  finally
    LLinhas.Free;
  end;
end;

end.
