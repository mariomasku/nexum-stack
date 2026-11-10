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
    local s_name s_user s_host s_prefix s_pass local_db=0 out url
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
    for _ in 1 2 3 4 5 6; do
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
    # shellcheck disable=SC2034  # (se lee por su nombre (${!nombre}) o es a propósito)
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
    # (el anterior, en ~/nexum-backups solo con el ajuste copias-ficheros)
    if [ -f "$file" ] && ! cmp -s "$file" "$saved" && [ -f "$COPIES_FILES_FLAG" ]; then
        mkdir -p -m 700 "$COPIES_DIR" && cp "$file" "$COPIES_DIR/wp-config.php-$folder-$(date +%Y%m%d-%H%M%S)" \
            && echo "  El anterior queda en ~/nexum-backups"
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

    mkdir -p -m 700 "$PS_PARAMS_DIR" || return 1
    # (el anterior, en ~/nexum-backups solo con el ajuste copias-ficheros)
    if [ -f "$COPIES_FILES_FLAG" ]; then
        mkdir -p -m 700 "$COPIES_DIR" || return 1
        cp "$file" "$COPIES_DIR/$(basename "$rel")-$folder-$(date +%Y%m%d-%H%M%S)" && echo "  El anterior queda en ~/nexum-backups"
    fi
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

