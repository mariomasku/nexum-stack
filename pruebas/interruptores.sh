#!/bin/bash
# Interruptores de la ventana que piden la contraseña de administrador (Linux 1.55.4 / Mac 1.39.14):
# si se cancela, el ajuste se queda como estaba (barrera entre webs, correo de pruebas, modo de
# WordPress y los .local de Dominios y hosts). Uso: interruptores.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-interruptores.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
grep -q '^function sudo_first() {' "$SRC" || { echo "  ok    (sin sudo_first)"; exit 0; }
MAC=0; grep -q '^function web_barrier_command() {' "$SRC" && MAC=1
extract "$SRC" sudo_first mail_command hosts_fake_one || exit 1

# sudo falso que no da la contraseña (como al pulsar Cancelar) y lo que haria falta despues, apuntado
LOG_DIR=$W/log DRY=0 SUDO=sudo
mkdir -p "$LOG_DIR"
sudo() { echo "sudo $*" >> "$W/sudo.log"; return 1; }
mail_on() { [ ! -e "$MAIL_OFF_FILE" ]; }
mail_wp_mode() { cat "$MAIL_WP_FILE" 2> /dev/null || echo mailpit; }
mail_wp_text() { echo "$1"; }
mailpit_installed() { true; }
mailpit_install() { echo instalar >> "$W/hecho.log"; }
mail_apply() { echo aplicar >> "$W/hecho.log"; }
MAIL_OFF_FILE=$LOG_DIR/correo-apagado MAIL_WP_FILE=$LOG_DIR/correo-wordpress

check "sudo_first: sin la contraseña, no sigue y lo dice" 'o=$(sudo_first); [ $? -ne 0 ] && grep -q "no se ha cambiado nada" <<< "$o"'
o=$(mail_command no)
check "correo no, cancelado: sigue encendido y no se aplica nada" '[ ! -e "$MAIL_OFF_FILE" ] && [ ! -e "$W/hecho.log" ]'
: > "$MAIL_OFF_FILE"
o=$(mail_command si --instalar)
check "correo si, cancelado: sigue apagado, sin instalar ni aplicar nada" '[ -e "$MAIL_OFF_FILE" ] && [ ! -e "$W/hecho.log" ]'
rm -f "$MAIL_OFF_FILE"
o=$(mail_command wordpress nada)
check "modo de WordPress, cancelado: el de antes" '[ ! -e "$MAIL_WP_FILE" ] && [ ! -e "$W/hecho.log" ]'

# Un .local de Dominios y hosts: apagarlo cancelado no lo apunta como apagado
LOCAL_OFF_FILE=$W/locales-apagados PROJECT_VHOST=web.local VHOSTS_FILE=$W/vhosts.conf
valid_domain() { true; }
project_link() { echo web.local; }
vhosts_info() { echo "80|tienda|tienda.local||"; }
local_off() { echo "$*" >> "$LOCAL_OFF_FILE"; }
hosts_fake() { echo "hosts $*" >> "$W/hecho.log"; }
o=$(hosts_fake_one tienda.local no)
check "apagar un .local, cancelado: no se apunta ni se toca hosts" '[ ! -e "$LOCAL_OFF_FILE" ] && [ ! -e "$W/hecho.log" ]'

# La barrera entre webs
if [ $MAC -eq 0 ]; then
    extract "$SRC" cross_site_command cross_site_on || exit 1
    CROSS_SITE_OFF=$LOG_DIR/sin-barrera-entre-webs
    secure_all() { echo asegurar >> "$W/hecho.log"; return 0; }
    o=$(cross_site_command no)
    check "barrera no, cancelada: sigue encendida y no se aplica" '[ ! -e "$CROSS_SITE_OFF" ] && [ ! -e "$W/hecho.log" ]'
    # Sin poder aplicarla en todas las versiones: vuelve a como estaba
    sudo() { return 0; }
    secure_all() { echo asegurar >> "$W/hecho.log"; [ -e "$CROSS_SITE_OFF" ] && return 2 || return 0; }
    o=$(cross_site_command no)
    check "barrera no, sin poder aplicarla: vuelve a encendida y lo dice" '[ ! -e "$CROSS_SITE_OFF" ] && grep -q "se deja como estaba" <<< "$o"'
else
    extract "$SRC" web_barrier_command web_barrier_on || exit 1
    COMMON=$W/compartido WEB_BARRIER_OFF=$W/compartido/lvm-sin-barrera-web
    mkdir -p "$COMMON"
    secure_all() { echo asegurar >> "$W/hecho.log"; return 0; }
    o=$(web_barrier_command no)
    check "barrera no, cancelada: sigue puesta y no se aplica" '[ ! -e "$WEB_BARRIER_OFF" ] && [ ! -e "$W/hecho.log" ]'
fi
exit $fail
