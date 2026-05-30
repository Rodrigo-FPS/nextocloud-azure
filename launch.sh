#!/usr/bin/env bash
#orquesta el despliegue completo en dos VMs via SSH
#uso bash launch.sh swarm apps o compose
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-swarm}"

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o BatchMode=yes"
SSH_TTY="-o StrictHostKeyChecking=accept-new"

if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a; source "$SCRIPT_DIR/.env"; set +a
fi

#espera hasta que el servicio indicado tenga replicas 1/1
wait_for_service() {
  local service="$1" host="$2" user="$3" max="${4:-300}" waited=0
  while true; do
    local replicas
    replicas=$(ssh $SSH_OPTS "$user@$host" \
      "docker service ls --filter name=$service --format '{{.Replicas}}'" 2>/dev/null || echo "0/0")
    [ "$replicas" = "1/1" ] && { echo "$service: 1/1"; return 0; }
    [ $waited -ge $max ] && { echo "WARN: $service no llego a 1/1 en ${max}s ($replicas)"; return 1; }
    printf "\r$service: $replicas (%ds)" "$waited"
    sleep 15; waited=$((waited + 15))
  done
}

case "$MODE" in
swarm)
  for VAR in MANAGER_IP MANAGER_PRIVATE_IP WORKER_IP SSH_USER; do
    val="${!VAR:-}"
    [ -z "$val" ] && { echo "ERROR: $VAR no definida en .env"; exit 1; }
    [[ "$val" == *"<"* ]] && { echo "ERROR: $VAR tiene valor placeholder en .env"; exit 1; }
  done
  STACK_NAME="${STACK_NAME:-nextcloud}"

  echo "manager: $MANAGER_IP  worker: $WORKER_IP  stack: $STACK_NAME"
  echo ""

  ssh $SSH_OPTS "$SSH_USER@$MANAGER_IP" "echo 'VM1: ok'" || { echo "ERROR: sin acceso SSH a VM1"; exit 1; }
  ssh $SSH_OPTS "$SSH_USER@$WORKER_IP"  "echo 'VM2: ok'" || { echo "ERROR: sin acceso SSH a VM2"; exit 1; }

  ssh $SSH_OPTS "$SSH_USER@$MANAGER_IP" "mkdir -p ~/nextcloud"
  scp -o StrictHostKeyChecking=accept-new -rq \
    "$SCRIPT_DIR/stack/" "$SCRIPT_DIR/vm1/" "$SCRIPT_DIR/.env" \
    "$SSH_USER@$MANAGER_IP:~/nextcloud/"

  ssh $SSH_OPTS "$SSH_USER@$WORKER_IP" "mkdir -p ~/nextcloud"
  scp -o StrictHostKeyChecking=accept-new -rq \
    "$SCRIPT_DIR/stack/" "$SCRIPT_DIR/vm2/" "$SCRIPT_DIR/.env" \
    "$SSH_USER@$WORKER_IP:~/nextcloud/"

  echo "archivos copiados"
  echo ""

  ssh $SSH_TTY -t "$SSH_USER@$MANAGER_IP" "sudo bash ~/nextcloud/vm1/provision.sh"
  echo ""

  JOIN_TOKEN=$(ssh $SSH_OPTS "$SSH_USER@$MANAGER_IP" "cat ~/swarm-join-token.txt" 2>/dev/null || true)
  [ -z "$JOIN_TOKEN" ] && { echo "ERROR: no se pudo leer el token de VM1"; exit 1; }

  ssh $SSH_TTY -t "$SSH_USER@$WORKER_IP" "sudo JOIN_TOKEN='$JOIN_TOKEN' bash ~/nextcloud/vm2/provision.sh"
  echo ""

  ssh $SSH_OPTS "$SSH_USER@$MANAGER_IP" \
    "cd ~/nextcloud && MANAGER_IP=$MANAGER_IP STACK_NAME=$STACK_NAME bash stack/deploy.sh"
  echo ""

  echo "esperando nextcloud..."
  sleep 60
  wait_for_service "${STACK_NAME}_nextcloud" "$MANAGER_IP" "$SSH_USER" 360
  echo ""

  ssh $SSH_OPTS "$SSH_USER@$MANAGER_IP" \
    "cd ~/nextcloud && STACK_NAME=$STACK_NAME bash stack/apps.sh"
  echo ""

  echo "nextcloud: https://$MANAGER_IP"
  echo "uptime kuma: http://$MANAGER_IP:3001"
  ;;

apps)
  MANAGER_IP="${MANAGER_IP:-}" SSH_USER="${SSH_USER:-}"
  [ -z "$MANAGER_IP" ] && { echo "ERROR: MANAGER_IP no definida"; exit 1; }
  [ -z "$SSH_USER" ]   && { echo "ERROR: SSH_USER no definido"; exit 1; }
  STACK_NAME="${STACK_NAME:-nextcloud}"
  ssh $SSH_OPTS "$SSH_USER@$MANAGER_IP" \
    "cd ~/nextcloud && STACK_NAME=$STACK_NAME bash stack/apps.sh"
  ;;

compose)
  MANAGER_IP="${MANAGER_IP:-localhost}"
  bash "$SCRIPT_DIR/setup-secrets-compose.sh"
  chmod +x "$SCRIPT_DIR/stack/nextcloud/redis-hook.sh"
  cd "$SCRIPT_DIR"
  MANAGER_IP="$MANAGER_IP" docker compose up -d
  echo "nextcloud: https://$MANAGER_IP"
  echo "uptime kuma: http://$MANAGER_IP:3001"
  ;;

*)
  echo "uso bash launch.sh swarm apps o compose"
  exit 1
  ;;
esac
