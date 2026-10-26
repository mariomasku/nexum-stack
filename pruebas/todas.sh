#!/bin/bash
# Batería de pruebas de seguridad de lvm-instalador. Se pasa entera en cada versión.
# Uso: todas.sh [linux.sh] [mac.sh] [empaquetar-deb.sh] [mac-1.27.1.sh de referencia]
# Sin argumentos: LVM_SCRIPT (por defecto ../lvm-instalador.sh), LVM_SCRIPT_MAC (por defecto
# ../macos/lvm-instalador.sh o, si no esta, el lvm-instalador.sh del zip mas reciente de
# ../macos/lvm-instalador-mac-*.zip, sacado a la carpeta temporal), LVM_EMPAQUETAR (../empaquetar-deb.sh) y LVM_MAC_ANTIGUO (datos/mac-1.27.1-xampp.sh).
# Sin sudo. Todo lo temporal va en una carpeta nueva de ${TMPDIR:-/tmp} que se borra al acabar.
HERE=$(cd "$(dirname "$0")" && pwd)
RAIZ=$(cd "$HERE/.." && pwd)
LVM_TMP=$(mktemp -d "${TMPDIR:-/tmp}/lvm-pruebas.XXXXXX") || exit 1
export LVM_TMP
trap 'rm -rf "$LVM_TMP"' EXIT
L=${1:-${LVM_SCRIPT:-$RAIZ/lvm-instalador.sh}}
M=${2:-$LVM_SCRIPT_MAC}
[ -z "$M" ] && [ -f "$RAIZ/macos/lvm-instalador.sh" ] && M=$RAIZ/macos/lvm-instalador.sh
if [ -z "$M" ]; then
    zip=$(ls "$RAIZ"/macos/lvm-instalador-mac-*.zip 2> /dev/null | sort -V | tail -1)
    [ -n "$zip" ] || { echo "No hay ningun $RAIZ/macos/lvm-instalador-mac-*.zip: pon LVM_SCRIPT_MAC"; exit 1; }
    mkdir "$LVM_TMP/mac" && unzip -q -o "$zip" lvm-instalador.sh -d "$LVM_TMP/mac" \
        || { echo "No se ha podido sacar lvm-instalador.sh de $zip"; exit 1; }
    M=$LVM_TMP/mac/lvm-instalador.sh
fi
E=${3:-${LVM_EMPAQUETAR:-$RAIZ/empaquetar-deb.sh}}
OLD=${4:-${LVM_MAC_ANTIGUO:-$HERE/datos/mac-1.27.1-xampp.sh}}
total=0 bad=0
suite() {
    local name=$1; shift
    local out rc
    out=$("$@" 2>&1); rc=$?
    local ok=$(grep -c '^  ok' <<< "$out") ko=$(grep -c 'FALLA' <<< "$out")
    total=$((total + ok + ko)); bad=$((bad + ko))
    if [ $rc -eq 0 ] && [ "$ko" -eq 0 ]; then
        printf '  %-34s %3d ok\n' "$name" "$ok"
    else
        printf '  %-34s %3d ok, %d FALLAN (rc %d)\n' "$name" "$ok" "$ko" "$rc"; grep -E 'FALLA|rror' <<< "$out" | head -8 | sed 's/^/      /'
        [ "$ko" -eq 0 ] && bad=$((bad + 1))
    fi
}
for s in "$L" "$M" "$E" "$OLD"; do [ -f "$s" ] || { echo "No esta $s"; exit 1; }; done
for s in "$L" "$M"; do bash -n "$s" || { echo "sintaxis: $s"; exit 1; }; done
echo "Linux ($L, $(grep -m1 '^APP_VERSION=' "$L" | cut -d'"' -f2))"
suite "ayudante de actualizacion" "$HERE/ayudante.sh" "$E" "$L"
suite "volcados (MariaDB temporal)" "$HERE/volcados.sh" "$L"
suite "certificados y dominios" "$HERE/certs.sh" "$L"
suite "arreglar-certificados" "$HERE/arreglar-certs.sh" "$L"
suite "SECURE_PY" "$HERE/secure.sh" "$L"
suite "escritura en proyectos" "$HERE/escritura.sh" "$L"
suite "vaciar cache" "$HERE/cache.sh" "$L"
suite "reglas web (Apache temporal)" "$HERE/web.sh" "$L"
suite "compilacion sin terminal" "$HERE/notty.sh" "$L"
suite "procesos (.pid manipulados)" "$HERE/procesos.sh" "$L"
suite "entorno de las tareas" "$HERE/entorno.sh" "$L"
suite "Python incrustado compila" "$HERE/compila.sh" "$L"
suite "root sobre carpetas tuyas" "$HERE/raiz.sh" "$L"
suite "hosts, vhosts, htdocs y MariaDB (1.42)" "$HERE/extras.sh" "$L"
suite "octavo repaso y proyectos (1.44)" "$HERE/repaso8.sh" "$L"
suite "noveno repaso (1.45)" "$HERE/repaso9.sh" "$L"
suite "administrador de pruebas (1.45)" "$HERE/admin-pruebas.sh" "$L"
suite "confiar en los certificados (1.47)" "$HERE/confianza.sh" "$L"
suite "prefijo de las tablas (1.47)" "$HERE/prefijos.sh" "$L"
suite "cargar vaciando antes (1.48)" "$HERE/cargas.sh" "$L"
suite "vincular BBDD y carpetas (1.51)" "$HERE/vinculos.sh" "$L"
suite "Docker (1.53)" "$HERE/docker.sh" "$L"
suite "barrera entre webs (1.54.1)" "$HERE/barrera.sh" "$L"
suite "PHP2Shell y repaso (1.54.1)" "$HERE/php2shell.sh" "$L"
suite "BBDD sin el admin de pruebas (1.54.1)" "$HERE/admin-fuera.sh" "$L"
suite "correo de pruebas: Mailpit (1.55)" "$HERE/correo.sh" "$L"
suite "cargar un proyecto, todo o nada (1.55.2)" "$HERE/carga-cancelar.sh" "$L"
suite "interruptores: cancelar la contraseña no cambia nada (1.55.4)" "$HERE/interruptores.sh" "$L"
suite "Docker: visor y Panel con el admin de pruebas (1.55.9)" "$HERE/docker-panel.sh" "$L"
suite "PrestaShop: cache con otra BBDD (1.55.10)" "$HERE/ps-cache.sh" "$L"
echo "Mac ($M, $(grep -m1 '^APP_VERSION=' "$M" | cut -d'"' -f2))"
suite "volcados (MariaDB temporal)" "$HERE/volcados.sh" "$M"
suite "certificados y dominios" "$HERE/certs.sh" "$M"
suite "SECURE_PY" "$HERE/secure.sh" "$M"
suite "escritura en proyectos" "$HERE/escritura.sh" "$M"
suite "vaciar cache" "$HERE/cache.sh" "$M"
suite "reglas web (Apache temporal)" "$HERE/web.sh" "$M"
suite "script xampp (MariaDB)" "$HERE/mac-xampp.sh" "$M" "$OLD"
suite "compilacion sin terminal" "$HERE/notty.sh" "$M"
suite "Python incrustado compila" "$HERE/compila.sh" "$M"
suite "procesos (.pid manipulados)" "$HERE/mac-procesos.sh" "$M"
suite "hosts, vhosts, htdocs y MariaDB (1.30)" "$HERE/extras.sh" "$M"
suite "octavo repaso y proyectos (1.32)" "$HERE/repaso8.sh" "$M"
suite "confiar en los certificados (1.35)" "$HERE/confianza.sh" "$M"
suite "prefijo de las tablas (1.35)" "$HERE/prefijos.sh" "$M"
suite "cargar vaciando antes (1.36)" "$HERE/cargas.sh" "$M"
suite "noveno repaso (1.33)" "$HERE/repaso9.sh" "$M"
suite "administrador de pruebas (1.33)" "$HERE/admin-pruebas.sh" "$M"
suite "actualizar desde GitHub, firmadas (1.38)" "$HERE/mac-actualizar.sh" "$M"
suite "vincular BBDD y carpetas (1.38)" "$HERE/vinculos.sh" "$M"
suite "Docker en el Mac (1.39)" "$HERE/mac-docker.sh" "$M"
suite "tamaños de BBDD en el Mac (1.39)" "$HERE/mac-bbdd-tamanos.sh" "$M"
suite "seguridad del Mac: PHP2Shell, barrera y firmas (1.39.2)" "$HERE/mac-seguridad.sh" "$M"
suite "gestor de root y /Library/Nexum (1.39.3)" "$HERE/mac-raiz.sh" "$M"
suite "correo de pruebas: Mailpit (1.39.9)" "$HERE/mac-correo.sh" "$M"
suite "cargar un proyecto, todo o nada (1.39.12)" "$HERE/carga-cancelar.sh" "$M"
suite "interruptores: cancelar la contraseña no cambia nada (1.39.14)" "$HERE/interruptores.sh" "$M"
suite "Docker: visor y Panel con el admin de pruebas (1.39.19)" "$HERE/docker-panel.sh" "$M"
suite "BBDD sin el admin de pruebas (1.39.20)" "$HERE/admin-fuera.sh" "$M"
suite "PrestaShop: cache con otra BBDD (1.39.21)" "$HERE/ps-cache.sh" "$M"
echo "Total: $total pruebas, $bad fallos"
[ $bad -eq 0 ]
