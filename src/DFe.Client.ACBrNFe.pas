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
  ACBrUtil.Base,
  DFe.Types,
  DFe.Errors,
  DFe.Provider;

type
  { Credenciais reais do certificado digital -- deliberadamente FORA de
    TDFeCertificado/TDFeConfigCertificado (ver DFe.Types, DFe.Config): o
    core nunca sabe de .pfx/senha, so' quem monta o client real (ver
    TDFeClientFactory em DFe.Config). }
  TDFeCredencialCertificado = record
    ArquivoPFX: string;
    Senha: string;
  end;

  TDFeDistribuicaoClientACBrNFe = class(TInterfacedObject, IDFeDistribuicaoClient)
  private
    FACBrNFe: TACBrNFe;
    { Garante certificado carregado, nao vencido e compativel com o CNPJ
      da unidade -- tudo isso e' problema de CONFIGURACAO/CERTIFICADO,
      nunca de comunicacao, entao qualquer falha aqui vira
      EDFeCertificadoInvalido (ver DFe.Errors), nao EDFeComunicacaoFalhou.
      Chamado ANTES da consulta de verdade, de proposito -- isola o que
      pode dar errado no certificado do que pode dar errado na rede. }
    procedure GarantirCertificadoValido(const ACnpjCpf: string);
  public
    { AAmbiente default taProducao de proposito -- homologacao e'
      escolha explicita de quem monta o client (host/config), nunca
      default silencioso escondido aqui. }
    constructor Create(const ACredencial: TDFeCredencialCertificado;
      const AAmbiente: TACBrTipoAmbiente = taProducao);
    destructor Destroy; override;

    function Consultar(const ACertificado: TDFeCertificado;
      const AUltimoNSU: Int64): TDFeLoteBruto;
  end;

implementation

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
    on E: EACBrDFeExceptionTimeOut do
      raise EDFeComunicacaoFalhou.Create(E.Message);
    on E: Exception do
    begin
      if LDistribuicao.retDistDFeInt.cStat <> 0 then
      begin
        { A SEFAZ respondeu com um cStat interpretavel (ver acima) --
          TratarResposta so' levantou por causa do criterio estreito de
          TACBrNFe.Distribuicao (nao usado aqui, ver topo do unit), nao
          porque a chamada falhou de verdade. Engolir e' proposital:
          MontarLoteBruto abaixo usa esse cStat, e ClassificarCStat (ver
          DFe.Types) decide o resto. }
      end
      else if FACBrNFe.SSL.HTTPResultCode = 200 then
        { Respondeu (HTTP 200) mas nao deu pra' interpretar como retorno
          de Distribuicao de DFe -- corpo corrompido/fora do schema
          esperado (ver EDFeRespostaInvalida em DFe.Errors). }
        raise EDFeRespostaInvalida.Create(E.Message)
      else
        { Sem resposta interpretavel nenhuma antes da falha (conexao
          recusada, DNS, HTTP != 200 sem corpo util) -- transitorio. }
        raise EDFeComunicacaoFalhou.Create(E.Message);
    end;
  end;

  Result := MontarLoteBruto(LDistribuicao.retDistDFeInt);
end;

end.
