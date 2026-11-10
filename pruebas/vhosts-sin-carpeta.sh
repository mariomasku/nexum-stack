#!/bin/bash
# Vhosts sin carpeta (Linux y Mac 1.57.12): los vhosts de un proyecto de htdocs cuya carpeta ya no existe (Apache
# avisa de cada uno al arrancar) salen en los avisos y se quitan con vhosts-sin-carpeta quitar. Los de localhost,
# los que llevan fuera de htdocs y los de carpetas que existen no se tocan. Todo en carpetas temporales.
# Uso: vhosts-sin-carpeta.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q '^function vhosts_orphans() {' "$SRC" || { echo "  ok    (sin vhosts-sin-carpeta)"; exit 0; }
W=$(mktemp -d "$TMPBASE/w-vhosts.XXXX") || exit 1
trap 'rm -rf "${W:?}"' EXIT
mkdir -p "$W/htdocs/panaderia-luna" "$W/log"
cat > "$W/vhosts.conf" << 'CONF'
# Vhosts de prueba
<VirtualHost *:80>
    DocumentRoot "/opt/lampp/htdocs"
    ServerName localhost
</VirtualHost>

<VirtualHost *:80>
    DocumentRoot "/opt/lampp/htdocs/panaderia-luna"
    ServerName panaderia-luna.test
</VirtualHost>

<VirtualHost *:80>
    DocumentRoot "/opt/lampp/htdocs/moda-verde"
    ServerName modaverde.example
    ServerAlias www.modaverde.example
</VirtualHost>

<VirtualHost *:443>
    DocumentRoot "/opt/lampp/htdocs/moda-verde/public"
    ServerName modaverde.example
    SSLEngine on
</VirtualHost>

<VirtualHost *:80>
    DocumentRoot "/var/www/otra-web"
    ServerName otra.example
</VirtualHost>
CONF
cp "$W/vhosts.conf" "$W/original.conf"
eval "$(awk '/^VHOSTS_ORPHANS_PY=/{p=1} p{print} p && /^'"'"'$/{exit}' "$SRC")"
out=$(python3 -I -c "$VHOSTS_ORPHANS_PY" "$W/vhosts.conf" "$W/htdocs" lista)
check "lista: solo la carpeta que falta, con sus dominios (sin repetir)" '[ "$out" = "W|moda-verde|modaverde.example www.modaverde.example" ]'
python3 -I -c "$VHOSTS_ORPHANS_PY" "$W/vhosts.conf" "$W/htdocs" quitar "$W/copia.conf"
check "quitar: sin sus dos vhosts (el de 80 y el de 443)" '! grep -q "moda-verde" "$W/copia.conf" && [ "$(grep -c "<VirtualHost" "$W/copia.conf")" = 3 ]'
check "quitar: localhost, el de una carpeta que existe y el de fuera de htdocs se quedan" 'grep -qx "    DocumentRoot \"/opt/lampp/htdocs\"" "$W/copia.conf" && grep -q "panaderia-luna" "$W/copia.conf" && grep -q "/var/www/otra-web" "$W/copia.conf" && grep -qx "# Vhosts de prueba" "$W/copia.conf"'
check "quitar: solo se quitan líneas, nada se cambia ni se añade" '! diff "$W/original.conf" "$W/copia.conf" | grep -q "^>"'
check "el original, sin tocar" 'cmp -s "$W/vhosts.conf" "$W/original.conf"'
ln -s "$W/htdocs/panaderia-luna" "$W/htdocs/enlace" 2> /dev/null
# La función, con edit_vhosts de mentira (el de verdad pide sudo y recarga Apache)
extract "$SRC" vhosts_orphans || exit 1
function edit_vhosts() { cp "$2" "$W/aplicado.conf"; echo "aplicado"; }
o=$(ACTIVE_VHOSTS=$W/vhosts.conf HTDOCS_DIR=$W/htdocs LOG_DIR=$W/log vhosts_orphans)
check "vhosts-sin-carpeta: los lista y dice cómo quitarlos, sin quitar nada" 'grep -q "moda-verde (modaverde.example www.modaverde.example)" <<< "$o" && grep -q "nexum vhosts-sin-carpeta quitar" <<< "$o" && [ ! -e "$W/aplicado.conf" ]'
o=$(ACTIVE_VHOSTS=$W/vhosts.conf HTDOCS_DIR=$W/htdocs LOG_DIR=$W/log vhosts_orphans quitar)
check "vhosts-sin-carpeta quitar: aplica la copia sin ellos (con edit_vhosts --aplicar) y no deja la copia" 'grep -q aplicado <<< "$o" && cmp -s "$W/aplicado.conf" "$W/copia.conf" && [ -z "$(ls -A "$W/log")" ]'
mkdir -p "$W/htdocs/moda-verde"; rm -f "$W/aplicado.conf"
o=$(ACTIVE_VHOSTS=$W/vhosts.conf HTDOCS_DIR=$W/htdocs LOG_DIR=$W/log vhosts_orphans quitar)
check "con todas las carpetas, nada que quitar" 'grep -q "Todos los vhosts de proyectos tienen su carpeta" <<< "$o" && [ ! -e "$W/aplicado.conf" ]'
check "en los avisos de la ventana (gui-datos: W|carpeta|dominios)" 'grep -qF "python3 -I -c \"\$VHOSTS_ORPHANS_PY\" \"\$vh\" \"\$HTDOCS_DIR\" lista" "$SRC"'
check "quitar pide la contraseña en las tareas de la ventana; listar, no" 'grep -qF "vhosts-sin-carpeta) [ \"\$2\" == quitar ] && { sudo_first || exit 130; } ;;" "$SRC"'
if grep -q "^let ERROR_LOG = " "$SRC"; then
    check "Mac: el aviso con «Quitarlos»" 'grep -qF "Card(\"Hay vhosts de carpetas que ya no existen\"," "$SRC" && grep -qF "runTask(\"Quitando vhosts de carpetas que ya no existen\", [\"vhosts-sin-carpeta\", \"quitar\"]," "$SRC"'
else
    check "Linux: el aviso con «Quitarlos»" 'grep -qF "box, lb = group(\"Hay vhosts de carpetas que ya no existen\"," "$SRC" && grep -qF "[\"vhosts-sin-carpeta\", \"quitar\"]," "$SRC"'
fi
exit $fail
