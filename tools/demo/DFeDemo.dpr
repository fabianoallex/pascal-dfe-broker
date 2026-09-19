program DFeDemo;

{ DEMO sem certificado: sobe o broker AMQP EMBUTIDO e publica NFes e eventos
  SINTETICOS nele, pelo mesmo caminho da producao (provider NFe -> routing-key ->
  publicador AMQP). So' o "client da SEFAZ" e' o simulador dos testes. Serve para
  ver os documentos chegando a um consumidor (exemplos/consumidor) sem CNPJ nem
  certificado.

    DFeDemo [--porta 5672] [--intervalo 5] [--usuario guest] [--senha guest]

  Cria as filas 'documentos' (nfe.documento.#) e 'eventos' (nfe.evento.#) e, a cada
  --intervalo segundos, publica uma NFe (e, a cada 3a, um evento de cancelamento) da
  empresa demo (CNPJ 12345678000199, UF SP). Ctrl+C / SIGTERM encerra.

  NAO e' o host de producao (esse e' hosts/console). O XML e' sintetico: chave com
  digito verificador correto, mas nenhuma nota real. Mesmo fonte para FPC e Delphi
  (so' ha' .lpi por enquanto). }

{$IFDEF FPC}
{$MODE DELPHI}{$H+}
{$ENDIF}
{$APPTYPE CONSOLE}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils,
  AMQP.Connection,
  AMQP.Server.Auth,
  AMQP.Server.Broker,
  DFe.Types,
  DFe.Provider,
  DFe.Provider.NFe,
  DFe.Publicador,
  DFe.Publicador.AMQP,
  DFe.RoutingKey,
  DFe.Simulador,
  DFe.Simulador.Client,
  DFe.Simulador.Fixtures,
  DFe.Host.Sinais;

const
  CNPJ_DEMO = '12345678000199';
  UF_DEMO = 'SP';

type
  TParada = class
  public
    Pedida: Boolean;
    procedure Parar;
  end;

procedure TParada.Parar;
begin
  Pedida := True;
end;

var
  GPorta: Integer = 5672;
  GIntervalo: Integer = 5;
  GUsuario: string = 'guest';
  GSenha: string = 'guest';

procedure LerArgumentos;
var
  I: Integer;
begin
  I := 1;
  while I <= ParamCount do
  begin
    if (ParamStr(I) = '--porta') and (I < ParamCount) then
    begin
      Inc(I);
      GPorta := StrToIntDef(ParamStr(I), GPorta);
    end
    else if (ParamStr(I) = '--intervalo') and (I < ParamCount) then
    begin
      Inc(I);
      GIntervalo := StrToIntDef(ParamStr(I), GIntervalo);
    end
    else if (ParamStr(I) = '--usuario') and (I < ParamCount) then
    begin
      Inc(I);
      GUsuario := ParamStr(I);
    end
    else if (ParamStr(I) = '--senha') and (I < ParamCount) then
    begin
      Inc(I);
      GSenha := ParamStr(I);
    end
    else
    begin
      WriteLn('uso: DFeDemo [--porta 5672] [--intervalo 5] [--usuario guest] [--senha guest]');
      Halt(1);
    end;
    Inc(I);
  end;
end;

{ Um "ciclo de consulta" simulado: a SEFAZ (simulada) entrega os documentos novos e
  o provider NFe os normaliza, exatamente como no orquestrador. }
procedure PublicarUmCiclo(const APublicador: IDFePublicador; const ANumero: Integer);
var
  LSim: TDFeSimuladorSefaz;
  LClient: IDFeDistribuicaoClient;
  LProvider: IDFeProvider;
  LCert: TDFeCertificado;
  LLote: TDFeLoteBruto;
  LEventos: TDFeEventoNormalizadoArray;
  LChave: string;
  I: Integer;
begin
  LCert.Identificador := 'demo';
  LCert.CnpjCpf := CNPJ_DEMO;
  LCert.UF := UF_DEMO;

  LSim := TDFeSimuladorSefaz.Create; // "conta" nova a cada ciclo: sem a janela de 1 h da SEFAZ
  try
    LChave := ChaveNFeSintetica(DFE_SIM_CNPJ_EMITENTE, ANumero);
    LSim.PublicarDocumento(CNPJ_DEMO, UF_DEMO, DFE_SIM_SCHEMA_RESNFE, XmlResNFe(LChave));
    if ANumero mod 3 = 0 then
      LSim.PublicarDocumento(CNPJ_DEMO, UF_DEMO, DFE_SIM_SCHEMA_RESEVENTO, XmlResEvento(LChave, '110111'));

    LClient := TDFeSimuladorClient.Create(LSim);
    LLote := LClient.Consultar(LCert, 0);
    LProvider := TDFeProviderRegistry.ObterPorIdentificador('nfe');
    LEventos := LProvider.Decodificar(LLote, LCert);
    for I := 0 to High(LEventos) do
    begin
      APublicador.Publicar(MontarRoutingKey(LEventos[I]), LEventos[I].XmlPayload);
      WriteLn(FormatDateTime('hh:nn:ss', Now), '  publicado  ', MontarRoutingKey(LEventos[I]),
        '  chave=', LEventos[I].ChaveAcesso);
    end;
    LClient := nil; // solta o client antes do simulador (ver TDFeSimuladorClient)
  finally
    LSim.Free;
  end;
end;

var
  GBroker: TAMQPServer;
  GParada: TParada;
  GParams: TAMQPConnectionParams;
  GConexao: TAMQPConnection;
  GCanal: TAMQPChannel;
  GPublicador: IDFePublicador;
  GNumero, GEspera: Integer;
begin
  {$IFDEF FPC}
  SetMultiByteConversionCodePage(CP_UTF8);
  {$ENDIF}
  LerArgumentos;

  GParada := TParada.Create;
  GBroker := TAMQPServer.Create;
  try
    GBroker.BindAddress := '127.0.0.1';
    GBroker.Port := Word(GPorta);
    GBroker.Authenticator := TAMQPStaticAuthenticator.Create([GUsuario, GSenha]);
    GBroker.Start;

    GParams := TAMQPConnectionParams.Localhost;
    GParams.Host := '127.0.0.1';
    GParams.Port := GBroker.Port;
    GParams.User := GUsuario;
    GParams.Password := GSenha;

    // as filas que o consumidor de exemplo le (sem elas o broker descartaria o publicado)
    GConexao := TAMQPConnection.Create(GParams);
    try
      GConexao.Open;
      GCanal := GConexao.CreateChannel;
      DeclararExchangeDfe(GCanal);
      DeclararFilaLigada(GCanal, 'documentos', ['nfe.documento.#']);
      DeclararFilaLigada(GCanal, 'eventos', ['nfe.evento.#']);
    finally
      GConexao.Free;
    end;

    GPublicador := TDFePublicadorAMQP.Create(GParams);
    InstalarTratadorDeParada(GParada.Parar);

    WriteLn('DFeDemo: broker em 127.0.0.1:', GBroker.Port, '  (usuario "', GUsuario, '")');
    WriteLn('filas: documentos (nfe.documento.#), eventos (nfe.evento.#); exchange "dfe" (topic)');
    WriteLn('publicando uma NFe a cada ', GIntervalo, ' s. Ctrl+C para parar.');
    WriteLn;

    GNumero := 0;
    while not GParada.Pedida do
    begin
      Inc(GNumero);
      PublicarUmCiclo(GPublicador, GNumero);
      GEspera := 0;
      while (GEspera < GIntervalo * 10) and not GParada.Pedida do
      begin
        Sleep(100);
        Inc(GEspera);
      end;
    end;
    WriteLn('Encerrando.');
  finally
    GPublicador := nil;
    GBroker.Stop;
    GBroker.Free;
    GParada.Free;
  end;
end.
