#!/usr/bin/env bash
# Inicializa o submodulo vendor/ACBr com clone parcial (--filter=blob:none)
# + sparse-checkout restrito ao que o broker realmente usa -- sem isso,
# "git submodule update --init" sozinho baixaria o monorepo inteiro do
# ACBr (~1,3 GB: SAT, ECF, boletos, dezenas de provedores de NFSe, demos
# Android/iOS/React...), quando o necessario para Distribuicao de DFe
# (NFe/CTe/MDFe) fica em ~70 MB. Ver CLAUDE.md, "Fonte do ACBr", e
# docs/architecture.md, "Integracao com ACBr", para o porque.
#
# Rodar a partir da raiz do repositorio, uma vez por clone:
#   ./tools/init-acbr-submodule.sh
#
# Idempotente: pode ser rodado de novo a qualquer momento (ex.: depois de
# adicionar mais um diretorio ao escopo abaixo).

set -euo pipefail

SUBMODULE_PATH="vendor/ACBr"

# Escopo atual (2026-09-18): base comum de todo componente ACBr
# (ACBrComum), a arvore de Distribuicao de DFe (ACBrDFe, com os
# subdiretorios ACBrNFe/ACBrCTe/ACBrMDFe/Comum e os units soltos de base
# como ACBrDFeComum.DistDFeInt.pas), OpenSSL (assinatura/HTTPS) e
# Terceiros (Synapse/synalist para HTTP, GZIPUtils/ZLibExGZ para o
# docZip, LibXmlSec para assinatura XML). Ainda nao refinado ao minimo
# exato -- isso so' fica claro quando a implementacao real de
# IDFeDistribuicaoClient comecar e o compilador reclamar de unit
# faltando (ver "Proximos marcos" em CLAUDE.md).
SPARSE_PATHS=(
  "Fontes/ACBrComum"
  "Fontes/ACBrDFe"
  "Fontes/ACBrOpenSSL"
  "Fontes/Terceiros"
)

git submodule update --init --filter=blob:none --depth 1 "$SUBMODULE_PATH"
git -C "$SUBMODULE_PATH" sparse-checkout init --cone
git -C "$SUBMODULE_PATH" sparse-checkout set "${SPARSE_PATHS[@]}"

echo "OK: $SUBMODULE_PATH inicializado (sparse-checkout restrito a ${#SPARSE_PATHS[@]} diretorios)."
