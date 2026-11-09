# ===========================================================================
# Deteccion de lo instalado
# ===========================================================================

function lampp_dirs() {
    find /opt -maxdepth 1 -type d -name "lampp-*" 2> /dev/null | sort -V
}

# Version de PHP nueva (PHP-FPM): pila propia o, las antiguas, copiada de un XAMPP
function is_fpm_install() {
    [ -d "$1/php/sbin" ]
}

function is_stack_install() {
    [ -f "$1/etc/lvm-stack" ]
}

function php_version() {
    if [ -f "$1/etc/lvm-php" ]; then
        cat "$1/etc/lvm-php"
    else
        readlink "$1/bin/php" | sed -n 's|^php-\([0-9.]*\)$|\1|p'
    fi
}

# Versiones de los componentes: "php|apache|mariadb|proftpd|perl|phpmyadmin"
# Se leen de las cabeceras de cada instalacion. Los binarios de XAMPP buscan sus librerias en
# /opt/lampp/lib, asi que solo se ejecutan como ultimo recurso y con LD_LIBRARY_PATH propio.
function stack_fields() {
    local dir=$1

    # Las pilas propias guardan sus versiones al instalarse
    if is_stack_install "$dir"; then
        cat "$dir/etc/lvm-stack"

        return 0
    fi

    local php=$(php_version "$dir")

    local apache=$(awk '/define AP_SERVER_(MAJORVERSION|MINORVERSION|PATCHLEVEL)_NUMBER/ {v = v (v == "" ? "" : ".") $3} END {print v}' \
        "$dir/include/ap_release.h" 2> /dev/null)
    [ -z "$apache" ] && apache=$(LD_LIBRARY_PATH="$dir/lib" "$dir/bin/httpd" -v 2> /dev/null | sed -n 's|.*Apache/\([0-9.]*\).*|\1|p')

    local mariadb=$(grep -hoE 'MYSQL_SERVER_VERSION[[:space:]]+"[0-9.]+' "$dir/include/mariadb_version.h" "$dir/include/server/mysql_version.h" 2> /dev/null \
        | head -1 | grep -oE '[0-9.]+$')
    [ -z "$mariadb" ] && mariadb=$(LD_LIBRARY_PATH="$dir/lib" "$dir/bin/mysql" --version 2> /dev/null | sed -n 's|.*Distrib \([0-9.]*\)-MariaDB.*|\1|p')

    local ftp=$(grep -hoE 'PROFTPD_VERSION_TEXT[[:space:]]+"[0-9.a-z]+' "$dir/include/proftpd/version.h" 2> /dev/null | grep -oE '[0-9][0-9.a-z]*$')
    [ -z "$ftp" ] && ftp=$(LD_LIBRARY_PATH="$dir/lib" "$dir/sbin/proftpd" -v 2> /dev/null | sed -n 's|.*Version \([0-9.a-z]*\).*|\1|p')

    local perl=$(ls -d "$dir"/lib/perl5/5.* 2> /dev/null | sort -V | tail -1 | sed 's|.*/||')
    [ -z "$perl" ] && perl=$(LD_LIBRARY_PATH="$dir/lib" "$dir/bin/perl" -e 'print substr($^V, 1)' 2> /dev/null)

    local pma=$(grep -hoE "(VERSION = |PMA_VERSION', )'[0-9.]+'" "$dir/phpmyadmin/libraries/classes/Version.php" \
        "$dir/phpmyadmin/libraries/classes/Config.php" "$dir/phpmyadmin/libraries/Config.php" 2> /dev/null | head -1 | grep -oE "[0-9][0-9.]+")
    [ -z "$pma" ] && pma=$(grep -rhoE "(VERSION = |PMA_VERSION', )'[0-9.]+'" "$dir/phpmyadmin/libraries" 2> /dev/null | head -1 | grep -oE "[0-9][0-9.]+")

    echo "${php:--}|${apache:--}|${mariadb:--}|${ftp:--}|${perl:--}|${pma:--}"
}

# Tabla de versiones: columna "Version", los seis componentes y una columna final variable
STACK_WIDTHS="11 8 8 9 9 8 12 8"
STACK_HEADER_FIELDS=("Version" "PHP" "Apache" "MariaDB" "ProFTPD" "Perl" "phpMyAdmin")

function stack_header() {
    fmt_row "$STACK_WIDTHS" "${STACK_HEADER_FIELDS[@]}" "$1"
}

# stack_row <carpeta> [texto de la ultima columna] [nombre a mostrar]
function stack_row() {
    local dir=$1 extra=$2 name=${3:-${1#/opt/lampp-}}
    local fields

    IFS='|' read -r -a fields <<< "$(stack_fields "$dir")"
    fmt_row "$STACK_WIDTHS" "$name" "${fields[@]}" "$extra"
}

# Fila de un XAMPP del catalogo que aun no esta instalado
function catalog_row() {
    local entry=$(catalog_entry "$1") extra=$2
    local folder release php apache mariadb ftp perl pma md5 sha

    IFS='|' read -r folder release php apache mariadb ftp perl pma md5 sha <<< "$entry"
    fmt_row "$STACK_WIDTHS" "$folder" "$php" "$apache" "$mariadb" "$ftp" "$perl" "$pma" "$extra"
}

# Componentes de un XAMPP instalado o del catalogo: "php|apache|mariadb|proftpd|perl|phpmyadmin"
function xampp_fields() {
    local folder=$1

    if [ -d "/opt/lampp-$folder" ]; then
        stack_fields "/opt/lampp-$folder"
    else
        catalog_entry "$folder" | awk -F'|' '{print $3"|"$4"|"$5"|"$6"|"$7"|"$8}'
    fi
}

# Versiones que usan las bases de datos de otra (separadas por espacios)
function data_users() {
    local version=$1 dir

    for dir in $(lampp_dirs); do
        [ "$dir" == "/opt/lampp-$version" ] && continue
        [ "$(data_owner "$dir")" == "$version" ] && echo -n "${dir#/opt/lampp-} "
    done
}

# Bases de datos de una instalacion, sin las del sistema. MariaDB guarda en la carpeta los
# caracteres especiales del nombre como @XXXX (wp_mi@002dweb es wp_mi-web): se decodifican
function db_names() {
    local name code char
    find "$1/var/mysql/" -mindepth 1 -maxdepth 1 -type d \
        -not -name mysql -not -name performance_schema -not -name phpmyadmin -not -name test -not -name sys \
        -printf "%f\n" 2> /dev/null | while IFS= read -r name; do
            while [[ "$name" =~ @([0-9a-f]{4}) ]]; do
                code=${BASH_REMATCH[1]}
                printf -v char "\\u$code"
                name=${name//"@$code"/$char}
            done
            # Solo nombres que se pueden usar (sin | ni saltos de linea)
            [[ "$name" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$ ]] && echo "$name"
        done | sort -f
}

# Nombres repartidos en columnas que caben en el ancho indicado
function columns() {
    local width=${1:-72} names=() name longest=0

    while IFS= read -r name; do
        [ -z "$name" ] && continue
        names+=("$name")
        (( ${#name} > longest )) && longest=${#name}
    done

    [ ${#names[@]} -eq 0 ] && return 0

    local col_w=$(( longest + 3 ))
    local ncols=$(( width / col_w ))
    (( ncols < 1 )) && ncols=1
    local nrows=$(( (${#names[@]} + ncols - 1) / ncols ))
    local r c line

    # Orden por columnas (de arriba abajo), como ls
    for (( r = 0; r < nrows; r++ )); do
        line=""
        for (( c = 0; c < ncols; c++ )); do
            local i=$(( c * nrows + r ))
            [ $i -lt ${#names[@]} ] && line+=$(pad "${names[i]}" $col_w)
        done
        echo "  ${line%"${line##*[! ]}"}"
    done
}

function active_dir() {
    [ -L /opt/lampp ] && readlink -f /opt/lampp
}

# Version cuyas bases de datos usa una instalacion
function data_owner() {
    readlink -f "$1/var/mysql" | sed -n 's|^/opt/lampp-\(.*\)/var/mysql$|\1|p'
}

# XAMPP del que se copio una version de PHP antigua (o la propia version si es un XAMPP)
function base_of() {
    local dir=$1

    if [ -f "$dir/etc/lvm-base" ]; then
        cat "$dir/etc/lvm-base"
    elif is_fpm_install "$dir"; then
        data_owner "$dir"
    else
        echo "${dir#/opt/lampp-}"
    fi
}

function xampp_bases() {
    for dir in $(lampp_dirs); do
        is_fpm_install "$dir" || echo "${dir#/opt/lampp-}"
    done
}

function status_text() {
    local active=$(active_dir) rows="" dir name mark old=0

    for dir in $(lampp_dirs); do
        name=${dir#/opt/lampp-}
        mark="  "
        [ "$dir" == "$active" ] && mark="* "
        is_fpm_install "$dir" && ! is_stack_install "$dir" && old=1

        rows+="$(stack_row "$dir" "$(install_type "$dir")" "$mark$name")\n"
    done

    local text=""
    if [ -z "$rows" ]; then
        text="No hay ninguna version instalada en /opt/lampp-*\n"
    else
        local header=$(fmt_row "$STACK_WIDTHS" "  ${STACK_HEADER_FIELDS[0]}" "${STACK_HEADER_FIELDS[@]:1}" "Tipo")
        text+="$header\n$(printf '%*s' ${#header} "" | tr ' ' '-')\n$rows\n"
        [ -n "$active" ] && text+="* = version activa\n"
        text+="Tipo: 'XAMPP' (paquete oficial) o 'propia' (pila propia de esa rama de PHP).\n"
        text+="Todas tienen sus propias bases de datos.\n"
        [ $old -eq 1 ] && text+="'sobre X': PHP nuevo con el resto copiado del XAMPP X. Se puede pasar a pila propia\ncon 'Actualizar versiones de PHP'.\n"
    fi

    if [ -e /opt/lampp ] && [ ! -L /opt/lampp ]; then
        text+="\nAVISO: /opt/lampp es una instalacion de XAMPP sin registrar.\n"
        text+="Hay que registrarla antes de instalar versiones de XAMPP (opcion del panel principal).\n"
    elif [ -z "$active" ]; then
        text+="\nNinguna version activa.\n"
    fi

    echo "$text"
}

# Tipo de instalacion para las tablas: XAMPP, pila propia o PHP sobre un XAMPP (antiguas)
function install_type() {
    local dir=$1

    if is_stack_install "$dir"; then
        echo "propia"
    elif is_fpm_install "$dir"; then
        local text="sobre $(base_of "$dir")"
        [ -L "$dir/var/mysql" ] && text+=", BBDD de $(data_owner "$dir")"
        echo "$text"
    else
        echo "XAMPP"
    fi
}

function catalog_entry() {
    local entry

    for entry in "${XAMPP_CATALOG[@]}"; do
        [ "${entry%%|*}" == "$1" ] && echo "$entry" && return 0
    done

    return 1
}

# Todas las versiones publicadas de PHP 7 y 8, de la mas nueva a la mas antigua: "version fecha
# seguridad" (fecha AAAA-MM-DD; seguridad: "seguridad" si php.net la marca como parche de seguridad,
# si no "-"). Solo las que tienen el codigo fuente .tar.xz con su suma sha256.
function php_all_releases() {
    local major

    for major in 7 8 9; do
        # Una rama mayor que aun no existe (9) devuelve {"error": ...} y no cuenta como fallo
        fetch "https://www.php.net/releases/index.php?json&version=$major&max=1000" | python3 -I -c 'import json, re, sys, datetime
data = json.load(sys.stdin)
for version, info in (data.items() if "error" not in data else []):
    # (solo X.Y.Z: con un | o un salto de linea descolocaria las lineas de la ventana)
    if re.match(r"^\d+\.\d+\.\d+$", version) and any(s["filename"].endswith(".tar.xz") and s.get("sha256") for s in info.get("source", [])):
        try:
            date = datetime.datetime.strptime(info.get("date", ""), "%d %b %Y").strftime("%Y-%m-%d")
        except ValueError:
            date = "-"
        print(version, date, "seguridad" if "security" in (info.get("tags") or []) else "-")' 2> /dev/null || true
    done | sort -rV
}

# Ramas de PHP con soporte oficial (las demas se marcan como antiguas en el panel)
function php_supported() {
    fetch "https://www.php.net/releases/active.php" | python3 -I -c 'import json, re, sys
for branches in json.load(sys.stdin).values():
    for branch in branches:
        if re.match(r"^\d+\.\d+$", str(branch)):
            print(branch)' 2> /dev/null
}

# Estado de cada rama en php.net: rama|estado|fin del soporte activo|fin de los parches de seguridad
#   estado: stable (correcciones de errores y de seguridad), security (solo de seguridad) o eol
function php_branch_states() {
    fetch "https://www.php.net/releases/branches.php" | python3 -I -c 'import json, re, sys
for b in json.load(sys.stdin):
    if not re.match(r"^\d+\.\d+$", str(b.get("branch", ""))) or b.get("state") not in ("stable", "security", "eol"):
        continue
    print("%s|%s|%s|%s" % (b.get("branch", ""), b.get("state", ""),
                           (b.get("active_support_end") or "")[:10], (b.get("security_support_end") or "")[:10]))' 2> /dev/null
}

# Texto del estado de una rama para el panel: estable, solo seguridad o sin soporte
function branch_state_text() {
    local st=$(grep "^$1|" <<< "$2" | cut -d'|' -f2)
    case "$st" in
        stable) echo "estable" ;;
        security) echo "solo seguridad" ;;
        eol) echo "sin soporte" ;;
        *) grep -qxF "$1" <<< "$3" && echo "con soporte" || echo "sin soporte" ;;
    esac
}

# Ramas que ofrece el instalador: las de STACK_MATRIX y las nuevas con soporte (usan la ultima fila)
function php_branches() {
    { printf '%s\n' "${STACK_MATRIX[@]%%|*}"; php_supported; } | sort -uV
}

# Ultima version publicada de cada rama que ofrece el instalador: "8.4 8.4.26"
function php_releases() {
    local all=$(php_all_releases) branch latest

    for branch in $(php_branches); do
        latest=$(awk -v b="$branch." 'index($1, b) == 1 {print $1; exit}' <<< "$all")
        [ -n "$latest" ] && echo "$branch $latest"
    done
}

# Parches publicados de una rama, del mas nuevo al mas antiguo: "8.4.26 2026-09-24"
function php_patches() {
    php_all_releases | awk -v b="$1." 'index($1, b) == 1'
}

# Elemento del plan para instalar una version de PHP: el ultimo parche de su rama (php:) o uno
# anterior (parche:). Desde la 1.51 los dos van en su propia carpeta, con la version completa
# (/opt/lampp-X.Y.Z): las lampp-X.Y de antes se siguen poniendo al dia con Actualizar
function php_item() {
    local full=$1 latest=$2

    if [ "$full" == "$latest" ]; then
        echo "php:$full"
    else
        echo "parche:$full"
    fi
}

# Version de PHP nueva (no XAMPP) que ya tiene una version exacta de PHP (vacio si ninguna).
# Un XAMPP con la misma version de PHP no cuenta: la pila propia lleva otros componentes.
function php_installed_in() {
    local dir

    for dir in $(lampp_dirs); do
        is_fpm_install "$dir" && [ "$(php_version "$dir")" == "$1" ] && echo "$dir" && return 0
    done

    return 1
}

# Carpeta (lampp-<carpeta>) en la que se instala un elemento del plan
function item_folder() {
    local name=${1#*:}

    case "${1%%:*}" in
        rehacer) echo "${name%.*}" ;;
        *) echo "$name" ;;
    esac
}

function lampp_running() {
    pgrep -f "^/opt/lampp(-[^/]+)?/(bin/httpd|sbin/mysqld|sbin/proftpd|apache2/bin/httpd|mysql/bin/mariadbd|proftpd/sbin/proftpd)( |$)" > /dev/null
}

function run() {
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $*"
    else
        "$@"
    fi
}

# Instala con apt los paquetes de Ubuntu que falten (los que ya estan no se tocan, y si estan todos no se
# llama a apt). Un repositorio roto de otro programa (un PPA sin version para esta Ubuntu, una clave
# caducada) hace fallar apt-get update: no se para por eso, se avisa de cual es y se instala con las
# listas que ya habia. Solo falla si no se puede instalar algun paquete. Uso: apt_install <paquetes...>
function apt_install() {
    local p missing=() out="" rc
    for p in "$@"; do
        dpkg-query -W -f='${Status}' "$p" 2> /dev/null | grep -q "install ok installed" || missing+=("$p")
    done
    [ ${#missing[@]} -eq 0 ] && { echo "  Ya estan todas instaladas"; return 0; }
    echo "  Faltan: ${missing[*]}"
    out=$(sudo apt-get update -qq 2>&1)
    rc=$?
    if [ $rc -ne 0 ] || grep -q '^E:' <<< "$out"; then
        echo "  Aviso: apt-get update no ha podido leer algun repositorio (de otro programa, no de Nexum):"
        grep -E '^(E|W):' <<< "$out" | sed 's/^/    /'
        echo "  Se sigue con las listas de paquetes que ya habia."
    fi
    # (sin preguntas de debconf: la tarea no tiene una terminal donde contestarlas)
    if ! sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" > /dev/null; then
        echo "No se han podido instalar: ${missing[*]}"
        if [ -n "$out" ]; then
            echo "Puede ser por los repositorios rotos de arriba: quitalos o arreglalos (Software y actualizaciones,"
            echo "pestaña Otro software, o los ficheros de /etc/apt/sources.list.d) y vuelve a probar."
        fi
        return 1
    fi
}

