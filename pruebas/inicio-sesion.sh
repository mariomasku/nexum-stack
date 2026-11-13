#!/bin/bash
# Configuración → General → Programa, «Abrir al iniciar sesión» (1.57.15). Linux: el acceso de inicio de la
# sesión (~/.config/autostart/nexum.desktop) abre la ventana con --al-iniciar y, con el icono junto al reloj,
# se queda en él. Solo se toca el nuestro (con su marca y sin enlaces). Las funciones de la ventana se
# ejecutan de verdad con XDG_CONFIG_HOME en una carpeta temporal. Uso: inicio-sesion.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q "def nv_tray_setup" "$SRC" || { echo "  ok    (el script del Mac: sus pruebas van en bandeja.sh)"; exit 0; }
W=$(mktemp -d "$TMPBASE/w-inicio.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT

check "el interruptor, en Programa, junto al del icono" 'grep -qF "row = ActionRow(\"Abrir al iniciar sesión\"," "$SRC" && grep -qF "sw.connect(\"notify::active\", self.nv_autostart_toggle)" "$SRC"'
check "en simulación no escribe nada" 'grep -A6 "    def nv_autostart_toggle(self, sw, _p):" "$SRC" | grep -qF "if SIMULATE:"'
check "abierta al iniciar sesión, con el icono se esconde" 'grep -qF "if START_HIDDEN and self.tray is not None:" "$SRC" && grep -qF "START_HIDDEN = os.environ.get(\"LVM_AL_INICIAR\") == \"1\"" "$SRC"'
check "nexum ventana --al-iniciar pasa LVM_AL_INICIAR a la ventana" 'grep -qF "ventana|gui|ventana-nueva) [ \"\$2\" == --al-iniciar ] && export LVM_AL_INICIAR=1; gui_open ;;" "$SRC"'

mkdir -p "$W/cfg"
XDG_CONFIG_HOME=$W/cfg python3 -I - "$SRC" "$W" > "$W/o" 2>&1 <<'PY'
import os, re, stat, sys
src, w = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
code = []
for name in ("AUTOSTART_FILE", "AUTOSTART_MARK"):
    code.append(re.search(r"(?ms)^%s = .*?\n(?=\S)" % name, text).group(0))
for name in ("autostart_read", "autostart_on", "autostart_text", "autostart_set"):
    code.append(re.search(r"(?ms)^def %s\(.*?\n(?=\S)" % name, text).group(0))
g = {"os": os, "re": re, "stat": stat}
exec("".join(code), g)
f = g["AUTOSTART_FILE"]
print("RUTA=%s" % (f == os.path.join(w, "cfg", "autostart", "nexum.desktop")))
print("APAGADO=%s" % g["autostart_on"]())
print("ENCENDER=%s" % g["autostart_set"](True, "/opt/nexum/nexum.sh"))
print("ENCENDIDO=%s" % g["autostart_on"]())
body = open(f).read()
print("EXEC=%s" % ("Exec=/opt/nexum/nexum.sh ventana --al-iniciar" in body.splitlines()))
print("MODO=%o" % (os.stat(f).st_mode & 0o777))
print("ESPACIOS=%s" % ('Exec="/home/a b/n$x.sh" ventana' in g["autostart_text"]("/home/a b/n$x.sh")
                       .replace("\\$", "$")))
# Desmarcado en «Aplicaciones al inicio»: apagado, aunque sea nuestro
open(f, "a").write("X-GNOME-Autostart-enabled=false\n")
print("DESMARCADO=%s" % g["autostart_on"]())
print("APAGAR=%s" % g["autostart_set"](False, "/opt/nexum/nexum.sh"))
print("BORRADO=%s" % (not os.path.lexists(f)))
# Uno que no es nuestro: ni se enciende encima ni se borra
open(f, "w").write("[Desktop Entry]\nExec=otro\n")
print("AJENO_ENCENDER=%s" % (g["autostart_set"](True, "/opt/nexum/nexum.sh") is not None and "otro" in open(f).read()))
print("AJENO_APAGAR=%s" % (g["autostart_set"](False, "/opt/nexum/nexum.sh") is not None and os.path.exists(f)))
os.unlink(f)
# Un enlace (aunque apunte a uno nuestro) no se sigue ni se borra
real = os.path.join(w, "nuestro.desktop")
open(real, "w").write(g["autostart_text"]("/opt/nexum/nexum.sh"))
os.symlink(real, f)
print("ENLACE_ON=%s" % g["autostart_on"]())
print("ENLACE_APAGAR=%s" % (g["autostart_set"](False, "/x") is not None and os.path.islink(f) and os.path.exists(real)))
PY
check "el acceso va en XDG_CONFIG_HOME/autostart/nexum.desktop; sin él, apagado" 'grep -qx "RUTA=True" "$W/o" && grep -qx "APAGADO=False" "$W/o"' || cat "$W/o"
check "encender: lo escribe (644) y abre la ventana con --al-iniciar" 'grep -qx "ENCENDER=None" "$W/o" && grep -qx "ENCENDIDO=True" "$W/o" && grep -qx "EXEC=True" "$W/o" && grep -qx "MODO=644" "$W/o"'
check "una ruta con espacios va entre comillas" 'grep -qx "ESPACIOS=True" "$W/o"'
check "desmarcado en «Aplicaciones al inicio»: apagado" 'grep -qx "DESMARCADO=False" "$W/o"'
check "apagar: borra el nuestro" 'grep -qx "APAGAR=None" "$W/o" && grep -qx "BORRADO=True" "$W/o"'
check "uno que no es nuestro no se cambia ni se borra" 'grep -qx "AJENO_ENCENDER=True" "$W/o" && grep -qx "AJENO_APAGAR=True" "$W/o"'
check "un enlace no se sigue ni se borra" 'grep -qx "ENLACE_ON=False" "$W/o" && grep -qx "ENLACE_APAGAR=True" "$W/o"'
exit $fail
