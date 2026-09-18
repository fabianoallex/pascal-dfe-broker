unit DFe.ProviderRegistryTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  DFe.Provider,
  DFe.TestDoubles;

type
  { TDFeProviderRegistry e' global (class var) por natureza -- ver
    comentario da declaracao em DFe.Provider.pas. Cada teste usa um
    Identificador exclusivo pra nao colidir com outros testes rodando no
    mesmo processo (nao ha metodo de reset, de proposito: nao existe
    "desregistrar" um provider de verdade em producao). }
  [TestFixture]
  TDFeProviderRegistryTests = class
  public
    [Test] procedure Registrar_DepoisEncontraPorIdentificador;
    [Test] procedure ObterPorIdentificador_NaoEncontrado_RetornaNil;
    [Test] procedure Registrar_IdentificadorDuplicado_Levanta;
    [Test] procedure Todos_ContemProviderRegistrado;
    [Test] procedure Todos_DevolveCopiaIndependente;
  end;

implementation

{ TDFeProviderRegistryTests }

procedure TDFeProviderRegistryTests.Registrar_DepoisEncontraPorIdentificador;
var
  LFake: IDFeProvider;
  LEncontrado: IDFeProvider;
begin
  LFake := TDFeProviderFake.Create('teste-registry-encontra');
  TDFeProviderRegistry.Registrar(LFake);

  LEncontrado := TDFeProviderRegistry.ObterPorIdentificador('teste-registry-encontra');

  Assert.IsTrue(Assigned(LEncontrado));
  Assert.AreEqual('teste-registry-encontra', LEncontrado.Identificador);
end;

procedure TDFeProviderRegistryTests.ObterPorIdentificador_NaoEncontrado_RetornaNil;
begin
  Assert.IsFalse(Assigned(TDFeProviderRegistry.ObterPorIdentificador('teste-registry-inexistente-xyz123')));
end;

procedure TDFeProviderRegistryTests.Registrar_IdentificadorDuplicado_Levanta;
begin
  TDFeProviderRegistry.Registrar(TDFeProviderFake.Create('teste-registry-duplicado'));

  { Atribuir a uma variavel local antes de passar para Registrar, em vez de
    construir inline como argumento -- o espelho FPCUnit (tests/Unit/fpc/)
    mediu com heaptrc que o FPC 3.2.2 nao libera corretamente uma interface
    temporaria criada direto no argumento quando a chamada levanta excecao.
    Sem certeza se o Delphi tem o mesmo problema, mas o padrao abaixo e'
    seguro nos dois. }
  Assert.WillRaise(
    procedure
    var
      LFake: IDFeProvider;
    begin
      LFake := TDFeProviderFake.Create('teste-registry-duplicado');
      TDFeProviderRegistry.Registrar(LFake);
    end,
    Exception);
end;

procedure TDFeProviderRegistryTests.Todos_ContemProviderRegistrado;
var
  LTodos: TDFeProviderArray;
  LEncontrou: Boolean;
  I: Integer;
begin
  TDFeProviderRegistry.Registrar(TDFeProviderFake.Create('teste-registry-todos'));

  LTodos := TDFeProviderRegistry.Todos;
  LEncontrou := False;
  for I := 0 to High(LTodos) do
    if LTodos[I].Identificador = 'teste-registry-todos' then
      LEncontrou := True;

  Assert.IsTrue(LEncontrou);
end;

procedure TDFeProviderRegistryTests.Todos_DevolveCopiaIndependente;
var
  LTodos: TDFeProviderArray;
  I: Integer;
begin
  TDFeProviderRegistry.Registrar(TDFeProviderFake.Create('teste-registry-independencia'));

  LTodos := TDFeProviderRegistry.Todos;
  for I := 0 to High(LTodos) do
    if LTodos[I].Identificador = 'teste-registry-independencia' then
      LTodos[I] := nil; // mutando a copia devolvida

  // o registry interno nao pode ter sido afetado pela mutacao acima
  Assert.IsTrue(Assigned(TDFeProviderRegistry.ObterPorIdentificador('teste-registry-independencia')));
end;

initialization
  TDUnitX.RegisterTestFixture(TDFeProviderRegistryTests);

end.
