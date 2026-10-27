#!/bin/bash
# Cargar un proyecto es todo o nada (Linux 1.55.2): si un paso falla o la ventana cancela la tarea
# (TERM), el enlace del vhost vuelve al proyecto de antes y no queda a medias (Mac 1.39.12). Uso:
# carga-cancelar.sh <lvm-instalador.sh>   (Linux o Mac)
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-carga.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
grep -q '^function load_project_undo() {' "$SRC" || { echo "  ok    (sin carga todo o nada)"; exit 0; }
extract "$SRC" load_project load_project_undo load_project_steps || exit 1

HTDOCS_DIR=$W/htdocs DRY=0 SUDO=""
mkdir -p "$HTDOCS_DIR/antes" "$HTDOCS_DIR/nuevo"
ln -s antes/ "$HTDOCS_DIR/web.local"
# Lo de fuera, falso: sin sudo, sin versiones y sin Apache de verdad
run() { [ "$1" == sudo ] && { echo "sudo ${*:2}" >> "$W/sudo.log"; return 0; }; "$@"; }
valid_project() { [ -d "$HTDOCS_DIR/$1" ]; }
valid_version_name() { true; }
project_link() { echo web.local; }
htdocs_close_world() { :; }
ensure_web_user() { :; }
secure_lampp() { return 1; }
vhosts_root() { return 1; }
active_dir() { echo ""; }
active_name() { echo ""; }
lampp_running() { true; }
use_lampp() { echo "use $1" >> "$W/sudo.log"; }
use_version() { echo "use $1" >> "$W/sudo.log"; }
xampp_ctl() { echo "xampp $*" >> "$W/sudo.log"; }
secure_version() { return 1; }
LINK=$W/sin-version
remember_project() { :; }
mailpit_sync() { :; }
mail_project_db() { return 1; }

# Un paso falla: el enlace vuelve al de antes
load_project_domain() { return 1; }
out=$(load_project nuevo "" wp_x 2>&1); rc=$?
check "si un paso falla, no se carga y lo dice" '[ $rc -ne 0 ] && grep -q "Se deja como estaba" <<< "$out"'
check "si un paso falla, el enlace vuelve al proyecto de antes" '[ "$(readlink "$HTDOCS_DIR/web.local")" == antes/ ]'

# La ventana cancela a mitad (TERM): igual
load_project_domain() { kill -TERM $BASHPID; sleep 1; return 0; }
out=$( (load_project nuevo "" wp_x) 2>&1); rc=$?
check "al cancelar a mitad, la tarea acaba sin cargarlo" '[ $rc -eq 130 ] && grep -q "Se deja como estaba" <<< "$out" && ! grep -q "Proyecto cargado" <<< "$out"'
check "al cancelar a mitad, el enlace vuelve al proyecto de antes" '[ "$(readlink "$HTDOCS_DIR/web.local")" == antes/ ]'

# Sin fallos: cargado, y sin deshacer nada
load_project_domain() { :; }
out=$(load_project nuevo "" wp_x 2>&1); rc=$?
check "sin fallos, cargado (y sin deshacer)" '[ $rc -eq 0 ] && [ "$(readlink "$HTDOCS_DIR/web.local")" == nuevo/ ] && ! grep -q "Se deja como estaba" <<< "$out"'
check "despues, una señal ya no deshace nada" '[ -z "$(trap -p TERM)" ]'
check "la contraseña se pide antes de cambiar nada" 'awk "/^function load_project\\(\\) \\{/,/^}/" "$SRC" | grep "sudo -v\|load_project_steps" | head -1 | grep -q "sudo -v"'

# Desmontar (Linux 1.55.12 / Mac 1.39.23): la contraseña antes de nada y todo o nada
if grep -q '^function unload_project_steps() {' "$SRC"; then
    extract "$SRC" unload_project unload_project_steps sudo_first || exit 1
    grep -q '^function empty_page() {' "$SRC" && { extract "$SRC" empty_page || exit 1; }
    ICON_PNG_B64=$(printf 'png' | base64) LOG_DIR=$W/log
    EMPTY_PROJECT=sin-proyecto PROJECT_VHOST=web.local LINK=$W/sin-version
    mkdir -p "$HTDOCS_DIR/$EMPTY_PROJECT"
    project_write() { cp "$1" "$2"; }
    ln -sfn nuevo/ "$HTDOCS_DIR/web.local"
    SUDO=sudo
    sudo() { return 1; }
    out=$(unload_project 2>&1); rc=$?
    check "desmontar, cancelada la contraseña: no se desmonta y lo dice" '[ $rc -ne 0 ] && grep -q "no se ha cambiado nada" <<< "$out" && [ "$(readlink "$HTDOCS_DIR/web.local")" == nuevo/ ]'
    sudo() { return 0; }
    hosts_fake() { return 1; }
    out=$(unload_project 2>&1); rc=$?
    check "desmontar, si un paso falla: el proyecto sigue cargado" '[ $rc -ne 0 ] && grep -q "Se deja como estaba" <<< "$out" && [ "$(readlink "$HTDOCS_DIR/web.local")" == nuevo/ ]'
    hosts_fake() { :; }
    out=$(unload_project 2>&1); rc=$?
    check "desmontar sin fallos: desmontado" '[ $rc -eq 0 ] && [ "$(readlink "$HTDOCS_DIR/web.local")" == sin-proyecto/ ]'
    # (Linux 1.56.0) La pagina sin proyecto: logotipo y nombre de Nexum Dev Stack, sin nada de fuera
    if grep -q '^function empty_page() {' "$SRC"; then
        page=$HTDOCS_DIR/$EMPTY_PROJECT/index.html
        check "pagina sin proyecto: con el logotipo y el nombre de Nexum Dev Stack" 'grep -q "<img src=\"data:image/png;base64,$ICON_PNG_B64\"" "$page" && grep -q "Abre <b>Nexum Dev Stack</b>" "$page" && ! grep -q lvm-instalador "$page"'
        check "pagina sin proyecto: no pide nada a otro sitio" '! grep -qE "(src|href)=\"(https?:)?//" "$page"'
        echo antigua > "$page"
        DRY=0 empty_page "$HTDOCS_DIR/$EMPTY_PROJECT"
        check "pagina sin proyecto: la de una version anterior se cambia por la nueva" 'grep -q "NEXUM" "$page"'
        before=$(stat -c %Y "$page"); touch -d "2000-01-01" "$page"
        DRY=0 empty_page "$HTDOCS_DIR/$EMPTY_PROJECT"
        check "pagina sin proyecto: si no ha cambiado, no se vuelve a escribir" '[ "$(stat -c %Y "$page")" == "$(date -d 2000-01-01 +%s)" ]'
    fi
    SUDO=""
fi
check "tareas de la ventana: lo que cambia algo pide la contraseña antes de empezar" 'grep -q "env\[\"LVM_TAREA\"\] = \"1\"\|extra\[\"LVM_TAREA\"\] = \"1\"" "$SRC" && sed -n "/^if \[ \"\${LVM_TAREA:-}\" == 1 \]; then/,/^fi/p" "$SRC" | grep -q "\*) sudo_first || exit 130 ;;"'
exit $fail
