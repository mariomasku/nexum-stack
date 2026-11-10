# ===========================================================================
# Ejecucion de un plan de instalacion
# ===========================================================================

# Nombre de un elemento del plan de instalacion
function plan_label() {
    local name=${1#*:}

    case "${1%%:*}" in
        php) echo "PHP $name" ;;
        rehacer) echo "PHP ${name%.*} (actualizar)" ;;
        parchear) echo "PHP $name (parche de seguridad)" ;;
    esac
}

# Instala un elemento del plan (en un subproceso: las funciones de instalacion usan exit)
function run_plan_item() {
    case "${1%%:*}" in
        php) ( install_stack "${1#*:}" ) ;;
        rehacer) ( install_stack "${1#*:}" 1 ) ;;
        parchear) ( install_stack "${1#*:}" 2 ) ;;
    esac
}

function fmt_minutes() {
    if [ "$1" -lt 60 ]; then
        echo "menos de 1 min"
    else
        echo "$(( ($1 + 30) / 60 )) min"
    fi
}

# Pantalla de la barra de progreso (protocolo de whiptail --gauge) a partir de $PROGRESS
function progress_screen() {
    local info=$(grep '^I|' "$PROGRESS" | tail -1)
    [ -z "$info" ] && return 0

    local k n label started
    IFS='|' read -r _ k n label started <<< "$info"

    # Solo cuentan las lineas escritas desde que empezo esta version
    local section=$(awk '/^I\|/ {buf = ""} {buf = buf $0 "\n"} END {printf "%s", buf}' "$PROGRESS")
    local parts=$(grep '^C|' <<< "$section" | tail -1 | cut -d'|' -f2)
    local step=$(grep '^S|' <<< "$section" | tail -1)
    local pct=0 cur=0 what="" from to mode file total t0 done=0 frac=0

    if [ -n "$step" ]; then
        IFS='|' read -r _ cur from to what mode file total t0 <<< "$step"
        case "$mode" in
            lines) done=$(wc -l < "$file" 2> /dev/null | tr -dc '0-9') ;;
            bytes) done=$(stat -f %z "$file" 2> /dev/null) ;;
            time) done=$(( $(date +%s) - t0 )) ;;
            percent) done=$(tail -n 40 "$file" 2> /dev/null | grep -oE '^\[ *[0-9]+%\]' | tail -1 | tr -dc '0-9') ;;
        esac
        if [ -n "$mode" ] && [ "${total:-0}" -gt 0 ]; then
            frac=$(( ${done:-0} * 1000 / total ))
            (( frac > 990 )) && frac=990
        fi
        pct=$(( from + (to - from) * frac / 1000 ))
    fi
    grep -q '^R|' <<< "$section" && pct=100 && cur=999

    local text="Instalando $k de $n: $label\n\n" i=1 part list
    IFS=';' read -r -a list <<< "$parts"
    for part in "${list[@]}"; do
        if (( i < cur )); then
            text+="  [x] $part\n"
        elif (( i == cur )); then
            text+="  [>] $part: $what\n"
        else
            text+="  [ ] $part\n"
        fi
        i=$(( i + 1 ))
    done

    local elapsed=$(( $(date +%s) - started ))
    text+="\nTiempo: $(fmt_minutes $elapsed)"
    if (( pct >= 5 && pct < 100 )); then
        local left=$(( elapsed * (100 - pct) / pct ))
        if (( left < 60 )); then text+="   Queda menos de 1 min"; else text+="   Quedan unos $(fmt_minutes $left)"; fi
    fi
    (( n > 1 )) && text+="\nTotal de la instalacion: $(( ((k - 1) * 100 + pct) / n ))%"

    printf 'XXX\n%d\n%s\nXXX\n' "$pct" "$text"
}

# Barra de progreso mientras se instala en segundo plano (proceso <pid>)
function progress_gauge() {
    local job=$1
    local rows=$(tput lines 2> /dev/null || echo 24)
    local text_lines=12
    (( text_lines + 6 > rows - 1 )) && text_lines=$(( rows - 7 ))

    # whiptail fija el alto del texto con el texto inicial: se abre con lineas vacias
    local init=$(printf '%.0s \\n' $(seq $text_lines))

    while true; do
        local finished=0
        kill -0 "$job" 2> /dev/null || finished=1
        progress_screen
        [ $finished -eq 1 ] && break
        sleep 1
    done | wt --title "$TITLE" --gauge "$init" $(( text_lines + 6 )) 74 0
}

# Solo una instalacion a la vez
LOCK_DIR="$LOG_DIR/instalando.lock"

function lock_install() {
    mkdir -p -m 700 "$LOG_DIR"
    if ! mkdir "$LOCK_DIR" 2> /dev/null; then
        local pid=$(cat "$LOCK_DIR/pid" 2> /dev/null)
        [ -n "$pid" ] && kill -0 "$pid" 2> /dev/null && return 1
        rm -rf "$LOCK_DIR"
        mkdir "$LOCK_DIR" 2> /dev/null || return 1
    fi
    echo $$ > "$LOCK_DIR/pid"
}

function unlock_install() {
    rm -rf "$LOCK_DIR"
}

function other_install_running() {
    local pid=$(cat "$LOCK_DIR/pid" 2> /dev/null)
    [ -n "$pid" ] && [ "$pid" != "$$" ] && kill -0 "$pid" 2> /dev/null
}

# install_plan "php:8.4.26 rehacer:8.3.35 ..."
function install_plan() {
    local items=($1) item ok=() failed=() errors=""

    mkdir -p -m 700 "$LOG_DIR"

    if [ "$DRY" -eq 0 ]; then
        if ! lock_install; then
            ui_msg "Hay otra instalacion en marcha. Espera a que termine."

            return 1
        fi

        if [ -z "$TEST_DIR" ]; then
            # Pide la contraseña una sola vez y la mantiene activa durante toda la instalacion
            echo "Se necesita la contraseña de administrador (sudo):"
            sudo -v || { unlock_install; return 1; }
            while true; do sudo -n true; sleep 50; kill -0 "$$" 2> /dev/null || exit; done 2> /dev/null &
            local keepalive=$!
            # shellcheck disable=SC2064  # (el PID, el de ahora)
            trap "kill $keepalive 2> /dev/null; unlock_install" EXIT
        else
            trap "unlock_install" EXIT
        fi
    fi

    if [ "$UI" == "whiptail" ] && [ "$DRY" -eq 0 ]; then
        # Con ventanas: la instalacion va en segundo plano (salida al log) y se muestra la barra
        PROGRESS=$(mktemp /tmp/lvm-progreso-XXXX)
        (
            local k=0
            for item in "${items[@]}"; do
                k=$(( k + 1 ))
                echo "I|$k|${#items[@]}|$(plan_label "$item")|$(date +%s)" >> "$PROGRESS"
                echo -e "\n================ ${item/:/ } ================" >> "$LOG"
                run_plan_item "$item" < /dev/null > "$PROGRESS.$k" 2>&1
                echo "R|$item|$?" >> "$PROGRESS"
                cat "$PROGRESS.$k" >> "$LOG"
            done
        ) &
        local job=$!
        progress_gauge "$job"
        wait "$job"

        local k=0 rc
        for item in "${items[@]}"; do
            k=$(( k + 1 ))
            rc=$(grep "^R|$item|" "$PROGRESS" | cut -d'|' -f3)
            if [ "$rc" == "0" ]; then
                ok+=("$item")
            else
                failed+=("$item")
                errors+="\nUltimas lineas de ${item/:/ }:\n$(tail -8 "$PROGRESS.$k" 2> /dev/null | fold -w 90)\n"
            fi
        done
        rm -f "$PROGRESS" "$PROGRESS".*
        PROGRESS=""
    else
        # La ventana pasa LVM_PROGRESO: se escribe el mismo archivo de progreso que lee la barra
        [ -n "$LVM_PROGRESO" ] && [ "$DRY" -eq 0 ] && PROGRESS=$LVM_PROGRESO
        local k=0 rc
        for item in "${items[@]}"; do
            k=$(( k + 1 ))
            [ -n "$PROGRESS" ] && echo "I|$k|${#items[@]}|$(plan_label "$item")|$(date +%s)" >> "$PROGRESS"
            echo ""
            echo "================ ${item/:/ } ================" | tee -a "$LOG"

            run_plan_item "$item" 2>&1 | tee -a "$LOG"
            rc=${PIPESTATUS[0]}

            [ -n "$PROGRESS" ] && echo "R|$item|$rc" >> "$PROGRESS"
            if [ "$rc" -eq 0 ]; then ok+=("$item"); else failed+=("$item"); fi
        done
        PROGRESS=""
    fi

    [ "$DRY" -eq 0 ] && unlock_install

    local summary="Resultado de la instalacion:\n\n"
    for item in "${ok[@]}"; do
        local name=${item#*:}
        summary+="  OK     PHP ${name}  ->  activar con: nexum use ${name%.*}\n"
    done
    for item in "${failed[@]}"; do
        local name=${item#*:}
        summary+="  ERROR  PHP ${name}  (no se ha instalado nada; revisa el log)\n"
    done
    summary+="$errors\nLog completo: $LOG"
    [ "$DRY" -eq 1 ] && summary+="\n\nSIMULACION: no se ha hecho ningun cambio."

    echo -e "\n$summary" >> "$LOG"
    ui_msg "$summary"

    [ ${#failed[@]} -eq 0 ]
}

function check_space() {
    local needed=$1
    # En modo prueba la carpeta puede no existir todavia: se mira la mas cercana que exista
    local dir=$BASE_DIR
    while [ ! -d "$dir" ] && [ "$dir" != "/" ]; do dir=$(dirname "$dir"); done
    local free=$(df -g "$dir" | awk 'NR == 2 {print $4}')

    if [ "${free:-0}" -lt "$(( needed + 2 ))" ]; then
        ui_msg "Espacio insuficiente: hay ${free}G libres y se necesitan unos ${needed}G (+2G de margen)."

        return 1
    fi
}

