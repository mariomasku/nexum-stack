#!/bin/bash
# Pruebas de la 1.51.0: BBDD vinculadas a la carpeta de su proyecto en cada version (vincular-bd),
# copiar-bd con otro nombre y otra carpeta (--como, --carpeta), carpetas de las versiones nuevas con
# la version completa de PHP (lampp-8.4.27) y fecha del PHP de las instaladas (gui-fechas), y en la
# ventana, el nombre propuesto para la copia. Uso: vinculos.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-vinc.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
MAC=0
grep -q 'BASE_DIR/XAMPP-' "$SRC" && MAC=1

# --- Vinculos: base@version=carpeta manda sobre base=carpeta ---------------------------------
extract "$SRC" linked_folder saved_project_db remember_project link_database db_valid_name \
    valid_version_name || exit 1
DB_SYSTEM="information_schema|mysql|performance_schema|phpmyadmin|sys|test"
PROJECTS_FILE=$W/proyectos DRY=0 HTDOCS_DIR=$W/htdocs
mkdir -p "$HTDOCS_DIR/tienda" "$HTDOCS_DIR/tienda 8.4" "$HTDOCS_DIR/otra"
active_name() { echo 8.4; }
valid_project() { [ -d "$HTDOCS_DIR/$1" ] && [[ "$1" != */* ]]; }
if [ $MAC -eq 1 ]; then
    BASE_DIR=$W/v; mkdir -p "$BASE_DIR/XAMPP-8.4" "$BASE_DIR/XAMPP-8.5.12" "$BASE_DIR/XAMPP-8.2"
else
    TEST_DIR=$W/v; mkdir -p "$TEST_DIR/lampp-8.4" "$TEST_DIR/lampp-8.5.12" "$TEST_DIR/lampp-8.2"
fi
printf 'wp_t=tienda\nwp_t_8_4=tienda 8.4\n' > "$PROJECTS_FILE"
check "sin vinculo de la version: el de todas" '[ "$(linked_folder wp_t 8.5.12)" == tienda ]'
check "carpeta con espacio entera" '[ "$(linked_folder wp_t_8_4 8.4)" == "tienda 8.4" ]'
link_database wp_t 8.5.12 "tienda 8.4" > /dev/null
check "vincular-bd: en esa version, la nueva" '[ "$(linked_folder wp_t 8.5.12)" == "tienda 8.4" ]'
check "vincular-bd: en las demas, la de antes" '[ "$(linked_folder wp_t 8.2)" == tienda ]'
check "vincular-bd: la de todas se queda en el fichero" 'grep -qx "wp_t=tienda" "$PROJECTS_FILE"'
link_database wp_t 8.2 - > /dev/null
check "vincular-bd -: desvinculada en esa version" '[ -z "$(linked_folder wp_t 8.2)" ] && grep -qx "wp_t@8.2=" "$PROJECTS_FILE"'
check "saved_project_db: la de la carpeta en la version" '[ "$(saved_project_db "tienda 8.4" 8.5.12)" == wp_t ]'
check "saved_project_db: en 8.4, la suya" '[ "$(saved_project_db "tienda 8.4" 8.4)" == wp_t_8_4 ]'
check "saved_project_db: desvinculada, nada" '[ -z "$(saved_project_db tienda 8.2)" ]'
check "saved_project_db: sin version, la activa" '[ "$(saved_project_db tienda)" == wp_t ]'
link_database wp_t 8.5.12 "tienda 8.4" > /dev/null
check "vincular otra vez no repite lineas" '[ "$(grep -c "^wp_t@8.5.12=" "$PROJECTS_FILE")" == 1 ]'
check "vincular-bd: carpeta que no existe, no" '! link_database wp_t 8.4 nada > /dev/null'
check "vincular-bd: version que no existe, no" '! link_database wp_t 9.9 tienda > /dev/null'
check "vincular-bd: base rara, no" '! link_database "a;b" 8.4 tienda > /dev/null && ! grep -q "a;b" "$PROJECTS_FILE"'
check "vincular-bd: sin carpeta, uso" 'link_database wp_t 8.4 2>&1 | grep -q Uso'
# --unica (subir una base para un proyecto): en esa version la carpeta deja las demas
printf 'wp_viejo=otra\nwp_x@8.4=otra\nwp_x@8.2=otra\n' > "$PROJECTS_FILE"
remember_project wp_nuevo otra 8.4 --unica
check "--unica: la nueva vinculada" '[ "$(linked_folder wp_nuevo 8.4)" == otra ]'
check "--unica: la otra de esa version, fuera" '[ -z "$(linked_folder wp_x 8.4)" ]'
check "--unica: la de otra version no se toca" '[ "$(linked_folder wp_x 8.2)" == otra ]'
check "--unica: la de todas, desvinculada solo en esta" '[ -z "$(linked_folder wp_viejo 8.4)" ] && [ "$(linked_folder wp_viejo 8.2)" == otra ]'
check "--unica: la carpeta va con la nueva" '[ "$(saved_project_db otra 8.4)" == wp_nuevo ]'
DRY=1; cp "$PROJECTS_FILE" "$W/antes"; remember_project wp_sim otra 8.4
check "simulacion: no se escribe" 'cmp -s "$PROJECTS_FILE" "$W/antes"'
DRY=0

# --- gui-proyectos: V|base|version|carpeta ---------------------------------------------------
extract "$SRC" gui_projects || exit 1
project_link() { echo web.local; }
EMPTY_PROJECT=/nada
printf 'wp_t=tienda\nwp_t@8.5.12=tienda 8.4\nwp_t@8.2=\n' > "$PROJECTS_FILE"
out=$(gui_projects 2> /dev/null)
check "gui-proyectos: R de las de todas" 'grep -qx "R|wp_t|tienda" <<< "$out"'
check "gui-proyectos: V de una version" 'grep -qx "V|wp_t|8.5.12|tienda 8.4" <<< "$out"'
check "gui-proyectos: V desvinculada" 'grep -qx "V|wp_t|8.2|" <<< "$out"'
check "gui-proyectos: la V no sale como R" '! grep -q "^R|wp_t@" <<< "$out"'

# --- copiar-bd --como / --carpeta (simulacion) -----------------------------------------------
extract "$SRC" copy_database || exit 1
if [ $MAC -eq 1 ]; then
    db_names() { case "$1" in *8.4) printf 'wp_t_8_4\n' ;; *8.5.12) printf 'wp_t_8_5\n' ;; esac; }
else
    data_owner() { basename "$1" | sed 's/^lampp-//'; }
    db_names() { case "$1" in *8.4) printf 'wp_t_8_4\n' ;; *8.5.12) printf 'wp_t_8_5\n' ;; esac; }
fi
active_dir() { echo ""; }; lampp_running() { return 1; }; realpath_f() { echo "$1"; }
DRY=1
out=$(copy_database wp_t_8_4 8.4 8.5.12 --como wp_t_8_5b --carpeta "tienda 8.4" 2>&1)
check "copiar-bd --como: se copia con el nombre nuevo" 'grep -q "como wp_t_8_5b" <<< "$out" && grep -q "carga de wp_t_8_5b" <<< "$out"'
check "copiar-bd --carpeta: se vincula alli" 'grep -q "wp_t_8_5b vinculada a tienda 8.4 en" <<< "$out"'
check "copiar-bd --como con un nombre que ya tiene: no, sin --sustituir" '! copy_database wp_t_8_4 8.4 8.5.12 --como wp_t_8_5 > /dev/null 2>&1'
check "copiar-bd --como ... --sustituir: si" 'copy_database wp_t_8_4 8.4 8.5.12 --como wp_t_8_5 --sustituir 2>&1 | grep -q "copia de wp_t_8_5 de"'
check "copiar-bd: el de destino con el mismo nombre libre, si" 'copy_database wp_t_8_4 8.4 8.5.12 > /dev/null 2>&1'
check "copiar-bd --como raro: no" '! copy_database wp_t_8_4 8.4 8.5.12 --como "x;y" > /dev/null 2>&1'
check "copiar-bd --como del sistema: no" '! copy_database wp_t_8_4 8.4 8.5.12 --como mysql > /dev/null 2>&1'
check "copiar-bd --carpeta que no existe: no" '! copy_database wp_t_8_4 8.4 8.5.12 --carpeta nada > /dev/null 2>&1'
check "copiar-bd --carpeta -: sin vincular" 'copy_database wp_t_8_4 8.4 8.5.12 --como z --carpeta - 2>&1 | grep -q "sin vincular a ningun proyecto"'
check "copiar-bd opcion desconocida: uso" 'copy_database wp_t_8_4 8.4 8.5.12 --otra 2>&1 | grep -q Uso'
check "copiar-bd --como sin nombre: uso" 'copy_database wp_t_8_4 8.4 8.5.12 --como 2>&1 | grep -q Uso'
DRY=0
check "comando copiar-bd pasa todas las opciones" 'grep -q "copiar-bd) shift; copy_database \"\$@\"" "$SRC"'
check "comando vincular-bd" 'grep -q "vincular-bd) link_database" "$SRC"'

# --- Versiones nuevas en su carpeta con la version completa ----------------------------------
if [ $MAC -eq 1 ]; then
    extract "$SRC" install_stack version_dirs version_name || exit 1
    STACK_MATRIX=("8.4|x")
    mkdir -p "$BASE_DIR/XAMPP-8.4.27" "$BASE_DIR/XAMPP-8.4.10" "$BASE_DIR/XAMPP-otra"
    check "el ultimo parche va en XAMPP-X.Y.Z" '( install_stack 8.4.27 ) | grep -q "Ya existe $BASE_DIR/XAMPP-8.4.27$"'
    check "actualizar una XAMPP-X.Y de antes sigue en la suya" '( install_stack 8.4.27 1 ) | grep -q "No existe $BASE_DIR/XAMPP-8.4,"'
    check "las XAMPP-X.Y.Z salen entre las instaladas, en orden" '[ "$(version_dirs | sed "s|.*/XAMPP-||" | tr "\n" " ")" == "8.2 8.4 8.4.10 8.4.27 8.5.12 " ]'
else
    extract "$SRC" php_item item_folder || exit 1
    check "el ultimo parche va en lampp-X.Y.Z" '[ "$(item_folder "$(php_item 8.4.27 8.4.27)")" == 8.4.27 ]'
    check "un parche anterior, tambien" '[ "$(item_folder "$(php_item 8.4.10 8.4.27)")" == 8.4.10 ]'
    check "actualizar una lampp-X.Y de antes sigue en la suya" '[ "$(item_folder rehacer:8.4.27)" == 8.4 ]'
fi

# --- gui-fechas ------------------------------------------------------------------------------
extract "$SRC" gui_php_dates || exit 1
php_all_releases() { printf '8.5.12 2026-10-09 -\n8.4.27 2026-10-02 seguridad\n8.2.4 2023-03-16 -\n'; }
if [ $MAC -eq 1 ]; then
    version_dirs() { printf '%s\n' "$BASE_DIR/XAMPP-8.4" "$BASE_DIR/XAMPP-8.5.12" "$BASE_DIR/XAMPP-8.2.4"; }
else
    lampp_dirs() { printf '/opt/lampp-8.4\n/opt/lampp-8.5.12\n/opt/lampp-8.2.4\n'; }
fi
stack_fields() { case "$1" in *8.4) echo "8.4.27|2.4|11.8|1.3|5.42|5.2.3" ;; *8.5.12) echo "8.5.12|2.4|12|1.3|5.44|5.2.3" ;; *) echo "-|-|-|-|-|-" ;; esac; }
out=$(gui_php_dates)
check "gui-fechas: fecha de cada PHP instalado" 'grep -q "^F|8.4|8.4.27|2026-10-02$" <<< "$out" && grep -q "^F|8.5.12|8.5.12|2026-10-09$" <<< "$out"'
check "gui-fechas: sin PHP conocido, nada" '! grep -q "8.2.4" <<< "$out"'
php_all_releases() { :; }
check "gui-fechas: sin conexion, falla sin lineas" '! out=$(gui_php_dates) && [ -z "$out" ]'

# --- Ventana: nombre propuesto para la copia -------------------------------------------------
if [ $MAC -eq 0 ]; then
    awk '/^    cat <<.LVM_GUI_PY.$/{f=1;next} /^LVM_GUI_PY$/{f=0} f' "$SRC" > "$W/gui.py"
    out=$(python3 -I - "$W/gui.py" <<'EOF'
import ast, re, sys
tree = ast.parse(open(sys.argv[1]).read())
ns = {"re": re}
for node in tree.body:
    if isinstance(node, ast.FunctionDef) and node.name == "copy_name":
        exec(compile(ast.Module(body=[node], type_ignores=[]), "gui", "exec"), ns)
for db, php in [("wp_t_8_4", "8.5.12"), ("wp_t", "8.5.12"), ("ps_x-8_2", "8.4.27"), ("a" * 62, "8.5.1")]:
    print(ns["copy_name"](db, php))
EOF
)
    check "ventana: wp_t_8_4 → wp_t_8_5" '[ "$(sed -n 1p <<< "$out")" == wp_t_8_5 ]'
    check "ventana: sin sufijo, se le pone" '[ "$(sed -n 2p <<< "$out")" == wp_t_8_5 ]'
    check "ventana: sufijo con guion" '[ "$(sed -n 3p <<< "$out")" == ps_x_8_4 ]'
    check "ventana: si no cabe en 64, el mismo nombre" '[ "$(sed -n 4p <<< "$out")" == "$(printf "a%.0s" {1..62})" ]'
fi
exit $fail
