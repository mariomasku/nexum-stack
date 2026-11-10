# Hasta la 1.57.6 las copias de seguridad iban en ~/lvm-copias: la primera vez se renombra a
# ~/nexum-backups (COPIES_DIR). Solo si es una carpeta tuya (no un enlace) y aun no hay ninguna
# ~/nexum-backups: si estan las dos, no se toca ninguna
function copies_migrate() {
    local old=$HOME/lvm-copias
    [ -d "$old" ] && [ ! -L "$old" ] && [ -O "$old" ] || return 0
    if [ -e "$COPIES_DIR" ] || [ -L "$COPIES_DIR" ]; then
        return 0
    fi
    mv "$old" "$COPIES_DIR" 2> /dev/null && chmod 700 "$COPIES_DIR" 2> /dev/null
    return 0
}

# Lo que ocupa (en KB) dicho para personas: 3,4 MB
function copies_size_text() {
    awk -v n="${1:-0}" 'BEGIN {
        split("KB MB GB TB", u); i = 1
        while (n >= 1024 && i < 4) { n /= 1024; i++ }
        s = (i == 1) ? sprintf("%d %s", n, u[i]) : sprintf("%.1f %s", n, u[i])
        gsub(/\./, ",", s); print s
    }'
}

# ¿Hay en ~/nexum-backups carpetas que no son tuyas (copias que hizo root)? Lo de dentro solo se puede
# borrar con sudo
function copies_need_root() {
    [ -d "$COPIES_DIR" ] && [ ! -L "$COPIES_DIR" ] || return 1
    [ -n "$(find "$COPIES_DIR" -mindepth 1 -type d ! -user "$(id -u)" -print 2> /dev/null | head -1)" ]
}

# copias [vaciar]: sin nada, cuantos ficheros hay en ~/nexum-backups y cuanto ocupan. vaciar borra todo
# lo que hay dentro (la carpeta se queda), despues de comprobar que es una carpeta tuya y no un enlace.
# Lo que no se pueda borrar con tu usuario (copias que hizo root en una carpeta suya) se borra con
# sudo, solo dentro de esa carpeta y sin pasar a otros discos. Con --simular no se borra nada
function copies_command() {
    local dir=$COPIES_DIR files kb left
    case "$1" in
        ""|vaciar) ;;
        *) echo "Uso: nexum copias [vaciar]"; return 1 ;;
    esac
    if [ -L "$dir" ] || { [ -e "$dir" ] && [ ! -d "$dir" ]; }; then
        echo "$dir no es una carpeta (es un enlace o un fichero): no se toca"
        return 1
    fi
    if [ ! -d "$dir" ]; then
        echo "No hay copias de seguridad: $dir no existe"
        return 0
    fi
    if [ ! -O "$dir" ]; then
        echo "$dir no es tuya: no se toca"
        return 1
    fi
    files=$(find "$dir" -mindepth 1 -type f 2> /dev/null | wc -l | tr -d ' ')
    kb=$(du -sk "$dir" 2> /dev/null | cut -f1)
    if [ "$1" != vaciar ]; then
        echo "Copias de seguridad en $dir: $files $([ "$files" == 1 ] && echo fichero || echo ficheros), $(copies_size_text "${kb:-0}")"
        return 0
    fi
    if [ -z "$(find "$dir" -mindepth 1 -maxdepth 1 2> /dev/null | head -1)" ]; then
        echo "No hay copias de seguridad que borrar: $dir esta vacia"
        return 0
    fi
    echo "Borrando las copias de seguridad de $dir ($files $([ "$files" == 1 ] && echo fichero || echo ficheros), $(copies_size_text "${kb:-0}"))..."
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] find $dir -xdev -mindepth 1 -delete (la carpeta se queda)"
        return 0
    fi
    # (find -delete no sigue los enlaces: un enlace de dentro se borra, no lo que hay al otro lado)
    find "$dir" -xdev -mindepth 1 -delete 2> /dev/null
    left=$(find "$dir" -mindepth 1 -maxdepth 1 2> /dev/null | head -1)
    if [ -n "$left" ] && [ -n "$SUDO" ]; then
        echo "Algunas copias son de root: se borran con sudo (solo dentro de $dir)"
        # (se vuelve a comprobar justo antes: que sigue siendo tu carpeta y no un enlace)
        if [ -L "$dir" ] || [ ! -d "$dir" ] || [ ! -O "$dir" ]; then
            echo "$dir ha cambiado: no se borra nada mas"
            return 1
        fi
        sudo find "$dir" -xdev -mindepth 1 -delete
        left=$(find "$dir" -mindepth 1 -maxdepth 1 2> /dev/null | head -1)
    fi
    if [ -n "$left" ]; then
        echo "No se ha podido borrar todo: queda, por ejemplo, $left"
        return 1
    fi
    echo "Copias de seguridad borradas ($dir esta vacia)"
}

# copias-ficheros [si|no]: las copias de los ficheros que el programa cambia por su cuenta (el de hosts,
# los vhosts, la configuracion de los proyectos al cargarlos, lo que cambia asegurar), en ~/nexum-backups
# antes de cambiarlos. Es el fichero COPIES_FILES_FLAG: si esta, se guardan; si no (lo de partida), no.
# Sin nada, dice como esta. No pide contraseña
function copies_files_command() {
    case "$1" in
        "")
            if [ -f "$COPIES_FILES_FLAG" ]; then
                echo "Copias de los ficheros que cambia el programa: si (en ~/nexum-backups, antes de cambiarlos)"
            else
                echo "Copias de los ficheros que cambia el programa: no (con nexum copias-ficheros si, se guardan)"
            fi
            ;;
        si)
            if [ "$DRY" -eq 1 ]; then
                echo "  [simulacion] se crearia $COPIES_FILES_FLAG"
                return 0
            fi
            mkdir -p -m 700 "$LOG_DIR" || return 1
            # (un enlace en su lugar no se sigue: se quita y se crea el fichero)
            [ -L "$COPIES_FILES_FLAG" ] && rm -f "$COPIES_FILES_FLAG"
            [ -f "$COPIES_FILES_FLAG" ] || ( umask 077; : > "$COPIES_FILES_FLAG" ) || return 1
            echo "Copias de los ficheros que cambia el programa: si (en ~/nexum-backups, antes de cambiarlos)"
            ;;
        no)
            if [ "$DRY" -eq 1 ]; then
                echo "  [simulacion] se quitaria $COPIES_FILES_FLAG"
                return 0
            fi
            rm -f "$COPIES_FILES_FLAG" || return 1
            echo "Copias de los ficheros que cambia el programa: no"
            ;;
        *) echo "Uso: nexum copias-ficheros [si|no]"; return 1 ;;
    esac
}
