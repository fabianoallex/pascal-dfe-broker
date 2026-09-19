unit DFe.Ambiente;

{$I dfe.inc}

{ Relatorio de AMBIENTE DE EXECUCAO -- ver docs/dependencias-runtime.md.

  O broker depende de coisas que NAO estao no binario: bibliotecas nativas
  (OpenSSL para certificado/TLS; libxml2 para ler QUALQUER resposta e para
  assinar/validar eventos) e os XSDs oficiais. Faltar qualquer uma nao aparece na compilacao; sem este
  relatorio so' se descobria na primeira chamada, disfarcado de "certificado
  invalido" ou "falha de comunicacao".

  Esta unit e' PURA (so' tipos, agregacao e texto): quem sabe VERIFICAR e'
  DFe.Ambiente.ACBr (que carrega as bibliotecas de verdade). Separado assim
  para o formato e a decisao "ambiente completo?" serem testaveis sem DLL
  nenhuma. Textos em ASCII de proposito (mesma convencao do resto do
  projeto). }

interface

type
  { Para que o ambiente e' verificado: OpenSSL, libxml2 e algum XSD sao
    necessarios em QUALQUER uso (a libxml2 le toda resposta do ACBr); a
    manifestacao (assinar/validar o evento) exige tambem os XSDs do evento. }
  TDFeUsoAmbiente = (uaDistribuicao, uaManifestacao);
  TDFeUsosAmbiente = set of TDFeUsoAmbiente;

  TDFeDependenciaAmbiente = record
    Nome: string;
    { Obrigatoria PARA OS USOS verificados; uma dependencia so' da manifestacao
      e' opcional numa verificacao so' de distribuicao. }
    Obrigatoria: Boolean;
    Presente: Boolean;
    Detalhe: string;   // o que foi achado (versao, caminho) ou o que faltou
    Correcao: string;  // como resolver; vazio quando presente
  end;

  TDFeRelatorioAmbiente = record
    Itens: array of TDFeDependenciaAmbiente;
  end;

procedure AdicionarDependencia(var ARelatorio: TDFeRelatorioAmbiente;
  const ANome: string; const AObrigatoria, APresente: Boolean;
  const ADetalhe, ACorrecao: string);

{ True quando NENHUMA dependencia obrigatoria esta ausente. Opcional ausente
  nao reprova. }
function AmbienteCompleto(const ARelatorio: TDFeRelatorioAmbiente): Boolean;

function QuantidadeObrigatoriasAusentes(const ARelatorio: TDFeRelatorioAmbiente): Integer;

{ Relatorio legivel, uma linha por dependencia (mais "como corrigir" nas que
  faltam):
    [OK]       OpenSSL -- OpenSSL 3.5.4 ...
    [FALTA]    libxml2 -- nao carregou
               -> Copie libxml2.dll ...
    [opcional] libxml2 -- ...   (ausente, mas nao obrigatoria neste uso) }
function FormatarRelatorio(const ARelatorio: TDFeRelatorioAmbiente): string;

{ Mensagem curta para excecao (EDFeAmbienteIndisponivel): so' o que falta E e'
  obrigatorio, com o detalhe e a correcao; vazia se o ambiente esta completo. }
function MensagemAmbienteIncompleto(const ARelatorio: TDFeRelatorioAmbiente): string;

implementation

procedure AdicionarDependencia(var ARelatorio: TDFeRelatorioAmbiente;
  const ANome: string; const AObrigatoria, APresente: Boolean;
  const ADetalhe, ACorrecao: string);
var
  N: Integer;
begin
  N := Length(ARelatorio.Itens);
  SetLength(ARelatorio.Itens, N + 1);
  ARelatorio.Itens[N].Nome := ANome;
  ARelatorio.Itens[N].Obrigatoria := AObrigatoria;
  ARelatorio.Itens[N].Presente := APresente;
  ARelatorio.Itens[N].Detalhe := ADetalhe;
  ARelatorio.Itens[N].Correcao := ACorrecao;
end;

function QuantidadeObrigatoriasAusentes(const ARelatorio: TDFeRelatorioAmbiente): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(ARelatorio.Itens) do
    if ARelatorio.Itens[I].Obrigatoria and not ARelatorio.Itens[I].Presente then
      Inc(Result);
end;

function AmbienteCompleto(const ARelatorio: TDFeRelatorioAmbiente): Boolean;
begin
  Result := QuantidadeObrigatoriasAusentes(ARelatorio) = 0;
end;

function FormatarRelatorio(const ARelatorio: TDFeRelatorioAmbiente): string;
var
  I: Integer;
  LMarca: string;
begin
  Result := '';
  for I := 0 to High(ARelatorio.Itens) do
    with ARelatorio.Itens[I] do
    begin
      if Presente then
        LMarca := '[OK]       '
      else if Obrigatoria then
        LMarca := '[FALTA]    '
      else
        LMarca := '[opcional] ';
      Result := Result + LMarca + Nome + ' -- ' + Detalhe + sLineBreak;
      if (not Presente) and (Correcao <> '') then
        Result := Result + '           -> ' + Correcao + sLineBreak;
    end;
end;

function MensagemAmbienteIncompleto(const ARelatorio: TDFeRelatorioAmbiente): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(ARelatorio.Itens) do
    with ARelatorio.Itens[I] do
      if Obrigatoria and not Presente then
      begin
        if Result <> '' then
          Result := Result + ' | ';
        Result := Result + Nome + ': ' + Detalhe;
        if Correcao <> '' then
          Result := Result + ' (' + Correcao + ')';
      end;
  if Result <> '' then
    Result := 'Ambiente de execucao incompleto -- ' + Result;
end;

end.
