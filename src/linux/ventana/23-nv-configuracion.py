class NvConfiguracion:
    """Títulos de las páginas, Hosts y Configuración por apartados."""

    def nv_page_title(self, box, symbol_name, title, sub, trailing=None):
        """Título grande arriba de una página hecha con los constructores de siempre (como el de las
        demás pestañas). trailing: un botón, a su derecha."""
        head = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        tl = Gtk.Box(spacing=10)
        tl.pack_start(symbol(symbol_name, 26), False, False, 0)
        title_lbl = label(title, "nv-titulo-grande")
        tl.pack_start(title_lbl, False, False, 0)
        head.pack_start(tl, False, False, 0)
        sub_lbl = label(sub, "nv-chico", "nv-tenue", xalign=0, wrap=True)
        head.pack_start(sub_lbl, False, False, 0)
        parts = (tl, title_lbl, sub_lbl)
        if trailing is not None:
            line = Gtk.Box(spacing=12)
            line.pack_start(head, True, True, 0)
            line.pack_end(trailing, False, False, 0)
            head = line
        box.pack_start(head, False, False, 0)
        box.reorder_child(head, 0)
        head.show_all()
        return parts

    def build_hosts(self):
        super().build_hosts()
        # (los desplegables y el dominio, del mismo ancho: caben en los 2/3 de la tarjeta)
        for w in self.nv_walk(self.hosts_box):
            if isinstance(w, Gtk.ComboBox):
                narrow(w, 30)
            elif isinstance(w, Gtk.Entry):
                w.set_width_chars(30)
        view = nv_button("text-x-generic-symbolic", "Ver fichero de hosts",
                         "Ver %s" % (self.data["hosts"] if self.data else "/etc/hosts"),
                         self.on_view_hosts)
        self.nv_page_title(self.hosts_box, "network-workgroup-symbolic", "Dominios y hosts",
                           "Los dominios de los vhosts y los que se llevan a este equipo en /etc/hosts", view)

    def on_hosts_data(self, rc, out):
        old = self.hosts
        res = super().on_hosts_data(rc, out)
        # (el interruptor del proyecto cargado sigue a /etc/hosts; solo su recuadro, no toda la lista)
        if self.hosts != old and getattr(self, "nv_list", None) and self.projects and self.data:
            loaded = self.loaded_project_entry()
            if loaded is not None:
                self.nv_hero(loaded, loaded)
        return res

    def build_tools(self):
        # (antes de vaciar la pestaña: al soltar su tarjeta, GTK destruiría también el visor del correo)
        web = getattr(self, "mail_web", None)
        if web is not None and web.get_parent() is not None:
            web.get_parent().remove(web)
        super().build_tools()
        # Barrera entre webs (nexum barrera-web): encendida si no existe el fichero
        box, lb = tile_group("Seguridad entre webs",
                             "Impide que otra web abierta en tu navegador use tus proyectos locales sin que lo sepas.")
        on = not os.path.exists(os.path.join(LOG_DIR, "sin-barrera-entre-webs"))
        row = ActionRow("Barrera entre webs", "Encendida: tus proyectos solo aceptan lo que llega desde ellos mismos"
                        if on else "Apagada: enciéndela cuando acabes de probar los pagos")
        sw = Gtk.Switch(active=on, valign=Gtk.Align.CENTER, sensitive=not self.busy)
        sw.connect("notify::active", self.on_cross_site)
        row.add_suffix(sw)
        lb.add(row)
        # Qué es, explicado: el problema, lo que hace, cuándo apagarla y dónde vale
        box.pack_start(label("Qué es", "nv-apartado-titulo", xalign=0, margin_top=20), False, False, 0)
        why = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE, margin_top=6), "caja")
        for ic, title, text in CROSS_SITE_HELP:
            r = ActionRow(title, text)
            r.add_prefix(symbol(ic, 18))
            r.subtitle.set_ellipsize(0)
            r.subtitle.set_line_wrap(True)
            r.subtitle.set_xalign(0)
            why.add(r)
        box.pack_start(why, False, False, 0)
        self.tools_box.pack_start(box, False, False, 0)
        self.tools_box.reorder_child(box, 1)
        box.show_all()
        self.nv_components_tools()
        self.nv_tasks_tools()
        self.nv_docker_tools()
        self.nv_tunnel_tools()
        self.nv_mail_tools()
        self.nv_github_tools()
        self.nv_look_tools()
        self.nv_clean_tools()
        self.nv_tools_sections()
        self.tools_title = self.nv_page_title(self.tools_box, "emblem-system-symbolic", "Configuración",
                                              "Elige un apartado en la columna de la izquierda")
        self.nv_tools_title()

    # Apartados de Configuración: su nombre en la columna de la izquierda, su icono y el orden (los que no
    # estén aquí, al final)
    TOOLS_SECTIONS = [("General", "General", "preferences-system-symbolic"),
                      ("Configuración", "Vhosts y hosts", "network-workgroup-symbolic"),
                      ("Seguridad entre webs", "Seguridad entre webs", "security-high-symbolic"),
                      ("Correo de pruebas (Mailpit)", "Correo de pruebas", "mail-unread-symbolic"),
                      ("Docker", "Docker", "logo:docker"),
                      ("Túnel de Cloudflare", "Túnel de Cloudflare", "network-transmit-receive-symbolic"),
                      ("GitHub (Repositorios)", "GitHub", "logo:github"),
                      ("Apariencia", "Apariencia", "preferences-desktop-appearance-symbolic"),
                      ("Limpieza", "Limpieza", "edit-clear-all-symbolic"),
                      ("Carpetas", "Carpetas", "folder-symbolic"),
                      ("XAMPP sin registrar", "XAMPP sin registrar", "drive-harddisk-symbolic"),
                      ("Información", "Información", "help-about-symbolic")]
    # Lo que va junto en General, cada uno en su bloque con su título, en este orden
    GENERAL_PARTS = ["Registro de errores", "Registro de tareas", "Parches nuevos", "Programa"]
    GENERAL_DESC = ("Los registros de errores de la web cargada y de Apache, el de las tareas que lanza la ventana, "
                    "los parches nuevos de lo que usa Nexum y el propio programa")

    def nv_tools_sections(self):
        """Configuración en dos columnas: a la izquierda, los encabezados de sus apartados; a la derecha, lo que
        se puede cambiar del elegido. Los apartados son los de siempre (cada constructor añade el suyo a
        tools_box): aqui se pasan a una hoja cada uno. Los de GENERAL_PARTS van juntos en la de General, cada
        uno con su título y su explicación. El elegido se recuerda al rehacer la pestaña."""
        groups = list(self.tools_box.get_children())
        for g in groups:
            self.tools_box.remove(g)
        order = {t: n for n, (t, _, _) in enumerate(self.TOOLS_SECTIONS)}
        info = {t: (name, ic) for t, name, ic in self.TOOLS_SECTIONS}

        def title_of(g):
            for w in self.nv_walk(g):
                if isinstance(w, Gtk.Label) and w.get_style_context().has_class("grupo-titulo"):
                    return w.get_label()
            return ""
        found = []
        parts = {}
        for n, g in enumerate(groups):
            t = title_of(g) or "Otros"
            if t in self.GENERAL_PARTS and t not in parts:
                parts[t] = g
            else:
                found.append((t, n, g))
        self.tools_parts = parts
        if parts:
            gen = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=30)
            for t in self.GENERAL_PARTS:
                g = parts.get(t)
                if g is None:
                    continue
                # (su explicación, a la vista debajo de su título, en lugar del símbolo de información)
                tlbl = next((w for w in self.nv_walk(g) if isinstance(w, Gtk.Label)
                             and w.get_style_context().has_class("grupo-titulo")), None)
                head = tlbl.get_parent() if tlbl is not None else None
                for c in head.get_children() if head is not None else []:
                    if isinstance(c, Gtk.EventBox) and c.get_tooltip_text():
                        desc = label(c.get_tooltip_text(), "dim-label", "subtitulo", xalign=0, wrap=True)
                        c.set_no_show_all(True)
                        c.hide()
                        g.pack_start(desc, False, False, 0)
                        g.reorder_child(desc, 1)
                        break
                gen.pack_start(g, False, False, 0)
            found.append(("General", -1, gen))
        found.sort(key=lambda x: (order.get(x[0], len(order)), x[1]))
        stack = Gtk.Stack(vhomogeneous=False, hhomogeneous=False, hexpand=True,
                          transition_type=Gtk.StackTransitionType.CROSSFADE, transition_duration=120)
        nav = css(Gtk.ListBox(valign=Gtk.Align.START), "nv-nav", "nv-subnav")
        rows = {}
        self.tools_desc = {"General": self.GENERAL_DESC}
        self.tools_extra = {}
        for title, _n, g in found:
            if title in rows:
                continue
            # (su nombre va en el título grande de arriba: aquí, sin repetirlo; su explicación, debajo de él.
            # General no: cada uno de sus bloques lleva el suyo)
            tlbl = None if title == "General" else next((w for w in self.nv_walk(g) if isinstance(w, Gtk.Label)
                                                         and w.get_style_context().has_class("grupo-titulo")), None)
            if tlbl is not None:
                head = tlbl.get_parent()
                kids = head.get_children()
                extra = []
                for n, c in enumerate(kids):
                    if c is not tlbl and isinstance(c, Gtk.EventBox) and c.get_tooltip_text():
                        self.tools_desc[title] = c.get_tooltip_text()
                    elif n > kids.index(tlbl):
                        # (lo de detrás del título, como el interruptor del correo, va al lado del título grande)
                        extra.append(c)
                    if c not in extra:
                        c.set_no_show_all(True)
                        c.hide()
                for c in extra:
                    head.remove(c)
                    c.set_valign(Gtk.Align.CENTER)
                    c.set_margin_start(14)
                    c.set_no_show_all(False)
                if extra:
                    self.tools_extra[title] = extra
                head.set_no_show_all(True)
                head.hide()
            stack.add_named(g, title)
            name, ic = info.get(title, (title, "emblem-system-symbolic"))
            row = Gtk.ListBoxRow()
            inner = Gtk.Box(spacing=10)
            inner.pack_start(MonoLogo(ic[5:], 16) if ic.startswith("logo:") else symbol(ic, 16), False, False, 0)
            inner.pack_start(label(name, ellipsize=3), True, True, 0)
            row.add(inner)
            row.section = title
            nav.add(row)
            rows[title] = row

        def picked(_lb, row):
            if row is not None:
                self.tools_section = row.section
                stack.set_visible_child_name(row.section)
                self.nv_tools_title()
        nav.connect("row-selected", picked)
        want = getattr(self, "tools_section", None)
        if want not in rows and found:
            want = found[0][0]
        for w in self.tools_side.get_children():
            w.destroy()
        self.tools_side.pack_start(label("CONFIGURACIÓN", "nv-seccion", margin_start=22, margin_top=16, margin_bottom=2),
                                   False, False, 0)
        self.tools_side.pack_start(nav, False, False, 0)
        self.tools_side.show_all()
        self.tools_box.pack_start(stack, True, True, 0)
        self.tools_nav = rows
        stack.show_all()
        if want:
            nav.select_row(rows[want])

    def nv_tools_title(self):
        """El título grande de Configuración: el del apartado abierto (su icono, su nombre y su explicación)."""
        parts = getattr(self, "tools_title", None)
        sec = getattr(self, "tools_section", None)
        if not parts or not sec:
            return
        tl, title_lbl, sub_lbl = parts
        info = {t: (name, ic) for t, name, ic in self.TOOLS_SECTIONS}
        name, ic = info.get(sec, (sec, "emblem-system-symbolic"))
        old = tl.get_children()[0]
        tl.remove(old)
        old.destroy()
        new = MonoLogo(ic[5:], 26) if ic.startswith("logo:") else symbol(ic, 26)
        tl.pack_start(new, False, False, 0)
        tl.reorder_child(new, 0)
        new.show()
        title_lbl.set_label(name)
        sub_lbl.set_label(getattr(self, "tools_desc", {}).get(sec) or "Configuración")
        # (lo que iba al lado del título del apartado: el de antes sale y entra el del abierto)
        for c in tl.get_children()[2:]:
            tl.remove(c)
        for c in getattr(self, "tools_extra", {}).get(sec, []):
            tl.pack_start(c, False, False, 0)
            c.show_all()

    # Limpieza (nexum gui-limpieza y limpiar <clave>...): cada cosa, con su título, qué es, dónde está, para qué
    # servía y qué pasa si se limpia, lo que se hace (en la confirmación) y si va marcada de partida. Nada de
    # esto lo necesita un proyecto para funcionar
    CLEAN_ITEMS = [
        ("descargas", "Caché de descargas",
         "Los paquetes de código de PHP, Apache, MariaDB, phpMyAdmin… que el programa descargó para instalar o "
         "actualizar tus versiones de PHP. Están en %s. Solo sirven para no descargarlos otra vez si repites una "
         "instalación (o si la web de donde salen no responde). Las versiones ya instaladas no los usan: si se "
         "limpia, todo sigue igual y la próxima instalación los vuelve a descargar. No toca ningún proyecto."
         % DL_CACHE_DIR,
         "se vacía %s: la próxima instalación lo vuelve a descargar" % DL_CACHE_DIR, True),
        ("copias", "Copias de seguridad",
         "Las copias que guardó el programa cuando se lo pediste («Guardar antes una copia» al borrar, sustituir "
         "o actualizar una BBDD o una versión) y, si lo tienes encendido, las de los ficheros que cambia por su "
         "cuenta (hosts, vhosts…). Están en ~/nexum-backups. Sirven para volver atrás si algo salió mal. Tus "
         "proyectos y sus BBDD de ahora no las usan y siguen igual, pero lo que había antes ya no se podrá "
         "recuperar: por eso va sin marcar.",
         "se borra todo lo de ~/nexum-backups (la carpeta se queda): ya no se podrá volver atrás con ellas", False),
        ("correo", "Correo de pruebas",
         "Los correos que han mandado tus webs locales (formularios, pedidos, contraseñas olvidadas…) y que "
         "Mailpit ha recogido para que no lleguen a nadie: los de su bandeja, en Configuración, Correo de "
         "pruebas. Solo sirven para ver qué mandaron las webs. Si se limpia, la bandeja se queda vacía y Mailpit "
         "sigue recogiendo los nuevos; las webs no notan nada. Mailpit tiene que estar en marcha (va con la "
         "versión activa).",
         "se vacía la bandeja de Mailpit", False),
        ("registros", "Registros del programa",
         "Lo que el programa ha ido apuntando de sus tareas: las instalaciones y actualizaciones de las versiones "
         "(y lo que dejan las que fallan), el registro de tareas de la ventana, los de los servidores de Node "
         "parados y el de la ventana. Están en ~/.lvm-instalador. Solo sirven para ver qué pasó en una tarea "
         "anterior o buscar por qué falló. Sus ajustes no se tocan, ni lo que esté usando una tarea o un "
         "servidor en marcha: el programa y tus proyectos siguen igual.",
         "se borran los registros de ~/.lvm-instalador (no sus ajustes ni lo que esté usando una tarea o un "
         "servidor de Node en marcha)", True),
        ("registros-versiones", "Registros de las versiones",
         "Lo que apunta cada versión de PHP: Apache (las visitas y los errores, también los de cada web), PHP-FPM, "
         "los errores de PHP y MariaDB. Están en la carpeta logs de cada /opt/lampp-<versión> (el de MariaDB, "
         "con sus datos). Sirven para buscar por qué falla una web (Configuración, General, Registro de "
         "errores). Se vacían, no se borran: Apache, PHP y MariaDB siguen escribiendo en ellos sin pararse. Solo "
         "se pierde lo que decían hasta ahora; las webs y sus BBDD no cambian.",
         "se vacían los registros de Apache, PHP-FPM, PHP y MariaDB de cada versión (siguen en marcha)", True),
        ("caches-proyectos", "Cachés de los proyectos",
         "Las páginas y plantillas que WordPress (wp-content/cache, la de sus plugins de caché) y PrestaShop "
         "(var/cache y las de Smarty) guardan ya preparadas para ir más deprisa, en cada proyecto de %s. Son "
         "solo una copia que se rehace sola: si se limpia, la primera visita a cada página va algo más lenta "
         "mientras se vuelve a crear. Nada más del proyecto se toca: ni sus ficheros, ni sus imágenes, ni su "
         "BBDD." % ("/opt/htdocs" if DEMO else HTDOCS),
         "se vacían las cachés de los proyectos de %s (se rehacen solas)" % ("/opt/htdocs" if DEMO else HTDOCS), True),
        ("temporales", "Temporales",
         "Ficheros y carpetas de trabajo que dejan las tareas del programa cuando se cortan a medias (una "
         "descarga, el volcado de una BBDD que se iba a cargar, la lista de imágenes de una tienda…), en /tmp y "
         "en ~/.lvm-instalador. Ya no sirven para nada. Solo se borra lo que lleva más de un día sin cambiar y "
         "no está usando ningún programa (un MariaDB temporal en marcha, por ejemplo, se deja). No afecta a "
         "ningún proyecto ni a ninguna versión.",
         "se borran los temporales del programa de más de un día que nada usa", True),
        ("sesiones", "Sesiones de PHP",
         "Los ficheros con los que PHP recuerda quién ha entrado en una web local: tu sesión en phpMyAdmin y la "
         "de las webs o plugins que usan las sesiones de PHP (WordPress y PrestaShop guardan la suya en una "
         "cookie: esa no se cierra). Están en la carpeta temp de cada versión y en /tmp. Si se limpian, esas "
         "sesiones se cierran y hay que volver a entrar; las webs, sus ficheros y sus BBDD no cambian. Va sin "
         "marcar para no cerrarte nada sin querer.",
         "se borran las sesiones de PHP: hay que volver a entrar en phpMyAdmin y en lo que las use", False)]

    def nv_clean_tools(self):
        """Configuración, Limpieza: lo que Nexum va dejando con el uso, cada cosa con lo que ocupa y su casilla;
        arriba, el total, y debajo «Limpiar lo marcado…». Se mide por detrás (gui-limpieza): hasta entonces,
        «Midiendo…». Las casillas se recuerdan mientras la ventana está abierta."""
        box, lb = tile_group("Limpieza", "Lo que Nexum va dejando con el uso y se puede borrar para recuperar "
                             "espacio. Ningún proyecto ni ninguna versión de PHP lo necesita para funcionar: cada "
                             "cosa dice qué es y qué pasa si se limpia. Lo que se limpia no se puede recuperar: no se "
                             "hacen copias.")
        total = ActionRow("Lo que se puede limpiar", "Midiendo…")
        total.add_prefix(icon("edit-clear-all-symbolic", 18))
        lb.add(total)
        marks = getattr(self, "clean_marks", None)
        if marks is None:
            marks = self.clean_marks = {k: on for k, _t, _d, _s, on in self.CLEAN_ITEMS}
        sizes = {}
        rows = {}
        btn = css(Gtk.Button(label="Limpiar lo marcado…", halign=Gtk.Align.END, margin_top=12, sensitive=False),
                  "destructive-action")

        def picked():
            return [k for k, *_r in self.CLEAN_ITEMS if marks.get(k) and sizes.get(k, (0, 0))[1] > 0]

        def update():
            keys = picked()
            btn.set_sensitive(bool(keys) and not self.busy)
            if sizes:
                all_b = sum(b for b, n in sizes.values() if n)
                sel = sum(sizes[k][0] for k in keys)
                total.subtitle.set_label("Total: %s · marcado: %s" % (fmt_size(all_b), fmt_size(sel)) if all_b
                                         else "Total: nada que limpiar")

        def toggled(w, key):
            marks[key] = w.get_active()
            update()
        for key, title, desc, _step, _on in self.CLEAN_ITEMS:
            row = ActionRow(title, desc)
            row.subtitle.set_ellipsize(0)
            row.subtitle.set_line_wrap(True)
            row.subtitle.set_xalign(0)
            size = label("…", "dim-label", width_chars=22, xalign=1)
            chk = Gtk.CheckButton(active=marks.get(key, False), valign=Gtk.Align.CENTER, sensitive=False)
            chk.connect("toggled", toggled, key)
            row.add_suffix(size)
            row.add_suffix(chk)
            lb.add(row)
            rows[key] = (size, chk)
        btn.connect("clicked", lambda *_: self.nv_clean_run(dict(sizes), picked()))
        box.pack_start(btn, False, False, 0)
        self.tools_box.pack_start(box, False, False, 0)
        box.show_all()

        def got(rc, out):
            # (si Configuración se ha rehecho mientras tanto, estas filas ya no están en la ventana)
            if total.subtitle.get_toplevel() is not self.win:
                return False
            for f in parse_lines(out):
                if f[0] == "L" and len(f) >= 4 and f[2].isdigit() and f[3].isdigit():
                    sizes[f[1]] = (int(f[2]), int(f[3]))
            for key, (size, chk) in rows.items():
                b, n = sizes.get(key, (0, 0))
                size.set_label("%s · %s" % (fmt_size(b), plural(n, "fichero", "ficheros")) if n else "Vacío")
                chk.set_sensitive(n > 0 and not self.busy)
            if not sizes:
                total.subtitle.set_label("No se ha podido medir: %s" % (out.strip().splitlines() or ["sin respuesta"])[-1])
            update()
            return False
        run_quick(["gui-limpieza"], got)

    def nv_clean_run(self, sizes, keys):
        """«Limpiar lo marcado…»: confirma con lo que se va a hacer, numerado, y el aviso en rojo, y lanza
        limpiar <claves> como tarea; al acabar, se vuelve a medir."""
        if not keys:
            return
        info = {k: (t, step) for k, t, _d, step, _on in self.CLEAN_ITEMS}
        steps = ["%s (%s · %s): %s." % (info[k][0], fmt_size(sizes[k][0]), plural(sizes[k][1], "fichero", "ficheros"),
                                        info[k][1]) for k in keys]
        warn = label("Lo que se limpia no se puede recuperar: no se hacen copias.", "aviso-rojo", wrap=True,
                     max_width_chars=60, xalign=0)
        if not confirm(self.win, "¿Limpiar lo marcado?",
                       "Si algo es del administrador (lo de root), se pide su contraseña.", "Limpiar",
                       destructive=True, extra=warn, steps=steps):
            return
        self.run_task("Limpiando", ["limpiar"] + keys, done_text="Limpieza terminada",
                      on_done=lambda *_: self.build_tools())

    def nv_tools_show(self, section):
        """Abre Configuración en ese apartado (su título, como en TOOLS_SECTIONS). Uno de los bloques de General
        (GENERAL_PARTS): General, con ese bloque arriba."""
        part = section if section in self.GENERAL_PARTS else None
        if part:
            section = "General"
        self.tools_section = section
        self.show_tab("config")
        row = getattr(self, "tools_nav", {}).get(section)
        if row is not None and row.get_parent() is not None:
            row.get_parent().select_row(row)
        if part:
            GLib.timeout_add(120, self.nv_tools_scroll, part)

    def nv_tools_scroll(self, part):
        """Desplaza Configuración hasta ese bloque de General."""
        g = getattr(self, "tools_parts", {}).get(part)
        adj = self.page_tools.get_vadjustment() if hasattr(self.page_tools, "get_vadjustment") else None
        if g is None or adj is None or g.get_toplevel() is not self.win:
            return False
        pos = g.translate_coordinates(self.tools_box, 0, 0)
        if pos is not None:
            adj.set_value(max(0, min(pos[1] - 12, adj.get_upper() - adj.get_page_size())))
        return False

    def nv_tasks_tools(self):
        """Configuración, General, Registro de tareas: las tareas que ha lanzado la ventana (las TASKS_KEEP
        últimas de TASKS_DIR), cada una con su fecha y cómo acabó; al pulsarla, entera."""
        # (en la demostración, la de siempre: la de verdad es la de su carpeta de ejemplo)
        home = os.path.expanduser("~")
        where = "~/.lvm-instalador/tareas" if DEMO else "~" + TASKS_DIR[len(home):] \
            if TASKS_DIR.startswith(home + os.sep) else TASKS_DIR
        box, lb = tile_group("Registro de tareas",
                             "Cada tarea que lanza la ventana (instalar, activar, arrancar, copiar una BBDD, limpiar…) "
                             "guarda aquí su registro entero: la orden de nexum que se ha ejecutado, todo lo que ha "
                             "dicho, lo mismo que en su ventana, y cómo acabó. Se guardan las %d últimas en %s, solo "
                             "para ti; las contraseñas y los tokens no se escriben." % (TASKS_KEEP, where))
        self.tasks_lb = lb
        self.tasks_line = Gtk.Box(spacing=8, halign=Gtk.Align.END, margin_top=6)
        box.pack_start(self.tasks_line, False, False, 0)
        self.tools_box.pack_start(box, False, False, 0)
        self.nv_tasks_fill()
        box.show_all()

    def nv_tasks_fill(self):
        """Las filas del registro de tareas (las 15 más nuevas; «Ver más», de 50 en 50). Se rehacen al acabar
        cada tarea."""
        lb, line = getattr(self, "tasks_lb", None), getattr(self, "tasks_line", None)
        if lb is None or line is None:
            return
        clear(lb)
        clear(line)
        logs = task_logs()
        shown = getattr(self, "tasks_shown", 15)
        marks = {"ok": ("object-select-symbolic", "punto-verde", "Terminada bien"),
                 "error": ("dialog-error-symbolic", "error", "Ha fallado"),
                 "cancel": ("process-stop-symbolic", "dim-label", "Cancelada"),
                 "run": ("media-playback-start-symbolic", "dim-label", "En marcha")}
        if not logs:
            row = ActionRow("Todavía no hay ninguna tarea", "Cada tarea que lances desde la ventana se guarda aquí")
            row.add_prefix(icon("document-open-recent-symbolic", 18))
            lb.add(row)
        for e in logs[:shown]:
            ic, cls, tip = marks[e["state"]]
            row = ActionRow(e["title"], "%s  ·  %s" % (e["when"], e["result"]), activatable=True)
            mark = css(icon(ic, 18), cls)
            mark.set_tooltip_text(tip)
            row.add_prefix(mark)
            row.set_tooltip_text(e["command"])
            row.on_activate = lambda p=e["path"]: self.nv_task_log_show(p)
            b = Gtk.Button(label="Ver", valign=Gtk.Align.CENTER)
            b.connect("clicked", lambda _b, p=e["path"]: self.nv_task_log_show(p))
            row.add_suffix(b)
            lb.add(row)
        if len(logs) > shown:
            more = Gtk.Button(label="Ver más (%d)" % (len(logs) - shown))
            more.connect("clicked", lambda *_: (setattr(self, "tasks_shown", shown + 50), self.nv_tasks_fill()))
            line.pack_start(more, False, False, 0)
        folder = Gtk.Button(label="Abrir la carpeta")
        folder.connect("clicked", lambda *_: (task_log_dir(), self.open_uri(GLib.filename_to_uri(TASKS_DIR))))
        line.pack_start(folder, False, False, 0)
        lb.show_all()
        line.show_all()

    def nv_task_log_show(self, path):
        """Una tarea del registro, entera: su orden y toda su salida, con «Copiar» y «Abrir la carpeta»."""
        got = task_log_read(path)
        if got is None:
            message(self.win, "No se ha podido leer el registro de la tarea", path, Gtk.MessageType.ERROR)
            return
        head, text = got
        dlg = Gtk.Dialog(title=head.get("Tarea", "Tarea"), transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(980, 640)
        hb = dlg.get_header_bar()
        hb.set_subtitle("%s  ·  %s" % (head.get("Fecha", ""), head.get("Resultado", "")))
        copy = Gtk.Button(label="Copiar")

        def on_copy(*_):
            Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(text, -1)
            copy.set_label("Copiado")
            GLib.timeout_add(2000, lambda: copy.set_label("Copiar") and False)
        copy.connect("clicked", on_copy)
        hb.pack_end(copy)
        folder = Gtk.Button(label="Abrir la carpeta")
        folder.connect("clicked", lambda *_: self.open_uri(GLib.filename_to_uri(os.path.dirname(path))))
        hb.pack_end(folder)
        view = css(Gtk.TextView(editable=False, monospace=True, cursor_visible=False, wrap_mode=Gtk.WrapMode.WORD_CHAR,
                                left_margin=14, right_margin=14, top_margin=10, bottom_margin=10), "log", "nv-consola")
        view.get_buffer().set_text(text)
        sw = css(Gtk.ScrolledWindow(vexpand=True), "nv-consola-marco")
        sw.add(view)
        dlg.get_content_area().add(sw)
        dlg.show_all()
        run_dialog(dlg)
        dlg.destroy()

    def nv_components_tools(self):
        """Configuración, Parches nuevos: lo que tiene un parche publicado (cada versión de PHP con su
        Apache, MariaDB, phpMyAdmin…, las imágenes de Docker, Mailpit y cloudflared) y «Actualizar todo»."""
        box, lb = tile_group("Parches nuevos",
                             "Los parches de seguridad de todo lo que usa Nexum: cada versión de PHP (PHP, Apache, "
                             "MariaDB, ProFTPD, Perl y phpMyAdmin, frente a lo último de su rama), las imágenes de "
                             "Docker (las MariaDB comunes, phpMyAdmin y PHP, frente a Docker Hub), Mailpit y "
                             "cloudflared. Se busca al abrir la ventana el primer arranque del día y cada pocos "
                             "arranques. Las versiones de PHP se rehacen (la de ahora sigue funcionando mientras se "
                             "compila); los contenedores de Docker se rehacen en unos segundos, con sus BBDD.")
        row = ActionRow("Componentes", "Buscando parches nuevos…")
        row.add_prefix(icon("software-update-available-symbolic", 18))
        row.wide = True
        lb.add(row)
        self.tools_box.pack_start(box, False, False, 0)
        self.tools_box.reorder_child(box, 1)
        box.show_all()
        cached = getattr(self, "components", None)
        if cached is not None:
            self.nv_components_fill(row, cached)
        else:
            run_quick(["componentes"], lambda rc, out: (self.nv_components_got(out, row), False)[1])

    def nv_components_got(self, out, row=None):
        res = {"items": [], "notes": [], "errors": [], "n": 0}
        for f in parse_lines(out):
            if f[0] == "L" and len(f) >= 5:
                res["items"].append("lampp-%s: %s %s → %s" % (f[1], f[2], f[3], f[4]))
            elif f[0] == "K" and len(f) >= 3:
                res["items"].append("%s (%s): versión nueva en Docker Hub" % (f[1], f[2]))
            elif f[0] == "X" and len(f) >= 4:
                res["items"].append("%s: %s → %s" % (f[1], f[2], f[3]))
            elif f[0] == "E" and len(f) >= 2:
                res["errors"].append(f[1])
            elif f[0] == "S" and len(f) >= 2 and f[1].isdigit():
                res["n"] = int(f[1])
        self.components = res
        self.nv_warn_refresh()
        # (si Configuración se ha rehecho mientras tanto, esa fila ya no está en la ventana)
        if row is not None and row.subtitle.get_toplevel() is self.win:
            self.nv_components_fill(row, res)
        return res

    def nv_components_fill(self, row, res):
        if res["items"]:
            text = "\n".join("• " + i for i in res["items"])
        elif res["errors"]:
            text = "No se ha podido consultar: %s" % ", ".join(res["errors"])
        else:
            text = "Todo al día: no hay parches nuevos."
        if res["items"] and res["errors"]:
            text += "\n(No se ha podido consultar: %s)" % ", ".join(res["errors"])
        row.subtitle.set_label(text)
        for ch in row.suffix.get_children():
            row.suffix.remove(ch)
        b = Gtk.Button(label="Buscar de nuevo", valign=Gtk.Align.CENTER, sensitive=not self.busy)
        b.connect("clicked", lambda *_: (setattr(self, "components", None), self.build_tools()))
        row.add_suffix(b)
        if res["items"]:
            b = css(Gtk.Button(label="Actualizar todo (%d)" % len(res["items"]), valign=Gtk.Align.CENTER,
                               sensitive=not self.busy), "verde")
            b.connect("clicked", lambda *_: self.nv_components_update(res))
            row.add_suffix(b)
        row.suffix.show_all()

    def nv_components_update(self, res, ask=True):
        extra = copy_check(UPDATE_COPY_WARN) if ask else None
        if ask and not confirm(self.win, "¿Actualizar todo?",
                               "Las versiones de PHP se rehacen con lo último de su rama (varios minutos; la de "
                               "ahora sigue funcionando mientras se compila). Los contenedores de Docker en marcha se "
                               "rehacen en unos segundos: sus BBDD y su configuración no cambian.", "Actualizar todo",
                               steps=res["items"], extra=extra):
            return
        self.components = None
        self.run_task("Actualizando los componentes",
                      ["componentes-actualizar"] + (["--copia"] if extra is not None and extra.wanted else []),
                      progress=True,
                      reload_branches=True, done_text="Componentes al día",
                      on_done=lambda *_: self.build_tools())

    def nv_components_auto(self):
        """Al abrir (cuando toca buscar una versión nueva del programa): si algo tiene un parche nuevo,
        se dice y se ofrece actualizarlo todo."""
        def got(_rc, out):
            res = self.nv_components_got(out)
            # (sin preguntar: el aviso de arriba lo dice, y se puede dejar para luego)
            if res["items"] and not updates_ignored(res["items"]):
                self.toast("Hay parches nuevos: míralos en los avisos de arriba")
            return False
        run_quick(["componentes"], got)
        return False

    def nv_warn_refresh(self):
        """Los avisos de arriba: los de las versiones y, si hay parches nuevos que no se han dejado para
        luego, el suyo, el primero."""
        if not hasattr(self, "warn_box"):
            return
        for ch in self.warn_box.get_children():
            if getattr(ch, "nv_updates", False):
                ch.destroy()
        res = getattr(self, "components", None)
        if res and res["items"] and not updates_ignored(res["items"]):
            n = len(res["items"])
            box, lb = group("Hay parches nuevos (%d)" % n, None)
            box.nv_updates = True
            shown = res["items"][:6] + (["…y %d más" % (n - 6)] if n > 6 else [])
            row = ActionRow("Conviene ponerlos: son parches de seguridad",
                            "\n".join("• " + i for i in shown) + "\nLo de ahora sigue funcionando mientras se actualiza "
                            "(se puede seguir en segundo plano). Si no quieres cambiar nada, «Ahora no» lo deja hasta "
                            "que salga otro parche; siguen en Configuración, General, Parches nuevos.")
            row.add_prefix(icon("software-update-available-symbolic", 18))
            # (entero, sin cortar: en el aviso hay sitio)
            for lbl in (row.title, row.subtitle):
                lbl.set_ellipsize(0)
                lbl.set_line_wrap(True)
                lbl.set_max_width_chars(46)
            later = Gtk.Button(label="Ahora no", valign=Gtk.Align.CENTER)
            later.connect("clicked", lambda *_: (self.warn_btn.get_popover().popdown(), updates_ignore(res["items"]),
                                                 self.nv_warn_refresh()))
            row.add_suffix(later)
            go = css(Gtk.Button(label="Actualizar todo", valign=Gtk.Align.CENTER, sensitive=not self.busy), "verde")
            go.connect("clicked", lambda *_: (self.warn_btn.get_popover().popdown(), self.nv_components_update(res)))
            row.add_suffix(go)
            lb.add(row)
            self.warn_box.pack_start(box, False, False, 0)
            self.warn_box.reorder_child(box, 0)
        self.warn_box.show_all()
        n = len(self.warn_box.get_children())
        self.warn_num.set_label(str(n))
        self.warn_btn.set_visible(n > 0)
