#!/bin/bash
# Pruebas de Docker en el Mac (1.39.0; 1.39.2: web del contenedor con clave) con un docker falso (sin
# Docker Desktop ni red): nombres cortos, gui-docker, la configuracion del proyecto que se sustituye en
# el contenedor sin tocar la del proyecto, el compose.yaml (la web del contenedor en 127.0.0.1, un
# puerto por proyecto, sin PHP-FPM publicado), el vhost con su clave (pasa VHOSTS_CHECK_PY), los
# proyectos de antes que pasan a la web con clave, cambiar de PHP sin sed -i, borrar, --nombre y las
# comprobaciones de docker-crear; 1.39.4: borrar y volver a descargar imagenes, y borrar volumenes.
# Uso: mac-docker.sh <macos/lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-mac-docker.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
grep -q '^function docker_create() {' "$SRC" || { echo "  ok    (sin Docker)"; exit 0; }
extract "$SRC" docker_bin docker_sock dk docker_ready docker_slug docker_valid_slug docker_conf docker_sed \
    docker_projects docker_port_used docker_free_port docker_state gui_docker gui_docker_stats \
    docker_container_action docker_set_php docker_install docker_php_image docker_project_config \
    docker_vhost_block docker_apply_vhosts docker_create docker_ps_domain docker_action db_valid_name \
    valid_version_name docker_web_rules docker_compose_file docker_sql docker_migrate docker_unmigrated \
    docker_migrate_command docker_update_image docker_db_password docker_image_action docker_volume_remove \
    docker_config_dir || exit 1
eval "$(sed -n '/^DOCKER_PHP_VERSIONS=/p; /^DOCKER_MARIADB_VERSIONS=/p; /^DOCKER_PMA_IMAGE=/p; /^DOCKER_PHP_EXT=/p; /^DOCKER_PMA_PORT=/p; /^DOCKER_WEB_PORT=/p; /^DOCKER_KEYS_DIR=/p; /^DOCKER_IMAGE_SCHEMA=/p; /^DOCKER_DOWNLOAD_URL=/p' "$SRC")"
eval "$(sed -n "/^VHOSTS_CHECK_PY='/,/^'\$/p" "$SRC")"
eval "$(sed -n "/^UNKNOWN_HOST_VHOST='/,/^'\$/p; /^PHP_SECURITY_INI='/,/^'\$/p; /^PHP_SECURITY_INI_85='/,/^'\$/p" "$SRC")"
DB_SYSTEM="information_schema|mysql|performance_schema|phpmyadmin|sys|test"
DRY=0 HTDOCS_DIR=$W/htdocs DOCKER_DIR=$W/docker LOG_DIR=$W/log HOSTS_FILE=$W/hosts OWN_SSL_DIR=/Library/Nexum/XAMPP-compartido/ssl
PORT_HTTP=80 PORT_HTTPS=443 ACTIVE_VHOSTS=$W/vhosts.conf BASE_DIR=$W/apps LINK=/Applications/XAMPP
DOCKER_APP=$W/Docker.app
DOCKER_CONFIG_DIR=$W/log/docker-config
mkdir -p "$HTDOCS_DIR" "$LOG_DIR" "$BASE_DIR/XAMPP-8.4"
printf '127.0.0.1 localhost\n' > "$HOSTS_FILE"
printf '<VirtualHost *:80>\n    ServerName web.local\n    DocumentRoot "/Applications/XAMPP/xamppfiles/htdocs/web.local"\n</VirtualHost>\n' > "$ACTIVE_VHOSTS"
# docker falso: apunta lo que se le pide y contesta como Docker Desktop
LVM_DOCKER=$W/docker-falso LVM_DOCKER_HOST=unix://$W/docker.sock
cat > "$LVM_DOCKER" << 'EOF'
#!/bin/bash
echo "$*" >> "$(dirname "$0")/docker.log"
case "$1" in
    info) [[ "$*" == *NCPU* ]] && echo "8|8217473024" || echo 28.5.1 ;;
    version) echo 28.5.1 ;;
    image) exit 1 ;;
    images) printf 'nexum-php|8.2|3f2a9c1d7e6b|512MB|2 hours ago\nmala|linea\n<none>|<none>|zz|1MB|1 day ago\n' ;;
    stats) echo "nexum-mi-tienda-8-4-php-1|1.25%|50.5MiB / 7.6GiB" ;;
    ps) if [[ "$*" == *"{{.Names}}"* ]]; then echo "nexum-mi-tienda-8-4-php-1|nexum-php:8.2|running|Up 2 minutes|127.0.0.1:29000->9000/tcp|nexum-mi-tienda-8-4|3f9a2c4b7d1e"; elif [ -f "$(dirname "$0")/estado" ]; then cat "$(dirname "$0")/estado"; fi ;;
    compose) [[ "$*" == *" exec "* ]] && cat > /dev/null; exit 0 ;;
esac
exit 0
EOF
chmod +x "$LVM_DOCKER"
valid_project() { [ -d "$HTDOCS_DIR/$1" ] && [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9\ ._-]*$ ]]; }
valid_domain() { [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]; }
vhosts_info() { printf '80|web.local|web.local||\n'; }
lampp_running() { return 0; }
server_admin() { echo admin@localhost; }
realpath_f() { readlink -f "$1"; }
make_selfsigned() { echo "$*" >> "$W/certs.log"; }
browser_trust() { :; }
edit_vhosts() { python3 -I -c "$VHOSTS_CHECK_PY" "$2" > "$W/vhosts-check.out" || return 1; cp "$2" "$ACTIVE_VHOSTS"; }
edit_hosts() { cp "$2" "$HOSTS_FILE"; }
export_database() { printf 'CREATE TABLE t (a INT);\n' | gzip > "$2"; }
# (la clave de cada proyecto la escribe root: aqui, en un fichero de la prueba)
docker_write_key() { printf '%s %s\n' "$1" "$2" >> "$W/claves"; }
docker_remove_key() { echo "$1" >> "$W/claves-quitadas"; }
db_temp_stop() { :; }
run() { "$@"; }

# --- Docker Desktop ---
check "docker: el de LVM_DOCKER (pruebas)" '[ "$(docker_bin)" == "$LVM_DOCKER" ]'
check "socket: el de LVM_DOCKER_HOST (pruebas)" '[ "$(docker_sock)" == "unix://$W/docker.sock" ]'
check "socket de Docker Desktop: el de tu usuario o /var/run" 'out=$(LVM_DOCKER_HOST= HOME=$W docker_sock) && [ "$out" == unix:///var/run/docker.sock ]'
check "Docker Desktop responde" 'docker_ready'
check "sin docker: no responde" '! LVM_DOCKER=$W/no-esta docker_ready'
check "docker-instalar sin Docker Desktop: abre la descarga, no instala nada" 'out=$(LVM_DOCKER=$W/no-esta; run() { echo "RUN $*"; }; docker_install) && grep -q "RUN open $DOCKER_DOWNLOAD_URL" <<< "$out" && ! grep -qi "sudo\|brew" <<< "$out"'

# --- Nombres cortos ---
check "nombre corto: carpeta con espacios y mayusculas" '[ "$(docker_slug "Mi Tienda 8.4")" == mi-tienda-8-4 ]'
check "nombre corto valido" 'docker_valid_slug mi-tienda-8-4 && ! docker_valid_slug "-x" && ! docker_valid_slug "a/b"'

# --- Proyecto WordPress con su BBDD copiada ---
mkdir -p "$HTDOCS_DIR/Mi Tienda 8.4"
WP="$HTDOCS_DIR/Mi Tienda 8.4/wp-config.php"
printf "<?php\ndefine( 'DB_NAME', 'wp_t' );\ndefine( 'DB_USER', 'root' );\ndefine( 'DB_PASSWORD', '' );\ndefine( 'DB_HOST', 'localhost' );\ndefine('WP_HOME', 'https://web.local');\n\$table_prefix = 'wp_';\n" > "$WP"
cp "$WP" "$W/wp-antes"
out=$(docker_create "Mi Tienda 8.4" 7.4 10.11 --bd wp_t --desde 8.4 2>&1); rc=$?
D=$DOCKER_DIR/mi-tienda-8-4
FPM=$(sed -n 's/^PUERTO_WEB=//p' "$D/proyecto.conf")
KEY=$(sed -n 's/^WEB_KEY=//p' "$D/.env")
check "docker-crear: termina bien" '[ $rc -eq 0 ] && grep -q "listo: https://mi-tienda-8-4.docker.local" <<< "$out"'
check "carpetas solo tuyas" '[ "$(stat -c %a "$DOCKER_DIR")" == 700 ] && [ "$(stat -c %a "$D")" == 700 ] && [ "$(stat -c %a "$D/.env")" == 600 ]'
check "contraseñas al azar en .env (no en compose.yaml)" 'grep -qE "^DB_ROOT_PASS=.{20,}$" "$D/.env" && ! grep -q "$(sed -n "s/^DB_PASS=//p" "$D/.env")" "$D/compose.yaml"'
check "wp-config.php del proyecto sin tocar" 'cmp -s "$WP" "$W/wp-antes"'
check "config del contenedor: BBDD del contenedor y dominio de Docker" 'grep -q "'"'"'DB_HOST'"'"', '"'"'db'"'"'" "$D/config.php" && grep -q "https://mi-tienda-8-4.docker.local" "$D/config.php" && ! grep -q "https://web.local" "$D/config.php"'
check "compose: la carpeta en la misma ruta que ve Apache (/Applications/XAMPP)" 'grep -qF "\"$HTDOCS_DIR/Mi Tienda 8.4:/Applications/XAMPP/xamppfiles/htdocs/Mi Tienda 8.4\"" "$D/compose.yaml"'
check "compose: wp-config sustituido solo en el contenedor y de solo lectura" 'grep -qF "./config.php:/Applications/XAMPP/xamppfiles/htdocs/Mi Tienda 8.4/wp-config.php:ro" "$D/compose.yaml"'
check "compose: la web del contenedor, solo en 127.0.0.1 y en su puerto; sin PHP-FPM publicado" '[ "$FPM" == "$DOCKER_WEB_PORT" ] && grep -qF "\"127.0.0.1:$FPM:80\"" "$D/compose.yaml" && ! grep -q ":9000" "$D/compose.yaml"'
check "compose: la clave del proyecto (de .env), su dominio y su carpeta para el Apache del contenedor" 'grep -qF "NEXUM_KEY: \${WEB_KEY}" "$D/compose.yaml" && [ ${#KEY} -ge 30 ] && ! grep -qF "$KEY" "$D/compose.yaml" && grep -qF "NEXUM_DOMAIN: \"mi-tienda-8-4.docker.local\"" "$D/compose.yaml" && grep -qF "NEXUM_ROOT: \"/Applications/XAMPP/xamppfiles/htdocs/Mi Tienda 8.4\"" "$D/compose.yaml"'
check "compose: phpMyAdmin sin entrar solo como root" '! grep -q "PMA_USER\|PMA_PASSWORD" "$D/compose.yaml" && grep -q "PMA_HOST: db" "$D/compose.yaml"'
check "proyecto.conf: esquema 2 y su configuracion sustituida" 'grep -qx "ESQUEMA=$DOCKER_IMAGE_SCHEMA" "$D/proyecto.conf" && grep -qx "CONFIG=wp-config.php" "$D/proyecto.conf"'
check "clave para el Apache del Mac: la de .env" 'grep -qx "mi-tienda-8-4 $KEY" "$W/claves"'
check "compose: phpMyAdmin solo en 127.0.0.1" 'grep -qE "\"127\.0\.0\.1:$(sed -n "s/^PUERTO_PMA=//p" "$D/proyecto.conf"):80\"" "$D/compose.yaml" && ! grep -qE "\"[0-9]+:[0-9]+\"" "$D/compose.yaml"'
check "compose: no arrancan solos" '[ "$(grep -c "restart: \"no\"" "$D/compose.yaml")" == 3 ] && ! grep -q unless-stopped "$D/compose.yaml"'
check "compose: YAML valido" 'python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$D/compose.yaml" 2> /dev/null || ! python3 -c "import yaml" 2> /dev/null'
I=$DOCKER_DIR/imagenes/php-7.4
check "imagen de PHP: oficial con Apache (sin PHP-FPM ni root), php.ini de produccion" 'grep -q "^FROM php:7.4-apache$" "$I/Dockerfile" && ! grep -qi "fpm\|user = root" "$I/Dockerfile" && grep -q "php.ini-production" "$I/Dockerfile" && grep -q "LABEL nexum.esquema=\"$DOCKER_IMAGE_SCHEMA\"" "$I/Dockerfile"'
check "imagen de PHP: sin la clave no arranca" 'grep -qF "[ \${#NEXUM_KEY} -ge 20 ] ||" "$I/Dockerfile"'
check "web del contenedor: 403 sin la clave o con otro dominio, y PHP no la ve" 'grep -qF "RewriteCond \"%{HTTP:X-Nexum-Key}\" \"!=\${NEXUM_KEY}\"" "$I/nexum-web.conf" && grep -qF "RewriteCond \"%{HTTP_HOST}\" \"!=\${NEXUM_DOMAIN}\" [NC]" "$I/nexum-web.conf" && [ "$(grep -c "RewriteRule \"^\" \"-\" \[F\]" "$I/nexum-web.conf")" == 2 ] && grep -q "RequestHeader unset X-Nexum-Key" "$I/nexum-web.conf"'
check "web del contenedor: .htaccess y las reglas de .env, .git y copias" 'grep -q "AllowOverride All" "$I/nexum-web.conf" && grep -q "^<FilesMatch \"(?i)(^\\\\.(env" "$I/nexum-web.conf" && grep -q "^</FilesMatch>" "$I/nexum-web.conf" && grep -q "LimitRequestBody 67108864" "$I/nexum-web.conf"'
check "php.ini del contenedor: contra PHP2Shell" 'grep -qx "session.upload_progress.enabled = Off" "$I/nexum.ini" && grep -qx "max_input_nesting_level = 6" "$I/nexum.ini" && grep -qx "post_max_size = 64M" "$I/nexum.ini" && grep -qx "expose_php = Off" "$I/nexum.ini" && ! grep -q fatal_error_backtraces "$I/nexum.ini"'
check "imagen de PHP 8.5: tambien sin las trazas de los errores fatales" 'docker_php_image 8.5 > /dev/null 2>&1; grep -qx "fatal_error_backtraces = 0" "$DOCKER_DIR/imagenes/php-8.5/nexum.ini"'
check "BBDD copiada al contenedor, sin la contraseña en la orden (ps)" 'grep -q "exec -T db sh -c MYSQL_PWD=\$MARIADB_ROOT_PASSWORD; export MYSQL_PWD; .*--binary-mode" "$W/docker.log" && ! grep -qF "$(sed -n "s/^DB_ROOT_PASS=//p" "$D/.env")" "$W/docker.log"'
check "vhost añadido, a la web del contenedor, y aceptado por VHOSTS_CHECK_PY" 'grep -q "^# nexum-docker mi-tienda-8-4:" "$ACTIVE_VHOSTS" && grep -qF "ProxyPass \"/\" \"http://127.0.0.1:$FPM/\"" "$ACTIVE_VHOSTS" && grep -q "ProxyPreserveHost On" "$ACTIVE_VHOSTS" && ! grep -q "proxy:fcgi" "$ACTIVE_VHOSTS" && grep -qF "DocumentRoot \"/Applications/XAMPP/xamppfiles/htdocs/Mi Tienda 8.4\"" "$ACTIVE_VHOSTS"'
check "vhost: la clave por un Include de root, no en los vhosts" '[ "$(grep -cF "Include \"$DOCKER_KEYS_DIR/mi-tienda-8-4.conf\"" "$ACTIVE_VHOSTS")" == 2 ] && ! grep -qF "$KEY" "$ACTIVE_VHOSTS"'
printf '<VirtualHost *:80>\n    ServerName x.local\n    Include "/etc/apache2/otro.conf"\n</VirtualHost>\n' > "$W/vh-mal"
printf '<VirtualHost *:80>\n    ServerName x.local\n    Include "/Library/Nexum/XAMPP-compartido/docker-claves/../../etc/x.conf"\n</VirtualHost>\n' > "$W/vh-mal2"
check "VHOSTS_CHECK_PY: otro Include no se admite" '! python3 -I -c "$VHOSTS_CHECK_PY" "$W/vh-mal" > /dev/null && ! python3 -I -c "$VHOSTS_CHECK_PY" "$W/vh-mal2" > /dev/null'
check "vhost con https y su certificado" 'grep -q "SSLCertificateFile \"/Library/Nexum/XAMPP-compartido/ssl/mi-tienda-8-4.docker.local-selfsigned.crt\"" "$ACTIVE_VHOSTS"'
check "linea en hosts" 'grep -qx "127.0.0.1 mi-tienda-8-4.docker.local" "$HOSTS_FILE"'
printf 'running\nrunning\nexited\n' > "$W/estado"
out=$(gui_docker)
check "gui-docker: instalado y en marcha (sin la aplicacion)" 'grep -qx "S|1|1|28.5.1|1|0" <<< "$out"'
check "gui-docker: el proyecto, a medias, con sus puertos (y ya con clave)" 'grep -qx "P|mi-tienda-8-4|Mi Tienda 8.4|7.4|10.11|mi-tienda-8-4.docker.local|parcial|wp_t|$(sed -n "s/^PUERTO_PMA=//p" "$D/proyecto.conf")|$FPM|0" <<< "$out"'
check "docker-clave: usuario y contraseña de su phpMyAdmin" '[ "$(docker_db_password mi-tienda-8-4)" == "K|root|$(sed -n "s/^DB_ROOT_PASS=//p" "$D/.env")|http://127.0.0.1:$(sed -n "s/^PUERTO_PMA=//p" "$D/proyecto.conf")/" ] && ! docker_db_password "../x" > /dev/null 2>&1'
check "gui-docker: contenedores para la tabla (C|)" 'grep -q "^C|nexum-mi-tienda-8-4-php-1|" <<< "$out"'
check "gui-docker: el ID corto de cada contenedor, al final de su C|" 'grep -q "^C|nexum-mi-tienda-8-4-php-1|.*|nexum-mi-tienda-8-4|3f9a2c4b7d1e\$" <<< "$out"'
out=$(gui_docker_stats)
check "gui-docker-estadisticas: nucleos y memoria de Docker Desktop, CPU por contenedor" 'grep -qx "T|8|8217473024" <<< "$out" && grep -q "^K|nexum-mi-tienda-8-4-php-1|1.25%|" <<< "$out"'
check "docker-crear dos veces la misma carpeta: no" '! docker_create "Mi Tienda 8.4" 8.4 11.8 > /dev/null 2>&1'

# --- Segundo proyecto: otros puertos ---
mkdir -p "$HTDOCS_DIR/ps17/app/config"
printf "<?php return array (\n  'parameters' =>\n  array (\n    'database_host' => '127.0.0.1',\n    'database_name' => 'ps_x',\n    'database_user' => 'root',\n    'database_password' => '',\n  ),\n);\n" > "$HTDOCS_DIR/ps17/app/config/parameters.php"
docker_create ps17 8.1 10.11 > /dev/null 2>&1
check "PrestaShop 1.7: parameters.php del contenedor" 'grep -q "'"'"'database_host'"'"' => '"'"'db'"'"'" "$DOCKER_DIR/ps17/config.php"'
check "los puertos de la web y de phpMyAdmin no se repiten" '[ "$(sed -n "s/^PUERTO_WEB=//p" "$DOCKER_DIR/ps17/proyecto.conf")" != "$FPM" ] && [ "$(sed -n "s/^PUERTO_PMA=//p" "$DOCKER_DIR/ps17/proyecto.conf")" != "$(sed -n "s/^PUERTO_PMA=//p" "$D/proyecto.conf")" ]'
python3 -c 'import socket, time, sys
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", 0)); s.listen(1)
print(s.getsockname()[1], flush=True); time.sleep(5)' > "$W/puerto" &
for i in $(seq 20); do [ -s "$W/puerto" ] && break; sleep 0.1; done
P=$(cat "$W/puerto")
check "puerto ocupado por otro programa: se salta" '[ -n "$P" ] && docker_port_used "$P" && [ "$(docker_free_port "$P" PUERTO_WEB)" != "$P" ]'
check "--nombre: la misma carpeta con otro nombre (otra version de PHP)" 'docker_create "Mi Tienda 8.4" 8.2 10.11 --nombre mi-tienda-8-4-php82 --dominio mi-tienda-8-4-php82.docker.local > /dev/null 2>&1 && [ -f "$DOCKER_DIR/mi-tienda-8-4-php82/compose.yaml" ] && grep -qx "DOMINIO=mi-tienda-8-4-php82.docker.local" "$DOCKER_DIR/mi-tienda-8-4-php82/proyecto.conf"'
check "--nombre no valido: no" '! docker_create "Mi Tienda 8.4" 8.1 10.11 --nombre "Mal_Nombre" > /dev/null 2>&1 && [ ! -e "$DOCKER_DIR/Mal_Nombre" ]'
docker_action borrar mi-tienda-8-4-php82 > /dev/null 2>&1

# --- Un proyecto de la 1.39.1 (PHP-FPM publicado en 127.0.0.1, sin clave) pasa a la web con clave ---
O=$DOCKER_DIR/viejo
mkdir -p -m 700 "$O" "$HTDOCS_DIR/viejo"
printf 'DB_ROOT_PASS=raiz123456789012345678\nDB_PASS=app123\n' > "$O/.env"
printf 'CARPETA=viejo\nPHP=8.1\nMARIADB=10.11\nDOMINIO=viejo.docker.local\nBBDD=viejo\nPUERTO_PMA=28090\nPUERTO_FPM=29050\n' > "$O/proyecto.conf"
printf 'name: nexum-viejo\nservices:\n  php:\n    image: nexum-php:8.1\n    restart: "no"\n    ports:\n      - "127.0.0.1:29050:9000"\n    volumes:\n      - "%s:/Applications/XAMPP/xamppfiles/htdocs/viejo"\n      - "./config.php:/Applications/XAMPP/xamppfiles/htdocs/viejo/wp-config.php:ro"\n' "$HTDOCS_DIR/viejo" > "$O/compose.yaml"
{ cat "$ACTIVE_VHOSTS"; printf '\n# nexum-docker viejo: el PHP va en Docker (no se edita a mano: lo quita Docker, Borrar)\n<VirtualHost *:80>\n    ServerName viejo.docker.local\n    DocumentRoot "/Applications/XAMPP/xamppfiles/htdocs/viejo"\n    <FilesMatch "\\.php$">\n        SetHandler "proxy:fcgi://127.0.0.1:29050"\n    </FilesMatch>\n</VirtualHost>\n# /nexum-docker viejo\n'; } > "$W/vh" && cp "$W/vh" "$ACTIVE_VHOSTS"
check "gui-docker: el de antes sale como sin clave" 'gui_docker | grep -q "^P|viejo|viejo|8.1|10.11|viejo.docker.local|.*|29050|1$" && [ "$(docker_unmigrated)" == viejo ]'
: > "$W/docker.log"
docker_action arrancar viejo > "$W/mig.out" 2>&1; rc=$?
check "arrancar uno de antes: primero pasa a la web con clave" '[ $rc -eq 0 ] && grep -qx "ESQUEMA=$DOCKER_IMAGE_SCHEMA" "$O/proyecto.conf" && grep -qF "\"127.0.0.1:29050:80\"" "$O/compose.yaml" && ! grep -q ":9000" "$O/compose.yaml"'
check "migrado: el mismo puerto, su configuracion y su BBDD; contraseñas de antes" 'grep -qx "PUERTO_WEB=29050" "$O/proyecto.conf" && ! grep -q "^PUERTO_FPM=" "$O/proyecto.conf" && grep -qx "CONFIG=wp-config.php" "$O/proyecto.conf" && grep -q "db:/var/lib/mysql" "$O/compose.yaml" && grep -qx "DB_ROOT_PASS=raiz123456789012345678" "$O/.env" && grep -qE "^WEB_KEY=.{30,}$" "$O/.env"'
check "migrado: vhost a la web con su clave; los demas como estaban; lo de antes guardado" 'grep -qF "ProxyPass \"/\" \"http://127.0.0.1:29050/\"" "$ACTIVE_VHOSTS" && ! grep -q "proxy:fcgi://127.0.0.1:29050" "$ACTIVE_VHOSTS" && grep -q "ServerName web.local" "$ACTIVE_VHOSTS" && grep -q "nexum-docker ps17" "$ACTIVE_VHOSTS" && [ "$(grep -c "^# nexum-docker viejo:" "$ACTIVE_VHOSTS")" == 1 ] && grep -q ":9000" "$O/antes-esquema-2/compose.yaml"'
check "migrado: imagen nueva, contenedores de PHP y phpMyAdmin rehechos" 'grep -q "^build -t nexum-php:8.1" "$W/docker.log" && grep -q "compose .* rm -s -f php pma" "$W/docker.log" && grep -q "compose .* up -d$" "$W/docker.log" && grep -q "^viejo " "$W/claves"'
check "docker-migrar --todos: nada que hacer ya" 'docker_migrate_command --todos | grep -q "al dia"'
: > "$W/docker.log"
check "docker-imagen: --pull --no-cache y rehace solo el contenedor de PHP" 'printf "running\nrunning\nrunning\n" > "$W/estado"; docker_update_image viejo > /dev/null 2>&1 && grep -q "^build --pull --no-cache -t nexum-php:8.1" "$W/docker.log" && grep -q "compose .* up -d --force-recreate php$" "$W/docker.log"; rm -f "$W/estado"'

# --- Lo que se rechaza ---
mkdir -p "$HTDOCS_DIR/otra"
check "version de PHP que no se ofrece: no" '! docker_create otra 6.0 10.11 > /dev/null 2>&1'
check "dominio que no es .local: no" '! docker_create otra 8.1 10.11 --dominio google.com > /dev/null 2>&1 && [ ! -e "$DOCKER_DIR/otra" ]'
check "--bd sin --desde (o con una version que no esta): no" '! docker_create otra 8.1 10.11 --bd wp_t > /dev/null 2>&1 && ! docker_create otra 8.1 10.11 --bd wp_t --desde 9.9 > /dev/null 2>&1'
check "nombre de proyecto raro en las acciones: no" '! docker_action parar "../x" > /dev/null 2>&1'
check "contenedor que no es de un proyecto del gestor: no" '! docker_container_action parar mysql-1 > /dev/null 2>&1 && ! docker_container_action borrar "nexum-x-php-1;ls" > /dev/null 2>&1'
: > "$W/docker.log"
check "contenedor del gestor: borrar lo quita (rm -f)" 'docker_container_action borrar nexum-mi-tienda-8-4-db-1 > /dev/null && grep -qx "rm -f nexum-mi-tienda-8-4-db-1" "$W/docker.log"'

# --- Cambiar la version de PHP (sin sed -i: en el Mac no vale el de Linux) ---
: > "$W/docker.log"
check "docker-php: cambia la imagen de PHP y nada mas" 'docker_set_php mi-tienda-8-4 8.2 > /dev/null 2>&1 && grep -qx "    image: nexum-php:8.2" "$D/compose.yaml" && grep -qx "PHP=8.2" "$D/proyecto.conf" && grep -q "image: mariadb:10.11" "$D/compose.yaml" && grep -qx "PUERTO_WEB=$FPM" "$D/proyecto.conf"'
check "docker-php: prepara la imagen y recrea solo el contenedor de PHP" 'grep -q "^build -t nexum-php:8.2" "$W/docker.log" && grep -q "compose .* up -d php$" "$W/docker.log"'
check "docker-php: sin ficheros .nuevo de sobra" '! ls "$D"/*.nuevo > /dev/null 2>&1'
check "docker-php: sin sed -i" '! grep -A40 "^function docker_set_php" "$SRC" | grep -q "sed -i"'

# --- Borrar ---
docker_action borrar mi-tienda-8-4 > /dev/null 2>&1
check "borrar: contenedores y su BBDD (down -v)" 'grep -q "compose .* down -v" "$W/docker.log"'
check "borrar: sin su vhost, con los demas" '! grep -q "mi-tienda-8-4" "$ACTIVE_VHOSTS" && grep -q "ServerName web.local" "$ACTIVE_VHOSTS" && grep -q "nexum-docker ps17" "$ACTIVE_VHOSTS"'
check "borrar: sin su linea en hosts" '! grep -q "mi-tienda-8-4" "$HOSTS_FILE" && grep -q localhost "$HOSTS_FILE"'
check "borrar: su carpeta fuera; la del proyecto, no" '[ ! -e "$D" ] && [ -f "$WP" ]'
check "borrar: su clave para Apache, fuera" 'grep -qx mi-tienda-8-4 "$W/claves-quitadas"'

# --- Imagenes y volumenes (1.39.4): borrar y volver a descargar, con nombres comprobados ---
out=$(gui_docker)
check "gui-docker: imagenes con etiqueta e ID (I|imagen|etiqueta|ID|tamaño|creada)" 'grep -qx "I|nexum-php|8.2|3f2a9c1d7e6b|512MB|2 hours ago" <<< "$out" && [ "$(grep -c "^I|" <<< "$out")" == 1 ]'
: > "$W/docker.log"
check "imagenes: borrar por ID" 'docker_image_action borrar 3f2a9c1d7e6b > /dev/null 2>&1; grep -qx "image rm 3f2a9c1d7e6b" "$W/docker.log"'
check "imagenes: borrar por imagen:etiqueta" 'docker_image_action borrar php:8.2-fpm > /dev/null 2>&1; grep -qx "image rm php:8.2-fpm" "$W/docker.log"'
check "imagenes: borrar algo raro, no" '! docker_image_action borrar "-f x" > /dev/null 2>&1 && ! docker_image_action borrar "a;b" > /dev/null 2>&1 && ! docker_image_action borrar php > /dev/null 2>&1'
check "imagenes: borrar sin -f (si la usa un contenedor, Docker no la borra)" '! grep -q "image rm -f" "$W/docker.log"'
check "imagenes: descargar" 'docker_image_action descargar mariadb:11.8 > /dev/null 2>&1 && grep -qx "pull mariadb:11.8" "$W/docker.log"'
check "imagenes: descargar sin etiqueta o rara, no" '! docker_image_action descargar mariadb > /dev/null 2>&1 && ! docker_image_action descargar "x:1;ls" > /dev/null 2>&1'
check "imagenes: las del gestor no se descargan" '! docker_image_action descargar nexum-php:8.2 > /dev/null 2>&1 && ! grep -q "pull nexum-php" "$W/docker.log"'
check "imagenes: accion desconocida, no" '! docker_image_action quitar php:8.2-fpm > /dev/null 2>&1'
check "volumenes: borrar" 'docker_volume_remove nexum-mi-tienda-8-4_db > /dev/null 2>&1 && grep -qx "volume rm nexum-mi-tienda-8-4_db" "$W/docker.log"'
check "volumenes: nombre raro, no" '! docker_volume_remove "../x" > /dev/null 2>&1 && ! docker_volume_remove "-f" > /dev/null 2>&1 && ! docker_volume_remove "" > /dev/null 2>&1'
check "comandos docker-imagenes y docker-volumen-borrar" 'grep -q "^    docker-imagenes) docker_image_action \"\$2\" \"\$3\" ;;" "$SRC" && grep -q "^    docker-volumen-borrar) docker_volume_remove \"\$2\" ;;" "$SRC" && grep -q "^#   lvm-instalador docker-imagenes borrar" "$SRC"'
check "ventana: borrar imagenes y volumenes con estos comandos" 'grep -qF "[\"docker-imagenes\", \"borrar\", ref]" "$SRC" && grep -qF "[\"docker-imagenes\", \"descargar\", i.name]" "$SRC" && grep -qF "[\"docker-volumen-borrar\", v.name]" "$SRC"'
# --- 1.39.7: docker con la configuracion del gestor (sin el credsStore de Docker Desktop) ---
mkdir -p "$DOCKER_CONFIG_DIR/cli-plugins"; touch "$DOCKER_CONFIG_DIR/cli-plugins/docker-malo"
docker_config_dir > /dev/null
check "dk: configuracion propia, sin credsStore y con los complementos de Docker Desktop" 'grep -q "\"cliPluginsExtraDirs\": \[\"$DOCKER_APP/Contents/Resources/cli-plugins\"\]" "$DOCKER_CONFIG_DIR/config.json" && ! grep -q credsStore "$DOCKER_CONFIG_DIR/config.json" && [ "$(stat -c %a "$DOCKER_CONFIG_DIR")" == 700 ]'
check "dk: sin los complementos que se pongan en su carpeta" '[ ! -e "$DOCKER_CONFIG_DIR/cli-plugins" ]'
check "dk: una carpeta que es un enlace, no" 'mv "$DOCKER_CONFIG_DIR" "$W/otra"; ln -s "$W/otra" "$DOCKER_CONFIG_DIR"; ! docker_config_dir > /dev/null 2>&1; r=$?; rm "$DOCKER_CONFIG_DIR"; mv "$W/otra" "$DOCKER_CONFIG_DIR"; [ $r -eq 0 ]'
check "dk: docker recibe DOCKER_CONFIG" 'grep -qF "DOCKER_CONFIG=\$conf \"\$b\" \"\$@\"" "$SRC"'
exit $fail
