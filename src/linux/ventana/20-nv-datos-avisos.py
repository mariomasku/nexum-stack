class NvDatosAvisos:
    """Los datos de la ventana, las versiones y los avisos."""

    # ------------------------------------------------------------------ datos
    def on_data(self, rc, out):
        res = super().on_data(rc, out)
        d = self.data
        if d:
            act = next((i for i in d["installs"] if i["folder"] == d["active"]), None)
            self.status_lbl.set_label("PHP %s" % act["php"] if act else "Ninguna versión activa")
            self.status_sub.set_label("lampp-%s" % d["active"] if act else "")
            self.nv_power_state()
            self.nv_projects_refresh()
            self.nv_mail_header()
        self.nv_tray_update()
        return res

    def on_services_data(self, rc, out):
        res = super().on_services_data(rc, out)
        self.nv_power_state()
        return res

    def nv_power_state(self):
        """Puntos de Apache y MariaDB (de gui-servicios)."""
        d = self.data
        if not d:
            return
        svc = {s["name"]: s["running"] for s in (self.services or [])}
        for name, dt in self.svc_dots.items():
            on = svc.get(name.lower(), False) if svc else d["running"]
            ctx = dt.get_style_context()
            ctx.remove_class("nv-gris" if on else "nv-verde")
            ctx.add_class("nv-verde" if on else "nv-gris")
            (ctx.add_class if on else ctx.remove_class)("nv-latido")

    def update_project_search(self):
        # (la busqueda de siempre sigue funcionando por detras: la usa el asistente de proyecto nuevo)
        if getattr(self, "proj_results", None) is not None:
            super().update_project_search()
        self.nv_build_projects()

    def on_docker_data(self, rc, out):
        res = super().on_docker_data(rc, out)
        self.nv_projects_refresh()
        return res

    def nv_projects_refresh(self):
        """Rehace Proyectos solo si ha cambiado algo de lo que enseña: los datos, los proyectos y Docker (on_data
        y los demás solo los cambian si llega algo distinto) y el túnel abierto. Cada 20 s llegan los datos de
        siempre: rehacerla entera cada vez costaba unos 400 ms de la interfaz, varias veces por vuelta."""
        key = (self.data, self.projects, self.docker, repr(tunnel_state()))
        old = getattr(self, "nv_proj_key", None)
        if old is not None and all(a is b for a, b in zip(old[:3], key[:3])) and old[3] == key[3]:
            return
        self.nv_proj_key = key
        self.nv_build_projects()

    # ------------------------------------------------------------------ versiones y avisos
    def build_versions(self):
        # Los de siempre se construyen en una caja que no se ve: de ahi salen los avisos (todo lo que
        # va antes de Cargar proyecto), que pasan al boton de avisos de arriba
        clear(self.legacy_box)
        self.ver_box = self.legacy_box
        super().build_versions()
        clear(self.warn_box)
        n = 0
        for child in list(self.legacy_box.get_children()):
            if child is getattr(self, "proj_box", None):
                break
            self.legacy_box.remove(child)
            self.warn_box.pack_start(child, False, False, 0)
            n += 1
        self.nv_warn_refresh()
        if self.inst_box.get_parent() is self.legacy_box:
            self.legacy_box.remove(self.inst_box)
        self.nv_build_versions()

    def nv_branch(self, php):
        """Linea B (de gui-ramas) de la rama de una version de PHP, o None si no se ha consultado."""
        branch = ".".join(php.split(".")[:2])
        return next((f for f in (self.branches or []) if f[0] == "B" and len(f) > 2 and f[1] == branch), None)

    def on_branches(self, rc, out):
        res = super().on_branches(rc, out)
        if self.data:
            self.nv_build_versions()
        return res

    def nv_build_versions(self):
        clear(self.vers_page)
        d = self.data
        head = Gtk.Box(spacing=12)
        t = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        tl = Gtk.Box(spacing=10)
        tl.pack_start(logo("php", 34), False, False, 0)
        tl.pack_start(label("Versiones de PHP", "nv-titulo-grande"), False, False, 0)
        t.pack_start(tl, False, False, 0)
        t.pack_start(label("Cada versión con su Apache, MariaDB y sus propias BBDD. Soporte y parches, según php.net",
                           "nv-chico", "nv-tenue"), False, False, 0)
        head.pack_start(t, True, True, 0)
        head.pack_end(nv_button("list-add-symbolic", "Instalar versión…", None, lambda *_: self.nv_install_dialog(),
                                "nv-azul"), False, False, 0)
        head.pack_end(nv_button(logo("apache", 16), "Componentes", "Componentes de cada versión",
                                lambda *_: self.nv_components_dialog()), False, False, 0)
        self.vers_page.pack_start(head, False, False, 0)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "nv-grupo")
        widths = [240, 90, 230, 200, 60, 0]
        groups = [Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL) for _ in widths]

        def row(cells, head_row=False):
            r = Gtk.ListBoxRow(activatable=False)
            b = css(Gtk.Box(spacing=14), "nv-fila", *(["nv-cab"] if head_row else []))
            for n, c in enumerate(cells):
                w = c if isinstance(c, Gtk.Widget) else label(c.upper() if head_row else c)
                if widths[n]:
                    w.set_size_request(widths[n], -1)
                    groups[n].add_widget(w)
                b.pack_start(w, n == len(cells) - 1, True, 0)
            hover = getattr(cells[-1], "hover_button", None)
            if hover is not None:
                ev = Gtk.EventBox(above_child=False)
                ev.add_events(Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK)
                ev.connect("enter-notify-event", lambda *_, h=hover: (h.set_opacity(1), False)[1])
                ev.connect("leave-notify-event", lambda _w, e, h=hover: (e.detail == Gdk.NotifyType.INFERIOR
                                                                          or h.set_opacity(0), False)[1])
                ev.add(b)
                r.add(ev)
            else:
                r.add(b)
            lb.add(r)
        row(["Versión", "PHP", "Soporte", "Último parche", "BBDD", ""], True)
        for inst in self.installs():
            folder = inst["folder"]
            act = folder == d["active"]
            date = self.php_dates.get(folder)
            name = Gtk.Box(spacing=8)
            name.pack_start(nv_dot(act and d["running"]), False, False, 0)
            nt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            tl = Gtk.Box(spacing=6)
            tl.pack_start(label("lampp-%s" % folder, "nv-mono"), False, False, 0)
            tl.pack_start(label({"XAMPP": "XAMPP", "propia": "propia"}.get(inst["kind"], "sobre XAMPP"),
                                "nv-etiqueta", valign=Gtk.Align.CENTER), False, False, 0)
            nt.pack_start(tl, False, False, 0)
            nt.pack_start(label(fmt_day(date[1]) if date and date[0] == inst["php"] else "/opt/lampp-%s" % folder,
                                "nv-chico", "nv-tenue"), False, False, 0)
            name.pack_start(nt, False, False, 0)
            name.set_tooltip_text("/opt/lampp-%s" % folder)
            # Soporte de su rama y su ultimo parche (de php.net: llegan aparte)
            f = self.nv_branch(inst["php"])
            sup = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
            patch = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
            newer = None
            if f is not None:
                st, a_end, s_end = branch_state(f)
                pill = state_pill(st, a_end, s_end)
                pill.set_halign(Gtk.Align.START)
                sup.pack_start(pill, False, False, 0)
                when = s_end if st == "security" else a_end if st == "stable" else ""
                if when:
                    sup.pack_start(label(("seguridad hasta %s" if st == "security" else "hasta %s") % fmt_month(when),
                                         "nv-chico", "nv-tenue"), False, False, 0)
                latest = f[2] if len(f) > 2 else ""
                if latest == inst["php"]:
                    patch.pack_start(label("Actualizado", "nv-verde", "nv-chico"), False, False, 0)
                elif latest and ver_tuple(latest) > ver_tuple(inst["php"]):
                    newer = latest
                    patch.pack_start(label("PHP %s disponible" % latest, "nv-chico", "nv-enlace"), False, False, 0)
                    ldate, _sec = branch_release(f)
                    if ldate and ldate != "-":
                        patch.pack_start(label(fmt_day(ldate), "nv-chico", "nv-tenue"), False, False, 0)
                else:
                    patch.pack_start(label("—", "nv-tenue"), False, False, 0)
            else:
                sup.pack_start(label("consultando php.net…" if self.branches is None else "—", "nv-chico", "nv-tenue"), False, False, 0)
                patch.pack_start(label("—", "nv-tenue"), False, False, 0)
            # PHP2Shell (gui-datos, R|): en rojo si no tiene el arreglo
            p2s, p2s_why = d.get("php2shell", {}).get(folder, ("", ""))
            if p2s == "vulnerable":
                vul = label("Vulnerable (PHP2Shell)", "nv-chico", "error")
                vul.set_halign(Gtk.Align.START)
                vul.set_tooltip_text("Vulnerable: actualízala en el menú ⋮")
                patch.pack_start(vul, False, False, 0)
                patch.reorder_child(vul, 0)
                # (vulnerable no está «Actualizado», aunque tenga el último parche de su rama)
                for w in patch.get_children():
                    if isinstance(w, Gtk.Label) and w.get_text() == "Actualizado":
                        patch.remove(w)
            php_cell = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
            php_cell.pack_start(label(inst["php"], "nv-mono"), False, False, 0)
            if p2s == "parche":
                ps = label("+ parche de seguridad (oct 2026)", "nv-chico", "nv-verde")
                ps.set_tooltip_text("Parche oficial contra PHP2Shell")
                php_cell.pack_start(ps, False, False, 0)
            right = Gtk.Box(spacing=2, halign=Gtk.Align.END)
            if act:
                b = css(Gtk.Button(label="Activa", sensitive=False), "nv-activa")
            else:
                # (como «Cargar» en Proyectos: solo en la version con el raton encima)
                b = css(Gtk.Button(label="Activar", sensitive=not self.busy), "nv-azul")
                b.connect("clicked", self.on_activate_version, folder)
                b.set_opacity(0)
            b.set_size_request(96, -1)
            right.pack_start(b, False, False, 0)
            right.pack_start(self.nv_version_menu(inst, newer), False, False, 0)
            if not act:
                right.hover_button = b
            dbs = len(d["dbs"].get(folder, []))
            row([name, php_cell, sup, patch,
                 label(str(dbs) if inst["owner"] == folder else "→ %s" % inst["owner"], "nv-mono", "nv-tenue"), right])
        if not self.installs():
            row([label("Ninguna versión instalada: instala la primera")] + [label("") for _ in range(5)])
        self.vers_page.pack_start(lb, False, False, 0)
        self.vers_page.show_all()

    def nv_version_menu(self, inst, newer=None):
        folder = inst["folder"]
        m = Gtk.MenuButton(relief=Gtk.ReliefStyle.NONE)
        m.add(icon("view-more-symbolic"))
        pop = Gtk.Popover(relative_to=m)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=4)
        items = [("Componentes…", lambda: self.nv_components_dialog(inst))]
        # Actualizar solo si hay un parche mas nuevo y la version se pone al dia en su carpeta (las
        # lampp-X.Y de antes); sin datos de php.net, se comprueba al pulsar
        updatable = inst["kind"] != "XAMPP" and inst["php"].rsplit(".", 1)[0] == folder
        if updatable and (newer or self.nv_branch(inst["php"]) is None
                          or self.data.get("php2shell", {}).get(folder, ("",))[0] == "vulnerable"):
            items.append(("Actualizar a PHP %s" % newer if newer else "Buscar parches nuevos",
                          lambda: self.nv_update(folder)))
        elif not updatable:
            # Las que no se ponen al dia en su carpeta (lampp-X.Y.Z y los XAMPP): la nueva, al lado
            target = self.nv_fix_target(inst)
            if target:
                items.append(("Actualizar a PHP %s%s" % (target, " + parche de seguridad" if target in PHP2SHELL_BACKPORTS else ""),
                              lambda: self.nv_upgrade_to(inst, target)))
        if pma_outdated(inst["php"], inst["pma"]):
            items.append(("Actualizar phpMyAdmin", lambda: self.on_update_pma(folder)))
        items.append(("Desinstalar…", lambda: self.on_remove(None, inst) if not inst["blocker"]
                      else message(self.win, "No se puede desinstalar", inst["blocker"], Gtk.MessageType.INFO)))
        for text, fn in items:
            b = Gtk.ModelButton(text=text)
            b.connect("clicked", lambda *_, fn=fn: fn())
            box.pack_start(b, False, False, 0)
        box.show_all()
        pop.add(box)
        m.set_popover(pop)
        return m

    def nv_fix_target(self, inst):
        """PHP al que se puede pasar una version que no se actualiza en su carpeta: el ultimo parche
        de su rama si es mas nuevo o, si es un XAMPP o le falta el arreglo de PHP2Shell, aunque sea
        el mismo (7.4.33 de XAMPP -> pila propia 7.4.33 con el parche de seguridad). None si no hay."""
        f = self.nv_branch(inst["php"])
        latest = f[2] if f is not None and len(f) > 2 else ""
        if not re.fullmatch(r"\d+\.\d+\.\d+", latest):
            return None
        st = self.data.get("php2shell", {}).get(inst["folder"], ("",))[0]
        if ver_tuple(latest) > ver_tuple(inst["php"]):
            return latest
        if latest == inst["php"] and (inst["kind"] == "XAMPP" or st == "vulnerable"):
            return latest
        return None

    def nv_upgrade_to(self, inst, target):
        folder = inst["folder"]
        same = target == folder
        dbs = len(self.data["dbs"].get(folder, [])) if inst["owner"] == folder else 0
        fix = " con el parche de seguridad de PHP2Shell" if target in PHP2SHELL_BACKPORTS else ""
        have = next((i["folder"] for i in self.installs() if i["php"] == target and i["kind"] != "XAMPP"
                     and i["folder"] != folder), None)
        if have and not same:
            text = ("PHP %s ya está en lampp-%s: se le copian %s de lampp-%s con sus vínculos a las carpetas "
                    "de los proyectos%s. lampp-%s no se toca: desinstálala cuando compruebes que todo va bien."
                    % (target, have, plural(dbs, "BBDD", "BBDD") if dbs else "las BBDD (ahora no tiene ninguna)", folder,
                       " y, como es la activa, se activa lampp-%s" % have if folder == self.data["active"] else "",
                       folder))
        elif same:
            text = ("Se vuelve a compilar PHP %s%s en su carpeta, con la última pila de su rama. Conserva "
                    "sus BBDD si su MariaDB sigue en la misma rama (si no, guarda antes una copia en "
                    "~/lvm-copias). Tarda varios minutos." % (target, fix))
        else:
            text = ("Se instala PHP %s%s en lampp-%s, al lado de lampp-%s, que no se toca. Después se le copian "
                    "%s con sus vínculos a las carpetas de los proyectos%s. Cuando compruebes que todo va bien "
                    "con lampp-%s, desinstala lampp-%s (menú ⋮, Desinstalar). Tarda varios minutos."
                    % (target, fix, target, folder, plural(dbs, "BBDD", "BBDD") if dbs else "sus BBDD (ahora no tiene ninguna)",
                       " y, como es la activa, se activa la nueva" if folder == self.data["active"] else "",
                       target, folder))
        if not confirm(self.win, "¿Actualizar lampp-%s a PHP %s?" % (folder, target), text, "Actualizar"):
            return
        self.run_task("lampp-%s → PHP %s" % (folder, target), ["actualizar-a", folder, target],
                      progress=True, reload_branches=True,
                      done_text="PHP %s instalada%s" % (target, "" if same else " con las BBDD de lampp-%s" % folder))

    def nv_update(self, folder):
        """Actualizar una version (como on_update), diciendo en un mensaje si ya esta al dia."""
        self.toast("Comprobando si hay una versión más nueva…")

        def checked(_rc, out):
            res = out.strip().splitlines()[-1].split("|") if out.strip() else ["error"]
            if res[0] == "si":
                message(self.win, "lampp-%s ya está actualizada" % folder,
                        "Tiene el último parche de su rama (%s)." % (res[1] if len(res) > 1 else ""),
                        Gtk.MessageType.INFO)
            elif res[0] == "no" and len(res) > 1:
                if confirm(self.win, "¿Actualizar lampp-%s?" % folder,
                           "PHP %s con los últimos parches de su rama. La actual sigue funcionando "
                           "mientras se compila (varios minutos)." % res[1], "Actualizar a PHP %s" % res[1]):
                    self.run_task("Actualizando lampp-%s" % folder, ["actualizar", folder],
                                  progress=True, reload_branches=True,
                                  done_text="lampp-%s actualizada a PHP %s" % (folder, res[1]))
            elif res[0] == "parche":
                message(self.win, "lampp-%s no se actualiza en su carpeta" % folder,
                        "Es un parche concreto: instala el nuevo aparte con «Instalar versión…».",
                        Gtk.MessageType.INFO)
            else:
                message(self.win, "No se ha podido comprobar la versión",
                        "No se ha podido consultar php.net. Comprueba la conexión a internet.",
                        Gtk.MessageType.WARNING)
            return False
        run_quick(["gui-al-dia", folder], checked)

    def nv_components_dialog(self, only=None):
        """Componentes de cada version en una tabla, con el logotipo de cada uno en color."""
        dlg = Gtk.Dialog(title="Componentes", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(900, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        dlg.get_content_area().add(box)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "nv-grupo")
        widths = [150, 84, 84, 92, 78, 78, 92]
        groups = [Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL) for _ in widths]

        def row(cells, head_row=False):
            r = Gtk.ListBoxRow(activatable=False)
            b = css(Gtk.Box(spacing=14), "nv-fila", *(["nv-cab"] if head_row else []))
            for n, w in enumerate(cells):
                w.set_size_request(widths[n], -1)
                groups[n].add_widget(w)
                b.pack_start(w, n == len(cells) - 1, True, 0)
            r.add(b)
            lb.add(r)

        def head(text, spec):
            h = Gtk.Box(spacing=6)
            h.pack_start(logo(spec, 16) if spec in LOGO_PATHS else icon(spec, 16), False, False, 0)
            h.pack_start(label(text.upper()), False, False, 0)
            return h
        row([label("VERSIÓN"), head("PHP", "php"), head("Apache", "apache"), head("MariaDB", "mariadb"),
             head("FTP", "folder-remote-symbolic"), head("Perl", "perl"), head("PMA", "phpmyadmin")], True)
        for inst in self.installs():
            if only is not None and inst["folder"] != only["folder"]:
                continue
            pma = label(inst["pma"], "nv-mono", "nv-chico")
            if pma_outdated(inst["php"], inst["pma"]):
                pma.get_style_context().add_class("error")
                pma.set_tooltip_text("phpMyAdmin antiguo: actualízalo en ⋮")
            row([label("lampp-%s" % inst["folder"], "nv-mono"), label(inst["php"], "nv-mono"),
                 label(inst["apache"], "nv-mono", "nv-chico"), label(inst["mariadb"], "nv-mono", "nv-chico"),
                 label(inst["ftp"], "nv-mono", "nv-chico"), label(inst["perl"], "nv-mono", "nv-chico"), pma])
        box.pack_start(lb, False, False, 0)
        dlg.add_button("Cerrar", Gtk.ResponseType.CLOSE)
        box.show_all()
        run_dialog(dlg)
        dlg.destroy()

    def nv_install_dialog(self):
        dlg = Gtk.Dialog(title="Instalar versión", transient_for=self.win, modal=False, use_header_bar=True)
        dlg.set_default_size(760, 680)
        sw = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True)
        if self.inst_box.get_parent():
            self.inst_box.get_parent().remove(self.inst_box)
        self.inst_box.set_margin_start(20)
        self.inst_box.set_margin_end(20)
        self.inst_box.set_margin_top(12)
        sw.add(self.inst_box)
        dlg.get_content_area().pack_start(sw, True, True, 0)
        dlg.connect("destroy", lambda *_: self.inst_box.get_parent() and
                    self.inst_box.get_parent().remove(self.inst_box))
        dlg.show_all()
