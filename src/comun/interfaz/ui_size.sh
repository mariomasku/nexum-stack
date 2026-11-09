# Tamano de la ventana ajustado al contenido: ui_size "texto" [ancho de la lista] [elementos de la lista]
function ui_size() {
    local text=$1 list_w=${2:-0} items=${3:-0}
    local cols=$(tput cols 2> /dev/null || echo 80)
    local lines=$(tput lines 2> /dev/null || echo 24)
    local longest=0 text_lines=0 line

    while IFS= read -r line; do
        (( ${#line} > longest )) && longest=${#line}
    done <<< "$(echo -e "$text")"

    W=$(( longest + 4 > list_w ? longest + 4 : list_w ))
    (( W < 60 )) && W=60
    (( W > cols - 2 )) && W=$(( cols - 2 ))

    # Lineas que ocupa el texto, contando las que whiptail parte por no caber
    while IFS= read -r line; do
        text_lines=$(( text_lines + (${#line} > W - 4 ? (${#line} + W - 5) / (W - 4) : 1) ))
    done <<< "$(echo -e "$text")"

    # La lista ocupa como minimo 3 lineas
    H=$(( text_lines + (items > 0 && items < 3 ? 3 : items) + 7 ))
    SCROLL=()
    (( H > lines - 2 )) && SCROLL=(--scrolltext)
    (( H > lines - 2 )) && H=$(( lines - 2 ))
    L=$(( H - text_lines - 7 ))
    (( L > items )) && L=$items
    (( L < 3 )) && L=3
}

# Rellena con espacios hasta el ancho indicado (el printf de bash cuenta bytes, no caracteres)
function pad() {
    local text=$1 width=$2

    printf '%s%*s' "$text" $(( width > ${#text} ? width - ${#text} : 0 )) ""
}

# fmt_row "anchos" campo [campo ...]: fila de una tabla con columnas de ancho fijo
function fmt_row() {
    local widths=($1) row="" i=0 field
    shift

    for field in "$@"; do
        row+=$(pad "$field" "${widths[i]:-0}")
        i=$((i + 1))
    done

    echo "$row"
}

