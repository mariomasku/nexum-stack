# ---------------------------------------------------------------- tareas con sudo

class Task:
    """Ejecuta un comando del script en una pseudoterminal y muestra su avance en una ventana.

    progress=True: instalaciones (barra y lista de pasos a partir de LVM_PROGRESO).
    El resto: barra en movimiento y la salida en el registro."""

    def __init__(self, app, title, args, progress=False, done_text=None, on_done=None,
                 auto_close=False, env=None, cancel_text=None):
        self.app, self.args, self.progress = app, args, progress
        self.env, self.cancel_text = env or {}, cancel_text
        self.done_text, self.on_done, self.auto_close = done_text, on_done, auto_close
        # (escondida con «Seguir en segundo plano»: el aviso de al lado del visor la trae de vuelta)
        self.background = False
        self.finished = self.cancelled = False
        self.prompts = 0
        self.since_prompt = ""
        self.pending = ""
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")
        self.pfile = None
        self.build(title)
        self.start()

    # ventana
    def build(self, title):
        dlg = Gtk.Dialog(title=title, transient_for=self.app.win, modal=True,
                         use_header_bar=True)
        dlg.set_default_size(620, -1)
        dlg.get_header_bar().set_show_close_button(False)
        # (Esc o cerrarla con la tarea en marcha: sigue en segundo plano, si la ventana tiene su aviso)
        dlg.connect("delete-event", self.on_delete)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=24)
        # Al terminar bien, un check verde grande: «Terminado» en gris no se ve de un vistazo
        ok_icon = "emblem-ok-symbolic" if Gtk.IconTheme.get_default().has_icon(
            "emblem-ok-symbolic") else "object-select-symbolic"
        self.done_icon = css(icon(ok_icon, 64), "nv-hecho")
        self.done_icon.set_no_show_all(True)
        box.pack_start(self.done_icon, False, False, 0)
        self.head = label(title, xalign=0.5, justify=Gtk.Justification.CENTER)
        css(self.head, "nv-titulo")
        self.head.set_line_wrap(True)
        box.pack_start(self.head, False, False, 0)
        # Encima de la barra: lo que se hace (a la izquierda) y el porcentaje con lo que queda
        top = Gtk.Box(spacing=12, margin_top=4)
        self.what = label("", "nv-tenue", ellipsize=3)
        top.pack_start(self.what, True, True, 0)
        self.pct = label("", "nv-porcentaje")
        top.pack_end(self.pct, False, False, 0)
        box.pack_start(top, False, False, 0)
        self.bar = css(Gtk.ProgressBar(), "nv-progreso")
        box.pack_start(self.bar, False, False, 0)
        self.info = label("", "nv-chico", "nv-tenue")
        box.pack_start(self.info, False, False, 0)
        # Porcentaje que se lee en la salida (tareas sin progreso propio): (primero, último, cuándo empezó)
        self.seen_pct = None

        self.parts_box = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "caja")
        self.parts_box.set_no_show_all(True)
        box.pack_start(self.parts_box, False, False, 0)
        self.parts_shown = []

        self.expander = Gtk.Expander(label="Ver registro", expanded=not self.progress)
        self.log = css(Gtk.TextView(editable=False, monospace=True, cursor_visible=False,
                                    wrap_mode=Gtk.WrapMode.WORD_CHAR, left_margin=14, right_margin=14,
                                    top_margin=10, bottom_margin=10, pixels_below_lines=2), "log", "nv-consola")
        self.console = Console(self.log.get_buffer())
        self.log_sw = css(Gtk.ScrolledWindow(min_content_height=220 if self.progress else 180, margin_top=8),
                          "nv-consola-marco")
        self.log_sw.add(self.log)
        self.expander.add(self.log_sw)
        box.pack_start(self.expander, True, True, 0)

        buttons = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER)
        # Si falla: el informe del error (o el registro) en una ventana para copiarlo
        self.report_btn = css(Gtk.Button(label="Ver el log del error"), "pildora")
        self.report_btn.set_no_show_all(True)
        self.report_btn.connect("clicked", self.show_report)
        buttons.pack_start(self.report_btn, False, False, 0)
        self.extra_btn = css(Gtk.Button(), "verde", "pildora")
        self.extra_btn.set_no_show_all(True)
        buttons.pack_start(self.extra_btn, False, False, 0)
        self.bg_btn = css(Gtk.Button(label="Seguir en segundo plano",
                                     tooltip_text="Esconder esta ventana y seguir usando el programa"), "pildora")
        self.bg_btn.connect("clicked", self.to_background)
        self.bg_btn.set_no_show_all(not hasattr(self.app, "nv_task_badge"))
        buttons.pack_start(self.bg_btn, False, False, 0)
        self.close_btn = css(Gtk.Button(label="Cancelar"), "pildora")
        self.close_btn.connect("clicked", self.on_close)
        buttons.pack_start(self.close_btn, False, False, 0)
        box.pack_start(buttons, False, False, 0)

        dlg.get_content_area().add(box)
        self.dlg = dlg
        dlg.show_all()

    def append(self, text):
        if not text:
            return
        self.console.write(text)
        if not self.progress:
            found = re.findall(r"(?<![\d.,])(\d{1,3})(?:[.,]\d+)?\s?%", ANSI.sub("", text))
            found = [int(n) for n in found if int(n) <= 100]
            if found:
                now = time.time()
                if self.seen_pct is None or found[-1] < self.seen_pct[1] - 30:
                    self.seen_pct = (found[-1], found[-1], now)
                else:
                    self.seen_pct = (self.seen_pct[0], found[-1], self.seen_pct[2])
        adj = self.log_sw.get_vadjustment()
        GLib.idle_add(lambda: adj.set_value(adj.get_upper() - adj.get_page_size()) and False)

    # proceso
    def start(self):
        env = script_env(**self.env)
        if self.progress:
            fd, self.pfile = tempfile.mkstemp(prefix="lvm-progreso-", dir="/tmp")
            os.close(fd)
            env["LVM_PROGRESO"] = self.pfile
        # (lo que cambia algo pide la contraseña al empezar: cancelarla no deja nada a medias)
        env["LVM_TAREA"] = "1"
        self.master, slave = pty.openpty()
        # Terminal exclusiva: ningún otro programa de tu usuario (el PHP de una web, por ejemplo)
        # puede abrirla para leer la contraseña o escribir la marca de sudo. Root (sudo) sí
        fcntl.ioctl(slave, termios.TIOCEXCL)
        fcntl.ioctl(self.master, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 160, 0, 0))
        self.tty = os.fstat(slave).st_rdev

        def as_terminal():
            # La pseudoterminal es la terminal de la sesion: sudo pide ahi la contraseña y
            # recuerda la autorizacion como en una terminal normal
            fcntl.ioctl(1, termios.TIOCSCTTY, 0)

        self.proc = subprocess.Popen(script_cmd(*self.args), stdin=subprocess.DEVNULL,
                                     stdout=slave, stderr=slave, env=env,
                                     # (preexec_fn con hilos: solo hace un ioctl, sin reservar memoria ni bloqueos)
                                     start_new_session=True, preexec_fn=as_terminal)  # noqa: PLW1509
        os.close(slave)
        flags = fcntl.fcntl(self.master, fcntl.F_GETFL)
        fcntl.fcntl(self.master, fcntl.F_SETFL, flags | os.O_NONBLOCK)
        self.watch = GLib.io_add_watch(GLib.IOChannel.unix_new(self.master), GLib.PRIORITY_DEFAULT,
                                       GLib.IOCondition.IN | GLib.IOCondition.HUP
                                       | GLib.IOCondition.ERR, self.on_output)
        GLib.child_watch_add(GLib.PRIORITY_DEFAULT, self.proc.pid, self.on_exit)
        self.started = time.time()
        self.timer = GLib.timeout_add(1000 if self.progress else 120, self.on_timer)
        self.on_timer()

    def read_all(self):
        chunks = []
        while True:
            try:
                data = os.read(self.master, 65536)
            except BlockingIOError:
                break
            except OSError:
                return chunks, True
            if not data:
                return chunks, True
            chunks.append(data)
        return chunks, False

    def on_output(self, *_):
        chunks, closed = self.read_all()
        for data in chunks:
            self.feed(self.decoder.decode(data))
        if closed:
            self.watch = None
            return False
        return True

    def feed(self, text):
        self.pending += text
        while SUDO_MARK in self.pending:
            before, self.pending = self.pending.split(SUDO_MARK, 1)
            self.append(before)
            self.since_prompt += before
            self.ask_password()
        # Se guarda un trozo que pueda ser el principio de la marca
        keep = 0
        for i in range(1, len(SUDO_MARK)):
            if self.pending.endswith(SUDO_MARK[:i]):
                keep = i
        out, self.pending = (self.pending[:-keep], self.pending[-keep:]) if keep else \
            (self.pending, "")
        self.since_prompt += out
        self.append(out)

    def sudo_asking(self):
        """¿Hay un sudo de root de esta tarea (descendiente de su proceso) en su terminal y sin hijos?
        Es lo que pasa cuando pide la contraseña. Cualquier programa de la tarea puede escribir la
        marca (la hereda en SUDO_PROMPT) y apagar el eco: así no se le manda a él"""
        procs = {}
        for name in os.listdir("/proc"):
            if not name.isdigit():
                continue
            try:
                with open("/proc/%s/stat" % name, "rb") as f:
                    stat = f.read().decode("ascii", "replace")
                with open("/proc/%s/status" % name, "rb") as f:
                    status = f.read().decode("utf-8", "replace")
            except OSError:
                continue
            comm = stat[stat.find("(") + 1:stat.rfind(")")]
            rest = stat[stat.rfind(")") + 2:].split()
            uid = next((l.split()[1:3] for l in status.splitlines() if l.startswith("Uid:")), [])
            if len(rest) < 5 or len(uid) < 2:
                continue
            tty = int(rest[4])
            procs[int(name)] = (int(rest[1]), comm, uid[1], os.makedev((tty >> 8) & 0xfff,
                                                                      (tty & 0xff) | ((tty >> 12) & 0xfff00)))
        children = {}
        for pid, (ppid, *_) in procs.items():
            children.setdefault(ppid, []).append(pid)
        stack, seen, found = [self.proc.pid], set(), []
        while stack:
            p = stack.pop()
            if p in seen:
                continue
            seen.add(p)
            for c in children.get(p, []):
                stack.append(c)
                # Solo cuenta un sudo de root (el de verdad es setuid): un programa tuyo que se
                # llame sudo no vale. Y en la terminal de la tarea, sin hijos (con hijos ya está
                # ejecutando la orden y la contraseña iría a ella)
                _, comm, euid, tty = procs[c]
                if comm == "sudo" and euid == "0" and tty == self.tty and not children.get(c):
                    found.append(c)
        return bool(found)

    def ask_password(self):
        retry = self.prompts > 0 and re.search(r"(?i)sorry|lo siento|incorrect|intent",
                                               self.since_prompt)
        self.prompts += 1
        self.since_prompt = ""
        if not self.sudo_asking():
            self.append("\nAviso: se ha pedido la contraseña, pero no la pide sudo. No se ha "
                        "enviado y se cancela la tarea.\n")
            self.cancel()
            return
        resp, password = password_dialog(self.dlg, os.environ.get("USER", ""), retry)
        if resp != Gtk.ResponseType.OK:
            self.cancel()
            return
        # Mientras el cuadro estaba abierto, sudo ha podido dejar de esperar: se vuelve a mirar
        if self.finished or not self.sudo_asking():
            self.append("\nAviso: sudo ya no esperaba la contraseña. No se ha enviado.\n")
            self.cancel()
            return
        # sudo apaga el eco de la terminal antes de pedirla. Si sigue encendido, quien la pide no
        # es sudo: no se escribe (se veria en el registro o la leeria otro programa)
        try:
            echo = termios.tcgetattr(self.master)[3] & termios.ECHO
        except termios.error:
            echo = True
        if echo:
            self.append("\nAviso: se ha pedido la contraseña, pero no la pide sudo. No se ha "
                        "enviado y se cancela la tarea.\n")
            self.cancel()
            return
        try:
            os.write(self.master, (password + "\n").encode())
        except OSError:
            pass

    def on_timer(self):
        if self.finished:
            return False
        if self.progress:
            self.show_progress(read_progress(self.pfile))
        elif self.seen_pct:
            # Sin progreso propio, pero la salida da un porcentaje (una descarga, por ejemplo)
            first, pct, since = self.seen_pct
            self.bar.set_fraction(pct / 100)
            self.what.set_label("Trabajando…")
            self.set_pct(pct, time_left(time.time() - since, pct - first, 100 - pct))
            self.info.set_label("Tiempo: %s" % fmt_clock(time.time() - self.started))
        else:
            self.bar.pulse()
            self.what.set_label("Trabajando…")
            self.pct.set_label("")
            self.info.set_label("Tiempo: %s  ·  sin porcentaje: esta tarea no dice cuánto le queda"
                                % fmt_clock(time.time() - self.started))
        return True

    def set_pct(self, pct, left):
        self.pct.set_label("%d %%" % pct + ("   ·   %s" % left if left else ""))

    def show_progress(self, p):
        elapsed = int(time.time() - self.started)
        if not p:
            self.bar.pulse()
            self.what.set_label("Preparando…")
            self.pct.set_label("0 %")
            self.info.set_label("Tiempo: %s" % fmt_clock(elapsed))
            return
        pct = p["pct"]
        total = ((p["k"] - 1) * 100 + pct) // p["n"]
        self.head.set_label(p["name"] + ("   (%d de %d)" % (p["k"], p["n"]) if p["n"] > 1 else ""))
        self.bar.set_fraction(total / 100)
        what = p["what"] or ("terminado" if pct >= 100 else "")
        self.what.set_label(what[:1].upper() + what[1:])
        since = int(time.time() - (p["started"] or self.started))
        self.set_pct(total, time_left(since, pct, 100 - pct) if pct < 100 else "")
        text = "Tiempo: %s" % fmt_clock(since)
        if p["mode"] == "fdpos" and p["total"]:
            text = "%s de %s   ·   %s" % (fmt_size(min(p["done"], p["total"])),
                                         fmt_size(p["total"]), text)
        self.info.set_label(text)
        self.show_parts(p["parts"], p["cur"])

    def show_parts(self, parts, cur):
        if not parts:
            return
        if parts != self.parts_shown:
            clear(self.parts_box)
            self.part_rows = []
            for name in parts:
                r = ActionRow(name)
                st = Gtk.Stack()
                st.add_named(label("…", "dim-label"), "pend")
                st.add_named(Gtk.Spinner(active=True), "run")
                st.add_named(css(icon("object-select-symbolic"), "punto-verde"), "ok")
                st.add_named(css(icon("dialog-error-symbolic"), "error"), "error")
                r.add_suffix(st)
                self.parts_box.add(r)
                self.part_rows.append(st)
            # (sin no_show_all: con él, show_all no muestra las filas y la lista sale vacía)
            self.parts_box.set_no_show_all(False)
            self.parts_box.show_all()
            self.parts_shown = parts
        for i, st in enumerate(self.part_rows, 1):
            st.set_visible_child_name("ok" if i < cur else "run" if i == cur else "pend")

    def on_exit(self, _pid, status):
        rc = os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1
        chunks, _ = self.read_all()
        for data in chunks:
            self.feed(self.decoder.decode(data))
        self.append(self.pending)
        if self.watch:
            GLib.source_remove(self.watch)
        try:
            os.close(self.master)
        except OSError:
            pass
        self.finish(rc)

    def on_delete(self, *_):
        if self.finished:
            return False
        if hasattr(self.app, "nv_task_badge"):
            self.to_background()
        return True

    def to_background(self, *_):
        """La tarea sigue sin su ventana: el programa se puede usar (sin lanzar otra tarea a la vez) y, al
        lado del visor, una flecha verde que late la trae de vuelta."""
        if self.finished or not hasattr(self.app, "nv_task_badge"):
            return
        self.background = True
        self.dlg.set_modal(False)
        self.dlg.hide()
        self.app.nv_task_badge(self)

    def to_front(self, *_):
        self.background = False
        if hasattr(self.app, "nv_task_badge"):
            self.app.nv_task_badge(None)
        self.dlg.set_modal(True)
        self.dlg.present()

    def finish(self, rc):
        self.finished = True
        self.bg_btn.hide()
        hidden = self.background
        if hidden:
            self.background = False
            self.app.nv_task_badge(None)
        p = read_progress(self.pfile) if self.pfile else None
        if self.pfile:
            try:
                os.unlink(self.pfile)
            except OSError:
                pass
        ok = rc == 0 and not self.cancelled
        self.info.set_label("Tiempo total: %s" % fmt_clock(time.time() - self.started))
        self.bar.set_fraction(1 if ok else self.bar.get_fraction())
        self.close_btn.set_label("Cerrar")
        if self.cancelled:
            self.head.set_label("Cancelado")
            self.what.set_label("Cancelado")
            self.pct.set_label("")
        elif ok:
            self.head.set_label(self.done_text or "Terminado")
            self.what.set_label("Terminado")
            self.pct.set_label("100 %")
            self.done_icon.show()
            self.head.set_xalign(0.5)
        else:
            self.head.set_label("No se ha podido completar")
            self.what.set_label("Error")
            self.pct.set_label("")
            css(self.bar, "nv-progreso-error")
            self.expander.set_expanded(True)
            self.report_btn.show()
            if p and self.part_rows_present():
                for i, st in enumerate(self.part_rows, 1):
                    if i == p["cur"]:
                        st.set_visible_child_name("error")
        if p:
            self.show_results(p, ok)
        if ok and self.progress and self.part_rows_present():
            for st in self.part_rows:
                st.set_visible_child_name("ok")
        if self.on_done:
            self.on_done(ok, self, p)
        if ok and self.auto_close:
            self.dlg.destroy()
            self.app.toast(self.done_text or "Terminado")
        elif hidden:
            # (en segundo plano: vuelve para enseñar cómo ha ido; si ha fallado, con su registro)
            self.dlg.set_modal(True)
            self.dlg.present()

    def log_text(self):
        return self.console.text()

    def show_report(self, *_):
        """El informe que deja el script al fallar una instalacion (uno por version con error) o,
        si no lo hay, el registro entero"""
        log = self.log_text()
        # Solo los informes de la carpeta de registros: la linea podria escribirla otro programa
        # para mostrar (y copiar) cualquier fichero
        logs = os.path.realpath(LOG_DIR) + os.sep
        paths = [p for p in dict.fromkeys(re.findall(r"^Informe del error: (.+?)\s*$", log, re.M))
                 if os.path.realpath(p).startswith(logs) and os.path.basename(p) == "informe-error.txt"]
        parts = []
        for path in paths:
            try:
                with open(path, encoding="utf-8", errors="replace") as f:
                    parts.append(f.read().rstrip())
            except OSError:
                pass
        text = ("\n\n" + "=" * 70 + "\n\n").join(parts) if parts else log.strip()
        folder = os.path.dirname(paths[-1]) if parts else LOG_DIR

        dlg = Gtk.Dialog(title="Log del error", transient_for=self.dlg, modal=True,
                         use_header_bar=True)
        dlg.set_default_size(820, 560)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=16)
        box.pack_start(label("Copia el texto para buscar la solución o para enviarlo. "
                             + ("Incluye el sistema, el paso que ha fallado y sus errores. "
                                if parts else "")
                             + "Los logs completos están en %s." % folder,
                             "dim-label", wrap=True), False, False, 0)
        view = css(Gtk.TextView(editable=False, monospace=True, wrap_mode=Gtk.WrapMode.CHAR),
                   "log")
        view.get_buffer().set_text(text)
        sw = Gtk.ScrolledWindow(vexpand=True)
        sw.add(view)
        box.pack_start(sw, True, True, 0)
        row = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER)
        copy = css(Gtk.Button(label="Copiar todo"), "verde", "pildora")

        def on_copy(*_):
            Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(text, -1)
            copy.set_label("Copiado")
            GLib.timeout_add(2000, lambda: copy.set_label("Copiar todo") and False)

        copy.connect("clicked", on_copy)
        row.pack_start(copy, False, False, 0)
        folder_btn = css(Gtk.Button(label="Abrir la carpeta de logs"), "pildora")
        folder_btn.connect("clicked", lambda *_: self.app.open_uri("file://" + folder))
        row.pack_start(folder_btn, False, False, 0)
        close = css(Gtk.Button(label="Cerrar"), "pildora")
        close.connect("clicked", lambda *_: dlg.destroy())
        row.pack_start(close, False, False, 0)
        box.pack_start(row, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.show_all()

    def part_rows_present(self):
        return bool(getattr(self, "part_rows", None))

    def show_results(self, p, ok):
        res = [r for r in p["results"] if not r[0].startswith("bd:")]
        if len(res) > 1 or (res and not ok):
            good = [i for i, rc in res if rc == "0"]
            bad = [i for i, rc in res if rc != "0"]
            text = []
            if good:
                text.append("Instaladas: " + ", ".join("lampp-" + item_folder(i) for i in good))
            if bad:
                text.append("Con error: " + ", ".join("lampp-" + item_folder(i) for i in bad)
                            + ". No se ha instalado nada de ellas; mira el registro.")
            self.info.set_label("\n".join(text))
            if res and len(good) == len(res):
                self.head.set_label(self.done_text or "Terminado")

    def offer(self, text, callback):
        self.extra_btn.set_label(text)
        self.extra_btn.connect("clicked", lambda *_: (self.dlg.destroy(), callback()))
        self.extra_btn.show()

    def cancel(self):
        if self.finished:
            return
        self.cancelled = True
        try:
            os.killpg(self.proc.pid, signal.SIGTERM)
        except OSError:
            pass

    def on_close(self, *_):
        if self.finished:
            self.dlg.destroy()
            return
        if self.progress:
            title, text, ok = self.cancel_text or (
                "¿Cancelar la instalación?",
                "Se pierde lo descargado y compilado. Las versiones instaladas no se tocan.",
                "Cancelar la instalación")
            if not confirm(self.dlg, title, text, ok, destructive=True):
                return
        self.cancel()
