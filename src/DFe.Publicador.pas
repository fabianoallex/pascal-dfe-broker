unit DFe.Publicador;

{$I dfe.inc}

{ Fronteira com o broker, no mesmo espirito de IDFeDistribuicaoClient (ver
  DFe.Provider): o orquestrador nao fala com o pascal-amqp-faa diretamente,
  fala com esta interface. A implementacao real embrulha o client/channel do
  broker embutido; uma implementacao de teste so acumula em memoria o que
  foi publicado -- o que torna o orquestrador testavel sem broker nenhum
  rodando, do mesmo jeito que IDFeDistribuicaoClient o torna testavel sem
  certificado nenhum. }

interface

uses
  SysUtils;

type
  IDFePublicador = interface
    ['{2C6B8A3E-4D1F-4A9C-8B3E-4D1F4A9C8B3E}']
    { ARoutingKey segue a convencao de DFe.RoutingKey. APayload e' o XML do
      evento (TDFeEventoNormalizado.XmlPayload) -- serializacao/envelope de
      mensagem (headers AMQP, content-type, etc.) e' decisao da
      implementacao real, nao desta interface. }
    procedure Publicar(const ARoutingKey: string; const APayload: string);
  end;

implementation

end.
