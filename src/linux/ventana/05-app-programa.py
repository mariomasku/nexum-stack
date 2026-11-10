class AppPrograma:
    """Buscar e instalar una versión nueva del programa (el paquete .deb)."""

    # ------------------------------------------- paquete .deb nuevo en Descargas
    def check_package(self, manual=False, auto=False):
        """Buscar una versión nueva (menú) o, con auto, al abrir la ventana (update_check_due): sin
        avisar si no hay."""
        def got(_rc, out):
            found, notes = False, []
            for f in parse_lines(out):
                if f[0] == "N" and len(f) >= 5:
                    found = True
                    # (si se dice que no, se vuelve a ofrecer la próxima vez que toque buscar)
                    self.offer_package(f[1], f[2], f[3], "|".join(f[4:]))
                elif f[0] == "I" and len(f) >= 2:
                    notes.append("|".join(f[1:]))
            if manual and not found:
                if notes:
                    message(self.win, "No hay ninguna versión nueva para instalar desde aquí",
                            "Tienes la %s.\n\n%s" % (self.data["version"], "\n\n".join(notes)))
                else:
                    self.toast("Tienes la última versión (%s)" % self.data["version"])
            return False
        if not auto:
            self.toast("Buscando actualizaciones…")
        run_quick(["gui-paquete"], got)
        return False

    def offer_package(self, version, when, sha, path):
        current = (self.data or {}).get("version", "")
        if os.path.dirname(path) == os.path.join(LOG_DIR, "actualizaciones"):
            where = "GitHub, publicada el %s" % when
        else:
            where = "%s (%s, del %s)" % (os.path.dirname(path), os.path.basename(path), when)
        if not confirm(self.win, "Hay una versión nueva de Nexum Dev Stack",
                       "De la %s a la %s (%s), firmada. Pide la contraseña de administrador y la ventana "
                       "se vuelve a abrir. Tus versiones, proyectos y BBDD no se tocan.\n\nHuella SHA-256:\n%s"
                       % (current, version, where, sha),
                       "Actualizar a la %s" % version):
            return False
        if SIMULATE:
            self.toast("[simulación] pkexec apt-get install -y %s" % path)
            return True

        dlg = Gtk.Dialog(title="Actualizando", transient_for=self.win, modal=True, deletable=False)
        box = Gtk.Box(spacing=12, margin=24)
        box.pack_start(Gtk.Spinner(active=True), False, False, 0)
        box.pack_start(label("Instalando la versión %s…" % version), False, False, 0)
        dlg.get_content_area().add(box)
        dlg.show_all()

        def done(rc, out):
            dlg.destroy()
            if rc == 0:
                # La version nueva esta en /opt/nexum: se abre su ventana cuando se
                # cierre esta (misma aplicacion: si siguiera abierta, solo se traeria al frente)
                subprocess.Popen(["sh", "-c", 'sleep 1; exec "$0" ventana',
                                  "/opt/nexum/nexum.sh"], start_new_session=True,
                                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)
                self.quit()
            elif rc in (126, 127):
                self.toast("Actualización cancelada")
            elif "instalalo en la terminal" in out:
                self.terminal_install(version, path)
            else:
                message(self.win, "No se ha podido actualizar", out[-1200:], Gtk.MessageType.ERROR)
            return False

        def work():
            try:
                # La contraseña se pide con el mensaje en español de la accion de polkit del
                # paquete (io.github.mariomasku.nexum.policy)
                # El ayudante (de root) copia el paquete a su carpeta y comprueba allí la huella que
                # se ha mostrado, su contenido y sus scripts. Sin él no se instala nada desde aquí
                helper = "/opt/nexum/nexum-actualizar"
                cmd = ["pkexec", helper, path, sha]
                res = subprocess.run(cmd,
                                     stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT)
                rc, out = res.returncode, res.stdout.decode("utf-8", "replace")
            except OSError as exc:
                rc, out = 1, str(exc)
            GLib.idle_add(done, rc, out)
        threading.Thread(target=work, daemon=True).start()
        return True

    def terminal_install(self, version, path):
        """La versión nueva cambia el ayudante de actualización (o su acción de polkit): el ayudante
        instalado no la acepta, a propósito, y hay que instalarla una vez en la terminal. Se explica
        y se da la orden lista para copiar (sin el «Tubería rota» de dpkg-deb, que solo confunde)."""
        cmd = "sudo apt install %s" % shlex.quote(path)
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True, message_type=Gtk.MessageType.INFO,
                                buttons=Gtk.ButtonsType.NONE,
                                text="La versión %s se instala una vez en la terminal" % version)
        dlg.format_secondary_text(
            "Esta versión cambia el programa que instala las actualizaciones, y el que tienes no "
            "puede dar por buena su propia sustitución. No es un error ni un paquete dañado.\n\n"
            "Abre una terminal (Ctrl+Alt+T), pega esta orden y escribe tu contraseña:\n\n%s\n\n"
            "Después, abre de nuevo Nexum Dev Stack. Las siguientes versiones se vuelven a "
            "actualizar desde aquí." % cmd)
        dlg.add_button("Copiar la orden", 1)
        dlg.add_button("Cerrar", Gtk.ResponseType.CLOSE)
        widen(dlg)
        if run_dialog(dlg) == 1:
            Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(cmd, -1)
            self.toast("Orden copiada: pégala en la terminal")
        dlg.destroy()

    def fit_height(self):
        """Alto inicial para que la pestaña Bases de datos se vea entera sin agrandar la ventana
        (sin pasar del alto de la pantalla)."""
        self.db_box.show_all()
        width = max(self.db_box.get_preferred_width()[1], 580)
        need = self.db_box.get_preferred_height_for_width(width)[1]
        self.foot.show_all()
        need += self.foot.get_preferred_height()[1]
        need += 1 + 24  # separador y un margen por si crece (aviso…)
        try:
            mon = Gdk.Display.get_default().get_primary_monitor() or \
                Gdk.Display.get_default().get_monitor(0)
            limit = mon.get_workarea().height - 90  # barra de título y bordes
        except Exception:  # noqa: BLE001
            limit = 1000
        height = max(760, min(need, limit))
        self.win.set_default_size(1000, height)
        return height

    def build_tabs(self):
        """Barra lateral con los apartados (como Configuración de Ubuntu)."""
        box = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL), "lateral")
        box.set_size_request(210, -1)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE, margin_top=10),
                 "barra-lateral")
        self.tabs = {}
        # Orden: lo que mas se usa primero (cambiar de version y cargar bases de datos)
        for name, text, ic in [("versiones", "Versiones", "view-list-symbolic"),
                               ("bbdd", "BBDD", "drive-multidisk-symbolic"),
                               ("servicios", "Servicios", "network-server-symbolic"),
                               ("hosts", "Hosts", "network-workgroup-symbolic"),
                               ("docker", "Docker", "logo:docker"),
                               # Lo que se usa de vez en cuando
                               ("herramientas", "Herramientas", "applications-utilities-symbolic")]:
            row = Gtk.ListBoxRow()
            inner = Gtk.Box(spacing=12)
            # (Docker con su logotipo, de un color como los demás iconos del tema)
            inner.pack_start(MonoLogo(ic[5:], 16) if ic.startswith("logo:") else symbol(ic, 16),
                             False, False, 0)
            inner.pack_start(label(text), False, False, 0)
            row.add(inner)
            row.tab_name = name
            lb.add(row)
            self.tabs[name] = row
        lb.connect("row-selected", self.on_tab)
        lb.select_row(self.tabs["versiones"])
        self.tabs_list = lb
        box.pack_start(lb, False, False, 0)
        return box

    def on_tab(self, _lb, row):
        if row is not None:
            self.stack.set_visible_child_name(row.tab_name)
            if row.tab_name == "docker":
                run_quick(["gui-docker"], self.on_docker_data)

    def show_tab(self, name):
        self.tabs_list.select_row(self.tabs[name])

    def build_toast(self):
        self.toast_rev = Gtk.Revealer(halign=Gtk.Align.CENTER, valign=Gtk.Align.END,
                                      margin_bottom=48)
        box = css(Gtk.Box(spacing=12), "app-notification")
        self.toast_lbl = Gtk.Label()
        box.pack_start(self.toast_lbl, False, False, 0)
        self.toast_rev.add(box)
        self.toast_timer = None
        return self.toast_rev

    def toast(self, text):
        self.toast_lbl.set_label(text)
        self.toast_rev.set_reveal_child(True)
        if self.toast_timer:
            GLib.source_remove(self.toast_timer)
        self.toast_timer = GLib.timeout_add_seconds(4, self.hide_toast)

    def hide_toast(self):
        self.toast_rev.set_reveal_child(False)
        self.toast_timer = None
        return False

    def loading(self, box, text="Leyendo…"):
        clear(box)
        spin = Gtk.Box(spacing=10, halign=Gtk.Align.CENTER, margin_top=40)
        spin.pack_start(Gtk.Spinner(active=True), False, False, 0)
        spin.pack_start(label(text, "dim-label"), False, False, 0)
        box.pack_start(spin, False, False, 0)
        box.show_all()

    def open_text(self, path):
        """Abre un fichero de texto con el editor de textos, aunque no tenga extensión (error_log,
        hosts): el programa por defecto según su contenido podría ser otro."""
        app = Gio.AppInfo.get_default_for_type("text/plain", False)
        if app is None:
            self.open_uri(GLib.filename_to_uri(path))
            return
        try:
            app.launch([Gio.File.new_for_path(path)], None)
        except GLib.Error as exc:
            message(self.win, "No se ha podido abrir %s" % path, exc.message, Gtk.MessageType.ERROR)

    def loaded_project_folder(self):
        """Carpeta del proyecto cargado (a la que apunta el enlace del vhost), solo si es una
        carpeta de htdocs."""
        p = self.projects
        if not p or not p.get("current"):
            return None
        cur = p["current"]
        real = os.path.realpath(cur if os.path.isabs(cur) else os.path.join(HTDOCS, cur))
        if os.path.dirname(real) != os.path.realpath(HTDOCS) or not os.path.isdir(real):
            return None
        return real

    def loaded_project_entry(self):
        """Datos (de gui-proyectos) del proyecto cargado, o None."""
        folder = self.loaded_project_folder()
        if folder is None:
            return None
        name = os.path.basename(folder)
        return next((x for x in self.projects["list"] if x["name"] == name), None)

    def loaded_project_db(self):
        """BBDD del proyecto cargado en la versión activa (la vinculada o la de su configuración),
        o vacío."""
        x = self.loaded_project_entry()
        db = ""
        if x and self.data:
            pairs = self.project_pairs(x)
            db = next((d for i, d in pairs if i["folder"] == self.data.get("active")), None) or \
                (pairs[0][1] if pairs else self.project_base(x))
        return db if re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_-]{0,63}", db or "") else ""

    def loaded_project_admin(self):
        """(tipo, carpeta del panel) del proyecto cargado (project_admin)."""
        folder = self.loaded_project_folder()
        return project_admin(folder) if folder is not None else ("", "")

    def open_project_pma(self):
        """phpMyAdmin con la BBDD del proyecto cargado (en http://127.0.0.1/phpmyadmin/)."""
        db = self.loaded_project_db()
        if not db:
            return
        act = next((i for i in self.installs() if i["folder"] == self.data.get("active")), None)
        # (phpMyAdmin 4 usa db= sin route)
        if act and act.get("pma", "").startswith("4."):
            self.open_uri("http://127.0.0.1/phpmyadmin/index.php?db=%s" % db)
        else:
            self.open_uri("http://127.0.0.1/phpmyadmin/index.php?route=/database/structure&db=%s" % db)

    def open_project_admin(self):
        """Panel de administración del proyecto cargado, por el vhost (web.local). Antes deja al día
        su administrador de pruebas (usuario-pruebas) y abre una página con el usuario y la
        contraseña ya escritos: basta con pulsar Entrar. Si no se puede, el panel como siempre."""
        kind, admin = self.loaded_project_admin()
        if not (admin and self.projects and self.projects["link"]):
            return
        db, folder = self.loaded_project_db(), self.loaded_project_folder()
        self.open_admin_login(kind, admin, "http://%s" % self.projects["link"], os.path.basename(folder or ""),
                              ["usuario-pruebas", db, os.path.basename(folder or "")] if db else None)

    def open_admin_login(self, kind, admin, site, name, cmd):
        """Panel (wp-admin o el de la tienda) de la web <site> (http://web.local, https://x.docker.local)
        con el administrador de pruebas: cmd lo deja al día (usuario-pruebas o docker-usuario-pruebas,
        que dicen A|tipo|usuario|contraseña) y se abre una página con el usuario y la contraseña ya
        escritos. Sin cmd, o si no sale, el panel como siempre."""
        base = "%s/%s/" % (site, admin)
        if not cmd or SIMULATE:
            self.open_uri(base)
            return

        def done(rc, out):
            mine = [l.split("|") for l in out.splitlines() if l.startswith("A|%s|" % kind)]
            if rc != 0 or not mine or len(mine[0]) < 4:
                self.open_uri(base)
                return False
            user, password = mine[0][2], mine[0][3]
            if kind == "wp":
                action = "%s/wp-login.php" % site
                fields = [("log", user, "Usuario o correo"), ("pwd", password, "Contraseña"),
                          ("rememberme", "forever", None), ("redirect_to", base, None)]
                title = "Panel de WordPress"
            else:
                action = base + "index.php?controller=AdminLogin"
                fields = [("email", user, "Correo"), ("passwd", password, "Contraseña"),
                          ("stay_logged_in", "1", None), ("submitLogin", "1", None),
                          ("redirect", "AdminDashboard", None)]
                title = "Back office de PrestaShop"
            url = serve_once(login_page(title, name, action, fields, base))
            self.open_uri(url) if url else self.open_uri(base)
            return False
        run_quick(cmd, done)

    def open_in_vscode(self, folder=None):
        """Abre el proyecto cargado (u otra carpeta de htdocs) en Visual Studio Code. Si ya tiene una
        ventana con esa carpeta, VS Code la trae delante en lugar de abrir otra."""
        folder, app = folder or self.loaded_project_folder(), vscode_app()
        if folder is None:
            message(self.win, "No se encuentra la carpeta del proyecto cargado",
                    "El enlace del vhost no apunta a una carpeta de %s." % HTDOCS, Gtk.MessageType.WARNING)
            return
        if app is None:
            message(self.win, "Visual Studio Code no está instalado",
                    "Instálalo desde code.visualstudio.com o desde el Centro de aplicaciones.",
                    Gtk.MessageType.WARNING)
            return
        try:
            # (con el contexto de la ventana, el escritorio deja que VS Code se ponga delante)
            ctx = self.win.get_display().get_app_launch_context()
            ctx.set_timestamp(Gtk.get_current_event_time())
            app.launch([Gio.File.new_for_path(folder)], ctx)
        except GLib.Error as exc:
            message(self.win, "No se ha podido abrir Visual Studio Code", exc.message, Gtk.MessageType.ERROR)

    def open_uri(self, uri):
        try:
            Gtk.show_uri_on_window(self.win, uri, Gdk.CURRENT_TIME)
        except GLib.Error as exc:
            message(self.win, "No se ha podido abrir %s" % uri, exc.message,
                    Gtk.MessageType.ERROR)

    def on_terminal(self, *_):
        for cmd in (["gnome-terminal", "--geometry=100x32", "--", SCRIPT],
                    ["x-terminal-emulator", "-e", SCRIPT]):
            try:
                subprocess.Popen(cmd, start_new_session=True)
                return
            except OSError:
                continue
        message(self.win, "No se ha encontrado ninguna terminal",
                "Abre una terminal y escribe: nexum")

    # datos
    def reload(self, branches=False):
        run_quick(["gui-datos"], self.on_data)
        run_quick(["gui-hosts"], self.on_hosts_data)
        run_quick(["gui-servicios"], self.on_services_data)
        run_quick(["gui-proyectos"], self.on_projects_data)
        if branches:
            self.branches = None
            self.branches_error = None
            self.loading(self.inst_box, "Consultando las versiones de PHP en php.net…")
            run_quick(["gui-ramas"], self.on_branches)
        run_quick(["gui-fechas"], self.on_php_dates)
        run_quick(["gui-docker"], self.on_docker_data)

    def on_php_dates(self, rc, out):
        """Fecha de publicación del PHP de cada versión instalada (de php.net: llega después)."""
        dates = {f[1]: (f[2], f[3]) for f in parse_lines(out) if f[0] == "F" and len(f) >= 4}
        if dates and dates != self.php_dates:
            self.php_dates = dates
            if self.data:
                self.build_versions()
        return False

    def on_refresh(self, *_):
        self.reload(branches=True)

    def on_tick(self):
        if not self.busy and self.win.is_active():
            # (las cuatro en una sola orden: el script se lee una vez y no cuatro)
            run_quick(["gui-vuelta"], self.on_round)
            # (Docker solo mientras se ve su pestaña: pregunta a su servicio)
            if self.stack.get_visible_child_name() == "docker":
                run_quick(["gui-docker"], self.on_docker_data)
        return True

    def on_round(self, rc, out):
        """gui-vuelta: cada parte («@@<orden>|<código>» y sus líneas) a lo de siempre."""
        handlers = {"gui-datos": self.on_data, "gui-hosts": self.on_hosts_data,
                    "gui-servicios": self.on_services_data, "gui-proyectos": self.on_projects_data}
        parts, name, code = {}, None, 0
        for line in out.splitlines():
            m = re.fullmatch(r"@@(gui-[a-z]+)\|(\d+)", line)
            if m and m.group(1) in handlers:
                name, code = m.group(1), int(m.group(2))
                parts[name] = [code, []]
            elif name:
                parts[name][1].append(line)
        # (sin ninguna parte, algo ha ido mal antes de empezar: la siguiente vuelta)
        for name, fn in handlers.items():
            if name in parts:
                fn(parts[name][0], "\n".join(parts[name][1]) + "\n")
        return False

    def on_data(self, rc, out):
        d = {"installs": [], "dbs": {}, "dbdate": {}, "active": "", "running": False,
             "unregistered": False, "native": True, "launcher": True,
             "name": "Nexum Dev Stack", "version": "", "signature": "",
             "vhosts": "/opt/lampp/etc/extra/httpd-vhosts.conf", "hosts": "/etc/hosts",
             "stray": "", "orphans": [], "exposed": "", "unsecured": [], "certs": [], "cas": [], "untrusted": [], "stale": [],
             "dbsys": None, "php2shell": {},
             "mail": {"installed": False, "on": True, "wp": "mailpit", "running": False, "version": "",
                      "url": "http://127.0.0.1:8025/", "offer": ""}}
        for f in parse_lines(out):
            if f[0] == "M" and len(f) >= 4:
                d["name"], d["version"], d["signature"] = f[1], f[2], f[3]
            elif f[0] == "A" and len(f) >= 6:
                d["active"], d["running"] = f[1], f[2] == "1"
                d["unregistered"], d["native"], d["launcher"] = \
                    f[3] == "1", f[4] == "1", f[5] == "1"
            elif f[0] == "V" and len(f) >= 11:
                d["installs"].append({
                    "folder": f[1], "php": f[2], "apache": f[3], "mariadb": f[4], "ftp": f[5],
                    "perl": f[6], "pma": f[7], "kind": f[8], "owner": f[9],
                    "blocker": "|".join(f[10:]).strip()})
            elif f[0] == "D" and len(f) >= 3:
                d["dbs"].setdefault(f[1], []).append(f[2])
                if len(f) >= 5 and f[3].isdigit():
                    d["dbdate"][(f[1], f[2])] = (int(f[3]), f[4])
            elif f[0] == "H" and len(f) >= 3:
                d["vhosts"], d["hosts"] = f[1], f[2]
            elif f[0] == "Z" and len(f) >= 2:
                d["stray"] = "|".join(f[1:])
            elif f[0] == "W" and len(f) >= 3:
                # (vhosts de proyectos cuya carpeta ya no está en htdocs)
                d["orphans"].append((f[1], f[2]))
            elif f[0] == "N" and len(f) >= 2:
                d["exposed"] = "|".join(f[1:])
            elif f[0] == "U" and len(f) >= 2:
                d["unsecured"] = f[1].split()
            elif f[0] == "Y" and len(f) >= 3:
                d["dbsys"] = (f[1], int(f[2]) if f[2].isdigit() else 0)
            elif f[0] == "C" and len(f) >= 3:
                d["certs"].append((f[1], f[2]))
            elif f[0] == "W" and len(f) >= 2:
                d["cas"].append("|".join(f[1:]))
            elif f[0] == "G" and len(f) >= 2:
                d["untrusted"].append(f[1])
            elif f[0] == "Q" and len(f) >= 2:
                d["stale"].append(f[1])
            elif f[0] == "E" and len(f) >= 8:
                # Correo de pruebas: Mailpit instalado, encendido, modo de WordPress, en marcha...
                d["mail"] = {"installed": f[1] == "1", "on": f[2] == "1", "wp": f[3], "running": f[4] == "1",
                             "version": f[5], "url": f[6] if f[6].startswith("http://127.0.0.1:") else
                             "http://127.0.0.1:8025/", "offer": f[7]}
            elif f[0] == "R" and len(f) >= 3:
                # PHP2Shell en cada version: ok, parche (7.4.33... con el arreglo) o vulnerable
                d["php2shell"][f[1]] = (f[2], "|".join(f[3:]))
        if rc != 0 and not d["installs"]:
            message(self.win, "No se han podido leer las versiones instaladas", out[-600:],
                    Gtk.MessageType.ERROR)
        if d == self.data:
            return False
        old_active = (self.data or {}).get("active")
        self.data = d
        # (Dominios y hosts: su campo BBDD es el de la versión activa; si cambia, o si la página se hizo antes de
        # tener las versiones, se rehace aunque sus dominios sigan igual)
        if getattr(self, "hosts", None) is not None and old_active != d["active"]:
            self.build_hosts()
        # (solo la versión: la firma está en Acerca de, en el menú)
        # (la versión va arriba, detrás de «Entornos LAMPP y Docker»; abajo solo el aviso de la simulación)
        self.foot.set_label("SIMULACIÓN: no se cambia nada" if SIMULATE and not DEMO else "")
        if getattr(self, "brand_sub", None) is not None:
            self.brand_sub.set_label("Entornos LAMPP y Docker  ·  v%s" % d["version"] if d["version"]
                                     else "Entornos LAMPP y Docker")
        self.build_versions()
        self.build_databases()
        self.build_services()
        self.build_tools()
        if self.branches is not None:
            self.build_install()
        return False

    def on_branches(self, rc, out):
        rows = parse_lines(out)
        err = [f for f in rows if f[0] == "ERROR"]
        self.branches = [f for f in rows if f[0] in ("B", "X")]
        self.branches_error = err[0][1] if err or rc != 0 else None
        if self.branches_error and not err:
            self.branches_error = out.strip()[-400:] or "Error al consultar las versiones"
        self.build_install()
        return False

    def installs(self):
        return self.data["installs"] if self.data else []
