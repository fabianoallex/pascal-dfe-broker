# Referências oficiais

Cópias locais das Notas Técnicas que definem os web services de Distribuição de DFe, baixadas para servirem de fonte de verdade citável — em vez de depender de memória ou de blogs de terceiros para regras que viram código (intervalo mínimo, significado de cStat, etc.).

**Isto é um retrato de um momento (2026-09-17), não uma assinatura ao vivo da SEFAZ.** As NTs são atualizadas pela Receita Federal/ENCAT sem aviso a este repositório. Antes de confiar num fato daqui para uma decisão de produção, confira a versão vigente no portal oficial — os links estão abaixo.

| Documento | Versão | Fonte oficial | Baixado em |
|---|---|---|---|
| `NT_2014.002_NFeDistribuicaoDFe_v1.02d.pdf` | 1.02d, março/2021 | https://www.nfe.fazenda.gov.br/portal (Nota Técnica 2014.002) | 2026-09-17 |
| `NT_2015.002_CTeDistribuicaoDFe_v1.00a.pdf` | 1.00a, agosto/2016 | https://www.cte.fazenda.gov.br/portal (Nota Técnica 2015/002) | 2026-09-17 |
| `NT_2015.002_MDFeDistribuicaoDFe_v1.00b.pdf` | 1.00b, março/2016 | https://portal.fazenda.sp.gov.br/servicos/mdfe (Nota Técnica 2015/002) | 2026-09-17 |

## Fatos extraídos que viraram código (e por quê valeu a pena buscar)

Antes desta busca, `DFe.Orquestrador.pas` tinha um backoff exponencial inventado (dobrando o intervalo até 24h) e `DFe.Types.ClassificarCStat` tratava 656 como o único código de "consumo indevido" universal. As três NTs mostram que **isso estava parcialmente errado**:

- **O intervalo mínimo é exatamente 1 hora**, confirmado nas três NTs (não um valor "conservador de design" como eu tinha marcado). Ver NFe NT 2014.002 v1.02d, seção 3.11.4, p.14: *"Se não existir mais documentos a serem retornados (cStat=137) o usuário deve aguardar uma hora para realizar nova consulta [...] o CNPJ é bloqueado por 1 hora [...] Decorrido o intervalo de tempo, o desbloqueio será automático."*
- **Não existe escalonamento documentado.** O bloqueio é sempre de 1 hora, fixo, com desbloqueio automático — não dobra a cada violação repetida. O backoff exponencial que eu tinha desenhado era engenharia defensiva minha, não uma exigência da SEFAZ; removido do orquestrador em favor do comportamento real (reagendar para +1h a partir do momento da rejeição, mesma cadência do intervalo base).
- **O código de "consumo indevido" NÃO é o mesmo em todos os tipos de documento**: NFe usa **656** (NT 2014.002, p.15) e CT-e também usa **656** (NT 2015/002 CT-e, p.12) — mas **MDF-e usa 678** (NT 2015/002 MDF-e, p.17), não 656. Isso significa que `IDFeProvider` precisa expor o próprio código de consumo indevido (cada provider sabe o seu), em vez de `DFe.Types.ClassificarCStat` assumir um número fixo universal.
- **Os demais códigos de infraestrutura são de fato compartilhados** entre os três tipos de documento, confirmados idênticos nas três NTs: `137` (nenhum documento localizado), `138` (documento localizado), `108` (serviço paralisado momentaneamente), `109` (serviço paralisado sem previsão).
- **Tamanho de lote**: até 50 documentos por lote (`loteDistDFeInt`), confirmado na NT do MDF-e (p.13) — mesmo layout de mensagem nos três serviços.
- **Documentos emitidos pela própria empresa não aparecem na distribuição dela** (NT MDF-e, p.13) — vale considerar isso em qualquer teste manual ("por que minha nota não apareceu?").

Essas correções estão refletidas em `docs/architecture.md` (seção "Modelo de erro e orquestrador") e no código (`DFe.Types.pas`, `DFe.Provider.pas`, `DFe.Orquestrador.pas`).
