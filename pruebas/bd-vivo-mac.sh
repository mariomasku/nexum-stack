#!/bin/bash
# BBDD de XAMPP-X en Docker, en vivo (Mac 1.40.1): un WordPress de Docker usa la BBDD de una version XAMPP-X
# (la misma que web.local) por un puente hasta su puerto en el Mac (host.docker.internal), con el usuario de
# su wp-config.php; su MariaDB se arranca sola (con tu usuario, en otro puerto) si no esta en marcha y se
# para al dejar de usarla; al activar esa version, su puente pasa al 3306. Con Docker y MariaDB falsos.
# Uso: bd-vivo-mac.sh <lvm-instalador.sh del Mac>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-bdvivomac.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
grep -q '^function docker_db_mode() {' "$SRC" && grep -q "LVM_SWIFT" "$SRC" || { echo "  ok    (sin la BBDD de XAMPP-X en vivo)"; exit 0; }
extract "$SRC" lampp_bd_owner lampp_bd_xdir lampp_bd_data lampp_bd_bridge lampp_bd_port lampp_bd_free_port lampp_bd_up \
    lampp_bd_bridge_up lampp_bd_users lampp_bd_stop_own lampp_bd_release lampp_bd_handover lampp_bd_retarget lampp_bd_keep \
    lampp_bd_creds docker_db_mode docker_conf docker_conf_set valid_version_name || exit 1
DRY=0 BASE_DIR=$W/apps HTDOCS_DIR=$W/htdocs DOCKER_DIR=$W/docker LAMPP_BD_MARK_DIR=$W/docker/lampp-bd PORT_MYSQL=3306
LAMPP_BD_BRIDGE_IMAGE=mariadb:11.8 LAMPP_BD_PORTS="3310 3312"
X=$BASE_DIR/XAMPP-8.4.27/xamppfiles
mkdir -p "$X/var/mysql" "$X/mysql/bin" "$X/etc" "$HTDOCS_DIR/blog" "$DOCKER_DIR/blog"
printf '#!/bin/bash\necho "mariadbd $*" >> "%s/hecho.log"; touch "%s/viva"; echo 4242 > "%s/var/mysql/mysqld.pid"\n' "$W" "$W" "$X" > "$X/mysql/bin/mariadbd"; chmod 755 "$X/mysql/bin/mariadbd"
printf "<?php\ndefine( 'DB_NAME', 'wp_blog' );\ndefine( 'DB_USER', 'root' );\ndefine( 'DB_PASSWORD', '' );\n" > "$HTDOCS_DIR/blog/wp-config.php"
printf 'MODO=web\nCARPETA=blog\nTIPO=wp\nPHP=8.4\nACTIVA=8.4\nMARIADB=11.8\nBBDD=wp_blog\nUSUARIO=nx_wp_blog\nCONFIG=wp-config.php\n' > "$DOCKER_DIR/blog/proyecto.conf"
printf 'DB_PASS=docker123\n' > "$DOCKER_DIR/blog/.env"
docker_web_project() { [ -f "$DOCKER_DIR/$1/proyecto.conf" ]; }
docker_web_projects() { echo blog; }
docker_web_config() { echo "config $*" >> "$W/hecho.log"; }
docker_web_action() { :; }
docker_net() { :; }
UP="" LABEL=""
dk() { echo "dk $*" >> "$W/dk.log"; case "$1" in ps) printf '%s\n' $UP ;; inspect) echo "$LABEL" ;; esac; return 0; }
lampp_bd_alive() { [ -f "$W/viva" ]; }
netstat() { printf 'tcp4 0 0 127.0.0.1.3310 *.* LISTEN\n'; }
ps() { echo "/x/mariadbd --defaults-file=/x/my.cnf --port=$(cat "$LAMPP_BD_MARK_DIR/8.4.27" 2> /dev/null)"; }
kill() { echo "kill $*" >> "$W/hecho.log"; rm -f "$W/viva"; }

check "solo WordPress y versiones que existen" '! docker_db_mode blog lampp 9.9 > /dev/null 2>&1'
docker_db_mode blog lampp 8.4.27 > /dev/null 2>&1
check "en vivo: la version, su usuario y su contraseña del wp-config.php; lo de Docker, para volver" '[ "$(docker_conf blog LAMPP_BD)" == 8.4.27 ] && [ "$(docker_conf blog USUARIO)" == root ] && grep -qx "DB_PASS=" "$DOCKER_DIR/blog/.env" && [ "$(docker_conf blog BBDD_DOCKER)" == wp_blog ]'
: > "$W/hecho.log"
lampp_bd_up 8.4.27 > /dev/null
check "no esta en marcha: solo ella, con tu usuario, en un puerto libre de 127.0.0.1 (y se apunta)" 'grep -q "^mariadbd --defaults-file=$X/etc/my.cnf --port=3311 --bind-address=127.0.0.1$" "$W/hecho.log" && [ "$(cat "$LAMPP_BD_MARK_DIR/8.4.27")" == 3311 ]'
lampp_bd_bridge_up 8.4.27
check "puente: en la red de Docker, hasta su puerto en el Mac por host.docker.internal" 'grep -q "dk run -d --name nexum-lampp-bd-8-4-27 --network nexum --restart no --label nexum.lampp-bd=8.4.27 --label nexum.lampp-bd-puerto=3311 --entrypoint socat mariadb:11.8 TCP-LISTEN:3306,fork,reuseaddr TCP:host.docker.internal:3311" "$W/dk.log"'
: > "$W/dk.log"; LABEL="true 3311"
lampp_bd_bridge_up 8.4.27
check "puente ya en marcha con su puerto: no se toca" '! grep -q "dk run" "$W/dk.log"'
UP="nexum-blog-php84"; : > "$W/hecho.log"
lampp_bd_handover "$BASE_DIR/XAMPP-8.4.27" > /dev/null
check "activar esa version: su MariaDB de Docker se para (la de su .pid y su puerto) para que arranque la normal" 'grep -q "^kill " "$W/hecho.log" && [ ! -f "$LAMPP_BD_MARK_DIR/8.4.27" ]'
: > "$W/dk.log"; LABEL="true 3311"
lampp_bd_retarget "$BASE_DIR/XAMPP-8.4.27"
check "y su puente pasa al 3306 (el de siempre)" 'grep -q "TCP:host.docker.internal:3306" "$W/dk.log"'
: > "$W/hecho.log"
lampp_bd_keep "$BASE_DIR/XAMPP-8.4.27" > /dev/null
check "parar XAMPP-X con un proyecto de Docker usandola: su MariaDB vuelve, en otro puerto" 'grep -q "^mariadbd .*--port=3311 --bind-address=127.0.0.1" "$W/hecho.log"'
UP=""; : > "$W/hecho.log"; : > "$W/dk.log"
lampp_bd_release 8.4.27 blog > /dev/null
check "nadie la usa: fuera el puente y su MariaDB (sin contraseña)" 'grep -q "rm -f nexum-lampp-bd-8-4-27" "$W/dk.log" && grep -q "^kill " "$W/hecho.log" && [ ! -f "$LAMPP_BD_MARK_DIR/8.4.27" ]'
docker_db_mode blog docker > /dev/null 2>&1
check "volver a la copia de Docker" '[ -z "$(docker_conf blog LAMPP_BD)" ] && [ "$(docker_conf blog USUARIO)" == nx_wp_blog ] && grep -qx "DB_PASS=docker123" "$DOCKER_DIR/blog/.env"'
check "procesos: la MariaDB de Docker (en su puerto, apuntada) no sobra ni se cierra" 'grep -q "for_docker = (name_of(p\[\"cmd\"\]) in (\"mariadbd\", \"mysqld\") and port.isdigit()" "$SRC" && grep -qF "\$8 != 1 && (\$6 == 1 || all == \"--todos\")" "$SRC"'
check "XAMPP-X: al arrancar o activar, el traspaso y el puente al 3306; al parar o dejarla, sigue para Docker" '[ "$(grep -c "lampp_bd_handover \"" "$SRC")" -ge 2 ] && [ "$(grep -c "lampp_bd_retarget \"" "$SRC")" -ge 2 ] && [ "$(grep -c "lampp_bd_keep \"" "$SRC")" -ge 2 ]'
check "configuracion: el servidor de su BBDD es el puente; borrar nunca toca la de XAMPP-X" 'grep -q "server=\$(lampp_bd_bridge \"\$(docker_conf \"\$slug\" LAMPP_BD)\")" "$SRC" && grep -q "db=\$(docker_conf \"\$slug\" BBDD_DOCKER) user=\$(docker_conf \"\$slug\" USUARIO_DOCKER)" "$SRC"'
check "ventana (Mac): botón BBDD en la fila de un WordPress, «Cómo» al montarlo y el puente con su nombre" 'grep -q "model.dockerDbMode(p)" "$SRC" && grep -q "args += \[\"--bd\", src\[1\], \"--desde\", src\[0\], \"--en-vivo\"\]" "$SRC" && grep -q "title = \"Puente a la BBDD de XAMPP-\"" "$SRC" && grep -q "lampp-bd-\[0-9\]{1,2}-\[0-9\]{1,2}(-\[0-9\]{1,3})?)\$\"," "$SRC"'
check "datos (Mac): la version en vivo en la fila del proyecto y el puente agrupado con su nombre" 'grep -q "|\$(docker_conf \"\$p\" TIPO)|\$(docker_conf \"\$p\" PHP)|\$(docker_conf \"\$p\" LAMPP_BD)\"" "$SRC" && grep -q "lampp: isWeb ? field(f, 13) : \"\"" "$SRC"'
exit $fail
