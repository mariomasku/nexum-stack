#!/bin/bash
# Seguridad (Linux y Mac 1.57.12): la barrera entre webs llega también al Apache de Docker (se rehace su
# configuración y, en marcha, se recarga), install-php-extensions fijado por su huella también en el Mac, y la
# copia al borrar una BBDD en el Mac sin el administrador de pruebas ni el correo (con export_database).
# Uso: seguridad-docker.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
check "la barrera rehace el Apache de Docker, si lo hay" 'grep -qF "if [ -f \"\$DOCKER_WEB_DIR/conf/httpd.conf\" ]; then" "$SRC" && grep -qF "docker_web_reload || echo \"Aviso: el Apache de Docker no se ha podido poner al dia; la tomara al arrancar\"" "$SRC"'
if grep -q "^let ERROR_LOG = " "$SRC"; then
    check "Mac: install-php-extensions fijado por su huella" 'grep -q "^DOCKER_EXT_INSTALLER=\"mlocati/php-extension-installer:[0-9.]*@sha256:[0-9a-f]\{64\}\"$" "$SRC" && ! grep -q "mlocati/php-extension-installer:2 " "$SRC" && grep -qF "printf '"'"'COPY --from=%s /usr/bin/install-php-extensions /usr/local/bin/\\n'"'"' \"\$DOCKER_EXT_INSTALLER\"" "$SRC"'
    check "Mac: borrar-bd --copia, con export_database (sin el administrador de pruebas ni el correo)" 'awk "/^function drop_database\\(\\)/,/^}/" "$SRC" | grep -qF "export_database \"\$db\" \"\$dest\" \"\$DB_FOLDER\"" && ! awk "/^function drop_database\\(\\)/,/^}/" "$SRC" | grep -q "mysqldump"'
else
    W=$(mktemp -d "$TMPBASE/w-barrera.XXXX") || exit 1
    trap 'rm -rf "${W:?}"' EXIT
    extract "$SRC" cross_site_command || exit 1
    function cross_site_on() { [ ! -e "$CROSS_SITE_OFF" ]; }
    function sudo_first() { return 0; }
    function secure_all() { return 0; }
    function lampp_running() { return 1; }
    function docker_web_reload() { echo recargado >> "$W/docker"; }
    mkdir -p "$W/web/conf"; : > "$W/web/conf/httpd.conf"
    DRY=0 LOG_DIR=$W/log CROSS_SITE_OFF=$W/log/sin-barrera DOCKER_WEB_DIR=$W/web cross_site_command no > /dev/null
    check "Linux: al apagarla, el Apache de Docker se rehace y se recarga" '[ "$(cat "$W/docker")" = recargado ] && [ -e "$W/log/sin-barrera" ]'
    DRY=0 LOG_DIR=$W/log CROSS_SITE_OFF=$W/log/sin-barrera DOCKER_WEB_DIR=$W/web cross_site_command si > /dev/null
    check "Linux: al encenderla, también" '[ "$(grep -c recargado "$W/docker")" = 2 ] && [ ! -e "$W/log/sin-barrera" ]'
    rm -f "$W/docker"
    DRY=0 LOG_DIR=$W/log CROSS_SITE_OFF=$W/log/sin-barrera DOCKER_WEB_DIR=$W/sin-docker cross_site_command no > /dev/null
    check "Linux: sin Apache de Docker, no se toca Docker" '[ ! -e "$W/docker" ]'
fi
exit $fail
