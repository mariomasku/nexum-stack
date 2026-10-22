#!/bin/bash
# Que cambiaria SECURE_PY en las versiones instaladas (solo lee; escribe en una carpeta temporal)
SRC=${1:-${LVM_SCRIPT:-$(cd "$(dirname "$0")/.." && pwd)/lvm-instalador.sh}} HERE=$(cd "$(dirname "$0")" && pwd)
TMPBASE=${LVM_TMP:-${TMPDIR:-/tmp}}
getvar() { ( eval "$(sed -n "/^$1='/,/^'\$/p" "$SRC")"; printf '%s.' "${!1}" ); }  # (el punto guarda los saltos de linea del final)
SP=$(getvar SECURE_PY); VH=$(getvar UNKNOWN_HOST_VHOST); SSL=$(getvar UNKNOWN_HOST_SSL); SP=${SP%.} VH=${VH%.} SSL=${SSL%.}
CONF=$(grep -m1 '^UNKNOWN_HOST_CONF=' "$SRC" | cut -d= -f2)
for d in /opt/lampp-*; do
    [ -L "$d" ] && continue
    o=$(mktemp -d "$TMPBASE/w-real.XXXX")
    r=$(python3 -I -c "$SP" "$d" "$o" 1 "$CONF" "$VH" "$SSL" 2>&1 | cut -d'|' -f1,3)
    echo "$d: ${r:-sin cambios}"
    rm -rf "$o"
done
