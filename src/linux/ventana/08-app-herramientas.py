class AppHerramientas:
    """Configuración: ficheros, carpetas, programa e información."""

    # ------------------------------------------------------- herramientas
    def build_tools(self):
        """Lo que se usa de vez en cuando: ficheros de configuración, carpetas, actualizar el
        programa e información."""
        clear(self.tools_box)
        d = self.data

        def add_row(lb, title, sub, btn_text, cb):
            row = ActionRow(title, sub)
            b = Gtk.Button(label=btn_text, valign=Gtk.Align.CENTER)
            b.connect("clicked", lambda *_: cb())
            row.add_suffix(b)
            lb.add(row)

        box, lb = tile_group("Configuración",
                        "Los vhosts y los hosts del sistema son del administrador: se edita una "
                        "copia y se aplica con Aplicar (pide la contraseña).")
        add_row(lb, "Virtual hosts", d["vhosts"], "Editar…", self.on_vhosts)
        add_row(lb, "Hosts del sistema", d["hosts"], "Editar…", self.on_hosts)
        self.tools_box.pack_start(box, False, False, 0)

        if d["unregistered"]:
            box, lb = tile_group("XAMPP sin registrar",
                            "/opt/lampp es una instalación de XAMPP completa y no un enlace.")
            add_row(lb, "XAMPP en /opt/lampp", "Regístralo con un nombre para gestionarlo junto a "
                    "las demás versiones", "Registrar…", self.on_register)
            self.tools_box.pack_start(box, False, False, 0)

        box, lb = tile_group("Carpetas")
        add_row(lb, "Proyectos", "/opt/htdocs, compartida por todas las versiones", "Abrir",
                lambda: self.open_uri(GLib.filename_to_uri("/opt/htdocs")))
        copies = os.path.expanduser("~/lvm-copias")
        add_row(lb, "Copias de seguridad", "~/lvm-copias: BBDD borradas o desinstaladas y "
                "/etc/hosts anteriores", "Abrir",
                lambda: (os.makedirs(copies, exist_ok=True),
                         self.open_uri(GLib.filename_to_uri(copies))))
        add_row(lb, "Registros de instalaciones", "~/.lvm-instalador: logs de las instalaciones "
                "y de la ventana", "Abrir", lambda: self.open_uri(GLib.filename_to_uri(LOG_DIR)))
        # Caché de descargas de las pilas propias: lo que ocupa y vaciarla
        n, size = downloads_cache_size()
        row = ActionRow("Caché de descargas",
                        "%s: el código de los componentes ya comprobado, para no descargarlo otra vez y para "
                        "instalar aunque su web no responda. %s" % (DL_CACHE_DIR, "Ocupa %s (%s)." % (
                            fmt_size(size), plural(n, "fichero", "ficheros")) if n else "Está vacía."))
        b = Gtk.Button(label="Vaciar…", valign=Gtk.Align.CENTER, sensitive=n > 0 and not self.busy)
        b.connect("clicked", lambda *_: self.on_clear_downloads(size))
        row.add_suffix(b)
        lb.add(row)
        self.tools_box.pack_start(box, False, False, 0)

        self.build_error_logs(add_row)

        box, lb = tile_group("Programa")
        add_row(lb, "Buscar una versión nueva", "Busca en GitHub (y en Descargas) una versión más "
                "nueva, firmada, y la instala", "Buscar", lambda: self.check_package(manual=True))
        add_row(lb, "Icono en el menú de aplicaciones", "Vuelve a crear el acceso «Nexum Dev Stack» "
                "si no aparece o no abre esta ventana", "Crear de nuevo",
                self.on_create_launcher)
        self.nv_tray_row(lb)
        self.tools_box.pack_start(box, False, False, 0)

        box, lb = tile_group("Información")
        add_row(lb, "Comandos de lvm-instalador", "Todos los comandos para la terminal y qué hace "
                "cada uno", "Ver", self.on_commands)
        add_row(lb, "Novedades", "Qué ha cambiado en cada versión", "Ver", self.on_changes)
        add_row(lb, "Acerca de", "%s %s" % (d["name"], d["version"]), "Ver", self.on_about)
        self.tools_box.pack_start(box, False, False, 0)
        self.tools_box.show_all()

    def nv_tray_row(self, lb):
        """Configuración, Programa: el icono junto al reloj (solo en la ventana nueva)."""
        if not hasattr(self, "nv_tray_toggle"):
            return
        has = tray_lib() is not None
        row = ActionRow("Dejar en la bandeja al cerrar",
                        "La X la esconde en un icono junto al reloj (abrir, arrancar o parar, web.local y salir)"
                        if has else
                        "Falta su componente. En una terminal: sudo apt install gir1.2-ayatanaappindicator3-0.1")
        sw = Gtk.Switch(active=has and tray_wanted(), valign=Gtk.Align.CENTER, sensitive=has)
        sw.connect("notify::active", self.nv_tray_toggle)
        row.add_suffix(sw)
        lb.add(row)

    def project_error_log(self, link=None):
        """Registro de errores del vhost de los proyectos (web.local) o del dominio que se diga,
        sacado de su ErrorLog: con PHP-FPM, los errores de PHP de la web cargada (el «error
        crítico» de WordPress) van ahí y no al error_log general de Apache."""
        link = link or (self.projects or {}).get("link") or ""
        if not link:
            return None
        try:
            with open(self.data["vhosts"], errors="replace") as fh:
                text = fh.read(2000000)
        except OSError:
            text = ""
        for m in re.finditer(r"(?is)<VirtualHost\b[^>]*>(.*?)</VirtualHost>", text):
            body = m.group(1)
            names = " ".join(re.findall(r"(?im)^[ \t]*Server(?:Name|Alias)[ \t]+(.+)$", body)).lower().split()
            e = re.search(r"(?im)^[ \t]*ErrorLog[ \t]+\"?([^\"\s]+)\"?", body)
            if link.lower() in names and e and not e.group(1).startswith(("|", "syslog")):
                path = e.group(1)
                return path if path.startswith("/") else os.path.join("/opt/lampp", path)
        # (sin ErrorLog propio, sus errores van al general: no hay otro registro que enseñar)
        path = os.path.join("/opt/lampp/logs", link + "-error_log")
        return path if os.path.isfile(path) else None

    def log_row(self, title, path, note=""):
        """Fila de un registro: dónde está, cuánto ocupa y cuándo se cambió."""
        try:
            st = os.stat(path)
        except OSError:
            return ActionRow(title, "%s: no existe todavía (se crea con el primer error)" % path)
        when = GLib.DateTime.new_from_unix_local(int(st.st_mtime)).format("%d/%m/%Y %H:%M")
        size = GLib.format_size(st.st_size)
        sub = "%s  ·  %s  ·  modificado el %s" % (path, size, when)
        if note:
            sub = note + "\n" + sub
        row = ActionRow(title, sub)
        row.subtitle.set_line_wrap(True)
        row.subtitle.set_ellipsize(0)
        b = Gtk.Button(label="Ver el final", sensitive=st.st_size > 0, valign=Gtk.Align.CENTER)
        b.connect("clicked", lambda *_: self.show_log_tail(path))
        row.add_suffix(b)
        b = Gtk.Button(label="Abrir", valign=Gtk.Align.CENTER)
        # Un fichero de cientos de MB dejaria colgado el editor de textos
        if st.st_size > LOG_OPEN_MAX:
            b.set_sensitive(False)
            b.set_tooltip_text("Ocupa %s: usa «Ver el final»" % size)
        b.connect("clicked", lambda *_: self.open_text(path))
        row.add_suffix(b)
        return row

    def build_error_logs(self, add_row):
        """Los registros de errores de la versión montada: el del vhost del proyecto cargado
        (web.local), donde van los errores de PHP de la web, y el general de Apache."""
        box, lb = tile_group("Registro de errores",
                        "Si la web cargada da un error (el «error crítico» de WordPress), el motivo "
                        "está en el registro de su vhost: ahí van los errores de PHP. Los de Apache "
                        "(que no arranca, un vhost mal escrito…), en el general. Lo más reciente "
                        "está al final.")
        path = self.project_error_log()
        if path:
            p = self.projects
            name = os.path.basename(p["current"].rstrip("/")) if p and p.get("current") else ""
            lb.add(self.log_row("error_log de %s%s" % (p["link"], "  (%s)" % name if name else ""), path))
        lb.add(self.log_row("error_log de Apache (lampp-%s)" % self.data["active"], APACHE_ERROR_LOG))
        self.tools_box.pack_start(box, False, False, 0)

    def show_log_tail(self, path, lines=400):
        """Últimas líneas de un registro (lo más reciente al final), sin leer el fichero entero."""
        try:
            # (sin quedarse esperando si no es un fichero normal: una tubería colgaría la ventana)
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
            if not stat.S_ISREG(os.fstat(fd).st_mode):
                os.close(fd)
                raise OSError("no es un fichero normal")
            with os.fdopen(fd, "rb") as f:
                f.seek(0, os.SEEK_END)
                size = f.tell()
                f.seek(max(0, size - 256 * 1024))
                text = f.read().decode("utf-8", "replace")
        except OSError as exc:
            message(self.win, "No se ha podido leer %s" % path, str(exc), Gtk.MessageType.ERROR)
            return
        self.show_text(os.path.basename(path), "Últimas %d líneas de %s" % (lines, path),
                       text, lambda: self.show_log_tail(path, lines), lines)

    def show_text(self, title, subtitle, text, reload=None, lines=400, to_end=True):
        """Las últimas líneas de un registro (lo más reciente al final) en un diálogo, con «Copiar
        todo» y, con reload, «Actualizar» (lo vuelve a leer)."""
        # (los de PHP-FPM llegan en una sola línea con \n escritos: se separan para leerlos)
        text = "\n".join(text.splitlines()[-lines:]).replace("\\n", "\n    ") or "(vacío)"
        dlg = Gtk.Dialog(title=title, transient_for=self.win, modal=True,
                         use_header_bar=True)
        dlg.set_default_size(980, 620)
        hb = dlg.get_header_bar()
        hb.set_subtitle(subtitle)
        copy = Gtk.Button(label="Copiar todo")
        copy.connect("clicked", lambda *_: (
            Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(text, -1),
            self.toast("Copiado al portapapeles")))
        hb.pack_start(copy)
        if reload is not None:
            reload_btn = Gtk.Button(label="Actualizar")
            reload_btn.connect("clicked", lambda *_: (dlg.destroy(), reload()))
            hb.pack_end(reload_btn)
        tv = css(Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                              wrap_mode=Gtk.WrapMode.WORD_CHAR, left_margin=12, right_margin=12,
                              top_margin=8, bottom_margin=8), "log")
        buf = tv.get_buffer()
        buf.set_text(text)
        sw = Gtk.ScrolledWindow(vexpand=True)
        sw.add(tv)
        dlg.get_content_area().add(sw)
        dlg.show_all()
        # Lo más reciente está al final
        if to_end:
            GLib.idle_add(lambda: (tv.scroll_to_iter(buf.get_end_iter(), 0, False, 0, 1), False)[1])
        run_dialog(dlg)
        dlg.destroy()
