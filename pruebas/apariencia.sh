#!/bin/bash
# Apariencia (Linux 1.57.1, Mac 1.41.0): iconos del menu lateral en color, Docker, Node y PHP con su logotipo
# (desde la 1.57.11, Docker y Node con su icono y al lado su logotipo de letras),
# que apartados salen (Proyectos y Configuracion, siempre) y el icono de discos de Bases de datos.
# Uso: apariencia.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/apariencia.XXXXXX") || exit 1
trap 'rm -rf "${W:?}"' EXIT
# Los trazos de los iconos nuevos: solo M, L, C y Z (lo unico que entiende el Mac) y en su caja de 24
python3 -I - "$SRC" > "$W/trazos" << 'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
for k in ("bbdd", "node"):
    m = re.search(r'^\s+"%s": "([^"]+)",$' % k, t, re.M)
    d = m.group(1) if m else ""
    nums = [float(x) for x in re.findall(r"-?\d+(?:\.\d+)?", d)]
    ok = bool(d) and set(re.findall(r"[A-Za-z]", d)) <= set("MLCZ") and all(0 <= n <= 24 for n in nums)
    print("%d|%s" % (ok, k))
PY
while IFS='|' read -r good k; do check "icono $k: solo M, L, C y Z, dentro de 24x24" '[ "$good" = 1 ]'; done < "$W/trazos"
if grep -q "^let ERROR_LOG = " "$SRC"; then
    python3 -I - "$SRC" > "$W/pdf" << 'PY'
import base64, re, sys
t = open(sys.argv[1], encoding="utf-8").read()
block = t[t.index("let BRAND_PDF: [String: String] = ["):]
block = block[:block.index("\n]\n")]
got = dict(re.findall(r'^    "([a-z-]+)": "([A-Za-z0-9+/=]+)",?$', block, re.M))
for k in ("docker", "docker-letras", "node-claro", "node-oscuro", "php"):
    print("%d|%s" % (k in got and base64.b64decode(got[k])[:5] == b"%PDF-", k))
# (los de Node, sin máscara: con ella macOS no los dibujaba)
print("%d|node sin máscara" % all(k in got and b"Mask" not in base64.b64decode(got[k]) for k in ("node-claro", "node-oscuro")))
PY
    while IFS='|' read -r good k; do check "Mac: logotipo $k en PDF" '[ "$good" = 1 ]'; done < "$W/pdf"
    check "Mac: Docker y Node, su icono y al lado su logotipo de letras (1.57.11)" 'sed -n "/^struct NavRow: View {/,/^}/p" "$SRC" | grep -A3 -F "if look.marcas && (key == \"docker\" || key == \"node\") {" | grep -qF "navIcon(on, color: look.color)" && grep -qF "BrandImage(key: key == \"docker\" ? \"docker-letras\" : key" "$SRC"'
    check "Mac: Bases de datos y Node con su icono" 'grep -qF "(\"bbdd\", \"Bases de datos\", \"logo:bbdd\")" "$SRC" && grep -qF "(\"node\", \"Node\", \"logo:node\")" "$SRC"'
    check "Mac: se guarda al cambiar y, si se oculta el apartado abierto, a Proyectos" 'grep -A5 "@Published var look = loadLook() {" "$SRC" | grep -qF "saveLook(look)" && grep -A5 "@Published var look = loadLook() {" "$SRC" | grep -qF "if look.ocultos.contains(tab) { openTab(\"proyectos\") }"'
    check "Mac: en la simulacion no se guarda" 'sed -n "/^func saveLook/,/^}/p" "$SRC" | grep -qF "if SIMULATE { return }"'
    check "Mac: Proyectos y Configuracion, siempre" 'grep -qF "let NAV_FIXED: Set<String> = [\"proyectos\", \"config\"]" "$SRC" && grep -qF "group.1.filter { NAV_FIXED.contains(\$0.0) || !model.look.ocultos.contains(\$0.0) }" "$SRC"'
    check "Mac: Docker y Node con su logotipo, PHP en color" 'grep -qF "if look.marcas && (key == \"docker\" || key == \"node\") {" "$SRC" && grep -qF "if look.marcas && look.color && key == \"versiones\" {" "$SRC"'
    check "Mac: apartado Apariencia" 'grep -qF "(\"apariencia\", \"Apariencia\", \"paintpalette\")" "$SRC" && grep -qF "case \"apariencia\":" "$SRC" && grep -q "^struct AppearanceCard: View {" "$SRC"'
    check "Mac: las imagenes se leen una vez" 'grep -A2 "^func brandImage" "$SRC" | grep -qF "if let i = brandImages[key] { return i }"'
else
    # look_conf y look_save de verdad, en una carpeta de prueba
    python3 -I - "$SRC" "$W" > "$W/look" << 'PY'
import base64, json, os, re, sys, zlib
import xml.etree.ElementTree as ET
t, w = open(sys.argv[1], encoding="utf-8").read(), sys.argv[2]
start = t.index("# Menú lateral: sus apartados")
code = t[start:t.index("\nclass MonoLogo(Gtk.DrawingArea):", start)]
g = {"os": os, "json": json, "LOG_DIR": w, "SIMULATE": False}
exec(code, g)
c = g["look_conf"]()
print("%d|sin fichero: de un color, sin logotipos y todo a la vista" % (c == {"color": False, "marcas": False, "ocultos": set()}))
open(g["LOOK_FILE"], "w").write("no es json")
print("%d|un fichero roto no rompe nada" % (g["look_conf"]()["ocultos"] == set()))
json.dump({"color": True, "marcas": "si", "ocultos": ["node", "proyectos", "config", "inventado", 3]}, open(g["LOOK_FILE"], "w"))
c = g["look_conf"]()
print("%d|solo lo que vale: Proyectos, Configuracion y lo desconocido no se ocultan" % (c == {"color": True, "marcas": False, "ocultos": {"node"}}))
c["marcas"] = True; c["ocultos"] = {"docker", "repos"}
g["look_save"](c)
print("%d|se guarda y se vuelve a leer igual" % (g["look_conf"]() == c and not os.path.exists(g["LOOK_FILE"] + ".nuevo")))
g["SIMULATE"] = True
before = open(g["LOOK_FILE"]).read()
g["look_save"]({"color": False, "marcas": False, "ocultos": set()})
print("%d|en la simulacion no se escribe, pero vale mientras dure" % (open(g["LOOK_FILE"]).read() == before and g["look_conf"]()["color"] is False))
bs = t[t.index("BRAND_SVG = {"):]
bs = bs[:bs.index("\n}\n")]
got = dict(re.findall(r'^    "([a-z-]+)": "([A-Za-z0-9+/=]+)",?$', bs, re.M))
for k in ("docker", "node-claro", "node-oscuro", "php"):
    try:
        ok = ET.fromstring(zlib.decompress(base64.b64decode(got[k]))).tag.endswith("svg")
    except Exception:
        ok = False
    print("%d|logotipo %s en SVG" % (ok, k))
PY
    while IFS='|' read -r good name; do check "$name" '[ "$good" = 1 ]'; done < "$W/look"
    check "Linux: el menu se rehace solo (no la ventana entera)" 'sed -n "/^    def nv_look_set/,/^    def nv_look_tools/p" "$SRC" | grep -qF "self.nv_sidebar_fill()"'
    check "Linux: apartado Apariencia" 'grep -qF "(\"Apariencia\", \"Apariencia\", \"preferences-desktop-appearance-symbolic\")" "$SRC" && grep -qF "self.nv_look_tools()" "$SRC"'
    check "Linux: los logotipos se dibujan una vez por tamaño" 'grep -A3 "^def brand_pixbuf" "$SRC" | grep -qF "if k not in _brand_cache:"'
    check "Linux: Docker y Node, su icono y al lado su logotipo de letras (1.57.11)" 'grep -A3 -F "if look[\"marcas\"] and name in (\"docker\", \"node\"):" "$SRC" | grep -qF "inner.pack_start(MonoLogo(ic[5:], 20, colored=look[\"color\"]), False, False, 0)" && grep -qF "BrandLogo(\"docker-letras\" if name == \"docker\" else \"node\"" "$SRC"'
    DL=$(python3 -I - "$SRC" << 'PY'
import base64, re, sys, zlib
t = open(sys.argv[1], encoding="utf-8").read()
bs = t[t.index("BRAND_SVG = {"):]
got = dict(re.findall(r'^    "([a-z-]+)": "([A-Za-z0-9+/=]+)",?$', bs[:bs.index("\n}\n")], re.M))
g = {"base64": base64, "zlib": zlib, "BRAND_SVG": got, "BRAND_RATIO": {}}
start = t.index("# El logotipo de letras de Docker, sin la ballena")
exec(t[start:t.index("\nclass NvTerminal:", start)], g)
svg = zlib.decompress(base64.b64decode(got["docker-letras"]))
print(int(b'viewBox="385 30 865 210"' in svg and abs(g["BRAND_RATIO"]["docker-letras"] - 865 / 210) < 1e-9))
PY
)
    check "Linux: el logotipo de letras de Docker, el mismo SVG solo sobre las letras" '[ "$DL" = 1 ]'
    check "Linux: en la fila elegida se leen (se repinta al cambiar)" 'grep -qF "self.side_box.queue_draw()" "$SRC" && grep -q "^def row_selected(widget):" "$SRC"'
fi
exit $fail
