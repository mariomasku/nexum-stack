#!/bin/bash
# Pruebas del entorno de las tareas de la ventana (Linux): ni funciones exportadas, ni SHELLOPTS+PS4,
# ni variables de prueba. Uso: entorno.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
out=$(env 'BASH_FUNC_sudo%%=() { echo PWNED; }' SHELLOPTS=xtrace 'PS4=$(echo PWNED2)' LVM_HTDOCS=/etc LD_PRELOAD=/x.so \
    python3 -I - "$SRC" <<'PY'
import os, re, sys, subprocess
src = open(sys.argv[1], encoding="utf-8").read()
gui = src[src.index("cat <<'LVM_GUI_PY'"):]
m = re.search(r"(?ms)^ENV_KEEP = .*?^def script_env\(\*\*extra\):.*?\n    return env\n", gui)
SUDO_MARK = "@@x@@"
exec(m.group(0))
env = script_env()
r = subprocess.run(["/bin/bash", "-c", "type sudo | head -1; echo HT=${LVM_HTDOCS:-no}; echo LD=${LD_PRELOAD:-no}"],
                   env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
print(r.stdout.decode())
PY
)
check "sin funciones exportadas (sudo es el de verdad)" '! grep -q PWNED <<< "$out" && grep -q "sudo is\|sudo es" <<< "$out"'
check "sin SHELLOPTS ni PS4" '! grep -q PWNED2 <<< "$out"'
check "sin variables de prueba ni LD_PRELOAD" 'grep -q "^HT=no$" <<< "$out" && grep -q "^LD=no$" <<< "$out"'
# El script ignora las variables de prueba sin LVM_PRUEBA
v=$(env -u LVM_PRUEBA LVM_HTDOCS=/etc LVM_VHOSTS=/etc/passwd bash -c 'eval "$(sed -n "/^TEST_DIR=/,/^VHOSTS_FILE=/p" "$1")"; echo "$HTDOCS_DIR|$VHOSTS_FILE"' _ "$SRC")
check "sin LVM_PRUEBA, LVM_HTDOCS y LVM_VHOSTS no valen" '[ "$v" = "/opt/htdocs|/opt/config/httpd-vhosts.conf" ]'
exit $fail
