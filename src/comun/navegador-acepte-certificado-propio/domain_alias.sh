# Alias del dominio: www.dominio, o el dominio sin www si ya lo lleva
function domain_alias() {
    if [[ "$1" == www.* ]]; then echo "${1#www.}"; else echo "www.$1"; fi
}

# Dominio de una tienda PrestaShop. Primero el de su base (tabla shop_url, tienda principal), que es
# al que redirige; si la base no se puede leer (MariaDB parado o root con contraseña), el ServerName
# del vhost que ya apunte a la carpeta.
function ps_domain() {
    local folder=$1 config db prefix domain
    config=$(ps_config "$folder")
    db=${config%%|*} prefix=${config#*|}
    if [ -n "$db" ] && [[ "$db$prefix" =~ ^[A-Za-z0-9_-]+$ ]] && [ -x "$DB_CLIENT" ] \
            && db_base_table root "${MYSQL_PWD:-}" "$db" "${prefix}shop_url"; then
        # Si MariaDB se acaba de arrancar (cambio de version), se le dan unos segundos
        for _ in 1 2 3 4 5 6; do
            domain=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT domain FROM \`$db\`.\`${prefix}shop_url\` ORDER BY main DESC, active DESC, id_shop_url LIMIT 1" < /dev/null 2>&1) && break
            [[ "$domain" == *"Can't connect"* ]] && [ "$DRY" -eq 0 ] || break
            sleep 1
        done
        domain=$(tr 'A-Z' 'a-z' <<< "${domain%%:*}")
        valid_domain "$domain" && echo "$domain" && return 0
    fi
    domain=$(vhosts_info | awk -F'|' -v f="$folder" -v l="$(project_link)" '$2 == f && $3 != l { print $3; exit }')
    [ -n "$domain" ] && echo "$domain"
}

# ¿Hay ya un vhost con ese dominio que apunte a la carpeta?
function vhost_points_to() {
    vhosts_info | awk -F'|' -v d="$1" -v f="$2" '$3 == d && $2 == f { found = 1 } END { exit !found }'
}

# ¿Se parece el dominio a la carpeta? Su nombre registrable (lo de antes de la terminacion:
# mitienda en www.mitienda.com, ejemplo en tienda.ejemplo.com, cliente en
# cliente.com.es), de 4 letras o mas, va en el nombre de la carpeta sin sus palabras genericas
# (dob, prestashop, wordpress...): asi prestashop.com no vale para dob-prestashop-x
function domain_fits_folder() {
    local domain=${1#www.} folder label w n parts
    folder=$(tr 'A-Z' 'a-z' <<< "$2")
    for w in dob prestashop wordpress tienda shop html php web wp ps; do folder=${folder//$w/}; done
    folder=$(tr -d '._-' <<< "$folder")
    IFS=. read -r -a parts <<< "$(tr 'A-Z' 'a-z' <<< "$domain")"
    n=${#parts[@]}
    (( n >= 2 )) || return 1
    label=${parts[n-2]}
    if (( n >= 3 )) && [[ "$label" =~ ^(com|co|org|net|gob|edu|ac|nom)$ ]]; then label=${parts[n-3]}; fi
    label=$(tr -d '_-' <<< "$label")
    [ ${#label} -ge 4 ] && [[ "$folder" == *"$label"* ]]
}

# ¿Es <tabla> de <base> una tabla de verdad (no una vista, que podria ejecutar funciones del volcado
# con los permisos de quien la lee)? db_base_table <usuario> <contraseña> <base> <tabla>
function db_base_table() {
    local n
    if [ -n "$2" ]; then
        n=$(MYSQL_PWD=$2 "${DB_SAFE[@]}" "$DB_CLIENT" -u"$1" -N -e "SELECT COUNT(*) FROM information_schema.TABLES
            WHERE TABLE_SCHEMA='$3' AND TABLE_NAME='$4' AND TABLE_TYPE='BASE TABLE'" < /dev/null 2> /dev/null)
    else
        n=$(env -u MYSQL_PWD "${DB_SAFE[@]}" "$DB_CLIENT" -u"$1" -N -e "SELECT COUNT(*) FROM information_schema.TABLES
            WHERE TABLE_SCHEMA='$3' AND TABLE_NAME='$4' AND TABLE_TYPE='BASE TABLE'" < /dev/null 2> /dev/null)
    fi
    [ "$n" == 1 ]
}

