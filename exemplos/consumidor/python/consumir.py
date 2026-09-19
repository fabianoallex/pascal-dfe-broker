#!/usr/bin/env python3
"""Consumidor de exemplo do pascal-dfe-broker (Python + pika, um cliente AMQP 0-9-1 comum).

O broker publica cada documento/evento na exchange topic "dfe" com a routing-key
    <tipo>.<categoria>.<uf>.<cnpj>          ex.: nfe.documento.sp.12345678000199
                                                 nfe.evento.cancelamento.sp.12345678000199
e o corpo e' o XML do item, em UTF-8.

Dois jeitos de consumir:

  1. Fila PROPRIA (padrao): este consumidor declara uma fila exclusiva, ligada ao
     padrao --padrao (padrao 'nfe.#'). Cada consumidor recebe uma COPIA de tudo que
     casa com o padrao (pub/sub). A fila some quando o consumidor sai.

  2. Fila NOMEADA (--fila documentos): le uma fila que ja' existe (a do [fila:*] do
     dfe.ini, duravel). Varios consumidores da MESMA fila dividem o trabalho.

Entrega "pelo menos uma vez": o mesmo documento pode chegar duas vezes (por exemplo
depois de uma falha do broker no meio de um lote). A CHAVE DE ACESSO identifica o
documento -- deduplique por ela (aqui, um set em memoria; em producao, o seu banco).

    pip install pika
    python consumir.py --padrao "nfe.documento.#"
    python consumir.py --fila documentos --usuario guest --senha guest
"""
import argparse
import sys
import xml.etree.ElementTree as ET

import pika

EXCHANGE = "dfe"


def sem_namespace(tag):
    return tag.split("}", 1)[-1]


def campos(xml_bytes):
    """Extrai os campos mais uteis do resumo (resNFe/resEvento) ou do documento completo."""
    raiz = ET.fromstring(xml_bytes)
    achados = {}
    for no in raiz.iter():
        nome = sem_namespace(no.tag)
        if nome in ("chNFe", "xNome", "vNF", "dhEmi", "tpEvento", "xEvento", "nProt") and no.text:
            achados.setdefault(nome, no.text.strip())
    # no documento completo (procNFe) a chave esta no atributo Id de infNFe ("NFe" + 44 digitos)
    if "chNFe" not in achados:
        for no in raiz.iter():
            if sem_namespace(no.tag) == "infNFe" and no.get("Id", "").startswith("NFe"):
                achados["chNFe"] = no.get("Id")[3:]
    return sem_namespace(raiz.tag), achados


def principal():
    # uma linha por mensagem, mesmo com a saida redirecionada (pipe/arquivo)
    sys.stdout.reconfigure(line_buffering=True)
    ap = argparse.ArgumentParser(description="Consumidor de exemplo do pascal-dfe-broker")
    ap.add_argument("--host", default="127.0.0.1", help="use 127.0.0.1, nao 'localhost' (pode resolver para ::1)")
    ap.add_argument("--porta", type=int, default=5672)
    ap.add_argument("--usuario", default="guest")
    ap.add_argument("--senha", default="guest")
    ap.add_argument("--vhost", default="/")
    grupo = ap.add_mutually_exclusive_group()
    grupo.add_argument("--padrao", default="nfe.#", help="fila propria ligada a este padrao topic (padrao: nfe.#)")
    grupo.add_argument("--fila", help="le uma fila nomeada que ja existe (ex.: documentos)")
    args = ap.parse_args()

    conexao = pika.BlockingConnection(pika.ConnectionParameters(
        host=args.host, port=args.porta, virtual_host=args.vhost,
        credentials=pika.PlainCredentials(args.usuario, args.senha)))
    canal = conexao.channel()

    if args.fila:
        fila = args.fila
        canal.queue_declare(queue=fila, passive=True)  # tem de existir (o dfe.ini a declara)
        origem = "fila '%s'" % fila
    else:
        # declarar a exchange e' idempotente, desde que igual: topic, duravel
        canal.exchange_declare(exchange=EXCHANGE, exchange_type="topic", durable=True)
        fila = canal.queue_declare(queue="", exclusive=True).method.queue
        canal.queue_bind(queue=fila, exchange=EXCHANGE, routing_key=args.padrao)
        origem = "fila propria ligada a '%s'" % args.padrao

    vistas = set()  # chaves ja' processadas (dedup de "pelo menos uma vez")
    print("Consumindo %s em %s:%d. Ctrl+C para sair.\n" % (origem, args.host, args.porta))

    def ao_receber(ch, metodo, props, corpo):
        # routing-key: <tipo>.<categoria>.<uf>.<cnpj>; categoria 'evento' tem um segmento a mais (o tipo do evento)
        partes = metodo.routing_key.split(".")
        cnpj, uf = partes[-1], partes[-2]
        try:
            tipo_xml, c = campos(corpo)
        except ET.ParseError as erro:
            print("XML ilegivel (%s) -- descartado: %s" % (erro, metodo.routing_key))
            ch.basic_ack(metodo.delivery_tag)
            return
        chave = c.get("chNFe", "?")
        repetido = (tipo_xml, chave, c.get("tpEvento")) in vistas
        vistas.add((tipo_xml, chave, c.get("tpEvento")))
        print("%s  %s  cnpj=%s uf=%s" % ("REPETIDO" if repetido else "novo    ", metodo.routing_key, cnpj, uf))
        print("          %s  chave=%s" % (tipo_xml, chave))
        detalhes = ", ".join("%s=%s" % (k, v) for k, v in c.items() if k not in ("chNFe",))
        if detalhes:
            print("          %s" % detalhes)
        # confirma DEPOIS de processar: se cair antes, o broker entrega de novo
        ch.basic_ack(metodo.delivery_tag)

    canal.basic_consume(queue=fila, on_message_callback=ao_receber)
    try:
        canal.start_consuming()
    except KeyboardInterrupt:
        print("\nsaindo")
    finally:
        conexao.close()


if __name__ == "__main__":
    principal()
