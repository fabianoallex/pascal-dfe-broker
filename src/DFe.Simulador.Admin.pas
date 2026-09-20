unit DFe.Simulador.Admin;

{$I dfe.inc}

(* API ADMIN do simulador (docs/simulador-standalone.md, "Contrato HTTP"): o que
  um teste (em qualquer linguagem) usa para PREPARAR e CONSULTAR o simulador em
  execucao -- publicar documento, enfileirar falha, avancar o relogio, ver o
  estado. Pura: (metodo, caminho, corpo) -> (status, content-type, corpo), sem
  HTTP.

  Corpos de entrada: JSON PLANO (DFe.Simulador.Json). Respostas: JSON, exceto
  /admin/violacoes e /admin/ultimo-envelope (texto), para serem legiveis num
  curl.

  Rotas:
    GET    /admin/estado
    GET    /admin/relogio
    POST   /admin/relogio/avancar   {"segundos":N} (+ "minutos","horas","dias")
    POST   /admin/relogio/zerar
    GET    /admin/violacoes         texto; "(nenhuma)" se nao houver
    DELETE /admin/violacoes
    GET    /admin/ultimo-envelope   o ultimo envelope recebido (XML)
    GET    /admin/modo              {"estrito":false}
    POST   /admin/modo              {"estrito":true}
    POST   /admin/documentos        {"cnpj","uf","tipo","quantidade","numero",...}
                                    ou {"cnpj","uf","schema","xml"} (literal)
    POST   /admin/pular-nsu         {"cnpj","uf","quantidade"}
    POST   /admin/falhas            {"falha":"timeout","quantidade":2}
                                    ou {"falhas":["timeout","consumo-indevido"]}
    POST   /admin/cenario           corpo = o INI do cenario (DFe.Simulador.Cenario)
    POST   /admin/zerar             estado, falhas, violacoes e relogio

  NAO faz trava: quem chama (TDFeSimuladorServidor) ja' serializa o acesso ao
  nucleo. NAO ha autenticacao (o simulador escuta em 127.0.0.1 por padrao). *)

interface

uses
  SysUtils,
  DFe.Simulador,
  DFe.Simulador.Soap,
  DFe.Simulador.Relogio;

const
  CAMINHO_ADMIN = '/admin/';
  DFE_SIM_CONTENT_TYPE_JSON = 'application/json; charset=utf-8';

type
  TDFeSimHttpResposta = record
    Status: Integer;
    ContentType: string;
    Corpo: string; // texto NATIVO (a casca codifica em UTF-8)
  end;

  TDFeSimuladorAdmin = class
  private
    FSimulador: TDFeSimuladorSefaz;
    FTransmissor: TDFeSimuladorTransmissor;
    FRelogio: TDFeRelogioVirtual;
    function Resp(const AStatus: Integer; const AContentType, ACorpo: string): TDFeSimHttpResposta;
    function Json(const AStatus: Integer; const ACorpo: string): TDFeSimHttpResposta;
    function Erro(const AStatus: Integer; const AMensagem: string): TDFeSimHttpResposta;
    function MetodoNaoPermitido: TDFeSimHttpResposta;
    function Estado: TDFeSimHttpResposta;
    function JsonRelogio: string;
    function GetRelogio: TDFeSimHttpResposta;
    function PostRelogioAvancar(const ACorpo: string): TDFeSimHttpResposta;
    function PostRelogioZerar: TDFeSimHttpResposta;
    function GetViolacoes: TDFeSimHttpResposta;
    function DeleteViolacoes: TDFeSimHttpResposta;
    function GetUltimoEnvelope: TDFeSimHttpResposta;
    function GetModo: TDFeSimHttpResposta;
    function PostModo(const ACorpo: string): TDFeSimHttpResposta;
    function PostDocumentos(const ACorpo: string): TDFeSimHttpResposta;
    function PostPularNsu(const ACorpo: string): TDFeSimHttpResposta;
    function PostFalhas(const ACorpo: string): TDFeSimHttpResposta;
    function PostCenario(const ACorpo: string): TDFeSimHttpResposta;
    function PostZerar: TDFeSimHttpResposta;
  public
    { Nao possui nenhum dos tres. ARelogio pode ser nil (as rotas de relogio
      respondem 501). }
    constructor Create(const ASimulador: TDFeSimuladorSefaz;
      const ATransmissor: TDFeSimuladorTransmissor; const ARelogio: TDFeRelogioVirtual);

    function Tratar(const AMetodo, ACaminho, ACorpo: string): TDFeSimHttpResposta;
  end;

implementation

uses
  DFe.XmlTexto,
  DFe.Simulador.Json,
  DFe.Simulador.Cenario,
  DFe.Simulador.Fixtures;

const
  MAX_QUANTIDADE = 1000;
  FORMATO_DATA_HORA = 'yyyy"-"mm"-"dd"T"hh":"nn":"ss';

function SoDigitos(const AValor: string; const ATamanhos: array of Integer): Boolean;
var
  I: Integer;
  LTamanhoOk: Boolean;
begin
  Result := AValor <> '';
  for I := 1 to Length(AValor) do
    if (AValor[I] < '0') or (AValor[I] > '9') then
    begin
      Result := False;
      Exit;
    end;
  LTamanhoOk := False;
  for I := 0 to High(ATamanhos) do
    if Length(AValor) = ATamanhos[I] then
      LTamanhoOk := True;
  Result := Result and LTamanhoOk;
end;

function XmlEscape(const AValor: string): string;
begin
  Result := StringReplace(AValor, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

function DataHoraJson(const AValor: TDateTime): string;
begin
  Result := JsonTexto(FormatDateTime(FORMATO_DATA_HORA, AValor));
end;

constructor TDFeSimuladorAdmin.Create(const ASimulador: TDFeSimuladorSefaz;
  const ATransmissor: TDFeSimuladorTransmissor; const ARelogio: TDFeRelogioVirtual);
begin
  inherited Create;
  FSimulador := ASimulador;
  FTransmissor := ATransmissor;
  FRelogio := ARelogio;
end;

function TDFeSimuladorAdmin.Resp(const AStatus: Integer; const AContentType,
  ACorpo: string): TDFeSimHttpResposta;
begin
  Result.Status := AStatus;
  Result.ContentType := AContentType;
  Result.Corpo := ACorpo;
end;

function TDFeSimuladorAdmin.Json(const AStatus: Integer; const ACorpo: string): TDFeSimHttpResposta;
begin
  Result := Resp(AStatus, DFE_SIM_CONTENT_TYPE_JSON, ACorpo);
end;

function TDFeSimuladorAdmin.Erro(const AStatus: Integer; const AMensagem: string): TDFeSimHttpResposta;
begin
  Result := Json(AStatus, '{"erro":' + JsonTexto(AMensagem) + '}');
end;

function TDFeSimuladorAdmin.MetodoNaoPermitido: TDFeSimHttpResposta;
begin
  Result := Erro(405, 'metodo nao permitido para esta rota');
end;

function TDFeSimuladorAdmin.Tratar(const AMetodo, ACaminho, ACorpo: string): TDFeSimHttpResposta;
var
  LCaminho: string;
  I: Integer;
begin
  LCaminho := LowerCase(ACaminho);
  I := Pos('?', LCaminho);
  if I > 0 then
    LCaminho := Copy(LCaminho, 1, I - 1);
  while (Length(LCaminho) > 1) and (LCaminho[Length(LCaminho)] = '/') do
    Delete(LCaminho, Length(LCaminho), 1);

  try
    if LCaminho = '/admin/estado' then
    begin
      if SameText(AMetodo, 'GET') then Result := Estado else Result := MetodoNaoPermitido;
    end
    else if LCaminho = '/admin/relogio' then
    begin
      if SameText(AMetodo, 'GET') then Result := GetRelogio else Result := MetodoNaoPermitido;
    end
    else if LCaminho = '/admin/relogio/avancar' then
    begin
      if SameText(AMetodo, 'POST') then Result := PostRelogioAvancar(ACorpo) else Result := MetodoNaoPermitido;
    end
    else if LCaminho = '/admin/relogio/zerar' then
    begin
      if SameText(AMetodo, 'POST') then Result := PostRelogioZerar else Result := MetodoNaoPermitido;
    end
    else if LCaminho = '/admin/violacoes' then
    begin
      if SameText(AMetodo, 'GET') then Result := GetViolacoes
      else if SameText(AMetodo, 'DELETE') then Result := DeleteViolacoes
      else Result := MetodoNaoPermitido;
    end
    else if LCaminho = '/admin/ultimo-envelope' then
    begin
      if SameText(AMetodo, 'GET') then Result := GetUltimoEnvelope else Result := MetodoNaoPermitido;
    end
    else if LCaminho = '/admin/modo' then
    begin
      if SameText(AMetodo, 'GET') then Result := GetModo
      else if SameText(AMetodo, 'POST') then Result := PostModo(ACorpo)
      else Result := MetodoNaoPermitido;
    end
    else if LCaminho = '/admin/documentos' then
    begin
      if SameText(AMetodo, 'POST') then Result := PostDocumentos(ACorpo) else Result := MetodoNaoPermitido;
    end
    else if LCaminho = '/admin/pular-nsu' then
    begin
      if SameText(AMetodo, 'POST') then Result := PostPularNsu(ACorpo) else Result := MetodoNaoPermitido;
    end
    else if LCaminho = '/admin/falhas' then
    begin
      if SameText(AMetodo, 'POST') then Result := PostFalhas(ACorpo) else Result := MetodoNaoPermitido;
    end
    else if LCaminho = '/admin/cenario' then
    begin
      if SameText(AMetodo, 'POST') then Result := PostCenario(ACorpo) else Result := MetodoNaoPermitido;
    end
    else if LCaminho = '/admin/zerar' then
    begin
      if SameText(AMetodo, 'POST') then Result := PostZerar else Result := MetodoNaoPermitido;
    end
    else
      Result := Erro(404, 'rota admin desconhecida: ' + ACaminho);
  except
    on E: Exception do
      Result := Erro(500, 'simulador: ' + E.Message);
  end;
end;

{ ---- estado e relogio ---- }

function TDFeSimuladorAdmin.JsonRelogio: string;
begin
  Result := '"agora":' + DataHoraJson(FSimulador.AgoraSimulado);
  if Assigned(FRelogio) then
    Result := Result + ',"deslocamentoSegundos":' + IntToStr(FRelogio.DeslocamentoSegundos)
  else
    Result := Result + ',"deslocamentoSegundos":null';
end;

function TDFeSimuladorAdmin.Estado: TDFeSimHttpResposta;
var
  LContas: TDFeSimContaResumoArray;
  I: Integer;
  LLista, LBloqueio: string;
begin
  LContas := FSimulador.Contas;
  LLista := '';
  for I := 0 to High(LContas) do
  begin
    if LContas[I].BloqueadoAte > 0 then
      LBloqueio := DataHoraJson(LContas[I].BloqueadoAte)
    else
      LBloqueio := 'null';
    if LLista <> '' then
      LLista := LLista + ',';
    LLista := LLista + '{"cnpj":' + JsonTexto(LContas[I].Cnpj) + ',"uf":' + JsonTexto(LContas[I].UF) +
      ',"nsuAtual":' + IntToStr(LContas[I].NsuAtual) + ',"documentos":' + IntToStr(LContas[I].Documentos) +
      ',"bloqueadoAte":' + LBloqueio + '}';
  end;
  Result := Json(200, '{"requisicoes":' + IntToStr(FTransmissor.Requisicoes) +
    ',"consultas":' + IntToStr(FSimulador.TotalConsultas) +
    ',"eventosRegistrados":' + IntToStr(FSimulador.EventosRegistrados) +
    ',"falhasPendentes":' + IntToStr(FSimulador.FalhasPendentes) +
    ',"violacoes":' + IntToStr(FTransmissor.QuantidadeViolacoes) +
    ',"estrito":' + LowerCase(BoolToStr(FTransmissor.Estrito, True)) +
    ',' + JsonRelogio +
    ',"contas":[' + LLista + ']}');
end;

function TDFeSimuladorAdmin.GetRelogio: TDFeSimHttpResposta;
begin
  Result := Json(200, '{' + JsonRelogio + '}');
end;

function TDFeSimuladorAdmin.PostRelogioAvancar(const ACorpo: string): TDFeSimHttpResposta;
var
  LJson: TDFeJsonPlano;
  LErro: string;
  LTotal: Int64;
begin
  if not Assigned(FRelogio) then
  begin
    Result := Erro(501, 'relogio virtual nao configurado neste simulador');
    Exit;
  end;
  if not LerJsonPlano(ACorpo, LJson, LErro) then
  begin
    Result := Erro(400, 'JSON invalido: ' + LErro);
    Exit;
  end;
  try
    if (LJson.Tem('segundos') and not LJson.EInteiro('segundos')) or
       (LJson.Tem('minutos') and not LJson.EInteiro('minutos')) or
       (LJson.Tem('horas') and not LJson.EInteiro('horas')) or
       (LJson.Tem('dias') and not LJson.EInteiro('dias')) then
    begin
      Result := Erro(400, 'segundos/minutos/horas/dias devem ser inteiros');
      Exit;
    end;
    LTotal := LJson.Inteiro('segundos', 0) + LJson.Inteiro('minutos', 0) * 60 +
      LJson.Inteiro('horas', 0) * 3600 + LJson.Inteiro('dias', 0) * 86400;
    if LTotal <= 0 then
    begin
      Result := Erro(400, 'informe um avanco positivo (segundos, minutos, horas ou dias)');
      Exit;
    end;
    FRelogio.Avancar(LTotal);
    Result := GetRelogio;
  finally
    LJson.Free;
  end;
end;

function TDFeSimuladorAdmin.PostRelogioZerar: TDFeSimHttpResposta;
begin
  if not Assigned(FRelogio) then
  begin
    Result := Erro(501, 'relogio virtual nao configurado neste simulador');
    Exit;
  end;
  FRelogio.Zerar;
  Result := GetRelogio;
end;

{ ---- violacoes, envelope, modo ---- }

function TDFeSimuladorAdmin.GetViolacoes: TDFeSimHttpResposta;
var
  LTexto: string;
begin
  LTexto := FTransmissor.TodasViolacoes;
  if LTexto = '' then
    LTexto := '(nenhuma)';
  Result := Resp(200, 'text/plain; charset=utf-8', LTexto);
end;

function TDFeSimuladorAdmin.DeleteViolacoes: TDFeSimHttpResposta;
var
  LQuantidade: Integer;
begin
  LQuantidade := FTransmissor.QuantidadeViolacoes;
  FTransmissor.LimparViolacoes;
  Result := Json(200, '{"removidas":' + IntToStr(LQuantidade) + '}');
end;

function TDFeSimuladorAdmin.GetUltimoEnvelope: TDFeSimHttpResposta;
begin
  // o adaptador guarda na convencao do ACBr; pela rede vai o texto de verdade
  Result := Resp(200, 'text/xml; charset=utf-8', TextoDoAcbr(FTransmissor.UltimoEnvelope));
end;

function TDFeSimuladorAdmin.GetModo: TDFeSimHttpResposta;
begin
  Result := Json(200, '{"estrito":' + LowerCase(BoolToStr(FTransmissor.Estrito, True)) + '}');
end;

function TDFeSimuladorAdmin.PostModo(const ACorpo: string): TDFeSimHttpResposta;
var
  LJson: TDFeJsonPlano;
  LErro: string;
begin
  if not LerJsonPlano(ACorpo, LJson, LErro) then
  begin
    Result := Erro(400, 'JSON invalido: ' + LErro);
    Exit;
  end;
  try
    if not LJson.Tem('estrito') then
    begin
      Result := Erro(400, 'informe "estrito": true ou false');
      Exit;
    end;
    FTransmissor.Estrito := LJson.Booleano('estrito', False);
    Result := GetModo;
  finally
    LJson.Free;
  end;
end;

{ ---- documentos, NSU, falhas ---- }

function TDFeSimuladorAdmin.PostDocumentos(const ACorpo: string): TDFeSimHttpResposta;
var
  LJson: TDFeJsonPlano;
  LErro, LCnpj, LUF, LTipo, LSchema, LXml, LEmitente, LXNome, LDhEmi, LTpEvento, LChave: string;
  LQuantidade, LNumero, LUltimo: Int64;
  I: Integer;
begin
  if not LerJsonPlano(ACorpo, LJson, LErro) then
  begin
    Result := Erro(400, 'JSON invalido: ' + LErro);
    Exit;
  end;
  try
    LCnpj := Trim(LJson.Texto('cnpj'));
    LUF := UpperCase(Trim(LJson.Texto('uf')));
    if not SoDigitos(LCnpj, [11, 14]) then
    begin
      Result := Erro(400, '"cnpj" ausente ou invalido (11 ou 14 digitos)');
      Exit;
    end;
    if Length(LUF) <> 2 then
    begin
      Result := Erro(400, '"uf" ausente ou invalida (2 letras)');
      Exit;
    end;

    // literal: schema + xml
    if LJson.Tem('xml') or LJson.Tem('schema') then
    begin
      LSchema := LJson.Texto('schema');
      LXml := LJson.Texto('xml');
      if (LSchema = '') or (LXml = '') then
      begin
        Result := Erro(400, 'documento literal exige "schema" E "xml"');
        Exit;
      end;
      LUltimo := FSimulador.PublicarDocumento(LCnpj, LUF, LSchema, LXml);
      Result := Json(200, '{"publicados":1,"ultimoNsu":' + IntToStr(LUltimo) + '}');
      Exit;
    end;

    // sintetico
    LTipo := LJson.Texto('tipo', 'resNFe');
    if LJson.Tem('quantidade') and not LJson.EInteiro('quantidade') then
    begin
      Result := Erro(400, '"quantidade" deve ser inteiro');
      Exit;
    end;
    LQuantidade := LJson.Inteiro('quantidade', 1);
    if (LQuantidade < 1) or (LQuantidade > MAX_QUANTIDADE) then
    begin
      Result := Erro(400, '"quantidade" deve estar entre 1 e ' + IntToStr(MAX_QUANTIDADE));
      Exit;
    end;
    if LJson.Tem('numero') and not LJson.EInteiro('numero') then
    begin
      Result := Erro(400, '"numero" deve ser inteiro');
      Exit;
    end;
    LNumero := LJson.Inteiro('numero', FSimulador.NsuAtual(LCnpj, LUF) + 1);
    if (LNumero < 1) or (LNumero > 999999999) then
    begin
      Result := Erro(400, '"numero" deve estar entre 1 e 999999999');
      Exit;
    end;
    LEmitente := Trim(LJson.Texto('emitente', DFE_SIM_CNPJ_EMITENTE));
    if not SoDigitos(LEmitente, [14]) then
    begin
      Result := Erro(400, '"emitente" deve ter 14 digitos');
      Exit;
    end;
    LXNome := XmlEscape(LJson.Texto('xNome', DFE_SIM_XNOME_EMITENTE));
    LDhEmi := LJson.Texto('dhEmi', '2026-09-10T14:30:05-03:00');
    LTpEvento := LJson.Texto('tpEvento', '110111');

    if SameText(LTipo, 'resNFe') then
      LSchema := DFE_SIM_SCHEMA_RESNFE
    else if SameText(LTipo, 'procNFe') then
      LSchema := DFE_SIM_SCHEMA_PROCNFE
    else if SameText(LTipo, 'resEvento') then
      LSchema := DFE_SIM_SCHEMA_RESEVENTO
    else if SameText(LTipo, 'procEventoNFe') then
      LSchema := DFE_SIM_SCHEMA_PROCEVENTONFE
    else
    begin
      Result := Erro(400, 'tipo desconhecido "' + LTipo + '" (resNFe, procNFe, resEvento, procEventoNFe)');
      Exit;
    end;

    if LJson.Tem('chave') then
    begin
      LChave := Trim(LJson.Texto('chave'));
      if (not SoDigitos(LChave, [44])) or (LQuantidade <> 1) then
      begin
        Result := Erro(400, '"chave" deve ter 44 digitos e so vale com quantidade 1');
        Exit;
      end;
    end
    else
      LChave := '';

    LUltimo := 0;
    for I := 0 to Integer(LQuantidade) - 1 do
    begin
      if not LJson.Tem('chave') then
        LChave := ChaveNFeSintetica(LEmitente, Integer(LNumero) + I);
      if SameText(LTipo, 'resNFe') then
        LXml := XmlResNFe(LChave, LEmitente, LXNome)
      else if SameText(LTipo, 'procNFe') then
        LXml := XmlProcNFe(LChave, LEmitente, LDhEmi)
      else if SameText(LTipo, 'resEvento') then
        LXml := XmlResEvento(LChave, LTpEvento)
      else
        LXml := XmlProcEventoNFe(LChave, LTpEvento);
      LUltimo := FSimulador.PublicarDocumento(LCnpj, LUF, LSchema, LXml);
    end;
    Result := Json(200, '{"publicados":' + IntToStr(LQuantidade) + ',"ultimoNsu":' + IntToStr(LUltimo) + '}');
  finally
    LJson.Free;
  end;
end;

function TDFeSimuladorAdmin.PostPularNsu(const ACorpo: string): TDFeSimHttpResposta;
var
  LJson: TDFeJsonPlano;
  LErro, LCnpj, LUF: string;
  LQuantidade: Int64;
begin
  if not LerJsonPlano(ACorpo, LJson, LErro) then
  begin
    Result := Erro(400, 'JSON invalido: ' + LErro);
    Exit;
  end;
  try
    LCnpj := Trim(LJson.Texto('cnpj'));
    LUF := UpperCase(Trim(LJson.Texto('uf')));
    if (not SoDigitos(LCnpj, [11, 14])) or (Length(LUF) <> 2) then
    begin
      Result := Erro(400, '"cnpj" (11 ou 14 digitos) e "uf" (2 letras) sao obrigatorios');
      Exit;
    end;
    if not LJson.EInteiro('quantidade') then
    begin
      Result := Erro(400, '"quantidade" inteira e obrigatoria');
      Exit;
    end;
    LQuantidade := LJson.Inteiro('quantidade', 0);
    if (LQuantidade < 1) or (LQuantidade > 1000000) then
    begin
      Result := Erro(400, '"quantidade" deve estar entre 1 e 1000000');
      Exit;
    end;
    FSimulador.PularNSU(LCnpj, LUF, Integer(LQuantidade));
    Result := Json(200, '{"nsuAtual":' + IntToStr(FSimulador.NsuAtual(LCnpj, LUF)) + '}');
  finally
    LJson.Free;
  end;
end;

function TDFeSimuladorAdmin.PostFalhas(const ACorpo: string): TDFeSimHttpResposta;
var
  LJson: TDFeJsonPlano;
  LErro: string;
  LNomes: TDFeJsonLista;
  LFalhas: array of TDFeFalhaSimulada;
  LFalha: TDFeFalhaSimulada;
  LQuantidade: Int64;
  I, K: Integer;
begin
  if not LerJsonPlano(ACorpo, LJson, LErro) then
  begin
    Result := Erro(400, 'JSON invalido: ' + LErro);
    Exit;
  end;
  try
    if LJson.Tem('falhas') then
      LNomes := LJson.Lista('falhas')
    else
      LNomes := LJson.Lista('falha');
    if Length(LNomes) = 0 then
    begin
      Result := Erro(400, 'informe "falha" ou "falhas" (validas: ' + NomesDeFalhaValidos + ')');
      Exit;
    end;
    if LJson.Tem('quantidade') and not LJson.EInteiro('quantidade') then
    begin
      Result := Erro(400, '"quantidade" deve ser inteiro');
      Exit;
    end;
    LQuantidade := LJson.Inteiro('quantidade', 1);
    if (LQuantidade < 1) or (LQuantidade > MAX_QUANTIDADE) then
    begin
      Result := Erro(400, '"quantidade" deve estar entre 1 e ' + IntToStr(MAX_QUANTIDADE));
      Exit;
    end;

    // valida TODAS antes de enfileirar qualquer uma
    SetLength(LFalhas, Length(LNomes));
    for I := 0 to High(LNomes) do
    begin
      if not FalhaPorNome(LNomes[I], LFalha) then
      begin
        Result := Erro(400, 'falha desconhecida "' + LNomes[I] + '" (validas: ' + NomesDeFalhaValidos + ')');
        Exit;
      end;
      LFalhas[I] := LFalha;
    end;
    for K := 1 to Integer(LQuantidade) do
      for I := 0 to High(LFalhas) do
        FSimulador.EnfileirarFalha(LFalhas[I]);
    Result := Json(200, '{"falhasPendentes":' + IntToStr(FSimulador.FalhasPendentes) + '}');
  finally
    LJson.Free;
  end;
end;

{ ---- cenario e zerar ---- }

function TDFeSimuladorAdmin.PostCenario(const ACorpo: string): TDFeSimHttpResposta;
var
  LResumo: TDFeCenarioResumo;
begin
  try
    LResumo := CarregarCenarioDeTexto(ACorpo, FSimulador);
  except
    on E: Exception do
    begin
      Result := Erro(400, E.Message);
      Exit;
    end;
  end;
  Result := Json(200, '{"contas":' + IntToStr(LResumo.Contas) + ',"documentos":' +
    IntToStr(LResumo.Documentos) + ',"falhas":' + IntToStr(LResumo.Falhas) + '}');
end;

function TDFeSimuladorAdmin.PostZerar: TDFeSimHttpResposta;
begin
  FSimulador.Zerar;
  FTransmissor.LimparViolacoes;
  if Assigned(FRelogio) then
    FRelogio.Zerar;
  Result := Json(200, '{"ok":true}');
end;

end.
