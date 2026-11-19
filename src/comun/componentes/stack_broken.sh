# stack_broken <carpeta de sus componentes>: las piezas de una pila propia que estan dañadas, con los
# nombres de Componentes (PHP Apache MariaDB ProFTPD Perl phpMyAdmin), en una linea. Nada si todo esta bien.
# Dañada es que falte su programa o, en Linux, que no responda (--version): como la MariaDB que traia uno
# de sus plugins en lugar de MariaDB, hasta la 1.57.29. En el Mac solo se mira que esten (sus programas no
# se han podido probar asi: uno bueno que no respondiera haria compilar la version sin motivo).
# Con alguna dañada, Componentes la ofrece y al actualizarla se rehace (con sus bases de datos)
function stack_broken() {
    local d=$1 run=1 bad=()
    [[ "$OSTYPE" == darwin* ]] && run=0
    # stack_ok <programa> [argumentos]: que este y (en Linux) que responda, sin entrada ni salida
    function stack_ok() {
        [ -x "$d/$1" ] || return 1
        [ $run -eq 1 ] || return 0
        "$d/$1" "${@:2}" < /dev/null > /dev/null 2>&1
    }
    { stack_ok php/bin/php -n -v && stack_ok php/sbin/php-fpm -n -v; } || bad+=(PHP)
    stack_ok apache2/bin/httpd -v || bad+=(Apache)
    { stack_ok mysql/bin/mariadbd --version && stack_ok mysql/bin/mariadb --version \
        && [ -x "$d/mysql/bin/mariadbd-safe" ]; } || bad+=(MariaDB)
    stack_ok proftpd/sbin/proftpd -v || bad+=(ProFTPD)
    stack_ok perl/bin/perl -e 1 || bad+=(Perl)
    [ -f "$d/phpmyadmin/index.php" ] || bad+=(phpMyAdmin)
    unset -f stack_ok
    echo "${bad[*]}"
}
