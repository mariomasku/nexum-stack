# ===========================================================================
# Deteccion de lo instalado
# ===========================================================================

# Carpetas de las versiones instaladas (/Applications/XAMPP-X.Y.Z; hasta la 1.36, XAMPP-X.Y), de la
# mas antigua a la mas nueva
function version_dirs() {
    local dir name

    for dir in "$BASE_DIR"/XAMPP-*; do
        name=${dir##*/XAMPP-}
        [ -d "$dir" ] && [ ! -L "$dir" ] && [[ "$name" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] && echo "$name $dir"
    done | sort -t. -k1,1n -k2,2n -k3,3n | cut -d' ' -f2-
}

function version_name() {
    echo "${1##*/XAMPP-}"
}

function php_version() {
    cat "$1/xamppfiles/etc/pvm-php" 2> /dev/null
}

# Versiones de los componentes: "php|apache|mariadb|proftpd|perl|phpmyadmin" (se guardan al instalar)
function stack_fields() {
    cat "$1/xamppfiles/etc/pvm-stack" 2> /dev/null || echo "-|-|-|-|-|-"
}

# Tabla de versiones: columna "Version", los seis componentes y una columna final variable
STACK_WIDTHS="11 8 8 9 9 8 12 8"
STACK_HEADER_FIELDS=("Version" "PHP" "Apache" "MariaDB" "ProFTPD" "Perl" "phpMyAdmin")

function stack_header() {
    fmt_row "$STACK_WIDTHS" "${STACK_HEADER_FIELDS[@]}" "$1"
}

# stack_row <carpeta> [texto de la ultima columna] [nombre a mostrar]
function stack_row() {
    local dir=$1 extra=$2 name=${3:-$(version_name "$1")}
    local fields

    IFS='|' read -r -a fields <<< "$(stack_fields "$dir")"
    fmt_row "$STACK_WIDTHS" "$name" "${fields[@]}" "$extra"
}

# Bases de datos de una instalacion, sin las del sistema
function db_names() {
    local dir name

    for dir in "$1"/xamppfiles/var/mysql/*/; do
        [ -d "$dir" ] || continue
        name=$(basename "$dir")
        case "$name" in mysql|performance_schema|phpmyadmin|test|sys) continue ;; esac
        # MariaDB guarda los caracteres especiales del nombre como @XXXX (wp_mi@002dweb es wp_mi-web)
        while [[ "$name" =~ @([0-9a-f]{4}) ]]; do
            local code=${BASH_REMATCH[1]} char
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
    [ -L "$LINK" ] && realpath_f "$LINK"
}

# Hay un XAMPP oficial (carpeta real) en /Applications/XAMPP: impide crear el enlace
function official_xampp() {
    [ -e "$LINK" ] && [ ! -L "$LINK" ]
}

function status_text() {
    local active=$(active_dir) rows="" dir name mark

    for dir in $(version_dirs); do
        name=$(version_name "$dir")
        mark="  "
        [ "$dir" == "$active" ] && mark="* "
        rows+="$(stack_row "$dir" "" "$mark$name")\n"
    done

    local text=""
    if [ -z "$rows" ]; then
        text="No hay ninguna version instalada en $BASE_DIR/XAMPP-*\n"
    else
        local header=$(fmt_row "$STACK_WIDTHS" "  ${STACK_HEADER_FIELDS[0]}" "${STACK_HEADER_FIELDS[@]:1}")
        text+="$header\n$(printf '%*s' ${#header} "" | tr ' ' '-')\n$rows\n"
        [ -n "$active" ] && text+="* = version activa ($LINK)\n"
        text+="Cada version tiene su pila propia y sus propias bases de datos.\n"
        text+="Proyectos y virtual hosts compartidos en $COMMON\n"
    fi

    if official_xampp; then
        text+="\nAVISO: $LINK es un XAMPP oficial. Hay que apartarlo antes de activar una version\n"
        text+="(opcion del panel principal).\n"
    elif [ -z "$active" ]; then
        text+="\nNinguna version activa.\n"
    fi

    echo "$text"
}

function lampp_running() {
    # (las versiones en BASE_DIR, el XAMPP oficial y las de antes de la 1.39.3 en /Applications)
    pgrep -f "^($BASE_DIR|$APPS_DIR|$LEGACY_DIR)/XAMPP(-[0-9.]+)?/xamppfiles/(apache2/bin/httpd|mysql/bin/mariadbd|proftpd/sbin/proftpd)( |$)" > /dev/null
}

function run() {
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $*"
    else
        "$@"
    fi
}

