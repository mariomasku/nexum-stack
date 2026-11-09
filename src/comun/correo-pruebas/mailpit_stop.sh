function mailpit_stop() {
    local p i
    p=$(mailpit_pid)
    if [ -z "$p" ]; then
        rm -f "$MAILPIT_DATA/mailpit.pid"
        return 0
    fi
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] se para Mailpit ($p)"
        return 0
    fi
    kill "$p" 2> /dev/null
    for i in $(seq 50); do
        kill -0 "$p" 2> /dev/null || break
        sleep 0.1
    done
    kill -0 "$p" 2> /dev/null && kill -9 "$p" 2> /dev/null
    rm -f "$MAILPIT_DATA/mailpit.pid"
    echo "Mailpit parado"
}

# Mailpit en marcha solo con el correo de pruebas encendido, instalado y la version activa en marcha
# (--suave: lo pasa a mailpit_start)
function mailpit_sync() {
    if mail_on && mailpit_installed && lampp_running; then
        mailpit_start "$1"
    else
        mailpit_stop
    fi
}

