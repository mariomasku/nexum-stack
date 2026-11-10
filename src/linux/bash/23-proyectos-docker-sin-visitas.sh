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

# El temporizador: uno de systemctl --user (sin root, como Docker sin root) que cada 15 minutos lanza
# docker-reposo comprobar, aunque la ventana este cerrada
DOCKER_IDLE_UNIT_DIR=${LVM_REPOSO_UNITS:-$HOME/.config/systemd/user}
function docker_idle_timer_on() {
    systemctl --user is-active --quiet nexum-reposo.timer 2> /dev/null || return 1
    # Uno puesto cuando la orden era lvm-instalador (ExecStart=/usr/local/bin/lvm-instalador o el script
    # de /opt/lvm-instalador, que ya no existen): se rehace con nexum, y asi sigue funcionando
    if grep -q '^ExecStart=\(.*/lvm-instalador\|/opt/lvm-instalador/lvm-instalador\.sh\) docker-reposo ' \
            "$DOCKER_IDLE_UNIT_DIR/nexum-reposo.service" 2> /dev/null; then
        docker_idle_timer poner > /dev/null 2>&1
    fi
    return 0
}
function docker_idle_timer() {
    local bin
    if [ "$1" == poner ]; then
        # (la orden nexum instalada; si no, este mismo)
        bin=$(command -v nexum 2> /dev/null)
        [ -n "$bin" ] || bin=$SELF
        mkdir -p "$DOCKER_IDLE_UNIT_DIR" || return 1
        printf '[Unit]\nDescription=Nexum Dev Stack: parar los proyectos de Docker sin visitas\n\n[Service]\nType=oneshot\nExecStart=%s docker-reposo comprobar\n' \
            "$bin" > "$DOCKER_IDLE_UNIT_DIR/nexum-reposo.service" || return 1
        printf '[Unit]\nDescription=Nexum Dev Stack: cada 15 minutos, los proyectos de Docker sin visitas\n\n[Timer]\nOnBootSec=10min\nOnUnitActiveSec=15min\n\n[Install]\nWantedBy=timers.target\n' \
            > "$DOCKER_IDLE_UNIT_DIR/nexum-reposo.timer" || return 1
        systemctl --user daemon-reload && systemctl --user enable --now nexum-reposo.timer > /dev/null 2>&1
    else
        systemctl --user disable --now nexum-reposo.timer > /dev/null 2>&1
        rm -f "$DOCKER_IDLE_UNIT_DIR/nexum-reposo.service" "$DOCKER_IDLE_UNIT_DIR/nexum-reposo.timer"
        systemctl --user daemon-reload > /dev/null 2>&1
    fi
}

#@incluir comun/proyectos-docker-sin-visitas/docker_started_at.sh
