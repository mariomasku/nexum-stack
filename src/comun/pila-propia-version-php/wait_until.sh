# Espera hasta <segundos> a que se cumpla una condicion
function wait_until() {
    local seconds=$1 i
    shift

    for i in $(seq $(( seconds * 10 ))); do
        "$@" && return 0
        sleep 0.1
    done

    return 1
}

function stopped() {
    ! running "$1"
}

function mysql_ready() {
    running "$MYSQL_PID" && [ -S "$MYSQL_SOCK" ]
}

