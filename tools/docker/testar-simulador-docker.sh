#!/bin/sh
# Criterio de pronto da Fase D (docs/simulador-standalone.md): a IMAGEM do simulador
# sobe com `docker run`, e um script Python de biblioteca padrao (sem Pascal, sem
# pika) reproduz o roteiro do README contra ela.
#
#   tools/docker/testar-simulador-docker.sh
#
# Requer o submodulo do Horse:  git submodule update --init vendor/horse
# Requer python3 no host (so' o roteiro; o simulador roda no conteiner).
set -u
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$RAIZ" || exit 1
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

IMAGEM=dfe-simulador-teste
PORTA=${PORTA:-9250}
NOME=dfe-simulador-teste-$$
FALHAS=0

if [ ! -d vendor/horse/src ]; then
  echo "vendor/horse nao inicializado: git submodule update --init vendor/horse"; exit 2
fi
PY=python3; command -v python3 >/dev/null 2>&1 || PY=python
"$PY" --version >/dev/null 2>&1 || { echo "python3 nao encontrado no host"; exit 2; }

limpar() { docker rm -f "$NOME" >/dev/null 2>&1; }
trap limpar EXIT

verifica() { # verifica <descricao> <comando...>
  D="$1"; shift
  if "$@"; then echo "  ok   $D"; else echo "  FALHOU  $D"; FALHAS=$((FALHAS+1)); fi
}

subir() { # subir [argumentos do simulador...]
  limpar
  docker run -d --name "$NOME" -p "127.0.0.1:$PORTA:9200" "$IMAGEM" --bind 0.0.0.0 --porta 9200 "$@" >/dev/null
}

esperar() {
  I=0
  while [ $I -lt 50 ]; do
    if "$PY" -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:$PORTA/ping',timeout=2).read()==b'ok' else 1)" 2>/dev/null; then return 0; fi
    I=$((I+1)); sleep 0.3
  done
  return 1
}

echo "=== imagem do simulador (simulador/Dockerfile) ==="
docker build -q -f simulador/Dockerfile -t "$IMAGEM" . >/dev/null || { echo "docker build FALHOU"; exit 1; }
echo "  ok   docker build"

echo; echo "=== docker run + roteiro Python (sem cenario) ==="
subir
verifica "o simulador responde em /ping" esperar
verifica "roda como usuario comum (nao root)" test "$(docker exec "$NOME" id -u 2>/dev/null || echo 0)" != "0"
verifica "o roteiro do README passa" "$PY" simulador/exemplos/python/roteiro.py --url "http://127.0.0.1:$PORTA"

echo; echo "=== cenarios que vao na imagem ==="
for C in basico paginacao instavel; do
  subir --cenario "/cenarios/$C.ini"
  verifica "cenario $C sobe" esperar
  docker logs "$NOME" 2>&1 | grep -q 'Cenario "/cenarios/'"$C"'.ini"' && echo "  ok   $C carregado" || { echo "  FALHOU  $C nao foi carregado"; FALHAS=$((FALHAS+1)); }
done

echo; echo "=== parada ==="
INICIO=$(date +%s)
docker stop "$NOME" >/dev/null
FIM=$(date +%s)
verifica "docker stop nao esperou o kill (< 8 s)" test $((FIM-INICIO)) -lt 8
verifica "saiu por SIGTERM com codigo 0 (nao foi morto: 137)" test "$(docker inspect -f '{{.State.ExitCode}}' "$NOME")" = "0"

echo
if [ "$FALHAS" = "0" ]; then echo "Simulador em Docker: tudo passou."; exit 0; fi
echo "Simulador em Docker: $FALHAS verificacao(oes) FALHARAM."; exit 1
