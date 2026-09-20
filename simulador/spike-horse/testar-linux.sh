#!/bin/sh
# Compila o spike com o FPC do Debian (Horse SEM patch) e roda os cenarios
# dentro de um conteiner. Usa a imagem dfe-linux-teste (tools/docker).
cd "$(dirname "$0")/../.." || exit 1
cat > /tmp/spike-linux-interno.sh <<'IN'
apt-get update -qq >/dev/null && apt-get install -y -qq curl >/dev/null
mkdir -p /tmp/o && cd /tmp/o
fpc -Mdelphi -dUseCThreads -Fu/proj/vendor/horse/src -Fu/proj/simulador/spike-horse -FU/tmp/o -FE/tmp/o /proj/simulador/spike-horse/SpikeHorse.lpr | grep -E "Error|Fatal|lines compiled"
/tmp/o/SpikeHorse 9100 >/tmp/srv.log 2>&1 &
sleep 2
sh /proj/simulador/spike-horse/testar-cenarios.sh 9100
IN
# cygpath so' existe no Git Bash do Windows; em Linux/macOS os caminhos ja' servem.
if command -v cygpath >/dev/null 2>&1; then
  RAIZ=$(cygpath -w "$PWD"); SCRIPT=$(cygpath -w /tmp/spike-linux-interno.sh)
else
  RAIZ=$PWD; SCRIPT=/tmp/spike-linux-interno.sh
fi
MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" docker run --rm -v "$RAIZ:/proj:ro" -v "$SCRIPT:/i.sh:ro" dfe-linux-teste sh /i.sh
