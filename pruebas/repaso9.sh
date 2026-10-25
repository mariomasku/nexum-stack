#!/bin/bash
# Pruebas del noveno repaso de seguridad (Linux 1.45.0 / Mac 1.33.0): el cliente de MariaDB sin
# ~/.my.cnf, programas que leen tu configuracion fuera de la terminal (no_tty), la contraseña solo
# para un sudo de verdad (Linux), \r en /etc/hosts, el dominio de una tienda montada desde un
# repositorio, Listen abierto en los vhosts compartidos, PHP_TIMEZONE, ServerAdmin, importar-bd
# --proyecto, rangos de bash con el idioma del equipo, .pid del script lampp (Linux), versiones de
# php.net y, en el Mac, Apartar sin root, rutas por el enlace /Applications/XAMPP y versiones
# revisadas por dentro.
# Uso: repaso9.sh <lvm-instalador.sh>   (Linux o Mac: lo que es de una sola plataforma se salta)
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-r9.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
MAC=0; grep -qE '^    BASE_DIR=(/Applications|/Library/Nexum)$' "$SRC" && MAC=1
getvar() { ( eval "$(sed -n "/^$1='/,/^'\$/p" "$SRC")"; printf '%s.' "${!1}" ); }

# --- El cliente de MariaDB y mysqldump, sin ~/.my.cnf ni $MYSQL_HOME/my.cnf
eval "$(grep -m1 '^DB_SAFE=(' "$SRC")"
mkdir -p "$W/casa"
printf '[client]\nplugin-dir=%s/plugins\ndefault-auth=prueba\n' "$W" > "$W/casa/.my.cnf"
cp "$W/casa/.my.cnf" "$W/casa/my.cnf"
for b in mysql mysqldump; do
    out=$(HOME=$W/casa MYSQL_HOME=$W/casa LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib "${DB_SAFE[@]}" /opt/lampp-8.2.4/bin/$b --print-defaults 2>&1)
    check "$b de XAMPP con DB_SAFE: sin plugin-dir ni default-auth de tu carpeta" '[ -n "$out" ] && ! grep -q "plugin-dir\|default-auth" <<< "$out"'
done
out=$(HOME=$W/casa LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib /opt/lampp-8.2.4/bin/mysql --print-defaults 2>&1)
check "(sin DB_SAFE si los leeria: la prueba vale)" 'grep -q "plugin-dir" <<< "$out"'
bare=$(grep -n '"\$DB_CLIENT" -[uN]\|"\$dump" -uroot' "$SRC" | grep -v 'DB_SAFE' | cut -d: -f1 | tr '\n' ' ')
check "todas las llamadas al cliente llevan DB_SAFE${bare:+ (lineas: $bare)}" '[ -z "$bare" ]'
check "mysqldump de exportar-bd con DB_SAFE" 'grep -q "dump=(\"\${DB_SAFE\[@\]}\" \"\${LVM_BD_VOLCADO" "$SRC"'

# --- no_tty: sin terminal de control y sin la terminal en sus descriptores
NO_TTY_PY=$(getvar NO_TTY_PY); NO_TTY_PY=${NO_TTY_PY%.}
extract "$SRC" no_tty || exit 1
out=$(python3 -I -c '
import os, pty, sys, subprocess
m, s = pty.openpty()
p = subprocess.Popen(["bash", "-c", sys.argv[1]], stdin=s, stdout=s, stderr=s, start_new_session=True,
                     preexec_fn=lambda: __import__("fcntl").ioctl(0, __import__("termios").TIOCSCTTY, 0))
os.close(s)
data = b""
while True:
    try:
        d = os.read(m, 4096)
    except OSError:
        break
    if not d:
        break
    data += d
p.wait()
print(data.decode(errors="replace"))' "$(declare -p NO_TTY_PY); $(declare -f no_tty)
no_tty sh -c 'if (exec 3< /dev/tty) 2> /dev/null; then echo TTY-ABIERTA; else echo TTY-NO; fi; [ -t 1 ] && echo SALIDA-TTY || echo SALIDA-TUBERIA'")
check "no_tty: no puede abrir /dev/tty" 'grep -q TTY-NO <<< "$out" && ! grep -q TTY-ABIERTA <<< "$out"'
check "no_tty: su salida no es la terminal (tuberia)" 'grep -q SALIDA-TUBERIA <<< "$out"'
no_tty sh -c 'exit 3'; rc=$?
check "no_tty: devuelve el codigo de la orden" '[ $rc -eq 3 ]'
check "el clon va con no_tty, StrictHostKeyChecking=yes y sin git-lfs" 'grep -q "no_tty git -c protocol.allow=never" "$SRC" && grep -q "StrictHostKeyChecking=yes" "$SRC" && ! grep -q "accept-new" "$SRC" && grep -q "GIT_LFS_SKIP_SMUDGE=1" "$SRC"'
check "las claves de GitHub, GitLab y Bitbucket estan fijadas" '[ "$(getvar GIT_KNOWN_HOSTS | grep -c "^\(github.com\|gitlab.com\|bitbucket.org\) ssh-ed25519 ")" -eq 3 ]'
check "git ls-remote sin terminal" 'grep -q "NO_TTY_PY\" git -c credential.helper= ls-remote" "$SRC"'
nocurl=$(grep -n '\bcurl --proto' "$SRC" | cut -d: -f1 | tr '\n' ' ')
check "todas las descargas con curl -q (sin ~/.curlrc)${nocurl:+ (lineas: $nocurl)}" '[ -z "$nocurl" ] && grep -q "curl -q --proto =https" "$SRC"'
check "CERTS_PY ejecuta certutil/security en su sesion y sin la entrada de la terminal" 'grep -q "start_new_session=True, \*\*kw" "$SRC"'
[ $MAC -eq 0 ] && check "Linux: certutil -D con no_tty" 'grep -q "run no_tty certutil -D" "$SRC"'

# --- Linux: la contraseña solo para un sudo de root de la tarea, en su terminal y sin hijos
if [ $MAC -eq 0 ]; then
    cp /bin/sleep "$W/sudo"
    out=$(python3 -I - "$SRC" "$W/sudo" <<'PY'
import os, pty, fcntl, termios, subprocess, time, sys, re
src = open(sys.argv[1]).read()
m = re.search(r"    def sudo_asking\(self\):.*?return bool\(found\)\n", src, re.S)
ns = {"os": os}
exec("class T:\n" + m.group(0), ns)
def probe(cmd):
    master, slave = pty.openpty()
    t = ns["T"](); t.tty = os.fstat(slave).st_rdev
    t.proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, start_new_session=True,
                              preexec_fn=lambda: fcntl.ioctl(0, termios.TIOCSCTTY, 0))
    os.close(slave)
    time.sleep(1)
    r = t.sudo_asking()
    os.system("pkill -P %d 2> /dev/null" % t.proc.pid)
    t.proc.kill(); t.proc.wait(); os.close(master)
    return r
print("falso", probe(["sh", "-c", "%s 3; true" % sys.argv[2]]))
print("ninguno", probe(["sh", "-c", "sleep 3; true"]))
# Un sudo de verdad pidiendo la contraseña (solo si este equipo la pide: con NOPASSWD no espera)
if subprocess.run(["sudo", "-n", "true"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                  stderr=subprocess.DEVNULL).returncode != 0:
    print("real", probe(["sh", "-c", "sudo -k -p MARCA true; true"]))
PY
)
    check "Linux: un programa tuyo que se llame sudo no recibe la contraseña" 'grep -q "^falso False" <<< "$out"'
    check "Linux: sin sudo esperando, no se manda" 'grep -q "^ninguno False" <<< "$out"'
    grep -q '^real' <<< "$out" && check "Linux: a un sudo de verdad esperando si se le manda" 'grep -q "^real True" <<< "$out"'
    check "Linux: se mira antes de abrir el cuadro y otra vez antes de mandarla" '[ "$(grep -c "not self.sudo_asking()" "$SRC")" -eq 2 ]'
fi

# --- /etc/hosts: un \r suelto no se salta la comprobacion; \r\n sigue valiendo
extract "$SRC" edit_hosts run || exit 1
DRY=0 HOSTS_FILE=$W/hosts
printf '127.0.0.1 localhost\n' > "$HOSTS_FILE"
printf '127.0.0.1 localhost\n203.0.113.7\rgithub.com\n' > "$W/copia-cr"
out=$(HOME=$W edit_hosts --aplicar "$W/copia-cr" 2>&1); rc=$?
check "hosts: una linea con \\r en medio no se aplica" '[ $rc -ne 0 ] && ! grep -q github "$HOSTS_FILE"'
printf '127.0.0.1 localhost\r\n127.0.0.1 nueva.local\r\n' > "$W/copia-crlf"
out=$(HOME=$W edit_hosts --aplicar "$W/copia-crlf" 2>&1); rc=$?
check "hosts: un fichero con \\r\\n (Windows) si se aplica" '[ $rc -eq 0 ] && grep -q nueva.local "$HOSTS_FILE"'
printf '127.0.0.1 localhost\n203.0.113.7 github.com\n' > "$W/copia-otra"
out=$(HOME=$W edit_hosts --aplicar "$W/copia-otra" 2>&1); rc=$?
check "hosts: un dominio a otra IP sigue sin aplicarse" '[ $rc -ne 0 ] && ! grep -q github "$HOSTS_FILE"'

# --- Rangos de bash: solo ASCII aunque el equipo este en español (tambien con LC_ALL)
if locale -a 2> /dev/null | grep -qi '^es_ES.utf-\?8$'; then
    head=$(sed -n '/^\[ -n "\${LC_ALL:-}" \] && export LANG=\$LC_ALL && unset LC_ALL$/,/^export LC_COLLATE=C$/p' "$SRC")
    for v in LANG LC_ALL; do
        r=$(env "$v=es_ES.UTF-8" bash -c "$head"'
            [[ "café" =~ ^[A-Za-z0-9]+$ ]] && echo acepta1; [[ "x²" =~ ^[A-Za-z0-9]+$ ]] && echo acepta2; echo fin')
        check "con $v=es_ES.UTF-8, [A-Za-z0-9] no acepta é ni ²" '[ "$r" = fin ]'
    done
fi

# --- PHP_TIMEZONE: solo un nombre de zona horaria
tzblock=$(sed -n '/^PHP_TIMEZONE=\${PHP_TIMEZONE:-Europe\/Madrid}$/,/^fi$/p' "$SRC")
for tz in $'Europe/Madrid\nextension=/tmp/x.so' 'Europe/Madrid extension=x' '../../x'; do
    r=$(PHP_TIMEZONE=$tz bash -c "$tzblock"'; printf %s "$PHP_TIMEZONE"' 2> /dev/null)
    check "PHP_TIMEZONE no valido ($(printf %q "$tz")) -> Europe/Madrid" '[ "$r" = Europe/Madrid ]'
done
for tz in America/Argentina/Buenos_Aires Etc/GMT+3 UTC; do
    r=$(PHP_TIMEZONE=$tz bash -c "$tzblock"'; printf %s "$PHP_TIMEZONE"' 2> /dev/null)
    check "PHP_TIMEZONE valido se queda ($tz)" '[ "$r" = "$tz" ]'
done

# --- ServerAdmin: el correo de git, sin \ al final ni comillas
extract "$SRC" server_admin || exit 1
for mail in 'a@b\' 'a"b@c.com' 'x@y z'; do
    sudo_user_git_email() { printf '%s' "$mail"; }
    git() { printf '%s' "$mail"; }; dscl() { :; }
    r=$(USER=yo SUDO_USER="" server_admin)
    check "ServerAdmin con correo raro ($mail) -> yo@localhost" '[ "$r" = yo@localhost ]'
done
sudo_user_git_email() { echo 'ana.p+web@hexer.dev'; }; git() { echo 'ana.p+web@hexer.dev'; }
r=$(USER=yo SUDO_USER="" server_admin)
check "ServerAdmin con un correo normal" '[ "$r" = ana.p+web@hexer.dev ]'
unset -f git dscl sudo_user_git_email

# --- importar-bd --proyecto: carpeta valida (sin .., . ni saltos de linea)
extract "$SRC" import_database valid_project db_valid_name || exit 1
HTDOCS_DIR=$W/htdocs DB_SYSTEM="mysql|sys"
mkdir -p "$HTDOCS_DIR/bien" "$HTDOCS_DIR/mal
linea"
echo "SELECT 1;" > "$W/v.sql"
for p in .. . $'mal\nlinea'; do
    out=$(import_database "$W/v.sql" base1 --proyecto "$p" 2>&1); rc=$?
    check "importar-bd --proyecto $(printf %q "$p"): no se acepta" '[ $rc -ne 0 ] && grep -q "proyecto\|carpeta" <<< "$out"'
done

# --- Listen abierto en los vhosts compartidos: se ve, y la version no se arranca
extract "$SRC" vhosts_open_listen || exit 1
realpath_f() { readlink -f "$1"; }
printf '<VirtualHost *:80>\n</VirtualHost>\nListen 8080\n  Listen 127.0.0.1:8081\nListen [::1]:80\n#Listen 9090\nListen 0.0.0.0:81 http\nListen "192.168.1.2:82"\n' > "$W/vh.conf"
out=$(VHOSTS_FILE=$W/vh.conf vhosts_open_listen)
check "Listen 8080, 0.0.0.0 y la IP de la red se ven" '[ "$(grep -c . <<< "$out")" -eq 3 ] && grep -q "Linea 3: Listen 8080" <<< "$out"'
printf 'Listen \\\n84\nListen '"'"'85'"'"'\nListen\v86\n\fListen 87\nListen\r88\nIncludeOptional /x/*.conf\nListen 127.0.0.1:89\n' > "$W/vh3.conf"
out=$(VHOSTS_FILE=$W/vh3.conf vhosts_open_listen)
check "Listen partido con \\, entre comillas simples, con \\v, \\f o \\r, e Include: se ven (6)" '[ "$(grep -c . <<< "$out")" -eq 6 ] && ! grep -q 89 <<< "$out" && ! grep -q $'"'"'[\x01-\x1f]'"'"' <<< "$out"'
printf '<VirtualHost *:80>\n</VirtualHost>\nListen 127.0.0.1:8081\nListen localhost:8082\n' > "$W/vh2.conf"
check "sin Listen abierto, nada" '[ -z "$(VHOSTS_FILE=$W/vh2.conf vhosts_open_listen)" ]'
fn=secure_lampp; [ $MAC -eq 1 ] && fn=secure_version
check "$fn no arranca (2) con un Listen abierto" 'sed -n "/^function $fn() {/,/^}/p" "$SRC" | grep -q "open=\$(vhosts_open_listen)" && sed -n "/^function $fn() {/,/^}/p" "$SRC" | grep -A8 "open=\$(vhosts_open_listen)" | grep -q "return 2"'

# --- Montar nuevo proyecto: el dominio de la base de una tienda clonada no se falsea solo
extract "$SRC" load_project_domain || exit 1
is_prestashop() { true; }; is_wordpress() { false; }; ps_parameters() { :; }; ps_set_db() { :; }
ps_first_load() { :; }; saved_project_db() { echo base; }; ps_config() { echo config; }
ps_domain() { echo paypal.com; }; vhost_points_to() { false; }; domain_fits_folder() { true; }
ps_vhost() { echo "VHOST $2"; }; hosts_fake() { echo "HOSTS $*"; }; custom_domain() { :; }
REPO_PROJECTS_FILE=$W/montados
printf 'otra\npaypal-checkout\n' > "$REPO_PROJECTS_FILE"
out=$(load_project_domain paypal-checkout base)
check "tienda montada desde un repositorio: su dominio no se falsea ni lleva vhost" '! grep -q "VHOST" <<< "$out" && grep -q "^HOSTS cargar$" <<< "$out" && grep -q "Nuevo proyecto con dominio falseado" <<< "$out"'
vhost_points_to() { true; }
out=$(load_project_domain paypal-checkout base)
check "... salvo si ya tiene su vhost (creado a mano en Hosts)" 'grep -q "VHOST paypal.com" <<< "$out" && grep -q "^HOSTS cargar paypal.com$" <<< "$out"'
vhost_points_to() { false; }
out=$(load_project_domain tienda-propia base)
check "una tienda que no se ha montado desde un repositorio, como antes" 'grep -q "VHOST paypal.com" <<< "$out"'
check "montar-proyecto apunta la carpeta en REPO_PROJECTS_FILE" 'sed -n "/^function mount_project() {/,/^}/p" "$SRC" | grep -q "\"\$REPO_PROJECTS_FILE\""'

# --- copiar-bd a una version que ya la tiene: solo con --sustituir, y antes una copia de la suya
extract "$SRC" copy_database || exit 1
LOG=$W/log.txt
db_valid_name() { true; }; valid_version_name() { true; }; data_owner() { :; }
# (la de destino es la activa y esta en marcha: se carga en su MariaDB)
if [ $MAC -eq 1 ]; then active_dir() { echo "$W/v/XAMPP-8.4"; }; else active_dir() { echo /opt/lampp-8.4; }; fi
realpath_f() { echo "$1"; }; lampp_running() { true; }; db_temp_stop() { :; }; php_version() { echo 8.4; }
version_name() { basename "$1"; }
db_names() { echo wp_x; }
export_database() { echo "EXPORT $1 $2 $3" >> "$LOG"; : > "$2"; }
import_database() { echo "IMPORT ${*:2}" >> "$LOG"; }
mkdir -p "$W/v/lampp-8.2.4" "$W/v/lampp-8.4" "$W/v/XAMPP-8.2" "$W/v/XAMPP-8.4" "$W/casa2"
src=8.2.4; [ $MAC -eq 1 ] && src=8.2
: > "$LOG"
out=$(TEST_DIR=$W/v BASE_DIR=$W/v HOME=$W/casa2 LOG_DIR=$W/casa2/.lvm DRY=0 copy_database wp_x $src 8.4 2>&1); rc=$?
check "copiar-bd a una version que ya la tiene, sin --sustituir: no hace nada" '[ $rc -ne 0 ] && [ ! -s "$LOG" ] && grep -q -- "--sustituir" <<< "$out"'
out=$(TEST_DIR=$W/v BASE_DIR=$W/v HOME=$W/casa2 LOG_DIR=$W/casa2/.lvm DRY=0 copy_database wp_x $src 8.4 --sustituir 2>&1); rc=$?
check "con --sustituir: primero la copia de la de destino en ~/lvm-copias" '[ "$(head -1 "$LOG" | cut -d" " -f1,2,4)" = "EXPORT wp_x 8.4" ] && head -1 "$LOG" | grep -q "/lvm-copias/.*8.4-wp_x-antes-de-copiar-"'
check "... despues la de origen, y se carga con --crear --sin-copia (la copia ya esta)" '[ "$(sed -n 2p "$LOG" | cut -d" " -f1,2,4)" = "EXPORT wp_x $src" ] && [ "$(sed -n 3p "$LOG")" = "IMPORT wp_x --crear --sin-copia" ] && [ $rc -eq 0 ]'
export_database() { echo "EXPORT $1 $2 $3" >> "$LOG"; [ "$3" != 8.4 ]; }
: > "$LOG"
out=$(TEST_DIR=$W/v BASE_DIR=$W/v HOME=$W/casa2 LOG_DIR=$W/casa2/.lvm DRY=0 copy_database wp_x $src 8.4 --sustituir 2>&1); rc=$?
check "si no se puede guardar la copia de la de destino, no se carga nada" '[ $rc -ne 0 ] && ! grep -q IMPORT "$LOG"'
db_names() { [[ "$1" == *8.2* ]] && echo wp_x; }
: > "$LOG"
TEST_DIR=$W/v BASE_DIR=$W/v HOME=$W/casa2 LOG_DIR=$W/casa2/.lvm DRY=0 copy_database wp_x $src 8.4 --sustituir > /dev/null 2>&1
check "con --sustituir a una version que no la tiene: sin copia y con --crear" '[ "$(grep -c EXPORT "$LOG")" = 1 ] && grep -qx "IMPORT wp_x --crear" "$LOG"'
unset -f export_database import_database db_names db_valid_name valid_version_name data_owner active_dir realpath_f lampp_running db_temp_stop php_version version_name

# --- Versiones de php.net: solo X.Y.Z (un | descolocaria las lineas de la ventana)
if [ $MAC -eq 0 ]; then
    extract "$SRC" php_all_releases || exit 1
    fetch() {
        case "$1" in
            *version=8\&*) printf '{"8.4.1": {"date": "21 Nov 2024", "tags": ["security"], "source": [{"filename": "php-8.4.1.tar.xz", "sha256": "ab"}]}, "8.4.2|B|x": {"date": "1 Dec 2024", "source": [{"filename": "a.tar.xz", "sha256": "ab"}]}, "8.4.3\\n9.9.9": {"source": [{"filename": "a.tar.xz", "sha256": "ab"}]}}' ;;
            *) echo '{"error": "x"}' ;;
        esac
    }
    out=$(php_all_releases)
    check "php.net: solo las versiones X.Y.Z" '[ "$out" = "8.4.1 2024-11-21 seguridad" ]'
else
    extract "$SRC" php_releases || exit 1
    STACK_MATRIX=("8.4|x")
    fetch() { printf '{"version": "8.4.2|B|x", "date": "1 Dec 2024", "source": [{"filename": "a.tar.xz", "sha256": "%s"}]}' "$(printf 'a%.0s' $(seq 64))"; }
    check "php.net (Mac): una version con | no sale" '[ -z "$(php_releases)" ]'
    fetch() { printf '{"version": "8.4.2", "date": "1 Dec 2024", "source": [{"filename": "a.tar.xz", "sha256": "%s"}]}' "$(printf 'a%.0s' $(seq 64))"; }
    check "php.net (Mac): una version normal si" '[ "$(php_releases | cut -d" " -f1,2)" = "8.4 8.4.2" ]'
fi
extract "$SRC" php_supported php_branch_states || exit 1
fetch() { echo '{"8": {"8.4": {}, "8.5|x": {}}}'; }
check "ramas con soporte: solo X.Y" '[ "$(php_supported)" = 8.4 ]'
fetch() { echo '[{"branch": "8.4", "state": "stable"}, {"branch": "8.5|y", "state": "stable"}, {"branch": "8.3", "state": "x|y"}]'; }
check "estado de las ramas: solo X.Y y estados conocidos" '[ "$(php_branch_states)" = "8.4|stable||" ]'

# --- Linux: el script lampp (como root) solo cierra el MariaDB de su .pid
if [ $MAC -eq 0 ]; then
    extract "$SRC" pid_in || exit 1
    for c in -1 1 0 abc 12x ''; do
        printf '%s\n' "$c" > "$W/p.pid"
        check "pid_in rechaza $(printf %q "$c")" '! pid_in "$W/p.pid" > /dev/null'
    done
    printf '4242\n' > "$W/p.pid"
    check "pid_in acepta un numero" '[ "$(pid_in "$W/p.pid")" = 4242 ]'
    check "stop_mysql mira que sea el MariaDB antes de kill" 'grep -q "p=\$(pid_in \"\$MYSQL_PID\") && \[\[ \"\$(cat \"/proc/\$p/comm\"" "$SRC"'
    check "init_stack_databases para el MariaDB por db_temp_pid" 'sed -n "/^function init_stack_databases() {/,/^}/p" "$SRC" | grep -q "spid=\$(db_temp_pid \"\$pid\" \"\$sock\")"'
    # Las pilas ya instaladas: SECURE_PY cambia su script lampp
    SECURE_PY=$(getvar SECURE_PY); VH=$(getvar UNKNOWN_HOST_VHOST); SSL=$(getvar UNKNOWN_HOST_SSL)
    SECURE_PY=${SECURE_PY%.} VH=${VH%.} SSL=${SSL%.}
    CONF=$(grep -m1 '^UNKNOWN_HOST_CONF=' "$SRC" | cut -d= -f2)
    B=$W/pila; mkdir -p "$B/etc/extra" "$W/out"
    printf 'Listen 127.0.0.1:80\n' > "$B/etc/httpd.conf"
    cat > "$B/lampp" <<'OLD'
#!/bin/bash
# Arranque y parada de lampp-8.4 (pila propia creada por lvm-instalador):
function running() {
    [ -f "$1" ] && kill -0 "$(cat "$1" 2> /dev/null)" 2> /dev/null
}
function stop_mysql() {
    running "$MYSQL_PID" || return 0

    kill "$(cat "$MYSQL_PID")"
}
function stop_ftp() {
    running "$FTP_PID" || return 0

    kill "$(cat "$FTP_PID")"
}
OLD
    out=$(python3 -I -c "$SECURE_PY" "$B" "$W/out" 1 "$CONF" "$VH" "$SSL" 2>&1)
    new=$(awk -F'|' '$1 == "lampp" {print $2}' <<< "$out")
    check "SECURE_PY rehace el script lampp de una pila ya instalada" '[ -n "$new" ] && grep -q "function pid_in()" "$new" && ! grep -q "kill \"\$(cat" "$new" && bash -n "$new"'
fi

# --- Mac: Apartar el XAMPP oficial sin root, rutas por el enlace y versiones revisadas por dentro
if [ $MAC -eq 1 ]; then
    body=$(sed -n '/^function official_dump_all() {/,/^}/p' "$SRC")
    check "Mac: Apartar no ejecuta como root el servidor, el cliente ni el volcado" '! grep -q "\$SUDO \"\$server\"\|\$SUDO \"\$client\"\|\$SUDO \"\$dumper\"" <<< "$body" && [ "$(grep -c "\"\${as_owner\[@\]}\" \"\$\(server\|client\|dumper\)\"" <<< "$body")" -eq 3 ]'
    check "Mac: Apartar se niega si las bases son de root" 'grep -q "\[ \"\$user\" == \"root\" \]" <<< "$body" && grep -q "stat -L -f %Su" <<< "$body"'
    VHOSTS_CHECK_PY=$(getvar VHOSTS_CHECK_PY); VHOSTS_CHECK_PY=${VHOSTS_CHECK_PY%.}
    vc() { printf '<VirtualHost *:80>\n    ServerName a.local\n    %s\n</VirtualHost>\n' "$1" > "$W/v.conf"; python3 -I -c "$VHOSTS_CHECK_PY" "$W/v.conf" > /dev/null; }
    check "Mac: registro por /Applications/XAMPP/... (el enlace): no" '! vc "ErrorLog \"/Applications/XAMPP/xamppfiles/logs/a-error_log\""'
    check "Mac: certificado por /Applications/XAMPP/... (el enlace): no" '! vc "SSLCertificateFile /Applications/XAMPP/xamppfiles/etc/ssl.crt/a.crt"'
    # (las versiones, desde la 1.39.3 en /Library/Nexum: por /Applications, que lo puede cambiar el grupo admin, no)
    VB=/Applications; grep -q '^    BASE_DIR=/Library/Nexum$' "$SRC" && VB=/Library/Nexum
    check "Mac: registro por logs/ o por una version: si" 'vc "ErrorLog logs/a-error_log" && vc "CustomLog $VB/XAMPP-8.4/xamppfiles/logs/a common"'
    [ "$VB" == /Library/Nexum ] && check "Mac: registro por /Applications/XAMPP-8.4 (el enlace de antes de la 1.39.3): no" '! vc "CustomLog /Applications/XAMPP-8.4/xamppfiles/logs/a common"'
    OLD_LOGS_SED=$(getvar OLD_LOGS_SED); OLD_LOGS_SED=${OLD_LOGS_SED%.}
    printf '    ErrorLog "/Applications/XAMPP/xamppfiles/logs/a-error_log"\n  CustomLog /Applications/XAMPP/xamppfiles/logs/b common\n  SSLCertificateKeyFile "/Applications/XAMPP/xamppfiles/etc/ssl.key/s.key"\n' > "$W/viejo.conf"
    sed -E "$OLD_LOGS_SED" "$W/viejo.conf" > "$W/nuevo.conf"
    check "Mac: las rutas viejas pasan a logs/ y etc/ (y entonces se admiten)" '! grep -q /Applications "$W/nuevo.conf" && grep -q "ErrorLog \"logs/a-error_log\"" "$W/nuevo.conf" && python3 -I -c "$VHOSTS_CHECK_PY" <(printf "<VirtualHost *:80>\n"; cat "$W/nuevo.conf"; printf "</VirtualHost>\n") > /dev/null'
    check "Mac: vhosts_root sin certificados «conocidos»" 'sed -n "/^function vhosts_root() {/,/^}/p" "$SRC" | grep -q "\"\$VHOSTS_CHECK_PY\" \"\$snap/v\"; then"'
    extract "$SRC" version_unsafe_files || exit 1
    V=$W/XAMPP-8.4; mkdir -p "$V/xamppfiles/apache2/bin" "$V/xamppfiles/var/mysql"
    touch "$V/xamppfiles/apache2/bin/httpd" "$V/xamppfiles/var/mysql/ibdata1"
    out=$(version_unsafe_files "$V")
    check "Mac: lo de dentro que no es de root se ve (no las bases)" 'grep -q "apache2/bin/httpd$" <<< "$out" && ! grep -q var/mysql <<< "$out"'
    check "Mac: trusted_version_dir lo mira" 'sed -n "/^function trusted_version_dir() {/,/^}/p" "$SRC" | grep -q version_unsafe_files'
fi
exit $fail
