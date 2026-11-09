class AppDocker:
    """Docker (la parte de la ventana base)."""

    # ------------------------------------------------------------------ Docker
    def on_docker_data(self, rc, out):
        d = {"installed": False, "ready": False, "version": "", "lampp": False,
             "php": [], "maria": [], "projects": [], "containers": []}
        for f in parse_lines(out):
            if f[0] == "S" and len(f) >= 5:
                d.update(installed=f[1] == "1", ready=f[2] == "1", version=f[3], lampp=f[4] == "1",
                         rootful=len(f) > 5 and f[5] == "1")
            elif f[0] == "V" and len(f) >= 3:
                d["php"], d["maria"] = f[1].split(), f[2].split()
            elif f[0] == "P" and len(f) >= 9 and re.fullmatch(r"[a-z0-9-]{1,40}", f[1]):
                web = len(f) >= 13 and f[9] == "web"
                d["projects"].append({"slug": f[1], "folder": f[2], "php": f[3], "maria": f[4],
                                      "domain": f[5], "state": f[6], "db": f[7], "pma": f[8], "web": web,
                                      "kind": f[11] if web else "", "versions": f[12].split() if web else [f[3]],
                                      "lampp": f[13] if web and len(f) > 13 else ""})
            elif f[0] == "W" and len(f) >= 6:
                d["web"] = {"ip": f[1], "http": f[2], "https": f[3], "state": f[4], "ports_ok": f[5] == "1",
                            "tld": f[6] if len(f) > 6 and f[6] in ("docker.local", "docker.test") else "docker.local",
                            "dns": len(f) > 7 and f[7] == "1"}
                DOCKER_TLD[0] = d["web"]["tld"]
            elif f[0] == "C" and len(f) >= 7:
                d["containers"].append({"name": f[1], "image": f[2], "state": f[3], "status": f[4],
                                        "ports": f[5], "project": f[6], "id": f[7][:12] if len(f) > 7 else ""})
            elif f[0] == "I" and len(f) >= 6:
                d.setdefault("images", []).append({"repo": f[1], "tag": f[2], "id": f[3][:12], "size": f[4],
                                                   "created": f[5]})
            elif f[0] == "O" and len(f) >= 3:
                d.setdefault("volumes", []).append({"name": f[1], "driver": f[2]})
        if d != self.docker:
            self.docker = d
            self.build_docker()
        return False

    def build_docker(self):
        clear(self.docker_box)
        d = self.docker
        if d is None:
            self.loading(self.docker_box, "Comprobando Docker…")
            return
        if d["ready"]:
            self.docker_box.pack_start(self.build_docker_console(), False, False, 0)
        box, lb = group("Docker sin root",
                        "Cada proyecto en Docker va con el PHP que quieras (de la 5.6 a la 8.5), también "
                        "con varias versiones a la vez y la misma BBDD, en una MariaDB común. Docker tiene "
                        "su propio Apache, con las mismas reglas de seguridad y los .htaccess de cada "
                        "proyecto, así que no necesita LAMPP y funcionan a la vez. Docker corre sin root, "
                        "con tu usuario: ni un proyecto ni Docker pueden hacerse administradores del equipo.")
        if not d["installed"]:
            row = ActionRow("Docker no está instalado",
                            "Se instala Docker de Ubuntu en modo sin root (el Docker del sistema, con "
                            "root, se deja apagado). Pide la contraseña de administrador.")
            row.add_prefix(label("●", "punto-gris"))
            b = css(Gtk.Button(label="Instalar Docker", sensitive=not self.busy), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Instalando Docker sin root", ["docker-instalar"], done_text="Docker sin root instalado",
                on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data)))
            row.add_suffix(b)
            lb.add(row)
        elif not d["ready"]:
            row = ActionRow("Docker sin root no responde",
                            "Está instalado, pero su servicio (el de tu usuario) no está en marcha o no "
                            "se ha preparado. Prepararlo lo deja listo; no cambia los contenedores.")
            row.add_prefix(label("●", "punto-gris"))
            b = css(Gtk.Button(label="Prepararlo", sensitive=not self.busy), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Preparando Docker sin root", ["docker-instalar"], progress=True, done_text="Docker sin root listo",
                on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data)))
            row.add_suffix(b)
            lb.add(row)
        else:
            row = ActionRow("Docker %s, sin root" % d["version"], "En marcha con tu usuario")
            row.add_prefix(label("●", "punto-verde"))
            lb.add(row)
            if d.get("rootful"):
                # (lo deja en marcha el paquete de Ubuntu: corre como root y no hace falta)
                row = ActionRow("Hay otro Docker en marcha: el de Ubuntu, como administrador",
                                "Este programa usa el suyo, con tu usuario. El de Ubuntu arranca solo con el equipo, "
                                "no hace falta y quien lo use puede hacerse con el equipo. Apágalo salvo que lo uses "
                                "fuera de este programa (pide la contraseña; tus proyectos no se tocan).")
                row.add_prefix(css(icon("dialog-warning-symbolic"), "error"))
                b = css(Gtk.Button(label="Apagarlo", sensitive=not self.busy), "verde")
                b.connect("clicked", lambda *_: self.run_task(
                    "Apagando el Docker del sistema", ["docker-instalar"], done_text="Docker del sistema apagado",
                    auto_close=True, on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data)))
                row.add_suffix(b)
                lb.add(row)
            if not d["lampp"]:
                row = ActionRow("La versión LAMPP activa está parada",
                                "Los proyectos en Docker se abren por su Apache: arráncala en Versiones.")
                row.add_prefix(css(icon("dialog-warning-symbolic"), "error"))
                lb.add(row)
        self.docker_box.pack_start(box, False, False, 0)
        if d["ready"]:
            self.docker_box.pack_start(self.build_docker_projects(), False, False, 0)
            self.docker_box.pack_start(self.build_docker_new(), False, False, 0)
        self.docker_box.show_all()

    def build_docker_projects(self):
        d = self.docker
        box, lb = group("Proyectos en Docker",
                        "Arrancados, siguen en marcha aunque cierres esta ventana. Borrar quita sus "
                        "contenedores y la copia de su BBDD (la carpeta del proyecto y la BBDD de "
                        "LAMPP no se tocan).")
        if not d["projects"]:
            lb.add(ActionRow("Todavía no hay ningún proyecto en Docker", "Créalo abajo."))
        for p in d["projects"]:
            on = p["state"] == "marcha"
            row = ActionRow(p["folder"], "MariaDB %s  ·  https://%s%s" % (
                p["maria"], p["domain"],
                {"parcial": "  ·  a medias", "nuevo": "  ·  sin contenedores"}.get(p["state"], "")))
            dot = label("●", "punto-verde" if on else "punto-gris")
            dot.set_tooltip_text({"marcha": "En marcha", "parado": "Parado",
                                  "parcial": "Algún contenedor está parado"}.get(p["state"], p["state"]))
            row.add_prefix(dot)
            php = Gtk.Button(label="PHP %s" % p["php"], valign=Gtk.Align.CENTER, sensitive=not self.busy,
                             tooltip_text="Cambiar la versión de PHP de %s" % p["folder"])
            php.connect("clicked", lambda *_, p=p: self.on_docker_php(p))
            row.add_suffix(php)
            for ic, tip, fn, ok in [
                    ("web-browser-symbolic", "Abrir https://%s" % p["domain"],
                     lambda *_, p=p: self.open_uri("https://%s/" % p["domain"]), on),
                    ("drive-multidisk-symbolic", "Abrir su phpMyAdmin (http://127.0.0.1:%s/)" % p["pma"],
                     lambda *_, p=p: self.open_uri("http://127.0.0.1:%s/" % p["pma"]),
                     on and p["pma"].isdigit()),
                    ("text-x-generic-symbolic", "Ver los registros de sus contenedores",
                     lambda *_, p=p: self.run_task("Registros de %s" % p["folder"],
                                                   ["docker-registros", p["slug"]]), True),
                    ("media-playback-stop-symbolic" if on else "media-playback-start-symbolic",
                     "Parar sus contenedores" if on else "Arrancar sus contenedores",
                     lambda *_, p=p, on=on: self.run_task(
                         ("Parando %s" if on else "Arrancando %s") % p["folder"],
                         ["docker-parar" if on else "docker-arrancar", p["slug"]],
                         done_text="%s %s" % (p["folder"], "parado" if on else "en marcha"),
                         auto_close=True, on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data)),
                     True),
                    ("user-trash-symbolic", "Borrar el proyecto en Docker",
                     lambda *_, p=p: self.on_docker_delete(p), True)]:
                b = Gtk.Button(tooltip_text=tip, relief=Gtk.ReliefStyle.NONE,
                               sensitive=ok and not self.busy)
                b.add(icon(ic))
                b.connect("clicked", fn)
                row.add_suffix(b)
            lb.add(row)
        return box

    def build_docker_console(self):
        """Consola de Docker (arriba de la pestaña, como Docker Desktop): todos los contenedores con su
        imagen, si están en marcha, desde cuándo y sus puertos."""
        d = self.docker
        cons = d.get("containers", [])
        box = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10), "consola-docker")
        head = Gtk.Box(spacing=10)
        head.pack_start(logo("docker", 26), False, False, 0)
        head.pack_start(label("Docker", "consola-titulo"), False, False, 0)
        up = sum(1 for c in cons if c["state"] == "running")
        head.pack_end(label("%d en marcha  ·  %d parados" % (up, len(cons) - up), "consola-tenue"),
                      False, False, 0)
        box.pack_start(head, False, False, 0)
        if not cons:
            box.pack_start(label("$ docker ps\nNo hay contenedores.", "consola-tenue"), False, False, 0)
            return box
        grid = Gtk.Grid(column_spacing=18, row_spacing=4)
        for n, title in enumerate(["", "CONTENEDOR", "IMAGEN", "ESTADO", "PUERTOS"]):
            grid.attach(label(title, "consola-tenue"), n, 0, 1, 1)
        for row, c in enumerate(sorted(cons, key=lambda c: (c["project"], c["name"])), 1):
            on = c["state"] == "running"
            grid.attach(label("●", "consola-verde" if on else "consola-gris"), 0, row, 1, 1)
            # (sin el prefijo del gestor: nexum-<proyecto>-php-1 → <proyecto>-php)
            name = re.sub(r"-\d+$", "", re.sub(r"^nexum-", "", c["name"]))
            n_lbl = label(name, ellipsize=3, max_width_chars=34)
            n_lbl.set_tooltip_text(c["name"])
            grid.attach(n_lbl, 1, row, 1, 1)
            grid.attach(label(c["image"], "consola-tenue", ellipsize=3, max_width_chars=18), 2, row, 1, 1)
            grid.attach(label(docker_status_text(c["status"]), "consola-verde" if on else "consola-gris"),
                        3, row, 1, 1)
            ports = ", ".join(p for p in c["ports"].split(", ") if "->" in p) or "—"
            grid.attach(label(ports.replace("/tcp", ""), "consola-tenue"), 4, row, 1, 1)
        box.pack_start(grid, False, False, 0)
        return box

    def on_docker_php(self, p):
        """Cambiar la versión de PHP de un proyecto en Docker (solo su contenedor de PHP)."""
        versions = self.docker["php"]
        dlg = Gtk.Dialog(title="Cambiar PHP", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(460, -1)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Cambiar", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=24)
        dlg.get_content_area().add(box)
        box.pack_start(css(label("¿Con qué versión de PHP quieres %s?" % p["folder"], wrap=True,
                                 max_width_chars=50), "title-3"), False, False, 0)
        box.pack_start(label("Solo se cambia su contenedor de PHP: su BBDD, su phpMyAdmin y su "
                             "configuración se quedan como están. La primera vez con cada versión se "
                             "prepara su imagen (unos minutos). Si no arranca, vuelve a PHP %s."
                             % p["php"], "dim-label", wrap=True, max_width_chars=50), False, False, 0)
        flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=4,
                           column_spacing=8, row_spacing=8, homogeneous=True)
        first, radios = None, []
        for v in versions:
            rb = Gtk.RadioButton.new_with_label_from_widget(first, "PHP %s%s" % (v, "  (ahora)" if v == p["php"] else ""))
            first = first or rb
            rb.set_active(v == p["php"])
            radios.append((rb, v))
            flow.add(rb)
        box.pack_start(flow, False, False, 0)
        box.show_all()
        resp = run_dialog(dlg)
        chosen = next((v for rb, v in radios if rb.get_active()), None)
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT or not chosen or chosen == p["php"]:
            return
        self.run_task("%s: PHP %s → %s" % (p["folder"], p["php"], chosen), ["docker-php", p["slug"], chosen],
                      done_text="%s funciona ya con PHP %s" % (p["folder"], chosen), auto_close=True,
                      on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))

    def on_docker_delete(self, p):
        if not confirm(self.win, "¿Borrar %s de Docker?" % p["folder"],
                       "Se borran sus contenedores, su copia de la BBDD (%s) y su vhost (%s). La carpeta "
                       "y las BBDD de LAMPP no se tocan." % (p["db"], p["domain"]),
                       "Borrar de Docker", destructive=True):
            return
        self.run_task("Borrando %s de Docker" % p["folder"], ["docker-borrar", p["slug"]],
                      done_text="%s borrado de Docker" % p["folder"], auto_close=True,
                      on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))

    def build_docker_new(self):
        d = self.docker
        box, lb = group("Nuevo proyecto en Docker",
                        "Elige la carpeta del proyecto, su versión de PHP y de MariaDB y, si quieres, "
                        "la BBDD de LAMPP que se copia al contenedor. Su wp-config.php (o la "
                        "configuración de PrestaShop) se sustituye solo dentro del contenedor: el del "
                        "proyecto no cambia y la carpeta se puede seguir usando con LAMPP.")
        f = self.docker_form
        taken = {p["folder"] for p in d["projects"]}
        folders = [x for x in project_folders() if x not in taken]

        def combo_row(title, items, key, on_change=None):
            row = ActionRow(title)
            c = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
            for k, text in items:
                c.append(k, text)
            if not c.set_active_id(f.get(key) or "") and items:
                c.set_active(0)
            f[key] = c.get_active_id()
            # Ancho del nombre más largo (hasta 56 letras), para verlo entero al elegirlo
            narrow(c, min(56, max([COMBO_CHARS] + [len(t) for _k, t in items])))

            def changed(cb):
                f[key] = cb.get_active_id()
                if on_change:
                    on_change()
            c.connect("changed", changed)
            row.add_suffix(c)
            lb.add(row)
            return c
        combo_row("Carpeta", [(x, x) for x in folders], "folder",
                  lambda: GLib.idle_add(lambda: (self.docker_folder_changed(), False)[1]))
        combo_row("PHP", [(v, "PHP %s" % v) for v in d["php"]], "php")
        combo_row("MariaDB", [(v, "MariaDB %s" % v) for v in d["maria"]], "maria")
        # BBDD de LAMPP que se copia: las vinculadas a la carpeta en cada versión
        x = next((p for p in (self.projects or {}).get("list", []) if p["name"] == f.get("folder")), None)
        pairs = self.project_pairs(x) if x and self.data else []
        combo_row("BBDD que se copia", [("@vacia", "— Ninguna: vacía —")] +
                  [("%s|%s" % (i["folder"], db), "%s (lampp-%s)" % (db, i["folder"])) for i, db in pairs],
                  "source")
        # (el dominio sale solo: el de la tienda o el de la version de PHP)
        if f.get("folder"):
            dom = docker_web_domain({"slug": docker_slug(f["folder"]), "kind": project_kind(f["folder"])}, f.get("php") or "")
            row = ActionRow("Dominio", "Con el Apache de Docker (sin LAMPP), por https: " + dom)
            lb.add(row)
        row = ActionRow("")
        b = css(Gtk.Button(label="Crear en Docker", sensitive=bool(folders) and not self.busy), "verde")
        b.connect("clicked", lambda *_: self.on_docker_create())
        row.add_suffix(b)
        lb.add(row)
        return box

    def docker_folder_changed(self):
        f = self.docker_form
        f["source"] = None
        if not f.get("domain_set"):
            f["domain"] = docker_slug(f["folder"] or "") + ".docker.local" if f.get("folder") else ""
        self.build_docker()

    def on_docker_create(self):
        f = self.docker_form
        folder, php, maria = f.get("folder"), f.get("php"), f.get("maria")
        if not (folder and php and maria):
            return
        domain = docker_web_domain({"slug": docker_slug(folder), "kind": project_kind(folder)}, php)
        args = ["docker-nuevo", folder, php, maria]
        src = f.get("source")
        text = "PHP %s y MariaDB %s, en https://%s." % (php, maria, domain)
        if src and src != "@vacia" and "|" in src:
            ver, db = src.split("|", 1)
            args += ["--bd", db, "--desde", ver]
            text += " Con una copia de %s de lampp-%s (esa no se toca)." % (db, ver)
        else:
            text += " La BBDD empieza vacía."
        text += " La primera vez con cada PHP se prepara su imagen (unos minutos)."
        if not confirm(self.win, "¿Crear %s en Docker?" % folder, text, "Crear en Docker"):
            return
        self.run_task("Creando %s en Docker" % folder, args, progress=True,
                      done_text="%s en Docker: https://%s" % (folder, domain),
                      on_done=lambda *a: (f.clear(), run_quick(["gui-docker"], self.on_docker_data)))
