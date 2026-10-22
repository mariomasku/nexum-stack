#!/bin/bash
# Todo el Python incrustado en variables '...' del script compila (y no lleva comillas simples).
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
for v in $(grep -oE "^[A-Z_]+_PY='" "$SRC" | tr -d "='"); do
    code=$( ( eval "$(sed -n "/^$v='/,/^'\$/p" "$SRC")"; printf '%s' "${!v}" ) )
    check "$v compila" 'python3 -I -c "import sys; compile(sys.stdin.read(), \"$v\", \"exec\")" <<< "$code"'
done
gui=$(awk "/cat <<'LVM_GUI_PY'/{f=1;next} /^LVM_GUI_PY\$/{f=0} f" "$SRC")
[ -n "$gui" ] && check "ventana GTK compila" 'python3 -I -c "import sys; compile(sys.stdin.read(), \"gui\", \"exec\")" <<< "$gui"'
exit $fail
