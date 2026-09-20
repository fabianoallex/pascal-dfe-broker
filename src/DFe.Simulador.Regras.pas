unit DFe.Simulador.Regras;

{$I dfe.inc}

(* EXTENSAO do simulador em Pascal (docs/simulador-standalone.md, Fase C).

  Uma REGRA e' uma classe do usuario que se PENDURA no simulador sem tocar no core:
  pode responder no lugar dele, alterar a resposta dele, servir rotas proprias
  (/ext/...) e reagir ao /admin/zerar. O usuario compila o proprio executavel do
  simulador com a unit dele (mesmo padrao de auto-registro do TDFeProviderRegistry,
  decisao 10 do CLAUDE.md):

    type
      TMinhaRegra = class(TDFeSimuladorRegra)
      public
        class function Nome: string; override;
        function AntesDeAtender(const AReq: TDFeSimRequisicao;
          var AResposta: TDFeSimHttpResposta): Boolean; override;
      end;
    ...
    initialization
      RegistrarRegraSimulador(TMinhaRegra);

  Contrato dos ganchos (todos rodam SOB A TRAVA do servidor: uma regra pode mexer
  no simulador -- Simulador -- sem se preocupar com concorrencia, e NAO deve
  bloquear, pois trava as demais requisicoes):

  - AntesDeAtender: so' para as duas rotas SOAP (Distribuicao e RecepcaoEvento).
    Devolver True = "eu respondi": AResposta e' a resposta final, o nucleo NAO e'
    tocado (nenhum NSU consumido, nenhum bloqueio aberto) e as regras seguintes
    nem sao consultadas. Devolver False = deixa passar.
  - DepoisDeAtender: so' quando NINGUEM respondeu antes; a resposta do nucleo vem
    em AResposta e a regra pode alterar. Rodam todas as regras ativas, na ordem.
  - TratarRota: para caminhos que comecam com /ext/ (rotas proprias, qualquer
    metodo). A primeira regra ativa que devolver True responde; nenhuma -> 404.
  - AoZerar: depois de um POST /admin/zerar bem-sucedido (a regra limpa o proprio
    estado, como o nucleo limpa o dele).
  - Excecao em qualquer gancho vira HTTP 500 com a mensagem (bug de regra aparece).

  As regras NAO veem /admin nem /ping: uma regra com defeito nao pode tirar do
  ar o controle do simulador. Uma regra LIGA/DESLIGA por GET/POST /admin/regras.

  Texto: Corpo e' texto NATIVO (o que a rede levou); ver DFe.XmlTexto.

  Instancia-se UMA regra por servidor (o estado dela e' do servidor, nao global):
  o registro guarda CLASSES, nao objetos. Rotas HTTP proprias fora de /ext/ (ou com
  outra logica) tambem podem ser registradas direto no Horse pelo programa do
  usuario (THorse.Get/Post...), pois o Horse e' global.

  Pura: sem HTTP, sem ACBr, sem broker. *)

interface

uses
  SysUtils,
  DFe.Simulador,
  DFe.Simulador.Soap,
  DFe.Simulador.Admin;

const
  CAMINHO_EXTENSAO = '/ext/';
  DFE_SIM_CONTENT_TYPE_SOAP = 'application/soap+xml; charset=utf-8';

type
  TDFeSimServico = (
    ssDistribuicao, // NFeDistribuicaoDFe
    ssEvento,       // NFeRecepcaoEvento4
    ssExtensao      // /ext/...
  );

  { O que chegou. Corpo e o cabecalho sao os do request; Agora e' o relogio do
    SIMULADOR (o virtual, se houver), nao o do sistema. }
  TDFeSimRequisicao = record
    Servico: TDFeSimServico;
    Metodo: string;
    Caminho: string;
    SoapAction: string;
    ContentType: string;
    Corpo: string;
    Agora: TDateTime;
  end;

  TDFeSimuladorRegra = class
  private
    FSimulador: TDFeSimuladorSefaz;
    FAtiva: Boolean;
  protected
    { O simulador do servidor a que esta regra pertence (nil antes de Anexar). Use-o
      so' DENTRO de um gancho (a trava do servidor esta tomada). }
    property Simulador: TDFeSimuladorSefaz read FSimulador;
  public
    constructor Create; virtual;

    { Identificador unico, estavel, em minusculas e sem espacos (aparece em
      /admin/regras). Duas regras com o mesmo Nome nao convivem. }
    class function Nome: string; virtual; abstract;
    class function Descricao: string; virtual;
    { Estado inicial (padrao True). Uma regra que atrapalha o uso normal pode
      nascer desligada e ser ligada por POST /admin/regras. }
    class function AtivaPorPadrao: Boolean; virtual;

    { Chamado pelo servidor ao adotar a regra; nao chame. }
    procedure Anexar(const ASimulador: TDFeSimuladorSefaz);

    function AntesDeAtender(const ARequisicao: TDFeSimRequisicao;
      var AResposta: TDFeSimHttpResposta): Boolean; virtual;
    procedure DepoisDeAtender(const ARequisicao: TDFeSimRequisicao;
      var AResposta: TDFeSimHttpResposta); virtual;
    function TratarRota(const ARequisicao: TDFeSimRequisicao;
      var AResposta: TDFeSimHttpResposta): Boolean; virtual;
    procedure AoZerar; virtual;

    property Ativa: Boolean read FAtiva write FAtiva;
  end;

  TDFeSimuladorRegraClasse = class of TDFeSimuladorRegra;
  TDFeSimuladorRegraClasseArray = array of TDFeSimuladorRegraClasse;

{ Registro global de CLASSES (chamado do initialization da unit da regra). Levanta
  excecao para Nome vazio ou repetido. }
procedure RegistrarRegraSimulador(const AClasse: TDFeSimuladorRegraClasse);
function RegrasSimuladorRegistradas: TDFeSimuladorRegraClasseArray;
{ So' para teste: esvazia o registro (quem chama restaura o que havia). }
procedure LimparRegrasSimuladorRegistradas;

{ Ajudas para quem escreve regra. }

{ Resposta de Distribuicao (envelope SOAP) para o lote dado. ATpAmb = '1' ou '2'
  (o que veio no request: ExtrairTag(Corpo, 'tpAmb')). }
function RespostaSoapDeDistribuicao(const ALote: TDFeRespostaSimulada;
  const ATpAmb: string): TDFeSimHttpResposta;
{ Um lote SEM documentos com o cStat/xMotivo dados (108, 656...), como o nucleo
  monta as suas rejeicoes. }
function LoteRejeitado(const ACStat: Integer; const AXMotivo: string): TDFeRespostaSimulada;
{ Resposta JSON de uma rota /ext/. }
function RespostaJson(const AStatus: Integer; const ACorpo: string): TDFeSimHttpResposta;

implementation

uses
  DFe.XmlTexto;

var
  GRegistradas: TDFeSimuladorRegraClasseArray;

constructor TDFeSimuladorRegra.Create;
begin
  inherited Create;
  FAtiva := AtivaPorPadrao;
end;

class function TDFeSimuladorRegra.Descricao: string;
begin
  Result := '';
end;

class function TDFeSimuladorRegra.AtivaPorPadrao: Boolean;
begin
  Result := True;
end;

procedure TDFeSimuladorRegra.Anexar(const ASimulador: TDFeSimuladorSefaz);
begin
  FSimulador := ASimulador;
end;

function TDFeSimuladorRegra.AntesDeAtender(const ARequisicao: TDFeSimRequisicao;
  var AResposta: TDFeSimHttpResposta): Boolean;
begin
  Result := False;
end;

procedure TDFeSimuladorRegra.DepoisDeAtender(const ARequisicao: TDFeSimRequisicao;
  var AResposta: TDFeSimHttpResposta);
begin
end;

function TDFeSimuladorRegra.TratarRota(const ARequisicao: TDFeSimRequisicao;
  var AResposta: TDFeSimHttpResposta): Boolean;
begin
  Result := False;
end;

procedure TDFeSimuladorRegra.AoZerar;
begin
end;

procedure RegistrarRegraSimulador(const AClasse: TDFeSimuladorRegraClasse);
var
  I: Integer;
  LNome: string;
begin
  LNome := AClasse.Nome;
  if LNome = '' then
    raise Exception.Create('Regra de simulador sem Nome: ' + AClasse.ClassName);
  for I := 0 to High(GRegistradas) do
    if SameText(GRegistradas[I].Nome, LNome) then
      raise Exception.Create('Ja existe uma regra de simulador registrada com o nome "' +
        LNome + '"');
  SetLength(GRegistradas, Length(GRegistradas) + 1);
  GRegistradas[High(GRegistradas)] := AClasse;
end;

function RegrasSimuladorRegistradas: TDFeSimuladorRegraClasseArray;
var
  I: Integer;
begin
  SetLength(Result, Length(GRegistradas));
  for I := 0 to High(GRegistradas) do
    Result[I] := GRegistradas[I];
end;

procedure LimparRegrasSimuladorRegistradas;
begin
  SetLength(GRegistradas, 0);
end;

function LoteRejeitado(const ACStat: Integer; const AXMotivo: string): TDFeRespostaSimulada;
begin
  Result.Tipo := trsLote;
  Result.DocZipCorrompido := False;
  Result.Lote.CStat := ACStat;
  Result.Lote.XMotivo := AXMotivo;
  Result.Lote.UltimoNSU := 0;
  Result.Lote.MaxNSU := 0;
  Result.Lote.Itens := nil;
end;

function RespostaSoapDeDistribuicao(const ALote: TDFeRespostaSimulada;
  const ATpAmb: string): TDFeSimHttpResposta;
var
  LTpAmb: string;
begin
  LTpAmb := ATpAmb;
  if (LTpAmb <> '1') and (LTpAmb <> '2') then
    LTpAmb := '2';
  Result.Status := 200;
  Result.ContentType := DFE_SIM_CONTENT_TYPE_SOAP;
  // o adaptador SOAP fala a convencao do ACBr; pela rede vai o texto de verdade
  Result.Corpo := TextoDoAcbr(MontarEnvelopeResposta(ALote, LTpAmb));
end;

function RespostaJson(const AStatus: Integer; const ACorpo: string): TDFeSimHttpResposta;
begin
  Result.Status := AStatus;
  Result.ContentType := DFE_SIM_CONTENT_TYPE_JSON;
  Result.Corpo := ACorpo;
end;

end.
