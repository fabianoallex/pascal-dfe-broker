#!/usr/bin/env bash
# Roda DENTRO do conteiner com systemd (imagem dfe-systemd-teste): instala o host
# como servico e verifica a unit hosts/console/systemd/dfe-broker.service de verdade.
# Chamado por tools/docker/testar-systemd.sh. Sai com o numero de falhas (0 = tudo ok).
set -u
FALHAS=0
ok()    { echo "[OK]    $*"; }
falha() { echo "[FALHA] $*"; FALHAS=$((FALHAS+1)); }
checa() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$desc"; else falha "$desc"; fi; }
estado() { systemctl is-active dfe-broker 2>/dev/null; }
mainpid() { systemctl show -p MainPID --value dfe-broker; }

# --- instalacao (o que o LEIAME manda fazer) ---
install -d /opt/dfe-broker /etc/dfe-broker
install -m 0755 /out/host/DFeBrokerConsole /opt/dfe-broker/DFeBrokerConsole
cp -r /proj/vendor/ACBr/Exemplos/ACBrDFe/Schemas/NFe /opt/dfe-broker/Schemas
# a config de exemplo sem o bloco de certificado (nao ha .pfx aqui)
sed "/^\[certificado:matriz\]/,\$d" /proj/hosts/console/systemd/dfe.ini.exemplo > /tmp/dfe.ini
install -m 0640 -o root -g dfe /tmp/dfe.ini /etc/dfe-broker/dfe.ini
cp /proj/hosts/console/systemd/dfe-broker.service /etc/systemd/system/dfe-broker.service
systemctl daemon-reload

echo "=== 1. a unit e' valida"
checa "systemd-analyze verify" systemd-analyze verify /etc/systemd/system/dfe-broker.service

echo "=== 2. sobe como servico, usuario dfe"
systemctl start dfe-broker
sleep 7
[ "$(estado)" = active ] && ok "active" || { falha "estado: $(estado)"; journalctl -u dfe-broker --no-pager | tail -15; }
PID1=$(mainpid)
[ "$(ps -o user= -p "$PID1" | tr -d ' ')" = dfe ] && ok "roda como usuario dfe (nao-root)" || falha "usuario: $(ps -o user= -p "$PID1")"
checa "escuta em 127.0.0.1:5672" bash -c "ss -ltn | grep -q '127.0.0.1:5672'"
[ "$(stat -c %U /var/lib/dfe-broker 2>/dev/null)" = dfe ] && ok "StateDirectory /var/lib/dfe-broker do usuario dfe" || falha "StateDirectory"
checa "WAL do broker criado em /var/lib/dfe-broker/broker" test -d /var/lib/dfe-broker/broker
checa "log no journal: Em execucao" bash -c "journalctl -u dfe-broker --no-pager | grep -q 'Em execucao'"
# ProtectSystem=strict: o processo NAO consegue escrever fora do StateDirectory
checa "escrita em /etc negada ao servico" bash -c "! nsenter -t $PID1 -m sh -c 'touch /etc/x' 2>/dev/null"

echo "=== 3. queda (SIGKILL): reinicia sozinho"
kill -9 "$PID1"
sleep 14
[ "$(estado)" = active ] && ok "voltou a active" || falha "apos SIGKILL: $(estado)"
PID2=$(mainpid)
[ "$PID2" != "$PID1" ] && [ "$PID2" != 0 ] && ok "PID novo ($PID1 -> $PID2)" || falha "PID nao mudou ($PID1 -> $PID2)"
[ "$(systemctl show -p NRestarts --value dfe-broker)" = 1 ] && ok "NRestarts=1" || falha "NRestarts=$(systemctl show -p NRestarts --value dfe-broker)"

echo "=== 4. parada (SIGTERM): sai limpo, codigo 0"
systemctl stop dfe-broker
[ "$(systemctl show -p Result --value dfe-broker)" = success ] && ok "Result=success" || falha "Result=$(systemctl show -p Result --value dfe-broker)"
[ "$(systemctl show -p ExecMainStatus --value dfe-broker)" = 0 ] && ok "ExecMainStatus=0" || falha "ExecMainStatus=$(systemctl show -p ExecMainStatus --value dfe-broker)"
checa "log no journal: Encerrando" bash -c "journalctl -u dfe-broker --no-pager | grep -q 'Encerrando'"

echo "=== 5. ambiente incompleto (exit 2): NAO reinicia em loop"
mv /opt/dfe-broker/Schemas /opt/dfe-broker/Schemas.off
systemctl start dfe-broker
sleep 15
[ "$(systemctl is-failed dfe-broker)" = failed ] && ok "failed (nao fica reiniciando)" || falha "estado: $(systemctl is-failed dfe-broker)"
[ "$(systemctl show -p ExecMainStatus --value dfe-broker)" = 2 ] && ok "exit 2" || falha "ExecMainStatus=$(systemctl show -p ExecMainStatus --value dfe-broker)"
mv /opt/dfe-broker/Schemas.off /opt/dfe-broker/Schemas

echo
[ "$FALHAS" = 0 ] && echo "systemd: TUDO OK" || echo "systemd: $FALHAS falha(s)"
exit "$FALHAS"
