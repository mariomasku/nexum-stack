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
        # Barrera entre webs (lvm-instalador barrera-web): encendida si no existe el fichero
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
        self.nv_docker_tools()
        self.nv_tunnel_tools()
        self.nv_mail_tools()
        self.nv_github_tools()
        self.nv_look_tools()
        self.nv_tools_sections()
        self.tools_title = self.nv_page_title(self.tools_box, "emblem-system-symbolic", "Configuración",
                                              "Elige un apartado en la columna de la izquierda")
        self.nv_tools_title()

    # Apartados de Configuración: su nombre en la columna de la izquierda, su icono y el orden (los que no
    # estén aquí, al final)
    TOOLS_SECTIONS = [("Parches nuevos", "Parches nuevos", "software-update-available-symbolic"),
                      ("Configuración", "Vhosts y hosts", "network-workgroup-symbolic"),
                      ("Seguridad entre webs", "Seguridad entre webs", "security-high-symbolic"),
                      ("Correo de pruebas (Mailpit)", "Correo de pruebas", "mail-unread-symbolic"),
                      ("Docker", "Docker", "logo:docker"),
                      ("Túnel de Cloudflare", "Túnel de Cloudflare", "network-transmit-receive-symbolic"),
                      ("GitHub (Repositorios)", "GitHub", "logo:github"),
                      ("Registro de errores", "Registro de errores", "dialog-warning-symbolic"),
                      ("Apariencia", "Apariencia", "preferences-desktop-appearance-symbolic"),
                      ("Carpetas", "Carpetas", "folder-symbolic"),
                      ("XAMPP sin registrar", "XAMPP sin registrar", "drive-harddisk-symbolic"),
                      ("Programa", "Programa", "system-software-install-symbolic"),
                      ("Información", "Información", "help-about-symbolic")]

    def nv_tools_sections(self):
        """Configuración en dos columnas: a la izquierda, los encabezados de sus apartados; a la derecha, lo que
        se puede cambiar del elegido. Los apartados son los de siempre (cada constructor añade el suyo a
        tools_box): aqui se pasan a una hoja cada uno. El elegido se recuerda al rehacer la pestaña."""
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
        found = sorted(((title_of(g) or "Otros", n, g) for n, g in enumerate(groups)),
                       key=lambda x: (order.get(x[0], len(order)), x[1]))
        stack = Gtk.Stack(vhomogeneous=False, hhomogeneous=False, hexpand=True,
                          transition_type=Gtk.StackTransitionType.CROSSFADE, transition_duration=120)
        nav = css(Gtk.ListBox(valign=Gtk.Align.START), "nv-nav", "nv-subnav")
        rows = {}
        self.tools_desc = {}
        self.tools_extra = {}
        for title, _n, g in found:
            if title in rows:
                continue
            # (su nombre va en el título grande de arriba: aquí, sin repetirlo; su explicación, debajo de él)
            tlbl = next((w for w in self.nv_walk(g) if isinstance(w, Gtk.Label)
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

    def nv_tools_show(self, section):
        """Abre Configuración en ese apartado (su título, como en TOOLS_SECTIONS)."""
        self.tools_section = section
        self.show_tab("config")
        row = getattr(self, "tools_nav", {}).get(section)
        if row is not None and row.get_parent() is not None:
            row.get_parent().select_row(row)

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
                            "que salga otro parche; siguen en Configuración, Parches nuevos.")
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
