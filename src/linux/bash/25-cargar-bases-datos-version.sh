# ===========================================================================
# Cargar bases de datos en la version activa
# ===========================================================================

# El cliente /opt/lampp/bin/mysql lee el my.cnf de la version activa (socket y puerto). Si root tiene
# contraseña, se pasa en la variable MYSQL_PWD
DB_SYSTEM="information_schema|mysql|performance_schema|phpmyadmin|sys|test"
# Para pruebas se puede usar otro cliente (por ejemplo uno contra un MariaDB temporal)
DB_CLIENT=${LVM_BD_CLIENTE:-/opt/lampp/bin/mysql}
# El cliente y mysqldump de XAMPP leen tambien ~/.my.cnf y $MYSQL_HOME/my.cnf, que cualquier programa
# tuyo puede preparar (plugin-dir/default-auth les hacen cargar una biblioteca) y se ejecutan en la
# terminal de la tarea, con el permiso de sudo recordado: siempre sin esos ficheros
DB_SAFE=(/usr/bin/env -u MYSQL_HOME -u MARIADB_HOME HOME=/nonexistent)

# Tamaño de cada BBDD (datos e indices, de information_schema) de la version activa en marcha. Se
# guarda para enseñar tambien el de las demas versiones (sus carpetas son de mysql y no se pueden
# leer sin sudo): Z|version duena de las BBDD|base|bytes|cuando se midio (segundos desde 1970)
function gui_db_sizes() {
    local cache=$LOG_DIR/cache/bbdd-tamanos active owner out check now
    now=$(date +%s)
    mkdir -p -m 700 "$LOG_DIR/cache" || return 0
    active=$(active_dir)
    if [ -n "$active" ] && check=$(gui_db_check) && [[ "$check" == ok\|* ]]; then
        owner=$(data_owner "$active")
        owner=${owner:-${active#/opt/lampp-}}
        out=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -B -e "SELECT table_schema, SUM(data_length + index_length) FROM information_schema.tables GROUP BY table_schema" < /dev/null 2> /dev/null)
        if [ -n "$out" ] && valid_version_name "$owner"; then
            { [ -f "$cache" ] && grep -v "^$owner|" "$cache"
              awk -F'\t' -v v="$owner" -v t="$now" '$1 ~ /^[A-Za-z0-9_-]+$/ && $2 ~ /^[0-9]+$/ { print v "|" $1 "|" $2 "|" t }' <<< "$out"
            } > "$cache.nuevo" && mv -f "$cache.nuevo" "$cache"
        fi
    fi
    [ -f "$cache" ] && grep -E '^[A-Za-z0-9._-]+\|[A-Za-z0-9_-]+\|[0-9]+\|[0-9]+$' "$cache" | sed 's/^/Z|/'
    return 0
}

# Lo que ocupa en el disco cada proyecto de /opt/htdocs (du), para la lista de Proyectos:
# T|carpeta|bytes|cuando se midio. Se guarda y se vuelven a medir los que tienen la medida de hace mas
# de 6 horas, de 10 en 10 (du tarda mas de un minuto con todos), los mas antiguos antes. Si quedan mas
# por medir, lo dice al final (F|cuantos) y la ventana pide la siguiente tanda. Con "ya", sin esperar
function gui_project_sizes() {
    local cache=$LOG_DIR/cache/proyectos-tamanos now dir name b t left
    local -a stale=()
    local -A when=() redo=()
    now=$(date +%s)
    mkdir -p -m 700 "$LOG_DIR/cache" || return 0
    if [ -f "$cache" ]; then
        while IFS='|' read -r name b t; do [[ "$t" =~ ^[0-9]+$ ]] && when[$name]=$t; done < "$cache"
    fi
    for dir in "$HTDOCS_DIR"/*; do
        name=${dir##*/}
        [ -d "$dir" ] && [ ! -L "$dir" ] && [[ "$name" != *'|'* ]] || continue
        t=${when[$name]:-0}
        if [ "$1" == ya ] || [ $((now - t)) -ge 21600 ]; then
            stale+=("$t|$name")
        fi
    done
    left=0
    if [ ${#stale[@]} -gt 0 ]; then
        mapfile -t stale < <(printf '%s\n' "${stale[@]}" | sort -t'|' -k1,1n)
        left=$(( ${#stale[@]} > 10 ? ${#stale[@]} - 10 : 0 ))
        local -a dirs=()
        for b in "${stale[@]:0:10}"; do
            name=${b#*|}
            redo[$name]=1
            dirs+=("$HTDOCS_DIR/$name")
        done
        # (sin salir del disco ni seguir enlaces; lo que no se puede leer no cuenta)
        { [ -f "$cache" ] && while IFS='|' read -r name b t; do
              [ -z "${redo[$name]}" ] && [ -d "$HTDOCS_DIR/$name" ] && [ ! -L "$HTDOCS_DIR/$name" ] && echo "$name|$b|$t"
          done < "$cache"
          du -sb --one-file-system "${dirs[@]}" 2> /dev/null | while IFS=$'\t' read -r b dir; do
              [[ "$b" =~ ^[0-9]+$ ]] && echo "${dir##*/}|$b|$now"
          done
        } > "$cache.nuevo" && mv -f "$cache.nuevo" "$cache"
    fi
    [ -f "$cache" ] && grep -E '^[^|]+\|[0-9]+\|[0-9]+$' "$cache" | sed 's/^/T|/'
    [ "$left" -gt 0 ] && echo "F|$left"
    return 0
}

# ¿Se puede cargar en la version activa? ok|carpeta|version de MariaDB / clave|carpeta / no|motivo
function gui_db_check() {
    local active=$(active_dir)
    if [ -z "$active" ]; then
        echo "no|No hay ninguna versión activa."

        return 0
    fi

    local folder=${active#/opt/lampp-} out
    if [ ! -x "$DB_CLIENT" ]; then
        echo "no|lampp-$folder no tiene el cliente de MariaDB (bin/mysql)."

        return 0
    fi

    if out=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e 'SELECT VERSION()' < /dev/null 2>&1); then
        echo "ok|$folder|${out%%-*}"
    elif [[ "$out" == *1045* ]] || [[ "$out" == *"Access denied"* ]]; then
        echo "clave|$folder"
    else
        echo "no|El MariaDB de lampp-$folder no está en marcha. Arráncalo en Versiones de PHP."
    fi
}

# Conexion con el MariaDB activo: deja en DB_FOLDER la carpeta de la version activa y en DB_VERSION
# la de MariaDB. Si no se puede, explica por que (sale con 3 si hace falta la contraseña de root)
function db_connect() {
    local check=$(gui_db_check)
    case "$check" in
        ok\|*)
            DB_FOLDER=$(cut -d'|' -f2 <<< "$check")
            DB_VERSION=$(cut -d'|' -f3 <<< "$check")
            ;;
        clave\|*)
            echo "MariaDB pide la contraseña de root: ponla en la variable MYSQL_PWD"

            return 3
            ;;
        *)
            echo "${check#no|}"

            return 1
            ;;
    esac
}

#@incluir comun/cargar-bases-datos-version/db_valid_name.sh
# crear-bd <base>: base vacia en utf8mb4_general_ci (como las de XAMPP)
function create_database() {
    local db=$1 rc
    db_valid_name "$db" || return 1
    db_connect
    rc=$?
    [ $rc -ne 0 ] && return $rc

    if db_exists "$db"; then
        echo "Ya hay una base de datos $db en lampp-$DB_FOLDER"

        return 1
    fi

    run "${DB_SAFE[@]}" "$DB_CLIENT" -uroot -e "CREATE DATABASE \`$db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci" < /dev/null || return 1
    db_note_import "/opt/lampp/var/mysql" "$db"
    echo "Base de datos $db creada en lampp-$DB_FOLDER"
}

# Tablas y tamaño (bytes) de una base: I|tablas|bytes
function gui_db_info() {
    local db=$1 rc
    db_valid_name "$db" || return 1
    db_connect
    rc=$?
    [ $rc -ne 0 ] && return $rc

    if ! db_exists "$db"; then
        echo "No hay ninguna base de datos $db en lampp-$DB_FOLDER"

        return 1
    fi

    "${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT CONCAT('I|', COUNT(*), '|', COALESCE(SUM(DATA_LENGTH + INDEX_LENGTH), 0))
        FROM information_schema.TABLES WHERE TABLE_SCHEMA='$db'" < /dev/null
}

# borrar-bd <base> [--copia]: elimina la base y todo su contenido. Con --copia guarda antes un
# volcado en ~/lvm-copias (se puede volver a cargar con importar-bd); si la copia falla, no se borra
function drop_database() {
    local db=$1 backup=0 rc
    [ "$2" == "--copia" ] && backup=1
    db_valid_name "$db" || return 1
    db_connect
    rc=$?
    [ $rc -ne 0 ] && return $rc

    if ! db_exists "$db"; then
        echo "No hay ninguna base de datos $db en lampp-$DB_FOLDER"

        return 1
    fi

    if [ $backup -eq 1 ]; then
        local dest="$HOME/lvm-copias/lampp-$DB_FOLDER-$db-$(date +%Y%m%d-%H%M%S).sql.gz"
        echo "Guardando copia de $db..."
        run mkdir -p -m 700 "$HOME/lvm-copias"
        if ! export_database "$db" "$dest" "$DB_FOLDER"; then
            echo "No se ha podido guardar la copia, asi que NO se borra nada."

            return 1
        fi
    fi

    echo "Borrando la base de datos $db de lampp-$DB_FOLDER..."
    run "${DB_SAFE[@]}" "$DB_CLIENT" -uroot -e "DROP DATABASE \`$db\`" < /dev/null || return 1
    db_note_import "/opt/lampp/var/mysql" "$db"
    echo "Base de datos $db borrada"
}

# MariaDB temporal de una version que no esta en marcha: sin red, sin comprobar usuarios
# (--skip-grant-tables: solo se llega por un socket en una carpeta temporal) y con los ficheros de
# esa version (las de XAMPP tienen en su my.cnf y en el RPATH las rutas de /opt/lampp, la version
# activa: se cambian por las suyas). Deja el socket en DB_TMP_SOCK; db_temp_stop lo para.
# ¿Responde un MariaDB en ese socket? db_socket_alive <socket>
function db_socket_alive() {
    python3 -I -c 'import socket, sys
s = socket.socket(socket.AF_UNIX)
s.settimeout(2)
try:
    s.connect(sys.argv[1])
except OSError:
    sys.exit(1)' "$1" 2> /dev/null
}

DB_TMP=""
function db_temp_start() {
    local dir=$1 data=$1/var/mysql server args user grants=(--skip-grant-tables)
    # (con --con-permisos, con sus usuarios: para cargar una base con su usuario lvm_bd_<base>)
    [ "$2" == "--con-permisos" ] && grants=()
    # Si su MariaDB ya esta en marcha (la arranco Docker, sin red), se usa esa: otra no podria abrir los
    # mismos datos. DB_TMP se queda vacio: db_temp_stop no la para
    if db_socket_alive "$data/mysql.sock"; then
        echo "Se usa el MariaDB que ya esta en marcha para Docker (sin red)"
        DB_TMP_SOCK=$data/mysql.sock DB_TMP_PID=""
        return 0
    fi
    # El dueño de los datos de verdad (-L: si var/mysql es un enlace, el de su destino). Nunca root:
    # un MariaDB de root escribiria como root donde le pidiera una base (DATA DIRECTORY, registros)
    user=$($SUDO stat -L -c %U "$data") || return 1
    [ -n "$TEST_DIR" ] && user=$(id -un)
    if [ "$user" == "root" ] || ! [[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "Las BBDD de lampp-${dir#/opt/lampp-} son de $user: no se arranca su MariaDB con ese usuario"
        return 1
    fi

    if [ -x "$dir/mysql/bin/mariadbd" ]; then
        server=("$dir/mysql/bin/mariadbd" --defaults-file="$dir/etc/my.cnf")
    elif [ -x "$dir/sbin/mysqld" ]; then
        server=(env LD_LIBRARY_PATH="$dir/lib" "$dir/sbin/mysqld" --defaults-file="$dir/etc/my.cnf"
            --basedir="$dir" --plugin-dir="$dir/lib/mysql/plugin/"
            --innodb-data-home-dir="$data/" --innodb-log-group-home-dir="$data/")
    else
        echo "lampp-${dir#/opt/lampp-} no tiene el servidor de MariaDB"

        return 1
    fi

    # La carpeta la crea root y solo entran mysql y tu grupo: el servidor no pide contraseña
    # mientras dura la copia (otros usuarios del equipo no pueden llegar a su socket)
    DB_TMP=$($SUDO mktemp -d /tmp/lvm-mysql-XXXX) || { DB_TMP=""; return 1; }
    DB_TMP_SOCK=$DB_TMP/mysql.sock
    $SUDO chown "$user:$(id -gn)" "$DB_TMP" && $SUDO chmod 750 "$DB_TMP" || { $SUDO rm -rf "$DB_TMP"; DB_TMP=""; return 1; }

    echo "Arrancando un MariaDB temporal de lampp-${dir#/opt/lampp-} (sin red, solo para esta copia)..."
    $SUDO "${server[@]}" --datadir="$data" --user="$user" --skip-networking "${grants[@]}" \
        --socket="$DB_TMP_SOCK" --pid-file="$DB_TMP/mysql.pid" --log-error="$DB_TMP/mysql.log" \
        < /dev/null > /dev/null 2>&1 &
    local server_pid=$!
    DB_TMP_PID=$server_pid

    local i
    for i in $(seq 300); do
        [ -S "$DB_TMP_SOCK" ] && return 0
        # Si se ha parado (por ejemplo, porque otro MariaDB usa ya esa carpeta), no se espera mas
        kill -0 $server_pid 2> /dev/null || break
        sleep 0.2
    done
    echo "No ha arrancado. Ultimas lineas de su registro:"
    # (lo lee el dueño de los datos, no root: si el registro fuera un enlace a un fichero de root,
    # root lo mostraria)
    $SUDO ${SUDO:+-u "$user"} tail -15 "$DB_TMP/mysql.log" 2> /dev/null | sed 's/^/  /'

    return 1
}

#@incluir comun/cargar-bases-datos-version/db_temp_kill_launched.sh
function db_temp_stop() {
    [ -z "$DB_TMP" ] && return 0
    if $SUDO test -f "$DB_TMP/mysql.pid"; then
        echo "Parando el MariaDB temporal..."
        # El de su .pid si es el servidor; si no, el sudo que lo arranco (que le pasa la señal)
        local pid
        pid=$(db_temp_pid "$DB_TMP/mysql.pid" "$DB_TMP_SOCK") && $SUDO kill "$pid" 2> /dev/null \
            || db_temp_kill_launched "$DB_TMP_PID" "$DB_TMP_SOCK"
        local i
        for i in $(seq 300); do $SUDO test -f "$DB_TMP/mysql.pid" || break; sleep 0.2; done
    fi
    $SUDO rm -rf "$DB_TMP"
    DB_TMP="" DB_TMP_PID=""
}

# copiar-bd <base> <version de origen> <version de destino> [--como <nombre>] [--carpeta <carpeta|->]
# [--sustituir]: copia una base a otra version, para probar el proyecto con otro PHP. --como le da
# otro nombre en la de destino (base_8_4 -> base_8_5) y --carpeta la vincula alli a esa carpeta de
# proyecto (- = a ninguna; sin --carpeta, el vinculo no se toca). Se descarga de la de origen (como exportar-bd) a un
# fichero solo tuyo y se carga en la de destino con la carga protegida de importar-bd (usuario de la
# base, sin DEFINER, lo INVOKER y los eventos neutralizados). Si la de destino no es la activa en
# marcha, se arranca su MariaDB solo para la copia (sin red y con su propio socket). La de origen no
# se toca
function copy_database() {
    local db=$1 src=$2 dst=$3 sdir ddir src_owner dst_owner tmp rc active active_owner
    local replace=0 load=(--crear) new="" link="" usage=0
    shift 3 2> /dev/null
    # --sustituir: si la de destino ya la tiene, antes se guarda una copia suya en ~/lvm-copias y se
    # carga la de origen encima (la de destino se vacia antes de cargar)
    while [ $# -gt 0 ]; do
        case $1 in
            --sustituir) replace=1; shift ;;
            --como|--carpeta)
                [ -n "$2" ] || { usage=1; break; }
                [ "$1" == --como ] && new=$2 || link=$2
                shift 2 ;;
            *) usage=1; break ;;
        esac
    done
    if [ -z "$db" ] || [ -z "$src" ] || [ -z "$dst" ] || [ $usage -eq 1 ]; then
        echo "Uso: lvm-instalador copiar-bd <base de datos> <version de origen> <version de destino> [--como <nombre>] [--carpeta <carpeta|->] [--sustituir]"
        return 1
    fi
    new=${new:-$db}
    db_valid_name "$db" || return 1
    db_valid_name "$new" || return 1
    link=${link%/}
    if [ -n "$link" ] && [ "$link" != "-" ]; then
        valid_project "$link" || return 1
    fi
    valid_version_name "$src" && valid_version_name "$dst" || { echo "Version no valida"; return 1; }
    sdir="${TEST_DIR:-/opt}/lampp-$src" ddir="${TEST_DIR:-/opt}/lampp-$dst"
    [ -d "$sdir" ] && [ ! -L "$sdir" ] || { echo "No existe la version lampp-$src"; return 1; }
    [ -d "$ddir" ] && [ ! -L "$ddir" ] || { echo "No existe la version lampp-$dst"; return 1; }
    src_owner=$(data_owner "$sdir"); src_owner=${src_owner:-$src}
    dst_owner=$(data_owner "$ddir"); dst_owner=${dst_owner:-$dst}
    if [ "$src_owner" == "$dst_owner" ]; then
        echo "lampp-$src y lampp-$dst comparten las BBDD: $db ya esta en las dos"
        return 1
    fi
    local shown=$db
    [ "$new" != "$db" ] && shown="$db (como $new)"
    if ! db_names "/opt/lampp-$src_owner" | grep -qxF "$db"; then
        echo "No hay ninguna BBDD $db en lampp-$src"
        return 1
    fi
    if db_names "/opt/lampp-$dst_owner" | grep -qxF "$new"; then
        if [ $replace -eq 0 ]; then
            echo "lampp-$dst ya tiene una BBDD $new: no se toca (con --sustituir se guarda una copia suya en"
            # shellcheck disable=SC2088  # (el ~ es un texto que se enseña)
            echo "~/lvm-copias y se pone la de lampp-$src en su lugar; o copiala con otro nombre: --como)"
            return 1
        fi
        load=(--crear --sin-copia)
    else
        replace=0
    fi
    active=$(active_dir)
    active_owner=""
    [ -n "$active" ] && { active_owner=$(data_owner "$active"); active_owner=${active_owner:-${active#/opt/lampp-}}; }
    echo "Copia de la BBDD $shown: de lampp-$src a lampp-$dst (lampp-$src no se toca)"
    if [ "$DRY" -eq 1 ]; then
        [ $replace -eq 1 ] && echo "  [simulacion] copia de $new de lampp-$dst en ~/lvm-copias (la sustituida)"
        echo "  [simulacion] descarga de $db de lampp-$src a un fichero temporal en ~/.lvm-instalador"
        if [ "$dst_owner" == "$active_owner" ] && lampp_running; then
            echo "  [simulacion] carga en el MariaDB en marcha de lampp-$dst (importar-bd ${load[*]})"
        else
            echo "  [simulacion] MariaDB temporal de lampp-$dst (sin red) y carga de $new"
        fi
        if [ "$link" == "-" ]; then
            echo "  [simulacion] $new sin vincular a ningun proyecto en lampp-$dst"
        elif [ -n "$link" ]; then
            echo "  [simulacion] $new vinculada a $link en lampp-$dst"
        fi
        return 0
    fi
    if [ $replace -eq 1 ]; then
        local backup="$HOME/lvm-copias/lampp-$dst-$new-antes-de-copiar-$(date +%Y%m%d-%H%M%S).sql.gz"
        echo "lampp-$dst ya tiene $new: antes se guarda una copia suya en $backup"
        mkdir -p -m 700 "$HOME/lvm-copias" || return 1
        if ! export_database "$new" "$backup" "$dst"; then
            echo "No se ha podido guardar la copia de $new de lampp-$dst, asi que no se ha cambiado nada."
            return 1
        fi
        db_temp_stop
    fi
    mkdir -p -m 700 "$LOG_DIR" || return 1
    tmp=$(mktemp "$LOG_DIR/copia-$db-XXXXXX") || return 1
    mv -f "$tmp" "$tmp.sql.gz" && tmp=$tmp.sql.gz || { rm -f "$tmp"; return 1; }
    # (si se cancela, db_cleanup la borra)
    DB_COPY_TMP=$tmp
    if ! export_database "$db" "$tmp" "$src"; then
        rm -f "$tmp"
        echo "No se ha podido descargar $db de lampp-$src: no se ha copiado nada."
        return 1
    fi
    db_temp_stop
    if [ "$dst_owner" == "$active_owner" ] && lampp_running; then
        import_database "$tmp" "$new" "${load[@]}"
        rc=$?
    else
        # MariaDB de la de destino solo para la copia, con sus usuarios (la carga va con el usuario de
        # la base). El cliente es el de esa version, sin sus ficheros de opciones (llevarian al socket
        # de la activa), por un envoltorio solo tuyo
        # El MariaDB y el cliente de la version duena de las BBDD de destino (si las comparte con
        # otra, la de la otra): su servidor es el que corresponde a esos datos
        local client libs="" odir="${TEST_DIR:-/opt}/lampp-$dst_owner"
        [ -d "$odir" ] && [ ! -L "$odir" ] || { rm -f "$tmp"; echo "No existe la version lampp-$dst_owner"; return 1; }
        if [ -x "$odir/mysql/bin/mariadb" ]; then
            client=$odir/mysql/bin/mariadb
        else
            # (el de XAMPP busca sus librerias en /opt/lampp/lib, que es la de la version activa)
            client=$odir/bin/mysql libs=$odir/lib
        fi
        if ! db_temp_start "$odir" --con-permisos; then
            rm -f "$tmp"
            db_temp_stop
            return 1
        fi
        if ! db_client_wrapper "$client" "$libs" "$DB_TMP_SOCK"; then
            rm -f "$tmp"
            db_temp_stop
            return 1
        fi
        DB_CLIENT=$DB_CLI DB_TARGET_FOLDER=$dst DB_TARGET_DATA="/opt/lampp-$dst_owner/var/mysql" import_database "$tmp" "$new" "${load[@]}"
        rc=$?
        db_client_wrapper_remove
        db_temp_stop
    fi
    rm -f "$tmp"
    DB_COPY_TMP=""
    if [ $rc -eq 0 ]; then
        if [ "$link" == "-" ]; then
            remember_project "$new" "" "$dst"
            echo "$new no queda vinculada a ningun proyecto en lampp-$dst (vinculala en Cargar proyecto)."
        elif [ -n "$link" ]; then
            remember_project "$new" "$link" "$dst"
            echo "$new queda vinculada al proyecto $link en lampp-$dst."
        fi
        echo "$new esta ahora en lampp-$dst. Para probar el proyecto con PHP $(php_version "$ddir" 2> /dev/null), cargalo"
        echo "en Proyectos y elige lampp-$dst en su Entorno."
    fi
    return $rc
}

# exportar-bd <base> <fichero .zip, .sql o .sql.gz> [version]: descarga una copia de la base (estructura,
# datos, rutinas y disparadores; sin eventos, que el MariaDB de XAMPP tiene desactivados), que se
# puede volver a cargar con importar-bd. Sin version, de la activa. Si la version (o la que tiene sus bases) es la activa y esta en marcha, se usa su
# MariaDB; si no, uno temporal (pide sudo).
function export_database() {
    local db=$1 dest=$2 folder=$3 rc

    if [ -z "$db" ] || [ -z "$dest" ]; then
        echo "Uso: lvm-instalador exportar-bd <base de datos> <fichero.zip|.sql|.sql.gz> [version]"

        return 1
    fi
    db_valid_name "$db" || return 1
    local active=$(active_dir)
    folder=${folder:-${active#/opt/lampp-}}
    local dir="${TEST_DIR:-/opt}/lampp-$folder"
    if [ -z "$folder" ] || [ ! -d "$dir" ]; then
        echo "No existe la version lampp-$folder"

        return 1
    fi
    local owner=$(data_owner "$dir")
    owner=${owner:-$folder}
    if ! db_names "/opt/lampp-$owner" | grep -qxF "$db"; then
        echo "No hay ninguna base de datos $db en lampp-$folder"

        return 1
    fi
    dest=$(readlink -m "$dest")
    if [ ! -d "$(dirname "$dest")" ] || [ ! -w "$(dirname "$dest")" ]; then
        echo "No se puede escribir en $(dirname "$dest")"

        return 1
    fi

    local active_owner=""
    if [ -n "$active" ]; then
        active_owner=$(data_owner "$active")
        active_owner=${active_owner:-${active#/opt/lampp-}}
    fi

    echo "Base de datos: $db (lampp-$folder$([ "$owner" != "$folder" ] && echo ", bases de lampp-$owner"))"
    echo "Destino: $dest"
    local dump=() query=() check i
    trap db_cleanup EXIT
    trap 'exit 130' INT TERM HUP
    if [ "$owner" == "$active_owner" ] && check=$(gui_db_check) && [[ "$check" != no\|* ]]; then
        db_connect
        rc=$?
        [ $rc -ne 0 ] && return $rc
        echo "Se usa el MariaDB en marcha de lampp-$DB_FOLDER (MariaDB $DB_VERSION)"
        dump=("${DB_SAFE[@]}" "${LVM_BD_VOLCADO:-$(dirname "$DB_CLIENT")/mysqldump}" -uroot)
        query=("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N)
    elif [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] MariaDB temporal de lampp-$owner y mysqldump $db > $dest"

        return 0
    else
        db_temp_start "/opt/lampp-$owner" || return 1
        # El cliente de la propia version (el de XAMPP, con sus bibliotecas)
        local client=/opt/lampp-$owner/mysql/bin/mariadb-dump sql=/opt/lampp-$owner/mysql/bin/mariadb
        [ -x "$client" ] || client=/opt/lampp-$owner/bin/mysqldump sql=/opt/lampp-$owner/bin/mysql
        dump=(env LD_LIBRARY_PATH="/opt/lampp-$owner/lib" "$client" --no-defaults -S "$DB_TMP_SOCK" -uroot)
        query=(env LD_LIBRARY_PATH="/opt/lampp-$owner/lib" "$sql" --no-defaults -S "$DB_TMP_SOCK" -uroot -N)
    fi
    # El administrador de pruebas (test_admin) no sale en la copia: sus filas de los usuarios de
    # WordPress y de los empleados de PrestaShop se quedan fuera del volcado (la BBDD de trabajo no
    # se toca). Esas tablas van aparte, con --where
    local skip=() only=() wheres=() mail_sql=""
    test_admin_filter "$db"
    [ ${#only[@]} -gt 0 ] && echo "El administrador de pruebas ($TEST_ADMIN_USER) no va en la copia"
    # Lo que cambio el correo de pruebas (plugins de WordPress, correo de PrestaShop) tampoco: la copia
    # lleva lo que habia antes (al final del volcado) y sin la tabla donde se apunto
    mail_export_filter "$db"
    [ -n "$mail_sql" ] && echo "Los cambios del correo de pruebas no van en la copia: lleva el correo como estaba"

    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] mysqldump $db > $dest"

        return 0
    fi

    local out=(cat) inner
    [[ "${dest,,}" == *.gz ]] && out=(gzip -6)
    if [[ "${dest,,}" == *.zip ]]; then
        inner=$(basename "$dest")
        inner=${inner%.*}
        out=(python3 -I -c "$ZIP_WRITE_PY" "${inner%.sql}.sql")
    fi
    local part="$dest.parte" errors=$(mktemp) routines=--routines pid
    DB_PART=$part
    echo "Descargando..."
    while :; do
        # (solo para ti: lleva la base entera, aunque la carpeta de destino sea de todos)
        ( umask 077; set -o pipefail
          { "${dump[@]}" --default-character-set=utf8mb4 --single-transaction --quick \
                $routines --triggers --max-allowed-packet=1G "${skip[@]}" "$db" || exit 1
            # (sin la linea del modo sandbox de cada volcado: solo la del primero, al principio, que la
            # carga sabe quitar para los MariaDB antiguos)
            for i in "${!only[@]}"; do
                "${dump[@]}" --default-character-set=utf8mb4 --single-transaction --quick --triggers \
                    --max-allowed-packet=1G --where="${wheres[$i]}" "$db" "${only[$i]}" | LC_ALL=C sed '/^\/\*M!999999\\-/d' || exit 1
            done
            [ -z "$mail_sql" ] || printf '%s\n' "$mail_sql"; } < /dev/null 2> "$errors" | "${out[@]}" > "$part" ) &
        pid=$!
        while kill -0 $pid 2> /dev/null; do
            sleep 2
            kill -0 $pid 2> /dev/null && echo "  $(numfmt --to=iec --suffix=B "$(stat -c %s "$part" 2> /dev/null || echo 0)") escritos"
        done
        wait $pid && break
        rm -f "$part"
        # MariaDB actualizados sin mysql_upgrade (como el XAMPP 8.2.4 con datos de 10.1): mysql.proc
        # tiene columnas de menos y no se pueden leer las rutinas. Se descarga sin ellas
        if [ -n "$routines" ] && grep -q "mysql.proc" "$errors"; then
            echo "Aviso: no se pueden leer sus funciones y procedimientos (la tabla mysql.proc es de un"
            echo "MariaDB anterior); se descarga sin ellos. Las tablas y los datos van completos."
            routines=""
            continue
        fi
        cat "$errors"
        rm -f "$errors"
        echo "No se ha podido descargar la base de datos."

        return 1
    done
    rm -f "$errors"
    mv -f "$part" "$dest"
    DB_PART=""
    echo "Copia guardada: $dest ($(du -h "$dest" | cut -f1))"
}

# Tablas del administrador de pruebas en una base (para exportar-bd): deja en skip los --ignore-table
# del volcado de siempre y en only/wheres cada tabla con su condicion (sin las filas de
# local@local.test). Solo las tablas de verdad que lo tienen. Usa query (el cliente de la base)
function test_admin_filter() {
    local db=$1 t c p n
    local -A cols=()
    while IFS=$'\t' read -r t c; do
        [[ "$t" =~ ^[A-Za-z0-9_]+$ ]] && cols[$t]=$c
    done < <("${query[@]}" -e "SELECT c.TABLE_NAME, c.COLUMN_NAME FROM information_schema.COLUMNS c
        JOIN information_schema.TABLES t ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME
        WHERE c.TABLE_SCHEMA = '$db' AND t.TABLE_TYPE = 'BASE TABLE' AND (
            (c.TABLE_NAME LIKE '%users' AND c.COLUMN_NAME = 'user_login')
            OR (c.TABLE_NAME LIKE '%employee' AND c.COLUMN_NAME = 'email'))" < /dev/null 2> /dev/null)
    for t in "${!cols[@]}"; do
        if [ "${cols[$t]}" == user_login ]; then
            p=${t%users}
            n=$("${query[@]}" "$db" -e "SELECT COUNT(*) FROM \`$t\` WHERE user_login = '$TEST_ADMIN_USER'" < /dev/null 2> /dev/null)
            [ "${n:-0}" -gt 0 ] 2> /dev/null || continue
            skip+=(--ignore-table="$db.$t") only+=("$t") wheres+=("NOT (user_login <=> '$TEST_ADMIN_USER')")
            if [ "$("${query[@]}" -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$db' AND TABLE_NAME = '${p}usermeta' AND TABLE_TYPE = 'BASE TABLE'" < /dev/null 2> /dev/null)" == 1 ]; then
                skip+=(--ignore-table="$db.${p}usermeta") only+=("${p}usermeta")
                wheres+=("user_id IS NULL OR user_id NOT IN (SELECT ID FROM \`$t\` WHERE user_login = '$TEST_ADMIN_USER')")
            fi
        else
            p=${t%employee}
            n=$("${query[@]}" "$db" -e "SELECT COUNT(*) FROM \`$t\` WHERE email = '$TEST_ADMIN_USER'" < /dev/null 2> /dev/null)
            [ "${n:-0}" -gt 0 ] 2> /dev/null || continue
            skip+=(--ignore-table="$db.$t") only+=("$t") wheres+=("NOT (email <=> '$TEST_ADMIN_USER')")
            if [ "$("${query[@]}" -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$db' AND TABLE_NAME = '${p}employee_shop' AND TABLE_TYPE = 'BASE TABLE'" < /dev/null 2> /dev/null)" == 1 ]; then
                skip+=(--ignore-table="$db.${p}employee_shop") only+=("${p}employee_shop")
                wheres+=("id_employee IS NULL OR id_employee NOT IN (SELECT id_employee FROM \`$t\` WHERE email = '$TEST_ADMIN_USER')")
            fi
        fi
    done
    return 0
}

# Correo de pruebas en las BBDD: WordPress (sus plugins de correo) y PrestaShop (su configuracion de
# correo, por SMTP a Mailpit). Lo que cambia se apunta, con lo de antes, en MAIL_TABLE de la propia
# base; MAIL_DB_PY lo deshace al cambiar de modo o apagarlo y para las copias (ver mail_export_filter)
MAIL_DB_PY='
import re, sys
# Correo de pruebas en una BBDD (mail_db y exportar-bd). Ordenes:
#   consulta                      (entrada: tabla<TAB>columna de la base) -> SQL que saca las filas
#   cambios <modo> <puerto> <sql> (entrada: esas filas) -> en <sql>, lo que deshace lo de antes y aplica
#                                 el modo (mailpit, desactivar, nada o apagado); en la salida, que cambia
#   copia                         (entrada: esas filas) -> SQL que deja los valores de antes (para el
#                                 final de un volcado)
# Las filas llegan con los valores en hexadecimal (- = NULL): O (opciones de WordPress), M (sitemeta de
# un multisitio), C (configuracion de PrestaShop), T (tabla y su tipo) y R (lo apuntado en MAIL_TABLE:
# tabla, fila, clave, tipo, ruta, valor de antes y valor puesto). Los nombres de tablas y claves se
# comprueban: la tabla apuntada puede venir de un volcado
Q = chr(39)
NAME = re.compile(r"^[A-Za-z0-9_]+$")
REC = "lvm_correo_original"
WP_OPTS = ("active_plugins", "wp_mail_smtp", "easy_wp_smtp", "solid_smtp_providers")
PS_MAIL = (("PS_MAIL_METHOD", "2"), ("PS_MAIL_SERVER", "127.0.0.1"), ("PS_MAIL_SMTP_PORT", None),
           ("PS_MAIL_SMTP_ENCRYPTION", "off"), ("PS_MAIL_USER", ""), ("PS_MAIL_PASSWD", ""))
# Plugins de correo de WordPress, por su carpeta: nombre y si su correo se lleva a Mailpit con
# phpmailer_init (los demas sustituyen wp_mail o mandan por una API: se desactivan). WP SMTP (Solid
# Mail) tambien se desactiva si tiene una conexion de Postmark, que va por API
PLUGINS = {
    "wp-mail-smtp": ("WP Mail SMTP", True), "wp-mail-smtp-pro": ("WP Mail SMTP Pro", True),
    "easy-wp-smtp": ("Easy WP SMTP", True), "smtp-mailer": ("SMTP Mailer", True),
    "wp-smtp": ("WP SMTP (Solid Mail)", True),
    "mailin": ("Brevo", False), "woocommerce-sendinblue-newsletter-subscription": ("Brevo para WooCommerce", False),
    "post-smtp": ("Post SMTP", False), "fluent-smtp": ("FluentSMTP", False), "gmail-smtp": ("Gmail SMTP", False),
    "wp-ses": ("WP Offload SES", False), "wp-offload-ses": ("WP Offload SES", False),
    "sendgrid-email-delivery-simplified": ("SendGrid", False), "mailgun": ("Mailgun", False),
    "postmark-approved-wordpress-plugin": ("Postmark", False), "sparkpost": ("SparkPost", False),
    "wp-mail-bank": ("Mail Bank", False), "mailjet-for-wordpress": ("Mailjet", False),
    "mailpoet": ("MailPoet", False), "suremails": ("SureMail", False),
}
# Opciones de WP Mail SMTP y Easy WP SMTP: con un servicio por API (brevo, sendgrid...), a mail()
MAILER_OPTS = {"wp_mail_smtp": ("wp-mail-smtp", "wp-mail-smtp-pro"), "easy_wp_smtp": ("easy-wp-smtp",)}
SMTP_MAILERS = (b"mail", b"smtp", b"pepipost")


def plugin_info(path):
    folder = path.split(b"/")[0].decode("utf-8", "replace").lower()
    if folder in PLUGINS:
        return PLUGINS[folder]
    if folder.startswith(("sendinblue", "brevo")):
        return ("Brevo", False)
    return None


# Datos serializados de PHP (los de las opciones): N, b, i, d, s y a (las claves, en orden). Los
# objetos no: esa opcion no se toca
def unser(b, i=0):
    t = b[i:i + 1]
    if t == b"N" and b[i + 1:i + 2] == b";":
        return ("N", b""), i + 2
    if t in (b"b", b"i", b"d") and b[i + 1:i + 2] == b":":
        j = b.index(b";", i)
        return (t.decode(), b[i + 2:j]), j + 1
    if t == b"s" and b[i + 1:i + 2] == b":":
        j = b.index(b":", i + 2)
        n = int(b[i + 2:j])
        if b[j + 1:j + 2] != b"\x22" or b[j + 2 + n:j + 4 + n] != b"\x22;":
            raise ValueError("cadena")
        return ("s", b[j + 2:j + 2 + n]), j + 4 + n
    if t == b"a" and b[i + 1:i + 2] == b":":
        j = b.index(b":", i + 2)
        n = int(b[i + 2:j])
        if b[j + 1:j + 2] != b"{":
            raise ValueError("lista")
        k, items = j + 2, []
        for _ in range(n):
            key, k = unser(b, k)
            if key[0] not in ("i", "s"):
                raise ValueError("clave")
            val, k = unser(b, k)
            items.append([key, val])
        if b[k:k + 1] != b"}":
            raise ValueError("fin de lista")
        return ("a", items), k + 1
    raise ValueError("tipo")


def parse(b):
    if b is None:
        return None
    try:
        v, i = unser(b)
    except (ValueError, IndexError):
        return None
    return v if i == len(b) else None


def ser(v):
    t, x = v
    if t == "N":
        return b"N;"
    if t in ("b", "i", "d"):
        return t.encode() + b":" + x + b";"
    if t == "s":
        return b"s:%d:\x22" % len(x) + x + b"\x22;"
    return b"a:%d:{" % len(x) + b"".join(ser(k) + ser(val) for k, val in x) + b"}"


def get_path(v, path):
    for part in path:
        if not v or v[0] != "a":
            return None
        v = next((val for k, val in v[1] if k == ("s", part)), None)
    return v


def set_path(v, path, new):
    for part in path[:-1]:
        v = next((val for k, val in v[1] if k == ("s", part)), None)
    for item in v[1]:
        if item[0] == ("s", path[-1]):
            item[1] = new


def sql(b):
    if b is None:
        return "NULL"
    return "0x" + b.hex().upper() if b else Q + Q


def unhex(x):
    if x == "-":
        return None
    if not re.fullmatch(r"(?:[0-9A-Fa-f]{2})*", x):
        raise ValueError("hex")
    return bytes.fromhex(x)


def read_rows():
    tables, rows, recs = {}, {}, []
    for line in sys.stdin.read().splitlines():
        f = line.split("\t")
        try:
            if f[0] == "T" and len(f) >= 3 and NAME.match(f[1]):
                tables[f[1]] = f[2]
            elif f[0] in ("O", "M", "C") and len(f) >= 5 and NAME.match(f[1]) and f[2].isdigit():
                rows[(f[1], f[2])] = {"kind": f[0], "name": f[3], "value": unhex(f[4]), "table": f[1], "id": f[2]}
            elif f[0] == "R" and len(f) >= 8:
                recs.append({"tabla": f[1], "fila": f[2], "clave": f[3], "tipo": f[4], "ruta": f[5],
                             "original": unhex(f[6]), "puesto": unhex(f[7])})
        except ValueError:
            continue
    # (solo lo apuntado sobre tablas de esta base que se han leido, con claves y tipos conocidos)
    known = set(WP_OPTS) | {"active_sitewide_plugins"} | {n for n, _ in PS_MAIL}
    recs = [r for r in recs if r["tabla"] in tables and tables[r["tabla"]] in ("wp", "ms", "ps")
            and r["fila"].isdigit() and r["clave"] in known
            and r["tipo"] in ("quitados", "ruta", "valor", "nuevo") and r["ruta"] in ("", "mail/mailer")]
    return tables, rows, recs


def restore(rows, recs, notes):
    """Deja en rows lo de antes (lo apuntado, del ultimo al primero). Lo que se ha cambiado despues en
    local (otro plugin activado, otro servidor de correo) se respeta."""
    back = {}
    for r in reversed(recs):
        row = rows.get((r["tabla"], r["fila"]))
        if not row or row.get("gone") or row["name"] != r["clave"]:
            continue
        if r["tipo"] == "nuevo":
            if row["value"] == r["puesto"]:
                row["gone"] = True
        elif r["tipo"] == "valor":
            if row["value"] == r["puesto"]:
                row["value"] = r["original"]
                back.setdefault(r["tabla"], set()).add("correo de PrestaShop")
        elif r["tipo"] == "ruta":
            cur = parse(row["value"])
            path = [p.encode() for p in r["ruta"].split("/")]
            got = get_path(cur, path)
            if got and got[0] == "s" and got[1] == r["puesto"] and r["original"] is not None:
                set_path(cur, path, ("s", r["original"]))
                row["value"] = ser(cur)
                back.setdefault(r["tabla"], set()).add("su servicio de correo")
        elif r["tipo"] == "quitados":
            cur, old = parse(row["value"]), parse(r["original"])
            if not cur or not old or cur[0] != "a" or old[0] != "a":
                continue
            names = []
            if r["clave"] == "active_plugins":
                have = {ser(v) for _k, v in cur[1]}
                last = max([int(k[1]) for k, _v in cur[1] if k[0] == "i"] + [-1])
                for _k, v in old[1]:
                    if ser(v) not in have and v[0] == "s":
                        last += 1
                        cur[1].append([("i", str(last).encode()), v])
                        names.append(v[1])
            else:
                have = {k for k, _v in cur[1]}
                for k, v in old[1]:
                    if k not in have:
                        cur[1].append([k, v])
                        names.append(k[1])
            if names:
                row["value"] = ser(cur)
                back.setdefault(r["tabla"], set()).update(
                    (plugin_info(n) or (n.decode("utf-8", "replace"),))[0] for n in names)
    for t in sorted(back):
        notes.append("Correo de pruebas deshecho en %s: vuelve %s" % (t, ", ".join(sorted(back[t]))))


def apply(tables, rows, mode, port, recs, inserts, notes):
    """Aplica el modo sobre rows (ya con lo de antes) y apunta en recs lo que cambia."""
    if mode not in ("mailpit", "desactivar"):
        return
    for t, kind in sorted(tables.items()):
        mine = [r for r in rows.values() if r["table"] == t and not r.get("gone")]
        if kind in ("wp", "ms"):
            key = "active_plugins" if kind == "wp" else "active_sitewide_plugins"
            providers = next((r["value"] or b"" for r in mine if r["name"] == "solid_smtp_providers"), b"")
            row = next((r for r in mine if r["name"] == key), None)
            cur = parse(row["value"]) if row else None
            active = set()
            if row and not (cur and cur[0] == "a"):
                notes.append("Aviso: WordPress (%s): no se pueden leer sus plugins activos; revisa sus plugins de correo" % t)
            if cur and cur[0] == "a":
                keep, gone = [], []
                for k, v in cur[1]:
                    path = (v if kind == "wp" else k)
                    path = path[1] if path[0] == "s" else b""
                    info = plugin_info(path) if path else None
                    off = info is not None and (mode == "desactivar" or not info[1]
                                                or (path.startswith(b"wp-smtp/") and b"postmark" in providers.lower()))
                    (gone if off else keep).append([k, v])
                    if not off and path:
                        active.add(path.split(b"/")[0].decode("utf-8", "replace").lower())
                if gone:
                    if kind == "wp":
                        keep = [[("i", str(n).encode()), v] for n, (_k, v) in enumerate(keep)]
                    row["value"] = ser(("a", keep))
                    recs.append((t, row["id"], key, "quitados", "", ser(("a", gone)), None))
                    names = sorted({(plugin_info((v if kind == "wp" else k)[1]) or ("?",))[0] for k, v in gone})
                    notes.append("WordPress (%s): desactivados en la copia local: %s" % (t, ", ".join(names)))
            if mode == "mailpit" and kind == "wp":
                for opt, folders in MAILER_OPTS.items():
                    r = next((x for x in mine if x["name"] == opt), None)
                    if not r or not active & set(folders):
                        continue
                    cur = parse(r["value"])
                    got = get_path(cur, [b"mail", b"mailer"])
                    if cur is None:
                        notes.append("Aviso: WordPress (%s): no se puede leer la configuracion de %s; revisa por donde manda"
                                     % (t, PLUGINS[folders[0]][0]))
                    if got and got[0] == "s" and got[1] not in SMTP_MAILERS:
                        set_path(cur, [b"mail", b"mailer"], ("s", b"mail"))
                        r["value"] = ser(cur)
                        recs.append((t, r["id"], opt, "ruta", "mail/mailer", got[1], b"mail"))
                        notes.append("WordPress (%s): %s mandaba por %s (API): ahora por PHP, a Mailpit"
                                     % (t, PLUGINS[folders[0]][0], got[1].decode("utf-8", "replace")))
        elif kind == "ps":
            changed = False
            for name, want in PS_MAIL:
                want = (want if want is not None else port).encode()
                same = [r for r in mine if r["name"] == name]
                if not same:
                    # (una que se borro al deshacer, con su numero, o una nueva para todas las tiendas)
                    old = next((r for r in rows.values() if r["table"] == t and r.get("gone") and r["name"] == name), None)
                    if old:
                        old["gone"], old["value"] = False, want
                        recs.append((t, old["id"], name, "nuevo", "", None, want))
                    else:
                        inserts.append((t, name, want))
                    changed = True
                for r in same:
                    if r["value"] != want:
                        recs.append((t, r["id"], name, "valor", "", r["value"], want))
                        r["value"] = want
                        changed = True
            if changed or any(x[0] == t for x in recs):
                notes.append("PrestaShop (%s): correo por SMTP a Mailpit (127.0.0.1:%s)" % (t, port))


COLS = {"O": ("option_value", "option_id"), "M": ("meta_value", "meta_id"), "C": ("value", "id_configuration")}


def statements(rows, before):
    out = []
    for key, r in sorted(rows.items()):
        val, idc = COLS[r["kind"]]
        if r.get("gone"):
            out.append("DELETE FROM `%s` WHERE %s = %s;" % (r["table"], idc, r["id"]))
        elif r["value"] != before[key]:
            out.append("UPDATE `%s` SET %s = %s WHERE %s = %s;" % (r["table"], val, sql(r["value"]), idc, r["id"]))
    return out


cmd = sys.argv[1] if len(sys.argv) > 1 else ""
if cmd == "consulta":
    cols = {}
    for line in sys.stdin.read().splitlines():
        f = line.split("\t")
        if len(f) >= 2 and NAME.match(f[0]):
            cols.setdefault(f[0], set()).add(f[1])
    out = []
    lit = lambda s: Q + s + Q
    for t, c in sorted(cols.items()):
        if t == REC and {"tabla", "fila", "clave", "tipo", "ruta", "original", "puesto"} <= c:
            out.append("SELECT %s, %s, %s;" % (lit("T"), lit(t), lit("rec")))
            out.append("SELECT %s, tabla, fila, clave, tipo, ruta, IFNULL(HEX(original), %s), IFNULL(HEX(puesto), %s) FROM `%s` ORDER BY id;"
                       % (lit("R"), lit("-"), lit("-"), t))
        elif {"option_id", "option_name", "option_value"} <= c:
            out.append("SELECT %s, %s, %s;" % (lit("T"), lit(t), lit("wp")))
            out.append("SELECT %s, %s, option_id, option_name, IFNULL(HEX(option_value), %s) FROM `%s` WHERE option_name IN (%s);"
                       % (lit("O"), lit(t), lit("-"), t, ", ".join(lit(n) for n in WP_OPTS)))
        elif {"meta_id", "meta_key", "meta_value", "site_id"} <= c:
            out.append("SELECT %s, %s, %s;" % (lit("T"), lit(t), lit("ms")))
            out.append("SELECT %s, %s, meta_id, meta_key, IFNULL(HEX(meta_value), %s) FROM `%s` WHERE meta_key = %s;"
                       % (lit("M"), lit(t), lit("-"), t, lit("active_sitewide_plugins")))
        elif {"id_configuration", "name", "value", "id_shop", "id_shop_group"} <= c:
            out.append("SELECT %s, %s, %s;" % (lit("T"), lit(t), lit("ps")))
            out.append("SELECT %s, %s, id_configuration, name, IFNULL(HEX(value), %s) FROM `%s` WHERE name IN (%s);"
                       % (lit("C"), lit(t), lit("-"), t, ", ".join(lit(n) for n, _v in PS_MAIL)))
    print("\n".join(out))
elif cmd in ("cambios", "copia"):
    tables, rows, recs = read_rows()
    before = {k: r["value"] for k, r in rows.items()}
    notes, new_recs, inserts = [], [], []
    restore(rows, recs, notes)
    if cmd == "copia":
        st = statements(rows, before)
        if st:
            print("\n-- lvm-instalador: el correo de pruebas cambio esto en la copia local; aqui vuelve lo de antes")
            print("\n".join(st))
        sys.exit(0)
    mode, port, dst = sys.argv[2], sys.argv[3], sys.argv[4]
    if not port.isdigit():
        sys.exit("puerto no valido")
    apply(tables, rows, mode, port, new_recs, inserts, notes)
    st = statements(rows, before)
    has_rec = "rec" in tables.values()
    out = []
    if st or inserts or new_recs or has_rec:
        if new_recs or inserts:
            out.append("CREATE TABLE IF NOT EXISTS `%s` (id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, "
                       "tabla VARCHAR(64) NOT NULL, fila VARCHAR(20) NOT NULL, clave VARCHAR(191) NOT NULL, "
                       "tipo VARCHAR(16) NOT NULL, ruta VARCHAR(64) NOT NULL DEFAULT %s, original LONGTEXT NULL, "
                       "puesto LONGTEXT NULL, cuando DATETIME NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 "
                       "COMMENT=%s;" % (REC, Q + Q, Q + "lvm-instalador: correo de pruebas, valores de antes (no va en las copias)" + Q))
        out.append("START TRANSACTION;")
        if has_rec and (new_recs or inserts):
            out.append("DELETE FROM `%s`;" % REC)
        out += st
        cols = "(tabla, fila, clave, tipo, ruta, original, puesto, cuando)"
        for t, fila, clave, tipo, ruta, orig, put in new_recs:
            out.append("INSERT INTO `%s` %s VALUES (%s, %s, %s, %s, %s, %s, %s, NOW());"
                       % (REC, cols, Q + t + Q, Q + fila + Q, Q + clave + Q, Q + tipo + Q, Q + ruta + Q, sql(orig), sql(put)))
        for t, name, val in inserts:
            out.append("INSERT INTO `%s` (id_shop_group, id_shop, name, value, date_add, date_upd) VALUES (NULL, NULL, %s, %s, NOW(), NOW());"
                       % (t, Q + name + Q, sql(val)))
            out.append("INSERT INTO `%s` %s VALUES (%s, LAST_INSERT_ID(), %s, %s, %s, NULL, %s, NOW());"
                       % (REC, cols, Q + t + Q, Q + name + Q, Q + "nuevo" + Q, Q + Q, sql(val)))
        out.append("COMMIT;")
        if has_rec and not (new_recs or inserts):
            out.append("DROP TABLE IF EXISTS `%s`;" % REC)
    with open(dst, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + ("\n" if out else ""))
    for n in notes:
        print(n)
else:
    sys.exit("uso: consulta | cambios <modo> <puerto> <sql> | copia")
'

#@incluir comun/cargar-bases-datos-version/mail_db_rows.sh
# Copias de una base (exportar-bd, copiar-bd, Docker): sin MAIL_TABLE (va a skip) y con lo que habia
# antes del correo de pruebas al final (mail_sql, que se añade al volcado). Usa query (el cliente)
function mail_export_filter() {
    local db=$1 rows
    rows=$(mail_db_rows "$db" "${query[@]}") || return 0
    grep -q "^T"$'\t'"$MAIL_TABLE"$'\t' <<< "$rows" || return 0
    skip+=(--ignore-table="$db.$MAIL_TABLE")
    mail_sql=$(python3 -I -c "$MAIL_DB_PY" copia <<< "$rows")
    return 0
}

# Mientras se carga un volcado, sus funciones y procedimientos ya existen: si fueran SQL SECURITY
# INVOKER y la web (que entra como root) o phpMyAdmin los usaran a mitad de carga, se ejecutarian como
# root y podrian cambiar otras bases o darle permisos a su usuario. Este filtro cambia al vuelo la
# palabra INVOKER suelta por DEFINER (se ejecutan con el usuario de la base, que solo puede tocarla),
# este donde este: asi da igual como se escriba (comentarios en medio, /*!...*/, trozos). No toca los
# nombres que la llevan dentro (invoker_id, php-di/invoker...) y conserva el largo y las mayusculas
# (no rompe los datos serializados de PHP); un texto con la palabra suelta cambia (documentado).
# Por SQL dinamico (PREPARE) no se pueden crear rutinas, y una vista solo puede tocar lo que su
# creador puede (su base); lo que quede lo neutraliza la limpieza
INVOKER_PY='
import re, sys
# La palabra INVOKER suelta (no dentro de un nombre: invoker_id, $invoker, php-di/invoker,
# Vendor\Invoker, x.invoker), en mayusculas o minusculas, pasa a DEFINER con las mismas mayusculas
RX = re.compile(rb"(?<![A-Za-z0-9_$@.\\])(?<![^*]/)INVOKER(?![A-Za-z0-9_$.\\])", re.I)
NEW = b"DEFINER"
def swap(w):
    return bytes(d if 65 <= c <= 90 else d + 32 for c, d in zip(w, NEW))
CHUNK = int(sys.argv[1]) if len(sys.argv) > 1 else 1 << 20
inp, out = sys.stdin.buffer, sys.stdout.buffer
# buf[:skip] ya se ha escrito: solo sirve para mirar los dos caracteres de antes de una palabra
buf, skip = b"", 0
while True:
    data = inp.read(CHUNK)
    eof = not data
    buf += data
    # Las palabras que empiezan en los ultimos 8 bytes esperan al trozo siguiente
    cut = len(buf) if eof else max(skip, len(buf) - 8)
    parts, pos = [], skip
    for m in RX.finditer(buf, skip):
        if m.start() >= cut:
            break
        parts.append(buf[pos:m.start()])
        parts.append(swap(m.group()))
        pos = m.end()
    cut = max(cut, pos)
    parts.append(buf[pos:cut])
    out.write(b"".join(parts))
    if eof:
        break
    keep = max(0, cut - 2)
    buf, skip = buf[keep:], cut - keep
'

# Copias en .zip (como las que se descargan del servidor): el .sql de dentro se lee sin
# descomprimirlo a disco. "info <zip>" -> nombre|tamaño|empieza por la linea del modo sandbox (1/0);
# "extraer <zip o ->" lo escribe en la salida ("-": el zip es la entrada estandar, para que el
# avance se vea en la posicion del descriptor)
ZIP_SQL_PY='
import re, shutil, sys, zipfile
# Los nombres de dentro del .zip salen en la terminal: sin caracteres de control
def clean(name):
    return re.sub(r"[\x00-\x1f\x7f-\x9f]", "?", name)
mode, src = sys.argv[1], sys.argv[2]
f = open(0, "rb", closefd=False) if src == "-" else open(src, "rb")
try:
    z = zipfile.ZipFile(f)
except Exception as exc:
    print("ERROR|El fichero .zip no es valido: %s" % clean(str(exc)))
    sys.exit(1)
sqls = [i for i in z.infolist() if not i.is_dir() and not i.filename.startswith("__MACOSX/")
        and i.filename.lower().endswith(".sql")]
if not sqls:
    print("ERROR|El .zip no tiene ningun fichero .sql dentro")
    sys.exit(1)
if len(sqls) > 1:
    print("ERROR|El .zip tiene varios .sql (%s): deja solo el que quieras cargar"
          % ", ".join(clean(i.filename) for i in sqls))
    sys.exit(1)
if mode == "info":
    with z.open(sqls[0]) as m:
        first = m.readline(200)
    print("%s|%d|%d" % (clean(sqls[0].filename).replace("|", " "), sqls[0].file_size,
                        1 if first.startswith(b"/*M!999999\\-") else 0))
    sys.exit(0)
try:
    with z.open(sqls[0]) as m:
        shutil.copyfileobj(m, sys.stdout.buffer, 1 << 20)
except BrokenPipeError:
    sys.exit(1)
'

# Escribe en un .zip (en la salida) lo que llega por la entrada, como un unico <nombre>.sql
ZIP_WRITE_PY='
import shutil, sys, time, zipfile
info = zipfile.ZipInfo(sys.argv[1], time.localtime()[:6])
info.compress_type = zipfile.ZIP_DEFLATED
info.external_attr = 0o644 << 16
with zipfile.ZipFile(sys.stdout.buffer, "w", zipfile.ZIP_DEFLATED) as z:
    with z.open(info, "w", force_zip64=True) as m:
        shutil.copyfileobj(sys.stdin.buffer, m, 1 << 20)
'

# importar-bd <fichero .sql, .sql.gz o .zip> <base> [--crear] [--sin-copia]: carga el fichero en el
# MariaDB de la version activa. --crear crea la base si no existe. Si ya existe, siempre se vacia
# antes (se borra y se crea de nuevo con su juego de caracteres): asi no quedan tablas que el volcado
# ya no trae ni filas de una carga anterior que fallo a medias (los volcados de phpMyAdmin no llevan
# DROP TABLE y sus INSERT se suman a lo que haya). Si tiene tablas, antes se guarda una copia suya en
# ~/lvm-copias; --sin-copia no la guarda (copiar-bd, que ya la ha guardado). --vaciar se admite, pero
# ya no hace falta.
# Las copias hechas con mariadb-dump moderno empiezan por "/*M!999999\- enable the sandbox mode */",
# que los clientes de MariaDB anteriores a 10.5.25 (el de XAMPP es 10.4) no entienden: esa primera
# linea se quita al vuelo, sin tocar el fichero.
# Avance: el fichero se abre como descriptor 3 del script y los programas que lo leen comparten su
# posicion, que se ve en /proc/<pid>/fdinfo/3 (asi lo hace pv -d). Con LVM_PROGRESO se escribe una
# linea S con modo fdpos para la ventana; en una terminal con pv se muestra la barra de pv.
function import_database() {
    local file=$1 db=$2 create=0 backup=1 saved="" project=""
    shift 2
    while [ $# -gt 0 ]; do
        case "$1" in
            --crear) create=1 ;;
            --vaciar) ;;
            --sin-copia) backup=0 ;;
            --proyecto) project=${2%/}; shift ;;
        esac
        shift
    done

    if [ -z "$file" ] || [ -z "$db" ]; then
        echo "Uso: lvm-instalador importar-bd <fichero.sql|.sql.gz|.zip> <base de datos> [--crear] [--sin-copia] [--proyecto <carpeta>]"

        return 1
    fi
    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        echo "No se puede leer el fichero $file"

        return 1
    fi
    db_valid_name "$db" || return 1
    # (como en el resto: sin ., .. ni saltos de linea, que meterian lineas en ~/.lvm-instalador/proyectos)
    if [ -n "$project" ] && ! valid_project "$project"; then
        return 1
    fi

    # Tipo de fichero (por su contenido) y si empieza por la linea del modo sandbox. Se mira antes
    # de crear o vaciar la base, para no vaciarla si el fichero no sirve
    local kind=sql first="" sandbox=0 inner="" inner_size=0
    case "$(head -c 4 "$file" | od -An -tx1 | tr -d ' \n')" in
        1f8b*) kind=gz ;;
        504b0304) kind=zip ;;
    esac
    case "${file,,}" in
        *.zip) [ $kind == zip ] || { echo "$(basename "$file") no es un .zip valido"; return 1; } ;;
        *.gz) [ $kind == gz ] || { echo "$(basename "$file") no es un .gz valido"; return 1; } ;;
    esac
    case $kind in
        sql) first=$(head -c 200 "$file" | head -1) ;;
        gz) first=$(gzip -dc "$file" 2> /dev/null | head -c 200 | head -1) ;;
        zip)
            local info
            info=$(python3 -I -c "$ZIP_SQL_PY" info "$file")
            if [ $? -ne 0 ]; then
                echo "${info#ERROR|}"

                return 1
            fi
            IFS='|' read -r inner inner_size sandbox <<< "$info"
            ;;
    esac
    [[ "$first" == '/*M!999999\-'* ]] && sandbox=1

    local rc
    # (copiar-bd a una version que no es la activa: DB_CLIENT ya va a su MariaDB temporal)
    if [ -n "$DB_TARGET_FOLDER" ]; then
        DB_FOLDER=$DB_TARGET_FOLDER
        DB_VERSION=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT VERSION()" < /dev/null 2> /dev/null | cut -d- -f1)
        [ -n "$DB_VERSION" ] || { echo "No se puede entrar en el MariaDB de lampp-$DB_FOLDER"; return 1; }
    else
        db_connect
        rc=$?
        [ $rc -ne 0 ] && return $rc
    fi

    local folder=$DB_FOLDER
    # --binary-mode: el cliente no ejecuta sus propios comandos que traiga el volcado (\! orden,
    # system, source, tee: con ellos un .sql manipulado ejecutaria programas en este equipo), solo
    # SQL. --local-infile=0: el volcado no puede leer ficheros del equipo (LOAD DATA LOCAL INFILE)
    local mysql=("${DB_SAFE[@]}" "$DB_CLIENT" -uroot --default-character-set=utf8mb4 --binary-mode --local-infile=0)
    local size=$(stat -c %s "$file") name=$(basename "$file")
    # (el nombre va en el fichero de progreso, separado por |)
    name=${name//[|$'\n'$'\r']/_}

    echo "Fichero: $file ($(numfmt --to=iec --suffix=B "$size"))"
    [ $kind == zip ] && echo "Dentro del zip: $inner ($(numfmt --to=iec --suffix=B "$inner_size"), se descomprime al vuelo)"
    echo "Destino: base $db en lampp-$folder (MariaDB $DB_VERSION)"
    [ $sandbox -eq 1 ] && echo "Se quita la primera linea (/*M!999999\- enable the sandbox mode */), que los MariaDB antiguos no entienden"
    # (antes de crear o vaciar la base: si no se puede cargar, no se toca nada)
    # Con FEDERATED, CONNECT o SPIDER activos, una tabla del volcado podria conectarse a este mismo
    # MariaDB como root (sin contraseña) y leer o cambiar cualquier base: no se carga (vienen
    # desactivados; se activan a mano con INSTALL SONAME)
    local engines
    engines=$("${mysql[@]}" -N -e "SELECT GROUP_CONCAT(ENGINE) FROM information_schema.ENGINES
        WHERE ENGINE IN ('FEDERATED', 'CONNECT', 'SPIDER', 'OQGRAPH') AND SUPPORT IN ('YES', 'DEFAULT')" < /dev/null 2> /dev/null)
    if [ -n "$engines" ] && [ "$engines" != NULL ]; then
        echo "No se carga: MariaDB tiene activos los motores $engines, con los que una tabla del volcado"
        echo "podria entrar como root en este MariaDB. Desactivalos (UNINSTALL SONAME) y vuelve a cargarlo."
        return 1
    fi
    if ! db_exists "$db"; then
        if [ $create -eq 0 ]; then
            echo "La base $db no existe en lampp-$folder (con --crear se crea)"

            return 1
        fi
        echo "Creando la base de datos $db..."
        run "${mysql[@]}" -e "CREATE DATABASE \`$db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci" < /dev/null || return 1
    else
        # (ya existe: se vacia siempre, con copia antes si tiene tablas)
        local tables
        tables=$("${mysql[@]}" -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$db'" < /dev/null)
        if ! [[ "$tables" =~ ^[0-9]+$ ]]; then
            echo "No se pueden ver las tablas de $db: no se ha cambiado nada."
            return 1
        fi
        if [ "$tables" -gt 0 ] && [ $backup -eq 1 ]; then
            saved="$HOME/lvm-copias/lampp-$DB_FOLDER-$db-antes-de-cargar-$(date +%Y%m%d-%H%M%S).sql.gz"
            echo "$db ya tiene $tables $([ "$tables" == 1 ] && echo tabla || echo tablas): se borran todas antes de cargar."
            echo "Antes se guarda una copia suya en $saved"
            run mkdir -p -m 700 "$HOME/lvm-copias"
            if ! export_database "$db" "$saved" "$DB_FOLDER"; then
                echo "No se ha podido guardar la copia de $db, asi que no se ha cambiado nada."
                return 1
            fi
        fi
        echo "Vaciando la base de datos $db..."
        local charset=$("${mysql[@]}" -N -e "SELECT CONCAT(DEFAULT_CHARACTER_SET_NAME, ' COLLATE ', DEFAULT_COLLATION_NAME)
            FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$db'" < /dev/null)
        run "${mysql[@]}" -e "DROP DATABASE \`$db\`; CREATE DATABASE \`$db\` CHARACTER SET $charset" < /dev/null || return 1
    fi

    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] mysql $db < $file"
        [ -n "$project" ] && import_project "$db" "$project"

        return 0
    fi

    # Las copias de WordPress o PrestaShop pueden traer filas grandes: el servidor admite paquetes
    # de hasta 1 GB (hasta que se reinicie) y el cliente tambien
    "${mysql[@]}" -e "SET GLOBAL max_allowed_packet = GREATEST(@@GLOBAL.max_allowed_packet, 1073741824)" < /dev/null 2> /dev/null

    # El volcado se carga con el usuario de esa base (lvm_bd_<base>), que solo puede tocarla (no
    # root): un .sql de una web comprometida no puede cambiar otras bases, crear usuarios ni leer o
    # escribir ficheros desde el servidor (sin el permiso FILE). En el permiso, el _ va escapado
    # (si no, wp_x valdria tambien para wpYx). Al terminar se bloquea: no puede entrar, pero las
    # vistas y disparadores del volcado (que son suyos) siguen funcionando.
    local imp_user="lvm_bd_$db" imp_pass grant_db=${db//_/\\_}
    imp_pass=$(head -c 18 /dev/urandom | base64 | tr -d '/+=\n')
    db_drop_import_users "${mysql[@]}"
    # (con su huella, no con la contraseña: la orden se ve en ps; la contraseña va en MYSQL_PWD)
    local imp_hash
    imp_hash=$(printf '%s' "$imp_pass" | db_pass_hash) || return 1
    if ! "${mysql[@]}" -e "CREATE USER IF NOT EXISTS '$imp_user'@'localhost' IDENTIFIED BY PASSWORD '$imp_hash';
            ALTER USER '$imp_user'@'localhost' IDENTIFIED BY PASSWORD '$imp_hash' ACCOUNT UNLOCK;
            GRANT ALL PRIVILEGES ON \`$grant_db\`.* TO '$imp_user'@'localhost'" < /dev/null; then
        echo "No se ha podido preparar el usuario de la base para cargar el volcado"
        return 1
    fi
    # Si la carga se interrumpe, solo se marca: despues se limpia lo que haya cargado (con su
    # usuario, que aun puede entrar) y se bloquea igual
    local imp_stop=0
    trap 'imp_stop=1' INT TERM HUP PIPE
    local imp=(env MYSQL_PWD="$imp_pass" "${DB_SAFE[@]}" "$DB_CLIENT" -u"$imp_user" --default-character-set=utf8mb4
               --binary-mode --local-infile=0)

    # Lectura: descomprimir (gzip o zip), quitar la linea del modo sandbox y los DEFINER de vistas,
    # disparadores y rutinas (son de otro usuario: con el temporal no se podrian crear)
    local source=(cat) filter=(env LC_ALL=C sed -E -e 's/DEFINER=`[^`]*`@`[^`]*`//g')
    case $kind in
        gz) source=(gzip -dc) ;;
        zip) source=(python3 -I -c "$ZIP_SQL_PY" extraer -) ;;
    esac
    [ $sandbox -eq 1 ] && filter=(env LC_ALL=C sed -E -e '/^\/\*M!999999\\-/d' -e 's/DEFINER=`[^`]*`@`[^`]*`//g')
    local definer=(python3 -I -c "$INVOKER_PY")
    local start=$(date +%s)

    exec 3< "$file"
    if [ -n "$TASK_OWNER" ]; then
        task_detail "cargando" fdpos "/proc/$BASHPID/fdinfo/3" "$size" "$start"
    elif [ -n "$LVM_PROGRESO" ]; then
        { echo "I|1|1|Cargando $name en $db|$start"
          echo "S|1|0|100|cargando|fdpos|/proc/$BASHPID/fdinfo/3|$size|$start"; } >> "$LVM_PROGRESO"
    fi
    echo "Cargando..."
    if [ -z "$LVM_PROGRESO" ] && [ -t 2 ] && command -v pv > /dev/null; then
        # En una terminal, la barra de pv (el zip necesita poder saltar dentro del fichero: pv va
        # sobre el .sql ya descomprimido)
        if [ $kind == zip ]; then
            ( set -o pipefail; python3 -I -c "$ZIP_SQL_PY" extraer "$file" | pv -s "$inner_size" \
                | "${filter[@]}" | "${definer[@]}" | "${imp[@]}" --max-allowed-packet=1G "$db" )
        else
            ( set -o pipefail; pv -s "$size" <&3 | "${source[@]}" | "${filter[@]}" \
                | "${definer[@]}" | "${imp[@]}" --max-allowed-packet=1G "$db" )
        fi
    else
        ( set -o pipefail; "${source[@]}" <&3 | "${filter[@]}" | "${definer[@]}" | "${imp[@]}" --max-allowed-packet=1G "$db" )
    fi
    rc=$?
    exec 3<&-
    # Primero se cortan sus conexiones (un evento del volcado que ya estuviera corriendo), despues
    # eventos y tablas con DIRECTORY, luego lo INVOKER; se bloquea y root repasa que no quede nada
    db_kill_user "$imp_user" "${mysql[@]}"
    db_neutralize_extras "$db" "${imp[@]}"
    db_neutralize_invoker "$db" "${imp[@]}"
    db_lock_import_user "$imp_user" "${mysql[@]}"
    db_root_cleanup "$db" "${mysql[@]}"
    trap - INT TERM HUP PIPE
    if [ $imp_stop -eq 1 ]; then
        echo "Carga interrumpida. Lo anterior ya esta en $db."
        [ -n "$saved" ] && echo "Lo que tenia antes esta en $saved (se vuelve a cargar con importar-bd)."
        return 130
    fi
    [ -n "$LVM_PROGRESO" ] && [ -z "$TASK_OWNER" ] && echo "R|bd:$db|$rc" >> "$LVM_PROGRESO"

    local secs=$(( $(date +%s) - start ))
    if [ $rc -ne 0 ]; then
        echo "Error al cargar $name. Lo anterior al error ya esta en $db."
        echo "Si el error es «Access denied», el volcado intenta tocar otra base o crear usuarios:"
        echo "solo se carga lo que va en $db (un volcado de una sola base, como los de phpMyAdmin)."
        [ -n "$saved" ] && echo "Lo que tenia antes esta en $saved (se vuelve a cargar con importar-bd)."

        return 1
    fi

    local tables=$("${mysql[@]}" -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$db'" < /dev/null)
    echo "Cargado en $((secs / 60)) min $((secs % 60)) s. La base $db tiene ahora $tables $([ "$tables" == 1 ] && echo tabla || echo tablas)."
    db_note_import "${DB_TARGET_DATA:-/opt/lampp/var/mysql}" "$db" "$(date +%s)"
    # Administrador de pruebas para el boton del panel de Cargar proyecto (WordPress o PrestaShop)
    local admin
    admin=$(test_admin "$db" "$project")
    grep -v '^A|' <<< "$admin" | grep .
    grep -q '^A|' <<< "$admin" && echo "Administrador de pruebas del panel: $TEST_ADMIN_USER, contraseña $TEST_ADMIN_PASS"
    # Correo de pruebas: lo que mande la web (sus plugins de correo, la configuracion de la tienda) va a
    # Mailpit (o, apagado, se deshace lo que traiga hecho)
    mail_db "$db"
    [ -n "$project" ] && { import_project "$db" "$project" || return 1; }
    return 0
}

#@incluir comun/cargar-bases-datos-version/db_neutralize_invoker.sh
# MariaDB de XAMPP trae un usuario anonimo (sin nombre ni contraseña) y permisos para cualquiera
# sobre las bases test y test_*: se quitan (las pilas propias ya se crean sin ellos). Con la version
# montada en marcha; si root tiene contraseña, con MYSQL_PWD.
# Tablas del sistema de MariaDB (mysql.*) de una version anterior a la del servidor: los datos de
# XAMPP vienen de una MariaDB antigua sin poner al dia, y el servidor escribe un error en su registro
# cada vez que usa las estadisticas de una tabla (en una 8.2.4 llego a 28 GB). 0 si la version
# montada, en marcha, las tiene asi (en las de 10.4 en adelante: varbinary(255) y varchar(199))
function db_system_outdated() {
    [ -x "$DB_CLIENT" ] && lampp_running || return 1
    local t
    t=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT CONCAT(TABLE_NAME, '.', COLUMN_NAME, '=', COLUMN_TYPE) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = 'mysql' AND ((TABLE_NAME = 'column_stats' AND COLUMN_NAME = 'min_value')
        OR (TABLE_NAME = 'innodb_table_stats' AND COLUMN_NAME = 'table_name'))" < /dev/null 2> /dev/null) || return 1
    [ -n "$t" ] || return 1
    grep -q "^column_stats.min_value=varbinary" <<< "$t" && grep -q "^innodb_table_stats.table_name=varchar(199)" <<< "$t" && return 1
    return 0
}

# Registro de errores de MariaDB de una version: el .err mas grande de var/mysql (solo su ruta)
function db_error_log() {
    find "$1/var/mysql" -maxdepth 1 -type f -name '*.err' -printf '%s %p\n' 2> /dev/null | sort -rn | head -1 | cut -d' ' -f2-
}

# reparar-bd-sistema: pone al dia las tablas del sistema de MariaDB de la version montada (con su
# propio mysql_upgrade, solo las del sistema: las bases de los proyectos no se tocan), despues de
# guardar una copia de la base mysql en ~/lvm-copias, y vacia su registro de errores si es grande
function repair_db_system() {
    local dir name upgrade dump log size backup out
    dir=$(active_dir)
    if [ -z "$dir" ] || ! lampp_running; then
        echo "La version activa tiene que estar en marcha: arrancala y vuelve a intentarlo."
        return 1
    fi
    if ! wait_mariadb; then
        echo "MariaDB no responde o root tiene contraseña (ponla en MYSQL_PWD y vuelve a intentarlo)."
        return 1
    fi
    name=$(basename "$dir")
    if [ -x "$dir/mysql/bin/mariadb-upgrade" ]; then
        upgrade=("$dir/mysql/bin/mariadb-upgrade") dump=("$dir/mysql/bin/mariadb-dump")
    elif [ -x "$dir/bin/mysql_upgrade" ] && [ -x "$dir/bin/mysqldump" ]; then
        upgrade=("$dir/bin/mysql_upgrade") dump=("$dir/bin/mysqldump")
    else
        echo "$name no tiene mysql_upgrade"
        return 1
    fi
    upgrade+=(--no-defaults -S "$dir/var/mysql/mysql.sock" -uroot)
    dump+=(--no-defaults -S "$dir/var/mysql/mysql.sock" -uroot)
    log=$(db_error_log "$dir")
    # mysql_upgrade escribe en la carpeta de datos (mysql_upgrade_info): se ejecuta con su dueño
    # (mysql, o tu usuario en el Mac), nunca como root. Con sudo -u, MYSQL_PWD no pasaria
    local owner as_owner=()
    owner=$(stat -c %U "$dir/var/mysql" 2> /dev/null)
    if [ -n "$owner" ] && [ "$owner" != "$(id -un)" ]; then
        [[ "$owner" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,31}$ ]] && [ "$owner" != root ] || {
            echo "La carpeta de datos de $name es de $owner: no se ejecuta mysql_upgrade con ese usuario."
            return 1
        }
        as_owner=(sudo -u "$owner")
        if [ -n "$MYSQL_PWD" ]; then
            echo "root de MariaDB tiene contraseña y con sudo -u no se le pasa: hazlo a mano en la terminal:"
            echo "  sudo -u $owner ${upgrade[0]} --no-defaults -S <socket> -uroot -p --upgrade-system-tables --force"
            return 1
        fi
    fi
    if db_system_outdated; then
        echo "Las tablas del sistema de MariaDB de $name son de una version anterior: se ponen al dia"
        echo "(las bases de los proyectos no se tocan)."
        backup="$HOME/lvm-copias/$name-mysql-sistema-$(date +%Y%m%d-%H%M%S).sql.gz"
        if [ "$DRY" -eq 1 ]; then
            echo "  [simulacion] copia de la base mysql en $backup"
            echo "  [simulacion] ${upgrade[0]##*/} --upgrade-system-tables --force"
        else
            mkdir -p -m 700 "$HOME/lvm-copias" || return 1
            if ! ( set -o pipefail; umask 077; "${dump[@]}" --databases mysql < /dev/null | gzip > "$backup" ); then
                rm -f "$backup"
                echo "No se ha podido guardar la copia de la base mysql: no se cambia nada."
                return 1
            fi
            echo "Copia de las tablas del sistema: $backup"
            if ! out=$("${as_owner[@]}" "${upgrade[@]}" --upgrade-system-tables --force < /dev/null 2>&1); then
                echo "$out" | tail -8 | sed 's/^/  /'
                echo "No se han podido poner al dia (la copia esta en $backup)."
                return 1
            fi
            echo "$out" | grep -E '^(Phase|OK)' | sed 's/^/  /'
            if db_system_outdated; then
                echo "Siguen sin estar al dia: revisa la salida de arriba."
                return 1
            fi
            echo "Tablas del sistema al dia."
            # Con las tablas antiguas, MariaDB no leia mysql.proc: rutinas INVOKER de volcados de
            # antes de la 1.42 (que nunca se neutralizaron) vuelven a funcionar. Se avisa de cuales
            local inv
            inv=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot --raw -N --force -e "SELECT CONCAT(ROUTINE_SCHEMA, '.', ROUTINE_NAME) FROM information_schema.ROUTINES
                    WHERE SECURITY_TYPE = 'INVOKER' AND ROUTINE_SCHEMA NOT IN ('mysql', 'sys');
                SELECT CONCAT(TABLE_SCHEMA, '.', TABLE_NAME) FROM information_schema.VIEWS
                    WHERE SECURITY_TYPE = 'INVOKER' AND TABLE_SCHEMA NOT IN ('mysql', 'sys');
                SELECT CONCAT(EVENT_SCHEMA, '.', EVENT_NAME, ' (evento)') FROM information_schema.EVENTS" < /dev/null 2> /dev/null)
            if [ -n "$inv" ]; then
                echo "Aviso: estas rutinas, vistas o eventos se ejecutan con los permisos de quien las use (root en"
                echo "phpMyAdmin). Si no las reconoces, vuelve a cargar esa BBDD con el gestor, que las neutraliza:"
                printf '%s\n' "$inv" | tr -c '[:alnum:]_ .()\n-' '?' | head -30 | sed 's/^/  /'
            fi
        fi
    else
        echo "Las tablas del sistema de MariaDB de $name ya estan al dia."
    fi
    # El registro: si pasa de 100 MB se vacia (solo son errores, ya corregidos; MariaDB sigue
    # escribiendo en el mismo fichero)
    if [ -n "$log" ] && [ -f "$log" ] && [ ! -L "$log" ] && [[ "$log" == "$dir"/var/mysql/*.err ]]; then
        size=$(stat -c %s "$log")
        if [ "$size" -gt 104857600 ]; then
            echo "El registro de errores de MariaDB ($log) ocupa $((size / 1048576)) MB: se vacia."
            # (con su dueño, mysql, no como root: no hace falta, y root seguiria un enlace)
            if [ ${#as_owner[@]} -gt 0 ]; then
                run sudo -u "$owner" truncate -s 0 "$log" || return 1
            else
                run truncate -s 0 "$log" || return 1
            fi
        fi
    fi
    return 0
}

# Espera (hasta 8 s) a que MariaDB de la version montada acepte a root. 1 si no arranca o pide
# contraseña (y no esta en MYSQL_PWD)
function wait_mariadb() {
    local i out
    [ -x "$DB_CLIENT" ] || return 1
    for i in 1 2 3 4 5 6 7 8; do
        out=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT 1" < /dev/null 2>&1) && return 0
        [[ "$out" == *"Access denied"* ]] && return 1
        sleep 1
    done
    return 1
}

function secure_mariadb() {
    [ -x "$DB_CLIENT" ] || return 0
    local mysql=("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N) hosts h
    hosts=$("${mysql[@]}" -e "SELECT Host FROM mysql.user WHERE User=''" < /dev/null 2> /dev/null) || return 0
    for h in $hosts; do
        [[ "$h" =~ ^[A-Za-z0-9._%-]+$ ]] || continue
        echo "MariaDB: se quita el usuario anonimo (''@$h)"
        [ "$DRY" -eq 1 ] || "${mysql[@]}" -e "DROP USER IF EXISTS ''@'$h'" < /dev/null 2> /dev/null
    done
    if [ -n "$("${mysql[@]}" -e "SELECT 1 FROM mysql.db WHERE Db IN ('test', 'test\\_%') LIMIT 1" < /dev/null 2> /dev/null)" ]; then
        echo "MariaDB: se quitan los permisos de cualquiera sobre las bases test"
        [ "$DRY" -eq 1 ] || "${mysql[@]}" -e "DELETE FROM mysql.db WHERE Db IN ('test', 'test\\_%'); FLUSH PRIVILEGES" < /dev/null 2> /dev/null
    fi
    # Usuarios de las bases que hayan quedado sin bloquear (una carga interrumpida)
    [ "$DRY" -eq 1 ] || db_drop_import_users "${DB_SAFE[@]}" "$DB_CLIENT" -uroot
    return 0
}

# Base subida para un proyecto: pasa a ser su base (sustituye a la anterior). Si es un WordPress, su
# wp-config.php se rehace con la plantilla para que la use; si es una tienda PrestaShop, su
# parameters.php (o settings.inc.php) pasa a usarla y se vacia su cache
function import_project() {
    local db=$1 folder=$2
    remember_project "$db" "$folder" "${DB_TARGET_FOLDER:-}" --unica
    echo "La base $db queda asociada al proyecto $folder"
    if is_prestashop "$folder"; then
        PS_NEW_PARAMS=0
        ps_parameters "$folder" "$db" || return 1
        ps_set_db "$folder" "$db" || return 1
        ps_first_load "$folder"
    elif is_wordpress "$folder"; then
        wp_config "$folder" "$db" || return 1
    fi
    return 0
}

# Codigo de la ventana (Python). No puede contener una linea con solo LVM_GUI_PY.
function gui_source() {
    cat <<'LVM_GUI_PY'
#@incluir ventana/
LVM_GUI_PY
}

