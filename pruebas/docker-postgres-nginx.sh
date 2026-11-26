#!/bin/bash
# Pruebas de la PostgreSQL y el Nginx comunes de Docker (Configuración > Docker, 1.57.39). PostgreSQL: una
# por versión, en la red interna y en 127.0.0.1 (54300 + la versión), con su contraseña al azar solo tuya;
# con alguna, las imágenes de PHP traen pgsql. Nginx: uno, al lado del Apache de Docker, para los proyectos
# que se le añaden, con sus dominios y sus puertos (8081 y 8444). Sin Docker: la orden dk es falsa.
# Uso: docker-postgres-nginx.sh <lvm-instalador.sh de Linux o del Mac>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-dkpgng.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
extract "$SRC" docker_pg_name docker_pg_port docker_pg_versions docker_pg_pass docker_pg_state docker_pg_up docker_pg_command \
    docker_php_ext docker_pg_dockerfile docker_php_needs_pgsql docker_pg_rebuild \
    docker_nginx_get docker_nginx_projects docker_nginx_state docker_nginx_url docker_nginx_site docker_nginx_write docker_nginx_up \
    docker_nginx_command docker_conf docker_conf_set docker_projects docker_valid_slug docker_web_projects docker_web_project \
    docker_web_domain docker_web_domains docker_web_container docker_web_tld docker_web_get || exit 1
grep -q "^function docker_web_valid_ip() {" "$SRC" && { extract "$SRC" docker_web_valid_ip || exit 1; }
eval "$(grep -E '^(DOCKER_PG_VERSIONS|DOCKER_NGINX_IMAGE|DOCKER_STOPPED_MSG|DOCKER_NGINX_FASTCGI|DOCKER_PHP_EXT|DOCKER_PHP_VERSIONS)=' "$SRC")"
MAC=0
grep -q "^let ERROR_LOG = " "$SRC" && MAC=1
DOCKER_DIR=$W/docker DOCKER_WEB_DIR=$W/docker/web DOCKER_WEB_FILE=$W/docker/web.conf DOCKER_NGINX_DIR=$W/docker/nginx
DOCKER_NGINX_FILE=$W/docker/nginx.conf HTDOCS_DIR=$W/htdocs DRY=0
# (dk falsa: lo que se le pide, a su registro; RUNNING=1, los contenedores en marcha; LABEL, la etiqueta pgsql)
RUNNING=0 LABEL=""
dk() {
    echo "dk $*" >> "$W/dk.log"
    case "$1 $2" in
        "ps -a") [ "$RUNNING" == 1 ] && echo running ;;
        "exec "*) return 0 ;;
        "image inspect") case "$*" in *nexum.pgsql*) echo "$LABEL" ;; esac; [ "$IMG" == 1 ] ;;
    esac
    return 0
}
run() { "$@"; }
docker_ready() { return 0; }
docker_net() { echo net >> "$W/dk.log"; }
docker_web_cert() { echo cert >> "$W/dk.log"; }
docker_php_image() { echo "imagen $*" >> "$W/dk.log"; }
mkdir -p "$DOCKER_DIR/blog" "$DOCKER_DIR/tienda" "$DOCKER_DIR/viejo" "$HTDOCS_DIR/blog"
printf 'MODO=web\nCARPETA=blog\nPHP=8.3 8.4\nTIPO=wp\n' > "$DOCKER_DIR/blog/proyecto.conf"
printf 'MODO=web\nCARPETA=tienda\nPHP=8.2 8.3\nACTIVA=8.3\nTIPO=ps\n' > "$DOCKER_DIR/tienda/proyecto.conf"
printf 'CARPETA=viejo\nPHP=8.1\n' > "$DOCKER_DIR/viejo/proyecto.conf"
perm() { stat -c %a "$1" 2> /dev/null || stat -f %Lp "$1"; }

# PostgreSQL
check "PostgreSQL: se ofrecen la 18, la 17 y la 16" '[ "$DOCKER_PG_VERSIONS" == "18 17 16" ]'
check "sin ninguna, las imágenes de PHP como siempre" '[ -z "$(docker_pg_versions)" ] && [ "$(docker_php_ext)" == "$DOCKER_PHP_EXT" ] && [ -z "$(docker_pg_dockerfile)" ] && ! IMG=1 docker_php_needs_pgsql 8.4'
o=$(docker_pg_command arrancar 15); check "una versión que no se ofrece, no" '[[ "$o" == *"no se ofrece"* ]] && [ ! -d "$DOCKER_DIR/postgres-15" ]'
: > "$W/dk.log"
o=$(IMG=0 docker_pg_command arrancar 18)
C=$DOCKER_DIR/postgres-18/compose.yaml
check "crear: su compose, con su imagen oficial, en la red interna" 'grep -qx "    image: postgres:18" "$C" && grep -qx "    container_name: nexum-postgres-18" "$C" && grep -q "name: nexum$" "$C" && grep -q "^dk compose --project-directory $DOCKER_DIR/postgres-18 -f $C up -d" "$W/dk.log"'
check "crear: en este equipo, solo en 127.0.0.1 y en su puerto (54318)" 'grep -qx "      - \"127.0.0.1:54318:5432\"" "$C" && [ "$(grep -c "^ *- \".*:5432\"" "$C")" -eq 1 ]'
check "crear: la 18 guarda sus datos en /var/lib/postgresql" 'grep -qx "      - \"datos:/var/lib/postgresql\"" "$C"'
check "crear: su contraseña al azar, solo tuya, y no en el compose" '[ -n "$(docker_pg_pass 18)" ] && [ "$(perm "$DOCKER_DIR/postgres-18/.env")" == 600 ] && [ "$(perm "$C")" == 600 ] && grep -qF "POSTGRES_PASSWORD: \${PG_PASS}" "$C" && ! grep -qF "$(docker_pg_pass 18)" "$C"'
check "crear: espera a que responda y dice cómo llegar" 'grep -q "^dk exec nexum-postgres-18 pg_isready -U postgres -q" "$W/dk.log" && [[ "$o" == *"nexum-postgres-18:5432"* ]] && [[ "$o" == *"127.0.0.1:54318"* ]]'
o=$(IMG=0 docker_pg_command arrancar 17); check "la 17, con sus datos en /var/lib/postgresql/data y su puerto" 'grep -qx "      - \"datos:/var/lib/postgresql/data\"" "$DOCKER_DIR/postgres-17/compose.yaml" && grep -qx "      - \"127.0.0.1:54317:5432\"" "$DOCKER_DIR/postgres-17/compose.yaml"'
check "con alguna, las imágenes de PHP traen pgsql y pdo_pgsql (con su etiqueta)" '[ "$(docker_php_ext)" == "$DOCKER_PHP_EXT pgsql pdo_pgsql" ] && [ "$(docker_pg_dockerfile)" == "LABEL nexum.pgsql=\"1\"" ]'
check "una imagen sin pgsql se rehace; con él, no" 'IMG=1 LABEL="" docker_php_needs_pgsql 8.4 && ! IMG=1 LABEL=1 docker_php_needs_pgsql 8.4'
: > "$W/dk.log"
o=$(IMG=1 LABEL="" docker_pg_rebuild); check "al crearla, las imágenes de PHP que hay se rehacen con pgsql" '[ "$(grep -c "^imagen .* --rehacer" "$W/dk.log")" -eq "$(wc -w <<< "$DOCKER_PHP_VERSIONS")" ]'
o=$(RUNNING=1 docker_pg_command estado); check "estado: cada una con su puerto y las que se ofrecen" '[[ "$o" == *"G|18|marcha|54318|nexum-postgres-18"* ]] && [[ "$o" == *"G|17|marcha|54317|nexum-postgres-17"* ]] && [[ "$o" == *"O|18 17 16"* ]]'
o=$(docker_pg_command borrar 16); check "borrar una que no hay, no" '[[ "$o" == *"No hay PostgreSQL 16"* ]]'
: > "$W/dk.log"
o=$(docker_pg_command borrar 17); check "borrar: su contenedor, sus datos y sus ficheros" 'grep -q "^dk compose .* down -v" "$W/dk.log" && grep -q "^dk volume rm nexum-postgres-17" "$W/dk.log" && [ ! -d "$DOCKER_DIR/postgres-17" ] && [ "$(docker_pg_versions)" == 18 ]'
DRY=1; o=$(docker_pg_command arrancar 16; docker_pg_command borrar 18); DRY=0
check "en simulación no cambia nada" '[ ! -d "$DOCKER_DIR/postgres-16" ] && [ -d "$DOCKER_DIR/postgres-18" ] && [[ "$o" == *"[simulacion]"* ]]'
check "las imágenes de PHP: con pgsql al construirlas y rehechas si les falta" 'grep -qF "\$(docker_php_ext)" "$SRC" && grep -qxF "        docker_pg_dockerfile" "$SRC" && grep -qF "! docker_php_needs_pgsql \"\$php\"" "$SRC"'
check "Componentes: la imagen de cada PostgreSQL y las de PHP sin pgsql" 'grep -qF "docker_image_outdated \"postgres:\$v\" && { echo \"K|postgres:\$v|la PostgreSQL \$v de Docker\"" "$SRC" && grep -qF "(nexum-php:\$v), para que traiga pgsql\"" "$SRC" && grep -qF "            postgres:*) steps+=(\"PostgreSQL \${v#postgres:} de Docker\") ;;" "$SRC"'

# Nginx de Docker
check "Nginx de Docker: imagen oficial fijada por su huella" '[[ "$DOCKER_NGINX_IMAGE" =~ ^nginx:1\.[0-9]+\.[0-9]+-alpine@sha256:[0-9a-f]{64}$ ]]'
check "sus puertos de serie: 8081 y 8444 (los de la pestaña Nginx son el 8080 y el 8443)" '[ "$(docker_nginx_get HTTP)" == 8081 ] && [ "$(docker_nginx_get HTTPS)" == 8444 ]'
o=$(docker_nginx_command anadir viejo); check "añadir: un proyecto del sistema de antes (sin el Apache de Docker), no" '[[ "$o" == *"No es un proyecto de Docker con el Apache de Docker"* ]]'
o=$(docker_nginx_command anadir blog); check "añadir: lo apunta y dice sus direcciones" '[ "$(docker_conf blog NGINX)" == 1 ] && [[ "$o" == *"https://blog-php83.$(docker_web_tld):8444"* ]] && [[ "$o" == *"https://blog-php84.$(docker_web_tld):8444"* ]]'
o=$(docker_nginx_command anadir tienda)
: > "$W/dk.log"
o=$(docker_nginx_command arrancar)
N=$DOCKER_NGINX_DIR/conf/nginx.conf D=$DOCKER_NGINX_DIR/compose.yaml
check "arrancar: con el certificado de *.docker.local, en la red interna, creado de nuevo" 'grep -qx cert "$W/dk.log" && grep -qx net "$W/dk.log" && grep -q "^dk compose --project-directory $DOCKER_NGINX_DIR -f $D up -d --force-recreate" "$W/dk.log"'
check "compose: en la dirección y los puertos de Docker, con htdocs, su configuración y los certificados solo para leer" 'grep -qx "      - \"$(docker_web_get IP):8081:80\"" "$D" && grep -qx "      - \"$(docker_web_get IP):8444:443\"" "$D" && grep -qx "      - \"$HTDOCS_DIR:/opt/lampp/htdocs:ro\"" "$D" && grep -qx "      - \"./conf:/etc/nginx/nexum:ro\"" "$D" && grep -qx "      - \"$DOCKER_WEB_DIR/certs:/certs:ro\"" "$D" && [ "$(perm "$D")" == 600 ]'
check "configuración: cada versión del proyecto por su dominio; de una tienda, solo la elegida" 'grep -qF "server_name blog-php83.$(docker_web_tld);" "$N" && grep -qF "server_name blog-php84.$(docker_web_tld);" "$N" && grep -qF "server_name tienda.$(docker_web_tld);" "$N" && [ "$(grep -c "server_name tienda" "$N")" -eq 1 ]'
check "configuración: lo que no es de un proyecto, sin respuesta; nunca ficheros ocultos" 'grep -qF "ssl_reject_handshake on;" "$N" && grep -qF "return 444;" "$N" && grep -qF "location ~ /\.(?!well-known/) { deny all; }" "$N"'
check "configuración: con su PHP parado, lo dice (a los 5 segundos)" 'grep -qF "error_page 502 504 = @parado;" "$N" && grep -qF "fastcgi_connect_timeout 5s;" "$N" && grep -qF "resolver 127.0.0.11 valid=10s ipv6=off;" "$N"'
if [ $MAC -eq 1 ]; then
    check "Mac: al Apache del contenedor de PHP de cada versión, con su dominio" '[ "$DOCKER_NGINX_FASTCGI" == 0 ] && grep -qF "set \$php http://nexum-blog-php83;" "$N" && grep -qF "proxy_set_header Host \$host;" "$N" && ! grep -q fastcgi_pass "$N"'
else
    check "Linux: por FastCGI, al PHP-FPM del contenedor de cada versión (puerto 9000)" '[ "$DOCKER_NGINX_FASTCGI" == 1 ] && grep -qF "set \$php nexum-blog-php83:9000;" "$N" && grep -qF "fastcgi_pass \$php;" "$N" && grep -qF "include /etc/nginx/fastcgi_params;" "$N" && grep -qF "root \"/opt/lampp/htdocs/blog\";" "$N"'
fi
: > "$W/dk.log"
o=$(RUNNING=1 docker_nginx_command quitar tienda); check "quitar, en marcha: prueba la configuración nueva y la recarga sin cortar" '[ "$(docker_conf tienda NGINX)" == 0 ] && ! grep -qF "server_name tienda." "$N" && grep -q "^dk exec nexum-nginx nginx -t -q" "$W/dk.log" && grep -q "^dk exec nexum-nginx nginx -s reload" "$W/dk.log"'
printf 'IP=127.0.0.2\nHTTP=8000\nHTTPS=9443\n' > "$DOCKER_WEB_FILE"
o=$(docker_nginx_command puertos 9443 9444); check "puertos: los del Apache de Docker, no" '[[ "$o" == *"es del Apache de Docker"* ]] && [ "$(docker_nginx_get HTTP)" == 8081 ]'
o=$(docker_nginx_command puertos 80 9444); check "puertos: los de menos de 1024, no" '[[ "$o" == *"no válido"* ]]'
o=$(docker_nginx_command puertos 9081 9444); check "puertos: se guardan (solo tuyos)" '[ "$(docker_nginx_get HTTP)" == 9081 ] && [ "$(docker_nginx_get HTTPS)" == 9444 ] && [ "$(perm "$DOCKER_NGINX_FILE")" == 600 ]'
o=$(RUNNING=1 docker_nginx_command estado); check "estado: cómo está y cada proyecto, con sus direcciones" '[[ "$o" == *"X|marcha|$(docker_web_get IP)|9081|9444"* ]] && [[ "$o" == *"Y|blog|1|https://blog-php83.$(docker_web_tld):9444 https://blog-php84.$(docker_web_tld):9444"* ]] && [[ "$o" == *"Y|tienda|0|"* ]] && [[ "$o" != *"Y|viejo"* ]]'
check "las órdenes, sin contraseña de administrador" 'grep -qxF "        docker-postgres) ;;" "$SRC" && grep -qxF "        docker-nginx) ;;" "$SRC" && grep -qxF "    docker-postgres) shift; docker_pg_command \"\$@\" ;;" "$SRC" && grep -qxF "    docker-nginx) shift; docker_nginx_command \"\$@\" ;;" "$SRC"'
if [ $MAC -eq 1 ]; then
    check "Mac: en Configuración, Docker" 'grep -qxF "          PgCard()" "$SRC" && grep -qxF "          DockerNginxCard()" "$SRC" && grep -qF "runQuick([\"docker-postgres\"])" "$SRC" && grep -qF "runQuick([\"docker-nginx\"])" "$SRC"'
else
    check "Linux: en Configuración, Docker" 'grep -qxF "        self.nv_docker_extras(lb)" "$SRC" && grep -qF "run_quick([\"docker-postgres\"], pg_got)" "$SRC" && grep -qF "run_quick([\"docker-nginx\"], ng_got)" "$SRC"'
fi
exit $fail
