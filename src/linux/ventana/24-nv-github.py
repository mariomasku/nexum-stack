class NvGithub:
    """Repositorios de GitHub."""

    # ------------------------------------------------------------------ repositorios de GitHub
    def nv_github_tools(self):
        """Configuración, GitHub: la conexión (un token en el llavero o la sesión de gh), la organización o
        cuenta y los prefijos de los repositorios que se ven en Repositorios."""
        box, lb = tile_group("GitHub (Repositorios)",
                             "Para la pestaña Repositorios: la lista de una organización o cuenta de GitHub, para "
                             "clonarlos por SSH (con tu clave) en /opt/htdocs. La lista se lee con un token de GitHub, "
                             "que se guarda en el llavero de la sesión (no en un fichero), o con tu sesión de gh. "
                             "Solo se ven los repositorios que empiezan por alguno de los prefijos (en la pestaña, "
                             "«Mostrar todos» enseña el resto).")
        self.tools_box.pack_start(box, False, False, 0)
        # (debajo del correo de pruebas)
        self.tools_box.reorder_child(box, 3)

        def fill(_rc, out):
            g = next((f for f in parse_lines(out) if f[0] == "G" and len(f) >= 6), None)
            # (si Configuración se ha rehecho mientras tanto, este apartado ya no está en la ventana)
            if g is None or box.get_toplevel() is not self.win:
                return False
            self.github_out = out
            self.github = {"on": g[1] == "1", "login": g[2], "source": g[3], "account": g[4], "prefixes": g[5]}
            gh = self.github
            how = {"llavero": "con el token del llavero", "gh": "con tu sesión de gh"}.get(gh["source"], "")
            row = ActionRow("Conexión", ("Conectado como %s, %s" % (gh["login"], how)) if gh["on"] else
                            "⚠ El token ya no vale (¿caducado?): conéctalo de nuevo" if gh["source"] else
                            "Sin conectar: hace falta para ver la lista de repositorios (también los privados)")
            row.add_prefix(logo("github", 18))
            row.wide = True
            b = css(Gtk.Button(label="Conectar con un token…", valign=Gtk.Align.CENTER, sensitive=not self.busy),
                    *(() if gh["on"] else ("verde",)))
            b.connect("clicked", lambda *_: self.nv_github_token())
            row.add_suffix(b)
            if shutil.which("gh") and gh["source"] != "gh":
                b = Gtk.Button(label="Usar la sesión de gh", valign=Gtk.Align.CENTER, sensitive=not self.busy,
                               tooltip_text="Usar la sesión de gh auth login")
                b.connect("clicked", lambda *_: run_quick(["github-conectar", "--gh"], self.nv_github_done))
                row.add_suffix(b)
            if gh["source"]:
                b = Gtk.Button(label="Desconectar", valign=Gtk.Align.CENTER, sensitive=not self.busy)
                b.connect("clicked", lambda *_: run_quick(["github-desconectar"], self.nv_github_done))
                row.add_suffix(b)
            lb.add(row)
            for key, title, sub, value, width in (
                    ("cuenta", "Organización o cuenta", "La de los repositorios que se ven (por ejemplo, mi-empresa)",
                     gh["account"], 22),
                    ("prefijos", "Prefijos de los repositorios",
                     "Separados por espacios (wordpress- tienda- …); vacío: todos", gh["prefixes"], 34)):
                row = ActionRow(title, sub)
                entry = Gtk.Entry(text=value, width_chars=width, valign=Gtk.Align.CENTER)
                save = Gtk.Button(label="Guardar", valign=Gtk.Align.CENTER, sensitive=False)
                entry.connect("changed", lambda e, b=save, v=value: b.set_sensitive(e.get_text().strip() != v))
                save.connect("clicked", lambda _b, k=key, e=entry: run_quick(["github", k, e.get_text().strip()],
                                                                            self.nv_github_saved))
                entry.connect("activate", lambda e, b=save: b.get_sensitive() and b.clicked())
                row.add_suffix(entry)
                row.add_suffix(save)
                lb.add(row)
            box.show_all()
            return False
        # (lo de la última vez, al momento: se lee de nuevo al conectar o cambiar algo)
        if getattr(self, "github_out", None):
            fill(0, self.github_out)
        else:
            run_quick(["github"], fill)

    def nv_github_done(self, rc, out):
        lines = [l for l in out.strip().splitlines() if l.strip()]
        self.toast(lines[-1] if lines else ("Hecho" if rc == 0 else "No se ha podido"))
        # (la lista de antes puede ser de otra cuenta o con otros prefijos)
        self.repos, self.github_out = None, None
        self.build_tools()
        return False

    def nv_github_saved(self, rc, out):
        """Guardar la cuenta o los prefijos: si no vale, se dice en una ventana y lo escrito se queda."""
        lines = [l for l in out.strip().splitlines() if l.strip()]
        if rc != 0:
            message(self.win, "No se ha guardado", lines[-1] if lines else "No se ha podido guardar", Gtk.MessageType.WARNING)
            return False
        return self.nv_github_done(rc, out)

    def nv_github_token(self):
        dlg = Gtk.Dialog(title="Conectar con GitHub", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(520, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        head = Gtk.Box(spacing=10)
        head.pack_start(logo("github", 28), False, False, 0)
        head.pack_start(label("Token de GitHub", "nv-titulo"), False, False, 0)
        box.pack_start(head, False, False, 0)
        box.pack_start(label("Solo para leer la lista de repositorios (también los privados): se clonan por SSH, con tu "
                             "clave. Créalo en GitHub con el permiso «repo» (y «read:org» para los de una organización) "
                             "y pégalo aquí. Se guarda en el llavero de la sesión, no en un fichero.",
                             "nv-tenue", wrap=True, max_width_chars=60), False, False, 0)
        link = Gtk.LinkButton(uri="https://github.com/settings/tokens/new?scopes=repo,read:org&description=Nexum%20Dev%20Stack",
                              label="Crear un token en GitHub", halign=Gtk.Align.START)
        box.pack_start(link, False, False, 0)
        entry = Gtk.Entry(visibility=False, input_purpose=Gtk.InputPurpose.PASSWORD, activates_default=True,
                          placeholder_text="ghp_… o github_pat_…")
        box.pack_start(entry, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Conectar", Gtk.ResponseType.OK), "nv-azul")
        ok.set_sensitive(False)
        entry.connect("changed", lambda e: ok.set_sensitive(len(e.get_text().strip()) >= 20))
        dlg.set_default_response(Gtk.ResponseType.OK)
        dlg.show_all()
        resp = run_dialog(dlg)
        token = entry.get_text().strip()
        dlg.destroy()
        if resp == Gtk.ResponseType.OK and token:
            self.toast("Comprobando el token con GitHub…")
            run_quick_input(["github-conectar"], token + "\n", self.nv_github_done)

    def nv_node_load(self):
        """Pestaña Node: los proyectos de htdocs con su package.json y cómo están."""
        def got(_rc, out):
            self.nv_node_parse(out)
            self.nv_node_render()
            return False
        run_quick(["gui-node"], got)

    def nv_node_parse(self, out):
        self.node_rows = [{"folder": f[1], "kind": f[2], "running": f[3] == "marcha", "mode": f[4], "url": f[5],
                           "need": f[6], "deps": f[7] == "1", "scripts": f[8]}
                          for f in parse_lines(out) if f[0] == "P" and len(f) >= 9]

    def nv_node_render(self):
        if self.node_rows is None:
            return
        box = self.node_page
        clear(box)
        head = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        # (de título, el logotipo de Node: su hexágono y sus letras, en su color)
        title = BrandLogo("node", 34)
        title.set_halign(Gtk.Align.START)
        head.pack_start(title, False, False, 0)
        head.pack_start(label("Proyectos de %s hechos con Astro, Next, Nuxt, SvelteKit o Vite. Cada uno con su servidor en "
                              "este equipo, con tu usuario y con la versión de Node que pide." % ("/opt/htdocs" if DEMO else HTDOCS),
                              "nv-chico", "nv-tenue", wrap=True, xalign=0), False, False, 0)
        box.pack_start(head, False, False, 0)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "caja")
        for p in self.node_rows:
            lb.add(self.nv_node_row(p))
        if not self.node_rows:
            lb.add(ActionRow("Ningún proyecto de Node", "Se buscan las carpetas de %s con su package.json" % HTDOCS))
        box.pack_start(lb, False, False, 0)
        box.show_all()

    def nv_node_row(self, p):
        bits = [p["kind"], "Node %s" % p["need"] if p["need"] else ""]
        if p["running"]:
            bits.append("en marcha (%s): %s" % (p["mode"], p["url"]))
        elif not p["deps"]:
            bits.append("sin dependencias instaladas: se instalan al arrancar")
        row = ActionRow(p["folder"], " · ".join(b for b in bits if b))
        row.add_prefix(label("●", "punto-verde" if p["running"] else "punto-gris"))
        path = os.path.join(HTDOCS, p["folder"])

        def add(image, text, tip, cb, *classes, task=True):
            b = nv_button(image, text, tip, lambda *_: cb(), "nv-proyecto-btn", *classes)
            b.set_sensitive(not (task and self.busy))
            row.add_suffix(b)
        # (los de siempre, solo con su icono: el proyecto en el editor, en su carpeta y lo que dice su servidor)
        code = vscode_app()
        if code is not None:
            img = None
            if code.get_icon() is not None:
                img = Gtk.Image.new_from_gicon(code.get_icon(), Gtk.IconSize.BUTTON)
                img.set_pixel_size(18)
            add(img or "text-editor-symbolic", None, "Abrir en Visual Studio Code", lambda: self.open_in_vscode(path), task=False)
        add("folder-open-symbolic", None, "Abrir su carpeta", lambda: self.open_uri(GLib.filename_to_uri(path, None)), task=False)
        add(logo("log", 18), None, "Registro: lo último que ha dicho su servidor", lambda: self.run_task(
            "Registro de %s" % p["folder"], ["node-registro", p["folder"]]))
        if p["running"]:
            add("view-refresh-symbolic", None, "Volver a compilar y arrancar" if p["mode"] == "compilado" else "Reiniciar su servidor",
                lambda: self.nv_node_start(p, p["mode"]))
            add(logo("globo", 18), "Abrir web", "Abrir %s" % p["url"], lambda: self.open_uri(p["url"]), task=False)
        else:
            add("media-playback-start-symbolic", "Arrancar", "En desarrollo: los cambios se ven al momento",
                lambda: self.nv_node_start(p, "desarrollo"))
            add("system-run-symbolic", "Compilar", "Compilar y arrancar, como en producción",
                lambda: self.nv_node_start(p, "compilado"))
        st = tunnel_state()
        if p["running"] and st and st["target"] == p["url"]:
            add(logo("cloudflare", 18), "Compartiendo", "Ver dirección y contraseña del túnel",
                lambda: self.nv_share_dialog(), "nv-compartiendo", task=False)
        else:
            add(logo("cloudflare", 18), "Túnel", "Compartir con un túnel de Cloudflare" if p["running"] and p["mode"] == "compilado"
                else "Compilar, arrancar y compartir con un túnel de Cloudflare", lambda: self.nv_node_share(p))
        if p["running"]:
            add("media-playback-stop-symbolic", "Parar", "Parar su servidor (y su túnel, si se está compartiendo)",
                lambda: self.nv_node_stop(p))
        return row

    def nv_node_share(self, p):
        """Túnel: solo se comparte lo compilado (el túnel no deja pasar /node_modules/.vite y así el código
        fuente no sale del equipo). Si no lo está, se compila y arranca antes."""
        path = os.path.join(HTDOCS, p["folder"])
        if p["running"] and p["mode"] == "compilado":
            self.nv_share(p["url"], path, p["folder"], live=False)
            return
        if p["running"] and not confirm(self.win, "¿Compilar %s para compartirlo?" % p["folder"],
                                        "Está en desarrollo, y lo que se comparte es la versión compilada. Se para y "
                                        "arranca compilado: los cambios ya no se verán al momento.", "Compilar y compartir"):
            return

        def got(_rc, out):
            self.nv_node_parse(out)
            self.nv_node_render()
            now = next((r for r in self.node_rows if r["folder"] == p["folder"]), None)
            if now and now["running"]:
                GLib.idle_add(lambda: self.nv_share(now["url"], path, p["folder"], live=False) and False)
            return False
        self.run_task("Arrancando %s" % p["folder"], ["node-arrancar", p["folder"], "compilado"], progress=True, auto_close=True,
                      done_text="%s en marcha" % p["folder"],
                      on_done=lambda ok, *_: run_quick(["gui-node"], got) if ok else self.nv_node_load())

    def nv_node_start(self, p, mode):
        self.run_task("Arrancando %s" % p["folder"], ["node-arrancar", p["folder"], mode], progress=True, auto_close=True,
                      done_text="%s en marcha" % p["folder"], on_done=lambda *_: self.nv_node_load())

    def nv_node_stop(self, p):
        def done(*_):
            self.nv_node_load()
        self.run_task("Parando %s" % p["folder"], ["node-parar", p["folder"]], auto_close=True,
                      done_text="%s parado" % p["folder"], on_done=done)

    def nv_repos_open(self):
        """Al entrar en Repositorios: la lista de la última vez, al momento, y luego la de GitHub."""
        if self.repos is None:
            self.nv_repos_render(loading=True)
            self.nv_repos_load(cache=True)
        self.nv_repos_load()

    def nv_repos_load(self, cache=False):
        args = ["repos"] + (["--todos"] if self.repos_all else []) + (["--cache"] if cache else [])
        if not cache:
            self.repos_loading = True

        def got(_rc, out):
            if not cache:
                self.repos_loading = False
            res = {"rows": [], "error": None, "head": None}
            for f in parse_lines(out):
                if f[0] == "R" and len(f) >= 11:
                    res["rows"].append({"full": f[1], "name": f[2], "private": f[3] == "1", "date": f[4],
                                        "branch": f[5], "prefix": f[6], "web": f[7], "desc": f[8],
                                        "state": f[9], "folder": f[10]})
                elif f[0] == "C" and len(f) >= 6:
                    res["head"] = f
                elif f[0] == "E" and len(f) >= 2:
                    res["error"] = f[1]
            if cache and not res["head"]:
                return False
            if not cache and res["error"] and self.repos and self.repos.get("head"):
                # (sin conexión con GitHub: se queda la lista de la última vez, y se dice)
                self.repos["error"] = res["error"]
            else:
                self.repos = res
            self.nv_repos_render()
            return False
        run_quick(args, got)

    def nv_repos_render(self, loading=False):
        box = self.repos_page
        clear(box)
        head = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        tl = Gtk.Box(spacing=10)
        tl.pack_start(MonoLogo("github", 26), False, False, 0)
        tl.pack_start(label("Repositorios", "nv-titulo-grande"), False, False, 0)
        head.pack_start(tl, False, False, 0)
        r = self.repos or {}
        h = r.get("head")
        sub = ("%s en GitHub: %s de %s repositorios%s" % (h[2], h[5], h[4], "" if self.repos_all else " (los de sus prefijos)")
               if h else "Los repositorios de tu organización en GitHub, para clonarlos por SSH en /opt/htdocs")
        head.pack_start(label(sub, "nv-chico", "nv-tenue"), False, False, 0)
        box.pack_start(head, False, False, 0)
        if r.get("error") and not h:
            card = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10), "nv-mosaico")
            card.pack_start(label(r["error"], wrap=True, xalign=0), False, False, 0)
            b = Gtk.Button(label="Ir a Configuración", halign=Gtk.Align.START)
            b.connect("clicked", lambda *_: self.nv_tools_show("GitHub (Repositorios)"))
            card.pack_start(b, False, False, 0)
            box.pack_start(card, False, False, 0)
            box.show_all()
            return
        bar = Gtk.Box(spacing=10)
        search = Gtk.SearchEntry(placeholder_text="Buscar por nombre, descripción o web", width_chars=36)
        bar.pack_start(search, False, False, 0)
        bar.pack_start(label("Mostrar todos", "nv-tenue", valign=Gtk.Align.CENTER), False, False, 0)
        sw = Gtk.Switch(active=self.repos_all, valign=Gtk.Align.CENTER,
                        tooltip_text="Incluir los que no tienen prefijo")
        sw.connect("notify::active", lambda w, _p: (setattr(self, "repos_all", w.get_active()),
                                                    self.nv_repos_load(cache=True), self.nv_repos_load()))
        bar.pack_start(sw, False, False, 0)
        if loading or getattr(self, "repos_loading", False):
            bar.pack_end(Gtk.Spinner(active=True), False, False, 0)
        else:
            rb = nv_button("view-refresh-symbolic", None, "Leer de nuevo la lista de GitHub", lambda *_: self.nv_repos_load())
            bar.pack_end(rb, False, False, 0)
        if r.get("error"):
            bar.pack_end(label("⚠ " + r["error"], "nv-chico", wrap=True, max_width_chars=40), False, False, 0)
        box.pack_start(bar, False, False, 0)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "caja")
        for repo in r.get("rows", []):
            lb.add(self.nv_repo_row(repo))
        if not r.get("rows"):
            lb.add(ActionRow("Cargando la lista de GitHub…" if loading or getattr(self, "repos_loading", False)
                             else "Ningún repositorio", ""))

        def match(row):
            q = search.get_text().strip().lower()
            return not q or q in getattr(row, "haystack", "")
        lb.set_filter_func(match)
        search.connect("search-changed", lambda *_: lb.invalidate_filter())
        box.pack_start(lb, False, False, 0)
        box.show_all()

    def nv_repo_row(self, repo):
        bits = [b for b in (("clonado en %s" % repo["folder"]) if repo["state"] == "clonado" else "", repo["desc"], repo["web"],
                            ("actualizado el %s" % repo["date"]) if repo["date"] else "") if b]
        row = ActionRow(repo["name"] + ("  🔒" if repo["private"] else ""), " · ".join(bits))
        kind = next((k for k in ("wordpress", "prestashop") if k in repo["prefix"] or k in repo["name"]), None)
        row.add_prefix(logo(kind, 20) if kind else MonoLogo("github", 20))
        row.haystack = " ".join((repo["full"], repo["desc"], repo["web"])).lower()
        if repo["state"] == "clonado":
            b = Gtk.Button(label="Traer cambios", valign=Gtk.Align.CENTER, sensitive=not self.busy,
                           tooltip_text="Actualizar con git pull")
            b.connect("clicked", lambda *_: self.nv_repo_fetch(repo))
        elif repo["state"] == "ocupado":
            b = Gtk.Button(label="Clonar", valign=Gtk.Align.CENTER, sensitive=False,
                           tooltip_text="Ya hay una carpeta con ese nombre")
        else:
            b = css(Gtk.Button(label="Clonar", valign=Gtk.Align.CENTER, sensitive=not self.busy,
                               tooltip_text="Clonar por SSH en /opt/htdocs"), "verde")
            b.connect("clicked", lambda *_: self.nv_repo_fetch(repo))
        row.add_suffix(b)
        # (detrás, el repositorio en GitHub: sus cambios, ramas y pull requests; solo el logotipo, así
        # todos los botones quedan a la misma altura)
        # (para pegarlo en Nuevo proyecto)
        cp = Gtk.Button(valign=Gtk.Align.CENTER, tooltip_text="Copiar repositorio")
        cp.add(icon("edit-copy-symbolic"))
        cp.connect("clicked", lambda *_: self.nv_repo_copy(repo))
        row.add_suffix(cp)
        gh = Gtk.Button(valign=Gtk.Align.CENTER, tooltip_text="Abrir en GitHub")
        gh.add(MonoLogo("github", 18))
        gh.connect("clicked", lambda *_: self.open_uri("https://github.com/%s" % repo["full"]))
        row.add_suffix(gh)
        return row

    def nv_repo_copy(self, repo):
        Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text("git@github.com:%s.git" % repo["full"], -1)
        self.toast("Repositorio copiado: %s" % repo["name"])

    def nv_repo_fetch(self, repo):
        if repo["state"] == "clonado":
            if not confirm(self.win, "¿Traer los cambios de GitHub a %s?" % repo["folder"],
                           "Este repositorio ya está clonado en /opt/htdocs/%s. Se traen sus cambios de GitHub (git pull) "
                           "y se juntan con los tuyos. Si chocan con lo que tienes sin subir o sin guardar, no se toca "
                           "nada y se dice." % repo["folder"], "Traer los cambios"):
                return
            args, title = ["repo-traer", repo["full"], "--actualizar"], "Trayendo los cambios de %s" % repo["name"]
        else:
            args, title = ["repo-traer", repo["full"]], "Clonando %s" % repo["name"]

        def done(ok, *_):
            # (su estado, de nuevo: ya clonado, en su carpeta)
            self.nv_repos_load(cache=True)
            if ok and repo["state"] != "clonado":
                self.toast("%s, en Proyectos" % repo["name"])
        self.run_task(title, args, auto_close=True, done_text="Hecho", on_done=done)

    def nv_docker_tools(self):
        """Configuración del Apache de Docker (docker-web): su dirección y sus puertos, permitir que Docker
        sin root use los de menos de 1024 y que el navegador acepte el certificado de *.docker.local."""
        w = {"IP": "127.0.0.2", "HTTP": "80", "HTTPS": "443"}
        try:
            for line in open(os.path.join(LOG_DIR, "docker", "web.conf"), encoding="utf-8", errors="replace"):
                k, _, v = line.strip().partition("=")
                if k in w and re.fullmatch(r"[0-9.]{1,15}", v):
                    w[k] = v
        except OSError:
            pass
        try:
            start = int(open("/proc/sys/net/ipv4/ip_unprivileged_port_start").read().strip())
        except (OSError, ValueError):
            start = 1024
        ports_ok = min(int(w["HTTP"]), int(w["HTTPS"])) >= start
        box, lb = tile_group("Docker",
                        "Los proyectos de Docker van con su propio Apache, en otra dirección de este equipo (nunca "
                        "abierta a la red): funcionan sin LAMPP y a la vez que él, con las mismas reglas de seguridad. "
                        "Con los puertos 80 y 443, las direcciones van sin puerto.", tiles=True)
        # La dirección y los dos puertos, juntos en una tarjeta a lo ancho (con Guardar y, si hace falta, Permitir)
        entries = {}
        row = ActionRow("Dirección y puertos",
                        "De este equipo (127.x.x.x; 127.0.0.1 con 80 y 443 es la de LAMPP). HTTP lleva siempre a https; si "
                        "HTTPS no es el 443, las direcciones lo llevan (https://…:8443). "
                        + ("Docker sin root ya puede usar sus puertos." if ports_ok else
                           "Docker sin root aún no puede usar los de menos de 1024: se permite una vez."))
        row.wide = True
        # (los campos en una línea y, debajo, a la derecha, Guardar y, si hace falta, Permitir)
        form = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, valign=Gtk.Align.CENTER)
        fields = Gtk.Box(spacing=8)
        form.pack_start(fields, False, False, 0)
        buttons = Gtk.Box(spacing=8, halign=Gtk.Align.END)
        form.pack_start(buttons, False, False, 0)
        row.add_suffix(form)
        for key, text, width in (("IP", "Dirección", 13), ("HTTP", "HTTP", 5), ("HTTPS", "HTTPS", 5)):
            field = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
            field.pack_start(label(text, "nv-chico", "nv-tenue"), False, False, 0)
            e = Gtk.Entry(text=w[key], width_chars=width, max_length=15)
            field.pack_start(e, False, False, 0)
            fields.pack_start(field, False, False, 0)
            entries[key] = e

        def save(*_):
            ip, http, https = (entries[k].get_text().strip() for k in ("IP", "HTTP", "HTTPS"))
            if not re.fullmatch(r"127\.\d{1,3}\.\d{1,3}\.\d{1,3}", ip) or not http.isdigit() or not https.isdigit():
                message(self.win, "Dirección o puertos no válidos",
                        "La dirección tiene que ser de este equipo (127.x.x.x, como 127.0.0.2) y los puertos, números.",
                        Gtk.MessageType.WARNING)
                return
            self.run_task("Dirección y puertos del Apache de Docker", ["docker-web", "puertos", ip, http, https],
                          done_text="Apache de Docker en %s (%s y %s)" % (ip, http, https), auto_close=True,
                          on_done=lambda *a: (run_quick(["gui-docker"], self.on_docker_data), self.build_tools()))
        if not ports_ok:
            b = Gtk.Button(label="Permitir", sensitive=not self.busy,
                           tooltip_text="Permitir puertos desde el %s"
                           % min(int(w["HTTP"]), int(w["HTTPS"])))
            b.connect("clicked", lambda *_: self.run_task(
                "Permitiendo los puertos del Apache de Docker", ["docker-web", "permitir"], auto_close=True,
                done_text="Docker ya puede usar sus puertos",
                on_done=lambda *a: (run_quick(["gui-docker"], self.on_docker_data), self.build_tools())))
            buttons.pack_start(b, False, False, 0)
        b = css(Gtk.Button(label="Guardar", sensitive=not self.busy), "verde")
        b.connect("clicked", save)
        buttons.pack_start(b, False, False, 0)
        lb.add(row)
        # DNS comodín de *.docker.test: los dominios de Docker ya no van en /etc/hosts (sin contraseña al
        # añadir proyectos o versiones). web.local y lo demás, igual
        conf = {}
        try:
            for line in open(os.path.join(LOG_DIR, "docker", "web.conf"), encoding="utf-8", errors="replace"):
                k, _, v = line.strip().partition("=")
                conf[k] = v
        except OSError:
            pass
        dns = conf.get("DNS") == "1" and conf.get("TLD") == "docker.test"
        row = ActionRow("DNS de *.docker.test",
                        "Puesto: los dominios de Docker (<proyecto>-php83.docker.test) no van en /etc/hosts ni piden la contraseña"
                        if dns else "Los dominios de Docker pasan a .docker.test y dejan de ir en /etc/hosts: sin contraseña al "
                        "añadir proyectos o versiones. web.local, los proyectos de siempre y las tiendas falseadas, igual")
        b = Gtk.Button(label="Quitar" if dns else "Activar", valign=Gtk.Align.CENTER, sensitive=not self.busy)
        b.connect("clicked", lambda *_: self.nv_docker_dns(not dns))
        row.add_suffix(b)
        lb.add(row)
        row = ActionRow("Certificado de *.docker.local y *.docker.test",
                        "Chrome y Firefox lo aceptan sin aviso: solo vale para esos dominios (no es de una CA)")
        b = Gtk.Button(label="Confiar", valign=Gtk.Align.CENTER, sensitive=not self.busy)
        b.connect("clicked", lambda *_: self.run_task("Certificado de Docker en el navegador", ["docker-web", "confiar"],
                                                      done_text="El navegador acepta el certificado de Docker", auto_close=True))
        row.add_suffix(b)
        lb.add(row)
        # Los proyectos sin visitas se paran solos (docker-reposo): cuántas horas (0: nunca; 3 si no se ha dicho)
        try:
            idle = open(os.path.join(LOG_DIR, "docker", "reposo"), encoding="utf-8").read(10).strip()
        except OSError:
            idle = "3"
        idle = idle if re.fullmatch(r"[0-9]|1[0-9]|2[0-4]", idle) else "3"
        try:
            last = open(os.path.join(LOG_DIR, "docker-reposo.log"), encoding="utf-8", errors="replace").read().strip().splitlines()[-1]
        except (OSError, IndexError):
            last = ""
        row = ActionRow("Parar los proyectos sin visitas",
                        ("Un proyecto de Docker que lleva esas horas sin ninguna visita (tampoco por el túnel) se para "
                         "solo, y con él lo común que ya no use nadie (su MariaDB, el Apache de Docker): no gasta "
                         "memoria ni CPU. Se mira cada 15 minutos, también con la ventana cerrada. Al entrar en uno "
                         "parado, la web lo dice: se arranca en la pestaña Docker." if idle != "0" else
                         "Apagado: los proyectos de Docker siguen en marcha hasta que se paren a mano")
                        + ("\nLo último: %s" % last if last and idle != "0" else ""))
        row.wide = True
        combo = Gtk.ComboBoxText(valign=Gtk.Align.CENTER, sensitive=not self.busy)
        for h in ("0", "1", "2", "3", "4", "6", "8", "12", "24"):
            combo.append(h, "Nunca" if h == "0" else "A la hora sin visitas" if h == "1" else "A las %s h sin visitas" % h)
        if not combo.set_active_id(idle):
            combo.append(idle, "A las %s h sin visitas" % idle)
            combo.set_active_id(idle)
        combo.connect("changed", lambda c: c.get_active_id() != idle and run_quick(
            ["docker-reposo", "horas", c.get_active_id()],
            lambda rc, out: (self.toast((out.strip().splitlines() or ["Hecho"])[-1]), self.build_tools(), False)[2]))
        row.add_suffix(combo)
        lb.add(row)
        self.tools_box.pack_start(box, False, False, 0)
        self.tools_box.reorder_child(box, 2)
        box.show_all()

    def nv_tunnel_tools(self):
        """Configuración, Túnel de Cloudflare: cloudflared, el túnel abierto (con Cerrar) y su registro. La
        contraseña, las horas y el admin de cada túnel se eligen al abrirlo («Compartir»)."""
        box, lb = tile_group("Túnel de Cloudflare",
                        "Para enseñar una web de este equipo a un cliente o a un compañero: una dirección "
                        "https://….trycloudflare.com (sin cuenta de Cloudflare; cambia cada vez) con contraseña, "
                        "que se cierra sola. Sin abrir puertos del router. La web no se toca: su dominio local se "
                        "cambia por el del túnel al pasar. Se abre con «Compartir» en el visor del proyecto, y "
                        "ahí se elige su contraseña, cuánto dura y si se bloquea el admin.")
        self.tools_box.pack_start(box, False, False, 0)
        self.tools_box.reorder_child(box, 3)
        def fill(rc, out):
            info = next((f for f in parse_lines(out) if f[0] == "I" and len(f) >= 4), None)
            row = ActionRow("cloudflared", "Aún no está: se descarga de GitHub la primera vez que compartes (unos 40 MB)"
                            if not info or info[1] != "1" else "Versión %s, en ~/.lvm-instalador/tunel" % info[2])
            if info and (info[1] != "1" or info[2] != info[3]):
                b = Gtk.Button(label="Instalar" if info[1] != "1" else "Actualizar a la %s" % info[3],
                               valign=Gtk.Align.CENTER, sensitive=not self.busy)
                b.connect("clicked", lambda *_: self.run_task("Instalando cloudflared", ["tunel-instalar"], progress=True, auto_close=True,
                                                              done_text="cloudflared instalado",
                                                              on_done=lambda *a: self.build_tools()))
                row.add_suffix(b)
            lb.insert(row, 0)
            row.show_all()
            return False
        run_quick(["tunel"], fill)
        # (cloudflared y el registro, juntos en una fila; el túnel abierto, debajo a lo ancho)
        reg = os.path.join(LOG_DIR, "tunel", "registro")
        if os.path.isfile(reg):
            row = ActionRow("Registro del túnel", "Quién entra, las contraseñas equivocadas y lo que se bloquea (el último túnel)")
            b = Gtk.Button(label="Ver", valign=Gtk.Align.CENTER)
            b.connect("clicked", lambda *_: self.show_log_tail(reg))
            row.add_suffix(b)
            lb.add(row)
        st = tunnel_state()
        if st:
            row = ActionRow("Túnel abierto", "%s → %s, hasta las %s" % (st["url"], st["target"],
                                                                       time.strftime("%H:%M", time.localtime(st["expires"]))))
            row.add_suffix(Gtk.Button(label="Ver", valign=Gtk.Align.CENTER))
            row.suffix.get_children()[-1].connect("clicked", lambda *_: self.nv_share_dialog())
            b = css(Gtk.Button(label="Cerrar", valign=Gtk.Align.CENTER), "destructive-action")
            b.connect("clicked", lambda *_: self.nv_tunnel_close())
            row.add_suffix(b)
            row.wide = True
            lb.add(row)
        box.show_all()

    def nv_place_buttons(self, acts, btns, fixed=(), conf=None):
        """Los botones del visor (clave: botón) en acts: los que se ven, en su orden y con su estilo. fixed:
        los que van siempre (botón, icono, nombre), ya colocados: con el mismo estilo y el mismo tamaño."""
        conf = conf or buttons_conf()
        specs = dict((k, i) for k, _n, i in VISOR_BUTTONS)
        for key in conf["order"]:
            if key in btns and key not in conf["hidden"]:
                b = btns[key]
                self.nv_restyle(b, conf, ("logo", b.nv_logo) if getattr(b, "nv_logo", None) else specs[key],
                                dict((k, n) for k, n, _i in VISOR_BUTTONS)[key])
                acts.pack_start(b, False, False, 0)
        for b, spec, name in fixed:
            self.nv_restyle(b, conf, spec, name)

    def nv_restyle(self, b, conf, spec, name):
        """Un botón de nv_button (o un menú de nv_menu_button) como dice conf: con su nombre (como está),
        solo el icono o con el icono y el nombre debajo, en un cuadrado de conf["size"] de lado."""
        if conf["style"] == "nombre":
            return
        old = b.get_child()
        texts = [w.get_text() for w in old.get_children() if isinstance(w, Gtk.Label)] \
            if isinstance(old, Gtk.Container) else []
        name = texts[0] if texts else name
        tip = b.get_tooltip_text()
        b.remove(old)
        side = conf["size"]
        if isinstance(b, Gtk.Button):
            b.set_relief(Gtk.ReliefStyle.NORMAL)
        css(b, "nv-proyecto-btn", "nv-boton-cuadrado")
        if conf["style"] == "icono":
            b.add(button_icon(spec, max(16, side // 2)))
            # (⋮ «Más», sin mensaje: solo despliega su menú)
            b.set_tooltip_text(None if name == "Más" else
                               "%s: %s" % (name, tip) if tip and not tip.startswith(name) else tip or name)
        else:
            side = max(side, BUTTON_SIZE_NAMED)
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, valign=Gtk.Align.CENTER)
            box.pack_start(button_icon(spec, max(18, side * 2 // 5)), False, False, 0)
            box.pack_start(label(name, "nv-chico", xalign=0.5, ellipsize=3, max_width_chars=max(6, side // 8)),
                           False, False, 0)
            b.add(box)
        b.set_size_request(side, side)
        b.set_valign(Gtk.Align.CENTER)
        b.show_all()

    def nv_buttons_dialog(self):
        """Personalizar los botones del visor: cuáles se ven, en qué orden y cómo."""
        conf = buttons_conf()
        names = dict((k, (n, i)) for k, n, i in VISOR_BUTTONS)
        dlg = Gtk.Dialog(title="Botones del proyecto", transient_for=self.win, modal=True, use_header_bar=True)
        # (en horizontal: la lista a la izquierda y el estilo, el tamaño y la vista previa a la derecha, para
        # que quepa en la altura de un portátil)
        dlg.set_default_size(900, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        box.pack_start(label("Botones del visor del proyecto", "nv-titulo"), False, False, 0)
        box.pack_start(label("Los que se ven y en qué orden (el del proyecto cargado y el de Docker). Desmontar, ⋮ "
                             "y los propios de Docker (Versiones de PHP, Arrancar o Parar) se ven siempre.",
                             "nv-tenue", wrap=True, max_width_chars=110), False, False, 0)
        cols = Gtk.Box(spacing=26)
        box.pack_start(cols, True, True, 0)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE, valign=Gtk.Align.START), "caja")
        lb.set_size_request(320, -1)
        cols.pack_start(lb, False, False, 0)
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        cols.pack_start(side, True, True, 0)

        def fill():
            for row in lb.get_children():
                lb.remove(row)
            for n, key in enumerate(conf["order"]):
                name, spec = names[key]
                row = ActionRow(name)
                row.prefix.foreach(row.prefix.remove)
                chk = Gtk.CheckButton(active=key not in conf["hidden"], tooltip_text="Verlo en el visor")
                chk.connect("toggled", lambda w, k=key: (conf["hidden"].discard(k) if w.get_active() else conf["hidden"].add(k),
                                                         show_preview()))
                row.add_prefix(chk)
                row.add_prefix(button_icon(spec, 18))
                for icon_name, step, tip in (("go-up-symbolic", -1, "Antes"), ("go-down-symbolic", 1, "Después")):
                    b = nv_button(icon_name, None, tip, lambda *_, i=n, d=step: move(i, d), flat=True)
                    b.set_sensitive(0 <= n + step < len(conf["order"]))
                    row.add_suffix(b)
                lb.add(row)
            lb.show_all()

        def move(i, d):
            o = conf["order"]
            o[i], o[i + d] = o[i + d], o[i]
            fill()
        fill()
        grid = Gtk.Grid(column_spacing=12, row_spacing=10)
        grid.attach(label("Estilo", valign=Gtk.Align.CENTER), 0, 0, 1, 1)
        combo = Gtk.ComboBoxText(hexpand=True)
        for key, text in BUTTON_STYLES:
            combo.append(key, text)
        combo.set_active_id(conf["style"])
        grid.attach(combo, 1, 0, 2, 1)
        grid.attach(label("Tamaño", valign=Gtk.Align.CENTER), 0, 1, 1, 1)
        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, BUTTON_SIZE_MIN, BUTTON_SIZE_MAX, 4)
        scale.set_draw_value(False)
        scale.set_hexpand(True)
        scale.set_value(conf["size"])
        grid.attach(scale, 1, 1, 1, 1)
        size_lbl = label("", "nv-mono", "nv-tenue", width_chars=9)
        grid.attach(size_lbl, 2, 1, 1, 1)
        side.pack_start(grid, False, False, 0)
        # Vista previa: los botones que se ven, como quedarán (con Desmontar y ⋮)
        side.pack_start(label("Así quedan", "nv-chico", "nv-tenue"), False, False, 0)
        # (en varias filas si no caben: se ven todos, del tamaño que tendrán)
        preview = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, column_spacing=8, row_spacing=8,
                              max_children_per_line=12, homogeneous=False, margin=4)
        side.pack_start(preview, False, False, 0)
        touched = {"size": False}

        def show_preview(*_):
            conf["style"] = combo.get_active_id() or "nombre"
            conf["size"] = int(scale.get_value())
            square = conf["style"] != "nombre"
            scale.set_sensitive(square)
            side = max(conf["size"], BUTTON_SIZE_NAMED) if conf["style"] == "grande" else conf["size"]
            size_lbl.set_label("%d×%d px" % (side, side) if square else "—")
            preview.foreach(preview.remove)
            btns = {}
            for key, name, spec in VISOR_BUTTONS:
                btns[key] = nv_button(button_icon(spec, 18), name, None, None, "nv-proyecto-btn")
            fixed = [(nv_button("media-eject-symbolic", None, "Desmontar", None, flat=True),
                      ("icono", "media-eject-symbolic"), "Desmontar"),
                     (self.nv_menu_button(None, "view-more-symbolic", []), ("icono", "view-more-symbolic"), "Más")]
            row = Gtk.Box()
            self.nv_place_buttons(row, btns, fixed, conf)
            for b in row.get_children() + [b for b, _spec, _name in fixed]:
                if b.get_parent():
                    b.get_parent().remove(b)
                b.set_can_focus(False)
                # (cada uno de su tamaño, sin estirarse al ancho de la columna)
                b.set_halign(Gtk.Align.START)
                preview.add(b)
            preview.show_all()

        def style_changed(*_):
            if not touched["size"]:
                scale.set_value(BUTTON_SIZES.get(combo.get_active_id(), conf["size"]))
            show_preview()

        def size_changed(*_):
            touched["size"] = True
            show_preview()
        combo.connect("changed", style_changed)
        scale.connect("value-changed", size_changed)
        refill = fill

        def fill():
            refill()
            show_preview()
        show_preview()

        def reset(*_):
            conf.update(order=[k for k, _n, _i in VISOR_BUTTONS], hidden=set())
            touched["size"] = False
            combo.set_active_id("nombre")
            fill()
        rb = css(Gtk.Button(label="Como al principio", halign=Gtk.Align.START,
                            tooltip_text="Volver a los botones de siempre"), "flat")
        rb.connect("clicked", reset)
        side.pack_end(rb, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Guardar", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        dlg.show_all()
        resp = run_dialog(dlg)
        conf["style"] = combo.get_active_id() or "nombre"
        conf["size"] = int(scale.get_value())
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return
        try:
            buttons_save(conf)
        except OSError as exc:
            message(self.win, "No se han podido guardar los botones", str(exc), Gtk.MessageType.ERROR)
            return
        self.nv_tunnel_refresh()
        self.toast("Botones del proyecto guardados")

    def nv_share_button(self, url, folder, name, tip_extra=""):
        """«Compartir» del visor de un proyecto: abre un túnel de Cloudflare a esa dirección; si ya lo
        está, «Compartiendo» (en verde) enseña la dirección y la contraseña."""
        st = tunnel_state()
        mine = bool(st) and st["target"] == url.rstrip("/")
        b = nv_button(logo("cloudflare", 18), "Compartiendo" if mine else "Compartir",
                      "Ver dirección y contraseña" if mine else
                      "Compartir con un túnel de Cloudflare%s" % tip_extra,
                      lambda *_: self.nv_share_dialog() if mine else self.nv_share(url, folder, name), "nv-proyecto-btn")
        if mine:
            css(b, "nv-compartiendo")
        return b

    def nv_share(self, url, folder, name, live=True):
        """Abre un túnel a esa web, con lo suyo, que se elige ahora: cuánto dura y si se bloquea el panel de
        administración. Su contraseña, siempre una nueva al azar (se ve al abrirlo, para copiarla)."""
        st = tunnel_state()
        dlg = Gtk.Dialog(title="Compartir", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(560, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        head = Gtk.Box(spacing=10)
        head.pack_start(logo("cloudflare", 30), False, False, 0)
        head.pack_start(label("Compartir %s" % name, "nv-titulo", wrap=True), False, False, 0)
        box.pack_start(head, False, False, 0)
        text = ("Cualquiera que tenga la dirección y la contraseña verá %s tal y como está en este equipo%s mientras "
                "el túnel esté abierto." % (url, " (lo que cambies, al momento)" if live else ""))
        if st:
            text += " Se cierra el que hay abierto (%s)." % st["target"]
        if not os.path.isfile(os.path.join(LOG_DIR, "tunel", "cloudflared")):
            text += " La primera vez se descarga cloudflared, el programa de Cloudflare (unos 40 MB)."
        text += " Lleva una contraseña nueva al azar: se ve al abrirlo, para copiarla y mandarla."
        box.pack_start(label(text, "nv-tenue", wrap=True, max_width_chars=64), False, False, 0)
        grid = Gtk.Grid(column_spacing=14, row_spacing=10, margin_top=4)
        grid.attach(label("Se cierra solo en", valign=Gtk.Align.CENTER), 0, 1, 1, 1)
        hours = Gtk.Box(spacing=6)
        spin = Gtk.SpinButton.new_with_range(1, 12, 1)
        spin.set_value(2)
        hours.pack_start(spin, False, False, 0)
        hours.pack_start(label("horas", "nv-tenue", valign=Gtk.Align.CENTER), False, False, 0)
        grid.attach(hours, 1, 1, 2, 1)
        grid.attach(label("Bloquear el panel de\nadministración", valign=Gtk.Align.CENTER), 0, 2, 1, 1)
        sw = Gtk.Switch(active=True, halign=Gtk.Align.START, valign=Gtk.Align.CENTER)
        grid.attach(sw, 1, 2, 1, 1)
        note = label("", "nv-chico", wrap=True, max_width_chars=64)
        box.pack_start(grid, False, False, 0)
        box.pack_start(note, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Compartir", Gtk.ResponseType.OK), "nv-azul")
        dlg.set_default_response(Gtk.ResponseType.OK)

        def update(*_):
            note.set_label("wp-admin y el admin de PrestaShop no se abren por el túnel (tus BBDD llevan el administrador "
                           "de pruebas, con una contraseña conocida)" if sw.get_active() else
                           "⚠ El panel de administración se podrá abrir por el túnel: cualquiera con la contraseña puede "
                           "probar a entrar")
        sw.connect("notify::active", update)
        dlg.show_all()
        update()
        resp = run_dialog(dlg)
        h, admin = str(spin.get_value_as_int()), "bloquear" if sw.get_active() else "permitir"
        dlg.destroy()
        if resp != Gtk.ResponseType.OK:
            return
        args = ["tunel-abrir", url, folder, "--horas", h, "--admin", admin]

        def opened(ok_, *_):
            self.nv_tunnel_refresh()
            if ok_ and tunnel_state():
                self.nv_share_dialog()
        if not os.path.isfile(os.path.join(LOG_DIR, "tunel", "cloudflared")):
            self.run_task("Instalando cloudflared", ["tunel-instalar"], progress=True, auto_close=True, done_text="cloudflared instalado",
                          on_done=lambda ok_, *a: ok_ and GLib.idle_add(
                              lambda: self.run_task("Abriendo el túnel de %s" % name, args, auto_close=True,
                                                    done_text="Túnel abierto", on_done=opened) and False))
            return
        self.run_task("Abriendo el túnel de %s" % name, args, auto_close=True, done_text="Túnel abierto",
                      on_done=opened)

    def nv_share_dialog(self):
        """La dirección del túnel abierto y su contraseña, para copiarlas y mandarlas."""
        st = tunnel_state()
        if not st:
            self.toast("El túnel ya está cerrado")
            self.nv_tunnel_refresh()
            return
        password, blocked = st.get("password", ""), st.get("admin") != "permitir"
        until = time.strftime("%H:%M", time.localtime(st["expires"]))
        clip = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
        dlg = Gtk.Dialog(title="Túnel de Cloudflare", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(640, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        head = Gtk.Box(spacing=10)
        head.pack_start(logo("cloudflare", 30), False, False, 0)
        head.pack_start(label("Compartiendo %s" % st["target"], "nv-titulo", wrap=True), False, False, 0)
        box.pack_start(head, False, False, 0)
        # La dirección y la contraseña, cada una en su fila: su nombre encima, el valor a la izquierda y Copiar a
        # la derecha. Lo copiado se dice debajo, en verde (el aviso de la ventana queda detrás del diálogo)
        copied = label("", "nv-verde", xalign=0)
        timer = [0]

        def copy(text, what):
            clip.set_text(text, -1)
            copied.set_label("✓ %s" % what)
            if timer[0]:
                GLib.source_remove(timer[0])
            timer[0] = GLib.timeout_add_seconds(4, lambda: (copied.set_label(""), timer.__setitem__(0, 0), False)[2])
        fields = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE, margin_top=4), "caja")
        fields.set_header_func(lambda row, before: row.set_header(Gtk.Separator() if before is not None else None))
        for title, value in (("Dirección", st["url"]), ("Contraseña", password)):
            row = Gtk.Box(spacing=12, margin=12)
            texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, valign=Gtk.Align.CENTER)
            texts.pack_start(label(title, "nv-tenue", "nv-chico", xalign=0, halign=Gtk.Align.START), False, False, 0)
            texts.pack_start(label(value, "nv-mono", selectable=True, xalign=0, halign=Gtk.Align.START,
                                   ellipsize=3, max_width_chars=60, tooltip_text=value), False, False, 0)
            row.pack_start(texts, True, True, 0)
            b = nv_button("edit-copy-symbolic", "Copiar", "Copiar %s" % title.lower(),
                          lambda *_, v=value, w=title: copy(v, "%s copiada" % w))
            b.set_valign(Gtk.Align.CENTER)
            row.pack_end(b, False, False, 0)
            r = Gtk.ListBoxRow(activatable=False, selectable=False)
            r.add(row)
            fields.add(r)
        box.pack_start(fields, False, False, 0)
        box.pack_start(copied, False, False, 0)
        box.pack_start(label("Se cierra solo a las %s. %s Quién entra y lo que se bloquea queda en el registro del "
                             "túnel (Configuración, Túnel de Cloudflare)." % (
                                 until, "El panel de administración va bloqueado." if blocked
                                 else "⚠ El panel de administración no va bloqueado."),
                             "nv-tenue", wrap=True, max_width_chars=64), False, False, 0)
        acts = Gtk.Box(spacing=8)
        msg = ("Te paso la web en pruebas:\n%s\nContraseña: %s\n(Funciona hasta las %s.)" % (st["url"], password, until))
        acts.pack_start(nv_button("mail-send-symbolic", "Copiar para enviar", "Copiar dirección y contraseña",
                                  lambda *_: copy(msg, "Dirección y contraseña copiadas, listas para enviar"), "nv-azul"),
                        False, False, 0)
        acts.pack_start(nv_button("web-browser-symbolic", "Abrir", "Abrirla tú en el navegador",
                                  lambda *_: self.open_uri(st["url"])), False, False, 0)
        box.pack_start(acts, False, False, 0)
        dlg.get_content_area().add(box)
        close = dlg.add_button("Cerrar el túnel", Gtk.ResponseType.REJECT)
        css(close, "destructive-action")
        dlg.add_button("Listo", Gtk.ResponseType.CLOSE)
        dlg.set_default_response(Gtk.ResponseType.CLOSE)
        dlg.show_all()
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp == Gtk.ResponseType.REJECT:
            self.nv_tunnel_close()

    def nv_tunnel_close(self):
        def done(rc, out):
            self.toast("Túnel cerrado: la dirección ya no lleva a ningún sitio" if rc == 0 else "No se ha podido cerrar el túnel")
            self.nv_tunnel_refresh()
            return False
        run_quick(["tunel-cerrar"], done)

    def nv_tunnel_refresh(self):
        """Los botones de Compartir y Configuración, con el túnel como esté ahora."""
        for fn in (self.nv_build_projects, self.nv_dk_table, self.nv_node_render, self.build_tools):
            try:
                fn()
            except Exception:  # noqa: BLE001 - una pestaña aún sin datos
                pass

    def nv_docker_dns(self, on):
        """docker-web dns activar|quitar"""
        if on:
            if not confirm(self.win, "¿Activar el DNS de *.docker.test?",
                           "Un DNS mínimo, solo en este equipo (127.0.0.1), que contesta a cualquier <algo>.docker.test. Los "
                           "proyectos del Apache de Docker pasan a .docker.test (su configuración, el dominio de las tiendas en "
                           "su BBDD y el certificado) y sus líneas salen de /etc/hosts. Desde entonces, añadir proyectos o "
                           "versiones de Docker no pide la contraseña por los dominios. web.local, los proyectos de siempre y "
                           "los dominios falseados de las tiendas no cambian. Si no contesta, se quita y todo sigue como "
                           "estaba. Pide la contraseña de administrador.", "Activar"):
                return
        elif not confirm(self.win, "¿Quitar el DNS de *.docker.test?",
                         "Los dominios de Docker siguen siendo .docker.test y vuelven a /etc/hosts. Pide la contraseña de "
                         "administrador.", "Quitar", destructive=True):
            return
        self.run_task("Activando el DNS de *.docker.test" if on else "Quitando el DNS de *.docker.test",
                      ["docker-web", "dns", "activar" if on else "quitar"],
                      done_text="DNS de *.docker.test " + ("puesto" if on else "quitado"),
                      on_done=lambda *a: (run_quick(["gui-docker"], self.on_docker_data), self.build_tools()))

    def on_cross_site(self, sw, _p):
        on = sw.get_active()
        if on == (not os.path.exists(os.path.join(LOG_DIR, "sin-barrera-entre-webs"))):
            return
        self.run_task("Encendiendo la barrera entre webs" if on else "Apagando la barrera entre webs",
                      ["barrera-web", "si" if on else "no"], auto_close=True,
                      done_text="Barrera entre webs %s" % ("encendida" if on else "apagada"),
                      on_done=lambda *_: self.build_tools())
