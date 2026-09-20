unit DFe.AcbrSimHttpTests;

{ O client ACBr REAL contra o simulador da SEFAZ rodando como PROCESSO
  SEPARADO, por HTTP (docs/simulador-standalone.md, Fase A): o
  TDFeTransmissorHttp leva o envelope ao executavel simulador/DFeSimulador, que
  responde pelo mesmo nucleo dos testes em processo (DFe.AcbrSimTests). Aqui o
  que e' novo e so' um teste assim pega: o HTTP de verdade (cabecalhos, corpo,
  codigos de status, conexao recusada) e o caminho completo
  broker -> rede -> simulador.

  Cada teste sobe o executavel numa porta propria com um cenario que ele mesmo
  escreve (a API admin so' chega na Fase B) e o derruba no TearDown.

  REQUISITO: compilar antes  lazbuild simulador\DFeSimulador.lpi  (em Windows
  precisa antes de  sh simulador/preparar-horse.sh ). Sem o executavel o teste
  FALHA (nao ignora) dizendo isso. }

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils, Classes, Process, fphttpclient,
  ACBrDFe.Conversao,
  ACBrLibXml2Ext,
  DFe.Types,
  DFe.Errors,
  DFe.Provider,
  DFe.Manifestacao,
  DFe.Provider.NFe,
  DFe.Simulador.Fixtures,
  DFe.Transmissor,
  DFe.Transmissor.Http,
  DFe.Transmissor.Http.Cliente,
  DFe.Client.ACBrNFe;

type
  TDFeAcbrSimHttpTests = class(TTestCase)
  private
    FProcesso: TProcess;
    FPorta: Integer;
    FCenario: string;
    function DiretorioBase: string;
    function CaminhoDoSimulador: string;
    { O exemplo de extensao (simulador/exemplos/limite-consultas): na pasta dele
      (Windows) ou ao lado do DFeSimulador (Linux, tools/docker/testar-linux.sh). }
    function CaminhoDoExemplo: string;
    function Certificado: TDFeCertificado;
    procedure IniciarSimulador(const ALinhasDoCenario: array of string;
      const AExecutavel: string = '');
    function NovoClient(const ABaseURL: string; const ATimeoutMs: Integer = 10000): IDFeDistribuicaoClient;
    function ClientDoSimulador: IDFeDistribuicaoClient;
    function ViolacoesDoSimulador: string;
    function PathSchemasDoClient: string;
    function UltimoEnvelopeDoSimulador: string;
    { Chama a API admin (ou qualquer rota) do simulador; devolve o corpo e o status HTTP. }
    function Chamar(const AMetodo, ACaminho, ACorpo: string; out AStatus: Integer): string;
    function Admin(const AMetodo, ACaminho: string; const ACorpo: string = ''): string;
    function EnvelopeDeDistribuicao: string;
    { Manifestacao assina e valida o XML: precisa de libxml2 e dos XSDs oficiais;
      sem eles o teste e' IGNORADO (e contado), como em DFe.AcbrSimEventoTests. }
    procedure ExigirAmbienteDeEvento;
    function DiretorioSchemasDeEvento: string;
  protected
    procedure TearDown; override;
  published
    procedure Consultar137_SemDocumentos;
    procedure Consultar138_DocumentosDoCenario;
    procedure ConsumoIndevido_ELoteComCStat656_NaoExcecao;
    procedure Timeout_ViraComunicacaoFalhou;
    procedure ErroHttp500_ViraComunicacaoFalhou;
    procedure CorpoIlegivel_ViraRespostaInvalida;
    procedure DocZipCorrompido_ViraRespostaInvalida;
    procedure SimuladorForaDoAr_ViraComunicacaoFalhou;
    procedure Admin_PublicaDocumentos_ClienteRecebe;
    procedure Admin_ConsumoIndevido_ReproduzidoEDesfeitoPeloRelogioVirtual;
    procedure Admin_FalhaEnfileirada_ClienteSofre;
    procedure Admin_Violacao_AparecePorHttpELimpa;
    procedure Admin_ModoEstrito_RecusaComHttp400ENaoConsomeNsu;
    procedure Admin_Zerar_VoltaAoInicio;
    procedure Extensao_RegraDoUsuario_BarraOClientPorHttp;
    procedure Manifestacao_Ciencia_RegistradaPorHttp;
    procedure Manifestacao_JustificativaComAcento_ChegaAssinadaEIntactaAoSimulador;
  end;

implementation

const
  CNPJ_CERT = '11222333000181'; // o do certificado sintetico cert-teste\valido.pfx
  SENHA_CERT = 'teste123';
  PORTA_BASE = 9410;

var
  GProximaPorta: Integer = PORTA_BASE;

function TDFeAcbrSimHttpTests.DiretorioBase: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

function TDFeAcbrSimHttpTests.CaminhoDoSimulador: string;
begin
  Result := DiretorioBase + '..' + PathDelim + '..' + PathDelim + '..' + PathDelim +
    'simulador' + PathDelim + 'DFeSimulador' {$IFDEF WINDOWS} + '.exe' {$ENDIF};
end;

function TDFeAcbrSimHttpTests.CaminhoDoExemplo: string;
var
  LBase: string;
begin
  LBase := DiretorioBase + '..' + PathDelim + '..' + PathDelim + '..' + PathDelim + 'simulador' + PathDelim;
  Result := LBase + 'exemplos' + PathDelim + 'limite-consultas' + PathDelim + 'DFeSimuladorLimite'
    {$IFDEF WINDOWS} + '.exe' {$ENDIF};
  if not FileExists(Result) then
    Result := LBase + 'DFeSimuladorLimite' {$IFDEF WINDOWS} + '.exe' {$ENDIF};
end;

function TDFeAcbrSimHttpTests.Certificado: TDFeCertificado;
begin
  Result.Identificador := 'teste';
  Result.CnpjCpf := CNPJ_CERT;
  Result.UF := 'RS';
end;

procedure TDFeAcbrSimHttpTests.IniciarSimulador(const ALinhasDoCenario: array of string;
  const AExecutavel: string);
var
  LExecutavel: string;
  LConteudo: TStringList;
  I, LTentativas: Integer;
  LCliente: TFPHTTPClient;
  LPronto: Boolean;
begin
  if AExecutavel <> '' then
    LExecutavel := AExecutavel
  else
    LExecutavel := CaminhoDoSimulador;
  if not FileExists(LExecutavel) then
    Fail('simulador nao encontrado em ' + ExpandFileName(LExecutavel) +
      ' -- compile antes: lazbuild simulador\DFeSimulador.lpi (Windows: sh simulador/preparar-horse.sh primeiro;' +
      ' o exemplo: lazbuild simulador\exemplos\limite-consultas\DFeSimuladorLimite.lpi)');

  Inc(GProximaPorta);
  FPorta := GProximaPorta;
  FCenario := DiretorioBase + 'sim_http_cenario_' + IntToStr(FPorta) + '.ini';
  LConteudo := TStringList.Create;
  try
    for I := 0 to High(ALinhasDoCenario) do
      LConteudo.Add(ALinhasDoCenario[I]);
    LConteudo.SaveToFile(FCenario);
  finally
    LConteudo.Free;
  end;

  FProcesso := TProcess.Create(nil);
  FProcesso.Executable := ExpandFileName(LExecutavel);
  FProcesso.Parameters.Add('--porta');
  FProcesso.Parameters.Add(IntToStr(FPorta));
  FProcesso.Parameters.Add('--cenario');
  FProcesso.Parameters.Add(FCenario);
  FProcesso.ShowWindow := swoHide;
  FProcesso.Execute;

  // espera o servidor responder (o processo leva alguns centesimos de segundo para subir)
  LPronto := False;
  LTentativas := 0;
  while (not LPronto) and (LTentativas < 100) do
  begin
    Inc(LTentativas);
    LCliente := TFPHTTPClient.Create(nil);
    try
      LCliente.IOTimeout := 500;
      try
        LPronto := LCliente.SimpleGet('http://127.0.0.1:' + IntToStr(FPorta) + '/ping') = 'ok';
      except
        LPronto := False;
      end;
    finally
      LCliente.Free;
    end;
    if not LPronto then
      Sleep(100);
  end;
  AssertTrue('o simulador nao respondeu em 10 s na porta ' + IntToStr(FPorta), LPronto);
end;

procedure TDFeAcbrSimHttpTests.TearDown;
begin
  if Assigned(FProcesso) then
  begin
    if FProcesso.Running then
      FProcesso.Terminate(0);
    FProcesso.WaitOnExit;
    FreeAndNil(FProcesso);
  end;
  if (FCenario <> '') and FileExists(FCenario) then
    DeleteFile(FCenario);
  FCenario := '';
end;

function TDFeAcbrSimHttpTests.NovoClient(const ABaseURL: string;
  const ATimeoutMs: Integer): IDFeDistribuicaoClient;
var
  LCred: TDFeCredencialCertificado;
  LTransmissor: IDFeTransmissor;
  LPost: IDFeHttpPost;
begin
  LCred.ArquivoPFX := DiretorioBase + 'cert-teste' + PathDelim + 'valido.pfx';
  LCred.Senha := SENHA_CERT;
  LCred.PathSchemas := PathSchemasDoClient;
  AssertTrue('certificado de teste nao encontrado: ' + LCred.ArquivoPFX, FileExists(LCred.ArquivoPFX));
  LPost := TDFeHttpPostPadrao.Create(ATimeoutMs);
  LTransmissor := TDFeTransmissorHttp.Create(ABaseURL, LPost);
  Result := TDFeDistribuicaoClientACBrNFe.Create(LCred, taHomologacao, LTransmissor);
end;

function TDFeAcbrSimHttpTests.ClientDoSimulador: IDFeDistribuicaoClient;
begin
  Result := NovoClient('http://127.0.0.1:' + IntToStr(FPorta));
end;

function TDFeAcbrSimHttpTests.ViolacoesDoSimulador: string;
var
  LCliente: TFPHTTPClient;
begin
  LCliente := TFPHTTPClient.Create(nil);
  try
    Result := LCliente.SimpleGet('http://127.0.0.1:' + IntToStr(FPorta) + '/admin/violacoes');
  finally
    LCliente.Free;
  end;
end;

function TDFeAcbrSimHttpTests.DiretorioSchemasDeEvento: string;
begin
  Result := ExpandFileName(DiretorioBase + '..' + PathDelim + '..' + PathDelim + '..' + PathDelim +
    'vendor' + PathDelim + 'ACBr' + PathDelim + 'Exemplos' + PathDelim + 'ACBrDFe' + PathDelim +
    'Schemas' + PathDelim + 'NFe') + PathDelim;
end;

function TDFeAcbrSimHttpTests.UltimoEnvelopeDoSimulador: string;
var
  LCliente: TFPHTTPClient;
begin
  LCliente := TFPHTTPClient.Create(nil);
  try
    Result := LCliente.SimpleGet('http://127.0.0.1:' + IntToStr(FPorta) + '/admin/ultimo-envelope');
  finally
    LCliente.Free;
  end;
end;

function TDFeAcbrSimHttpTests.Chamar(const AMetodo, ACaminho, ACorpo: string;
  out AStatus: Integer): string;
var
  LCliente: TFPHTTPClient;
  LEnvio, LResposta: TStringStream;
begin
  LCliente := TFPHTTPClient.Create(nil);
  LEnvio := TStringStream.Create(ACorpo);
  LResposta := TStringStream.Create('');
  try
    LCliente.IOTimeout := 5000;
    if ACorpo <> '' then
      LCliente.RequestBody := LEnvio;
    LCliente.HTTPMethod(AMetodo, 'http://127.0.0.1:' + IntToStr(FPorta) + ACaminho, LResposta, []);
    AStatus := LCliente.ResponseStatusCode;
    Result := LResposta.DataString;
  finally
    LResposta.Free;
    LEnvio.Free;
    LCliente.Free;
  end;
end;

function TDFeAcbrSimHttpTests.Admin(const AMetodo, ACaminho, ACorpo: string): string;
var
  LStatus: Integer;
begin
  Result := Chamar(AMetodo, ACaminho, ACorpo, LStatus);
  AssertEquals('status de ' + AMetodo + ' ' + ACaminho + ': ' + Result, 200, LStatus);
end;

{ Requisicao no formato que o ACBr emite (a mesma dos testes puros do adaptador),
  mas SEM a SOAPAction: quem a manda aqui e' um cliente que nao e' o ACBr. }
function TDFeAcbrSimHttpTests.EnvelopeDeDistribuicao: string;
begin
  Result := '<?xml version="1.0" encoding="UTF-8"?><soap12:Envelope ' +
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" ' +
    'xmlns:soap12="http://www.w3.org/2003/05/soap-envelope"><soap12:Body>' +
    '<nfeDistDFeInteresse xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe">' +
    '<nfeDadosMsg><distDFeInt xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.01">' +
    '<tpAmb>2</tpAmb><cUFAutor>43</cUFAutor><CNPJ>' + CNPJ_CERT + '</CNPJ>' +
    '<distNSU><ultNSU>000000000000000</ultNSU></distNSU></distDFeInt></nfeDadosMsg>' +
    '</nfeDistDFeInteresse></soap12:Body></soap12:Envelope>';
end;

function TDFeAcbrSimHttpTests.PathSchemasDoClient: string;
begin
  // Com os XSDs oficiais, a mesma pasta serve a distribuicao e a manifestacao;
  // sem eles, a pasta Schemas\ (placeholder) so' serve a distribuicao.
  if FileExists(DiretorioSchemasDeEvento + 'envEvento_v1.00.xsd') then
    Result := DiretorioSchemasDeEvento
  else
    Result := DiretorioBase + 'Schemas' + PathDelim;
end;

procedure TDFeAcbrSimHttpTests.ExigirAmbienteDeEvento;
begin
  if not FileExists(DiretorioSchemasDeEvento + 'envEvento_v1.00.xsd') then
    Ignore('XSDs oficiais de NFe nao encontrados em ' + DiretorioSchemasDeEvento +
      ' (rode tools/init-acbr-submodule.sh)');
  if not InitLibXml2Interface then
    Ignore('libxml2 nativa nao encontrada -- ver docs/dependencias-runtime.md');
end;

procedure TDFeAcbrSimHttpTests.Consultar137_SemDocumentos;
var
  LClient: IDFeDistribuicaoClient;
  LLote: TDFeLoteBruto;
begin
  IniciarSimulador(['[conta:a]', 'Cnpj=' + CNPJ_CERT, 'UF=RS']);
  LClient := ClientDoSimulador;
  LLote := LClient.Consultar(Certificado, 0);
  AssertEquals(137, LLote.CStat);
  AssertEquals(0, Length(LLote.Itens));
  AssertEquals('o request do ACBr nao deve violar o formato', '(nenhuma)', ViolacoesDoSimulador);
end;

procedure TDFeAcbrSimHttpTests.Consultar138_DocumentosDoCenario;
var
  LClient: IDFeDistribuicaoClient;
  LLote: TDFeLoteBruto;
begin
  IniciarSimulador(['[conta:a]', 'Cnpj=' + CNPJ_CERT, 'UF=RS', 'ResNFe=3', 'ProcNFe=1']);
  LClient := ClientDoSimulador;
  LLote := LClient.Consultar(Certificado, 0);
  AssertEquals(138, LLote.CStat);
  AssertEquals(4, Length(LLote.Itens));
  AssertEquals(4, LLote.UltimoNSU);
  AssertEquals('resNFe', LLote.Itens[0].Schema);
  AssertEquals('procNFe', LLote.Itens[3].Schema);
  AssertTrue('o XML do docZip chegou descompactado', Pos('<chNFe>', LLote.Itens[0].XmlDecodificado) > 0);
  AssertEquals('(nenhuma)', ViolacoesDoSimulador);
end;

procedure TDFeAcbrSimHttpTests.ConsumoIndevido_ELoteComCStat656_NaoExcecao;
var
  LClient: IDFeDistribuicaoClient;
  LLote: TDFeLoteBruto;
begin
  IniciarSimulador(['[simulador]', 'Falhas=consumo-indevido', '[conta:a]', 'Cnpj=' + CNPJ_CERT, 'UF=RS']);
  LClient := ClientDoSimulador;
  LLote := LClient.Consultar(Certificado, 0);
  AssertEquals(656, LLote.CStat);
  AssertEquals(0, Length(LLote.Itens));
end;

procedure TDFeAcbrSimHttpTests.Timeout_ViraComunicacaoFalhou;
var
  LClient: IDFeDistribuicaoClient;
begin
  IniciarSimulador(['[simulador]', 'Falhas=timeout', '[conta:a]', 'Cnpj=' + CNPJ_CERT, 'UF=RS']);
  LClient := ClientDoSimulador;
  try
    LClient.Consultar(Certificado, 0);
    Fail('esperava EDFeComunicacaoFalhou');
  except
    on EDFeComunicacaoFalhou do ;
  end;
end;

procedure TDFeAcbrSimHttpTests.ErroHttp500_ViraComunicacaoFalhou;
var
  LClient: IDFeDistribuicaoClient;
begin
  IniciarSimulador(['[simulador]', 'Falhas=erro-http', '[conta:a]', 'Cnpj=' + CNPJ_CERT, 'UF=RS']);
  LClient := ClientDoSimulador;
  try
    LClient.Consultar(Certificado, 0);
    Fail('esperava EDFeComunicacaoFalhou');
  except
    on EDFeComunicacaoFalhou do ;
  end;
end;

procedure TDFeAcbrSimHttpTests.CorpoIlegivel_ViraRespostaInvalida;
var
  LClient: IDFeDistribuicaoClient;
begin
  IniciarSimulador(['[simulador]', 'Falhas=corpo-ilegivel', '[conta:a]', 'Cnpj=' + CNPJ_CERT, 'UF=RS']);
  LClient := ClientDoSimulador;
  try
    LClient.Consultar(Certificado, 0);
    Fail('esperava EDFeRespostaInvalida');
  except
    on EDFeRespostaInvalida do ;
  end;
end;

procedure TDFeAcbrSimHttpTests.DocZipCorrompido_ViraRespostaInvalida;
var
  LClient: IDFeDistribuicaoClient;
begin
  IniciarSimulador(['[simulador]', 'Falhas=doczip-corrompido', '[conta:a]', 'Cnpj=' + CNPJ_CERT, 'UF=RS', 'ResNFe=1']);
  LClient := ClientDoSimulador;
  try
    LClient.Consultar(Certificado, 0);
    Fail('esperava EDFeRespostaInvalida');
  except
    on EDFeRespostaInvalida do ;
  end;
end;

procedure TDFeAcbrSimHttpTests.SimuladorForaDoAr_ViraComunicacaoFalhou;
var
  LClient: IDFeDistribuicaoClient;
begin
  // porta 9 (discard) sem ninguem escutando: sem resposta HTTP (no Windows a conexao
  // local a porta fechada nao e' recusada na hora -- timeout curto para nao pesar)
  LClient := NovoClient('http://127.0.0.1:9', 1500);
  try
    LClient.Consultar(Certificado, 0);
    Fail('esperava EDFeComunicacaoFalhou');
  except
    on EDFeComunicacaoFalhou do ;
  end;
end;

procedure TDFeAcbrSimHttpTests.Admin_PublicaDocumentos_ClienteRecebe;
var
  LClient: IDFeDistribuicaoClient;
  LLote: TDFeLoteBruto;
begin
  IniciarSimulador(['[simulador]']); // sem contas: tudo vem pela API admin
  Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_CERT + '","uf":"RS","quantidade":2}');
  Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_CERT + '","uf":"RS","tipo":"procNFe"}');
  LClient := ClientDoSimulador;
  LLote := LClient.Consultar(Certificado, 0);
  AssertEquals(138, LLote.CStat);
  AssertEquals(3, Length(LLote.Itens));
  AssertEquals('resNFe', LLote.Itens[0].Schema);
  AssertEquals('procNFe', LLote.Itens[2].Schema);
  AssertTrue('o estado da API reflete a consulta', Pos('"consultas":1', Admin('GET', '/admin/estado')) > 0);
end;

procedure TDFeAcbrSimHttpTests.Admin_ConsumoIndevido_ReproduzidoEDesfeitoPeloRelogioVirtual;
var
  LClient: IDFeDistribuicaoClient;
begin
  // O criterio de pronto da Fase B: o 656 (bloqueio de 1 h) reproduzido e desfeito
  // por HTTP em SEGUNDOS, sem esperar a hora -- com o client ACBr real.
  IniciarSimulador(['[simulador]']);
  LClient := ClientDoSimulador;
  AssertEquals('1a: sem novidade', 137, LClient.Consultar(Certificado, 0).CStat);
  AssertEquals('2a, na hora: consumo indevido', 656, LClient.Consultar(Certificado, 0).CStat);
  Admin('POST', '/admin/relogio/avancar', '{"horas":1,"minutos":1}');
  AssertTrue('o relogio virtual andou', Pos('"deslocamentoSegundos":3660', Admin('GET', '/admin/relogio')) > 0);
  AssertEquals('depois de 1 h virtual: liberado', 137, LClient.Consultar(Certificado, 0).CStat);
end;

procedure TDFeAcbrSimHttpTests.Extensao_RegraDoUsuario_BarraOClientPorHttp;
var
  LClient: IDFeDistribuicaoClient;
  LLote: TDFeLoteBruto;
begin
  // Criterio de pronto da Fase C: uma regra que o core NAO tem (limite de consultas
  // por janela), registrada so' por estar linkada no programa do exemplo, vista pelo
  // client ACBr real por HTTP -- inclusive a rota propria /ext/ e o relogio virtual.
  IniciarSimulador(['[simulador]'], CaminhoDoExemplo);
  Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_CERT + '","uf":"RS"}');
  AssertTrue('a regra aparece em /admin/regras', Pos('"nome":"limite-consultas"', Admin('GET', '/admin/regras')) > 0);
  Admin('POST', '/ext/limite', '{"maximo":1,"janelaSegundos":600}');
  LClient := ClientDoSimulador;
  AssertEquals('1a: dentro do limite, o nucleo responde', 138, LClient.Consultar(Certificado, 0).CStat);
  LLote := LClient.Consultar(Certificado, 0); // 656 e' LOTE, nao excecao (decisao 16)
  AssertEquals('2a: barrada pela regra', 656, LLote.CStat);
  AssertTrue('a mensagem e a da regra: ' + LLote.XMotivo, Pos('limite de 1 consulta', LLote.XMotivo) > 0);
  AssertTrue('a rota propria conta a rejeicao', Pos('"rejeitadas":1', Admin('GET', '/ext/limite')) > 0);
  Admin('POST', '/admin/relogio/avancar', '{"minutos":11}');
  AssertEquals('depois da janela (virtual), liberada', 138, LClient.Consultar(Certificado, 0).CStat);
  Admin('POST', '/admin/regras', '{"nome":"limite-consultas","ativa":false}');
  AssertEquals('desligada: sem limite', 138, LClient.Consultar(Certificado, 0).CStat);
  AssertEquals('desligada: sem limite (de novo)', 138, LClient.Consultar(Certificado, 0).CStat);
end;

procedure TDFeAcbrSimHttpTests.Admin_FalhaEnfileirada_ClienteSofre;
var
  LClient: IDFeDistribuicaoClient;
begin
  IniciarSimulador(['[simulador]']);
  Admin('POST', '/admin/falhas', '{"falhas":["erro-http","corpo-ilegivel"]}');
  LClient := ClientDoSimulador;
  try
    LClient.Consultar(Certificado, 0);
    Fail('esperava EDFeComunicacaoFalhou (HTTP 500)');
  except
    on EDFeComunicacaoFalhou do ;
  end;
  try
    LClient.Consultar(Certificado, 0);
    Fail('esperava EDFeRespostaInvalida (corpo ilegivel)');
  except
    on EDFeRespostaInvalida do ;
  end;
  AssertTrue('acabaram as falhas', Pos('"falhasPendentes":0', Admin('GET', '/admin/estado')) > 0);
end;

procedure TDFeAcbrSimHttpTests.Admin_Violacao_AparecePorHttpELimpa;
var
  LStatus: Integer;
begin
  IniciarSimulador(['[simulador]']);
  // um cliente que NAO e' o ACBr, sem a SOAPAction: leniente = atendido, mas registrado
  Chamar('POST', '/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx', EnvelopeDeDistribuicao, LStatus);
  AssertEquals('leniente atende', 200, LStatus);
  AssertTrue('registra a violacao de SoapAction', Pos('SoapAction', Admin('GET', '/admin/violacoes')) > 0);
  AssertTrue(Pos('"removidas":1', Admin('DELETE', '/admin/violacoes')) > 0);
  AssertEquals('(nenhuma)', Admin('GET', '/admin/violacoes'));
end;

procedure TDFeAcbrSimHttpTests.Admin_ModoEstrito_RecusaComHttp400ENaoConsomeNsu;
var
  LStatus: Integer;
  LCorpo: string;
begin
  IniciarSimulador(['[simulador]']);
  Admin('POST', '/admin/modo', '{"estrito":true}');
  LCorpo := Chamar('POST', '/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx', EnvelopeDeDistribuicao, LStatus);
  AssertEquals('estrito recusa', 400, LStatus);
  AssertTrue('diz o motivo', Pos('SoapAction', LCorpo) > 0);
  // o ponto: a requisicao recusada nao tocou o estado
  AssertTrue('nenhuma consulta processada', Pos('"consultas":0', Admin('GET', '/admin/estado')) > 0);
  AssertTrue('e nenhuma conta criada', Pos('"contas":[]', Admin('GET', '/admin/estado')) > 0);
  // o client ACBr real manda o formato certo: passa mesmo no modo estrito
  AssertEquals(137, ClientDoSimulador.Consultar(Certificado, 0).CStat);
end;

procedure TDFeAcbrSimHttpTests.Admin_Zerar_VoltaAoInicio;
var
  LEstado: string;
begin
  IniciarSimulador(['[simulador]']);
  Admin('POST', '/admin/documentos', '{"cnpj":"' + CNPJ_CERT + '","uf":"RS"}');
  Admin('POST', '/admin/falhas', '{"falha":"timeout"}');
  Admin('POST', '/admin/relogio/avancar', '{"segundos":500}');
  Admin('POST', '/admin/zerar');
  LEstado := Admin('GET', '/admin/estado');
  AssertTrue(Pos('"contas":[]', LEstado) > 0);
  AssertTrue(Pos('"falhasPendentes":0', LEstado) > 0);
  AssertTrue(Pos('"deslocamentoSegundos":0', LEstado) > 0);
end;

procedure TDFeAcbrSimHttpTests.Manifestacao_Ciencia_RegistradaPorHttp;
var
  LClient: IDFeDistribuicaoClient;
  LManifestador: IDFeManifestador;
  LComando: TDFeComandoManifestacao;
  LEv: TDFeEventoNormalizado;
begin
  ExigirAmbienteDeEvento;
  IniciarSimulador(['[conta:a]', 'Cnpj=' + CNPJ_CERT, 'UF=RS', 'ResNFe=1']);
  LClient := ClientDoSimulador;
  LClient.Consultar(Certificado, 0); // o simulador so' registra evento de NFe que ele conhece
  AssertTrue('o client real deve implementar IDFeManifestador', Supports(LClient, IDFeManifestador, LManifestador));

  LComando.Alias := 'teste';
  LComando.ChaveAcesso := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1);
  LComando.TipoEvento := DFE_EVENTO_MANIFESTACAO_CIENCIA;
  LComando.Justificativa := '';
  LEv := LManifestador.EnviarEvento(Certificado, LComando);

  AssertEquals(DFE_EVENTO_MANIFESTACAO_CIENCIA, LEv.TipoEvento);
  AssertTrue('payload e o procEventoNFe', Pos('<procEventoNFe', LEv.XmlPayload) > 0);
  AssertTrue('payload traz o protocolo do simulador', Pos('<nProt>891', LEv.XmlPayload) > 0);
  AssertTrue('payload traz a assinatura', Pos('<SignatureValue>', LEv.XmlPayload) > 0);
  AssertEquals('(nenhuma)', ViolacoesDoSimulador);
end;

procedure TDFeAcbrSimHttpTests.Manifestacao_JustificativaComAcento_ChegaAssinadaEIntactaAoSimulador;
var
  LClient: IDFeDistribuicaoClient;
  LManifestador: IDFeManifestador;
  LComando: TDFeComandoManifestacao;
  LEv: TDFeEventoNormalizado;
  LJust: string;
begin
  ExigirAmbienteDeEvento;
  IniciarSimulador(['[conta:a]', 'Cnpj=' + CNPJ_CERT, 'UF=RS', 'ResNFe=1']);
  LClient := ClientDoSimulador;
  LClient.Consultar(Certificado, 0);
  AssertTrue(Supports(LClient, IDFeManifestador, LManifestador));

  LComando.Alias := 'teste';
  LComando.ChaveAcesso := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, 1);
  LComando.TipoEvento := DFE_EVENTO_MANIFESTACAO_OPERACAO_NAO_REALIZADA;
  LJust := 'Mercadoria n' + #$C3#$A3 + 'o foi entregue no prazo combinado'; // UTF-8 (FPC)
  LComando.Justificativa := LJust;
  LEv := LManifestador.EnviarEvento(Certificado, LComando);

  AssertEquals(DFE_EVENTO_MANIFESTACAO_OPERACAO_NAO_REALIZADA, LEv.TipoEvento);
  AssertEquals('(nenhuma)', ViolacoesDoSimulador);
  // O que o simulador RECEBEU pela rede traz o texto exato, nao uma dupla codificacao
  // (que passaria pelo XSD: os bytes virariam "A" til + libra, ambos <= U+00FF).
  AssertTrue('xJust chegou intacto ao simulador',
    Pos('<xJust>' + LJust + '</xJust>', UltimoEnvelopeDoSimulador) > 0);
end;

initialization
  RegisterTest(TDFeAcbrSimHttpTests);

end.
