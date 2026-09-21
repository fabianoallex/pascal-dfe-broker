object frmConsumidor: TfrmConsumidor
  Left = 0
  Top = 0
  Caption = 'Consumidor DFe (pascal-dfe-broker)'
  Color = clBtnFace
  ClientHeight = 620
  ClientWidth = 1000
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnClose = FormClose
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnShow = FormShow
  TextHeight = 15
  object pnlTopo: TPanel
    Left = 0
    Top = 0
    Width = 1000
    Height = 126
    Align = alTop
    BevelOuter = bvNone
    Caption = ''
    TabOrder = 0
    object gbConexao: TGroupBox
      Left = 8
      Top = 2
      Width = 480
      Height = 120
      Caption = ' Conexao '
      TabOrder = 0
      object lblHost: TLabel
        Left = 12
        Top = 22
        Width = 30
        Height = 15
        Caption = 'Host:'
      end
      object edtHost: TEdit
        Left = 60
        Top = 18
        Width = 150
        Height = 23
        TabOrder = 0
        Text = '127.0.0.1'
      end
      object lblPorta: TLabel
        Left = 226
        Top = 22
        Width = 34
        Height = 15
        Caption = 'Porta:'
      end
      object edtPorta: TEdit
        Left = 268
        Top = 18
        Width = 60
        Height = 23
        TabOrder = 1
        Text = '5672'
      end
      object lblVHost: TLabel
        Left = 12
        Top = 48
        Width = 40
        Height = 15
        Caption = 'VHost:'
      end
      object edtVHost: TEdit
        Left = 60
        Top = 44
        Width = 50
        Height = 23
        TabOrder = 2
        Text = '/'
      end
      object lblUsuario: TLabel
        Left = 128
        Top = 48
        Width = 45
        Height = 15
        Caption = 'Usuario:'
      end
      object edtUsuario: TEdit
        Left = 180
        Top = 44
        Width = 100
        Height = 23
        TabOrder = 3
        Text = 'guest'
      end
      object lblSenha: TLabel
        Left = 294
        Top = 48
        Width = 38
        Height = 15
        Caption = 'Senha:'
      end
      object edtSenha: TEdit
        Left = 338
        Top = 44
        Width = 120
        Height = 23
        PasswordChar = '*'
        TabOrder = 4
        Text = 'guest'
      end
      object btnConectar: TButton
        Left = 12
        Top = 74
        Width = 110
        Height = 26
        Caption = 'Conectar'
        TabOrder = 5
        OnClick = btnConectarClick
      end
      object lblStatus: TLabel
        Left = 136
        Top = 79
        Width = 60
        Height = 15
        Caption = 'Desconectado'
        Font.Style = [fsBold]
      end
    end
    object gbOrigem: TGroupBox
      Left = 496
      Top = 2
      Width = 496
      Height = 120
      Anchors = [akTop, akLeft, akRight]
      Caption = ' O que consumir '
      TabOrder = 1
      object rbPropria: TRadioButton
        Left = 12
        Top = 20
        Width = 190
        Height = 19
        Caption = 'Fila propria, padrao:'
        Checked = True
        TabOrder = 0
        TabStop = True
        OnClick = rbOrigemClick
      end
      object edtPadrao: TEdit
        Left = 206
        Top = 18
        Width = 160
        Height = 23
        TabOrder = 1
        Text = 'nfe.#'
      end
      object rbNomeada: TRadioButton
        Left = 12
        Top = 46
        Width = 190
        Height = 19
        Caption = 'Fila nomeada (duravel):'
        TabOrder = 2
        OnClick = rbOrigemClick
      end
      object edtFila: TEdit
        Left = 206
        Top = 44
        Width = 160
        Height = 23
        TabOrder = 3
        Text = 'documentos'
      end
      object chkSalvar: TCheckBox
        Left = 12
        Top = 74
        Width = 190
        Height = 19
        Caption = 'Salvar XML na pasta:'
        TabOrder = 4
      end
      object edtPasta: TEdit
        Left = 206
        Top = 70
        Width = 278
        Height = 23
        Anchors = [akTop, akLeft, akRight]
        TabOrder = 5
        Text = 'xml-recebidos'
      end
      object btnConsumir: TButton
        Left = 376
        Top = 16
        Width = 108
        Height = 50
        Anchors = [akTop, akRight]
        Caption = 'Iniciar consumo'
        TabOrder = 6
        OnClick = btnConsumirClick
      end
    end
  end
  object pnlContadores: TPanel
    Left = 0
    Top = 126
    Width = 1000
    Height = 28
    Align = alTop
    BevelOuter = bvNone
    Caption = ''
    TabOrder = 1
    object lblContadores: TLabel
      Left = 8
      Top = 7
      Width = 400
      Height = 15
      Caption = 'Recebidas: 0'
    end
    object btnLimparLista: TButton
      Left = 862
      Top = 1
      Width = 130
      Height = 26
      Anchors = [akTop, akRight]
      Caption = 'Limpar lista'
      TabOrder = 0
      OnClick = btnLimparListaClick
    end
  end
  object lvDocs: TListView
    Left = 0
    Top = 154
    Width = 1000
    Height = 180
    Align = alTop
    GridLines = True
    HideSelection = False
    ReadOnly = True
    RowSelect = True
    TabOrder = 2
    ViewStyle = vsReport
    OnSelectItem = lvDocsSelectItem
    Columns = <
      item
        Caption = 'Hora'
        Width = 62
      end
      item
        Caption = 'Situacao'
        Width = 100
      end
      item
        Caption = 'Routing key'
        Width = 270
      end
      item
        Caption = 'XML'
        Width = 90
      end
      item
        Caption = 'Chave de acesso'
        Width = 300
      end
      item
        Caption = 'Detalhe'
        Width = 400
      end>
  end
  object pnlBaixo: TPanel
    Left = 0
    Top = 450
    Width = 1000
    Height = 170
    Align = alBottom
    BevelOuter = bvNone
    Caption = ''
    TabOrder = 3
    object gbManifestacao: TGroupBox
      Left = 0
      Top = 0
      Width = 430
      Height = 170
      Align = alLeft
      Caption = ' Manifestacao do destinatario '
      TabOrder = 0
      object lblAlias: TLabel
        Left = 12
        Top = 20
        Width = 30
        Height = 15
        Caption = 'Alias:'
      end
      object edtAlias: TEdit
        Left = 96
        Top = 16
        Width = 130
        Height = 23
        TabOrder = 0
        Text = 'matriz'
      end
      object lblChave: TLabel
        Left = 12
        Top = 44
        Width = 70
        Height = 15
        Caption = 'Chave (44):'
      end
      object edtChave: TEdit
        Left = 96
        Top = 40
        Width = 320
        Height = 23
        MaxLength = 44
        TabOrder = 1
        Text = ''
      end
      object lblTipo: TLabel
        Left = 12
        Top = 68
        Width = 30
        Height = 15
        Caption = 'Tipo:'
      end
      object cboTipo: TComboBox
        Left = 96
        Top = 64
        Width = 200
        Height = 23
        Style = csDropDownList
        TabOrder = 2
      end
      object lblJustificativa: TLabel
        Left = 12
        Top = 92
        Width = 80
        Height = 15
        Caption = 'Justificativa:'
      end
      object edtJustificativa: TEdit
        Left = 96
        Top = 88
        Width = 320
        Height = 23
        TabOrder = 3
        Text = ''
      end
      object btnManifestar: TButton
        Left = 96
        Top = 118
        Width = 200
        Height = 26
        Caption = 'Enviar comando'
        TabOrder = 4
        OnClick = btnManifestarClick
      end
    end
    object mmoLog: TMemo
      Left = 430
      Top = 0
      Width = 570
      Height = 170
      Align = alClient
      ReadOnly = True
      ScrollBars = ssVertical
      TabOrder = 1
    end
  end
  object mmoXml: TMemo
    Left = 0
    Top = 334
    Width = 1000
    Height = 116
    Align = alClient
    Font.Height = -12
    Font.Name = 'Courier New'
    ReadOnly = True
    ScrollBars = ssBoth
    TabOrder = 4
    WordWrap = False
  end
end
