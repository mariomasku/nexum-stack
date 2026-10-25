#!/bin/bash
# Pruebas de la barrera entre webs (1.54.1) en un Apache temporal (puertos 28471 y 28472, solo
# 127.0.0.1, como web.sh): lo que manda otra web a web.local, con la barrera encendida y apagada, y
# peticiones de mas de 64 MB. Tambien que SECURE_PY rehace lvm-dominio-desconocido.conf al cambiarla
# y que los vhosts la admiten. Uso: barrera.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q '^function host_vhost() {' "$SRC" || { echo "  ok    (sin barrera entre webs)"; exit 0; }
W=$(mktemp -d "$TMPBASE/w-barrera.XXXX")
getvar() { ( eval "$(sed -n "/^$1='/,/^'\$/p" "$SRC")"; printf '%s.' "${!1}" ); }
VH=$(getvar UNKNOWN_HOST_VHOST); VH=${VH%.}
SECURE_PY=$(getvar SECURE_PY); SECURE_PY=${SECURE_PY%.}
SSL=$(getvar UNKNOWN_HOST_SSL); SSL=${SSL%.}
VCHECK=$(getvar VHOSTS_CHECK_PY); VCHECK=${VCHECK%.}
CONF=$(grep -m1 '^UNKNOWN_HOST_CONF=' "$SRC" | cut -d= -f2)
extract "$SRC" host_vhost cross_site_on || exit 1
CROSS_SITE_OFF=$W/sin-barrera-entre-webs UNKNOWN_HOST_VHOST=$VH
host_vhost; ON=$HOST_VHOST
: > "$CROSS_SITE_OFF"; host_vhost; OFF=$HOST_VHOST; rm -f "$CROSS_SITE_OFF"
check "encendida: el texto de siempre (UNKNOWN_HOST_VHOST)" '[ "$ON" == "$VH" ]'
check "apagada: sin la regla y con lo demas" '! grep -q "HTTP:Sec-Fetch-Mode" <<< "$OFF" && grep -q "LimitRequestBody 67108864" <<< "$OFF" && grep -q "TraceEnable Off" <<< "$OFF" && grep -q "/phpmyadmin" <<< "$OFF"'
check "apagada: acaba en salto de linea, como la encendida" '[ "${OFF: -1}" == $'"'"'\n'"'"' ]'

# SECURE_PY: rehace el fichero de una version al cambiar la barrera (y no lo toca si ya esta)
B=$W/base; mkdir -p "$B/etc/extra" "$W/o"
printf 'Listen 127.0.0.1:80\nInclude %s\nInclude etc/extra/httpd-vhosts.conf\n' "$CONF" > "$B/etc/httpd.conf"
: > "$B/etc/extra/httpd-vhosts.conf"
printf '%s' "$ON" > "$B/$CONF"
out=$(python3 -I -c "$SECURE_PY" "$B" "$W/o" 0 "$CONF" "$ON" "$SSL")
check "SECURE_PY: con la barrera ya puesta, nada que cambiar" '! grep -q "^$CONF|" <<< "$out"'
out=$(python3 -I -c "$SECURE_PY" "$B" "$W/o" 0 "$CONF" "$OFF" "$SSL")
dst=$(awk -F'|' -v r="$CONF" '$1 == r {print $2}' <<< "$out")
check "SECURE_PY: al apagarla, el fichero se rehace sin ella" '[ -n "$dst" ] && ! grep -q "HTTP:Sec-Fetch-Mode" "$dst" && [ "$(cat "$dst"; echo .)" == "$OFF." ]'
printf '# lvm-instalador: dominios que no tienen ningun vhost (de la 1.54.0)\n' > "$B/$CONF"
out=$(python3 -I -c "$SECURE_PY" "$B" "$W/o" 0 "$CONF" "$ON" "$SSL")
dst=$(awk -F'|' -v r="$CONF" '$1 == r {print $2}' <<< "$out")
check "SECURE_PY: el de una version anterior pasa a llevarla" '[ -n "$dst" ] && grep -q "HTTP:Sec-Fetch-Mode" "$dst"'

# Los vhosts admiten la misma regla (por ejemplo, para un proyecto concreto)
sed -n '/^# >>> barrera entre webs/,/^# <<< barrera entre webs/p' <<< "$VH" \
    | sed 's/^/    /' | sed '1i <VirtualHost *:80>\n    ServerName tienda.local' | sed '$a </VirtualHost>' > "$W/vh.conf"
check "VHOSTS_CHECK_PY admite la regla en un vhost" 'python3 -I -c "$VCHECK" "$W/vh.conf" > /dev/null'

# --- En un Apache de verdad (el de la 8.2.4, como web.sh) ---
[ -x /opt/lampp-8.2.4/bin/httpd ] || { echo "  ok    (sin /opt/lampp-8.2.4: no se prueba en Apache)"; rm -rf "$W"; exit $fail; }
start() {
    printf '%s' "$1" | sed 's#<VirtualHost \*:80>#<VirtualHost *:28471 *:28472>#' > "$W/a/unk.conf"
    python3 -I "$HERE/apache-temporal.py" /opt/lampp-8.2.4/etc/httpd.conf "$W/a" "$W/a/unk.conf" || return 1
    env LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib /opt/lampp-8.2.4/bin/httpd -f "$W/a/httpd.conf" -k start 2> "$W/arranque.txt" || { cat "$W/arranque.txt"; return 1; }
    for i in $(seq 30); do curl -s -o /dev/null http://127.0.0.1:28471/ && return 0; sleep 0.2; done
    return 1
}
stop() { env LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib /opt/lampp-8.2.4/bin/httpd -f "$W/a/httpd.conf" -k stop 2> /dev/null; sleep 1; }
trap 'stop; rm -rf "$W"' EXIT
mkdir -p "$W/a"
start "$ON" || { echo "  FALLA no arranca el Apache de prueba"; exit 1; }
wl() { curl -s -o /dev/null -w '%{http_code}' -H "Host: web.local" "$@"; }
U=http://127.0.0.1:28471
check "web.local: formulario desde otra web (cross-site, POST): 403" '[ "$(wl -X POST -H "Sec-Fetch-Site: cross-site" -H "Sec-Fetch-Mode: navigate" -H "Sec-Fetch-Dest: document" -H "Origin: https://evil.example" -d x=1 "$U/no-existe.php")" = 403 ]'
check "web.local: fetch desde otra web (cors): 403" '[ "$(wl -X POST -H "Sec-Fetch-Site: cross-site" -H "Sec-Fetch-Mode: cors" -H "Sec-Fetch-Dest: empty" -d x=1 "$U/no-existe.php")" = 403 ]'
check "web.local: imagen o script desde otra web: 403" '[ "$(wl -H "Sec-Fetch-Site: cross-site" -H "Sec-Fetch-Mode: no-cors" -H "Sec-Fetch-Dest: image" "$U/no-existe.png")" = 403 ]'
check "web.local: POST con Origin de otra web (navegador sin Sec-Fetch): 403" '[ "$(wl -X POST -H "Origin: https://evil.example" -d x=1 "$U/no-existe.php")" = 403 ]'
check "web.local: Origin null (iframe sandbox): 403" '[ "$(wl -X POST -H "Origin: null" -d x=1 "$U/no-existe.php")" = 403 ]'
check "web.local: enlace desde otra web (navegacion GET): pasa" '[ "$(wl -H "Sec-Fetch-Site: cross-site" -H "Sec-Fetch-Mode: navigate" -H "Sec-Fetch-Dest: document" "$U/no-existe.php?x=1")" = 404 ]'
check "web.local: POST de la propia web: pasa" '[ "$(wl -X POST -H "Sec-Fetch-Site: same-origin" -H "Origin: http://web.local" -d x=1 "$U/no-existe.php")" = 404 ]'
check "web.local: webhook de un servidor (sin Origin ni Sec-Fetch): pasa" '[ "$(wl -X POST -d x=1 "$U/no-existe.php")" = 404 ]'
check "localhost: formulario desde otra web: 403" '[ "$(curl -s -o /dev/null -w "%{http_code}" -H "Host: localhost" -X POST -H "Sec-Fetch-Site: cross-site" -d x=1 "$U/no-existe.php")" = 403 ]'
head -c 70000000 /dev/zero > "$W/grande"
check "peticion de mas de 64 MB: 413" '[ "$(wl -X POST --data-binary @"$W/grande" "$U/no-existe.php")" = 413 ]'
rm -f "$W/grande"
stop
start "$OFF" || { echo "  FALLA no arranca el Apache de prueba sin la barrera"; exit 1; }
check "apagada: el formulario de una pasarela de pago pasa" '[ "$(wl -X POST -H "Sec-Fetch-Site: cross-site" -H "Sec-Fetch-Mode: navigate" -H "Sec-Fetch-Dest: document" -H "Origin: https://pagos.example" -d x=1 "$U/no-existe.php")" = 404 ]'
check "apagada: phpMyAdmin sigue protegido" '[ "$(curl -s -o /dev/null -w "%{http_code}" -H "Host: 127.0.0.1:28471" -X POST -H "Origin: https://evil.example" -d x=1 "$U/phpmyadmin/no-existe.php")" = 403 ]'
exit $fail
