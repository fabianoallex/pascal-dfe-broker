#!/usr/bin/env bash
# Roda DENTRO da imagem dfe-linux-teste: compila hosts/console/DFeBrokerConsole.dpr
# (FPC, backend LCL nogui) para /out/host/DFeBrokerConsole. /proj e' somente-leitura.
# Chamado por tools/docker/testar-systemd.sh.
set -uo pipefail
LPI=/proj/hosts/console/DFeBrokerConsole.lpi
# caminhos do .lpi sao relativos a hosts/console e usam barra invertida; o fpc roda la
conv() { tr ";" "\n" | sed "s#\\\\#/#g"; }
UNITS=$(grep -o "OtherUnitFiles Value=\"[^\"]*\"" $LPI | sed "s/.*Value=\"//; s/\"\$//" | conv | sed "s#^#-Fu#" | tr "\n" " ")
INCS=$(grep -o "IncludeFiles Value=\"[^\"]*\"" $LPI | sed "s/.*Value=\"//; s/\"\$//" | conv | sed "s#^#-Fi#" | tr "\n" " ")
LAZ=/usr/lib/lazarus/2.2.6
mkdir -p /out/host
cd /proj/hosts/console
fpc -Mdelphi -Sh $UNITS $INCS \
    -Fu$LAZ/lcl/units/x86_64-linux/nogui -Fu$LAZ/lcl/units/x86_64-linux \
    -Fu$LAZ/components/lazutils/lib/x86_64-linux -dLCL -dLCLnogui \
    -FU/out/host -FE/out/host -oDFeBrokerConsole DFeBrokerConsole.dpr 2>&1 | grep -E "Fatal|Error:|lines compiled"
test -x /out/host/DFeBrokerConsole
