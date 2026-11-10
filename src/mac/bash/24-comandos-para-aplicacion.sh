# ===========================================================================
# Comandos para la aplicacion (ventana nativa)
# ===========================================================================

# Datos de la ventana:
#   M|nombre|version|firma
#   A|activa|en marcha (1/0)|XAMPP oficial en /Applications/XAMPP (1/0)
#   V|version|php|apache|mariadb|proftpd|perl|phpmyadmin|motivo para no desinstalar
#   D|version|base de datos|fecha|tipo (i: importada con lvm-instalador, c: ultimo cambio de tablas)
# gui-vuelta: lo que la ventana pregunta cada 20 s (gui-datos, gui-hosts, gui-servicios y gui-proyectos) en
# una sola orden: el script se lee una vez y no cuatro. Cada parte, en su subshell (un exit no corta las
# demas), va detras de una linea «@@<orden>|<codigo de salida>»
function gui_round() {
    local part out rc
    for part in gui-datos:gui_data gui-hosts:gui_hosts gui-servicios:gui_services gui-proyectos:gui_projects; do
        out=$("${part#*:}" 2>&1 < /dev/null)
        rc=$?
        echo "@@${part%%:*}|$rc"
        [ -n "$out" ] && printf '%s\n' "$out"
    done
    return 0
}

function gui_data() {
    local active=$(active_dir) dir name blocker dates=()

    echo "M|$APP_NAME|$APP_VERSION|$SIGNATURE"
    echo "A|$([ -n "$active" ] && version_name "$active")|$(lampp_running && echo 1 || echo 0)|$(official_xampp && echo 1 || echo 0)"
    echo "H|$ACTIVE_VHOSTS|$HOSTS_FILE"
    # T|barrera entre webs puesta (1) o apagada (0)
    echo "T|$(web_barrier_on && echo 1 || echo 0)"
    # Correo de pruebas: E|Mailpit instalado (1/0)|encendido (1/0)|modo de WordPress|Mailpit en marcha
    # (1/0)|version instalada|direccion de su web|version que instala el gestor. Si la version activa
    # esta en marcha y Mailpit no (se ha cerrado la sesion, por ejemplo), se arranca
    [ "$DRY" -eq 0 ] && mailpit_sync --suave > /dev/null 2>&1
    echo "E|$(mailpit_installed && echo 1 || echo 0)|$(mail_on && echo 1 || echo 0)|$(mail_wp_mode)|$([ -n "$(mailpit_pid)" ] && echo 1 || echo 0)|$(mailpit_installed_version)|$MAIL_UI_URL|$MAILPIT_VERSION"
    # Z|procesos de XAMPP que sobran en memoria (de otras versiones)
    local stray=$(stray_summary)
    [ -n "$stray" ] && echo "Z|$stray"
    # N|servicios de la version montada a los que se puede entrar desde otros equipos de la red
    local exposed=$(exposed_summary)
    [ -n "$exposed" ] && echo "N|$exposed"
    # Versiones a las que les falta algo para ser solo de este Mac
    local open_versions=$(unsecured_versions)
    [ -n "$open_versions" ] && echo "U|$open_versions"
    # Tablas del sistema de MariaDB antiguas en la version montada (llenan su registro de errores)
    if db_system_outdated; then
        local err_log=$(db_error_log "$active")
        echo "Y|$(version_name "$active")|$([ -n "$err_log" ] && stat -f %z "$err_log" 2> /dev/null || echo 0)"
    fi
    # Certificados de proyectos en los que confia todo el Mac: C|dominio|motivo y W|CA
    # y G|dominio: proyectos https cuyo certificado propio aun no acepta el navegador, y Q|dominio:
    # los que acepta y ya no deberia (una tienda que ya no esta falseada)
    cert_audit | awk -F'|' '$1 == "C" { print "C|" $2 "|" $5 } $1 == "A" && !seen[$2]++ { print "W|" $2 }
        $1 == "T" && $5 == "0" { print "G|" $2 } $1 == "U" && !gone[$2]++ { print "Q|" $2 }'
    # O|carpeta con las copias de las bases del XAMPP oficial|numero de copias
    for dir in "$COPIES_DIR"/XAMPP-oficial-*/; do
        [ -d "$dir" ] || continue
        set -- "$dir"*.zip
        [ -e "$1" ] && echo "O|${dir%/}|$#"
    done
    # R|XAMPP oficial apartado (se puede devolver a /Applications/XAMPP)
    for dir in "$APPS_DIR"/XAMPP-oficial-*; do
        [ -d "$dir" ] && [ ! -L "$dir" ] && echo "R|$dir"
    done

    for dir in $(version_dirs); do
        name=$(version_name "$dir")
        blocker=$(remove_blocker "$name")
        blocker=${blocker//\\n/ }
        echo "V|$name|$(stack_fields "$dir")|${blocker//|/ }"
        # X|carpeta|estado frente a PHP2Shell (php2shell_state)
        echo "X|$name|$(php2shell_state "$(stack_fields "$dir" | cut -d'|' -f1)" "$dir")"
        dates+=("$name" "$dir/xamppfiles/var/mysql")
    done
    # (las fechas de las BBDD de todas las versiones en un solo python3)
    [ ${#dates[@]} -gt 0 ] && db_dates --varias "${dates[@]}"
    return 0
}

# Ramas de PHP para instalar, de la mas nueva a la mas antigua:
#   B|rama|ultimo parche|con soporte (1/0)|MariaDB|Perl|estado|estado en php.net|fin del soporte
#     activo|fin de los parches de seguridad (de php_branch_states; vacios si no se pudo consultar)|
#     fecha del ultimo parche (AAAA-MM-DD)|seguridad (1 si php.net lo marca como parche de seguridad)
#   estado: nueva (se instala en XAMPP-<ultimo parche>) o instalada (alguna version ya lo tiene)
function gui_branches() {
    local releases=$(php_releases) supported=$(php_supported) branch latest sup state b dir
    local states=$(php_branch_states) st date sec

    if [ -z "$releases" ]; then
        echo "ERROR|No se ha podido consultar php.net. Comprueba la conexion a internet."

        return 1
    fi

    while read -r branch latest _ date sec; do
        [ -z "$branch" ] && continue
        read -r -a b <<< "$(stack_branches "$branch")"
        sup=0
        grep -qxF "$branch" <<< "$supported" && sup=1
        state=nueva
        { [ -e "$BASE_DIR/XAMPP-$latest" ] || php_installed_in "$latest" > /dev/null; } && state=instalada
        st=$(grep "^$branch|" <<< "$states" | cut -d'|' -f2-)
        # (siempre tres campos, aunque no se haya podido consultar: van despues la fecha y la marca)
        [ -z "$st" ] && st="||"
        [ "$sec" == "seguridad" ] && sec=1 || sec=0
        echo "B|$branch|$latest|$sup|${b[1]}|${b[3]}|$state|$st|${date:--}|$sec"
    done <<< "$releases"
}

# Parches de una rama (como en Linux, desde la 1.57.5): todos los de php.net, del mas nuevo al mas
# antiguo. Cada uno se instala en su carpeta (XAMPP-X.Y.Z), con la pila de su rama.
function php_patches() {
    php_all_releases | awk -v b="$1." 'index($1, b) == 1'
}

# gui-parches <rama>: P|version|fecha|estado|seguridad (1/0)|ultimo (1/0)
#   estado: nueva, instalada (ya hay una version con ese PHP) o existe (ya hay una XAMPP-X.Y.Z)
function gui_patches() {
    local branch=$1 version date sec state first=1

    if ! [[ "$branch" =~ ^[0-9]+\.[0-9]+$ ]] || ! awk -v b="$branch" '$1 == b { f = 1 } END { exit !f }' <<< "$(php_releases)"; then
        echo "ERROR|PHP $branch no se puede instalar en este Mac."

        return 1
    fi
    local list=$(php_patches "$branch")
    if [ -z "$list" ]; then
        echo "ERROR|No se ha podido consultar php.net. Comprueba la conexion a internet."

        return 1
    fi
    while read -r version date sec; do
        [ -z "$version" ] && continue
        state=nueva
        if php_installed_in "$version" > /dev/null; then
            state=instalada
        elif [ -e "$BASE_DIR/XAMPP-$version" ]; then
            state=existe
        fi
        echo "P|$version|${date:--}|$state|$([ "$sec" == "seguridad" ] && echo 1 || echo 0)|$first"
        first=0
    done <<< "$list"
}

# Fecha de publicacion en php.net del PHP de cada version instalada: F|carpeta|php|AAAA-MM-DD
function gui_php_dates() {
    local all=$(php_all_releases) dir php date
    [ -n "$all" ] || return 1
    for dir in $(version_dirs); do
        php=$(stack_fields "$dir" | cut -d'|' -f1)
        [[ "$php" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
        date=$(awk -v v="$php" '$1 == v { print $2; exit }' <<< "$all")
        [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && echo "F|$(version_name "$dir")|$php|$date"
    done
    return 0
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
# y sha256 de cada .tgz de la publicacion en GitHub (sus digest, comprobados al descargarlos el
# 27/10/2026; los de sus notas son de antes de firmarlos para el Mac y no coinciden)
TUNNEL_VERSION="2026.10.0"
TUNNEL_SHA_AMD64="903845b81828c8cb3c5d13d816a2de71c06a3da5785469df8eb0e1b736d92f9f"
TUNNEL_SHA_ARM64="a2f79ff7b9420aa537d74af239f376da170bbabeb529aec416002adac6a72e70"
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

# tunel-instalar: descarga cloudflared de GitHub (un .tgz con el programa) y comprueba su sha256
# antes de abrirlo y dejarlo en su sitio
function tunnel_install() {
    local arch sha url tmp got tls=(--proto '=https' --tlsv1.2)
    case $(uname -m) in
        x86_64) arch=amd64 sha=$TUNNEL_SHA_AMD64 ;;
        arm64) arch=arm64 sha=$TUNNEL_SHA_ARM64 ;;
        *) echo "Cloudflare no publica cloudflared para este Mac ($(uname -m))"; return 1 ;;
    esac
    url=https://github.com/cloudflare/cloudflared/releases/download/$TUNNEL_VERSION/cloudflared-darwin-$arch.tgz
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
    tmp=$(mktemp -d "$TUNNEL_DIR/cloudflared-descarga.XXXXXX") || return 1
    task_step
    echo "Descargando cloudflared-darwin-$arch.tgz (unos 20 MB)..."
    if ! curl -fsSL "${tls[@]}" --retry 2 --max-time 900 -o "$tmp/cloudflared.tgz" "$url"; then
        rm -rf "$tmp"
        echo "No se ha podido descargar cloudflared ($url)"
        return 1
    fi
    task_step
    got=$(shasum -a 256 "$tmp/cloudflared.tgz" 2> /dev/null | cut -d' ' -f1)
    if [ "$got" != "$sha" ]; then
        rm -rf "$tmp"
        echo "La descarga de cloudflared no coincide con su suma sha256 (${got:-ninguna}): no se instala."
        return 1
    fi
    task_step
    if ! tar -xzf "$tmp/cloudflared.tgz" -C "$tmp" cloudflared 2> /dev/null || [ ! -f "$tmp/cloudflared" ] || [ -L "$tmp/cloudflared" ]; then
        rm -rf "$tmp"
        echo "El paquete de cloudflared no trae su programa: no se instala."
        return 1
    fi
    chmod 755 "$tmp/cloudflared" && mv -f "$tmp/cloudflared" "$TUNNEL_BIN" && echo "$TUNNEL_VERSION" > "$TUNNEL_DIR/version" \
        || { rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
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
    [[ "$pid" =~ ^[0-9]+$ ]] && ps -p "$pid" -o command= 2> /dev/null | grep -q "nexum-tunel" && echo "$pid"
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
        echo "Uso: lvm-instalador tunel-abrir <direccion local> [carpeta] [--horas 1-12] [--admin bloquear|permitir]"

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
    ip=$(python3 -I -c 'import socket, sys
print(socket.getaddrinfo(sys.argv[1], None, socket.AF_INET)[0][4][0])' "$host" 2> /dev/null)
    if ! valid_domain "$host" || [[ ! "$ip" =~ ^127\. ]]; then
        echo "$host no es una web de este equipo (no lleva a 127.x en /etc/hosts): no se comparte"

        return 1
    fi
    if [ -n "$folder" ]; then
        [[ "$folder" == /* ]] || folder=$HTDOCS_DIR/$folder
        dir=$(realpath_f "$folder" 2> /dev/null)
        if [ -z "$dir" ] || [ ! -d "$dir" ] || [[ "$dir" != "$(realpath_f "$HTDOCS_DIR")"/* ]]; then
            echo "$folder no es la carpeta de un proyecto de $HTDOCS_DIR"

            return 1
        fi
    fi
    if ! tunnel_installed; then
        echo "Falta cloudflared: lvm-instalador tunel-instalar (o en Configuracion, Tunel de Cloudflare)"

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
    # (aparte de esta tarea: sigue abierto al cerrar la ventana, hasta su hora o tunel-cerrar. En el
    # Mac no hay setsid: TUNNEL_PY se aparta solo con os.setsid)
    nohup python3 -I -c "$TUNNEL_PY" nexum-tunel "$params" >> "$TUNNEL_LOG" 2>&1 < /dev/null &
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

