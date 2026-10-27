#!/bin/bash
# Lo que ocupa cada proyecto en el disco, para la lista de Proyectos (Linux 1.55.12 / Mac 1.39.23): se mide con du,
# se guarda, de 10 en 10 y cada 6 horas. Uso: proyectos-tamanos.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-proyectos-tamanos.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
grep -q '^function gui_project_sizes() {' "$SRC" || { echo "  ok    (sin tamaños de proyectos)"; exit 0; }
extract "$SRC" gui_project_sizes || exit 1

HTDOCS_DIR=$W/htdocs LOG_DIR=$W/log
for n in $(seq -w 1 12); do mkdir -p "$HTDOCS_DIR/web$n"; done
head -c 300000 /dev/zero > "$HTDOCS_DIR/web01/grande.bin"
mkdir -p "$W/fuera" && ln -s "$W/fuera" "$HTDOCS_DIR/enlace"
CACHE=$LOG_DIR/cache/proyectos-tamanos

o=$(gui_project_sizes); rc=$?
check "la primera vez: 10 medidos y dice cuántos quedan" '[ $rc -eq 0 ] && [ "$(grep -c "^T|" <<< "$o")" == 10 ] && grep -qx "F|2" <<< "$o"'
check "mide lo que ocupa (con sus ficheros)" 'b=$(grep "^T|web01|" <<< "$o" | cut -d"|" -f3); [ "${b:-0}" -ge 300000 ]'
check "un enlace no es un proyecto: no se mide" '! grep -q "|enlace|" <<< "$o" && ! grep -q "^enlace|" "$CACHE"'
o=$(gui_project_sizes)
check "la siguiente tanda: los que faltaban, y ya no quedan" '[ "$(grep -c "^T|" <<< "$o")" == 12 ] && ! grep -q "^F|" <<< "$o"'
before=$(cat "$CACHE")
o=$(gui_project_sizes)
check "recién medidos: no se vuelven a medir" '[ "$(cat "$CACHE")" == "$before" ] && [ "$(grep -c "^T|" <<< "$o")" == 12 ]'
# Uno medido hace 7 horas: se vuelve a medir (y uno que ya no esta, se olvida)
old=$(( $(date +%s) - 25200 ))
sed -i "s/^web05|\([0-9]*\)|.*/web05|\1|$old/" "$CACHE"
rm -rf "$HTDOCS_DIR/web12"
o=$(gui_project_sizes)
check "medido hace más de 6 horas: otra vez; el que ya no está, fuera" '! grep -q "|$old$" "$CACHE" && grep -q "^web05|" "$CACHE" && ! grep -q "^web12|" "$CACHE" && [ "$(grep -c "^T|" <<< "$o")" == 11 ]'
check "solo líneas T|carpeta|bytes|cuando (y F|n)" '! grep -vE "^(T\|[^|]+\|[0-9]+\|[0-9]+|F\|[0-9]+)$" <<< "$o"'
exit $fail
