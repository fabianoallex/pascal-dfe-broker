# Changelog

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), e as versões
seguem o [Versionamento Semântico](https://semver.org/lang/pt-BR/). Enquanto a versão for 0.x,
uma versão minor pode mudar o jeito de compilar ou a configuração; toda mudança desse tipo
aparece aqui.

## [Unreleased]

## [0.2.0] - 2026-10-05

### Mudado

- **Dependência nova: [pascal-common-faa](https://github.com/fabianoallex/pascal-common-faa)
  1.1.1**, em `vendor/pascal-common-faa`. O broker AMQP embutido
  ([pascal-amqp-faa](https://github.com/fabianoallex/pascal-amqp-faa)) foi para a **v0.1.0**,
  que tirou dele os atomics, o monitor e o pool de threads e passou a exigir a pascal-common-faa.
  Pela regra de uma cópia por aplicação, quem fornece essa cópia é o projeto que compila, não
  o amqp. **Quem já tem um clone precisa inicializar o submódulo novo, sem `--recursive`:**

  ```
  git submodule update --init vendor/pascal-amqp-faa vendor/pascal-common-faa
  ```

  Nos `.lpi`, `pascal_common_faa` é o primeiro pacote, apontando para
  `vendor/pascal-common-faa/packages` com `Prefer="True"` (uma cópia registrada na IDE não
  ganha dela); nos `.dproj`, `vendor\pascal-common-faa\src` entrou no caminho de busca.
- O broker embutido roda os atores das filas num pool próprio, e não mais no pool que divide
  com os callbacks do cliente AMQP no mesmo processo. Um teste novo
  (`Publicar_ComPcPoolSaturado_NaoDependeDoPool`) prova que, com o pool do processo saturado,
  declarar, publicar com confirmação e ler continua levando milissegundos.
- `tools/docker/testar-linux.sh` compila tudo com `heaptrc` e confere a linha
  `0 unfreed memory blocks` no arquivo de `HEAPTRC=log=`: no FPC do Debian o relatório não sai no
  console, e o script antes nem ligava o `heaptrc`. A integração ACBr x simulador também passou a
  ter `heaptrc` no Windows.

### Adicionado

- **Consumidor Pascal com tela** (`exemplos/consumidor/pascal/ConsumidorDFeVcl`, VCL e LCL num
  fonte só), usando só o cliente AMQP: fila própria ou nomeada, salva o XML antes do `Ack`,
  deduplica pela chave e manifesta pelo comando `comando.manifestacao`.
- `exemplos/consumidor/pascal/ConsumidorDFeVcl/prova/ProvaFechamento`: fecha o consumidor com
  trabalho em andamento (pool ocupado ou entregas em voo) e registra a linha do tempo.
- FAQ em inglês, guia para explorar o projeto com um agente de IA e `docs/roadmap.md`.

### Corrigido

- **Consumidor Pascal: fechar a janela durante uma queda do broker podia rodar código contra a
  janela já liberada.** O aviso de "conexão caiu" fica numa fila do pool de threads do processo;
  se a janela fechava antes de ele rodar, o aviso rodava depois, quando o pool era liberado no
  fim do programa (medido no FPC/LCL: access violation). Agora a janela conta esses avisos e
  espera por eles ao fechar (`OnCloseQuery`).

## [0.1.0] - 2026-09-20

Pré-lançamento para demonstração com o simulador da SEFAZ (pacote Windows x64). Nunca executado
contra a SEFAZ real. Ver a [release](https://github.com/fabianoallex/pascal-dfe-broker/releases/tag/v0.1.0).

[Unreleased]: https://github.com/fabianoallex/pascal-dfe-broker/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/fabianoallex/pascal-dfe-broker/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/fabianoallex/pascal-dfe-broker/releases/tag/v0.1.0
