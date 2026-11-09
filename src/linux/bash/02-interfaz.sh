# ===========================================================================
# Interfaz: ventanas con whiptail si hay terminal, texto en caso contrario
# ===========================================================================

APP_NAME="Nexum Dev Stack"
TITLE="$APP_NAME"
UI=text
if [ "$LVM_UI" != "text" ] && [ -t 0 ] && [ -t 1 ] && command -v whiptail > /dev/null; then
    UI=whiptail
fi

# Abierto desde el acceso del menu (el script es el primer proceso de su terminal, no lo lanzo
# una shell): si la terminal es menor de 100x32 se le pide ese tamaño con CSI 8 t (GNOME Terminal,
# xterm, Konsole...), para que el panel principal deje sitio al logo. Desde una terminal propia
# no se toca su tamaño.
if [ "$UI" == "whiptail" ] && [ "$(ps -o sid= -p $$ 2> /dev/null | tr -d ' ')" == "$$" ]; then
    size=$(stty size < /dev/tty 2> /dev/null)
    if [ -n "$size" ] && { (( ${size% *} < 32 )) || (( ${size#* } < 100 )); }; then
        printf '\033[8;32;100t' > /dev/tty
        # La terminal tarda un poco en cambiar; se espera hasta un segundo
        for i in 1 2 3 4 5 6 7 8 9 10; do
            [ "$(stty size < /dev/tty 2> /dev/null)" != "$size" ] && break
            sleep 0.1
        done
    fi
    unset size i
fi

# Colores de las ventanas: fondo oscuro y el elemento seleccionado en blanco (los colores por
# defecto, rojo sobre gris/rosa, apenas se distinguen). Se respeta un NEWT_COLORS propio.
# La barra de progreso rellena va en verde #45A57C con el % en blanco (newt ignora el color de texto
# de emptyscale/fullscale). El color exacto solo sale con COLORTERM=truecolor (GNOME Terminal,
# Konsole...); sin el, slang lo aproxima y pone el % en negro, asi que se usa el verde basico.
OWN_COLORS=1
if [ -z "$NEWT_COLORS" ]; then
    OWN_COLORS=0
    case "$COLORTERM" in
        truecolor|24bit) BAR_COLOR='#45A57C' ;;
        *) BAR_COLOR=green ;;
    esac
    export NEWT_COLORS='
        root=white,black
        roottext=white,black
        helpline=white,black
        shadow=black,black
        border=white,black
        window=white,black
        title=brightcyan,black
        textbox=white,black
        acttextbox=black,white
        listbox=white,black
        actlistbox=black,lightgray
        sellistbox=black,lightgray
        actsellistbox=black,white
        checkbox=white,black
        actcheckbox=black,white
        entry=white,black
        disentry=gray,black
        label=white,black
        button=black,white
        actbutton=black,white
        compactbutton=white,black
        emptyscale=,black
        fullscale=,'"$BAR_COLOR"'
    '
fi

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

# wt: whiptail con la firma abajo a la derecha de la pantalla y el logo abajo a la izquierda,
# fuera de la ventana.
# whiptail borra la pantalla al abrirse, asi que la firma se escribe en la terminal justo despues
# de que dibuje; como no vuelve a tocar esa linea, se queda ahi. El proceso que la escribe no
# hereda la salida (se capturan con $(...)) y se detiene en cuanto whiptail termina.
# logo_escape filas columnas [argumentos de whiptail]: secuencia que pinta el logo abajo a la
# izquierda, o nada si la ventana (centrada, con su sombra) llegaria a taparlo
function logo_escape() {
    local lines=$1 cols=$2; shift 2
    local h=0 w=0 n=${#LOGO[@]} logo_w=0 row
    for row in "${LOGO[@]}"; do (( ${#row} > logo_w )) && logo_w=${#row}; done

    while [ $# -gt 0 ]; do
        case "$1" in
            --msgbox|--yesno|--infobox|--inputbox|--passwordbox|--textbox|--menu|--checklist|--radiolist|--gauge)
                h=${3:-0}; w=${4:-0}; break ;;
        esac
        shift
    done
    (( h > lines )) && h=$lines
    (( w > cols )) && w=$cols
    local top=$(( (lines - h) / 2 )) left=$(( (cols - w) / 2 ))
    # Sitio libre: la ventana empieza a la derecha del logo o acaba (sombra incluida) por encima
    if (( left <= logo_w + 3 )) && (( top + h + 1 >= lines - n + 1 )); then
        return 0
    fi

    local green='\033[32m' out="" i ch y
    case "$COLORTERM" in truecolor|24bit) green='\033[38;2;69;165;124m' ;; esac
    for (( i = 0; i < n; i++ )); do
        row=${LOGO[$i]}
        y=$(( lines - n + 1 + i ))
        out+="\033[${y};2H\033[0;1;40m"
        for (( ch = 0; ch < ${#row}; ch++ )); do
            case "${row:$ch:1}" in
                '#') out+='\033[97m#' ;;
                '/') out+="${green}/" ;;
                *) out+=' ' ;;
            esac
        done
    done
    printf '%s' "$out"
}

# green_escape filas columnas [argumentos de whiptail]: secuencia que repinta en verde el texto
# $WT_GREEN dentro de la ventana (whiptail no permite colorear una parte del texto). Calcula su
# posicion igual que whiptail centra la ventana: el texto empieza una fila por debajo del borde
# y dos columnas a su derecha. No pinta nada con un NEWT_COLORS propio (el fondo podria no ser
# negro), con texto que se desplaza (--scrolltext) o si la linea no cabe entera.
function green_escape() {
    local lines=$1 cols=$2; shift 2
    [ -z "$WT_GREEN" ] || [ "$OWN_COLORS" -eq 1 ] && return 0

    local text="" h=0 w=0 gap=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --scrolltext) return 0 ;;
            # Las ventanas de mensaje dejan una fila en blanco encima del texto; las listas no
            --msgbox|--yesno|--infobox)
                text=$2; h=${3:-0}; w=${4:-0}; gap=1; break ;;
            --inputbox|--textbox|--menu|--checklist|--radiolist)
                text=$2; h=${3:-0}; w=${4:-0}; break ;;
        esac
        shift
    done
    (( h > lines )) && h=$lines
    (( w > cols )) && w=$cols
    local top=$(( (lines - h) / 2 )) left=$(( (cols - w) / 2 ))

    # Fila del texto (contando las lineas que whiptail parte por no caber)
    local row=$(( top + 1 + gap )) line found=0
    while IFS= read -r line; do
        [[ "$line" == *"$WT_GREEN"* ]] && found=1 && break
        row=$(( row + (${#line} > w - 4 ? (${#line} + w - 5) / (w - 4) : 1) ))
    done <<< "$(echo -e "$text")"
    (( found == 1 && ${#line} <= w - 4 && row < top + h - 1 )) || return 0

    local prefix=${line%%"$WT_GREEN"*} green='\033[32m'
    case "$COLORTERM" in truecolor|24bit) green='\033[38;2;69;165;124m' ;; esac
    printf '%s' "\033[$(( row + 1 ));$(( left + 3 + ${#prefix} ))H\033[0;1;40m${green}${WT_GREEN}"
}

# signature_escape filas columnas [argumentos de whiptail]: secuencia que pinta la firma abajo a la
# derecha con la version del instalador debajo. Si la ventana llega a la penultima fila, firma y
# version van juntas en la ultima.
function signature_escape() {
    local lines=$1 cols=$2; shift 2
    local version="v$APP_VERSION" h=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --msgbox|--yesno|--infobox|--inputbox|--passwordbox|--textbox|--menu|--checklist|--radiolist|--gauge)
                h=${3:-0}; break ;;
        esac
        shift
    done
    (( h > lines )) && h=$lines
    local top=$(( (lines - h) / 2 )) col=$(( cols - ${#SIGNATURE} - 1 ))
    (( col > 0 )) || return 0

    if (( top + h < lines - 1 )); then
        printf '%s' "\033[$(( lines - 1 ));${col}H\033[0;37;40m$SIGNATURE"
        printf '%s' "\033[${lines};$(( cols - ${#version} - 1 ))H\033[0;37;40m$version"
    else
        local both="$SIGNATURE  $version"
        (( ${#both} + 1 < cols )) || both=$SIGNATURE
        printf '%s' "\033[${lines};$(( cols - ${#both} - 1 ))H\033[0;37;40m$both"
    fi
}

function wt() {
    local signer=""

    if [ -w /dev/tty ]; then
        (
            # Se repite mientras whiptail este abierto: al principio por si tarda en dibujar y
            # despues cada 2 segundos, por si la terminal cambia de tamaño (GNOME Terminal puede
            # ajustarla justo despues de abrirse) y whiptail lo borra al redibujar. El tamaño se
            # lee cada vez. ESC 7 / ESC 8 guardan y restauran la posicion del cursor y los
            # colores, para no alterar lo que dibuja whiptail.
            # Se para si el script ya no existe ($$ es su PID tambien aqui) o la terminal se cierra.
            local delay=0.15 lines cols sign logo size
            while kill -0 $$ 2> /dev/null; do
                sleep $delay
                case $delay in 0.15) delay=0.4 ;; 0.4) delay=1 ;; *) delay=2 ;; esac
                size=$(stty size < /dev/tty 2> /dev/null) || size="24 80"
                lines=${size% *} cols=${size#* }
                sign=$(signature_escape "$lines" "$cols" "$@")
                [ -n "$sign" ] || continue
                logo=$(logo_escape "$lines" "$cols" "$@")$(green_escape "$lines" "$cols" "$@")
                printf "\0337${sign}${logo}\0338" > /dev/tty || break
            done
        ) < /dev/null > /dev/null 2>&1 &
        signer=$!
    fi

    whiptail "$@"
    local rc=$?

    [ -n "$signer" ] && kill "$signer" 2> /dev/null && wait "$signer" 2> /dev/null
    return $rc
}

# with_signature "texto" ancho: pone la firma alineada a la derecha en la ultima linea del texto
function with_signature() {
    local text=$(echo -e "$1") width=$2
    local last=${text##*$'\n'}
    local rest=""
    [ "$last" != "$text" ] && rest="${text%$'\n'*}\n"

    if (( ${#last} + ${#SIGNATURE} + 2 > width )); then
        echo "$1\n$(printf '%*s' $(( width - ${#SIGNATURE} > 0 ? width - ${#SIGNATURE} : 0 )) "")$SIGNATURE"
    else
        echo "$rest$(pad "$last" $(( width - ${#SIGNATURE} )))$SIGNATURE"
    fi
}

function ui_msg() {
    if [ "$UI" == "whiptail" ]; then
        ui_size "$1"
        wt --title "$TITLE" "${SCROLL[@]}" --ok-button "Continuar" --msgbox "$1" $H $W
    else
        echo "" >&2
        echo -e "$1" >&2
        echo "" >&2
        [ -t 0 ] && read -p "Pulsa Intro para continuar... " _ >&2
    fi
}

function ui_yesno() {
    if [ "$UI" == "whiptail" ]; then
        ui_size "$1"
        wt --title "$TITLE" --yes-button "Si" --no-button "No" --defaultno "${SCROLL[@]}" --yesno "$1" $H $W
    else
        local answer
        echo "" >&2
        echo -e "$1" >&2
        read -p "[s/N]: " answer >&2
        [[ "$answer" =~ ^[sSyY]$ ]]
    fi
}

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

function ui_input() {
    local text=$1 default=$2

    if [ "$UI" == "whiptail" ]; then
        ui_size "$text"
        wt --title "$TITLE" --ok-button "Aceptar" --cancel-button "Volver" \
            --inputbox "$text" $((H + 2)) $W "$default" 3>&1 1>&2 2>&3
    else
        local answer
        echo "" >&2
        echo -e "$text" >&2
        read -p "> " answer >&2
        echo "${answer:-$default}"
    fi
}

function say() {
    echo ""
    echo "==> $*"
}

