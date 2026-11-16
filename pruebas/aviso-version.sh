#!/bin/bash
# Arrancar o reiniciar la versión activa (1.57.15): el aviso del final dice cuál es, con su PHP
# (lampp-8.4 (PHP 8.4.14) en Linux, XAMPP-8.4 (PHP 8.4.14) en el Mac). Uso: aviso-version.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
if grep -q "LVM_SWIFT" "$SRC"; then
    check "Mac: arrancada o reiniciada, con XAMPP-carpeta y su PHP" 'grep -qF "let name = \"XAMPP-\\(folder)\" + (php.isEmpty ? \"\" : \" (PHP \\(php))\")" "$SRC" && grep -qF "\"arrancar\": \"Versión activa arrancada: \\(name)\", \"reiniciar\": \"Versión activa reiniciada: \\(name)\"" "$SRC"'
    exit $fail
fi
check "Linux: arrancada o reiniciada, con lampp-carpeta y su PHP" 'grep -qF "name = \"lampp-%s\" % folder + (\" (PHP %s)\" % inst[\"php\"] if inst and inst.get(\"php\") else \"\")" "$SRC" && grep -qF "\"arrancar\": \"Versión activa arrancada: %s\" % name, \"reiniciar\": \"Versión activa reiniciada: %s\" % name" "$SRC"'
# (de verdad: el texto con una versión de mentira)
out=$(python3 -I -c '
inst = {"folder": "8.4", "php": "8.4.14"}; folder = "8.4"
name = "lampp-%s" % folder + (" (PHP %s)" % inst["php"] if inst and inst.get("php") else "")
print("Versión activa arrancada: %s" % name)')
check "Linux: el aviso queda «Versión activa arrancada: lampp-8.4 (PHP 8.4.14)»" '[ "$out" == "Versión activa arrancada: lampp-8.4 (PHP 8.4.14)" ]'
exit $fail
