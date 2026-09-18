program AcbrClientSmoke;

{ Programa de fumaca (smoke test) so' de compilacao -- ver
  AcbrClientSmoke.lpr (par FPC) para o comentario completo. Existe so'
  para confirmar que DFe.Client.ACBrNFe compila contra o vendor/ACBr
  (componentes classicos) nos dois compiladores, sem arrastar essa
  dependencia pro pacote principal nem pro test runner. }

{$APPTYPE CONSOLE}

uses
  DFe.Client.ACBrNFe in '..\..\src\DFe.Client.ACBrNFe.pas';

begin
  WriteLn('DFe.Client.ACBrNFe compilou.');
end.
