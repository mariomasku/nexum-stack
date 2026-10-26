#!/bin/bash
# Pruebas del administrador de pruebas de los paneles (Linux 1.45.0 / Mac 1.33.0) contra un MariaDB
# temporal (como volcados.sh): WordPress, PrestaShop 1.7 (bcrypt) y 1.6 (md5 con _COOKIE_KEY_), sin
# tocar a los usuarios de verdad, y dos veces seguidas sin duplicarlo. Las contraseñas se comprueban
# con el PHP de la 8.4 (password_verify) y md5. Uso: admin-pruebas.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
MDB=$(mktemp -d "$TMPBASE/w-adm.XXXX") || exit 1
SOCKD=$MDB; [ ${#SOCKD} -gt 80 ] && SOCKD=$(mktemp -d /tmp/lvm-adm.XXXX)
trap 'kill "$(cat "$MDB/pid" 2> /dev/null)" 2> /dev/null; wait; rm -rf "$MDB"; [ "$SOCKD" != "$MDB" ] && rm -rf "$SOCKD"' EXIT
LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib /opt/lampp-8.2.4/bin/mysql_install_db --no-defaults --basedir=/opt/lampp-8.2.4 \
    --datadir="$MDB/data" --auth-root-authentication-method=normal > "$MDB/install.log" 2>&1 \
    || { echo "  FALLA no se ha podido crear el MariaDB temporal (mysql_install_db)"; tail -5 "$MDB/install.log"; exit 1; }
printf '#!/bin/sh\nLD_LIBRARY_PATH=/opt/lampp-8.2.4/lib exec /opt/lampp-8.2.4/bin/mysql --no-defaults -S %s/sock "$@"\n' "$SOCKD" > "$MDB/client"; chmod +x "$MDB/client"
DB_CLIENT=$MDB/client
LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib /opt/lampp-8.2.4/sbin/mysqld --no-defaults --basedir=/opt/lampp-8.2.4 --datadir="$MDB/data" --socket="$SOCKD/sock" --skip-networking \
    --pid-file="$MDB/pid" --log-error="$MDB/err.log" > /dev/null 2>&1 &
for i in $(seq 50); do "$DB_CLIENT" -uroot -e 'SELECT 1' > /dev/null 2>&1 && break; sleep 0.2; done
"$DB_CLIENT" -uroot -e 'SELECT 1' > /dev/null 2>&1 || { echo "  FALLA el MariaDB temporal no arranca"; exit 1; }
trap '"$DB_CLIENT" -uroot -e "SHUTDOWN" > /dev/null 2>&1; wait; rm -rf "$MDB"; [ "$SOCKD" != "$MDB" ] && rm -rf "$SOCKD"' EXIT
extract "$SRC" test_admin wp_table_prefixes ps_table_prefix || exit 1
# (1.55.9 / Mac 1.39.19: el cliente de root, por db_root_sql, que tambien vale para un contenedor)
grep -q '^function db_root_sql() {' "$SRC" && { extract "$SRC" db_root_sql || exit 1; DB_ROOT_CLIENT=(); }
# (la carpeta de la base: linked_folder desde la 1.51; antes, una linea de awk dentro de test_admin)
grep -q "^function linked_folder" "$SRC" && { extract "$SRC" linked_folder || exit 1; active_name() { :; }; }
eval "$(grep -m1 '^DB_SAFE=(' "$SRC")"
eval "$(grep -m1 '^TEST_ADMIN_USER=' "$SRC")"; eval "$(grep -m1 '^TEST_ADMIN_PASS=' "$SRC")"
eval "$(grep -m1 "^TEST_ADMIN_BCRYPT=" "$SRC")"
DRY=0 HTDOCS_DIR=$MDB/htdocs PROJECTS_FILE=$MDB/proyectos
m() { "$DB_CLIENT" -uroot -N "$@"; }
php() { LD_LIBRARY_PATH=/opt/lampp-8.4/lib /opt/lampp-8.4/bin/php -n "$@"; }

# --- WordPress (con prefijo propio) y un administrador de verdad que no se toca
m -e "CREATE DATABASE wp1; USE wp1;
CREATE TABLE xy_options (option_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, option_name VARCHAR(191), option_value LONGTEXT, autoload VARCHAR(20));
CREATE TABLE xy_users (ID BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, user_login VARCHAR(60) NOT NULL DEFAULT '', user_pass VARCHAR(255) NOT NULL DEFAULT '',
  user_nicename VARCHAR(50) NOT NULL DEFAULT '', user_email VARCHAR(100) NOT NULL DEFAULT '', user_url VARCHAR(100) NOT NULL DEFAULT '',
  user_registered DATETIME NOT NULL DEFAULT '0000-00-00 00:00:00', user_activation_key VARCHAR(255) NOT NULL DEFAULT '', user_status INT NOT NULL DEFAULT 0,
  display_name VARCHAR(250) NOT NULL DEFAULT '', UNIQUE KEY (user_login));
CREATE TABLE xy_usermeta (umeta_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, user_id BIGINT UNSIGNED NOT NULL DEFAULT 0, meta_key VARCHAR(255), meta_value LONGTEXT);
INSERT INTO xy_users (user_login, user_pass, user_email, display_name) VALUES ('jefe', '\$P\$Breal', 'jefe@cliente.es', 'Jefe');
INSERT INTO xy_usermeta (user_id, meta_key, meta_value) VALUES (1, 'xy_capabilities', 'a:1:{s:13:\"administrator\";b:1;}');"
out=$(test_admin wp1)
check "WordPress: dice A|wp con el usuario y la contraseña" '[ "$out" = "A|wp|local@local.test|local" ]'
check "WordPress: usuario local@local.test con md5 de «local»" '[ "$(m wp1 -e "SELECT user_pass FROM xy_users WHERE user_login = '"'"'local@local.test'"'"'")" = "$(printf local | md5sum | cut -d" " -f1)" ]'
check "WordPress: rol de administrador y nivel 10" '[ "$(m wp1 -e "SELECT COUNT(*) FROM xy_usermeta u JOIN xy_users s ON s.ID = u.user_id WHERE s.user_login = '"'"'local@local.test'"'"' AND ((u.meta_key = '"'"'xy_capabilities'"'"' AND u.meta_value LIKE '"'"'%administrator%'"'"') OR (u.meta_key = '"'"'xy_user_level'"'"' AND u.meta_value = '"'"'10'"'"'))")" = 2 ]'
check "WordPress: el administrador de verdad no se toca" '[ "$(m wp1 -e "SELECT CONCAT(user_pass, user_email) FROM xy_users WHERE user_login = '"'"'jefe'"'"'")" = "\$P\$Brealjefe@cliente.es" ]'
m wp1 -e "UPDATE xy_users SET user_pass = 'cambiada' WHERE user_login = 'local@local.test'"
test_admin wp1 > /dev/null
check "WordPress: otra vez: sin duplicar y con la contraseña de nuevo" '[ "$(m wp1 -e "SELECT COUNT(*), MAX(user_pass) FROM xy_users WHERE user_login = '"'"'local@local.test'"'"'" | tr "\t" " ")" = "1 $(printf local | md5sum | cut -d" " -f1)" ] && [ "$(m wp1 -e "SELECT COUNT(*) FROM xy_usermeta WHERE meta_key = '"'"'xy_capabilities'"'"'")" = 2 ]'

# --- PrestaShop 1.7 (bcrypt), con dos tiendas
ps_schema() {
    m -e "CREATE DATABASE $1; USE $1;
CREATE TABLE ps_shop_url (id_shop_url INT UNSIGNED AUTO_INCREMENT PRIMARY KEY, id_shop INT, domain VARCHAR(150));
CREATE TABLE ps_shop (id_shop INT UNSIGNED AUTO_INCREMENT PRIMARY KEY, name VARCHAR(64));
CREATE TABLE ps_employee_shop (id_employee INT UNSIGNED NOT NULL, id_shop INT UNSIGNED NOT NULL, PRIMARY KEY (id_employee, id_shop));
CREATE TABLE ps_employee (id_employee INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, id_profile INT UNSIGNED NOT NULL, id_lang INT UNSIGNED NOT NULL DEFAULT 0,
  lastname VARCHAR(255) NOT NULL, firstname VARCHAR(255) NOT NULL, email VARCHAR(255) NOT NULL, passwd VARCHAR($2) NOT NULL,
  last_passwd_gen TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, stats_date_from DATE DEFAULT NULL, bo_theme VARCHAR(32) DEFAULT NULL,
  bo_css VARCHAR(64) DEFAULT NULL, default_tab INT UNSIGNED NOT NULL DEFAULT 0, active TINYINT UNSIGNED NOT NULL DEFAULT 0,
  id_last_order INT UNSIGNED NOT NULL DEFAULT 0, reset_password_token VARCHAR(40) DEFAULT NULL, reset_password_validity DATETIME DEFAULT NULL);
INSERT INTO ps_shop (name) VALUES ('Tienda'), ('Outlet');
INSERT INTO ps_shop_url (id_shop, domain) VALUES (1, 'tienda.com');
INSERT INTO ps_employee (id_profile, id_lang, lastname, firstname, email, passwd, bo_theme, default_tab, active)
    VALUES (2, 1, 'Vende', 'Dor', 'vende@tienda.com', '$3', 'default', 7, 1), (1, 3, 'Jefe', 'Real', 'jefe@tienda.com', '$3', 'new-theme', 1, 1);
INSERT INTO ps_employee_shop VALUES (2, 1), (2, 2);"
}
ps_schema ps17 255 '$2y$10$hashdeverdad'
out=$(test_admin ps17)
check "PrestaShop 1.7: dice A|ps" '[ "$out" = "A|ps|local@local.test|local" ]'
row=$(m ps17 -e "SELECT id_profile, id_lang, active, firstname, lastname, bo_theme, default_tab, passwd FROM ps_employee WHERE email = 'local@local.test'")
check "PrestaShop 1.7: copia del SuperAdmin (perfil 1, su idioma y su tema) con nombre de pruebas" '[ "$(cut -f1-7 <<< "$row" | tr "\t" " ")" = "1 3 1 Pruebas Local new-theme 1" ]'
hash=$(cut -f8 <<< "$row")
check "PrestaShop 1.7: la contraseña «local» vale (password_verify)" '[ "$(php -r "echo password_verify(\"local\", \$argv[1]) ? 1 : 0;" "$hash")" = 1 ]'
check "PrestaShop 1.7: en las dos tiendas" '[ "$(m ps17 -e "SELECT COUNT(*) FROM ps_employee_shop s JOIN ps_employee e USING (id_employee) WHERE e.email = '"'"'local@local.test'"'"'")" = 2 ]'
check "PrestaShop 1.7: los de verdad no se tocan" '[ "$(m ps17 -e "SELECT COUNT(*) FROM ps_employee WHERE passwd = '"'"'\$2y\$10\$hashdeverdad'"'"'")" = 2 ]'
test_admin ps17 > /dev/null
check "PrestaShop 1.7: otra vez, sin duplicar" '[ "$(m ps17 -e "SELECT COUNT(*) FROM ps_employee WHERE email = '"'"'local@local.test'"'"'")" = 1 ]'

# --- PrestaShop 1.6: md5(_COOKIE_KEY_ + contraseña), con la clave de la carpeta recordada
ps_schema ps16 32 'abcdefabcdefabcdefabcdefabcdefab'
# (carpeta con un espacio en el nombre: se toma entera)
mkdir -p "$HTDOCS_DIR/tienda16 8.2/config"
printf "<?php\ndefine('_COOKIE_KEY_', 'K3yDePrueba1234');\n" > "$HTDOCS_DIR/tienda16 8.2/config/settings.inc.php"
echo "ps16=tienda16 8.2" > "$PROJECTS_FILE"
test_admin ps16 > /dev/null
check "PrestaShop 1.6: md5 de _COOKIE_KEY_ y «local»" '[ "$(m ps16 -e "SELECT passwd FROM ps_employee WHERE email = '"'"'local@local.test'"'"'")" = "$(printf K3yDePrueba1234local | md5sum | cut -d" " -f1)" ]'
ps_schema ps16b 32 'abcdefabcdefabcdefabcdefabcdefab'
out=$(test_admin ps16b); rc=$?
check "PrestaShop 1.6 sin su carpeta: no se crea y se avisa" '[ $rc -ne 0 ] && grep -q "_COOKIE_KEY_" <<< "$out" && [ "$(m ps16b -e "SELECT COUNT(*) FROM ps_employee WHERE email = '"'"'local@local.test'"'"'")" = 0 ]'

# --- Lo que no es WordPress ni PrestaShop, y nombres raros
m -e "CREATE DATABASE otra; CREATE TABLE otra.cosas (a INT)"
test_admin otra > /dev/null; rc=$?
check "una base que no es de WordPress ni PrestaShop: nada (1)" '[ $rc -eq 1 ] && [ "$(m -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = '"'"'otra'"'"'")" = 1 ]'
test_admin "wp1\`; DROP DATABASE wp1; --" > /dev/null 2>&1; rc=$?
check "nombre de base no valido: no se hace nada" '[ $rc -ne 0 ] && [ "$(m -e "SHOW DATABASES LIKE '"'"'wp1'"'"'")" = wp1 ]'
# Una vista con el nombre de la tabla de usuarios (del volcado) no se toca como root
m -e "CREATE DATABASE wpv; USE wpv; CREATE TABLE wp_options (a INT); CREATE TABLE real_users (ID INT); CREATE VIEW wp_users AS SELECT * FROM real_users; CREATE TABLE wp_usermeta (a INT)"
test_admin wpv > /dev/null; rc=$?
check "WordPress con wp_users vista: no se toca" '[ $rc -eq 1 ]'
check "el gestor lo llama al acabar de cargar un volcado" 'sed -n "/^function import_database() {/,/^}/p" "$SRC" | grep -q "admin=\$(test_admin \"\$db\" \"\$project\")"'
check "orden usuario-pruebas" 'grep -q "^    usuario-pruebas) test_admin \"\$2\" \"\$3\" ;;" "$SRC"'
exit $fail
