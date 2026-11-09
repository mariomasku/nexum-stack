// MARK: - Acciones de la ventana nueva

extension AppModel {
    /// Cambia de apartado y lee lo que haga falta
    /// Abre Configuración en ese apartado (su clave de ToolsView.sections)
    func openTools(_ section: String) {
        toolsSection = section
        openTab("config")
    }

    func openTab(_ key: String) {
        tab = key
        // Al entrar en un apartado, sus desplegables aparecen plegados (las versiones de Bases de datos
        // y los proyectos de Docker; con una búsqueda se siguen viendo desplegados)
        expanded = expanded.filter { !$0.hasPrefix("@db") }
        dkOpen = []
        if key == "docker" { reloadDocker(stats: true) }
        if key == "node" { reloadNode() }
        if key == "repos" {
            if repos == nil { reloadRepos(cache: true) }
            reloadRepos()
        }
        if key == "bbdd" {
            refreshBackups()
            reloadDbSizes()
        }
    }

    var isDark: Bool {
        return dark ?? (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }

    /// Pone el tema guardado (solo en esta ventana)
    func applyTheme() {
        if dark == nil {
            let saved = ((try? String(contentsOfFile: THEME_FILE, encoding: .utf8)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if saved == "oscuro" { dark = true } else if saved == "claro" { dark = false }
        }
        if let dk = dark { NSApp.appearance = NSAppearance(named: dk ? .darkAqua : .aqua) }
    }

    func toggleTheme() {
        dark = !isDark
        applyTheme()
        try? FileManager.default.createDirectory(atPath: LOG_DIR, withIntermediateDirectories: true)
        try? ((dark ?? false) ? "oscuro\n" : "claro\n").write(toFile: THEME_FILE, atomically: true, encoding: .utf8)
    }

    /// Botón de encender o apagar del visor: arranca la versión activa o la para y desactiva
    func power() {
        guard let d = data, !d.active.isEmpty else {
            openTab("versiones")
            return
        }
        control(d.running ? "parar" : "arrancar", d.running ? "Parando" : "Arrancando")
    }

    /// Rama de php.net de una versión de PHP (8.4.12 → la de 8.4), nil si no se ha consultado
    func branch(_ php: String) -> Branch? {
        let b = php.split(separator: ".").prefix(2).joined(separator: ".")
        return branches?.first { $0.branch == b }
    }

    /// Último parche de su rama, si es más nuevo que el que tiene
    func newerPatch(_ inst: Install) -> String? {
        guard let b = branch(inst.php), !b.latest.isEmpty else { return nil }
        return verParts(inst.php).lexicographicallyPrecedes(verParts(b.latest)) ? b.latest : nil
    }

    /// Proyecto de una BBDD en una versión: el vinculado o, si no tiene, el único que la usa en su
    /// configuración
    func dbProject(_ db: String, _ folder: String) -> String {
        if let f = linkOf(db, folder) { return f }
        let users = (projects?.list ?? []).filter { $0.db == db }.map { $0.name }
        return users.count == 1 ? users[0] : ""
    }

    /// Proyectos en Docker de una carpeta de htdocs
    /// Columna Proyecto de la tabla de proyectos: tan ancha como el nombre más largo (se ve entero),
    /// entre 260 y 320 (uno más largo se corta con «…» y se ve entero al pasar el ratón)
    func projectNameWidth() -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let widest = (projects?.list ?? []).map { ceil(($0.name as NSString).size(withAttributes: [.font: font]).width) }.max() ?? 0
        return Swift.min(320, Swift.max(260, widest + 8))
    }

    /// Lo que necesita la tabla de proyectos para que no se apriete nada: los márgenes y los espacios
    /// de la fila, sus columnas fijas y, en Versiones, sitio para dos versiones y una de Docker
    var projectsTableWidth: CGFloat {
        let anyDocker = !(docker?.projects.isEmpty ?? true)
        return 28 + 5 * 12 + 20 + projectNameWidth() + 80 + 190 + 170 + (anyDocker ? 270 : 130)
    }

    /// Ancho mínimo de la ventana: la barra lateral (220 y su línea), los márgenes de la página (24 a
    /// cada lado), la barra de desplazamiento y la tabla de proyectos. Así no se puede hacer tan
    /// estrecha que se rompan los textos y las etiquetas (como mucho unos 1425: cabe en un portátil de 13")
    var minWindowWidth: CGFloat {
        return Swift.max(1140, 220 + 1 + 48 + 16 + projectsTableWidth)
    }

    func dockerOf(_ folder: String) -> [DockerProject] {
        return (docker?.projects ?? []).filter { $0.folder == folder }
    }

    /// Entorno elegido en el proyecto de arriba: x:<versión> lo carga en esa versión; d:<nombre> lleva
    /// a la pestaña Docker (el proyecto se abre por su dominio)
    func chooseEnv(_ x: Project, _ key: String) {
        if key.hasPrefix("d:") {
            openTab("docker")
            if let dp = dockerOf(x.name).first(where: { $0.slug == String(key.dropFirst(2)) }) {
                toast("\(x.name) en Docker: https://\(dp.domain)")
            }
            return
        }
        let folder = String(key.dropFirst(2))
        guard let p = projects, let d = data, let inst = d.installs.first(where: { $0.folder == folder }) else { return }
        if loadedEntry()?.name == x.name && folder == d.active { return }
        let db = projectPairs(x).first(where: { $0.0.folder == folder })?.1 ?? projectBase(x)
        let req = ProjectRequest(db: db, inst: inst, link: p.link, current: p.current, create: p.create,
                                 projects: p.list, saved: p.saved)
        loadProject(req, folder: x.name, version: folder, manual: false, confirmSwitch: true)
    }

    /// Importar SQL del proyecto de arriba: el formulario de Bases de datos con su BBDD y su carpeta
    func importFor(_ x: Project) {
        if let db = projectPairs(x).first(where: { $0.0.folder == data?.active })?.1 { impDb = db }
        impProject = x.name
        if !impProjects.contains(x.name) { refreshImpProjects() }
        openTab("bbdd")
        toast("Elige el fichero en «Subir o actualizar una BBDD»: proyecto \(x.name)")
    }

    /// Lo que ocupan las copias de seguridad (~/lvm-copias) y cuántos ficheros hay
    func refreshBackups() {
        DispatchQueue.global(qos: .utility).async {
            var size: Int64 = 0
            var n = 0
            let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
            if let en = FileManager.default.enumerator(at: URL(fileURLWithPath: NSHomeDirectory() + "/lvm-copias"),
                                                       includingPropertiesForKeys: keys) {
                for case let u as URL in en {
                    if let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true {
                        size += Int64(v.fileSize ?? 0)
                        n += 1
                    }
                }
            }
            DispatchQueue.main.async { self.backups = [size, Int64(n)] }
        }
    }

    /// Lo que ocupa cada proyecto en el disco: du en segundo plano, de 10 en 10 proyectos y como mucho una
    /// vez por minuto (cada uno se vuelve a medir cada 6 horas). Si quedan por medir, la siguiente tanda
    func reloadProjectSizes(now: Bool = false) {
        if projSizesBusy || (!now && Date().timeIntervalSince(projSizesAt) < 60) { return }
        projSizesBusy = true
        runQuick(["gui-proyectos-tamanos"]) { _, out in
            var sizes: [String: [Int64]] = [:]
            var more = false
            for f in parseLines(out) {
                if f.count >= 4 && f[0] == "T", let bytes = Int64(f[2]), let when = Int64(f[3]) { sizes[f[1]] = [bytes, when] }
                if f[0] == "F" { more = true }
            }
            self.projSizesBusy = false
            self.projSizesAt = Date()
            if sizes != self.projectSizes { self.projectSizes = sizes }
            if more { self.reloadProjectSizes(now: true) }
        }
    }

    /// Lo que ocupa cada BBDD: se mide en la versión activa si su MariaDB está en marcha y se recuerda
    /// lo medido en las demás (sus carpetas de datos no se pueden leer sin sudo)
    func reloadDbSizes() {
        runQuick(["gui-bbdd-tamanos"], env: dbEnv()) { _, out in
            var sizes: [String: [Int64]] = [:]
            for f in parseLines(out) where f.count >= 5 && f[0] == "Z" {
                if let bytes = Int64(f[3]), let when = Int64(f[4]) { sizes[f[1] + "|" + f[2]] = [bytes, when] }
            }
            if sizes != self.dbSizes { self.dbSizes = sizes }
        }
    }

    // MARK: Docker

    func reloadDocker(stats: Bool = false) {
        runQuick(["gui-docker"]) { _, out in self.onDocker(out) }
        if stats { runQuick(["gui-docker-estadisticas"]) { _, out in self.onDockerStats(out) } }
    }

    func onDocker(_ out: String) {
        var k = DockerData()
        for f in parseLines(out) {
            switch f[0] {
            case "S" where f.count >= 5:
                k.installed = f[1] == "1"
                k.ready = f[2] == "1"
                k.version = f[3]
                k.xampp = f[4] == "1"
                k.app = field(f, 5) == "1"
            case "V" where f.count >= 3:
                k.php = f[1].split(separator: " ").map(String.init)
                k.maria = f[2].split(separator: " ").map(String.init)
            case "P" where f.count >= 9:
                // (los del Apache de Docker: web en vez de los puertos, y su tipo y sus versiones al final)
                let isWeb = f[8] == "web"
                k.projects.append(DockerProject(slug: f[1], folder: f[2], php: f[3], maria: f[4], domain: f[5],
                                                state: f[6], db: f[7], pma: isWeb ? "" : f[8], web: field(f, 9),
                                                old: field(f, 10) == "1", isWeb: isWeb, kind: field(f, 11),
                                                versions: isWeb ? field(f, 12).split(separator: " ").map(String.init) : [],
                                                lampp: isWeb ? field(f, 13) : ""))
            case "W" where f.count >= 6:
                k.web = DockerWeb(ip: f[1], http: f[2], https: f[3], state: f[4], ok: f[5] == "1",
                                  tld: field(f, 6) == "docker.test" ? "docker.test" : "docker.local", dns: field(f, 7) == "1")
            case "C" where f.count >= 7:
                k.containers.append(DockerContainer(name: f[1], image: f[2], state: f[3], status: f[4],
                                                    ports: f[5], project: f[6],
                                                    cid: String(field(f, 7).prefix(12))))
            case "I" where f.count >= 6:
                // (imagen|etiqueta|ID|tamaño|creada)
                k.images.append(DockerImage(repo: f[1], tag: f[2], cid: String(f[3].prefix(12)), size: f[4], created: f[5]))
            case "I" where f.count >= 4:
                // (el de antes: imagen:etiqueta|tamaño|creada; la etiqueta, tras los últimos dos puntos
                // que no sean los del puerto de un registro)
                var repo = f[1], tag = ""
                if let r = f[1].range(of: ":", options: .backwards), !f[1][r.upperBound...].contains("/") {
                    repo = String(f[1][..<r.lowerBound])
                    tag = String(f[1][r.upperBound...])
                }
                k.images.append(DockerImage(repo: repo, tag: tag, cid: "", size: f[2], created: f[3]))
            case "O" where f.count >= 3:
                k.volumes.append(DockerVolume(name: f[1], driver: f[2]))
            default:
                break
            }
        }
        if k != docker { docker = k }
    }

    func onDockerStats(_ out: String) {
        var s = DockerStats()
        let units: [String: Double] = ["B": 1, "KiB": 1024, "MiB": 1048576, "GiB": 1073741824, "TiB": 1099511627776,
                                       "kB": 1000, "KB": 1000, "MB": 1000000, "GB": 1000000000]
        for f in parseLines(out) {
            if f[0] == "T" && f.count >= 3, let c = Int(f[1]), let t = Int64(f[2]) {
                s.cores = max(1, c)
                s.total = t
            } else if f[0] == "K" && f.count >= 4 {
                s.cpu[f[1]] = Double(f[2].replacingOccurrences(of: "%", with: "")) ?? 0
                let used = (f[3].components(separatedBy: "/").first ?? "").trimmingCharacters(in: .whitespaces)
                let num = String(used.prefix { "0123456789.".contains($0) })
                let unit = String(used.dropFirst(num.count)).trimmingCharacters(in: .whitespaces)
                s.mem[f[1]] = (Double(num) ?? 0) * (units[unit] ?? 1)
            }
        }
        if s != dkStats { dkStats = s }
    }

    /// Instalar Docker: en el Mac se explica y se abre la página de descarga de Docker Desktop. Si ya
    /// está, se abre y se espera a que responda
    func dockerInstall() {
        let k = docker ?? DockerData()
        if !k.installed && !k.app {
            guard confirm("Instalar Docker Desktop",
                          "En el Mac, Docker es Docker Desktop: se descarga de docker.com (Apple Silicon) y se arrastra a Aplicaciones. Ábrelo una vez, acepta su licencia y vuelve aquí.\n\nDespués añade \(HTDOCS) en su Settings › Resources › File sharing.",
                          "Abrir la descarga") else { return }
            openURL(DOCKER_DOWNLOAD)
            return
        }
        runTask("Abriendo Docker Desktop", ["docker-instalar"], progress: true, doneText: "Docker Desktop listo", autoClose: true)
    }

    func openDockerForm(folder: String?) {
        dkForm = DockerForm()
        if let f = folder {
            dkForm.folder = f
            dkForm.domain = dockerSlug(f) + ".docker.local"
        }
        openTab("docker")
        panel = .dockerNew
    }

    /// Valores por omisión del formulario: la primera carpeta libre y las versiones más nuevas
    func fillDockerForm(_ folders: [String]) {
        let k = docker ?? DockerData()
        if dkForm.folder.isEmpty || !folders.contains(dkForm.folder), let f = folders.first {
            dkForm.folder = f
            dkForm.source = ""
            if !dkForm.domainSet { dkForm.domain = dockerSlug(f) + ".docker.local" }
        }
        if dkForm.php.isEmpty, let v = k.php.first { dkForm.php = v }
        if dkForm.maria.isEmpty, let v = k.maria.first { dkForm.maria = v }
    }

    func dockerCreate() {
        let f = dkForm
        guard !f.folder.isEmpty, !f.php.isEmpty, !f.maria.isEmpty else { return }
        var args = ["docker-nuevo", f.folder, f.php, f.maria]
        let slug = dockerSlug(f.folder)
        let tld = dockerTLD(docker)
        let site = dockerWebURL(docker, (projects?.list.first(where: { $0.name == f.folder })?.kind == "ps")
                                ? slug + "." + tld : slug + "-php" + f.php.replacingOccurrences(of: ".", with: "") + "." + tld)
        var text = "Con el Apache de Docker (sin XAMPP-X): su PHP \(f.php) y su BBDD en la MariaDB \(f.maria) común. Se abrirá en \(site)."
        let src = f.source.split(separator: "|", maxSplits: 1).map(String.init)
        let wp = projects?.list.first(where: { $0.name == f.folder })?.kind == "wp"
        if src.count == 2 && wp && f.live {
            args += ["--bd", src[1], "--desde", src[0], "--en-vivo"]
            text += " Usa en vivo \(src[1]) de XAMPP-\(src[0]): la misma BBDD que web.local, sin copias."
        } else if src.count == 2 {
            args += ["--bd", src[1], "--desde", src[0]]
            text += " Se copia \(src[1]) de XAMPP-\(src[0]) (esa no se toca)."
        } else {
            text += " La BBDD empieza vacía."
        }
        text += " La primera vez con cada PHP se prepara su imagen (unos minutos). Pide la contraseña de administrador.\n\n\(HTDOCS) tiene que estar en Docker Desktop, Settings › Resources › File sharing."
        guard confirm("¿Crear \(f.folder) en Docker?", text, "Crear en Docker") else { return }
        runTask("Creando \(f.folder) en Docker", args, progress: true, doneText: "\(f.folder) en Docker: \(site)") { ok, _, _ in
            if ok { self.dkForm = DockerForm() }
            self.reloadDocker()
        }
    }

    /// La BBDD de un WordPress de Docker: en vivo la de una versión XAMPP-X (la misma que web.local) o su
    /// copia en la MariaDB común de Docker
    func dockerDbMode(_ p: DockerProject) {
        var versions: [String] = []
        if let x = projects?.list.first(where: { $0.name == p.folder }) {
            for (i, _) in projectPairs(x) where !versions.contains(i.folder) { versions.append(i.folder) }
        }
        var choices: [(String, String)] = versions.map { ("lampp|" + $0, "En vivo: la de XAMPP-\($0) (la de web.local)") }
        choices.append(("docker", "Su copia en la MariaDB común de Docker"))
        let now = p.lampp.isEmpty ? "docker" : "lampp|" + p.lampp
        let alert = NSAlert()
        alert.messageText = "BBDD de \(p.folder) en Docker"
        alert.addButton(withTitle: "Usarla")
        alert.addButton(withTitle: "Cancelar")
        let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 380, height: 26), pullsDown: false)
        pop.addItems(withTitles: choices.map { $0.1 })
        pop.selectItem(at: choices.firstIndex(where: { $0.0 == now }) ?? 0)
        alert.accessoryView = dialogStack([
            dialogLabel("En vivo, Docker usa la misma BBDD que web.local: lo que cambies en un lado se ve en el otro, sin copias. Si la MariaDB de esa versión no está en marcha, se arranca solo ella, en otro puerto. La copia de Docker no se borra: se puede volver a ella."
                        + (versions.isEmpty ? " Su BBDD no está en ninguna versión de XAMPP-X." : ""), color: .secondaryLabelColor),
            pop,
        ], spacing: 10)
        guard alert.runStyled() == .alertFirstButtonReturn else { return }
        let i = pop.indexOfSelectedItem
        guard i >= 0, i < choices.count, choices[i].0 != now else { return }
        let c = choices[i].0
        let args = ["docker-bd", p.slug] + (c.hasPrefix("lampp|") ? ["lampp", String(c.dropFirst(6))] : ["docker"])
        _ = runTask("BBDD de \(p.folder)", args, doneText: "Hecho", autoClose: true) { _, _, _ in self.reloadDocker() }
    }

    func dockerAction(_ p: DockerProject, start: Bool) {
        runTask((start ? "Arrancando " : "Parando ") + p.folder, [start ? "docker-arrancar" : "docker-parar", p.slug],
                doneText: "\(p.folder) \(start ? "en marcha" : "parado")", autoClose: true)
    }

    func dockerLogs(_ p: DockerProject) {
        runTask("Registros de \(p.folder)", ["docker-registros", p.slug])
    }

    func dockerDelete(_ p: DockerProject) {
        guard confirm("¿Borrar \(p.folder) de Docker?",
                      p.isWeb ? "Se borran sus contenedores, su BBDD (\(p.db)) y su usuario de la MariaDB común y sus dominios; no se puede deshacer. La carpeta y las BBDD de XAMPP-X no se tocan. Pide la contraseña de administrador."
                        : "Se borran sus contenedores, su copia de la BBDD (\(p.db)) y su vhost (\(p.domain)); no se puede deshacer. La carpeta y las BBDD de XAMPP-X no se tocan. Pide la contraseña de administrador.",
                      "Borrar de Docker", destructive: true) else { return }
        runTask("Borrando \(p.folder) de Docker", ["docker-borrar", p.slug],
                doneText: "\(p.folder) borrado de Docker", autoClose: true)
    }

    /// Cambiar la versión de PHP de un proyecto en Docker (solo su contenedor de PHP)
    func dockerSetPhp(_ p: DockerProject) {
        guard let k = docker, !busy, !k.php.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "¿Con qué versión de PHP quieres \(p.folder)?"
        alert.informativeText = "Solo cambia su contenedor de PHP: su BBDD y su configuración se quedan. La primera vez con cada versión se prepara su imagen. Si no arranca, vuelve a PHP \(p.php)."
        alert.addButton(withTitle: "Cambiar de PHP")
        alert.addButton(withTitle: "Cancelar")
        let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26), pullsDown: false)
        pop.addItems(withTitles: k.php.map { "PHP \($0)" + ($0 == p.php ? "  (ahora)" : "") })
        if let i = k.php.firstIndex(of: p.php) { pop.selectItem(at: i) }
        alert.accessoryView = pop
        guard alert.runStyled() == .alertFirstButtonReturn else { return }
        let i = pop.indexOfSelectedItem
        guard i >= 0 && i < k.php.count && k.php[i] != p.php else { return }
        let v = k.php[i]
        runTask("\(p.folder): PHP \(p.php) → \(v)", ["docker-php", p.slug, v],
                doneText: "\(p.folder) funciona ya con PHP \(v)", autoClose: true)
    }

    /// Los proyectos en Docker de antes de la 1.39.2 (PHP-FPM abierto en 127.0.0.1, sin clave) pasan a
    /// la web del contenedor con clave (docker-migrar --todos)
    func dockerMigrateAll() {
        guard confirm("¿Cerrar el PHP-FPM de los proyectos en Docker?",
                      "Estaba abierto en 127.0.0.1 sin clave: cualquier programa del Mac podía ejecutar PHP con él. Su web pasa al contenedor (Apache con PHP), con una clave que solo tiene el Apache del Mac. Sus BBDD, configuración y dominios se conservan. Pide la contraseña de administrador.",
                      "Cerrarlo") else { return }
        runTask("Cerrando el PHP-FPM de los proyectos en Docker", ["docker-migrar", "--todos"],
                doneText: "Proyectos en Docker con su clave", autoClose: true)
    }

    /// Rehace la imagen de PHP de un proyecto con la última de Docker Hub (parches de seguridad)
    func dockerUpdateImage(_ p: DockerProject) {
        let vs = p.isWeb ? p.versions.joined(separator: ", ") : p.php
        guard confirm("¿Actualizar la imagen de PHP \(vs)?",
                      "Se descarga otra vez la imagen oficial (php:<versión>-apache, con sus últimos parches), se rehace y se vuelve a crear el contenedor de PHP de \(p.folder). Su BBDD y su configuración no se tocan. Tarda unos minutos.",
                      "Actualizar la imagen") else { return }
        runTask("Actualizando la imagen de PHP \(vs)", ["docker-imagen", p.slug], progress: true,
                doneText: "\(p.folder) con la imagen nueva de PHP \(vs)")
    }

    /// Usuario y contraseña del phpMyAdmin de un proyecto (ya no entra solo como root)
    func dockerPassword(_ p: DockerProject) {
        runQuick(["docker-clave", p.slug]) { rc, out in
            guard rc == 0, let k = parseLines(out).first(where: { $0[0] == "K" && $0.count >= 4 }) else {
                message("No se encuentra la contraseña", String(out.suffix(400)), error: true)
                return
            }
            let pass = k[2]
            let r = runDialog(title: "phpMyAdmin de \(p.folder)",
                              text: "Usuario: \(k[1])\nContraseña: \(pass)\n\n\(k[3...].joined(separator: "|"))",
                              okLabel: "Copiar la contraseña", cancelLabel: "Cerrar")
            if r.ok {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pass, forType: .string)
                self.toast("Contraseña de \(p.folder) copiada")
            }
        }
    }

    /// phpMyAdmin de un proyecto en Docker (el visor): antes copia la contraseña de root, que pide
    func dockerOpenPma(_ p: DockerProject) {
        runQuick(["docker-clave", p.slug]) { rc, out in
            if rc == 0, let k = parseLines(out).first(where: { $0[0] == "K" && $0.count >= 4 }) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(k[2], forType: .string)
                self.toast(p.isWeb ? "Contraseña de root de la MariaDB \(p.maria) de Docker copiada: en phpMyAdmin, usuario root"
                           : "Contraseña de root de \(p.folder) copiada: en su phpMyAdmin, usuario root")
            }
            openURL(p.isWeb ? self.dockerPmaURL : "http://127.0.0.1:\(p.pma)/")
        }
    }

    /// Panel del WordPress o la tienda de un proyecto en Docker, por su dominio, con el administrador de
    /// pruebas en la BBDD del contenedor (docker-usuario-pruebas lo pone si falta: la copia no lo lleva)
    func dockerPanel(_ p: DockerProject, kind: String, admin: String) {
        openAdminLogin(kind: kind, admin: admin, site: dockerSite(p), name: p.folder,
                       command: ["docker-usuario-pruebas", p.slug])
    }

    /// Lo último del contenedor de la web de un proyecto en Docker (Apache con PHP: ahí van los errores
    /// de PHP de la web)
    func dockerWebLog(_ p: DockerProject, _ name: String) {
        runQuick(["docker-contenedor", "registros", name]) { rc, out in
            if rc != 0 && out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                message("No se han podido leer los registros de \(name)", "", error: true)
                return
            }
            let tail = out.components(separatedBy: "\n").suffix(400).joined(separator: "\n")
                .replacingOccurrences(of: "\\n", with: "\n    ")
            showLongText("PHP de \(p.folder)", tail.isEmpty ? "(vacío)" : tail,
                         subtitle: "Últimas líneas del contenedor \(name) (los errores de PHP de https://\(p.domain))",
                         toEnd: true)
        }
    }

    // MARK: Docker desde el proyecto cargado

    /// Botón Docker del proyecto cargado. Sin Docker Desktop en marcha, primero se abre (o se explica
    /// cómo instalarlo). Si el proyecto no está en Docker, se monta con la versión de PHP que se elija;
    /// si está con una, se arranca; con varias, se pregunta cuál (o se monta con otra)
    func dockerForLoaded(_ x: Project) {
        runQuick(["gui-docker"]) { _, out in
            self.onDocker(out)
            let k = self.docker ?? DockerData()
            let envs = self.dockerOf(x.name)
            if !k.ready || k.php.isEmpty {
                if !k.installed && !k.app {
                    self.dockerInstall()
                    return
                }
                guard confirm("Docker Desktop no está en marcha",
                              "Se abre Docker Desktop y, cuando responda, se sigue con \(x.name).",
                              "Abrir Docker Desktop") else { return }
                self.runTask("Abriendo Docker Desktop", ["docker-instalar"], progress: true, doneText: "Docker Desktop listo",
                             autoClose: true) { ok, _, _ in
                    if ok { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.dockerForLoaded(x) } }
                }
            } else if envs.isEmpty {
                self.dockerMountDialog(x)
            } else if envs.count == 1 {
                self.dockerMount(envs[0])
            } else {
                self.dockerChoose(x, envs)
            }
        }
    }

    /// Arranca un proyecto de Docker y lleva a la pestaña Docker
    func dockerMount(_ dp: DockerProject) {
        if dp.state == "marcha" {
            openTab("docker")
            toast("\(dp.folder) ya está en marcha en Docker: \(dockerSite(dp))")
            return
        }
        runTask("Arrancando \(dp.folder) en Docker (PHP \(dp.php))", ["docker-arrancar", dp.slug],
                doneText: "\(dp.folder) en Docker: \(dockerSite(dp))", autoClose: true) { ok, _, _ in
            if ok { self.openTab("docker") }
        }
    }

    /// El proyecto está en Docker con varias versiones de PHP: cuál se monta, u otra nueva
    func dockerChoose(_ x: Project, _ envs: [DockerProject]) {
        let list = envs.sorted { $0.php.compare($1.php, options: .numeric) == .orderedDescending }
        let alert = NSAlert()
        alert.messageText = "¿Qué versión de \(x.name) montas?"
        alert.addButton(withTitle: "Montar")
        alert.addButton(withTitle: "Cancelar")
        let group = RadioGroup()
        var options: [NSView] = []
        for (n, dp) in list.enumerated() {
            let b = NSButton(radioButtonWithTitle: "PHP \(dp.php)  ·  \(dp.domain)" + (dp.state == "marcha" ? "  ·  en marcha" : ""),
                             target: group, action: #selector(RadioGroup.pick(_:)))
            b.state = n == 0 ? .on : .off
            group.buttons.append(b)
            options.append(b)
        }
        let other = NSButton(radioButtonWithTitle: "Otra versión de PHP…", target: group, action: #selector(RadioGroup.pick(_:)))
        other.state = .off
        group.buttons.append(other)
        options.append(other)
        alert.accessoryView = dialogStack([dialogLabel("Está en Docker con varias versiones de PHP.", color: .secondaryLabelColor),
                                           dialogOptions(options)], spacing: 14)
        guard alert.runStyled() == .alertFirstButtonReturn else { return }
        let i = group.buttons.firstIndex(where: { $0.state == .on }) ?? 0
        if i < list.count {
            dockerMount(list[i])
        } else if let w = envs.first(where: { $0.isWeb }) {
            dockerVersions(w)
        } else {
            dockerMountDialog(x)
        }
    }

    /// «Montar <proyecto> en Docker»: PHP (la rama de la versión activa), MariaDB (la de la activa,
    /// si se ofrece), la BBDD que se copia (la del proyecto en la activa) y el dominio. Si la carpeta
    /// ya está en Docker, el nuevo va con otro nombre (<carpeta>-php84)
    func dockerMountDialog(_ x: Project) {
        guard let k = docker, !k.php.isEmpty, !k.maria.isEmpty, !busy else { return }
        let d = data ?? AppData()
        let act = d.installs.first(where: { $0.folder == d.active })
        let phpNow = act.map { shortPhp($0.php) } ?? ""
        let mariaNow = act?.mariadb ?? ""
        let pairs = projectPairs(x)
        let alert = NSAlert()
        alert.messageText = "Montar \(x.name) en Docker"
        alert.addButton(withTitle: "Montar en Docker")
        alert.addButton(withTitle: "Cancelar")
        // (ancho del nombre más largo: la BBDD con su versión, entera)
        let width = fitWidth(pairs.map { "\($0.1) (XAMPP-\($0.0.folder))" }, min: 300, max: 520)
        func popup(_ items: [String], _ selected: Int) -> NSPopUpButton {
            let b = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: width, height: 26), pullsDown: false)
            b.addItems(withTitles: items)
            if selected >= 0 && selected < items.count { b.selectItem(at: selected) }
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: width).isActive = true
            return b
        }
        func line(_ title: String, _ view: NSView) -> NSView {
            let t = NSTextField(labelWithString: title)
            t.textColor = .secondaryLabelColor
            t.translatesAutoresizingMaskIntoConstraints = false
            t.widthAnchor.constraint(equalToConstant: 140).isActive = true
            let row = NSStackView(views: [t, view])
            row.orientation = .horizontal
            row.spacing = 10
            return row
        }
        let phpPop = popup(k.php.map { "PHP \($0)" }, k.php.firstIndex(of: phpNow) ?? 0)
        let mariaPop = popup(k.maria.map { "MariaDB \($0)" },
                             k.maria.firstIndex(where: { mariaNow == $0 || mariaNow.hasPrefix($0 + ".") }) ?? 0)
        var sources: [(String, String)] = [("", "Ninguna: empieza vacía")]
        sources += pairs.map { ("\($0.0.folder)|\($0.1)", "\($0.1) (XAMPP-\($0.0.folder))") }
        let srcSel = sources.firstIndex(where: { !d.active.isEmpty && $0.0.hasPrefix(d.active + "|") }) ?? (sources.count - 1)
        let srcPop = popup(sources.map { $0.1 }, srcSel)
        let wp = x.kind == "wp"
        let modePop = popup(["En vivo: la misma que web.local (sin copias)", "Una copia en Docker"], 0)
        alert.accessoryView = dialogStack([
            dialogLabel("Con el Apache de Docker (sin XAMPP-X). Se descargan las imágenes que falten y se abre por su dominio (\(dockerSlug(x.name)).\(dockerTLD(k))). La carpeta y sus BBDD de XAMPP-X no se tocan.",
                        color: .secondaryLabelColor),
            line("PHP", phpPop), line("MariaDB", mariaPop), line(wp ? "BBDD" : "BBDD que se copia", srcPop),
        ] + (wp ? [line("Cómo", modePop)] : []), spacing: 10)
        guard alert.runStyled() == .alertFirstButtonReturn else { return }
        let pi = phpPop.indexOfSelectedItem, mi = mariaPop.indexOfSelectedItem, si = srcPop.indexOfSelectedItem
        guard pi >= 0, pi < k.php.count, mi >= 0, mi < k.maria.count else { return }
        var args = ["docker-nuevo", x.name, k.php[pi], k.maria[mi]]
        if si > 0, si < sources.count {
            let src = sources[si].0.split(separator: "|", maxSplits: 1).map(String.init)
            if src.count == 2 { args += ["--bd", src[1], "--desde", src[0]] + (wp && modePop.indexOfSelectedItem == 0 ? ["--en-vivo"] : []) }
        }
        runTask("Montando \(x.name) en Docker", args, progress: true, doneText: "\(x.name) en Docker") { ok, _, _ in
            self.reloadDocker()
            if ok { self.openTab("docker") }
        }
    }

    /// Acción sobre un contenedor suelto de un proyecto en Docker
    func containerAction(_ c: DockerContainer, _ action: String) {
        if action == "parar" && !stopSharedOK([c.name], c.name) { return }
        if action == "borrar" {
            guard confirm("¿Eliminar el contenedor \(c.name)?",
                          "Al arrancar el proyecto se vuelve a crear; los datos de la BBDD siguen en su volumen. Para quitar el proyecto entero, usa la papelera de su fila.",
                          "Eliminar el contenedor", destructive: true) else { return }
        }
        let titles = ["arrancar": "Arrancando", "parar": "Parando", "reiniciar": "Reiniciando",
                      "registros": "Registros de", "borrar": "Eliminando"]
        runTask("\(titles[action] ?? action) \(c.name)", ["docker-contenedor", action, c.name],
                autoClose: action != "registros")
    }

    /// Volver a descargar una imagen de Docker Hub (las nexum-* del gestor se rehacen con «Actualizar
    /// imagen» de su proyecto)
    func imagePull(_ i: DockerImage) {
        guard i.tagged, !i.repo.hasPrefix("nexum-") else { return }
        runTask("Descargando \(i.name)", ["docker-imagenes", "descargar", i.name], doneText: "\(i.name) descargada")
    }

    /// Borrar una imagen (sin -f: si la usa un contenedor, Docker no la borra)
    func imageDelete(_ i: DockerImage) {
        // (sin etiqueta, por su ID)
        let ref = i.tagged || i.cid.isEmpty ? i.name : i.cid
        guard confirm("¿Borrar la imagen \(ref)?",
                      "Ocupa \(i.size). Si hace falta, se vuelve a descargar o a preparar.",
                      "Borrar la imagen", destructive: true) else { return }
        runTask("Borrando \(ref)", ["docker-imagenes", "borrar", ref], doneText: "Imagen borrada", autoClose: true)
    }

    func volumeDelete(_ v: DockerVolume) {
        guard confirm("¿Borrar el volumen \(v.name)?", "Se pierden sus datos. No se puede deshacer.",
                      "Borrar el volumen", destructive: true) else { return }
        runTask("Borrando \(v.name)", ["docker-volumen-borrar", v.name], doneText: "Volumen borrado", autoClose: true)
    }
}
