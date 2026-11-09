class NvBasesDatos:
    """Bases de datos (como Docker)."""

    # ------------------------------------------------------------------ Bases de datos (como Docker)
    def update_db_search(self):
        # (el buscador de siempre no esta en la ventana nueva: la tabla tiene el suyo)
        pass

    def on_db_sizes(self, rc, out):
        sizes = {(f[1], f[2]): (int(f[3]), int(f[4])) for f in parse_lines(out)
                 if f[0] == "Z" and len(f) >= 5 and f[3].isdigit() and f[4].isdigit()}
        if sizes != self.db_sizes:
            self.db_sizes = sizes
            self.nv_db_table()
        self.nv_db_disk()
        return False

    def reload(self, branches=False):
        super().reload(branches)
        run_quick(["gui-bbdd-tamanos"], self.on_db_sizes)

    def build_databases(self):
        d = self.data
        clear(self.db_box)
        if not d:
            self.loading(self.db_box)
            return
        box = self.db_box
        act = next((i for i in self.installs() if i["folder"] == d["active"]), None)
        head = Gtk.Box(spacing=12)
        t = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        t.pack_start(label("Bases de datos", "nv-titulo-grande"), False, False, 0)
        t.pack_start(label("Cada versión con su MariaDB y sus BBDD (sin las del sistema)", "nv-chico", "nv-tenue"), False, False, 0)
        head.pack_start(t, True, True, 0)
        new = nv_button("list-add-symbolic", "Nueva BBDD…", "Crear una BBDD vacía", self.on_create_db, "nv-azul")
        new.set_sensitive(bool(act) and not self.busy)
        head.pack_end(new, False, False, 0)
        pma = nv_button(logo("phpmyadmin", 16), "phpMyAdmin", "phpMyAdmin de la versión activa",
                        lambda *_: self.open_uri("http://127.0.0.1/phpmyadmin/"))
        pma.set_sensitive(bool(act) and d["running"])
        head.pack_end(pma, False, False, 0)
        box.pack_start(head, False, False, 0)
        # Tarjetas: cuantas hay, en la activa y la ultima que ha cambiado
        all_dbs = [(f, db) for f, dbs in d["dbs"].items() for db in dbs
                   if next((i for i in self.installs() if i["folder"] == f and i["owner"] == f), None)]
        latest = max(((d["dbdate"].get(k, (0, ""))[0], k) for k in all_dbs), default=(0, None))
        stats = Gtk.Box(spacing=12, homogeneous=True)
        cards = [("BBDD", str(len(all_dbs)), plural(len({f for f, _ in all_dbs}), "versión", "versiones"), None),
                 ("En la versión activa", str(len(d["dbs"].get(d["active"], []))) if act else "—",
                  ("lampp-%s · MariaDB %s" % (act["folder"], act["mariadb"])) if act else "ninguna activa", None),
                 ("La última que ha cambiado", latest[1][1] if latest[1] else "—",
                  ("lampp-%s · %s" % (latest[1][0], fmt_age(max(0, int(time.time()) - latest[0])))) if latest[1] else "", None)]
        for title, value, sub, _extra in cards:
            c = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4), "nv-stat")
            top = Gtk.Box(spacing=6)
            top.pack_start(label(title, "nv-chico", "nv-tenue", ellipsize=3), True, True, 0)
            c.pack_start(top, False, False, 0)
            c.pack_start(label(value, "nv-cifra", ellipsize=3), False, False, 0)
            c.pack_start(label(sub, "nv-chico", "nv-tenue", ellipsize=3), False, False, 0)
            stats.pack_start(c, True, True, 0)
        # Lo que ocupan las BBDD de todas las versiones y lo que queda libre en el disco de /opt
        c = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4), "nv-stat")
        c.pack_start(label("Ocupan las BBDD", "nv-chico", "nv-tenue", ellipsize=3), False, False, 0)
        self.db_disk_card = (label("—", "nv-cifra", ellipsize=3), css(Gtk.ProgressBar(margin_top=2), "nv-barra"),
                             label("", "nv-chico", "nv-tenue", ellipsize=3), c)
        for w in self.db_disk_card[:3]:
            c.pack_start(w, False, False, 0)
        stats.pack_start(c, True, True, 0)
        self.nv_db_disk()
        box.pack_start(stats, False, False, 0)
        # Subir o actualizar una BBDD: antes de la tabla, en un visor hundido
        box.pack_start(self.nv_db_import(), False, False, 0)
        tools = Gtk.Box(spacing=10)
        only = Gtk.Switch(active=self.db_only_active, valign=Gtk.Align.CENTER)
        only.connect("notify::active", lambda w, _p: (setattr(self, "db_only_active", w.get_active()), self.nv_db_table()))
        tools.pack_end(only, False, False, 0)
        tools.pack_end(label("Solo la versión activa", "nv-chico", "nv-tenue", valign=Gtk.Align.CENTER), False, False, 0)
        search = Gtk.SearchEntry(placeholder_text="Buscar una BBDD o su proyecto", width_chars=30,
                                 valign=Gtk.Align.CENTER, text=self.db_query)
        search.connect("search-changed", lambda e: (setattr(self, "db_query", e.get_text().strip().lower()), self.nv_db_table()))
        tools.pack_start(search, False, False, 0)
        box.pack_start(tools, False, False, 0)
        self.db_table = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.pack_start(self.db_table, False, False, 0)
        self.nv_db_table()
        box.show_all()
        self.update_import_button()

    def nv_db_import(self):
        """Subir o actualizar una BBDD, compacto: el fichero, la BBDD de destino, el proyecto y Cargar en
        columnas, dentro de un visor hundido. Lo que hace es lo de siempre (on_pick_sql, on_import...)."""
        d = self.data
        act = next((i for i in d["installs"] if i["folder"] == d["active"]), None)
        if act and self.imp["folder"] != act["folder"]:
            # Otra version activa: sus bases son otras
            self.imp.update(db=None, folder=act["folder"])
        box = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10), "nv-hundido")
        head = Gtk.Box(spacing=8)
        head.pack_start(symbol("document-send-symbolic", 16), False, False, 0)
        head.pack_start(label("Subir o actualizar una BBDD", "nv-hundido-titulo"), False, False, 0)
        head.pack_start(info_icon("Carga una copia .sql, .sql.gz o .zip en el MariaDB de la versión activa. Antes se "
                                  "borran todas las tablas de la BBDD de destino (con una copia en ~/lvm-copias), para "
                                  "que no quede nada de lo anterior. Los .zip se descomprimen solos."), False, False, 0)
        if act:
            head.pack_start(label("en lampp-%s · MariaDB %s" % (act["folder"], act["mariadb"]), "nv-chico", "nv-tenue",
                                  valign=Gtk.Align.CENTER), False, False, 0)
        box.pack_start(head, False, False, 0)
        # (sin version activa: lo dice y no hay nada que elegir; update_import_button no se llama)
        self.imp_btn = None
        if not act:
            box.pack_start(label("Activa una versión en Versiones de PHP para cargar BBDD.", "nv-chico", "nv-tenue"),
                           False, False, 0)
            return box

        def column(title, widget, hint=None):
            c = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            c.pack_start(label(title.upper(), "nv-chico", "nv-tenue"), False, False, 0)
            c.pack_start(widget, False, False, 0)
            if hint is not None:
                c.pack_start(hint, False, False, 0)
            return c
        cols = Gtk.Box(spacing=16)
        # Fichero
        f = self.imp["file"]
        name = "Ningún fichero elegido"
        if f:
            try:
                name = "%s · %s" % (os.path.basename(f), fmt_size(os.path.getsize(f)))
            except OSError:
                name = "%s · ya no existe" % os.path.basename(f)
        pick = Gtk.Box(spacing=6)
        b = Gtk.Button(label="Elegir…", valign=Gtk.Align.CENTER)
        b.connect("clicked", self.on_pick_sql)
        pick.pack_start(b, False, False, 0)
        fl = label(name, "nv-chico", "nv-mono" if f else "nv-tenue", ellipsize=2, max_width_chars=28,
                   valign=Gtk.Align.CENTER)
        if f:
            fl.set_tooltip_text(f)
        pick.pack_start(fl, True, True, 0)
        # (lo que falta para poder cargar: debajo del fichero, que tiene sitio)
        self.imp_hint = label("", "nv-chico", "nv-tenue", wrap=True, max_width_chars=36)
        self.imp_hint.set_no_show_all(True)
        cols.pack_start(column("Fichero SQL", pick, self.imp_hint), True, True, 0)
        # BBDD de destino (con crear y borrar al lado)
        dest = Gtk.Box(spacing=4)
        combo = narrow(Gtk.ComboBoxText(valign=Gtk.Align.CENTER), 24)
        for db in d["dbs"].get(act["folder"], []):
            combo.append(db, db)
        if self.imp["db"]:
            combo.set_active_id(self.imp["db"])
        if combo.get_active_id() is None:
            self.imp["db"] = None
            combo.append("@ninguna", "Elige una BBDD")
            combo.set_active_id("@ninguna")
        combo.connect("changed", self.on_pick_db)
        dest.pack_start(combo, True, True, 0)
        b = nv_button("list-add-symbolic", None, "Crear una BBDD nueva", self.on_create_db, flat=True)
        dest.pack_start(b, False, False, 0)
        self.imp_drop_btn = nv_button("user-trash-symbolic", None, "Borrar la BBDD elegida",
                                      lambda *_: self.on_drop_db(self.imp["db"]), flat=True)
        self.imp_drop_btn.set_sensitive(bool(self.imp["db"]))
        dest.pack_start(self.imp_drop_btn, False, False, 0)
        cols.pack_start(column("BBDD de destino", dest), True, True, 0)
        # Proyecto de la base: queda como su base y, si es un WordPress, su wp-config.php la usa
        folders = project_folders()
        if self.imp.get("project") not in folders:
            self.imp["project"] = None
        # La primera vez con esta base se propone su proyecto; luego se respeta lo elegido
        if self.imp["db"] and self.imp.get("project_for") != self.imp["db"]:
            self.imp["project"] = guess_project(self.imp["db"], d["active"]) or self.imp["project"]
            self.imp["project_for"] = self.imp["db"]
        combo = narrow(Gtk.ComboBoxText(valign=Gtk.Align.CENTER), 24)
        combo.append("@ninguno", "Ninguno")
        for name in folders:
            combo.append(name, name)
        combo.set_active_id(self.imp["project"] or "@ninguno")
        combo.connect("changed", self.on_pick_project)
        self.imp_proj_combo = combo
        # (la explicacion de debajo: la cambia on_pick_project)
        self.imp_proj_hint = label(self.import_project_hint(), "nv-chico", "nv-tenue", wrap=True, max_width_chars=30)
        cols.pack_start(column("Proyecto (opcional)", combo, self.imp_proj_hint), True, True, 0)
        # Cargar
        go = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, valign=Gtk.Align.END)
        self.imp_btn = css(Gtk.Button(label="Cargar"), "verde", "pildora")
        self.imp_btn.connect("clicked", self.on_import)
        go.pack_start(self.imp_btn, False, False, 0)
        cols.pack_end(go, False, False, 0)
        box.pack_start(cols, False, False, 0)
        return box

    def update_import_button(self):
        # (sin version activa no hay boton Cargar)
        if getattr(self, "imp_btn", None) is not None:
            super().update_import_button()

    def nv_db_disk(self):
        """Tarjeta «Ocupan las BBDD»: la suma de las medidas de todas las versiones (cada una se mide
        cuando está activa y en marcha) y la barra del disco donde están (/opt), con lo que queda libre."""
        card, d = getattr(self, "db_disk_card", None), self.data
        if card is None or not d:
            return
        val, bar, sub, box = card
        all_dbs = [(f, db) for f, dbs in d["dbs"].items() for db in dbs
                   if next((i for i in self.installs() if i["folder"] == f and i["owner"] == f), None)]
        got = [self.db_sizes[k][0] for k in all_dbs if k in self.db_sizes]
        val.set_label(fmt_size(sum(got)) if got else "—")
        missing = len(all_dbs) - len(got)
        box.set_tooltip_text(("%s sin medir"
                              % plural(missing, "BBDD", "BBDD")) if missing else
                             "Tamaño de las BBDD de todas las versiones")
        try:
            st = os.statvfs("/opt")
            total, free = st.f_blocks * st.f_frsize, st.f_bavail * st.f_frsize
        except OSError:
            total = free = 0
        bar.set_fraction(1 - free / total if total else 0)
        sub.set_label("Disco: %s libres de %s" % (fmt_size(free), fmt_size(total)) if total else "")
        tip = "Quedan %s libres en el disco de /opt (ocupado el %d %%)" % (fmt_size(free), round(100 - 100 * free / total)) \
            if total else None
        bar.set_tooltip_text(tip)
        sub.set_tooltip_text(tip)

    def nv_db_project(self, db, folder):
        """Proyecto de una BBDD en una version: el vinculado o el que la usa en su configuracion."""
        f = self.link_of(db, folder)
        if f:
            return f
        if f == "":
            return ""
        users = [x["name"] for x in (self.projects or {}).get("list", []) if x["db"] == db]
        return users[0] if len(users) == 1 else ""

    def nv_db_toggle(self, key):
        """Pliega o despliega una versión en Bases de datos: solo una desplegada a la vez (al abrir
        otra, se cierra la anterior)."""
        if key in self.expanded:
            self.expanded.discard(key)
        else:
            self.expanded.difference_update({k for k in self.expanded if k.startswith("@db")})
            self.expanded.add(key)
        self.nv_db_table()

    def nv_db_table(self):
        if getattr(self, "db_table", None) is None:
            return
        clear(self.db_table)
        d = self.data
        q = self.db_query
        used = self.loaded_project_db()
        loaded = self.loaded_project_entry()
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "nv-grupo")
        widths = [270, 210, 110, 230, 190]
        groups = [Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL) for _ in widths]

        def row(cells, head_row=False, indent=0, on_click=None):
            r = Gtk.ListBoxRow(activatable=on_click is not None)
            b = css(Gtk.Box(spacing=12), "nv-fila", *(["nv-cab"] if head_row else []))
            for n, c in enumerate(cells):
                w = c if isinstance(c, Gtk.Widget) else label(c.upper() if head_row else c)
                if n == 0 and indent:
                    cell = Gtk.Box()
                    sp = Gtk.Box()
                    sp.set_size_request(indent, -1)
                    cell.pack_start(sp, False, False, 0)
                    cell.pack_start(w, True, True, 0)
                    w = cell
                w.set_size_request(widths[n], -1)
                groups[n].add_widget(w)
                b.pack_start(w, n == len(cells) - 1, True, 0)
            r.add(b)
            r.on_click = on_click
            lb.add(r)

        def actions(items):
            a = Gtk.Box(spacing=6, halign=Gtk.Align.START)
            for w in items:
                if w is not None:
                    a.pack_start(w, False, False, 0)
            return a
        lb.connect("row-activated", lambda _l, r: r.on_click and r.on_click())
        row(["Nombre", "Proyecto", "Tamaño", "Cambiada", "Acciones"], True)

        def size_label(owner, db):
            got = self.db_sizes.get((owner, db))
            if not got:
                lbl = label("—", "nv-chico", "nv-tenue")
                lbl.set_tooltip_text("Se mide con su versión en marcha")
                return lbl
            lbl = label(fmt_size(got[0]), "nv-chico", "nv-mono")
            lbl.set_tooltip_text("Datos e índices, medido el %s"
                                 % time.strftime("%d/%m/%Y a las %H:%M", time.localtime(got[1])))
            return lbl
        shown = 0
        for inst in sorted(self.installs(), key=lambda i: ver_tuple(i["php"]), reverse=True):
            folder = inst["folder"]
            active = folder == d["active"]
            if self.db_only_active and not active:
                continue
            dbs = d["dbs"].get(folder, []) if inst["owner"] == folder else []
            rows = []
            for db in dbs:
                proj = self.nv_db_project(db, folder)
                if q and q not in db.lower() and q not in proj.lower():
                    continue
                rows.append((db, proj))
            if q and not rows:
                continue
            shown += 1
            key = "@db" + folder
            opened = key in self.expanded if not q else True
            name = Gtk.Box(spacing=8)
            name.pack_start(icon("pan-down-symbolic" if opened else "pan-end-symbolic"), False, False, 0)
            ic = css(Gtk.Box(), "nv-dk-icono")
            ic.pack_start(logo("mariadb", 14), False, False, 0)
            name.pack_start(ic, False, False, 0)
            name.pack_start(label("lampp-%s" % folder, "nv-dk-proyecto", "nv-mono"), False, False, 0)
            if active:
                name.pack_start(label("Activa", "nv-etiqueta", "nv-etiqueta-azul", valign=Gtk.Align.CENTER), False, False, 0)
            sub = "PHP %s · MariaDB %s" % (inst["php"], inst["mariadb"])
            count = plural(len(dbs), "BBDD", "BBDD") if inst["owner"] == folder else "usa las de lampp-%s" % inst["owner"]
            grp_acts = []
            if active:
                b = nv_button("drive-multidisk-symbolic", None, "Abrir phpMyAdmin", lambda *_: self.open_uri("http://127.0.0.1/phpmyadmin/"), flat=True)
                b.set_sensitive(d["running"])
                grp_acts.append(b)
                b = nv_button("list-add-symbolic", None, "Crear una BBDD vacía aquí", self.on_create_db, flat=True)
                b.set_sensitive(not self.busy)
                grp_acts.append(b)
            total = sum(self.db_sizes.get((inst["owner"], db), (0, 0))[0] for db in d["dbs"].get(inst["owner"], []))
            row([name, label(sub, "nv-chico", "nv-tenue"),
                 label(fmt_size(total) if total else "—", "nv-chico", "nv-mono" if total else "nv-tenue"),
                 label(count, "nv-chico", "nv-tenue"), actions(grp_acts)],
                on_click=lambda key=key: self.nv_db_toggle(key))
            if not opened:
                continue
            for db, proj in rows:
                when, kind = d["dbdate"].get((folder, db), (0, ""))
                n = Gtk.Box(spacing=8)
                is_used = active and loaded is not None and db == used
                dt = label("●", "nv-verde" if is_used else "nv-gris")
                dt.set_tooltip_text("La usa el proyecto cargado (%s)" % loaded["name"] if is_used else None)
                if not is_used:
                    dt.set_opacity(0.25)
                n.pack_start(dt, False, False, 0)
                if is_ps_db(db):
                    n.pack_start(logo("prestashop", 14), False, False, 0)
                elif db.lower().startswith("wp_"):
                    n.pack_start(logo("wordpress", 14), False, False, 0)
                n.pack_start(label(db, "nv-mono", "nv-chico", ellipsize=3, tooltip_text=db), False, False, 0)
                pl = label(proj or "—", "nv-chico", "nv-tenue" if not proj else "", ellipsize=3)
                # (la fecha del cambio: la de su carga con el gestor o la del ultimo cambio de sus tablas)
                ch = label(("%s %s" % (time.strftime("%d/%m/%Y %H:%M", time.localtime(when)),
                                       "· importada" if kind == "i" else ""))
                           if when else "—", "nv-chico", "nv-mono" if when else "nv-tenue")
                if when:
                    ch.set_tooltip_text(db_date_text(when, kind))
                acts = []
                if is_ps_db(db):
                    acts.append(self.cache_button(db))
                cp = self.copy_button(db, inst)
                if cp:
                    acts.append(cp)
                acts.append(self.download_button(db, folder))
                ld = nv_button("folder-open-symbolic", None, "Cargar su proyecto (en lampp-%s)" % folder,
                               lambda *_, db=db, inst=inst: self.on_load_project(db, inst), flat=True)
                ld.set_sensitive(not self.busy)
                acts.append(ld)
                if active:
                    rm = nv_button("user-trash-symbolic", None, "Borrar la BBDD %s" % db, lambda *_, db=db: self.on_drop_db(db), flat=True)
                    rm.set_sensitive(not self.busy)
                    acts.append(rm)
                row([n, pl, size_label(inst["owner"], db), ch, actions(acts)], indent=26)
        if not shown:
            r = Gtk.ListBoxRow(activatable=False)
            r.add(label("Ninguna BBDD con «%s»" % q if q else "No hay versiones con BBDD", "nv-tenue", margin=14))
            lb.add(r)
        self.db_table.pack_start(lb, False, False, 0)
        self.db_table.show_all()
