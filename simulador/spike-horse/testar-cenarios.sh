#!/bin/sh
# Bate nas rotas do spike (SpikeHorse ja' rodando na porta $1, padrao 9100)
# e confere: corpo com acento devolvido byte a byte, HTTP 500, resposta de
# ~360 KB e concorrencia (4 chamadas de 1 s devem levar bem menos de 4 s).
# Funciona contra o exe FPC (Windows/Linux) e contra o do Delphi.
P=${1:-9100}; T=$(mktemp -d)
printf '<a>Ação é ç ã ü — “aspas”</a>' > "$T/a.xml"
curl -s -m 5 localhost:$P/ping; echo
curl -s -m 5 -X POST -H 'Content-Type: application/soap+xml; charset=utf-8' \
  --data-binary @"$T/a.xml" localhost:$P/eco -o "$T/e.out"
cmp "$T/a.xml" "$T/e.out" && echo "ACENTO: bytes identicos"
curl -s -m 5 -X POST -H 'Content-Type: application/soap+xml; charset=utf-8' \
  -H 'SOAPAction: "urn:x"' --data-binary @"$T/a.xml" localhost:$P/tipo; echo
curl -s -m 5 -o /dev/null -w "erro: http=%{http_code}\n" -X POST -d x localhost:$P/erro
curl -s -m 10 -X POST -d x localhost:$P/grande -o "$T/g.out" \
  -w "grande: http=%{http_code} bytes=%{size_download}\n"
s=$(date +%s%N)
for i in 1 2 3 4; do curl -s -m 10 -X POST -d x localhost:$P/lento -o /dev/null & done; wait
e=$(date +%s%N); echo "4x lento: $(( (e-s)/1000000 )) ms (concorrente < ~2000; serial ~4000)"
rm -rf "$T"
