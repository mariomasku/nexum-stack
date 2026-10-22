# Ayudas de las pruebas. extract <script> <funcion...>: define en este bash las funciones del script
# TMPBASE: donde cada prueba crea su carpeta de trabajo (mktemp -d). todas.sh crea una por ejecucion
# (LVM_TMP) y la borra al acabar; una prueba lanzada sola usa ${TMPDIR:-/tmp}.
TMPBASE=${LVM_TMP:-${TMPDIR:-/tmp}}
# DATOS: ficheros fijos de las pruebas (certificado de fabrica falso, script viejo del Mac...)
DATOS=$(cd "$(dirname "${BASH_SOURCE[0]}")/datos" && pwd)
extract() {
    local src=$1 f; shift
    for f in "$@"; do
        eval "$(awk -v n="$f" '$0 ~ "^function "n"\\(\\) \\{" {p=1} p {print} p && /^}/ {exit}' "$src")"
        declare -F "$f" > /dev/null || { echo "no esta la funcion $f"; return 1; }
    done
}
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FALLA $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
