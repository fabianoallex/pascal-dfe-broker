#!/usr/bin/env bash
# Compila e roda os testes do broker em Linux x86_64 (Debian 12) via Docker.
# Ver docs/linux.md. Do git-bash (Windows), do Linux ou do macOS, na raiz do repo:
#
#   tools/docker/testar-linux.sh              # suite pura + integracao (com libxml2.so)
#   tools/docker/testar-linux.sh --sem-link   # integracao SEM o link libxml2.so: mostra
#                                             # a recusa que o operador veria (esperado: falha)
#   tools/docker/testar-linux.sh --so-pura    # so' a suite pura (rapido, ~10 s)
#
# Pre-requisito da integracao: vendor/ACBr inicializado (tools/init-acbr-submodule.sh).
# Para os testes AMQP e o host: vendor/pascal-amqp-faa (git submodule update --init vendor/pascal-amqp-faa).
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

SEM_LINK=0; SO_PURA=0
for a in "$@"; do
  case "$a" in
    --sem-link) SEM_LINK=1 ;;
    --so-pura)  SO_PURA=1 ;;
    *) echo "opcao desconhecida: $a" >&2; exit 2 ;;
  esac
done

cd "$(dirname "$0")/../.."
RAIZ="$(pwd -W 2>/dev/null || pwd)"   # -W: caminho estilo Windows no git-bash

if ! docker image inspect dfe-linux-teste >/dev/null 2>&1; then
  echo ">> construindo a imagem dfe-linux-teste (uma vez)..."
  docker build -f tools/docker/Dockerfile.linux-teste -t dfe-linux-teste tools/docker
fi

SAIDA="$(mktemp -d)"
# O conteiner roda como root: o que ele gera em $SAIDA pertence a root, e o usuario
# comum de um runner de CI nao consegue apagar. Apaga de dentro de um conteiner.
limpar() {
  docker run --rm -v "${SAIDA_MONTAGEM:-$SAIDA}:/out" --entrypoint sh dfe-linux-teste     -c 'rm -rf /out/* /out/.[!.]* 2>/dev/null' >/dev/null 2>&1 || true
  rm -rf "$SAIDA" 2>/dev/null || true
}
trap limpar EXIT
SAIDA_MONTAGEM="$(cd "$SAIDA" && (pwd -W 2>/dev/null || pwd))"

docker run --rm \
  -v "$RAIZ:/proj:ro" -v "$SAIDA_MONTAGEM:/out" \
  -e SEM_LINK="$SEM_LINK" -e SO_PURA="$SO_PURA" \
  --entrypoint bash dfe-linux-teste -c '
set -uo pipefail

echo "=== suite pura (FPCUnit) ==="
cd /proj/tests/Unit/fpc
fpc -Mdelphi -Sh -Fu/proj/src -Fu/proj/tests/Unit/fpc -Fi/proj/src -FU/out -FE/out \
    -oDFeUnitTestsFpc DFeUnitTestsFpc.lpr 2>&1 | grep -E "Fatal|Error:|lines compiled"
/out/DFeUnitTestsFpc --all --format=plain > /out/pura.txt 2>&1; RCP=$?
grep -E "Number of|unfreed" /out/pura.txt
if [ "$SO_PURA" = "1" ]; then exit $RCP; fi

echo; echo "=== integracao ACBr x simulador ==="
LPI=/proj/tests/Integration/AcbrSim/AcbrSimTests.lpi
# caminhos do .lpi (relativos a tests/Integration/AcbrSim, com barra invertida) -> absolutos no contêiner
conv() { tr ";" "\n" | sed "s#\\\\#/#g; s#^\.\./\.\./\.\./#/proj/#; s#^\.\./\.\./Unit#/proj/tests/Unit#"; }
UNITS=$(grep -o "OtherUnitFiles Value=\"[^\"]*\"" $LPI | sed "s/.*Value=\"//; s/\"\$//" | conv | sed "s#^#-Fu#" | tr "\n" " ")
INCS=$(grep -o "IncludeFiles Value=\"[^\"]*\"" $LPI | sed "s/.*Value=\"//; s/\"\$//" | conv | sed "s#^#-Fi#" | tr "\n" " ")
LAZ=/usr/lib/lazarus/2.2.6
cd /proj/tests/Integration/AcbrSim
fpc -Mdelphi -Sh $UNITS $INCS \
    -Fu$LAZ/lcl/units/x86_64-linux/nogui -Fu$LAZ/lcl/units/x86_64-linux \
    -Fu$LAZ/components/lazutils/lib/x86_64-linux -dLCL -dLCLnogui \
    -FU/out -FE/out -oAcbrSimTests AcbrSimTests.lpr 2>&1 | grep -E "Fatal|Error:|lines compiled"

cp -r /proj/tests/Integration/AcbrSim/cert-teste /proj/tests/Integration/AcbrSim/Schemas /out/
ln -sf /proj/vendor /vendor    # os testes de evento acham os XSDs em ../../../vendor a partir do executavel
if [ "$SEM_LINK" = "0" ]; then
  ln -sf /usr/lib/x86_64-linux-gnu/libxml2.so.2 /usr/lib/x86_64-linux-gnu/libxml2.so
else
  echo "(sem o link libxml2.so -- o ACBr nao vai achar a libxml2)"
fi
cd /out
timeout 300 ./AcbrSimTests --all --format=plain > /out/resultado.txt 2>&1; RCI=$?
echo "saida da integracao=$RCI (0 = tudo passou; 124 = estourou o tempo)"
grep -E "Number of|Time:" /out/resultado.txt | head -6 || true
grep -A2 "Message:" /out/resultado.txt | head -4 | cut -c1-400 || true
RCA=0; RCH=0
if [ ! -d /proj/vendor/pascal-amqp-faa/src ]; then
  echo; echo "=== integracao AMQP embutido e host console: PULADA (vendor/pascal-amqp-faa nao inicializado: git submodule update --init vendor/pascal-amqp-faa) ==="
else
  echo; echo "=== integracao AMQP embutido (broker in-process, sem ACBr) ==="
  mkdir -p /out/amqp
  cd /proj/tests/Integration/AmqpBroker
  fpc -Mdelphi -Sh -Fu/proj/src -Fu/proj/vendor/pascal-amqp-faa/src -Fu/proj/vendor/pascal-amqp-faa/src/server -Fu/proj/tests/Unit/fpc \
      -Fi/proj/src -Fi/proj/vendor/pascal-amqp-faa/src -FU/out/amqp -FE/out/amqp -oAmqpBrokerTests AmqpBrokerTests.lpr 2>&1 | grep -E "Fatal|Error:|lines compiled"
  cd /out/amqp
  timeout 300 ./AmqpBrokerTests --all --format=plain > /out/amqp.txt 2>&1; RCA=$?
  echo "saida da integracao AMQP=$RCA (0 = tudo passou; 124 = estourou o tempo)"
  grep -E "Number of|Time:" /out/amqp.txt | head -6 || true
  grep -A2 "Message:" /out/amqp.txt | head -6 | cut -c1-400 || true

  echo; echo "=== host console: compila, sobe, recebe SIGTERM ==="
  HLPI=/proj/hosts/console/DFeBrokerConsole.lpi
  # caminhos do .lpi sao relativos a hosts/console (com barra invertida); o fpc roda la
  hconv() { tr ";" "\n" | sed "s#\\\\#/#g"; }
  HUNITS=$(grep -o "OtherUnitFiles Value=\"[^\"]*\"" $HLPI | sed "s/.*Value=\"//; s/\"\$//" | hconv | sed "s#^#-Fu#" | tr "\n" " ")
  HINCS=$(grep -o "IncludeFiles Value=\"[^\"]*\"" $HLPI | sed "s/.*Value=\"//; s/\"\$//" | hconv | sed "s#^#-Fi#" | tr "\n" " ")
  LAZ=/usr/lib/lazarus/2.2.6
  mkdir -p /out/host /out/host-cfg
  cd /proj/hosts/console
  fpc -Mdelphi -Sh $HUNITS $HINCS \
      -Fu$LAZ/lcl/units/x86_64-linux/nogui -Fu$LAZ/lcl/units/x86_64-linux \
      -Fu$LAZ/components/lazutils/lib/x86_64-linux -dLCL -dLCLnogui \
      -FU/out/host -FE/out/host -oDFeBrokerConsole DFeBrokerConsole.dpr 2>&1 | grep -E "Fatal|Error:|lines compiled"
  printf "[dfe]\nPathSchemas=/proj/vendor/ACBr/Exemplos/ACBrDFe/Schemas/NFe\n[broker]\nPorta=25672\n[fila:documentos]\nRoutingKey=nfe.documento.#\n" > /out/host-cfg/dfe.ini
  ln -sf /usr/lib/x86_64-linux-gnu/libxml2.so.2 /usr/lib/x86_64-linux-gnu/libxml2.so
  /out/host/DFeBrokerConsole --config /out/host-cfg/dfe.ini > /out/host.txt 2>&1 &
  HPID=$!
  sleep 8
  kill -TERM $HPID
  wait $HPID; RCH=$?
  cut -c1-220 /out/host.txt
  echo "saida do host apos SIGTERM=$RCH (0 = parada limpa)"
  if ! grep -q "Encerrando" /out/host.txt; then RCH=1; fi
fi

# codigo de saida do script = falha se QUALQUER suite falhou
if [ "$RCP" -ne 0 ] || [ "$RCI" -ne 0 ] || [ "$RCA" -ne 0 ] || [ "$RCH" -ne 0 ]; then exit 1; fi
exit 0
'
