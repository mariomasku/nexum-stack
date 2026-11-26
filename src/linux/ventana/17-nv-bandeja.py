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
        busy_guard(it["power"], self.busy).set_sensitive(bool(d))
        link = (self.projects or {}).get("link") or ""
        it["web"].set_label("Abrir %s" % (link or "web.local"))
        it["web"].set_sensitive(bool(link) and bool(d.get("running")))

    def nv_tray_hide(self):
        """La X de la ventana: con el icono, la esconde (True: no se cierra); sin él, se cierra como siempre."""
        if self.tray is None:
            # (sin el icono, se cierra el programa: con tareas en la cola, antes se pregunta)
            return not self.task_queue_quit()
        self.win.hide()
        return True

    def nv_tray_open(self):
        self.win.present()
        self.update_recheck()
        # (al volver, sus datos al momento: escondida solo se preguntaba lo del menú)
        if not self.busy:
            run_quick(["gui-vuelta"], self.on_round)

    def nv_tray_power(self):
        if not (self.data or {}).get("active"):
            self.nv_tray_open()
        self.nv_power()

    def nv_tray_web(self):
        if self.project_web():
            self.open_uri(self.project_web())

    def nv_tray_quit(self):
        if not self.task_queue_quit():
            return
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

    def nv_autostart_toggle(self, sw, _p):
        """Configuración, Programa: abrir al iniciar sesión (en simulación no se escribe nada)."""
        on = sw.get_active()
        if on == autostart_on():
            return
        if SIMULATE:
            self.toast("[simulación] %s %s" % ("Se escribiría" if on else "Se quitaría", AUTOSTART_FILE))
            return
        err = autostart_set(on, SCRIPT)
        if err:
            message(self.win, "No se ha podido cambiar el inicio de sesión", err, Gtk.MessageType.ERROR)
            sw.handler_block_by_func(self.nv_autostart_toggle)
            sw.set_active(autostart_on())
            sw.handler_unblock_by_func(self.nv_autostart_toggle)
            return
        self.toast("Se abrirá al iniciar sesión" if on else "Ya no se abre al iniciar sesión")

    def nv_exit(self):
        """Al cerrar la última ventana: se sale y, si algo lo retuviera (un bucle, un hilo, una orden que
        no acaba), a los 5 s se corta el proceso. Nunca queda un Nexum en marcha sin ventana."""
        self.quit()

        def watchdog():
            time.sleep(5)
            os._exit(0)
        threading.Thread(target=watchdog, daemon=True).start()

    def auto_check_package(self):
        """Si hay una versión nueva del programa: cada vez que se abre (1.57.51; antes, solo el primer arranque
        del día), al volver a la ventana desde el icono si hace más de UPDATE_RECHECK que se miró y, con ella
        abierta, cada UPDATE_RECHECK_OPEN. Los parches de los componentes, como antes (update_check_due)."""
        if self.data is None or self.busy:
            return True
        self.update_checked = time.time()
        self.check_package(auto=True)
        if self.update_check_due():
            # (y los parches de los componentes, un poco después: sin juntarse con el aviso del programa)
            GLib.timeout_add_seconds(25, self.nv_components_auto)
        return False

    def update_recheck(self):
        """Al volver a mostrar la ventana (o con el reloj): otra búsqueda si hace rato de la última y, si se
        encontró una versión nueva con la ventana escondida, se ofrece ahora."""
        pending = getattr(self, "update_pending", None)
        if pending and self.win.get_visible():
            self.update_pending = None
            GLib.timeout_add_seconds(1, lambda: (self.offer_package(*pending), False)[1])
            return
        if time.time() - getattr(self, "update_checked", 0) >= UPDATE_RECHECK:
            GLib.timeout_add_seconds(2, self.auto_check_package)

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
        # (php_group: lo de la versión, que con el visor arriba (Apariencia) baja a la barra de estado; pill, su
        # recuadro en la barra de arriba con el visor clásico)
        pill = css(Gtk.Box(spacing=8, valign=Gtk.Align.CENTER), "nv-pastilla")
        self.pill = pill
        grp = Gtk.Box(spacing=8, valign=Gtk.Align.CENTER)
        self.php_group = grp
        # ▶ / ■ (a la derecha de los servicios): arrancar o parar la version; sin ninguna activa, ▶
        # despliega las versiones para elegir
        self.power_btn = css(Gtk.Button(valign=Gtk.Align.CENTER), "nv-encender", "nv-play")
        self.power_img = symbol("media-playback-start-symbolic", 22)
        self.power_btn.add(self.power_img)
        self.power_btn.connect("clicked", lambda *_: self.nv_power_click())
        pill.pack_start(Gtk.Box(), False, False, 4)
        pill.pack_start(grp, False, False, 0)
        pill.pack_start(Gtk.Box(), False, False, 2)
        # (la versión activa: al pulsarla, las instaladas para cambiar de versión)
        self.php_btn = css(Gtk.Button(relief=Gtk.ReliefStyle.NONE, valign=Gtk.Align.CENTER,
                                      tooltip_text="Cambiar de versión de PHP"), "nv-version-btn")
        vb = Gtk.Box(spacing=8)
        vb.pack_start(logo("php", 18), False, False, 0)
        self.status_lbl = label("…")
        vb.pack_start(self.status_lbl, False, False, 0)
        self.status_sub = label("", "nv-tenue", "nv-mono", "nv-chico")
        vb.pack_start(self.status_sub, False, False, 0)
        self.php_btn.add(vb)
        self.php_btn.connect("clicked", lambda *_: self.nv_versions_fan())
        grp.pack_start(self.php_btn, False, False, 0)
        grp.pack_start(css(Gtk.Box(), "nv-sep"), False, False, 0)
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
        grp.pack_start(self.status_btn, False, False, 0)
        grp.pack_start(self.power_btn, False, False, 0)
        # Lo que gastan Nexum y sus servicios juntos (al pasar el ratón, cada parte)
        grp.pack_start(css(Gtk.Box(), "nv-sep"), False, False, 0)
        self.usage_lbl = label("CPU — · RAM —", "nv-mono", "nv-chico", "nv-tenue", width_chars=21, xalign=0.5,
                               tooltip_text="Consumo de Nexum y sus servicios")
        grp.pack_start(self.usage_lbl, False, False, 0)
        self.usage = UsageMeter()
        self.nv_usage_tick()
        GLib.timeout_add_seconds(3, self.nv_usage_tick)
        self.warn_btn = css(Gtk.MenuButton(tooltip_text="Avisos", relief=Gtk.ReliefStyle.NONE, valign=Gtk.Align.CENTER),
                            "nv-avisos")
        wb = Gtk.Box(spacing=4)
        wb.pack_start(css(icon("dialog-warning-symbolic"), "nv-aviso-icono"), False, False, 0)
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
        # (en medio, el recuadro de la versión o, con el visor arriba, los botones del proyecto cargado)
        self.center_slot = Gtk.Box(valign=Gtk.Align.CENTER)
        center.pack_start(self.center_slot, False, False, 0)
        center.pack_start(self.menu_btn, False, False, 0)
        hb.set_custom_title(center)
        self.header = hb
        # Visor arriba: el proyecto cargado en web.local y sus botones, cuadrados y con su nombre, y Correo y
        # Terminal igual que ellos. Todo el ancho que deje la barra; si no caben, se desplazan (rueda del ratón)
        # sin ensanchar la ventana. Su alto, el de los botones: sin él, la barra los recortaba por abajo
        self.top_wrap = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.AUTOMATIC,
                                           vscrollbar_policy=Gtk.PolicyType.NEVER, propagate_natural_width=True,
                                           valign=Gtk.Align.CENTER)
        self.top_wrap.set_overlay_scrolling(True)
        self.top_wrap.set_size_request(-1, TOP_VISOR_SIDE + 2)
        self.top_btns = css(Gtk.Box(spacing=4, valign=Gtk.Align.CENTER), "nv-visor-arriba")
        self.top_wrap.add(self.top_btns)
        self.top_wrap.show_all()
        # Terminal: la de abajo de la ventana, que se enseña y se esconde (en lugar de Localhost; phpMyAdmin
        # ya está en la pestaña Bases de datos)
        self.term_btn = Gtk.ToggleButton(relief=Gtk.ReliefStyle.NONE, valign=Gtk.Align.CENTER,
                                         tooltip_text="Mostrar u ocultar la terminal")
        tbox = Gtk.Box(spacing=6)
        tbox.pack_start(icon("utilities-terminal-symbolic", 16), False, False, 0)
        tbox.pack_start(Gtk.Label(label="Terminal"), False, False, 0)
        self.term_btn.add(tbox)
        self.term_btn.connect("toggled", lambda b: self.nv_term_show(b.get_active()))
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
        self.visor_mode = None
        return hb

    def nv_versions_fan(self):
        """Al pulsar la versión de PHP (en la barra de abajo o, con el visor clásico, en el recuadro de arriba): las
        versiones instaladas en un desplegable, abriéndose en abanico (cada una un instante después, desde la barra).
        La activa, marcada; al elegir otra, se cambia como desde Versiones de PHP (on_activate_version)."""
        d = self.data or {}
        installs = sorted(d.get("installs") or [], key=lambda i: ver_tuple(i["php"]), reverse=True)
        if not installs:
            self.toast("No hay ninguna versión de PHP instalada")
            return
        up = getattr(self, "visor_mode", None) == "arriba"
        pop = Gtk.Popover(relative_to=self.php_btn, position=Gtk.PositionType.TOP if up else Gtk.PositionType.BOTTOM)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=6)
        title = label("Cambiar de versión de PHP", "nv-chico", "nv-tenue", margin_start=8, margin_bottom=4, margin_top=2)
        rows = []
        for i in installs:
            here = i["folder"] == d.get("active")
            b = css(Gtk.Button(relief=Gtk.ReliefStyle.NONE), "nv-menuitem")
            row = Gtk.Box(spacing=10)
            row.pack_start(logo("php", 16), False, False, 0)
            row.pack_start(label("PHP %s" % i["php"]), False, False, 0)
            row.pack_start(label("lampp-%s" % i["folder"], "nv-tenue", "nv-mono", "nv-chico"), True, True, 0)
            if here:
                row.pack_end(label("● %s" % ("en marcha" if d.get("running") else "activa"), "nv-chico",
                                   "nv-verde" if d.get("running") else "nv-tenue"), False, False, 0)
            b.add(row)
            if here:
                b.set_tooltip_text("Es la versión activa")
            else:
                busy_guard(b, self.busy)
                b.connect("clicked", lambda _b, f=i["folder"]: (pop.popdown(), self.on_activate_version(None, f)))
            rows.append(b)
        # (el abanico: desde la barra hacia fuera, cada fila un poco después que la anterior)
        order = list(reversed(rows)) if up else rows
        for n, b in enumerate(order):
            css(b, "nv-abanico-arriba" if up else "nv-abanico-abajo", "nv-abanico-%d" % min(n, 11))
        box.pack_start(title, False, False, 0)
        for b in rows:
            box.pack_start(b, False, False, 0)
        pop.add(box)
        box.show_all()
        pop.connect("closed", lambda *_: GLib.idle_add(pop.destroy))
        pop.popup()

    def nv_visor_layout(self):
        """Coloca la barra de arriba como diga Apariencia (visor arriba o clásico). Arriba: los botones del
        proyecto cargado (con Correo y Terminal iguales que ellos) donde iba el recuadro de la versión, y lo de
        la versión, sin recuadro, en la barra de estado. Clásico: como siempre. Mueve los mismos elementos (lo
        que los actualiza no cambia) y rehace el visor de Proyectos."""
        mode = look_conf()["visor"]
        if mode == self.visor_mode:
            return
        self.visor_mode = mode
        for w in (self.php_group, self.mail_btn, self.term_btn, self.pill, self.top_wrap, self.menu_btn, self.warn_btn):
            parent = w.get_parent()
            if parent is not None:
                parent.remove(w)
        top = mode == "arriba"
        self.nv_mail_term_look(top)
        self.services_pop.set_position(Gtk.PositionType.TOP if top else Gtk.PositionType.BOTTOM)
        if top:
            self.center_slot.pack_start(self.top_wrap, False, False, 0)
            self.st_right.pack_start(self.php_group, False, False, 0)
            # (☰, pegado a la derecha, junto a minimizar, maximizar y cerrar: el sitio de en medio, para los botones;
            # los avisos, justo a su izquierda)
            self.header.pack_end(self.menu_btn)
            self.header.pack_end(self.warn_btn)
        else:
            self.pill.pack_start(self.php_group, False, False, 0)
            self.pill.reorder_child(self.php_group, 1)
            self.center_slot.pack_start(self.pill, False, False, 0)
            # (los avisos, justo a la izquierda de ☰)
            self.center_slot.get_parent().pack_start(self.warn_btn, False, False, 0)
            self.center_slot.get_parent().pack_start(self.menu_btn, False, False, 0)
            self.header.pack_end(self.term_btn)
            self.header.pack_end(self.mail_btn)
        self.menu_btn.show_all()
        self.term_btn.show()
        self.php_group.show_all()
        self.pill.show_all()
        self.center_slot.show_all()
        self.st_right.set_visible(top)
        if getattr(self, "nv_list", None) is not None:
            self.nv_build_projects()
        self.nv_top_visor_fill()

    def nv_mail_term_look(self, square, named=True):
        """Correo y Terminal: planos, con el icono y el nombre al lado (clásico) o cuadrados, con el nombre
        debajo, como los botones del visor de arriba. El número de correos sin leer va con ellos."""
        unread = self.mail_num.get_visible()
        for b in (self.mail_btn, self.term_btn):
            old = b.get_child()
            if old is not None:
                if self.mail_num.get_parent() is not None:
                    self.mail_num.get_parent().remove(self.mail_num)
                b.remove(old)
        ctx_m, ctx_t = self.mail_btn.get_style_context(), self.term_btn.get_style_context()
        for b, ctx, ic, name in ((self.mail_btn, ctx_m, logo("mailpit", 18 if not square else TOP_VISOR_ICON), "Correo"),
                                 (self.term_btn, ctx_t, tint_icon(icon("utilities-terminal-symbolic", 16 if not square else TOP_VISOR_ICON),
                                                                  "utilities-terminal-symbolic"), "Terminal")):
            if square:
                box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3, valign=Gtk.Align.CENTER)
                row = Gtk.Box(spacing=3, halign=Gtk.Align.CENTER)
                row.pack_start(ic, False, False, 0)
                if b is self.mail_btn:
                    row.pack_start(self.mail_num, False, False, 0)
                box.pack_start(row, False, False, 0)
                if named:
                    box.pack_start(label(name, "nv-visor-nombre", xalign=0.5, ellipsize=3, max_width_chars=9), False, False, 0)
                b.set_relief(Gtk.ReliefStyle.NORMAL)
                for c in ("nv-proyecto-btn", "nv-boton-cuadrado", "nv-visor-btn"):
                    ctx.add_class(c)
                b.set_size_request(TOP_VISOR_SIDE, TOP_VISOR_SIDE)
            else:
                box = Gtk.Box(spacing=6)
                box.pack_start(ic, False, False, 0)
                box.pack_start(Gtk.Label(label=name), False, False, 0)
                if b is self.mail_btn:
                    box.pack_start(self.mail_num, False, False, 0)
                b.set_relief(Gtk.ReliefStyle.NONE)
                for c in ("nv-proyecto-btn", "nv-boton-cuadrado", "nv-visor-btn"):
                    ctx.remove_class(c)
                b.set_size_request(-1, -1)
            b.add(box)
            for w in box.get_children():
                w.show_all()
            box.show()
        # (el número, solo con correos sin leer: lo enseña o lo esconde nv_mail_poll)
        self.mail_num.set_visible(unread)

    def nv_top_visor_fill(self):
        """Visor arriba: el proyecto cargado y, como en Personalizar los botones (cuáles se ven y en qué orden), sus
        botones, Unlink, Correo y Terminal; ⋮, el último de todos. Sin proyecto cargado, solo Correo y Terminal."""
        if self.visor_mode != "arriba":
            return
        for w in list(self.top_btns.get_children()):
            self.top_btns.remove(w)
            if w not in (self.mail_btn, self.term_btn):
                w.destroy()
        x = self.loaded_project_entry() if self.projects and self.data else None
        # (delante, el proyecto cargado, con el logotipo de su tipo y sin recuadro: al pulsarlo, Proyectos. A dónde
        # apunta web.local ya lo dice la barra de abajo. Su nombre entero, sin cortar y sin el prefijo de su tipo)
        who = Gtk.Button(relief=Gtk.ReliefStyle.NONE, valign=Gtk.Align.CENTER,
                         tooltip_text=x["name"] if x else "Ningún proyecto cargado: elige uno en Proyectos")
        css(who, "nv-visor-proyecto")
        wb = Gtk.Box(spacing=8, valign=Gtk.Align.CENTER)
        brand = project_brand(x["name"], x["kind"]) if x else None
        wb.pack_start(logo(brand, 24) if brand else icon("folder-symbolic", 22), False, False, 0)
        wb.pack_start(label(short_project_name(x["name"]) if x else "Sin proyecto",
                            "nv-visor-cargado" if x else "nv-tenue"), False, False, 0)
        who.add(wb)
        who.connect("clicked", lambda *_: self.show_tab("proyectos"))
        self.top_btns.pack_start(who, False, False, 0)
        self.top_btns.pack_start(css(Gtk.Box(), "nv-sep"), False, False, 4)
        # (siempre cuadrados y del mismo tamaño; con «Solo el icono», sin el nombre)
        own = buttons_conf()
        self.nv_mail_term_look(True, named=own["style"] != "icono")
        conf = dict(own, style="grande", size=TOP_VISOR_SIDE, compacto=True, sin_nombre=own["style"] == "icono")
        btns = self.nv_project_buttons(x)[0] if x is not None else {}
        for key in conf["order"]:
            if key in conf["hidden"]:
                continue
            if key == "correo":
                self.top_btns.pack_start(self.mail_btn, False, False, 0)
            elif key == "terminal":
                self.top_btns.pack_start(self.term_btn, False, False, 0)
            elif key in btns:
                b = btns[key]
                self.nv_restyle(b, conf, ("logo", b.nv_logo) if getattr(b, "nv_logo", None) else visor_spec(key),
                                dict((k, n) for k, n, _i in VISOR_BUTTONS)[key])
                b.get_style_context().add_class("nv-visor-btn")
                self.top_btns.pack_start(b, False, False, 0)
        if x is not None:
            more = self.nv_more_menu(x)
            self.nv_restyle(more, conf, ("icono", "view-more-symbolic"), "Más")
            more.get_style_context().add_class("nv-visor-btn")
            self.top_btns.pack_start(more, False, False, 0)
        for w in self.top_btns.get_children():
            if w is not self.mail_btn:
                w.show_all() if w is not self.term_btn else w.show()
