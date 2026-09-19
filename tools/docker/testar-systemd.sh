#!/usr/bin/env bash
# Valida hosts/console/systemd/dfe-broker.service de verdade: sobe um conteiner Debian 12
# com systemd como PID 1, instala o host como servico (usuario nao-root) e confere
# subida, queda + reinicio, parada por SIGTERM e o exit 2 do ambiente incompleto.
# Ver docs/linux.md. Da raiz do repo (git-bash, Linux ou macOS):
#
#   tools/docker/testar-systemd.sh
#
# Requer Docker com suporte a --privileged e cgroup v2 (Docker Desktop/WSL2 serve).
# Pre-requisito: vendor/ACBr inicializado (XSDs) -- tools/init-acbr-submodule.sh.
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

cd "$(dirname "$0")/../.."
RAIZ="$(pwd -W 2>/dev/null || pwd)"

if ! docker image inspect dfe-linux-teste >/dev/null 2>&1; then
  echo ">> construindo a imagem dfe-linux-teste (uma vez)..."
  docker build -f tools/docker/Dockerfile.linux-teste -t dfe-linux-teste tools/docker
fi
if ! docker image inspect dfe-systemd-teste >/dev/null 2>&1; then
  echo ">> construindo a imagem dfe-systemd-teste (uma vez)..."
  docker build -f tools/docker/Dockerfile.systemd-teste -t dfe-systemd-teste tools/docker
fi

SAIDA="$(mktemp -d)"
SAIDA_MONTAGEM="$(cd "$SAIDA" && (pwd -W 2>/dev/null || pwd))"
CT="dfe-systemd-$$"
trap 'docker rm -f "$CT" >/dev/null 2>&1 || true; rm -rf "$SAIDA"' EXIT

echo ">> compilando o host (FPC, Linux)..."
docker run --rm -v "$RAIZ:/proj:ro" -v "$SAIDA_MONTAGEM:/out" \
  --entrypoint bash dfe-linux-teste /proj/tools/docker/compilar-host-linux.sh

echo ">> subindo o conteiner com systemd..."
docker run -d --name "$CT" --privileged --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw --tmpfs /run --tmpfs /run/lock \
  -v "$RAIZ:/proj:ro" -v "$SAIDA_MONTAGEM:/out:ro" dfe-systemd-teste >/dev/null

for _ in $(seq 1 40); do
  ESTADO="$(docker exec "$CT" systemctl is-system-running 2>/dev/null || true)"
  case "$ESTADO" in running|degraded) break ;; esac
  sleep 1
done
echo ">> systemd: ${ESTADO:-nao respondeu}"
[ -n "${ESTADO:-}" ] || { echo "systemd nao subiu no conteiner (Docker sem --privileged/cgroup v2?)"; docker logs "$CT" | tail -20; exit 2; }

docker exec "$CT" bash /proj/tools/docker/systemd-dentro.sh
