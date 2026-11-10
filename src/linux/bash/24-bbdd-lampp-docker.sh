# ===========================================================================
# BBDD de LAMPP en Docker (en vivo)
# ===========================================================================
# Un WordPress de Docker puede usar la BBDD de una version LAMPP en vivo: la misma que web.local, sin
# copias. Su MariaDB (si no esta en marcha, solo ella y sin red: no choca con la de la version activa
# en el 3306) y, en la red de Docker, un puente hasta su socket (socat, de la imagen de MariaDB; ella ve
# las conexiones como de localhost, como las de web.local). El proyecto entra con el usuario y la
# contraseña de su wp-config.php, los mismos que con web.local. PrestaShop no: guarda su dominio en la
# BBDD y una misma BBDD no puede servir a web.local y a Docker a la vez
LAMPP_BD_BRIDGE_IMAGE=mariadb:11.8
LAMPP_BD_MARK_DIR=$DOCKER_DIR/lampp-bd

# La version que tiene de verdad las BBDD de otra (las que comparten datos)
function lampp_bd_owner() {
    local o
    o=$(data_owner "${TEST_DIR:-/opt}/lampp-$1")
    echo "${o:-$1}"
}

function lampp_bd_data() {
    echo "${TEST_DIR:-/opt}/lampp-$1/var/mysql"
}

function lampp_bd_bridge() {
    echo "nexum-lampp-bd-${1//./-}"
}

# ¿Responde la MariaDB de esa version en su socket?
function lampp_bd_alive() {
    db_socket_alive "$(lampp_bd_data "$1")/mysql.sock"
}

# La MariaDB de una version, en marcha: si no lo esta, se arranca solo ella, sin red (pide la contraseña)
# y se apunta en LAMPP_BD_MARK_DIR (asi no se cierra al arrancar otra version ni al parar LAMPP)
function lampp_bd_up() {
    local f=$1 dir data user server=() i
    dir=${TEST_DIR:-/opt}/lampp-$f data=$(lampp_bd_data "$f")
    lampp_bd_alive "$f" && return 0
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] MariaDB de lampp-$f, sin red (solo su socket), para Docker"
        return 0
    fi
    [ -d "$data" ] || { echo "lampp-$f no tiene BBDD ($data)"; return 1; }
    # (con el dueño de sus datos, nunca root, como db_temp_start)
    user=$($SUDO stat -L -c %U "$data") || return 1
    if [ "$user" == root ] || ! [[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "Las BBDD de lampp-$f son de $user: no se arranca su MariaDB con ese usuario"
        return 1
    fi
    if [ -x "$dir/mysql/bin/mariadbd" ]; then
        server=("$dir/mysql/bin/mariadbd" --defaults-file="$dir/etc/my.cnf")
    elif [ -x "$dir/sbin/mysqld" ]; then
        server=(env LD_LIBRARY_PATH="$dir/lib" "$dir/sbin/mysqld" --defaults-file="$dir/etc/my.cnf"
            --basedir="$dir" --plugin-dir="$dir/lib/mysql/plugin/"
            --innodb-data-home-dir="$data/" --innodb-log-group-home-dir="$data/")
    else
        echo "lampp-$f no tiene el servidor de MariaDB"
        return 1
    fi
    echo "Arrancando la MariaDB de lampp-$f para Docker (sin red: solo su socket)..."
    mkdir -p -m 700 "$LAMPP_BD_MARK_DIR" && : > "$LAMPP_BD_MARK_DIR/$f" || return 1
    # (aparte de esta tarea: sigue al terminar)
    $SUDO setsid -f "${server[@]}" --datadir="$data" --user="$user" --skip-networking \
        --socket="$data/mysql.sock" --pid-file="$data/mysqld.pid" --log-error="$data/mysqld.err" \
        < /dev/null > /dev/null 2>&1
    for i in $(seq 300); do
        lampp_bd_alive "$f" && return 0
        sleep 0.2
    done
    rm -f "$LAMPP_BD_MARK_DIR/$f"
    echo "La MariaDB de lampp-$f no ha arrancado (¿la tiene otro programa?). Lo ultimo de su registro:"
    $SUDO ${SUDO:+-u "$user"} tail -8 "$data/mysqld.err" 2> /dev/null | sed 's/^/  /'
    return 1
}

# El puente de la red de Docker hasta el socket de esa version (nexum-lampp-bd-8-4, en el 3306)
function lampp_bd_bridge_up() {
    local f=$1 name data
    name=$(lampp_bd_bridge "$f") data=$(lampp_bd_data "$f")
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] puente $name hasta $data/mysql.sock"; return 0; }
    [ "$(dk inspect -f '{{.State.Running}}' "$name" 2> /dev/null)" == true ] && return 0
    dk rm -f "$name" > /dev/null 2>&1
    docker_net || return 1
    dk run -d --name "$name" --network nexum --restart no --label "nexum.lampp-bd=$f" \
        -v "$(readlink -f "$data"):/run/nexum-bd:ro" --entrypoint socat "$LAMPP_BD_BRIDGE_IMAGE" \
        TCP-LISTEN:3306,fork,reuseaddr UNIX-CONNECT:/run/nexum-bd/mysql.sock > /dev/null
}

# Proyectos de Docker en marcha que usan la BBDD de esa version (menos el segundo argumento)
function lampp_bd_users() {
    local f=$1 skip=$2 p up
    up=$(dk ps --format '{{.Names}}' 2> /dev/null)
    for p in $(docker_web_projects); do
        [ "$p" != "$skip" ] && [ "$(docker_conf "$p" LAMPP_BD)" == "$f" ] && grep -qE "^nexum-$p-php[0-9]{2}\$" <<< "$up" && echo "$p"
    done
}

# Cuando ya no la usa ningun proyecto en marcha: fuera su puente y, si la arranco Docker, su MariaDB (sin
# contraseña de root: la para con el usuario del proyecto, que en LAMPP es root de MariaDB)
# lampp_bd_release <version> [proyecto que se para]
function lampp_bd_release() {
    local f=$1 slug=$2 dir data admin user pass
    [ -n "$f" ] || return 0
    [ -n "$(lampp_bd_users "$f" "$slug")" ] && return 0
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] fuera el puente de lampp-$f (y su MariaDB, si la arranco Docker)"; return 0; }
    dk rm -f "$(lampp_bd_bridge "$f")" > /dev/null 2>&1
    [ -f "$LAMPP_BD_MARK_DIR/$f" ] || return 0
    # (la de la version activa con LAMPP en marcha no: es la suya)
    [ "$(active_dir)" == "${TEST_DIR:-/opt}/lampp-$f" ] && lampp_running && return 0
    dir=${TEST_DIR:-/opt}/lampp-$f data=$(lampp_bd_data "$f")
    admin=$dir/mysql/bin/mariadb-admin
    [ -x "$admin" ] || admin=$dir/bin/mysqladmin
    for p in ${slug:-} $(docker_web_projects); do
        [ "$(docker_conf "$p" LAMPP_BD)" == "$f" ] || continue
        user=$(docker_conf "$p" USUARIO) pass=$(sed -n 's/^DB_PASS=//p' "$DOCKER_DIR/$p/.env")
        if MYSQL_PWD=$pass LD_LIBRARY_PATH="$dir/lib" "$admin" --no-defaults -S "$data/mysql.sock" -u "$user" shutdown > /dev/null 2>&1; then
            rm -f "$LAMPP_BD_MARK_DIR/$f"
            echo "MariaDB de lampp-$f parada (ya no la usa ningun proyecto de Docker)"
            return 0
        fi
    done
    return 0
}

# Antes de arrancar LAMPP con esa version: si su MariaDB la tenia Docker (sin red), se para para que
# arranque la normal (con su puerto); los proyectos de Docker vuelven a entrar por el mismo socket
function lampp_bd_handover() {
    local f data pid
    f=${1##*/lampp-} data=$(lampp_bd_data "$f")
    [ -n "$f" ] && [ -f "$LAMPP_BD_MARK_DIR/$f" ] || return 0
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] la MariaDB de lampp-$f que tenia Docker pasa a la de LAMPP"; return 0; }
    rm -f "$LAMPP_BD_MARK_DIR/$f"
    lampp_bd_alive "$f" || return 0
    # (solo si de verdad es ese servidor: el de su .pid, sin red y con su socket)
    pid=$(db_temp_pid "$data/mysqld.pid" "$data/mysql.sock") || return 0
    [[ "$($SUDO ps -ww -o args= -p "$pid" 2> /dev/null)" == *--skip-networking* ]] || return 0
    echo "La MariaDB de lampp-$f la tenia Docker: pasa a la de LAMPP"
    $SUDO kill "$pid" 2> /dev/null
    local i
    for i in $(seq 150); do lampp_bd_alive "$f" || break; sleep 0.2; done
    return 0
}

# Al parar LAMPP: si algun proyecto de Docker en marcha usaba la BBDD de esta version, vuelve su MariaDB
# (sin red, para Docker)
function lampp_bd_keep() {
    local f=${1##*/lampp-}
    [ -n "$f" ] && [ -n "$(lampp_bd_users "$f")" ] || return 0
    echo "Algun proyecto de Docker usa la BBDD de lampp-$f: su MariaDB sigue para el (sin red)"
    lampp_bd_up "$f"
}

#@incluir comun/bbdd-lampp-docker/lampp_bd_creds.sh
# docker-bd <nombre> lampp <version> | docker: la BBDD de un WordPress de Docker, en vivo la de esa
# version LAMPP (la misma que web.local) o su copia en la MariaDB comun de Docker (la de antes, que no
# se borra al pasar a LAMPP)
function docker_db_mode() {
    local slug=$1 mode=$2 v=$3 dir creds user db pass owner was
    docker_web_project "$slug" || { echo "No hay ningun proyecto en Docker (con el Apache de Docker) con el nombre $slug"; return 1; }
    dir=$DOCKER_DIR/$slug
    case $mode in
        lampp)
            [ "$(docker_conf "$slug" TIPO)" == wp ] || { echo "Solo WordPress: una tienda guarda su dominio en la BBDD y no puede servir a web.local y a Docker a la vez"; return 1; }
            valid_version_name "$v" && [ -d "${TEST_DIR:-/opt}/lampp-$v" ] || { echo "No existe la version lampp-$v"; return 1; }
            owner=$(lampp_bd_owner "$v")
            creds=$(lampp_bd_creds "$(docker_conf "$slug" CARPETA)") || { echo "No se puede leer el usuario y la base del wp-config.php de $(docker_conf "$slug" CARPETA)"; return 1; }
            user=${creds%%|*} db=$(head -1 <<< "$creds" | cut -d'|' -f2) pass=$(sed -n 2p <<< "$creds")
            echo "$slug: BBDD $db de lampp-$owner, en vivo (la misma que web.local; la copia de Docker se queda)"
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
        *) echo "Uso: nexum docker-bd <nombre> lampp <version> | docker"; return 1 ;;
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

#@incluir comun/bbdd-lampp-docker/docker_shared_warn.sh
# docker-pasar <nombre> [--copia]: un proyecto de antes (PHP-FPM con LAMPP delante, con su MariaDB y su phpMyAdmin)
# pasa al Apache de Docker. Su BBDD se descarga a un fichero (con --copia, en ~/nexum-backups, y se queda;
# sin ella, uno temporal que se borra al acabar bien; si algo falla, ahi esta) y se carga
# en la MariaDB comun; despues se quitan sus contenedores, su vhost de LAMPP y su linea de hosts. Si la
# carpeta ya esta en el sistema nuevo (otra version de PHP del mismo proyecto), solo se le añade su PHP
function docker_pass() {
    local slug=$1 dir folder php maria db target="" p backup copy=0
    [ "$2" == "--copia" ] && copy=1
    if ! docker_valid_slug "$slug" || [ ! -f "$DOCKER_DIR/$slug/proyecto.conf" ] || docker_web_project "$slug"; then
        echo "No hay ningun proyecto de antes (con LAMPP delante) con el nombre $slug"
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
        [ $copy -eq 1 ] && echo "  [simulacion] copia de $db en ~/nexum-backups, fuera sus contenedores, su vhost y su linea de hosts"
        [ $copy -eq 0 ] && echo "  [simulacion] sin copia: $db pasa por un fichero temporal; fuera sus contenedores, su vhost y su linea de hosts"
        return 0
    fi
    docker_ready || { echo "Docker sin root no esta en marcha"; return 1; }
    docker_web_ports_ok || { echo "Docker sin root aun no puede usar los puertos del Apache de Docker: pulsa «Permitir» en Configuracion"; return 1; }
    sudo_first || return 1
    task_plan "Pasando $folder al Apache de Docker" "Copiar su BBDD" "Quitar el proyecto de antes" "Montarlo en el Apache de Docker"
    task_step
    echo "Copia de su BBDD ($db)"
    if [ $copy -eq 1 ]; then
        mkdir -p -m 700 "$COPIES_DIR" || return 1
        backup="$COPIES_DIR/docker-$slug-$db-$(date +%Y%m%d-%H%M%S).sql.gz"
    else
        # (sin copia: un fichero solo tuyo en ~/.lvm-instalador, que se borra cuando ya esta cargada)
        mkdir -p -m 700 "$LOG_DIR" || return 1
        backup=$(mktemp "$LOG_DIR/pasar-$slug-XXXXXX") || return 1
        mv -f "$backup" "$backup.sql.gz" && backup=$backup.sql.gz || { rm -f "$backup"; return 1; }
    fi
    dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d db > /dev/null || { rm -f "$backup"; return 1; }
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
    [ $copy -eq 1 ] && echo "Copia de $db: $backup"
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
    # (si no se ha cargado, porque ya tenia BBDD, la descarga se queda: es lo unico que hay de ella)
    if [ $copy -eq 0 ] && [ -z "$target" ]; then
        rm -f "$backup"
        echo "Sin copia: la descarga de $db ya esta cargada y se ha borrado (con --copia se guarda en ~/nexum-backups)"
    fi
    echo "$slug ya funciona con el Apache de Docker"
}

# Tunel de Cloudflare: una web de este equipo, a la vista de un cliente o de un compañero con una
# direccion publica (https://<algo>.trycloudflare.com, sin cuenta: cambia cada vez). cloudflared abre
# una conexion de salida a Cloudflare, sin abrir puertos, y lo que llega por ella pasa por un proxy
# del programa (TUNNEL_PY, solo en 127.0.0.1) antes de llegar a Apache:
#  - pide una contraseña (la de ese tunel: al azar o la que se elija al abrirlo) y se cierra solo pasadas
#    las horas que se elijan
#  - el admin de WordPress o PrestaShop, bloqueado (las BBDD llevan el administrador de pruebas, con
#    contraseña conocida), y siempre lo de LAMPP para este equipo (phpMyAdmin...): Apache ve las
#    peticiones del proxy como de 127.0.0.1
#  - cambia el dominio local (web.local, el de la tienda...) por el del tunel en lo que devuelve la web:
#    no se toca ni wp-config.php ni la BBDD, y al cerrarlo no hay nada que deshacer
# Un tunel cada vez. cloudflared va en ~/.lvm-instalador/tunel, con tu usuario (sin root): version fijada
# y sha256 de la publicacion en GitHub (sus digest, iguales a los de sus notas, el 27/10/2026)
TUNNEL_VERSION="2026.10.0"
TUNNEL_SHA_AMD64="d33ff2d14475178d2012c2c56beba87389ac5ded27649519f198a7d3134a99db"
TUNNEL_SHA_ARM64="e6422b9d4f72d3194bc5a38676f13667c06666523217b842a877d72a80b5ac08"
TUNNEL_DIR=$LOG_DIR/tunel
TUNNEL_BIN=$TUNNEL_DIR/cloudflared
# El tunel abierto (lo escribe TUNNEL_PY al tener su direccion, solo tuyo): JSON con pid, url, destino,
# carpeta, fin, su contraseña, sus horas y si bloquea el admin
TUNNEL_STATE=$TUNNEL_DIR/estado
TUNNEL_LOG=$TUNNEL_DIR/registro

function tunnel_installed() {
    [ -f "$TUNNEL_BIN" ] && [ -x "$TUNNEL_BIN" ] && [ ! -L "$TUNNEL_BIN" ]
}

function tunnel_installed_version() {
    tunnel_installed && head -c 40 "$TUNNEL_DIR/version" 2> /dev/null | tr -cd '0-9.'
}

# tunel-instalar: descarga cloudflared de GitHub y comprueba su sha256 antes de dejarlo en su sitio
function tunnel_install() {
    local arch sha url tmp got tls=(--proto '=https' --tlsv1.2)
    case $(uname -m) in
        x86_64|amd64) arch=amd64 sha=$TUNNEL_SHA_AMD64 ;;
        aarch64|arm64) arch=arm64 sha=$TUNNEL_SHA_ARM64 ;;
        *) echo "Cloudflare no publica cloudflared para este equipo ($(uname -m))"; return 1 ;;
    esac
    url=https://github.com/cloudflare/cloudflared/releases/download/$TUNNEL_VERSION/cloudflared-linux-$arch
    # (las pruebas, sin red: otro fichero y su suma)
    if [ -n "$TEST_DIR" ]; then
        url=${LVM_CLOUDFLARED_URL:-$url} sha=${LVM_CLOUDFLARED_SHA:-$sha} tls=()
    fi
    if [ "$(tunnel_installed_version)" == "$TUNNEL_VERSION" ]; then
        echo "cloudflared $TUNNEL_VERSION ya esta instalado en $TUNNEL_DIR"
        return 0
    fi
    task_plan "Instalando cloudflared $TUNNEL_VERSION" "Descargar cloudflared" "Comprobar la descarga" "Instalar cloudflared"
    echo "Instalando cloudflared $TUNNEL_VERSION (tunel de Cloudflare) en $TUNNEL_DIR"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] descarga de $url y comprobacion de su sha256"
        return 0
    fi
    if [ -L "$TUNNEL_DIR" ] || [ -L "$TUNNEL_BIN" ]; then
        echo "$TUNNEL_DIR o su cloudflared son un enlace: no se instala"
        return 1
    fi
    mkdir -p -m 700 "$TUNNEL_DIR" || return 1
    tmp=$(mktemp "$TUNNEL_DIR/cloudflared-descarga.XXXXXX") || return 1
    task_step
    echo "Descargando cloudflared-linux-$arch (unos 40 MB)..."
    if ! curl -fsSL "${tls[@]}" --retry 2 --max-time 900 -o "$tmp" "$url"; then
        rm -f "$tmp"
        echo "No se ha podido descargar cloudflared ($url)"
        return 1
    fi
    task_step
    got=$(sha256sum "$tmp" 2> /dev/null | cut -d' ' -f1)
    if [ "$got" != "$sha" ]; then
        rm -f "$tmp"
        echo "La descarga de cloudflared no coincide con su suma sha256 (${got:-ninguna}): no se instala."
        return 1
    fi
    task_step
    chmod 755 "$tmp" && mv -f "$tmp" "$TUNNEL_BIN" && echo "$TUNNEL_VERSION" > "$TUNNEL_DIR/version" || { rm -f "$tmp"; return 1; }
    echo "cloudflared $TUNNEL_VERSION instalado: $TUNNEL_BIN"
}

# Contraseña nueva, facil de dictar: tres grupos de cuatro letras y numeros sin los que se confunden
function tunnel_new_pass() {
    local s
    s=$(LC_ALL=C tr -dc 'abcdefghjkmnpqrstuvwxyz23456789' < /dev/urandom | head -c 12)
    echo "${s:0:4}-${s:4:4}-${s:8:4}"
}

# PID del tunel abierto (el de TUNNEL_PY, si sigue vivo y es el)
function tunnel_pid() {
    local pid
    pid=$(python3 -I -c 'import json, sys
try:
    print(int(json.load(open(sys.argv[1]))["pid"]))
except Exception:
    pass' "$TUNNEL_STATE" 2> /dev/null)
    [[ "$pid" =~ ^[0-9]+$ ]] && tr '\0' ' ' < "/proc/$pid/cmdline" 2> /dev/null | grep -q "nexum-tunel" && echo "$pid"
}

# tunel-cerrar
function tunnel_close() {
    local pid n
    pid=$(tunnel_pid)
    if [ -z "$pid" ]; then
        rm -f "$TUNNEL_STATE"
        echo "No hay ningun tunel abierto"

        return 0
    fi
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] se cierra el tunel ($pid)"; return 0; }
    kill -TERM "$pid" 2> /dev/null
    for n in $(seq 20); do
        kill -0 "$pid" 2> /dev/null || break
        sleep 0.25
    done
    kill -0 "$pid" 2> /dev/null && kill -KILL "$pid" 2> /dev/null
    rm -f "$TUNNEL_STATE"
    echo "Tunel cerrado: la direccion ya no lleva a ningun sitio"
}

# tunel-abrir <direccion local> [carpeta del proyecto] [--horas 1-12] [--admin bloquear|permitir]: la
# direccion, de una web de este equipo (http://web.local, https://proyecto-php83.docker.local:8443...); la
# carpeta, para saber que admin bloquear y el dominio de una tienda PrestaShop. Cada tunel con lo suyo: sus
# horas (2 si no se dice), el admin (bloqueado si no se dice) y su contraseña, siempre una nueva al azar
# (la de un tunel no vale para el siguiente). Cierra el que hubiera
function tunnel_open() {
    local url=$1 folder="" scheme host port ip clave horas=2 admin=bloquear params dir="" domains n url_t
    shift
    [ -n "$1" ] && [[ "$1" != --* ]] && { folder=${1%/}; shift; }
    while [ $# -gt 0 ]; do
        case $1 in
            --horas) [[ "$2" =~ ^([1-9]|1[0-2])$ ]] || { echo "Las horas van de 1 a 12"; return 1; }; horas=$2; shift 2 ;;
            --admin) [[ "$2" =~ ^(bloquear|permitir)$ ]] || { echo "--admin bloquear o permitir"; return 1; }; admin=$2; shift 2 ;;
            *) echo "Opcion desconocida: $1"; return 1 ;;
        esac
    done
    if [ -z "$url" ]; then
        echo "Uso: nexum tunel-abrir <direccion local> [carpeta] [--horas 1-12] [--admin bloquear|permitir]"

        return 1
    fi
    clave=$(tunnel_new_pass)
    if ! [[ "$url" =~ ^(https?)://([A-Za-z0-9.-]+)(:([0-9]{1,5}))?/?$ ]]; then
        echo "$url no es una direccion valida (como http://web.local)"

        return 1
    fi
    scheme=${BASH_REMATCH[1]} host=$(tr 'A-Z' 'a-z' <<< "${BASH_REMATCH[2]}") port=${BASH_REMATCH[4]}
    [ -n "$port" ] || { [ "$scheme" == https ] && port=443 || port=80; }
    # Solo webs de este equipo: el proxy no lleva a ningun otro sitio
    ip=$(getent ahostsv4 "$host" 2> /dev/null | awk '{ print $1; exit }')
    if ! valid_domain "$host" || [[ ! "$ip" =~ ^127\. ]]; then
        echo "$host no es una web de este equipo (no lleva a 127.x en /etc/hosts): no se comparte"

        return 1
    fi
    if [ -n "$folder" ]; then
        [[ "$folder" == /* ]] || folder=$HTDOCS_DIR/$folder
        dir=$(realpath -e "$folder" 2> /dev/null)
        if [ -z "$dir" ] || [ ! -d "$dir" ] || [[ "$dir" != "$(realpath -e "$HTDOCS_DIR")"/* ]]; then
            echo "$folder no es la carpeta de un proyecto de $HTDOCS_DIR"

            return 1
        fi
    fi
    if ! tunnel_installed; then
        echo "Falta cloudflared: nexum tunel-instalar (o en Configuracion, Tunel de Cloudflare)"

        return 1
    fi
    # Los dominios de la web que se cambian por el del tunel: el suyo y, en una tienda, el de su BBDD
    # (va con el dominio real falseado: la direccion local lleva a el)
    domains=$host
    if [ -n "$dir" ] && is_prestashop "$(basename "$dir")" 2> /dev/null; then
        n=$(ps_domain "$(basename "$dir")" 2> /dev/null)
        valid_domain "$n" && domains+=" $n"
    fi
    echo "Abriendo un tunel de Cloudflare a $scheme://$host$([[ "$port" =~ ^(80|443)$ ]] || echo ":$port")/"
    echo "(con contraseña, el admin $([ "$admin" == bloquear ] && echo bloqueado || echo "SIN bloquear") y se cierra solo en $horas h)"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] cloudflared tunnel --url http://127.0.0.1:<puerto del proxy>"

        return 0
    fi
    tunnel_close > /dev/null
    mkdir -p -m 700 "$TUNNEL_DIR" || return 1
    # (lo que necesita el proxy, en un fichero solo tuyo que borra al leerlo: la contraseña no va en
    # la linea de ordenes)
    params=$(mktemp "$TUNNEL_DIR/abrir.XXXXXX") || return 1
    T_SCHEME=$scheme T_HOST=$host T_PORT=$port T_DOMAINS=$domains T_FOLDER=$dir T_CLAVE=$clave T_HORAS=$horas \
        T_ADMIN=$admin T_BIN=$TUNNEL_BIN T_STATE=$TUNNEL_STATE T_DIR=$TUNNEL_DIR T_ICON=$(tr -d ' \n' <<< "$ICON_PNG_B64") \
        python3 -I -c 'import json, os, sys
e = os.environ
json.dump({"scheme": e["T_SCHEME"], "host": e["T_HOST"], "port": int(e["T_PORT"]), "domains": e["T_DOMAINS"].split(),
           "folder": e["T_FOLDER"], "password": e["T_CLAVE"], "hours": int(e["T_HORAS"]), "admin": e["T_ADMIN"],
           "cloudflared": e["T_BIN"], "state": e["T_STATE"], "dir": e["T_DIR"], "icon": e["T_ICON"]}, open(sys.argv[1], "w"))' \
        "$params" || { rm -f "$params"; return 1; }
    rm -f "$TUNNEL_STATE"
    : > "$TUNNEL_LOG" && chmod 600 "$TUNNEL_LOG"
    # (aparte de esta tarea: sigue abierto al cerrar la ventana, hasta su hora o tunel-cerrar)
    setsid python3 -I -c "$TUNNEL_PY" nexum-tunel "$params" >> "$TUNNEL_LOG" 2>&1 < /dev/null &
    for n in $(seq 120); do
        [ -s "$TUNNEL_STATE" ] && break
        kill -0 $! 2> /dev/null || break
        sleep 0.5
    done
    url_t=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["url"])' "$TUNNEL_STATE" 2> /dev/null)
    if [ -z "$url_t" ]; then
        kill -TERM $! 2> /dev/null
        rm -f "$params" "$TUNNEL_STATE"
        echo "No se ha podido abrir el tunel. Lo ultimo de cloudflared:"
        grep -v '^\s*$' "$TUNNEL_LOG" | tail -6 | sed 's/^/  /'
        echo "(sin conexion a Internet, o Cloudflare no da tuneles rapidos ahora mismo: prueba en un rato)"

        return 1
    fi
    echo "Tunel abierto: $url_t"
    echo "Contraseña para entrar: $clave"
    echo "URL|$url_t"
}

# tunel [estado]: para la ventana y la terminal
#   I|instalado (1/0)|version instalada|version del programa
#   T|url|direccion local|carpeta|fin (epoch)   (si hay uno abierto)
function tunnel_status() {
    local pid
    echo "I|$(tunnel_installed && echo 1 || echo 0)|$(tunnel_installed_version)|$TUNNEL_VERSION"
    pid=$(tunnel_pid)
    [ -n "$pid" ] && python3 -I -c 'import json, sys
s = json.load(open(sys.argv[1]))
print("T|%s|%s|%s|%d" % (s["url"], s["target"], s["folder"], s["expires"]))' "$TUNNEL_STATE" 2> /dev/null
    return 0
}

TUNNEL_PY=$(cat <<'PYEOF'
#@incluir tunel.py
PYEOF
)

# Parches de una rama: P|version|fecha|carpeta|estado (nueva, instalada o existe)|seguridad (1/0)
function gui_patches() {
    local branch=$1 latest version date item folder state sec

    latest=$(php_patches "$branch" | head -1 | cut -d' ' -f1)
    if [ -z "$latest" ]; then
        echo "ERROR|No se ha podido consultar php.net. Comprueba la conexion a internet."

        return 1
    fi

    while read -r version date sec; do
        folder=$(item_folder "$(php_item "$version" "$latest")")
        state=nueva
        if [ -n "$(php_installed_in "$version")" ]; then
            state=instalada
        elif [ -e "${TEST_DIR:-/opt}/lampp-$folder" ]; then
            state=existe
        fi
        echo "P|$version|$date|$folder|$state|$([ "$sec" == "seguridad" ] && echo 1 || echo 0)"
    done < <(php_patches "$branch")
}

# ¿Esta al dia una version de PHP? si|<php> / no|<php nuevo> / parche / no-php / error
function gui_up_to_date() {
    local version=$1
    local dir=${TEST_DIR:-/opt}/lampp-$version

    if ! is_fpm_install "$dir"; then
        echo "no-php"

        return 0
    fi

    local php=$(stack_fields "$dir" | cut -d'|' -f1)
    if [ "$version" != "${php%.*}" ]; then
        echo "parche"

        return 0
    fi

    local full=$(rebuild_version "$dir" "$(php_releases)")
    if [ -z "$full" ]; then
        echo "error"
    elif is_stack_install "$dir" && [ "$(stack_fields "$dir")" == "$(stack_versions "$full")" ] \
            && { ! php2shell_backport "$full" > /dev/null || [ -f "$dir/$PHP2SHELL_MARK" ]; }; then
        # (7.4.33, 8.0.30 y 8.1.34 sin el parche de seguridad no estan al dia: se vuelven a compilar)
        echo "si|$full"
    else
        echo "no|$full"
    fi
}

