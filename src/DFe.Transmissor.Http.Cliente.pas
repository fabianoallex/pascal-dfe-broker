unit DFe.Transmissor.Http.Cliente;

{$I dfe.inc}

{ IDFeHttpPost de verdade: um POST HTTP (sem TLS -- o simulador escuta em HTTP
  puro, ver docs/simulador-standalone.md) com o cliente da RTL de cada
  compilador: fphttpclient no FPC, System.Net.HttpClient no Delphi. Fica
  FORA do pacote Lazarus (como DFe.Client.ACBrNFe): puxa bibliotecas de rede
  que so' quem usa o simulador precisa.

  Texto: IDFeHttpPost fala texto NATIVO; a rede leva UTF-8.
  - FPC: String ja' sao bytes UTF-8, vao e voltam como estao.
  - Delphi: UnicodeString -> UTF-8 na ida; UTF-8 -> UnicodeString na volta.

  Nao levanta excecao por falha de rede: devolve TDFeHttpResposta.Erro.
  Qualquer STATUS HTTP (inclusive 500) e' resposta, nao erro. Sem redirecionamento. }

interface

uses
  SysUtils,
  DFe.Transmissor.Http;

const
  DFE_HTTP_TIMEOUT_PADRAO_MS = 60000;

type
  TDFeHttpPostPadrao = class(TInterfacedObject, IDFeHttpPost)
  private
    FTimeoutMs: Integer;
  public
    constructor Create(const ATimeoutMs: Integer = DFE_HTTP_TIMEOUT_PADRAO_MS);
    function Postar(const AURL, AMimeType, ASoapAction,
      ACorpo: string): TDFeHttpResposta;
  end;

implementation

uses
  {$IFDEF FPC}
  Classes, fphttpclient;
  {$ELSE}
  System.Classes, System.Net.HttpClient, System.Net.URLClient;
  {$ENDIF}

constructor TDFeHttpPostPadrao.Create(const ATimeoutMs: Integer);
begin
  inherited Create;
  FTimeoutMs := ATimeoutMs;
end;

{$IFDEF FPC}

function TDFeHttpPostPadrao.Postar(const AURL, AMimeType, ASoapAction,
  ACorpo: string): TDFeHttpResposta;
var
  LClient: TFPHTTPClient;
  LEnvio, LResposta: TStringStream;
begin
  Result.Status := 0;
  Result.Corpo := '';
  Result.Erro := '';
  LClient := TFPHTTPClient.Create(nil);
  LEnvio := TStringStream.Create(ACorpo);
  LResposta := TStringStream.Create('');
  try
    try
      LClient.ConnectTimeout := FTimeoutMs;
      LClient.IOTimeout := FTimeoutMs;
      LClient.AllowRedirect := False;
      LClient.AddHeader('Content-Type', AMimeType);
      LClient.AddHeader('SOAPAction', ASoapAction);
      LClient.RequestBody := LEnvio;
      // Lista de codigos aceitos VAZIA: qualquer status vale (sem excecao por 500).
      LClient.HTTPMethod('POST', AURL, LResposta, []);
      Result.Status := LClient.ResponseStatusCode;
      Result.Corpo := LResposta.DataString;
    except
      on E: Exception do
        Result.Erro := E.ClassName + ': ' + E.Message;
    end;
  finally
    LResposta.Free;
    LEnvio.Free;
    LClient.Free;
  end;
end;

{$ELSE}

function TDFeHttpPostPadrao.Postar(const AURL, AMimeType, ASoapAction,
  ACorpo: string): TDFeHttpResposta;
var
  LClient: THTTPClient;
  LEnvio: TStringStream;
  LResp: IHTTPResponse;
begin
  Result.Status := 0;
  Result.Corpo := '';
  Result.Erro := '';
  LClient := THTTPClient.Create;
  LEnvio := TStringStream.Create(ACorpo, TEncoding.UTF8);
  try
    try
      LClient.ConnectionTimeout := FTimeoutMs;
      LClient.ResponseTimeout := FTimeoutMs;
      LClient.HandleRedirects := False;
      LClient.ContentType := AMimeType;
      LClient.CustomHeaders['SOAPAction'] := ASoapAction;
      LResp := LClient.Post(AURL, LEnvio);
      Result.Status := LResp.StatusCode;
      Result.Corpo := LResp.ContentAsString(TEncoding.UTF8);
    except
      on E: Exception do
        Result.Erro := E.ClassName + ': ' + E.Message;
    end;
  finally
    LEnvio.Free;
    LClient.Free;
  end;
end;

{$ENDIF}

end.
