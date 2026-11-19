# El logotipo de letras de Docker, sin la ballena (en el menú lateral va al lado de su icono): el mismo SVG,
# con el recuadro (viewBox) solo sobre las letras
BRAND_SVG["docker-letras"] = base64.b64encode(zlib.compress(zlib.decompress(base64.b64decode(BRAND_SVG["docker"])).replace(
    b'viewBox="0 0 1250 268"', b'viewBox="385 30 865 210"'))).decode()
BRAND_RATIO["docker-letras"] = 865 / 210


def dns_flush_command(os_release="/etc/os-release", which=None):
    """La orden para vaciar la caché DNS de systemd-resolved en este sistema: en Ubuntu 20.04 y anteriores (y lo que
    va sobre ellas, como Linux Mint 20), `systemd-resolve --flush-cache`; desde la 22.04, `resolvectl flush-caches`.
    Si la que toca no está instalada, la otra; sin ninguna de las dos, None (no usa systemd-resolved)."""
    info = {}
    try:
        with open(os_release, encoding="utf-8") as f:
            for line in f:
                k, sep, v = line.strip().partition("=")
                if sep:
                    info[k] = v.strip().strip('"')
    except OSError:
        pass
    old = info.get("UBUNTU_CODENAME", info.get("VERSION_CODENAME", "")) in ("xenial", "bionic", "focal")
    if not old and info.get("ID") == "ubuntu":
        try:
            old = tuple(int(x) for x in info.get("VERSION_ID", "").split(".")[:2]) < (22, 4)
        except ValueError:
            pass
    which = which or shutil.which
    new_cmd = "sudo resolvectl flush-caches" if which("resolvectl") else None
    old_cmd = "sudo systemd-resolve --flush-cache" if which("systemd-resolve") else None
    return (old_cmd or new_cmd) if old else (new_cmd or old_cmd)


class NvTerminal:
    """La terminal de abajo de la ventana."""

    # ------------------------------------------------------------------ terminal (abajo de la ventana)
    def nv_term_panel(self):
        """La terminal de abajo: con el aspecto del visor de arriba, un poco hundida. La de verdad (VTE, la de
        la Terminal de GNOME) se crea la primera vez que se enseña; sigue viva al esconderla."""
        box = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6), "nv-terminal")
        box.set_size_request(-1, 120)
        head = Gtk.Box(spacing=8)
        head.pack_start(icon("utilities-terminal-symbolic", 14), False, False, 0)
        head.pack_start(label("Terminal", "nv-chico"), False, False, 0)
        self.term_where = label("", "nv-chico", "nv-tenue")
        self.term_where.set_ellipsize(2)  # Pango.EllipsizeMode.MIDDLE
        head.pack_start(self.term_where, True, True, 0)
        b = nv_button("folder-symbolic", "Proyecto cargado", "Ir a la carpeta del proyecto cargado (cd)",
                      lambda *_: self.nv_term_cd(), flat=True)
        head.pack_end(nv_button("window-close-symbolic", None, "Esconder la terminal (sigue abierta)",
                                lambda *_: self.term_btn.set_active(False), flat=True), False, False, 0)
        head.pack_end(nv_button("list-add-symbolic", None, "Otra pestaña de terminal (en la carpeta del proyecto cargado)",
                                lambda *_: self.nv_term_spawn(new_tab=True), flat=True), False, False, 0)
        head.pack_end(b, False, False, 0)
        head.pack_end(nv_button("network-transmit-receive-symbolic", "ping",
                                "Hacer ping al dominio del proyecto cargado: 127.0.0.1 es que está falseado",
                                lambda *_: self.nv_term_ping(), flat=True),
                      False, False, 0)
        head.pack_end(nv_button("edit-clear-all-symbolic", "Vaciar DNS",
                                "Vaciar la caché DNS",
                                lambda *_: self.nv_term_flush_dns(), flat=True),
                      False, False, 0)
        box.pack_start(head, False, False, 0)
        # (una pestaña por terminal: las pestañas solo se ven con más de una)
        self.term_tabs = css(Gtk.Notebook(scrollable=True, show_border=False), "nv-terminal-pestanas")
        self.term_tabs.set_show_tabs(False)
        self.term_tabs.connect("switch-page", self.nv_term_switched)
        box.pack_start(self.term_tabs, True, True, 0)
        box.show_all()
        box.set_no_show_all(True)
        box.hide()
        self.term_panel, self.term, self.term_sw, self.term_count = box, None, None, 0
        return box

    def nv_term_switched(self, _nb, page, _num):
        """Otra pestaña: los botones (cd, ping, Vaciar DNS, copiar y pegar) van a su terminal."""
        self.term, self.term_sw = page, page.get_child()
        self.term_where.set_label(getattr(page, "nv_cwd", ""))
        GLib.idle_add(lambda: self.term_sw is not None and self.term_sw.grab_focus() and False)

    def nv_term_tab_label(self, sw, n):
        tab = Gtk.Box(spacing=4)
        tab.pack_start(label("Terminal %d" % n, "nv-chico"), False, False, 0)
        close = nv_button("window-close-symbolic", None, "Cerrar esta pestaña (y lo que tenga en marcha)",
                          lambda *_: self.nv_term_exited(sw), flat=True)
        tab.pack_start(close, False, False, 0)
        tab.show_all()
        return tab

    def nv_term_show(self, on):
        if on:
            if self.term is None and not self.nv_term_spawn():
                self.term_btn.set_active(False)
                return
            first = not self.term_panel.get_visible()
            self.term_panel.show()
            if first:
                # (un tercio de la ventana, como poco 220 px)
                h = self.term_paned.get_allocated_height()
                self.term_paned.set_position(max(200, h - max(220, h // 3)))
            self.term.grab_focus()
        else:
            self.term_panel.hide()

    def nv_term_project(self):
        p = self.projects or {}
        # (gui-proyectos da la carpeta como la tiene el enlace de web.local: su nombre, dentro de los proyectos)
        cur = (p.get("current") or "").rstrip("/")
        cur = os.path.join(HTDOCS, cur) if cur else ""
        return cur if cur and os.path.isdir(cur) else HTDOCS

    def nv_term_spawn(self, new_tab=False):
        """La terminal: tu shell, con tu usuario, en la carpeta del proyecto cargado (o de los proyectos). Con
        new_tab, otra más, en su propia pestaña (las de antes siguen abiertas)."""
        try:
            gi.require_version("Vte", "2.91")
            from gi.repository import Pango, Vte
        except (ValueError, ImportError):
            message(self.win, "Falta la terminal de GNOME (VTE)",
                    "Para la terminal de la ventana hace falta su componente. En una terminal:\n\n"
                    "sudo apt install gir1.2-vte-2.91", Gtk.MessageType.INFO)
            return False
        if self.term is not None and not new_tab:
            return True
        sw = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        t = css(Vte.Terminal(), "nv-terminal-vte")
        t.set_scrollback_lines(10000)
        t.set_font(Pango.FontDescription("Monospace 10.5"))
        bg, fg = Gdk.RGBA(), Gdk.RGBA()
        bg.parse("#1D2228")
        fg.parse("#D7DEE6")
        # (colores que se leen bien sobre el fondo oscuro del visor: el azul de las carpetas, más claro)
        palette = []
        for c in ("#1D2228", "#E06C75", "#98C379", "#E5C07B", "#61AFEF", "#C678DD", "#56B6C2", "#D7DEE6",
                  "#5C6370", "#EF8A92", "#B5DC97", "#F0D49B", "#8CC8F7", "#DDA3EC", "#7FD3DD", "#FFFFFF"):
            rgba = Gdk.RGBA()
            rgba.parse(c)
            palette.append(rgba)
        t.set_colors(fg, bg, palette)
        t.set_hexpand(True)
        t.set_vexpand(True)
        # (al terminar el shell, se cierra su pestaña; con la última, se esconde y al volver a enseñarla, otra nueva)
        t.connect("child-exited", lambda *_: GLib.idle_add(self.nv_term_exited, sw))
        # (copiar y pegar como en la Terminal de GNOME: Ctrl+Mayús+C/V, Ctrl/Mayús+Insert y el botón derecho)
        t.connect("key-press-event", self.nv_term_key)
        t.connect("button-press-event", self.nv_term_click)
        cwd = self.nv_term_project()
        import pwd
        shell = os.environ.get("SHELL") or pwd.getpwuid(os.getuid()).pw_shell or "/bin/bash"
        if not os.path.isabs(shell) or not os.access(shell, os.X_OK):
            shell = "/bin/bash"
        t.spawn_async(Vte.PtyFlags.DEFAULT, cwd, [shell], None, GLib.SpawnFlags.DEFAULT, None, None, -1, None, None)
        sw.add(t)
        sw.nv_cwd = cwd
        sw.show_all()
        self.term_count += 1
        n = self.term_tabs.append_page(sw, self.nv_term_tab_label(sw, self.term_count))
        self.term_tabs.set_tab_reorderable(sw, True)
        self.term_tabs.set_show_tabs(self.term_tabs.get_n_pages() > 1)
        self.term, self.term_sw = sw, t
        self.term_tabs.set_current_page(n)
        self.term_where.set_label(cwd)
        if new_tab:
            t.grab_focus()
        return True

    def nv_term_copy(self):
        t = self.term_sw
        if not t.get_has_selection():
            return
        try:
            from gi.repository import Vte
            t.copy_clipboard_format(Vte.Format.TEXT)
        except (AttributeError, ImportError):
            t.copy_clipboard()

    def nv_term_paste(self):
        self.term_sw.paste_clipboard()
        self.term_sw.grab_focus()

    def nv_term_key(self, t, ev):
        mods = ev.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)
        both = Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK
        key = Gdk.keyval_to_lower(ev.keyval)
        if (mods == both and key == Gdk.KEY_c) or (mods == Gdk.ModifierType.CONTROL_MASK and key == Gdk.KEY_Insert):
            self.nv_term_copy()
            return True
        if (mods == both and key == Gdk.KEY_v) or (mods == Gdk.ModifierType.SHIFT_MASK and key == Gdk.KEY_Insert):
            self.nv_term_paste()
            return True
        return False

    def nv_term_click(self, t, ev):
        if ev.type != Gdk.EventType.BUTTON_PRESS or ev.button != 3:
            return False
        menu = Gtk.Menu()
        clip = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
        for text, keys, sensitive, cb in (
                ("Copiar", "<Control><Shift>c", t.get_has_selection(), self.nv_term_copy),
                ("Pegar", "<Control><Shift>v", clip.wait_is_text_available(), self.nv_term_paste),
                ("Seleccionar todo", None, True, t.select_all)):
            item = Gtk.MenuItem(label=text)
            if keys:
                item.get_child().set_accel(*Gtk.accelerator_parse(keys))
            item.set_sensitive(sensitive)
            item.connect("activate", lambda _i, f=cb: f())
            menu.append(item)
        menu.show_all()
        menu.attach_to_widget(t, None)
        menu.popup_at_pointer(ev)
        return True

    def nv_term_exited(self, sw):
        """Su shell ha terminado (o se cierra con su ×): fuera su pestaña. Con la última, la terminal se esconde."""
        n = self.term_tabs.page_num(sw)
        if n < 0:
            return False
        self.term_tabs.remove_page(n)
        sw.destroy()
        left = self.term_tabs.get_n_pages()
        self.term_tabs.set_show_tabs(left > 1)
        if left == 0:
            self.term, self.term_sw, self.term_count = None, None, 0
            self.term_btn.set_active(False)
        return False

    def nv_term_cd(self):
        """cd a la carpeta del proyecto cargado (escrito en la terminal, como si lo tecleara)."""
        if self.term is None:
            return
        cwd = self.nv_term_project()
        self.nv_term_type("cd %s" % shlex.quote(cwd))
        self.term_where.set_label(cwd)

    def nv_term_type(self, cmd):
        """Escribe una orden en la terminal y la manda, como si se tecleara."""
        if self.term is None:
            return
        self.term_sw.feed_child((cmd + "\n").encode())
        self.term_sw.grab_focus()

    def nv_term_ping_domains(self):
        """Los dominios del proyecto cargado que se pueden falsear (los de los vhosts de su carpeta, sin los .local)."""
        cur = ((self.projects or {}).get("current") or "").rstrip("/")
        return [h["name"] for h in self.project_hosts(os.path.basename(cur))] if cur else []

    def nv_term_ping(self):
        """«ping»: escribe en la terminal un ping (3 veces) a cada dominio del proyecto cargado. Con 127.0.0.1 está
        falseado (lleva a este equipo); si no, sale la dirección de la web real."""
        if self.term is None:
            return
        doms = self.nv_term_ping_domains()
        if not doms:
            cur = ((self.projects or {}).get("current") or "").rstrip("/")
            self.toast("El proyecto cargado no tiene dominio propio (solo web.local)" if cur
                       else "No hay ningún proyecto cargado")
            return
        self.nv_term_type("; ".join("ping -c 3 %s" % shlex.quote(d) for d in doms))

    def nv_term_flush_dns(self):
        """«Vaciar DNS»: escribe la orden de este sistema (dns_flush_command) en la terminal."""
        cmd = dns_flush_command()
        if cmd is None:
            self.toast("Este sistema no usa systemd-resolved: no hay caché DNS que vaciar con resolvectl")
            return
        self.nv_term_type(cmd)

    def nv_theme(self):
        """Claro u oscuro, solo en esta ventana (se recuerda). Con un tema que ya es oscuro de por si
        (Yaru-...-dark), preferir el oscuro no cambia nada: se cambia a su variante clara."""
        self.nv_apply_theme(not self.nv_is_dark())
        # (se redibuja lo que lleva logotipos con el color del fondo)
        if self.data:
            self.build_versions()
            self.build_databases()
            self.build_tools()
            self.nv_build_projects()
        if self.docker is not None:
            self.build_docker()
        try:
            os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
            with open(THEME_FILE, "w", encoding="utf-8") as f:
                f.write("oscuro\n" if self.nv_is_dark() else "claro\n")
        except OSError:
            pass

    def nv_is_dark(self):
        s = Gtk.Settings.get_default()
        return s.get_property("gtk-theme-name").lower().endswith("-dark") \
            or s.get_property("gtk-application-prefer-dark-theme")

    def nv_apply_theme(self, dark):
        s = Gtk.Settings.get_default()
        name = s.get_property("gtk-theme-name")
        base = name[:-5] if name.lower().endswith("-dark") else name
        if dark:
            # (la variante -dark si el tema la tiene; si no, el oscuro del propio tema)
            if theme_exists(base + "-dark"):
                s.set_property("gtk-theme-name", base + "-dark")
                s.set_property("gtk-application-prefer-dark-theme", False)
            else:
                s.set_property("gtk-theme-name", base)
                s.set_property("gtk-application-prefer-dark-theme", True)
        else:
            s.set_property("gtk-theme-name", base if theme_exists(base) else "Adwaita")
            s.set_property("gtk-application-prefer-dark-theme", False)
        # (lo que cambia de color con el tema claro: .nv-claro en la ventana)
        if getattr(self, "win", None) is not None:
            ctx = self.win.get_style_context()
            (ctx.remove_class if dark else ctx.add_class)("nv-claro")
        # (los logotipos que dependen del fondo, con su color de nuevo)
        _logo_cache.clear()
        if getattr(self, "theme_item", None):
            img, lbl = self.theme_item
            img.set_from_icon_name("weather-clear-symbolic" if dark else "weather-clear-night-symbolic",
                                   Gtk.IconSize.BUTTON)
            lbl.set_label("Tema claro" if dark else "Tema oscuro")

    def nv_power(self):
        d = self.data
        if not d or not d["active"]:
            self.show_tab("versiones")
            return
        self.on_control(None, "parar" if d["running"] else "arrancar",
                        "Parar y desactivar" if d["running"] else "Arrancar")

    def nv_task_badge(self, task):
        """El aviso de la tarea en segundo plano (None: se quita)."""
        self.bg_task = task
        if task is None:
            self.task_badge.hide()
            return
        self.nv_task_badge_tick(task)
        self.task_badge.show()
        GLib.timeout_add(700, self.nv_task_badge_tick, task)

    def nv_task_badge_tick(self, task):
        if self.bg_task is not task or task.finished:
            return False
        m = re.search(r"\d+ ?%", task.pct.get_label() or "")
        # (lo que hace, con la primera palabra del título: «Actualizando…», «Instalando…»)
        verb = (task.dlg.get_title() or "En marcha").split()[0].rstrip(".,:")
        self.task_badge_lbl.set_label("%s…%s" % (verb, "  " + m.group(0) if m else ""))
        self.task_badge.set_tooltip_text("%s\n%s\nPulsa para ver la ventana" % (
            task.dlg.get_title(), task.what.get_label() or "En marcha"))
        return True

    def nv_sidebar(self):
        box = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4), "nv-lateral")
        box.set_size_request(230, -1)
        self.side_box, self.tabs, self.tab_lists = box, {}, []
        self.foot = label("", "nv-chico", "nv-tenue", xalign=0.5, wrap=True, max_width_chars=26, margin=12)
        box.pack_end(self.foot, False, False, 0)
        self.nv_sidebar_fill()
        return box

    def nv_sidebar_fill(self):
        """Los apartados del menú lateral, como diga Apariencia (también al cambiarla: solo se rehace esto)."""
        box, look = self.side_box, look_conf()
        current = next((lb.get_selected_row().tab_name for lb in self.tab_lists if lb.get_selected_row()), "proyectos")
        for w in box.get_children():
            if w is not self.foot:
                w.destroy()
        self.tabs, self.tab_lists = {}, []
        for group_name, items in SIDEBAR:
            items = [it for it in items if (it[0] in SIDEBAR_FIXED or it[0] not in look["ocultos"])
                     and (it[0] != "nginx" or nginx_used())]
            if not items:
                continue
            box.pack_start(label(group_name, "nv-seccion", margin_start=22, margin_top=16, margin_bottom=2), False, False, 0)
            lb = css(Gtk.ListBox(), "nv-nav")
            for name, text, ic in items:
                row = Gtk.ListBoxRow()
                inner = Gtk.Box(spacing=12)
                if look["marcas"] and name in ("docker", "node"):
                    # (su icono, como los demás, y al lado su logotipo de letras en lugar del nombre)
                    inner.pack_start(MonoLogo(ic[5:], 20, colored=look["color"]), False, False, 0)
                    inner.pack_start(BrandLogo("docker-letras" if name == "docker" else "node", 15 if name == "docker" else 20,
                                               mono=not look["color"]), False, False, 0)
                else:
                    if look["marcas"] and look["color"] and name == "versiones":
                        w = BrandLogo("php", 20)
                    elif ic.startswith("logo:"):
                        # (en color, cada uno el suyo; si no, de un color, como los iconos del tema)
                        w = MonoLogo(ic[5:], 20, colored=look["color"] and ic != "logo:github")
                    else:
                        w = symbol(ic, 20)
                        if look["color"]:
                            css(w, "nv-tinte-" + name)
                    inner.pack_start(w, False, False, 0)
                    inner.pack_start(label(text), False, False, 0)
                row.add(inner)
                row.tab_name = name
                lb.add(row)
                self.tabs[name] = (lb, row)
            lb.connect("row-selected", self.nv_on_tab)
            self.tab_lists.append(lb)
            box.pack_start(lb, False, False, 0)
        box.show_all()
        lb, row = self.tabs.get(current) or self.tabs["proyectos"]
        lb.select_row(row)

    def nv_look_set(self, key, value):
        conf = look_conf()
        if key.startswith("@"):
            (conf["ocultos"].discard if value else conf["ocultos"].add)(key[1:])
        else:
            conf[key] = value
        look_save(conf)
        if key in ("zoom", "cristal"):
            self.nv_apply_look()
            return
        self.nv_sidebar_fill()

    def nv_apply_look(self):
        """Apariencia, tamaño y cristal, al momento. El tamaño: las letras con la resolución (gtk-xft-dpi, la de
        este equipo por el tanto por ciento) y las medidas de la hoja de estilos a escala. El cristal: la clase
        .nv-cristal en la ventana (el fondo de color y los paneles translúcidos los pinta la hoja de estilos)."""
        look = look_conf()
        s = Gtk.Settings.get_default()
        if getattr(self, "nv_base_dpi", None) is None:
            dpi = s.get_property("gtk-xft-dpi")
            self.nv_base_dpi = dpi if dpi and dpi > 0 else 96 * 1024
        want = int(self.nv_base_dpi * look["zoom"] / 100)
        if s.get_property("gtk-xft-dpi") != want:
            s.set_property("gtk-xft-dpi", want)
        if getattr(self, "nv_zoom_loaded", 100) != look["zoom"]:
            for text, prov in getattr(self, "nv_css", []):
                prov.load_from_data(css_zoom(text, look["zoom"]).encode())
        self.nv_zoom_loaded = look["zoom"]
        if look["cristal"] and getattr(self, "nv_glass_prov", None) is None:
            self.nv_glass_prov = Gtk.CssProvider()
            self.nv_glass_prov.load_from_data(glass_css().encode())
            Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), self.nv_glass_prov,
                                                     Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        ctx = self.win.get_style_context()
        (ctx.add_class if look["cristal"] else ctx.remove_class)("nv-cristal")

    def nv_look_tools(self):
        """Configuración, Apariencia: en tres bloques, cada uno con su título, porque hacen cosas distintas:
        cómo se ve el menú lateral, qué apartados salen en él y los botones del visor de los proyectos."""
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=26)
        head = Gtk.Box(spacing=6)
        head.pack_start(label("Apariencia", "grupo-titulo"), False, False, 0)
        head.pack_start(info_icon("Cómo se ve la ventana. Se guarda al momento y vale también para la versión de Mac."),
                        False, False, 0)
        page.pack_start(head, False, False, 0)
        look = look_conf()

        def block(title, sub):
            b = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            b.pack_start(label(title, "nv-apartado-titulo", xalign=0), False, False, 0)
            b.pack_start(label(sub, "dim-label", "subtitulo", xalign=0, wrap=True), False, False, 0)
            lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE, margin_top=8), "caja")
            lb.connect("row-activated", on_row_activated)
            b.pack_start(lb, False, False, 0)
            page.pack_start(b, False, False, 0)
            return lb

        def switch(lb, title, sub, key, on):
            row = ActionRow(title, sub)
            s = Gtk.Switch(active=on, valign=Gtk.Align.CENTER)
            s.connect("notify::active", lambda w, _p: self.nv_look_set(key, w.get_active()))
            row.add_suffix(s)
            lb.add(row)
        lb = block("Iconos del menú lateral", "Cómo se dibujan los iconos de la columna de la izquierda")
        switch(lb, "Iconos en color", "Cada apartado con su color; apagado, de un color, como el texto",
               "color", look["color"])
        switch(lb, "Logotipos de Docker, Node y PHP", "Con su logotipo y su tipografía en lugar del nombre",
               "marcas", look["marcas"])
        lb = block("Tamaño y aspecto", "Más pequeña para que quepa más, y el aspecto de cristal")
        row = ActionRow("Tamaño de la ventana", "Letras, márgenes y botones. 100 %: el de siempre")
        zoom = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
        for z in LOOK_ZOOMS:
            zoom.append(str(z), "%d %%" % z)
        zoom.set_active_id(str(look["zoom"]))
        zoom.connect("changed", lambda w: w.get_active_id() and self.nv_look_set("zoom", int(w.get_active_id())))
        row.add_suffix(zoom)
        lb.add(row)
        switch(lb, "Cristal", "Paneles translúcidos sobre un fondo de color. Gasta algo más al redibujar la ventana, "
               "nada mientras no cambia", "cristal", look["cristal"])
        lb = block("Apartados del menú lateral",
                   "Cuáles se ven en la columna de la izquierda (Proyectos y Configuración salen siempre)")
        # (en dos columnas: la primera mitad a la izquierda y el resto a la derecha)
        b = lb.get_parent()
        b.remove(lb)
        cols = Gtk.Box(spacing=12, homogeneous=True, margin_top=8)
        b.pack_start(cols, False, False, 0)
        names = [(name, text) for _g, items in SIDEBAR for name, text, _ic in items if name not in SIDEBAR_FIXED
                 and (name != "nginx" or nginx_used())]
        half = (len(names) + 1) // 2
        for chunk in (names[:half], names[half:]):
            col = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE, valign=Gtk.Align.START), "caja")
            col.connect("row-activated", on_row_activated)
            cols.pack_start(col, True, True, 0)
            for name, text in chunk:
                switch(col, text, None, "@" + name, name not in look["ocultos"])
        lb = block("Visor de los proyectos", "Los botones de cada proyecto: cuáles se ven, en qué orden y cómo")
        conf = buttons_conf()
        shown = [n for k, n, _i in sorted(VISOR_BUTTONS, key=lambda b: conf["order"].index(b[0])) if k not in conf["hidden"]]
        row = ActionRow("Botones", "%s · %s" % (", ".join(shown) or "ninguno",
                                                dict(BUTTON_STYLES)[conf["style"]].split(":")[0].lower()))
        b = Gtk.Button(label="Personalizar…", valign=Gtk.Align.CENTER)
        b.connect("clicked", lambda *_: self.nv_buttons_dialog())
        row.add_suffix(b)
        lb.add(row)
        self.tools_box.pack_start(page, False, False, 0)

    def nv_on_tab(self, lb, row):
        if row is None:
            return
        # (los logotipos dibujados cambian de color en la fila elegida: GTK no se lo dice, se repintan)
        self.side_box.queue_draw()
        for other in self.tab_lists:
            if other is not lb:
                other.unselect_all()
        self.stack.set_visible_child_name(row.tab_name)
        # Al entrar en una pestaña, sus apartados desplegables aparecen plegados
        if any(k.startswith("@db") for k in self.expanded) or self.dk_open:
            self.expanded.difference_update({k for k in self.expanded if k.startswith("@db")})
            self.dk_open = set()
            if self.data:
                self.nv_db_table()
            if self.docker is not None:
                self.nv_dk_table()
        if row.tab_name == "docker":
            run_quick(["gui-docker"], self.on_docker_data)
            run_quick(["gui-docker-estadisticas"], self.on_docker_stats)
        elif row.tab_name == "bbdd":
            run_quick(["gui-bbdd-tamanos"], self.on_db_sizes)
        elif row.tab_name == "repos":
            self.nv_repos_open()
        elif row.tab_name == "versiones":
            self.nv_broken_load()
        elif row.tab_name == "node":
            self.nv_node_load()
        elif row.tab_name == "nginx":
            self.nv_nginx_load()

    def on_tick(self):
        res = super().on_tick()
        # (escondida en el icono: solo lo que enseña su menú, cada minuto)
        if self.tray is not None and not self.win.get_visible() and not self.busy:
            self.tray_ticks = (self.tray_ticks + 1) % 3
            if self.tray_ticks == 0:
                run_quick(["gui-datos"], self.on_data)
        if not self.busy and self.win.is_active() and self.stack.get_visible_child_name() == "docker":
            run_quick(["gui-docker-estadisticas"], self.on_docker_stats)
        if self.win.is_active():
            self.nv_mail_poll()
        return res
