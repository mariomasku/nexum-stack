class AppServicios:
    """Servicios de la versión activa: arrancar, parar y proteger."""

    # -------------------------------------------------------------- servicios
    def on_services_data(self, _rc, out):
        rows = [{"name": f[1], "running": f[2] == "1", "ports": f[3], "open": f[4] == "1",
                 "auto": f[5] == "1", "user": f[6] if len(f) > 6 else ""}
                for f in parse_lines(out) if f[0] == "S" and len(f) >= 6]
        if rows != self.services:
            self.services = rows
            self.build_services()
        return False

    def build_services(self):
        """Apache, MariaDB y el FTP de la versión montada, como el panel de XAMPP: si están en
        marcha, si se puede entrar desde la red y botones para arrancarlos, pararlos o
        reiniciarlos. El FTP no arranca con la versión: se arranca aquí cuando haga falta."""
        clear(self.services_box)
        d = self.data
        if not d or self.services is None:
            self.loading(self.services_box)
            return
        if not d["active"]:
            box, lb = group("Servicios")
            row = ActionRow("Ninguna versión activa",
                            "Activa una versión en la pestaña Versiones para ver sus servicios.")
            row.add_prefix(label("●", "punto-gris"))
            lb.add(row)
            self.services_box.pack_start(box, False, False, 0)
            self.services_box.show_all()
            return
        # Cabecera: versión, cuántos están en marcha y si solo se entra desde este equipo
        running = sum(1 for sv in self.services if sv["running"])
        exposed = any(sv["open"] for sv in self.services)
        head = Gtk.Box(spacing=12, margin_bottom=4)
        texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, valign=Gtk.Align.CENTER)
        texts.pack_start(label("Servicios de lampp-%s" % d["active"], "titulo-grande"),
                         False, False, 0)
        texts.pack_start(label("%d de %d en marcha" % (running, len(self.services)),
                               "dim-label"), False, False, 0)
        head.pack_start(texts, True, True, 0)
        if exposed:
            badge = label("Abierto a la red", "pastilla", "peligro", valign=Gtk.Align.CENTER)
        else:
            badge = label("Solo desde este equipo", "pastilla", "segura", valign=Gtk.Align.CENTER,
                          tooltip_text="Solo accesibles desde este equipo")
        head.pack_end(badge, False, False, 0)
        # (en la ventana nueva, arrancar o parar la version entera: lo que hacia el boton Encendidos)
        if hasattr(self, "nv_power"):
            on = d["running"]
            b = Gtk.Button(label="Parar y desactivar" if on else "Arrancar lampp-%s" % d["active"],
                           valign=Gtk.Align.CENTER, sensitive=not self.busy)
            if not on:
                css(b, "verde")
            b.connect("clicked", lambda *_: (self.services_pop.popdown(), self.nv_power()))
            head.pack_end(b, False, False, 0)
        self.services_box.pack_start(head, False, False, 0)

        info = {"apache": ("Apache", "Servidor web: las webs de /opt/htdocs y phpMyAdmin (con PHP)",
                           ("logo", "apache")),
                "mariadb": ("MariaDB", "Servidor de BBDD", ("logo", "mariadb")),
                "ftp": ("FTP (ProFTPD)", "Acceso por FTP a /opt/htdocs. No arranca con la versión: "
                        "arráncalo cuando lo necesites y páralo después.",
                        ("icono", "folder-remote-symbolic", ""))}
        cards = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        for sv in self.services:
            title, help_text, spec = info.get(sv["name"], (sv["name"], "",
                                                           ("icono", "system-run-symbolic", "")))
            card = css(Gtk.Box(spacing=16), "servicio")
            card.pack_start(section_icon(spec, 26, "icono-servicio"), False, False, 0)
            mid = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4,
                          valign=Gtk.Align.CENTER)
            top = Gtk.Box(spacing=10)
            top.pack_start(label(title, "servicio-nombre"), False, False, 0)
            if sv["running"]:
                top.pack_start(label("En marcha", "pastilla", "activa", valign=Gtk.Align.CENTER),
                               False, False, 0)
            else:
                top.pack_start(label("Parado", "pastilla", "parada", valign=Gtk.Align.CENTER),
                               False, False, 0)
            if sv["open"]:
                top.pack_start(label("Abierto a la red", "pastilla", "peligro",
                                     valign=Gtk.Align.CENTER), False, False, 0)
            mid.pack_start(top, False, False, 0)
            mid.pack_start(label(help_text, "dim-label", "subtitulo", wrap=True,
                                 max_width_chars=44), False, False, 0)
            chips = Gtk.Box(spacing=6, margin_top=2)
            for port in [p.strip() for p in sv["ports"].split(",") if p.strip()]:
                chips.pack_start(label("Puerto %s" % port, "chip"), False, False, 0)
            if sv["name"] == "ftp" and sv["user"]:
                chips.pack_start(label("usuario %s" % sv["user"], "chip"), False, False, 0)
            if sv["name"] == "ftp" and sv["auto"]:
                chips.pack_start(label("arranca con la versión", "chip"), False, False, 0)
            mid.pack_start(chips, False, False, 0)
            card.pack_start(mid, True, True, 0)
            actions = Gtk.Box(spacing=8, valign=Gtk.Align.CENTER)
            buttons = [("view-refresh-symbolic", "Reiniciar", "reiniciar", None),
                       ("media-playback-stop-symbolic", "Parar", "parar", None)] \
                if sv["running"] else \
                [("media-playback-start-symbolic", "Arrancar", "arrancar", "verde")]
            for ic, text, cmd, cls in buttons:
                b = Gtk.Button()
                inner = Gtk.Box(spacing=6)
                inner.pack_start(icon(ic), False, False, 0)
                inner.pack_start(Gtk.Label(label=text), False, False, 0)
                b.add(inner)
                if cls:
                    css(b, cls)
                b.connect("clicked", self.on_service, sv["name"], cmd, title)
                actions.pack_start(b, False, False, 0)
            card.pack_end(actions, False, False, 0)
            cards.pack_start(card, False, False, 0)
        self.services_box.pack_start(cards, False, False, 0)

        if any(sv["open"] for sv in self.services):
            box, lb = group("Se puede entrar desde otros equipos de la red")
            row = ActionRow("Abierto a la red", d["exposed"] or "Algún servicio escucha en toda la red")
            b = css(Gtk.Button(label="Cerrar a la red"), "verde")
            b.connect("clicked", self.on_secure)
            row.add_suffix(b)
            lb.add(row)
            self.services_box.pack_start(box, False, False, 0)
        self.services_box.show_all()

    def on_service(self, _btn, name, cmd, title):
        verbs = {"arrancar": ("Arrancando", "arrancado"), "parar": ("Parando", "parado"),
                 "reiniciar": ("Reiniciando", "reiniciado")}
        doing, done = verbs[cmd]
        self.run_task("%s %s" % (doing, title), ["servicio", name, cmd],
                      done_text="%s %s" % (title, done), auto_close=True)

    def on_update_pma(self, folder):
        self.run_task("Actualizando phpMyAdmin", ["actualizar-phpmyadmin", folder], progress=True,
                      done_text="phpMyAdmin actualizado", auto_close=True)

    def on_secure_all(self, *_):
        self.run_task("Protegiendo las versiones", ["asegurar", "--todas"],
                      done_text="Todas las versiones son solo para este equipo", auto_close=True)

    def on_secure(self, *_):
        self.run_task("Cerrando a la red", ["asegurar"],
                      done_text="Solo se puede entrar desde este equipo", auto_close=True)
