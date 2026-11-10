class NvProyectos:
    """Proyectos: el cargado y la lista de todos."""

    # ------------------------------------------------------------------ Proyectos
    def nv_build_projects_shell(self):
        self.hero_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.proj_page.pack_start(self.hero_box, False, False, 0)
        head = Gtk.Box(spacing=10, margin_top=10)
        t = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        t.pack_start(label("Proyectos", "nv-titulo"), False, False, 0)
        head.pack_start(t, True, True, 0)
        self.nv_search = Gtk.SearchEntry(placeholder_text="Buscar proyecto", width_chars=22, valign=Gtk.Align.CENTER)
        self.nv_search.connect("search-changed", lambda *_: self.nv_list.invalidate_filter())
        self.nv_kind = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
        for k, v in [("all", "Todos"), ("wp", "WordPress"), ("ps", "PrestaShop"), ("", "Otros")]:
            self.nv_kind.append(k or "otros", v)
        self.nv_kind.set_active_id("all")
        self.nv_kind.connect("changed", lambda *_: self.nv_list.invalidate_filter())
        # (en azul, como «Nueva BBDD…»: el asistente de clonar de git, con su versión y su BBDD)
        new = nv_button("list-add-symbolic", "Nuevo proyecto…", "Clonar y montar un repositorio", lambda *_: self.nv_new_project(), "nv-azul")
        for w in (new, self.nv_kind, self.nv_search):
            head.pack_end(w, False, False, 0)
        self.proj_page.pack_start(head, False, False, 0)
        self.nv_list = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "nv-grupo")
        self.nv_list.set_filter_func(self.nv_filter)
        self.nv_list.connect("row-activated", lambda _l, r: r.project is not None and self.nv_select(r.project))
        self.proj_list_page.pack_start(self.nv_list, False, False, 0)
        self.nv_count = label("", "nv-chico", "nv-tenue")
        self.proj_list_page.pack_start(self.nv_count, False, False, 0)

    def nv_filter(self, row):
        x = row.project
        if x is None:
            return True
        q = self.nv_search.get_text().strip().lower()
        k = self.nv_kind.get_active_id()
        # (por el nombre de la carpeta o por el de cualquiera de sus BBDD: «tienda» encuentra
        # wordpress-ejemplo, cuya BBDD es wp_tienda)
        found = not q or q in x["name"].lower() or any(q in db.lower() for db in row.dbs)
        return found and (k == "all" or (k == "otros" and not x["kind"]) or x["kind"] == k)

    def nv_docker_loaded(self, x):
        """Botón Docker del proyecto cargado. Sin Docker, lo primero es instalarlo (o arrancarlo). Si el
        proyecto no está en Docker, se monta (con la versión de PHP que se elija); si está con una
        versión, se arranca; con varias, se pregunta cuál (o se monta con otra versión)."""
        def got(rc, out):
            self.on_docker_data(rc, out)
            d = self.docker or {}
            envs = self.nv_docker_of(x["name"])
            if not d.get("ready") or not d.get("php"):
                installed = d.get("installed")
                if confirm(self.win, "Docker está apagado" if installed else "Docker no está instalado",
                           "Se %s Docker sin root, con tu usuario. Pide la contraseña de administrador."
                           % ("arranca" if installed else "instala"),
                           "Arrancar Docker" if installed else "Instalar Docker"):
                    self.run_task("Arrancando Docker sin root" if installed else "Instalando Docker sin root",
                                  ["docker-instalar"], progress=True, done_text="Docker sin root listo",
                                  on_done=lambda ok, *_: ok and self.nv_docker_loaded(x))
            elif not envs:
                self.nv_docker_loaded_dialog(x)
            elif len(envs) == 1:
                self.nv_docker_mount(envs[0])
            else:
                self.nv_docker_choose(x, envs)
            return False
        run_quick(["gui-docker"], got)

    def nv_docker_add_env(self, x):
        """Añadir entorno en Docker: si ya va con el Apache de Docker, otra versión de PHP; si no, montarlo."""
        web = next((e for e in self.nv_docker_of(x["name"]) if e.get("web")), None)
        if web is not None:
            self.nv_docker_versions(web)
        else:
            self.nv_docker_loaded(x)

    def nv_docker_mount(self, dp):
        """Monta (arranca) un proyecto de Docker y lleva a la pestaña Docker."""
        if dp["state"] in ("marcha", "running"):
            self.show_tab("docker")
            self.toast("%s ya está en marcha en Docker: https://%s" % (dp["folder"], dp["domain"]))
            return

        def done(ok, *_):
            run_quick(["gui-docker"], self.on_docker_data)
            if ok:
                self.show_tab("docker")
        self.run_task("Arrancando %s en Docker (PHP %s)" % (dp["folder"], dp["php"]), ["docker-arrancar", dp["slug"]],
                      done_text="%s en Docker: https://%s" % (dp["folder"], dp["domain"]), auto_close=True, on_done=done)

    def nv_docker_choose(self, x, envs):
        """El proyecto está en Docker con varias versiones de PHP: cuál se monta, u otra nueva."""
        dlg = Gtk.Dialog(title="Docker", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(480, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        box.pack_start(label("¿Qué versión de %s montas?" % x["name"], "nv-titulo", wrap=True), False, False, 0)
        box.pack_start(label("Está en Docker con varias versiones de PHP.", "nv-tenue", wrap=True), False, False, 0)
        group_rb, choice = None, {"v": envs[0]}
        for dp in sorted(envs, key=lambda e: ver_tuple(e["php"]), reverse=True) + [None]:
            opt = css(Gtk.Box(), "opcion")
            text = ("PHP %s  ·  %s%s" % (dp["php"], dp["domain"], "  ·  en marcha" if dp["state"] == "running" else "")
                    if dp else "Otra versión de PHP…")
            rb = Gtk.RadioButton.new_with_label_from_widget(group_rb, text)
            group_rb = group_rb or rb
            rb.connect("toggled", lambda b, o=opt, dp=dp: (o.get_style_context().add_class("elegida"), choice.update(v=dp))
                       if b.get_active() else o.get_style_context().remove_class("elegida"))
            if dp is envs[0]:
                css(opt, "elegida")
            opt.pack_start(rb, True, True, 0)
            box.pack_start(opt, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Montar", Gtk.ResponseType.OK), "nv-azul")
        dlg.show_all()
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp != Gtk.ResponseType.OK:
            return
        if choice["v"] is None:
            self.nv_docker_loaded_dialog(x)
        else:
            self.nv_docker_mount(choice["v"])

    def nv_docker_loaded_dialog(self, x):
        d = self.docker
        act = next((i for i in self.data["installs"] if i["folder"] == self.data["active"]), None) if self.data else None
        # Por defecto, lo mismo que tiene en la versión activa: su rama de PHP, su MariaDB y su BBDD
        php_now = ".".join((act or {}).get("php", "").split(".")[:2])
        maria_now = (act or {}).get("mariadb", "")
        php = php_now if php_now in d["php"] else d["php"][-1]
        maria = next((m for m in d["maria"] if maria_now.startswith(m + ".") or maria_now == m), d["maria"][-1])
        pairs = self.project_pairs(x) if self.data else []
        sources = [("@vacia", "Ninguna: empieza vacía")] + \
            [("%s|%s" % (i["folder"], db), "%s (lampp-%s)" % (db, i["folder"])) for i, db in pairs]
        source = next((k for k, _t in sources if act and k.startswith(act["folder"] + "|")), sources[-1][0])

        dlg = Gtk.Dialog(title="Docker", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(560, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        box.pack_start(label("Montar %s en Docker" % x["name"], "nv-titulo", wrap=True), False, False, 0)
        box.pack_start(label("Se descargan las imágenes que falten y se abre por su dominio. La carpeta y su "
                             "BBDD de LAMPP no se tocan.", "nv-tenue", wrap=True, max_width_chars=60), False, False, 0)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "caja")
        combos = {}
        wp = project_kind(x["name"]) == "wp"
        for key, title, items, current in [("php", "PHP", [(v, "PHP %s" % v) for v in d["php"]], php),
                                           ("maria", "MariaDB", [(v, "MariaDB %s" % v) for v in d["maria"]], maria),
                                           ("source", "BBDD" if wp else "BBDD que se copia", sources, source)] + (
                [("mode", "Cómo", [("vivo", "En vivo: la misma que web.local (sin copias)"),
                                   ("copia", "Una copia en Docker")], "vivo")] if wp else []):
            row = ActionRow(title)
            c = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
            for k, text in items:
                c.append(k, text)
            c.set_active_id(current)
            narrow(c, min(56, max([COMBO_CHARS] + [len(t) for _k, t in items])))
            row.add_suffix(c)
            lb.add(row)
            combos[key] = c
        # (el dominio sale solo: el de la tienda o el de la version de PHP elegida)
        base = docker_slug(x["name"])
        dom_row = ActionRow("Dominio", "…")
        lb.add(dom_row)

        def show_domain(*_):
            dom_row.subtitle.set_label("Con el Apache de Docker (sin LAMPP), por https: " + docker_web_domain(
                {"slug": base, "kind": project_kind(x["name"])}, combos["php"].get_active_id() or ""))
        combos["php"].connect("changed", show_domain)
        show_domain()
        box.pack_start(lb, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Montar en Docker", Gtk.ResponseType.OK), "nv-azul")
        dlg.show_all()
        resp = run_dialog(dlg)
        php, maria, src = (combos[k].get_active_id() for k in ("php", "maria", "source"))
        live = "mode" in combos and combos["mode"].get_active_id() == "vivo"
        dlg.destroy()
        if resp != Gtk.ResponseType.OK or not (php and maria):
            return
        domain = docker_web_domain({"slug": base, "kind": project_kind(x["name"])}, php)
        args = ["docker-nuevo", x["name"], php, maria]
        if src and src != "@vacia" and "|" in src:
            ver, db = src.split("|", 1)
            args += ["--bd", db, "--desde", ver] + (["--en-vivo"] if live else [])

        def done(ok, *_):
            run_quick(["gui-docker"], self.on_docker_data)
            if ok:
                self.show_tab("docker")
        self.run_task("Montando %s en Docker" % x["name"], args, progress=True,
                      done_text="%s en Docker: https://%s" % (x["name"], domain), on_done=done)

    def nv_docker_db_mode(self, p):
        """La BBDD de un WordPress de Docker: en vivo la de una versión LAMPP (la misma que web.local) o su
        copia en la MariaDB común de Docker."""
        x = {"name": p["folder"], "db": p["db"]}
        versions = []
        for i, _db in (self.project_pairs(x) if self.data else []):
            if i["folder"] not in versions:
                versions.append(i["folder"])
        dlg = Gtk.Dialog(title="BBDD", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(560, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        box.pack_start(label("BBDD de %s en Docker" % p["folder"], "nv-titulo", wrap=True), False, False, 0)
        box.pack_start(label("En vivo, Docker usa la misma BBDD que web.local: lo que cambies en un lado se ve en el otro, "
                             "sin copias. Si la MariaDB de esa versión no está en marcha, se arranca solo ella (pide la "
                             "contraseña). La copia de Docker no se borra: se puede volver a ella.",
                             "nv-tenue", wrap=True, max_width_chars=62), False, False, 0)
        combo = Gtk.ComboBoxText()
        for v in versions:
            combo.append("lampp|" + v, "En vivo: la de lampp-%s (la de web.local)" % v)
        combo.append("docker", "Su copia en la MariaDB común de Docker")
        combo.set_active_id("lampp|" + p["lampp"] if p.get("lampp") else "docker")
        if combo.get_active_id() is None:
            combo.set_active(0)
        box.pack_start(combo, False, False, 0)
        if not versions:
            box.pack_start(label("Su BBDD no está en ninguna versión de LAMPP.", "nv-chico", "nv-tenue"), False, False, 0)
        dlg.get_content_area().add(box)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Usarla", Gtk.ResponseType.OK), "nv-azul")
        dlg.show_all()
        resp = run_dialog(dlg)
        choice = combo.get_active_id()
        dlg.destroy()
        if resp != Gtk.ResponseType.OK or not choice or choice == ("lampp|" + p["lampp"] if p.get("lampp") else "docker"):
            return
        args = ["docker-bd", p["slug"]] + (["lampp", choice.split("|", 1)[1]] if choice.startswith("lampp|") else ["docker"])
        self.run_task("BBDD de %s" % p["folder"], args, auto_close=True, done_text="Hecho",
                      on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))

    def dk_url(self, domain):
        """Dirección de una web del Apache de Docker: con el puerto si no es el 443."""
        port = ((self.docker or {}).get("web") or {}).get("https", "443")
        return "https://%s%s" % (domain, "" if port == "443" else ":" + port)

    def dk_pma_url(self, p):
        return self.dk_url(docker_pma_domain()) + "/" if p.get("web") else "http://127.0.0.1:%s/" % p["pma"]

    def nv_docker_copy_pass(self, p):
        """Contraseña de root de la BBDD del contenedor (DB_ROOT_PASS de su .env, solo tuyo), al
        portapapeles: su phpMyAdmin ya no entra solo. En los del Apache de Docker, la de su MariaDB comun."""
        path = os.path.join(LOG_DIR, "docker", ("mariadb-%s" % p["maria"]) if p.get("web") else p["slug"], ".env")
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                pw = next((l.split("=", 1)[1].strip() for l in fh.read(4000).splitlines()
                           if l.startswith("DB_ROOT_PASS=")), "")
        except OSError:
            pw = ""
        if not pw:
            self.toast("No se encuentra la contraseña de %s (%s)" % (p["folder"], path))
            return
        Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(pw, -1)
        if p.get("web"):
            self.toast("Contraseña de root de la MariaDB %s de Docker copiada: en phpMyAdmin, usuario root" % p["maria"])
        else:
            self.toast("Contraseña de root de %s copiada: en su phpMyAdmin, usuario root" % p["folder"])

    def nv_docker_versions(self, p):
        """Versiones de PHP de un proyecto del Apache de Docker: la misma carpeta y la misma BBDD. En
        WordPress van a la vez, cada una con su dominio; una tienda va con un dominio y la que se elija."""
        d = self.docker or {}
        ps = p.get("kind") == "ps"
        dlg = Gtk.Dialog(title="Versiones de PHP", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(560, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        box.pack_start(label("Versiones de PHP de %s" % p["folder"], "nv-titulo", wrap=True), False, False, 0)
        box.pack_start(label(("La tienda guarda su dominio en la BBDD: va con %s y la versión que elijas." % self.dk_url(p["domain"]))
                             if ps else "Todas a la vez, cada una con su dominio, con la misma carpeta y la misma BBDD.",
                             "nv-tenue", wrap=True, max_width_chars=60), False, False, 0)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "caja")
        choice = {}

        def act(args, title, done):
            choice.update(args=args, title=title, done=done)
            dlg.response(Gtk.ResponseType.OK)
        for v in p["versions"]:
            on = v == p["php"]
            row = ActionRow("PHP %s" % v, (self.dk_url(p["domain"]) + ("  ·  la elegida" if on else ""))
                            if ps else self.dk_url(docker_web_domain(p, v)))
            if ps and not on:
                b = Gtk.Button(label="Elegir", valign=Gtk.Align.CENTER, sensitive=not self.busy)
                b.connect("clicked", lambda *_, v=v: act(["docker-php-elegir", p["slug"], v], "%s con PHP %s" % (p["folder"], v),
                                                          "%s ya va con PHP %s" % (p["folder"], v)))
                row.add_suffix(b)
            if len(p["versions"]) > 1:
                b = Gtk.Button(valign=Gtk.Align.CENTER, sensitive=not self.busy,
                               tooltip_text="Quitar PHP %s" % v)
                b.add(icon("user-trash-symbolic"))
                b.connect("clicked", lambda *_, v=v: act(["docker-php-quitar", p["slug"], v], "Quitando PHP %s de %s" % (v, p["folder"]),
                                                          "PHP %s quitado de %s" % (v, p["folder"])))
                row.add_suffix(b)
            lb.add(row)
        rest = [v for v in d.get("php", []) if v not in p["versions"]]
        if rest:
            row = ActionRow("Añadir otra", "Se prepara su imagen la primera vez (unos minutos)")
            c = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
            for v in rest:
                c.append(v, "PHP %s" % v)
            c.set_active(0)
            row.add_suffix(c)
            b = css(Gtk.Button(label="Añadir", valign=Gtk.Align.CENTER, sensitive=not self.busy), "nv-azul")
            b.connect("clicked", lambda *_: c.get_active_id() and act(
                ["docker-php-añadir", p["slug"], c.get_active_id()], "Añadiendo PHP %s a %s" % (c.get_active_id(), p["folder"]),
                "%s con PHP %s" % (p["folder"], c.get_active_id())))
            row.add_suffix(b)
            lb.add(row)
        box.pack_start(lb, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.add_button("Cerrar", Gtk.ResponseType.CANCEL)
        dlg.show_all()
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp == Gtk.ResponseType.OK and choice:
            self.run_task(choice["title"], choice["args"], done_text=choice["done"],
                          on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))

    def nv_docker_pass(self, p):
        """Un proyecto de antes (con LAMPP delante) pasa al Apache de Docker (docker-pasar)."""
        new = self.dk_url(docker_web_domain(dict(p, kind=project_kind(p["folder"])), p["php"]))
        extra = copy_check("Sin copia, su BBDD de ahora no se podrá recuperar.")
        if not confirm(self.win, "¿Pasar %s al Apache de Docker?" % p["folder"],
                       "Ya no necesitará LAMPP y podrás añadirle más versiones de PHP. Pide la contraseña de "
                       "administrador.", "Pasarlo",
                       steps=["Su BBDD (%s) se carga en la MariaDB común de Docker." % p["db"],
                              "Se quitan sus contenedores de ahora, su vhost de LAMPP y su línea de /etc/hosts.",
                              "Se abrirá en %s." % new], extra=extra):
            return
        args = ["docker-pasar", p["slug"]] + (["--copia"] if extra.wanted else [])
        self.run_task("Pasando %s al Apache de Docker" % p["folder"], args, progress=True,
                      done_text="%s ya va con el Apache de Docker" % p["folder"],
                      on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))

    def nv_docker_web_strip(self, box):
        """El Apache de Docker: si está en marcha, su dirección y arrancarlo o pararlo; y si Docker sin root
        aún no puede usar sus puertos, el aviso con «Permitir»."""
        d = self.docker or {}
        w = d.get("web")
        if not w or not any(p.get("web") for p in d.get("projects", [])):
            return
        if not w["ports_ok"]:
            r = css(Gtk.Box(spacing=10), "nv-stat")
            r.pack_start(icon("dialog-warning-symbolic"), False, False, 0)
            tt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            tt.pack_start(label("Docker sin root aún no puede usar los puertos %s y %s" % (w["http"], w["https"])), False, False, 0)
            tt.pack_start(label("Los puertos de menos de 1024 son de root: se permite una vez (pide la contraseña). "
                                "O elige otros en Configuración.", "nv-chico", "nv-tenue"), False, False, 0)
            r.pack_start(tt, True, True, 0)
            r.pack_end(nv_button(None, "Permitir", None, lambda *_: self.run_task(
                "Permitiendo los puertos del Apache de Docker", ["docker-web", "permitir"], auto_close=True,
                done_text="Docker ya puede usar sus puertos", on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))),
                False, False, 0)
            box.pack_start(r, False, False, 0)
        r = css(Gtk.Box(spacing=10), "nv-stat")
        up = w["state"] == "marcha"
        r.pack_start(label("●", "nv-verde", "nv-latido") if up else nv_dot(False), False, False, 0)
        tt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        tt.pack_start(label("Apache de Docker %s" % ("en marcha" if up else "parado")), False, False, 0)
        tt.pack_start(label("En %s (http %s, https %s): sirve los proyectos de Docker sin LAMPP, con las mismas reglas "
                            "de seguridad. phpMyAdmin: %s" % (w["ip"], w["http"], w["https"], self.dk_url(docker_pma_domain())),
                            "nv-chico", "nv-tenue", ellipsize=3), False, False, 0)
        r.pack_start(tt, True, True, 0)
        r.pack_end(nv_button(None, "Parar" if up else "Arrancar", None, lambda *_: self.run_task(
            ("Parando" if up else "Arrancando") + " el Apache de Docker", ["docker-web", "parar" if up else "arrancar"],
            auto_close=True, on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))), False, False, 0)
        box.pack_start(r, False, False, 0)

    def nv_docker_update_image(self, p):
        if not confirm(self.win, "¿Actualizar la imagen de PHP %s?" % p["php"],
                       "Se rehace con los últimos parches de Docker Hub y se recrea el contenedor de PHP de "
                       "%s. Su BBDD y su configuración no cambian." % p["folder"],
                       "Actualizar la imagen"):
            return
        self.run_task("%s: imagen de PHP %s" % (p["folder"], p["php"]), ["docker-imagen", p["slug"]], progress=True,
                      done_text="%s ya usa la imagen nueva de PHP %s" % (p["folder"], p["php"]),
                      on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))

    def nv_docker_of(self, name):
        return [p for p in (self.docker or {}).get("projects", []) if p["folder"] == name]

    def nv_select(self, x):
        """Elegir un proyecto de la lista: solo el visor y la fila elegida (rehacer la lista entera
        tarda un cuarto de segundo con muchos proyectos; esto, al momento)."""
        self.selected_project = x["name"]
        if not getattr(self, "nv_list", None) or not self.projects or not self.data:
            return
        loaded = self.loaded_project_entry()
        if loaded is None:
            self.nv_hero(next((p for p in self.projects["list"] if p["name"] == x["name"]), None), None)
        for row in self.nv_list.get_children():
            proj = getattr(row, "project", None)
            if proj is None:
                continue
            ctx = row.get_style_context()
            if proj["name"] == x["name"] and not (loaded and proj["name"] == loaded["name"]):
                ctx.add_class("nv-elegida")
            else:
                ctx.remove_class("nv-elegida")

    def nv_build_projects(self):
        if not getattr(self, "nv_list", None) or not self.projects or not self.data:
            return
        p = self.projects
        loaded = self.loaded_project_entry()
        names = [x["name"] for x in p["list"]]
        if self.selected_project not in names:
            self.selected_project = loaded["name"] if loaded else None
        # (arriba, siempre el cargado, con sus botones: elegir otro en la lista no lo cambia. Sin
        # ninguno cargado, el elegido)
        shown = loaded or next((x for x in p["list"] if x["name"] == self.selected_project), None)
        self.nv_hero(shown, loaded)
        clear(self.nv_list)
        head = Gtk.ListBoxRow(activatable=False, selectable=False)
        head.project, head.dbs = None, []
        hb = css(Gtk.Box(spacing=12, margin_start=12, margin_end=8, margin_top=8, margin_bottom=8), "nv-cab")
        # (la columna Proyecto, tan ancha como el nombre más largo: se ve entero)
        self.nv_name_group = Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL)
        self.nv_size_lbls = {}
        for text, w in [("", 18), ("Proyecto", 260), ("Tamaño", 80), ("BBDD", 190), ("Versiones", 0)]:
            lbl = label(text.upper())
            if w:
                lbl.set_size_request(w, -1)
            if text == "Proyecto":
                self.nv_name_group.add_widget(lbl)
            hb.pack_start(lbl, not w, True, 0)
        head.add(hb)
        self.nv_list.add(head)
        for x in p["list"]:
            self.nv_list.add(self.nv_row(x, loaded))
        self.nv_list.show_all()
        self.nv_project_sizes()
        self.nv_count.set_label(plural(len(p["list"]), "proyecto", "proyectos") + " en /opt/htdocs")

    def nv_project_sizes(self):
        """Lo que ocupa cada proyecto en el disco: du en segundo plano, de 10 en 10 proyectos (sin límite de
        tiempo: alguno tarda) y como mucho una vez por minuto; cada uno se vuelve a medir cada 6 horas."""
        if getattr(self, "nv_sizes_busy", False) or time.time() - getattr(self, "nv_sizes_at", 0) < 60:
            return
        self.nv_sizes_busy = True
        run_quick(["gui-proyectos-tamanos"], self.on_project_sizes, timeout=None)

    def on_project_sizes(self, rc, out):
        self.nv_sizes_busy, self.nv_sizes_at = False, time.time()
        lines = parse_lines(out)
        self.project_sizes = {f[1]: (int(f[2]), int(f[3])) for f in lines
                              if f[0] == "T" and len(f) >= 4 and f[2].isdigit() and f[3].isdigit()}
        for name, lbl in getattr(self, "nv_size_lbls", {}).items():
            self.nv_size_text(lbl, name)
        # (quedan por medir: la siguiente tanda, ya)
        if any(f[0] == "F" for f in lines):
            self.nv_sizes_at = 0
            self.nv_project_sizes()
        return False

    def nv_size_text(self, lbl, name):
        got = getattr(self, "project_sizes", {}).get(name)
        lbl.set_label(fmt_size(got[0]) if got else "…")
        lbl.set_tooltip_text("Tamaño en disco, medido el %s"
                             % time.strftime("%d/%m/%Y a las %H:%M", time.localtime(got[1])) if got
                             else "Midiendo lo que ocupa en el disco…")

    def nv_row(self, x, loaded):
        row = Gtk.ListBoxRow()
        row.project = x
        is_loaded = loaded is not None and x["name"] == loaded["name"]
        # BBDD del proyecto para el buscador: las de cada version, la de su configuracion y la de Docker
        row.dbs = {db for _i, db in self.project_pairs(x)} | ({x["db"]} if x["db"] else set()) | \
            {dp["db"] for dp in self.nv_docker_of(x["name"])}
        if is_loaded:
            css(row, "nv-cargada")
        elif x["name"] == self.selected_project:
            css(row, "nv-elegida")
        box = Gtk.Box(spacing=12, margin_start=12, margin_end=8, margin_top=6, margin_bottom=6)
        box.pack_start(kind_icon(x["kind"]), False, False, 0)
        name = label(x["name"], tooltip_text=x["name"])
        name.set_size_request(260, -1)
        self.nv_name_group.add_widget(name)
        box.pack_start(name, False, False, 0)
        size = label("", "nv-mono", "nv-chico", "nv-tenue")
        size.set_size_request(80, -1)
        self.nv_size_lbls[x["name"]] = size
        self.nv_size_text(size, x["name"])
        box.pack_start(size, False, False, 0)
        pairs = self.project_pairs(x)
        db = pairs[0][1] if pairs else self.project_base(x)
        dbl = label(db or "sin BBDD", "nv-mono", "nv-chico", "nv-tenue", ellipsize=3, max_width_chars=24)
        dbl.set_size_request(190, -1)
        box.pack_start(dbl, False, False, 0)
        chips = Gtk.Box(spacing=4, valign=Gtk.Align.CENTER)
        for inst, _db in pairs:
            chips.pack_start(label(inst["php"].rsplit(".", 1)[0] if inst["php"].count(".") == 2 else inst["php"],
                                   "nv-chip", "nv-mono", tooltip_text="lampp-%s · %s" % (inst["folder"], _db)), False, False, 0)
        for dp in self.nv_docker_of(x["name"]):
            chip = css(Gtk.Box(spacing=5, tooltip_text="Docker · %s" % dp["db"]), "nv-chip", "nv-chip-docker")
            chip.pack_start(logo("docker", 13), False, False, 0)
            chip.pack_start(label("Docker %s" % dp["php"], "nv-mono"), False, False, 0)
            chips.pack_start(chip, False, False, 0)
        box.pack_start(chips, True, True, 0)
        # Al pasar el raton: Cargar (si no es el cargado), Montar en Docker (si tiene contenedores: con varios
        # pregunta cual) y su menu ⋮ (el hueco se guarda: la fila no salta)
        hover, dk = [], None
        if self.nv_docker_of(x["name"]):
            dk = nv_button(logo("docker", 16), "Montar en Docker", "Arrancar %s en Docker" % x["name"], lambda *_: self.nv_docker_loaded(x), "nv-proyecto-btn")
            dk.set_sensitive(not self.busy)
            hover.append(dk)
        if is_loaded:
            box.pack_end(label("Cargado", "nv-etiqueta", "nv-etiqueta-azul", valign=Gtk.Align.CENTER, margin_end=6), False, False, 0)
        else:
            b = css(Gtk.Button(label="Cargar", sensitive=not self.busy), "nv-azul")
            b.connect("clicked", lambda *_: self.on_load_folder(x))
            menu = self.nv_row_menu(x)
            menu.set_valign(Gtk.Align.CENTER)
            menu.set_sensitive(not self.busy)
            box.pack_end(menu, False, False, 0)
            box.pack_end(b, False, False, 0)
            hover += [b, menu]
        if dk is not None:
            box.pack_end(dk, False, False, 0)
        if not hover:
            row.add(box)
            return row
        for w in hover:
            w.set_opacity(0)
        menus = [w for w in hover if isinstance(w, Gtk.MenuButton)]
        ev = Gtk.EventBox(above_child=False)
        ev.add_events(Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK)
        ev.connect("enter-notify-event", lambda *_: ([w.set_opacity(1) for w in hover], False)[1])
        ev.connect("leave-notify-event", lambda _w, e: (e.detail == Gdk.NotifyType.INFERIOR or any(m.get_active() for m in menus)
                                                         or [w.set_opacity(0) for w in hover], False)[1])
        ev.add(box)
        row.add(ev)
        return row

    def nv_hero(self, x, loaded):
        clear(self.hero_box)
        p = self.projects
        is_loaded = x is not None and loaded is not None and x["name"] == loaded["name"]
        head = Gtk.Box(spacing=8)
        head.pack_start(nv_dot(is_loaded), False, False, 0)
        head.pack_start(label("PROYECTO CARGADO" if is_loaded else "PROYECTO ELEGIDO" if x else "NINGÚN PROYECTO CARGADO",
                              "nv-seccion"), False, False, 0)
        if p.get("link"):
            head.pack_end(label(("en %s" % p["link"]) if is_loaded else "%s → %s" % (
                p["link"], os.path.basename(p["current"].rstrip("/")) if p["current"] else "nada"), "nv-chico", "nv-tenue"), False, False, 0)
        # (el correo de la web cargada va a Mailpit: discreto, al lado)
        m = self.nv_mail()
        if is_loaded and m.get("on") and m.get("installed"):
            mail = Gtk.Box(spacing=5)
            mail.pack_start(MonoLogo("mailpit", 13), False, False, 0)
            mail.pack_start(label("su correo va a Mailpit", "nv-chico", "nv-tenue"), False, False, 0)
            mail.set_tooltip_text("Se ve en Correo, arriba")
            head.pack_end(mail, False, False, 12)
        self.hero_box.pack_start(head, False, False, 0)
        card = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16), "nv-tarjeta")
        if x is None:
            card.pack_start(label("Elige un proyecto de la lista para cargarlo.", "nv-tenue"), False, False, 0)
            self.hero_box.pack_start(card, False, False, 0)
            self.hero_box.show_all()
            return
        top = Gtk.Box(spacing=20)
        # (el logotipo solo, sin recuadro: con el visor de la derecha más alto, el recuadro se estiraba)
        img = kind_icon(x["kind"], 48)
        img.set_valign(Gtk.Align.CENTER)
        top.pack_start(img, False, False, 0)
        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, valign=Gtk.Align.CENTER)
        tl = Gtk.Box(spacing=10)
        # (los nombres largos, en dos lineas, no cortados)
        tl.pack_start(label(x["name"], "nv-titulo-grande", wrap=True, wrap_mode=2, max_width_chars=44), False, False, 0)
        if x["kind"]:
            tl.pack_start(label(KIND_TEXT[x["kind"]], "nv-etiqueta", valign=Gtk.Align.CENTER), False, False, 0)
        info.pack_start(tl, False, False, 0)
        info.pack_start(label("%s/%s" % ("/opt/htdocs" if DEMO else HTDOCS, x["name"]), "nv-mono", "nv-chico", "nv-tenue", selectable=True,
                              ellipsize=1, max_width_chars=40), False, False, 0)
        top.pack_start(info, True, True, 0)
        # Selectores: el entorno (version y su BBDD) y la BBDD de ese entorno
        pairs = self.project_pairs(x)
        dockers = self.nv_docker_of(x["name"])
        sel = css(Gtk.Grid(column_spacing=12, row_spacing=6, valign=Gtk.Align.CENTER), "nv-selectores")
        sel.attach(label("Entorno (versión de PHP)", "nv-chico", "nv-tenue"), 1, 0, 1, 1)
        sel.attach(label("BBDD", "nv-chico", "nv-tenue"), 2, 0, 1, 1)
        envs = [("lampp", inst, db) for inst, db in pairs] + [("docker", dp, dp["db"]) for dp in dockers]
        env = Gtk.ComboBoxText()
        env.set_size_request(230, -1)
        for kind, obj, _db in envs:
            env.append_text("PHP %s · lampp-%s" % (obj["php"], obj["folder"]) if kind == "lampp"
                            else "PHP %s · Docker" % obj["php"])
        if not envs:
            env.append_text("Sin entornos")
        current = next((n for n, (k, o, _d) in enumerate(envs) if k == "lampp" and o["folder"] == self.data["active"]), 0)
        env.set_active(current if is_loaded else 0)
        env.set_sensitive(bool(envs) and not self.busy)
        dbl = label("", "nv-mono", valign=Gtk.Align.CENTER)
        dbl.set_size_request(180, -1)

        def show_db(*_):
            n = env.get_active()
            dbl.set_label(envs[n][2] if envs and 0 <= n < len(envs) else "—")
        show_db()
        env.connect("changed", show_db)

        def changed(*_):
            n = env.get_active()
            if not envs or n < 0:
                return
            kind, obj, db = envs[n]
            if kind == "docker":
                self.show_tab("docker")
                self.toast("%s en Docker: https://%s" % (x["name"], obj["domain"]))
            elif not (is_loaded and obj["folder"] == self.data["active"]):
                self.do_load_project(x["name"], db, obj, p["link"], p["create"])
        env.connect("changed", changed)
        # Llevarlo a otro entorno: el +, a la izquierda del entorno (su SQL se importa en la pestaña
        # Bases de datos; la fila de abajo queda para los accesos directos del proyecto)
        sel.attach(self.nv_add_env_menu(x), 0, 1, 1, 1)
        sel.attach(env, 1, 1, 1, 1)
        sel.attach(dbl, 2, 1, 1, 1)
        lk = nv_button("insert-link-symbolic", None, "Cambiar la BBDD de cada versión (vincular)",
                       lambda *_: self.on_link_project(x), flat=True)
        sel.attach(lk, 3, 1, 1, 1)
        top.pack_end(sel, False, False, 0)
        card.pack_start(top, False, False, 0)
        card.pack_start(css(Gtk.Box(), "nv-pie"), False, False, 0)
        acts = Gtk.Box(spacing=8)
        if is_loaded:
            kind, admin = self.loaded_project_admin()
            # (con los logotipos de siempre: el globo, VS Code, phpMyAdmin y WordPress o PrestaShop)
            # (los que se ven, su orden y su estilo, como se haya elegido: nv_place_buttons)
            btns = {"web": nv_button(logo("globo", 18), "Abrir web", "Abrir http://%s/" % p["link"],
                                     lambda *_: self.open_uri("http://%s/" % p["link"]), "nv-proyecto-btn")}
            code = vscode_app()
            if code is not None:
                img = None
                if code.get_icon() is not None:
                    img = Gtk.Image.new_from_gicon(code.get_icon(), Gtk.IconSize.BUTTON)
                    img.set_pixel_size(18)
                btns["vscode"] = nv_button(img or "text-editor-symbolic", "VS Code",
                                           "Abrir en Visual Studio Code", lambda *_: self.open_in_vscode(),
                                           "nv-proyecto-btn")
            pma = nv_button(logo("phpmyadmin", 18), "phpMyAdmin", None, lambda *_: self.open_project_pma(), "nv-proyecto-btn")
            pma.set_sensitive(bool(self.loaded_project_db()))
            btns["pma"] = pma
            adm = nv_button(logo("prestashop" if kind == "ps" else "wordpress", 18), "Panel",
                            "Abrir el panel de administración",
                            lambda *_: self.open_project_admin(), "nv-proyecto-btn")
            adm.set_sensitive(bool(admin))
            adm.nv_logo = "prestashop" if kind == "ps" else "wordpress"
            btns["panel"] = adm
            btns["docker"] = nv_button(logo("docker", 18), "Docker", "Montar en Docker",
                                       lambda *_: self.nv_docker_loaded(x), "nv-proyecto-btn")
            btns["compartir"] = self.nv_share_button("http://%s" % p["link"], os.path.join(HTDOCS, x["name"]), x["name"])
            # El registro general de Apache: lo primero que se mira con un error (el del vhost, en Herramientas)
            has_log = os.path.isfile(APACHE_ERROR_LOG)
            logb = nv_button(logo("log", 18), "Log", "Ver el log de Apache" if has_log else "Aún no hay log de Apache",
                             lambda *_: self.show_log_tail(APACHE_ERROR_LOG), "nv-proyecto-btn")
            logb.set_sensitive(has_log)
            btns["log"] = logb
            btns["actualizar"] = nv_button(logo("actualizar", 18), "Actualizar", "Actualizar proyecto",
                                           lambda *_: self.nv_update_project(x), "nv-proyecto-btn")
            btns["actualizar"].set_sensitive(not self.busy)
            if x["kind"] in ("wp", "ps"):
                btns["imagenes"] = self.nv_images_button(x)
            eject = nv_button("media-eject-symbolic", None, "Desmontar el proyecto",
                              lambda *_: self.on_unload_project(), flat=True)
            self.nv_place_buttons(acts, btns, [(eject, ("icono", "media-eject-symbolic"), "Desmontar")])
            acts.pack_start(eject, False, False, 0)
        else:
            acts.pack_start(nv_button("media-playback-start-symbolic", "Cargar", None,
                                      lambda *_: self.on_load_folder(x), "nv-azul"), False, False, 0)
        # (⋮, pegado a la derecha; con un proyecto cargado, del tamaño de los demás botones)
        more = self.nv_more_menu(x)
        if is_loaded:
            self.nv_restyle(more, buttons_conf(), ("icono", "view-more-symbolic"), "Más")
        acts.pack_end(more, False, False, 0)
        # Si su carpeta tiene un dominio en los vhosts: falsearlo o dejar de falsearlo desde aquí, como
        # en Dominios y hosts
        if is_loaded:
            for h in reversed(self.project_hosts(x["name"])):
                fake = h["fake"]
                host = Gtk.Box(spacing=10, margin_end=10)
                texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
                texts.pack_start(label("Host falseado" if fake else "Falsear Host", halign=Gtk.Align.END), False, False, 0)
                texts.pack_start(label(h["name"], "nv-chico", "nv-tenue", halign=Gtk.Align.END, ellipsize=2,
                                       max_width_chars=28, tooltip_text=h["name"]), False, False, 0)
                host.pack_start(texts, False, False, 0)
                sw = Gtk.Switch(active=fake, valign=Gtk.Align.CENTER, tooltip_text=host_switch_tip(h))
                sw.connect("state-set", self.on_host_switch, h)
                host.pack_start(sw, False, False, 0)
                acts.pack_end(host, False, False, 0)
        card.pack_start(acts, False, False, 0)
        self.hero_box.pack_start(card, False, False, 0)
        self.hero_box.show_all()
