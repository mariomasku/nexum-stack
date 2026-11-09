# Servicios que van en marcha: todas las versiones o, en una tienda, la elegida
function docker_web_services() {
    local v
    if [ "$(docker_conf "$1" TIPO)" == ps ]; then
        v=$(docker_conf "$1" ACTIVA)
        echo "php${v//./}"
    else
        for v in $(docker_conf "$1" PHP); do echo "php${v//./}"; done
    fi
}

# Cambia una clave de proyecto.conf
function docker_conf_set() {
    local f=$DOCKER_DIR/$1/proyecto.conf
    [ -f "$f" ] && [ ! -L "$f" ] || return 1
    awk -F= -v k="$2" -v v="$3" 'BEGIN { done = 0 } $1 == k { print k "=" v; done = 1; next } { print } END { if (!done) print k "=" v }' \
        "$f" > "$f.nuevo" && chmod 600 "$f.nuevo" && mv -f "$f.nuevo" "$f"
}

# Tienda PrestaShop en la MariaDB comun: su dominio pasa a ser el de Docker (la BBDD es una copia)
function docker_web_ps_domain() {
    local slug=$1 v db dom prefix
    v=$(docker_conf "$slug" MARIADB) db=$(docker_conf "$slug" BBDD)
    dom=$(docker_web_domain "$slug" "")
    [ "$(docker_web_get HTTPS)" == 443 ] || dom+=":$(docker_web_get HTTPS)"
    prefix=$(docker_maria_sql "$v" -N -e "SELECT LEFT(table_name, LENGTH(table_name) - 8) FROM information_schema.tables
        WHERE table_schema = '$db' AND table_name LIKE '%shop\\_url' AND table_type = 'BASE TABLE' LIMIT 1" < /dev/null 2> /dev/null | tr -d '\r')
    [[ "$prefix" =~ ^[A-Za-z0-9_]+$ ]] || return 0
    # (el de produccion, para traer de alli sus imagenes: ps-imagenes)
    local prod
    prod=$(docker_maria_sql "$v" -N -e "SELECT domain FROM \`$db\`.\`${prefix}shop_url\` ORDER BY main DESC, active DESC, id_shop_url LIMIT 1" \
        < /dev/null 2> /dev/null | tr -d '\r' | tr 'A-Z' 'a-z')
    prod=${prod%%:*}
    if valid_domain "$prod" && [[ "$prod" != *.docker.local && "$prod" != *.docker.test && "$prod" != *.local ]]; then
        docker_conf_set "$slug" PRODUCCION "$prod"
    fi
    echo "Tienda PrestaShop: su dominio pasa a $dom en la BBDD de Docker"
    docker_maria_sql "$v" "$db" << EOF
UPDATE \`${prefix}shop_url\` SET domain = '$dom', domain_ssl = '$dom';
UPDATE \`${prefix}configuration\` SET value = '$dom' WHERE name IN ('PS_SHOP_DOMAIN', 'PS_SHOP_DOMAIN_SSL');
UPDATE \`${prefix}configuration\` SET value = '1' WHERE name IN ('PS_SSL_ENABLED', 'PS_SSL_ENABLED_EVERYWHERE');
EOF
}

