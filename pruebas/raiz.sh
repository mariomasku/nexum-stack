#!/bin/bash
# Lo que hace root sobre carpetas que eran tuyas (1.41.0): enlaces de lo compilado, .pid del MariaDB
# temporal y secure_lampp preparando los ficheros como root. Sin root: sudo sustituido.
# Uso: raiz.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-raiz.XXXX"); trap 'rm -rf "$W"' EXIT
getvar() { ( eval "$(sed -n "/^$1='/,/^'\$/p" "$SRC")"; printf '%s.' "${!1}" ); }
BUILD_LINKS_PY=$(getvar BUILD_LINKS_PY); BUILD_LINKS_PY=${BUILD_LINKS_PY%.}

# --- Enlaces de lo compilado ---
if [ -n "$BUILD_LINKS_PY" ]; then
    T=/opt/lampp-9.9 S=$W/stage/opt/lampp-9.9; mkdir -p "$S/php/bin" "$S/etc/extra" "$S/phpmyadmin" "$S/mysql/lib"
    ln -s php.phar "$S/php/bin/phar"; ln -s /opt/lampp-9.9/mysql/lib/libx.so.3 "$S/mysql/lib/libx.so"
    ln -s ../../mysql/lib "$S/php/bin/libs"; ln -s /opt/htdocs "$S/htdocs"; ln -s /opt/config/httpd-vhosts.conf "$S/etc/extra/httpd-vhosts.conf"
    check "enlaces de una pila normal: ninguno fuera" '[ -z "$(python3 -I -c "$BUILD_LINKS_PY" "$S" "$T")" ]'
    ln -s /etc/passwd "$S/phpmyadmin/tmp"
    ln -s ../../../../etc "$S/tmp"
    ln -s /opt/lampp-9.9/../../etc/shadow "$S/php/bin/x"
    ln -s /opt/htdocs/../../etc "$S/etc/extra/otro"
    ln -s htdocs/.x/lampp "$S/lampp"
    ln -s ../../htdocs/evil "$S/php/bin/php"
    ln -s /opt/lampp-9.9/etc/extra/httpd-vhosts.conf "$S/etc/vh"
    out=$(python3 -I -c "$BUILD_LINKS_PY" "$S" "$T")
    check "enlace absoluto a /etc/passwd: fuera" 'grep -q "^phpmyadmin/tmp -> /etc/passwd$" <<< "$out"'
    check "enlace relativo que sale con ../: fuera" 'grep -q "^tmp -> " <<< "$out"'
    check "enlace absoluto con .. que sale de la version: fuera" 'grep -q "^php/bin/x -> " <<< "$out"'
    check "htdocs solo vale en su sitio" 'grep -q "^etc/extra/otro -> " <<< "$out" && ! grep -q "^htdocs " <<< "$out"'
    check "enlace a traves de htdocs (tuyo): fuera" 'grep -q "^lampp -> htdocs/.x/lampp$" <<< "$out" && grep -q "^php/bin/php -> " <<< "$out"'
    check "enlace a traves de los vhosts compartidos: fuera" 'grep -q "^etc/vh -> " <<< "$out"'
    # En la copia ya en su sitio se mira tambien como lo resuelve el sistema (enlaces de en medio)
    C=$W/copia; mkdir -p "$C/php/bin" "$W/fuera"; ln -s "$W/fuera" "$C/sub"; ln -s ../../sub/x "$C/php/bin/y"
    out=$(python3 -I -c "$BUILD_LINKS_PY" "$C" "$C")
    check "copia de root: enlace que sale por otro enlace de dentro: fuera" 'grep -q "^php/bin/y -> ../../sub/x$" <<< "$out"'
    ok_t=$(python3 -I -c "$BUILD_LINKS_PY" /opt/lampp-8.4 /opt/lampp-8.4)
    check "la pila 8.4 instalada pasa la comprobacion de la copia" '[ -z "$ok_t" ]'
else
    bad "no esta BUILD_LINKS_PY"
fi
check "install_stack crea phpmyadmin/tmp y tmp como root (sin chown ni chmod sobre lo copiado)" \
    'grep -q "sudo install -d -o 0 -g \"\$web_group\" -m 775 \"\$target/phpmyadmin/tmp\"" "$SRC" && ! grep -q "sudo chmod 1777 \"\$target/tmp\"" "$SRC"'
check "install_stack vuelve a mirar los enlaces en la copia de root (y un fallo de python no vale)" 'grep -q "links=\$(\$SUDO /usr/bin/python3 -I -c \"\$BUILD_LINKS_PY\" \"\$target\" \"\$target\") && \[ -z \"\$links\" \]" "$SRC"'
check "actualizar phpMyAdmin: sin chown ni chmod sobre su tmp copiado" '! grep -q "sudo chown \"root:\$grp\" \"\$dir/tmp\"" "$SRC" && grep -q "sudo install -d -o 0 -g \"\$grp\" -m 775 \"\$dir/tmp\"" "$SRC"'

# --- PID del MariaDB temporal ---
extract "$SRC" db_temp_pid || exit 1
SUDO="" D=$W/mdb; mkdir -p "$D"; SOCK=$D/mysql.sock
bash -c 'exec -a "mariadbd --socket='"$SOCK"' --datadir=x" sleep 30' & srv=$!
sleep 0.3
echo "$srv" > "$D/mysql.pid"
check ".pid del servidor: vale" '[ "$(db_temp_pid "$D/mysql.pid" "$SOCK")" = "$srv" ]'
sleep 30 & otro=$!
echo "$otro" > "$D/mysql.pid"
check ".pid de otro proceso: no vale" '! db_temp_pid "$D/mysql.pid" "$SOCK" > /dev/null'
echo 1 > "$D/mysql.pid"
check ".pid 1: no vale" '! db_temp_pid "$D/mysql.pid" "$SOCK" > /dev/null'
echo "$srv x" > "$D/mysql.pid"
check ".pid con algo mas: no vale" '! db_temp_pid "$D/mysql.pid" "$SOCK" > /dev/null'
rm "$D/mysql.pid"; ln -s /proc/$srv/stat "$D/mysql.pid"
check ".pid que es un enlace: no vale" '! db_temp_pid "$D/mysql.pid" "$SOCK" > /dev/null'
kill $srv $otro 2> /dev/null; wait 2> /dev/null
check "db_temp_stop usa db_temp_pid (y si no, para lo que lanzo)" 'grep -q "db_temp_kill_launched \"\$DB_TMP_PID\" \"\$DB_TMP_SOCK\"" "$SRC"'
# Parada de reserva: lo lanzado con una funcion sudo (Mac) es una subshell; su hijo tambien se para
extract "$SRC" db_temp_kill_launched || exit 1
SUDO=""
fsudo() { "$@"; }
SK=$W/s.sock
( fsudo bash -c 'exec -a "mariadbd --socket='"$SK"'" sleep 30' ) & sub=$!
sleep 0.3; hijo=$(pgrep -P $sub)
sleep 30 & ajeno=$!
db_temp_kill_launched "$ajeno" "$SK"; sleep 0.2
check "parada de reserva: un proceso sin el socket (PID reutilizado) no se toca" 'kill -0 "$ajeno"'
kill $ajeno
db_temp_kill_launched "$sub" "$SK"; sleep 0.3
check "parada de reserva: el hijo de la subshell (lleva el socket) se para" '[ -n "$hijo" ] && ! kill -0 "$hijo" 2> /dev/null'
check "parada de reserva: un pid raro o sin socket no hace nada" 'db_temp_kill_launched "1 2" x && db_temp_kill_launched 1 x && db_temp_kill_launched 123'

# --- secure_lampp: los ficheros los prepara root en una carpeta de root ---
eval "$(sed -n "/^SECURE_PY='/,/^'\$/p;/^UNKNOWN_HOST_VHOST='/,/^'\$/p;/^UNKNOWN_HOST_SSL='/,/^'\$/p" "$SRC")"
UNKNOWN_HOST_CONF=$(grep -m1 '^UNKNOWN_HOST_CONF=' "$SRC" | cut -d= -f2)
extract "$SRC" secure_lampp || exit 1
# (1.54.1: el texto de lvm-dominio-desconocido.conf segun la barrera entre webs)
if grep -q '^function host_vhost() {' "$SRC"; then
    extract "$SRC" host_vhost cross_site_on || exit 1
    CROSS_SITE_OFF=$W/sin-barrera
    eval "$(sed -n '/^PHP_SECURE_INI=/,/^PHP_SECURE_INI_85=/p' "$SRC")"
fi
has_ipv6_loopback() { return 0; }
V=$W/lampp-9.9; mkdir -p "$V/etc/extra"
printf 'Listen 80\nInclude etc/extra/httpd-vhosts.conf\n' > "$V/etc/httpd.conf"; : > "$V/etc/extra/httpd-vhosts.conf"
printf '[mysqld]\nport=3306\n' > "$V/etc/my.cnf"
sudo() {
    echo "SUDO $*" >> "$W/sudo.log"
    if [ "$1" == install ]; then
        shift; local a=(); while [ $# -gt 0 ]; do case $1 in -o|-g) shift 2 ;; *) a+=("$1"); shift ;; esac; done
        set -- install "${a[@]}"
    fi
    "$@"
}
DRY=1 TEST_DIR="" HOME=$W/home SECURE_MARK=etc/lvm-seguridad
out=$(secure_lampp "$V"); rc=$?
check "simulacion: dice lo que cambiaria sin sudo" '[ $rc = 0 ] && grep -q "secure_file_priv" <<< "$out" && [ ! -s "$W/sudo.log" ]'
check "simulacion: no cambia nada" '! grep -q "secure-file-priv" "$V/etc/my.cnf" && [ ! -d "$V/etc/lvm-sin-ficheros" ]'
DRY=0
out=$(secure_lampp "$V"); rc=$?
check "secure_lampp: SECURE_PY lo ejecuta root (sudo env ... python3)" 'grep -q "^SUDO env LVM_SECURE_APPLY=1 LVM_FTP_USER=$(id -un) .*/usr/bin/python3 -I -c" "$W/sudo.log"'
check "secure_lampp: en una carpeta de root (sudo mktemp)" 'grep -q "^SUDO mktemp -d /tmp/lvm-seguridad" "$W/sudo.log"'
check "secure_lampp: root copia con sh -c cat (no lee tu usuario la carpeta)" 'grep -q "^SUDO sh -c cat \"\$1\" > \"\$2\" sh /tmp/lvm-seguridad" "$W/sudo.log"'
check "secure_lampp: carpeta vacia creada antes que el my.cnf" '[ -d "$V/etc/lvm-sin-ficheros" ] && [ "$(grep -n "^SUDO install -d" "$W/sudo.log" | cut -d: -f1)" -lt "$(grep -n "^SUDO sh -c .*etc/my.cnf$" "$W/sudo.log" | cut -d: -f1)" ]'
check "secure_lampp: my.cnf con secure-file-priv y local-infile" 'grep -q "^secure-file-priv = \"$V/etc/lvm-sin-ficheros\"" "$V/etc/my.cnf" && grep -q "^local-infile = 0" "$V/etc/my.cnf"'
check "secure_lampp: no deja la carpeta temporal" '! ls -d /tmp/lvm-seguridad.* 2> /dev/null | grep -q .  || [ -z "$(find /tmp -maxdepth 1 -name "lvm-seguridad.*" -user "$(id -un)" -newer "$W/sudo.log" 2> /dev/null)" ]'
: > "$W/sudo.log"
out=$(secure_lampp "$V"); rc=$?
check "segunda vez: nada que cambiar y sin pedir sudo" '[ $rc = 1 ] && [ ! -s "$W/sudo.log" ]'
# Sin nada que cambiar en los ficheros, lo demas se sigue haciendo (permisos de XAMPP y la marca)
V2=$W/lampp-9.8; cp -r "$V" "$V2"; rm -f "$V2/etc/lvm-seguridad"; mkdir -p "$V2/temp"; chmod 777 "$V2/temp"
: > "$W/sudo.log"
out=$(secure_lampp "$V2"); rc=$?
check "sin ficheros que cambiar: arregla temp y pone la marca" '[ "$(stat -c %a "$V2/temp")" = 1777 ] && [ -f "$V2/etc/lvm-seguridad" ] && ! grep -q "^SUDO env" "$W/sudo.log"'
exit $fail
