// MARK: acciones

extension AppModel {
    /// Dirección de la web de un proyecto en Docker: la del Apache de Docker o, en los de antes, la del
    /// Apache del Mac
    func dockerSite(_ p: DockerProject) -> String {
        return p.isWeb ? dockerWebURL(docker, p.domain) : "https://\(p.domain)"
    }

    var dockerPmaURL: String { return dockerWebURL(docker, "pma." + dockerTLD(docker)) + "/" }

    func saveVisor(_ c: VisorConf) {
        guard saveVisorConf(c) else {
            message("No se han podido guardar los botones", VISOR_FILE, error: true)
            return
        }
        visorConf = c
        panel = nil
        toast("Botones del proyecto guardados")
    }

    // Consumo (cada 3 s) y el túnel abierto

    func usageTick() {
        guard !usageBusy else { return }
        usageBusy = true
        DispatchQueue.global(qos: .utility).async {
            let u = sampleUsage()
            DispatchQueue.main.async {
                self.usageBusy = false
                if !u.isEmpty && u != self.usage { self.usage = u }
                self.refreshTunnel()
            }
        }
    }

    func refreshTunnel() {
        let t = readTunnel()
        if t != tunnel { tunnel = t }
    }

    /// Lo de cloudflared (tunel: I|instalado|versión|la del programa)
    func reloadTunnelInfo() {
        runQuick(["tunel"]) { _, out in
            let f = parseLines(out).first(where: { $0[0] == "I" && $0.count >= 4 })
            if f != self.tunnelInfo { self.tunnelInfo = f }
        }
    }

    /// «Compartir» del visor: abre un túnel de Cloudflare a esa dirección; si ya lo está, «Compartiendo»
    /// (con el borde naranja) enseña la dirección y la contraseña
    func shareButton(_ url: String, folder: String, name: String, conf: VisorConf) -> some View {
        let mine = tunnel?.target == url
        return VisorButton(conf: conf, name: mine ? "Compartiendo" : "Compartir", icon: .logo("cloudflare"),
                           tip: mine ? "Ver dirección y contraseña"
                                : "Compartir con un túnel de Cloudflare",
                           kind: mine ? "compartiendo" : "") {
            if mine { self.shareDialog() } else { self.share(url, folder: folder, name: name) }
        }
    }

    /// Abre un túnel a esa web, con lo suyo, que se elige ahora: cuánto dura y si se bloquea el panel de
    /// administración. Su contraseña, siempre una nueva al azar (se ve al abrirlo, para copiarla)
    func share(_ url: String, folder: String, name: String, live: Bool = true) {
        var text = "Cualquiera que tenga la dirección y la contraseña verá \(url) tal y como está en este Mac\(live ? " (lo que cambies, al momento)" : "") mientras el túnel esté abierto."
        if let t = tunnel { text += " Se cierra el que hay abierto (\(t.target))." }
        let installed = FileManager.default.isExecutableFile(atPath: TUNNEL_DIR + "/cloudflared")
        if !installed { text += " La primera vez se descarga cloudflared, el programa de Cloudflare (unos 20 MB)." }
        text += " Lleva una contraseña nueva al azar: se ve al abrirlo, para copiarla y mandarla."
        let alert = NSAlert()
        alert.messageText = "Compartir \(name)"
        alert.addButton(withTitle: "Compartir")
        alert.addButton(withTitle: "Cancelar")
        func line(_ title: String, _ views: [NSView]) -> NSView {
            let t = NSTextField(labelWithString: title)
            t.textColor = .secondaryLabelColor
            t.translatesAutoresizingMaskIntoConstraints = false
            t.widthAnchor.constraint(equalToConstant: 150).isActive = true
            let row = NSStackView(views: [t] + views)
            row.orientation = .horizontal
            row.spacing = 10
            return row
        }
        let hours = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 110, height: 26), pullsDown: false)
        hours.addItems(withTitles: (1...12).map { plural($0, "hora", "horas") })
        hours.selectItem(at: 1)
        let block = NSButton(checkboxWithTitle: "Bloquear el panel de administración (tus BBDD llevan el administrador de pruebas)",
                             target: nil, action: nil)
        block.state = .on
        alert.accessoryView = dialogStack([
            dialogLabel(text, color: .secondaryLabelColor),
            line("Se cierra solo en", [hours]), block,
        ], spacing: 12)
        guard alert.runStyled() == .alertFirstButtonReturn else { return }
        let args = ["tunel-abrir", url, folder, "--horas", String(hours.indexOfSelectedItem + 1),
                    "--admin", block.state == .on ? "bloquear" : "permitir"]
        let open: () -> Void = {
            _ = self.runTask("Abriendo el túnel de \(name)", args, doneText: "Túnel abierto", autoClose: true) { ok, _, _ in
                self.refreshTunnel()
                if ok && self.tunnel != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.shareDialog() }
                }
            }
        }
        if installed {
            open()
        } else {
            runTask("Instalando cloudflared", ["tunel-instalar"], progress: true, doneText: "cloudflared instalado", autoClose: true) { ok, _, _ in
                self.reloadTunnelInfo()
                if ok { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { open() } }
            }
        }
    }

    /// La dirección del túnel abierto y su contraseña, para copiarlas y mandarlas
    func shareDialog() {
        refreshTunnel()
        guard let t = tunnel else {
            toast("El túnel ya está cerrado")
            return
        }
        let hour = clockTime(t.expires)
        let alert = NSAlert()
        alert.messageText = "Compartiendo \(t.target)"
        alert.addButton(withTitle: "Listo")
        let close = alert.addButton(withTitle: "Cerrar el túnel")
        close.hasDestructiveAction = true
        // La dirección y la contraseña, cada una en su recuadro: su nombre encima, el valor a la izquierda y
        // Copiar a la derecha. Lo copiado se dice debajo, en verde (el aviso de la ventana queda detrás)
        let copied = NSTextField(labelWithString: "")
        copied.textColor = .systemGreen
        copied.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        copied.alignment = .left
        copied.translatesAutoresizingMaskIntoConstraints = false
        copied.widthAnchor.constraint(equalToConstant: DIALOG_WIDTH).isActive = true
        var stamp = 0
        func copy(_ text: String, _ what: String) {
            copyText(text)
            copied.stringValue = "✓ \(what)"
            stamp += 1
            let mine = stamp
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if stamp == mine { copied.stringValue = "" } }
        }
        // (la dirección y la contraseña se copian cada una por su lado: se mandan por separado)
        let copyURL = DialogValidator()
        copyURL.update = { copy(t.url, "Dirección copiada") }
        let copyPass = DialogValidator()
        copyPass.update = { copy(t.password, "Contraseña copiada") }
        let openURL = DialogValidator()
        openURL.update = { if let u = URL(string: t.url) { NSWorkspace.shared.open(u) } }
        func field(_ title: String, _ value: String, _ v: DialogValidator) -> NSView {
            let l = NSTextField(labelWithString: title)
            l.textColor = .secondaryLabelColor
            l.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            let val = NSTextField(labelWithString: value)
            val.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
            val.isSelectable = true
            val.lineBreakMode = .byTruncatingMiddle
            val.toolTip = value
            val.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let texts = NSStackView(views: [l, val])
            texts.orientation = .vertical
            texts.alignment = .leading
            texts.spacing = 2
            let b = NSButton(title: "Copiar", target: v, action: #selector(DialogValidator.changed(_:)))
            b.setContentHuggingPriority(.required, for: .horizontal)
            // (la fila misma hace de recuadro: su alto sale de lo que lleva dentro. Dentro de un NSBox con solo el
            // ancho, el diálogo le daba 0 de alto y las dos filas se pintaban una encima de otra)
            let row = NSStackView(views: [texts, NSView(), b])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 10
            row.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
            row.wantsLayer = true
            row.layer?.cornerRadius = 8
            row.layer?.borderWidth = 1
            row.layer?.borderColor = NSColor.separatorColor.cgColor
            row.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: DIALOG_WIDTH).isActive = true
            row.setContentHuggingPriority(.required, for: .vertical)
            row.setContentCompressionResistancePriority(.required, for: .vertical)
            return row
        }
        let open = NSButton(title: "Abrir", target: openURL, action: #selector(DialogValidator.changed(_:)))
        open.toolTip = "Abrirla tú en el navegador"
        let openRow = NSStackView(views: [open, NSView()])
        openRow.orientation = .horizontal
        openRow.translatesAutoresizingMaskIntoConstraints = false
        openRow.widthAnchor.constraint(equalToConstant: DIALOG_WIDTH).isActive = true
        alert.accessoryView = dialogStack([
            field("Dirección", t.url, copyURL), field("Contraseña", t.password, copyPass), copied, openRow,
            dialogLabel("Se cierra solo a las \(hour). "
                        + (t.block ? "El panel de administración va bloqueado." : "⚠ El panel de administración no va bloqueado.")
                        + " Quién entra y lo que se bloquea queda en el registro del túnel (Configuración, Túnel de Cloudflare).",
                        color: .secondaryLabelColor, align: .left),
        ], spacing: 10)
        let r = alert.runStyled()
        withExtendedLifetime([copyURL, copyPass, openURL]) {}
        if r == .alertSecondButtonReturn {
            tunnelClose()
        }
    }

    func tunnelClose() {
        runQuick(["tunel-cerrar"]) { rc, _ in
            self.refreshTunnel()
            self.toast(rc == 0 ? "Túnel cerrado: la dirección ya no lleva a ningún sitio" : "No se ha podido cerrar el túnel")
        }
    }

    // Docker: lo común, parar todo y las versiones de PHP

    /// Proyectos del Apache de Docker en marcha que usan un contenedor común: el Apache de Docker o su
    /// phpMyAdmin (todos) o una MariaDB común (los que van con esa versión). Vacío si no es común
    func sharedUsers(_ name: String) -> [String] {
        guard let k = docker else { return [] }
        var maria: String? = nil
        var bridge: String? = nil
        if name.range(of: "^nexum-mariadb-[0-9]+-[0-9]+$", options: .regularExpression) != nil {
            maria = String(name.dropFirst(14)).replacingOccurrences(of: "-", with: ".")
        } else if name.range(of: "^nexum-lampp-bd-[0-9]+-[0-9]+(-[0-9]+)?$", options: .regularExpression) != nil {
            bridge = String(name.dropFirst(15)).replacingOccurrences(of: "-", with: ".")
        } else if name != "nexum-web" && name != "nexum-pma" {
            return []
        }
        let up = k.containers.filter { $0.state == "running" }.map { $0.name }
        return k.projects.filter { p in
            // (una MariaDB común no la usan los que van en vivo con XAMPP-X; el puente, solo esos)
            p.isWeb && (maria.map { p.maria == $0 && p.lampp.isEmpty } ?? true) && (bridge.map { p.lampp == $0 } ?? true) && up.contains { n in
                n.range(of: "^nexum-" + NSRegularExpression.escapedPattern(for: p.slug) + "-php[0-9]{2}$",
                        options: .regularExpression) != nil
            }
        }.map { $0.folder }
    }

    /// Antes de parar algo común: si lo usa algún proyecto en marcha, se dice cuáles y se pregunta
    func stopSharedOK(_ names: [String], _ what: String) -> Bool {
        let users = Array(Set(names.flatMap { sharedUsers($0) })).sorted()
        if users.isEmpty { return true }
        let many = users.count > 1
        let text: String
        if names.contains(where: { $0.hasPrefix("nexum-mariadb-") || $0.hasPrefix("nexum-lampp-bd-") }) {
            text = "Es común: ahora \(many ? "la usan" : "la usa") \(users.joined(separator: ", ")). \(many ? "Se quedarán" : "Se quedará") sin BBDD (errores de conexión) hasta que la vuelvas a arrancar; al arrancar un proyecto que va con ella, se arranca sola."
        } else {
            text = "Es común: ahora \(many ? "lo usan" : "lo usa") \(users.joined(separator: ", ")). \(many ? "Dejarán" : "Dejará") de verse hasta que lo vuelvas a arrancar; al arrancar un proyecto del Apache de Docker, se arranca solo."
        }
        return confirm("¿Parar \(what)?", text,
                       names.contains(where: { $0.hasPrefix("nexum-mariadb-") }) ? "Pararla igualmente" : "Pararlo igualmente",
                       destructive: true)
    }

    func dockerStopAll() {
        runTask("Parando todos los contenedores de Nexum", ["docker-parar-todo"], doneText: "Contenedores de Nexum parados",
                autoClose: true) { _, _, _ in self.reloadDocker(stats: true) }
    }

    /// docker-web arrancar|parar|permitir|confiar (el Apache de Docker)
    func dockerWebCommand(_ action: String) {
        let titles = ["arrancar": "Arrancando el Apache de Docker", "parar": "Parando el Apache de Docker",
                      "permitir": "Dando de alta la dirección del Apache de Docker",
                      "confiar": "Certificado de Docker en el navegador"]
        runTask(titles[action] ?? action, ["docker-web", action], doneText: "Listo", autoClose: true) { _, _, _ in
            self.reloadDocker(stats: true)
        }
    }

    /// docker-web dns activar|quitar: el DNS comodín de *.docker.test
    func dockerDNS(_ on: Bool) {
        if on {
            guard confirm("¿Activar el DNS de *.docker.test?",
                          "Un DNS mínimo, solo en este Mac (127.0.0.1), que contesta a cualquier <algo>.docker.test. Los proyectos del Apache de Docker pasan a .docker.test (su configuración, el dominio de las tiendas en su BBDD y el certificado) y sus líneas salen de /etc/hosts. Desde entonces, añadir proyectos o versiones de Docker no pide la contraseña por los dominios. web.local, los proyectos de siempre y los dominios falseados de las tiendas no cambian. Si no contesta, se quita y todo sigue como estaba. Pide la contraseña de administrador.",
                          "Activar") else { return }
        } else {
            guard confirm("¿Quitar el DNS de *.docker.test?",
                          "Los dominios de Docker siguen siendo .docker.test y vuelven a /etc/hosts. Pide la contraseña de administrador.",
                          "Quitar", destructive: true) else { return }
        }
        runTask(on ? "Activando el DNS de *.docker.test" : "Quitando el DNS de *.docker.test",
                ["docker-web", "dns", on ? "activar" : "quitar"],
                doneText: "DNS de *.docker.test " + (on ? "puesto" : "quitado")) { _, _, _ in self.reloadDocker() }
    }

    /// Dirección y puertos del Apache de Docker (docker-web puertos)
    func dockerWebPorts(_ ip: String, _ http: String, _ https: String) {
        let a = ip.trimmingCharacters(in: .whitespaces), h = http.trimmingCharacters(in: .whitespaces),
            s = https.trimmingCharacters(in: .whitespaces)
        if a.range(of: "^127\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$", options: .regularExpression) == nil
            || Int(h) == nil || Int(s) == nil {
            message("Dirección o puertos no válidos",
                    "La dirección tiene que ser de este Mac (127.x.x.x, como 127.0.0.2) y los puertos, números.", error: true)
            return
        }
        runTask("Dirección y puertos del Apache de Docker", ["docker-web", "puertos", a, h, s],
                doneText: "Apache de Docker en \(a) (\(h) y \(s))", autoClose: true) { _, _, _ in self.reloadDocker() }
    }

    /// Versiones de PHP de un proyecto del Apache de Docker: añadir, quitar y, en una tienda, elegir
    func dockerVersions(_ p: DockerProject) {
        guard let k = docker, !busy else { return }
        let ps = p.kind == "ps"
        let group = RadioGroup()
        var options: [NSView] = []
        var acts: [([String], String, String)] = []
        func add(_ text: String, _ args: [String], _ title: String, _ done: String) {
            let b = NSButton(radioButtonWithTitle: text, target: group, action: #selector(RadioGroup.pick(_:)))
            b.state = group.buttons.isEmpty ? .on : .off
            group.buttons.append(b)
            options.append(b)
            acts.append((args, title, done))
        }
        if ps {
            for v in p.versions where v != p.php {
                add("Elegir PHP \(v) (la tienda pasa a ir con ella)", ["docker-php-elegir", p.slug, v],
                    "\(p.folder) con PHP \(v)", "\(p.folder) ya va con PHP \(v)")
            }
        }
        if p.versions.count > 1 {
            for v in p.versions {
                add("Quitar PHP \(v) (su contenedor; la carpeta y la BBDD se quedan)", ["docker-php-quitar", p.slug, v],
                    "Quitando PHP \(v) de \(p.folder)", "PHP \(v) quitado de \(p.folder)")
            }
        }
        let rest = k.php.filter { !p.versions.contains($0) }
        let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 160, height: 26), pullsDown: false)
        pop.addItems(withTitles: rest.map { "PHP \($0)" })
        if !rest.isEmpty {
            let b = NSButton(radioButtonWithTitle: "Añadir otra:", target: group, action: #selector(RadioGroup.pick(_:)))
            b.state = group.buttons.isEmpty ? .on : .off
            group.buttons.append(b)
            let row = NSStackView(views: [b, pop])
            row.orientation = .horizontal
            row.spacing = 8
            options.append(row)
        }
        if options.isEmpty {
            message("Versiones de PHP de \(p.folder)", "Tiene PHP \(p.php) y no hay otra versión que añadir.")
            return
        }
        let now = ps ? "La tienda guarda su dominio en la BBDD: va con \(dockerSite(p)) y la versión que elijas (ahora PHP \(p.php))."
            : "Todas a la vez, cada una con su dominio (\(p.slug)-php83.\(dockerTLD(k))), con la misma carpeta y la misma BBDD."
        let alert = NSAlert()
        alert.messageText = "Versiones de PHP de \(p.folder)"
        alert.addButton(withTitle: "Hacerlo")
        alert.addButton(withTitle: "Cancelar")
        alert.accessoryView = dialogStack([
            dialogLabel(now + " Tiene: PHP " + p.versions.joined(separator: ", ") + ". La primera vez con cada versión se prepara su imagen (unos minutos).",
                        color: .secondaryLabelColor),
            dialogOptions(options),
        ], spacing: 14)
        guard alert.runStyled() == .alertFirstButtonReturn else { return }
        let i = group.buttons.firstIndex(where: { $0.state == .on }) ?? -1
        if i >= 0 && i < acts.count {
            let a = acts[i]
            runTask(a.1, a.0, doneText: a.2, autoClose: true) { _, _, _ in self.reloadDocker() }
        } else if i == acts.count && pop.indexOfSelectedItem >= 0 && pop.indexOfSelectedItem < rest.count {
            let v = rest[pop.indexOfSelectedItem]
            runTask("Añadiendo PHP \(v) a \(p.folder)", ["docker-php-anadir", p.slug, v], doneText: "\(p.folder) con PHP \(v)") { _, _, _ in
                self.reloadDocker()
            }
        }
    }

    /// Un proyecto de antes (con XAMPP-X delante) pasa al Apache de Docker (docker-pasar)
    func dockerPass(_ p: DockerProject) {
        let c = confirmCopy("¿Pasar \(p.folder) al Apache de Docker?",
                            "Ya no necesitará XAMPP-X y podrás añadirle más versiones de PHP. Pide la contraseña de administrador.",
                            "Pasarlo",
                            steps: ["Su BBDD (\(p.db)) se carga en la MariaDB común de Docker.",
                                    "Se quitan sus contenedores de ahora, su vhost de XAMPP-X, su clave y su línea de /etc/hosts."],
                            warning: "Sin copia, su BBDD de ahora no se podrá recuperar.")
        if !c.ok { return }
        runTask("Pasando \(p.folder) al Apache de Docker", ["docker-pasar", p.slug] + (c.copy ? ["--copia"] : []), progress: true,
                doneText: "\(p.folder) ya va con el Apache de Docker") { _, _, _ in self.reloadDocker() }
    }
}

/// Formulario «Proyecto en Docker»: la carpeta, su versión de PHP y de MariaDB y la BBDD de XAMPP-X que
/// se copia (si se quiere). Va con el Apache de Docker (desde la 1.40): sin dominio que elegir
struct DockerNewPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let k = model.docker ?? DockerData()
        let taken = Set(k.projects.map { $0.folder })
        let folders = projectFolders().filter { !taken.contains($0) }
        let x = model.projects?.list.first(where: { $0.name == model.dkForm.folder })
        let pairs = x.map { model.projectPairs($0) } ?? []
        // (ancho del nombre más largo, para verlo entero al elegirlo)
        let wide = fitWidth(folders + pairs.map { "\($0.1) (XAMPP-\($0.0.folder))" } + [model.dkForm.domain],
                            min: 320, max: 520)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Va con el Apache de Docker (sin XAMPP-X) y su BBDD, en una MariaDB común. Su configuración (wp-config.php o la de PrestaShop) cambia solo dentro del contenedor: la carpeta sigue sirviendo con XAMPP-X. Más versiones de PHP: «Versiones de PHP…» de su visor.")
                .font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
            formRow("Carpeta") {
                SearchPicker(selection: Binding(get: { model.dkForm.folder }, set: { v in
                    model.dkForm.folder = v
                    model.dkForm.source = ""
                    if !model.dkForm.domainSet { model.dkForm.domain = dockerSlug(v) + ".docker.local" }
                }), items: folders.map { ($0, $0) }, width: wide)
            }
            formRow("PHP") {
                SearchPicker(selection: $model.dkForm.php, items: k.php.map { ($0, "PHP \($0)") }, width: 180)
                // (las imágenes oficiales de 8.1 y anteriores ya no reciben parches: siguen con PHP2Shell)
                if verParts(model.dkForm.php).lexicographicallyPrecedes([8, 2]) && !model.dkForm.php.isEmpty {
                    Text("Vulnerable (PHP2Shell)").font(.caption.weight(.bold)).foregroundColor(RED)
                        .tip("Imagen sin parches: solo con proyectos de confianza")
                }
            }
            formRow("MariaDB") {
                SearchPicker(selection: $model.dkForm.maria, items: k.maria.map { ($0, "MariaDB \($0)") }, width: 180)
            }
            formRow("BBDD") {
                SearchPicker(selection: $model.dkForm.source,
                             items: [("", "— Ninguna: vacía —")] + pairs.map { pr in ("\(pr.0.folder)|\(pr.1)", "\(pr.1) (XAMPP-\(pr.0.folder))") },
                             width: wide)
            }
            if !model.dkForm.source.isEmpty && x?.kind == "wp" {
                formRow("Cómo") {
                    SearchPicker(selection: Binding(get: { model.dkForm.live ? "vivo" : "copia" },
                                                    set: { model.dkForm.live = $0 == "vivo" }),
                                 items: [("vivo", "En vivo: la misma que web.local (sin copias)"), ("copia", "Una copia en Docker")],
                                 width: wide)
                }
            }
            if folders.isEmpty {
                Text("Todas las carpetas de htdocs están ya en Docker.").font(.callout).foregroundColor(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancelar") { model.panel = nil }.buttonStyle(OutlineButton())
                Button("Crear en Docker") { model.dockerCreate() }
                    .buttonStyle(OutlineButton(kind: "primary"))
                    .disabled(folders.isEmpty || model.dkForm.folder.isEmpty || model.busy)
            }
        }
        .onAppear { model.fillDockerForm(folders) }
    }

    func formRow<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 150, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}
