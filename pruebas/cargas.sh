#!/bin/bash
# importar-bd sobre una base que ya existe: siempre se vacia antes (con copia en ~/lvm-copias si
# tiene tablas), contra un MariaDB temporal (mysql_install_db de la 8.2.4 en una carpeta temporal,
# sin red: solo un socket; nunca el de una version). Volcados como los de phpMyAdmin: sin DROP TABLE.
# Uso: cargas.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
MAC=0; grep -qE '^    BASE_DIR=(/Applications|/Library/Nexum)$' "$SRC" && MAC=1
MDB=$(mktemp -d "$TMPBASE/w-carga.XXXX") || exit 1
SOCKD=$MDB; [ ${#SOCKD} -gt 80 ] && SOCKD=$(mktemp -d /tmp/lvm-mdb.XXXX)
trap 'kill "$(cat "$MDB/pid" 2> /dev/null)" 2> /dev/null; wait; rm -rf "$MDB"; [ "$SOCKD" != "$MDB" ] && rm -rf "$SOCKD"' EXIT
LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib /opt/lampp-8.2.4/bin/mysql_install_db --no-defaults --basedir=/opt/lampp-8.2.4 \
    --datadir="$MDB/data" --auth-root-authentication-method=normal > "$MDB/install.log" 2>&1 \
    || { echo "  FALLA no se ha podido crear el MariaDB temporal (mysql_install_db)"; tail -5 "$MDB/install.log"; exit 1; }
for p in mysql mysqldump; do
    printf '#!/bin/sh\nLD_LIBRARY_PATH=/opt/lampp-8.2.4/lib exec /opt/lampp-8.2.4/bin/%s --no-defaults -S %s/sock "$@"\n' "$p" "$SOCKD" > "$MDB/$p"
    chmod +x "$MDB/$p"
done
DB_CLIENT=$MDB/mysql
LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib /opt/lampp-8.2.4/sbin/mysqld --no-defaults --basedir=/opt/lampp-8.2.4 --datadir="$MDB/data" --socket="$SOCKD/sock" --skip-networking \
    --pid-file="$MDB/pid" --log-error="$MDB/err.log" > /dev/null 2>&1 &
for i in $(seq 50); do "$DB_CLIENT" -uroot -e 'SELECT 1' > /dev/null 2>&1 && break; sleep 0.2; done
"$DB_CLIENT" -uroot -e 'SELECT 1' > /dev/null 2>&1 || { echo "  FALLA el MariaDB temporal no arranca"; exit 1; }
trap '"$DB_CLIENT" -uroot -e "SHUTDOWN" > /dev/null 2>&1; wait; rm -rf "$MDB"; [ "$SOCKD" != "$MDB" ] && rm -rf "$SOCKD"' EXIT

extract "$SRC" import_database db_exists db_pass_hash db_drop_import_users db_kill_user db_neutralize_extras \
    db_neutralize_invoker db_lock_import_user db_root_cleanup || exit 1
[ $MAC -eq 1 ] && { extract "$SRC" human_size || exit 1; }
for v in DB_SAFE; do eval "$(grep -m1 "^$v=(" "$SRC")"; done
for v in INVOKER_PY DB_DIRECTORY_PY ZIP_SQL_PY; do
    eval "$(sed -n "/^$v='/,/^'\$/p" "$SRC")"
    [ -n "${!v}" ] || { echo "  FALLA no esta $v"; exit 1; }
done
db_valid_name() { true; }; valid_project() { true; }
run() { if [ "$DRY" -eq 1 ]; then echo "  [simulacion] $*"; else "$@"; fi; }
db_connect() { DB_FOLDER=prueba DB_VERSION=10.4; }
db_note_import() { :; }; test_admin() { :; }; import_project() { :; }
# (el stat del Mac es stat -f %z)
[ $MAC -eq 1 ] && stat() { if [ "$1" == -f ]; then command stat -c %s "$3"; else command stat "$@"; fi; }
# Linux: la copia la hace export_database (aqui, con el mysqldump del MariaDB temporal); Mac: el
# mysqldump de LVM_BD_VOLCADO
NOCOPY=0
export_database() {
    [ $NOCOPY -eq 0 ] || return 1
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] mysqldump $1 > $2"; return 0; }
    ( set -o pipefail; "$MDB/mysqldump" -uroot "$1" | gzip > "$2" ) || { rm -f "$2"; return 1; }
}
export LVM_BD_VOLCADO=$MDB/mysqldump
H=$MDB/casa; mkdir -p "$H"
sql() { "$DB_CLIENT" -uroot -N -e "$1" 2> /dev/null; }
load() { HOME=$H DRY=0 LVM_PROGRESO="" import_database "$@" < /dev/null 2>&1; }
copies() { ls "$H/lvm-copias" 2> /dev/null | grep -c -- "-wpz-antes-de-cargar-.*\.sql\.gz$"; }

# Volcado como el de phpMyAdmin: sin DROP TABLE
cat > "$MDB/volcado.sql" <<'SQL'
CREATE TABLE `claims` (`id` INT NOT NULL, `v` VARCHAR(10));
INSERT INTO `claims` VALUES (1,'a'),(2,'b'),(3,'c');
ALTER TABLE `claims` ADD PRIMARY KEY (`id`);
SQL
# Base que ya existe, con latin1, una tabla que el volcado ya no trae y las filas de una carga que
# fallo a medias (claims sin clave y repetida)
sql "CREATE DATABASE wpz CHARACTER SET latin1 COLLATE latin1_spanish_ci;
     CREATE TABLE wpz.vieja (x INT); INSERT INTO wpz.vieja VALUES (7);
     CREATE TABLE wpz.claims (id INT, v VARCHAR(10)); INSERT INTO wpz.claims VALUES (1,'a'),(1,'a'),(2,'b')"

out=$(load "$MDB/volcado.sql" wpz); rc=$?
check "carga sobre una base con tablas: termina bien" '[ $rc -eq 0 ]' || echo "$out" | tail -5
check "... no queda la tabla que el volcado ya no trae" '[ "$(sql "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=\"wpz\" AND TABLE_NAME=\"vieja\"")" = 0 ]'
check "... ni las filas de la carga a medias: 3 filas, con su clave primaria" '[ "$(sql "SELECT COUNT(*) FROM wpz.claims")" = 3 ] && [ "$(sql "SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=\"wpz\" AND TABLE_NAME=\"claims\" AND INDEX_NAME=\"PRIMARY\"")" = 1 ]'
check "... la base conserva su juego de caracteres" '[ "$(sql "SELECT DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME=\"wpz\"")" = latin1_spanish_ci ]'
f=$(ls "$H"/lvm-copias/*-wpz-antes-de-cargar-*.sql.gz 2> /dev/null | head -1)
check "... antes guarda una copia en ~/lvm-copias con lo que tenia (la tabla vieja)" '[ -n "$f" ] && gzip -dc "$f" | grep -q "CREATE TABLE \`vieja\`" && grep -qF "$f" <<< "$out"'
check "... ~/lvm-copias es solo tuya" '[ "$(command stat -c %a "$H/lvm-copias")" = 700 ]'

out=$(load "$MDB/volcado.sql" wpz); rc=$?
check "cargar el mismo volcado otra vez no suma filas ni falla (no lleva DROP TABLE)" '[ $rc -eq 0 ] && [ "$(sql "SELECT COUNT(*) FROM wpz.claims")" = 3 ]'

n=$(copies)
out=$(load "$MDB/volcado.sql" wpz --sin-copia); rc=$?
check "--sin-copia: vacia y carga sin guardar copia" '[ $rc -eq 0 ] && [ "$(copies)" = "$n" ] && [ "$(sql "SELECT COUNT(*) FROM wpz.claims")" = 3 ]'
out=$(load "$MDB/volcado.sql" wpz --vaciar); rc=$?
check "--vaciar se sigue admitiendo" '[ $rc -eq 0 ] && [ "$(sql "SELECT COUNT(*) FROM wpz.claims")" = 3 ]'

sql "CREATE DATABASE wpv"
n=$(ls "$H/lvm-copias" | wc -l)
out=$(load "$MDB/volcado.sql" wpv); rc=$?
check "base vacia: carga sin copia (no hay nada que guardar)" '[ $rc -eq 0 ] && [ "$(ls "$H/lvm-copias" | wc -l)" = "$n" ] && [ "$(sql "SELECT COUNT(*) FROM wpv.claims")" = 3 ]'

out=$(load "$MDB/volcado.sql" wpn --crear); rc=$?
check "--crear: crea la base y carga" '[ $rc -eq 0 ] && [ "$(sql "SELECT COUNT(*) FROM wpn.claims")" = 3 ]'

# Si no se puede guardar la copia, no se toca nada
sql "CREATE TABLE wpz.vieja (x INT)"
NOCOPY=1; export LVM_BD_VOLCADO=/bin/false
out=$(load "$MDB/volcado.sql" wpz); rc=$?
check "si no se puede guardar la copia, no se vacia ni se carga" '[ $rc -ne 0 ] && [ "$(sql "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=\"wpz\" AND TABLE_NAME=\"vieja\"")" = 1 ] && grep -q "no se ha cambiado nada" <<< "$out"'
NOCOPY=0; export LVM_BD_VOLCADO=$MDB/mysqldump

# Un fichero que no sirve no vacia la base
printf 'esto no es gzip' > "$MDB/malo.sql.gz"
out=$(load "$MDB/malo.sql.gz" wpz); rc=$?
check "un .gz roto no vacia la base" '[ $rc -ne 0 ] && [ "$(sql "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=\"wpz\" AND TABLE_NAME=\"vieja\"")" = 1 ]'

# Volcado que falla a medias: dice donde esta la copia de lo que habia
printf 'CREATE TABLE a (x INT);\nINSERT INTO noexiste VALUES (1);\n' > "$MDB/roto.sql"
out=$(load "$MDB/roto.sql" wpz); rc=$?
check "si el volcado falla, dice donde esta la copia de lo que habia" '[ $rc -ne 0 ] && grep -q "Lo que tenia antes esta en .*lvm-copias/.*-wpz-antes-de-cargar-" <<< "$out"'

# Simulacion: no cambia nada
t0=$(sql "SELECT GROUP_CONCAT(TABLE_NAME) FROM information_schema.TABLES WHERE TABLE_SCHEMA=\"wpz\"")
n=$(ls "$H/lvm-copias" | wc -l)
out=$(HOME=$H DRY=1 import_database "$MDB/volcado.sql" wpz < /dev/null 2>&1); rc=$?
check "--simular: no vacia ni guarda nada" '[ $rc -eq 0 ] && [ -n "$t0" ] && [ "$(sql "SELECT GROUP_CONCAT(TABLE_NAME) FROM information_schema.TABLES WHERE TABLE_SCHEMA=\"wpz\"")" = "$t0" ] && [ "$(ls "$H/lvm-copias" | wc -l)" = "$n" ]'

exit $fail
