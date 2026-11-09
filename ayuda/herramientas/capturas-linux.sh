#!/bin/bash
# Capturas de la ventana de Linux para el manual, con datos inventados (demo-linux.py): la abre en
# simulación (no cambia nada), con una carpeta personal temporal (ni tus ajustes de la ventana ni tus
# proyectos), pasa por cada página y cada apartado de Configuración y guarda una captura de cada uno.
#
# Uso: ayuda/herramientas/capturas-linux.sh [carpeta de salida, por defecto ayuda/img/linux]
#      (con el script construido de la raíz: ./construir.sh antes si has cambiado src/)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT=$(mkdir -p "${1:-$ROOT/ayuda/img/linux}" && cd "${1:-$ROOT/ayuda/img/linux}" && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/nexum-capturas.XXXXXX")
trap 'rm -rf "${W:?}"' EXIT

python3 -I "$HERE/demo-linux.py" "$W/demo" > /dev/null
mkdir -p "$W/home" "$W/capturas"
echo "Abriendo la ventana en demostración (tarda un minuto; no la toques)..."
env HOME="$W/home" LVM_DEMO="$W/demo" LVM_HTDOCS="$W/demo/htdocs" LVM_CAPTURA="$W/capturas" \
    timeout 300 dbus-run-session -- "$ROOT/lvm-instalador.sh" --simular ventana > "$W/ventana.log" 2>&1 || true
n=$(find "$W/capturas" -name '*.png' | wc -l)
if [ "$n" -eq 0 ]; then
    echo "No ha salido ninguna captura. Lo que dijo la ventana:"
    tail -20 "$W/ventana.log"
    exit 1
fi
cp "$W/capturas/"*.png "$OUT/"
echo "$n capturas en $OUT"
