unit DFe.Errors;

{$I dfe.inc}

{ Modelo de erro do IDFeDistribuicaoClient (ver DFe.Provider). So existem
  excecoes para o que impede a chamada de produzir um TDFeLoteBruto
  interpretavel -- a semantica de protocolo da SEFAZ (nenhum documento,
  consumo indevido, servico indisponivel, etc.) NAO e' modelada como
  excecao, e' o campo CStat de TDFeLoteBruto, classificado por
  DFe.Types.ClassificarCStat. Essa separacao existe de proposito: excecao e'
  "a chamada falhou", CStat e' "a chamada funcionou e a SEFAZ respondeu isto"
  -- misturar os dois faria o orquestrador nao conseguir distinguir uma
  rejeicao de protocolo (656) de uma falha de rede so olhando o tipo da
  excecao. }

interface

uses
  SysUtils;

type
  EDFeError = class(Exception);

  { Falha de transporte/comunicacao com a SEFAZ antes de existir qualquer
    resposta interpretavel: timeout, TLS, DNS, SOAP fault sem corpo util.
    Transitorio -- o orquestrador mantem o agendamento normal (nao aciona o
    backoff de consumo indevido, que e' especifico do cStat 656). }
  EDFeComunicacaoFalhou = class(EDFeError);

  { O certificado nao pode ser usado: expirado, senha incorreta, cadeia
    invalida, revogado. NAO e' transitorio -- exige intervencao humana na
    configuracao. O orquestrador deve pausar o agendamento daquele
    certificado, nunca tentar de novo em loop apertado. }
  EDFeCertificadoInvalido = class(EDFeError);

  { A SEFAZ respondeu, mas o corpo nao e' interpretavel como retorno de
    Distribuicao de DFe (docZip corrompido, XML fora do schema esperado). O
    orquestrador loga e pula o ciclo -- o cursor de NSU NAO avanca. }
  EDFeRespostaInvalida = class(EDFeError);

implementation

end.
