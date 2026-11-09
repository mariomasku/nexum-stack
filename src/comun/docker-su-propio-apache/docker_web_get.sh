# Direccion (IP) y puertos (HTTP, HTTPS) del Apache de Docker. Siempre de 127.x: nunca abiertos a la red
function docker_web_get() {
    local v def
    case $1 in IP) def=127.0.0.2 ;; HTTP) def=80 ;; HTTPS) def=443 ;; TLD) def=docker.local ;; DNS) def=0 ;; *) return 1 ;; esac
    v=$(awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$DOCKER_WEB_FILE" 2> /dev/null)
    case $1 in
        IP) docker_web_valid_ip "$v" || v=$def ;;
        TLD) [ "$v" == docker.test ] || v=$def ;;
        DNS) [ "$v" == 1 ] || v=$def ;;
        *) [[ "$v" =~ ^[1-9][0-9]{0,4}$ ]] && [ "$v" -le 65535 ] || v=$def ;;
    esac
    echo "$v"
}

# Guarda web.conf (solo tuyo): docker_web_conf_write <ip> <http> <https> <tld> <dns>
function docker_web_conf_write() {
    mkdir -p -m 700 "$DOCKER_DIR" || return 1
    ( umask 077; printf 'IP=%s\nHTTP=%s\nHTTPS=%s\nTLD=%s\nDNS=%s\n' "$@" > "$DOCKER_WEB_FILE.nuevo" ) \
        && mv -f "$DOCKER_WEB_FILE.nuevo" "$DOCKER_WEB_FILE"
}

# Final de los dominios del Apache de Docker: docker.local (en /etc/hosts, uno a uno) o, con el DNS
# comodin, docker.test. .local es de mDNS: un DNS para *.docker.local no se consultaria
function docker_web_tld() {
    docker_web_get TLD
}

# ¿Va el DNS comodin de *.docker.test? (sus dominios ya no van en /etc/hosts)
function docker_dns_on() {
    [ "$(docker_web_get DNS)" == 1 ] && [ "$(docker_web_get TLD)" == docker.test ]
}

# Dominio de phpMyAdmin
function docker_web_pma() {
    echo "pma.$(docker_web_tld)"
}

function docker_web_valid_ip() {
    [[ "$1" =~ ^127\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] \
        && [ "${BASH_REMATCH[1]}" -le 255 ] && [ "${BASH_REMATCH[2]}" -le 255 ] && [ "${BASH_REMATCH[3]}" -le 254 ] \
        && [ "${BASH_REMATCH[3]}" -ge 1 ]
}

# Direccion de una web del Apache de Docker: https://<dominio>, con el puerto si no es el 443
function docker_web_url() {
    local port=$(docker_web_get HTTPS)
    echo "https://$1$([ "$port" == 443 ] || echo ":$port")"
}

