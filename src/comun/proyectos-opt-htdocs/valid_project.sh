# Carpeta de proyecto valida: existe en htdocs, no es un enlace y su nombre solo lleva letras sin
# acentos, numeros, espacios, punto, _ y - (se escribe entre comillas en los vhosts: unas comillas
# o un salto de linea en el nombre meterian directivas en la configuracion de Apache)
function valid_project() {
    local folder=$1 rx='^[A-Za-z0-9_][A-Za-z0-9 ._-]*$'
    if [ -z "$folder" ] || [ ! -d "$HTDOCS_DIR/$folder" ] || [ -L "$HTDOCS_DIR/$folder" ] || [[ "$folder" == */* ]]; then
        echo "No existe el proyecto $HTDOCS_DIR/$folder"

        return 1
    fi
    if ! [[ "$folder" =~ $rx ]]; then
        echo "El nombre de la carpeta $folder lleva caracteres que no se admiten (solo letras sin"
        echo "acentos, numeros, espacios, punto, _ y -). Cambiale el nombre y vuelve a intentarlo."

        return 1
    fi
}

