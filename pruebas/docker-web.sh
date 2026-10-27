#!/bin/bash
# Proyectos en Docker con el Apache de Docker (Linux 1.56.0), con un docker falso (sin Docker de verdad ni
# red): la direccion y los puertos (siempre de 127.x, sin los de LAMPP), el permiso de los puertos, los
# vhosts (con las reglas de seguridad de LAMPP y la barrera entre webs), el compose.yaml de cada
# proyecto con una version de PHP por servicio, la BBDD en la MariaDB comun sin contraseñas en las
# ordenes, varias versiones de PHP a la vez (WordPress) o la elegida (tienda), hosts y borrar.
# Uso: docker-web.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-docker-web.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
grep -q '^function docker_web_create() {' "$SRC" || { echo "  ok    (sin el Apache de Docker)"; exit 0; }
extract "$SRC" docker_sock dk docker_config_dir docker_ready docker_slug docker_valid_slug docker_conf docker_projects \
    docker_state docker_php_image docker_project_config docker_action docker_set_php docker_container_action \
    docker_web_get docker_web_valid_ip docker_web_url docker_web_ports_ok docker_maria_name docker_web_container \
    docker_web_project docker_web_domain docker_web_domains docker_web_projects docker_net docker_maria_sql \
    docker_maria_up docker_maria_versions docker_web_cert docker_web_trust docker_web_hosts docker_web_security \
    docker_web_site docker_web_write docker_web_state docker_web_up docker_web_reload docker_web_command \
    docker_web_set docker_web_allow docker_web_config docker_web_compose docker_web_services docker_conf_set \
    docker_web_ps_domain docker_web_create docker_web_add docker_web_remove docker_web_switch docker_web_action \
    docker_test_admin gui_docker docker_fix_restart docker_fix_pma docker_fix_cache docker_pass db_valid_name \
    valid_version_name cross_site_on php_85_or_later || exit 1
eval "$(sed -n "/^NO_TTY_PY='/,/^'\$/p" "$SRC")"
eval "$(sed -n '/^PHP_SECURE_INI=/,/^PHP_SECURE_INI_85=/p; /^DOCKER_EXT_INSTALLER=/p; /^DOCKER_WEB_IMAGE=/p; /^DOCKER_WEB_CONF=/p' "$SRC")"
eval "$(sed -n '/^DOCKER_PHP_VERSIONS=/p; /^DOCKER_MARIADB_VERSIONS=/p; /^DOCKER_PMA_IMAGE=/p; /^DOCKER_PHP_EXT=/p' "$SRC")"
eval "$(sed -n "/^UNKNOWN_HOST_VHOST='/,/^'\$/p" "$SRC")"
DB_SYSTEM="information_schema|mysql|performance_schema|phpmyadmin|sys|test"
DRY=0 SUDO="" HTDOCS_DIR=$W/htdocs DOCKER_DIR=$W/docker LOG_DIR=$W/log HOSTS_FILE=$W/hosts TEST_DIR=$W/v
DOCKER_WEB_DIR=$W/docker/web DOCKER_WEB_FILE=$W/docker/web.conf DOCKER_SYSCTL=$W/sysctl.conf
LVM_PORT_START_FILE=$W/port-start CROSS_SITE_OFF=$W/sin-barrera XDG_RUNTIME_DIR=$W/xdg
DOCKER_CONFIG_DIR=$W/log/docker-config TEST_ADMIN_USER=local@local.test TEST_ADMIN_PASS=local
mkdir -p "$HTDOCS_DIR/blog/wp-includes" "$HTDOCS_DIR/tienda/app/config" "$HTDOCS_DIR/tienda/src/PrestaShopBundle" \
    "$LOG_DIR" "$TEST_DIR/lampp-8.4"
printf '127.0.0.1 localhost\n127.0.0.1 tienda.es www.tienda.es\n' > "$HOSTS_FILE"
echo 1024 > "$LVM_PORT_START_FILE"
printf "<?php\ndefine( 'DB_NAME', 'wp_blog' );\ndefine( 'DB_USER', 'root' );\ndefine( 'DB_PASSWORD', '' );\ndefine( 'DB_HOST', 'localhost' );\n" > "$HTDOCS_DIR/blog/wp-config.php"
printf "<?php return array('parameters' => array('database_host' => '127.0.0.1', 'database_name' => 'ps_tienda', 'database_user' => 'root', 'database_password' => ''));\n" > "$HTDOCS_DIR/tienda/app/config/parameters.php"
cp "$HTDOCS_DIR/blog/wp-config.php" "$W/wp-antes"
# docker falso: apunta lo que se le pide (y lo que le llega por la entrada, el SQL) y contesta como Docker sin root
DOCKER_BIN=$W/docker-falso LVM_DOCKER_HOST=unix://$W/docker.sock
cat > "$DOCKER_BIN" << 'EOF'
#!/bin/bash
d=$(dirname "$0")
echo "$*" >> "$d/docker.log"
case "$1" in
    info) echo '["name=seccomp,profile=builtin","name=rootless"]' ;;
    version) echo 29.1.3 ;;
    image) exit 0 ;;
    network) exit 0 ;;
    ps) if [[ "$*" == *"name=^nexum-web\$"* ]]; then cat "$d/estado-web" 2> /dev/null; fi ;;
    exec)
        if [[ "$*" == *"SCHEMATA"* ]]; then cat "$d/bbdd-existe" 2> /dev/null || echo 0
        elif [[ "$*" == *"shop"*"url"* ]]; then echo ps_
        elif [[ "$*" == *" -i "* || "$2" == -i ]]; then cat >> "$d/sql.log"
        fi ;;
    compose)
        [[ "$*" == *" exec "* ]] && cat > /dev/null
        # (la copia de la BBDD de un proyecto de antes; con sin-volcado, no sale nada)
        [[ "$*" == *"mariadb-dump"* && ! -e "$d/sin-volcado" ]] && printf -- '-- volcado de prueba\nCREATE TABLE viejo (a INT);\nINSERT INTO viejo VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9);\n'
        exit 0 ;;
esac
exit 0
EOF
chmod +x "$DOCKER_BIN"
valid_project() { [ -d "$HTDOCS_DIR/$1" ] && [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9\ ._-]*$ ]]; }
valid_domain() { [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]; }
is_prestashop() { [ -d "$HTDOCS_DIR/$1/src/PrestaShopBundle" ]; }
is_wordpress() { [ -f "$HTDOCS_DIR/$1/wp-config.php" ]; }
sudo_first() { echo sudo_first >> "$W/hecho.log"; return 0; }
edit_hosts() { echo hosts >> "$W/hecho.log"; cp "$2" "$HOSTS_FILE"; }
export_database() { printf 'CREATE TABLE t (a INT);\n' | gzip > "$2"; }
db_temp_stop() { :; }
test_admin() { echo "A|wp|$TEST_ADMIN_USER|$TEST_ADMIN_PASS"; }
lampp_running() { return 0; }
no_tty() { "$@"; }
run() { "$@"; }
sudo() { echo "sudo $*" >> "$W/hecho.log"; "$@"; }
sysctl() { echo "sysctl $*" >> "$W/hecho.log"; echo 80 > "$LVM_PORT_START_FILE"; }
reset() { rm -f "$W/docker.log" "$W/sql.log" "$W/hecho.log"; }

# --- Direccion y puertos ---
check "por defecto: 127.0.0.2, 80 y 443" '[ "$(docker_web_get IP)|$(docker_web_get HTTP)|$(docker_web_get HTTPS)" == "127.0.0.2|80|443" ]'
check "direccion de la red, no" '! docker_web_valid_ip 192.168.1.10 && ! docker_web_valid_ip 0.0.0.0 && ! docker_web_valid_ip 127.0.0.256 && docker_web_valid_ip 127.0.0.2'
o=$(docker_web_set 127.0.0.1 80 443)
check "127.0.0.1 con 80 y 443 (los de LAMPP), no" '[ $? -ne 0 ] && [ ! -e "$DOCKER_WEB_FILE" ]'
o=$(docker_web_set 10.0.0.2 80 443)
check "otra direccion que no es de este equipo, no" '[ $? -ne 0 ] && [ ! -e "$DOCKER_WEB_FILE" ]'
o=$(docker_web_set 127.0.0.2 8443 8443)
check "el mismo puerto para http y https, no" '[ $? -ne 0 ] && [ ! -e "$DOCKER_WEB_FILE" ]'
o=$(docker_web_set 127.0.0.3 8080 8443)
check "otros puertos: se guardan (solo tuyo)" '[ $? -eq 0 ] && [ "$(docker_web_get IP)|$(docker_web_get HTTP)|$(docker_web_get HTTPS)" == "127.0.0.3|8080|8443" ] && [ "$(stat -c %a "$DOCKER_WEB_FILE")" == 600 ]'
check "con un puerto que no es el 443, la direccion lo lleva" '[ "$(docker_web_url a.docker.local)" == "https://a.docker.local:8443" ]'
check "puertos altos: no hace falta permiso" 'docker_web_ports_ok'
printf 'IP=127.0.0.2\nHTTP=80\nHTTPS=443\n' > "$DOCKER_WEB_FILE"
check "80 y 443 con el limite de siempre (1024): sin permiso" '! docker_web_ports_ok'
printf 'IP=$(echo mal)\nHTTP=80;x\nHTTPS=443\n' > "$DOCKER_WEB_FILE"
check "un docker-web.conf raro: los de siempre" '[ "$(docker_web_get IP)|$(docker_web_get HTTP)" == "127.0.0.2|80" ]'
printf 'IP=127.0.0.2\nHTTP=80\nHTTPS=443\n' > "$DOCKER_WEB_FILE"
reset
o=$(docker_web_allow)
check "permitir: baja el limite al puerto mas bajo, con la contraseña" 'grep -q "^net.ipv4.ip_unprivileged_port_start = 80$" "$DOCKER_SYSCTL" && grep -q sudo_first "$W/hecho.log" && docker_web_ports_ok'

# --- Crear (WordPress) ---
reset
o=$(docker_web_create blog 8.5 11.8 --bd wp_blog --desde 8.4 2>&1); rc=$?
D=$DOCKER_DIR/blog
check "docker-nuevo: termina bien" '[ $rc -eq 0 ] && grep -q "listo: https://blog-php85.docker.local " <<< "$o"'
check "la contraseña antes de cambiar nada" '[ "$(head -1 "$W/hecho.log")" == sudo_first ]'
check "carpeta y ficheros solo tuyos" '[ "$(stat -c %a "$D")" == 700 ] && [ "$(stat -c %a "$D/.env")" == 600 ] && [ "$(stat -c %a "$D/proyecto.conf")" == 600 ]'
check "proyecto.conf: del Apache de Docker, WordPress, PHP 8.5 y la BBDD en la MariaDB comun" 'grep -qx MODO=web "$D/proyecto.conf" && grep -qx TIPO=wp "$D/proyecto.conf" && grep -qx PHP=8.5 "$D/proyecto.conf" && grep -qx BBDD=wp_blog "$D/proyecto.conf" && grep -qx USUARIO=nx_wp_blog "$D/proyecto.conf"'
check "wp-config.php del proyecto sin tocar" 'cmp -s "$HTDOCS_DIR/blog/wp-config.php" "$W/wp-antes"'
check "config de PHP 8.5: la MariaDB comun, su usuario y su dominio" 'grep -qF "'"'"'DB_HOST'"'"', '"'"'nexum-mariadb-11-8'"'"'" "$D/config-85.php" && grep -qF "'"'"'DB_USER'"'"', '"'"'nx_wp_blog'"'"'" "$D/config-85.php" && grep -qF "https://blog-php85.docker.local" "$D/config-85.php"'
check "compose: PHP-FPM en la red interna, sin puertos fuera" 'grep -qx "  php85:" "$D/compose.yaml" && grep -qx "    container_name: nexum-blog-php85" "$D/compose.yaml" && grep -qF "./fpm.conf:/usr/local/etc/php-fpm.d/zz-nexum.conf:ro" "$D/compose.yaml" && ! grep -q "ports:" "$D/compose.yaml" && grep -qx "listen = 9000" "$D/fpm.conf"'
check "compose: la carpeta en la ruta que ve el Apache de Docker y el wp-config del contenedor encima" 'grep -qF "\"$HTDOCS_DIR/blog:/opt/lampp/htdocs/blog\"" "$D/compose.yaml" && grep -qF "./config-85.php:/opt/lampp/htdocs/blog/wp-config.php:ro" "$D/compose.yaml"'
check "compose: YAML valido" 'python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$D/compose.yaml" 2> /dev/null || ! python3 -c "import yaml" 2> /dev/null'
check "BBDD: su base y su usuario, solo con permiso en ella" 'grep -qF "CREATE DATABASE \`wp_blog\`" "$W/sql.log" && grep -qF "GRANT ALL PRIVILEGES ON \`wp_blog\`.* TO '"'"'nx_wp_blog'"'"'@" "$W/sql.log" && ! grep -q "ON \*\.\*" "$W/sql.log"'
check "BBDD: la copia de LAMPP cargada" 'grep -q "CREATE TABLE t" "$W/sql.log"'
check "ninguna contraseña en las ordenes de docker" '! grep -qF "$(sed -n "s/^DB_PASS=//p" "$D/.env")" "$W/docker.log" && ! grep -qF "$(sed -n "s/^DB_ROOT_PASS=//p" "$DOCKER_DIR/mariadb-11.8/.env")" "$W/docker.log"'
check "MariaDB comun: su contraseña de root, solo tuya" '[ "$(stat -c %a "$DOCKER_DIR/mariadb-11.8/.env")" == 600 ] && grep -qx "    container_name: nexum-mariadb-11-8" "$DOCKER_DIR/mariadb-11.8/compose.yaml" && ! grep -q "ports:" "$DOCKER_DIR/mariadb-11.8/compose.yaml"'
check "hosts: su dominio y el de phpMyAdmin, a 127.0.0.2 (los demas, igual)" 'grep -qE "^127\.0\.0\.2 .*blog-php85\.docker\.local" "$HOSTS_FILE" && grep -qE "^127\.0\.0\.2 .*pma\.docker\.local" "$HOSTS_FILE" && grep -qx "127.0.0.1 tienda.es www.tienda.es" "$HOSTS_FILE"'
check "certificado: *.docker.local, solo tuyo, y no de una CA" '[ "$(stat -c %a "$DOCKER_WEB_DIR/certs/docker.local.key")" == 600 ] && openssl x509 -in "$DOCKER_WEB_DIR/certs/docker.local.crt" -noout -text | grep -q "DNS:\*\.docker\.local" && openssl x509 -in "$DOCKER_WEB_DIR/certs/docker.local.crt" -noout -text | grep -q "CA:FALSE"'
check "Apache de Docker: sus puertos solo en 127.0.0.2 y la carpeta de proyectos de solo lectura" 'grep -qF "\"127.0.0.2:80:80\"" "$DOCKER_WEB_DIR/compose.yaml" && grep -qF "\"127.0.0.2:443:443\"" "$DOCKER_WEB_DIR/compose.yaml" && grep -qF "\"$HTDOCS_DIR:/opt/lampp/htdocs:ro\"" "$DOCKER_WEB_DIR/compose.yaml"'
check "Apache de Docker: imagen fijada por su huella" 'grep -qE "image: httpd:2\.4\.[0-9]+@sha256:[0-9a-f]{64}$" "$DOCKER_WEB_DIR/compose.yaml"'
check "Apache de Docker: su configuracion en una carpeta que no se cambia (montada entera)" 'grep -qF "./conf:/usr/local/apache2/conf/nexum:ro" "$DOCKER_WEB_DIR/compose.yaml" && ! grep -q "httpd.conf:/usr" "$DOCKER_WEB_DIR/compose.yaml" && [ -f "$DOCKER_WEB_DIR/conf/httpd.conf" ]'
check "Apache de Docker: trabaja con un usuario sin privilegios del contenedor" 'grep -qx "User daemon" "$DOCKER_WEB_DIR/conf/httpd.conf"'
check "vhost: http a https y los .php a su PHP 8.5" 'grep -qF "Redirect permanent / https://blog-php85.docker.local/" "$DOCKER_WEB_DIR/conf/sitios/blog.conf" && grep -qF "proxy:fcgi://nexum-blog-php85:9000" "$DOCKER_WEB_DIR/conf/sitios/blog.conf"'
check "reglas: las de LAMPP (.env, .git, copias de wp-config, copias de seguridad)" 'grep -qF "<FilesMatch \"(?i)(^\\.(env" "$DOCKER_WEB_DIR/conf/seguridad.conf" && grep -qF "/\\.(git|svn" "$DOCKER_WEB_DIR/conf/seguridad.conf" && grep -q "^LimitRequestBody" "$DOCKER_WEB_DIR/conf/seguridad.conf"'
check "reglas: con la barrera entre webs encendida" 'grep -q "^# >>> barrera entre webs" "$DOCKER_WEB_DIR/conf/seguridad.conf"'
check "un dominio sin proyecto: 403" 'grep -q "Require all denied" "$DOCKER_WEB_DIR/conf/sitios/000-defecto.conf" && [ "$(ls "$DOCKER_WEB_DIR/conf/sitios" | head -1)" == 000-defecto.conf ]'
check "phpMyAdmin: sin entrar solo (su pantalla de acceso) y con la MariaDB comun" '! grep -qE "PMA_(USER|PASSWORD)" "$DOCKER_WEB_DIR/compose.yaml" && grep -qF "PMA_HOSTS: \"nexum-mariadb-11-8\"" "$DOCKER_WEB_DIR/compose.yaml"'
check "arranca su PHP 8.5" 'grep -q "compose .* up -d php85$" "$W/docker.log"'
touch "$CROSS_SITE_OFF"; docker_web_write
check "barrera apagada: fuera del Apache de Docker tambien" '! grep -q "barrera entre webs" "$DOCKER_WEB_DIR/conf/seguridad.conf" && grep -q "^LimitRequestBody" "$DOCKER_WEB_DIR/conf/seguridad.conf"'
rm -f "$CROSS_SITE_OFF"

o=$(docker_web_create blog 8.4 11.8 2>&1)
check "la misma carpeta otra vez: no (se añade otra version)" '[ $? -ne 0 ] && grep -q "docker-php-añadir blog 8.4" <<< "$o"'
mkdir -p "$HTDOCS_DIR/otro" "$DOCKER_DIR/otro"; echo "CARPETA=otro" > "$DOCKER_DIR/otro/proyecto.conf"
o=$(docker_web_create otro 8.4 11.8 2>&1)
check "con un proyecto de antes del mismo nombre: no (docker-pasar)" '[ $? -ne 0 ] && grep -q "docker-pasar otro" <<< "$o"'
rm -rf "$DOCKER_DIR/otro"
echo 1 > "$W/bbdd-existe"
o=$(docker_web_create otro 8.4 11.8 --bd wp_blog --desde 8.4 2>&1)
check "una BBDD que ya esta en la MariaDB comun (de otro proyecto): no" '[ $? -ne 0 ] && grep -q "Ya hay una BBDD wp_blog" <<< "$o"'
rm -f "$W/bbdd-existe" "$DOCKER_DIR/otro" -r
check "version de PHP o MariaDB que no se ofrece, opcion rara o --bd sin origen: no" '! docker_web_create otro 6.0 11.8 > /dev/null 2>&1 && ! docker_web_create otro 8.4 9.9 > /dev/null 2>&1 && ! docker_web_create otro 8.4 11.8 --raro x > /dev/null 2>&1 && ! docker_web_create otro 8.4 11.8 --bd x > /dev/null 2>&1 && [ ! -e "$DOCKER_DIR/otro" ]'
mkdir -p "$HTDOCS_DIR/web"
o=$(DRY=1 docker_web_create web 8.4 11.8 2>&1)
check "una carpeta que se llama como lo comun (web): con otro nombre" 'grep -q "web-proyecto" <<< "$o"'

# --- Varias versiones de PHP (WordPress) ---
reset
o=$(docker_web_add blog 7.4 2>&1)
check "añadir PHP 7.4: las dos a la vez, cada una con su dominio" 'grep -qx "PHP=8.5 7.4" "$D/proyecto.conf" && grep -qx "  php74:" "$D/compose.yaml" && grep -qx "  php85:" "$D/compose.yaml" && grep -qF "https://blog-php74.docker.local" "$D/config-74.php" && grep -qF "proxy:fcgi://nexum-blog-php74:9000" "$DOCKER_WEB_DIR/conf/sitios/blog.conf" && grep -qF "proxy:fcgi://nexum-blog-php85:9000" "$DOCKER_WEB_DIR/conf/sitios/blog.conf"'
check "añadir: la misma BBDD (sin otra copia)" '! grep -qE "CREATE (DATABASE|TABLE)" "$W/sql.log" 2> /dev/null && grep -qF "'"'"'DB_NAME'"'"', '"'"'wp_blog'"'"'" "$D/config-74.php"'
check "añadir: su dominio en hosts" 'grep -qE "^127\.0\.0\.2 .*blog-php74\.docker\.local" "$HOSTS_FILE"'
check "añadir la que ya tiene: no hace nada" 'o=$(docker_web_add blog 7.4) && grep -q "ya tiene PHP 7.4" <<< "$o"'
out=$(gui_docker)
check "gui-docker: del Apache de Docker, con sus versiones" 'grep -qx "P|blog|blog|8.5|11.8|blog-php85.docker.local|[a-z?]*|wp_blog|web|web|8.5|wp|8.5 7.4" <<< "$out" && grep -qE "^W\|127\.0\.0\.2\|80\|443\|" <<< "$out"'
reset
o=$(docker_web_remove blog 8.5 2>&1)
check "quitar PHP 8.5: su contenedor, su configuracion y su dominio" 'grep -qx "PHP=7.4" "$D/proyecto.conf" && ! grep -q "php85" "$D/compose.yaml" && [ ! -e "$D/config-85.php" ] && ! grep -q "blog-php85" "$HOSTS_FILE" && grep -q "rm -sf php85" "$W/docker.log"'
check "quitar la elegida: la siguiente pasa a ser la suya" 'grep -qx "ACTIVA=7.4" "$D/proyecto.conf" && grep -qx "DOMINIO=blog-php74.docker.local" "$D/proyecto.conf"'
check "quitar la ultima: no" '! docker_web_remove blog 7.4 > /dev/null 2>&1 && grep -qx "PHP=7.4" "$D/proyecto.conf"'

# --- Tienda PrestaShop: un dominio y la version elegida ---
reset
o=$(docker_web_create tienda 8.1 10.11 --bd ps_tienda --desde 8.4 2>&1)
T=$DOCKER_DIR/tienda
check "tienda: un solo dominio (tienda.docker.local) y su dominio cambiado en su BBDD" 'grep -qx TIPO=ps "$T/proyecto.conf" && grep -qx DOMINIO=tienda.docker.local "$T/proyecto.conf" && grep -qF "UPDATE \`ps_shop_url\` SET domain = '"'"'tienda.docker.local'"'"'" "$W/sql.log"'
check "tienda: su cache en un volumen de cada version" 'grep -qF "\"cache-81:/opt/lampp/htdocs/tienda/var/cache\"" "$T/compose.yaml"'
reset
o=$(docker_web_add tienda 8.3 2>&1)
check "tienda: añadir PHP 8.3 la elige (arranca esa y quita la de antes)" 'grep -qx "ACTIVA=8.3" "$T/proyecto.conf" && grep -q "up -d php83$" "$W/docker.log" && grep -q "rm -sf php81$" "$W/docker.log" && grep -qF "proxy:fcgi://nexum-tienda-php83:9000" "$DOCKER_WEB_DIR/conf/sitios/tienda.conf" && ! grep -q "php81" "$DOCKER_WEB_DIR/conf/sitios/tienda.conf"'
check "tienda: arrancar solo la elegida" '[ "$(docker_web_services tienda)" == php83 ]'
reset
o=$(docker_web_switch tienda 8.1 2>&1)
check "tienda: volver a PHP 8.1" 'grep -qx "ACTIVA=8.1" "$T/proyecto.conf" && grep -qF "proxy:fcgi://nexum-tienda-php81:9000" "$DOCKER_WEB_DIR/conf/sitios/tienda.conf"'
check "tienda: elegir una que no tiene, no" '! docker_web_switch tienda 7.4 > /dev/null 2>&1 && grep -qx "ACTIVA=8.1" "$T/proyecto.conf"'

# --- Contenedores que se pueden manejar ---
check "contenedores del Apache de Docker: si" 'docker_container_action registros nexum-blog-php74 > /dev/null 2>&1 && docker_container_action registros nexum-web > /dev/null 2>&1 && docker_container_action registros nexum-mariadb-11-8 > /dev/null 2>&1'
check "otros contenedores: no" '! docker_container_action parar mi-postgres > /dev/null 2>&1 && ! docker_container_action parar "nexum-web;x" > /dev/null 2>&1'
check "docker-php de antes en uno nuevo: no (se añade y se quita)" '! docker_set_php blog 8.2 > /dev/null 2>&1'

# --- Cambiar la direccion ---
reset
o=$(docker_web_set 127.0.0.5 80 443 2>&1)
check "otra direccion: sus dominios pasan a ella en hosts, en una sola vez" 'grep -qE "^127\.0\.0\.5 .*blog-php74\.docker\.local" "$HOSTS_FILE" && grep -qE "^127\.0\.0\.5 .*tienda\.docker\.local" "$HOSTS_FILE" && ! grep -q "^127\.0\.0\.2" "$HOSTS_FILE" && [ "$(grep -c "^hosts$" "$W/hecho.log")" == 1 ]'
check "otra direccion: el Apache de Docker con ella" 'grep -qF "\"127.0.0.5:443:443\"" "$DOCKER_WEB_DIR/compose.yaml"'

# --- Pasar un proyecto de antes (con LAMPP delante) ---
HOME=$W/home
mkdir -p "$HOME" "$HTDOCS_DIR/viejo" "$DOCKER_DIR/viejo"
printf 'CARPETA=viejo\nPHP=8.2\nMARIADB=10.11\nDOMINIO=viejo.docker.local\nBBDD=wp_viejo\nPUERTO_PMA=28080\n' > "$DOCKER_DIR/viejo/proyecto.conf"
printf 'services:\n  db:\n    image: mariadb:10.11\n' > "$DOCKER_DIR/viejo/compose.yaml"
touch "$W/sin-volcado"; reset
o=$( docker_action() { echo "borrar $2" >> "$W/hecho.log"; }; docker_pass viejo 2>&1 )
check "pasar: si no sale la copia de su BBDD, no se cambia nada" '[ $? -ne 0 ] && [ -f "$DOCKER_DIR/viejo/proyecto.conf" ] && ! grep -q "^borrar" "$W/hecho.log" && [ -z "$(ls -A "$HOME/lvm-copias" 2> /dev/null)" ]'
rm -f "$W/sin-volcado"; reset
o=$( docker_action() { [ "$1" == borrar ] && echo "borrar $2" >> "$W/hecho.log" && rm -rf "$DOCKER_DIR/$2"; }; docker_pass viejo 2>&1 ); rc=$?
check "pasar: la copia de su BBDD en ~/lvm-copias (solo tuya), antes de quitar nada" '[ $rc -eq 0 ] && ls "$HOME/lvm-copias"/docker-viejo-wp_viejo-*.sql.gz > /dev/null 2>&1 && [ "$(stat -c %a "$(ls "$HOME/lvm-copias"/docker-viejo-*.sql.gz)")" == 600 ]'
check "pasar: se quita el de antes y queda en el Apache de Docker con su BBDD" 'grep -qx "borrar viejo" "$W/hecho.log" && grep -qx MODO=web "$DOCKER_DIR/viejo/proyecto.conf" && grep -qx BBDD=wp_viejo "$DOCKER_DIR/viejo/proyecto.conf" && grep -qx PHP=8.2 "$DOCKER_DIR/viejo/proyecto.conf" && grep -q "CREATE TABLE viejo" "$W/sql.log"'
check "pasar uno que ya es del Apache de Docker: no" '! docker_pass viejo > /dev/null 2>&1'

# --- Borrar ---
reset
o=$(docker_action borrar blog 2>&1)
check "borrar: sus contenedores, su BBDD y su usuario de la MariaDB comun" 'grep -q "compose .* down -v" "$W/docker.log" && grep -qF "DROP DATABASE IF EXISTS \`wp_blog\`" "$W/sql.log" && grep -qF "DROP USER IF EXISTS '"'"'nx_wp_blog'"'"'@'"'"'%'"'"'" "$W/sql.log"'
check "borrar: sus dominios fuera de hosts, su vhost y su carpeta del gestor (la del proyecto, no)" '! grep -q "blog-php" "$HOSTS_FILE" && [ ! -e "$DOCKER_WEB_DIR/conf/sitios/blog.conf" ] && [ ! -e "$D" ] && [ -d "$HTDOCS_DIR/blog" ] && grep -q "tienda.docker.local" "$HOSTS_FILE"'
exit $fail
