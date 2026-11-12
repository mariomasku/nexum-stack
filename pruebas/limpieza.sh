#!/bin/bash
# Limpieza (Linux y Mac 1.57.9): limpieza, gui-limpieza y limpiar <clave>..., y gui-limpiar-proyecto y
# limpiar-proyecto. Que borra lo que debe y nada mas: los ajustes de ~/.nexum, uploads e img, los
# .pid y cgisock, los datos de MariaDB y los index.php de PrestaShop se quedan; no sigue enlaces; con
# --simular no borra nada; los registros de las versiones quedan a 0 bytes; los temporales recientes o en
# uso siguen. Todo en carpetas temporales, sin sudo de verdad (un sudo falso que solo lo apunta).
# Uso: limpieza.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q '^function clean_command() {' "$SRC" || { echo "  ok    (sin limpieza)"; exit 0; }
MAC=0; grep -qE '^    BASE_DIR=(/Applications|/Library/Nexum)$' "$SRC" && MAC=1
W=$(mktemp -d "$TMPBASE/w-limpieza.XXXX") || exit 1
case "$W" in "$TMPBASE"/w-limpieza.*) ;; *) echo "  FALLA carpeta de trabajo: $W"; exit 1 ;; esac
PIDS=()
trap 'kill "${PIDS[@]}" 2> /dev/null; chmod -R u+w "$W" 2> /dev/null; rm -rf "$W"' EXIT

# --- Lo que tiene el script ---
check "comandos limpieza, gui-limpieza, limpiar, gui-limpiar-proyecto y limpiar-proyecto" 'grep -qx "    limpieza) clean_list ;;" "$SRC" && grep -qx "    gui-limpieza) clean_measure \"\${CLEAN_KEYS\[@\]}\" | cut -d.|. -f1-4 ;;" "$SRC" && grep -qx "    limpiar) shift; clean_command \"\$@\" ;;" "$SRC" && grep -qx "    gui-limpiar-proyecto) gui_clean_project \"\$2\" ;;" "$SRC" && grep -qx "    limpiar-proyecto) shift; clean_project_command \"\$@\" ;;" "$SRC"'
check "en la ayuda (--ayuda): limpieza, limpiar y limpiar-proyecto" 'sed -n "3,/^\$/p" "$SRC" | grep -q "nexum limpieza$" && sed -n "3,/^\$/p" "$SRC" | grep -q "nexum limpiar <clave>" && sed -n "3,/^\$/p" "$SRC" | grep -q "nexum limpiar-proyecto <carpeta>"'
check "tareas de la ventana: limpieza sin contraseña; limpiar, solo si algo es de root" 'grep -E "^        gui-\*\|.*\) ;;$" "$SRC" | grep -q "|limpieza|" && grep -qx "        limpiar) clean_need_root \"\${@:2}\" && { sudo_first || exit 130; } ;;" "$SRC" && grep -qx "        limpiar-proyecto) clean_project_need_root \"\${@:2}\" && { sudo_first || exit 130; } ;;" "$SRC"'
check "vaciar-cache con sudo usa CLEAN_PY (ya no hay CACHE_CLEAR_PY)" '! grep -q CACHE_CLEAR_PY "$SRC" && grep -q "python3 -I -c \"\$CLEAN_PY\" limpiar \"cache|\$HTDOCS_DIR/\$folder|vaciar|var/cache||\"" "$SRC"'
check "sin copias de seguridad en la limpieza" '! awk "/^function clean_size_text\\(\\) \\{/,/^function clean_project_command/" "$SRC" | grep -q "COPIES_DIR/"'

extract "$SRC" clean_size_text clean_files_text clean_title clean_project_title clean_projects clean_project_rules clean_rules \
    clean_mail_count clean_measure clean_valid_key clean_list clean_need_root clean_run clean_mail clean_command \
    clean_project_measure gui_clean_project clean_project_need_root clean_project_key clean_project_command \
    clean_version_dirs valid_project ps_clear_cache downloads_command copies_command copies_need_root \
    copies_size_text dl_cache_trusted || exit 1
[ $MAC -eq 1 ] && { extract "$SRC" version_dirs || exit 1; realpath_f() { readlink -f "$1"; }; }
eval "$(sed -n "/^CLEAN_PY='/,/^'\$/p" "$SRC")"
eval "$(grep -E '^(CLEAN_KEYS|CLEAN_PROJECT_KEYS|CLEAN_AGE|CLEAN_STACK_SUB)=' "$SRC")"
SUB=$CLEAN_STACK_SUB
mailpit_pid() { :; }
mail_command() { echo "mail_command $*" >> "$W/correo.log"; }
run() { if [ "$DRY" -eq 1 ]; then echo "  [simulacion] $*"; else "$@"; fi; }

# Un equipo de prueba: HOME, htdocs, las versiones, la caché de descargas y la carpeta temporal, en $1
fixture() {
    local R=$1 L V T
    L=$R/home/.nexum T=$R/tmp
    mkdir -p "$L" "$R/home/nexum-backups/sub" "$R/descargas" "$T" "$R/fuera/dentro" "$R/htdocs"
    echo "no se toca" > "$R/fuera/dentro/importante"
    # Ajustes (nada de esto se borra nunca)
    for f in apariencia botones-visor copias-ficheros ultima-version dominios proyectos hosts media-produccion \
        github importaciones locales-apagados montados-de-repositorio prestashop-cargados repos-github \
        sin-barrera-entre-webs ventana-tema ventana-plegados httpd-vhosts.conf certificados actualizaciones-arranques; do
        echo "ajuste $f" > "$L/$f"
    done
    mkdir -p "$L/tunel" "$L/docker/web" "$L/mailpit" "$L/prestashop" "$L/wordpress" "$L/node/proyectos" "$L/cache" "$L/temporal"
    echo "registro del tunel" > "$L/tunel/registro"; echo estado > "$L/tunel/estado"
    echo conf > "$L/docker/web/web.conf"; echo db > "$L/mailpit/mailpit.db"; echo log > "$L/mailpit/mailpit.log"
    echo p > "$L/prestashop/tienda.parameters.php"; echo w > "$L/wordpress/plantilla"
    echo "otro" > "$L/otro.log"
    # Registros del programa
    echo "instalacion" > "$L/instalacion-20260101-101010.log"
    echo "abierta" > "$L/instalacion-20260202-101010.log"
    echo "db" > "$L/install-db.log"; echo "reposo" > "$L/docker-reposo.log"; echo "ventana" > "$L/ventana.log"
    mkdir -p "$L/pila-8.4-20261108-105826"; echo "fallo" > "$L/pila-8.4-20261108-105826/php-make.log"
    echo "node" > "$L/node/proyectos/web.log"
    # Las versiones
    for V in "$R/lampp-8.4" "$R/XAMPP-8.4.1"; do
        mkdir -p "$V/${SUB}logs" "$V/${SUB}var/mysql/wp_base" "$V/${SUB}temp"
        echo "acceso" > "$V/${SUB}logs/access_log"; echo "error" > "$V/${SUB}logs/error_log"
        echo "vhost" > "$V/${SUB}logs/web.local-error_log"; echo "fpm" > "$V/${SUB}logs/php-fpm.log"
        echo "php" > "$V/${SUB}logs/php_error_log"; echo "1234" > "$V/${SUB}logs/httpd.pid"
        echo "sock" > "$V/${SUB}logs/cgisock.4321"
        echo "err" > "$V/${SUB}var/mysql/mysqld.err"; echo "1" > "$V/${SUB}var/mysql/mysqld.pid"
        echo "datos" > "$V/${SUB}var/mysql/ibdata1"; echo "bin" > "$V/${SUB}var/mysql/mysql-bin.000001"
        echo "tabla" > "$V/${SUB}var/mysql/wp_base/wp_posts.ibd"
        echo "s" > "$V/${SUB}temp/sess_abc123"; echo "otro" > "$V/${SUB}temp/no-es-sesion"
        # (un registro enlazado a un fichero de fuera: no se vacia lo de fuera)
        ln -s "$R/fuera/dentro/importante" "$V/${SUB}logs/enlace_log"
    done
    # Copias y descargas
    echo "copia" > "$R/home/nexum-backups/a.sql.gz"; echo "copia" > "$R/home/nexum-backups/sub/b.sql.gz"
    echo "codigo" > "$R/descargas/php-8.4.1.tar.xz"; echo "suma" > "$R/descargas/php-8.4.1.tar.xz.sha256"
    # Temporales
    mkdir -p "$T/lvm-mysql-viej" "$T/lvm-pila-8.4-nuev" "$T/lvm-mysql-vivo" "$T/lvm-mysql-sock" "$T/lvm-pruebas.ABCDEF" "$T/otra-cosa"
    echo log > "$T/lvm-mysql-viej/mysql.log"; echo log > "$T/lvm-pila-8.4-nuev/build.log"
    echo $$ > "$T/lvm-mysql-vivo/mysql.pid"; echo x > "$T/lvm-pruebas.ABCDEF/x"; echo x > "$T/otra-cosa/x"
    echo t > "$T/lvm-hosts.Ab12Cd"; echo s > "$T/sess_mia"
    mkdir -p "$L/temporal/actualizar-viejo" "$L/temporal/actualizar-nuevo" "$L/ps-imagenes-abcd1234"
    echo x > "$L/temporal/actualizar-viejo/f"; echo x > "$L/temporal/actualizar-nuevo/f"; echo x > "$L/ps-imagenes-abcd1234/l"
    echo x > "$L/ps-imagenes-lista-Ab12Cd"; echo x > "$L/vhosts-docker-Xy12Zw"; echo x > "$L/pasar-web-Ab12Cd.sql.gz"
    # Proyectos: un WordPress, una tienda, una tienda 1.6 y una carpeta que no es ninguno
    local P=$R/htdocs/blog S=$R/htdocs/tienda O=$R/htdocs/tienda16
    mkdir -p "$P/wp-includes" "$P/wp-content/cache/pagina" "$P/wp-content/uploads/2026/11" "$P/wp-content/uploads/wc-logs" \
        "$P/wp-content/upgrade/plugin" "$P/wp-content/upgrade-temp-backup/plugins"
    echo "<?php" > "$P/wp-config.php"
    echo c > "$P/wp-content/cache/pagina/index.html"; echo d > "$P/wp-content/debug.log"
    echo foto > "$P/wp-content/uploads/2026/11/foto.jpg"; echo log > "$P/wp-content/uploads/2026/11/no-es-wc.log"
    echo w > "$P/wp-content/uploads/wc-logs/fatal-errors-2026.log"; echo h > "$P/wp-content/uploads/wc-logs/index.html"
    echo u > "$P/wp-content/upgrade/plugin/a.php"; echo u > "$P/wp-content/upgrade-temp-backup/plugins/b.php"
    ln -s "$R/fuera" "$P/wp-content/cache/enlace"
    mkdir -p "$S/classes" "$S/var/cache/prod" "$S/var/logs" "$S/cache/smarty/compile/ab" "$S/cache/smarty/cache" \
        "$S/img/p" "$S/modules/pago/logs" "$S/modules/envios/log"
    touch "$S/classes/PrestaShopAutoload.php"
    echo c > "$S/var/cache/prod/appParameters.php"; echo l > "$S/var/logs/prod.log"
    echo "<?php" > "$S/cache/smarty/compile/index.php"; echo c > "$S/cache/smarty/compile/ab/x.tpl.php"
    echo "<?php" > "$S/cache/smarty/cache/index.php"; echo c > "$S/cache/smarty/cache/y.tpl"
    echo foto > "$S/img/p/1.jpg"; echo l > "$S/modules/pago/logs/pago.log"; echo "<?php" > "$S/modules/pago/logs/index.php"
    echo l > "$S/modules/envios/log/envios.log"; echo m > "$S/modules/pago/pago.php"
    ln -s "$R/fuera" "$S/modules/fuera"
    mkdir -p "$R/fuera/logs"; echo "de fuera" > "$R/fuera/logs/ajeno.log"
    mkdir -p "$O/classes" "$O/cache/cachefs/1" "$O/log" "$O/cache/smarty/compile"
    touch "$O/classes/PrestaShopAutoload.php"
    echo "<?php" > "$O/cache/cachefs/index.php"; echo c > "$O/cache/cachefs/1/x"; echo l > "$O/log/20260101_exception.log"
    echo "<?php" > "$O/log/index.php"
    # (una cache que es un enlace a una carpeta de fuera: no se vacia)
    mkdir -p "$R/htdocs/enlazada/wp-includes" "$R/htdocs/enlazada/wp-content"; echo "<?php" > "$R/htdocs/enlazada/wp-config.php"
    ln -s "$R/fuera" "$R/htdocs/enlazada/wp-content/cache"
    mkdir -p "$R/htdocs/estatica"; echo hola > "$R/htdocs/estatica/index.html"
    # Todo de hace dos dias, salvo los temporales nuevos
    find "$R" -exec touch -h -d "2 days ago" {} +
    touch "$T/lvm-pila-8.4-nuev/build.log" "$L/temporal/actualizar-nuevo/f"
}

# Las variables del script para un equipo de prueba
use() {
    local R=$1
    HOME=$R/home LOG_DIR=$R/home/.nexum COPIES_DIR=$R/home/nexum-backups HTDOCS_DIR=$R/htdocs
    DL_CACHE_DIR=$R/descargas TEST_DIR=$R BASE_DIR=$R MAILPIT_DATA=$R/home/.nexum/mailpit
    CLEAN_TMP_DIRS=("$R/tmp") DRY=0 SUDO=""
}
listing() { (cd "$1" && find . -printf '%p %s %y\n' 2> /dev/null | sort) || (cd "$1" && find . | sort); }

# Un socket en uso (un MariaDB temporal en marcha) y un registro abierto por una tarea
inuse() {
    local R=$1
    python3 -I -c 'import socket, sys, time
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
s.listen(1)
time.sleep(120)' "$R/tmp/lvm-mysql-sock/mysql.sock" &
    PIDS+=($!)
    ( exec 3>> "$R/home/.nexum/instalacion-20260202-101010.log"; sleep 120 ) &
    PIDS+=($!)
    for _ in $(seq 50); do [ -S "$R/tmp/lvm-mysql-sock/mysql.sock" ] && break; sleep 0.1; done
    touch -h -d "2 days ago" "$R/tmp/lvm-mysql-sock/mysql.sock" "$R/tmp/lvm-mysql-sock"
}

R=$W/a; fixture "$R"; use "$R"; inuse "$R"
# Las versiones: en el Mac, XAMPP-*; en Linux (con LVM_PRUEBA), lampp-*
if [ $MAC -eq 1 ]; then rm -rf "$R/lampp-8.4"; VER=$R/XAMPP-8.4.1/xamppfiles; else rm -rf "$R/XAMPP-8.4.1"; VER=$R/lampp-8.4; fi
check "las versiones de la limpieza: las de esta prueba" '[ "$(clean_version_dirs)" = "${VER%/xamppfiles}" ]'

# --- Medir ---
o=$(clean_measure "${CLEAN_KEYS[@]}" | cut -d'|' -f1-4)
check "gui-limpieza: una linea L|<clave>|<bytes>|<ficheros> por clave, en su orden" '[ "$(cut -d"|" -f2 <<< "$o" | tr "\n" " ")" = "descargas copias correo registros registros-versiones caches-proyectos temporales sesiones " ] && ! grep -vqE "^L\|[a-z-]+\|[0-9]+\|[0-9]+$" <<< "$o"'
get() { grep "^L|$1|" <<< "$o" | cut -d'|' -f4; }
check "gui-limpieza: descargas (sin las .sha256), copias y correo (sin Mailpit, sus correos de la base: 0)" '[ "$(get descargas)" = 1 ] && [ "$(get copias)" = 2 ] && [ "$(get correo)" = 0 ]'
check "gui-limpieza: registros (sin los ajustes, sin otro.log ni el abierto; ventana.log)" '[ "$(get registros)" = 6 ]'
check "gui-limpieza: registros de las versiones (los 5 de Apache, PHP-FPM y PHP y el .err; no los enlaces)" '[ "$(get registros-versiones)" = 6 ]'
check "gui-limpieza: cachés de los proyectos (WordPress, tienda y tienda 1.6, sin los index.php)" '[ "$(get caches-proyectos)" = 6 ]'
check "gui-limpieza: temporales (los viejos que no estan en uso)" '[ "$(get temporales)" = 6 ]'
check "gui-limpieza: sesiones (la de la version y la tuya de la carpeta temporal)" '[ "$(get sesiones)" = 2 ]'
o=$(clean_list)
check "limpieza: cada cosa con lo que ocupa, cuantos ficheros y el total" 'grep -q "Registros del programa" <<< "$o" && grep -q "6 ficheros" <<< "$o" && grep -q "^Total: " <<< "$o" && grep -q "vacío" <<< "$o"'

# --- Con --simular no se borra nada ---
before=$(listing "$R")
o=$(DRY=1 clean_command descargas copias correo registros registros-versiones caches-proyectos temporales sesiones 2>&1)
check "limpiar con --simular: no borra ni vacia nada, solo lo dice" '[ "$(listing "$R")" = "$before" ] && grep -q "simulacion" <<< "$o" && [ ! -e "$W/correo.log" ]'
o=$(DRY=1 clean_project_command tienda 2>&1)
check "limpiar-proyecto con --simular: tampoco" '[ "$(listing "$R")" = "$before" ] && grep -q "simulacion" <<< "$o"'

# --- Claves que no valen ---
o=$(clean_command todo 2>&1); rc=$?
check "limpiar con una clave que no existe: error, sin borrar nada" '[ $rc -ne 0 ] && grep -q "Clave no valida" <<< "$o" && [ "$(listing "$R")" = "$before" ]'
o=$(clean_command 2>&1); rc=$?
check "limpiar sin claves: uso" '[ $rc -ne 0 ] && grep -q "Uso:" <<< "$o"'

# --- registros ---
L=$R/home/.nexum
o=$(clean_command registros 2>&1); rc=$?
check "registros: borra los de las instalaciones, install-db, el de reposo, los de Node y pila-<version>-<fecha>" '[ $rc -eq 0 ] && [ ! -e "$L/instalacion-20260101-101010.log" ] && [ ! -e "$L/install-db.log" ] && [ ! -e "$L/docker-reposo.log" ] && [ ! -e "$L/node/proyectos/web.log" ] && [ ! -e "$L/pila-8.4-20261108-105826" ]'
check "registros: ventana.log (abierto por la ventana) se vacia, no se borra" '[ -f "$L/ventana.log" ] && [ ! -s "$L/ventana.log" ]'
check "registros: el de una tarea en marcha (abierto) se deja, y lo dice" '[ -s "$L/instalacion-20260202-101010.log" ] && grep -q "En uso" <<< "$o"'
ok_settings=1
for f in apariencia botones-visor copias-ficheros ultima-version dominios proyectos hosts media-produccion github importaciones \
    locales-apagados montados-de-repositorio prestashop-cargados repos-github sin-barrera-entre-webs ventana-tema ventana-plegados \
    httpd-vhosts.conf certificados actualizaciones-arranques; do
    [ "$(cat "$L/$f" 2> /dev/null)" = "ajuste $f" ] || ok_settings=0
done
check "registros: los ajustes de ~/.nexum, intactos" '[ $ok_settings -eq 1 ]'
check "registros: tunel, docker, mailpit, prestashop, wordpress y otro.log (no es del programa), intactos" '[ -s "$L/tunel/registro" ] && [ -s "$L/tunel/estado" ] && [ -s "$L/docker/web/web.conf" ] && [ -s "$L/mailpit/mailpit.db" ] && [ -s "$L/mailpit/mailpit.log" ] && [ -s "$L/prestashop/tienda.parameters.php" ] && [ -s "$L/wordpress/plantilla" ] && [ -s "$L/otro.log" ]'

# --- registros-versiones ---
o=$(clean_command registros-versiones 2>&1); rc=$?
check "registros-versiones: los de Apache (con los de cada vhost), PHP-FPM, PHP y el .err, a 0 bytes y sin borrar" '[ $rc -eq 0 ] && for f in logs/access_log logs/error_log logs/web.local-error_log logs/php-fpm.log logs/php_error_log var/mysql/mysqld.err; do [ -f "$VER/$f" ] && [ ! -s "$VER/$f" ] || exit 1; done'
check "registros-versiones: los .pid, los cgisock y los datos de MariaDB (binlogs y tablas), intactos" '[ -s "$VER/logs/httpd.pid" ] && [ -s "$VER/logs/cgisock.4321" ] && [ -s "$VER/var/mysql/mysqld.pid" ] && [ -s "$VER/var/mysql/ibdata1" ] && [ -s "$VER/var/mysql/mysql-bin.000001" ] && [ -s "$VER/var/mysql/wp_base/wp_posts.ibd" ]'
check "registros-versiones: un registro que es un enlace no se sigue (lo de fuera sigue)" '[ -L "$VER/logs/enlace_log" ] && [ "$(cat "$R/fuera/dentro/importante")" = "no se toca" ]'

# --- caches-proyectos, limpiar-proyecto ---
P=$R/htdocs/blog S=$R/htdocs/tienda O=$R/htdocs/tienda16
o=$(gui_clean_project tienda)
check "gui-limpiar-proyecto: P|<clave>|<bytes>|<ficheros>|<rutas> de lo que tiene algo" 'grep -qx "P|cache|[0-9]*|3|var/cache,cache/smarty/compile,cache/smarty/cache" <<< "$o" && grep -qx "P|registros|[0-9]*|3|var/logs,modules/\*/logs/\*.log,modules/\*/log/\*.log" <<< "$o" && [ "$(grep -c . <<< "$o")" = 2 ]'
o=$(gui_clean_project blog)
check "gui-limpiar-proyecto de un WordPress: cache, registros (debug.log y wc-logs) y actualizaciones" 'grep -qx "P|cache|[0-9]*|2|wp-content/cache" <<< "$o" && grep -qx "P|registros|[0-9]*|2|wp-content/debug.log,wp-content/uploads/wc-logs/\*.log" <<< "$o" && grep -qx "P|actualizaciones|[0-9]*|2|wp-content/upgrade,wp-content/upgrade-temp-backup" <<< "$o"'
check "gui-limpiar-proyecto de una carpeta sin nada: nada" '[ -z "$(gui_clean_project estatica)" ] && [ -z "$(gui_clean_project enlazada)" ]'
o=$(clean_project_command estatica 2>&1)
check "limpiar-proyecto de una carpeta que no es WordPress ni PrestaShop: lo dice" 'grep -q "No hay cachés ni registros que limpiar en estatica" <<< "$o"'
check "limpiar-proyecto: una carpeta que no existe o con / no vale" '! clean_project_command ../a > /dev/null 2>&1 && ! clean_project_command noexiste > /dev/null 2>&1'
o=$(clean_command caches-proyectos 2>&1); rc=$?
check "caches-proyectos: wp-content/cache vacia (la carpeta se queda)" '[ $rc -eq 0 ] && [ -d "$P/wp-content/cache" ] && [ -z "$(ls -A "$P/wp-content/cache")" ]'
check "caches-proyectos: un enlace dentro de una cache se borra sin seguirlo (lo de fuera sigue)" '[ "$(cat "$R/fuera/dentro/importante")" = "no se toca" ] && [ -s "$R/fuera/logs/ajeno.log" ]'
check "caches-proyectos: una cache que es un enlace a fuera no se vacia" '[ -L "$R/htdocs/enlazada/wp-content/cache" ] && [ -d "$R/fuera/dentro" ]'
check "caches-proyectos: var/cache y smarty de la tienda vacias, sus index.php se quedan" '[ -d "$S/var/cache" ] && [ -z "$(ls -A "$S/var/cache")" ] && [ "$(ls -A "$S/cache/smarty/compile")" = index.php ] && [ "$(ls -A "$S/cache/smarty/cache")" = index.php ]'
check "caches-proyectos: la cachefs de la tienda 1.6, sin su index.php" '[ "$(ls -A "$O/cache/cachefs")" = index.php ]'
check "caches-proyectos: los registros y las actualizaciones no son cache: siguen" '[ -s "$P/wp-content/debug.log" ] && [ -s "$S/var/logs/prod.log" ] && [ -s "$P/wp-content/upgrade/plugin/a.php" ]'
o=$(clean_project_command tienda 2>&1); rc=$?
check "limpiar-proyecto de la tienda: var/logs vacia y los registros de los modulos (no su index.php)" '[ $rc -eq 0 ] && [ -d "$S/var/logs" ] && [ -z "$(ls -A "$S/var/logs")" ] && [ ! -e "$S/modules/pago/logs/pago.log" ] && [ -f "$S/modules/pago/logs/index.php" ] && [ ! -e "$S/modules/envios/log/envios.log" ] && [ -f "$S/modules/pago/pago.php" ]'
check "limpiar-proyecto de la tienda: img/ intacta y un modulo enlazado a fuera no se sigue" '[ -s "$S/img/p/1.jpg" ] && [ -s "$R/fuera/logs/ajeno.log" ] && [ -L "$S/modules/fuera" ]'
o=$(clean_project_command tienda16 registros 2>&1)
check "limpiar-proyecto de la tienda 1.6: log/ sin su index.php" '[ "$(ls -A "$O/log")" = index.php ]'
check "limpiar-proyecto: dice «Registros de <carpeta>» (no los del programa)" 'grep -q "^Registros de tienda16: borrados " <<< "$o" && ! grep -q "Registros del programa" <<< "$o"'
o=$(clean_project_command blog registros actualizaciones 2>&1); rc=$?
check "limpiar-proyecto del WordPress: debug.log y los wc-logs/*.log fuera; uploads intacto (salvo wc-logs)" '[ $rc -eq 0 ] && [ ! -e "$P/wp-content/debug.log" ] && [ ! -e "$P/wp-content/uploads/wc-logs/fatal-errors-2026.log" ] && [ -s "$P/wp-content/uploads/wc-logs/index.html" ] && [ -s "$P/wp-content/uploads/2026/11/foto.jpg" ] && [ -s "$P/wp-content/uploads/2026/11/no-es-wc.log" ]'
check "limpiar-proyecto del WordPress: upgrade y upgrade-temp-backup vacias (las carpetas se quedan)" '[ -d "$P/wp-content/upgrade" ] && [ -z "$(ls -A "$P/wp-content/upgrade")" ] && [ -d "$P/wp-content/upgrade-temp-backup" ] && [ -z "$(ls -A "$P/wp-content/upgrade-temp-backup")" ]'
check "limpiar-proyecto con una clave que no existe: error" '! clean_project_command blog todo > /dev/null 2>&1'

# --- temporales ---
T=$R/tmp
o=$(clean_command temporales 2>&1); rc=$?
check "temporales: los lvm-* viejos se borran" '[ $rc -eq 0 ] && [ ! -e "$T/lvm-mysql-viej" ] && [ ! -e "$T/lvm-hosts.Ab12Cd" ]'
check "temporales: los de menos de un dia siguen" '[ -s "$T/lvm-pila-8.4-nuev/build.log" ] && [ -s "$L/temporal/actualizar-nuevo/f" ]'
check "temporales: en uso (un .pid vivo, un socket con su servidor), siguen" '[ -s "$T/lvm-mysql-vivo/mysql.pid" ] && [ -S "$T/lvm-mysql-sock/mysql.sock" ]'
check "temporales: lo que no es del programa (lvm-pruebas, otra-cosa, sesiones) sigue" '[ -d "$T/lvm-pruebas.ABCDEF" ] && [ -d "$T/otra-cosa" ] && [ -f "$T/sess_mia" ]'
check "temporales de ~/.nexum: temporal/ vieja, ps-imagenes y los de mktemp; la carpeta temporal se queda" '[ -d "$L/temporal" ] && [ ! -e "$L/temporal/actualizar-viejo" ] && [ ! -e "$L/ps-imagenes-abcd1234" ] && [ ! -e "$L/ps-imagenes-lista-Ab12Cd" ] && [ ! -e "$L/vhosts-docker-Xy12Zw" ]'
check "temporales: la copia de pasar a Docker (pasar-*) sigue: puede ser la unica de su BBDD" '[ -s "$L/pasar-web-Ab12Cd.sql.gz" ]'

# --- sesiones ---
o=$(clean_command sesiones 2>&1); rc=$?
check "sesiones: las sess_* de la version y las tuyas de la carpeta temporal; lo demas sigue" '[ $rc -eq 0 ] && [ ! -e "$VER/temp/sess_abc123" ] && [ -s "$VER/temp/no-es-sesion" ] && [ ! -e "$T/sess_mia" ]'

# --- descargas, copias y correo: con lo suyo ---
o=$(clean_command descargas copias correo 2>&1); rc=$?
check "descargas y copias: vacias (con descargas vaciar y copias vaciar); correo vacio, sin tocar Mailpit" '[ -z "$(ls -A "$R/descargas")" ] && [ -d "$R/home/nexum-backups" ] && [ -z "$(ls -A "$R/home/nexum-backups")" ] && [ ! -e "$W/correo.log" ] && grep -q "Correo de pruebas (Mailpit): nada que limpiar" <<< "$o"'
check "despues de todo, los ajustes siguen y lo de fuera tambien" '[ $ok_settings -eq 1 ] && [ "$(cat "$L/apariencia")" = "ajuste apariencia" ] && [ "$(cat "$R/fuera/dentro/importante")" = "no se toca" ]'

# --- Lo que tu usuario no puede borrar: sudo, solo con CLEAN_PY ---
R=$W/b; fixture "$R"; use "$R"
[ $MAC -eq 1 ] && rm -rf "$R/lampp-8.4" || rm -rf "$R/XAMPP-8.4.1"
chmod 555 "$R/tmp/lvm-mysql-viej"
o=$(clean_need_root temporales && echo root)
check "clean_need_root: lo que no puede borrar tu usuario pide root" '[ "$o" = root ]'
check "clean_need_root: los registros del programa, no" '! clean_need_root registros'
sudo() { echo "sudo $1 $2 $3" >> "$W/sudo.log"; [ "$1" == python3 ] && [ "$2" == -I ] && [ "$3" == -c ] && [ "$4" == "$CLEAN_PY" ] || return 99; chmod -R u+w "$R/tmp/lvm-mysql-viej"; "$@"; }
o=$(SUDO=sudo clean_command temporales 2>&1); rc=$?
check "con sudo: solo CLEAN_PY (nada de rm ni find), y lo borra" '[ $rc -eq 0 ] && [ ! -e "$R/tmp/lvm-mysql-viej" ] && [ "$(grep -c . "$W/sudo.log")" = 1 ] && grep -qx "sudo python3 -I -c" "$W/sudo.log" && grep -q "con sudo" <<< "$o"'
unset -f sudo
chmod 555 "$R/home/.nexum/pila-8.4-20261108-105826"
o=$(clean_command registros 2>&1); rc=$?
check "sin sudo, lo que no se puede borrar se dice (y lo demas se borra)" '[ $rc -ne 0 ] && grep -q "No se ha podido limpiar todo" <<< "$o" && [ ! -e "$R/home/.nexum/install-db.log" ]'
chmod 755 "$R/home/.nexum/pila-8.4-20261108-105826"

# --- CLEAN_PY: la raiz y la ruta sin enlaces, dentro de su carpeta ---
mkdir -p "$W/c/real/cache" "$W/c/proy"; echo x > "$W/c/real/cache/f"; ln -s "$W/c/real" "$W/c/enlace"; ln -s "$W/c/real/cache" "$W/c/proy/cache"
o=$(python3 -I -c "$CLEAN_PY" limpiar "k|$W/c/enlace|vaciar|cache||" 2>&1)
check "CLEAN_PY: una raiz que es un enlace no se toca" '[ -s "$W/c/real/cache/f" ] && grep -q "enlace" <<< "$o"'
python3 -I -c "$CLEAN_PY" limpiar "k|$W/c/proy|vaciar|cache||" > /dev/null 2>&1
check "CLEAN_PY: una ruta con un enlace dentro de la raiz no se sigue" '[ -s "$W/c/real/cache/f" ]'
python3 -I -c "$CLEAN_PY" limpiar "k|$W/c/proy|vaciar|../real/cache||" > /dev/null 2>&1
check "CLEAN_PY: .. no sale de la raiz" '[ -s "$W/c/real/cache/f" ]'
o=$(python3 -I -c "$CLEAN_PY" limpiar "k|$W/c/real|borrar|cache||" 2>&1)
check "CLEAN_PY: una regla que no es de las suyas no hace nada" '[ -s "$W/c/real/cache/f" ] && grep -q "no valida" <<< "$o"'

# --- El script entero (Linux, con LVM_PRUEBA y todo en carpetas temporales) ---
if [ $MAC -eq 0 ]; then
    R=$W/s; fixture "$R"; rm -rf "$R/XAMPP-8.4.1"
    mkdir -p "$R/config"
    E=(env -u LVM_SIMULAR -u LVM_TAREA HOME="$R/home" LVM_PRUEBA="$R" LVM_HTDOCS="$R/htdocs" LVM_VHOSTS="$R/config/httpd-vhosts.conf")
    o=$("${E[@]}" bash "$SRC" gui-limpieza 2>&1)
    check "el script: gui-limpieza" '[ "$(grep -c "^L|" <<< "$o")" = 8 ] && grep -q "^L|registros-versiones|[0-9]*|6$" <<< "$o"'
    before=$(listing "$R")
    "${E[@]}" bash "$SRC" --simular limpiar descargas copias registros registros-versiones caches-proyectos temporales sesiones > /dev/null 2>&1
    "${E[@]}" bash "$SRC" --simular limpiar-proyecto tienda > /dev/null 2>&1
    check "el script con --simular: limpiar y limpiar-proyecto no tocan nada" '[ "$(listing "$R")" = "$before" ]'
    o=$("${E[@]}" bash "$SRC" limpiar registros registros-versiones caches-proyectos 2>&1); rc=$?
    check "el script: limpiar" '[ $rc -eq 0 ] && [ ! -e "$R/home/.nexum/install-db.log" ] && [ ! -s "$R/lampp-8.4/logs/error_log" ] && [ -f "$R/lampp-8.4/logs/error_log" ] && [ -s "$R/home/.nexum/apariencia" ] && grep -q "Limpieza terminada" <<< "$o"'
    o=$("${E[@]}" bash "$SRC" limpiar-proyecto blog 2>&1); rc=$?
    check "el script: limpiar-proyecto" '[ $rc -eq 0 ] && [ ! -e "$R/htdocs/blog/wp-content/debug.log" ] && [ -s "$R/htdocs/blog/wp-content/uploads/2026/11/foto.jpg" ]'
    mkdir -p "$W/bin"; printf '#!/bin/sh\necho "$@" >> %s/sudo-script.log\nexit 1\n' "$W" > "$W/bin/sudo"; chmod +x "$W/bin/sudo"
    o=$(env -u LVM_SIMULAR -u LVM_PRUEBA PATH="$W/bin:$PATH" LVM_TAREA=1 HOME="$R/home" bash "$SRC" limpieza 2>&1); rc=$?
    check "el script, como tarea de la ventana: limpieza sin sudo" '[ $rc -eq 0 ] && [ ! -e "$W/sudo-script.log" ] && grep -q "^Total" <<< "$o"'
fi

exit $fail
