#!/bin/bash
# Diálogos que piden confirmar varios cambios (Linux 1.57.4, Mac 1.41.3): «Qué se va a realizar» y los
# cambios numerados, a la izquierda; el texto de siempre, debajo como nota.
# Uso: dialogos.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
if grep -q "^let ERROR_LOG = " "$SRC"; then
    check "Mac: confirm y runDialog aceptan los pasos" 'grep -qF "             steps: [String] = [], warning: String? = nil, task: Bool = true) -> Bool {" "$SRC" && grep -qF "destructive: destructive, steps: steps, warning: warning).ok" "$SRC"'
    check "Mac: «Qué se va a realizar», numerado y a la izquierda" 'grep -qF "\"Qué se va a realizar\\n\"" "$SRC" && grep -qF "NSAttributedString(string: \"\\(i + 1).\"" "$SRC" && grep -qF "l.alignment = .left" "$SRC"'
    check "Mac: con pasos, la nota a la izquierda" 'grep -qF "steps.isEmpty ? dialogLabel(text) : dialogLabel(text, color: .secondaryLabelColor, align: .left)" "$SRC"'
    check "Mac: crear dominio, copiar, replicar, cargar, actualizar, instalar y Actualizar todo, con pasos" '[ "$(grep -cE "steps: (steps|notes|what|c\.items|list\.map|notes \+ )" "$SRC")" -ge 7 ]'
    check "Mac: git pull antes de copiar, con los pasos" 'grep -qF "let steps = dialogSteps(what)" "$SRC"'
    check "Mac: con otra tarea en marcha, lo dice nombrándola (antes de preguntar y al lanzarla)" 'grep -qF "if task, let guardTask = TASK_GUARD, guardTask() { return false }" "$SRC" && grep -qF "TASK_GUARD = { [weak self] in" "$SRC" && grep -qF "sigue en marcha. Espera a que acabe y vuelve a probar." "$SRC" && grep -qF "            refuseTask(cur)" "$SRC"'
    check "Mac: Instalar versiones se puede pulsar con otra tarea (y lo dice)" 'grep -qF ".disabled(model.selected.isEmpty)" "$SRC" && ! grep -qF ".disabled(model.selected.isEmpty || model.busy)" "$SRC"'
    check "Mac: ya no hay listas con viñetas en los diálogos" '! grep -qE "confirm\(.*map \{ \"• \" \+" "$SRC"'
else
    check "Linux: confirm acepta los pasos" 'grep -qF "def confirm(parent, title, text, ok_label, destructive=False, extra=None, steps=None, task=True):" "$SRC"'
    check "Linux: «Qué se va a realizar», numerado y a la izquierda" 'grep -qF "head.set_markup(\"<b>Qué se va a realizar</b>\")" "$SRC" && grep -qF "% (GREEN, i))" "$SRC"'
    check "Linux: el centrado de los diálogos no toca los pasos" 'grep -qF "or getattr(w, \"nv_pasos\", False):" "$SRC"'
    check "Linux: crear dominio, copiar, replicar, cargar, actualizar, instalar y Actualizar todo, con pasos" '[ "$(grep -cE "steps=(steps|notes|what|res\[\"items\"\]|\[\"Se instala|notes \+)" "$SRC")" -ge 7 ]'
    check "Linux: git pull antes de copiar, con los pasos" 'grep -qF "pack_start(steps_box(what," "$SRC"'
    check "Linux: con otra tarea en marcha, lo dice nombrándola en la ventana que se mira" 'grep -qF "TASK_GUARD[0] = lambda check=False: bool(self.task_running()) and (check or self.refuse_task() or True)" "$SRC" && grep -qF "sigue en marcha. Espera a que acabe y vuelve a probar.\" % (cur.title" "$SRC" && grep -qF "if w.is_active() and w.get_visible()), self.win)" "$SRC"'
    check "Linux: la tarea en marcha se mira aunque no esté en segundo plano" 'grep -qF "        self.cur_task = Task(self, title, args, on_done=done, **kw)" "$SRC" && ! grep -qF "if self.busy and bg is not None and not bg.finished:" "$SRC"'
    check "Linux: cancelar la propia tarea sí se pregunta" 'grep -qF "destructive=True, task=False):" "$SRC"'
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
code = 'import gi\ngi.require_version("Gtk", "3.0")\nfrom gi.repository import Gtk, GLib\nGREEN = "#45A57C"\nTASK_GUARD = [None]\n'
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
# (1.57.33) con otra tarea en marcha no se pregunta: la guarda lo dice y confirm devuelve False sin diálogo
said = []
ns["TASK_GUARD"][0] = lambda: said.append(1) or True
seen.clear()
GLib.timeout_add(600, look)
r = ns["confirm"](None, "¿Instalar?", "", "Instalar")
r2 = ns["confirm"](None, "¿Cancelar la tarea?", "", "Cancelar", task=False)
print("guarda|%s|%s|%d|%s" % (r, r2, len(said), any(x.startswith("¿Cancelar") for x in seen) and not any(x.startswith("¿Instalar") for x in seen)))
PY
        check "Linux (pintado): «Qué se va a realizar» y los pasos 1. y 2., a la izquierda" 'grep -qx "Qué se va a realizar|0.0" "$W/out" && grep -qx "1.|1.0" "$W/out" && grep -qx "Uno.|0.0" "$W/out" && grep -qx "2.|1.0" "$W/out" && grep -qx "Se pide la contraseña de sudo.|0.0" "$W/out"'
        check "Linux (pintado): con otra tarea en marcha, confirm no pregunta (salvo lo de la propia tarea)" 'grep -qx "guarda|False|False|1|True" "$W/out"'
    fi
fi
exit $fail
