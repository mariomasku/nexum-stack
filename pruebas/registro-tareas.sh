#!/bin/bash
# Configuración, General y el registro de tareas: cada tarea de la ventana guarda el suyo en
# ~/.lvm-instalador/tareas (solo tuyo, 600), con la orden de nexum y su salida, sin secretos, y se quedan las
# 200 últimas. Uso: registro-tareas.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/lvm-tareas.XXXXXX")
trap 'rm -rf "$W"' EXIT
if grep -q "^let ERROR_LOG = " "$SRC"; then
    check "Mac: General, el primero, con errores, tareas, parches y programa" 'grep -qF "(\"general\", \"General\", \"slider.horizontal.3\")," "$SRC" && ! grep -qF "(\"parches\", \"Parches nuevos\"" "$SRC" && ! grep -qF "(\"errores\", \"Registro de errores\"" "$SRC" && ! grep -qF "(\"programa\", \"Programa\"" "$SRC" && grep -qF "generalBlock(\"Registro de tareas\"" "$SRC" && grep -qF "@Published var toolsSection = \"general\"" "$SRC"'
    check "Mac: Ayuda en General lleva a su capítulo" 'grep -qF "let sections = [\"general\": \"general\"," "$SRC"'
    check "Mac: cada tarea guarda su registro al empezar y al acabar (con la orden y sin secretos)" 'grep -qF "saveLog(\"En marcha" "$SRC" && grep -qF "saveLog(cancelled ? \"Cancelada\"" "$SRC" && grep -qF "taskLogWrite(path, taskLogRedact(all, env: env))" "$SRC" && grep -qF "O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, mode_t(0o600)" "$SRC"'
    check "Mac: se quedan las 200 últimas" 'grep -qx "let TASKS_KEEP = 200" "$SRC" && grep -qF "func taskLogPrune()" "$SRC"'
    exit $fail
fi
check "Linux: General, el primero, con errores, tareas, parches y programa" 'grep -qF "TOOLS_SECTIONS = [(\"General\", \"General\"," "$SRC" && grep -qF "GENERAL_PARTS = [\"Registro de errores\", \"Registro de tareas\", \"Parches nuevos\", \"Programa\"]" "$SRC" && ! grep -qF "(\"Parches nuevos\", \"Parches nuevos\"," "$SRC"'
check "Linux: Ayuda en General lleva a su capítulo; un bloque de General abre General" 'grep -qF "HELP_SECTIONS = {\"General\": \"general\"," "$SRC" && grep -qF "part = section if section in self.GENERAL_PARTS else None" "$SRC"'
check "Linux: Apariencia, los apartados del menú lateral en dos columnas" 'grep -qF "for chunk in (names[:half], names[half:]):" "$SRC"'

# Las funciones del registro, de la ventana del script
python3 -I - "$SRC" "$W" <<'PY' > "$W/o" 2>&1
import os, re, shlex, stat, sys, time
src = open(sys.argv[1], encoding="utf-8").read()
gui = src[src.index("cat <<'LVM_GUI_PY'"):]
code = gui[gui.index("# Registro de tareas: cada tarea de la ventana"):gui.index("class Task:")]
home = sys.argv[2]
DEMO, SIMULATE, LOG_DIR = "", False, os.path.join(home, ".lvm-instalador")
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
check "ventana.log en modo de añadir (Limpieza lo vacía con la ventana abierta)" 'grep -qF "exec 2>> \"\$LOG_DIR/ventana.log\"" "$SRC"'
exit $fail
