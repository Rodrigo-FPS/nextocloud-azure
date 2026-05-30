#!/usr/bin/env bash
#despliega el stack en el nodo manager
#uso bash stack/deploy.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STACK_NAME="${STACK_NAME:-nextcloud}"

#carga el archivo .env desde el directorio del script o su padre
for env_file in "$SCRIPT_DIR/.env" "$ROOT_DIR/.env"; do
  if [ -f "$env_file" ]; then
    set -a; source "$env_file"; set +a
    break
  fi
done

MANAGER_IP="${MANAGER_IP:-}"
if [ -z "$MANAGER_IP" ]; then
  echo "ERROR: MANAGER_IP no definida en .env"
  exit 1
fi

SWARM_STATE=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive")
IS_MANAGER=$(docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null || echo "false")
if [ "$SWARM_STATE" != "active" ] || [ "$IS_MANAGER" != "true" ]; then
  echo "ERROR: este nodo no es manager activo del swarm"
  exit 1
fi

docker node ls
echo ""

WORKER_NODE=$(docker node ls --filter "role=worker" --format "{{.ID}}" | head -1)
if [ -z "$WORKER_NODE" ]; then
  echo "ERROR: no hay nodo worker en el swarm ejecuta provision.sh en VM2 primero"
  exit 1
fi

MANAGER_NODE=$(docker node ls --filter "role=manager" --format "{{.ID}}" | head -1)
docker node update --label-add role=worker  "$WORKER_NODE"  > /dev/null
docker node update --label-add role=manager "$MANAGER_NODE" > /dev/null
echo "labels: manager=$MANAGER_NODE worker=$WORKER_NODE"
echo ""

bash "$SCRIPT_DIR/setup-secrets.sh"

cd "$SCRIPT_DIR"
MANAGER_IP="$MANAGER_IP" docker stack deploy -c docker-stack.yml "$STACK_NAME" --with-registry-auth
echo ""

sleep 15
docker stack services "$STACK_NAME"
