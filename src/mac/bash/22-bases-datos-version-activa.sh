# ===========================================================================
# Bases de datos de la version activa: cargar, crear y borrar
# ===========================================================================

# El cliente $LINK/xamppfiles/bin/mysql lee el my.cnf de la version activa (socket y puerto). Si root
# tiene contraseña, se pasa en la variable MYSQL_PWD
DB_SYSTEM="information_schema|mysql|performance_schema|phpmyadmin|sys|test"
# Para pruebas se puede usar otro cliente (por ejemplo uno contra un MariaDB temporal)
DB_CLIENT=${LVM_BD_CLIENTE:-$LINK/xamppfiles/bin/mysql}
# El cliente y mysqldump de XAMPP leen tambien ~/.my.cnf y $MYSQL_HOME/my.cnf, que cualquier programa
# tuyo puede preparar (plugin-dir/default-auth les hacen cargar una biblioteca) y se ejecutan en la
# terminal de la tarea, con el permiso de sudo recordado: siempre sin esos ficheros
DB_SAFE=(/usr/bin/env -u MYSQL_HOME -u MARIADB_HOME HOME=/var/empty)

# Tamaño legible: 1,5 GB
function human_size() {
    awk -v n="${1:-0}" 'BEGIN {
        split("B KB MB GB TB", u); i = 1
        while (n >= 1024 && i < 5) { n /= 1024; i++ }
        s = (i == 1) ? sprintf("%d %s", n, u[i]) : sprintf("%.1f %s", n, u[i])
        gsub(/\./, ",", s); print s
    }'
}

# Lo que ocupa en el disco cada proyecto de htdocs (du), para la lista de Proyectos:
# T|carpeta|bytes|cuando se midio. Se guarda y se vuelven a medir los que tienen la medida de hace mas
# de 6 horas, de 10 en 10 (du tarda con miles de ficheros), los mas antiguos antes. Si quedan mas por
# medir, lo dice al final (F|cuantos) y la ventana pide la siguiente tanda. Con "ya", sin esperar.
# (bash 3.2 de macOS: sin arrays asociativos ni mapfile; du de BSD, en KB)
function gui_project_sizes() {
    local cache=$LOG_DIR/cache/proyectos-tamanos now dir name t k left=0 list batch
    local -a dirs=()
    now=$(date +%s)
    mkdir -p -m 700 "$LOG_DIR/cache" || return 0
    [ -f "$cache" ] || : > "$cache"
    # Los que hay que medir, los mas antiguos antes («cuando|carpeta»)
    list=$(for dir in "$HTDOCS_DIR"/*; do
               name=${dir##*/}
               [ -d "$dir" ] && [ ! -L "$dir" ] && [[ "$name" != *'|'* ]] || continue
               t=$(awk -F'|' -v n="$name" '$1 == n { print $3; exit }' "$cache")
               [[ "$t" =~ ^[0-9]+$ ]] || t=0
               if [ "$1" == ya ] || [ $((now - t)) -ge 21600 ]; then echo "$t|$name"; fi
           done | sort -t'|' -k1,1n)
    if [ -n "$list" ]; then
        left=$(( $(wc -l <<< "$list") - 10 ))
        [ $left -lt 0 ] && left=0
        batch=$(head -10 <<< "$list" | cut -d'|' -f2-)
        while IFS= read -r name; do dirs+=("$HTDOCS_DIR/$name"); done <<< "$batch"
        # (sin salir del disco ni seguir enlaces; lo que no se puede leer no cuenta)
        { REDO=$batch awk -F'|' 'BEGIN { n = split(ENVIRON["REDO"], r, "\n"); for (i = 1; i <= n; i++) skip[r[i]] = 1 }
                                 !($1 in skip)' "$cache" | while IFS='|' read -r name k t; do
              [ -d "$HTDOCS_DIR/$name" ] && [ ! -L "$HTDOCS_DIR/$name" ] && echo "$name|$k|$t"
          done
          du -skx "${dirs[@]}" 2> /dev/null | while IFS=$'\t' read -r k dir; do
              [[ "$k" =~ ^[0-9]+$ ]] && echo "${dir##*/}|$((k * 1024))|$now"
          done
        } > "$cache.nuevo" && mv -f "$cache.nuevo" "$cache"
    fi
    grep -E '^[^|]+\|[0-9]+\|[0-9]+$' "$cache" | sed 's/^/T|/'
    [ "$left" -gt 0 ] && echo "F|$left"
    return 0
}

# ¿Se puede entrar en el MariaDB de la version activa? ok|version|mariadb / clave|version / no|motivo
function gui_db_check() {
    local active=$(active_dir)
    if [ -z "$active" ]; then
        echo "no|No hay ninguna versión activa."

        return 0
    fi

    local version=$(version_name "$active") out
    if [ ! -x "$DB_CLIENT" ]; then
        echo "no|XAMPP-$version no tiene el cliente de MariaDB (bin/mysql)."

        return 0
    fi

    if out=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e 'SELECT VERSION()' < /dev/null 2>&1); then
        echo "ok|$version|${out%%-*}"
    elif [[ "$out" == *1045* ]] || [[ "$out" == *"Access denied"* ]]; then
        echo "clave|$version"
    else
        echo "no|El MariaDB de XAMPP-$version no está en marcha. Arráncalo antes."
    fi
}

# Tamaño de cada BBDD (datos e indices, de information_schema) de la version activa en marcha. Se
# guarda para enseñar tambien el de las demas versiones (sus carpetas de datos no se pueden leer sin
# sudo): Z|version de las BBDD|base|bytes|cuando se midio (segundos desde 1970). La cache se
# rehace en un fichero nuevo que sustituye al anterior (sin sed -i)
function gui_db_sizes() {
    local cache=$LOG_DIR/cache/bbdd-tamanos active owner out check now
    now=$(date +%s)
    mkdir -p -m 700 "$LOG_DIR/cache" || return 0
    active=$(active_dir)
    if [ -n "$active" ] && check=$(gui_db_check) && [[ "$check" == ok\|* ]]; then
        owner=$(version_name "$active")
        out=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -B -e "SELECT table_schema, SUM(data_length + index_length) FROM information_schema.tables GROUP BY table_schema" < /dev/null 2> /dev/null)
        if [ -n "$out" ] && valid_version_name "$owner"; then
            { [ -f "$cache" ] && awk -F'|' -v v="$owner" '$1 != v' "$cache"
              awk -F'\t' -v v="$owner" -v t="$now" '$1 ~ /^[A-Za-z0-9_-]+$/ && $2 ~ /^[0-9]+$/ { print v "|" $1 "|" $2 "|" t }' <<< "$out"
            } > "$cache.nuevo" && mv -f "$cache.nuevo" "$cache"
        fi
    fi
    [ -f "$cache" ] && grep -E '^[A-Za-z0-9._-]+\|[A-Za-z0-9_-]+\|[0-9]+\|[0-9]+$' "$cache" | sed 's/^/Z|/'
    return 0
}

# Conexion con el MariaDB activo: deja en DB_FOLDER la version activa y en DB_VERSION la de MariaDB.
# Si no se puede, explica por que (sale con 3 si hace falta la contraseña de root)
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
# Bases de la version activa vistas por el servidor (sin las del sistema)
function db_list_active() {
    "${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA" < /dev/null 2> /dev/null \
        | grep -vxE "$DB_SYSTEM" | sort -f
}

# crear-bd <base>: base vacia en utf8mb4_general_ci (como las de XAMPP)
function create_database() {
    local db=$1 rc
    db_valid_name "$db" || return 1
    db_connect
    rc=$?
    [ $rc -ne 0 ] && return $rc

    if db_exists "$db"; then
        echo "Ya hay una base de datos $db en XAMPP-$DB_FOLDER"

        return 1
    fi

    run "${DB_SAFE[@]}" "$DB_CLIENT" -uroot -e "CREATE DATABASE \`$db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci" < /dev/null || return 1
    db_note_import "$LINK/xamppfiles/var/mysql" "$db"
    echo "Base de datos $db creada en XAMPP-$DB_FOLDER"
}

# Tablas y tamaño (bytes) de una base: I|tablas|bytes
function gui_db_info() {
    local db=$1 rc
    db_valid_name "$db" || return 1
    db_connect
    rc=$?
    [ $rc -ne 0 ] && return $rc

    if ! db_exists "$db"; then
        echo "No hay ninguna base de datos $db en XAMPP-$DB_FOLDER"

        return 1
    fi

    "${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT CONCAT('I|', COUNT(*), '|', COALESCE(SUM(DATA_LENGTH + INDEX_LENGTH), 0))
        FROM information_schema.TABLES WHERE TABLE_SCHEMA='$db'" < /dev/null
}

# borrar-bd <base> [--copia]: elimina la base y todo su contenido. Con --copia guarda antes un
# volcado en ~/nexum-backups (se puede volver a cargar con importar-bd); si la copia falla, no se borra
function drop_database() {
    local db=$1 backup=0 rc
    [ "$2" == "--copia" ] && backup=1
    db_valid_name "$db" || return 1
    db_connect
    rc=$?
    [ $rc -ne 0 ] && return $rc

    if ! db_exists "$db"; then
        echo "No hay ninguna base de datos $db en XAMPP-$DB_FOLDER"

        return 1
    fi

    if [ $backup -eq 1 ]; then
        local dump=${LVM_BD_VOLCADO:-$(dirname "$DB_CLIENT")/mysqldump}
        local dest="$COPIES_DIR/XAMPP-$DB_FOLDER-$db-$(date +%Y%m%d-%H%M%S).sql.gz"
        echo "Guardando copia de $db en $dest..."
        if [ "$DRY" -eq 1 ]; then
            echo "  [simulacion] mysqldump $db | gzip > $dest"
        else
            mkdir -p -m 700 "$COPIES_DIR"
            if ! ( set -o pipefail; "${DB_SAFE[@]}" "$dump" -uroot --default-character-set=utf8mb4 --single-transaction \
                --routines --triggers --events "$db" < /dev/null | gzip > "$dest" ); then
                rm -f "$dest"
                echo "No se ha podido guardar la copia, asi que NO se borra nada."

                return 1
            fi
            echo "Copia guardada: $dest ($(du -h "$dest" | cut -f1))"
        fi
    fi

    echo "Borrando la base de datos $db de XAMPP-$DB_FOLDER..."
    run "${DB_SAFE[@]}" "$DB_CLIENT" -uroot -e "DROP DATABASE \`$db\`" < /dev/null || return 1
    db_note_import "$LINK/xamppfiles/var/mysql" "$db"
    echo "Base de datos $db borrada"
}

# Posicion de lectura del descriptor <fd> del proceso <pid> ("pid:fd"). macOS no tiene /proc: se
# consulta con lsof, que da la posicion como 0t<decimal> o, si es grande, como 0x<hexadecimal>
function fd_offset() {
    local off=$(lsof -a -p "${1%%:*}" -d "${1##*:}" -o -Fo 2> /dev/null | sed -n 's/^o//p' | head -1)
    case "$off" in
        0t*) echo "${off#0t}" ;;
        0x*) echo $(( 16#${off#0x} )) ;;
        *) echo 0 ;;
    esac
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

# MariaDB temporal de una version que no esta en marcha: sin red, sin comprobar usuarios
# (--skip-grant-tables: solo se llega por un socket en una carpeta temporal). Deja el socket en
# DB_TMP_SOCK; db_temp_stop lo para.
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
    local root=$1/xamppfiles data=$1/xamppfiles/var/mysql user grants=(--skip-grant-tables)
    # (con --con-permisos, con sus usuarios: para cargar una base con su usuario lvm_bd_<base>)
    [ "$2" == "--con-permisos" ] && grants=()
    # Si su MariaDB ya esta en marcha (la arranco Docker, sin red), se usa esa: otra no podria abrir los
    # mismos datos. DB_TMP se queda vacio: db_temp_stop no la para
    if db_socket_alive "$data/mysql.sock"; then
        echo "Se usa el MariaDB que ya esta en marcha para Docker (sin red)"
        DB_TMP_SOCK=$data/mysql.sock DB_TMP_PID=""
        return 0
    fi
    # Root ejecuta su mariadbd: solo de una version de root (como xampp_ctl)
    if [ -z "$TEST_DIR" ] && ! trusted_version_dir "$1"; then
        echo "No se arranca el MariaDB de $1 como administrador: no es de root, tiene enlaces o el grupo"
        echo "puede cambiarlo (lvm-instalador asegurar --todas)"

        return 1
    fi
    # El dueño de los datos de verdad (-L: si var/mysql es un enlace, el de su destino). Nunca root:
    # un MariaDB de root escribiria como root donde le pidiera una base (DATA DIRECTORY, registros)
    user=$($SUDO stat -L -f %Su "$data") || return 1
    [ -n "$TEST_DIR" ] && user=$(id -un)
    if [ "$user" == "root" ] || ! [[ "$user" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]]; then
        echo "Las BBDD de XAMPP-$(version_name "$1") son de $user: no se arranca su MariaDB con ese usuario"
        return 1
    fi
    if [ ! -x "$root/mysql/bin/mariadbd" ]; then
        echo "XAMPP-$(version_name "$1") no tiene el servidor de MariaDB"

        return 1
    fi

    # La carpeta la crea root y solo es del usuario del servidor (en el Mac, el tuyo): no pide
    # contraseña mientras dura la copia y otros usuarios del Mac no pueden llegar a su socket
    DB_TMP=$($SUDO mktemp -d /tmp/lvm-mysql-XXXX) || { DB_TMP=""; return 1; }
    DB_TMP_SOCK=$DB_TMP/mysql.sock
    $SUDO chown "$user" "$DB_TMP" && $SUDO chmod 700 "$DB_TMP" || { $SUDO rm -rf "$DB_TMP"; DB_TMP=""; return 1; }

    echo "Arrancando un MariaDB temporal de XAMPP-$(version_name "$1") (sin red, solo para esta copia)..."
    $SUDO "$root/mysql/bin/mariadbd" --defaults-file="$root/etc/my.cnf" --user="$user" --skip-networking \
        "${grants[@]}" --socket="$DB_TMP_SOCK" --pid-file="$DB_TMP/mysql.pid" --log-error="$DB_TMP/mysql.log" \
        < /dev/null > /dev/null 2>&1 &
    local server_pid=$!
    DB_TMP_PID=$server_pid

    local i
    for i in $(seq 300); do
        [ -S "$DB_TMP_SOCK" ] && return 0
        # (sin kill -0: el pid es el del sudo, que es de root, y kill -0 a un proceso de root da
        # «no permitido» aunque siga vivo)
        /bin/ps -p "$server_pid" > /dev/null 2>&1 || break
        sleep 0.2
    done
    echo "No ha arrancado. Ultimas lineas de su registro:"
    # (lo lee el dueño de los datos, no root: si el registro fuera un enlace a un fichero de root,
    # root lo mostraria)
    $SUDO ${SUDO:+-u "$user"} /usr/bin/tail -15 "$DB_TMP/mysql.log" 2> /dev/null | sed 's/^/  /'

    return 1
}

#@incluir comun/cargar-bases-datos-version/db_temp_kill_launched.sh
function db_temp_stop() {
    [ -z "$DB_TMP" ] && return 0
    if $SUDO test -f "$DB_TMP/mysql.pid"; then
        echo "Parando el MariaDB temporal..."
        # El de su .pid si es el servidor (en el Mac corre con tu usuario: el .pid lo podria cambiar
        # otro programa tuyo); si no, el sudo que lo arranco (que le pasa la señal)
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
# [--sustituir [--copia]]: --como le da otro nombre en la de destino (base_8_4 -> base_8_5) y --carpeta la
# vincula alli a esa carpeta de proyecto (- = a ninguna; sin --carpeta, el vinculo no se toca).
# Copia una base a otra version que no
# la tiene, para probar el proyecto con otro PHP. Se descarga de la de origen (como exportar-bd) a un
# fichero solo tuyo y se carga en la de destino con la carga protegida de importar-bd (usuario de la
# base, sin DEFINER, lo INVOKER y los eventos neutralizados). Si la de destino no es la activa en
# marcha, se arranca su MariaDB solo para la copia (sin red y con su propio socket). La de origen no
# se toca
function copy_database() {
    local db=$1 src=$2 dst=$3 sdir ddir tmp rc active
    local replace=0 load=(--crear) new="" link="" usage=0 backup=0
    shift 3 2> /dev/null
    # --sustituir: si la de destino ya la tiene, se carga la de origen encima (la de destino se vacia
    # antes de cargar); con --copia, antes se guarda una copia suya en ~/nexum-backups
    while [ $# -gt 0 ]; do
        case $1 in
            --sustituir) replace=1; shift ;;
            --copia) backup=1; shift ;;
            --como|--carpeta)
                [ -n "$2" ] || { usage=1; break; }
                [ "$1" == --como ] && new=$2 || link=$2
                shift 2 ;;
            *) usage=1; break ;;
        esac
    done
    if [ -z "$db" ] || [ -z "$src" ] || [ -z "$dst" ] || [ $usage -eq 1 ]; then
        echo "Uso: lvm-instalador copiar-bd <base de datos> <version de origen> <version de destino> [--como <nombre>] [--carpeta <carpeta|->] [--sustituir [--copia]]"
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
    if [ "$src" == "$dst" ]; then
        echo "La version de origen y la de destino son la misma"
        return 1
    fi
    sdir="$BASE_DIR/XAMPP-$src" ddir="$BASE_DIR/XAMPP-$dst"
    [ -d "$sdir" ] && [ ! -L "$sdir" ] || { echo "No existe la version XAMPP-$src"; return 1; }
    [ -d "$ddir" ] && [ ! -L "$ddir" ] || { echo "No existe la version XAMPP-$dst"; return 1; }
    if ! db_names "$sdir" | grep -qxF "$db"; then
        echo "No hay ninguna BBDD $db en XAMPP-$src"
        return 1
    fi
    if db_names "$ddir" | grep -qxF "$new"; then
        if [ $replace -eq 0 ]; then
            echo "XAMPP-$dst ya tiene una BBDD $new: no se toca (con --sustituir se pone la de XAMPP-$src en"
            echo "su lugar, y con --copia antes se guarda una copia suya; o copiala con otro nombre: --como)"
            return 1
        fi
        load=(--crear --sin-copia)
    else
        replace=0
    fi
    active=$(active_dir)
    local shown=$db
    [ "$new" != "$db" ] && shown="$db (como $new)"
    echo "Copia de la BBDD $shown: de XAMPP-$src a XAMPP-$dst (XAMPP-$src no se toca)"
    if [ "$DRY" -eq 1 ]; then
        [ $replace -eq 1 ] && [ $backup -eq 1 ] && echo "  [simulacion] copia de $new de XAMPP-$dst en ~/nexum-backups (la sustituida)"
        [ $replace -eq 1 ] && [ $backup -eq 0 ] && echo "  [simulacion] sin copia de $new de XAMPP-$dst (la sustituida)"
        echo "  [simulacion] descarga de $db de XAMPP-$src a un fichero temporal en ~/.lvm-instalador"
        if [ "$active" == "$(realpath_f "$ddir")" ] && lampp_running; then
            echo "  [simulacion] carga en el MariaDB en marcha de XAMPP-$dst (importar-bd ${load[*]})"
        else
            echo "  [simulacion] MariaDB temporal de XAMPP-$dst (sin red) y carga de $new"
        fi
        if [ "$link" == "-" ]; then
            echo "  [simulacion] $new sin vincular a ningun proyecto en XAMPP-$dst"
        elif [ -n "$link" ]; then
            echo "  [simulacion] $new vinculada a $link en XAMPP-$dst"
        fi
        return 0
    fi
    if [ $replace -eq 1 ] && [ $backup -eq 0 ]; then
        echo "XAMPP-$dst ya tiene $new: se sustituye."
        echo "Sin copia: la que tenia no se podra recuperar (con --copia se guarda antes en ~/nexum-backups)"
    elif [ $replace -eq 1 ]; then
        local saved="$COPIES_DIR/XAMPP-$dst-$new-antes-de-copiar-$(date +%Y%m%d-%H%M%S).sql.gz"
        echo "XAMPP-$dst ya tiene $new: antes se guarda una copia suya en $saved"
        mkdir -p -m 700 "$COPIES_DIR" || return 1
        if ! export_database "$new" "$saved" "$dst"; then
            echo "No se ha podido guardar la copia de $new de XAMPP-$dst, asi que no se ha cambiado nada."
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
        echo "No se ha podido descargar $db de XAMPP-$src: no se ha copiado nada."
        return 1
    fi
    db_temp_stop
    if [ "$active" == "$(realpath_f "$ddir")" ] && lampp_running; then
        import_database "$tmp" "$new" "${load[@]}"
        rc=$?
    else
        # MariaDB de la de destino solo para la copia, con sus usuarios (la carga va con el usuario de
        # la base). Su cliente, sin ficheros de opciones (llevarian al socket de la activa), por un
        # envoltorio en una carpeta de root (db_client_wrapper)
        local client=$ddir/xamppfiles/mysql/bin/mariadb
        if [ ! -x "$client" ] || ! db_temp_start "$ddir" --con-permisos; then
            rm -f "$tmp"
            db_temp_stop
            return 1
        fi
        if ! db_client_wrapper "$client" "" "$DB_TMP_SOCK"; then
            rm -f "$tmp"
            db_temp_stop
            return 1
        fi
        DB_CLIENT=$DB_CLI DB_TARGET_FOLDER=$dst DB_TARGET_DATA="$ddir/xamppfiles/var/mysql" import_database "$tmp" "$new" "${load[@]}"
        rc=$?
        db_client_wrapper_remove
        db_temp_stop
    fi
    rm -f "$tmp"
    DB_COPY_TMP=""
    if [ $rc -eq 0 ]; then
        if [ "$link" == "-" ]; then
            remember_project "$new" "" "$dst"
            echo "$new no queda vinculada a ningun proyecto en XAMPP-$dst (vinculala en Cargar proyecto)."
        elif [ -n "$link" ]; then
            remember_project "$new" "$link" "$dst"
            echo "$new queda vinculada al proyecto $link en XAMPP-$dst."
        fi
        echo "$new esta ahora en XAMPP-$dst. Para probar el proyecto con PHP $(php_version "$ddir" 2> /dev/null),"
        echo "cargalo en Proyectos y elige XAMPP-$dst en su Entorno."
    fi
    return $rc
}

# pasar-version <origen> <destino>: despues de instalar el parche nuevo de PHP a su lado (XAMPP-8.4.26
# -> XAMPP-8.4.27), copia a la nueva todas las BBDD de la anterior con copiar-bd, cada una vinculada
# a su carpeta como estaba, y la activa si la anterior era la activa. La anterior no se toca (se
# desinstala despues a mano). Las que la nueva ya tiene no se tocan
function move_to_version() {
    local src=$1 dst=$2 sdir ddir db folder rc=0 was_active=0 n=0
    valid_version_name "$src" && valid_version_name "$dst" && [ -n "$src" ] && [ -n "$dst" ] && [ "$src" != "$dst" ] \
        || { echo "Uso: lvm-instalador pasar-version <origen> <destino>"; return 1; }
    sdir=$BASE_DIR/XAMPP-$src ddir=$BASE_DIR/XAMPP-$dst
    [ -f "$sdir/xamppfiles/etc/pvm-stack" ] && [ ! -L "$sdir" ] || { echo "No existe la version XAMPP-$src"; return 1; }
    [ -f "$ddir/xamppfiles/etc/pvm-stack" ] && [ ! -L "$ddir" ] || { echo "No existe la version XAMPP-$dst"; return 1; }
    [ "$(active_dir)" == "$(realpath_f "$sdir")" ] && was_active=1
    echo "BBDD de XAMPP-$src a XAMPP-$dst, con sus vinculos (XAMPP-$src no se toca)"
    for db in $(db_names "$sdir"); do
        if db_names "$ddir" | grep -qxF "$db"; then
            echo "  $db ya esta en XAMPP-$dst: no se toca"
            continue
        fi
        folder=$(linked_folder "$db" "$src")
        copy_database "$db" "$src" "$dst" ${folder:+--carpeta "$folder"} || { rc=1; echo "  No se ha podido copiar $db"; }
        n=$((n + 1))
    done
    [ $n -eq 0 ] && echo "  No hay BBDD que copiar"
    if [ $rc -ne 0 ]; then
        echo "Alguna BBDD no se ha copiado: XAMPP-$dst no se activa. Revisa el registro."
        return 1
    fi
    if [ $was_active -eq 1 ]; then
        echo "XAMPP-$src era la activa: se activa XAMPP-$dst"
        use_version "$dst" || return 1
    fi
    echo "Listo. Cuando compruebes que todo va bien, desinstala XAMPP-$src."
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


# exportar-bd <base> <fichero .zip, .sql o .sql.gz> [version]: descarga una copia de la base
# (estructura, datos, rutinas, disparadores y eventos) que se puede volver a cargar con importar-bd.
# Sin version, de la activa. Si es la activa y esta en marcha se usa su MariaDB; si no, uno
# temporal (pide la contraseña de administrador).
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

function export_database() {
    local db=$1 dest=$2 folder=$3
    if [ -z "$db" ] || [ -z "$dest" ]; then
        echo "Uso: lvm-instalador exportar-bd <base de datos> <fichero.zip|.sql|.sql.gz> [version]"

        return 1
    fi
    db_valid_name "$db" || return 1
    local active=$(active_dir)
    folder=${folder:-$([ -n "$active" ] && version_name "$active")}
    local dir="$BASE_DIR/XAMPP-$folder"
    if [ -z "$folder" ] || [ ! -d "$dir" ]; then
        echo "No existe la version XAMPP-$folder"

        return 1
    fi
    if ! db_names "$dir" | grep -qxF "$db"; then
        echo "No hay ninguna base de datos $db en XAMPP-$folder"

        return 1
    fi
    local parent
    parent=$(cd "$(dirname "$dest")" 2> /dev/null && pwd -P)
    if [ -z "$parent" ] || [ ! -w "$parent" ]; then
        echo "No se puede escribir en $(dirname "$dest")"

        return 1
    fi
    dest=$parent/$(basename "$dest")

    echo "Base de datos: $db (XAMPP-$folder)"
    echo "Destino: $dest"
    local dump=() query=() check
    trap db_cleanup EXIT
    trap 'exit 130' INT TERM HUP
    if [ "$dir" == "$active" ] && check=$(gui_db_check) && [[ "$check" != no\|* ]]; then
        db_connect || return $?
        echo "Se usa el MariaDB en marcha de XAMPP-$DB_FOLDER (MariaDB $DB_VERSION)"
        dump=("${DB_SAFE[@]}" "${LVM_BD_VOLCADO:-$(dirname "$DB_CLIENT")/mysqldump}" -uroot)
        query=("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N)
    elif [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] MariaDB temporal de XAMPP-$folder y mysqldump $db > $dest"

        return 0
    else
        db_temp_start "$dir" || return 1
        dump=("$dir/xamppfiles/mysql/bin/mariadb-dump" --no-defaults -S "$DB_TMP_SOCK" -uroot)
        query=("$dir/xamppfiles/mysql/bin/mariadb" --no-defaults -S "$DB_TMP_SOCK" -uroot -N)
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
    local part="$dest.parte" errors=$(mktemp) pid
    DB_PART=$part
    echo "Descargando..."
    # (solo para ti: lleva la base entera, aunque la carpeta de destino sea de todos)
    ( umask 077; set -o pipefail
      { "${dump[@]}" --default-character-set=utf8mb4 --single-transaction --quick \
            --routines --triggers --events --max-allowed-packet=1G "${skip[@]}" "$db" || exit 1
        # (las tablas del administrador de pruebas, aparte y sin sus filas; sin la linea del modo
        # sandbox de cada volcado: solo la del primero, que la carga sabe quitar)
        for i in "${!only[@]}"; do
            "${dump[@]}" --default-character-set=utf8mb4 --single-transaction --quick --triggers \
                --max-allowed-packet=1G --where="${wheres[$i]}" "$db" "${only[$i]}" | LC_ALL=C sed '/^\/\*M!999999\\-/d' || exit 1
        done
        [ -z "$mail_sql" ] || printf '%s\n' "$mail_sql"; } < /dev/null 2> "$errors" | "${out[@]}" > "$part" ) &
    pid=$!
    while kill -0 $pid 2> /dev/null; do
        sleep 2
        kill -0 $pid 2> /dev/null && echo "  $(human_size "$(stat -f %z "$part" 2> /dev/null || echo 0)") escritos"
    done
    if ! wait $pid; then
        cat "$errors"
        rm -f "$errors"
        echo "No se ha podido descargar la base de datos."

        return 1
    fi
    rm -f "$errors"
    mv -f "$part" "$dest"
    DB_PART=""
    echo "Copia guardada: $dest ($(du -h "$dest" | cut -f1))"
}

# importar-bd <fichero .sql, .sql.gz o .zip> <base> [--crear] [--copia]: carga el fichero en el
# MariaDB de la version activa. --crear crea la base si no existe. Si ya existe, siempre se vacia
# antes (se borra y se crea de nuevo con su juego de caracteres): asi no quedan tablas que el volcado
# ya no trae ni filas de una carga anterior que fallo a medias (los volcados de phpMyAdmin no llevan
# DROP TABLE y sus INSERT se suman a lo que haya). Si tiene tablas y se pide --copia, antes se guarda
# una copia suya en ~/nexum-backups (sin --copia, no se guarda y se dice). --sin-copia y --vaciar se
# admiten, pero ya no hacen falta.
# Las copias hechas con mariadb-dump moderno empiezan por "/*M!999999\- enable the sandbox mode */",
# que los clientes de MariaDB anteriores a 10.5.25 no entienden: esa primera linea se quita al
# vuelo, sin tocar el fichero.
# Avance: el fichero se abre como descriptor 3 del script y los programas que lo leen comparten su
# posicion, que se lee con lsof (fd_offset). Con LVM_PROGRESO (o $PROGRESS, en el panel) se escribe
# una linea S con modo lsof; en una terminal con pv se muestra la barra de pv.
function import_database() {
    local file=$1 db=$2 create=0 backup=0 told=0 saved="" project="" rc
    shift 2
    while [ $# -gt 0 ]; do
        case "$1" in
            --crear) create=1 ;;
            --vaciar) ;;
            --copia) backup=1 ;;
            # (copiar-bd: ya ha guardado la copia, o ya ha dicho que no la hay)
            --sin-copia) backup=0; told=1 ;;
            --proyecto) project=${2%/}; shift ;;
        esac
        shift
    done

    if [ -z "$file" ] || [ -z "$db" ]; then
        echo "Uso: lvm-instalador importar-bd <fichero.sql|.sql.gz|.zip> <base de datos> [--crear] [--copia] [--proyecto <carpeta>]"

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

    # (copiar-bd a una version que no es la activa: DB_CLIENT ya va a su MariaDB temporal)
    if [ -n "$DB_TARGET_FOLDER" ]; then
        DB_FOLDER=$DB_TARGET_FOLDER
        DB_VERSION=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT VERSION()" < /dev/null 2> /dev/null | cut -d- -f1)
        [ -n "$DB_VERSION" ] || { echo "No se puede entrar en el MariaDB de XAMPP-$DB_FOLDER"; return 1; }
    else
        db_connect
        rc=$?
        [ $rc -ne 0 ] && return $rc
    fi

    # --binary-mode: el cliente no ejecuta sus propios comandos que traiga el volcado (\! orden,
    # system, source, tee: con ellos un .sql manipulado ejecutaria programas en este Mac), solo SQL.
    # --local-infile=0: el volcado no puede leer ficheros del Mac (LOAD DATA LOCAL INFILE)
    local mysql=("${DB_SAFE[@]}" "$DB_CLIENT" -uroot --default-character-set=utf8mb4 --binary-mode --local-infile=0)
    local size=$(stat -f %z "$file") name=$(basename "$file")
    # (el nombre va en el fichero de progreso, separado por |)
    name=${name//[|$'\n'$'\r']/_}
    local progress=${LVM_PROGRESO:-$PROGRESS}

    echo "Fichero: $file ($(human_size "$size"))"
    [ $kind == zip ] && echo "Dentro del zip: $inner ($(human_size "$inner_size"), se descomprime al vuelo)"
    echo "Destino: base $db en XAMPP-$DB_FOLDER (MariaDB $DB_VERSION)"
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
            echo "La base $db no existe en XAMPP-$DB_FOLDER (con --crear se crea)"

            return 1
        fi
        echo "Creando la base de datos $db..."
        run "${mysql[@]}" -e "CREATE DATABASE \`$db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci" < /dev/null || return 1
    else
        # (ya existe: se vacia siempre, con copia antes si tiene tablas y se ha pedido)
        local tables
        tables=$("${mysql[@]}" -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$db'" < /dev/null)
        if ! [[ "$tables" =~ ^[0-9]+$ ]]; then
            echo "No se pueden ver las tablas de $db: no se ha cambiado nada."
            return 1
        fi
        if [ "$tables" -gt 0 ] && [ $backup -eq 1 ]; then
            saved="$COPIES_DIR/XAMPP-$DB_FOLDER-$db-antes-de-cargar-$(date +%Y%m%d-%H%M%S).sql.gz"
            echo "$db ya tiene $tables $([ "$tables" == 1 ] && echo tabla || echo tablas): se borran todas antes de cargar."
            echo "Antes se guarda una copia suya en $saved"
            local dump=${LVM_BD_VOLCADO:-$(dirname "$DB_CLIENT")/mysqldump}
            if [ "$DRY" -eq 1 ]; then
                echo "  [simulacion] mysqldump $db | gzip > $saved"
            else
                mkdir -p -m 700 "$COPIES_DIR"
                if ! ( set -o pipefail; "${DB_SAFE[@]}" "$dump" -uroot --default-character-set=utf8mb4 --single-transaction \
                    --routines --triggers --events "$db" < /dev/null | gzip > "$saved" ); then
                    rm -f "$saved"
                    echo "No se ha podido guardar la copia de $db, asi que no se ha cambiado nada."
                    return 1
                fi
                echo "Copia guardada: $saved ($(du -h "$saved" | cut -f1))"
            fi
        fi
        if [ "$tables" -gt 0 ] && [ $backup -eq 0 ] && [ $told -eq 0 ]; then
            echo "$db ya tiene $tables $([ "$tables" == 1 ] && echo tabla || echo tablas): se borran todas antes de cargar."
            echo "Sin copia: lo que tenia no se podra recuperar (con --copia se guarda antes en ~/nexum-backups)"
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

    # Lectura: descomprimir (gzip o zip), quitar la linea del modo sandbox (sed de macOS: el ;
    # antes de } es obligatorio) y los DEFINER de vistas, disparadores y rutinas (son de otro
    # usuario: con el temporal no se podrian crear)
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
        task_detail "cargando" lsof "$BASHPID:3" "$size" "$start"
    elif [ -n "$progress" ]; then
        { echo "I|1|1|Cargando $name en $db|$start"
          echo "S|1|0|100|cargando|lsof|$BASHPID:3|$size|$start"; } >> "$progress"
    fi
    echo "Cargando..."
    if [ -z "$progress" ] && [ -t 2 ] && command -v pv > /dev/null; then
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
    [ -n "$progress" ] && [ -z "$TASK_OWNER" ] && echo "R|bd:$db|$rc" >> "$progress"

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
    db_note_import "${DB_TARGET_DATA:-$LINK/xamppfiles/var/mysql}" "$db" "$(date +%s)"
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
    local f
    for f in "$1"/xamppfiles/var/mysql/*.err; do
        [ -f "$f" ] && [ ! -L "$f" ] && echo "$(stat -f %z "$f") $f"
    done | sort -rn | head -1 | cut -d' ' -f2-
}

# reparar-bd-sistema [--copia]: pone al dia las tablas del sistema de MariaDB de la version montada (con su
# propio mysql_upgrade, solo las del sistema: las bases de los proyectos no se tocan), despues de
# guardar (con --copia) una copia de la base mysql en ~/nexum-backups, y vacia su registro de errores si es grande
function repair_db_system() {
    local dir name upgrade dump log size backup="" out copy=0
    [ "$1" == "--copia" ] && copy=1
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
    if [ -x "$dir/xamppfiles/mysql/bin/mariadb-upgrade" ] && [ -x "$dir/xamppfiles/mysql/bin/mariadb-dump" ]; then
        upgrade=("$dir/xamppfiles/mysql/bin/mariadb-upgrade") dump=("$dir/xamppfiles/mysql/bin/mariadb-dump")
    else
        echo "$name no tiene mariadb-upgrade"
        return 1
    fi
    upgrade+=(--no-defaults -S "$dir/xamppfiles/var/mysql/mysql.sock" -uroot)
    dump+=(--no-defaults -S "$dir/xamppfiles/var/mysql/mysql.sock" -uroot)
    log=$(db_error_log "$dir")
    # mysql_upgrade escribe en la carpeta de datos (mysql_upgrade_info): se ejecuta con su dueño
    # (mysql, o tu usuario en el Mac), nunca como root. Con sudo -u, MYSQL_PWD no pasaria
    local owner as_owner=()
    owner=$(stat -f %Su "$dir/xamppfiles/var/mysql" 2> /dev/null)
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
        [ $copy -eq 1 ] && backup="$COPIES_DIR/$name-mysql-sistema-$(date +%Y%m%d-%H%M%S).sql.gz"
        [ $copy -eq 0 ] && echo "Sin copia: las tablas del sistema de ahora no se podran recuperar (con --copia se guardan antes)"
        if [ "$DRY" -eq 1 ]; then
            [ -n "$backup" ] && echo "  [simulacion] copia de la base mysql en $backup"
            echo "  [simulacion] ${upgrade[0]##*/} --upgrade-system-tables --force"
        else
            if [ -n "$backup" ]; then
                mkdir -p -m 700 "$COPIES_DIR" || return 1
                if ! ( set -o pipefail; umask 077; "${dump[@]}" --databases mysql < /dev/null | gzip > "$backup" ); then
                    rm -f "$backup"
                    echo "No se ha podido guardar la copia de la base mysql: no se cambia nada."
                    return 1
                fi
                echo "Copia de las tablas del sistema: $backup"
            fi
            if ! out=$("${as_owner[@]}" "${upgrade[@]}" --upgrade-system-tables --force < /dev/null 2>&1); then
                echo "$out" | tail -8 | sed 's/^/  /'
                echo "No se han podido poner al dia${backup:+ (la copia esta en $backup)}."
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
    if [ -n "$log" ] && [ -f "$log" ] && [ ! -L "$log" ] && [[ "$log" == "$dir"/xamppfiles/var/mysql/*.err ]]; then
        size=$(stat -f %z "$log")
        if [ "$size" -gt 104857600 ]; then
            echo "El registro de errores de MariaDB ($log) ocupa $((size / 1048576)) MB: se vacia."
            # (en el Mac el registro es tuyo: MariaDB corre con tu usuario; sin sudo, que vaciaria lo
            # que apuntara un enlace puesto ahi)
            if [ "$DRY" -eq 1 ]; then
                echo "  [simulacion] vaciar $log"
            elif ! : > "$log"; then
                echo "No se ha podido vaciar (no es tuyo): vacialo a mano con: sudo sh -c ': > \"$log\"'"
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

# Sin usuarios anonimos (sin nombre ni contraseña) ni permisos de cualquiera sobre las bases test y
# test_* (las versiones nuevas ya se crean asi)
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

# ---------------------------------------------------------------- panel de bases de datos

function ui_password() {
    if [ "$UI" == "whiptail" ]; then
        ui_size "$1"
        wt --title "$TITLE" --ok-button "Aceptar" --cancel-button "Volver" \
            --passwordbox "$1" $((H + 2)) $W 3>&1 1>&2 2>&3
    else
        local answer
        echo -e "\n$1" >&2
        read -r -s -p "> " answer >&2
        echo "" >&2
        echo "$answer"
    fi
}

# Comprueba que se puede entrar en el MariaDB activo; si root tiene contraseña la pide (MYSQL_PWD)
function panel_db_connect() {
    local check=$(gui_db_check) pwd retry=""

    while [[ "$check" == clave\|* ]]; do
        pwd=$(ui_password "${retry}El usuario root del MariaDB de XAMPP-${check#clave|} tiene contraseña.\nEscribela para continuar:") || return 1
        export MYSQL_PWD=$pwd
        check=$(gui_db_check)
        retry="Contraseña incorrecta. "
    done

    if [[ "$check" != ok\|* ]]; then
        ui_msg "${check#no|}"

        return 1
    fi
}

# Elige una base de la version activa: ui_pick_db "texto" [con_nueva]
function ui_pick_db() {
    local text=$1 with_new=$2 items=() db
    while IFS= read -r db; do
        [ -n "$db" ] && items+=("$db" "")
    done < <(db_list_active)
    [ -n "$with_new" ] && items+=("@nueva" "(crear una base nueva)")

    if [ ${#items[@]} -eq 0 ]; then
        ui_msg "La version activa no tiene bases de datos (aparte de las del sistema)."

        return 1
    fi

    ui_menu "$text" "" "${items[@]}"
}

# Fichero SQL: ventana de Finder para elegirlo (osascript) o, si no se puede, la ruta escrita
function ui_pick_sql() {
    local path
    path=$(osascript -e 'try' \
        -e 'POSIX path of (choose file with prompt "Elige la copia SQL (.sql, .sql.gz o .zip)" of type {"sql", "gz", "zip", "public.data"})' \
        -e 'end try' 2> /dev/null)
    if [ -z "$path" ]; then
        path=$(ui_input "Escribe la ruta del fichero .sql, .sql.gz o .zip (puedes arrastrarlo aqui desde Finder):" "") || return 1
        # Arrastrado desde Finder llega con comillas o con los espacios escapados (\ )
        path=${path% }; path=${path%\'}; path=${path#\'}; path=${path//\\ / }
    fi
    [ -n "$path" ] && echo "$path"
}

function ui_new_db_name() {
    local name err=""
    while true; do
        name=$(ui_input "${err}Nombre de la base de datos nueva (letras sin acentos, numeros, _ y -).\nSe crea vacia en utf8mb4 (utf8mb4_general_ci)." "") || return 1
        err=$(db_valid_name "$name")
        [ -z "$err" ] && db_exists "$name" && err="Ya hay una base de datos $name."
        [ -z "$err" ] && echo "$name" && return 0
        err="$err\n\n"
    done
}

# Pantalla de la barra al cargar una base (protocolo de whiptail --gauge) a partir de $PROGRESS
function db_progress_screen() {
    local info=$(grep '^I|' "$PROGRESS" | tail -1) step=$(grep '^S|' "$PROGRESS" | tail -1)
    [ -z "$step" ] && return 0
    local label started cur from to what mode file total t0
    IFS='|' read -r _ _ _ label started <<< "$info"
    IFS='|' read -r _ cur from to what mode file total t0 <<< "$step"

    local done=$(fd_offset "$file") pct=0
    (( total > 0 )) && pct=$(( done * 100 / total ))
    (( pct > 99 )) && pct=99
    grep -q '^R|' "$PROGRESS" && pct=100 && done=$total

    local elapsed=$(( $(date +%s) - started ))
    local text="$label\n\n$(human_size "$done") de $(human_size "$total")\n\nTiempo: $(fmt_minutes $elapsed)"
    if (( pct >= 5 && pct < 100 )); then
        local left=$(( elapsed * (100 - pct) / pct ))
        if (( left < 60 )); then text+="   Queda menos de 1 min"; else text+="   Quedan unos $(fmt_minutes $left)"; fi
    fi

    printf 'XXX\n%d\n%s\nXXX\n' "$pct" "$text"
}

function panel_db_import() {
    panel_db_connect || return 0

    local file db args=()
    file=$(ui_pick_sql) || return 0
    if [ ! -r "$file" ]; then
        ui_msg "No se puede leer el fichero:\n$file"

        return 0
    fi
    db=$(ui_pick_db "Elige la base de datos de XAMPP-$(version_name "$(active_dir)") donde cargar\n$(basename "$file") ($(human_size "$(stat -f %z "$file")"))" 1) || return 0
    if [ "$db" == "@nueva" ]; then
        db=$(ui_new_db_name) || return 0
        args+=(--crear)
    fi

    local text="Se va a cargar $(basename "$file") en la base $db de XAMPP-$(version_name "$(active_dir)").\n\n"
    if [ ${#args[@]} -gt 0 ]; then
        text+="Primero se crea la base $db (vacia)."
    else
        text+="Antes se BORRAN todas las tablas de $db, para que no quede nada de lo anterior."
    fi
    ui_yesno "$text\n\n¿Cargar?" || return 0
    # (solo si ya existe: sin copia, lo que tenga no se podra recuperar)
    if [ ${#args[@]} -eq 0 ] && ui_yesno "¿Guardar antes una copia de $db en ~/nexum-backups?\n\nSin copia, lo que tenga ahora no se podra recuperar."; then
        args+=(--copia)
    fi

    if [ "$UI" == "whiptail" ] && [ "$DRY" -eq 0 ]; then
        PROGRESS=$(mktemp /tmp/lvm-progreso-XXXX)
        local out=$PROGRESS.salida
        ( import_database "$file" "$db" "${args[@]}" > "$out" 2>&1 ) &
        local job=$!
        local rows=$(tput lines 2> /dev/null || echo 24)
        while true; do
            local finished=0
            kill -0 "$job" 2> /dev/null || finished=1
            db_progress_screen
            [ $finished -eq 1 ] && break
            sleep 1
        done | wt --title "$TITLE" --gauge "$(printf '%.0s \\n' 1 2 3 4 5 6)" 12 74 0
        wait "$job"
        local rc=$?
        ui_msg "$( [ $rc -eq 0 ] && echo "Base de datos $db cargada." || echo "No se ha podido cargar la base de datos.")\n\n$(tail -12 "$out" | fold -w 90)"
        rm -f "$PROGRESS" "$out"
        PROGRESS=""
    else
        [ "$UI" == "whiptail" ] && clear
        import_database "$file" "$db" "${args[@]}"
        [ -t 0 ] && [ "$NO_ASK" != "1" ] && read -p "Pulsa Intro para volver al panel... " _
    fi
}

function panel_db_create() {
    panel_db_connect || return 0
    local name
    name=$(ui_new_db_name) || return 0
    ui_msg "$(create_database "$name" 2>&1)"
}

function panel_db_drop() {
    panel_db_connect || return 0
    local db info tables bytes
    db=$(ui_pick_db "Elige la base de datos de XAMPP-$(version_name "$(active_dir)") que quieres BORRAR.") || return 0
    info=$(gui_db_info "$db" | grep '^I|')
    IFS='|' read -r _ tables bytes <<< "$info"

    local backup=0
    if [ "${tables:-0}" -gt 0 ]; then
        local text="¿Borrar la base de datos $db de XAMPP-$(version_name "$(active_dir)")?\n\n"
        text+="Tiene $tables $([ "$tables" == 1 ] && echo tabla || echo tablas) ($(human_size "$bytes")).\n\n"
        text+="ATENCION: se eliminara todo su contenido. Esta accion es IRREVERSIBLE: no se puede deshacer."
        ui_yesno "$text" || return 0

        local choice
        choice=$(ui_menu "Antes de borrar $db puedes guardar una copia en ~/nexum-backups (un .sql.gz que se puede volver a cargar)." \
            "copia" "copia" "Guardar una copia y despues borrar" "sin" "Borrar SIN copia") || return 0
        if [ "$choice" == "copia" ]; then
            backup=1
        else
            local typed
            typed=$(ui_input "Sin copia, el contenido de $db no se podra recuperar.\n\nEscribe $db para confirmar:" "") || return 0
            if [ "$typed" != "$db" ]; then
                ui_msg "No coincide. No se ha borrado nada."

                return 0
            fi
        fi
    else
        ui_yesno "¿Borrar la base de datos $db?\n\nEsta vacia (no tiene tablas). Esta accion no se puede deshacer." || return 0
    fi

    [ "$UI" == "whiptail" ] && clear
    if [ $backup -eq 1 ]; then
        drop_database "$db" --copia
    else
        drop_database "$db"
    fi
    [ -t 0 ] && [ "$NO_ASK" != "1" ] && read -p "Pulsa Intro para volver al panel... " _
}

# Version instalada que ya tiene una version exacta de PHP (vacio y 1 si ninguna)
function php_installed_in() {
    local dir
    for dir in $(version_dirs); do
        [ "$(stack_fields "$dir" | cut -d'|' -f1)" == "$1" ] && echo "$dir" && return 0
    done
    return 1
}

# Ultima version de PHP de la rama de una instalacion
function rebuild_version() {
    local dir=$1 releases=$2
    local php=$(stack_fields "$dir" | cut -d'|' -f1)

    awk -v b="${php%.*}" '$1 == b {print $2}' <<< "$releases"
}

# Vuelve a compilar una version con la ultima pila de su rama (parches nuevos)
function panel_rebuild() {
    local releases=$(php_releases) items=() dir version full f state

    if [ -z "$releases" ]; then
        ui_msg "No se pudo consultar php.net. Comprueba la conexion a internet."

        return 0
    fi

    [ "$UI" == "whiptail" ] && clear && echo "Consultando las ultimas versiones de cada componente..."
    for dir in $(version_dirs); do
        # (solo las XAMPP-X.Y de antes: las XAMPP-X.Y.Z llevan su version en el nombre)
        [[ "$(version_name "$dir")" =~ ^[0-9]+\.[0-9]+$ ]] || continue
        full=$(rebuild_version "$dir" "$releases")
        [ -z "$full" ] && continue

        local new=$(stack_versions "$full")
        if [ "$(stack_fields "$dir")" == "$new" ] && ! php2shell_missing "$dir" "$full"; then
            state="al dia"
        else
            state="actualizable"
        fi

        IFS='|' read -r -a f <<< "$new"
        items+=("$(version_name "$dir")" "$(fmt_row "$STACK_WIDTHS" "$(version_name "$dir")" "${f[@]}" "$state")")
    done

    if [ ${#items[@]} -eq 0 ]; then
        ui_msg "No hay versiones instaladas que se puedan actualizar."

        return 0
    fi

    local text="Elige la version que quieres actualizar. Se muestra la pila con la que quedara:\n"
    text+="la ultima de su rama de PHP. 'actualizable' = hay parches nuevos;\n"
    text+="'al dia' = ya tiene todos los paquetes en su ultima version."
    local new
    while true; do
        version=$(ui_table_menu "$text" "$version" "$(stack_header "Estado")" "${items[@]}") || return 0
        dir=$BASE_DIR/XAMPP-$version
        full=$(rebuild_version "$dir" "$releases")
        new=$(stack_versions "$full")

        # Con todos los paquetes al dia no hay nada que actualizar: se avisa y se vuelve a la lista
        if [ "$(stack_fields "$dir")" == "$new" ] && ! php2shell_missing "$dir" "$full"; then
            ui_up_to_date "XAMPP-$version"
            continue
        fi
        break
    done

    local old_mariadb=$(stack_fields "$dir" | cut -d'|' -f3) new_mariadb=$(cut -d'|' -f3 <<< "$new")
    IFS='|' read -r -a f <<< "$new"

    local header=$(stack_header "") ask_copy=0
    local summary="XAMPP-$version se volvera a compilar con la ultima pila de PHP ${full%.*}:\n\n"
    summary+="$header\n$(printf '%*s' ${#header} "" | tr ' ' '-')\n"
    summary+="$(stack_row "$dir" "" "Ahora")\n"
    summary+="$(fmt_row "$STACK_WIDTHS" "Despues" "${f[@]}" "")\n\n"

    if [ "${old_mariadb%.*}" == "${new_mariadb%.*}" ]; then
        summary+="Conserva sus bases de datos (misma rama de MariaDB, ${new_mariadb%.*}).\n"
    else
        local count=$(db_names "$dir" | grep -c .)
        summary+="MariaDB $new_mariadb no usa directamente los datos de MariaDB $old_mariadb, asi que\n"
        summary+="la nueva version empezara con bases de datos vacias (ahora tiene $count). Despues\n"
        summary+="se pregunta si guardar antes una copia en ~/nexum-backups/. Para llevarte alguna,\n"
        summary+="exportala antes desde phpMyAdmin e importala despues.\n"
        ask_copy=1
    fi

    summary+="\nLa compilacion tarda 20-40 minutos y mientras tanto la version actual sigue\n"
    summary+="como esta. Solo al final se sustituye"
    if [ "$(active_dir)" == "$dir" ]; then
        summary+=": como es la version activa, se parara\nunos segundos y se arrancara la nueva.\n"
    else
        summary+=".\n"
    fi
    summary+="Los proyectos y los vhosts de $COMMON no se tocan."
    [ "$DRY" -eq 1 ] && summary+="\n\nSIMULACION: no se hara ningun cambio."
    summary+="\n\n¿Actualizar XAMPP-$version?"

    check_space "$SPACE_STACK_GB" || return 0

    if other_install_running; then
        ui_msg "Hay otra instalacion en marcha. Espera a que termine."

        return 0
    fi

    ui_yesno "$summary" || return 0
    # (sin copia, las bases de ahora no se podran recuperar: la casilla, desmarcada de partida)
    if [ $ask_copy -eq 1 ] && ui_yesno "¿Guardar antes una copia de las bases de datos de XAMPP-$version en ~/nexum-backups?\n\nSin copia, no se podran recuperar."; then
        STACK_DB_COPY=1
    fi

    [ "$UI" == "whiptail" ] && clear
    install_plan "rehacer:$full"
}

# ui_up_to_date XAMPP-X.Y: aviso en verde de que la version ya tiene todos los paquetes al dia
function ui_up_to_date() {
    local message="El paquete $1 se encuentra actualizado."

    if [ "$UI" == "whiptail" ]; then
        WT_GREEN=$message ui_msg "$message\n\nTodos sus paquetes (PHP, Apache, MariaDB, ProFTPD, Perl y phpMyAdmin)\nestan en la ultima version de su rama: no hay nada que actualizar."
    elif [ -t 2 ]; then
        ui_msg "\033[1;32m$message\033[0m\n\nNo hay nada que actualizar."
    else
        ui_msg "$message\n\nNo hay nada que actualizar."
    fi
}

function panel_remove() {
    local items=() dir version active=$(active_dir)

    for dir in $(version_dirs); do
        local mark=""
        [ "$dir" == "$active" ] && mark="activa"
        items+=("$(version_name "$dir")" "$(stack_row "$dir" "$mark")")
    done

    if [ ${#items[@]} -eq 0 ]; then
        ui_msg "No hay versiones instaladas."

        return 0
    fi

    local text="Elige la version que quieres desinstalar.\n"
    text+="No se puede desinstalar la version activa."
    version=$(ui_table_menu "$text" "" "$(stack_header "Estado")" "${items[@]}") || return 0
    dir=$BASE_DIR/XAMPP-$version

    local blocker=$(remove_blocker "$version")
    if [ -n "$blocker" ]; then
        ui_msg "$blocker"

        return 0
    fi

    local fields
    IFS='|' read -r -a fields <<< "$(stack_fields "$dir")"

    local summary="Se va a desinstalar XAMPP-$version (PHP ${fields[0]}) y se borrara la carpeta $dir.\n\n"
    local names=$(db_names "$dir")
    local own_dbs=$(grep -c . <<< "$names")

    if [ "$own_dbs" -gt 0 ]; then
        summary+="ATENCION: sus bases de datos ($own_dbs) se BORRARAN con ella:\n\n"
        summary+="$(columns 66 <<< "$names")\n\n"
        summary+="Antes de borrar podras guardar una copia de todas ellas.\n"
    else
        summary+="No tiene bases de datos propias (aparte de las del sistema).\n"
    fi

    summary+="\nLos proyectos y los vhosts de $COMMON no se tocan."
    [ "$DRY" -eq 1 ] && summary+="\n\nSIMULACION: no se hara ningun cambio."
    summary+="\n\n¿Desinstalar XAMPP-$version?"

    ui_yesno "$summary" || return 0

    local backup=0
    if [ "$own_dbs" -gt 0 ]; then
        ui_yesno "¿Guardar antes una copia comprimida de las bases de datos de XAMPP-$version?\n\nSe guardara en ~/nexum-backups/ (se necesita espacio libre en tu carpeta personal)." && backup=1

        # Sin copia, se pide escribir el nombre de la version para confirmar
        if [ $backup -eq 0 ]; then
            local typed
            typed=$(ui_input "Se borraran sus bases de datos ($own_dbs) SIN copia y no se podran recuperar.\n\nEscribe $version para confirmar:" "") || return 0
            if [ "$typed" != "$version" ]; then
                ui_msg "No coincide. No se ha desinstalado nada."

                return 0
            fi
        fi
    fi

    [ "$UI" == "whiptail" ] && clear

    if [ "$DRY" -eq 0 ] && [ -n "$SUDO" ]; then
        echo "Se necesita la contraseña de administrador (sudo):"
        sudo -v || return 0
    fi

    local ok=1
    if [ $backup -eq 1 ]; then
        local home_dir=$(eval echo "~${SUDO_USER:-$USER}")
        local size_kb=0
        [ "$DRY" -eq 0 ] && size_kb=$($SUDO du -sk "$dir/xamppfiles/var/mysql" 2> /dev/null | cut -f1)
        local free_kb=$(df -k "$home_dir" | awk 'NR == 2 {print $4}')

        if [ -n "$size_kb" ] && [ "$free_kb" -lt "$size_kb" ]; then
            echo "No hay espacio para la copia: ocupan $((size_kb / 1024)) MB y hay $((free_kb / 1024)) MB libres en $home_dir."
            ok=0
        else
            backup_databases "$version" || ok=0
        fi

        [ $ok -eq 0 ] && echo "No se ha podido guardar la copia, asi que NO se desinstala nada."
    fi

    [ $ok -eq 1 ] && remove_version "$version"

    [ -t 0 ] && [ "$NO_ASK" != "1" ] && read -p "Pulsa Intro para volver al panel... " _
}

