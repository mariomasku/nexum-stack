#!/bin/bash
# Descargas del código (Linux 1.57.3, Mac 1.41.2): la suma de ProFTPD por la API de GitHub si su
# descarga directa falla (respondía 504) y, si falla una descarga, el motivo en el informe del error.
# Uso: descargas.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q "^function proftpd_sum()" "$SRC" || { echo "  ok    (sin proftpd_sum)"; exit 0; }
W=$(mktemp -d "$TMPBASE/descargas.XXXXXX") || exit 1
trap 'rm -rf "${W:?}"' EXIT
extract "$SRC" proftpd_sum download error_report
SUM=7db91f229f8c3ad18e233f38a3c1749bd11bf92e1079b6c7f86e51a3fcfce5eb
# curl falso: la descarga directa, como el 504 de GitHub; la API, con su lista y el fichero
curl() {
    local u="${@: -1}"
    echo "$u" >> "$W/curl.log"
    case $u in
        https://github.com/proftpd/proftpd/releases/download/*) [ -f "$W/directa-bien" ] && { echo "$SUM  proftpd-1.3.9e.tar.gz"; return 0; }; return 22 ;;
        https://api.github.com/repos/proftpd/proftpd/releases/tags/v1.3.9e)
            echo '{"assets":[{"id":11,"name":"proftpd-1.3.9e.tar.gz.asc"},{"id":12,"name":"proftpd-1.3.9e.tar.gz.sha256"}]}' ;;
        https://api.github.com/repos/proftpd/proftpd/releases/assets/12) echo "$SUM  proftpd-1.3.9e.tar.gz" ;;
        https://api.github.com/*) return 22 ;;
        *) return 22 ;;
    esac
}
check "504 en la directa: la suma llega por la API" '[ "$(proftpd_sum 1.3.9e)" = "$SUM" ] && grep -q "releases/assets/12" "$W/curl.log"'
: > "$W/curl.log"; touch "$W/directa-bien"
check "si la directa responde, no se usa la API" '[ "$(proftpd_sum 1.3.9e)" = "$SUM" ] && ! grep -q api.github.com "$W/curl.log"'
rm -f "$W/directa-bien"
check "una versión que no existe: sin suma (y no se instala)" '[ -z "$(proftpd_sum 9.9.9z)" ]'
check "la de la API es la del mismo fichero (solo ese nombre)" 'grep -qF "if a.get(\"name\") == sys.argv[1]" "$SRC" && grep -qF "\"proftpd-\$ftp.tar.gz.sha256\"" "$SRC"'
check "y se usa al compilar" 'grep -qF "\"\$(proftpd_sum \"\$ftp\")\" || stack_fail" "$SRC"'
# El motivo en el informe
STEP_DESC=""
( cd "$W" && download "https://example.org/x.tar.gz" x.tar.gz "" > /dev/null; echo "$STEP_DESC" > "$W/motivo" )
check "sin suma: el motivo queda para el informe" 'grep -q "no se ha podido leer la suma sha256 de x.tar.gz" "$W/motivo"'
APP_NAME=Nexum APP_VERSION=0
error_report "$W/informe.txt" "lampp-8.2: PHP 8.2.35" "" "$(cat "$W/motivo")" "" > /dev/null 2>&1
check "el informe dice el motivo (antes, solo la cabecera)" 'grep -q "^Motivo: no se ha podido leer la suma sha256 de x.tar.gz" "$W/informe.txt"'
exit $fail
