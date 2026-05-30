#!/usr/bin/env bash
#genera contrasenas aleatorias y las registra como Docker secrets
set -euo pipefail

if ! docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q "active"; then
  echo "ERROR: este nodo no esta en un swarm activo"
  exit 1
fi

create_secret() {
  local name="$1" value="$2"
  if docker secret inspect "$name" &>/dev/null; then
    echo "secret $name: ya existe"
  else
    printf '%s' "$value" | docker secret create "$name" - > /dev/null
    echo "secret $name: creado"
  fi
}

DB_ROOT_PASS=$(openssl rand -hex 32)
DB_PASS=$(openssl rand -hex 24)
REDIS_PASS=$(openssl rand -hex 24)
NC_ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9!@#$%' | head -c 18)

create_secret "db_root_password"         "$DB_ROOT_PASS"
create_secret "db_password"              "$DB_PASS"
create_secret "redis_password"           "$REDIS_PASS"
create_secret "nextcloud_admin_password" "$NC_ADMIN_PASS"

echo ""
echo "admin user:     admin"
echo "admin password: $NC_ADMIN_PASS"
echo ""
