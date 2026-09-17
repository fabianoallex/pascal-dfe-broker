unit DFe.Types;

{$I dfe.inc}

{ Tipos de valor compartilhados entre o core e qualquer provider (NFe, e
  futuramente CTe/MDFe). Nao ha logica aqui, so os dados que atravessam a
  fronteira entre "consulta bruta a SEFAZ" e "evento normalizado publicado
  no broker" -- ver docs/architecture.md no repositorio para o desenho
  completo e o porque de cada campo existir. }

interface

uses
  SysUtils;

type
  { Documento normal (resNFe/resCTe/resMDFe) vs. evento (cancelamento,
    ciencia da operacao, etc.). O tipo especifico do evento fica em
    TDFeEventoNormalizado.TipoEvento, nao aqui -- esta categoria e' so o
    primeiro nivel da routing-key (ver DFe.RoutingKey). }
  TDFeCategoria = (dcDocumento, dcEvento);

  { Identifica de qual certificado + UF partiu a consulta. Ainda nao amarrado
    a nenhuma forma real de certificado digital (arquivo .pfx, Windows
    CryptoAPI, etc.) -- isso e' decisao da implementacao real do
    IDFeDistribuicaoClient (ver DFe.Provider), nunca deste record. }
  TDFeCertificado = record
    Identificador: string;  // alias livre configurado pelo usuario (nao e' o CNPJ/CPF em si)
    CnpjCpf: string;        // somente digitos
    UF: string;             // sigla, ex.: 'RS'
  end;

  { Um item do lote bruto devolvido pela consulta de Distribuicao de DFe, ja
    com o envelope de transporte (gzip+base64 do docZip) decodificado -- essa
    decodificacao e' generica entre tipos de documento e nao e' preocupacao
    de nenhum provider especifico. O que resta especifico por tipo de
    documento e' interpretar XmlDecodificado de acordo com Schema. }
  TDFeItemBruto = record
    NSU: Int64;
    Schema: string;          // ex.: 'resNFe_v1.01.xsd', 'resEvento_v1.01.xsd' -- como a SEFAZ identifica o schema do item
    XmlDecodificado: string; // XML ja fora do gzip+base64
  end;

  TDFeItemBrutoArray = array of TDFeItemBruto;

  { Retorno bruto de uma chamada de Distribuicao de DFe, antes de qualquer
    interpretacao especifica de tipo de documento. }
  TDFeLoteBruto = record
    CStat: Integer;    // codigo de status da SEFAZ (137 = nenhum documento localizado, 138 = documentos localizados; o codigo de consumo indevido VARIA por tipo de documento -- ver ClassificarCStat abaixo)
    XMotivo: string;
    UltimoNSU: Int64;  // maior NSU devolvido neste lote
    MaxNSU: Int64;     // maior NSU disponivel no ambiente da SEFAZ (UltimoNSU < MaxNSU => ha mais lotes a buscar)
    Itens: TDFeItemBrutoArray;
  end;

  { O evento interno padronizado (ver "Evento interno padronizado" em
    docs/architecture.md) -- e' o que todo provider produz e o que o core
    publica no broker, independente de o documento ser NFe, CTe ou MDFe. }
  TDFeEventoNormalizado = record
    TipoDocumento: string;        // identificador do provider: 'nfe', 'cte', 'mdfe', ...
    Categoria: TDFeCategoria;
    TipoEvento: string;           // vazio quando Categoria = dcDocumento; ex.: 'cancelamento', 'cienciaOperacao' quando dcEvento
    ChaveAcesso: string;
    CnpjCpfConsultante: string;   // dono da consulta (o certificado usado), nao necessariamente emitente/destinatario do documento
    UF: string;
    NSU: Int64;
    XmlPayload: string;           // resumo e/ou XML completo, conforme o que a distribuicao devolveu para este item
    DataEmissao: TDateTime;       // 0 quando nao disponivel no retorno da distribuicao
  end;

  TDFeEventoNormalizadoArray = array of TDFeEventoNormalizado;

  { Como o orquestrador interpreta o CStat de um TDFeLoteBruto -- concentrar
    essa leitura numa unica funcao pura (ClassificarCStat) em vez de espalhar
    "if CStat = codigo" pelo core é o que torna essa interpretacao testavel
    isoladamente e documentada num lugar so.

    Fontes primarias conferidas em 2026-09-17 (copias em
    docs/referencias/, ver o README la para os links oficiais e o porque
    de cada fato): NT 2014.002 v1.02d (NFe), NT 2015/002 v1.00a (CT-e),
    NT 2015/002 v1.00b (MDF-e). 137/138/108/109 sao identicos nos tres
    servicos -- confirmado, nao mais suposicao. }
  TDFeClassificacaoCStat = (
    dccDocumentosLocalizados,  // cStat 138: ha itens em TDFeLoteBruto.Itens
    dccNenhumDocumento,        // cStat 137: consulta ok, nada novo
    dccConsumoIndevido,        // consultou antes do intervalo minimo (1h) -- o CODIGO NUMERICO NAO E UNIVERSAL, ver ACodigoConsumoIndevido abaixo
    dccServicoIndisponivel,    // cStat 108/109: SEFAZ em manutencao/paralisada -- transitorio, tratar como falha de comunicacao
    dccDesconhecido            // qualquer outro codigo -- tratar de forma conservadora (como transitorio), nunca assumir sucesso
  );

  { O codigo de "Rejeicao: Consumo Indevido" NAO e' o mesmo em todos os
    tipos de documento -- NFe e CT-e usam 656, MDF-e usa 678 (ver
    docs/referencias/README.md). Por isso nao ha uma constante global
    DFE_CSTAT_CONSUMO_INDEVIDO: cada IDFeProvider expõe o proprio codigo
    (ver DFe.Provider.CodigoConsumoIndevido) e passa para esta funcao. }
function ClassificarCStat(const ACStat: Integer;
  const ACodigoConsumoIndevido: Integer): TDFeClassificacaoCStat;

implementation

function ClassificarCStat(const ACStat: Integer;
  const ACodigoConsumoIndevido: Integer): TDFeClassificacaoCStat;
begin
  case ACStat of
    138: Result := dccDocumentosLocalizados;
    137: Result := dccNenhumDocumento;
    108, 109: Result := dccServicoIndisponivel;
  else
    if ACStat = ACodigoConsumoIndevido then
      Result := dccConsumoIndevido
    else
      Result := dccDesconhecido;
  end;
end;

end.
