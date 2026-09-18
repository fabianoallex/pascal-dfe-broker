unit DFe.Simulador.Client;

{$I dfe.inc}

{ Camada 1 do simulador (docs/simulador-sefaz.md): um IDFeDistribuicaoClient
  que responde a partir de TDFeSimuladorSefaz, SEM ACBr e sem SOAP. Cobre
  orquestrador + provider + publicacao contra uma "SEFAZ" com estado (NSU,
  janela de 1h, paginacao, falhas), o que o TDFeDistribuicaoClientFake de
  teste (fila de respostas prontas) nao faz.

  NAO exercita o client real (DFe.Client.ACBrNFe): a traducao de falhas
  abaixo e' a que o client real FAZ (timeout/HTTP -> EDFeComunicacaoFalhou,
  resposta ilegivel e docZip corrompido -> EDFeRespostaInvalida), mas aqui
  e' reimplementada para o simulador. Que o client real de fato se comporta
  assim e' o que tests/Integration/AcbrSim confirma (Fase 3) -- inclusive
  o docZip corrompido, que ANTES de uma conferencia no client passava como
  lote valido com item vazio. }

interface

uses
  SysUtils,
  DFe.Types,
  DFe.Errors,
  DFe.Provider,
  DFe.Simulador;

type
  TDFeSimuladorClient = class(TInterfacedObject, IDFeDistribuicaoClient)
  private
    FSimulador: TDFeSimuladorSefaz;
  public
    { O simulador NAO e' possuido: quem o criou o libera, depois de soltar
      todos os clients (mesma regra de qualquer dependencia por classe). }
    constructor Create(const ASimulador: TDFeSimuladorSefaz);
    function Consultar(const ACertificado: TDFeCertificado;
      const AUltimoNSU: Int64): TDFeLoteBruto;
  end;

implementation

constructor TDFeSimuladorClient.Create(const ASimulador: TDFeSimuladorSefaz);
begin
  inherited Create;
  FSimulador := ASimulador;
end;

function TDFeSimuladorClient.Consultar(const ACertificado: TDFeCertificado;
  const AUltimoNSU: Int64): TDFeLoteBruto;
var
  LResposta: TDFeRespostaSimulada;
begin
  LResposta := FSimulador.Consultar(ACertificado.CnpjCpf, ACertificado.UF, AUltimoNSU);
  case LResposta.Tipo of
    trsTimeout:
      raise EDFeComunicacaoFalhou.Create('Simulado: timeout na comunicacao com a SEFAZ');
    trsErroHttp:
      raise EDFeComunicacaoFalhou.Create('Simulado: erro HTTP na comunicacao com a SEFAZ');
    trsCorpoIlegivel:
      raise EDFeRespostaInvalida.Create('Simulado: resposta da SEFAZ ilegivel');
  end;

  if LResposta.DocZipCorrompido and (Length(LResposta.Lote.Itens) > 0) then
    raise EDFeRespostaInvalida.Create('Simulado: docZip corrompido na resposta da SEFAZ');

  Result := LResposta.Lote;
end;

end.
