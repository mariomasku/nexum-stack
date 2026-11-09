function media_saved() {
    awk -F'|' -v f="$1" '$1 == f { d = $2 } END { if (d != "") print d }' "$MEDIA_PROJECTS_FILE" 2> /dev/null
}

# media-proyecto <carpeta> <dominio de produccion>|quitar: lo que le falte a un WordPress de
# wp-content/uploads se pide a su web real mientras este cargado (por web.local, que es un .local:
# sin bucles). Las tiendas PrestaShop se ven con su dominio real falseado: para ellas, ps-imagenes
function media_project() {
    local folder=${1%/} prod=$(tr 'A-Z' 'a-z' <<< "$2") rest
    if [ -z "$folder" ] || [ -z "$prod" ]; then
        echo "Uso: lvm-instalador media-proyecto <carpeta> <dominio de produccion>|quitar"

        return 1
    fi
    valid_project "$folder" || return 1
    if is_prestashop "$folder"; then
        echo "$folder es una tienda PrestaShop: se ve con su dominio real falseado y una redireccion volveria"
        echo "a este equipo. Descarga las imagenes que faltan: lvm-instalador ps-imagenes $folder"

        return 1
    fi
    if [ "$prod" != quitar ]; then
        prod=${prod#https://}; prod=${prod#http://}; prod=${prod%/}
        if ! valid_domain "$prod" || [[ "$prod" == *.local || "$prod" == localhost || "$prod" == *.localhost ]]; then
            echo "El dominio de produccion no es valido: $prod (solo el dominio, como ejemplo.com)"

            return 1
        fi
    fi
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $folder: $([ "$prod" == quitar ] && echo "se olvida su dominio de produccion" || echo "imagenes de $prod") en $MEDIA_PROJECTS_FILE"
    else
        mkdir -p -m 700 "$(dirname "$MEDIA_PROJECTS_FILE")" || return 1
        rest=$(awk -F'|' -v f="$folder" '$1 != f' "$MEDIA_PROJECTS_FILE" 2> /dev/null)
        [ "$prod" != quitar ] && rest+=$'\n'"$folder|$prod"
        ( umask 077; sed '/^$/d' <<< "$rest" > "$MEDIA_PROJECTS_FILE" ) || return 1
    fi
    if [ "$prod" == quitar ]; then
        echo "$folder ya no pide a produccion las imagenes que le faltan"
    else
        echo "$folder pide a https://$prod las imagenes que le falten en wp-content/uploads (mientras este cargado"
        echo "y, si esta en el Apache de Docker, tambien alli)"
    fi
    media_sync
    # (en el Apache de Docker, en sus vhosts: se rehacen y se recargan)
    local p
    for p in $(docker_web_projects 2> /dev/null); do
        if [ "$(docker_conf "$p" CARPETA)" == "$folder" ] && [ "$DRY" -eq 0 ]; then
            docker_web_reload || echo "Aviso: el Apache de Docker no ha recargado su configuracion"
            break
        fi
    done
}

