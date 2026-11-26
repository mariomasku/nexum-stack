# Tablas con DATA DIRECTORY o INDEX DIRECTORY (guardan sus ficheros fuera de la carpeta de MariaDB):
# las que borra db_root_cleanup. Desde la 1.57.48 los volcados se cargan como root y esto solo repasa
# las bases de los usuarios lvm_bd_<base> de antes que se quedaran sin bloquear (db_drop_import_users)
DB_DIRECTORY_PY='
import re, sys
# Salida de SHOW CREATE TABLE con -N --batch: nombre<TAB>sentencia, con \n \t \\ escapados
def unesc(s):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t", "0": "\0"}.get(m.group(1), m.group(1)), s)
# La opcion de verdad es DATA DIRECTORY = <cadena>: las cadenas (un COMMENT o un DEFAULT que digan
# data directory), los nombres entre comillas y los comentarios no cuentan
def options(sql):
    sql = re.sub(r"\x27(?:[^\x27\\]|\\.|\x27\x27)*\x27", " Q ", sql)
    sql = re.sub(r"`(?:[^`]|``)*`", " I ", sql)
    return re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
for line in sys.stdin:
    name, _, create = line.rstrip("\n").partition("\t")
    if re.search(r"(?i)\b(DATA|INDEX)\s+DIRECTORY\s*=?\s*Q", options(unesc(create))):
        print("DROP TABLE IF EXISTS `%s`;" % unesc(name).replace("`", "``"))
'
# Bloquea el usuario de una base (con otra contraseña al azar): ya no puede entrar, pero lo suyo
# (vistas, disparadores) sigue funcionando. Se borra y se vuelve a crear con solo los permisos de su
# base: si durante la carga hubiera conseguido otros (globales, de otras bases, roles), no le quedan.
# db_lock_import_user <usuario> <cliente como root...>
function db_lock_import_user() {
    local user=$1 pass extra
    shift
    [[ "$user" =~ ^lvm_bd_[A-Za-z0-9_-]+$ ]] || return 0
    pass=$(head -c 18 /dev/urandom | base64 | tr -d '/+=\n')
    # Sin permiso para crear vistas, rutinas ni eventos: una rutina suya (DEFINER) no podria crear
    # despues otra INVOKER. Lo que ya tiene sigue funcionando (la proxima carga le vuelve a dar todo)
    local gdb=${user#lvm_bd_}
    gdb=${gdb//_/\\_}
    db_kill_user "$user" "$@"
    if ! "$@" -e "DROP USER IF EXISTS '$user'@'localhost';
            CREATE USER '$user'@'localhost' IDENTIFIED BY '$pass' ACCOUNT LOCK;
            GRANT ALL PRIVILEGES ON \`$gdb\`.* TO '$user'@'localhost';
            REVOKE CREATE VIEW, CREATE ROUTINE, ALTER ROUTINE, EVENT ON \`$gdb\`.* FROM '$user'@'localhost'" < /dev/null 2> /dev/null; then
        # (MariaDB sin DROP USER IF EXISTS o sin ACCOUNT LOCK: como antes, y sin lo de fuera de su base)
        "$@" -e "ALTER USER '$user'@'localhost' IDENTIFIED BY '$pass' ACCOUNT LOCK" < /dev/null 2> /dev/null
        "$@" -e "REVOKE ALL PRIVILEGES, GRANT OPTION FROM '$user'@'localhost'" < /dev/null 2> /dev/null
        "$@" -e "GRANT ALL PRIVILEGES ON \`$gdb\`.* TO '$user'@'localhost'" < /dev/null 2> /dev/null
        "$@" -e "REVOKE CREATE VIEW, CREATE ROUTINE, ALTER ROUTINE, EVENT ON \`$gdb\`.* FROM '$user'@'localhost'" < /dev/null 2> /dev/null
    fi
    # Lo que le quede fuera de su base (no deberia haber nada) se avisa
    extra=$("$@" -N --raw -e "SHOW GRANTS FOR '$user'@'localhost'" < /dev/null 2> /dev/null \
        | LVM_ON="ON \`$gdb\`.* TO " awk 'index($0, "GRANT USAGE ON *.* TO ") != 1 && !index($0, ENVIRON["LVM_ON"])' | wc -l)
    [ "${extra:-0}" -gt 0 ] && echo "Aviso: el usuario $user conserva permisos fuera de su base. Revisalo en phpMyAdmin (Cuentas de usuario)."
    db_kill_user "$user" "$@"
    return 0
}

# Corta las conexiones de un usuario de base (tambien un evento suyo en marcha). Como root.
# db_kill_user <usuario> <cliente como root...>
function db_kill_user() {
    local user=$1
    shift
    [[ "$user" =~ ^lvm_bd_[A-Za-z0-9_-]+$ ]] || return 0
    "$@" -e "KILL USER '$user'@'localhost'" < /dev/null 2> /dev/null
    return 0
}

# Repaso como root, al final de una carga (o de una que se corto): si en la base quedan vistas,
# rutinas o paquetes INVOKER, eventos o tablas con DATA DIRECTORY, root los borra (solo DROP: nunca
# se ejecutan ni se pasan a DEFINER de root) y avisa. db_root_cleanup <base> <cliente como root...>
function db_root_cleanup() {
    local db=$1 drop left
    shift
    [[ "$db" =~ ^[A-Za-z0-9_-]+$ ]] || return 0
    local w="TABLE_SCHEMA = '$db'" rw="ROUTINE_SCHEMA = '$db'" ew="EVENT_SCHEMA = '$db'"
    # (--force: en una MariaDB con las tablas del sistema antiguas, EVENTS o ROUTINES dan error y lo
    # demas tiene que seguir)
    drop=$( { "$@" --raw -N --force -e "SELECT CONCAT('DROP VIEW IF EXISTS \`$db\`.\`', REPLACE(TABLE_NAME, '\`', '\`\`'), '\`;')
                FROM information_schema.VIEWS WHERE $w AND SECURITY_TYPE = 'INVOKER';
            SELECT CONCAT(IF(ROUTINE_TYPE LIKE 'PACKAGE%', 'SET sql_mode = ORACLE; ', ''), 'DROP ', ROUTINE_TYPE,
                ' IF EXISTS \`$db\`.\`', REPLACE(ROUTINE_NAME, '\`', '\`\`'), '\`; SET sql_mode = DEFAULT;')
                FROM information_schema.ROUTINES WHERE $rw AND SECURITY_TYPE = 'INVOKER'
                ORDER BY ROUTINE_TYPE = 'PACKAGE';
            SELECT CONCAT('DROP EVENT IF EXISTS \`$db\`.\`', REPLACE(EVENT_NAME, '\`', '\`\`'), '\`;')
                FROM information_schema.EVENTS WHERE $ew;
            SELECT CONCAT('DROP TABLE IF EXISTS \`$db\`.\`', REPLACE(TABLE_NAME, '\`', '\`\`'), '\`;')
                FROM information_schema.TABLES WHERE $w AND TABLE_TYPE = 'BASE TABLE' AND CREATE_OPTIONS LIKE '%DIRECTORY%'" \
                < /dev/null 2> /dev/null
          "$@" --raw -N -e "SELECT CONCAT('SHOW CREATE TABLE \`$db\`.\`', REPLACE(TABLE_NAME, '\`', '\`\`'), '\`;')
                FROM information_schema.TABLES WHERE $w AND TABLE_TYPE = 'BASE TABLE' AND CREATE_OPTIONS LIKE '%partitioned%'" \
                < /dev/null 2> /dev/null | "$@" -N --batch --force 2> /dev/null | /usr/bin/python3 -I -c "$DB_DIRECTORY_PY" \
                | sed "s/^DROP TABLE IF EXISTS /DROP TABLE IF EXISTS \`$db\`./"; } )
    [ -z "$drop" ] && return 0
    printf '%s\n' "$drop" | "$@" --force > /dev/null 2>&1
    left=$("$@" --raw -N --force -e "SELECT CONCAT('vista ', TABLE_NAME) FROM information_schema.VIEWS WHERE $w AND SECURITY_TYPE = 'INVOKER';
        SELECT CONCAT(LOWER(ROUTINE_TYPE), ' ', ROUTINE_NAME) FROM information_schema.ROUTINES WHERE $rw AND SECURITY_TYPE = 'INVOKER';
        SELECT CONCAT('evento ', EVENT_NAME) FROM information_schema.EVENTS WHERE $ew" < /dev/null 2> /dev/null)
    echo "Aviso: en $db quedaban $(printf '%s\n' "$drop" | grep -c 'DROP ') cosas del volcado que no deben estar (vistas o"
    echo "rutinas INVOKER, eventos o tablas con DATA DIRECTORY): las ha borrado root."
    if [ -n "$left" ]; then
        echo "ATENCION: siguen en $db: $(printf '%s' "$left" | tr -c '[:alnum:]_ \n-' '?' | head -10 | paste -sd ',' - | sed 's/,/, /g')."
        echo "No abras esa base como root en phpMyAdmin hasta quitarlas."
    fi
    return 0
}

# Borra los usuarios temporales de la 1.37 (lvm_imp_*) y bloquea los de las bases (lvm_bd_*) que
# hayan quedado abiertos (una carga que no termino). Recibe el cliente de MariaDB como root.
function db_drop_import_users() {
    local u
    for u in $("$@" -N -e "SELECT User FROM mysql.user WHERE User LIKE 'lvm\\_imp\\_%' AND Host='localhost'" < /dev/null 2> /dev/null); do
        [[ "$u" =~ ^lvm_imp_[0-9a-f]+$ ]] && "$@" -e "DROP USER IF EXISTS '$u'@'localhost'" < /dev/null 2> /dev/null
    done
    local open_users old_tables=0
    open_users=$("$@" -N -e "SELECT User FROM mysql.global_priv WHERE User LIKE 'lvm\\_bd\\_%' AND Host='localhost'
            AND IFNULL(JSON_VALUE(Priv, '$.account_locked'), 'false') <> 'true'" < /dev/null 2> /dev/null) \
        || { old_tables=1; open_users=$("$@" -N -e "SELECT User FROM mysql.user WHERE User LIKE 'lvm\\_bd\\_%' AND Host='localhost'" \
            < /dev/null 2> /dev/null); }
    # (con las tablas del sistema antiguas no hay global_priv ni se sabe si estan bloqueados: todos)
    for u in $open_users; do
        # (una carga que se corto: lo que dejara en su base lo repasa root)
        db_kill_user "$u" "$@"
        db_lock_import_user "$u" "$@"
        # (con las tablas antiguas no se sabe cuales se cortaron: se bloquean todos, pero su base no se
        # repasa, que borraria lo que hayas creado despues a proposito)
        [ $old_tables -eq 0 ] && db_root_cleanup "${u#lvm_bd_}" "$@"
    done
    return 0
}

