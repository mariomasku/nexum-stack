# PostgreSQL de Docker (Configuración > Docker, 1.57.39): una común por versión, como las MariaDB comunes,
# para todos los proyectos. En la red interna de Docker (los PHP la ven como nexum-postgres-18, puerto
# 5432) y en este equipo, para tus herramientas de BBDD: 127.0.0.1, puerto 54300 + la versión (54318 la
# 18). Usuario postgres y su contraseña al azar, en un fichero solo tuyo. Con alguna, las imágenes de PHP
# de Docker traen pgsql y pdo_pgsql
DOCKER_PG_VERSIONS="18 17 16"

function docker_pg_name() {
    echo "nexum-postgres-$1"
}

function docker_pg_port() {
    echo $((54300 + $1))
}

# Las que hay (sus versiones)
function docker_pg_versions() {
    local v
    for v in $DOCKER_PG_VERSIONS; do
        [ -f "$DOCKER_DIR/postgres-$v/compose.yaml" ] && echo "$v"
    done
    return 0
}

# La contraseña del usuario postgres de una versión (de su .env)
function docker_pg_pass() {
    sed -n 's/^PG_PASS=//p' "$DOCKER_DIR/postgres-$1/.env" 2> /dev/null | head -1
}

# Estado: marcha, parado o nuevo (sin contenedor)
function docker_pg_state() {
    local s
    s=$(dk ps -a --filter name="^$(docker_pg_name "$1")\$" --format '{{.State}}' 2> /dev/null | head -1)
    case $s in running) echo marcha ;; "") echo nuevo ;; *) echo parado ;; esac
}

# La crea si no existe (su compose.yaml y su contraseña, en ficheros solo tuyos), la arranca y espera a
# que responda
function docker_pg_up() {
    local v=$1 name dir i data=/var/lib/postgresql/data
    [[ " $DOCKER_PG_VERSIONS " == *" $v "* ]] || { echo "PostgreSQL $v no se ofrece en Docker ($DOCKER_PG_VERSIONS)"; return 1; }
    name=$(docker_pg_name "$v") dir=$DOCKER_DIR/postgres-$v
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] PostgreSQL $v de Docker ($name) en marcha, en 127.0.0.1:$(docker_pg_port "$v")"
        return 0
    fi
    # (desde la 18, los datos van en una carpeta por versión dentro de /var/lib/postgresql)
    [ "$v" -ge 18 ] && data=/var/lib/postgresql
    if [ ! -f "$dir/compose.yaml" ]; then
        mkdir -p -m 700 "$DOCKER_DIR" "$dir" || return 1
        ( umask 077
          printf 'PG_PASS=%s\n' "$(head -c 18 /dev/urandom | base64 | tr -d '/+=\n')" > "$dir/.env"
          { printf 'name: %s\nservices:\n  db:\n    image: postgres:%s\n    container_name: %s\n    restart: "no"\n' "$name" "$v" "$name"
            printf '    environment:\n      POSTGRES_PASSWORD: ${PG_PASS}\n'
            printf '    ports:\n      - "127.0.0.1:%s:5432"\n' "$(docker_pg_port "$v")"
            printf '    volumes:\n      - "datos:%s"\n    networks: [nexum]\n' "$data"
            printf 'volumes:\n  datos:\n    name: %s\n' "$name"
            printf 'networks:\n  nexum:\n    external: true\n    name: nexum\n'; } > "$dir/compose.yaml" ) || return 1
        echo "PostgreSQL $v de Docker: nueva, con el usuario postgres y su contraseña en $dir/.env"
    fi
    docker_net || return 1
    dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d || return 1
    for i in $(seq 90); do
        dk exec "$name" pg_isready -U postgres -q < /dev/null > /dev/null 2>&1 && return 0
        sleep 1
    done
    echo "La PostgreSQL $v de Docker no responde (mira sus registros en la pestaña Docker)"
    return 1
}

# docker-postgres [estado] | arrancar <versión> | parar <versión> | borrar <versión>
#   estado: G|versión|estado (marcha, parado o nuevo)|puerto en 127.0.0.1|contenedor, una por cada una, y
#   O|versiones que se ofrecen
function docker_pg_command() {
    local v=$2 dir
    case ${1:-estado} in
        estado)
            for v in $(docker_pg_versions); do
                echo "G|$v|$(docker_pg_state "$v")|$(docker_pg_port "$v")|$(docker_pg_name "$v")"
            done
            echo "O|$DOCKER_PG_VERSIONS" ;;
        arrancar)
            docker_ready > /dev/null 2>&1 || { echo "Docker sin root no esta en marcha"; return 1; }
            docker_pg_up "$v" || return 1
            echo "PostgreSQL $v de Docker en marcha: desde los PHP de Docker, $(docker_pg_name "$v"):5432; desde este equipo, 127.0.0.1:$(docker_pg_port "$v"). Usuario postgres"
            # (con la primera, las imágenes de PHP de Docker que hay se ponen pgsql y pdo_pgsql)
            docker_pg_rebuild ;;
        parar)
            [[ " $(docker_pg_versions | tr '\n' ' ') " == *" $v "* ]] || { echo "No hay PostgreSQL $v en Docker"; return 1; }
            [ "$DRY" -eq 1 ] && { echo "  [simulacion] PostgreSQL $v de Docker parada"; return 0; }
            dir=$DOCKER_DIR/postgres-$v
            run dk compose --project-directory "$dir" -f "$dir/compose.yaml" stop && echo "PostgreSQL $v de Docker parada" ;;
        borrar)
            [[ " $(docker_pg_versions | tr '\n' ' ') " == *" $v "* ]] || { echo "No hay PostgreSQL $v en Docker"; return 1; }
            [ "$DRY" -eq 1 ] && { echo "  [simulacion] PostgreSQL $v de Docker borrada, con sus BBDD"; return 0; }
            dir=$DOCKER_DIR/postgres-$v
            dk compose --project-directory "$dir" -f "$dir/compose.yaml" down -v > /dev/null 2>&1
            dk volume rm "$(docker_pg_name "$v")" > /dev/null 2>&1
            rm -rf "$dir" || return 1
            echo "PostgreSQL $v de Docker borrada, con sus BBDD" ;;
        *) echo "Uso: nexum docker-postgres [estado] | arrancar <version> | parar <version> | borrar <version> ($DOCKER_PG_VERSIONS)"; return 1 ;;
    esac
}

# Las extensiones de las imágenes de PHP de Docker: las de siempre y, con alguna PostgreSQL, pgsql y pdo_pgsql
function docker_php_ext() {
    if [ -n "$(docker_pg_versions)" ]; then
        echo "$DOCKER_PHP_EXT pgsql pdo_pgsql"
    else
        echo "$DOCKER_PHP_EXT"
    fi
}

# La etiqueta de la imagen que dice si trae pgsql
function docker_pg_dockerfile() {
    [ -n "$(docker_pg_versions)" ] && echo 'LABEL nexum.pgsql="1"'
    return 0
}

# ¿Le falta pgsql a la imagen de PHP <versión>, con alguna PostgreSQL?
function docker_php_needs_pgsql() {
    [ -n "$(docker_pg_versions)" ] \
        && [ "$(dk image inspect --format '{{index .Config.Labels "nexum.pgsql"}}' "nexum-php:$1" 2> /dev/null)" != 1 ]
}

# Rehace ya las imágenes de PHP que hay y no traen pgsql (con lo ya descargado) y vuelve a crear los
# contenedores en marcha de sus proyectos
function docker_pg_rebuild() {
    local v slug dir running vs=() fail=0
    for v in $DOCKER_PHP_VERSIONS; do
        dk image inspect "nexum-php:$v" > /dev/null 2>&1 && docker_php_needs_pgsql "$v" && vs+=("$v")
    done
    [ ${#vs[@]} -eq 0 ] && return 0
    echo "Las imágenes de PHP de Docker se rehacen con pgsql y pdo_pgsql (unos minutos cada una): ${vs[*]}"
    for v in "${vs[@]}"; do
        docker_php_image "$v" --rehacer || { echo "No se ha podido rehacer la imagen de PHP $v: sigue sin pgsql"; fail=1; }
    done
    for slug in $(docker_projects); do
        dir=$DOCKER_DIR/$slug
        running=$(dk ps --filter "label=com.docker.compose.project=nexum-$slug" --format '{{.Label "com.docker.compose.service"}}' 2> /dev/null)
        [ -n "$running" ] || continue
        # shellcheck disable=SC2086
        dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d $running > /dev/null || fail=1
    done
    dk image prune -f > /dev/null 2>&1
    return $fail
}
