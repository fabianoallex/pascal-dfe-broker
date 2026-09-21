unit DFe.ConsumidorDocumentoTests;

{ Testa a unit pura do sample de consumidor Pascal
  (exemplos/consumidor/pascal/ConsumidorDFeVcl/uDFeDocumento.pas): o que um
  consumidor de terceiros consegue ler da routing-key e do XML, e o comando de
  manifestacao que ele monta.

  O sample NAO usa nenhuma unit do broker (de proposito: e' a prova de que so'
  o cliente AMQP basta). Estes testes fazem a ponte -- o comando montado pelo
  sample tem de ser aceito pelo InterpretarComando do host de verdade. }

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils,
  uDFeDocumento, DFe.Manifestacao;

type
  TDFeConsumidorDocumentoTests = class(TTestCase)
  published
    procedure RoutingKey_Documento;
    procedure RoutingKey_Evento_TemOTipoDoEvento;
    procedure RoutingKey_ComandoOuLixo_NaoEValida;
    procedure LerXml_ResumoDeNFe;
    procedure LerXml_DocumentoCompleto_ChaveVemDoAtributoId;
    procedure LerXml_Evento_TemTpEvento;
    procedure LerXml_Ilegivel;
    procedure Dedup_ResumoEDocumentoCompletoSaoItensDiferentes;
    procedure Dedup_EventosDaMesmaChave_SeDistinguemPeloTipo;
    procedure Dedup_MesmoItemDuasVezes_MesmaChave;
    procedure NomeDeArquivo_SoTemCaracteresSeguros;
    procedure NomeDeArquivo_Deterministico;
    procedure Comando_Ciencia_SemJustificativa;
    procedure Comando_OperacaoNaoRealizada_LevaJustificativa;
    procedure Comando_DescartaJustificativaFora_DeOperacaoNaoRealizada;
    procedure Comando_Recusa_EntradaInvalida;
    procedure Comando_QueOSampleMonta_EAceitoPeloHost;
  end;

implementation

const
  CHAVE = '35260998765432000110550010000000011000079198';
  CNPJ_CERT = '11222333000181';

  XML_RESUMO =
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<resNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.01">' +
    '<chNFe>' + CHAVE + '</chNFe><CNPJ>98765432000110</CNPJ>' +
    '<xNome>EMITENTE SINTETICO LTDA</xNome><dhEmi>2026-09-10T14:30:05-03:00</dhEmi>' +
    '<vNF>150.00</vNF></resNFe>';

  XML_COMPLETO =
    '<nfeProc versao="4.00"><NFe><infNFe Id="NFe' + CHAVE + '" versao="4.00">' +
    '<emit><xNome>EMITENTE SINTETICO LTDA</xNome></emit>' +
    '<total><ICMSTot><vNF>150.00</vNF></ICMSTot></total></infNFe></NFe></nfeProc>';

  XML_EVENTO =
    '<resEvento versao="1.01"><chNFe>' + CHAVE + '</chNFe>' +
    '<tpEvento>110111</tpEvento><xEvento>Cancelamento</xEvento></resEvento>';

procedure TDFeConsumidorDocumentoTests.RoutingKey_Documento;
var
  LRk: TDFeRoutingKey;
begin
  LRk := LerRoutingKey('nfe.documento.sp.' + CNPJ_CERT);
  AssertTrue(LRk.Valida);
  AssertEquals('nfe', LRk.Tipo);
  AssertEquals('documento', LRk.Categoria);
  AssertEquals('', LRk.TipoEvento);
  AssertEquals('sp', LRk.UF);
  AssertEquals(CNPJ_CERT, LRk.Cnpj);
end;

procedure TDFeConsumidorDocumentoTests.RoutingKey_Evento_TemOTipoDoEvento;
var
  LRk: TDFeRoutingKey;
begin
  LRk := LerRoutingKey('nfe.evento.cancelamento.rs.' + CNPJ_CERT);
  AssertTrue(LRk.Valida);
  AssertEquals('evento', LRk.Categoria);
  AssertEquals('cancelamento', LRk.TipoEvento);
  AssertEquals('rs', LRk.UF);
  AssertEquals(CNPJ_CERT, LRk.Cnpj);
end;

procedure TDFeConsumidorDocumentoTests.RoutingKey_ComandoOuLixo_NaoEValida;
begin
  // a routing-key do comando de manifestacao nao segue <tipo>.<categoria>...
  AssertFalse(LerRoutingKey('comando.manifestacao').Valida);
  AssertFalse(LerRoutingKey('').Valida);
  AssertFalse(LerRoutingKey('nfe.documento.sp').Valida);
  AssertFalse(LerRoutingKey('nfe.evento.sp.' + CNPJ_CERT).Valida); // evento sem tipo: 4 palavras
end;

procedure TDFeConsumidorDocumentoTests.LerXml_ResumoDeNFe;
var
  LInfo: TDFeInfo;
begin
  LInfo := LerXml(XML_RESUMO);
  AssertTrue(LInfo.Legivel);
  AssertEquals('resNFe', LInfo.TipoXml);
  AssertEquals(CHAVE, LInfo.Chave);
  AssertEquals('EMITENTE SINTETICO LTDA', LInfo.XNome);
  AssertEquals('150.00', LInfo.VNF);
  AssertEquals('2026-09-10T14:30:05-03:00', LInfo.DhEmi);
  AssertEquals('', LInfo.TpEvento);
  AssertEquals('xNome=EMITENTE SINTETICO LTDA, dhEmi=2026-09-10T14:30:05-03:00, vNF=150.00',
    LInfo.Resumo);
end;

procedure TDFeConsumidorDocumentoTests.LerXml_DocumentoCompleto_ChaveVemDoAtributoId;
var
  LInfo: TDFeInfo;
begin
  LInfo := LerXml(XML_COMPLETO);
  AssertTrue(LInfo.Legivel);
  AssertEquals('nfeProc', LInfo.TipoXml);
  AssertEquals(CHAVE, LInfo.Chave);
  AssertEquals('EMITENTE SINTETICO LTDA', LInfo.XNome);
end;

procedure TDFeConsumidorDocumentoTests.LerXml_Evento_TemTpEvento;
var
  LInfo: TDFeInfo;
begin
  LInfo := LerXml(XML_EVENTO);
  AssertTrue(LInfo.Legivel);
  AssertEquals('resEvento', LInfo.TipoXml);
  AssertEquals(CHAVE, LInfo.Chave);
  AssertEquals('110111', LInfo.TpEvento);
end;

procedure TDFeConsumidorDocumentoTests.LerXml_Ilegivel;
begin
  AssertFalse(LerXml('').Legivel);
  AssertFalse(LerXml('isto nao e xml').Legivel);
  AssertFalse(LerXml('<resNFe><chNFe>').Legivel); // aberto e nunca fechado
end;

procedure TDFeConsumidorDocumentoTests.Dedup_ResumoEDocumentoCompletoSaoItensDiferentes;
begin
  // a mesma NFe chega primeiro como resumo, depois (apos a ciencia) completa:
  // sao dois itens legitimos, nao repeticao
  AssertTrue(LerXml(XML_RESUMO).ChaveDeDedup <> LerXml(XML_COMPLETO).ChaveDeDedup);
end;

procedure TDFeConsumidorDocumentoTests.Dedup_EventosDaMesmaChave_SeDistinguemPeloTipo;
var
  LOutro: string;
begin
  LOutro := StringReplace(XML_EVENTO, '110111', '110110', []);
  AssertTrue(LerXml(XML_EVENTO).ChaveDeDedup <> LerXml(LOutro).ChaveDeDedup);
end;

procedure TDFeConsumidorDocumentoTests.Dedup_MesmoItemDuasVezes_MesmaChave;
begin
  AssertEquals(LerXml(XML_RESUMO).ChaveDeDedup, LerXml(XML_RESUMO).ChaveDeDedup);
end;

procedure TDFeConsumidorDocumentoTests.NomeDeArquivo_SoTemCaracteresSeguros;
var
  LInfo: TDFeInfo;
  LNome: string;
  I: Integer;
begin
  // a chave vem de um XML de fora: nao pode virar caminho
  LInfo := LerXml('<resNFe><chNFe>..\..\evil/x</chNFe></resNFe>');
  LNome := LInfo.NomeDeArquivo;
  for I := 1 to Length(LNome) do
    AssertTrue('caractere inseguro em ' + LNome,
      (LNome[I] in ['0'..'9', 'A'..'Z', 'a'..'z', '_', '.', '-']));
  AssertEquals(0, Pos('..', StringReplace(LNome, '.xml', '', [])));
  AssertTrue(Copy(LNome, Length(LNome) - 3, 4) = '.xml');
end;

procedure TDFeConsumidorDocumentoTests.NomeDeArquivo_Deterministico;
begin
  AssertEquals(CHAVE + '_resNFe.xml', LerXml(XML_RESUMO).NomeDeArquivo);
  AssertEquals(CHAVE + '_nfeProc.xml', LerXml(XML_COMPLETO).NomeDeArquivo);
  AssertEquals(CHAVE + '_resEvento_110111.xml', LerXml(XML_EVENTO).NomeDeArquivo);
  AssertEquals('sem-chave_resNFe.xml', LerXml('<resNFe></resNFe>').NomeDeArquivo);
end;

procedure TDFeConsumidorDocumentoTests.Comando_Ciencia_SemJustificativa;
var
  LErro: string;
begin
  AssertEquals('Alias=matriz'#10'ChaveAcesso=' + CHAVE + #10'TipoEvento=ciencia',
    MontarComandoManifestacao('matriz', CHAVE, 'ciencia', '', LErro));
  AssertEquals('', LErro);
end;

procedure TDFeConsumidorDocumentoTests.Comando_OperacaoNaoRealizada_LevaJustificativa;
var
  LErro: string;
begin
  AssertEquals('Alias=matriz'#10'ChaveAcesso=' + CHAVE + #10'TipoEvento=operacaonaorealizada'#10 +
    'Justificativa=mercadoria nao recebida',
    MontarComandoManifestacao(' matriz ', CHAVE, 'operacaonaorealizada', ' mercadoria nao recebida ', LErro));
end;

procedure TDFeConsumidorDocumentoTests.Comando_DescartaJustificativaFora_DeOperacaoNaoRealizada;
var
  LErro: string;
begin
  AssertEquals('Alias=matriz'#10'ChaveAcesso=' + CHAVE + #10'TipoEvento=confirmacao',
    MontarComandoManifestacao('matriz', CHAVE, 'confirmacao', 'texto que sobrou na tela', LErro));
end;

procedure TDFeConsumidorDocumentoTests.Comando_Recusa_EntradaInvalida;
var
  LErro: string;
begin
  AssertEquals('', MontarComandoManifestacao('', CHAVE, 'ciencia', '', LErro));
  AssertTrue('alias vazio: ' + LErro, LErro <> '');

  AssertEquals('', MontarComandoManifestacao('matriz', '123', 'ciencia', '', LErro));
  AssertTrue('chave curta: ' + LErro, LErro <> '');

  AssertEquals('', MontarComandoManifestacao('matriz', Copy(CHAVE, 1, 43) + 'x', 'ciencia', '', LErro));
  AssertTrue('chave com letra: ' + LErro, LErro <> '');

  AssertEquals('', MontarComandoManifestacao('matriz', CHAVE, 'aprovacao', '', LErro));
  AssertTrue('tipo desconhecido: ' + LErro, LErro <> '');

  AssertEquals('', MontarComandoManifestacao('matriz', CHAVE, 'operacaonaorealizada', '   ', LErro));
  AssertTrue('sem justificativa: ' + LErro, LErro <> '');
end;

procedure TDFeConsumidorDocumentoTests.Comando_QueOSampleMonta_EAceitoPeloHost;
var
  LErro: string;
  LComando: TDFeComandoManifestacao;
  I: Integer;
begin
  // o contrato de verdade: o que o consumidor publica em comando.manifestacao
  // e' lido por InterpretarComando, o mesmo que a fila de comandos do host usa
  for I := Low(DFE_TIPOS_MANIFESTACAO) to High(DFE_TIPOS_MANIFESTACAO) do
  begin
    LComando := InterpretarComando(MontarComandoManifestacao('matriz', CHAVE,
      DFE_TIPOS_MANIFESTACAO[I], 'mercadoria nao recebida no prazo', LErro));
    AssertEquals(DFE_TIPOS_MANIFESTACAO[I], LComando.TipoEvento);
    AssertEquals('matriz', LComando.Alias);
    AssertEquals(CHAVE, LComando.ChaveAcesso);
    if DFE_TIPOS_MANIFESTACAO[I] = 'operacaonaorealizada' then
      AssertEquals('mercadoria nao recebida no prazo', LComando.Justificativa)
    else
      AssertEquals('', LComando.Justificativa);
  end;
end;

initialization
  RegisterTest(TDFeConsumidorDocumentoTests);

end.
