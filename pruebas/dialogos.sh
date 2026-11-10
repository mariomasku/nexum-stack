#!/bin/bash
# Diálogos que piden confirmar varios cambios (Linux 1.57.4, Mac 1.41.3): «Qué se va a realizar» y los
# cambios numerados, a la izquierda; el texto de siempre, debajo como nota.
# Uso: dialogos.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
if grep -q "^let ERROR_LOG = " "$SRC"; then
    check "Mac: confirm y runDialog aceptan los pasos" 'grep -qF "             steps: [String] = [], warning: String? = nil) -> Bool {" "$SRC" && grep -qF "destructive: destructive, steps: steps, warning: warning).ok" "$SRC"'
    check "Mac: «Qué se va a realizar», numerado y a la izquierda" 'grep -qF "\"Qué se va a realizar\\n\"" "$SRC" && grep -qF "NSAttributedString(string: \"\\(i + 1).\"" "$SRC" && grep -qF "l.alignment = .left" "$SRC"'
    check "Mac: con pasos, la nota a la izquierda" 'grep -qF "steps.isEmpty ? dialogLabel(text) : dialogLabel(text, color: .secondaryLabelColor, align: .left)" "$SRC"'
    check "Mac: crear dominio, copiar, replicar, cargar, actualizar, instalar y Actualizar todo, con pasos" '[ "$(grep -cE "steps: (steps|notes|what|c\.items|list\.map|notes \+ )" "$SRC")" -ge 7 ]'
    check "Mac: git pull antes de copiar, con los pasos" 'grep -qF "let steps = dialogSteps(what)" "$SRC"'
    check "Mac: ya no hay listas con viñetas en los diálogos" '! grep -qE "confirm\(.*map \{ \"• \" \+" "$SRC"'
else
    check "Linux: confirm acepta los pasos" 'grep -qF "def confirm(parent, title, text, ok_label, destructive=False, extra=None, steps=None):" "$SRC"'
    check "Linux: «Qué se va a realizar», numerado y a la izquierda" 'grep -qF "head.set_markup(\"<b>Qué se va a realizar</b>\")" "$SRC" && grep -qF "% (GREEN, i))" "$SRC"'
    check "Linux: el centrado de los diálogos no toca los pasos" 'grep -qF "or getattr(w, \"nv_pasos\", False):" "$SRC"'
    check "Linux: crear dominio, copiar, replicar, cargar, actualizar, instalar y Actualizar todo, con pasos" '[ "$(grep -cE "steps=(steps|notes|what|res\[\"items\"\]|\[\"Se instala|notes \+)" "$SRC")" -ge 7 ]'
    check "Linux: git pull antes de copiar, con los pasos" 'grep -qF "pack_start(steps_box(what," "$SRC"'
    check "Linux: ya no hay listas con viñetas en los diálogos" '! grep -qE "confirm\(.*\"• \" \+ x" "$SRC"'
    # Que se pinte: un diálogo con pasos, sin pantalla de verdad no; con ella, se abre y se cierra solo
    if [ -n "$DISPLAY$WAYLAND_DISPLAY" ] && python3 -c "import gi" 2> /dev/null; then
        W=$(mktemp -d "$TMPBASE/dialogos.XXXXXX") || exit 1
        trap 'rm -rf "${W:?}"' EXIT
        awk '/cat <<.LVM_GUI_PY.$/{f=1;next} /^LVM_GUI_PY$/{f=0} f' "$SRC" > "$W/gui.py"
        python3 -I - "$W/gui.py" > "$W/out" 2>&1 << 'PY'
import re, sys
g = open(sys.argv[1], encoding="utf-8").read()
def fn(name):
    return re.search(r"^def %s\(.*?(?=^\S)" % name, g, re.S | re.M).group(0)
code = 'import gi\ngi.require_version("Gtk", "3.0")\nfrom gi.repository import Gtk, GLib\nGREEN = "#45A57C"\n'
code += "".join(fn(n) for n in ("css", "center_texts", "airy_dialog", "run_dialog", "widen", "steps_box", "confirm"))
ns = {}
exec(code, ns)
Gtk, GLib = ns["Gtk"], ns["GLib"]
seen = []
def look():
    for w in Gtk.Window.list_toplevels():
        if isinstance(w, Gtk.MessageDialog) and w.get_visible():
            def labels(x):
                if isinstance(x, Gtk.Label):
                    yield x
                elif isinstance(x, Gtk.Container):
                    for c in x.get_children():
                        yield from labels(c)
            for l in labels(w.get_message_area()):
                seen.append("%s|%.1f" % (l.get_text(), l.get_xalign()))
            w.response(Gtk.ResponseType.CANCEL)
    return False
GLib.timeout_add(600, look)
ns["confirm"](None, "¿Crear a.test?", "Se pide la contraseña de sudo.", "Crear", steps=["Uno.", "Dos."])
print("\n".join(seen))
PY
        check "Linux (pintado): «Qué se va a realizar» y los pasos 1. y 2., a la izquierda" 'grep -qx "Qué se va a realizar|0.0" "$W/out" && grep -qx "1.|1.0" "$W/out" && grep -qx "Uno.|0.0" "$W/out" && grep -qx "2.|1.0" "$W/out" && grep -qx "Se pide la contraseña de sudo.|0.0" "$W/out"'
    fi
fi
exit $fail
