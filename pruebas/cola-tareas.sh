#!/bin/bash
# La cola de tareas (1.57.40): con una tarea en marcha, la que se pide va a la cola y empieza cuando acabe la
# anterior (si esa falla, antes se pregunta); traer los cambios de un repositorio va a su lado si no es de la misma
# carpeta; crear una BBDD vacía espera. Y, de la misma versión: Avisos en amarillo, el registro de tareas con el
# alto de sus filas y el logotipo de NGINX con sus letras. Uso: cola-tareas.sh <script de Linux o del Mac>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
if grep -q "^let ERROR_LOG = " "$SRC"; then
    check "Mac: con otra en marcha (o acabada, con su hoja abierta), a la cola y lo dice" 'grep -A3 "        if task != nil {" "$SRC" | grep -qF "taskQueue.append(q)" && grep -qF "toast(\"En la cola: «\\(title)». Empieza cuando acabe" "$SRC"'
    check "Mac: al cerrarse la hoja, la siguiente (después, por si su botón lanza otra)" 'grep -qF "DispatchQueue.main.async { [weak self] in self?.taskClosed(old) }" "$SRC" && grep -qF "        guard task == nil, !taskQueue.isEmpty else { return }" "$SRC" && grep -qF "        launchTask(taskQueue.removeFirst())" "$SRC"'
    check "Mac: si la anterior falla, pregunta antes de seguir" 'grep -qF "        if !lastTaskOk {" "$SRC" && grep -qF "okLabel: \"Seguir con la cola\", style: .warning, cancelLabel: \"Vaciar la cola\").ok {" "$SRC"'
    check "Mac: al acabar bien con más en la cola, su hoja se cierra sola (salvo si ofrece algo)" 'grep -qF "if ok, !self.taskQueue.isEmpty, task.extraLabel == nil, self.task === task {" "$SRC"'
    check "Mac: la cola en la hoja de la tarea, con «Vaciar la cola», y en el aviso de segundo plano" 'grep -qF "Text(\"Después, en la cola: \" + model.taskQueue.map" "$SRC" && grep -qF "Button(\"Vaciar la cola\") { model.clearTaskQueue() }" "$SRC" && grep -qF "Text(\"· \\(model.taskQueue.count) en la cola\")" "$SRC" && grep -qF "TaskView(task: t).environmentObject(model)" "$SRC"'
    check "Mac: cerrar la ventana no corta la cola; salir con tareas en ella, se pregunta" 'grep -qF "if task == nil && oldValue != nil && taskQueue.isEmpty && !TrayIcon.shared.on" "$SRC" && grep -qF "if let m = AppModel.current, !m.taskQueueQuit() { return }" "$SRC"'
    check "Mac: traer los cambios, al lado de la otra si no es de su carpeta" 'grep -qF "let free = task != nil && taskFree(r.folder)" "$SRC" && grep -qF "runFree(title, args, doneText: \"Hecho\")" "$SRC"'
    check "Mac: crear una BBDD vacía espera a que acabe la tarea" 'grep -B1 -A2 "        if let cur = runningTask {" "$SRC" | grep -qF "refuseTask(cur)"'
    check "Mac: Avisos en amarillo" 'grep -B2 -A1 "UIIcon(\"exclamationmark.triangle.fill\").foregroundColor(.yellow)" "$SRC" | grep -qF "Text(\"\\(n)\")"'
    check "Mac: el registro de tareas, con el alto medido de sus 4 primeras filas" 'grep -qF "private struct TaskRowHeightsKey: PreferenceKey {" "$SRC" && grep -qF ".frame(height: max(listHeight, 3 * 54))" "$SRC"'
    check "Mac: la página de Nginx, con el logotipo de NGINX" 'grep -qF "BrandImage(key: \"nginx\", height: 26)" "$SRC" && grep -qE "^    \"nginx\": \"JVBERi0" "$SRC"'
else
    check "Linux: crear una BBDD vacía espera a que acabe la tarea" 'grep -B1 -A3 "        if self.task_running():" "$SRC" | grep -qF "run_quick([\"crear-bd\", name], created, env=self.db_env())"'
    check "Linux: Avisos en amarillo" 'grep -qF ".nv-aviso-num { background-color: #ffd60a;" "$SRC" && grep -qF "css(icon(\"dialog-warning-symbolic\"), \"nv-aviso-icono\")" "$SRC"'
    check "Linux: el registro de tareas se mide con sus filas en la ventana" 'grep -qF "lb.connect(\"size-allocate\", lambda *_: GLib.idle_add(self.nv_tasks_fit))" "$SRC" && grep -qF "        h = max(h, min(len(rows), 3) * 54)" "$SRC"'
    check "Linux: la página de Nginx, con el logotipo de NGINX" 'grep -qF "        tl = BrandLogo(\"nginx\", 26)" "$SRC" && grep -qF "\"nginx\": 4.7595" "$SRC"'
    # La cola de verdad: los métodos del script, con una ventana de tarea falsa y GLib.idle_add al momento
    python3 -I - "$SRC" > "$TMPBASE/cola.$$" 2>&1 << 'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
def method(name):
    return re.search(r"(    def %s\(self.*?)(?=\n    def |\n\S)" % name, t, re.S).group(1)
names = ("task_running", "task_note", "task_free", "run_task", "task_launch", "task_enqueue", "task_after", "task_closed",
         "task_queue_clear", "task_queue_quit")
asked = []
class GLib:
    @staticmethod
    def idle_add(fn, *a):
        fn(*a)
class Dlg:
    def __init__(s, task): s.task, s.cb = task, []
    def connect(s, sig, fn): s.cb.append(fn)
    def destroy(s):
        s.task.closed = True
        for fn in s.cb:
            fn()
class Btn:
    def __init__(s): s.v = False
    def get_visible(s): return s.v
class Task:
    made = []
    def __init__(s, app, title, args, on_done=None, free=False, **kw):
        s.app, s.title, s.args, s.on_done, s.free, s.kw = app, title, args, on_done, free, kw
        s.finished = s.ok = s.closed = False
        s.done_text = kw.get("done_text")
        s.dlg, s.extra_btn = Dlg(s), Btn()
        Task.made.append(s)
    def queue_show(s, q): pass
    def end(s, ok):
        s.finished, s.ok = True, ok
        s.on_done(ok, s, None)
        if ok and s.kw.get("auto_close"):
            s.dlg.destroy()
def confirm(parent, title, text, ok, **kw):
    asked.append(title)
    return answer[0]
answer = [True]
def plural(n, a, b): return "%d %s" % (n, a if n == 1 else b)
code = "class App:\n" + "\n".join(method(n) for n in names)
g = {"GLib": GLib, "Task": Task, "confirm": confirm, "plural": plural}
exec(code, g)
class A(g["App"]):
    def __init__(s):
        s.busy, s.task_queue, s.task_hold, s.task_from_offer, s.win, s.toasts = False, [], False, False, None, []
    def toast(s, x): s.toasts.append(x)
    def reload(s, **kw): pass
    def nv_queue_show(s): pass
    def refuse_task(s): pass
app = A()
one = app.run_task("Uno", ["uno"])
two = app.run_task("Dos", ["dos"], auto_close=True)
three = app.run_task("Tres", ["tres"])
print("%d|con una en marcha, las demás a la cola, en orden, y se dice" % (
    isinstance(one, Task) and not isinstance(two, Task) and [q["title"] for q in app.task_queue] == ["Dos", "Tres"]
    and app.busy and app.toasts[0].startswith("En la cola: «Dos»")))
print("%d|la pregunta de una tarea dice que va a la cola, nombrando la de ahora" % ("«Uno» sigue en marcha" in (app.task_note() or "")))
one.end(True)
print("%d|al acabar bien con más en la cola, su ventana se cierra sola y empieza la siguiente" % (
    one.closed and app.cur_task.title == "Dos" and [q["title"] for q in app.task_queue] == ["Tres"]))
app.cur_task.end(False)
print("%d|si falla, su ventana se queda (para ver qué ha pasado) y no sigue" % (
    not app.cur_task.closed and app.cur_task.title == "Dos" and app.task_queue and not asked))
app.cur_task.dlg.destroy()
print("%d|al cerrarla, pregunta y, si se sigue, la siguiente" % (asked == ["¿Seguir con la cola?"] and app.cur_task.title == "Tres"))
app.cur_task.end(True)
app.cur_task.dlg.destroy()
print("%d|sin nada más, todo libre" % (not app.busy and not app.task_hold and not app.task_queue and app.task_note() is None))
# Si falla y no se sigue: la cola se vacía
asked.clear(); answer[0] = False
a = app.run_task("Cuatro", ["cuatro"]); app.run_task("Cinco", ["cinco"])
a.end(False); a.dlg.destroy()
print("%d|si falla y no se sigue, la cola se vacía sin hacer nada" % (asked and not app.task_queue and app.cur_task is a and not app.busy))
# El botón de la que acaba de terminar: su tarea va antes que las de la cola
answer[0] = True
b = app.run_task("Seis", ["seis"]); app.run_task("Siete", ["siete"])
b.extra_btn.v = True
b.end(True)
app.task_from_offer = True
b.dlg.destroy(); app.run_task("Del botón", ["boton"])
app.task_from_offer = False
print("%d|ofrece algo: su ventana no se cierra sola, y lo que lanza su botón va antes" % (app.cur_task.title == "Del botón" or [q["title"] for q in app.task_queue][:1] == ["Del botón"]))
# Traer los cambios: al lado si la de ahora no es de su carpeta; si lo es, a la cola
while app.task_queue or (app.cur_task and not app.cur_task.closed):
    cur = app.cur_task
    if not cur.finished:
        cur.end(True)
    if not cur.closed:
        cur.dlg.destroy()
c = app.run_task("Actualizando tienda", ["actualizar-proyecto", "tienda"])
print("%d|traer los cambios de otra carpeta va ya, a su lado, sin cola" % (app.task_free("blog") and app.run_task("Trayendo blog", ["repo-traer", "x/blog"], free=True).free and not app.task_queue))
print("%d|de la misma carpeta, no: a la cola" % (not app.task_free("tienda")))
print("%d|salir con tareas en la cola se pregunta" % (app.task_queue_quit() is True and (app.run_task("Ocho", ["ocho"]) or True) and (asked.clear() or answer.__setitem__(0, False) or True) and app.task_queue_quit() is False and asked == ["¿Cerrar con tareas en la cola?"]))
PY
    while IFS='|' read -r good name; do
        [ -n "$name" ] || { bad "Linux (cola): $good"; continue; }
        check "Linux (cola): $name" '[ "$good" = 1 ]'
    done < "$TMPBASE/cola.$$"
    rm -f "$TMPBASE/cola.$$"
fi
exit $fail
