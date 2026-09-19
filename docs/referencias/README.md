# Referências oficiais

Cópias locais das Notas Técnicas que definem os web services de Distribuição de DFe, baixadas para servirem de fonte de verdade citável — em vez de depender de memória ou de blogs de terceiros para regras que viram código (intervalo mínimo, significado de cStat, etc.).

**Isto é um retrato de um momento (2026-09-17), não uma assinatura ao vivo da SEFAZ.** As NTs são atualizadas pela Receita Federal/ENCAT sem aviso a este repositório. Antes de confiar num fato daqui para uma decisão de produção, confira a versão vigente no portal oficial — os links estão abaixo.

| Documento | Versão | Fonte oficial | Baixado em |
|---|---|---|---|
| `NT_2014.002_NFeDistribuicaoDFe_v1.02d.pdf` | 1.02d, março/2021 | https://www.nfe.fazenda.gov.br/portal (Nota Técnica 2014.002) | 2026-09-17 |
| `NT_2015.002_CTeDistribuicaoDFe_v1.00a.pdf` | 1.00a, agosto/2016 | https://www.cte.fazenda.gov.br/portal (Nota Técnica 2015/002) | 2026-09-17 |
| `NT_2015.002_MDFeDistribuicaoDFe_v1.00b.pdf` | 1.00b, março/2016 | https://portal.fazenda.sp.gov.br/servicos/mdfe (Nota Técnica 2015/002) | 2026-09-17 |
| `NT_2012.002_ManifestacaoDestinatario_v1.02.pdf` | 1.02, março/2012 | https://www.nfe.fazenda.gov.br/portal/exibirArquivo.aspx?conteudo=nrErNm+QeWE%3D (Nota Técnica 2012/002) | 2026-09-18 |
| *(não copiado, 4 MB)* MOC 7.0 — **Anexo I, Leiaute e Regras de Validação da NF-e e NFC-e**, v7.00 nov/2020 | 7.00 | https://www.nfe.fazenda.gov.br/portal/exibirArquivo.aspx?conteudo=J%2BI%2Bv4eN00E%3D (listagem: https://www.nfe.fazenda.gov.br/portal/listaConteudo.aspx?tipoConteudo=ndIjl+iEFdE%3D) | 2026-09-18 |

## Fatos extraídos que viraram código (e por quê valeu a pena buscar)

Antes desta busca, `DFe.Orquestrador.pas` tinha um backoff exponencial inventado (dobrando o intervalo até 24h) e `DFe.Types.ClassificarCStat` tratava 656 como o único código de "consumo indevido" universal. As três NTs mostram que **isso estava parcialmente errado**:

- **O intervalo mínimo é exatamente 1 hora**, confirmado nas três NTs (não um valor "conservador de design" como eu tinha marcado). Ver NFe NT 2014.002 v1.02d, seção 3.11.4, p.14: *"Se não existir mais documentos a serem retornados (cStat=137) o usuário deve aguardar uma hora para realizar nova consulta [...] o CNPJ é bloqueado por 1 hora [...] Decorrido o intervalo de tempo, o desbloqueio será automático."*
- **Não existe escalonamento documentado.** O bloqueio é sempre de 1 hora, fixo, com desbloqueio automático — não dobra a cada violação repetida. O backoff exponencial que eu tinha desenhado era engenharia defensiva minha, não uma exigência da SEFAZ; removido do orquestrador em favor do comportamento real (reagendar para +1h a partir do momento da rejeição, mesma cadência do intervalo base).
- **O código de "consumo indevido" NÃO é o mesmo em todos os tipos de documento**: NFe usa **656** (NT 2014.002, p.15) e CT-e também usa **656** (NT 2015/002 CT-e, p.12) — mas **MDF-e usa 678** (NT 2015/002 MDF-e, p.17), não 656. Isso significa que `IDFeProvider` precisa expor o próprio código de consumo indevido (cada provider sabe o seu), em vez de `DFe.Types.ClassificarCStat` assumir um número fixo universal.
- **Os demais códigos de infraestrutura são de fato compartilhados** entre os três tipos de documento, confirmados idênticos nas três NTs: `137` (nenhum documento localizado), `138` (documento localizado), `108` (serviço paralisado momentaneamente), `109` (serviço paralisado sem previsão).
- **Tamanho de lote**: até 50 documentos por lote (`loteDistDFeInt`), confirmado na NT do MDF-e (p.13) — mesmo layout de mensagem nos três serviços.
- **Documentos emitidos pela própria empresa não aparecem na distribuição dela** (NT MDF-e, p.13) — vale considerar isso em qualquer teste manual ("por que minha nota não apareceu?").

Essas correções estão refletidas em `docs/architecture.md` (seção "Modelo de erro e orquestrador") e no código (`DFe.Types.pas`, `DFe.Provider.pas`, `DFe.Orquestrador.pas`).

## Manifestação do destinatário — fatos que viraram código (verificados em 2026-09-18)

Fontes: **NT 2012/002 v1.02** (cópia aqui; páginas citadas são do PDF) e **MOC 7.0, Anexo I** (não copiado; páginas do PDF baixado em 2026-09-18). O portal exige cookie: `curl -L -c cj -b cj` na URL `exibirArquivo.aspx?conteudo=...`. Antes desta conferência, `DFe.Simulador.ReceberEvento` e `DFe.Manifestacao.InterpretarComando` codificavam regras **de memória**, e várias estavam erradas:

- **Chave inexistente NÃO é rejeição.** NT 4.9.9 (p. 9): quando a NF-e não existe no momento do recebimento, o evento é "armazenado [...] a vinculação do evento à respectiva NF-e fica prejudicada" e o resultado é **cStat 136 – "Evento registrado, mas não vinculado a NF-e"**. As regras G09/G11/G13 (p. 8–9) valem só "se a NF-e existir". O **494** ("Chave de Acesso inexistente") consta da lista de códigos da NT (p. 23) e do Anexo I (p. 147), mas **sem regra associada a evento** — o simulador o usava e deixou de usar. Nossa `CStatEventoRegistrado` (135/136/155) já tratava 136 como registrado.
- **Duplicidade = 573** "Rejeição: Duplicidade de Evento" (regra G07: `tpEvento + chNFe + nSeqEvento`; NT p. 8 e 23, Anexo I p. 148).
- **Autor ≠ destinatário da NF-e = 575** (G09, "se a NF-e existir"; NT p. 8/23, Anexo I p. 148).
- **`nSeqEvento` deve ser 1** (HP15 "informar 1", p. 4; regra H02 → **594**, "O número de sequência do evento informado é maior que o permitido"). O simulador aceitava 2.
- **Ciência depois de manifestação final = 655** (H06, p. 9): ciência (210210) informada após Confirmação (210200), Operação não Realizada (210240) ou Desconhecimento (210220). O inverso (final depois de ciência) é permitido.
- **`xJust` só na Operação não Realizada.** HP20 (p. 4): 15 a 255 caracteres, "este campo deve ser informado **somente** no evento de Operação não Realizada"; H01 (p. 9): obrigatório nela, senão **595**. **Correção de código**: `InterpretarComando` exigia justificativa também no desconhecimento e o client a enviava em qualquer tipo; agora só em 210240 (nos outros é descartada).
- **Regras da NT que o simulador NÃO modela**: H03/596 (prazo de 180 dias), H04/650 e H05/651 (NF-e cancelada/denegada), G11/G12/G13 (577/578/579, datas), G09/574 (autor ≠ emitente), H07/658 (n/a no Ambiente Nacional).
- **cOrgao = 91** para o Ambiente Nacional (HP08, p. 4). **Lote de até 20 eventos** (HP04); o client envia 1. **`tpEvento`**: 210200 Confirmação da Operação, 210210 Ciência da Operação, 210220 Desconhecimento da Operação, 210240 Operação não Realizada; `descEvento` sem acento ("Confirmacao da Operacao", "Ciencia da Operacao", "Desconhecimento da Operacao", "Operacao nao Realizada"). `Id` = `"ID" + tpEvento + chNFe + nSeqEvento` (rejeição 572).
- **Textos oficiais de status** (Anexo I, Tabela 4.4.1, p. 143): 108 "Serviço Paralisado Momentaneamente (curto prazo)", 109 "Serviço Paralisado sem Previsão", 128 "Lote de Evento Processado", 135 "Evento registrado e vinculado a NF-e", 136 "Evento registrado, mas não vinculado a NF-e", 137 "Nenhum documento localizado para o Destinatário", 138 "Documento localizado para o Destinatário". **999**: "Rejeição: Erro não catalogado (informar a mensagem de erro capturado no tratamento da exceção)" (p. 153). O simulador usa estes textos **sem acento** (fonte ASCII, ver a pendência de acentos no `RetInfEvento.XML`).
