# ---------------------------------------------------------------- llamadas al script

def script_cmd(*args):
    if DEMO:
        return ["/usr/bin/python3", "-I", "-c", DEMO_PY, DEMO] + list(args)
    return ["/bin/bash", SCRIPT] + (["--simular"] if SIMULATE else []) + list(args)


# Respuesta de un comando en el modo demostración: <comando>_<argumento>.txt o <comando>.txt de la carpeta
# (nada si no está), con @DEMO@ cambiado por la carpeta
DEMO_PY = r"""
import os, re, sys
folder, args = sys.argv[1], sys.argv[2:]
for n in range(len(args), 0, -1):
    name = re.sub(r"[^A-Za-z0-9_.-]", "_", "_".join(args[:n])) + ".txt"
    path = os.path.join(folder, name)
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            sys.stdout.write(f.read().replace("@DEMO@", folder))
        break
"""


# Solo estas variables de la sesion pasan a las tareas: el resto podria cambiar lo que hace bash
# (funciones exportadas BASH_FUNC_*, SHELLOPTS con PS4, BASH_ENV) o lo que toca el gestor con sudo
ENV_KEEP = {"HOME", "USER", "LOGNAME", "LANG", "LANGUAGE", "DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY", "SSH_AUTH_SOCK",
            "DBUS_SESSION_BUS_ADDRESS", "TMPDIR", "PATH", "LVM_PRUEBA", "PHP_TIMEZONE",
            "http_proxy", "https_proxy", "no_proxy", "all_proxy", "HTTP_PROXY", "HTTPS_PROXY",
            "NO_PROXY", "ALL_PROXY"}


def script_env(**extra):
    # (en las pruebas, con LVM_PRUEBA, tambien las LVM_* que cambian las carpetas)
    test = bool(os.environ.get("LVM_PRUEBA"))
    env = {k: v for k, v in os.environ.items()
           if k in ENV_KEEP or k.startswith(("LC_", "XDG_"))
           or (test and k.startswith("LVM_") and k != "LVM_SIMULAR")}
    env.update(LVM_UI="text", SUDO_PROMPT=SUDO_MARK, TERM="dumb")
    env.update(extra)
    return env


def once(callback, *args):
    """Llama a callback(*args) una sola vez en la interfaz. GLib.idle_add repite la llamada mientras
    devuelva algo verdadero: un callback que devolviera sus datos se quedaria dando vueltas a toda
    CPU, tambien despues de cerrar la ventana."""
    GLib.idle_add(lambda: (callback(*args), False)[1])


def close_stale_windows(script):
    """Cierra las ventanas de Nexum de este usuario que van con un código anterior al instalado: las de este
    mismo script (python3 -I - <script>) que arrancaron antes de que se instalara (su ctime). Las de la
    versión instalada no se tocan: si hay una abierta, el sistema le pasa la petición y se trae al frente."""
    if not script or not os.path.isfile(script):
        return
    try:
        installed = os.stat(script).st_ctime
        with open("/proc/stat") as fh:
            boot = int(next(l for l in fh if l.startswith("btime ")).split()[1])
    except (OSError, StopIteration, ValueError):
        return
    tick, me, uid = os.sysconf("SC_CLK_TCK"), os.getpid(), os.getuid()
    want = [b"/usr/bin/python3", b"-I", b"-", os.fsencode(script)]
    stale = []
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == me:
            continue
        pid = int(name)
        try:
            if os.stat("/proc/%d" % pid).st_uid != uid:
                continue
            with open("/proc/%d/cmdline" % pid, "rb") as fh:
                if fh.read().split(b"\0")[:-1] != want:
                    continue
            with open("/proc/%d/stat" % pid) as fh:
                st = fh.read()
            started = boot + int(st[st.rfind(")") + 2:].split()[19]) / tick
        except (OSError, ValueError, IndexError):
            continue
        if started < installed - 1:
            stale.append(pid)
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in stale:
            try:
                os.kill(pid, sig)
            except OSError:
                pass
        if not stale:
            break
        time.sleep(1.5)
        stale = [pid for pid in stale if os.path.exists("/proc/%d" % pid)]


# Buscador de Nuevo proyecto: al abrir el asistente, si hace más de estos segundos que no se pregunta a
# GitHub, se le pregunta por detrás
NP_REPOS_FRESH = 300
# Cuántos resultados enseña debajo
NP_REPOS_HITS = 6


def repo_query(text):
    """Lo que se busca en la lista de repositorios: dueño/repo si es una dirección de GitHub."""
    q = text.strip().lower()
    q = re.sub(r"^(git@github\.com:|ssh://git@github\.com/|https?://github\.com/)", "", q)
    return re.sub(r"(\.git)?/?$", "", q)


def run_quick(args, callback, env=None, timeout=180):
    """Comando sin sudo ni preguntas, en segundo plano. callback(rc, salida) en la interfaz."""
    def work():
        try:
            res = subprocess.run(script_cmd(*args), stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 env=script_env(**(env or {})), timeout=timeout)
            out = res.stdout.decode("utf-8", "replace")
            once(callback, res.returncode, out)
        except Exception as exc:  # noqa: BLE001 - cualquier fallo se muestra como error
            once(callback, 1, "ERROR|%s" % exc)
    threading.Thread(target=work, daemon=True).start()


def run_quick_input(args, text, callback, timeout=60):
    """Como run_quick, con text por la entrada del comando (un token: en la línea de órdenes se vería
    con ps)."""
    def work():
        try:
            res = subprocess.run(script_cmd(*args), input=text.encode(), stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, env=script_env(), timeout=timeout)
            once(callback, res.returncode, res.stdout.decode("utf-8", "replace"))
        except Exception as exc:  # noqa: BLE001 - cualquier fallo se muestra como error
            once(callback, 1, "ERROR|%s" % exc)
    threading.Thread(target=work, daemon=True).start()


# Botones del visor de un proyecto (el cargado y los de Docker) que se pueden ocultar y ordenar:
# clave, nombre e icono. «Desmontar», ⋮ y los propios de Docker (Versiones de PHP, Arrancar o Parar)
# se ven siempre
VISOR_BUTTONS = [("web", "Abrir web", ("logo", "globo")), ("vscode", "VS Code", ("vscode", "text-editor-symbolic")),
                 ("pma", "phpMyAdmin", ("logo", "phpmyadmin")), ("panel", "Panel", ("logo", "wordpress")),
                 ("docker", "Docker", ("logo", "docker")), ("compartir", "Compartir", ("logo", "cloudflare")),
                 ("log", "Log", ("logo", "log")), ("actualizar", "Actualizar", ("logo", "actualizar")),
                 ("imagenes", "Importar", ("logo", "imagenes"))]
# Configuración, Seguridad entre webs: qué es, en cuatro puntos (el mismo texto en el Mac)
CROSS_SITE_HELP = [
    ("dialog-warning-symbolic", "El problema",
     "Mientras trabajas, el navegador tiene abierta tu sesión en tus proyectos (el panel de WordPress, el de "
     "PrestaShop…). Cualquier otra web que abras a la vez podría mandarles a escondidas un formulario o una "
     "petición, y el navegador la enviaría con tu sesión: crear un administrador, cambiar una contraseña, borrar "
     "productos…"),
    ("security-high-symbolic", "Lo que hace la barrera",
     "Apache rechaza lo que llega a tus proyectos desde otra web, salvo abrir una página con un enlace normal. Lo "
     "que hagas dentro del propio proyecto, o escribiendo su dirección, funciona igual."),
    ("dialog-information-symbolic", "Cuándo apagarla",
     "Al probar una pasarela de pago (Redsys, PayPal, Stripe…): al acabar el pago, el banco te devuelve a la "
     "tienda mandando un formulario desde su web, y la barrera lo para (sale «Otra web ha intentado mandar algo a "
     "esta»). Apágala mientras pruebas los pagos y vuelve a encenderla al acabar."),
    ("network-workgroup-symbolic", "Dónde se aplica",
     "En todas tus versiones de PHP: localhost, web.local, los dominios falseados y los vhosts de los proyectos. "
     "Al cambiarla se reinicia Apache."),
]

BUTTON_STYLES = [("nombre", "Con su nombre"), ("icono", "Solo el icono (cuadrado)"),
                 ("grande", "Icono y nombre (cuadrado)")]
# Lado del cuadrado (px) de los estilos icono y grande: el de cada uno si no se ha elegido otro
BUTTON_SIZES = {"icono": 44, "grande": 88}
BUTTON_SIZE_MIN, BUTTON_SIZE_MAX = 32, 128
# (con el nombre debajo hace falta algo más de sitio)
BUTTON_SIZE_NAMED = 72
BUTTONS_FILE = os.path.join(LOG_DIR, "botones-visor")
# Al abrir la ventana se busca una versión nueva el primer arranque de cada día y, después, cada tantos
UPDATE_EVERY = 4
# (en la simulacion no se escribe nada: lo elegido vale mientras la ventana siga abierta)
_buttons_sim = {}


def buttons_conf():
    """order (todas las claves, en su orden), hidden (las que no se ven) y style (BUTTON_STYLES)."""
    keys = [k for k, _n, _i in VISOR_BUTTONS]
    conf = dict(_buttons_sim)
    if not conf:
        try:
            with open(BUTTONS_FILE, encoding="utf-8") as fh:
                conf = json.loads(fh.read(4000))
        except (OSError, ValueError):
            conf = {}
    if not isinstance(conf, dict):
        conf = {}
    order = [k for k in conf.get("order", []) if k in keys] if isinstance(conf.get("order"), list) else []
    order += [k for k in keys if k not in order]
    hidden = {k for k in conf.get("hidden", []) if k in keys} if isinstance(conf.get("hidden"), list) else set()
    style = conf.get("style") if conf.get("style") in [k for k, _t in BUTTON_STYLES] else "nombre"
    size = conf.get("size")
    if not isinstance(size, int) or not BUTTON_SIZE_MIN <= size <= BUTTON_SIZE_MAX:
        size = BUTTON_SIZES.get(style, BUTTON_SIZES["icono"])
    return {"order": order, "hidden": hidden, "style": style, "size": size}


def buttons_save(conf):
    data = {"order": conf["order"], "hidden": sorted(conf["hidden"]), "style": conf["style"], "size": conf["size"]}
    if SIMULATE:
        _buttons_sim.clear()
        _buttons_sim.update(data)
        return
    os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
    with open(BUTTONS_FILE + ".nuevo", "w", encoding="utf-8") as fh:
        json.dump(data, fh)
    os.replace(BUTTONS_FILE + ".nuevo", BUTTONS_FILE)


def button_icon(spec, size):
    if spec[0] == "logo":
        return logo(spec[1], size)
    if spec[0] == "vscode":
        code = vscode_app()
        if code is not None and code.get_icon() is not None:
            img = Gtk.Image.new_from_gicon(code.get_icon(), Gtk.IconSize.BUTTON)
            img.set_pixel_size(size)
            return img
    return icon(spec[1], size)


# Consumo de Nexum y sus servicios (el visor de arriba): los procesos de cada parte, leídos de /proc
USAGE_GROUPS = [("ventana", "Nexum Dev Stack (la ventana y sus tareas)"), ("lampp", "LAMPP (Apache, MariaDB y PHP-FPM)"),
                ("docker", "Docker sin root y sus contenedores"), ("mailpit", "Mailpit (correo de pruebas)"),
                ("tunel", "Túnel de Cloudflare")]


def usage_group(pid, argv, cgroup, own):
    """A qué parte de Nexum es un proceso (None: a ninguna). Sin los hijos: esos van con su padre."""
    first = argv[0] if argv else ""
    if pid == own:
        return "ventana"
    if first.startswith("/opt/lampp") or (first in ("/bin/sh", "sh") and len(argv) > 1 and argv[1].startswith("/opt/lampp")):
        return "lampp"
    if os.path.basename(first) == "mailpit" and "/mailpit/" in first:
        return "mailpit"
    if "nexum-tunel" in argv or first == os.path.join(LOG_DIR, "tunel", "cloudflared"):
        return "tunel"
    # Docker sin root: dockerd y los suyos en su servicio de usuario y cada contenedor en su scope
    if "user@%d.service" % os.getuid() in cgroup and ("/docker.service" in cgroup or "/docker-" in cgroup):
        return "docker"
    return None


class UsageMeter:
    """CPU y memoria de Nexum y sus servicios juntos: la CPU, en % de todo el equipo (todos los núcleos
    son el 100 %), entre una lectura y la anterior; la memoria, la PSS de cada proceso (lo que de verdad
    ocupa, sin contar dos veces lo compartido) o, si no se puede leer (los de root), lo suyo sin lo
    compartido."""

    def __init__(self):
        self.prev, self.when, self.known = {}, None, {}
        self.tick = os.sysconf("SC_CLK_TCK")
        self.page = os.sysconf("SC_PAGE_SIZE")
        self.cpus = os.cpu_count() or 1
        self.total = 0
        try:
            with open("/proc/meminfo") as fh:
                self.total = int(next(l for l in fh if l.startswith("MemTotal:")).split()[1]) * 1024
        except (OSError, StopIteration, ValueError):
            pass

    @staticmethod
    def read(path, mode="r"):
        try:
            with open(path, mode) as fh:
                return fh.read()
        except OSError:
            return None

    def sample(self):
        own = os.getpid()
        procs, known, seen = {}, self.known, {}
        for name in os.listdir("/proc"):
            if not name.isdigit():
                continue
            pid = int(name)
            stat = self.read("/proc/%d/stat" % pid)
            if stat is None:
                continue
            f = stat[stat.rfind(")") + 2:].split()
            # (su orden y su parte no cambian: se leen una vez por proceso, con su hora de inicio)
            key = (pid, f[19])
            if key not in known:
                raw = self.read("/proc/%d/cmdline" % pid, "rb")
                if raw is None:
                    continue
                argv = [a.decode("utf-8", "replace") for a in raw.split(b"\0") if a]
                known[key] = (argv, usage_group(pid, argv, self.read("/proc/%d/cgroup" % pid) or "", own))
            argv, group = known[key]
            seen[key] = known[key]
            procs[pid] = {"ppid": int(f[1]), "cpu": int(f[11]) + int(f[12]), "argv": argv, "group": group}
        self.known = seen
        # Los hijos van con su padre (los PHP-FPM de LAMPP, las tareas de la ventana: solo las suyas)
        for _pid, pr in procs.items():
            q, depth = pr["ppid"], 0
            while pr["group"] is None and q in procs and depth < 6:
                g = procs[q]["group"]
                if g and (g != "ventana" or any("lvm-instalador" in a for a in pr["argv"])):
                    pr["group"] = g
                q, depth = procs[q]["ppid"], depth + 1
        now = time.monotonic()
        out = {k: [0.0, 0] for k, _t in USAGE_GROUPS}
        for pid, pr in procs.items():
            if not pr["group"]:
                continue
            if self.when is not None and pid in self.prev:
                out[pr["group"]][0] += max(0, pr["cpu"] - self.prev[pid])
            mem = None
            roll = self.read("/proc/%d/smaps_rollup" % pid)
            if roll:
                m = re.search(r"^Pss:\s+(\d+) kB", roll, re.M)
                mem = int(m.group(1)) * 1024 if m else None
            if mem is None:
                # (residente sin lo compartido: los hijos de Apache comparten casi todo con su padre)
                statm = self.read("/proc/%d/statm" % pid)
                mem = max(0, int(statm.split()[1]) - int(statm.split()[2])) * self.page if statm else 0
            out[pr["group"]][1] += mem
        span = (now - self.when) if self.when else 0
        self.prev = {pid: pr["cpu"] for pid, pr in procs.items() if pr["group"]}
        self.when = now
        for k in out:
            out[k][0] = 100.0 * out[k][0] / self.tick / span / self.cpus if span > 0 else None
        return out


def docker_own(name):
    """¿Es un contenedor de Nexum (los que acepta docker-contenedor)? Los de los proyectos (de antes y
    del Apache de Docker), las MariaDB comunes, el Apache de Docker y su phpMyAdmin."""
    return bool(re.fullmatch(r"nexum-[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?-((php|db|pma)-\d{1,3}|php\d{2})", name)
                or re.fullmatch(r"nexum-(web|pma|mariadb-\d{1,2}-\d{1,2})", name))


def smooth_scroll(sw, target=0.0, ms=320):
    """Lleva una ventana con desplazamiento a esa altura poco a poco (como al deslizar)."""
    adj = sw.get_vadjustment()
    start, t0 = adj.get_value(), time.monotonic()
    if abs(start - target) < 1:
        return

    def step():
        k = min(1.0, (time.monotonic() - t0) * 1000 / ms)
        adj.set_value(start + (target - start) * (1 - (1 - k) ** 3))
        return k < 1.0
    GLib.timeout_add(15, step)


def tunnel_state():
    """El túnel de Cloudflare abierto (tunel-abrir): url, target (la dirección local), folder y expires.
    None si no hay ninguno o su proceso ya no está."""
    try:
        with open(os.path.join(LOG_DIR, "tunel", "estado"), encoding="utf-8") as fh:
            st = json.load(fh)
        pid = int(st["pid"])
        with open("/proc/%d/cmdline" % pid, "rb") as fh:
            if b"nexum-tunel" not in fh.read():
                return None
        return st if st.get("url") and int(st.get("expires", 0)) > time.time() else None
    except (OSError, ValueError, KeyError, TypeError):
        return None


def project_admin(folder):
    """(tipo, carpeta del panel) de un proyecto: wp-admin en WordPress y, en PrestaShop, su carpeta de
    administración (cada tienda la llama de una forma; se reconoce por lo que tiene)."""
    if os.path.isfile(os.path.join(folder, "wp-config.php")) and os.path.isdir(os.path.join(folder, "wp-admin")):
        return "wp", "wp-admin"
    try:
        names = sorted(os.listdir(folder), key=lambda n: (not n.lower().startswith("admin"), n))
    except OSError:
        return "", ""
    for n in names:
        d = os.path.join(folder, n)
        if re.fullmatch(r"[A-Za-z0-9_-]+", n) and not os.path.islink(d) and os.path.isdir(d) \
                and os.path.isfile(os.path.join(d, "index.php")) \
                and any(os.path.isfile(os.path.join(d, f)) for f in ("ajax-tab.php", "get-file-admin.php")):
            return "ps", n
    return "", ""


def login_page(title, project, action, fields, panel):
    """Página de acceso al panel de un proyecto con el administrador de pruebas ya escrito: un
    formulario que va a la pantalla de acceso del proyecto; solo hay que pulsar Entrar."""
    e = html.escape
    rows, hidden = "", ""
    for name, value, text in fields:
        if text:
            kind = "password" if name in ("pwd", "passwd") else "text"
            rows += ('<label>%s<input type="%s" name="%s" value="%s" autocomplete="off"></label>'
                     % (e(text), kind, e(name), e(value)))
        else:
            hidden += '<input type="hidden" name="%s" value="%s">' % (e(name), e(value))
    return """<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="referrer" content="no-referrer"><title>%(title)s · %(project)s</title>
<style>
:root { color-scheme: light dark; --bg: #f4f4f6; --card: #fff; --line: #d8d8dc; --muted: #6b6b72; --accent: #2a7ae2; }
@media (prefers-color-scheme: dark) { :root { --bg: #1e1e20; --card: #2a2a2d; --line: #444; --muted: #a0a0a6; } }
body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: var(--bg);
       font: 15px/1.45 system-ui, "Ubuntu", sans-serif; }
form { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 28px 32px;
       width: min(380px, calc(100vw - 32px)); box-sizing: border-box; }
h1 { font-size: 19px; margin: 0 0 4px; } p { margin: 0 0 18px; color: var(--muted); font-size: 13px; }
label { display: block; font-size: 13px; color: var(--muted); margin-bottom: 14px; }
input[type=text], input[type=password] { display: block; width: 100%%; box-sizing: border-box; margin-top: 4px;
       padding: 8px 10px; font: inherit; border: 1px solid var(--line); border-radius: 8px; background: transparent; }
button { width: 100%%; margin-top: 6px; padding: 10px; font: inherit; font-weight: 600; color: #fff;
         background: var(--accent); border: 0; border-radius: 8px; cursor: pointer; }
small { display: block; margin-top: 14px; color: var(--muted); font-size: 12px; }
</style></head><body>
<form method="post" action="%(action)s">
<h1>%(title)s</h1><p>%(project)s · administrador de pruebas de este equipo</p>
%(rows)s%(hidden)s<button type="submit" autofocus>Entrar</button>
<small>Si no entra, el panel normal está en <a href="%(panel)s">%(panel)s</a>.</small>
</form></body></html>""" % {"title": e(title), "project": e(project or "proyecto"), "action": e(action),
                            "rows": rows, "hidden": hidden, "panel": e(panel)}


def serve_once(page, seconds=60):
    """Sirve una página en 127.0.0.1 (puerto libre y ruta al azar) durante un minuto y la devuelve.
    Por http y no como fichero: el Firefox de snap no puede abrir ficheros de /tmp ni de las
    carpetas ocultas. None si no se puede."""
    body = page.encode("utf-8")
    path = "/acceso-%s" % os.urandom(8).hex()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != path:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_):
            pass
    try:
        srv = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    except OSError:
        return None
    srv.timeout = 1
    end = time.time() + seconds

    def work():
        while time.time() < end:
            srv.handle_request()
        srv.server_close()
    threading.Thread(target=work, daemon=True).start()
    return "http://127.0.0.1:%d%s" % (srv.server_address[1], path)


def parse_lines(out):
    return [line.split("|") for line in out.splitlines() if "|" in line]


def read_progress(path):
    """Como _read_progress, pero una línea rara (un nombre de fichero con |) no rompe la tarea."""
    try:
        return _read_progress(path)
    except (ValueError, IndexError):
        return None


def _read_progress(path):
    """Interpreta el archivo de progreso del script (mismo calculo que progress_screen).
    Devuelve dict o None si aun no ha empezado."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return None
    starts = [i for i, l in enumerate(lines) if l.startswith("I|")]
    if not starts:
        return None
    _, k, n, name, started = (lines[starts[-1]].split("|") + [""] * 5)[:5]
    section = lines[starts[-1]:]
    parts = [l.split("|", 1)[1] for l in section if l.startswith("C|")]
    parts = parts[-1].split(";") if parts else []
    steps = [l for l in section if l.startswith("S|")]
    pct, cur, what, mode, done, total = 0, 0, "", "", 0, 0
    if steps:
        f = (steps[-1].split("|") + [""] * 9)[:9]
        _, cur, frm, to, what, mode, file, total, t0 = f
        cur, frm, to = int(cur or 0), int(frm or 0), int(to or 0)
        done = 0
        try:
            if mode == "lines":
                with open(file, "rb") as fh:
                    done = sum(1 for _ in fh)
            elif mode == "bytes":
                done = os.path.getsize(file)
            elif mode == "time":
                done = int(time.time()) - int(t0 or 0)
            elif mode == "fdpos":
                with open(file, encoding="ascii", errors="replace") as fh:
                    done = next((int(l.split()[1]) for l in fh if l.startswith("pos:")), 0)
            elif mode == "percent":
                with open(file, "rb") as fh:
                    tail = fh.read()[-8000:].decode("utf-8", "replace").splitlines()[-40:]
                found = [m.group(1) for m in (re.match(r"^\[ *(\d+)%\]", t) for t in tail) if m]
                done = int(found[-1]) if found else 0
        except (OSError, ValueError):
            done = 0
        frac = 0
        if mode and int(total or 0) > 0:
            frac = min(done * 1000 // int(total), 990)
        pct = frm + (to - frm) * frac // 1000
    results = [l.split("|") for l in lines if l.startswith("R|")]
    finished = any(l.startswith("R|") for l in section)
    if finished:
        pct, cur = 100, 999
    return {"k": int(k or 1), "n": int(n or 1), "name": name, "started": int(started or 0),
            "parts": parts, "cur": cur, "what": what, "pct": pct, "mode": mode,
            "done": done, "total": int(total or 0),
            "results": [(r[1], r[2]) for r in results if len(r) > 2]}


def item_folder(item):
    """Carpeta (lampp-<carpeta>) de un elemento del plan, como item_folder del script."""
    kind, _, name = item.partition(":")
    return name.rsplit(".", 1)[0] if kind in ("php", "rehacer") else name


# Caché de descargas de las pilas propias (lvm-instalador descargas)
DL_CACHE_DIR = "/var/cache/nexum-stack"


def downloads_cache_size():
    """Ficheros de la caché de descargas y lo que ocupan (sin sus .sha256)."""
    n = size = 0
    try:
        with os.scandir(DL_CACHE_DIR) as it:
            for e in it:
                if e.is_file(follow_symlinks=False) and not e.name.endswith(".sha256"):
                    n += 1
                    size += e.stat(follow_symlinks=False).st_size
    except OSError:
        pass
    return n, size


def fmt_size(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return ("%d %s" % (n, unit)) if unit == "B" else \
                ("%.1f %s" % (n, unit)).replace(".", ",")
        n /= 1024


MONTHS = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
          "septiembre", "octubre", "noviembre", "diciembre"]


def fmt_month(date):
    """2026-12-31 -> diciembre de 2026"""
    try:
        y, m = date.split("-")[:2]
        return "%s de %s" % (MONTHS[int(m) - 1], y)
    except (ValueError, IndexError):
        return date


def fmt_day(date):
    """2026-10-21 -> 21 de octubre de 2026"""
    try:
        y, m, d = date.split("-")[:3]
        return "%d de %s de %s" % (int(d), MONTHS[int(m) - 1], y)
    except (ValueError, IndexError):
        return date


def release_tag(sec):
    """Etiqueta de un parche de PHP: de seguridad (php.net lo marca así: corrige vulnerabilidades)
    o solo de errores"""
    if sec == "1":
        tag = label("Parche de seguridad", "etiqueta-parche", "seguridad-parche")
        tag.set_tooltip_text("Parche de seguridad")
    else:
        tag = label("Corrección de errores", "etiqueta-parche", "dim-label")
        tag.set_tooltip_text("Corrige errores")
    return tag


def branch_release(f):
    """Fecha y marca de seguridad del último parche de una línea B"""
    fields = (f + [""] * 13)[:13]
    return fields[11], fields[12]


def branch_state(f):
    """Estado en php.net de una linea B: (estado, fin del soporte activo, fin de seguridad)"""
    fields = (f + [""] * 11)[:11]
    state, active_end, security_end = fields[8], fields[9], fields[10]
    if not state:
        state = "stable" if fields[3] == "1" else "eol"
    return state, active_end, security_end


def state_pill(state, active_end, security_end):
    """Estado de una rama en su color (sin fondo): Estable, Solo seguridad o Sin soporte"""
    if state == "stable":
        pill = label("Estable", "estado", "estable")
        pill.set_tooltip_text("Con soporte completo"
                              + (" (hasta %s)" % fmt_month(active_end) if active_end else "")
                              + ". Es la mejor opción para proyectos nuevos.")
    elif state == "security":
        pill = label("Solo seguridad", "estado", "seguridad")
        pill.set_tooltip_text("Solo parches de seguridad"
                              + (" hasta %s" % fmt_month(security_end) if security_end else "")
                              + ". Sirve para proyectos que aún no funcionan con las estables.")
    else:
        pill = label("Sin soporte", "estado", "soporte-no")
        pill.set_tooltip_text("Sin parches"
                              + (" (desde %s)" % fmt_month(security_end) if security_end else "")
                              + ". Solo para proyectos antiguos.")
    return pill


def fmt_minutes(secs):
    return "menos de 1 min" if secs < 60 else "%d min" % ((secs + 30) // 60)


def fmt_clock(secs):
    """Tiempo transcurrido como un reloj: 0:42, 3:05, 1:02:10"""
    secs = int(secs)
    return ("%d:%02d:%02d" % (secs // 3600, secs // 60 % 60, secs % 60)) if secs >= 3600 else \
        "%d:%02d" % (secs // 60, secs % 60)


def time_left(elapsed, done, left):
    """Lo que queda, al ritmo de hasta ahora (done % en elapsed segundos; quedan left %)."""
    if done < 3 or elapsed < 3:
        return "calculando lo que queda…"
    secs = int(elapsed * left / done)
    if secs < 60:
        return "quedan unos %d s" % max(5, (secs + 4) // 5 * 5)
    if secs < 90:
        return "queda 1 min"
    if secs < 3600:
        return "quedan unos %d min" % ((secs + 30) // 60)
    return "quedan unas %d h %02d min" % (secs // 3600, secs // 60 % 60)


class Console:
    """El registro de una tarea como lo pinta una terminal: \r vuelve al principio de la línea (las
    barras de las descargas se quedan en una línea que avanza), ESC[nA sube n líneas y ESC[K / ESC[2K
    las borran (docker pull), y las líneas seguidas que solo cambian en sus números y llevan un % se
    quedan en una sola, que va subiendo. Solo las últimas líneas se pueden reescribir: las de antes
    pasan al texto fijo."""
    LIVE = 80
    TOKEN = re.compile(r"\x1b\[([0-9;?]*)([A-Za-z])|\x1b[78()][0-9A-Za-z]?|\r\n|\r|\n|\x08")

    def __init__(self, buf):
        self.buf = buf
        self.fixed = 0            # caracteres del texto fijo (al principio del buffer)
        self.lines, self.row, self.col = [""], 0, 0

    def put(self, s):
        line = self.lines[self.row]
        if len(line) < self.col:
            line += " " * (self.col - len(line))
        self.lines[self.row] = line[:self.col] + s + line[self.col + len(s):]
        self.col += len(s)

    def newline(self):
        # Un contador (12 %, 13 %, …) en líneas seguidas: se queda la última
        if self.row > 0 and "%" in self.lines[self.row]:
            shape = re.sub(r"\d+(?:[.,]\d+)?", "#", self.lines[self.row].strip())
            if shape == re.sub(r"\d+(?:[.,]\d+)?", "#", self.lines[self.row - 1].strip()):
                del self.lines[self.row - 1]
                self.row -= 1
        self.row += 1
        self.col = 0
        if self.row == len(self.lines):
            self.lines.append("")

    def write(self, text):
        pos = 0
        for m in self.TOKEN.finditer(text):
            if m.start() > pos:
                self.put(text[pos:m.start()])
            pos = m.end()
            tok = m.group(0)
            if tok in ("\n", "\r\n"):
                self.newline()
            elif tok == "\r":
                self.col = 0
            elif tok == "\x08":
                self.col = max(0, self.col - 1)
            elif m.group(2):
                arg, cmd = m.group(1), m.group(2)
                n = int(arg) if arg.isdigit() else 1
                if cmd == "A":
                    self.row = max(0, self.row - n)
                elif cmd == "B":
                    self.row = min(len(self.lines) - 1, self.row + n)
                elif cmd == "G":
                    self.col = max(0, n - 1)
                elif cmd == "K":
                    line = self.lines[self.row]
                    self.lines[self.row] = "" if arg == "2" else " " * min(self.col, len(line)) + \
                        line[self.col:] if arg == "1" else line[:self.col]
        if pos < len(text):
            self.put(text[pos:])
        self.show()

    def show(self):
        frozen = []
        while self.row > self.LIVE:
            frozen.append(self.lines.pop(0))
            self.row -= 1
        live = "\n".join(self.lines)
        self.buf.delete(self.buf.get_iter_at_offset(self.fixed), self.buf.get_end_iter())
        if frozen:
            fixed = "\n".join(frozen) + "\n"
            self.buf.insert(self.buf.get_end_iter(), fixed)
            self.fixed += len(fixed)
        self.buf.insert(self.buf.get_end_iter(), live)

    def text(self):
        return self.buf.get_text(self.buf.get_start_iter(), self.buf.get_end_iter(), False)


def fmt_age(secs):
    """Antigüedad aproximada: hace 5 min, hace 3 h, hace 12 días, hace 4 meses, hace 2 años."""
    if secs < 3600:
        return "hace %s" % plural(max(1, secs // 60), "min", "min")
    if secs < 86400:
        return "hace %s" % plural(secs // 3600, "hora", "horas")
    if secs < 60 * 86400:
        return "hace %s" % plural(secs // 86400, "día", "días")
    if secs < 365 * 86400:
        return "hace %s" % plural(secs // (30 * 86400), "mes", "meses")
    return "hace %s" % plural(secs // (365 * 86400), "año", "años")


# Tipo c de la fecha de una base: no se ha importado con lvm-instalador
DB_DATE_HELP = ("Fecha en la que cambiaron por última vez las tablas de la BBDD (al importarla "
                "desde phpMyAdmin, por ejemplo). Las que se suben desde esta versión guardan la "
                "fecha exacta de la importación.")


def db_date_text(when, kind):
    """Fecha de una base para su fila: la de su importación o la del último cambio de sus tablas."""
    if not when:
        return ""
    stamp = time.strftime("%d/%m/%Y a las %H:%M", time.localtime(when))
    age = fmt_age(max(0, int(time.time()) - when))
    return ("Importada el %s  ·  %s" if kind == "i" else
            "Tablas cambiadas el %s  ·  %s") % (stamp, age)
