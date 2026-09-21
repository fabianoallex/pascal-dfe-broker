# Roadmap

Este arquivo lista o que está **no radar** do projeto: evoluções naturais, dívidas conhecidas e lacunas de verificação. **Não é uma promessa nem tem prazo.** Serve para que quem quiser contribuir, ou só saber para onde o projeto pode ir, veja o quadro inteiro.

## Como isto se relaciona com as issues

As [issues abertas](https://github.com/fabianoallex/pascal-dfe-broker/issues) são a fila de trabalho **atual**: poucas, de propósito. À medida que uma é concluída, um item deste roadmap é promovido a issue. Assim a lista não cresce sem controle e nada aqui vira cobrança. Se você quer trabalhar em algo que ainda está só neste arquivo, abra uma issue referenciando o item (ou comente numa existente) e combinamos o escopo antes.

Legenda: **[#n]** = já é uma issue aberta · sem marca = só no radar.

---

## 1. Validar contra a SEFAZ real

O risco mais importante que resta. Tudo o que foi provado até aqui usa o [simulador](../simulador/LEIAME.md), que reflete a *nossa leitura* das Notas Técnicas ([`docs/referencias/`](referencias/README.md)), não a SEFAZ.

- **[#1]** Roteiro de validação em homologação com certificado real.
- Pontos que só a SEFAZ responde:
  - aceitação de acento em `xJust` (o client desliga `RetirarAcentos`; o XSD aceita, a SEFAZ não foi consultada);
  - `dhEvento` com `-03:00` fixo (hora de Brasília);
  - o fluxo completo de `EnviarEvento`, incluindo `cOrgao` 91.
- Parada do Serviço Windows com um ciclo em andamento (espera de até 60 s): implementada, mas nunca exercitada.

## 2. Novos tipos de documento

O contrato de provider ([`docs/architecture.md`](architecture.md), [`CONTRIBUTING.md`](../CONTRIBUTING.md)) existe justamente para isto. O escopo da v1 é NFe.

- **[#2]** Provider CT-e.
- **[#3]** Provider MDF-e.
- Cuidados que se aplicam a qualquer tipo novo:
  - o `cStat` de consumo indevido não é universal (656 em NFe e CT-e, 678 em MDF-e);
  - o client precisa repetir a conferência de lote completo (`ConferirLoteCompleto`), porque o ACBr engole erro de interpretação de `docZip`;
  - **fechar o vocabulário de `TipoEvento` antes de haver consumidores**: um código sem nome mapeado sai como número, e promovê-lo a nome depois muda a routing-key (interface pública).

## 3. Distribuição e operação

- **[#4]** Imagem Docker do `DFeBrokerConsole` (a base existe: Dockerfile de teste no Linux e o do simulador).
- Observabilidade: hoje só há log em arquivo. Faltam métricas (documentos publicados, último NSU, tempo desde o último ciclo, ocorrências de 656) e um health check.
- Aviso proativo de vencimento do certificado. Hoje a troca é manual (`Ativo=`) e depende de saber a data; um aviso em log/evento seria a versão barata da detecção automática.
- Recarga a quente da configuração do broker e da mudança de ambiente (hoje exigem reiniciar; só certificados recarregam).
- Broker externo (RabbitMQ) com TLS e autenticação: previsto (fala AMQP 0-9-1), pouco exercitado.
- O job `testar-simulador-docker` do CI ainda não rodou no GitHub.

## 4. Consumidores

Baixo custo e boa porta de entrada para contribuir. Hoje só o Python foi testado com um cliente de terceiros.

- **[#6]** Consumidor de exemplo em Node.js.
- **[#7]** Consumidor de exemplo em C# / .NET.
- **[#11]** Consumidor Pascal em modo console (servidor/Linux).
- Um guia de contrato e versionamento da routing-key e do payload para quem consome de outras linguagens.
- Um consumidor "oficial" que grave o XML em arquivo/banco, em vez de só exemplo.

## 5. Robustez do core

Limitações conhecidas e aceitas, que podem deixar de valer se o uso crescer.

- `TDFeCursorStoreArquivo` não é thread-safe para escritas concorrentes: assume o orquestrador sequencial. Vira problema se houver paralelismo por unidade.
- Fonte de comandos manuais: o ack sai ao enfileirar em memória; um crash entre o ack e o processamento perde o comando (basta reenviar, a SEFAZ devolve 573). Uma fila de processamento durável resolveria.
- O provider ignora em silêncio um schema desconhecido (para não travar o cursor). Falta um hook de log ou contador para essa perda não ser invisível.
- Consumidor com tela: queda/reconexão do broker e falha ao salvar não foram verificadas na tela.

## 6. Plataformas e verificação

- Delphi Win64 no consumidor VCL e no `DFeSimulador`; espelho DUnitX da integração por HTTP do simulador; caminhos de erro do `THTTPClient` (conexão recusada, timeout).
- Consumidor LCL em GTK2/Qt.
- Linux em ARM.
- O Delphi não roda no CI (só pela IDE). Um runner Windows com Delphi fecharia a maior assimetria do fluxo de verificação.
- Delphi para Linux: fora de alcance hoje (ver [`docs/linux.md`](linux.md)).

## 7. Simulador

- HTTPS opcional, só se houver demanda.
- Simular outros serviços além da Distribuição de DFe (Consulta Protocolo, Status do Serviço).
- Extrair para repositório próprio (o desenho já favorece: o núcleo não depende do broker). **Decidido em 2026-09-21 manter sob este projeto**; só se reabre por pedido concreto de usuários externos ou se o nosso uso pedir mais serviços (ver [`docs/simulador-standalone.md`](simulador-standalone.md)).
- Verificar se a ACBrLib permite trocar as URLs dos serviços: isso decide quem consegue apontar a própria aplicação para o simulador.
- PR ao Horse (`const` vs `constref` em `Horse.FPC.inc`, que hoje exige contorno no FPC/Windows).
- Propor ao projeto ACBr os achados acumulados em [`docs/acbr-achados.md`](acbr-achados.md): só quando o projeto estiver viabilizado e, de preferência, em uso pela comunidade.

## 8. Além da v1

- Manifestação automática segura para produção. É uma questão fiscal, não só técnica (hoje: nunca `ManifestacaoAutomatica=true` em produção sem aval fiscal). Um modo *dry-run* ou uma política por CNPJ poderia torná-la viável.
- Outros eventos de NFe além da manifestação, que hoje só são recebidos e publicados.

---

## Ordem sugerida

1. **#1**: sem a validação real, o resto se apoia numa leitura ainda não confrontada com a SEFAZ.
2. **#4** e observabilidade: o que permite alguém realmente rodar.
3. **#2/#3**, fechando antes o vocabulário de `TipoEvento`.
4. **#6/#7/#11**, em paralelo, como porta de entrada para contribuidores.
