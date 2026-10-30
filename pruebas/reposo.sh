#!/bin/bash
# Proyectos de Docker sin visitas (Linux 1.56.8, Mac 1.40.1): los que llevan las horas elegidas sin
# ninguna en el registro del Apache de Docker se paran solos (no los visitados, ni los que acaban de
# arrancar, ni si nexum-web arranco hace poco); el temporizador (systemd --user o LaunchAgent), las
# horas y la pagina de un proyecto parado. Con un Docker falso. Uso: reposo.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-reposo.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
grep -q '^function docker_idle_check() {' "$SRC" || { echo "  ok    (sin parar los proyectos sin visitas)"; exit 0; }
extract "$SRC" docker_idle_hours docker_idle_timer_on docker_idle_timer docker_started_at docker_idle_check \
    docker_idle_ensure docker_idle_command || exit 1
MAC=0
grep -q "LVM_SWIFT" "$SRC" && MAC=1
DRY=0 DOCKER_DIR=$W/docker LOG_DIR=$W/log SELF=/usr/bin/lvm-instalador TRUSTED_SCRIPT=/Library/Nexum/gestor/lvm-instalador.sh
DOCKER_IDLE_FILE=$DOCKER_DIR/reposo DOCKER_IDLE_LOG=$LOG_DIR/docker-reposo.log
DOCKER_IDLE_UNIT_DIR=$W/units DOCKER_IDLE_AGENT=dev.hexer.nexum-reposo DOCKER_IDLE_PLIST=$W/agents/dev.hexer.nexum-reposo.plist
mkdir -p "$LOG_DIR"
ago() { date -u -d "@$(( $(date +%s) - $1 * 3600 ))" +%Y-%m-%dT%H:%M:%S.123456789Z 2> /dev/null || date -u -r "$(( $(date +%s) - $1 * 3600 ))" +%Y-%m-%dT%H:%M:%S.123456789Z; }
# Docker falso: blog (visitado), tienda (sin visitas), nuevo (arranco hace 1 h), parado (no esta en marcha)
docker_ready() { true; }
docker_web_projects() { echo blog tienda nuevo parado; }
docker_web_domains() { case $1 in blog) echo blog-php84.docker.test; echo blog-php83.docker.test ;; tienda) echo tienda.es ;; nuevo) echo nuevo-php84.docker.test ;; parado) echo parado-php84.docker.test ;; esac; }
WEB_AGE=10
dk() { echo "$*" >> "$W/dk.log"
    case "$1" in
        ps) printf '%s\n' nexum-web nexum-pma nexum-blog-php83 nexum-tienda-php81 nexum-nuevo-php84 nexum-mariadb-11-8 ;;
        inspect) case ${@: -1} in nexum-web) ago $WEB_AGE ;; nexum-nuevo-php84) ago 1 ;; *) ago 8 ;; esac ;;
        logs) printf 'BLOG-php84.docker.test 127.0.0.1 [x] "GET / HTTP/1.1" 200 5\npma.docker.test 127.0.0.1 [x] "GET /" 200 1\n' ;;
    esac; }
docker_web_action() { echo "$*" >> "$W/parados.log"; }
systemctl() { echo "systemctl $*" >> "$W/timer.log"; [ "$*" != "--user is-active --quiet nexum-reposo.timer" ] || [ -f "$W/timer-on" ]; }
launchctl() { echo "launchctl $*" >> "$W/timer.log"; [ "$1" != print ] || [ -f "$W/timer-on" ]; }

check "por defecto: a las 3 h" '[ "$(docker_idle_hours)" == 3 ]'
out=$(docker_idle_check 2>&1)
check "sin visitas en esas horas: se para (y se apunta cuando)" 'grep -qx "parar tienda" "$W/parados.log" && grep -q " tienda: 3 h sin visitas, se para$" "$DOCKER_IDLE_LOG"'
check "visitado (en cualquiera de sus dominios, sin mirar mayusculas): sigue" '! grep -q "parar blog" "$W/parados.log"'
check "arranco hace menos de esas horas: sigue" '! grep -q "parar nuevo" "$W/parados.log"'
check "los que no estan en marcha, ni se miran" '! grep -q "parar parado" "$W/parados.log"'
check "phpMyAdmin no cuenta como visita de nadie, y el registro se lee solo de esas horas" 'grep -q "logs --since 3h nexum-web" "$W/dk.log"'
: > "$W/parados.log"; WEB_AGE=1
docker_idle_check > /dev/null 2>&1
check "nexum-web arranco hace poco (su registro no alcanza): no se para nada" '[ ! -s "$W/parados.log" ]'
WEB_AGE=10
DRY=1 docker_idle_check > "$W/o" 2>&1
check "simulacion: lo dice, no para nada ni lo apunta" 'grep -q "\[simulacion\] tienda" "$W/o" && [ ! -s "$W/parados.log" ] && [ "$(wc -l < "$DOCKER_IDLE_LOG")" == 1 ]'

# Las horas y el temporizador
check "horas: de 0 a 24" '! docker_idle_command horas 25 > /dev/null && ! docker_idle_command horas x > /dev/null'
docker_idle_command horas 6 > "$W/o"
check "horas: se guardan (solo tuyo) y se pone el temporizador" '[ "$(docker_idle_hours)" == 6 ] && [ "$(stat -c %a "$DOCKER_IDLE_FILE" 2> /dev/null || stat -f %Lp "$DOCKER_IDLE_FILE")" == 600 ] && grep -q "a las 6 h" "$W/o"'
if [ $MAC -eq 1 ]; then
    check "temporizador (Mac): un LaunchAgent tuyo, cada 15 minutos, con docker-reposo comprobar" 'grep -q "<integer>900</integer>" "$DOCKER_IDLE_PLIST" && grep -q "<string>$TRUSTED_SCRIPT</string><string>docker-reposo</string><string>comprobar</string>" "$DOCKER_IDLE_PLIST" && grep -q "launchctl bootstrap gui/" "$W/timer.log" && python3 -c "import plistlib, sys; plistlib.load(open(sys.argv[1], \"rb\"))" "$DOCKER_IDLE_PLIST"'
else
    check "temporizador: de systemctl --user, cada 15 minutos, con docker-reposo comprobar" 'grep -qx "OnUnitActiveSec=15min" "$DOCKER_IDLE_UNIT_DIR/nexum-reposo.timer" && grep -q "^ExecStart=.* docker-reposo comprobar$" "$DOCKER_IDLE_UNIT_DIR/nexum-reposo.service" && grep -q "enable --now nexum-reposo.timer" "$W/timer.log"'
fi
docker_idle_command horas 0 > "$W/o"
check "nunca: no se para nada y se quita el temporizador" '[ "$(docker_idle_hours)" == 0 ] && : > "$W/parados.log" && docker_idle_check > /dev/null && [ ! -s "$W/parados.log" ] && [ ! -e "$DOCKER_IDLE_UNIT_DIR/nexum-reposo.timer" ] && [ ! -e "$DOCKER_IDLE_PLIST" ]'
docker_idle_command horas 3 > /dev/null; : > "$W/timer.log"; touch "$W/timer-on"
docker_idle_ensure
check "al arrancar: si el temporizador ya esta, no se toca" '! grep -q "enable\|bootstrap" "$W/timer.log"'
rm -f "$W/timer-on"; docker_idle_ensure
check "al arrancar: si falta, se pone" 'grep -q "enable --now\|bootstrap" "$W/timer.log"'
check "estado: horas, temporizador y lo ultimo" 'docker_idle_command | grep -q "^Q|3|0| *[0-9-]* [0-9:]* tienda: 3 h sin visitas, se para$"'

# La pagina de un proyecto parado, y el temporizador al arrancar uno y al mirar Docker
check "proyecto parado: su web lo dice (502 y 503 del Apache de Docker)" 'awk "/^function docker_web_site\\(\\)/,/^}/" "$SRC" > "$W/site" && grep -qF "ErrorDocument 502 \"%s\"" "$W/site" && grep -qF "ErrorDocument 503 \"%s\"" "$W/site" && grep -q "^DOCKER_STOPPED_MSG=\"Este proyecto de Docker está parado" "$SRC"'
check "al arrancar un proyecto y al mirar Docker, el temporizador" '[ "$(grep -c "^            docker_idle_ensure$\|^        \[ -n \"\$(docker_web_projects)\" \] && docker_idle_ensure$" "$SRC")" == 2 ]'
if [ $MAC -eq 1 ]; then
    check "ventana (Mac): en Configuración, Docker, cuántas horas" 'grep -q "^          IdleStopCard()$" "$SRC" && grep -q "runQuick(\[\"docker-reposo\", \"horas\", h\])" "$SRC"'
else
    check "ventana: en Configuración, Docker, cuántas horas" 'grep -q "row = ActionRow(\"Parar los proyectos sin visitas\"," "$SRC" && grep -q "\[\"docker-reposo\", \"horas\", c.get_active_id()\]" "$SRC"'
fi
exit $fail
