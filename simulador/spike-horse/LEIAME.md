# Spike do Horse como casca HTTP do simulador (descartável)

Pergunta: o Horse (`vendor/horse`, v3.3.0, commit `72cc45f`) serve para hospedar o
simulador da SEFAZ nos **dois** compiladores? Rotas em `SpikeHorseRotas.pas`
(unit única, compartilhada); `SpikeHorse.lpr` (FPC) e `SpikeHorse.dpr/.dproj` (Delphi).
Cenários (`testar-cenarios.sh`): corpo XML com acentos devolvido byte a byte, cabeçalhos
`Content-Type`/`SOAPAction`, HTTP 500, resposta de ~360 KB, 4 chamadas concorrentes de 1 s.

## Resultado (2026-09-20)

| Alvo | Compila | Cenários |
|---|---|---|
| FPC 3.2.2 **Linux** x86_64 (Debian 12, Docker) | sim, Horse **sem alteração** | todos OK; 4×1 s em ~1,0 s |
| FPC 3.2.2 **Windows** x64 (Lazarus 4.0) | **só com 1 linha alterada em `Horse.FPC.inc`** (ver abaixo) | todos OK; 4×1,36 s |
| Delphi **Win32** (IDE, confirmado pelo usuário) | sim, Horse sem alteração | todos OK; 4×1,34 s; `len=29` no `/tipo` (caracteres, não bytes) |
| Delphi Win64 | não testado | — |

**Achado (Windows/FPC):** `Horse.FPC.inc` escolhe `const` para o comparador genérico quando
`CPU64 AND WINDOWS`, mas o `rtl-generics` deste FPC 3.2.2 declara `IEqualityComparer<T>` com
`constref` sempre (`packages/rtl-generics/src/generics.defaults.pas:77`) → erro
`No matching implementation for interface method "Equals(constref ...)"` em
`Horse.Core.Param.Header`. Contorno testado sem tocar o submódulo: copiar `vendor/horse/src`
e trocar `{$ELSEIF DEFINED(CPU64) AND DEFINED(WINDOWS)}` por `{$ELSEIF FALSE}`. Candidato a PR
upstream (decisão de 2026-09-20: por ora só fica documentado; avaliar abrir o PR depois). Consequência: o executável de distribuição (Linux/Docker) não é afetado; quem compilar
o simulador em FPC/Windows precisa do contorno até o Horse corrigir.

Também observado: em FPC `Req.Body` é a string de **bytes UTF-8** (`Length` conta bytes); no
Delphi é `UnicodeString` (confirmado: o mesmo corpo dá `len=41` no FPC e `len=29` no Delphi) e
o eco voltou byte a byte idêntico nos dois. Falta só levar o adaptador SOAP (`DFe.XmlTexto`)
a esse fluxo, o que é trabalho da fase A.

## Rodar

- Linux/Docker: `sh simulador/spike-horse/testar-linux.sh`
- Windows/FPC: compilar com o contorno acima, subir `SpikeHorse.exe 9100` e `sh testar-cenarios.sh`
- Delphi: abrir `PascalDfeBroker.groupproj` → `SpikeHorse` (Win32 ou Win64), rodar, e
  `sh simulador/spike-horse/testar-cenarios.sh 9100` num terminal com `curl` (Git Bash serve).
