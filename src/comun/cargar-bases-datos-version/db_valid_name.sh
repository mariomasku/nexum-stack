# Nombre de base valido y que no sea del sistema
function db_valid_name() {
    # Sin - delante: mysql y mysqldump lo tomarian como una opcion (-h otroequipo...)
    if ! [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$ ]]; then
        echo "Nombre de base de datos no valido: $1 (solo letras sin acentos, numeros, _ y -, sin - delante)"

        return 1
    fi
    # (sin distinguir mayusculas: en el Mac el disco no las distingue y MySQL seria la base mysql)
    if [[ "${1,,}" =~ ^($DB_SYSTEM)$ ]]; then
        echo "$1 es una base de datos del sistema: no se toca"

        return 1
    fi
}

# Importaciones hechas con lvm-instalador: carpeta real de datos de MariaDB|base|fecha (segundos)
IMPORTS_FILE="$HOME/.lvm-instalador/importaciones"

# Bases de una carpeta de datos de MariaDB con su fecha: base|fecha|tipo. Tipo i: la de su ultima
# importacion con lvm-instalador. Tipo c: la de su carpeta, que cambia al crear o borrar tablas (al
# importar desde phpMyAdmin, por ejemplo); se lee sin MariaDB en marcha aunque la carpeta sea suya.
# Con --varias <etiqueta> <carpeta>...: las de todas en un solo python3 (la ventana lo pregunta cada 20 s),
# cada linea con su etiqueta delante: D|etiqueta|base|fecha|tipo
function db_dates() {
    if [ "$1" == --varias ]; then
        shift
        python3 -I - "$IMPORTS_FILE" "$@" <<< "$DB_DATES_PY"
    else
        python3 -I - "$IMPORTS_FILE" "" "$1" <<< "$DB_DATES_PY"
    fi
}

DB_DATES_PY='
import os, re, sys
imports = sys.argv[1]
done = {}
try:
    with open(imports, encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("|")
            if len(parts) == 3 and parts[2].isdigit():
                done[(parts[0], parts[1])] = int(parts[2])
except OSError:
    pass
for tag, data in zip(sys.argv[2::2], sys.argv[3::2]):
    data = os.path.realpath(data)
    try:
        names = os.listdir(data)
    except OSError:
        names = []
    rows = []
    for raw in names:
        path = os.path.join(data, raw)
        if raw in ("mysql", "performance_schema", "phpmyadmin", "test", "sys") or raw.startswith("#") \
                or os.path.islink(path) or not os.path.isdir(path):
            continue
        # MariaDB guarda los caracteres especiales del nombre como @XXXX (wp_mi@002dweb es wp_mi-web)
        name = re.sub(r"@([0-9a-f]{4})", lambda m: chr(int(m.group(1), 16)), raw)
        # Solo nombres que se pueden usar: uno con | o un salto de linea (@007c, @000a) meteria lineas
        # falsas en lo que lee la ventana
        if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_-]{0,63}", name):
            continue
        if (data, name) in done:
            rows.append((name, done[(data, name)], "i"))
        else:
            try:
                rows.append((name, int(os.stat(path).st_mtime), "c"))
            except OSError:
                rows.append((name, 0, "c"))
    for name, when, kind in sorted(rows, key=lambda r: r[0].lower()):
        print("%s%s|%d|%s" % ("D|%s|" % tag if tag else "", name, when, kind))
'

# Apunta la fecha de la importacion de una base (sin fecha: la olvida, al borrarla o crearla vacia)
function db_note_import() {
    local data=$1 db=$2 when=$3
    [ "$DRY" -eq 1 ] && return 0
    data=$(python3 -I -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$data") || return 0
    mkdir -p "$(dirname "$IMPORTS_FILE")" || return 0
    { [ -f "$IMPORTS_FILE" ] && awk -F'|' -v a="$data" -v d="$db" '!($1 == a && $2 == d)' "$IMPORTS_FILE"
      [ -n "$when" ] && echo "$data|$db|$when"; } > "$IMPORTS_FILE.nuevo"
    mv "$IMPORTS_FILE.nuevo" "$IMPORTS_FILE"
}

function db_exists() {
    # Va dentro de la consulta: solo nombres validos
    [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
    [ "$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$1'" < /dev/null)" != "0" ]
}

