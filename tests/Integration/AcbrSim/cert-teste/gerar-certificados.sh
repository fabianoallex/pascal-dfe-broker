#!/usr/bin/env bash
# Gera os certificados SINTETICOS de teste (nunca use nada disto em producao):
#   valido.pfx  - autoassinado, CNPJ 11222333000181 (padrao ICP-Brasil: CN
#                 "RAZAO:CNPJ" + otherName 2.16.76.1.3.3), valido por 100 anos
#   vencido.pfx - mesmo, com validade de 2020-01-01 a 2020-01-02
# Senha de ambos: teste123. Requer OpenSSL 3 (o do Git for Windows serve).
# Os .pfx gerados sao versionados para o teste nao depender do openssl.
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")"
T=".gerar-tmp"
rm -rf "$T"; mkdir "$T"   # caminho relativo: openssl.exe nativo nao entende /tmp do MSYS
trap 'rm -rf "$T"' EXIT

cat > "$T/ext.cnf" <<'EOF'
subjectAltName=otherName:2.16.76.1.3.3;UTF8:11222333000181
EOF
cat > "$T/ca.cnf" <<'EOF'
[ca]
default_ca=CA_default
[CA_default]
database=index.txt
new_certs_dir=.
serial=serial
default_md=sha256
policy=pol
unique_subject=no
copy_extensions=none
[pol]
commonName=supplied
countryName=optional
organizationName=optional
[req]
distinguished_name=dn
prompt=no
[dn]
C=BR
O=ICP-Brasil
CN=EMPRESA TESTE LTDA:11222333000181
EOF

gerar() { # nome inicio fim
  ( cd "$T" && : > index.txt && echo 01 > serial \
    && openssl req -new -newkey rsa:2048 -nodes -keyout "$1.key" -out "$1.csr" -config ca.cnf 2>/dev/null \
    && openssl ca -config ca.cnf -selfsign -keyfile "$1.key" -in "$1.csr" -out "$1.crt" \
         -startdate "$2" -enddate "$3" -batch -notext -extfile ext.cnf 2>/dev/null )
  openssl pkcs12 -export -inkey "$T/$1.key" -in "$T/$1.crt" -out "$1.pfx" -passout pass:teste123
}

gerar valido 20200101000000Z 21200101000000Z
gerar vencido 20200101000000Z 20200102000000Z
rm -rf "$T"
echo "gerados: valido.pfx vencido.pfx"
