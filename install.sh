#!/bin/bash
# ============================================================================= # Piloto Elasticsearch - Script de instalacion automatizado # Entorno: Linux (bash) # Version: 1.0 # =============================================================================

set -e

# ------------------------------------------------------- # Argumentos de linea de comandos # -------------------------------------------------------
CLEAN=false
VERBOSE=false
ENV_FILE=".env.example"
TARGET_ENV=".env"

# Parsear argumentos
while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean|-c) CLEAN=true; shift ;;
        --verbose|-v) VERBOSE=true; shift ;;
        --env-file=*) ENV_FILE="${1#*=}"; shift ;;
        --target-env=*) TARGET_ENV="${1#*=}"; shift ;;
        *) echo "Uso: $0 [--clean|--verbose] [--env-file <archivo>] [--target-env <archivo>]"
           exit 1 ;;
    esac
done

# Asegurar que el directorio de trabajo sea el del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ------------------------------------------------------- # Colores y log # -------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC} $1" ; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1" ; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" ; exit 1 ; }
log_step()  { echo -e "\n${CYAN}--- $1 ---${NC}" ; }

# ------------------------------------------------------- # Verificar dependencias # -------------------------------------------------------
log_step "Verificando dependencias"

# Verificar docker
if ! command -v docker &> /dev/null; then
    log_error "Docker no se encontro en el PATH. Instala Docker y reinicia."
fi
DOCKER_VERSION=$(docker --version)
log_info "Docker version detected: $DOCKER_VERSION"

# Verificar docker compose
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    log_error "Docker Compose no esta disponible. Instala el plugin de Docker Compose."
fi
log_info "Docker Compose esta disponible"

# Verificar curl
if ! command -v curl &> /dev/null; then
    log_error "curl no se encontro. Instala curl para las validaciones."
fi

# Verificar memoria disponible (minimo 4GB)
if [ -f /proc/meminfo ]; then
    DOCKER_MEM=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo "0")
    if [ "$DOCKER_MEM" -lt 4294967296 ] 2>/dev/null; then
        log_warn "La memoria total de Docker es menor a 4GB. Elasticsearch puede fallar."
        log_info "Ajusta la memoria de Docker a minimo 4GB en tu configuracion."
    fi
fi

# ------------------------------------------------------- # Verificar vm.max_map_count (Linux nativo) # -------------------------------------------------------
log_step "Verificando vm.max_map_count"

VM_MAX_MAP=$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo "0")

if [ "$VM_MAX_MAP" -lt 1048576 ]; then
    log_warn "vm.max_map_count esta en $VM_MAX_MAP. Debe ser >= 1048576"
    read -p "Deseas corregir vm.max_map_count ahora? [Y/n] " -r
    if [[ ! "$REPLY" =~ ^[Nn]$ ]]; then
        log_info "Corrigiendo vm.max_map_count..."
        sudo sysctl -w vm.max_map_count=1048576
        log_info "vm.max_map_count actualizado a 1048576"

        # Intentar persistir el cambio
        if [ -w /etc/sysctl.d/ ]; then
            echo "vm.max_map_count=1048576" | sudo tee /etc/sysctl.d/99-elasticsearch.conf > /dev/null
            log_info "Configuracion persistida en /etc/sysctl.d/99-elasticsearch.conf"
        fi
    fi
else
    log_info "vm.max_map_count = $VM_MAX_MAP (correcto)"
fi

# ------------------------------------------------------- # Configurar archivo .env # -------------------------------------------------------
log_step "Configurando entorno"

if [ "$CLEAN" = true ]; then
    log_info "Modo limpio: eliminando contenedores y volenes existentes"
    docker compose down -v --remove-orphans 2>/dev/null || true
fi

if [ -f "$TARGET_ENV" ]; then
    log_info "Archivo $TARGET_ENV ya existe. Usando configuracion existente."
elif [ -f "$ENV_FILE" ]; then
    log_info "Copiando $ENV_FILE como $TARGET_ENV"
    cp "$ENV_FILE" "$TARGET_ENV"
    log_info "Edita $TARGET_ENV para ajustar credenciales y puertos"
else
    log_error "No se encontro el archivo de entorno. Se requiere $ENV_FILE o $TARGET_ENV."
fi

# ------------------------------------------------------- # Validar rutas de bind mounts (si estan configuradas) # -------------------------------------------------------
log_step "Validando rutas de almacenamiento"

# Leer variables de entorno desde .env
get_env_var() {
    local name="$1"
    local line
    line=$(grep -E "^${name}\s*=" "$TARGET_ENV" 2>/dev/null | head -1)
    if [ -n "$line" ]; then
        echo "${line#*=}" | xargs
    fi
}

USE_BIND_MOUNTS=$(get_env_var "USE_BIND_MOUNTS")

if [ "$USE_BIND_MOUNTS" = "true" ]; then
    DATA_DIR_BASE=$(get_env_var "DATA_DIR_BASE")
    ES01_DATA_DIR=$(get_env_var "ES01_DATA_DIR")
    ES02_DATA_DIR=$(get_env_var "ES02_DATA_DIR")
    ES03_DATA_DIR=$(get_env_var "ES03_DATA_DIR")
    CERTS_DIR=$(get_env_var "CERTS_DIR")
    KIBANA_DIR=$(get_env_var "KIBANA_DATA_DIR")

    if [ -n "$DATA_DIR_BASE" ]; then
        # Validar que DATA_DIR_BASE existe (debe ser pre-provisionado)
        if [ ! -d "$DATA_DIR_BASE" ]; then
            log_error "DATA_DIR_BASE no existe: $DATA_DIR_BASE"
            log_error "El directorio base debe ser pre-provisionado antes de ejecutar el script."
        fi

        # Crear los subdirectorios
        SUB_DIRS=("$ES01_DATA_DIR" "$ES02_DATA_DIR" "$ES03_DATA_DIR" "$CERTS_DIR" "$KIBANA_DIR")

        for sub_dir in "${SUB_DIRS[@]}"; do
            if [ -n "$sub_dir" ]; then
                full_path="$DATA_DIR_BASE/$sub_dir"
                if [ ! -d "$full_path" ]; then
                    log_info "Creando subdirectorio de bind mount: $full_path"
                    mkdir -p "$full_path"
                fi
            fi
        done

        log_info "Rutas de bind mounts configuradas:"
        for sub_dir in "${SUB_DIRS[@]}"; do
            if [ -n "$sub_dir" ]; then
                full_path="$DATA_DIR_BASE/$sub_dir"
                echo -e "   ${GRAY}- $full_path${NC}"
            fi
        done
    else
        log_warn "DATA_DIR_BASE no definido. Usando volumes Docker por defecto."
    fi
else
    log_info "USE_BIND_MOUNTS no activo. Usando volumes Docker por defecto."
fi

# ------------------------------------------------------- # Levantar el cluster # -------------------------------------------------------
log_step "Levantando cluster Elasticsearch"

log_info "Descargando imagenes Docker si es necesario..."
docker compose pull --quiet

log_info "Iniciando contenedores (sin --wait, la validacion se hace despues)..."
docker compose up -d

if [ $? -ne 0 ]; then
    log_error "Fallo al levantar los contenedores. Revisa los logs con:"
    log_error "  docker compose logs setup"
    log_error "  docker compose logs es01"
fi

# Verificar que los contenedores estan en estado healthy despues de un tiempo
log_info "Verificando estado de contenedores..."
MAX_HEALTH_CHECKS=36  # 36 intentos * 5s = 180s maximo
HEALTH_ATTEMPT=0

while [ $HEALTH_ATTEMPT -lt $MAX_HEALTH_CHECKS ]; do
    HEALTH_ATTEMPT=$((HEALTH_ATTEMPT + 1))
    sleep 5

    # Obtener estado de contenedores relevantes
    COMPOSE_OUTPUT=$(docker compose ps --format json 2>/dev/null) || true

    if [ -z "$COMPOSE_OUTPUT" ]; then
        printf "."
        continue
    fi

    # Verificar si hay servicios no saludables
    UNHEALTHY=$(echo "$COMPOSE_OUTPUT" | grep -i "unhealthy\|exited\|dead" || true)

    if [ -z "$UNHEALTHY" ]; then
        log_info "Todos los contenedores estan activos. Verificar cluster..."
        break
    fi

    if [ $HEALTH_ATTEMPT -eq $MAX_HEALTH_CHECKS ]; then
        log_warn "Algunos contenedores tardaron en iniciarse. Revisa los logs."
    fi
done
echo ""

# ------------------------------------------------------- # Funcion auxiliar para hacer peticiones HTTP/S # -------------------------------------------------------
es_request() {
    local uri="$1"
    local username="$2"
    local password="$3"

    local curl_opts=(--silent --insecure --cacert /dev/null)

    if [ -n "$username" ] && [ -n "$password" ]; then
        curl_opts+=(-u "${username}:${password}")
    fi

    curl_opts+=("$uri")

    curl "${curl_opts[@]}" 2>/dev/null
}

# ------------------------------------------------------- # Esperar a que Elasticsearch este listo # -------------------------------------------------------
log_step "Esperando que Elasticsearch este disponible"

MAX_ATTEMPTS=60  # 60 intentos * 5s = 300s maximo
ATTEMPT=0

# Obtener credenciales del .env
ELASTIC_CRED=$(get_env_var "ELASTIC_PASSWORD")
ES_PORT="9200"

if [ -f "$TARGET_ENV" ]; then
    PORT_LINE=$(grep -E "^ES_HOST:" "$TARGET_ENV" 2>/dev/null || echo "")
    if [ -n "$PORT_LINE" ]; then
        ES_PORT=$(echo "$PORT_LINE" | sed 's/.*://')
    fi

    ELASTIC_CRED_LINE=$(grep -E "^ELASTIC_PASSWORD=" "$TARGET_ENV" 2>/dev/null | head -1)
    if [ -n "$ELASTIC_CRED_LINE" ]; then
        ELASTIC_CRED=$(echo "$ELASTIC_CRED_LINE" | sed 's/^[^=]*=//' | xargs)
    fi
fi

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))

    RESPONSE=$(es_request "https://localhost:$ES_PORT")
    if [ $? -eq 0 ] || echo "$RESPONSE" | grep -q "status"; then
        log_info "Elasticsearch esta activo. Intento $ATTEMPT/$MAX_ATTEMPTS"
        break
    fi

    printf "."
    sleep 5
done

if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
    log_error "Elasticsearch no se levanto despues de $MAX_ATTEMPTS intentos."
    log_error "Revisa los logs: docker compose logs es01"
fi
echo ""

# ------------------------------------------------------- # Validar el cluster # -------------------------------------------------------
log_step "Validando cluster Elasticsearch"

if [ -n "$ELASTIC_CRED" ]; then
    # Obtener lista de nodos
    NODES_DATA=$(curl --silent --insecure -u "elastic:$ELASTIC_CRED" "https://localhost:$ES_PORT/_cat/nodes?format=json" 2>/dev/null)

    if [ -n "$NODES_DATA" ]; then
        NODE_COUNT=$(echo "$NODES_DATA" | grep -c '"name"' || echo "0")
        log_info "Cluster activo con $NODE_COUNT nodo(s)"

        # Mostrar informacion de cada nodo
        while IFS= read -r line; do
            NODE_NAME=$(echo "$line" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')
            NODE_ROLE=$(echo "$line" | sed -n 's/.*"role":"\([^"]*\)".*/\1/p')
            if [ -n "$NODE_NAME" ]; then
                echo -e "  ${GREEN}- Node: $NODE_NAME${NC}"
                if [ -n "$NODE_ROLE" ]; then
                    echo -e "    Role: ${GRAY}$NODE_ROLE${NC}"
                fi
            fi
        done <<< "$NODES_DATA"

        # Obtener salud del cluster
        CLUSTER_DATA=$(curl --silent --insecure -u "elastic:$ELASTIC_CRED" "https://localhost:$ES_PORT/_cluster/health" 2>/dev/null)

        if [ -n "$CLUSTER_DATA" ]; then
            CLUSTER_STATUS=$(echo "$CLUSTER_DATA" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
            NUM_NODES=$(echo "$CLUSTER_DATA" | sed -n 's/.*"number_of_nodes":\([0-9]*\).*/\1/p')
            log_info "Estado del cluster: $CLUSTER_STATUS"
            log_info "Nodos activos: $NUM_NODES"
        fi
    else
        log_warn "No se pudo obtener informacion de los nodos."
    fi
else
    log_warn "No se encontro ELASTIC_PASSWORD. Saltando validacion detallada del cluster."
fi

# ------------------------------------------------------- # Mostrar informacion de acceso # -------------------------------------------------------
log_step "Informacion de acceso"

KIBANA_PORT="5601"
KIBANA_HOST_LINE=$(grep -E "^KIBANA_PORT=" "$TARGET_ENV" 2>/dev/null || echo "")
if [ -n "$KIBANA_HOST_LINE" ]; then
    KIBANA_PORT=$(echo "$KIBANA_HOST_LINE" | sed 's/^[^=]*=//')
fi

echo ""
echo -e "${CYAN}=============================================================${NC}"
echo -e "${CYAN} Piloto Elasticsearch 8.19 listo${NC}"
echo -e "${CYAN}=============================================================${NC}"
echo ""
echo -e "${WHITE} Elasticsearch API: ${CYAN}https://localhost:$ES_PORT${NC}"
echo -e "${WHITE} Kibana UI: ${CYAN}http://localhost:$KIBANA_PORT${NC}"
echo ""
echo -e " Usuario: ${YELLOW}elastic${NC}"
echo -e " Password: ${YELLOW}$ELASTIC_CRED${NC}"
echo ""
log_info "Para detener el cluster: docker compose down"
log_info "Para logs en tiempo real: docker compose logs -f"
log_info "Para reiniciar con datos: docker compose restart"
log_info "Para limpiar todo: docker compose down -v"
echo ""
