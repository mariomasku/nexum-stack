class NvActualizarProyecto:
    """Actualizar un proyecto, sus menús, crearlo, importarlo y borrarlo."""

    # --- Actualizar proyecto: la BBDD y el código de producción, arrastrados o elegidos ---

    def nv_drop_zone(self, title, formats, symbol_name, choosers, on_path):
        """Zona donde arrastrar un fichero o una carpeta, con sus botones de elegir. choosers: (texto,
        es carpeta). on_path(ruta) devuelve el motivo si no vale. Devuelve (widget, poner la ruta)."""
        ev = css(Gtk.EventBox(), "nv-zona")
        # (alta: es donde se suelta, tiene que verse bien)
        ev.set_size_request(-1, 112)
        box = Gtk.Box(spacing=16, margin_start=20, margin_end=18, margin_top=16, margin_bottom=16)
        ev.add(box)
        box.pack_start(css(icon(symbol_name, 36), "nv-zona-icono"), False, False, 0)
        # (en una rejilla: airy_dialog centra los textos de las cajas verticales; aquí, junto al icono, a la izquierda)
        texts = Gtk.Grid(orientation=Gtk.Orientation.VERTICAL, row_spacing=2, valign=Gtk.Align.CENTER)
        texts.add(label(title, "grupo-titulo", halign=Gtk.Align.START))
        name = label("Arrástralo aquí: %s" % formats, "dim-label", ellipsize=2, halign=Gtk.Align.START)
        texts.add(name)
        box.pack_start(texts, True, True, 0)

        def put(path):
            why = on_path(path)
            ctx = name.get_style_context()
            ctx.remove_class("error")
            if why:
                ctx.add_class("error")
                name.set_label(why)
            else:
                name.set_label(path or "Arrástralo aquí: %s" % formats)
            name.set_tooltip_text(path or None)
            clear_btn.set_visible(bool(path) and not why)
            # (el recuadro azul, solo con algo incorporado o al arrastrar encima)
            zone_ctx = ev.get_style_context()
            if path and not why:
                zone_ctx.add_class("nv-zona-lista")
            else:
                zone_ctx.remove_class("nv-zona-lista")

        def choose(folder):
            dlg = Gtk.FileChooserDialog(title=title, transient_for=ev.get_toplevel(), modal=True,
                                        action=Gtk.FileChooserAction.SELECT_FOLDER if folder else Gtk.FileChooserAction.OPEN)
            dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
            dlg.add_button("Elegir", Gtk.ResponseType.ACCEPT)
            dlg.set_current_folder(GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD) or os.path.expanduser("~"))
            resp = run_dialog(dlg)
            path = dlg.get_filename()
            dlg.destroy()
            if resp == Gtk.ResponseType.ACCEPT and path:
                put(path)

        def dropped(_w, _ctx, _x, _y, data, _info, _time):
            uris = data.get_uris()
            if uris:
                try:
                    put(GLib.filename_from_uri(uris[0])[0])
                except GLib.Error:
                    put("")
        ev.drag_dest_set(Gtk.DestDefaults.ALL, [], Gdk.DragAction.COPY)
        ev.drag_dest_add_uri_targets()
        ev.connect("drag-data-received", dropped)
        clear_btn = nv_button("window-close-symbolic", None, "Quitar", lambda *_: put(""), flat=True)
        # (oculto hasta que haya algo elegido, sin dejar oculto su icono)
        clear_btn.get_child().show_all()
        clear_btn.set_no_show_all(True)
        box.pack_start(clear_btn, False, False, 0)
        for text, folder in choosers:
            box.pack_start(nv_button(None, text, None, lambda *_, f=folder: choose(f)), False, False, 0)
        return ev, put

    def nv_update_project(self, x):
        """Actualizar el proyecto cargado con lo de producción: su BBDD y su código."""
        folder = x["name"]
        dlg = Gtk.Dialog(title="Actualizar proyecto", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(680, -1)
        dlg.get_header_bar().set_subtitle(folder)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin=22)
        state = {"sql": "", "code": ""}

        def set_sql(path):
            why = ""
            if path and not (os.path.isfile(path) and path.lower().endswith((".sql", ".gz", ".zip"))):
                why, path = "Tiene que ser .sql, .sql.gz o .zip", ""
            state["sql"] = path
            update()
            return why

        def set_code(path):
            why = ""
            ok = os.path.isdir(path) or (os.path.isfile(path) and path.lower().endswith(
                (".zip", ".tar", ".tgz", ".tar.gz", ".tar.bz2", ".tar.xz")))
            if path and not ok:
                why, path = "Tiene que ser un .zip, un .tar.gz o una carpeta", ""
            state["code"] = path
            update()
            return why

        zone, _put = self.nv_drop_zone("Base de datos de producción", ".sql, .sql.gz o .zip", "drive-multidisk-symbolic",
                                       [("Elegir fichero…", False)], set_sql)
        box.pack_start(zone, False, False, 0)
        line = Gtk.Box(spacing=8)
        db_text = label("", "dim-label")
        line.pack_start(db_text, False, False, 0)
        # (su nombre, como texto; solo si el proyecto no tiene ninguna hay que escribirlo)
        known_db = self.loaded_project_db() or ""
        db_entry = Gtk.Entry(text=known_db, width_chars=28, max_length=64)
        line.pack_start(label(known_db, "nv-bbdd", selectable=True) if known_db else db_entry, False, False, 0)
        db_copy = label("(al confirmar, puedes guardar antes una copia de la actual)", "dim-label")
        line.pack_start(db_copy, False, False, 0)
        box.pack_start(line, False, False, 0)
        zone, _put = self.nv_drop_zone("Código de producción", ".zip, .tar.gz o carpeta", "folder-symbolic",
                                       [("Elegir fichero…", False), ("Elegir carpeta…", True)], set_code)
        box.pack_start(zone, False, False, 0)
        # Qué hacer con la carpeta: siempre a la vista, para saber lo que va a pasar
        merge = Gtk.RadioButton.new_with_label(None, "Fusionar: copia lo que trae y deja lo demás de la carpeta")
        over = Gtk.RadioButton.new_with_label_from_widget(merge, "Sobrescribir: además borra lo que no traiga")
        modes = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        modes.pack_start(merge, False, False, 0)
        modes.pack_start(over, False, False, 0)
        modes.pack_start(label("Se escribe sobre %s/%s. Su .git no se toca; lo sustituido o borrado solo se puede "
                               "recuperar si al confirmar guardas antes una copia en ~/nexum-backups." % (HTDOCS, folder),
                               "aviso-rojo", wrap=True), False, False, 0)
        box.pack_start(modes, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        go = css(dlg.add_button("Actualizar…", Gtk.ResponseType.ACCEPT), "nv-azul")

        def update(*_):
            db_ok = bool(re.fullmatch(r"[A-Za-z0-9_-]{1,64}", db_entry.get_text().strip()))
            go.set_sensitive(bool(state["sql"] or state["code"]) and (not state["sql"] or db_ok))
            modes.set_sensitive(bool(state["code"]))
            # (sin fichero de BBDD no se toca: se sigue usando la misma)
            db_text.set_label("Se carga en la BBDD" if state["sql"] else "Se sigue usando la BBDD")
            db_copy.set_visible(bool(state["sql"]))
            line.set_visible(bool(known_db or state["sql"]))
            if not known_db:
                db_entry.set_sensitive(bool(state["sql"]))
        db_entry.connect("changed", update)
        dlg.show_all()
        update()
        resp = run_dialog(dlg)
        db = db_entry.get_text().strip()
        mode = "sobrescribir" if over.get_active() else "fusionar"
        dlg.destroy()
        if resp == Gtk.ResponseType.ACCEPT:
            self.nv_update_project_ask(folder, state["sql"], db, state["code"], mode)

    def nv_update_project_ask(self, folder, sql, db, code, mode):
        """Antes de copiar: si es un repositorio, ¿git pull antes?, avisando de lo que no se ha subido."""
        def start(pull, backup):
            args = ["actualizar-proyecto", folder] + (["--copia"] if backup else [])
            if code:
                args += ["--codigo", code, "--modo", mode] + (["--pull"] if pull else [])
            if sql:
                args += ["--bd", sql]
            # (también solo con el código: al volver a cargarlo, su configuración vuelve a esta BBDD)
            if db:
                args += ["--base", db]

            def run(_pwd=None):
                self.run_task("Actualizando %s" % folder, args, progress=True, env=self.db_env(),
                              done_text="%s actualizado" % folder,
                              cancel_text=("¿Cancelar la actualización?",
                                           "El proyecto se queda a medias, con lo hecho hasta ahora."
                                           + (" Lo sustituido sigue en ~/nexum-backups." if backup else ""),
                                           "Cancelar la actualización"))
            if sql:
                self.check_db_access(run)
            else:
                run()

        what = []
        if code:
            what.append(("Se fusiona «%s» con %s/%s." if mode == "fusionar" else
                         "Se sobrescribe la carpeta con «%s» en %s/%s: se borra lo que no traiga.")
                        % (os.path.basename(code), HTDOCS, folder))
        if sql:
            what.append("La BBDD %s se vacía y se carga «%s»." % (db, os.path.basename(sql)))

        def got(_rc, out):
            f = next((x for x in parse_lines(out) if x[0] == "G" and len(x) >= 6), None)
            is_git = bool(code) and f is not None and f[1] == "1"
            extra = copy_check()
            if not is_git:
                if confirm(self.win, "¿Actualizar %s?" % folder, "", "Actualizar", steps=what, extra=extra):
                    start(False, extra.wanted)
                return False
            dirty, ahead = int(f[3] or 0), int(f[4] or 0)
            state = ["Rama %s" % (f[2] or "sin rama (HEAD suelto)")]
            if dirty:
                state.append("%s sin commit" % plural(dirty, "cambio", "cambios"))
            if ahead:
                state.append("%s sin subir" % plural(ahead, "commit", "commits"))
            text = ["  ·  ".join(state)]
            if dirty or ahead:
                text.append("Revisa antes lo que estás trabajando: lo sustituido no queda en git (solo en la copia, "
                            "si la guardas).")
            has_pull = f[5] == "1" and bool(f[2])
            text.append("Con el pull, la carpeta se equipara antes al repositorio. Si choca con tus cambios, se para "
                        "sin tocar nada." if has_pull else "No se puede hacer pull: no tiene origin o no está en una rama.")
            dlg = Gtk.MessageDialog(transient_for=self.win, modal=True, message_type=Gtk.MessageType.QUESTION,
                                    buttons=Gtk.ButtonsType.NONE, text="¿Hacer git pull antes de copiar?")
            dlg.get_message_area().pack_start(steps_box(what, "\n\n".join(text)), False, False, 0)
            dlg.get_message_area().pack_start(extra, False, False, 0)
            dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
            dlg.add_button("Copiar sin pull", Gtk.ResponseType.NO)
            if has_pull:
                css(dlg.add_button("Hacer pull y copiar", Gtk.ResponseType.YES), "nv-azul")
            dlg.show_all()
            resp = run_dialog(dlg)
            dlg.destroy()
            if resp in (Gtk.ResponseType.YES, Gtk.ResponseType.NO):
                start(resp == Gtk.ResponseType.YES, extra.wanted)
            return False
        run_quick(["gui-proyecto-git", folder], got)

    def nv_menu_button(self, text, icon_name, items, tip=None):
        m = css(Gtk.MenuButton(tooltip_text=tip), "nv-proyecto-btn")
        b = Gtk.Box(spacing=6)
        b.pack_start(icon_name if isinstance(icon_name, Gtk.Widget) else icon(icon_name), False, False, 0)
        if text:
            b.pack_start(Gtk.Label(label=text), False, False, 0)
        m.add(b)
        pop = Gtk.Popover(relative_to=m)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=4)
        for t, fn in items:
            mb = Gtk.ModelButton(text=t)
            mb.connect("clicked", lambda *_, fn=fn: fn())
            box.pack_start(mb, False, False, 0)
        box.show_all()
        pop.add(box)
        m.set_popover(pop)
        return m

    def nv_add_env_menu(self, x):
        return self.nv_menu_button(None, "list-add-symbolic", [
            ("En otra versión de PHP (copiar su BBDD)…", lambda: self.on_replicate(x)),
            ("En Docker…", lambda: self.nv_docker_new_for(x))],
            "Añadir entorno: llevar el proyecto a otra versión de PHP o a Docker")

    def nv_docker_new_for(self, x):
        """«En Docker…» del + de Entorno: el diálogo «Proyecto en Docker» con ese proyecto elegido. Con Docker
        apagado o sin instalar, o si el proyecto ya está en Docker (su carpeta no sale en ese diálogo), lo
        mismo que «Añadir entorno en Docker…» del menú ⋮ (instalarlo, arrancarlo u otra versión de PHP)."""
        def got(rc, out):
            self.on_docker_data(rc, out)
            d = self.docker or {}
            if not d.get("ready") or not d.get("php") or self.nv_docker_of(x["name"]):
                self.nv_docker_add_env(x)
                return False
            self.docker_form.update(folder=x["name"], source=None, domain_set=False,
                                    domain=docker_slug(x["name"]) + ".docker.local")
            self.nv_docker_new()
            return False
        run_quick(["gui-docker"], got)

    def nv_row_menu(self, x):
        """Menú ⋮ de una fila de la lista (aparece al pasar el ratón, con Cargar): llevar el proyecto a
        otra versión o a Docker, importar su SQL y lo del menú Más, sin cambiar el proyecto de arriba."""
        items = [("Añadir entorno en otra versión de PHP…", lambda: self.on_replicate(x)),
                 ("Añadir entorno en Docker…", lambda: self.nv_docker_add_env(x)),
                 ("Importar SQL…", lambda: self.nv_import(x))] + self.nv_more_items(x)
        return self.nv_menu_button(None, "view-more-symbolic", items)

    def nv_more_menu(self, x):
        items = self.nv_more_items(x)
        loaded = self.loaded_project_folder()
        if loaded is not None and os.path.basename(loaded) == x["name"]:
            # (solo el cargado: se exporta con la versión de PHP donde está y su BBDD de esa versión)
            items.insert(2, ("Exportar proyecto…", lambda: self.nv_export_project(x)))
        return self.nv_menu_button(None, "view-more-symbolic", items)

    def nv_more_items(self, x):
        items = [("Opciones de la BBDD…", lambda: self.on_link_project(x)),
                 ("Abrir la carpeta", lambda: self.open_uri("file://%s/%s" % (HTDOCS, x["name"])))]
        for dp in self.nv_docker_of(x["name"]):
            # (uno por entorno de Docker: cada uno dice el suyo)
            items.append(("Eliminar de Docker (PHP %s)…" % ", ".join(dp.get("versions") or [dp["php"]]),
                          lambda dp=dp: self.on_docker_delete(dp)))
        db = self.project_base(x)
        if x["kind"] == "ps" and db:
            items.append(("Vaciar la caché de la tienda", lambda: self.run_task(
                "Vaciando la caché de la tienda de %s" % db, ["vaciar-cache", x["name"]],
                done_text="Caché vaciada", auto_close=True)))
        items.append(("Limpiar proyecto…", lambda: self.nv_clean_project(x)))
        if x["kind"] == "ps":
            items.append(("Descargar de producción las imágenes que faltan…", lambda: self.nv_ps_images(x)))
        elif x["kind"] == "wp":
            items.append(("Imágenes de producción…", lambda: self.nv_wp_media(x)))
        items.append(("Personalizar los botones…", lambda: self.nv_buttons_dialog()))
        items.append(("Borrar el proyecto…", lambda: self.nv_delete_project(x)))
        return items

    # --- Exportar proyecto: un zip con su código y su BBDD (gui-exportar-proyecto y exportar-proyecto) ---

    def nv_export_project(self, x):
        """⋮, Exportar proyecto… (del cargado): primero se mira su código en git. Con cambios sin commit no se
        deja exportar (se dice cuáles); si no, el diálogo con lo que se exporta."""
        name = x["name"]

        def got(_rc, out):
            lines = parse_lines(out)
            f = {ln[0]: ln for ln in lines}
            g, v = f.get("G"), f.get("V")
            if not g or len(g) < 6 or not v or len(v) < 5:
                message(self.win, "No se puede exportar «%s»" % name,
                        out.strip()[-400:] or "Sin respuesta del instalador.", Gtk.MessageType.ERROR)
                return False
            if not v[1]:
                message(self.win, "No hay ninguna versión activa",
                        "Para exportar un proyecto hace falta la versión de PHP donde está cargado.",
                        Gtk.MessageType.ERROR)
                return False
            if g[1] == "2":
                message(self.win, "No se puede comprobar el código de «%s»" % name,
                        "git no ha podido leer la carpeta: %s\n\nArréglalo antes de exportar." % g[2],
                        Gtk.MessageType.ERROR)
                return False
            n = int(g[3]) if g[3].isdigit() else 0
            if g[1] == "1" and n:
                shown = [ln[1] for ln in lines if ln[0] == "C" and len(ln) >= 2]
                more = "\n  y %d más" % (n - len(shown)) if n > len(shown) else ""
                message(self.win, "«%s» tiene cambios sin commit" % name,
                        "Tiene %s sin commit en git:\n\n%s%s\n\nHaz commit antes de exportar (o descarta esos "
                        "cambios): el zip tiene que llevar lo mismo que el repositorio."
                        % (plural(n, "cambio", "cambios"), "\n".join("  " + c for c in shown), more),
                        Gtk.MessageType.WARNING)
                return False
            self.nv_export_dialog(x, f)
            return False
        run_quick(["gui-exportar-proyecto", name], got)

    def nv_export_dialog(self, x, f):
        """«Exportar «carpeta»»: de qué versión de PHP, las casillas del código y de su BBDD (marcadas) y los
        pasos, que cambian con ellas. Al aceptar, la tarea exportar-proyecto."""
        name = x["name"]
        g, v = f["G"], f["V"]
        active = self.data.get("active") if self.data else None
        # (la BBDD del proyecto cargado, como la ve la ventana; si no está en esta versión, la del script)
        db = self.loaded_project_db()
        if not db or db not in self.data["dbs"].get(active, []):
            db = f.get("B", ["B", ""])[1]
        dest = f.get("D", ["D", ""])[1] or os.path.expanduser("~")
        zip_name = f.get("N", ["N", ""])[1] or "%s_php…_nexum.zip" % name
        size = int(f["S"][1]) if "S" in f and f["S"][1].isdigit() else 0
        ver_label = "%s · PHP %s" % (v[2], v[3] or "?")
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True, message_type=Gtk.MessageType.QUESTION,
                                buttons=Gtk.ButtonsType.NONE, text="Exportar «%s»" % name)
        ahead = int(g[4]) if g[4].isdigit() else 0
        if g[1] == "1":
            git = "El código está en git, sin cambios sin commit%s." % (" (rama %s)" % g[2] if g[2] else "")
        else:
            git = "No es un repositorio git: no se puede comprobar si tiene cambios sin commit."
        dlg.format_secondary_text("Se exporta de la versión activa, donde está cargado: %s.\n%s" % (ver_label, git))
        widen(dlg)
        extra = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        code = Gtk.CheckButton(label="Código: %s/%s · %s (sin la carpeta .git)" % (HTDOCS, name, fmt_size(size)),
                               active=True)
        extra.pack_start(code, False, False, 0)
        if db:
            base = Gtk.CheckButton(label="Base de datos: %s (%s)" % (db, v[2]), active=True)
        else:
            base = Gtk.CheckButton(label="Base de datos: Sin BBDD vinculada", active=False, sensitive=False)
        extra.pack_start(base, False, False, 0)
        if ahead:
            extra.pack_start(label("Tiene %s sin subir a su rama remota: el zip los lleva, pero el repositorio "
                                   "remoto no." % plural(ahead, "commit", "commits"),
                                   "aviso-rojo", wrap=True, max_width_chars=60, xalign=0), False, False, 0)
        holder = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin_top=8)
        extra.pack_start(holder, False, False, 0)
        dlg.get_message_area().pack_start(extra, False, False, 0)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Exportar", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)

        def update(*_):
            with_code, with_db = code.get_active(), base.get_active() and bool(db)
            steps = []
            if with_code:
                steps.append("Se copia el código de %s/%s en %s/, sin .git (los enlaces que salen de la carpeta "
                             "no van)." % (HTDOCS, name, name))
            if with_db:
                steps.append("Se descarga la BBDD %s de %s en %s.sql, como «Descargar»: sin el administrador de "
                             "pruebas ni los cambios del correo de pruebas." % (db, v[2], db))
            steps.append("Se escribe el zip en %s/%s, con un LEEME-nexum.txt. Si falla o lo cancelas, no queda "
                         "nada." % (dest, zip_name))
            for child in holder.get_children():
                holder.remove(child)
            holder.pack_start(steps_box(steps), False, False, 0)
            holder.show_all()
            ok.set_sensitive(with_code or with_db)
        code.connect("toggled", update)
        base.connect("toggled", update)
        dlg.show_all()
        update()
        resp = run_dialog(dlg)
        with_code, with_db = code.get_active(), base.get_active() and bool(db)
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT or not (with_code or with_db):
            return
        args = ["exportar-proyecto", name, "--destino", dest] + ([] if with_code else ["--sin-codigo"]) + \
            (["--bd", db] if with_db else ["--sin-bd"])

        def done(success, task, _p):
            if success:
                task.offer("Mostrar en la carpeta", lambda: self.open_uri(GLib.filename_to_uri(dest)))

        def start(_pwd=None):
            self.run_task("Exportando %s" % name, args, progress=True, env=self.db_env() if with_db else None,
                          on_done=done, done_text="«%s» exportado en %s" % (name, dest),
                          cancel_text=("¿Cancelar la exportación?", "No se guarda nada: el zip a medias se borra.",
                                       "Cancelar la exportación"))
        if with_db:
            self.check_db_access(start)
        else:
            start()

    def nv_images_button(self, x):
        """Imágenes de producción: un WordPress las pide a su web real; una tienda las descarga."""
        b = nv_button(logo("imagenes", 18), "Imágenes de producción",
                      "Traer de producción las imágenes que falten",
                      lambda *_: self.nv_wp_media(x) if x["kind"] == "wp" else self.nv_ps_images(x), "nv-proyecto-btn")
        b.set_sensitive(not self.busy)
        return b

    def nv_wp_media(self, x):
        """media-proyecto: lo que le falte a un WordPress de wp-content/uploads se pide a su web real
        mientras esté cargado (por web.local). Se propone el dominio de su base (home o siteurl)."""
        name = x["name"]

        def got(rc, out):
            f = {l[0]: l[1] for l in parse_lines(out) if len(l) >= 2}
            saved, guess = f.get("G", ""), f.get("D", "")
            dlg = Gtk.Dialog(title="Imágenes de producción", transient_for=self.win, modal=True, use_header_bar=True)
            dlg.set_default_size(520, -1)
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
            box.pack_start(label("Imágenes de producción de %s" % name, "nv-titulo", wrap=True), False, False, 0)
            box.pack_start(label("Mientras esté cargado (y, si está en el Apache de Docker, también allí), lo que "
                                 "falte en su carpeta wp-content/uploads (imágenes, vídeos y PDF) se pide a su web "
                                 "real: no hace falta descargarlo. Lo que ya está en local se sigue sirviendo desde "
                                 "aquí.", "nv-tenue", wrap=True,
                                 max_width_chars=60), False, False, 0)
            entry = Gtk.Entry(text=saved or guess, placeholder_text="ejemplo.com", max_length=80,
                              activates_default=True)
            box.pack_start(entry, False, False, 0)
            if guess and not saved:
                box.pack_start(label("Es el dominio de su BBDD: compruébalo antes de guardar.", "nv-chico", "nv-tenue"),
                               False, False, 0)
            dlg.get_content_area().add(box)
            if saved:
                css(dlg.add_button("Quitar", Gtk.ResponseType.REJECT), "destructive-action")
            dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
            ok = css(dlg.add_button("Guardar", Gtk.ResponseType.OK), "nv-azul")
            dlg.set_default_response(Gtk.ResponseType.OK)

            def clean():
                return re.sub(r"^https?://", "", entry.get_text().strip().lower()).rstrip("/")

            # (el mismo de antes también: se vuelve a aplicar, en web.local y en el Apache de Docker)
            def update(*_):
                d = clean()
                ok.set_sensitive(bool(DOMAIN_RX.match(d)) and not d.endswith((".local", ".test")))
            entry.connect("changed", update)
            dlg.show_all()
            update()
            resp = run_dialog(dlg)
            prod = clean()
            dlg.destroy()
            if resp == Gtk.ResponseType.REJECT:
                self.run_task("Quitando las imágenes de producción de %s" % name, ["media-proyecto", name, "quitar"],
                              done_text="%s ya no pide nada a producción" % name, auto_close=True)
            elif resp == Gtk.ResponseType.OK:
                self.run_task("Imágenes de producción de %s" % name, ["media-proyecto", name, prod],
                              done_text="%s pide a %s las imágenes que le faltan" % (name, prod), auto_close=True)
            return False
        run_quick(["gui-wp-produccion", name], got, env=self.db_env())

    def nv_ps_images(self, x):
        """ps-imagenes: una tienda se ve con su dominio real falseado (una redirección volvería aquí), así
        que las imágenes que faltan se descargan de la web real, con la lista de su BBDD."""
        name = x["name"]
        if not confirm(self.win, "¿Descargar las imágenes que le faltan a %s?" % name,
                       "Se descargan de su web real las imágenes de productos, categorías y marcas que no "
                       "están en su carpeta img (la lista sale de su BBDD: la de la versión activa o, si no está "
                       "allí, la de su proyecto del Apache de Docker). Van a su carpeta img, la misma con LAMPP y con "
                       "Docker. Lo que ya "
                       "está en local no se toca. Con muchos productos puede tardar y ocupar bastante.\n\n"
                       "Su dominio está falseado en este equipo: se busca con DNS cifrado (Cloudflare) y se "
                       "comprueba su certificado real.", "Descargar"):
            return
        self.check_db_access(lambda _pwd: self.run_task(
            "Descargando las imágenes de %s" % name, ["ps-imagenes", name], env=self.db_env(),
            done_text="Imágenes de %s descargadas" % name))

    # Limpiar proyecto (gui-limpiar-proyecto y limpiar-proyecto): cada clave, con su título y lo que se hace
    PROJECT_CLEAN_ITEMS = [("cache", "Caché", "se vacía su caché"),
                           ("registros", "Registros", "se borran sus registros"),
                           ("actualizaciones", "Restos de actualizaciones", "se vacían los restos de las actualizaciones")]

    def nv_clean_project(self, x):
        """⋮, Limpiar proyecto…: lo que tiene de caché, registros y restos de actualizaciones (gui-limpiar-proyecto),
        cada cosa con sus carpetas, lo que ocupa y su casilla (marcada); se confirma con lo que se va a hacer y se
        lanza limpiar-proyecto con lo marcado. Si no tiene nada, se dice."""
        name = x["name"]

        def got(_rc, out):
            found = [(f[1], int(f[2]), int(f[3]), f[4]) for f in parse_lines(out)
                     if f[0] == "P" and len(f) >= 5 and f[2].isdigit() and f[3].isdigit() and int(f[3]) > 0]
            if not found:
                message(self.win, "Nada que limpiar", "No hay cachés ni registros que limpiar en %s." % name)
                return False
            self.nv_clean_project_dialog(name, found)
            return False
        run_quick(["gui-limpiar-proyecto", name], got)

    def nv_clean_project_dialog(self, name, found):
        info = {k: (t, step) for k, t, step in self.PROJECT_CLEAN_ITEMS}
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True, message_type=Gtk.MessageType.QUESTION,
                                buttons=Gtk.ButtonsType.NONE, text="Limpiar «%s»" % name)
        dlg.format_secondary_text("Marca lo que quieres limpiar. Las carpetas se quedan, vacías; nada de las "
                                  "imágenes ni de lo que se sube a la web.")
        widen(dlg)
        extra = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        checks = []
        for key, b, n, paths in found:
            title = info.get(key, (key, ""))[0]
            chk = Gtk.CheckButton(label="%s · %s · %s" % (title, fmt_size(b), plural(n, "fichero", "ficheros")),
                                  active=True, margin_top=6)
            extra.pack_start(chk, False, False, 0)
            extra.pack_start(css(label(", ".join(p for p in paths.split(",") if p), wrap=True, xalign=0,
                                       max_width_chars=60, margin_start=26), "dim-label", "subtitulo"), False, False, 0)
            checks.append((key, b, n, paths, chk))
        extra.pack_start(label("Lo que se limpia no se puede recuperar: no se hacen copias.", "aviso-rojo", wrap=True,
                               max_width_chars=60, xalign=0, margin_top=10), False, False, 0)
        dlg.get_message_area().pack_start(extra, False, False, 0)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Limpiar lo marcado…", Gtk.ResponseType.ACCEPT), "destructive-action")
        dlg.set_default_response(Gtk.ResponseType.CANCEL)

        def update(*_):
            ok.set_sensitive(any(c[4].get_active() for c in checks))
        for c in checks:
            c[4].connect("toggled", update)
        dlg.show_all()
        update()
        resp = run_dialog(dlg)
        chosen = [c[:4] for c in checks if c[4].get_active()]
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT or not chosen:
            return
        steps = ["%s (%s · %s): %s (%s)." % (info.get(k, (k, ""))[0], fmt_size(b), plural(n, "fichero", "ficheros"),
                                             info.get(k, ("", "se limpia"))[1], paths.replace(",", ", "))
                 for k, b, n, paths in chosen]
        warn = label("Lo que se limpia no se puede recuperar: no se hacen copias.", "aviso-rojo", wrap=True,
                     max_width_chars=60, xalign=0)
        if not confirm(self.win, "¿Limpiar «%s»?" % name, "Si algo es del administrador (lo que creó Apache), se "
                       "pide su contraseña.", "Limpiar", destructive=True, extra=warn, steps=steps):
            return
        self.run_task("Limpiando %s" % name, ["limpiar-proyecto", name] + [k for k, *_r in chosen],
                      done_text="%s limpio" % name, auto_close=True)

    def nv_delete_project(self, x):
        """Borra el proyecto entero (borrar-proyecto): su carpeta, sus vhosts y dominios, lo de Docker y,
        si se marca, su BBDD de la versión activa (la de phpMyAdmin), con copia si se marca. Hay que
        escribir el nombre de la carpeta para confirmar: la carpeta no se puede recuperar."""
        name = x["name"]
        active = self.data["active"] if self.data else None
        db = next((d for i, d in self.project_pairs(x) if i["folder"] == active), None)
        docker = self.nv_docker_of(name)
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True, message_type=Gtk.MessageType.WARNING,
                                buttons=Gtk.ButtonsType.NONE, text="¿Borrar el proyecto «%s»?" % name)
        what = ["su carpeta %s/%s" % (HTDOCS, name), "sus vhosts y las líneas de sus dominios en /etc/hosts"]
        if docker:
            what.append("sus contenedores de Docker (%s)" % ", ".join(dp["domain"] for dp in docker))
        dlg.format_secondary_markup("Se borran %s. <b>La carpeta no se puede recuperar.</b>"
                                    % GLib.markup_escape_text(", ".join(what[:-1]) + " y " + what[-1]))
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Borrar el proyecto", Gtk.ResponseType.ACCEPT), "destructive-action")
        dlg.set_default_response(Gtk.ResponseType.CANCEL)
        extra = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        drop = copy = None
        if db:
            drop = Gtk.CheckButton(label="Borrar también su BBDD «%s» (lampp-%s, la de phpMyAdmin)" % (db, active))
            copy = Gtk.CheckButton(label="Guardar antes una copia en ~/nexum-backups (se puede volver a cargar)",
                                   active=False, margin_start=24)
            no_copy = label("Sin copia, la BBDD no se podrá recuperar.", "error", wrap=True, max_width_chars=50,
                            margin_start=24)
            no_copy.set_no_show_all(True)
            extra.pack_start(drop, False, False, 0)
            extra.pack_start(copy, False, False, 0)
            extra.pack_start(no_copy, False, False, 0)
        extra.pack_start(label("Escribe %s para confirmar:" % name, "error", wrap=True, max_width_chars=50),
                         False, False, 0)
        entry = Gtk.Entry(activates_default=False)
        extra.pack_start(entry, False, False, 0)
        dlg.get_message_area().pack_start(extra, False, False, 0)

        def update(*_):
            if copy is not None:
                copy.set_sensitive(drop.get_active())
                no_copy.set_visible(drop.get_active() and not copy.get_active())
            ok.set_sensitive(entry.get_text().strip() == name)
        entry.connect("changed", update)
        if drop is not None:
            drop.connect("toggled", update)
            copy.connect("toggled", update)
        dlg.show_all()
        update()
        resp = run_dialog(dlg)
        with_db = bool(drop and drop.get_active())
        with_copy = bool(copy and copy.get_active())
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return
        args = ["borrar-proyecto", name]
        if with_db:
            args += ["--bd", db] + (["--copia"] if with_copy else [])
        done = "Proyecto «%s» borrado" % name + (" con su BBDD" if with_db else "") \
            + (" (copia en ~/nexum-backups)" if with_db and with_copy else "")

        def go(*_):
            self.run_task("Borrando el proyecto %s" % name, args, env=self.db_env() if with_db else None,
                          done_text=done)
        if with_db:
            self.check_db_access(go)
        else:
            go()

    def nv_import(self, x):
        pairs = self.project_pairs(x)
        act = next((d for i, d in pairs if i["folder"] == self.data["active"]), None)
        self.imp.update(project=x["name"], db=act or self.imp.get("db"))
        self.build_databases()
        self.show_tab("bbdd")
        self.toast("Elige el fichero en «Subir o actualizar una BBDD»: proyecto %s" % x["name"])

    def nv_new_project(self):
        # El asistente de siempre (clonar de git, version y BBDD), en una ventana aparte
        if getattr(self, "proj_box", None) is None:
            return
        if self.np_dialog is None:
            self.np_dialog = Gtk.Window(title="Nuevo proyecto", transient_for=self.win, modal=False)
            self.np_dialog.set_default_size(700, -1)
            self.np_dialog.connect("delete-event", lambda w, *_: (self.toggle_new_project(False), w.hide(), True)[2])
            if self.new_proj_rev.get_parent():
                self.new_proj_rev.get_parent().remove(self.new_proj_rev)
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=20)
            box.pack_start(self.new_proj_rev, True, True, 0)
            self.np_dialog.add(box)
        self.toggle_new_project(True)
        self.np_dialog.show_all()

    def toggle_new_project(self, show):
        super().toggle_new_project(show)
        if not show and self.np_dialog is not None:
            self.np_dialog.hide()
