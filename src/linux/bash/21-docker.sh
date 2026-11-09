# ===========================================================================
# Docker (sin root): proyectos con cualquier version de PHP en contenedores
# ===========================================================================
# Cada proyecto en Docker lleva su PHP-FPM, su MariaDB (con una copia de su BBDD) y su phpMyAdmin en
# contenedores de Docker sin root: corren con tu usuario, asi que ni un proyecto ni Docker pueden
# hacerse administradores del equipo. La web la sigue sirviendo el Apache de la version LAMPP activa,
# por su dominio (<carpeta>.docker.local, http y https con su certificado), con los .htaccess de
# siempre: los .php los pasa al PHP-FPM del contenedor por un socket de una carpeta solo tuya. Dentro
# del contenedor el proyecto esta en la misma ruta que ve Apache (/opt/lampp/htdocs/<carpeta>), y su
# wp-config.php (o parameters.php / settings.inc.php) se sustituye por uno con la BBDD del contenedor:
# el del proyecto no se toca, y la carpeta se puede seguir usando con LAMPP a la vez.
# (LVM_DOCKER, LVM_DOCKER_DIR y LVM_DOCKER_HOST solo para pruebas)
DOCKER_DIR=${LVM_DOCKER_DIR:-$HOME/.lvm-instalador/docker}
DOCKER_BIN=${LVM_DOCKER:-/usr/bin/docker}
# Versiones que se ofrecen: imagenes oficiales php:<version>-fpm y mariadb:<version> de Docker Hub
DOCKER_PHP_VERSIONS="8.5 8.4 8.3 8.2 8.1 8.0 7.4 7.3 7.2 7.1 7.0 5.6"
DOCKER_MARIADB_VERSIONS="11.8 11.4 10.11 10.6 10.5 10.4"
DOCKER_PMA_IMAGE="phpmyadmin:5.2"
# Extensiones de PHP de las imagenes (las que piden WordPress y PrestaShop)
DOCKER_PHP_EXT="bcmath exif gd intl mysqli opcache pdo_mysql soap zip"
# Paquetes de Ubuntu para Docker sin root (el demonio del sistema, con root, se deja apagado)
DOCKER_PACKAGES="docker.io docker-compose-v2 rootlesskit uidmap slirp4netns dbus-user-session"
# Puertos de 127.0.0.1 para el phpMyAdmin de cada proyecto (uno por proyecto, desde este)
DOCKER_PMA_PORT=28080

# Docker sin root siempre por su socket: nunca el del demonio del sistema
function docker_sock() {
    echo "${LVM_DOCKER_HOST:-unix://${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/docker.sock}"
}

# Configuracion del cliente de Docker: una carpeta del gestor (solo tuya) y no ~/.docker, donde
# cualquier programa tuyo puede dejar un complemento (cli-plugins/docker-*) o un ayudante de claves
# (credsStore) que docker ejecutaria. Cada vez sin complementos propios y con un config.json vacio:
# docker compose y buildx son los del sistema (/usr/libexec/docker/cli-plugins)
DOCKER_CONFIG_DIR="$LOG_DIR/docker-config"
function docker_config_dir() {
    local cfg=$DOCKER_CONFIG_DIR
    if [ -L "$cfg" ] || { [ -e "$cfg" ] && [ ! -O "$cfg" ]; }; then
        echo "$cfg no es una carpeta tuya: no se usa Docker" >&2
        return 1
    fi
    mkdir -p -m 700 "$cfg" && chmod 700 "$cfg" || return 1
    [ -e "$cfg/cli-plugins" ] && rm -rf "$cfg/cli-plugins"
    [ "$(cat "$cfg/config.json" 2> /dev/null)" == "{}" ] || { rm -f "$cfg/config.json"; echo "{}" > "$cfg/config.json"; }
    chmod 600 "$cfg/config.json"
    echo "$cfg"
}

# docker como git (no_tty): en su propia sesion, sin la terminal de la tarea (sus complementos no
# pueden usar el permiso de sudo recordado ni leer lo que se escribe en ella). Su salida y sus
# errores pasan por tuberias; la entrada, solo si no es la terminal (una carga de BBDD por tuberia)
function dk() {
    local cfg
    cfg=$(docker_config_dir) || return 1
    ( [ -t 0 ] && exec < /dev/null
      set -o pipefail
      DOCKER_HOST=$(docker_sock) DOCKER_CONFIG=$cfg /usr/bin/python3 -I -c "$NO_TTY_PY" "$DOCKER_BIN" "$@" \
          2> >(cat >&2) | cat )
}

# ¿Responde Docker sin root? (0 si si)
function docker_ready() {
    [ -x "$DOCKER_BIN" ] || return 1
    local info
    info=$(dk info --format '{{json .SecurityOptions}}' 2> /dev/null) || return 1
    [[ "$info" == *rootless* ]]
}

# Nombre corto de un proyecto: el de su carpeta en minusculas, solo letras, numeros y - (va en el
# nombre de los contenedores y en el dominio)
function docker_slug() {
    local s
    s=$(tr 'A-Z' 'a-z' <<< "$1" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40 | sed -E 's/-+$//')
    [ -n "$s" ] && echo "$s"
}

# Carpeta del socket de PHP-FPM de un proyecto: en /run/user/<tu uid> (solo tuya, en memoria y corta:
# la ruta de un socket no puede pasar de 107 caracteres)
function docker_run_dir() {
    echo "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/nexum/$1"
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

# Proyectos en Docker (nombres cortos validos con su proyecto.conf)
function docker_projects() {
    local d
    [ -d "$DOCKER_DIR" ] || return 0
    for d in "$DOCKER_DIR"/*/; do
        d=$(basename "$d")
        docker_valid_slug "$d" && [ -f "$DOCKER_DIR/$d/proyecto.conf" ] && echo "$d"
    done
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
#   S|instalado (1/0)|Docker sin root responde (1/0)|version|LAMPP activa en marcha (1/0)|Docker o
#     containerd del sistema (con root) en marcha (1/0)
#   V|versiones de PHP|versiones de MariaDB
#   P|nombre|carpeta|php|mariadb|dominio|estado|bbdd|puerto de phpMyAdmin (de antes; en los del Apache de
#     Docker: web)|modo (web o nada)|version elegida (tienda)|tipo (wp, ps u otro)|versiones de PHP (espacios)
#   W|direccion|http|https|estado del Apache de Docker (marcha, parado, nuevo)|puertos permitidos (1/0)
#   C|contenedor|imagen|estado (running, exited...)|estado en texto|puertos|proyecto de compose
#     (todos los contenedores de tu Docker, para la consola de la pestaña)
#   I|imagen:etiqueta|tamaño|creada  y  O|volumen|driver   (imagenes y volumenes de tu Docker)
function gui_docker() {
    local installed=0 ready=0 version="" p
    [ -x "$DOCKER_BIN" ] && installed=1
    if [ $installed -eq 1 ] && docker_ready; then
        ready=1
        version=$(dk version --format '{{.Server.Version}}' 2> /dev/null | tr -cd '0-9.')
        # (con proyectos del Apache de Docker, que el temporizador de los que no tienen visitas este puesto:
        # los de antes de la 1.56.8 / 1.40.1 no lo tenian)
        [ -n "$(docker_web_projects)" ] && docker_idle_ensure
    fi
    [ $ready -eq 1 ] && docker_fix_restart > /dev/null
    echo "S|$installed|$ready|$version|$(lampp_running && echo 1 || echo 0)|$(systemctl is-active -q docker.service docker.socket containerd.service 2> /dev/null && echo 1 || echo 0)"
    echo "V|$DOCKER_PHP_VERSIONS|$DOCKER_MARIADB_VERSIONS"
    for p in $(docker_projects); do
        if docker_web_project "$p"; then
            echo "P|$p|$(docker_conf "$p" CARPETA)|$(docker_conf "$p" ACTIVA)|$(docker_conf "$p" MARIADB)|$(docker_conf "$p" DOMINIO)|$([ $ready -eq 1 ] && docker_state "$p" || echo "?")|$(docker_conf "$p" BBDD)|web|web|$(docker_conf "$p" ACTIVA)|$(docker_conf "$p" TIPO)|$(docker_conf "$p" PHP)|$(docker_conf "$p" LAMPP_BD)"
        else
            echo "P|$p|$(docker_conf "$p" CARPETA)|$(docker_conf "$p" PHP)|$(docker_conf "$p" MARIADB)|$(docker_conf "$p" DOMINIO)|$([ $ready -eq 1 ] && docker_state "$p" || echo "?")|$(docker_conf "$p" BBDD)|$(docker_conf "$p" PUERTO_PMA)"
        fi | tr -d '\000-\010\013-\037'
    done
    echo "W|$(docker_web_get IP)|$(docker_web_get HTTP)|$(docker_web_get HTTPS)|$([ $ready -eq 1 ] && docker_web_state || echo "?")|$(docker_web_ports_ok && echo 1 || echo 0)|$(docker_web_tld)|$(docker_dns_on && echo 1 || echo 0)"
    if [ $ready -eq 1 ]; then
        # (al final, el ID corto del contenedor)
        dk ps -a --format '{{.Names}}|{{.Image}}|{{.State}}|{{.Status}}|{{.Ports}}|{{.Label "com.docker.compose.project"}}|{{.ID}}' 2> /dev/null \
            | tr -d '\000-\010\013-\037' | awk -F'|' -v OFS='|' 'NF == 7 && $7 ~ /^[0-9a-f]+$/ {
                # (el puente hasta la BBDD de una version LAMPP no es de compose: va con su nombre)
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
#   T|nucleos|memoria del equipo en bytes   y   K|contenedor|% de CPU|memoria usada (texto de Docker)
function gui_docker_stats() {
    docker_ready || return 0
    echo "T|$(nproc 2> /dev/null || echo 1)|$(awk '/^MemTotal:/ { print $2 * 1024 }' /proc/meminfo)"
    dk stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}' 2> /dev/null \
        | tr -d '\000-\010\013-\037' | awk -F'|' 'NF == 3 { print "K|" $0 }'
    return 0
}

# docker-contenedor arrancar|parar|reiniciar|registros|borrar <contenedor>: uno solo de los contenedores de
# un proyecto del gestor (nexum-<proyecto>-php|db|pma-N), no cualquiera de tu Docker
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

# docker-imagenes borrar <ID|imagen:etiqueta> | descargar <imagen:etiqueta>: las imagenes de tu Docker.
# Se borra sin -f: si la usa algun contenedor (aunque este parado), Docker no la borra y lo dice
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

# Los contenedores de los proyectos no arrancan solos al encender el equipo (se arrancan desde la
# pestaña Docker). Hasta la 1.54 se creaban con restart: unless-stopped y Docker los volvia a arrancar
# al iniciar la sesion: se cambia en sus compose.yaml y en los contenedores que ya existen (sin pararlos)
function docker_fix_restart() {
    local p dir
    for p in $(docker_projects); do
        dir=$DOCKER_DIR/$p
        docker_web_project "$p" && continue
        grep -q '^    restart: unless-stopped$' "$dir/compose.yaml" 2> /dev/null || continue
        [ "$DRY" -eq 1 ] && { echo "  [simulacion] $p: sin arranque automatico"; continue; }
        sed -i 's/^    restart: unless-stopped$/    restart: "no"/' "$dir/compose.yaml"
        dk ps -aq --filter "label=com.docker.compose.project=nexum-$p" 2> /dev/null \
            | xargs -r "$DOCKER_BIN" -H "$(docker_sock)" update --restart=no > /dev/null 2>&1
    done
    docker_fix_pma
    docker_fix_cache
    return 0
}

# Hasta la 1.55.9 la cache de una tienda PrestaShop 1.7+ en Docker (var/cache) iba en la carpeta del
# proyecto, la misma que usa LAMPP: guardaba alli la BBDD del contenedor (db) y la tienda dejaba de
# funcionar en LAMPP. Se pasa a un volumen del contenedor; se aplica al volver a crear su contenedor
# de PHP (al arrancar el proyecto, o ya, si esta en marcha)
function docker_fix_cache() {
    local p dir folder
    for p in $(docker_projects); do
        dir=$DOCKER_DIR/$p
        folder=$(docker_conf "$p" CARPETA)
        docker_web_project "$p" && continue
        grep -q '/app/config/parameters.php:ro"$' "$dir/compose.yaml" 2> /dev/null || continue
        grep -q '/var/cache"$' "$dir/compose.yaml" && continue
        [ "$DRY" -eq 1 ] && { echo "  [simulacion] $p: la cache de PrestaShop en su volumen"; continue; }
        python3 -I - "$dir/compose.yaml" "$folder" <<'PY' || continue
import sys
path, folder = sys.argv[1], sys.argv[2]
lines = open(path, encoding="utf-8").read().split("\n")
out = []
for line in lines:
    out.append(line)
    if line.endswith('/app/config/parameters.php:ro"'):
        out.append('      - "cache:/opt/lampp/htdocs/%s/var/cache"' % folder)
    if line == "  db: {}":
        out.append("  cache: {}")
open(path + ".nuevo", "w", encoding="utf-8").write("\n".join(out))
PY
        mv -f "$dir/compose.yaml.nuevo" "$dir/compose.yaml" || continue
        if [ "$(docker_state "$p")" == marcha ]; then
            dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d php > /dev/null 2>&1
        fi
    done
    return 0
}

# Hasta la 1.54.0 el phpMyAdmin de cada proyecto entraba solo como root (PMA_USER y PMA_PASSWORD):
# cualquier programa o web que llegara a su puerto tenia la BBDD entera. Ahora enseña su pantalla
# de acceso (usuario root y la contraseña de la BBDD, que la ventana copia). Se quita de sus
# compose.yaml; el contenedor se rehace al arrancar el proyecto (o ya, si esta en marcha)
function docker_fix_pma() {
    local p dir
    for p in $(docker_projects); do
        dir=$DOCKER_DIR/$p
        docker_web_project "$p" && continue
        grep -qE '^      PMA_(USER|PASSWORD):' "$dir/compose.yaml" 2> /dev/null || continue
        [ "$DRY" -eq 1 ] && { echo "  [simulacion] $p: phpMyAdmin con su pantalla de acceso"; continue; }
        sed -i -E '/^      PMA_(USER|PASSWORD):/d' "$dir/compose.yaml" || continue
        if [ "$(docker_state "$p")" == marcha ]; then
            dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d pma > /dev/null 2>&1
        fi
    done
    return 0
}

# docker-imagen <nombre>: rehace la imagen de PHP de un proyecto (nexum-php:<version>) con lo ultimo
# de Docker Hub (--pull, sin la cache: con los parches de seguridad de PHP y del sistema de la
# imagen) y vuelve a crear su contenedor de PHP. La BBDD y la configuracion no se tocan. Los demas
# proyectos con esa version de PHP pasan a la imagen nueva al volver a crear su contenedor
function docker_update_image() {
    local slug=$1 dir php
    if ! docker_valid_slug "$slug" || [ ! -f "$DOCKER_DIR/$slug/proyecto.conf" ]; then
        echo "No hay ningun proyecto en Docker con el nombre $slug"
        return 1
    fi
    dir=$DOCKER_DIR/$slug
    if docker_web_project "$slug"; then
        local v running
        echo "$slug: imagenes de PHP $(docker_conf "$slug" PHP) de nuevo, con lo ultimo de Docker Hub (la BBDD y la configuracion no cambian)"
        [ "$DRY" -eq 1 ] && return 0
        docker_ready || { echo "Docker sin root no esta en marcha"; return 1; }
        local steps=()
        for v in $(docker_conf "$slug" PHP); do steps+=("Imagen de PHP $v"); done
        steps+=("Volver a crear sus contenedores")
        task_plan "$slug: imágenes de PHP" "${steps[@]}"
        for v in $(docker_conf "$slug" PHP); do
            task_step
            docker_php_image "$v" --nueva || { echo "No se ha podido rehacer la imagen de PHP $v: sigue con la anterior"; return 1; }
        done
        task_step
        running=$(dk ps --filter "label=com.docker.compose.project=nexum-$slug" --format '{{.Label "com.docker.compose.service"}}' 2> /dev/null)
        [ -n "$running" ] && { dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d --force-recreate $running || return 1; }
        dk image prune -f > /dev/null 2>&1
        echo "$slug ya funciona con las imagenes nuevas"
        return 0
    fi
    php=$(docker_conf "$slug" PHP)
    [[ " $DOCKER_PHP_VERSIONS " == *" $php "* ]] || { echo "$slug usa una version de PHP que no se ofrece: $php"; return 1; }
    echo "$slug: imagen de PHP $php de nuevo, con lo ultimo de Docker Hub (la BBDD y la configuracion no cambian)"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] docker build --pull --no-cache -t nexum-php:$php y contenedor de PHP nuevo"
        return 0
    fi
    docker_ready || { echo "Docker sin root no esta en marcha"; return 1; }
    task_plan "$slug: imagen de PHP $php" "Imagen de PHP $php" "Volver a crear su contenedor"
    task_step
    docker_php_image "$php" --nueva || { echo "No se ha podido rehacer la imagen de PHP $php: sigue con la anterior"; return 1; }
    task_step
    mkdir -p -m 700 "$(docker_run_dir "$slug")"
    dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d --force-recreate php || return 1
    dk image prune -f > /dev/null 2>&1
    echo "$slug ya funciona con la imagen nueva de PHP $php"
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
        echo "$slug va con el Apache de Docker: añade la version (docker-php-añadir $slug $php) y, si quieres, quita otra (docker-php-quitar)"
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
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] imagen nexum-php:$php y contenedor de PHP nuevo"
        return 0
    fi
    docker_ready || { echo "Docker sin root no esta en marcha"; return 1; }
    docker_php_image "$php" || { echo "No se ha podido preparar la imagen de PHP $php: sigue con PHP $old"; return 1; }
    sed -i -E "s|^    image: nexum-php:[0-9.]+$|    image: nexum-php:$php|" "$dir/compose.yaml" \
        && sed -i "s/^PHP=.*/PHP=$php/" "$dir/proyecto.conf" || return 1
    mkdir -p -m 700 "$(docker_run_dir "$slug")"
    if ! dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d php; then
        echo "No arranca con PHP $php: se vuelve a PHP $old"
        sed -i -E "s|^    image: nexum-php:[0-9.]+$|    image: nexum-php:$old|" "$dir/compose.yaml"
        sed -i "s/^PHP=.*/PHP=$old/" "$dir/proyecto.conf"
        dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d php
        return 1
    fi
    echo "$slug ya funciona con PHP $php"
}

# Arranque de Docker sin root y su servicio de usuario (lo mismo que hace dockerd-rootless-setuptool.sh
# del Docker oficial, que el paquete docker.io de Ubuntu no trae): rootlesskit crea el espacio de
# usuarios y la red (slirp4netns) y dentro arranca dockerd, que al verse ahi usa
# $XDG_RUNTIME_DIR/docker.sock y ~/.local/share/docker
DOCKER_ROOTLESS_SH='#!/bin/sh
# Docker sin root de Nexum Dev Stack (como dockerd-rootless.sh de Docker). Lo arranca systemctl --user
set -e
if [ -z "$_DOCKERD_ROOTLESS_CHILD" ]; then
    : "${XDG_RUNTIME_DIR:?falta XDG_RUNTIME_DIR}"
    export _DOCKERD_ROOTLESS_CHILD=1
    exec /usr/bin/rootlesskit --state-dir="$XDG_RUNTIME_DIR/dockerd-rootless" --net=slirp4netns --mtu=65520 \
        --slirp4netns-sandbox=auto --slirp4netns-seccomp=auto --disable-host-loopback --port-driver=builtin \
        --copy-up=/etc --copy-up=/run --propagation=rslave "$0" "$@"
fi
[ "$_DOCKERD_ROOTLESS_CHILD" = 1 ]
# (los del Docker del sistema: dentro del espacio de usuarios /run es una copia propia)
rm -f /run/docker /run/containerd /run/xtables.lock
exec /usr/bin/dockerd "$@"
'
DOCKER_UNIT='[Unit]
Description=Docker sin root (Nexum Dev Stack)
Documentation=https://docs.docker.com/engine/security/rootless/

[Service]
Environment=PATH=/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=%h/.lvm-instalador/docker/bin/dockerd-rootless
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
Type=notify
NotifyAccess=all
KillMode=mixed

[Install]
WantedBy=default.target
'

# docker-instalar: Docker sin root. Instala los paquetes de Ubuntu (con sudo, si falta alguno), deja
# apagados el Docker y el containerd del sistema (los que corren como root), prepara los rangos de
# usuarios (subuid/subgid) y, si Ubuntu limita los espacios de usuarios, el perfil de AppArmor de
# rootlesskit. Despues, ya con tu usuario, el servicio de Docker sin root (systemctl --user)
function docker_install() {
    local me=$(id -un) p missing=""
    if ! command -v apt-get > /dev/null; then
        echo "Docker sin root solo se instala solo en Ubuntu o Debian. Instalalo a mano: https://docs.docker.com/engine/security/rootless/"
        return 1
    fi
    for p in $DOCKER_PACKAGES; do
        dpkg-query -W -f='${Status}' "$p" 2> /dev/null | grep -q "install ok installed" || missing+=" $p"
    done
    task_plan "Preparando Docker sin root" "Paquetes del sistema" "Docker del sistema, apagado" "Docker sin root" "Comprobar que responde"
    task_step
    if [ -n "$missing" ]; then
        echo "1/4 Paquetes:$missing"
        # (sin preguntas de debconf: la tarea no tiene una terminal donde contestarlas)
        run sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y $missing || return 1
    else
        echo "1/4 Paquetes: ya estan instalados"
    fi
    # (el paquete deja en marcha el demonio con root: con el, el grupo docker seria como ser root)
    task_step
    echo "2/4 Docker y containerd del sistema (con root), apagados: se usa solo el tuyo"
    if systemctl is-enabled -q docker.service docker.socket containerd.service 2> /dev/null \
            || systemctl is-active -q docker.service docker.socket containerd.service 2> /dev/null; then
        run sudo systemctl disable --now docker.service docker.socket containerd.service 2> /dev/null || true
    fi
    if ! grep -q "^$me:" /etc/subuid 2> /dev/null || ! grep -q "^$me:" /etc/subgid 2> /dev/null; then
        echo "   Rangos de usuarios para los contenedores (/etc/subuid y /etc/subgid)"
        run sudo usermod --add-subuids 231072-296607 --add-subgids 231072-296607 "$me" || return 1
    fi
    if [ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2> /dev/null)" == 1 ] \
            && ! grep -lqs 'rootlesskit' /etc/apparmor.d/* 2> /dev/null; then
        echo "   Perfil de AppArmor para rootlesskit (Ubuntu limita los espacios de usuarios)"
        if [ "$DRY" -eq 1 ]; then
            echo "  [simulacion] /etc/apparmor.d/usr.bin.rootlesskit y recarga de AppArmor"
        else
            printf '%s\n' 'abi <abi/4.0>,' 'include <tunables/global>' '' \
                '"/usr/bin/rootlesskit" flags=(unconfined) {' '  userns,' '' \
                '  include if exists <local/usr.bin.rootlesskit>' '}' \
                | sudo tee /etc/apparmor.d/usr.bin.rootlesskit > /dev/null \
                && sudo apparmor_parser -r /etc/apparmor.d/usr.bin.rootlesskit || return 1
        fi
    fi
    task_step
    echo "3/4 Docker sin root para $me (servicio de tu usuario)"
    local unit_dir=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $DOCKER_DIR/bin/dockerd-rootless y $unit_dir/docker.service"
    else
        mkdir -p -m 700 "$DOCKER_DIR" "$DOCKER_DIR/bin" && mkdir -p "$unit_dir" || return 1
        printf '%s' "$DOCKER_ROOTLESS_SH" > "$DOCKER_DIR/bin/dockerd-rootless.nuevo" \
            && chmod 700 "$DOCKER_DIR/bin/dockerd-rootless.nuevo" \
            && mv -f "$DOCKER_DIR/bin/dockerd-rootless.nuevo" "$DOCKER_DIR/bin/dockerd-rootless" || return 1
        printf '%s' "$DOCKER_UNIT" > "$unit_dir/docker.service.nuevo" \
            && mv -f "$unit_dir/docker.service.nuevo" "$unit_dir/docker.service" || return 1
    fi
    run systemctl --user daemon-reload || return 1
    run systemctl --user enable docker.service || return 1
    run systemctl --user restart docker.service || {
        echo "No arranca Docker sin root. Lo que dice:"
        journalctl --user -u docker.service -n 30 --no-pager 2> /dev/null
        return 1
    }
    task_step
    echo "4/4 Comprobando"
    local i
    for i in $(seq 20); do docker_ready && break; [ "$DRY" -eq 1 ] && break; sleep 1; done
    if [ "$DRY" -eq 0 ] && ! docker_ready; then
        echo "Docker sin root no responde. Prueba a cerrar la sesion y volver a entrar, y pulsa Comprobar."
        return 1
    fi
    echo "Docker sin root listo (socket $(docker_sock))."
}

# Imagen de PHP del gestor para una version (nexum-php:<version>): la oficial php:<version>-fpm con
# las extensiones de DOCKER_PHP_EXT (con install-php-extensions, que sabe instalarlas tambien en las
# versiones antiguas). PHP-FPM escucha en un socket de /run/nexum (docker_run_dir del proyecto) y corre
# como el root del contenedor, que en Docker sin root eres tu: asi escribe en el proyecto con tu usuario
# Con --nueva se rehace aunque ya exista (Actualizar imagen: con lo ultimo de Docker Hub, sin cache).
# El php.ini es el de produccion, con las mitigaciones de PHP2Shell (PHP_SECURE_INI), y cada proceso
# de PHP-FPM se renueva cada 50 peticiones
# (install-php-extensions, fijado por su huella: la etiqueta 2 la puede mover cualquiera que llegue a
# esa cuenta de Docker Hub. Es la 2.12.3, del 20/10/2026; para otra: docker buildx imagetools inspect)
DOCKER_EXT_INSTALLER="mlocati/php-extension-installer:2.12.3@sha256:ac4b252c153a9f6de5578ff2c417790aba836bb49855543144606033eceda253"
function docker_php_image() {
    local php=$1 dir=$DOCKER_DIR/imagenes/php-$1 fresh=() ini
    if [ "$2" == "--nueva" ]; then
        fresh=(--pull --no-cache)
    elif [ "$DRY" -eq 0 ] && dk image inspect "nexum-php:$php" > /dev/null 2>&1; then
        return 0
    fi
    mkdir -p -m 700 "$dir" || return 1
    ini=$(printf 'memory_limit = 512M\nmax_execution_time = 300\n%s' "$PHP_SECURE_INI")
    php_85_or_later "$php" && ini+=$'\n'$PHP_SECURE_INI_85
    ini=${ini//$'\n'/\\n}
    cat > "$dir/Dockerfile" << EOF
FROM php:$php-fpm
COPY --from=$DOCKER_EXT_INSTALLER /usr/bin/install-php-extensions /usr/local/bin/
RUN install-php-extensions $DOCKER_PHP_EXT
RUN rm -f /usr/local/etc/php-fpm.d/zz-docker.conf /usr/local/etc/php-fpm.d/docker.conf \\
 && printf '[global]\\nerror_log = /proc/self/fd/2\\ndaemonize = no\\n[www]\\nuser = root\\ngroup = root\\nlisten = /run/nexum/php.sock\\nlisten.mode = 0660\\nclear_env = no\\ncatch_workers_output = yes\\npm.max_requests = 50\\n' > /usr/local/etc/php-fpm.d/zz-nexum.conf \\
 && cp "\$PHP_INI_DIR/php.ini-production" "\$PHP_INI_DIR/php.ini" \\
 && printf '$ini\\n' > "\$PHP_INI_DIR/conf.d/zz-nexum.ini"
CMD ["php-fpm", "-R", "-F"]
EOF
    echo "Preparando la imagen de PHP $php (${fresh:+de nuevo, }tarda unos minutos)..."
    run dk build "${fresh[@]}" -t "nexum-php:$php" "$dir"
}

# Configuracion del proyecto para el contenedor: copia de su wp-config.php (o parameters.php /
# settings.inc.php) con la BBDD del contenedor y, en WordPress, su dominio. Imprime la ruta relativa
# del fichero dentro del proyecto (la que se sustituye en el contenedor), nada si no tiene. El
# servidor de la BBDD es db (el contenedor del proyecto) o el septimo argumento (la MariaDB comun)
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

# Bloque del vhost de un proyecto en Docker (http y https) para los vhosts compartidos: la carpeta
# del proyecto como siempre y los .php al PHP-FPM del contenedor
function docker_vhost_block() {
    local slug=$1 folder=$2 domain=$3 sock=$4 crt=$5 key=$6 admin=$(server_admin) port
    printf '\n# nexum-docker %s: el PHP va en Docker (no se edita a mano: lo quita Docker, Borrar)\n' "$slug"
    for port in "$PORT_HTTP" "$PORT_HTTPS"; do
        printf '<VirtualHost *:%s>\n    ServerAdmin %s\n    DocumentRoot "/opt/lampp/htdocs/%s"\n    ServerName %s\n' \
            "$port" "$admin" "$folder" "$domain"
        [ "$port" == "$PORT_HTTPS" ] && printf '    SSLEngine on\n    SSLCertificateFile "%s"\n    SSLCertificateKeyFile "%s"\n' "$crt" "$key"
        printf '    <FilesMatch "\\.php$">\n        SetHandler "proxy:unix:%s|fcgi://nexum-%s"\n    </FilesMatch>\n' "$sock" "$slug"
        printf '    ErrorLog "logs/%s-error_log"\n</VirtualHost>\n' "$domain"
    done
    printf '# /nexum-docker %s\n' "$slug"
}

# Cambia los vhosts compartidos por los de la copia, con la comprobacion de siempre (edit_vhosts)
function docker_apply_vhosts() {
    local copy=$1
    edit_vhosts --aplicar "$copy"
}

# docker-crear <carpeta> <php> <mariadb> [--bd <base> --desde <version LAMPP>] [--dominio <dominio>]
#   [--nombre <nombre>]  (otro nombre: el mismo proyecto en Docker con otra version de PHP)
function docker_create() {
    local folder=${1%/} php=$2 maria=$3 db="" from="" domain="" name="" slug dir sock rel pma_port p
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
        [ -n "$from" ] && valid_version_name "$from" && [ -d "${TEST_DIR:-/opt}/lampp-$from" ] \
            || { echo "Con --bd hay que decir de que version LAMPP se copia (--desde)"; return 1; }
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
        echo "Docker sin root no esta en marcha: instalalo o arrancalo en la pestaña Docker."
        return 1
    fi
    # Puerto de 127.0.0.1 para su phpMyAdmin: el primero libre
    pma_port=$DOCKER_PMA_PORT
    while grep -qs "^PUERTO_PMA=$pma_port$" "$DOCKER_DIR"/*/proyecto.conf || ss -Hltn "sport = :$pma_port" 2> /dev/null | grep -q .; do
        pma_port=$((pma_port + 1))
    done
    local dbname=${db:-$(tr '-' '_' <<< "$slug")} user=nexum
    local root_pass app_pass
    root_pass=$(head -c 18 /dev/urandom | base64 | tr -d '/+=\n')
    app_pass=$(head -c 18 /dev/urandom | base64 | tr -d '/+=\n')
    sock=$(docker_run_dir "$slug")/php.sock
    if [ ${#sock} -gt 100 ]; then
        echo "La ruta del socket de PHP ($sock) es demasiado larga: usa una carpeta con un nombre mas corto"
        return 1
    fi

    echo "Proyecto en Docker: $folder con PHP $php y MariaDB $maria (https://$domain)"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $dir con compose.yaml, la imagen nexum-php:$php, vhost de $domain y su linea en $HOSTS_FILE"
        [ -n "$db" ] && echo "  [simulacion] copia de $db de lampp-$from a la MariaDB del contenedor"
        return 0
    fi
    mkdir -p -m 700 "$DOCKER_DIR" "$dir" "$(dirname "$sock")" || return 1
    chmod 700 "$DOCKER_DIR" "$dir" "$(dirname "$(dirname "$sock")")" "$(dirname "$sock")"
    # (las contraseñas, solo en ficheros solo tuyos)
    ( umask 077
      printf 'DB_ROOT_PASS=%s\nDB_PASS=%s\n' "$root_pass" "$app_pass" > "$dir/.env"
      printf 'CARPETA=%s\nPHP=%s\nMARIADB=%s\nDOMINIO=%s\nBBDD=%s\nPUERTO_PMA=%s\n' \
          "$folder" "$php" "$maria" "$domain" "$dbname" "$pma_port" > "$dir/proyecto.conf" ) || return 1
    rel=$(docker_project_config "$folder" "$dir" "$domain" "$dbname" "$user" "$app_pass") || return 1
    {
        printf 'name: nexum-%s\nservices:\n' "$slug"
        printf '  php:\n    image: nexum-php:%s\n    restart: "no"\n    volumes:\n' "$php"
        printf '      - "%s:/opt/lampp/htdocs/%s"\n' "$HTDOCS_DIR/$folder" "$folder"
        printf '      - "%s:/run/nexum"\n' "$(dirname "$sock")"
        [ -n "$rel" ] && printf '      - "./config.php:/opt/lampp/htdocs/%s/%s:ro"\n' "$folder" "$rel"
        # PrestaShop 1.7 y posteriores guardan su configuracion (con la BBDD del contenedor: db y su
        # usuario) en var/cache: aparte, en un volumen del contenedor, no en la carpeta que comparte
        # con LAMPP (que la leeria y no encontraria la BBDD)
        [ "$rel" == app/config/parameters.php ] && printf '      - "cache:/opt/lampp/htdocs/%s/var/cache"\n' "$folder"
        printf '    depends_on: [db]\n'
        printf '  db:\n    image: mariadb:%s\n    restart: "no"\n    environment:\n' "$maria"
        printf '      MARIADB_ROOT_PASSWORD: ${DB_ROOT_PASS}\n      MARIADB_DATABASE: %s\n      MARIADB_USER: %s\n      MARIADB_PASSWORD: ${DB_PASS}\n' "$dbname" "$user"
        printf '    volumes:\n      - "db:/var/lib/mysql"\n'
        # (sin PMA_USER ni PMA_PASSWORD: phpMyAdmin enseña su pantalla de acceso; la contraseña de
        # root la copia la ventana)
        printf '  pma:\n    image: %s\n    restart: "no"\n    environment:\n      PMA_HOST: db\n      UPLOAD_LIMIT: 64M\n' "$DOCKER_PMA_IMAGE"
        printf '    ports:\n      - "127.0.0.1:%s:80"\n    depends_on: [db]\n' "$pma_port"
        printf 'volumes:\n  db: {}\n'
        if [ "$rel" == app/config/parameters.php ]; then printf '  cache: {}\n'; fi
    } > "$dir/compose.yaml" || return 1

    task_plan "Creando $folder en Docker" "Imagen de PHP $php" "Contenedores" "BBDD $dbname" "Vhost de $domain"
    task_step
    echo "1/4 Imagen de PHP $php"
    docker_php_image "$php" || { echo "No se ha podido preparar la imagen de PHP $php"; return 1; }
    task_step
    echo "2/4 Contenedores"
    dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d || return 1
    task_step
    echo "3/4 BBDD $dbname"
    local i
    # (la contraseña no va en ninguna orden, que se ve en ps: el cliente la toma dentro del contenedor
    # de MARIADB_ROOT_PASSWORD, la variable con la que se creo)
    for i in $(seq 60); do
        dk compose --project-directory "$dir" -f "$dir/compose.yaml" exec -T db \
            sh -c 'MYSQL_PWD=$MARIADB_ROOT_PASSWORD exec $(command -v mariadb || command -v mysql) -uroot -e "SELECT 1"' < /dev/null > /dev/null 2>&1 && break
        sleep 1
    done
    if [ -n "$db" ]; then
        local tmp
        mkdir -p -m 700 "$LOG_DIR" || return 1
        tmp=$(mktemp "$LOG_DIR/docker-$slug-XXXXXX") && mv -f "$tmp" "$tmp.sql.gz" && tmp=$tmp.sql.gz || return 1
        echo "Copiando $db de lampp-$from..."
        if ! export_database "$db" "$tmp" "$from"; then
            rm -f "$tmp"
            echo "No se ha podido descargar $db de lampp-$from: el proyecto queda con la BBDD vacia."
        else
            db_temp_stop
            gzip -dc "$tmp" | dk compose --project-directory "$dir" -f "$dir/compose.yaml" exec -T db \
                sh -c 'MYSQL_PWD=$MARIADB_ROOT_PASSWORD exec $(command -v mariadb || command -v mysql) -uroot --binary-mode "$0"' "$dbname" \
                || echo "Aviso: la carga de $db ha dado errores (mira el registro)."
            rm -f "$tmp"
            docker_ps_domain "$dir" "$dbname" "$domain" "$root_pass"
            # (la copia va sin el administrador de pruebas: se le pone el de este equipo para el Panel)
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
    copy=$(mktemp "$LOG_DIR/vhosts-docker-XXXXXX") || return 1
    { cat "$(readlink -f "$ACTIVE_VHOSTS")"; docker_vhost_block "$slug" "$folder" "$domain" "$sock" "$crt" "$key"; } > "$copy"
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
}

# Tienda PrestaShop copiada al contenedor: su dominio pasa a ser el del contenedor (la BBDD es una copia)
function docker_ps_domain() {
    local dir=$1 db=$2 domain=$3 pass=$4 prefix
    # (la contraseña, la del contenedor: MARIADB_ROOT_PASSWORD)
    prefix=$(dk compose --project-directory "$dir" -f "$dir/compose.yaml" exec -T db \
        sh -c 'MYSQL_PWD=$MARIADB_ROOT_PASSWORD exec $(command -v mariadb || command -v mysql) -uroot -N -e "SELECT LEFT(table_name, LENGTH(table_name) - 8) FROM information_schema.tables WHERE table_schema = \"$0\" AND table_name LIKE \"%shop\\_url\" LIMIT 1"' "$db" < /dev/null 2> /dev/null | tr -d '\r')
    [[ "$prefix" =~ ^[A-Za-z0-9_]+$ ]] || return 0
    echo "Tienda PrestaShop: su dominio pasa a $domain en la copia del contenedor"
    dk compose --project-directory "$dir" -f "$dir/compose.yaml" exec -T db \
        sh -c 'MYSQL_PWD=$MARIADB_ROOT_PASSWORD exec $(command -v mariadb || command -v mysql) -uroot "$0"' "$db" << EOF
UPDATE \`${prefix}shop_url\` SET domain = '$domain', domain_ssl = '$domain';
UPDATE \`${prefix}configuration\` SET value = '$domain' WHERE name IN ('PS_SHOP_DOMAIN', 'PS_SHOP_DOMAIN_SSL');
UPDATE \`${prefix}configuration\` SET value = '1' WHERE name IN ('PS_SSL_ENABLED', 'PS_SSL_ENABLED_EVERYWHERE');
EOF
}

# docker-usuario-pruebas <nombre>: el administrador de pruebas (usuario-pruebas) en la BBDD del
# contenedor del proyecto. La copia que se lleva de LAMPP no lo tiene (exportar-bd lo deja fuera) y
# sin el no entra el Panel. Es el mismo test_admin, por el cliente de la MariaDB del contenedor como
# root: la contraseña la toma dentro del contenedor (MARIADB_ROOT_PASSWORD), nunca en una orden. Dice
# A|wp|... y/o A|ps|... como usuario-pruebas; con el proyecto parado, nada (sale con 1)
function docker_test_admin() {
    local slug=$1 dir db folder
    docker_valid_slug "$slug" && [ -f "$DOCKER_DIR/$slug/proyecto.conf" ] || { echo "No hay ningun proyecto en Docker con el nombre $slug"; return 1; }
    dir=$DOCKER_DIR/$slug
    db=$(docker_conf "$slug" BBDD) folder=$(docker_conf "$slug" CARPETA)
    db_valid_name "$db" > /dev/null || { echo "$slug no tiene una BBDD valida en su proyecto.conf"; return 1; }
    if docker_web_project "$slug"; then
        local DB_ROOT_CLIENT=(dk exec -i "$(docker_maria_name "$(docker_conf "$slug" MARIADB)")"
            sh -c 'MYSQL_PWD=$MARIADB_ROOT_PASSWORD exec $(command -v mariadb || command -v mysql) -uroot "$@"' mariadb)
        test_admin "$db" "$folder"
        return
    fi
    local DB_ROOT_CLIENT=(dk compose --project-directory "$dir" -f "$dir/compose.yaml" exec -T db
        sh -c 'MYSQL_PWD=$MARIADB_ROOT_PASSWORD exec $(command -v mariadb || command -v mysql) -uroot "$@"' mariadb)
    test_admin "$db" "$folder"
}

# docker-arrancar|docker-parar|docker-registros|docker-borrar <nombre>
function docker_action() {
    local action=$1 slug=$2 dir
    docker_valid_slug "$slug" && [ -f "$DOCKER_DIR/$slug/proyecto.conf" ] || { echo "No hay ningun proyecto en Docker con el nombre $slug"; return 1; }
    # (los del Apache de Docker: lo suyo es distinto)
    if docker_web_project "$slug"; then
        case $action in
            arrancar|parar|registros|borrar) docker_web_action "$action" "$slug" ;;
            *) echo "Uso: lvm-instalador docker-arrancar|docker-parar|docker-registros|docker-borrar <nombre>"; return 1 ;;
        esac
        return
    fi
    dir=$DOCKER_DIR/$slug
    local c=(dk compose --project-directory "$dir" -f "$dir/compose.yaml")
    case $action in
        # (la carpeta del socket esta en memoria: tras reiniciar el equipo hay que volver a crearla)
        arrancar) run mkdir -p -m 700 "$(docker_run_dir "$slug")" && run "${c[@]}" up -d ;;
        parar) run "${c[@]}" stop ;;
        registros) "${c[@]}" logs --no-color --tail 200 ;;
        borrar)
            local domain=$(docker_conf "$slug" DOMINIO) copy
            echo "Se borran los contenedores de $slug y su BBDD (la copia del contenedor; la de LAMPP no se toca)"
            run "${c[@]}" down -v || return 1
            if grep -q "^# nexum-docker $slug:" "$(readlink -f "$ACTIVE_VHOSTS")" 2> /dev/null; then
                copy=$(mktemp "$LOG_DIR/vhosts-docker-XXXXXX") || return 1
                awk -v s="$slug" '$0 ~ ("^# nexum-docker " s ":") { skip = 1 } !skip { print } $0 == ("# /nexum-docker " s) { skip = 0 }' \
                    "$(readlink -f "$ACTIVE_VHOSTS")" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' > "$copy"
                docker_apply_vhosts "$copy" || { rm -f "$copy"; return 1; }
                rm -f "$copy"
            fi
            if [ -n "$domain" ] && valid_domain "$domain" && grep -qE "^127\.0\.0\.1[[:space:]]+${domain//./\\.}$" "$HOSTS_FILE"; then
                copy=$(mktemp "$LOG_DIR/hosts-docker-XXXXXX") || return 1
                grep -vE "^127\.0\.0\.1[[:space:]]+${domain//./\\.}$" "$HOSTS_FILE" > "$copy"
                edit_hosts --aplicar "$copy"
                rm -f "$copy"
            fi
            [ "$DRY" -eq 1 ] || rm -rf "$dir" "$(docker_run_dir "$slug")"
            echo "Proyecto en Docker $slug borrado"
            ;;
        *) echo "Uso: lvm-instalador docker-arrancar|docker-parar|docker-registros|docker-borrar <nombre>"; return 1 ;;
    esac
}

