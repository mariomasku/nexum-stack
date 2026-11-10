# Limpieza (1.57.9): lo que el programa va dejando y se puede borrar (limpieza, gui-limpieza, limpiar
# <clave>...) y las cachés y registros de un proyecto (gui-limpiar-proyecto, limpiar-proyecto). Todo se
# mide y se borra con CLEAN_PY: sin seguir enlaces, solo dentro de su carpeta y sin pasar a otro disco.
# Lo que es de root, con sudo y con el mismo CLEAN_PY. Sin copias de seguridad: lo borrado no se recupera.
# Las claves, en el orden de la ventana
CLEAN_KEYS=(descargas copias correo registros registros-versiones caches-proyectos temporales sesiones)
CLEAN_PROJECT_KEYS=(cache registros actualizaciones)
# Los temporales, solo si llevan un dia sin cambiar (ellos y lo que tienen dentro)
CLEAN_AGE=86400

# Lo que ocupa (en bytes) dicho para personas: 3,4 MB
function clean_size_text() {
    awk -v n="${1:-0}" 'BEGIN {
        split("B KB MB GB TB", u); i = 1
        while (n >= 1024 && i < 5) { n /= 1024; i++ }
        s = (i == 1) ? sprintf("%d %s", n, u[i]) : sprintf("%.1f %s", n, u[i])
        gsub(/\./, ",", s); print s
    }'
}

function clean_files_text() {
    [ "${1:-0}" == 1 ] && echo "1 fichero" || echo "${1:-0} ficheros"
}

function clean_title() {
    case $1 in
        descargas) echo "Caché de descargas" ;;
        copias) echo "Copias de seguridad" ;;
        correo) echo "Correo de pruebas (Mailpit)" ;;
        registros) echo "Registros del programa" ;;
        registros-versiones) echo "Registros de las versiones" ;;
        caches-proyectos) echo "Cachés de los proyectos" ;;
        temporales) echo "Temporales" ;;
        sesiones) echo "Sesiones de PHP" ;;
        cache) echo "Caché" ;;
        actualizaciones) echo "Restos de actualizaciones" ;;
    esac
}

# Las carpetas de los proyectos de htdocs (sin enlaces, con un nombre valido)
function clean_projects() {
    local d n
    for d in "$HTDOCS_DIR"/*/; do
        d=${d%/} n=${d##*/}
        [ -d "$d" ] && [ ! -L "$d" ] && [[ "$n" =~ ^[A-Za-z0-9_][A-Za-z0-9\ ._-]*$ ]] && echo "$n"
    done
}

# clean_project_rules <carpeta> [<clave>...]: las reglas de CLEAN_PY de un proyecto (todas sus claves si
# no se dice ninguna). Solo las de lo que es: WordPress (wp-content y wp-config.php o wp-includes) o
# PrestaShop (sus clases o su PrestaShopBundle). Nada de wp-content/uploads (salvo los registros de
# WooCommerce, wc-logs) ni de img/ de las tiendas
function clean_project_rules() {
    local dir=$HTDOCS_DIR/$1
    shift
    local want=" ${*:-${CLEAN_PROJECT_KEYS[*]}} "
    if [ -d "$dir/wp-content" ] && { [ -f "$dir/wp-config.php" ] || [ -d "$dir/wp-includes" ]; }; then
        if [[ "$want" == *" cache "* ]]; then
            echo "cache|$dir|vaciar|wp-content/cache||"
        fi
        if [[ "$want" == *" registros "* ]]; then
            echo "registros|$dir|ficheros|wp-content|debug.log|"
            echo "registros|$dir|ficheros|wp-content/uploads/wc-logs|*.log|"
        fi
        if [[ "$want" == *" actualizaciones "* ]]; then
            echo "actualizaciones|$dir|vaciar|wp-content/upgrade||"
            echo "actualizaciones|$dir|vaciar|wp-content/upgrade-temp-backup||"
        fi
    fi
    if [ -f "$dir/classes/PrestaShopAutoload.php" ] || [ -d "$dir/src/PrestaShopBundle" ]; then
        # (los index.php que trae PrestaShop en sus carpetas de cache y de registros se quedan)
        if [[ "$want" == *" cache "* ]]; then
            echo "cache|$dir|vaciar|var/cache||"
            echo "cache|$dir|vaciar|cache/smarty/compile||index"
            echo "cache|$dir|vaciar|cache/smarty/cache||index"
            echo "cache|$dir|vaciar|cache/cachefs||index"
        fi
        if [[ "$want" == *" registros "* ]]; then
            echo "registros|$dir|vaciar|var/logs||index"
            echo "registros|$dir|vaciar|log||index"
            echo "registros|$dir|ficheros|modules/*/logs|*.log|"
            echo "registros|$dir|ficheros|modules/*/log|*.log|"
        fi
    fi
}

# clean_rules <clave>: las reglas de CLEAN_PY de una clave de limpiar (descargas, copias y correo, solo
# para medirlas: se limpian con lo suyo)
function clean_rules() {
    local d t p me
    me=$(id -u)
    case $1 in
        descargas) echo "descargas|$DL_CACHE_DIR|entradas|.|"'(?!.*[.]sha256$).+'"|solo=fich" ;;
        copias) echo "copias|$COPIES_DIR|vaciar|||" ;;
        correo) echo "correo|$MAILPIT_DATA|vaciar|||" ;;
        registros)
            # Solo estos (ninguno es un ajuste): los de las instalaciones y lo que dejan las que fallan
            # (pila-<version>-<fecha>), el de install-db, el de los proyectos sin visitas, los de los
            # proyectos de Node, el de la compilacion de la ventana del Mac y el registro de tareas de la
            # ventana (tareas/). Lo que tenga abierto una tarea o un servidor en marcha se deja; ventana.log,
            # que la ventana tiene abierto mientras esta abierta (en modo de añadir), se vacia
            [ -d "$LOG_DIR" ] && [ ! -L "$LOG_DIR" ] && [ -O "$LOG_DIR" ] || return 0
            echo "registros|$LOG_DIR|ficheros|.|instalacion-*.log|uso"
            echo "registros|$LOG_DIR|ficheros|.|install-db.log|uso"
            echo "registros|$LOG_DIR|ficheros|.|docker-reposo.log|uso"
            echo "registros|$LOG_DIR|entradas|.|pila-[A-Za-z0-9._]+-[0-9]{8}-[0-9]{6}|solo=dir,uso"
            echo "registros|$LOG_DIR|ficheros|node/proyectos|*.log|uso"
            echo "registros|$LOG_DIR|ficheros|app|compilar.log|uso"
            echo "registros|$LOG_DIR|ficheros|tareas|*.txt|uso"
            echo "registros|$LOG_DIR|truncar|.|ventana.log|"
            ;;
        registros-versiones)
            # Se vacian (Apache, PHP-FPM y MariaDB los tienen abiertos): los de Apache (logs/*_log, con los
            # de cada vhost y el de errores de PHP), el de PHP-FPM y el .err de MariaDB. Ni los .pid, ni los
            # cgisock, ni nada mas de los datos de MariaDB
            while IFS= read -r d; do
                [ -n "$d" ] || continue
                echo "registros-versiones|$d|truncar|${CLEAN_STACK_SUB}logs|*_log|"
                echo "registros-versiones|$d|truncar|${CLEAN_STACK_SUB}logs|php-fpm.log|"
                echo "registros-versiones|$d|truncar|${CLEAN_STACK_SUB}var/mysql|*.err|"
            done < <(clean_version_dirs)
            ;;
        caches-proyectos)
            while IFS= read -r p; do
                clean_project_rules "$p" cache | sed 's/^cache|/caches-proyectos|/'
            done < <(clean_projects)
            ;;
        temporales)
            # Los del programa que llevan un dia sin cambiar y no estan en uso (un MariaDB temporal en
            # marcha tiene su socket en /tmp/lvm-mysql-XXXX): las carpetas y ficheros lvm-* que crea en la
            # carpeta temporal y, en ~/.lvm-instalador, temporal/ (actualizar proyecto), las listas y carpetas
            # de ps-imagenes, los ficheros de mktemp de los vhosts, hosts, correo y BBDD de Docker, y las
            # descargas a medias de Mailpit, cloudflared y Node. No las copias de pasar a Docker
            # (pasar-*): si el paso falla a medias, son la unica copia de su BBDD. Ni lvm-copia.* (Mac): si
            # no se pudo mover a htdocs un proyecto del XAMPP oficial, se queda ahi y se dice
            for t in "${CLEAN_TMP_DIRS[@]}"; do
                echo "temporales|$t|entradas|.|lvm-(seguridad|mysql|conocidos|hosts|progreso|vhosts|vhosts-cert|cert|ca|pma|actualizar|mailpit|xampp|pila|icono|cliente|bash|instalar|gpg|dns|github|gh|direccion)[.-].+|edad=$CLEAN_AGE,uso"
            done
            if [ -d "$LOG_DIR" ] && [ ! -L "$LOG_DIR" ] && [ -O "$LOG_DIR" ]; then
                echo "temporales|$LOG_DIR|vaciar|temporal||edad=$CLEAN_AGE,uso"
                echo "temporales|$LOG_DIR|entradas|.|ps-imagenes-[a-z0-9_]{8}|solo=dir,edad=$CLEAN_AGE,uso"
                echo "temporales|$LOG_DIR|entradas|.|(ps-imagenes-lista|vhosts-docker|hosts-docker|vhost-docker|vhosts-media|vhosts-borrar|hosts-borrar|correo)-[A-Za-z0-9]{6}|solo=fich,edad=$CLEAN_AGE,uso"
                echo "temporales|$LOG_DIR|entradas|.|(docker|copia)-.+-[A-Za-z0-9]{6}([.]sql[.]gz)?|solo=fich,edad=$CLEAN_AGE,uso"
                echo "temporales|$LOG_DIR|entradas|.|mailpit-descarga[.][A-Za-z0-9]{6}|edad=$CLEAN_AGE,uso"
                echo "temporales|$LOG_DIR|entradas|tunel|(abrir|cloudflared-descarga)[.][A-Za-z0-9]{6}|edad=$CLEAN_AGE,uso"
                echo "temporales|$LOG_DIR|entradas|node|descarga[.][A-Za-z0-9]{6}|edad=$CLEAN_AGE,uso"
            fi
            ;;
        sesiones)
            # Las de cada version: los XAMPP las guardan en su temp (session.save_path); las pilas propias
            # no lo cambian y van a la carpeta temporal, donde solo se borran las tuyas
            while IFS= read -r d; do
                [ -n "$d" ] && echo "sesiones|$d|ficheros|${CLEAN_STACK_SUB}temp|sess_*|"
            done < <(clean_version_dirs)
            for t in "${CLEAN_TMP_DIRS[@]}"; do
                echo "sesiones|$t|ficheros|.|sess_*|uid=$me"
            done
            ;;
    esac
}

# Los correos de Mailpit: los que dice su API si esta en marcha o, si no, los de su base (sin cambiarla)
function clean_mail_count() {
    local n=""
    if [ -n "$(mailpit_pid)" ]; then
        n=$(curl -fs --noproxy '*' --max-time 5 "${MAIL_UI_URL}api/v1/messages?limit=1" 2> /dev/null \
            | grep -oE '"total":[0-9]+' | head -1 | cut -d: -f2)
    fi
    if [ -z "$n" ] && [ -f "$MAILPIT_DATA/mailpit.db" ] && [ ! -L "$MAILPIT_DATA/mailpit.db" ]; then
        n=$(python3 -I -c 'import sqlite3, sys
c = sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True)
print(c.execute("SELECT COUNT(*) FROM mailbox").fetchone()[0])' "$MAILPIT_DATA/mailpit.db" 2> /dev/null)
    fi
    [[ "$n" =~ ^[0-9]+$ ]] && echo "$n" || echo 0
}

# clean_measure <clave>...: L|<clave>|<bytes>|<ficheros>|<1 si hace falta root> de cada una, sin pedir
# contraseña (lo que no se puede leer con tu usuario no cuenta). Correo: sus correos y su carpeta
function clean_measure() {
    local rules=() k line out b f r
    for k in "$@"; do
        while IFS= read -r line; do
            [ -n "$line" ] && rules+=("$line")
        done < <(clean_rules "$k")
    done
    out=""
    [ ${#rules[@]} -gt 0 ] && out=$(python3 -I -c "$CLEAN_PY" medir "${rules[@]}" < /dev/null 2> /dev/null)
    for k in "$@"; do
        line=$(grep -m 1 "^L|$k|" <<< "$out")
        IFS='|' read -r _ _ b f r <<< "${line:-L|$k|0|0|0}"
        case $k in
            correo) f=$(clean_mail_count); [ "$f" -gt 0 ] || b=0; r=0 ;;
            copias) copies_need_root && r=1 ;;
        esac
        echo "L|$k|${b:-0}|${f:-0}|${r:-0}"
    done
}

function clean_valid_key() {
    local k
    for k in "${CLEAN_KEYS[@]}"; do
        [ "$k" == "$1" ] && return 0
    done
    return 1
}

# limpieza: cada cosa que se puede limpiar, con lo que ocupa y cuantos ficheros
function clean_list() {
    local k b f total=0 line
    echo "Lo que se puede limpiar (nexum limpiar <clave>...):"
    while IFS='|' read -r _ k b f _; do
        total=$((total + b))
        if [ "$f" -gt 0 ]; then
            printf '  %-20s %-30s %s · %s\n' "$k" "$(clean_title "$k")" "$(clean_size_text "$b")" "$(clean_files_text "$f")"
        else
            printf '  %-20s %-30s %s\n' "$k" "$(clean_title "$k")" "vacío"
        fi
    done < <(clean_measure "${CLEAN_KEYS[@]}")
    echo "Total: $(clean_size_text "$total"). Lo que se limpia no se puede recuperar (no se hacen copias)."
}

# ¿Hace falta root para limpiar estas claves? (para pedir la contraseña antes de empezar)
function clean_need_root() {
    local k b f r
    [ $# -gt 0 ] || return 1
    while IFS='|' read -r _ k b f r; do
        [ "${f:-0}" -gt 0 ] && [ "$r" == 1 ] && return 0
    done < <(clean_measure "$@" 2> /dev/null)
    return 1
}

# clean_run <clave> <texto> <reglas...>: limpia con CLEAN_PY como tu usuario y, si algo es de root, otra
# vez con sudo (el mismo CLEAN_PY: solo dentro de sus carpetas y sin seguir enlaces). Con --simular, solo
# dice lo que borraria
function clean_run() {
    local key=$1 title=$2 out out2 rc b f n verb=borrados
    shift 2
    [ $# -gt 0 ] || return 0
    [ "$key" == registros-versiones ] && verb=vaciados
    if [ "$DRY" -eq 1 ]; then
        out=$(python3 -I -c "$CLEAN_PY" simular "$@" < /dev/null 2> /dev/null)
        b=$(awk -F'|' '$1 == "L" { s += $3 } END { print s + 0 }' <<< "$out")
        f=$(awk -F'|' '$1 == "L" { s += $4 } END { print s + 0 }' <<< "$out")
        echo "  [simulacion] $title: se $([ "$verb" == vaciados ] && echo vaciarian || echo borrarian) $(clean_files_text "$f") ($(clean_size_text "$b"))"
        return 0
    fi
    out=$(python3 -I -c "$CLEAN_PY" limpiar "$@" < /dev/null 2>&1)
    rc=$?
    if [ $rc -eq 3 ] && [ -n "$SUDO" ]; then
        echo "$title: parte es de root, se limpia con sudo (solo dentro de sus carpetas, sin seguir enlaces)"
        out2=$(sudo python3 -I -c "$CLEAN_PY" limpiar "$@" < /dev/null 2>&1)
        rc=$?
        out=$(grep -v '^Q|' <<< "$out"; echo "$out2")
    fi
    b=$(awk -F'|' '$1 == "L" { s += $3 } END { print s + 0 }' <<< "$out")
    f=$(awk -F'|' '$1 == "L" { s += $4 } END { print s + 0 }' <<< "$out")
    echo "$title: $verb $(clean_files_text "$f") ($(clean_size_text "$b"))"
    n=$(grep '^U|' <<< "$out" | sort -u | grep -c .)
    if [ "$n" -gt 0 ]; then
        echo "  En uso, se deja$([ "$n" -gt 5 ] && echo " (y $((n - 5)) más)"):"
        grep '^U|' <<< "$out" | sort -u | head -5 | cut -d'|' -f3- | sed 's/^/    /'
    fi
    grep -vE '^[LPUQ]\|' <<< "$out" | grep . | head -5 | sed 's/^/  /'
    if [ $rc -ne 0 ]; then
        n=$(grep -c '^Q|' <<< "$out")
        echo "  No se ha podido limpiar todo$([ "$n" -gt 5 ] && echo " ($n sitios)"):"
        grep '^Q|' <<< "$out" | head -5 | cut -d'|' -f3- | sed 's/^/    /'
        return 1
    fi
    return 0
}

# Mailpit: con su API (correo vaciar). Si no esta en marcha, no se puede
function clean_mail() {
    if [ -z "$(mailpit_pid)" ] && [ "$DRY" -eq 0 ]; then
        echo "Correo de pruebas: Mailpit no esta en marcha (va con la version activa): arrancala y vuelve a limpiarlo"
        return 1
    fi
    mail_command vaciar
}

# limpiar <clave>...: limpia esas cosas (lo que esta vacio, nada). Pide sudo solo si alguna lo necesita
function clean_command() {
    local k b f r keys=() rc=0 line
    if [ $# -eq 0 ]; then
        echo "Uso: nexum limpiar <clave>... (claves: ${CLEAN_KEYS[*]}; nexum limpieza dice lo que ocupa cada una)"
        return 1
    fi
    for k in "$@"; do
        clean_valid_key "$k" || { echo "Clave no valida: $k (claves: ${CLEAN_KEYS[*]})"; return 1; }
        [[ " ${keys[*]} " == *" $k "* ]] || keys+=("$k")
    done
    echo "Limpiando (no se puede recuperar: no se hacen copias)..."
    # (lo medido, antes: dentro del bucle, sudo y lo demas no tienen que leer de una tuberia)
    local measured=() projects=() p
    mapfile -t measured < <(clean_measure "${keys[@]}")
    for line in "${measured[@]}"; do
        IFS='|' read -r _ k b f r <<< "$line"
        if [ "${f:-0}" -eq 0 ]; then
            echo "$(clean_title "$k"): nada que limpiar"
            continue
        fi
        case $k in
            descargas) downloads_command vaciar || rc=1 ;;
            copias) copies_command vaciar || rc=1 ;;
            correo) clean_mail || rc=1 ;;
            caches-proyectos)
                mapfile -t projects < <(clean_projects)
                for p in "${projects[@]}"; do
                    clean_project_key "$p" cache quiet || rc=1
                done
                ;;
            *)
                local rules=()
                while IFS= read -r line; do
                    [ -n "$line" ] && rules+=("$line")
                done < <(clean_rules "$k")
                clean_run "$k" "$(clean_title "$k")" "${rules[@]}" < /dev/null || rc=1
                ;;
        esac
    done
    [ $rc -eq 0 ] && echo "Limpieza terminada" || echo "Limpieza terminada, pero algo no se ha podido limpiar: mira lo de arriba"
    return $rc
}

# Lo que se limpiaria de un proyecto, por clave: <clave>|<bytes>|<ficheros>|<root>|<rutas separadas por ,>
function clean_project_measure() {
    local folder=$1 rules=() line out k b f r
    shift
    while IFS= read -r line; do
        [ -n "$line" ] && rules+=("$line")
    done < <(clean_project_rules "$folder" "$@")
    [ ${#rules[@]} -gt 0 ] || return 0
    out=$(python3 -I -c "$CLEAN_PY" medir "${rules[@]}" < /dev/null 2> /dev/null)
    while IFS='|' read -r _ k b f r; do
        [ -n "$k" ] || continue
        echo "$k|$b|$f|$r|$(awk -F'|' -v k="$k" '$1 == "P" && $2 == k { printf "%s%s", (n++ ? "," : ""), $3 }' <<< "$out")"
    done < <(grep '^L|' <<< "$out")
}

# gui-limpiar-proyecto <carpeta>: P|<clave>|<bytes>|<ficheros>|<rutas> de lo que tiene algo
function gui_clean_project() {
    local folder=${1%/} k b f r paths
    valid_project "$folder" > /dev/null || return 1
    while IFS='|' read -r k b f r paths; do
        [ "${f:-0}" -gt 0 ] && echo "P|$k|$b|$f|$paths"
    done < <(clean_project_measure "$folder")
    return 0
}

function clean_project_need_root() {
    local folder=${1%/} k b f r paths
    valid_project "$folder" > /dev/null 2>&1 || return 1
    shift
    while IFS='|' read -r k b f r paths; do
        [ "${f:-0}" -gt 0 ] && [ "$r" == 1 ] && return 0
    done < <(clean_project_measure "$folder" "$@")
    return 1
}

# clean_project_key <carpeta> <clave> [quiet]: limpia esa clave del proyecto. La var/cache de una tienda,
# con ps_clear_cache (vaciar-cache); lo demas, con clean_run. quiet: sin decir nada si no hay nada
function clean_project_key() {
    local folder=$1 key=$2 quiet=$3 rules=() line b f r paths
    IFS='|' read -r _ b f r paths <<< "$(clean_project_measure "$folder" "$key")"
    if [ "${f:-0}" -eq 0 ]; then
        [ -n "$quiet" ] || echo "$(clean_title "$key") de $folder: nada que limpiar"
        return 0
    fi
    while IFS= read -r line; do
        [ -n "$line" ] && rules+=("$line")
    done < <(clean_project_rules "$folder" "$key")
    if [ "$key" == cache ] && [[ ",$paths," == *",var/cache,"* ]]; then
        ps_clear_cache "$folder" || return 1
        local rest=() x
        for x in "${rules[@]}"; do
            [[ "$x" == *"|vaciar|var/cache||" ]] || rest+=("$x")
        done
        rules=("${rest[@]}")
        [ "$paths" == var/cache ] && return 0
    fi
    clean_run "$key" "$(clean_title "$key") de $folder" "${rules[@]}"
}

# limpiar-proyecto <carpeta> [<clave>...]: sus cachés, registros y restos de actualizaciones (sin claves,
# todo lo que tenga). Las carpetas se vacian, no se borran
function clean_project_command() {
    local folder=${1%/} k keys=() rc=0
    valid_project "$folder" || return 1
    shift
    for k in "$@"; do
        [[ " ${CLEAN_PROJECT_KEYS[*]} " == *" $k "* ]] || { echo "Clave no valida: $k (claves: ${CLEAN_PROJECT_KEYS[*]})"; return 1; }
        [[ " ${keys[*]} " == *" $k "* ]] || keys+=("$k")
    done
    [ ${#keys[@]} -gt 0 ] || keys=("${CLEAN_PROJECT_KEYS[@]}")
    if [ -z "$(clean_project_rules "$folder" "${keys[@]}")" ]; then
        echo "No hay cachés ni registros que limpiar en $folder (no es un WordPress ni una tienda PrestaShop)"
        return 0
    fi
    echo "Limpiando $folder (no se puede recuperar: no se hacen copias)..."
    for k in "${keys[@]}"; do
        clean_project_key "$folder" "$k" || rc=1
    done
    return $rc
}
