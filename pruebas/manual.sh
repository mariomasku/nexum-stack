#!/bin/bash
# El manual dentro del programa (Linux y Mac 1.57.10): va al final del script, después del exit, en base64;
# «manual» lo saca a ~/.lvm-instalador/ayuda (solo si ha cambiado) y abre abrir.html, que lleva al capítulo
# con el sistema ya elegido. «Ayuda» en el menú ☰ abre el capítulo de la pestaña. Todo en carpetas temporales.
# Uso: manual.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd) ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$HERE/comun.sh"
grep -q '^function manual_command() {' "$SRC" || { echo "  ok    (sin el manual dentro)"; exit 0; }
SO=linux; grep -q "^let ERROR_LOG = " "$SRC" && SO=mac
W=$(mktemp -d "$TMPBASE/w-manual.XXXX") || exit 1
trap 'rm -rf "${W:?}"' EXIT

check "el manual va al final, después del exit, en un heredoc" '[ "$(tail -n1 "$SRC")" = NEXUM_MANUAL ] && grep -qx ": <<'"'"'NEXUM_MANUAL'"'"'" "$SRC" && [ "$(grep -B1 -x ": <<'"'"'NEXUM_MANUAL'"'"'" "$SRC" | head -1)" = exit ]'
# (la función, con el script como SELF: el del Mac no se puede ejecutar entero aquí)
eval "$(awk '/^MANUAL_PY=/{p=1} p{print} p && /^'"'"'$/{exit}' "$SRC")"
extract "$SRC" manual_command || exit 1
function man() { local h=$1; shift; HOME=$h LOG_DIR=$h/.lvm-instalador SELF=${MAN_SELF:-$SRC} MANUAL_SO=$SO manual_command "$@"; }
H=$W/h1; mkdir -p "$H"
out=$(man "$H" --ruta limpieza 2>&1); rc=$?
A=$H/.lvm-instalador/ayuda
check "manual --ruta: lo saca y dice qué abrir" '[ $rc -eq 0 ] && [ "$(tail -n1 <<< "$out")" = "$A/abrir.html" ] && [ -f "$A/index.html" ] && [ -f "$A/manual.js" ] && [ -f "$A/estilo.css" ] && [ -f "$A/img/nexum.png" ] && [ -f "$A/fuentes/Goldman-Regular.ttf" ]'
check "lo sacado es el manual de ayuda/" 'cmp -s "$A/index.html" "$ROOT/ayuda/index.html" && cmp -s "$A/manual.js" "$ROOT/ayuda/manual.js"'
check "con las capturas de Linux (en el Mac, las de Linux que aún no tienen la suya)" '[ "$(ls "$A/img/linux" | wc -l)" -ge 20 ]'
check "abrir.html lleva al capítulo, con el sistema elegido" 'grep -qF "url=index.html?so=$SO#limpieza" "$A/abrir.html" && grep -qF "location.replace(\"index.html?so=$SO#limpieza\")" "$A/abrir.html"'
check "solo tuyo: la carpeta y lo de dentro" '[ "$(stat -c %a "$A")" = 700 ] && [ "$(stat -c %a "$A/index.html")" = 600 ]'
touch -d "2020-01-01" "$A/index.html"
man "$H" --ruta proyectos > /dev/null 2>&1
check "si no ha cambiado, no se vuelve a sacar" '[ "$(stat -c %Y "$A/index.html")" = "$(date -d 2020-01-01 +%s)" ] && grep -qF "#proyectos" "$A/abrir.html"'
echo "viejo" > "$A/.huella"; echo "x" > "$A/sobra.txt"
man "$H" --ruta > /dev/null 2>&1
check "si ha cambiado, se cambia entero (sin lo que sobraba) y sin capítulo, al principio" '[ ! -e "$A/sobra.txt" ] && cmp -s "$A/index.html" "$ROOT/ayuda/index.html" && grep -qF "#inicio" "$A/abrir.html" && [ -z "$(ls -A "$H/.lvm-instalador" | grep "^\.ayuda")" ]'
BAD='../x"><script>'
out=$(man "$H" --ruta "$BAD" 2>&1)
check "un capítulo raro no entra en abrir.html" 'grep -q "Capitulo no valido" <<< "$out" && grep -qF "#inicio" "$A/abrir.html" && ! grep -qF "script>\"" "$A/abrir.html"'
# Un manual con una ruta que se sale de su carpeta: no se saca nada
python3 -I - "$W/malo.sh" << 'PY'
import base64, io, sys, tarfile
buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode="w") as t:
    data = b"fuera"
    i = tarfile.TarInfo("../fuera.txt"); i.size = len(data); t.addfile(i, io.BytesIO(data))
b = base64.b64encode(buf.getvalue()).decode()
open(sys.argv[1], "w").write("exit\n: <<'NEXUM_MANUAL'\n" + b + "\nNEXUM_MANUAL\n")
PY
H2=$W/h2; mkdir -p "$H2/.lvm-instalador"
MAN_SELF=$W/malo.sh man "$H2" --ruta > /dev/null 2>&1; rc=$?
check "un manual que se sale de su carpeta: falla y no deja nada" '[ $rc -ne 0 ] && [ ! -e "$H2/.lvm-instalador/fuera.txt" ] && [ ! -e "$H2/fuera.txt" ] && [ ! -e "$H2/.lvm-instalador/ayuda" ]'
H3=$W/h3; mkdir -p "$H3/.lvm-instalador" "$W/otra"; ln -s "$W/otra" "$H3/.lvm-instalador/ayuda"
man "$H3" --ruta > /dev/null 2>&1; rc=$?
check "si ~/.lvm-instalador/ayuda es un enlace, no se toca" '[ $rc -ne 0 ] && [ -L "$H3/.lvm-instalador/ayuda" ] && [ -z "$(ls -A "$W/otra")" ]'
if [ $SO = linux ]; then
    H4=$W/h4; mkdir -p "$H4"
    out=$(HOME=$H4 LVM_PRUEBA=$W/p bash "$SRC" manual --ruta bbdd 2>&1)
    check "el script entero: lvm-instalador manual --ruta" '[ "$(tail -n1 <<< "$out")" = "$H4/.lvm-instalador/ayuda/abrir.html" ] && grep -qF "#bbdd" "$H4/.lvm-instalador/ayuda/abrir.html"'
fi
# La ventana: «Ayuda» en el menú ☰ y cada capítulo, uno que existe en el manual
if [ $SO = mac ]; then
    check "Mac: «Ayuda» en el menú ☰, con manual --ruta" 'grep -qF "item(\"Ayuda\", \"questionmark.circle\") { model.showHelp() }" "$SRC" && grep -qF "runQuick([\"manual\", \"--ruta\", chapter])" "$SRC"'
    ids=$(grep -A8 "func showHelp() {" "$SRC" | grep -oE ': "[a-z-]+"' | tr -d ':" ' | sort -u)
else
    check "Linux: «Ayuda» en el menú ☰, con manual --ruta" 'grep -qF "[(\"Ayuda\", \"help-browser-symbolic\", lambda: self.on_help())," "$SRC" && grep -qF "run_quick([\"manual\", \"--ruta\", chapter], opened)" "$SRC"'
    ids=$(sed -n '/HELP_TABS = {/,/^ *def on_help/p' "$SRC" | grep -oE ': "[a-z-]+"' | tr -d ':" ' | sort -u)
fi
missing=""
for id in $ids ventana; do grep -qF "id=\"$id\"" "$ROOT/ayuda/index.html" || missing+=" $id"; done
check "cada pestaña y apartado lleva a un capítulo que existe en el manual${missing:+ (faltan:$missing)}" '[ -n "$ids" ] && [ -z "$missing" ]'
exit $fail
