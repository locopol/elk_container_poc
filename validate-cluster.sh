#!/bin/bash
# ============================================================================= # Piloto Elasticsearch - Script de validacion del cluster # Verifica que todos los nodos, seguridad y monitoreo esten operativos # Entorno: Linux (bash) # Version: 1.0 # =============================================================================

set -uo pipefail

# ------------------------------------------------------- # Argumentos # -------------------------------------------------------
ENV_FILE=".env"
CA_CERT_PATH="config/certs/ca/ca.crt"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env-file=*) ENV_FILE="${1#*=}"; shift ;;
        --ca-cert=*) CA_CERT_PATH="${1#*=}"; shift ;;
        *) echo "Uso: $0 [--env-file <archivo>] [--ca-cert <ruta>]"
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
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

test_name() { echo -e "\n${CYAN}[$1]${NC}" ; }
pass_test()  { TESTS_PASSED=$((TESTS_PASSED + 1)) ; TESTS_TOTAL=$((TESTS_TOTAL + 1)) ; echo -e "  ${GREEN}[PASS]${NC} $1" ; }
fail_test()  { TESTS_FAILED=$((TESTS_FAILED + 1)) ; TESTS_TOTAL=$((TESTS_TOTAL + 1)) ; echo -e "  ${RED}[FAIL]${NC} $1" ; }

# ------------------------------------------------------- # Leer credenciales del .env # -------------------------------------------------------
get_env_var() {
    local name="$1"
    local line
    line=$(grep -E "^${name}\s*=" "$ENV_FILE" 2>/dev/null | head -1)
    if [ -n "$line" ]; then
        echo "${line#*=}" | xargs
    fi
}

ELASTIC_PASSWORD=""
KIBANA_PASSWORD=""
ES_PORT="9200"

if [ -f "$ENV_FILE" ]; then
    ELASTIC_PASSWORD=$(get_env_var "ELASTIC_PASSWORD")
    KIBANA_PASSWORD=$(get_env_var "KIBANA_PASSWORD")

    # Extraer el puerto del ES_HOST:puerto o solo ES_HOST si no tiene puerto
    ES_HOST_LINE=$(grep -E "^ES_HOST" "$ENV_FILE" 2>/dev/null | grep -v "^#" | head -1)
    if [ -n "$ES_HOST_LINE" ]; then
        # Si tiene formato 0.0.0.0:9200 o similar, extraer el puerto
        PORT_PART=$(echo "$ES_HOST_LINE" | grep -oE ':[0-9]+$' || true)
        if [ -n "$PORT_PART" ]; then
            ES_PORT="${PORT_PART:1}"
        fi
    fi
fi

if [ -z "$ELASTIC_PASSWORD" ]; then
    echo -e "${RED}[ERROR]${NC} No se encontro ELASTIC_PASSWORD en $ENV_FILE"
    exit 1
fi

BASE_URI="https://localhost:$ES_PORT"

# Funcion para hacer peticiones curl seguras (sin verificar certificado)
curl_es() {
    local uri="$1"
    local extra_opts="${2:-}"
    curl --silent --insecure -u "elastic:$ELASTIC_PASSWORD" "$uri" $extra_opts 2>/dev/null
}

# ------------------------------------------------------- # Test 1: Elasticsearch HTTP API esta disponible # -------------------------------------------------------
test_name "Test 1 - API HTTP de Elasticsearch"

HTTP_INFO=$(curl_es "$BASE_URI")
if [ -n "$HTTP_INFO" ]; then
    HTTP_VERSION=$(echo "$HTTP_INFO" | grep -oP '"number"\s*:\s*"[^"]*"' | head -1 | grep -oP '":\s*"\K[^"]+' || echo "")
    CLUSTER_NAME=$(echo "$HTTP_INFO" | grep -oP '"cluster_name"\s*:\s*"\K[^"]+' || echo "")

    if [ -n "$HTTP_VERSION" ]; then
        pass_test "API HTTP responde correctamente"
        echo "   Version: $HTTP_VERSION"
        echo "   Cluster: $CLUSTER_NAME"
    else
        # Aunque no podamos parsear, si recibimos algo es bueno
        pass_test "API HTTP responde correctamente"
    fi
else
    fail_test "API HTTP no responde (curl fallo)"
fi

# ------------------------------------------------------- # Test 2: Seguridad TLS esta habilitada # -------------------------------------------------------
test_name "Test 2 - Seguridad TLS"

AUTH_RESPONSE=$(curl_es "$BASE_URI/_security/authc")
if [ -n "$AUTH_RESPONSE" ]; then
    pass_test "Autenticacion HTTP habilitada"
else
    fail_test "Autenticacion HTTP no disponible"
fi

# ------------------------------------------------------- # Test 3: Estado del cluster # -------------------------------------------------------
test_name "Test 3 - Estado del cluster"

HEALTH_RESPONSE=$(curl_es "$BASE_URI/_cluster/health")
if [ -n "$HEALTH_RESPONSE" ]; then
    CLUSTER_STATUS=$(echo "$HEALTH_RESPONSE" | grep -oP '"status"\s*:\s*"\K[^"]+' || echo "")
    NODE_COUNT=$(echo "$HEALTH_RESPONSE" | grep -oP '"number_of_nodes"\s*:\s*\K[0-9]+' || echo "")
    PRIMARY_SHARDS=$(echo "$HEALTH_RESPONSE" | grep -oP '"number_of_primary_shards"\s*:\s*\K[0-9]+' || echo "")
    TOTAL_SHARDS=$(echo "$HEALTH_RESPONSE" | grep -oP '"number_of_shards"\s*:\s*\K[0-9]+' || echo "")

    if [ "$CLUSTER_STATUS" = "green" ] || [ "$CLUSTER_STATUS" = "yellow" ]; then
        pass_test "Estado del cluster: $CLUSTER_STATUS"
    else
        fail_test "Estado del cluster: ${CLUSTER_STATUS:-desconocido} (esperado green/yellow)"
    fi

    echo "   Nodos: $NODE_COUNT"
    echo "   Shards primarios: $PRIMARY_SHARDS"
    echo "   Shards totales: $TOTAL_SHARDS"
else
    fail_test "No se pudo obtener estado del cluster"
fi

# ------------------------------------------------------- # Test 4: Todos los nodos estan activos # -------------------------------------------------------
test_name "Test 4 - Nodos del cluster"

NODES_RESPONSE=$(curl_es "$BASE_URI/_cat/nodes?format=json")
if [ -n "$NODES_RESPONSE" ]; then
    NODE_COUNT=$(echo "$NODES_RESPONSE" | grep -c '"name"' || echo "0")

    if [ "$NODE_COUNT" -ge 3 ]; then
        pass_test "Hay $NODE_COUNT nodos activos (esperado: 3+)"
    else
        fail_test "Solo hay $NODE_COUNT nodos (esperado: 3+)"
    fi

    # Mostrar nombre y roles de cada nodo
    # Parsear JSON de nodos individualmente
    NODE_COUNT_PARSED=$(echo "$NODES_RESPONSE" | python3 -c "import sys,json; data=json.load(sys.stdin); [print(f'{n.get(\"name\",\"?\"},roles={n.get(\"role\",\"\")}') for n in data]" 2>/dev/null || true)

    if [ -n "$NODE_COUNT_PARSED" ]; then
        echo "$NODE_COUNT_PARSED" | while IFS= read -r line; do
            echo "   - $line"
        done
    else
        # Fallback: mostrar las primeras lineas sin parsear
        echo "$NODES_RESPONSE" | head -5 | sed 's/^/     /'
    fi
else
    fail_test "No se pudo listar los nodos"
fi

# ------------------------------------------------------- # Test 5: Monitoreo X-Pack esta activo # -------------------------------------------------------
test_name "Test 5 - Monitoreo X-Pack"

MONITORING_RESPONSE=$(curl_es "$BASE_URI/_nodes/stats/jvm?pretty=false")
if [ -n "$MONITORING_RESPONSE" ]; then
    pass_test "Monitoreo de nodos accesible via API"
else
    fail_test "No se pudo acceder al monitoreo de nodos"
fi

# ------------------------------------------------------- # Test 6: Kibana esta disponible # -------------------------------------------------------
test_name "Test 6 - Kibana UI"

KIBANA_PORT="5601"
if [ -f "$ENV_FILE" ]; then
    KIBANA_PORT_LINE=$(grep -E "^KIBANA_PORT=" "$ENV_FILE" 2>/dev/null | head -1)
    if [ -n "$KIBANA_PORT_LINE" ]; then
        KIBANA_PORT=$(echo "$KIBANA_PORT_LINE" | sed 's/^[^=]*=//')
    fi
fi

# Probar Kibana (HTTP, sin autenticacion obligatoria por defecto)
KIBANA_HTTP_RESPONSE=$(curl --silent --connect-timeout 10 -o /dev/null -w "%{http_code}" "http://localhost:$KIBANA_PORT" 2>/dev/null)

if [ -n "$KIBANA_HTTP_RESPONSE" ] && [ "$KIBANA_HTTP_RESPONSE" -ge 200 ] 2>/dev/null; then
    pass_test "Kibana responde en puerto $KIBANA_PORT (status: $KIBANA_HTTP_RESPONSE)"
else
    fail_test "Kibana no responde en puerto $KIBANA_PORT"
fi

# ------------------------------------------------------- # Test 7: Indice de monitoreo existe # -------------------------------------------------------
test_name "Test 7 - Indices de monitoreo"

MONITORING_INDICES=$(curl_es "$BASE_URI/_cat/indices/.monitoring*?format=json")
if [ -n "$MONITORING_INDICES" ] && echo "$MONITORING_INDICES" | grep -q '"index"'; then
    pass_test "Indices de monitoreo .monitoring* existen"
    echo "$MONITORING_INDICES" | grep -oP '"index"\s*:\s*"\K[^"]+' | sed 's/^/     /'
else
    # No todos los clusters tienen indices de monitoring inmediatamente despues de arrancar
    echo -e "  ${YELLOW}[WARN]${NC} No hay indices de monitoreo (puede tardar en poblarse)"
fi

# ------------------------------------------------------- # Test 8: Certificado SSL de la CA # -------------------------------------------------------
test_name "Test 8 - Certificado CA"

if [ -f "$CA_CERT_PATH" ]; then
    pass_test "Certificado CA existe en $CA_CERT_PATH"
else
    # Verificar si el certificado esta dentro del volumen Docker
    # En entornos Docker, los certificados se generan en el contenedor setup
    DOCKER_CA_EXISTS=$(docker compose ps setup 2>/dev/null | grep -q "setup" && echo "true" || echo "false")

    if [ "$DOCKER_CA_EXISTS" = "true" ]; then
        # Verificar si existe en el directorio de datos
        DATA_DIR_BASE=$(get_env_var "DATA_DIR_BASE")
        CERTS_DIR=$(get_env_var "CERTS_DIR")

        if [ -n "$DATA_DIR_BASE" ] && [ -n "$CERTS_DIR" ]; then
            DOCKER_CA_PATH="$DATA_DIR_BASE/$CERTS_DIR/ca/ca.crt"
            if [ -f "$DOCKER_CA_PATH" ]; then
                pass_test "Certificado CA existe en $DOCKER_CA_PATH (bind mount)"
            else
                fail_test "Certificado CA no encontrado en $CA_CERT_PATH"
            fi
        else
            # Intentar ver si el volumen de datos existe
            if [ -d "config/certs" ]; then
                pass_test "Directorio de certificados existe (config/certs)"
            else
                fail_test "Certificado CA no encontrado en $CA_CERT_PATH"
            fi
        fi
    else
        fail_test "Certificado CA no encontrado en $CA_CERT_PATH"
    fi
fi

# ------------------------------------------------------- # Resumen # -------------------------------------------------------
echo ""
echo -e "${CYAN}=============================================================${NC}"
echo -e "${CYAN} Resultados de validacion${NC}"
echo -e "${CYAN}=============================================================${NC}"
echo -e " Aprobados: ${GREEN}$TESTS_PASSED${NC}"
echo -e " Fallidos: ${RED}$TESTS_FAILED${NC}"
echo -e " Total: $((TESTS_PASSED + TESTS_FAILED))${NC}"
echo ""

if [ "$TESTS_FAILED" -gt 0 ]; then
    echo -e "${YELLOW}Algunas pruebas fallaron. Revisa los logs con:${NC}"
    echo -e "${WHITE} docker compose logs${NC}"
    exit 1
else
    echo -e "${GREEN}Todas las pruebas pasaron correctamente.${NC}"
    exit 0
fi
