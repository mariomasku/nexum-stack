class AppInstalar:
    """Instalar versiones y parches de PHP."""

    # ------------------------------------------------------------ instalar
    def build_install(self):
        clear(self.inst_box)
        self.checks = {}
        if self.branches_error:
            box, lb = group("Instalar nuevas versiones de PHP")
            row = ActionRow("No se han podido consultar las versiones", self.branches_error)
            row.add_prefix(css(icon("dialog-warning-symbolic"), "error"))
            b = Gtk.Button(label="Reintentar")
            b.connect("clicked", self.on_refresh)
            row.add_suffix(b)
            lb.add(row)
            self.inst_box.pack_start(box, False, False, 0)
            self.inst_box.show_all()
            return

        nuevas = sum(1 for f in self.branches if f[0] == "B" and (f + [""] * 8)[6] == "nueva")
        box, lb = fold_group("Instalar nuevas versiones de PHP",
                        "Pulsa el título para plegar o desplegar la lista. "
                        "Cada versión lleva su propio Apache, MariaDB, ProFTPD y Perl, "
                        "compilados para ella, y sus propias BBDD. Según php.net: "
                        "Estable recibe correcciones de errores y de seguridad (la mejor opción "
                        "para proyectos nuevos), Solo seguridad recibe únicamente parches de "
                        "seguridad hasta la fecha indicada y Sin soporte ya no recibe parches.",
                        "instalar" not in self.folded, lambda on: self.remember_fold("instalar", on),
                        plural(nuevas, "versión nueva", "versiones nuevas") if nuevas else "")
        rows = sorted((f for f in self.branches if f[0] == "B"),
                      key=lambda f: [int(x) for x in f[1].split(".")], reverse=True)
        for f in rows:
            _, branch, latest, sup, maria, perl, state, folder = (f + [""] * 8)[:8]
            stack = "Apache 2.4  ·  MariaDB %s  ·  Perl %s" % (maria, perl)
            date, sec = branch_release(f)
            if state == "nueva":
                r = ActionRow("PHP %s" % latest, "%s  ·  → /opt/lampp-%s" % (stack, folder),
                              activatable=True)
                chk = Gtk.CheckButton()
                chk.connect("toggled", self.on_check)
                r.add_prefix(chk)
                r.on_activate = chk.activate
                self.checks["php:" + latest] = (chk, latest)
            else:
                sub = {"instalada": "Ya instalada en /opt/lampp-%s" % folder,
                       "actualizable": "lampp-%s tiene un parche anterior: usa Actualizar en "
                                       "Instaladas" % folder,
                       "existe": "Ya existe /opt/lampp-%s" % folder}.get(state, state)
                r = ActionRow("PHP %s" % latest, sub)
                r.add_prefix(icon("object-select-symbolic" if state == "instalada"
                                  else "dialog-information-symbolic"))
                r.set_sensitive(False)
            # Junto a la versión, la fecha en que se publicó y si es un parche de seguridad
            if date and date != "-":
                r.add_title_tag(label(fmt_day(date), "dim-label", "fecha-version"))
                r.add_title_tag(release_tag(sec))
            st, active_end, security_end = branch_state(f)
            r.add_suffix(state_pill(st, active_end, security_end))
            if st == "security" and security_end:
                r.subtitle.set_label(r.subtitle.get_label()
                                     + "  ·  seguridad hasta %s" % fmt_month(security_end))
            lb.add(r)
        self.inst_box.pack_start(box, False, False, 0)

        box, lb = group("Otras opciones")
        other = ActionRow("Otro parche concreto…",
                          "Una versión anterior de cualquier rama, en su propia carpeta",
                          activatable=True)
        other.add_suffix(icon("go-next-symbolic"))
        other.on_activate = self.on_pick_patch
        lb.add(other)
        for version in self.extra_patches:
            r = ActionRow("PHP %s" % version, "Parche concreto  ·  → /opt/lampp-%s" % version)
            chk = Gtk.CheckButton(active=True)
            chk.connect("toggled", self.on_check)
            r.add_prefix(chk)
            rm = Gtk.Button(tooltip_text="Quitar de la lista", relief=Gtk.ReliefStyle.NONE)
            rm.add(icon("window-close-symbolic"))
            rm.connect("clicked", self.on_drop_patch, version)
            r.add_suffix(rm)
            self.checks["parche:" + version] = (chk, version)
            lb.add(r)
        xampps = [f for f in self.branches if f[0] == "X"]
        if xampps:
            xexp = ExpanderRow("XAMPP oficiales", "Para proyectos antiguos (PHP 7.1 a 8.1). Sin parche posible "
                               "de PHP2Shell: mejor una pila propia",
                               on_toggle=lambda on: self.remember("@xampp", on))
            for f in xampps:
                _, folder, release, php, installed = (f + [""] * 5)[:5]
                if installed == "1":
                    xr = ActionRow("XAMPP %s" % release, "Ya instalado en /opt/lampp-%s" % folder)
                    xr.set_sensitive(False)
                else:
                    xr = ActionRow("XAMPP %s" % release,
                                   "PHP %s  ·  → /opt/lampp-%s  ·  sin parche posible (PHP2Shell)" % (php, folder),
                                   activatable=True)
                    chk = Gtk.CheckButton()
                    chk.connect("toggled", self.on_check)
                    xr.add_prefix(chk)
                    xr.on_activate = chk.activate
                    self.checks["xampp:" + folder] = (chk, folder)
                xexp.add_row(xr)
            if "@xampp" in self.expanded:
                xexp.set_expanded(True)
            lb.add(xexp)
        self.inst_box.pack_start(box, False, False, 0)

        self.install_btn = css(Gtk.Button(halign=Gtk.Align.CENTER), "verde", "pildora")
        self.install_btn.connect("clicked", self.on_install)
        self.inst_box.pack_start(self.install_btn, False, False, 0)
        self.inst_box.show_all()
        self.on_check()

    def selected(self):
        return [key for key, (chk, _v) in self.checks.items() if chk.get_active()]

    def on_check(self, *_):
        n = len(self.selected())
        self.install_btn.set_sensitive(n > 0)
        self.install_btn.set_label("Marca una o más versiones" if n == 0 else
                                   "Instalar %s" % plural(n, "versión", "versiones"))

    def on_drop_patch(self, _btn, version):
        self.extra_patches.remove(version)
        self.build_install()

    def on_pick_patch(self):
        branch_rows = {f[1]: f for f in self.branches if f[0] == "B"}
        branches = sorted(branch_rows, key=lambda b: [int(x) for x in b.split(".")], reverse=True)
        state_names = {"stable": "estable", "security": "solo seguridad", "eol": "sin soporte"}
        dlg = Gtk.Dialog(title="Otro parche de PHP", transient_for=self.win, modal=True,
                         use_header_bar=True)
        dlg.set_default_size(620, 540)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        add = css(dlg.add_button("Añadir", Gtk.ResponseType.OK), "verde")
        add.set_sensitive(False)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=16)
        combo = Gtk.ComboBoxText()
        for b in branches:
            combo.append(b, "PHP %s  (%s)" % (b, state_names.get(branch_state(branch_rows[b])[0], "")))
        top = Gtk.Box(spacing=10)
        top.pack_start(label("Rama:"), False, False, 0)
        top.pack_start(combo, False, False, 0)
        box.pack_start(top, False, False, 0)
        sw = Gtk.ScrolledWindow(vexpand=True)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE,
                             activate_on_single_click=False), "caja")
        sw.add(lb)
        box.pack_start(sw, True, True, 0)
        status = label("", "dim-label")
        box.pack_start(status, False, False, 0)
        box.pack_start(label("Las versiones publicadas en php.net son todas definitivas, pero los "
                             "parches anteriores al último no tienen sus correcciones de "
                             "seguridad: úsalos solo si un proyecto necesita esa versión.",
                             "dim-label", wrap=True, max_width_chars=50), False, False, 0)
        dlg.get_content_area().add(box)
        chosen = {}

        def on_select(_lb, row):
            chosen["v"] = getattr(row, "version", None) if row else None
            add.set_sensitive(bool(chosen.get("v")))
        lb.connect("row-selected", on_select)
        lb.connect("row-activated", lambda _lb, row: getattr(row, "version", None)
                   and dlg.response(Gtk.ResponseType.OK))

        def loaded(rc, out, branch):
            if combo.get_active_id() != branch:
                return False
            clear(lb)
            rows = [f for f in parse_lines(out) if f[0] == "P"]
            if rc != 0 or not rows:
                status.set_label("No se ha podido consultar php.net.")
                return False
            st = branch_state(branch_rows[branch])
            status.set_label("PHP %s: %s" % (branch, {
                "stable": "estable, con correcciones de errores y de seguridad",
                "security": "solo parches de seguridad" + (" hasta %s" % fmt_month(st[2]) if st[2] else ""),
            }.get(st[0], "sin soporte de php.net")))
            for i, f in enumerate(rows):
                _, version, date, folder, state, sec = (f + [""] * 6)[:6]
                if state == "nueva" and version not in self.extra_patches:
                    r = ActionRow("PHP %s" % version, "→ /opt/lampp-%s" % folder)
                    r.version = version if folder == version else None
                    # ActionRow no se puede seleccionar por defecto: estas filas si (y con
                    # doble clic o Intro se añade directamente)
                    r.set_selectable(bool(r.version))
                    r.set_activatable(bool(r.version))
                    if folder != version:
                        # El ultimo parche de la rama va en lampp-X.Y: se marca en la lista principal
                        r.subtitle.set_label("Es la última: márcala en la lista principal")
                        r.set_sensitive(False)
                else:
                    r = ActionRow("PHP %s" % version, "%s" % (
                        "Ya instalada" if state == "instalada" else
                        "Ya en la lista" if version in self.extra_patches else
                        "Ya existe /opt/lampp-%s" % folder))
                    r.version = None
                    r.set_sensitive(False)
                if date and date != "-":
                    r.add_title_tag(label(fmt_day(date), "dim-label", "fecha-version"))
                r.add_title_tag(release_tag(sec))
                if i == 0:
                    r.add_suffix(label("Último", "pastilla", "estable" if st[0] != "eol" else "soporte-no"))
                lb.add(r)
            lb.show_all()
            return False

        def on_branch(*_):
            branch = combo.get_active_id()
            clear(lb)
            add.set_sensitive(False)
            status.set_label("Consultando los parches de PHP %s…" % branch)
            run_quick(["gui-parches", branch], lambda rc, out: loaded(rc, out, branch))
        combo.connect("changed", on_branch)
        dlg.show_all()
        if branches:
            combo.set_active(0)
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp == Gtk.ResponseType.OK and chosen.get("v"):
            self.extra_patches.append(chosen["v"])
            self.build_install()

    def on_install(self, *_):
        sel = self.selected()
        if not sel:
            return
        php = [self.checks[k][1] for k in sel if not k.startswith("xampp:")]
        xampp = [self.checks[k][1] for k in sel if k.startswith("xampp:")]
        names = ["XAMPP %s" % x for x in xampp] + ["PHP %s" % v for v in php]
        text = "Cada PHP se compila aquí (unos minutos). Las versiones instaladas no se tocan."
        if not confirm(self.win, "¿Instalar %s?" % plural(len(names), "versión", "versiones"),
                       text, "Instalar %s" % (names[0] if len(names) == 1 else plural(len(names), "versión", "versiones")),
                       steps=["Se instala %s." % n for n in names]):
            return
        args = ["instalar"]
        if xampp:
            args += ["--xampp", ",".join(xampp)]
        if php:
            args += ["--php", ",".join(php)]
        args.append("--si")
        installed = [k for k in sel]

        def done(ok, task, p):
            if not p:
                return
            good = [item for item, rc in p["results"] if rc == "0"]
            for k in installed:
                if k.startswith("parche:") and any(g.endswith(k.split(":", 1)[1]) for g in good):
                    self.extra_patches = [v for v in self.extra_patches
                                          if v != k.split(":", 1)[1]]
            if len(good) == 1 and not SIMULATE:
                folder = item_folder(good[0])
                task.offer("Activar lampp-%s" % folder,
                           lambda: self.on_activate_version(None, folder))

        self.run_task("Instalando", args, progress=True, reload_branches=True, on_done=done,
                      done_text="Instalación terminada")
