#!/bin/bash
# Referencia para mac-xampp.sh: el script "xampp" que dejaba el Mac 1.27.1 en sus pilas propias
# (MariaDB arrancado y parado como root). La copia completa del script 1.27.1 se perdio con el
# scratchpad; esto es solo su bloque xampp, rehecho a partir del Mac 1.31.1 quitando los cambios
# de la 1.28.0 (as_web, WEB_USER, PATH del sistema). mac-xampp.sh solo lee el heredoc de abajo.
exit 0

    sed -e "s|@ROOT@|$target|g" -e "s|@NAME@|$short|g" -e "s|@NEED_ROOT@|$(( 1 - test_mode ))|g" > "$S/xampp" <<'EOF'
#!/bin/bash
# Arranque y parada de XAMPP-@NAME@ (pila propia creada por lvm-instalador):
# Apache con PHP-FPM, MariaDB y ProFTPD.
# Uso: xampp start|stop|restart|status|startapache|stopapache|reloadapache|startmysql|stopmysql|startftp|stopftp

ROOT=@ROOT@
# OpenSSL: solo su configuracion (no la de Homebrew, que es de tu usuario)
export OPENSSL_CONF=$ROOT/etc/openssl.cnf
export OPENSSL_MODULES=$ROOT/lib/ossl-modules
APACHE_PID=$ROOT/logs/httpd.pid
MYSQL_PID=$ROOT/var/mysql/mysqld.pid
MYSQL_SOCK=$ROOT/var/mysql/mysql.sock
FTP_PID=$ROOT/var/proftpd/proftpd.pid

if [ @NEED_ROOT@ -eq 1 ] && [ "$(id -u)" -ne 0 ]; then
    echo "Hay que ejecutarlo como administrador: sudo $0 $*"
    exit 1
fi

function running() {
    [ -f "$1" ] && kill -0 "$(cat "$1" 2> /dev/null)" 2> /dev/null
}

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

# Programa que ya escucha en un puerto (el Apache de macOS, otro XAMPP...)
function port_owner() {
    lsof -nP -iTCP:"$1" -sTCP:LISTEN 2> /dev/null | awk 'NR == 2 {print $1 " (PID " $2 ")"}'
}

function start_apache() {
    running "$APACHE_PID" && { echo "Apache ya estaba arrancado."; return 0; }

    "$ROOT/bin/pvm-php-fpm" start
    # Como XAMPP: los avisos del arranque (vhosts sin carpeta, certificados...) van al log
    if "$ROOT/apache2/bin/httpd" -f "$ROOT/etc/httpd.conf" -E "$ROOT/logs/error_log" -k start >> "$ROOT/logs/error_log" 2>&1 \
        && wait_until 10 running "$APACHE_PID"; then
        echo "Apache arrancado."
    else
        local port=$(sed -n 's/^Listen //p' "$ROOT/etc/httpd.conf" | head -1)
        local owner=$(port_owner "$port")
        echo "Apache no ha arrancado. Revisa $ROOT/logs/error_log"
        [ -n "$owner" ] && echo "El puerto $port ya lo usa $owner. Si es el Apache de macOS: sudo apachectl stop"
        return 1
    fi
}

function stop_apache() {
    if running "$APACHE_PID"; then
        "$ROOT/apache2/bin/httpd" -f "$ROOT/etc/httpd.conf" -k stop
        wait_until 15 stopped "$APACHE_PID"
        echo "Apache parado."
    fi
    "$ROOT/bin/pvm-php-fpm" stop
}

function reload_apache() {
    "$ROOT/bin/pvm-php-fpm" reload
    running "$APACHE_PID" && "$ROOT/apache2/bin/httpd" -f "$ROOT/etc/httpd.conf" -E "$ROOT/logs/error_log" -k graceful >> "$ROOT/logs/error_log" 2>&1 \
        && echo "Apache recargado."
}

function start_mysql() {
    running "$MYSQL_PID" && { echo "MariaDB ya estaba arrancado."; return 0; }

    # mariadbd-safe busca sus herramientas desde la carpeta de MariaDB
    (cd "$ROOT/mysql" && nohup ./bin/mariadbd-safe --defaults-file="$ROOT/etc/my.cnf" > /dev/null 2>&1 &)
    if wait_until 60 mysql_ready; then
        echo "MariaDB arrancado."
    else
        echo "MariaDB no ha arrancado. Revisa $ROOT/var/mysql/mysqld.err"
        return 1
    fi
}

function stop_mysql() {
    running "$MYSQL_PID" || return 0

    kill "$(cat "$MYSQL_PID")"
    wait_until 60 stopped "$MYSQL_PID" && echo "MariaDB parado." || echo "MariaDB sigue parandose."
}

function start_ftp() {
    running "$FTP_PID" && { echo "ProFTPD ya estaba arrancado."; return 0; }

    if "$ROOT/proftpd/sbin/proftpd" -c "$ROOT/etc/proftpd.conf" 2> /dev/null && wait_until 5 running "$FTP_PID"; then
        echo "ProFTPD arrancado."
    else
        echo "ProFTPD no ha arrancado. Revisa $ROOT/logs/proftpd.log"
        return 1
    fi
}

function stop_ftp() {
    running "$FTP_PID" || return 0

    kill "$(cat "$FTP_PID")"
    wait_until 10 stopped "$FTP_PID"
    echo "ProFTPD parado."
}

function status() {
    local name pid

    echo "XAMPP-@NAME@ (pila propia)"
    for name in Apache MariaDB ProFTPD; do
        case $name in
            Apache) pid=$APACHE_PID ;;
            MariaDB) pid=$MYSQL_PID ;;
            ProFTPD) pid=$FTP_PID ;;
        esac
        running "$pid" && echo "$name esta arrancado." || echo "$name no esta arrancado."
    done
    "$ROOT/bin/pvm-php-fpm" status
}

case "$1" in
    # El FTP solo si se ha activado (xampp startftp; lo quita xampp stopftp)
    start) echo "Arrancando XAMPP-@NAME@..."; start_mysql; start_apache; if [ -f "$ROOT/etc/lvm-startftp" ]; then start_ftp; fi ;;
    stop) echo "Parando XAMPP-@NAME@..."; stop_apache; stop_mysql; stop_ftp ;;
    restart|reload) "$0" stop; "$0" start ;;
    status) status ;;
    startapache) start_apache ;;
    stopapache) stop_apache ;;
    reloadapache) reload_apache ;;
    restartapache) stop_apache; start_apache ;;
    startmysql) start_mysql ;;
    stopmysql) stop_mysql ;;
    restartmysql) stop_mysql; start_mysql ;;
    startftp) touch "$ROOT/etc/lvm-startftp"; start_ftp ;;
    stopftp) rm -f "$ROOT/etc/lvm-startftp"; stop_ftp ;;
    *) sed -n '4p' "$0" | sed 's/^# //'; exit 1 ;;
esac
EOF
