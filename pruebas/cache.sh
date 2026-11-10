#!/bin/bash
# Pruebas de CLEAN_PY vaciando la var/cache de una tienda, como hace vaciar-cache con sudo (como tu
# usuario). Uso: cache.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-cache.XXXX"); trap 'rm -rf "$W"' EXIT
CC=$( ( eval "$(sed -n "/^CLEAN_PY='/,/^'\$/p" "$SRC")"; printf '%s' "$CLEAN_PY" ) )
H=$W/htdocs; mkdir -p "$H/tienda/var/cache/prod/sub" "$W/sistema/cache"
touch "$H/tienda/var/cache/a" "$H/tienda/var/cache/prod/sub/b" "$W/sistema/cache/importante" "$W/sistema/fuera"
ln -s "$W/sistema" "$H/tienda/var/cache/enlace"
python3 -I -c "$CC" limpiar "cache|$H/tienda|vaciar|var/cache||" > /dev/null
check "vacia var/cache" '[ -d "$H/tienda/var/cache" ] && [ -z "$(ls -A "$H/tienda/var/cache")" ]'
check "un enlace dentro se borra sin seguirlo" '[ -f "$W/sistema/fuera" ] && [ -f "$W/sistema/cache/importante" ]'
mkdir -p "$H/t2"; ln -s "$W/sistema" "$H/t2/var"
python3 -I -c "$CC" limpiar "cache|$H/t2|vaciar|var/cache||" > /dev/null 2>&1
check "var cambiado por un enlace fuera: no vacia" '[ -f "$W/sistema/cache/importante" ]'
mkdir -p "$H/t3/real/var/cache"; touch "$H/t3/real/var/cache/x"; ln -s "$H/t3/real/var" "$H/t3/var"
python3 -I -c "$CC" limpiar "cache|$H/t3|vaciar|var/cache||" > /dev/null 2>&1
check "var enlazado a otra carpeta de la misma tienda: tampoco (no se sigue ningun enlace)" '[ -f "$H/t3/real/var/cache/x" ]'
ln -s "$H/tienda" "$H/t4"
out=$(python3 -I -c "$CC" limpiar "cache|$H/t4|vaciar|var/cache||" 2>&1)
check "la tienda es un enlace: no se toca" 'echo "$out" | grep -q "enlace"'
exit $fail
