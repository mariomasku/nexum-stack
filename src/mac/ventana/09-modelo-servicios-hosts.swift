extension AppModel {
    // MARK: servicios

    func reloadServices() {
        runQuick(["gui-servicios"]) { rc, out in self.onServices(rc, out) }
    }

    func onServices(_ rc: Int32, _ out: String) {
        let rows = parseLines(out).filter { $0[0] == "S" && $0.count >= 6 }.map { f in
            Service(name: f[1], running: f[2] == "1", ports: f[3], open: f[4] == "1", auto: f[5] == "1",
                    user: field(f, 6))
        }
        if services != rows { services = rows }
    }

    /// Arranca, para o reinicia un servicio de la versión montada (nexum servicio ...)
    func service(_ name: String, _ cmd: String, _ title: String) {
        let verbs = ["arrancar": ("Arrancando", "arrancado"), "parar": ("Parando", "parado"),
                     "reiniciar": ("Reiniciando", "reiniciado")]
        let v = verbs[cmd] ?? ("", "")
        runTask("\(v.0) \(title)", ["servicio", name, cmd], doneText: "\(title) \(v.1)", autoClose: true)
    }

    /// Deja la versión montada solo para este Mac y la reinicia (nexum asegurar)
    func secure() {
        runTask("Cerrando a la red", ["asegurar"], doneText: "Solo se puede entrar desde este Mac", autoClose: true)
    }

    /// phpMyAdmin más nuevo que admite el PHP de una versión ("--todas": todas las que lo necesiten)
    func updatePma(_ folder: String) {
        runTask("Actualizando phpMyAdmin", ["actualizar-phpmyadmin", folder], progress: true,
                doneText: "phpMyAdmin actualizado", autoClose: true)
    }

    /// Certificados propios para los proyectos https y sin la CA local (nexum arreglar-certificados)
    func fixCerts() {
        runTask("Arreglando los certificados", ["arreglar-certificados"], doneText: "Certificados arreglados")
    }

    /// Que el navegador acepte el certificado propio de cada proyecto https (nexum confiar-certificados)
    func trustCerts() {
        runTask("Confiando en los certificados de los proyectos", ["confiar-certificados"],
                doneText: "El navegador acepta los certificados de los proyectos")
    }

    /// Que deje de aceptar los de las tiendas que ya no están falseadas (confiar-certificados --quitar)
    func untrustCerts() {
        runTask("Quitando los certificados de las webs reales", ["confiar-certificados", "--quitar"],
                doneText: "El navegador ya no acepta esos certificados")
    }

    /// Todas las versiones solo para este Mac (nexum asegurar --todas)
    func secureAll() {
        runTask("Protegiendo las versiones", ["asegurar", "--todas"],
                doneText: "Todas las versiones son solo para este Mac", autoClose: true)
    }

    /// Repara las tablas del sistema de MariaDB (reparar-bd-sistema), con copia antes si se marca
    func repairDbSystem() {
        let ver = data?.dbsysVersion ?? ""
        let c = confirmCopy("¿Reparar las tablas del sistema?", "Las BBDD de los proyectos no se tocan.", "Repararlas",
                            steps: ["Se ponen al día las tablas del sistema (mysql.*) del MariaDB de XAMPP-\(ver) con el mariadb-upgrade de la versión.",
                                    "Si el registro de errores es grande, se vacía."],
                            warning: "Sin copia, las tablas del sistema de ahora no se podrán recuperar.")
        if !c.ok { return }
        runTask("Reparando las tablas del sistema de MariaDB", ["reparar-bd-sistema"] + (c.copy ? ["--copia"] : []),
                doneText: "Tablas del sistema de MariaDB al día", autoClose: true)
    }

    // MARK: hosts falseados

    func reloadHosts() {
        runQuick(["gui-hosts"]) { rc, out in self.onHosts(rc, out) }
    }

    func onHosts(_ rc: Int32, _ out: String) {
        let rows = parseLines(out).filter { $0[0] == "F" && $0.count >= 8 }.map { f in
            HostEntry(name: f[1], alias: f[2], folder: f[3], fake: f[4] == "1",
                      https: f[5] == "1", crt: f[6] == "1", ps: f[7] == "1",
                      custom: f.count >= 9 && f[8] == "1", media: f.count >= 10 ? f[9] : "")
        }
        if hosts == nil || rows != hosts! { hosts = rows }
        let fix = parseLines(out).filter { $0[0] == "L" && $0.count >= 3 }.map { [$0[1], $0[2]] }
        if fix != hostsLinkFix { hostsLinkFix = fix }
    }

    /// web.local a 127.0.0.1 en /etc/hosts (aviso de la pestaña Hosts)
    func fixHostsLink() {
        runTask("Arreglando /etc/hosts", ["hosts-enlace"], doneText: "web.local ya lleva a este Mac", autoClose: true)
    }

    /// Interruptor de la pestaña Hosts: falsea o deja de falsear un dominio en /etc/hosts
    func setHostFake(_ h: HostEntry, _ on: Bool) {
        if on == h.fake || busy { return }
        let local = h.name.lowercased().hasSuffix(".local")
        if local && !on {
            guard confirm("¿Apagar \(h.name)?",
                          "Sus líneas de /etc/hosts se comentan y no se vuelven a añadir solas. Mientras esté apagado, alguien de tu misma wifi podría contestar por \(h.name) con una web suya. Se puede volver a encender.",
                          "Apagar \(h.name)") else { return }
        }
        let done = local ? "\(h.name) \(on ? "lleva a este equipo" : "apagado")"
            : on ? "\(h.name) lleva a este equipo" : "\(h.name) lleva a la web real"
        let title = local ? "\(on ? "Encendiendo" : "Apagando") \(h.name)"
            : on ? "Falseando \(h.name)" : "Dejando de falsear \(h.name)"
        runTask(title,
                ["hosts-falsear", h.name, on ? "si" : "no"], doneText: done, autoClose: true) { ok, _, _ in
            self.toast(ok ? done : "No se ha cambiado /etc/hosts")
        }
    }

    /// Dominios falseables de un proyecto: los de los vhosts de su carpeta. Un .local no es un dominio
    /// falseado (no hay ninguna web real a la que devolverlo)
    func projectHosts(_ name: String) -> [HostEntry] {
        return (hosts ?? []).filter { $0.folder == name && !$0.name.lowercased().hasSuffix(".local") }
    }

    /// El fichero de hosts, solo para verlo (para cambiarlo: Editar, en Configuración), con los dominios
    /// que se pueden falsear delante: un dominio con vhost no sale en él hasta falsearlo
    func viewHostsFile() {
        let d = data ?? AppData()
        guard let raw = FileManager.default.contents(atPath: d.hosts) else {
            message("No se ha podido leer \(d.hosts)", "", error: true)
            return
        }
        let list = hosts ?? []
        let states = list.map { h -> String in
            h.name.lowercased().hasSuffix(".local") ? (h.fake ? "encendido" : "apagado") : (h.fake ? "falseado" : "sin falsear")
        }
        let stateW = states.map { $0.count }.max() ?? 0
        let nameW = list.map { $0.name.count }.max() ?? 0
        var head = ["# DOMINIOS QUE SE PUEDEN FALSEAR (tienen vhost en \(d.vhosts))"]
        for (h, state) in zip(list, states) {
            let st = state.padding(toLength: stateW, withPad: " ", startingAt: 0)
            let nm = h.name.padding(toLength: nameW, withPad: " ", startingAt: 0)
            head.append("#   \(st)  \(nm)  ->  \(h.folder.isEmpty ? "sin carpeta" : h.folder)")
        }
        if list.isEmpty { head.append("#   (ninguno)") }
        head += ["#", "# CONTENIDO DE \(d.hosts)", ""]
        showLongText(d.hosts, head.joined(separator: "\n") + "\n" + String(decoding: raw, as: UTF8.self),
                     subtitle: "Dominios que se pueden falsear y contenido del fichero (solo lectura)")
    }

    /// Carpeta del proyecto nuevo: si trae su configuración, se propone su base de datos
    func pickNewFolder(_ folder: String) {
        newFolder = folder
        if newDb.isEmpty && !folder.isEmpty {
            let db = projectDb(folder)
            if !db.isEmpty {
                newDb = db
                toast("BBDD de su configuración: \(db)")
            }
        }
    }

    /// Nombre de una carpeta o una base nueva (se crea al pulsar «Crear y falsear»)
    func askNewDomainName(db isDb: Bool) {
        let existing = isDb ? (data.map { $0.dbs[$0.active] ?? [] } ?? []) : projectFolders()
        let hint = isDb ? "Letras sin acentos, números, _ y -" : "Letras sin acentos, números, punto, _ y -"
        let fallback = isDb ? "" : newDomain
        let r = runDialog(title: isDb ? "BBDD nueva" : "Carpeta nueva",
                          text: isDb ? "El nombre de la BBDD de producción. Se crea vacía en XAMPP-\(data?.active ?? "") al pulsar «Crear y falsear»."
                                     : "Se crea en htdocs al pulsar «Crear y falsear». Si vas a clonarlo con git, clónalo antes y elígelo en la lista.",
                          okLabel: "Usar este nombre", hasField: true, fieldLabel: hint,
                          placeholder: isDb ? "nombre_de_la_base" : (newDomain.isEmpty ? "carpeta-del-proyecto" : newDomain),
                          validate: { _, typed in
                              var name = typed.trimmingCharacters(in: .whitespaces)
                              if name.isEmpty { name = fallback }
                              if existing.contains(name) { return (false, "Ya existe: elígela en la lista.", true) }
                              let valid = isDb ? validDbName(name) : matches(FOLDER_RX, name)
                              return (valid, hint, !valid && !name.isEmpty)
                          })
        if !r.ok { return }
        var name = r.text.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = fallback }
        if isDb { newDb = name } else { newFolder = name }
    }

    func createNewDomain() {
        let domain = cleanDomain(newDomain).lowercased()
        let folder = newFolder, db = newDb
        guard matches(DOMAIN_RX, domain), !folder.isEmpty, let d = data else { return }
        let exists = projectFolders().contains(folder)
        var steps = ["Carpeta htdocs/\(folder)\(exists ? "" : " (se crea)").",
                     "Vhost http y https de \(domain) con su certificado autofirmado."]
        if !db.isEmpty {
            let have = (d.dbs[d.active] ?? []).contains(db)
            steps.append("BBDD \(db) en XAMPP-\(d.active)\(have ? " (ya existe: se deja como está)" : " (se crea vacía)").")
        }
        steps.append("\(domain) se falsea en /etc/hosts; los demás dominios dejan de estarlo.")
        if !confirm("¿Crear \(domain)?", "Pide la contraseña de administrador.", "Crear y falsear",
                    steps: steps) { return }
        runTask("Creando \(domain)", ["nuevo-dominio", domain, folder] + (db.isEmpty ? [] : [db]),
                doneText: "\(domain) listo", env: dbEnv()) { ok, _, _ in
            if ok {
                self.newDomain = ""
                self.newFolder = ""
                self.newDb = ""
                self.toast("\(domain) falseado: https://\(domain) → htdocs/\(folder)")
            }
        }
    }

    /// Cierra los procesos de XAMPP de otras versiones que se quedaron en memoria
    /// Quita los vhosts de los proyectos cuya carpeta ya no existe (vhosts-sin-carpeta quitar)
    func removeOrphanVhosts() {
        let orphans = data?.orphans ?? []
        guard !orphans.isEmpty else { return }
        let steps = orphans.map { "Se quitan del fichero de vhosts los de \($0.0) (\($0.1.isEmpty ? "sin dominio" : $0.1))." }
            + ["Apache comprueba el fichero y se recarga."]
        guard confirm("¿Quitar los vhosts de carpetas que ya no existen?",
                      "Las carpetas, las BBDD y /etc/hosts no se tocan. Pide la contraseña de administrador.",
                      "Quitarlos", destructive: true, steps: steps) else { return }
        runTask("Quitando vhosts de carpetas que ya no existen", ["vhosts-sin-carpeta", "quitar"],
                doneText: "Vhosts quitados", autoClose: true)
    }

    func closeStray() {
        runTask("Cerrando los procesos que sobran", ["cerrar-procesos"],
                doneText: "Solo queda en memoria la versión montada", autoClose: true) { ok, _, _ in
            self.toast(ok ? "Procesos cerrados" : "No se han podido cerrar todos")
        }
    }

    /// Últimas líneas del error_log (sin leer el fichero entero, que puede ocupar cientos de MB)
    func showLogTail(_ path: String, lines: Int = 400) {
        guard let fh = FileHandle(forReadingAtPath: path) else {
            message("No se ha podido leer \(path)", "", error: true)
            return
        }
        let size = fh.seekToEndOfFile()
        fh.seek(toFileOffset: size > 262_144 ? size - 262_144 : 0)
        let text = String(decoding: fh.readDataToEndOfFile(), as: UTF8.self)
        fh.closeFile()
        // (los de PHP-FPM llegan en una sola línea con \\n escritos: se separan para leerlos)
        let tail = text.components(separatedBy: "\n").suffix(lines).joined(separator: "\n")
            .replacingOccurrences(of: "\\n", with: "\n    ")
        showLongText((path as NSString).lastPathComponent, tail.isEmpty ? "(vacío)" : tail,
                     subtitle: "Últimas \(lines) líneas de \(path)", toEnd: true)
    }

    func openInEditor(_ path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-t", path]
        try? p.run()
    }

    func showCommands() {
        runQuick(["--ayuda"]) { _, out in
            showLongText("Comandos de nexum", out, subtitle: "En la terminal: nexum --ayuda",
                         commands: true)
        }
    }
}
