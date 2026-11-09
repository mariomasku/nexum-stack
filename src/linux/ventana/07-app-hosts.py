class AppHosts:
    """Dominios y hosts del sistema."""

    # -------------------------------------------------------------- hosts
    def on_hosts_data(self, _rc, out):
        rows = [{"name": f[1], "alias": f[2], "folder": f[3], "fake": f[4] == "1",
                 "https": f[5] == "1", "crt": f[6] == "1", "ps": f[7] == "1",
                 "custom": len(f) >= 9 and f[8] == "1", "media": f[9] if len(f) >= 10 else ""}
                for f in parse_lines(out) if f[0] == "F" and len(f) >= 8]
        # El vhost de los proyectos (web.local) que no lleva a 127.0.0.1: (nombre, dirección de ahora)
        link_fix = [(f[1], f[2]) for f in parse_lines(out) if f[0] == "L" and len(f) >= 3]
        if rows != self.hosts or link_fix != getattr(self, "hosts_link_fix", None):
            self.hosts = rows
            self.hosts_link_fix = link_fix
            self.build_hosts()
        return False

    def build_hosts(self):
        """Dominios de los vhosts y si están falseados en /etc/hosts (llevan a este equipo). Al
        cargar una tienda PrestaShop se falsea su dominio y el resto vuelve a la web real."""
        clear(self.hosts_box)
        if self.hosts is None:
            self.loading(self.hosts_box)
            return
        # Un .local siempre esta en /etc/hosts (sin su linea se preguntaria a la red) y no hay ninguna
        # web real a la que devolverlo: no es un dominio falseado, va con los demas (sin apagarse)
        fake = [h for h in self.hosts if h["fake"] and not h["name"].lower().endswith(".local")]
        rest = [h for h in self.hosts if h not in fake]

        # Primero, si el vhost de los proyectos no lleva a este equipo: el navegador no conecta
        for name, now in getattr(self, "hosts_link_fix", []):
            box, lb = group("%s no lleva a este equipo" % name,
                            "Apache solo escucha en 127.0.0.1 y en /etc/hosts %s. El navegador da "
                            "«No se puede acceder a este sitio web» (ERR_CONNECTION_REFUSED). "
                            "Arreglarlo hace que %s lleve a 127.0.0.1 (una sola vez; la copia del "
                            "/etc/hosts anterior queda en ~/lvm-copias). Pide la contraseña de sudo."
                            % (("apunta a %s" % now) if now else "no está", name))
            row = ActionRow("%s → %s" % (name, now or "sin línea en /etc/hosts"),
                            "Tiene que ir a 127.0.0.1, donde escucha Apache")
            b = css(Gtk.Button(label="Arreglarlo"), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Arreglando /etc/hosts", ["hosts-enlace"],
                done_text="web.local ya lleva a este equipo", auto_close=True))
            row.add_suffix(b)
            lb.add(row)
            self.hosts_box.pack_start(box, False, False, 0)

        box, lb = group("Host falseado",
                        "Al cargar una tienda PrestaShop se crea lo que le falte (su vhost y su "
                        "certificado) y su dominio se falsea en /etc/hosts: el navegador la abre "
                        "en este equipo. Al cargar otro proyecto deja de estar falseado y vuelve "
                        "a llevar a la web real.")
        if not fake:
            row = ActionRow("Ningún dominio falseado",
                            "Los dominios de los vhosts llevan a sus webs reales")
            # (en un tercio de la pestaña no cabe en una línea)
            row.subtitle.set_line_wrap(True)
            row.subtitle.set_ellipsize(0)
            lb.add(row)
        for h in fake:
            lb.add(self.host_row(h))
        # En la misma fila: el host falseado ocupa 1/3 y el proyecto nuevo, 2/3 (tres columnas iguales)
        grid = Gtk.Grid(column_spacing=18, column_homogeneous=True)
        box.set_valign(Gtk.Align.START)
        grid.attach(box, 0, 0, 1, 1)
        new_domain = self.build_new_domain()
        new_domain.set_valign(Gtk.Align.START)
        grid.attach(new_domain, 1, 0, 2, 1)
        self.hosts_box.pack_start(grid, False, False, 0)

        box, lb = group("Dominios de los vhosts",
                        "Encendido, el dominio lleva a este equipo (127.0.0.1); apagado, a la "
                        "web real. Se pide la contraseña de sudo para cambiar /etc/hosts.")
        if not rest:
            lb.add(ActionRow("No hay más dominios",
                             "Los vhosts están en /opt/config/httpd-vhosts.conf"))
        for h in rest:
            lb.add(self.host_row(h))
        self.hosts_box.pack_start(box, False, False, 0)
        self.hosts_box.show_all()

    def build_new_domain(self):
        """Proyecto nuevo con el dominio de producción falseado (para construirlo en local y
        subirlo después a producción con los nombres reales). La carpeta se elige entre las de
        /opt/htdocs (por ejemplo, la de un git clone) o se crea; la base, entre las de la
        versión activa o se crea, como en Bases de datos."""
        f = self.newdom
        active = self.data["active"] if self.data else ""
        box, lb = group("Nuevo proyecto con dominio falseado",
                        "Para construir en local un proyecto nuevo con su dominio y su BBDD "
                        "de producción, sin tocar nada en producción. Elige su carpeta de "
                        "/opt/htdocs (por ejemplo, la de un git clone) o crea una, y su BBDD. "
                        "Se crea su vhost http y https con certificado, lo que falte de la "
                        "carpeta y la BBDD, y se falsea el dominio. Al terminar se exporta a "
                        "producción tal cual.")

        row = ActionRow("Dominio", "El de producción")
        e = Gtk.Entry(text=f["domain"], placeholder_text="mitienda.com", width_chars=COMBO_CHARS,
                      valign=Gtk.Align.CENTER)
        e.connect("changed", lambda w: (f.__setitem__("domain", clean_domain(w.get_text())),
                                        update())[0])
        row.add_suffix(e)
        lb.add(row)

        # Carpeta: las de /opt/htdocs (las que ya tienen dominio lo indican) o una nueva
        with_domain = {h["folder"]: h["name"] for h in (self.hosts or []) if h["folder"]}
        folders = project_folders()
        row = ActionRow("Carpeta", "Ya tiene el dominio %s" % with_domain[f["folder"]]
                        if f["folder"] in with_domain else
                        "En /opt/htdocs (git clone) o nueva")
        # Un dominio largo no ensancha la pestaña: se corta con «…» y se ve entero al pasar el raton
        row.subtitle.set_max_width_chars(26)
        row.subtitle.set_tooltip_text(row.subtitle.get_label())
        fcombo = narrow(Gtk.ComboBoxText(valign=Gtk.Align.CENTER))
        for name in folders:
            fcombo.append(name, name)
        if f["folder"] and f["folder"] not in folders:
            fcombo.append(f["folder"], "%s (nueva)" % f["folder"])
        if f["folder"]:
            fcombo.set_active_id(f["folder"])
        if fcombo.get_active_id() is None:
            f["folder"] = ""
            fcombo.append("@ninguna", "Elige una carpeta")
            fcombo.set_active_id("@ninguna")
        fcombo.connect("changed", lambda w: self.on_new_domain_folder(w.get_active_id()))
        row.add_suffix(fcombo)
        b = Gtk.Button(tooltip_text="Crear una carpeta nueva", valign=Gtk.Align.CENTER)
        b.add(icon("list-add-symbolic"))
        b.connect("clicked", lambda *_: self.ask_new_domain_name("folder", folders))
        row.add_suffix(b)
        lb.add(row)

        # Base de datos: las de la versión activa, una nueva o ninguna
        dbs = self.data["dbs"].get(active, []) if active else []
        row = ActionRow("BBDD", "En lampp-%s" % active if active
                        else "No hay ninguna versión activa")
        dcombo = narrow(Gtk.ComboBoxText(valign=Gtk.Align.CENTER, sensitive=bool(active)))
        dcombo.append("@sin", "Sin BBDD")
        for db in dbs:
            dcombo.append(db, db)
        if f["db"] and f["db"] not in dbs:
            dcombo.append(f["db"], "%s (nueva)" % f["db"])
        dcombo.set_active_id(f["db"] or "@sin")
        if dcombo.get_active_id() is None:
            f["db"] = ""
            dcombo.set_active_id("@sin")
        dcombo.connect("changed", lambda w: f.__setitem__(
            "db", "" if w.get_active_id() in (None, "@sin") else w.get_active_id()))
        row.add_suffix(dcombo)
        b = Gtk.Button(tooltip_text="Crear una BBDD nueva", valign=Gtk.Align.CENTER,
                       sensitive=bool(active))
        b.add(icon("list-add-symbolic"))
        b.connect("clicked", lambda *_: self.ask_new_domain_name("db", dbs))
        row.add_suffix(b)
        lb.add(row)

        # (debajo, lo que falta para poder crearlo: sin eso el boton no se puede pulsar)
        row = ActionRow("", " ")
        btn = css(Gtk.Button(label="Crear y falsear"), "suggested-action")
        btn.connect("clicked", lambda *_: self.on_new_domain())
        row.add_suffix(btn)
        lb.add(row)

        def update():
            why = ("Escribe el dominio de producción" if not f["domain"] else
                   "«%s» no es un dominio (por ejemplo: mitienda.com)" % f["domain"]
                   if not DOMAIN_RX.match(f["domain"]) else
                   "Elige su carpeta" if not f["folder"] else
                   "Espera a que acabe la tarea en marcha" if self.busy else
                   "https://%s → /opt/htdocs/%s" % (f["domain"].lower(), f["folder"]))
            row.subtitle.set_label(why)
            btn.set_sensitive(bool(DOMAIN_RX.match(f["domain"])) and bool(f["folder"])
                              and not self.busy)
        self.newdom_update = update
        update()
        return box

    def on_new_domain_folder(self, folder):
        f = self.newdom
        f["folder"] = "" if folder in (None, "@ninguna") else folder
        # Si el proyecto ya trae su configuración (wp-config.php, PrestaShop, .env), se propone
        # su base de datos
        db = project_db(f["folder"]) if f["folder"] else ""
        if db and not f["db"]:
            f["db"] = db
            GLib.idle_add(lambda: (self.build_hosts(), False)[1])
            self.toast("BBDD de su configuración: %s" % db)
        else:
            GLib.idle_add(lambda: (self.build_hosts(), False)[1])

    def ask_new_domain_name(self, key, existing):
        """Nombre de una carpeta o una base nueva (se crea al pulsar «Crear y falsear»)."""
        is_db = key == "db"
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True,
                                message_type=Gtk.MessageType.QUESTION,
                                buttons=Gtk.ButtonsType.NONE,
                                text="BBDD nueva" if is_db else "Carpeta nueva")
        dlg.format_secondary_text(
            "Pon el nombre de la BBDD de producción. Se crea vacía en lampp-%s al "
            "pulsar «Crear y falsear»." % self.data["active"] if is_db else
            "Se crea en /opt/htdocs al pulsar «Crear y falsear». Si vas a clonar el proyecto "
            "con git, clónalo antes y elige su carpeta en la lista.")
        entry = Gtk.Entry(max_length=64, activates_default=True,
                          placeholder_text="nombre_de_la_base" if is_db else
                          (self.newdom["domain"] or "carpeta-del-proyecto"))
        hint = label("Letras sin acentos, números, _ y -" if is_db else
                     "Letras sin acentos, números, punto, _ y -", "dim-label")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.pack_start(entry, False, False, 0)
        box.pack_start(hint, False, False, 0)
        dlg.get_message_area().pack_start(box, False, False, 0)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Elegir", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        rx = r"^[A-Za-z0-9_-]{1,64}$" if is_db else r"^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$"

        def value():
            return entry.get_text().strip() or ("" if is_db else self.newdom["domain"])

        def update(*_):
            name = value()
            taken = name in existing
            ok.set_sensitive(bool(re.match(rx, name)) and not taken)
            hint.set_label("Ya existe: elígela en la lista." if taken else
                           "Letras sin acentos, números, _ y -" if is_db else
                           "Letras sin acentos, números, punto, _ y -")
        entry.connect("changed", update)
        update()
        dlg.show_all()
        resp = run_dialog(dlg)
        name = value()
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return
        self.newdom[key] = name
        GLib.idle_add(lambda: (self.build_hosts(), False)[1])

    def on_new_domain(self):
        f = self.newdom
        domain = f["domain"].lower()
        folder = f["folder"]
        db = f["db"]
        if not folder:
            return
        active = self.data["active"] if self.data else ""
        exists = os.path.isdir(os.path.join(HTDOCS, folder))
        steps = ["Carpeta /opt/htdocs/%s%s." % (folder, "" if exists else " (se crea)"),
                 "Vhost http y https de %s con su certificado autofirmado." % domain]
        if db:
            have = db in (self.data["dbs"].get(active, []) if active else [])
            steps.append("BBDD %s en lampp-%s%s." % (
                db, active, " (ya existe: se deja como está)" if have else " (se crea vacía)"))
        steps.append("%s se falsea en /etc/hosts; los demás dominios dejan de estarlo." % domain)
        if not confirm(self.win, "¿Crear %s?" % domain, "Se pide la contraseña de sudo.", "Crear y falsear",
                       steps=steps):
            return
        args = ["nuevo-dominio", domain, folder] + ([db] if db else [])

        def done(ok_, *_):
            if ok_:
                self.newdom = {"domain": "", "folder": "", "db": ""}
                self.hosts = None
                self.toast("%s falseado: https://%s → /opt/htdocs/%s" % (domain, domain, folder))
        self.run_task("Creando %s" % domain, args, done_text="%s listo" % domain,
                      env=self.db_env() if active else None, on_done=done)

    def host_row(self, h):
        info = [h["folder"] or "sin carpeta en /opt/htdocs"]
        if not h["https"]:
            info.append("sin https")
        elif not h["crt"]:
            info.append("falta el certificado")
        if h.get("media"):
            info.append("imágenes que faltan de %s" % h["media"])
        row = ActionRow(h["name"], "  ·  ".join(info))
        # (en la tarjeta estrecha se cortan con «…»: enteros al pasar el ratón)
        row.title.set_tooltip_text(h["name"])
        row.subtitle.set_tooltip_text("  ·  ".join(info))
        # Logotipo del proyecto: PrestaShop, WordPress (por el nombre de su carpeta) o un globo
        if h["ps"]:
            row.add_prefix(section_icon(("logo", "prestashop"), 16))
        elif "wordpress" in (h["folder"] or "").lower():
            row.add_prefix(section_icon(("logo", "wordpress"), 16))
        else:
            row.add_prefix(section_icon(("icono", "web-browser-symbolic", ""), 16))
        if h["ps"]:
            row.add_title_tag(label("PrestaShop", "dim-label"))
        elif h.get("custom"):
            row.add_title_tag(label("Proyecto nuevo", "dim-label"))
        if h["fake"]:
            b = Gtk.Button(label="Abrir", valign=Gtk.Align.CENTER,
                           tooltip_text="https://%s" % h["name"])
            b.connect("clicked", lambda *_: self.open_uri(
                "%s://%s" % ("https" if h["https"] else "http", h["name"])))
            row.add_suffix(b)
        if h["name"].lower().endswith(".local"):
            b = Gtk.Button(valign=Gtk.Align.CENTER, sensitive=not self.busy,
                           tooltip_text="Imágenes de producción" + (": %s" % h["media"] if h.get("media") else ""))
            b.add(icon("image-x-generic-symbolic"))
            b.connect("clicked", lambda *_: self.on_media_proxy(h))
            row.add_suffix(b)
        sw = Gtk.Switch(active=h["fake"], valign=Gtk.Align.CENTER)
        sw.set_tooltip_text(host_switch_tip(h))
        sw.connect("state-set", self.on_host_switch, h)
        row.add_suffix(sw)
        return row

    def project_hosts(self, name):
        """Dominios falseables de un proyecto: los de los vhosts de su carpeta. Un .local no es un
        dominio falseado (no hay ninguna web real a la que devolverlo)."""
        return [h for h in self.hosts or []
                if h["folder"] == name and not h["name"].lower().endswith(".local")]

    def on_view_hosts(self, *_):
        """El fichero de hosts, solo para verlo (para cambiarlo: Editar, en Configuración), con los
        dominios que se pueden falsear delante: un dominio con vhost no sale en él hasta falsearlo."""
        path = self.data["hosts"] if self.data else "/etc/hosts"
        vhosts = self.data["vhosts"] if self.data else ""
        try:
            with open(path, errors="replace") as f:
                text = f.read()
        except OSError as exc:
            message(self.win, "No se ha podido leer %s" % path, str(exc), Gtk.MessageType.ERROR)
            return
        self.show_text(path, "Dominios que se pueden falsear y contenido del fichero (solo lectura)",
                       hosts_view_text(self.hosts or [], path, vhosts, text), self.on_view_hosts,
                       lines=1000000, to_end=False)

    def on_media_proxy(self, h):
        """media-produccion: el dominio de producción al que se piden las imágenes que faltan en un
        .local (uploads e img no van en git). Se propone el dominio real del vhost de su carpeta."""
        name = h["name"]
        guess = h.get("media") or next((o["name"] for o in (self.hosts or []) if h["folder"]
                                        and o["folder"] == h["folder"] and not o["name"].endswith(".local")), "")
        dlg = Gtk.Dialog(title="Imágenes de producción", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(520, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        box.pack_start(label("Imágenes de producción en %s" % name, "nv-titulo", wrap=True), False, False, 0)
        box.pack_start(label("Las imágenes, vídeos y PDF de wp-content/uploads o img que no estén en la carpeta "
                             "se piden a la web real (redirección 302): no hace falta descargarlas. Solo en "
                             "los .local; lo que ya está en local se sigue sirviendo desde aquí.",
                             "nv-tenue", wrap=True, max_width_chars=60), False, False, 0)
        entry = Gtk.Entry(text=guess, placeholder_text="ejemplo.com", max_length=80, activates_default=True)
        box.pack_start(entry, False, False, 0)
        dlg.get_content_area().add(box)
        if h.get("media"):
            css(dlg.add_button("Quitar", Gtk.ResponseType.REJECT), "destructive-action")
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Guardar", Gtk.ResponseType.OK), "nv-azul")
        dlg.set_default_response(Gtk.ResponseType.OK)

        def update(*_):
            d = re.sub(r"^https?://", "", entry.get_text().strip().lower()).rstrip("/")
            ok.set_sensitive(bool(DOMAIN_RX.match(d)) and not d.endswith(".local") and d != h.get("media"))
        entry.connect("changed", update)
        dlg.show_all()
        update()
        resp = run_dialog(dlg)
        prod = re.sub(r"^https?://", "", entry.get_text().strip().lower()).rstrip("/")
        dlg.destroy()
        if resp == Gtk.ResponseType.REJECT:
            self.run_task("Quitando las imágenes de producción de %s" % name, ["media-produccion", name, "quitar"],
                          done_text="%s ya no pide nada a producción" % name, auto_close=True)
        elif resp == Gtk.ResponseType.OK:
            self.run_task("Imágenes de producción en %s" % name, ["media-produccion", name, prod],
                          done_text="%s pide a %s las imágenes que faltan" % (name, prod), auto_close=True)

    def on_host_switch(self, sw, state, h):
        if state == h["fake"]:
            return False
        name = h["name"]
        local = name.lower().endswith(".local")
        if local and not state and not confirm(
                self.win, "¿Apagar %s?" % name,
                "Su línea de /etc/hosts queda comentada. Mientras esté apagado, al abrir %s "
                "cualquiera de tu misma wifi podría contestar con una web suya. Se puede volver a "
                "encender cuando quieras." % name,
                "Apagar %s" % name):
            sw.set_active(True)
            return True
        if local:
            title = "%s %s" % ("Encendiendo" if state else "Apagando", name)
            done = "%s %s" % (name, "lleva a este equipo" if state else "apagado")
        elif state:
            title, done = "Falseando %s" % name, "%s lleva a este equipo" % name
        else:
            title, done = "Dejando de falsear %s" % name, "%s lleva a la web real" % name

        def finished(ok_, *_):
            if not ok_:
                self.hosts = None
            self.toast(done if ok_ else "No se ha cambiado /etc/hosts")
        self.run_task(title, ["hosts-falsear", name, "si" if state else "no"],
                      done_text=done, auto_close=True, on_done=finished)
        # El interruptor cambia cuando se vuelva a leer /etc/hosts
        return True
