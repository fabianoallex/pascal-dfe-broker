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
    CStat: Integer;    // codigo de status da SEFAZ (137 = nenhum documento localizado, 138 = documentos localizados, 656 = consumo indevido, etc.)
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

implementation

end.
