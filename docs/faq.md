# Perguntas frequentes

Respostas curtas. Para o passo a passo, veja o [`guia-de-uso.md`](guia-de-uso.md); para o "porquê" das decisões, [`architecture.md`](architecture.md).

## Sobre o projeto

**Funciona com a SEFAZ de verdade?**
Não sabemos. O autor não tem certificado ICP-Brasil, então nunca foi executado contra a SEFAZ real (nem em homologação). Funciona de ponta a ponta com o componente ACBr **real** contra um simulador construído a partir das Notas Técnicas — e a fidelidade do simulador é a leitura que fazemos delas. Se você tem certificado, a [issue #1](https://github.com/fabianoallex/pascal-dfe-broker/issues/1) é um roteiro de validação em homologação.

**Para quem é?**
Para quem precisa receber os documentos fiscais em que o CNPJ da empresa aparece (NF-e emitidas contra ela) e quer entregá-los a um ou mais sistemas — ERP, BI, conciliação, arquivo — sem pagar um SaaS e sem reimplementar NSU, certificado e manifestação dentro de cada sistema.

**Em que difere de um SaaS de consulta de notas?**
Você roda na sua infraestrutura, com o seu certificado (que não sai da sua máquina), sem mensalidade por CNPJ, e o código é aberto. O preço: **você opera**. Não há suporte contratado, e o projeto ainda não foi validado contra a SEFAZ real.

**Só NFe?**
Na v1, sim. O contrato de provider e o [`CONTRIBUTING.md`](../CONTRIBUTING.md) existem justamente para que CT-e e MDF-e entrem por contribuição. Ao fazê-lo, lembre-se de que o código de "consumo indevido" não é o mesmo em todos os tipos (656 na NF-e e no CT-e, 678 no MDF-e).

**E a emissão de notas?**
Fora do escopo. É só a *Distribuição de DFe* (receber) e a manifestação do destinatário.

**Que licença?**
MIT neste repositório. O ACBr é LGPLv3 e a integração preserva a separação: o projeto não incorpora código do ACBr sob MIT. Como o ACBr é compilado junto no binário, **releia a LGPL antes de distribuir um binário comercial** — esta resposta não é aconselhamento jurídico.

## Uso

**Preciso ter Delphi?**
Não. O projeto compila com **FPC/Lazarus**, que é gratuito (Windows e Linux). Delphi é suportado, e o Serviço Windows é o único componente só de Delphi (no Linux, o console sob systemd faz o mesmo papel).

**Meu sistema não é Pascal. Como consumo?**
Com qualquer cliente AMQP 0-9-1 (pika, amqplib, RabbitMQ.Client, Bunny…). Basta a exchange `dfe` e a routing-key. Há dois consumidores de exemplo em Python em [`exemplos/consumidor/`](../exemplos/consumidor/README.md). Consumidores em outras linguagens ainda não foram testados (mas o protocolo é padrão).

**Meu sistema é Delphi. Consumo como?**
Com o cliente AMQP do [pascal-amqp-faa](https://github.com/fabianoallex/pascal-amqp-faa), o mesmo broker embutido, ou qualquer cliente AMQP 0-9-1. O exemplo pronto é o [`ConsumidorDFeVcl`](../exemplos/consumidor/README.md#consumidor-em-pascal-delphi-e-lazarus): uma tela VCL/LCL (um só fonte) que conecta, consome fila própria ou nomeada, salva o XML e só então confirma, deduplica pela chave e envia a manifestação — usando só o cliente AMQP. Compila e roda no Delphi (VCL, Win32) e no Lazarus/FPC (Windows); no Linux só compila e linka.

**Preciso instalar RabbitMQ?**
Não: o broker vem embutido. Se você já tem um RabbitMQ, use `Modo=externo` no `dfe.ini`.

**Posso perder documento?**
O cursor de NSU só avança depois que o broker confirma o lote inteiro, com escrita atômica, e as filas são duráveis. O preço é a entrega **pelo menos uma vez**: o mesmo documento pode chegar duas vezes; deduplique pela **chave de acesso** (44 dígitos). Um consumidor que caia depois de receber, mas antes de confirmar (`ack`), recebe a mensagem de novo. Uma fila **sem consumidor e sem fila ligada** descarta a mensagem (é pub/sub): por isso o `dfe.ini` deve declarar ao menos uma `[fila:*]`.

**Qual a diferença entre fila própria e fila nomeada?**
Fila **própria**: o consumidor a declara, recebe uma cópia e ela some quando ele sai. Fila **nomeada**: declarada no `dfe.ini`, durável, acumula enquanto ninguém lê; vários consumidores da mesma fila dividem o trabalho. Para integrar um ERP, use a nomeada.

**Com que frequência ele consulta?**
No máximo uma vez por hora por certificado quando não há novidade (é o mínimo da SEFAZ). Não baixe `IntervaloBaseSegundos`: consultar antes gera o 656 (consumo indevido) e bloqueia o CNPJ por 1 hora. Se ainda há documentos a receber, ele continua buscando lotes no mesmo ciclo.

**Meu ERP já consulta a Distribuição de DFe. Posso rodar isto junto?**
É o principal risco. Aplicações diferentes consultando o **mesmo CNPJ** precisam seguir a mesma sequência de NSU; senão a SEFAZ responde 656 e o **CNPJ inteiro** fica bloqueado por 1 hora, para todos (NT 2014.002, seção 3.11.4). Combine antes; em dúvida, use homologação ou um CNPJ que ninguém consulta.

**Manifestar o destinatário é seguro?**
É um **ato fiscal**: registra um evento na NF-e da empresa. Por isso `ManifestacaoAutomatica` vem `false`. Não a ligue em produção sem o aval de quem responde pelo fiscal. A manifestação **manual** (por comando na fila) é uma decisão sua, documento a documento.

**Como troco o certificado antes de vencer?**
Adicione o novo como `[certificado:outro]`, com o **mesmo CNPJ**, e alterne o `Ativo` (o antigo para `false`, o novo para `true`) — o broker recarrega o arquivo sozinho. O cursor é do CNPJ/UF, não do certificado, então não há perda nem duplicação. Nunca deixe os dois `Ativo=true`: a configuração é recusada.

**Onde guardo a senha do certificado?**
Em uma variável de ambiente (`SenhaEnv=NOME` no `dfe.ini`), não no arquivo. Num Serviço Windows, a variável precisa ser **do sistema**.

## Operação e segurança

**Que dependências preciso instalar?**
OpenSSL 3 e **libxml2** (as duas obrigatórias, até para consultar) e os XSDs da NFe (já no submódulo do ACBr). `DFeBrokerConsole --config dfe.ini --verificar-ambiente` diz o que falta. Ver [`dependencias-runtime.md`](dependencias-runtime.md).

**O broker embutido é seguro?**
Por padrão escuta só em `127.0.0.1`, com `guest/guest`. Se abrir para a rede (`BindAddress=0.0.0.0`), **troque usuário e senha** e proteja a porta. O `dfe.ini` não tem, hoje, opção de TLS para o AMQP embutido; se precisar de conexão criptografada pela rede, mantenha o `BindAddress` em `127.0.0.1` e use uma VPN ou um túnel.

**Escala?**
O limite é a SEFAZ (uma consulta por hora por CNPJ), não o broker. O volume por certificado é de dezenas a alguns milhares de mensagens por dia — irrisório para o broker.

**Onde ficam os dados?**
Ao lado do `dfe.ini`: o cursor (`cursores.dat`), o WAL do broker (`broker/`) e, no serviço, os logs (`logs/`). Caminhos relativos valem em relação à pasta do arquivo de configuração.

**Posso rodar em Docker?**
O simulador tem `Dockerfile` (`simulador/`). Para o broker, ainda não há imagem oficial; ele roda no Linux sob systemd, e a suíte de testes roda em contêiner. Contribuições são bem-vindas.

## Simulador

**O simulador é a SEFAZ?**
Não. Ele responde conforme a leitura que o projeto faz das NTs, só para teste. Se essa leitura estiver errada, ele repete o erro.

**Posso usar o simulador no meu projeto, que não é este?**
Sim: é um servidor HTTP, e o seu cliente só precisa poder trocar a URL do serviço e falar HTTP (sem TLS). Há um roteiro em Python só com a biblioteca padrão: [`simulador/LEIAME.md`](../simulador/LEIAME.md).

**Por que preciso de certificado, mesmo em homologação?**
Porque os web services da SEFAZ exigem certificado ICP-Brasil real em qualquer ambiente. O simulador não exige (o projeto usa um certificado de teste autoassinado, público no repositório: **jamais o use fora de teste**).
