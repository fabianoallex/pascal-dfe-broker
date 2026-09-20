# Segurança

O DFe Broker manuseia um **certificado digital ICP-Brasil** (a identidade e a assinatura com valor legal de uma empresa) e documentos fiscais. Por isso, falhas de segurança merecem cuidado.

## Como reportar

**Não abra uma issue pública** com detalhes de uma vulnerabilidade. Use o relato privado do GitHub: aba **Security → Report a vulnerability** deste repositório. Se ela não estiver disponível, abra uma issue pública **apenas pedindo um contato privado**, sem descrever o problema.

Inclua, sem dados reais: a versão/commit, o que acontece, e como reproduzir. **Nunca** envie o `.pfx`, a senha ou XML fiscal real.

O projeto é mantido por uma pessoa, sem prazo contratual; a resposta é feita no melhor esforço.

## O que consideramos de segurança

- Vazamento da **senha ou do conteúdo do certificado** (log, mensagem de erro, arquivo de configuração, publicação na fila).
- Um documento ou comando de um terceiro que faça o broker **manifestar/enviar** algo sem que o operador tenha autorizado.
- Execução de código, leitura ou escrita de arquivos fora das pastas esperadas a partir de dados externos (XML da SEFAZ, mensagens da fila `dfe.comandos`, configuração).

## Conhecido e por projeto (não é vulnerabilidade)

- O **broker embutido** escuta só em `127.0.0.1` e vem com `guest/guest`. Ao abrir para a rede (`BindAddress=0.0.0.0`), troque usuário e senha e proteja a porta. O `dfe.ini` não tem opção de TLS para o AMQP embutido.
- Quem consegue publicar na exchange `dfe` com a routing-key `comando.manifestacao` **consegue pedir manifestações** com o certificado do alias indicado. Trate o acesso à fila de comandos como acesso ao certificado para fins fiscais.
- A **API de administração do simulador** (`/admin`) não tem autenticação: é uma ferramenta de teste. Não a exponha (no Docker, publique a porta só em `127.0.0.1`).
- O **certificado de teste** em `tests/Integration/AcbrSim/cert-teste/` é sintético, público, com senha `teste123`. Nunca o use fora de teste.
- O projeto **nunca foi executado contra a SEFAZ real**; ver o aviso no [`README.md`](README.md).

## Boas práticas ao operar

- Passe a senha do certificado por **variável de ambiente** (`SenhaEnv=`), não no arquivo. Num Serviço Windows, a variável deve ser **do sistema**.
- Restrinja a leitura do `.pfx` e do `dfe.ini` à conta do serviço.
- Mantenha OpenSSL e libxml2 atualizados: são bibliotecas de terceiros, carregadas em execução.
