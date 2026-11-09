# Tu usuario (el de SUDO_USER si esto corre con sudo), para Apache, PHP-FPM y los permisos: solo un
# nombre valido de un usuario que existe (va a la configuracion que lee root). Si no, el que corre
function web_user_name() {
    local u=${SUDO_USER:-$USER}
    if [[ "$u" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,31}$ ]] && id "$u" > /dev/null 2>&1; then
        echo "$u"
    else
        id -un
    fi
}

# Proyectos nuevos con dominio falseado (pestaña Hosts): dominio=carpeta, uno por linea
CUSTOM_DOMAINS_FILE="$HOME/.lvm-instalador/dominios"

# Dominio personalizado de una carpeta (vacio si no tiene)
function custom_domain() {
    local d
    [ -f "$CUSTOM_DOMAINS_FILE" ] || return 0
    d=$(awk -F= -v f="$1" '$2 == f { d = $1 } END { if (d != "") print d }' "$CUSTOM_DOMAINS_FILE")
    # El fichero es tuyo: solo un dominio valido (sin /, .., espacios ni saltos de linea)
    [ -n "$d" ] && valid_domain "$d" && echo "$d"
    return 0
}

