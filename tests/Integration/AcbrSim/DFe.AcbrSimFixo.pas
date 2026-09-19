unit DFe.AcbrSimFixo;

{ Transmissor que devolve SEMPRE o mesmo texto -- para testar como o client
  reage a respostas que o simulador da SEFAZ (DFe.Simulador.Soap) nao produz de
  proposito, como um retDistDFeInt sem cStat.

  UNICO fonte, compartilhado pelo projeto FPC e pelo Delphi (sem atributo de
  teste, nao precisa de espelho). }

{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}

interface

uses
  SysUtils,
  DFe.Transmissor;

type
  TDFeTransmissorFixo = class(TInterfacedObject, IDFeTransmissor)
  private
    FTexto: string;
    FRequisicoes: Integer;
  public
    constructor Create(const ATexto: string);
    function Transmitir(const AEnvelope, AURL, ASoapAction,
      AMimeType: string): TDFeRespostaTransmissao;
    property Requisicoes: Integer read FRequisicoes;
  end;

{ Envelope SOAP de resposta da distribuicao cujo retDistDFeInt NAO tem cStat. }
function EnvelopeDistribuicaoSemCStat: string;

implementation

constructor TDFeTransmissorFixo.Create(const ATexto: string);
begin
  inherited Create;
  FTexto := ATexto;
end;

function TDFeTransmissorFixo.Transmitir(const AEnvelope, AURL, ASoapAction,
  AMimeType: string): TDFeRespostaTransmissao;
begin
  Inc(FRequisicoes);
  Result.Texto := FTexto;
  Result.HTTPResultCode := 200;
  Result.InternalErrorCode := 0;
end;

function EnvelopeDistribuicaoSemCStat: string;
begin
  Result := '<?xml version="1.0" encoding="utf-8"?>' +
    '<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope"><soap:Body>' +
    '<nfeDistDFeInteresseResponse xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe">' +
    '<nfeDistDFeInteresseResult>' +
    '<retDistDFeInt xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.01">' +
    '<tpAmb>2</tpAmb><verAplic>SEM-CSTAT</verAplic></retDistDFeInt>' +
    '</nfeDistDFeInteresseResult></nfeDistDFeInteresseResponse></soap:Body></soap:Envelope>';
end;

end.
