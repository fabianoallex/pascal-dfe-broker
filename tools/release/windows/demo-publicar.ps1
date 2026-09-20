# Publica documentos no DFeSimulador e avanca o relogio virtual em 1h01, para o
# broker (que ja' foi bloqueado 1 h pela primeira consulta) receber tudo agora.
# Uso:  .\demo-publicar.ps1            (padrao: simulador em 127.0.0.1:9200)
param([string]$Simulador = "http://127.0.0.1:9200")

function Post($rota, $json) {
    Invoke-RestMethod -Method Post -Uri "$Simulador$rota" -ContentType "application/json" -Body $json
}

Write-Host "Publicando 2 resNFe e 1 cancelamento no simulador..."
Post "/admin/documentos" '{"cnpj":"11222333000181","uf":"RS","tipo":"resNFe","quantidade":2}' | Out-String | Write-Host
Post "/admin/documentos" '{"cnpj":"11222333000181","uf":"RS","tipo":"resEvento","tpEvento":"110111"}' | Out-String | Write-Host
Write-Host "Avancando o relogio virtual em 1h01 (o bloqueio de 1 h do simulador acaba)..."
Post "/admin/relogio/avancar" '{"horas":1,"minutos":1}' | Out-String | Write-Host
Write-Host "Em alguns segundos os documentos aparecem no consumidor."
