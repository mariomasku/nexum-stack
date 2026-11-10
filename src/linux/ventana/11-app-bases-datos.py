class AppBasesDatos:
    """Bases de datos: lista, buscador y cargar el proyecto de una base."""

    # ------------------------------------------------------- bases de datos
    def build_databases(self):
        # El buscador no se redibuja (si no, se perderia lo escrito y el foco al refrescar)
        if getattr(self, "db_dyn", None) is None or self.db_dyn.get_parent() is None:
            clear(self.db_box)
            self.db_box.pack_start(self.build_db_search(), False, False, 0)
            self.db_dyn = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
            self.db_box.pack_start(self.db_dyn, False, False, 0)
        clear(self.db_dyn)
        d = self.data
        box, lb = group("BBDD por versión",
                        "Cada versión tiene su propio MariaDB. No se muestran las BBDD del "
                        "sistema (mysql, phpmyadmin…).")
        if not d["installs"]:
            lb.add(ActionRow("No hay ninguna versión instalada"))
        for inst in d["installs"]:
            folder = inst["folder"]
            dbs = d["dbs"].get(folder, [])
            sub = "MariaDB %s  ·  %s" % (inst["mariadb"], plural(len(dbs), "BBDD",
                                                                 "BBDD"))
            if inst["owner"] != folder:
                sub += "  ·  las de lampp-%s" % inst["owner"]
            exp = ExpanderRow("lampp-%s" % folder, sub,
                              on_toggle=lambda on, f=folder: self.remember("@db" + f, on))
            active = folder == d["active"]
            if active:
                exp.add_title_tag(label("Activa", "texto-activa"))
                pma = Gtk.Button(label="Abrir phpMyAdmin", sensitive=d["running"],
                                 tooltip_text=None if d["running"] else
                                 "La versión activa está parada")
                pma.connect("clicked", lambda *_: self.open_uri("http://127.0.0.1/phpmyadmin/"))
                exp.add_suffix(pma)
                row = ActionRow("Crear BBDD…")
                row.add_prefix(icon("list-add-symbolic"))
                row.set_activatable(True)
                row.on_activate = self.on_create_db
                exp.add_row(row)
            elif not dbs:
                exp.add_row(ActionRow("Sin BBDD propias"))
            # En la activa, punto verde en la BBDD que usa el proyecto cargado
            used = self.loaded_project_db() if active else ""
            for db in dbs:
                row = ActionRow(db, db_date_text(*d["dbdate"].get((folder, db), (0, ""))))
                if active:
                    dot = label("●", "punto-verde")
                    if db == used:
                        x = self.loaded_project_entry()
                        dot.set_tooltip_text("La usa el proyecto cargado%s"
                                             % (" (%s)" % x["name"] if x else ""))
                    else:
                        # (invisible: así los nombres quedan alineados)
                        dot.set_opacity(0)
                    row.add_prefix(dot)
                if d["dbdate"].get((folder, db), (0, ""))[1] == "c":
                    row.subtitle.set_tooltip_text(DB_DATE_HELP)
                if is_ps_db(db):
                    row.add_suffix(self.cache_button(db))
                copy = self.copy_button(db, inst)
                if copy:
                    row.add_suffix(copy)
                row.add_suffix(self.download_button(db, folder))
                if active:
                    b = Gtk.Button(tooltip_text="Borrar la BBDD %s" % db,
                                   relief=Gtk.ReliefStyle.NONE)
                    b.add(icon("user-trash-symbolic"))
                    b.connect("clicked", lambda _b, n=db: self.on_drop_db(n))
                    row.add_suffix(b)
                exp.add_row(row)
            if "@db" + folder in self.expanded:
                exp.set_expanded(True)
            lb.add(exp)
        self.db_dyn.pack_start(box, False, False, 0)
        self.db_dyn.pack_start(self.build_import(), False, False, 0)
        self.db_box.show_all()
        self.update_db_search()

    def cache_button(self, db):
        """Vaciar var/cache de la tienda PrestaShop de la base (la carpeta la busca el script)."""
        b = Gtk.Button(tooltip_text="Vaciar la caché de %s" % db,
                       relief=Gtk.ReliefStyle.NONE, sensitive=not self.busy)
        b.add(icon("edit-clear-all-symbolic"))
        b.connect("clicked", lambda *_: self.run_task(
            "Vaciando la caché de la tienda de %s" % db, ["vaciar-cache", "--bd", db],
            done_text="Caché vaciada", auto_close=True))
        return b

    def copy_targets(self, db, inst):
        """Versiones a las que se puede copiar la base: las que no comparten las bases con la de
        origen. Las que ya la tienen también (se sustituye, con copia antes)."""
        return [i for i in self.installs() if i["owner"] != inst["owner"]]

    def has_db(self, folder, db):
        return db in self.data["dbs"].get(folder, [])

    def copy_button(self, db, inst):
        """Copiar la base a otra versión de PHP que no la tenga (para probar el proyecto con ella)."""
        if not self.copy_targets(db, inst):
            return None
        b = Gtk.Button(tooltip_text="Copiar %s a otra versión de PHP" % db,
                       relief=Gtk.ReliefStyle.NONE, sensitive=not self.busy)
        b.add(icon("edit-copy-symbolic"))
        b.connect("clicked", lambda *_: self.on_copy_db(db, inst))
        return b

    def on_copy_db(self, db, inst):
        """Copia la BBDD, con el mismo nombre, de la versión pulsada a otra. Siempre se avisa
        antes. (Copiarla con otro nombre o con otra carpeta: Replicar, en Cargar proyecto.)"""
        targets = self.copy_targets(db, inst)
        if not targets:
            return
        dlg = Gtk.Dialog(title="Copiar BBDD", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(520, -1)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Copiar", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=24)
        dlg.get_content_area().add(box)
        box.pack_start(css(label("¿A qué versión de PHP copias %s?" % db, wrap=True,
                                 max_width_chars=60), "title-3"), False, False, 0)
        box.pack_start(label("Se copia con el mismo nombre desde lampp-%s, que no se toca. Para "
                             "copiarla con otro nombre o con otra carpeta de proyecto, usa, en "
                             "Proyectos, el + de «Entorno»: «En otra versión de PHP (copiar su BBDD)…»." % inst["folder"],
                             "dim-label", wrap=True, max_width_chars=60), False, False, 0)
        first, radios = None, []
        # (primero las que no la tienen; dentro, de la más nueva a la más antigua)
        for i in sorted(targets, key=lambda i: (not self.has_db(i["folder"], db), ver_tuple(i["php"])),
                        reverse=True):
            rb = Gtk.RadioButton.new_from_widget(first)
            rb.add(label("PHP %s  (lampp-%s)%s%s" % (
                i["php"], i["folder"], "  ·  la activa" if i["folder"] == self.data["active"] else "",
                "  ·  ya la tiene: se sustituye" if self.has_db(i["folder"], db) else "")))
            first = first or rb
            opt = css(Gtk.Box(), "opcion")
            opt.pack_start(rb, True, True, 0)
            rb.connect("toggled", lambda b, o=opt: (o.get_style_context().add_class("elegida")
                                                     if b.get_active() else
                                                     o.get_style_context().remove_class("elegida")))
            if rb is first:
                css(opt, "elegida")
            radios.append((rb, i))
            box.pack_start(opt, False, False, 0)
        box.show_all()
        resp = run_dialog(dlg)
        chosen = next((i for rb, i in radios if rb.get_active()), None)
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT or chosen is None:
            return
        args = ["copiar-bd", db, inst["folder"], chosen["folder"]]
        dst = chosen["folder"]
        notes = ["Se copia %s de lampp-%s (PHP %s) a lampp-%s (PHP %s), con el mismo nombre. "
                 "La de lampp-%s no se toca." % (db, inst["folder"], inst["php"], dst, chosen["php"],
                                                 inst["folder"])]
        if dst != self.data["active"]:
            notes.append("lampp-%s no es la activa: se arranca su MariaDB solo para la copia y se "
                         "pide la contraseña de administrador." % dst)
        replace = self.has_db(dst, db)
        if replace:
            notes.append("lampp-%s ya tiene una BBDD %s: se guarda antes una copia suya en "
                         "~/lvm-copias y después se pone en su lugar la de lampp-%s. Lo que tuviera "
                         "se pierde (salvo en esa copia)." % (dst, db, inst["folder"]))
            args.append("--sustituir")
        if not confirm(self.win, "¿Sustituir %s en lampp-%s?" % (db, dst) if replace else
                       "¿Copiar %s a lampp-%s?" % (db, dst), "",
                       ("Sustituir en lampp-%s" if replace else "Copiar a lampp-%s") % dst, destructive=replace,
                       steps=notes):
            return
        self.run_task("Copiando %s a lampp-%s" % (db, dst), args,
                      done_text="%s copiada a lampp-%s" % (db, dst), auto_close=True)

    def on_replicate(self, project=None):
        """Replicar un proyecto en otra versión de PHP: copia su BBDD de una versión a otra con el
        nombre que se elija (se propone el de la versión de destino: wp_x_8_4 → wp_x_8_5) y la
        vincula allí a la carpeta que se elija (la misma, otra o ninguna)."""
        if not self.data or not self.projects or self.busy:
            return
        projects = [x for x in self.projects["list"] if self.project_pairs(x)]
        if not projects:
            message(self.win, "No hay proyectos que replicar",
                    "Ningún proyecto de /opt/htdocs tiene su BBDD en una versión instalada.",
                    Gtk.MessageType.INFO)
            return
        if len({i["owner"] for i in self.installs()}) < 2:
            message(self.win, "No hay otra versión de PHP",
                    "Instala otra versión de PHP (con sus propias BBDD) para replicar un proyecto en ella.",
                    Gtk.MessageType.INFO)
            return
        # (el de la fila desde la que se pide o, si no, el cargado)
        loaded = project or self.loaded_project_entry()
        dlg = Gtk.Dialog(title="Replicar proyecto", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(600, -1)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Replicar", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=24)
        dlg.get_content_area().add(box)
        box.pack_start(css(label("Replicar un proyecto en otra versión de PHP", wrap=True,
                                 max_width_chars=60), "title-3"), False, False, 0)
        box.pack_start(label("Se copia su BBDD a la otra versión, con el nombre que elijas, y allí "
                             "queda vinculada a la carpeta que elijas: después, Cargar proyecto lo "
                             "monta con esa versión. La versión de origen no se toca.",
                             "dim-label", wrap=True, max_width_chars=60), False, False, 0)
        grid = Gtk.Grid(column_spacing=12, row_spacing=10, margin_top=8)
        box.pack_start(grid, False, False, 0)

        def field(n, text, widget):
            grid.attach(label(text, "dim-label"), 0, n, 1, 1)
            widget.set_hexpand(True)
            grid.attach(widget, 1, n, 1, 1)
            return widget
        pcombo = field(0, "Proyecto", Gtk.ComboBoxText())
        for x in projects:
            pcombo.append(x["name"], x["name"])
        scombo = field(1, "Desde", Gtk.ComboBoxText())
        tcombo = field(2, "A la versión", Gtk.ComboBoxText())
        entry = field(3, "Nombre de la BBDD", Gtk.Entry(max_length=64, activates_default=True))
        hint = label("", "dim-label", "subtitulo", wrap=True, max_width_chars=50)
        grid.attach(hint, 1, 4, 1, 1)
        fcombo = field(5, "Carpeta", Gtk.ComboBoxText())
        fcombo.append("@ninguna", "— Ninguna: vincúlala después —")
        for f in project_folders():
            fcombo.append(f, f)
        grid.attach(label("La carpeta del proyecto con la que se cargará en esa versión (si tiene "
                          "una propia para ella, elígela).", "dim-label", "subtitulo", wrap=True,
                          max_width_chars=50), 1, 6, 1, 1)
        for c in (pcombo, scombo, tcombo, fcombo):
            narrow(c, 40)
        state = {"auto": True, "set": False, "pairs": [], "targets": []}

        def source():
            n = scombo.get_active()
            return state["pairs"][n] if 0 <= n < len(state["pairs"]) else None

        def target():
            n = tcombo.get_active()
            return state["targets"][n] if 0 <= n < len(state["targets"]) else None

        def update(*_):
            t, name = target(), entry.get_text().strip()
            valid = bool(re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_-]{0,63}", name)) and \
                name.lower() not in ("information_schema", "mysql", "performance_schema",
                                     "phpmyadmin", "sys", "test")
            if not valid:
                hint.set_label("Letras sin acentos, números, _ y - (sin - delante).")
            elif t and self.has_db(t["folder"], name):
                hint.set_markup('<span foreground="#e01b24">lampp-%s ya tiene una BBDD %s: se '
                                'sustituye (antes se guarda una copia suya en ~/lvm-copias).</span>'
                                % (t["folder"], GLib.markup_escape_text(name)))
            else:
                hint.set_label("Se crea %s en lampp-%s." % (name, t["folder"]) if t else "")
            ok.set_sensitive(valid and t is not None and source() is not None)

        def on_target(*_):
            # (mientras no se escriba otro, el nombre sigue a la versión elegida)
            s, t = source(), target()
            if s and t and state["auto"]:
                state["set"] = True
                entry.set_text(copy_name(s[1], t["php"]))
                state["set"] = False
            update()

        def on_source(*_):
            s = source()
            tcombo.remove_all()
            state["targets"] = sorted((i for i in self.installs() if s and i["owner"] != s[0]["owner"]),
                                      key=lambda i: ver_tuple(i["php"]), reverse=True)
            for i in state["targets"]:
                tcombo.append(i["folder"], "PHP %s  (lampp-%s)" % (i["php"], i["folder"]))
            tcombo.set_active(0 if state["targets"] else -1)
            on_target()

        def on_project(*_):
            x = next((p for p in projects if p["name"] == pcombo.get_active_id()), None)
            scombo.remove_all()
            state["pairs"] = sorted(self.project_pairs(x), key=lambda c: ver_tuple(c[0]["php"]),
                                    reverse=True) if x else []
            for i, d in state["pairs"]:
                scombo.append(None, "PHP %s  (lampp-%s)  ·  BBDD %s" % (i["php"], i["folder"], d))
            # (la de la versión activa, si la tiene)
            act = next((n for n, (i, _) in enumerate(state["pairs"])
                        if i["folder"] == self.data["active"]), 0)
            scombo.set_active(act if state["pairs"] else -1)
            if x:
                fcombo.set_active_id(x["name"])
            on_source()

        def edited(*_):
            if not state["set"]:
                state["auto"] = False
            update()
        pcombo.connect("changed", on_project)
        scombo.connect("changed", on_source)
        tcombo.connect("changed", on_target)
        entry.connect("changed", edited)
        pcombo.set_active_id(loaded["name"] if loaded and loaded in projects else projects[0]["name"])
        box.show_all()
        resp = run_dialog(dlg)
        s, t, name, folder = source(), target(), entry.get_text().strip(), fcombo.get_active_id()
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT or not s or not t or not name:
            return
        (src, db), dst = s, t["folder"]
        folder = None if folder in (None, "@ninguna") else folder
        args = ["copiar-bd", db, src["folder"], dst, "--como", name, "--carpeta", folder or "-"]
        notes = ["Se copia %s de lampp-%s (PHP %s) a lampp-%s (PHP %s) como %s, y allí queda "
                 "vinculada a %s." % (db, src["folder"], src["php"], dst, t["php"], name,
                                       folder or "ninguna carpeta")]
        if dst != self.data["active"]:
            notes.append("lampp-%s no es la activa: se arranca su MariaDB solo para la copia y se "
                         "pide la contraseña de administrador." % dst)
        replace = self.has_db(dst, name)
        if replace:
            notes.append("lampp-%s ya tiene una BBDD %s: se guarda antes una copia suya en "
                         "~/lvm-copias y se pone en su lugar. Lo que tuviera se pierde (salvo en esa "
                         "copia)." % (dst, name))
            args.append("--sustituir")
        if not confirm(self.win, "¿Replicar en lampp-%s?" % dst, "",
                       ("Sustituir en lampp-%s" if replace else "Replicar en lampp-%s") % dst, destructive=replace,
                       steps=notes):
            return
        self.run_task("Replicando en lampp-%s" % dst, args,
                      done_text="%s replicada en lampp-%s como %s" % (db, dst, name), auto_close=True)

    def download_button(self, db, folder):
        b = Gtk.Button(tooltip_text="Descargar una copia de %s (.zip)" % db,
                       relief=Gtk.ReliefStyle.NONE)
        b.add(icon("document-save-symbolic"))
        b.connect("clicked", lambda *_: self.on_download_db(db, folder))
        return b

    # ------------------------------------------------------ buscador de bases
    def build_db_search(self):
        box, lb = group("Buscar una BBDD",
                        "Escribe parte del nombre para ver en qué versión está y qué PHP "
                        "tienes que activar para trabajar con ella.")
        self.db_entry = Gtk.SearchEntry(placeholder_text="Nombre de la BBDD…",
                                        margin_top=6)
        self.db_entry.connect("search-changed", lambda *_: self.update_db_search())
        self.db_entry.connect("stop-search", lambda e: e.set_text(""))
        box.pack_start(self.db_entry, False, False, 0)
        box.reorder_child(self.db_entry, len(box.get_children()) - 2)
        self.db_found = label("", "dim-label", "subtitulo")
        self.db_found.set_no_show_all(True)
        box.pack_start(self.db_found, False, False, 0)
        box.reorder_child(self.db_found, len(box.get_children()) - 2)
        lb.set_no_show_all(True)
        self.db_results = lb
        return box

    def db_installs(self, db, skip_owner=None):
        """Versiones en las que está la base (sin repetir las que comparten bases)."""
        return [i for i in self.installs() if db in self.data["dbs"].get(i["folder"], [])
                and i["owner"] != skip_owner]

    def update_db_search(self):
        if getattr(self, "db_results", None) is None or not self.data:
            return
        lb, q = self.db_results, self.db_entry.get_text().strip().lower()
        clear(lb)
        if not q:
            lb.hide()
            self.db_found.hide()
            return
        hits = [(db, inst) for inst in self.installs()
                for db in self.data["dbs"].get(inst["folder"], []) if q in db.lower()]
        # Primero la coincidencia exacta, luego las que empiezan igual; la activa delante
        hits.sort(key=lambda h: (h[0].lower() != q, not h[0].lower().startswith(q),
                                 h[0].lower(), h[1]["folder"] != self.data["active"]))
        names = len({h[0] for h in hits})
        if hits:
            self.db_found.set_label("%s en %s" % (
                plural(names, "BBDD", "BBDD"),
                plural(len({h[1]["folder"] for h in hits}), "versión", "versiones")))
        else:
            self.db_found.set_label("Ninguna versión tiene una BBDD con «%s» en el "
                                    "nombre." % q)
        self.db_found.show()
        if not hits:
            lb.hide()
            return
        limit = 40
        for db, inst in hits[:limit]:
            lb.add(self.db_hit_row(db, inst, q))
        if len(hits) > limit:
            lb.add(ActionRow("Y %d más…" % (len(hits) - limit),
                             "Escribe más letras del nombre para encontrarla."))
        # no_show_all (para que no aparezca vacía) hace que show_all no la toque: fila a fila
        for row in lb.get_children():
            row.show_all()
        lb.show()

    def db_hit_row(self, db, inst, q):
        folder = inst["folder"]
        row = ActionRow(db)
        start = db.lower().find(q)
        esc = GLib.markup_escape_text
        row.title.set_markup("%s<b>%s</b>%s" % (esc(db[:start]), esc(db[start:start + len(q)]),
                                                esc(db[start + len(q):])))
        sub = "lampp-%s  ·  PHP %s  ·  MariaDB %s" % (folder, inst["php"], inst["mariadb"])
        if inst["owner"] != folder:
            sub += "  ·  las de lampp-%s" % inst["owner"]
        when, kind = self.data["dbdate"].get((folder, db), (0, ""))
        if when:
            sub += "\n" + db_date_text(when, kind)
            if kind == "c":
                row.subtitle.set_tooltip_text(DB_DATE_HELP)
        row.subtitle.set_label(sub)
        row.subtitle.set_no_show_all(False)
        if is_ps_db(db):
            row.add_suffix(self.cache_button(db))
        row.add_suffix(self.download_button(db, folder))
        # Punto verde: su version de PHP es la activa
        active = folder == self.data["active"]
        dot = label("●", "punto-verde" if active else "punto-gris")
        dot.set_tooltip_text("Su versión de PHP está activa" if active else
                             "Su versión de PHP no está activa")
        row.add_prefix(dot)
        if active:
            b = Gtk.Button(label="Elegir como destino",
                           tooltip_text="Elegirla para subir una BBDD")
            b.connect("clicked", lambda *_: self.use_as_destination(db))
            row.add_suffix(b)
        load = Gtk.Button(label="Cargar proyecto", sensitive=not self.busy,
                          tooltip_text="Cargar en lampp-%s (PHP %s)"
                                       % (folder, inst["php"]))
        load.connect("clicked", lambda *_: self.on_load_project(db, inst))
        row.add_suffix(load)
        return row

    def use_as_destination(self, db):
        self.imp.update(db=db)
        self.build_databases()
        self.toast("BBDD de destino: %s" % db)
        # Baja hasta el formulario de carga
        GLib.idle_add(lambda: (self.imp_btn.grab_focus(), False)[1])

    # ------------------------------------------------- cargar el proyecto de una base
    def on_load_project(self, db, inst):
        def got(rc, out):
            link, current, projects, saved, create = "", "", [], {}, False
            vlinks = {}
            for f in parse_lines(out):
                if f[0] == "E" and len(f) >= 3:
                    link, current = f[1], f[2]
                    create = len(f) >= 4 and f[3] == "N"
                elif f[0] == "P" and len(f) >= 4:
                    projects.append({"name": f[1], "db": f[2], "php": f[3]})
                elif f[0] == "R" and len(f) >= 3:
                    saved[f[1]] = f[2]
                elif f[0] == "V" and len(f) >= 4:
                    vlinks[(f[1], f[2])] = f[3]
            # (el vínculo de la versión manda sobre el de todas; "" = desvinculada en ella)
            if (db, inst["folder"]) in vlinks:
                saved[db] = vlinks[(db, inst["folder"])]
            if rc != 0 or not projects:
                message(self.win, "No se han podido leer los proyectos",
                        "No se ha podido leer la carpeta /opt/htdocs.", Gtk.MessageType.WARNING)
            elif not link:
                message(self.win, "No hay un vhost para cargar proyectos",
                        "Ningún vhost de /opt/config/httpd-vhosts.conf tiene como DocumentRoot "
                        "un enlace de /opt/htdocs (como web.local).", Gtk.MessageType.WARNING)
            else:
                self.project_dialog(db, inst, link, current, projects, saved, create)
            return False
        run_quick(["gui-proyectos"], got)

    def project_dialog(self, db, inst, link, current, projects, saved, create=False):
        """Carga el proyecto de la base en la versión del resultado pulsado (inst). Si la carpeta
        se sabe (elegida antes o la única cuya configuración usa la base), sin preguntar; si no,
        se elige de una lista. Solo avisa cuando hay que cambiar de versión o crear el vhost."""
        by_name = {p["name"]: p for p in projects}
        matches = [p["name"] for p in projects if p["db"] == db]
        folder, manual = None, False
        if saved.get(db) in by_name:
            folder = saved[db]
        elif len(matches) == 1 and saved.get(db) != "":
            folder = matches[0]
        else:
            folder = self.pick_project_folder(db, projects, matches)
            manual = True
        if not folder:
            return
        self.do_load_project(folder, db, inst, link, create, remember=manual)

    def do_load_project(self, folder, db, inst, link, create, confirm_switch=True, remember=False):
        """Carga una carpeta en una versión. Avisa cuando hay que cambiar de versión (si no se
        acaba de elegir) o crear el vhost."""
        target = inst["folder"]
        act = next((i for i in self.installs() if i["folder"] == self.data["active"]), None)
        where = (", donde está la BBDD %s" % db) if db and db in self.data["dbs"].get(target, []) \
            else ""
        notes = []
        if target != self.data["active"] and confirm_switch:
            if act:
                notes.append("Se va a cambiar de versión de PHP: se para lampp-%s (PHP %s) y se "
                             "activa lampp-%s (PHP %s)%s."
                             % (act["folder"], act["php"], target, inst["php"], where))
            else:
                notes.append("Se activa lampp-%s (PHP %s)%s." % (target, inst["php"], where))
        if create:
            notes.append("Todavía no hay un vhost para cargar proyectos: se crea %s (http y "
                         "https, con su certificado y su línea en /etc/hosts)." % link)
        if notes:
            title = "¿Cambiar a PHP %s?" % inst["php"] if target != self.data["active"] \
                and confirm_switch else "¿Crear %s?" % link
            if not confirm(self.win, title, "", "Cargar %s" % folder,
                           steps=notes + ["%s apuntará a %s." % (link, folder)]):
                return
        if remember:
            self.remember_project(db, folder, target)
        def loaded(ok_, *_):
            if not ok_:
                return
            # El visor pasa al proyecto nuevo al momento, con sus botones: lo que se acaba de hacer se
            # sabe sin preguntarlo (gui-datos tarda unos segundos; la lectura completa sigue detrás)
            if self.projects is not None:
                self.projects = dict(self.projects, link=link, current=folder, create=False)
                self.selected_project = folder
            if self.data is not None and target != self.data["active"]:
                self.data = dict(self.data, active=target)
            self.update_project_search()
            # (la lista sube sola hasta arriba, donde está el cargado: sin desplazarla a mano. El visor ya está
            # a la vista, fijo; en la ventana antigua, la página entera)
            GLib.timeout_add(120, lambda: smooth_scroll(getattr(self, "proj_scroll", self.page_projects)) and False)

            def got(_rc, out):
                # Tienda PrestaShop: su dominio queda falseado (se ve en la pestaña Hosts)
                fake = [f[1] for f in parse_lines(out)
                        if f[0] == "F" and len(f) >= 9 and f[3] == folder and f[4] == "1"]
                self.on_hosts_data(_rc, out)
                self.toast("Proyecto cargado: %s → %s (PHP %s)%s"
                           % (link, folder, inst["php"],
                              "  ·  %s falseado (pestaña Hosts)" % fake[0] if fake else ""))
                return False
            run_quick(["gui-hosts"], got)
        self.run_task("Cargando el proyecto %s" % folder, ["cargar-proyecto", folder, target, db],
                      done_text="%s apunta a %s (PHP %s)" % (link, folder, inst["php"]),
                      auto_close=True, env=self.db_pwd.get(target) and
                      {"MYSQL_PWD": self.db_pwd[target]}, on_done=loaded)

    def pick_project_folder(self, db, projects, matches):
        """Lista con buscador de las carpetas de htdocs para elegir la del proyecto de una base."""
        dlg = Gtk.Dialog(title="Cargar proyecto", transient_for=self.win, modal=True,
                         use_header_bar=True)
        dlg.set_default_size(560, -1)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Cargar proyecto", Gtk.ResponseType.ACCEPT), "verde")
        ok.set_sensitive(False)
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=24)
        dlg.get_content_area().add(box)
        box.pack_start(css(label("Proyecto de %s" % db), "title-3"), False, False, 0)
        if len(matches) > 1:
            why = "Hay %d carpetas que usan «%s». Elige la que quieres cargar:" % (
                len(matches), db)
        else:
            why = ("No hay ninguna carpeta cuya configuración use «%s». Elige la del "
                   "proyecto:" % db)
        box.pack_start(label(why, "dim-label", wrap=True, max_width_chars=60), False, False, 0)
        box.pack_start(label("La elección se recuerda para esta BBDD.", "dim-label",
                             "subtitulo"), False, False, 0)
        find = Gtk.SearchEntry(placeholder_text="Buscar una carpeta de htdocs")
        box.pack_start(find, False, False, 0)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE,
                             activate_on_single_click=False), "caja")
        sw = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, min_content_height=260)
        sw.add(lb)
        box.pack_start(sw, False, False, 0)
        # Primero las que usan esta base, luego el resto por nombre
        for p in sorted(projects, key=lambda p: (p["db"] != db, p["name"].lower())):
            sub = ("Usa esta BBDD" if p["db"] == db else
                   "BBDD: %s" % p["db"] if p["db"] else "Sin BBDD detectada")
            if p["php"]:
                sub += "  ·  .php-version %s" % p["php"]
            row = ActionRow(p["name"], sub)
            row.set_selectable(True)
            row.set_activatable(True)
            row.name = p["name"]
            lb.add(row)
        lb.set_filter_func(lambda r: find.get_text().strip().lower() in r.name.lower())
        find.connect("search-changed", lambda *_: lb.invalidate_filter())
        lb.connect("row-selected", lambda _lb, row: ok.set_sensitive(row is not None))
        lb.connect("row-activated", lambda *_: dlg.response(Gtk.ResponseType.ACCEPT))
        box.show_all()
        find.grab_focus()
        resp = run_dialog(dlg)
        row = lb.get_selected_row()
        dlg.destroy()
        return row.name if resp == Gtk.ResponseType.ACCEPT and row is not None else None

    def remember_project(self, db, folder, ver):
        """Guarda en ~/.lvm-instalador/proyectos la carpeta elegida a mano para una base en una
        versión."""
        if SIMULATE:
            return
        err = write_links([(db, ver, folder)])
        if err:
            self.toast("No se ha podido recordar la carpeta: %s" % err)
