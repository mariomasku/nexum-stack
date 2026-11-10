class App2(NvBandeja,
           NvTerminal,
           NvCorreo,
           NvDatosAvisos,
           NvProyectos,
           NvActualizarProyecto,
           NvConfiguracion,
           NvGithub,
           NvBasesDatos,
           NvDocker,
           App):
    def __init__(self):
        super().__init__()

        self.selected_project = None
        self.np_dialog = None
        # Pestaña Docker: vista (cont, img, vol), filtros, proyectos plegados y uso de CPU y memoria
        # (dk_open: el proyecto desplegado, uno como mucho; al entrar en la pestaña, todos plegados)
        self.dk_view, self.dk_query, self.dk_only_up, self.dk_open, self.dk_stats = "cont", "", False, set(), None
        # Pestaña Bases de datos: buscador y «solo la activa» (la activa se ve desplegada al abrir)
        self.db_query, self.db_only_active = "", False
        # Tamaño de cada BBDD: (version duena, base) -> (bytes, cuando se midio)
        self.db_sizes = {}
        # Correo de pruebas: correos sin leer en Mailpit (None: no se sabe) y si se esta preguntando
        self.mail_unread, self.mail_polling = None, False

    # ------------------------------------------------------------------ ventana
    def do_activate(self):
        if getattr(self, "win", None):
            self.win.present()
            return
        hand = Gdk.Cursor.new_from_name(Gdk.Display.get_default(), "pointer")

        def pointer_hook(widget, event, *_):
            if isinstance(widget, (Gtk.Button, Gtk.Switch)) and event.window is not None:
                event.window.set_cursor(hand if widget.is_sensitive() else None)
            return True
        GObject.add_emission_hook(Gtk.Widget, "enter-notify-event", pointer_hook)

        # Los desplegables se abren debajo del boton, como una lista. Sin esto, GTK 3 pone la opcion
        # elegida encima del boton y, con muchas (los proyectos), deja huecos vacios por arriba o abajo
        def combo_hook(widget, *_):
            if isinstance(widget, Gtk.ComboBox) and widget.get_wrap_width() == 0:
                widget.set_wrap_width(1)
            return True
        GObject.add_emission_hook(Gtk.Widget, "realize", combo_hook)
        for text in (CSS, NEW_CSS):
            prov = Gtk.CssProvider()
            prov.load_from_data(text.encode())
            Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), prov,
                                                     Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        theme = Gtk.IconTheme.get_default()
        self.icon = ICON if theme.lookup_icon(ICON, 24, 0) else "utilities-terminal"
        Gtk.Window.set_default_icon_name(self.icon)
        for name, cb in [("localhost", lambda *_: self.open_uri("http://localhost/")),
                         ("phpmyadmin", lambda *_: self.open_uri("http://127.0.0.1/phpmyadmin/")),
                         ("vhosts", self.on_vhosts), ("hosts", self.on_hosts),
                         ("logs", lambda *_: self.open_uri("file://" + LOG_DIR)),
                         ("update", lambda *_: self.check_package(manual=True)),
                         ("terminal", self.on_terminal), ("refresh", self.on_refresh),
                         ("changes", self.on_changes), ("about", self.on_about)]:
            act = Gio.SimpleAction.new(name, None)
            act.connect("activate", cb)
            self.add_action(act)
        self.win = Gtk.ApplicationWindow(application=self, title="Nexum Dev Stack")
        # Sin ninguna ventana del programa, se cierra del todo
        self.connect("window-removed", lambda app, _w: app.get_windows() or self.nv_exit())
        # (con el icono junto al reloj, la X la esconde: se vuelve a abrir o se sale desde él)
        self.win.connect("delete-event", lambda *_: self.nv_tray_hide())
        self.tray, self.tray_items, self.tray_ticks = None, {}, 0
        self.nv_tray_setup()
        self.win.set_default_size(1240, 840)
        self.win.set_titlebar(self.nv_header())
        try:
            with open(THEME_FILE, encoding="utf-8") as f:
                saved = f.read().strip()
        except OSError:
            saved = ""
        if saved in ("claro", "oscuro"):
            self.nv_apply_theme(saved == "oscuro")
        else:
            self.nv_apply_theme(self.nv_is_dark())

        # Cajas que rellenan los constructores de siempre (algunas no se ven: de ellas se sacan los
        # avisos, el asistente de proyecto nuevo e Instalar)
        self.legacy_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.ver_box = self.legacy_box
        self.inst_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
        self.services_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=12)
        self.services_box.set_size_request(520, -1)
        self.services_pop.add(self.services_box)
        self.page_dbs, self.db_box = new_page()
        self.page_tools, self.tools_box = new_page(620)
        # (los apartados de Configuración, en una columna pegada al menú lateral)
        self.tools_side = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL), "nv-subnav-lateral")
        self.tools_side.set_size_request(220, -1)
        self.tools_wrap = Gtk.Box()
        self.tools_wrap.pack_start(self.tools_side, False, False, 0)
        self.tools_wrap.pack_start(self.page_tools, True, True, 0)
        self.page_hosts, self.hosts_box = new_page()
        self.page_docker, self.docker_box = new_page(940)
        # (el visor, fijo arriba: solo la lista de proyectos se desplaza)
        self.page_projects, self.proj_page, self.proj_list_page, self.proj_scroll = new_split_page(940)
        self.page_repos, self.repos_page = new_page(940)
        self.repos, self.repos_all, self.github = None, False, None
        self.page_node, self.node_page = new_page(940)
        self.node_rows = None
        self.page_vers, self.vers_page = new_page(900)
        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        for name, w in [("proyectos", self.page_projects), ("repos", self.page_repos), ("versiones", self.page_vers),
                        ("bbdd", self.page_dbs), ("docker", self.page_docker), ("node", self.page_node),
                        ("dominios", self.page_hosts), ("config", self.tools_wrap)]:
            self.stack.add_named(w, name)
        body = Gtk.Box()
        body.pack_start(self.nv_sidebar(), False, False, 0)
        # (el contenido arriba y, abajo, la terminal: se cambia de alto arrastrando el borde)
        self.term_paned = Gtk.Paned(orientation=Gtk.Orientation.VERTICAL)
        self.term_paned.pack1(self.stack, True, False)
        self.term_paned.pack2(self.nv_term_panel(), False, False)
        body.pack_start(self.term_paned, True, True, 0)
        overlay = Gtk.Overlay()
        overlay.add(body)
        overlay.add_overlay(self.build_toast())
        self.win.add(overlay)
        self.nv_build_projects_shell()
        for box in (self.db_box, self.vers_page):
            self.loading(box)
        self.win.show_all()
        self.toast_rev.set_reveal_child(False)
        self.reload(branches=True)
        GLib.timeout_add_seconds(20, self.on_tick)
        # Los repositorios del buscador de Nuevo proyecto, ya cargados cuando se abra: los de la última
        # vez y, en cuanto la ventana ha cargado lo suyo, los de GitHub
        self.np_repos_load(cache=True)
        GLib.timeout_add_seconds(5, lambda: (self.np_repos_load(), False)[1])
        # Al abrir: si hay una versión nueva del programa (con los datos ya leídos: la versión actual)
        GLib.timeout_add_seconds(6, self.auto_check_package)
        # (los correos sin leer, tambien al volver a la ventana)
        self.win.connect("notify::is-active", lambda w, _p: w.is_active() and self.nv_mail_poll())
        # Capturas de cada página (LVM_CAPTURA=<carpeta>: las del manual, con LVM_DEMO)
        if os.environ.get("LVM_CAPTURA"):
            GLib.timeout_add(6000, self.nv_capture_all)

    def nv_capture_all(self):
        """Una captura de cada página y de cada apartado de Configuración en LVM_CAPTURA (nombre-de-pagina.png),
        y se cierra. Para el manual (ayuda/herramientas/capturas-linux.sh) y para revisar la ventana."""
        steps = [(lambda n=n: self.show_tab(n), "pagina-" + n)
                 for n in ("proyectos", "versiones", "bbdd", "docker", "node", "repos", "dominios") if n in self.tabs]
        for title, _name, _ic in self.TOOLS_SECTIONS:
            slug = re.sub(r"[^a-z0-9]+", "-", title.lower().translate(str.maketrans("áéíóúñ", "aeioun"))).strip("-")
            steps.append((lambda t=title: self.nv_tools_show(t), "config-" + slug))

        def step(i=[0]):  # noqa: B006 (el contador de los pasos, a propósito)
            if i[0] >= len(steps):
                self.nv_exit()
                return False
            fn, shot = steps[i[0]]
            # (sin el fundido al cambiar de página: con la ventana detrás de otras no avanza, y se capturaba la
            # anterior. Antes de cada paso: Configuración rehace los suyos)
            for w in self.nv_walk(self.win):
                if isinstance(w, Gtk.Stack):
                    w.set_transition_type(Gtk.StackTransitionType.NONE)
            fn()
            GLib.timeout_add(1800, lambda: (self.capture(self.win, shot), False)[1])
            i[0] += 1
            return True
        GLib.timeout_add(2500, step)
        return False
