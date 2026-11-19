#!/bin/bash
# Apariencia, tamaño y cristal (1.57.35): la ventana al 80, 90, 100 o 110 % y el aspecto de cristal, guardados en
# ~/.nexum/apariencia (el mismo fichero en Linux y Mac). Uso: apariencia-tamano.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
if grep -q "^let ERROR_LOG = " "$SRC"; then
    check "Mac: zoom y cristal en el fichero de Apariencia (se leen y se guardan)" 'grep -qF "let LOOK_ZOOMS = [80, 90, 100, 110]" "$SRC" && grep -qF "if let z = o[\"zoom\"] as? Int, LOOK_ZOOMS.contains(z) { c.zoom = z }" "$SRC" && grep -qF "\"zoom\": c.zoom, \"cristal\": c.cristal]" "$SRC"'
    check "Mac: la ventana entera a escala, y al 100 % tal cual" 'grep -qF ".scaleEffect(zoom, anchor: .topLeading)" "$SRC" && grep -qF "ZoomBox(zoom: CGFloat(model.look.zoom) / 100) {" "$SRC" && grep -qF "        if zoom == 1 {" "$SRC"'
    check "Mac: cristal con el material de macOS y la ventana sin opacar" 'grep -qF "v.blendingMode = .behindWindow" "$SRC" && grep -qF "w.isOpaque = !on" "$SRC" && grep -qF ".background(GlassBackground(on: model.look.cristal))" "$SRC"'
    check "Mac: en Apariencia, el tamaño y el cristal" 'grep -qF "Tile(\"Tamaño de la ventana\"" "$SRC" && grep -qF "Tile(\"Cristal\"" "$SRC"'
    exit $fail
fi
W=$(mktemp -d "$TMPBASE/tamano.XXXXXX") || exit 1
trap 'rm -rf "${W:?}"' EXIT
awk '/cat <<.LVM_GUI_PY.$/{f=1;next} /^LVM_GUI_PY$/{f=0} f' "$SRC" > "$W/gui.py"
mkdir -p "$W/home"
cat > "$W/t.py" << 'PY'
import json, os, sys, time
src = open(sys.argv[1], encoding="utf-8").read()
ns = {"__name__": "prueba"}
exec(compile(src[:src.index("\nif __name__")], "gui", "exec"), ns)
out = []
z = ns["css_zoom"]
out.append("zoom80|" + z("a { padding: 10px 1px 0.5px; margin: -4px; border-radius: 12px; }", 80))
out.append("zoom100|%s" % (z("a { padding: 10px; }", 100) == "a { padding: 10px; }"))
look = ns["LOOK_FILE"]
os.makedirs(os.path.dirname(look), exist_ok=True)
for raw, name in (('{"zoom": 90, "cristal": true}', "bueno"), ('{"zoom": 73, "cristal": "si"}', "malo"), ("{}", "vacio")):
    open(look, "w").write(raw)
    c = ns["look_conf"]()
    out.append("conf-%s|%s|%s" % (name, c["zoom"], c["cristal"]))
c = ns["look_conf"](); c["zoom"] = 80; c["cristal"] = True; ns["look_save"](c)
d = json.load(open(look))
out.append("guardado|%s|%s" % (d.get("zoom"), d.get("cristal")))
try:
    Gtk, Gdk = ns["Gtk"], ns["Gdk"]
    errs = []
    for zz in ns["LOOK_ZOOMS"]:
        for t in (ns["CSS"], ns["NEW_CSS"]):
            p = Gtk.CssProvider()
            p.connect("parsing-error", lambda _p, _s, e: errs.append(e.message))
            p.load_from_data(z(t, zz).encode())
    g = ns["glass_css"]()
    p = Gtk.CssProvider(); p.connect("parsing-error", lambda _p, _s, e: errs.append(e.message)); p.load_from_data(g.encode())
    imgs = sorted(os.listdir(ns["GLASS_DIR"]))
    out.append("css|%d|%s|%s" % (len(errs), ",".join(imgs), "url(" in g and "background-size: 100% 100%" in g))
    # Lo que cuesta pintar: una ventana de 1240x840 con 6 paneles, con cristal y sin él
    import cairo
    for t in (ns["CSS"], ns["NEW_CSS"], g):
        p = Gtk.CssProvider(); p.load_from_data(t.encode())
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), p, 800)
    win = Gtk.OffscreenWindow(); win.get_style_context().add_class("background")
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=20)
    for i in range(6):
        lb = Gtk.ListBox(); lb.get_style_context().add_class("caja")
        for j in range(5):
            r = Gtk.ListBoxRow(); r.add(Gtk.Label(label="Fila %d" % j)); lb.add(r)
        box.pack_start(lb, False, False, 0)
    win.add(box); win.set_default_size(1240, 840); win.show_all()
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, 1240, 840)
    def ms(on):
        ctx = win.get_style_context(); (ctx.add_class if on else ctx.remove_class)("nv-cristal")
        while Gtk.events_pending(): Gtk.main_iteration()
        cr = cairo.Context(surf)
        for _ in range(3): win.draw(cr)
        t0 = time.process_time()
        for _ in range(30): win.draw(cr)
        return (time.process_time() - t0) / 30 * 1000
    off, on = ms(False), ms(True)
    out.append("coste|%d" % (on < max(8.0, off * 6)))
except Exception as e:
    out.append("sin-gtk|%s" % e)
print("\n".join(out))
PY
res=$(cd "$W" && HOME="$W/home" LVM_SIMULAR=0 timeout 60 python3 -I t.py gui.py 2> /dev/null)
check "Linux: las medidas en px a escala (las de 1 px y las negativas, igual)" 'grep -qx "zoom80|a { padding: 8px 1px 0.5px; margin: -4px; border-radius: 10px; }" <<< "$res" && grep -qx "zoom100|True" <<< "$res"'
check "Linux: el fichero de Apariencia: zoom y cristal; lo que no vale, el de siempre" 'grep -qx "conf-bueno|90|True" <<< "$res" && grep -qx "conf-malo|100|False" <<< "$res" && grep -qx "conf-vacio|100|False" <<< "$res" && grep -qx "guardado|80|True" <<< "$res"'
if grep -q "^css|" <<< "$res"; then
    check "Linux: la hoja de estilos se carga a todos los tamaños, y el fondo del cristal es una imagen" 'grep -qx "css|0|fondo-claro.png,fondo-oscuro.png|True" <<< "$res"'
    check "Linux: el cristal no encarece el pintado (sin degradados que se recalculen)" 'grep -qx "coste|1" <<< "$res" && ! grep -q "radial-gradient" "$SRC"'
fi
check "Linux: en Apariencia, el tamaño y el cristal, y se aplican al momento" 'grep -qF "row = ActionRow(\"Tamaño de la ventana\"" "$SRC" && grep -qF "switch(lb, \"Cristal\"" "$SRC" && grep -qF "        if key in (\"zoom\", \"cristal\"):" "$SRC" && grep -qF "s.set_property(\"gtk-xft-dpi\", want)" "$SRC"'
exit $fail
