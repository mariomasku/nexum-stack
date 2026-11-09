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
        """Ayuda: los comandos de lvm-instalador (lo mismo que lvm-instalador --ayuda)."""
        def show(_rc, out):
            dlg = Gtk.Dialog(title="Comandos de lvm-instalador", transient_for=self.win,
                             modal=True, use_header_bar=True)
            dlg.set_default_size(860, 700)
            hb = dlg.get_header_bar()
            hb.set_subtitle("En la terminal: lvm-instalador --ayuda")
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
                    "orden" if line.startswith("  lvm-instalador") else None
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
    def capture(self, widget, name):
        import cairo
        widget.check_resize()
        w, h = widget.get_allocated_width(), widget.get_allocated_height()
        surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
        cr = cairo.Context(surf)
        Gtk.render_background(widget.get_style_context(), cr, 0, 0, w, h)
        widget.draw(cr)
        surf.write_to_png(os.path.join(os.environ["LVM_CAPTURA"], name + ".png"))

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
