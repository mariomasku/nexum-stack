# ui_list menu|checklist "texto" "opcion por defecto" "cabecera" tag descripcion [tag descripcion ...]
# Con cabecera, las descripciones son filas de una tabla (todas del mismo ancho, ver fmt_row) y se
# ocultan los tags; la cabecera se alinea encima de las columnas.
function ui_list() {
    local kind=$1 text=$2 default=$3 header=$4
    shift 4

    local tags=() descs=() n=0 longest=0 longest_tag=0
    while [ $# -gt 0 ]; do
        tags+=("$1")
        descs+=("$2")
        n=$((n + 1))
        (( ${#1} > longest_tag )) && longest_tag=${#1}
        (( ${#2} > longest )) && longest=${#2}
        shift 2
    done

    if [ "$UI" == "whiptail" ]; then
        local args=() i list_w
        for (( i = 0; i < n; i++ )); do
            args+=("${tags[i]}" "${descs[i]}")
            [ "$kind" == "checklist" ] && args+=(OFF)
        done

        # Ancho que ocupa la lista dentro de la ventana (casillas, tags, marco y barra de desplazamiento)
        local boxes=0
        [ "$kind" == "checklist" ] && boxes=4
        if [ -n "$header" ]; then
            list_w=$(( longest + boxes + 8 ))
        else
            list_w=$(( longest_tag + longest + boxes + 10 ))
        fi

        local help=""
        [ "$kind" == "checklist" ] && help="\n(Espacio = marcar/desmarcar, Intro = aceptar)"

        local full="$text$help"
        [ -n "$header" ] && full+="\n\n$header\n$header"
        ui_size "$full" "$list_w" "$n"

        if [ -n "$header" ]; then
            # El menu centra la lista en la ventana; la lista de casillas empieza siempre en la columna 5
            local indent=5
            [ "$kind" == "menu" ] && indent=$(( (W - 4 - longest) / 2 - 1 ))
            (( n > L )) && [ "$kind" == "menu" ] && indent=$(( (W - 6 - longest) / 2 - 1 ))
            (( indent < 0 )) && indent=0
            local margin=$(printf '%*s' $indent "")
            local rule=$(printf '%*s' ${#header} "" | tr ' ' '-')
            text+="$help\n\n$margin$header\n$margin$rule"
            args=(--notags "${args[@]}")
        else
            text+="$help"
        fi

        if [ "$kind" == "menu" ]; then
            wt --title "$TITLE" --ok-button "Aceptar" --cancel-button "Volver" \
                --default-item "$default" --menu "$text" $H $W $L "${args[@]}" 3>&1 1>&2 2>&3
        else
            wt --title "$TITLE" --separate-output --ok-button "Aceptar" --cancel-button "Volver" \
                --checklist "$text" $H $W $L "${args[@]}" 3>&1 1>&2 2>&3
        fi
        return
    fi

    local i choice
    echo "" >&2
    echo -e "$text" >&2
    if [ -n "$header" ]; then
        echo "" >&2
        echo "      $header" >&2
        echo "      $(printf '%*s' ${#header} "" | tr ' ' '-')" >&2
    fi
    for (( i = 0; i < n; i++ )); do
        local mark=""
        [ "$kind" == "menu" ] && [ "${tags[i]}" == "$default" ] && mark="  (por defecto)"
        printf '  %2d) %s%s\n' $((i + 1)) "${descs[i]}" "$mark" >&2
    done

    if [ "$kind" == "menu" ]; then
        read -p "Numero [Intro = por defecto, v = volver]: " choice >&2

        [ "$choice" == "v" ] && return 1
        if [ -z "$choice" ]; then
            [ -n "$default" ] && echo "$default" && return 0
            return 1
        fi
        [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $n ] || return 1
        echo "${tags[$((choice - 1))]}"
    else
        read -p "Numeros separados por espacios (Intro = volver): " choice >&2
        [ -z "$choice" ] && return 1

        for c in $choice; do
            [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le $n ] && echo "${tags[$((c - 1))]}"
        done
    fi
}

# ui_menu "texto" "opcion por defecto" tag descripcion [tag descripcion ...]
function ui_menu() {
    ui_list menu "$1" "$2" "" "${@:3}"
}

# ui_table_menu "texto" "opcion por defecto" "cabecera" tag fila [tag fila ...]
function ui_table_menu() {
    ui_list menu "$@"
}

# ui_table_checklist "texto" "cabecera" tag fila [tag fila ...] -> una opcion elegida por linea
function ui_table_checklist() {
    ui_list checklist "$1" "" "${@:2}"
}

