#!/bin/bash
# Pruebas de la pestaña Docker (1.53.0) con un docker falso (sin Docker de verdad ni red): nombres
# cortos, gui-docker, la configuracion del proyecto que se sustituye en el contenedor (WordPress,
# PrestaShop 1.7 y 1.6) sin tocar la del proyecto, el compose.yaml, el vhost (pasa VHOSTS_CHECK_PY),
# las comprobaciones de docker-crear y borrar. Uso: docker.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-docker.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
grep -q '^function docker_create() {' "$SRC" || { echo "  ok    (sin pestaña Docker)"; exit 0; }
extract "$SRC" docker_sock docker_run_dir dk docker_ready docker_slug docker_valid_slug docker_conf docker_projects \
    docker_state gui_docker docker_php_image docker_project_config docker_vhost_block docker_apply_vhosts \
    docker_create docker_ps_domain docker_action docker_set_php db_valid_name valid_version_name || exit 1
# (1.54.1: docker en su sesion, con su carpeta de configuracion, y el php.ini con las mitigaciones)
for f in docker_config_dir php_85_or_later docker_fix_restart docker_fix_pma docker_update_image; do
    grep -q "^function $f() {" "$SRC" && { extract "$SRC" $f || exit 1; }
done
eval "$(sed -n "/^NO_TTY_PY='/,/^'\$/p" "$SRC")"
eval "$(sed -n '/^PHP_SECURE_INI=/,/^PHP_SECURE_INI_85=/p; /^DOCKER_EXT_INSTALLER=/p' "$SRC")"
eval "$(sed -n '/^DOCKER_PHP_VERSIONS=/p; /^DOCKER_MARIADB_VERSIONS=/p; /^DOCKER_PMA_IMAGE=/p; /^DOCKER_PHP_EXT=/p; /^DOCKER_PMA_PORT=/p' "$SRC")"
eval "$(sed -n "/^VHOSTS_CHECK_PY='/,/^'\$/p" "$SRC")"
DB_SYSTEM="information_schema|mysql|performance_schema|phpmyadmin|sys|test"
DRY=0 HTDOCS_DIR=$W/htdocs DOCKER_DIR=$W/docker LOG_DIR=$W/log HOSTS_FILE=$W/hosts OWN_SSL_DIR=/opt/config/ssl
PORT_HTTP=80 PORT_HTTPS=443 ACTIVE_VHOSTS=$W/vhosts.conf TEST_DIR=$W/v XDG_RUNTIME_DIR=$W/xdg
DOCKER_CONFIG_DIR=$W/log/docker-config
mkdir -p "$HTDOCS_DIR" "$LOG_DIR" "$TEST_DIR/lampp-8.4"
printf '127.0.0.1 localhost\n' > "$HOSTS_FILE"
printf '<VirtualHost *:80>\n    ServerName web.local\n    DocumentRoot "/opt/lampp/htdocs/web.local"\n</VirtualHost>\n' > "$ACTIVE_VHOSTS"
# docker falso: apunta lo que se le pide y contesta como Docker sin root
DOCKER_BIN=$W/docker-falso LVM_DOCKER_HOST=unix://$W/docker.sock
cat > "$DOCKER_BIN" << 'EOF'
#!/bin/bash
echo "$*" >> "$(dirname "$0")/docker.log"
case "$1" in
    info) echo '["name=seccomp,profile=builtin","name=rootless"]' ;;
    version) echo 29.1.3 ;;
    image) exit 1 ;;
    ps) if [[ "$*" == *"{{.Names}}"* ]]; then echo "nexum-mi-tienda-8-4-php-1|nexum-php:8.2|running|Up 2 minutes|9000/tcp|nexum-mi-tienda-8-4|3f2a9c1d7e6b"; elif [ -f "$(dirname "$0")/estado" ]; then cat "$(dirname "$0")/estado"; fi ;;
    compose) [[ "$*" == *" exec "* ]] && cat > /dev/null; exit 0 ;;
esac
exit 0
EOF
chmod +x "$DOCKER_BIN"
valid_project() { [ -d "$HTDOCS_DIR/$1" ] && [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9\ ._-]*$ ]]; }
valid_domain() { [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]; }
vhosts_info() { printf '80|web.local|web.local||\n'; }
lampp_running() { return 0; }
server_admin() { echo admin@localhost; }
make_selfsigned() { echo "$*" >> "$W/certs.log"; }
browser_trust() { :; }
edit_vhosts() { python3 -I -c "$VHOSTS_CHECK_PY" "$2" > "$W/vhosts-check.out" || return 1; cp "$2" "$ACTIVE_VHOSTS"; }
edit_hosts() { cp "$2" "$HOSTS_FILE"; }
export_database() { printf 'CREATE TABLE t (a INT);\n' | gzip > "$2"; }
db_temp_stop() { :; }
run() { "$@"; }

# --- Nombres cortos ---
check "nombre corto: carpeta con espacios y mayusculas" '[ "$(docker_slug "Mi Tienda 8.4")" == mi-tienda-8-4 ]'
check "nombre corto: sin letras validas, nada" '[ -z "$(docker_slug "___")" ]'
check "nombre corto valido" 'docker_valid_slug mi-tienda-8-4 && ! docker_valid_slug "-x" && ! docker_valid_slug "a/b"'

# --- Proyecto WordPress con su BBDD copiada ---
mkdir -p "$HTDOCS_DIR/Mi Tienda 8.4"
WP="$HTDOCS_DIR/Mi Tienda 8.4/wp-config.php"
printf "<?php\ndefine( 'DB_NAME', 'wp_t' );\ndefine( 'DB_USER', 'root' );\ndefine( 'DB_PASSWORD', '' );\ndefine( 'DB_HOST', 'localhost' );\ndefine('WP_HOME', 'https://web.local');\n\$table_prefix = 'wp_';\n" > "$WP"
cp "$WP" "$W/wp-antes"
out=$(docker_create "Mi Tienda 8.4" 7.4 10.11 --bd wp_t --desde 8.4 2>&1); rc=$?
D=$DOCKER_DIR/mi-tienda-8-4
check "docker-crear: termina bien" '[ $rc -eq 0 ] && grep -q "listo: https://mi-tienda-8-4.docker.local" <<< "$out"'
check "carpetas solo tuyas" '[ "$(stat -c %a "$DOCKER_DIR")" == 700 ] && [ "$(stat -c %a "$D")" == 700 ] && [ "$(stat -c %a "$D/.env")" == 600 ]'
check "contraseñas al azar en .env (no en compose.yaml)" 'grep -qE "^DB_ROOT_PASS=.{20,}$" "$D/.env" && ! grep -q "$(sed -n "s/^DB_PASS=//p" "$D/.env")" "$D/compose.yaml"'
check "wp-config.php del proyecto sin tocar" 'cmp -s "$WP" "$W/wp-antes"'
check "config del contenedor: BBDD del contenedor" 'grep -q "'"'"'DB_HOST'"'"', '"'"'db'"'"'" "$D/config.php" && grep -q "'"'"'DB_USER'"'"', '"'"'nexum'"'"'" "$D/config.php" && grep -q "'"'"'DB_NAME'"'"', '"'"'wp_t'"'"'" "$D/config.php"'
check "config del contenedor: dominio de Docker y sin el WP_HOME de antes" 'grep -q "https://mi-tienda-8-4.docker.local" "$D/config.php" && ! grep -q "https://web.local" "$D/config.php"'
check "config del contenedor: PHP valido" '! command -v php > /dev/null || php -l "$D/config.php" > /dev/null'
check "compose: la carpeta en la misma ruta que ve Apache" 'grep -qF "\"$HTDOCS_DIR/Mi Tienda 8.4:/opt/lampp/htdocs/Mi Tienda 8.4\"" "$D/compose.yaml"'
check "compose: wp-config sustituido solo en el contenedor y de solo lectura" 'grep -qF "./config.php:/opt/lampp/htdocs/Mi Tienda 8.4/wp-config.php:ro" "$D/compose.yaml"'
check "compose: phpMyAdmin solo en 127.0.0.1" 'grep -qE "\"127\.0\.0\.1:$(sed -n "s/^PUERTO_PMA=//p" "$D/proyecto.conf"):80\"" "$D/compose.yaml" && ! grep -qE "\"[0-9]+:[0-9]+\"" "$D/compose.yaml"'
check "compose: YAML valido" 'python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$D/compose.yaml" 2> /dev/null || ! python3 -c "import yaml" 2> /dev/null'
check "docker siempre por el socket sin root" 'DOCKER_HOST= ; [ "$(docker_sock)" == "unix://$W/docker.sock" ]'
check "imagen de PHP: oficial, FPM por socket y como el root del contenedor" 'grep -q "^FROM php:7.4-fpm$" "$DOCKER_DIR/imagenes/php-7.4/Dockerfile" && grep -q "listen = /run/nexum/php.sock" "$DOCKER_DIR/imagenes/php-7.4/Dockerfile" && grep -q "php-fpm\", \"-R\"" "$DOCKER_DIR/imagenes/php-7.4/Dockerfile"'
# (1.54.1: la contraseña no va en la orden, que se ve en ps: el cliente la toma en el contenedor)
check "BBDD copiada al contenedor" 'grep -q "exec -T db sh -c MYSQL_PWD=\$MARIADB_ROOT_PASSWORD .*--binary-mode" "$W/docker.log"'
check "ninguna contraseña en las ordenes de docker" '! grep -qF "$(sed -n "s/^DB_ROOT_PASS=//p" "$W/docker/mi-tienda-8-4/.env")" "$W/docker.log"'
check "vhost añadido y aceptado por VHOSTS_CHECK_PY" 'grep -q "^# nexum-docker mi-tienda-8-4:" "$ACTIVE_VHOSTS" && grep -qF "proxy:unix:$W/xdg/nexum/mi-tienda-8-4/php.sock|fcgi://nexum-mi-tienda-8-4" "$ACTIVE_VHOSTS"'
check "socket en una carpeta solo tuya y montada en el contenedor" '[ "$(stat -c %a "$W/xdg/nexum/mi-tienda-8-4")" == 700 ] && grep -qF "\"$W/xdg/nexum/mi-tienda-8-4:/run/nexum\"" "$D/compose.yaml"'
check "socket con ruta demasiado larga: no" 'mkdir -p "$HTDOCS_DIR/corta"; ! XDG_RUNTIME_DIR=$W/$(printf "x%.0s" {1..90}) docker_create corta 8.1 10.11 > /dev/null 2>&1' 
check "vhost con https y su certificado" 'grep -q "SSLCertificateFile \"/opt/config/ssl/mi-tienda-8-4.docker.local-selfsigned.crt\"" "$ACTIVE_VHOSTS"'
check "linea en hosts" 'grep -qx "127.0.0.1 mi-tienda-8-4.docker.local" "$HOSTS_FILE"'
printf 'running\nrunning\nexited\n' > "$W/estado"
out=$(gui_docker)
check "gui-docker: instalado y sin root" 'grep -qE "^S\|1\|1\|29.1.3\|1\|[01]$" <<< "$out"'
check "gui-docker: el proyecto, a medias" 'grep -qx "P|mi-tienda-8-4|Mi Tienda 8.4|7.4|10.11|mi-tienda-8-4.docker.local|parcial|wp_t|$(sed -n "s/^PUERTO_PMA=//p" "$D/proyecto.conf")" <<< "$out"'
check "docker-crear dos veces la misma carpeta: no" '! docker_create "Mi Tienda 8.4" 8.4 11.8 > /dev/null 2>&1'
check "la misma carpeta con otro nombre (otra version de PHP): si" 'docker_create "Mi Tienda 8.4" 8.2 10.11 --nombre mi-tienda-8-4-php82 --dominio mi-tienda-8-4-php82.docker.local > /dev/null 2>&1 && [ -f "$DOCKER_DIR/mi-tienda-8-4-php82/compose.yaml" ]'
check "--nombre no valido: no" '! docker_create "Mi Tienda 8.4" 8.1 10.11 --nombre "Mal_Nombre" > /dev/null 2>&1 && [ ! -e "$DOCKER_DIR/Mal_Nombre" ]'

# --- PrestaShop 1.7 y 1.6 ---
mkdir -p "$HTDOCS_DIR/ps17/app/config" "$HTDOCS_DIR/ps16/config"
printf "<?php return array (\n  'parameters' =>\n  array (\n    'database_host' => '127.0.0.1',\n    'database_port' => '',\n    'database_name' => 'ps_x',\n    'database_user' => 'root',\n    'database_password' => '',\n    'database_prefix' => 'ps_',\n  ),\n);\n" > "$HTDOCS_DIR/ps17/app/config/parameters.php"
printf "<?php\ndefine('_DB_SERVER_', 'localhost');\ndefine('_DB_NAME_', 'ps_y');\ndefine('_DB_USER_', 'root');\ndefine('_DB_PASSWD_', '');\n" > "$HTDOCS_DIR/ps16/config/settings.inc.php"
docker_create ps17 8.1 10.11 > /dev/null 2>&1
check "PrestaShop 1.7: parameters.php del contenedor" 'grep -q "'"'"'database_host'"'"' => '"'"'db'"'"'" "$DOCKER_DIR/ps17/config.php" && grep -qF "./config.php:/opt/lampp/htdocs/ps17/app/config/parameters.php:ro" "$DOCKER_DIR/ps17/compose.yaml"'
docker_create ps16 5.6 10.4 > /dev/null 2>&1
check "PrestaShop 1.6: settings.inc.php del contenedor" 'grep -q "_DB_SERVER_'"'"', '"'"'db'"'"'" "$DOCKER_DIR/ps16/config.php"'
check "el puerto de phpMyAdmin no se repite" '[ "$(cat "$DOCKER_DIR"/*/proyecto.conf | grep -c "^PUERTO_PMA=")" == "$(cat "$DOCKER_DIR"/*/proyecto.conf | grep "^PUERTO_PMA=" | sort -u | wc -l)" ]'

# --- Lo que se rechaza ---
check "version de PHP que no se ofrece: no" '! docker_create ps17 6.0 10.11 > /dev/null 2>&1'
check "MariaDB que no se ofrece: no" '! docker_create ps17 8.1 9.9 > /dev/null 2>&1'
check "dominio que no es .local: no" 'mkdir -p "$HTDOCS_DIR/otra"; ! docker_create otra 8.1 10.11 --dominio google.com > /dev/null 2>&1 && [ ! -e "$DOCKER_DIR/otra" ]'
check "base rara: no" '! docker_create otra 8.1 10.11 --bd "a;b" --desde 8.4 > /dev/null 2>&1'
check "--bd sin --desde: no" '! docker_create otra 8.1 10.11 --bd wp_t > /dev/null 2>&1'
check "carpeta que no existe: no" '! docker_create nada 8.1 10.11 > /dev/null 2>&1'
check "opcion desconocida: no" '! docker_create otra 8.1 10.11 --raro x > /dev/null 2>&1'
check "nombre de proyecto raro en las acciones: no" '! docker_action parar "../x" > /dev/null 2>&1'

# --- Cambiar la version de PHP ---
: > "$W/docker.log"
check "docker-php: cambia la imagen de PHP y nada mas" 'docker_set_php mi-tienda-8-4 8.2 > /dev/null 2>&1 && grep -qx "    image: nexum-php:8.2" "$D/compose.yaml" && grep -qx "PHP=8.2" "$D/proyecto.conf" && grep -q "image: mariadb:10.11" "$D/compose.yaml"'
check "docker-php: prepara la imagen y recrea solo el contenedor de PHP" 'grep -q "^build -t nexum-php:8.2" "$W/docker.log" && grep -q "compose .* up -d php$" "$W/docker.log"'
check "docker-php: la misma version, no hace nada" 'out=$(docker_set_php mi-tienda-8-4 8.2) && grep -q "ya usa PHP 8.2" <<< "$out"'
check "docker-php: version que no se ofrece, no" '! docker_set_php mi-tienda-8-4 6.0 > /dev/null 2>&1 && grep -qx "PHP=8.2" "$D/proyecto.conf"'
check "docker-php: proyecto que no existe, no" '! docker_set_php "../x" 8.1 > /dev/null 2>&1'
cp "$DOCKER_BIN" "$W/docker-bueno"
printf '#!/bin/bash\necho "$*" >> "$(dirname "$0")/docker.log"\ncase "$1" in info) echo rootless ;; image) exit 1 ;; compose) [[ "$*" == *" up -d php" ]] && ! grep -q "nexum-php:8.2" "%s" && exit 1; exit 0 ;; esac\nexit 0\n' "$D/compose.yaml" > "$DOCKER_BIN"
check "docker-php: si no arranca, vuelve a la de antes" '! docker_set_php mi-tienda-8-4 5.6 > /dev/null 2>&1 && grep -qx "    image: nexum-php:8.2" "$D/compose.yaml" && grep -qx "PHP=8.2" "$D/proyecto.conf"'
cp "$W/docker-bueno" "$DOCKER_BIN"
out=$(gui_docker)
check "gui-docker: contenedores para la consola (C|)" 'grep -q "^C|" <<< "$out" || ! grep -q "{{.Label" "$SRC"'

# --- Borrar ---
docker_action borrar mi-tienda-8-4 > /dev/null 2>&1
check "borrar: contenedores y su BBDD (down -v)" 'grep -q "compose .* down -v" "$W/docker.log"'
# (solo los suyos: el de mi-tienda-8-4-php82, la misma carpeta con otro PHP, se queda)
check "borrar: sin su vhost, con los demas" '! grep -qE "mi-tienda-8-4(:|\.docker\.local)" "$ACTIVE_VHOSTS" && grep -q "ServerName web.local" "$ACTIVE_VHOSTS"'
check "borrar: sin su linea en hosts" '! grep -q "mi-tienda-8-4\.docker\.local" "$HOSTS_FILE" && grep -q localhost "$HOSTS_FILE"'
check "borrar: su carpeta y la del socket, fuera; la del proyecto, no" '[ ! -e "$D" ] && [ ! -e "$W/xdg/nexum/mi-tienda-8-4" ] && [ -f "$WP" ]'
printf "<?php\ndefine('DB_NAME','x');define('DB_USER','root');define('DB_PASSWORD','');define('DB_HOST','localhost');\n" > "$W/linea.php"
mkdir -p "$HTDOCS_DIR/linea"; cp "$W/linea.php" "$HTDOCS_DIR/linea/wp-config.php"; mkdir -p "$W/cfg"
docker_project_config linea "$W/cfg" l.docker.local base nexum clave > /dev/null
check "config: varios define en la misma linea, todos cambiados" 'grep -qF "define('"'"'DB_NAME'"'"','"'"'base'"'"');define('"'"'DB_USER'"'"','"'"'nexum'"'"');define('"'"'DB_PASSWORD'"'"','"'"'clave'"'"');define('"'"'DB_HOST'"'"','"'"'db'"'"');" "$W/cfg/config.php" && [ "$(grep -c "DB_USER" "$W/cfg/config.php")" == 1 ]'
printf "<?php\n// define('DB_HOST', 'viejo');\ndefine('DB_HOST', 'localhost');\n" > "$HTDOCS_DIR/linea/wp-config.php"
docker_project_config linea "$W/cfg" l.docker.local base nexum clave > /dev/null
check "config: un define comentado no se toca" 'grep -qF "// define('"'"'DB_HOST'"'"', '"'"'viejo'"'"');" "$W/cfg/config.php" && grep -qF "define('"'"'DB_HOST'"'"', '"'"'db'"'"');" "$W/cfg/config.php"'
# --- Imagenes y volumenes (1.54.2): borrar y volver a descargar, con nombres comprobados ---
eval "$(sed -n '/^function docker_image_action() {/,/^}/p; /^function docker_volume_remove() {/,/^}/p' "$SRC")"
: > "$W/docker.log"
check "imagenes: borrar por ID" 'docker_image_action borrar 3f2a9c1d7e6b > /dev/null 2>&1; grep -q "image rm 3f2a9c1d7e6b" "$W/docker.log"'
check "imagenes: borrar por imagen:etiqueta" 'docker_image_action borrar php:8.2-fpm > /dev/null 2>&1; grep -q "image rm php:8.2-fpm" "$W/docker.log"'
check "imagenes: borrar algo raro, no" '! docker_image_action borrar "-f x" > /dev/null 2>&1 && ! docker_image_action borrar "a;b" > /dev/null 2>&1'
check "imagenes: borrar sin -f (si la usa un contenedor, Docker no la borra)" '! grep -q "image rm -f" "$W/docker.log"'
check "imagenes: descargar" 'docker_image_action descargar mariadb:11.8 > /dev/null 2>&1 && grep -q "pull mariadb:11.8" "$W/docker.log"'
check "imagenes: las del gestor no se descargan" '! docker_image_action descargar nexum-php:8.2 > /dev/null 2>&1 && ! grep -q "pull nexum-php" "$W/docker.log"'
check "volumenes: borrar" 'docker_volume_remove nexum-mi-tienda-8-4_db > /dev/null 2>&1 && grep -q "volume rm nexum-mi-tienda-8-4_db" "$W/docker.log"'
check "volumenes: nombre raro, no" '! docker_volume_remove "../x" > /dev/null 2>&1 && ! docker_volume_remove "-f" > /dev/null 2>&1'
check "gui-docker: imagenes con etiqueta e ID" 'grep -qF "{{.Repository}}|{{.Tag}}|{{.ID}}|{{.Size}}|{{.CreatedSince}}" "$SRC"'
exit $fail
