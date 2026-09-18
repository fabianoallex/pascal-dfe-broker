program AcbrClientSmoke;

{ Programa de fumaca (smoke test) so' de compilacao -- nao roda nada de
  verdade (ver DFe.Client.ACBrNFe, comentario de topo: sem certificado
  real nesta maquina, nao da' pra' testar em execucao). Existe so' para
  confirmar que DFe.Client.ACBrNFe compila contra o vendor/ACBr
  (componentes classicos) nos dois compiladores, sem arrastar essa
  dependencia pro pacote principal (packages/pascal_dfe_broker.lpk) nem
  pro test runner -- ver CLAUDE.md, decisao 15, e docs/architecture.md,
  "Fonte dos componentes classicos". Apagar/mover quando um host real
  (.dpr/.lpr) existir e assumir esse papel. }

{$mode delphi}{$H+}

uses
  Interfaces,
  DFe.Client.ACBrNFe;

begin
  WriteLn('DFe.Client.ACBrNFe compilou.');
end.
