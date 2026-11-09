# Segundos (de 1970) de cuando arranco un contenedor (nada si no esta)
function docker_started_at() {
    dk inspect -f '{{.State.StartedAt}}' "$1" 2> /dev/null | python3 -I -c '
import datetime, re, sys
t = sys.stdin.read().strip()
m = re.match(r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)", t)
if m:
    print(int(datetime.datetime.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S").replace(tzinfo=datetime.timezone.utc).timestamp()))'
}

# docker-reposo comprobar: para los que llevan las horas sin visitas (lo lanza el temporizador)
function docker_idle_check() {
    local h now cutoff up visited p name t newest stopped=0 dom seen
    h=$(docker_idle_hours)
    [ "$h" -gt 0 ] || return 0
    docker_ready > /dev/null 2>&1 || return 0
    up=$(dk ps --format '{{.Names}}' 2> /dev/null)
    grep -qx nexum-web <<< "$up" || return 0
    now=$(date +%s) cutoff=$(( $(date +%s) - h * 3600 ))
    t=$(docker_started_at nexum-web)
    [ -n "$t" ] && [ "$t" -le "$cutoff" ] || return 0
    # (los dominios visitados en esas horas: el primero de cada linea del registro de nexum-web)
    visited=$(dk logs --since "${h}h" nexum-web 2> /dev/null | awk '{ print tolower($1) }' | sort -u)
    for p in $(docker_web_projects); do
        newest=""
        for name in $(grep -E "^nexum-$p-php[0-9]{2}\$" <<< "$up"); do
            t=$(docker_started_at "$name")
            [ -n "$t" ] && { [ -z "$newest" ] || [ "$t" -gt "$newest" ]; } && newest=$t
        done
        [ -n "$newest" ] && [ "$newest" -le "$cutoff" ] || continue
        seen=0
        for dom in $(docker_web_domains "$p"); do
            grep -qxF "${dom,,}" <<< "$visited" && { seen=1; break; }
        done
        [ $seen -eq 1 ] && continue
        if [ "$DRY" -eq 1 ]; then
            echo "  [simulacion] $p: $h h sin visitas, se pararia"
            stopped=$((stopped + 1))
            continue
        fi
        echo "$(date '+%Y-%m-%d %H:%M') $p: $h h sin visitas, se para" | tee -a "$DOCKER_IDLE_LOG"
        docker_web_action parar "$p" > /dev/null 2>&1 && stopped=$((stopped + 1))
    done
    # (el registro, con lo ultimo)
    [ -f "$DOCKER_IDLE_LOG" ] && [ "$(wc -l < "$DOCKER_IDLE_LOG")" -gt 500 ] \
        && tail -n 200 "$DOCKER_IDLE_LOG" > "$DOCKER_IDLE_LOG.nuevo" && mv -f "$DOCKER_IDLE_LOG.nuevo" "$DOCKER_IDLE_LOG"
    [ $stopped -gt 0 ] || [ "${1:-}" != --decir ] || echo "Ningún proyecto lleva $h h sin visitas"
    return 0
}

# Que el temporizador este si hace falta (al arrancar un proyecto de Docker): con horas y sin el, se pone
function docker_idle_ensure() {
    [ "$DRY" -eq 1 ] && return 0
    if [ "$(docker_idle_hours)" -gt 0 ]; then
        docker_idle_timer_on || docker_idle_timer poner > /dev/null 2>&1
    fi
    return 0
}

# docker-reposo [estado] | horas <0-24> | comprobar
#   estado: Q|horas (0: nunca)|temporizador puesto (1/0)|lo ultimo que se ha parado
function docker_idle_command() {
    case ${1:-estado} in
        estado) echo "Q|$(docker_idle_hours)|$(docker_idle_timer_on && echo 1 || echo 0)|$(tail -n 1 "$DOCKER_IDLE_LOG" 2> /dev/null | tr '|' ' ')" ;;
        horas)
            [[ "$2" =~ ^([0-9]|1[0-9]|2[0-4])$ ]] || { echo "Las horas van de 0 (nunca) a 24"; return 1; }
            [ "$DRY" -eq 1 ] && { echo "  [simulacion] proyectos de Docker parados tras $2 h sin visitas"; return 0; }
            mkdir -p -m 700 "$DOCKER_DIR" && ( umask 077; echo "$2" > "$DOCKER_IDLE_FILE" ) || return 1
            if [ "$2" -gt 0 ]; then
                docker_idle_timer poner || { echo "No se ha podido poner el temporizador"; return 1; }
                echo "Los proyectos de Docker sin visitas se paran solos a las $2 h"
            else
                docker_idle_timer quitar
                echo "Los proyectos de Docker ya no se paran solos"
            fi ;;
        comprobar) docker_idle_check "$2" ;;
        *) echo "Uso: lvm-instalador docker-reposo [estado] | horas <0-24> | comprobar"; return 1 ;;
    esac
}

