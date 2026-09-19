# Linux

Estado (2026-09-18): o core, o client ACBr real e o simulador da SEFAZ **compilam e passam todos os testes em Linux x86_64** (Debian 12), em contêiner Docker. **Não testado**: Delphi para Linux, outras distribuições/arquiteturas (ARM), execução como serviço (systemd) e — como no Windows — TLS/HTTP reais com a SEFAZ.

## Como rodar

Do git-bash (Windows), Linux ou macOS, na raiz do repositório, com Docker:

```
tools/docker/testar-linux.sh              # suíte pura + integração ACBr×simulador
tools/docker/testar-linux.sh --so-pura    # só a suíte pura (~10 s depois da 1ª vez)
tools/docker/testar-linux.sh --sem-link   # integração SEM o link libxml2.so (a recusa que o operador veria)
```

A 1ª execução constrói a imagem `dfe-linux-teste` (`tools/docker/Dockerfile.linux-teste`, ~1 min, autocontida: `debian:bookworm-slim` + `fpc` + `lcl-nogui-2.2` + `lcl-units-2.2` + `libssl3` + `libxml2`). A integração precisa de `vendor/ACBr` inicializado (`tools/init-acbr-submodule.sh`). Resultado da última verificação:

| Suíte | Resultado |
|---|---|
| Pura (FPCUnit) | 227/227 |
| Integração ACBr × simulador (44 testes, inclui assinatura e validação XSD de eventos, acento no `xJust` e fuso do `dhEvento`) | 44/44 |

Ambiente: Debian 12, x86_64, FPC 3.2.2, Lazarus/LCL 2.2.6 `nogui`, OpenSSL **3.0.20**, libxml2 2.9.14. O executável de integração liga só a `libc` (libssl e libxml2 são carregadas em execução; **nenhuma** dependência de GTK/X11/Qt).

## O que o Linux exigiu (achados)

Tudo abaixo passou despercebido no Windows e só apareceu rodando no Linux — uma razão para não confiar em "compila no Windows".

1. **LCL sem interface gráfica.** O ACBr arrasta o LCL transitivamente mesmo num programa de console (ver `CLAUDE.md`, gotcha do LCL). No Linux isso fica resolvido compilando com o backend `nogui`: `uses Interfaces` (como no Windows) + `-dLCL -dLCLnogui` + os caminhos `lcl/units/x86_64-linux/nogui`, `lcl/units/x86_64-linux` e `components/lazutils/lib/x86_64-linux` do Lazarus (pacotes Debian `lcl-nogui-2.2`, `lcl-units-2.2`). Um host headless **não** depende de gtk/qt.
2. **`libxml2.so` é o link sem versão.** O ACBr procura exatamente esse nome, que no Debian/Ubuntu só o pacote `-dev` cria (o runtime traz `libxml2.so.2`). Confirmado em execução: sem o link, o client recusa com `EDFeAmbienteIndisponivel` ("...nao foi possivel carregar libxml2.so (...instale libxml2-dev, ou crie o link libxml2.so -> libxml2.so.2.)"); com `ln -s libxml2.so.2 libxml2.so` os testes passam. A libxml2 é obrigatória **sempre** (ver `docs/dependencias-runtime.md`).
3. **Exceções de ponto flutuante da FPU.** O FPC as deixa habilitadas e o código nativo em C (libxml2, OpenSSL) faz operações que as disparam: a inicialização da libxml2 derrubava o processo com `EInvalidOp: Invalid floating point operation`. Correção: `DFe.Ambiente.ACBr.PrepararParaBibliotecasNativas` (FPC: mascara as exceções da thread atual), chamada no construtor do client, a cada operação e no verificador. **A máscara vale por thread**: um host multithread deve chamá-la em cada thread que usar o client.
4. **OpenSSL 3.0.x não ativa o provider padrão.** Em Debian 12 / Ubuntu 22.04 (OpenSSL 3.0), `OSSL_PROVIDER_available('default')` é `0` no processo e **toda** operação de PKCS12 falha — `PKCS12_parse` devolve 0 com `digital envelope routines::unsupported / key gen error / mac generation error`, e o ACBr reporta "Erro ao ler informações do Certificado" para um `.pfx` **válido** (o `openssl` da linha de comando o lê). Nenhuma variação do `.pfx` (MAC SHA1/SHA256, 3DES/AES) mudou isso; `OPENSSL_init_crypto` com as flags de cifras/digests também não; só `OSSL_PROVIDER_load(nil, 'default')` resolveu. O verificador (`DFe.Ambiente.ACBr`) agora o ativa quando a versão é ≥ 3.0 — no Windows, com OpenSSL 3.2/3.5, o provider já vem ativo. **Sem esta correção, o broker não leria nenhum certificado num Debian 12/Ubuntu 22.04.**
5. **`Now` é UTC no FPC 3.2.2 em Linux** (medido no Debian 12 em Docker: `TZ` = UTC, `America/Sao_Paulo`, `America/Manaus`, `America/Noronha` e `/etc/localtime` apontando para cada uma — em todas, `Now` devolve UTC). O ACBr formata `dhEvento` com o fuso *do sistema* e escrevia `+00:00`, fora da lista da NT 2012/002 (`-02:00`, `-03:00`, `-04:00`). O broker agora não depende do fuso do sistema: `DFe.Fuso` escreve a hora de Brasília com `-03:00` fixo. **Não use `Now` como "hora local" no Linux neste projeto** (o cursor/relógio do orquestrador usa o relógio injetado; conferir se algum host novo precisar de hora local).

## Como um host Linux deve subir (recomendação)

1. Instalar o runtime: `apt install libssl3 libxml2` **e** o nome que o ACBr procura: `libxml2-dev` ou `ln -s libxml2.so.2 libxml2.so` (na pasta das bibliotecas).
2. Compilar com o backend `nogui` (item 1) e chamar `VerificarAmbienteACBr` na inicialização (ver `docs/dependencias-runtime.md`).
3. Sob systemd, o console é o host de produção (decisão 9 do `CLAUDE.md`, "sem daemonização própria"). O host ainda **não existe**; quando existir, valide aqui de novo.

## Limites

O contêiner roda os testes como `root`, com `/proj` somente-leitura; nada aqui exercita permissões de arquivo, o cursor de NSU em disco com outro usuário ou o comportamento sob systemd. Os testes de FPU/thread cobrem só a thread principal.
