# ===========================================================================
# BBDD de XAMPP-X en Docker (en vivo)
# ===========================================================================
# Un WordPress de Docker puede usar la BBDD de una version XAMPP-X en vivo: la misma que web.local, sin
# copias. Su MariaDB (si no esta en marcha, solo ella, con tu usuario y en otro puerto de 127.0.0.1: no
# choca con la de la version activa en el 3306) y, en la red de Docker, un puente hasta su puerto en el
# Mac (socat, de la imagen de MariaDB, por host.docker.internal: Docker Desktop no llega a los sockets
# del Mac). Si cambia el puerto (al activar esa version, pasa al 3306), se rehace el puente: la
# configuracion del proyecto no cambia. El proyecto entra con el usuario y la contraseña de su
# wp-config.php, los mismos que con web.local. PrestaShop no: guarda su dominio en la BBDD
LAMPP_BD_BRIDGE_IMAGE=mariadb:11.8
LAMPP_BD_MARK_DIR=$DOCKER_DIR/lampp-bd
LAMPP_BD_PORTS="3310 3399"

# (cada version tiene sus BBDD)
function lampp_bd_owner() {
    echo "$1"
}

function lampp_bd_xdir() {
    echo "$BASE_DIR/XAMPP-$1/xamppfiles"
}

function lampp_bd_data() {
    echo "$(lampp_bd_xdir "$1")/var/mysql"
}

function lampp_bd_bridge() {
    echo "nexum-lampp-bd-${1//./-}"
}

# ¿Responde la MariaDB de esa version en su socket?
function lampp_bd_alive() {
    db_socket_alive "$(lampp_bd_data "$1")/mysql.sock"
}

# Su puerto: el apuntado si la arranco Docker; si no, el de siempre
function lampp_bd_port() {
    local p
    p=$(head -c 10 "$LAMPP_BD_MARK_DIR/$1" 2> /dev/null | tr -d ' \n')
    [[ "$p" =~ ^[0-9]{4,5}$ ]] && echo "$p" || echo "$PORT_MYSQL"
}

# Un puerto libre para la MariaDB de una version que arranca Docker (ni de otra apuntada ni ocupado)
function lampp_bd_free_port() {
    local p used
    used=$(cat "$LAMPP_BD_MARK_DIR"/* 2> /dev/null; netstat -an -p tcp 2> /dev/null | awk '$NF == "LISTEN" { n = split($4, a, "."); print a[n] }')
    for p in $(seq $LAMPP_BD_PORTS); do
        grep -qx "$p" <<< "$used" || { echo "$p"; return 0; }
    done
    return 1
}

# La MariaDB de una version, en marcha: si no lo esta, se arranca solo ella, con tu usuario y en otro
# puerto de 127.0.0.1, y se apunta en LAMPP_BD_MARK_DIR (asi no se cierra al arrancar otra version ni al
# parar XAMPP-X)
function lampp_bd_up() {
    local f=$1 x data port i
    x=$(lampp_bd_xdir "$f") data=$(lampp_bd_data "$f")
    lampp_bd_alive "$f" && return 0
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] MariaDB de XAMPP-$f en otro puerto de 127.0.0.1, para Docker"
        return 0
    fi
    [ -d "$data" ] && [ -x "$x/mysql/bin/mariadbd" ] || { echo "XAMPP-$f no tiene MariaDB ($x)"; return 1; }
    port=$(lampp_bd_free_port) || { echo "No hay ningun puerto libre para la MariaDB de XAMPP-$f"; return 1; }
    echo "Arrancando la MariaDB de XAMPP-$f para Docker (en 127.0.0.1:$port)..."
    mkdir -p -m 700 "$LAMPP_BD_MARK_DIR" && echo "$port" > "$LAMPP_BD_MARK_DIR/$f" || return 1
    # (con tu usuario, como la de XAMPP-X; aparte de esta tarea: sigue al terminar)
    ( cd "$x/mysql" && /usr/bin/nohup ./bin/mariadbd --defaults-file="$x/etc/my.cnf" --port="$port" \
        --bind-address=127.0.0.1 < /dev/null > /dev/null 2>&1 & )
    for i in $(seq 300); do
        lampp_bd_alive "$f" && return 0
        sleep 0.2
    done
    rm -f "$LAMPP_BD_MARK_DIR/$f"
    echo "La MariaDB de XAMPP-$f no ha arrancado (¿la tiene otro programa?). Lo ultimo de su registro:"
    tail -8 "$data/mysqld.err" 2> /dev/null | sed 's/^/  /'
    return 1
}

# El puente de la red de Docker hasta su puerto en el Mac (nexum-lampp-bd-8-4-27, en el 3306). Si el
# puerto ha cambiado, se rehace
function lampp_bd_bridge_up() {
    local f=$1 name port
    name=$(lampp_bd_bridge "$f") port=$(lampp_bd_port "$f")
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] puente $name hasta host.docker.internal:$port"; return 0; }
    [ "$(dk inspect -f '{{.State.Running}} {{index .Config.Labels "nexum.lampp-bd-puerto"}}' "$name" 2> /dev/null)" == "true $port" ] && return 0
    dk rm -f "$name" > /dev/null 2>&1
    docker_net || return 1
    dk run -d --name "$name" --network nexum --restart no --label "nexum.lampp-bd=$f" --label "nexum.lampp-bd-puerto=$port" \
        --entrypoint socat "$LAMPP_BD_BRIDGE_IMAGE" TCP-LISTEN:3306,fork,reuseaddr "TCP:host.docker.internal:$port" > /dev/null
}

# Proyectos de Docker en marcha que usan la BBDD de esa version (menos el segundo argumento)
function lampp_bd_users() {
    local f=$1 skip=$2 p up
    up=$(dk ps --format '{{.Names}}' 2> /dev/null)
    for p in $(docker_web_projects); do
        [ "$p" != "$skip" ] && [ "$(docker_conf "$p" LAMPP_BD)" == "$f" ] && grep -qE "^nexum-$p-php[0-9]{2}\$" <<< "$up" && echo "$p"
    done
}

# La MariaDB que arranco Docker para esa version (solo si de verdad es ella: su .pid y su puerto)
function lampp_bd_stop_own() {
    local f=$1 data pid port
    data=$(lampp_bd_data "$f") port=$(lampp_bd_port "$f")
    pid=$(head -c 20 "$data/mysqld.pid" 2> /dev/null | tr -d ' \n')
    [[ "$pid" =~ ^[0-9]+$ ]] && [ "$pid" -gt 1 ] || return 0
    [[ " $(ps -ww -o command= -p "$pid" 2> /dev/null) " == *" --port=$port "* ]] || return 0
    kill "$pid" 2> /dev/null
    local i
    for i in $(seq 150); do lampp_bd_alive "$f" || break; sleep 0.2; done
    return 0
}

# Cuando ya no la usa ningun proyecto en marcha: fuera su puente y, si la arranco Docker, su MariaDB
# lampp_bd_release <version> [proyecto que se para]
function lampp_bd_release() {
    local f=$1 slug=$2
    [ -n "$f" ] || return 0
    [ -n "$(lampp_bd_users "$f" "$slug")" ] && return 0
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] fuera el puente de XAMPP-$f (y su MariaDB, si la arranco Docker)"; return 0; }
    dk rm -f "$(lampp_bd_bridge "$f")" > /dev/null 2>&1
    [ -f "$LAMPP_BD_MARK_DIR/$f" ] || return 0
    lampp_bd_stop_own "$f"
    rm -f "$LAMPP_BD_MARK_DIR/$f"
    echo "MariaDB de XAMPP-$f parada (ya no la usa ningun proyecto de Docker)"
}

# Antes de arrancar XAMPP-X con esa version: si su MariaDB la tenia Docker (en otro puerto), se para para
# que arranque la normal; despues, lampp_bd_retarget lleva su puente al 3306
function lampp_bd_handover() {
    local f=${1##*/XAMPP-}
    [ -n "$f" ] && [ -f "$LAMPP_BD_MARK_DIR/$f" ] || return 0
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] la MariaDB de XAMPP-$f que tenia Docker pasa a la de XAMPP-X"; return 0; }
    echo "La MariaDB de XAMPP-$f la tenia Docker: pasa a la de XAMPP-X"
    lampp_bd_stop_own "$f"
    rm -f "$LAMPP_BD_MARK_DIR/$f"
}

# Despues de arrancar XAMPP-X: el puente de esa version, a su puerto de siempre (si lo usa Docker)
function lampp_bd_retarget() {
    local f=${1##*/XAMPP-}
    [ -n "$f" ] && [ -n "$(lampp_bd_users "$f")" ] || return 0
    lampp_bd_bridge_up "$f"
}

# Al parar XAMPP-X: si algun proyecto de Docker en marcha usaba la BBDD de esta version, vuelve su MariaDB
# (en otro puerto, para Docker) y su puente
function lampp_bd_keep() {
    local f=${1##*/XAMPP-}
    [ -n "$f" ] && [ -n "$(lampp_bd_users "$f")" ] || return 0
    echo "Algun proyecto de Docker usa la BBDD de XAMPP-$f: su MariaDB sigue para el (en otro puerto)"
    lampp_bd_up "$f" && lampp_bd_bridge_up "$f"
}

# El usuario, la contraseña y la base del proyecto en LAMPP (los de su wp-config.php): usuario|base y la
# contraseña en la segunda linea
function lampp_bd_creds() {
    python3 -I - "$HTDOCS_DIR/$1/wp-config.php" << 'EOF'
import re, sys
try:
    text = open(sys.argv[1], encoding="utf-8", errors="replace").read(2000000)
except OSError:
    sys.exit(1)
def get(name):
    m = re.search(r"""(?m)^(?:(?!//|#)[^\n])*?\bdefine\(\s*['"]%s['"]\s*,\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")""" % name, text)
    return None if not m else re.sub(r"\\(.)", r"\1", m.group(1) if m.group(1) is not None else m.group(2))
user, db, pw = get("DB_USER"), get("DB_NAME"), get("DB_PASSWORD")
if not user or not db or pw is None or "\n" in pw or "|" in user + db:
    sys.exit(1)
print(user + "|" + db)
print(pw)
EOF
}

# docker-bd <nombre> lampp <version> | docker: la BBDD de un WordPress de Docker, en vivo la de esa
# version XAMPP-X (la misma que web.local) o su copia en la MariaDB comun de Docker (la de antes, que no
# se borra al pasar a LAMPP)
function docker_db_mode() {
    local slug=$1 mode=$2 v=$3 dir creds user db pass owner was
    docker_web_project "$slug" || { echo "No hay ningun proyecto en Docker (con el Apache de Docker) con el nombre $slug"; return 1; }
    dir=$DOCKER_DIR/$slug
    case $mode in
        lampp)
            [ "$(docker_conf "$slug" TIPO)" == wp ] || { echo "Solo WordPress: una tienda guarda su dominio en la BBDD y no puede servir a web.local y a Docker a la vez"; return 1; }
            valid_version_name "$v" && [ -d "$BASE_DIR/XAMPP-$v" ] || { echo "No existe la version XAMPP-$v"; return 1; }
            owner=$(lampp_bd_owner "$v")
            creds=$(lampp_bd_creds "$(docker_conf "$slug" CARPETA)") || { echo "No se puede leer el usuario y la base del wp-config.php de $(docker_conf "$slug" CARPETA)"; return 1; }
            user=${creds%%|*} db=$(head -1 <<< "$creds" | cut -d'|' -f2) pass=$(sed -n 2p <<< "$creds")
            echo "$slug: BBDD $db de XAMPP-$owner, en vivo (la misma que web.local; la copia de Docker se queda)"
            [ "$DRY" -eq 1 ] && return 0
            # (los de Docker de antes, para volver: BBDD y usuario de su copia)
            [ -z "$(docker_conf "$slug" LAMPP_BD)" ] && docker_conf_set "$slug" BBDD_DOCKER "$(docker_conf "$slug" BBDD)" \
                && docker_conf_set "$slug" USUARIO_DOCKER "$(docker_conf "$slug" USUARIO)" \
                && { grep -q '^DB_PASS_DOCKER=' "$dir/.env" || ( umask 077; sed -n 's/^DB_PASS=/DB_PASS_DOCKER=/p' "$dir/.env" >> "$dir/.env" ); }
            docker_conf_set "$slug" LAMPP_BD "$owner" && docker_conf_set "$slug" BBDD "$db" && docker_conf_set "$slug" USUARIO "$user" || return 1
            ( umask 077; { grep -v '^DB_PASS=' "$dir/.env"; printf 'DB_PASS=%s\n' "$pass"; } > "$dir/.env.nuevo" ) && mv -f "$dir/.env.nuevo" "$dir/.env" || return 1 ;;
        docker)
            owner=$(docker_conf "$slug" LAMPP_BD)
            [ -n "$owner" ] || { echo "$slug ya usa su copia de Docker"; return 0; }
            [ -n "$(docker_conf "$slug" BBDD_DOCKER)" ] || { echo "$slug no tiene copia en Docker: crea el proyecto de nuevo copiando la BBDD"; return 1; }
            echo "$slug: vuelve a su copia de Docker ($(docker_conf "$slug" BBDD_DOCKER))"
            [ "$DRY" -eq 1 ] && return 0
            docker_conf_set "$slug" BBDD "$(docker_conf "$slug" BBDD_DOCKER)" && docker_conf_set "$slug" USUARIO "$(docker_conf "$slug" USUARIO_DOCKER)" \
                && docker_conf_set "$slug" LAMPP_BD "" || return 1
            ( umask 077; { grep -v '^DB_PASS=' "$dir/.env"; sed -n 's/^DB_PASS_DOCKER=/DB_PASS=/p' "$dir/.env"; } > "$dir/.env.nuevo" ) && mv -f "$dir/.env.nuevo" "$dir/.env" || return 1 ;;
        *) echo "Uso: lvm-instalador docker-bd <nombre> lampp <version> | docker"; return 1 ;;
    esac
    # (su configuracion con la BBDD nueva; si estaba en marcha, se arranca de nuevo con ella)
    was=$(dk ps --format '{{.Names}}' 2> /dev/null | grep -cE "^nexum-$slug-php[0-9]{2}\$")
    for v in $(docker_conf "$slug" PHP); do docker_web_config "$slug" "$v" > /dev/null || return 1; done
    if [ "$was" -gt 0 ]; then
        docker_web_action arrancar "$slug" || return 1
        [ "$mode" == docker ] && lampp_bd_release "$owner" "$slug"
    fi
    echo "Listo"
}

# Aviso al parar algo comun (una MariaDB comun, el Apache de Docker o su phpMyAdmin) que usa algun
# proyecto en marcha: cuales se quedan sin el
function docker_shared_warn() {
    local name=$1 up p v="" users=() lampp=""
    if [[ "$name" =~ ^nexum-lampp-bd-([0-9]{1,2})-([0-9]{1,2})(-([0-9]{1,3}))?$ ]]; then
        lampp=${BASH_REMATCH[1]}.${BASH_REMATCH[2]}${BASH_REMATCH[4]:+.${BASH_REMATCH[4]}} v=x
    else
        [[ "$name" =~ ^nexum-(web|pma|mariadb-([0-9]{1,2})-([0-9]{1,2}))$ ]] || return 0
        [ -n "${BASH_REMATCH[2]}" ] && v=${BASH_REMATCH[2]}.${BASH_REMATCH[3]}
    fi
    up=$(dk ps --format '{{.Names}}' 2> /dev/null) || return 0
    for p in $(docker_web_projects); do
        if [ -n "$lampp" ]; then
            [ "$(docker_conf "$p" LAMPP_BD)" == "$lampp" ] || continue
        elif [ -n "$v" ] && { [ "$(docker_conf "$p" MARIADB)" != "$v" ] || [ -n "$(docker_conf "$p" LAMPP_BD)" ]; }; then
            continue
        fi
        grep -qE "^nexum-$p-php[0-9]{2}\$" <<< "$up" && users+=("$(docker_conf "$p" CARPETA)")
    done
    [ ${#users[@]} -eq 0 ] && return 0
    echo "Aviso: $name es comun y lo usan ahora: ${users[*]}. $([ -n "$v" ] && echo "Se quedan sin BBDD" || echo "Dejan de verse") hasta que lo arranques"
}

# docker-parar-todo: todos los contenedores de Nexum en marcha (los de los proyectos, las MariaDB
# comunes, el Apache de Docker y su phpMyAdmin), parados. Los de otros programas no se tocan
function docker_stop_all() {
    local up names=()
    up=$(dk ps --format '{{.Names}}' 2> /dev/null) || { echo "Docker no responde"; return 1; }
    mapfile -t names < <(grep -E '^nexum-([a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?-((php|db|pma)-[0-9]{1,3}|php[0-9]{2})|web|pma|mariadb-[0-9]{1,2}-[0-9]{1,2}|lampp-bd-[0-9]{1,2}-[0-9]{1,2}(-[0-9]{1,3})?)$' <<< "$up")
    if [ ${#names[@]} -eq 0 ]; then
        echo "No hay ningun contenedor de Nexum en marcha"
        return 0
    fi
    echo "Parando ${#names[@]} contenedores de Nexum: ${names[*]}"
    run dk stop "${names[@]}" > /dev/null || return 1
    # (y la MariaDB de LAMPP que hubiera arrancado Docker para alguno)
    local f
    for f in $(ls "$LAMPP_BD_MARK_DIR" 2> /dev/null); do valid_version_name "$f" && lampp_bd_release "$f"; done
    echo "Todos parados"
}

# docker-pasar <nombre>: un proyecto de antes (con XAMPP-X delante, con su MariaDB y su phpMyAdmin)
# pasa al Apache de Docker. Su BBDD se guarda antes en ~/lvm-copias (si algo falla, ahi esta) y se carga
# en la MariaDB comun; despues se quitan sus contenedores, su vhost de XAMPP-X, su clave y su linea de hosts. Si la
# carpeta ya esta en el sistema nuevo (otra version de PHP del mismo proyecto), solo se le añade su PHP
function docker_pass() {
    local slug=$1 dir folder php maria db target="" p backup
    if ! docker_valid_slug "$slug" || [ ! -f "$DOCKER_DIR/$slug/proyecto.conf" ] || docker_web_project "$slug"; then
        echo "No hay ningun proyecto de antes (con XAMPP-X delante) con el nombre $slug"
        return 1
    fi
    dir=$DOCKER_DIR/$slug
    folder=$(docker_conf "$slug" CARPETA) php=$(docker_conf "$slug" PHP) maria=$(docker_conf "$slug" MARIADB) db=$(docker_conf "$slug" BBDD)
    db_valid_name "$db" > /dev/null || { echo "$slug no tiene una BBDD valida en su proyecto.conf"; return 1; }
    for p in $(docker_web_projects); do
        [ "$(docker_conf "$p" CARPETA)" == "$folder" ] && target=$p
    done
    echo "$slug pasa al Apache de Docker${target:+ (como PHP $php de $target)}"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] copia de $db en ~/lvm-copias, fuera sus contenedores, su vhost y su linea de hosts"
        return 0
    fi
    docker_ready || { echo "Docker Desktop no esta en marcha"; return 1; }
    docker_web_ports_ok || { echo "La direccion del Apache de Docker aun no esta en este Mac: pulsa «Permitir» en Configuracion, Docker"; return 1; }
    sudo_first || return 1
    task_plan "Pasando $folder al Apache de Docker" "Copiar su BBDD" "Quitar el proyecto de antes" "Montarlo en el Apache de Docker"
    task_step
    echo "Copia de su BBDD ($db)"
    mkdir -p -m 700 "$HOME/lvm-copias" || return 1
    backup="$HOME/lvm-copias/docker-$slug-$db-$(date +%Y%m%d-%H%M%S).sql.gz"
    dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d db > /dev/null || return 1
    local i
    for i in $(seq 60); do
        dk compose --project-directory "$dir" -f "$dir/compose.yaml" exec -T db \
            sh -c 'MYSQL_PWD=$MARIADB_ROOT_PASSWORD exec $(command -v mariadb || command -v mysql) -uroot -e "SELECT 1"' < /dev/null > /dev/null 2>&1 && break
        sleep 1
    done
    ( umask 077
      set -o pipefail
      dk compose --project-directory "$dir" -f "$dir/compose.yaml" exec -T db \
          sh -c 'MYSQL_PWD=$MARIADB_ROOT_PASSWORD exec $(command -v mariadb-dump || command -v mysqldump) -uroot --single-transaction --routines --triggers --events "$0"' "$db" \
          < /dev/null | gzip > "$backup" )
    if [ $? -ne 0 ] || [ "$(gzip -dc "$backup" 2> /dev/null | head -c 4096 | wc -c)" -lt 100 ]; then
        echo "No se ha podido copiar su BBDD: no se cambia nada"
        rm -f "$backup"
        return 1
    fi
    echo "Copia de $db: $backup"
    task_step
    docker_action borrar "$slug" || { echo "No se ha podido quitar el proyecto de antes (la copia de su BBDD esta en $backup)"; return 1; }
    task_step
    if [ -n "$target" ]; then
        docker_web_add "$target" "$php" || return 1
        echo "$folder ya tenia BBDD en el sistema nuevo: la de $slug no se carga (esta en $backup)"
    else
        docker_web_create "$folder" "$php" "$maria" --bd "$db" --volcado "$backup" \
            || { echo "La copia de su BBDD sigue en $backup"; return 1; }
    fi
    echo "$slug ya funciona con el Apache de Docker"
}

# ¿Le falta a la version el parche de seguridad contra PHP2Shell que llevaria al rehacerla con PHP
# <php>? (solo 7.4.33, 8.0.30 y 8.1.34 lo llevan)
function php2shell_missing() {
    php2shell_backport "$2" > /dev/null && [ ! -f "$1/$PHP2SHELL_MARK" ]
}

# ¿Esta al dia una version? si|<php> / no|<php nuevo> / error
function gui_up_to_date() {
    local dir=$BASE_DIR/XAMPP-$1
    # (XAMPP-7.4.33 y las demas con la version en el nombre: solo falta, si acaso, el parche)
    if ! [[ "$1" =~ ^[0-9]+\.[0-9]+$ ]] && php2shell_backport "$1" > /dev/null; then
        php2shell_missing "$dir" "$1" && echo "no|$1" || echo "si|$1"
        return 0
    fi
    local full=$(rebuild_version "$dir" "$(php_releases)")

    if [ -z "$full" ]; then
        echo "error"
    elif [ "$(stack_fields "$dir")" == "$(stack_versions "$full")" ] && ! php2shell_missing "$dir" "$full"; then
        echo "si|$full"
    else
        echo "no|$full"
    fi
}

# arrancar / parar / reiniciar la version activa
function control_lampp() {
    if [ -z "$(active_dir)" ]; then
        echo "No hay ninguna version activa"

        return 1
    fi

    # Antes de arrancar, fuera los de otras versiones (ademas ocuparian los puertos 80, 443 y 3306)
    # y solo para este Mac
    if [ "$1" == start ] || [ "$1" == restart ]; then
        close_processes
        secure_version "$(active_dir)"
        secure_failed $? "$(active_dir)" && return 1
        vhosts_root
    fi
    local rc
    # (la MariaDB de esta version, si la tenia Docker en otro puerto: se para para que arranque la normal)
    [ "$1" != stop ] && lampp_bd_handover "$(active_dir)"
    run xampp_ctl "$1"
    rc=$?
    # Parada: no queda nada en memoria, tampoco de esta version
    if [ "$1" == stop ]; then
        close_processes --todos
        # (salvo lo que use Docker: su MariaDB vuelve, en otro puerto)
        lampp_bd_keep "$(active_dir)"
    else
        lampp_bd_retarget "$(active_dir)"
    fi
    # Mailpit (correo de pruebas) arranca y para con la version
    mailpit_sync
    return $rc
}

# desinstalar <version> [--copia]: sin preguntas (la ventana ya ha confirmado)
function cli_remove() {
    local version=$1 dir=$BASE_DIR/XAMPP-$1
    local blocker=$(remove_blocker "$version")

    if [ -n "$blocker" ]; then
        echo -e "$blocker"

        return 1
    fi

    if [ "$2" == "--copia" ] && [ -n "$(db_names "$dir")" ]; then
        if [ "$DRY" -eq 0 ] && [ -n "$SUDO" ]; then
            echo "Se necesita la contraseña de administrador (sudo):"
            sudo -v || return 1
        fi
        local size_kb=0
        [ "$DRY" -eq 0 ] && size_kb=$($SUDO du -sk "$dir/xamppfiles/var/mysql" 2> /dev/null | cut -f1)
        local free_kb=$(df -k "$HOME" | awk 'NR == 2 {print $4}')
        if [ -n "$size_kb" ] && [ "$free_kb" -lt "$size_kb" ]; then
            echo "No hay espacio para la copia: ocupan $((size_kb / 1024)) MB y hay $((free_kb / 1024)) MB libres en $HOME."
            echo "No se ha podido guardar la copia, asi que NO se desinstala nada."

            return 1
        fi
        if ! backup_databases "$version"; then
            echo "No se ha podido guardar la copia, asi que NO se desinstala nada."

            return 1
        fi
    fi

    remove_version "$version"
}

# Acerca de: que hace el instalador y la lista de versiones con sus cambios (la ultima, arriba)
ABOUT_TEXT="Herramientas de desarrollo web en local. Para Mac con Apple Silicon.

QUE HACE
- Instala varias versiones de PHP, de la 7.4 a la 8.5, cada una con su
  propia pila compilada en el Mac: Apache, PHP-FPM, MariaDB, ProFTPD,
  Perl y phpMyAdmin, en /Library/Nexum/XAMPP-X.Y.Z (de root) y con sus
  propias bases de datos. Cada rama de PHP lleva componentes compatibles
  entre si.
- Solo hay una versión activa (/Applications/XAMPP). Los proyectos y los
  virtual hosts se comparten en /Library/Nexum/XAMPP-compartido.
- El gestor está en /Library/Nexum/gestor, de root: lo que se ejecuta
  como administrador no lo puede cambiar ningún programa de tu usuario.
- Actualiza cada versión a los últimos parches de su rama, muestra sus
  bases de datos y desinstala versiones guardando copia en ~/lvm-copias.
- De Homebrew solo usa librerias, que se copian dentro de cada versión.
  No instala PHP ni MariaDB en el sistema.
- Lleva proyectos a Docker Desktop con cualquier versión de PHP, de la
  5.6 a la 8.5, a la vez que las versiones XAMPP-X.
- Correo de pruebas: lo que mandan las webs (formularios, pedidos,
  contraseñas) va a Mailpit y no llega a nadie.

VERSIONES

1.57.5 (9 nov 2026)
- Mismo número de versión que la de Linux, porque las dos llevan lo
  mismo (hasta ahora iba por la 1.41).
- Instalar, «Otro parche concreto» (como en Linux): una versión
  anterior de cualquier rama (8.3.10…), en su propia carpeta
  XAMPP-X.Y.Z. En la terminal: instalar --php 8.3.10.
- Al acabar de instalar, «Activar» ofrece la carpeta de verdad
  (XAMPP-8.4.27, no XAMPP-8.4).
- Configuración: arriba, en grande, el nombre del apartado abierto
  (con su icono y lo que hace), no «Configuración»; el correo de
  pruebas se enciende con el interruptor de al lado.
- Apariencia: en tres bloques, cada uno con su título (iconos del
  menú lateral, apartados del menú lateral y visor de los proyectos).
  Los botones del visor están aquí: ya no hay un apartado aparte (salían
  dos veces).
- Seguridad entre webs: explicada en cuatro puntos (el problema, lo
  que hace la barrera, cuándo apagarla y dónde se aplica).

1.41.3 (9 nov 2026)
- Diálogos que piden confirmar varios cambios (crear un dominio,
  copiar o replicar una BBDD, cargar o actualizar un proyecto, instalar
  versiones, Actualizar todo): empiezan por «Qué se va a realizar» y
  los cambios van numerados, a la izquierda y separados entre sí.

1.41.2 (8 nov 2026)
- Actualizar versiones de PHP: si GitHub no da la suma sha256 de
  ProFTPD (su descarga respondía 504 y la actualización fallaba al
  momento), se pide por la API de GitHub, del mismo repositorio. Si
  una descarga falla, el informe del error dice por qué.

1.41.1 (7 nov 2026)
- Configuración: sus apartados, en una columna pegada al menú
  lateral, y en filas (Docker y el correo de pruebas siguen en
  tarjetas). El correo de pruebas se enciende con el interruptor de su
  título; en la dirección del Apache de Docker, Guardar va debajo de
  sus campos.
- Parches nuevos: en lugar de preguntar al abrir, sale un aviso arriba
  (al lado del visor) con lo que tiene un parche y si conviene ponerlo.
  «Ahora no» lo deja hasta que salga otro.
- Terminal: pegada a la ventana, de lado a lado y sin márgenes, y
  el prompt sale bien (antes, zsh lo dejaba a la derecha de un «%»).

1.41.0 (6 nov 2026)
- Proyectos de Node: nueva pestaña Node para los proyectos de htdocs
  hechos con Astro, Next, Nuxt, SvelteKit o Vite. Cada uno se arranca en
  desarrollo o compilado, con la versión de Node que pide y sus
  dependencias, y el compilado se puede compartir con un túnel de
  Cloudflare. En la terminal: node-arrancar, node-parar y node-registro.
- Instalaciones en segundo plano: la ventana de una instalación o
  actualización tiene «Seguir en segundo plano» (también con Esc) y
  el programa se puede usar mientras tanto. Al lado del visor sale una
  flecha verde que late, con lo que hace
  («Actualizando…», «Instalando…») y el porcentaje; al pulsarla vuelve la
  ventana. Si acaba bien, avisa; si falla, la ventana vuelve sola. No
  se puede lanzar otra tarea hasta que acabe.
- Apariencia, en Configuración: los iconos del menú lateral en color
  o de un color, como el texto; Docker, Node y PHP con su logotipo y su
  tipografía; qué apartados salen en el menú (Proyectos y Configuración,
  siempre), y los botones del proyecto. Bases de datos, con su icono de
  discos apilados.

1.40.14 (6 nov 2026)
- Correo de pruebas: la bandeja de Mailpit se ve dentro de la ventana,
  debajo de sus tarjetas, y el botón Correo lleva a ella en lugar de
  abrir el navegador. Los enlaces de los correos sí se abren en el
  navegador al pulsarlos.

1.40.13 (6 nov 2026)
- Instalaciones y actualizaciones: encima de «Ver registro» sale la
  lista de lo que se está haciendo y cada paso se marca con un check al
  acabar. También al actualizar un proyecto o los componentes, al montar
  un proyecto nuevo, en Docker, Mailpit, cloudflared y phpMyAdmin.

1.40.12 (6 nov 2026)
- Proyecto cargado: los botones se llaman «Actualizar» e «Importar». Al
  pasar por encima dicen «Actualizar proyecto» e «Importar imágenes de
  producción».

1.40.11 (5 nov 2026)
- Proyecto cargado y Docker: botón «Importar imágenes» en WordPress y
  PrestaShop. Se muestra u oculta en Personalizar los botones.
- Iconos nuevos en «Actualizar proyecto» e «Importar imágenes».

1.40.10 (5 nov 2026)
- Proyecto cargado: el botón Log abre el error_log de Apache. El de
  web.local sigue en Herramientas, Registro de errores.

1.40.9 (5 nov 2026)
- Actualizar proyecto: se puede actualizar la BBDD, el código o los
  dos. Sin fichero de BBDD, dice que se sigue usando la misma y no la
  toca.
- Actualizar proyecto: al acabar se comprueba que wp-config.php o
  parameters.php han quedado con la BBDD y la dirección locales, sin
  desmontar ni volver a cargar a mano. Si no, lo dice.
- Proyecto cargado: botón «Actualizar proyecto». En su ventana se
  arrastra o se elige la BBDD descargada de producción y su código (un
  .zip, un .tar.gz o una carpeta), y se elige entre fusionar o
  sobrescribir la carpeta. Si es un repositorio, antes de copiar
  pregunta si hacer git pull y avisa de lo que no tiene commit o no se
  ha subido.
- Lo sustituido o quitado del proyecto queda en ~/lvm-copias, su .git
  no se toca y, al acabar, el proyecto se vuelve a cargar para que su
  configuración apunte a la base y al dominio locales.
- En la terminal: lvm-instalador actualizar-proyecto.

1.40.8 (5 nov 2026)
- Repositorios: botón para copiar el repositorio. Al pegarlo en el
  buscador de Nuevo proyecto, queda elegido.
- Nuevo proyecto, buscador de repositorios: encuentra el repositorio al
  momento. La lista se carga en segundo plano al abrir el programa y
  se pone al día con GitHub. También salen los que no llevan uno de
  los prefijos de Configuración.
- Repositorios: la lista tardaba unos minutos y a veces no llegaba a
  cargar. Cada lectura del token de gh esperaba 15 segundos sin motivo.

1.40.7 (5 nov 2026)
- Los mensajes al dejar el ratón encima de botones, interruptores e
  indicadores son ahora cortos y dicen solo lo que hacen. Las
  explicaciones largas siguen en los símbolos ⓘ.
- Proyecto cargado: el interruptor del dominio lleva el título «Falsear
  Host» y, cuando está falseado, «Host falseado».
- Botón Log: icono nuevo, un folio verde con «LOG» escrito.
- Proyecto cargado: si su carpeta tiene un dominio en los vhosts, junto
  a sus botones sale ese dominio con un interruptor para falsearlo o
  dejar de falsearlo sin ir a Dominios y hosts.
- Dominios y hosts: «Host falseado» ocupa 1/3 de la pestaña y, a su
  lado, «Nuevo proyecto con dominio falseado» ocupa los otros 2/3.
- Dominios y hosts, botón «Ver fichero de hosts»: enseña /etc/hosts,
  solo para leerlo, con los dominios que se pueden falsear delante (los
  que tienen vhost, estén o no en el fichero).

1.40.6 (3 nov 2026)
- Dominios y hosts, «Crear y falsear»: junto al botón dice lo que
  falta para poder crearlo (un dominio válido o la carpeta) y, con todo
  puesto, lo que va a crear (https://dominio → carpeta).
- El dominio se puede pegar como dirección (https://www.mitienda.com/):
  se queda solo con el nombre.

1.40.5 (3 nov 2026)
- WordPress: el wp-config.php lleva siempre WP_SITEURL y WP_HOME con
  la dirección local (https://web.local o su dominio propio). Si
  entraba en la base pero le faltaban, se daba por bueno y la web
  redirigía a producción: ahora, al cargar el proyecto (o en Nuevo
  proyecto), se le añaden sin tocar el resto del fichero.

1.40.4 (3 nov 2026)
- Nuevo proyecto con un WordPress: al acabar de importar su BBDD se
  prepara su wp-config.php para local (la base, root y localhost, y
  WP_HOME). Se hacía al cargarlo, antes de importarla, y como la base
  aún no existía se quedaba sin hacer (solo se repetía con PrestaShop).
  Si después pegas encima el código de producción, vuelve a cargar el
  proyecto: su wp-config.php vuelve a la base local.

1.40.3 (3 nov 2026)
- Icono en la barra de menús (junto al reloj): al cerrar la ventana,
  la aplicación sigue en él. Su menú abre la ventana, arranca o para
  la versión activa (con su estado), abre web.local y sale. Se quita
  en Configuración → Programa; sin él, cerrar la ventana la cierra
  como antes.
- Terminal: ⌘C y ⌘V copian y pegan (antes Pegar no hacía nada), y
  con el botón derecho, Copiar, Pegar y Seleccionar todo. Lo pegado
  con varias líneas llega como si pulsaras Intro en cada una.
- Terminal: «Proyecto cargado» ya lleva a su carpeta (se quedaba en la
  de los proyectos), y lo mismo al abrirla. Nuevo botón «Vaciar DNS»:
  escribe sudo dscacheutil -flushcache y reinicia mDNSResponder (la
  contraseña, en la terminal).

1.40.2 (30 oct 2026)
- Descargar una BBDD: ya no falla («Unable to lock ibdata1») si la
  MariaDB de esa versión la tiene en marcha Docker (sin red). Se usa
  esa MariaDB en lugar de arrancar otra sobre los mismos datos, y al
  terminar sigue en marcha para Docker. Lo mismo al copiar una BBDD a
  otra versión.
- Visor de arriba: sin el botón Encendidos. Al pulsar Apache o MariaDB
  se abren sus servicios (lo que antes salía en la flecha), con
  «Parar y desactivar» o «Arrancar» la versión entera arriba.
- Bases de datos: «Subir o actualizar una BBDD» va antes de la tabla,
  más compacto (el fichero, la BBDD de destino, el proyecto y Cargar
  en columnas) y en un visor un poco hundido.
- Configuración: a la izquierda, una columna con sus apartados (Parches
  nuevos, Vhosts y hosts, Correo de pruebas, Docker, GitHub, Carpetas…);
  a la derecha, solo lo que se puede cambiar del elegido.
- Ventana: al cerrarla, la aplicación se cierra del todo (con una tarea
  en marcha, al acabar la tarea).
- Ventana más ligera: lo que pregunta cada 20 s va en una sola orden (la
  revisión de seguridad de las versiones solo se repite si cambian sus
  ficheros y las fechas de las BBDD se leen de una vez).

1.40.1 (30 oct 2026)
- Nuevo proyecto: en el paso 1, el repositorio se elige de los de
  GitHub (los de la pestaña Repositorios, escribiendo parte de su
  nombre): se rellenan solos su dirección SSH y su carpeta. Se puede
  seguir escribiendo la dirección de otro. Un paso 4 pregunta si falsear
  su dominio de producción (ya puesto si el repositorio tiene su web en
  GitHub): al terminar de montarlo, se falsea como en Dominios y hosts.
- Terminal: el mismo hueco arriba que abajo de su caja.
- Terminal abajo de la ventana: el botón Terminal de arriba (en lugar
  de Localhost) la enseña y la esconde. Con el aspecto del visor, un
  poco hundida; tu shell, con tu usuario, en la carpeta del proyecto
  cargado, con Ctrl+C como en Terminal (sin colores ni programas a
  pantalla completa, como vim). Al esconderla sigue abierta.
- Docker con la BBDD de XAMPP-X en vivo (WordPress): un proyecto de
  Docker puede usar la BBDD de cualquier versión de XAMPP-X, la misma
  que web.local, sin copias. Si la MariaDB de esa versión no está en
  marcha, se arranca solo ella, con tu usuario y en otro puerto de
  127.0.0.1; un puente en Docker lleva las conexiones hasta ella. Se para
  sola cuando ningún proyecto de Docker la usa, y al activar esa versión
  pasa a la de siempre. Se elige al montarlo («Cómo: en vivo») o con el
  botón de su fila en la pestaña Docker. Las tiendas PrestaShop siguen
  con su copia. En la terminal: docker-bd <proyecto> lampp <versión> |
  docker.
- Docker: las imágenes y enlaces que un WordPress guardó trabajando con
  XAMPP-X (https://web.local/wp-content/…, o su dominio propio) salen del
  contenedor: antes se pedían a XAMPP-X y, sin él en marcha o con otro
  proyecto en web.local, no se veían. La BBDD no se toca: se cambian en
  lo que devuelve la web (también escapadas, como las de Elementor). Los
  proyectos de antes se arreglan al arrancarlos.
- Configuración, GitHub: la organización o cuenta se puede escribir
  también como su dirección (https://github.com/hexer-dev) o con @, se
  comprueba que existe, y si no vale se dice en una ventana y lo escrito
  se queda (antes volvía la de antes sin decir nada).
- Los proyectos de Docker sin visitas se paran solos (Configuración,
  Docker): uno que lleva las horas elegidas (3 de partida; de 1 a 24, o
  nunca) sin ninguna visita, tampoco por el túnel, se para, y con él lo
  común que ya no use nadie (su MariaDB, el Apache de Docker). Se mira
  cada 15 minutos, también con la ventana cerrada (un LaunchAgent tuyo). Al entrar
  en un proyecto parado, su web lo dice en vez de dar un error. En la
  terminal: docker-reposo.
- Pestaña Repositorios (como DevHub): los repositorios de la
  organización o cuenta de GitHub que se elija en Configuración, solo
  los de sus prefijos (de partida dob-wordpress- y dob-prestashop-; se
  pueden añadir otros, como los de Shopify) o todos, con un buscador.
  «Clonar» lo clona por SSH, con tu clave, en la carpeta de proyectos.
  Si ya está clonado en un proyecto, se pregunta si aplastarlo: se
  traen sus cambios con git pull y, si chocan con los tuyos, no se toca
  nada y se dice. La lista se lee con un token de GitHub (se guarda en
  el Llavero, no en un fichero) o con la sesión de gh, y la de la
  última vez sale al momento. En la terminal: github, github-conectar,
  repos y repo-traer.
- Túnel de Cloudflare: cuánto dura y si se bloquea el admin se eligen
  al pulsar «Compartir», para ese proyecto y ese túnel. Cada túnel
  lleva una contraseña nueva al azar (se ve al abrirlo, para copiarla);
  la de un túnel no vale para el siguiente. Configuración, Túnel de
  Cloudflare deja solo cloudflared, el túnel abierto y su registro. En
  la terminal: tunel-abrir <dirección> [carpeta] [--horas 1-12]
  [--admin bloquear|permitir]; ya no hay tunel-config.
- Menos memoria con varios proyectos de Docker a la vez: el Apache con
  PHP de cada contenedor espera con un proceso (no con cinco) y, sin
  trabajo, no se queda con más de dos; cada uno se rehace a las 200
  peticiones. Los de antes se ponen al día solos al arrancarlos. El
  Apache de Docker espera con un proceso, no con tres.
- Imágenes de producción: «Guardar» funciona también con el dominio que
  ya estaba guardado (así se vuelve a aplicar, también en el Apache de
  Docker).
- Imágenes de producción también en Docker: en un WordPress del Apache
  de Docker, lo que falte de wp-content/uploads se pide a su web real
  (con el mismo dominio que con XAMPP-X: «Imágenes de producción…» vale
  para los dos). En una tienda, «Descargar las imágenes que faltan»
  usa la BBDD de Docker si no está en la versión activa (su dominio de
  producción se guarda al pasarla a Docker; si no se sabe, se pide).
  Botón «Imágenes de producción…» en el visor de Docker.
- Configuración más clara: cada ajuste en su tarjeta, de dos en dos
  (como los visores de las otras pestañas), con su explicación entera
  y sus botones en la tarjeta. Docker junta la dirección y los dos
  puertos en una sola; lo que va solo (la barrera entre webs, los
  botones del visor, el túnel abierto) va a lo ancho.
- Botones del proyecto: el configurador va en horizontal (la lista a la
  izquierda; el estilo, el tamaño y la vista previa a la derecha), y
  cabe en la pantalla de un portátil: el botón Guardar ya no se queda
  fuera.
- Proyecto nuevo desde un repositorio privado: si su dirección https
  de GitHub, GitLab o Bitbucket no se puede clonar (pide usuario y
  contraseña), se prueba sola la misma por SSH
  (git@github.com:usuario/repositorio.git), con tu clave. Con otros
  servidores, como siempre: su dirección SSH a mano.
- DNS de *.docker.test (Configuración, Docker, «Activar»): un DNS
  mínimo, solo en este Mac, que contesta a cualquier
  <algo>.docker.test. Los proyectos del Apache de Docker pasan a
  .docker.test (su configuración, el dominio de las tiendas en su BBDD
  y el certificado) y dejan de ir en /etc/hosts: añadir proyectos o
  versiones de Docker ya no pide la contraseña por los dominios.
  web.local, los proyectos de siempre y los dominios falseados de las
  tiendas no cambian (siguen en /etc/hosts, que se mira antes). Si el
  DNS no contesta al activarlo, se quita y todo sigue como estaba.
  .local es de mDNS (Bonjour): un DNS para *.docker.local no se
  consultaría nunca. En la terminal: docker-web dns activar|quitar.
- El certificado del Apache de Docker vale para *.docker.local y
  *.docker.test.
- Parches nuevos (Configuración): lo que tiene un parche publicado en
  cada versión XAMPP-X (PHP, Apache, MariaDB, ProFTPD, Perl y
  phpMyAdmin), en las imágenes de Docker (las MariaDB comunes,
  phpMyAdmin y PHP, frente a Docker Hub, sin descargar nada), Mailpit y
  cloudflared, con «Actualizar todo» (las XAMPP-X.Y.Z llevan su parche
  en el nombre: la nueva se instala a su lado). Se busca al abrir la ventana
  cuando toca buscar una versión nueva del programa y, si hay algo, se
  ofrece actualizarlo. Las MariaDB comunes de Docker se ponen al día
  solas al cambiar de parche. En la terminal: componentes y
  componentes-actualizar.
- Correo de pruebas (Configuración): sus tres tarjetas en una fila.
- Repositorios: detrás de «Clonar» o «Traer cambios», el logotipo de
  GitHub abre el repositorio en GitHub (sus cambios, ramas y pull
  requests). La carpeta de los ya clonados va debajo del nombre, y así
  todos los botones quedan a la misma altura.

1.40.0 (28 oct 2026)
- Docker con su propio Apache: los proyectos de Docker ya no necesitan
  XAMPP-X (funcionan con XAMPP-X parado o con cualquier versión activa).
  Un Apache en un contenedor, en otra dirección de este Mac (127.0.0.2,
  nunca abierta a la red), con la barrera entre webs, que pasa cada
  dominio al contenedor de su versión de PHP con la clave del proyecto.
  Las imágenes de PHP son las de siempre (con sus .htaccess y las reglas
  de los ficheros que no se sirven). macOS solo tiene 127.0.0.1: la otra
  se da de alta una vez («Permitir», pide la contraseña) y un servicio
  del sistema la vuelve a poner en cada arranque.
- Docker, varias versiones de PHP a la vez: con la misma BBDD. En un
  WordPress, cada una con su dominio (proyecto-php83.docker.local); una
  tienda PrestaShop guarda su dominio en la BBDD, así que va con uno
  (proyecto.docker.local) y la versión que elijas. Botón «Versiones de
  PHP…» del proyecto: añadir, quitar y elegir.
- Docker, BBDD: una MariaDB común por versión de MariaDB, cada proyecto
  con su BBDD y su usuario, y un solo phpMyAdmin en
  https://pma.docker.local. Un certificado propio para *.docker.local
  (solo vale para esos dominios) que Safari y Chrome aceptan sin aviso.
- Configuración, Docker: la dirección y los puertos del Apache de Docker,
  «Permitir» (dar de alta la dirección) y «Confiar» en el certificado.
- Los proyectos que ya estaban en Docker siguen igual (con XAMPP-X
  delante) hasta que pulses «Pasar al Apache de Docker»: se guarda antes
  una copia de su BBDD en ~/lvm-copias y se carga en la MariaDB común.
- Docker: se pueden parar todos los contenedores de Nexum a mano,
  también la MariaDB común, el Apache de Docker y su phpMyAdmin, y hay
  un «Parar todos». Si lo que paras es común y lo usa un proyecto en
  marcha, avisa de cuáles se quedan sin él. Al parar un proyecto, lo
  común que ya no usa nadie se para también.
- Túnel de Cloudflare: «Compartir» en el visor del proyecto (y en el de
  Docker) enseña la web a un cliente o a un compañero con una dirección
  https://….trycloudflare.com, sin cuenta de Cloudflare y sin abrir
  puertos. Con contraseña (al azar, para copiar y mandar), el panel de
  administración bloqueado y phpMyAdmin siempre bloqueado, y se cierra
  solo (2 h; de 1 a 12 en Configuración). La web no se toca: su dominio
  local se cambia por el del túnel al pasar. cloudflared se descarga de
  GitHub la primera vez (comprobado con su sha256).
- Botones del proyecto a tu gusto: cuáles se ven, en qué orden y cómo
  (con su nombre, solo el icono o con el icono y el nombre, en un
  cuadrado del tamaño que elijas, con vista previa). En el menú ⋮ del
  proyecto, «Personalizar los botones…», y en Configuración. Desmontar,
  ⋮, «Versiones de PHP…» y Arrancar o Parar van con el mismo estilo.
- Arriba, en el recuadro de la versión: lo que gastan Nexum y sus
  servicios juntos (la ventana, XAMPP-X, Docker Desktop, Mailpit y el
  túnel), en % de la CPU y de la RAM del Mac. Al pasar el ratón, cada
  parte.
- Al cargar un proyecto, la página sube sola hasta su visor.
- Actualizaciones: se buscan al abrir la ventana la primera vez de cada
  día y, después, cada 4 veces que la abres. Si dices que no a una
  versión, se vuelve a ofrecer la próxima vez que toque buscar.
- web.local sin proyecto cargado: la página lleva el logotipo y el
  nombre de Nexum Dev Stack, y dice dónde cargar uno.
- En la terminal: docker-nuevo, docker-php-añadir, docker-php-quitar,
  docker-php-elegir, docker-pasar, docker-parar-todo, docker-web y
  tunel-abrir, tunel-cerrar y tunel-config.

1.39.26 (27 oct 2026)
- Ventana: ya no se puede hacer tan estrecha que se rompa. Su ancho
  mínimo sale de la tabla de proyectos (la columna Proyecto, la de las
  versiones y los botones), y la página de Proyectos ya no se queda en
  980 puntos: el nombre del proyecto cargado, «BBDD» y las etiquetas de
  versión («8.5») ya no se parten. Un nombre de carpeta muy largo se
  corta con «…» y se ve entero al pasar el ratón.
- Bases de datos: sin la tarjeta «Copias de seguridad» (están en
  Configuración, con su botón Abrir).
- Correo de pruebas: Mailpit ya se instala. Decía siempre «no lleva una
  firma válida» porque la firma se comprobaba con tu usuario en una
  carpeta que solo puede abrir root. Ahora se comprueba como root (y,
  si alguna versión viniera sin firmar, se le pone una firma local: su
  contenido ya está comprobado con la sha256 de la descarga).

1.39.25 (27 oct 2026)
- Proyectos, menú ⋮: «Borrar el proyecto…» borra el proyecto entero:
  su carpeta, sus vhosts, las líneas de sus dominios en /etc/hosts (un
  dominio real no se queda falseado) y lo que tenga en Docker. Pregunta
  si se borra también su BBDD de la versión activa (la de phpMyAdmin),
  con copia antes por defecto. Hay que escribir el nombre de la carpeta
  para confirmar. Si un paso falla no sigue: la carpeta, lo último.
  En la terminal: borrar-proyecto <carpeta> [--bd <base> --copia].
- Imágenes de producción: uploads e img no van en git, así que lo que
  falte en local se trae de la web real. En WordPress, menú ⋮
  «Imágenes de producción…» (propone el dominio de su BBDD): mientras
  esté cargado, lo que falte de wp-content/uploads se pide a la web
  real, sin descargar nada. En PrestaShop, que se ve con su dominio real
  falseado, «Descargar de producción las imágenes que faltan…»: las de
  productos, categorías y marcas que dice su BBDD, por https con DNS
  cifrado y comprobando el certificado real. Solo imágenes, vídeos y
  PDF; nunca un .php ni fuera de img. En Dominios y hosts, cada .local
  tiene también su botón de imagen. En la terminal: media-produccion,
  media-proyecto y ps-imagenes.
- Docker: al crear un proyecto o montarlo desde Proyectos, los
  desplegables y el dominio enseñan el nombre entero.

1.39.24 (27 oct 2026)
- Cancelar ya no deja nada a medias: desde la ventana, lo que cambia
  algo pide la contraseña de administrador al empezar, no a mitad. Si se
  cancela, no se ha hecho nada. Antes, al desmontar el proyecto y cancelar
  la contraseña, se desmontaba igual. Desmontar es ahora todo o nada,
  como cargar: si un paso falla, el proyecto sigue cargado.
- Cabecera: «Dev Stack» vuelve a la letra de antes.
- Acerca de: más corto («Herramientas de desarrollo web en local») y
  la firma sin HEXER.

1.39.23 (27 oct 2026)
- Proyectos: columna «Tamaño», con lo que ocupa cada proyecto en el
  disco (se mide en segundo plano, de 10 en 10, y cada uno se vuelve a
  medir cada 6 horas). La columna Proyecto, con el nombre entero de la
  carpeta. La etiqueta de Docker de Versiones, con su logotipo.
- Cabecera: «NEXUM» en mayúsculas y en Goldman (Google Fonts, licencia
  SIL Open Font License; va dentro del programa).

1.39.22 (26 oct 2026)
- Bases de datos: tarjeta nueva «Ocupan las BBDD», con lo que ocupan las
  de todas las versiones y una barra del disco con lo que queda libre.
- Proyecto cargado: «Añadir entorno» pasa a un botón + a la izquierda del
  entorno, en su misma fila. Sin el botón «Importar SQL»: para importar,
  la pestaña Bases de datos (o el menú ⋮ de la fila del proyecto).

1.39.21 (26 oct 2026)
- PrestaShop 1.7+ en Docker y en LAMPP a la vez: la tienda ya no deja de
  funcionar en LAMPP (error 500, «Link to database cannot be
  established») después de abrirla en Docker. Su caché (var/cache), que
  guarda la BBDD, va en Docker en un volumen del contenedor; y al cargarla,
  una caché con otra BBDD (la de Docker o la de producción) se aparta a
  ~/lvm-copias y se rehace sola.

1.39.20 (26 oct 2026)
- Al descargar o copiar una BBDD, el administrador de pruebas
  (local@local.test) ya no va en la copia, como en Linux: sus filas de
  usuarios de WordPress y empleados de PrestaShop se quedan fuera (la BBDD
  de trabajo no se toca).

1.39.19 (26 oct 2026)
- Docker: cada proyecto, al desplegar su fila, tiene su visor, como el del
  proyecto cargado: su nombre, versiones, dominio y si está en marcha, con
  «Abrir web», «Panel», «phpMyAdmin», «VS Code», «Log» (los errores de su
  PHP) y Arrancar o Parar. Parado, la web, el panel y phpMyAdmin se
  apagan.
- Docker, Panel: entra en el WordPress o la tienda PrestaShop del
  contenedor con el administrador de pruebas ya escrito (local@local.test,
  contraseña local). Se pone en su BBDD al crearlo con una copia y, si
  falta, al pulsar Panel (lvm-instalador docker-usuario-pruebas <nombre>).
  Las copias que salen de XAMPP-X siguen sin él.
- Docker, phpMyAdmin: al pulsarlo se copia la contraseña de root.
- En la lista de proyectos, «Montar en Docker» en la fila de los que tienen
  contenedores.

1.39.18 (26 oct 2026)
- Proyecto cargado: «Añadir entorno…» e «Importar SQL» pasan al recuadro
  del entorno y la BBDD; la fila de abajo queda para los accesos directos
  del proyecto, con ⋮ a la derecha. El logotipo de WordPress o PrestaShop,
  sin recuadro. Sin la explicación debajo de «Proyectos».

1.39.17 (26 oct 2026)
- Proyecto cargado: botón «Log» junto a sus botones, con el final del
  registro de errores de su web (el de su vhost), para ver al momento por
  qué da un error 500.

1.39.16 (26 oct 2026)
- Al abrir el programa busca solo si hay una versión nueva y la ofrece. Si
  se dice que no, no vuelve a preguntar por esa versión al abrirlo (solo
  avisa); sigue en el menú, Buscar actualizaciones.
- Proyectos: arriba se queda siempre el proyecto cargado, con sus botones;
  pulsar otro en la lista solo lo marca. Cada fila, al pasar el ratón,
  tiene «Cargar» y un menú ⋮ (añadir entorno en otra versión o en Docker,
  importar SQL, vincular sus BBDD, abrir la carpeta…).
- Tema claro: «Encendidos» en azul (el verde no se veía sobre el gris).

1.39.15 (26 oct 2026)
- Copiar una BBDD a una versión con un MariaDB antiguo (como de la 8.2 a la
  7.4) ya no falla con «Unknown command '\-'»: la descarga lleva una sola
  línea del modo sandbox y la carga las quita todas.

1.39.14 (26 oct 2026)
- Interruptores que piden la contraseña de administrador (barrera entre
  webs, correo de pruebas y su modo de WordPress, los .local de Dominios y
  hosts): si se cancela, no cambia nada y el interruptor vuelve a su sitio.
  Si no se puede aplicar, se deja como estaba.
- Proyectos: el asistente de proyecto nuevo (clonar de git, con su versión
  y su BBDD) se abre con el botón azul «Nuevo proyecto…» de la lista.

1.39.13 (25 oct 2026)
- Igual que la 1.39.12, sin datos de ejemplo de proyectos reales en el
  código.

1.39.12 (25 oct 2026)
- Cargar un proyecto es todo o nada: la contraseña se pide antes de cambiar
  nada y, si se cancela o falla un paso, se queda el proyecto que había
  (el enlace del vhost, la versión activa y Apache, como estaban). Antes
  podía quedar a medias: cargado en la ventana y la web sin estilos.

1.39.11 (25 oct 2026)
- Al cargar un proyecto, el visor pasa a él en cuanto termina la carga, con
  sus botones, sin esperar a volver a leer todo.

1.39.10 (25 oct 2026)
- Mailpit: se instala aunque el paquete cambie de forma; si no se puede,
  dice por qué y desde dónde descargarlo a mano.

1.39.9 (25 oct 2026)
- Correo de pruebas con Mailpit: lo que mandan las webs de este Mac
  (formularios, pedidos, contraseñas) no llega a nadie, se ve en su
  bandeja (botón Correo, arriba, con los correos sin leer). Encendido por
  defecto; se apaga en Configuración. Mailpit arranca y para con la
  versión activa, con tu usuario y solo en 127.0.0.1.
- Mailpit se instala desde Configuración: la versión oficial de GitHub
  para Mac, comprobada con su sha256 y su firma, y de root en
  /Library/Nexum/mailpit.
- PHP de todas las versiones: mail() va a Mailpit. PrestaShop: al cargar
  la tienda, su correo va por SMTP a Mailpit (en todas sus tiendas).
- WordPress con plugins de SMTP o Brevo, en Configuración: llevarlos a
  Mailpit (por defecto: WP Mail SMTP, Easy WP SMTP y los de SMTP siguen,
  con su correo a Mailpit; Brevo, FluentSMTP, Post SMTP y los que mandan
  por una API se desactivan en la copia local), desactivarlos todos o no
  tocarlos (avisa: su correo puede llegar de verdad).
- Lo que se cambia en las BBDD para el correo no va en las copias
  (exportar-bd, copiar-bd, Docker): llevan el correo de producción. Al
  apagarlo o elegir «No tocarlos», se deshace al cargar el proyecto.
- En la terminal: lvm-instalador correo (estado, si, no, wordpress
  mailpit|desactivar|nada, instalar, vaciar y bd <base>).
- Docker: sus proyectos aún no mandan a Mailpit.

1.39.8 (25 oct 2026)
- Docker: montar un proyecto ya no falla con «docker-credential-desktop»
  (el gestor usa su propia configuración de Docker, sin el ayudante de
  credenciales de Docker Desktop ni los complementos de ~/.docker).
- Arriba, el menú pasa a la derecha del visor, el visor ya no parte el
  nombre de la versión en dos líneas y la versión del programa va detrás
  de «Entornos PHP y Docker» (ya no abajo de la barra lateral).
- Versiones de PHP: una versión vulnerable ya no sale también como
  «Actualizada», y los tres puntos ya no enseñan «Más» al pasar el ratón.
- Los mensajes al dejar el ratón encima salen junto al cursor, no más abajo.

1.39.7 (25 oct 2026)
- Abajo de la barra lateral, solo la versión: la firma está en Acerca de.
- Al actualizar o arrancar una versión, la ventana de la tarea ya no se queda
  en el 98 %: MariaDB, PHP-FPM, Apache y ProFTPD arrancan sin quedarse con
  su terminal (las versiones instaladas se corrigen solas al protegerlas o
  arrancarlas), y la tarea acaba cuando acaba el instalador. Sin los avisos
  «getcwd» del final.

1.39.6 (25 oct 2026)
- Al instalar o actualizar, cada paso de la lista lleva su logotipo (Apache,
  Perl, ProFTPD, MariaDB, phpMyAdmin y la configuración), no solo PHP.

1.39.5 (25 oct 2026)
- Ya no hace falta gnupg: la firma de lo que se descarga para compilar
  (PHP, Apache y APR, MariaDB y phpMyAdmin) la comprueba el propio
  gestor con el Python del sistema, con las mismas claves de siempre.
  En macOS 14 Homebrew ya no tiene gnupg hecho y lo compilaba entero
  (con python, meson, gnutls...), lo que tardaba mucho.
- Librerías de Homebrew: solo se instalan las que faltan, sin
  actualizar las que ya tienes (openssl@3 sí, si hay una nueva). Si no
  falta nada, ni se llama a Homebrew. Antes se dice qué se instala y
  que, en las versiones de macOS sin paquetes hechos, se compila y
  puede tardar. Sin los avisos repetidos de Homebrew en la consola
  (las herramientas de Xcode, pistas, fórmulas nuevas); los errores
  sí se ven.
- Al cerrar la ventana (botón rojo) la aplicación sigue abierta, con
  su icono en el Dock, como las demás del Mac: se sale con ⌘Q o con
  Salir del menú. Pulsando el icono del Dock vuelve la ventana.
- La barra de arriba ya no lleva el botón de phpMyAdmin: está en
  Bases de datos y en el menú Gestor (Abrir phpMyAdmin).
- Bases de datos y Docker: al entrar en un apartado, las versiones y
  los proyectos se ven plegados (también la versión activa), y solo se
  despliega uno a la vez: abrir otro cierra el que estaba y pulsar el
  abierto lo cierra. Con una búsqueda se siguen viendo desplegados.
- El nombre de arriba a la izquierda: «Nexum» en negrita y «Dev Stack»
  normal y en azul (que se lee en los temas claro y oscuro).

1.39.4 (24 oct 2026)
- Barra de la izquierda: la ballena de Docker, de un color como los
  demás iconos.
- Docker: columna ID de cada contenedor (en lugar de Estado; el punto
  verde junto al nombre dice si está en marcha) y los puertos enteros,
  con las acciones a la derecha.
- Docker: primero en la fila del proyecto, arrancar o parar todos sus
  servicios a la vez.
- Docker, Imágenes: imagen, etiqueta e ID por separado, y botones para
  volver a descargarla de Docker Hub o borrarla (si no la usa ningún
  contenedor). Volúmenes: botón para borrar los que no use ninguno. En la
  terminal: docker-imagenes borrar|descargar <imagen> y
  docker-volumen-borrar <volumen>.

1.39.3 (24 oct 2026)
- El gestor se instala en /Library/Nexum/gestor, de root, con su propio
  bash (5.3, compilado en el Mac del código de GNU con su huella fijada).
  Lo que se ejecuta con tu contraseña ya no sale de ficheros tuyos: ni
  la copia de ~/lvm-instalador (se queda en un aviso que abre el de
  root) ni el bash o el sudo de Homebrew. La primera vez pide la
  contraseña una vez.
- Las versiones y XAMPP-compartido pasan de /Applications (donde puede
  escribir el grupo admin) a /Library/Nexum, con sus BBDD, proyectos,
  vhosts y certificados. En /Applications queda un enlace a cada una
  para tus rutas de siempre; root no pasa nunca por ellos. Si algo
  falla al pasarlas, se deja todo como estaba (lvm-instalador migrar).
- Como root solo se ejecutan programas del sistema o de /Library/Nexum,
  y los de /Library/Nexum se vuelven a comprobar ya como root justo
  antes. Sin el HOME de tu usuario y sin «brew shellenv».
- Al instalar una versión, root comprueba que sus programas solo
  cargan librerías suyas o del sistema (nunca de /opt/homebrew).
- Las actualizaciones las comprueba e instala root en su carpeta, con
  la firma revisada por el propio gestor (ya no hace falta gnupg).
- La ventana usa siempre el gestor de /Library/Nexum/gestor.
- Docker Desktop: hay que añadir /Library/Nexum/XAMPP-compartido/htdocs
  en File sharing.

1.39.2 (24 oct 2026)
- PHP2Shell (CVE-2026-109618 y CVE-2026-109619): las versiones
  vulnerables salen en rojo en Versiones de PHP, y activarlas pide
  confirmación. Las 8.2 a 8.5 se arreglan con el último parche de su
  rama (las XAMPP-X.Y.Z, instalándolo a su lado y pasándole después sus
  BBDD); las 7.4, 8.0 y 8.1, con el parche oficial de seguridad, que se
  pone al actualizarlas (PHP 7.4.33 + parche de seguridad, oct 2026).
- Todas las versiones, contra PHP2Shell: sin el progreso de subida de
  la sesión, arrays de como mucho 6 niveles, peticiones de 64 MB, PHP-FPM
  que renueva sus procesos y htdocs sin CGI ni SSI. Se pone solo.
- Barrera entre webs: otra web ya no puede mandar formularios ni
  peticiones a tus proyectos. Se apaga en Configuración (para la vuelta
  de una pasarela de pago) o con lvm-instalador barrera-web no.
- Docker: el PHP-FPM ya no está abierto en 127.0.0.1. La web va en el
  contenedor (Apache con PHP, php.ini de producción) y solo responde al
  Apache del Mac, con la clave de cada proyecto. Los proyectos de antes
  se cambian solos al arrancarlos (o con Cerrarlo, en Docker).
- Docker: phpMyAdmin ya no entra solo como root (la llave de su fila
  enseña y copia la contraseña), Actualizar imagen (con sus últimos
  parches), sin contraseñas en las órdenes y un botón Docker en el
  proyecto cargado para montarlo o arrancarlo.
- Las descargas de PHP, Apache, MariaDB y phpMyAdmin se comprueban
  también con su firma GPG; si no es buena, no se instala nada.
- Diálogos con el título y el texto centrados, más cortos, y con el
  botón principal diciendo lo que hace («Borrar la BBDD»).
- Versiones de PHP: «Actualizado» en verde. Bases de datos: un poco de
  aire entre los botones y una sola versión abierta a la vez.
- Corregido: las versiones XAMPP-8.4.27 (con el parche en el nombre) no
  pasaban las comprobaciones de seguridad de sus registros y
  certificados.

1.39.1 (24 oct 2026)
- Los avisos y las preguntas, con los botones grandes y el principal en
  azul (o en rojo si borra), sea cual sea el color de acento del Mac.
- El instalador del .dmg también actualiza cuando la versión es la misma
  pero el programa ha cambiado (antes decía «Ya tienes la …» y no lo
  copiaba).

1.39.0 (24 oct 2026)
- Nuevo nombre: Nexum Dev Stack, con logotipo nuevo, como en Linux. La
  aplicación de ~/Applications pasa a llamarse así (la anterior se
  cambia sola). Los comandos (lvm-instalador, lvm) y las carpetas no
  cambian.
- Ventana nueva: cambian la organización y el aspecto, con las mismas
  órdenes de siempre. Arriba, siempre a la vista, el visor de la versión
  montada (PHP, Apache y MariaDB con su punto, encender o apagar y sus
  servicios), el menú (con tema claro u oscuro), Localhost, phpMyAdmin y
  los avisos en un solo botón. A la izquierda, Proyectos, Versiones de
  PHP, Bases de datos, Docker, Dominios y hosts y Configuración. En
  Proyectos, el cargado en grande con su entorno (versión de PHP), su
  BBDD y sus botones, y la lista de todos, que busca por el nombre de la
  carpeta o de su BBDD. Versiones de PHP en una tabla con su soporte y su
  último parche (los componentes y la instalación, en un diálogo); Bases
  de datos y Docker en tablas por versión y por proyecto, con sus
  tarjetas arriba (la de copias de seguridad dice cuánto ocupa
  ~/lvm-copias).
- Versiones de PHP: Actualizar solo sale cuando hay un parche más nuevo,
  y si ya está al día lo dice.
- Nuevo apartado Docker: proyectos con cualquier versión de PHP (de la
  5.6 a la 8.5) en contenedores de Docker Desktop, a la vez que XAMPP-X.
  Cada uno lleva su PHP, su MariaDB con una copia de su BBDD y su
  phpMyAdmin, y se abre por su dominio (carpeta.docker.local, con https)
  desde el Apache de la versión activa, con sus .htaccess de siempre. Su
  wp-config.php (o la configuración de PrestaShop) se sustituye solo
  dentro del contenedor. Arrancar, parar, registros, cambiar de PHP y
  borrar; CPU y memoria de los contenedores, sus imágenes y volúmenes, y
  acciones para cada contenedor. Los contenedores no arrancan solos al
  encender el Mac.
- Docker en el Mac es Docker Desktop: «Instalar Docker» abre su página de
  descarga (se instala como cualquier aplicación) y, si está instalado y
  parado, lo abre. Hay que añadir /Applications/XAMPP-compartido/htdocs
  en sus carpetas compartidas (Settings › Resources › File sharing). El
  PHP-FPM de cada proyecto escucha en un puerto propio de 127.0.0.1 (no
  en un socket, como en Linux: las carpetas compartidas de Docker
  Desktop no pasan sockets al Mac). En la terminal: lvm-instalador
  docker-instalar, docker-crear <carpeta> <php> <mariadb> [--bd <base>
  --desde <versión>], docker-php <nombre> <versión>, docker-arrancar|
  docker-parar|docker-registros|docker-borrar <nombre> y
  docker-contenedor arrancar|parar|reiniciar|registros|borrar
  <contenedor>.
- Ventana de las tareas como en Linux: en azul, con una barra gruesa;
  encima, lo que se hace y el porcentaje con lo que queda («quedan unos
  3 min») y, debajo, el tiempo como un reloj. Las tareas sin progreso
  propio enseñan el porcentaje que escriben (una descarga) o dicen que
  no lo dan. El registro se ve como una terminal: las barras de las
  descargas y los contadores se quedan en una línea que avanza.
- Botones redondeados con borde (azul al pasar el ratón) en toda la
  ventana, sus diálogos y la ventana de las tareas; los principales, en
  azul. Lo elegido y los mensajes de que todo ha ido bien, también en
  azul; el verde queda para lo que está en marcha.
- Dominios y hosts y Configuración llevan su título grande, como las
  demás pestañas; Versiones de PHP, el logotipo de PHP; y los iconos de
  la barra lateral son algo más grandes.
- Bases de datos: columna Tamaño (datos e índices) de cada BBDD y el
  total de cada versión. Se mide cuando su versión está activa y en
  marcha, y se recuerda para las demás (lvm-instalador
  gui-bbdd-tamanos).
- Se quita la carpeta del ayudante de PAM de MariaDB
  (auth_pam_tool_dir), que no se usa: ya no impide proteger ni arrancar
  las versiones (el aviso «versiones sin proteger»). Las versiones
  nuevas se compilan sin él.

1.38.0 (23 oct 2026)
- Nuevo nombre: Nexum Stack (antes Gestor de versiones PHP), como en
  Linux. Cambian el título de la ventana, el nombre de la aplicación de
  ~/Applications (la anterior se cambia sola) y los textos; los comandos
  (lvm-instalador, lvm), las carpetas y el funcionamiento siguen igual.
- Buscar actualizaciones: busca la versión nueva en GitHub, en las
  publicaciones del repositorio de Nexum Stack, y ya no hace falta dejar
  el .dmg en Descargas. Si hay una más nueva, la descarga a
  ~/.lvm-instalador/actualizaciones, enseña su fecha y su huella, la
  instala y vuelve a abrir la ventana con ella. Sin conexión se sigue
  buscando el .dmg en Descargas.
- Seguridad: cada versión va firmada por quien publica el programa. Se
  comprueba la firma antes de ofrecerla y otra vez antes de instalarla;
  sin firma válida no se instala nada desde la ventana. Tampoco se
  instala una versión más vieja que la que tienes, aunque esté firmada.
  La firma se comprueba con gpgv: si falta, la ventana ofrece instalar
  gnupg con Homebrew. En la terminal: lvm-instalador actualizar-gestor
  <lvm-instalador-mac-X.zip> y lvm-instalador preparar-firma.
- Pestaña Hosts: los dominios .local de los vhosts se pueden apagar. Su
  interruptor estaba bloqueado: el gestor los mantiene siempre en
  /etc/hosts (sin su línea, el Mac los pregunta a la red y cualquiera de
  la misma wifi podría contestar) y volvía a añadirlos aunque se
  quitaran a mano. Ahora, al apagar uno (se avisa antes), sus líneas
  quedan comentadas y se recuerda que está apagado, así que no se vuelve
  a añadir; al encenderlo, vuelve a mantenerse. En la terminal:
  lvm-instalador hosts-falsear <dominio>.local si|no.
- Pestaña Hosts: los .local ya no salen como «Host falseado» (no hay
  ninguna web real a la que lleven): van en «Dominios de los vhosts».
- Cargar proyecto: botón Replicar, junto a «Montar nuevo proyecto», para
  llevar un proyecto a otra versión de PHP. Se elige el proyecto, de qué
  versión se copia su BBDD, a cuál, el nombre que tendrá allí (se
  propone el de esa versión: wp_tienda_8_4 → wp_tienda_8_5) y la
  carpeta con la que se cargará en ella. En la terminal: copiar-bd
  <base> <origen> <destino> --como <nombre> --carpeta <carpeta|->.
- BBDD, copiar: el botón de cada BBDD solo la copia, con el mismo
  nombre, de esa versión a la que elijas, y siempre avisa antes de
  hacerlo (y de si la sustituye). Para copiarla con otro nombre o con
  otra carpeta está Replicar.
- BBDD por versión: en la versión activa, la BBDD que usa el proyecto
  cargado lleva un punto verde.
- Versiones: «Instaladas» e «Instalar nuevas versiones de PHP» se pliegan
  y se despliegan al pulsar su título (plegadas, dicen cuántas hay), y
  siguen así al volver a abrir la ventana.
- Versión activa: los botones de arrancar, reiniciar y parar son más
  grandes.
- Cargar proyecto: cada versión de PHP puede ir con su propia carpeta.
  Las BBDD quedan vinculadas a la carpeta del proyecto en cada versión,
  no en todas a la vez, así que la copia de una BBDD en la 8.5 puede ir
  con una carpeta distinta de la de la 8.4. Con el botón de vincular de
  cada proyecto se elige su BBDD en cada versión, o «Ninguna» para
  desvincularla; los botones del proyecto cargado (phpMyAdmin, panel)
  usan la de la versión activa. En la terminal: lvm-instalador
  vincular-bd <base> <versión> <carpeta|->.
- Versiones instaladas: junto a la versión de PHP sale la fecha en que
  se publicó.
- Instalar: cada versión nueva de PHP va en una carpeta con su versión
  completa (/Applications/XAMPP-8.4.27), al lado de las que ya haya de
  su rama. Las que ya estaban (XAMPP-8.4) no cambian de nombre y se
  siguen poniendo al día con Actualizar.
1.36.0 (22 oct 2026)
- Subir o actualizar una BBDD: si la base ya existe, ahora siempre se
  borran todas sus tablas antes de cargar la copia (antes era una opción,
  «Vaciar la BBDD antes de cargar», que venía apagada). Sin vaciarla, las
  tablas que la copia ya no trae se quedaban, y una copia de phpMyAdmin
  (no lleva DROP TABLE) cargada otra vez tras un error sumaba sus filas a
  las de antes: así se repitieron filas y faltaron claves primarias en una
  base de WordPress. Si la base tiene tablas, antes se guarda una copia
  suya en ~/lvm-copias (…-antes-de-cargar-fecha.sql.gz); si no se puede
  guardar, no se toca nada, y si la carga falla, se dice dónde está.
  Copiar una BBDD a otra versión que ya la tiene sigue igual (ya guardaba
  su copia). En la terminal: importar-bd <fichero> <base> [--crear]
  [--sin-copia]; --vaciar se sigue admitiendo, pero ya no hace falta.
1.35.0 (22 oct 2026)
- Tiendas con dominio real (las falseadas en /etc/hosts): el navegador
  puede aceptar su certificado mientras están falseadas, así que Claude
  in Chrome también puede abrirlas. Al falsear una, sale en el aviso «El
  navegador avisa al abrir estos proyectos»: pulsa Confiar. Al dejar de
  falsearla (o al cargar otro proyecto), el navegador deja de aceptarlo
  (el Mac pide tu contraseña). Así, con su clave (Apache la tiene en
  memoria) no se puede suplantar la web de verdad: mientras está
  falseada, el navegador no va a ella. Si cambias /etc/hosts a mano o
  cancelas la contraseña, sale el aviso «El navegador acepta webs reales
  que ya no están falseadas» con el botón Quitar. En la terminal:
  lvm-instalador confiar-certificados --quitar.
- Prefijo de las tablas al rehacer wp-config.php: siempre uno que traen
  las tablas de la base (las tablas nunca se cambian ni se renombran).
  Si la base tiene tablas de varios WordPress, se usa el del wp-config.php
  del proyecto (antes ganaba el de la copia de este equipo) y, si ninguno
  está en la base, ya no se escribe un prefijo sin tablas: no se toca y
  se avisa. En las tiendas con varios prefijos, el que ya usaba su
  configuración si la base lo tiene.
1.34.0 (22 oct 2026)
- Certificados de los proyectos: el navegador ya no tiene por qué avisar
  con «La conexión no es privada». Desde que Arreglarlos quitó la CA
  común, cada proyecto https lleva su propio certificado y el navegador
  avisaba en todos; con el aviso, las herramientas que manejan el
  navegador (como Claude in Chrome) no podían abrirlos. Nuevo aviso «El
  navegador avisa al abrir estos proyectos» con el botón Confiar: Safari
  y Chrome aceptan el certificado de cada proyecto con un dominio de
  pruebas (web.local, .local, .test), solo ese y solo para su dominio (no
  una CA: no vale para ninguna otra web). Los de un dominio real (las
  tiendas falseadas en /etc/hosts) siguen avisando: Apache tiene su clave
  en memoria, donde la puede leer el PHP de cualquier web, y con ella se
  podría suplantar la web de verdad. El Mac pide tu contraseña una vez por
  proyecto. Después cierra Chrome y vuelve a abrirlo. En la terminal:
  lvm-instalador confiar-certificados [dominio].
1.33.1 (22 oct 2026)
- BBDD, copiar a otra versión: ahora salen también las versiones que ya
  tienen esa BBDD, marcadas «ya la tiene: se sustituye». Al elegir una, se
  pide confirmación, se guarda antes una copia de la suya en ~/lvm-copias
  y se pone en su lugar la de origen (por ejemplo, para volver a copiar a
  la 8.4 una BBDD que ya se había copiado antes desde la 8.2.4). En la
  terminal: copiar-bd <base> <origen> <destino> --sustituir.
1.33.0 (22 oct 2026)
- Administrador de pruebas en los paneles: al cargar una BBDD de
  WordPress o PrestaShop se le añade un administrador local@local.test
  con contraseña local (el mismo en todos los equipos; las BBDD de este Mac
  nunca van a producción). En Cargar proyecto, el botón del panel abre
  una página con los dos ya escritos: solo hay que pulsar Entrar. Con
  las BBDD que ya estaban cargadas, se crea al pulsar el botón. En la
  terminal: lvm-instalador usuario-pruebas <base> [carpeta].
- Seguridad (noveno repaso):
  * El cliente de MariaDB y mysqldump de XAMPP ya no leen ~/.my.cnf:
    cualquier programa tuyo podía prepararlo para que cargaran una
    biblioteca suya con el permiso de administrador que la tarea ya tenía.
    Por lo mismo, git, ssh, certutil y curl van sin tu configuración o
    fuera de la terminal de la tarea.
  * Apartar el XAMPP oficial: su MariaDB y sus programas ya no se
    ejecutan como administrador, sino con el dueño de sus bases. Si sus
    bases son de root, no se copian y se explica qué hacer.
  * Vhosts: los registros y certificados por /Applications/XAMPP (un
    enlace que puede cambiar el grupo admin) pasan a logs/ y etc/, que es
    lo mismo sin pasar por el enlace. Al proteger una versión, se mira
    también lo que el administrador ejecuta dentro de ella.
  * Editar /etc/hosts: una línea con un retorno de carro (\r) en medio se
    saltaba la comprobación y podía llevar cualquier dominio a otra IP.
  * Montar nuevo proyecto: el dominio de una tienda (el de su base) ya no
    se falsea solo, porque la base y el nombre de la carpeta vienen con el
    repositorio. Si es el suyo, se crea en la pestaña Hosts (Nuevo
    proyecto con dominio falseado). Por SSH solo se clona de servidores
    cuya clave ya conoces (y de GitHub, GitLab y Bitbucket), y sin git-lfs.
  * Un Listen abierto a la red en los vhosts compartidos ya no pasa sin
    aviso: la versión no se arranca hasta quitarlo (Editar vhosts).
  * Tampoco se sirven por la web las exportaciones de clientes de WP All
    Import (carpeta wpallimport), las de PrestaShop en .zip o .xml, ni
    .my.cnf, .netrc, .pgpass, credentials*.json, .aws o .docker.
  * Otros: PHP_TIMEZONE, el correo de git en ServerAdmin y
    importar-bd --proyecto se comprueban antes de usarlos; los nombres solo
    admiten letras sin tilde (como en la ventana) aunque el Mac esté en
    español; las versiones de php.net se validan antes de enseñarlas.

1.32.3 (22 oct 2026)
- Seguridad:
  * ~/lvm-copias (copias de BBDD de clientes, vhosts y /etc/hosts
    anteriores) es siempre solo tuya, aunque ya existiera con otros
    permisos. Las copias que se descargan con exportar-bd, también.
  * Vaciar la base antes de cargar: si el volcado no se puede cargar
    (motores FEDERATED, CONNECT o SPIDER activos), ya no se borra antes.
  * Pestaña Hosts: los .local ya no se apagan (no existen fuera y, sin su
    línea, el equipo los preguntaba a la red, donde cualquiera de la misma
    wifi podía contestar). Los que estaban apagados vuelven a encenderse.
  * La contraseña temporal del usuario de la BBDD ya no se ve con ps
    mientras se carga un volcado.

1.32.2 (22 oct 2026)
- Versiones, Instalar: cada fila lleva como título la versión completa
  («PHP 8.5.12») y, a su lado, la fecha en que se publicó y si es un
  parche de seguridad. Debajo, su MariaDB y su Perl.

1.32.1 (21 oct 2026)
- Versiones, Instalar: la fecha de publicación va junto a la versión de
  PHP, y «Parche de seguridad» es solo texto azul (sin fondo).
- Cargar proyecto: el título va fuera del recuadro, como en los demás
  apartados; el recuadro tiene más aire arriba y abajo, y el buscador y
  «Montar nuevo proyecto» van más separados de los botones del proyecto.

1.32.0 (21 oct 2026)
- Seguridad (octavo repaso):
  * Cerrar procesos: un programa que se pusiera un nombre trucado podía
    hacer que el gestor cerrara como administrador otros procesos, o todos
    los del equipo. Ahora los nombres se limpian y solo se cierran números
    de proceso de verdad.
  * Copiar una BBDD a otra versión: el programa auxiliar del cliente de
    MariaDB estaba en tu carpeta, y otro programa tuyo podía cambiarlo y
    conseguir permisos de administrador. Ahora va en una carpeta del
    administrador. Si se cancela la copia, no queda el volcado temporal.
  * Subir un volcado: sus vistas y funciones «SQL SECURITY INVOKER» se
    cargan ya como «DEFINER», así que, aunque la web o phpMyAdmin las lean
    a mitad de la carga, no se ejecutan como root. Al acabar, el usuario
    de la BBDD se vuelve a crear con permisos solo sobre su BBDD.
  * El MariaDB temporal (copiar o descargar una BBDD de otra versión)
    nunca se arranca como administrador.
  * Si no se puede dejar una versión solo para este equipo, ya no se
    arranca (al cargar un proyecto, Servicios, Arrancar o Reiniciar).
- Mac: el script del XAMPP oficial ya no se ejecuta nunca como
  administrador (se arranca desde su panel, manager-osx; al apartarlo se
  cierran solo sus servidores). Una versión al instalarla y los vhosts
  solo se ejecutan como administrador si son de root (antes un programa
  tuyo podía poner una carpeta en /Applications). Ventana: arreglado un
  nombre repetido (validDbName) que podía impedir compilar.
- Versiones, Instalar: cada versión de PHP lleva la fecha en que se
  publicó y si es un parche de seguridad (según php.net) o solo de errores.
- Cargar proyecto: solo dice a dónde apunta web.local (sin «Cargado
  ahora:», para que quepa el nombre entero) y, junto al nombre, un botón
  para desmontar el proyecto (web.local enseña una página vacía). Los botones van, de
  derecha a izquierda, en este orden: VS Code, phpMyAdmin, wp-admin y
  web.local, y son algo más grandes. Si la versión montada no tiene la
  BBDD del proyecto cargado, sale un aviso en rojo.
- Montar nuevo proyecto: botón junto al buscador de proyectos. Se
  despliega un asistente de tres pasos: la dirección del repositorio de
  GitHub (se clona en htdocs), la versión de PHP y la BBDD nueva, con su
  volcado si lo hay. Al terminar, el proyecto queda cargado. En la
  terminal: lvm-instalador montar-proyecto <url> <carpeta> <version> <base>
  [volcado] y lvm-instalador desmontar-proyecto.
- Los mensajes que salen al dejar el ratón encima tienen el aspecto de la
  ventana: gris oscuro y con las esquinas redondeadas.
- Herramientas, Registro de errores: ya no enseña el último error.
- Comandos: cada uno en su línea, con lo que hace debajo, separados por
  secciones resaltadas.
- Novedades: más espacio entre versiones, puntos y líneas.

1.31.1 (21 oct 2026)
- Herramientas, Registro de errores: primero el registro del vhost del
  proyecto cargado (web.local-error_log), que es donde van los errores de
  PHP de la web (el «error crítico» de WordPress) con PHP-FPM. Se ve el
  último error de PHP resumido: el mensaje, el fichero y la línea. Debajo,
  el general de Apache. «Ver el final» separa en líneas los mensajes de
  PHP-FPM, que llegan todos en una.

1.31.0 (21 oct 2026)
- BBDD: botón para copiar una BBDD a otra versión de PHP que no la tenga,
  para probar si el proyecto funciona con ese PHP. Se elige la versión en
  una ventana; la de origen no se toca. Si la de destino no es la activa,
  se arranca su MariaDB solo para la copia (pide la contraseña). La copia
  se carga igual de protegida que al subir un volcado. Después, al cargar
  el proyecto, se pregunta en qué versión. En la terminal:
  lvm-instalador copiar-bd <base> <origen> <destino>

1.30.3 (21 oct 2026)
- Cargar proyecto con la BBDD en varias versiones: la pregunta es más corta
  y cabe en una línea («¿Qué versión del proyecto y de PHP quieres?»).

1.30.2 (21 oct 2026)
- Pestaña Hosts: aviso «web.local no lleva a este Mac» con el botón
  Arreglarlo, si en /etc/hosts web.local apunta a otra dirección (como
  127.0.1.1, la del nombre del equipo en Ubuntu) o no está. Apache solo
  escucha en 127.0.0.1 y el navegador daba «No se puede acceder a este
  sitio web» (ERR_CONNECTION_REFUSED). Se arregla una sola vez.
- phpMyAdmin abierto por localhost (un marcador antiguo o la costumbre
  de XAMPP) ya no da el aviso de error: lleva directamente a su dirección
  buena, 127.0.0.1/phpmyadmin. Por web.local u otro dominio sigue dando el
  aviso. Pulsa Protegerlas para aplicarlo a las versiones instaladas.

1.30.1 (21 oct 2026)
- Cargar proyecto: el proyecto cargado tiene ahora cuatro botones de icono,
  todos del mismo tamaño (al dejar el ratón encima se ve qué abre cada uno):
  * Bola del mundo: el proyecto en el navegador (web.local). Sustituye al
    botón verde «Abrir web.local».
  * phpMyAdmin: su BBDD directamente.
  * WordPress o PrestaShop: su panel de administración (wp-admin, o el
    back office de la tienda, se llame como se llame su carpeta).
  * Visual Studio Code, como antes.

1.30.0 (21 oct 2026)
- Nuevo aviso en Versiones: «Tablas del sistema de MariaDB antiguas». Las
  de algunas versiones vienen de una MariaDB anterior y el servidor llena
  su registro de errores (en una 8.2.4 llegó a 28 GB). Repararlas las pone
  al día sin tocar las BBDD de los proyectos (copia antes en ~/lvm-copias)
  y vacía el registro si es grande.
- Seguridad (séptimo repaso). Pulsa Protegerlas otra vez para aplicarlo:
  * Volcados: aunque se cierre la ventana a mitad de la carga, no queda
    nada INVOKER ni ningún evento; un evento que ya estuviera en marcha se
    corta, y al terminar el usuario de la BBDD ya no puede crear vistas,
    rutinas ni eventos. Root repasa la base al final. No se carga si
    MariaDB tiene activos FEDERATED, CONNECT o SPIDER.
  * Vhosts: un registro o un certificado entre comillas con espacios ya no
    puede llevar a otra carpeta (Apache lo abre como root). Los
    certificados nuevos, solo de las carpetas del gestor (los que ya
    tenías siguen valiendo), y los registros no pueden llamarse como sus
    ficheros de control.
  * Los dominios .local de los vhosts van siempre en hosts (si no, el Mac
    los pregunta a la red y otro de la misma wifi podría contestar).
  * Protegerlas y Cargar proyecto quitan la escritura para cualquier
    usuario en htdocs (plugins que dejan carpetas en 777).
  * Más ficheros que no se sirven: claves (.pem, .key, .p12, id_rsa, la
    carpeta .ssh), bases SQLite, .ini, .conf y las exportaciones de
    clientes de PrestaShop (customers_export).
  * Un dominio guardado para un proyecto solo se falsea si tiene su vhost
    o se parece a la carpeta.
  * Una carpeta de proyecto manipulada (un FIFO) ya no cuelga la ventana.
  * Funciona en macOS 12.0 a 12.2 (no tienen readlink -f).
  * Root solo escribe vhosts y certificados en XAMPP-compartido si son de
    root y sin enlaces, y no adopta una carpeta ssl con enlaces.
  * La contraseña solo se envía al sudo de la terminal de la propia tarea.
  * Actualizar phpMyAdmin e instalar versiones rechazan enlaces duros.

1.29.0 (21 oct 2026)
- Cargar proyecto: botón con el icono de Visual Studio Code a la derecha
  de «Abrir web.local». Abre la carpeta del proyecto cargado; si ya está
  abierta en VS Code, trae su ventana delante (no abre otra).
- Seguridad (sexto repaso, tras otra auditoría). Pulsa Protegerlas en el
  aviso de Versiones para aplicarlo a las versiones ya instaladas:
  * phpMyAdmin: una web abierta en el navegador ya no puede enviarle una
    consulta (un formulario o un fetch a 127.0.0.1). Desde otra web solo
    se abre su portada; escribiendo la dirección o desde el gestor, igual
    que siempre.
  * MariaDB ya no lee ni escribe ficheros del Mac desde SQL (LOAD_FILE,
    INTO OUTFILE, LOAD DATA LOCAL): secure_file_priv en una carpeta vacía
    de cada versión (xamppfiles/etc/lvm-sin-ficheros).
  * Más ficheros que no se sirven: registros .log, .yml (docker-compose
    lleva las claves), copias de wp-config.php y copias de seguridad de
    las webs (.wpress, Duplicator, UpdraftPlus...).
  * Protegerlas ya no hace de root una versión que no lo es (podría ser
    una falsa puesta por otro programa): avisa de que hay que volver a
    instalarla. Prepara los ficheros como root en una carpeta de root.
  * Root solo ejecuta el httpd, el MariaDB o el script xampp de una
    versión de root, y solo escribe en los vhosts de XAMPP-compartido si
    son de root y sin enlaces; unos vhosts tuyos solo pasan a root si
    no llevan directivas peligrosas.
  * Apartar el XAMPP oficial: sus proyectos se copian en una carpeta de
    root y los mueve tu usuario; sus vhosts se comprueban y se escriben
    de una sola lectura. Las copias de las BBDD las lee su dueño.
  * Instalar versiones y actualizar phpMyAdmin: lo compilado no puede
    llevar enlaces fuera de la versión, y las carpetas tmp las crea root.
  * Volcados: se borran los eventos programados y las tablas que guardan
    sus ficheros fuera de MariaDB (DATA DIRECTORY), y se avisa. Un nombre
    de BBDD como MySQL (con mayúsculas) ya cuenta como del sistema.
  * El MariaDB temporal solo se para por su propio .pid, la ventana no
    abre dos paneles de contraseña a la vez y los nombres raros de un
    proyecto o un .zip ya no cambian lo que se ve en la terminal.

1.28.2 (21 oct 2026)
- La ventana no compilaba: ptrace (sin depuradores) no existe en Swift;
  ahora se busca con dlsym.

1.28.1 (21 oct 2026)
- Ventana: los títulos de los apartados ya no llevan icono; lo lleva cada
  fila. Iconos de la barra lateral un poco más grandes. «BBDD» también en
  las cuentas de BBDD que aún decían «base de datos».

1.28.0 (21 oct 2026)
- Seguridad (quinto repaso, tras otra auditoría):
  * sudo y lo que ejecuta como root, con la ruta y el PATH del sistema:
    un sudo o un python3 falso en /opt/homebrew/bin (que es tuyo) ya
    no recibe la contraseña ni corre como root.
  * La contraseña solo se envía si sudo está leyendo de verdad de la
    terminal (se comprueba otra vez al cerrar el panel), y la tarea no
    sigue si no se puede reservar la terminal.
  * MariaDB de las pilas propias arranca y se para con tu usuario.
  * La aplicación se firma con hardened runtime y no admite
    depuradores. Una copia vieja del script no la hace volver atrás.
  * Actualizar desde Descargas: se abre una copia del .dmg y se dice de
    dónde se descargó. ~/.lvm-instalador solo para tu usuario.
  * Volcados: una vista rota en el volcado ya no deja a medias el paso
    de SQL SECURITY INVOKER a DEFINER; lo que no se pueda pasar se
    borra y se avisa.
  * Nuevo aviso «Certificados en los que confía todo el Mac» con el
    botón Arreglarlos (arreglar-certificados): pone un certificado propio
    a cada proyecto https cuyo certificado sea de CA o lo firme una CA
    local sin límite de dominios (como la de mkcert), y la quita de los
    llaveros.
  * Los certificados se crean con tu usuario y solo en la carpeta del
    gestor (nunca donde diga un vhost). Dominios guardados validados.
  * Protegerlas corrige también lo que ya estaba abierto (Listen con la
    IP de la red, bind-address 0.0.0.0, DefaultAddress, puertos de más)
    y cambia la clave SSL de fábrica de XAMPP, igual en todos.
  * Más ficheros que no se sirven: .dump, .old, .orig, copias~,
    error_log, auth.json, .npmrc, .sql.xz y .sql.bz2.
  * Lo compilado se copia a /Applications sin conservar el dueño ni el
    setuid. Root ya no sigue enlaces al escribir la configuración de un
    proyecto ni al vaciar la caché de una tienda.
  * Al instalar no se usa la caché de descargas, y phpMyAdmin lleva
    siempre sus huellas fijadas.
  * Lo que se compila corre sin la terminal de la tarea: aunque un
    programa tuyo lo cambie, no puede usar el permiso de sudo ya dado.
  * Cerrar procesos de otras versiones: un .pid manipulado ya no hace
    que se cierre otro programa del sistema ni la versión montada.
  * Las tareas de la ventana reciben solo las variables necesarias.
  * Protegerlas no deja dos Listen iguales (Apache no arrancaría).
  * Una CA local solo se avisa y se quita si su clave está en tu carpeta
    (también sus ajustes de confianza, los de mkcert).

1.27.1 (20 oct 2026)
- Ventana: «BBDD» en lugar de «base de datos» en todos los textos.

1.27.0 (20 oct 2026)
- Seguridad (cuarto repaso, tras otra auditoría):
  * La terminal de cada tarea es exclusiva: ningún otro programa de tu
    usuario puede abrirla para leer la contraseña. Solo cuenta un sudo
    de root, y la marca de fin lleva su propio código.
  * Vhosts y /etc/hosts: se leen como los lee el sistema (por bytes);
    un carácter de control como \0 hacía que Apache viera una línea
    que la comprobación no veía.
  * Volcados: cada base tiene su usuario (lvm_bd_<base>), con el
    permiso solo para ella (el _ ya no vale por cualquier carácter),
    que se bloquea al terminar: sus disparadores y vistas siguen
    funcionando (en la 1.37 dejaban de hacerlo). Sus vistas y
    funciones SQL SECURITY INVOKER pasan a DEFINER, y el gestor solo
    lee como root tablas de verdad.
  * Reglas web sin distinguir mayúsculas (.ENV, .GIT) y más ficheros
    que no se sirven: copias .sql, debug.log, .vscode, config.inc.php.
    Una web de fuera ya no puede leer la API de tus WordPress (CORS).
  * Los wp-config.php que prepara el gestor desactivan el editor de
    plugins y temas (DISALLOW_FILE_EDIT).
  * phpMyAdmin se actualiza con huellas fijadas y solo si la versión
    es de root. El dominio de una tienda solo se falsea si su nombre
    va en la carpeta (prestashop.com ya no vale).
  * Los ficheros raros en un proyecto (FIFO, /dev/zero) ya no cuelgan
    la lista, y todos los python3 van con -I.

1.26.1 (20 oct 2026)
- Barra lateral: filas más altas e iconos algo más grandes, como los de
  Ajustes del Sistema.

1.26.0 (20 oct 2026)
- phpMyAdmin tiene su propia dirección: http://127.0.0.1/phpmyadmin/
  (los botones ya la abren). En 127.0.0.1 no hay nada más, y en
  localhost, web.local o los dominios falseados da 403. Así, un fallo
  XSS en un proyecto (que va en localhost/carpeta o en su dominio) no
  puede leer phpMyAdmin: para el navegador es otra web.
- Actualizar phpMyAdmin: botón Actualizar en su fila de cada versión y
  aviso en Versiones (Actualizarlos) cuando trae uno con fallos ya
  corregidos. Pone el más nuevo que admite su PHP (5.2.x desde PHP
  7.2.5, 5.1.4 para PHP 7.1), comprobado con su sha256, con la misma
  configuración y una clave de cookies nueva si era la de fábrica. El
  anterior queda en phpmyadmin.anterior.
  * En la terminal: lvm-instalador actualizar-phpmyadmin <versión> o
    --todas.

1.25.0 (20 oct 2026)
- Seguridad (tercer repaso, tras una auditoría completa):
  * Arrancar y parar como administrador solo si la versión es de root:
    en /Applications puede escribir tu usuario, y un programa con él
    podría cambiar el enlace XAMPP, una versión o XAMPP-compartido.
  * La contraseña solo se envía si la pide un sudo de la tarea, con el
    eco de su terminal apagado.
  * Aplicar vhosts y /etc/hosts: la copia se lee una sola vez a una
    carpeta de root y se comprueba y escribe esa misma. En los vhosts
    ya no se admiten Define ni variables.
  * Todas las versiones quedan solo para este Mac; si una no se puede
    proteger, no se arranca. Versiones avisa, con el botón Protegerlas.
  * phpMyAdmin solo desde localhost, sin su asistente setup. Los .env y
    los .git de los proyectos ya no se ven por el navegador. Dominios
    desconocidos rechazados también por https.
  * OpenSSL de cada versión con su propia configuración (no la de
    Homebrew, que es de tu usuario) al arrancar como root.
  * Los volcados se cargan con un usuario temporal que solo puede tocar
    su base (sin DEFINER). MariaDB sin el usuario anónimo ni los
    permisos de las bases test.
  * El dominio de una tienda que viene de su base solo se falsea si se
    parece al nombre de la carpeta (o ya tiene su vhost).
  * Escrituras como root en los proyectos sin seguir enlaces, descargas
    solo por https, versiones de internet comprobadas, registros solo
    para tu usuario y las carpetas siempre en el Finder.

1.24.0 (20 oct 2026)
- Diálogos con más aire: más separación entre textos, campos y
  opciones, y campos algo más altos. En todos los que abre la ventana.
  * Elegir la versión de un proyecto: cada versión es una opción
    separada, con la fecha de su base de datos debajo.

1.23.0 (20 oct 2026)
- Ventana con los apartados en una barra a la izquierda, como Ajustes
  del Sistema, cada uno con su icono de color.
- Logotipos originales de PHP, Apache, MariaDB, phpMyAdmin, Perl,
  XAMPP, WordPress y PrestaShop (de Simple Icons) en blanco sobre el
  color de cada marca: en los apartados, los componentes de cada
  versión, los servicios y los proyectos.
- Contraseña de administrador: ventana nueva con más aire, como la de
  autorización del sistema: el icono de la aplicación con un candado,
  el texto centrado, un campo más estrecho y más alto y botones grandes.

1.22.0 (20 oct 2026)
- Cada apartado lleva un icono de color, como en Ajustes del Sistema,
  y también los componentes de cada versión.
- Servicios: una tarjeta por servicio con su icono, su estado, sus
  puertos y botones con texto (Reiniciar, Parar, Arrancar). Arriba,
  cuántos están en marcha y «Solo desde este Mac».

1.21.0 (20 oct 2026)
- Cargar proyecto: va en un contenedor hundido, con su título dentro,
  el buscador más grande y más separación con la versión activa.
  * En «Cargado ahora:» solo el proyecto va en verde (el vhost y la
    flecha, en el color normal).
  * El botón «Abrir web.local» es verde con letras blancas.
- Botones: al pasar el ratón sale la mano y cambian un poco de color,
  con una transición corta.

1.20.1 (20 oct 2026)
- Cargar proyecto: botón «Abrir Web.local» (borde y letras verdes) a
  la derecha del proyecto cargado. Abre el vhost en el navegador.

1.20.0 (20 oct 2026)
- Seguridad: una web que visites ya no puede leer phpMyAdmin ni tus
  proyectos desde el navegador haciendo que su dominio apunte a
  127.0.0.1 (DNS rebinding).
  * Nuevo primer vhost del puerto 80 (lvm-dominio-desconocido.conf):
    los dominios que no tienen vhost reciben un 403. Solo pasan
    localhost, 127.0.0.1 y [::1].
  * web.local y los dominios falseados funcionan igual que antes.
  * La dirección localhost muestra ahora la carpeta htdocs (antes salía
    el proyecto de web.local). phpMyAdmin sigue en localhost/phpmyadmin.
  * Se añade al montar cada versión (o con lvm-instalador asegurar) y
    ya viene en las versiones nuevas.

1.19.1 (20 oct 2026)
- Ventana: vuelve a compilar en el Mac. Desde la 1.13.0 un error en el
  formulario de subir una base de datos impedía compilarla y el gestor
  abría el panel de Terminal en su lugar.

1.19.0 (20 oct 2026)
- Novedades: la lista de cambios se ve con formato (Markdown): cada
  versión con su título y su fecha, viñetas con sangría, el tema de
  cada cambio en negrita y las rutas y los ficheros en letra de código.
  lvm-instalador novedades la saca en Markdown.
- Se han puesto las tildes que faltaban en la lista de cambios.

1.18.0 (20 oct 2026)
- Seguridad (segundo repaso):
  * Pilas nuevas: tu usuario esta en el grupo admin, así que se quita
    la escritura de grupo y de otros en lo que lee Apache al arrancar
    como root (menos las bases de datos y tmp).
  * Una rama de PHP desconocida ya no recibe sin avisar la pila de la
    última.

1.17.4 (20 oct 2026)
- Cargar proyecto: en «Cargado ahora:» el nombre del proyecto va en
  negrita.

1.17.3 (20 oct 2026)
- Cargar proyecto: si la base del proyecto esta en varias versiones,
  la pregunta es «¿Qué versión del proyecto y de PHP quieres
  cargar?» y muestra la fecha de la copia de la base de cada una.
- «Cargado ahora:» va en gris y sin negrita; el proyecto, en verde.

1.17.2 (20 oct 2026)
- Versiones, Cargar proyecto: «Cargado ahora: …» sale en verde y en
  negrita, para ver de un vistazo que proyecto esta activo.

1.17.1 (20 oct 2026)
- Menú Gestor: Buscar actualizaciones. Busca en Descargas un
  lvm-instalador-mac-*.dmg más nuevo y, si lo hay, muestra su fecha y
  su huella y lo abre para ejecutar su instalador.

1.17.0 (20 oct 2026)
- Versiones: bloque nuevo, Cargar proyecto, el primero de la pestaña.
  Se busca la carpeta del proyecto en htdocs (se ve también el que
  esta cargado ahora) y se pulsa Cargar: el vhost (web.local) apunta
  a su carpeta y se monta la versión de PHP donde esta su base de
  datos. Si la base esta en varias versiones, o en ninguna, se
  pregunta cual montar (se propone la activa o la de su .php-version).
- El aviso «Se puede entrar desde otros equipos de la red» ya solo
  sale en la pestaña Servicios.

1.16.0 (20 oct 2026)
- Seguridad: Apache, MariaDB y el FTP solo aceptan conexiones de este
  Mac (127.0.0.1 y ::1). Antes escuchaban en toda la red: en la de la
  oficina o en una wifi pública, otros equipos podian ver los
  proyectos y entrar por FTP con la contraseña del Mac, que viaja sin
  cifrar. Se cambia solo lo que falta al montar o arrancar una
  versión (copia en ~/lvm-copias); las nuevas ya se instalan así. Si
  algo sigue abierto, la pestaña Versiones avisa con un botón «Cerrar
  a la red». En la terminal: lvm-instalador asegurar.
- Pestaña nueva, Servicios (como el panel de XAMPP): Apache, MariaDB y
  el FTP de la versión montada, si están en marcha y si se puede
  entrar desde la red, con botones para arrancar, parar o reiniciar
  cada uno. El FTP ya no arranca con la versión: se arranca aquí
  cuando haga falta. En la terminal: lvm-instalador servicio
  apache|mariadb|ftp arrancar|parar|reiniciar.
- Subir una base: el volcado solo puede llevar SQL. Un .sql manipulado
  ya no puede ejecutar programas en el Mac (\! orden, system) ni leer
  sus ficheros. La línea del modo sandbox se sigue quitando.
- Los vhosts vuelven a ser del administrador (Apache los lee como root
  al arrancar). Editar vhosts abre una copia; al pulsar Aplicar se
  comprueba, se guarda la anterior en ~/lvm-copias, se escribe con la
  contraseña y se recarga Apache. Si Apache no la acepta, se deja
  como estaba. No se admiten ordenes que cambien todo Apache
  (LoadModule, Include, registros con |orden...). Al apartar un XAMPP
  oficial, sus vhosts solo se copian si cumplen lo mismo.
- wp-config.php, parameters.php y var/cache: si en un proyecto son
  enlaces a otra carpeta, no se tocan. Los nombres de bases, prefijos
  y carpetas que traen los proyectos se comprueban antes de usarlos.
- Las marcas con las que la ventana reconoce la contraseña de sudo y
  el final de cada tarea son distintas en cada ejecución: lo que sale
  en el registro no puede imitarlas.
- ~/lvm-copias y ~/.lvm-instalador (copias de bases y configuraciones
  de los proyectos) solo son accesibles para tu usuario: en el Mac la
  carpeta personal la pueden leer los demas usuarios.

1.15.1 (19 oct 2026)
- Subir una base de datos: el desplegable Proyecto es tan ancho como
  el nombre de carpeta más largo, para verlo entero al elegirlo.
- Al elegir la base se propone el proyecto que se llama como ella
  (wp_mitienda -> dob-wordpress-mitienda, ps_mitienda ->
  dob-prestashop-mitienda), si no hay uno recordado o que ya la use.
  Si se cambia a mano, se respeta.
- Lo mismo que Linux 1.28.1.

1.15.0 (19 oct 2026)
- Bases de datos: cada base lleva debajo la fecha y la hora en que se
  importo y su antiguedad (hace 3 días, hace 4 meses...), en la lista
  de cada versión y en el buscador. Las que se suben con la aplicación
  guardan la fecha exacta en ~/.lvm-instalador/importaciones; para las
  demas se muestra cuando cambiaron por última vez sus tablas (al
  importarlas desde phpMyAdmin, por ejemplo), que se ve aunque su
  MariaDB este parado.
- Lo mismo que Linux 1.28.0.

1.14.0 (19 oct 2026)
- Al subir una base de datos, la ventana de la carga termina con un
  check verde grande y el título en verde (antes solo ponia
  Terminado en gris). Igual en el resto de tareas que terminan bien.
- Subir una base de datos: nuevo campo Proyecto. Si es la base nueva de
  un proyecto, se elige su carpeta (se propone sola si se sabe) y la
  base pasa a ser la suya. Si es un WordPress, su wp-config.php se
  rehace con la plantilla de este equipo (la copia del último
  wp-config.php que funciono en local) cambiando solo la base y, si
  hace falta, el prefijo de las tablas. Comando: importar-bd ...
  --proyecto <carpeta>.
- Cargar proyecto en un WordPress con el código de produccion pegado
  encima: comprueba que wp-config.php usa la base asociada a la
  carpeta y que entra en el MariaDB local. Si no, lo rehace con la
  plantilla (sin plantilla: el mismo fichero con root y localhost; sin
  wp-config.php: wp-config-sample.php con claves nuevas). El anterior
  queda en ~/lvm-copias. Comando: wp-config <carpeta> [base].
- Lo mismo en las tiendas PrestaShop: al subirle una base con Proyecto
  elegido, y al cargarla si se ha volcado encima el código de
  produccion, su app/config/parameters.php (o config/settings.inc.php
  en las 1.6) pasa a usar la base de la carpeta y su prefijo; si sus
  datos no entran en el MariaDB local, root y localhost. El anterior
  queda en ~/lvm-copias y se vacia la cache.
- El wp-config.php que se crea o se rehace lleva WP_SITEURL y WP_HOME
  con la dirección local del proyecto: la del vhost de los proyectos
  tal y como este configurado (https://web.local, http://localhost...)
  o, si el proyecto tiene dominio propio (pestaña Hosts), su dominio.
  Si ya las tiene, se cambia su valor; si no, se añaden delante de los
  datos de la base.
- La base con la que se carga un proyecto queda asociada a su carpeta.
- La base de cada proyecto ya no se lee de las líneas comentadas de
  wp-config.php (// define( 'DB_NAME', ... )).
- Lo mismo que Linux 1.27.0 y 1.27.1.

1.13.0 (19 oct 2026)
- Tiendas PrestaShop recien clonadas: su app/config/parameters.php no
  va en el repositorio y quedaba vacio (\"install\" directory is
  missing). Cargar proyecto lo crea con la base cargada en local (la
  del buscador, la recordada o ps_<final de la carpeta>), el prefijo de
  sus tablas y claves nuevas, y guarda una copia en
  ~/.lvm-instalador/prestashop para reponerla igual si se pierde. Si ya
  tiene base, no se toca. Ahora se reconoce como tienda aunque no tenga
  configuración, por sus carpetas o por \"prestashop\" en el nombre.
- La primera vez que se carga una tienda (y al crear su parameters.php)
  se vacia su var/cache, que en las 1.7 da error 500 con la cache de
  otro equipo. Si no tiene var/cache no pasa nada.
- Bases de datos: botón para vaciar la cache de la tienda en las bases
  ps_ (lista y buscador). Comando: vaciar-cache <carpeta> | --bd <base>.
- Los vhosts que se crean llevan ServerAdmin con el correo de quien usa
  la app (el de su git, user.email; si no hay, usuario@localhost).
- Lo mismo que Linux 1.26.0.

1.12.0 (13 oct 2026)
- La pestaña Instalar pasa a Versiones, debajo de Instaladas: Instalar
  nuevas versiones de PHP. Quedan cuatro pestañas: Versiones, Bases de
  datos, Hosts y Herramientas.
- Las explicaciones de cada bloque van en un símbolo de información
  junto al título: se ven al pasar el raton por encima.
- Solo la versión montada queda en memoria: al montar otra, al pulsar
  Parar o al parar desde la terminal se cierran los procesos de XAMPP
  que sigan vivos (primero de forma normal; a MariaDB se le dan hasta
  90 s para guardar; después a la fuerza). Antes de arrancar se cierran
  los de otras versiones. Versiones avisa si hay procesos de otras
  versiones en memoria, con el botón Cerrarlos. Comandos: procesos y
  cerrar-procesos [--todos].
- Hosts: Nuevo proyecto con dominio falseado. Dominio de produccion,
  carpeta de htdocs (por ejemplo, la de un git clone) o nueva con +, y
  base de datos de la versión activa, nueva con + o ninguna (si la
  carpeta trae su configuración, se propone su base). Crea lo que falte,
  su vhost con certificado y falsea el dominio. Cargar proyecto lo
  vuelve a falsear. Comando: nuevo-dominio <dominio> <carpeta> [base].
- Herramientas: Registro de errores con el error_log de la versión
  montada (Ver el final y Abrir); Registros pasa a llamarse Registros de
  instalaciones; Comandos de lvm-instalador con todos los comandos (la
  ayuda, lvm-instalador --ayuda, ahora completa y por temas).
- Los certificados nuevos son CA:FALSE (Apache ya no avisa con AH01906).

1.11.0 (13 oct 2026)
- Tiendas PrestaShop: al cargar el proyecto se lee su dominio de la base
  (tabla shop_url) y se crea lo que falte: su certificado autofirmado en
  XAMPP-compartido/ssl y su vhost http y https en httpd-vhosts.conf
  (con copia en ~/lvm-copias). Lo que ya existe no se toca. Su dominio
  se falsea en /etc/hosts (127.0.0.1 y ::1) y se vacia la cache de DNS.
- Al cargar cualquier otro proyecto, los dominios de los vhosts dejan
  de estar falseados y vuelven a llevar a la web real. localhost y
  web.local no se tocan nunca.
- Pestaña nueva, Hosts: el dominio falseado arriba, con el interruptor
  encendido y el botón Abrir; debajo, los demas dominios de los vhosts
  con su interruptor para falsearlos o no a mano.
  Comando: lvm-instalador hosts-falsear <dominio> si|no.

1.10.0 (8 oct 2026)
- Pestaña nueva, Herramientas (la última): editar vhosts y hosts, todo
  lo del XAMPP oficial (apartarlo, cargar las copias de sus bases y
  volver a el), las carpetas de copias y de registros, Novedades y
  Acerca de. Volver al XAMPP oficial y sus copias ya no ocupan sitio en
  Versiones ni en Bases de datos.

1.9.0 (8 oct 2026)
- Apartar un XAMPP oficial ya no deja sin acceso a sus proyectos ni a
  sus bases de datos. Sin borrar nada: lo para y, si algo sigue en
  marcha, no mueve nada; copia todas sus bases (.zip, con un MariaDB
  suyo temporal sin red, aunque root tenga contraseña) en
  ~/lvm-copias/XAMPP-oficial-<fecha>; copia sus proyectos a
  XAMPP-compartido/htdocs (sin pisar los que ya estén) y sus vhosts al
  fichero compartido (si Apache no los acepta, lo deja como estaba y
  avisa); y lo mueve a /Applications/XAMPP-oficial-<fecha>. Si falla
  algo antes de moverlo, el XAMPP oficial se queda donde estaba.
- Bases de datos: tarjeta Bases del XAMPP oficial para cargar esas
  copias en la versión activa (las que ya existan no se tocan).
  Comando: importar-copias <carpeta>.
- Versiones: Volver al XAMPP oficial (y en el panel). Para y desactiva
  la versión del gestor, devuelve el XAMPP oficial a /Applications/XAMPP
  y lo arranca. Comando: volver-oficial.

1.8.1 (8 oct 2026)
- Editar vhosts vuelve a abrir /Applications/XAMPP-compartido/
  httpd-vhosts.conf, el fichero real que comparten todas las versiones
  (el mismo que usa Cargar proyecto). La ruta de la 1.7.0 pasaba por el
  enlace /Applications/XAMPP, que no existe tras pulsar Parar o sin
  versión activa, y entonces no encontraba el fichero.

1.8.0 (8 oct 2026)
- Editar vhosts pasa al menú Gestor (debajo de Abrir phpMyAdmin), junto
  a uno nuevo, Editar hosts: abre una copia de /etc/hosts en el editor y,
  al pulsar Aplicar, la escribe con la contraseña de administrador (el
  anterior se guarda en ~/lvm-copias; no deja guardar uno sin la línea
  de localhost) y vacia la cache de DNS. Comando: lvm-instalador hosts.
- Versión activa: arrancar en verde, reiniciar en azul y parar en rojo.
- Descargar bases de datos en .zip: botón de descarga en cada base de
  cada versión y en el buscador. Si la versión no esta en marcha se
  arranca un MariaDB temporal solo para la copia. Comando:
  exportar-bd <base> <fichero.zip|.sql|.sql.gz> [version].
- Buscador de bases: un punto verde marca las de la versión activa (ya
  no pone Activa) y no hay botón Activar. Cargar proyecto lo carga
  directamente en la versión de esa base; si hay que cambiar de PHP,
  avisa antes de parar la actual y activar la del proyecto.
- Instalar: Estable, Solo seguridad y Sin soporte son texto de color,
  sin fondo.

1.7.0 (8 oct 2026)
- Botón Editar vhosts en la versión activa (pestaña Versiones): abre
  /Applications/XAMPP/xamppfiles/etc/extra/httpd-vhosts.conf con el
  editor de textos. Si el fichero es de root, pide la contraseña una vez
  y lo hace tuyo para poder guardarlo. Después, Reiniciar aplica los
  cambios.
- Comando nuevo: lvm-instalador vhosts (lo abre en la terminal).

1.6.0 (8 oct 2026)
- Cargar proyecto en un Mac sin vhosts: ya no sale \"No hay un vhost para
  cargar proyectos\". Crea el vhost web.local (http y https, sin cache en
  el navegador) en /Applications/XAMPP-compartido/httpd-vhosts.conf, su
  certificado autofirmado en XAMPP-compartido/ssl y su línea en
  /etc/hosts (IPv4 e IPv6, para que .local no tarde por Bonjour), y lo
  apunta al proyecto. La ventana lo explica antes de cargar.
- Dialogos más anchos (460 puntos): el texto ya no se parte en cuatro
  líneas.
- Acerca de: ventana propia más grande con el nombre, la versión, que es
  (gestor de paquetes Apache, MariaDB, PHP, Perl, phpMyAdmin y ProFTPD
  al estilo XAMPP de forma independiente), la firma y el año.
- Novedades: ventana más grande y solo con la lista de cambios (comando
  lvm-instalador novedades).

1.5.2 (8 oct 2026)
- La ventana se abre con el alto necesario para ver entera la pestaña
  Bases de datos (sin pasar del alto de la pantalla).

1.5.1 (8 oct 2026)
- Cargar proyecto recarga Apache y PHP-FPM (recarga suave) si no cambia
  de versión: cada proceso de PHP recordaba durante 120 s a donde
  apuntaba web.local y seguia sirviendo el proyecto anterior.

1.5.0 (8 oct 2026)
- Bases de datos: buscador que filtra mientras escribes y dice en que
  versión (y con que PHP) esta cada base, con \"Activar\" o, si ya es
  la activa, \"Elegir como destino\" para cargar una copia.
- \"Cargar proyecto\" en cada resultado: busca la carpeta de htdocs cuya
  configuración (wp-config.php, PrestaShop o .env) usa esa base, activa
  su versión de PHP y apunta el enlace del vhost (web.local) a esa
  carpeta. Si hay varias carpetas o ninguna, la eliges tu y se recuerda
  (~/.lvm-instalador/proyectos). Si la base esta en varias versiones o
  el .php-version del proyecto pide otra, pregunta cual montar.
  Comando: cargar-proyecto <carpeta> [version].
- \"Activa\" ya no parece un botón: es texto verde junto al nombre. El
  botón de phpMyAdmin dice \"Abrir phpMyAdmin\" y solo esta en la activa.

1.4.2 (7 oct 2026)
- PHP 7.4 y 8.0 encuentran argon2 (password_hash con Argon2): su
  configure solo lo buscaba en /usr y /usr/local, no en Homebrew.

1.4.1 (7 oct 2026)
- PHP 7.4 ya no falla al configurar con \"GD build test failed\": su
  configure ejecuta un programa de prueba compilado con
  -fvisibility=hidden, y el enlazador actual de Apple lo deja sin punto
  de entrada. La 7.4 se compila ahora con -fvisibility=default.

1.4.0 (7 oct 2026)
- Si falla una instalación, la ventana muestra el botón \"Ver el log
  del error\": un informe con el sistema, el compilador, lo que se
  instalaba, el paso que ha fallado, sus primeros errores, el final de
  su log y, si fallo la configuración, lo último de su config.log. Se
  copia entero con \"Copiar todo\" para buscar la solucion. También se
  guarda como informe-error.txt junto a los logs de la compilación.

1.3.2 (7 oct 2026)
- Bases de datos: el selector de la base de destino dice \"Elige una
  base de datos\" mientras no se ha elegido ninguna.

1.3.1 (7 oct 2026)
- Si falla la configuración de un componente al instalar, su
  config.log se guarda con los demas logs, porque ahi esta la causa.

1.3.0 (7 oct 2026)
- Instalar: las versiones salen de la más nueva a la más antigua, en
  la ventana y en el panel, y cada rama indica su estado según
  php.net: Estable (correcciones de errores y de seguridad), Solo
  seguridad (con la fecha hasta la que tendrá parches) o Sin soporte.
- Bases de datos: también se cargan copias en .zip (con un solo .sql
  dentro, como las que se descargan del servidor), sin descomprimirlas
  a disco y con barra de progreso.
- Las copias que empiezan por /*M!999999\\- enable the sandbox mode */
  (mariadb-dump moderno) se cargan sin error: esa línea se quita al
  vuelo, sin tocar el fichero.

1.2.0 (7 oct 2026)
- Ventana nativa de macOS (SwiftUI), como la de Linux: pestañas
  Versiones, Bases de datos e Instalar, barra de progreso y la
  contraseña de administrador en una ventana. Se compila en el Mac la
  primera vez; la aplicación de ~/Applications abre la ventana.
- Bases de datos de la versión activa: subir o actualizar una base
  desde un fichero .sql o .sql.gz con barra de progreso (lo cargado,
  el tiempo y lo que queda), crear y borrar bases. Al borrar una base
  con tablas avisa de que es irreversible y ofrece guardar una copia en
  ~/lvm-copias. En el panel, opción \"Bases de datos\".
- Comandos ventana, arrancar, parar, reiniciar, importar-bd, crear-bd,
  borrar-bd y desinstalar <version> --copia.
- Las bases con guion en el nombre se ven bien (no wp_mi@002dweb).
- En la ventana, Parar hace lo mismo que \"lvm disable\": para la
  versión y quita el enlace /Applications/XAMPP, así que php deja de
  responder en la terminal hasta que actives una versión.

1.1.0 (7 oct 2026)
- Los comandos pasan a ser lvm-instalador y lvm, y el archivo
  lvm-instalador.sh. Los comandos pvm-instalador y pvm se quitan.
- Logs en ~/.lvm-instalador y copias en ~/lvm-copias, como en Linux.
1.0.0 (7 oct 2026)
- Primera versión comprobada en un Mac real (Apple Silicon): PHP 8.5
  instalado con su pila completa. Deja de ser beta.

0.9.3 (6 oct 2026)
- MariaDB: la carpeta de cabeceras del SDK de macOS ya no tapa las de
  C++ (no compilaba: \"didn't find libc++'s <stddef.h>\").

0.9.2 (6 oct 2026)
- Si falla una compilación, se muestran sus primeros errores (antes
  solo el final del log, que en paralelo suele ser de avisos).

0.9.1 (6 oct 2026)
- MariaDB: encuentra la libreria fmt de Homebrew (la primera prueba en
  un Mac fallaba al configurar MariaDB con \"CHECK_LIBFMT\").
- El resumen de un error ya no corta la ruta de la carpeta de logs.

0.9.0 (6 oct 2026)
- Número de versión debajo de la firma y opción \"Acerca de\".

0.8.0 (6 oct 2026)
- Icono de PHP en la aplicación.
- Arreglos para Apple Silicon: PCRE de Homebrew en PHP 7.4 y 8.0,
  compilación limitada por memoria, CMake 4 y ProFTPD con sha256.
- Los comandos funcionan aunque el archivo llegue sin permiso de
  ejecución.

0.7.0 (6 oct 2026)
- \"Cambiar la versión activa\" es la primera opción del menú.
- Actualizar: una versión al día no se puede actualizar; avisa en verde.

0.6.0 (5 oct 2026)
- Aviso si se acepta la lista sin marcar ninguna versión.

0.5.0 (5 oct 2026)
- Primera versión para macOS, a partir de la de Linux 1.1.0."

function about_text() {
    echo "$APP_NAME $APP_VERSION\n$SIGNATURE\n\n$ABOUT_TEXT"
}

# Lista de versiones de ABOUT_TEXT en Markdown: «## version · fecha», viñetas (las de «  *», dentro
# de la anterior) en una sola linea, el tema antes de «:» en negrita y rutas y ficheros como codigo
CHANGES_MD_PY='
import re, sys

VERSION = re.compile(r"^(\d+\.\d+\.\d+) \((.+)\)$")
# Rutas (/opt/..., ~/...) y nombres de fichero: en letra de codigo (no lo de detras de https://)
CODE = re.compile(r"(?<![\w`:/])((?:~/|/)[\w.*<>@+-]+(?:/[\w.*<>@+-]*)*|[\w*<>-]+(?:\.[\w*<>-]+)*"
                  r"\.(?:php|conf|cnf|deb|dmg|sql|zip|gz|desktop|policy|md|py|sh|log|pid|run|sha256)\b)")


def inline(text):
    text = CODE.sub(lambda m: "`%s`" % m.group(1), text)
    # Un punto o una coma del final de la frase queda fuera del codigo
    return re.sub(r"`([^`]*?)([.,;:]+)`", r"`\1`\2", text)


def bullet(text, depth):
    # «Tema: explicacion» o «Tema:» -> el tema en negrita
    m = re.match(r"^([^:«`/]{2,45}):(\s+(.*))?$", text)
    if m:
        text = "**%s:**%s" % (m.group(1), " " + m.group(3) if m.group(3) else "")
        return "  " * depth + "- " + text[:text.index(":**") + 3] + inline(text[text.index(":**") + 3:])
    return "  " * depth + "- " + inline(text)


def convert(plain):
    out, item, depth = [], None, 0

    def flush():
        nonlocal item
        if item is not None:
            out.append(bullet(item, depth))
            item = None

    for line in plain.split("\n"):
        m = VERSION.match(line)
        if m:
            flush()
            if out and out[-1] != "":
                out.append("")
            out.append("## %s · %s" % (m.group(1), m.group(2)))
            out.append("")
        elif line.startswith("- "):
            flush()
            item, depth = line[2:].strip(), 0
        elif line.startswith("  * "):
            flush()
            item, depth = line[4:].strip(), 1
        elif line.strip() and item is not None:
            item += " " + line.strip()
        elif not line.strip():
            flush()
        else:
            flush()
            out.append(inline(line.strip()))
    flush()
    return "\n".join(out).strip() + "\n"


sys.stdout.write(convert(sys.stdin.read()))
'

# Solo la lista de versiones con sus cambios, en Markdown (ventana "Novedades")
function changes_text() {
    echo -e "$ABOUT_TEXT" | sed -n '/^VERSIONES$/,$p' | tail -n +3 | python3 -I -c "$CHANGES_MD_PY"
}

function panel_about() {
    ui_msg "$(about_text)"
}

function panel() {
    offer_command_install

    while true; do
        local options=()

        official_xampp && options+=("apartar" "Apartar el XAMPP oficial de $LINK (necesario para activar versiones)")
        ! official_xampp && ls -d "$APPS_DIR"/XAMPP-oficial-* > /dev/null 2>&1 \
            && options+=("volver" "Volver al XAMPP oficial apartado")

        options+=(
            "activar" "Cambiar la version activa"
            "instalar" "Instalar versiones de PHP"
            "estado" "Ver versiones instaladas"
            "bases" "Bases de datos (ver, cargar, crear y borrar)"
            "desinstalar" "Desinstalar versiones"
        )
        [ -n "$(version_dirs)" ] && options+=("actualizar" "Actualizar versiones de PHP")
        options+=("acerca" "Acerca de (version y cambios)" "salir" "Salir")

        local header="Version activa: "
        local active=$(active_dir)
        if [ -n "$active" ]; then
            header+="XAMPP-$(version_name "$active") (PHP $(php_version "$active"))"
        else
            header+="ninguna"
        fi
        [ "$DRY" -eq 1 ] && header+="\nMODO SIMULACION: no se hace ningun cambio"
        header+="\n\n¿Que quieres hacer?"

        # Firma abajo a la derecha de la cabecera, del ancho de la lista de opciones
        local cols=$(tput cols 2> /dev/null || echo 80)
        local sign_w=72
        (( sign_w > cols - 6 )) && sign_w=$(( cols - 6 ))
        if [ "$UI" == "text" ]; then
            header=$(with_signature "$header" $sign_w)
            header+="\n$(printf '%*s' $(( sign_w - ${#APP_VERSION} - 1 > 0 ? sign_w - ${#APP_VERSION} - 1 : 0 )) "")v$APP_VERSION"
        fi

        local choice
        choice=$(ui_menu "$header" "activar" "${options[@]}") || break

        case "$choice" in
            apartar) panel_set_aside ;;
            volver) panel_restore_official ;;
            instalar) panel_install ;;
            activar) panel_use ;;
            estado) ui_msg "$(status_text)" ;;
            bases) panel_databases ;;
            desinstalar) panel_remove ;;
            actualizar) panel_rebuild ;;
            acerca) panel_about ;;
            salir) break ;;
        esac
    done

    [ "$UI" == "whiptail" ] && clear

    return 0
}

