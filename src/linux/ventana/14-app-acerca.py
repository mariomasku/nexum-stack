class AppAcerca:
    """Acerca de, comandos, novedades y capturas para revisar la ventana."""

    # -------------------------------------------------------------- acerca
    def on_about(self, *_):
        d = self.data or {}
        about = Gtk.AboutDialog(
            transient_for=self.win, modal=True, program_name=d.get("name", ""),
            version=d.get("version", ""), logo_icon_name=self.icon,
            copyright="%s\n© %d" % (d.get("signature", ""), time.localtime().tm_year),
            comments="Herramientas de desarrollo web en local.")
        about.set_default_size(560, -1)
        about.run()
        about.destroy()

    def on_commands(self, *_):
        """Ayuda: los comandos de nexum (lo mismo que nexum --ayuda)."""
        def show(_rc, out):
            dlg = Gtk.Dialog(title="Comandos de nexum", transient_for=self.win,
                             modal=True, use_header_bar=True)
            dlg.set_default_size(860, 700)
            hb = dlg.get_header_bar()
            hb.set_subtitle("En la terminal: nexum --ayuda")
            copy = Gtk.Button(label="Copiar todo")
            copy.connect("clicked", lambda *_: (
                Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(out, -1),
                self.toast("Copiado al portapapeles")))
            hb.pack_start(copy)
            tv = css(Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                                  left_margin=16, right_margin=16, top_margin=12,
                                  bottom_margin=12), "log")
            # Cada sección («=== TÍTULO ===») en verde y grande, y cada orden en negrita: se
            # distinguen de su explicación (con sangría, debajo)
            buf = tv.get_buffer()
            buf.set_text(out)
            buf.create_tag("seccion", weight=700, scale=1.15, foreground=GREEN, pixels_above_lines=10,
                           pixels_below_lines=4)
            buf.create_tag("orden", weight=700, pixels_above_lines=4)
            for n, line in enumerate(out.split("\n")):
                tag = "seccion" if line.startswith("=== ") else \
                    "orden" if line.startswith("  nexum") else None
                if tag:
                    start = buf.get_iter_at_line(n)
                    end = start.copy()
                    end.forward_to_line_end()
                    buf.apply_tag_by_name(tag, start, end)
            sw = Gtk.ScrolledWindow(vexpand=True)
            sw.add(tv)
            dlg.get_content_area().add(sw)
            dlg.show_all()
            run_dialog(dlg)
            dlg.destroy()
            return False
        run_quick(["--ayuda"], show)

    # El capítulo del manual de cada pestaña y de cada apartado de Configuración (los id de ayuda/index.html)
    HELP_TABS = {"proyectos": "proyectos", "repos": "repositorios", "versiones": "versiones", "bbdd": "bbdd",
                 "docker": "docker", "node": "node", "dominios": "dominios", "config": "configuracion"}
    HELP_SECTIONS = {"General": "general", "Configuración": "vhosts", "Seguridad entre webs": "seguridad-webs",
                     "Correo de pruebas (Mailpit)": "correo", "Docker": "docker-config",
                     "Túnel de Cloudflare": "tunel-config", "GitHub (Repositorios)": "github-config",
                     "Apariencia": "apariencia", "Limpieza": "limpieza", "Carpetas": "carpetas",
                     "XAMPP sin registrar": "xampp-registrar", "Información": "informacion"}

    def on_help(self, *_):
        """Ayuda (menú ☰): el manual, que va dentro del script, en el navegador; en el capítulo de la pestaña
        abierta (en Configuración, el de su apartado)."""
        stack = getattr(self, "stack", None)
        tab = stack.get_visible_child_name() if stack is not None else ""
        chapter = self.HELP_TABS.get(tab, "ventana")
        if tab == "config":
            chapter = self.HELP_SECTIONS.get(getattr(self, "tools_section", None) or "", chapter)

        def opened(rc, out):
            path = (out.strip().splitlines() or [""])[-1]
            if rc == 0 and path.startswith("/") and os.path.isfile(path):
                self.open_uri("file://" + path)
            else:
                message(self.win, "No se ha podido abrir el manual", out.strip() or "Error al sacar el manual.",
                        Gtk.MessageType.ERROR)
            return False
        run_quick(["manual", "--ruta", chapter], opened)

    def on_changes(self, *_):
        def show(_rc, out):
            dlg = Gtk.Dialog(title="Novedades", transient_for=self.win, modal=True,
                             use_header_bar=True)
            dlg.set_default_size(780, 680)
            tv = Gtk.TextView(editable=False, cursor_visible=False, wrap_mode=Gtk.WrapMode.WORD_CHAR,
                              left_margin=24, right_margin=24, top_margin=8, bottom_margin=24)
            markdown_to_buffer(tv.get_buffer(), out)
            sw = Gtk.ScrolledWindow(vexpand=True)
            sw.add(tv)
            dlg.get_content_area().add(sw)
            dlg.show_all()
            run_dialog(dlg)
            dlg.destroy()
            return False
        run_quick(["novedades"], show)

    # ----------------------------------------- capturas (solo para revisar la ventana)
    def capture(self, widget, name, last=True):
        import cairo
        # (como en primer plano aunque haya otra ventana delante: en segundo plano, GTK pinta la selección casi
        # invisible y una sombra más suave, y el recorte por el borde falla)
        def front(w):
            w.unset_state_flags(Gtk.StateFlags.BACKDROP)
            if isinstance(w, Gtk.Container):
                for c in w.get_children():
                    front(c)
        front(widget)
        widget.check_resize()
        w, h = widget.get_allocated_width(), widget.get_allocated_height()
        surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
        cr = cairo.Context(surf)
        Gtk.render_background(widget.get_style_context(), cr, 0, 0, w, h)
        widget.draw(cr)
        surf.flush()
        # (de un solo color: aún no se ha dibujado; mejor otro intento, salvo que sea el último)
        data = bytes(surf.get_data())
        if not last and len(set(data[i:i + 4] for i in range(0, len(data), 4 * 997))) <= 2:
            return False
        # (y la misma que la anterior: si aún cambia, la página se estaba rehaciendo)
        prev, self._capture_prev = getattr(self, "_capture_prev", None), (name, data)
        if not last and prev != (name, data):
            return False
        surf.write_to_png(os.path.join(os.environ["LVM_CAPTURA"], name + ".png"))
        return True

    def capture_all(self):
        steps = [(lambda: None, "1-versiones"), (lambda: self.show_tab("bbdd"), "3-bbdd"),
                 (lambda: self.show_tab("servicios"), None), (lambda: None, "6-servicios"),
                 (lambda: self.show_tab("hosts"), None), (lambda: None, "5-hosts"),
                 (lambda: self.show_tab("herramientas"), None), (lambda: None, "4-herramientas"),
                 (lambda: self.quit(), None)]

        def step(i=[0]):  # noqa: B006 (el contador de los pasos, a propósito)
            fn, shot = steps[i[0]]
            fn()
            if shot:
                GLib.timeout_add(1500, lambda: (self.capture(self.win, shot), False)[1])
            i[0] += 1
            return i[0] < len(steps)
        GLib.timeout_add(2500, step)
        return False
