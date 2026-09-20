unit DFe.Simulador.Exemplo.LimiteConsultas;

// Sem o include dfe.inc: o exemplo mora fora de src/ e so' precisa do modo Delphi.
{$IFDEF FPC}
  {$MODE DELPHI}{$H+}
{$ENDIF}

(* EXEMPLO DE EXTENSAO do simulador (docs/simulador-standalone.md, Fase C): uma
  regra que o core NAO tem, escrita sem alterar o core.

  O que o core faz: bloqueia um CNPJ por 1 h depois de uma consulta sem novidade
  (137). O que esta regra acrescenta: uma politica de TAXA -- no maximo N
  consultas por CNPJ numa janela de S segundos; a partir da (N+1)-esima, a
  Distribuicao responde consumo indevido (656) SEM tocar no nucleo (nao consome
  NSU, nao abre bloqueio). Serve para testar como o SEU cliente reage a ser
  barrado por excesso de chamadas, coisa que a SEFAZ real pode fazer e que o
  bloqueio de 1 h do core nao reproduz.

  Mostra, num arquivo so', cada ponto de extensao:
  - AntesDeAtender: le o request (CNPJ, tpAmb) e responde no lugar do nucleo;
  - o RELOGIO do simulador (ARequisicao.Agora): a janela anda com o relogio
    virtual (POST /admin/relogio/avancar), sem esperar de verdade;
  - estado proprio da regra (um por servidor) e AoZerar para limpa-lo;
  - rota propria: GET /ext/limite (estado) e POST /ext/limite (ajusta o limite);
  - registro por initialization (esta unit, ao entrar no programa, se registra).

  NAO E' O COMPORTAMENTO DA SEFAZ: e' uma politica inventada, para demonstrar a
  extensao. A regra nasce LIGADA; desligue com
  POST /admin/regras {"nome":"limite-consultas","ativa":false}. *)

interface

uses
  SysUtils,
  DFe.Simulador,
  DFe.Simulador.Admin,
  DFe.Simulador.Regras;

const
  LIMITE_PADRAO = 3;
  JANELA_PADRAO_SEGUNDOS = 600;

type
  TConsultaRegistrada = record
    Cnpj: string;
    Instante: TDateTime;
  end;

  TRegraLimiteConsultas = class(TDFeSimuladorRegra)
  private
    FMaximo: Integer;
    FJanelaSegundos: Integer;
    FConsultas: array of TConsultaRegistrada;
    FRejeitadas: Integer;
    procedure Podar(const AAgora: TDateTime);
    function ContarDoCnpj(const ACnpj: string): Integer;
    function JsonDoEstado: string;
    function AjustarLimite(const ACorpo: string): TDFeSimHttpResposta;
  public
    constructor Create; override;

    class function Nome: string; override;
    class function Descricao: string; override;

    function AntesDeAtender(const ARequisicao: TDFeSimRequisicao;
      var AResposta: TDFeSimHttpResposta): Boolean; override;
    function TratarRota(const ARequisicao: TDFeSimRequisicao;
      var AResposta: TDFeSimHttpResposta): Boolean; override;
    procedure AoZerar; override;

    property Maximo: Integer read FMaximo;
    property JanelaSegundos: Integer read FJanelaSegundos;
    property Rejeitadas: Integer read FRejeitadas;
  end;

implementation

uses
  DFe.Simulador.Soap,
  DFe.Simulador.Json;

constructor TRegraLimiteConsultas.Create;
begin
  inherited Create;
  FMaximo := LIMITE_PADRAO;
  FJanelaSegundos := JANELA_PADRAO_SEGUNDOS;
end;

class function TRegraLimiteConsultas.Nome: string;
begin
  Result := 'limite-consultas';
end;

class function TRegraLimiteConsultas.Descricao: string;
begin
  Result := 'exemplo: no maximo N consultas por CNPJ numa janela; acima disso, 656';
end;

{ Esquece as consultas fora da janela. Um instante NO FUTURO tambem sai: significa
  que o relogio virtual voltou (POST /admin/relogio/zerar). }
procedure TRegraLimiteConsultas.Podar(const AAgora: TDateTime);
var
  I, N: Integer;
  LInicio: TDateTime;
begin
  LInicio := AAgora - FJanelaSegundos / SecsPerDay;
  N := 0;
  for I := 0 to High(FConsultas) do
    if (FConsultas[I].Instante > LInicio) and (FConsultas[I].Instante <= AAgora) then
    begin
      FConsultas[N] := FConsultas[I];
      Inc(N);
    end;
  SetLength(FConsultas, N);
end;

function TRegraLimiteConsultas.ContarDoCnpj(const ACnpj: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FConsultas) do
    if FConsultas[I].Cnpj = ACnpj then
      Inc(Result);
end;

function TRegraLimiteConsultas.AntesDeAtender(const ARequisicao: TDFeSimRequisicao;
  var AResposta: TDFeSimHttpResposta): Boolean;
var
  LCnpj: string;
begin
  Result := False;
  if ARequisicao.Servico <> ssDistribuicao then
    Exit;
  LCnpj := ExtrairTag(ARequisicao.Corpo, 'CNPJ');
  if LCnpj = '' then
    Exit; // request estranho: deixa o adaptador SOAP registrar a violacao

  Podar(ARequisicao.Agora);
  if ContarDoCnpj(LCnpj) >= FMaximo then
  begin
    Inc(FRejeitadas);
    AResposta := RespostaSoapDeDistribuicao(
      LoteRejeitado(Simulador.CodigoConsumoIndevido,
        'Rejeicao: Consumo Indevido (limite de ' + IntToStr(FMaximo) + ' consulta(s) em ' +
        IntToStr(FJanelaSegundos) + ' s)'),
      ExtrairTag(ARequisicao.Corpo, 'tpAmb'));
    Result := True;
    Exit;
  end;

  SetLength(FConsultas, Length(FConsultas) + 1);
  FConsultas[High(FConsultas)].Cnpj := LCnpj;
  FConsultas[High(FConsultas)].Instante := ARequisicao.Agora;
end;

function TRegraLimiteConsultas.JsonDoEstado: string;
var
  I, K: Integer;
  LVistos: array of string;
  LLista, LCnpj: string;
  LJa: Boolean;
begin
  LLista := '';
  for I := 0 to High(FConsultas) do
  begin
    LCnpj := FConsultas[I].Cnpj;
    LJa := False;
    for K := 0 to High(LVistos) do
      if LVistos[K] = LCnpj then
        LJa := True;
    if LJa then
      Continue;
    SetLength(LVistos, Length(LVistos) + 1);
    LVistos[High(LVistos)] := LCnpj;
    if LLista <> '' then
      LLista := LLista + ',';
    LLista := LLista + '{"cnpj":' + JsonTexto(LCnpj) + ',"consultasNaJanela":' +
      IntToStr(ContarDoCnpj(LCnpj)) + '}';
  end;
  Result := '{"maximo":' + IntToStr(FMaximo) + ',"janelaSegundos":' + IntToStr(FJanelaSegundos) +
    ',"rejeitadas":' + IntToStr(FRejeitadas) + ',"contas":[' + LLista + ']}';
end;

function TRegraLimiteConsultas.AjustarLimite(const ACorpo: string): TDFeSimHttpResposta;
var
  LJson: TDFeJsonPlano;
  LErro: string;
  LMaximo, LJanela: Int64;
begin
  if not LerJsonPlano(ACorpo, LJson, LErro) then
  begin
    Result := RespostaJson(400, '{"erro":' + JsonTexto('JSON invalido: ' + LErro) + '}');
    Exit;
  end;
  try
    if (LJson.Tem('maximo') and not LJson.EInteiro('maximo')) or
       (LJson.Tem('janelaSegundos') and not LJson.EInteiro('janelaSegundos')) then
    begin
      Result := RespostaJson(400, '{"erro":"maximo e janelaSegundos devem ser inteiros"}');
      Exit;
    end;
    LMaximo := LJson.Inteiro('maximo', FMaximo);
    LJanela := LJson.Inteiro('janelaSegundos', FJanelaSegundos);
    if (LMaximo < 1) or (LMaximo > 100000) or (LJanela < 1) or (LJanela > 86400) then
    begin
      Result := RespostaJson(400,
        '{"erro":"maximo entre 1 e 100000; janelaSegundos entre 1 e 86400"}');
      Exit;
    end;
    FMaximo := Integer(LMaximo);
    FJanelaSegundos := Integer(LJanela);
    Result := RespostaJson(200, JsonDoEstado);
  finally
    LJson.Free;
  end;
end;

function TRegraLimiteConsultas.TratarRota(const ARequisicao: TDFeSimRequisicao;
  var AResposta: TDFeSimHttpResposta): Boolean;
var
  LCaminho: string;
  I: Integer;
begin
  LCaminho := LowerCase(ARequisicao.Caminho);
  I := Pos('?', LCaminho);
  if I > 0 then
    LCaminho := Copy(LCaminho, 1, I - 1);
  while (Length(LCaminho) > 1) and (LCaminho[Length(LCaminho)] = '/') do
    Delete(LCaminho, Length(LCaminho), 1);

  Result := LCaminho = CAMINHO_EXTENSAO + 'limite';
  if not Result then
    Exit;
  if SameText(ARequisicao.Metodo, 'GET') then
  begin
    Podar(ARequisicao.Agora);
    AResposta := RespostaJson(200, JsonDoEstado);
  end
  else if SameText(ARequisicao.Metodo, 'POST') then
    AResposta := AjustarLimite(ARequisicao.Corpo)
  else
    AResposta := RespostaJson(405, '{"erro":"metodo nao permitido para esta rota"}');
end;

procedure TRegraLimiteConsultas.AoZerar;
begin
  SetLength(FConsultas, 0);
  FRejeitadas := 0;
  FMaximo := LIMITE_PADRAO;
  FJanelaSegundos := JANELA_PADRAO_SEGUNDOS;
end;

initialization
  RegistrarRegraSimulador(TRegraLimiteConsultas);

end.
