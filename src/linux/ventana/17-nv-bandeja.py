class NvBandeja:
    """El icono junto al reloj."""

    # ------------------------------------------------------------------ icono junto al reloj
    def nv_tray_setup(self):
        """El icono junto al reloj (si está encendido en Configuración y hay AppIndicator): abrir la ventana,
        arrancar o parar la versión activa, abrir web.local y salir."""
        if self.tray is not None or not tray_wanted():
            return
        lib = tray_lib()
        if lib is None:
            return
        ind = lib.Indicator.new(APP_ID, self.icon, lib.IndicatorCategory.APPLICATION_STATUS)
        ind.set_title("Nexum Dev Stack")
        menu = Gtk.Menu()

        def add(key, text, cb=None):
            item = Gtk.MenuItem(label=text)
            if cb:
                item.connect("activate", lambda *_: cb())
            else:
                item.set_sensitive(False)
            menu.append(item)
            self.tray_items[key] = item
        add("open", "Abrir Nexum Dev Stack", self.nv_tray_open)
        menu.append(Gtk.SeparatorMenuItem())
        add("state", "Ninguna versión activa")
        add("power", "Arrancar", self.nv_tray_power)
        add("web", "Abrir web.local", self.nv_tray_web)
        menu.append(Gtk.SeparatorMenuItem())
        add("quit", "Salir", self.nv_tray_quit)
        menu.show_all()
        ind.set_menu(menu)
        ind.set_secondary_activate_target(self.tray_items["open"])
        ind.set_status(lib.IndicatorStatus.ACTIVE)
        self.tray = (lib, ind, menu)
        self.nv_tray_update()

    def nv_tray_remove(self):
        if self.tray is None:
            return
        lib, ind, _menu = self.tray
        ind.set_status(lib.IndicatorStatus.PASSIVE)
        self.tray, self.tray_items = None, {}

    def nv_tray_update(self):
        if self.tray is None:
            return
        d = self.data or {}
        act = d.get("active") or ""
        it = self.tray_items
        if not act:
            it["state"].set_label("Ninguna versión activa")
            it["power"].set_label("Elegir una versión…")
        else:
            it["state"].set_label("● lampp-%s en marcha" % act if d.get("running") else "○ lampp-%s parada" % act)
            it["power"].set_label("Parar y desactivar" if d.get("running") else "Arrancar lampp-%s" % act)
        it["power"].set_sensitive(bool(d) and not self.busy)
        link = (self.projects or {}).get("link") or ""
        it["web"].set_label("Abrir %s" % (link or "web.local"))
        it["web"].set_sensitive(bool(link) and bool(d.get("running")))

    def nv_tray_hide(self):
        """La X de la ventana: con el icono, la esconde (True: no se cierra); sin él, se cierra como siempre."""
        if self.tray is None:
            return False
        self.win.hide()
        return True

    def nv_tray_open(self):
        self.win.present()
        # (al volver, sus datos al momento: escondida solo se preguntaba lo del menú)
        if not self.busy:
            run_quick(["gui-vuelta"], self.on_round)

    def nv_tray_power(self):
        if not (self.data or {}).get("active"):
            self.nv_tray_open()
        self.nv_power()

    def nv_tray_web(self):
        link = (self.projects or {}).get("link")
        if link:
            self.open_uri("http://%s/" % link)

    def nv_tray_quit(self):
        self.nv_tray_remove()
        self.win.destroy()

    def nv_tray_toggle(self, sw, _p):
        on = sw.get_active()
        try:
            os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
            with open(TRAY_FILE, "w", encoding="utf-8") as f:
                f.write("si\n" if on else "no\n")
        except OSError as exc:
            message(self.win, "No se ha podido guardar", str(exc), Gtk.MessageType.ERROR)
            return
        if on:
            self.nv_tray_setup()
        else:
            self.nv_tray_remove()

    def nv_exit(self):
        """Al cerrar la última ventana: se sale y, si algo lo retuviera (un bucle, un hilo, una orden que
        no acaba), a los 5 s se corta el proceso. Nunca queda un Nexum en marcha sin ventana."""
        self.quit()

        def watchdog():
            time.sleep(5)
            os._exit(0)
        threading.Thread(target=watchdog, daemon=True).start()

    def auto_check_package(self):
        if self.data is None or self.busy:
            return True
        if self.update_check_due():
            self.check_package(auto=True)
            # (y los parches de los componentes, un poco después: sin juntarse con el aviso del programa)
            GLib.timeout_add_seconds(25, self.nv_components_auto)
        return False

    def update_check_due(self):
        """¿Toca buscar una versión nueva al abrir? El primer arranque de cada día y, después, cada
        UPDATE_EVERY arranques. Se lleva en ~/.nexum/actualizaciones-arranques: fecha y los
        arranques desde la última vez que se buscó."""
        path = os.path.join(LOG_DIR, "actualizaciones-arranques")
        today = time.strftime("%Y-%m-%d")
        if SIMULATE:
            return True
        try:
            with open(path, encoding="utf-8") as fh:
                day, _, n = fh.read(40).strip().partition(" ")
            n = int(n)
        except (OSError, ValueError):
            day, n = "", 0
        due = day != today or n + 1 >= UPDATE_EVERY
        try:
            os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
            with open(path + ".nuevo", "w", encoding="utf-8") as fh:
                fh.write("%s %d\n" % (today, 0 if due else n + 1))
            os.replace(path + ".nuevo", path)
        except OSError:
            pass
        return due

    def nv_header(self):
        hb = css(Gtk.HeaderBar(show_close_button=True), "nv-cabecera")
        brand = Gtk.Box(spacing=10)
        brand.pack_start(icon(self.icon, 30), False, False, 0)
        t = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
        # «NEXUM» en Goldman y «Dev Stack» sin negrita, en azul
        name = Gtk.Box(spacing=7)
        name.pack_start(label("NEXUM", "nv-titulo", "nv-nexum"), False, False, 0)
        name.pack_start(label("Dev Stack", "nv-titulo", "nv-marca"), False, False, 0)
        t.pack_start(name, False, False, 0)
        # (con la versión del programa detrás, al leer los datos)
        self.brand_sub = label("Entornos LAMPP y Docker", "nv-chico", "nv-tenue")
        t.pack_start(self.brand_sub, False, False, 0)
        brand.pack_start(t, False, False, 0)
        hb.pack_start(brand)
        # La version activa: al pulsarla, sus servicios (los de la pestaña Servicios de siempre)
        # Menu con un icono en cada opcion (el de GTK 3 a partir de un Gio.Menu no los pone) y el tema.
        # Sin recuadro, a la derecha del visor, con sus tres rayas mas anchas que las del tema
        mb = css(Gtk.MenuButton(tooltip_text="Menú", relief=Gtk.ReliefStyle.NONE, valign=Gtk.Align.CENTER), "nv-hamburguesa")
        mb.add(Hamburger())
        pop = Gtk.Popover(relative_to=mb)
        mbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1, margin=4)
        self.theme_item = None
        for n, section in enumerate([
                [("@tema", None, lambda: self.nv_theme())],
                [("Editar vhosts", "document-edit-symbolic", lambda: self.on_vhosts()),
                 ("Editar /etc/hosts", "network-workgroup-symbolic", lambda: self.on_hosts())],
                [("Volver a leer las versiones", "view-refresh-symbolic", lambda: self.on_refresh()),
                 ("Buscar actualizaciones", "software-update-available-symbolic", lambda: self.check_package(manual=True)),
                 ("Abrir el panel en la terminal", "utilities-terminal-symbolic", lambda: self.on_terminal()),
                 ("Carpeta de registros", "folder-documents-symbolic", lambda: self.open_uri("file://" + LOG_DIR))],
                [("Ayuda", "help-browser-symbolic", lambda: self.on_help()),
                 ("Novedades", "starred-symbolic", lambda: self.on_changes()),
                 ("Acerca de Nexum Dev Stack", "help-about-symbolic", lambda: self.on_about())]]):
            if n:
                mbox.pack_start(Gtk.Separator(margin_top=4, margin_bottom=4), False, False, 0)
            for text, ic, fn in section:
                b = css(Gtk.Button(relief=Gtk.ReliefStyle.NONE), "nv-menuitem")
                row = Gtk.Box(spacing=10)
                img = symbol(ic or "weather-clear-night-symbolic", 16)
                lbl = Gtk.Label(label=text, xalign=0)
                row.pack_start(img, False, False, 0)
                row.pack_start(lbl, True, True, 0)
                b.add(row)
                b.connect("clicked", lambda _b, fn=fn: (pop.popdown(), fn()))
                if text == "@tema":
                    self.theme_item = (img, lbl)
                mbox.pack_start(b, False, False, 0)
        mbox.show_all()
        pop.add(mbox)
        mb.set_popover(pop)
        self.menu_btn = mb
        # Recuadro de la version montada: el logotipo de PHP y su version y Apache y MariaDB con su punto
        # (verde si estan en marcha); al pulsar en ellos, sus servicios (arrancarlos, pararlos...)
        pill = css(Gtk.Box(spacing=8, valign=Gtk.Align.CENTER), "nv-pastilla")
        # ▶ / ■ (a la derecha de los servicios): arrancar o parar la version; sin ninguna activa, ▶
        # despliega las versiones para elegir
        self.power_btn = css(Gtk.Button(valign=Gtk.Align.CENTER), "nv-encender", "nv-play")
        self.power_img = symbol("media-playback-start-symbolic", 22)
        self.power_btn.add(self.power_img)
        self.power_btn.connect("clicked", lambda *_: self.nv_power_click())
        pill.pack_start(Gtk.Box(), False, False, 4)
        pill.pack_start(logo("php", 18), False, False, 0)
        self.status_lbl = label("…")
        pill.pack_start(self.status_lbl, False, False, 0)
        self.status_sub = label("", "nv-tenue", "nv-mono", "nv-chico")
        pill.pack_start(self.status_sub, False, False, 0)
        pill.pack_start(css(Gtk.Box(), "nv-sep"), False, False, 0)
        self.status_btn = css(Gtk.MenuButton(tooltip_text="Servicios de la versión activa"), "nv-servicios")
        sbox = Gtk.Box(spacing=8)
        self.svc_dots = {}
        for name in ("Apache", "MariaDB"):
            dt = nv_dot(False)
            self.svc_dots[name] = dt
            sbox.pack_start(dt, False, False, 0)
            sbox.pack_start(label(name, "nv-chico"), False, False, 0)
        self.status_btn.add(sbox)
        self.services_pop = Gtk.Popover(relative_to=self.status_btn)
        self.status_btn.set_popover(self.services_pop)
        pill.pack_start(self.status_btn, False, False, 0)
        pill.pack_start(self.power_btn, False, False, 0)
        # Lo que gastan Nexum y sus servicios juntos (al pasar el ratón, cada parte)
        pill.pack_start(css(Gtk.Box(), "nv-sep"), False, False, 0)
        self.usage_lbl = label("CPU — · RAM —", "nv-mono", "nv-chico", "nv-tenue", width_chars=21, xalign=0.5,
                               tooltip_text="Consumo de Nexum y sus servicios")
        pill.pack_start(self.usage_lbl, False, False, 0)
        self.usage = UsageMeter()
        self.nv_usage_tick()
        GLib.timeout_add_seconds(3, self.nv_usage_tick)
        pill.pack_start(Gtk.Box(), False, False, 2)
        self.warn_btn = Gtk.MenuButton(tooltip_text="Avisos", relief=Gtk.ReliefStyle.NONE)
        wb = Gtk.Box(spacing=4)
        wb.pack_start(icon("dialog-warning-symbolic"), False, False, 0)
        self.warn_num = label("0", "nv-aviso-num", valign=Gtk.Align.CENTER)
        wb.pack_start(self.warn_num, False, False, 0)
        self.warn_btn.add(wb)
        # (el boton no se muestra con show_all: lo de dentro, si, o saldria vacio al aparecer)
        wb.show_all()
        pop = Gtk.Popover(relative_to=self.warn_btn)
        sw = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, propagate_natural_height=True,
                                max_content_height=560)
        self.warn_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16, margin=12)
        self.warn_box.set_size_request(560, -1)
        sw.add(self.warn_box)
        sw.show_all()
        pop.add(sw)
        self.warn_btn.set_popover(pop)
        self.warn_btn.set_no_show_all(True)
        # Tarea en segundo plano: una flecha verde que late, con su porcentaje; al pulsarla, su ventana
        self.bg_task = None
        self.task_badge = css(Gtk.Button(valign=Gtk.Align.CENTER), "nv-tarea-fondo")
        tb = Gtk.Box(spacing=5)
        tb.pack_start(css(logo("descarga", 16), "nv-tarea-flecha"), False, False, 0)
        self.task_badge_lbl = label("", "nv-chico", "nv-mono")
        tb.pack_start(self.task_badge_lbl, False, False, 0)
        self.task_badge.add(tb)
        tb.show_all()
        self.task_badge.set_no_show_all(True)
        self.task_badge.connect("clicked", lambda *_: self.bg_task and self.bg_task.to_front())
        # Los avisos, a la izquierda del visor, y el menu, justo a su derecha (antes de Localhost)
        center = Gtk.Box(spacing=10, valign=Gtk.Align.CENTER)
        center.pack_start(self.task_badge, False, False, 0)
        center.pack_start(self.warn_btn, False, False, 0)
        center.pack_start(pill, False, False, 0)
        center.pack_start(self.menu_btn, False, False, 0)
        hb.set_custom_title(center)
        # Terminal: la de abajo de la ventana, que se enseña y se esconde (en lugar de Localhost; phpMyAdmin
        # ya está en la pestaña Bases de datos)
        self.term_btn = Gtk.ToggleButton(relief=Gtk.ReliefStyle.NONE, valign=Gtk.Align.CENTER,
                                         tooltip_text="Mostrar u ocultar la terminal")
        tbox = Gtk.Box(spacing=6)
        tbox.pack_start(icon("utilities-terminal-symbolic", 16), False, False, 0)
        tbox.pack_start(Gtk.Label(label="Terminal"), False, False, 0)
        self.term_btn.add(tbox)
        self.term_btn.connect("toggled", lambda b: self.nv_term_show(b.get_active()))
        hb.pack_end(self.term_btn)
        # Correo de pruebas: la bandeja de Mailpit, plano como Terminal y con los correos sin leer (se
        # pregunta solo con la ventana activa). Con el correo de pruebas apagado no sale
        self.mail_btn = Gtk.Button(relief=Gtk.ReliefStyle.NONE, valign=Gtk.Align.CENTER)
        mbox = Gtk.Box(spacing=6)
        mbox.pack_start(logo("mailpit", 18), False, False, 0)
        mbox.pack_start(Gtk.Label(label="Correo"), False, False, 0)
        self.mail_num = label("0", "nv-correo-num", valign=Gtk.Align.CENTER)
        mbox.pack_start(self.mail_num, False, False, 0)
        mbox.show_all()
        self.mail_num.set_no_show_all(True)
        self.mail_num.hide()
        self.mail_btn.add(mbox)
        self.mail_btn.connect("clicked", lambda *_: self.nv_open_mail())
        self.mail_btn.set_no_show_all(True)
        hb.pack_end(self.mail_btn)
        return hb
