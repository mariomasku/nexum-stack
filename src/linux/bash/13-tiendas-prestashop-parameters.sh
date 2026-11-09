#@incluir comun/tiendas-prestashop-parameters/is_prestashop.sh
# vaciar-cache <carpeta>: borra el contenido de var/cache de una tienda (PrestaShop 1.7 la usa para
# Symfony y da error 500 con la de otro equipo). Si no tiene var/cache no hace nada.
function ps_clear_cache() {
    local folder=${1%/} cache s=""
    valid_project "$folder" || return 1
    cache=$HTDOCS_DIR/$folder/var/cache
    if [ ! -d "$cache" ]; then
        echo "$folder no tiene la carpeta var/cache: no hay cache que vaciar"

        return 0
    fi
    # var y var/cache tienen que estar dentro de la tienda: si fueran enlaces a otra carpeta (por
    # ejemplo a /var), con sudo se vaciaria la del sistema
    if [ -L "$HTDOCS_DIR/$folder/var" ] || [ -L "$cache" ] \
        || [ "$(readlink -f "$cache")" != "$(readlink -f "$HTDOCS_DIR/$folder")/var/cache" ]; then
        echo "var/cache de $folder es un enlace a otra carpeta: no se vacia"

        return 1
    fi
    # Los ficheros que creo Apache como daemon (antes de User/Group) solo se borran con sudo
    find "$cache" -mindepth 1 ! -user "$(id -un)" -print -quit 2> /dev/null | grep -q . && s=sudo
    echo "Vaciando la cache de $folder (var/cache)..."
    # Con sudo, root abre var/cache carpeta a carpeta sin seguir enlaces y borra desde ahi: si entre
    # la comprobacion y el borrado cambian var por un enlace (a /var), falla en lugar de vaciar otra
    if [ -n "$s" ]; then
        run $s python3 -I -c "$CACHE_CLEAR_PY" "$cache" "$HTDOCS_DIR"
    else
        run find "$cache" -mindepth 1 -delete
    fi || { echo "No se ha podido vaciar $cache"; return 1; }
    echo "Cache de $folder vaciada"
}

#@incluir comun/tiendas-prestashop-parameters/ps_clear_cache_db.sh
