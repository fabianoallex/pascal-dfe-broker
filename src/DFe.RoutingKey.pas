unit DFe.RoutingKey;

{$I dfe.inc}

{ Implementa a convencao de routing-key fixada em docs/architecture.md,
  secao "Convencao de exchange / routing-key":

    <tipo>.<categoria>.<uf>.<cnpj>

  Isolada numa unit propria e pura (sem I/O, sem broker) de proposito: e' a
  interface publica mais importante do projeto, e o formato so pode mudar
  numa decisao deliberada, nunca como efeito colateral de uma mudanca em
  outro lugar -- concentrar a logica aqui torna essa mudanca (quando for
  necessaria) um diff de um lugar so, e testavel isoladamente. }

interface

uses
  SysUtils,
  DFe.Types;

function MontarRoutingKey(const AEvento: TDFeEventoNormalizado): string;

implementation

function MontarRoutingKey(const AEvento: TDFeEventoNormalizado): string;
var
  LCategoria: string;
begin
  case AEvento.Categoria of
    dcDocumento:
      LCategoria := 'documento';
    dcEvento:
      begin
        if AEvento.TipoEvento = '' then
          raise Exception.Create('TDFeEventoNormalizado.TipoEvento nao pode ser vazio quando Categoria = dcEvento');
        LCategoria := 'evento.' + LowerCase(AEvento.TipoEvento);
      end;
  else
    raise Exception.Create('TDFeEventoNormalizado.Categoria desconhecida');
  end;

  Result := Format('%s.%s.%s.%s', [
    LowerCase(AEvento.TipoDocumento),
    LCategoria,
    LowerCase(AEvento.UF),
    AEvento.CnpjCpfConsultante]);
end;

end.
