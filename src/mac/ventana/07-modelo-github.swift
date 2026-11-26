extension AppModel {
    // MARK: repositorios de GitHub

    func reloadGithub() {
        runQuick(["github"]) { _, out in
            if let g = parseLines(out).first(where: { $0.first == "G" && $0.count >= 6 }) {
                self.github = GitHubState(on: g[1] == "1", login: g[2], source: g[3], account: g[4], prefixes: g[5])
            }
        }
    }

    /// Después de conectar o cambiar algo: lo dice, y la lista de antes ya no vale (otra cuenta o prefijos)
    func githubDone(_ rc: Int32, _ out: String) {
        let lines = out.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if rc == 0 {
            toast(lines.last ?? "Hecho")
        } else {
            // (un error se queda en una ventana hasta que se cierra: en el aviso de abajo no da tiempo a leerlo)
            let why = lines.suffix(6).joined(separator: "\n")
            message("No se ha podido conectar con GitHub", why.isEmpty ? "No se ha podido" : why, error: true)
        }
        repos = nil
        reloadGithub()
    }

    func githubToken() {
        let r = runDialog(title: "Conectar con GitHub",
                          text: "Solo para leer la lista de repositorios (también los privados): se clonan por SSH, con tu clave. Créalo en GitHub (Settings, Developer settings, Personal access tokens) con el permiso «repo» (y «read:org» para los de una organización) y pégalo aquí. Se guarda en el Llavero, no en un fichero.",
                          okLabel: "Conectar", hasField: true, placeholder: "ghp_… o github_pat_…", secure: true,
                          validate: { _, t in (t.trimmingCharacters(in: .whitespaces).count >= 20, nil, false) })
        guard r.ok else { return }
        toast("Comprobando el token con GitHub…")
        runQuick(["github-conectar"], input: r.text.trimmingCharacters(in: .whitespaces) + "\n") { rc, out in self.githubDone(rc, out) }
    }

    /// Guardar la cuenta o los prefijos: si no vale, se dice en una ventana y lo escrito se queda
    func githubSet(_ key: String, _ value: String) {
        runQuick(["github", key, value]) { rc, out in
            if rc != 0 {
                let lines = out.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                message("No se ha guardado", lines.last ?? "No se ha podido guardar", error: true)
                return
            }
            self.githubDone(rc, out)
        }
    }

    func reloadNode() {
        runQuick(["gui-node"]) { _, out in
            let items = parseNode(out)
            if items != self.nodeItems { self.nodeItems = items }
        }
    }

    // MARK: Nginx (pestaña Nginx)
    func reloadNginx() {
        runQuick(["gui-nginx"]) { _, out in
            let n = parseNginx(out)
            if n != self.nginx { self.nginx = n }
        }
    }

    /// Encender o apagar Nginx: su pestaña sale o se oculta (apagarlo lo para, sin borrar nada)
    func nginxUse(_ on: Bool) {
        runTask("Nginx: \(on ? "encendiendo" : "apagando")", ["nginx-usar", on ? "si" : "no"],
                doneText: "Nginx \(on ? "encendido" : "apagado")", autoClose: true) { _, _, _ in
            self.nginxUsed = FileManager.default.fileExists(atPath: LOG_DIR + "/nginx/usar")
            if !self.nginxUsed && self.tab == "nginx" { self.openTab("config") }
            self.reloadNginx()
        }
    }

    func nginxDo(_ cmd: String, _ title: String, _ done: String) {
        runTask(title, [cmd], doneText: done, autoClose: true) { _, _, _ in self.reloadNginx() }
    }

    func nginxInstall() {
        runTask("Instalando Nginx \(nginx?.latest ?? "")", ["nginx-instalar"], progress: true, doneText: "Nginx instalado",
                autoClose: true) { _, _, _ in self.reloadNginx() }
    }

    func nginxAdd(_ folder: String, _ sub: String) {
        runTask("Añadiendo \(folder) a Nginx", ["nginx-anadir", folder] + (sub.isEmpty ? [] : [sub]),
                doneText: "\(folder) en Nginx", autoClose: true) { _, _, _ in self.reloadNginx() }
    }

    func nginxRemove(_ p: NginxProject) {
        guard confirm("¿Quitar \(p.folder) de Nginx?",
                      "Deja de servirse en \(p.host). Su carpeta y sus BBDD no se tocan, y Apache lo sigue sirviendo.",
                      "Quitar", destructive: true) else { return }
        runTask("Quitando \(p.folder) de Nginx", ["nginx-quitar", p.folder], doneText: "\(p.folder) ya no está en Nginx",
                autoClose: true) { _, _, _ in self.reloadNginx() }
    }

    func nginxPorts(_ http: String, _ https: String) {
        let h = http.trimmingCharacters(in: .whitespaces), s = https.trimmingCharacters(in: .whitespaces)
        guard let a = Int(h), let b = Int(s), (1024...65535).contains(a), (1024...65535).contains(b), a != b else {
            message("Puertos no válidos", "Dos números distintos, de 1024 a 65535 (como 8080 y 8443).", error: true)
            return
        }
        runTask("Puertos de Nginx", ["nginx-puertos", h, s], doneText: "Nginx en los puertos \(h) y \(s)", autoClose: true) { _, _, _ in
            self.reloadNginx()
        }
    }

    func startNode(_ p: NodeItem, mode: String) {
        runTask("Arrancando \(p.folder)", ["node-arrancar", p.folder, mode], progress: true,
                doneText: "\(p.folder) en marcha", autoClose: true) { _, _, _ in self.reloadNode() }
    }

    /// Túnel: solo se comparte lo compilado (el túnel no deja pasar /node_modules/.vite y así el código
    /// fuente no sale del Mac). Si no lo está, se compila y arranca antes
    func shareNode(_ p: NodeItem) {
        let path = HTDOCS + "/" + p.folder
        if p.running && p.mode == "compilado" {
            share(p.url, folder: path, name: p.folder, live: false)
            return
        }
        if p.running {
            guard confirm("¿Compilar \(p.folder) para compartirlo?",
                          "Está en desarrollo, y lo que se comparte es la versión compilada. Se para y arranca compilado: los cambios ya no se verán al momento.",
                          "Compilar y compartir") else { return }
        }
        runTask("Arrancando \(p.folder)", ["node-arrancar", p.folder, "compilado"], progress: true,
                doneText: "\(p.folder) en marcha", autoClose: true) { ok, _, _ in
            guard ok else {
                self.reloadNode()
                return
            }
            runQuick(["gui-node"]) { _, out in
                let items = parseNode(out)
                self.nodeItems = items
                if let now = items.first(where: { $0.folder == p.folder }), now.running {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.share(now.url, folder: path, name: p.folder, live: false)
                    }
                }
            }
        }
    }

    func stopNode(_ p: NodeItem) {
        runTask("Parando \(p.folder)", ["node-parar", p.folder],
                doneText: "\(p.folder) parado", autoClose: true) { _, _, _ in
            self.reloadNode()
            self.refreshTunnel()
        }
    }

    func reloadRepos(cache: Bool = false) {
        let args = ["repos"] + (reposAll ? ["--todos"] : []) + (cache ? ["--cache"] : [])
        if !cache { reposLoading = true }
        runQuick(args) { _, out in
            if !cache { self.reposLoading = false }
            let r = parseRepos(out)
            if cache && r.head.isEmpty { return }
            if !cache, let e = r.error, !(self.repos?.head ?? []).isEmpty {
                // (sin conexión con GitHub: se queda la lista de la última vez, y se dice)
                self.repos?.error = e
            } else {
                self.repos = r
            }
        }
    }

    /// Clonar (por SSH) o, si ya está clonado, traer sus cambios con git pull, preguntando antes
    func fetchRepo(_ r: RepoItem) {
        var args = ["repo-traer", r.full]
        var title = "Clonando \(r.name)"
        // (solo con git, en su carpeta y sin sudo: va ya, al lado de la que siga, si no es de la misma carpeta)
        let free = task != nil && taskFree(r.folder)
        if r.state == "clonado" {
            guard confirm("¿Traer los cambios de GitHub a \(r.folder)?",
                          "Este repositorio ya está clonado en \(HTDOCS)/\(r.folder). Se traen sus cambios de GitHub (git pull) y se juntan con los tuyos. Si chocan con lo que tienes sin subir o sin guardar, no se toca nada y se dice.",
                          "Traer los cambios", task: !free) else { return }
            args.append("--actualizar")
            title = "Trayendo los cambios de \(r.name)"
        }
        if free {
            runFree(title, args, doneText: "Hecho") { [weak self] _ in self?.reloadRepos(cache: true) }
            return
        }
        _ = runTask(title, args, doneText: "Hecho", autoClose: true) { ok, _, _ in
            self.reloadRepos(cache: true)
            if ok && r.state != "clonado" { self.toast("\(r.name), en Proyectos") }
        }
    }

    func updateComponents(_ c: ComponentsState) {
        let r = confirmCopy("¿Actualizar todo?", "Las versiones de PHP se rehacen con lo último de su rama (varios minutos; la de ahora sigue funcionando mientras se compila). Los contenedores de Docker en marcha se rehacen en unos segundos: sus BBDD y su configuración no cambian." + (c.docker ? " Docker Desktop se instala a mano: antes se copian todas las BBDD de Docker en ~/nexum-backups y luego se abre su descarga." : ""),
                            "Actualizar todo", steps: c.items, warning: UPDATE_COPY_WARNING)
        if !r.ok { return }
        components = nil
        _ = runTask("Actualizando los componentes", ["componentes-actualizar"] + (r.copy ? ["--copia"] : []), progress: true,
                    doneText: "Componentes al día", reloadBranches: true) { _, _, _ in self.reloadComponents() }
    }

    func toast(_ text: String) {
        toastText = text
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toastText = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    func reload(branches withBranches: Bool = false) {
        runQuick(["gui-datos"]) { rc, out in self.onData(rc, out) }
        reloadHosts()
        reloadServices()
        reloadProjects()
        reloadDocker()
        reloadDbSizes()
        reloadProjectSizes()
        if withBranches {
            branches = nil
            branchesError = nil
            runQuick(["gui-ramas"]) { rc, out in self.onBranches(rc, out) }
        }
        runQuick(["gui-fechas"]) { _, out in
            var dates: [String: [String]] = [:]
            for f in parseLines(out) where f[0] == "F" && f.count >= 4 { dates[f[1]] = [f[2], f[3]] }
            if !dates.isEmpty && dates != self.phpDates { self.phpDates = dates }
        }
    }

    /// gui-vuelta: cada parte («@@<orden>|<código>» y sus líneas) a lo de siempre
    private func onRound(_ rc: Int32, _ out: String) {
        var parts: [String: (Int32, [String])] = [:]
        var name = ""
        for line in out.components(separatedBy: "\n") {
            if line.hasPrefix("@@gui-"), let bar = line.firstIndex(of: "|") {
                name = String(line[line.index(line.startIndex, offsetBy: 2)..<bar])
                parts[name] = (Int32(line[line.index(after: bar)...]) ?? 1, [])
            } else if !name.isEmpty {
                parts[name]?.1.append(line)
            }
        }
        // (sin ninguna parte, algo ha ido mal antes de empezar: la siguiente vuelta)
        let text = { (key: String) -> (Int32, String)? in
            parts[key].map { ($0.0, $0.1.joined(separator: "\n") + "\n") }
        }
        if let p = text("gui-datos") { onData(p.0, p.1) }
        if let p = text("gui-hosts") { onHosts(p.0, p.1) }
        if let p = text("gui-servicios") { onServices(p.0, p.1) }
        if let p = text("gui-proyectos") { onProjects(p.0, p.1) }
    }

    /// Al abrirse la ventana, antes de las órdenes de verdad: lo que leyó la última vez (DATA_CACHED), por el mismo
    /// código que interpreta cada respuesta, para pintarla al momento. Las de verdad lo sustituyen al llegar. Sin
    /// avisos ni preguntas: gui-datos, sin lo que hace onData después de guardar los datos (cached)
    func loadDataCache() {
        if let out = dataCacheRead("gui-datos") { onData(0, out, cached: true) }
        if let out = dataCacheRead("gui-hosts") { onHosts(0, out) }
        if let out = dataCacheRead("gui-servicios") { onServices(0, out) }
        if let out = dataCacheRead("gui-proyectos") { onProjects(0, out) }
        if let out = dataCacheRead("gui-docker") { onDocker(out) }
    }

    /// (cached: lo guardado de la última vez; solo se pintan los datos, sin preguntas, avisos ni nada más)
    private func onData(_ rc: Int32, _ out: String, cached: Bool = false) {
        var d = AppData()
        for f in parseLines(out) {
            switch f[0] {
            case "M" where f.count >= 4:
                d.name = f[1]
                d.version = f[2]
                d.signature = f[3]
            case "A" where f.count >= 4:
                d.active = f[1]
                d.running = f[2] == "1"
                d.official = f[3] == "1"
            case "V" where f.count >= 8:
                d.installs.append(Install(folder: f[1], php: f[2], apache: f[3], mariadb: f[4], ftp: f[5],
                                          perl: f[6], pma: f[7],
                                          blocker: f.count > 8 ? f[8...].joined(separator: "|").trimmingCharacters(in: .whitespaces) : ""))
            case "D" where f.count >= 3:
                d.dbs[f[1], default: []].append(f[2])
                if f.count >= 5, let when = Int(f[3]) {
                    d.dbDates[f[1] + "|" + f[2]] = DbDate(when: when, imported: f[4] == "i")
                }
            case "J" where f.count >= 3:
                d.marks.insert(f[1] + "|" + f[2])
            case "H" where f.count >= 3:
                d.vhosts = f[1]
                d.hosts = f[2]
            case "Z" where f.count >= 2:
                d.stray = f[1...].joined(separator: "|")
            case "W" where f.count >= 3:
                d.orphans.append(OrphanVhost(folder: f[1], domains: f[2]))
            case "N" where f.count >= 2:
                d.exposed = f[1...].joined(separator: "|")
            case "U" where f.count >= 2:
                d.unsecured = f[1].split(separator: " ").map(String.init)
            case "K" where f.count >= 2:
                d.apacheOld = f[1]
            case "Y" where f.count >= 3:
                d.dbsysVersion = f[1]
                d.dbsysLog = Int64(f[2]) ?? 0
            case "C" where f.count >= 3:
                d.certs.append(CertIssue(domain: f[1], why: f[2]))
            case "W" where f.count >= 2:
                d.cas.append(f[1...].joined(separator: "|"))
            case "G" where f.count >= 2:
                d.untrusted.append(f[1])
            case "Q" where f.count >= 2:
                d.stale.append(f[1])
            case "X" where f.count >= 3:
                d.php2shell[f[1]] = f[2]
            case "T" where f.count >= 2:
                d.barrier = f[1] != "0"
                d.barrierAllowed = f.count >= 3 ? f[2].split(separator: " ").map(String.init) : []
            case "E" where f.count >= 8:
                var m = MailState()
                m.installed = f[1] == "1"
                m.on = f[2] == "1"
                m.wp = f[3]
                m.running = f[4] == "1"
                m.version = f[5]
                m.url = f[6].hasPrefix("http://127.0.0.1:") ? f[6] : "http://127.0.0.1:8025/"
                m.offer = f[7]
                d.mail = m
            case "O" where f.count >= 3:
                d.copies[f[1]] = Int(f[2]) ?? 0
            case "R" where f.count >= 2:
                d.asides.append(f[1])
            default:
                break
            }
        }
        if rc != 0 && d.installs.isEmpty && d.version.isEmpty {
            loadError = String(out.suffix(600))
            return
        }
        loadError = nil
        if impFolder != d.active {
            impFolder = d.active
            impDb = nil
        }
        if let db = impDb, !(d.dbs[d.active] ?? []).contains(db) { impDb = nil }
        if d != data { data = d }
        if cached { return }
        // (con la versión ya cargada y en marcha: si tiene BBDD marcadas para borrar, se pregunta)
        dbMarksCheck()
        // (los correos sin leer, solo con Mailpit en marcha)
        pollMail()
        if !sized {
            sized = true
            DispatchQueue.main.async { self.fitWindow(installs: d.installs.count) }
        }
        if !secureAsked { DispatchQueue.main.async { self.secureAfterUpdate(d) } }
        if !apacheOldAsked, !d.apacheOld.isEmpty, d.unsecured.isEmpty {
            DispatchQueue.main.async { self.apacheOldCheck(d) }
        }
    }

    /// Una vez por sesión de la ventana: si el Apache en marcha sigue con la configuración de antes (se ha
    /// escrito y no se ha recargado), se pregunta si se reinicia. No a la vez que el aviso de aplicar la
    /// seguridad: ese ya reinicia Apache
    func apacheOldCheck(_ d: AppData) {
        guard !SIMULATE, !apacheOldAsked, !d.apacheOld.isEmpty else { return }
        apacheOldAsked = true
        if confirm("Apache sigue con la configuración de antes",
                   "La configuración de Apache de XAMPP-\(d.apacheOld) ha cambiado (la seguridad, la barrera entre webs...) y Apache no se ha recargado: hasta reiniciarlo, sigue con lo de antes. Reiniciarlo pide la contraseña de administrador. Si lo dejas para luego, está en los avisos.",
                   "Reiniciar Apache") {
            reloadApacheConfig()
        }
    }

    /// Tras actualizar Nexum, una vez por versión: si a las versiones de PHP les falta lo que pone esta
    /// (la barrera entre webs de ahora, las reglas de Apache...), se pregunta si se aplica ya. Al
    /// actualizar no se toca su configuración (es de root y pide la contraseña); sin esto, seguirían con
    /// lo de la versión de antes hasta pulsar Protegerlas
    func secureAfterUpdate(_ d: AppData) {
        guard !SIMULATE, !secureAsked, !d.version.isEmpty else { return }
        secureAsked = true
        let file = LOG_DIR + "/seguridad-aplicada"
        let done = ((try? String(contentsOfFile: file, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if done == d.version { return }
        try? FileManager.default.createDirectory(atPath: LOG_DIR, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? (d.version + "\n").write(toFile: file, atomically: true, encoding: .utf8)
        if !d.unsecured.isEmpty, confirm("Aplicar la seguridad de la \(d.version)",
                "Nexum se ha actualizado, pero las versiones de PHP siguen con la configuración de Apache de antes (\(d.unsecured.map { "XAMPP-" + $0 }.joined(separator: ", "))): les falta lo de esta versión, como la barrera entre webs de ahora. Aplicarlo pide la contraseña de administrador y reinicia Apache si está en marcha. Si lo dejas para luego, está en Protegerlas, en los avisos.",
                "Aplicar ahora") {
            secureAll()
        }
    }

    /// Alto para que la pestaña Bases de datos se vea entera sin agrandar la ventana (sin pasar del
    /// alto de la pantalla). SwiftUI de macOS 12 no deja fijar el tamaño inicial: se agranda al llegar
    /// los datos, con una estimación por número de versiones (cabecera, buscador, carga y una fila por versión)
    func fitWindow(installs n: Int) {
        guard let w = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }),
              let screen = w.screen ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let want = CGFloat(720 + 57 * max(n, 1))
        let h = min(max(w.frame.height, want), area.height)
        guard h > w.frame.height + 1 else { return }
        var f = w.frame
        f.origin.y -= h - f.height
        f.size.height = h
        if f.minY < area.minY { f.origin.y = area.minY }
        w.setFrame(f, display: true, animate: false)
    }

    private func onBranches(_ rc: Int32, _ out: String) {
        let rows = parseLines(out)
        if let err = rows.first(where: { $0[0] == "ERROR" }) {
            branchesError = field(err, 1)
            return
        }
        // De la rama mas nueva a la mas antigua. Si php.net no dio el estado de la rama, se deduce de
        // la lista de ramas con soporte
        let list = rows.filter { $0[0] == "B" && $0.count >= 7 }.map { f -> Branch in
            let st = field(f, 7)
            return Branch(branch: f[1], latest: f[2], supported: f[3] == "1", mariadb: f[4], perl: f[5], state: f[6],
                          phpState: st.isEmpty ? (f[3] == "1" ? "stable" : "eol") : st,
                          activeEnd: field(f, 8), securityEnd: field(f, 9),
                          date: field(f, 10) == "-" ? "" : field(f, 10), security: field(f, 11) == "1")
        }.sorted { a, b in
            a.branch.compare(b.branch, options: .numeric) == .orderedDescending
        }
        if rc != 0 && list.isEmpty {
            branchesError = out.trimmingCharacters(in: .whitespacesAndNewlines).suffix(400).description
            return
        }
        branches = list
        selected = selected.filter { b in list.contains(where: { $0.branch == b && $0.state == "nueva" }) }
    }
}
