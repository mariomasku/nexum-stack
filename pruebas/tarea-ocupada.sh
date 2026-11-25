#!/bin/bash
# Con una tarea en marcha (1.57.34): lo que lanza otra no se apaga; se ve atenuado y se puede pulsar, y en vez de
# hacer lo suyo dice cuál sigue (busy_guard en Linux, busyGuard en el Mac). Uso: tarea-ocupada.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
if grep -q "^let ERROR_LOG = " "$SRC"; then
    check "Mac: ya no se apaga nada por la tarea en marcha" '! grep -qE "\.disabled\([^)]*model\.busy" "$SRC" && ! grep -qF "&& !model.busy" "$SRC"'
    check "Mac: atenuado, sin tocar el botón, y la capa de encima lo dice" 'grep -qF ".opacity(busy ? 0.5 : 1)" "$SRC" && grep -qF ".allowsHitTesting(!busy)" "$SRC" && grep -qF "if let m = AppModel.current, let cur = m.runningTask { m.refuseTask(cur) }" "$SRC"'
    check "Mac: en todos los botones de tareas" '[ "$(grep -c "busyGuard(model.busy)" "$SRC")" -ge 120 ]'
else
    check "Linux: ya no se apaga nada por la tarea en marcha" '! grep -qE "sensitive(=|\()[^#]*not self\.busy" "$SRC" && ! grep -qF "not (task and self.busy)" "$SRC"'
    check "Linux: en todos los botones de tareas" '[ "$(grep -c "busy_guard(" "$SRC")" -ge 65 ]'
    check "Linux: atenuado (.nv-espera)" 'grep -qF ".nv-espera { opacity: 0.5; }" "$SRC"'
    # Con pantalla: clics de verdad en un botón, un interruptor y un desplegable, con tarea y sin ella
    if [ -n "$DISPLAY" ] && python3 -c "import gi" 2> /dev/null; then
        W=$(mktemp -d "$TMPBASE/ocupada.XXXXXX") || exit 1
        trap 'rm -rf "${W:?}"' EXIT
        awk '/cat <<.LVM_GUI_PY.$/{f=1;next} /^LVM_GUI_PY$/{f=0} f' "$SRC" > "$W/gui.py"
        cp "$HERE/datos/clics-ocupada.py" "$W/c.py"
        out=$(cd "$W" && GDK_BACKEND=x11 LVM_SIMULAR=1 timeout 30 python3 -I c.py gui.py 2> /dev/null)
        check "Linux (clics): con tarea, nada hace lo suyo y cada uno avisa; atenuado" 'grep -qx "ocupado: clics=0 interruptor=False desplegable_abierto=False avisos=3 atenuado=True" <<< "$out"'
        check "Linux (clics): sin tarea, todo va como siempre" 'grep -qx "libre: desplegable_abierto=True" <<< "$out" && grep -qx "libre: clics=1 interruptor=True avisos=3 atenuado=False" <<< "$out"'
    fi
fi
exit $fail
