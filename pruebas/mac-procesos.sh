#!/bin/bash
# Prueba (Mac) de lampp_processes con salida de ps inventada: un .pid con 1, con un programa del
# sistema o con el httpd de la version montada no hace que se cierren. Uso: mac-procesos.sh <mac.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-mp.XXXX"); trap 'rm -rf "$W"' EXIT
extract "$SRC" lampp_processes || exit 1
DRY=0 BASE_DIR=$W LINK=$W/XAMPP
mkdir -p "$W/XAMPP-8.4/xamppfiles/logs" "$W/XAMPP-7.4/xamppfiles/logs"; ln -s "$W/XAMPP-8.4" "$W/XAMPP"
d=$(LC_ALL=C date -d "+2 minutes" "+%a %b %d %H:%M:%S %Y")
cat > "$W/ps" <<P
    1     0 root     $d /sbin/launchd
  300     1 root     $d /usr/sbin/cupsd -l
  500     1 root     $d $W/XAMPP/xamppfiles/apache2/bin/httpd -f $W/XAMPP/xamppfiles/etc/httpd.conf
  501   500 daemon   $d $W/XAMPP/xamppfiles/apache2/bin/httpd -f $W/XAMPP/xamppfiles/etc/httpd.conf
P
printf '1\n' > "$W/XAMPP-7.4/xamppfiles/logs/httpd.pid"
LVM_PS=$W/ps out=$(lampp_processes)
check "un .pid con 1 no marca launchd ni sus hijos" '! grep -qE "^P\|(1|300)\|" <<< "$out"'
printf '500\n' > "$W/XAMPP-7.4/xamppfiles/logs/httpd.pid"
LVM_PS=$W/ps out=$(lampp_processes)
check "el httpd de la montada escrito en el .pid de otra no se cierra" '! grep -qE "^P\|500\|[^|]*\|[^|]*\|[^|]*\|1\|" <<< "$out"'
exit $fail
