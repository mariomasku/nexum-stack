# Nginx (pestaña Nginx, 1.57.38): un servidor web aparte de las versiones de PHP, para los proyectos de
# htdocs que se le añadan. Uno para todo el equipo, en ~/.nexum/nginx y con tu usuario (nunca root ni
# sudo, salvo para instalar en Linux lo que hace falta para compilarlo), solo en este equipo (127.0.0.1
# y ::1) y en sus puertos (8080 y 8443 de serie, en Configuración, Nginx). Cada proyecto, por su nombre:
# http://<carpeta>.localhost:8080 y https://<carpeta>.localhost:8443 (el navegador lleva cualquier
# .localhost a este equipo sin tocar /etc/hosts), con el PHP-FPM de la versión de PHP activa y sus BBDD.
# Se compila de su código, fijado por su huella (la del .tar.gz de nginx.org, firmado por quien publica
# Nginx: se comprobó al fijarla). Para otra versión: su .tar.gz.asc de nginx.org/en/download.html
NGINX_VERSION=1.30.7
NGINX_SHA256=2565b5c837050e958f70fb0f73c48e2bca4542ad349fd356f46fb0c72610bc6e
NGINX_DIR=$LOG_DIR/nginx
NGINX_PREFIX=$NGINX_DIR/programa
NGINX_BIN=$NGINX_PREFIX/sbin/nginx
NGINX_SETTINGS=$NGINX_DIR/ajustes
NGINX_LIST=$NGINX_DIR/proyectos
NGINX_CONF=$NGINX_DIR/conf/nginx.conf
NGINX_RUN=$NGINX_DIR/run
NGINX_ERROR_LOG=$NGINX_DIR/logs/error.log
NGINX_HTTP_DEFAULT=8080
NGINX_HTTPS_DEFAULT=8443

# nginx_get HTTP|HTTPS: el puerto de Configuración, o el de serie si no hay o no vale
function nginx_get() {
    local v="" def=$NGINX_HTTP_DEFAULT
    [ "$1" == HTTPS ] && def=$NGINX_HTTPS_DEFAULT
    [ -f "$NGINX_SETTINGS" ] && v=$(sed -n "s/^$1=//p" "$NGINX_SETTINGS" | tail -1)
    if [[ "$v" =~ ^[1-9][0-9]{3,4}$ ]] && [ "$v" -le 65535 ]; then
        echo "$v"
    else
        echo "$def"
    fi
}

function nginx_installed() {
    [ -x "$NGINX_BIN" ] && [ ! -L "$NGINX_BIN" ]
}

function nginx_installed_version() {
    cat "$NGINX_PREFIX/version" 2> /dev/null
}

# El nombre de un proyecto en Nginx: <carpeta>.localhost, en minúsculas y con guiones en lugar de lo que
# no va en un nombre (Mi Tienda_2 -> mi-tienda-2.localhost). Nada si no queda ninguna letra o número
function nginx_host() {
    local h
    h=$(printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9-]\{1,\}/-/g; s/^-*//; s/-*$//' | cut -c1-63 | sed 's/-*$//')
    [ -n "$h" ] && echo "$h.localhost"
}

# Los proyectos añadidos: carpeta|raíz, uno por línea (raíz: la subcarpeta que se sirve, como public, o
# vacía para la carpeta entera). Solo los que siguen siendo una carpeta de proyecto válida
function nginx_projects() {
    local folder root
    [ -f "$NGINX_LIST" ] || return 0
    while IFS='|' read -r folder root; do
        [[ "$folder" =~ ^[A-Za-z0-9_][A-Za-z0-9\ ._-]*$ ]] || continue
        [[ "$root" =~ ^([A-Za-z0-9_][A-Za-z0-9._-]*(/[A-Za-z0-9_][A-Za-z0-9._-]*)*)?$ ]] || continue
        [[ "/$root/" == */../* ]] && continue
        echo "$folder|$root"
    done < "$NGINX_LIST"
}

# La raíz que se sirve de un proyecto, si no se dice: public (Laravel, Symfony), web (Symfony antiguo) o
# la carpeta entera
function nginx_root_guess() {
    local d=$HTDOCS_DIR/$1
    if [ -f "$d/public/index.php" ] || [ -f "$d/public/index.html" ]; then
        echo public
    elif [ -f "$d/web/app.php" ] || [ -f "$d/web/index.php" ]; then
        echo web
    fi
}

function nginx_running() {
    local pid
    pid=$(cat "$NGINX_RUN/nginx.pid" 2> /dev/null)
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2> /dev/null && ps -p "$pid" -o comm= 2> /dev/null | grep -q nginx
}

# Cómo está el PHP de la versión activa para Nginx: ok (su PHP-FPM responde), parado (no está en marcha)
# o sin-fpm (la versión activa no tiene PHP-FPM, como un XAMPP oficial)
function nginx_php_state() {
    if [ -S "$NGINX_PHP_SOCK" ]; then
        echo ok
    elif [ -n "$(active_dir)" ] && ! is_fpm_install "$(active_dir)"; then
        echo sin-fpm
    else
        echo parado
    fi
}

# ¿Está libre <puerto> en este equipo? (lo que ya escucha ahí no deja arrancar a Nginx)
function nginx_port_free() {
    python3 -I -c '
import socket, sys
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(("127.0.0.1", int(sys.argv[1])))
except OSError:
    sys.exit(1)' "$1"
}

# Descarga (comprobada por su huella) y compila Nginx en ~/.nexum/nginx/programa, con tu usuario. Si ya
# estaba en marcha, sigue con el nuevo. Sin su lista de pasos (nginx_install o Componentes la ponen)
function nginx_build() {
    local tmp url=https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz sha=$NGINX_SHA256 got jobs was=0 tls=(--proto =https --tlsv1.2)
    [ "$EUID" -eq 0 ] && { echo "Nginx se instala con tu usuario, no como root"; return 1; }
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] descarga de Nginx $NGINX_VERSION (comprobada por su huella) y compilación en $NGINX_PREFIX"
        return 0
    fi
    # (en las pruebas, de una carpeta local)
    [ -n "$TEST_DIR" ] && [ -n "$LVM_NGINX_URL" ] && { url=$LVM_NGINX_URL sha=$LVM_NGINX_SHA tls=(); }
    for got in "$NGINX_DIR" "$NGINX_PREFIX"; do
        [ -L "$got" ] && { echo "$got es un enlace: no se toca"; return 1; }
    done
    mkdir -p -m 700 "$NGINX_DIR" || return 1
    tmp=$(mktemp -d "$NGINX_DIR/compilar.XXXXXX") || return 1
    echo "Descargando Nginx $NGINX_VERSION de nginx.org..."
    if ! curl -q -fsSL "${tls[@]}" --retry 2 --max-time 300 -o "$tmp/nginx.tar.gz" "$url"; then
        rm -rf "$tmp"
        echo "No se ha podido descargar Nginx $NGINX_VERSION"
        return 1
    fi
    if command -v sha256sum > /dev/null; then
        got=$(sha256sum "$tmp/nginx.tar.gz" | cut -d' ' -f1)
    else
        got=$(shasum -a 256 "$tmp/nginx.tar.gz" | cut -d' ' -f1)
    fi
    if [ "$got" != "$sha" ]; then
        rm -rf "$tmp"
        echo "La descarga de Nginx no es la que se espera (su huella no coincide): no se instala"
        return 1
    fi
    echo "  Huella de Nginx $NGINX_VERSION: buena"
    tar -xzf "$tmp/nginx.tar.gz" -C "$tmp" || { rm -rf "$tmp"; echo "No se ha podido abrir el código de Nginx"; return 1; }
    jobs=$(getconf _NPROCESSORS_ONLN 2> /dev/null || echo 2)
    echo "Compilando Nginx $NGINX_VERSION (menos de un minuto)..."
    # (lo que se usa con PHP: https, http/2, gzip; sin los módulos de correo ni otros protocolos de aplicaciones)
    NGINX_BUILD_FLAGS=()
    nginx_build_flags || { rm -rf "$tmp"; return 1; }
    if ! ( cd "$tmp/nginx-$NGINX_VERSION" \
            && ./configure --prefix="$NGINX_PREFIX" --with-http_ssl_module --with-http_v2_module \
                --with-http_realip_module --with-http_gzip_static_module --with-pcre-jit \
                --without-http_uwsgi_module --without-http_scgi_module --without-mail_pop3_module \
                "${NGINX_BUILD_FLAGS[@]}" > "$tmp/configure.log" 2>&1 \
            && make -j"$jobs" > "$tmp/make.log" 2>&1 \
            && make install DESTDIR="$tmp/stage" > "$tmp/install.log" 2>&1 ); then
        echo "No se ha podido compilar Nginx. Lo último que ha dicho:"
        tail -15 "$(ls -t "$tmp"/*.log | head -1)" | sed 's/^/  /'
        rm -rf "$tmp"
        return 1
    fi
    echo "$NGINX_VERSION" > "$tmp/stage$NGINX_PREFIX/version"
    nginx_running && was=1
    rm -rf "$NGINX_PREFIX.anterior"
    [ -d "$NGINX_PREFIX" ] && mv "$NGINX_PREFIX" "$NGINX_PREFIX.anterior"
    if ! mv "$tmp/stage$NGINX_PREFIX" "$NGINX_PREFIX"; then
        [ -d "$NGINX_PREFIX.anterior" ] && mv "$NGINX_PREFIX.anterior" "$NGINX_PREFIX"
        rm -rf "$tmp"
        echo "No se ha podido poner Nginx en $NGINX_PREFIX"
        return 1
    fi
    rm -rf "$tmp" "$NGINX_PREFIX.anterior"
    echo "Nginx $NGINX_VERSION instalado en $NGINX_PREFIX"
    # (el que estaba en marcha, con el programa nuevo)
    if [ $was -eq 1 ]; then
        nginx_stop > /dev/null
        nginx_start
    fi
}

# nginx-instalar: lo que hace falta para compilarlo y Nginx
function nginx_install() {
    task_plan "Instalando Nginx $NGINX_VERSION" "Lo que hace falta para compilarlo" "Nginx $NGINX_VERSION"
    task_step
    nginx_build_deps || return 1
    task_step
    nginx_build
}

# Certificado propio de <nombre>.localhost (no es de una CA: solo vale para ese nombre), en una carpeta
# solo tuya. Se rehace si falta o no es de ese nombre
function nginx_cert() {
    local host=$1 c=$NGINX_DIR/certs
    if [ -s "$c/$host.crt" ] && [ -s "$c/$host.key" ] \
            && openssl x509 -in "$c/$host.crt" -noout -text 2> /dev/null | grep -qF "DNS:$host"; then
        return 0
    fi
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] certificado propio de $host en $c"; return 0; }
    mkdir -p -m 700 "$NGINX_DIR" "$c" || return 1
    # (las extensiones en un fichero propio y no con -addext: ver make_selfsigned)
    if ! ( umask 077
            printf '[req]\ndistinguished_name = dn\nx509_extensions = ext\nprompt = no\n[dn]\nCN = %s\n[ext]\nbasicConstraints = critical,CA:FALSE\nextendedKeyUsage = serverAuth\nsubjectAltName = DNS:%s\n' "$host" "$host" > "$c/$host.cnf" \
            && openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -config "$c/$host.cnf" \
            -keyout "$c/$host.key" -out "$c/$host.crt" > /dev/null 2>&1 ); then
        rm -f "$c/$host.key" "$c/$host.crt" "$c/$host.cnf"
        echo "No se ha podido crear el certificado de $host"
        return 1
    fi
    rm -f "$c/$host.cnf"
}

# La configuración entera de Nginx (conf/nginx.conf), de los ajustes y los proyectos. Se prueba antes de
# cambiarla: si Nginx no la acepta, se queda la de antes
function nginx_write_conf() {
    local http https folder root host dir ip new
    http=$(nginx_get HTTP) https=$(nginx_get HTTPS)
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] configuración de Nginx en $NGINX_CONF"; return 0; }
    mkdir -p -m 700 "$NGINX_DIR" "$NGINX_DIR/conf" "$NGINX_RUN" "$NGINX_RUN/tmp" "$NGINX_DIR/logs" || return 1
    new=$NGINX_CONF.nuevo
    {
        cat << EOF
# Configuración de Nginx de Nexum Dev Stack: la escribe el gestor (pestaña Nginx), no se edita a mano
worker_processes 1;
pid "$NGINX_RUN/nginx.pid";
error_log "$NGINX_ERROR_LOG" warn;
events { worker_connections 256; }
http {
    include "$NGINX_PREFIX/conf/mime.types";
    default_type application/octet-stream;
    access_log off;
    sendfile on;
    server_tokens off;
    client_max_body_size 256m;
    client_body_temp_path "$NGINX_RUN/tmp/body";
    proxy_temp_path "$NGINX_RUN/tmp/proxy";
    fastcgi_temp_path "$NGINX_RUN/tmp/fastcgi";
    # Lo que no es el nombre de un proyecto (otro nombre, la IP o un dominio real), sin respuesta
    server {
        listen 127.0.0.1:$http default_server;
        listen [::1]:$http default_server;
        listen 127.0.0.1:$https ssl default_server;
        listen [::1]:$https ssl default_server;
        ssl_reject_handshake on;
        return 444;
    }
EOF
        while IFS='|' read -r folder root; do
            host=$(nginx_host "$folder") || continue
            [ -d "$HTDOCS_DIR/$folder" ] || continue
            dir=$HTDOCS_DIR/$folder${root:+/$root}
            cat << EOF
    # $folder
    server {
EOF
            for ip in 127.0.0.1 "[::1]"; do
                printf '        listen %s:%s;\n        listen %s:%s ssl;\n' "$ip" "$http" "$ip" "$https"
            done
            cat << EOF
        http2 on;
        server_name $host;
        ssl_certificate "$NGINX_DIR/certs/$host.crt";
        ssl_certificate_key "$NGINX_DIR/certs/$host.key";
        root "$dir";
        index index.php index.html;
        # Ficheros ocultos (.env, .git...) y dependencias, nunca
        location ~ /\.(?!well-known/) { deny all; }
        location ~ ^/(vendor|node_modules)/ { deny all; }
        location / { try_files \$uri \$uri/ /index.php?\$query_string; }
        location ~ [^/]\.php(/|\$) {
            fastcgi_split_path_info ^(.+?\.php)(/.*)\$;
            try_files \$fastcgi_script_name =404;
            include "$NGINX_PREFIX/conf/fastcgi_params";
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            fastcgi_param PATH_INFO \$fastcgi_path_info;
            fastcgi_param HTTPS \$https if_not_empty;
            fastcgi_read_timeout 300;
            fastcgi_pass unix:$NGINX_PHP_SOCK;
        }
    }
EOF
        done < <(nginx_projects)
        echo "}"
    } > "$new" || return 1
    chmod 600 "$new"
    if nginx_installed && ! "$NGINX_BIN" -t -q -p "$NGINX_RUN" -c "$new" -e "$NGINX_ERROR_LOG" 2> "$NGINX_RUN/prueba.log"; then
        echo "Nginx no acepta la configuración nueva: se queda la de antes. Lo que dice:"
        sed 's/^/  /' "$NGINX_RUN/prueba.log" | tail -5
        rm -f "$new"
        return 1
    fi
    mv -f "$new" "$NGINX_CONF"
}

# La configuración de ahora, y si está en marcha, que la use (sin cortar lo que esté sirviendo)
function nginx_apply() {
    nginx_write_conf || return 1
    if [ "$DRY" -eq 0 ] && nginx_running; then
        "$NGINX_BIN" -p "$NGINX_RUN" -c "$NGINX_CONF" -e "$NGINX_ERROR_LOG" -s reload || return 1
    fi
    return 0
}

function nginx_start() {
    local http https p i
    [ "$EUID" -eq 0 ] && { echo "Nginx corre con tu usuario, no como root"; return 1; }
    nginx_installed || { echo "Nginx no está instalado: instálalo en la pestaña Nginx (nginx-instalar)"; return 1; }
    if nginx_running; then
        nginx_apply || return 1
        echo "Nginx ya estaba en marcha: con la configuración de ahora"
        return 0
    fi
    http=$(nginx_get HTTP) https=$(nginx_get HTTPS)
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] Nginx en marcha en 127.0.0.1:$http y :$https"
        return 0
    fi
    for p in "$http" "$https"; do
        nginx_port_free "$p" || { echo "El puerto $p ya lo usa otro programa: cámbialo en Configuración, Nginx"; return 1; }
    done
    nginx_write_conf || return 1
    if ! "$NGINX_BIN" -p "$NGINX_RUN" -c "$NGINX_CONF" -e "$NGINX_ERROR_LOG"; then
        echo "Nginx no ha arrancado. Lo último de su registro:"
        tail -5 "$NGINX_ERROR_LOG" 2> /dev/null | sed 's/^/  /'
        return 1
    fi
    for i in $(seq 30); do
        nginx_running && break
        sleep 0.1
    done
    nginx_running || { echo "Nginx no ha arrancado (mira su registro)"; return 1; }
    echo "Nginx en marcha en este equipo: puertos $http (http) y $https (https)"
    [ "$(nginx_php_state)" == ok ] || echo "Aviso: el PHP de la versión activa no está en marcha: arráncala para que sirva PHP"
}

function nginx_stop() {
    local i
    if ! nginx_running; then
        echo "Nginx no estaba en marcha"
        return 0
    fi
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] se para Nginx"; return 0; }
    "$NGINX_BIN" -p "$NGINX_RUN" -c "$NGINX_CONF" -e "$NGINX_ERROR_LOG" -s quit 2> /dev/null
    for i in $(seq 50); do
        nginx_running || break
        sleep 0.1
    done
    nginx_running && kill -TERM "$(cat "$NGINX_RUN/nginx.pid")" 2> /dev/null
    echo "Nginx parado"
}

# nginx-anadir <carpeta> [raíz]: el proyecto, servido por <carpeta>.localhost (raíz: la subcarpeta que se
# sirve; sin ella, la que parezca: public, web o la carpeta entera)
function nginx_add() {
    local folder=${1%/} root=${2-__adivinar__} host f r
    valid_project "$folder" || return 1
    [ "$root" == __adivinar__ ] && root=$(nginx_root_guess "$folder")
    root=${root%/}
    [ "$root" == . ] && root=""
    if [ -n "$root" ] && { ! [[ "$root" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*(/[A-Za-z0-9_][A-Za-z0-9._-]*)*$ ]] || [[ "/$root/" == */../* ]]; }; then
        echo "Subcarpeta no válida: $root"
        return 1
    fi
    [ -z "$root" ] || [ -d "$HTDOCS_DIR/$folder/$root" ] || { echo "No existe $HTDOCS_DIR/$folder/$root"; return 1; }
    host=$(nginx_host "$folder") || { echo "Con el nombre de $folder no se puede hacer un nombre para Nginx"; return 1; }
    while IFS='|' read -r f r; do
        [ "$f" == "$folder" ] && continue
        [ "$(nginx_host "$f")" == "$host" ] && { echo "$f ya usa $host: cambia el nombre de una de las dos carpetas"; return 1; }
    done < <(nginx_projects)
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $folder en Nginx: http://$host:$(nginx_get HTTP) (${root:-la carpeta entera})"
        return 0
    fi
    mkdir -p -m 700 "$NGINX_DIR" || return 1
    { nginx_projects | grep -v "^$(printf '%s' "$folder" | sed 's/[.[\*^$]/\\&/g')|"; echo "$folder|$root"; } > "$NGINX_LIST.nuevo" \
        && chmod 600 "$NGINX_LIST.nuevo" && mv -f "$NGINX_LIST.nuevo" "$NGINX_LIST" || return 1
    nginx_cert "$host" || return 1
    nginx_trust "$host"
    nginx_apply || return 1
    echo "$folder en Nginx: http://$host:$(nginx_get HTTP) y https://$host:$(nginx_get HTTPS)${root:+ (sirve $root/)}"
}

# nginx-quitar <carpeta>: deja de servirlo (su carpeta no se toca)
function nginx_remove() {
    local folder=${1%/} host
    [[ "$folder" =~ ^[A-Za-z0-9_][A-Za-z0-9\ ._-]*$ ]] || { echo "Carpeta no válida: $folder"; return 1; }
    nginx_projects | grep -q "^$(printf '%s' "$folder" | sed 's/[.[\*^$]/\\&/g')|" || { echo "$folder no está en Nginx"; return 0; }
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] $folder deja de estar en Nginx"; return 0; }
    host=$(nginx_host "$folder")
    nginx_projects | grep -v "^$(printf '%s' "$folder" | sed 's/[.[\*^$]/\\&/g')|" > "$NGINX_LIST.nuevo"
    chmod 600 "$NGINX_LIST.nuevo" && mv -f "$NGINX_LIST.nuevo" "$NGINX_LIST" || return 1
    [ -n "$host" ] && rm -f "$NGINX_DIR/certs/$host.crt" "$NGINX_DIR/certs/$host.key"
    nginx_apply || return 1
    echo "$folder ya no está en Nginx (su carpeta sigue igual)"
}

# nginx-puertos <http> <https>: los de Nginx (de 1024 en adelante: los de abajo son de root)
function nginx_ports() {
    local http=$1 https=$2 p
    for p in "$http" "$https"; do
        if ! [[ "$p" =~ ^[1-9][0-9]{3,4}$ ]] || [ "$p" -gt 65535 ]; then
            echo "Puerto no válido: $p (de 1024 a 65535)"
            return 1
        fi
    done
    [ "$http" == "$https" ] && { echo "http y https no pueden ir en el mismo puerto"; return 1; }
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] Nginx en los puertos $http y $https"; return 0; }
    if nginx_running; then
        for p in "$http" "$https"; do
            [ "$p" == "$(nginx_get HTTP)" ] || [ "$p" == "$(nginx_get HTTPS)" ] && continue
            nginx_port_free "$p" || { echo "El puerto $p ya lo usa otro programa"; return 1; }
        done
    fi
    mkdir -p -m 700 "$NGINX_DIR" || return 1
    ( umask 077; printf 'HTTP=%s\nHTTPS=%s\n' "$http" "$https" > "$NGINX_SETTINGS.nuevo" ) && mv -f "$NGINX_SETTINGS.nuevo" "$NGINX_SETTINGS" || return 1
    nginx_apply || return 1
    echo "Nginx en los puertos $http (http) y $https (https)"
}

# nginx-registro: lo último que ha dicho Nginx (sus errores)
function nginx_log() {
    if [ -s "$NGINX_ERROR_LOG" ]; then
        tail -200 "$NGINX_ERROR_LOG"
    else
        echo "Nginx no ha escrito nada en su registro ($NGINX_ERROR_LOG)"
    fi
}

# nginx-confiar: que el navegador acepte sin aviso el certificado de cada proyecto
function nginx_trust_all() {
    local folder root host n=0
    while IFS='|' read -r folder root; do
        host=$(nginx_host "$folder") || continue
        nginx_cert "$host" && nginx_trust "$host" && n=$((n + 1))
    done < <(nginx_projects)
    [ $n -eq 0 ] && echo "No hay proyectos en Nginx"
    return 0
}

# Para la ventana (gui-nginx):
#   N|instalado 1/0|versión instalada|la de este gestor|en marcha 1/0|http|https|PHP (ok, parado, sin-fpm)
#   P|carpeta|raíz|nombre|carpeta existe 1/0
#   C|carpeta          una de htdocs que aún no está en Nginx (para añadirla)
function gui_nginx() {
    local folder root d added=""
    printf 'N|%s|%s|%s|%s|%s|%s|%s\n' "$(nginx_installed && echo 1 || echo 0)" "$(nginx_installed_version)" "$NGINX_VERSION" \
        "$(nginx_running && echo 1 || echo 0)" "$(nginx_get HTTP)" "$(nginx_get HTTPS)" "$(nginx_php_state)"
    while IFS='|' read -r folder root; do
        printf 'P|%s|%s|%s|%s\n' "$folder" "$root" "$(nginx_host "$folder")" "$([ -d "$HTDOCS_DIR/$folder" ] && echo 1 || echo 0)"
        added+="|$folder|"
    done < <(nginx_projects)
    for d in "$HTDOCS_DIR"/*/; do
        d=${d%/}
        folder=${d##*/}
        [ -L "$d" ] && continue
        [[ "$folder" =~ ^[A-Za-z0-9_][A-Za-z0-9\ ._-]*$ ]] || continue
        [[ "$added" == *"|$folder|"* ]] && continue
        echo "C|$folder"
    done
    return 0
}

# nginx <orden> ...: las de la pestaña Nginx
function nginx_command() {
    case "$1" in
        nginx-instalar) nginx_install ;;
        nginx-arrancar) nginx_start ;;
        nginx-parar) nginx_stop ;;
        nginx-reiniciar) nginx_stop > /dev/null; nginx_start ;;
        nginx-anadir) shift; nginx_add "$@" ;;
        nginx-quitar) nginx_remove "$2" ;;
        nginx-puertos) nginx_ports "$2" "$3" ;;
        nginx-registro) nginx_log ;;
        nginx-confiar) nginx_trust_all ;;
        *) echo "Uso: nexum nginx-instalar|nginx-arrancar|nginx-parar|nginx-reiniciar|nginx-anadir <carpeta> [subcarpeta]|nginx-quitar <carpeta>|nginx-puertos <http> <https>|nginx-registro|nginx-confiar"; return 1 ;;
    esac
}
