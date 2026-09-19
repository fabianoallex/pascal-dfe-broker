# pascal-dfe-broker sob systemd (Linux)

No Linux o host console **é** o host de produção (decisão 9): o systemd cuida de iniciar no boot, reiniciar se cair e capturar o log — o processo não faz fork nem PID file. Arquivos desta pasta:

| Arquivo | Para quê |
|---|---|
| `dfe-broker.service` | a unit (comentada linha a linha) |
| `dfe.ini.exemplo` | config com caminhos **absolutos** para o layout abaixo |

> **Verificado** (Debian 12, Docker com systemd como PID 1, `tools/docker/testar-systemd.sh`): a unit é válida (`systemd-analyze verify`), sobe como usuário não-root, cria o `StateDirectory`, `ProtectSystem=strict` barra escrita em `/etc`, `SIGKILL` reinicia sozinho (PID novo, `NRestarts=1`), `systemctl stop` sai com código 0, e ambiente incompleto (exit 2) **não** entra em loop. **Não verificado:** máquina real (não contêiner), Ubuntu/outras versões do systemd, **certificado real / SEFAZ real**.

## Layout

```
/opt/dfe-broker/DFeBrokerConsole     executável (0755)
/opt/dfe-broker/Schemas/             XSDs oficiais de NFe
/etc/dfe-broker/dfe.ini              config (0640 root:dfe)
/etc/dfe-broker/certs/*.pfx          certificados (0640 root:dfe)
/etc/dfe-broker/dfe.env              senhas (0600 root:root)
/var/lib/dfe-broker/                 cursor e WAL do broker (criado pelo systemd, dono dfe)
```

**Por que caminhos absolutos no INI:** o padrão do projeto é resolver `CursorPath`/`DataDir` em relação à pasta do `dfe.ini`, mas `/etc` é somente-leitura para o serviço (`ProtectSystem=strict`); por isso o `dfe.ini.exemplo` já aponta `CursorPath` e `DataDir` para `/var/lib/dfe-broker`.

## Instalar (como root)

```bash
# 1. dependências de execução (ver docs/dependencias-runtime.md)
apt install libssl3 libxml2
ln -s /usr/lib/x86_64-linux-gnu/libxml2.so.2 /usr/lib/x86_64-linux-gnu/libxml2.so   # o ACBr procura este nome; ou: apt install libxml2-dev

# 2. usuário sem login
useradd --system --no-create-home --shell /usr/sbin/nologin dfe

# 3. arquivos (o executável vem de: lazbuild hosts/console/DFeBrokerConsole.lpi, com o backend LCL nogui -- docs/linux.md)
install -d /opt/dfe-broker /etc/dfe-broker/certs
install -m 0755 DFeBrokerConsole /opt/dfe-broker/
cp -r vendor/ACBr/Exemplos/ACBrDFe/Schemas/NFe /opt/dfe-broker/Schemas
install -m 0640 -o root -g dfe hosts/console/systemd/dfe.ini.exemplo /etc/dfe-broker/dfe.ini   # edite CNPJ, UF, filas...
install -m 0640 -o root -g dfe matriz.pfx /etc/dfe-broker/certs/
install -m 0600 /dev/null /etc/dfe-broker/dfe.env && echo 'DFE_SENHA_MATRIZ=...' > /etc/dfe-broker/dfe.env

# 4. conferir o ambiente ANTES de ligar o serviço (como o usuario do servico)
sudo -u dfe /opt/dfe-broker/DFeBrokerConsole --config /etc/dfe-broker/dfe.ini --verificar-ambiente

# 5. instalar e ligar
cp hosts/console/systemd/dfe-broker.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now dfe-broker
```

## Operação

```bash
systemctl status dfe-broker              # estado, PID, ultimas linhas
journalctl -u dfe-broker -f              # log ao vivo (o log vai para o journal; cada linha e' descarregada na hora)
journalctl -u dfe-broker -b              # desde o boot
systemctl restart dfe-broker             # aplica mudancas de Ambiente/broker (a lista de certificados recarrega sozinha)
systemctl stop dfe-broker                # SIGTERM: termina o tick em andamento (ate 90 s) e sai com 0
```

| Situação | O que o systemd faz |
|---|---|
| Processo morre (SIGKILL, falha) | reinicia em 10 s (`Restart=on-failure`) |
| Exit **2** (ambiente incompleto: DLL/XSD ausente) | **não** reinicia — corrija e `systemctl restart` |
| Exit **1** (config inválida, porta ocupada, broker externo fora) | tenta de novo a cada 10 s, no máximo **5 vezes em 5 min**, depois marca `failed` |
| `systemctl stop` | `SIGTERM`; se passar de 90 s, `SIGKILL` |

## Detalhes que pegam

- **`localhost` × IPv4:** o broker escuta em `127.0.0.1`; um cliente que use `localhost` pode resolver para `::1`. Use `127.0.0.1`.
- **Porta > 1024:** o serviço roda sem privilégios; para o broker embutido, a porta padrão 5672 já serve. Para expor a outra máquina, `BindAddress=0.0.0.0`, **troque `Usuario`/`Senha`** e abra a porta no firewall.
- **Log:** o host escreve em stdout e o journald guarda; a hora de cada linha é a de Brasília com `-03:00` explícito (o `Now` do FPC/Linux é UTC — `docs/linux.md`, item 5).
- **Retenção do log** é do journald (`SystemMaxUse=` em `/etc/systemd/journald.conf`), não do projeto.
