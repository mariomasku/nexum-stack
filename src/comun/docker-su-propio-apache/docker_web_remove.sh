# docker-php-quitar <nombre> <php>: quita una version de PHP de un proyecto (su contenedor, su
# configuracion y su dominio). La ultima no: para eso, borrar el proyecto de Docker
function docker_web_remove() {
    local slug=$1 php=$2 dir list rest dom
    docker_web_project "$slug" || { echo "No hay ningun proyecto en Docker (con el Apache de Docker) con el nombre $slug"; return 1; }
    dir=$DOCKER_DIR/$slug
    list=$(docker_conf "$slug" PHP)
    [[ " $list " == *" $php "* ]] || { echo "$slug no tiene PHP $php"; return 1; }
    rest=$(tr ' ' '\n' <<< "$list" | grep -vxF "$php" | tr '\n' ' ' | sed 's/ $//')
    [ -n "$rest" ] || { echo "PHP $php es la unica version de $slug: para quitarla, borra el proyecto de Docker"; return 1; }
    dom=$(docker_web_domain "$slug" "$php")
    echo "$slug: se quita PHP $php (la carpeta y la BBDD se quedan)"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] fuera el contenedor $(docker_web_container "$slug" "$php")"
        return 0
    fi
    docker_dns_on || sudo_first || return 1
    if [ "$(docker_conf "$slug" TIPO)" == ps ] && [ "$(docker_conf "$slug" ACTIVA)" == "$php" ]; then
        docker_web_switch "$slug" "${rest%% *}" || return 1
    fi
    dk compose --project-directory "$dir" -f "$dir/compose.yaml" rm -sf "php${php//./}" > /dev/null 2>&1
    dk volume rm "nexum-${slug}_cache-${php//./}" > /dev/null 2>&1
    rm -f "$dir/config-${php//./}.php"
    docker_conf_set "$slug" PHP "$rest" && docker_web_compose "$slug" || return 1
    # (la que se enseña como suya, si era esa: la siguiente)
    if [ "$(docker_conf "$slug" ACTIVA)" == "$php" ]; then
        docker_conf_set "$slug" ACTIVA "${rest%% *}" && docker_conf_set "$slug" DOMINIO "$(docker_web_domain "$slug" "${rest%% *}")"
    fi
    [ "$(docker_conf "$slug" TIPO)" == ps ] || docker_web_hosts quitar "$dom"
    docker_web_reload
    echo "Listo: $slug sigue con PHP $rest"
}

