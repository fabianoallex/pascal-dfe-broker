#!/usr/bin/env bash
# Baixa do SVN OFICIAL do Projeto ACBr, numa revisao fixa, so' as pastas que o
# broker usa, para vendor/ACBr (~70 MB; o trunk2 inteiro tem ~1,3 GB: SAT, ECF,
# boletos, dezenas de provedores de NFSe, demos...). Ver CLAUDE.md, decisao 15.
#
# Rodar a partir da raiz do repositorio, uma vez por clone:
#   ./tools/obter-acbr.sh
#
# Precisa do cliente de linha de comando "svn" OU do Docker (sem svn, o export
# roda dentro de um conteiner Debian com o subversion; nada a instalar no Windows).
#
# Idempotente: vendor/ACBr/REVISAO-SVN.txt guarda a revisao exportada; se for a
# mesma, nao faz nada. Para atualizar o ACBr: mude REVISAO abaixo, rode de novo,
# recompile tudo e registre a nova revisao no CLAUDE.md.
#
# Variavel ACBR_DESTINO: exporta para outra pasta (usada para comparar revisoes).
#
# Por que nao um submodulo git: o ACBr e' SVN; o mirror git nao oficial que o
# projeto usava (github.com/MirrorProjetoACBr/ACBr) sumiu em 2026-10-05.

set -euo pipefail

URL="https://svn.code.sf.net/p/acbr/code/trunk2"
REVISAO="48289"
DESTINO="${ACBR_DESTINO:-vendor/ACBr}"

# Escopo (2026-09-18, refinado compilando de verdade DFe.Client.ACBrNFe contra
# vendor/ACBr -- ver tools/smoke/AcbrClientSmoke.lpi, o smoke test que existe so'
# para provar que esse escopo compila): base comum de todo componente ACBr
# (ACBrComum), a arvore de Distribuicao de DFe (ACBrDFe, com ACBrNFe/ACBrCTe/
# ACBrMDFe/Comum e os units soltos de base como ACBrDFeComum.DistDFeInt.pas),
# ACBrDiversos (ACBrValidador), ACBrIntegrador, ACBrLibXML2 (backend xsLibXml2),
# ACBrTCP (ACBrIBGE, ACBrMail, ACBrConsultaCNPJ), OpenSSL (assinatura/HTTPS) e
# Terceiros (Synapse/synalist para HTTP, GZIPUtils/ZLibExGZ para o docZip,
# LibXmlSec). Cada pasta vem com as subpastas.
PASTAS=(
  "Fontes/ACBrComum"
  "Fontes/ACBrDFe"
  "Fontes/ACBrDiversos"
  "Fontes/ACBrIntegrador"
  "Fontes/ACBrLibXML2"
  "Fontes/ACBrOpenSSL"
  "Fontes/ACBrTCP"
  "Fontes/PCNComum"
  "Fontes/Terceiros"
  # XSDs oficiais de NFe (~2 MB): o ACBr exige uma pasta de schemas em EXECUCAO
  # e EnviarEvento (manifestacao) valida o XML contra eles. So' NFe; CTe/MDFe
  # entram com o provider.
  "Exemplos/ACBrDFe/Schemas/NFe"
)

MARCADOR="$DESTINO/REVISAO-SVN.txt"
if [ -f "$MARCADOR" ] && grep -qx "trunk2@$REVISAO" "$MARCADOR"; then
  echo "OK: $DESTINO ja' esta' em trunk2@$REVISAO."
  exit 0
fi

if [ -d "$DESTINO" ] && [ -n "$(ls -A "$DESTINO" 2>/dev/null)" ]; then
  echo "$DESTINO existe e nao e' um export desta revisao (falta $MARCADOR ou a revisao e' outra)." >&2
  echo "Apague a pasta e rode de novo:  rm -rf $DESTINO && $0" >&2
  exit 1
fi

# Monta o comando de export de cada pasta (o mesmo, com svn local ou no conteiner).
# --force: a pasta-mae ja' existe; --quiet: sao milhares de arquivos.
SCRIPT="set -e"
for P in "${PASTAS[@]}"; do
  SCRIPT="$SCRIPT
echo \"  $P\"
mkdir -p \"\$DEST/$(dirname "$P")\"
svn export --quiet --force --non-interactive \"$URL/$P@$REVISAO\" \"\$DEST/$P\""
done

mkdir -p "$DESTINO"
echo "Exportando trunk2@$REVISAO de $URL para $DESTINO (${#PASTAS[@]} pastas, alguns minutos)..."
if command -v svn >/dev/null 2>&1; then
  DEST="$DESTINO" bash -c "$SCRIPT"
elif command -v docker >/dev/null 2>&1; then
  echo "(sem svn local: usando o subversion num conteiner Debian)"
  ABS="$(cd "$DESTINO" && (pwd -W 2>/dev/null || pwd))"
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" docker run --rm -v "$ABS:/acbr" -e DEST=/acbr \
    debian:12-slim bash -c "apt-get update -qq >/dev/null && apt-get install -y -qq subversion ca-certificates >/dev/null && $SCRIPT && chmod -R a+rwX /acbr"
else
  echo "Precisa do cliente svn (Linux: apt install subversion; Windows: TortoiseSVN com as" >&2
  echo "'command line client tools') ou do Docker." >&2
  exit 1
fi

printf 'trunk2@%s\n' "$REVISAO" > "$MARCADOR"
echo "OK: $DESTINO = $URL@$REVISAO (${#PASTAS[@]} pastas)."
