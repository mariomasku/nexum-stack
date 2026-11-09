# Progreso de la instalacion, para la barra del panel. Las funciones de instalacion escriben en el
# archivo $PROGRESS (si esta definido) lineas como estas:
#   C|componente 1;componente 2;...               componentes de la version que se instala
#   S|n|desde|hasta|texto|modo|archivo|total|hora  empieza un paso del componente n
# <desde>-<hasta> es el tramo de la barra (en % de la version). Dentro del tramo se avanza segun
# <modo>: lines (lineas de un log), bytes (tamaño de un archivo que se descarga), time (segundos)
# o percent (ultimo "[ NN%]" del log, como el que escribe CMake).
function progress_parts() {
    [ -n "$PROGRESS" ] && echo "C|$(IFS=';'; echo "$*")" >> "$PROGRESS"
    return 0
}

# Pasos de una tarea de la ventana (LVM_PROGRESO): la lista que se va marcando. task_plan <titulo>
# <paso>... y un task_step al empezar cada paso. Solo manda quien hizo el plan: lo que llame por dentro
# (una instalacion dentro de otra) no cambia la lista. Fuera de la ventana no hace nada.
TASK_OWNER="" TASK_CUR=0
TASK_NAMES=()
function task_plan() {
    [ -n "$LVM_PROGRESO" ] && [ -z "$TASK_OWNER" ] || return 0
    local name=${1//[|$'\n']/ } parts
    shift
    TASK_OWNER=${FUNCNAME[1]} TASK_CUR=0
    TASK_NAMES=("$@")
    parts=$(IFS=';'; echo "${TASK_NAMES[*]//;/,}")
    { echo "I|1|1|$name|$(date +%s)"; echo "C|${parts//[|$'\n']/ }"; } >> "$LVM_PROGRESO"
    return 0
}
function task_step() {
    [ -n "$LVM_PROGRESO" ] && [ "$TASK_OWNER" == "${FUNCNAME[1]}" ] && [ "$TASK_CUR" -lt "${#TASK_NAMES[@]}" ] || return 0
    TASK_CUR=$(( TASK_CUR + 1 ))
    local what=${TASK_NAMES[TASK_CUR - 1]}
    task_detail "${what//[|$'\n']/ }" "" "" 0 "$(date +%s)"
}
# El avance por dentro del paso de ahora: task_detail <texto> <modo> <fichero> <total> <inicio>
function task_detail() {
    local n=${#TASK_NAMES[@]}
    echo "S|$TASK_CUR|$(( (TASK_CUR - 1) * 100 / n ))|$(( TASK_CUR * 100 / n ))|$1|$2|$3|$4|$5" >> "$LVM_PROGRESO"
}

