#!/bin/bash
# Prueba de NO_TTY_PY: dentro de una pseudoterminal, la orden no la tiene y se propaga su codigo
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
NT=$( ( eval "$(sed -n "/^NO_TTY_PY='/,/^'\$/p" "$SRC")"; printf '%s' "$NO_TTY_PY" ) )
export NT
out=$(script -qec '/usr/bin/python3 -I -c "$NT" sh -c "echo T=\$(ps -o tty= -p \$\$); exit 3" < /dev/null; echo "rc=$?"; tty' /dev/null 2>&1 | tr -d '\r')
check "la orden no tiene terminal" 'grep -q "^T=?$" <<< "$out"'
check "la tarea si la tiene" 'grep -q "^/dev/pts/" <<< "$out"'
check "se propaga el codigo de salida" 'grep -q "^rc=3$" <<< "$out"'
check "env VAR=... orden funciona" '[ "$(/usr/bin/python3 -I -c "$NT" env X=1 sh -c "echo \$X")" = 1 ]'
check "orden que no existe: falla" '! /usr/bin/python3 -I -c "$NT" no-existe-xyz 2> /dev/null'
# Cancelar (señal al grupo de la tarea) para tambien lo que se compila
setsid bash -c '/usr/bin/python3 -I -c "$NT" sleep 97 & wait' &
G=$!; sleep 1
kill -TERM -- -"$G" 2> /dev/null; sleep 1
check "cancelar para tambien la orden" '! pgrep -f "^sleep 97$" > /dev/null'
pkill -f "^sleep 97$" 2> /dev/null
exit $fail
