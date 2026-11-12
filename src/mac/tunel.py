import hashlib, hmac, html, http.client, http.server, json, os, re, secrets, signal, socket
import socketserver, ssl, subprocess, sys, threading, time, urllib.parse

params_path = sys.argv[2]
# (en su propia sesion: cerrar la tarea o la ventana no lo cierra)
try:
    os.setsid()
except OSError:
    pass
P = json.load(open(params_path))
os.remove(params_path)
STATE, DIR = P["state"], P["dir"]
# (los minutos que se han elegido; los de antes de la 1.57.14 venian en horas)
MINUTES = int(P["minutes"]) if "minutes" in P else int(P["hours"]) * 60
EXPIRES = int(time.time() + MINUTES * 60)
PASSWORD = P["password"].encode()
KEY = secrets.token_bytes(32)
COOKIE = "nexum_tunel"
TOKEN = hmac.new(KEY, b"dentro", hashlib.sha256).hexdigest()
DOMAINS = [d.lower() for d in P["domains"]]
TEXT = re.compile(r"^(text/|application/(javascript|x-javascript|json|ld\+json|xml|rss\+xml|atom\+xml|"
                  r"manifest\+json)|image/svg\+xml)", re.I)
HOP = {"connection", "keep-alive", "proxy-connection", "transfer-encoding", "te", "trailer", "upgrade",
       "proxy-authorization", "proxy-authenticate"}
tunnel_host = None


def log(text):
    print(time.strftime("%H:%M:%S"), text, flush=True)


def loopback(host):
    try:
        return all(a[4][0].startswith("127.") for a in socket.getaddrinfo(host, None, socket.AF_INET))
    except OSError:
        return False


# A donde van las peticiones: el destino y, si la web redirige a otro de sus dominios de este equipo
# (web.local a https://tienda.es, http a https), ese desde entonces
origin = {"scheme": P["scheme"], "host": P["host"], "port": int(P["port"])}
origin_lock = threading.Lock()


def host_header(o):
    default = 443 if o["scheme"] == "https" else 80
    return o["host"] if o["port"] == default else "%s:%d" % (o["host"], o["port"])


# Lo que nunca va por el tunel: lo de LAMPP para este equipo (Apache ve el proxy como 127.0.0.1) y los
# ficheros ocultos. Y el admin, salvo que se permita
BLOCKED = ["/phpmyadmin", "/cgi-bin", "/server-status", "/server-info", "/dashboard", "/xampp", "/webalizer",
           "/licenses", "/__nexum"]
ADMIN = []
if P["admin"] != "permitir":
    ADMIN = ["/wp-login.php", "/wp-admin", "/xmlrpc.php"]
    folder = P["folder"]
    if folder:
        try:
            for n in os.listdir(folder):
                d = os.path.join(folder, n)
                if re.fullmatch(r"[A-Za-z0-9_-]+", n) and os.path.isdir(d) and os.path.isfile(os.path.join(d, "index.php")) \
                        and any(os.path.isfile(os.path.join(d, f)) for f in ("ajax-tab.php", "get-file-admin.php")):
                    ADMIN.append("/" + n.lower())
        except OSError:
            pass
# (wp-admin/admin-ajax.php lo usan las webs de cara al publico)
ALLOWED = ["/wp-admin/admin-ajax.php"]


def blocked(path):
    p = urllib.parse.unquote(path.split("?", 1)[0]).lower()
    p = re.sub(r"/+", "/", p)
    # (cualquier /../ o /./ se rechaza entero: Apache los normaliza y saltaria la lista)
    if re.search(r"(^|/)\.\.?(/|$)", p) or "\\" in p or "\x00" in p:
        return "ruta"
    if re.search(r"/\.(?!well-known/)", p):
        return "oculto"
    if any(p == a for a in ALLOWED):
        return None
    for b in BLOCKED:
        if p == b or p.startswith(b + "/"):
            return "local"
    for b in ADMIN:
        if p == b or p.startswith(b + "/") or p.startswith(b + "?"):
            return "admin"
    return None


def pattern():
    names = b"|".join(re.escape(d.encode()) for d in DOMAINS)
    return (re.compile(rb"(?:https?:)?(\\?/\\?/)(?:www\.)?(?:" + names + rb")(?::\d+)?(?![A-Za-z0-9.-])", re.I),
            re.compile(rb"https?%3A%2F%2F(?:www\.)?(?:" + names + rb")(?:%3A\d+)?(?![A-Za-z0-9.-])", re.I))


URL_RE, ENC_RE = pattern()


def to_tunnel(data):
    t = tunnel_host.encode()
    data = URL_RE.sub(lambda m: (b"https:\\/\\/" if b"\\" in m.group(1) else b"https://") + t, data)
    return ENC_RE.sub(b"https%3A%2F%2F" + t, data)


def to_local(text):
    """Al reves, en lo que manda el visitante (Origin, Referer, la consulta y los formularios)."""
    if not tunnel_host:
        return text
    o = origin
    local = "%s://%s" % (o["scheme"], host_header(o))
    text = re.sub(r"https?://" + re.escape(tunnel_host), local, text, flags=re.I)
    return re.sub(r"https?%3A%2F%2F" + re.escape(tunnel_host), urllib.parse.quote(local, safe=""), text, flags=re.I)


class HTTPS(http.client.HTTPSConnection):
    """A la direccion de este equipo del dominio, con su nombre en el certificado (SNI)."""

    def __init__(self, ip, host, port, timeout):
        ctx = ssl.create_default_context()
        # (los certificados de este equipo son propios: el que importa es el de Cloudflare)
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        super().__init__(ip, port, timeout=timeout, context=ctx)
        self.sni = host

    def connect(self):
        sock = socket.create_connection((self.host, self.port), self.timeout)
        self.sock = self._context.wrap_socket(sock, server_hostname=self.sni)


def connect(o):
    ip = socket.getaddrinfo(o["host"], None, socket.AF_INET)[0][4][0]
    if not ip.startswith("127."):
        raise OSError("%s ya no es de este equipo" % o["host"])
    if o["scheme"] == "https":
        return HTTPS(ip, o["host"], o["port"], 120)
    return http.client.HTTPConnection(ip, o["port"], timeout=120)


fails, fails_lock = {}, threading.Lock()


def page(title, body, status_note=""):
    return ("""<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex">
<title>%s</title><style>body{font-family:system-ui,sans-serif;background:#1e1e1e;color:#ddd;display:flex;
align-items:center;justify-content:center;min-height:100vh;margin:0;padding:16px;box-sizing:border-box}
main{text-align:center;max-width:26em;width:100%%}img{width:72px;height:72px}h1{font-size:1.3em;font-weight:500}
p{color:#9a9a9a;line-height:1.5}input{width:100%%;box-sizing:border-box;font-size:1.1em;padding:10px 12px;
border-radius:8px;border:1px solid #555;background:#2a2a2a;color:#fff;margin:6px 0 12px}
button{width:100%%;font-size:1.05em;padding:10px;border:0;border-radius:8px;background:#3584e4;color:#fff;
cursor:pointer}.err{color:#f66}small{color:#777}</style></head><body><main>
<img src="data:image/png;base64,%s" alt=""><h1>%s</h1>%s<p><small>Nexum Dev Stack · una web en pruebas</small></p>
</main></body></html>""" % (html.escape(title), P["icon"], html.escape(title), body)).encode()


class Proxy(http.server.BaseHTTPRequestHandler):
    server_version = "Nexum"
    sys_version = ""

    def log_message(self, fmt, *args):
        pass

    def visitor(self):
        return self.headers.get("Cf-Connecting-IP", "")[:64] or self.client_address[0]

    def send_page(self, status, data, extra=()):
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Robots-Tag", "noindex, nofollow")
        for k, v in extra:
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def logged_in(self):
        for part in self.headers.get("Cookie", "").split(";"):
            k, _, v = part.strip().partition("=")
            if k == COOKIE and hmac.compare_digest(v, TOKEN):
                return True
        return False

    def login(self):
        back = self.path if self.path.startswith("/") and not self.path.startswith("//") else "/"
        if self.command == "POST" and self.path.split("?")[0] == "/__nexum-tunel/entrar":
            ip = self.visitor()
            with fails_lock:
                recent = [t for t in fails.get(ip, []) if t > time.time() - 600]
                fails[ip] = recent
            if len(recent) >= 8:
                log("%s: demasiados intentos" % ip)
                return self.send_page(429, page("Demasiados intentos", "<p>Espera unos minutos y vuelve a probar.</p>"))
            n = int(self.headers.get("Content-Length") or 0)
            form = urllib.parse.parse_qs(self.rfile.read(min(n, 4096)).decode("utf-8", "replace"))
            given = (form.get("clave") or [""])[0].strip().encode()
            back = (form.get("volver") or ["/"])[0]
            if not back.startswith("/") or back.startswith("//") or "\\" in back:
                back = "/"
            if hmac.compare_digest(given, PASSWORD):
                log("%s: entra" % ip)
                self.send_response(303)
                self.send_header("Location", back)
                self.send_header("Set-Cookie", "%s=%s; Path=/; Secure; HttpOnly; SameSite=Lax" % (COOKIE, TOKEN))
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            with fails_lock:
                fails.setdefault(ip, []).append(time.time())
            log("%s: contraseña equivocada" % ip)
            err = '<p class="err">Esa no es la contraseña.</p>'
        else:
            err = ""
        body = ('<p>Esta web está en pruebas. Escribe la contraseña que te han dado.</p>%s'
                '<form method="post" action="/__nexum-tunel/entrar"><input type="hidden" name="volver" value="%s">'
                '<input type="password" name="clave" autocomplete="current-password" autofocus placeholder="Contraseña">'
                '<button type="submit">Entrar</button></form>' % (err, html.escape(back, quote=True)))
        self.send_page(401, page("Web en pruebas", body))

    def handle_any(self):
        if not self.logged_in():
            return self.login()
        why = blocked(self.path)
        if why:
            log("%s: %s %s (bloqueado: %s)" % (self.visitor(), self.command, self.path[:200], why))
            text = ("El panel de administración no se puede abrir desde aquí." if why == "admin"
                    else "Esto no se puede abrir desde aquí.")
            return self.send_page(403, page("No disponible", "<p>%s</p>" % text))
        body = self.read_body()
        if body is None:
            return self.send_page(400, page("Petición no válida", ""))
        ctype = self.headers.get("Content-Type", "")
        if body and len(body) < 10_000_000 and ctype.startswith(("application/x-www-form-urlencoded", "text/", "application/json")):
            body = to_local(body.decode("latin-1")).encode("latin-1")
        path = to_local(self.path)
        for _hop in range(4):
            with origin_lock:
                o = dict(origin)
            headers = {}
            for k, v in self.headers.items():
                lk = k.lower()
                if lk in HOP or lk in ("host", "content-length", "accept-encoding") or lk.startswith("cf-") \
                        or lk.startswith("x-forwarded-") or lk == "cdn-loop":
                    continue
                if lk == "cookie":
                    v = "; ".join(c for c in (x.strip() for x in v.split(";")) if c and not c.startswith(COOKIE + "="))
                    if not v:
                        continue
                elif lk in ("origin", "referer"):
                    v = to_local(v)
                headers[k] = v
            headers["Host"] = host_header(o)
            headers["Accept-Encoding"] = "identity"
            if body or self.command in ("POST", "PUT", "PATCH"):
                headers["Content-Length"] = str(len(body))
            try:
                conn = connect(o)
                conn.request(self.command, path, body=body or None, headers=headers)
                res = conn.getresponse()
            except OSError as exc:
                log("Sin respuesta de %s: %s" % (host_header(o), exc))
                return self.send_page(502, page("La web no responde", "<p>La web de este equipo no contesta. "
                                                "Puede que se haya parado: vuelve a probar en un momento.</p>"))
            # Redirige a otro de sus dominios de este equipo: se sigue aqui y desde entonces va ahi
            loc = res.getheader("Location", "")
            if res.status in (301, 302, 307, 308) and self.command in ("GET", "HEAD") and loc:
                u = urllib.parse.urlsplit(loc)
                new = {"scheme": (u.scheme or o["scheme"]).lower(), "host": (u.hostname or "").lower(),
                       "port": u.port or (443 if (u.scheme or o["scheme"]).lower() == "https" else 80)}
                if u.hostname and new != o and re.sub(r"^www\.", "", new["host"]) in [re.sub(r"^www\.", "", d) for d in DOMAINS] \
                        and new["scheme"] in ("http", "https") and new["port"] in (80, 443, int(P["port"])) and loopback(new["host"]):
                    res.read()
                    conn.close()
                    with origin_lock:
                        origin.update(new)
                    log("La web va a %s://%s" % (new["scheme"], host_header(new)))
                    path = urllib.parse.urlunsplit(("", "", u.path or "/", u.query, ""))
                    continue
            return self.relay(res, conn)
        return self.send_page(508, page("Demasiadas redirecciones", ""))

    def read_body(self):
        if "chunked" in self.headers.get("Transfer-Encoding", "").lower():
            out = b""
            while True:
                line = self.rfile.readline(65537)
                try:
                    size = int(line.split(b";")[0].strip(), 16)
                except ValueError:
                    return None
                if size == 0:
                    while self.rfile.readline(65537).strip():
                        pass
                    return out
                out += self.rfile.read(size)
                self.rfile.readline(3)
                if len(out) > 512_000_000:
                    return None
        n = self.headers.get("Content-Length")
        if not n:
            return b""
        if not n.isdigit() or int(n) > 512_000_000:
            return None
        return self.rfile.read(int(n))

    def relay(self, res, conn):
        ctype = res.getheader("Content-Type", "")
        rewrite = bool(TEXT.match(ctype)) and self.command != "HEAD"
        length = res.getheader("Content-Length")
        if rewrite and length and length.isdigit() and int(length) > 30_000_000:
            rewrite = False
        self.send_response(res.status, res.reason)
        for k, v in res.getheaders():
            lk = k.lower()
            if lk in HOP or lk == "content-length" or (rewrite and lk == "content-encoding"):
                continue
            if lk == "set-cookie":
                # (sin Domain: la cookie es del dominio del tunel)
                v = re.sub(r";\s*domain=[^;]*", "", v, flags=re.I)
            elif lk in ("location", "refresh", "link", "content-location", "content-security-policy"):
                v = to_tunnel(v.encode("latin-1")).decode("latin-1")
            self.send_header(k, v)
        self.send_header("X-Robots-Tag", "noindex, nofollow")
        if rewrite:
            data = to_tunnel(res.read())
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            if length and length.isdigit():
                self.send_header("Content-Length", length)
            self.end_headers()
            if self.command != "HEAD" and res.status not in (204, 304):
                while True:
                    chunk = res.read(65536)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
        conn.close()

    do_GET = do_POST = do_HEAD = do_PUT = do_PATCH = do_DELETE = do_OPTIONS = handle_any


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


server = Server(("127.0.0.1", 0), Proxy)
threading.Thread(target=server.serve_forever, daemon=True).start()
port = server.server_address[1]
# (sin la configuracion de ~/.cloudflared, que haria otro tipo de tunel, ni actualizarse solo)
proc = subprocess.Popen([P["cloudflared"], "tunnel", "--no-autoupdate", "--config", os.devnull,
                         "--url", "http://127.0.0.1:%d" % port],
                        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
stop = threading.Event()


def finish(*_):
    stop.set()


signal.signal(signal.SIGTERM, finish)
signal.signal(signal.SIGINT, finish)
signal.signal(signal.SIGHUP, finish)


def write_state(url):
    tmp = STATE + ".nuevo"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump({"pid": os.getpid(), "url": url, "target": "%s://%s" % (P["scheme"], host_header(
            {"scheme": P["scheme"], "host": P["host"], "port": int(P["port"])})), "folder": P["folder"],
            "expires": EXPIRES, "started": int(time.time()), "password": P["password"], "minutes": MINUTES, "hours": max(1, MINUTES // 60),
            "admin": P["admin"]}, f)
    os.replace(tmp, STATE)


def read_output():
    global tunnel_host
    for raw in proc.stdout:
        line = raw.decode("utf-8", "replace").rstrip()
        print("cloudflared:", line, flush=True)
        m = re.search(r"https://([a-z0-9-]+\.trycloudflare\.com)", line)
        if m and not tunnel_host:
            tunnel_host = m.group(1)
            write_state("https://" + tunnel_host)
            log("Tunel abierto: https://%s (hasta las %s)" % (tunnel_host, time.strftime("%H:%M", time.localtime(EXPIRES))))
    stop.set()


threading.Thread(target=read_output, daemon=True).start()
while not stop.wait(5):
    if time.time() >= EXPIRES:
        log("Se ha cumplido su hora: se cierra")
        break
proc.terminate()
try:
    proc.wait(10)
except subprocess.TimeoutExpired:
    proc.kill()
try:
    if json.load(open(STATE)).get("pid") == os.getpid():
        os.remove(STATE)
except (OSError, ValueError):
    pass
log("Tunel cerrado")
