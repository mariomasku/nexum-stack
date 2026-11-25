# Intermediario de imagenes (1.57.17): lo que le falte a un proyecto con «Imagenes de produccion»
# (media-proyecto) se trae de su web real en el momento en que la pagina lo pide, y se guarda en su
# carpeta. Vale para las tiendas PrestaShop (img/) y para los WordPress (las imagenes de
# wp-content/uploads/; los videos y los PDF siguen con la redireccion de media-produccion), tambien
# con su dominio real falseado: una redireccion volveria a este equipo. Apache, en los vhosts de la
# carpeta del proyecto (y en web.local, si es el cargado), pasa a MEDIA_LOCAL_PY solo lo que no esta;
# MEDIA_LOCAL_PY pregunta la direccion de la web real al DNS cifrado (nunca al sistema), la pide con
# curl --resolve comprobando su certificado, la sirve y la deja en la carpeta (sin salirse de img o de
# uploads). Corre con tu usuario, solo en 127.0.0.1, mientras la version activa este en marcha y algun
# proyecto tenga sus imagenes de produccion
MEDIA_LOCAL_PORT=${LVM_MEDIA_LOCAL_PORT:-47817}
MEDIA_LOCAL_PID="$LOG_DIR/imagenes-intermediario.pid"
MEDIA_LOCAL_LOG="$LOG_DIR/imagenes-intermediario.log"
MEDIA_IMG_EXT="jpe?g|png|gif|webp|avif|svg|ico|bmp"
MEDIA_LOCAL_PY=$(cat <<'PYEOF'
import http.server, ipaddress, json, os, re, socketserver, subprocess, sys, tempfile, threading, time
import urllib.parse
port, conf, htdocs, doh, agent, pidfile = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6], sys.argv[7]
port = int(port)
agent = "%s (imagenes que faltan en una copia local)" % agent.replace(" ", "-")
EXT = re.compile(r"(?i)\.(jpe?g|png|gif|webp|avif|svg|ico|bmp)$")
TYPES = {"jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "gif": "image/gif", "webp": "image/webp",
         "avif": "image/avif", "svg": "image/svg+xml", "ico": "image/x-icon", "bmp": "image/bmp"}
FOLDER = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$")
DOMAIN = re.compile(r"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$")
lock = threading.Lock()
busy = threading.BoundedSemaphore(8)
ips_cache, missing, fetching = {}, {}, {}

def projects():
    out = {}
    try:
        for line in open(conf, errors="replace"):
            f = line.rstrip("\n").split("|")
            if len(f) == 2 and FOLDER.match(f[0]) and DOMAIN.match(f[1].lower()):
                out[f[0]] = f[1].lower()
    except OSError:
        pass
    return out

def resolve(domain):
    """Las direcciones publicas del dominio (y de www.), del DNS cifrado; 10 minutos en memoria"""
    now = time.time()
    with lock:
        c = ips_cache.get(domain)
        if c and c[0] > now:
            return c[1]
    found = []
    for name in (domain, "www." + domain if not domain.startswith("www.") else domain[4:]):
        ips = []
        for t, want in (("A", 1), ("AAAA", 28)):
            try:
                r = subprocess.run(["curl", "-s", "--proto", "=https", "--max-redirs", "0", "--connect-timeout", "10",
                                    "--max-time", "20", "-H", "accept: application/dns-json",
                                    "%s?name=%s&type=%s" % (doh, name, t)],
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=30)
                data = json.loads(r.stdout.decode(errors="replace") or "{}")
            except (subprocess.SubprocessError, ValueError, OSError):
                continue
            for a in data.get("Answer") or []:
                try:
                    ip = ipaddress.ip_address(str(a.get("data", "")).strip()) if a.get("type") == want else None
                except ValueError:
                    ip = None
                if ip and ip.is_global:
                    ips.append(str(ip) if ip.version == 4 else "[%s]" % ip)
        if ips:
            found.append((name, ",".join(ips[:4])))
    with lock:
        ips_cache[domain] = (now + (600 if found else 60), found)
    return found

def inside(base, path):
    """¿path (que aun puede no existir) queda dentro de base, sin enlaces que lleven fuera?"""
    d = os.path.dirname(path)
    while not os.path.lexists(d):
        d = os.path.dirname(d)
    real = os.path.realpath(d)
    return real == base or real.startswith(base + os.sep)

def save(base, dest, data):
    try:
        if os.path.lexists(dest) or not inside(base, dest):
            return
        os.makedirs(os.path.dirname(dest), mode=0o755, exist_ok=True)
        if not inside(base, dest):
            return
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(dest), prefix=".nexum-")
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.chmod(tmp, 0o644)
        try:
            os.link(tmp, dest)
        except OSError:
            pass
        os.unlink(tmp)
    except OSError as e:
        print("no se ha podido guardar %s: %s" % (dest, e), flush=True)

def fetch(domain, rel):
    """(codigo, datos): 200 con la imagen, 404 si produccion no la tiene, 502 si no se ha podido"""
    names = resolve(domain)
    if not names:
        return 502, b""
    with tempfile.TemporaryDirectory(prefix="nexum-imagen-") as tmp:
        out = os.path.join(tmp, "f")
        cmd = ["curl", "-s", "--proto", "=https", "--proto-redir", "=https", "--fail", "--location", "--max-redirs", "3",
               "--max-filesize", "30000000", "--connect-timeout", "10", "--max-time", "60", "-A", agent,
               "-o", out, "-w", "%{http_code} %{content_type}"]
        for name, ips in names:
            cmd += ["--resolve", "%s:443:%s" % (name, ips)]
        cmd.append("https://%s/%s" % (domain, urllib.parse.quote(rel, safe="/")))
        try:
            r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=90)
        except subprocess.SubprocessError:
            return 502, b""
        code, ctype = (r.stdout.decode(errors="replace").strip().split(" ", 1) + [""])[:2]
        # (solo una imagen: una web que lleva lo que no tiene a su pagina de error, con 200, no deja un HTML
        # con nombre de .jpg)
        if r.returncode == 0 and code == "200" and ctype.lower().startswith("image/") \
                and os.path.isfile(out) and os.path.getsize(out) > 0:
            with open(out, "rb") as f:
                return 200, f.read()
        # (403: lo que da PrestaShop si falta la carpeta de la imagen, por su img/.htaccess)
        if code in ("200", "403", "404", "410"):
            print("no esta en produccion (%s): https://%s/%s" % (code, domain, rel), flush=True)
            return 404, b""
        print("no se ha podido traer (%s): https://%s/%s" % (code or "sin respuesta", domain, rel), flush=True)
        return 502, b""

class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "nexum-imagenes"
    sys_version = ""

    def log_message(self, *args):
        pass

    def answer(self, code, data=b"", ctype="text/plain; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        # Solo lo que manda el Apache de este equipo: con su cabecera (una web no puede ponerla sin
        # permiso) y a esta direccion (otro nombre que lleve a 127.0.0.1 no vale)
        if self.headers.get("X-Nexum-Imagenes") != "1" or self.headers.get("Host") not in (
                "127.0.0.1:%d" % port, "localhost:%d" % port):
            return self.answer(403, b"solo para el Apache de este equipo")
        path = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path, errors="strict")
        parts = path.lstrip("/").split("/", 1)
        if path == "/__nexum/ok":
            return self.answer(200, b"ok")
        if len(parts) != 2 or not FOLDER.match(parts[0]):
            return self.answer(404)
        folder, rel = parts
        segs = rel.split("/")
        if "\x00" in rel or "\\" in rel or any(s in ("", ".", "..") or s.startswith(".") for s in segs) \
                or not EXT.search(rel) or len(rel) > 400:
            return self.answer(404)
        if rel.startswith("img/"):
            base_rel = "img"
        elif rel.startswith("wp-content/uploads/"):
            base_rel = "wp-content/uploads"
        else:
            return self.answer(404)
        domain = projects().get(folder)
        root = os.path.join(htdocs, folder)
        if not domain or not os.path.isdir(root) or os.path.islink(root):
            return self.answer(404)
        if not os.path.isdir(os.path.join(root, base_rel)):
            if base_rel == "img":
                return self.answer(404)
        base = os.path.realpath(os.path.join(root, base_rel)) if os.path.isdir(os.path.join(root, base_rel)) \
            else os.path.join(os.path.realpath(os.path.join(root, "wp-content")), "uploads")
        dest = os.path.join(root, rel)
        ctype = TYPES.get(rel.rsplit(".", 1)[-1].lower(), "application/octet-stream")
        # (ya esta: la sirve, sin salirse de su carpeta)
        if os.path.isfile(dest) and inside(base, dest):
            with open(dest, "rb") as f:
                return self.answer(200, f.read(), ctype)
        key = (folder, rel)
        now = time.time()
        with lock:
            if missing.get(key, 0) > now:
                return self.answer(404)
            ev = fetching.get(key)
            first = ev is None
            if first:
                ev = fetching[key] = threading.Event()
        if not first:
            ev.wait(90)
            if os.path.isfile(dest) and inside(base, dest):
                with open(dest, "rb") as f:
                    return self.answer(200, f.read(), ctype)
            return self.answer(404)
        try:
            with busy:
                code, data = fetch(domain, rel)
            if code == 200:
                save(base, dest, data)
                return self.answer(200, data, ctype)
            if code == 404:
                with lock:
                    missing[key] = now + 300
            return self.answer(code)
        finally:
            with lock:
                fetching.pop(key, None)
            ev.set()

class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

srv = Server(("127.0.0.1", port), Handler)
# (aparte de la terminal o la tarea que lo arranca: sigue aunque se cierren)
try:
    os.setsid()
except OSError:
    pass
fd = os.open(pidfile + ".nuevo", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
os.write(fd, str(os.getpid()).encode())
os.close(fd)
os.replace(pidfile + ".nuevo", pidfile)
print("intermediario de imagenes en 127.0.0.1:%d (%s)" % (port, time.strftime("%d/%m/%Y %H:%M")), flush=True)
srv.serve_forever()
PYEOF
)

# El intermediario en marcha (su PID), si es el de verdad: tuyo y con su marca
function media_local_pid() {
    local p
    p=$(head -c 20 "$MEDIA_LOCAL_PID" 2> /dev/null | tr -d ' \n')
    [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -gt 1 ] || return 0
    [ "$(ps -o user= -p "$p" 2> /dev/null | tr -d ' ')" == "$(id -un)" ] || return 0
    ps -o command= -p "$p" 2> /dev/null | grep -q -- " nexum-imagenes $MEDIA_LOCAL_PORT " && echo "$p"
}

# ¿Algun proyecto con imagenes de produccion?
function media_local_wanted() {
    grep -qE '^[A-Za-z0-9_][A-Za-z0-9_.-]*\|[a-z0-9.-]+$' "$MEDIA_PROJECTS_FILE" 2> /dev/null
}

function media_local_start() {
    local i
    [ -n "$(media_local_pid)" ] && return 0
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] intermediario de imagenes en 127.0.0.1:$MEDIA_LOCAL_PORT"
        return 0
    fi
    [ "$(id -u)" -eq 0 ] && { echo "El intermediario de imagenes no se arranca como root"; return 1; }
    mkdir -p -m 700 "$LOG_DIR" || return 1
    [ -L "$MEDIA_LOCAL_LOG" ] && rm -f "$MEDIA_LOCAL_LOG"
    rm -f "$MEDIA_LOCAL_PID"
    ( cd / && exec env -i HOME="$HOME" USER="$USER" PATH=/usr/bin:/bin python3 -I -c "$MEDIA_LOCAL_PY" \
        nexum-imagenes "$MEDIA_LOCAL_PORT" "$MEDIA_PROJECTS_FILE" "$HTDOCS_DIR" "$PS_IMAGES_DOH" \
        "$APP_NAME/$APP_VERSION" "$MEDIA_LOCAL_PID" ) < /dev/null >> "$MEDIA_LOCAL_LOG" 2>&1 &
    for i in $(seq 30); do
        sleep 0.1
        [ -n "$(media_local_pid)" ] && curl -s --noproxy '*' --max-time 1 -o /dev/null -H "X-Nexum-Imagenes: 1" \
            "http://127.0.0.1:$MEDIA_LOCAL_PORT/__nexum/ok" 2> /dev/null && break
    done
    if [ -z "$(media_local_pid)" ]; then
        echo "El intermediario de imagenes no ha arrancado (¿otro programa en el puerto $MEDIA_LOCAL_PORT?): mira $MEDIA_LOCAL_LOG"
        return 1
    fi
}

function media_local_stop() {
    local p i
    p=$(media_local_pid)
    [ -n "$p" ] || { rm -f "$MEDIA_LOCAL_PID"; return 0; }
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] se para el intermediario de imagenes ($p)"
        return 0
    fi
    kill "$p" 2> /dev/null
    for i in $(seq 30); do
        kill -0 "$p" 2> /dev/null || break
        sleep 0.1
    done
    kill -0 "$p" 2> /dev/null && kill -9 "$p" 2> /dev/null
    rm -f "$MEDIA_LOCAL_PID"
}

# En marcha solo con la version activa en marcha y algun proyecto con imagenes de produccion (va con
# mailpit_sync: al arrancar, parar y reiniciar la version, y desde la ventana cada 20 s)
function media_local_run_sync() {
    if media_local_wanted && lampp_running; then
        media_local_start > /dev/null 2>&1 || true
    else
        media_local_stop > /dev/null 2>&1
    fi
    return 0
}

# Reglas del intermediario en los vhosts (nexum-imagenes): en cada vhost cuya carpeta (la de su
# DocumentRoot o, en web.local, la del proyecto cargado) tiene imagenes de produccion: en una tienda,
# las de /img/ (tambien las de sus direcciones amigables, /12-home_default/x.jpg, que su .htaccess pasa
# a /img/p/1/2/12-home_default.jpg); en un WordPress, las de /wp-content/uploads/. Antes que todo lo
# demas del vhost (la redireccion de media-produccion queda para los videos y los PDF).
# Solo GET y HEAD y lo que no esta en la carpeta. Solo cambia los vhosts si hace falta
function media_local_vhosts() {
    local copy rc vf
    # (en el Mac, realpath_f: su readlink no tiene -f en todas las versiones)
    if declare -F realpath_f > /dev/null; then vf=$(realpath_f "$ACTIVE_VHOSTS"); else vf=$(readlink -f "$ACTIVE_VHOSTS"); fi
    [ -f "$vf" ] || return 0
    mkdir -p -m 700 "$LOG_DIR" || return 1
    copy=$(mktemp "$LOG_DIR/vhosts-imagenes-XXXXXX") || return 1
    python3 -I - "$vf" "$copy" "$HTDOCS_DIR" "$MEDIA_PROJECTS_FILE" "$MEDIA_LOCAL_PORT" "$MEDIA_IMG_EXT" << 'EOF'
import os, re, sys
src, dst, htdocs, conf, port, ext = sys.argv[1:7]
lines = open(src, encoding="utf-8", errors="surrogateescape", newline="").read().split("\n")
want = {}
try:
    for l in open(conf, errors="replace"):
        f = l.rstrip("\n").split("|")
        if len(f) == 2 and re.match(r"^[A-Za-z0-9_][A-Za-z0-9_.-]*$", f[0]) and re.match(r"^[a-z0-9.-]+$", f[1]):
            want[f[0]] = f[1]
except OSError:
    pass
def kind(folder):
    p = os.path.join(htdocs, folder)
    if "prestashop" in folder.lower() or os.path.isdir(os.path.join(p, "src/PrestaShopBundle")) \
            or os.path.isfile(os.path.join(p, "classes/PrestaShopAutoload.php")):
        return "ps"
    if os.path.isfile(os.path.join(p, "wp-config.php")) or os.path.isdir(os.path.join(p, "wp-includes")):
        return "wp"
    return ""
def rule(block):
    root = folder = ""
    for l in block:
        w = l.split("#", 1)[0].strip()
        m = re.match(r'(?i)^DocumentRoot\s+"?([^"]+?)"?\s*$', w)
        if m:
            root = m.group(1).rstrip("/")
    m = re.search(r"/htdocs/([^/]+)$", root)
    if not m:
        return []
    folder = m.group(1)
    link = os.path.join(htdocs, folder)
    if os.path.islink(link):
        folder = os.path.basename(os.readlink(link).rstrip("/"))
    if folder not in want or not os.path.isdir(os.path.join(htdocs, folder)) or os.path.islink(os.path.join(htdocs, folder)):
        return []
    k = kind(folder)
    head = "    # nexum-imagenes %s %s: lo que falte se pide a produccion por el intermediario de Nexum (no se edita a mano: nexum media-proyecto)" % (folder, want[folder])
    proxy = "http://127.0.0.1:%s/%s" % (port, folder)
    # (en el vhost, no en <Directory img>: va antes que los permisos de img/.htaccess, que con una carpeta
    # que aun no existe no dejarian pasar. Tambien con las direcciones amigables de una tienda: su .htaccess
    # las pasa a /img/p/... y Apache vuelve a mirar las reglas del vhost con la ruta nueva)
    base = {"ps": "img", "wp": "wp-content/uploads"}.get(k)
    if not base:
        return []
    return [head,
            "    <IfModule proxy_http_module>",
            "        RewriteEngine On",
            "        RewriteCond %{REQUEST_METHOD} ^(GET|HEAD)$",
            "        RewriteCond %{DOCUMENT_ROOT}%{REQUEST_URI} !-f",
            "        RewriteRule ^/(%s/.+\\.(%s))$ %s/$1 [NC,P,L]" % (base, ext, proxy),
            "        <IfModule headers_module>",
            '            RequestHeader set X-Nexum-Imagenes 1 "expr=%%{REQUEST_URI} =~ m#^/%s/#"' % base,
            "        </IfModule>",
            "    </IfModule>",
            "    # /nexum-imagenes"]
    return []
def fix(block):
    out, skip = [], False
    for l in block:
        s = l.strip()
        if s.startswith("# nexum-imagenes "):
            skip = True
        elif skip and s == "# /nexum-imagenes":
            skip = False
        elif not skip:
            out.append(l)
    # (justo despues de <VirtualHost>: antes que cualquier otra regla del vhost)
    return out[:1] + rule(out) + out[1:]
out, block = [], None
for line in lines:
    if block is None:
        if re.match(r"^\s*<VirtualHost\b", line, re.I):
            block = [line]
        else:
            out.append(line)
        continue
    block.append(line)
    if re.match(r"^\s*</VirtualHost>", line, re.I):
        out += fix(block)
        block = None
if block:
    out += block
if out == lines:
    sys.exit(3)
with open(dst, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
    f.write("\n".join(out))
EOF
    rc=$?
    if [ $rc -eq 3 ]; then
        rm -f "$copy"
        media_local_run_sync
        return 0
    fi
    if [ $rc -ne 0 ]; then
        rm -f "$copy"
        return 1
    fi
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] reglas del intermediario de imagenes en $vf"
        rm -f "$copy"
        return 0
    fi
    edit_vhosts --aplicar "$copy" || { rm -f "$copy"; return 1; }
    rm -f "$copy"
    media_local_run_sync
}
