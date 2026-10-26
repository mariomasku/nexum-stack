#!/bin/bash
# La cache de PrestaShop 1.7+ (var/cache/<entorno>/appParameters.php) con la BBDD de otro sitio (la de
# Docker: db) no deja a la tienda conectar en LAMPP (Linux 1.55.10 / Mac 1.39.21): al cargarla se
# aparta, y en Docker la cache va en un volumen del contenedor. Uso: ps-cache.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-ps-cache.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
grep -q '^function ps_stale_cache() {' "$SRC" || { echo "  ok    (sin ps_stale_cache)"; exit 0; }
extract "$SRC" ps_stale_cache || exit 1

HTDOCS_DIR=$W/htdocs HOME=$W/casa DRY=0
T=$HTDOCS_DIR/tienda
mkdir -p "$T/app/config" "$T/var/cache/prod" "$T/var/cache/dev" "$HOME"
params() { printf "<?php return array('parameters' => array(\n    'database_host' => '%s',\n    'database_name' => 'ps_tienda',\n    'database_user' => '%s',\n));\n" "$1" "$2"; }
params localhost root > "$T/app/config/parameters.php"
params db nexum > "$T/var/cache/prod/appParameters.php"
params localhost root > "$T/var/cache/dev/appParameters.php"
o=$(ps_stale_cache tienda)
check "la cache con la BBDD de Docker se aparta y lo dice" '[ ! -e "$T/var/cache/prod" ] && ls -d "$HOME"/lvm-copias/tienda-cache-prod-* > /dev/null 2>&1 && grep -q "apartada" <<< "$o"'
check "la cache con la BBDD buena se queda" '[ -f "$T/var/cache/dev/appParameters.php" ]'
o=$(ps_stale_cache tienda)
check "otra vez: nada que apartar" '[ -z "$o" ] && [ -f "$T/var/cache/dev/appParameters.php" ]'
mkdir -p "$HTDOCS_DIR/blog"
check "un proyecto que no es PrestaShop 1.7: no hace nada" 'o=$(ps_stale_cache blog); [ $? -eq 0 ] && [ -z "$o" ]'

# docker_fix_cache: los compose.yaml de antes pasan la cache a su volumen
if grep -q '^function docker_fix_cache() {' "$SRC"; then
    extract "$SRC" docker_fix_cache || exit 1
    DOCKER_DIR=$W/docker
    mkdir -p "$DOCKER_DIR/tienda"
    docker_projects() { echo tienda; }
    docker_conf() { echo tienda; }
    docker_state() { echo parado; }
    dk() { echo "dk $*" >> "$W/dk.log"; }
    cat > "$DOCKER_DIR/tienda/compose.yaml" << 'EOF'
name: nexum-tienda
services:
  php:
    volumes:
      - "/opt/htdocs/tienda:/opt/lampp/htdocs/tienda"
      - "./config.php:/opt/lampp/htdocs/tienda/app/config/parameters.php:ro"
    depends_on: [db]
volumes:
  db: {}
EOF
    docker_fix_cache
    check "docker: la cache de la tienda, en un volumen del contenedor" 'grep -qx "      - \"cache:/opt/lampp/htdocs/tienda/var/cache\"" "$DOCKER_DIR/tienda/compose.yaml" && grep -qx "  cache: {}" "$DOCKER_DIR/tienda/compose.yaml"'
    docker_fix_cache
    check "docker: otra vez, sin repetirlo" '[ "$(grep -c "var/cache" "$DOCKER_DIR/tienda/compose.yaml")" == 1 ]'
else
    # (Mac: el compose.yaml se hace entero con docker_compose_file, y al arrancar se rehace si le falta)
    check "docker: la cache de la tienda, en un volumen del contenedor (y se rehace al arrancar)" 'awk "/^function docker_compose_file\(\) \{/,/^}/" "$SRC" | grep -q "cache:%s/xamppfiles/htdocs/%s/var/cache" && awk "/^function docker_action\(\) \{/,/^}/" "$SRC" | grep -q "docker_compose_file \"\$slug\" > \"\$dir/compose.yaml.nuevo\""'
fi
exit $fail
