#!/bin/bash
# Configuración, General y el registro de tareas: cada tarea de la ventana guarda el suyo en
# ~/.nexum/tareas (solo tuyo, 600), con la orden de nexum y su salida, sin secretos, y se quedan las
# 200 últimas. Uso: registro-tareas.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/lvm-tareas.XXXXXX")
trap 'rm -rf "$W"' EXIT
if grep -q "^let ERROR_LOG = " "$SRC"; then
    check "Mac: General, el primero, con errores, parches y programa; el registro de tareas, aparte en Sistema" 'grep -qF "(\"general\", \"General\", \"slider.horizontal.3\")," "$SRC" && grep -A1 -F "(\"general\", \"General\", \"slider.horizontal.3\")," "$SRC" | grep -qF "(\"tareas\", \"Registro de tareas\", \"clock.arrow.circlepath\")," && ! grep -qF "(\"parches\", \"Parches nuevos\"" "$SRC" && ! grep -qF "(\"errores\", \"Registro de errores\"" "$SRC" && ! grep -qF "(\"programa\", \"Programa\"" "$SRC" && ! grep -qF "generalBlock(\"Registro de tareas\"" "$SRC" && grep -qF "TaskLogsCard()" "$SRC" && grep -qF "let CONFIG_SYSTEM: Set<String> = [\"general\", \"tareas\", \"apariencia\", \"limpieza\", \"oficial\", \"info\"]" "$SRC" && grep -qF "@Published var toolsSection = \"general\"" "$SRC"'
    check "Mac: Ayuda en General y en el Registro de tareas lleva a su capítulo" 'grep -qF "let sections = [\"general\": \"general\", \"tareas\": \"tareas\"," "$SRC"'
    check "Mac: cada tarea guarda su registro al empezar y al acabar (con la orden y sin secretos)" 'grep -qF "saveLog(TASK_RUNNING)" "$SRC" && grep -qF "saveLog(cancelled ? \"Cancelada\"" "$SRC" && grep -qF "taskLogWrite(path, taskLogRedact(all, env: env))" "$SRC" && grep -qF "O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, mode_t(0o600)" "$SRC"'
    check "Mac: con la tarea en marcha, su registro lleva la consola (cada 3 s) y «Ver» se actualiza solo" 'grep -qF "let TASK_LOG_LIVE: TimeInterval = 3" "$SRC" && grep -qF "saveLog(TASK_RUNNING, log)" "$SRC" && grep -qF "        saveLive()" "$SRC" && grep -qF "RunLoop.main.add(t, forMode: .common)" "$SRC" && grep -qF "NSPasteboard.general.setString(shown, forType: .string)" "$SRC"'
    check "Mac: se quedan las 200 últimas" 'grep -qx "let TASKS_KEEP = 200" "$SRC" && grep -qF "func taskLogPrune()" "$SRC"'
    exit $fail
fi
check "Linux: General, el primero, con errores, parches y programa; el registro de tareas, aparte en Sistema" 'grep -qF "TOOLS_SECTIONS = [(\"General\", \"General\"," "$SRC" && grep -qF "GENERAL_PARTS = [\"Registro de errores\", \"Parches nuevos\", \"Programa\"]" "$SRC" && ! grep -qF "(\"Parches nuevos\", \"Parches nuevos\"," "$SRC" && grep -qF "(\"Registro de tareas\", \"Registro de tareas\"," "$SRC" && grep -qF "CONFIG_SYSTEM = (\"General\", \"Registro de tareas\"," "$SRC"'
check "Linux: Ayuda en General lleva a su capítulo; un bloque de General abre General" 'grep -qF "HELP_SECTIONS = {\"General\": \"general\"," "$SRC" && grep -qF "part = section if section in self.GENERAL_PARTS else None" "$SRC"'
check "Linux: con la tarea en marcha, su registro lleva la consola (cada 3 s) y «Ver» se actualiza solo" 'grep -qx "TASK_LOG_LIVE = 3" "$SRC" && grep -qF "self.save_log(TASK_RUNNING, text)" "$SRC" && grep -qF "        self.save_live()" "$SRC" && grep -qF "GLib.timeout_add_seconds(TASK_LOG_LIVE, refresh)" "$SRC"'
check "Linux: Apariencia, los apartados del menú lateral en tres columnas (1.60.0)" 'grep -qF "for chunk in (names[:per], names[per:2 * per], names[2 * per:]):" "$SRC"'
check "Linux: la versión de PHP, pulsable: las instaladas en abanico para cambiar de versión (1.60.0)" 'grep -qF "self.php_btn.connect(\"clicked\", lambda *_: self.nv_versions_fan())" "$SRC" && grep -qF "self.on_activate_version(None, f)" "$SRC" && grep -q "@keyframes nv-abanico-arriba" "$SRC"'
check "Linux: en los cuadrados, PMA e Imágenes si el nombre no cabe (1.60.0)" 'grep -qF "SQUARE_SHORT_NAMES = {\"phpMyAdmin\": \"PMA\", \"Imágenes de producción\": \"Imágenes\"}" "$SRC" && grep -qF "square_name(name, TOP_VISOR_SIDE - 6, 9, \"nv-visor-nombre\")" "$SRC"'
check "Linux: iconos en color: los de acción por su función y los demás con los colores de Nexum (1.60.0)" 'grep -qF "def tint_icon(img, name):" "$SRC" && grep -qF "if not isinstance(name, str) or not look_conf()[\"color\"]:" "$SRC" && grep -q "^.nv-tinta-nexum-4 { color: #F20093; }" "$SRC" && grep -qF "tint_icon(icon(icon_name), icon_name)" "$SRC"'
check "Linux: Clonar, tan ancho como Traer cambios (1.60.0)" 'grep -qF "self.repo_btn_group = Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL)" "$SRC" && grep -qF "group.add_widget(b)" "$SRC"'
check "Linux: los diálogos, más pequeños que la ventana de Nexum y dentro de la pantalla (1.60.0)" 'grep -qF "GObject.add_emission_hook(Gtk.Widget, \"realize\", dialog_hook)" "$SRC" && grep -qF "dlg.set_geometry_hints(None, geom, Gdk.WindowHints.MAX_SIZE)" "$SRC" && grep -q "^DIALOG_MARGIN = 80$" "$SRC"'
check "Linux: Mailpit no se mira en cada lectura: se arranca al pulsar Correo (1.60.0)" '! sed -n "/^function gui_data()/,/^}/p" "$SRC" | grep -q "mailpit_sync" && grep -qF "run_quick([\"correo\", \"arrancar\"], started)" "$SRC" && grep -q "        arrancar) mailpit_sync --suave ;;" "$SRC"'
check "Linux: arranque al momento con lo último leído, guardado en el hilo de la orden y solo si cambia (1.60.0)" 'grep -qF "DATA_CACHED = (\"gui-datos\", \"gui-hosts\", \"gui-servicios\", \"gui-proyectos\", \"gui-docker\")" "$SRC" && grep -qF "data_cache_write(args[0], out)" "$SRC" && grep -qF "if fh.read(4 * 1024 * 1024 + 1) == out:" "$SRC" && grep -qF "out = data_cache_read(cmd)" "$SRC" && grep -qF "if SIMULATE or DEMO or cmd not in DATA_CACHED" "$SRC"'
check "Linux: sin esperas al cambiar de pestaña ni al pulsar (sin fundidos ni transiciones; desplegables rápidos) (1.60.0)" '! grep -q "StackTransitionType.CROSSFADE" "$SRC" && grep -qF "* { transition: none; }" "$SRC" && grep -q "^REVEAL_MS = 90$" "$SRC" && grep -q "animation: nv-latido" "$SRC"'

# Las funciones del registro, de la ventana del script
python3 -I - "$SRC" "$W" <<'PY' > "$W/o" 2>&1
import os, re, shlex, stat, sys, time
src = open(sys.argv[1], encoding="utf-8").read()
gui = src[src.index("cat <<'LVM_GUI_PY'"):]
code = gui[gui.index("# Registro de tareas: cada tarea de la ventana"):gui.index("class Task:")]
home = sys.argv[2]
DEMO, SIMULATE, LOG_DIR = "", False, os.path.join(home, ".nexum")
exec(code)
print("DIR=" + str(task_log_dir() == TASKS_DIR))
print("MODO_DIR=%o" % stat.S_IMODE(os.stat(TASKS_DIR).st_mode))
print("ORDEN=" + task_log_command(["copiar-bd", "wp_panaderia_luna", "8.3", "con espacio"]))
text = ("Orden: nexum x\nVariables: MYSQL_PWD=" + HIDDEN + "\n" + TASK_LOG_SEP + "\nconectando con s3cr3t-pw\n"
        "Contraseña para entrar: Abc123xyz\ntoken ghp_0123456789abcdefghijABCDEFGHIJ\nmysql://root:pw9@localhost/x\n")
body = task_log_redact(text, {"MYSQL_PWD": "s3cr3t-pw", "LVM_X": "1"})
for s in ("s3cr3t-pw", "Abc123xyz", "ghp_0123456789", "pw9@"):
    print("SECRETO=%s %s" % (s, s in body))
p = os.path.join(TASKS_DIR, "20261110-120000-1000.txt")
task_log_write(p, "Tarea: Copiando wp_panaderia_luna\nResultado: Terminada bien\n" + body)
print("MODO=%o" % stat.S_IMODE(os.stat(p).st_mode))
for i in range(205):
    open(os.path.join(TASKS_DIR, "20261111-%06d-1.txt" % i), "w").write("Tarea: t%d\nResultado: Ha fallado (código 1)\n" % i)
os.symlink("/etc/passwd", os.path.join(TASKS_DIR, "20261112-000000-1.txt"))
task_log_prune()
names = sorted(os.listdir(TASKS_DIR))
print("QUEDAN=%d" % len(names))
print("BORRADA_LA_VIEJA=%s" % (not os.path.exists(p)))
logs = task_logs()
print("PRIMERA=" + logs[0]["title"] + " " + logs[0]["state"])
print("ENLACE=" + str(task_log_read(os.path.join(TASKS_DIR, "20261112-000000-1.txt"))))
PY
check "la carpeta, solo tuya (700)" 'grep -qx "DIR=True" "$W/o" && grep -qx "MODO_DIR=700" "$W/o"'
check "la orden, como en la terminal" 'grep -qxF "ORDEN=nexum copiar-bd wp_panaderia_luna 8.3 '"'"'con espacio'"'"'" "$W/o"'
check "sin secretos: ni el valor de MYSQL_PWD, ni contraseñas, ni tokens, ni la de una dirección" '[ "$(grep -c "^SECRETO=.* False$" "$W/o")" -eq 4 ]'
check "cada registro, solo tuyo (600)" 'grep -qx "MODO=600" "$W/o"'
check "se quedan las 200 últimas (las viejas se borran)" 'grep -qx "QUEDAN=200" "$W/o" && grep -qx "BORRADA_LA_VIEJA=True" "$W/o"'
check "la lista, la más nueva primero, con cómo acabó; un enlace no se lee" 'grep -qx "PRIMERA=t204 error" "$W/o" && grep -qx "ENLACE=None" "$W/o"' || cat "$W/o"
check "Limpieza: los registros del programa incluyen el registro de tareas" 'grep -qF "echo \"registros|\$LOG_DIR|ficheros|tareas|*.txt|uso\"" "$SRC"'
check "Limpieza: y las listas de ficheros de Actualizar proyecto, que van con los registros y no en las copias (1.57.50)" 'grep -qF "echo \"registros|\$LOG_DIR|ficheros|listas|*.txt|uso\"" "$SRC" && grep -qF "\"\$LOG_DIR/listas/\$folder-\$stamp\"; then" "$SRC" && ! grep -qF "COPIES_DIR/\$folder-registro" "$SRC"'
check "ventana.log en modo de añadir (Limpieza lo vacía con la ventana abierta)" 'grep -qF "exec 2>> \"\$LOG_DIR/ventana.log\"" "$SRC"'
exit $fail
