program DFeBrokerConsole;

{ Host CONSOLE do pascal-dfe-broker (decisao 9): o broker AMQP embutido, o
  poller de Distribuicao de DFe e a manifestacao, num processo so'. Mesmo fonte
  para Delphi e FPC. No Linux e' o host de PRODUCAO, rodado sob systemd
  (Type=simple, Restart=on-failure) -- sem daemonizacao propria; no Windows serve
  para desenvolvimento e para quem nao quer um Servico.

    DFeBrokerConsole [--config <dfe.ini>] [--verificar-ambiente] [--ajuda]

  --config              padrao: dfe.ini ao lado do executavel.
  --verificar-ambiente  so' confere OpenSSL / libxml2 / XSDs, imprime e sai
                        (0 = completo, 2 = falta algo obrigatorio).

  Codigos de saida: 0 encerrou por Ctrl+C/SIGTERM; 1 falha na subida (config,
  porta, broker externo); 2 ambiente de execucao incompleto.

  Parada: Ctrl+C (ou SIGTERM). O processo termina o tick em andamento e sai.

  Formato do arquivo de configuracao: DFe.Config e DFe.Host.ACBr; exemplo em
  hosts/console/dfe.exemplo.ini. }

{$IFDEF FPC}
{$MODE DELPHI}{$H+}
{$ENDIF}
{$APPTYPE CONSOLE}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF FPC}
  Interfaces, // widgetset LCL: TACBrNFe arrasta LCL transitivamente (ver CLAUDE.md, gotchas)
  {$ENDIF}
  SysUtils, SyncObjs,
  DFe.Ambiente,
  DFe.Fuso,
  DFe.Host.ACBr,
  DFe.Host.Aplicacao,
  DFe.Host.Sinais;

type
  TLogConsole = class
  private
    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Registrar(const ANivel, AMensagem: string);
  end;

constructor TLogConsole.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
end;

destructor TLogConsole.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TLogConsole.Registrar(const ANivel, AMensagem: string);
begin
  // chamado tambem de threads do pool do cliente AMQP: uma linha por vez
  FLock.Enter;
  try
    // Hora de Brasilia com o sufixo explicito, igual em qualquer plataforma: no
    // FPC/Linux `Now` e' UTC e no Windows e' local (ver DFe.Fuso, docs/linux.md).
    WriteLn(FormatDateTime('yyyy-mm-dd hh:nn:ss', AgoraDeBrasilia), DFE_FUSO_BRASILIA,
      ' [', ANivel, '] ', AMensagem);
    // Sem isto, com a saida redirecionada (journald sob systemd, arquivo) o FPC
    // guarda as linhas em buffer: o log sai atrasado e uma queda (SIGKILL) o perde.
    Flush(Output);
  finally
    FLock.Leave;
  end;
end;

procedure Ajuda;
begin
  WriteLn('pascal-dfe-broker (host console)');
  WriteLn;
  WriteLn('  DFeBrokerConsole [--config <dfe.ini>] [--verificar-ambiente] [--ajuda]');
  WriteLn;
  WriteLn('  --config <arquivo>     arquivo de configuracao (padrao: dfe.ini ao lado do executavel)');
  WriteLn('  --verificar-ambiente   confere OpenSSL, libxml2 e XSDs; sai com 0 (ok) ou 2 (falta algo)');
  WriteLn('  --ajuda                esta mensagem');
end;

var
  GCaminhoConfig: string;
  GSoVerificar: Boolean;
  GLog: TLogConsole;
  GFabrica: TDFeFabricaClientesACBr;
  GApp: TDFeAplicacao;
  GRelatorio: TDFeRelatorioAmbiente;
  I: Integer;
begin
  {$IFDEF FPC}
  SetMultiByteConversionCodePage(CP_UTF8); // ver "Encoding do XML" em docs/architecture.md
  {$ENDIF}
  ExitCode := 0;

  GCaminhoConfig := ExtractFilePath(ParamStr(0)) + 'dfe.ini';
  GSoVerificar := False;
  I := 1;
  while I <= ParamCount do
  begin
    if (ParamStr(I) = '--config') and (I < ParamCount) then
    begin
      Inc(I);
      GCaminhoConfig := ParamStr(I);
    end
    else if ParamStr(I) = '--verificar-ambiente' then
      GSoVerificar := True
    else if (ParamStr(I) = '--ajuda') or (ParamStr(I) = '-h') or (ParamStr(I) = '--help') then
    begin
      Ajuda;
      Exit;
    end
    else
    begin
      WriteLn('Argumento desconhecido: ', ParamStr(I));
      Ajuda;
      ExitCode := 1;
      Exit;
    end;
    Inc(I);
  end;

  GLog := TLogConsole.Create;
  GFabrica := TDFeFabricaClientesACBr.Create(GCaminhoConfig);
  GApp := nil;
  try
    try
      if not FileExists(GCaminhoConfig) then
      begin
        GLog.Registrar('ERRO', 'Arquivo de configuracao nao encontrado: ' + ExpandFileName(GCaminhoConfig));
        ExitCode := 1;
        Exit;
      end;

      GRelatorio := GFabrica.VerificarAmbiente;
      WriteLn(FormatarRelatorio(GRelatorio));
      if not AmbienteCompleto(GRelatorio) then
      begin
        GLog.Registrar('ERRO', 'Ambiente de execucao incompleto -- corrija o que esta marcado [FALTA] (docs/dependencias-runtime.md)');
        ExitCode := 2;
        Exit;
      end;
      if GSoVerificar then
        Exit;

      GApp := TDFeAplicacao.Create(GCaminhoConfig, GFabrica.CriarClient, GLog.Registrar);
      GApp.Iniciar;
      InstalarTratadorDeParada(GApp.Parar);
      GLog.Registrar('INFO', 'Em execucao. Ctrl+C ou SIGTERM para parar.');
      GApp.Executar;
      GLog.Registrar('INFO', 'Encerrando.');
    except
      on E: Exception do
      begin
        GLog.Registrar('ERRO', E.ClassName + ': ' + E.Message);
        ExitCode := 1;
      end;
    end;
  finally
    GApp.Free;
    GFabrica.Free;
    GLog.Free;
  end;
end.
