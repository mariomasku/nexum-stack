#!/bin/bash
# Prueba de la 1.54.1: la BBDD descargada (exportar-bd, copiar-bd) no lleva el administrador de
# pruebas (local@local.test) de WordPress ni de PrestaShop, y la BBDD de trabajo no cambia. Contra un
# MariaDB temporal (el de la 8.2.4, sin red), como volcados.sh. Uso: admin-fuera.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q '^function test_admin_filter() {' "$SRC" || { echo "  ok    (sin filtro del administrador de pruebas)"; exit 0; }
[ -x /opt/lampp-8.2.4/sbin/mysqld ] || { echo "  ok    (sin /opt/lampp-8.2.4: no se prueba)"; exit 0; }
MDB=$(mktemp -d "$TMPBASE/w-adm.XXXX") || exit 1
SOCKD=$MDB; [ ${#SOCKD} -gt 80 ] && SOCKD=$(mktemp -d /tmp/lvm-adm.XXXX)
LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib /opt/lampp-8.2.4/bin/mysql_install_db --no-defaults --basedir=/opt/lampp-8.2.4 \
    --datadir="$MDB/data" --auth-root-authentication-method=normal > "$MDB/install.log" 2>&1 \
    || { echo "  FALLA no se ha podido crear el MariaDB temporal"; rm -rf "$MDB"; exit 1; }
printf '#!/bin/sh\nLD_LIBRARY_PATH=/opt/lampp-8.2.4/lib exec /opt/lampp-8.2.4/bin/mysql --no-defaults -S %s/sock "$@"\n' "$SOCKD" > "$MDB/client"
printf '#!/bin/sh\nLD_LIBRARY_PATH=/opt/lampp-8.2.4/lib exec /opt/lampp-8.2.4/bin/mysqldump --no-defaults -S %s/sock "$@"\n' "$SOCKD" > "$MDB/dump"
chmod +x "$MDB/client" "$MDB/dump"
LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib /opt/lampp-8.2.4/sbin/mysqld --no-defaults --basedir=/opt/lampp-8.2.4 --datadir="$MDB/data" \
    --socket="$SOCKD/sock" --skip-networking --pid-file="$MDB/pid" --log-error="$MDB/err.log" > /dev/null 2>&1 &
DB_CLIENT=$MDB/client
for i in $(seq 50); do "$DB_CLIENT" -uroot -e 'SELECT 1' > /dev/null 2>&1 && break; sleep 0.2; done
trap '"$DB_CLIENT" -uroot -e "SHUTDOWN" > /dev/null 2>&1; wait; rm -rf "$MDB"; [ "$SOCKD" != "$MDB" ] && rm -rf "$SOCKD"' EXIT
"$DB_CLIENT" -uroot -e 'SELECT 1' > /dev/null 2>&1 || { echo "  FALLA el MariaDB temporal no arranca"; exit 1; }
extract "$SRC" test_admin test_admin_filter wp_table_prefixes ps_table_prefix linked_folder || exit 1
eval "$(grep -m1 '^TEST_ADMIN_USER=' "$SRC")"; eval "$(grep -m1 '^TEST_ADMIN_PASS=' "$SRC")"
eval "$(grep -m1 "^TEST_ADMIN_BCRYPT=" "$SRC")"
DRY=0 DB_SAFE=() HTDOCS_DIR=$MDB/htdocs PROJECTS_FILE=$MDB/proyectos
active_name() { echo 8.4; }
m() { "$DB_CLIENT" -uroot -N "$@"; }
m -e "CREATE DATABASE tienda"
m tienda << 'SQL'
CREATE TABLE xy_options (option_id INT PRIMARY KEY, option_name VARCHAR(64), option_value TEXT);
CREATE TABLE xy_users (ID BIGINT AUTO_INCREMENT PRIMARY KEY, user_login VARCHAR(60) NOT NULL, user_pass VARCHAR(255), user_nicename VARCHAR(50),
    user_email VARCHAR(100), user_url VARCHAR(100), user_registered DATETIME, user_activation_key VARCHAR(255), user_status INT, display_name VARCHAR(250));
CREATE TABLE xy_usermeta (umeta_id BIGINT AUTO_INCREMENT PRIMARY KEY, user_id BIGINT NOT NULL DEFAULT 0, meta_key VARCHAR(255), meta_value LONGTEXT);
INSERT INTO xy_users (user_login, user_pass, user_email, display_name) VALUES ('admin', 'x', 'admin@tienda.es', 'Admin'), ('cliente', 'y', 'c@tienda.es', 'Cliente');
INSERT INTO xy_usermeta (user_id, meta_key, meta_value) VALUES (1, 'xy_capabilities', 'a:1:{s:13:"administrator";b:1;}'), (2, 'nickname', 'cliente');
CREATE TABLE ps_employee (id_employee INT AUTO_INCREMENT PRIMARY KEY, id_profile INT, id_lang INT, lastname VARCHAR(255), firstname VARCHAR(255),
    email VARCHAR(255) NOT NULL, passwd VARCHAR(255), last_passwd_gen DATETIME, active TINYINT);
CREATE TABLE ps_employee_shop (id_employee INT, id_shop INT, PRIMARY KEY (id_employee, id_shop));
CREATE TABLE ps_shop (id_shop INT PRIMARY KEY, name VARCHAR(64));
CREATE TABLE ps_shop_url (id_shop_url INT PRIMARY KEY, id_shop INT, domain VARCHAR(150));
CREATE TABLE ps_configuration (id_configuration INT PRIMARY KEY, name VARCHAR(254), value TEXT);
INSERT INTO ps_shop VALUES (1, 'Tienda');
INSERT INTO ps_shop_url VALUES (1, 1, 'tienda.es');
INSERT INTO ps_employee VALUES (1, 1, 1, 'Jefe', 'La', 'jefa@tienda.es', '$2y$10$abc', NOW(), 1);
INSERT INTO ps_employee_shop VALUES (1, 1);
SQL
out=$(test_admin tienda)
check "el administrador de pruebas esta en la BBDD de trabajo (WordPress y PrestaShop)" 'grep -q "^A|wp|" <<< "$out" && grep -q "^A|ps|" <<< "$out"'
before=$(m tienda -e "CHECKSUM TABLE xy_users, xy_usermeta, ps_employee, ps_employee_shop")
# Lo mismo que hace export_database con el MariaDB de la version
query=("$DB_CLIENT" -uroot -N) dump=("$MDB/dump" -uroot)
skip=() only=() wheres=()
test_admin_filter tienda
check "filtro: las cuatro tablas, aparte" '[ ${#only[@]} -eq 4 ] && [ ${#skip[@]} -eq 4 ]'
{ "${dump[@]}" --single-transaction --quick --triggers "${skip[@]}" tienda
  for i in "${!only[@]}"; do "${dump[@]}" --single-transaction --quick --triggers --where="${wheres[$i]}" tienda "${only[$i]}"; done; } > "$MDB/copia.sql" 2> "$MDB/dump.err"
check "el volcado se hace sin errores" '[ ! -s "$MDB/dump.err" ]'
# (solo sale en el comentario del --where que pone mysqldump)
check "el volcado no lleva local@local.test" '! grep -v "^-- WHERE: " "$MDB/copia.sql" | grep -q "local@local.test"'
m -e "CREATE DATABASE copia"; m copia < "$MDB/copia.sql"
check "la copia: los usuarios de WordPress, sin el de pruebas" '[ "$(m copia -e "SELECT GROUP_CONCAT(user_login ORDER BY ID) FROM xy_users")" == "admin,cliente" ]'
check "la copia: los usermeta de los demas, sin los del de pruebas" '[ "$(m copia -e "SELECT COUNT(*) FROM xy_usermeta")" == 2 ]'
check "la copia: los empleados de PrestaShop, sin el de pruebas (y en sus tiendas)" '[ "$(m copia -e "SELECT GROUP_CONCAT(email) FROM ps_employee")" == "jefa@tienda.es" ] && [ "$(m copia -e "SELECT COUNT(*) FROM ps_employee_shop")" == 1 ]'
check "la copia: el resto de tablas, entero" '[ "$(m copia -e "SELECT COUNT(*) FROM ps_shop_url")" == 1 ] && m copia -e "SHOW TABLES" | grep -qx xy_options'
check "la BBDD de trabajo no cambia (sigue con el de pruebas)" '[ "$(m tienda -e "CHECKSUM TABLE xy_users, xy_usermeta, ps_employee, ps_employee_shop")" == "$before" ] && [ "$(m tienda -e "SELECT COUNT(*) FROM xy_users WHERE user_login = \"local@local.test\"")" == 1 ]'
skip=() only=() wheres=()
test_admin_filter copia
check "una BBDD sin el administrador de pruebas: se descarga como siempre" '[ ${#only[@]} -eq 0 ] && [ ${#skip[@]} -eq 0 ]'
check "export_database usa el filtro en las dos formas (MariaDB en marcha y temporal)" 'grep -q "test_admin_filter \"\$db\"" "$SRC" && grep -q "query=(env LD_LIBRARY_PATH=" "$SRC" && grep -q "query=(\"\${DB_SAFE\[@\]}\" \"\$DB_CLIENT\" -uroot -N)" "$SRC"'
exit $fail
