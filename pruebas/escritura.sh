#!/bin/bash
# Pruebas de PROJECT_WRITE_PY (como tu usuario: lo que importa es dónde escribe). Uso: escritura.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-esc.XXXX"); trap 'rm -rf "$W"' EXIT
PW=$( ( eval "$(sed -n "/^PROJECT_WRITE_PY='/,/^'\$/p" "$SRC")"; printf '%s' "$PROJECT_WRITE_PY" ) )
H=$W/htdocs; mkdir -p "$H/web/app" "$W/sistema" "$H/otra"
echo original > "$W/sistema/wp-config.php"
w() { echo "$2" | python3 -I -c "$PW" "$1" "$(id -u)" "$(id -g)" "$H" 2>&1; }
w "$H/web/wp-config.php" nuevo > /dev/null
check "escribe dentro de htdocs" '[ "$(cat "$H/web/wp-config.php")" = nuevo ]'
ln -s "$W/sistema" "$H/enlazado"
out=$(w "$H/enlazado/wp-config.php" malo)
check "proyecto cambiado por un enlace fuera de htdocs: no escribe" '[ "$(cat "$W/sistema/wp-config.php")" = original ] && echo "$out" | grep -q "no esta dentro"'
ln -s "$W/sistema/wp-config.php" "$H/web/app/parameters.php"
w "$H/web/app/parameters.php" seguro > /dev/null
check "fichero final enlazado: se cambia el enlace, no el destino" '[ "$(cat "$W/sistema/wp-config.php")" = original ] && [ ! -L "$H/web/app/parameters.php" ] && [ "$(cat "$H/web/app/parameters.php")" = seguro ]'
out=$(w "$H/../sistema/wp-config.php" malo)
check "ruta con .. fuera de htdocs: no escribe" '[ "$(cat "$W/sistema/wp-config.php")" = original ]'
ln -s "$H/otra" "$H/alias"
w "$H/alias/x.php" dentro > /dev/null
check "enlace a otra carpeta de htdocs: sí (sigue dentro)" '[ "$(cat "$H/otra/x.php")" = dentro ]'
exit $fail
