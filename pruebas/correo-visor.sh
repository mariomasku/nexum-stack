#!/bin/bash
# La bandeja de Mailpit dentro de la ventana (Linux 1.56.33, Mac 1.40.14): debajo de las tarjetas, el
# boton Correo lleva a ella, sin nada en disco y solo se navega dentro de Mailpit. Uso: correo-visor.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
if grep -q "^let ERROR_LOG = " "$SRC"; then
    check "Mac: visor sin nada en disco" 'grep -q "conf.websiteDataStore = WKWebsiteDataStore.nonPersistent()" "$SRC" && grep -q "^import WebKit$" "$SRC"'
    check "Mac: debajo de las tarjetas y con el mismo visor siempre" 'grep -q "MailWebView(host: model.mailWeb, url: m.url)" "$SRC" && grep -q "lazy var mailWeb = MailWebHost()" "$SRC"'
    check "Mac: el boton Correo lleva a su apartado, sin navegador" '! sed -n "/^    func openMail() {/,/^    }/p" "$SRC" | grep -q openURL && sed -n "/^    func openMail() {/,/^    }/p" "$SRC" | grep -q "toolsSection = \"correo\""'
    check "Mac: ya no hay boton Abrir en la bandeja" '! grep -q "Button(\"Abrir\") { openURL(m.url) }" "$SRC"'
    check "Mac: fuera de Mailpit no se navega; al navegador solo con clic" 'grep -q "if action.navigationType == .linkActivated { external(action.request.url) }" "$SRC" && grep -q "if let u = url, u.scheme == \"http\" || u.scheme == \"https\"" "$SRC"'
else
    check "Linux: visor sin nada en disco y sin proxy" 'grep -q "kit.WebsiteDataManager.new_ephemeral()" "$SRC" && grep -q "set_network_proxy_settings(kit.NetworkProxyMode.NO_PROXY, None)" "$SRC"'
    check "Linux: el componente se carga al necesitarlo y sin el se dice como ponerlo" '! grep -q "^from gi.repository import.*WebKit2" "$SRC" && grep -q "sudo apt install gir1.2-webkit2-4.1" "$SRC"'
    check "Linux: el visor se saca antes de vaciar la pestaña (si no, GTK lo destruye)" 'grep -A4 "^    def build_tools(self):$" "$SRC" | grep -q "web.get_parent().remove(web)"'
    check "Linux: un visor destruido no se reutiliza" 'grep -q "web.connect(\"destroy\", self.nv_mail_destroyed)" "$SRC"'
    check "Linux: en la simulacion no se abre (desde ella se puede borrar)" 'sed -n "/^    def nv_mail_view/,/^    def nv_mail_tools/p" "$SRC" | grep -q "if SIMULATE:"'
    check "Linux: el boton Correo lleva a su apartado" 'sed -n "/^    def nv_open_mail/,/^    def nv_mail_webkit/p" "$SRC" | grep -q "self.nv_tools_show(\"Correo de pruebas (Mailpit)\")"'
    check "Linux: ya no hay boton Abrir en la bandeja" '! grep -q "Gtk.Button(label=\"Abrir\", tooltip_text=\"Abrir la bandeja\"" "$SRC"'
    # La politica de navegacion, de verdad
    python3 -I - "$SRC" > "$TMPBASE/correo-visor.$$" << 'PY'
import re, sys, types
t = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"    def nv_mail_policy\(self.*?(?=\n    def nv_mail_download)", t, re.S)
code = "\n".join(l[4:] for l in m.group(0).split("\n"))
g = {}
exec(code, g)
base = "http://127.0.0.1:8025/"
class E: RESPONSE, NAVIGATION_ACTION, NEW_WINDOW_ACTION = 0, 1, 2
class N: OTHER, LINK_CLICKED = 0, 1
opened = []
app = types.SimpleNamespace(mail_webkit=types.SimpleNamespace(PolicyDecisionType=E, NavigationType=N), mail_web_url=base, open_uri=opened.append)
app.nv_mail_external = lambda u: g["nv_mail_external"](app, u)
class R:
    def __init__(s, u): s.u = u
    def get_uri(s): return s.u
class A:
    def __init__(s, u, t, h): s.u, s.t, s.h = u, t, h
    def get_request(s): return R(s.u)
    def get_navigation_type(s): return s.t
    def is_user_gesture(s): return s.h
class D:
    def __init__(s, a): s.a, s.no = a, False
    def get_navigation_action(s): return s.a
    def ignore(s): s.no = True
for name, u, typ, h, kind, blocked, ext in (
    ("dentro de Mailpit", base + "view/x", N.OTHER, False, E.NAVIGATION_ACTION, False, False),
    ("el HTML del correo", "about:srcdoc", N.OTHER, False, E.NAVIGATION_ACTION, False, False),
    ("otro puerto del equipo", "http://127.0.0.1:8026/", N.OTHER, False, E.NAVIGATION_ACTION, True, False),
    ("enlace pulsado", "https://example.com/", N.LINK_CLICKED, True, E.NAVIGATION_ACTION, True, True),
    ("redireccion sola", "https://example.com/", N.OTHER, False, E.NAVIGATION_ACTION, True, False),
    ("ventana con clic", "https://example.com/", N.LINK_CLICKED, True, E.NEW_WINDOW_ACTION, True, True),
    ("ventana sin clic", "https://example.com/", N.OTHER, False, E.NEW_WINDOW_ACTION, True, False),
    ("clic a file:", "file:///etc/passwd", N.LINK_CLICKED, True, E.NAVIGATION_ACTION, True, False),
    ("clic a javascript:", "javascript:alert(1)", N.LINK_CLICKED, True, E.NAVIGATION_ACTION, True, False),
):
    opened.clear()
    d = D(A(u, typ, h))
    g["nv_mail_policy"](app, None, d, kind)
    print("%d|%s" % (d.no == blocked and bool(opened) == ext, name))
PY
    while IFS='|' read -r good name; do
        check "politica: $name" '[ "$good" = 1 ]'
    done < "$TMPBASE/correo-visor.$$"
    rm -f "$TMPBASE/correo-visor.$$"
fi
exit $fail
