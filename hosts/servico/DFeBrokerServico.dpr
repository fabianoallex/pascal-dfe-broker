program DFeBrokerServico;

{ Host SERVICO WINDOWS do pascal-dfe-broker (decisao 9, Delphi-only). Ver
  DFe.Host.Servico e LEIAME.md.

    DFeBrokerServico.exe /install     registra o servico (config: dfe.ini ao lado do exe)
    DFeBrokerServico.exe /uninstall   remove

  Para apontar outro arquivo de config, registre com 'sc create' e coloque
  --config <caminho absoluto> no binPath (ver LEIAME.md).

  PLATAFORMA: Win64 (as DLLs de OpenSSL e libxml2 desta maquina sao x64). }

uses
  Vcl.SvcMgr,
  DFe.Host.Servico in 'DFe.Host.Servico.pas' {DFeBrokerService: TService};

begin
  // O Windows Server 2003 exige StartServiceCtrlDispatcher antes de
  // CoRegisterClassObject: por isso o Initialize so' roda cedo na instalacao.
  if not Application.DelayInitialize or Application.Installing then
    Application.Initialize;
  Application.CreateForm(TDFeBrokerService, DFeBrokerService);
  Application.Run;
end.
