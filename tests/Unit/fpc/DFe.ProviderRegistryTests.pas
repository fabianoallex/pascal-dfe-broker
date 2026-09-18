unit DFe.ProviderRegistryTests;

{$mode delphi}{$H+}

interface

uses
  fpcunit, testregistry, SysUtils,
  DFe.Provider,
  DFe.TestDoubles;

type
  { TDFeProviderRegistry e' global (class var) por natureza -- ver
    comentario da declaracao em DFe.Provider.pas. Cada teste usa um
    Identificador exclusivo pra nao colidir com outros testes rodando no
    mesmo processo (nao ha metodo de reset, de proposito: nao existe
    "desregistrar" um provider de verdade em producao). }
  TDFeProviderRegistryTests = class(TTestCase)
  private
    procedure DoRegistrarDuplicado;
  published
    procedure Registrar_DepoisEncontraPorIdentificador;
    procedure ObterPorIdentificador_NaoEncontrado_RetornaNil;
    procedure Registrar_IdentificadorDuplicado_Levanta;
    procedure Todos_ContemProviderRegistrado;
    procedure Todos_DevolveCopiaIndependente;
  end;

implementation

{ TDFeProviderRegistryTests }

procedure TDFeProviderRegistryTests.DoRegistrarDuplicado;
var
  LFake: IDFeProvider;
begin
  { Atribuir a uma variavel local antes de passar para Registrar, em vez de
    construir inline como argumento -- medido nesta maquina: quando
    Registrar levanta excecao, o FPC 3.2.2 nao libera corretamente uma
    interface temporaria criada direto no argumento da chamada (vazamento
    real, achado por heaptrc). Atribuir a uma variavel local usa o caminho
    normal de finalizacao de variavel gerenciada, que e' seguro em
    unwind de excecao. }
  LFake := TDFeProviderFake.Create('teste-registry-duplicado');
  TDFeProviderRegistry.Registrar(LFake);
end;

procedure TDFeProviderRegistryTests.Registrar_DepoisEncontraPorIdentificador;
var
  LFake: IDFeProvider;
  LEncontrado: IDFeProvider;
begin
  LFake := TDFeProviderFake.Create('teste-registry-encontra');
  TDFeProviderRegistry.Registrar(LFake);

  LEncontrado := TDFeProviderRegistry.ObterPorIdentificador('teste-registry-encontra');

  AssertTrue(Assigned(LEncontrado));
  AssertEquals('teste-registry-encontra', LEncontrado.Identificador);
end;

procedure TDFeProviderRegistryTests.ObterPorIdentificador_NaoEncontrado_RetornaNil;
begin
  AssertFalse(Assigned(TDFeProviderRegistry.ObterPorIdentificador('teste-registry-inexistente-xyz123')));
end;

procedure TDFeProviderRegistryTests.Registrar_IdentificadorDuplicado_Levanta;
begin
  TDFeProviderRegistry.Registrar(TDFeProviderFake.Create('teste-registry-duplicado'));
  AssertException(Exception, DoRegistrarDuplicado);
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

  AssertTrue(LEncontrou);
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
  AssertTrue(Assigned(TDFeProviderRegistry.ObterPorIdentificador('teste-registry-independencia')));
end;

initialization
  RegisterTest(TDFeProviderRegistryTests);

end.
