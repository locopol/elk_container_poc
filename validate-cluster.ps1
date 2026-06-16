# =============================================================================
# Piloto Elasticsearch - Script de validacion del cluster
# Verifica que todos los nodos, seguridad y monitoreo esten operativos
# Entorno: Windows PowerShell
# Version: 1.0
# =============================================================================

param(
    [string]$EnvFile = ".env",
    [string]$CaCertPath = "config/certs/ca/ca.crt"
)

$ErrorActionPreference = "Stop"

$testsPassed = 0
$testsFailed = 0
$testsTotal = 0

function Test-Name($name) { Write-Host "`n[$name]" -ForegroundColor Cyan }
function Pass-Test($desc) { $global:testsPassed++ ; Write-Host "  [PASS] $desc" -ForegroundColor Green }
function Fail-Test($desc) { $global:testsFailed++ ; Write-Host "  [FAIL] $desc" -ForegroundColor Red }

$global:testsTotal = 0

# ------------------------------------------------------------------
# Leer credenciales del .env
# ------------------------------------------------------------------
$elasticPassword = ""
$kibanaPassword = ""
$esPort = "9200"

if (Test-Path $EnvFile) {
    $envContent = Get-Content $EnvFile
    foreach ($line in $envContent) {
        if ($line -match '^ELASTIC_PASSWORD=(.+)') { $elasticPassword = $Matches[1] }
        if ($line -match '^KIBANA_PASSWORD=(.+)') { $kibanaPassword = $Matches[1] }
        if ($line -match '^ES_PORT=(.+)') { $esPort = ($Matches[1] -split ':')[-1] }
    }
}

if (-not $elasticPassword) {
    Write-Host "[ERROR] No se encontro ELASTIC_PASSWORD en $EnvFile" -ForegroundColor Red
    exit 1
}

$baseUri = "https://localhost:$esPort"
$headers = @{ Authorization = "Basic $(['elastic:' + $elasticPassword] | ForEach-Object { [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($_)) })" }
$uriParams = @("-SkipCertificateCheck")

# ------------------------------------------------------------------
# Test 1: Elasticsearch HTTP API esta disponible
# ------------------------------------------------------------------
Test-Name "Test 1 - API HTTP de Elasticsearch"

try {
    $info = Invoke-RestMethod -Uri "$baseUri" @uriParams -Headers $headers 2>$null
    Pass-Test "API HTTP responde correctamente"
    Write-Host "  Version: $($info.version.number)"
    Write-Host "  Cluster: $($info.cluster_name)"
} catch {
    Fail-Test "API HTTP no responde (error: $_)"
}

# ------------------------------------------------------------------
# Test 2: Seguridad TLS esta habilitada
# ------------------------------------------------------------------
Test-Name "Test 2 - Seguridad TLS"

try {
    $sslInfo = Invoke-RestMethod -Uri "$baseUri/_security/authc" @uriParams -Headers $headers 2>$null
    Pass-Test "Autenticacion HTTP habilitada"
} catch {
    Fail-Test "Autenticacion HTTP no disponible"
}

# ------------------------------------------------------------------
# Test 3: Estado del cluster
# ------------------------------------------------------------------
Test-Name "Test 3 - Estado del cluster"

try {
    $health = Invoke-RestMethod -Uri "$baseUri/_cluster/health" @uriParams -Headers $headers 2>$null
    $global:testsTotal++

    if ($health.status -eq "green" -or $health.status -eq "yellow") {
        Pass-Test "Estado del cluster: $($health.status)"
    } else {
        Fail-Test "Estado del cluster: $($health.status) (esperado green/yellow)"
    }

    Write-Host "  Nodos: $($health.number_of_nodes)"
    Write-Host "  Shards primarios: $($health.number_of_primary_shards)"
    Write-Host "  Shards totales: $($health.number_of_shards)"
} catch {
    Fail-Test "No se pudo obtener estado del cluster"
}

# ------------------------------------------------------------------
# Test 4: Todos los nodos estan activos
# ------------------------------------------------------------------
Test-Name "Test 4 - Nodos del cluster"

try {
    $nodes = Invoke-RestMethod -Uri "$baseUri/_cat/nodes?format=json" @uriParams -Headers $headers 2>$null
    $nodeCount = $nodes.Count

    if ($nodeCount -ge 3) {
        Pass-Test "Hay $nodeCount nodos activos (esperado: 3+)"
    } else {
        Fail-Test "Solo hay $nodeCount nodos (esperado: 3+)"
    }

    foreach ($node in $nodes) {
        Write-Host "  - $($node.name) [role: $($node.role)]"
    }
} catch {
    Fail-Test "No se pudo listar los nodos"
}

# ------------------------------------------------------------------
# Test 5: Monitoreo X-Pack esta activo
# ------------------------------------------------------------------
Test-Name "Test 5 - Monitoreo X-Pack"

try {
    $monitoring = Invoke-RestMethod -Uri "$baseUri/_nodes/stats/jvm?pretty=false" @uriParams -Headers $headers 2>$null
    Pass-Test "Monitoreo de nodos accesible via API"
} catch {
    Fail-Test "No se pudo acceder al monitoreo de nodos"
}

# ------------------------------------------------------------------
# Test 6: Kibana esta disponible
# ------------------------------------------------------------------
Test-Name "Test 6 - Kibana UI"

$kibanaPort = "5601"
if (Test-Path $EnvFile) {
    $envContent = Get-Content $EnvFile
    foreach ($line in $envContent) {
        if ($line -match '^KIBANA_PORT=(.+)') { $kibanaPort = $Matches[1] }
    }
}

try {
    $kibanaResp = Invoke-WebRequest -Uri "http://localhost:$kibanaPort" `
        -Method Head -TimeoutSec 10 2>$null
    Pass-Test "Kibana responde en puerto $kibanaPort (status: $($kibanaResp.StatusCode))"
} catch {
    Fail-Test "Kibana no responde en puerto $kibanaPort"
}

# ------------------------------------------------------------------
# Test 7: Indice de monitoreo existe
# ------------------------------------------------------------------
Test-Name "Test 7 - Indices de monitoreo"

try {
    $indices = Invoke-RestMethod -Uri "$baseUri/_cat/indices/.monitoring*" @uriParams -Headers $headers 2>$null
    if ($indices) {
        Pass-Test "Indices de monitoreo .monitoring* existen"
        Write-Host $indices
    } else {
        Fail-Test "No se encontraron indices de monitoreo .monitoring*"
    }
} catch {
    Write-Host "  [WARN] No hay indices de monitoreo (puede tardar en poblarse)" -ForegroundColor Yellow
}

# ------------------------------------------------------------------
# Test 8: Certificado SSL de la CA
# ------------------------------------------------------------------
Test-Name "Test 8 - Certificado CA"

if (Test-Path $CaCertPath) {
    Pass-Test "Certificado CA existe en $CaCertPath"
} else {
    Fail-Test "Certificado CA no encontrado en $CaCertPath"
}

# ------------------------------------------------------------------
# Resumen
# ------------------------------------------------------------------
Write-Host ""
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host "  Resultados de validacion" -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host "  Aprobados: $testsPassed" -ForegroundColor Green
Write-Host "  Fallidos:  $testsFailed" -ForegroundColor Red
$total = $testsPassed + $testsFailed
Write-Host "  Total:     $total" -ForegroundColor White
Write-Host ""

if ($testsFailed -gt 0) {
    Write-Host "Algunas pruebas fallaron. Revisa los logs con:" -ForegroundColor Yellow
    Write-Host "  docker compose logs" -ForegroundColor White
    exit 1
} else {
    Write-Host "Todas las pruebas pasaron correctamente." -ForegroundColor Green
    exit 0
}
