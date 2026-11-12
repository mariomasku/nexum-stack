#!/bin/bash
# La carpeta de los ajustes (Linux y Mac 1.57.14): ~/.nexum. La de antes, ~/.lvm-instalador, se renombra
# sola al arrancar (settings_migrate) y en su sitio queda un enlace relativo a .nexum. Con las dos, con un
# enlace o con un fichero, no se toca nada; cortada a medias, se completa; no con --simular ni en las
# pruebas (y entonces se sigue con la de antes, sin crear una ~/.nexum al lado). Todo con carpetas
# personales temporales: nunca la de verdad.
# Uso: carpeta-nexum.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q '^function settings_migrate() {' "$SRC" || { echo "  ok    (sin la carpeta ~/.nexum)"; exit 0; }
MAC=0; grep -qE '^    BASE_DIR=(/Applications|/Library/Nexum)$' "$SRC" && MAC=1
W=$(mktemp -d "$TMPBASE/w-carpeta.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
# (cada prueba, con su carpeta personal dentro de W: la migracion nunca ve la de verdad)
function casa() {
    H=$W/$1
    case "$H" in "$W"/*) ;; *) echo "carpeta personal fuera de la temporal: $H"; exit 1 ;; esac
    mkdir -p "$H"
}
function migra() { HOME=$H LOG_DIR=$H/.nexum SETTINGS_OLD_DIR=$H/.lvm-instalador settings_migrate; }
function dir_de() { HOME=$H LOG_DIR=$H/.nexum SETTINGS_OLD_DIR=$H/.lvm-instalador settings_dir; }

# --- En el script ---
check "LOG_DIR=\$HOME/.nexum y la de antes, ~/.lvm-instalador" 'grep -qx "LOG_DIR=\"\$HOME/.nexum\"" "$SRC" && grep -qx "SETTINGS_OLD_DIR=\$HOME/.lvm-instalador" "$SRC" && grep -qx "LOG_DIR=\$(settings_dir)" "$SRC"'
check "la migracion, nada mas definir LOG_DIR: no con --simular, en las pruebas ni al pedir la version" 'grep -A1 -x "    --simular|version|--version|-v|acerca|about|novedades|-h|--help|--ayuda|construir-pila) ;;" "$SRC" | grep -qx "    \*) \[ -z \"\${LVM_PRUEBA:-}\" \] && settings_migrate ;;" && [ "$(grep -n -x "LOG_DIR=\"\$HOME/.nexum\"" "$SRC" | cut -d: -f1)" -lt "$(grep -n "&& settings_migrate ;;" "$SRC" | cut -d: -f1)" ]'
first_mkdir=$(grep -n 'mkdir[^|;]*\$LOG_DIR' "$SRC" | head -1 | cut -d: -f1)
migr_line=$(grep -n '&& settings_migrate ;;' "$SRC" | head -1 | cut -d: -f1)
check "antes de que nada cree LOG_DIR" '[ -n "$migr_line" ] && [ -n "$first_mkdir" ] && [ "$migr_line" -lt "$first_mkdir" ]'
check "nada usa ya la ruta escrita (\$HOME/.lvm-instalador/... ni %h/.lvm-instalador)" '! grep -n "\$HOME/\.lvm-instalador/\|%h/\.lvm-instalador" "$SRC" | grep -v "^[0-9]*: *#" | grep -q .'
if [ $MAC -eq 0 ]; then
    unit=$(awk "/^DOCKER_UNIT='/ {p=1} p {print} p && /^'\$/ {exit}" "$SRC")
    got=$(HOME=/home/x LOG_DIR=/home/x/.nexum; eval "$unit"; grep "^ExecStart=" <<< "$DOCKER_UNIT")
    check "docker.service nuevo: ExecStart en ~/.nexum/docker" '[ "$got" = "ExecStart=%h/.nexum/docker/bin/dockerd-rootless" ]'
    check "la ventana de Linux: ~/.nexum, o la de antes si no se ha pasado" 'grep -qx "LOG_DIR = os.path.expanduser(\"~/.nexum\")" "$SRC" && grep -qx "if not os.path.lexists(LOG_DIR) and os.path.isdir(LOG_DIR_OLD) and not os.path.islink(LOG_DIR_OLD):" "$SRC"'
else
    check "la ventana del Mac: la migracion al abrirse (init de la aplicacion, antes de tocar LOG_DIR)" 'grep -A2 -x "    init() {" "$SRC" | grep -qx "        settingsMigrate()" && grep -qx "func settingsMigrate() {" "$SRC" && grep -qx "let SETTINGS_DIR = NSHomeDirectory() + \"/.nexum\"" "$SRC"'
    check "la ventana del Mac: no en simulacion ni en las pruebas" 'grep -qx "    if SIMULATE || !(ProcessInfo.processInfo.environment\[\"LVM_PRUEBA\"\] ?? \"\").isEmpty { return }" "$SRC"'
    check "la ventana del Mac: la misma marca y el mismo aviso que el script" 'grep -qx "SETTINGS_MOVE_MARK=.pasando-a-nexum" "$SRC" && grep -qx "SETTINGS_BOTH_LOG=carpeta-anterior.log" "$SRC" && grep -qF "let mark = new + \"/.pasando-a-nexum\", both = new + \"/carpeta-anterior.log\"" "$SRC"'
fi

# --- settings_migrate ---
extract "$SRC" settings_migrate settings_dir || exit 1
SETTINGS_MOVE_MARK=.pasando-a-nexum SETTINGS_BOTH_LOG=carpeta-anterior.log
casa m1; mkdir -p "$H/.lvm-instalador/docker/web"; echo ajuste > "$H/.lvm-instalador/apariencia"; echo d > "$H/.lvm-instalador/docker/web/x"
ino=$(stat -c %i "$H/.lvm-instalador")
migra
check "migracion: ~/.lvm-instalador pasa a ~/.nexum (la misma carpeta, sin copiar) con lo que tenia" '[ -d "$H/.nexum" ] && [ ! -L "$H/.nexum" ] && [ "$(stat -c %i "$H/.nexum")" = "$ino" ] && [ "$(cat "$H/.nexum/apariencia")" = ajuste ] && [ "$(cat "$H/.nexum/docker/web/x")" = d ]'
check "migracion: ~/.lvm-instalador queda como enlace relativo a .nexum (lo de antes sigue funcionando)" '[ -L "$H/.lvm-instalador" ] && [ "$(readlink "$H/.lvm-instalador")" = .nexum ] && [ "$(cat "$H/.lvm-instalador/docker/web/x")" = d ]'
check "migracion: sin la marca ni el aviso" '[ ! -e "$H/.nexum/.pasando-a-nexum" ] && [ ! -e "$H/.nexum/carpeta-anterior.log" ]'
migra
check "otra vez: nada cambia" '[ "$(readlink "$H/.lvm-instalador")" = .nexum ] && [ "$(cat "$H/.nexum/apariencia")" = ajuste ]'
check "y la carpeta de esta vez es ~/.nexum" '[ "$(dir_de)" = "$H/.nexum" ]'

casa m2; mkdir -p "$H/.lvm-instalador" "$H/.nexum"; echo viejo > "$H/.lvm-instalador/v"; echo nuevo > "$H/.nexum/n"
migra; aviso=$(cat "$H/.nexum/carpeta-anterior.log" 2> /dev/null); sleep 1; migra
check "con las dos: no se toca ninguna" '[ -d "$H/.lvm-instalador" ] && [ ! -L "$H/.lvm-instalador" ] && [ "$(cat "$H/.lvm-instalador/v")" = viejo ] && [ "$(cat "$H/.nexum/n")" = nuevo ] && [ ! -e "$H/.nexum/v" ] && [ ! -e "$H/.lvm-instalador/.pasando-a-nexum" ]'
check "con las dos: se avisa una vez, en el registro (~/.nexum/carpeta-anterior.log)" 'grep -q "no se toca ninguna" <<< "$aviso" && [ "$(cat "$H/.nexum/carpeta-anterior.log")" = "$aviso" ] && [ "$(grep -c . "$H/.nexum/carpeta-anterior.log")" = 1 ]'
check "con las dos: se usa ~/.nexum" '[ "$(dir_de)" = "$H/.nexum" ]'

casa m3; mkdir -p "$W/otra"; echo fuera > "$W/otra/f"; ln -s "$W/otra" "$H/.lvm-instalador"
migra
check "~/.lvm-instalador que ya es un enlace: nada (ni se sigue ni se mueve)" '[ "$(readlink "$H/.lvm-instalador")" = "$W/otra" ] && [ ! -e "$H/.nexum" ] && [ ! -L "$H/.nexum" ] && [ "$(cat "$W/otra/f")" = fuera ] && [ ! -e "$W/otra/.pasando-a-nexum" ]'

casa m4; echo f > "$H/.lvm-instalador"
migra
check "un fichero ~/.lvm-instalador (no carpeta): nada" '[ -f "$H/.lvm-instalador" ] && [ "$(cat "$H/.lvm-instalador")" = f ] && [ ! -e "$H/.nexum" ]'

casa m5; mkdir -p "$H/.lvm-instalador"; echo v > "$H/.lvm-instalador/v"; ln -s "$W/no-existe" "$H/.nexum"
migra
check "~/.nexum como enlace roto: no se mueve nada" '[ -d "$H/.lvm-instalador" ] && [ ! -L "$H/.lvm-instalador" ] && [ -L "$H/.nexum" ] && [ ! -e "$W/no-existe" ] && [ "$(cat "$H/.lvm-instalador/v")" = v ]'

casa m6; mkdir -p "$H/.nexum"; echo v > "$H/.nexum/v"; : > "$H/.nexum/.pasando-a-nexum"
migra
check "cortada entre el mv y el enlace: la siguiente vez se crea el enlace (y se quita la marca)" '[ "$(readlink "$H/.lvm-instalador")" = .nexum ] && [ ! -e "$H/.nexum/.pasando-a-nexum" ] && [ "$(cat "$H/.lvm-instalador/v")" = v ]'
casa m7; mkdir -p "$H/.nexum"; : > "$H/.nexum/.pasando-a-nexum"; ln -s .nexum "$H/.lvm-instalador"
migra
check "cortada entre el enlace y quitar la marca: se quita la marca" '[ ! -e "$H/.nexum/.pasando-a-nexum" ] && [ "$(readlink "$H/.lvm-instalador")" = .nexum ]'
casa m8; mkdir -p "$H/.nexum"
migra
check "una ~/.nexum nueva (sin la de antes ni la marca): no se crea ningun enlace" '[ ! -e "$H/.lvm-instalador" ] && [ ! -L "$H/.lvm-instalador" ]'
casa m9; mkdir -p "$H/.lvm-instalador"; echo v > "$H/.lvm-instalador/v"; : > "$H/.lvm-instalador/.pasando-a-nexum"
migra
check "cortada antes del mv (la marca en la de antes): se hace entera" '[ "$(readlink "$H/.lvm-instalador")" = .nexum ] && [ "$(cat "$H/.nexum/v")" = v ] && [ ! -e "$H/.nexum/.pasando-a-nexum" ]'

casa d1; mkdir -p "$H/.lvm-instalador"
check "sin pasar (con --simular...): la carpeta de esta vez es la de antes, sin crear ~/.nexum" '[ "$(dir_de)" = "$H/.lvm-instalador" ] && [ ! -e "$H/.nexum" ]'
casa d2
check "sin ninguna: ~/.nexum" '[ "$(dir_de)" = "$H/.nexum" ]'

# --- El script entero, con otra carpeta personal (en el Mac solo se puede ejecutar alli) ---
if [ $MAC -eq 0 ]; then
    casa s1; mkdir -p "$H/.lvm-instalador"; echo ajuste > "$H/.lvm-instalador/apariencia"; chmod 755 "$H/.lvm-instalador"
    env -u LVM_PRUEBA -u LVM_SIMULAR HOME=$H bash "$SRC" --simular copias > /dev/null 2>&1
    env -u LVM_PRUEBA -u LVM_SIMULAR HOME=$H bash "$SRC" --simular copias-ficheros si > /dev/null 2>&1
    check "el script con --simular: no la renombra ni crea ~/.nexum" '[ -d "$H/.lvm-instalador" ] && [ ! -L "$H/.lvm-instalador" ] && [ ! -e "$H/.nexum" ] && [ ! -L "$H/.nexum" ]'
    LVM_PRUEBA=$W/prueba HOME=$H bash "$SRC" copias-ficheros si > /dev/null 2>&1
    check "el script en las pruebas (LVM_PRUEBA): no la renombra y sigue con la de antes" '[ -d "$H/.lvm-instalador" ] && [ ! -L "$H/.lvm-instalador" ] && [ ! -e "$H/.nexum" ] && [ -f "$H/.lvm-instalador/copias-ficheros" ]'
    for c in version novedades --ayuda; do
        env -u LVM_PRUEBA -u LVM_SIMULAR HOME=$H bash "$SRC" $c > /dev/null 2>&1
    done
    check "el script con version, novedades o --ayuda: no la renombra" '[ -d "$H/.lvm-instalador" ] && [ ! -L "$H/.lvm-instalador" ] && [ ! -e "$H/.nexum" ]'
    o=$(env -u LVM_PRUEBA -u LVM_SIMULAR HOME=$H bash "$SRC" copias-ficheros 2>&1)
    check "el script al arrancar: la renombra, deja el enlace y usa ~/.nexum" '[ -d "$H/.nexum" ] && [ ! -L "$H/.nexum" ] && [ "$(readlink "$H/.lvm-instalador")" = .nexum ] && [ "$(cat "$H/.nexum/apariencia")" = ajuste ] && grep -q "Copias de los ficheros que cambia el programa: si" <<< "$o"'
    check "y solo tuya (700)" '[ "$(stat -c %a "$H/.nexum")" = 700 ]'
    env -u LVM_PRUEBA -u LVM_SIMULAR HOME=$H bash "$SRC" copias-ficheros no > /dev/null 2>&1
    check "lo que escribe despues, en ~/.nexum" '[ ! -e "$H/.nexum/copias-ficheros" ] && [ -L "$H/.lvm-instalador" ]'
    casa s2
    env -u LVM_PRUEBA -u LVM_SIMULAR HOME=$H bash "$SRC" copias-ficheros si > /dev/null 2>&1
    check "el script sin ninguna carpeta: ~/.nexum, sin enlace de la de antes" '[ -f "$H/.nexum/copias-ficheros" ] && [ ! -e "$H/.lvm-instalador" ] && [ ! -L "$H/.lvm-instalador" ]'
fi
exit $fail
