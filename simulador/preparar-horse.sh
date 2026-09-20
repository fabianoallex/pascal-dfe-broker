#!/bin/sh
# Copia vendor/horse/src para simulador/build/horse-src, que e' o que o FPC usa.
# Em Windows aplica o contorno de 1 linha em Horse.FPC.inc (const x constref do
# comparador generico; ver spike-horse/LEIAME.md) -- sem tocar no submodulo. Em
# Linux a copia sai sem alteracao. Idempotente. O Delphi usa vendor/horse/src
# direto e nao precisa disto.
cd "$(dirname "$0")" || exit 1
DEST=build/horse-src
rm -rf "$DEST" && mkdir -p "$DEST" && cp -r ../vendor/horse/src/. "$DEST"/ || exit 1
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    sed -i 's/{\$ELSEIF DEFINED(CPU64) AND DEFINED(WINDOWS)}/{$ELSEIF FALSE}/' "$DEST/Horse.FPC.inc"
    echo "Horse preparado em $DEST (Windows: contorno do Horse.FPC.inc aplicado)" ;;
  *) echo "Horse preparado em $DEST (copia sem alteracao)" ;;
esac
