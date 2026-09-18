unit DFe.RoutingKeyTests;

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils,
  DFe.Types, DFe.RoutingKey;

type
  TDFeRoutingKeyTests = class(TTestCase)
  private
    FEventoSemTipoEvento: TDFeEventoNormalizado;
    procedure DoMontarRoutingKeySemTipoEvento;
  published
    procedure Documento_MontaTipoCategoriaUfCnpj;
    procedure Documento_LowercaseTipoDocumentoEUf_NaoMexeNoCnpj;
    procedure Evento_IncluiTipoEventoLowercase;
    procedure Evento_SemTipoEvento_Levanta;
  end;

implementation

function EventoBase: TDFeEventoNormalizado;
begin
  Result.TipoDocumento := 'nfe';
  Result.Categoria := dcDocumento;
  Result.TipoEvento := '';
  Result.ChaveAcesso := '';
  Result.CnpjCpfConsultante := '12345678000199';
  Result.UF := 'RS';
  Result.NSU := 0;
  Result.XmlPayload := '';
  Result.DataEmissao := 0;
end;

{ TDFeRoutingKeyTests }

procedure TDFeRoutingKeyTests.DoMontarRoutingKeySemTipoEvento;
begin
  MontarRoutingKey(FEventoSemTipoEvento);
end;

procedure TDFeRoutingKeyTests.Documento_MontaTipoCategoriaUfCnpj;
var
  LEvento: TDFeEventoNormalizado;
begin
  LEvento := EventoBase;
  AssertEquals('nfe.documento.rs.12345678000199', MontarRoutingKey(LEvento));
end;

procedure TDFeRoutingKeyTests.Documento_LowercaseTipoDocumentoEUf_NaoMexeNoCnpj;
var
  LEvento: TDFeEventoNormalizado;
begin
  LEvento := EventoBase;
  LEvento.TipoDocumento := 'NFE';
  LEvento.UF := 'RS';
  AssertEquals('nfe.documento.rs.12345678000199', MontarRoutingKey(LEvento));
end;

procedure TDFeRoutingKeyTests.Evento_IncluiTipoEventoLowercase;
var
  LEvento: TDFeEventoNormalizado;
begin
  LEvento := EventoBase;
  LEvento.Categoria := dcEvento;
  LEvento.TipoEvento := 'Cancelamento';
  AssertEquals('nfe.evento.cancelamento.rs.12345678000199', MontarRoutingKey(LEvento));
end;

procedure TDFeRoutingKeyTests.Evento_SemTipoEvento_Levanta;
begin
  // Sem metodo anonimo de proposito -- nao existe no FPC 3.2 (ver
  // ../../../CLAUDE.md, "Regras da codebase dual" do pascal-amqp-faa, que
  // vale aqui igual). AssertException exige um TRunMethod (procedure of
  // object), por isso o campo + metodo privado em vez de uma closure.
  FEventoSemTipoEvento := EventoBase;
  FEventoSemTipoEvento.Categoria := dcEvento;
  FEventoSemTipoEvento.TipoEvento := '';
  AssertException(Exception, DoMontarRoutingKeySemTipoEvento);
end;

initialization
  RegisterTest(TDFeRoutingKeyTests);

end.
