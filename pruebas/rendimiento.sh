#!/bin/bash
# Rendimiento de la ventana (Linux 1.56.16): la revision de seguridad de las versiones (unsecured_versions)
# se guarda mientras no cambien sus ficheros; las cuatro ordenes de cada 20 s van en una (gui-vuelta); los
# callbacks de run_quick se llaman una sola vez (un callback que devolvia datos se quedaba dando vueltas a
# toda CPU), Proyectos solo se rehace si cambia algo, al cerrar la ventana se sale del todo y al abrirla
# se cierran las de versiones anteriores. Uso: rendimiento.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q '^function gui_round() {' "$SRC" || { echo "  ok    (sin gui-vuelta)"; exit 0; }
if grep -q "LVM_SWIFT" "$SRC"; then
    # (Mac: su cache usa find y stat de macOS, que aqui no estan: se comprueba lo que se puede)
    check "Mac: gui-vuelta, las cuatro de cada 20 s en una orden" 'grep -q "^    gui-vuelta) gui_round ;;" "$SRC" && grep -q "runQuick(\[\"gui-vuelta\"\]) { rc, out in self.onRound(rc, out) }" "$SRC"'
    check "Mac: las fechas de las BBDD de todas las versiones en un solo python3" 'grep -q "db_dates --varias \"\${dates\[@\]}\"" "$SRC" && ! grep -q "db_dates \"\$dir/xamppfiles/var/mysql\" | sed" "$SRC"'
    check "Mac: la revision de seguridad, guardada mientras no cambien sus ficheros" 'grep -q "xargs -0 stat -f .%c %m %u %g %p %N." "$SRC" && grep -q "if \[ \"\$EUID\" -ne 0 \] && \[ -z \"\${LVM_SIN_CACHE:-}\" \]; then" "$SRC"'
    check "Mac: al cerrar la ventana la aplicacion se cierra (con una tarea en marcha, al acabarla)" 'grep -q "return !(AppModel.current?.busy ?? false)" "$SRC" && grep -q "DispatchQueue.main.async { NSApp.terminate(nil) }" "$SRC"'
    exit $fail
fi
W=$(mktemp -d "$TMPBASE/w-rendimiento.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
extract "$SRC" unsecured_versions || exit 1

# --- La cache de la revision de seguridad (con un SECURE_PY falso que cuenta sus llamadas) ---
unset TEST_DIR LVM_SIN_CACHE
LOG_DIR=$W/log APP_VERSION=9.9.9 SECURE_MARK=etc/lvm-seguridad
host_vhost() { HOST_VHOST=x; }
mail_secure_spec() { echo correo; }
lampp_dirs() { echo "$W/v1 $W/v2"; }
SECURE_PY='import os, sys
open(os.environ["CUENTA"], "a").write("x\n")
if "ABIERTO" in open(os.path.join(sys.argv[1], "etc/httpd.conf")).read(): print("Listen")'
export CUENTA=$W/cuenta
for v in v1 v2; do mkdir -p "$W/$v/etc/extra" && echo "Listen 127.0.0.1:80" > "$W/$v/etc/httpd.conf"; done
echo "ABIERTO" > "$W/v1/etc/httpd.conf"
calls() { wc -l < "$CUENTA" 2> /dev/null || echo 0; }

out=$(unsecured_versions)
check "la primera vez se revisa cada version" '[ "$(calls)" -eq 2 ] && [ "$out" == "$W/v1" ]'
out=$(unsecured_versions)
check "sin cambios, la respuesta de antes y sin revisar nada" '[ "$(calls)" -eq 2 ] && [ "$out" == "$W/v1" ]'
echo "Listen 127.0.0.1:80" > "$W/v1/etc/httpd.conf"
out=$(unsecured_versions)
check "si cambia un fichero de una version, se revisa otra vez" '[ "$(calls)" -eq 4 ] && [ -z "$out" ]'
chmod 666 "$W/v2/etc/httpd.conf"
unsecured_versions > /dev/null
check "si cambian sus permisos, tambien" '[ "$(calls)" -eq 6 ]'
touch "$W/v2/etc/extra/nuevo.conf"
unsecured_versions > /dev/null
check "y si aparece un fichero nuevo" '[ "$(calls)" -eq 8 ]'
touch -d "11 minutes ago" "$LOG_DIR/cache/versiones-abiertas"
unsecured_versions > /dev/null
check "con la respuesta de hace mas de 10 min, se revisa otra vez" '[ "$(calls)" -eq 10 ]'
LVM_SIN_CACHE=1 unsecured_versions > /dev/null
check "con LVM_SIN_CACHE, siempre se revisa" '[ "$(calls)" -eq 12 ]'
check "con root no se usa la cache" 'grep -q "if \[ \"\$EUID\" -ne 0 \] && \[ -z \"\${LVM_SIN_CACHE:-}\" \]; then" <<< "$(declare -f unsecured_versions)"'

# --- gui-vuelta y la ventana ---
check "gui-vuelta: las cuatro de cada 20 s, cada una en su subshell y con su codigo" 'grep -q "for part in gui-datos:gui_data gui-hosts:gui_hosts gui-servicios:gui_services gui-proyectos:gui_projects; do" "$SRC" && grep -q "^    gui-vuelta) gui_round ;;" "$SRC"'
check "ventana: la vuelta de cada 20 s es una sola orden" 'grep -q "run_quick(\[\"gui-vuelta\"\], self.on_round)" "$SRC"'
check "ventana: run_quick entrega la respuesta una sola vez" 'grep -q "GLib.idle_add(lambda: (callback(\*args), False)\[1\])" "$SRC" && ! grep -q "GLib.idle_add(callback," "$SRC"'
check "las fechas de las BBDD de todas las versiones en un solo python3" 'grep -q "db_dates --varias \"\${dates\[@\]}\"" "$SRC"'
check "ventana: Proyectos solo se rehace si cambia algo" 'grep -q "            self.nv_projects_refresh()" "$SRC" && grep -q "        self.nv_projects_refresh()" "$SRC"'
check "ventana: sin ninguna ventana se sale, y a los 5 s se corta si algo lo retiene" 'grep -q "self.connect(\"window-removed\", lambda app, _w: app.get_windows() or self.nv_exit())" "$SRC" && grep -A8 "    def nv_exit(self):" "$SRC" | grep -q "os._exit(0)" && grep -q "    os._exit(rc or 0)" "$SRC"'
check "ventana: al abrir se cierran las de versiones anteriores (arrancadas antes de instalar el script)" 'grep -q "    close_stale_windows(sys.argv\[1\] if len(sys.argv) > 1 else \"\")" "$SRC" && grep -q "if started < installed - 1:" "$SRC"'
exit $fail
