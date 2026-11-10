# ===========================================================================
# Tiendas PrestaShop: parameters.php y cache
# ===========================================================================
# El repositorio de una tienda 1.7 no lleva app/config/parameters.php (esta en su .gitignore): al
# clonarla queda vacio ('parameters' => NULL) y PrestaShop dice "install" directory is missing. Se
# crea con la base cargada en local y claves nuevas, y se guarda una copia en PS_PARAMS_DIR para
# volver a ponerla (con las mismas claves) si se pierde. La primera vez que se carga una tienda se
# vacia su var/cache (la de produccion da error 500 en local); se apunta en PS_LOADED_FILE.
PS_PARAMS_DIR="$HOME/.lvm-instalador/prestashop"
PS_LOADED_FILE="$HOME/.lvm-instalador/prestashop-cargados"
# Carpetas clonadas con montar-proyecto (el dominio de su base no se falsea solo)
REPO_PROJECTS_FILE="$HOME/.lvm-instalador/montados-de-repositorio"

# ¿Es una tienda PrestaShop? Por su configuracion, sus carpetas o "prestashop" en el nombre
function is_prestashop() {
    local dir=$HTDOCS_DIR/$1
    [[ "${1,,}" == *prestashop* ]] || [ -d "$dir/src/PrestaShopBundle" ] \
        || [ -f "$dir/classes/PrestaShopAutoload.php" ] || [ -n "$(ps_config "$1")" ]
}

# Base de una tienda cuya configuracion no la dice: la indicada, la recordada para la carpeta
# (~/.lvm-instalador/proyectos) o, en la version activa, la unica ps_<final de la carpeta>
# (prestashop-mitienda -> ps_mitienda)
function ps_guess_db() {
    local folder=$1 db=$2 tail
    if [ -z "$db" ] && [ -f "$PROJECTS_FILE" ]; then
        db=$(saved_project_db "$folder")
    fi
    if [ -z "$db" ]; then
        tail=$(tr 'A-Z' 'a-z' <<< "${folder##*[-.]}")
        # Va dentro de la consulta: solo letras, numeros y _
        if [[ "$tail" =~ ^[a-z0-9_]+$ ]]; then
            db=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE LOWER(SCHEMA_NAME) IN ('ps_$tail', '$tail')" < /dev/null 2> /dev/null)
        fi
        [ "$(grep -c . <<< "$db")" == 1 ] || db=""
    fi
    [[ "$db" =~ ^[A-Za-z0-9_-]+$ ]] && echo "$db"
}

# Prefijo de las tablas de una tienda: el de su tabla <prefijo>shop_url (solo letras, numeros y _:
# los nombres de las tablas los trae la base, y el prefijo se usa despues en otras consultas). Si la
# base tiene varias tiendas, el indicado (el que ya usaba su configuracion) si lo tiene; si no, el
# mas corto. ps_table_prefix <base> [prefijo preferido]
function ps_table_prefix() {
    local pref=$2
    [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] || return 0
    [[ "$pref" =~ ^[A-Za-z0-9_]+$ ]] || pref=""
    db_root_sql -N -e "SELECT LEFT(TABLE_NAME, LENGTH(TABLE_NAME) - 8) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$1' AND TABLE_TYPE='BASE TABLE' AND TABLE_NAME LIKE '%shop\\_url' ORDER BY TABLE_NAME = '${pref}shop_url' DESC, LENGTH(TABLE_NAME) LIMIT 1" < /dev/null 2> /dev/null \
        | grep -E '^[A-Za-z0-9_]+$'
}

# Tienda 1.7 o posterior sin base en app/config/parameters.php: lo crea con la base cargada en local
# (la copia guardada si es de la misma base). Lo que ya tiene base no se toca.
function ps_parameters() {
    local folder=$1 db dir=$HTDOCS_DIR/$1 prefix saved out
    local file=$dir/app/config/parameters.php
    [ -f "$dir/app/config/set_parameters.php" ] || [ -d "$dir/src/PrestaShopBundle" ] || return 0
    [ -f "$file" ] && grep -qE "['\"]database_name['\"][[:space:]]*=>[[:space:]]*['\"][^'\"]" "$file" && return 0

    # Si MariaDB se acaba de arrancar (cambio de version), se le dan unos segundos
    for _ in 1 2 3 4 5 6; do
        out=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e 'SELECT 1' < /dev/null 2>&1) && break
        [[ "$out" == *"Can't connect"* ]] && [ "$DRY" -eq 0 ] || break
        sleep 1
    done
    db=$(ps_guess_db "$folder" "$2")
    if [ -z "$db" ] || ! db_exists "$db" 2> /dev/null; then
        echo "Aviso: $folder no tiene la base de datos en app/config/parameters.php y no se sabe"
        echo "cual es${db:+ ($db no esta en la version activa)}. Cargala desde el buscador de Bases de"
        echo "datos (Cargar proyecto) o pon database_name a mano en ese fichero."

        return 0
    fi
    prefix=$(ps_table_prefix "$db")
    if [ -z "$prefix" ]; then
        echo "Aviso: la base $db no tiene la tabla shop_url de PrestaShop: no se crea parameters.php"

        return 0
    fi

    if ! project_path_ok "$dir" "$file"; then
        echo "Aviso: app/config/parameters.php de $folder es un enlace o esta fuera de la carpeta: no se toca"

        return 0
    fi
    saved=$PS_PARAMS_DIR/$folder.parameters.php
    if [ -f "$saved" ] && grep -qF "'database_name' => '$db'" "$saved"; then
        echo "app/config/parameters.php no tiene la base: se pone la copia guardada ($db)"
        project_write "$saved" "$file" || return 1
    else
        echo "Creando app/config/parameters.php con la base $db (prefijo $prefix) y claves nuevas..."
        if [ "$DRY" -eq 1 ]; then
            echo "  [simulacion] $file con la base $db y copia en $saved"
            return 0
        fi
        [ -f "$file" ] && [ -f "$COPIES_FILES_FLAG" ] && mkdir -p -m 700 "$COPIES_DIR" \
            && cp "$file" "$COPIES_DIR/parameters.php-$folder-$(date +%Y%m%d-%H%M%S)"
        mkdir -p -m 700 "$PS_PARAMS_DIR" || return 1
        python3 -I - "$PS_PARAMS_DIR/.nuevo" "$db" "$prefix" <<'EOF' || { echo "No se ha podido preparar $file"; return 1; }
import datetime, hashlib, os, secrets, string, sys
path, db, prefix = sys.argv[1:4]
alnum = string.ascii_letters + string.digits
def gen(n):
    return "".join(secrets.choice(alnum) for _ in range(n))
# Clave de defuse/php-encryption (new_cookie_key): cabecera, 32 bytes y su sha256, en hexadecimal
head = b"\xde\xf0\x00\x00"
key = os.urandom(32)
defuse = (head + key + hashlib.sha256(head + key).digest()).hex()
params = [
    ("database_host", "localhost"), ("database_port", ""), ("database_name", db),
    ("database_user", "root"), ("database_password", ""), ("database_prefix", prefix),
    ("database_engine", "InnoDB"), ("mailer_transport", "smtp"), ("mailer_host", "127.0.0.1"),
    ("mailer_user", None), ("mailer_password", None), ("secret", gen(64)),
    ("ps_caching", "CacheMemcache"), ("ps_cache_enable", False),
    ("ps_creation_date", datetime.date.today().isoformat()), ("locale", "es-ES"),
    ("use_debug_toolbar", True), ("cookie_key", gen(64)), ("cookie_iv", gen(32)),
    ("new_cookie_key", defuse),
]
def php(v):
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "true" if v else "false"
    return "'%s'" % v.replace("\\", "\\\\").replace("'", "\\'")
text = "<?php return array (\n  'parameters' => \n  array (\n%s  ),\n);\n" % "".join(
    "    '%s' => %s,\n" % (k, php(v)) for k, v in params)
with open(path, "w") as f:
    f.write(text)
EOF
        project_write "$PS_PARAMS_DIR/.nuevo" "$file" || { rm -f "$PS_PARAMS_DIR/.nuevo"; echo "No se ha podido escribir $file"; return 1; }
        mv "$PS_PARAMS_DIR/.nuevo" "$saved"
    fi
    # La cache guarda la configuracion anterior (var/cache/*/appParameters.php): se vacia al cargar
    PS_NEW_PARAMS=1
    return 0
}

# Vacia una carpeta (var/cache de una tienda) como root sin seguir enlaces en ningun momento: la ruta
# se recorre desde / con O_NOFOLLOW y tiene que estar dentro de htdocs; dentro, los enlaces se
# borran (no se sigue a donde apuntan). CACHE_CLEAR_PY <carpeta> <htdocs>
CACHE_CLEAR_PY='
import os, stat, sys
target, top = sys.argv[1], os.path.realpath(sys.argv[2])
real = os.path.realpath(target)
if not real.startswith(top + "/") or not real.endswith("/var/cache"):
    sys.exit("%s no esta dentro de %s: no se vacia" % (target, top))
fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
for p in [p for p in real.split("/") if p]:
    nfd = os.open(p, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
    os.close(fd)
    fd = nfd
dev = os.fstat(fd).st_dev
def empty(dfd):
    for e in os.scandir(dfd):
        st = os.stat(e.name, dir_fd=dfd, follow_symlinks=False)
        if stat.S_ISDIR(st.st_mode) and st.st_dev == dev:
            sub = os.open(e.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=dfd)
            try:
                empty(sub)
            finally:
                os.close(sub)
            os.rmdir(e.name, dir_fd=dfd)
        elif not stat.S_ISDIR(st.st_mode):
            os.unlink(e.name, dir_fd=dfd)
empty(fd)
'

