unit DFe.Client.ACBrNFe;

{$I dfe.inc}

{ Implementacao REAL de IDFeDistribuicaoClient (ver DFe.Provider) via
  TACBrNFe -- componente classico do ACBr (ver docs/architecture.md,
  "Integracao com ACBr", decisao revertida de ACBrLib em 2026-09-18). E'
  a UNICA peca do sistema que fala de verdade com a SEFAZ.

  NAO TESTADA CONTRA A SEFAZ DE VERDADE (nem em homologacao): este
  ambiente de desenvolvimento nao tem certificado digital real -- ver
  docs/architecture.md, "Fronteira testavel sem certificado real". Tudo
  abaixo foi verificado lendo o fonte do ACBr (vendor/ACBr), nao rodando
  contra a SEFAZ. Compilacao (FPC e Delphi) e' o unico nivel de
  verificacao possivel ate' existir um certificado de teste.

  DUAS PECAS DA API do TACBrNFe foram deliberadamente evitadas em favor
  de chamar WebServices.DistribuicaoDFe diretamente:

  1. TACBrNFe.DistribuicaoDFePorUltNSU/.Distribuicao(...) levanta excecao
     (GerarException) sempre que TDistribuicaoDFe.TratarResposta devolve
     False -- e TratarResposta so' considera sucesso cStat 137/138 (ver
     ACBrNFeWebServices.pas). Isso significa que consumo indevido (656),
     servico indisponivel (108/109) e qualquer outro cStat viram excecao
     nessas chamadas de conveniencia -- exatamente o que DFe.Errors NAO
     quer (ver comentario de topo daquele unit: cStat e' "a chamada
     funcionou e a SEFAZ respondeu isto", nunca excecao). Chamando
     WebServices.DistribuicaoDFe.Executar diretamente (o metodo herdado
     de TDFeWebService, sem o wrapper de TACBrNFe.Distribuicao por cima)
     devolve so' um Boolean sem levantar nada quando cStat e' outro
     valor -- o que sobra e' inspecionavel via retDistDFeInt, que e' o
     que MontarLoteBruto le. So' EXCECOES DE VERDADE (timeout, XML
     ilegivel, falha antes de existir resposta) continuam propagando de
     Executar -- exatamente a fronteira que DFe.Errors modela.
  2. Nao existe try/except generico "por via das duvidas": os 3 ramos
     (timeout, sem resposta interpretavel, resposta com cStat valido)
     sao distinguidos via TACBrNFe.SSL.HTTPResultCode e
     retDistDFeInt.cStat, nunca por texto de mensagem de excecao (texto
     de erro do ACBr nao e' um contrato estavel entre versoes). }

interface

uses
  SysUtils,
  ACBrNFe,
  ACBrNFeWebServices,
  ACBrDFeConfiguracoes,
  ACBrDFeSSL,
  ACBrDFeException,
  ACBrDFeComum.RetDistDFeInt,
  ACBrDFe.Conversao,
  ACBrNFe.EnvEvento,
  ACBrNFe.EventoClass,
  ACBrUtil.Base,
  ACBrUtil.DateTime,
  StrUtils,
  DFe.Types,
  DFe.Errors,
  DFe.Transmissor,
  DFe.XmlTexto,
  DFe.Fuso,
  DFe.Ambiente,
  DFe.Ambiente.ACBr,
  DFe.Provider,
  DFe.Provider.NFe,
  DFe.Manifestacao;

type
  { Credenciais reais do certificado digital -- deliberadamente FORA de
    TDFeCertificado/TDFeConfigCertificado (ver DFe.Types, DFe.Config): o
    core nunca sabe de .pfx/senha, so' quem monta o client real (ver
    TDFeClientFactory em DFe.Config). }
  TDFeCredencialCertificado = record
    ArquivoPFX: string;
    Senha: string;
    { Pasta com os XSD oficiais (Configuracoes.Arquivos.PathSchemas do
      ACBr). Vazio = padrao do ACBr, 'Schemas' ao lado do executavel. O ACBr
      exige ao menos um *.xsd la em EXECUCAO, ate' para distribuicao (ver
      docs/simulador-sefaz.md, Fase 0, achado 3); EnviarEvento precisa dos
      XSD reais, pois valida o XML. }
    PathSchemas: string;
  end;

  { Implementa TAMBEM IDFeManifestador (ver DFe.Manifestacao para o porque
    de ficar no client e nao no provider): e' este objeto quem tem o
    certificado real carregado no TACBrNFe.

    EnviarEvento -- NAO TESTADO contra a SEFAZ, mesma limitacao de
    Consultar. Verificado lendo o fonte do ACBr (ACBrNFe.pas,
    ACBrNFeWebServices.pas, ACBrNFe.EnvEvento.pas):
    - Manifestacao vai para o Ambiente Nacional (cOrgao = 91), nao para a
      SEFAZ da UF; o ACBr ja' escolhe a URL 'AN' para tpEvento fora de
      CCe/cancelamento (TNFeEnvEvento.DefinirURL), mas cOrgao precisa ser
      definido aqui -- o default do ACBr seria a UF da chave, que o AN
      rejeita.
    - infEvento.CNPJ e' o do DESTINATARIO (o certificado desta unidade),
      nao o do emitente: se ficasse vazio o ACBr usaria o CNPJ da chave,
      ou seja, o emitente -- por isso e' sempre preenchido.
    - Como em Consultar, chama FACBrNFe.EnviarEvento (que devolve Boolean
      sem levantar por cStat) em vez de Cancelamento()/wrappers que
      levantam GerarException; rejeicao de protocolo vem no evento
      devolvido, nunca como excecao (ver DFe.Errors). }
  TDFeDistribuicaoClientACBrNFe = class(TInterfacedObject, IDFeDistribuicaoClient, IDFeManifestador)
  private
    FACBrNFe: TACBrNFe;
    { nil em producao (o ACBr faz o HTTP). Guardado como interface para
      manter o objeto vivo enquanto o ACBr o usa via AoTransmitir. }
    FTransmissor: IDFeTransmissor;
    { HTTPResultCode devolvido pelo transmissor na ultima chamada. Com
      transmissor injetado o ACBr NAO popula SSL.HTTPResultCode (so' o
      caminho HTTP proprio dele faz isso), entao TratarFalhaDeChamada usa
      este valor para distinguir resposta ilegivel de falha de comunicacao. }
    FHttpDoTransmissor: Integer;
    { Usos para os quais o ambiente de execucao ja foi verificado E estava
      completo (so' o sucesso e' guardado: falha e' reverificada, para o
      operador consertar o servidor sem reiniciar o processo). }
    FAmbienteVerificado: TDFeUsosAmbiente;
    function CodigoHttpDaUltimaChamada: Integer;
    { Confere OpenSSL / libxml2 / XSDs ANTES de tocar no certificado ou na rede
      e levanta EDFeAmbienteIndisponivel (DFe.Errors) com o que falta e como
      corrigir. Sem isto, DLL ausente saia como "certificado invalido" (a
      unidade era PAUSADA) ou "falha de comunicacao" (parecia transitorio). }
    procedure ExigirAmbiente(const AUso: TDFeUsoAmbiente);
    procedure AoTransmitir(const Dados, URL, SoapAction, MimeType: string;
      var Resposta: string; var HTTPResultCode: Integer;
      var InternalErrorCode: Integer);
    { Garante certificado carregado, nao vencido e compativel com o CNPJ
      da unidade -- tudo isso e' problema de CONFIGURACAO/CERTIFICADO,
      nunca de comunicacao, entao qualquer falha aqui vira
      EDFeCertificadoInvalido (ver DFe.Errors), nao EDFeComunicacaoFalhou.
      Chamado ANTES da consulta de verdade, de proposito -- isola o que
      pode dar errado no certificado do que pode dar errado na rede. }
    procedure GarantirCertificadoValido(const ACnpjCpf: string);
    { Traduz uma excecao levantada DURANTE a chamada de rede para o modelo
      de DFe.Errors, sem depender de texto de mensagem (nao e' contrato
      estavel entre versoes do ACBr). Timeout sempre vira
      EDFeComunicacaoFalhou. Se a SEFAZ ja' respondeu com um cStat
      interpretavel (ACStatRecebido <> 0), a excecao e' so' o criterio
      estreito do ACBr reclamando de um cStat que nao e' "sucesso" --
      ENGOLIDA de proposito (o chamador le o cStat do que sobrou). Sem
      cStat: HTTP 200 = respondeu mas ilegivel (EDFeRespostaInvalida); o
      resto = EDFeComunicacaoFalhou. }
    procedure TratarFalhaDeChamada(const E: Exception; const ACStatRecebido: Integer);
  public
    { AAmbiente default taProducao de proposito -- homologacao e'
      escolha explicita de quem monta o client (host/config), nunca
      default silencioso escondido aqui. }
    { ATransmissor: nil (padrao) = comportamento de producao, o ACBr faz o
      HTTP/TLS. Se informado, ele substitui SO' o transporte (ver
      DFe.Transmissor) -- usado pelo simulador da SEFAZ e por testes. }
    constructor Create(const ACredencial: TDFeCredencialCertificado;
      const AAmbiente: TACBrTipoAmbiente = taProducao;
      const ATransmissor: IDFeTransmissor = nil);
    destructor Destroy; override;

    function Consultar(const ACertificado: TDFeCertificado;
      const AUltimoNSU: Int64): TDFeLoteBruto;

    function EnviarEvento(const ACertificado: TDFeCertificado;
      const AComando: TDFeComandoManifestacao): TDFeEventoNormalizado;
  end;

implementation

const
  { Codigo de "orgao" do Ambiente Nacional (Receita Federal), destino da
    manifestacao do destinatario -- ver comentario da classe. }
  ORGAO_AMBIENTE_NACIONAL = 91;

function TipoEventoACBr(const ATipoEvento: string): TACBrTipoEvento;
begin
  if ATipoEvento = DFE_EVENTO_MANIFESTACAO_CONFIRMACAO then
    Result := teManifDestConfirmacao
  else if ATipoEvento = DFE_EVENTO_MANIFESTACAO_CIENCIA then
    Result := teManifDestCiencia
  else if ATipoEvento = DFE_EVENTO_MANIFESTACAO_DESCONHECIMENTO then
    Result := teManifDestDesconhecimento
  else if ATipoEvento = DFE_EVENTO_MANIFESTACAO_OPERACAO_NAO_REALIZADA then
    Result := teManifDestOperNaoRealizada
  else
    { InterpretarComando (DFe.Manifestacao) ja' recusa isto -- so' chega
      aqui por comando montado na mao com tipo invalido: bug de quem
      chamou, nao um caso modelado. }
    raise Exception.CreateFmt('Tipo de evento de manifestacao desconhecido: "%s"', [ATipoEvento]);
end;

function ContarOcorrencias(const ASub, Atexto: string): Integer;
var
  P: Integer;
begin
  Result := 0;
  P := Pos(ASub, Atexto);
  while P > 0 do
  begin
    Inc(Result);
    P := PosEx(ASub, Atexto, P + Length(ASub));
  end;
end;

{ O ACBr NAO avisa quando falha ao interpretar um docZip: TRetDistDFeInt.
  LerXml engole a excecao e devolve False, que TDistribuicaoDFe.
  TratarResposta ignora -- o lote sai TRUNCADO (ou com item de XML vazio) mas
  com o ultNSU/maxNSU do CABECALHO da resposta. Sem esta conferencia o
  cursor avancaria ate' o ultNSU e os documentos perdidos nunca voltariam:
  PERDA SILENCIOSA. Achado pelo teste de integracao com o simulador
  (tests/Integration/AcbrSim): um procNFe sem <tpNF> derrubou o 3o item de 4.
  Levantar aqui faz o orquestrador reagendar SEM avancar o cursor, entao a
  proxima tentativa busca o mesmo lote.

  Conta os '<docZip' da resposta BRUTA e compara com o que o ACBr
  interpretou. So' aplica quando ha algum (0 = nao reconheceu o formato,
  ex.: elemento com prefixo de namespace; nesse caso nao ha como conferir,
  e nunca falso-positivo). }
procedure ConferirLoteCompleto(const ARet: TRetDistDFeInt; const ARespostaBruta: string);
var
  LEsperados, I: Integer;
begin
  LEsperados := ContarOcorrencias('<docZip ', ARespostaBruta) +
    ContarOcorrencias('<docZip>', ARespostaBruta);
  if (LEsperados > 0) and (ARet.docZip.Count <> LEsperados) then
    raise EDFeRespostaInvalida.CreateFmt(
      'Lote truncado: a resposta traz %d docZip mas so'' %d foram interpretados ' +
      '(ultNSU=%s); cursor nao deve avancar', [LEsperados, ARet.docZip.Count, ARet.ultNSU]);

  for I := 0 to ARet.docZip.Count - 1 do
    if ARet.docZip[I].XML = '' then
      raise EDFeRespostaInvalida.CreateFmt(
        'docZip do NSU %s nao pode ser lido (gzip ou XML corrompido?); cursor nao deve avancar',
        [ARet.docZip[I].NSU]);
end;

function MontarLoteBruto(const ARet: TRetDistDFeInt): TDFeLoteBruto;
var
  I: Integer;
begin
  Result.CStat := ARet.cStat;
  Result.XMotivo := ARet.xMotivo;
  Result.UltimoNSU := StrToInt64Def(ARet.ultNSU, 0);
  Result.MaxNSU := StrToInt64Def(ARet.maxNSU, 0);

  SetLength(Result.Itens, ARet.docZip.Count);
  for I := 0 to ARet.docZip.Count - 1 do
  begin
    Result.Itens[I].NSU := StrToInt64Def(ARet.docZip[I].NSU, 0);
    { GetEnumName sobre TSchemaDFe (ex.: 'schresNFe', 'schresEvento') --
      nao e' o nome do .xsd oficial, mas e' estavel e e' so' o provider de
      NFe (ver DFe.Provider) quem interpreta este campo, entao a
      convencao interna e' suficiente (ver comentario de
      TDFeItemBruto.Schema em DFe.Types). }
    Result.Itens[I].Schema := SchemaDFeToStr(ARet.docZip[I].schema);
    { docZip[I].XML ja' vem descompactado (gzip+base64 do docZip ja'
      tratado pelo proprio ACBrDFeComum.RetDistDFeInt) -- nao ha
      decodificacao manual de envelope aqui, ao contrario do que uma
      implementacao via ACBrLib exigiria (ver docs/architecture.md,
      "Fonte dos componentes classicos"). }
    { TextoDoAcbr: no Delphi o ACBr entrega os bytes UTF-8 reinterpretados como
      ANSI (mojibake); aqui vira o texto nativo do compilador. Achado pelo
      teste de integracao em Delphi -- ver DFe.XmlTexto. }
    Result.Itens[I].XmlDecodificado := TextoDoAcbr(ARet.docZip[I].XML);
  end;
end;

{ TDFeDistribuicaoClientACBrNFe }

constructor TDFeDistribuicaoClientACBrNFe.Create(const ACredencial: TDFeCredencialCertificado;
  const AAmbiente: TACBrTipoAmbiente; const ATransmissor: IDFeTransmissor);
begin
  inherited Create;
  PrepararParaBibliotecasNativas; // antes de o ACBr poder carregar qualquer biblioteca nativa
  FACBrNFe := TACBrNFe.Create(nil);
  FTransmissor := ATransmissor;
  if ACredencial.PathSchemas <> '' then
    FACBrNFe.Configuracoes.Arquivos.PathSchemas := ACredencial.PathSchemas;
  if Assigned(FTransmissor) then
    FACBrNFe.OnTransmit := AoTransmitir;

  { O ACBr grava por padrao, sob o diretorio da aplicacao, os XMLs de
    envio/resposta (Geral.Salvar = True) e cada documento baixado
    (Arquivos.Salvar = True). O broker entrega tudo por mensagem, nao por
    arquivo -- achado ao rodar o spike da Fase 0 (apareceu uma pasta
    Docs\). WebServices.Salvar ja' e' False por padrao. }
  FACBrNFe.Configuracoes.Geral.Salvar := False;
  FACBrNFe.Configuracoes.Arquivos.Salvar := False;

  { Acentos do texto livre do evento (xJust): o ACBr os REMOVE por padrao
    (RetirarAcentos = True), em silencio -- o motivo que o operador digitou
    nao e' o que a SEFAZ recebe. O XSD (TMotivo) aceita U+0020..U+00FF, e
    InterpretarComando recusa o que ficaria fora disso; a assinatura confere
    com o acento (teste de integracao). }
  FACBrNFe.Configuracoes.Geral.RetirarAcentos := False;

  { Fuso do dhEvento fixo em Brasilia (-03:00), independente do sistema: ver
    DFe.Fuso. ModoDeteccao ANTES de TimeZoneStr (fora de tzManual o ACBr
    zera a string). }
  FACBrNFe.Configuracoes.WebServices.TimeZoneConf.ModoDeteccao := tzManual;
  FACBrNFe.Configuracoes.WebServices.TimeZoneConf.TimeZoneStr := DFE_FUSO_BRASILIA;

  { OpenSSL/LibXml2 em vez de WinCrypt/CAPICOM/MSXml -- unica combinacao
    que funciona nos dois compiladores/plataformas (ver decisao 2 em
    CLAUDE.md, dual-compiler desde o inicio). xsLibXml2 e NAO xsXmlSec: o
    ACBr.inc upstream define DFE_SEM_XMLSEC por padrao, e nesse caso
    atribuir xsXmlSec LEVANTA EXCECAO no construtor (achado pelo spike da
    Fase 0 do simulador, docs/simulador-sefaz.md). Depende de libcrypto/
    libssl (e libxml2, so' para ASSINAR -- a distribuicao nao assina)
    disponiveis em tempo de execucao; carregamento de certificado e
    libcrypto-3 confirmados em execucao (Win64) so' com o spike, nao contra
    a SEFAZ. Requer tambem uma pasta Schemas\*.xsd (ver
    Configuracoes.Arquivos.PathSchemas) -- o ACBr a consulta ate' para
    resolver a versao do servico de distribuicao. }
  FACBrNFe.Configuracoes.Geral.SSLCryptLib := cryOpenSSL;
  FACBrNFe.Configuracoes.Geral.SSLHttpLib := httpOpenSSL;
  FACBrNFe.Configuracoes.Geral.SSLXmlSignLib := xsLibXml2;

  FACBrNFe.Configuracoes.WebServices.Ambiente := AAmbiente;
  FACBrNFe.Configuracoes.Certificados.ArquivoPFX := ACredencial.ArquivoPFX;
  FACBrNFe.Configuracoes.Certificados.Senha := ACredencial.Senha;
end;

destructor TDFeDistribuicaoClientACBrNFe.Destroy;
begin
  FACBrNFe.Free;
  inherited Destroy;
end;

procedure TDFeDistribuicaoClientACBrNFe.AoTransmitir(const Dados, URL, SoapAction,
  MimeType: string; var Resposta: string; var HTTPResultCode: Integer;
  var InternalErrorCode: Integer);
var
  LResposta: TDFeRespostaTransmissao;
begin
  LResposta := FTransmissor.Transmitir(Dados, URL, SoapAction, MimeType);
  Resposta := LResposta.Texto;
  FHttpDoTransmissor := LResposta.HTTPResultCode;
  HTTPResultCode := LResposta.HTTPResultCode;
  InternalErrorCode := LResposta.InternalErrorCode;
end;

procedure TDFeDistribuicaoClientACBrNFe.ExigirAmbiente(const AUso: TDFeUsoAmbiente);
var
  LRelatorio: TDFeRelatorioAmbiente;
begin
  if AUso in FAmbienteVerificado then
    Exit;
  LRelatorio := VerificarAmbienteACBr(FACBrNFe.Configuracoes.Arquivos.PathSchemas, [AUso]);
  if not AmbienteCompleto(LRelatorio) then
    raise EDFeAmbienteIndisponivel.Create(MensagemAmbienteIncompleto(LRelatorio));
  Include(FAmbienteVerificado, AUso);
end;

function TDFeDistribuicaoClientACBrNFe.CodigoHttpDaUltimaChamada: Integer;
begin
  if Assigned(FTransmissor) then
    Result := FHttpDoTransmissor
  else
    Result := FACBrNFe.SSL.HTTPResultCode;
end;

procedure TDFeDistribuicaoClientACBrNFe.GarantirCertificadoValido(const ACnpjCpf: string);
begin
  try
    FACBrNFe.SSL.CarregarCertificadoSeNecessario;

    if (FACBrNFe.SSL.CertDataVenc <> 0) and (FACBrNFe.SSL.CertDataVenc < Now) then
      raise EDFeCertificadoInvalido.CreateFmt(
        'Certificado expirado em %s', [DateToStr(FACBrNFe.SSL.CertDataVenc)]);

    { Confere que o certificado carregado e' realmente do CNPJ desta
      unidade (raiz, primeiros 8 digitos -- mesmo criterio que o proprio
      ACBr usa, ver TDFeSSL.ValidarCNPJCertificado) -- protege contra o
      erro de configuracao "alias aponta pro .pfx errado". }
    FACBrNFe.SSL.ValidarCNPJCertificado(ACnpjCpf);
  except
    on E: EDFeCertificadoInvalido do
      raise;
    on E: Exception do
      raise EDFeCertificadoInvalido.Create(E.Message);
  end;
end;

function TDFeDistribuicaoClientACBrNFe.Consultar(const ACertificado: TDFeCertificado;
  const AUltimoNSU: Int64): TDFeLoteBruto;
var
  LDistribuicao: TDistribuicaoDFe;
begin
  PrepararParaBibliotecasNativas; // FPU mascarada nesta thread (DFe.Ambiente.ACBr)
  ExigirAmbiente(uaDistribuicao);
  GarantirCertificadoValido(ACertificado.CnpjCpf);
  FHttpDoTransmissor := 0;

  FACBrNFe.Configuracoes.WebServices.UF := ACertificado.UF;

  LDistribuicao := FACBrNFe.WebServices.DistribuicaoDFe;
  LDistribuicao.cUFAutor := UFparaCodigoUF(ACertificado.UF);
  LDistribuicao.CNPJCPF := ACertificado.CnpjCpf;
  LDistribuicao.ultNSU := IntToStr(AUltimoNSU);
  LDistribuicao.NSU := '';
  LDistribuicao.chNFe := '';

  try
    { Boolean devolvido ignorado de proposito -- ver comentario de topo
      do unit: TratarResposta so' considera 137/138 sucesso, mas
      qualquer cStat valido (656, 108/109, etc.) e' um retorno legitimo
      da SEFAZ pro nosso modelo (ver DFe.Errors), nao uma falha. O que
      importa e' se retDistDFeInt ficou populado. }
    LDistribuicao.Executar;
  except
    on E: Exception do
      TratarFalhaDeChamada(E, LDistribuicao.retDistDFeInt.cStat);
  end;

  { cStat = 0: o ACBr NAO conseguiu interpretar a resposta (LerXml engole o
    erro -- ex.: libxml2 ausente, XML fora do formato) mas a chamada nao
    levantou nada. Um retDistDFeInt de verdade sempre traz cStat. Sem esta
    recusa o lote "sem cStat" chegava ao orquestrador como cStat desconhecido
    e a unidade ficava sem consultar de verdade, em silencio. }
  if LDistribuicao.retDistDFeInt.cStat = 0 then
    raise EDFeRespostaInvalida.Create(
      'Resposta da SEFAZ sem cStat interpretavel (o ACBr nao conseguiu ler o retDistDFeInt)');

  ConferirLoteCompleto(LDistribuicao.retDistDFeInt, LDistribuicao.RetWS);
  Result := MontarLoteBruto(LDistribuicao.retDistDFeInt);
end;

procedure TDFeDistribuicaoClientACBrNFe.TratarFalhaDeChamada(const E: Exception;
  const ACStatRecebido: Integer);
begin
  if E is EACBrDFeExceptionTimeOut then
    raise EDFeComunicacaoFalhou.Create(E.Message);

  if ACStatRecebido <> 0 then
    Exit; // ver comentario da declaracao: engolida de proposito

  if CodigoHttpDaUltimaChamada = 200 then
    raise EDFeRespostaInvalida.Create(E.Message)
  else
    raise EDFeComunicacaoFalhou.Create(E.Message);
end;

function TDFeDistribuicaoClientACBrNFe.EnviarEvento(const ACertificado: TDFeCertificado;
  const AComando: TDFeComandoManifestacao): TDFeEventoNormalizado;
var
  LEnvio: TNFeEnvEvento;
  LRetorno: TRetInfEvento;
begin
  PrepararParaBibliotecasNativas;
  ExigirAmbiente(uaManifestacao);
  GarantirCertificadoValido(ACertificado.CnpjCpf);
  FHttpDoTransmissor := 0;

  FACBrNFe.Configuracoes.WebServices.UF := ACertificado.UF;

  FACBrNFe.EventoNFe.Evento.Clear;
  with FACBrNFe.EventoNFe.Evento.New do
  begin
    infEvento.cOrgao := ORGAO_AMBIENTE_NACIONAL;
    infEvento.CNPJ := ACertificado.CnpjCpf;
    infEvento.chNFe := AComando.ChaveAcesso;
    infEvento.dhEvento := AgoraDeBrasilia; // hora de parede de Brasilia; o sufixo -03:00 vem do TimeZoneConf
    infEvento.tpEvento := TipoEventoACBr(AComando.TipoEvento);
    infEvento.nSeqEvento := 1;
    { xJust so' existe em Operacao nao Realizada: a NT 2012/002 (HP20) manda
      informa-lo SOMENTE nesse evento. O ACBr o enviaria tambem no
      desconhecimento se estivesse preenchido. }
    if (AComando.Justificativa <> '')
      and (AComando.TipoEvento = DFE_EVENTO_MANIFESTACAO_OPERACAO_NAO_REALIZADA) then
      infEvento.detEvento.xJust := AComando.Justificativa;
  end;

  LEnvio := FACBrNFe.WebServices.EnvEvento;
  try
    { Boolean ignorado de proposito, mesmo motivo de Consultar: TratarResposta
      so' considera cStat 128 (lote processado) sucesso; o resultado de
      CADA evento (135/136 aceito, demais rejeicao) esta em
      EventoRetorno.retEvento. idLote = 1: lote de um evento so'. }
    FACBrNFe.EnviarEvento(1);
  except
    on E: Exception do
      TratarFalhaDeChamada(E, LEnvio.cStat);
  end;

  if LEnvio.cStat = 0 then
    raise EDFeRespostaInvalida.Create('Resposta ao evento de manifestacao sem cStat interpretavel');

  Result.TipoDocumento := DFE_TIPO_DOCUMENTO_NFE;
  Result.Categoria := dcEvento;
  Result.TipoEvento := DFE_EVENTO_MANIFESTACAO_REJEITADA;
  Result.ChaveAcesso := AComando.ChaveAcesso;
  Result.CnpjCpfConsultante := ACertificado.CnpjCpf;
  Result.UF := ACertificado.UF;
  Result.NSU := 0; // nao veio da distribuicao -- nao ha NSU
  Result.DataEmissao := Now;

  { Rejeicao (do evento ou do lote inteiro, sem retEvento): TipoEvento
    'manifestacaorejeitada' e payload = retorno bruto da SEFAZ
    (retEnvEvento). So' quando o evento foi registrado (CStatEventoRegistrado)
    o resultado usa o TipoEvento do comando e o procEventoNFe completo que o
    ACBr monta em RetInfEvento.XML -- assim a routing-key ja' diz se a
    manifestacao valeu (ver DFE_EVENTO_MANIFESTACAO_REJEITADA). }
  Result.XmlPayload := LEnvio.RetWS;
  if LEnvio.EventoRetorno.retEvento.Count > 0 then
  begin
    LRetorno := LEnvio.EventoRetorno.retEvento.Items[0].RetInfEvento;
    if CStatEventoRegistrado(LRetorno.cStat) and (LRetorno.XML <> '') then
    begin
      Result.TipoEvento := AComando.TipoEvento;
      { mesma fronteira de encoding do docZip (DFe.XmlTexto). NAO testado em
        Delphi com acento (o simulador so' devolve ASCII no retEvento); o
        fallback de TextoDoAcbr protege se o formato for outro. }
      Result.XmlPayload := TextoDoAcbr(string(LRetorno.XML));
      if LRetorno.dhRegEvento <> 0 then
        Result.DataEmissao := LRetorno.dhRegEvento;
    end;
  end;
end;

end.
