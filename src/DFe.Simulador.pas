unit DFe.Simulador;

{$I dfe.inc}

{ Nucleo do simulador da SEFAZ para a Distribuicao de DFe -- ver
  docs/simulador-sefaz.md, Fase 2.

  PURO e independente de transporte: decide O QUE a SEFAZ responderia
  (regras de NSU, janela de 1h, paginacao, falhas roteirizadas) e devolve
  isso como dado (TDFeRespostaSimulada). Nao sabe de SOAP, HTTP, ACBr nem
  de excecoes do projeto. Cada "casa" traduz o resultado para o seu
  transporte: DFe.Simulador.Client (IDFeDistribuicaoClient, camada 1) e,
  na Fase 3, um adaptador SOAP para TACBrDFe.OnTransmit (camada 2).

  Regras -- todas conferidas contra as NTs oficiais (docs/referencias/
  README.md), nenhuma "inventada" aqui:
  - lote de ate 50 documentos;
  - cStat 137 (nada novo) inicia um bloqueio de 1 HORA por CNPJ/UF; uma
    consulta dentro dele recebe consumo indevido (656 por padrao, 678 em
    MDF-e -- CodigoConsumoIndevido) e NAO estende nem escalona o bloqueio;
  - cStat 138 com mais documentos pendentes NAO bloqueia (pode consultar
    de novo na hora, e' assim que se pagina);
  - o NSU pertence ao CNPJ/UF, nao ao certificado.

  Limite conhecido (risco de espelho, ver o plano): isto codifica a NOSSA
  leitura das NTs. Um erro de leitura aqui e' replicado nos testes. Ponto
  em aberto documentado: se a SEFAZ real reinicia o bloqueio a cada
  consulta rejeitada -- a NT nao diz; aqui NAO reinicia.

  Relogio injetavel (mesmo padrao de TDFeOrquestrador.Agora): nenhum
  Sleep, nenhum tempo real. Nao e' thread-safe -- uso sequencial de teste. }

interface

uses
  SysUtils,
  DFe.Types;

const
  DFE_SIM_MAX_DOCS_POR_LOTE = 50;
  DFE_SIM_BLOQUEIO_SEGUNDOS = 3600;
  DFE_SIM_CSTAT_CONSUMO_INDEVIDO_PADRAO = 656;

type
  TDFeAgoraFunc = function: TDateTime of object;

  { Falhas que o teste enfileira para as PROXIMAS consultas (uma por
    consulta, na ordem). Cada uma consome uma consulta e, exceto
    fsDocZipCorrompido, NAO altera o estado da conta (a SEFAZ "nem
    processou"). }
  TDFeFalhaSimulada = (
    fsIndisponivelCurtoPrazo,   // cStat 108
    fsIndisponivelSemPrevisao,  // cStat 109
    fsConsumoIndevido,          // forca o cStat de consumo indevido mesmo fora do bloqueio
    fsTimeout,                  // sem resposta: o transporte traduz (ACBr: InternalErrorCode 10060)
    fsErroHttp,                 // HTTP 500 / erro de transporte
    fsCorpoIlegivel,            // HTTP 200 com corpo que nao e' o envelope esperado
    fsDocZipCorrompido,         // processa normal, mas o gzip do 1o docZip sai invalido
    { Falhas SO' de RecepcaoEvento (ReceberEvento) -- levantam excecao se
      forem consumidas por Consultar, e vice-versa para as de distribuicao
      que nao se aplicam a evento (fsConsumoIndevido, fsDocZipCorrompido):
      um teste que enfileira a falha errada tem que saber na hora. }
    fsEventoRejeitado,          // lote 128, mas o evento sai rejeitado (cStat 999, generico)
    fsLoteEventoRejeitado       // o proprio lote e' rejeitado (cStat 999), sem retEvento
  );

  TDFeTipoRespostaSimulada = (trsLote, trsTimeout, trsErroHttp, trsCorpoIlegivel);

  TDFeRespostaSimulada = record
    Tipo: TDFeTipoRespostaSimulada;
    { Valido so' quando Tipo = trsLote. Itens ja com XML descompactado
      (mesmo formato que o client real entrega); quem monta o envelope
      SOAP recompacta. }
    Lote: TDFeLoteBruto;
    { So' faz sentido com Itens: o transporte deve corromper o gzip do
      primeiro docZip. }
    DocZipCorrompido: Boolean;
  end;

  { Resposta a UM evento de manifestacao (RecepcaoEvento com lote de um
    evento -- e' assim que o client real envia). Tipo <> trsLote = falha de
    transporte, sem resposta interpretavel. }
  TDFeRespostaEventoSimulada = record
    Tipo: TDFeTipoRespostaSimulada;
    CStatLote: Integer;       // 128 = lote processado
    XMotivoLote: string;
    TemEvento: Boolean;       // False quando o proprio lote foi rejeitado/indisponivel
    CStat: Integer;           // do evento: 135 registrado; demais = rejeicao
    XMotivo: string;
    NProt: string;            // so' quando registrado
    DhRegEvento: TDateTime;
  end;

  TDFeSimDocumento = record
    NSU: Int64;
    Schema: string;
    Xml: string;
  end;

  { Estado de um CNPJ/UF. Publica so' porque o array precisa de tipo
    nomeado na interface; nao e' API para uso externo. }
  TDFeSimConta = class
  public
    Chave: string;
    NsuAtual: Int64;                 // maior NSU ja atribuido (= maxNSU)
    Documentos: array of TDFeSimDocumento;
    BloqueadoAte: TDateTime;         // 0 = livre
  end;

  TDFeSimuladorSefaz = class
  private
    FAgora: TDFeAgoraFunc;
    FCodigoConsumoIndevido: Integer;
    FContas: array of TDFeSimConta;
    FFalhas: array of TDFeFalhaSimulada;
    FTotalConsultas: Integer;
    FUltimoNSURecebido: Int64;
    FTotalEventos: Integer;
    FEventosRegistrados: array of string; // 'chave|tpEvento|nSeq'
    function ChaveConhecida(const ACnpjCpf, AChave: string): Boolean;
    function ObterConta(const ACnpjCpf, AUF: string): TDFeSimConta;
    function AgoraAtual: TDateTime;
    function ProximaFalha(out AFalha: TDFeFalhaSimulada): Boolean;
    function LoteSemDocumentos(const ACStat: Integer; const AXMotivo: string;
      const AUltimoNSU, AMaxNSU: Int64): TDFeLoteBruto;
  public
    { AAgora nil = relogio real (Now). Em teste, ligar ao mesmo valor
      simulado que o orquestrador usa. }
    constructor Create(const AAgora: TDFeAgoraFunc = nil);
    destructor Destroy; override;

    { Acrescenta um documento ao CNPJ/UF e devolve o NSU atribuido
      (sequencial, comecando em 1). }
    function PublicarDocumento(const ACnpjCpf, AUF, ASchema, AXml: string): Int64;

    { Avanca o contador de NSU sem documento algum -- reproduz o "salto
      de NSU" (numeros que a SEFAZ atribuiu mas nao entrega a este CNPJ). }
    procedure PularNSU(const ACnpjCpf, AUF: string; const AQuantidade: Integer);

    procedure EnfileirarFalha(const AFalha: TDFeFalhaSimulada);

    function Consultar(const ACnpjCpf, AUF: string; const AUltimoNSU: Int64): TDFeRespostaSimulada;

    { Manifestacao do destinatario (RecepcaoEvento do Ambiente Nacional).
      Regras, na ordem: falha enfileirada; chave que este CNPJ nao ve nos
      documentos publicados -> rejeicao 494; mesmo (chave, tpEvento,
      nSeqEvento) ja registrado -> rejeicao 573; senao registra (135) e
      atribui um protocolo. Os cStat 494 e 573 vem do Manual de Orientacao
      do Contribuinte, que NAO tem copia em docs/referencias -- conferir
      antes de tratar como definitivos. A assinatura/forma do XML NAO e'
      julgada aqui (e' assunto do transporte: DFe.Simulador.Soap). }
    function ReceberEvento(const ACnpjDest, AChave, ATpEvento: string;
      const ANSeq: Integer): TDFeRespostaEventoSimulada;

    { Maior NSU atribuido ao CNPJ/UF (0 se nunca houve). }
    function NsuAtual(const ACnpjCpf, AUF: string): Int64;

    { Codigo de "consumo indevido" do tipo de documento simulado: 656 em
      NFe/CT-e (padrao), 678 em MDF-e. }
    property CodigoConsumoIndevido: Integer read FCodigoConsumoIndevido write FCodigoConsumoIndevido;
    { Quantas vezes Consultar foi chamado (inclui as que receberam falha
      ou consumo indevido). }
    property TotalConsultas: Integer read FTotalConsultas;
    property UltimoNSURecebido: Int64 read FUltimoNSURecebido;
    { Quantas vezes ReceberEvento foi chamado / quantos eventos foram
      registrados (135). }
    property TotalEventos: Integer read FTotalEventos;
    function EventosRegistrados: Integer;
  end;

implementation

{ TDFeSimuladorSefaz }

constructor TDFeSimuladorSefaz.Create(const AAgora: TDFeAgoraFunc);
begin
  inherited Create;
  FAgora := AAgora;
  FCodigoConsumoIndevido := DFE_SIM_CSTAT_CONSUMO_INDEVIDO_PADRAO;
end;

destructor TDFeSimuladorSefaz.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(FContas) do
    FContas[I].Free;
  inherited Destroy;
end;

function TDFeSimuladorSefaz.AgoraAtual: TDateTime;
begin
  if Assigned(FAgora) then
    Result := FAgora()
  else
    Result := Now;
end;

function TDFeSimuladorSefaz.ObterConta(const ACnpjCpf, AUF: string): TDFeSimConta;
var
  I: Integer;
  LChave: string;
begin
  LChave := ACnpjCpf + '/' + UpperCase(AUF);
  for I := 0 to High(FContas) do
    if FContas[I].Chave = LChave then
    begin
      Result := FContas[I];
      Exit;
    end;
  Result := TDFeSimConta.Create;
  Result.Chave := LChave;
  SetLength(FContas, Length(FContas) + 1);
  FContas[High(FContas)] := Result;
end;

function TDFeSimuladorSefaz.ProximaFalha(out AFalha: TDFeFalhaSimulada): Boolean;
var
  I: Integer;
begin
  Result := Length(FFalhas) > 0;
  if not Result then
    Exit;
  AFalha := FFalhas[0];
  for I := 1 to High(FFalhas) do
    FFalhas[I - 1] := FFalhas[I];
  SetLength(FFalhas, Length(FFalhas) - 1);
end;

function TDFeSimuladorSefaz.LoteSemDocumentos(const ACStat: Integer;
  const AXMotivo: string; const AUltimoNSU, AMaxNSU: Int64): TDFeLoteBruto;
begin
  Result.CStat := ACStat;
  Result.XMotivo := AXMotivo;
  Result.UltimoNSU := AUltimoNSU;
  Result.MaxNSU := AMaxNSU;
  Result.Itens := nil;
end;

function TDFeSimuladorSefaz.PublicarDocumento(const ACnpjCpf, AUF, ASchema, AXml: string): Int64;
var
  LConta: TDFeSimConta;
  N: Integer;
begin
  LConta := ObterConta(ACnpjCpf, AUF);
  Inc(LConta.NsuAtual);
  N := Length(LConta.Documentos);
  SetLength(LConta.Documentos, N + 1);
  LConta.Documentos[N].NSU := LConta.NsuAtual;
  LConta.Documentos[N].Schema := ASchema;
  LConta.Documentos[N].Xml := AXml;
  Result := LConta.NsuAtual;
end;

procedure TDFeSimuladorSefaz.PularNSU(const ACnpjCpf, AUF: string; const AQuantidade: Integer);
begin
  Inc(ObterConta(ACnpjCpf, AUF).NsuAtual, AQuantidade);
end;

procedure TDFeSimuladorSefaz.EnfileirarFalha(const AFalha: TDFeFalhaSimulada);
begin
  SetLength(FFalhas, Length(FFalhas) + 1);
  FFalhas[High(FFalhas)] := AFalha;
end;

function TDFeSimuladorSefaz.NsuAtual(const ACnpjCpf, AUF: string): Int64;
begin
  Result := ObterConta(ACnpjCpf, AUF).NsuAtual;
end;

function TDFeSimuladorSefaz.Consultar(const ACnpjCpf, AUF: string;
  const AUltimoNSU: Int64): TDFeRespostaSimulada;
var
  LConta: TDFeSimConta;
  LFalha: TDFeFalhaSimulada;
  LTemFalha: Boolean;
  LAgora: TDateTime;
  I, N: Integer;
begin
  Inc(FTotalConsultas);
  FUltimoNSURecebido := AUltimoNSU;

  Result.Tipo := trsLote;
  Result.DocZipCorrompido := False;
  LConta := ObterConta(ACnpjCpf, AUF);
  LAgora := AgoraAtual;

  LFalha := fsTimeout; // so' para silenciar "nao inicializada"; LTemFalha decide
  LTemFalha := ProximaFalha(LFalha);
  if LTemFalha then
    case LFalha of
      fsTimeout:
        begin
          Result.Tipo := trsTimeout;
          Exit;
        end;
      fsErroHttp:
        begin
          Result.Tipo := trsErroHttp;
          Exit;
        end;
      fsCorpoIlegivel:
        begin
          Result.Tipo := trsCorpoIlegivel;
          Exit;
        end;
      fsIndisponivelCurtoPrazo:
        begin
          Result.Lote := LoteSemDocumentos(108,
            'Servico Paralisado Momentaneamente (curto prazo)', 0, 0);
          Exit;
        end;
      fsIndisponivelSemPrevisao:
        begin
          Result.Lote := LoteSemDocumentos(109,
            'Servico Paralisado sem Previsao', 0, 0);
          Exit;
        end;
      fsConsumoIndevido:
        begin
          Result.Lote := LoteSemDocumentos(FCodigoConsumoIndevido,
            'Rejeicao: Consumo Indevido (simulado)', 0, 0);
          Exit;
        end;
      fsEventoRejeitado, fsLoteEventoRejeitado:
        raise Exception.Create('Falha simulada so'' vale para ReceberEvento, nao para Consultar');
    end;

  { Bloqueio de 1h aberto por um 137 anterior. Meio segundo de tolerancia
    absorve o erro de ponto flutuante de TDateTime + 1h. }
  if (LConta.BloqueadoAte > 0) and ((LConta.BloqueadoAte - LAgora) > (0.5 / SecsPerDay)) then
  begin
    Result.Lote := LoteSemDocumentos(FCodigoConsumoIndevido,
      'Rejeicao: Consumo Indevido (aguarde 1 hora)', 0, 0);
    Exit;
  end;

  { Documentos pendentes: NSU > AUltimoNSU, no maximo 50, em ordem. }
  N := 0;
  for I := 0 to High(LConta.Documentos) do
    if (LConta.Documentos[I].NSU > AUltimoNSU) and (N < DFE_SIM_MAX_DOCS_POR_LOTE) then
      Inc(N);

  if N = 0 then
  begin
    Result.Lote := LoteSemDocumentos(137, 'Nenhum documento localizado',
      LConta.NsuAtual, LConta.NsuAtual);
    LConta.BloqueadoAte := LAgora + DFE_SIM_BLOQUEIO_SEGUNDOS / SecsPerDay;
    Exit;
  end;

  Result.Lote := LoteSemDocumentos(138, 'Documento(s) localizado(s)', 0, LConta.NsuAtual);
  SetLength(Result.Lote.Itens, N);
  N := 0;
  for I := 0 to High(LConta.Documentos) do
    if (LConta.Documentos[I].NSU > AUltimoNSU) and (N < DFE_SIM_MAX_DOCS_POR_LOTE) then
    begin
      Result.Lote.Itens[N].NSU := LConta.Documentos[I].NSU;
      Result.Lote.Itens[N].Schema := LConta.Documentos[I].Schema;
      Result.Lote.Itens[N].XmlDecodificado := LConta.Documentos[I].Xml;
      Result.Lote.UltimoNSU := LConta.Documentos[I].NSU;
      Inc(N);
    end;

  Result.DocZipCorrompido := LTemFalha and (LFalha = fsDocZipCorrompido);
end;


function TDFeSimuladorSefaz.EventosRegistrados: Integer;
begin
  Result := Length(FEventosRegistrados);
end;

function TDFeSimuladorSefaz.ChaveConhecida(const ACnpjCpf, AChave: string): Boolean;
var
  I, J: Integer;
  LPrefixo: string;
begin
  Result := False;
  LPrefixo := ACnpjCpf + '/';
  for I := 0 to High(FContas) do
    if Copy(FContas[I].Chave, 1, Length(LPrefixo)) = LPrefixo then
      for J := 0 to High(FContas[I].Documentos) do
        if Pos(AChave, FContas[I].Documentos[J].Xml) > 0 then
        begin
          Result := True;
          Exit;
        end;
end;

function TDFeSimuladorSefaz.ReceberEvento(const ACnpjDest, AChave, ATpEvento: string;
  const ANSeq: Integer): TDFeRespostaEventoSimulada;
var
  LFalha: TDFeFalhaSimulada;
  LId: string;
  I: Integer;

  procedure Rejeitar(const ACStat: Integer; const AMotivo: string);
  begin
    Result.CStat := ACStat;
    Result.XMotivo := AMotivo;
  end;

begin
  Inc(FTotalEventos);
  Result.Tipo := trsLote;
  Result.CStatLote := 128;
  Result.XMotivoLote := 'Lote de Evento Processado';
  Result.TemEvento := True;
  Result.CStat := 0;
  Result.XMotivo := '';
  Result.NProt := '';
  Result.DhRegEvento := 0;

  LFalha := fsTimeout; // so' para silenciar "nao inicializada"; o retorno decide
  if ProximaFalha(LFalha) then
    case LFalha of
      fsTimeout:
        begin
          Result.Tipo := trsTimeout;
          Exit;
        end;
      fsErroHttp:
        begin
          Result.Tipo := trsErroHttp;
          Exit;
        end;
      fsCorpoIlegivel:
        begin
          Result.Tipo := trsCorpoIlegivel;
          Exit;
        end;
      fsIndisponivelCurtoPrazo:
        begin
          Result.CStatLote := 108;
          Result.XMotivoLote := 'Servico Paralisado Momentaneamente (curto prazo)';
          Result.TemEvento := False;
          Exit;
        end;
      fsIndisponivelSemPrevisao:
        begin
          Result.CStatLote := 109;
          Result.XMotivoLote := 'Servico Paralisado sem Previsao';
          Result.TemEvento := False;
          Exit;
        end;
      fsLoteEventoRejeitado:
        begin
          Result.CStatLote := 999;
          Result.XMotivoLote := 'Rejeicao: lote de evento rejeitado (simulado)';
          Result.TemEvento := False;
          Exit;
        end;
      fsEventoRejeitado:
        begin
          Rejeitar(999, 'Rejeicao: evento rejeitado (simulado)');
          Exit;
        end;
    else
      raise Exception.Create('Falha simulada so'' vale para Consultar, nao para ReceberEvento');
    end;

  Result.DhRegEvento := AgoraAtual;

  if not ChaveConhecida(ACnpjDest, AChave) then
  begin
    Rejeitar(494, 'Rejeicao: Chave de Acesso inexistente');
    Result.DhRegEvento := 0;
    Exit;
  end;

  LId := AChave + '|' + ATpEvento + '|' + IntToStr(ANSeq);
  for I := 0 to High(FEventosRegistrados) do
    if FEventosRegistrados[I] = LId then
    begin
      Rejeitar(573, 'Rejeicao: Duplicidade de evento');
      Result.DhRegEvento := 0;
      Exit;
    end;

  SetLength(FEventosRegistrados, Length(FEventosRegistrados) + 1);
  FEventosRegistrados[High(FEventosRegistrados)] := LId;
  Rejeitar(135, 'Evento registrado e vinculado a NF-e');
  Result.NProt := '891' + Format('%.12d', [Length(FEventosRegistrados)]);
end;

end.
