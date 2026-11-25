#!/bin/bash
# Apache con la configuracion de antes (1.57.20): apache_stale avisa si etc/httpd.conf o etc/extra/*.conf
# son mas nuevos que su ultima carga (la ultima AH00489 de logs/error_log), y la ventana lo recibe en
# gui-datos (K|version). Uso: apache-recargado.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
eval "$(sed -n "/^APACHE_STALE_PY='/,/^'\$/p" "$SRC")"
[ -n "$APACHE_STALE_PY" ] || { echo "no esta APACHE_STALE_PY"; exit 1; }
extract "$SRC" apache_stale || exit 1
R=$W/raiz; mkdir -p "$R/etc/extra" "$R/logs"
: > "$R/etc/httpd.conf"; : > "$R/etc/extra/lvm-dominio-desconocido.conf"
# (la hora de la linea de Apache, en su formato: [Tue Nov 17 10:28:46.492640 2026])
stamp() { LC_ALL=C date -d "@$1" '+%a %b %d %H:%M:%S.123456 %Y'; }
now=$(date +%s)
{ echo "[$(stamp $((now - 7200)))] [mpm_event:notice] [pid 1:tid 1] AH00489: Apache/2.4.71 (Unix) configured -- resuming normal operations"
  echo "[$(stamp $((now - 3600)))] [mpm_event:notice] [pid 1:tid 1] AH00493: SIGUSR1 received.  Doing graceful restart"
  echo "[$(stamp $((now - 3600)))] [mpm_event:notice] [pid 1:tid 1] AH00489: Apache/2.4.71 (Unix) configured -- resuming normal operations"
  echo "[$(stamp $((now - 3000)))] [php:warn] [pid 9] un aviso cualquiera"; } > "$R/logs/error_log"
touch -d "@$((now - 5000))" "$R/etc/httpd.conf" "$R/etc/extra/lvm-dominio-desconocido.conf"
check "al dia: la configuracion es de antes de la ultima recarga" '! apache_stale "$R"'
touch -d "@$((now - 1800))" "$R/etc/extra/lvm-dominio-desconocido.conf"
check "de antes: la barrera escrita despues de la ultima recarga, avisa" 'apache_stale "$R"'
touch -d "@$((now - 5000))" "$R/etc/extra/lvm-dominio-desconocido.conf"; touch -d "@$((now - 1800))" "$R/etc/httpd.conf"
check "de antes: tambien por httpd.conf" 'apache_stale "$R"'
echo "[$(stamp $((now - 600)))] [mpm_event:notice] [pid 1:tid 1] AH00489: Apache/2.4.71 (Unix) configured -- resuming normal operations" >> "$R/logs/error_log"
check "recargado despues: ya no avisa (cuenta la ultima linea)" '! apache_stale "$R"'
touch -d "@$((now - 598))" "$R/etc/httpd.conf"
check "escrita justo en la recarga (unos segundos de margen): no avisa" '! apache_stale "$R"'
touch -d "@$((now - 60))" "$R/etc/httpd.conf"
mv "$R/logs/error_log" "$R/logs/otro"
check "sin registro (o sin permiso para leerlo): no dice nada" '! apache_stale "$R"'
grep -v AH00489 "$R/logs/otro" > "$R/logs/error_log"
check "registro sin ninguna carga (vaciado): no dice nada" '! apache_stale "$R"'
check "sin raiz: no dice nada" '! apache_stale "" && ! apache_stale "$W/no-existe"'
check "gui-datos: K| solo con Apache en marcha" 'grep -qF "apache_stale \"\$active" "$SRC" && grep -q "echo \"K|" "$SRC"'
exit $fail
