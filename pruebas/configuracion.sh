#!/bin/bash
# Configuración y avisos (Linux 1.57.2, Mac 1.41.1): apartados en una columna pegada al menú, en filas (Docker y el
# correo, en tarjetas), el interruptor del correo en su título, Guardar debajo de los campos de Docker, el aviso de
# parches nuevos con «Ahora no» y, en el Mac, la terminal con \r. Uso: configuracion.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/configuracion.XXXXXX") || exit 1
trap 'rm -rf "${W:?}"' EXIT
if grep -q "^let ERROR_LOG = " "$SRC"; then
    check "Mac: la columna de apartados, fuera de la página" 'sed -n "/^struct ToolsView: View {/,/^    func section/p" "$SRC" | grep -qF ".frame(width: 220)" && sed -n "/^struct ToolsView: View {/,/^    func section/p" "$SRC" | grep -qF "Text(\"CONFIGURACIÓN\")"'
    check "Mac: en filas salvo con tiles" 'grep -qF "if !tiles {" "$SRC" && grep -qF ".environment(\\.tileRow, !tiles)" "$SRC"'
    check "Mac: Docker y el correo, en tarjetas" 'grep "TileCard(\"Docker\"" "$SRC" | grep -qF "tiles: true" && grep -qF "TileCard(tiles: true) {" "$SRC" && grep -A1 "TileCard(\"Correo de pruebas (Mailpit)\"" "$SRC" | grep -qF "tiles: true"'
    check "Mac: el interruptor del correo, en su título (sin su tarjeta)" '! grep -qF "Tile(\"Correo de pruebas\", m.on ?" "$SRC" && grep -qF "lead: AnyView(LogoShape(d: LOGO_PATHS[\"mailpit\"]" "$SRC"'
    check "Mac: Guardar debajo de los campos" 'grep -B1 "HStack(spacing: 8) {" "$SRC" | grep -qF "VStack(alignment: .trailing, spacing: 10) {" && ! grep -q "underCaption" "$SRC"'
    check "Mac: aviso de parches con Ahora no" 'grep -qF "Button(\"Ahora no\") { model.ignoreUpdates(c) }" "$SRC" && grep -qF "(model.updatesPending != nil ? 1 : 0)" "$SRC"'
    check "Mac: al abrir ya no pregunta" '! sed -n "/^    func autoCheckComponents/,/^    }/p" "$SRC" | grep -q "updateComponents"'
    check "Mac: la terminal, pegada (sin márgenes ni redondeos)" '! sed -n "/^struct TermPanel: View {/,/^}/p" "$SRC" | grep -q "RoundedRectangle"'
    # El \r de la terminal, de verdad (el algoritmo de feed, en Python)
    python3 -I - << 'PY' > "$W/cr"
seq = "%" + " " * 159 + "\r \r" + "yo@mac web % " + "ls" + "\b \b" + "s\n" + "10%\r100%\n" + "%" + " " * 159 + "\r \r" + "yo@mac web % "
line, col, done = [], 0, ""
tr = lambda l: "".join(l).rstrip(" ")
for ch in seq:
    if ch == "\n": done += tr(line) + "\n"; line, col = [], 0
    elif ch == "\r": col = 0
    elif ch == "\b": col = max(0, col - 1)
    else:
        if col < len(line): line[col] = ch
        else: line += [" "] * (col - len(line)); line.append(ch)
        col += 1
print(int(done + tr(line) == "yo@mac web % ls\n100%\nyo@mac web %"))
PY
    check "Mac: \\r vuelve al principio de la línea (el algoritmo)" '[ "$(cat "$W/cr")" = 1 ]'
    check "Mac: y es el del programa" 'grep -qF "} else if ch == \"\\r\" {" "$SRC" && grep -F -A1 "} else if ch == \"\\r\" {" "$SRC" | grep -qF "col = 0" && grep -qF "let tail = trimmed(line)" "$SRC"'
else
    check "Linux: la columna de apartados, fuera de la página" 'grep -qF "(\"config\", self.tools_wrap)" "$SRC" && grep -qF "self.tools_side.pack_start(nav, False, False, 0)" "$SRC"'
    check "Linux: en filas salvo con tiles" 'grep -q "^def tile_group(title=None, description=None, columns=2, tiles=False, lead=None, tail=None):" "$SRC"'
    check "Linux: Docker y el correo, en tarjetas" 'grep -qF "van sin puerto.\", tiles=True)" "$SRC" && grep -qF "tile_group(\"Correo de pruebas (Mailpit)\", tiles=True, lead=logo(\"mailpit\", 20), tail=tail," "$SRC"'
    check "Linux: sin la tarjeta de encender el correo" '! grep -qF "row = ActionRow(\"Correo de pruebas\", \"Encendido:" "$SRC"'
    check "Linux: Guardar debajo de los campos" 'grep -qF "buttons.pack_start(b, False, False, 0)" "$SRC" && grep -qF "form.pack_start(buttons, False, False, 0)" "$SRC"'
    check "Linux: al abrir ya no pregunta" '! sed -n "/^    def nv_components_auto/,/^    def nv_warn_refresh/p" "$SRC" | grep -q "nv_components_update"'
    python3 -I - "$SRC" "$W" > "$W/ign" << 'PY'
import os, sys
t, w = open(sys.argv[1], encoding="utf-8").read(), sys.argv[2]
a = t.index("# Parches nuevos dejados para luego"); b = t.index("# Menú lateral: sus apartados", a)
g = {"os": os, "LOG_DIR": w, "SIMULATE": False}
exec(t[a:b], g)
items = ["lampp-8.2: Apache 2.4.62 → 2.4.65", "mailpit: 1.32.0 → 1.33.1"]
print("%d|sin dejar nada para luego, se avisa" % (not g["updates_ignored"](items)))
g["updates_ignore"](items)
print("%d|«Ahora no»: esos ya no se avisan (en otro orden, tampoco)" % g["updates_ignored"](list(reversed(items))))
print("%d|con un parche más, vuelve el aviso" % (not g["updates_ignored"](items + ["cloudflared: 1 → 2"])))
PY
    while IFS='|' read -r good name; do check "$name" '[ "$good" = 1 ]'; done < "$W/ign"
fi
exit $fail
