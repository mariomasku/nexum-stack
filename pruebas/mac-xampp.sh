#!/bin/bash
# Prueba (Mac) del parche de SECURE_PY a un script xampp de la 1.27 y del script nuevo. Uso: mac-xampp.sh <mac.sh> <mac-1.27.1.sh>
SRC=$1 OLD=$2 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-mx.XXXX"); trap 'rm -rf "$W"' EXIT
getvar() { ( eval "$(sed -n "/^$1='/,/^'\$/p" "$SRC")"; printf '%s.' "${!1}" ); }
SP=$(getvar SECURE_PY); SP=${SP%.}; VH=$(getvar UNKNOWN_HOST_VHOST); VH=${VH%.}; SSL=$(getvar UNKNOWN_HOST_SSL); SSL=${SSL%.}
CONF=$(grep -m1 '^UNKNOWN_HOST_CONF=' "$SRC" | cut -d= -f2)
heredoc() { awk '/> "\$S\/xampp" <<.EOF.$/{p=1;next} p&&/^EOF$/{exit} p' "$1"; }
B=$W/b; mkdir -p "$B/etc/extra" "$W/o"
heredoc "$OLD" | sed -e "s|@ROOT@|$B|g" -e "s|@NAME@|8.4|g" -e "s|@NEED_ROOT@|1|g" > "$B/xampp"
printf '[mysqld]\nuser = pepe\nbind-address = 127.0.0.1\n' > "$B/etc/my.cnf"
printf 'Include %s\n' "$CONF" > "$B/etc/httpd.conf"; printf '%s' "$VH" > "$B/$CONF"
out=$(python3 -I -c "$SP" "$B" "$W/o" 1 "$CONF" "$VH" "$SSL")
dst=$(awk -F'|' '$1 == "xampp" {print $2}' <<< "$out")
check "xampp de la 1.27: se parchea" '[ -n "$dst" ] && grep -q "^WEB_USER=pepe$" "$dst" && grep -q "as_web /usr/bin/nohup ./bin/mariadbd-safe" "$dst" && grep -q "as_web kill" "$dst"'
check "el parcheado es bash valido" 'bash -n "$dst"'
cp "$dst" "$B/xampp"; out=$(python3 -I -c "$SP" "$B" "$W/o" 1 "$CONF" "$VH" "$SSL")
check "segunda pasada: sin cambios" '! grep -q "^xampp|" <<< "$out"'
heredoc "$SRC" | sed -e "s|@ROOT@|$B|g" -e "s|@NAME@|8.4|g" -e "s|@NEED_ROOT@|1|g" -e "s|@WEB_USER@|pepe|g" > "$W/nuevo"
check "xampp nuevo: bash valido, MariaDB con el usuario" 'bash -n "$W/nuevo" && grep -q "^WEB_USER=pepe$" "$W/nuevo" && grep -q "^export PATH=/usr/bin:/bin:/usr/sbin:/sbin$" "$W/nuevo"'
exit $fail
