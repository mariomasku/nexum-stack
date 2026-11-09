# ===========================================================================
# Interfaz: ventanas con whiptail si hay terminal, texto en caso contrario
# ===========================================================================

APP_NAME="Nexum Dev Stack"
TITLE="$APP_NAME"
# LVM_SIN_PREGUNTAS=1: no se espera ningun Intro y las preguntas si/no reciben "no". Lo usa la
# ventana, que ejecuta el instalador en una pseudoterminal en la que nadie puede contestar
NO_ASK=${LVM_SIN_PREGUNTAS:-0}
UI=text
if [ "$LVM_UI" != "text" ] && [ -t 0 ] && [ -t 1 ] && command -v whiptail > /dev/null; then
    UI=whiptail
fi

# Abierto desde la aplicacion (LVM_ACCESO=1): si la terminal es menor de 100x32 se le pide ese
# tamaño con CSI 8 t (Terminal e iTerm2 lo admiten), para que el panel principal deje sitio al logo.
# Desde una terminal propia no se toca su tamaño.
if [ "$UI" == "whiptail" ] && [ -n "$LVM_ACCESO" ]; then
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
# de emptyscale/fullscale). El color exacto solo sale con COLORTERM=truecolor (iTerm2...); sin el,
# slang lo aproxima y pone el % en negro, asi que se usa el verde basico.
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

#@incluir comun/interfaz/ui_size.sh
# wt: whiptail con la firma abajo a la derecha de la pantalla y el logo abajo a la izquierda,
# fuera de la ventana.
# whiptail borra la pantalla al abrirse, asi que la firma se escribe en la terminal justo despues
# de que dibuje. El proceso que la escribe no hereda la salida (se capturan con $(...)) y se
# detiene en cuanto whiptail termina.
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

#@incluir comun/interfaz/green_escape.sh
function wt() {
    local signer=""

    if [ -w /dev/tty ]; then
        (
            # Se repite mientras whiptail este abierto: al principio por si tarda en dibujar y
            # despues cada 2 segundos, por si la terminal cambia de tamaño y whiptail lo borra al
            # redibujar. El tamaño se lee cada vez. ESC 7 / ESC 8 guardan y restauran la posicion
            # del cursor y los colores, para no alterar lo que dibuja whiptail.
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
        [ -t 0 ] && [ "$NO_ASK" != "1" ] && read -p "Pulsa Intro para continuar... " _ >&2
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
        [ "$NO_ASK" == "1" ] && return 1
        read -p "[s/N]: " answer >&2
        [[ "$answer" =~ ^[sSyY]$ ]]
    fi
}

#@incluir comun/interfaz/ui_list.sh
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

