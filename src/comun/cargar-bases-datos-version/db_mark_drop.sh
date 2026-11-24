# BBDD marcadas para borrar (borrado diferido): se marcan aunque su version no este en marcha (las de
# versiones antiguas de un proyecto que ya no se usan) y, al cargar esa version, la ventana dice cuantas
# tiene marcadas y pregunta si se borran. Una linea version|base|fecha por cada una
DROP_MARKS_FILE="$LOG_DIR/bbdd-para-borrar"

# marcar-bd <version> <base> [--quitar]: la marca (o la desmarca) para borrarla al cargar esa version
function db_mark_drop() {
    local folder=$1 db=$2 off=0
    [ "$3" == "--quitar" ] && off=1
    if [ -z "$folder" ] || [ -z "$db" ] || { [ -n "$3" ] && [ $off -eq 0 ]; }; then
        echo "Uso: nexum marcar-bd <version> <base> [--quitar]"

        return 1
    fi
    if ! [[ "$folder" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        echo "Version no valida: $folder"

        return 1
    fi
    db_valid_name "$db" || return 1
    db_mark_set "$folder" "$db" "$([ $off -eq 0 ] && date +%s)" || return 1
    if [ $off -eq 1 ]; then
        echo "$db (en $folder) ya no esta marcada para borrar"
    else
        echo "$db (en $folder) marcada para borrar: se pregunta al cargar esa version"
    fi
}

# Pone (con fecha) o quita (sin ella) la marca de una base
function db_mark_set() {
    local folder=$1 db=$2 when=$3
    [ "$DRY" -eq 1 ] && return 0
    mkdir -p "$(dirname "$DROP_MARKS_FILE")" || return 1
    { [ -f "$DROP_MARKS_FILE" ] && awk -F'|' -v a="$folder" -v d="$db" 'NF >= 2 && !($1 == a && $2 == d)' "$DROP_MARKS_FILE"
      if [ -n "$when" ]; then echo "$folder|$db|$when"; fi; } > "$DROP_MARKS_FILE.nuevo" || return 1
    mv "$DROP_MARKS_FILE.nuevo" "$DROP_MARKS_FILE"
}

# Las bases marcadas de una version, una por linea (de todas: version|base)
function db_marked() {
    [ -f "$DROP_MARKS_FILE" ] || return 0
    if [ -n "$1" ]; then
        awk -F'|' -v a="$1" '$1 == a && $2 ~ /^[A-Za-z0-9_][A-Za-z0-9_-]*$/ { print $2 }' "$DROP_MARKS_FILE"
    else
        awk -F'|' '$1 ~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/ && $2 ~ /^[A-Za-z0-9_][A-Za-z0-9_-]*$/ { print $1 "|" $2 }' "$DROP_MARKS_FILE"
    fi
}

# Para la ventana (gui-datos): J|version|base por cada marcada
function gui_db_marks() {
    local line
    while IFS= read -r line; do
        [ -n "$line" ] && echo "J|$line"
    done < <(db_marked)
    return 0
}

# borrar-bd-marcadas [--copia]: borra las marcadas de la version activa (con su MariaDB en marcha). Las que
# ya no estan se desmarcan sin mas. --copia: antes, una copia de cada una en ~/nexum-backups
function drop_marked_databases() {
    local copy="" db rc n=0 fail=0 dbs
    if [ -n "$1" ] && [ "$1" != "--copia" ]; then
        echo "Uso: nexum borrar-bd-marcadas [--copia]"

        return 1
    fi
    [ "$1" == "--copia" ] && copy=--copia
    db_connect
    rc=$?
    [ $rc -ne 0 ] && return $rc
    dbs=$(db_marked "$DB_FOLDER")
    if [ -z "$dbs" ]; then
        echo "No hay ninguna BBDD marcada para borrar en $DB_FOLDER"

        return 0
    fi
    echo "BBDD marcadas para borrar en $DB_FOLDER: $(tr '\n' ' ' <<< "$dbs")"
    # (por el 3: lo de dentro no se come la lista)
    while IFS= read -r db <&3; do
        if ! db_exists "$db"; then
            echo "$db ya no está: se desmarca"
            db_mark_set "$DB_FOLDER" "$db" ""
            continue
        fi
        if drop_database "$db" $copy; then
            db_mark_set "$DB_FOLDER" "$db" ""
            n=$((n + 1))
        else
            fail=$((fail + 1))
        fi
    done 3<<< "$dbs"
    echo "Borradas: $n$([ $fail -gt 0 ] && echo " (y $fail que no se han podido borrar: siguen marcadas)")"
    [ $fail -eq 0 ]
}

# Al cargar una version (use), si tiene BBDD marcadas, se dice (en la ventana se pregunta)
function db_marks_notice() {
    local folder=$1 dbs
    dbs=$(db_marked "$folder")
    [ -n "$dbs" ] || return 0
    echo "Tiene $(wc -l <<< "$dbs" | tr -d ' ') BBDD marcadas para borrar ($(tr '\n' ' ' <<< "$dbs" | sed 's/ $//')): nexum borrar-bd-marcadas [--copia]"
}
