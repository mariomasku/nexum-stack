#!/bin/bash
# Copias de seguridad (Linux y Mac 1.57.7): la carpeta ~/nexum-backups (antes ~/lvm-copias, que se
# renombra sola), las copias que solo se guardan con --copia, el ajuste copias-ficheros (las de los
# ficheros que cambia el programa por su cuenta) y copias [vaciar]. Todo en carpetas temporales.
# Uso: copias.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q '^function copies_command() {' "$SRC" || { echo "  ok    (sin copias de seguridad opcionales)"; exit 0; }
MAC=0; grep -qE '^    BASE_DIR=(/Applications|/Library/Nexum)$' "$SRC" && MAC=1
W=$(mktemp -d "$TMPBASE/w-copias.XXXX") || exit 1
trap 'chmod -R u+w "$W" 2> /dev/null; rm -rf "$W"' EXIT

# --- La carpeta: una sola variable, y la migracion de ~/lvm-copias ---
check "COPIES_DIR=\$HOME/nexum-backups y el ajuste en ~/.lvm-instalador/copias-ficheros" 'grep -qx "COPIES_DIR=\"\$HOME/nexum-backups\"" "$SRC" && grep -qx "COPIES_FILES_FLAG=\"\$LOG_DIR/copias-ficheros\"" "$SRC"'
check "la migracion, al arrancar: no con --simular, en las pruebas ni al pedir la version" 'grep -qx "    \*) \[ \"\$DRY\" -eq 0 \] && \[ -z \"\$TEST_DIR\" \] && copies_migrate ;;" "$SRC" && grep -qx "    version|--version|-v|acerca|about|novedades|-h|--help|--ayuda|construir-pila) ;;" "$SRC"'
extract "$SRC" copies_migrate copies_size_text copies_need_root copies_command copies_files_command || exit 1
H=$W/m1; mkdir -p "$H/lvm-copias/sub"; echo uno > "$H/lvm-copias/sub/a.sql.gz"; chmod 755 "$H/lvm-copias"
HOME=$H COPIES_DIR=$H/nexum-backups copies_migrate
check "migracion: ~/lvm-copias pasa a ~/nexum-backups, con lo que tenia y solo tuya" '[ ! -e "$H/lvm-copias" ] && [ "$(cat "$H/nexum-backups/sub/a.sql.gz")" = uno ] && [ "$(command stat -c %a "$H/nexum-backups")" = 700 ]'
H=$W/m2; mkdir -p "$H/lvm-copias" "$H/nexum-backups"; echo viejo > "$H/lvm-copias/v"; echo nuevo > "$H/nexum-backups/n"
HOME=$H COPIES_DIR=$H/nexum-backups copies_migrate
check "migracion: con las dos, no se toca ninguna" '[ "$(cat "$H/lvm-copias/v")" = viejo ] && [ "$(cat "$H/nexum-backups/n")" = nuevo ] && [ ! -e "$H/nexum-backups/v" ]'
H=$W/m3; mkdir -p "$H" "$W/otra"; echo fuera > "$W/otra/f"; ln -s "$W/otra" "$H/lvm-copias"
HOME=$H COPIES_DIR=$H/nexum-backups copies_migrate
check "migracion: un enlace ~/lvm-copias no se sigue ni se mueve" '[ -L "$H/lvm-copias" ] && [ ! -e "$H/nexum-backups" ] && [ "$(cat "$W/otra/f")" = fuera ]'
H=$W/m4; mkdir -p "$H"; echo f > "$H/lvm-copias"
HOME=$H COPIES_DIR=$H/nexum-backups copies_migrate
check "migracion: un fichero ~/lvm-copias (no carpeta), tampoco" '[ -f "$H/lvm-copias" ] && [ ! -e "$H/nexum-backups" ]'
if [ $MAC -eq 0 ]; then
    # El script entero, con otra carpeta personal
    H=$W/s1; mkdir -p "$H/lvm-copias"; echo uno > "$H/lvm-copias/a"
    env -u LVM_PRUEBA -u LVM_SIMULAR HOME=$H bash "$SRC" --simular copias > /dev/null 2>&1
    check "el script con --simular: no la renombra" '[ -d "$H/lvm-copias" ] && [ ! -e "$H/nexum-backups" ]'
    LVM_PRUEBA=$W/prueba HOME=$H bash "$SRC" copias > /dev/null 2>&1
    check "el script en las pruebas (LVM_PRUEBA): no la renombra" '[ -d "$H/lvm-copias" ] && [ ! -e "$H/nexum-backups" ]'
    env -u LVM_PRUEBA -u LVM_SIMULAR HOME=$H bash "$SRC" version > /dev/null 2>&1
    env -u LVM_PRUEBA -u LVM_SIMULAR HOME=$H bash "$SRC" novedades > /dev/null 2>&1
    check "el script con version o novedades (el empaquetador): no la renombra" '[ -d "$H/lvm-copias" ] && [ ! -e "$H/nexum-backups" ]'
    o=$(env -u LVM_PRUEBA -u LVM_SIMULAR HOME=$H bash "$SRC" copias 2>&1)
    check "el script al arrancar: la renombra" '[ ! -e "$H/lvm-copias" ] && [ "$(cat "$H/nexum-backups/a")" = uno ] && grep -q "1 fichero," <<< "$o"'
fi

# --- copias-ficheros [si|no] ---
LOG_DIR=$W/log COPIES_FILES_FLAG=$W/log/copias-ficheros DRY=0
o=$(copies_files_command)
check "copias-ficheros: apagado de partida" '[ ! -e "$COPIES_FILES_FLAG" ] && grep -q ": no" <<< "$o"'
o=$(DRY=1 copies_files_command si)
check "copias-ficheros si con --simular: no cambia nada" '[ ! -e "$COPIES_FILES_FLAG" ] && grep -q simulacion <<< "$o"'
o=$(copies_files_command si); rc=$?
check "copias-ficheros si: crea el ajuste (solo tuyo) y lo dice" '[ $rc -eq 0 ] && [ -f "$COPIES_FILES_FLAG" ] && [ "$(command stat -c %a "$COPIES_FILES_FLAG")" = 600 ] && grep -q ": si" <<< "$o"'
check "copias-ficheros sin nada: dice que esta encendido" 'copies_files_command | grep -q ": si"'
o=$(copies_files_command no); rc=$?
check "copias-ficheros no: lo quita" '[ $rc -eq 0 ] && [ ! -e "$COPIES_FILES_FLAG" ] && grep -q ": no" <<< "$o"'
check "copias-ficheros otra cosa: uso y error" 'o=$(copies_files_command quizas); [ $? -ne 0 ] && grep -q "Uso:" <<< "$o"'
ln -s "$W/fuera-ajuste" "$COPIES_FILES_FLAG"
copies_files_command si > /dev/null
check "copias-ficheros si: un enlace en su lugar no se sigue" '[ -f "$COPIES_FILES_FLAG" ] && [ ! -L "$COPIES_FILES_FLAG" ] && [ ! -e "$W/fuera-ajuste" ]'
rm -f "$COPIES_FILES_FLAG"
check "copias-ficheros: en las tareas de la ventana no pide la contraseña" 'grep -E "^        gui-\*\|.*\) ;;$" "$SRC" | grep -q "|copias-ficheros) ;;"'
check "las ordenes copias y copias-ficheros" 'grep -qx "    copias) copies_command \"\$2\" ;;" "$SRC" && grep -qx "    copias-ficheros) copies_files_command \"\$2\" ;;" "$SRC"'
if [ $MAC -eq 0 ]; then
    H=$W/s2; mkdir -p "$H" "$W/bin"
    printf '#!/bin/sh\necho "$@" >> %s/sudo.log\nexit 1\n' "$W" > "$W/bin/sudo"; chmod +x "$W/bin/sudo"
    o=$(env -u LVM_PRUEBA -u LVM_SIMULAR PATH="$W/bin:$PATH" LVM_TAREA=1 HOME=$H bash "$SRC" copias-ficheros si 2>&1); rc=$?
    check "el script, como tarea de la ventana: copias-ficheros si sin sudo" '[ $rc -eq 0 ] && [ -f "$H/.lvm-instalador/copias-ficheros" ] && [ ! -e "$W/sudo.log" ]'
    o=$(env -u LVM_PRUEBA -u LVM_SIMULAR PATH="$W/bin:$PATH" LVM_TAREA=1 HOME=$H bash "$SRC" copias 2>&1); rc=$?
    check "el script, como tarea de la ventana: copias sin sudo" '[ $rc -eq 0 ] && [ ! -e "$W/sudo.log" ] && grep -q "nexum-backups" <<< "$o"'
fi

# --- Las funciones que cambian ficheros por su cuenta miran el ajuste ---
for f in edit_hosts edit_vhosts ps_vhost wp_config ps_set_db ps_parameters ps_stale_cache secure_lampp secure_version; do
    body=$(awk -v n="$f" '$0 ~ "^function "n"\\(\\) \\{" {p=1} p {print} p && /^}/ {exit}' "$SRC")
    [ -z "$body" ] && continue
    check "$f: su copia solo con el ajuste copias-ficheros" 'grep -q "\[ -f \"\$COPIES_FILES_FLAG\" \]" <<< "$body" && ! grep -q "lvm-copias" <<< "$body"'
done

# edit_hosts --aplicar, de verdad (en un fichero de hosts de prueba, escribible: sin sudo)
extract "$SRC" edit_hosts || exit 1
browser_trust() { :; }
run() { "$@"; }
HOSTS_FILE=$W/hosts COPIES_DIR=$W/casa/nexum-backups
printf '127.0.0.1 localhost\n' > "$HOSTS_FILE"
printf '127.0.0.1 localhost\n127.0.0.1 tienda.local\n' > "$W/hosts.nuevo"
o=$(edit_hosts --aplicar "$W/hosts.nuevo" 2>&1); rc=$?
check "edit_hosts sin el ajuste: cambia el fichero sin guardar copia" '[ $rc -eq 0 ] && grep -q tienda.local "$HOSTS_FILE" && [ ! -e "$COPIES_DIR" ] && ! grep -q "Copia del" <<< "$o"'
: > "$COPIES_FILES_FLAG"
printf '127.0.0.1 localhost\n127.0.0.1 otra.local\n' > "$W/hosts.nuevo"
o=$(edit_hosts --aplicar "$W/hosts.nuevo" 2>&1); rc=$?
f=$(ls "$COPIES_DIR"/hosts-* 2> /dev/null | head -1)
check "edit_hosts con el ajuste: antes guarda el anterior en ~/nexum-backups" '[ $rc -eq 0 ] && grep -q otra.local "$HOSTS_FILE" && [ -n "$f" ] && grep -q tienda.local "$f" && grep -q "Copia del" <<< "$o" && [ "$(command stat -c %a "$COPIES_DIR")" = 700 ]'
rm -f "$COPIES_FILES_FLAG"

# --- Las que solo se guardan con --copia ---
check "importar-bd: sin --copia no guarda nada (y lo dice)" 'awk "/^function import_database\\(\\) \\{/,/^}/" "$SRC" | grep -q "create=0 backup=0 " && awk "/^function import_database\\(\\) \\{/,/^}/" "$SRC" | grep -q "Sin copia:"'
check "copiar-bd --sustituir: la copia solo con --copia" 'awk "/^function copy_database\\(\\) \\{/,/^}/" "$SRC" | grep -q -- "--copia) backup=1"'
check "reparar-bd-sistema --copia" 'grep -q "reparar-bd-sistema) repair_db_system \"\$2\" ;;" "$SRC" && awk "/^function repair_db_system\\(\\) \\{/,/^}/" "$SRC" | grep -q "\[ \"\$1\" == \"--copia\" \] && copy=1"'
check "docker-pasar --copia" 'grep -q "docker-pasar) docker_pass \"\$2\" \"\$3\" ;;" "$SRC" && awk "/^function docker_pass\\(\\) \\{/,/^}/" "$SRC" | grep -q "\[ \"\$2\" == \"--copia\" \] && copy=1"'
check "actualizar y componentes-actualizar --copia (las BBDD de una version que empieza vacia)" 'grep -q "rehacer|actualizar) cli_rebuild \"\$2\" \"\$3\" ;;" "$SRC" && grep -q "componentes-actualizar) components_update \"\$2\" ;;" "$SRC" && awk "/^function install_stack\\(\\) \\{/,/^}/" "$SRC" | grep -q "STACK_DB_COPY:-0}\" -eq 1 \]; then"'
[ $MAC -eq 0 ] && check "actualizar-a --copia (lo que se vuelve a compilar en su carpeta)" 'grep -q "actualizar-a) upgrade_to \"\$2\" \"\$3\" \"\$4\" ;;" "$SRC"'
check "actualizar-proyecto --copia: sin ella, lo sustituido no se guarda" 'grep -q "            --copia) backup=(--copia) ;;" "$SRC" && grep -q "Sin copia: lo sustituido o quitado" "$SRC"'

# reparar-bd-sistema de verdad (con mysql_upgrade y el volcado de prueba)
extract "$SRC" repair_db_system || exit 1
V=$W/v; mkdir -p "$V/bin" "$V/var/mysql" "$V/xamppfiles/var/mysql" "$V/xamppfiles/mysql/bin"
for b in mysql_upgrade mysqldump; do printf '#!/bin/sh\necho "%s $*" >> %s/mdb.log\necho "-- volcado de mysql"\n' "$b" "$W" > "$V/bin/$b"; chmod +x "$V/bin/$b"; done
cp "$V/bin/mysql_upgrade" "$V/xamppfiles/mysql/bin/mariadb-upgrade"; cp "$V/bin/mysqldump" "$V/xamppfiles/mysql/bin/mariadb-dump"
# (el stat del Mac es stat -f %Su)
[ $MAC -eq 1 ] && stat() { if [ "$1" == -f ]; then command stat -c %U "$3"; else command stat "$@"; fi; }
active_dir() { echo "$V"; }; lampp_running() { true; }; wait_mariadb() { true; }; db_error_log() { :; }
OUTDATED=1; db_system_outdated() { [ $OUTDATED -eq 1 ] && { OUTDATED=0; return 0; }; return 1; }
version_name() { basename "$1"; }
DB_SAFE=(env); DB_CLIENT=/bin/true
COPIES_DIR=$W/casa3/nexum-backups
o=$(repair_db_system 2>&1); rc=$?
OUTDATED=1
check "reparar-bd-sistema sin --copia: las pone al dia sin guardar nada, y lo dice" '[ $rc -eq 0 ] && grep -q "Sin copia" <<< "$o" && [ ! -e "$COPIES_DIR" ] && grep -q "mysql_upgrade" "$W/mdb.log" && ! grep -q mysqldump "$W/mdb.log"'
o=$(repair_db_system --copia 2>&1); rc=$?
check "reparar-bd-sistema --copia: antes la copia de la base mysql en ~/nexum-backups" '[ $rc -eq 0 ] && ls "$COPIES_DIR"/*-mysql-sistema-*.sql.gz > /dev/null 2>&1 && grep -q mysqldump "$W/mdb.log"'
unset -f active_dir lampp_running wait_mariadb db_error_log db_system_outdated version_name stat

# --- copias [vaciar] ---
C=$W/casa2/nexum-backups SUDO=""
o=$(COPIES_DIR=$C copies_command)
check "copias sin carpeta: lo dice y no la crea" '[ $? -eq 0 ] && grep -q "No hay copias" <<< "$o" && [ ! -e "$C" ]'
mkdir -p -m 700 "$C/sub" "$W/fuera"; echo 1 > "$C/a.sql.gz"; echo 2 > "$C/sub/b"; head -c 3000 /dev/zero > "$C/sub/c"
echo intacto > "$W/fuera/f"; ln -s "$W/fuera" "$C/enlace"
o=$(COPIES_DIR=$C copies_command)
check "copias: cuantos ficheros hay y cuanto ocupan" 'grep -q "3 ficheros" <<< "$o" && grep -qE "[0-9],?[0-9]* (KB|MB)" <<< "$o"'
o=$(COPIES_DIR=$C DRY=1 copies_command vaciar)
check "copias vaciar con --simular: no borra nada" '[ -f "$C/a.sql.gz" ] && [ -f "$C/sub/c" ] && grep -q simulacion <<< "$o"'
o=$(COPIES_DIR=$C copies_command vaciar); rc=$?
check "copias vaciar: borra todo lo de dentro y la carpeta se queda" '[ $rc -eq 0 ] && [ -d "$C" ] && [ -z "$(ls -A "$C")" ] && grep -q "borradas" <<< "$o"'
check "copias vaciar: un enlace de dentro se borra, no lo que hay al otro lado" '[ "$(cat "$W/fuera/f")" = intacto ]'
o=$(COPIES_DIR=$C copies_command vaciar)
check "copias vaciar en una carpeta vacia: nada que borrar" '[ $? -eq 0 ] && grep -q "vacia" <<< "$o"'
ln -s "$W/fuera" "$W/enlace-copias"
o=$(COPIES_DIR=$W/enlace-copias copies_command vaciar); rc=$?
check "copias vaciar: si la carpeta es un enlace, no se toca" '[ $rc -ne 0 ] && [ "$(cat "$W/fuera/f")" = intacto ]'
check "copias otra cosa: uso y error" 'o=$(COPIES_DIR=$C copies_command todo); [ $? -ne 0 ] && grep -q "Uso:" <<< "$o"'
# Copias que tu usuario no puede borrar (como las de root): sin sudo, lo dice; con sudo, solo dentro
mkdir -p "$C/root"; echo r > "$C/root/x"; echo y > "$C/suelto"; chmod 555 "$C/root"
o=$(COPIES_DIR=$C copies_command vaciar); rc=$?
check "copias vaciar: lo que no se puede borrar, lo dice (y lo demas se borra)" '[ $rc -ne 0 ] && grep -q "No se ha podido borrar todo" <<< "$o" && [ ! -e "$C/suelto" ] && [ -f "$C/root/x" ]'
sudo() { echo "sudo $*" >> "$W/sudo2.log"; [ "$1" == find ] && [ "$2" == "$C" ] || return 1; chmod -R u+w "$2"; "$@"; }
o=$(COPIES_DIR=$C SUDO=sudo copies_command vaciar); rc=$?
check "copias vaciar: con sudo, solo con find dentro de la carpeta (sin pasar a otros discos)" '[ $rc -eq 0 ] && [ -z "$(ls -A "$C")" ] && grep -qx "sudo find $C -xdev -mindepth 1 -delete" "$W/sudo2.log" && [ "$(grep -c . "$W/sudo2.log")" = 1 ]'
unset -f sudo

exit $fail
