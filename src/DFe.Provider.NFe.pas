unit DFe.Provider.NFe;

{$I dfe.inc}

{ Implementacao de IDFeProvider para NFe (ver DFe.Provider e
  docs/architecture.md, "Contrato de provider").

  PURA de proposito: nao usa ACBr nem I/O. Recebe o TDFeLoteBruto que
  DFe.Client.ACBrNFe (ou um dublê de teste) ja' montou -- com o docZip
  descompactado e o schema de cada item em TDFeItemBruto.Schema -- e so'
  o traduz para TDFeEventoNormalizado. Por isso e' testavel com fixtures
  sinteticas, sem certificado (ver "Fronteira testavel sem certificado
  real" em docs/architecture.md).

  Os quatro schemas que a Distribuicao de DFe devolve para NFe:

    resNFe          resumo de documento      -> dcDocumento
    procNFe         NFe completa (nfeProc)   -> dcDocumento
    resEvento       resumo de evento         -> dcEvento
    procEventoNFe   evento completo          -> dcEvento

  XmlPayload e' o XML do item exatamente como veio (resumo OU completo);
  quem consome distingue pela raiz do XML. Resumo e completo do mesmo
  documento saem na mesma routing-key (so' muda o payload), porque a
  convencao <tipo>.<categoria>.<uf>.<cnpj> nao distingue os dois.

  EXTRACAO DE CAMPOS SEM PARSER XML: os poucos campos lidos (chNFe,
  dhEmi/dEmi, dhEvento, tpEvento e o atributo Id de infNFe) sao folhas de
  schemas fiscais fixos, sem prefixo de namespace (a SEFAZ usa
  namespace default) -- localizar a tag por nome basta e mantem a unit
  identica nos dois compiladores, sem depender de MSXML/Xml.XMLDoc (so'
  Delphi) nem de DOM (so' FPC). Se a SEFAZ um dia passar a devolver
  prefixo de namespace nesses documentos, a extracao falha alto (chave
  nao encontrada -> EDFeRespostaInvalida), nunca em silencio. }

interface

uses
  SysUtils,
  DFe.Types,
  DFe.Errors,
  DFe.Provider;

const
  DFE_TIPO_DOCUMENTO_NFE = 'nfe';

  { cStat de "Rejeicao: Consumo Indevido" para NFe -- NT 2014.002 v1.02d
    (ver docs/referencias/README.md). NAO e' universal: MDF-e usa 678. }
  DFE_CSTAT_CONSUMO_INDEVIDO_NFE = 656;

{ Traduz o tpEvento numerico da NFe para o nome usado em
  TDFeEventoNormalizado.TipoEvento -- que vira parte da routing-key
  (<tipo>.evento.<TipoEvento>.<uf>.<cnpj>), ou seja, e' INTERFACE PUBLICA
  (decisao 4 em CLAUDE.md).

  Os quatro tipos de manifestacao usam o mesmo vocabulario de
  DFe.Manifestacao ('confirmacao', 'ciencia', 'desconhecimento',
  'operacaonaorealizada'), para o resultado de uma manifestacao enviada
  pelo broker sair na mesma routing-key que o evento equivalente vindo da
  distribuicao.

  Codigo sem nome mapeado devolve o proprio codigo numerico
  (ex.: '110150') -- nunca descarta nem inventa nome. ATENCAO: promover um
  codigo hoje numerico a um nome depois MUDA a routing-key dele, entao so'
  acrescentar nomes aqui apos avaliar consumidores existentes. }
function NomeTipoEventoNFe(const ATpEvento: string): string;

type
  TDFeProviderNFe = class(TInterfacedObject, IDFeProvider)
  public
    function Identificador: string;
    function CodigoConsumoIndevido: Integer;

    { Levanta EDFeRespostaInvalida quando um item de schema CONHECIDO
      esta malformado (sem chave de 44 digitos, evento sem tpEvento) --
      dado corrompido nao pode ser publicado nem descartado em silencio.

      Item de schema DESCONHECIDO e' ignorado (nao levanta): um schema
      novo da SEFAZ nao pode travar o cursor de todos os outros
      documentos do CNPJ. Trade-off consciente -- ver
      docs/architecture.md, "Provider NFe". }
    function Decodificar(const ALote: TDFeLoteBruto;
      const ACertificado: TDFeCertificado): TDFeEventoNormalizadoArray;
  end;

implementation

uses
  StrUtils;

type
  TSchemaNFe = (snDesconhecido, snResNFe, snProcNFe, snResEvento, snProcEvento);

{ Localiza '<ATag' garantindo que e' a tag exata e nao prefixo de outra
  (ex.: '<chNFe' dentro de '<chNFeAlgo'). Devolve a posicao do '<', ou 0. }
function LocalizarAbertura(const AXml, ATag: string): Integer;
var
  LMarca: string;
  LProximo: Char;
begin
  LMarca := '<' + ATag;
  Result := PosEx(LMarca, AXml, 1);
  while Result > 0 do
  begin
    if Result + Length(LMarca) > Length(AXml) then
    begin
      Result := 0;
      Exit;
    end;
    LProximo := AXml[Result + Length(LMarca)];
    if (LProximo = '>') or (LProximo = '/') or (LProximo = ' ')
      or (LProximo = #9) or (LProximo = #10) or (LProximo = #13) then
      Exit;
    Result := PosEx(LMarca, AXml, Result + 1);
  end;
end;

{ Conteudo da primeira ocorrencia de <ATag>...</ATag>, sem espacos nas
  pontas; '' se nao existir (ou for auto-fechada). }
function ExtrairTag(const AXml, ATag: string): string;
var
  LAbre, LFimAbertura, LFecha: Integer;
begin
  Result := '';
  LAbre := LocalizarAbertura(AXml, ATag);
  if LAbre = 0 then
    Exit;

  LFimAbertura := PosEx('>', AXml, LAbre);
  if (LFimAbertura = 0) or (AXml[LFimAbertura - 1] = '/') then
    Exit;

  LFecha := PosEx('</' + ATag + '>', AXml, LFimAbertura + 1);
  if LFecha = 0 then
    Exit;

  Result := Trim(Copy(AXml, LFimAbertura + 1, LFecha - LFimAbertura - 1));
end;

{ Valor de AAtributo="..." dentro da abertura de <ATag ...>; '' se nao existir. }
function ExtrairAtributo(const AXml, ATag, AAtributo: string): string;
var
  LAbre, LFimAbertura, LAttr, LInicio, LFim: Integer;
  LAbertura: string;
begin
  Result := '';
  LAbre := LocalizarAbertura(AXml, ATag);
  if LAbre = 0 then
    Exit;

  LFimAbertura := PosEx('>', AXml, LAbre);
  if LFimAbertura = 0 then
    Exit;

  LAbertura := Copy(AXml, LAbre, LFimAbertura - LAbre + 1);
  LAttr := Pos(' ' + AAtributo + '="', LAbertura);
  if LAttr = 0 then
    Exit;

  LInicio := LAttr + Length(AAtributo) + 3;
  LFim := PosEx('"', LAbertura, LInicio);
  if LFim = 0 then
    Exit;

  Result := Copy(LAbertura, LInicio, LFim - LInicio);
end;

{ ISO 8601 como a SEFAZ escreve: 'AAAA-MM-DD' ou 'AAAA-MM-DDThh:mm:ss' com
  fracao e/ou fuso opcionais ('...-03:00'). O fuso e' DESCARTADO: o valor
  e' o horario de parede local escrito no documento, sem conversao. 0 se
  ausente ou ilegivel (TDFeEventoNormalizado.DataEmissao documenta 0 como
  "nao disponivel"). }
function ParseDataHoraISO(const AValor: string): TDateTime;
var
  LData, LHora: TDateTime;
begin
  Result := 0;
  if (Length(AValor) < 10) or (AValor[5] <> '-') or (AValor[8] <> '-') then
    Exit;

  if not TryEncodeDate(StrToIntDef(Copy(AValor, 1, 4), -1),
    StrToIntDef(Copy(AValor, 6, 2), -1), StrToIntDef(Copy(AValor, 9, 2), -1), LData) then
    Exit;

  LHora := 0;
  if (Length(AValor) >= 19) and (AValor[11] = 'T') and (AValor[14] = ':') and (AValor[17] = ':') then
    if not TryEncodeTime(StrToIntDef(Copy(AValor, 12, 2), -1),
      StrToIntDef(Copy(AValor, 15, 2), -1), StrToIntDef(Copy(AValor, 18, 2), -1), 0, LHora) then
      LHora := 0;

  Result := LData + LHora;
end;

function ChaveAcessoValida(const AChave: string): Boolean;
var
  I: Integer;
begin
  Result := Length(AChave) = 44;
  if Result then
    for I := 1 to 44 do
      if not CharInSet(AChave[I], ['0'..'9']) then
      begin
        Result := False;
        Exit;
      end;
end;

function SchemaDoItem(const ASchema: string): TSchemaNFe;
var
  LNome: string;
  LCorte: Integer;
begin
  { Aceita tanto o nome que DFe.Client.ACBrNFe produz ('resNFe') quanto o
    nome de arquivo oficial ('resNFe_v1.01.xsd') -- ver comentario de
    TDFeItemBruto.Schema em DFe.Types. }
  LNome := ASchema;
  LCorte := Pos('_', LNome);
  if LCorte > 0 then
    LNome := Copy(LNome, 1, LCorte - 1);
  LCorte := Pos('.', LNome);
  if LCorte > 0 then
    LNome := Copy(LNome, 1, LCorte - 1);

  if SameText(LNome, 'resNFe') then
    Result := snResNFe
  else if SameText(LNome, 'procNFe') then
    Result := snProcNFe
  else if SameText(LNome, 'resEvento') then
    Result := snResEvento
  else if SameText(LNome, 'procEventoNFe') then
    Result := snProcEvento
  else
    Result := snDesconhecido;
end;

function NomeTipoEventoNFe(const ATpEvento: string): string;
begin
  if ATpEvento = '110110' then
    Result := 'cartacorrecao'
  else if ATpEvento = '110111' then
    Result := 'cancelamento'
  else if ATpEvento = '110112' then
    Result := 'cancelamentosubstituicao'
  else if ATpEvento = '110140' then
    Result := 'epec'
  else if ATpEvento = '210200' then
    Result := 'confirmacao'
  else if ATpEvento = '210210' then
    Result := 'ciencia'
  else if ATpEvento = '210220' then
    Result := 'desconhecimento'
  else if ATpEvento = '210240' then
    Result := 'operacaonaorealizada'
  else
    Result := ATpEvento;
end;

procedure LevantarItemInvalido(const AItem: TDFeItemBruto; const AMotivo: string);
begin
  raise EDFeRespostaInvalida.CreateFmt('Item NSU %d (schema "%s") invalido: %s',
    [AItem.NSU, AItem.Schema, AMotivo]);
end;

{ Devolve False para schema desconhecido (item deve ser ignorado). Levanta
  EDFeRespostaInvalida para item de schema conhecido e malformado. }
function TryDecodificarItem(const AItem: TDFeItemBruto;
  const ACertificado: TDFeCertificado; out AEvento: TDFeEventoNormalizado): Boolean;
var
  LSchema: TSchemaNFe;
  LChave, LTpEvento, LData: string;
begin
  LSchema := SchemaDoItem(AItem.Schema);
  Result := LSchema <> snDesconhecido;

  AEvento.TipoDocumento := DFE_TIPO_DOCUMENTO_NFE;
  AEvento.Categoria := dcDocumento;
  AEvento.TipoEvento := '';
  AEvento.ChaveAcesso := '';
  AEvento.CnpjCpfConsultante := ACertificado.CnpjCpf;
  AEvento.UF := ACertificado.UF;
  AEvento.NSU := AItem.NSU;
  AEvento.XmlPayload := AItem.XmlDecodificado;
  AEvento.DataEmissao := 0;

  if not Result then
    Exit;

  case LSchema of
    snResNFe:
      begin
        LChave := ExtrairTag(AItem.XmlDecodificado, 'chNFe');
        LData := ExtrairTag(AItem.XmlDecodificado, 'dhEmi');
      end;
    snProcNFe:
      begin
        { Id="NFe<44 digitos>" em infNFe e' a fonte primaria (sempre presente
          na NFe assinada); chNFe do protocolo e' o fallback. }
        LChave := ExtrairAtributo(AItem.XmlDecodificado, 'infNFe', 'Id');
        if StartsText('NFe', LChave) then
          LChave := Copy(LChave, 4, MaxInt)
        else
          LChave := ExtrairTag(AItem.XmlDecodificado, 'chNFe');
        LData := ExtrairTag(AItem.XmlDecodificado, 'dhEmi');
        if LData = '' then
          LData := ExtrairTag(AItem.XmlDecodificado, 'dEmi'); // NFe 2.00/3.10 antigas
      end;
  else // snResEvento, snProcEvento
    begin
      AEvento.Categoria := dcEvento;
      { Primeira ocorrencia: em procEventoNFe e' a de evento/infEvento;
        retEvento (depois) repete os mesmos valores. }
      LChave := ExtrairTag(AItem.XmlDecodificado, 'chNFe');
      LTpEvento := ExtrairTag(AItem.XmlDecodificado, 'tpEvento');
      LData := ExtrairTag(AItem.XmlDecodificado, 'dhEvento');
      if LTpEvento = '' then
        LevantarItemInvalido(AItem, 'evento sem tpEvento');
      AEvento.TipoEvento := NomeTipoEventoNFe(LTpEvento);
    end;
  end;

  if not ChaveAcessoValida(LChave) then
    LevantarItemInvalido(AItem, Format('chave de acesso ausente ou fora do formato de 44 digitos ("%s")', [LChave]));

  AEvento.ChaveAcesso := LChave;
  AEvento.DataEmissao := ParseDataHoraISO(LData);
end;

{ TDFeProviderNFe }

function TDFeProviderNFe.Identificador: string;
begin
  Result := DFE_TIPO_DOCUMENTO_NFE;
end;

function TDFeProviderNFe.CodigoConsumoIndevido: Integer;
begin
  Result := DFE_CSTAT_CONSUMO_INDEVIDO_NFE;
end;

function TDFeProviderNFe.Decodificar(const ALote: TDFeLoteBruto;
  const ACertificado: TDFeCertificado): TDFeEventoNormalizadoArray;
var
  I, LTotal: Integer;
  LEvento: TDFeEventoNormalizado;
begin
  Result := nil;
  SetLength(Result, Length(ALote.Itens));
  LTotal := 0;

  for I := 0 to High(ALote.Itens) do
    if TryDecodificarItem(ALote.Itens[I], ACertificado, LEvento) then
    begin
      Result[LTotal] := LEvento;
      Inc(LTotal);
    end;

  SetLength(Result, LTotal);
end;

initialization
  TDFeProviderRegistry.Registrar(TDFeProviderNFe.Create);

end.
