#!/usr/bin/env bash
#instala Docker y une el nodo al Swarm como worker
#uso sudo JOIN_TOKEN=token bash vm2/provision.sh
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
JOIN_TOKEN="${JOIN_TOKEN:?ERROR: JOIN_TOKEN no definido obtenerlo de VM1 con cat ~/swarm-join-token.txt}"
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

if [ "$SWARM_STATE" = "active" ]; then
  echo "swarm: ya en un swarm"
else
  docker swarm join --token "$JOIN_TOKEN" "${MANAGER_PRIVATE_IP}:2377"
  echo "swarm: unido a $MANAGER_PRIVATE_IP"
fi
