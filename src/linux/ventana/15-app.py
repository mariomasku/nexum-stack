# ---------------------------------------------------------------- aplicacion

class App(AppPrograma,
          AppServicios,
          AppHosts,
          AppHerramientas,
          AppVersiones,
          AppInstalar,
          AppBasesDatos,
          AppDocker,
          AppSubirBajarBD,
          AppAcerca,
          Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.data = None
        self.branches = None
        self.php_dates = {}
        # Pestaña Docker: datos de gui-docker (None hasta leerlos) y el formulario de proyecto nuevo
        self.docker = None
        self.docker_form = {}
        self.branches_error = None
        self.expanded = set()
        try:
            with open(FOLDED_FILE, encoding="utf-8") as f:
                self.folded = {l.strip() for l in f if l.strip()}
        except OSError:
            self.folded = set()
        self.extra_patches = []
        self.busy = False
        # Formulario «Subir o actualizar una base de datos» (se conserva al redibujar la pestaña)
        self.imp = {"file": None, "db": None, "folder": None, "project": None}
        self.db_pwd = {}
        # Dominios de los vhosts (pestaña Hosts): None hasta leerlos
        self.hosts = None
        # Apache, MariaDB y FTP de la version montada (pestaña Servicios): None hasta leerlos
        self.services = None
        # Proyectos de /opt/htdocs (bloque «Cargar proyecto» de Versiones): None hasta leerlos
        self.projects = None
        # Los repositorios del buscador de Nuevo proyecto (np_repos_load)
        self.np_repos, self.np_repos_when, self.np_repos_busy = None, 0, False
        # Formulario «Nuevo proyecto con dominio falseado» (se conserva al redibujar la pestaña)
        self.newdom = {"domain": "", "folder": "", "db": ""}

    # ventana
    def do_activate(self):
        if getattr(self, "win", None):
            self.win.present()
            return
        # Mano al pasar el ratón por cualquier botón (GTK 3 no tiene cursor en CSS): se pone en la
        # ventana de eventos del botón cada vez que el ratón entra, según esté activo o no
        hand = Gdk.Cursor.new_from_name(Gdk.Display.get_default(), "pointer")

        def pointer_hook(widget, event, *_):
            if isinstance(widget, (Gtk.Button, Gtk.Switch)) and event.window is not None:
                event.window.set_cursor(hand if widget.is_sensitive() else None)
            return True
        GObject.add_emission_hook(Gtk.Widget, "enter-notify-event", pointer_hook)
        prov = Gtk.CssProvider()
        prov.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        theme = Gtk.IconTheme.get_default()
        # El icono es un PNG suelto en ~/.local/share/icons (no de un tema): has_icon no lo ve
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
        self.win.set_default_size(920, 760)

        header = Gtk.HeaderBar(show_close_button=True)
        title = Gtk.Box(spacing=8)
        title.pack_start(icon(self.icon, 24), False, False, 0)
        self.title_lbl = label("Nexum Dev Stack", "title")
        title.pack_start(self.title_lbl, False, False, 0)
        header.set_custom_title(title)
        menu = Gio.Menu()
        sec = Gio.Menu()
        sec.append("Abrir localhost", "app.localhost")
        sec.append("Abrir phpMyAdmin", "app.phpmyadmin")
        sec.append("Editar vhosts", "app.vhosts")
        sec.append("Editar hosts", "app.hosts")
        menu.append_section(None, sec)
        sec = Gio.Menu()
        sec.append("Volver a leer las versiones", "app.refresh")
        # De momento, el .deb de Descargas; mas adelante, un repositorio
        sec.append("Buscar actualizaciones", "app.update")
        sec.append("Abrir el panel en la terminal", "app.terminal")
        sec.append("Carpeta de registros", "app.logs")
        menu.append_section(None, sec)
        sec = Gio.Menu()
        sec.append("Novedades", "app.changes")
        sec.append("Acerca de Nexum Dev Stack", "app.about")
        menu.append_section(None, sec)
        mb = Gtk.MenuButton(menu_model=menu)
        mb.add(icon("open-menu-symbolic"))
        header.pack_end(mb)
        self.win.set_titlebar(header)

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.page_versions, self.ver_box = page()
        # Instalar va dentro de Versiones, debajo de las instaladas
        self.inst_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
        self.page_dbs, self.db_box = page()
        self.page_tools, self.tools_box = page()
        self.page_hosts, self.hosts_box = page()
        self.page_services, self.services_box = page()
        self.page_docker, self.docker_box = page()
        self.stack.add_named(self.page_versions, "versiones")
        self.stack.add_named(self.page_services, "servicios")
        self.stack.add_named(self.page_hosts, "hosts")
        self.stack.add_named(self.page_dbs, "bbdd")
        self.stack.add_named(self.page_tools, "herramientas")
        self.stack.add_named(self.page_docker, "docker")

        main = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        # Apartados en una barra a la izquierda, como Configuración de Ubuntu
        body = Gtk.Box()
        self.tabs_box = self.build_tabs()
        body.pack_start(self.tabs_box, False, False, 0)
        body.pack_start(self.stack, True, True, 0)
        main.pack_start(body, True, True, 0)
        main.pack_start(Gtk.Separator(), False, False, 0)
        self.foot = label("", "dim-label", "firma", xalign=0.5, margin=6)
        main.pack_start(self.foot, False, False, 0)

        overlay = Gtk.Overlay()
        overlay.add(main)
        overlay.add_overlay(self.build_toast())
        self.win.add(overlay)
        for box in (self.ver_box, self.db_box, self.inst_box):
            self.loading(box)
        # Los datos se leen antes de mostrar la ventana (tarda poco) para abrirla ya con el tamaño
        # que necesita la pestaña Bases de datos, sin saltos
        try:
            res = subprocess.run(script_cmd("gui-datos"), stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 env=script_env(), timeout=10)
            self.on_data(res.returncode, res.stdout.decode("utf-8", "replace"))
            self.fit_height()
        except Exception:  # noqa: BLE001 - si falla, se abre con el tamaño por defecto
            pass
        self.win.show_all()
        self.toast_rev.set_reveal_child(False)
        self.reload(branches=True)
        GLib.timeout_add_seconds(20, self.on_tick)
        # El paquete nuevo de Descargas ya no se busca solo al abrir: se instala como root y
        # cualquier web puede dejar un fichero en Descargas. Se busca desde Herramientas
        if os.environ.get("LVM_CAPTURA"):
            GLib.timeout_add(2500, self.capture_all)
