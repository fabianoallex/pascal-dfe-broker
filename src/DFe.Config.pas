unit DFe.Config;

{$I dfe.inc}

{ Formato de configuracao: INI, sem dependencia externa -- mesma filosofia
  de DFe.CursorStore.Arquivo e da propria resposta da ACBrLib (ver
  docs/architecture.md, "Integracao com ACBr"). JSON/YAML foram descartados
  de proposito: JSON tem API diferente entre Delphi (System.JSON) e FPC
  (fpjson), exigiria uma camada de abstracao; YAML nao tem suporte nativo
  em nenhum dos dois, exigiria biblioteca de terceiros. INI e' RTL padrao
  identica nos dois compiladores (unit IniFiles), legivel a olho nu.

  Formato:

    [dfe]
    IntervaloBaseSegundos=3600   ; opcional
    TickSegundos=60              ; opcional
    CursorPath=cursores.dat      ; opcional

    [certificado:matriz]
    Provider=nfe
    CnpjCpf=12345678000199
    UF=RS

  Cada secao 'certificado:<alias>' vira uma TDFeUnidadeTrabalho. Campos de
  certificado digital "de verdade" (caminho do .pfx, senha) ficam FORA
  deste arquivo de proposito -- pertencem a implementacao real de
  IDFeDistribuicaoClient (ACBrLib, ainda nao escrita), nunca ao core, que
  so precisa saber CnpjCpf/UF/qual provider usar. }

interface

uses
  SysUtils, Classes, IniFiles,
  DFe.Types,
  DFe.Provider,
  DFe.Orquestrador,
  DFe.Host.Loop;

type
  { Uma linha de configuracao de certificado, antes de virar
    TDFeUnidadeTrabalho. }
  TDFeConfigCertificado = record
    Alias: string;              // nome da secao (sem o prefixo 'certificado:'), so' para mensagem de erro
    ProviderIdentificador: string;
    Certificado: TDFeCertificado;
  end;

  TDFeConfigCertificadoArray = array of TDFeConfigCertificado;

  TDFeConfig = record
    IntervaloBaseSegundos: Integer;
    TickSegundos: Integer;
    CursorPath: string;
    Certificados: TDFeConfigCertificadoArray;
  end;

  { Fabrica de IDFeDistribuicaoClient para um certificado -- quem monta o
    orquestrador de verdade passa aqui a implementacao real (ACBrLib);
    testes passam uma fabrica que devolve fakes. 'of object' (metodo
    ligado), nao 'reference to' -- closures nao existem no FPC 3.2 (ver
    CLAUDE.md do pascal-amqp-faa, regra que vale aqui tambem). Isolado
    assim porque "como construir um client" (certificado, ACBrLib) e'
    decisao de quem hospeda, nao do parser de config. }
  TDFeClientFactory = function(const ACertificado: TDFeConfigCertificado): IDFeDistribuicaoClient of object;

{ Le e valida o arquivo de configuracao. Levanta excecao com o nome da
  secao problematica se uma secao 'certificado:*' estiver sem Provider,
  CnpjCpf ou UF -- falha alto e cedo, na inicializacao do host, em vez de
  criar uma unidade de trabalho quebrada em silencio. }
function CarregarConfig(const ACaminho: string): TDFeConfig;

{ Monta as unidades de trabalho a partir da config, resolvendo cada
  provider pelo identificador via TDFeProviderRegistry (levanta excecao se
  nao encontrar -- config referenciando provider nao registrado e' erro de
  configuracao/deploy, nao deve falhar em silencio) e usando
  AClientFactory para criar o client de cada certificado. Nao cria o
  cursor store nem o TDFeHostLoop -- isso e' responsabilidade de quem
  chama (ver TDFeConfig.CursorPath / TickSegundos). }
function MontarUnidades(const AConfig: TDFeConfig;
  const ACursorStore: IDFeCursorStore;
  const AClientFactory: TDFeClientFactory): TDFeUnidadeTrabalhoArray;

implementation

const
  SECAO_GLOBAL = 'dfe';
  PREFIXO_CERTIFICADO = 'certificado:';

function CarregarConfig(const ACaminho: string): TDFeConfig;
var
  LIni: TMemIniFile;
  LSecoes: TStringList;
  I, LIndice: Integer;
  LNomeSecao: string;
begin
  LIni := TMemIniFile.Create(ACaminho);
  try
    Result.IntervaloBaseSegundos := LIni.ReadInteger(SECAO_GLOBAL, 'IntervaloBaseSegundos', DFE_INTERVALO_BASE_SEGUNDOS_PADRAO);
    Result.TickSegundos := LIni.ReadInteger(SECAO_GLOBAL, 'TickSegundos', DFE_HOST_TICK_SEGUNDOS_PADRAO);
    Result.CursorPath := LIni.ReadString(SECAO_GLOBAL, 'CursorPath', 'cursores.dat');

    SetLength(Result.Certificados, 0);
    LSecoes := TStringList.Create;
    try
      LIni.ReadSections(LSecoes);
      for I := 0 to LSecoes.Count - 1 do
      begin
        LNomeSecao := LSecoes[I];
        if Pos(PREFIXO_CERTIFICADO, LowerCase(LNomeSecao)) <> 1 then
          Continue;

        LIndice := Length(Result.Certificados);
        SetLength(Result.Certificados, LIndice + 1);

        Result.Certificados[LIndice].Alias := Copy(LNomeSecao, Length(PREFIXO_CERTIFICADO) + 1, MaxInt);
        Result.Certificados[LIndice].ProviderIdentificador := LIni.ReadString(LNomeSecao, 'Provider', '');
        Result.Certificados[LIndice].Certificado.Identificador := Result.Certificados[LIndice].Alias;
        Result.Certificados[LIndice].Certificado.CnpjCpf := LIni.ReadString(LNomeSecao, 'CnpjCpf', '');
        Result.Certificados[LIndice].Certificado.UF := LIni.ReadString(LNomeSecao, 'UF', '');

        if Result.Certificados[LIndice].ProviderIdentificador = '' then
          raise Exception.CreateFmt('Config: secao "%s" sem "Provider"', [LNomeSecao]);
        if Result.Certificados[LIndice].Certificado.CnpjCpf = '' then
          raise Exception.CreateFmt('Config: secao "%s" sem "CnpjCpf"', [LNomeSecao]);
        if Result.Certificados[LIndice].Certificado.UF = '' then
          raise Exception.CreateFmt('Config: secao "%s" sem "UF"', [LNomeSecao]);
      end;
    finally
      LSecoes.Free;
    end;
  finally
    LIni.Free;
  end;
end;

function MontarUnidades(const AConfig: TDFeConfig;
  const ACursorStore: IDFeCursorStore;
  const AClientFactory: TDFeClientFactory): TDFeUnidadeTrabalhoArray;
var
  I: Integer;
  LProvider: IDFeProvider;
  LClient: IDFeDistribuicaoClient;
begin
  SetLength(Result, Length(AConfig.Certificados));
  for I := 0 to High(AConfig.Certificados) do
  begin
    LProvider := TDFeProviderRegistry.ObterPorIdentificador(AConfig.Certificados[I].ProviderIdentificador);
    if not Assigned(LProvider) then
      raise Exception.CreateFmt(
        'Config: certificado "%s" usa provider "%s", que nao esta registrado (a unit do provider foi linkada ao programa?)',
        [AConfig.Certificados[I].Alias, AConfig.Certificados[I].ProviderIdentificador]);

    LClient := AClientFactory(AConfig.Certificados[I]);
    Result[I] := TDFeUnidadeTrabalho.Create(LProvider, LClient,
      AConfig.Certificados[I].Certificado, ACursorStore, AConfig.IntervaloBaseSegundos);
  end;
end;

end.
