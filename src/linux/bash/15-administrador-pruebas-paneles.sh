# ===========================================================================
# Administrador de pruebas de los paneles (WordPress y PrestaShop)
# ===========================================================================
# Al cargar una BBDD (y al pulsar el boton del panel en Cargar proyecto) se le añade un administrador
# de pruebas, el mismo en todos los equipos: el boton abre la pantalla de acceso con el usuario y la
# contraseña ya escritos. Solo en las BBDD de este equipo (que nunca van a produccion)
TEST_ADMIN_USER="local@local.test"
TEST_ADMIN_PASS="local"
# (huella bcrypt de «local», para PrestaShop 1.7 o posterior; la 1.6 usa md5 de su _COOKIE_KEY_ y
# la contraseña, y WordPress acepta md5 y la cambia por la suya al entrar)
TEST_ADMIN_BCRYPT='$2y$12$IqVkFsJq4UhjbzLfagfW9eU5V6iIauQCbfMJDY26MoM8ETz6ZKgxG'

# Cliente de MariaDB como root para el administrador de pruebas (test_admin, wp_table_prefixes y
# ps_table_prefix): el de LAMPP (DB_CLIENT) o, si DB_ROOT_CLIENT (un array) tiene algo, ese. Asi
# test_admin sirve tambien para la BBDD de un contenedor de Docker (docker_test_admin)
DB_ROOT_CLIENT=()
function db_root_sql() {
    if [ ${#DB_ROOT_CLIENT[@]} -gt 0 ]; then
        "${DB_ROOT_CLIENT[@]}" "$@"
    else
        "${DB_SAFE[@]}" "$DB_CLIENT" -uroot "$@"
    fi
}

# usuario-pruebas <base> [carpeta]: crea o deja al dia el administrador de pruebas en los WordPress y
# la tienda PrestaShop de la base. Dice A|wp|usuario|contraseña y/o A|ps|... por cada uno (para la
# ventana); sale con 1 si no hay ninguno. La carpeta (o la recordada para la base) solo hace falta en
# PrestaShop 1.6, por su _COOKIE_KEY_
function test_admin() {
    local db=$1 folder=$2 p sql cols col exprs hash src key done_any=1
    if ! [[ "$db" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$ ]]; then
        echo "Base no valida: $db"
        return 1
    fi
    [ -z "$folder" ] && folder=$(linked_folder "$db" "${DB_TARGET_FOLDER:-}")
    [[ "$folder" =~ ^[A-Za-z0-9_][A-Za-z0-9\ ._-]*$ ]] && [ -d "$HTDOCS_DIR/$folder" ] || folder=""
    # (el cliente de root de LAMPP o, con DB_ROOT_CLIENT, otro: el de la MariaDB de un contenedor)
    local mysql=(db_root_sql -N --default-character-set=utf8mb4)
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] administrador de pruebas $TEST_ADMIN_USER / $TEST_ADMIN_PASS en $db"
        return 0
    fi
    # (solo tablas de verdad: una vista del volcado ejecutaria sus funciones como root)
    function has_table() {
        [ "$("${mysql[@]}" -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$db' AND TABLE_NAME='$1' AND TABLE_TYPE='BASE TABLE'" < /dev/null 2> /dev/null)" == 1 ]
    }

    # WordPress (todos los de la base): usuario con rol de administrador
    for p in $(wp_table_prefixes "$db"); do
        has_table "${p}usermeta" || continue
        sql=$(sed "s/@P@/$p/g" <<'SQL'
SET @id := (SELECT ID FROM `@P@users` WHERE user_login = 'local@local.test' ORDER BY ID LIMIT 1);
INSERT INTO `@P@users` (user_login, user_pass, user_nicename, user_email, user_url, user_registered, user_activation_key, user_status, display_name)
    SELECT 'local@local.test', MD5('local'), 'local-pruebas', 'local@local.test', '', NOW(), '', 0, 'Local (pruebas)' FROM DUAL WHERE @id IS NULL;
SET @id := IFNULL(@id, LAST_INSERT_ID());
UPDATE `@P@users` SET user_pass = MD5('local'), user_activation_key = '' WHERE ID = @id;
DELETE FROM `@P@usermeta` WHERE user_id = @id AND meta_key IN ('@P@capabilities', '@P@user_level');
INSERT INTO `@P@usermeta` (user_id, meta_key, meta_value) SELECT @id, '@P@capabilities', 'a:1:{s:13:"administrator";b:1;}' FROM DUAL WHERE @id > 0;
INSERT INTO `@P@usermeta` (user_id, meta_key, meta_value) SELECT @id, '@P@user_level', '10' FROM DUAL WHERE @id > 0;
SELECT CAST(IFNULL(@id, 0) AS UNSIGNED);
SQL
)
        if [ "$("${mysql[@]}" "$db" -e "$sql" < /dev/null 2> /dev/null | tail -1)" -gt 0 ] 2> /dev/null; then
            echo "A|wp|$TEST_ADMIN_USER|$TEST_ADMIN_PASS"
            done_any=0
        fi
    done

    # PrestaShop: una copia del primer SuperAdmin (mismas columnas, sea cual sea la version) con el
    # correo y la contraseña de pruebas, en todas las tiendas
    p=$(ps_table_prefix "$db")
    # (ps_table_prefix no da nada si la tienda no lleva prefijo)
    if has_table "${p}employee" && has_table "${p}employee_shop" && has_table "${p}shop" && has_table "${p}shop_url"; then
        src=$("${mysql[@]}" "$db" -e "SELECT passwd FROM \`${p}employee\` WHERE id_profile = 1 ORDER BY active DESC, id_employee LIMIT 1" < /dev/null 2> /dev/null)
        if [[ "$src" == '$'* ]]; then
            hash=$TEST_ADMIN_BCRYPT
        elif [ -n "$src" ]; then
            # PrestaShop 1.6: md5(_COOKIE_KEY_ + contraseña), con la clave de su settings.inc.php
            key=""
            [ -n "$folder" ] && key=$(python3 -I - "$HTDOCS_DIR/$folder/config/settings.inc.php" <<'EOF'
import re, sys
try:
    text = open(sys.argv[1], errors="replace").read(1000000)
except OSError:
    sys.exit(0)
m = re.search(r"""define\(\s*['"]_COOKIE_KEY_['"]\s*,\s*['"]([A-Za-z0-9]+)['"]""", text)
print(m.group(1) if m else "")
EOF
)
            [ -n "$key" ] && hash=$(python3 -I -c 'import hashlib, sys; print(hashlib.md5(sys.argv[1].encode()).hexdigest())' "$key$TEST_ADMIN_PASS")
        fi
        cols=$("${mysql[@]}" -e "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$db' AND TABLE_NAME='${p}employee' ORDER BY ORDINAL_POSITION" < /dev/null 2> /dev/null)
        if [ -z "$hash" ]; then
            [ -n "$src" ] && echo "Aviso: no se sabe la _COOKIE_KEY_ de la tienda (PrestaShop 1.6): sin administrador de pruebas. Cargala con su carpeta (Cargar proyecto)."
        elif [ -n "$cols" ] && ! grep -qvE '^[A-Za-z0-9_]+$' <<< "$cols"; then
            local list="" sel=""
            for col in $cols; do
                case $col in
                    id_employee) continue ;;
                    email) exprs="'local@local.test'" ;;
                    passwd) exprs="'$hash'" ;;
                    firstname) exprs="'Pruebas'" ;;
                    lastname) exprs="'Local'" ;;
                    active|id_profile) exprs=1 ;;
                    last_passwd_gen) exprs="NOW()" ;;
                    reset_password_token|reset_password_validity) exprs=NULL ;;
                    *) exprs="\`$col\`" ;;
                esac
                list+="${list:+, }\`$col\`" sel+="${sel:+, }$exprs"
            done
            sql="SET @src := (SELECT id_employee FROM \`${p}employee\` WHERE id_profile = 1 ORDER BY active DESC, id_employee LIMIT 1);
SET @id := (SELECT id_employee FROM \`${p}employee\` WHERE email = 'local@local.test' ORDER BY id_employee LIMIT 1);
INSERT INTO \`${p}employee\` ($list) SELECT $sel FROM \`${p}employee\` WHERE id_employee = @src AND @id IS NULL;
SET @id := IFNULL(@id, LAST_INSERT_ID());
UPDATE \`${p}employee\` SET passwd = '$hash', active = 1, id_profile = 1 WHERE id_employee = @id AND @src IS NOT NULL;
INSERT IGNORE INTO \`${p}employee_shop\` (id_employee, id_shop) SELECT @id, id_shop FROM \`${p}shop\` WHERE @id > 0 AND @src IS NOT NULL;
SELECT CAST(IF(@src IS NULL, 0, @id) AS UNSIGNED);"
            if [ "$("${mysql[@]}" "$db" -e "$sql" < /dev/null 2> /dev/null | tail -1)" -gt 0 ] 2> /dev/null; then
                echo "A|ps|$TEST_ADMIN_USER|$TEST_ADMIN_PASS"
                done_any=0
            fi
        fi
    fi
    unset -f has_table
    return $done_any
}

#@incluir comun/administrador-pruebas-paneles/wp_table_prefixes.sh
# Bases de datos de una version, en columnas. Si usa las de otra version, se indica de cual.
function databases_text() {
    local version=$1 width=${2:-72}
    local dir=/opt/lampp-$version
    local owner=$(data_owner "$dir")
    owner=${owner:-$version}

    local names=$(db_names "/opt/lampp-$owner")
    local count=$(grep -c . <<< "$names")
    local users=$(data_users "$owner")

    local text="lampp-$version: "
    if [ "$owner" != "$version" ]; then
        text+="usa las bases de datos de lampp-$owner"
    else
        text+="bases de datos propias"
    fi
    text+="\n"
    [ -n "$users" ] && text+="Las comparten: lampp-$owner $(printf 'lampp-%s ' $users)\n"
    text+="\nBases de datos: $count (sin contar las del sistema)\n\n"
    text+="$(columns "$width" <<< "$names")\n"

    echo "$text"
}

function list_databases() {
    local dir

    for dir in $(lampp_dirs); do
        echo -e "$(databases_text "${dir#/opt/lampp-}" "$(tput cols 2> /dev/null || echo 80)")"
        echo ""
    done
}

function disable_lampp() {
    if [ -d "/opt/lampp" ] && [ ! -L "/opt/lampp" ]; then
        echo "La carpeta /opt/lampp es una instalacion completa y no un enlace. No se puede ejecutar esta accion."

        return 1
    fi

    if [ -L "/opt/lampp" ]; then
        run sudo /opt/lampp/lampp stop
        run sudo unlink /opt/lampp
    fi
    # Sin version montada no queda ningun proceso de LAMPP en memoria (ni Mailpit)
    close_processes --todos
    mailpit_sync
}

# Motivo por el que no se puede desinstalar una version (vacio si se puede)
function remove_blocker() {
    local version=$1
    local dir=/opt/lampp-$version

    if [ -z "$version" ] || [[ "$version" == */* ]] || [ ! -d "$dir" ] || [ -L "$dir" ]; then
        echo "No existe la version $version de lampp en el sistema."
    elif [ "$(active_dir)" == "$dir" ]; then
        echo "lampp-$version es la version activa. Cambia antes a otra version (o desactivala) y vuelve a intentarlo."
    elif [ -n "$(data_users "$version")" ]; then
        echo "lampp-$version no se puede desinstalar porque estas versiones usan sus bases de datos: $(printf 'lampp-%s ' $(data_users "$version"))\nDesinstala antes esas versiones."
    elif [ -e "$dir/htdocs" ] && [ ! -L "$dir/htdocs" ]; then
        # htdocs deberia ser un enlace a /opt/htdocs; si es una carpeta real puede tener proyectos
        echo "lampp-$version tiene una carpeta htdocs propia (no es un enlace a /opt/htdocs) y podria contener proyectos.\nRevisala y muevela a mano antes de desinstalar."
    fi
}

# Copia comprimida de las bases de datos de una version (sin la version en marcha)
function backup_databases() {
    local version=$1 dir=${2:-/opt/lampp-$1}
    local user=${SUDO_USER:-$USER}
    local dest_dir=$(getent passwd "$user" | cut -d: -f6)/${COPIES_DIR##*/}
    local dest="$dest_dir/lampp-$version-bases-$(date +%Y%m%d-%H%M%S).tar.gz"

    echo "Guardando copia de las bases de datos en $dest..."
    run mkdir -p -m 700 "$dest_dir" || return 1
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] tar -czf $dest -C $dir/var mysql"

        return 0
    fi

    # root solo lee las bases; el fichero lo crea tu usuario (solo para ti). Si root escribiera en
    # tu carpeta, un enlace con ese nombre le haria escribir encima de un fichero del sistema
    if [ "$(id -u)" -eq 0 ] && [ "$user" != root ]; then
        $SUDO tar -czf - -C "$dir/var" mysql | sudo -u "$user" sh -c 'umask 077; cat > "$1"' sh "$dest.parte" \
            || { rm -f "$dest.parte"; return 1; }
    else
        ( umask 077; $SUDO tar -czf - -C "$dir/var" mysql > "$dest.parte" ) || { rm -f "$dest.parte"; return 1; }
    fi
    mv -f "$dest.parte" "$dest" || return 1
    echo "Copia guardada: $dest ($(du -h "$dest" | cut -f1))"
}

# Copia de las bases de datos antes de desinstalar, si caben en la carpeta personal
function remove_backup() {
    local version=$1 dir=/opt/lampp-$1
    local home_dir=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
    local size_kb=0
    [ "$DRY" -eq 0 ] && size_kb=$(sudo du -sk "$dir/var/mysql" 2> /dev/null | cut -f1)
    local free_kb=$(df --output=avail -k "$home_dir" | tail -1 | tr -dc '0-9')

    if [ -n "$size_kb" ] && [ "$free_kb" -lt "$size_kb" ]; then
        echo "No hay espacio para la copia: ocupan $((size_kb / 1024)) MB y hay $((free_kb / 1024)) MB libres en $home_dir."
    elif backup_databases "$version"; then
        return 0
    fi

    echo "No se ha podido guardar la copia, asi que NO se desinstala nada."

    return 1
}

# desinstalar <version> [--copia]: sin preguntas (lo usa la ventana, que ya ha confirmado)
function cli_remove() {
    local version=$1 backup=0
    [ "$2" == "--copia" ] && backup=1

    local blocker=$(remove_blocker "$version")
    if [ -n "$blocker" ]; then
        echo -e "$blocker"

        return 1
    fi

    [ $backup -eq 1 ] && ! remove_backup "$version" && return 1

    remove_lampp "$version"
}

# Arranca, para o reinicia la version activa
function control_lampp() {
    if [ ! -L /opt/lampp ]; then
        echo "No hay ninguna version activa"

        return 1
    fi

    # Antes de arrancar, fuera los de otras versiones (ademas ocuparian los puertos 80, 443 y 3306)
    # y solo para este equipo
    if [ "$1" == start ] || [ "$1" == restart ]; then
        close_processes
        secure_lampp "$(active_dir)"
        secure_failed $? "$(active_dir)" && return 1
        vhosts_root
    fi
    local rc
    # (la MariaDB de esta version, si la tenia Docker sin red: se para para que arranque la normal)
    [ "$1" != stop ] && lampp_bd_handover "$(active_dir)"
    run sudo /opt/lampp/lampp "$1"
    rc=$?
    # Parada: no queda nada en memoria, tampoco de esta version
    if [ "$1" == stop ]; then
        close_processes --todos
        # (salvo lo que use Docker: su MariaDB vuelve, sin red)
        lampp_bd_keep "$(active_dir)"
    fi
    # Mailpit (correo de pruebas) arranca y para con la version
    mailpit_sync
    return $rc
}

function remove_lampp() {
    local version=$1
    local blocker=$(remove_blocker "$version")

    if [ -n "$blocker" ]; then
        echo -e "$blocker"

        return 1
    fi

    # htdocs y vhosts son enlaces (y las bases de datos, en las antiguas sobre XAMPP): rm no los sigue
    run sudo rm -R --one-file-system "/opt/lampp-$version" || return 1

    if [ "$DRY" -eq 1 ]; then
        echo "SIMULACION: no se ha borrado nada"
    else
        echo "lampp-$version desinstalada"
    fi
}

# Lo que trae de fabrica el htdocs de XAMPP
XAMPP_HTDOCS_DEFAULTS="applications.html|bitnami.css|dashboard|favicon.ico|img|index.php|webalizer|xampp"

# Convierte el XAMPP real de /opt/lampp en /opt/lampp-<nombre>, compartiendo htdocs y vhosts
function register_lampp() {
    local version=$1

    if [ ! -d "/opt/lampp" ] || [ -L "/opt/lampp" ]; then
        echo "Debes tener una instalacion valida en /opt/lampp antes de registrarla como una version alternativa"

        return 1
    fi

    if [ -z "$version" ] || ! valid_version_name "$version" || [ -e "/opt/lampp-$version" ]; then
        echo "Nombre no valido o ya existe /opt/lampp-$version"

        return 1
    fi

    run sudo /opt/lampp/lampp stop

    # Si ya hay /opt/htdocs (compartido), el htdocs de este XAMPP no se borra si tiene algo mas que
    # lo de fabrica (un XAMPP instalado a mano puede tener proyectos): se aparta en /opt, sin tocar
    # /opt/htdocs, y se avisa de donde esta
    local stamp=$(date +%Y%m%d-%H%M%S) extra
    if [ ! -d "/opt/htdocs" ]; then
        run sudo mv /opt/lampp/htdocs /opt/htdocs
    else
        extra=$(find /opt/lampp/htdocs -mindepth 1 -maxdepth 1 2> /dev/null | sed 's|.*/||' \
            | grep -vxE "$XAMPP_HTDOCS_DEFAULTS" | head -5)
        if [ -n "$extra" ]; then
            run sudo mv /opt/lampp/htdocs "/opt/htdocs-de-lampp-$version-$stamp"
            echo "El htdocs de este XAMPP tenia proyectos ($(paste -sd ',' - <<< "$extra" | sed 's/,/, /g')...): no se"
            echo "borra. Esta en /opt/htdocs-de-lampp-$version-$stamp; pasa a /opt/htdocs lo que quieras usar."
        else
            run sudo rm -R --one-file-system /opt/lampp/htdocs
        fi
    fi

    if [ ! -f "/opt/config/httpd-vhosts.conf" ]; then
        run sudo mkdir -p /opt/config
        run sudo mv /opt/lampp/etc/extra/httpd-vhosts.conf /opt/config/httpd-vhosts.conf
    else
        # (sus vhosts, por si tenia alguno propio: una copia en ~/nexum-backups, porque se quitan)
        if [ "$DRY" -eq 0 ] && [ -f /opt/lampp/etc/extra/httpd-vhosts.conf ] \
                && grep -qvE '^[[:space:]]*(#|$)' /opt/lampp/etc/extra/httpd-vhosts.conf; then
            mkdir -p -m 700 "$COPIES_DIR" \
                && cp /opt/lampp/etc/extra/httpd-vhosts.conf "$COPIES_DIR/httpd-vhosts-de-lampp-$version-$stamp.conf" \
                && echo "Sus vhosts estan en ~/nexum-backups/httpd-vhosts-de-lampp-$version-$stamp.conf (copialos con Editar vhosts)"
        fi
        run sudo rm /opt/lampp/etc/extra/httpd-vhosts.conf
    fi

    run sudo mv /opt/lampp "/opt/lampp-$version"
    run sudo ln -s /opt/htdocs "/opt/lampp-$version/htdocs"
    run sudo ln -s /opt/config/httpd-vhosts.conf "/opt/lampp-$version/etc/extra/httpd-vhosts.conf"

    # Lo demas del manual de XAMPP, si falta: vhosts activados, Apache con tu usuario y htdocs tuyo
    [ -f "/opt/lampp-$version/etc/httpd.conf" ] \
        && run sudo sed -i 's|^#\(Include etc/extra/httpd-vhosts.conf\)|\1|' "/opt/lampp-$version/etc/httpd.conf"
    ensure_web_user "/opt/lampp-$version"
    # Y solo para este equipo (XAMPP escucha en toda la red y trae el FTP con daemon/xampp)
    secure_lampp "/opt/lampp-$version"
    vhosts_root
    local web_user=$(web_user_name)
    if [ -d /opt/htdocs ] && [ "$web_user" != root ] && [ "$(stat -c %U /opt/htdocs)" != "$web_user" ]; then
        echo "/opt/htdocs pasa a ser de $web_user para poder crear proyectos sin sudo"
        run sudo chown "$web_user:$(id -gn "$web_user")" /opt/htdocs
    fi

    echo "Nueva version de lampp registrada: $version"
}

# Vuelve a dejar activa la version que lo estaba antes de instalar un XAMPP
function restore_active() {
    local previous=$1 was_running=$2

    # Si un instalador fallido dejo una carpeta real en /opt/lampp, se aparta para no perderla
    if [ -e /opt/lampp ] && [ ! -L /opt/lampp ]; then
        local aside="/opt/lampp-fallido-$(date +%Y%m%d%H%M%S)"
        echo "Se aparta la instalacion incompleta de /opt/lampp a $aside"
        run sudo mv /opt/lampp "$aside"
    fi

    if [ -n "$previous" ] && [ ! -e /opt/lampp ]; then
        secure_lampp "$previous"
        local secure_rc=$?
        run sudo ln -s "$previous" /opt/lampp
        [ "$was_running" -eq 1 ] && ! secure_failed $secure_rc "$previous" && run sudo /opt/lampp/lampp start
    fi
}

