# Serviço Windows (`DFeBrokerServico`)

Host do pascal-dfe-broker como Serviço Windows. **Delphi-only** (Win64) — um serviço é uma noção inerentemente Windows; em Lazarus/Windows use o host console (`hosts/console`). É o mesmo core do console (`TDFeAplicacao`): mesmo `dfe.ini`, mesmo comportamento; só muda o log (arquivo, sem console) e o ciclo de vida (Iniciar/Parar do SCM).

> **Estado (2026-09-19):** verificado em Windows 11 (Delphi Win64, instalado com `/install`, LocalSystem): sobe, escuta, para e reinicia limpo, e a falha de subida aparece no log e no Event Log. **Não verificado:** parada com tick em andamento, conta `NT SERVICE\...` e, como em todo o projeto, **certificado real / SEFAZ real** (ver `CLAUDE.md`, decisão 20). Teste primeiro com o console (`hosts/console`) usando o mesmo `dfe.ini`; só então instale o serviço.

## Antes de instalar

1. **Rode o console com a mesma config** e confira que o relatório de ambiente sai todo `[OK]` (`DFeBrokerConsole.exe --config C:\dfe\dfe.ini --verificar-ambiente`).
2. **DLLs ao lado do executável.** O serviço **não** enxerga o PATH do *seu usuário* — só o do sistema. Copie para a pasta do `DFeBrokerServico.exe` (64 bits, como o executável) estes 4 arquivos, **todos da mesma pasta**:

   ```powershell
   $pg = 'C:\Program Files\PostgreSQL\18\bin'   # se você tem o PostgreSQL 18 instalado
   Copy-Item "$pg\libssl-3-x64.dll", "$pg\libcrypto-3-x64.dll", "$pg\libxml2.dll", "$pg\zlib1.dll" C:\dfe\
   ```

   Verificado (2026-09-19): numa pasta só com o `.exe` do console e essas 4 DLLs, **com o PATH reduzido ao do Windows**, o relatório de ambiente carrega OpenSSL 3.5.4 e libxml2 sem depender de mais nada. **Não misture origens**: `libssl` e `libcrypto` têm de ser da mesma versão (numa máquina de teste o PATH trouxe a `libssl` 3.5.4 do PostgreSQL com a `libcrypto` 3.4.0 do Tesseract-OCR — funciona por sorte, e não deve ser usado). Sem o PostgreSQL: o Git for Windows tem o par OpenSSL em `C:\Program Files\Git\mingw64\bin` (3.2.4), e a libxml2 x64 precisa vir de outra fonte (`docs/dependencias-runtime.md`, "Como obter"). Confirme com `DFeBrokerConsole.exe --config <ini> --verificar-ambiente` rodado **a partir dessa pasta**.
   
   **XSDs:** copie `vendor\ACBr\Exemplos\ACBrDFe\Schemas\NFe\*` para uma pasta (por exemplo `C:\dfe\Schemas\`) e ponha `PathSchemas=Schemas` no `[dfe]` do `dfe.ini`.
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

Alternativa sem `sc`: `DFeBrokerServico.exe /install` (usa `dfe.ini` ao lado do executável) e `/uninstall`. **`/install` não configura o reinício automático**: rode depois o `sc.exe failure ...` acima. Verificado (2026-09-19): com ele, matar o processo faz o Windows registrar "finalizado inesperadamente" e reiniciar o serviço sozinho; depois de 3 quedas dentro do prazo do `reset=` ele desiste de reiniciar (proteção contra loop).

**Conta:** o padrão (LocalSystem) funciona, mas o ideal é uma conta com o mínimo: `sc.exe config DFeBrokerService obj= "NT SERVICE\DFeBrokerService"` e dar a ela **leitura** no `.pfx` e no `dfe.ini` e **escrita** na pasta do `dfe.ini` (o cursor, o WAL do broker `broker\` e `logs\` ficam lá).

## Operação

| O quê | Onde |
|---|---|
| Log | `<pasta do dfe.ini>\logs\dfe-aaaammdd.log` (um por dia, hora de Brasília, UTF-8; **mantém 30 dias** e apaga os mais antigos uma vez por dia — ajuste com `LogRetencaoDias=` no `[dfe]` do `dfe.ini`, `0` = nunca apagar; só apaga arquivos que casam exatamente com `dfe-aaaammdd.log`) |
| Falha de subida | **Visualizador de Eventos → Windows Logs → Application**, origem `DFeBrokerService`, nível Erro: `pascal-dfe-broker nao iniciou: ...`. O Windows pode mostrar "a descrição da ID do evento 0 não pôde ser encontrada" — é normal (a origem não tem DLL de mensagens); o texto do erro vem logo abaixo, em "os seguintes dados foram incluídos". Detalhes no log acima. Um evento "o processo do serviço não pôde se conectar ao controlador" só significa que o `.exe` foi executado direto, fora do SCM |
| Parar | `sc.exe stop DFeBrokerService` — espera o tick em andamento terminar (até 60 s) |
| Broker AMQP | `BindAddress:Porta` do `[broker]` do `dfe.ini` (padrão `127.0.0.1:5672`); com `0.0.0.0` **troque `Usuario`/`Senha`** e libere a porta no firewall |

Se o serviço para logo depois de iniciar, quase sempre é ambiente incompleto (DLLs/XSDs) ou config inválida — o motivo está no log e no Event Log.
