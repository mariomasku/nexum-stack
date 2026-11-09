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

