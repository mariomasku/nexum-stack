# Nombres repartidos en columnas que caben en el ancho indicado
function columns() {
    local width=${1:-72} names=() name longest=0

    while IFS= read -r name; do
        [ -z "$name" ] && continue
        names+=("$name")
        (( ${#name} > longest )) && longest=${#name}
    done

    [ ${#names[@]} -eq 0 ] && return 0

    local col_w=$(( longest + 3 ))
    local ncols=$(( width / col_w ))
    (( ncols < 1 )) && ncols=1
    local nrows=$(( (${#names[@]} + ncols - 1) / ncols ))
    local r c line

    # Orden por columnas (de arriba abajo), como ls
    for (( r = 0; r < nrows; r++ )); do
        line=""
        for (( c = 0; c < ncols; c++ )); do
            local i=$(( c * nrows + r ))
            [ $i -lt ${#names[@]} ] && line+=$(pad "${names[i]}" $col_w)
        done
        echo "  ${line%"${line##*[! ]}"}"
    done
}

