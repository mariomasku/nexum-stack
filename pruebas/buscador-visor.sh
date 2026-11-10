#!/bin/bash
# Desplegables largos con buscador y ▶ / ■ en el visor (Linux y Mac 1.57.9): con 8 opciones o más, el desplegable
# se abre con «Buscar…» (se escribe y se queda lo que lleva ese texto, flechas, Intro y Esc); en el visor, a la
# derecha de Apache y MariaDB, ▶ arranca (sin ninguna activa, despliega las versiones, la última primero) y ■ para.
# Uso: buscador-visor.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
if grep -q "^let ERROR_LOG = " "$SRC"; then
    check "Mac: SearchPicker con buscador a partir de 8 opciones (con menos, el Picker de siempre)" 'grep -qx "let COMBO_SEARCH_MIN = 8" "$SRC" && grep -qF "if items.count < COMBO_SEARCH_MIN {" "$SRC" && grep -qF "KeySearchField(text: \$query, placeholder: \"Buscar…\"," "$SRC"'
    check "Mac: filtra por lo que lleva el texto, sin distinguir mayúsculas" 'grep -qF "items.filter { \$0.1.lowercased().contains(q) }" "$SRC"'
    check "Mac: flechas, Intro y Esc en el buscador" 'grep -qF "case #selector(NSResponder.moveDown(_:)): parent.onMove(1)" "$SRC" && grep -qF "case #selector(NSResponder.insertNewline(_:)): parent.onEnter()" "$SRC" && grep -qF "case #selector(NSResponder.cancelOperation(_:)):" "$SRC"'
    check "Mac: todos los desplegables (no los de opciones ni los segmentos) son SearchPicker" '[ "$(grep -c "^ *SearchPicker(selection:" "$SRC")" -ge 15 ] && [ "$(grep -c "^ *Picker(\"\", selection:" "$SRC")" -eq 4 ]'
    check "Mac: ▶ / ■ a la derecha de los servicios" 'grep -A3 "ServicesView(close: { servicesOpen = false })" "$SRC" | grep -qF "powerButton()"'
    check "Mac: sin ninguna activa, ▶ despliega las versiones (la última primero) y la arranca" 'grep -qF "if active.isEmpty { powerOpen.toggle() } else { model.power() }" "$SRC" && grep -qF "model.activate(i.folder)" "$SRC" && grep -qF "let LAST_VERSION_FILE = LOG_DIR + \"/ultima-version\"" "$SRC"'
    check "Mac: al parar, se recuerda cuál era" 'grep -qF "try? (d.active + \"\\n\").write(toFile: LAST_VERSION_FILE, atomically: true, encoding: .utf8)" "$SRC"'
else
    check "Linux: los desplegables de 8 o más se abren con buscador" 'grep -qx "COMBO_SEARCH_MIN = 8" "$SRC" && grep -qF "widget.connect(\"notify::popup-shown\", popup_shown)" "$SRC" && grep -qF "GLib.idle_add(lambda: (combo_search(combo), False)[1])" "$SRC"'
    check "Linux: ▶ / ■ a la derecha de los servicios" 'grep -A1 "pill.pack_start(self.status_btn, False, False, 0)" "$SRC" | grep -qF "pill.pack_start(self.power_btn, False, False, 0)"'
    check "Linux: sin ninguna activa, ▶ despliega las versiones (la última primero) y la arranca" 'grep -qF "key=lambda i: (i[\"folder\"] != last, i[\"folder\"])" "$SRC" && grep -qF "self.on_activate_version(None, f)" "$SRC" && grep -qF "LAST_VERSION_FILE = os.path.join(LOG_DIR, \"ultima-version\")" "$SRC"'
    check "Linux: el icono, solo (sin círculo ni borde) y de 22" 'grep -qF "self.power_img.set_pixel_size(22)" "$SRC" && ! grep -qF "button.nv-encender { border-radius: 50%" "$SRC"'
    if [ -n "$DISPLAY$WAYLAND_DISPLAY" ] && python3 -c "import gi" 2> /dev/null; then
        W=$(mktemp -d "$TMPBASE/buscador.XXXXXX") || exit 1
        trap 'rm -rf "${W:?}"' EXIT
        awk '/cat <<.LVM_GUI_PY.$/{f=1;next} /^LVM_GUI_PY$/{f=0} f' "$SRC" > "$W/gui.py"
        timeout 30 python3 -I - "$W/gui.py" > "$W/out" 2>&1 << 'PY'
import re, sys
g = open(sys.argv[1], encoding="utf-8").read()
def fn(name):
    return re.search(r"^def %s\(.*?(?=^\S)" % name, g, re.S | re.M).group(0)
code = 'import gi\ngi.require_version("Gtk", "3.0")\ngi.require_version("Gdk", "3.0")\nfrom gi.repository import Gtk, Gdk, GLib\nCOMBO_SEARCH_MIN = 8\n'
code += "".join(fn(n) for n in ("label", "css", "combo_search"))
ns = {}
exec(code, ns)
Gtk, Gdk, GLib = ns["Gtk"], ns["Gdk"], ns["GLib"]
w = Gtk.Window()
c = Gtk.ComboBoxText()
for n in ("panaderia-luna", "taller-bici", "floristeria-sol", "academia-ingles", "clinica-dental",
          "libreria-mar", "gimnasio-norte", "bodega-sur", "zapateria-centro", "Panaderia-rio"):
    c.append_text(n)
c.set_active(0)
w.add(c)
w.show_all()
short = Gtk.ComboBoxText()
for n in ("uno", "dos"):
    short.append_text(n)
out = []
def go():
    out.append("corto:%s" % ns["combo_search"](short))
    out.append("largo:%s" % ns["combo_search"](c))
    pop = c.search_popover
    box = pop.get_child()
    entry = box.get_children()[0]
    lb = box.get_children()[1].get_child().get_child()
    entry.set_text("PANA")
    def after():
        out.append("filtra:" + ",".join(r.key for r in lb.get_children() if r.get_child_visible()))
        ev = Gdk.Event.new(Gdk.EventType.KEY_PRESS)
        ev.keyval = Gdk.KEY_Down
        entry.emit("key-press-event", ev)
        ev.keyval = Gdk.KEY_Return
        entry.emit("key-press-event", ev)
        out.append("elegido:%s" % c.get_active_text())
        print("\n".join(out))
        Gtk.main_quit()
        return False
    GLib.timeout_add(400, after)
    return False
GLib.timeout_add(300, go)
GLib.timeout_add(10000, Gtk.main_quit)
Gtk.main()
PY
        check "Linux (pintado): con menos de 8, el menú de siempre" 'grep -qx "corto:False" "$W/out"'
        check "Linux (pintado): con 8 o más, la lista con buscador" 'grep -qx "largo:True" "$W/out"'
        check "Linux (pintado): «PANA» deja los dos que lo llevan (sin distinguir mayúsculas)" 'grep -qx "filtra:panaderia-luna,panaderia-rio" "$W/out"'
        check "Linux (pintado): flecha abajo e Intro eligen el segundo" 'grep -qx "elegido:Panaderia-rio" "$W/out"'
    fi
fi
exit $fail
