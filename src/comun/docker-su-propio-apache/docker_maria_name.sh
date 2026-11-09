# Nombres de lo comun: la MariaDB de una version (nexum-mariadb-11-8) y el contenedor de PHP de una
# version de un proyecto (nexum-<proyecto>-php83)
function docker_maria_name() {
    echo "nexum-mariadb-${1//./-}"
}
function docker_web_container() {
    echo "nexum-$1-php${2//./}"
}

# ¿Es un proyecto del sistema nuevo (con el Apache de Docker)?
function docker_web_project() {
    docker_valid_slug "$1" && [ "$(docker_conf "$1" MODO)" == web ]
}

# Dominio de una version de PHP de un proyecto: el de la tienda (uno solo) o <proyecto>-php83.docker.local
function docker_web_domain() {
    if [ "$(docker_conf "$1" TIPO)" == ps ]; then
        echo "$1.$(docker_web_tld)"
    else
        echo "$1-php${2//./}.$(docker_web_tld)"
    fi
}

# Dominios de un proyecto (todas sus versiones)
function docker_web_domains() {
    local v
    for v in $(docker_conf "$1" PHP); do docker_web_domain "$1" "$v"; done | awk '!seen[$0]++'
}

# Proyectos del sistema nuevo
function docker_web_projects() {
    local p
    for p in $(docker_projects); do
        [ "$(docker_conf "$p" MODO)" == web ] && echo "$p"
    done
}

# La red interna de Docker que comparten el Apache, las MariaDB y los PHP (sin puertos fuera)
function docker_net() {
    dk network inspect nexum > /dev/null 2>&1 || dk network create nexum > /dev/null
}

# SQL como root en la MariaDB comun de una version: docker_maria_sql <version> [argumentos de mariadb].
# La contraseña no va en ninguna orden (se ve en ps): el cliente la toma dentro del contenedor
function docker_maria_sql() {
    local v=$1
    shift
    dk exec -i "$(docker_maria_name "$v")" \
        sh -c 'MYSQL_PWD=$MARIADB_ROOT_PASSWORD exec $(command -v mariadb || command -v mysql) -uroot "$@"' mariadb "$@"
}

# La MariaDB comun de una version: la crea (su compose.yaml y su contraseña de root al azar, en
# ficheros solo tuyos) si no existe, la arranca y espera a que responda
function docker_maria_up() {
    local v=$1 name dir i
    [[ " $DOCKER_MARIADB_VERSIONS " == *" $v "* ]] || { echo "MariaDB $v no se ofrece en Docker ($DOCKER_MARIADB_VERSIONS)"; return 1; }
    name=$(docker_maria_name "$v") dir=$DOCKER_DIR/mariadb-$v
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] MariaDB $v comun ($name) en marcha"
        return 0
    fi
    if [ ! -f "$dir/compose.yaml" ]; then
        mkdir -p -m 700 "$DOCKER_DIR" "$dir" || return 1
        ( umask 077
          printf 'DB_ROOT_PASS=%s\n' "$(head -c 18 /dev/urandom | base64 | tr -d '/+=\n')" > "$dir/.env"
          { printf 'name: %s\nservices:\n  db:\n    image: mariadb:%s\n    container_name: %s\n    restart: "no"\n' "$name" "$v" "$name"
            printf '    environment:\n      MARIADB_ROOT_PASSWORD: ${DB_ROOT_PASS}\n      MARIADB_AUTO_UPGRADE: "1"\n'
            printf '    command: ["--character-set-server=utf8mb4", "--collation-server=utf8mb4_unicode_ci", "--max-allowed-packet=512M"]\n'
            printf '    volumes:\n      - "datos:/var/lib/mysql"\n    networks: [nexum]\n'
            printf 'volumes:\n  datos:\n    name: %s\n' "$name"
            printf 'networks:\n  nexum:\n    external: true\n    name: nexum\n'; } > "$dir/compose.yaml" ) || return 1
    fi
    docker_net || return 1
    dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d || return 1
    for i in $(seq 90); do
        docker_maria_sql "$v" -e "SELECT 1" < /dev/null > /dev/null 2>&1 && return 0
        sleep 1
    done
    echo "La MariaDB $v de Docker no responde (mira sus registros en la pestaña Docker)"
    return 1
}

# MariaDB comunes que hay (sus versiones)
function docker_maria_versions() {
    local d
    for d in "$DOCKER_DIR"/mariadb-*/; do
        d=$(basename "$d")
        d=${d#mariadb-}
        [[ " $DOCKER_MARIADB_VERSIONS " == *" $d "* ]] && [ -f "$DOCKER_DIR/mariadb-$d/compose.yaml" ] && echo "$d"
    done
}

