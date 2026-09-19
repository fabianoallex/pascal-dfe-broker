unit DFe.Provider;

{$I dfe.inc}

{ Contrato de provider por tipo de documento (ver docs/architecture.md,
  secao "Contrato de provider"), e a fronteira que separa o que precisa de
  certificado digital real do que nao precisa (secao "Fronteira testavel
  sem certificado real").

  Nada aqui integra ACBr de verdade -- so as interfaces/contratos. A
  implementacao real de IDFeDistribuicaoClient (a unica peca que toca a
  SEFAZ) e' um pacote separado, ainda nao escrito; a implementacao de
  IDFeProvider para NFe tambem. }

interface

uses
  SysUtils,
  DFe.Types;

type
  { Adaptador fino que fala com a SEFAZ. A unica peca do sistema que exige
    certificado digital real. Tem uma implementacao real (via ACBr, ainda
    nao escrita) e uma implementacao de teste (stub que devolve fixtures
    gravadas), ambas atras desta mesma interface -- e' o que permite testar
    o resto do sistema sem certificado nenhum. }
  IDFeDistribuicaoClient = interface
    ['{6E2B7B1E-2B7C-4A2D-9C7B-1B7B2B7C4A2D}']
    { AUltimoNSU e' o cursor atual (0 na primeira consulta de um certificado).
      Consumo indevido NAO e' excecao: a SEFAZ responde normalmente com um
      cStat de rejeicao (656 para NFe/CT-e, 678 para MDF-e -- ver
      docs/referencias/README.md), entao a implementacao real deve devolver
      esse TDFeLoteBruto tal como veio, e o orquestrador classifica via
      DFe.Types.ClassificarCStat. So levantar excecao (ver DFe.Errors) quando
      a chamada em si falhar antes de existir uma resposta interpretavel. }
    function Consultar(const ACertificado: TDFeCertificado;
      const AUltimoNSU: Int64): TDFeLoteBruto;
  end;

  { Persistencia do cursor de NSU, namespaced por (tipo de documento,
    certificado, UF) -- e' o chamador de IDFeCursorStore (o core, nao o
    provider) que monta essa chave, o provider so pede/grava pelo Namespace
    que recebeu. Implementacao real: DFe.CursorStore.Arquivo.pas
    (TDFeCursorStoreArquivo) -- ver docs/architecture.md, "Persistencia do
    cursor de NSU", para a justificativa de nao usar SQLite nem o WAL do
    pascal-amqp-faa. }
  IDFeCursorStore = interface
    ['{3A1D9E4F-8C2A-4F1B-9E4F-8C2A4F1B9E4F}']
    { Namespace tipico: '<tipo>/<cnpjCpf>/<uf>', ex.: 'nfe/12345678000199/rs'
      (em homologacao, com o sufixo '/homologacao' -- ver MontarNamespaceCursor).
      Retorna 0 quando nao ha cursor gravado ainda para o namespace. }
    function ObterUltimoNSU(const ANamespace: string): Int64;

    { So deve ser chamado depois que os eventos daquele lote foram publicados
      com sucesso no broker -- nunca antes (ver docs/architecture.md,
      "Persistencia do cursor de NSU"). }
    procedure GravarUltimoNSU(const ANamespace: string; const ANSU: Int64);
  end;

  { O contrato que qualquer tipo de documento implementa: NFe na v1;
    CTe/MDFe depois, idealmente via contribuicao de terceiros (ver
    CONTRIBUTING.md). Decodificar e' a unica operacao com logica de negocio
    real -- e' pura (sem I/O), o que a torna testavel so com fixtures de
    TDFeLoteBruto, sem precisar de broker nem de certificado. }
  IDFeProvider = interface
    ['{9F4C2A7D-1E6B-4C8A-A2D7-1E6B4C8AA2D7}']
    { Codigo curto e estavel usado em routing-key, namespace de configuracao
      e namespace de persistencia de cursor: 'nfe', 'cte', 'mdfe', ... }
    function Identificador: string;

    { O codigo de cStat que a SEFAZ usa para "Rejeicao: Consumo Indevido"
      NESTE tipo de documento -- NAO e' universal (NFe/CT-e = 656,
      MDF-e = 678; ver docs/referencias/README.md, conferido em 2026-09-17
      contra as NTs oficiais). O orquestrador usa isto ao chamar
      DFe.Types.ClassificarCStat -- e' o provider quem sabe esse numero,
      nunca o core. }
    function CodigoConsumoIndevido: Integer;

    { Traduz o lote bruto (generico, ja sem o envelope gzip+base64) para o
      evento interno padronizado (TDFe.Types.TDFeEventoNormalizado), de
      acordo com os schemas especificos deste tipo de documento
      (resNFe/resEvento/procNFe ou equivalentes de CTe/MDFe). Nao publica no
      broker e nao persiste cursor -- isso e' responsabilidade do core, que
      chama este metodo e so depois publica e avanca o cursor. }
    function Decodificar(const ALote: TDFeLoteBruto;
      const ACertificado: TDFeCertificado): TDFeEventoNormalizadoArray;
  end;

  TDFeProviderArray = array of IDFeProvider;

  { Registro de providers disponiveis, para o core nao precisar conhecer
    'nfe'/'cte'/'mdfe' em tempo de compilacao. Decidido (2026-09-17):
    auto-registro via 'initialization' de unit -- ver comentario de
    Registrar abaixo e a secao "Contrato de provider" em
    docs/architecture.md para o porque (essencialmente: registro explicito
    numa config central exigiria o core, ou um arquivo compartilhado,
    conhecendo cada tipo de documento de antemao -- o oposto do que o
    projeto quer para contribuicao de terceiros).

    So chamar Registrar/Todos/ObterPorIdentificador depois que todas as
    units de provider desejadas ja foram linkadas ao programa (ou seja, na
    pratica, depois que o programa comecou a rodar) -- 'initialization' de
    unit roda inteiramente antes disso, em ordem determinada pelo linker,
    sempre em thread unica. Nao ha cenario real de leitura/escrita
    concorrente no registro. }
  TDFeProviderRegistry = class
  private
    class var FProviders: TDFeProviderArray;
  public
    { Cada provider chama isto na inicializacao da propria unit (secao
      'initialization'), ex.:

        initialization
          TDFeProviderRegistry.Registrar(TDFeProviderNfe.Create);
        end.

      Basta a unit do provider estar no 'uses' (direto ou indireto) do
      programa final para o provider ficar disponivel -- nenhum arquivo
      central precisa ser editado. Levanta excecao se Identificador ja
      estiver registrado (colisao de nome entre dois providers, tipicamente
      um bug ou um identificador mal escolhido por um novo provider). }
    class procedure Registrar(const AProvider: IDFeProvider);

    class function ObterPorIdentificador(const AIdentificador: string): IDFeProvider;

    { Devolve uma copia independente -- quem chama nao pode corromper o
      estado interno do registry escrevendo num indice do array devolvido. }
    class function Todos: TDFeProviderArray;
  end;

implementation

class procedure TDFeProviderRegistry.Registrar(const AProvider: IDFeProvider);
var
  LIndiceNovo: Integer;
begin
  if ObterPorIdentificador(AProvider.Identificador) <> nil then
    raise Exception.CreateFmt(
      'Provider "%s" ja registrado -- Identificador precisa ser unico entre todos os providers (ver IDFeProvider.Identificador)',
      [AProvider.Identificador]);

  LIndiceNovo := Length(FProviders);
  SetLength(FProviders, LIndiceNovo + 1);
  FProviders[LIndiceNovo] := AProvider;
end;

class function TDFeProviderRegistry.ObterPorIdentificador(const AIdentificador: string): IDFeProvider;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to High(FProviders) do
    if SameText(FProviders[I].Identificador, AIdentificador) then
    begin
      Result := FProviders[I];
      Break;
    end;
end;

class function TDFeProviderRegistry.Todos: TDFeProviderArray;
var
  I: Integer;
begin
  { Copia elemento a elemento -- FProviders e' array de interface (tipo
    gerenciado); Move/CopyMemory sobre ele corromperia o refcount das duas
    copias. SetLength sozinho nao basta: so copia sob demanda quando o
    array compartilhado e' redimensionado, nao protege contra escrita
    direta num indice do array devolvido. }
  Result := nil;
  SetLength(Result, Length(FProviders));
  for I := 0 to High(FProviders) do
    Result[I] := FProviders[I];
end;

end.
