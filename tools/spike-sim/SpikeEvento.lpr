program SpikeEvento;

{ SPIKE DESCARTAVEL da Fase 4 do simulador (docs/simulador-sefaz.md):
  chama TDFeDistribuicaoClientACBrNFe.EnviarEvento (manifestacao) com um
  transmissor que imprime o envelope que o ACBr montou e devolve um
  retEnvEvento de sucesso. Objetivo: descobrir ate' onde o ACBr chega e o
  que exige em execucao (libxml2 para assinar/validar, XSDs reais).

  Uso: SpikeEvento <arquivo.pfx> <senha> <pasta-schemas> }

{$mode delphi}{$H+}

uses
  Interfaces,
  SysUtils,
  ACBrDFe.Conversao,
  DFe.Transmissor,
  DFe.Types,
  DFe.Errors,
  DFe.Provider,
  DFe.Manifestacao,
  DFe.Client.ACBrNFe;

type
  TTransmissorSpike = class(TInterfacedObject, IDFeTransmissor)
    function Transmitir(const AEnvelope, AURL, ASoapAction,
      AMimeType: string): TDFeRespostaTransmissao;
  end;

const
  CHAVE = '35260998765432000110550010000000011000000019';

function TTransmissorSpike.Transmitir(const AEnvelope, AURL, ASoapAction,
  AMimeType: string): TDFeRespostaTransmissao;
begin
  WriteLn('  [Transmitir] URL=', AURL);
  WriteLn('  [Transmitir] SoapAction=', ASoapAction);
  WriteLn('  [Transmitir] Envelope=', AEnvelope);
  Result.HTTPResultCode := 200;
  Result.InternalErrorCode := 0;
  Result.Texto :=
    '<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope"><soap:Body>' +
    '<nfeRecepcaoEventoNFResult xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeRecepcaoEvento4">' +
    '<retEnvEvento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00"><idLote>1</idLote><tpAmb>2</tpAmb>' +
    '<verAplic>SIMULADOR</verAplic><cOrgao>91</cOrgao><cStat>128</cStat><xMotivo>Lote de Evento Processado</xMotivo>' +
    '<retEvento versao="1.00"><infEvento><tpAmb>2</tpAmb><verAplic>SIMULADOR</verAplic><cOrgao>91</cOrgao>' +
    '<cStat>135</cStat><xMotivo>Evento registrado e vinculado a NF-e</xMotivo><chNFe>' + CHAVE + '</chNFe>' +
    '<tpEvento>210210</tpEvento><xEvento>Ciencia da Operacao</xEvento><nSeqEvento>1</nSeqEvento>' +
    '<CNPJDest>11222333000181</CNPJDest><dhRegEvento>2026-09-18T10:00:00-03:00</dhRegEvento>' +
    '<nProt>891260000000001</nProt></infEvento></retEvento></retEnvEvento>' +
    '</nfeRecepcaoEventoNFResult></soap:Body></soap:Envelope>';
end;

var
  LCred: TDFeCredencialCertificado;
  LCert: TDFeCertificado;
  LCmd: TDFeComandoManifestacao;
  LClient: TDFeDistribuicaoClientACBrNFe;
  LManif: IDFeManifestador;
  LTransm: IDFeTransmissor;
  LEv: TDFeEventoNormalizado;
begin
  if ParamCount < 3 then
  begin
    WriteLn('uso: SpikeEvento <arquivo.pfx> <senha> <pasta-schemas>');
    Halt(2);
  end;
  LCred.ArquivoPFX := ParamStr(1);
  LCred.Senha := ParamStr(2);
  LCred.PathSchemas := ParamStr(3);
  LCert.Identificador := 'teste';
  LCert.CnpjCpf := '11222333000181';
  LCert.UF := 'RS';
  LCmd.Alias := 'teste';
  LCmd.ChaveAcesso := CHAVE;
  LCmd.TipoEvento := DFE_EVENTO_MANIFESTACAO_CIENCIA;
  LCmd.Justificativa := '';

  LTransm := TTransmissorSpike.Create;
  LClient := TDFeDistribuicaoClientACBrNFe.Create(LCred, taHomologacao, LTransm);
  LManif := LClient;
  try
    LEv := LManif.EnviarEvento(LCert, LCmd);
    WriteLn('EnviarEvento OK: TipoEvento=', LEv.TipoEvento, ' Categoria=', Ord(LEv.Categoria));
    WriteLn('XmlPayload=', Copy(LEv.XmlPayload, 1, 300));
  except
    on E: Exception do
      WriteLn('EXCECAO ', E.ClassName, ': ', E.Message);
  end;
  LManif := nil;
end.
