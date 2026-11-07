#!/bin/bash
# Tareas en segundo plano (Linux 1.57.1, Mac 1.41.0): la ventana de la tarea se esconde, el programa se
# puede usar, un aviso al lado del visor la trae de vuelta y no van dos tareas a la vez. Uso: segundo-plano.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
if grep -q "^let ERROR_LOG = " "$SRC"; then
    check "Mac: boton en la hoja mientras sigue" 'grep -qF "Button(\"Seguir en segundo plano\") { task.model?.taskHidden = true }" "$SRC"'
    check "Mac: escondida, la hoja no se ve y la tarea sigue" 'grep -qF ".sheet(item: Binding(get: { model.taskHidden ? nil : model.task }," "$SRC" && grep -qF "set: { t in if t == nil && !model.taskHidden { model.task = nil } }" "$SRC"'
    check "Mac: el aviso al lado del visor" 'grep -B3 "^            visor()$" "$SRC" | grep -qF "TaskBadge(task: t)" && grep -q "^struct TaskBadge: View {" "$SRC" && grep -qF "repeatForever(autoreverses: true)) { pulse = true }" "$SRC"'
    check "Mac: si acaba sin cerrarse sola, vuelve" 'grep -A3 "} else if model?.taskHidden == true {" "$SRC" | grep -qF "model?.taskHidden = false"'
    check "Mac: no van dos tareas a la vez" 'grep -A5 "if let cur = task, !cur.finished {" "$SRC" | grep -qF "return cur"'
    check "Mac: el aviso dice lo que hace" 'grep -qF "Text((task.title.split(separator: \" \").first.map(String.init) ?? \"En marcha\") + \"…\")" "$SRC" && grep -qF "self.title = title" "$SRC"'
    check "Mac: al acabar, el aviso se quita" 'grep -qF "if task == nil && taskHidden { taskHidden = false }" "$SRC"'
else
    check "Linux: boton en la ventana de la tarea" 'grep -qF "Gtk.Button(label=\"Seguir en segundo plano\"" "$SRC" && grep -qF "self.bg_btn.connect(\"clicked\", self.to_background)" "$SRC"'
    check "Linux: Esc o cerrarla la lleva al segundo plano" 'grep -qF "dlg.connect(\"delete-event\", self.on_delete)" "$SRC"'
    check "Linux: el aviso al lado del visor" 'grep -qF "center.pack_start(self.task_badge, False, False, 0)" "$SRC" && grep -q "^\.nv-tarea-flecha { animation: nv-baja" "$SRC"'
    check "Linux: el aviso dice lo que hace" 'grep -qF "verb = (task.dlg.get_title() or \"En marcha\").split()[0]" "$SRC"'
    check "Linux: no van dos tareas a la vez" 'grep -A6 "    def run_task(self, title, args, \*\*kw):" "$SRC" | grep -qF "bg.to_front()"'
    # El comportamiento de verdad, con la clase Task del script y una ventana falsa
    python3 -I - "$SRC" > "$TMPBASE/segundo-plano.$$" << 'PY'
import re, sys, types
t = open(sys.argv[1], encoding="utf-8").read()
body = re.search(r"\nclass Task:\n(.*?)\n# -{20,}", t, re.S).group(1)
names = ("on_delete", "to_background", "to_front")
code = "class Task:\n" + "\n".join(re.search(r"(    def %s\(self.*?)(?=\n    def )" % n, body, re.S).group(1) for n in names)
g = {}
exec(code, g)
class Dlg:
    def __init__(s): s.modal, s.shown = True, True
    def set_modal(s, m): s.modal = m
    def hide(s): s.shown = False
    def present(s): s.shown = True
class App:
    def __init__(s): s.badge = "-"
    def nv_task_badge(s, task): s.badge = task
task = g["Task"](); task.dlg, task.app, task.finished, task.background = Dlg(), App(), False, False
r = task.on_delete()
print("%d|Esc con la tarea en marcha: se esconde, sin modal, con su aviso" % (r is True and not task.dlg.shown and not task.dlg.modal and task.app.badge is task))
task.to_front()
print("%d|el aviso la trae de vuelta, modal, y se quita" % (task.dlg.shown and task.dlg.modal and task.app.badge is None and not task.background))
task.finished = True
print("%d|acabada, Esc la cierra" % (task.on_delete() is False))
old = g["Task"](); old.dlg, old.app, old.finished, old.background = Dlg(), types.SimpleNamespace(), False, False
print("%d|sin aviso (ventana antigua) no se esconde" % (old.on_delete() is True and old.dlg.shown))
PY
    while IFS='|' read -r good name; do
        check "$name" '[ "$good" = 1 ]'
    done < "$TMPBASE/segundo-plano.$$"
    rm -f "$TMPBASE/segundo-plano.$$"
fi
exit $fail
