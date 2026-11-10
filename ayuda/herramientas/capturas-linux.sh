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
echo "Abriendo la ventana en demostración (tarda un minuto: no la toques ni pases el ratón por encima)..."
env HOME="$W/home" LVM_DEMO="$W/demo" LVM_HTDOCS="$W/demo/htdocs" LVM_CAPTURA="$W/capturas" \
    timeout 300 dbus-run-session -- "$ROOT/lvm-instalador.sh" --simular ventana > "$W/ventana.log" 2>&1 || true
n=$(find "$W/capturas" -name '*.png' | wc -l)
if [ "$n" -eq 0 ]; then
    echo "No ha salido ninguna captura. Lo que dijo la ventana:"
    tail -20 "$W/ventana.log"
    exit 1
fi
# Sin la sombra de la ventana: se recorta por su borde (la línea oscura de cada lado) y las esquinas
# redondeadas quedan transparentes. Sin Pillow (python3-pil), tal cual
python3 -I - "$W/capturas" "$OUT" << 'PY'
import glob, os, shutil, sys
src, out = sys.argv[1:3]
try:
    from PIL import Image, ImageDraw
except ImportError:
    for f in glob.glob(os.path.join(src, "*.png")):
        shutil.copy(f, out)
    sys.exit(0)

def edge(values):
    # el borde: el primer salto brusco a oscuro desde fuera (antes, la sombra se oscurece poco a poco). No
    # el más oscuro: por ahí puede pasar la fila azul del menú lateral
    for i in range(1, 80):
        if values[i] < values[i - 1] - 100:
            return i
    return 0

for f in sorted(glob.glob(os.path.join(src, "*.png"))):
    im = Image.open(f).convert("RGB")
    w, h = im.size
    # (por la mitad de alto para los lados, y por el menú lateral para arriba y abajo: por el centro pasa
    # el recuadro de la versión activa, con su propio borde)
    row = [sum(im.getpixel((x, h // 2))) for x in range(w)]
    col = [sum(im.getpixel((edge(row) + 60, y))) for y in range(h)]
    left, right = edge(row), w - 1 - edge(row[::-1])
    top, bottom = edge(col), h - 1 - edge(col[::-1])
    im = im.crop((left, top, right + 1, bottom + 1)).convert("RGBA")
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.size[0] - 1, im.size[1] - 1), radius=12, fill=255)
    im.putalpha(mask)
    im.save(os.path.join(out, os.path.basename(f)), optimize=True)
PY
echo "$n capturas en $OUT"
