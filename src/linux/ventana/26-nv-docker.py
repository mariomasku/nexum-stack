class NvDocker:
    """Docker (como Docker Desktop)."""

    # ------------------------------------------------------------------ Docker (como Docker Desktop)
    def build_docker(self):
        d = self.docker
        if d is None or not d["ready"]:
            # (sin Docker en marcha: lo de siempre, con el boton de instalarlo o prepararlo)
            return super().build_docker()
        clear(self.docker_box)
        box = self.docker_box
        head = Gtk.Box(spacing=12)
        t = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        # (de título, el logotipo de Docker: la ballena y sus letras, en su color)
        title = BrandLogo("docker", 34)
        title.set_halign(Gtk.Align.START)
        t.pack_start(title, False, False, 0)
        t.pack_start(label("Docker %s · sin root, con tu usuario" % d["version"], "nv-chico", "nv-tenue"), False, False, 0)
        head.pack_start(t, True, True, 0)
        new = nv_button("list-add-symbolic", "Proyecto en Docker…", None, lambda *_: self.nv_docker_new(), "nv-azul")
        head.pack_end(new, False, False, 0)
        # Parar todo lo de Nexum de una vez (proyectos, MariaDB comunes y el Apache de Docker)
        running = [c for c in d.get("containers", []) if c["state"] == "running" and docker_own(c["name"])]
        stop = nv_button("media-playback-stop-symbolic", "Parar todos",
                         "Parar %d contenedores de Nexum" % len(running) if running else
                         "No hay ningún contenedor de Nexum en marcha",
                         lambda *_: self.run_task("Parando todos los contenedores de Nexum", ["docker-parar-todo"],
                                                  auto_close=True, done_text="Contenedores de Nexum parados",
                                                  on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data)),
                         "nv-proyecto-btn", "nv-stop")
        stop.set_sensitive(bool(running) and not self.busy)
        head.pack_end(stop, False, False, 0)
        box.pack_start(head, False, False, 0)
        for text, sub, btn in ([("Hay otro Docker en marcha: el de Ubuntu, como administrador",
                                 "Este programa usa el suyo, con tu usuario: el de Ubuntu no hace falta y quien lo use "
                                 "puede hacerse con el equipo. Apágalo salvo que lo uses fuera de este programa.",
                                 ("Apagarlo", lambda *_: self.run_task("Apagando el Docker del sistema", ["docker-instalar"],
                                                                         done_text="Docker del sistema apagado", auto_close=True,
                                                                         on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))))]
                               if d.get("rootful") else []) + \
                              ([("La versión LAMPP activa está parada", "Los proyectos en Docker de antes se abren por su "
                                 "Apache (los del Apache de Docker, no).", ("Arrancarla", lambda *_: self.nv_power()))]
                               if not d["lampp"] and any(not p.get("web") for p in d["projects"]) else []):
            r = css(Gtk.Box(spacing=10), "nv-stat")
            r.pack_start(icon("dialog-warning-symbolic"), False, False, 0)
            tt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            tt.pack_start(label(text), False, False, 0)
            tt.pack_start(label(sub, "nv-chico", "nv-tenue"), False, False, 0)
            r.pack_start(tt, True, True, 0)
            r.pack_end(nv_button(None, btn[0], None, btn[1]), False, False, 0)
            box.pack_start(r, False, False, 0)
        self.nv_docker_web_strip(box)
        # Tarjetas: CPU, memoria (docker stats, llegan aparte) y en marcha
        cons = d.get("containers", [])
        up = sum(1 for c in cons if c["state"] == "running")
        stats = Gtk.Box(spacing=12, homogeneous=True)
        self.dk_cards = {}
        for key, title in [("cpu", "Uso de CPU de los contenedores"), ("mem", "Memoria de los contenedores"),
                           ("up", "En marcha")]:
            c = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6), "nv-stat")
            c.pack_start(label(title, "nv-chico", "nv-tenue"), False, False, 0)
            val = label("…", "nv-cifra")
            bar = css(Gtk.ProgressBar(), "nv-barra")
            sub = label("", "nv-chico", "nv-tenue")
            for w in (val, bar, sub):
                c.pack_start(w, False, False, 0)
            stats.pack_start(c, True, True, 0)
            self.dk_cards[key] = (val, bar, sub)
        val, bar, sub = self.dk_cards["up"]
        val.set_label("%d de %d" % (up, len(cons)))
        bar.set_fraction(up / len(cons) if cons else 0)
        sub.set_label(plural(len(d["projects"]), "proyecto", "proyectos"))
        box.pack_start(stats, False, False, 0)
        self.nv_show_stats()
        # Pestañas, buscador y «solo en marcha»
        tools = Gtk.Box(spacing=10)
        seg = css(Gtk.Box(), "nv-segmentado")
        first = None
        for key, text in [("cont", "Contenedores"), ("img", "Imágenes"), ("vol", "Volúmenes")]:
            rb = Gtk.RadioButton.new_with_label_from_widget(first, text)
            rb.set_mode(False)
            first = first or rb
            rb.set_active(self.dk_view == key)
            rb.connect("toggled", lambda r, k=key: r.get_active() and (setattr(self, "dk_view", k), self.nv_dk_table()))
            seg.pack_start(rb, False, False, 0)
        tools.pack_start(seg, False, False, 0)
        only = Gtk.Switch(active=self.dk_only_up, valign=Gtk.Align.CENTER)
        only.connect("notify::active", lambda w, _p: (setattr(self, "dk_only_up", w.get_active()), self.nv_dk_table()))
        tools.pack_end(only, False, False, 0)
        tools.pack_end(label("Solo en marcha", "nv-chico", "nv-tenue", valign=Gtk.Align.CENTER), False, False, 0)
        search = Gtk.SearchEntry(placeholder_text="Buscar", width_chars=18, valign=Gtk.Align.CENTER, text=self.dk_query)
        search.connect("search-changed", lambda e: (setattr(self, "dk_query", e.get_text().strip().lower()), self.nv_dk_table()))
        tools.pack_end(search, False, False, 0)
        box.pack_start(tools, False, False, 0)
        self.dk_table = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.pack_start(self.dk_table, False, False, 0)
        self.nv_dk_table()
        box.pack_start(label("Para llevar un proyecto a Docker: «Proyecto en Docker…» o, en Proyectos, «Añadir entorno».",
                             "nv-chico", "nv-tenue"), False, False, 0)
        for w in self.nv_walk(box):
            if isinstance(w, Gtk.Button) and not w.get_style_context().has_class("nv-azul"):
                css(w, "nv-clasico")
        box.show_all()

    def nv_container_delete(self, c):
        """Eliminar un contenedor suelto de un proyecto en Docker."""
        if not confirm(self.win, "¿Eliminar el contenedor %s?" % c["name"],
                       "Se vuelve a crear al arrancar el proyecto; los datos de la BBDD siguen en su volumen. "
                       "Para quitar el proyecto entero, usa la papelera de su fila.",
                       "Eliminar el contenedor", destructive=True):
            return
        self.run_task("Eliminando %s" % c["name"], ["docker-contenedor", "borrar", c["name"]],
                      done_text="%s eliminado" % c["name"], auto_close=True,
                      on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))

    def nv_docker_new(self):
        """El formulario de siempre para crear un proyecto en Docker, en un dialogo."""
        dlg = Gtk.Dialog(title="Proyecto en Docker", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(620, -1)
        self.nv_docker_dlg = dlg
        dlg.connect("destroy", lambda *_: setattr(self, "nv_docker_dlg", None))
        self.nv_docker_new_fill()
        dlg.show_all()

    def nv_docker_new_fill(self):
        """El formulario del diálogo «Proyecto en Docker», con lo elegido ahora (al cambiar la carpeta se rehace:
        la BBDD que se copia y el dominio son los de esa carpeta)."""
        dlg = getattr(self, "nv_docker_dlg", None)
        if dlg is None:
            return
        area = dlg.get_content_area()
        for old in area.get_children():
            area.remove(old)
        form = self.build_docker_new()
        form.set_margin_start(18)
        form.set_margin_end(18)
        form.set_margin_bottom(18)
        area.add(form)
        # (al pulsar «Crear en Docker» se cierra: la tarea va en su ventana)
        for w in self.nv_walk(form):
            if isinstance(w, Gtk.Button) and w.get_label() == "Crear en Docker":
                w.connect("clicked", lambda *_: dlg.destroy())
        form.show_all()

    def nv_walk(self, w):
        yield w
        if isinstance(w, Gtk.Container):
            for c in w.get_children():
                yield from self.nv_walk(c)

    def docker_folder_changed(self):
        f = self.docker_form
        f["source"] = None
        if not f.get("domain_set"):
            f["domain"] = docker_slug(f["folder"] or "") + ".docker.local" if f.get("folder") else ""
        # (el formulario va en un diálogo: se rehace ahí, con la BBDD y el dominio de la carpeta nueva)
        self.nv_docker_new_fill()

    def on_docker_stats(self, rc, out):
        cores, total, cpu, mem = 1, 0, {}, {}
        units = {"B": 1, "KiB": 1024, "MiB": 1024 ** 2, "GiB": 1024 ** 3, "TiB": 1024 ** 4,
                 "kB": 1000, "KB": 1000, "MB": 1000 ** 2, "GB": 1000 ** 3}
        for f in parse_lines(out):
            if f[0] == "T" and len(f) >= 3 and f[1].isdigit() and f[2].isdigit():
                cores, total = int(f[1]), int(f[2])
            elif f[0] == "K" and len(f) >= 4:
                try:
                    cpu[f[1]] = float(f[2].rstrip("%"))
                    m = re.match(r"([\d.]+)\s*([A-Za-z]+)", f[3].split("/")[0].strip())
                    mem[f[1]] = float(m.group(1)) * units.get(m.group(2), 1) if m else 0
                except ValueError:
                    pass
        self.dk_stats = {"cores": cores, "total": total, "cpu": cpu, "mem": mem}
        self.nv_show_stats()
        if getattr(self, "dk_table", None) is not None and self.dk_view == "cont":
            self.nv_dk_table()
        return False

    def nv_show_stats(self):
        s = self.dk_stats
        if not getattr(self, "dk_cards", None) or s is None:
            return
        val, bar, sub = self.dk_cards["cpu"]
        total_cpu = sum(s["cpu"].values())
        val.set_label(("%.1f %%" % total_cpu).replace(".", ","))
        bar.set_fraction(min(1, total_cpu / (100 * s["cores"])))
        sub.set_label("de %d %% (%s)" % (100 * s["cores"], plural(s["cores"], "núcleo", "núcleos")))
        val, bar, sub = self.dk_cards["mem"]
        used = sum(s["mem"].values())
        val.set_label(fmt_size(int(used)))
        bar.set_fraction(min(1, used / s["total"]) if s["total"] else 0)
        sub.set_label("de %s" % fmt_size(s["total"]) if s["total"] else "")

    def nv_dk_toggle(self, proj):
        """Despliega un proyecto de Docker (y pliega el que estuviera abierto) o lo pliega."""
        self.dk_open = set() if proj in self.dk_open else {proj}
        self.nv_dk_table()

    def nv_dk_table(self):
        if getattr(self, "dk_table", None) is None:
            return
        clear(self.dk_table)
        d = self.docker
        q = self.dk_query
        if self.dk_view == "img":
            rows = [i for i in d.get("images", []) if q in ("%s:%s %s" % (i["repo"], i["tag"], i["id"])).lower()]
            used = {c["image"] for c in d.get("containers", [])}
            self.dk_table.pack_start(self.nv_simple_table(
                ["Imagen", "Etiqueta", "ID", "Tamaño", "Creada", "Acciones"], [300, 110, 120, 90, 120, 90],
                [[label(i["repo"], "nv-mono", "nv-chico", ellipsize=3, tooltip_text=i["repo"]),
                  label(i["tag"], "nv-mono", "nv-chico", "nv-enlace"),
                  label(i["id"], "nv-mono", "nv-chico", "nv-tenue", selectable=True),
                  label(i["size"], "nv-mono", "nv-tenue"),
                  label(docker_status_text("Up " + i["created"].replace(" ago", "")).replace("en marcha · ", "hace "), "nv-tenue"),
                  self.nv_image_actions(i, "%s:%s" % (i["repo"], i["tag"]) in used or i["id"] in used)] for i in rows],
                "No hay imágenes"), False, False, 0)
        elif self.dk_view == "vol":
            rows = [v for v in d.get("volumes", []) if q in v["name"].lower()]
            # (el de la BBDD de un proyecto lo usa su contenedor db, aunque esté parado)
            used = {"%s_db" % c["project"] for c in d.get("containers", []) if c["project"]}
            self.dk_table.pack_start(self.nv_simple_table(["Volumen", "Driver", "De", "Acciones"], [420, 120, 200, 90],
                                     [[label(v["name"], "nv-mono", "nv-chico"), label(v["driver"], "nv-tenue"),
                                       label(re.sub(r"^nexum-(.+)_db$", r"\1 (BBDD)", v["name"]) if v["name"].startswith("nexum-") else "—",
                                             "nv-tenue"),
                                       self.nv_volume_actions(v, v["name"] in used)] for v in rows], "No hay volúmenes"), False, False, 0)
        else:
            self.dk_table.pack_start(self.nv_containers_table(), False, False, 0)
        for w in self.nv_walk(self.dk_table):
            if isinstance(w, Gtk.Button) and not w.get_style_context().has_class("nv-proyecto-btn"):
                css(w, "nv-clasico")
        self.dk_table.show_all()

    def nv_image_actions(self, i, in_use):
        """Volver a descargar una imagen de Docker Hub y borrarla (si no la usa ningún contenedor)."""
        a = Gtk.Box(spacing=6, halign=Gtk.Align.START)
        ref = "%s:%s" % (i["repo"], i["tag"])
        pullable = i["tag"] != "<none>" and not i["repo"].startswith("nexum-")
        pull = nv_button("folder-download-symbolic", None, "Volver a descargar de Docker Hub"
                         if pullable else "Se rehace con «Actualizar imagen»"
                         if i["repo"].startswith("nexum-") else "Sin etiqueta: no se puede volver a descargar",
                         lambda *_: self.run_task("Descargando %s" % ref, ["docker-imagenes", "descargar", ref],
                                                  done_text="%s descargada" % ref,
                                                  on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data)))
        pull.set_sensitive(pullable and not self.busy)
        a.pack_start(pull, False, False, 0)
        rm = nv_button("user-trash-symbolic", None, "La usa un contenedor: bórralo antes" if in_use else "Borrar la imagen",
                       lambda *_: self.nv_image_delete(i, ref))
        rm.set_sensitive(not in_use and not self.busy)
        a.pack_start(rm, False, False, 0)
        return a

    def nv_image_delete(self, i, ref):
        tagged = i["tag"] != "<none>"
        if not confirm(self.win, "¿Borrar la imagen %s?" % (ref if tagged else i["id"]),
                       "Ocupa %s. Si hace falta, se vuelve a descargar o a preparar." % i["size"],
                       "Borrar la imagen", destructive=True):
            return
        self.run_task("Borrando %s" % (ref if tagged else i["id"]), ["docker-imagenes", "borrar", ref if tagged else i["id"]],
                      done_text="Imagen borrada", auto_close=True,
                      on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))

    def nv_volume_actions(self, v, in_use):
        a = Gtk.Box(spacing=6, halign=Gtk.Align.START)
        rm = nv_button("user-trash-symbolic", None, "Lo usa un contenedor: bórralo antes"
                       if in_use else "Borrar el volumen", lambda *_: self.nv_volume_delete(v))
        rm.set_sensitive(not in_use and not self.busy)
        a.pack_start(rm, False, False, 0)
        return a

    def nv_volume_delete(self, v):
        if not confirm(self.win, "¿Borrar el volumen %s?" % v["name"],
                       "Se pierden sus datos. No se puede deshacer.", "Borrar el volumen", destructive=True):
            return
        self.run_task("Borrando %s" % v["name"], ["docker-volumen-borrar", v["name"]],
                      done_text="Volumen borrado", auto_close=True,
                      on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))

    def nv_simple_table(self, headers, widths, rows, empty):
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "nv-grupo")
        groups = [Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL) for _ in widths]
        for n_row, cells in enumerate([[label(h.upper()) for h in headers]] + rows):
            r = Gtk.ListBoxRow(activatable=False)
            b = css(Gtk.Box(spacing=14), "nv-fila", *(["nv-cab"] if n_row == 0 else []))
            for n, w in enumerate(cells):
                w.set_size_request(widths[n], -1)
                groups[n].add_widget(w)
                b.pack_start(w, n == len(cells) - 1, True, 0)
            r.add(b)
            lb.add(r)
        if not rows:
            r = Gtk.ListBoxRow(activatable=False)
            r.add(label(empty, "nv-tenue", margin=14))
            lb.add(r)
        return lb

    def nv_docker_visor(self, p, items):
        """Visor de un proyecto en Docker, como el del proyecto cargado: su nombre y su logotipo, sus
        versiones, su dominio, si está en marcha y sus accesos directos (la web, su panel con el
        administrador de pruebas, su phpMyAdmin, VS Code, el registro de PHP y arrancar o parar)."""
        folder = os.path.join(HTDOCS, p["folder"])
        kind = project_kind(p["folder"])
        akind, admin = project_admin(folder)
        up = bool(items) and all(c["state"] == "running" for c in items)
        some = any(c["state"] == "running" for c in items)
        web = p.get("web")
        if web:
            php_c = next((c["name"] for c in items if c["name"] == "nexum-%s-php%s" % (p["slug"], p["php"].replace(".", ""))), None)
        else:
            php_c = next((c["name"] for c in items if re.fullmatch(r"nexum-[a-z0-9-]+-php-\d+", c["name"])), None)
        card = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12), "nv-tarjeta", "nv-dk-visor")
        top = Gtk.Box(spacing=14)
        # (el logotipo solo, sin recuadro, como arriba en Proyectos)
        img = kind_icon(kind, 36)
        img.set_valign(Gtk.Align.CENTER)
        top.pack_start(img, False, False, 0)
        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3, valign=Gtk.Align.CENTER)
        tl = Gtk.Box(spacing=10)
        tl.pack_start(label(p["folder"], "nv-titulo", ellipsize=3, max_width_chars=48, tooltip_text=p["folder"]),
                      False, False, 0)
        if kind:
            tl.pack_start(label(KIND_TEXT[kind], "nv-etiqueta", valign=Gtk.Align.CENTER), False, False, 0)
        info.pack_start(tl, False, False, 0)
        info.pack_start(label(("PHP %s · %s · %s" % (" · ".join(p["versions"]),
                                                    ("BBDD de lampp-%s en vivo (la de web.local)" % p["lampp"]) if p.get("lampp")
                                                    else "MariaDB %s común" % p["maria"], self.dk_url(p["domain"])))
                              if web else "PHP %s · MariaDB %s · https://%s" % (p["php"], p["maria"], p["domain"]),
                              "nv-mono", "nv-chico", "nv-tenue", selectable=True, ellipsize=3), False, False, 0)
        top.pack_start(info, True, True, 0)
        st = Gtk.Box(spacing=6, valign=Gtk.Align.CENTER)
        st.pack_start(label("●", "nv-verde", "nv-latido") if up else nv_dot(False), False, False, 0)
        st.pack_start(label("En marcha" if up else "A medias" if some else "Parado", "nv-chico",
                            *([] if up else ["nv-tenue"])), False, False, 0)
        top.pack_end(st, False, False, 0)
        card.pack_start(top, False, False, 0)
        card.pack_start(css(Gtk.Box(), "nv-pie"), False, False, 0)
        acts = Gtk.Box(spacing=8)
        stopped = "Está parado: arráncalo antes"
        if web and p.get("kind") != "ps" and len(p["versions"]) > 1:
            # (varias versiones a la vez: cada una con su dominio)
            wb = self.nv_menu_button("Abrir web", "web-browser-symbolic",
                                     [("PHP %s  ·  %s" % (v, docker_web_domain(p, v)),
                                       lambda v=v: self.open_uri(self.dk_url(docker_web_domain(p, v)) + "/")) for v in p["versions"]],
                                     "Abrir una de sus versiones de PHP" if up else stopped)
        else:
            wb = nv_button(logo("globo", 18), "Abrir web", "Abrir %s/" % self.dk_url(p["domain"]) if up else stopped,
                           lambda *_: self.open_uri(self.dk_url(p["domain"]) + "/"), "nv-proyecto-btn")
        wb.set_sensitive(up)
        btns = {"web": wb}
        st = tunnel_state()
        targets = [(v, self.dk_url(docker_web_domain(p, v))) for v in p["versions"]] \
            if web and p.get("kind") != "ps" and len(p["versions"]) > 1 else [(p["php"], self.dk_url(p["domain"]))]
        if len(targets) > 1 and not (st and st["target"] in [t for _v, t in targets]):
            sb = self.nv_menu_button("Compartir", logo("cloudflare", 18), [("PHP %s  ·  %s" % (v, t), lambda t=t: self.nv_share(t, folder, p["folder"]))
                                                         for v, t in targets],
                                     "Compartir con un túnel de Cloudflare" if up else stopped)
        else:
            mine = next((t for _v, t in targets if st and st["target"] == t), targets[0][1])
            sb = self.nv_share_button(mine, folder, p["folder"])
        sb.set_sensitive(up)
        btns["compartir"] = sb
        adm = nv_button(logo("prestashop" if akind == "ps" else "wordpress", 18), "Panel",
                        stopped if not up else "Abrir el panel de administración"
                        if admin else "No tiene panel de administración",
                        lambda *_: self.open_admin_login(akind, admin, self.dk_url(p["domain"]), p["folder"],
                                                         ["docker-usuario-pruebas", p["slug"]]), "nv-proyecto-btn")
        adm.set_sensitive(up and bool(admin))
        adm.nv_logo = "prestashop" if akind == "ps" else "wordpress"
        btns["panel"] = adm
        pma_ok = web or p["pma"].isdigit()
        pma = nv_button(logo("phpmyadmin", 18), "phpMyAdmin",
                        stopped if not up else "Abrir phpMyAdmin (copia la contraseña)" if pma_ok else "Sin puerto de phpMyAdmin",
                        lambda *_: (self.nv_docker_copy_pass(p), self.open_uri(self.dk_pma_url(p))),
                        "nv-proyecto-btn")
        pma.set_sensitive(up and pma_ok)
        btns["pma"] = pma
        code = vscode_app()
        if code is not None:
            cimg = None
            if code.get_icon() is not None:
                cimg = Gtk.Image.new_from_gicon(code.get_icon(), Gtk.IconSize.BUTTON)
                cimg.set_pixel_size(18)
            vs = nv_button(cimg or "text-editor-symbolic", "VS Code", "Abrir en Visual Studio Code",
                           lambda *_: self.open_in_vscode(folder), "nv-proyecto-btn")
            vs.set_sensitive(os.path.isdir(folder))
            btns["vscode"] = vs
        lg = nv_button(logo("log", 18), "Log", "Ver el log de errores" if php_c else "Arráncalo para ver su log",
                       lambda *_: self.nv_docker_log(p, php_c), "nv-proyecto-btn")
        lg.set_sensitive(bool(php_c))
        btns["log"] = lg
        if kind in ("wp", "ps"):
            btns["imagenes"] = self.nv_images_button({"name": p["folder"], "kind": kind})
        self.nv_place_buttons(acts, btns)
        if web:
            vb = nv_button("list-add-symbolic", "Versiones de PHP…", "Gestionar sus versiones de PHP",
                           lambda *_: self.nv_docker_versions(p), "nv-proyecto-btn")
        else:
            vb = nv_button("go-up-symbolic", "Pasar al Apache de Docker", "Varias versiones de PHP a la vez",
                           lambda *_: self.nv_docker_pass(p), "nv-proyecto-btn")
        vb.set_sensitive(not self.busy)
        conf = buttons_conf()
        self.nv_restyle(vb, conf, ("icono", "list-add-symbolic" if web else "go-up-symbolic"),
                        "Versiones de PHP" if web else "Pasar")
        acts.pack_start(vb, False, False, 0)
        power = nv_button("media-playback-stop-symbolic" if up else "media-playback-start-symbolic",
                          "Parar" if up else "Arrancar",
                          "Parar sus contenedores" if up else "Arrancar sus contenedores",
                          lambda *_: self.run_task(("Parando %s" if up else "Arrancando %s") % p["folder"],
                                                   ["docker-parar" if up else "docker-arrancar", p["slug"]], auto_close=True,
                                                   on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data)),
                          "nv-proyecto-btn", "nv-stop" if up else "nv-play")
        power.set_sensitive(not self.busy)
        self.nv_restyle(power, conf, ("icono", "media-playback-stop-symbolic" if up else "media-playback-start-symbolic"),
                        "Parar" if up else "Arrancar")
        acts.pack_end(power, False, False, 0)
        card.pack_start(acts, False, False, 0)
        return card

    def nv_usage_tick(self):
        """Cada 3 s, en segundo plano (leer /proc lleva unos milisegundos): CPU y RAM de Nexum y sus servicios.
        Con la ventana minimizada u oculta, nada."""
        gw = self.win.get_window()
        if getattr(self, "usage_busy", False) or not self.win.get_visible() or not gw or \
                gw.get_state() & Gdk.WindowState.ICONIFIED:
            return True
        self.usage_busy = True

        def work():
            try:
                out = self.usage.sample()
            except Exception:  # noqa: BLE001 - un proceso que desaparece a mitad: la siguiente vez
                out = None
            GLib.idle_add(self.nv_usage_show, out)
        threading.Thread(target=work, daemon=True).start()
        return True

    def nv_usage_show(self, out):
        self.usage_busy = False
        if not out:
            return False
        total = self.usage.total or 1
        cpu = [v[0] for v in out.values() if v[0] is not None]
        mem = sum(v[1] for v in out.values())
        fmt = lambda x: ("%.1f" % x).replace(".", ",")
        self.usage_lbl.set_label("CPU %s %% · RAM %s %%" % (fmt(sum(cpu)) if cpu else "—", fmt(100.0 * mem / total)))
        lines = ["Nexum Dev Stack y sus servicios: CPU %s %% de todo el equipo (%d núcleos) · RAM %s (%s %% de %s)"
                 % (fmt(sum(cpu)) if cpu else "—", self.usage.cpus, fmt_size(mem), fmt(100.0 * mem / total),
                    fmt_size(total)), ""]
        for key, text in USAGE_GROUPS:
            c, m = out[key]
            if m or c:
                lines.append("%s: CPU %s %% · %s" % (text, fmt(c) if c is not None else "—", fmt_size(m)))
        self.usage_lbl.set_tooltip_text("\n".join(lines))
        return False

    def nv_shared_users(self, name):
        """Proyectos del Apache de Docker en marcha que usan un contenedor común: el Apache de Docker o
        su phpMyAdmin (todos) o una MariaDB común (los que van con esa versión). Vacío si no es común."""
        d = self.docker or {}
        up = {c["name"] for c in d.get("containers", []) if c["state"] == "running"}
        m = re.fullmatch(r"nexum-mariadb-(\d+)-(\d+)", name)
        bridge = re.fullmatch(r"nexum-lampp-bd-(\d+(?:-\d+){1,2})", name)
        if not m and not bridge and name not in ("nexum-web", "nexum-pma"):
            return []
        users = []
        for p in d.get("projects", []):
            if not p.get("web"):
                continue
            if bridge and p.get("lampp") != bridge.group(1).replace("-", "."):
                continue
            if m and (p["maria"] != "%s.%s" % m.groups() or p.get("lampp")):
                continue
            if any(re.fullmatch(r"nexum-%s-php\d{2}" % re.escape(p["slug"]), n) for n in up):
                users.append(p["folder"])
        return users

    def nv_stop_shared_ok(self, names, what):
        """Antes de parar algo común: si lo usa algún proyecto en marcha, se dice cuáles y se pregunta."""
        users = sorted({u for n in names for u in self.nv_shared_users(n)})
        if not users:
            return True
        many = len(users) > 1
        if "mariadb" in " ".join(names) or "lampp-bd" in " ".join(names):
            text = ("Es común: ahora %s %s. %s sin BBDD (errores de conexión) hasta que la vuelvas a arrancar; "
                    "al arrancar un proyecto que va con ella, se arranca sola."
                    % ("la usan" if many else "la usa", ", ".join(users), "Se quedarán" if many else "Se quedará"))
        else:
            text = ("Es común: ahora %s %s. %s de verse hasta que lo vuelvas a arrancar; al arrancar un proyecto "
                    "del Apache de Docker, se arranca solo."
                    % ("lo usan" if many else "lo usa", ", ".join(users), "Dejarán" if many else "Dejará"))
        return confirm(self.win, "¿Parar %s?" % what, text,
                       "Pararla igualmente" if "mariadb" in " ".join(names) else "Pararlo igualmente", destructive=True)

    def nv_docker_log(self, p, name):
        """Lo último del contenedor de PHP de un proyecto en Docker: ahí van los errores de PHP de su web
        (PHP-FPM los manda a su salida de errores) y los avisos del propio PHP-FPM."""
        def done(rc, out):
            if rc != 0 and not out.strip():
                message(self.win, "No se han podido leer los registros de %s" % name, "", Gtk.MessageType.ERROR)
                return False
            self.show_text("PHP de %s" % p["folder"], "Últimas líneas del contenedor %s (los errores de PHP de "
                           "https://%s)" % (name, p["domain"]), out, lambda: self.nv_docker_log(p, name))
            return False
        run_quick(["docker-contenedor", "registros", name], done)

    def nv_containers_table(self):
        d = self.docker
        cons = d.get("containers", [])
        stats = (self.dk_stats or {}).get("cpu", {})
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "nv-grupo")
        widths = [270, 110, 150, 130, 60, 130]
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
            a = Gtk.Box(halign=Gtk.Align.START)
            for ic, tip, fn, ok in items:
                b = nv_button(ic, None, tip, lambda *_, fn=fn: fn(), "nv-clasico",
                              *(["nv-stop"] if "stop" in ic else ["nv-play"] if "start" in ic else []))
                b.set_sensitive(ok and not self.busy)
                a.pack_start(b, False, False, 2)
            return a

        def cpu_text(names):
            vals = [stats[n] for n in names if n in stats]
            return ("%.1f %%" % sum(vals)).replace(".", ",") if vals else "—"
        lb.connect("row-activated", lambda _l, r: r.on_click and r.on_click())
        row(["Nombre", "ID", "Imagen", "Puertos", "CPU", "Acciones"], True)
        projects = {p["slug"]: p for p in d["projects"]}
        shown = 0
        for proj in sorted({c["project"] for c in cons}):
            items = sorted((c for c in cons if c["project"] == proj), key=lambda c: c["name"])
            slug = proj[6:] if proj.startswith("nexum-") else ""
            p = projects.get(slug)
            title = p["folder"] if p else proj or "(sin proyecto)"
            # (lo comun del Apache de Docker)
            if not p and proj == "nexum-web":
                title = "Apache de Docker y phpMyAdmin"
            elif not p and re.fullmatch(r"nexum-mariadb-\d+-\d+", proj or ""):
                title = "MariaDB %s (común)" % proj[len("nexum-mariadb-"):].replace("-", ".")
            elif not p and re.fullmatch(r"nexum-lampp-bd-\d+-\d+(-\d+)?", proj or ""):
                title = "Puente a la BBDD de lampp-%s (en vivo)" % proj[len("nexum-lampp-bd-"):].replace("-", ".")
            visible = [c for c in items if (not self.dk_only_up or c["state"] == "running")
                       and (self.dk_query in c["name"].lower() or self.dk_query in title.lower())]
            if not visible:
                continue
            shown += 1
            up = all(c["state"] == "running" for c in items)
            opened = proj in self.dk_open
            name = Gtk.Box(spacing=8)
            name.pack_start(icon("pan-down-symbolic" if opened else "pan-end-symbolic"), False, False, 0)
            ic = css(Gtk.Box(), "nv-dk-icono")
            ic.pack_start(logo("docker", 14), False, False, 0)
            name.pack_start(ic, False, False, 0)
            name.pack_start(label(title, "nv-dk-proyecto", ellipsize=3), False, False, 0)
            # (en marcha: su punto verde que late; ya no hay columna Estado)
            if up:
                name.pack_start(label("●", "nv-verde", "nv-latido", valign=Gtk.Align.CENTER,
                                      tooltip_text="En marcha"), False, False, 0)
            if p:
                web = p.get("web")
                php = Gtk.Button(label="PHP %s" % " · ".join(p["versions"]) if web else "PHP %s" % p["php"],
                                 valign=Gtk.Align.CENTER, sensitive=not self.busy,
                                 tooltip_text="Gestionar sus versiones de PHP"
                                 if web else "Cambiar la versión de PHP")
                php.connect("clicked", lambda *_, p=p: self.nv_docker_versions(p) if p.get("web") else self.on_docker_php(p))
                img_cell = Gtk.Box()
                img_cell.pack_start(php, False, False, 0)
                pma = label(docker_pma_domain() if web else "%s:80" % p["pma"] if p["pma"].isdigit() else "—",
                            "nv-mono", "nv-chico", "nv-enlace")
                acts = actions(([] if web else [
                    ("go-up-symbolic", "Pasarlo al Apache de Docker: sin LAMPP y con varias versiones de PHP a la vez",
                     lambda p=p: self.nv_docker_pass(p), True)]) + [
                    # (lo primero: arrancar o parar todos sus servicios a la vez)
                    ("media-playback-stop-symbolic" if up else "media-playback-start-symbolic", "Parar todos sus servicios" if up else "Arrancar todos sus servicios",
                     lambda p=p, up=up: self.run_task(("Parando %s" if up else "Arrancando %s") % p["folder"],
                                                      ["docker-parar" if up else "docker-arrancar", p["slug"]],
                                                      auto_close=True, on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data)), True),
                    ("web-browser-symbolic", "Abrir %s" % self.dk_url(p["domain"]), lambda p=p: self.open_uri(self.dk_url(p["domain"]) + "/"), up),
                    ("drive-multidisk-symbolic", "phpMyAdmin (entra con el usuario root y la contraseña de la llave)",
                     lambda p=p: self.open_uri(self.dk_pma_url(p)), up),
                    ("dialog-password-symbolic", "Copiar la contraseña de root de su BBDD (para su phpMyAdmin)",
                     lambda p=p: self.nv_docker_copy_pass(p), True),
                    ("software-update-available-symbolic", "Actualizar la imagen de PHP %s con lo último de Docker Hub "
                     "(parches de seguridad); la BBDD y la configuración no cambian" % p["php"],
                     lambda p=p: self.nv_docker_update_image(p), True),
                    ("text-x-generic-symbolic", "Registros", lambda p=p: self.run_task("Registros de %s" % p["folder"], ["docker-registros", p["slug"]]), True)] + (
                    [("network-transmit-receive-symbolic", "BBDD: la de LAMPP en vivo (la misma que web.local) o su copia de Docker",
                      lambda p=p: self.nv_docker_db_mode(p), True)] if web and p.get("kind") == "wp" else []) + [
                    ("user-trash-symbolic", "Eliminar el proyecto de Docker: sus contenedores y la copia de su BBDD "
                     "(la carpeta y la BBDD de LAMPP no se tocan)", lambda p=p: self.on_docker_delete(p), True)])
            else:
                img_cell, pma, acts = label(plural(len(items), "contenedor", "contenedores"), "nv-chico", "nv-tenue"), label(""), label("")
                done = lambda *a: run_quick(["gui-docker"], self.on_docker_data)
                if proj == "nexum-web":
                    acts = actions([("media-playback-stop-symbolic" if up else "media-playback-start-symbolic",
                                     "Parar el Apache de Docker y su phpMyAdmin (los proyectos del Apache de Docker dejan "
                                     "de verse)" if up else "Arrancar el Apache de Docker y su phpMyAdmin",
                                     lambda up=up: (not up or self.nv_stop_shared_ok(["nexum-web"], "el Apache de Docker")) and self.run_task(
                                         "Parando el Apache de Docker" if up else "Arrancando el Apache de Docker",
                                         ["docker-web", "parar" if up else "arrancar"], auto_close=True, on_done=done), True)])  # noqa: B023 (done es el mismo en cada vuelta)
                elif re.fullmatch(r"nexum-lampp-bd-\d+-\d+(-\d+)?", proj or "") and len(items) == 1:
                    # (el puente de los proyectos de Docker que usan en vivo la BBDD de esa version LAMPP)
                    ver = proj[len("nexum-lampp-bd-"):].replace("-", ".")
                    users = [q["folder"] for q in d["projects"] if q.get("lampp") == ver]
                    name.set_tooltip_text("Conecta Docker a la MariaDB de lampp-%s" % ver)
                    acts = actions([("media-playback-stop-symbolic" if up else "media-playback-start-symbolic",
                                     "Parar el puente (%s se queda%s sin BBDD)" % (", ".join(users) or "ningún proyecto",
                                                                                   "n" if len(users) > 1 else "")
                                     if up else "Arrancar el puente",
                                     lambda up=up, n=items[0]["name"], t=title: (not up or self.nv_stop_shared_ok([n], t)) and self.run_task(
                                         ("Parando %s" if up else "Arrancando %s") % t,
                                         ["docker-contenedor", "parar" if up else "arrancar", n], auto_close=True,
                                         on_done=done), True)])  # noqa: B023 (done es el mismo en cada vuelta)
                elif re.fullmatch(r"nexum-mariadb-\d+-\d+", proj or "") and len(items) == 1:
                    acts = actions([("media-playback-stop-symbolic" if up else "media-playback-start-symbolic",
                                     "Parar %s (los proyectos que van con ella se quedan sin BBDD)" % title if up else
                                     "Arrancar %s" % title,
                                     lambda up=up, n=items[0]["name"], t=title: (not up or self.nv_stop_shared_ok([n], t)) and self.run_task(
                                         ("Parando %s" if up else "Arrancando %s") % t,
                                         ["docker-contenedor", "parar" if up else "arrancar", n], auto_close=True,
                                         on_done=done), True)])  # noqa: B023 (done es el mismo en cada vuelta)
            row([name, label(""), img_cell, pma, label(cpu_text([c["name"] for c in items]), "nv-mono", "nv-chico", "nv-tenue"), acts],
                on_click=lambda proj=proj: self.nv_dk_toggle(proj))
            if not opened:
                continue
            # (desplegado: su visor, con sus accesos directos, encima de sus contenedores)
            if p:
                vr = Gtk.ListBoxRow(activatable=False, selectable=False)
                vr.on_click = None
                vr.add(self.nv_docker_visor(p, items))
                lb.add(vr)
            for c in visible:
                on = c["state"] == "running"
                kn = Gtk.Box(spacing=8)
                kn.pack_start(nv_dot(on), False, False, 0)
                # (dentro de su proyecto, solo su parte: db-1, php-1, pma-1)
                short = c["name"][len(proj) + 1:] if proj and c["name"].startswith(proj + "-") else c["name"]
                kn.pack_start(label(short, "nv-mono", "nv-chico", ellipsize=3,
                                    tooltip_text="%s · %s" % (c["name"], docker_status_text(c["status"]))), False, False, 0)
                ports = ", ".join(pp.replace("/tcp", "").replace("127.0.0.1:", "").replace("->", ":")
                                  for pp in c["ports"].split(", ") if "->" in pp) or "—"
                own = docker_own(c["name"])
                row([kn, label(c["id"] or "—", "nv-mono", "nv-chico", "nv-tenue", selectable=True,
                               tooltip_text="ID del contenedor"),
                     label(c["image"], "nv-mono", "nv-chico", "nv-enlace", ellipsize=3),
                     label(ports, "nv-mono", "nv-chico", "nv-enlace" if ports != "—" else "nv-tenue"),
                     label(cpu_text([c["name"]]), "nv-mono", "nv-chico", "nv-tenue"),
                     actions([("media-playback-stop-symbolic" if on else "media-playback-start-symbolic", "Parar" if on else "Arrancar",
                               lambda c=c, on=on: (not on or self.nv_stop_shared_ok([c["name"]], c["name"])) and self.run_task(
                                   ("Parando %s" if on else "Arrancando %s") % c["name"],
                                                                ["docker-contenedor", "parar" if on else "arrancar", c["name"]],
                                                                auto_close=True, on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data)), own),
                              ("view-refresh-symbolic", "Reiniciar", lambda c=c: self.run_task("Reiniciando %s" % c["name"],
                                                                                              ["docker-contenedor", "reiniciar", c["name"]], auto_close=True), own and on),
                              ("text-x-generic-symbolic", "Registros", lambda c=c: self.run_task("Registros de %s" % c["name"],
                                                                                                ["docker-contenedor", "registros", c["name"]]), own),
                              ("user-trash-symbolic", "Eliminar este contenedor", lambda c=c: self.nv_container_delete(c), own)])],
                    indent=26)
        if not shown:
            r = Gtk.ListBoxRow(activatable=False)
            r.add(label("Ningún contenedor" + (" en marcha" if self.dk_only_up else "") + (" con «%s»" % self.dk_query if self.dk_query else ""),
                        "nv-tenue", margin=14))
            lb.add(r)
        return lb
