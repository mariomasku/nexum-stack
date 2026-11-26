# Tienda con la BBDD de una version en vivo (la misma que web.local): su BBDD no se toca, asi que sigue en su
# dominio de verdad (DOMINIO_TIENDA). Al vhost del Apache de Docker:
#   - la peticion llega con ese dominio (Host, antes que nada): PrestaShop se ve en su casa y las reglas de
#     su .htaccess atadas a %{HTTP_HOST} (las de las imagenes) funcionan. El vhost sigue siendo el de
#     Docker (por el nombre del certificado: sin 421)
#   - en lo que devuelve, su dominio pasa al de Docker: en el texto (tambien escapado, \/\/, y codificado,
#     %2F%2F), en las redirecciones y en el domain= de sus cookies. Sin comprimir (Accept-Encoding fuera):
#     el cambio se hace sobre el texto tal cual
# docker_web_ps_live <nombre> <dominio de Docker de esa version>
function docker_web_ps_live() {
    local slug=$1 dom=$2 real base esc to
    [ "$(docker_conf "$slug" TIPO)" == ps ] && [ -n "$(docker_conf "$slug" LAMPP_BD)" ] || return 0
    real=$(docker_conf "$slug" DOMINIO_TIENDA)
    valid_domain "$real" || return 0
    base=${real#www.}
    # (el dominio entero: no el principio de otro, como tienda.es.otra.com o tienda.esp)
    esc="${base//./\\.}(?![A-Za-z0-9-]|\\.[A-Za-z0-9])"
    to=$(docker_web_url "$dom")
    to=${to#https://}
    printf '    # (tienda en vivo: llega con su dominio, %s, y lo que devuelve sale con el de Docker)\n' "$real"
    printf '    RequestHeader set Host "%s" early\n    RequestHeader unset Accept-Encoding early\n' "$real"
    printf '    AddOutputFilterByType SUBSTITUTE text/html text/css text/plain text/xml application/xml application/json application/javascript text/javascript application/ld+json\n'
    printf '    SubstituteMaxLineLength 64m\n'
    # (Apache deja \\ en \ dentro de las comillas: \\\\/ en el fichero es \\/ en la regex, la barra escapada)
    printf '    Substitute "s#(//|\\\\\\\\/\\\\\\\\/|%%2F%%2F)(www\\.)?%s#$1%s#iq"\n' "$esc" "$to"
    printf '    Header edit Location "(?i)^https?://(www\\.)?%s" "https://%s"\n' "$esc" "$to"
    printf '    Header always edit Location "(?i)^https?://(www\\.)?%s" "https://%s"\n' "$esc" "$to"
    printf '    Header edit* Set-Cookie "(?i)domain=\\.?(www\\.)?%s" "domain=%s"\n' "$esc" "$dom"
    printf '    Header always edit* Set-Cookie "(?i)domain=\\.?(www\\.)?%s" "domain=%s"\n' "$esc" "$dom"
}

# La BBDD de un proyecto, en marcha: la de su version en vivo (su MariaDB y su puente) o la MariaDB comun
function docker_web_db_up() {
    local f
    f=$(docker_conf "$1" LAMPP_BD)
    if [ -n "$f" ]; then
        lampp_bd_up "$f" && lampp_bd_bridge_up "$f"
    else
        docker_maria_up "$(docker_conf "$1" MARIADB)"
    fi
}
