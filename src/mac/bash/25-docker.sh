# ===========================================================================
# Docker (Docker Desktop): proyectos con cualquier version de PHP en contenedores
# ===========================================================================
# Cada proyecto en Docker lleva su web (Apache con PHP), su MariaDB (con una copia de su BBDD) y su phpMyAdmin en
# contenedores de Docker Desktop, que en el Mac corren dentro de su maquina virtual (en el Mac no hay
# Docker sin root: Docker Desktop ya los aparta del sistema, y no se instala desde aqui). La web la
# llega por el Apache de la version XAMPP-X activa, por su dominio (<carpeta>.docker.local, http y
# https con su certificado), que la pasa entera (ProxyPass) a la web del contenedor: Apache con PHP,
# con los .htaccess de siempre. Dentro del contenedor el proyecto esta en la misma ruta que en el Mac
# (/Applications/XAMPP/xamppfiles/htdocs/<carpeta>), y su wp-config.php (o parameters.php /
# settings.inc.php) se sustituye por uno con la BBDD del contenedor: el del proyecto no se toca, y la
# carpeta se puede seguir usando con XAMPP-X a la vez.
# En el Mac la web del contenedor se publica por TCP en 127.0.0.1, con un puerto por proyecto (desde
# DOCKER_WEB_PORT): las carpetas compartidas de Docker Desktop (VirtioFS o gRPC FUSE) pasan
# ficheros, no sockets. Para que ningun otro programa del Mac (ni otro contenedor, por
# host.docker.internal) la use, solo responde a las peticiones con la clave del proyecto
# (X-Nexum-Key), que pone el vhost con un Include de root y solo para root (DOCKER_KEYS_DIR), y con su
# dominio. Hasta la 1.39.1 se publicaba PHP-FPM (FastCGI, sin clave): docker_migrate lo cambia.
# (LVM_DOCKER y LVM_DOCKER_HOST solo para pruebas)
DOCKER_DIR=${LVM_DOCKER_DIR:-$HOME/.lvm-instalador/docker}
# Versiones que se ofrecen: imagenes oficiales php:<version>-apache y mariadb:<version> de Docker Hub
DOCKER_PHP_VERSIONS="8.5 8.4 8.3 8.2 8.1 8.0 7.4 7.3 7.2 7.1 7.0 5.6"
DOCKER_MARIADB_VERSIONS="11.8 11.4 10.11 10.6 10.5 10.4"
DOCKER_PMA_IMAGE="phpmyadmin:5.2"
# Extensiones de PHP de las imagenes (las que piden WordPress y PrestaShop)
DOCKER_PHP_EXT="bcmath exif gd intl mysqli opcache pdo_mysql soap zip"
# Puertos de 127.0.0.1 para el phpMyAdmin y la web de cada proyecto (uno por proyecto, desde estos;
# hasta la 1.39.1 el segundo era el de su PHP-FPM, y se sigue usando el mismo)
DOCKER_PMA_PORT=28080
DOCKER_WEB_PORT=29000
# Claves de los proyectos para el Apache del Mac (de root y solo para root; VHOSTS_CHECK_PY solo
# admite este Include)
DOCKER_KEYS_DIR=/Library/Nexum/XAMPP-compartido/docker-claves
# Docker Desktop: la aplicacion y su pagina de descarga (se instala a mano, como cualquier aplicacion)
DOCKER_APP=/Applications/Docker.app
DOCKER_DOWNLOAD_URL="https://www.docker.com/products/docker-desktop/"

# El docker de Docker Desktop: el de su aplicacion o el enlace que pone en /usr/local/bin
function docker_bin() {
    local b
    for b in ${LVM_DOCKER:-/usr/local/bin/docker "$DOCKER_APP/Contents/Resources/bin/docker" /opt/homebrew/bin/docker}; do
        [ -x "$b" ] && { echo "$b"; return 0; }
    done
    return 1
}

# Socket de Docker Desktop: el de tu usuario (~/.docker/run) o el del sistema, que es un enlace a el
function docker_sock() {
    if [ -n "$LVM_DOCKER_HOST" ]; then
        echo "$LVM_DOCKER_HOST"
    elif [ -S "$HOME/.docker/run/docker.sock" ]; then
        echo "unix://$HOME/.docker/run/docker.sock"
    else
        echo "unix:///var/run/docker.sock"
    fi
}

# Configuracion de docker propia del gestor (no ~/.docker): sin el credsStore "desktop" de Docker
# Desktop, que pide docker-credential-desktop (no esta en el PATH limpio del gestor, y las imagenes
# son publicas: no hace falta), y sin los complementos de ~/.docker/cli-plugins, que puede poner
# cualquier programa de tu usuario. Compose y buildx, los de dentro de Docker Desktop
DOCKER_CONFIG_DIR=$LOG_DIR/docker-config

function docker_config_dir() {
    local d=$DOCKER_CONFIG_DIR
    if [ -L "$d" ] || { [ -e "$d" ] && [ ! -O "$d" ]; }; then
        echo "$d no es una carpeta tuya: no se usa Docker con ella" >&2
        return 1
    fi
    mkdir -p -m 700 "$d" && chmod 700 "$d" || return 1
    rm -rf "$d/cli-plugins"
    ( umask 077; printf '{"cliPluginsExtraDirs": ["%s"]}\n' "$DOCKER_APP/Contents/Resources/cli-plugins" > "$d/config.json" ) \
        || return 1
    echo "$d"
}

function dk() {
    local b conf
    b=$(docker_bin) || { echo "No esta Docker Desktop" >&2; return 1; }
    conf=$(docker_config_dir) || return 1
    DOCKER_HOST=$(docker_sock) DOCKER_CONFIG=$conf "$b" "$@"
}

# ¿Responde Docker Desktop? (0 si si)
function docker_ready() {
    docker_bin > /dev/null || return 1
    dk info --format '{{.ServerVersion}}' > /dev/null 2>&1
}

# Nombre corto de un proyecto: el de su carpeta en minusculas, solo letras, numeros y - (va en el
# nombre de los contenedores y en el dominio)
function docker_slug() {
    local s
    s=$(tr 'A-Z' 'a-z' <<< "$1" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40 | sed -E 's/-+$//')
    [ -n "$s" ] && echo "$s"
}

function docker_valid_slug() {
    [[ "$1" =~ ^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?$ ]]
}

# Valor de proyecto.conf (lineas CLAVE=valor que escribe el gestor)
function docker_conf() {
    local f=$DOCKER_DIR/$1/proyecto.conf
    [ -f "$f" ] && [ ! -L "$f" ] || return 1
    awk -F= -v k="$2" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$f"
}

# Cambia un fichero con sed (sin sed -i, que en el Mac pide otro argumento que en Linux)
function docker_sed() {
    local expr=$1 file=$2
    sed -E "$expr" "$file" > "$file.nuevo" && mv -f "$file.nuevo" "$file"
}

# Proyectos en Docker (nombres cortos validos con su proyecto.conf)
function docker_projects() {
    local d
    [ -d "$DOCKER_DIR" ] || return 0
    for d in "$DOCKER_DIR"/*/; do
        d=$(basename "$d")
        docker_valid_slug "$d" && [ -f "$DOCKER_DIR/$d/proyecto.conf" ] && echo "$d"
    done
}

# ¿Hay algo escuchando en ese puerto de 127.0.0.1? (en el Mac no hay ss)
function docker_port_used() {
    python3 -I -c 'import socket, sys
s = socket.socket()
s.settimeout(0.3)
sys.exit(0 if s.connect_ex(("127.0.0.1", int(sys.argv[1]))) == 0 else 1)' "$1" 2> /dev/null
}

# Primer puerto libre desde <puerto> que no use ya otro proyecto en <clave> de su proyecto.conf
function docker_free_port() {
    local port=$1 key=$2
    while grep -qsE "^($key)=$port$" "$DOCKER_DIR"/*/proyecto.conf || docker_port_used "$port"; do
        port=$((port + 1))
    done
    echo "$port"
}

# Estado de los contenedores de un proyecto: marcha (todos), parado (ninguno), parcial o nuevo
function docker_state() {
    local out up=0 total=0 state
    out=$(dk ps -a --filter "label=com.docker.compose.project=nexum-$1" --format '{{.State}}' 2> /dev/null) || { echo "?"; return 0; }
    while read -r state; do
        [ -z "$state" ] && continue
        total=$((total + 1))
        [ "$state" == running ] && up=$((up + 1))
    done <<< "$out"
    if [ $total -eq 0 ]; then echo nuevo
    elif [ $up -eq $total ]; then echo marcha
    elif [ $up -eq 0 ]; then echo parado
    else echo parcial
    fi
}

# Para la ventana:
#   S|docker instalado (1/0)|Docker Desktop responde (1/0)|version|XAMPP-X activa en marcha (1/0)|
#     esta la aplicacion Docker Desktop (1/0)
#   V|versiones de PHP|versiones de MariaDB
#   P|nombre|carpeta|php|mariadb|dominio|estado|bbdd|puerto de phpMyAdmin|puerto de la web|
#     1 si aun tiene PHP-FPM abierto en 127.0.0.1 (antes de la 1.39.2: docker-migrar)
#   C|contenedor|imagen|estado (running, exited...)|estado en texto|puertos|proyecto de compose
#     (todos los contenedores de Docker Desktop, para la consola de la pestaña)
#   I|imagen|etiqueta|ID corto|tamaño|creada  y  O|volumen|driver   (imagenes y volumenes; hasta la
#     1.39.4, I|imagen:etiqueta|tamaño|creada)
function gui_docker() {
    local installed=0 ready=0 version="" app=0 p
    docker_bin > /dev/null && installed=1
    [ -d "$DOCKER_APP" ] && app=1
    if [ $installed -eq 1 ] && docker_ready; then
        ready=1
        version=$(dk version --format '{{.Server.Version}}' 2> /dev/null | tr -cd '0-9.')
        # (con proyectos del Apache de Docker, que el temporizador de los que no tienen visitas este puesto:
        # los de antes de la 1.56.8 / 1.40.1 no lo tenian)
        [ -n "$(docker_web_projects)" ] && docker_idle_ensure
    fi
    echo "S|$installed|$ready|$version|$(lampp_running && echo 1 || echo 0)|$app"
    echo "V|$DOCKER_PHP_VERSIONS|$DOCKER_MARIADB_VERSIONS"
    for p in $(docker_projects); do
        # (los del Apache de Docker: web en vez de los puertos, y su tipo y sus versiones de PHP al final)
        if docker_web_project "$p"; then
            echo "P|$p|$(docker_conf "$p" CARPETA)|$(docker_conf "$p" ACTIVA)|$(docker_conf "$p" MARIADB)|$(docker_conf "$p" DOMINIO)|$([ $ready -eq 1 ] && docker_state "$p" || echo "?")|$(docker_conf "$p" BBDD)|web|web|0|$(docker_conf "$p" TIPO)|$(docker_conf "$p" PHP)|$(docker_conf "$p" LAMPP_BD)" \
                | tr -d '\000-\010\013-\037'
            continue
        fi
        echo "P|$p|$(docker_conf "$p" CARPETA)|$(docker_conf "$p" PHP)|$(docker_conf "$p" MARIADB)|$(docker_conf "$p" DOMINIO)|$([ $ready -eq 1 ] && docker_state "$p" || echo "?")|$(docker_conf "$p" BBDD)|$(docker_conf "$p" PUERTO_PMA)|$(docker_conf "$p" PUERTO_WEB)$(docker_conf "$p" PUERTO_FPM)|$([ "$(docker_conf "$p" ESQUEMA)" == "$DOCKER_IMAGE_SCHEMA" ] && echo 0 || echo 1)" \
            | tr -d '\000-\010\013-\037'
    done
    # El Apache de Docker: W|direccion|http|https|estado|direccion dada de alta (1/0)
    echo "W|$(docker_web_get IP)|$(docker_web_get HTTP)|$(docker_web_get HTTPS)|$([ $ready -eq 1 ] && docker_web_state || echo "?")|$(docker_web_ports_ok && echo 1 || echo 0)|$(docker_web_tld)|$(docker_dns_on && echo 1 || echo 0)"
    if [ $ready -eq 1 ]; then
        # (al final, el ID corto del contenedor)
        dk ps -a --format '{{.Names}}|{{.Image}}|{{.State}}|{{.Status}}|{{.Ports}}|{{.Label "com.docker.compose.project"}}|{{.ID}}' 2> /dev/null \
            | tr -d '\000-\010\013-\037' | awk -F'|' -v OFS='|' 'NF == 7 && $7 ~ /^[0-9a-f]+$/ {
                # (el puente hasta la BBDD de una version XAMPP-X no es de compose: va con su nombre)
                if ($6 == "" && $1 ~ /^nexum-lampp-bd-[0-9]+-[0-9]+(-[0-9]+)?$/) $6 = $1
                print "C|" $0 }'
        # (imagen, etiqueta e ID corto por separado)
        dk images --format '{{.Repository}}|{{.Tag}}|{{.ID}}|{{.Size}}|{{.CreatedSince}}' 2> /dev/null \
            | tr -d '\000-\010\013-\037' | awk -F'|' 'NF == 5 && $3 ~ /^[0-9a-f]+$/ { print "I|" $0 }'
        dk volume ls --format '{{.Name}}|{{.Driver}}' 2> /dev/null \
            | tr -d '\000-\010\013-\037' | awk -F'|' 'NF == 2 { print "O|" $0 }'
    fi
    return 0
}

# Uso de CPU y memoria de los contenedores en marcha (tarda un par de segundos: docker stats mide):
#   T|nucleos|memoria en bytes (los de la maquina virtual de Docker Desktop, o los del Mac)   y
#   K|contenedor|% de CPU|memoria usada (texto de Docker)
function gui_docker_stats() {
    docker_ready || return 0
    local info
    info=$(dk info --format '{{.NCPU}}|{{.MemTotal}}' 2> /dev/null | tr -cd '0-9|')
    [[ "$info" =~ ^[0-9]+\|[0-9]+$ ]] || info="$(sysctl -n hw.ncpu 2> /dev/null || echo 1)|$(sysctl -n hw.memsize 2> /dev/null || echo 0)"
    echo "T|$info"
    dk stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}' 2> /dev/null \
        | tr -d '\000-\010\013-\037' | awk -F'|' 'NF == 3 { print "K|" $0 }'
    return 0
}

# docker-contenedor arrancar|parar|reiniciar|registros <contenedor>: uno solo de los contenedores de
# un proyecto del gestor (nexum-<proyecto>-php|db|pma-N), no cualquiera de Docker Desktop
function docker_container_action() {
    local action=$1 name=$2
    if ! [[ "$name" =~ ^nexum-[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?-(php|db|pma)-[0-9]{1,3}$ \
            || "$name" =~ ^nexum-[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?-php[0-9]{2}$ \
            || "$name" =~ ^nexum-(web|pma|mariadb-[0-9]{1,2}-[0-9]{1,2}|lampp-bd-[0-9]{1,2}-[0-9]{1,2}(-[0-9]{1,3})?)$ ]]; then
        echo "Contenedor no valido: $name (solo los de los proyectos en Docker del gestor)"
        return 1
    fi
    case $action in
        arrancar)
            if [[ "$name" =~ ^nexum-lampp-bd-([0-9]{1,2})-([0-9]{1,2})(-([0-9]{1,3}))?$ ]]; then
                local f=${BASH_REMATCH[1]}.${BASH_REMATCH[2]}${BASH_REMATCH[4]:+.${BASH_REMATCH[4]}}
                lampp_bd_up "$f" && lampp_bd_bridge_up "$f"
                return
            fi
            run dk start "$name" ;;
        parar)
            docker_shared_warn "$name"
            run dk stop "$name" ;;
        reiniciar) run dk restart "$name" ;;
        registros) dk logs --tail 200 "$name" ;;
        # (se quita el contenedor; los datos de la BBDD siguen en su volumen y, al arrancar el
        # proyecto, se vuelve a crear. Para quitarlo todo: docker-borrar <proyecto>)
        borrar) run dk rm -f "$name" ;;
        *) echo "Uso: lvm-instalador docker-contenedor arrancar|parar|reiniciar|registros|borrar <contenedor>"; return 1 ;;
    esac
}

# docker-imagenes borrar <ID|imagen:etiqueta> | descargar <imagen:etiqueta>: las imagenes de Docker
# Desktop. Se borra sin -f: si la usa algun contenedor (aunque este parado), Docker no la borra y lo dice
function docker_image_action() {
    local action=$1 ref=$2
    case $action in
        borrar)
            [[ "$ref" =~ ^[0-9a-f]{12,64}$ || "$ref" =~ ^[a-z0-9][a-z0-9._/-]{0,127}:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] \
                || { echo "Imagen no valida: $ref"; return 1; }
            run dk image rm "$ref" ;;
        descargar)
            [[ "$ref" =~ ^[a-z0-9][a-z0-9._/-]{0,127}:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] \
                || { echo "Imagen no valida: $ref (imagen:etiqueta)"; return 1; }
            # (las nexum-php:X son del gestor y no estan en Docker Hub: se rehacen con docker-imagen)
            [[ "$ref" == nexum-* ]] && { echo "$ref es del gestor: se rehace con «Actualizar imagen» de su proyecto"; return 1; }
            run dk pull "$ref" ;;
        *) echo "Uso: lvm-instalador docker-imagenes borrar <ID|imagen:etiqueta> | descargar <imagen:etiqueta>"; return 1 ;;
    esac
}

# docker-volumen-borrar <volumen>: Docker no borra uno que use algun contenedor (aunque este parado)
function docker_volume_remove() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ ]] || { echo "Volumen no valido: $1"; return 1; }
    run dk volume rm "$1"
}

# docker-php <nombre> <version>: cambia la version de PHP de un proyecto en Docker. Solo se cambia su
# contenedor de PHP (con la imagen de esa version, que se prepara si hace falta): su BBDD, su
# phpMyAdmin y su configuracion se quedan como estaban
function docker_set_php() {
    local slug=$1 php=$2 dir old
    if ! docker_valid_slug "$slug" || [ ! -f "$DOCKER_DIR/$slug/proyecto.conf" ]; then
        echo "No hay ningun proyecto en Docker con el nombre $slug"
        return 1
    fi
    [[ " $DOCKER_PHP_VERSIONS " == *" $php "* ]] || { echo "PHP $php no se ofrece en Docker ($DOCKER_PHP_VERSIONS)"; return 1; }
    if docker_web_project "$slug"; then
        echo "$slug va con el Apache de Docker: sus versiones de PHP se añaden y se quitan (docker-php-añadir, docker-php-quitar)"
        return 1
    fi
    dir=$DOCKER_DIR/$slug
    old=$(docker_conf "$slug" PHP)
    if [ "$old" == "$php" ]; then
        echo "$slug ya usa PHP $php"
        return 0
    fi
    if ! grep -qE '^    image: nexum-php:[0-9.]+$' "$dir/compose.yaml"; then
        echo "No se encuentra el contenedor de PHP en $dir/compose.yaml"
        return 1
    fi
    echo "$slug: PHP $old -> $php (la BBDD y la configuracion no cambian)"
    # (los de antes de la 1.39.2, con PHP-FPM abierto, pasan antes a la web con clave)
    docker_migrate "$slug" || return 1
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] imagen nexum-php:$php y contenedor de PHP nuevo"
        return 0
    fi
    docker_ready || { echo "Docker Desktop no esta en marcha"; return 1; }
    docker_php_image "$php" || { echo "No se ha podido preparar la imagen de PHP $php: sigue con PHP $old"; return 1; }
    docker_sed "s|^    image: nexum-php:[0-9.]+$|    image: nexum-php:$php|" "$dir/compose.yaml" \
        && docker_sed "s/^PHP=.*/PHP=$php/" "$dir/proyecto.conf" || return 1
    if ! dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d php; then
        echo "No arranca con PHP $php: se vuelve a PHP $old"
        docker_sed "s|^    image: nexum-php:[0-9.]+$|    image: nexum-php:$old|" "$dir/compose.yaml"
        docker_sed "s/^PHP=.*/PHP=$old/" "$dir/proyecto.conf"
        dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d php
        return 1
    fi
    echo "$slug ya funciona con PHP $php"
}

# docker-instalar: en el Mac, Docker es Docker Desktop, que se instala a mano como cualquier
# aplicacion (pide aceptar su licencia y la contraseña de administrador). Si no esta, se abre su
# pagina de descarga; si esta y no responde, se abre y se espera a que arranque
function docker_install() {
    if [ ! -d "$DOCKER_APP" ] && ! docker_bin > /dev/null; then
        echo "Docker Desktop no esta instalado. En el Mac no se instala desde aqui: se abre su pagina"
        echo "de descarga ($DOCKER_DOWNLOAD_URL). Descarga la version para Apple Silicon, arrastra"
        echo "Docker a Aplicaciones, abrelo una vez y vuelve a la pestaña Docker."
        run open "$DOCKER_DOWNLOAD_URL"
        return 0
    fi
    if docker_ready; then
        echo "Docker Desktop ya esta en marcha (socket $(docker_sock))."
        return 0
    fi
    task_plan "Abriendo Docker Desktop" "Abrir Docker Desktop" "Esperar a que responda"
    task_step
    echo "Abriendo Docker Desktop..."
    run open -a "$DOCKER_APP" || return 1
    task_step
    local i
    for i in $(seq 90); do docker_ready && break; [ "$DRY" -eq 1 ] && break; sleep 1; done
    if [ "$DRY" -eq 0 ] && ! docker_ready; then
        echo "Docker Desktop no responde todavia. Si te pide aceptar su licencia o la contraseña, hazlo"
        echo "en su ventana y pulsa Comprobar."
        return 1
    fi
    echo "Docker Desktop listo (socket $(docker_sock))."
}

# Imagen de PHP del gestor para una version (nexum-php:<version>): la oficial php:<version>-apache
# (Apache con PHP dentro, como en XAMPP: con los .htaccess de siempre) con las extensiones de
# DOCKER_PHP_EXT (con install-php-extensions, que sabe instalarlas tambien en las versiones
# antiguas), el php.ini de produccion y los limites contra PHP2Shell. Hasta la 1.39.1 era la -fpm,
# con PHP-FPM publicado en 127.0.0.1: FastCGI no pide nada, y cualquier programa del Mac (o, por
# host.docker.internal, otro contenedor) podia ejecutar PHP con PHP_VALUE. Ahora no hay FastCGI:
# solo responde la web del contenedor, y solo a quien trae la clave del proyecto (la pone el Apache
# del Mac). PHP corre como www-data dentro del contenedor.
# docker_php_image <version> [--nueva]: con --nueva, se rehace descargando otra vez la de Docker Hub
DOCKER_IMAGE_SCHEMA=2
function docker_php_image() {
    local php=$1 fresh=$2 dir=$DOCKER_DIR/imagenes/php-$1 have
    if [ "$DRY" -eq 0 ] && [ "$fresh" != --nueva ]; then
        have=$(dk image inspect --format '{{index .Config.Labels "nexum.esquema"}}' "nexum-php:$php" 2> /dev/null)
        [ "$have" == "$DOCKER_IMAGE_SCHEMA" ] && return 0
    fi
    mkdir -p -m 700 "$dir" || return 1
    # (con la version de PHP en el nombre del FROM y en las extensiones, nada mas del exterior)
    {
        printf 'FROM php:%s-apache\nLABEL nexum.esquema="%s"\n' "$php" "$DOCKER_IMAGE_SCHEMA"
        cat << 'EOF'
COPY --from=mlocati/php-extension-installer:2 /usr/bin/install-php-extensions /usr/local/bin/
EOF
        printf 'RUN install-php-extensions %s\n' "$DOCKER_PHP_EXT"
        cat << 'EOF'
COPY nexum-web.conf /etc/apache2/sites-available/000-default.conf
COPY nexum.ini /usr/local/etc/php/conf.d/zz-nexum.ini
RUN a2enmod rewrite headers \
 && cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
 && printf 'ServerTokens Prod\nServerSignature Off\nTraceEnable Off\n' > /etc/apache2/conf-available/zz-nexum.conf \
 && a2enconf zz-nexum
# Sin la clave del proyecto no arranca (la web quedaria abierta a cualquier programa del Mac)
CMD ["sh", "-c", "[ ${#NEXUM_KEY} -ge 20 ] || { echo 'Falta la clave del proyecto (NEXUM_KEY): no se arranca' >&2; exit 1; }; exec apache2-foreground"]
EOF
    } > "$dir/Dockerfile" || return 1
    {
        cat << 'EOF'
# Web del proyecto (Nexum Dev Stack). Solo responde al Apache del Mac, que pone la clave del
# proyecto (X-Nexum-Key) y su dominio: cualquier otro programa del Mac, u otro contenedor por
# host.docker.internal, recibe un 403. NEXUM_KEY, NEXUM_DOMAIN y NEXUM_ROOT van en el entorno
<VirtualHost *:80>
    ServerName ${NEXUM_DOMAIN}
    DocumentRoot "${NEXUM_ROOT}"
    <Directory "${NEXUM_ROOT}">
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    RewriteEngine On
    RewriteCond "%{HTTP:X-Nexum-Key}" "!=${NEXUM_KEY}"
    RewriteRule "^" "-" [F]
    RewriteCond "%{HTTP_HOST}" "!=${NEXUM_DOMAIN}" [NC]
    RewriteRule "^" "-" [F]
    # (PHP no la ve)
    RequestHeader unset X-Nexum-Key
    LimitRequestBody 67108864
    ErrorLog /proc/self/fd/2
    CustomLog /proc/self/fd/1 combined
</VirtualHost>
# Lo que el Apache del Mac no sirve de los proyectos (.env, .git, copias de BBDD...): la web va
# entera al contenedor, asi que las mismas reglas van aqui
EOF
        docker_web_rules
    } > "$dir/nexum-web.conf" || return 1
    {
        printf '; Nexum Dev Stack: como en las versiones XAMPP-X, y contra PHP2Shell (CVE-2026-109618/109619)\n'
        printf 'memory_limit = 512M\nmax_execution_time = 300\ndisplay_errors = Off\nlog_errors = On\n'
        printf '%s' "$PHP_SECURITY_INI" | grep -v '^;'
        if [ "${php%%.*}" -gt 8 ] || { [ "${php%%.*}" -eq 8 ] && [ "${php#*.}" -ge 5 ]; }; then
            printf '%s' "$PHP_SECURITY_INI_85"
        fi
    } > "$dir/nexum.ini" || return 1
    echo "Preparando la imagen de PHP $php (la primera vez tarda unos minutos)..."
    if [ "$fresh" == --nueva ]; then
        run dk build --pull --no-cache -t "nexum-php:$php" "$dir"
    else
        run dk build -t "nexum-php:$php" "$dir"
    fi
}

# Reglas de UNKNOWN_HOST_VHOST que no sirven ficheros de los proyectos (DirectoryMatch y FilesMatch):
# las mismas en el Apache del contenedor
function docker_web_rules() {
    awk '/^<DirectoryMatch / { p = 1 } p { print } /^<\/FilesMatch>/ { if (p) exit }' <<< "$UNKNOWN_HOST_VHOST"
}

# Configuracion del proyecto para el contenedor: copia de su wp-config.php (o parameters.php /
# settings.inc.php) con la BBDD del contenedor (en el servidor db o, con el Apache de Docker, en su
# MariaDB comun) y, en WordPress, su dominio. Imprime la ruta relativa del fichero dentro del proyecto
# (la que se sustituye en el contenedor), nada si no tiene
function docker_project_config() {
    local folder=$1 dir=$2 domain=$3 db=$4 user=$5 pass=$6 host=${7:-db} rel
    for rel in wp-config.php app/config/parameters.php config/settings.inc.php; do
        [ -f "$HTDOCS_DIR/$folder/$rel" ] && [ ! -L "$HTDOCS_DIR/$folder/$rel" ] && break
        rel=""
    done
    [ -z "$rel" ] && return 0
    python3 -I - "$HTDOCS_DIR/$folder/$rel" "$dir/config.php" "$rel" "$domain" "$db" "$user" "$pass" "$host" << 'EOF' || return 1
import os, re, sys
src, dst, rel, domain, db, user, pw, host = sys.argv[1:9]
with open(src, encoding="utf-8", errors="surrogateescape", newline="") as f:
    text = f.read(2000000)
def lit(v):
    return "'" + v.replace("\\", "\\\\").replace("'", "\\'") + "'"
if rel == "wp-config.php":
    for name, val in (("DB_NAME", db), ("DB_USER", user), ("DB_PASSWORD", pw), ("DB_HOST", host)):
        # (en cualquier sitio de la linea, salvo detras de un comentario // o #)
        text, n = re.subn(r"""(?m)^((?:(?!//|#)[^\n])*?\bdefine\(\s*['"]%s['"]\s*,\s*)(?:'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")""" % name,
                          lambda m: m.group(1) + lit(val), text, count=1)
        if not n:
            text = re.sub(r"^<\?php", lambda m: "<?php\ndefine(%s, %s);" % (lit(name), lit(val)), text, count=1)
    # (el dominio del contenedor, sin tocar la BBDD; detras de un proxy con https)
    extra = ("\nif (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https' || ($_SERVER['HTTPS'] ?? '') === 'on') { $_SERVER['HTTPS'] = 'on'; }\n"
             "define('WP_HOME', 'https://%s');\ndefine('WP_SITEURL', 'https://%s');\n" % (domain, domain))
    # Las direcciones de la web en local que lleva el contenido (las imagenes y enlaces que se guardaron
    # trabajando con LAMPP: https://web.local/wp-content/...): en lo que devuelve, las del contenedor. Si
    # no, se piden a LAMPP (sin el en marcha, o con otro proyecto en web.local, no salen). La BBDD no se
    # toca. Tambien escapadas (JSON, Elementor) y codificadas
    hosts = [h for h in os.environ.get("LVM_DOMINIOS_LOCALES", "").split() if re.fullmatch(r"[A-Za-z0-9.-]+(:[0-9]+)?", h)]
    if hosts:
        pairs = []
        for h in hosts:
            for scheme in ("https://", "http://"):
                pairs.append((scheme + h, "https://" + domain))
                pairs.append((scheme.replace("/", "\\/") + h, "https:\\/\\/" + domain))
                pairs.append((scheme.replace(":", "%3A").replace("/", "%2F") + h, "https%3A%2F%2F" + domain))
        extra += ("if (PHP_SAPI !== 'cli') { ob_start(function ($b) { return str_replace(%s, %s, $b); }); }\n"
                  % ("array(" + ", ".join(lit(a) for a, _ in pairs) + ")", "array(" + ", ".join(lit(b) for _, b in pairs) + ")"))
    text = re.sub(r"(?m)^[ \t]*define\(\s*['\"](WP_HOME|WP_SITEURL)['\"].*$", "", text)
    text = re.sub(r"^<\?php", lambda m: "<?php" + extra, text, count=1)
elif rel == "app/config/parameters.php":
    for key, val in (("database_host", host), ("database_port", ""), ("database_name", db),
                     ("database_user", user), ("database_password", pw)):
        text = re.sub(r"""(['"]%s['"]\s*=>\s*)(?:'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"|NULL|null|\d+)""" % key,
                      lambda m: m.group(1) + lit(val), text, count=1)
else:
    for name, val in (("_DB_SERVER_", host), ("_DB_NAME_", db), ("_DB_USER_", user), ("_DB_PASSWD_", pw)):
        text = re.sub(r"""(define\(\s*['"]%s['"]\s*,\s*)(?:'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")""" % name,
                      lambda m: m.group(1) + lit(val), text, count=1)
fd = os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
with os.fdopen(fd, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
    f.write(text)
EOF
    echo "$rel"
}

# Bloque del vhost de un proyecto en Docker (http y https) para los vhosts compartidos: la web entera
# va a la del contenedor (http://127.0.0.1:<PUERTO_WEB>), con su dominio y la clave del proyecto, que
# va en un fichero aparte de root y solo para root (los vhosts los puede leer cualquiera)
function docker_vhost_block() {
    local slug=$1 folder=$2 domain=$3 web=$4 crt=$5 key=$6 admin=$(server_admin) port
    printf '\n# nexum-docker %s: la web va en Docker (no se edita a mano: lo quita Docker, Borrar)\n' "$slug"
    for port in "$PORT_HTTP" "$PORT_HTTPS"; do
        printf '<VirtualHost *:%s>\n    ServerAdmin %s\n    DocumentRoot "%s/xamppfiles/htdocs/%s"\n    ServerName %s\n' \
            "$port" "$admin" "$LINK" "$folder" "$domain"
        [ "$port" == "$PORT_HTTPS" ] && printf '    SSLEngine on\n    SSLCertificateFile "%s"\n    SSLCertificateKeyFile "%s"\n' "$crt" "$key"
        printf '    ProxyPreserveHost On\n    ProxyPass "/" "http://127.0.0.1:%s/"\n    ProxyPassReverse "/" "http://127.0.0.1:%s/"\n' "$web" "$web"
        printf '    RequestHeader set X-Forwarded-Proto "%s"\n' "$([ "$port" == "$PORT_HTTPS" ] && echo https || echo http)"
        printf '    Include "%s/%s.conf"\n' "$DOCKER_KEYS_DIR" "$slug"
        printf '    ErrorLog "logs/%s-error_log"\n</VirtualHost>\n' "$domain"
    done
    printf '# /nexum-docker %s\n' "$slug"
}

# Clave de un proyecto en Docker para el Apache del Mac: DOCKER_KEYS_DIR/<nombre>.conf, de root y solo
# para root (Apache lee su configuracion como root). La clave va por la entrada, no en la orden (ps)
function docker_write_key() {
    local slug=$1 secret=$2
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] clave de $slug en $DOCKER_KEYS_DIR (de root, 600)"; return 0; }
    $SUDO install -d -o 0 -g 0 -m 700 "$DOCKER_KEYS_DIR" 2> /dev/null || $SUDO mkdir -p -m 700 "$DOCKER_KEYS_DIR" || return 1
    printf '# Clave de %s en Docker (Nexum Dev Stack): solo para el Apache del Mac\nRequestHeader set X-Nexum-Key "%s"\n' "$slug" "$secret" \
        | $SUDO sh -c 'umask 077; cat > "$1.nuevo" && mv -f "$1.nuevo" "$1"' sh "$DOCKER_KEYS_DIR/$slug.conf"
}

function docker_remove_key() {
    [ -e "$DOCKER_KEYS_DIR/$1.conf" ] || $SUDO test -e "$DOCKER_KEYS_DIR/$1.conf" 2> /dev/null || return 0
    run $SUDO rm -f "$DOCKER_KEYS_DIR/$1.conf"
}

# compose.yaml de un proyecto, con lo de su proyecto.conf: la web (Apache con PHP) en
# 127.0.0.1:<PUERTO_WEB>, su MariaDB y su phpMyAdmin (que pide usuario y contraseña: root y la de
# DB_ROOT_PASS, que la ventana enseña). Las claves van en .env, solo tuyo
function docker_compose_file() {
    local slug=$1 folder php maria domain db pma web rel
    folder=$(docker_conf "$slug" CARPETA) php=$(docker_conf "$slug" PHP) maria=$(docker_conf "$slug" MARIADB)
    domain=$(docker_conf "$slug" DOMINIO) db=$(docker_conf "$slug" BBDD) pma=$(docker_conf "$slug" PUERTO_PMA)
    web=$(docker_conf "$slug" PUERTO_WEB) rel=$(docker_conf "$slug" CONFIG)
    [ -n "$folder" ] && [ -n "$php" ] && [ -n "$maria" ] && [ -n "$domain" ] && [ -n "$db" ] && [ -n "$pma" ] && [ -n "$web" ] || return 1
    printf 'name: nexum-%s\nservices:\n' "$slug"
    printf '  php:\n    image: nexum-php:%s\n    restart: "no"\n    environment:\n' "$php"
    printf '      NEXUM_KEY: ${WEB_KEY}\n      NEXUM_DOMAIN: "%s"\n      NEXUM_ROOT: "%s/xamppfiles/htdocs/%s"\n' "$domain" "$LINK" "$folder"
    printf '    ports:\n      - "127.0.0.1:%s:80"\n    volumes:\n' "$web"
    printf '      - "%s:%s/xamppfiles/htdocs/%s"\n' "$HTDOCS_DIR/$folder" "$LINK" "$folder"
    [ -n "$rel" ] && printf '      - "./config.php:%s/xamppfiles/htdocs/%s/%s:ro"\n' "$LINK" "$folder" "$rel"
    # PrestaShop 1.7 y posteriores guardan su configuracion (con la BBDD del contenedor: db y su
    # usuario) en var/cache: aparte, en un volumen del contenedor, no en la carpeta que comparte con
    # XAMPP-X (que la leeria y no encontraria la BBDD)
    [ "$rel" == app/config/parameters.php ] && printf '      - "cache:%s/xamppfiles/htdocs/%s/var/cache"\n' "$LINK" "$folder"
    printf '    depends_on: [db]\n'
    printf '  db:\n    image: mariadb:%s\n    restart: "no"\n    environment:\n' "$maria"
    printf '      MARIADB_ROOT_PASSWORD: ${DB_ROOT_PASS}\n      MARIADB_DATABASE: %s\n      MARIADB_USER: nexum\n      MARIADB_PASSWORD: ${DB_PASS}\n' "$db"
    printf '    volumes:\n      - "db:/var/lib/mysql"\n'
    printf '  pma:\n    image: %s\n    restart: "no"\n    environment:\n      PMA_HOST: db\n      UPLOAD_LIMIT: 64M\n' "$DOCKER_PMA_IMAGE"
    printf '    ports:\n      - "127.0.0.1:%s:80"\n    depends_on: [db]\n' "$pma"
    printf 'volumes:\n  db: {}\n'
    [ "$rel" == app/config/parameters.php ] && printf '  cache: {}\n'
    return 0
}

# Una orden SQL en la MariaDB del contenedor como root: la contraseña la tiene el contenedor en su
# entorno (MARIADB_ROOT_PASSWORD) y no va en la orden (ps). docker_sql <carpeta> <sh -c ...> [args]
function docker_sql() {
    local dir=$1 script=$2
    shift 2
    dk compose --project-directory "$dir" -f "$dir/compose.yaml" exec -T db \
        sh -c 'MYSQL_PWD=$MARIADB_ROOT_PASSWORD; export MYSQL_PWD; '"$script" "$@"
}

# Cambia los vhosts compartidos por los de la copia, con la comprobacion de siempre (edit_vhosts)
function docker_apply_vhosts() {
    local copy=$1
    edit_vhosts --aplicar "$copy"
}

# docker-crear <carpeta> <php> <mariadb> [--bd <base> --desde <version XAMPP-X>] [--dominio <dominio>]
#   [--nombre <nombre>]  (otro nombre: la misma carpeta en Docker con otra version de PHP)
function docker_create() {
    local folder=${1%/} php=$2 maria=$3 db="" from="" domain="" name="" slug dir rel pma_port web_port
    shift 3 2> /dev/null
    while [ $# -gt 0 ]; do
        case $1 in
            --bd|--desde|--dominio|--nombre)
                [ -n "$2" ] || { echo "Falta el valor de $1"; return 1; }
                case $1 in --bd) db=$2 ;; --desde) from=$2 ;; --dominio) domain=$2 ;; --nombre) name=$2 ;; esac
                shift 2 ;;
            *) echo "Opcion desconocida: $1"; return 1 ;;
        esac
    done
    if [ -z "$folder" ] || [ -z "$php" ] || [ -z "$maria" ]; then
        echo "Uso: lvm-instalador docker-crear <carpeta> <php> <mariadb> [--bd <base> --desde <version>] [--dominio <dominio>] [--nombre <nombre>]"
        return 1
    fi
    valid_project "$folder" || return 1
    [[ " $DOCKER_PHP_VERSIONS " == *" $php "* ]] || { echo "PHP $php no se ofrece en Docker ($DOCKER_PHP_VERSIONS)"; return 1; }
    [[ " $DOCKER_MARIADB_VERSIONS " == *" $maria "* ]] || { echo "MariaDB $maria no se ofrece en Docker ($DOCKER_MARIADB_VERSIONS)"; return 1; }
    if [ -n "$db" ]; then
        db_valid_name "$db" || return 1
        [ -n "$from" ] && valid_version_name "$from" && [ -d "$BASE_DIR/XAMPP-$from" ] \
            || { echo "Con --bd hay que decir de que version XAMPP-X se copia (--desde)"; return 1; }
    fi
    if [ -n "$name" ]; then
        slug=$name
        docker_valid_slug "$slug" || { echo "Nombre no valido para Docker: $slug (minusculas, numeros y guiones)"; return 1; }
    else
        slug=$(docker_slug "$folder") && docker_valid_slug "$slug" || { echo "No se puede sacar un nombre corto de $folder"; return 1; }
    fi
    domain=${domain:-$slug.docker.local}
    domain=$(tr 'A-Z' 'a-z' <<< "$domain")
    valid_domain "$domain" || { echo "Dominio no valido: $domain"; return 1; }
    [[ "$domain" == *.local ]] || { echo "El dominio de un proyecto en Docker tiene que acabar en .local ($domain)"; return 1; }
    dir=$DOCKER_DIR/$slug
    if [ -e "$dir" ]; then
        echo "Ya hay un proyecto en Docker con el nombre $slug ($dir): borralo antes o usa otra carpeta"
        return 1
    fi
    if vhosts_info | awk -F'|' -v d="$domain" '$3 == d || (" " $4 " ") ~ (" " d " ") { f = 1 } END { exit !f }'; then
        echo "Ya hay un vhost con el dominio $domain"
        return 1
    fi
    if [ "$DRY" -eq 0 ] && ! docker_ready; then
        echo "Docker Desktop no esta en marcha: abrelo (o instalalo) desde la pestaña Docker."
        return 1
    fi
    # Puertos de 127.0.0.1 para su phpMyAdmin y su web: los primeros libres
    pma_port=$(docker_free_port "$DOCKER_PMA_PORT" PUERTO_PMA)
    # (y los PUERTO_FPM de los proyectos de antes que aun no han pasado a la web con clave)
    web_port=$(docker_free_port "$DOCKER_WEB_PORT" 'PUERTO_WEB|PUERTO_FPM')
    local dbname=${db:-$(tr '-' '_' <<< "$slug")} user=nexum
    local root_pass app_pass web_key
    root_pass=$(head -c 18 /dev/urandom | base64 | tr -d '/+=\n')
    app_pass=$(head -c 18 /dev/urandom | base64 | tr -d '/+=\n')
    web_key=$(head -c 30 /dev/urandom | base64 | tr -d '/+=\n')

    echo "Proyecto en Docker: $folder con PHP $php y MariaDB $maria (https://$domain)"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $dir con compose.yaml, la imagen nexum-php:$php, vhost de $domain y su linea en $HOSTS_FILE"
        [ -n "$db" ] && echo "  [simulacion] copia de $db de XAMPP-$from a la MariaDB del contenedor"
        return 0
    fi
    mkdir -p -m 700 "$DOCKER_DIR" "$dir" || return 1
    chmod 700 "$DOCKER_DIR" "$dir"
    # (las contraseñas, solo en ficheros solo tuyos)
    ( umask 077
      printf 'DB_ROOT_PASS=%s\nDB_PASS=%s\nWEB_KEY=%s\n' "$root_pass" "$app_pass" "$web_key" > "$dir/.env"
      printf 'CARPETA=%s\nPHP=%s\nMARIADB=%s\nDOMINIO=%s\nBBDD=%s\nPUERTO_PMA=%s\nPUERTO_WEB=%s\nESQUEMA=%s\n' \
          "$folder" "$php" "$maria" "$domain" "$dbname" "$pma_port" "$web_port" "$DOCKER_IMAGE_SCHEMA" > "$dir/proyecto.conf" ) || return 1
    rel=$(docker_project_config "$folder" "$dir" "$domain" "$dbname" "$user" "$app_pass") || return 1
    [ -n "$rel" ] && echo "CONFIG=$rel" >> "$dir/proyecto.conf"
    docker_compose_file "$slug" > "$dir/compose.yaml" || return 1

    task_plan "Creando $folder en Docker" "Imagen de PHP $php" "Contenedores" "BBDD $dbname" "Vhost de $domain"
    task_step
    echo "1/4 Imagen de PHP $php"
    docker_php_image "$php" || { echo "No se ha podido preparar la imagen de PHP $php"; return 1; }
    task_step
    echo "2/4 Contenedores"
    if ! dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d; then
        # (Docker Desktop solo comparte con los contenedores las carpetas de su lista: /Applications no esta)
        echo "No arrancan los contenedores. Si Docker dice «mounts denied», añade $HTDOCS_DIR en Docker"
        echo "Desktop, Settings > Resources > File sharing, pulsa Apply y vuelve a probar (Docker, Arrancar)."
        return 1
    fi
    task_step
    echo "3/4 BBDD $dbname"
    local i
    for i in $(seq 60); do
        docker_sql "$dir" 'exec $(command -v mariadb || command -v mysql) -uroot -e "SELECT 1"' < /dev/null > /dev/null 2>&1 && break
        sleep 1
    done
    if [ -n "$db" ]; then
        local tmp
        mkdir -p -m 700 "$LOG_DIR" || return 1
        tmp=$(mktemp "$LOG_DIR/docker-$slug-XXXXXX") && mv -f "$tmp" "$tmp.sql.gz" && tmp=$tmp.sql.gz || return 1
        echo "Copiando $db de XAMPP-$from..."
        if ! export_database "$db" "$tmp" "$from"; then
            rm -f "$tmp"
            echo "No se ha podido descargar $db de XAMPP-$from: el proyecto queda con la BBDD vacia."
        else
            db_temp_stop
            gzip -dc "$tmp" | docker_sql "$dir" 'exec $(command -v mariadb || command -v mysql) -uroot --binary-mode "$0"' "$dbname" \
                || echo "Aviso: la carga de $db ha dado errores (mira el registro)."
            rm -f "$tmp"
            docker_ps_domain "$dir" "$dbname" "$domain"
            # (la copia va sin el administrador de pruebas: se le pone el de este Mac para el Panel)
            local admin
            admin=$(docker_test_admin "$slug")
            grep -v '^A|' <<< "$admin" | grep .
            grep -q '^A|' <<< "$admin" && echo "Administrador de pruebas del panel: $TEST_ADMIN_USER, contraseña $TEST_ADMIN_PASS"
        fi
    fi
    task_step
    echo "4/4 Vhost de $domain"
    local crt=$OWN_SSL_DIR/$domain-selfsigned.crt key=$OWN_SSL_DIR/$domain-selfsigned.key copy
    [ -f "$crt" ] || make_selfsigned "$domain" "" "$crt" "$key" || return 1
    # (la clave, antes que el vhost: Apache la lee al comprobarlo)
    docker_write_key "$slug" "$web_key" || { echo "No se ha podido guardar la clave de $slug para Apache"; return 1; }
    copy=$(mktemp "$LOG_DIR/vhosts-docker-XXXXXX") || return 1
    { cat "$(realpath_f "$ACTIVE_VHOSTS")"; docker_vhost_block "$slug" "$folder" "$domain" "$web_port" "$crt" "$key"; } > "$copy"
    docker_apply_vhosts "$copy" || { rm -f "$copy"; echo "No se ha podido añadir el vhost de $domain (los contenedores quedan creados)"; return 1; }
    rm -f "$copy"
    if ! grep -qE "^[^#]*[[:space:]]${domain//./\\.}([[:space:]]|$)" "$HOSTS_FILE" 2> /dev/null; then
        copy=$(mktemp "$LOG_DIR/hosts-docker-XXXXXX") || return 1
        { cat "$HOSTS_FILE"; printf '127.0.0.1 %s\n' "$domain"; } > "$copy"
        edit_hosts --aplicar "$copy"
        rm -f "$copy"
    fi
    browser_trust "$domain" || true
    echo "Proyecto en Docker listo: https://$domain (PHP $php). phpMyAdmin: http://127.0.0.1:$pma_port/"
    echo "(phpMyAdmin pide usuario y contraseña: root y la que enseña la ventana, Docker, o lvm-instalador docker-clave $slug)"
}

# Proyectos en Docker de antes de la 1.39.2: PHP-FPM publicado en 127.0.0.1:<PUERTO_FPM>, sin clave
# (FastCGI no pide nada: cualquier programa del Mac podia ejecutar PHP con PHP_VALUE). Pasan a la
# web del contenedor (Apache con PHP) en ese mismo puerto, con su clave en el vhost. Sus BBDD (el
# volumen db), su configuracion y su phpMyAdmin se quedan; lo de antes se guarda en
# <proyecto>/antes-esquema-2 y, si algo falla, se deja como estaba. Sus contenedores de PHP y de
# phpMyAdmin se rehacen (si estaba en marcha, sigue en marcha). docker_migrate <nombre>
function docker_migrate() {
    local slug=$1 dir=$DOCKER_DIR/$1 old state key rel port php domain folder copy block crt sslkey
    docker_valid_slug "$slug" && [ -f "$dir/proyecto.conf" ] || { echo "No hay ningun proyecto en Docker con el nombre $slug"; return 1; }
    [ "$(docker_conf "$slug" ESQUEMA)" == "$DOCKER_IMAGE_SCHEMA" ] && return 0
    php=$(docker_conf "$slug" PHP) domain=$(docker_conf "$slug" DOMINIO) folder=$(docker_conf "$slug" CARPETA)
    echo "$slug: su PHP-FPM deja de estar abierto en 127.0.0.1; la web va en el contenedor, con clave"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] imagen nexum-php:$php nueva, compose.yaml con la web en 127.0.0.1 y su clave, vhost con ProxyPass"
        return 0
    fi
    docker_ready || { echo "Docker Desktop no esta en marcha: abrelo y vuelve a probar"; return 1; }
    old=$dir/antes-esquema-2
    mkdir -p -m 700 "$old" && cp -p "$dir/compose.yaml" "$dir/proyecto.conf" "$dir/.env" "$old/" || return 1
    docker_migrate_undo() {
        cp -p "$old/compose.yaml" "$old/proyecto.conf" "$old/.env" "$dir/"
        echo "$slug se queda como estaba (lo de antes esta en $old)"
    }
    state=$(docker_state "$slug")
    rel=$(sed -nE 's#^      - "\./config\.php:.*/(wp-config\.php|app/config/parameters\.php|config/settings\.inc\.php):ro"$#\1#p' "$old/compose.yaml" | head -1)
    port=$(docker_conf "$slug" PUERTO_FPM)
    [[ "$port" =~ ^[0-9]+$ ]] || port=$(docker_free_port "$DOCKER_WEB_PORT" PUERTO_WEB)
    key=$(head -c 30 /dev/urandom | base64 | tr -d '/+=\n')
    if ! ( umask 077
           { grep -v '^WEB_KEY=' "$old/.env"; echo "WEB_KEY=$key"; } > "$dir/.env"
           { grep -vE '^(PUERTO_FPM|PUERTO_WEB|ESQUEMA|CONFIG)=' "$old/proyecto.conf"; echo "PUERTO_WEB=$port"
             [ -n "$rel" ] && echo "CONFIG=$rel"; } > "$dir/proyecto.conf" ) \
        || ! docker_compose_file "$slug" > "$dir/compose.yaml"; then
        docker_migrate_undo
        return 1
    fi
    if ! docker_php_image "$php"; then
        echo "No se ha podido preparar la imagen nueva de PHP $php"
        docker_migrate_undo
        return 1
    fi
    if ! docker_write_key "$slug" "$key"; then
        echo "No se ha podido guardar la clave de $slug para Apache"
        docker_migrate_undo
        return 1
    fi
    # El vhost: el bloque de este proyecto, cambiado por el nuevo (los demas, como estaban)
    crt=$OWN_SSL_DIR/$domain-selfsigned.crt sslkey=$OWN_SSL_DIR/$domain-selfsigned.key
    block=$(mktemp "$LOG_DIR/vhost-docker-XXXXXX") && copy=$(mktemp "$LOG_DIR/vhosts-docker-XXXXXX") || { docker_migrate_undo; return 1; }
    docker_vhost_block "$slug" "$folder" "$domain" "$port" "$crt" "$sslkey" | tail -n +2 > "$block"
    if grep -q "^# nexum-docker $slug:" "$(realpath_f "$ACTIVE_VHOSTS")" 2> /dev/null; then
        awk -v s="$slug" -v b="$block" '$0 ~ ("^# nexum-docker " s ":") { skip = 1; while ((getline l < b) > 0) print l; next }
            skip && $0 == ("# /nexum-docker " s) { skip = 0; next } !skip { print }' "$(realpath_f "$ACTIVE_VHOSTS")" > "$copy"
    else
        { cat "$(realpath_f "$ACTIVE_VHOSTS")"; echo; cat "$block"; } > "$copy"
    fi
    if ! docker_apply_vhosts "$copy"; then
        rm -f "$block" "$copy"
        echo "No se ha podido cambiar el vhost de $domain"
        docker_migrate_undo
        return 1
    fi
    rm -f "$block" "$copy"
    # Los contenedores de PHP y phpMyAdmin de antes, fuera (el de PHP publicaba PHP-FPM); la BBDD sigue
    dk compose --project-directory "$dir" -f "$dir/compose.yaml" rm -s -f php pma > /dev/null 2>&1
    echo "ESQUEMA=$DOCKER_IMAGE_SCHEMA" >> "$dir/proyecto.conf"
    if [ "$state" == marcha ] || [ "$state" == parcial ]; then
        dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d || { echo "No arranca: mira Docker, Registros"; return 1; }
    fi
    echo "$slug listo: https://$domain"
}

# Proyectos en Docker que aun tienen PHP-FPM abierto en 127.0.0.1 (antes de la 1.39.2)
function docker_unmigrated() {
    local p
    for p in $(docker_projects); do
        [ "$(docker_conf "$p" ESQUEMA)" == "$DOCKER_IMAGE_SCHEMA" ] || echo "$p"
    done
}

# docker-migrar <nombre>|--todos
function docker_migrate_command() {
    local p rc=0 list
    if [ "$1" == --todos ]; then
        list=$(docker_unmigrated)
        [ -n "$list" ] || { echo "Todos los proyectos en Docker estan al dia"; return 0; }
        for p in $list; do docker_migrate "$p" || rc=1; done
        return $rc
    fi
    docker_migrate "$1"
}

# docker-imagen <nombre>: rehace la imagen de PHP del proyecto descargando otra vez la oficial (con
# los ultimos parches de su rama: los de seguridad de PHP y de Debian) y rehace su contenedor de PHP
function docker_update_image() {
    local slug=$1 dir=$DOCKER_DIR/$1 php state
    docker_valid_slug "$slug" && [ -f "$dir/proyecto.conf" ] || { echo "No hay ningun proyecto en Docker con el nombre $slug"; return 1; }
    if docker_web_project "$slug"; then
        [ "$DRY" -eq 1 ] && { echo "  [simulacion] dk build --pull --no-cache de nexum-php:$(docker_conf "$slug" PHP | tr ' ' ',')"; return 0; }
        docker_ready || { echo "Docker Desktop no esta en marcha"; return 1; }
        local steps=()
        for php in $(docker_conf "$slug" PHP); do steps+=("Imagen de PHP $php"); done
        steps+=("Volver a crear sus contenedores")
        task_plan "$slug: imágenes de PHP" "${steps[@]}"
        for php in $(docker_conf "$slug" PHP); do
            task_step
            echo "Imagen de PHP $php: se descarga otra vez la oficial (php:$php-apache) y se rehace"
            docker_php_image "$php" --nueva || { echo "No se ha podido rehacer la imagen de PHP $php: sigue la de antes"; return 1; }
        done
        task_step
        dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d --force-recreate $(docker_web_services "$slug") || return 1
        echo "Imagenes de PHP de $slug al dia"
        return 0
    fi
    docker_migrate "$slug" || return 1
    php=$(docker_conf "$slug" PHP)
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] dk build --pull --no-cache -t nexum-php:$php y contenedor de PHP nuevo"; return 0; }
    docker_ready || { echo "Docker Desktop no esta en marcha"; return 1; }
    state=$(docker_state "$slug")
    task_plan "$slug: imagen de PHP $php" "Imagen de PHP $php" "Volver a crear su contenedor"
    task_step
    echo "Imagen de PHP $php: se descarga otra vez la oficial (php:$php-apache) y se rehace"
    docker_php_image "$php" --nueva || { echo "No se ha podido rehacer la imagen: sigue la de antes"; return 1; }
    task_step
    if [ "$state" == marcha ] || [ "$state" == parcial ]; then
        dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d --force-recreate php || return 1
    fi
    echo "$slug con la imagen nueva de PHP $php$([ "$state" == marcha ] || [ "$state" == parcial ] || echo " (al arrancarlo)")"
}

# docker-clave <nombre>: usuario y contraseña de su phpMyAdmin (root del MariaDB del contenedor)
#   K|usuario|contraseña|direccion de phpMyAdmin
function docker_db_password() {
    local slug=$1 f=$DOCKER_DIR/$1/.env pass
    if docker_web_project "$slug"; then
        f=$DOCKER_DIR/mariadb-$(docker_conf "$slug" MARIADB)/.env
        pass=$(awk -F= '$1 == "DB_ROOT_PASS" { sub(/^[^=]*=/, ""); print; exit }' "$f" 2> /dev/null)
        [ -n "$pass" ] || { echo "No se encuentra la contraseña de la MariaDB comun de $slug"; return 1; }
        echo "K|root|$pass|$(docker_web_url pma.docker.local)/"
        return 0
    fi
    docker_valid_slug "$slug" && [ -f "$f" ] && [ ! -L "$f" ] || { echo "No hay ningun proyecto en Docker con el nombre $slug"; return 1; }
    pass=$(awk -F= '$1 == "DB_ROOT_PASS" { sub(/^[^=]*=/, ""); print; exit }' "$f")
    [ -n "$pass" ] || { echo "No se encuentra la contraseña de $slug"; return 1; }
    echo "K|root|$pass|http://127.0.0.1:$(docker_conf "$slug" PUERTO_PMA)/"
}

# Tienda PrestaShop copiada al contenedor: su dominio pasa a ser el del contenedor (la BBDD es una copia)
function docker_ps_domain() {
    local dir=$1 db=$2 domain=$3 prefix
    prefix=$(docker_sql "$dir" 'exec $(command -v mariadb || command -v mysql) -uroot -N -e "SELECT LEFT(table_name, LENGTH(table_name) - 8) FROM information_schema.tables WHERE table_schema = \"$0\" AND table_name LIKE \"%shop\\_url\" LIMIT 1"' "$db" < /dev/null 2> /dev/null | tr -d '\r')
    [[ "$prefix" =~ ^[A-Za-z0-9_]+$ ]] || return 0
    echo "Tienda PrestaShop: su dominio pasa a $domain en la copia del contenedor"
    docker_sql "$dir" 'exec $(command -v mariadb || command -v mysql) -uroot "$0"' "$db" << EOF
UPDATE \`${prefix}shop_url\` SET domain = '$domain', domain_ssl = '$domain';
UPDATE \`${prefix}configuration\` SET value = '$domain' WHERE name IN ('PS_SHOP_DOMAIN', 'PS_SHOP_DOMAIN_SSL');
UPDATE \`${prefix}configuration\` SET value = '1' WHERE name IN ('PS_SSL_ENABLED', 'PS_SSL_ENABLED_EVERYWHERE');
EOF
}

# docker-usuario-pruebas <nombre>: el administrador de pruebas (usuario-pruebas) en la BBDD del
# contenedor del proyecto. La copia que se lleva de XAMPP-X no lo tiene (exportar-bd lo deja fuera) y
# sin el no entra el Panel. Es el mismo test_admin, por el cliente de la MariaDB del contenedor como
# root (docker_sql: la contraseña la toma dentro del contenedor, nunca en una orden). Dice A|wp|... y/o
# A|ps|... como usuario-pruebas; con el proyecto parado, nada (sale con 1)
function docker_test_admin() {
    local slug=$1 dir db folder
    docker_valid_slug "$slug" && [ -f "$DOCKER_DIR/$slug/proyecto.conf" ] || { echo "No hay ningun proyecto en Docker con el nombre $slug"; return 1; }
    dir=$DOCKER_DIR/$slug
    db=$(docker_conf "$slug" BBDD) folder=$(docker_conf "$slug" CARPETA)
    db_valid_name "$db" > /dev/null || { echo "$slug no tiene una BBDD valida en su proyecto.conf"; return 1; }
    if docker_web_project "$slug"; then
        local DB_ROOT_CLIENT=(docker_maria_sql "$(docker_conf "$slug" MARIADB)")
    else
        local DB_ROOT_CLIENT=(docker_sql "$dir" 'exec $(command -v mariadb || command -v mysql) -uroot "$@"' mariadb)
    fi
    test_admin "$db" "$folder"
}

# docker-arrancar|docker-parar|docker-registros|docker-borrar <nombre>
function docker_action() {
    local action=$1 slug=$2 dir
    docker_valid_slug "$slug" && [ -f "$DOCKER_DIR/$slug/proyecto.conf" ] || { echo "No hay ningun proyecto en Docker con el nombre $slug"; return 1; }
    # (los del Apache de Docker, desde la 1.40)
    if docker_web_project "$slug"; then
        docker_web_action "$action" "$slug"
        return
    fi
    dir=$DOCKER_DIR/$slug
    local c=(dk compose --project-directory "$dir" -f "$dir/compose.yaml")
    case $action in
        # (los de antes de la 1.39.2, con PHP-FPM abierto, pasan antes a la web con clave)
        # (y, hasta la 1.39.20, las tiendas PrestaShop 1.7+ tenian su cache en la carpeta compartida con
        # XAMPP-X: su compose.yaml se rehace con la cache en su volumen)
        arrancar)
            docker_migrate "$slug" || return 1
            if [ "$(docker_conf "$slug" CONFIG)" == app/config/parameters.php ] && ! grep -q '/var/cache"$' "$dir/compose.yaml" \
                    && [ "$DRY" -eq 0 ]; then
                docker_compose_file "$slug" > "$dir/compose.yaml.nuevo" && mv -f "$dir/compose.yaml.nuevo" "$dir/compose.yaml"
            fi
            run "${c[@]}" up -d ;;
        parar) run "${c[@]}" stop ;;
        registros) "${c[@]}" logs --no-color --tail 200 ;;
        borrar)
            local domain=$(docker_conf "$slug" DOMINIO) copy
            echo "Se borran los contenedores de $slug y su BBDD (la copia del contenedor; la de XAMPP-X no se toca)"
            run "${c[@]}" down -v || return 1
            if grep -q "^# nexum-docker $slug:" "$(realpath_f "$ACTIVE_VHOSTS")" 2> /dev/null; then
                copy=$(mktemp "$LOG_DIR/vhosts-docker-XXXXXX") || return 1
                awk -v s="$slug" '$0 ~ ("^# nexum-docker " s ":") { skip = 1 } !skip { print } $0 == ("# /nexum-docker " s) { skip = 0 }' \
                    "$(realpath_f "$ACTIVE_VHOSTS")" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' > "$copy"
                docker_apply_vhosts "$copy" || { rm -f "$copy"; return 1; }
                rm -f "$copy"
            fi
            docker_remove_key "$slug"
            if [ -n "$domain" ] && valid_domain "$domain" && grep -qE "^127\.0\.0\.1[[:space:]]+${domain//./\\.}$" "$HOSTS_FILE"; then
                copy=$(mktemp "$LOG_DIR/hosts-docker-XXXXXX") || return 1
                grep -vE "^127\.0\.0\.1[[:space:]]+${domain//./\\.}$" "$HOSTS_FILE" > "$copy"
                edit_hosts --aplicar "$copy"
                rm -f "$copy"
            fi
            [ "$DRY" -eq 1 ] || rm -rf "$dir"
            echo "Proyecto en Docker $slug borrado"
            ;;
        *) echo "Uso: lvm-instalador docker-arrancar|docker-parar|docker-registros|docker-borrar <nombre>"; return 1 ;;
    esac
}

