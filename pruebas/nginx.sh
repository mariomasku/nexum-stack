#!/bin/bash
# Pruebas de Nginx (pestaña Nginx, 1.57.38): un servidor web aparte de Apache, en ~/.nexum/nginx y con tu
# usuario, solo en este equipo (127.0.0.1 y ::1), en 8080 y 8443 de serie, con cada proyecto por su nombre
# (<carpeta>.localhost) y el PHP-FPM de la versión activa. Sin descargar ni compilar nada: el código de Nginx
# es uno falso (su configure y su make hacen un nginx falso) y la orden nginx, la falsa.
# Uso: nginx.sh <lvm-instalador.sh de Linux o del Mac>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-nginx.XXXX") || exit 1
trap 'kill $(cat "$W/ajustes/nginx/run/nginx.pid" 2> /dev/null) $BUSY 2> /dev/null; rm -rf "$W"' EXIT
extract "$SRC" nginx_get nginx_installed nginx_installed_version nginx_host nginx_projects nginx_root_guess nginx_running \
    nginx_php_state nginx_port_free nginx_build nginx_install nginx_cert nginx_write_conf nginx_apply nginx_start nginx_stop \
    nginx_add nginx_remove nginx_ports nginx_log nginx_trust_all gui_nginx nginx_command nginx_deps_missing nginx_build_deps \
    nginx_build_flags nginx_trust valid_project || exit 1
MAC=0
grep -q "^let ERROR_LOG = " "$SRC" && MAC=1
LOG_DIR=$W/ajustes HTDOCS_DIR=$W/htdocs DRY=0 TEST_DIR=$W LAMPP_LINK=$W/lampp LINK=$W/xampp
eval "$(sed -n '/^NGINX_VERSION=/,/^NGINX_HTTPS_DEFAULT=/p; /^NGINX_PHP_SOCK=/p; /^NGINX_BUILD_DEPS=/p' "$SRC")"
task_plan() { echo "plan $*" >> "$W/hecho.log"; }
task_step() { :; }
active_dir() { echo "$W/lampp"; }
is_fpm_install() { return 0; }
# (lo de cada sistema para compilar, de mentira: aquí solo se prueba el recorrido)
nginx_build_deps() { echo deps >> "$W/hecho.log"; }
nginx_build_flags() { NGINX_BUILD_FLAGS=(--falsa="con espacio"); }
mkdir -p "$HTDOCS_DIR/tienda-laravel/public" "$HTDOCS_DIR/Mi Web_2" "$HTDOCS_DIR/antiguo/web" "$HTDOCS_DIR/__"
touch "$HTDOCS_DIR/tienda-laravel/public/index.php" "$HTDOCS_DIR/antiguo/web/app.php"
ln -s "$HTDOCS_DIR/tienda-laravel" "$HTDOCS_DIR/enlace"

# El código de Nginx, falso: su configure guarda lo que le llega y su make install deja un nginx falso que
# arranca (un proceso que espera), se para (-s quit), recarga (-s reload) y prueba la configuración (-t:
# falla si la configuración lleva ROMPER)
mkdir -p "$W/src/nginx-$NGINX_VERSION"
cat > "$W/src/nginx-$NGINX_VERSION/configure" << 'EOF'
#!/bin/bash
printf '%s\n' "$@" > configure.args
p=$(sed -n 's/^--prefix=//p' configure.args)
printf 'all:\n\t@true\ninstall:\n\tmkdir -p $(DESTDIR)%s/sbin $(DESTDIR)%s/conf\n\tcp nginx.falso $(DESTDIR)%s/sbin/nginx\n\ttouch $(DESTDIR)%s/conf/mime.types $(DESTDIR)%s/conf/fastcgi_params\n' "$p" "$p" "$p" "$p" "$p" > Makefile
cp configure.args "$FALSO_ARGS"
EOF
cat > "$W/src/nginx-$NGINX_VERSION/nginx.falso" << 'EOF'
#!/bin/bash
# (nginx falso: -p <run> -c <conf> -e <log> [-t -q | -s quit|reload])
conf="" run="" t=0 sig=""
while [ $# -gt 0 ]; do
    case $1 in
        -p) run=$2; shift ;; -c) conf=$2; shift ;; -e) shift ;; -t) t=1 ;; -q) ;; -s) sig=$2; shift ;;
    esac
    shift
done
echo "nginx $t $sig $conf" >> "$run/../ordenes.log"
if [ $t -eq 1 ]; then grep -q ROMPER "$conf" && { echo "nginx: [emerg] rota" >&2; exit 1; }; exit 0; fi
case $sig in
    quit) kill "$(cat "$run/nginx.pid")"; rm -f "$run/nginx.pid"; exit 0 ;;
    reload) exit 0 ;;
esac
cp "$(command -v sleep)" "$run/nginx"
"$run/nginx" 300 > /dev/null 2>&1 < /dev/null &
echo $! > "$run/nginx.pid"
EOF
chmod +x "$W/src/nginx-$NGINX_VERSION/configure" "$W/src/nginx-$NGINX_VERSION/nginx.falso"
tar -czf "$W/nginx.tar.gz" -C "$W/src" "nginx-$NGINX_VERSION"
GOOD=$( (sha256sum "$W/nginx.tar.gz" 2> /dev/null || shasum -a 256 "$W/nginx.tar.gz") | cut -d' ' -f1)
export FALSO_ARGS=$W/configure.args
LVM_NGINX_URL=file://$W/nginx.tar.gz
free_port() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }

check "Nginx fijado: versión y huella sha256 (la de nginx.org)" '[[ "$NGINX_VERSION" =~ ^1\.[0-9]+\.[0-9]+$ ]] && [[ "$NGINX_SHA256" =~ ^[0-9a-f]{64}$ ]] && grep -qF "url=https://nginx.org/download/nginx-\$NGINX_VERSION.tar.gz" "$SRC"'
check "todo en ~/.nexum/nginx: programa, ajustes, proyectos, configuración y registro" '[ "$NGINX_DIR" == "$LOG_DIR/nginx" ] && [ "$NGINX_BIN" == "$NGINX_DIR/programa/sbin/nginx" ]'
check "puertos de serie: 8080 y 8443" '[ "$(nginx_get HTTP)" == 8080 ] && [ "$(nginx_get HTTPS)" == 8443 ]'
check "nombre: <carpeta>.localhost, en minúsculas y con guiones" '[ "$(nginx_host "Mi Web_2")" == mi-web-2.localhost ] && [ "$(nginx_host tienda-laravel)" == tienda-laravel.localhost ] && ! nginx_host "__" > /dev/null'
if [ $MAC -eq 1 ]; then
    check "Mac: el PHP-FPM de la versión activa (/Applications/XAMPP)" '[ "$NGINX_PHP_SOCK" == "$LINK/xamppfiles/var/run/php-fpm.sock" ]'
    check "Mac: compila con pcre2 y openssl@3 de Homebrew y confía en el llavero" 'grep -qF "pcre=\$(brew_quiet --prefix pcre2 2> /dev/null) && ssl=\$(brew_quiet --prefix openssl@3 2> /dev/null)" "$SRC" && grep -qF "NGINX_BUILD_FLAGS=(--with-cc-opt=\"-I\$pcre/include -I\$ssl/include\" --with-ld-opt=\"-L\$pcre/lib -L\$ssl/lib\")" "$SRC" && grep -qF "security add-trusted-cert -r trustRoot -p ssl -k \"\$HOME/Library/Keychains/login.keychain-db\" \"\$crt\"" "$SRC"'
else
    check "Linux: el PHP-FPM de la versión activa (/opt/lampp)" '[ "$NGINX_PHP_SOCK" == "$LAMPP_LINK/var/run/php-fpm.sock" ] && [ "$NGINX_BUILD_DEPS" == "gcc make libpcre2-dev libssl-dev zlib1g-dev" ]'
    check "Linux: pide la contraseña solo si falta un paquete para compilarlo" 'grep -qxF "        nginx-instalar) nginx_deps_missing && { sudo_first || exit 130; } ;;" "$SRC"'
fi
check "lo demás de Nginx, sin contraseña" 'grep -qF "|copias-ficheros|manual|nginx-arrancar|nginx-parar|nginx-reiniciar|nginx-anadir|nginx-quitar|nginx-puertos|nginx-registro|nginx-confiar) ;;" "$SRC" && grep -qxF "    gui-nginx) gui_nginx ;;" "$SRC" && grep -qxF "    nginx-instalar|nginx-arrancar|nginx-parar|nginx-reiniciar|nginx-anadir|nginx-quitar|nginx-puertos|nginx-registro|nginx-confiar) nginx_command \"\$@\" ;;" "$SRC"'
check "nunca sudo ni root en lo común de Nginx" '! sed -n "/^function nginx_get() {/,/^function nginx_command() {/p" "$SRC" | grep -vE "^ *#" | grep -qE "(^|[^_])sudo |\\\$SUDO"'

# Puertos
o=$(nginx_ports 80 8443); check "puertos: los de menos de 1024, no" '[[ "$o" == *"no válido: 80"* ]] && [ ! -f "$NGINX_SETTINGS" ]'
o=$(nginx_ports 9000 9000); check "puertos: http y https, distintos" '[[ "$o" == *"mismo puerto"* ]] && [ ! -f "$NGINX_SETTINGS" ]'
P1=$(free_port) P2=$(free_port)
[ "$P1" == "$P2" ] && P2=$((P1 + 1))
o=$(nginx_ports "$P1" "$P2"); check "puertos: se guardan (solo tuyos) y valen" '[ "$(nginx_get HTTP)" == "$P1" ] && [ "$(nginx_get HTTPS)" == "$P2" ] && [ "$(stat -c %a "$NGINX_SETTINGS" 2> /dev/null || stat -f %Lp "$NGINX_SETTINGS")" == 600 ]'

# Instalar: la huella manda
o=$(LVM_NGINX_SHA=$(printf '0%.0s' $(seq 64)) nginx_build 2>&1)
check "instalar: si la huella no coincide, no se instala" '[[ "$o" == *"no coincide"* ]] && ! nginx_installed && [ -z "$(ls -d "$NGINX_DIR"/compilar.* 2> /dev/null)" ]'
: > "$W/hecho.log"
o=$(LVM_NGINX_SHA=$GOOD nginx_install 2>&1)
check "instalar: con su lista de pasos, lo que hace falta y Nginx en ~/.nexum/nginx/programa" 'grep -q "^plan Instalando Nginx $NGINX_VERSION Lo que hace falta para compilarlo Nginx $NGINX_VERSION" "$W/hecho.log" && grep -qx deps "$W/hecho.log" && nginx_installed && [ "$(nginx_installed_version)" == "$NGINX_VERSION" ] && [[ "$o" == *"Huella de Nginx $NGINX_VERSION: buena"* ]]'
check "compilado con su carpeta, https, http/2 y las opciones del sistema (enteras, con sus espacios)" 'grep -qx -- "--prefix=$NGINX_PREFIX" "$W/configure.args" && grep -qx -- "--with-http_ssl_module" "$W/configure.args" && grep -qx -- "--with-http_v2_module" "$W/configure.args" && grep -qx -- "--falsa=con espacio" "$W/configure.args" && [ -z "$(ls -d "$NGINX_DIR"/compilar.* 2> /dev/null)" ]'
check "instalar y arrancar como root, no" '[ "$(grep -cF '"'"'[ "$EUID" -eq 0 ] && { echo "Nginx '"'"' "$SRC")" -eq 2 ]'

# Proyectos
o=$(nginx_add no-existe); check "añadir: una carpeta que no existe, no" '[[ "$o" == *"No existe el proyecto"* ]] && [ ! -s "$NGINX_LIST" ]'
o=$(nginx_add enlace); check "añadir: un enlace, no" '[[ "$o" == *"No existe el proyecto"* ]]'
o=$(nginx_add "__"); check "añadir: sin letras ni números para su nombre, no" '[[ "$o" == *"no se puede hacer un nombre"* ]] && [ ! -s "$NGINX_LIST" ]'
o=$(nginx_add tienda-laravel ../..); check "añadir: una subcarpeta fuera del proyecto, no" '[[ "$o" == *"Subcarpeta no válida"* ]] && [ ! -s "$NGINX_LIST" ]'
o=$(nginx_add tienda-laravel); check "añadir: con public/, sirve public/ (Laravel, Symfony)" 'grep -qx "tienda-laravel|public" "$NGINX_LIST" && [[ "$o" == *"http://tienda-laravel.localhost:$P1 y https://tienda-laravel.localhost:$P2 (sirve public/)"* ]]'
o=$(nginx_add antiguo); check "añadir: con web/app.php, sirve web/" 'grep -qx "antiguo|web" "$NGINX_LIST"'
o=$(nginx_add "Mi Web_2" ""); check "añadir: sin subcarpeta, la carpeta entera" 'grep -qx "Mi Web_2|" "$NGINX_LIST"'
mkdir -p "$HTDOCS_DIR/mi web 2"
o=$(nginx_add "mi web 2"); check "añadir: dos carpetas con el mismo nombre en Nginx, no" '[[ "$o" == *"Mi Web_2 ya usa mi-web-2.localhost"* ]] && ! grep -q "^mi web 2|" "$NGINX_LIST"'
check "su certificado: propio, de su nombre, no de una CA, y la clave solo tuya" 'openssl x509 -in "$NGINX_DIR/certs/tienda-laravel.localhost.crt" -noout -text | grep -qF "DNS:tienda-laravel.localhost" && openssl x509 -in "$NGINX_DIR/certs/tienda-laravel.localhost.crt" -noout -text | grep -q "CA:FALSE" && [ "$(stat -c %a "$NGINX_DIR/certs/tienda-laravel.localhost.key" 2> /dev/null || stat -f %Lp "$NGINX_DIR/certs/tienda-laravel.localhost.key")" == 600 ]'
C=$NGINX_CONF
check "configuración: solo en este equipo (127.0.0.1 y ::1), nunca abierta a la red" '[ "$(grep -cE "^ *listen " "$C")" -gt 0 ] && ! grep -E "^ *listen " "$C" | grep -vqE "listen (127\.0\.0\.1|\[::1\]):[0-9]+( ssl)?( default_server)?;"'
check "configuración: lo que no es el nombre de un proyecto, sin respuesta (ni por https)" 'grep -qF "listen 127.0.0.1:$P1 default_server;" "$C" && grep -qF "ssl_reject_handshake on;" "$C" && grep -qF "return 444;" "$C"'
check "configuración: cada proyecto por su nombre, su carpeta (con espacios) y su certificado" 'grep -qF "server_name tienda-laravel.localhost;" "$C" && grep -qF "root \"$HTDOCS_DIR/tienda-laravel/public\";" "$C" && grep -qF "root \"$HTDOCS_DIR/Mi Web_2\";" "$C" && grep -qF "ssl_certificate \"$NGINX_DIR/certs/mi-web-2.localhost.crt\";" "$C"'
check "configuración: PHP por el PHP-FPM de la versión activa, con PATH_INFO y HTTPS" 'grep -qF "fastcgi_pass unix:$NGINX_PHP_SOCK;" "$C" && grep -qF "fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;" "$C" && grep -qF "fastcgi_param HTTPS \$https if_not_empty;" "$C" && grep -qF "location / { try_files \$uri \$uri/ /index.php?\$query_string; }" "$C"'
check "configuración: nunca los ficheros ocultos (.env, .git) ni vendor y node_modules" 'grep -qF "location ~ /\.(?!well-known/) { deny all; }" "$C" && grep -qF "location ~ ^/(vendor|node_modules)/ { deny all; }" "$C"'
check "configuración: solo tuya" '[ "$(stat -c %a "$C" 2> /dev/null || stat -f %Lp "$C")" == 600 ]'
cp "$C" "$W/antes.conf"
printf 'ROMPER|\n' >> "$NGINX_LIST"
mkdir -p "$HTDOCS_DIR/ROMPER"
o=$(nginx_write_conf); check "si Nginx no acepta la configuración nueva, se queda la de antes" '[[ "$o" == *"se queda la de antes"* ]] && cmp -s "$C" "$W/antes.conf" && [ ! -f "$C.nuevo" ]'
sed -i.bak '/^ROMPER|/d' "$NGINX_LIST"

# Arrancar y parar
python3 -c 'import socket, sys, time; s = socket.socket(); s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen(); time.sleep(60)' "$P1" &
BUSY=$!
sleep 0.4
o=$(nginx_start); check "arrancar: con su puerto ocupado por otro programa, lo dice y no arranca" '[[ "$o" == *"El puerto $P1 ya lo usa otro programa"* ]] && ! nginx_running'
kill $BUSY 2> /dev/null; wait $BUSY 2> /dev/null
o=$(nginx_start); check "arrancar: en marcha, y avisa si el PHP de la versión activa no lo está" 'nginx_running && [[ "$o" == *"Nginx en marcha"* ]] && [[ "$o" == *"no está en marcha"* ]]'
o=$(nginx_add "Mi Web_2" ""); check "en marcha, un cambio se recarga (sin cortar)" 'grep -q "^nginx 0 reload " "$NGINX_DIR/ordenes.log"'
mkdir -p "$(dirname "$NGINX_PHP_SOCK")" && python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$NGINX_PHP_SOCK"
check "el PHP de la versión activa: su socket" '[ "$(nginx_php_state)" == ok ]'
o=$(gui_nginx)
check "gui-nginx: cómo está, sus proyectos y los que se pueden añadir (sin enlaces)" '[[ "$o" == *"N|1|$NGINX_VERSION|$NGINX_VERSION|1|$P1|$P2|ok"* ]] && [[ "$o" == *"P|tienda-laravel|public|tienda-laravel.localhost|1"* ]] && [[ "$o" == *"C|mi web 2"* ]] && [[ "$o" != *"C|enlace"* ]] && [[ "$o" != *"C|tienda-laravel"* ]]'
o=$(nginx_remove antiguo); check "quitar: deja de servirlo, sin su certificado (su carpeta sigue)" '! grep -q "^antiguo|" "$NGINX_LIST" && [ ! -f "$NGINX_DIR/certs/antiguo.localhost.crt" ] && [ -d "$HTDOCS_DIR/antiguo" ] && ! grep -qF "server_name antiguo.localhost;" "$C"'
o=$(nginx_stop); check "parar" '! nginx_running && [[ "$o" == *"Nginx parado"* ]]'
DRY=1; o=$(nginx_add "mi web 2"; nginx_ports 9100 9101; nginx_start); DRY=0
check "en simulación no cambia nada" '[[ "$o" == *"[simulacion]"* ]] && [ "$(nginx_get HTTP)" == "$P1" ] && ! nginx_running'
check "Componentes: avisa de otra versión de Nginx y la compila al actualizar" 'grep -qF "    if nginx_installed && [ \"\$(nginx_installed_version)\" != \"\$NGINX_VERSION\" ]; then" "$SRC" && grep -qF "echo \"X|Nginx|\$(nginx_installed_version)|\$NGINX_VERSION\"" "$SRC" && grep -qF "[[ \" \$progs \" == *\" Nginx \"* ]] && { task_step; nginx_build_deps && nginx_build || fail=1; }" "$SRC"'
if [ $MAC -eq 1 ]; then
    check "Mac: la pestaña Nginx y su apartado de Configuración" 'grep -qF "        case \"nginx\": NginxView()" "$SRC" && grep -qF "        if key == \"nginx\" { reloadNginx() }" "$SRC" && grep -qF "(\"nginx\", \"Nginx\", \"logo:nginx\")" "$SRC" && grep -qF "            NginxCard()" "$SRC" && grep -qF "runQuick([\"gui-nginx\"])" "$SRC"'
else
    check "Linux: la pestaña Nginx y su apartado de Configuración" 'grep -qF "(\"nginx\", self.page_nginx)" "$SRC" && grep -qF "        elif row.tab_name == \"nginx\":" "$SRC" && grep -qF "(\"nginx\", \"Nginx\", \"logo:nginx\")" "$SRC" && grep -qF "        self.nv_nginx_tools()" "$SRC" && grep -qF "run_quick([\"gui-nginx\"], got)" "$SRC"'
fi
exit $fail
