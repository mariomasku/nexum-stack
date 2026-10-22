#!/bin/bash
# Pruebas de SECURE_PY sobre arboles de prueba (sin root). Uso: secure.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-sec.XXXX"); trap '[ -n "$KEEP" ] || rm -rf "$W"' EXIT
# Las variables, evaluadas por bash como en el script (comillas '"'"' incluidas)
getvar() { ( eval "$(sed -n "/^$1='/,/^'\$/p" "$SRC")"; printf '%s.' "${!1}" ); }  # (el punto guarda los saltos de linea del final)
SECURE_PY=$(getvar SECURE_PY); VH=$(getvar UNKNOWN_HOST_VHOST); SSL=$(getvar UNKNOWN_HOST_SSL); SECURE_PY=${SECURE_PY%.} VH=${VH%.} SSL=${SSL%.}
CONF=$(grep -m1 '^UNKNOWN_HOST_CONF=' "$SRC" | cut -d= -f2)
[ -n "$SECURE_PY" ] && [ -n "$VH" ] || { echo "no se encuentra SECURE_PY"; exit 1; }
B=$W/base; mkdir -p "$B/etc/extra/sub" "$W/out"
cat > "$B/etc/httpd.conf" <<'C'
Listen 80
Listen 192.168.1.5:8080
Listen 127.0.0.1:81
Listen localhost:82
Include etc/extra/httpd-vhosts.conf
C
printf 'Listen 443 https\nListen 8443\n' > "$B/etc/extra/httpd-ssl.conf"
printf 'Listen 9443\n' >> "$B/etc/httpd.conf"
printf '<VirtualHost *:9443>\n    ServerName x.com\n    SSLEngine on\n</VirtualHost>\n' > "$B/etc/extra/httpd-vhosts.conf"
printf 'Listen 0.0.0.0:9090\n' > "$B/etc/extra/sub/x.conf"
printf '[client]\nport=3306\n[mysqld]\nport=3306\nbind-address = 0.0.0.0\nskip-networking=0\n' > "$B/etc/my.cnf"
printf 'Port 21\nDefaultAddress 0.0.0.0\nSocketBindTight off\n' > "$B/etc/proftpd.conf"
out=$(python3 -I -c "$SECURE_PY" "$B" "$W/out" 1 "$CONF" "$VH" "$SSL" 2>&1) || { echo "SECURE_PY falla: $out"; exit 1; }
f() { local rel=$1; local dst; dst=$(awk -F'|' -v r="$rel" '$1 == r {print $2}' <<< "$out"); [ -n "$dst" ] && cat "$dst"; }
H=$(f etc/httpd.conf); X=$(f etc/extra/sub/x.conf); MY=$(f etc/my.cnf); FTP=$(f etc/proftpd.conf); U=$(f "$CONF")
check "Listen 80 -> 127.0.0.1 y ::1" 'grep -q "^Listen 127.0.0.1:80$" <<< "$H" && grep -q "^Listen \[::1\]:80$" <<< "$H"'
check "Listen con la IP de la red se cierra" 'grep -q "^Listen 127.0.0.1:8080$" <<< "$H" && ! grep -q 192.168 <<< "$H"'
check "Listen de 127.0.0.1 y localhost se quedan" 'grep -q "^Listen 127.0.0.1:81$" <<< "$H" && grep -q "^Listen localhost:82$" <<< "$H"'
check "Listen en subcarpeta se cierra" 'grep -q "^Listen 127.0.0.1:9090$" <<< "$X"'
check "bind-address 0.0.0.0 se comenta y se pone el bueno" 'grep -q "^# (lvm-instalador: abierto a la red) bind-address" <<< "$MY" && grep -q "^bind-address = 127.0.0.1" <<< "$MY"'
check "skip-networking=0 se comenta" 'grep -q "^# (lvm-instalador: abierto a la red) skip-networking=0" <<< "$MY"'
check "[client] no se toca" 'grep -q "^\[client\]" <<< "$MY" && grep -q "^port=3306" <<< "$MY"'
check "DefaultAddress 0.0.0.0 -> 127.0.0.1" 'grep -q "^DefaultAddress 127.0.0.1$" <<< "$FTP"'
check "SocketBindTight off -> on" 'grep -q "^SocketBindTight on$" <<< "$FTP"'
check "vhost de desconocidos tambien en 8080, 81, 82 y 9090 (no en 443, 8443 ni 9443 de SSL)" 'grep -q "<VirtualHost \*:80 \*:81 \*:82 \*:8080 \*:9090>" <<< "$U"'
# Ya protegido: no cambia nada (y una segunda pasada tampoco)
B2=$W/b2; mkdir -p "$B2/etc/extra" "$W/o2"
printf 'Listen 127.0.0.1:80\nListen [::1]:80\nInclude %s\nInclude etc/extra/httpd-vhosts.conf\n' "$CONF" > "$B2/etc/httpd.conf"
printf '%s' "$VH" > "$B2/$CONF"
# (desde la 1.41.0, protegida es tambien con secure_file_priv en su carpeta vacia y sin local-infile)
mkdir -p "$B2/etc/lvm-sin-ficheros"
printf '[mysqld]\nbind-address=127.0.0.1\nsecure-file-priv = "%s/etc/lvm-sin-ficheros"\nlocal-infile = 0\n' "$B2" > "$B2/etc/my.cnf"
o2=$(python3 -I -c "$SECURE_PY" "$B2" "$W/o2" 1 "$CONF" "$VH" "$SSL")
check "version ya protegida: sin cambios" '[ -z "$o2" ]'
printf '[mysqld]\nskip-networking\nsecure_file_priv=%s/etc/lvm-sin-ficheros\nlocal_infile=OFF\n' "$B2" > "$B2/etc/my.cnf"
o2=$(python3 -I -c "$SECURE_PY" "$B2" "$W/o2" 1 "$CONF" "$VH" "$SSL")
check "skip-networking sin valor cuenta como cerrado" '[ -z "$o2" ]'
# secure_file_priv (LOAD_FILE e INTO OUTFILE de root): vacio, sin poner o con local-infile
B4=$W/b4; mkdir -p "$B4/etc/extra" "$W/o4"
cp "$B2/etc/httpd.conf" "$B4/etc/httpd.conf"; printf '%s' "$VH" > "$B4/$CONF"
printf '[client]\nlocal-infile=1\n[mysqld]\nbind-address=127.0.0.1\nsecure_file_priv = ""\nlocal-infile=1\n' > "$B4/etc/my.cnf"
o4=$(python3 -I -c "$SECURE_PY" "$B4" "$W/o4" 1 "$CONF" "$VH" "$SSL")
M4=$(cat "$(awk -F'|' '$1 == "etc/my.cnf" {print $2}' <<< "$o4")")
check "secure_file_priv vacio se comenta" 'grep -q "^# (lvm-instalador: dejaba leer y escribir ficheros) secure_file_priv" <<< "$M4"'
check "local-infile=1 de [mysqld] se comenta, el de [client] se queda" 'grep -q "^# (lvm-instalador: dejaba leer y escribir ficheros) local-infile=1" <<< "$M4" && [ "$(grep -c "^local-infile=1" <<< "$M4")" = 1 ]'
check "se pone secure-file-priv en la carpeta vacia de la version y local-infile = 0 en [mysqld]" \
    'sed -n "/^\[mysqld\]/,\$p" <<< "$M4" | grep -q "^secure-file-priv = \"$B4/etc/lvm-sin-ficheros\"" && sed -n "/^\[mysqld\]/,\$p" <<< "$M4" | grep -q "^local-infile = 0"'
check "pide crear la carpeta (y va la primera)" '[ "$(head -1 <<< "$o4" | cut -d"|" -f1)" = "etc/lvm-sin-ficheros/" ]'
check "el resultado lo acepta MariaDB (my_print_defaults)" 'env LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib /opt/lampp-8.2.4/bin/my_print_defaults --defaults-file=<(printf "%s" "$M4") mysqld | grep -qx -- "--secure-file-priv=$B4/etc/lvm-sin-ficheros"'
mkdir -p "$B4/etc/lvm-sin-ficheros"; printf '%s' "$M4" > "$B4/etc/my.cnf"
o4=$(python3 -I -c "$SECURE_PY" "$B4" "$W/o4" 1 "$CONF" "$VH" "$SSL")
check "segunda pasada: sin cambios" '[ -z "$o4" ]'
rmdir "$B4/etc/lvm-sin-ficheros"
o4=$(python3 -I -c "$SECURE_PY" "$B4" "$W/o4" 1 "$CONF" "$VH" "$SSL")
check "si falta la carpeta (MariaDB no arrancaria): solo la vuelve a pedir" '[ "$o4" = "etc/lvm-sin-ficheros/||MariaDB, carpeta vacia de secure_file_priv" ]'
printf '[mysqld]\nbind-address=127.0.0.1\nsecure-file-priv=/srv/mis-ficheros\nlocal-infile=0\n' > "$B4/etc/my.cnf"
o4=$(python3 -I -c "$SECURE_PY" "$B4" "$W/o4" 1 "$CONF" "$VH" "$SSL")
check "una carpeta puesta a mano se respeta" '[ -z "$o4" ]'
# Certificado de fabrica de XAMPP (Apache Friends): al comprobar se avisa; al aplicar, clave propia
B3=$W/b3; mkdir -p "$B3/etc/ssl.crt" "$B3/etc/ssl.key" "$B3/etc/extra" "$W/o3"
cp "$DATOS/fabrica.crt" "$B3/etc/ssl.crt/server.crt"; echo vieja > "$B3/etc/ssl.key/server.key"
printf 'Include %s\n' "$CONF" > "$B3/etc/httpd.conf"; printf "%s%s" "$VH" "$SSL" > "$B3/$CONF"
o3=$(python3 -I -c "$SECURE_PY" "$B3" "$W/o3" 1 "$CONF" "$VH" "$SSL")
check "certificado de fabrica: se avisa al comprobar" 'grep -q "^etc/ssl.crt/server.crt|" <<< "$o3" && ! grep -q "server.key" <<< "$o3"'
o3=$(LVM_SECURE_APPLY=1 python3 -I -c "$SECURE_PY" "$B3" "$W/o3" 1 "$CONF" "$VH" "$SSL")
nk=$(awk -F"|" '$1 == "etc/ssl.key/server.key" {print $2}' <<< "$o3"); nc=$(awk -F"|" '$1 == "etc/ssl.crt/server.crt" {print $2}' <<< "$o3")
check "al aplicar: clave y certificado nuevos de localhost" '[ -s "$nk" ] && openssl x509 -in "$nc" -noout -subject | grep -q "CN *= *localhost" && ! openssl x509 -in "$nc" -noout -subject | grep -q "Apache Friends"'
check "la clave nueva es del certificado nuevo" '[ "$(openssl x509 -in "$nc" -noout -pubkey)" = "$(openssl pkey -in "$nk" -pubout 2>/dev/null)" ]'
cp "$nc" "$B3/etc/ssl.crt/server.crt"
o3=$(python3 -I -c "$SECURE_PY" "$B3" "$W/o3" 1 "$CONF" "$VH" "$SSL")
check "con certificado propio: sin cambios" '[ -z "$o3" ]'
# Listen repetidos: Apache no arrancaria. Tambien en minusculas y entre comillas
B4=$W/b4; mkdir -p "$B4/etc/extra" "$W/o4"
printf 'Listen 127.0.0.1:80\nListen 192.168.1.5:80\nlisten "81"\nListen 80\nListen [::1]:80\n' > "$B4/etc/httpd.conf"
printf 'Include %s\n' "$CONF" >> "$B4/etc/httpd.conf"; printf '%s' "$VH" > "$B4/$CONF"
o4=$(python3 -I -c "$SECURE_PY" "$B4" "$W/o4" 1 "$CONF" "$VH" "$SSL")
H4=$(cat "$(awk -F"|" '$1 == "etc/httpd.conf" {print $2}' <<< "$o4")" 2> /dev/null)
check "sin Listen repetidos (127.0.0.1:80 y [::1]:80 una vez cada uno)" '[ "$(grep -c "^Listen 127.0.0.1:80$" <<< "$H4")" = 1 ] && [ "$(grep -c "^Listen \[::1\]:80$" <<< "$H4")" = 1 ] && ! grep -q 192.168 <<< "$(grep -v "^#" <<< "$H4")"'
check "listen en minusculas y entre comillas se cierra" 'grep -q "^Listen 127.0.0.1:81$" <<< "$H4"'
check "Apache acepta el resultado (httpd -t)" 'printf "%s\nServerName x\nPidFile %s/p\nErrorLog %s/e\n" "$(grep -v "^Include" <<< "$H4" | sed "s/:80$/:18990/; s/:81$/:18991/")" "$W" "$W" > "$W/t4.conf"; env LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib PHPRC=/opt/lampp-8.2.4/etc /opt/lampp-8.2.4/bin/httpd -t -f "$W/t4.conf" > "$W/t4.out" 2>&1 || grep -q "Syntax OK" "$W/t4.out"'
exit $fail
