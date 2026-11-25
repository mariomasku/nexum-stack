# Clics de verdad (eventos de GTK) sobre lo que lleva busy_guard: lo usa tarea-ocupada.sh
import sys
src = open(sys.argv[1], encoding="utf-8").read()
ns = {"__name__": "prueba"}
exec(compile(src[:src.index("\nif __name__")], "gui", "exec"), ns)
Gtk, GLib, Gdk = ns["Gtk"], ns["GLib"], ns["Gdk"]
state = {"busy": True, "warned": 0}
ns["TASK_GUARD"][0] = lambda check=False: state["busy"] and (check or state.__setitem__("warned", state["warned"] + 1) or True)
log = []
win = Gtk.Window(); box = Gtk.Box(spacing=10)
b = ns["busy_guard"](Gtk.Button(label="Instalar"), True); b.connect("clicked", lambda *_: log.append("clic"))
sw = ns["busy_guard"](Gtk.Switch(), True)
combo = ns["busy_guard"](Gtk.ComboBoxText(), True); combo.append_text("a"); combo.append_text("b")
for w in (b, sw, combo): box.pack_start(w, False, False, 0)
win.add(box); win.show_all()
def click(w):
    a = w.get_allocation(); gw = w.get_window()
    x, y = a.x + a.width // 2, a.y + a.height // 2
    # (la ventana de entrada que esté debajo del punto, la más honda)
    while True:
        sub = [c for c in gw.get_children() if c.is_visible() and
               c.get_position()[0] <= x < c.get_position()[0] + c.get_width() and
               c.get_position()[1] <= y < c.get_position()[1] + c.get_height()]
        if not sub: break
        px, py = sub[-1].get_position(); x, y = x - px, y - py; gw = sub[-1]
    dev = Gdk.Display.get_default().get_default_seat().get_pointer()
    for t in (Gdk.EventType.BUTTON_PRESS, Gdk.EventType.BUTTON_RELEASE):
        ev = Gdk.Event.new(t)
        ev.button.window = gw; ev.button.x = float(x); ev.button.y = float(y); ev.button.button = 1
        ev.button.time = Gtk.get_current_event_time() or GLib.get_monotonic_time() // 1000
        ev.set_device(dev); ev.set_source_device(dev)
        Gtk.main_do_event(ev)
steps = []
def run():
    click(b); click(sw); click(combo)
    GLib.timeout_add(400, phase2)
    return False
def phase2():
    pop = combo.get_property("popup-shown")
    steps.append("ocupado: clics=%d interruptor=%s desplegable_abierto=%s avisos=%d atenuado=%s" % (
        log.count("clic"), sw.get_active(), pop, state["warned"], b.get_style_context().has_class("nv-espera")))
    state["busy"] = False; ns["busy_guard"](b, False)
    click(b); click(sw); click(combo)
    GLib.timeout_add(400, phase3)
    return False
def phase3():
    steps.append("libre: desplegable_abierto=%s" % combo.get_property("popup-shown"))
    steps.append("libre: clics=%d interruptor=%s avisos=%d atenuado=%s" % (log.count("clic"), sw.get_active(), state["warned"], b.get_style_context().has_class("nv-espera")))
    print("\n".join(steps)); Gtk.main_quit()
    return False
GLib.timeout_add(800, run)
Gtk.main()
