#!/bin/bash
# Panel de los proyectos en Docker (Linux 1.55.9 / Mac 1.39.19): el administrador de pruebas se pone en
# la BBDD del contenedor (docker-usuario-pruebas) con el mismo test_admin de siempre, por el cliente
# del contenedor como root y sin la contraseña en ninguna orden. Un MariaDB temporal hace de BBDD del
# contenedor (como en admin-pruebas.sh) y un dk falso pasa el «compose exec -T db sh -c ...» a un sh
# de aqui, con su cliente. Tambien que la copia de LAMPP lo pone al crear el proyecto y que la ventana
# tiene el visor con su Panel. Uso: docker-panel.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q '^function docker_test_admin() {' "$SRC" || { echo "  ok    (sin docker-usuario-pruebas)"; exit 0; }
MAC=0; grep -q '^function docker_sql() {' "$SRC" && MAC=1
MDB=$(mktemp -d "$TMPBASE/w-dkpanel.XXXX") || exit 1
SOCKD=$MDB; [ ${#SOCKD} -gt 80 ] && SOCKD=$(mktemp -d /tmp/lvm-dkp.XXXX)
trap 'kill "$(cat "$MDB/pid" 2> /dev/null)" 2> /dev/null; wait; rm -rf "$MDB"; [ "$SOCKD" != "$MDB" ] && rm -rf "$SOCKD"' EXIT
LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib /opt/lampp-8.2.4/bin/mysql_install_db --no-defaults --basedir=/opt/lampp-8.2.4 \
    --datadir="$MDB/data" --auth-root-authentication-method=normal > "$MDB/install.log" 2>&1 \
    || { echo "  FALLA no se ha podido crear el MariaDB temporal (mysql_install_db)"; tail -5 "$MDB/install.log"; exit 1; }
# (el cliente «de dentro del contenedor»: el que encuentra el sh -c por command -v mariadb)
mkdir -p "$MDB/bin"
printf '#!/bin/sh\necho "$MYSQL_PWD" >> %s/pwd.log\nLD_LIBRARY_PATH=/opt/lampp-8.2.4/lib exec /opt/lampp-8.2.4/bin/mysql --no-defaults -S %s/sock "$@"\n' \
    "$MDB" "$SOCKD" > "$MDB/bin/mariadb"
chmod +x "$MDB/bin/mariadb"
LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib /opt/lampp-8.2.4/sbin/mysqld --no-defaults --basedir=/opt/lampp-8.2.4 --datadir="$MDB/data" --socket="$SOCKD/sock" --skip-networking \
    --pid-file="$MDB/pid" --log-error="$MDB/err.log" > /dev/null 2>&1 &
m() { LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib /opt/lampp-8.2.4/bin/mysql --no-defaults -S "$SOCKD/sock" -uroot -N "$@"; }
for i in $(seq 50); do m -e 'SELECT 1' > /dev/null 2>&1 && break; sleep 0.2; done
m -e 'SELECT 1' > /dev/null 2>&1 || { echo "  FALLA el MariaDB temporal no arranca"; exit 1; }
trap 'm -e "SHUTDOWN" > /dev/null 2>&1; wait; rm -rf "$MDB"; [ "$SOCKD" != "$MDB" ] && rm -rf "$SOCKD"' EXIT

extract "$SRC" docker_test_admin docker_valid_slug docker_conf db_valid_name db_root_sql test_admin \
    wp_table_prefixes ps_table_prefix linked_folder || exit 1
[ $MAC -eq 1 ] && { extract "$SRC" docker_sql || exit 1; }
eval "$(grep -m1 '^DB_SAFE=(' "$SRC")"
eval "$(grep -m1 '^TEST_ADMIN_USER=' "$SRC")"; eval "$(grep -m1 '^TEST_ADMIN_PASS=' "$SRC")"
eval "$(grep -m1 "^TEST_ADMIN_BCRYPT=" "$SRC")"
DB_SYSTEM="information_schema|mysql|performance_schema|phpmyadmin|sys|test"
DRY=0 HTDOCS_DIR=$MDB/htdocs PROJECTS_FILE=$MDB/proyectos DOCKER_DIR=$MDB/docker DB_ROOT_CLIENT=()
# (el cliente de LAMPP no existe: todo tiene que ir por el del contenedor)
DB_CLIENT=$MDB/no-existe
active_name() { :; }
# dk falso: apunta la orden y, si es «compose ... exec -T db sh -c <script> <$0> <args>», la hace aqui,
# con la contraseña de root solo en el entorno (como en el contenedor)
dk() {
    printf '%s\n' "$*" >> "$MDB/dk.log"
    while [ $# -gt 0 ] && [ "$1" != "-T" ]; do shift; done
    [ "$1" == -T ] && [ "$2" == db ] && [ "$3" == sh ] && [ "$4" == -c ] || return 1
    shift 4
    PATH=$MDB/bin:$PATH MARIADB_ROOT_PASSWORD=$ROOT_PASS sh -c "$@"
}
ROOT_PASS=""
mkdir -p "$HTDOCS_DIR/web" "$HTDOCS_DIR/tienda" "$DOCKER_DIR/web" "$DOCKER_DIR/tienda"
printf 'CARPETA=web\nPHP=8.4\nMARIADB=11.8\nDOMINIO=web.docker.local\nBBDD=wp_web\nPUERTO_PMA=28080\n' > "$DOCKER_DIR/web/proyecto.conf"
printf 'CARPETA=tienda\nPHP=7.4\nMARIADB=10.4\nDOMINIO=tienda.docker.local\nBBDD=ps_tienda\nPUERTO_PMA=28081\n' > "$DOCKER_DIR/tienda/proyecto.conf"
printf 'DB_ROOT_PASS=SecretoDeRoot123\nDB_PASS=otra\n' > "$DOCKER_DIR/web/.env"

# --- WordPress en la BBDD del contenedor (la copia de LAMPP, sin el administrador de pruebas)
m -e "CREATE DATABASE wp_web; USE wp_web;
CREATE TABLE wp_options (option_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, option_name VARCHAR(191), option_value LONGTEXT, autoload VARCHAR(20));
CREATE TABLE wp_users (ID BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, user_login VARCHAR(60) NOT NULL DEFAULT '', user_pass VARCHAR(255) NOT NULL DEFAULT '',
  user_nicename VARCHAR(50) NOT NULL DEFAULT '', user_email VARCHAR(100) NOT NULL DEFAULT '', user_url VARCHAR(100) NOT NULL DEFAULT '',
  user_registered DATETIME NOT NULL DEFAULT '0000-00-00 00:00:00', user_activation_key VARCHAR(255) NOT NULL DEFAULT '', user_status INT NOT NULL DEFAULT 0,
  display_name VARCHAR(250) NOT NULL DEFAULT '', UNIQUE KEY (user_login));
CREATE TABLE wp_usermeta (umeta_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, user_id BIGINT UNSIGNED NOT NULL DEFAULT 0, meta_key VARCHAR(255), meta_value LONGTEXT);
INSERT INTO wp_users (user_login, user_pass, user_email, display_name) VALUES ('jefe', '\$P\$Breal', 'jefe@cliente.es', 'Jefe');"
out=$(docker_test_admin web); rc=$?
check "WordPress en Docker: dice A|wp con el usuario y la contraseña" '[ $rc -eq 0 ] && [ "$out" = "A|wp|local@local.test|local" ]'
check "WordPress en Docker: el administrador queda en la BBDD del contenedor" '[ "$(m wp_web -e "SELECT COUNT(*) FROM wp_users u JOIN wp_usermeta x ON x.user_id = u.ID AND x.meta_key = '"'"'wp_capabilities'"'"' WHERE u.user_login = '"'"'local@local.test'"'"' AND u.user_pass = MD5('"'"'local'"'"')")" = 1 ]'
check "WordPress en Docker: el administrador de verdad no se toca" '[ "$(m wp_web -e "SELECT user_pass FROM wp_users WHERE user_login = '"'"'jefe'"'"'")" = "\$P\$Breal" ]'
check "todo por el cliente del contenedor (compose exec -T db), nada por el de LAMPP" 'grep -q "compose --project-directory $DOCKER_DIR/web -f $DOCKER_DIR/web/compose.yaml exec -T db sh -c" "$MDB/dk.log"'
check "la contraseña de root no va en ninguna orden" '! grep -q SecretoDeRoot123 "$MDB/dk.log" && grep -q "MARIADB_ROOT_PASSWORD" "$MDB/dk.log"'
ROOT_PASS=SecretoDeRoot123
docker_test_admin web > /dev/null
check "la contraseña la toma el cliente de dentro (MYSQL_PWD de MARIADB_ROOT_PASSWORD)" 'tail -1 "$MDB/pwd.log" | grep -qx SecretoDeRoot123'
ROOT_PASS=""
check "otra vez: sin duplicarlo" '[ "$(m wp_web -e "SELECT COUNT(*) FROM wp_users WHERE user_login = '"'"'local@local.test'"'"'")" = 1 ]'
check "DB_ROOT_CLIENT vuelve a estar vacio (solo dentro de docker_test_admin)" '[ ${#DB_ROOT_CLIENT[@]} -eq 0 ]'

# --- PrestaShop 1.7 (bcrypt)
m -e "CREATE DATABASE ps_tienda; USE ps_tienda;
CREATE TABLE ps_shop_url (id_shop_url INT UNSIGNED AUTO_INCREMENT PRIMARY KEY, id_shop INT, domain VARCHAR(150));
CREATE TABLE ps_shop (id_shop INT UNSIGNED AUTO_INCREMENT PRIMARY KEY, name VARCHAR(64));
CREATE TABLE ps_employee_shop (id_employee INT UNSIGNED NOT NULL, id_shop INT UNSIGNED NOT NULL, PRIMARY KEY (id_employee, id_shop));
CREATE TABLE ps_employee (id_employee INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, id_profile INT UNSIGNED NOT NULL, id_lang INT UNSIGNED NOT NULL DEFAULT 0,
  lastname VARCHAR(255) NOT NULL, firstname VARCHAR(255) NOT NULL, email VARCHAR(255) NOT NULL, passwd VARCHAR(255) NOT NULL,
  last_passwd_gen TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, active TINYINT UNSIGNED NOT NULL DEFAULT 0,
  reset_password_token VARCHAR(40) DEFAULT NULL, reset_password_validity DATETIME DEFAULT NULL);
INSERT INTO ps_shop (name) VALUES ('Tienda');
INSERT INTO ps_shop_url (id_shop, domain) VALUES (1, 'tienda.docker.local');
INSERT INTO ps_employee (id_profile, id_lang, lastname, firstname, email, passwd, active) VALUES (1, 1, 'Jefe', 'Real', 'jefe@tienda.com', '\$2y\$10\$hashdeverdad', 1);"
out=$(docker_test_admin tienda); rc=$?
check "PrestaShop en Docker: dice A|ps" '[ $rc -eq 0 ] && [ "$out" = "A|ps|local@local.test|local" ]'
check "PrestaShop en Docker: SuperAdmin de pruebas con la contraseña bcrypt de «local»" '[ "$(m ps_tienda -e "SELECT CONCAT(id_profile, active, passwd) FROM ps_employee WHERE email = '"'"'local@local.test'"'"'")" = "11$TEST_ADMIN_BCRYPT" ]'

# --- Lo que no vale
: > "$MDB/dk.log"
docker_test_admin "web; rm -rf /" > /dev/null 2>&1; rc=$?
check "nombre de proyecto no valido: nada y sin llamar a Docker" '[ $rc -ne 0 ] && [ ! -s "$MDB/dk.log" ]'
docker_test_admin otro > /dev/null 2>&1; rc=$?
check "proyecto que no existe: nada" '[ $rc -ne 0 ] && [ ! -s "$MDB/dk.log" ]'
mkdir -p "$DOCKER_DIR/rara"; printf 'CARPETA=web\nBBDD=mysql\n' > "$DOCKER_DIR/rara/proyecto.conf"
docker_test_admin rara > /dev/null 2>&1; rc=$?
check "BBDD del sistema en su proyecto.conf: nada" '[ $rc -ne 0 ] && [ ! -s "$MDB/dk.log" ]'
DRY=1; out=$(docker_test_admin web); DRY=0
check "simulacion: lo dice y no toca Docker" 'grep -q "simulacion" <<< "$out" && [ ! -s "$MDB/dk.log" ]'

# --- El resto: al crearlo con una copia, la orden y la ventana
body=$(sed -n '/^function docker_create() {/,/^}/p' "$SRC")
check "docker-crear con --bd lo pone despues de cargar la copia" 'grep -q "admin=\$(docker_test_admin \"\$slug\")" <<< "$body"'
check "orden docker-usuario-pruebas" 'grep -q "^    docker-usuario-pruebas) docker_test_admin \"\$2\" ;;" "$SRC"'
# (en Linux, exportar-bd lo deja fuera desde la 1.54.1; el Mac no lo filtra)
[ $MAC -eq 0 ] && check "exportar-bd sigue dejando fuera al administrador de pruebas" 'sed -n "/^function export_database() {/,/^}/p" "$SRC" | grep -q "test_admin_filter \"\$db\""'
if [ $MAC -eq 1 ]; then
    check "ventana: visor de cada proyecto en Docker, con su Panel por docker-usuario-pruebas" 'grep -q "func visor(_ p: DockerProject, _ g: DockerGroup)" "$SRC" && grep -q "\"docker-usuario-pruebas\", p.slug" "$SRC" && grep -q "site: \"https://\\\\(p.domain)\"" "$SRC"'
    check "ventana: «Montar en Docker» en la fila de los proyectos con contenedores" 'grep -q "Text(\"Montar en Docker\")" "$SRC"'
else
    check "ventana: visor de cada proyecto en Docker, con su Panel por docker-usuario-pruebas" 'grep -q "def nv_docker_visor(self, p, items):" "$SRC" && grep -q "\"docker-usuario-pruebas\", p\[\"slug\"\]" "$SRC" && grep -q "self.open_admin_login(akind, admin, self.dk_url(p\[\"domain\"\])" "$SRC"'
    check "ventana: los botones del visor se apagan con el proyecto parado" 'grep -q "wb.set_sensitive(up)" "$SRC" && grep -q "adm.set_sensitive(up and bool(admin))" "$SRC" && grep -q "pma.set_sensitive(up and pma_ok)" "$SRC"'
fi
exit $fail
