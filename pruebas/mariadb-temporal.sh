#!/bin/bash
# MariaDB temporal de una version parada (Linux y Mac 1.57.8): mientras arranca, se mira si sigue vivo
# sin kill -0. Su pid es el del sudo que lo lanza, que es de root, y kill -0 a un proceso de root da
# «no permitido» aunque siga vivo: la copia se daba por fallida nada mas arrancar.
# Uso: mariadb-temporal.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q 'server_pid=\$!' "$SRC" || { echo "  ok    (sin MariaDB temporal)"; exit 0; }

check "ningun kill -0 al pid del servidor (el del sudo, de root)" '! grep -qE "kill -0 \"?\\\$server_pid" "$SRC"'
# Las comprobaciones de verdad, tal como estan en el script (una por cada arranque)
mapfile -t ALIVE < <(grep -E '^ +(\[ -d "/proc/\$server_pid" \]|/bin/ps -p "\$server_pid" > /dev/null 2>&1) \|\| break$' "$SRC" | sed -E 's/ \|\| break$//')
# (una por cada espera que, si no arranca, dice «No ha arrancado» y enseña su registro)
check "cada espera del servidor lo mira con /proc (Linux) o ps -p (Mac)" '[ ${#ALIVE[@]} -ge 1 ] && [ ${#ALIVE[@]} -eq $(grep -c "echo \"No ha arrancado. Ultimas lineas de su registro:\"" "$SRC") ]'
# (el 1, init o launchd, es de root: como el sudo)
ROOT_PID=1
[ "$(ps -o uid= -p 1 2> /dev/null | tr -d " ")" = 0 ] || ROOT_PID=""
sleep 30 & DEAD=$!; kill $DEAD; wait $DEAD 2> /dev/null
for a in "${ALIVE[@]}"; do
    case "$a" in */bin/ps*) command -v /bin/ps > /dev/null || continue ;; *) [ -d /proc ] || continue ;; esac
    [ -n "$ROOT_PID" ] && [ "$(id -u)" != 0 ] && \
        check "un proceso de root en marcha cuenta como vivo: ${a# *}" 'server_pid=$ROOT_PID; eval "$a"'
    check "un proceso que ya ha terminado, no: ${a# *}" 'server_pid=$DEAD; ! eval "$a"'
done
exit $fail
