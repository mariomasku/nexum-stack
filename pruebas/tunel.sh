#!/bin/bash
# Tunel de Cloudflare (Linux 1.56.0): con un cloudflared falso (sin Internet) y una web falsa de este
# equipo, el proxy pide la contraseña, bloquea el admin y lo de LAMPP, cambia el dominio local por el
# del tunel y se cierra del todo. Y solo comparte webs de este equipo. Uso: tunel.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-tunel.XXXX") || exit 1
UP=""
trap '[ -n "$UP" ] && kill $UP 2> /dev/null; [ -n "$(tunnel_pid 2> /dev/null)" ] && tunnel_close > /dev/null; rm -rf "$W"' EXIT
grep -q '^function tunnel_open() {' "$SRC" || { echo "  ok    (sin tunel de Cloudflare)"; exit 0; }
extract "$SRC" tunnel_installed tunnel_installed_version tunnel_install tunnel_conf tunnel_new_pass \
    tunnel_conf_write tunnel_config tunnel_pid tunnel_close tunnel_open tunnel_status || exit 1
eval "$(sed -n "/^TUNNEL_PY=\$(cat <<'PYEOF'/,/^PYEOF/p" "$SRC"; echo ')')"
[ -n "$TUNNEL_PY" ] || { echo "no esta TUNNEL_PY"; exit 1; }

LOG_DIR=$W/log DRY=0 HTDOCS_DIR=$W/htdocs TEST_DIR=$W
TUNNEL_VERSION=$(grep -oP '^TUNNEL_VERSION="\K[^"]+' "$SRC")
TUNNEL_DIR=$LOG_DIR/tunel TUNNEL_BIN=$LOG_DIR/tunel/cloudflared TUNNEL_CONF=$LOG_DIR/tunel/config
TUNNEL_STATE=$LOG_DIR/tunel/estado TUNNEL_LOG=$LOG_DIR/tunel/registro
ICON_PNG_B64=$(printf 'png' | base64)
mkdir -p "$LOG_DIR" "$HTDOCS_DIR/tienda/admin123abc" "$HTDOCS_DIR/tienda/img"
touch "$HTDOCS_DIR/tienda/admin123abc/index.php" "$HTDOCS_DIR/tienda/admin123abc/ajax-tab.php"
valid_domain() { [[ "$1" =~ ^[a-z0-9.-]+$ ]]; }
is_prestashop() { [ "$1" == tienda ]; }
ps_domain() { echo localhost; }

# Instalar: solo si coincide su sha256
printf '#!/bin/bash\necho falso\n' > "$W/bueno"
LVM_CLOUDFLARED_URL=file://$W/bueno LVM_CLOUDFLARED_SHA=0000
out=$(tunnel_install 2>&1); rc=$?
check "instalar: con otra sha256, no se instala" '[ $rc -ne 0 ] && grep -q "no coincide" <<< "$out" && ! tunnel_installed'
LVM_CLOUDFLARED_SHA=$(sha256sum "$W/bueno" | cut -d" " -f1)
out=$(tunnel_install 2>&1); rc=$?
check "instalar: con su sha256, queda en su carpeta y con su version" '[ $rc -eq 0 ] && tunnel_installed && [ "$(tunnel_installed_version)" == "$TUNNEL_VERSION" ]'
check "instalar: la carpeta del tunel, solo tuya" '[ "$(stat -c %a "$TUNNEL_DIR")" == 700 ]'

# Configuracion
tunnel_config horas 0 > /dev/null; rc=$?
check "config: las horas, de 1 a 12" '[ $rc -ne 0 ] && tunnel_config horas 12 > /dev/null && [ "$(tunnel_conf HORAS)" == 12 ]'
tunnel_config clave-nueva > /dev/null
k1=$(tunnel_conf CLAVE); tunnel_config clave-nueva > /dev/null; k2=$(tunnel_conf CLAVE)
check "config: contraseña al azar, facil de dictar y nueva cada vez" '[[ "$k1" =~ ^[a-z2-9]{4}-[a-z2-9]{4}-[a-z2-9]{4}$ ]] && [ "$k1" != "$k2" ]'
check "config: el fichero, solo tuyo" '[ "$(stat -c %a "$TUNNEL_CONF")" == 600 ]'
check "config: el admin, bloqueado salvo que se diga" '[ "$(tunnel_conf ADMIN)" == bloquear ] && ! tunnel_config admin abierto > /dev/null'
tunnel_config horas 2 > /dev/null

# Solo webs de este equipo
out=$(tunnel_open https://example.com/ 2>&1); rc=$?
check "abrir: una web de fuera no se comparte" '[ $rc -ne 0 ] && grep -q "no es una web de este equipo" <<< "$out"'
out=$(tunnel_open http://localhost/ /etc 2>&1); rc=$?
check "abrir: una carpeta fuera de htdocs no vale" '[ $rc -ne 0 ] && grep -q "no es la carpeta de un proyecto" <<< "$out"'

# La web falsa (en localhost): enlaces a si misma, una cookie con Domain, una redireccion, y lo que le llega
cat > "$W/web.py" << 'EOF'
import base64, http.server, json, sys
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n).decode() if n else ""
        port = self.server.server_address[1]
        if self.path == "/ir":
            self.send_response(302); self.send_header("Location", "http://localhost:%d/destino" % port)
            self.send_header("Content-Length", "0"); self.end_headers(); return
        seen = json.dumps({"path": self.path, "host": self.headers["Host"], "cookie": self.headers.get("Cookie", ""),
                           "origin": self.headers.get("Origin", ""), "body": body, "cf": self.headers.get("Cf-Connecting-IP", "")})
        page = ('<a href="http://localhost:%d/pagina">x</a> <a href="//localhost:%d/b">y</a> "http:\\/\\/localhost:%d\\/c" '
                'http%%3A%%2F%%2Flocalhost%%3A%d%%2Fd http://localhost.otro/e <pre>%s</pre>' % (port, port, port, port,
                base64.b64encode(seen.encode()).decode())).encode()
        self.send_response(200); self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Set-Cookie", "sesion=1; Domain=localhost; Path=/")
        self.send_header("Content-Length", str(len(page))); self.end_headers(); self.wfile.write(page)
    do_GET = do_POST = reply
s = http.server.HTTPServer(("127.0.0.1", 0), H)
print(s.server_address[1], flush=True)
s.serve_forever()
EOF
exec 3< <(python3 -I "$W/web.py")
UP=$!
read -r -t 10 WP <&3
# cloudflared falso: dice su direccion como el de verdad, apunta a donde manda y espera
cat > "$TUNNEL_BIN" << EOF
#!/bin/bash
echo "\$@" > "$W/args"
echo "INF |  https://prueba-uno-dos.trycloudflare.com                                     |"
exec sleep 600
EOF
chmod 755 "$TUNNEL_BIN"
out=$(tunnel_open "http://localhost:$WP/" tienda 2>&1); rc=$?
check "abrir: dice la direccion del tunel y la contraseña" '[ $rc -eq 0 ] && grep -q "^URL|https://prueba-uno-dos.trycloudflare.com$" <<< "$out" && grep -q "Contraseña para entrar: $k2" <<< "$out"'
check "abrir: la contraseña no va en la linea de ordenes ni queda el fichero de datos" '! grep -rq -- "$k2" /proc/$(tunnel_pid)/cmdline && [ -z "$(ls "$TUNNEL_DIR"/abrir.* 2> /dev/null)" ]'
check "abrir: cloudflared sin la configuracion de ~/.cloudflared y sin actualizarse solo" 'grep -q -- "--no-autoupdate --config /dev/null --url http://127.0.0.1:" "$W/args"'
check "estado: el tunel abierto, con su hora de cierre" 'tunnel_status | grep -qE "^T\|https://prueba-uno-dos.trycloudflare.com\|http://localhost:$WP\|$HTDOCS_DIR/tienda\|[0-9]{10}$"'
PX=$(grep -oP "127.0.0.1:\K[0-9]+" "$W/args")
B=http://127.0.0.1:$PX
c() { curl -s --max-time 10 -H "Cf-Connecting-IP: 203.0.113.$IPN" "$@"; }
IPN=1
check "sin contraseña: la pagina para escribirla (y nada de la web)" 'o=$(c -w "%{http_code}" $B/); [[ "$o" == *401 ]] && grep -q "Escribe la contraseña" <<< "$o" && ! grep -q pagina <<< "$o"'
check "contraseña equivocada: no entra" 'o=$(c -w "%{http_code}" -d "clave=mala&volver=/" $B/__nexum-tunel/entrar); [[ "$o" == *401 ]] && grep -q "Esa no es" <<< "$o"'
for n in 1 2 3 4 5 6 7; do c -o /dev/null -d "clave=mala" $B/__nexum-tunel/entrar; done
check "muchos intentos equivocados: espera, aunque luego acierte" '[ "$(c -o /dev/null -w "%{http_code}" -d "clave=$k2" $B/__nexum-tunel/entrar)" == 429 ]'
IPN=2
h=$(c -D - -o /dev/null -d "clave=$k2&volver=/hola" $B/__nexum-tunel/entrar)
check "contraseña buena: cookie segura y vuelve a donde iba" 'grep -q "^HTTP/1.0 303" <<< "$h" && grep -qi "^Location: /hola" <<< "$h" && grep -qi "Set-Cookie: nexum_tunel=[0-9a-f]*; Path=/; Secure; HttpOnly; SameSite=Lax" <<< "$h"'
CK=$(grep -oPi "Set-Cookie: \Knexum_tunel=[0-9a-f]+" <<< "$h")
check "volver a otra web tras entrar: no" '[ "$(c -o /dev/null -D - -d "clave=$k2&volver=//otra.web/" $B/__nexum-tunel/entrar | grep -i "^Location" | tr -d "\r")" == "Location: /" ]'
o=$(c -D "$W/h" -H "Cookie: nexum_tunel=${CK#*=}; otra=2" -H "Origin: https://prueba-uno-dos.trycloudflare.com" $B/pagina)
seen() { grep -oP "<pre>\K[^<]+" <<< "$1" | base64 -d; }
check "dentro: la web, con su dominio y sin la cookie del tunel ni datos de Cloudflare" 'seen "$o" | grep -q "\"host\": \"localhost:$WP\"" && seen "$o" | grep -q "\"cookie\": \"otra=2\"" && seen "$o" | grep -q "\"cf\": \"\""'
check "dentro: Origin del tunel llega como el de la web" 'seen "$o" | grep -q "\"origin\": \"http://localhost:$WP\""'
check "dentro: los enlaces llevan al tunel (normales, sin esquema, escapados y codificados)" 'grep -q "href=\"https://prueba-uno-dos.trycloudflare.com/pagina\"" <<< "$o" && grep -q "href=\"https://prueba-uno-dos.trycloudflare.com/b\"" <<< "$o" && grep -qF "https:\/\/prueba-uno-dos.trycloudflare.com\/c" <<< "$o" && grep -q "https%3A%2F%2Fprueba-uno-dos.trycloudflare.com%2Fd" <<< "$o"'
check "dentro: otro dominio que empieza igual no se toca" 'grep -q "http://localhost.otro/e" <<< "$o"'
check "dentro: la cookie de la web, sin Domain" 'grep -qi "^Set-Cookie: sesion=1; Path=/" "$W/h" && ! grep -qi "domain=" "$W/h"'
check "dentro: sin indexar" 'grep -qi "^X-Robots-Tag: noindex" "$W/h"'
o=$(c -H "Cookie: $CK" -d "url=https://prueba-uno-dos.trycloudflare.com/x" $B/formulario)
check "formulario: la direccion del tunel llega como la de la web" 'seen "$o" | grep -q "\"body\": \"url=http://localhost:$WP/x\""'
check "redireccion: lleva al tunel" '[ "$(c -o /dev/null -D - -H "Cookie: $CK" $B/ir | grep -i "^Location" | tr -d "\r")" == "Location: https://prueba-uno-dos.trycloudflare.com/destino" ]'
code() { c -o /dev/null -w "%{http_code}" -H "Cookie: $CK" "$B$1"; }
check "bloqueado: el admin de WordPress, su acceso y xmlrpc" '[ "$(code /wp-admin/)" == 403 ] && [ "$(code /WP-ADMIN/options.php)" == 403 ] && [ "$(code /wp-login.php)" == 403 ] && [ "$(code /xmlrpc.php)" == 403 ]'
check "bloqueado: el admin de la tienda (su carpeta)" '[ "$(code /admin123abc/index.php)" == 403 ] && [ "$(code /Admin123ABC)" == 403 ]'
check "bloqueado: phpMyAdmin y lo de LAMPP, ocultos y rutas con .." '[ "$(code /phpmyadmin/)" == 403 ] && [ "$(code /server-status)" == 403 ] && [ "$(code /.env)" == 403 ] && [ "$(code /.git/config)" == 403 ] && [ "$(code /x/%2e%2e/phpmyadmin/)" == 403 ] && [ "$(code /%70hpmyadmin/)" == 403 ]'
check "no bloqueado: admin-ajax de WordPress y .well-known" '[ "$(code /wp-admin/admin-ajax.php)" == 200 ] && [ "$(code /.well-known/x)" == 200 ]'
check "cookie inventada: no entra" '[ "$(c -o /dev/null -w "%{http_code}" -H "Cookie: nexum_tunel=0000" $B/)" == 401 ]'

# Cerrar: el tunel, cloudflared y el proxy
P1=$(tunnel_pid)
out=$(tunnel_close); sleep 0.5
check "cerrar: se para todo y se olvida" '! kill -0 $P1 2> /dev/null && [ ! -e "$TUNNEL_STATE" ] && ! pgrep -f "$W/log/tunel/cloudflared" > /dev/null && ! tunnel_status | grep -q "^T|"'
check "cerrado: el proxy ya no contesta" '! curl -s --max-time 3 $B/ > /dev/null'
# Con el admin permitido
tunnel_config admin permitir > /dev/null
tunnel_open "http://localhost:$WP/" tienda > /dev/null 2>&1
PX=$(grep -oP "127.0.0.1:\K[0-9]+" "$W/args") B=http://127.0.0.1:$PX IPN=3
h=$(c -D - -o /dev/null -d "clave=$(tunnel_conf CLAVE)" $B/__nexum-tunel/entrar); CK=$(grep -oPi "Set-Cookie: \Knexum_tunel=[0-9a-f]+" <<< "$h")
check "admin permitido: wp-admin pasa, phpMyAdmin sigue bloqueado" '[ "$(code /wp-admin/)" == 200 ] && [ "$(code /phpmyadmin/)" == 403 ]'
# Abrir otro cierra el de antes
P1=$(tunnel_pid)
tunnel_open "http://localhost:$WP/" > /dev/null 2>&1
check "abrir otro: el de antes se cierra (uno cada vez)" '! kill -0 $P1 2> /dev/null && [ -n "$(tunnel_pid)" ] && [ "$(tunnel_pid)" != "$P1" ]'
tunnel_close > /dev/null
# cloudflared que no da direccion: lo dice y no deja nada
printf '#!/bin/bash\necho "ERR failed to request quick Tunnel"\nexit 1\n' > "$TUNNEL_BIN"
out=$(tunnel_open "http://localhost:$WP/" 2>&1); rc=$?
check "sin direccion de Cloudflare: lo dice, con lo ultimo de cloudflared" '[ $rc -ne 0 ] && grep -q "No se ha podido abrir el tunel" <<< "$out" && grep -q "failed to request quick Tunnel" <<< "$out" && [ ! -e "$TUNNEL_STATE" ]'

# La ventana: Compartir en los dos visores, con el logotipo de Cloudflare, y su apartado en Configuración
check "ventana: Compartir en el visor del proyecto cargado y en el de Docker" '[ "$(grep -c "self.nv_share_button(" "$SRC")" -ge 2 ] && grep -q "self.nv_share(t, folder, p\[\"folder\"\])" "$SRC"'
check "ventana: el logotipo de Cloudflare y su apartado en Configuración" 'grep -q "^    \"cloudflare\": ($" "$SRC" && grep -q "self.nv_tunnel_tools()" "$SRC"'
check "ventana: pregunta antes de abrir un tunel" 'awk "/    def nv_share\\(self/,/    def nv_share_dialog/" "$SRC" | grep -q "if not confirm(self.win"'
exit $fail
