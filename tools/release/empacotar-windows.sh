#!/usr/bin/env bash
# Monta o pacote Windows x64 (demo) para uma release do GitHub.
#
#   tools/release/empacotar-windows.sh --raiz <repo com os executaveis compilados> \
#       --dlls <pasta com libssl-3-x64.dll libcrypto-3-x64.dll libxml2.dll zlib1.dll> \
#       [--saida <pasta>] [--versao 0.1.0]
#
# - Os executaveis (DFeBrokerConsole, DFeSimulador, DFeDemo) e os XSDs/certificado de
#   teste vem de --raiz, que deve ser um clone LIMPO do commit da release, ja compilado
#   com o FPC (ver "Como compilar e rodar" no README). Os textos do pacote (LEIAME,
#   dfe.ini, demo-publicar.ps1, avisos de terceiros) vem de tools/release/windows/ DESTE repositorio.
# - As DLLs sao de terceiros e NAO ficam no repositorio: aponte --dlls para uma pasta que
#   tenha as quatro (a demo foi testada com as do PostgreSQL 18 x64). libssl e libcrypto
#   precisam ser da mesma versao. Confira THIRD-PARTY-NOTICES.txt se usar outras.
# - Gera <saida>/dfe-broker-win64-v<versao>.zip.
set -euo pipefail

RAIZ=""; DLLS=""; SAIDA="."; VERSAO="0.1.0"
while [ $# -gt 0 ]; do
  case "$1" in
    --raiz)   RAIZ="$2"; shift 2 ;;
    --dlls)   DLLS="$2"; shift 2 ;;
    --saida)  SAIDA="$2"; shift 2 ;;
    --versao) VERSAO="$2"; shift 2 ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done
[ -n "$RAIZ" ] && [ -n "$DLLS" ] || { echo "uso: --raiz <repo compilado> --dlls <pasta com as DLLs> [--saida d] [--versao v]" >&2; exit 2; }

TPL="$(cd "$(dirname "$0")/windows" && pwd)"
RAIZ="$(cd "$RAIZ" && pwd)"; DLLS="$(cd "$DLLS" && pwd)"; mkdir -p "$SAIDA"; SAIDA="$(cd "$SAIDA" && pwd)"
STRIP="$(command -v strip || true)"
[ -n "$STRIP" ] || STRIP=/c/lazarus4.0/fpc/3.2.2/bin/x86_64-win64/strip.exe

NOME="dfe-broker-win64-v$VERSAO"
TMP="$(mktemp -d)"; PKG="$TMP/$NOME"
mkdir -p "$PKG/exemplos/python" "$PKG/cert-teste" "$PKG/Schemas"

for exe in hosts/console/DFeBrokerConsole simulador/DFeSimulador tools/demo/DFeDemo; do
  [ -f "$RAIZ/$exe.exe" ] || { echo "faltou compilar: $exe.exe em $RAIZ" >&2; exit 1; }
  cp "$RAIZ/$exe.exe" "$PKG/"
done
[ -x "$STRIP" ] && for f in "$PKG"/*.exe; do "$STRIP" --strip-all "$f"; done

for d in libssl-3-x64.dll libcrypto-3-x64.dll libxml2.dll zlib1.dll; do
  [ -f "$DLLS/$d" ] || { echo "faltou a DLL: $d em $DLLS" >&2; exit 1; }
  cp "$DLLS/$d" "$PKG/"
done

cp "$RAIZ"/vendor/ACBr/Exemplos/ACBrDFe/Schemas/NFe/* "$PKG/Schemas/"
cp "$RAIZ/tests/Integration/AcbrSim/cert-teste/valido.pfx" "$PKG/cert-teste/"
cp "$RAIZ/exemplos/consumidor/python/consumir.py" "$RAIZ/exemplos/consumidor/python/manifestar.py" \
   "$RAIZ/simulador/exemplos/python/roteiro.py" "$PKG/exemplos/python/"
cp "$RAIZ/LICENSE" "$PKG/"
cp "$TPL/dfe.ini" "$TPL/demo-publicar.ps1" "$TPL/LEIAME.md" "$TPL/THIRD-PARTY-NOTICES.txt" "$PKG/"

rm -f "$SAIDA/$NOME.zip"
# zip com separadores padrao (o Compress-Archive do PowerShell 5.1 grava barras invertidas)
python -c "import shutil,sys; shutil.make_archive(sys.argv[1], 'zip', sys.argv[2], sys.argv[3])"        "$SAIDA/$NOME" "$TMP" "$NOME"
rm -rf "$TMP"
echo "gerado: $SAIDA/$NOME.zip ($(du -h "$SAIDA/$NOME.zip" | cut -f1))"
