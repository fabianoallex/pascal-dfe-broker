unit uDFeDocumento;

{ Leitura do que o pascal-dfe-broker publica -- SEM depender do broker nem de
  nenhuma unit dele: um consumidor de terceiros so' enxerga a routing-key e o
  XML do corpo (o contrato esta em exemplos/consumidor/README.md).

  Unit pura (nada de VCL/LCL, nada de AMQP): compila igual no Delphi e no FPC
  (modo Delphi) e e' a parte do sample que da' para testar sem tela.

  O XML e' lido por busca de tag, sem parser: os campos usados sao folhas do
  schema fiscal, sem prefixo de namespace -- o mesmo criterio do provider NFe
  do broker. Um consumidor de verdade que precise do documento inteiro deve
  usar um parser XML (ou o proprio ACBr, para gerar o DANFE, por exemplo). }

interface

type
  { <tipo>.<categoria>.<uf>.<cnpj>, ou <tipo>.evento.<tipoevento>.<uf>.<cnpj>.
    <cnpj> e' o do CERTIFICADO que consultou, nao necessariamente o do
    emitente ou do destinatario. }
  TDFeRoutingKey = record
    Valida: Boolean;
    Tipo: string;        // nfe
    Categoria: string;   // documento | evento
    TipoEvento: string;  // so' em evento: cancelamento, ciencia, manifestacaorejeitada...
    UF: string;
    Cnpj: string;
  end;

  { O que da' para dizer de um item sem abrir o XML inteiro. }
  TDFeInfo = record
    Legivel: Boolean;
    TipoXml: string;     // resNFe, nfeProc, resEvento, procEventoNFe...
    Chave: string;       // chave de acesso, 44 digitos
    TpEvento: string;    // so' em evento
    XNome: string;
    VNF: string;
    DhEmi: string;
    { Chave de deduplicacao: a entrega e' "pelo menos uma vez", entao o mesmo
      documento pode chegar duas vezes. Resumo e documento completo da mesma
      NFe sao itens DIFERENTES (tipo de XML diferente); um evento e' um item
      por (chave, tpEvento). }
    function ChaveDeDedup: string;
    { Nome de arquivo (sem pasta) que identifica o item: chave + tipo do XML
      [+ tpEvento]. Deterministico: salvar o mesmo item duas vezes sobrescreve
      o mesmo arquivo, entao a entrega repetida nao gera lixo. So' letras e
      digitos (a chave vem de um XML de fora; nao se confia nela num caminho). }
    function NomeDeArquivo: string;
    function Resumo: string;
  end;

function LerRoutingKey(const ARoutingKey: string): TDFeRoutingKey;
function LerXml(const AXml: string): TDFeInfo;

const
  DFE_EXCHANGE = 'dfe';
  DFE_RK_COMANDO_MANIFESTACAO = 'comando.manifestacao';

  { Tipos aceitos pelo host (TipoEvento do comando). }
  DFE_TIPOS_MANIFESTACAO: array[0..3] of string =
    ('ciencia', 'confirmacao', 'desconhecimento', 'operacaonaorealizada');

{ Monta o corpo do comando de manifestacao (chave=valor, uma por linha).
  Devolve '' e o motivo em AErro quando a entrada nao serve; o host valida de
  novo (e e' a palavra final), isto so' evita mandar o que se sabe invalido. }
function MontarComandoManifestacao(const AAlias, AChave, ATipo, AJustificativa: string;
  out AErro: string): string;

implementation

uses
  SysUtils;

function LerRoutingKey(const ARoutingKey: string): TDFeRoutingKey;
var
  LPartes: array of string;
  LInicio, I: Integer;
begin
  Result.Valida := False;
  Result.Tipo := '';
  Result.Categoria := '';
  Result.TipoEvento := '';
  Result.UF := '';
  Result.Cnpj := '';

  SetLength(LPartes, 0);
  LInicio := 1;
  for I := 1 to Length(ARoutingKey) + 1 do
    if (I > Length(ARoutingKey)) or (ARoutingKey[I] = '.') then
    begin
      SetLength(LPartes, Length(LPartes) + 1);
      LPartes[High(LPartes)] := Copy(ARoutingKey, LInicio, I - LInicio);
      LInicio := I + 1;
    end;

  // documento: 4 palavras; evento: 5 (a terceira e' o tipo do evento)
  if (Length(LPartes) = 4) and (LPartes[1] = 'documento') then
  begin
    Result.Tipo := LPartes[0];
    Result.Categoria := LPartes[1];
    Result.UF := LPartes[2];
    Result.Cnpj := LPartes[3];
    Result.Valida := True;
  end
  else if (Length(LPartes) = 5) and (LPartes[1] = 'evento') then
  begin
    Result.Tipo := LPartes[0];
    Result.Categoria := LPartes[1];
    Result.TipoEvento := LPartes[2];
    Result.UF := LPartes[3];
    Result.Cnpj := LPartes[4];
    Result.Valida := True;
  end;
end;

{ Texto entre <ATag> e </ATag>, '' se nao houver. Nao serve para tag com
  atributo nem com prefixo de namespace -- as folhas que usamos nao tem. }
function TextoDaTag(const AXml, ATag: string): string;
var
  LAbre, LFecha: Integer;
begin
  Result := '';
  LAbre := Pos('<' + ATag + '>', AXml);
  if LAbre = 0 then
    Exit;
  Inc(LAbre, Length(ATag) + 2);
  LFecha := Pos('</' + ATag + '>', AXml);
  if LFecha < LAbre then
    Exit;
  Result := Trim(Copy(AXml, LAbre, LFecha - LAbre));
end;

{ Nome do elemento raiz: a primeira tag que nao e' declaracao (<?xml ...?>),
  comentario nem DOCTYPE. }
function NomeDaRaiz(const AXml: string): string;
var
  I, J: Integer;
begin
  Result := '';
  I := 1;
  while I < Length(AXml) do
  begin
    if (AXml[I] = '<') and (AXml[I + 1] <> '?') and (AXml[I + 1] <> '!') then
    begin
      J := I + 1;
      while (J <= Length(AXml)) and not CharInSet(AXml[J], [' ', '>', '/', #9, #10, #13]) do
        Inc(J);
      Result := Copy(AXml, I + 1, J - I - 1);
      Exit;
    end;
    Inc(I);
  end;
end;

function ChaveDoAtributoId(const AXml: string): string;
var
  LPos: Integer;
begin
  // <infNFe Id="NFe35..."> no documento completo
  Result := '';
  LPos := Pos('Id="NFe', AXml);
  if LPos > 0 then
    Result := Copy(AXml, LPos + 7, 44);
end;

function LerXml(const AXml: string): TDFeInfo;
begin
  Result.TipoXml := NomeDaRaiz(AXml);
  Result.Legivel := (Result.TipoXml <> '') and (Pos('</', AXml) > 0);
  Result.Chave := TextoDaTag(AXml, 'chNFe');
  if Result.Chave = '' then
    Result.Chave := ChaveDoAtributoId(AXml);
  Result.TpEvento := TextoDaTag(AXml, 'tpEvento');
  Result.XNome := TextoDaTag(AXml, 'xNome');
  Result.VNF := TextoDaTag(AXml, 'vNF');
  Result.DhEmi := TextoDaTag(AXml, 'dhEmi');
end;

function TDFeInfo.ChaveDeDedup: string;
begin
  Result := TipoXml + '|' + Chave + '|' + TpEvento;
end;

function SoAlfanumerico(const AText: string): string;
var
  I: Integer;
begin
  Result := AText;
  for I := 1 to Length(Result) do
    if not CharInSet(Result[I], ['0'..'9', 'A'..'Z', 'a'..'z']) then
      Result[I] := '_';
end;

function TDFeInfo.NomeDeArquivo: string;
begin
  if Chave = '' then
    Result := 'sem-chave'
  else
    Result := SoAlfanumerico(Chave);
  Result := Result + '_' + SoAlfanumerico(TipoXml);
  if TpEvento <> '' then
    Result := Result + '_' + SoAlfanumerico(TpEvento);
  Result := Result + '.xml';
end;

procedure Acrescentar(var ATexto: string; const AParte: string);
begin
  if ATexto <> '' then
    ATexto := ATexto + ', ';
  ATexto := ATexto + AParte;
end;

function TDFeInfo.Resumo: string;
begin
  Result := '';
  if XNome <> '' then
    Acrescentar(Result, 'xNome=' + XNome);
  if DhEmi <> '' then
    Acrescentar(Result, 'dhEmi=' + DhEmi);
  if VNF <> '' then
    Acrescentar(Result, 'vNF=' + VNF);
  if TpEvento <> '' then
    Acrescentar(Result, 'tpEvento=' + TpEvento);
end;

function MontarComandoManifestacao(const AAlias, AChave, ATipo, AJustificativa: string;
  out AErro: string): string;
var
  I: Integer;
  LTipoValido: Boolean;
begin
  Result := '';
  AErro := '';

  if Trim(AAlias) = '' then
  begin
    AErro := 'Informe o alias do certificado (a secao [certificado:alias] do dfe.ini).';
    Exit;
  end;

  if Length(AChave) <> 44 then
    AErro := 'A chave de acesso tem 44 digitos.'
  else
    for I := 1 to 44 do
      if not CharInSet(AChave[I], ['0'..'9']) then
        AErro := 'A chave de acesso tem 44 digitos.';
  if AErro <> '' then
    Exit;

  LTipoValido := False;
  for I := Low(DFE_TIPOS_MANIFESTACAO) to High(DFE_TIPOS_MANIFESTACAO) do
    if DFE_TIPOS_MANIFESTACAO[I] = ATipo then
      LTipoValido := True;
  if not LTipoValido then
  begin
    AErro := 'Tipo de manifestacao desconhecido: ' + ATipo;
    Exit;
  end;

  if (ATipo = 'operacaonaorealizada') and (Trim(AJustificativa) = '') then
  begin
    AErro := 'operacaonaorealizada exige justificativa (15 a 255 caracteres).';
    Exit;
  end;

  Result := 'Alias=' + Trim(AAlias) + #10 + 'ChaveAcesso=' + AChave + #10 + 'TipoEvento=' + ATipo;
  // so' operacaonaorealizada leva justificativa; nos outros o host a descarta
  if ATipo = 'operacaonaorealizada' then
    Result := Result + #10 + 'Justificativa=' + Trim(AJustificativa);
end;

end.
