class AppSubirBajarBD:
    """Descargar, subir o actualizar una base de datos."""

    # ------------------------------------------------- descargar una base de datos
    def on_download_db(self, db, folder):
        d = self.data
        inst = next((i for i in d["installs"] if i["folder"] == folder), None)
        if not inst:
            return
        act = next((i for i in d["installs"] if i["folder"] == d["active"]), None)
        running = bool(act) and d["running"] and act["owner"] == inst["owner"]
        dlg = Gtk.FileChooserDialog(title="Descargar la BBDD %s" % db,
                                    transient_for=self.win, action=Gtk.FileChooserAction.SAVE,
                                    do_overwrite_confirmation=True)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Descargar", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        dlg.set_current_folder(
            GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD)
            or os.path.expanduser("~"))
        dlg.set_current_name("%s-lampp-%s-%s.zip" % (db, folder, time.strftime("%Y%m%d-%H%M")))
        if not running:
            dlg.set_extra_widget(label(
                "lampp-%s no está en marcha: se arranca un MariaDB temporal solo para la copia "
                "(pide la contraseña de sudo)." % folder, "dim-label", wrap=True,
                max_width_chars=60))
        path = dlg.get_filename() if run_dialog(dlg) == Gtk.ResponseType.ACCEPT else None
        dlg.destroy()
        if not path:
            return
        if not re.search(r"(?i)(\.sql(\.gz)?|\.zip)$", path):
            path += ".zip"

        def start(pwd):
            def done(ok, task, _p):
                if ok:
                    task.offer("Abrir la carpeta", lambda: self.open_uri(
                        GLib.filename_to_uri(os.path.dirname(path))))
            self.run_task("Descargando %s" % db, ["exportar-bd", db, path, folder],
                          env={"MYSQL_PWD": pwd} if pwd else None, on_done=done,
                          done_text="Copia de «%s» guardada: %s" % (db, os.path.basename(path)),
                          cancel_text=("¿Cancelar la descarga?",
                                       "No se guarda nada.", "Cancelar la descarga"))
        if running:
            self.check_db_access(start)
        else:
            start(None)

    # ------------------------------------------- subir o actualizar una base de datos
    def build_import(self):
        d = self.data
        act = next((i for i in d["installs"] if i["folder"] == d["active"]), None)
        if act and self.imp["folder"] != act["folder"]:
            # Otra version activa: sus bases son otras
            self.imp.update(db=None, folder=act["folder"])
        box, lb = group("Subir o actualizar una BBDD",
                        "Carga una copia .sql, .sql.gz o .zip en el MariaDB de la versión activa%s. "
                        "Antes se borran todas las tablas de la BBDD de destino (con una copia en "
                        "~/lvm-copias), para que no quede nada de lo anterior. Los .zip se "
                        "descomprimen solos."
                        % (", lampp-%s (MariaDB %s)" % (act["folder"], act["mariadb"])
                           if act else ""))
        if not act:
            lb.add(ActionRow("No hay ninguna versión activa",
                             "Activa una versión en Versiones de PHP para cargar BBDD."))
            return box

        f = self.imp["file"]
        sub = "Ningún fichero elegido"
        if f:
            try:
                sub = "%s  ·  %s" % (os.path.basename(f), fmt_size(os.path.getsize(f)))
            except OSError:
                sub = "%s  ·  ya no existe" % os.path.basename(f)
        row = ActionRow("Fichero SQL", sub)
        if f:
            row.set_tooltip_text(f)
        b = Gtk.Button(label="Elegir…")
        b.connect("clicked", self.on_pick_sql)
        row.add_suffix(b)
        lb.add(row)

        row = ActionRow("BBDD de destino", "En lampp-%s" % act["folder"])
        combo = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
        for db in d["dbs"].get(act["folder"], []):
            combo.append(db, db)
        if self.imp["db"]:
            combo.set_active_id(self.imp["db"])
        if combo.get_active_id() is None:
            self.imp["db"] = None
            combo.append("@ninguna", "Elige una BBDD")
            combo.set_active_id("@ninguna")
        combo.connect("changed", self.on_pick_db)
        row.add_suffix(combo)
        b = Gtk.Button(tooltip_text="Crear una BBDD nueva", valign=Gtk.Align.CENTER)
        b.add(icon("list-add-symbolic"))
        b.connect("clicked", self.on_create_db)
        row.add_suffix(b)
        self.imp_drop_btn = Gtk.Button(tooltip_text="Borrar la BBDD elegida",
                                       valign=Gtk.Align.CENTER, sensitive=bool(self.imp["db"]))
        self.imp_drop_btn.add(icon("user-trash-symbolic"))
        self.imp_drop_btn.connect("clicked", lambda *_: self.on_drop_db(self.imp["db"]))
        row.add_suffix(self.imp_drop_btn)
        lb.add(row)

        # Proyecto de la base: queda como su base y, si es un WordPress, su wp-config.php la usa
        folders = project_folders()
        if self.imp.get("project") not in folders:
            self.imp["project"] = None
        # La primera vez con esta base se propone su proyecto; luego se respeta lo elegido
        if self.imp["db"] and self.imp.get("project_for") != self.imp["db"]:
            self.imp["project"] = guess_project(self.imp["db"], self.data["active"] if self.data else None) or self.imp["project"]
            self.imp["project_for"] = self.imp["db"]
        self.imp_proj_row = ActionRow("Proyecto", self.import_project_hint())
        self.imp_proj_hint = self.imp_proj_row.subtitle
        # Ancho del nombre más largo (hasta 56 letras), para verlo entero al elegirlo
        combo = narrow(Gtk.ComboBoxText(valign=Gtk.Align.CENTER),
                       min(56, max([COMBO_CHARS] + [len(n) for n in folders])))
        combo.append("@ninguno", "Ninguno")
        for name in folders:
            combo.append(name, name)
        combo.set_active_id(self.imp["project"] or "@ninguno")
        combo.connect("changed", self.on_pick_project)
        self.imp_proj_combo = combo
        self.imp_proj_row.add_suffix(combo)
        lb.add(self.imp_proj_row)

        self.imp_btn = css(Gtk.Button(label="Cargar", halign=Gtk.Align.CENTER, margin_top=6),
                           "verde", "pildora")
        self.imp_btn.connect("clicked", self.on_import)
        box.pack_start(self.imp_btn, False, False, 0)
        self.imp_hint = label("", "dim-label", xalign=0.5)
        box.pack_start(self.imp_hint, False, False, 0)
        self.update_import_button()
        return box

    def update_import_button(self):
        db = self.imp["db"]
        hint = ""
        if not self.data["running"]:
            hint = "La versión activa está parada: arráncala en Versiones de PHP."
        elif not self.imp["file"]:
            hint = "Elige el fichero SQL."
        elif not db:
            hint = "Elige la BBDD de destino o crea una con +."
        self.imp_btn.set_sensitive(not hint and not self.busy)
        self.imp_hint.set_label(hint)
        self.imp_hint.set_visible(bool(hint))

    def on_pick_sql(self, *_):
        dlg = Gtk.FileChooserDialog(title="Elegir el fichero SQL", transient_for=self.win,
                                    action=Gtk.FileChooserAction.OPEN)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Elegir", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        flt = Gtk.FileFilter()
        flt.set_name("Copias SQL (.sql, .sql.gz, .zip)")
        for pat in ("*.sql", "*.SQL", "*.sql.gz", "*.SQL.GZ", "*.zip", "*.ZIP"):
            flt.add_pattern(pat)
        dlg.add_filter(flt)
        flt = Gtk.FileFilter()
        flt.set_name("Todos los ficheros")
        flt.add_pattern("*")
        dlg.add_filter(flt)
        start = os.path.dirname(self.imp["file"]) if self.imp["file"] else \
            GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD) or os.path.expanduser("~")
        dlg.set_current_folder(start)
        if run_dialog(dlg) == Gtk.ResponseType.ACCEPT:
            path = dlg.get_filename()
            self.imp["file"] = path
            # Si hay una base que se llama como el fichero (mi_web.sql → mi_web), se propone
            stem = re.sub(r"(?i)(\.sql)?(\.gz|\.zip)?$", "", os.path.basename(path))
            if not self.imp["db"] and stem in self.data["dbs"].get(self.data["active"], []):
                self.imp["db"] = stem
                self.imp["project"] = guess_project(stem, self.data["active"] if self.data else None) or self.imp.get("project")
                self.imp["project_for"] = stem
            elif stem not in self.data["dbs"].get(self.data["active"], []):
                others = self.db_installs(stem)
                if others:
                    self.toast("«%s» está en %s, no en la versión activa" % (
                        stem, ", ".join("lampp-%s" % i["folder"] for i in others)))
        dlg.destroy()
        self.build_databases()

    def import_project_hint(self):
        folder = self.imp.get("project")
        if not folder:
            return "Opcional: si es la BBDD nueva de un proyecto, elige su carpeta."
        what = PROJECT_CONFIG_TEXT.get(project_kind(folder))
        if what:
            return what[:1].upper() + what[1:] + "."
        return "La BBDD queda asociada a esta carpeta (Cargar proyecto la usa)."

    def on_pick_project(self, combo):
        folder = combo.get_active_id()
        self.imp["project"] = None if folder in (None, "@ninguno") else folder
        self.imp["project_for"] = self.imp["db"]
        self.imp_proj_hint.set_label(self.import_project_hint())

    def on_pick_db(self, combo):
        db = combo.get_active_id()
        if db == "@ninguna":
            return
        self.imp["db"] = db
        guess = guess_project(db, self.data["active"] if self.data else None)
        if guess:
            self.imp_proj_combo.set_active_id(guess)
        self.imp["project_for"] = db
        self.imp_drop_btn.set_sensitive(True)
        self.update_import_button()

    def on_import(self, *_):
        db = self.imp["db"]
        path, folder = self.imp["file"], self.data["active"]
        try:
            size = fmt_size(os.path.getsize(path))
        except OSError:
            message(self.win, "No se encuentra el fichero", path, Gtk.MessageType.ERROR)
            return
        text = "Se carga en el MariaDB de lampp-%s. " % folder
        act = next((i for i in self.installs() if i["folder"] == folder), None)
        others = self.db_installs(db, skip_owner=act["owner"] if act else None)
        title = "¿Cargar %s (%s) en %s?" % (os.path.basename(path), size, db)
        ok_label = "Vaciar y cargar"
        if others:
            where = ", ".join("lampp-%s (PHP %s)" % (i["folder"], i["php"]) for i in others)
            title = "«%s» ya existe en %s" % (db, where)
            text = ("¿Quieres introducirla también en lampp-%s%s, la versión activa? Cada versión "
                    "tiene su propio MariaDB: la de %s no se toca.\n\n"
                    % (folder, " (PHP %s)" % act["php"] if act else "", where)
                    + "Fichero: %s (%s).\n\n" % (os.path.basename(path), size))
            ok_label = "Cargar también en lampp-%s" % folder
        text += ("Antes se BORRAN todas las tablas de «%s», para que no quede nada de lo "
                 "anterior. Si tiene alguna, primero se guarda una copia en ~/lvm-copias." % db)
        project = self.imp.get("project")
        if project:
            what = PROJECT_CONFIG_TEXT.get(project_kind(project))
            text += "\n\nDespués, «%s» pasa a ser la BBDD de %s%s." % (
                db, project, ": " + what if what else "")
        if not confirm(self.win, title, text, ok_label, destructive=True):
            return
        self.check_db_access(lambda pwd: self.start_import(path, db, pwd, project))

    # crear y borrar bases de datos (siempre en la version activa)
    def db_env(self):
        pwd = self.db_pwd.get(self.data["active"])
        return {"MYSQL_PWD": pwd} if pwd else None

    def on_create_db(self, *_):
        self.check_db_access(lambda _pwd: self.ask_new_db())

    def ask_new_db(self):
        folder = self.data["active"]
        existing = self.data["dbs"].get(folder, [])
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True,
                                message_type=Gtk.MessageType.QUESTION,
                                buttons=Gtk.ButtonsType.NONE, text="Crear BBDD")
        dlg.format_secondary_text("Se crea vacía en el MariaDB de lampp-%s, con juego de "
                                  "caracteres utf8mb4 (utf8mb4_general_ci)." % folder)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        entry = Gtk.Entry(placeholder_text="nombre_de_la_base", max_length=64,
                          activates_default=True)
        box.pack_start(entry, False, False, 0)
        hint = label("Letras sin acentos, números, _ y -", "dim-label", wrap=True,
                     max_width_chars=50)
        box.pack_start(hint, False, False, 0)
        dlg.get_message_area().pack_start(box, False, False, 0)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Crear", Gtk.ResponseType.ACCEPT), "verde")
        ok.set_sensitive(False)
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)

        def update(*_):
            name = entry.get_text().strip()
            valid = bool(re.match(r"^[A-Za-z0-9_-]{1,64}$", name))
            taken = name in existing or name.lower() in (
                "information_schema", "mysql", "performance_schema", "phpmyadmin", "sys", "test")
            act = next((i for i in self.installs() if i["folder"] == folder), None)
            others = [] if taken or not valid else \
                self.db_installs(name, skip_owner=act["owner"] if act else None)
            if taken:
                hint.set_label("Ya hay una BBDD con ese nombre.")
            elif others:
                hint.set_label("Ya existe en %s. Si sigues, se crea también en lampp-%s."
                               % (", ".join("lampp-%s (PHP %s)" % (i["folder"], i["php"])
                                            for i in others), folder))
            else:
                hint.set_label("Letras sin acentos, números, _ y -")
            ctx = hint.get_style_context()
            (ctx.add_class if taken or (name and not valid) else ctx.remove_class)("error")
            (ctx.add_class if others else ctx.remove_class)("aviso")
            ok.set_sensitive(valid and not taken)
        entry.connect("changed", update)
        dlg.show_all()
        resp = run_dialog(dlg)
        name = entry.get_text().strip()
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return

        def created(rc, out):
            if rc == 0:
                self.imp.update(db=name)
                self.toast("BBDD «%s» creada" % name)
                self.reload()
            else:
                message(self.win, "No se ha podido crear la BBDD", out.strip()[-600:],
                        Gtk.MessageType.ERROR)
            return False
        run_quick(["crear-bd", name], created, env=self.db_env())

    def on_drop_db(self, db):
        if not db:
            return

        def info(rc, out):
            res = [f for f in parse_lines(out) if f[0] == "I"]
            if rc != 0 or not res:
                message(self.win, "No se puede borrar la BBDD", out.strip()[-600:],
                        Gtk.MessageType.ERROR)
            else:
                self.confirm_drop(db, int(res[0][1]), int(res[0][2]))
            return False
        self.check_db_access(lambda _pwd: run_quick(["gui-bd-info", db], info,
                                                    env=self.db_env()))

    def confirm_drop(self, db, tables, size):
        folder = self.data["active"]
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True,
                                message_type=Gtk.MessageType.WARNING,
                                buttons=Gtk.ButtonsType.NONE,
                                text="¿Borrar la BBDD «%s»?" % db)
        state = {"copy": tables > 0}
        if tables:
            dlg.format_secondary_markup(
                "En lampp-%s, con <b>%s</b> (%s). <b>No se puede deshacer.</b>"
                % (folder, plural(tables, "tabla", "tablas"), fmt_size(size)))
        else:
            dlg.format_secondary_text("En lampp-%s, vacía (sin tablas). No se puede deshacer." % folder)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Borrar la BBDD", Gtk.ResponseType.ACCEPT), "destructive-action")
        dlg.set_default_response(Gtk.ResponseType.CANCEL)
        if tables:
            extra = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            copy = Gtk.CheckButton(label="Guardar antes una copia en ~/lvm-copias "
                                         "(se puede volver a cargar)", active=True)
            extra.pack_start(copy, False, False, 0)
            warn = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            warn.pack_start(label("Sin copia, el contenido no se podrá recuperar. "
                                  "Escribe %s para confirmar:" % db, "error", wrap=True,
                                  max_width_chars=50), False, False, 0)
            entry = Gtk.Entry()
            warn.pack_start(entry, False, False, 0)
            extra.pack_start(warn, False, False, 0)
            dlg.get_message_area().pack_start(extra, False, False, 0)

            def update(*_):
                state["copy"] = copy.get_active()
                warn.set_visible(not state["copy"])
                ok.set_sensitive(state["copy"] or entry.get_text().strip() == db)
            copy.connect("toggled", update)
            entry.connect("changed", update)
            dlg.show_all()
            update()
        else:
            dlg.show_all()
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return

        def done(ok_, _task, _p):
            if ok_ and self.imp["db"] == db:
                self.imp.update(db=None)
        self.run_task("Borrando la BBDD %s" % db,
                      ["borrar-bd", db] + (["--copia"] if state["copy"] else []),
                      env=self.db_env(), on_done=done, auto_close=True,
                      done_text="BBDD «%s» borrada" % db
                      + (" (copia en ~/lvm-copias)" if state["copy"] else ""))

    def check_db_access(self, then, retry=False):
        """Comprueba que se puede entrar en el MariaDB activo; si root tiene contraseña la pide."""
        folder = self.data["active"]
        pwd = self.db_pwd.get(folder)
        self.imp_btn.set_sensitive(False)

        def checked(_rc, out):
            self.update_import_button()
            res = (out.strip().splitlines() or ["no|Sin respuesta"])[-1].split("|")
            if res[0] == "ok":
                then(pwd)
            elif res[0] == "clave":
                new = self.ask_db_password(folder, retry=pwd is not None)
                if new is not None:
                    self.db_pwd[folder] = new
                    self.check_db_access(then, retry=True)
            else:
                message(self.win, "No se puede entrar en MariaDB", "|".join(res[1:]),
                        Gtk.MessageType.ERROR)
            return False
        run_quick(["gui-bd-comprobar"], checked, env={"MYSQL_PWD": pwd} if pwd else None)

    def ask_db_password(self, folder, retry=False):
        dlg = Gtk.Dialog(title="Contraseña de MariaDB", transient_for=self.win, modal=True,
                         use_header_bar=True)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Continuar", Gtk.ResponseType.OK), "verde")
        dlg.set_default_response(Gtk.ResponseType.OK)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=20)
        box.pack_start(icon("dialog-password-symbolic", 48), False, False, 0)
        box.pack_start(label("El usuario root del MariaDB de lampp-%s tiene contraseña.\n"
                             "Escríbela para continuar." % folder,
                             xalign=0.5, justify=Gtk.Justification.CENTER), False, False, 0)
        if retry:
            box.pack_start(label("Contraseña incorrecta. Vuelve a intentarlo.", "error",
                                 xalign=0.5), False, False, 0)
        entry = Gtk.Entry(visibility=False, activates_default=True,
                          input_purpose=Gtk.InputPurpose.PASSWORD)
        box.pack_start(entry, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.show_all()
        resp = run_dialog(dlg)
        pwd = entry.get_text()
        dlg.destroy()
        return pwd if resp == Gtk.ResponseType.OK else None

    def start_import(self, path, db, pwd, project=None):
        args = ["importar-bd", path, db] + (["--proyecto", project] if project else [])

        def done(ok, _task, _p):
            if ok:
                self.imp.update(file=None, db=db)

        self.run_task("Cargando %s en %s" % (os.path.basename(path), db), args, progress=True,
                      on_done=done, done_text="BBDD «%s» cargada" % db
                      + (" en %s" % project if project else ""),
                      env={"MYSQL_PWD": pwd} if pwd else None,
                      cancel_text=("¿Cancelar la carga?",
                                   "La BBDD «%s» se queda a medias: tendrá lo que se haya "
                                   "cargado hasta ahora." % db, "Cancelar la carga"))
