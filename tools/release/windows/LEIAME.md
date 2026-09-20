# DFe Broker — pacote Windows x64 (demonstração)

> ⚠️ **Este pacote é uma demonstração com um SIMULADOR da SEFAZ.** O projeto **nunca foi executado contra a SEFAZ real** (o autor não tem certificado ICP-Brasil). Não use com o certificado de uma empresa sem ler o aviso no [README](https://github.com/fabianoallex/pascal-dfe-broker#antes-de-usar-com-o-certificado-de-uma-empresa) — em especial o risco de bloquear o CNPJ se outro sistema já o consulta.

Descompacte e rode: os executáveis, as bibliotecas (OpenSSL, libxml2, zlib), os XSDs da NFe e um certificado **de teste** já estão aqui. Nada é instalado e nada toca a SEFAZ.

## O que tem na pasta

| Arquivo | Para quê |
|---|---|
| `DFeBrokerConsole.exe` | O broker: consulta a distribuição, mantém o cursor de NSU e publica na fila AMQP (embutida). |
| `DFeSimulador.exe` | O "SEFAZ de mentira", com API de administração. |
| `DFeDemo.exe` | Demonstração mínima: publica NF-es sintéticas direto na fila (sem simulador). |
| `dfe.ini` | Configuração da demo (comentada). Portas 5672 (AMQP) e 9200 (simulador). |
| `demo-publicar.ps1` | Publica documentos no simulador e avança o relógio virtual. |
| `exemplos\python\` | Consumidor e emissor de comando de manifestação (Python) e o roteiro do simulador. |
| `cert-teste\valido.pfx` | Certificado **sintético** (CNPJ `11222333000181`, senha `teste123`). **Nunca use fora de teste.** |
| `Schemas\` | XSDs oficiais da NFe. |
| `*.dll` | OpenSSL, libxml2 e zlib (avisos em `THIRD-PARTY-NOTICES.txt`). |

**Requisitos:** Windows 10/11 x64; o *Microsoft Visual C++ Redistributable 2015–2022 (x64)* (a maioria dos PCs já tem; a `libxml2.dll` depende dele); Python 3 com `pip install pika` (só para os exemplos de consumidor).

> O Windows SmartScreen ou o antivírus podem avisar sobre executáveis não assinados. Se preferir não confiar no binário, [compile do fonte](https://github.com/fabianoallex/pascal-dfe-broker#como-compilar-e-rodar).

## Ver funcionando em 5 minutos

Abra o PowerShell **nesta pasta**, em vários terminais.

**1. O simulador**

```powershell
.\DFeSimulador.exe
```

**2. O broker**

```powershell
.\DFeBrokerConsole.exe --config dfe.ini
```

Você deve ver quatro linhas `[OK]` (OpenSSL, libxml2, XSDs e XSDs da manifestação) e o aviso `TRANSPORTE SIMULADO`. O broker já fez a primeira consulta: o simulador não tinha nada e abriu um bloqueio de 1 hora, como a SEFAZ faria.

**3. Um consumidor**

```powershell
python exemplos\python\consumir.py --padrao "nfe.#"
```

**4. Publique documentos** (em outro terminal)

```powershell
.\demo-publicar.ps1
```

O script publica 2 resumos de NF-e e 1 cancelamento no simulador e avança o **relógio virtual** em 1h01, para o bloqueio acabar. Em poucos segundos o consumidor mostra:

```
novo      nfe.documento.rs.11222333000181  cnpj=11222333000181 uf=rs
          resNFe  chave=35260998765432000110550010000000011000079198
          ...
novo      nfe.evento.cancelamento.rs.11222333000181  cnpj=11222333000181 uf=rs
          resEvento  chave=...  tpEvento=110111
```

(Antes de você avançar o relógio, o log do broker mostra `Consumo indevido (cStat=656)`: é exatamente a rejeição real da SEFAZ para uma consulta feita cedo demais, reproduzida de propósito.)

**5. Manifeste o destinatário** (use uma chave que apareceu no passo 4)

```powershell
python exemplos\python\manifestar.py --alias matriz --tipo ciencia --chave 35260998765432000110550010000000011000079198
```

O resultado volta como evento: `nfe.evento.ciencia.rs.11222333000181`.

**6. Teste a durabilidade:** com o broker parado, as mensagens ficam na fila `documentos`; ao religar, `python exemplos\python\consumir.py --fila documentos` as recebe.

Se a porta 5672 ou 9200 estiver ocupada (Docker, WSL…), troque `Porta=` e `SimuladorURL=` no `dfe.ini`, passe `--porta` ao simulador e aos scripts Python, e `-Simulador http://127.0.0.1:<porta>` ao `demo-publicar.ps1`.

Para parar: `Ctrl+C` no simulador e no broker. Para recomeçar do zero, apague `cursores.dat` e a pasta `broker\`.

## E depois?

- O guia completo, com o vocabulário, as funcionalidades e mais cenários (paginação, falhas, modo estrito): [`docs/guia-de-uso.md`](https://github.com/fabianoallex/pascal-dfe-broker/blob/main/docs/guia-de-uso.md).
- Perguntas frequentes: [`docs/faq.md`](https://github.com/fabianoallex/pascal-dfe-broker/blob/main/docs/faq.md).
- Usar com o seu certificado (em **homologação** primeiro) e nos ajudar a validar: [issue #1](https://github.com/fabianoallex/pascal-dfe-broker/issues/1). Um `dfe.ini` de produção parte de `hosts/console/dfe.exemplo.ini` no repositório; as DLLs deste pacote servem para testar, mas para produção obtenha e mantenha as suas (`docs/dependencias-runtime.md`).

## Licença e código-fonte

O DFe Broker é MIT. O executável contém o ACBr (LGPL v3), e as DLLs são de terceiros (`THIRD-PARTY-NOTICES.txt`). O código-fonte, a revisão exata do ACBr e as instruções para recompilar estão em <https://github.com/fabianoallex/pascal-dfe-broker>.
