#!/bin/bash
# Exportar proyecto (1.57.14): exportar-proyecto y gui-exportar-proyecto con un repositorio git de mentira en
# una carpeta temporal (HOME, htdocs, descargas y la version, todo de mentira; la BBDD, con un export_database
# falso). Con cambios sin commit no exporta; limpio, el zip <carpeta>_php<rama>_<fecha>_nexum.zip con el codigo
# sin .git, la base y el LEEME; --sin-bd y --sin-codigo; los enlaces que salen no se siguen; si falla la base no
# queda nada; --simular no crea nada. Uso: exportar-proyecto.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q '^function project_export() {' "$SRC" || { echo "  ok    (sin Exportar proyecto)"; exit 0; }
command -v git > /dev/null || { echo "  ok    (sin git: no se prueba)"; exit 0; }
W=$(mktemp -d "$TMPBASE/w-exportar.XXXXXX") || exit 1
trap 'chmod -R u+rwX "${W:?}" 2> /dev/null; rm -rf "${W:?}"' EXIT
MAC=0; grep -qE '^    BASE_DIR=(/Applications|/Library/Nexum)$' "$SRC" && MAC=1

extract "$SRC" project_export project_export_run project_export_cleanup project_export_git project_export_db \
    project_export_branch project_export_name gui_project_export export_downloads export_version_label \
    valid_project db_valid_name || exit 1
eval "$(sed -n "/^PROJECT_EXPORT_PY='/,/^'\$/p" "$SRC")"
[ -n "$PROJECT_EXPORT_PY" ] || { echo "  FALLA no esta PROJECT_EXPORT_PY"; exit 1; }
EXPORT_PART="" EXPORT_TMP=""

# El equipo de mentira: HOME, htdocs, la version activa y sus BBDD
export HOME=$W/casa
mkdir -p "$HOME/Descargas" "$HOME/Downloads"
DOWN=$HOME/Descargas; [ $MAC -eq 1 ] && DOWN=$HOME/Downloads
HTDOCS_DIR=$W/htdocs LOG_DIR=$HOME/.lvm-instalador DRY=0 APP_NAME="Nexum Dev Stack" APP_VERSION=9.9.9
unset LVM_TAREA LVM_PROGRESO
active_dir() { echo "$W/version"; }
active_name() { echo 8.4; }
php_version() { echo 8.4.27; }
stack_fields() { echo "8.4.27|2.4.65|11.4.8|1.3.9|5.40|5.2.2"; }
db_names() { printf '%s\n' wp_panaderia_luna otra; }
saved_project_db() { [ "$1" == panaderia-luna ] && echo wp_panaderia_luna; }
project_config_db() { :; }
task_plan() { :; }; task_step() { :; }
gui_db_check() { echo "ok|8.4|11.4.8"; }
xdg-user-dir() { echo "$HOME/Descargas"; }
DUMP_FAIL=0
export_database() {
    echo "export_database $*" >> "$W/bd.log"
    printf -- '-- volcado de %s\nCREATE TABLE wp_options (option_id INT);\n' "$1" > "$2.parte"
    [ "$DUMP_FAIL" -eq 1 ] && { rm -f "$2.parte"; return 1; }
    mv "$2.parte" "$2"
}

P=$HTDOCS_DIR/panaderia-luna
mkdir -p "$P/wp-content/themes/luna" "$P/vacia" "$W/fuera"
echo secreto > "$W/fuera/secreto.txt"
echo '<?php echo "hola";' > "$P/index.php"
echo tema > "$P/wp-content/themes/luna/style.css"
printf '#!/bin/sh\n' > "$P/run.sh"; chmod 750 "$P/run.sh"
printf 'node_modules/\n*.log\n' > "$P/.gitignore"
( cd "$P" && git init -q && git -c user.name=Prueba -c user.email=prueba@ejemplo.test add -A \
    && git -c user.name=Prueba -c user.email=prueba@ejemplo.test commit -qm inicio ) || { echo "  FALLA git init"; exit 1; }
# (lo que esta en .gitignore no cuenta como cambio, pero va en el zip)
echo registro > "$P/debug.log"

zips() { ls "$DOWN" 2> /dev/null | grep -c '_nexum\.zip$'; }
parts() { find "$DOWN" "$LOG_DIR" -name '*.parte' 2> /dev/null | wc -l | tr -d ' '; }
run() { ( project_export "$@" ) < /dev/null 2>&1; }
names() { python3 -I -c 'import sys, zipfile; print("\n".join(zipfile.ZipFile(sys.argv[1]).namelist()))' "$1"; }

# Con cambios sin commit (uno cambiado y uno nuevo sin seguimiento): no exporta y dice cuales
echo cambio >> "$P/index.php"
echo nuevo > "$P/nuevo.php"
out=$(run panaderia-luna); rc=$?
check "con cambios sin commit no exporta y dice cuáles" '[ $rc -ne 0 ] && [ "$(zips)" == 0 ] && grep -q "2 cambios sin commit" <<< "$out" && grep -q "index.php" <<< "$out" && grep -q "nuevo.php" <<< "$out" && grep -q "Haz commit" <<< "$out"'
check "... no descarga la BBDD ni deja nada" '[ ! -e "$W/bd.log" ] && [ "$(parts)" == 0 ] && [ -z "$(ls -A "$LOG_DIR" 2> /dev/null | grep exportar)" ]'
out=$(gui_project_export panaderia-luna)
check "gui-exportar-proyecto: los cambios, con la lista" 'grep -q "^G|1|[^|]*|2|0|0$" <<< "$out" && [ "$(grep -c "^C|" <<< "$out")" == 2 ]'
( cd "$P" && git checkout -q -- index.php ) && rm -f "$P/nuevo.php"

# Limpio: el zip, con el codigo sin .git, la base y el LEEME
out=$(gui_project_export panaderia-luna)
check "gui-exportar-proyecto: limpio, la versión, su PHP, la BBDD, lo que ocupa y el destino" 'grep -q "^G|1|[^|]*|0|0|0$" <<< "$out" && grep -qx "V|8.4|$(export_version_label 8.4)|8.4.27|11.4.8" <<< "$out" && grep -qx "B|wp_panaderia_luna" <<< "$out" && grep -qE "^S|[1-9][0-9]*$" <<< "$out" && grep -qx "D|$DOWN" <<< "$out" && grep -qE "^N\|panaderia-luna_php8\.4_[0-9]{8}-[0-9]{4}_nexum\.zip$" <<< "$out"'
out=$(run panaderia-luna); rc=$?
Z=$(ls "$DOWN"/*_nexum.zip 2> /dev/null | head -1)
check "limpio: crea el zip con el nombre <carpeta>_php<rama>_<fecha>_nexum.zip" '[ $rc -eq 0 ] && [ "$(zips)" == 1 ] && [[ "$(basename "$Z")" =~ ^panaderia-luna_php8\.4_[0-9]{8}-[0-9]{4}_nexum\.zip$ ]] && grep -qF "Exportado: $Z" <<< "$out"' || echo "$out" | tail -5
check "... el zip es solo tuyo y no quedan .parte ni temporales" '[ "$(stat -c %a "$Z" 2> /dev/null || stat -f %Lp "$Z")" == 600 ] && [ "$(parts)" == 0 ] && [ -z "$(ls -A "$LOG_DIR" | grep exportar)" ]'
n=$(names "$Z")
check "... el código va en panaderia-luna/, sin .git" 'grep -qx "panaderia-luna/index.php" <<< "$n" && grep -qx "panaderia-luna/wp-content/themes/luna/style.css" <<< "$n" && grep -qx "panaderia-luna/debug.log" <<< "$n" && grep -qx "panaderia-luna/vacia/" <<< "$n" && ! grep -q "\.git/" <<< "$n"'
check "... con sus permisos (run.sh, 750)" 'python3 -I -c "import sys, zipfile; z = zipfile.ZipFile(sys.argv[1]); sys.exit(0 if (z.getinfo(\"panaderia-luna/run.sh\").external_attr >> 16) & 0o777 == 0o750 else 1)" "$Z"'
check "... la base, con export_database, de la versión activa" 'grep -qx "wp_panaderia_luna.sql" <<< "$n" && unzip -p "$Z" wp_panaderia_luna.sql | grep -q "volcado de wp_panaderia_luna" && grep -q "^export_database wp_panaderia_luna .*/wp_panaderia_luna.sql 8.4$" "$W/bd.log"'
L=$(unzip -p "$Z" LEEME-nexum.txt)
check "... y el LEEME-nexum.txt: proyecto, PHP, MariaDB, fecha y la versión de Nexum" 'grep -q "Proyecto: panaderia-luna" <<< "$L" && grep -q "PHP: 8.4.27" <<< "$L" && grep -q "MariaDB: 11.4.8" <<< "$L" && grep -q "Nexum Dev Stack 9.9.9 el [0-9][0-9]/" <<< "$L"'
check "... el código del proyecto no ha cambiado" '[ -z "$(cd "$P" && git status --porcelain)" ]'

# Otro en el mismo minuto: otro nombre, sin escribir encima
out=$(run panaderia-luna --sin-bd); rc=$?
check "--sin-bd: otro zip (sin escribir encima del de antes), sin la base" '[ $rc -eq 0 ] && [ "$(zips)" == 2 ] && Z2=$(sed -n "s/^Exportado: //p" <<< "$out") && [ "$Z2" != "$Z" ] && [[ "$Z2" == *_nexum.zip ]] && ! names "$Z2" | grep -q "\.sql$" && names "$Z2" | grep -qx "panaderia-luna/index.php"'
rm -f "$DOWN"/*_nexum.zip

out=$(run panaderia-luna --sin-codigo); rc=$?
Z=$(ls "$DOWN"/*_nexum.zip 2> /dev/null | head -1)
check "--sin-codigo: solo la base y el LEEME" '[ $rc -eq 0 ] && [ -n "$Z" ] && [ "$(names "$Z" | sort | tr "\n" " ")" == "LEEME-nexum.txt wp_panaderia_luna.sql " ]'
rm -f "$DOWN"/*_nexum.zip
out=$(run panaderia-luna --sin-codigo --sin-bd); rc=$?
check "--sin-codigo y --sin-bd: nada que exportar" '[ $rc -ne 0 ] && [ "$(zips)" == 0 ] && grep -q "Uso:" <<< "$out"'
out=$(run panaderia-luna --bd noexiste); rc=$?
check "--bd de una base que no está en la versión activa: no exporta" '[ $rc -ne 0 ] && [ "$(zips)" == 0 ] && grep -q "No hay ninguna base de datos noexiste" <<< "$out"'
mkdir -p "$W/otro-destino"
out=$(run panaderia-luna --destino "$W/otro-destino" --bd otra); rc=$?
check "--destino y --bd" '[ $rc -eq 0 ] && ls "$W/otro-destino" | grep -q "_nexum\.zip$" && names "$W/otro-destino/"*_nexum.zip | grep -qx "otra.sql"'
out=$(run panaderia-luna --destino "$P/wp-content"); rc=$?
check "el zip no puede ir dentro del propio proyecto" '[ $rc -ne 0 ] && [ -z "$(find "$P" -name "*_nexum.zip*")" ]'

# Enlaces: uno que sale de la carpeta no se sigue; uno de dentro va como enlace
ln -s "$W/fuera" "$P/sale"
ln -s ../../fuera/secreto.txt "$P/sale-relativo"
ln -s wp-content/themes "$P/temas"
( cd "$P" && git add -A && git -c user.name=Prueba -c user.email=prueba@ejemplo.test commit -qm enlaces )
out=$(run panaderia-luna --sin-bd); rc=$?
Z=$(ls "$DOWN"/*_nexum.zip 2> /dev/null | head -1)
n=$(names "$Z")
check "un enlace que sale de la carpeta no se sigue ni se guarda (absoluto o con ..)" '[ $rc -eq 0 ] && ! grep -q "secreto" <<< "$n" && ! grep -qx "panaderia-luna/sale" <<< "$n" && ! grep -qx "panaderia-luna/sale-relativo" <<< "$n" && ! unzip -p "$Z" | grep -q secreto && grep -q "No van en el zip 2 enlaces" <<< "$out"'
check "... uno de dentro de la carpeta va como enlace (sin copiar lo de dentro dos veces)" 'python3 -I -c "import stat, sys, zipfile; z = zipfile.ZipFile(sys.argv[1]); i = z.getinfo(\"panaderia-luna/temas\"); sys.exit(0 if stat.S_ISLNK(i.external_attr >> 16) and z.read(i) == b\"wp-content/themes\" else 1)" "$Z" && ! grep -q "panaderia-luna/temas/" <<< "$n"'
rm -f "$DOWN"/*_nexum.zip "$P/sale" "$P/sale-relativo" "$P/temas"
( cd "$P" && git add -A && git -c user.name=Prueba -c user.email=prueba@ejemplo.test commit -qm sin-enlaces )

# Si falla la descarga de la base: ningun zip ni .parte (ni el .sql temporal)
DUMP_FAIL=1
out=$(run panaderia-luna); rc=$?
check "si falla la descarga de la BBDD no queda ningún zip, ni .parte, ni el .sql" '[ $rc -ne 0 ] && [ "$(zips)" == 0 ] && [ "$(parts)" == 0 ] && [ -z "$(find "$DOWN" "$LOG_DIR" -name "*.sql*")" ] && grep -q "no se ha exportado nada" <<< "$out"'
DUMP_FAIL=0
# Sin poder escribir en la carpeta de descargas
chmod 500 "$DOWN"
out=$(run panaderia-luna); rc=$?
chmod 700 "$DOWN"
check "sin poder escribir en descargas: no exporta ni deja nada" '[ $rc -ne 0 ] && [ "$(zips)" == 0 ] && [ "$(parts)" == 0 ] && [ -z "$(ls -A "$LOG_DIR" | grep exportar)" ]'
# Cancelada a media escritura del zip (como el Cancelar de la ventana): no queda nada
dd if=/dev/urandom of="$P/grande.bin" bs=1M count=48 2> /dev/null
( cd "$P" && git add -A && git -c user.name=Prueba -c user.email=prueba@ejemplo.test commit -qm grande )
( project_export panaderia-luna > "$W/cancelar.out" 2>&1 < /dev/null ) &
pid=$!
seen=0
for i in $(seq 100); do [ -n "$(find "$DOWN" -name "*.parte" 2> /dev/null)" ] && { seen=1; break; }; sleep 0.05; done
# (como la ventana, que lo manda a todo el grupo: a la tarea y a lo que esta escribiendo el zip)
pkill -TERM -P "$pid" 2> /dev/null; kill -TERM "$pid" 2> /dev/null
wait "$pid" 2> /dev/null
sleep 0.3
check "cancelada a medias: no queda ningún zip, ni .parte, ni el temporal" '[ $seen -eq 1 ] && [ "$(zips)" == 0 ] && [ "$(parts)" == 0 ] && [ -z "$(ls -A "$LOG_DIR" | grep exportar)" ]'
rm -f "$P/grande.bin"; rm -f "$DOWN"/*_nexum.zip
( cd "$P" && git add -A && git -c user.name=Prueba -c user.email=prueba@ejemplo.test commit -qm sin-grande )

# Un fichero que no se puede leer (en .gitignore, como un registro de Apache): no va, y se dice
echo privado > "$P/privado.log"; chmod 000 "$P/privado.log"
if [ -r "$P/privado.log" ]; then
    ok "(como root se puede leer todo: no se prueba un fichero sin permiso)"
else
    out=$(run panaderia-luna --sin-bd); rc=$?
    check "un fichero que no se puede leer no va en el zip y se avisa" '[ $rc -eq 0 ] && grep -q "no se han podido leer 1" <<< "$out" && ! names "$(ls "$DOWN"/*_nexum.zip | head -1)" | grep -q privado.log'
fi
chmod 600 "$P/privado.log"; rm -f "$P/privado.log" "$DOWN"/*_nexum.zip

# Commits sin subir: se avisa y se exporta igual
git init -q --bare "$W/remoto.git"
( cd "$P" && git remote add origin "$W/remoto.git" && git push -q -u origin HEAD 2> /dev/null && echo mas >> index.php \
    && git -c user.name=Prueba -c user.email=prueba@ejemplo.test commit -qam mas ) > /dev/null 2>&1
out=$(gui_project_export panaderia-luna)
check "gui-exportar-proyecto: los commits sin subir" 'grep -q "^G|1|[^|]*|0|1|1$" <<< "$out"'
out=$(run panaderia-luna --sin-bd); rc=$?
check "con commits sin subir: avisa y exporta" '[ $rc -eq 0 ] && grep -q "1 commit sin subir" <<< "$out" && [ "$(zips)" == 1 ]'
rm -f "$DOWN"/*_nexum.zip

# Sin git: lo dice y deja seguir
Q=$HTDOCS_DIR/sin-git
mkdir -p "$Q"; echo hola > "$Q/index.html"
out=$(gui_project_export sin-git)
check "gui-exportar-proyecto: sin git y sin BBDD vinculada" 'grep -qx "G|0||0|0|0" <<< "$out" && grep -qx "B|" <<< "$out"'
out=$(run sin-git); rc=$?
check "sin git: «no se puede comprobar» y exporta; sin BBDD vinculada, solo el código" '[ $rc -eq 0 ] && grep -q "no se puede comprobar" <<< "$out" && grep -q "Sin BBDD vinculada" <<< "$out" && [ "$(zips)" == 1 ] && ! names "$(ls "$DOWN"/*_nexum.zip)" | grep -q "\.sql$"'
rm -f "$DOWN"/*_nexum.zip
out=$(run sin-git --sin-codigo); rc=$?
check "sin BBDD vinculada y --sin-codigo: no hay nada que exportar" '[ $rc -ne 0 ] && [ "$(zips)" == 0 ]'
out=$(run ../fuera); rc=$?
check "una carpeta que no es de htdocs: no" '[ $rc -ne 0 ] && [ "$(zips)" == 0 ]'

# Desde la ventana, con el MariaDB parado: no pide la contraseña, lo dice
gui_db_check() { echo "no|El MariaDB no está en marcha."; }
out=$(LVM_TAREA=1 run panaderia-luna); rc=$?
check "en la ventana, con el MariaDB parado: lo dice y no exporta" '[ $rc -ne 0 ] && grep -q "no está en marcha" <<< "$out" && [ "$(zips)" == 0 ] && [ "$(parts)" == 0 ]'
gui_db_check() { echo "ok|8.4|11.4.8"; }

# --simular: no crea nada
: > "$W/bd.log"
out=$(DRY=1 run panaderia-luna); rc=$?
check "--simular: dice lo que haría y no crea nada" '[ $rc -eq 0 ] && grep -q "\[simulacion\]" <<< "$out" && [ "$(zips)" == 0 ] && [ "$(parts)" == 0 ] && [ ! -s "$W/bd.log" ] && [ -z "$(ls -A "$LOG_DIR" 2> /dev/null | grep exportar)" ]'

# La orden, en la cabecera (--ayuda) y sin pedir la contraseña desde la ventana
check "exportar-proyecto en la ayuda y en las órdenes" 'grep -q "^#   nexum exportar-proyecto <carpeta> \[--sin-codigo\] \[--sin-bd\] \[--bd <base>\] \[--destino <carpeta>\]" "$SRC" && grep -q "^    exportar-proyecto) shift; project_export" "$SRC" && grep -q "^    gui-exportar-proyecto) gui_project_export" "$SRC"'
check "exportar-proyecto no pide la contraseña de administrador" 'grep -qE "^        gui-\*\|.*\|exportar-proyecto\|.*\) ;;$" "$SRC"'
exit $fail
