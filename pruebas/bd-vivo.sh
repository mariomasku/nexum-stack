#!/bin/bash
# BBDD de LAMPP en Docker, en vivo (Linux 1.56.10): un WordPress de Docker usa la BBDD de una version LAMPP
# (la misma que web.local) por un puente hasta el socket de su MariaDB, con el usuario de su wp-config.php;
# su MariaDB se arranca sola (sin red) si no esta en marcha y se para al dejar de usarla; al activar esa
# version en LAMPP pasa a la normal. Con Docker, sudo y MariaDB falsos. Uso: bd-vivo.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-bdvivo.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
grep -q '^function docker_db_mode() {' "$SRC" || { echo "  ok    (sin la BBDD de LAMPP en vivo)"; exit 0; }
extract "$SRC" lampp_bd_owner lampp_bd_data lampp_bd_bridge lampp_bd_up lampp_bd_bridge_up lampp_bd_users \
    lampp_bd_release lampp_bd_handover lampp_bd_keep lampp_bd_creds docker_db_mode docker_conf docker_conf_set \
    valid_version_name || exit 1
DRY=0 SUDO="" TEST_DIR=$W/opt HTDOCS_DIR=$W/htdocs DOCKER_DIR=$W/docker LAMPP_BD_MARK_DIR=$W/docker/lampp-bd
LAMPP_BD_BRIDGE_IMAGE=mariadb:11.8
mkdir -p "$TEST_DIR/lampp-8.4/var/mysql" "$TEST_DIR/lampp-8.2/var/mysql" "$TEST_DIR/lampp-8.4/mysql/bin" "$HTDOCS_DIR/blog" "$HTDOCS_DIR/tienda" "$DOCKER_DIR/blog" "$DOCKER_DIR/tienda"
printf "<?php\n// define( 'DB_USER', 'comentado' );\ndefine( 'DB_NAME', 'wp_blog' );\ndefine('DB_USER', \"root\");\ndefine( 'DB_PASSWORD', 'cla\\\\'ve' );\ndefine( 'DB_HOST', 'localhost' );\n" > "$HTDOCS_DIR/blog/wp-config.php"
printf 'MODO=web\nCARPETA=blog\nTIPO=wp\nPHP=8.4\nACTIVA=8.4\nMARIADB=11.8\nBBDD=wp_blog\nUSUARIO=nx_wp_blog\nCONFIG=wp-config.php\n' > "$DOCKER_DIR/blog/proyecto.conf"
printf 'DB_PASS=docker123\n' > "$DOCKER_DIR/blog/.env"
printf 'MODO=web\nCARPETA=tienda\nTIPO=ps\nPHP=8.1\nACTIVA=8.1\nMARIADB=11.8\nBBDD=ps\nUSUARIO=nx_ps\n' > "$DOCKER_DIR/tienda/proyecto.conf"
# Lo de alrededor, falso
docker_web_project() { [ -f "$DOCKER_DIR/$1/proyecto.conf" ]; }
docker_web_projects() { echo blog tienda; }
data_owner() { [ "$1" == "$TEST_DIR/lampp-8.2" ] && echo 8.4; }
docker_web_config() { echo "config $*" >> "$W/hecho.log"; }
docker_web_action() { echo "accion $*" >> "$W/hecho.log"; }
active_dir() { cat "$W/activa" 2> /dev/null; }
lampp_running() { [ -f "$W/lampp-marcha" ]; }
UP=""
dk() { echo "dk $*" >> "$W/dk.log"; case "$1" in ps) printf '%s\n' $UP ;; inspect) [ -f "$W/puente" ] && echo true ;; esac; return 0; }
docker_net() { :; }
lampp_bd_alive() { [ -f "$W/viva-$1" ]; }
stat() { [ "$1" == -L ] && echo mysql || command stat "$@"; }
setsid() { echo "setsid $*" >> "$W/hecho.log"; touch "$W/viva-8.4"; }
printf '#!/bin/bash\necho "admin $* MYSQL_PWD=$MYSQL_PWD" >> "%s/hecho.log"\n' "$W" > "$TEST_DIR/lampp-8.4/mysql/bin/mariadb-admin"
chmod 755 "$TEST_DIR/lampp-8.4/mysql/bin/mariadb-admin"
printf '#!/bin/bash\n' > "$TEST_DIR/lampp-8.4/mysql/bin/mariadbd"; chmod 755 "$TEST_DIR/lampp-8.4/mysql/bin/mariadbd"
db_temp_pid() { echo 4242; }
ps() { echo "mariadbd --skip-networking --socket=x"; }
kill() { echo "kill $*" >> "$W/hecho.log"; rm -f "$W/viva-8.4"; }

check "credenciales: las del wp-config.php (sin los comentados; comillas y escapes)" '[ "$(lampp_bd_creds blog | head -1)" == "root|wp_blog" ] && [ "$(lampp_bd_creds blog | sed -n 2p)" == "cla'"'"'ve" ]'
check "solo WordPress: una tienda no (su dominio va en la BBDD)" '! docker_db_mode tienda lampp 8.4 > /dev/null 2>&1 && [ -z "$(docker_conf tienda LAMPP_BD)" ]'
check "una version que no existe, no" '! docker_db_mode blog lampp 9.9 > /dev/null 2>&1'
out=$(docker_db_mode blog lampp 8.2 2>&1)
check "en vivo: la version que tiene de verdad sus BBDD, su usuario y su contraseña" '[ "$(docker_conf blog LAMPP_BD)" == 8.4 ] && [ "$(docker_conf blog USUARIO)" == root ] && grep -qx "DB_PASS=cla'"'"'ve" "$DOCKER_DIR/blog/.env" && [ "$(stat -c %a "$DOCKER_DIR/blog/.env")" == 600 ]'
check "en vivo: lo de su copia de Docker se guarda para volver" '[ "$(docker_conf blog BBDD_DOCKER)" == wp_blog ] && [ "$(docker_conf blog USUARIO_DOCKER)" == nx_wp_blog ] && grep -qx "DB_PASS_DOCKER=docker123" "$DOCKER_DIR/blog/.env"'
check "en vivo: su configuracion de nuevo y, parado, no se arranca" 'grep -q "^config blog 8.4" "$W/hecho.log" && ! grep -q "^accion" "$W/hecho.log"'
docker_db_mode blog docker > /dev/null 2>&1
check "volver a la copia de Docker: su usuario y su contraseña de antes" '[ -z "$(docker_conf blog LAMPP_BD)" ] && [ "$(docker_conf blog USUARIO)" == nx_wp_blog ] && grep -qx "DB_PASS=docker123" "$DOCKER_DIR/blog/.env"'
docker_db_mode blog lampp 8.4 > /dev/null 2>&1

# Su MariaDB y su puente
: > "$W/hecho.log"
lampp_bd_up 8.4 > /dev/null
check "no esta en marcha: solo ella, sin red, con el dueño de sus datos y su socket de siempre (y se apunta)" 'grep -q "^setsid -f .*/lampp-8.4/mysql/bin/mariadbd --defaults-file=.*/lampp-8.4/etc/my.cnf --datadir=.*/lampp-8.4/var/mysql --user=mysql --skip-networking --socket=.*/lampp-8.4/var/mysql/mysql.sock" "$W/hecho.log" && [ -f "$LAMPP_BD_MARK_DIR/8.4" ]'
: > "$W/hecho.log"
lampp_bd_up 8.4 > /dev/null
check "ya en marcha (por ejemplo, la activa): no se toca" '[ ! -s "$W/hecho.log" ]'
lampp_bd_bridge_up 8.4
check "puente: en la red de Docker, su carpeta de solo lectura y socat hasta su socket" 'grep -q "dk run -d --name nexum-lampp-bd-8-4 --network nexum --restart no --label nexum.lampp-bd=8.4 -v .*/lampp-8.4/var/mysql:/run/nexum-bd:ro --entrypoint socat mariadb:11.8 TCP-LISTEN:3306,fork,reuseaddr UNIX-CONNECT:/run/nexum-bd/mysql.sock" "$W/dk.log"'
UP="nexum-blog-php84"
: > "$W/hecho.log"; : > "$W/dk.log"
lampp_bd_release 8.4
check "aun la usa un proyecto en marcha: sigue" '! grep -q "rm -f nexum-lampp-bd" "$W/dk.log" && [ -f "$LAMPP_BD_MARK_DIR/8.4" ]'
UP=""
lampp_bd_release 8.4 blog > /dev/null
check "nadie la usa: fuera el puente y su MariaDB, parada con el usuario del proyecto (sin contraseña de root)" 'grep -q "rm -f nexum-lampp-bd-8-4" "$W/dk.log" && grep -q "^admin --no-defaults -S .*/lampp-8.4/var/mysql/mysql.sock -u root shutdown MYSQL_PWD=cla'"'"'ve" "$W/hecho.log" && [ ! -f "$LAMPP_BD_MARK_DIR/8.4" ]'
: > "$W/hecho.log"; touch "$LAMPP_BD_MARK_DIR/8.4" "$W/lampp-marcha"; echo "$TEST_DIR/lampp-8.4" > "$W/activa"
lampp_bd_release 8.4 > /dev/null
check "la de la version activa con LAMPP en marcha: no se para (es la suya)" '! grep -q shutdown "$W/hecho.log"'
rm -f "$W/lampp-marcha"
# Al activar esa version en LAMPP
touch "$W/viva-8.4"; : > "$W/hecho.log"
lampp_bd_handover "$TEST_DIR/lampp-8.4" > /dev/null
check "activar en LAMPP la version que tenia Docker: su MariaDB sin red se para para que arranque la normal" 'grep -qx "kill 4242" "$W/hecho.log" && [ ! -f "$LAMPP_BD_MARK_DIR/8.4" ]'
: > "$W/hecho.log"
lampp_bd_handover "$TEST_DIR/lampp-8.2" > /dev/null
check "otra version (sin apuntar): no se toca nada" '[ ! -s "$W/hecho.log" ]'
UP="nexum-blog-php84"; : > "$W/hecho.log"; rm -f "$W/viva-8.4"
lampp_bd_keep "$TEST_DIR/lampp-8.4" > /dev/null
check "parar LAMPP con un proyecto de Docker usandola: su MariaDB vuelve, sin red" 'grep -q "^setsid -f .*--skip-networking" "$W/hecho.log"'

# Lo demas del programa
check "procesos: la MariaDB de Docker (sin red, apuntada) no sobra ni se cierra al parar LAMPP" 'grep -q "for_docker = (name in (\"mysqld\", \"mariadbd\") and \"--skip-networking\" in p\[\"argv\"\]" "$SRC" && grep -qF "\$8 != 1 && (\$6 == 1 || all == \"--todos\")" "$SRC"'
check "LAMPP: al arrancar o activar una version, el traspaso; al parar o dejarla, su MariaDB sigue para Docker" '[ "$(grep -c "lampp_bd_handover " "$SRC")" -ge 2 ] && [ "$(grep -c "lampp_bd_keep " "$SRC")" -ge 2 ]'
check "configuracion: el servidor de su BBDD es el puente" 'grep -q "server=\$(lampp_bd_bridge \"\$(docker_conf \"\$slug\" LAMPP_BD)\")" "$SRC"'
check "borrar un proyecto en vivo: nunca la BBDD de LAMPP" 'grep -q "db=\$(docker_conf \"\$slug\" BBDD_DOCKER) user=\$(docker_conf \"\$slug\" USUARIO_DOCKER)" "$SRC"'
check "pestaña Docker: el puente va con su nombre (no «sin proyecto»), con quien lo usa y parar o arrancar" 'grep -q "if (\$6 == \"\" && \$1 ~ /^nexum-lampp-bd-" "$SRC" && grep -q "title = \"Puente a la BBDD de lampp-%s (en vivo)\"" "$SRC" && grep -q "|lampp-bd-\[0-9\]{1,2}-\[0-9\]{1,2}(-\[0-9\]{1,3})?)\$ \]\]; then" "$SRC"'
check "la MariaDB comun no cuenta como usada por los que van en vivo" 'grep -q "\[ -z \"\$(docker_conf \"\$p\" LAMPP_BD)\" \] && used+=" "$SRC"'
check "ventana: cambiarla en la fila del proyecto y elegirla al montarlo en Docker" 'grep -q "self.nv_docker_db_mode(p), True)\] if web and p.get(\"kind\") == \"wp\"" "$SRC" && grep -q "(\[\"--en-vivo\"\] if live else \[\])" "$SRC"'
exit $fail
