#!/bin/bash
# Pruebas de la 1.42.0 / Mac 1.30.0: .local en hosts, reglas de los vhosts, htdocs sin escritura
# para otros, deteccion de tablas del sistema antiguas y la ventana con un FIFO. Uso: extras.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-extras.XXXX"); trap 'rm -rf "$W"' EXIT
getvar() { ( eval "$(sed -n "/^$1='/,/^'\$/p" "$SRC")"; printf '%s.' "${!1}" ); }

# --- hosts: los .local de los vhosts siempre, y al cargar otro proyecto no se comentan ---
extract "$SRC" hosts_fake || exit 1
printf '127.0.0.1 localhost\n127.0.0.1 web.local\n127.0.0.1 tienda.com www.tienda.com\n127.0.0.1 otra.local\n' > "$W/h"
HOSTS_FILE=$W/h PROJECT_VHOST=web.local
project_link() { echo web.local; }
vhosts_info() { printf '80|x|web.local||\n80|t|tienda.com|www.tienda.com|\n80|s|ejemplo.local||\n80|o|otra.local||\n80|n|nueva.com||\n'; }
edit_hosts() { cp "$2" "$HOSTS_FILE"; }
hosts_fake cargar nueva.com > /dev/null
check "hosts: el .local que faltaba se añade" 'grep -q "^127.0.0.1 ejemplo.local$" "$W/h"'
check "hosts: un .local que ya estaba no se comenta al cargar otro" 'grep -q "^127.0.0.1 otra.local$" "$W/h"'
check "hosts: el dominio real de otro proyecto si se comenta" 'grep -q "^#127.0.0.1 tienda.com" "$W/h"'
check "hosts: el cargado se falsea" 'grep -q "^127.0.0.1 nueva.com www.nueva.com" "$W/h"'
check "hosts: web.local no se toca" 'grep -q "^127.0.0.1 web.local$" "$W/h"'
cp "$W/h" "$W/h0"; hosts_fake locales > /dev/null
check "hosts locales: segunda vez sin cambios" 'cmp -s "$W/h" "$W/h0"'

# Linea con un dominio de verdad y un .local (vhost con los dos, el .local en mayusculas)
printf '127.0.0.1 localhost\n127.0.0.1 web.local\n127.0.0.1 tienda.com www.tienda.com tienda.local\n' > "$W/h"
vhosts_info() { printf '80|x|web.local||\n80|t|tienda.com|www.tienda.com Tienda.Local|\n80|n|nueva.com||\n'; }
hosts_fake cargar nueva.com > /dev/null
check "hosts: linea mixta: el dominio real se comenta" 'grep -q "^#127.0.0.1 tienda.com www.tienda.com$" "$W/h"'
check "hosts: linea mixta: el .local sigue activo en otra linea" 'grep -q "^127.0.0.1 tienda.local$" "$W/h"'
# (desde la 1.44.2 / Mac 1.32.3 un .local no se apaga: sin su linea se preguntaria a la red, mDNS)
hosts_fake no tienda.local > /dev/null
check "hosts: un .local no se apaga (sigue en hosts)" 'grep -q "^127.0.0.1 tienda.local" "$W/h"'
sed -i 's/^127.0.0.1 tienda.local$/#127.0.0.1 tienda.local/' "$W/h"
hosts_fake cargar nueva.com > /dev/null
check "hosts: un .local comentado a mano vuelve a añadirse al cargar otro proyecto" 'grep -q "^127.0.0.1 tienda.local$" "$W/h"'
# Desde la 1.50.1 un .local se puede apagar en la pestaña Hosts (hosts-falsear): se recuerda, con su
# www., y ya no se vuelve a añadir; al encenderlo se olvida (Mac desde la 1.37.0)
if grep -q '^function local_off() {' "$SRC"; then
extract "$SRC" local_off hosts_fake_one sudo_first || exit 1
DRY=0 LOCAL_OFF_FILE=$W/apagados
valid_domain() { [[ "$1" =~ ^[a-z0-9.-]+$ ]]; }
printf '127.0.0.1 localhost\n127.0.0.1 web.local\n127.0.0.1 ejemplo.local\n127.0.0.1 www.ejemplo.local\n' > "$W/h"
vhosts_info() { printf '80|x|web.local||\n80|s|ejemplo.local|www.ejemplo.local|\n80|n|nueva.com||\n'; }
hosts_fake_one ejemplo.local no > /dev/null
check "hosts: un .local apagado a mano se comenta (con su www.)" '! grep -q "^127.0.0.1 .*ejemplo.local" "$W/h" && grep -q "^#127.0.0.1 ejemplo.local$" "$W/h" && grep -q "^#127.0.0.1 www.ejemplo.local$" "$W/h"'
check "hosts: el .local apagado se recuerda, con su www." 'grep -qx ejemplo.local "$W/apagados" && grep -qx www.ejemplo.local "$W/apagados"'
check "hosts: la lista de apagados es solo tuya" '[ "$(stat -c %a "$W/apagados")" = 600 ]'
hosts_fake cargar nueva.com > /dev/null; hosts_fake locales > /dev/null
check "hosts: un .local apagado no vuelve a añadirse (al cargar otro ni al asegurar)" '! grep -q "^127.0.0.1 .*ejemplo.local" "$W/h"'
hosts_fake_one ejemplo.local si > /dev/null
check "hosts: al encenderlo vuelve a hosts" 'grep -q "^127.0.0.1 ejemplo.local$" "$W/h" && grep -q "^127.0.0.1 www.ejemplo.local$" "$W/h"'
check "hosts: al encenderlo se olvida" '! grep -q ejemplo "$W/apagados"'
hosts_fake cargar nueva.com > /dev/null
check "hosts: encendido otra vez, se mantiene al cargar otro proyecto" 'grep -q "^127.0.0.1 ejemplo.local$" "$W/h"'
edit_hosts() { return 1; }
hosts_fake_one ejemplo.local no > /dev/null 2>&1
check "hosts: si no se puede cambiar hosts (contraseña cancelada), no se recuerda apagado" '! grep -q ejemplo "$W/apagados" && grep -q "^127.0.0.1 ejemplo.local$" "$W/h"'
edit_hosts() { cp "$2" "$HOSTS_FILE"; }
fi
# --- web.local que no lleva a 127.0.0.1 (127.0.1.1 del nombre del equipo): aviso y arreglo ---
extract "$SRC" gui_hosts hosts_fix_link || exit 1
valid_domain() { [[ "$1" =~ ^[a-z0-9.-]+$ ]]; }
vhosts_info() { printf '80|x|web.local||\n'; }
HTDOCS_DIR=$W PORT_HTTPS=443 CUSTOM_DOMAINS_FILE=$W/nada
printf '127.0.0.1 localhost\n127.0.1.1 equipo\n127.0.1.1    web.local\n' > "$W/h"
check "web.local en 127.0.1.1: se avisa" '[ "$(gui_hosts | grep "^L|")" = "L|web.local|127.0.1.1" ]'
hosts_fix_link > /dev/null
check "Arreglarlo: web.local a 127.0.0.1" 'grep -q "^127.0.0.1 web.local$" "$W/h"'
check "Arreglarlo: la linea vieja queda comentada y la del equipo, igual" 'grep -q "^# (lvm-instalador: web.local pasa a 127.0.0.1) 127.0.1.1" "$W/h" && grep -q "^127.0.1.1 equipo$" "$W/h"'
check "despues: sin aviso" '[ -z "$(gui_hosts | grep "^L|")" ]'
printf '127.0.0.1 localhost\n127.0.1.1 equipo web.local\n' > "$W/h"; hosts_fix_link > /dev/null
check "web.local junto al nombre del equipo: se quita de esa linea, que se queda con el equipo" 'grep -q "^127.0.1.1 equipo$" "$W/h" && grep -q "^127.0.0.1 web.local$" "$W/h"'
printf '127.0.0.1 localhost\n' > "$W/h"
check "sin linea de web.local: se avisa" '[ "$(gui_hosts | grep "^L|")" = "L|web.local|" ]'
cp "$W/h" "$W/h0"; printf '127.0.0.1 localhost web.local\n' > "$W/h"
check "web.local ya en 127.0.0.1: sin aviso" '[ -z "$(gui_hosts | grep "^L|")" ]'
check "comando hosts-enlace" 'grep -q "hosts-enlace) hosts_fix_link" "$SRC"'

# --- copiar-bd: solo a una version que no la tiene ---
extract "$SRC" copy_database db_valid_name valid_version_name || exit 1
DB_SYSTEM="information_schema|mysql|performance_schema|phpmyadmin|sys|test"
if grep -q 'BASE_DIR/XAMPP-' <<< "$(declare -f copy_database)"; then
    BASE_DIR=$W/v; mkdir -p "$BASE_DIR/XAMPP-8.1" "$BASE_DIR/XAMPP-8.4"
    db_names() { case "$1" in *8.1) echo wp_a ;; *8.4) echo wp_b ;; esac; }
else
    TEST_DIR=$W/v; mkdir -p "$TEST_DIR/lampp-8.1" "$TEST_DIR/lampp-8.4"
    data_owner() { basename "$1" | sed 's/^lampp-//'; }
    db_names() { case "$1" in *8.1) echo wp_a ;; *8.4) echo wp_b ;; esac; }
fi
active_dir() { echo ""; }; lampp_running() { return 1; }; realpath_f() { echo "$1"; }
DRY=1
check "copiar-bd: a la misma version, no" '! copy_database wp_a 8.1 8.1 > /dev/null'
check "copiar-bd: una BBDD que no esta en el origen, no" '! copy_database wp_x 8.1 8.4 > /dev/null'
check "copiar-bd: si el destino ya la tiene, no (no se pisa)" 'db_names() { echo wp_a; }; ! copy_database wp_a 8.1 8.4 > /dev/null'
db_names() { case "$1" in *8.1) echo wp_a ;; *8.4) echo wp_b ;; esac; }
check "copiar-bd: nombre de BBDD raro, no" '! copy_database "x;y" 8.1 8.4 > /dev/null'
check "copiar-bd: simulacion de una copia buena" 'copy_database wp_a 8.1 8.4 | grep -q "MariaDB temporal"'
DRY=0

# --- vhosts: certificados solo del gestor y registros sin nombres de control ---
VC=$(getvar VHOSTS_CHECK_PY); VC=${VC%.}
# (en el Mac, desde la 1.39.3, en /Library/Nexum)
if grep -q "Library/Nexum/XAMPP-compartido/ssl/" <<< "$VC"; then SSLD=/Library/Nexum/XAMPP-compartido/ssl
elif grep -q "XAMPP-compartido/ssl/" <<< "$VC"; then SSLD=/Applications/XAMPP-compartido/ssl; else SSLD=/opt/config/ssl; fi
vc() { printf '%b' "$1" > "$W/v.conf"; python3 -I -c "$VC" "$W/v.conf" > /dev/null; }
check "vhosts: certificado del gestor pasa" 'vc "<VirtualHost *:443>\nSSLCertificateFile \"$SSLD/a.com.crt\"\nSSLCertificateKeyFile $SSLD/a.com.key\n</VirtualHost>\n"'
check "vhosts: clave de otro servicio no pasa" '! vc "<VirtualHost *:443>\nSSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key\n</VirtualHost>\n"'
check "vhosts: certificado con .. no pasa" '! vc "<VirtualHost *:443>\nSSLCertificateFile $SSLD/../../etc/x.crt\n</VirtualHost>\n"'
check "vhosts: SSLCACertificateFile de fuera no pasa" '! vc "<VirtualHost *:443>\nSSLCACertificateFile /root/ca.pem\n</VirtualHost>\n"'
check "vhosts: ErrorLog normal pasa" 'vc "<VirtualHost *:80>\nErrorLog \"logs/a.com-error_log\"\n</VirtualHost>\n"'
check "vhosts: ErrorLog httpd.pid no pasa" '! vc "<VirtualHost *:80>\nErrorLog logs/httpd.pid\n</VirtualHost>\n"'
check "vhosts: CustomLog cgisock no pasa" '! vc "<VirtualHost *:80>\nCustomLog logs/cgisock.123 common\n</VirtualHost>\n"'

check "vhosts: ruta entre comillas con espacio y .. (ErrorLog) no pasa" '! vc "<VirtualHost *:80>\nErrorLog \"logs/x /../../../../tmp/fuera.log\"\n</VirtualHost>\n"'
check "vhosts: ruta entre comillas con espacio y .. (certificado) no pasa" '! vc "<VirtualHost *:443>\nSSLCertificateKeyFile \"$SSLD/x /../../../../etc/k.key\"\n</VirtualHost>\n"'
check "vhosts: certificado de mkcert con + pasa" 'vc "<VirtualHost *:443>\nSSLCertificateFile $SSLD/a.test+2.pem\n</VirtualHost>\n"'
printf '<VirtualHost *:443>\nSSLCertificateFile /home/x/certs/a.crt\n</VirtualHost>\n' > "$W/antes.conf"; cp "$W/antes.conf" "$W/v2.conf"
check "vhosts: un certificado de fuera que ya estaba sigue valiendo" 'python3 -I -c "$VC" "$W/v2.conf" "$W/antes.conf" > /dev/null'
printf '<VirtualHost *:443>\nSSLCertificateFile /home/x/certs/a.crt\nSSLCertificateKeyFile /home/x/otra.key\n</VirtualHost>\n' > "$W/v3.conf"
check "vhosts: uno nuevo de fuera no" '! python3 -I -c "$VC" "$W/v3.conf" "$W/antes.conf" > /dev/null'
check "vhosts: espacio Unicode (U+00A0) que lleva el registro fuera: no pasa" '! vc "<VirtualHost *:80>\nErrorLog logs/x\xc2\xa0/../../../esc.log\n</VirtualHost>\n"'
check "vhosts: espacio Unicode entre comillas en un certificado: no pasa" '! vc "<VirtualHost *:443>\nSSLCertificateKeyFile \"$SSLD/a\xc2\xa0/../../../etc/k.key\"\n</VirtualHost>\n"'
check "vhosts: barra invertida en la ruta: no pasa" '! vc "<VirtualHost *:80>\nErrorLog \"logs\\\\/x.log\"\n</VirtualHost>\n"'
# --- htdocs: sin escritura para otros, sin seguir enlaces ---
extract "$SRC" htdocs_close_world || exit 1
mkdir -p "$W/hd/p/up"; touch "$W/hd/p/a.php" "$W/fuera"; chmod 777 "$W/hd/p/up"; chmod 666 "$W/hd/p/a.php" "$W/fuera"
ln -s "$W/fuera" "$W/hd/p/enlace"
DRY=1 out=$(htdocs_close_world "$W/hd/p")
check "htdocs (simulacion): no cambia nada" '[ "$(stat -c %a "$W/hd/p/up")" = 777 ] && grep -q simulacion <<< "$out"'
DRY=0 htdocs_close_world "$W/hd/p" > /dev/null
check "htdocs: carpeta 777 -> 775 y fichero 666 -> 664" '[ "$(stat -c %a "$W/hd/p/up")" = 775 ] && [ "$(stat -c %a "$W/hd/p/a.php")" = 664 ]'
check "htdocs: no sigue enlaces" '[ "$(stat -c %a "$W/fuera")" = 666 ]'

# --- tablas del sistema antiguas: deteccion con un cliente de prueba ---
extract "$SRC" db_system_outdated || exit 1
lampp_running() { true; }
printf '#!/bin/sh\necho "column_stats.min_value=varchar(255)"\necho "innodb_table_stats.table_name=varchar(64)"\n' > "$W/viejo"
printf '#!/bin/sh\necho "column_stats.min_value=varbinary(255)"\necho "innodb_table_stats.table_name=varchar(199)"\n' > "$W/nuevo"
printf '#!/bin/sh\nexit 1\n' > "$W/caido"; chmod +x "$W/viejo" "$W/nuevo" "$W/caido"
check "tablas del sistema antiguas: se detectan" 'DB_CLIENT=$W/viejo db_system_outdated'
check "tablas al dia: no" '! DB_CLIENT=$W/nuevo db_system_outdated'
check "MariaDB que no responde: no se avisa" '! DB_CLIENT=$W/caido db_system_outdated'
grep -q "reparar-bd-sistema) repair_db_system" "$SRC" && ok "comando reparar-bd-sistema" || bad "comando reparar-bd-sistema"

# --- ventana de Linux: un FIFO en la configuracion de un proyecto no la cuelga ---
if grep -q "^function gui_source" "$SRC"; then
    awk "/^    cat <<'LVM_GUI_PY'/{f=1;next} /^LVM_GUI_PY\$/{f=0} f" "$SRC" > "$W/v.py"
    mkdir -p "$W/ht/bueno" "$W/ht/fifo" "$W/ht/cero"
    printf "<?php\ndefine( 'DB_NAME', 'wp_bueno' );\n" > "$W/ht/bueno/wp-config.php"
    mkfifo "$W/ht/fifo/wp-config.php"; ln -s /dev/zero "$W/ht/cero/wp-config.php"
    res=$(timeout 10 python3 -I - "$W/v.py" "$W/ht" <<'PY'
import os, re, stat, sys
src = open(sys.argv[1]).read()
HTDOCS = sys.argv[2]
exec(src[src.index("DB_RULES = ["):src.index("# Visual Studio Code, seg")])
exec(src[src.index("def project_db(folder):"):src.index("# Registros mayores que esto")])
print(project_db("bueno"), project_db("fifo") or "-", project_db("cero") or "-")
PY
)
    check "ventana: FIFO y /dev/zero no la cuelgan (y el normal se lee)" '[ "$res" = "wp_bueno - -" ]'
fi
exit $fail
