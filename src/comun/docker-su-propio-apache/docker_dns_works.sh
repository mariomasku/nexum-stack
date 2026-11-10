# ¿Contesta el DNS comodin? (como lo buscan los navegadores: con el sistema)
function docker_dns_works() {
    local ip got i
    ip=$(docker_web_get IP)
    for i in $(seq 20); do
        got=$(python3 -I -c 'import socket, sys
try:
    print(socket.getaddrinfo(sys.argv[1], None, socket.AF_INET)[0][4][0])
except OSError:
    pass' "nexum-comprobacion.docker.test" 2> /dev/null)
        [ "$got" == "$ip" ] && return 0
        sleep 0.5
    done
    return 1
}

# docker_web_retld: los proyectos del Apache de Docker con el final de los dominios de ahora (docker_web_tld):
# su dominio, su configuracion de cada version (WordPress: WP_HOME), el dominio de una tienda en su BBDD y
# sus contenedores de PHP en marcha, rehechos (su configuracion va montada fichero a fichero)
function docker_web_retld() {
    local p state
    for p in $(docker_web_projects); do
        docker_conf_set "$p" DOMINIO "$(docker_web_domain "$p" "$(docker_conf "$p" ACTIVA)")" || return 1
        for v in $(docker_conf "$p" PHP); do
            docker_web_config "$p" "$v" || return 1
        done
        docker_web_compose "$p" || return 1
        if docker_ready; then
            if [ "$(docker_conf "$p" TIPO)" == ps ] && docker_maria_up "$(docker_conf "$p" MARIADB)" > /dev/null; then
                docker_web_ps_domain "$p"
            fi
            state=$(docker_state "$p")
            if [ "$state" == marcha ] || [ "$state" == parcial ]; then
                dk compose --project-directory "$DOCKER_DIR/$p" -f "$DOCKER_DIR/$p/compose.yaml" up -d --force-recreate \
                    $(docker_web_services "$p") > /dev/null || return 1
            fi
        fi
        echo "  $(docker_conf "$p" CARPETA): $(docker_web_url "$(docker_web_domain "$p" "$(docker_conf "$p" ACTIVA)")")"
    done
}

# docker-web dns activar: pone el DNS comodin y pasa los proyectos del Apache de Docker a *.docker.test
# (sus lineas de /etc/hosts se quitan). Si no contesta, se quita y todo sigue como estaba. Pide la
# contraseña de administrador una vez
function docker_dns_activate() {
    local old p olds=()
    if docker_dns_on && docker_dns_works; then
        echo "El DNS de *.docker.test ya va: los dominios de Docker no van en /etc/hosts"
        return 0
    fi
    echo "DNS de *.docker.test: los dominios de Docker pasan a .docker.test y dejan de ir en /etc/hosts"
    echo "(web.local, los proyectos de siempre y los dominios falseados de las tiendas siguen igual)"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] DNS en 127.0.0.1:$DOCKER_DNS_PORT para *.docker.test y los proyectos de Docker a .docker.test"
        return 0
    fi
    sudo_first || return 1
    docker_dns_install || { echo "No se ha podido poner el DNS de *.docker.test"; docker_dns_uninstall; return 1; }
    if ! docker_dns_works; then
        echo "El DNS de *.docker.test no contesta: se quita y todo sigue como estaba"
        docker_dns_uninstall
        return 1
    fi
    old=$(docker_web_tld)
    if [ "$old" != docker.test ]; then
        olds+=("pma.$old")
        for p in $(docker_web_projects); do
            mapfile -t -O "${#olds[@]}" olds < <(docker_web_domains "$p")
        done
    fi
    docker_web_conf_write "$(docker_web_get IP)" "$(docker_web_get HTTP)" "$(docker_web_get HTTPS)" docker.test 1 || return 1
    if [ "$old" != docker.test ] && [ -n "$(docker_web_projects)" ]; then
        echo "Los proyectos del Apache de Docker pasan a .docker.test:"
        docker_web_retld || return 1
    fi
    [ ${#olds[@]} -gt 0 ] && docker_web_hosts quitar "${olds[@]}"
    if [ -d "$DOCKER_WEB_DIR" ]; then
        docker_web_cert && docker_web_trust
        if docker_ready && [ "$(docker_web_state)" != nuevo ]; then
            docker_web_up || return 1
        else
            docker_web_write
        fi
    fi
    echo "Listo: los proyectos de Docker se abren en $(docker_web_url "<proyecto>.docker.test") y phpMyAdmin en $(docker_web_url "$(docker_web_pma)")"
}

# docker-web dns quitar: sin el DNS comodin. Los dominios siguen siendo .docker.test y vuelven a /etc/hosts
function docker_dns_deactivate() {
    local p domains=()
    echo "Se quita el DNS de *.docker.test: sus dominios vuelven a /etc/hosts"
    [ "$DRY" -eq 1 ] && return 0
    sudo_first || return 1
    docker_web_conf_write "$(docker_web_get IP)" "$(docker_web_get HTTP)" "$(docker_web_get HTTPS)" "$(docker_web_tld)" 0 || return 1
    docker_dns_uninstall
    for p in $(docker_web_projects); do
        mapfile -t -O "${#domains[@]}" domains < <(docker_web_domains "$p")
    done
    [ -d "$DOCKER_WEB_DIR" ] && { docker_web_hosts poner "$(docker_web_pma)" "${domains[@]}" || return 1; }
    echo "Listo: los dominios de Docker van otra vez en /etc/hosts"
}

function docker_dns_command() {
    case $1 in
        activar) docker_dns_activate ;;
        quitar) docker_dns_deactivate ;;
        *) echo "Uso: nexum docker-web dns activar|quitar"; return 1 ;;
    esac
}

