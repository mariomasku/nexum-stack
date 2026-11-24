#!/bin/bash
# BBDD marcadas para borrar al cargar su version (1.57.48): marcar-bd, gui-datos (J|version|base),
# borrar-bd-marcadas (solo las de la version activa; las que ya no estan, se desmarcan) y el aviso de use.
# Tambien, en las dos ventanas: la marca, la pregunta y el scroll de Copiar BBDD.
# Uso: marcas-bd.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-marcas.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
extract "$SRC" db_mark_drop db_mark_set db_marked gui_db_marks drop_marked_databases db_marks_notice || exit 1
DRY=0 LOG_DIR=$W
eval "$(grep -m1 '^DROP_MARKS_FILE=' "$SRC")"
db_valid_name() { [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ ]] || { echo "Nombre de base de datos no valido: $1"; return 1; }; }

out=$(db_mark_drop 7.4 wp_viejo; db_mark_drop 7.4 ps_antigua; db_mark_drop 8.1 wp_otra)
check "marca tres (dos en 7.4)" '[ "$(wc -l < "$DROP_MARKS_FILE")" -eq 3 ] && [[ "$out" == *"wp_viejo (en 7.4) marcada para borrar"* ]]'
db_mark_drop 7.4 wp_viejo > /dev/null
check "marcar dos veces no la repite" '[ "$(grep -c "^7.4|wp_viejo|" "$DROP_MARKS_FILE")" -eq 1 ]'
check "gui-datos: J|version|base" '[ "$(gui_db_marks | sort | tr "\n" " ")" == "J|7.4|ps_antigua J|7.4|wp_viejo J|8.1|wp_otra " ]'
out=$(db_mark_drop 7.4 ps_antigua --quitar); rc=$?
check "--quitar la desmarca (y sale bien)" '[ $rc -eq 0 ] && ! grep -q "|ps_antigua|" "$DROP_MARKS_FILE" && [[ "$out" == *"ya no esta marcada"* ]]'
check "desmarcar la que no esta: sale bien" 'db_mark_drop 7.4 nada --quitar > /dev/null'
check "una version que no vale, no" '! db_mark_drop "../x" wp_a > /dev/null && ! db_mark_drop "7.4|x" wp_a > /dev/null'
check "un nombre de base que no vale, no" '! db_mark_drop 7.4 "a;b" > /dev/null'
check "una opcion que no es --quitar, no" '! db_mark_drop 7.4 wp_a --otra > /dev/null && ! grep -q "|wp_a|" "$DROP_MARKS_FILE"'
echo "7.4|mal|nombre|x" >> "$DROP_MARKS_FILE"; echo "basura" >> "$DROP_MARKS_FILE"
check "las lineas raras no se leen como marcas" '[ "$(db_marked 7.4 | tr "\n" " ")" == "wp_viejo mal " ] && ! gui_db_marks | grep -q basura'
sed -i '/^7.4|mal|/d; /^basura$/d' "$DROP_MARKS_FILE"
check "aviso al cargar la version" '[[ "$(db_marks_notice 7.4)" == "Tiene 1 BBDD marcadas para borrar (wp_viejo): nexum borrar-bd-marcadas [--copia]" ]] && [ -z "$(db_marks_notice 8.2)" ]'

# borrar-bd-marcadas: con la 7.4 activa, la que esta se borra (con --copia si se pide) y la que no, se desmarca
db_mark_drop 7.4 wp_ya_no > /dev/null
db_connect() { DB_FOLDER=7.4; }
db_exists() { [ "$1" != wp_ya_no ]; }
drop_database() { echo "borrar $1 $2" >> "$W/borradas"; read -r -t 0.1 _ 2> /dev/null; return 0; }
out=$(drop_marked_databases --copia); rc=$?
check "borra las marcadas de la activa (con --copia)" '[ $rc -eq 0 ] && [ "$(cat "$W/borradas")" == "borrar wp_viejo --copia" ]'
check "la que ya no esta se desmarca sin borrar" '[[ "$out" == *"wp_ya_no ya no está: se desmarca"* ]]'
check "las de otras versiones siguen marcadas" '[ "$(db_marked | tr "\n" " ")" == "8.1|wp_otra " ]'
check "sin marcadas en la activa, lo dice" '[[ "$(drop_marked_databases)" == "No hay ninguna BBDD marcada para borrar en 7.4" ]]'
db_mark_drop 7.4 wp_falla > /dev/null
drop_database() { return 1; }
out=$(drop_marked_databases); rc=$?
check "si no se puede borrar, sigue marcada y sale mal" '[ $rc -ne 0 ] && [ "$(db_marked 7.4)" == wp_falla ] && [[ "$out" == *"siguen marcadas"* ]]'
check "una opcion que no es --copia, no" '! drop_marked_databases --otra > /dev/null'

# Los comandos, sin sudo, y borrar-bd desmarca
check "marcar-bd y borrar-bd-marcadas en el case" 'grep -q "^    marcar-bd) db_mark_drop" "$SRC" && grep -q "^    borrar-bd-marcadas) drop_marked_databases" "$SRC"'
check "sin pedir la contraseña de administrador" 'grep -q "borrar-bd|borrar-bd-marcadas|marcar-bd) ;;" "$SRC"'
check "borrar-bd le quita la marca" 'awk "/^function drop_database\\(\\)/,/^}/" "$SRC" | grep -q "db_mark_set \"\$DB_FOLDER\" \"\$db\" \"\""'
check "use avisa de las marcadas" 'grep -q "^    db_marks_notice \"\$version\"" "$SRC"'
check "gui-datos manda las marcas" 'awk "/^function gui_data\\(\\)/,/^}/" "$SRC" | grep -q "^    gui_db_marks"'

# Las ventanas
if grep -qE '^    BASE_DIR=(/Applications|/Library/Nexum)$' "$SRC"; then
    check "Mac: lee J y pregunta al cargar" 'grep -q "case \"J\" where f.count >= 3:" "$SRC" && grep -q "func dbMarksCheck()" "$SRC" && grep -q "\[\"borrar-bd-marcadas\"\]" "$SRC"'
    check "Mac: marcar, desmarcar y la etiqueta" 'grep -q "\"Marcar para borrar al cargar XAMPP-\"" "$SRC" && grep -q "SmallTag(text: \"Para borrar\", red: true)" "$SRC"'
    check "Mac: Copiar BBDD con scroll" 'grep -q "views.append(dialogScroll(dialogOptions(options)))" "$SRC"'
    check "Mac: desplegables debajo del botón" 'grep -q "final class DropDownButton: NSPopUpButton" "$SRC" && ! grep -q "NSPopUpButton(frame:" "$SRC" && grep -q "MenuPicker(selection: \$selection" "$SRC"'
else
    check "Linux: lee J y pregunta al cargar" 'grep -q "elif f\[0\] == \"J\" and len(f) >= 3:" "$SRC" && grep -q "def nv_db_marks_check(self):" "$SRC" && grep -q "\[\"borrar-bd-marcadas\"\]" "$SRC"'
    check "Linux: marcar, desmarcar y la etiqueta" 'grep -q "\"Marcar para borrar al cargar lampp-%s\"" "$SRC" && grep -q "label(\"Para borrar\", \"nv-etiqueta\", \"nv-etiqueta-roja\"" "$SRC"'
    check "Linux: Copiar BBDD con scroll" 'grep -q "box.pack_start(scroll_list(opts, self.win), False, False, 0)" "$SRC"'
    check "Linux: la lista con buscador cabe en su ventana" 'grep -q "max_content_height=max(120, min(360, room))" "$SRC" && grep -q "Gtk.PositionType.TOP if up else Gtk.PositionType.BOTTOM" "$SRC"'
fi
exit $fail
