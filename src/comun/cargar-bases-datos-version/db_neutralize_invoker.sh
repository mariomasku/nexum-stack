# Vistas y rutinas SQL SECURITY INVOKER de un volcado: se ejecutarian con los permisos de quien las
# use (root en phpMyAdmin, o en la web si su wp-config.php usa root). Pasan a DEFINER, de
# lvm_bd_<base> (lo hace ese mismo usuario). Con --force: una vista rota del volcado no para las
# demas. Las que no se dejen cambiar se borran, y se avisa. db_neutralize_invoker <base> <cliente...>
function db_neutralize_invoker() {
    local db=$1 left
    shift
    local list="FROM information_schema.VIEWS WHERE TABLE_SCHEMA = DATABASE() AND SECURITY_TYPE = 'INVOKER'"
    local rlist="FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND SECURITY_TYPE = 'INVOKER'"
    "$@" --raw -N "$db" -e "SELECT CONCAT('ALTER SQL SECURITY DEFINER VIEW \`', REPLACE(TABLE_NAME, '\`', '\`\`'), '\` AS ', VIEW_DEFINITION, ';') $list;
        SELECT CONCAT('ALTER ', ROUTINE_TYPE, ' \`', REPLACE(ROUTINE_NAME, '\`', '\`\`'), '\` SQL SECURITY DEFINER;') $rlist" \
        < /dev/null 2> /dev/null | "$@" --force "$db" > /dev/null 2>&1
    left=$("$@" --raw -N "$db" -e "SELECT CONCAT('vista ', TABLE_NAME) $list; SELECT CONCAT(LOWER(ROUTINE_TYPE), ' ', ROUTINE_NAME) $rlist" < /dev/null 2> /dev/null)
    [ -z "$left" ] && return 0
    "$@" --raw -N "$db" -e "SELECT CONCAT('DROP VIEW IF EXISTS \`', REPLACE(TABLE_NAME, '\`', '\`\`'), '\`;') $list;
        SELECT CONCAT('DROP ', ROUTINE_TYPE, ' IF EXISTS \`', REPLACE(ROUTINE_NAME, '\`', '\`\`'), '\`;') $rlist" \
        < /dev/null 2> /dev/null | "$@" --force "$db" > /dev/null 2>&1
    echo "Aviso: el volcado traia vistas o rutinas SQL SECURITY INVOKER que no se han podido pasar a"
    echo "DEFINER (rotas o mal hechas). Se han borrado, porque se ejecutarian con los permisos de quien"
    echo "las usara: $(printf '%s' "$left" | tr -c '[:alnum:]_ \n-' '?' | head -20 | paste -sd ',' - | sed 's/,/, /g')"
    # (lo que no haya podido borrar este usuario, como los paquetes de MariaDB 10.4, lo borra root
    # en db_root_cleanup)
    return 0
}

# Eventos y tablas con DATA DIRECTORY o INDEX DIRECTORY de un volcado. Los eventos se ejecutan solos
# (si el planificador de MariaDB esta encendido) aunque el usuario de la base este bloqueado, y
# podrian volver a crear vistas INVOKER. Las tablas con esas opciones guardan sus ficheros fuera de
# la carpeta de MariaDB (en las de otras versiones, en /tmp...). Se borran, y se avisa (lo hace el
# usuario de la base). db_neutralize_extras <base> <cliente...>
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
function db_neutralize_extras() {
    local db=$1 events tables drop
    shift
    local elist="FROM information_schema.EVENTS WHERE EVENT_SCHEMA = DATABASE()"
    events=$("$@" --raw -N "$db" -e "SELECT EVENT_NAME $elist" < /dev/null 2> /dev/null)
    if [ -n "$events" ]; then
        "$@" --raw -N "$db" -e "SELECT CONCAT('DROP EVENT IF EXISTS \`', REPLACE(EVENT_NAME, '\`', '\`\`'), '\`;') $elist" \
            < /dev/null 2> /dev/null | "$@" --force "$db" > /dev/null 2>&1
        echo "Aviso: el volcado traia eventos programados (se ejecutan solos en el servidor). Se han"
        echo "borrado: $(printf '%s' "$events" | tr -c '[:alnum:]_ \n-' '?' | head -20 | paste -sd ',' - | sed 's/,/, /g')"
    fi
    # Las particionadas no lo dicen en CREATE_OPTIONS: se mira su SHOW CREATE TABLE
    local tlist="FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE'"
    drop=$( { "$@" --raw -N "$db" -e "SELECT CONCAT('DROP TABLE IF EXISTS \`', REPLACE(TABLE_NAME, '\`', '\`\`'), '\`;')
                $tlist AND CREATE_OPTIONS LIKE '%DIRECTORY%'" < /dev/null 2> /dev/null
              "$@" --raw -N "$db" -e "SELECT CONCAT('SHOW CREATE TABLE \`', REPLACE(TABLE_NAME, '\`', '\`\`'), '\`;')
                $tlist AND CREATE_OPTIONS LIKE '%partitioned%'" < /dev/null 2> /dev/null \
                  | "$@" -N --batch --force "$db" 2> /dev/null | /usr/bin/python3 -I -c "$DB_DIRECTORY_PY"; } | sort -u)
    [ -z "$drop" ] && return 0
    tables=$(printf '%s\n' "$drop" | sed -e 's/^DROP TABLE IF EXISTS `//' -e 's/`;$//')
    printf '%s\n' "$drop" | "$@" --force "$db" > /dev/null 2>&1
    echo "Aviso: el volcado traia tablas con DATA DIRECTORY o INDEX DIRECTORY, que guardan sus ficheros"
    echo "fuera de la carpeta de MariaDB. Se han borrado (con sus ficheros): $(printf '%s' "$tables" \
        | tr -c '[:alnum:]_ \n-' '?' | head -20 | paste -sd ',' - | sed 's/,/, /g')"
    if [ -n "$("$@" --raw -N "$db" -e "SELECT 1 $tlist AND CREATE_OPTIONS LIKE '%DIRECTORY%' LIMIT 1" < /dev/null 2> /dev/null)" ]; then
        echo "ATENCION: siguen quedando tablas con DATA DIRECTORY en $db."
    fi
    return 0
}

# Huella mysql_native_password de una contraseña leida de la entrada (asi no va en ninguna linea de
# ordenes, que cualquier usuario del equipo ve con ps)
function db_pass_hash() {
    python3 -I -c 'import hashlib, sys; p = sys.stdin.buffer.read(); print("*" + hashlib.sha1(hashlib.sha1(p).digest()).hexdigest().upper())'
}

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

