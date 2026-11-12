# ===========================================================================
# Paso a /Library/Nexum (1.39.3)
# ===========================================================================
# Hasta la 1.39.2 las versiones y XAMPP-compartido estaban en /Applications, donde puede escribir el
# grupo admin (tu usuario): un programa tuyo podia cambiar una carpeta por otra entre la comprobacion
# y el uso como root. "nexum migrar" las pasa a /Library/Nexum, de root.

# Pasa, como root, las versiones de antes de la 1.39.3 de <antes> (/Applications) a <ahora>
# (/Library/Nexum): mueve XAMPP-X.Y[.Z] (solo las de root, con pvm-stack) y XAMPP-compartido, deja en
# <antes> un enlace a cada una (para lo tuyo que use las rutas viejas: root no pasa por ellos), cambia
# las rutas de su configuracion, sus scripts y sus enlaces, y las de las librerias de sus programas
# (install_name_tool y la firma local otra vez), repunta <enlace> (/Applications/XAMPP) y fija el
# php.ini, conf.d y extension_dir de PHP-FPM (las rutas que trae compiladas son las de antes). Lo que
# cambia queda en un diario, con el original enlazado, para deshacerlo. Las BBDD (var), los registros
# y los proyectos de htdocs no se tocan.
# Uso: migrar|deshacer|terminar <antes> <ahora> <diario> [<enlace> <plantilla de pvm-php-fpm>]
# Escribe M|version (o XAMPP-compartido) movida, S|carpeta|por que no, E|error, I|aviso
MIGRATE_PY='
import json, os, re, shutil, stat, subprocess, sys
mode, old, new, jdir = sys.argv[1:5]
link = sys.argv[5] if len(sys.argv) > 5 else ""
tmpl = sys.argv[6] if len(sys.argv) > 6 else ""
J = os.path.join(jdir, "diario.json")
VER = re.compile(r"^XAMPP-[0-9]+\.[0-9]+(\.[0-9]+)?$")
MACHO = (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe")
# Dentro de xamppfiles no se tocan los datos, los registros ni lo temporal
SKIP = ("var", "logs", "tmp", "phpmyadmin/tmp")
TOOLS = {"otool": "/usr/bin/otool", "install_name_tool": "/usr/bin/install_name_tool", "codesign": "/usr/bin/codesign"}
ROOT = 0
# (en las pruebas, sin root: otras herramientas, y tu usuario hace de root)
if os.getuid() != 0 and os.environ.get("LVM_PRUEBA_HERRAMIENTAS"):
    TOOLS = {k: os.path.join(os.environ["LVM_PRUEBA_HERRAMIENTAS"], k) for k in TOOLS}
    ROOT = os.getuid()
state = {}

def say(*f):
    print("|".join(str(x).replace("|", "/").replace("\n", " ") for x in f))
    sys.stdout.flush()

def save():
    tmp = J + ".nuevo"
    with open(tmp, "w") as f:
        json.dump(state, f)
    os.replace(tmp, J)

# Deshace lo del diario, en orden inverso (cada paso aunque falle otro: lo que no se pueda, se dice)
def undo(st):
    def each(items, fn):
        for item in reversed(items):
            try:
                fn(*item) if isinstance(item, list) else fn(item)
            except OSError as e:
                say("E", "no se ha podido deshacer %s: %s" % (item, e))
    def back_file(path, b):
        if os.path.lexists(b):
            os.replace(b, path)
    def drop(path):
        if os.path.lexists(path) and not os.path.isdir(path):
            os.unlink(path)
    def attrs(path, uid, gid, mode_):
        if os.path.lexists(path):
            os.lchown(path, uid, gid)
            os.chmod(path, mode_)
    def back_link(path, target):
        if os.path.islink(path):
            tmp = path + ".lvm-migracion"
            if os.path.lexists(tmp):
                os.unlink(tmp)
            os.symlink(target, tmp)
            os.rename(tmp, path)
    def unlink(path):
        if os.path.islink(path):
            os.unlink(path)
    def back_move(src, dst):
        if os.path.lexists(dst) and not os.path.lexists(src):
            os.rename(dst, src)
    each(st.get("files", []), back_file)
    each(st.get("created", []), drop)
    each(st.get("attrs", []), attrs)
    each(st.get("relinks", []), back_link)
    each(st.get("links", []), unlink)
    each(st.get("moves", []), back_move)

def backup(path):
    b = os.path.join(jdir, "b", str(len(state["files"])))
    os.link(path, b)
    state["files"].append([path, b])
    save()

def put(path, st, data):
    tmp = path + ".lvm-migracion"
    if os.path.lexists(tmp):
        os.unlink(tmp)
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(data)
    os.chown(tmp, st.st_uid, st.st_gid)
    os.chmod(tmp, stat.S_IMODE(st.st_mode))
    backup(path)
    os.rename(tmp, path)

def swap(subs, text):
    for rx, rep in subs:
        text = rx.sub(lambda m: rep, text)
    return text

def run(*args):
    r = subprocess.run(list(args), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode != 0:
        raise RuntimeError("%s: %s" % (os.path.basename(args[0]), r.stderr.decode("utf-8", "replace").strip()[:300]))
    return r.stdout.decode("utf-8", "replace")

LOADS = {"LC_LOAD_DYLIB", "LC_LOAD_WEAK_DYLIB", "LC_REEXPORT_DYLIB", "LC_LAZY_LOAD_DYLIB", "LC_LOAD_UPWARD_DYLIB"}
def load_commands(path):
    cmd, found = "", []
    for line in run(TOOLS["otool"], "-l", path).splitlines():
        w = line.split()
        if len(w) >= 2 and w[0] == "cmd":
            cmd = w[1]
        elif len(w) >= 2 and w[0] == "name" and (cmd in LOADS or cmd == "LC_ID_DYLIB"):
            found.append(("id" if cmd == "LC_ID_DYLIB" else "dep", line.strip()[5:].rsplit(" (offset", 1)[0]))
        elif len(w) >= 2 and w[0] == "path" and cmd == "LC_RPATH":
            found.append(("rpath", line.strip()[5:].rsplit(" (offset", 1)[0]))
    return found

# Un programa o una libreria: las rutas de sus librerias (install_name_tool) y la firma local de
# nuevo. Las cadenas que lleva compiladas no se cambian (nexum actualizar las rehace)
def macho(path, st, subs):
    args, seen = [], set()
    for kind, value in load_commands(path):
        nv = swap(subs, value.encode()).decode()
        if nv == value or (kind, value) in seen:
            continue
        seen.add((kind, value))
        if kind == "id":
            args += ["-id", nv]
        elif kind == "rpath":
            args += ["-rpath", value, nv]
        else:
            args += ["-change", value, nv]
    if not args:
        return
    tmp = path + ".lvm-migracion"
    if os.path.lexists(tmp):
        os.unlink(tmp)
    shutil.copyfile(path, tmp)
    os.chown(tmp, st.st_uid, st.st_gid)
    os.chmod(tmp, stat.S_IMODE(st.st_mode))
    try:
        run(TOOLS["install_name_tool"], *(args + [tmp]))
        run(TOOLS["codesign"], "--force", "--sign", "-", "--identifier", os.path.basename(path), tmp)
    except Exception:
        os.unlink(tmp)
        raise
    backup(path)
    os.rename(tmp, path)

# (sin leerlo entero: los programas pueden ser grandes)
def contains(path, needle):
    tail = b""
    with open(path, "rb") as f:
        while True:
            chunk = f.read(1 << 20)
            if not chunk:
                return False
            if needle in tail + chunk:
                return True
            tail = chunk[-len(needle):]

def rewrite(path, subs, extra=None):
    st = os.lstat(path)
    if not stat.S_ISREG(st.st_mode) or st.st_size < 4:
        return
    with open(path, "rb") as f:
        head = f.read(4)
    if not contains(path, (old + "/").encode()):
        return
    if head in MACHO:
        macho(path, st, subs)
        return
    # Otros binarios (.a, .mo...), no: cambiar la longitud de una ruta los romperia. Y nada enorme
    if st.st_size > 64 * 1024 * 1024:
        return
    with open(path, "rb") as f:
        data = f.read()
    if b"\0" in data:
        return
    text = swap(subs, data)
    if extra:
        text = text.replace(extra[0], extra[1])
    if text != data:
        put(path, st, text)

def relink(path, subs):
    target = os.readlink(path)
    nt = swap(subs, target.encode()).decode()
    if nt == target:
        return
    st = os.lstat(path)
    tmp = path + ".lvm-migracion"
    if os.path.lexists(tmp):
        os.unlink(tmp)
    os.symlink(nt, tmp)
    os.lchown(tmp, st.st_uid, st.st_gid)
    state["relinks"].append([path, target])
    save()
    os.rename(tmp, path)

def skipped(top, path):
    rel = os.path.relpath(path, top)
    return any(rel == s or rel.startswith(s + "/") for s in SKIP)

def stack(dst, subs):
    top = os.path.join(dst, "xamppfiles")
    ftp = os.path.join(top, "etc/proftpd.conf")
    for d, dirs, files in os.walk(dst):
        for name in list(dirs):
            p = os.path.join(d, name)
            if os.path.islink(p):
                relink(p, subs)
                dirs.remove(name)
            elif skipped(top, p):
                dirs.remove(name)
        for name in files:
            p = os.path.join(d, name)
            if os.path.islink(p):
                relink(p, subs)
            elif p == ftp:
                # El FTP entra (chroot, como root) en su htdocs por su ruta, no por /Applications/XAMPP
                rewrite(p, subs, ((old + "/XAMPP/xamppfiles").encode(), top.encode()))
            elif not p.endswith(".lvm-migracion"):
                rewrite(p, subs)
    # PHP-FPM con el php.ini y conf.d de su carpeta nueva (las rutas compiladas son las de antes)
    fpm = os.path.join(top, "bin/pvm-php-fpm")
    php = ""
    try:
        php = open(os.path.join(top, "etc/pvm-php")).read().strip()
    except OSError:
        pass
    if tmpl and re.match(r"^[0-9]+\.[0-9]+\.[0-9]+$", php) and os.path.isfile(fpm) and not os.path.islink(fpm):
        want = tmpl.replace("@ROOT@", top).replace("@VERSION@", php).encode()
        cur = open(fpm, "rb").read()
        if cur != want and b"--fpm-config" in cur:
            put(fpm, os.lstat(fpm), want)
    # extension_dir: el que trae compilado PHP es el de antes
    ini = os.path.join(top, "php/etc/php.ini")
    conf_d = os.path.join(top, "php/etc/conf.d")
    exts = [e for e in sorted(os.listdir(os.path.join(top, "php/lib/php/extensions")))
            if os.path.isdir(os.path.join(top, "php/lib/php/extensions", e))] \
        if os.path.isdir(os.path.join(top, "php/lib/php/extensions")) else []
    has = os.path.isfile(ini) and re.search(r"(?m)^[ \t]*extension_dir[ \t]*=", open(ini, encoding="utf-8", errors="replace").read())
    pin = os.path.join(conf_d, "00-lvm-rutas.ini")
    if not has and len(exts) == 1 and os.path.isdir(conf_d) and not os.path.islink(conf_d) and not os.path.lexists(pin):
        cst = os.lstat(conf_d)
        fd = os.open(pin, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
        state["created"].append(pin)
        save()
        with os.fdopen(fd, "w") as f:
            f.write("; lvm-instalador (1.39.3): las extensiones, por su carpeta de %s (la ruta que trae\n"
                    "; compilada PHP es la de %s, y root no pasa por alli)\nextension_dir = \"%s\"\n"
                    % (new, old, os.path.join(top, "php/lib/php/extensions", exts[0])))
        os.chown(pin, cst.st_uid, cst.st_gid)

def migrate():
    global state
    if os.path.exists(J):
        st = json.load(open(J))
        if not st.get("done"):
            say("I", "Se deshace lo que quedo a medias la otra vez")
            undo(st)
        shutil.rmtree(jdir)
    elif os.path.lexists(jdir):
        shutil.rmtree(jdir)
    nst = os.lstat(new)
    if not stat.S_ISDIR(nst.st_mode) or nst.st_uid != ROOT or nst.st_mode & 0o022:
        say("E", "%s no es una carpeta de root" % new)
        sys.exit(1)
    moves = []
    for name in sorted(os.listdir(old)):
        src, dst = os.path.join(old, name), os.path.join(new, name)
        if not (VER.match(name) or name == "XAMPP-compartido") or os.path.islink(src) or not os.path.isdir(src):
            continue
        if name != "XAMPP-compartido":
            if not os.path.isfile(os.path.join(src, "xamppfiles/etc/pvm-stack")):
                say("S", src, "no es una version del gestor")
                continue
            if os.lstat(src).st_uid != ROOT or os.lstat(os.path.join(src, "xamppfiles")).st_uid != ROOT:
                say("S", src, "no es de root: no se pasa (vuelve a instalarla con nexum actualizar)")
                continue
        if os.path.lexists(dst):
            say("E", "ya existe %s: no se mueve nada" % dst)
            sys.exit(1)
        moves.append((src, dst))
    if not moves:
        return
    os.mkdir(jdir, 0o700)
    os.mkdir(os.path.join(jdir, "b"), 0o700)
    state = {"moves": [], "links": [], "files": [], "created": [], "attrs": [], "relinks": [], "done": False}
    save()
    try:
        for src, dst in moves:
            os.rename(src, dst)
            state["moves"].append([src, dst])
            save()
            os.symlink(dst, src)
            state["links"].append(src)
            save()
        subs = [(re.compile(re.escape((old + "/" + os.path.basename(d)).encode()) + rb"(?![A-Za-z0-9._-])"),
                 (new + "/" + os.path.basename(d)).encode()) for s, d in moves]
        for src, dst in moves:
            if os.path.basename(dst) == "XAMPP-compartido":
                # Solo su configuracion (los proyectos de htdocs no se tocan) y la carpeta, de root
                for f in [os.path.join(dst, "httpd-vhosts.conf")] + [
                        os.path.join(dst, "docker-claves", n) for n in
                        (sorted(os.listdir(os.path.join(dst, "docker-claves")))
                         if os.path.isdir(os.path.join(dst, "docker-claves")) and not os.path.islink(os.path.join(dst, "docker-claves")) else [])
                        if n.endswith(".conf")]:
                    if os.path.isfile(f) and not os.path.islink(f):
                        rewrite(f, subs)
                st = os.lstat(dst)
                if st.st_uid != ROOT or stat.S_IMODE(st.st_mode) != 0o755 or (ROOT == 0 and st.st_gid != 0):
                    state["attrs"].append([dst, st.st_uid, st.st_gid, stat.S_IMODE(st.st_mode)])
                    save()
                    os.lchown(dst, ROOT, 0 if ROOT == 0 else st.st_gid)
                    os.chmod(dst, 0o755)
                say("M", "XAMPP-compartido")
                continue
            stack(dst, subs)
            say("M", os.path.basename(dst)[len("XAMPP-"):])
        # El enlace a la version activa, a su carpeta nueva
        if link and os.path.islink(link):
            target = os.readlink(link)
            for src, dst in moves:
                if target.rstrip("/") == src:
                    tmp = link + ".lvm-migracion"
                    if os.path.lexists(tmp):
                        os.unlink(tmp)
                    os.symlink(dst, tmp)
                    state["relinks"].append([link, target])
                    save()
                    os.rename(tmp, link)
    except Exception as e:
        say("E", "%s: %s" % (type(e).__name__, e))
        undo(state)
        shutil.rmtree(jdir, ignore_errors=True)
        say("I", "Se ha dejado todo como estaba")
        sys.exit(1)

if mode == "migrar":
    migrate()
elif mode == "deshacer":
    if os.path.exists(J):
        undo(json.load(open(J)))
        shutil.rmtree(jdir)
        say("I", "Se ha dejado todo como estaba")
elif mode == "terminar":
    if os.path.exists(J):
        state = json.load(open(J))
        state["done"] = True
        save()
        shutil.rmtree(jdir)
else:
    sys.exit(2)
'

# Librerias que cargan los programas de una version (como root, en su carpeta de root): solo de ella
# misma o del sistema. Una de /opt/homebrew o de otra carpeta tuya la cargaria Apache como root. Los
# LC_RPATH, si algo se carga con @rpath. Uso: <carpeta XAMPP-X>. Escribe lo que no vale
MACHO_AUDIT_PY='
import os, stat, subprocess, sys
top = os.path.realpath(sys.argv[1])
OTOOL = "/usr/bin/otool"
if os.getuid() != 0 and os.environ.get("LVM_PRUEBA_HERRAMIENTAS"):
    OTOOL = os.path.join(os.environ["LVM_PRUEBA_HERRAMIENTAS"], "otool")
MACHO = (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe")
SYSTEM = ("/usr/lib/", "/System/Library/")
LOADS = {"LC_LOAD_DYLIB", "LC_LOAD_WEAK_DYLIB", "LC_REEXPORT_DYLIB", "LC_LAZY_LOAD_DYLIB", "LC_LOAD_UPWARD_DYLIB"}
bad = []
def inside(p):
    p = os.path.realpath(p)
    return p == top or p.startswith(top + "/")
def ok_path(p):
    return p.startswith(SYSTEM) and ".." not in p or inside(p)
def commands(path):
    r = subprocess.run([OTOOL, "-l", path], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if r.returncode != 0:
        return None
    cmd, found = "", []
    for line in r.stdout.decode("utf-8", "replace").splitlines():
        w = line.split()
        if len(w) >= 2 and w[0] == "cmd":
            cmd = w[1]
        elif len(w) >= 2 and w[0] == "name" and cmd in LOADS:
            found.append(("dep", line.strip()[5:].rsplit(" (offset", 1)[0]))
        elif len(w) >= 2 and w[0] == "path" and cmd == "LC_RPATH":
            found.append(("rpath", line.strip()[5:].rsplit(" (offset", 1)[0]))
    return found
def resolve(value, base):
    for k in ("@loader_path", "@executable_path"):
        if value == k or value.startswith(k + "/"):
            return base + value[len(k):]
    return value
uses_rpath, rpaths = False, []
for d, dirs, files in os.walk(os.path.join(top, "xamppfiles")):
    rel = os.path.relpath(d, os.path.join(top, "xamppfiles"))
    if rel == "var" or rel.startswith("var/"):
        dirs[:] = []
        continue
    for name in files:
        p = os.path.join(d, name)
        try:
            st = os.lstat(p)
            if not stat.S_ISREG(st.st_mode) or st.st_size < 4:
                continue
            with open(p, "rb") as f:
                if f.read(4) not in MACHO:
                    continue
        except OSError:
            continue
        found = commands(p)
        if found is None:
            bad.append("%s (no se puede leer)" % os.path.relpath(p, top))
            continue
        for kind, value in found:
            if kind == "rpath":
                rpaths.append((p, value, resolve(value, d)))
            elif value.startswith("@rpath/"):
                uses_rpath = True
            elif not ok_path(resolve(value, d)):
                bad.append("%s -> %s" % (os.path.relpath(p, top), value))
# Las rutas de busqueda (LC_RPATH) solo cuentan si algo se carga con @rpath: entonces, dentro de la version
if uses_rpath:
    for p, value, real in rpaths:
        if not ok_path(real):
            bad.append("%s -> LC_RPATH %s" % (os.path.relpath(p, top), value))
for b in bad[:50]:
    print(b)
sys.exit(1 if bad else 0)
'

# Versiones de antes de la 1.39.3 que siguen en /Applications (carpetas, no enlaces, con pvm-stack) y
# XAMPP-compartido si sigue alli: lo que pasa a /Library/Nexum con nexum migrar
function legacy_dirs() {
    local d name
    [ -n "$TEST_DIR" ] && return 0
    for d in "$LEGACY_DIR"/XAMPP-*; do
        name=${d##*/}
        [ -d "$d" ] && [ ! -L "$d" ] || continue
        if [[ "$name" =~ ^XAMPP-[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] && [ -f "$d/xamppfiles/etc/pvm-stack" ]; then
            echo "$d"
        elif [ "$name" == XAMPP-compartido ]; then
            echo "$d"
        fi
    done
}

# Lo que se comprueba de una version recien movida: que sus programas solo cargan librerias suyas o
# del sistema (como root), que arrancan (con tu usuario: librerias, rutas y firmas) y que su
# configuracion ya no lleva a /Applications. Escribe los problemas
function stack_check() {
    local dir=$1 top=$1/xamppfiles name out p
    name=$(basename "$1")
    if ! out=$($SUDO /usr/bin/python3 -I -c "$MACHO_AUDIT_PY" "$dir" 2>&1); then
        echo "  $name carga librerias de fuera de su carpeta:"
        head -5 <<< "$out" | sed 's/^/    /'
    fi
    for p in "apache2/bin/httpd -v" "php/bin/php -n -v" "php/sbin/php-fpm -n -v" "mysql/bin/mariadbd --no-defaults --version" \
            "proftpd/sbin/proftpd -v"; do
        [ -x "$top/${p%% *}" ] || continue
        "$top/${p%% *}" ${p#* } > /dev/null 2>&1 < /dev/null || echo "  $name: ${p%% *} no arranca desde $BASE_DIR"
    done
    out=$(grep -rlsE "$LEGACY_DIR/XAMPP-(compartido|[0-9])" "$top/etc" "$top/xampp" "$top/bin/pvm-php-fpm" \
        "$top/php/etc" "$top/apache2/conf" 2> /dev/null | head -3)
    [ -n "$out" ] && echo "  $name: estos ficheros siguen llevando a $LEGACY_DIR: $(tr '\n' ' ' <<< "$out")"
    return 0
}

# compose.yaml de los proyectos en Docker: su carpeta de htdocs, la de /Library/Nexum
function docker_refresh_compose() {
    local f
    for f in "$DOCKER_DIR"/*/compose.yaml; do
        [ -f "$f" ] && [ ! -L "$f" ] && [ -O "$f" ] && grep -qF "$LEGACY_DIR/XAMPP-compartido/" "$f" || continue
        python3 -I - "$f" "$LEGACY_DIR/XAMPP-compartido/" "$COMMON/" <<'EOF' || continue
import os, sys
path, old, new = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
tmp = path + ".nuevo"
with open(tmp, "w", encoding="utf-8") as f:
    f.write(text.replace(old, new))
os.chmod(tmp, os.stat(path).st_mode & 0o777)
os.replace(tmp, path)
EOF
        echo "  Docker: $(basename "$(dirname "$f")") usa ya $HTDOCS_DIR (se nota al arrancarlo otra vez)"
    done
}

# ¿Hay algo en marcha de las versiones del gestor (las de /Applications de antes o las de BASE_DIR)?
# Como lampp_running, pero sin el XAMPP oficial
function stacks_running() {
    pgrep -f "^($LEGACY_DIR|$BASE_DIR)/XAMPP-[0-9][0-9.]*/xamppfiles/(apache2/bin/httpd|mysql/bin/mariadbd|proftpd/sbin/proftpd)( |$)" > /dev/null
}

# nexum migrar: las versiones de antes de la 1.39.3 pasan de /Applications a /Library/Nexum
# (MIGRATE_PY). Antes se para todo, con kill (como root no se ejecuta nada de /Applications); despues
# se comprueba cada una en su sitio nuevo y, si algo falla, se deja todo como estaba. Las BBDD, los
# proyectos, los vhosts, los certificados y /etc/hosts se conservan. Se puede repetir (si no queda
# nada en /Applications, no hace nada). Devuelve 0 si ya no queda nada por pasar
function stacks_migrate() {
    local list was="" out rc kind a b v problems="" moved=() jdir=$BASE_DIR/.migracion
    list=$(legacy_dirs)
    [ -n "$list" ] || return 0
    echo "Las versiones pasan de $LEGACY_DIR a $BASE_DIR (una carpeta de root, que no puede cambiar tu usuario):"
    sed 's/^/  /' <<< "$list"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] se pararia lo que este en marcha y se moverian con sus BBDD; en $LEGACY_DIR quedaria un enlace a cada una"
        echo "  [simulacion] se cambiarian sus rutas, se comprobarian y, si algo fallara, se dejaria todo como estaba"
        return 0
    fi
    [ -n "$SUDO" ] && [ -z "$TEST_DIR" ] || return 1
    sudo -v || return 1
    boot_root_owned "$BASE_DIR" || { echo "$BASE_DIR no es una carpeta de root: no se mueve nada."; return 1; }
    # (solo si hay algo de las versiones del gestor en marcha: el XAMPP oficial, si lo hay, sigue)
    if stacks_running; then
        was=$(active_dir)
        echo "Parando lo que esta en marcha..."
        close_processes --todos
    fi
    if stacks_running; then
        echo "Sigue algo de XAMPP en marcha: no se mueve nada. Cierralo (nexum cerrar-procesos --todos) y vuelve a probar."
        return 1
    fi
    echo "Moviendolas y cambiando sus rutas (sus programas se vuelven a firmar: puede tardar unos minutos)..."
    out=$($SUDO /usr/bin/python3 -I -c "$MIGRATE_PY" migrar "$LEGACY_DIR" "$BASE_DIR" "$jdir" "$LINK" "$(fpm_script_template)")
    rc=$?
    while IFS='|' read -r kind a b; do
        case $kind in
            M) if [ "$a" == XAMPP-compartido ]; then
                   echo "  XAMPP-compartido -> $COMMON"
               else
                   echo "  XAMPP-$a -> $BASE_DIR/XAMPP-$a"
                   moved+=("$a")
               fi ;;
            S) echo "  No se pasa $a: $b" ;;
            E) echo "  Error: $a${b:+ ($b)}" ;;
            I) echo "  $a" ;;
        esac
    done <<< "$out"
    if [ $rc -ne 0 ]; then
        echo "No se ha movido nada. Si no se ve por que, pasa este registro."
        return 1
    fi
    echo "Comprobandolas en su sitio nuevo..."
    for v in "${moved[@]}"; do
        out=$(stack_check "$BASE_DIR/XAMPP-$v")
        [ -n "$out" ] && problems+="$out"$'\n'
    done
    if [ -n "$problems" ]; then
        printf '%s' "$problems"
        echo "Se deja todo como estaba (en $LEGACY_DIR)..."
        $SUDO /usr/bin/python3 -I -c "$MIGRATE_PY" deshacer "$LEGACY_DIR" "$BASE_DIR" "$jdir" | sed 's/^I|/  /; s/^E|/  Error: /'
        return 1
    fi
    $SUDO /usr/bin/python3 -I -c "$MIGRATE_PY" terminar "$LEGACY_DIR" "$BASE_DIR" "$jdir" || return 1
    # Los vhosts y su carpeta, de root (si alguna version anterior los hizo tuyos), y los Docker
    vhosts_root
    docker_refresh_compose
    echo "Hecho: las versiones estan en $BASE_DIR. Docker Desktop: añade $HTDOCS_DIR en Settings > Resources > File sharing."
    [ ${#moved[@]} -gt 0 ] && [ -n "$was" ] && [ -d "$BASE_DIR/$(basename "$was")" ] && use_version "$(version_name "$was")"
    return 0
}

# Comando nexum de /opt/homebrew/bin: a este gestor (se crea si no esta, como hacia el instalador
# del .dmg; si lleva a otro programa, no se toca). Los de antes de la 1.57.11 se quitan: lvm-instalador
# si es un enlace a un *-instalador.sh, y lvm solo si es un enlace a un lvm-instalador.sh (cualquier
# otro lvm es de otro programa)
function point_commands() {
    local link=$CMD_DIR/nexum
    [ "$DRY" -eq 1 ] && return 0
    [ -d "$CMD_DIR" ] && [ -w "$CMD_DIR" ] || return 0
    if [ -L "$link" ]; then
        [[ "$(readlink "$link")" == */[lp]vm-instalador.sh ]] && [ "$(readlink "$link")" != "$SELF" ] \
            && ln -sfh "$SELF" "$link"
    elif [ ! -e "$link" ]; then
        ln -s "$SELF" "$link"
    fi
    drop_old_commands
}

# Quita los comandos de antes de la 1.57.11 (lvm-instalador, y lvm si era de este programa). Nunca un
# lvm que no sea un enlace a un lvm-instalador.sh
function drop_old_commands() {
    local link
    [ "$DRY" -eq 1 ] && return 0
    link=$CMD_DIR/lvm-instalador
    [ -L "$link" ] && [[ "$(readlink "$link")" == */*-instalador.sh ]] && rm -f "$link"
    link=$CMD_DIR/lvm
    [ -L "$link" ] && [[ "$(readlink "$link")" == *lvm-instalador.sh ]] && rm -f "$link"
    return 0
}

# La copia de antes de la 1.39.3 (~/lvm-instalador/lvm-instalador.sh, o a la que apuntaban los
# comandos o la aplicacion) se queda en un aviso que abre el gestor de root: asi no la usa nadie para
# nada de root aunque un programa tuyo la cambie. Nunca una version mas nueva que esta
function retire_old_copies() {
    local f link plist app list=("$HOME/lvm-instalador/lvm-instalador.sh")
    for link in "$CMD_DIR/nexum" "$CMD_DIR/lvm-instalador" "$CMD_DIR/lvm"; do
        [ -L "$link" ] && list+=("$(readlink "$link")")
    done
    for app in "$APP_BUNDLE" "${OLD_APP_BUNDLES[@]}"; do
        plist=$(/usr/libexec/PlistBuddy -c "Print :LVMScript" "$app/Contents/Info.plist" 2> /dev/null) && list+=("$plist")
    done
    for f in "${list[@]}"; do
        [ -n "$f" ] && [ "$f" != "$TRUSTED_SCRIPT" ] && [[ "$f" == "$HOME"/* ]] && [ -f "$f" ] && [ ! -L "$f" ] \
            && [ -O "$f" ] && grep -q '^APP_VERSION=' "$f" && ! script_is_newer "$f" || continue
        printf '#!/bin/bash\n# Nexum Dev Stack ya no esta aqui: desde la 1.39.3 el gestor esta en %s,\n# de root. Este fichero solo lo abre.\nexec /bin/bash %s "$@"\n' \
            "$TRUSTED_DIR" "$TRUSTED_SCRIPT" > "$f.nuevo" && chmod 755 "$f.nuevo" && mv -f "$f.nuevo" "$f" \
            && echo "  $f ahora solo abre $TRUSTED_SCRIPT"
    done
}

# nexum migrar [--ventana] (lo lanza tambien instalar-gestor): lo que queda de antes de la
# 1.39.3. Las versiones pasan a /Library/Nexum, la copia de antes se queda en un aviso, y los comandos
# y la aplicacion apuntan a este gestor. Con --ventana, al final abre la ventana (desde el instalador
# del .dmg, LVM_INSTALADOR=1, la deja lista y la abre el instalador, con su boton). Se puede repetir
function gestor_migrate() {
    local rc=0
    if [ -z "$TEST_DIR" ] && [ "$SELF" != "$TRUSTED_SCRIPT" ]; then
        echo "migrar lo hace el gestor de root ($TRUSTED_SCRIPT): bash $SELF instalar-gestor"
        return 1
    fi
    boot_step 82 "Comprobando las versiones de PHP (las de antes de la 1.39.3 pasan a /Library/Nexum)"
    stacks_migrate || rc=1
    boot_step 86 "Creando la orden nexum"
    if [ "$DRY" -eq 0 ]; then
        retire_old_copies
        point_commands
        migrate_old_app
    fi
    boot_step 90 "Preparando la aplicación «$APP_NAME» (la primera vez se compila la ventana: un minuto)"
    if [ "$1" == --ventana ]; then
        open_window || rc=1
    elif [ -d "$APP_BUNDLE" ]; then
        update_app
    fi
    [ $rc -eq 0 ] && [ -n "$(legacy_dirs)" ] && rc=1
    [ $rc -eq 0 ] && boot_step 100 "Se ha finalizado la instalación"
    return $rc
}

# Ejecuta el script xampp de la version montada como root, por su ruta real y solo si
# trusted_version_dir la da por buena. El XAMPP oficial (una carpeta, no un enlace) va como antes.
function xampp_ctl() {
    local real
    if [ -z "$SUDO" ]; then
        "$LINK/xamppfiles/xampp" "$@"
        return
    fi
    if [ ! -L "$LINK" ]; then
        # El XAMPP oficial (una carpeta, no el enlace): su script no se ejecuta nunca como root. Lleva
        # programas y librerias que el gestor no revisa, y /Applications la puede cambiar el grupo
        # admin (tu usuario). Se arranca desde su panel (manager-osx); para pararlo, official_stop
        echo "El XAMPP oficial de $LINK no se arranca ni se para desde aqui: usa su panel (manager-osx),"
        echo "o apartalo (nexum apartar) para usar las versiones del gestor."
        return 1
    fi
    real=$(readlink "$LINK")
    if ! trusted_version_dir "$real"; then
        if [[ "$real" == "$LEGACY_DIR"/XAMPP-* ]]; then
            echo "No se arranca ni se para $real como administrador: esta en $LEGACY_DIR (lo puede cambiar"
            echo "el grupo admin). Pasala a $BASE_DIR con: nexum migrar"
        else
            echo "No se arranca ni se para $real como administrador: no es de root, tiene enlaces o el"
            echo "grupo puede cambiarlo. Dejalo bien con: nexum asegurar --todas"
        fi
        return 1
    fi
    # (root vuelve a comprobar la ruta antes de ejecutarlo: ROOT_EXEC_PY)
    $SUDO "$real/xamppfiles/xampp" "$@"
}

# ¿Esta en marcha un servicio (apache, mariadb o ftp) de la version montada? Por su .pid: sin sudo,
# macOS no enseña la orden de los procesos de root
function service_running() {
    local dir pidf pid
    dir=$(active_dir)
    [ -n "$dir" ] || return 1
    case $1 in
        apache) pidf=logs/httpd.pid ;;
        mariadb) pidf=var/mysql/mysqld.pid ;;
        ftp) pidf=var/proftpd/proftpd.pid ;;
        *) return 1 ;;
    esac
    [ -r "$dir/xamppfiles/$pidf" ] || return 1
    pid=$(head -1 "$dir/xamppfiles/$pidf" 2> /dev/null | tr -dc '0-9')
    [ -n "$pid" ] && ps -p "$pid" > /dev/null 2>&1
}

# Puertos de XAMPP que escuchan en toda la red y no solo en este Mac, uno por linea
function exposed_ports() {
    netstat -an -p tcp 2> /dev/null | awk -v ports=" $PORT_HTTP $PORT_HTTPS $PORT_MYSQL $PORT_FTP " '$NF == "LISTEN" {
        a = $4; p = a; sub(/.*\./, "", p); h = substr(a, 1, length(a) - length(p) - 1)
        if (index(ports, " " p " ") && h !~ /^(127\.|::1$|fe80::1%lo0$)/) print p
    }' | sort -un
}

# Servicios abiertos a la red, para avisar: «Apache (80, 443), MariaDB (3306)»
function exposed_summary() {
    local ports p apache="" out=""
    lampp_running || return 0
    ports=$(exposed_ports)
    [ -z "$ports" ] && return 0
    for p in $ports; do
        case $p in
            "$PORT_HTTP"|"$PORT_HTTPS") apache+="${apache:+, }$p" ;;
        esac
    done
    [ -n "$apache" ] && out="Apache ($apache)"
    grep -qx "$PORT_MYSQL" <<< "$ports" && out+="${out:+, }MariaDB ($PORT_MYSQL)"
    grep -qx "$PORT_FTP" <<< "$ports" && out+="${out:+, }FTP ($PORT_FTP)"
    echo "$out"
}

# asegurar [version]: lo que falte para que solo se pueda entrar desde este Mac. Si es la version en
# marcha y algo sigue abierto a la red, se reinicia para aplicarlo.
function secure_command() {
    local version=$1 dir changed=1 rc moved=0
    if [ "$version" == "--todas" ]; then
        # Las de antes de la 1.39.3, primero a /Library/Nexum (si no, no se pueden arrancar como root)
        stacks_migrate || moved=1
        secure_all
        rc=$?
        [ $moved -eq 1 ] && rc=2
        htdocs_close_world "$HTDOCS_DIR" --otros
        hosts_fake locales
        vhosts_root
        [ $rc -eq 2 ] && return 1
        dir=$(active_dir)
        if [ -n "$dir" ] && lampp_running && { [ $rc -eq 0 ] || [ -n "$(exposed_ports)" ]; }; then
            echo "Reiniciando $(basename "$dir") para aplicarlo..."
            run xampp_ctl restart > /dev/null || { echo "No se ha podido reiniciar"; return 1; }
        fi
        lampp_running && wait_mariadb && secure_mariadb
        echo "Todas las versiones son solo para este Mac"
        return 0
    fi
    if [ -n "$version" ]; then
        if valid_version_name "$version" && [ ! -d "$BASE_DIR/XAMPP-$version" ] && [ -d "$LEGACY_DIR/XAMPP-$version" ] \
                && [ ! -L "$LEGACY_DIR/XAMPP-$version" ] && [ -z "$TEST_DIR" ]; then
            echo "XAMPP-$version sigue en $LEGACY_DIR (de antes de la 1.39.3): pasala a $BASE_DIR con: nexum migrar"
            return 1
        fi
        valid_version_name "$version" && [ -d "$BASE_DIR/XAMPP-$version" ] \
            || { echo "No existe la version $version"; return 1; }
        dir=$BASE_DIR/XAMPP-$version
    else
        dir=$(active_dir)
        [ -n "$dir" ] || { echo "No hay ninguna version activa (indica cual: nexum asegurar <version>)"; return 1; }
    fi
    secure_version "$dir"
    rc=$?
    [ $rc -eq 2 ] && { echo "No se ha podido dejar $(basename "$dir") solo para este Mac"; return 1; }
    [ $rc -eq 0 ] && changed=0
    vhosts_root && changed=0
    if [ "$(realpath_f "$dir")" == "$(active_dir)" ] && lampp_running \
        && { [ $changed -eq 0 ] || [ -n "$(exposed_ports)" ]; }; then
        echo "Reiniciando $(basename "$dir") para aplicarlo..."
        run xampp_ctl restart > /dev/null || { echo "No se ha podido reiniciar"; return 1; }
        [ "$DRY" -eq 1 ] && return 0
        sleep 1
        local left=$(exposed_summary)
        if [ -n "$left" ]; then
            echo "Sigue abierto a la red: $left"
            echo "Puede que no sea de XAMPP (otro programa en el mismo puerto): nexum procesos"
            return 1
        fi
    fi
    [ "$(realpath_f "$dir")" == "$(active_dir)" ] && lampp_running && wait_mariadb && secure_mariadb
    [ $changed -eq 1 ] && echo "$(basename "$dir") ya era solo para este Mac: no hay nada que cambiar"
    echo "Solo se puede entrar desde este Mac"
}

# servicio apache|mariadb|ftp arrancar|parar|reiniciar: un servicio de la version montada (lo que
# hace el panel de XAMPP). El FTP arrancado asi sigue arrancando con la version hasta que se pare.
function service_control() {
    local name=$1 action=$2 dir cmds=() c
    dir=$(active_dir)
    if [ -z "$dir" ]; then
        echo "No hay ninguna version activa"

        return 1
    fi
    case "$name" in
        apache) c=apache ;;
        mariadb|mysql) c=mysql ;;
        ftp) c=ftp ;;
        *) echo "Uso: nexum servicio apache|mariadb|ftp arrancar|parar|reiniciar"; return 1 ;;
    esac
    case "$action" in
        arrancar|start) cmds=("start$c") ;;
        parar|stop) cmds=("stop$c") ;;
        reiniciar|restart) cmds=("stop$c" "start$c") ;;
        *) echo "Uso: nexum servicio apache|mariadb|ftp arrancar|parar|reiniciar"; return 1 ;;
    esac
    # Antes de arrancar: solo para este Mac y nada de otras versiones ocupando el puerto
    if [ "${cmds[-1]}" == "start$c" ]; then
        secure_version "$dir"
        secure_failed $? "$dir" && return 1
        vhosts_root
        close_processes
    fi
    for c in "${cmds[@]}"; do
        run xampp_ctl "$c" || return 1
    done
    mailpit_sync
}

# Para la ventana (menu Gestor > Buscar actualizaciones), solo cuando se pide:
#   U|version|fecha|sha256|ruta del .zip   version nueva de GitHub, descargada y con la firma comprobada
#   I|texto                                avisos (sin conexion, sin firma...)
#   O|origen y N|version|fecha|sha256|ruta del .dmg mas nuevo que esta version que haya en Descargas,
#   si en GitHub no hay ninguna (sin conexion, por ejemplo). Ese no va firmado: se dice de donde se
#   descargo y su huella, y se abre para ejecutar su instalador
UPDATES_DIR="$LOG_DIR/actualizaciones"
# Publicaciones de GitHub (JSON de la API en la entrada, la lista de las ultimas): la version de Mac
# mas nueva que traen, version|fecha|url del .zip|url del .sig. Sin borradores ni versiones de
# prueba, y las descargas solo de la publicacion que las trae
MAC_RELEASE_PY='
import json, re, sys
repo = sys.argv[1]
try:
    rels = json.load(sys.stdin)
except ValueError:
    sys.exit(1)
if not isinstance(rels, list):
    sys.exit(1)
best = None
for r in rels:
    if not isinstance(r, dict) or not isinstance(r.get("assets"), list) or r.get("draft") or r.get("prerelease"):
        continue
    tag, when = r.get("tag_name") or "", r.get("published_at") or ""
    if not re.fullmatch(r"v[0-9]{1,4}(\.[0-9]{1,4}){1,3}", tag) \
            or not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", when):
        continue
    base = "https://github.com/%s/releases/download/%s/" % (repo, tag)
    urls = {a.get("name"): a.get("browser_download_url") for a in r["assets"] if isinstance(a, dict)}
    for name in urls:
        # (nexum-mac desde la 1.57.11; lvm-instalador-mac, el nombre de antes: con los dos en la misma
        # publicacion, el nuevo)
        m = re.fullmatch(r"(nexum|lvm-instalador)-mac-([0-9]{1,4}(\.[0-9]{1,4}){1,3})\.zip", name or "")
        if not m or urls.get(name) != base + name or urls.get(name + ".sig") != base + name + ".sig":
            continue
        v = (tuple(int(x) for x in m.group(2).split(".")), m.group(1) == "nexum")
        if best is None or v > best[0]:
            best = (v, m.group(2), when, base + name, base + name + ".sig")
if not best:
    sys.exit(1)
print("%s|%s|%s|%s" % best[1:])
'

# ¿Es la version <a> mas nueva que <b>? (numeros separados por puntos)
function mac_version_gt() {
    [[ "$1" =~ ^[0-9]+(\.[0-9]+)*$ ]] && [[ "$2" =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 1
    python3 -I -c 'import sys; a, b = (tuple(int(x) for x in v.split(".")) for v in sys.argv[1:3]); sys.exit(0 if a > b else 1)' "$1" "$2"
}

# Comprueba una firma OpenPGP suelta (.sig, binaria) de la clave de las actualizaciones (EdDSA con
# Ed25519, v4), solo con Python del sistema: sin gpgv de Homebrew, que es de tu usuario y podria dar
# por buena cualquier cosa que despues instalaria root. La huella de la clave tiene que ser la
# esperada y la firma, de esa clave principal. Uso: <fichero> <firma> <clave en base64> <huella>.
# Solo es buena si escribe FIRMA-BUENA (no basta con que termine bien)
UPDATE_VERIFY_PY='
import base64, hashlib, sys, time
path, sig_path, key_b64, want = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4].upper()
def no(why):
    sys.stderr.write("Firma: %s\n" % why)
    sys.exit(1)
def packets(data):
    i, out = 0, []
    while i < len(data):
        b = data[i]
        if not b & 0x80:
            no("paquete OpenPGP no valido")
        if b & 0x40:
            tag, o = b & 0x3F, data[i + 1]
            if o < 192:
                n, h = o, 2
            elif o < 224:
                n, h = ((o - 192) << 8) + data[i + 2] + 192, 3
            elif o == 255:
                n, h = int.from_bytes(data[i + 2:i + 6], "big"), 6
            else:
                no("longitud parcial no admitida")
        else:
            tag, lt = (b >> 2) & 0x0F, b & 3
            if lt == 3:
                no("longitud indeterminada no admitida")
            size = (1, 2, 4)[lt]
            n, h = int.from_bytes(data[i + 1:i + 1 + size], "big"), 1 + size
        body = data[i + h:i + h + n]
        if len(body) != n:
            no("paquete cortado")
        out.append((tag, body, data[i:i + h + n]))
        i += h + n
    return out
def mpi(b, i):
    bits = int.from_bytes(b[i:i + 2], "big")
    n = (bits + 7) // 8
    return b[i + 2:i + 2 + n], i + 2 + n
# Ed25519 (RFC 8032), solo para comprobar
P = 2 ** 255 - 19
Q = 2 ** 252 + 27742317777372353535851937790883648493
D = -121665 * pow(121666, P - 2, P) % P
SQRT_M1 = pow(2, (P - 1) // 4, P)
def recover_x(y, sign):
    xx = (y * y - 1) * pow(D * y * y + 1, P - 2, P) % P
    x = pow(xx, (P + 3) // 8, P)
    if (x * x - xx) % P:
        x = x * SQRT_M1 % P
    if (x * x - xx) % P:
        return None
    if x == 0 and sign:
        return None
    if x & 1 != sign:
        x = P - x
    return x
def add(a, b):
    x1, y1, z1, t1 = a
    x2, y2, z2, t2 = b
    A = (y1 - x1) * (y2 - x2) % P
    B = (y1 + x1) * (y2 + x2) % P
    C = 2 * t1 * t2 * D % P
    E = 2 * z1 * z2 % P
    e, f, g, h = B - A, E - C, E + C, B + A
    return (e * f % P, g * h % P, f * g % P, e * h % P)
def mul(s, a):
    r = (0, 1, 1, 0)
    while s:
        if s & 1:
            r = add(r, a)
        a = add(a, a)
        s >>= 1
    return r
def encode(a):
    zi = pow(a[2], P - 2, P)
    x, y = a[0] * zi % P, a[1] * zi % P
    return (y | ((x & 1) << 255)).to_bytes(32, "little")
def decode(s):
    if len(s) != 32:
        return None
    y = int.from_bytes(s, "little")
    sign, y = y >> 255, y & ((1 << 255) - 1)
    if y >= P:
        return None
    x = recover_x(y, sign)
    return None if x is None else (x, y, 1, x * y % P)
BY = 4 * pow(5, P - 2, P) % P
BASE = (recover_x(BY, 0), BY, 1, recover_x(BY, 0) * BY % P)
def ed25519_ok(pub, msg, sig):
    a, r = decode(pub), decode(sig[:32])
    s = int.from_bytes(sig[32:], "little")
    if a is None or r is None or s >= Q:
        return False
    h = int.from_bytes(hashlib.sha512(sig[:32] + pub + msg).digest(), "little") % Q
    return encode(mul(s, BASE)) == encode(add(r, mul(h, a)))
# La clave: la principal (EdDSA con Ed25519) y su huella v4, que tiene que ser la esperada
try:
    key = base64.b64decode("".join(key_b64.split()), validate=True)
except ValueError:
    no("clave no valida")
kp = [p for p in packets(key) if p[0] == 6]
if not kp:
    no("no hay clave")
kb = kp[0][1]
fpr = hashlib.sha1(b"\x99" + len(kb).to_bytes(2, "big") + kb).hexdigest().upper()
OID = bytes.fromhex("2B06010401DA470F01")
if fpr != want or kb[0] != 4 or kb[5] != 22 or kb[6] != len(OID) or kb[7:7 + len(OID)] != OID:
    no("la clave no es la esperada")
q, _ = mpi(kb, 7 + len(OID))
if len(q) != 33 or q[0] != 0x40:
    no("clave Ed25519 no valida")
pub = q[1:]
# La firma: una sola, v4, de un fichero (tipo 0), EdDSA y SHA-2, de esa clave
with open(sig_path, "rb") as f:
    raw = f.read(65536)
sp = packets(raw)
if len(sp) != 1 or sp[0][0] != 2:
    no("no es una firma suelta")
sb = sp[0][1]
if len(sb) < 10 or sb[0] != 4 or sb[1] != 0 or sb[2] != 22 or sb[3] not in (8, 9, 10):
    no("tipo de firma no admitido")
HASH = {8: hashlib.sha256, 9: hashlib.sha384, 10: hashlib.sha512}[sb[3]]
hl = int.from_bytes(sb[4:6], "big")
hashed = sb[6:6 + hl]
ul = int.from_bytes(sb[6 + hl:8 + hl], "big")
unhashed = sb[8 + hl:8 + hl + ul]
rest = sb[8 + hl + ul:]
def subpackets(b, hashed_area):
    i, out = 0, []
    while i < len(b):
        o = b[i]
        if o < 192:
            n, h = o, 1
        elif o < 255:
            n, h = ((o - 192) << 8) + b[i + 1] + 192, 2
        else:
            n, h = int.from_bytes(b[i + 1:i + 5], "big"), 5
        if n < 1 or i + h + n > len(b):
            no("subpaquete no valido")
        t, v = b[i + h] & 0x7F, b[i + h + 1:i + h + n]
        # Uno critico que no se conoce: no se puede dar por buena (como gpgv)
        if hashed_area and b[i + h] & 0x80 and t not in (2, 16, 33, 27, 3):
            no("subpaquete critico desconocido (%d)" % t)
        out.append((t, v))
        i += h + n
    return out
subs = subpackets(hashed, True) + subpackets(unhashed, False)
issuers = [v[1:].hex().upper() for t, v in subs if t == 33 and len(v) == 21 and v[0] == 4]
ids = [v.hex().upper() for t, v in subs if t == 16 and len(v) == 8]
if not (fpr in issuers or (not issuers and fpr[-16:] in ids)):
    no("la firma no es de esa clave")
# (si caduca, que no haya caducado)
made = [int.from_bytes(v, "big") for t, v in subpackets(hashed, True) if t == 2 and len(v) == 4]
life = [int.from_bytes(v, "big") for t, v in subpackets(hashed, True) if t == 3 and len(v) == 4]
if life and life[0] and (not made or time.time() > made[0] + life[0]):
    no("la firma ha caducado")
h = HASH()
with open(path, "rb") as f:
    for chunk in iter(lambda: f.read(1 << 20), b""):
        h.update(chunk)
h.update(sb[:6 + hl])
h.update(b"\x04\xff" + (6 + hl).to_bytes(4, "big"))
digest = h.digest()
if len(rest) < 2 or rest[:2] != digest[:2]:
    no("el fichero no es el firmado")
r, i = mpi(rest, 2)
s, i = mpi(rest, i)
if len(r) > 32 or len(s) > 32 or i != len(rest):
    no("firma EdDSA no valida")
if not ed25519_ok(pub, digest, r.rjust(32, b"\0") + s.rjust(32, b"\0")):
    no("la firma no es buena")
print("FIRMA-BUENA")
'

# ¿Esta <fichero> firmado con la clave de las actualizaciones? (la firma, en <fichero>.sig)
function update_signed() {
    [ -f "$1" ] && [ -f "$1.sig" ] && [ ! -L "$1.sig" ] && [ -n "$UPDATE_VERIFY_PY" ] || return 1
    [ "$(/usr/bin/python3 -I -c "$UPDATE_VERIFY_PY" "$1" "$1.sig" "$UPDATE_KEY_B64" "$UPDATE_KEY_FPR" 2> /dev/null)" == FIRMA-BUENA ]
}

# Si en GitHub hay una version de Mac mas nueva que esta, descarga su .zip y su firma a UPDATES_DIR
# (solo tuya; el .zip con la fecha de la publicacion) y la ofrece (U|) si la firma es buena. Si no se
# puede, lo dice (I|...). Devuelve 1 si no hay nada que ofrecer de GitHub
function github_update() {
    local json code rel v when zip_url sig_url f
    local get=(curl -q --proto =https --proto-redir =https -fsSL --max-time 60)

    # (sin -f: un 404 es que el repositorio aun no tiene publicaciones, no un fallo de la conexion)
    json=$(curl -q --proto =https --proto-redir =https -sSL --max-time 30 --max-filesize 4194304 \
        -H "Accept: application/vnd.github+json" -w '\n%{http_code}' \
        "https://api.github.com/repos/$UPDATE_REPO/releases?per_page=30" 2> /dev/null)
    code=${json##*$'\n'} json=${json%$'\n'*}
    case "$code" in
        200) ;;
        404) echo "I|Todavía no hay ninguna versión publicada en GitHub"; return 1 ;;
        *) echo "I|No se ha podido consultar GitHub (¿sin conexión?): solo se ha buscado en Descargas"; return 1 ;;
    esac
    rel=$(python3 -I -c "$MAC_RELEASE_PY" "$UPDATE_REPO" <<< "$json") \
        || { echo "I|En GitHub todavía no hay ninguna versión para Mac con su firma"; return 1; }
    IFS='|' read -r v when zip_url sig_url <<< "$rel"
    mac_version_gt "$v" "$APP_VERSION" || return 1

    [ -L "$UPDATES_DIR" ] && { echo "I|$UPDATES_DIR es un enlace: no se descarga nada ahí"; return 1; }
    mkdir -p -m 700 "$UPDATES_DIR" && chmod 700 "$UPDATES_DIR" || return 1
    # (con el nombre que trae la publicacion: nexum-mac-<v>.zip, o lvm-instalador-mac-<v>.zip si es de antes)
    f=$UPDATES_DIR/${zip_url##*/}
    [[ "$f" == */nexum-mac-$v.zip || "$f" == */lvm-instalador-mac-$v.zip ]] || return 1
    # Ya descargada y bien firmada: no se vuelve a bajar
    if ! { [ -f "$f" ] && [ ! -L "$f" ] && update_signed "$f"; }; then
        rm -f -- "$UPDATES_DIR"/nexum-mac-* "$UPDATES_DIR"/lvm-instalador-mac-*
        if ! "${get[@]}" --max-filesize 52428800 -o "$f.part" "$zip_url" 2> /dev/null \
                || ! "${get[@]}" --max-filesize 65536 -o "$f.sig" "$sig_url" 2> /dev/null; then
            rm -f -- "$f.part" "$f.sig"
            echo "I|No se ha podido descargar la $v de GitHub"
            return 1
        fi
        mv -f -- "$f.part" "$f"
        touch -d "$when" "$f" 2> /dev/null
        if ! update_signed "$f"; then
            rm -f -- "$f" "$f.sig"
            echo "I|La $v de GitHub no está firmada por quien hace el programa: no se ofrece"
            return 1
        fi
    fi
    echo "U|$v|$(date -r "$(stat -f %m "$f")" '+%d/%m/%Y %H:%M')|$(shasum -a 256 "$f" | cut -d' ' -f1)|$f"
}

function gui_package() {
    github_update && return 0
    local f v best="" best_v=$APP_VERSION
    for f in "$HOME"/Downloads/nexum-mac-*.dmg "$HOME"/Downloads/lvm-instalador-mac-*.dmg; do
        [ -f "$f" ] && [ ! -L "$f" ] && [ -O "$f" ] || continue
        v=${f##*/}
        v=${v#nexum-mac-} v=${v#lvm-instalador-mac-}
        v=${v%.dmg}
        mac_version_gt "$v" "$best_v" && best=$f best_v=$v
    done
    [ -n "$best" ] || return 0
    # Se abre una copia en una carpeta privada, con la huella calculada sobre esa copia: si despues
    # cambiaran el de Descargas, no se abriria otro distinto del que se te ha mostrado. Tambien se
    # dice de donde se descargo (lo guarda macOS): un .dmg que deja una web lo delata
    local dir copy from old
    # (las copias de otras veces se borran)
    for old in "${TMPDIR:-/tmp}"/lvm-actualizar.*; do
        [ -d "$old" ] && [ ! -L "$old" ] && [ -O "$old" ] && rm -rf "$old"
    done
    dir=$(mktemp -d "${TMPDIR:-/tmp}/lvm-actualizar.XXXXXX") || return 0
    copy=$dir/$(basename "$best")
    # Con sus atributos: com.apple.quarantine hace que Gatekeeper revise lo que traiga el .dmg
    cp "$best" "$copy" || { rm -rf "$dir"; return 0; }
    from=$(mdls -raw -name kMDItemWhereFroms "$best" 2> /dev/null | tr -d '\n"()' | sed 's/^ *//; s/ *, */ y /g' | tr -c '[:print:]' ' ')
    [ "$from" == "(null)" ] || [ "$from" == "null" ] && from=""
    echo "O|${from:-desconocido (no viene de una descarga del navegador)}"
    echo "N|$best_v|$(date -r "$(stat -f %m "$best")" '+%d/%m/%Y %H:%M')|$(shasum -a 256 "$copy" | cut -d' ' -f1)|$copy"
}

# Saca lvm-instalador.sh de un .zip de actualizacion: uno solo, normal (no un enlace) y de un tamaño
# razonable. Uso: <zip> <destino>
UPDATE_EXTRACT_PY='
import stat, sys, zipfile
src, dst = sys.argv[1:3]
try:
    with zipfile.ZipFile(src) as z:
        infos = [i for i in z.infolist() if i.filename == "lvm-instalador.sh"]
        if len(infos) != 1 or stat.S_ISLNK(infos[0].external_attr >> 16) or infos[0].file_size > 16 * 1024 * 1024:
            sys.exit(1)
        data = z.read(infos[0])
except (OSError, zipfile.BadZipFile, RuntimeError):
    sys.exit(1)
with open(dst, "wb") as f:
    f.write(data)
'

# actualizar-gestor <nexum-mac-X.zip>: instala la version de un .zip firmado (el que ha
# descargado Buscar actualizaciones) en el gestor de root (/Library/Nexum/gestor), al que apuntan los
# comandos y la aplicacion. Root copia el .zip y su firma a una carpeta suya y lo comprueba todo
# alli (la firma, con UPDATE_VERIFY_PY; que solo traiga un lvm-instalador.sh normal; que sea la
# version del nombre del .zip, mas nueva que esta, y que bash la entienda entera): lo que instala es
# justo lo comprobado, aunque un programa tuyo cambiara el .zip de tu carpeta entre medias
function install_update() {
    local zip=$1 v work new_v dest=$TRUSTED_SCRIPT owner=(-o root -g wheel)

    # (nexum-mac-X.Y.Z.zip; lvm-instalador-mac-X.Y.Z.zip, el nombre hasta la 1.57.10, tambien vale)
    v=${zip##*/}
    v=${v#nexum-mac-} v=${v#lvm-instalador-mac-}
    v=${v%.zip}
    if [ ! -f "$zip" ] || [ -L "$zip" ] || [ ! -O "$zip" ] \
            || [[ "$zip" != */nexum-mac-*.zip && "$zip" != */lvm-instalador-mac-*.zip ]] \
            || ! [[ "$v" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
        echo "Uso: nexum actualizar-gestor <ruta de nexum-mac-X.Y.Z.zip>"
        return 1
    fi
    if ! mac_version_gt "$v" "$APP_VERSION"; then
        echo "La $v no es mas nueva que la que tienes ($APP_VERSION): no se instala."
        return 1
    fi
    if ! update_signed "$zip"; then
        echo "$zip no lleva la firma de quien publica el programa: no se instala."
        return 1
    fi
    # (en las pruebas, LVM_PRUEBA: sin sudo y en el sitio de este script)
    if [ -n "$TEST_DIR" ]; then
        dest=$SELF owner=()
    elif [ "$SELF" != "$TRUSTED_SCRIPT" ]; then
        echo "Las actualizaciones las instala el gestor de root ($TRUSTED_SCRIPT): bash $SELF instalar-gestor"
        return 1
    fi
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] root copiaria el .zip a una carpeta suya, volveria a comprobar la firma y $dest pasaria a ser la $v"
        return 0
    fi
    if [ -n "$TEST_DIR" ]; then
        work=$(mktemp -d "${TMPDIR:-/tmp}/lvm-actualizar.XXXXXX") || return 1
    else
        work=$($SUDO mktemp -d /private/tmp/lvm-actualizar.XXXXXX) && $SUDO chmod 755 "$work" || return 1
    fi
    task_plan "Actualizando Nexum Dev Stack a la $v" "Copiar el paquete" "Comprobar su firma" "Instalar la versión"
    task_step
    if ! { $SUDO install -m 644 "$zip" "$work/nuevo.zip" && $SUDO install -m 644 "$zip.sig" "$work/nuevo.zip.sig"; }; then
        $SUDO rm -rf "$work"
        echo "No se ha podido copiar $zip"
        return 1
    fi
    task_step
    if [ "$($SUDO /usr/bin/python3 -I -c "$UPDATE_VERIFY_PY" "$work/nuevo.zip" "$work/nuevo.zip.sig" "$UPDATE_KEY_B64" "$UPDATE_KEY_FPR")" != FIRMA-BUENA ]; then
        $SUDO rm -rf "$work"
        echo "$zip no lleva la firma de quien publica el programa: no se instala."
        return 1
    fi
    if ! { $SUDO /usr/bin/python3 -I -c "$UPDATE_EXTRACT_PY" "$work/nuevo.zip" "$work/lvm-instalador.sh" \
            && $SUDO chmod 644 "$work/lvm-instalador.sh"; }; then
        $SUDO rm -rf "$work"
        echo "$zip no trae un lvm-instalador.sh valido: no se instala."
        return 1
    fi
    # (la copia es de root: se puede mirar sin sudo, no cambiar)
    new_v=$(grep -m1 '^APP_VERSION=' "$work/lvm-instalador.sh" | cut -d'"' -f2)
    if [ "$new_v" != "$v" ] || ! "$BASH" -n "$work/lvm-instalador.sh" 2> /dev/null; then
        $SUDO rm -rf "$work"
        echo "El lvm-instalador.sh de $zip no es la $v o esta dañado: no se instala."
        return 1
    fi
    task_step
    echo "Instalando la $v en $dest..."
    # Al lado del instalado y despues con mv: si algo falla, el de antes sigue entero
    if ! { $SUDO install "${owner[@]}" -m 755 "$work/lvm-instalador.sh" "$dest.nuevo" && $SUDO mv -f "$dest.nuevo" "$dest"; }; then
        $SUDO rm -f "$dest.nuevo"
        $SUDO rm -rf "$work"
        echo "No se ha podido escribir $dest"
        return 1
    fi
    $SUDO rm -rf "$work"
    echo "Instalada la $v. La ventana se vuelve a abrir con ella."
}

# Para la pestaña Servicios: S|servicio|en marcha (1/0)|puertos|abierto a la red (1/0)|arranca con
# la version (1/0)|usuario (FTP), de la version montada
function gui_services() {
    local dir ports p name running port open auto user
    dir=$(active_dir)
    [ -n "$dir" ] || return 0
    ports=$(exposed_ports)
    for name in apache mariadb ftp; do
        running=0
        service_running "$name" && running=1
        case $name in
            apache) port="$PORT_HTTP, $PORT_HTTPS" ;;
            mariadb) port=$PORT_MYSQL ;;
            ftp) port=$PORT_FTP ;;
        esac
        open=0
        if [ $running -eq 1 ]; then
            for p in ${port//,/}; do grep -qx "$p" <<< "$ports" && open=1; done
        fi
        auto=1 user=""
        if [ $name == ftp ]; then
            [ -f "$dir/xamppfiles/etc/lvm-startftp" ] || auto=0
            # Las versiones anteriores a la 1.16.0, sin asegurar, arrancan el FTP siempre
            [ -f "$dir/$SECURE_MARK" ] || auto=1
            user=$(awk '/<Limit LOGIN>/ { f = 1 } f && $1 == "AllowUser" { print $2; exit }' "$dir/xamppfiles/etc/proftpd.conf" 2> /dev/null)
        fi
        echo "S|$name|$running|$port|$open|$auto|$user"
    done
}

# Lo que falta en la carga de un proyecto: si es PrestaShop, su dominio con vhost, certificado y
# falseado en /etc/hosts; si no, ningun dominio falseado. Recarga Apache si ha cambiado algo.
function load_project_domain() {
    local folder=$1 domain=""
    PS_RELOAD=0
    # Tienda recien clonada: parameters.php con la base cargada y, la primera vez, cache vacia
    if is_prestashop "$folder"; then
        PS_NEW_PARAMS=0
        ps_parameters "$folder" "$2" || return 1
        # Codigo de produccion volcado encima: la configuracion vuelve a la base de la carpeta
        ps_set_db "$folder" "${2:-$(saved_project_db "$folder")}" || return 1
        ps_first_load "$folder"
    fi
    # WordPress con el codigo de produccion pegado encima: wp-config.php con la base de la carpeta
    if ! is_prestashop "$folder" && is_wordpress "$folder"; then
        wp_config "$folder" "$2" || return 1
    fi
    if [ -n "$(ps_config "$folder")" ]; then
        domain=$(ps_domain "$folder")
        if [ -z "$domain" ]; then
            echo "Aviso: $folder es una tienda PrestaShop, pero no se ha podido saber su dominio: su"
            echo "base no se puede leer (¿MariaDB parado o root con contraseña?) y ningun vhost apunta"
            echo "a la carpeta. Crea su vhost (Editar vhosts) y vuelve a cargar el proyecto."
        elif ! vhost_points_to "$domain" "$folder" && grep -qxF -- "$folder" "$REPO_PROJECTS_FILE" 2> /dev/null; then
            # Montada con Montar nuevo proyecto: la base (su volcado) y el nombre de la carpeta (el del
            # repositorio) los elige quien publica el repositorio, asi que el parecido no basta
            echo "La tienda usa el dominio $domain (de su base). No se falsea solo, porque la base y el"
            echo "nombre de la carpeta vienen con el repositorio: si es el suyo, crealo en Dominios y"
            echo "hosts (Nuevo proyecto con dominio falseado, con la carpeta $folder y ese dominio)."
            domain=""
        elif ! vhost_points_to "$domain" "$folder" && ! domain_fits_folder "$domain" "$folder"; then
            # El dominio viene de la base (shop_url): un volcado manipulado podria llevar uno real
            # (de un banco, de github...) para que este Mac lo mande aqui. Sin vhost suyo, solo se
            # falsea si se parece al nombre de la carpeta
            echo "Aviso: el dominio de la base ($domain) no se parece al nombre de la carpeta $folder:"
            echo "no se le crea vhost ni se falsea. Si es el correcto, crealo en Dominios y hosts"
            echo "(Nuevo proyecto con dominio falseado) o en los vhosts."
            domain=""
        else
            echo "Tienda PrestaShop: dominio $domain"
            ps_vhost "$folder" "$domain" || return 1
        fi
    elif domain=$(custom_domain "$folder") && [ -n "$domain" ]; then
        # Proyecto nuevo creado con su dominio desde la pestaña Hosts (al crearlo ya se le hace su
        # vhost). El fichero de dominios es tuyo y otro programa podria añadir uno real (github.com):
        # sin vhost suyo, solo si se parece al nombre de la carpeta, como con PrestaShop
        if ! vhost_points_to "$domain" "$folder" && ! domain_fits_folder "$domain" "$folder"; then
            echo "Aviso: el dominio guardado para $folder ($domain) no tiene vhost ni se parece al nombre"
            echo "de la carpeta: no se crea ni se falsea. Si es el correcto, crealo en Dominios y hosts."
            domain=""
        else
            echo "Proyecto con dominio propio: $domain"
            ps_vhost "$folder" "$domain" || return 1
        fi
    fi
    hosts_fake cargar $domain || return 1
    if [ "$PS_RELOAD" -eq 1 ] && [ -f "$LINK/xamppfiles/logs/httpd.pid" ]; then
        echo "Recargando Apache para aplicar el vhost y el certificado..."
        run xampp_ctl reloadapache > /dev/null || { echo "No se ha podido recargar Apache. Reinicia la version activa."; return 1; }
    fi
    return 0
}

