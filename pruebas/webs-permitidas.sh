#!/bin/bash
# Webs permitidas de la barrera entre webs y espacios de trabajo de VS Code (1.57.41). En Linux, el comando
# barrera-web permitir|quitar de verdad (con secure_all y lo demas de mentira) y los .code-workspace con las
# funciones de la ventana; en el Mac, lo que lleva el script. Lo de Apache esta en barrera.sh.
# Uso: webs-permitidas.sh <script de Linux o del Mac>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-permitidas.XXXX")
trap 'rm -rf "${W:?}"' EXIT
if grep -q "^let ERROR_LOG = " "$SRC"; then
    check "Mac: la lista, del administrador (en XAMPP-compartido) y solo si es de root" 'grep -qF "WEB_BARRIER_ALLOW=\$COMMON/lvm-barrera-permitidas" "$SRC" && grep -qF "[ -n \"\$TEST_DIR\" ] || [ \"\$(stat -f %u \"\$WEB_BARRIER_ALLOW\" 2> /dev/null)\" == 0 ] || return 0" "$SRC"'
    check "Mac: con la barrera y sin ella, el hueco relleno (unknown_host_vhost)" 'grep -A10 "^function unknown_host_vhost() {" "$SRC" | grep -qF "web_barrier_fill \"\$text\""'
    check "Mac: el hueco en la barrera y en CORS" '[ "$(grep -c "lvm-permitidas\\\\.invalid" "$SRC")" -ge 3 ]'
    check "Mac: barrera-web permitir|quitar|permitidas" 'grep -qF "barrera-web) web_barrier_command \"\$2\" \"\$3\" ;;" "$SRC" && grep -qF "permitir|quitar) web_barrier_allow_command \"\$1\" \"\$2\"; return ;;" "$SRC"'
    check "Mac: la ventana recibe la lista (T|1|...)" 'grep -qF "echo \"T|\$(web_barrier_on && echo 1 || echo 0)|\$(web_barrier_allowed | paste -sd '"' '"' -)\"" "$SRC" && grep -qF "d.barrierAllowed = f.count >= 3" "$SRC"'
    check "Mac: Añadir… y Quitar en Seguridad entre webs" 'grep -qF "Button(\"Añadir…\") { model.addBarrierAllowed() }" "$SRC" && grep -qF "Button(\"Quitar\") { model.removeBarrierAllowed(dom) }" "$SRC" && grep -qF "runTask(\"Permitiendo \\(dom)\", [\"barrera-web\", \"permitir\", dom]" "$SRC"'
    check "Mac: VS Code abre el espacio de trabajo del proyecto (y lo crea si no tiene)" 'grep -qF "let VSCODE_WS_FILE = LOG_DIR + \"/vscode-espacios\"" "$SRC" && grep -qF "if let ws = had ?? vscodeWorkspace(folder) {" "$SRC" && grep -qF "VSCodeWsTile()" "$SRC"'
    # Las funciones de bash del Mac, aqui (con TEST_DIR, cualquier fichero vale)
    extract "$SRC" web_barrier_allowed web_barrier_domain web_barrier_allow_regex web_barrier_fill || exit 1
    eval "$(grep -E "^WEB_BARRIER_(SLOT|ALLOW_RE)=" "$SRC")"
    TEST_DIR=$W WEB_BARRIER_ALLOW=$W/lista
    printf '%s\n' erp.ejemplo-empresa.com '*.grupo.example' > "$W/lista"
    check "Mac: el hueco, con las de la lista" '[ "$(web_barrier_fill "a lvm-permitidas\.invalid b")" = "a erp\.ejemplo-empresa\.com|([a-z0-9-]+\.)*grupo\.example b" ] || [ "$(web_barrier_fill "a lvm-permitidas\.invalid b")" = "a ([a-z0-9-]+\.)*grupo\.example|erp\.ejemplo-empresa\.com b" ]'
    check "Mac: lo que se pega, en la forma de la lista" '[ "$(web_barrier_domain "https://ERP.ejemplo-empresa.com/x")" = erp.ejemplo-empresa.com ] && [ -z "$(web_barrier_domain "*.com")" ]'
    exit $fail
fi
# --- Linux: el comando, con lo que toca el sistema de mentira ---
extract "$SRC" cross_site_command cross_site_allow_command cross_site_apply cross_site_on cross_site_allowed cross_site_domain \
    cross_site_allow_regex cross_site_fill || exit 1
eval "$(grep -E "^CROSS_SITE_ALLOW_(SLOT|RE)=" "$SRC")"
LOG_DIR=$W/nexum CROSS_SITE_OFF=$W/nexum/sin-barrera-entre-webs CROSS_SITE_ALLOW=$W/nexum/barrera-webs-permitidas DRY=0
DOCKER_WEB_DIR=$W/no-hay
sudo_first() { return 0; }
lampp_running() { return 1; }
secure_all() { echo "secure_all" >> "$W/llamadas"; return "${SECURE_RC:-0}"; }
out=$(cross_site_command permitir "https://ERP.Ejemplo-Empresa.com/login")
check "Linux: permitir guarda el dominio (lo pegado, en su forma) y lo aplica en todas" '[ "$(cat "$CROSS_SITE_ALLOW")" = erp.ejemplo-empresa.com ] && grep -q "^secure_all$" "$W/llamadas" && grep -qF "erp.ejemplo-empresa.com, permitida" <<< "$out"'
cross_site_command permitir '*.grupo.example' > /dev/null
check "Linux: la lista, ordenada y sin repetir" '[ "$(cross_site_command permitidas | paste -sd " ")" = "*.grupo.example erp.ejemplo-empresa.com" ] && cross_site_command permitir erp.ejemplo-empresa.com | grep -q "ya estaba"'
check "Linux: sin argumento dice cuales son" 'cross_site_command | grep -qF "Webs permitidas: *.grupo.example erp.ejemplo-empresa.com"'
check "Linux: un dominio que no vale, nada" '! cross_site_command permitir "*.com" > /dev/null && ! cross_site_command permitir "a b" > /dev/null && [ "$(wc -l < "$CROSS_SITE_ALLOW")" = 2 ]'
SECURE_RC=2 cross_site_command quitar erp.ejemplo-empresa.com > "$W/o" 2>&1
check "Linux: si no se puede aplicar, la lista vuelve a como estaba" 'grep -q "se deja como estaba" "$W/o" && [ "$(grep -c . "$CROSS_SITE_ALLOW")" = 2 ]'
cross_site_command quitar erp.ejemplo-empresa.com > /dev/null
check "Linux: quitar" '[ "$(cat "$CROSS_SITE_ALLOW")" = "*.grupo.example" ] && cross_site_command quitar erp.ejemplo-empresa.com | grep -q "no estaba"'
DRY=1 cross_site_command permitir otra.example > "$W/o"
check "Linux: en simulacion, no se escribe nada" 'grep -q "simulacion" "$W/o" && ! grep -q otra "$CROSS_SITE_ALLOW"'
# --- Linux: la ventana ---
check "Linux: Añadir… y Quitar en Seguridad entre webs" 'grep -qF "b.connect(\"clicked\", lambda *_: self.on_cross_site_allow())" "$SRC" && grep -qF "self.run_task(\"Permitiendo %s\" % dom, [\"barrera-web\", \"permitir\", dom]" "$SRC" && grep -qF "[\"barrera-web\", \"quitar\", dom]" "$SRC"'
check "Linux: el Apache de Docker, con las webs permitidas" 'grep -A3 "^function docker_web_security() {" "$SRC" | grep -qF "text=\$(cross_site_fill \"\$text\")"'
# Los espacios de trabajo de VS Code, con las funciones de la ventana
mkdir -p "$W/ws" "$W/htdocs/tienda" "$W/htdocs/blog" "$W/htdocs/nueva"
printf '{\n\t// la tienda\n\t"folders": [\n\t\t{ "path": "../htdocs/tienda", }, /* y */\n\t],\n\t"settings": {"x": "//no"},\n}\n' > "$W/ws/Mi tienda.code-workspace"
printf '{"folders":[{"path":"%s"}]}\n' "$W/htdocs/blog" > "$W/ws/blog.code-workspace"
awk '/cat <<.LVM_GUI_PY.$/{f=1;next} /^LVM_GUI_PY$/{f=0} f' "$SRC" > "$W/gui.py"
res=$(python3 -I - "$W/gui.py" "$W" << 'PY'
import json, os, re, sys
t = open(sys.argv[1], encoding="utf-8").read()
W = sys.argv[2]
a, b = t.index("VSCODE_WS_FILE ="), t.index("def nginx_used")
for sim in (False, True):
    g = {"os": os, "re": re, "json": json, "LOG_DIR": W + "/nexum", "SIMULATE": sim}
    exec(t[a:b], g)
    if sim:
        g["vscode_ws_save"](W + "/ws")
        print("sim|%d" % (g["vscode_workspace"](W + "/htdocs/otra") == W + "/ws/otra.code-workspace"
                          and not os.path.exists(W + "/ws/otra.code-workspace") and not os.path.exists(W + "/nexum/vscode-espacios")))
        continue
    print("sin|%s" % g["vscode_workspace"](W + "/htdocs/tienda"))
    g["vscode_ws_save"](W + "/ws")
    print("dir|%s" % g["vscode_ws_dir"]())
    print("tienda|%s" % g["vscode_workspace"](W + "/htdocs/tienda", create=False))
    print("blog|%s" % g["vscode_workspace"](W + "/htdocs/blog"))
    print("nueva-antes|%s" % g["vscode_workspace"](W + "/htdocs/nueva", create=False))
    n = g["vscode_workspace"](W + "/htdocs/nueva")
    print("nueva|%s|%s" % (n, json.load(open(n))["folders"][0]["path"]))
    g["vscode_ws_save"]("")
    print("quitada|%s" % g["vscode_ws_dir"]())
PY
)
check "Linux (VS Code): sin carpeta elegida, la carpeta del proyecto (nada que buscar)" 'grep -qx "sin|None" <<< "$res"'
check "Linux (VS Code): elegida, se guarda en ~/.nexum/vscode-espacios" 'grep -qx "dir|$W/ws" <<< "$res"'
check "Linux (VS Code): uno que ya lleva su carpeta, aunque se llame distinto (con comentarios y comas de más)" 'grep -qxF "tienda|$W/ws/Mi tienda.code-workspace" <<< "$res"'
check "Linux (VS Code): el de su nombre" 'grep -qxF "blog|$W/ws/blog.code-workspace" <<< "$res"'
check "Linux (VS Code): un proyecto nuevo, sin el suyo: se le crea con su carpeta" 'grep -qx "nueva-antes|None" <<< "$res" && grep -qxF "nueva|$W/ws/nueva.code-workspace|$W/htdocs/nueva" <<< "$res"'
check "Linux (VS Code): Quitar la deja sin elegir" 'grep -qx "quitada|" <<< "$res"'
check "Linux (VS Code): en simulacion no se escribe nada" 'grep -qx "sim|1" <<< "$res"'
check "Linux (VS Code): el botón abre el espacio de trabajo, y Carpetas lo deja elegir" 'grep -qF "ws = had or vscode_workspace(folder)" "$SRC" && grep -qF "app.launch([Gio.File.new_for_path(target)], ctx)" "$SRC" && grep -qF "        self.vscode_ws_row(lb)" "$SRC"'
exit $fail
