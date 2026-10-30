#!/bin/bash
# Proyectos en Docker con el Apache de Docker en el Mac (1.40.0), con un docker falso (sin Docker
# Desktop ni red): la direccion (de 127.x, dada de alta en lo0 con un servicio del sistema), los vhosts
# (cada dominio al contenedor de su version de PHP, con la clave del proyecto y la barrera entre webs),
# el compose.yaml de cada proyecto con una version de PHP por servicio, la BBDD en la MariaDB comun sin
# contraseñas en las ordenes, varias versiones de PHP a la vez (WordPress) o la elegida (tienda), hosts,
# pasar uno de antes y borrar. Uso: docker-web-mac.sh <lvm-instalador.sh del Mac>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-docker-web-mac.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
grep -q '^function docker_web_create() {' "$SRC" && grep -q "LVM_SWIFT" "$SRC" || { echo "  ok    (sin el Apache de Docker del Mac)"; exit 0; }
extract "$SRC" docker_bin docker_sock dk docker_config_dir docker_ready docker_slug docker_valid_slug docker_conf \
    docker_projects docker_state docker_php_image docker_web_rules docker_project_config docker_action docker_set_php \
    docker_container_action docker_web_get docker_web_valid_ip docker_web_url docker_web_ports_ok docker_maria_name \
    docker_web_container docker_web_project docker_web_domain docker_web_domains docker_web_projects docker_net \
    docker_maria_sql docker_maria_up docker_maria_versions docker_web_cert docker_web_trust docker_web_hosts \
    docker_web_security docker_web_site docker_web_write docker_web_state docker_web_up docker_web_reload \
    docker_web_command docker_web_set docker_web_allow docker_web_config docker_web_compose docker_web_services docker_prefork_conf \
    docker_conf_set docker_web_ps_domain docker_web_create docker_web_add docker_web_remove docker_web_switch \
    docker_web_action docker_test_admin gui_docker docker_pass docker_shared_warn docker_web_idle_stop \
    docker_db_password docker_migrate db_valid_name valid_version_name web_barrier_on unknown_host_vhost || exit 1
grep -q '^function docker_web_media() {' "$SRC" && { extract "$SRC" docker_web_media media_saved || exit 1; }
MEDIA_PROJECTS_FILE=$W/media-produccion
docker_idle_ensure() { :; }
custom_domain() { [ "$1" == blog ] && echo blog.test; }
PROJECT_VHOST=web.local
grep -q '^function docker_dns_activate() {' "$SRC" && { extract "$SRC" docker_web_conf_write docker_web_tld docker_dns_on \
    docker_web_pma docker_dns_install docker_dns_uninstall docker_dns_works docker_web_retld docker_dns_activate \
    docker_dns_deactivate docker_dns_command || exit 1; eval "$(sed -n "/^DOCKER_DNS_PY=\$(cat <<'DNSPY'/,/^DNSPY/p; /^DOCKER_DNS_PORT=/p" "$SRC"; echo ')')"; }
eval "$(sed -n "/^PHP_SECURITY_INI='/,/^'\$/p; /^PHP_SECURITY_INI_85='/,/^'\$/p" "$SRC")"
eval "$(sed -n '/^DOCKER_WEB_IMAGE=/p; /^DOCKER_WEB_CONF=/p; /^DOCKER_IMAGE_SCHEMA=/p' "$SRC")"
eval "$(sed -n '/^DOCKER_PHP_VERSIONS=/p; /^DOCKER_MARIADB_VERSIONS=/p; /^DOCKER_PMA_IMAGE=/p; /^DOCKER_PHP_EXT=/p' "$SRC")"
eval "$(sed -n "/^UNKNOWN_HOST_VHOST='/,/^'\$/p" "$SRC")"
DRY=0 SUDO="" HTDOCS_DIR=$W/htdocs DOCKER_DIR=$W/docker LOG_DIR=$W/log HOSTS_FILE=$W/hosts TEST_DIR=$W/v
BASE_DIR=$W/apps LINK=$W/apps/XAMPP DOCKER_APP=$W/Docker.app
DOCKER_PREFORK_CONF=$DOCKER_DIR/apache-ligero.conf
DOCKER_WEB_DIR=$W/docker/web DOCKER_WEB_FILE=$W/docker/web.conf DOCKER_LOOPBACK_PLIST=$W/direccion.plist
LVM_LO0_FILE=$W/lo0 WEB_BARRIER_OFF=$W/sin-barrera
DOCKER_CONFIG_DIR=$W/log/docker-config TEST_ADMIN_USER=local@local.test TEST_ADMIN_PASS=local
mkdir -p "$HTDOCS_DIR/blog/wp-includes" "$HTDOCS_DIR/tienda/app/config" "$HTDOCS_DIR/tienda/src/PrestaShopBundle" \
    "$LOG_DIR" "$BASE_DIR/XAMPP-8.4"
printf '127.0.0.1 localhost\n127.0.0.1 tienda.es www.tienda.es\n' > "$HOSTS_FILE"
: > "$LVM_LO0_FILE"
printf "<?php\ndefine( 'DB_NAME', 'wp_blog' );\ndefine( 'DB_USER', 'root' );\ndefine( 'DB_PASSWORD', '' );\ndefine( 'DB_HOST', 'localhost' );\n" > "$HTDOCS_DIR/blog/wp-config.php"
printf "<?php return array('parameters' => array('database_host' => '127.0.0.1', 'database_name' => 'ps_tienda', 'database_user' => 'root', 'database_password' => ''));\n" > "$HTDOCS_DIR/tienda/app/config/parameters.php"
cp "$HTDOCS_DIR/blog/wp-config.php" "$W/wp-antes"
# docker falso: apunta lo que se le pide (y lo que le llega por la entrada, el SQL) y contesta como Docker Desktop
LVM_DOCKER=$W/docker-falso LVM_DOCKER_HOST=unix://$W/docker.sock
cat > "$LVM_DOCKER" << 'EOF'
#!/bin/bash
d=$(dirname "$0")
echo "$*" >> "$d/docker.log"
case "$1" in
    info) echo 29.1.3 ;;
    version) echo 29.1.3 ;;
    image) exit 0 ;;
    build) exit 0 ;;
    network) exit 0 ;;
    ps) if [[ "$*" == *"name=^nexum-web\$"* ]]; then cat "$d/estado-web" 2> /dev/null; fi ;;
    exec)
        if [[ "$*" == *"SCHEMATA"* ]]; then cat "$d/bbdd-existe" 2> /dev/null || echo 0
        elif [[ "$*" == *"SELECT domain FROM"* ]]; then echo tienda.es
        elif [[ "$*" == *"shop"*"url"* ]]; then echo ps_
        elif [[ "$*" == *" -i "* || "$2" == -i ]]; then cat >> "$d/sql.log"
        fi ;;
    compose)
        [[ "$*" == *" exec "* ]] && cat > /dev/null
        [[ "$*" == *"mariadb-dump"* && ! -e "$d/sin-volcado" ]] && printf -- '-- volcado de prueba\nCREATE TABLE viejo (a INT);\nINSERT INTO viejo VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9);\n'
        exit 0 ;;
esac
exit 0
EOF
chmod +x "$LVM_DOCKER"
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
run() { "$@"; }
# (lo del sistema: ifconfig y launchctl, sin tocarlos)
launchctl() { echo "launchctl $*" >> "$W/hecho.log"; }
install() { local a=() x; for x in "$@"; do [[ "$x" == -o || "$x" == -g ]] && { skip=1; continue; }; [ "${skip:-0}" == 1 ] && { skip=0; continue; }; a+=("$x"); done; command install "${a[@]}"; }
ifconfig_falso() { echo "$4" >> "$LVM_LO0_FILE"; }
reset() { rm -f "$W/docker.log" "$W/sql.log" "$W/hecho.log"; }

# --- Direccion y puertos ---
check "por defecto: 127.0.0.2, 80 y 443" '[ "$(docker_web_get IP)|$(docker_web_get HTTP)|$(docker_web_get HTTPS)" == "127.0.0.2|80|443" ]'
check "direccion de la red, no" '! docker_web_valid_ip 192.168.1.10 && ! docker_web_valid_ip 0.0.0.0 && ! docker_web_valid_ip 127.0.0.256 && docker_web_valid_ip 127.0.0.2'
o=$(docker_web_set 127.0.0.1 80 443)
check "127.0.0.1 con 80 y 443 (los de XAMPP-X), no" '[ $? -ne 0 ] && [ ! -e "$DOCKER_WEB_FILE" ]'
o=$(docker_web_set 10.0.0.2 80 443)
check "otra direccion que no es de este equipo, no" '[ $? -ne 0 ] && [ ! -e "$DOCKER_WEB_FILE" ]'
o=$(docker_web_set 127.0.0.2 8443 8443)
check "el mismo puerto para http y https, no" '[ $? -ne 0 ] && [ ! -e "$DOCKER_WEB_FILE" ]'
o=$(docker_web_set 127.0.0.3 8080 8443)
check "otros puertos: se guardan (solo tuyo)" '[ $? -eq 0 ] && [ "$(docker_web_get IP)|$(docker_web_get HTTP)|$(docker_web_get HTTPS)" == "127.0.0.3|8080|8443" ] && [ "$(stat -c %a "$DOCKER_WEB_FILE")" == 600 ]'
check "con un puerto que no es el 443, la direccion lo lleva" '[ "$(docker_web_url a.docker.local)" == "https://a.docker.local:8443" ]'
check "una direccion que no esta en lo0: hay que darla de alta" '! docker_web_ports_ok'
printf 'IP=127.0.0.2\nHTTP=80\nHTTPS=443\n' > "$DOCKER_WEB_FILE"
printf 'IP=$(echo mal)\nHTTP=80;x\nHTTPS=443\n' > "$DOCKER_WEB_FILE"
check "un docker-web.conf raro: los de siempre" '[ "$(docker_web_get IP)|$(docker_web_get HTTP)" == "127.0.0.2|80" ]'
printf 'IP=127.0.0.2\nHTTP=80\nHTTPS=443\n' > "$DOCKER_WEB_FILE"
reset
o=$( SUDO=sudo_falso; sudo_falso() { if [ "$1" == /sbin/ifconfig ]; then echo "$4" >> "$LVM_LO0_FILE"; else "$@"; fi; }; docker_web_allow )
check "permitir: con la contraseña, el servicio del sistema que pone 127.0.0.2 en lo0 en cada arranque" 'grep -q sudo_first "$W/hecho.log" && grep -q "<string>/sbin/ifconfig</string>" "$DOCKER_LOOPBACK_PLIST" && grep -q "<string>127.0.0.2</string>" "$DOCKER_LOOPBACK_PLIST" && grep -q "<key>RunAtLoad</key>" "$DOCKER_LOOPBACK_PLIST" && grep -q "launchctl bootstrap system" "$W/hecho.log"'
check "permitir: y ya esta en este Mac" 'docker_web_ports_ok'

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
check "compose: su PHP (con Apache) en la red interna, con su dominio y la clave, sin puertos fuera" 'grep -qx "  php85:" "$D/compose.yaml" && grep -qx "    container_name: nexum-blog-php85" "$D/compose.yaml" && grep -qF "NEXUM_KEY: \${WEB_KEY}" "$D/compose.yaml" && grep -qF "NEXUM_DOMAIN: \"blog-php85.docker.local\"" "$D/compose.yaml" && ! grep -q "ports:" "$D/compose.yaml"'
check "la clave del proyecto: larga, solo tuya y nunca en el compose" 'grep -qE "^WEB_KEY=[A-Za-z0-9]{20,}$" "$D/.env" && ! grep -qF "$(sed -n "s/^WEB_KEY=//p" "$D/.env")" "$D/compose.yaml"'
check "compose: la carpeta en la misma ruta que en el Mac y el wp-config del contenedor encima" 'grep -qF "\"$HTDOCS_DIR/blog:$LINK/xamppfiles/htdocs/blog\"" "$D/compose.yaml" && grep -qF "./config-85.php:$LINK/xamppfiles/htdocs/blog/wp-config.php:ro" "$D/compose.yaml"'
check "config: las direcciones de la web en local (web.local y su dominio propio), en lo que devuelve, las del contenedor" 'grep -qF "ob_start(function (\$b) { return str_replace(array(" "$D"/config-*.php && grep -qF "https://web.local" "$D"/config-*.php && grep -qF "https://blog.test" "$D"/config-*.php'
PHPBIN=$(command -v php || ls /opt/lampp/bin/php 2> /dev/null)
if [ -n "$PHPBIN" ]; then
    f=$(ls "$D"/config-*.php | head -1)
    dom=$(sed -n "s/^define(.WP_HOME., .https:\/\/\([^\x27]*\).);$/\1/p" "$f" | head -1)
    sed -n "/ob_start/p" "$f" > "$W/ob.php"
    printf '<?php\ndefine("PHP_SAPI_X", 1);\n' > "$W/prueba.php"
    sed 's/PHP_SAPI !== .cli./true/' "$W/ob.php" >> "$W/prueba.php"
    printf 'echo "<img src=\\"https://web.local/wp-content/uploads/a.jpg\\"> {\\"u\\":\\"https:\\\\/\\\\/web.local\\\\/b.jpg\\"} web.local http://blog.test/c";\n' >> "$W/prueba.php"
    out=$("$PHPBIN" -n "$W/prueba.php" 2>&1)
    check "config: con PHP, las imagenes de web.local (normales y escapadas) salen del contenedor; el texto suelto, igual" '[[ "$out" == *"https://$dom/wp-content/uploads/a.jpg"* ]] && [[ "$out" == *"https:\\/\\/$dom\\/b.jpg"* ]] && [[ "$out" == *" web.local "* ]] && [[ "$out" == *"https://$dom/c"* ]]'
fi
check "compose: YAML valido" 'python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$D/compose.yaml" 2> /dev/null || ! python3 -c "import yaml" 2> /dev/null'
check "BBDD: su base y su usuario, solo con permiso en ella" 'grep -qF "CREATE DATABASE \`wp_blog\`" "$W/sql.log" && grep -qF "GRANT ALL PRIVILEGES ON \`wp_blog\`.* TO '"'"'nx_wp_blog'"'"'@" "$W/sql.log" && ! grep -q "ON \*\.\*" "$W/sql.log"'
check "BBDD: la copia de XAMPP-X cargada" 'grep -q "CREATE TABLE t" "$W/sql.log"'
check "ninguna contraseña en las ordenes de docker" '! grep -qF "$(sed -n "s/^DB_PASS=//p" "$D/.env")" "$W/docker.log" && ! grep -qF "$(sed -n "s/^DB_ROOT_PASS=//p" "$DOCKER_DIR/mariadb-11.8/.env")" "$W/docker.log"'
check "MariaDB comun: su contraseña de root, solo tuya" '[ "$(stat -c %a "$DOCKER_DIR/mariadb-11.8/.env")" == 600 ] && grep -qx "    container_name: nexum-mariadb-11-8" "$DOCKER_DIR/mariadb-11.8/compose.yaml" && ! grep -q "ports:" "$DOCKER_DIR/mariadb-11.8/compose.yaml"'
check "hosts: su dominio y el de phpMyAdmin, a 127.0.0.2 (los demas, igual)" 'grep -qE "^127\.0\.0\.2 .*blog-php85\.docker\.local" "$HOSTS_FILE" && grep -qE "^127\.0\.0\.2 .*pma\.docker\.local" "$HOSTS_FILE" && grep -qx "127.0.0.1 tienda.es www.tienda.es" "$HOSTS_FILE"'
check "certificado: *.docker.local, solo tuyo, y no de una CA" '[ "$(stat -c %a "$DOCKER_WEB_DIR/certs/docker.local.key")" == 600 ] && openssl x509 -in "$DOCKER_WEB_DIR/certs/docker.local.crt" -noout -text | grep -q "DNS:\*\.docker\.local" && openssl x509 -in "$DOCKER_WEB_DIR/certs/docker.local.crt" -noout -text | grep -q "CA:FALSE"'
check "Apache de Docker: sus puertos solo en 127.0.0.2 y la carpeta de los proyectos de solo lectura" 'grep -qF "\"127.0.0.2:80:80\"" "$DOCKER_WEB_DIR/compose.yaml" && grep -qF "\"127.0.0.2:443:443\"" "$DOCKER_WEB_DIR/compose.yaml" && grep -qF "\"$HTDOCS_DIR:/opt/lampp/htdocs:ro\"" "$DOCKER_WEB_DIR/compose.yaml"'
check "Apache de Docker: imagen fijada por su huella" 'grep -qE "image: httpd:2\.4\.[0-9]+@sha256:[0-9a-f]{64}$" "$DOCKER_WEB_DIR/compose.yaml"'
check "Apache de Docker: su configuracion en una carpeta que no se cambia (montada entera)" 'grep -qF "./conf:/usr/local/apache2/conf/nexum:ro" "$DOCKER_WEB_DIR/compose.yaml" && ! grep -q "httpd.conf:/usr" "$DOCKER_WEB_DIR/compose.yaml" && [ -f "$DOCKER_WEB_DIR/conf/httpd.conf" ]'
check "Apache de Docker: trabaja con un usuario sin privilegios del contenedor" 'grep -qx "User daemon" "$DOCKER_WEB_DIR/conf/httpd.conf"'
# Pocos recursos con varios proyectos a la vez (Linux 1.56.7, Mac 1.40.1)
check "ligero: el Apache de Docker, con un proceso esperando (no tres)" 'grep -qx "StartServers 1" "$DOCKER_WEB_DIR/conf/httpd.conf" && grep -qx "MaxRequestWorkers 100" "$DOCKER_WEB_DIR/conf/httpd.conf"'
check "ligero: el Apache con PHP de cada contenedor, con un proceso esperando (no cinco)" 'grep -qF "\"$DOCKER_DIR/apache-ligero.conf:/etc/apache2/mods-available/mpm_prefork.conf:ro\"" "$D/compose.yaml" && grep -q "^    StartServers 1$" "$DOCKER_DIR/apache-ligero.conf" && grep -q "^    MaxSpareServers 2$" "$DOCKER_DIR/apache-ligero.conf" && [ "$(stat -c %a "$DOCKER_DIR/apache-ligero.conf" 2> /dev/null || stat -f %Lp "$DOCKER_DIR/apache-ligero.conf")" == 600 ]'
grep -v "apache-ligero" "$D/compose.yaml" > "$W/c" && cat "$W/c" > "$D/compose.yaml"
docker_web_action arrancar blog > /dev/null 2>&1
check "ligero: uno de antes se pone al dia al arrancar (compose lo rehace)" 'grep -qF "apache-ligero.conf:/etc/apache2/mods-available/mpm_prefork.conf:ro" "$D/compose.yaml"'
check "vhost: http a https y todo a su PHP 8.5, con su dominio y la clave" 'grep -qF "Redirect permanent / https://blog-php85.docker.local/" "$DOCKER_WEB_DIR/conf/sitios/blog.conf" && grep -qF "ProxyPass / http://nexum-blog-php85/" "$DOCKER_WEB_DIR/conf/sitios/blog.conf" && grep -qx "    ProxyPreserveHost On" "$DOCKER_WEB_DIR/conf/sitios/blog.conf" && grep -qF "X-Nexum-Key \"$(sed -n "s/^WEB_KEY=//p" "$D/.env")\"" "$DOCKER_WEB_DIR/conf/sitios/blog.conf"'
check "vhosts con la clave: solo tuyos" '[ "$(stat -c %a "$DOCKER_WEB_DIR/conf/sitios/blog.conf")" == 600 ] && [ "$(stat -c %a "$DOCKER_WEB_DIR")" == 700 ]'
check "reglas: las de XAMPP-X (.env, .git, copias de wp-config, copias de seguridad)" 'grep -qF "<FilesMatch \"(?i)(^\\.(env" "$DOCKER_WEB_DIR/conf/seguridad.conf" && grep -qF "/\\.(git|svn" "$DOCKER_WEB_DIR/conf/seguridad.conf" && grep -q "^LimitRequestBody" "$DOCKER_WEB_DIR/conf/seguridad.conf"'
check "reglas: con la barrera entre webs encendida" 'grep -q "^# lvm-barrera-web:" "$DOCKER_WEB_DIR/conf/seguridad.conf"'
check "un dominio sin proyecto: 403" 'grep -q "Require all denied" "$DOCKER_WEB_DIR/conf/sitios/000-defecto.conf" && [ "$(ls "$DOCKER_WEB_DIR/conf/sitios" | head -1)" == 000-defecto.conf ]'
check "phpMyAdmin: sin entrar solo (su pantalla de acceso) y con la MariaDB comun" '! grep -qE "PMA_(USER|PASSWORD)" "$DOCKER_WEB_DIR/compose.yaml" && grep -qF "PMA_HOSTS: \"nexum-mariadb-11-8\"" "$DOCKER_WEB_DIR/compose.yaml"'
check "arranca su PHP 8.5" 'grep -q "compose .* up -d php85$" "$W/docker.log"'
touch "$WEB_BARRIER_OFF"; docker_web_write
check "barrera apagada: fuera del Apache de Docker tambien" '! grep -q "lvm-barrera-web" "$DOCKER_WEB_DIR/conf/seguridad.conf" && grep -q "^LimitRequestBody" "$DOCKER_WEB_DIR/conf/seguridad.conf"'
rm -f "$WEB_BARRIER_OFF"

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
check "añadir PHP 7.4: las dos a la vez, cada una con su dominio" 'grep -qx "PHP=8.5 7.4" "$D/proyecto.conf" && grep -qx "  php74:" "$D/compose.yaml" && grep -qx "  php85:" "$D/compose.yaml" && grep -qF "https://blog-php74.docker.local" "$D/config-74.php" && grep -qF "ProxyPass / http://nexum-blog-php74/" "$DOCKER_WEB_DIR/conf/sitios/blog.conf" && grep -qF "ProxyPass / http://nexum-blog-php85/" "$DOCKER_WEB_DIR/conf/sitios/blog.conf" && grep -qF "NEXUM_DOMAIN: \"blog-php74.docker.local\"" "$D/compose.yaml"'
check "añadir: la misma BBDD (sin otra copia)" '! grep -qE "CREATE (DATABASE|TABLE)" "$W/sql.log" 2> /dev/null && grep -qF "'"'"'DB_NAME'"'"', '"'"'wp_blog'"'"'" "$D/config-74.php"'
check "añadir: su dominio en hosts" 'grep -qE "^127\.0\.0\.2 .*blog-php74\.docker\.local" "$HOSTS_FILE"'
check "añadir la que ya tiene: no hace nada" 'o=$(docker_web_add blog 7.4) && grep -q "ya tiene PHP 7.4" <<< "$o"'
out=$(gui_docker)
check "gui-docker: del Apache de Docker, con sus versiones" 'grep -qx "P|blog|blog|8.5|11.8|blog-php85.docker.local|[a-z?]*|wp_blog|web|web|0|wp|8.5 7.4|" <<< "$out" && grep -qE "^W\|127\.0\.0\.2\|80\|443\|" <<< "$out"'
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
check "tienda: su cache en un volumen de cada version" 'grep -qF "\"cache-81:$LINK/xamppfiles/htdocs/tienda/var/cache\"" "$T/compose.yaml"'
reset
o=$(docker_web_add tienda 8.3 2>&1)
check "tienda: añadir PHP 8.3 la elige (arranca esa y quita la de antes)" 'grep -qx "ACTIVA=8.3" "$T/proyecto.conf" && grep -q "up -d php83$" "$W/docker.log" && grep -q "rm -sf php81$" "$W/docker.log" && grep -qF "ProxyPass / http://nexum-tienda-php83/" "$DOCKER_WEB_DIR/conf/sitios/tienda.conf" && ! grep -q "php81" "$DOCKER_WEB_DIR/conf/sitios/tienda.conf"'
check "tienda: arrancar solo la elegida" '[ "$(docker_web_services tienda)" == php83 ]'
reset
o=$(docker_web_switch tienda 8.1 2>&1)
check "tienda: volver a PHP 8.1" 'grep -qx "ACTIVA=8.1" "$T/proyecto.conf" && grep -qF "ProxyPass / http://nexum-tienda-php81/" "$DOCKER_WEB_DIR/conf/sitios/tienda.conf"'
check "tienda: elegir una que no tiene, no" '! docker_web_switch tienda 7.4 > /dev/null 2>&1 && grep -qx "ACTIVA=8.1" "$T/proyecto.conf"'

# --- Contenedores que se pueden manejar ---
check "contenedores del Apache de Docker: si" 'docker_container_action registros nexum-blog-php74 > /dev/null 2>&1 && docker_container_action registros nexum-web > /dev/null 2>&1 && docker_container_action registros nexum-mariadb-11-8 > /dev/null 2>&1'
check "otros contenedores: no" '! docker_container_action parar mi-postgres > /dev/null 2>&1 && ! docker_container_action parar "nexum-web;x" > /dev/null 2>&1'
check "docker-php de antes en uno nuevo: no (se añade y se quita)" '! docker_set_php blog 8.2 > /dev/null 2>&1'

# --- Cambiar la direccion ---
reset
echo 127.0.0.5 >> "$LVM_LO0_FILE"
o=$(docker_web_set 127.0.0.5 80 443 2>&1)
check "otra direccion: sus dominios pasan a ella en hosts, en una sola vez" 'grep -qE "^127\.0\.0\.5 .*blog-php74\.docker\.local" "$HOSTS_FILE" && grep -qE "^127\.0\.0\.5 .*tienda\.docker\.local" "$HOSTS_FILE" && ! grep -q "^127\.0\.0\.2" "$HOSTS_FILE" && [ "$(grep -c "^hosts$" "$W/hecho.log")" == 1 ]'
check "otra direccion: el Apache de Docker con ella" 'grep -qF "\"127.0.0.5:443:443\"" "$DOCKER_WEB_DIR/compose.yaml"'

# --- Pasar un proyecto de antes (con XAMPP-X delante) ---
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
check "contraseña de phpMyAdmin: la de su MariaDB comun, con pma.docker.local" 'docker_db_password tienda | grep -qE "^K\|root\|[A-Za-z0-9]+\|https://pma\.docker\.local/$"'
check "borrar: sus contenedores, su BBDD y su usuario de la MariaDB comun" 'grep -q "compose .* down -v" "$W/docker.log" && grep -qF "DROP DATABASE IF EXISTS \`wp_blog\`" "$W/sql.log" && grep -qF "DROP USER IF EXISTS '"'"'nx_wp_blog'"'"'@'"'"'%'"'"'" "$W/sql.log"'
check "borrar: sus dominios fuera de hosts, su vhost y su carpeta del gestor (la del proyecto, no)" '! grep -q "blog-php" "$HOSTS_FILE" && [ ! -e "$DOCKER_WEB_DIR/conf/sitios/blog.conf" ] && [ ! -e "$D" ] && [ -d "$HTDOCS_DIR/blog" ] && grep -q "tienda.docker.local" "$HOSTS_FILE"'
# --- Imagenes de produccion (Mac 1.40.1) ---
if grep -q '^function docker_web_media() {' "$SRC"; then
    extract "$SRC" media_project ps_images || exit 1
    eval "$(grep -m1 '^MEDIA_EXT=' "$SRC")"
    MEDIA_PROJECTS_FILE=$LOG_DIR/media-produccion
    media_sync() { :; }
    check "imagenes: la tienda guarda su dominio de produccion al pasar a Docker" 'grep -qx PRODUCCION=tienda.es "$T/proyecto.conf"'
    mkdir -p "$HTDOCS_DIR/wpmedia/wp-includes" && printf "<?php\ndefine( 'DB_NAME', 'wp_m' );\n" > "$HTDOCS_DIR/wpmedia/wp-config.php"
    docker_web_create wpmedia 8.4 11.8 > /dev/null 2>&1
    check "imagenes: sin dominio de produccion, ninguna regla" '! grep -q "nexum-media" "$DOCKER_WEB_DIR/conf/sitios/wpmedia.conf"'
    reset
    o=$(media_project wpmedia ejemplo.es 2>&1)
    check "imagenes: el dominio de media-proyecto vale tambien en el Apache de Docker (al momento)" 'grep -q "nexum-media ejemplo.es" "$DOCKER_WEB_DIR/conf/sitios/wpmedia.conf" && grep -qF "RewriteCond /opt/lampp/htdocs/wpmedia%{REQUEST_URI} !-f" "$DOCKER_WEB_DIR/conf/sitios/wpmedia.conf" && grep -qF "RewriteRule ^/(wp-content/uploads/.+\.(" "$DOCKER_WEB_DIR/conf/sitios/wpmedia.conf" && grep -qF " https://ejemplo.es/\$1 [NC,R=302,L]" "$DOCKER_WEB_DIR/conf/sitios/wpmedia.conf"'
    check "imagenes: solo GET y HEAD" 'grep -qF "RewriteCond %{REQUEST_METHOD} ^(GET|HEAD)\$" "$DOCKER_WEB_DIR/conf/sitios/wpmedia.conf"'
    check "imagenes: en la tienda, no (sus imagenes se descargan: ps-imagenes)" '! grep -q "nexum-media" "$DOCKER_WEB_DIR/conf/sitios/tienda.conf"'
    check "imagenes (Mac): antes de pasar al contenedor, y la carpeta de los proyectos de solo lectura" '[ "$(grep -n "nexum-media" "$DOCKER_WEB_DIR/conf/sitios/wpmedia.conf" | head -1 | cut -d: -f1)" -lt "$(grep -n "ProxyPass /" "$DOCKER_WEB_DIR/conf/sitios/wpmedia.conf" | head -1 | cut -d: -f1)" ] && grep -qF "\"$HTDOCS_DIR:/opt/lampp/htdocs:ro\"" "$DOCKER_WEB_DIR/compose.yaml"'
    o=$(media_project wpmedia quitar 2>&1)
    check "imagenes: quitarlo, fuera tambien del Apache de Docker" '! grep -q "nexum-media" "$DOCKER_WEB_DIR/conf/sitios/wpmedia.conf"'
    # ps-imagenes con la BBDD de la tienda solo en Docker (y su dominio de produccion guardado)
    is_prestashop() { [ "$1" == tienda ]; }
    ps_config() { echo "ps_tienda|ps_"; }
    db_connect() { echo "XAMPP/LAMPP parado"; return 1; }
    db_exists() { return 1; }
    docker_ready() { return 0; }
    o=$(DRY=1 ps_images tienda 2>&1)
    check "ps-imagenes: con la BBDD de la tienda en Docker y su dominio de produccion" 'grep -q "Con la BBDD de la tienda en Docker" <<< "$o" && ! grep -q "no esta en" <<< "$o" && ! grep -q "No se sabe el dominio" <<< "$o"'
    docker_conf_set tienda PRODUCCION ""
    o=$(DRY=1 ps_images tienda 2>&1)
    check "ps-imagenes: sin dominio de produccion, lo pide (como segundo argumento)" 'grep -q "lvm-instalador ps-imagenes tienda <dominio de produccion>" <<< "$o"'
    o=$(DRY=1 ps_images tienda https://tienda.es/ 2>&1)
    check "ps-imagenes: con el dominio dicho, sigue" '! grep -q "No se sabe el dominio" <<< "$o" && grep -q "Con la BBDD de la tienda en Docker" <<< "$o"'
    docker_conf_set tienda PRODUCCION tienda.es
    unset -f docker_ready
    extract "$SRC" docker_ready
fi

# --- DNS comodin de *.docker.test (Mac 1.40.1) ---
if declare -F docker_dns_activate > /dev/null; then
    DOCKER_DNS_SCRIPT=$W/dns/nexum-dns.py DOCKER_DNS_PLIST=$W/dns/dev.hexer.nexum-dns.plist DOCKER_DNS_RESOLVER=$W/dns/resolver/docker.test
    dscacheutil() { :; }
    killall() { :; }
    printf '#!/bin/sh\n' > "$W/python3-xcode" && chmod 755 "$W/python3-xcode"
    xcrun() { echo "$W/python3-xcode"; }
    docker_ready() { return 0; }
    # (la tienda, en marcha; su dominio sigue siendo el de antes)
    docker_state() { echo marcha; }
    printf 'IP=127.0.0.5\nHTTP=80\nHTTPS=443\n' > "$DOCKER_WEB_FILE"
    docker_web_hosts poner pma.docker.local tienda.docker.local
    check "dns: por defecto, *.docker.local en /etc/hosts" '[ "$(docker_web_tld)" == docker.local ] && ! docker_dns_on && [ "$(docker_web_domain tienda 8.1)" == tienda.docker.local ]'
    reset
    o=$( docker_dns_works() { return 1; }; docker_dns_activate 2>&1 ); rc=$?
    check "dns: si no contesta, se quita y todo sigue como estaba" '[ $rc -ne 0 ] && grep -q "no contesta" <<< "$o" && [ ! -e "$DOCKER_DNS_PLIST" ] && [ ! -e "$DOCKER_DNS_RESOLVER" ] && [ "$(docker_web_tld)" == docker.local ] && grep -q "tienda.docker.local" "$HOSTS_FILE"'
    reset
    o=$( docker_dns_works() { return 0; }; docker_dns_activate 2>&1 ); rc=$?
    check "dns: activar pide la contraseña y termina bien" '[ $rc -eq 0 ] && [ "$(head -1 "$W/hecho.log")" == sudo_first ] && grep -q "Listo" <<< "$o"'
    check "dns: el servicio del sistema, con nobody, solo en 127.0.0.1, con la direccion del Apache de Docker" 'tr -d " \n" < "$DOCKER_DNS_PLIST" | grep -qF "<string>$W/python3-xcode</string><string>-I</string><string>$DOCKER_DNS_SCRIPT</string><string>127.0.0.1</string><string>5354</string><string>docker.test</string><string>127.0.0.5</string>" && tr -d " \n" < "$DOCKER_DNS_PLIST" | grep -q "<key>UserName</key><string>nobody</string>" && grep -q "launchctl bootstrap system" "$W/hecho.log"'
    check "dns: macOS le pregunta solo lo de docker.test (/etc/resolver)" '[ "$(cat "$DOCKER_DNS_RESOLVER")" == "$(printf "nameserver 127.0.0.1\nport 5354")" ]'
    check "dns: web.conf con docker.test y el DNS" '[ "$(docker_web_tld)" == docker.test ] && docker_dns_on && grep -qx IP=127.0.0.5 "$DOCKER_WEB_FILE"'
    check "dns: la tienda pasa a tienda.docker.test (y su dominio en su BBDD)" 'grep -qx DOMINIO=tienda.docker.test "$T/proyecto.conf" && grep -qF "SET domain = '"'"'tienda.docker.test'"'"'" "$W/sql.log"'
    check "dns: su PHP en marcha, rehecho con la configuracion nueva (y su dominio)" 'grep -q "compose .* up -d --force-recreate php81" "$W/docker.log" && grep -qF "NEXUM_DOMAIN: \"tienda.docker.test\"" "$T/compose.yaml"'
    check "dns: sus lineas de /etc/hosts fuera, sin poner otras (web.local y lo de siempre, igual)" '! grep -q "docker.local" "$HOSTS_FILE" && ! grep -q "docker.test" "$HOSTS_FILE" && grep -qx "127.0.0.1 tienda.es www.tienda.es" "$HOSTS_FILE"'
    check "dns: el certificado vale tambien para *.docker.test" 'openssl x509 -in "$DOCKER_WEB_DIR/certs/docker.local.crt" -noout -text | grep -q "DNS:\*\.docker\.test" && openssl x509 -in "$DOCKER_WEB_DIR/certs/docker.local.crt" -noout -text | grep -q "DNS:\*\.docker\.local"'
    check "dns: el Apache de Docker con los dominios nuevos (y phpMyAdmin en pma.docker.test)" 'grep -q "ServerName tienda.docker.test" "$DOCKER_WEB_DIR/conf/sitios/tienda.conf" && grep -q "ServerName pma.docker.test" "$DOCKER_WEB_DIR/conf/sitios/001-phpmyadmin.conf" && grep -qF "PMA_ABSOLUTE_URI: \"https://pma.docker.test/\"" "$DOCKER_WEB_DIR/compose.yaml"'
    check "dns: gui-docker lo dice" 'gui_docker | grep -qE "^W\|127\.0\.0\.5\|80\|443\|[a-z?]*\|[01]\|docker\.test\|1$"'
    reset
    mkdir -p "$HTDOCS_DIR/nuevo" && printf "<?php\ndefine( 'DB_NAME', 'x' );\n" > "$HTDOCS_DIR/nuevo/wp-config.php"
    o=$(docker_web_create nuevo 8.4 10.11 2>&1); rc=$?
    check "dns: un proyecto nuevo, en .docker.test, sin contraseña ni /etc/hosts" '[ $rc -eq 0 ] && grep -qx DOMINIO=nuevo-php84.docker.test "$DOCKER_DIR/nuevo/proyecto.conf" && ! grep -qs "^sudo_first$\|^hosts$" "$W/hecho.log" && ! grep -q nuevo "$HOSTS_FILE"'
    reset
    o=$(docker_web_add nuevo 8.3 2>&1); rc=$?
    check "dns: otra version de PHP, sin contraseña ni /etc/hosts" '[ $rc -eq 0 ] && ! grep -qs "^sudo_first$\|^hosts$" "$W/hecho.log" && grep -qF "https://nuevo-php83.docker.test" "$DOCKER_DIR/nuevo/config-83.php"'
    reset
    o=$(docker_dns_deactivate 2>&1); rc=$?
    check "dns: quitarlo: fuera el servicio y los dominios .docker.test vuelven a /etc/hosts" '[ $rc -eq 0 ] && [ ! -e "$DOCKER_DNS_PLIST" ] && [ ! -e "$DOCKER_DNS_RESOLVER" ] && ! docker_dns_on && grep -qE "^127\.0\.0\.5 .*nuevo-php83\.docker\.test" "$HOSTS_FILE" && grep -qE "^127\.0\.0\.5 .*pma\.docker\.test" "$HOSTS_FILE"'
    # El DNS de verdad, con tu usuario en un puerto alto: *.docker.test a la direccion, lo demas rechazado
    printf '%s\n' "$DOCKER_DNS_PY" > "$W/nexum-dns.py"
    PORT=$(python3 -c 'import socket; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
    python3 -I "$W/nexum-dns.py" 127.0.0.1 "$PORT" docker.test 127.0.0.5 & DNSP=$!
    sleep 0.6
    ask() { python3 -c '
import socket, struct, sys
name, qtype, port = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
q = struct.pack(">HHHHHH", 0x1234, 0x0100, 1, 0, 0, 0) + b"".join(bytes([len(l)]) + l.encode() for l in name.split(".")) + b"\0" + struct.pack(">HH", qtype, 1)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(2); s.sendto(q, ("127.0.0.1", port))
r = s.recv(512)
rcode, an = struct.unpack(">H", r[2:4])[0] & 15, struct.unpack(">H", r[6:8])[0]
print(rcode, an, socket.inet_ntoa(r[-4:]) if an else "-")' "$1" "$2" "$PORT"; }
    check "dns de verdad: <algo>.docker.test, a la direccion" '[ "$(ask blog-php83.docker.test 1)" == "0 1 127.0.0.5" ] && [ "$(ask PMA.Docker.Test 1)" == "0 1 127.0.0.5" ]'
    check "dns de verdad: IPv6, sin datos (no se queda esperando)" '[ "$(ask blog.docker.test 28)" == "0 0 -" ]'
    check "dns de verdad: lo demas, rechazado" '[ "$(ask google.com 1)" == "5 0 -" ] && [ "$(ask docker.testing.com 1)" == "5 0 -" ]'
    kill $DNSP 2> /dev/null
fi
exit $fail
