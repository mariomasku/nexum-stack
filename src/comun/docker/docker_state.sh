# Estado de los contenedores de un proyecto: marcha (todos), parado (ninguno), parcial o nuevo
function docker_state() {
    local out up=0 total=0 state
    out=$(dk ps -a --filter "label=com.docker.compose.project=nexum-$1" --format '{{.State}}' 2> /dev/null) || { echo "?"; return 0; }
    while read -r state; do
        [ -z "$state" ] && continue
        total=$((total + 1))
        [ "$state" == running ] && up=$((up + 1))
    done <<< "$out"
    if [ $total -eq 0 ]; then echo nuevo
    elif [ $up -eq $total ]; then echo marcha
    elif [ $up -eq 0 ]; then echo parado
    else echo parcial
    fi
}

