#!/bin/bash
# Dependencias con apt (Linux 1.56.15): un repositorio roto de otro programa (un PPA sin version para esa
# Ubuntu, la clave caducada de Warp) hacia fallar apt-get update y no se instalaba ninguna version de PHP.
# Ahora solo se instala lo que falta (si esta todo, ni se llama a apt), se avisa de los repositorios rotos
# y se sigue. Con sudo, apt-get y dpkg-query falsos. Uso: apt.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q '^function apt_install() {' "$SRC" || { echo "  ok    (sin apt_install)"; exit 0; }
W=$(mktemp -d "$TMPBASE/w-apt.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
extract "$SRC" apt_install || exit 1
mkdir -p "$W/bin"
cat > "$W/bin/sudo" << 'EOF'
#!/bin/bash
[ "$1" == env ] && { shift; while [[ "$1" == *=* ]]; do export "$1"; shift; done; }
exec "$@"
EOF
cat > "$W/bin/apt-get" << 'EOF'
#!/bin/bash
echo "$*" >> "$APT_LOG"
if [[ " $* " == *" update "* ]]; then
    echo "E: El repositorio «https://ppa.launchpadcontent.net/zeal-developers/ppa/ubuntu jammy Release» no tiene un fichero de Publicación." >&2
    echo "W: Error de GPG: https://releases.warp.dev/linux/deb stable Release: EXPKEYSIG 31F4254AFE49E02E" >&2
    exit 100
fi
[ -n "$APT_FALLA" ] && { echo "E: No se ha podido localizar el paquete $APT_FALLA" >&2; exit 100; }
exit 0
EOF
cat > "$W/bin/dpkg-query" << 'EOF'
#!/bin/bash
[[ " $INSTALADOS " == *" ${@: -1} "* ]] && echo "install ok installed" || exit 1
EOF
chmod +x "$W/bin/"*
PATH=$W/bin:$PATH APT_LOG=$W/log
export APT_LOG

: > "$W/log"
out=$(INSTALADOS="a b" apt_install a b 2>&1); rc=$?
check "todas instaladas: no se llama a apt" '[ $rc -eq 0 ] && [ ! -s "$W/log" ]'

: > "$W/log"
out=$(INSTALADOS="a" apt_install a b 2>&1); rc=$?
check "apt-get update roto por otro repositorio: avisa de cual y sigue" '[ $rc -eq 0 ] && grep -q "zeal-developers" <<< "$out" && grep -q "Se sigue con las listas" <<< "$out"'
check "solo se instala lo que falta" 'grep -qx "install -y -qq b" "$W/log"'

: > "$W/log"
out=$(INSTALADOS="a" APT_FALLA=b apt_install a b 2>&1); rc=$?
check "si un paquete no se puede instalar, falla y dice que repositorios arreglar" '[ $rc -ne 0 ] && grep -q "No se han podido instalar: b" <<< "$out" && grep -q "sources.list.d" <<< "$out"'

check "la instalacion de una version usa apt_install (no apt-get update && install)" 'grep -q "^        apt_install \$deps || exit 1$" "$SRC" && ! grep -q "sudo apt-get update -qq && sudo apt-get install" "$SRC"'
exit $fail
