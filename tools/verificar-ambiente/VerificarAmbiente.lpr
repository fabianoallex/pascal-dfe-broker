program VerificarAmbiente;

{ Verifica o AMBIENTE DE EXECUCAO do broker -- OpenSSL, libxml2 e XSDs -- e diz o
  que falta e como corrigir. Rode no SERVIDOR, com o mesmo usuario e a mesma
  pasta do executavel do broker: o que importa e' o que ESTE processo enxerga.
  Ver docs/dependencias-runtime.md.

  Uso:
    VerificarAmbiente [pasta-de-schemas] [--distribuicao]

  pasta-de-schemas  padrao: "Schemas" ao lado deste executavel (o mesmo padrao
                    do ACBr; use a MESMA que o broker usara em PathSchemas)
  --distribuicao    verifica so' o necessario para consultar documentos (sem
                    libxml2 nem XSDs de evento); o padrao verifica tambem a
                    manifestacao do destinatario

  Codigo de saida: 0 = ambiente completo; 1 = falta algo obrigatorio; 2 = uso. }

{$mode delphi}{$H+}

uses
  Interfaces, // widgetset LCL: o ACBr arrasta LCL transitivamente (CLAUDE.md, gotchas)
  SysUtils,
  DFe.Ambiente,
  DFe.Ambiente.ACBr;

var
  LPasta: string;
  LUsos: TDFeUsosAmbiente;
  LRelatorio: TDFeRelatorioAmbiente;
  I: Integer;
begin
  LPasta := '';
  LUsos := [uaDistribuicao, uaManifestacao];
  for I := 1 to ParamCount do
    if ParamStr(I) = '--distribuicao' then
      LUsos := [uaDistribuicao]
    else if (ParamStr(I) = '-h') or (ParamStr(I) = '--help') or (ParamStr(I) = '/?') then
    begin
      WriteLn('uso: VerificarAmbiente [pasta-de-schemas] [--distribuicao]');
      Halt(2);
    end
    else
      LPasta := ParamStr(I);

  WriteLn('Executavel de ', SizeOf(Pointer) * 8, ' bits: ', ParamStr(0));
  LRelatorio := VerificarAmbienteACBr(LPasta, LUsos);
  Write(FormatarRelatorio(LRelatorio));
  if AmbienteCompleto(LRelatorio) then
  begin
    WriteLn('Ambiente COMPLETO.');
    Halt(0);
  end
  else
  begin
    WriteLn('Ambiente INCOMPLETO: ', QuantidadeObrigatoriasAusentes(LRelatorio),
      ' dependencia(s) obrigatoria(s) ausente(s).');
    Halt(1);
  end;
end.
