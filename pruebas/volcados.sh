#!/bin/bash
# Pruebas de los volcados contra un MariaDB temporal (creado aqui con mysql_install_db de la 8.2.4 en
# una carpeta temporal, sin red: solo un socket; nunca el de una version).
# Uso: volcados.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
MDB=$(mktemp -d "$TMPBASE/w-mdb.XXXX") || exit 1
# (la ruta del socket no puede pasar de 107 caracteres: si la carpeta es larga, otra corta en /tmp)
SOCKD=$MDB; [ ${#SOCKD} -gt 80 ] && SOCKD=$(mktemp -d /tmp/lvm-mdb.XXXX)
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
extract "$SRC" db_lock_import_user db_kill_user db_root_cleanup wp_table_prefixes ps_table_prefix || exit 1
# (1.55.9 / Mac 1.39.19: el cliente de root, por db_root_sql, que tambien vale para un contenedor)
grep -q '^function db_root_sql() {' "$SRC" && { extract "$SRC" db_root_sql || exit 1; DB_ROOT_CLIENT=(); }
eval "$(sed -n "/^DB_DIRECTORY_PY='/,/^'\$/p" "$SRC")"
[ -n "$DB_DIRECTORY_PY" ] || { echo "  FALLA no esta DB_DIRECTORY_PY"; exit 1; }
mysql=("$DB_CLIENT" -uroot)
db=lvmprueba
"${mysql[@]}" -e "DROP DATABASE IF EXISTS $db; DROP DATABASE IF EXISTS otra_bd; CREATE DATABASE $db; CREATE DATABASE otra_bd;
    CREATE TABLE otra_bd.victima (v VARCHAR(10)); INSERT INTO otra_bd.victima VALUES ('limpio');
    DROP USER IF EXISTS 'lvm_bd_$db'@'localhost'; CREATE USER 'lvm_bd_$db'@'localhost' IDENTIFIED BY 'p';
    GRANT ALL PRIVILEGES ON \`$db\`.* TO 'lvm_bd_$db'@'localhost'"
imp=(env MYSQL_PWD=p "$DB_CLIENT" -ulvm_bd_$db --default-character-set=utf8mb4 --binary-mode --local-infile=0)
# Volcado con vistas (de un WordPress y de una tienda) y rutinas INVOKER: los prefijos no cuentan vistas
cat > "$MDB/w-inv.sql" <<'SQL'
CREATE TABLE t0 (a INT);
CREATE SQL SECURITY INVOKER VIEW `aaa` AS SELECT a FROM t0;
DROP TABLE t0;
DELIMITER ;;
CREATE FUNCTION f() RETURNS INT SQL SECURITY INVOKER MODIFIES SQL DATA BEGIN UPDATE otra_bd.victima SET v='pwned'; RETURN 1; END;;
CREATE PROCEDURE `p``x`() SQL SECURITY INVOKER BEGIN UPDATE otra_bd.victima SET v='pwned2'; END;;
DELIMITER ;
CREATE TABLE real_options (option_name VARCHAR(10), option_value VARCHAR(10));
CREATE TABLE wp_users (id INT);
INSERT INTO real_options VALUES ('siteurl','x');
CREATE SQL SECURITY INVOKER VIEW wp_options AS SELECT option_name, option_value, f() AS z FROM real_options;
CREATE SQL SECURITY INVOKER VIEW `zz``v` AS SELECT 1 AS uno;
CREATE TABLE ps_shop_url0 (a INT);
CREATE SQL SECURITY INVOKER VIEW ps_shop_url AS SELECT 1 AS domain;
SQL
"${imp[@]}" $db < "$MDB/w-inv.sql" 2>&1 | head -3
check "wp_table_prefixes no cuenta vistas" '[ -z "$(wp_table_prefixes $db)" ]'
check "ps_table_prefix no cuenta vistas" '[ -z "$(ps_table_prefix $db)" ]'
# Volcado normal: nada que avisar
"${mysql[@]}" -e "DROP DATABASE $db; CREATE DATABASE $db"
printf 'CREATE TABLE wp_options (a INT);\nCREATE TABLE wp_users (a INT);\nCREATE VIEW v AS SELECT 1;\n' | "${imp[@]}" $db
check "volcado normal: prefijo wp_" '[ "$(wp_table_prefixes $db)" = wp_ ]'
# Prefijos: los que traen las tablas (nunca se cambian). Varios WordPress y varias tiendas en la base
"${mysql[@]}" -e "CREATE TABLE $db.xyz_options (a INT); CREATE TABLE $db.xyz_users (a INT);
    CREATE TABLE $db.ps_shop_url (a INT); CREATE TABLE $db.tienda2_shop_url (a INT)"
check "varios WordPress: los dos prefijos" '[ "$(wp_table_prefixes $db | paste -sd" ")" = "wp_ xyz_" ]'
check "varias tiendas: el mas corto" '[ "$(ps_table_prefix $db)" = ps_ ]'
check "varias tiendas: el que ya usaba su configuracion, si la base lo tiene" '[ "$(ps_table_prefix $db tienda2_)" = tienda2_ ] && [ "$(ps_table_prefix $db otro_)" = ps_ ]'
check "varias tiendas: un prefijo preferido raro no entra en la consulta" '[ "$(ps_table_prefix $db "x'"'"' OR 1=1 -- ")" = ps_ ]'
"${mysql[@]}" -e "DROP TABLE $db.xyz_options, $db.xyz_users, $db.ps_shop_url, $db.tienda2_shop_url"
# Un usuario lvm_bd_<base> de antes que se quedo sin bloquear (db_drop_import_users): evento ya en marcha
# (planificador encendido) que vuelve a crear algo INVOKER, y paquete INVOKER (10.4); root lo repasa
"${mysql[@]}" -e "SET GLOBAL event_scheduler = ON"
"${mysql[@]}" -e "GRANT ALL PRIVILEGES ON \`$db\`.* TO 'lvm_bd_$db'@'localhost'; ALTER USER 'lvm_bd_$db'@'localhost' IDENTIFIED BY 'p' ACCOUNT UNLOCK"
"${imp[@]}" $db <<'SQL' 2>&1 | head -3
DELIMITER //
CREATE EVENT ev_lento ON SCHEDULE AT CURRENT_TIMESTAMP DO BEGIN DO SLEEP(3); CREATE SQL SECURITY INVOKER VIEW v_tarde AS SELECT 1 AS x; END;
//
SET sql_mode = ORACLE;
//
CREATE PACKAGE pk SQL SECURITY INVOKER AS FUNCTION f RETURN INT; END;
//
CREATE PACKAGE BODY pk SQL SECURITY INVOKER AS FUNCTION f RETURN INT AS BEGIN RETURN 1; END; END;
//
DELIMITER ;
SQL
sleep 1
check "el evento lento esta en marcha (si no, la prueba no vale)" '"${mysql[@]}" -N -e "SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE USER=\"lvm_bd_$db\"" | grep -qv "^0$"'
check "el paquete INVOKER existe (si no, la prueba no vale)" '"${mysql[@]}" -N -e "SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA=\"$db\" AND ROUTINE_TYPE LIKE \"PACKAGE%\"" | grep -q "^2$"'
db_kill_user lvm_bd_$db "${mysql[@]}"
db_lock_import_user lvm_bd_$db "${mysql[@]}"
out=$(db_root_cleanup $db "${mysql[@]}")
echo "$out" | sed 's/^/    | /'
sleep 4
left=$("${mysql[@]}" -N -e "SELECT COUNT(*) FROM information_schema.VIEWS WHERE TABLE_SCHEMA='$db' AND SECURITY_TYPE='INVOKER'; SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='$db' AND SECURITY_TYPE='INVOKER'; SELECT COUNT(*) FROM information_schema.EVENTS WHERE EVENT_SCHEMA='$db'" | paste -sd+ | bc)
check "evento en marcha cortado (KILL USER): no crea la vista despues" '! "${mysql[@]}" -N -e "SHOW TABLES FROM $db LIKE \"v_tarde\"" | grep -q .'
check "paquete INVOKER (MariaDB 10.4) borrado por root, sin INVOKER ni eventos" '[ "$left" = 0 ]'
check "al bloquear se quitan crear vistas, rutinas y eventos" '"${mysql[@]}" -N -e "SHOW GRANTS FOR \"lvm_bd_$db\"@\"localhost\"" | grep -v "CREATE VIEW" | grep -q "ON \`$db\`"'
check "repaso de root sin nada que quitar: sin avisos" '[ -z "$(db_root_cleanup $db "${mysql[@]}")" ]'
"${mysql[@]}" -e "SET GLOBAL event_scheduler = OFF"
db_lock_import_user lvm_bd_$db "${mysql[@]}"
check "usuario bloqueado al final" '! env MYSQL_PWD=p "$DB_CLIENT" -ulvm_bd_$db -e "SELECT 1" > /dev/null 2>&1'
"${mysql[@]}" -e "DROP DATABASE $db; DROP DATABASE otra_bd; DROP USER 'lvm_bd_$db'@'localhost'"
rm -f "$MDB/w-inv.sql"
exit $fail
