unit DFe.AmbienteTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  DFe.Ambiente;

type
  [TestFixture]
  TDFeAmbienteTests = class
  public
    [Test] procedure RelatorioVazio_EhCompleto;
    [Test] procedure ObrigatoriaAusente_ReprovaOAmbiente;
    [Test] procedure OpcionalAusente_NaoReprova;
    [Test] procedure QuantidadeObrigatoriasAusentes_ContaSoAsObrigatorias;
    [Test] procedure Formatar_MarcaOkFaltaEOpcionalEMostraCorrecaoSoNasAusentes;
    [Test] procedure Mensagem_TrazSoObrigatoriasAusentesComDetalheECorrecao;
    [Test] procedure Mensagem_AmbienteCompleto_EhVazia;
  end;

implementation

function RelatorioDeTeste: TDFeRelatorioAmbiente;
begin
  Result.Itens := nil;
  AdicionarDependencia(Result, 'OpenSSL', True, True, 'OpenSSL 3.5.4', '');
  AdicionarDependencia(Result, 'libxml2', False, False, 'nao carregou', 'copie libxml2.dll');
  AdicionarDependencia(Result, 'XSDs', True, False, 'pasta inexistente: C:\x\', 'copie os XSDs');
end;

procedure TDFeAmbienteTests.RelatorioVazio_EhCompleto;
var
  R: TDFeRelatorioAmbiente;
begin
  R.Itens := nil;
  Assert.IsTrue(AmbienteCompleto(R));
  Assert.AreEqual(0, QuantidadeObrigatoriasAusentes(R));
end;

procedure TDFeAmbienteTests.ObrigatoriaAusente_ReprovaOAmbiente;
begin
  Assert.IsFalse(AmbienteCompleto(RelatorioDeTeste));
end;

procedure TDFeAmbienteTests.OpcionalAusente_NaoReprova;
var
  R: TDFeRelatorioAmbiente;
begin
  R.Itens := nil;
  AdicionarDependencia(R, 'OpenSSL', True, True, 'ok', '');
  AdicionarDependencia(R, 'libxml2', False, False, 'nao carregou', 'copie');
  Assert.IsTrue(AmbienteCompleto(R));
end;

procedure TDFeAmbienteTests.QuantidadeObrigatoriasAusentes_ContaSoAsObrigatorias;
begin
  Assert.AreEqual(1, QuantidadeObrigatoriasAusentes(RelatorioDeTeste)); // XSDs; libxml2 e' opcional
end;

procedure TDFeAmbienteTests.Formatar_MarcaOkFaltaEOpcionalEMostraCorrecaoSoNasAusentes;
var
  LTexto: string;
begin
  LTexto := FormatarRelatorio(RelatorioDeTeste);
  Assert.IsTrue(Pos('[OK]       OpenSSL -- OpenSSL 3.5.4', LTexto) > 0, 'OK');
  Assert.IsTrue(Pos('[opcional] libxml2 -- nao carregou', LTexto) > 0, 'opcional');
  Assert.IsTrue(Pos('[FALTA]    XSDs -- pasta inexistente', LTexto) > 0, 'falta');
  Assert.IsTrue(Pos('-> copie os XSDs', LTexto) > 0, 'correcao da ausente');
  Assert.IsTrue(Pos('-> copie libxml2.dll', LTexto) > 0, 'correcao da opcional ausente');
  Assert.IsTrue(Pos('-> ', Copy(LTexto, 1, Pos('[opcional]', LTexto))) = 0, 'presente nao mostra correcao');
end;

procedure TDFeAmbienteTests.Mensagem_TrazSoObrigatoriasAusentesComDetalheECorrecao;
var
  LMsg: string;
begin
  LMsg := MensagemAmbienteIncompleto(RelatorioDeTeste);
  Assert.IsTrue(Pos('Ambiente de execucao incompleto', LMsg) = 1, 'prefixo');
  Assert.IsTrue(Pos('XSDs: pasta inexistente', LMsg) > 0, 'XSDs e detalhe');
  Assert.IsTrue(Pos('(copie os XSDs)', LMsg) > 0, 'correcao');
  Assert.IsTrue(Pos('libxml2', LMsg) = 0, 'libxml2 opcional NAO entra');
  Assert.IsTrue(Pos('OpenSSL', LMsg) = 0, 'OpenSSL presente NAO entra');
end;

procedure TDFeAmbienteTests.Mensagem_AmbienteCompleto_EhVazia;
var
  R: TDFeRelatorioAmbiente;
begin
  R.Itens := nil;
  AdicionarDependencia(R, 'OpenSSL', True, True, 'ok', '');
  Assert.AreEqual('', MensagemAmbienteIncompleto(R));
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeAmbienteTests);

end.
