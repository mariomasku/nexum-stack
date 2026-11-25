# ===========================================================================
# Administrador de pruebas de los paneles (WordPress y PrestaShop)
# ===========================================================================
#@incluir comun/administrador-pruebas-paneles/test_admin.sh

# Cliente de MariaDB como root para el administrador de pruebas (test_admin, wp_table_prefixes y
# ps_table_prefix): el de XAMPP-X (DB_CLIENT) o, si DB_ROOT_CLIENT (un array) tiene algo, ese. Asi
# test_admin sirve tambien para la BBDD de un contenedor de Docker (docker_test_admin)
DB_ROOT_CLIENT=()
function db_root_sql() {
    if [ ${#DB_ROOT_CLIENT[@]} -gt 0 ]; then
        "${DB_ROOT_CLIENT[@]}" "$@"
    else
        "${DB_SAFE[@]}" "$DB_CLIENT" -uroot "$@"
    fi
}

#@incluir comun/administrador-pruebas-paneles/wp_table_prefixes.sh
function databases_text() {
    local version=$1 width=${2:-72}
    local names=$(db_names "$BASE_DIR/XAMPP-$version")
    local count=$(grep -c . <<< "$names")

    local text="XAMPP-$version: bases de datos propias\n"
    text+="\nBases de datos: $count (sin contar las del sistema)\n\n"
    text+="$(columns "$width" <<< "$names")\n"

    echo "$text"
}

function list_databases() {
    local dir

    for dir in $(version_dirs); do
        echo -e "$(databases_text "$(version_name "$dir")" "$(tput cols 2> /dev/null || echo 80)")"
        echo ""
    done
}

function disable_version() {
    if official_xampp; then
        echo "$LINK es un XAMPP oficial y no un enlace. No se puede ejecutar esta accion."

        return 1
    fi

    if [ -L "$LINK" ]; then
        run xampp_ctl stop
        run $SUDO rm "$LINK"
    fi
    # Sin version montada no queda ningun proceso de XAMPP en memoria (ni Mailpit)
    close_processes --todos
    mailpit_sync
}

# Lo que trae de serie el htdocs de un XAMPP oficial: no se copia a la carpeta compartida
OFFICIAL_DEFAULTS="applications.html|bitnami.css|dashboard|favicon.ico|img|index.php|webalizer|xampp|.DS_Store"

# ¿Sigue en marcha algun programa del XAMPP oficial? (con sudo: sin el, macOS no deja ver la orden
# completa de los procesos de otros usuarios, como MariaDB)
function official_running() {
    $SUDO pgrep -f "$LINK/xamppfiles/" > /dev/null 2>&1
}

# Para el XAMPP oficial y espera a que no quede nada en marcha (hasta 30 s)
function official_stop() {
    if [ -x "$LINK/xamppfiles/xampp" ]; then
        echo "Parando el XAMPP oficial..."
        if [ -z "$SUDO" ]; then
            xampp_ctl stop 2>&1 | sed 's/^/  /'
        else
            # Su script no se ejecuta como root (ver xampp_ctl): se cierran sus programas, que con
            # TERM terminan bien (tambien MariaDB). Solo los servidores de XAMPP, no cualquier proceso
            # que lleve la ruta en su orden (un editor, un tail)
            local p
            for p in $(kill_pids $($SUDO pgrep -f "$LINK/xamppfiles/" 2> /dev/null)); do
                case "$(basename "$($SUDO ps -o comm= -p "$p" 2> /dev/null)")" in
                    httpd|mysqld|mariadbd|proftpd|php-fpm) $SUDO kill -TERM "$p" 2> /dev/null ;;
                esac
            done
        fi
    fi
    local i
    for i in $(seq 30); do
        official_running || return 0
        sleep 1
    done
    echo "El XAMPP oficial sigue en marcha despues de pararlo:"
    $SUDO pgrep -lf "$LINK/xamppfiles/" 2> /dev/null | sed 's/^/  /'
    echo "No se mueve nada. Cierra su panel (manager-osx), paralo desde ahi y vuelve a intentarlo."

    return 1
}

# Descarga todas las bases del XAMPP oficial (ya parado) en <carpeta>/<base>.zip con un MariaDB
# temporal suyo: sin red, con un socket propio y sin comprobar usuarios (asi da igual que root
# tenga contraseña). Si alguna falla, devuelve error y no se aparta nada
function official_dump_all() {
    local dest=$1 root=$LINK/xamppfiles data=$LINK/xamppfiles/var/mysql server="" client="" dumper="" user b
    if [ ! -d "$data" ]; then
        echo "El XAMPP oficial no tiene bases de datos ($data no existe)."

        return 0
    fi
    for b in sbin/mariadbd sbin/mysqld bin/mariadbd bin/mysqld; do [ -x "$root/$b" ] && { server=$root/$b; break; }; done
    for b in bin/mariadb bin/mysql; do [ -x "$root/$b" ] && { client=$root/$b; break; }; done
    for b in bin/mariadb-dump bin/mysqldump; do [ -x "$root/$b" ] && { dumper=$root/$b; break; }; done
    if [ -z "$server" ] || [ -z "$client" ] || [ -z "$dumper" ]; then
        echo "No se encuentran el servidor o los clientes de MariaDB del XAMPP oficial en $root."

        return 1
    fi
    # El servidor, el cliente y mysqldump son del XAMPP oficial, que no ha comprobado nadie (en
    # /Applications escribe el grupo admin): nunca como root, sino con el dueño de sus datos (-L: el
    # de verdad si var/mysql es un enlace). Si son de root, no se copian
    user=$($SUDO stat -L -f %Su "$data") || return 1
    [ -n "$TEST_DIR" ] && user=$(id -un)
    if [ "$user" == "root" ] || ! [[ "$user" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]]; then
        echo "Las bases del XAMPP oficial son de $user: no se arranca su MariaDB con ese usuario."
        echo "Copialas desde su phpMyAdmin (Exportar), o dale los datos a su usuario de MariaDB"
        echo "(sudo chown -R _mysql \"$data\") y vuelve a intentarlo."

        return 1
    fi
    local as_owner=(${SUDO:+$SUDO -u "$user"})
    local defaults=(--no-defaults --basedir="$root")
    [ -f "$root/etc/my.cnf" ] && defaults=(--defaults-file="$root/etc/my.cnf")

    # La carpeta la crea root y solo es del usuario del servidor: no pide contraseña mientras dura
    # la copia (otros usuarios del Mac no pueden llegar a su socket)
    DB_TMP=$($SUDO mktemp -d /tmp/lvm-mysql-XXXX) || { DB_TMP=""; return 1; }
    DB_TMP_SOCK=$DB_TMP/mysql.sock
    $SUDO chown "$user" "$DB_TMP" && $SUDO chmod 700 "$DB_TMP" || return 1
    echo "Arrancando el MariaDB del XAMPP oficial solo para copiar sus bases (sin red)..."
    "${as_owner[@]}" "$server" "${defaults[@]}" --datadir="$data" --skip-networking --skip-grant-tables \
        --socket="$DB_TMP_SOCK" --pid-file="$DB_TMP/mysql.pid" --log-error="$DB_TMP/mysql.log" \
        < /dev/null > /dev/null 2>&1 &
    local server_pid=$! i
    DB_TMP_PID=$server_pid
    for i in $(seq 300); do
        $SUDO test -S "$DB_TMP_SOCK" && break
        # (sin kill -0: el pid es el del sudo, que es de root, y kill -0 a un proceso de root da
        # «no permitido» aunque siga vivo)
        /bin/ps -p "$server_pid" > /dev/null 2>&1 || break
        sleep 0.2
    done
    if ! $SUDO test -S "$DB_TMP_SOCK"; then
        echo "No ha arrancado. Ultimas lineas de su registro:"
        # (lo lee el dueño de los datos, no root)
        $SUDO ${SUDO:+-u "$user"} /usr/bin/tail -15 "$DB_TMP/mysql.log" 2> /dev/null | sed 's/^/  /'
        db_temp_stop

        return 1
    fi

    local dbs db n=0 errors=$(mktemp) routines odd
    dbs=$("${as_owner[@]}" "$client" --no-defaults -S "$DB_TMP_SOCK" -uroot -N -e 'SHOW DATABASES' < /dev/null) || { db_temp_stop; return 1; }
    dbs=$(grep -vxE "$DB_SYSTEM" <<< "$dbs")
    # Solo nombres que se pueden usar como fichero y en las ordenes (sin /, espacios ni - delante)
    odd=$(grep -vE '^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$' <<< "$dbs" | grep .)
    dbs=$(grep -E '^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$' <<< "$dbs")
    echo "Bases de datos: $(grep -c . <<< "$dbs")"
    if [ -n "$odd" ]; then
        echo "Estas tienen un nombre que no se puede copiar asi (copialas desde su phpMyAdmin):"
        sed 's/^/  /' <<< "$odd"
    fi
    for db in $dbs; do
        routines=--routines
        while :; do
            if ( set -o pipefail; "${as_owner[@]}" "$dumper" --no-defaults -S "$DB_TMP_SOCK" -uroot --default-character-set=utf8mb4 \
                --single-transaction --quick $routines --triggers --max-allowed-packet=1G "$db" < /dev/null 2> "$errors" \
                | python3 -I -c "$ZIP_WRITE_PY" "$db.sql" > "$dest/$db.zip" ); then
                echo "  $db ($(du -h "$dest/$db.zip" | cut -f1))"
                n=$((n + 1))
                break
            fi
            rm -f "$dest/$db.zip"
            # Datos de un MariaDB anterior sin actualizar (mysql.proc con columnas de menos): sin rutinas
            if [ -n "$routines" ] && grep -q "mysql.proc" "$errors"; then
                routines=""
                echo "  $db: sin funciones ni procedimientos (mysql.proc es de un MariaDB anterior)"
                continue
            fi
            echo "  $db: no se ha podido copiar:"
            sed 's/^/    /' "$errors"
            rm -f "$errors"
            db_temp_stop

            return 1
        done
    done
    rm -f "$errors"
    db_temp_stop
    echo "$n bases copiadas en $dest"
}

# Copia los proyectos del htdocs del XAMPP oficial a la carpeta compartida (sin borrar los
# originales; en APFS, con cp -c, la copia es instantanea y no ocupa espacio hasta que cambian).
# Si ya hay algo con ese nombre en la carpeta compartida, no se toca y se avisa
function official_copy_projects() {
    local src=$LINK/xamppfiles/htdocs dst=$COMMON/htdocs entry name copied=0 skipped=()
    local user=${SUDO_USER:-$USER}
    local group=$(id -gn "$user")
    [ -d "$src" ] || { echo "El XAMPP oficial no tiene carpeta htdocs."; return 0; }
    if [ ! -d "$dst" ]; then
        $SUDO mkdir -p "$dst" && $SUDO chown "$user:$group" "$dst" || return 1
    fi
    echo "Copiando los proyectos de $src a $dst..."
    # Root copia en una carpeta suya de /tmp (el mismo volumen de datos que /Applications: mover es
    # al momento) y no dentro de htdocs, que es tuya: alli, un programa con tu usuario podria cambiar
    # el destino por un enlace a una carpeta del sistema justo antes de la copia. Lo copiado se pasa a
    # tu usuario ahi dentro y lo mueve a htdocs tu usuario (sin permisos de root)
    local stage as_user=() left=0
    [ "$(id -u)" == 0 ] && as_user=(sudo -u "$user")
    # (con rutas: el sudo de macOS no trae secure_path)
    stage=$($SUDO mktemp -d /tmp/lvm-copia.XXXXXX) && $SUDO chmod 700 "$stage" || return 1
    for entry in "$src"/* "$src"/.[!.]*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        name=$(basename "$entry")
        [[ "$name" =~ ^($OFFICIAL_DEFAULTS)$ ]] && continue
        if [ -e "$dst/$name" ] || [ -L "$dst/$name" ]; then
            skipped+=("$name")
            continue
        fi
        $SUDO cp -Rpc "$entry" "$stage/" 2> /dev/null || $SUDO cp -Rp "$entry" "$stage/" || {
            echo "No se ha podido copiar $name."
            $SUDO rm -rf "$stage"

            return 1
        }
        # macOS no protege los enlaces duros: uno de htdocs a un fichero de root que tu no puedes
        # leer quedaria copiado y tuyo. Se mira en la copia (cp -p deja su dueño y sus permisos): lo
        # que no es tuyo ni lo puede leer cualquiera no se pasa a tu usuario, se quita
        local rel
        while IFS= read -r -d '' rel; do
            $SUDO rm -f "$rel"
            echo "  No se copia ${rel#"$stage"/}: no es tuyo ni lo puede leer cualquiera"
        done < <($SUDO find "$stage/$name" ! -type d ! -type l ! -user "$user" ! -perm -004 -print0 2> /dev/null)
        $SUDO chown -Rh "$user:$group" "$stage/$name"
        copied=$((copied + 1))
    done
    # La carpeta pasa a tu usuario (ya no queda nada que hacer como root) y tu usuario lo mueve
    $SUDO chown "$user:$group" "$stage" || { $SUDO rm -rf "$stage"; return 1; }
    for entry in "$stage"/* "$stage"/.[!.]*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        name=$(basename "$entry")
        if [ -e "$dst/$name" ] || [ -L "$dst/$name" ] || ! "${as_user[@]}" /bin/mv "$entry" "$dst/$name"; then
            echo "  No se ha podido mover $name a $dst (queda en $stage)"
            left=1
        fi
    done
    [ $left -eq 0 ] && "${as_user[@]}" /bin/rmdir "$stage" 2> /dev/null
    echo "  $copied copiados"
    if [ ${#skipped[@]} -gt 0 ]; then
        echo "  Ya existian en la carpeta compartida y no se han tocado: ${skipped[*]}"
        echo "  (los originales siguen en el XAMPP oficial apartado, en xamppfiles/htdocs)"
    fi
}

# Añade los vhosts del XAMPP oficial al fichero compartido y comprueba la configuracion de Apache
# con una version instalada. Si no es valida, deja el fichero como estaba y avisa (no impide apartar)
function official_copy_vhosts() {
    local backup=$1 src=$LINK/xamppfiles/etc/extra/httpd-vhosts.conf s="" dir check=""
    [ -f "$src" ] || return 0
    cp "$src" "$backup/httpd-vhosts-del-xampp-oficial.conf"
    if ! grep -qvE '^[[:space:]]*(#|$)' "$src"; then
        echo "Sus vhosts estan todos comentados: no hay nada que copiar."

        return 0
    fi
    if [ ! -f "$VHOSTS_FILE" ]; then
        echo "No existe $VHOSTS_FILE: sus vhosts no se copian (estan en $backup)."

        return 0
    fi
    # Se lee una sola vez: lo que se comprueba es lo que se escribe (y lo de antes, para dejarlo como
    # estaba, tambien de aqui y no de la copia de tu carpeta, que podria cambiar otro programa)
    local content before
    content=$(sed -E "$OLD_LOGS_SED" "$src") && before=$(cat "$VHOSTS_FILE") || return 1
    # Solo directivas de vhosts (Apache arranca como root: nada de ordenes, modulos ni Include)
    if ! python3 -I -c "$VHOSTS_CHECK_PY" /dev/stdin "$VHOSTS_FILE" <<< "$content" > /dev/null; then
        echo "Sus vhosts llevan directivas que cambiarian todo Apache: no se copian. Estan en"
        echo "$backup/httpd-vhosts-del-xampp-oficial.conf: copia a mano los que necesites con Editar vhosts."

        return 0
    fi
    [ -w "$VHOSTS_FILE" ] || s=$SUDO
    if [ -n "$s" ] && ! vhosts_path_ok; then
        echo "No se copian sus vhosts: $VHOSTS_FILE tiene que ser un fichero normal de $COMMON (sin enlaces)."
        echo "Estan en $backup/httpd-vhosts-del-xampp-oficial.conf."
        return 0
    fi
    printf '%s\n' "$before" > "$backup/httpd-vhosts-compartido-antes.conf"
    echo "Añadiendo sus vhosts a $VHOSTS_FILE..."
    { printf '\n# ---- Copiado del XAMPP oficial el %s ----\n' "$(date '+%d/%m/%Y %H:%M')"
      printf '%s\n' "$content"
      printf '\n# ---- Fin de lo copiado del XAMPP oficial ----\n'; } | $s tee -a "$VHOSTS_FILE" > /dev/null || return 1
    # (con el httpd de una version de root: lo ejecuta root)
    for dir in $(version_dirs); do
        [ -x "$dir/xamppfiles/apache2/bin/httpd" ] || continue
        [ -z "$SUDO" ] || [ -n "$TEST_DIR" ] || trusted_version_dir "$dir" || continue
        check=$($SUDO "$dir/xamppfiles/apache2/bin/httpd" -t -f "$dir/xamppfiles/etc/httpd.conf" 2>&1) && return 0
        break
    done
    [ -z "$check" ] && return 0
    printf '%s\n' "$before" | $s tee "$VHOSTS_FILE" > /dev/null
    echo "Aviso: con sus vhosts, Apache no arrancaria:"
    sed 's/^/  /' <<< "$check" | head -8
    echo "Se ha dejado $VHOSTS_FILE como estaba. Sus vhosts estan en"
    echo "$backup/httpd-vhosts-del-xampp-oficial.conf: copialos a mano con Editar vhosts."
}

# Aparta un XAMPP oficial de /Applications/XAMPP para poder usar el enlace, sin borrar nada:
#   1. lo para y comprueba que no queda nada en marcha (si no, no se mueve nada)
#   2. copia todas sus bases (.zip) en ~/nexum-backups/xampp-oficial/XAMPP-oficial-<fecha>
#   3. copia sus proyectos a XAMPP-compartido/htdocs y sus vhosts al fichero compartido
#   4. mueve la carpeta a /Applications/XAMPP-oficial-<fecha> (volver-oficial la devuelve)
function set_aside_official() {
    official_xampp || { echo "No hay ningun XAMPP oficial en $LINK."; return 0; }
    local stamp=$(date +%Y%m%d-%H%M%S)
    local aside="$APPS_DIR/XAMPP-oficial-$stamp" user=${SUDO_USER:-$USER} home=$HOME
    [ -n "$SUDO_USER" ] && home=$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2> /dev/null | awk '{ print $2 }')
    local backup="$home/${COPIES_DIR##*/}/xampp-oficial/XAMPP-oficial-$stamp"

    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] parar el XAMPP oficial y comprobar que no queda nada en marcha"
        echo "  [simulacion] copiar sus bases de datos (.zip) en $backup"
        echo "  [simulacion] copiar sus proyectos a $COMMON/htdocs y sus vhosts a $VHOSTS_FILE"
        echo "  [simulacion] mover $LINK a $aside"

        return 0
    fi

    trap db_cleanup EXIT
    trap 'exit 130' INT TERM HUP
    official_stop || return 1
    copies_in xampp-oficial "$home/${COPIES_DIR##*/}" > /dev/null && mkdir -p "$backup" || return 1
    # Si algo falla, la carpeta de copias queda como incompleta-… (la ventana no la ofrece para cargar)
    local failed="No se ha apartado nada: el XAMPP oficial sigue en $LINK."
    official_dump_all "$backup" || { mv "$backup" "$home/${COPIES_DIR##*/}/xampp-oficial/incompleta-XAMPP-oficial-$stamp"; echo "$failed"; return 1; }
    if official_running; then
        mv "$backup" "$home/${COPIES_DIR##*/}/xampp-oficial/incompleta-XAMPP-oficial-$stamp"
        echo "El XAMPP oficial se ha vuelto a arrancar: no se mueve nada."

        return 1
    fi
    official_copy_projects || { mv "$backup" "$home/${COPIES_DIR##*/}/xampp-oficial/incompleta-XAMPP-oficial-$stamp"; echo "$failed"; return 1; }
    official_copy_vhosts "$backup"
    printf 'carpeta=%s\nfecha=%s\n' "$aside" "$stamp" > "$backup/xampp-oficial.txt"
    # Solo si esto corre como root (con tu usuario, todo lo de la carpeta ya es tuyo), y solo lo que
    # ha creado root: un enlace duro que pusiera ahi otro programa (macOS no los protege) a un
    # fichero del sistema no pasa a tu usuario
    [ "$(id -u)" == 0 ] && find "$backup" -user 0 \( -type d -o -type f -links 1 \) -exec chown -h "$user" {} + 2> /dev/null

    $SUDO mv "$LINK" "$aside" || return 1
    echo ""
    echo "Hecho. No se ha borrado nada:"
    echo "  - El XAMPP oficial esta ahora en $aside (con todo lo suyo)."
    echo "  - Copia de sus bases de datos: $backup"
    echo "  - Sus proyectos estan tambien en $COMMON/htdocs."
    echo "Ahora activa una version y, en Configuración de la ventana, carga las bases del XAMPP oficial."
    echo "Para deshacerlo: nexum volver-oficial."
}

# importar-copias <carpeta>: carga en la version activa las bases .zip de una carpeta (las del XAMPP
# oficial apartado). Las que ya existen en la version activa no se tocan
function import_backups() {
    local folder=$1 f db rc loaded=0 skipped=() failed=()
    if [ -z "$folder" ] || [ ! -d "$folder" ]; then
        echo "Uso: nexum importar-copias <carpeta con copias .zip>"

        return 1
    fi
    db_connect
    rc=$?
    [ $rc -ne 0 ] && return $rc
    for f in "$folder"/*.zip; do
        [ -f "$f" ] || continue
        db=$(basename "$f" .zip)
        if ! db_valid_name "$db" > /dev/null; then
            failed+=("$db (nombre no valido: cargala a mano con otro nombre)")
            continue
        fi
        if db_exists "$db"; then
            skipped+=("$db")
            continue
        fi
        echo ""
        echo "== $db"
        if ( import_database "$f" "$db" --crear ); then
            loaded=$((loaded + 1))
        else
            failed+=("$db")
        fi
    done
    echo ""
    echo "Cargadas en XAMPP-$DB_FOLDER: $loaded"
    [ ${#skipped[@]} -gt 0 ] && echo "Ya existian y no se han tocado: ${skipped[*]}"
    if [ ${#failed[@]} -gt 0 ]; then
        echo "No se han podido cargar: ${failed[*]}"

        return 1
    fi
    return 0
}

# volver-oficial [carpeta]: deshace el apartado. Para y desactiva la version activa del gestor, y
# devuelve el XAMPP oficial apartado (el mas reciente si no se indica) a /Applications/XAMPP y lo
# arranca. Las versiones del gestor, sus bases y las copias no se tocan
function restore_official() {
    local aside=$1
    [ -z "$aside" ] && aside=$(ls -d "$APPS_DIR"/XAMPP-oficial-* 2> /dev/null | sort | tail -1)
    if [ -z "$aside" ] || [ ! -d "$aside" ] || [[ "$(basename "$aside")" != XAMPP-oficial-* ]]; then
        echo "No hay ningun XAMPP oficial apartado en $APPS_DIR."

        return 1
    fi
    if official_xampp; then
        echo "Ya hay un XAMPP oficial en $LINK: no se puede devolver $aside."

        return 1
    fi
    if [ -L "$LINK" ]; then
        echo "Parando y desactivando $(basename "$(readlink "$LINK")")..."
        run xampp_ctl stop
        run $SUDO rm "$LINK" || return 1
    fi
    run $SUDO mv "$aside" "$LINK" || return 1
    echo "El XAMPP oficial vuelve a estar en $LINK. Arrancalo desde su panel (manager-osx): el gestor"
    echo "no ejecuta su script como administrador."
}

# Motivo por el que no se puede desinstalar una version (vacio si se puede)
function remove_blocker() {
    local version=$1
    local dir=$BASE_DIR/XAMPP-$version

    if [ -z "$version" ] || [[ "$version" == */* ]] || [ ! -d "$dir" ] || [ -L "$dir" ] || [ ! -f "$dir/xamppfiles/etc/pvm-stack" ]; then
        echo "No existe la version $version."
    elif [ "$(active_dir)" == "$dir" ]; then
        echo "XAMPP-$version es la version activa. Cambia antes a otra version (o desactivala) y vuelve a intentarlo."
    elif [ -e "$dir/xamppfiles/htdocs" ] && [ ! -L "$dir/xamppfiles/htdocs" ]; then
        # htdocs deberia ser un enlace a la carpeta compartida; si es real puede tener proyectos
        echo "XAMPP-$version tiene una carpeta htdocs propia (no es un enlace a $COMMON/htdocs) y podria contener proyectos.\nRevisala y muevela a mano antes de desinstalar."
    fi
}

# Copia comprimida de las bases de datos de una version (sin la version en marcha)
function backup_databases() {
    local version=$1 dir=${2:-$BASE_DIR/XAMPP-$1}
    local user=${SUDO_USER:-$USER}
    local copies=$(dscl . -read "/Users/$user" NFSHomeDirectory 2> /dev/null | awk '{ print $2 }')/${COPIES_DIR##*/}
    local dest_dir=$copies/bbdd/XAMPP-$version
    local dest="$dest_dir/todas-las-bases-$(date +%Y%m%d-%H%M%S).tar.gz"

    echo "Guardando copia de las bases de datos en $dest..."
    copies_in "bbdd/XAMPP-$version" "$copies" > /dev/null || return 1
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] tar -czf $dest -C $dir/xamppfiles/var mysql"

        return 0
    fi

    # Las bases las lee su dueño (en el Mac, tu usuario, con el que corre MariaDB), no root: macOS no
    # protege los enlaces duros, y uno de var/mysql a un fichero de root (una clave) acabaria dentro
    # de la copia. Solo si son de root las lee root. El fichero lo crea tu usuario (solo para ti)
    local owner reader=($SUDO tar)
    owner=$(stat -f %Su "$dir/xamppfiles/var/mysql" 2> /dev/null)
    if [ -n "$owner" ] && [ "$owner" != root ]; then
        reader=(tar)
        [ "$owner" != "$(id -un)" ] && reader=(sudo -u "$owner" /usr/bin/tar)
    fi
    if [ "$(id -u)" -eq 0 ] && [ "$user" != root ]; then
        "${reader[@]}" -czf - -C "$dir/xamppfiles/var" mysql | sudo -u "$user" /bin/sh -c 'umask 077; cat > "$1"' sh "$dest.parte" \
            || { rm -f "$dest.parte"; return 1; }
    else
        ( umask 077; "${reader[@]}" -czf - -C "$dir/xamppfiles/var" mysql > "$dest.parte" ) || { rm -f "$dest.parte"; return 1; }
    fi
    mv -f "$dest.parte" "$dest" || return 1
    echo "Copia guardada: $dest ($(du -h "$dest" | cut -f1))"
}

function remove_version() {
    local version=$1
    local blocker=$(remove_blocker "$version")

    if [ -n "$blocker" ]; then
        echo -e "$blocker"

        return 1
    fi

    # htdocs y vhosts son enlaces: rm no los sigue
    run $SUDO rm -R "$BASE_DIR/XAMPP-$version" || return 1
    # (y el enlace que dejo migrar en /Applications, si llevaba a ella)
    if [ -z "$TEST_DIR" ] && [ -L "$LEGACY_DIR/XAMPP-$version" ] \
            && [ "$(readlink "$LEGACY_DIR/XAMPP-$version")" == "$BASE_DIR/XAMPP-$version" ]; then
        run $SUDO rm "$LEGACY_DIR/XAMPP-$version"
    fi

    if [ "$DRY" -eq 1 ]; then
        echo "SIMULACION: no se ha borrado nada"
    else
        echo "XAMPP-$version desinstalada"
    fi
}

