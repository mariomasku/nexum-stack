extension AppModel {
    // MARK: bases de datos (siempre en la version activa)

    func dbEnv() -> [String: String] {
        if let d = data, let pwd = dbPwd[d.active] { return ["MYSQL_PWD": pwd] }
        return [:]
    }

    /// Comprueba que se puede entrar en el MariaDB activo; si root tiene contraseña la pide
    func checkDbAccess(_ then: @escaping () -> Void) {
        guard let d = data else { return }
        let folder = d.active
        runQuick(["gui-bd-comprobar"], env: dbEnv()) { _, out in
            let last = out.components(separatedBy: "\n").filter { !$0.isEmpty }.last ?? "no|Sin respuesta del instalador"
            let res = last.components(separatedBy: "|")
            switch res[0] {
            case "ok":
                then()
            case "clave":
                let retry = self.dbPwd[folder] != nil
                let r = runDialog(title: "Contraseña de MariaDB",
                                  text: "root del MariaDB de XAMPP-\(folder) tiene contraseña: escríbela para seguir."
                                      + (retry ? "\n\nContraseña incorrecta. Vuelve a intentarlo." : ""),
                                  okLabel: "Entrar en MariaDB", hasField: true, secure: true)
                if r.ok {
                    self.dbPwd[folder] = r.text
                    self.checkDbAccess(then)
                }
            default:
                message("No se puede usar la BBDD", res.dropFirst().joined(separator: "|"), error: true)
            }
        }
    }

    func createDb() {
        checkDbAccess { self.askNewDb() }
    }

    private func askNewDb() {
        guard let d = data else { return }
        let existing = d.dbs[d.active] ?? []
        let hint = "Letras sin acentos, números, _ y -"
        let r = runDialog(title: "Crear BBDD",
                          text: "Se crea vacía en XAMPP-\(d.active) (utf8mb4_general_ci).",
                          okLabel: "Crear la BBDD", hasField: true, fieldLabel: hint, placeholder: "nombre_de_la_base",
                          validate: { _, typed in
                              let name = typed.trimmingCharacters(in: .whitespaces)
                              if existing.contains(name) || SYSTEM_DBS.contains(name.lowercased()) {
                                  return (false, "Ya hay una BBDD con ese nombre.", true)
                              }
                              let valid = validDbName(name)
                              return (valid, hint, !valid && !name.isEmpty)
                          })
        if !r.ok { return }
        let name = r.text
        runQuick(["crear-bd", name], env: dbEnv()) { rc, out in
            if rc == 0 {
                self.impDb = name
                self.toast("BBDD «\(name)» creada")
                self.reload()
            } else {
                message("No se ha podido crear la BBDD", String(out.suffix(600)), error: true)
            }
        }
    }

    func dropDb(_ db: String) {
        checkDbAccess {
            runQuick(["gui-bd-info", db], env: self.dbEnv()) { rc, out in
                guard rc == 0, let info = parseLines(out).first(where: { $0[0] == "I" && $0.count >= 3 }) else {
                    message("No se puede borrar la BBDD", String(out.suffix(600)), error: true)
                    return
                }
                self.confirmDrop(db, Int(info[1]) ?? 0, Int64(info[2]) ?? 0)
            }
        }
    }

    private func confirmDrop(_ db: String, _ tables: Int, _ size: Int64) {
        let folder = data?.active ?? ""
        var copy = false
        if tables > 0 {
            let r = runDialog(title: "¿Borrar la BBDD «\(db)»?",
                              text: "Está en XAMPP-\(folder) y tiene \(plural(tables, "tabla", "tablas")) (\(fmtSize(size))). Se borra todo su contenido y no se puede deshacer.",
                              okLabel: "Borrar la BBDD", style: .critical, destructive: true,
                              checkbox: "Guardar antes una copia en ~/lvm-copias (se puede volver a cargar)", checked: true,
                              hasField: true,
                              fieldLabel: "Sin copia, el contenido no se podrá recuperar. Escribe \(db) para confirmar:",
                              validate: { checked, typed in (checked || typed.trimmingCharacters(in: .whitespaces) == db, nil, false) })
            if !r.ok { return }
            copy = r.checked
        } else {
            if !confirm("¿Borrar la BBDD «\(db)»?",
                        "Está en XAMPP-\(folder) y está vacía (sin tablas). No se puede deshacer.",
                        "Borrar la BBDD", destructive: true) { return }
        }
        runTask("Borrando la BBDD \(db)", ["borrar-bd", db] + (copy ? ["--copia"] : []),
                doneText: "BBDD «\(db)» borrada" + (copy ? " (copia en ~/lvm-copias)" : ""),
                autoClose: true, env: dbEnv()) { ok, _, _ in
            if ok && self.impDb == db {
                self.impDb = nil
            }
        }
    }

    func pickSql() {
        let panel = NSOpenPanel()
        panel.title = "Elegir el fichero SQL"
        panel.prompt = "Elegir"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = fileTypes(["sql", "gz", "zip"])
        if let f = impFile {
            panel.directoryURL = URL(fileURLWithPath: f).deletingLastPathComponent()
        } else {
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        }
        if panel.runModal() != .OK { return }
        guard let url = panel.url else { return }
        impFile = url.path
        // Si hay una base que se llama como el fichero (mi_web.sql -> mi_web), se propone
        var stem = url.lastPathComponent
        for ext in [".zip", ".ZIP", ".gz", ".GZ", ".sql", ".SQL"] where stem.hasSuffix(ext) { stem = String(stem.dropLast(ext.count)) }
        if impDb == nil, let d = data, (d.dbs[d.active] ?? []).contains(stem) { impDb = stem }
    }

    /// Carpetas de htdocs para el formulario y, si se sabe, la del proyecto de la base elegida (la
    /// recordada o la única cuya configuración la usa)
    func refreshImpProjects() {
        let db = impDb
        runQuick(["gui-proyectos"]) { rc, out in
            var names: [String] = []
            var kind: [String: String] = [:]
            var users: [String] = []
            var saved: String? = nil
            for f in parseLines(out) {
                if f[0] == "P" && f.count >= 4 {
                    names.append(f[1])
                    if f.count >= 5 && !f[4].isEmpty { kind[f[1]] = f[4] }
                    if let d = db, f[2] == d { users.append(f[1]) }
                } else if f[0] == "R" && f.count >= 3, let d = db, f[1] == d {
                    saved = f[2]
                }
            }
            guard rc == 0 else { return }
            self.impProjects = names
            self.impKind = kind
            if let s = saved, names.contains(s) {
                self.impProject = s
            } else if users.count == 1 {
                self.impProject = users[0]
            } else if let d = db, let m = self.nameMatchProject(d, names, kind) {
                self.impProject = m
            } else if let p = self.impProject, !names.contains(p) {
                self.impProject = nil
            }
        }
    }

    /// Carpeta que se llama como la base: wp_ajoselpajizo → dob-wordpress-ajoselpajizo (la base sin
    /// wp_ ni ps_, al final del nombre). Si hay varias, la del mismo tipo (WordPress o tienda)
    func nameMatchProject(_ db: String, _ folders: [String], _ kind: [String: String]) -> String? {
        let low = db.lowercased()
        let pre = String(low.prefix(3))
        var tails: Set<String> = [low]
        if (pre == "wp_" || pre == "ps_") && low.count > 3 { tails.insert(String(low.dropFirst(3))) }
        var hits = folders.filter { f in
            let n = f.lowercased()
            return tails.contains { v in n == v || n.hasSuffix("-" + v) || n.hasSuffix("." + v) || n.hasSuffix("_" + v) }
        }
        if hits.count > 1 && (pre == "wp_" || pre == "ps_") {
            let same = hits.filter { kind[$0] == String(pre.prefix(2)) }
            if !same.isEmpty { hits = same }
        }
        return hits.count == 1 ? hits[0] : nil
    }

    /// Ancho del desplegable de Proyecto: el del nombre más largo, para verlo entero al elegirlo
    func importProjectWidth() -> CGFloat {
        let longest = impProjects.map { $0.count }.max() ?? 0
        return max(230, min(440, CGFloat(longest) * 7.5 + 50))
    }

    func importProjectHint() -> String {
        guard let p = impProject else { return "Opcional: si es la BBDD nueva de un proyecto, elige su carpeta." }
        if let what = projectConfigText(p) { return what.prefix(1).uppercased() + String(what.dropFirst()) + "." }
        return "La BBDD queda asociada a esta carpeta (Cargar proyecto la usa)."
    }

    /// Lo que se hace con la configuración del proyecto al subirle una base nueva
    func projectConfigText(_ folder: String) -> String? {
        switch impKind[folder] {
        case "wp": return "su wp-config.php se rehace con la plantilla de este equipo para usar esta BBDD"
        case "ps": return "su parameters.php (o settings.inc.php) pasa a usar esta BBDD y se vacía su caché"
        default: return nil
        }
    }

    func importHint() -> String? {
        guard let d = data else { return nil }
        if !d.running { return "La versión activa está parada: arráncala con el botón de arriba (Parados)." }
        if impFile == nil { return "Elige el fichero SQL." }
        if impDb == nil { return "Elige la BBDD de destino o crea una con +." }
        return nil
    }

    func importDb() {
        guard let d = data, let path = impFile, let db = impDb else { return }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber else {
            message("No se encuentra el fichero", path, error: true)
            return
        }
        let name = (path as NSString).lastPathComponent
        var text = "Se carga en XAMPP-\(d.active). Antes se BORRAN todas las tablas de «\(db)» (si tiene alguna, con una copia en ~/lvm-copias)."
        let project = impProject
        if let p = project {
            text += "\n\nDespués, «\(db)» pasa a ser la BBDD de \(p)" + (projectConfigText(p).map { ": \($0)" } ?? "") + "."
        }
        if !confirm("¿Cargar \(name) (\(fmtSize(size.int64Value))) en \(db)?", text,
                    "Vaciar y cargar", destructive: true) { return }
        checkDbAccess {
            self.runTask("Cargando \(name) en \(db)",
                         ["importar-bd", path, db] + (project.map { ["--proyecto", $0] } ?? []),
                         progress: true, doneText: "BBDD «\(db)» cargada" + (project.map { " en \($0)" } ?? ""),
                         env: self.dbEnv(),
                         cancelText: ("¿Cancelar la carga?",
                                      "«\(db)» se queda a medias, con lo cargado hasta ahora.",
                                      "Cancelar la carga")) { ok, _, _ in
                if ok {
                    self.impFile = nil
                }
            }
        }
    }

    // MARK: menu

    // MARK: cargar el proyecto de una base

    func openProject(_ db: String, _ inst: Install) {
        runQuick(["gui-proyectos"]) { rc, out in
            var link = "", current = ""
            var create = false
            var projects: [Project] = []
            var saved: [String: String] = [:]
            for f in parseLines(out) {
                switch f[0] {
                case "E" where f.count >= 3:
                    link = f[1]
                    current = f[2]
                    create = f.count >= 4 && f[3] == "N"
                case "P" where f.count >= 4:
                    projects.append(Project(name: f[1], db: f[2], php: f[3]))
                case "R" where f.count >= 3:
                    saved[f[1]] = f[2]
                case "V" where f.count >= 4 && f[1] == db && f[2] == inst.folder:
                    // (el vínculo de la versión manda sobre el de todas; "" = desvinculada en ella.
                    // gui-proyectos saca las V después de las R)
                    saved[db] = f[3...].joined(separator: "|")
                default:
                    break
                }
            }
            if rc != 0 || projects.isEmpty {
                message("No se han podido leer los proyectos",
                        "No se ha podido leer la carpeta \(HTDOCS).", error: true)
            } else if link.isEmpty {
                message("No hay un vhost para cargar proyectos",
                        "Ningún vhost compartido tiene como DocumentRoot un enlace de htdocs (como web.local).",
                        error: true)
            } else {
                let req = ProjectRequest(db: db, inst: inst, link: link, current: current, create: create,
                                         projects: projects, saved: saved)
                let matches = projects.filter { $0.db == db }.map { $0.name }
                // Carpeta conocida (elegida antes o la unica que usa la base): se carga sin preguntar
                if let s = saved[db], projects.contains(where: { $0.name == s }) {
                    self.loadProject(req, folder: s, version: inst.folder, manual: false)
                } else if matches.count == 1 && saved[db] != "" {
                    self.loadProject(req, folder: matches[0], version: inst.folder, manual: false)
                } else {
                    self.projectReq = req
                }
            }
        }
    }

    /// Guarda en ~/.lvm-instalador/proyectos la carpeta elegida a mano para una base en una versión
    func rememberProject(_ db: String, _ folder: String, _ version: String) {
        if SIMULATE { return }
        if let err = writeLinks([(db, version, folder)]) {
            toast("No se ha podido recordar la carpeta: \(err)")
        }
    }

    /// Elige con qué BBDD va la carpeta en cada versión (o con ninguna): Cargar proyecto monta la
    /// versión con esa BBDD. Cada BBDD es de un solo proyecto en cada versión
    func linkProject(_ x: Project) {
        let d = data ?? AppData()
        let installs = d.installs.sorted { $0.php.compare($1.php, options: .numeric) == .orderedDescending }
        guard !installs.isEmpty else { return }
        let pairs = projectPairs(x)
        let alert = NSAlert()
        alert.messageText = "BBDD de \(x.name) en cada versión"
        alert.addButton(withTitle: "Guardar los vínculos")
        alert.addButton(withTitle: "Cancelar")
        var views: [NSView] = [dialogLabel("Cargar proyecto monta cada versión con la BBDD que elijas. «Ninguna»: la carpeta deja de ir con esa versión (la BBDD no se toca). Cada BBDD es de un solo proyecto por versión.", color: .secondaryLabelColor)]
        var popups: [(Install, NSPopUpButton, [String], [String])] = []
        for i in installs {
            let dbs = (d.dbs[i.folder] ?? []).sorted { $0.lowercased() < $1.lowercased() }
            let mine = pairs.filter { $0.0.folder == i.folder }.map { $0.1 }
            let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
            pop.addItem(withTitle: "— Ninguna —")
            for db in dbs {
                let other = linkOf(db, i.folder)
                pop.addItem(withTitle: other == nil || other == "" || other == x.name ? db : "\(db)  (de \(other!))")
            }
            if let m = mine.first, let n = dbs.firstIndex(of: m) { pop.selectItem(at: n + 1) } else { pop.selectItem(at: 0) }
            pop.isEnabled = !dbs.isEmpty
            let title = NSTextField(labelWithString: "PHP \(i.php)  (XAMPP-\(i.folder))")
            title.translatesAutoresizingMaskIntoConstraints = false
            title.widthAnchor.constraint(equalToConstant: 190).isActive = true
            let row = NSStackView(views: [title, pop])
            row.orientation = .horizontal
            row.spacing = 10
            views.append(row)
            popups.append((i, pop, dbs, mine))
        }
        alert.accessoryView = dialogStack(views, spacing: 10)
        guard alert.runStyled() == .alertFirstButtonReturn else { return }
        var changes: [(String, String, String)] = []
        for (i, pop, dbs, mine) in popups {
            let idx = pop.indexOfSelectedItem
            let new = idx >= 1 && idx <= dbs.count ? dbs[idx - 1] : ""
            for db in mine where db != new { changes.append((db, i.folder, "")) }
            // (también la que solo venía de su configuración: así queda fija)
            if !new.isEmpty && linkOf(new, i.folder) != x.name { changes.append((new, i.folder, x.name)) }
        }
        if changes.isEmpty { return }
        if SIMULATE { toast("[simulación] no se cambian los vínculos"); return }
        if let err = writeLinks(changes) {
            message("No se han podido guardar los vínculos", err, error: true)
            return
        }
        toast("Vínculos de \(x.name) guardados")
        reloadProjects()
    }

    /// Carga el proyecto en la versión del resultado pulsado. Solo pregunta si hay que cambiar de
    /// versión de PHP o crear el vhost
    func loadProject(_ req: ProjectRequest, folder: String, version: String, manual: Bool,
                     confirmSwitch: Bool = true) {
        let php = data?.installs.first(where: { $0.folder == version })?.php ?? req.inst.php
        let wasSheet = projectReq != nil
        projectReq = nil
        // Se espera a que se cierre la hoja antes de abrir la de la tarea
        DispatchQueue.main.asyncAfter(deadline: .now() + (wasSheet ? 0.4 : 0)) {
            let d = self.data ?? AppData()
            var notes: [String] = []
            let place = !req.db.isEmpty && (d.dbs[version] ?? []).contains(req.db) ? ", donde está la BBDD \(req.db)" : ""
            if version != d.active && confirmSwitch {
                if let act = d.installs.first(where: { $0.folder == d.active }) {
                    notes.append("Se va a cambiar de versión de PHP: se para XAMPP-\(act.folder) (PHP \(act.php)) y se activa XAMPP-\(version) (PHP \(php))\(place).")
                } else {
                    notes.append("Se activa XAMPP-\(version) (PHP \(php))\(place).")
                }
            }
            if req.create {
                notes.append("Todavía no hay un vhost para cargar proyectos: se crea \(req.link) (http y https, con su certificado y sus líneas en /etc/hosts).")
            }
            let st = d.php2shell[version] ?? "ok"
            if version != d.active && php2shellVulnerable(st) {
                notes.append("Ojo: " + php2shellText(st, php))
            }
            if !notes.isEmpty {
                let title = version != d.active && confirmSwitch ? "¿Cambiar a PHP \(php)?" : "¿Crear \(req.link)?"
                if !confirm(title, "Se pide la contraseña de administrador.", "Cargar proyecto",
                            steps: notes + ["\(req.link) apuntará a \(folder)."]) { return }
            }
            if manual { self.rememberProject(req.db, folder, version) }
            var env: [String: String] = [:]
            if let pwd = self.dbPwd[version] { env["MYSQL_PWD"] = pwd }
            self.runTask("Cargando el proyecto \(folder)", ["cargar-proyecto", folder, version, req.db],
                         doneText: "\(req.link) apunta a \(folder) (PHP \(php))", autoClose: true, env: env) { ok, _, _ in
                guard ok else { return }
                // El visor pasa al proyecto nuevo al momento, con sus botones: lo que se acaba de hacer
                // se sabe sin preguntarlo (gui-datos tarda unos segundos; la lectura completa sigue detrás)
                self.projects?.link = req.link
                self.projects?.current = folder
                self.projects?.create = false
                // (la página sube sola hasta el visor, arriba: sin desplazarla a mano)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.scrollTop += 1 }
                if let a = self.data?.active, a != version { self.data?.active = version }
                // Tienda PrestaShop: su dominio queda falseado (se ve en la pestaña Hosts)
                runQuick(["gui-hosts"]) { rc, out in
                    self.onHosts(rc, out)
                    let fake = (self.hosts ?? []).first { $0.folder == folder && $0.fake }
                    self.toast("Proyecto cargado: \(req.link) → \(folder) (PHP \(php))"
                               + (fake.map { "  ·  \($0.name) falseado (Dominios y hosts)" } ?? ""))
                }
            }
        }
    }

    /// Descarga una copia .zip de una base de cualquier versión (exportar-bd). Si no es la activa en
    /// marcha, el script arranca un MariaDB temporal y pide la contraseña de administrador
    /// Desmonta el proyecto cargado: el vhost (web.local) deja de apuntar a él y enseña una página vacía
    func unloadProject() {
        guard let p = projects, !p.current.isEmpty else { return }
        let name = (p.current as NSString).lastPathComponent
        runTask("Desmontando el proyecto \(name)", ["desmontar-proyecto"],
                doneText: "\(p.link) ya no apunta a \(name)", autoClose: true)
    }

    /// Abre (vacío) o cierra el asistente de Montar nuevo proyecto
    func newProject(_ show: Bool) {
        if show {
            npUrl = ""
            npFolder = ""
            npFolderAuto = true
            npVersion = data?.active ?? ""
            npDb = ""
            npFile = nil
            npStep = 1
            projQuery = ""
            npRepoQuery = ""
            npRepoNote = ""
            npFake = false
            npDomain = ""
            // (la lista ya está en memoria: loadNpRepos, al abrir el programa. Si hace rato que no se
            // pregunta a GitHub, se pone al día por detrás)
            showNpReposNote()
            if !npReposLoaded { loadNpRepos(cache: true) }
            if Date().timeIntervalSince(npReposWhen) > NP_REPOS_FRESH { loadNpRepos() }
        }
        npOpen = show
    }

    /// Los repositorios para el buscador de Nuevo proyecto, en segundo plano: los de la última vez (cache:
    /// al momento) o los de GitHub. Sin conexión, se queda la lista que había
    func loadNpRepos(cache: Bool = false) {
        if cache && npReposWhen != .distantPast { return }
        if !cache {
            if npReposBusy { return }
            npReposBusy = true
        }
        runQuick(["repos", "--todos"] + (cache ? ["--cache"] : [])) { _, out in
            let rows = parseRepos(out).items
            if !cache {
                self.npReposBusy = false
                if !rows.isEmpty { self.npReposWhen = Date() }
            }
            // (una respuesta de la última vez que llega tarde no pisa la de GitHub)
            if !rows.isEmpty && !(cache && self.npReposWhen != .distantPast) { self.npRepos = rows }
            self.npReposLoaded = true
            self.showNpReposNote()
        }
    }

    /// Debajo del buscador, cuántos hay (con uno ya elegido, sigue lo que se va a clonar)
    func showNpReposNote() {
        if !npReposLoaded || !npUrl.isEmpty { return }
        npRepoNote = npRepos.isEmpty ? "Sin la lista de GitHub (conéctalo en Configuración, GitHub): escribe la dirección abajo"
            : "\(npRepos.count) repositorios de GitHub"
    }
}
