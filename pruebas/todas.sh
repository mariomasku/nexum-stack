#!/bin/bash
# Batería de pruebas de seguridad de lvm-instalador. Se pasa entera en cada versión (sus grupos, en paralelo).
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
# Los grupos van en paralelo (cada uno en su carpeta temporal y con sus puertos): tantos a la vez como
# nucleos (LVM_PRUEBAS_A_LA_VEZ para cambiarlo; 1, uno detras de otro). El resultado sale en su orden; con
# LVM_TIEMPOS=1, con lo que tarda cada grupo
N=${LVM_PRUEBAS_A_LA_VEZ:-$(nproc 2> /dev/null || echo 4)}
items=() n=0
suite() {
    local name=$1 f
    shift
    n=$((n + 1)) f=$LVM_TMP/grupo.$n
    items+=("s|$n|$name")
    while [ "$(jobs -rp | wc -l)" -ge "$N" ]; do wait -n; done
    # (los que arrancan una MariaDB de verdad, de uno en uno: a la vez se quedan sin recursos al crearla)
    local a lock=()
    for a in "$@"; do
        [[ "$a" == *.sh ]] && [ -f "$a" ] && grep -q "mysql_install_db" "$a" && lock=(flock "$LVM_TMP/mariadb.lock")
    done
    # (sin entrada: una prueba que se pusiera a leer del teclado se quedaria esperando para siempre)
    ( t0=$(date +%s%N); "${lock[@]}" "$@" > "$f.out" 2>&1 < /dev/null; echo $? > "$f.rc"; echo $(( ($(date +%s%N) - t0) / 1000000 )) > "$f.ms" ) &
}
note() { items+=("e|$*"); }
report() {
    local it kind idx name out rc ok ko ms
    wait
    for it in "${items[@]}"; do
        kind=${it%%|*}
        if [ "$kind" == e ]; then echo "${it#e|}"; continue; fi
        idx=$(cut -d'|' -f2 <<< "$it") name=$(cut -d'|' -f3- <<< "$it")
        out=$(cat "$LVM_TMP/grupo.$idx.out" 2> /dev/null) rc=$(cat "$LVM_TMP/grupo.$idx.rc" 2> /dev/null || echo 1)
        ms=$(cat "$LVM_TMP/grupo.$idx.ms" 2> /dev/null || echo 0)
        ok=$(grep -c '^  ok' <<< "$out") ko=$(grep -c 'FALLA' <<< "$out")
        total=$((total + ok + ko)); bad=$((bad + ko))
        [ "${LVM_TIEMPOS:-0}" == 1 ] && name+=" ($((ms / 1000)),$((ms % 1000 / 100)) s)"
        if [ "$rc" -eq 0 ] && [ "$ko" -eq 0 ]; then
            printf '  %-34s %3d ok\n' "$name" "$ok"
        else
            printf '  %-34s %3d ok, %d FALLAN (rc %d)\n' "$name" "$ok" "$ko" "$rc"; grep -E 'FALLA|rror' <<< "$out" | head -8 | sed 's/^/      /'
            [ "$ko" -eq 0 ] && bad=$((bad + 1))
        fi
    done
}
for s in "$L" "$M" "$E" "$OLD"; do [ -f "$s" ] || { echo "No esta $s"; exit 1; }; done
for s in "$L" "$M"; do bash -n "$s" || { echo "sintaxis: $s"; exit 1; }; done
note "Linux ($L, $(grep -m1 '^APP_VERSION=' "$L" | cut -d'"' -f2))"
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
suite "Proyectos: lo que ocupa cada uno (1.55.12)" "$HERE/proyectos-tamanos.sh" "$L"
suite "imágenes de producción y borrar un proyecto (1.55.14)" "$HERE/media-borrar.sh" "$L"
suite "Docker con su propio Apache (1.56.0)" "$HERE/docker-web.sh" "$L"
suite "túnel de Cloudflare (1.56.0)" "$HERE/tunel.sh" "$L"
suite "botones a tu gusto y cuándo se actualiza (1.56.1-1.56.2)" "$HERE/botones-actualizar.sh" "$L"
suite "parar los contenedores de Nexum (1.56.2)" "$HERE/docker-parar.sh" "$L"
suite "consumo de Nexum en el visor (1.56.2)" "$HERE/consumo.sh" "$L"
suite "repositorio privado: se prueba por SSH (1.56.3)" "$HERE/clonar-ssh.sh" "$L"
suite "parches nuevos de los componentes (1.56.8)" "$HERE/componentes.sh" "$L"
suite "pestaña Repositorios (1.56.8)" "$HERE/repos.sh" "$L"
suite "parar los proyectos sin visitas (1.56.8)" "$HERE/reposo.sh" "$L"
suite "terminal en la ventana (1.56.12)" "$HERE/terminal.sh" "$L"
suite "asistente de nuevo proyecto (1.56.13)" "$HERE/nuevo-proyecto.sh" "$L"
suite "dependencias con apt, con repositorios rotos (1.56.15)" "$HERE/apt.sh" "$L"
suite "BBDD de LAMPP en Docker, en vivo (1.56.10)" "$HERE/bd-vivo.sh" "$L"
note "Mac ($M, $(grep -m1 '^APP_VERSION=' "$M" | cut -d'"' -f2))"
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
suite "Proyectos: lo que ocupa cada uno (1.39.23)" "$HERE/proyectos-tamanos.sh" "$M"
suite "imágenes de producción y borrar un proyecto (1.39.25)" "$HERE/media-borrar.sh" "$M"
suite "túnel de Cloudflare (1.40.0)" "$HERE/tunel.sh" "$M"
suite "Docker con su propio Apache (1.40.0)" "$HERE/docker-web-mac.sh" "$M"
suite "parar los contenedores de Nexum (1.40.0)" "$HERE/docker-parar.sh" "$M"
suite "ventana 1.40.0 (Swift)" "$HERE/mac-ventana-140.sh" "$M"
suite "repositorio privado: se prueba por SSH (1.40.1)" "$HERE/clonar-ssh.sh" "$M"
suite "parches nuevos de los componentes (1.40.1)" "$HERE/componentes.sh" "$M"
suite "pestaña Repositorios (1.40.1)" "$HERE/repos.sh" "$M"
suite "parar los proyectos sin visitas (1.40.1)" "$HERE/reposo.sh" "$M"
suite "terminal en la ventana (1.40.1)" "$HERE/terminal.sh" "$M"
suite "asistente de nuevo proyecto (1.40.1)" "$HERE/nuevo-proyecto.sh" "$M"
suite "BBDD de XAMPP-X en Docker, en vivo (1.40.1)" "$HERE/bd-vivo-mac.sh" "$M"
report
echo "Total: $total pruebas, $bad fallos"
[ $bad -eq 0 ]
