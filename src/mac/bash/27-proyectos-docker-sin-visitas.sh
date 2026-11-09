# ===========================================================================
# Proyectos de Docker sin visitas: se paran solos
# ===========================================================================
# Un proyecto del Apache de Docker en marcha que lleva DOCKER_IDLE_FILE horas sin ninguna visita (en el
# registro de nexum-web, que apunta el dominio de cada una: tambien las que llegan por el tunel) se para,
# y con el lo comun que ya no use nadie (su MariaDB, el Apache de Docker). Solo si el y nexum-web llevan
# en marcha al menos esas horas (si no, su registro no alcanza). Con 0, nunca. Por defecto, 3 horas
DOCKER_IDLE_FILE=$DOCKER_DIR/reposo
DOCKER_STOPPED_MSG="Este proyecto de Docker está parado (se para solo tras unas horas sin visitas). Arráncalo en Nexum Dev Stack, pestaña Docker."
DOCKER_IDLE_LOG=$LOG_DIR/docker-reposo.log
function docker_idle_hours() {
    local v
    v=$(head -c 10 "$DOCKER_IDLE_FILE" 2> /dev/null | tr -d ' \n')
    [ -f "$DOCKER_IDLE_FILE" ] || v=3
    [[ "$v" =~ ^([0-9]|1[0-9]|2[0-4])$ ]] || v=3
    echo "$v"
}

# El temporizador: un LaunchAgent tuyo (sin root) que cada 15 minutos lanza docker-reposo comprobar
DOCKER_IDLE_AGENT=dev.hexer.nexum-reposo
DOCKER_IDLE_PLIST=${LVM_REPOSO_PLIST:-$HOME/Library/LaunchAgents/$DOCKER_IDLE_AGENT.plist}
function docker_idle_timer_on() {
    [ -f "$DOCKER_IDLE_PLIST" ] && launchctl print "gui/$(id -u)/$DOCKER_IDLE_AGENT" > /dev/null 2>&1
}
function docker_idle_timer() {
    if [ "$1" == poner ]; then
        mkdir -p "$(dirname "$DOCKER_IDLE_PLIST")" "$LOG_DIR" || return 1
        cat > "$DOCKER_IDLE_PLIST.nuevo" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$DOCKER_IDLE_AGENT</string>
    <key>ProgramArguments</key>
    <array><string>/bin/bash</string><string>$TRUSTED_SCRIPT</string><string>docker-reposo</string><string>comprobar</string></array>
    <key>StartInterval</key><integer>900</integer>
    <key>RunAtLoad</key><false/>
    <key>StandardOutPath</key><string>/dev/null</string>
    <key>StandardErrorPath</key><string>/dev/null</string>
</dict>
</plist>
EOF
        mv -f "$DOCKER_IDLE_PLIST.nuevo" "$DOCKER_IDLE_PLIST" || return 1
        launchctl bootout "gui/$(id -u)/$DOCKER_IDLE_AGENT" > /dev/null 2>&1
        launchctl bootstrap "gui/$(id -u)" "$DOCKER_IDLE_PLIST"
    else
        launchctl bootout "gui/$(id -u)/$DOCKER_IDLE_AGENT" > /dev/null 2>&1
        rm -f "$DOCKER_IDLE_PLIST"
    fi
}

#@incluir comun/proyectos-docker-sin-visitas/docker_started_at.sh
