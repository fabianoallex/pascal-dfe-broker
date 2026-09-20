unit DFe.Simulador.Principal;

{ O programa DFeSimulador em si (argumentos, cenario, Horse), numa unit para o
  .lpr (FPC) e o .dpr (Delphi) ficarem finos e iguais.

  ATENCAO: nao e' a SEFAZ. Responde conforme a LEITURA que o projeto faz das NTs
  (docs/referencias/), so' para teste. Ver simulador/LEIAME.md e
  docs/simulador-standalone.md. }

{$IFDEF FPC}
  {$MODE DELPHI}{$H+}
{$ENDIF}

interface

procedure Executar;

implementation

uses
  {$IFDEF FPC}
  SysUtils,
  {$ELSE}
  System.SysUtils, System.Classes,
  {$ENDIF}
  Horse,
  DFe.Simulador,
  DFe.Simulador.Relogio,
  DFe.Simulador.Servidor,
  DFe.Simulador.Regras,
  DFe.Simulador.Cenario,
  DFe.Simulador.Horse;

const
  PORTA_PADRAO = 9200;

var
  GPorta: Integer;
  GBind, GCenario: string;
  GSim: TDFeSimuladorSefaz;
  GRelogio: TDFeRelogioVirtual;
  GEstrito: Boolean;
  GServidor: TDFeSimuladorServidor;
  GResumo: TDFeCenarioResumo;
  I: Integer;

procedure Ajuda;
begin
  Writeln('DFeSimulador -- simulador da SEFAZ (Distribuicao de DFe / manifestacao da NFe)');
  Writeln;
  Writeln('  --porta <n>        porta HTTP (padrao ', PORTA_PADRAO, ')');
  Writeln('  --bind <endereco>  endereco de escuta (padrao 127.0.0.1; 0.0.0.0 = a rede toda, SEM autenticacao)');
  Writeln('  --cenario <ini>    cenario declarativo (contas, documentos, falhas); ver simulador/LEIAME.md');
  Writeln('  --estrito          recusa (HTTP 400) requisicao fora do formato esperado (padrao: aceita e registra)');
  Writeln('  --ajuda            esta mensagem');
  Writeln;
  Writeln('Extensao em Pascal: ver simulador/exemplos/ (regras registradas por initialization).');
  Writeln;
  Writeln('NAO e'' a SEFAZ: responde conforme a leitura do projeto das NTs, so'' para teste.');
end;

procedure Anunciar;
begin
  Writeln('DFeSimulador escutando em http://', GBind, ':', GPorta, ' (Ctrl+C para parar)');
  Flush(Output);
end;

function LerArgumentos: Boolean;
var
  I: Integer;
begin
  Result := True;
  GPorta := PORTA_PADRAO;
  GBind := '127.0.0.1';
  GCenario := '';
  GEstrito := False;
  I := 1;
  while I <= ParamCount do
  begin
    if SameText(ParamStr(I), '--porta') and (I < ParamCount) then
    begin
      Inc(I);
      GPorta := StrToIntDef(ParamStr(I), -1);
      if (GPorta < 1) or (GPorta > 65535) then
      begin
        Writeln('Porta invalida: ', ParamStr(I));
        Exit(False);
      end;
    end
    else if SameText(ParamStr(I), '--bind') and (I < ParamCount) then
    begin
      Inc(I);
      GBind := ParamStr(I);
    end
    else if SameText(ParamStr(I), '--estrito') then
      GEstrito := True
    else if SameText(ParamStr(I), '--cenario') and (I < ParamCount) then
    begin
      Inc(I);
      GCenario := ParamStr(I);
    end
    else
    begin
      if not SameText(ParamStr(I), '--ajuda') then
        Writeln('Argumento desconhecido: ', ParamStr(I));
      Ajuda;
      Exit(False);
    end;
    Inc(I);
  end;
end;

procedure Executar;
begin
  if not LerArgumentos then
  begin
    ExitCode := 1;
    Exit;
  end;

  GRelogio := TDFeRelogioVirtual.Create;
  GSim := TDFeSimuladorSefaz.Create(GRelogio.Agora);
  GServidor := TDFeSimuladorServidor.Create(GSim, GRelogio);
  try
    try
      GServidor.Estrito := GEstrito;
      if GEstrito then
        Writeln('Modo ESTRITO: requisicao fora do formato esperado e'' recusada com HTTP 400.');
      if GCenario <> '' then
      begin
        GResumo := CarregarCenario(GCenario, GSim);
        Writeln('Cenario "', GCenario, '": ', GResumo.Contas, ' conta(s), ',
          GResumo.Documentos, ' documento(s), ', GResumo.Falhas, ' falha(s) enfileirada(s)');
      end
      else
        Writeln('Sem cenario: nenhuma conta nem documento (use --cenario).');

      // regras do usuario (DFe.Simulador.Regras): as units delas, se linkadas no
      // programa, se registram sozinhas; o simulador puro nao tem nenhuma
      GServidor.AdicionarRegrasRegistradas;
      for I := 0 to GServidor.Regras - 1 do
        Writeln('Regra "', GServidor.Regra(I).Nome, '"', ' (',
          BoolToStr(GServidor.Regra(I).Ativa, True), '): ', GServidor.Regra(I).Descricao);

      RegistrarRotas(GServidor);
      THorse.Listen(GPorta, GBind, Anunciar);
      {$IFNDEF FPC}
      // Delphi (Indy): Listen nao bloqueia -- espera enquanto o servidor roda
      while THorse.IsRunning do
        TThread.Sleep(1000);
      {$ENDIF}
    except
      on E: Exception do
      begin
        Writeln('ERRO: ', E.Message);
        ExitCode := 2;
      end;
    end;
  finally
    GServidor.Free; // antes do simulador
    GSim.Free;
    GRelogio.Free;
  end;
end;

end.
