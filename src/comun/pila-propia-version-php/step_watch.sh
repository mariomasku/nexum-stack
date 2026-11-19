# step_watch <desde> <hasta> <lineas> <descripcion> <registro> <orden...>: ejecuta un paso de la
# compilacion (su salida, en su registro) y, mientras dura, escribe cada STEP_TICK segundos (30) por donde
# va: «[ 41%] Compilando... sigue (2 min 30 s)». Sin esto, el registro de la tarea se quedaba minutos en la
# misma linea y parecia congelado. El porcentaje sale de las lineas que lleva su registro frente a las que
# suele tener (<lineas>) o, con 0, del ultimo «[ NN%]» que escribe cmake. Devuelve lo que devuelve la orden.
# (la orden va en segundo plano pero en el grupo de la tarea: Cancelar le llega igual)
function step_watch() {
    local from=$1 to=$2 lines=$3 desc=$4 log=$5 pid el next n pct tick=${STEP_TICK:-30}
    shift 5
    "$@" > "$log" 2>&1 < /dev/null &
    pid=$!
    el=0 next=$tick
    while kill -0 "$pid" 2> /dev/null; do
        sleep 1
        el=$((el + 1))
        [ "$el" -ge "$next" ] || continue
        next=$((next + tick))
        n=0
        if [ "$lines" -gt 0 ]; then
            n=$(wc -l < "$log" 2> /dev/null)
            n=$(( ${n:-0} * 100 / lines ))
        else
            n=$(tail -c 8000 "$log" 2> /dev/null | grep -aoE '^\[ *[0-9]+%\]' | tail -1 | tr -dc '0-9')
        fi
        [ "${n:-0}" -gt 99 ] 2> /dev/null && n=99
        pct=$(( from + (to - from) * ${n:-0} / 100 ))
        printf '  [%3d%%] %s... sigue (%s)\n' "$pct" "$desc" "$(step_elapsed "$el")"
    done
    wait "$pid"
}

# 45 s, 2 min, 2 min 30 s, 1 h 5 min
function step_elapsed() {
    local s=$1
    if [ "$s" -lt 60 ]; then
        echo "$s s"
    elif [ "$s" -lt 3600 ]; then
        echo "$((s / 60)) min$([ $((s % 60)) -gt 0 ] && echo " $((s % 60)) s")"
    else
        echo "$((s / 3600)) h$([ $((s % 3600 / 60)) -gt 0 ] && echo " $((s % 3600 / 60)) min")"
    fi
}
