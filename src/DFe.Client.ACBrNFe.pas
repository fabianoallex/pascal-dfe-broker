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
  DFe.Types,
  DFe.Errors,
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
    constructor Create(const ACredencial: TDFeCredencialCertificado;
      const AAmbiente: TACBrTipoAmbiente = taProducao);
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
    Result.Itens[I].XmlDecodificado := ARet.docZip[I].XML;
  end;
end;

{ TDFeDistribuicaoClientACBrNFe }

constructor TDFeDistribuicaoClientACBrNFe.Create(const ACredencial: TDFeCredencialCertificado;
  const AAmbiente: TACBrTipoAmbiente);
begin
  inherited Create;
  FACBrNFe := TACBrNFe.Create(nil);

  { OpenSSL/XmlSec em vez de WinCrypt/CAPICOM/MSXml -- unica combinacao
    que funciona nos dois compiladores/plataformas (ver decisao 2 em
    CLAUDE.md, dual-compiler desde o inicio). Depende de libcrypto/
    libssl e libxmlsec1 disponiveis em tempo de execucao -- dependencia
    de sistema, nao de compilacao; NAO verificado nesta maquina (sem
    certificado real para exercitar a chamada de verdade). }
  FACBrNFe.Configuracoes.Geral.SSLCryptLib := cryOpenSSL;
  FACBrNFe.Configuracoes.Geral.SSLHttpLib := httpOpenSSL;
  FACBrNFe.Configuracoes.Geral.SSLXmlSignLib := xsXmlSec;

  FACBrNFe.Configuracoes.WebServices.Ambiente := AAmbiente;
  FACBrNFe.Configuracoes.Certificados.ArquivoPFX := ACredencial.ArquivoPFX;
  FACBrNFe.Configuracoes.Certificados.Senha := ACredencial.Senha;
end;

destructor TDFeDistribuicaoClientACBrNFe.Destroy;
begin
  FACBrNFe.Free;
  inherited Destroy;
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
  GarantirCertificadoValido(ACertificado.CnpjCpf);

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

  Result := MontarLoteBruto(LDistribuicao.retDistDFeInt);
end;

procedure TDFeDistribuicaoClientACBrNFe.TratarFalhaDeChamada(const E: Exception;
  const ACStatRecebido: Integer);
begin
  if E is EACBrDFeExceptionTimeOut then
    raise EDFeComunicacaoFalhou.Create(E.Message);

  if ACStatRecebido <> 0 then
    Exit; // ver comentario da declaracao: engolida de proposito

  if FACBrNFe.SSL.HTTPResultCode = 200 then
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
  GarantirCertificadoValido(ACertificado.CnpjCpf);

  FACBrNFe.Configuracoes.WebServices.UF := ACertificado.UF;

  FACBrNFe.EventoNFe.Evento.Clear;
  with FACBrNFe.EventoNFe.Evento.New do
  begin
    infEvento.cOrgao := ORGAO_AMBIENTE_NACIONAL;
    infEvento.CNPJ := ACertificado.CnpjCpf;
    infEvento.chNFe := AComando.ChaveAcesso;
    infEvento.dhEvento := Now;
    infEvento.tpEvento := TipoEventoACBr(AComando.TipoEvento);
    infEvento.nSeqEvento := 1;
    if AComando.Justificativa <> '' then
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
      Result.XmlPayload := string(LRetorno.XML);
      if LRetorno.dhRegEvento <> 0 then
        Result.DataEmissao := LRetorno.dhRegEvento;
    end;
  end;
end;

end.
