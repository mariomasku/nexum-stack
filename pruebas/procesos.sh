#!/bin/bash
# Pruebas de lampp_processes (Linux): un .pid manipulado no marca procesos ajenos. Uso: procesos.sh <script> [anterior]
SRC=$1 OLD=$2 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-proc.XXXX"); trap 'kill $SL 2> /dev/null; rm -rf "$W"' EXIT
extract "$SRC" lampp_processes || exit 1
# Como en el equipo: sin LVM_PRUEBA no se hace caso a LVM_ENLACE
real=$(TEST_DIR= LVM_ENLACE=/x; eval "$(grep -m1 -A1 '^LAMPP_LINK=' "$SRC")"; echo "$LAMPP_LINK")
check "sin LVM_PRUEBA, LVM_ENLACE no cambia /opt/lampp" '[ "$real" = /opt/lampp ]'
# Version falsa cuyo httpd.pid dice 1 y el pid de un sleep cualquiera
mkdir -p "$W/lampp-9.9/logs"; ln -s "$W/lampp-9.9" "$W/lampp"
sleep 300 & SL=$!
printf '1\n' > "$W/lampp-9.9/logs/httpd.pid"
LAMPP_LINK=$W/lampp
out=$(lampp_processes)
check "un .pid con 1 no marca el 1 ni sus hijos" '! grep -qE "^P\|1\|" <<< "$out" && [ "$(grep -c "^P|" <<< "$out")" -lt 20 ]'
printf '%s\n' "$SL" > "$W/lampp-9.9/logs/httpd.pid"
out=$(lampp_processes)
check "un .pid con un programa que no es de LAMPP no lo marca" '! grep -qE "^P\|$SL\|" <<< "$out"'
# En el equipo de verdad, lo mismo que antes
if [ -n "$OLD" ]; then
    LAMPP_LINK=/opt/lampp
    a=$(lampp_processes | sort); extract "$OLD" lampp_processes; b=$(lampp_processes | sort)
    check "en el equipo, los mismos procesos que la version anterior" '[ "$a" = "$b" ]'
fi
exit $fail
