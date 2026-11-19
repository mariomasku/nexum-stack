#!/bin/bash
# Pruebas del avance mientras se compila (1.57.30): step_watch ejecuta un paso de la compilacion y, mientras
# dura, escribe por donde va cada STEP_TICK segundos, para que el registro de la tarea no parezca congelado.
# Uso: paso-avance.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-avance.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
extract "$SRC" step_watch step_elapsed || exit 1

check "tiempo: segundos, minutos y horas" '[ "$(step_elapsed 45)" == "45 s" ] && [ "$(step_elapsed 120)" == "2 min" ] && [ "$(step_elapsed 150)" == "2 min 30 s" ] && [ "$(step_elapsed 3900)" == "1 h 5 min" ] && [ "$(step_elapsed 3600)" == "1 h" ]'

# Un paso que escribe 30 lineas en unos 3 segundos, de las 40 que suele tener: avance por lineas
out=$(STEP_TICK=1 step_watch 20 60 40 Compilando "$W/a.log" bash -c 'for i in $(seq 30); do echo l$i; sleep 0.1; done; sleep 1')
rc=$?
check "mientras dura, una linea con su porcentaje y el tiempo que lleva" '[ $rc -eq 0 ] && grep -qE "^  \[ *[0-9]+%\] Compilando\.\.\. sigue \(1 s\)$" <<< "$out" && [ "$(wc -l <<< "$out")" -ge 2 ]'
last=$(tail -1 <<< "$out" | grep -oE "[0-9]+%" | tr -d %)
check "el porcentaje sube con las lineas, entre el del paso y el siguiente" '[ "$last" -gt 20 ] && [ "$last" -le 60 ]'
check "la salida del paso va a su registro, no a la tarea" '[ "$(wc -l < "$W/a.log")" -eq 30 ] && ! grep -q "^l1$" <<< "$out"'
# cmake escribe su propio porcentaje: con 0 lineas se usa ese
out=$(STEP_TICK=1 step_watch 80 90 0 Compilando "$W/b.log" bash -c 'echo "[ 10%] Building x"; sleep 1.5; echo "[ 50%] Building y"; sleep 1.5')
check "con cmake (0 lineas), su ultimo [ NN%]" 'grep -q "^  \[ 85%\] Compilando\.\.\. sigue" <<< "$out"'
# Un paso corto no escribe nada mas; uno que falla devuelve su codigo
out=$(step_watch 10 20 5 Instalando "$W/c.log" bash -c 'echo hecho')
check "un paso corto: nada en la tarea" '[ -z "$out" ] && grep -qx hecho "$W/c.log"'
step_watch 10 20 5 Instalando "$W/d.log" bash -c 'echo mal; exit 3' > /dev/null
check "si el paso falla, su codigo" '[ $? -eq 3 ]'
# Cancelar (la ventana manda SIGTERM a todo el grupo de la tarea): no se queda nada en marcha
( setsid bash -c '
    '"$(declare -f step_watch step_elapsed)"'
    echo $$ > "'"$W"'/grupo"
    step_watch 1 2 10 Compilando "'"$W"'/e.log" bash -c "echo \$\$ > '"$W"'/hijo; sleep 60"
' > /dev/null 2>&1 & )
for i in $(seq 50); do [ -s "$W/hijo" ] && break; sleep 0.1; done
g=$(cat "$W/grupo" 2> /dev/null) h=$(cat "$W/hijo" 2> /dev/null)
[ -n "$g" ] && kill -TERM -- "-$g" 2> /dev/null
sleep 0.5
check "al cancelar la tarea, el paso tambien se para" '[ -n "$h" ] && ! kill -0 "$h" 2> /dev/null'
check "los dos step lo usan (Linux y Mac)" 'grep -q "if ! step_watch .* \"\$lines\" \"\$desc\" \"\$log\" /usr/bin/python3 -I -c \"\$NO_TTY_PY\" \"\$@\"; then" "$SRC"'
exit $fail
