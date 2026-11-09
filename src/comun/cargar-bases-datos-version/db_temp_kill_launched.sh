# Para lo que se lanzo en segundo plano con $SUDO (su $!): sus hijos y el. Con sudo es el sudo (que
# pasa la señal al servidor); si sudo es una funcion (Mac), una subshell cuyo hijo es el sudo
# Solo si lleva el socket de esa carpeta (al azar) en su orden: si ya habia terminado, su PID podria
# ser de otro proceso. db_temp_kill_launched <pid lanzado> <socket>
function db_temp_kill_launched() {
    local p
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 1 ] && [ -n "$2" ] || return 0
    for p in "$1" $($SUDO pgrep -P "$1" 2> /dev/null); do
        [[ "$($SUDO ps -ww -o args= -p "$p" 2> /dev/null)" == *"--socket=$2"* ]] && $SUDO kill "$p" 2> /dev/null
    done
    return 0
}

# PID de un MariaDB temporal: el de su .pid, solo si es de verdad ese servidor (su orden lleva el
# socket de esa carpeta, que es al azar). Si el MariaDB corre con tu usuario, otro programa tuyo
# podria poner en el .pid el de otro proceso para que root lo parase. db_temp_pid <.pid> <socket>
function db_temp_pid() {
    local pid
    $SUDO test -f "$1" && ! $SUDO test -L "$1" || return 1
    pid=$($SUDO head -c 20 "$1" 2> /dev/null | tr -d ' \n')
    [[ "$pid" =~ ^[0-9]+$ ]] && [ "$pid" -gt 1 ] || return 1
    # (con sudo: macOS no enseña la orden de los procesos de otros usuarios)
    [[ "$($SUDO ps -ww -o args= -p "$pid" 2> /dev/null)" == *"--socket=$2"* ]] || return 1
    echo "$pid"
}

# Al salir (tambien si se cancela): sin copia a medias y sin MariaDB temporal en marcha
DB_PART="" DB_COPY_TMP=""
function db_cleanup() {
    [ -n "$DB_PART" ] && rm -f "$DB_PART"
    # (copiar-bd: su copia temporal y el envoltorio del cliente, tambien si se cancela)
    [ -n "$DB_COPY_TMP" ] && rm -f "$DB_COPY_TMP"
    db_client_wrapper_remove
    db_temp_stop
}

# Envoltorio del cliente de MariaDB para un MariaDB temporal: en una carpeta de root que nadie mas
# puede cambiar. Se ejecuta muchas veces en la terminal de la tarea, que ya tiene el permiso de sudo:
# si fuera un fichero tuyo, otro programa tuyo podria cambiarlo por «sudo -n ...» y ser root.
# db_client_wrapper <cliente> <carpeta de librerias o ""> <socket>: deja la ruta en DB_CLI
DB_CLI_DIR="" DB_CLI=""
function db_client_wrapper() {
    local client=$1 libs=$2 sock=$3 body
    if [ -n "$libs" ]; then
        body=$(printf '#!/bin/bash\nexec /usr/bin/env LD_LIBRARY_PATH=%q %q --no-defaults -S %q "$@"\n' "$libs" "$client" "$sock")
    else
        body=$(printf '#!/bin/bash\nexec %q --no-defaults -S %q "$@"\n' "$client" "$sock")
    fi
    DB_CLI_DIR=$($SUDO mktemp -d /tmp/lvm-cliente-XXXXXX) || { DB_CLI_DIR=""; return 1; }
    DB_CLI=$DB_CLI_DIR/mysql
    if ! printf '%s\n' "$body" | $SUDO sh -c 'umask 022; cat > "$1"' sh "$DB_CLI" \
        || ! $SUDO chmod 755 "$DB_CLI_DIR" "$DB_CLI"; then
        db_client_wrapper_remove
        return 1
    fi
}

function db_client_wrapper_remove() {
    [ -n "$DB_CLI_DIR" ] && [[ "$DB_CLI_DIR" == /tmp/lvm-cliente-* ]] && $SUDO rm -rf "$DB_CLI_DIR"
    DB_CLI_DIR="" DB_CLI=""
}

