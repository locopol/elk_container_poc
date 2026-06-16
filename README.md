# Piloto de Implementacion Elasticsearch 8.19

## Resumen del Proyecto

Piloto de validacion e implementacion de un cluster Elasticsearch multi-nodo en contenedores Docker, con todas las caracteristicas habilitadas: seguridad TLS con certificados auto-firmados, monitoreo X-Pack, consola de administracion Kibana y credenciales personalizadas. El resultado es un compose reutilizable que puede desplegar la solucion completa de Elastic para uso inmediato en desarrollo, pruebas y evaluaciones.

## Arquitectura

```
+-----------------+
|   Kibana :5601  |  Consola de administracion web
+--------+--------+
         | https (TLS)
+--------+--------+--------+
|                        |
+-----v-----+   +-------v-------+
| ES01 :9200|<-------------->| ES02 :9200 |
| (master)  |   TLS transport | (master)  |
+------+----+   +-------+-------+
       |                |
+------v----------------v-------+
|      +--------v--------+      |
|      | ES03 :9200      |      |
|      |    (master)     |      |
+-----------------+        +------+
          |
+---------v-----------+
|  Setup Service      |  Genera CA + certificados al inicio
+---------------------+

Volumes: certs, esdata01, esdata02, esdata03, kibanadata
```

## Caracteristicas Implementadas

### 1. Cluster Multi-Nodo
- 3 nodos master-eligible con replica de datos
- Discovery automatico entre nodos
- Tolerancia a fallos (resiste la perdida de 1 nodo)

### 2. Seguridad con TLS/Certificados
- **Certificate Authority (CA) auto-firmada** generada automaticamente
- Certificados individuales para cada nodo
- TLS en HTTP (comunicacion cliente-servidor)
- TLS en Transport (comunicacion entre nodos)
- Verificacion de certificados habilitada

### 3. Monitoreo X-Pack
- Monitoreo de JVM, CPU, memoria, I/O por nodo
- Indices `.monitoring-*` para datos historicos
- Disponibles via Kibana Stack Monitoring

### 4. Credenciales Personalizables
- Usuario `elastic` con password configurable en `.env`
- Usuario `kibana_system` con password configurable en `.env`
- Los passwords se pasan como variables de entorno Docker

### 5. Consola Kibana
- Interfaz web para administracion del cluster
- Monitoring en tiempo real de nodos e indices
- Acceso seguro con credenciales configuradas

## Requisitos del Sistema

| Componente | Requisito Minimo | Recomendado |
|---|---|---|
| Sistema operativo | Linux / Windows 10/11 con WSL2 | Linux con Docker nativo |
| Docker | 4.0+ (Docker Desktop en Windows) | 4.25+ (Docker en Linux) |
| Memoria RAM | 8 GB total, 4 GB para Docker | 16 GB total, 8 GB para Docker |
| Disco | 20 GB disponibles | 50 GB+ disponibles |
| Kernel WSL2 (Windows) | vm.max_map_count >= 1048576 | Se ajusta automaticamente con el script |

### Configuracion de WSL2 (Windows)

Elasticsearch requiere `vm.max_map_count=1048576` en WSL2. El script de inicio verifica y corrige este valor automaticamente. Si se necesita correccion manual:

```bash
wsl -d docker-desktop -u root sysctl -w vm.max_map_count=1048576
```

Para persistir el cambio globalmente, editar `%USERPROFILE%\.wslconfig`:

```ini
[wsl2]
kernelCommandLine = "sysctl.vm.max_map_count=1048576"
```

## Estructura del Proyecto

```
elk_container_poc/
├── docker-compose.yml       # Configuracion del cluster (3 nodos + Kibana)
├── .env                     # Variables de entorno con valores ejemplo
├── .gitignore               # Archivos excluidos del repositorio
├── AGENTS.md                # Documentacion para agentes IA
│
├── Scripts Windows (PowerShell):
│   ├── start-piloto.ps1     # Script de inicio automatizado (Windows/WSL2)
│   └── validate-cluster.ps1 # Script de validacion del cluster (Windows)
│
├── Scripts Linux (Bash):
│   ├── install.sh           # Script de instalacion automatizado (Linux)
│   └── validate-cluster.sh  # Script de validacion del cluster (Linux)
│
├── README.md                # Este archivo (documentacion)
└── config/                  # Directorio para configuraciones externas
```

## Uso Rápido

### Opcion A: Usar scripts predefinidos (recomendado)

#### En Windows (PowerShell 5.x):

```powershell
# Paso 1: Configurar credenciales (opcional)
Copy-Item .env.example .env
# Editar .env para cambiar ELASTIC_PASSWORD y KIBANA_PASSWORD si se requiere

# Paso 2: Ejecutar el script de inicio
.\start-piloto.ps1

# Paso 3 (opcional): Validar el cluster
.\validate-cluster.ps1
```

#### En Linux (Bash):

```bash
# Paso 1: Dar permisos de ejecucion
chmod +x install.sh validate-cluster.sh

# Paso 2: Configurar credenciales (opcional)
cp .env.example .env
# Editar .env para cambiar ELASTIC_PASSWORD y KIBANA_PASSWORD si se requiere

# Paso 3: Ejecutar el script de instalacion
sudo ./install.sh

# Paso 4 (opcional): Validar el cluster
./validate-cluster.sh
```

### Opcion B: Usar Docker Compose directamente

#### En Windows (PowerShell):

```powershell
# Configurar entorno
Copy-Item .env.example .env

# Levantar el cluster
docker compose pull --quiet
docker compose up -d
```

#### En Linux (Bash):

```bash
# Configurar entorno
cp .env.example .env

# Levantar el cluster
docker compose pull --quiet
docker compose up -d
```

### Paso 4: Validar el cluster (opcional)

Ejecuta 8 pruebas automatizadas:
1. API HTTP de Elasticsearch responde
2. Seguridad TLS habilitada
3. Estado del cluster (green/yellow)
4. Todos los nodos activos (3+)
5. Monitoreo X-Pack accesible
6. Kibana UI disponible
7. Indices de monitoreo existentes
8. Certificado CA generado

### Paso 5: Acceder al cluster

| Servicio | URL | Credenciales |
|---|---|---|
| Elasticsearch API | `https://localhost:9200` | `elastic` / (password del .env) |
| Kibana UI | `http://localhost:5601` | `elastic` / (password del .env) |

**Nota**: Las credenciales deben ser al menos 6 caracteres y solo contienen caracteres alfanumericos.

## Gestion del Cluster

### Detener el cluster

```bash
docker compose down
```
Los datos se preservan en los volumes Docker.

### Reiniciar el cluster (con datos)

```bash
docker compose restart
```

### Eliminar todo (datos y contenedores)

```bash
docker compose down -v --remove-orphans
```
**Cuidado**: Esto elimina los datos persistentes. Usar solo para reinicios completos.

### Ver logs en tiempo real

```bash
docker compose logs -f setup    # Logs del servicio de configuracion
docker compose logs -f es01     # Logs del nodo 1
docker compose logs -f es02     # Logs del nodo 2
docker compose logs -f es03     # Logs del nodo 3
docker compose logs -f kibana   # Logs de Kibana
```

### Ver estado de contenedores

```bash
docker compose ps
```

## Personalizacion del Cluster

### Cambiar credenciales de admin

Editar el archivo `.env`:

```ini
ELASTIC_PASSWORD=TuPassword123
KIBANA_PASSWORD=TuKibana456
```

### Cambiar nombre del cluster

```ini
CLUSTER_NAME=micluster-custom
```

### Exponer puertos en la red

```ini
# Por defecto: ES expuesto en 0.0.0.0 (accesible desde la red)
ES_HOST=0.0.0.0
ES_PORT=9200

# Para restringir solo a localhost:
# ES_HOST=127.0.0.1
# ES_PORT=9200

# Kibana se expone en localhost por defecto (mas seguro)
KIBANA_HOST=127.0.0.1
KIBANA_PORT=5601
```

### Bind Mounts para persistencia de datos

El proyecto soporta dos modos de almacenamiento:

**Modo 1: Bind mounts (recomendado)**
- Los datos se almacenan en directorios del host configurables:

```ini
USE_BIND_MOUNTS=true
DATA_DIR_BASE=/ruta/al/directorio/base
ES01_DATA_DIR=esdata01
ES02_DATA_DIR=esdata02
ES03_DATA_DIR=esdata03
CERTS_DIR=certs
KIBANA_DATA_DIR=kibanadata
```

**Modo 2: Volumes Docker** (comportamiento anterior):

```ini
USE_BIND_MOUNTS=false
```

Al desactivar bind mounts, se usan volumes nombrados de Docker (comportamiento por defecto sin configuracion explicita).

### Cambiar limite de memoria

```ini
MEM_LIMIT=2147483648   # 2 GB (en bytes)
MEM_LIMIT=4294967296   # 4 GB (en bytes)
```

### Cambiar version de Elastic

```ini
STACK_VERSION=8.19.16
```

Consultar https://www.docker.elastic.co/ para todas las versiones disponibles.

### Habilitar licencia trial (30 dias)

Descomentar en `.env`:

```ini
LICENSE=trial
```

Esto habilita todas las caracteristicas premium (ML, seguridad avanzada, etc.).

### Agregar un 4to nodo

1. Agregar un nuevo bloque `es04` en `docker-compose.yml` replicando el formato de es03.
2. Actualizar `cluster.initial_master_nodes` en todos los nodos:

```ini
- cluster.initial_master_nodes=es01,es02,es03,es04
```

3. Actualizar `discovery.seed_hosts` en cada nodo para incluir los demas.
4. Agregar `es04` al `instances.yml` en el servicio `setup`.
5. Reiniciar con `docker compose up -d`.

## Referencias Tecnicas

### Variables de entorno Elasticsearch (en docker-compose.yml)

| Variable | Descripcion |
|---|---|
| `node.name` | Nombre identificador del nodo |
| `cluster.name` | Nombre del cluster |
| `cluster.initial_master_nodes` | Nodos master-eligible iniciales |
| `discovery.seed_hosts` | Pares de descubrimiento para el cluster |
| `ELASTIC_PASSWORD` | Password del usuario elastic |
| `bootstrap.memory_lock=true` | Bloquea memoria RAM (evita swap) |
| `xpack.security.enabled=true` | Habilita seguridad X-Pack |
| `xpack.security.http.ssl.enabled=true` | TLS en HTTP |
| `xpack.security.transport.ssl.enabled=true` | TLS en transport |
| `xpack.monitoring.enabled=true` | Habilita monitoreo X-Pack |
| `xpack.license.self_generated.type` | Tipo de licencia (basic/trial) |

### Volúmenes Docker

| Volume | Descripcion |
|---|---|
| `certs` | Certificados TLS (CA + nodos) |
| `esdata01` | Datos del nodo es01 (bind mount o volume) |
| `esdata02` | Datos del nodo es02 (bind mount o volume) |
| `esdata03` | Datos del nodo es03 (bind mount o volume) |
| `kibanadata` | Datos de Kibana (bind mount o volume) |

**Nota**: Por defecto se usan bind mounts configurados en `.env`. Para cambiar a volumes Docker nombrados, establece `USE_BIND_MOUNTS=false` en el archivo `.env`.

### Puertos

| Puerto | Servicio | Protocolo |
|---|---|---|
| 9200 | Elasticsearch HTTP | HTTPS (TLS) |
| 9300 | Elasticsearch Transport | TLS entre nodos |
| 5601 | Kibana UI | HTTP (sin TLS en el contenedor) |

## Consideraciones de Seguridad

1. **NUNCA comprometas el archivo `.env`** en el repositorio. Contiene las credenciales de acceso.
2. **Los certificados son auto-firmados** (CA generada localmente). Apto para desarrollo/pruebas. Para produccion, usar una CA externa.
3. **La memoria lock (`memlock: -1`)** previene el uso de swap por Elasticsearch, necesario para el rendimiento.
4. **El usuario `elastic` tiene acceso total** al cluster. Para produccion, crear roles y usuarios con privilegios minimos.
5. **Las credenciales se pasan como variables de entorno**. Para produccion, usar Docker Secrets o un gestor de credenciales.

## Solucion de Problemas

### Contenedor no arranca

```bash
docker compose logs es01
docker compose logs setup
```

Verificar que `vm.max_map_count` este en 1048576.

### Memoria insuficiente

Aumentar la memoria asignada a Docker Desktop (Settings > Resources > Memory) a al menos 4 GB.

### Certificados expirados o corruptos

```bash
docker compose down -v
docker compose up -d
```

Esto regenera los certificados automaticamente.

### Kibana no conecta con Elasticsearch

Verificar que todos los nodos de Elasticsearch esten saludables antes de que Kibana intente conectar. El servicio Kibana espera `condition: service_healthy` en los nodos ES.

## Resumen de Automatizacion

| Elemento | Entorno | Descripcion |
|---|---|---|
| docker-compose.yml | Multi-plataforma | Cluster 3 nodos + Kibana con seguridad TLS |
| .env | Multi-plataforma | Variables de entorno configurables |
| start-piloto.ps1 | Windows (PowerShell) | Script de inicio con verificacion automatica para WSL2 |
| validate-cluster.ps1 | Windows (PowerShell) | 8 pruebas automatizadas del cluster (Windows) |
| install.sh | Linux (Bash) | Script de instalacion con verificacion automatica para Linux nativo |
| validate-cluster.sh | Linux (Bash) | 8 pruebas automatizadas del cluster (Linux) |
| .gitignore | Multi-plataforma | Protege credenciales y datos sensibles |
| Documentacion (README) | Multi-plataforma | Referencia completa del proyecto |

## Versiones

- **Elasticsearch**: 8.19.16
- **Kibana**: 8.19.16
- **Docker Compose**: v2.2+
- **Piloto version**: 1.0

---

* Proyecto piloto generado para validacion y evaluacion de Elasticsearch en entorno Docker.
* Realizado por Paul Asalgado Ruz, 2026
* Se ha hecho uso de IA local para la implementacion, prueba y ejecucion del piloto.
