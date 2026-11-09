# Filas de una base que mira MAIL_DB_PY (con su orden «consulta»). mail_db_rows <base> <cliente...>
function mail_db_rows() {
    local db=$1 cols sql
    shift
    [[ "$db" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
    cols=$("$@" -B -e "SELECT c.TABLE_NAME, c.COLUMN_NAME FROM information_schema.COLUMNS c
        JOIN information_schema.TABLES t ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME
        WHERE c.TABLE_SCHEMA = '$db' AND t.TABLE_TYPE = 'BASE TABLE' AND c.COLUMN_NAME IN ('option_id', 'option_name',
        'option_value', 'meta_id', 'meta_key', 'meta_value', 'site_id', 'id_configuration', 'name', 'value', 'id_shop',
        'id_shop_group', 'tabla', 'fila', 'clave', 'tipo', 'ruta', 'original', 'puesto')" < /dev/null 2> /dev/null) || return 1
    [ -n "$cols" ] || return 0
    sql=$(python3 -I -c "$MAIL_DB_PY" consulta <<< "$cols") || return 1
    [ -n "$sql" ] || return 0
    "$@" -B "$db" -e "$sql" < /dev/null 2> /dev/null
}

# correo bd <base>: el correo de pruebas en esa base (de la version activa en marcha), segun como este:
# encendido, lleva a Mailpit (o desactiva) lo de WordPress y PrestaShop; apagado o con WordPress en
# «nada», deshace lo que se hizo. Se hace solo al cargar un proyecto o una BBDD
function mail_db() {
    local db=$1 mode=apagado rows out sqlf
    if ! [[ "$db" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$ ]]; then
        echo "Base no valida: $db"
        return 1
    fi
    mail_on && mode=$(mail_wp_mode)
    local mysql=("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N --default-character-set=utf8mb4)
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] correo de pruebas en $db ($mode)"
        return 0
    fi
    rows=$(mail_db_rows "$db" "${mysql[@]}") || { echo "Aviso: no se ha podido leer $db para el correo de pruebas"; return 1; }
    [ -n "$rows" ] || return 0
    mkdir -p -m 700 "$LOG_DIR" || return 1
    sqlf=$(mktemp "$LOG_DIR/correo-XXXXXX") || return 1
    if ! out=$(python3 -I -c "$MAIL_DB_PY" cambios "$mode" "$MAIL_SMTP_PORT" "$sqlf" <<< "$rows"); then
        rm -f "$sqlf"
        echo "Aviso: no se ha podido preparar el correo de pruebas en $db"
        return 1
    fi
    if [ -s "$sqlf" ] && ! "${mysql[@]}" "$db" < "$sqlf" > /dev/null 2>&1; then
        rm -f "$sqlf"
        echo "Aviso: no se ha podido cambiar el correo de pruebas en $db: lo que mande la web puede salir de verdad"
        return 1
    fi
    rm -f "$sqlf"
    [ -n "$out" ] && echo "$out"
    return 0
}

# Base de un proyecto para el correo de pruebas: la indicada, la de su configuracion (PrestaShop o
# wp-config.php) o la vinculada a la carpeta
function mail_project_db() {
    local folder=$1 db=$2 conf
    if [ -z "$db" ]; then
        conf=$(ps_config "$folder")
        db=${conf%%|*}
    fi
    [ -z "$db" ] && [ -f "$HTDOCS_DIR/$folder/wp-config.php" ] && db=$(wp_config_read "$HTDOCS_DIR/$folder/wp-config.php" | head -1)
    [ -z "$db" ] && db=$(saved_project_db "$folder")
    [[ "$db" =~ ^[A-Za-z0-9_-]+$ ]] && echo "$db"
}

# Al cambiar el correo de pruebas: la BBDD del proyecto cargado (si MariaDB esta en marcha)
function mail_loaded_project() {
    local link folder db check
    link=$(project_link)
    [ -n "$link" ] && [ -L "$HTDOCS_DIR/$link" ] || return 0
    folder=$(readlink "$HTDOCS_DIR/$link")
    folder=${folder%/}
    valid_project "$folder" > /dev/null 2>&1 || return 0
    check=$(gui_db_check)
    [[ "$check" == ok\|* ]] || return 0
    db=$(mail_project_db "$folder") || return 0
    db_names "$(active_dir)" | grep -qxF "$db" || return 0
    mail_db "$db"
}

