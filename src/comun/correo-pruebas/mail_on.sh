function mail_on() {
    [ ! -e "$MAIL_OFF_FILE" ]
}

# Modo de los plugins de correo de WordPress: mailpit, desactivar o nada
function mail_wp_mode() {
    local m=""
    [ -f "$MAIL_WP_FILE" ] && m=$(head -c 20 "$MAIL_WP_FILE" | tr -d ' \n')
    case $m in
        desactivar|nada) echo "$m" ;;
        *) echo mailpit ;;
    esac
}

function mailpit_installed() {
    [ -f "$MAILPIT_BIN" ] && [ -x "$MAILPIT_BIN" ] && [ ! -L "$MAILPIT_BIN" ]
}

function mailpit_installed_version() {
    head -c 20 "$MAILPIT_DIR/version" 2> /dev/null | head -1 | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$'
}

# Lo que SECURE_PY pone en el PHP de cada version (LVM_CORREO): binario|puerto|WordPress a Mailpit
# (1/0). Nada con el correo apagado. Sin Mailpit instalado tambien: mail() falla en lugar de salir
function mail_secure_spec() {
    mail_on || return 0
    echo "$MAILPIT_BIN|$MAIL_SMTP_PORT|$([ "$(mail_wp_mode)" == mailpit ] && echo 1 || echo 0)"
}

