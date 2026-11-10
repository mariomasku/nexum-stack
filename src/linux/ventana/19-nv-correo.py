class NvCorreo:
    """Correo de pruebas (Mailpit)."""

    # ------------------------------------------------------------------ correo de pruebas (Mailpit)
    def nv_mail(self):
        return (self.data or {}).get("mail") or {}

    def nv_mail_header(self):
        """Botón Correo de arriba: oculto con el correo de pruebas apagado; sin Mailpit instalado o
        parado, lleva a Configuración o lo explica."""
        m = self.nv_mail()
        self.mail_btn.set_visible(bool(m.get("on")))
        if not m.get("installed"):
            tip = "Mailpit no está instalado"
        elif not m.get("running"):
            tip = "Arranca la versión activa para ver el correo"
        else:
            n = self.mail_unread
            tip = "Correo de las webs (Mailpit)%s" % (": %d sin leer" % n if n else "")
        self.mail_btn.set_tooltip_text(tip)
        if not m.get("running"):
            self.nv_mail_count(None)
        else:
            self.nv_mail_poll()

    def nv_mail_poll(self):
        """Pregunta a Mailpit cuántos correos hay sin leer (en segundo plano, sin proxy)."""
        m = self.nv_mail()
        if not (m.get("on") and m.get("running")) or self.mail_polling:
            return
        # (en la demostración, nunca el Mailpit de verdad: sus correos sin leer saldrían en la captura)
        if DEMO and ":8025" in m["url"]:
            return
        self.mail_polling = True
        url = m["url"] + "api/v1/info"

        def work():
            n = None
            try:
                import json
                import urllib.request
                opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
                with opener.open(url, timeout=3) as r:
                    n = int(json.loads(r.read(100000).decode("utf-8", "replace")).get("Unread", 0))
            except Exception:  # noqa: BLE001 - parado o sin responder: sin número
                n = None
            GLib.idle_add(self.nv_mail_count, n, True)
        threading.Thread(target=work, daemon=True).start()

    def nv_mail_count(self, n, polled=False):
        if polled:
            self.mail_polling = False
        self.mail_unread = n
        if n:
            self.mail_num.set_label("99+" if n > 99 else str(n))
            self.mail_num.show()
        else:
            self.mail_num.hide()
        if self.nv_mail().get("running"):
            self.mail_btn.set_tooltip_text("Correo de las webs (Mailpit)%s" % (": %d sin leer" % n if n else ""))
        return False

    def nv_open_mail(self):
        m = self.nv_mail()
        if not m.get("installed"):
            self.nv_tools_show("Correo de pruebas (Mailpit)")
            self.toast("Instala Mailpit en Configuración, apartado Correo de pruebas")
        elif not m.get("running"):
            self.toast("Mailpit arranca con la versión activa: arráncala arriba")
        elif self.nv_mail_webkit() is None or getattr(self, "mail_web_dead", False):
            # (sin el componente del visor, o si se ha caído: como antes, en el navegador)
            self.open_uri(m["url"])
            GLib.timeout_add_seconds(3, lambda: (self.nv_mail_poll(), False)[1])
        else:
            self.nv_tools_show("Correo de pruebas (Mailpit)")

    def nv_mail_webkit(self):
        """El módulo del visor web (WebKitGTK para GTK 3) o None si no está instalado. Se carga la primera
        vez que hace falta: tarda y la ventana arranca igual sin él."""
        if not hasattr(self, "mail_webkit"):
            self.mail_webkit = None
            for version in ("4.1", "4.0"):
                try:
                    gi.require_version("WebKit2", version)
                    from gi.repository import WebKit2
                    self.mail_webkit = WebKit2
                    break
                except (ImportError, ValueError):
                    continue
        return self.mail_webkit

    def nv_mail_web(self):
        """El visor de la bandeja, siempre el mismo (al rehacer la pestaña no se pierde el correo abierto):
        sin nada en disco y sin proxy, porque Mailpit está en este equipo."""
        web = getattr(self, "mail_web", None)
        kit = self.nv_mail_webkit()
        if web is not None or kit is None:
            return web
        data = kit.WebsiteDataManager.new_ephemeral()
        data.set_network_proxy_settings(kit.NetworkProxyMode.NO_PROXY, None)
        ctx = kit.WebContext.new_with_website_data_manager(data)
        web = kit.WebView.new_with_context(ctx)
        web.get_settings().set_javascript_can_open_windows_automatically(False)
        web.connect("decide-policy", self.nv_mail_policy)
        web.connect("load-failed", self.nv_mail_load_failed)
        web.connect("web-process-terminated", self.nv_mail_crashed)
        web.connect("destroy", self.nv_mail_destroyed)
        ctx.connect("download-started", self.nv_mail_download)
        # (también su contexto: si Python lo suelta, el visor carga la página pero no la pinta)
        self.mail_web, self.mail_web_url, self.mail_web_ctx = web, None, (data, ctx)
        # (mientras se ve, el número de sin leer de arriba sigue a lo que se lee o se borra aquí)
        GLib.timeout_add_seconds(5, self.nv_mail_tick, web)
        return web

    def nv_mail_tick(self, web):
        if getattr(self, "mail_web", None) is not web:
            return False
        if web.get_mapped():
            self.nv_mail_poll()
        return True

    def nv_mail_policy(self, _web, decision, kind):
        """Solo se navega dentro de Mailpit. Un enlace de un correo va al navegador, y solo si se ha pulsado:
        un correo no puede abrir nada por su cuenta."""
        kit = self.mail_webkit
        if kind == kit.PolicyDecisionType.RESPONSE:
            if decision.is_mime_type_supported():
                return False
            uri = decision.get_request().get_uri()
            decision.ignore()
            self.nv_mail_external(uri)
            return True
        action = decision.get_navigation_action()
        uri = action.get_request().get_uri() or ""
        new_window = kind == kit.PolicyDecisionType.NEW_WINDOW_ACTION
        if not new_window and (uri.startswith(("about:", self.mail_web_url or "\0", "blob:" + (self.mail_web_url or "\0")))):
            return False
        decision.ignore()
        if new_window and action.is_user_gesture() \
                or action.get_navigation_type() == kit.NavigationType.LINK_CLICKED:
            self.nv_mail_external(uri)
        return True

    def nv_mail_external(self, uri):
        if (uri or "").startswith(("http://", "https://")):
            self.open_uri(uri)

    def nv_mail_download(self, _ctx, download):
        """Un adjunto: lo descarga el navegador, que pregunta dónde guardarlo."""
        uri = download.get_request().get_uri()
        download.cancel()
        self.nv_mail_external(uri)

    def nv_mail_load_failed(self, *_):
        # (parado o sin responder: se vuelve a pedir la próxima vez que se vea en marcha)
        self.mail_web_url = None
        return False

    def nv_mail_destroyed(self, web):
        # (destruido, su página ya no vale: la próxima vez se crea otro)
        if getattr(self, "mail_web", None) is web:
            self.mail_web = None

    def nv_mail_crashed(self, *_):
        """El proceso del visor se ha caído o no puede arrancar: se ofrece el navegador."""
        self.mail_web_dead = True
        self.mail_web = None
        GLib.idle_add(lambda: (self.build_tools(), False)[1])

    def nv_mail_view(self, m):
        """Debajo de las tarjetas: la bandeja de Mailpit o por qué no se ve."""
        box = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin_top=12), "caja")
        box.set_size_request(-1, 620)
        old = getattr(self, "mail_web", None)

        def note(text, command=None):
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, valign=Gtk.Align.CENTER, vexpand=True, margin=24)
            inner.pack_start(label(text, "nv-tenue", wrap=True, xalign=0.5, justify=Gtk.Justification.CENTER), False, False, 0)
            if command:
                inner.pack_start(label(command, "nv-chico", selectable=True, xalign=0.5), False, False, 0)
            if m["running"]:
                b = Gtk.Button(label="Abrir en el navegador", halign=Gtk.Align.CENTER)
                b.connect("clicked", lambda *_: self.open_uri(m["url"]))
                inner.pack_start(b, False, False, 0)
            box.pack_start(inner, True, True, 0)
            return box
        # (en la demostración, solo el Mailpit de la demostración, con sus correos inventados: nunca el de verdad,
        # que es el del puerto 8025)
        if DEMO and ":8025" in m["url"]:
            return note("La bandeja está vacía: aquí aparecerá lo que manden las webs de este equipo.")
        if SIMULATE and not DEMO:
            return note("En la simulación no se abre la bandeja: desde ella se pueden borrar correos.")
        if not m["running"]:
            if old is not None:
                self.mail_web_url = None
            return note("Mailpit está parado: arranca con la versión activa.")
        if getattr(self, "mail_web_dead", False):
            return note("La bandeja no se puede ver dentro de la ventana en este equipo.")
        web = self.nv_mail_web()
        if web is None:
            return note("Para ver la bandeja dentro de la ventana falta su componente:", "sudo apt install gir1.2-webkit2-4.1")
        box.pack_start(web, True, True, 0)
        if self.mail_web_url != m["url"]:
            self.mail_web_url = m["url"]
            web.load_uri(m["url"])
        return box

    def nv_mail_tools(self):
        """Configuración, Correo de pruebas: encenderlo, el modo de WordPress y Mailpit."""
        m = self.nv_mail()
        if not m:
            return
        on = m["on"]
        sw = Gtk.Switch(active=on, valign=Gtk.Align.CENTER, sensitive=not self.busy,
                        tooltip_text="Encendido: el correo de las webs va a Mailpit" if on else
                        "Apagado: lo que manden las webs puede llegar de verdad a los clientes")
        sw.connect("notify::active", self.on_mail_switch)
        tail = Gtk.Box(spacing=8)
        tail.pack_start(sw, False, False, 0)
        if not on:
            tail.pack_start(label("Apagado: lo que manden las webs puede llegar de verdad a los clientes",
                                  "nv-chico", "nv-correo-aviso", valign=Gtk.Align.CENTER), False, False, 0)
        box, lb = tile_group("Correo de pruebas (Mailpit)", tiles=True, lead=logo("mailpit", 20), tail=tail,
                        description=
                        "Lo que mandan las webs de este equipo (formularios, pedidos, contraseñas) no llega a "
                        "nadie: va a Mailpit, que lo enseña en su bandeja. PHP (mail()) en todas las versiones, "
                        "PrestaShop por SMTP y WordPress según su opción. Lo que se cambia en las BBDD no va en "
                        "las copias que descargas (exportar-bd, copiar-bd, Docker). Mailpit arranca y para con "
                        "la versión activa y solo se ve desde este equipo.")
        texts = {"mailpit": "Siguen funcionando, con su correo a Mailpit (los que usan una API, como Brevo, se desactivan en la copia local)",
                 "desactivar": "Se desactivan en la copia local: WordPress manda con mail(), a Mailpit",
                 "nada": "⚠ No se tocan: lo que manden puede llegar de verdad a los clientes"}
        row = ActionRow("WordPress con plugins de SMTP o Brevo", texts.get(m["wp"], ""))
        row.add_prefix(logo("wordpress", 18))
        if m["wp"] == "nada":
            css(row.subtitle, "nv-correo-aviso")
        combo = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
        for key, text in (("mailpit", "Llevarlos a Mailpit"), ("desactivar", "Desactivarlos en la copia local"),
                          ("nada", "No tocarlos")):
            combo.append(key, text)
        combo.set_active_id(m["wp"])
        combo.set_tooltip_text("Qué hacer con sus plugins de correo")
        combo.set_sensitive(on and not self.busy)
        combo.connect("changed", self.on_mail_wp)
        row.add_suffix(combo)
        lb.add(row)
        if m["installed"]:
            sub = "Mailpit %s · %s" % (m["version"] or "?", ("en marcha: %s" % (m["url"].replace(":18025/", ":8025/") if DEMO else m["url"])) if m["running"]
                                       else "parado: arranca con la versión activa")
            row = ActionRow("Bandeja de entrada", sub)
            row.add_prefix(icon("mail-unread-symbolic", 16))
            if m["offer"] and m["version"] and ver_tuple(m["offer"]) > ver_tuple(m["version"]):
                b = css(Gtk.Button(label="Actualizar a %s" % m["offer"], valign=Gtk.Align.CENTER), "verde")
                b.connect("clicked", lambda *_: self.on_mail_install())
                b.set_sensitive(not self.busy)
                row.add_suffix(b)
            b = Gtk.Button(label="Vaciar", tooltip_text="Vaciar la bandeja", valign=Gtk.Align.CENTER,
                           sensitive=m["running"] and not self.busy)
            b.connect("clicked", lambda *_: self.on_mail_clear())
            row.add_suffix(b)
        else:
            row = ActionRow("Mailpit no está instalado",
                            "Sin él, el correo de las webs no sale ni se ve. Se descarga de GitHub (Mailpit %s) y se "
                            "comprueba antes de instalarlo" % (m["offer"] or ""))
            row.subtitle.set_line_wrap(True)
            row.subtitle.set_ellipsize(0)
            b = css(Gtk.Button(label="Instalar Mailpit", valign=Gtk.Align.CENTER, sensitive=not self.busy), "verde")
            b.connect("clicked", lambda *_: self.on_mail_install())
            row.add_suffix(b)
        lb.add(row)
        if m["installed"]:
            box.pack_start(self.nv_mail_view(m), True, True, 0)
        self.tools_box.pack_start(box, False, False, 0)
        self.tools_box.reorder_child(box, 2)
        box.show_all()

    def on_mail_switch(self, sw, _p):
        on = sw.get_active()
        m = self.nv_mail()
        if on == m.get("on"):
            return
        args = ["correo", "si" if on else "no"]
        if on and not m.get("installed"):
            # (la primera vez: se ofrece instalar Mailpit, que se descarga de GitHub)
            if confirm(self.win, "¿Instalar Mailpit?",
                       "El correo de las webs irá a Mailpit, que se descarga de GitHub (Mailpit %s, comprobado "
                       "antes de instalarlo). Sin él, el correo no sale ni se ve." % (m.get("offer") or ""),
                       "Instalar Mailpit"):
                args.append("--instalar")
        if not on and not confirm(self.win, "¿Apagar el correo de pruebas?",
                                  "Lo que manden las webs (pedidos, formularios, contraseñas) podrá llegar de verdad "
                                  "a los clientes de las BBDD copiadas.", "Apagarlo", destructive=True):
            sw.set_active(True)
            return
        self.run_task("Encendiendo el correo de pruebas" if on else "Apagando el correo de pruebas", args,
                      auto_close=True, done_text="Correo de pruebas %s" % ("encendido" if on else "apagado"),
                      on_done=lambda *_: self.build_tools())

    def on_mail_wp(self, combo):
        mode = combo.get_active_id()
        if not mode or mode == self.nv_mail().get("wp"):
            return
        names = {"mailpit": "llevados a Mailpit", "desactivar": "desactivados en la copia local", "nada": "sin tocar"}
        self.run_task("Plugins de correo de WordPress: %s" % names[mode], ["correo", "wordpress", mode],
                      auto_close=True, done_text="Plugins de correo de WordPress %s" % names[mode],
                      on_done=lambda *_: self.build_tools())

    def on_mail_install(self):
        self.run_task("Instalando Mailpit", ["correo", "instalar"], progress=True, auto_close=True,
                      done_text="Mailpit instalado", on_done=lambda *_: self.build_tools())

    def on_mail_clear(self):
        if not confirm(self.win, "¿Vaciar la bandeja de Mailpit?", "Se borran todos los correos que han mandado "
                       "las webs de este equipo.", "Vaciar la bandeja", destructive=True):
            return

        def done(rc, out):
            self.toast("Bandeja de Mailpit vacía" if rc == 0 else (out.strip().splitlines() or ["No se ha podido vaciar"])[-1])
            self.nv_mail_poll()
            return False
        run_quick(["correo", "vaciar"], done)

    def show_tab(self, name):
        name = {"hosts": "dominios", "herramientas": "config", "servicios": "versiones"}.get(name, name)
        if name in self.tabs:
            lb, row = self.tabs[name]
            lb.select_row(row)
