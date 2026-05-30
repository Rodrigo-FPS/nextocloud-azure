#!/bin/sh
#escribe la configuracion de Redis en Nextcloud leyendo la contrasena desde el secret
#se ejecuta antes de iniciar Apache en cada arranque del contenedor

SECRET_FILE="/run/secrets/redis_password"
CONFIG_FILE="/var/www/html/config/redis.config.php"

if [ ! -f "$SECRET_FILE" ]; then
  echo "[redis-hook] secret redis_password no encontrado saltando configuracion"
  exit 0
fi

REDIS_PASS=$(cat "$SECRET_FILE")

#espera a que el directorio de configuracion exista antes de escribir
ATTEMPTS=0
while [ ! -d "/var/www/html/config" ] && [ $ATTEMPTS -lt 30 ]; do
  sleep 2
  ATTEMPTS=$((ATTEMPTS + 1))
done

cat > "$CONFIG_FILE" << PHPEOF
<?php
\$CONFIG = [
  'memcache.local'   => '\\OC\\Memcache\\Redis',
  'memcache.locking' => '\\OC\\Memcache\\Redis',
  'redis' => [
    'host'     => 'redis',
    'port'     => 6379,
    'password' => '${REDIS_PASS}',
    'timeout'  => 0.0,
  ],
  'filelocking.enabled' => true,
];
PHPEOF

#www-data tiene uid 33 en la imagen oficial de Nextcloud
chown 33:33 "$CONFIG_FILE" 2>/dev/null || true
chmod 640   "$CONFIG_FILE"

echo "[redis-hook] configuracion Redis escrita en $CONFIG_FILE"
