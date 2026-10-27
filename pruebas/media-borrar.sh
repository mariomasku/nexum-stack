#!/bin/bash
# Imagenes de produccion (media-produccion) y borrar un proyecto entero (borrar-proyecto), Linux
# 1.55.14: la regla solo en los .local y sin bucles, la de web.local con el WordPress cargado, la
# descarga de las imagenes de una tienda y el borrado por orden, sin seguir si un paso
# falla (la carpeta, lo ultimo). Uso: media-borrar.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-media-borrar.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
grep -q '^function media_proxy() {' "$SRC" || { echo "  ok    (sin media-produccion)"; exit 0; }
extract "$SRC" media_proxy delete_project valid_domain valid_project || exit 1
# (el Mac no tiene readlink -f: realpath_f)
grep -q "function realpath_f() {" "$SRC" && realpath_f() { readlink -f "$1"; }
# (y el rm de BSD tiene -x, que es --one-file-system en el de GNU de este equipo)
grep -q "rm -rfx --" "$SRC" && rm() { local a=() x; for x in "$@"; do [ "$x" == -rfx ] && x=-rf; a+=("$x"); done; command rm "${a[@]}"; }
# (nunca el sudo de verdad)
sudo() { return 1; }

LOG_DIR=$W/log DRY=0 HTDOCS_DIR=$W/htdocs HOSTS_FILE=$W/hosts DOCKER_DIR=$W/docker
MEDIA_EXT=$(grep -oP '^MEDIA_EXT="\K[^"]+' "$SRC")
PROJECT_VHOST=web.local EMPTY_PROJECT=.lvm-sin-proyecto
PROJECTS_FILE=$LOG_DIR/proyectos REPO_PROJECTS_FILE=$LOG_DIR/montados
mkdir -p "$LOG_DIR" "$HTDOCS_DIR/tienda/img" "$HTDOCS_DIR/otra" "$DOCKER_DIR"
ACTIVE_VHOSTS=$W/vhosts.conf VHOSTS_FILE=$W/vhosts.conf
cat > "$ACTIVE_VHOSTS" << 'EOF'
# Virtual Hosts
<VirtualHost *:80>
    DocumentRoot "/opt/lampp/htdocs/tienda"
    ServerName tienda.es
    ServerAlias www.tienda.es
</VirtualHost>

<VirtualHost *:80>
    DocumentRoot "/opt/lampp/htdocs/tienda"
    ServerName tienda.local
    ServerAlias www.tienda.local
</VirtualHost>

<VirtualHost *:443>
    DocumentRoot "/opt/lampp/htdocs/tienda"
    ServerName tienda.local
    SSLEngine on
</VirtualHost>

<VirtualHost *:80>
    DocumentRoot "/opt/lampp/htdocs/otra"
    ServerName otra.local
</VirtualHost>
EOF
cp "$ACTIVE_VHOSTS" "$W/original.conf"
printf '127.0.0.1 localhost\n127.0.0.1 tienda.es www.tienda.es\n#127.0.0.1 tienda.local\n127.0.0.1 otra.local tienda.local\n' > "$HOSTS_FILE"
vhosts_info() { python3 -I -c '
import re, sys
b = None
for l in open(sys.argv[1]):
    s = l.strip()
    if s.startswith("<VirtualHost"): b = {"n": "", "a": []}
    elif s.startswith("</VirtualHost>"): print("80|x|%s|%s||" % (b["n"], " ".join(b["a"])))
    elif s.startswith("ServerName"): b["n"] = s.split()[1]
    elif s.startswith("ServerAlias"): b["a"] += s.split()[1:]
' "$VHOSTS_FILE"; }
# (aplicar: se copia tal cual, como si Apache lo aceptara; FALLA_VHOSTS=1 como si no)
edit_vhosts() { [ -n "$FALLA_VHOSTS" ] && return 1; echo vhosts >> "$W/hecho.log"; cp "$2" "$ACTIVE_VHOSTS"; }
edit_hosts() { echo hosts >> "$W/hecho.log"; cp "$2" "$HOSTS_FILE"; }
sudo_first() { true; }
local_off() { echo "encendido $*" >> "$W/hecho.log"; }
project_link() { echo web.local; }
unload_project() { echo desmontar >> "$W/hecho.log"; }
docker_ready() { true; }
docker_action() { echo "docker $*" >> "$W/hecho.log"; }
db_valid_name() { [[ "$1" =~ ^[a-z_]+$ ]]; }
db_connect() { DB_FOLDER=8.4; }
db_exists() { [ "$1" == ps_tienda ]; }
drop_database() { echo "bd $*" >> "$W/hecho.log"; [ -z "$FALLA_BD" ]; }

# media-produccion
o=$(media_proxy tienda.es tienda.es)
check "media: un dominio real no se toca (la redireccion volveria aqui)" '[ $? -ne 0 ] && cmp -s "$ACTIVE_VHOSTS" "$W/original.conf"'
o=$(media_proxy tienda.local otra.local)
check "media: la produccion no puede ser un .local" '[ $? -ne 0 ] && cmp -s "$ACTIVE_VHOSTS" "$W/original.conf"'
o=$(media_proxy tienda.local "tienda.es/x\"y")
check "media: un dominio de produccion raro no se admite" '[ $? -ne 0 ] && cmp -s "$ACTIVE_VHOSTS" "$W/original.conf"'
o=$(media_proxy nada.local tienda.es)
check "media: sin vhost de ese dominio, nada" '[ $? -ne 0 ] && cmp -s "$ACTIVE_VHOSTS" "$W/original.conf"'
o=$(media_proxy WWW.Tienda.local https://www.tienda.es/)
check "media: la regla en los dos vhosts de tienda.local (y con www y https:// tambien)" \
    '[ "$(grep -c "RewriteRule .* https://www.tienda.es/\$1 \[NC,R=302,L\]" "$ACTIVE_VHOSTS")" == 2 ]'
check "media: ni en tienda.es ni en otra.local" \
    '! awk "/ServerName (tienda.es|otra.local)/{f=1} /<\/VirtualHost>/{f=0} f && /nexum-media/" "$ACTIVE_VHOSTS" | grep -q .'
check "media: solo GET y HEAD, solo si falta el fichero y solo imagenes, videos y pdf" \
    'grep -qF "RewriteCond %{REQUEST_METHOD} ^(GET|HEAD)\$" "$ACTIVE_VHOSTS" && grep -qF "RewriteCond %{DOCUMENT_ROOT}%{REQUEST_URI} !-f" "$ACTIVE_VHOSTS" && ! grep -q "php" <<< "$MEDIA_EXT"'
check "media: el comprobador de vhosts la admite" \
    'python3 -I -c "$(eval "$(sed -n "/^VHOSTS_CHECK_PY='"'"'/,/^'"'"'\$/p" "$SRC")"; printf "%s" "$VHOSTS_CHECK_PY")" "$ACTIVE_VHOSTS" "$W/original.conf"'
cp "$ACTIVE_VHOSTS" "$W/con-media.conf"
o=$(media_proxy tienda.local www.tienda.es)
check "media: otra vez lo mismo, nada que cambiar" 'cmp -s "$ACTIVE_VHOSTS" "$W/con-media.conf" && grep -q "ya pide" <<< "$o"'
o=$(media_proxy tienda.local tienda.es)
check "media: otro dominio sustituye al anterior" \
    '[ "$(grep -c "# nexum-media " "$ACTIVE_VHOSTS")" == 2 ] && ! grep -q "www.tienda.es/\$1" "$ACTIVE_VHOSTS"'
o=$(media_proxy tienda.local quitar)
check "media: quitar deja los vhosts como estaban" 'cmp -s "$ACTIVE_VHOSTS" "$W/original.conf"'

# borrar-proyecto
rm -f "$W/hecho.log"
o=$(delete_project tienda --bd ps_otra)
check "borrar: una BBDD que no existe se dice antes de tocar nada" '[ $? -ne 0 ] && [ ! -e "$W/hecho.log" ] && [ -d "$HTDOCS_DIR/tienda" ]'
o=$(delete_project ../otra)
check "borrar: una carpeta fuera de htdocs no" '[ $? -ne 0 ] && [ -d "$HTDOCS_DIR/otra" ]'
o=$(delete_project web.local)
check "borrar: el vhost de los proyectos no" '[ $? -ne 0 ]'
o=$(FALLA_BD=1; delete_project tienda --bd ps_tienda --copia)
check "borrar: si falla la BBDD (o su copia), ni vhosts ni carpeta" \
    '[ $? -ne 0 ] && cmp -s "$ACTIVE_VHOSTS" "$W/original.conf" && [ -d "$HTDOCS_DIR/tienda" ]'
rm -f "$W/hecho.log"
o=$(FALLA_VHOSTS=1; delete_project tienda)
check "borrar: si Apache no acepta los vhosts, la carpeta se queda" '[ $? -ne 0 ] && [ -d "$HTDOCS_DIR/tienda" ]'
mkdir -p "$DOCKER_DIR/tienda"; printf 'CARPETA=tienda\n' > "$DOCKER_DIR/tienda/proyecto.conf"
mkdir -p "$DOCKER_DIR/otra"; printf 'CARPETA=otra\n' > "$DOCKER_DIR/otra/proyecto.conf"
printf 'ps_tienda=tienda 8.4\nps_otra=otra\n' > "$PROJECTS_FILE"; printf 'tienda\notra\n' > "$REPO_PROJECTS_FILE"
rm -f "$W/hecho.log"
o=$(delete_project tienda --bd ps_tienda --copia)
check "borrar: termina bien y la carpeta ya no esta" '[ $? -eq 0 ] && [ ! -e "$HTDOCS_DIR/tienda" ] && [ -d "$HTDOCS_DIR/otra" ]'
check "borrar: por orden: Docker, BBDD con copia, vhosts, hosts" \
    '[ "$(grep -v ^encendido "$W/hecho.log" | tr "\n" ,)" == "docker borrar tienda,bd ps_tienda --copia,vhosts,hosts," ]'
check "borrar: solo los vhosts de su carpeta" \
    '! grep -q "htdocs/tienda" "$ACTIVE_VHOSTS" && grep -q "ServerName otra.local" "$ACTIVE_VHOSTS"'
check "borrar: sus dominios fuera de hosts (falseados y comentados); los de otros, no" \
    '[ "$(cat "$HOSTS_FILE")" == "$(printf "127.0.0.1 localhost\n127.0.0.1 otra.local")" ]'
check "borrar: el gestor ya no lo recuerda (y al otro si)" \
    '[ "$(cat "$PROJECTS_FILE")" == "ps_otra=otra" ] && [ "$(cat "$REPO_PROJECTS_FILE")" == "otra" ]'

# media-proyecto y media_sync: la regla de web.local sigue al WordPress cargado
grep -q '^function media_project() {' "$SRC" || exit $fail
extract "$SRC" media_project media_sync media_saved || exit 1
MEDIA_PROJECTS_FILE=$LOG_DIR/media-produccion
mkdir -p "$HTDOCS_DIR/blog" "$HTDOCS_DIR/blog2" "$HTDOCS_DIR/tienda2"
printf '<VirtualHost *:80>\n    DocumentRoot "/opt/lampp/htdocs/web.local"\n    ServerName web.local\n</VirtualHost>\n' > "$ACTIVE_VHOSTS"
cp "$ACTIVE_VHOSTS" "$W/web.conf"
vhosts_info() { echo "80|web.local|web.local||"; }
is_prestashop() { [ "$1" == tienda2 ]; }
ln -sfn blog "$HTDOCS_DIR/web.local"
o=$(media_project tienda2 tienda.es)
check "media-proyecto: una tienda PrestaShop no (dominio falseado: se descargan)" '[ $? -ne 0 ] && grep -q ps-imagenes <<< "$o" && [ ! -e "$MEDIA_PROJECTS_FILE" ]'
o=$(media_project blog https://Blog.ES/)
check "media-proyecto: se guarda y, si esta cargado, va en web.local" \
    '[ "$(cat "$MEDIA_PROJECTS_FILE")" == "blog|blog.es" ] && grep -q "https://blog.es/\$1" "$ACTIVE_VHOSTS"'
o=$(media_project blog2 blog2.es)
check "media-proyecto: el de otro proyecto se guarda sin tocar web.local" \
    'grep -qx "blog2|blog2.es" "$MEDIA_PROJECTS_FILE" && grep -q "https://blog.es/\$1" "$ACTIVE_VHOSTS"'
ln -sfn blog2 "$HTDOCS_DIR/web.local"; media_sync > /dev/null
check "media_sync: al cargar otro, web.local pasa a su dominio" 'grep -q "https://blog2.es/\$1" "$ACTIVE_VHOSTS" && ! grep -q "blog.es/" "$ACTIVE_VHOSTS"'
rm -f "$W/hecho.log"; media_sync > /dev/null
check "media_sync: sin cambios, no se tocan los vhosts" '[ ! -e "$W/hecho.log" ]'
ln -sfn tienda2 "$HTDOCS_DIR/web.local"; media_sync > /dev/null
check "media_sync: con una tienda cargada, web.local sin regla" 'cmp -s "$ACTIVE_VHOSTS" "$W/web.conf"'
ln -sfn blog2 "$HTDOCS_DIR/web.local"; media_sync > /dev/null
o=$(media_project blog2 quitar)
check "media-proyecto quitar: se olvida y web.local sin regla" \
    '! grep -q blog2 "$MEDIA_PROJECTS_FILE" && cmp -s "$ACTIVE_VHOSTS" "$W/web.conf"'

# ps-imagenes: el descargador, con un curl falso (200, 404, 301 o 403 segun la ruta)
grep -q '^function ps_images() {' "$SRC" || exit $fail
awk '/^function ps_images\(\) \{/,/^}/' "$SRC" | awk "/<< 'EOF'/{f=1;next} /^EOF\$/{f=0} f" > "$W/dl.py"
mkdir -p "$W/bin" "$W/ps/img/p" "$W/fuera" "$W/dl"
ln -s "$W/fuera" "$W/ps/img/p/5"
cat > "$W/bin/curl" << 'EOF'
#!/bin/bash
# curl falso: -K <config> con url/output; -A apuntado; -w como el de verdad
while [ $# -gt 0 ]; do
    case $1 in -K) cfg=$2; shift ;; -A) echo "$2" > "$CURL_LOG" ;; esac
    shift
done
url=""
while IFS= read -r l; do
    case $l in
        url*) url=${l#*\"}; url=${url%\"} ;;
        output*) out=${l#*\"}; out=${out%\"}
            case $url in
                */bloqueada/*) echo "22 403 $out" ;;
                */no/*) echo "22 404 $out" ;;
                */mueve/*) echo "0 301 $out" ;;
                *) echo "imagen" > "$out"; echo "0 200 $out" ;;
            esac ;;
    esac
done < "$cfg"
EOF
chmod +x "$W/bin/curl"
printf 'img/p/1/1.jpg\nimg/p/1/1-home_default.jpg\nimg/p/no/2.jpg\nimg/p/mueve/3.jpg\nimg/p/5/5.jpg\n' > "$W/lista"
o=$(PATH=$W/bin:$PATH CURL_LOG=$W/agente python3 -I "$W/dl.py" "$W/ps" tienda.es "" "$W/dl" "$W/lista" "Nexum Dev Stack/9.9")
check "ps-imagenes: solo pasan a img las que llegan enteras (200)" \
    '[ "$(cat "$W/ps/img/p/1/1.jpg")" == imagen ] && [ -f "$W/ps/img/p/1/1-home_default.jpg" ] && [ ! -e "$W/ps/img/p/no" ] && [ ! -e "$W/ps/img/p/mueve" ]'
check "ps-imagenes: nada fuera de img (un enlace dentro que lleva a otra carpeta)" '[ -z "$(ls -A "$W/fuera")" ]'
check "ps-imagenes: cuenta las que no estan y las que redirigen" 'grep -q "Descargadas 2 de 5 (2 no estan en produccion, 1 con redireccion)" <<< "$o"'
check "ps-imagenes: se presenta como el programa, no como un navegador" 'grep -q "^Nexum-Dev-Stack/9.9 " "$W/agente" && ! grep -qi mozilla "$W/agente"'
check "ps-imagenes: sin restos en la carpeta temporal" '[ -z "$(ls -A "$W/dl")" ]'
seq 1 400 | sed 's|^|img/p/bloqueada/|; s|$|.jpg|' > "$W/lista"
o=$(PATH=$W/bin:$PATH CURL_LOG=$W/agente python3 -I "$W/dl.py" "$W/ps" tienda.es "" "$W/dl" "$W/lista" "Nexum/9.9")
check "ps-imagenes: si la web lo bloquea todo, para en el primer lote y explica que hacer" \
    '[ $? -ne 0 ] && [ "$(grep -c "^Descargadas" <<< "$o")" == 1 ] && grep -q "dale permiso en el servidor" <<< "$o"'
exit $fail
