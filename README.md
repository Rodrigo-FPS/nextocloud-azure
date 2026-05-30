# Nextcloud en Docker Swarm

Despliegue de Nextcloud sobre un cluster Docker Swarm distribuido en dos nodos, con proxy HTTPS mediante Caddy, cache y bloqueo de archivos con Redis, base de datos MariaDB y monitoreo con Uptime Kuma.

Las contrasenas se gestionan exclusivamente mediante Docker secrets. Ningun valor sensible aparece en archivos de codigo, variables de entorno en texto plano ni imagenes Docker.

---

## Arquitectura

```
Internet
    |
    | HTTPS :443 / HTTP :80 / Uptime Kuma :3001
    |
VM1 — Nodo Manager
    Caddy          proxy reverso HTTPS y gateway de Uptime Kuma
    Nextcloud      aplicacion principal
    |
    | red overlay frontend
    | red overlay backend (internal)
    |
VM2 — Nodo Worker
    MariaDB        base de datos (solo red interna)
    Redis          cache y bloqueo de archivos (solo red interna)
    Uptime Kuma    monitoreo (accesible via Caddy en VM1)
```

La red `backend` tiene `internal: true`, lo que impide que MariaDB y Redis tengan salida a internet o sean alcanzables desde fuera del cluster.

Uptime Kuma no publica ningun puerto propio. Caddy en VM1 actua como proxy hacia el en el puerto 3001 a traves de la red overlay `frontend`.

---

## Requisitos

### Infraestructura

- Dos VMs Linux con Ubuntu 22.04 LTS en la misma red privada
- Acceso SSH con clave desde la maquina local a ambas VMs
- Los scripts de provision instalan Docker automaticamente si no esta presente

### Puertos requeridos en el firewall o NSG

**VM1:**

| Puerto | Protocolo | Origen | Uso |
|--------|-----------|--------|-----|
| 22 | TCP | administrador | SSH |
| 80 | TCP | cualquiera | HTTP, redirige a HTTPS |
| 443 | TCP | cualquiera | HTTPS Nextcloud |
| 3001 | TCP | administrador | Uptime Kuma via Caddy |
| 2377 | TCP | IP privada VM2 | Swarm manager |
| 7946 | TCP/UDP | IP privada VM2 | comunicacion entre nodos |
| 4789 | UDP | IP privada VM2 | red overlay VXLAN |

**VM2:**

| Puerto | Protocolo | Origen | Uso |
|--------|-----------|--------|-----|
| 22 | TCP | administrador | SSH |
| 7946 | TCP/UDP | IP privada VM1 | comunicacion entre nodos |
| 4789 | UDP | IP privada VM1 | red overlay VXLAN |

MariaDB (3306) y Redis (6379) no se abren en ningun firewall. Son internos al cluster.

### Maquina local

- Git
- Acceso SSH a ambas VMs sin passphrase (mediante clave)

---

## Estructura del proyecto

```
.
├── launch.sh                   orquesta el despliegue completo via SSH
├── compose.yaml                stack alternativo para un solo host
├── setup-secrets-compose.sh    genera secrets para compose
├── .env.example                plantilla de configuracion
├── vm1/
│   └── provision.sh            instala Docker e inicializa el Swarm en VM1
├── vm2/
│   └── provision.sh            instala Docker y une VM2 al Swarm
└── stack/
    ├── docker-stack.yml        definicion del stack Docker Swarm
    ├── deploy.sh               despliega el stack en el nodo manager
    ├── apps.sh                 instala apps y crea usuarios en Nextcloud
    ├── setup-secrets.sh        genera contrasenas y crea Docker secrets
    ├── caddy/Caddyfile         configuracion del proxy reverso
    ├── mariadb/custom.cnf      configuracion de MariaDB
    ├── redis/redis.conf        configuracion de Redis
    └── nextcloud/redis-hook.sh configura Redis en Nextcloud al arrancar
```

---

## Configuracion

Copiar `.env.example` como `.env` y completar los valores:

```bash
cp .env.example .env
nano .env
```

| Variable | Descripcion |
|----------|-------------|
| `MANAGER_IP` | IP publica de VM1, usada para Nextcloud y Uptime Kuma |
| `MANAGER_PRIVATE_IP` | IP privada de VM1, usada para el advertise-addr del Swarm |
| `WORKER_IP` | IP publica de VM2, usada para SSH durante el despliegue |
| `SSH_USER` | usuario SSH en ambas VMs |
| `STACK_NAME` | nombre del stack, por defecto `nextcloud` |

---

## Despliegue

### Automatizado desde la maquina local

Con el `.env` configurado y acceso SSH sin passphrase a ambas VMs:

```bash
bash launch.sh swarm
```

El script realiza los siguientes pasos de forma automatica:

1. Valida que el `.env` este completo y sin valores placeholder
2. Verifica la conectividad SSH a ambas VMs
3. Copia los archivos del proyecto a cada VM via SCP
4. Instala Docker y configura el Swarm en VM1
5. Obtiene el token de union del Swarm
6. Instala Docker y une VM2 al Swarm
7. Etiqueta los nodos, genera los secrets y despliega el stack
8. Espera que Nextcloud este disponible
9. Instala las aplicaciones y crea los usuarios de prueba

Al finalizar se muestra la contrasena del administrador. Guardarla en ese momento, no es recuperable despues.

---

### Despliegue manual paso a paso

**Paso 1 — Clonar el repositorio en ambas VMs**

En VM1:
```bash
git clone https://github.com/Rodrigo-FPS/nextocloud-azure.git ~/nextcloud
cd ~/nextcloud
cp .env.example .env
nano .env
```

En VM2:
```bash
git clone https://github.com/Rodrigo-FPS/nextocloud-azure.git ~/nextcloud
cd ~/nextcloud
cp .env.example .env
nano .env
```

El `.env` debe tener los mismos valores en ambas VMs.

**Paso 2 — Provisionar VM1**

```bash
# conectarse a VM1
ssh azureuser@<IP_VM1>
cd ~/nextcloud

sudo bash vm1/provision.sh
```

Al terminar se muestra el token de union al Swarm. Copiarlo para el paso siguiente.

**Paso 3 — Provisionar VM2**

```bash
# conectarse a VM2
ssh azureuser@<IP_VM2>
cd ~/nextcloud

sudo JOIN_TOKEN=<token_del_paso_anterior> bash vm2/provision.sh
```

**Paso 4 — Verificar el Swarm**

Desde VM1:
```bash
docker node ls
```

Deben aparecer dos nodos: el manager y el worker, ambos en estado `Ready`.

**Paso 5 — Desplegar el stack**

Desde VM1:
```bash
cd ~/nextcloud
bash stack/deploy.sh
```

Monitorear el estado hasta que todos los servicios esten `1/1`:
```bash
watch docker service ls
```

**Paso 6 — Instalar aplicaciones y crear usuarios**

```bash
bash stack/apps.sh
```

---

## Servicios desplegados

| Servicio | Imagen | Nodo | Puerto externo |
|----------|--------|------|----------------|
| Caddy | `caddy:2-alpine` | VM1 | 80, 443, 3001 |
| Nextcloud | `nextcloud:28-apache` | VM1 | ninguno directo |
| MariaDB | `mariadb:10.11` | VM2 | ninguno |
| Redis | `redis:7-alpine` | VM2 | ninguno |
| Uptime Kuma | `louislam/uptime-kuma:1` | VM2 | via Caddy :3001 |

## Aplicaciones en Nextcloud

| App | Identificador | Funcion |
|-----|--------------|---------|
| Talk | `spreed` | comunicacion y videollamadas |
| Calendar | `calendar` | calendario compartido |
| Two-Factor TOTP | `twofactor_totp` | autenticacion de dos factores |
| Group Folders | `groupfolders` | carpetas de grupo compartidas |
| Notes | `notes` | notas personales |

---

## Credenciales

El usuario administrador de Nextcloud es `admin`. La contrasena se genera de forma aleatoria al desplegar y se muestra una unica vez en la terminal. Se almacena como Docker secret y no puede leerse despues.

Si se pierde, resetearla con:

```bash
NC=$(docker ps --filter name=nextcloud_nextcloud -q | head -1)
docker exec --user www-data $NC php occ user:resetpassword admin
```

Los usuarios `usuario1` y `usuario2` se crean automaticamente con `stack/apps.sh`. Sus contrasenas se muestran al finalizar ese script.

---

## Monitoreo

Abrir `http://<IP_VM1>:3001` en el navegador y crear una cuenta de administrador la primera vez.

Agregar los siguientes monitores:

| Monitor | Tipo | Destino | Nota |
|---------|------|---------|------|
| Nextcloud HTTPS | HTTP(s) | `https://<IP_VM1>` | activar ignorar TLS |
| HTTP Redirect | HTTP(s) | `http://<IP_VM1>` | desactivar seguir redirecciones |
| MariaDB | TCP Port | `db:3306` | acceso interno via red overlay |
| Redis | TCP Port | `redis:6379` | acceso interno via red overlay |

---

## Comandos de diagnostico

```bash
# nodos del cluster
docker node ls

# estado de todos los servicios
docker service ls

# logs en tiempo real de un servicio
docker service logs -f nextcloud_nextcloud

# estado de Nextcloud
NC=$(docker ps --filter name=nextcloud_nextcloud -q | head -1)
docker exec --user www-data $NC php occ status

# usuarios registrados
docker exec --user www-data $NC php occ user:list

# apps activas
docker exec --user www-data $NC php occ app:list --enabled

# verificar que Redis esta configurado
docker exec $NC cat /var/www/html/config/redis.config.php

# secrets registrados
docker secret ls

# redes overlay activas
docker network ls --filter driver=overlay
```

---

## Reiniciar el stack desde cero

```bash
# en VM1
docker stack rm nextcloud
sleep 20
docker config ls --format '{{.Name}}' | xargs -r docker config rm
docker secret ls --format '{{.Name}}' | xargs -r docker secret rm

bash stack/deploy.sh
bash stack/apps.sh
```

Para limpiar tambien los datos de la base de datos y Nextcloud:
```bash
# en VM1
docker volume rm nextcloud_nextcloud_data

# en VM2
docker volume rm nextcloud_nextcloud_db nextcloud_nextcloud_redis
```
