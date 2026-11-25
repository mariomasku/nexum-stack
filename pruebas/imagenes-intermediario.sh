#!/bin/bash
# Intermediario de imagenes (1.57.17): las reglas de los vhosts (nexum-imagenes) para las tiendas y los
# WordPress con imagenes de produccion, y MEDIA_LOCAL_PY, que trae lo que falta de la web real (por la
# direccion del DNS cifrado, con --resolve), lo sirve y lo guarda sin salirse de img o de uploads.
# Sin red: curl de mentira. Uso: imagenes-intermediario.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d)
PX=""
trap '[ -n "$PX" ] && kill $PX 2> /dev/null; rm -rf "$W"' EXIT
LOG_DIR=$W/logs HTDOCS_DIR=$W/htdocs DRY=0 APP_NAME="Nexum Dev Stack" APP_VERSION=prueba
export LVM_MEDIA_LOCAL_PORT=$((20000 + RANDOM % 20000))
eval "$(sed -n '/^PS_IMAGES_DOH=/p' "$SRC")"
eval "$(awk '/^MEDIA_LOCAL_PORT=/ {p = 1} p {print} p && /^PYEOF$/ {getline; print; exit}' "$SRC")"
[ -n "$MEDIA_LOCAL_PY" ] || { echo "no esta MEDIA_LOCAL_PY"; exit 1; }
MEDIA_PROJECTS_FILE=$W/logs/media-produccion
extract "$SRC" media_local_wanted media_local_run_sync media_local_vhosts || exit 1
mkdir -p "$W/logs" "$W/bin" "$W/htdocs/tienda/img/p" "$W/htdocs/tienda/classes" "$W/htdocs/blog/wp-content/uploads" "$W/htdocs/otra"
chmod 700 "$W/logs"
touch "$W/htdocs/tienda/classes/PrestaShopAutoload.php" "$W/htdocs/blog/wp-config.php"
ln -s blog "$W/htdocs/web.local"
printf 'tienda|tienda.es\nblog|blog.es\n' > "$MEDIA_PROJECTS_FILE"
ACTIVE_VHOSTS=$W/vhosts.conf
cat > "$ACTIVE_VHOSTS" << EOF
<VirtualHost *:443>
    DocumentRoot "$W/htdocs/tienda"
    ServerName tienda.es
</VirtualHost>
<VirtualHost *:80>
    DocumentRoot "$W/htdocs/web.local"
    ServerName web.local
    # nexum-media blog.es: lo de antes
    RewriteRule ^/x$ https://blog.es/x [R=302,L]
    # /nexum-media
</VirtualHost>
<VirtualHost *:80>
    DocumentRoot "$W/htdocs/otra"
    ServerName otra.local
</VirtualHost>
EOF
cp "$ACTIVE_VHOSTS" "$W/vhosts.antes"
applied=0
edit_vhosts() { [ "$1" == --aplicar ] && cp "$2" "$ACTIVE_VHOSTS" && applied=$((applied + 1)); }
synced=0
media_local_run_sync() { synced=$((synced + 1)); }

# --- Las reglas de los vhosts
media_local_vhosts
v=$(cat "$ACTIVE_VHOSTS")
check "vhosts: la tienda, sus /img/ al intermediario (en el vhost, antes que nada)" 'grep -A1 "^<VirtualHost \*:443>" <<< "$v" | grep -q "# nexum-imagenes tienda tienda.es:" && grep -qF "RewriteRule ^/(img/.+\.(jpe?g|png|gif|webp|avif|svg|ico|bmp))\$ http://127.0.0.1:$LVM_MEDIA_LOCAL_PORT/tienda/\$1 [NC,P,L]" <<< "$v"'
check "vhosts: web.local, del WordPress cargado (su enlace), las de /wp-content/uploads/" 'grep -qF "RewriteRule ^/(wp-content/uploads/.+\.(jpe?g|png|gif|webp|avif|svg|ico|bmp))\$ http://127.0.0.1:$LVM_MEDIA_LOCAL_PORT/blog/\$1 [NC,P,L]" <<< "$v"'
check "vhosts: solo GET y HEAD, lo que no esta, y con la cabecera para el intermediario" '[ "$(grep -cF "RewriteCond %{REQUEST_METHOD} ^(GET|HEAD)\$" <<< "$v")" -eq 2 ] && [ "$(grep -cF "RewriteCond %{DOCUMENT_ROOT}%{REQUEST_URI} !-f" <<< "$v")" -eq 2 ] && grep -qF "RequestHeader set X-Nexum-Imagenes 1 \"expr=%{REQUEST_URI} =~ m#^/img/#\"" <<< "$v"'
check "vhosts: el bloque del intermediario va antes que la redireccion de media-produccion" 'awk "/nexum-imagenes blog/ { a = NR } /nexum-media blog.es/ { b = NR } END { exit !(a && b && a < b) }" <<< "$v"'
check "vhosts: sin imagenes de produccion (otra), nada" '! grep -q "nexum-imagenes otra" <<< "$v" && [ "$(grep -c "# nexum-imagenes " <<< "$v")" -eq 2 ]'
check "vhosts: se aplican con edit_vhosts --aplicar y se pone al dia el intermediario" '[ $applied -eq 1 ] && [ $synced -eq 1 ]'
media_local_vhosts
check "vhosts: otra vez, igual (no se vuelven a aplicar, pero el intermediario si)" '[ $applied -eq 1 ] && [ $synced -eq 2 ] && [ "$(cat "$ACTIVE_VHOSTS")" == "$v" ]'
printf 'blog|blog.es\n' > "$MEDIA_PROJECTS_FILE"
media_local_vhosts
check "vhosts: sin la tienda, se quita su bloque (el resto, como estaba)" '! grep -q "nexum-imagenes tienda" "$ACTIVE_VHOSTS" && grep -q "nexum-imagenes blog" "$ACTIVE_VHOSTS"'
: > "$MEDIA_PROJECTS_FILE"
media_local_vhosts
check "vhosts: sin ninguno, quedan como estaban al principio" 'cmp -s "$ACTIVE_VHOSTS" "$W/vhosts.antes"'
check "intermediario: solo con algun proyecto con imagenes de produccion" '! media_local_wanted && echo "blog|blog.es" > "$MEDIA_PROJECTS_FILE" && media_local_wanted'

# --- El intermediario, con un curl de mentira: el DNS cifrado da 1.2.3.4 (y una privada, que no vale);
# la web real tiene img/p/1/1.jpg y wp-content/uploads/2026/01/foto con espacio.jpg; lo demas, 404, y
# img/p/2/2.jpg lleva a una pagina de error (200, pero HTML)
cat > "$W/bin/curl" << 'EOF'
#!/bin/bash
echo "$*" >> "$CURL_LOG"
for a in "$@"; do last=$a; done
case "$last" in
    *dns-query*type=AAAA*) echo '{"Answer":[]}'; exit 0 ;;
    *dns-query*) echo '{"Answer":[{"type":1,"data":"10.0.0.9"},{"type":1,"data":"1.2.3.4"}]}'; exit 0 ;;
esac
while [ $# -gt 0 ]; do [ "$1" == -o ] && out=$2; shift; done
case "$last" in
    https://tienda.es/img/p/1/1.jpg|"https://blog.es/wp-content/uploads/2026/01/foto%20con%20espacio.jpg")
        printf 'JPEGDATA' > "$out"; printf '200 image/jpeg' ;;
    https://tienda.es/img/p/2/2.jpg) printf '<html>error</html>' > "$out"; printf '200 text/html' ;;
    *) printf '404 text/html'; exit 22 ;;
esac
EOF
chmod +x "$W/bin/curl"
printf 'tienda|tienda.es\nblog|blog.es\n' > "$MEDIA_PROJECTS_FILE"
P=$LVM_MEDIA_LOCAL_PORT
CURL_LOG=$W/curl.log PATH=$W/bin:$PATH python3 -I -c "$MEDIA_LOCAL_PY" nexum-imagenes "$P" "$MEDIA_PROJECTS_FILE" \
    "$W/htdocs" "$PS_IMAGES_DOH" "Nexum Dev Stack/prueba" "$W/logs/pid" >> "$W/logs/proxy.log" 2>&1 &
for i in $(seq 50); do [ -s "$W/logs/pid" ] && break; sleep 0.1; done
PX=$(cat "$W/logs/pid" 2> /dev/null)
g() { curl -s -o "$W/out" -w "%{http_code}" -H "X-Nexum-Imagenes: 1" "${@:2}" "http://127.0.0.1:$P/$1"; }
check "intermediario: en marcha, solo en 127.0.0.1" '[ -n "$PX" ] && [ "$(g __nexum/ok)" == 200 ]'
check "intermediario: sin la cabecera de Apache, o con otro nombre, no atiende" '[ "$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$P/tienda/img/p/1/1.jpg")" == 403 ] && [ "$(g tienda/img/p/1/1.jpg -H "Host: otro.es:$P")" == 403 ]'
check "tienda: la trae, la sirve como imagen y la guarda en img" '[ "$(g tienda/img/p/1/1.jpg)" == 200 ] && [ "$(cat "$W/out")" == JPEGDATA ] && [ "$(cat "$W/htdocs/tienda/img/p/1/1.jpg")" == JPEGDATA ]'
check "tienda: a la direccion del DNS cifrado (la publica), con --resolve y comprobando https" 'grep -F "https://tienda.es/img/p/1/1.jpg" "$W/curl.log" | grep -qF -- "--resolve tienda.es:443:1.2.3.4 " && grep -F "https://tienda.es/img/p/1/1.jpg" "$W/curl.log" | grep -qF -- "--proto =https"'
check "wordpress: una de uploads con espacio, igual (y se guarda con su nombre)" '[ "$(g "blog/wp-content/uploads/2026/01/foto%20con%20espacio.jpg")" == 200 ] && [ -f "$W/htdocs/blog/wp-content/uploads/2026/01/foto con espacio.jpg" ]'
check "lo que da una pagina de error (200, pero HTML), 404 y no se guarda" '[ "$(g tienda/img/p/2/2.jpg)" == 404 ] && [ ! -e "$W/htdocs/tienda/img/p/2/2.jpg" ]'
n=$(grep -c "img/p/3/3.jpg" "$W/curl.log")
check "lo que no esta en produccion, 404, y no se vuelve a preguntar enseguida" '[ "$(g tienda/img/p/3/3.jpg)" == 404 ] && [ "$(g tienda/img/p/3/3.jpg)" == 404 ] && [ "$(grep -c "img/p/3/3.jpg" "$W/curl.log")" -eq $((n + 1)) ]'
check "ni fuera de img o uploads, ni lo que no es una imagen, ni de un proyecto sin imagenes de produccion" '[ "$(g tienda/img/../../x.jpg)" == 404 ] && [ "$(g tienda/img/p/1/x.php)" == 404 ] && [ "$(g tienda/config/x.jpg)" == 404 ] && [ "$(g otra/img/x.jpg)" == 404 ]'
mkdir -p "$W/fuera" && ln -s "$W/fuera" "$W/htdocs/tienda/img/enlace"
check "un enlace dentro de img que lleva fuera: no se guarda alli" '[ "$(g tienda/img/enlace/1.jpg)" != 500 ] && [ -z "$(ls "$W/fuera")" ]'
check "sin ficheros a medias en las carpetas" '[ -z "$(find "$W/htdocs" -name ".nexum-*")" ]'
exit $fail
