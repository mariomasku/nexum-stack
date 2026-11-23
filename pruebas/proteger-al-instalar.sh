#!/bin/bash
# Una version de PHP recien instalada o rehecha queda protegida al acabar (1.57.42): antes se quedaba
# «sin proteger» (el httpd.conf original de Apache, el correo de pruebas, el https) hasta Protegerlas, y la
# ventana preguntaba tras cada actualizacion de Nexum. Uso: proteger-al-instalar.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
body=$(awk '/^function install_stack\(\) \{/,/^}/' "$SRC")
if grep -q "^let ERROR_LOG = " "$SRC"; then
    check "Mac: install_stack protege la version antes de comprobarla" 'grep -B6 "        echo \"Comprobando la configuracion...\"" <<< "$body" | grep -qF "        secure_version \"\$root\""'
else
    check "Linux: install_stack protege la version antes de comprobarla y arrancarla" 'grep -B6 "    echo \"Comprobando la configuracion...\"" <<< "$body" | grep -qF "    secure_lampp \"\$target\""'
fi
check "si no se puede, lo dice (sin cortar la instalacion)" 'grep -qF "Aviso: no se ha podido proteger del todo" <<< "$body" && ! grep -qE "secure_(lampp|version) \"\\\$(target|root)\" \|\| stack_fail" <<< "$body"'
exit $fail
