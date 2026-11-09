# Vuelve a escribir la configuracion del Apache de Docker y, si esta en marcha, la recarga sin cortar las
# conexiones (si Apache no la acepta, lo dice y sigue con la de antes)
function docker_web_reload() {
    local out
    [ "$DRY" -eq 1 ] && return 0
    [ "$1" == --sin-escribir ] || docker_web_write || return 1
    [ "$(docker_web_state)" == marcha ] || return 0
    if ! out=$(dk exec nexum-web httpd -f "$DOCKER_WEB_CONF" -t 2>&1); then
        echo "El Apache de Docker no acepta su configuracion nueva: sigue con la de antes"
        sed 's/^/  /' <<< "$out" | tail -5
        return 1
    fi
    dk exec nexum-web httpd -f "$DOCKER_WEB_CONF" -k graceful > /dev/null 2>&1
}

