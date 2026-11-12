# Exportar un proyecto (exportar-proyecto y gui-exportar-proyecto): un zip en la carpeta de descargas con su
# codigo (sin .git), su BBDD (con export_database, como Descargar: sin el administrador de pruebas ni los
# cambios del correo de pruebas) y un LEEME-nexum.txt. El codigo, solo si en git esta todo con commit: con
# cambios sin commit no se exporta. export_downloads y export_version_label son de cada sistema

# El zip, sin salir nunca de la carpeta del proyecto:
#   python3 -c "$PROJECT_EXPORT_PY" medir <carpeta>                 lo que ocupa, sin .git (en bytes)
#   python3 -c "$PROJECT_EXPORT_PY" zip <carpeta> <nombre> <.parte> <zip> <sql o ""> <nombre del sql> <leeme>
# El codigo va en <nombre>/ con sus permisos (sin .git, en ninguna subcarpeta). Los enlaces no se siguen: uno
# relativo que apunta dentro de la carpeta se guarda como enlace; uno que sale (o absoluto) no se guarda.
# Los ficheros se abren sin seguir enlaces (O_NOFOLLOW) y solo si siguen siendo el mismo fichero normal. El zip
# se escribe en <.parte> (nuevo, solo para ti) y solo al acabar bien pasa a <zip>; si falla, no queda nada
PROJECT_EXPORT_PY='
import os, stat, sys, time, zipfile


def walk(top):
    """(ruta relativa, lstat o None, error) de lo que hay en top, sin .git y sin entrar en los enlaces."""
    pending = [""]
    while pending:
        rel = pending.pop()
        try:
            names = sorted(os.listdir(os.path.join(top, rel) if rel else top))
        except OSError as e:
            yield rel, None, e
            continue
        for n in names:
            if n == ".git":
                continue
            r = os.path.join(rel, n) if rel else n
            try:
                st = os.lstat(os.path.join(top, r))
            except OSError as e:
                yield r, None, e
                continue
            yield r, st, None
            if stat.S_ISDIR(st.st_mode):
                pending.append(r)


def link_inside(top, rel):
    """El destino de un enlace si es relativo y no sale de la carpeta (ni por el texto ni de verdad)."""
    try:
        target = os.readlink(os.path.join(top, rel))
    except OSError:
        return None
    if os.path.isabs(target):
        return None
    if os.path.normpath(os.path.join(os.path.dirname(rel), target)).split(os.sep)[0] == "..":
        return None
    real_top = os.path.realpath(top)
    real = os.path.realpath(os.path.join(top, rel))
    if real != real_top and not real.startswith(real_top + os.sep):
        return None
    return target


def stamp(st):
    t = time.localtime(max(st.st_mtime, 315532800))
    return tuple(t[:6]) if t.tm_year >= 1980 else (1980, 1, 1, 0, 0, 0)


def measure(top):
    total = 0
    for _r, st, _e in walk(top):
        if st is not None and stat.S_ISREG(st.st_mode):
            total += st.st_size
    print(total)


def add_file(z, top, rel, st, arc):
    """Copia el fichero en el zip, abierto sin seguir enlaces y solo si sigue siendo el mismo."""
    fd = os.open(os.path.join(top, rel), os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
    try:
        now = os.fstat(fd)
        if not stat.S_ISREG(now.st_mode) or (now.st_dev, now.st_ino) != (st.st_dev, st.st_ino):
            raise OSError("ha cambiado mientras se exportaba")
        info = zipfile.ZipInfo(arc, stamp(now))
        info.external_attr = (stat.S_IFREG | stat.S_IMODE(now.st_mode) & 0o777) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        info.file_size = now.st_size
        with os.fdopen(fd, "rb", closefd=False) as src, z.open(info, "w") as dst:
            while True:
                chunk = src.read(1 << 20)
                if not chunk:
                    break
                dst.write(chunk)
    finally:
        os.close(fd)
    return now.st_size


def make_zip(top, name, part, final, sql, sql_name, readme):
    if os.path.lexists(final):
        raise SystemExit("Ya existe %s: no se escribe encima" % final)
    fd = os.open(part, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
    out = os.fdopen(fd, "wb")
    links, skipped, unreadable = [], [], []
    files = size = 0
    last = time.time()
    try:
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as z:
            if top:
                root = zipfile.ZipInfo(name + "/", stamp(os.lstat(top)))
                root.external_attr = (stat.S_IFDIR | 0o755) << 16 | 0x10
                z.writestr(root, b"")
                for rel, st, err in walk(top):
                    arc = name + "/" + rel.replace(os.sep, "/")
                    if st is None:
                        unreadable.append("%s (%s)" % (rel or ".", err.strerror or err))
                        continue
                    mode = st.st_mode
                    if stat.S_ISDIR(mode):
                        info = zipfile.ZipInfo(arc + "/", stamp(st))
                        info.external_attr = (stat.S_IFDIR | stat.S_IMODE(mode) & 0o777) << 16 | 0x10
                        z.writestr(info, b"")
                    elif stat.S_ISLNK(mode):
                        target = link_inside(top, rel)
                        if target is None:
                            skipped.append(rel)
                            continue
                        info = zipfile.ZipInfo(arc, stamp(st))
                        info.external_attr = (stat.S_IFLNK | 0o777) << 16
                        z.writestr(info, target)
                        links.append(rel)
                    elif stat.S_ISREG(mode):
                        try:
                            size += add_file(z, top, rel, st, arc)
                            files += 1
                        except OSError as e:
                            unreadable.append("%s (%s)" % (rel, e.strerror or e))
                    else:
                        skipped.append(rel)
                    if time.time() - last > 2:
                        last = time.time()
                        print("  %d ficheros (%.1f MB)" % (files, size / 1048576.0), flush=True)
            if sql:
                info = zipfile.ZipInfo(sql_name, stamp(os.stat(sql)))
                info.external_attr = (stat.S_IFREG | 0o600) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                info.file_size = os.stat(sql).st_size
                with open(sql, "rb") as src, z.open(info, "w") as dst:
                    while True:
                        chunk = src.read(1 << 20)
                        if not chunk:
                            break
                        dst.write(chunk)
            info = zipfile.ZipInfo("LEEME-nexum.txt", time.localtime()[:6])
            info.external_attr = (stat.S_IFREG | 0o644) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, readme)
        out.flush()
        os.fsync(out.fileno())
        out.close()
        # (sin escribir encima de nada: si ya hubiera uno con ese nombre, falla)
        try:
            os.link(part, final)
            os.unlink(part)
        except OSError:
            if os.path.lexists(final):
                raise
            os.rename(part, final)
    except BaseException:
        if not out.closed:
            out.close()
        try:
            os.unlink(part)
        except OSError:
            pass
        raise
    if top:
        print("Código: %d ficheros (%.1f MB), sin .git" % (files, size / 1048576.0))
    if links:
        print("%d enlaces de dentro de la carpeta, guardados como enlaces" % len(links))
    if skipped:
        print("No van en el zip %d enlaces que salen de la carpeta (o ficheros especiales):" % len(skipped))
        for r in skipped[:10]:
            print("  " + r)
        if len(skipped) > 10:
            print("  y %d más" % (len(skipped) - 10))
    if unreadable:
        print("Aviso: no se han podido leer %d (no van en el zip):" % len(unreadable))
        for r in unreadable[:10]:
            print("  " + r)
        if len(unreadable) > 10:
            print("  y %d más" % (len(unreadable) - 10))


if sys.argv[1] == "medir":
    measure(sys.argv[2])
else:
    try:
        make_zip(*sys.argv[2:9])
    except OSError as e:
        raise SystemExit("No se ha podido escribir el zip: %s" % e)
'

# El estado en git de la carpeta de un proyecto (solo se lee):
# G|<0 no es un repositorio, 1 si, 2 no se ha podido leer>|<rama o el error>|<cambios sin commit>|<commits sin subir>|<tiene rama remota 1/0>
# y una linea C|<cambio> por cada uno de los primeros 8 (git status --porcelain: tambien lo nuevo que no esta
# en .gitignore)
function project_export_git() {
    local dir=$1 out err branch ahead=0 up=0 n
    if [ ! -e "$dir/.git" ] || ! command -v git > /dev/null; then
        echo "G|0||0|0|0"
        return 0
    fi
    err=$(mktemp "${TMPDIR:-/tmp}/lvm-git.XXXXXX") || return 1
    # (sin los ayudantes que pudiera traer su configuracion, y sin escribir nada en el repositorio: status
    # no rehace su indice)
    if ! out=$(GIT_OPTIONAL_LOCKS=0 git -C "$dir" -c core.fsmonitor=false -c core.hooksPath=/dev/null status --porcelain 2> "$err" < /dev/null); then
        echo "G|2|$(head -1 "$err" | tr '|' ' ')|0|0|0"
        rm -f "$err"
        return 0
    fi
    rm -f "$err"
    branch=$(git -C "$dir" symbolic-ref --short -q HEAD 2> /dev/null)
    if git -C "$dir" rev-parse -q --verify '@{u}' > /dev/null 2>&1; then
        up=1
        ahead=$(git -C "$dir" rev-list --count '@{u}..HEAD' 2> /dev/null)
    fi
    n=0
    [ -n "$out" ] && n=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
    echo "G|1|${branch//|/_}|$n|${ahead:-0}|$up"
    [ -n "$out" ] && printf '%s\n' "$out" | head -8 | sed 's/|/_/g; s/^/C|/'
    return 0
}

# La BBDD del proyecto en la version activa: la vinculada a su carpeta o, si no tiene, la de su configuracion
# (solo si esta en esa version). Nada si no tiene
function project_export_db() {
    local folder=$1 active=$(active_dir) db
    [ -n "$active" ] || return 0
    db=$(saved_project_db "$folder")
    [ -n "$db" ] || db=$(project_config_db "$folder")
    [ -n "$db" ] && db_names "$active" | grep -qxF -- "$db" && echo "$db"
    return 0
}

# La rama de PHP (8.4 de 8.4.27)
function project_export_branch() {
    if [[ "$1" =~ ^([0-9]+)\.([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
    else
        echo "${1:-x}"
    fi
}

# El nombre del zip (<carpeta>_php<rama>_<AAAAMMDD-HHMM>_nexum.zip), uno que aun no este en la carpeta
function project_export_name() {
    local folder=$1 branch=$2 dest=$3 stamp n=1 name
    stamp=$(date +%Y%m%d-%H%M)
    name=${folder}_php${branch}_${stamp}_nexum.zip
    while [ -e "$dest/$name" ] || [ -e "$dest/$name.parte" ]; do
        n=$((n + 1))
        name=${folder}_php${branch}_${stamp}-${n}_nexum.zip
    done
    echo "$name"
}

# gui-exportar-proyecto <carpeta>: lo que la ventana necesita para el dialogo de Exportar proyecto:
# las lineas G y C de project_export_git, V|<version>|<lampp-version>|<PHP>|<MariaDB> (V||||, sin version
# activa), B|<BBDD vinculada o nada>, S|<lo que ocupa el codigo sin .git>, D|<carpeta de descargas> y
# N|<nombre del zip>
function gui_project_export() {
    local folder=${1%/} dir active ver php dest
    valid_project "$folder" > /dev/null || return 1
    dir=$HTDOCS_DIR/$folder
    project_export_git "$dir"
    active=$(active_dir)
    if [ -n "$active" ]; then
        ver=$(active_name)
        php=$(php_version "$active")
        echo "V|$ver|$(export_version_label "$ver")|$php|$(stack_fields "$active" | cut -d'|' -f3)"
    else
        echo "V||||"
    fi
    echo "B|$(project_export_db "$folder")"
    echo "S|$(python3 -I -c "$PROJECT_EXPORT_PY" medir "$dir" 2> /dev/null || echo 0)"
    dest=$(export_downloads)
    echo "D|$dest"
    echo "N|$(project_export_name "$folder" "$(project_export_branch "$php")" "$dest")"
}

# exportar-proyecto <carpeta> [--sin-codigo] [--sin-bd] [--bd <base>] [--destino <carpeta>]: el zip del proyecto
# en la carpeta de descargas (o en --destino). Con el codigo, antes se comprueba en git: con cambios sin commit
# no se exporta nada; con commits sin subir, se avisa. Sin --bd, la BBDD vinculada en la version activa (sin
# ninguna, solo el codigo). Si se cancela o falla, no queda ningun zip ni nada a medias
EXPORT_PART="" EXPORT_TMP=""
function project_export_cleanup() {
    [ -n "$EXPORT_PART" ] && rm -f "$EXPORT_PART"
    [ -n "$EXPORT_TMP" ] && [ -d "$EXPORT_TMP" ] && rm -rf "$EXPORT_TMP"
    EXPORT_PART="" EXPORT_TMP=""
}

function project_export() {
    local rc
    trap project_export_cleanup EXIT
    trap 'exit 130' INT TERM HUP
    project_export_run "$@"
    rc=$?
    project_export_cleanup
    trap - EXIT INT TERM HUP
    return $rc
}

function project_export_run() {
    local folder=${1%/} code=1 bd=1 db="" dest="" dir active ver label php branch mariadb out state
    local changes ahead name sql="" readme steps=() parent real_dir branch_or_err
    shift
    while [ $# -gt 0 ]; do
        case $1 in
            --sin-codigo) code=0 ;;
            --sin-bd) bd=0 ;;
            --bd) db=$2; shift ;;
            --destino) dest=$2; shift ;;
            *) folder="" ;;
        esac
        shift
    done
    if [ -z "$folder" ] || { [ $code -eq 0 ] && [ $bd -eq 0 ]; }; then
        echo "Uso: nexum exportar-proyecto <carpeta> [--sin-codigo] [--sin-bd] [--bd <base>] [--destino <carpeta>]"
        return 1
    fi
    valid_project "$folder" || return 1
    dir=$HTDOCS_DIR/$folder
    active=$(active_dir)
    if [ -z "$active" ]; then
        echo "No hay ninguna versión activa: hace falta para saber con qué PHP se exporta (y su BBDD)"
        return 1
    fi
    ver=$(active_name)
    label=$(export_version_label "$ver")
    php=$(php_version "$active")
    branch=$(project_export_branch "$php")
    mariadb=$(stack_fields "$active" | cut -d'|' -f3)
    echo "Proyecto: $dir ($label · PHP ${php:-?})"

    if [ $code -eq 1 ]; then
        out=$(project_export_git "$dir")
        IFS='|' read -r _ state branch_or_err changes ahead _ <<< "$(head -1 <<< "$out")"
        case $state in
            2)
                echo "No se ha podido comprobar el código con git: $branch_or_err"
                echo "No se ha exportado nada."
                return 1
                ;;
            1)
                if [ "${changes:-0}" -gt 0 ]; then
                    echo "«$folder» tiene $changes $([ "$changes" -eq 1 ] && echo "cambio" || echo "cambios") sin commit:"
                    grep '^C|' <<< "$out" | cut -d'|' -f2- | sed 's/^/  /'
                    [ "$changes" -gt 8 ] && echo "  y $((changes - 8)) más"
                    echo "Haz commit antes de exportar (o descarta esos cambios): no se ha exportado nada."
                    return 1
                fi
                echo "Código: en git, sin cambios sin commit${branch_or_err:+ (rama $branch_or_err)}"
                [ "${ahead:-0}" -gt 0 ] && echo "Aviso: $ahead $([ "$ahead" -eq 1 ] && echo "commit" || echo "commits") sin subir a su rama remota (el zip lo lleva igualmente)"
                ;;
            *)
                echo "Código: no es un repositorio git, no se puede comprobar si tiene cambios sin commit"
                ;;
        esac
    fi

    if [ $bd -eq 1 ]; then
        if [ -n "$db" ]; then
            db_valid_name "$db" || return 1
            if ! db_names "$active" | grep -qxF -- "$db"; then
                echo "No hay ninguna base de datos $db en $label"
                return 1
            fi
        else
            db=$(project_export_db "$folder")
            if [ -z "$db" ]; then
                if [ $code -eq 0 ]; then
                    echo "$folder no tiene ninguna BBDD vinculada en $label: no hay nada que exportar"
                    return 1
                fi
                echo "Sin BBDD vinculada en $label: solo va el código"
                bd=0
            fi
        fi
    fi

    dest=${dest:-$(export_downloads)}
    parent=$(cd "$dest" 2> /dev/null && pwd -P)
    if [ -z "$parent" ] || [ ! -w "$parent" ]; then
        echo "No se puede escribir en ${dest:-la carpeta de descargas}"
        return 1
    fi
    real_dir=$(cd "$dir" && pwd -P)
    if [ $code -eq 1 ] && { [ "$parent" == "$real_dir" ] || [[ "$parent" == "$real_dir"/* ]]; }; then
        echo "El zip no puede ir dentro del propio proyecto ($parent)"
        return 1
    fi
    dest=$parent
    name=$(project_export_name "$folder" "$branch" "$dest")

    [ $code -eq 1 ] && steps+=("Comprobar el código")
    [ $bd -eq 1 ] && steps+=("Descargar la BBDD $db")
    steps+=("Escribir el zip")
    task_plan "Exportando $folder" "${steps[@]}"
    [ $code -eq 1 ] && task_step
    if [ "$DRY" -eq 1 ]; then
        [ $code -eq 1 ] && echo "  [simulacion] el código de $dir (sin .git) en $folder/"
        [ $bd -eq 1 ] && echo "  [simulacion] exportar-bd $db ($label) en $db.sql"
        echo "  [simulacion] LEEME-nexum.txt y el zip en $dest/$name"
        return 0
    fi
    # (sin la contraseña de administrador: la BBDD, con el MariaDB en marcha)
    if [ $bd -eq 1 ] && [ "${LVM_TAREA:-}" == 1 ] && out=$(gui_db_check) && [[ "$out" == no\|* ]]; then
        echo "${out#no|}"
        echo "No se ha exportado nada (o exporta solo el código, sin la BBDD)."
        return 1
    fi

    mkdir -p "$LOG_DIR" || return 1
    EXPORT_TMP=$(mktemp -d "$LOG_DIR/exportar.XXXXXX") || return 1
    EXPORT_PART=$dest/$name.parte
    if [ $bd -eq 1 ]; then
        task_step
        echo "== BBDD $db ($label)"
        sql=$EXPORT_TMP/$db.sql
        # (en otro proceso: export_database pone sus propias trampas de salida)
        if ! ( export_database "$db" "$sql" "$ver" ) || [ ! -f "$sql" ]; then
            echo "No se ha podido descargar la BBDD $db: no se ha exportado nada."
            return 1
        fi
    fi
    task_step
    echo "== Escribiendo el zip"
    readme="Exportado con $APP_NAME $APP_VERSION el $(date '+%d/%m/%Y a las %H:%M').

Proyecto: $folder
PHP: ${php:-?} ($label)
MariaDB: ${mariadb:--}

Contenido:"
    [ $code -eq 1 ] && readme+="
  $folder/  el código del proyecto (sin .git)"
    [ $bd -eq 1 ] && readme+="
  $db.sql  la base de datos $db (sin el administrador de pruebas de Nexum
  ni los cambios del correo de pruebas)"
    readme+="
  LEEME-nexum.txt  este fichero
"
    if ! python3 -I -c "$PROJECT_EXPORT_PY" zip "$([ $code -eq 1 ] && echo "$dir")" "$folder" "$EXPORT_PART" \
        "$dest/$name" "$sql" "$db.sql" "$readme"; then
        echo "No se ha exportado nada."
        return 1
    fi
    EXPORT_PART=""
    echo "Exportado: $dest/$name"
}
