extension AppModel {
    // MARK: actualizaciones

    /// Busca una versión nueva: en GitHub (firmada; se instala desde aquí y la ventana se vuelve a
    /// abrir) o, si no se puede, un .dmg más nuevo en Descargas (se abre para ejecutar su instalador)
    /// Buscar una versión nueva (menú) o, con auto, al abrir la ventana (updateCheckDue): sin avisar si
    /// no hay y solo la firmada de GitHub. Si se dice que no, se vuelve a ofrecer la próxima vez que toque
    func checkUpdates(auto: Bool = false) {
        if !auto { toast("Buscando actualizaciones…") }
        runQuick(["gui-paquete"]) { _, out in
            let current = self.data?.version ?? ""
            let lines = parseLines(out)
            let notes = lines.filter { $0[0] == "I" && $0.count >= 2 }.map { $0[1...].joined(separator: "|") }
            if let u = lines.first(where: { $0[0] == "U" && $0.count >= 5 }) {
                let path = u[4...].joined(separator: "|")
                guard confirm("Hay una versión nueva de Nexum Dev Stack",
                              "Tienes la \(current); en GitHub está la \(u[1]) (\(u[2])), firmada por quien hace el programa. Huella SHA-256:\n\(u[3])\n\nSe cambia el gestor y la ventana se vuelve a abrir. Tus versiones de PHP, proyectos y BBDD no se tocan.",
                              "Actualizar a la \(u[1])") else { return }
                self.runTask("Actualizando Nexum Dev Stack a la \(u[1])", ["actualizar-gestor", path], progress: true,
                             doneText: "Instalada la \(u[1])", autoClose: true) { ok, _, _ in
                    if !ok { self.toast("No se ha actualizado"); return }
                    if !SIMULATE { relaunchApp() }
                }
                return
            }
            // (al abrir, solo la firmada de GitHub: la de Descargas, sin firma, solo desde el menú)
            if auto { return }
            guard let f = lines.first(where: { $0[0] == "N" && $0.count >= 5 }) else {
                if notes.isEmpty {
                    self.toast("Tienes la última versión (\(current))")
                } else {
                    message("No hay ninguna versión nueva para instalar desde aquí",
                            "Tienes la \(current).\n\n" + notes.joined(separator: "\n\n"))
                }
                return
            }
            let path = f[4...].joined(separator: "|")
            let origin = lines.first(where: { $0[0] == "O" && $0.count >= 2 })
                .map { $0[1...].joined(separator: "|") } ?? "desconocido"
            guard confirm("Hay una versión nueva de Nexum Dev Stack en Descargas",
                          "Tienes la \(current); en Descargas está la \(f[1]) (\((path as NSString).lastPathComponent), del \(f[2]), de \(origin)).\n\nNo lleva firma: ábrela solo si te la ha pasado quien hace el programa y su huella SHA-256 es esta:\n\(f[3])\n\nSe abre el .dmg para ejecutar su instalador. Tus versiones de PHP, proyectos y BBDD no se tocan.",
                          "Abrir el instalador") else { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    // MARK: cargar un proyecto (Versiones)

    func reloadProjects() {
        runQuick(["gui-proyectos"]) { rc, out in self.onProjects(rc, out) }
    }

    func onProjects(_ rc: Int32, _ out: String) {
        var p = ProjectsData()
        for f in parseLines(out) {
            switch f[0] {
            case "E" where f.count >= 3:
                p.link = f[1]
                p.current = f[2]
                p.create = f.count >= 4 && f[3] == "N"
            case "P" where f.count >= 4:
                p.list.append(Project(name: f[1], db: f[2], php: f[3], kind: field(f, 4)))
            case "R" where f.count >= 3:
                p.saved[f[1]] = f[2...].joined(separator: "|")
            case "V" where f.count >= 4:
                p.vlinks[f[1] + "@" + f[2]] = f[3...].joined(separator: "|")
            default:
                break
            }
        }
        let next: ProjectsData? = (rc != 0 && p.list.isEmpty) ? nil : p
        if next != projects { projects = next }
    }

    /// Carpeta vinculada a una BBDD en una versión: la de esa versión ("" = ninguna), la de todas
    /// las versiones (como se guardaba hasta la 1.36) o nil si no tiene
    func linkOf(_ db: String, _ ver: String) -> String? {
        let p = projects ?? ProjectsData()
        if let v = p.vlinks[db + "@" + ver] { return v }
        return p.saved[db]
    }

    /// (versión, BBDD) de un proyecto: las BBDD vinculadas a su carpeta en cada versión o, si no
    /// tiene ninguna, la de su configuración en las versiones donde no es de otro proyecto
    func projectPairs(_ x: Project) -> [(Install, String)] {
        let d = data ?? AppData()
        var pairs: [(Install, String)] = []
        for i in d.installs {
            for db in d.dbs[i.folder] ?? [] where linkOf(db, i.folder) == x.name { pairs.append((i, db)) }
        }
        if !pairs.isEmpty || x.db.isEmpty { return pairs }
        return d.installs.filter { (d.dbs[$0.folder] ?? []).contains(x.db) && linkOf(x.db, $0.folder) == nil }
            .map { ($0, x.db) }
    }

    /// Proyecto cargado (al que apunta el vhost), o nil
    func loadedEntry() -> Project? {
        guard let p = projects, !p.current.isEmpty else { return nil }
        let name = (p.current as NSString).lastPathComponent
        return p.list.first { $0.name == name }
    }

    /// BBDD que usa el proyecto cargado en la versión activa (vacío si no hay)
    func loadedProjectDb() -> String {
        guard let x = loadedEntry() else { return "" }
        return cleanDbName(loadedDb(x))
    }

    /// BBDD del proyecto en la versión activa (la vinculada o la de su configuración)
    func loadedDb(_ x: Project) -> String {
        let pairs = projectPairs(x)
        if let p = pairs.first(where: { $0.0.folder == data?.active }) { return p.1 }
        return pairs.first?.1 ?? projectBase(x)
    }

    /// Base de un proyecto que no está en ninguna versión (para los textos): la recordada para su
    /// carpeta o la de su configuración
    func projectBase(_ x: Project) -> String {
        if let first = projectPairs(x).first { return first.1 }
        let d = data ?? AppData()
        let all = Set(d.installs.flatMap { d.dbs[$0.folder] ?? [] })
        let saved = (projects?.saved ?? [:]).filter { $0.value == x.name }.map { $0.key }.sorted()
        if let s = saved.first(where: { all.contains($0) }) { return s }
        return x.db.isEmpty ? (saved.first ?? "") : x.db
    }

    /// Carga la carpeta de un proyecto en la versión donde está su base. Si está en varias (o en
    /// ninguna), pregunta cuál montar
    func loadFolder(_ x: Project) {
        guard let p = projects, !p.link.isEmpty else {
            message("No hay un vhost para cargar proyectos",
                    "Ningún vhost compartido tiene como DocumentRoot un enlace de htdocs (como web.local).",
                    error: true)
            return
        }
        let d = data ?? AppData()
        var db = projectBase(x)
        var cands = projectPairs(x)
        let found = !cands.isEmpty
        if cands.isEmpty { cands = d.installs.map { ($0, db) } }
        guard !cands.isEmpty else {
            message("No hay ninguna versión instalada", "Instala una versión de PHP en Versiones de PHP para cargar proyectos.", error: true)
            return
        }
        var inst = cands[0].0
        db = cands[0].1
        if cands.count > 1 {
            guard let chosen = askVersion(x, db, cands, found) else { return }
            inst = chosen.0
            db = chosen.1
        }
        let req = ProjectRequest(db: db, inst: inst, link: p.link, current: p.current, create: p.create,
                                 projects: p.list, saved: p.saved)
        loadProject(req, folder: x.name, version: inst.folder, manual: false, confirmSwitch: cands.count == 1)
    }

    /// Versión de PHP (y su BBDD) en la que se carga un proyecto, cuando puede ir en varias (nil si
    /// se cancela)
    func askVersion(_ x: Project, _ db: String, _ cands: [(Install, String)], _ found: Bool) -> (Install, String)? {
        let active = data?.active ?? ""
        let pre = cands.firstIndex(where: { $0.0.folder == active })
            ?? cands.firstIndex(where: { !x.php.isEmpty && $0.0.php.hasPrefix(x.php) }) ?? 0
        let alert = NSAlert()
        alert.messageText = found ? "¿Qué versión del proyecto y de PHP quieres?"
            : "¿Con qué versión de PHP quieres cargar el proyecto?"
        let why: String
        if found {
            why = "\(x.name) tiene BBDD en \(cands.count) versiones de PHP, cada una con su copia. Elige cuál cargar:"
        } else if !db.isEmpty {
            why = "Su BBDD (\(db)) no está en ninguna versión: súbela después en Bases de datos. Elige la versión de PHP:"
        } else {
            why = "No se sabe qué BBDD usa \(x.name). Elige la versión de PHP:"
        }
        alert.addButton(withTitle: "Cargar proyecto")
        alert.addButton(withTitle: "Cancelar")
        // Una opción por versión; con la base en varias, la fecha de cada copia debajo
        let group = RadioGroup()
        var views: [NSView] = [dialogLabel(why, color: .secondaryLabelColor)]
        var options: [NSView] = []
        for (n, c) in cands.enumerated() {
            let i = c.0, cdb = c.1
            var notes: [String] = []
            if found { notes.append("BBDD \(cdb)") }
            if i.folder == active { notes.append("la activa") }
            if !x.php.isEmpty && i.php.hasPrefix(x.php) { notes.append("la de su .php-version") }
            let title = "PHP \(i.php)  (XAMPP-\(i.folder))" + (notes.isEmpty ? "" : "  ·  " + notes.joined(separator: ", "))
            let b = NSButton(radioButtonWithTitle: title, target: group, action: #selector(RadioGroup.pick(_:)))
            b.state = n == pre ? .on : .off
            group.buttons.append(b)
            let option = NSStackView()
            option.orientation = .vertical
            option.alignment = .leading
            option.spacing = 3
            option.addArrangedSubview(b)
            if found {
                let when = dbDateText(data?.dbDates[i.folder + "|" + cdb]) ?? "sin fecha"
                let sub = NSTextField(labelWithString: "BBDD: " + when)
                sub.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                sub.textColor = .secondaryLabelColor
                // alineado con el texto del botón, no con el círculo
                let indent = NSStackView(views: [sub])
                indent.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)
                option.addArrangedSubview(indent)
            }
            options.append(option)
        }
        views.append(dialogOptions(options, spacing: 14))
        alert.accessoryView = dialogStack(views, spacing: 14)
        guard alert.runStyled() == .alertFirstButtonReturn else { return nil }
        let chosen = group.buttons.firstIndex(where: { $0.state == .on }) ?? pre
        return cands[chosen]
    }
}
