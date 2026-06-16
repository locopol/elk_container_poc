# =============================================================================
# Piloto Elasticsearch - Script de inicio automatizado
# Entorno: Windows PowerShell 5.x compatible
# Version: 1.0.1
# =============================================================================

param(
    [switch]$Clean,
    [switch]$Verbose,
    [string]$EnvFile = ".env.example",
    [string]$TargetEnv = ".env"
)

# Asegurar que el directorio de trabajo sea el del script
Set-Location $PSScriptRoot

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Write-Host ""
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host "  Piloto de Implementacion Elasticsearch 8.19" -ForegroundColor Cyan
Write-Host "  Docker Compose Multi-Nodo con Seguridad y Monitoreo" -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------------
# Funciones auxiliares
# ------------------------------------------------------------------
function Log-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Log-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Log-Error($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Log-Step($msg) { Write-Host "" ; Write-Host "--- $msg ---" -ForegroundColor Cyan }

# ------------------------------------------------------------------
# Verificar dependencias
# ------------------------------------------------------------------
Log-Step "Verificando dependencias"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Log-Error "Docker no se encontro en el PATH. Instala Docker Desktop y reinicia."
    exit 1
}
$dockerVersion = docker --version
Log-Info "Docker version detected: $dockerVersion"

if (-not (Get-Command docker-compose -ErrorAction SilentlyContinue) -and
    -not (docker compose version 2>$null)) {
    Log-Error "Docker Compose no esta disponible. Instala Docker Compose plugin."
    exit 1
}
Log-Info "Docker Compose esta disponible"

# Verificar memoria disponible (minimo 4GB para Docker Desktop)
$dockerMem = docker info --format '{{.MemTotal}}' 2>$null
if ($dockerMem -and [long]$dockerMem -lt 4294967296) {
    Log-Warn "La memoria total de Docker es menor a 4GB. Elasticsearch puede fallar."
    Log-Info "Ajusta la memoria de Docker Desktop a minimo 4GB en Settings > Resources."
}

# ------------------------------------------------------------------
# Verificar vm.max_map_count en WSL2
# ------------------------------------------------------------------
Log-Step "Verificando vm.max_map_count en WSL2"

function Test-WSLMaxMapCount {
    $result = wsl -d docker-desktop -u root sysctl vm.max_map_count 2>&1 | Out-String
    if ($result -match "vm\.max_map_count\s*=\s*(\d+)") {
        $value = [int]$Matches[1]
        return $value
    }
    return 0
}

$vmMaxMap = Test-WSLMaxMapCount
if ($vmMaxMap -eq 0) {
    Log-Warn "No se pudo verificar vm.max_map_count en WSL2."
    Log-Info "Ejecuta: wsl -d docker-desktop -u root && sysctl vm.max_map_count"
} elseif ($vmMaxMap -lt 1048576) {
    Log-Warn "vm.max_map_count esta en $vmMaxMap. Debe ser >= 1048576"
    $fix = Read-Host "Deseas corregir vm.max_map_count en WSL2? [Y/n]"
    if ($fix -ne "n") {
        Log-Info "Corrigiendo vm.max_map_count..."
        wsl -d docker-desktop -u root sh -c "sysctl -w vm.max_map_count=1048576"
        Log-Info "vm.max_map_count actualizado a 1048576"
    }
} else {
    Log-Info "vm.max_map_count = $vmMaxMap (correcto)"
}

# ------------------------------------------------------------------
# Configurar archivo .env
# ------------------------------------------------------------------
Log-Step "Configurando entorno"

if ($Clean) {
    Log-Info "Modo limpio: eliminando contenedores y volenes existentes"
    docker compose down -v --remove-orphans 2>$null
}

if (Test-Path $TargetEnv) {
    Log-Info "Archivo $TargetEnv ya existe. Usando configuracion existente."
} elseif (Test-Path $EnvFile) {
    Log-Info "Copiando $EnvFile como $TargetEnv"
    Copy-Item $EnvFile $TargetEnv -Force
    Log-Info "Edita $TargetEnv para ajustar credenciales y puertos"
} else {
    Log-Error "No se encontro el archivo de entorno. Se requiere $EnvFile o $TargetEnv."
    exit 1
}

# ------------------------------------------------------------------
# Validar rutas de bind mounts (si estan configuradas)
# ------------------------------------------------------------------
Log-Step "Validando rutas de almacenamiento"

# Leer variables de entorno desde .env
$envContent = Get-Content (Join-Path $PSScriptRoot $TargetEnv) -ErrorAction SilentlyContinue

function Get-EnvVar {
    param([string]$Name)
    $line = $envContent | Where-Object { $_ -match "^\s*$Name\s*=" }
    if ($line) {
        return ($line -split '=')[1].Trim()
    }
    return $null
}

$useBindMounts = Get-EnvVar "USE_BIND_MOUNTS"
if ($useBindMounts -and $useBindMounts.ToLower() -eq "true") {
    $dataDirBase = Get-EnvVar "DATA_DIR_BASE"
    $es01Dir = Get-EnvVar "ES01_DATA_DIR"
    $es02Dir = Get-EnvVar "ES02_DATA_DIR"
    $es03Dir = Get-EnvVar "ES03_DATA_DIR"
    $certsDir = Get-EnvVar "CERTS_DIR"
    $kibanaDir = Get-EnvVar "KIBANA_DATA_DIR"

    if ($dataDirBase) {
        # Validar que DATA_DIR_BASE existe (debe ser pre-provisionado)
        if (-not (Test-Path $dataDirBase)) {
            Log-Error "DATA_DIR_BASE no existe: $dataDirBase"
            Log-Error "El directorio base debe ser pre-provisionado antes de ejecutar el script."
            exit 1
        }

        $subDirs = @()
        if ($es01Dir) { $subDirs += $es01Dir }
        if ($es02Dir) { $subDirs += $es02Dir }
        if ($es03Dir) { $subDirs += $es03Dir }
        if ($certsDir) { $subDirs += $certsDir }
        if ($kibanaDir) { $subDirs += $kibanaDir }

        # Crear solo los subdirectorios (el base ya debe existir)
        foreach ($subDir in $subDirs) {
            $fullPath = Join-Path $dataDirBase $subDir
            if (-not (Test-Path $fullPath)) {
                Log-Info "Creando subdirectorio de bind mount: $fullPath"
                New-Item -ItemType Directory -Force -Path $fullPath | Out-Null
            }
        }

        Log-Info "Rutas de bind mounts configuradas:"
        foreach ($subDir in $subDirs) {
            $fullPath = Join-Path $dataDirBase $subDir
            Write-Host "   - $fullPath" -ForegroundColor Gray
        }
    } else {
        Log-Warn "DATA_DIR_BASE no definido. Usando volumes Docker por defecto."
    }
} else {
    Log-Info "USE_BIND_MOUNTS no activo. Usando volumes Docker por defecto."
}

# ------------------------------------------------------------------
# Levantar el cluster
# ------------------------------------------------------------------
Log-Step "Levantando cluster Elasticsearch"

Log-Info "Descargando imagenes Docker si es necesario..."
docker compose pull --quiet

Log-Info "Iniciando contenedores (sin --wait, la validacion se hace despues)..."
docker compose up -d

if ($LASTEXITCODE -ne 0) {
    Log-Error "Fallo al levantar los contenedores. Revisa los logs con:"
    Log-Error "  docker compose logs setup"
    Log-Error "  docker compose logs es01"
    exit 1
}

# Verificar que los contenedores estan en estado healthy despues de un tiempo
Log-Info "Verificando estado de contenedores..."
$maxHealthChecks = 36   # 36 intentos * 5s = 180s maximo
$healthAttempt = 0
while ($healthAttempt -lt $maxHealthChecks) {
    $healthAttempt++
    Start-Sleep -Seconds 5

    # Obtener estado de contenedores relevantes
    $composeOutput = docker compose ps --format json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue

    if ($null -eq $composeOutput) {
        Write-Host "." -NoNewline -ForegroundColor DarkGray
        continue
    }

    $unhealthy = @()
    foreach ($svc in $composeOutput) {
        $status = ($svc.Status -split ',')[0] -replace '^\s*|\s*$',''
        if ($status -notmatch 'healthy|running') {
            $unhealthy += $svc.Service
        }
    }

    if ($unhealthy.Count -eq 0) {
        Log-Info "Todos los contenedores estan activos. Verificar cluster..."
        break
    }

    if ($healthAttempt -eq $maxHealthChecks) {
        Log-Warn "Algunos contenedores tardaron en iniciarse: $($unhealthy -join ', ')"
    }
}
Write-Host ""

# ------------------------------------------------------------------
# Funcion auxiliar para hacer peticiones HTTP/S desde PowerShell 5.x
# (Invoke-RestMethod no funciona bien con SSL auto-firmado en PS 5.x)
# ------------------------------------------------------------------
function Invoke-ESRequest {
    param(
        [string]$Uri,
        [string]$Username = $null,
        [string]$Password = $null,
        [int]$TimeoutSec = 30
    )

    # Configurar SSL una sola vez (callback global)
    if (-not $script:SSLConfigured) {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        $script:SSLConfigured = $true
    }

    $webClient = New-Object System.Net.WebClient
    $webClient.UseDefaultCredentials = $false
    # Nota: WebClient en .NET Framework usa un timeout por defecto de 100s
    # La propiedad .Timeout solo existe en .NET Core/5+, no en .NET Framework

    if ($Username -and $Password) {
        $pair = "$($Username):$($Password)"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
        $webClient.Headers["Authorization"] = "Basic $encoded"
    }
    $webClient.Headers["User-Agent"] = "PilotoElastic"

    try {
        $data = $webClient.DownloadString($Uri)
        return $data
    } catch [System.Net.WebException] {
        # Si es un error HTTP (4xx, 5xx), devolver la respuesta de todos modos
        # porque significa que ES esta respondiendo (aunque sea con auth required)
        if ($null -ne $_.Exception.Response) {
            $responseStream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($responseStream)
            $body = $reader.ReadToEnd()
            $reader.Close()
            $responseStream.Close()
            return $body
        }
        # Si no es un error HTTP, rethrow
        throw $_
    } finally {
        $webClient.Dispose()
    }
}

# ------------------------------------------------------------------
# Esperar a que Elasticsearch este listo
# ------------------------------------------------------------------
Log-Step "Esperando que Elasticsearch este disponible"

$maxAttempts = 60   # 60 intentos * 5s = 300s maximo
$attempt = 0
$elasticCred = $env:ELASTIC_PASSWORD

if (Test-Path $TargetEnv) {
    $envContent = Get-Content $TargetEnv
    $elasticCredLine = $envContent | Where-Object { $_ -match '^ELASTIC_PASSWORD=' }
    if ($elasticCredLine) {
        $elasticCred = ($elasticCredLine -split '=')[1]
    }
}

$esPort = "9200"
if (Test-Path $TargetEnv) {
    $envContent = Get-Content $TargetEnv
    $portLine = $envContent | Where-Object { $_ -match '^ES_PORT=' }
    if ($portLine) {
        $esPort = ($portLine -split '=')[1] -replace '.*:',''
    }
}

while ($attempt -lt $maxAttempts) {
    $attempt++
    try {
        # Usar WebClient directamente (funciona con SSL en PS 5.x)
        $response = Invoke-ESRequest -Uri "https://localhost:$esPort"

        # Si llega aqui, la conexion fue exitosa (responda con algo, aunque sea error)
        Log-Info "Elasticsearch esta activo. Intento $attempt/$maxAttempts"
        break
    } catch {
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 5
    }

    if ($attempt -eq $maxAttempts) {
        Log-Error "Elasticsearch no se levanto despues de $maxAttempts intentos."
        Log-Error "Revisa los logs: docker compose logs es01"
        exit 1
    }
}
Write-Host ""

# ------------------------------------------------------------------
# Validar el cluster
# ------------------------------------------------------------------
Log-Step "Validando cluster Elasticsearch"

try {
    $nodesData = Invoke-ESRequest -Uri "https://localhost:$esPort/_cat/nodes?format=json" `
        -Username "elastic" -Password "$elasticCred"

    $nodesResponse = $nodesData | ConvertFrom-Json
    $nodeCount = $nodesResponse.Count
    Log-Info "Cluster activo con $nodeCount nodo(s)"

    foreach ($node in $nodesResponse) {
        # ES 8.x usa node.role como string de letras (ej: "cdfhilmrstw")
        # Cada letra representa un rol: c=cluster_manager, d=data, h=hot, i=warm, etc.
        # Tambien verifica el campo master para el rol de master
        $roles = @()

        if ($node.master -eq "*" -or $node.master -eq "true") {
            $roles += "master"
        }

        if ($null -ne $node."node.role") {
            $roleStr = $node."node.role"
            $roleMap = @{
                "c" = "cluster_manager"
                "d" = "data"
                "f" = "data_content"
                "h" = "data_hot"
                "i" = "data_warm"
                "l" = "data_cold"
                "m" = "remote_storage"
                "r" = "data_read"
                "s" = "search"
                "t" = "transform"
                "w" = "ml"
            }
            $parsedRoles = @()
            foreach ($char in $roleStr.ToCharArray()) {
                $roleName = $null
                if ($roleMap.ContainsKey($char)) { $roleName = $roleMap[$char] }
                else { $roleName = $char }

                # Evitar duplicados
                if ($parsedRoles -notcontains $roleName) {
                    $parsedRoles += $roleName
                }
            }
            $roles += $parsedRoles
        }

        $roleStr = if ($roles.Count -gt 0) { $roles -join ", " } else { "unknown" }
        Write-Host "  - Node: $($node.name) | Role: $roleStr" -ForegroundColor Green
    }

    $clusterData = Invoke-ESRequest -Uri "https://localhost:$esPort/_cluster/health" `
        -Username "elastic" -Password "$elasticCred"

    $clusterHealth = $clusterData | ConvertFrom-Json

    Log-Info "Estado del cluster: $($clusterHealth.status)"
    Log-Info "Nodos activos: $($clusterHealth.number_of_nodes)"

} catch {
    Log-Warn "No se pudo validar el cluster completamente. Revisa los logs."
}

# ------------------------------------------------------------------
# Mostrar informacion de acceso
# ------------------------------------------------------------------
Log-Step "Informacion de acceso"

$kibanaPort = "5601"
if (Test-Path $TargetEnv) {
    $envContent = Get-Content $TargetEnv
    $kbnLine = $envContent | Where-Object { $_ -match '^KIBANA_PORT=' }
    if ($kbnLine) {
        $kibanaPort = ($kbnLine -split '=')[1]
    }
}

Write-Host ""
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host "  Piloto Elasticsearch 8.19 listo" -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Elasticsearch API: https://localhost:$esPort" -ForegroundColor White
Write-Host "  Kibana UI:         http://localhost:$kibanaPort" -ForegroundColor White
Write-Host ""
Write-Host "  Usuario:     elastic" -ForegroundColor Yellow
Write-Host "  Password:    $elasticCred" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Credenciales disponibles en: .env" -ForegroundColor Gray
Write-Host ""
Log-Info "Para detener el cluster: docker compose down"
Log-Info "Para logs en tiempo real:  docker compose logs -f"
Log-Info "Para reiniciar con datos:  docker compose restart"
Log-Info "Para limpiar todo:         docker compose down -v"
Write-Host ""
