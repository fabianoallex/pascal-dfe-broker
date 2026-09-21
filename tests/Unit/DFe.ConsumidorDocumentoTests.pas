unit DFe.ConsumidorDocumentoTests;

{ Espelho DUnitX de tests/Unit/fpc/DFe.ConsumidorDocumentoTests.pas (1:1).

  Testa a unit pura do sample de consumidor Pascal
  (exemplos/consumidor/pascal/ConsumidorDFeVcl/uDFeDocumento.pas): o que um
  consumidor de terceiros consegue ler da routing-key e do XML, e o comando de
  manifestacao que ele monta.

  O sample NAO usa nenhuma unit do broker (de proposito: e' a prova de que so'
  o cliente AMQP basta). Estes testes fazem a ponte -- o comando montado pelo
  sample tem de ser aceito pelo InterpretarComando do host de verdade. }

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  uDFeDocumento, DFe.Manifestacao;

type
  [TestFixture]
  TDFeConsumidorDocumentoTests = class
  public
    [Test] procedure RoutingKey_Documento;
    [Test] procedure RoutingKey_Evento_TemOTipoDoEvento;
    [Test] procedure RoutingKey_ComandoOuLixo_NaoEValida;
    [Test] procedure LerXml_ResumoDeNFe;
    [Test] procedure LerXml_DocumentoCompleto_ChaveVemDoAtributoId;
    [Test] procedure LerXml_Evento_TemTpEvento;
    [Test] procedure LerXml_Ilegivel;
    [Test] procedure Dedup_ResumoEDocumentoCompletoSaoItensDiferentes;
    [Test] procedure Dedup_EventosDaMesmaChave_SeDistinguemPeloTipo;
    [Test] procedure Dedup_MesmoItemDuasVezes_MesmaChave;
    [Test] procedure NomeDeArquivo_SoTemCaracteresSeguros;
    [Test] procedure NomeDeArquivo_Deterministico;
    [Test] procedure Comando_Ciencia_SemJustificativa;
    [Test] procedure Comando_OperacaoNaoRealizada_LevaJustificativa;
    [Test] procedure Comando_DescartaJustificativaFora_DeOperacaoNaoRealizada;
    [Test] procedure Comando_Recusa_EntradaInvalida;
    [Test] procedure Comando_QueOSampleMonta_EAceitoPeloHost;
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
  Assert.IsTrue(LRk.Valida);
  Assert.AreEqual('nfe', LRk.Tipo);
  Assert.AreEqual('documento', LRk.Categoria);
  Assert.AreEqual('', LRk.TipoEvento);
  Assert.AreEqual('sp', LRk.UF);
  Assert.AreEqual(CNPJ_CERT, LRk.Cnpj);
end;

procedure TDFeConsumidorDocumentoTests.RoutingKey_Evento_TemOTipoDoEvento;
var
  LRk: TDFeRoutingKey;
begin
  LRk := LerRoutingKey('nfe.evento.cancelamento.rs.' + CNPJ_CERT);
  Assert.IsTrue(LRk.Valida);
  Assert.AreEqual('evento', LRk.Categoria);
  Assert.AreEqual('cancelamento', LRk.TipoEvento);
  Assert.AreEqual('rs', LRk.UF);
  Assert.AreEqual(CNPJ_CERT, LRk.Cnpj);
end;

procedure TDFeConsumidorDocumentoTests.RoutingKey_ComandoOuLixo_NaoEValida;
begin
  // a routing-key do comando de manifestacao nao segue <tipo>.<categoria>...
  Assert.IsFalse(LerRoutingKey('comando.manifestacao').Valida);
  Assert.IsFalse(LerRoutingKey('').Valida);
  Assert.IsFalse(LerRoutingKey('nfe.documento.sp').Valida);
  Assert.IsFalse(LerRoutingKey('nfe.evento.sp.' + CNPJ_CERT).Valida); // evento sem tipo: 4 palavras
end;

procedure TDFeConsumidorDocumentoTests.LerXml_ResumoDeNFe;
var
  LInfo: TDFeInfo;
begin
  LInfo := LerXml(XML_RESUMO);
  Assert.IsTrue(LInfo.Legivel);
  Assert.AreEqual('resNFe', LInfo.TipoXml);
  Assert.AreEqual(CHAVE, LInfo.Chave);
  Assert.AreEqual('EMITENTE SINTETICO LTDA', LInfo.XNome);
  Assert.AreEqual('150.00', LInfo.VNF);
  Assert.AreEqual('2026-09-10T14:30:05-03:00', LInfo.DhEmi);
  Assert.AreEqual('', LInfo.TpEvento);
  Assert.AreEqual('xNome=EMITENTE SINTETICO LTDA, dhEmi=2026-09-10T14:30:05-03:00, vNF=150.00',
    LInfo.Resumo);
end;

procedure TDFeConsumidorDocumentoTests.LerXml_DocumentoCompleto_ChaveVemDoAtributoId;
var
  LInfo: TDFeInfo;
begin
  LInfo := LerXml(XML_COMPLETO);
  Assert.IsTrue(LInfo.Legivel);
  Assert.AreEqual('nfeProc', LInfo.TipoXml);
  Assert.AreEqual(CHAVE, LInfo.Chave);
  Assert.AreEqual('EMITENTE SINTETICO LTDA', LInfo.XNome);
end;

procedure TDFeConsumidorDocumentoTests.LerXml_Evento_TemTpEvento;
var
  LInfo: TDFeInfo;
begin
  LInfo := LerXml(XML_EVENTO);
  Assert.IsTrue(LInfo.Legivel);
  Assert.AreEqual('resEvento', LInfo.TipoXml);
  Assert.AreEqual(CHAVE, LInfo.Chave);
  Assert.AreEqual('110111', LInfo.TpEvento);
end;

procedure TDFeConsumidorDocumentoTests.LerXml_Ilegivel;
begin
  Assert.IsFalse(LerXml('').Legivel);
  Assert.IsFalse(LerXml('isto nao e xml').Legivel);
  Assert.IsFalse(LerXml('<resNFe><chNFe>').Legivel); // aberto e nunca fechado
end;

procedure TDFeConsumidorDocumentoTests.Dedup_ResumoEDocumentoCompletoSaoItensDiferentes;
begin
  // a mesma NFe chega primeiro como resumo, depois (apos a ciencia) completa:
  // sao dois itens legitimos, nao repeticao
  Assert.IsTrue(LerXml(XML_RESUMO).ChaveDeDedup <> LerXml(XML_COMPLETO).ChaveDeDedup);
end;

procedure TDFeConsumidorDocumentoTests.Dedup_EventosDaMesmaChave_SeDistinguemPeloTipo;
var
  LOutro: string;
begin
  LOutro := StringReplace(XML_EVENTO, '110111', '110110', []);
  Assert.IsTrue(LerXml(XML_EVENTO).ChaveDeDedup <> LerXml(LOutro).ChaveDeDedup);
end;

procedure TDFeConsumidorDocumentoTests.Dedup_MesmoItemDuasVezes_MesmaChave;
begin
  Assert.AreEqual(LerXml(XML_RESUMO).ChaveDeDedup, LerXml(XML_RESUMO).ChaveDeDedup);
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
    Assert.IsTrue(CharInSet(LNome[I], ['0'..'9', 'A'..'Z', 'a'..'z', '_', '.', '-']),
      'caractere inseguro em ' + LNome);
  Assert.AreEqual(0, Integer(Pos('..', StringReplace(LNome, '.xml', '', []))));
  Assert.IsTrue(Copy(LNome, Length(LNome) - 3, 4) = '.xml');
end;

procedure TDFeConsumidorDocumentoTests.NomeDeArquivo_Deterministico;
begin
  Assert.AreEqual(CHAVE + '_resNFe.xml', LerXml(XML_RESUMO).NomeDeArquivo);
  Assert.AreEqual(CHAVE + '_nfeProc.xml', LerXml(XML_COMPLETO).NomeDeArquivo);
  Assert.AreEqual(CHAVE + '_resEvento_110111.xml', LerXml(XML_EVENTO).NomeDeArquivo);
  Assert.AreEqual('sem-chave_resNFe.xml', LerXml('<resNFe></resNFe>').NomeDeArquivo);
end;

procedure TDFeConsumidorDocumentoTests.Comando_Ciencia_SemJustificativa;
var
  LErro: string;
begin
  Assert.AreEqual('Alias=matriz'#10'ChaveAcesso=' + CHAVE + #10'TipoEvento=ciencia',
    MontarComandoManifestacao('matriz', CHAVE, 'ciencia', '', LErro));
  Assert.AreEqual('', LErro);
end;

procedure TDFeConsumidorDocumentoTests.Comando_OperacaoNaoRealizada_LevaJustificativa;
var
  LErro: string;
begin
  Assert.AreEqual('Alias=matriz'#10'ChaveAcesso=' + CHAVE + #10'TipoEvento=operacaonaorealizada'#10 +
    'Justificativa=mercadoria nao recebida',
    MontarComandoManifestacao(' matriz ', CHAVE, 'operacaonaorealizada', ' mercadoria nao recebida ', LErro));
end;

procedure TDFeConsumidorDocumentoTests.Comando_DescartaJustificativaFora_DeOperacaoNaoRealizada;
var
  LErro: string;
begin
  Assert.AreEqual('Alias=matriz'#10'ChaveAcesso=' + CHAVE + #10'TipoEvento=confirmacao',
    MontarComandoManifestacao('matriz', CHAVE, 'confirmacao', 'texto que sobrou na tela', LErro));
end;

procedure TDFeConsumidorDocumentoTests.Comando_Recusa_EntradaInvalida;
var
  LErro: string;
begin
  Assert.AreEqual('', MontarComandoManifestacao('', CHAVE, 'ciencia', '', LErro));
  Assert.IsTrue(LErro <> '', 'alias vazio: ' + LErro);

  Assert.AreEqual('', MontarComandoManifestacao('matriz', '123', 'ciencia', '', LErro));
  Assert.IsTrue(LErro <> '', 'chave curta: ' + LErro);

  Assert.AreEqual('', MontarComandoManifestacao('matriz', Copy(CHAVE, 1, 43) + 'x', 'ciencia', '', LErro));
  Assert.IsTrue(LErro <> '', 'chave com letra: ' + LErro);

  Assert.AreEqual('', MontarComandoManifestacao('matriz', CHAVE, 'aprovacao', '', LErro));
  Assert.IsTrue(LErro <> '', 'tipo desconhecido: ' + LErro);

  Assert.AreEqual('', MontarComandoManifestacao('matriz', CHAVE, 'operacaonaorealizada', '   ', LErro));
  Assert.IsTrue(LErro <> '', 'sem justificativa: ' + LErro);
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
    Assert.AreEqual(DFE_TIPOS_MANIFESTACAO[I], LComando.TipoEvento);
    Assert.AreEqual('matriz', LComando.Alias);
    Assert.AreEqual(CHAVE, LComando.ChaveAcesso);
    if DFE_TIPOS_MANIFESTACAO[I] = 'operacaonaorealizada' then
      Assert.AreEqual('mercadoria nao recebida no prazo', LComando.Justificativa)
    else
      Assert.AreEqual('', LComando.Justificativa);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeConsumidorDocumentoTests);

end.
