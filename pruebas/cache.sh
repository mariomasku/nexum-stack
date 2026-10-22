#!/bin/bash
# Pruebas de CACHE_CLEAR_PY (como tu usuario). Uso: cache.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-cache.XXXX"); trap 'rm -rf "$W"' EXIT
CC=$( ( eval "$(sed -n "/^CACHE_CLEAR_PY='/,/^'\$/p" "$SRC")"; printf '%s' "$CACHE_CLEAR_PY" ) )
H=$W/htdocs; mkdir -p "$H/tienda/var/cache/prod/sub" "$W/sistema/cache"
touch "$H/tienda/var/cache/a" "$H/tienda/var/cache/prod/sub/b" "$W/sistema/cache/importante" "$W/sistema/fuera"
ln -s "$W/sistema" "$H/tienda/var/cache/enlace"
python3 -I -c "$CC" "$H/tienda/var/cache" "$H"
check "vacia var/cache" '[ -d "$H/tienda/var/cache" ] && [ -z "$(ls -A "$H/tienda/var/cache")" ]'
check "un enlace dentro se borra sin seguirlo" '[ -f "$W/sistema/fuera" ] && [ -f "$W/sistema/cache/importante" ]'
mkdir -p "$H/t2"; ln -s "$W/sistema" "$H/t2/var"
out=$(python3 -I -c "$CC" "$H/t2/var/cache" "$H" 2>&1)
check "var cambiado por un enlace fuera: no vacia" '[ -f "$W/sistema/cache/importante" ] && echo "$out" | grep -q "no esta dentro"'
mkdir -p "$H/t3/real/var/cache"; touch "$H/t3/real/var/cache/x"; ln -s "$H/t3/real/var" "$H/t3/var"
python3 -I -c "$CC" "$H/t3/var/cache" "$H" > /dev/null 2>&1
check "solo carpetas que acaban en var/cache" 'python3 -I -c "$CC" "$H/tienda" "$H" > /dev/null 2>&1; [ $? -ne 0 ] && [ -d "$H/tienda/var" ]'
exit $fail
