unit DFe.Transmissor;

{$I dfe.inc}

{ Costura de injecao do TRANSPORTE do client ACBr (ver
  DFe.Client.ACBrNFe e docs/simulador-sefaz.md, Fase 1).

  Por padrao o ACBr monta o envelope SOAP e ele mesmo faz o HTTP/TLS
  mutuo. Um IDFeTransmissor, quando injetado no client, assume so' esse
  ultimo passo: recebe o envelope pronto e devolve o texto da resposta
  (ou um codigo de falha). Todo o resto -- montagem do envelope, parse da
  resposta, cStat, docZip, traducao de excecao para DFe.Errors -- continua
  sendo o ACBr e o codigo REAL do client. E' o que permite ao simulador
  da SEFAZ e a testes exercitar o client de verdade sem rede nem
  certificado aceito pela SEFAZ.

  Unit pura (sem ACBr) de proposito: o nucleo do simulador nao deve
  depender do ACBr, so' o adaptador dele. }

interface

type
  { HTTPResultCode e InternalErrorCode espelham o contrato do
    TACBrDFe.OnTransmit: InternalErrorCode <> 0 significa falha antes de
    existir resposta HTTP (10060 = timeout, ver ACBrDFeWebService.pas);
    nesse caso Texto e' ignorado. }
  TDFeRespostaTransmissao = record
    Texto: string;
    HTTPResultCode: Integer;
    InternalErrorCode: Integer;
  end;

  IDFeTransmissor = interface
    ['{6F1C2B7E-3A54-4D0B-9C6A-1E8D5B7F2A90}']
    function Transmitir(const AEnvelope, AURL, ASoapAction,
      AMimeType: string): TDFeRespostaTransmissao;
  end;

implementation

end.
