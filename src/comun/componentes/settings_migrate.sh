# Hasta la 1.57.13 la carpeta de los ajustes y los registros era ~/.lvm-instalador: al arrancar, la
# primera vez, se renombra a ~/.nexum (LOG_DIR; en la misma carpeta personal, un rename: no se copia
# nada) y en su sitio se deja ~/.lvm-instalador como enlace relativo a .nexum, para que lo que aun
# apunte a la ruta de antes (el docker.service de tu usuario, los contenedores de Docker con sus
# rutas, el temporizador, una ventana ya abierta, Mailpit o un tunel en marcha) siga funcionando.
# Solo si es una carpeta tuya (no un enlace) y no hay ninguna ~/.nexum (ni un enlace roto): si estan
# las dos, no se toca ninguna y se avisa una vez, en SETTINGS_BOTH_LOG. Si ya es un enlace, nada.
# Antes del mv se deja dentro una marca (SETTINGS_MOVE_MARK): si se corta entre el mv y el enlace, la
# siguiente vez se crea el enlace. (La ventana del Mac hace lo mismo al abrirse: settingsMigrate)
SETTINGS_OLD_DIR=$HOME/.lvm-instalador
SETTINGS_MOVE_MARK=.pasando-a-nexum
SETTINGS_BOTH_LOG=carpeta-anterior.log
function settings_migrate() {
    local old=$SETTINGS_OLD_DIR new=$LOG_DIR mark
    mark=$new/$SETTINGS_MOVE_MARK
    # (el enlace es relativo: las dos en la misma carpeta)
    [ "$old" != "$new" ] && [ "${old%/*}" == "${new%/*}" ] || return 0
    if [ -L "$old" ]; then
        # (cortada entre el enlace y quitar la marca)
        [ -f "$mark" ] && [ ! -L "$mark" ] && [ -d "$new" ] && [ ! -L "$new" ] && [ -O "$new" ] && rm -f "$mark"
        return 0
    fi
    if [ ! -e "$old" ]; then
        # (cortada entre el mv y el enlace: ~/.nexum lleva la marca)
        if [ -f "$mark" ] && [ ! -L "$mark" ] && [ -d "$new" ] && [ ! -L "$new" ] && [ -O "$new" ]; then
            ln -s "${new##*/}" "$old" 2> /dev/null && rm -f "$mark"
        fi
        return 0
    fi
    [ -d "$old" ] && [ -O "$old" ] || return 0
    if [ -e "$new" ] || [ -L "$new" ]; then
        if [ -d "$new" ] && [ ! -L "$new" ] && [ -O "$new" ] && [ ! -e "$new/$SETTINGS_BOTH_LOG" ] \
                && [ ! -L "$new/$SETTINGS_BOTH_LOG" ]; then
            ( umask 077; printf '%s Estan %s y %s: no se toca ninguna. Los ajustes que se usan son los de %s; mira que hay en %s y, si ya no hace falta, borrala.\n' \
                "$(date '+%Y-%m-%d %H:%M:%S')" "$old" "$new" "$new" "$old" > "$new/$SETTINGS_BOTH_LOG" ) 2> /dev/null
        fi
        return 0
    fi
    ( umask 077; : > "$old/$SETTINGS_MOVE_MARK" ) 2> /dev/null || return 0
    # (justo antes, otra vez: que no haya aparecido una ~/.nexum, donde el mv la meteria dentro)
    if [ -e "$new" ] || [ -L "$new" ] || ! mv "$old" "$new" 2> /dev/null; then
        rm -f "$old/$SETTINGS_MOVE_MARK"
        return 0
    fi
    ln -s "${new##*/}" "$old" 2> /dev/null && rm -f "$mark"
    return 0
}

# La carpeta de los ajustes de esta vez: ~/.nexum o, si no se ha pasado (con --simular, en las pruebas,
# al pedir solo la version... o si no se ha podido), la de antes, para no crear una ~/.nexum al lado
function settings_dir() {
    if [ ! -e "$LOG_DIR" ] && [ ! -L "$LOG_DIR" ] && [ -d "$SETTINGS_OLD_DIR" ] && [ ! -L "$SETTINGS_OLD_DIR" ]; then
        echo "$SETTINGS_OLD_DIR"
    else
        echo "$LOG_DIR"
    fi
}
