# Explorar o projeto com um agente de IA

Este projeto tem muitas peças (ACBr, broker AMQP, simulador da SEFAZ, host, consumidores) e um ambiente com detalhes (OpenSSL, libxml2, submódulos). Se você usa um agente de IA (Claude Code, Cursor, GitHub Copilot em modo agente, Codex…), ele pode fazer o trabalho braçal de colocar tudo para rodar e responder suas dúvidas **lendo a documentação do próprio repositório**.

Isto **não substitui** o [`guia-de-uso.md`](guia-de-uso.md): os prompts abaixo mandam o agente ler o guia e o README, em vez de repetir o que está lá. Se o guia estiver errado, o agente erra junto — e, se ele travar em algum ponto, abra uma issue: é um bug de documentação.

**Antes de começar**

- **Clone num caminho curto** (no Windows, algo como `C:\dev\dfe-broker`): há caminhos longos nos submódulos.
- Abra o agente **na pasta do clone**.
- Um agente **com acesso a terminal** consegue rodar tudo. Um chat **sem** ferramentas serve para *entender* o projeto (prompt 2), não para rodar.
- Você continua sendo o responsável: leia o que o agente pretende instalar ou executar antes de aprovar.

## Regras para o agente (cole sempre, no início)

Este bloco existe por um motivo real: consultar a Distribuição de DFe **com o mesmo CNPJ que outro sistema já consulta** faz a SEFAZ bloquear o CNPJ por 1 hora para todos (ver "Antes de usar com o certificado de uma empresa" no README). Um agente entusiasmado não sabe disso, a menos que você diga.

```
Você vai me ajudar a explorar o projeto pascal-dfe-broker, nesta pasta. Regras:

1. Só use o SIMULADOR da SEFAZ e homologação. NUNCA configure Ambiente=producao,
   NUNCA use um certificado digital real de empresa, e NUNCA ligue
   ManifestacaoAutomatica=true. O certificado de teste do projeto
   (tests/Integration/AcbrSim/cert-teste) é o único que você usa.
2. Não instale software, não altere variáveis de ambiente e não mexa em nada fora
   desta pasta sem me perguntar antes e dizer o que vai fazer.
3. Não faça commit, push nem apague arquivos que você não criou.
4. Fonte da verdade: README.md, docs/guia-de-uso.md e docs/faq.md. O CLAUDE.md é o
   diário de quem DESENVOLVE o projeto: use só para consultar um detalhe pontual,
   não para aprender o projeto.
5. Seja honesto: diga o que você EXECUTOU e o que apenas LEU. Não afirme que algo
   funciona sem ter rodado. Se um comando falhar, mostre o erro e explique; não
   invente uma solução escondida.
6. Se uma porta já estiver ocupada (5672 do AMQP, 9200 do simulador), escolha outra
   e me avise. Ao terminar, encerre os processos que você iniciou.
```

## Prompt 1 — Colocar a demo para rodar

Para ver documentos chegando numa fila, sem certificado.

```
[cole as regras acima]

Objetivo: colocar para rodar a demo sem certificado do projeto e me mostrar
documentos chegando numa fila.

1. Leia o README.md ("Veja funcionando, sem certificado" e "Como compilar e rodar")
   e o docs/guia-de-uso.md, seção 4 (roteiro prático).
2. Descubra meu sistema operacional e o que já tenho instalado (Lazarus/FPC,
   Delphi, Docker, Python). Se eu estiver no Windows x64, considere primeiro o
   pacote pronto da release do GitHub (é uma PRE-RELEASE: use a página
   https://github.com/fabianoallex/pascal-dfe-broker/releases, não "latest"), que
   dispensa compilar; se não, compile a partir do fonte, seguindo o README.
3. Me diga o plano ANTES de executar: o que vai instalar/baixar/compilar e quanto
   deve demorar.
4. Execute o roteiro do guia: simulador, broker (host console) e um consumidor.
   Publique alguns documentos pelo simulador e mostre a saída do consumidor.
5. Ao final, resuma em poucas linhas o que rodou, o que aparece onde, e como
   encerrar tudo.
```

## Prompt 2 — Entender como funciona (serve para chat sem terminal)

```
[cole as regras acima, ou só leia-as como contexto]

Leia o README.md, docs/guia-de-uso.md e docs/faq.md e me explique, para alguém que
nunca viu o projeto: o que ele resolve, como um documento vai da SEFAZ até o meu
sistema, e o que eu preciso ter (e NÃO preciso ter) para usar. Use os termos do
glossário do guia. Termine listando o que o próprio projeto diz que NÃO está
provado (seção "O que NÃO está provado" do guia).
```

Depois dá para perguntar o que quiser ("por que a consulta é de hora em hora?", "o que é o cursor de NSU?", "como funciona a manifestação?").

## Prompt 3 — Consumir os documentos na minha linguagem

O broker fala AMQP 0-9-1, então qualquer cliente AMQP serve.

```
[cole as regras acima]

Objetivo: escrever um consumidor na linguagem <SUA LINGUAGEM> que receba os
documentos do pascal-dfe-broker.

1. Leia exemplos/consumidor/README.md: ele descreve o contrato (exchange, routing
   key, corpo do XML, fila própria x nomeada, deduplicação pela chave, Ack depois
   de processar). O exemplo em Python (exemplos/consumidor/python/consumir.py) e o
   em Pascal (exemplos/consumidor/pascal) mostram o comportamento esperado.
2. Escreva o consumidor numa pasta nova (exemplos/consumidor/<linguagem>/) e me
   diga quais bibliotecas usou.
3. Suba a demo (guia de uso, seção 4) e prove que o seu consumidor recebe os
   documentos. Diga claramente o que testou e o que não testou.
```

Se o resultado ficar bom, considere contribuir: consumidores em outras linguagens são bem-vindos (ver [`CONTRIBUTING.md`](../CONTRIBUTING.md)).

## Prompt 4 — Contribuir com um novo tipo de documento (CT-e, MDF-e…)

```
[cole as regras acima]

Objetivo: entender o que é preciso para adicionar suporte a <CT-e | MDF-e> ao
projeto.

Leia CONTRIBUTING.md e docs/architecture.md (contrato de provider e convenção de
routing-key) e olhe como o provider de NF-e foi feito (src/DFe.Provider.NFe.pas e
seus testes). Me apresente um PLANO com os arquivos a criar, os testes exigidos
e as decisões que precisam de um humano (por exemplo, a routing-key de eventos).
Não escreva código antes de eu aprovar o plano.
```

## Se o agente travar

- **Porta 5672 ocupada** é o tropeço mais comum (Docker e WSL costumam usá-la). O agente deve trocar de porta numa cópia do `dfe.ini` na mesma pasta; a regra 6 já cobre isso.
- **Peça o erro completo** e o que ele já tentou; um agente que "vai tentando" sem mostrar o erro esconde o problema.
- Compare com o [`guia-de-uso.md`](guia-de-uso.md) e com [`dependencias-runtime.md`](dependencias-runtime.md) (OpenSSL, libxml2, XSDs): a maior parte dos tropeços de ambiente está ali.
- Se o guia estava errado ou incompleto, **abra uma issue** com o prompt usado e o ponto onde travou. Isso melhora a documentação para o próximo.
