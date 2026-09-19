# Serviço Windows (`DFeBrokerServico`)

Host do pascal-dfe-broker como Serviço Windows. **Delphi-only** (Win64) — um serviço é uma noção inerentemente Windows; em Lazarus/Windows use o host console (`hosts/console`). É o mesmo core do console (`TDFeAplicacao`): mesmo `dfe.ini`, mesmo comportamento; só muda o log (arquivo, sem console) e o ciclo de vida (Iniciar/Parar do SCM).

> **Estado:** compila e roda como serviço **não foi verificado pelo autor** (ver `CLAUDE.md`, decisão 20). Teste primeiro com o console (`hosts/console`) usando o mesmo `dfe.ini`; só então instale o serviço.

## Antes de instalar

1. **Rode o console com a mesma config** e confira que o relatório de ambiente sai todo `[OK]` (`DFeBrokerConsole.exe --config C:\dfe\dfe.ini --verificar-ambiente`).
2. **DLLs ao lado do executável.** O serviço **não** enxerga o PATH do *seu usuário* — só o do sistema. Copie para a pasta do `DFeBrokerServico.exe` o par `libssl-3-x64.dll` + `libcrypto-3-x64.dll` **do mesmo pacote** e a `libxml2.dll` x64 (ver `docs/dependencias-runtime.md`).
3. **Caminhos absolutos.** O diretório corrente de um serviço é `C:\Windows\System32`. `ArquivoPFX`, `PathSchemas`, `CursorPath` e `DataDir` relativos valem em relação à **pasta do `dfe.ini`** (regra do projeto), então isso já funciona — mas passe `--config` **absoluto**.
4. **Senha do certificado:** prefira `SenhaEnv=NOME` no INI e defina `NOME` como variável de ambiente **do sistema** (`setx NOME "senha" /M`, PowerShell como administrador); reinicie o serviço depois. O arquivo de config não deve guardar segredo.

## Instalar (PowerShell como administrador)

```powershell
$exe = 'C:\dfe\DFeBrokerServico.exe'
$ini = 'C:\dfe\dfe.ini'
sc.exe create DFeBrokerService binPath= "`"$exe`" --config `"$ini`"" start= delayed-auto DisplayName= "pascal-dfe-broker"
sc.exe description DFeBrokerService "Distribuicao de DFe (SEFAZ) publicada em filas AMQP"
# reinicia sozinho se cair (60 s entre tentativas; zera a contagem apos 1 dia)
sc.exe failure DFeBrokerService reset= 86400 actions= restart/60000/restart/60000/restart/60000
sc.exe start DFeBrokerService
```

Alternativa sem `sc`: `DFeBrokerServico.exe /install` (usa `dfe.ini` ao lado do executável) e `/uninstall`.

**Conta:** o padrão (LocalSystem) funciona, mas o ideal é uma conta com o mínimo: `sc.exe config DFeBrokerService obj= "NT SERVICE\DFeBrokerService"` e dar a ela **leitura** no `.pfx` e no `dfe.ini` e **escrita** na pasta do `dfe.ini` (o cursor, o WAL do broker `broker\` e `logs\` ficam lá).

## Operação

| O quê | Onde |
|---|---|
| Log | `<pasta do dfe.ini>\logs\dfe-aaaammdd.log` (um por dia, hora de Brasília, UTF-8; **não há retenção** — apague os antigos) |
| Falha de subida | **Visualizador de Eventos → Windows Logs → Application** (o serviço "não inicia"); detalhes no log acima |
| Parar | `sc.exe stop DFeBrokerService` — espera o tick em andamento terminar (até 60 s) |
| Broker AMQP | `BindAddress:Porta` do `[broker]` do `dfe.ini` (padrão `127.0.0.1:5672`); com `0.0.0.0` **troque `Usuario`/`Senha`** e libere a porta no firewall |

Se o serviço para logo depois de iniciar, quase sempre é ambiente incompleto (DLLs/XSDs) ou config inválida — o motivo está no log e no Event Log.
