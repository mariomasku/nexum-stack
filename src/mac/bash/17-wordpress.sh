# ===========================================================================
# WordPress: wp-config.php con la base cargada en local
# ===========================================================================
# Al pegar el codigo de produccion encima del proyecto local, su wp-config.php trae la base, el
# usuario, la contraseña y el servidor de produccion. Al cargar el proyecto (y al subir una base
# nueva para el) se comprueba que use la base asociada a la carpeta y que sus datos entren en el
# MariaDB local. Si no, se rehace con la plantilla: la copia del ultimo wp-config.php que funciono
# en este equipo (WP_CONFIG_DIR/<carpeta>.wp-config.php) o, si no la hay, el propio fichero (o
# wp-config-sample.php) con root y localhost. De la plantilla solo cambian la base y el prefijo.
WP_CONFIG_DIR="$HOME/.lvm-instalador/wordpress"

function is_wordpress() {
    [ -f "$HTDOCS_DIR/$1/wp-config.php" ] || [ -d "$HTDOCS_DIR/$1/wp-includes" ]
}

# Vinculos entre las BBDD y las carpetas de los proyectos (~/.lvm-instalador/proyectos), uno por
# linea: base@version=carpeta (en esa version, la de XAMPP-<version>; sin carpeta, la base no es de
# ningun proyecto en esa version) o base=carpeta (en todas las versiones, como se guardaban hasta la
# 1.36). El de la version manda: asi la copia de una base en otra version puede ir con otra carpeta

# Nombre de la version activa (8.4.27, de XAMPP-8.4.27), o nada
function active_name() {
    local a=$(active_dir)
    [ -n "$a" ] && version_name "$a"
}

# Carpeta vinculada a <base> en <version> (sin version, la activa). Nada si no tiene
function linked_folder() {
    local db=$1 ver=${2:-$(active_name)}
    [ -f "$PROJECTS_FILE" ] || return 0
    awk -F= -v d="$db" -v k="$db@$ver" '$1 == k { v = $2; hv = 1 } $1 == d { g = $2 } END { print (hv ? v : g) }' "$PROJECTS_FILE"
}

# Base vinculada a una carpeta en <version> (sin version, la activa): la ultima que se vinculo
function saved_project_db() {
    local ver=${2:-$(active_name)}
    [ -f "$PROJECTS_FILE" ] || return 0
    awk -F= -v f="$1" -v ver="$ver" '{
        n = index($1, "@")
        if (n) { d = substr($1, 1, n - 1); if (substr($1, n + 1) != ver) next; per[d] = $2; has[d] = 1 }
        else { d = $1; all[d] = $2 }
        last[d] = NR
    } END {
        for (d in last) { v = (d in has) ? per[d] : all[d]; if (v == f && last[d] > best) { best = last[d]; db = d } }
        if (db != "") print db
    }' "$PROJECTS_FILE"
}

# remember_project <base> <carpeta> [version] [--unica]: vincula la base a la carpeta en esa version
# (sin version, la activa; sin carpeta, la desvincula). Con --unica, en esa version la carpeta deja
# de estar vinculada a otras bases (la base nueva sustituye a la anterior)
function remember_project() {
    local db=$1 folder=$2 ver=${3:-$(active_name)} key
    [ "$DRY" -eq 1 ] && return 0
    key=$db${ver:+@$ver}
    mkdir -p "$(dirname "$PROJECTS_FILE")"
    { [ -f "$PROJECTS_FILE" ] && awk -F= -v k="$key" -v d="$db" -v f="$folder" -v ver="$ver" -v u="$4" '
        $1 == k { next }
        u == "--unica" && f != "" && $2 == f && $1 != d {
            # (la de todas las versiones se queda para las demas y en esta se desvincula)
            if (index($1, "@") == 0) { print; if (ver != "") print $1 "@" ver "="; next }
            if (substr($1, index($1, "@") + 1) == ver) next
        }
        { print }' "$PROJECTS_FILE"; echo "$key=$folder"; } > "$PROJECTS_FILE.nuevo"
    mv "$PROJECTS_FILE.nuevo" "$PROJECTS_FILE"
}

# vincular-bd <base> <version> <carpeta|->: la carpeta del proyecto de la base en esa version (- =
# ninguna). Cargar proyecto la carga con ella
function link_database() {
    local db=$1 ver=$2 folder=$3
    if [ -z "$db" ] || [ -z "$ver" ] || [ -z "$folder" ]; then
        echo "Uso: lvm-instalador vincular-bd <base de datos> <version> <carpeta de htdocs|->"
        return 1
    fi
    db_valid_name "$db" || return 1
    if ! valid_version_name "$ver" || [ ! -d "$BASE_DIR/XAMPP-$ver" ]; then
        echo "No existe la version XAMPP-$ver"
        return 1
    fi
    if [ "$folder" == "-" ]; then
        remember_project "$db" "" "$ver"
        echo "$db ya no esta vinculada a ningun proyecto en XAMPP-$ver"
    else
        folder=${folder%/}
        valid_project "$folder" || return 1
        remember_project "$db" "$folder" "$ver"
        echo "$db queda vinculada a $folder en XAMPP-$ver"
    fi
}

# Datos de un wp-config.php, uno por linea: base, usuario, servidor, prefijo y contraseña
function wp_config_read() {
    python3 -I - "$1" <<'EOF'
import os, re, sys
try:
    if not os.path.isfile(sys.argv[1]) or os.path.getsize(sys.argv[1]) > 2000000:
        raise OSError("no es un fichero normal")
    with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
        text = f.read()
except OSError:
    sys.exit(1)
def const(name):
    # Solo las que no estan comentadas (// define( 'DB_USER', 'development' );)
    m = re.search(r"""(?m)^[ \t]*define\(\s*['"]%s['"]\s*,\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")""" % name, text)
    if not m:
        return ""
    return re.sub(r"\\(.)", r"\1", m.group(1) if m.group(1) is not None else m.group(2))
m = re.search(r"""(?m)^[ \t]*\$table_prefix\s*=\s*['"]([^'"]*)['"]""", text)
# Sin caracteres de control (salen en la terminal: un ESC cambiaria lo que se ve), salvo en la
# contraseña, que no se muestra
for i, v in enumerate((const("DB_NAME"), const("DB_USER"), const("DB_HOST"), m.group(1) if m else "", const("DB_PASSWORD"))):
    print(v.replace("\n", " ") if i == 4 else re.sub(r"[\x00-\x1f\x7f-\x9f]", "?", v))
EOF
}

