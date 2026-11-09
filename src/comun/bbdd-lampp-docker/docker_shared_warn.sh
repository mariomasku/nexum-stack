# Aviso al parar algo comun (una MariaDB comun, el Apache de Docker o su phpMyAdmin) que usa algun
# proyecto en marcha: cuales se quedan sin el
function docker_shared_warn() {
    local name=$1 up p v="" users=() lampp=""
    if [[ "$name" =~ ^nexum-lampp-bd-([0-9]{1,2})-([0-9]{1,2})(-([0-9]{1,3}))?$ ]]; then
        lampp=${BASH_REMATCH[1]}.${BASH_REMATCH[2]}${BASH_REMATCH[4]:+.${BASH_REMATCH[4]}} v=x
    else
        [[ "$name" =~ ^nexum-(web|pma|mariadb-([0-9]{1,2})-([0-9]{1,2}))$ ]] || return 0
        [ -n "${BASH_REMATCH[2]}" ] && v=${BASH_REMATCH[2]}.${BASH_REMATCH[3]}
    fi
    up=$(dk ps --format '{{.Names}}' 2> /dev/null) || return 0
    for p in $(docker_web_projects); do
        if [ -n "$lampp" ]; then
            [ "$(docker_conf "$p" LAMPP_BD)" == "$lampp" ] || continue
        elif [ -n "$v" ] && { [ "$(docker_conf "$p" MARIADB)" != "$v" ] || [ -n "$(docker_conf "$p" LAMPP_BD)" ]; }; then
            continue
        fi
        grep -qE "^nexum-$p-php[0-9]{2}\$" <<< "$up" && users+=("$(docker_conf "$p" CARPETA)")
    done
    [ ${#users[@]} -eq 0 ] && return 0
    echo "Aviso: $name es comun y lo usan ahora: ${users[*]}. $([ -n "$v" ] && echo "Se quedan sin BBDD" || echo "Dejan de verse") hasta que lo arranques"
}

# docker-parar-todo: todos los contenedores de Nexum en marcha (los de los proyectos, las MariaDB
# comunes, el Apache de Docker y su phpMyAdmin), parados. Los de otros programas no se tocan
function docker_stop_all() {
    local up names=()
    up=$(dk ps --format '{{.Names}}' 2> /dev/null) || { echo "Docker no responde"; return 1; }
    mapfile -t names < <(grep -E '^nexum-([a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?-((php|db|pma)-[0-9]{1,3}|php[0-9]{2})|web|pma|mariadb-[0-9]{1,2}-[0-9]{1,2}|lampp-bd-[0-9]{1,2}-[0-9]{1,2}(-[0-9]{1,3})?)$' <<< "$up")
    if [ ${#names[@]} -eq 0 ]; then
        echo "No hay ningun contenedor de Nexum en marcha"
        return 0
    fi
    echo "Parando ${#names[@]} contenedores de Nexum: ${names[*]}"
    run dk stop "${names[@]}" > /dev/null || return 1
    # (y la MariaDB de LAMPP que hubiera arrancado Docker para alguno)
    local f
    # shellcheck disable=SC2045  # (nombres de versión ya comprobados, sin espacios)
    for f in $(ls "$LAMPP_BD_MARK_DIR" 2> /dev/null); do valid_version_name "$f" && lampp_bd_release "$f"; done
    echo "Todos parados"
}

