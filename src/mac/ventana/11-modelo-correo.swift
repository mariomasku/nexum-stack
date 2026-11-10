extension AppModel {
    // MARK: correo de pruebas (Mailpit)

    /// Cuántos correos hay sin leer (api/v1/info de Mailpit, con curl del sistema y sin proxy), en
    /// segundo plano y solo con la ventana a la vista y Mailpit en marcha
    func pollMail() {
        guard let m = data?.mail, m.on, m.running else {
            if mailUnread != nil { mailUnread = nil }
            return
        }
        guard !mailPolling, NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        mailPolling = true
        let url = m.url + "api/v1/info"
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            p.arguments = ["-q", "-s", "--noproxy", "*", "--max-time", "3", "--max-filesize", "100000", url]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            var n: Int? = nil
            do {
                try p.run()
                let body = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if p.terminationStatus == 0,
                   let obj = (try? JSONSerialization.jsonObject(with: body, options: [])) as? [String: Any],
                   let unread = obj["Unread"] as? NSNumber {
                    n = unread.intValue
                }
            } catch {
                n = nil
            }
            let result = n
            DispatchQueue.main.async {
                self.mailPolling = false
                if self.mailUnread != result { self.mailUnread = result }
            }
        }
    }

    /// Botón Correo de arriba: la bandeja de Mailpit o, si no está instalado o parado, por qué
    func openMail() {
        guard let m = data?.mail else { return }
        if !m.installed {
            toolsSection = "correo"
            tab = "config"
            toast("Instala Mailpit en Configuración, apartado Correo de pruebas")
        } else if !m.running {
            toast("Mailpit arranca con la versión activa: arráncala arriba")
        } else {
            toolsSection = "correo"
            tab = "config"
        }
    }

    /// Encender o apagar el correo de pruebas (Configuración). La primera vez, ofrece instalar Mailpit
    func setMail(_ on: Bool) {
        guard let m = data?.mail, m.on != on, !busy else { return }
        var args = ["correo", on ? "si" : "no"]
        if on && !m.installed && confirm("¿Instalar Mailpit?",
                       "El correo de las webs irá a Mailpit, que se descarga de GitHub (Mailpit \(m.offer), comprobado antes de instalarlo, de root en /Library/Nexum/mailpit). Sin él, el correo no sale ni se ve. Pide la contraseña de administrador.",
                       "Instalar Mailpit") {
            args.append("--instalar")
        }
        if !on && !confirm("¿Apagar el correo de pruebas?",
                           "Lo que manden las webs (pedidos, formularios, contraseñas) podrá llegar de verdad a los clientes de las BBDD copiadas. Se aplica a todas las versiones y se recarga Apache. Pide la contraseña de administrador.",
                           "Apagarlo", destructive: true) { return }
        runTask(on ? "Encendiendo el correo de pruebas" : "Apagando el correo de pruebas", args,
                doneText: on ? "Correo de pruebas encendido" : "Correo de pruebas apagado", autoClose: true)
    }

    /// Plugins de correo de WordPress en la copia local: mailpit, desactivar o nada
    func setMailWp(_ mode: String) {
        guard let m = data?.mail, m.wp != mode, !busy else { return }
        let names = ["mailpit": "llevados a Mailpit", "desactivar": "desactivados en la copia local", "nada": "sin tocar"]
        let name = names[mode] ?? mode
        runTask("Plugins de correo de WordPress: \(name)", ["correo", "wordpress", mode],
                doneText: "Plugins de correo de WordPress \(name)", autoClose: true)
    }

    func installMail() {
        runTask("Instalando Mailpit", ["correo", "instalar"], progress: true, doneText: "Mailpit instalado", autoClose: true)
    }

    /// Configuración, Carpetas: vacía la caché de descargas (es de root: pide la contraseña)
    func clearDownloads(_ size: Int64) {
        guard confirm("¿Vaciar la caché de descargas?", "Las versiones instaladas no se tocan. La próxima instalación descargará todo otra vez.",
                      "Vaciar la caché", destructive: true,
                      steps: ["Se borra lo que hay en \(DL_CACHE_DIR) (\(fmtSize(size))).",
                              "Se pide la contraseña de administrador: la carpeta es suya."]) else { return }
        _ = runTask("Vaciando la caché de descargas", ["descargas", "vaciar"], doneText: "Caché de descargas vacía", autoClose: true)
    }

    /// Configuración, Carpetas: borra las copias de seguridad (lo de dentro de ~/nexum-backups, no la carpeta).
    /// Alguna copia de root puede pedir la contraseña
    func clearCopies(_ files: Int, _ size: Int64) {
        guard confirm("¿Borrar las copias de seguridad?", "Las copias borradas no se pueden recuperar.",
                      "Borrar las copias", destructive: true,
                      steps: ["Se borra todo lo que hay en ~/nexum-backups: \(plural(files, "fichero", "ficheros")) (\(fmtSize(size))). La carpeta se queda, vacía.",
                              "Si alguna copia es del administrador, se pide su contraseña para borrarla."]) else { return }
        _ = runTask("Borrando las copias de seguridad", ["copias", "vaciar"], doneText: "Copias de seguridad borradas",
                    autoClose: true) { _, _, _ in self.refreshBackups() }
    }

    /// Configuración, Carpetas: guardar o no una copia de los ficheros que cambia el programa por su cuenta
    /// (hosts, vhosts, configuración de los proyectos)
    func setCopiesFiles(_ on: Bool) {
        guard on != copiesFiles, !busy else { return }
        _ = runTask(on ? "Encendiendo las copias de los ficheros" : "Apagando las copias de los ficheros",
                    ["copias-ficheros", on ? "si" : "no"],
                    doneText: "Copias de los ficheros que cambia el programa " + (on ? "encendidas" : "apagadas"),
                    autoClose: true) { _, _, _ in
            self.copiesFiles = FileManager.default.fileExists(atPath: COPIES_FILES_FLAG)
        }
    }

    func clearMail() {
        guard confirm("¿Vaciar la bandeja de Mailpit?", "Se borran todos los correos que han mandado las webs de este Mac.",
                      "Vaciar la bandeja", destructive: true) else { return }
        runQuick(["correo", "vaciar"]) { rc, out in
            let last = out.split(separator: "\n").last.map(String.init) ?? "No se ha podido vaciar"
            self.toast(rc == 0 ? "Bandeja de Mailpit vacía" : last)
            self.pollMail()
        }
    }

    func setAside() {
        if !confirm("¿Apartar el XAMPP oficial?",
                    "/Applications/XAMPP tiene que ser un enlace a la versión activa. Sin borrar nada, se para, se copian sus BBDD (.zip, a ~/nexum-backups), sus proyectos y sus vhosts, y se mueve a /Applications/XAMPP-oficial-<fecha>.\n\nDespués, carga sus BBDD en Configuración (ahí también puedes volver a él). Pide la contraseña de administrador.",
                    "Apartar el XAMPP oficial") { return }
        runTask("Apartando el XAMPP oficial", ["apartar"], doneText: "XAMPP oficial apartado. Sus BBDD están copiadas en ~/nexum-backups")
    }

    func restoreOfficial(_ aside: String) {
        let name = (aside as NSString).lastPathComponent
        if !confirm("¿Volver al XAMPP oficial?",
                    "Se para la versión activa y \(name) vuelve a /Applications/XAMPP y arranca. Las versiones del gestor, sus BBDD y las copias no se tocan. Pide la contraseña de administrador.",
                    "Volver al XAMPP oficial") { return }
        runTask("Volviendo al XAMPP oficial", ["volver-oficial", aside], doneText: "El XAMPP oficial vuelve a estar en /Applications/XAMPP", autoClose: true)
    }

    func importBackups(_ folder: String) {
        let name = (folder as NSString).lastPathComponent
        let act = data?.active ?? ""
        if !confirm("¿Cargar las BBDD de \(name)?",
                    "Se cargan en XAMPP-\(act). Las que ya existan ahí no se tocan.",
                    "Cargar las BBDD") { return }
        checkDbAccess {
            _ = self.runTask("Cargando las BBDD del XAMPP oficial", ["importar-copias", folder],
                             doneText: "BBDD del XAMPP oficial cargadas en XAMPP-\(act)", env: self.dbEnv())
        }
    }

    func update(_ folder: String) {
        toast("Comprobando si hay una versión más nueva…")
        runQuick(["gui-al-dia", folder]) { _, out in
            let res = (out.components(separatedBy: "\n").filter { !$0.isEmpty }.last ?? "error").components(separatedBy: "|")
            switch res[0] {
            case "si":
                message("XAMPP-\(folder) ya está actualizada",
                        "Tiene el último parche de PHP de su rama (\(field(res, 1))) y sus componentes al día: no hay nada que actualizar.")
            case "no":
                let inst = self.data?.installs.first(where: { $0.folder == folder })
                let patch = (self.data?.php2shell[folder] ?? "") == "parcheable" && inst?.php == field(res, 1)
                // (si la rama de MariaDB cambia, sus BBDD no se pueden conservar: empieza vacía, con copia antes si se pide)
                var keep = "Sus BBDD, proyectos y vhosts se conservan."
                var warning = UPDATE_COPY_WARNING
                if let i = inst, let b = self.branch(i.php), !b.mariadb.isEmpty, !i.mariadb.hasPrefix(b.mariadb + ".") {
                    keep = "MariaDB pasa de la \(shortPhp(i.mariadb)) a la \(b.mariadb): empieza con las BBDD vacías. Proyectos y vhosts se conservan."
                    warning = "Sin copia, sus BBDD no se podrán recuperar."
                }
                let c = confirmCopy(patch ? "¿Poner el parche de seguridad a XAMPP-\(folder)?" : "¿Actualizar XAMPP-\(folder)?",
                                    (patch ? "Se vuelve a compilar PHP \(field(res, 1)) con el parche oficial contra PHP2Shell (\(PHP2SHELL_DATE)), y su pila con los últimos parches (unos minutos). "
                                           : "Se vuelve a compilar con PHP \(field(res, 1)) y los últimos parches de su pila (unos minutos). ")
                                    + keep + " Pide la contraseña de administrador.",
                                    patch ? "Poner el parche" : "Actualizar a PHP \(field(res, 1))", warning: warning)
                if !c.ok { return }
                self.runTask("Actualizando XAMPP-\(folder)", ["actualizar", folder] + (c.copy ? ["--copia"] : []), progress: true,
                             doneText: "XAMPP-\(folder) actualizada", reloadBranches: true)
            default:
                message("No se ha podido comprobar", "No se ha podido consultar php.net. Comprueba la conexión a internet.", error: true)
            }
        }
    }

    func remove(_ inst: Install) {
        let folder = inst.folder
        let dbs = data?.dbs[folder] ?? []
        var text = "Se borra /Library/Nexum/XAMPP-\(folder) (PHP \(inst.php))"
        text += dbs.isEmpty ? ". " : " con sus \(plural(dbs.count, "BBDD", "BBDD")). "
        text += "Los proyectos y los vhosts compartidos no se tocan. No se puede deshacer."
        var copy = false
        if dbs.isEmpty {
            if !confirm("¿Desinstalar XAMPP-\(folder)?", text, "Desinstalar XAMPP-\(folder)", destructive: true) { return }
        } else {
            let r = runDialog(title: "¿Desinstalar XAMPP-\(folder)?", text: text, okLabel: "Desinstalar XAMPP-\(folder)",
                              style: .warning, destructive: true,
                              checkbox: "Guardar antes una copia de sus BBDD en ~/nexum-backups", checked: false,
                              hasField: true,
                              fieldLabel: "Sin copia, las BBDD no se podrán recuperar. Escribe \(folder) para confirmar:",
                              validate: { checked, typed in (checked || typed.trimmingCharacters(in: .whitespaces) == folder, nil, false) })
            if !r.ok { return }
            copy = r.checked
        }
        expanded.remove(folder)
        runTask("Desinstalando XAMPP-\(folder)", ["desinstalar", folder] + (copy ? ["--copia"] : []),
                doneText: "XAMPP-\(folder) desinstalada" + (copy ? " (copia en ~/nexum-backups)" : ""),
                reloadBranches: true)
    }

    /// Los parches de una rama, de php.net (gui-parches), para elegir uno concreto
    func loadPatches(_ branch: String) {
        patchBranch = branch
        patches = nil
        patchesError = nil
        if branch.isEmpty { return }
        runQuick(["gui-parches", branch]) { rc, out in
            // (si mientras tanto se ha elegido otra rama, esta respuesta ya no vale)
            guard self.patchBranch == branch else { return }
            let lines = parseLines(out)
            if let e = lines.first(where: { $0[0] == "ERROR" }) {
                self.patchesError = e.count > 1 ? e[1] : "No se ha podido consultar php.net."
                return
            }
            let items = lines.filter { $0[0] == "P" && $0.count >= 6 }.map {
                PatchItem(version: $0[1], date: $0[2] == "-" ? "" : $0[2], state: $0[3], security: $0[4] == "1", latest: $0[5] == "1")
            }
            if rc != 0 || items.isEmpty { self.patchesError = "No se ha podido consultar php.net."; return }
            self.patches = items
        }
    }

    func install() {
        let list = selected.sorted { $0.compare($1, options: .numeric) == .orderedAscending }
        if list.isEmpty { return }
        let names = list.map { "PHP \($0)" }.joined(separator: ", ")
        if !confirm("¿Instalar \(names)?",
                    "Cada versión se compila en tu Mac con su Apache, MariaDB, ProFTPD, Perl y phpMyAdmin (20-40 min cada una). Pide la contraseña de administrador una vez. Las instaladas no se tocan.",
                    list.count == 1 ? "Instalar \(names)" : "Instalar \(list.count) versiones",
                    steps: list.map { "Se instala PHP \($0)." }) { return }
        runTask("Instalando", ["instalar", "--php", list.joined(separator: ","), "--si"], progress: true,
                doneText: "Instalación terminada", reloadBranches: true) { [weak self] _, task, p in
            guard let self = self, let p = p else { return }
            let good = p.results.filter { $0.1 == "0" }.map { $0.0 }
            self.selected.removeAll()
            if !self.patchBranch.isEmpty { self.loadPatches(self.patchBranch) }
            if good.count == 1 && !SIMULATE {
                let folder = itemFolder(good[0])
                task.offer("Activar XAMPP-\(folder)") {
                    self.task = nil
                    self.activate(folder)
                }
            }
        }
    }
}
