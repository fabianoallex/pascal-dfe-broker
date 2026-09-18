unit DFe.RoutingKeyTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  DFe.Types,
  DFe.RoutingKey;

type
  [TestFixture]
  TDFeRoutingKeyTests = class
  public
    [Test] procedure Documento_MontaTipoCategoriaUfCnpj;
    [Test] procedure Documento_LowercaseTipoDocumentoEUf_NaoMexeNoCnpj;
    [Test] procedure Evento_IncluiTipoEventoLowercase;
    [Test] procedure Evento_SemTipoEvento_Levanta;
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

procedure TDFeRoutingKeyTests.Documento_MontaTipoCategoriaUfCnpj;
var
  LEvento: TDFeEventoNormalizado;
begin
  LEvento := EventoBase;
  Assert.AreEqual('nfe.documento.rs.12345678000199', MontarRoutingKey(LEvento));
end;

procedure TDFeRoutingKeyTests.Documento_LowercaseTipoDocumentoEUf_NaoMexeNoCnpj;
var
  LEvento: TDFeEventoNormalizado;
begin
  LEvento := EventoBase;
  LEvento.TipoDocumento := 'NFE';
  LEvento.UF := 'RS';
  Assert.AreEqual('nfe.documento.rs.12345678000199', MontarRoutingKey(LEvento));
end;

procedure TDFeRoutingKeyTests.Evento_IncluiTipoEventoLowercase;
var
  LEvento: TDFeEventoNormalizado;
begin
  LEvento := EventoBase;
  LEvento.Categoria := dcEvento;
  LEvento.TipoEvento := 'Cancelamento';
  Assert.AreEqual('nfe.evento.cancelamento.rs.12345678000199', MontarRoutingKey(LEvento));
end;

procedure TDFeRoutingKeyTests.Evento_SemTipoEvento_Levanta;
var
  LEvento: TDFeEventoNormalizado;
begin
  LEvento := EventoBase;
  LEvento.Categoria := dcEvento;
  LEvento.TipoEvento := '';
  Assert.WillRaise(
    procedure
    begin
      MontarRoutingKey(LEvento);
    end,
    Exception);
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeRoutingKeyTests);

end.
