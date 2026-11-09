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

# Prefijos de los WordPress de una base: los de sus tablas <prefijo>options con <prefijo>users
function wp_table_prefixes() {
    [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] || return 0
    # Solo prefijos de letras, numeros y _ (los nombres de las tablas los trae la base)
    db_root_sql -N -e "SELECT LEFT(TABLE_NAME, LENGTH(TABLE_NAME) - 7) AS p FROM information_schema.TABLES
        WHERE TABLE_SCHEMA='$1' AND TABLE_TYPE='BASE TABLE' AND TABLE_NAME LIKE '%options' AND CONCAT(LEFT(TABLE_NAME, LENGTH(TABLE_NAME) - 7), 'users')
        IN (SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='$1' AND TABLE_TYPE='BASE TABLE') ORDER BY LENGTH(p)" < /dev/null 2> /dev/null \
        | grep -E '^[A-Za-z0-9_]*$'
}

# ¿Entra la web en la base con estos datos? usuario contraseña servidor base tabla. Solo se prueba
# si el servidor es este equipo (nunca se conecta a uno de produccion). La base y la tabla van en
# la consulta: solo nombres validos (el prefijo de la tabla puede venir del wp-config.php)
function db_login_ok() {
    local user=$1 pass=$2 host=$3 db=$4 table=$5
    [ -n "$user" ] && [[ "$host" =~ ^(localhost|127\.0\.0\.1)(:.*)?$ ]] || return 1
    [[ "$db" =~ ^[A-Za-z0-9_-]+$ ]] && [[ "$table" =~ ^[A-Za-z0-9_]+$ ]] || return 1
    # Sin leer la tabla: podria ser una vista del volcado que ejecuta funciones con los permisos de
    # este usuario (root muchas veces). Basta con que la vea como tabla de verdad
    db_base_table "$user" "$pass" "$db" "$table"
}

# URL con la que se ve un proyecto en este equipo: su dominio propio (pestaña Hosts) o el vhost de
# los proyectos (el ServerName que tenga: web.local, localhost...), con https si tiene certificado
function wp_local_url() {
    local domain link
    domain=$(custom_domain "$1")
    if [ -n "$domain" ]; then
        echo "https://$domain"

        return 0
    fi
    link=$(project_link)
    vhosts_info | awk -F'|' -v l="${link:-$PROJECT_VHOST}" '
        $2 == l && $5 != "" && https == "" { https = "https://" $3 ($1 == 443 ? "" : ":" $1) }
        $2 == l && $5 == "" && http == "" { http = "http://" $3 ($1 == 80 ? "" : ":" $1) }
        END { print (https != "" ? https : http != "" ? http : "https://" l) }'
}

# Si el wp-config.php define WP_SITEURL y WP_HOME con la direccion dada (fuera de comentarios)
function wp_config_has_url() {
    python3 -I - "$1" "$2" <<'EOF'
import re, sys
try:
    with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
        text = f.read(2000000)
except OSError:
    sys.exit(1)
url = sys.argv[2].rstrip("/")
for name in ("WP_SITEURL", "WP_HOME"):
    rx = r"""(?m)^[ \t]*define\(\s*['"]%s['"]\s*,\s*['"]%s/?['"]\s*\)""" % (name, re.escape(url))
    if not re.search(rx, text):
        sys.exit(1)
EOF
}

# wp-config <carpeta> [base]: comprueba el wp-config.php de un WordPress y, si no usa la base
# asociada (la indicada, la recordada para la carpeta o la suya si esta en local) o no entra en el
# MariaDB local, lo rehace con la plantilla
function wp_config() {
    local folder=${1%/} db=$2 dir file sample saved src name user host prefix pass new_prefix prefixes
    local s_name s_user s_host s_prefix s_pass local_db=0 try out url
    valid_project "$folder" || return 1
    dir=$HTDOCS_DIR/$folder file=$HTDOCS_DIR/$folder/wp-config.php sample=$HTDOCS_DIR/$folder/wp-config-sample.php
    if ! project_path_ok "$dir" "$file" || { [ -e "$sample" ] && ! project_path_ok "$dir" "$sample"; }; then
        echo "Aviso: wp-config.php de $folder es un enlace o esta fuera de la carpeta: no se toca"

        return 0
    fi
    saved=$WP_CONFIG_DIR/$folder.wp-config.php
    { IFS= read -r name; IFS= read -r user; IFS= read -r host; IFS= read -r prefix; IFS= read -r pass; } \
        < <(wp_config_read "$file")

    # Si MariaDB se acaba de arrancar (cambio de version), se le dan unos segundos
    for try in 1 2 3 4 5 6; do
        out=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e 'SELECT 1' < /dev/null 2>&1) && break
        [[ "$out" == *"Can't connect"* ]] && [ "$DRY" -eq 0 ] || break
        sleep 1
    done
    [ -z "$db" ] && db=$(saved_project_db "$folder")
    if [ -z "$db" ]; then
        # El nombre lo trae el wp-config.php: solo si es un nombre de base valido
        [[ "$name" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ ]] && db_exists "$name" 2> /dev/null && db=$name
    fi
    if [ -z "$db" ]; then
        echo "Aviso: el wp-config.php de $folder usa la base ${name:-(ninguna)}, que no esta en la"
        echo "version activa, y la carpeta no tiene una base asociada. Cargala desde el buscador de"
        echo "Bases de datos (Cargar proyecto) o al subirla elige el proyecto, y se corrige sola."

        return 0
    fi
    if ! [[ "$db" =~ ^[A-Za-z0-9_-]+$ ]] || ! db_exists "$db" 2> /dev/null; then
        echo "Aviso: la base $db de $folder no esta en la version activa: no se toca su wp-config.php"

        return 0
    fi
    prefixes=$(wp_table_prefixes "$db")
    if [ -z "$prefixes" ]; then
        echo "Aviso: la base $db no tiene las tablas de WordPress: no se toca el wp-config.php de $folder"

        return 0
    fi

    # Funciona en este equipo con la base asociada y con WP_SITEURL y WP_HOME en su direccion local
    # (sin ellas WordPress redirige al dominio de produccion): es la plantilla para la proxima vez
    url=$(wp_local_url "$folder")
    if [ "$name" == "$db" ] && grep -qxF -- "$prefix" <<< "$prefixes" && db_login_ok "$user" "$pass" "$host" "$db" "${prefix}options" \
        && wp_config_has_url "$file" "$url"; then
        if [ "$DRY" -eq 0 ] && ! cmp -s "$file" "$saved"; then
            mkdir -p "$WP_CONFIG_DIR" && cp "$file" "$saved"
        fi
        echo "WordPress: wp-config.php usa la base $db"

        return 0
    fi

    # Plantilla: la copia de este equipo, el propio fichero o wp-config-sample.php (si solo le faltan
    # WP_SITEURL y WP_HOME, el propio fichero, que ya entra en la base)
    if [ "$name" == "$db" ] && grep -qxF -- "$prefix" <<< "$prefixes" && db_login_ok "$user" "$pass" "$host" "$db" "${prefix}options"; then
        src=$file
    elif [ -f "$saved" ]; then
        src=$saved
    elif [ -f "$file" ]; then
        src=$file
    elif [ -f "$sample" ]; then
        src=$sample
    else
        echo "Aviso: $folder no tiene wp-config.php ni wp-config-sample.php: no se puede crear"

        return 0
    fi
    { IFS= read -r s_name; IFS= read -r s_user; IFS= read -r s_host; IFS= read -r s_prefix; IFS= read -r s_pass; } \
        < <(wp_config_read "$src")
    # Prefijo: siempre uno que traen las tablas de la base (nunca se cambian las tablas). Con varios
    # WordPress en la base, el del wp-config.php del proyecto o el de la plantilla si la base lo
    # tiene; si no se sabe cual es, no se toca (un prefijo sin tablas abriria la instalacion)
    if grep -qxF -- "$prefix" <<< "$prefixes" && [ -f "$file" ]; then
        new_prefix=$prefix
    elif grep -qxF -- "$s_prefix" <<< "$prefixes"; then
        new_prefix=$s_prefix
    elif [ "$(wc -l <<< "$prefixes")" == 1 ]; then
        new_prefix=$prefixes
    else
        echo "Aviso: $db tiene tablas de varios WordPress (prefijos $(tr '\n' ' ' <<< "$prefixes"| sed 's/ $//'))"
        echo "y el wp-config.php de $folder no usa ninguno: no se toca. Pon en \$table_prefix el"
        echo "de su web y vuelve a cargar el proyecto."

        return 0
    fi
    # Usuario, contraseña y servidor de la plantilla si entran en local; si no, root y localhost
    db_login_ok "$s_user" "$s_pass" "$s_host" "$db" "${new_prefix}options" || local_db=1

    if [ "$name" != "$db" ]; then
        echo "WordPress: el wp-config.php de $folder usa la base ${name:-(ninguna)}${host:+ en $host}; la de la carpeta es $db"
    elif db_login_ok "$user" "$pass" "$host" "$db" "${prefix}options"; then
        echo "WordPress: el wp-config.php de $folder no lleva WP_SITEURL y WP_HOME en $url"
    else
        echo "WordPress: el wp-config.php de $folder no entra en el MariaDB local${host:+ (servidor $host, usuario $user)}"
    fi
    case "$src" in
        "$saved") echo "Se rehace con la plantilla de este equipo, con la base $db" ;;
        "$sample") echo "Se crea a partir de wp-config-sample.php, con la base $db y claves nuevas" ;;
        *) [ "$name" == "$db" ] && echo "Se le ponen WP_SITEURL y WP_HOME" || echo "Se cambia a la base $db" ;;
    esac
    [ $local_db -eq 1 ] && echo "  Usuario root y servidor localhost (los de MariaDB local)"
    [ "$new_prefix" != "$s_prefix" ] && echo "  Prefijo de las tablas: $new_prefix (era ${s_prefix:-ninguno})"
    echo "  WP_SITEURL y WP_HOME: $url"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $file con la base $db y copia en $saved"

        return 0
    fi

    mkdir -p -m 700 "$WP_CONFIG_DIR" || return 1
    if [ -f "$file" ] && ! cmp -s "$file" "$saved"; then
        mkdir -p -m 700 "$HOME/lvm-copias" && cp "$file" "$HOME/lvm-copias/wp-config.php-$folder-$(date +%Y%m%d-%H%M%S)" \
            && echo "  El anterior queda en ~/lvm-copias"
    fi
    LVM_WP_CLAVE=${MYSQL_PWD:-} python3 -I - "$src" "$WP_CONFIG_DIR/.nuevo" "$db" "$new_prefix" "$local_db" "$url" <<'EOF' || { echo "No se ha podido preparar el wp-config.php"; return 1; }
import os, re, secrets, string, sys
src, dst, db, prefix, local_db, url = sys.argv[1:7]
# newline="": se conservan los finales de linea (CRLF en muchos wp-config.php)
with open(src, encoding="utf-8", errors="surrogateescape", newline="") as f:
    text = f.read()
def php(v):
    return "'%s'" % v.replace("\\", "\\\\").replace("'", "\\'")
def put(text, name, value):
    rx = re.compile(r"""(?m)^([ \t]*define\(\s*['"]%s['"]\s*,\s*)(?:'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")""" % name)
    return rx.sub(lambda m: m.group(1) + php(value), text, count=1)
text = put(text, "DB_NAME", db)
if local_db == "1":
    text = put(text, "DB_USER", "root")
    text = put(text, "DB_PASSWORD", os.environ.get("LVM_WP_CLAVE", ""))
    text = put(text, "DB_HOST", "localhost")
text = re.sub(r"""(?m)^([ \t]*\$table_prefix\s*=\s*)(['"])[^'"]*\2""", lambda m: m.group(1) + php(prefix), text, count=1)
# La web en este equipo (si no, WordPress redirige al dominio de produccion guardado en la base)
nl = "\r\n" if "\r\n" in text else "\n"
missing = []
for name in ("WP_SITEURL", "WP_HOME"):
    rx = re.compile(r"""(?m)^([ \t]*define\(\s*['"]%s['"]\s*,\s*)(?:'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")""" % name)
    if rx.search(text):
        text = rx.sub(lambda m: m.group(1) + php(url), text, count=1)
    else:
        missing.append(name)
if missing:
    lines = "".join("define('%s', %s);%s" % (name, php(url), nl) for name in missing) + nl
    # Delante de los datos de la base, como en la plantilla del equipo; si no, detras de <?php
    m = re.search(r"""(?m)^[ \t]*(?://[^\r\n]*Database settings|define\(\s*['"]DB_NAME['"])""", text)
    if m:
        text = text[:m.start()] + lines + text[m.start():]
    else:
        m = re.search(r"<\?php[^\n]*\n", text)
        at = m.end() if m else 0
        text = text[:at] + nl + lines + text[at:]
# Sin editor de plugins y temas en el escritorio de WordPress: todos los proyectos van en el mismo
# origen (localhost), y un fallo XSS en uno podria usar ese editor en otro para ejecutar PHP
if not re.search(r"""(?m)^[ \t]*define\(\s*['"]DISALLOW_FILE_EDIT['"]""", text):
    line = "define('DISALLOW_FILE_EDIT', true); // lvm-instalador: sin editor de plugins en local" + nl
    m = re.search(r"""(?m)^[ \t]*(?:/\*[^\n]*stop editing|\$table_prefix\b)""", text)
    if m:
        text = text[:m.start()] + line + nl + text[m.start():]
    else:
        m = re.search(r"<\?php[^\n]*\n", text)
        at = m.end() if m else 0
        text = text[:at] + line + text[at:]
# wp-config-sample.php: claves nuevas
chars = string.ascii_letters + string.digits + "!#$%&()*+,-./:;<=>?@[]^_{|}~"
for key in ("AUTH_KEY", "SECURE_AUTH_KEY", "LOGGED_IN_KEY", "NONCE_KEY",
            "AUTH_SALT", "SECURE_AUTH_SALT", "LOGGED_IN_SALT", "NONCE_SALT"):
    rx = re.compile(r"""(?m)^([ \t]*define\(\s*['"]%s['"]\s*,\s*)['"]put your unique phrase here['"]""" % key)
    text = rx.sub(lambda m: m.group(1) + php("".join(secrets.choice(chars) for _ in range(64))), text, count=1)
with open(dst, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
    f.write(text)
EOF
    project_write "$WP_CONFIG_DIR/.nuevo" "$file" || { rm -f "$WP_CONFIG_DIR/.nuevo"; echo "No se ha podido escribir $file"; return 1; }
    mv "$WP_CONFIG_DIR/.nuevo" "$saved"
    echo "wp-config.php de $folder listo: base $db (plantilla guardada en $saved)"
}

# Datos de la base en la configuracion de una tienda (app/config/parameters.php o, en 1.6,
# config/settings.inc.php), uno por linea: fichero, base, usuario, servidor, prefijo y contraseña.
# Nada si no tiene configuracion con base (la crea ps_parameters).
function ps_db_read() {
    python3 -I - "$HTDOCS_DIR/$1" <<'EOF'
import os, re, sys
root = sys.argv[1]
quoted = r"""(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")"""
rules = [
    ("app/config/parameters.php", r"""['"]%s['"]\s*=>\s*""" + quoted,
     ("database_name", "database_user", "database_host", "database_prefix", "database_password")),
    ("config/settings.inc.php", r"""(?m)^[ \t]*define\(\s*['"]%s['"]\s*,\s*""" + quoted,
     ("_DB_NAME_", "_DB_USER_", "_DB_SERVER_", "_DB_PREFIX_", "_DB_PASSWD_")),
]
for rel, rx, keys in rules:
    try:
        if not os.path.isfile(os.path.join(root, rel)) or os.path.getsize(os.path.join(root, rel)) > 2000000:
            raise OSError("no es un fichero normal")
        with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        continue
    values = []
    for i, key in enumerate(keys):
        m = re.search(rx % key, text)
        v = (m.group(1) if m.group(1) is not None else m.group(2)) if m else ""
        v = re.sub(r"\\(.)", r"\1", v)
        # Sin caracteres de control (salen en la terminal), salvo en la contraseña
        values.append(v.replace("\n", " ") if i == 4 else re.sub(r"[\x00-\x1f\x7f-\x9f]", "?", v))
    if values[0]:
        print(rel)
        for v in values:
            print(v)
        break
EOF
}

# Tienda cuya configuracion no usa la base asociada a la carpeta (base nueva subida para ella o
# codigo de produccion pegado encima): cambia la base y el prefijo de las tablas y, si sus datos no
# entran en el MariaDB local, pone root y localhost. Deja PS_NEW_PARAMS=1 para vaciar la cache.
function ps_set_db() {
    local folder=$1 db=$2 rel name user host prefix pass new_prefix local_db=0 file
    [[ "$db" =~ ^[A-Za-z0-9_-]+$ ]] || return 0
    { IFS= read -r rel; IFS= read -r name; IFS= read -r user; IFS= read -r host; IFS= read -r prefix; IFS= read -r pass; } \
        < <(ps_db_read "$folder")
    [ -n "$rel" ] || return 0
    file=$HTDOCS_DIR/$folder/$rel
    if ! project_path_ok "$HTDOCS_DIR/$folder" "$file"; then
        echo "Aviso: $rel de $folder es un enlace o esta fuera de la carpeta: no se toca"

        return 0
    fi
    if ! db_exists "$db" 2> /dev/null; then
        echo "Aviso: la base $db de $folder no esta en la version activa: no se toca $rel"

        return 0
    fi
    new_prefix=$(ps_table_prefix "$db" "$prefix")
    if [ -z "$new_prefix" ]; then
        echo "Aviso: la base $db no tiene la tabla shop_url de PrestaShop: no se toca $rel"

        return 0
    fi
    if [ "$name" == "$db" ] && [ "$prefix" == "$new_prefix" ] \
        && db_login_ok "$user" "$pass" "$host" "$db" "${new_prefix}shop_url"; then
        return 0
    fi
    db_login_ok "$user" "$pass" "$host" "$db" "${new_prefix}shop_url" || local_db=1

    if [ "$name" != "$db" ]; then
        echo "PrestaShop: $rel de $folder usa la base $name${host:+ en $host}; la de la carpeta es $db"
    else
        echo "PrestaShop: $rel de $folder no entra en el MariaDB local${host:+ (servidor $host, usuario $user)}"
    fi
    echo "Se cambia a la base $db"
    [ $local_db -eq 1 ] && echo "  Usuario root y servidor localhost (los de MariaDB local)"
    [ "$new_prefix" != "$prefix" ] && echo "  Prefijo de las tablas: $new_prefix (era ${prefix:-ninguno})"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $file con la base $db"

        return 0
    fi

    mkdir -p -m 700 "$PS_PARAMS_DIR" "$HOME/lvm-copias" || return 1
    cp "$file" "$HOME/lvm-copias/$(basename "$rel")-$folder-$(date +%Y%m%d-%H%M%S)" && echo "  El anterior queda en ~/lvm-copias"
    LVM_PS_CLAVE=${MYSQL_PWD:-} python3 -I - "$file" "$PS_PARAMS_DIR/.nuevo" "$db" "$new_prefix" "$local_db" <<'EOF' || { echo "No se ha podido preparar $rel"; return 1; }
import os, re, sys
src, dst, db, prefix, local_db = sys.argv[1:6]
# newline="": se conservan los finales de linea
with open(src, encoding="utf-8", errors="surrogateescape", newline="") as f:
    text = f.read()
def php(v):
    return "'%s'" % v.replace("\\", "\\\\").replace("'", "\\'")
value = r"""(?:'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"|NULL|null)"""
if src.endswith("parameters.php"):
    rx = r"""(['"]%s['"]\s*=>\s*)""" + value
    keys = dict(name="database_name", prefix="database_prefix", user="database_user",
                password="database_password", host="database_host", port="database_port")
else:
    rx = r"""(?m)^([ \t]*define\(\s*['"]%s['"]\s*,\s*)""" + value
    keys = dict(name="_DB_NAME_", prefix="_DB_PREFIX_", user="_DB_USER_", password="_DB_PASSWD_",
                host="_DB_SERVER_")
def put(text, key, v):
    return re.sub(rx % keys[key], lambda m: m.group(1) + php(v), text, count=1)
text = put(text, "name", db)
text = put(text, "prefix", prefix)
if local_db == "1":
    text = put(text, "user", "root")
    text = put(text, "password", os.environ.get("LVM_PS_CLAVE", ""))
    text = put(text, "host", "localhost")
    if "port" in keys:
        text = put(text, "port", "")
with open(dst, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
    f.write(text)
EOF
    project_write "$PS_PARAMS_DIR/.nuevo" "$file" || { rm -f "$PS_PARAMS_DIR/.nuevo"; echo "No se ha podido escribir $file"; return 1; }
    # La copia que se repone si se pierde parameters.php pasa a ser esta
    if [[ "$rel" == */parameters.php ]]; then
        mv "$PS_PARAMS_DIR/.nuevo" "$PS_PARAMS_DIR/$folder.parameters.php"
    else
        rm -f "$PS_PARAMS_DIR/.nuevo"
    fi
    echo "$rel de $folder listo: base $db"
    PS_NEW_PARAMS=1
}

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
    local dest_dir=$(getent passwd "$user" | cut -d: -f6)/lvm-copias
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
        # (sus vhosts, por si tenia alguno propio: una copia en ~/lvm-copias)
        if [ "$DRY" -eq 0 ] && [ -f /opt/lampp/etc/extra/httpd-vhosts.conf ] \
                && grep -qvE '^[[:space:]]*(#|$)' /opt/lampp/etc/extra/httpd-vhosts.conf; then
            mkdir -p -m 700 "$HOME/lvm-copias" \
                && cp /opt/lampp/etc/extra/httpd-vhosts.conf "$HOME/lvm-copias/httpd-vhosts-de-lampp-$version-$stamp.conf" \
                && echo "Sus vhosts estan en ~/lvm-copias/httpd-vhosts-de-lampp-$version-$stamp.conf (copialos con Editar vhosts)"
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

