# DFeSimulador em Docker: o simulador da SEFAZ (Distribuicao de DFe / manifestacao
# da NFe) para quem NAO usa Pascal. Nao e' a SEFAZ: ver simulador/LEIAME.md.
#
#   git submodule update --init vendor/horse
#   docker build -f simulador/Dockerfile -t dfe-simulador .
#   docker run --rm -p 127.0.0.1:9200:9200 dfe-simulador
#   docker run --rm -p 127.0.0.1:9200:9200 dfe-simulador --bind 0.0.0.0 --cenario /cenarios/basico.ini
#
# O contexto de build e' a RAIZ do repositorio (ver o .dockerignore).

FROM debian:bookworm-slim AS build
RUN apt-get update \
 && apt-get install -y --no-install-recommends fpc binutils \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /proj
COPY src ./src
COPY simulador/DFeSimulador.lpr simulador/DFe.Simulador.Principal.pas simulador/DFe.Simulador.Horse.pas ./simulador/
COPY vendor/horse/src ./vendor/horse/src
RUN mkdir -p /out/units \
 && cd simulador \
 && fpc -Mdelphi -Sh -O2 -Xs -dUseCThreads \
      -Fu/proj/src -Fi/proj/src -Fu/proj/vendor/horse/src \
      -FU/out/units -FE/out -oDFeSimulador DFeSimulador.lpr

FROM debian:bookworm-slim
# usuario comum: o simulador nao precisa de privilegio nenhum
RUN useradd --system --no-create-home --shell /usr/sbin/nologin simulador
COPY --from=build /out/DFeSimulador /usr/local/bin/dfe-simulador
COPY simulador/cenarios /cenarios
USER simulador
EXPOSE 9200
# Dentro do conteiner a escuta precisa ser em todas as interfaces, senao o
# `-p` do docker nao alcanca. Quem PUBLICA a porta decide quem enxerga: prefira
# -p 127.0.0.1:9200:9200 (a API admin nao tem autenticacao).
ENTRYPOINT ["/usr/local/bin/dfe-simulador"]
CMD ["--bind", "0.0.0.0", "--porta", "9200"]
