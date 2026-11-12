# ===========================================================================
# Tiendas PrestaShop: parameters.php y cache
# ===========================================================================
# El repositorio de una tienda 1.7 no lleva app/config/parameters.php (esta en su .gitignore): al
# clonarla queda vacio ('parameters' => NULL) y PrestaShop dice "install" directory is missing. Se
# crea con la base cargada en local y claves nuevas, y se guarda una copia en PS_PARAMS_DIR para
# volver a ponerla (con las mismas claves) si se pierde. La primera vez que se carga una tienda se
# vacia su var/cache (la de produccion da error 500 en local); se apunta en PS_LOADED_FILE.
PS_PARAMS_DIR="$LOG_DIR/prestashop"
PS_LOADED_FILE="$LOG_DIR/prestashop-cargados"
# Carpetas clonadas con montar-proyecto (el dominio de su base no se falsea solo)
REPO_PROJECTS_FILE="$LOG_DIR/montados-de-repositorio"

# ¿Es una tienda PrestaShop? Por su configuracion, sus carpetas o "prestashop" en el nombre
function is_prestashop() {
    local dir=$HTDOCS_DIR/$1
    [[ "${1,,}" == *prestashop* ]] || [ -d "$dir/src/PrestaShopBundle" ] \
        || [ -f "$dir/classes/PrestaShopAutoload.php" ] || [ -n "$(ps_config "$1")" ]
}

# Base de una tienda cuya configuracion no la dice: la indicada, la recordada para la carpeta
# (~/.nexum/proyectos) o, en la version activa, la unica ps_<final de la carpeta>
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

# Medir, simular o limpiar sin seguir enlaces en ningun momento (limpieza, limpiar-proyecto y la var/cache
# de una tienda con sudo). Cada regla dice que limpiar dentro de una carpeta raiz:
#   <clave>|<raiz>|<tipo>|<ruta dentro de la raiz>|<patron>|<opciones>   (el patron puede llevar |)
# tipos: vaciar (todo lo de dentro de <ruta>, que se queda), ficheros (los de <ruta> que cumplen el patron,
# con comodines), entradas (lo de <ruta> cuyo nombre cumple el patron, una expresion: ficheros o carpetas
# enteras) y truncar (los ficheros de <ruta> que cumplen el patron se dejan a 0 bytes: los que un servicio
# tiene abiertos). Las partes de <ruta> pueden llevar comodines (modules/*/logs).
# opciones (separadas por comas): index (los index.php se quedan), edad=<segundos> (solo lo que lleva ese
# tiempo sin cambiar, ni ello ni nada de dentro), uso (no lo que tiene abierto un proceso, ni un socket o un
# .pid vivo dentro), uid=<n> (solo lo de ese usuario), solo=dir|fich.
# La raiz no puede ser un enlace; se abre desde / con O_NOFOLLOW (su ruta real) y desde ella cada carpeta,
# tambien con O_NOFOLLOW: un enlace en la ruta hace que esa regla no limpie nada. Dentro, los enlaces se
# borran sin seguirlos, no se pasa a otro disco (st_dev de la raiz) y todo se borra con su carpeta abierta
# (unlinkat/rmdir con dir_fd): si algo cambia por un enlace entre medias, falla en lugar de borrar fuera.
# Escribe L|<clave>|<bytes>|<ficheros>|<1 si hace falta root> por cada clave (en limpiar, lo borrado) y
# P|<clave>|<ruta> de cada regla con algo; al limpiar, Q|<clave>|<ruta> de lo que no se ha podido borrar
# (sale con 3) y U|<clave>|<ruta> de lo que se deja por estar en uso.
# Uso: CLEAN_PY medir|simular|limpiar <regla>...
CLEAN_PY='
import errno, fnmatch, os, re, socket, stat, subprocess, sys, time
mode, rules = sys.argv[1], sys.argv[2:]
me = os.geteuid()
now = time.time()
DIR = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
totals, order, paths, left, busy = {}, [], [], [], []
_open = None


def open_paths():
    """Lo que tienen abierto los procesos que se pueden ver (como root, todos) y los sockets en uso."""
    global _open
    if _open is not None:
        return _open
    found = set()
    if os.path.isdir("/proc/self/fd"):
        for pid in os.listdir("/proc"):
            # (sin este mismo proceso: tiene abiertas las carpetas que esta mirando)
            if not pid.isdigit() or int(pid) == os.getpid():
                continue
            try:
                found.add(os.readlink("/proc/%s/cwd" % pid))
            except OSError:
                pass
            try:
                fds = os.listdir("/proc/%s/fd" % pid)
            except OSError:
                continue
            for n in fds:
                try:
                    p = os.readlink("/proc/%s/fd/%s" % (pid, n))
                except OSError:
                    continue
                if p.startswith("/"):
                    found.add(p[:-10] if p.endswith(" (deleted)") else p)
        try:
            with open("/proc/net/unix") as f:
                for line in f.read().splitlines()[1:]:
                    parts = line.split()
                    if len(parts) >= 8 and parts[-1].startswith("/"):
                        found.add(parts[-1])
        except OSError:
            pass
    else:
        # (en el Mac, lsof: los de tu usuario o, como root, todos)
        try:
            out = subprocess.run(["lsof", "-n", "-P", "-w", "-Fn"], stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL, timeout=30).stdout.decode("utf-8", "replace")
            found.update(line[1:] for line in out.splitlines() if line.startswith("n/"))
        except (OSError, subprocess.SubprocessError):
            pass
    _open = found
    return found


def alive(pid):
    if pid <= 1:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def socket_alive(path):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(1)
    try:
        s.connect(path)
        return True
    except OSError as e:
        return e.errno not in (errno.ECONNREFUSED, errno.ENOENT, errno.ENOTSOCK)
    finally:
        s.close()


def in_use(path, info):
    for p in open_paths():
        if p == path or p.startswith(path + "/"):
            return True
    if any(alive(p) for p in info["pids"]):
        return True
    return any(socket_alive(s) for s in info["socks"])


def can_remove(dpath, dst, st):
    """Se puede borrar sin root: la carpeta es escribible y, si es como /tmp (sticky), la entrada es tuya."""
    if me == 0:
        return True
    if dst.st_mode & stat.S_ISVTX and st.st_uid != me and dst.st_uid != me:
        return False
    return os.access(dpath, os.W_OK | os.X_OK)


def new_info():
    return {"bytes": 0, "files": 0, "newest": 0, "root": False, "pids": [], "socks": []}


def scan(dfd, dpath, dst, name, st, dev, keep, info):
    """Suma en info lo que se borraria de la entrada name de dfd (st es su lstat)."""
    path = dpath + "/" + name
    info["newest"] = max(info["newest"], st.st_mtime)
    if stat.S_ISDIR(st.st_mode):
        if st.st_dev != dev:
            return
        if not can_remove(dpath, dst, st):
            info["root"] = True
        try:
            sub = os.open(name, DIR, dir_fd=dfd)
        except OSError:
            info["root"] = True
            return
        try:
            for n in os.listdir(sub):
                try:
                    s = os.stat(n, dir_fd=sub, follow_symlinks=False)
                except OSError:
                    continue
                scan(sub, path, st, n, s, dev, keep, info)
        except OSError:
            info["root"] = True
        finally:
            os.close(sub)
        return
    if keep and name == "index.php":
        return
    if not can_remove(dpath, dst, st):
        info["root"] = True
    info["files"] += 1
    if stat.S_ISREG(st.st_mode):
        info["bytes"] += st.st_size
        if name.endswith(".pid") and st.st_size < 64:
            try:
                fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=dfd)
                with os.fdopen(fd) as f:
                    info["pids"].append(int(f.read(30).strip() or 0))
            except (OSError, ValueError):
                pass
    elif stat.S_ISSOCK(st.st_mode):
        info["socks"].append(path)


def remove(dfd, dpath, name, st, dev, keep, res):
    """Borra la entrada name de dfd sin seguir enlaces. Devuelve True si ya no esta."""
    path = dpath + "/" + name
    if stat.S_ISDIR(st.st_mode):
        if st.st_dev != dev:
            return False
        try:
            sub = os.open(name, DIR, dir_fd=dfd)
            if os.fstat(sub).st_dev != dev:
                os.close(sub)
                return False
        except OSError:
            left.append((res["key"], path))
            return False
        gone = True
        try:
            for n in os.listdir(sub):
                try:
                    s = os.stat(n, dir_fd=sub, follow_symlinks=False)
                except FileNotFoundError:
                    continue
                if not remove(sub, path, n, s, dev, keep, res):
                    gone = False
        except OSError:
            left.append((res["key"], path))
            gone = False
        finally:
            os.close(sub)
        if not gone:
            return False
        try:
            os.rmdir(name, dir_fd=dfd)
        except FileNotFoundError:
            pass
        except OSError:
            left.append((res["key"], path))
            return False
        return True
    if keep and name == "index.php":
        return False
    try:
        os.unlink(name, dir_fd=dfd)
    except FileNotFoundError:
        return True
    except OSError:
        left.append((res["key"], path))
        return False
    res["files"] += 1
    if stat.S_ISREG(st.st_mode):
        res["bytes"] += st.st_size
    return True


def root_fd(root):
    """La raiz abierta desde / sin seguir enlaces (su ruta real): (fd, disco, ruta)."""
    if os.path.islink(root):
        raise OSError(errno.ELOOP, "es un enlace", root)
    real = os.path.realpath(root)
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    for p in [p for p in real.split("/") if p]:
        try:
            nfd = os.open(p, DIR, dir_fd=fd)
        finally:
            os.close(fd)
        fd = nfd
    return fd, os.fstat(fd).st_dev, real


def targets(fd, path, rel, dev):
    """Las carpetas rel de dentro de fd (cada parte puede llevar comodines), sin seguir enlaces ni pasar
    a otro disco: [(fd, ruta, lstat)]. Cierra fd."""
    cur = [(fd, path)]
    for seg in [s for s in rel.split("/") if s and s != "."]:
        nxt = []
        for dfd, dpath in cur:
            try:
                if seg == "..":
                    names = []
                elif any(c in seg for c in "*?["):
                    names = sorted(n for n in os.listdir(dfd) if fnmatch.fnmatchcase(n, seg))
                else:
                    names = [seg]
                for n in names:
                    try:
                        st = os.stat(n, dir_fd=dfd, follow_symlinks=False)
                        if stat.S_ISDIR(st.st_mode) and st.st_dev == dev:
                            nxt.append((os.open(n, DIR, dir_fd=dfd), dpath + "/" + n))
                    except OSError:
                        continue
            except OSError:
                pass
            finally:
                os.close(dfd)
        cur = nxt
    out = []
    for dfd, dpath in cur:
        st = os.fstat(dfd)
        if st.st_dev == dev:
            out.append((dfd, dpath, st))
        else:
            os.close(dfd)
    return out


def entries(dfd, kind, pattern, opts):
    """Las entradas de la carpeta que entran en la regla: [(nombre, lstat)]."""
    out = []
    try:
        names = sorted(os.listdir(dfd))
    except OSError:
        return out
    for n in names:
        if kind == "entradas":
            if not re.fullmatch(pattern, n):
                continue
        elif kind in ("ficheros", "truncar") and not fnmatch.fnmatchcase(n, pattern):
            continue
        try:
            st = os.stat(n, dir_fd=dfd, follow_symlinks=False)
        except OSError:
            continue
        isdir = stat.S_ISDIR(st.st_mode)
        if kind in ("ficheros", "truncar") and isdir:
            continue
        if kind == "truncar" and (not stat.S_ISREG(st.st_mode) or st.st_nlink != 1):
            continue
        if opts.get("solo") == "dir" and not isdir or opts.get("solo") == "fich" and not stat.S_ISREG(st.st_mode):
            continue
        if "uid" in opts and str(st.st_uid) != opts["uid"]:
            continue
        out.append((n, st))
    return out


def truncate(dfd, dpath, name, st, res):
    path = dpath + "/" + name
    try:
        fd = os.open(name, os.O_WRONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=dfd)
    except OSError:
        left.append((res["key"], path))
        return
    try:
        now_st = os.fstat(fd)
        if (now_st.st_ino, now_st.st_dev) != (st.st_ino, st.st_dev) or now_st.st_nlink != 1 \
                or not stat.S_ISREG(now_st.st_mode):
            left.append((res["key"], path))
            return
        os.ftruncate(fd, 0)
        res["files"] += 1
        res["bytes"] += now_st.st_size
    except OSError:
        left.append((res["key"], path))
    finally:
        os.close(fd)


for rule in rules:
    # (el patron de las entradas puede llevar | : es lo que queda entre la ruta y las opciones)
    parts = rule.split("|")
    if len(parts) < 6 or parts[2] not in ("vaciar", "ficheros", "entradas", "truncar"):
        print("Regla no valida: %s" % rule, file=sys.stderr)
        continue
    key, root, kind, rel, pattern, optstr = parts[0], parts[1], parts[2], parts[3], "|".join(parts[4:-1]), parts[-1]
    opts = dict((o.split("=", 1) + [""])[:2] for o in optstr.split(",") if o)
    keep = "index" in opts
    if key not in totals:
        totals[key] = {"key": key, "bytes": 0, "files": 0, "root": False}
        order.append(key)
    tot = totals[key]
    if not os.path.lexists(root):
        continue
    try:
        fd, dev, real = root_fd(root)
    except OSError as e:
        print("%s: %s, no se toca" % (root, e.strerror or e), file=sys.stderr)
        continue
    label = rel if kind == "vaciar" else (rel + "/" + pattern if rel not in ("", ".") else pattern)
    found = False
    for dfd, dpath, dst in targets(fd, real, rel, dev):
        try:
            names = entries(dfd, kind, pattern, opts) if kind != "vaciar" else entries(dfd, "", "", opts)
            for n, st in names:
                if kind == "truncar":
                    if st.st_size == 0:
                        continue
                    found = True
                    if me != 0 and not os.access(dpath + "/" + n, os.W_OK):
                        tot["root"] = True
                    if mode == "limpiar":
                        truncate(dfd, dpath, n, st, tot)
                    else:
                        tot["files"] += 1
                        tot["bytes"] += st.st_size
                    continue
                info = new_info()
                scan(dfd, dpath, dst, n, st, dev, keep, info)
                if not info["files"]:
                    # (una carpeta vacia de las entradas tambien es un resto: cuenta como uno)
                    if not (stat.S_ISDIR(st.st_mode) and kind == "entradas"):
                        continue
                    info["files"] = 1
                if "edad" in opts and now - info["newest"] < float(opts["edad"] or 0):
                    continue
                if "uso" in opts and in_use(dpath + "/" + n, info):
                    busy.append((key, dpath + "/" + n))
                    continue
                found = True
                if mode == "limpiar":
                    remove(dfd, dpath, n, st, dev, keep, tot)
                else:
                    tot["files"] += info["files"]
                    tot["bytes"] += info["bytes"]
                    tot["root"] = tot["root"] or info["root"]
        finally:
            os.close(dfd)
    if found and (key, label) not in paths:
        paths.append((key, label))

for key in order:
    t = totals[key]
    print("L|%s|%d|%d|%d" % (key, t["bytes"], t["files"], 1 if t["root"] else 0))
for key, label in paths:
    print("P|%s|%s" % (key, label))
for key, path in busy:
    print("U|%s|%s" % (key, path))
for key, path in left:
    print("Q|%s|%s" % (key, path))
sys.exit(3 if left else 0)
'
