# Para el boton de la pestaña Bases de datos: la carpeta de la tienda de una base (la recordada, o
# la unica cuya configuracion la usa, o la unica cuyo nombre acaba como la base sin ps_)
function ps_clear_cache_db() {
    local db=$1 folder="" tail
    [[ "$db" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Base de datos no valida: $db"; return 1; }
    folder=$(linked_folder "$db")
    if [ -z "$folder" ] || [ ! -d "$HTDOCS_DIR/$folder" ]; then
        folder=$(gui_projects | awk -F'|' -v d="$db" '$1 == "P" && $3 == d { print $2 }')
        if [ "$(grep -c . <<< "$folder")" != 1 ]; then
            tail=$(tr 'A-Z' 'a-z' <<< "${db#ps_}")
            folder=$(gui_projects | awk -F'|' -v t="$tail" '$1 == "P" { n = tolower($2); if (n == t || substr(n, length(n) - length(t)) ~ ("[-.]" t "$")) print $2 }')
        fi
    fi
    if [ -z "$folder" ] || [ "$(grep -c . <<< "$folder")" != 1 ]; then
        echo "No se sabe cual es la carpeta de la tienda de $db. Cargala una vez con Cargar proyecto"
        echo "(se recuerda) o usa: nexum vaciar-cache <carpeta>"

        return 1
    fi
    ps_clear_cache "$folder"
}

# Primera carga de una tienda en este equipo (o parameters.php nuevo): vacia su cache y la apunta
function ps_first_load() {
    local folder=$1
    if [ "$PS_NEW_PARAMS" != 1 ] && [ -f "$PS_LOADED_FILE" ] && grep -qxF "$folder" "$PS_LOADED_FILE"; then
        return 0
    fi
    grep -qxF "$folder" "$PS_LOADED_FILE" 2> /dev/null || echo "Primera carga de la tienda $folder en este equipo"
    ps_clear_cache "$folder" || return 0
    [ "$DRY" -eq 1 ] && return 0
    grep -qxF "$folder" "$PS_LOADED_FILE" 2> /dev/null && return 0
    mkdir -p "$(dirname "$PS_LOADED_FILE")" && echo "$folder" >> "$PS_LOADED_FILE"
}

