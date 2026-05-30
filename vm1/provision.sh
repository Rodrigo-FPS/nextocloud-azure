#!/usr/bin/env bash
#instala Docker e inicializa Docker Swarm en el nodo manager
#uso sudo bash vm1/provision.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

#carga el archivo .env desde el directorio del script o su padre
for env_file in "$SCRIPT_DIR/.env" "$ROOT_DIR/.env"; do
  if [ -f "$env_file" ]; then
    set -a; source "$env_file"; set +a
    break
  fi
done

MANAGER_PRIVATE_IP="${MANAGER_PRIVATE_IP:?ERROR: MANAGER_PRIVATE_IP no definida en .env}"
export DEBIAN_FRONTEND=noninteractive

#obtiene el usuario real del sistema usando SSH_USER del .env o el primer usuario con uid mayor a 1000
LINUX_USER="${SSH_USER:-}"
if [ -z "$LINUX_USER" ] || [ "$LINUX_USER" = "root" ]; then
  LINUX_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' | head -1)
fi

if command -v docker &>/dev/null; then
  echo "docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
else
  echo "docker: instalando..."
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  systemctl enable docker
  systemctl start docker
  echo "docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
fi

if [ -n "$LINUX_USER" ] && id "$LINUX_USER" &>/dev/null; then
  usermod -aG docker "$LINUX_USER"
  echo "docker group: $LINUX_USER agregado (requiere nueva sesion SSH para tomar efecto)"
else
  echo "WARN: no se encontro usuario no-root para agregar al grupo docker"
fi

SWARM_STATE=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive")
IS_MANAGER=$(docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null || echo "false")

if [ "$SWARM_STATE" = "active" ] && [ "$IS_MANAGER" = "true" ]; then
  echo "swarm: ya activo como manager"
else
  docker swarm leave --force 2>/dev/null || true
  docker swarm init --advertise-addr "$MANAGER_PRIVATE_IP" 2>&1 | grep -v "^$" || true
  echo "swarm: inicializado en $MANAGER_PRIVATE_IP"
fi

if [ -n "$LINUX_USER" ] && id "$LINUX_USER" &>/dev/null; then
  TOKEN_FILE="/home/$LINUX_USER/swarm-join-token.txt"
else
  TOKEN_FILE="/root/swarm-join-token.txt"
fi
docker swarm join-token worker -q > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"
chown "${LINUX_USER}:${LINUX_USER}" "$TOKEN_FILE" 2>/dev/null || true

echo "token: $TOKEN_FILE"
echo "---"
cat "$TOKEN_FILE"
