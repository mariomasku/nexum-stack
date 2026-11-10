# ¿Va a necesitar sudo importar-bd? Solo habla con el MariaDB en marcha (con la version parada no carga
# nada), salvo al cargarla para una tienda PrestaShop (--proyecto) cuya var/cache tiene ficheros de otro
# usuario (los que creo Apache): ps_clear_cache los borra con sudo. import_need_root <opciones de importar-bd>
function import_need_root() {
    local project=""
    while [ $# -gt 0 ]; do
        [ "$1" == --proyecto ] && project=${2%/}
        shift
    done
    [ -n "$project" ] && valid_project "$project" > /dev/null 2>&1 && is_prestashop "$project" 2> /dev/null || return 1
    find "$HTDOCS_DIR/$project/var/cache" -mindepth 1 ! -user "$(id -un)" -print -quit 2> /dev/null | grep -q .
}
