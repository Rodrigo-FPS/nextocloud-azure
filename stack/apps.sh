#!/usr/bin/env bash
#instala apps en Nextcloud y crea usuarios de prueba
set -euo pipefail

STACK_NAME="${STACK_NAME:-nextcloud}"

get_nc_container() {
  docker ps --filter "name=${STACK_NAME}_nextcloud" --format "{{.ID}}" | head -1 || \
  docker ps --filter "name=${STACK_NAME}-nextcloud" --format "{{.ID}}" | head -1
}

echo "esperando contenedor nextcloud..."
MAX_WAIT=180; WAITED=0
while [ -z "$(get_nc_container)" ] && [ $WAITED -lt $MAX_WAIT ]; do
  sleep 10; WAITED=$((WAITED + 10))
  echo "  ${WAITED}s / ${MAX_WAIT}s"
done

NC=$(get_nc_container)
if [ -z "$NC" ]; then
  echo "ERROR: contenedor nextcloud no encontrado"
  exit 1
fi

install_app() {
  local app="$1"
  docker exec --user www-data "$NC" php occ app:install "$app" &>/dev/null || true
  docker exec --user www-data "$NC" php occ app:enable  "$app" &>/dev/null || true
  echo "app: $app"
}

install_app spreed
install_app calendar
install_app twofactor_totp
install_app groupfolders
install_app notes

echo ""

U1_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)"X1!"
U2_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)"X2!"

docker exec --user www-data -e OC_PASS="$U1_PASS" "$NC" \
  php occ user:add --password-from-env --display-name="Usuario Empresa 1" usuario1 &>/dev/null \
  && echo "usuario1: creado" || echo "usuario1: ya existe"

docker exec --user www-data -e OC_PASS="$U2_PASS" "$NC" \
  php occ user:add --password-from-env --display-name="Usuario Empresa 2" usuario2 &>/dev/null \
  && echo "usuario2: creado" || echo "usuario2: ya existe"

docker exec --user www-data "$NC" php occ background:cron &>/dev/null

echo ""
echo "usuario1 password: $U1_PASS"
echo "usuario2 password: $U2_PASS"
