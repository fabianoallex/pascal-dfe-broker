#!/usr/bin/env python3
"""Envia um comando de MANIFESTACAO do destinatario ao pascal-dfe-broker (Python + pika).

Publica na exchange "dfe", routing-key "comando.manifestacao", um corpo de texto
chave=valor, uma por linha:

    Alias=matriz                      # a secao [certificado:matriz] do dfe.ini
    ChaveAcesso=<44 digitos>
    TipoEvento=ciencia                # ciencia | confirmacao | desconhecimento | operacaonaorealizada
    Justificativa=...                 # so' operacaonaorealizada: 15 a 255 caracteres

O broker valida ANTES de falar com a SEFAZ (chave de 44 digitos, tipo conhecido,
justificativa no tamanho e so' com caracteres que o schema aceita). Comando invalido
e' descartado e aparece no log do broker. O RESULTADO sai como um evento normal, na
mesma exchange:

    nfe.evento.<tipo>.<uf>.<cnpj>                  a SEFAZ registrou (ex.: nfe.evento.ciencia.sp.123...)
    nfe.evento.manifestacaorejeitada.<uf>.<cnpj>   a SEFAZ rejeitou (o corpo traz cStat/xMotivo)

Basta assinar 'nfe.evento.#' (ver consumir.py) para receber o resultado.

    pip install pika
    python manifestar.py --alias matriz --chave 35260912345678000199550010000000011000000012 --tipo ciencia
"""
import argparse

import pika

EXCHANGE = "dfe"
ROUTING_KEY = "comando.manifestacao"
TIPOS = ("ciencia", "confirmacao", "desconhecimento", "operacaonaorealizada")


def principal():
    ap = argparse.ArgumentParser(description="Comando de manifestacao do pascal-dfe-broker")
    ap.add_argument("--alias", required=True)
    ap.add_argument("--chave", required=True, help="chave de acesso, 44 digitos")
    ap.add_argument("--tipo", required=True, choices=TIPOS)
    ap.add_argument("--justificativa", default="", help="obrigatoria em operacaonaorealizada")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--porta", type=int, default=5672)
    ap.add_argument("--usuario", default="guest")
    ap.add_argument("--senha", default="guest")
    ap.add_argument("--vhost", default="/")
    args = ap.parse_args()

    if len(args.chave) != 44 or not args.chave.isdigit():
        ap.error("a chave de acesso tem 44 digitos")
    if args.tipo == "operacaonaorealizada" and not (15 <= len(args.justificativa) <= 255):
        ap.error("operacaonaorealizada exige --justificativa de 15 a 255 caracteres")

    linhas = ["Alias=" + args.alias, "ChaveAcesso=" + args.chave, "TipoEvento=" + args.tipo]
    if args.tipo == "operacaonaorealizada":
        linhas.append("Justificativa=" + args.justificativa)
    corpo = "\n".join(linhas).encode("utf-8")

    conexao = pika.BlockingConnection(pika.ConnectionParameters(
        host=args.host, port=args.porta, virtual_host=args.vhost,
        credentials=pika.PlainCredentials(args.usuario, args.senha)))
    canal = conexao.channel()
    canal.exchange_declare(exchange=EXCHANGE, exchange_type="topic", durable=True)
    canal.basic_publish(exchange=EXCHANGE, routing_key=ROUTING_KEY, body=corpo,
                        properties=pika.BasicProperties(content_type="text/plain", delivery_mode=2))
    conexao.close()
    print("comando enviado (o resultado sai em nfe.evento.<tipo>.<uf>.<cnpj>, e no proximo tick do host, ate 60 s)")


if __name__ == "__main__":
    principal()
