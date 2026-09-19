unit DFe.AmbienteTests;

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils,
  DFe.Ambiente;

type
  TDFeAmbienteTests = class(TTestCase)
  published
    procedure RelatorioVazio_EhCompleto;
    procedure ObrigatoriaAusente_ReprovaOAmbiente;
    procedure OpcionalAusente_NaoReprova;
    procedure QuantidadeObrigatoriasAusentes_ContaSoAsObrigatorias;
    procedure Formatar_MarcaOkFaltaEOpcionalEMostraCorrecaoSoNasAusentes;
    procedure Mensagem_TrazSoObrigatoriasAusentesComDetalheECorrecao;
    procedure Mensagem_AmbienteCompleto_EhVazia;
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
  AssertTrue(AmbienteCompleto(R));
  AssertEquals(0, QuantidadeObrigatoriasAusentes(R));
end;

procedure TDFeAmbienteTests.ObrigatoriaAusente_ReprovaOAmbiente;
begin
  AssertFalse(AmbienteCompleto(RelatorioDeTeste));
end;

procedure TDFeAmbienteTests.OpcionalAusente_NaoReprova;
var
  R: TDFeRelatorioAmbiente;
begin
  R.Itens := nil;
  AdicionarDependencia(R, 'OpenSSL', True, True, 'ok', '');
  AdicionarDependencia(R, 'libxml2', False, False, 'nao carregou', 'copie');
  AssertTrue(AmbienteCompleto(R));
end;

procedure TDFeAmbienteTests.QuantidadeObrigatoriasAusentes_ContaSoAsObrigatorias;
begin
  AssertEquals(1, QuantidadeObrigatoriasAusentes(RelatorioDeTeste)); // XSDs; libxml2 e' opcional
end;

procedure TDFeAmbienteTests.Formatar_MarcaOkFaltaEOpcionalEMostraCorrecaoSoNasAusentes;
var
  LTexto: string;
begin
  LTexto := FormatarRelatorio(RelatorioDeTeste);
  AssertTrue('OK', Pos('[OK]       OpenSSL -- OpenSSL 3.5.4', LTexto) > 0);
  AssertTrue('opcional', Pos('[opcional] libxml2 -- nao carregou', LTexto) > 0);
  AssertTrue('falta', Pos('[FALTA]    XSDs -- pasta inexistente', LTexto) > 0);
  AssertTrue('correcao da ausente', Pos('-> copie os XSDs', LTexto) > 0);
  AssertTrue('correcao da opcional ausente', Pos('-> copie libxml2.dll', LTexto) > 0);
  AssertTrue('presente nao mostra correcao', Pos('-> ', Copy(LTexto, 1, Pos('[opcional]', LTexto))) = 0);
end;

procedure TDFeAmbienteTests.Mensagem_TrazSoObrigatoriasAusentesComDetalheECorrecao;
var
  LMsg: string;
begin
  LMsg := MensagemAmbienteIncompleto(RelatorioDeTeste);
  AssertTrue('prefixo', Pos('Ambiente de execucao incompleto', LMsg) = 1);
  AssertTrue('XSDs e detalhe', Pos('XSDs: pasta inexistente', LMsg) > 0);
  AssertTrue('correcao', Pos('(copie os XSDs)', LMsg) > 0);
  AssertTrue('libxml2 opcional NAO entra', Pos('libxml2', LMsg) = 0);
  AssertTrue('OpenSSL presente NAO entra', Pos('OpenSSL', LMsg) = 0);
end;

procedure TDFeAmbienteTests.Mensagem_AmbienteCompleto_EhVazia;
var
  R: TDFeRelatorioAmbiente;
begin
  R.Itens := nil;
  AdicionarDependencia(R, 'OpenSSL', True, True, 'ok', '');
  AssertEquals('', MensagemAmbienteIncompleto(R));
end;

initialization
  RegisterTest(TDFeAmbienteTests);

end.
