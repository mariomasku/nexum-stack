class AppVersiones:
    """Versiones de PHP y cargar un proyecto."""

    # ---------------------------------------------------------- versiones
    def on_close_stray(self, *_):
        self.run_task("Cerrando los procesos que sobran", ["cerrar-procesos"],
                      done_text="Solo queda en memoria la versión montada", auto_close=True,
                      on_done=lambda ok_, *_: self.toast(
                          "Procesos cerrados" if ok_ else "No se han podido cerrar todos"))

    # ------------------------------------------------- cargar un proyecto (Versiones)
    def on_projects_data(self, rc, out):
        p = {"link": "", "current": "", "create": False, "list": [], "saved": {}, "vlinks": {}}
        for f in parse_lines(out):
            if f[0] == "E" and len(f) >= 3:
                p["link"], p["current"] = f[1], f[2]
                p["create"] = len(f) >= 4 and f[3] == "N"
            elif f[0] == "P" and len(f) >= 4:
                p["list"].append({"name": f[1], "db": f[2], "php": f[3],
                                  "kind": f[4] if len(f) > 4 else ""})
            elif f[0] == "R" and len(f) >= 3:
                p["saved"][f[1]] = "|".join(f[2:])
            elif f[0] == "V" and len(f) >= 4:
                p["vlinks"][(f[1], f[2])] = f[3]
        if rc != 0 and not p["list"]:
            p = None
        if p != self.projects:
            old_link = (self.projects or {}).get("link"), (self.projects or {}).get("current")
            self.projects = p
            self.update_project_search()
            # (el registro de errores de Herramientas es el del vhost del proyecto cargado)
            if self.data and old_link != ((p or {}).get("link"), (p or {}).get("current")):
                self.build_tools()
            # (en BBDD, el punto verde va en la BBDD que usa el proyecto cargado)
            if self.data:
                self.build_databases()
            # (y el menú del icono junto al reloj, su web.local)
            if hasattr(self, "nv_tray_update"):
                self.nv_tray_update()
        return False

    def build_project_box(self):
        # Uno de los bloques más usados: su título fuera, como los demás apartados, y debajo el
        # contenedor hundido, con algo más de separación con lo de debajo (Versión activa)
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, margin_bottom=12)
        box = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin_top=6), "hundido")
        head = Gtk.Box(spacing=6)
        head.pack_start(label("Cargar proyecto", "grupo-titulo"), False, False, 0)
        head.pack_start(info_icon(
            "Busca la carpeta de un proyecto de /opt/htdocs y cárgalo: el vhost "
            "(web.local) apunta a ella y se monta la versión de PHP donde está su BBDD. "
            "Si la BBDD está en varias versiones, se pregunta cuál montar. Con «Montar nuevo "
            "proyecto» se clona uno de GitHub y se le crea su BBDD."), False, False, 0)
        outer.pack_start(head, False, False, 0)
        outer.pack_start(box, False, False, 0)
        # «web.local → proyecto», junto al nombre el botón de desmontarlo y, a la derecha,
        # botones de icono (el texto sale al dejar el ratón encima). De derecha a izquierda: su
        # carpeta en Visual Studio Code, su BBDD en phpMyAdmin, su panel de administración
        # (WordPress o PrestaShop) y la web en el navegador
        # (todo el nombre si cabe; si no, cortado por el final)
        self.proj_now = label("", ellipsize=3, max_width_chars=70)

        def icon_button(image, callback):
            b = css(Gtk.Button(valign=Gtk.Align.CENTER, relief=Gtk.ReliefStyle.NORMAL),
                    "boton-proyecto")
            b.set_image(image)
            b.set_always_show_image(True)
            b.connect("clicked", lambda *_: callback())
            return b
        self.proj_open = icon_button(logo("globo", 20), lambda: self.projects and self.projects["link"]
                                     and self.open_uri("http://%s/" % self.projects["link"]))
        self.proj_pma = icon_button(logo("phpmyadmin", 20), self.open_project_pma)
        self.proj_admin = icon_button(logo("wordpress", 20), self.open_project_admin)
        # Desmontar: el vhost deja de apuntar al proyecto (enseña una página vacía)
        self.proj_unload = icon_button(icon("media-eject-symbolic", 18), self.on_unload_project)
        self.proj_now_row = Gtk.Box(spacing=8)
        self.proj_now_row.pack_start(section_icon(("icono", "folder-open-symbolic", "verde-suave"), 16),
                                     False, False, 4)
        name_box = Gtk.Box(spacing=8)
        name_box.pack_start(self.proj_now, False, True, 0)
        name_box.pack_start(self.proj_unload, False, False, 0)
        self.proj_now_row.pack_start(name_box, True, True, 0)
        # El de abrir su carpeta en Visual Studio Code, el último por la derecha (solo si está
        # instalado), con el icono de VS Code
        code = vscode_app()
        self.proj_code = css(Gtk.Button(valign=Gtk.Align.CENTER, relief=Gtk.ReliefStyle.NORMAL),
                             "boton-proyecto")
        if code is not None and code.get_icon() is not None:
            img = Gtk.Image.new_from_gicon(code.get_icon(), Gtk.IconSize.BUTTON)
            img.set_pixel_size(20)
            self.proj_code.set_image(img)
        else:
            self.proj_code.set_label("VS Code")
        self.proj_code.connect("clicked", lambda *_: self.open_in_vscode())
        self.proj_now_row.pack_end(self.proj_code, False, False, 0)
        self.proj_now_row.pack_end(self.proj_pma, False, False, 0)
        self.proj_now_row.pack_end(self.proj_admin, False, False, 0)
        self.proj_now_row.pack_end(self.proj_open, False, False, 0)
        if code is None:
            self.proj_code.set_no_show_all(True)
        self.proj_now_row.show_all()
        self.proj_now_row.set_no_show_all(True)
        box.pack_start(self.proj_now_row, False, False, 0)
        # Aviso en rojo: la versión montada no tiene el proyecto cargado (su BBDD está en otra)
        self.proj_warn = label("", "aviso-rojo", wrap=True)
        self.proj_warn.set_no_show_all(True)
        box.pack_start(self.proj_warn, False, False, 0)
        # Buscador y, a su derecha, «Montar nuevo proyecto» (despliega el asistente)
        # (algo separado de los botones del proyecto, que van justo encima)
        search_row = Gtk.Box(spacing=10, margin_top=16)
        self.proj_entry = css(Gtk.SearchEntry(placeholder_text="Buscar la carpeta del proyecto…"),
                              "buscador")
        self.proj_entry.connect("search-changed", lambda *_: self.update_project_search())
        self.proj_entry.connect("stop-search", lambda e: e.set_text(""))
        search_row.pack_start(self.proj_entry, True, True, 0)
        self.proj_new_btn = css(Gtk.Button(valign=Gtk.Align.CENTER), "verde")
        nb = Gtk.Box(spacing=6)
        nb.pack_start(icon("list-add-symbolic"), False, False, 0)
        nb.pack_start(Gtk.Label(label="Montar nuevo proyecto"), False, False, 0)
        self.proj_new_btn.add(nb)
        self.proj_new_btn.set_tooltip_text("Clonar un proyecto de GitHub")
        self.proj_new_btn.connect("clicked", lambda *_: self.toggle_new_project(True))
        # Replicar: el proyecto en otra versión de PHP (su BBDD copiada con otro nombre y vinculada
        # allí a la carpeta que se elija)
        self.proj_rep_btn = Gtk.Button(valign=Gtk.Align.CENTER)
        rb = Gtk.Box(spacing=6)
        rb.pack_start(icon("edit-copy-symbolic"), False, False, 0)
        rb.pack_start(Gtk.Label(label="Replicar"), False, False, 0)
        self.proj_rep_btn.add(rb)
        self.proj_rep_btn.set_tooltip_text("Replicar en otra versión de PHP")
        self.proj_rep_btn.connect("clicked", lambda *_: self.on_replicate())
        search_row.pack_start(self.proj_rep_btn, False, False, 0)
        search_row.pack_start(self.proj_new_btn, False, False, 0)
        box.pack_start(search_row, False, False, 0)
        self.new_proj_rev = Gtk.Revealer(transition_type=Gtk.RevealerTransitionType.SLIDE_DOWN)
        self.new_proj_rev.add(self.build_new_project())
        # Plegado, oculto del todo: si no, el hueco entre filas del recuadro deja más espacio
        # debajo del buscador que encima de la primera fila
        self.new_proj_rev.set_no_show_all(True)
        self.new_proj_rev.connect("notify::child-revealed", lambda r, _p: r.get_reveal_child()
                                  or r.get_child_revealed() or r.hide())
        box.pack_start(self.new_proj_rev, False, False, 0)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "caja")
        lb.connect("row-activated", on_row_activated)
        lb.set_no_show_all(True)
        box.pack_start(lb, False, False, 0)
        self.proj_results = lb
        outer.show_all()
        return outer

    # --- Montar nuevo proyecto: asistente de tres pasos (clon, versión de PHP y BBDD) ---

    def build_new_project(self):
        w = {}
        self.np = w
        outer = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14), "asistente")
        w["step"] = label("", "asistente-paso")
        outer.pack_start(w["step"], False, False, 0)
        w["stack"] = Gtk.Stack(transition_type=Gtk.StackTransitionType.SLIDE_LEFT_RIGHT,
                               vhomogeneous=False, interpolate_size=True)
        outer.pack_start(w["stack"], False, False, 0)

        # 1. Repositorio y carpeta: de los de GitHub (pestaña Repositorios) o la dirección de otro
        p1 = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        p1.pack_start(label("¿De qué repositorio de GitHub? (escribe parte de su nombre)"), False, False, 0)
        w["repo"] = Gtk.Entry(placeholder_text="nombre del repositorio…", primary_icon_name="system-search-symbolic")
        w["repo"].connect("changed", lambda *_: self.new_project_search())
        w["repo"].connect("activate", lambda *_: self.new_project_first_hit())
        w["repo"].connect("key-press-event", self.new_project_search_key)
        p1.pack_start(w["repo"], False, False, 0)
        # Los resultados, en la propia ventana: el desplegable de Gtk.EntryCompletion es una ventana
        # emergente aparte, que en Wayland puede no llegar a verse
        w["repo_hits"] = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "caja")
        w["repo_hits"].connect("row-activated", on_row_activated)
        w["repo_hits"].set_no_show_all(True)
        p1.pack_start(w["repo_hits"], False, False, 0)
        w["repo_note"] = label("", "dim-label", wrap=True)
        p1.pack_start(w["repo_note"], False, False, 0)
        p1.pack_start(label("o la dirección de otro repositorio (GitHub u otro servidor):"), False, False, 0)
        w["url"] = Gtk.Entry(placeholder_text="https://github.com/usuario/repositorio.git")
        p1.pack_start(w["url"], False, False, 0)
        p1.pack_start(label("Carpeta en /opt/htdocs:"), False, False, 0)
        w["folder"] = Gtk.Entry(placeholder_text="nombre-del-proyecto")
        p1.pack_start(w["folder"], False, False, 0)
        p1.pack_start(label("Se clona con tu usuario (sin sudo). Los de la lista, por SSH con tu clave; "
                            "una dirección https de un privado de GitHub, GitLab o Bitbucket se prueba sola "
                            "por SSH.", "dim-label", wrap=True), False, False, 0)
        w["err1"] = label("", "aviso-rojo", wrap=True)
        p1.pack_start(w["err1"], False, False, 0)
        w["stack"].add_named(p1, "1")
        w["folder_auto"] = True

        def url_changed(*_):
            name = re.sub(r"\.git$", "", w["url"].get_text().strip().rstrip("/").split("/")[-1].split(":")[-1])
            name = re.sub(r"[^A-Za-z0-9._-]", "-", name).lstrip(".-")[:100]
            if w["folder_auto"]:
                w["setting"] = True
                w["folder"].set_text(name)
                w["setting"] = False
            self.new_project_check()

        def folder_changed(*_):
            if not w.get("setting"):
                w["folder_auto"] = not w["folder"].get_text()
            self.new_project_check()
        w["url"].connect("changed", url_changed)
        w["folder"].connect("changed", folder_changed)

        # 2. Versión de PHP
        p2 = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        p2.pack_start(label("¿En qué versión de PHP quieres crear el proyecto?"), False, False, 0)
        w["versions"] = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        p2.pack_start(w["versions"], False, False, 0)
        w["stack"].add_named(p2, "2")

        # 3. BBDD nueva y volcado
        p3 = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        p3.pack_start(label("Nombre de la BBDD nueva:"), False, False, 0)
        w["db"] = Gtk.Entry(placeholder_text="wp_proyecto")
        w["db"].connect("changed", lambda *_: self.new_project_check())
        p3.pack_start(w["db"], False, False, 0)
        p3.pack_start(label("Volcado que se sube a la BBDD (.sql, .sql.gz o .zip):"), False, False, 0)
        w["file"] = Gtk.FileChooserButton(title="Elige el volcado de la BBDD",
                                          action=Gtk.FileChooserAction.OPEN)
        flt = Gtk.FileFilter()
        flt.set_name("Volcados (.sql, .sql.gz, .zip)")
        for pat in ("*.sql", "*.sql.gz", "*.zip", "*.SQL", "*.GZ", "*.ZIP"):
            flt.add_pattern(pat)
        w["file"].add_filter(flt)
        w["file"].connect("file-set", lambda *_: self.new_project_check())
        p3.pack_start(w["file"], False, False, 0)
        p3.pack_start(label("Si no eliges ninguno, la BBDD se crea vacía. El volcado se carga con "
                            "la carga protegida (con el usuario de la BBDD y sin DEFINER).",
                            "dim-label", wrap=True), False, False, 0)
        w["err3"] = label("", "aviso-rojo", wrap=True)
        p3.pack_start(w["err3"], False, False, 0)
        w["stack"].add_named(p3, "3")

        # 4. El dominio de producción: falsearlo en este equipo (como en Dominios y hosts) o no
        p4 = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        row4 = Gtk.Box(spacing=10)
        row4.pack_start(label("¿Falsear su dominio de producción en este equipo?", valign=Gtk.Align.CENTER), False, False, 0)
        w["fake"] = Gtk.Switch(active=False, valign=Gtk.Align.CENTER)
        w["fake"].connect("notify::active", lambda *_: self.new_project_check())
        row4.pack_end(w["fake"], False, False, 0)
        p4.pack_start(row4, False, False, 0)
        p4.pack_start(label("Dominio de producción:"), False, False, 0)
        w["domain"] = Gtk.Entry(placeholder_text="midominio.com")
        w["domain"].connect("changed", lambda *_: self.new_project_check())
        p4.pack_start(w["domain"], False, False, 0)
        p4.pack_start(label("Falseado, el navegador abre el proyecto en local con su dominio de verdad (con su "
                            "certificado), como en Dominios y hosts: lo que necesitan las tiendas PrestaShop y "
                            "los WordPress con el dominio en su BBDD. Si no, se abre en web.local.",
                            "dim-label", wrap=True), False, False, 0)
        w["err4"] = label("", "aviso-rojo", wrap=True)
        p4.pack_start(w["err4"], False, False, 0)
        w["stack"].add_named(p4, "4")

        # Botones: Cancelar a la izquierda; Atrás y Siguiente (o Montar proyecto) a la derecha
        nav = Gtk.Box(spacing=8)
        cancel = Gtk.Button(label="Cancelar")
        cancel.connect("clicked", lambda *_: self.toggle_new_project(False))
        nav.pack_start(cancel, False, False, 0)
        w["next"] = css(Gtk.Button(label="Siguiente"), "verde")
        w["next"].connect("clicked", lambda *_: self.new_project_go(1))
        nav.pack_end(w["next"], False, False, 0)
        w["back"] = Gtk.Button(label="Atrás")
        w["back"].connect("clicked", lambda *_: self.new_project_go(-1))
        nav.pack_end(w["back"], False, False, 0)
        outer.pack_start(nav, False, False, 0)
        return outer

    def toggle_new_project(self, show):
        w = self.np
        if show:
            w["repo"].set_text("")
            w["repo_note"].set_label("")
            w["fake"].set_active(False)
            w["domain"].set_text("")
            w["url"].set_text("")
            w["folder"].set_text("")
            w["folder_auto"] = True
            self.new_project_repos()
            w["db"].set_text("")
            w["db_auto"] = True
            w["file"].unselect_all()
            w["version"] = None
            w["stack"].set_visible_child_name("1")
            # (show_all no le llega: tiene no_show_all)
            self.new_proj_rev.get_child().show_all()
            self.new_proj_rev.show()
            self.new_project_check()
            self.proj_entry.set_text("")
        self.new_proj_rev.set_reveal_child(show)
        self.proj_new_btn.set_sensitive(not show)
        if show:
            GLib.idle_add(w["repo"].grab_focus)

    def new_project_page(self):
        return int(self.np["stack"].get_visible_child_name() or "1")

    def new_project_check(self):
        """Comprueba el paso en el que está el asistente: activa Siguiente y explica lo que falta."""
        w = self.np
        page = self.new_project_page()
        titles = {1: "Paso 1 de 4: el repositorio", 2: "Paso 2 de 4: versión de PHP",
                  3: "Paso 3 de 4: BBDD nueva", 4: "Paso 4 de 4: dominio de producción"}
        w["step"].set_label(titles[page])
        w["back"].set_visible(page > 1)
        w["next"].set_label("Montar proyecto" if page == 4 else "Siguiente")
        ok, err = True, ""
        if page == 1:
            url, folder = w["url"].get_text().strip(), w["folder"].get_text().strip()
            host, path = r"[A-Za-z0-9][A-Za-z0-9.-]*", r"[A-Za-z0-9_~][A-Za-z0-9._~/-]*"
            url_ok = bool(re.fullmatch(r"https://%s(:[0-9]{1,5})?/%s" % (host, path), url)
                          or re.fullmatch(r"git@%s:%s" % (host, path), url)
                          or re.fullmatch(r"ssh://git@%s(:[0-9]{1,5})?/%s" % (host, path), url))
            if not url:
                ok = False
            elif not url_ok:
                ok, err = False, "La dirección no es válida: usa https://… o git@servidor:usuario/repositorio.git"
            elif not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9._-]{0,99}", folder) or folder == ".lvm-sin-proyecto":
                ok, err = False, ("Pon un nombre de carpeta: letras sin acentos, números, punto, _ y -"
                                  if folder else "")
            elif os.path.lexists(os.path.join(HTDOCS, folder)):
                ok, err = False, "Ya existe /opt/htdocs/%s: elige otro nombre" % folder
            w["err1"].set_label(err)
            w["err1"].set_visible(bool(err))
        elif page == 2:
            ok = bool(w.get("version"))
        else:
            db = w["db"].get_text().strip()
            have = self.data["dbs"].get(w.get("version") or "", []) if self.data else []
            if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_-]{0,63}", db):
                ok, err = False, ("El nombre de la BBDD solo puede llevar letras sin acentos, números, _ y -"
                                  if db else "")
            elif db.lower() in (d.lower() for d in have):
                ok, err = False, "lampp-%s ya tiene una BBDD %s: elige otro nombre" % (w["version"], db)
            w["err3"].set_label(err)
            w["err3"].set_visible(bool(err))
        if page == 4:
            dom = w["domain"].get_text().strip().lower()
            w["domain"].set_sensitive(w["fake"].get_active())
            ok, err = True, ""
            if w["fake"].get_active() and not re.fullmatch(r"[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+", dom):
                ok, err = False, ("Dominio no válido (por ejemplo: midominio.com)" if dom else "")
            w["err4"].set_label(err)
            w["err4"].set_visible(bool(err))
        w["next"].set_sensitive(ok and not self.busy)

    def new_project_go(self, step):
        w = self.np
        page = self.new_project_page() + step
        if page == 5:
            self.new_project_run()
            return
        page = max(1, page)
        if page == 2:
            clear(w["versions"])
            insts = sorted(self.installs(), key=lambda i: [int(x) for x in re.findall(r"\d+", i["php"])],
                           reverse=True)
            if not insts:
                w["versions"].pack_start(label("No hay ninguna versión instalada: instala una en "
                                               "esta pestaña.", "aviso-rojo", wrap=True), False, False, 0)
            first = None
            for inst in insts:
                text = "PHP %s  ·  lampp-%s%s" % (inst["php"], inst["folder"],
                                                  "  (activa)" if inst["folder"] == self.data["active"] else "")
                rb = Gtk.RadioButton.new_with_label_from_widget(first, text)
                first = first or rb
                rb.connect("toggled", lambda b, f=inst["folder"]: b.get_active() and
                           (w.__setitem__("version", f), self.new_project_check()))
                w["versions"].pack_start(rb, False, False, 0)
                if inst["folder"] == (w.get("version") or self.data["active"]):
                    rb.set_active(True)
            if insts and not w.get("version"):
                w["version"] = insts[0]["folder"]
                first.set_active(True)
            w["versions"].show_all()
        if page == 3 and w.get("db_auto", True) and not w["db"].get_text():
            base = re.sub(r"[^a-z0-9_]", "_", w["folder"].get_text().strip().lower()).strip("_")[:40]
            w["db"].set_text(("wp_" + base) if base else "")
        w["stack"].set_visible_child_name(str(page))
        self.new_project_check()

    def new_project_run(self):
        w = self.np
        url, folder = w["url"].get_text().strip(), w["folder"].get_text().strip()
        version, db = w["version"], w["db"].get_text().strip()
        dump = w["file"].get_filename() or ""
        args = ["montar-proyecto", url, folder, version, db] + ([dump] if dump else [])
        domain = w["domain"].get_text().strip().lower() if w["fake"].get_active() else ""

        def faked(ok, *_):
            if ok:
                self.toast("%s, con %s falseado en este equipo" % (folder, domain))

        def done(ok, *_):
            if ok:
                self.toggle_new_project(False)
                self.toast("Proyecto nuevo montado: %s en lampp-%s con la BBDD %s" % (folder, version, db))
                # (después, si se ha pedido, su dominio de producción falseado)
                if domain:
                    GLib.idle_add(lambda: self.run_task("Falseando %s para %s" % (domain, folder),
                                                        ["nuevo-dominio", domain, folder], auto_close=True,
                                                        done_text="%s falseado: se abre en local" % domain,
                                                        on_done=faked) and False)
        self.run_task("Montando el proyecto %s" % folder, args, progress=True,
                      done_text="%s está clonado, cargado en lampp-%s y con su BBDD %s" % (folder, version, db),
                      on_done=done)

    def new_project_repo(self, full, web, kind):
        """Repositorio elegido de la lista de GitHub: su dirección SSH (con tu clave), su carpeta y, si su web
        es la de producción, su dominio para el paso 4 (y, en una tienda, falsearlo)."""
        w = self.np
        w["url"].set_text("git@github.com:%s.git" % full)
        dom = re.sub(r"^https?://", "", (web or "").strip().lower()).split("/")[0].split(":")[0]
        if re.fullmatch(r"[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+", dom):
            w["domain"].set_text(dom)
            w["fake"].set_active(kind == "ps")
        w["repo_note"].set_label("Se clona por SSH, con tu clave: git@github.com:%s.git%s" % (
            full, ("  ·  web: %s" % dom) if dom else ""))

    def new_project_search(self):
        """Al escribir en el buscador del paso 1: hasta NP_REPOS_HITS resultados debajo. Un repositorio
        pegado (botón de copiar de Repositorios) o escrito entero queda elegido."""
        w = self.np
        if w.get("repo_setting"):
            return
        text = w["repo"].get_text().strip()
        q = repo_query(text)
        rows = self.np_repos or []
        # (si se cambia lo escrito tras elegir uno, deja de estar elegido)
        if w.get("repo_picked") and q != w["repo_picked"]:
            w["repo_picked"] = None
            w["url"].set_text("")
            self.np_repos_show()
        hits = w["repo_hits"]
        clear(hits)
        exact = next((r for r in rows if r[0].lower() == q), None)
        if exact:
            self.new_project_pick(exact)
            return
        # (la dirección de un repositorio que no está en la lista, a su campo)
        if re.match(r"(git@|ssh://|https?://)", text):
            w["url"].set_text(text)
            q = ""
        if len(q) < 2:
            self.new_project_hits_shown(False)
            return
        found = [r for r in rows if q in r[0].lower()]
        for r in found[:NP_REPOS_HITS]:
            row = Gtk.ListBoxRow()
            row.on_activate = lambda r=r: self.new_project_pick(r)
            line = Gtk.Box(spacing=12, margin_start=12, margin_end=12, margin_top=6, margin_bottom=6)
            line.pack_start(label(r[0], ellipsize=3), False, True, 0)
            if r[1]:
                line.pack_end(label(r[1], "dim-label", "subtitulo", ellipsize=3, max_width_chars=30), False, True, 0)
            row.add(line)
            hits.add(row)
        if len(found) > NP_REPOS_HITS or not found:
            row = Gtk.ListBoxRow(activatable=False, selectable=False, can_focus=False)
            row.add(label("Y %d más: sigue escribiendo" % (len(found) - NP_REPOS_HITS) if found else
                          "Ningún repositorio con «%s»" % text if self.np_repos is not None else "Cargando la lista…",
                          "dim-label", margin_start=12, margin_end=12, margin_top=6, margin_bottom=6))
            hits.add(row)
        self.new_project_hits_shown(True)

    def new_project_hits_shown(self, show):
        hits = self.np["repo_hits"]
        if show:
            for row in hits.get_children():
                row.show_all()
            hits.show()
        else:
            hits.hide()
        # (la ventana del asistente, al alto de lo que enseña)
        top = hits.get_toplevel()
        if top is getattr(self, "np_dialog", None):
            top.resize(top.get_size()[0], 1)

    def new_project_pick(self, repo):
        w = self.np
        w["repo_setting"] = True
        w["repo"].set_text(repo[0])
        w["repo"].set_position(-1)
        w["repo_setting"] = False
        w["repo_picked"] = repo[0].lower()
        clear(w["repo_hits"])
        self.new_project_hits_shown(False)
        self.new_project_repo(*repo)

    def new_project_first_hit(self):
        """Intro en el buscador: el primer resultado."""
        for row in self.np["repo_hits"].get_children():
            if getattr(row, "on_activate", None):
                row.on_activate()
                return

    def new_project_search_key(self, _entry, event):
        """Flecha abajo en el buscador: a los resultados."""
        if event.keyval != Gdk.KEY_Down:
            return False
        rows = self.np["repo_hits"].get_children()
        if self.np["repo_hits"].get_visible() and rows and getattr(rows[0], "on_activate", None):
            rows[0].grab_focus()
            return True
        return False

    def new_project_repos(self):
        """La lista de repositorios de GitHub para el paso 1: ya está en memoria (np_repos_load, al abrir
        el programa). Si hace rato que no se pregunta a GitHub, se pone al día por detrás."""
        self.np_repos_show()
        if self.np_repos is None:
            self.np_repos_load(cache=True)
        if time.time() - self.np_repos_when > NP_REPOS_FRESH:
            self.np_repos_load()

    def np_repos_load(self, cache=False):
        """Los repositorios para el buscador de Nuevo proyecto, en segundo plano: los de la última vez
        (cache: al momento) o los de GitHub. Sin conexión, se queda la lista que había."""
        if cache and self.np_repos_when:
            return
        if not cache:
            if self.np_repos_busy:
                return
            self.np_repos_busy = True

        def got(_rc, out):
            rows = []
            for f in parse_lines(out):
                if f[0] == "R" and len(f) >= 11:
                    kind = "ps" if "prestashop" in f[6] + f[2] else "wp" if "wordpress" in f[6] + f[2] else ""
                    rows.append((f[1], f[7], kind))
            if not cache:
                self.np_repos_busy = False
                if rows:
                    self.np_repos_when = time.time()
            # (una respuesta de la última vez que llega tarde no pisa la de GitHub)
            if rows and not (cache and self.np_repos_when):
                self.np_repos = rows
            elif self.np_repos is None:
                self.np_repos = []
            self.np_repos_show()
            return False
        run_quick(["repos", "--todos"] + (["--cache"] if cache else []), got)

    def np_repos_show(self):
        """Debajo del buscador, cuántos hay, si el asistente ya existe."""
        w = getattr(self, "np", None)
        if not w or self.np_repos is None:
            return
        # (con uno ya elegido, debajo sigue lo que se va a clonar)
        if not w["url"].get_text():
            n = len(self.np_repos)
            w["repo_note"].set_label("%d repositorios de GitHub" % n if n else
                                     "Sin la lista de GitHub (conéctalo en Configuración, GitHub): escribe la dirección abajo")
            # (si ya se estaba escribiendo cuando ha llegado)
            if w["repo"].get_text().strip():
                self.new_project_search()

    def on_unload_project(self):
        p = self.projects
        if not p or not p.get("current"):
            return
        name = os.path.basename(p["current"].rstrip("/"))
        self.run_task("Desmontando el proyecto %s" % name, ["desmontar-proyecto"],
                      done_text="%s ya no apunta a %s" % (p["link"], name), auto_close=True)

    def link_of(self, db, ver):
        """Carpeta vinculada a una BBDD en una versión: la de esa versión ("" = ninguna), la de
        todas las versiones (como se guardaba hasta la 1.50) o None si no tiene."""
        p = self.projects or {}
        if (db, ver) in p.get("vlinks", {}):
            return p["vlinks"][(db, ver)]
        return p.get("saved", {}).get(db)

    def project_pairs(self, x):
        """(versión, BBDD) de un proyecto: las BBDD vinculadas a su carpeta en cada versión o, si no
        tiene ninguna, la de su configuración en las versiones donde no es de otro proyecto."""
        if not self.data:
            return []
        pairs = [(i, db) for i in self.installs() for db in self.data["dbs"].get(i["folder"], [])
                 if self.link_of(db, i["folder"]) == x["name"]]
        if pairs or not x["db"]:
            return pairs
        return [(i, x["db"]) for i in self.installs() if x["db"] in self.data["dbs"].get(i["folder"], [])
                and self.link_of(x["db"], i["folder"]) is None]

    def project_base(self, x):
        """Base de un proyecto que no está en ninguna versión (para los textos): la recordada para su
        carpeta o la de su configuración."""
        pairs = self.project_pairs(x)
        if pairs:
            return pairs[0][1]
        dbs = {db for i in self.installs() for db in self.data["dbs"].get(i["folder"], [])}
        saved = [db for db, f in (self.projects or {}).get("saved", {}).items() if f == x["name"]]
        for db in reversed(saved):
            if db in dbs:
                return db
        return x["db"] or (saved[-1] if saved else "")

    def update_project_search(self):
        if getattr(self, "proj_results", None) is None or not self.data:
            return
        p = self.projects
        now = ""
        esc = GLib.markup_escape_text
        if p and p["current"]:
            now = '%s → <span foreground="%s"><b>%s</b></span>' % (
                esc(p["link"]), GREEN, esc(os.path.basename(p["current"].rstrip("/"))))
        # Solo a dónde apunta el enlace: el vhost y la flecha, en el color normal, y el proyecto en
        # verde y negrita (sin título delante, para que quepa el nombre entero junto al botón de
        # desmontar). Desmontado: el vhost sin proyecto
        if now:
            self.proj_now.set_markup(now)
            # (si no cabe entero, al dejar el ratón encima)
            self.proj_now.set_tooltip_text("%s → %s" % (p["link"], p["current"].rstrip("/")))
        elif p and p.get("link") and not p.get("create"):
            self.proj_now.set_tooltip_text(None)
            self.proj_now.set_markup('%s → <i>ningún proyecto</i>  <span alpha="55%%">(enseña una página vacía)</span>'
                                     % esc(p["link"]))
        for b in (self.proj_unload, self.proj_open, self.proj_pma, self.proj_admin):
            b.set_visible(bool(now))
        self.proj_code.set_visible(bool(now) and vscode_app() is not None)
        # La versión montada no tiene la BBDD del proyecto cargado: aviso en rojo
        warn = ""
        if now and self.data and self.data.get("active"):
            db = self.loaded_project_db()
            x = self.loaded_project_entry()
            pairs = self.project_pairs(x) if x else []
            if db and not any(i["folder"] == self.data["active"] for i, _ in pairs) \
                    and db not in self.data["dbs"].get(self.data["active"], []):
                where = ["lampp-%s (%s)" % (i["folder"], d) for i, d in pairs]
                warn = ("El proyecto vinculado a %s no está disponible para esa versión: lampp-%s no "
                        "tiene su BBDD %s%s." % (p["link"], self.data["active"], db,
                                                 (" (está en %s; vuelve a cargarlo para cambiar de versión)"
                                                  % ", ".join(where)) if where else ""))
        self.proj_warn.set_label(warn)
        self.proj_warn.set_visible(bool(warn))
        if now:
            name = os.path.basename(p["current"].rstrip("/"))
            self.proj_open.set_tooltip_text("Abrir http://%s/ en el navegador" % p["link"])
            db = self.loaded_project_db()
            self.proj_pma.set_sensitive(bool(db))
            self.proj_pma.set_tooltip_text("Abrir la BBDD %s en phpMyAdmin" % db if db
                                           else "No se sabe qué BBDD usa %s" % name)
            kind, admin = self.loaded_project_admin()
            self.proj_admin.set_image(logo("prestashop" if kind == "ps" else "wordpress", 16))
            self.proj_admin.set_sensitive(bool(admin))
            self.proj_admin.set_tooltip_text(
                ("Abrir el back office de PrestaShop (http://%s/%s/)" if kind == "ps"
                 else "Abrir el panel de WordPress (http://%s/%s/)") % (p["link"], admin)
                + " con el administrador de pruebas ya escrito (local@local.test, contraseña local): "
                  "solo hay que pulsar Entrar" if admin
                else "%s no es un WordPress ni una tienda PrestaShop con su carpeta de administración" % name)
            self.proj_code.set_tooltip_text(
                "Abrir %s en Visual Studio Code (si ya está abierto, se trae su ventana delante)" % name)
            self.proj_unload.set_tooltip_text(
                "Desmontar %s: %s deja de apuntar a él y enseña una página vacía" % (name, p["link"]))
        self.proj_now_row.set_visible(bool(p and p.get("link") and not p.get("create")))
        lb, q = self.proj_results, self.proj_entry.get_text().strip().lower()
        clear(lb)
        if not q or not p:
            lb.hide()
            return
        hits = [x for x in p["list"] if q in x["name"].lower()]
        hits.sort(key=lambda x: (not x["name"].lower().startswith(q), x["name"].lower()))
        if not hits:
            lb.add(ActionRow("Ningún proyecto con «%s» en el nombre" % q,
                             "Las carpetas de /opt/htdocs (sin las ocultas ni los enlaces)."))
        limit = 30
        for x in hits[:limit]:
            lb.add(self.project_hit_row(x, q))
        if len(hits) > limit:
            lb.add(ActionRow("Y %d más…" % (len(hits) - limit),
                             "Escribe más letras del nombre para encontrarlo."))
        for row in lb.get_children():
            row.show_all()
        lb.show()

    def project_hit_row(self, x, q):
        name = x["name"]
        row = ActionRow(name)
        kind = {"wp": "wordpress", "ps": "prestashop"}.get(x["kind"])
        row.add_prefix(section_icon(("logo", kind) if kind else ("icono", "folder-symbolic", ""), 16))
        start = name.lower().find(q)
        esc = GLib.markup_escape_text
        row.title.set_markup("%s<b>%s</b>%s" % (esc(name[:start]), esc(name[start:start + len(q)]),
                                                esc(name[start + len(q):])))
        pairs = self.project_pairs(x)
        db = self.project_base(x)
        parts = [{"wp": "WordPress", "ps": "PrestaShop"}.get(x["kind"], "")]
        if pairs:
            # (BBDD wp_tienda en lampp-8.4, wp_tienda_8_5 en lampp-8.5.12)
            by = {}
            for i, d in pairs:
                by.setdefault(d, []).append("lampp-%s" % i["folder"])
            parts.append(", ".join("BBDD %s en %s" % (d, ", ".join(v)) for d, v in by.items()))
        elif db:
            parts.append("BBDD %s" % db)
            parts.append("no está en ninguna versión")
        else:
            parts.append("sin BBDD detectada")
        if x["php"]:
            parts.append(".php-version %s" % x["php"])
        row.subtitle.set_label("  ·  ".join(t for t in parts if t))
        row.subtitle.set_no_show_all(False)
        current = self.projects and os.path.basename(self.projects["current"].rstrip("/")) == name
        if current:
            row.add_title_tag(label("Cargado", "texto-activa", "subtitulo"))
        lk = Gtk.Button(tooltip_text="Vincular %s con su BBDD"
                        % name, relief=Gtk.ReliefStyle.NONE, sensitive=not self.busy and bool(self.data))
        lk.add(icon("insert-link-symbolic"))
        lk.connect("clicked", lambda *_: self.on_link_project(x))
        row.add_suffix(lk)
        b = Gtk.Button(label="Cargar", sensitive=not self.busy)
        b.connect("clicked", lambda *_: self.on_load_folder(x))
        row.add_suffix(b)
        return row

    def on_link_project(self, x):
        """Elige con qué BBDD va la carpeta en cada versión (o con ninguna): Cargar proyecto monta
        la versión con esa BBDD. Cada BBDD es de un solo proyecto en cada versión."""
        installs = sorted(self.installs(), key=lambda i: ver_tuple(i["php"]), reverse=True)
        if not installs:
            return
        pairs = self.project_pairs(x)
        name = x["name"]
        dlg = Gtk.Dialog(title="Vincular BBDD", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(600, -1)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Guardar", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=24)
        dlg.get_content_area().add(box)
        box.pack_start(css(label("BBDD de %s en cada versión" % name, wrap=True, max_width_chars=60),
                           "title-3"), False, False, 0)
        box.pack_start(label("Cargar proyecto monta la versión con la BBDD que elijas aquí. Con "
                             "«Ninguna», la carpeta deja de ir con esa versión (la BBDD no se toca). "
                             "Cada BBDD es de un solo proyecto en cada versión: si era de otro, "
                             "deja de serlo.", "dim-label", wrap=True, max_width_chars=60),
                         False, False, 0)
        grid = Gtk.Grid(column_spacing=12, row_spacing=8, margin_top=6)
        combos = []
        for n, i in enumerate(installs):
            dbs = sorted(self.data["dbs"].get(i["folder"], []), key=str.lower)
            mine = [d for j, d in pairs if j["folder"] == i["folder"]]
            grid.attach(label("PHP %s  (lampp-%s)" % (i["php"], i["folder"])), 0, n, 1, 1)
            c = Gtk.ComboBoxText(hexpand=True)
            c.append("@ninguna", "— Ninguna —")
            for d in dbs:
                other = self.link_of(d, i["folder"])
                c.append(d, d if other in (None, "", name) else "%s  (de %s)" % (d, other))
            c.set_active_id(mine[0] if mine else "@ninguna")
            narrow(c, 34)
            if not dbs:
                c.set_sensitive(False)
            grid.attach(c, 1, n, 1, 1)
            combos.append((i, c, mine))
        box.pack_start(grid, False, False, 0)
        box.show_all()
        resp = run_dialog(dlg)
        chosen = [(i, "" if c.get_active_id() in (None, "@ninguna") else c.get_active_id(), mine)
                  for i, c, mine in combos]
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return
        changes = []
        for i, new, mine in chosen:
            ver = i["folder"]
            for d in mine:
                if d != new:
                    changes.append((d, ver, ""))
            # (también la que solo venía de su configuración: así queda fija)
            if new and self.link_of(new, ver) != name:
                changes.append((new, ver, name))
        if not changes:
            return
        if SIMULATE:
            self.toast("[simulación] no se cambian los vínculos")
            return
        err = write_links(changes)
        if err:
            message(self.win, "No se han podido guardar los vínculos", err, Gtk.MessageType.ERROR)
            return
        self.toast("Vínculos de %s guardados" % name)
        run_quick(["gui-proyectos"], self.on_projects_data)

    def on_load_folder(self, x):
        p = self.projects
        if not p or not p["link"]:
            message(self.win, "No hay un vhost para cargar proyectos",
                    "Ningún vhost de /opt/config/httpd-vhosts.conf tiene como DocumentRoot un "
                    "enlace de /opt/htdocs (como web.local).", Gtk.MessageType.WARNING)
            return
        db = self.project_base(x)
        cands = self.project_pairs(x)
        found = bool(cands)
        if not cands:
            cands = [(i, db) for i in self.installs()]
        if not cands:
            message(self.win, "No hay ninguna versión instalada",
                    "Instala una versión de PHP en esta pestaña para cargar proyectos.",
                    Gtk.MessageType.WARNING)
            return
        asked = len(cands) > 1
        if asked:
            chosen = self.pick_version(x, db, cands, found)
            if not chosen:
                return
        else:
            chosen = cands[0]
        inst, db = chosen
        self.do_load_project(x["name"], db, inst, p["link"], p["create"], confirm_switch=not asked)

    def pick_version(self, x, db, cands, found):
        """Versión de PHP (y su BBDD) en la que se carga un proyecto, cuando puede ir en varias.
        cands: (versión, BBDD). Devuelve la elegida o None."""
        active = self.data["active"]
        pre = next((c for c in cands if c[0]["folder"] == active), None) or \
            next((c for c in cands if x["php"] and c[0]["php"].startswith(x["php"])), None) or cands[0]
        dlg = Gtk.Dialog(title="Cargar proyecto", transient_for=self.win, modal=True,
                         use_header_bar=True)
        dlg.set_default_size(520, -1)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Cargar proyecto", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=24)
        dlg.get_content_area().add(box)
        ask = ("¿Qué versión del proyecto y de PHP quieres?" if found else
               "¿Con qué versión de PHP quieres cargar el proyecto?")
        box.pack_start(css(label(ask, wrap=True, max_width_chars=60), "title-3"), False, False, 0)
        if found:
            why = ("%s está vinculado a una BBDD en %d versiones de PHP y cada una guarda su "
                   "propia copia. Elige cuál cargar (cámbialas con el botón de vincular):"
                   % (x["name"], len(cands)))
        elif db:
            why = ("La BBDD de %s (%s) no está en ninguna versión: súbela después en la "
                   "pestaña BBDD. Elige con qué versión de PHP cargarlo:" % (x["name"], db))
        else:
            why = ("No se sabe qué BBDD usa %s. Elige con qué versión de PHP cargarlo:"
                   % x["name"])
        box.pack_start(label(why, "dim-label", wrap=True, max_width_chars=60), False, False, 0)
        first, radios = None, []
        for c in cands:
            i, cdb = c
            notes = []
            if found:
                notes.append("BBDD %s" % cdb)
            if i["folder"] == active:
                notes.append("la activa")
            if x["php"] and i["php"].startswith(x["php"]):
                notes.append("la de su .php-version")
            text = "PHP %s  (lampp-%s)%s" % (i["php"], i["folder"],
                                            "  ·  " + ", ".join(notes) if notes else "")
            rb = Gtk.RadioButton.new_from_widget(first)
            lines = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            lines.pack_start(label(text), False, False, 0)
            when = db_date_text(*self.data["dbdate"].get((i["folder"], cdb), (0, ""))) if found else ""
            if when:
                lines.pack_start(label("BBDD: " + when, "dim-label", "subtitulo"),
                                 False, False, 0)
            rb.add(lines)
            first = first or rb
            # Cada opción en su tarjeta; la elegida, con el borde verde
            opt = css(Gtk.Box(), "opcion")
            opt.pack_start(rb, True, True, 0)
            rb.connect("toggled", lambda b, o=opt: (o.get_style_context().add_class("elegida")
                                                     if b.get_active() else
                                                     o.get_style_context().remove_class("elegida")))
            rb.set_active(c is pre)
            if c is pre:
                css(opt, "elegida")
            radios.append((rb, c))
            box.pack_start(opt, False, False, 0)
        box.show_all()
        resp = run_dialog(dlg)
        chosen = next((i for rb, i in radios if rb.get_active()), None)
        dlg.destroy()
        return chosen if resp == Gtk.ResponseType.ACCEPT else None

    def build_versions(self):
        clear(self.ver_box)
        d = self.data
        if d["unregistered"]:
            box, lb = group("Hay un XAMPP sin registrar",
                            "/opt/lampp es una instalación de XAMPP completa y no un enlace. "
                            "Regístrala con un nombre (por ejemplo 8.2.12) para poder gestionarla "
                            "junto a las demás.")
            row = ActionRow("XAMPP en /opt/lampp")
            b = css(Gtk.Button(label="Registrar…"), "verde")
            b.connect("clicked", self.on_register)
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)

        if d["stray"]:
            # Procesos de otras versiones que se quedaron en memoria al cambiar (el lampp de XAMPP
            # solo cierra lo que encuentra en sus .pid)
            box, lb = group("Hay procesos de otras versiones en memoria",
                            "Solo debería estar en memoria la versión montada%s. Ocupan memoria y "
                            "pueden bloquear los puertos 80, 443 y 3306."
                            % (" (lampp-%s)" % d["active"] if d["active"] else ""))
            row = ActionRow("Procesos que sobran", d["stray"])
            row.subtitle.set_line_wrap(True)
            row.subtitle.set_ellipsize(0)
            b = css(Gtk.Button(label="Cerrarlos"), "destructive-action")
            b.connect("clicked", self.on_close_stray)
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)
        if d["dbsys"]:
            # Tablas del sistema de MariaDB antiguas: el servidor llena su registro de errores
            ver, size = d["dbsys"]
            box, lb = group("Tablas del sistema de MariaDB antiguas",
                            "Las tablas del sistema (mysql.*) son de una MariaDB anterior y el servidor "
                            "escribe un error cada vez que las usa: su registro de errores no para de "
                            "crecer. Repararlas las pone al día con el mysql_upgrade de la versión, sin "
                            "tocar las BBDD de los proyectos (si quieres, después de guardar una copia en "
                            "~/nexum-backups), y vacía el registro si es grande.")
            row = ActionRow("MariaDB de lampp-%s" % ver, "Registro de errores: %s" % fmt_size(size))
            b = css(Gtk.Button(label="Repararlas"), "verde")
            b.connect("clicked", lambda *_, v=ver: self.on_repair_dbsys(v))
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)
        old_pma = [i for i in self.installs() if pma_outdated(i["php"], i["pma"])]
        if old_pma:
            box, lb = group("phpMyAdmin antiguo",
                            "Estas versiones traen un phpMyAdmin con fallos de seguridad que ya están "
                            "corregidos. Actualizarlo pone el más nuevo que admite su PHP, con la "
                            "misma configuración; el anterior queda en phpmyadmin.anterior.")
            row = ActionRow("phpMyAdmin con fallos corregidos después",
                            ", ".join("lampp-%s (%s)" % (i["folder"], i["pma"]) for i in old_pma))
            b = css(Gtk.Button(label="Actualizarlos"), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Actualizando phpMyAdmin", ["actualizar-phpmyadmin", "--todas"],
                done_text="phpMyAdmin actualizado", auto_close=True))
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)
        if d["unsecured"]:
            # Versiones a las que les falta algo de lo que pone el gestor (cerradas a la red y lo de
            # cada repaso de seguridad): se protegen todas a la vez
            box, lb = group("A algunas versiones les faltan protecciones",
                            "Les falta algo de lo que pone el gestor: solo para este equipo (si se "
                            "arrancan a mano, escucharían en toda la red), phpMyAdmin cerrado a otras "
                            "webs, MariaDB sin acceso a los ficheros del equipo... Protegerlas lo pone, "
                            "como en la activa; pide la contraseña de administrador.")
            row = ActionRow("Versiones sin proteger",
                            ", ".join("lampp-%s" % v for v in d["unsecured"]))
            b = css(Gtk.Button(label="Protegerlas"), "verde")
            b.connect("clicked", self.on_secure_all)
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)

        if d["certs"] or d["cas"]:
            # Certificados de proyectos en los que confía todo el equipo (no solo el navegador para
            # ese dominio): con su clave se podría falsificar cualquier web real en este equipo
            why = []
            if any(r == "falta" for _, r in d["certs"]):
                why.append("no tienen el certificado (Apache no arrancaría)")
            if any(r == "sistema" for _, r in d["certs"]):
                why.append("están en /etc/ssl/certs, donde el sistema los da por buenos para cualquier web")
            if any(r == "ca" for _, r in d["certs"]):
                why.append("son de CA (con su clave se puede firmar cualquier web)")
            if d["cas"]:
                why.append("los firma una CA de confianza sin límite de dominios (%s) cuya clave puede "
                           "leer cualquier programa tuyo, como el PHP de una web" % ", ".join(d["cas"]))
            box, lb = group("Certificados en los que confía todo el equipo",
                            "Los certificados https de estos proyectos " + "; ".join(why) + ". "
                            "Arreglarlos les pone uno propio, que solo vale para su dominio, y quita "
                            "esa confianza. Después el navegador avisará una vez en cada proyecto: "
                            "acepta el aviso. Pide la contraseña de administrador.")
            names = [dom for dom, _ in d["certs"]]
            row = ActionRow("Proyectos con https", ", ".join(names[:6]) + (" y %d más" % (len(names) - 6)
                                                                        if len(names) > 6 else "")
                            if names else "Ninguno: solo la CA")
            b = css(Gtk.Button(label="Arreglarlos"), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Arreglando los certificados", ["arreglar-certificados"],
                done_text="Certificados arreglados"))
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)
        if d["untrusted"]:
            # Proyectos https cuyo certificado propio no acepta el navegador: avisa al abrirlos y las
            # herramientas que lo manejan (Claude in Chrome) no pueden pasar del aviso
            box, lb = group("El navegador avisa al abrir estos proyectos",
                            "Chrome y Firefox no aceptan todavía su certificado: sale «La conexión no "
                            "es privada» y las herramientas que manejan el navegador (como Claude in "
                            "Chrome) no pueden abrirlos. Confiar hace que acepte el certificado propio "
                            "de cada proyecto, que solo vale para su dominio: no sirve para falsificar "
                            "ninguna otra web. El de una tienda con dominio real, solo mientras esté "
                            "falseada en /etc/hosts: al dejar de falsearla, deja de aceptarlo (con su "
                            "clave se podría suplantar la web de verdad). Después, si el navegador "
                            "estaba abierto, ciérralo y vuelve a abrirlo.")
            names = d["untrusted"]
            row = ActionRow("Proyectos que avisan en el navegador",
                            ", ".join(names[:6]) + (" y %d más" % (len(names) - 6) if len(names) > 6 else ""))
            b = css(Gtk.Button(label="Confiar"), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Confiando en los certificados de los proyectos", ["confiar-certificados"],
                done_text="El navegador acepta los certificados de los proyectos"))
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)
        if d["stale"]:
            # Tiendas con dominio real cuyo certificado aun acepta el navegador y ya no estan falseadas
            # (hosts cambiado a mano): con su clave se podria suplantar la web de verdad
            box, lb = group("El navegador acepta webs reales que ya no están falseadas",
                            "El navegador aceptaba su certificado mientras estaban falseadas en "
                            "/etc/hosts. Ya no lo están, así que el navegador va a la web de verdad, y "
                            "con la clave de ese certificado (Apache la tiene en memoria) se la podría "
                            "suplantar. Quitar hace que deje de aceptarlo. Después, si el navegador "
                            "estaba abierto, ciérralo y vuelve a abrirlo.")
            names = d["stale"]
            row = ActionRow("Webs reales que acepta el navegador",
                            ", ".join(names[:6]) + (" y %d más" % (len(names) - 6) if len(names) > 6 else ""))
            b = css(Gtk.Button(label="Quitar"), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Quitando los certificados de las webs reales", ["confiar-certificados", "--quitar"],
                done_text="El navegador ya no acepta esos certificados"))
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)

        # Lo primero: cargar un proyecto (el bloque se crea una vez y se conserva al redibujar,
        # para no perder lo escrito en el buscador)
        if getattr(self, "proj_box", None) is None:
            self.proj_box = self.build_project_box()
        parent = self.proj_box.get_parent()
        if parent:
            parent.remove(self.proj_box)
        self.ver_box.pack_start(self.proj_box, False, False, 0)
        self.update_project_search()

        if not d["launcher"] and not SIMULATE:
            box, lb = group()
            row = ActionRow("Icono en el menú de aplicaciones",
                            "Crea el acceso «Nexum Dev Stack» para abrir esta ventana.")
            b = Gtk.Button(label="Crear")
            b.connect("clicked", self.on_create_launcher)
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)

        act = next((i for i in d["installs"] if i["folder"] == d["active"]), None)
        box, lb = group("Versión activa")
        if act:
            row = ActionRow("PHP %s" % act["php"], "/opt/lampp → lampp-%s" % act["folder"])
            row.add_prefix(label("●", "punto-verde" if d["running"] else "punto-gris"))
            row.add_suffix(label("En marcha" if d["running"] else "Parada", "dim-label"))
            # Parar = lvm disable: para y quita el enlace /opt/lampp, asi que php (enlazado a
            # /opt/lampp/bin/php) deja de responder. Tambien con la version ya parada
            actions = [("view-refresh-symbolic", "Reiniciar", "reiniciar", "icono-azul")] \
                if d["running"] else \
                [("media-playback-start-symbolic", "Arrancar", "arrancar", "icono-verde")]
            actions.append(("media-playback-stop-symbolic",
                            "Parar y desactivar (como lvm disable): php deja de responder hasta "
                            "que actives una versión", "parar", "icono-rojo"))
            for ic, tip, cmd, color in actions:
                # (más grandes que los demás botones de icono: son los que más se usan)
                b = css(Gtk.Button(tooltip_text=tip, relief=Gtk.ReliefStyle.NONE), color, "control-grande")
                b.add(icon(ic, 24))
                b.connect("clicked", self.on_control, cmd, tip)
                row.add_suffix(b)
            web = Gtk.Button(label="Abrir localhost", sensitive=d["running"])
            web.connect("clicked", lambda *_: self.open_uri("http://localhost/"))
            row.add_suffix(web)
        else:
            row = ActionRow("Ninguna versión activa",
                            "Activa una de las versiones instaladas para usarla.")
            row.add_prefix(label("●", "punto-gris"))
        lb.add(row)
        self.ver_box.pack_start(box, False, False, 0)

        self.sg_tag = Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL)
        self.sg_btn = Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL)
        if d["installs"]:
            box, lb = fold_group("Instaladas", "Pulsa una versión para ver sus componentes. "
                                 "Pulsa el título para plegar o desplegar la lista.",
                                 "instaladas" not in self.folded,
                                 lambda on: self.remember_fold("instaladas", on),
                                 plural(len(d["installs"]), "versión", "versiones"))
            for inst in d["installs"]:
                lb.add(self.version_row(inst))
        else:
            box, lb = group("Instaladas")
            row = ActionRow("No hay ninguna versión instalada",
                            "Instala la primera más abajo.")
            lb.add(row)
        self.ver_box.pack_start(box, False, False, 0)
        # Debajo, instalar nuevas versiones (se rellena aparte, al consultar php.net)
        parent = self.inst_box.get_parent()
        if parent:
            parent.remove(self.inst_box)
        self.ver_box.pack_start(self.inst_box, False, False, 0)
        self.ver_box.show_all()

    def version_row(self, inst):
        folder = inst["folder"]
        is_active = folder == self.data["active"]
        exp = ExpanderRow("PHP %s" % inst["php"], "/opt/lampp-%s" % folder,
                          on_toggle=lambda on, f=folder: self.remember(f, on))
        # Fecha de publicación de su PHP, junto a la versión (como en Instalar)
        php_date = self.php_dates.get(folder)
        if php_date and php_date[0] == inst["php"]:
            tag = label(fmt_day(php_date[1]), "dim-label", "fecha-version")
            tag.set_tooltip_text("Publicada en php.net el %s" % fmt_day(php_date[1]))
            exp.add_title_tag(tag)
        kind = inst["kind"]
        # Icono: el de XAMPP si es (o va sobre) un XAMPP; el de PHP si es una pila propia
        if kind != "propia":
            for c in exp.prefix.get_children():
                exp.prefix.remove(c)
            exp.add_prefix(section_icon(("logo", "xampp"), 16))
        tag = label({"XAMPP": "XAMPP", "propia": "Pila propia"}.get(kind, "Sobre XAMPP"),
                    "tag", "dim-label", xalign=0.5)
        self.sg_tag.add_widget(tag)
        exp.add_suffix(tag)
        if is_active:
            b = css(Gtk.Button(label="Activa", can_focus=False), "verde")
        else:
            b = Gtk.Button(label="Activar")
            b.connect("clicked", self.on_activate_version, folder)
        self.sg_btn.add_widget(b)
        exp.add_suffix(b)

        dbs = len(self.data["dbs"].get(folder, []))
        db_text = plural(dbs, "propia", "propias") if inst["owner"] == folder else \
            "usa las de lampp-%s" % inst["owner"]
        for name, val, spec in [
                ("Apache", inst["apache"], ("logo", "apache")),
                ("MariaDB", inst["mariadb"], ("logo", "mariadb")),
                ("ProFTPD", inst["ftp"], ("icono", "folder-remote-symbolic", "")),
                ("Perl", inst["perl"], ("logo", "perl")),
                ("phpMyAdmin", inst["pma"], ("logo", "phpmyadmin")),
                ("BBDD", db_text, ("icono", "drive-multidisk-symbolic", ""))]:
            r = ActionRow(name)
            # (su propio icono, en lugar del que pondría la fila por su título)
            for c in r.prefix.get_children():
                r.prefix.remove(c)
            r.add_prefix(section_icon(spec, 16))
            if name == "phpMyAdmin" and pma_outdated(inst["php"], inst["pma"]):
                r.add_title_tag(label("antiguo", "estado", "seguridad"))
                up = Gtk.Button(label="Actualizar", tooltip_text="Actualizar phpMyAdmin")
                up.connect("clicked", lambda *_, f=folder: self.on_update_pma(f))
                r.add_suffix(up)
            r.add_suffix(label(val, "dim-label"))
            exp.add_row(r)

        actions = Gtk.Box(spacing=8, halign=Gtk.Align.END, margin=10)
        branch = inst["php"].rsplit(".", 1)[0]
        if kind != "XAMPP" and branch == folder:
            up = Gtk.Button(label="Actualizar")
            up.connect("clicked", self.on_update, folder)
            actions.pack_start(up, False, False, 0)
        rm = css(Gtk.Button(label="Desinstalar…", sensitive=not inst["blocker"]),
                 "destructive-action")
        if inst["blocker"]:
            rm.set_tooltip_text(inst["blocker"])
        rm.connect("clicked", self.on_remove, inst)
        actions.pack_start(rm, False, False, 0)
        exp.add_row(actions)
        if folder in self.expanded:
            exp.set_expanded(True)
        return exp

    def remember(self, folder, on):
        (self.expanded.add if on else self.expanded.discard)(folder)

    def remember_fold(self, key, opened):
        """Guarda qué apartados están plegados (siguen así al volver a abrir la ventana)."""
        (self.folded.discard if opened else self.folded.add)(key)
        try:
            os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
            with open(FOLDED_FILE, "w", encoding="utf-8") as f:
                f.write("".join(k + "\n" for k in sorted(self.folded)))
        except OSError:
            pass

    # acciones
    def run_task(self, title, args, **kw):
        bg = getattr(self, "bg_task", None)
        if self.busy and bg is not None and not bg.finished:
            # (otra tarea en segundo plano: no van dos a la vez, que tocarían lo mismo)
            self.toast("Hay una tarea en marcha: espera a que acabe")
            bg.to_front()
            return None
        self.busy = True
        user_done = kw.pop("on_done", None)

        def done(ok, task, p):
            self.busy = False
            if user_done:
                user_done(ok, task, p)
            self.reload(branches=kw_reload)
        kw_reload = kw.pop("reload_branches", False)
        return Task(self, title, args, on_done=done, **kw)

    def on_control(self, _btn, cmd, what):
        folder = self.data["active"]
        if cmd == "parar":
            self.run_task("Parando y desactivando lampp-%s" % folder, ["disable"],
                          done_text="lampp-%s parada y desactivada" % folder, auto_close=True)
            return
        texts = {"arrancar": "Versión activa arrancada", "reiniciar": "Versión activa reiniciada"}
        self.run_task("%s lampp-%s" % (what, folder), [cmd], done_text=texts[cmd], auto_close=True)

    def on_vhosts(self, *_):
        """Los vhosts son del administrador (Apache los lee como root al arrancar): se edita una
        copia en ~/.lvm-instalador y, al pulsar Aplicar, el script la comprueba, la escribe con sudo
        (guardando antes la anterior en ~/nexum-backups, si está el ajuste) y recarga Apache."""
        if not self.data:
            return
        path = self.data["vhosts"]
        real = os.path.realpath(path)
        if not os.path.isfile(real):
            message(self.win, "No se encuentra el fichero de vhosts",
                    "%s no existe en la versión activa." % path, Gtk.MessageType.WARNING)
            return
        copy = os.path.join(LOG_DIR, "httpd-vhosts.conf")
        try:
            os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
            shutil.copyfile(real, copy)
        except OSError as exc:
            message(self.win, "No se ha podido leer %s" % real, str(exc), Gtk.MessageType.ERROR)
            return
        self.open_text(copy)
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True,
                                message_type=Gtk.MessageType.INFO,
                                buttons=Gtk.ButtonsType.NONE, text="Editar vhosts")
        dlg.format_secondary_text(
            "Los vhosts (%s) son del administrador: Apache los lee como root al arrancar. Se abre "
            "una copia (%s) en el editor de textos.\n\nHaz los cambios, guárdalos y pulsa Aplicar: "
            "se comprueban, %sse escriben los "
            "nuevos (pide la contraseña de sudo) y se recarga Apache. Si Apache no los acepta, se "
            "dejan como estaban." % (real, copy, "se guarda una copia de los actuales en ~/nexum-backups, "
                                     if os.path.exists(COPIES_FILES_FLAG) else ""))
        widen(dlg)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Aplicar", Gtk.ResponseType.ACCEPT), "verde")
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return
        try:
            with open(real, "rb") as a, open(copy, "rb") as b:
                same = a.read() == b.read()
        except OSError:
            same = False
        if same:
            self.toast("No has cambiado nada en los vhosts (¿guardaste los cambios?)")
            return
        self.run_task("Guardando los vhosts", ["vhosts", "--aplicar", copy],
                      done_text="Vhosts actualizados", auto_close=True)

    def on_hosts(self, *_):
        """/etc/hosts es de root: se edita una copia en ~/.lvm-instalador y, al pulsar Aplicar,
        el script la escribe encima con sudo (guardando antes el anterior en ~/nexum-backups, si está el
        ajuste)."""
        src = self.data["hosts"] if self.data else "/etc/hosts"
        copy = os.path.join(LOG_DIR, "hosts")
        try:
            os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
            shutil.copyfile(src, copy)
        except OSError as exc:
            message(self.win, "No se ha podido leer %s" % src, str(exc), Gtk.MessageType.ERROR)
            return
        self.open_text(copy)
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True,
                                message_type=Gtk.MessageType.INFO,
                                buttons=Gtk.ButtonsType.NONE, text="Editar hosts")
        dlg.format_secondary_text(
            "%s es del administrador, así que se abre una copia (%s) en el editor de textos.\n\n"
            "Haz los cambios, guárdalos y pulsa Aplicar: %sse escribe el nuevo (pide la contraseña "
            "de sudo)." % (src, copy, "se guarda una copia del %s actual en ~/nexum-backups y " % src
                           if os.path.exists(COPIES_FILES_FLAG) else ""))
        widen(dlg)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Aplicar", Gtk.ResponseType.ACCEPT), "verde")
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return
        try:
            with open(src, "rb") as a, open(copy, "rb") as b:
                same = a.read() == b.read()
        except OSError:
            same = False
        if same:
            self.toast("No has cambiado nada en %s (¿guardaste los cambios?)" % src)
            return
        self.run_task("Guardando %s" % src, ["hosts", "--aplicar", copy],
                      done_text="%s actualizado" % src, auto_close=True)

    def on_activate_version(self, _btn, folder):
        st, why = (self.data or {}).get("php2shell", {}).get(folder, ("", ""))
        if st == "vulnerable" and not confirm(
                self.win, "lampp-%s es vulnerable a PHP2Shell" % folder,
                "%s. Una petición preparada puede ejecutar código con tu usuario. Mejor actualízala "
                "(menú ⋮ de la versión)." % why,
                "Activar lampp-%s igualmente" % folder, destructive=True):
            return
        self.run_task("Activando lampp-%s" % folder, ["use", folder],
                      done_text="lampp-%s activada" % folder, auto_close=True)

    def on_update(self, btn, folder):
        btn.set_sensitive(False)
        self.toast("Comprobando si hay una versión más nueva…")

        def checked(_rc, out):
            btn.set_sensitive(True)
            res = out.strip().splitlines()[-1].split("|") if out.strip() else ["error"]
            if res[0] == "si":
                self.toast("El paquete lampp-%s se encuentra actualizado" % folder)
            elif res[0] == "no" and len(res) > 1:
                extra = copy_check(UPDATE_COPY_WARN)
                if confirm(self.win, "¿Actualizar lampp-%s?" % folder,
                           "PHP %s con los últimos parches de su rama. La actual sigue funcionando "
                           "mientras se compila (varios minutos)." % res[1],
                           "Actualizar a PHP %s" % res[1], extra=extra):
                    self.run_task("Actualizando lampp-%s" % folder,
                                  ["actualizar", folder] + (["--copia"] if extra.wanted else []),
                                  progress=True, reload_branches=True,
                                  done_text="lampp-%s actualizada a PHP %s" % (folder, res[1]))
            else:
                message(self.win, "No se ha podido comprobar la versión",
                        "No se ha podido consultar php.net. Comprueba la conexión a internet.",
                        Gtk.MessageType.WARNING)
            return False
        run_quick(["gui-al-dia", folder], checked)

    def on_remove(self, _btn, inst):
        folder = inst["folder"]
        own = inst["owner"] == folder
        dbs = self.data["dbs"].get(folder, []) if own else []
        text = "Se borrará la carpeta /opt/lampp-%s (PHP %s). " % (folder, inst["php"])
        if not own:
            text += "Sus BBDD no se tocan: son las de lampp-%s. " % inst["owner"]
        elif dbs:
            text += "Sus %s se borrarán con ella. " % plural(len(dbs), "BBDD propia",
                                                            "BBDD propias")
        text += "Los proyectos de /opt/htdocs y los vhosts no se tocan."

        extra = None
        state = {"copy": False}
        if dbs:
            extra = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            copy = Gtk.CheckButton(label="Guardar antes una copia de sus BBDD en "
                                         "~/nexum-backups", active=False)
            extra.pack_start(copy, False, False, 0)
            warn = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            warn.pack_start(label("Sin copia, las BBDD no se podrán recuperar. "
                                  "Escribe %s para confirmar:" % folder, "error", wrap=True,
                                  max_width_chars=50), False, False, 0)
            entry = Gtk.Entry()
            warn.pack_start(entry, False, False, 0)
            warn.set_no_show_all(True)
            extra.pack_start(warn, False, False, 0)

        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True,
                                message_type=Gtk.MessageType.WARNING,
                                buttons=Gtk.ButtonsType.NONE,
                                text="¿Desinstalar lampp-%s?" % folder)
        dlg.format_secondary_text(text)
        if extra:
            dlg.get_message_area().pack_start(extra, False, False, 0)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Desinstalar", Gtk.ResponseType.ACCEPT), "destructive-action")
        dlg.set_default_response(Gtk.ResponseType.CANCEL)
        if dbs:
            def update(*_):
                state["copy"] = copy.get_active()
                warn.set_visible(not state["copy"])
                for child in warn.get_children():
                    child.show()
                ok.set_sensitive(state["copy"] or entry.get_text().strip() == folder)
            copy.connect("toggled", update)
            entry.connect("changed", update)
            update()
        dlg.show_all()
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return
        args = ["desinstalar", folder] + (["--copia"] if state["copy"] else [])
        self.expanded.discard(folder)
        self.run_task("Desinstalando lampp-%s" % folder, args, reload_branches=True,
                      done_text="lampp-%s desinstalada" % folder
                      + (" (copia en ~/nexum-backups)" if state["copy"] else ""))

    def on_register(self, *_):
        entry = Gtk.Entry(placeholder_text="por ejemplo 8.2.12")
        dlg_ok = confirm(self.win, "Registrar el XAMPP de /opt/lampp",
                         "Pasa a /opt/lampp-<nombre> y comparte htdocs y los vhosts con las demás. "
                         "Nombre de la versión:",
                         "Registrar el XAMPP", extra=entry)
        name = entry.get_text().strip()
        if not dlg_ok or not name:
            return
        if not re.match(r"^[0-9A-Za-z._-]+$", name):
            message(self.win, "Nombre no válido", "Usa solo números, letras, puntos y guiones.")
            return
        self.run_task("Registrando lampp-%s" % name, ["add", name],
                      done_text="XAMPP registrado como lampp-%s" % name)

    def on_clear_downloads(self, size):
        """Configuración, Carpetas: vacía la caché de descargas (es de root: pide la contraseña)."""
        if not confirm(self.win, "¿Vaciar la caché de descargas?",
                       "Las versiones instaladas no se tocan. La próxima instalación descargará todo otra vez.",
                       "Vaciar la caché", destructive=True,
                       steps=["Se borra lo que hay en %s (%s)." % (DL_CACHE_DIR, fmt_size(size)),
                              "Se pide la contraseña de administrador: la carpeta es suya."]):
            return
        self.run_task("Vaciando la caché de descargas", ["descargas", "vaciar"],
                      done_text="Caché de descargas vacía", auto_close=True)

    def on_repair_dbsys(self, ver):
        """Repara las tablas del sistema de MariaDB (reparar-bd-sistema), con copia antes si se marca."""
        extra = copy_check("Sin copia, las tablas del sistema de ahora no se podrán recuperar.")
        if not confirm(self.win, "¿Reparar las tablas del sistema?",
                       "Las BBDD de los proyectos no se tocan.", "Repararlas",
                       steps=["Se ponen al día las tablas del sistema (mysql.*) del MariaDB de lampp-%s con el "
                              "mysql_upgrade de la versión." % ver,
                              "Si el registro de errores es grande, se vacía."], extra=extra):
            return
        self.run_task("Reparando las tablas del sistema de MariaDB",
                      ["reparar-bd-sistema"] + (["--copia"] if extra.wanted else []),
                      done_text="Tablas del sistema de MariaDB al día", auto_close=True)

    def on_clear_copies(self, n, size):
        """Configuración, Carpetas: borra las copias de seguridad (lo de dentro de ~/nexum-backups, no la
        carpeta). Alguna copia de root puede pedir la contraseña."""
        if not confirm(self.win, "¿Borrar las copias de seguridad?",
                       "Las copias borradas no se pueden recuperar.",
                       "Borrar las copias", destructive=True,
                       steps=["Se borra todo lo que hay en ~/nexum-backups: %s (%s). La carpeta se queda, vacía."
                              % (plural(n, "fichero", "ficheros"), fmt_size(size)),
                              "Si alguna copia es del administrador, se pide su contraseña para borrarla."]):
            return
        self.run_task("Borrando las copias de seguridad", ["copias", "vaciar"],
                      done_text="Copias de seguridad borradas", auto_close=True,
                      on_done=lambda *_: self.build_tools())

    def on_copies_files(self, sw, _p):
        """Configuración, Carpetas: guardar o no una copia de los ficheros que cambia el programa por su cuenta
        (hosts, vhosts, configuración de los proyectos)."""
        on = sw.get_active()
        if on == os.path.exists(COPIES_FILES_FLAG):
            return
        task = self.run_task("Encendiendo las copias de los ficheros" if on else "Apagando las copias de los ficheros",
                             ["copias-ficheros", "si" if on else "no"], auto_close=True,
                             done_text="Copias de los ficheros que cambia el programa %s"
                             % ("encendidas" if on else "apagadas"),
                             on_done=lambda *_: self.build_tools())
        if task is None:
            # (otra tarea en marcha: el interruptor vuelve a como está)
            sw.set_active(not on)

    def on_create_launcher(self, *_):
        def done(rc, out):
            self.toast("Icono creado en el menú de aplicaciones" if rc == 0 else
                       "No se ha podido crear el icono")
            self.reload()
            return False
        run_quick(["gui-crear-acceso"], done)
