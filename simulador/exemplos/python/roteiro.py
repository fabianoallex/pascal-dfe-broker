#!/usr/bin/env python3
"""Roteiro do DFeSimulador para quem NAO usa Pascal: so' a biblioteca padrao do Python.

  docker run --rm -p 127.0.0.1:9200:9200 dfe-simulador
  python3 simulador/exemplos/python/roteiro.py --url http://127.0.0.1:9200

Faz, como um cliente qualquer, o que o README descreve: publica documentos pela API
admin, consulta a Distribuicao de DFe por SOAP (o envelope que o ACBr envia), paginacao,
o bloqueio de 1 h (656) desfeito pelo RELOGIO VIRTUAL, falhas enfileiradas e o modo
estrito. Sai com codigo 0 se tudo bate, 1 no primeiro desvio.

NAO e' a SEFAZ: o simulador responde conforme a leitura do projeto das NTs.
"""
import argparse
import base64
import gzip
import json
import re
import sys
import time
import urllib.error
import urllib.request

CNPJ = "11222333000181"
UF = "RS"
CAMINHO_DISTRIBUICAO = "/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx"
SOAP_ACTION = "http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe/nfeDistDFeInteresse"
COD_UF = {"RS": "43", "SP": "35"}


class Falha(Exception):
    pass


def chamar(base, metodo, caminho, corpo=None, cabecalhos=None, timeout=10):
    """Devolve (status HTTP, corpo como texto UTF-8). Um status de erro NAO levanta."""
    dados = corpo.encode("utf-8") if isinstance(corpo, str) else corpo
    req = urllib.request.Request(base + caminho, data=dados, method=metodo, headers=cabecalhos or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode("utf-8")
    except urllib.error.HTTPError as erro:
        return erro.code, erro.read().decode("utf-8", "replace")


def admin(base, metodo, caminho, corpo=None):
    """Chama a API admin (JSON plano); exige 200."""
    cabecalhos = {"Content-Type": "application/json; charset=utf-8"}
    status, texto = chamar(base, metodo, caminho, json.dumps(corpo) if corpo is not None else None, cabecalhos)
    conferir(status == 200, "%s %s -> HTTP %s: %s" % (metodo, caminho, status, texto))
    return texto


def envelope(cnpj, uf, ult_nsu):
    """O envelope de distDFeInt por ultNSU, como o ACBr o monta."""
    return (
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<soap12:Envelope xmlns:soap12="http://www.w3.org/2003/05/soap-envelope"><soap12:Body>'
        '<nfeDistDFeInteresse xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe">'
        '<nfeDadosMsg><distDFeInt xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.01">'
        "<tpAmb>2</tpAmb><cUFAutor>%s</cUFAutor><CNPJ>%s</CNPJ>"
        "<distNSU><ultNSU>%s</ultNSU></distNSU></distDFeInt></nfeDadosMsg>"
        "</nfeDistDFeInteresse></soap12:Body></soap12:Envelope>"
    ) % (COD_UF[uf], cnpj, ult_nsu)


def consultar(base, ult_nsu, cnpj=CNPJ, uf=UF, ult_nsu_texto=None):
    """Uma consulta de Distribuicao. Devolve dict com status HTTP, cStat, ultNSU, maxNSU e documentos."""
    texto_nsu = ult_nsu_texto if ult_nsu_texto is not None else "%015d" % ult_nsu
    status, corpo = chamar(
        base, "POST", CAMINHO_DISTRIBUICAO, envelope(cnpj, uf, texto_nsu),
        {"Content-Type": "application/soap+xml; charset=utf-8", "SOAPAction": SOAP_ACTION},
    )
    resultado = {"http": status, "corpo": corpo, "cstat": None, "docs": []}
    m = re.search(r"<cStat>(\d+)</cStat>", corpo)
    if m:
        resultado["cstat"] = int(m.group(1))
    for tag in ("ultNSU", "maxNSU"):
        m = re.search(r"<%s>(\d+)</%s>" % (tag, tag), corpo)
        resultado[tag] = int(m.group(1)) if m else None
    for nsu, schema, b64 in re.findall(r'<docZip NSU="(\d+)" schema="([^"]+)">([^<]*)</docZip>', corpo):
        xml = gzip.decompress(base64.b64decode(b64)).decode("utf-8")
        resultado["docs"].append({"nsu": int(nsu), "schema": schema, "xml": xml})
    return resultado


def conferir(condicao, mensagem):
    if not condicao:
        raise Falha(mensagem)


def passo(texto):
    print("- " + texto, flush=True)


def esperar_no_ar(base, segundos=15):
    limite = time.time() + segundos
    while time.time() < limite:
        try:
            status, texto = chamar(base, "GET", "/ping", timeout=2)
            if status == 200 and texto == "ok":
                return
        except (urllib.error.URLError, OSError):
            pass
        time.sleep(0.3)
    raise Falha("o simulador nao respondeu em /ping em %d s (%s)" % (segundos, base))


def roteiro(base):
    esperar_no_ar(base)
    admin(base, "POST", "/admin/zerar")

    passo("publica 3 resNFe + 1 procNFe pela API admin")
    admin(base, "POST", "/admin/documentos", {"cnpj": CNPJ, "uf": UF, "tipo": "resNFe", "quantidade": 3})
    admin(base, "POST", "/admin/documentos", {"cnpj": CNPJ, "uf": UF, "tipo": "procNFe"})

    passo("consulta por ultNSU=0: 138 com 4 documentos (docZip = gzip + base64)")
    r = consultar(base, 0)
    conferir(r["http"] == 200 and r["cstat"] == 138, "esperava 138, veio %s/%s" % (r["http"], r["cstat"]))
    conferir(len(r["docs"]) == 4, "esperava 4 documentos, vieram %d" % len(r["docs"]))
    conferir([d["nsu"] for d in r["docs"]] == [1, 2, 3, 4], "NSUs fora de ordem: %s" % [d["nsu"] for d in r["docs"]])
    conferir(r["ultNSU"] == 4 and r["maxNSU"] == 4, "ultNSU/maxNSU: %s/%s" % (r["ultNSU"], r["maxNSU"]))
    conferir(all(d["xml"].lstrip().startswith("<") for d in r["docs"]), "docZip nao virou XML")
    print("    schemas: " + ", ".join(d["schema"] for d in r["docs"]))

    passo("consulta a partir do ultimo NSU: 137 (nada novo) e abre o bloqueio de 1 h")
    r = consultar(base, 4)
    conferir(r["cstat"] == 137, "esperava 137, veio %s" % r["cstat"])

    passo("consulta de novo, na hora: 656 (consumo indevido)")
    r = consultar(base, 4)
    conferir(r["http"] == 200 and r["cstat"] == 656, "esperava 656, veio %s" % r["cstat"])

    passo("RELOGIO VIRTUAL +1 h 01 min (sem esperar): a consulta e' liberada")
    admin(base, "POST", "/admin/relogio/avancar", {"horas": 1, "minutos": 1})
    r = consultar(base, 4)
    conferir(r["cstat"] == 137, "depois do relogio, esperava 137, veio %s" % r["cstat"])

    passo("documento novo depois do 137: a proxima consulta traz so' ele")
    admin(base, "POST", "/admin/relogio/avancar", {"horas": 1, "minutos": 1})
    admin(base, "POST", "/admin/documentos", {"cnpj": CNPJ, "uf": UF, "tipo": "resNFe"})
    r = consultar(base, 4)
    conferir(r["cstat"] == 138 and [d["nsu"] for d in r["docs"]] == [5], "esperava 138 com o NSU 5, veio %s %s" % (r["cstat"], [d["nsu"] for d in r["docs"]]))

    passo("paginacao: 120 documentos em outra conta -> lotes de 50, 50 e 20")
    outro = "12345678000199"
    admin(base, "POST", "/admin/documentos", {"cnpj": outro, "uf": "SP", "quantidade": 120})
    cursor, tamanhos = 0, []
    while True:
        r = consultar(base, cursor, cnpj=outro, uf="SP")
        if r["cstat"] != 138:
            conferir(r["cstat"] == 137, "fim da paginacao: esperava 137, veio %s" % r["cstat"])
            break
        tamanhos.append(len(r["docs"]))
        cursor = r["ultNSU"]
    conferir(tamanhos == [50, 50, 20], "lotes: %s" % tamanhos)

    passo("falhas enfileiradas: 'timeout' vira HTTP 504 e 'erro-http' vira HTTP 500")
    admin(base, "POST", "/admin/falhas", {"falhas": ["timeout", "erro-http"]})
    r = consultar(base, 0)
    conferir(r["http"] == 504, "timeout: esperava HTTP 504, veio %s" % r["http"])
    r = consultar(base, 0)
    conferir(r["http"] == 500, "erro-http: esperava HTTP 500, veio %s" % r["http"])
    r = consultar(base, 0)
    conferir(r["http"] == 200 and r["cstat"] == 138, "depois das falhas, volta ao normal")

    passo("nenhuma violacao: o request tem o formato que o ACBr envia")
    status, texto = chamar(base, "GET", "/admin/violacoes")
    conferir(status == 200 and texto == "(nenhuma)", "violacoes: %s" % texto)

    passo("modo ESTRITO: request fora do formato (ultNSU com 3 digitos) -> HTTP 400, sem consumir NSU")
    admin(base, "POST", "/admin/modo", {"estrito": True})
    r = consultar(base, 0, ult_nsu_texto="000")
    conferir(r["http"] == 400, "estrito: esperava HTTP 400, veio %s" % r["http"])
    admin(base, "POST", "/admin/modo", {"estrito": False})
    r = consultar(base, 0, ult_nsu_texto="000")
    conferir(r["http"] == 200, "leniente: aceita e registra, veio HTTP %s" % r["http"])
    status, texto = chamar(base, "GET", "/admin/violacoes")
    conferir("ultNSU" in texto, "a violacao deveria ter sido registrada: %s" % texto)

    passo("zerar: volta ao inicio")
    admin(base, "POST", "/admin/zerar")
    conferir('"contas":[]' in admin(base, "GET", "/admin/estado"), "estado depois de zerar")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--url", default="http://127.0.0.1:9200", help="base do DFeSimulador")
    args = parser.parse_args()
    base = args.url.rstrip("/")
    try:
        roteiro(base)
    except Falha as erro:
        print("FALHOU: %s" % erro, file=sys.stderr)
        return 1
    print("Roteiro concluido: tudo como esperado.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
