#!/bin/bash
# Pruebas (Mac, 1.39.0) de gui-bbdd-tamanos con un cliente de MariaDB falso: mide con
# information_schema solo si el MariaDB de la version activa esta en marcha (gui_db_check ok), guarda
# lo medido en $LOG_DIR/cache/bbdd-tamanos sin borrar lo de las demas versiones (ni con sed -i) y
# solo enseña lineas Z| bien formadas, aunque alguien haya escrito otra cosa en la cache.
# Uso: mac-bbdd-tamanos.sh <macos/lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-mac-tam.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
grep -q '^function gui_db_sizes() {' "$SRC" || { echo "  ok    (sin tamaños de BBDD)"; exit 0; }
extract "$SRC" gui_db_sizes gui_db_check active_dir version_name valid_version_name || exit 1
realpath_f() { readlink -f "$1"; }
BASE_DIR=$W/apps LINK=$W/apps/XAMPP LOG_DIR=$W/log
DB_SAFE=(/usr/bin/env -u MYSQL_HOME -u MARIADB_HOME HOME=/var/empty)
DB_CLIENT=$W/mysql
CACHE=$LOG_DIR/cache/bbdd-tamanos
mkdir -p "$BASE_DIR/XAMPP-8.4" "$BASE_DIR/XAMPP-8.3"
ln -s "$BASE_DIR/XAMPP-8.4" "$LINK"
# Cliente falso: apunta lo que se le pide (y con que HOME) y contesta como el MariaDB de la activa
cat > "$DB_CLIENT" << 'EOF'
#!/bin/bash
D=$(dirname "$0")
echo "HOME=$HOME|$*" >> "$D/mysql.log"
[ -f "$D/parado" ] && { echo "ERROR 2002 (HY000): Can't connect to local server through socket '/Applications/XAMPP/xamppfiles/var/mysql/mysql.sock'" >&2; exit 1; }
[ -f "$D/clave" ] && { echo "ERROR 1045 (28000): Access denied for user 'root'@'localhost' (using password: NO)" >&2; exit 1; }
case "$*" in
    *"SELECT VERSION()"*) echo "10.11.8-MariaDB" ;;
    *information_schema.tables*) printf 'wp_t\t57671680\nps_x\t1024\nmal|nombre\t5\nvista\tNULL\nmysql\t2048\n' ;;
esac
EOF
chmod +x "$DB_CLIENT"
measured() { grep -c "information_schema.tables" "$W/mysql.log" 2> /dev/null; }

# --- Con la version activa en marcha ---
mkdir -p "$LOG_DIR/cache"
printf '8.3|vieja|100|1000\n8.4|borrada|5|1000\n8.40|otra|7|1000\n' > "$CACHE"
t0=$(date +%s)
out=$(gui_db_sizes); rc=$?
t1=$(date +%s)
when=$(sed -n 's/^Z|8\.4|wp_t|57671680|\([0-9]*\)$/\1/p' <<< "$out")
check "gui-bbdd-tamanos: termina bien y mide la activa (Z|version|base|bytes|cuando)" '[ $rc -eq 0 ] && [ -n "$when" ] && [ "$when" -ge "$t0" ] && [ "$when" -le "$t1" ]'
check "datos e indices de information_schema, sin cabecera (-N -B)" 'grep -q "SUM(data_length + index_length) FROM information_schema.tables GROUP BY table_schema" "$W/mysql.log" && grep -q -- "-N -B" "$W/mysql.log"'
check "el cliente va sin ~/.my.cnf (DB_SAFE: HOME=/var/empty)" '! grep -qv "^HOME=/var/empty|" "$W/mysql.log"'
check "todas las BBDD de la activa, cada una en su linea" 'grep -qx "Z|8.4|ps_x|1024|$when" <<< "$out" && grep -qx "Z|8.4|mysql|2048|$when" <<< "$out"'
check "nombres raros o tamaños que no son numeros: fuera" '! grep -q "mal\|nombre\|vista\|NULL" <<< "$out" && ! grep -q "mal\|vista" "$CACHE"'
check "lo medido antes de otra version se queda" 'grep -qx "Z|8.3|vieja|100|1000" <<< "$out"'
check "lo de antes de la activa se cambia por lo medido (una BBDD que ya no esta, fuera)" '! grep -q "borrada" "$CACHE" && [ "$(grep -c "^8\.4|wp_t|" "$CACHE")" == 1 ]'
check "la version se compara entera (8.4 no se lleva lo de 8.40)" 'grep -qx "8.40|otra|7|1000" "$CACHE"'
check "la cache, sin Z| delante (como la lee la funcion)" '! grep -q "^Z|" "$CACHE"'
check "sin el fichero a medias" '[ ! -e "$CACHE.nuevo" ]'

# --- MariaDB parado: no se mide, se enseña lo guardado ---
cp "$CACHE" "$W/antes"
: > "$W/mysql.log"
touch "$W/parado"
out=$(gui_db_sizes); rc=$?
check "MariaDB parado: no mide y enseña lo guardado" '[ $rc -eq 0 ] && [ "$(measured)" == 0 ] && grep -qx "Z|8.4|wp_t|57671680|$when" <<< "$out" && cmp -s "$CACHE" "$W/antes"'
rm -f "$W/parado"

# --- root con contraseña (gui_db_check: clave): tampoco ---
: > "$W/mysql.log"
touch "$W/clave"
out=$(gui_db_sizes)
check "root con contraseña: no mide" '[ "$(measured)" == 0 ] && grep -qx "Z|8.3|vieja|100|1000" <<< "$out"'
rm -f "$W/clave"

# --- Sin version activa ---
rm "$LINK"
: > "$W/mysql.log"
out=$(gui_db_sizes)
check "sin version activa: no mide y enseña lo guardado" '[ "$(measured)" == 0 ] && grep -qx "Z|8.3|vieja|100|1000" <<< "$out" && ! grep -qv "^Z|" <<< "$out"'
ln -s "$BASE_DIR/XAMPP-8.4" "$LINK"

# --- Cache escrita por otro programa ---
printf '8.3|vieja|100|1000\n../x|db|1|2\n8.3|a;b|1|2\n8.3|db|-1|2\n8.3|db|1|2|Z|mas\nZ|8.3|z|1|2\n' > "$CACHE"
touch "$W/parado"
out=$(gui_db_sizes)
check "cache cambiada a mano: solo salen las lineas bien formadas" '[ "$out" == "Z|8.3|vieja|100|1000" ]'
rm -f "$W/parado"

# --- Sin cache ni MariaDB ---
rm -rf "$LOG_DIR/cache"
touch "$W/parado"
out=$(gui_db_sizes); rc=$?
check "sin cache y con MariaDB parado: nada y sin error" '[ $rc -eq 0 ] && [ -z "$out" ]'
check "la carpeta de la cache se crea solo tuya" '[ "$(stat -c %a "$LOG_DIR/cache" 2> /dev/null || stat -f %Lp "$LOG_DIR/cache")" == 700 ]'
rm -f "$W/parado"

# --- En el script y en la ventana ---
check "sin sed -i" '! declare -f gui_db_sizes | grep -q "sed -i"'
check "comando gui-bbdd-tamanos" 'grep -q "^    gui-bbdd-tamanos) gui_db_sizes ;;$" "$SRC"'
check "la ventana lo pide (al abrir Bases de datos y al volver a leer)" '[ "$(grep -c "runQuick(\[\"gui-bbdd-tamanos\"\]" "$SRC")" -ge 1 ] && grep -q "func reloadDbSizes" "$SRC"'
exit $fail
