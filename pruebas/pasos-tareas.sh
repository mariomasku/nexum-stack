#!/bin/bash
# La lista de pasos de las instalaciones (Linux 1.56.32, Mac 1.40.13): task_plan y task_step escriben
# lo que lee la ventana, solo manda quien hizo el plan y cada plan fijo tiene tantos pasos como
# task_step. Uso: pasos-tareas.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q "^function task_plan()" "$SRC" || { echo "  ok    (sin pasos de tareas)"; exit 0; }
W=$(mktemp -d "$TMPBASE/pasos.XXXXXX") || exit 1
trap 'rm -rf "${W:?}"' EXIT
extract "$SRC" task_plan task_step task_detail
TASK_OWNER="" TASK_CUR=0 TASK_NAMES=()
P=$W/progreso

fuera() { LVM_PROGRESO="" task_plan "T" "A"; task_step; }
fuera
check "fuera de la ventana no escribe nada" '[ ! -e "$P" ] && [ -z "$TASK_OWNER" ]'

interna() { task_plan "Otra" "X" "Y"; task_step; }
externa() {
    task_plan "Actualizar; mi|web" "Uno; con punto y coma" "Dos|con barra" "Tres"
    task_step
    interna
    task_step
    task_detail "cargando" fdpos "/proc/1/fdinfo/3" 1000 123
    task_step
    task_step
}
LVM_PROGRESO=$P externa
check "un plan: I y C, con ; y | de los textos quitados" 'grep -qxE "I\|1\|1\|Actualizar; mi web\|[0-9]+" "$P" && grep -qx "C|Uno, con punto y coma;Dos con barra;Tres" "$P"'
check "lo de dentro no cambia la lista ni avanza" '[ "$(grep -c "^I|" "$P")" = 1 ] && [ "$(grep -c "^C|" "$P")" = 1 ] && ! grep -q "^S|.*|X|" "$P"'
check "cada paso con su tramo de la barra" 'grep -qE "^S\|1\|0\|33\|Uno, |^S\|1\|0\|33\|Uno; " "$P" && grep -q "^S|2|33|66|Dos con barra|" "$P" && grep -q "^S|3|66|100|Tres|" "$P"'
check "el avance por dentro del paso, en su tramo" 'grep -q "^S|2|33|66|cargando|fdpos|/proc/1/fdinfo/3|1000|123$" "$P"'
check "un task_step de mas no pasa del ultimo" '[ "$(grep -c "^S|3|" "$P")" = 1 ] && ! grep -q "^S|4|" "$P"'

# Cada plan de pasos fijos tiene tantos pasos como task_step, y las ventanas los piden
python3 -I - "$SRC" > "$W/planes" << 'PY'
import re, shlex, sys
t = open(sys.argv[1], encoding="utf-8").read()
for m in re.finditer(r"^function (\w+)\(\) \{\n(.*?)^\}\n", t, re.M | re.S):
    name, body = m.groups()
    if name in ("task_plan", "task_step", "task_detail") or "task_plan " not in body:
        continue
    plans = re.findall(r"^ *task_plan (.*)$", body, re.M)
    steps = len(re.findall(r"(?:^ *|\{ )task_step\b", body, re.M))
    fixed = [len(shlex.split(p)) - 1 for p in plans if "${steps[@]}" not in p]
    dynamic = len(plans) - len(fixed)
    print(name, sum(fixed), steps, dynamic)
PY
while read -r f want have dyn; do
    if [ "$dyn" = 0 ]; then
        check "$f: tantos task_step como pasos ($want)" '[ "$want" = "$have" ]'
    else
        check "$f: plan calculado y con task_step" '[ "$have" -gt 0 ]'
    fi
done < "$W/planes"
for f in project_update components_update mailpit_install tunnel_install update_pma mount_project docker_create docker_web_create docker_web_create_live docker_pass docker_install docker_update_image; do
    check "$f lleva su lista de pasos" 'grep -qE "^$f " "$W/planes"'
done
check "la carga de una BBDD dentro de un plan no lo sustituye" 'grep -q "^    if \[ -n \"\$TASK_OWNER\" \]; then$" "$SRC" && grep -qE "\[ -z \"\\\$TASK_OWNER\" \] && echo \"R\|bd:" "$SRC"'
if grep -q "^let ERROR_LOG = " "$SRC"; then
    check "Mac: la actualización de Nexum lleva su lista" 'grep -qE "^install_update " "$W/planes"'
    for t in 'Actualizando phpMyAdmin' 'Instalando Mailpit' 'Montando el proyecto' 'Abriendo Docker Desktop' '(Creando|Montando) .* en Docker' 'Actualizando la imagen de PHP' 'Pasando .{1,3}p\.folder' 'Instalando cloudflared' 'Actualizando Nexum Dev Stack'; do
        check "Mac: «$t» con progress" '! grep -E "runTask\(\"$t" "$SRC" | grep -qv "progress: true"'
    done
else
    for t in 'Actualizando phpMyAdmin' 'Instalando Mailpit' 'Montando el proyecto' '(Creando|Montando) %s en Docker' 'Pasando %s al Apache' 'Instalando cloudflared' '%s: imagen de PHP'; do
        check "Linux: «$t» con progress" '! grep -E "self\.run_task\(\"$t" "$SRC" | grep -qv "progress=True"'
    done
fi
exit $fail
