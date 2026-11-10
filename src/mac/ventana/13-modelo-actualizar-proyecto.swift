extension AppModel {
    // MARK: Actualizar proyecto

    /// Abre el diálogo para actualizar el proyecto cargado con lo de producción
    func upOpen(_ x: Project) {
        upFolder = x.name
        upSql = ""
        upCode = ""
        upMode = "fusionar"
        upDb = loadedDb(x)
        upDbKnown = !upDb.isEmpty
        upSqlError = ""
        upCodeError = ""
        upShown = true
    }

    /// Fichero o carpeta elegidos o arrastrados (ruta vacía: quitarlo). Lo que no vale se dice en su zona
    func upSet(code: Bool, _ path: String) {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        let low = path.lowercased()
        if code {
            let ok = path.isEmpty || (exists && (isDir.boolValue || [".zip", ".tar", ".tgz", ".tar.gz", ".tar.bz2", ".tar.xz"].contains(where: { low.hasSuffix($0) })))
            upCodeError = ok ? "" : "Tiene que ser un .zip, un .tar.gz o una carpeta"
            upCode = ok ? path : ""
        } else {
            let ok = path.isEmpty || (exists && !isDir.boolValue && [".sql", ".gz", ".zip"].contains(where: { low.hasSuffix($0) }))
            upSqlError = ok ? "" : "Tiene que ser .sql, .sql.gz o .zip"
            upSql = ok ? path : ""
        }
    }

    func upPick(code: Bool, folder: Bool) {
        let panel = NSOpenPanel()
        panel.title = code ? "Código de producción" : "Base de datos de producción"
        panel.prompt = "Elegir"
        panel.canChooseFiles = !folder
        panel.canChooseDirectories = folder
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK, let url = panel.url { upSet(code: code, url.path) }
    }

    /// Antes de copiar: si es un repositorio, ¿git pull antes?, avisando de lo que no se ha subido
    func upAsk() {
        upShown = false
        let folder = upFolder, sql = upSql, db = upDb.trimmingCharacters(in: .whitespaces), code = upCode, mode = upMode
        var what: [String] = []
        if !code.isEmpty {
            let name = (code as NSString).lastPathComponent
            what.append(mode == "fusionar" ? "Se fusiona «\(name)» con \(HTDOCS)/\(folder)."
                        : "Se sobrescribe la carpeta con «\(name)» en \(HTDOCS)/\(folder): se borra lo que no traiga.")
        }
        if !sql.isEmpty { what.append("La BBDD \(db) se vacía y se carga «\((sql as NSString).lastPathComponent)».") }
        runQuick(["gui-proyecto-git", folder]) { _, out in
            let f = parseLines(out).first(where: { $0.first == "G" && $0.count >= 6 })
            guard !code.isEmpty, let g = f, g[1] == "1" else {
                let c = confirmCopy("¿Actualizar \(folder)?", "", "Actualizar", steps: what)
                if c.ok {
                    self.upStart(folder, sql, db, code, mode, pull: false, copy: c.copy)
                }
                return
            }
            let dirty = Int(g[3]) ?? 0, ahead = Int(g[4]) ?? 0
            var state = ["Rama " + (g[2].isEmpty ? "sin rama (HEAD suelto)" : g[2])]
            if dirty > 0 { state.append(plural(dirty, "cambio", "cambios") + " sin commit") }
            if ahead > 0 { state.append(plural(ahead, "commit", "commits") + " sin subir") }
            var text = [state.joined(separator: "  ·  ")]
            if dirty > 0 || ahead > 0 { text.append("Revisa antes lo que estás trabajando: lo sustituido no queda en git (solo en la copia, si la guardas).") }
            let canPull = g[5] == "1" && !g[2].isEmpty
            text.append(canPull ? "Con el pull, la carpeta se equipara antes al repositorio. Si choca con tus cambios, se para sin tocar nada."
                        : "No se puede hacer pull: no tiene origin o no está en una rama.")
            let alert = NSAlert()
            alert.messageText = "¿Hacer git pull antes de copiar?"
            let steps = dialogSteps(what)
            let note = dialogLabel(text.joined(separator: "\n\n"), color: .secondaryLabelColor, align: .left)
            let cc = copyCheckViews()
            alert.accessoryView = dialogStack([steps, note, cc.box, cc.note])
            if canPull { alert.addButton(withTitle: "Hacer pull y copiar") }
            alert.addButton(withTitle: "Copiar sin pull")
            alert.addButton(withTitle: "Cancelar")
            let resp = withExtendedLifetime(cc.validator) { alert.runModal() }
            let copy = cc.box.state == .on
            if canPull && resp == .alertFirstButtonReturn {
                self.upStart(folder, sql, db, code, mode, pull: true, copy: copy)
            } else if resp == (canPull ? .alertSecondButtonReturn : .alertFirstButtonReturn) {
                self.upStart(folder, sql, db, code, mode, pull: false, copy: copy)
            }
        }
    }

    func upStart(_ folder: String, _ sql: String, _ db: String, _ code: String, _ mode: String, pull: Bool, copy: Bool) {
        var args = ["actualizar-proyecto", folder] + (copy ? ["--copia"] : [])
        if !code.isEmpty { args += ["--codigo", code, "--modo", mode] + (pull ? ["--pull"] : []) }
        if !sql.isEmpty { args += ["--bd", sql] }
        // (también solo con el código: al volver a cargarlo, su configuración vuelve a esta BBDD)
        if !db.isEmpty { args += ["--base", db] }
        let go = {
            _ = self.runTask("Actualizando \(folder)", args, progress: true, doneText: "\(folder) actualizado", env: self.dbEnv(),
                             cancelText: ("¿Cancelar la actualización?",
                                          "El proyecto se queda a medias, con lo hecho hasta ahora."
                                              + (copy ? " Lo sustituido sigue en ~/nexum-backups." : ""),
                                          "Cancelar la actualización"))
        }
        if sql.isEmpty { go() } else { checkDbAccess { go() } }
    }

    /// Al escribir en el buscador: un repositorio pegado (botón de copiar de Repositorios) o escrito entero
    /// queda elegido
    func npRepoTyped(_ text: String) {
        npRepoQuery = text
        let q = repoQuery(text)
        if let r = npRepos.first(where: { $0.full.lowercased() == q }), npUrl != "git@github.com:\(r.full).git" {
            npPickRepo(r)
        }
    }

    /// Repositorio elegido de la lista de GitHub: su dirección SSH (con tu clave), su carpeta y, si su web es
    /// la de producción, su dominio para el paso 4 (en una tienda, falsearlo)
    func npPickRepo(_ r: RepoItem) {
        npRepoQuery = r.full
        npUrl = "git@github.com:\(r.full).git"
        if npFolderAuto { npFolder = folderFromGitURL(npUrl) }
        var dom = r.web.lowercased().replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
        dom = String(dom.split(separator: "/").first ?? "").components(separatedBy: ":").first ?? ""
        if matches(DOMAIN_RX, dom) {
            npDomain = dom
            npFake = r.prefix.contains("prestashop") || r.name.contains("prestashop")
        }
        npRepoNote = "Se clona por SSH, con tu clave: \(npUrl)" + (dom.isEmpty ? "" : "  ·  web: \(dom)")
    }

    /// ¿Se puede seguir desde el paso del asistente? (y, si no, por qué: vacío si solo falta escribirlo)
    func npCheck() -> (Bool, String) {
        let d = data ?? AppData()
        switch npStep {
        case 1:
            let url = npUrl.trimmingCharacters(in: .whitespaces)
            let folder = npFolder.trimmingCharacters(in: .whitespaces)
            if url.isEmpty { return (false, "") }
            if !matches(GIT_URL_RX, url) {
                return (false, "La dirección no es válida: usa https://… o git@servidor:usuario/repositorio.git")
            }
            if folder.isEmpty { return (false, "") }
            if !matches(NEW_FOLDER_RX, folder) || folder == ".lvm-sin-proyecto" {
                return (false, "Pon un nombre de carpeta: letras sin acentos, números, punto, _ y -")
            }
            if (try? FileManager.default.attributesOfItem(atPath: HTDOCS + "/" + folder)) != nil {
                return (false, "Ya existe htdocs/\(folder): elige otro nombre")
            }
            return (true, "")
        case 2:
            return (d.installs.contains { $0.folder == npVersion }, "")
        case 4:
            let dom = npDomain.trimmingCharacters(in: .whitespaces).lowercased()
            if npFake && !matches(DOMAIN_RX, dom) {
                return (false, dom.isEmpty ? "" : "Dominio no válido (por ejemplo: midominio.com)")
            }
            return (true, "")
        default:
            let db = npDb.trimmingCharacters(in: .whitespaces)
            if db.isEmpty { return (false, "") }
            if cleanDbName(db).isEmpty {
                return (false, "El nombre de la BBDD solo puede llevar letras sin acentos, números, _ y -")
            }
            if (d.dbs[npVersion] ?? []).contains(where: { $0.lowercased() == db.lowercased() }) {
                return (false, "XAMPP-\(npVersion) ya tiene una BBDD \(db): elige otro nombre")
            }
            return (true, "")
        }
    }

    func npGo(_ step: Int) {
        let next = npStep + step
        if next >= 5 {
            mountProject()
            return
        }
        if next == 2 && !(data?.installs ?? []).contains(where: { $0.folder == npVersion }) {
            npVersion = data?.active ?? data?.installs.first?.folder ?? ""
        }
        if next == 3 && npDb.isEmpty {
            let base = npFolder.lowercased()
                .replacingOccurrences(of: "[^a-z0-9_]", with: "_", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            npDb = base.isEmpty ? "" : "wp_" + String(base.prefix(40))
        }
        npStep = max(1, next)
    }

    func npPickDump() {
        let panel = NSOpenPanel()
        panel.title = "Elegir el volcado de la BBDD"
        panel.prompt = "Elegir"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = fileTypes(["sql", "gz", "zip"])
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK, let url = panel.url { npFile = url.path }
    }

    /// Clona el repositorio, lo carga en la versión elegida y le crea su BBDD (montar-proyecto)
    func mountProject() {
        let url = npUrl.trimmingCharacters(in: .whitespaces)
        let folder = npFolder.trimmingCharacters(in: .whitespaces)
        let db = npDb.trimmingCharacters(in: .whitespaces)
        let version = npVersion
        var args = ["montar-proyecto", url, folder, version, db]
        if let f = npFile { args.append(f) }
        let domain = npFake ? npDomain.trimmingCharacters(in: .whitespaces).lowercased() : ""
        runTask("Montando el proyecto \(folder)", args, progress: true,
                doneText: "\(folder) está clonado, cargado en XAMPP-\(version) y con su BBDD \(db)") { ok, _, _ in
            guard ok else { return }
            self.npOpen = false
            self.toast("Proyecto nuevo montado: \(folder) en XAMPP-\(version) con la BBDD \(db)")
            // (después, si se ha pedido, su dominio de producción falseado)
            if !domain.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    _ = self.runTask("Falseando \(domain) para \(folder)", ["nuevo-dominio", domain, folder],
                                     doneText: "\(domain) falseado: se abre en local", autoClose: true)
                }
            }
        }
    }

    /// Vaciar var/cache de la tienda PrestaShop de la base (la carpeta la busca el script)
    func clearCache(_ db: String) {
        runTask("Vaciando la caché de la tienda de \(db)", ["vaciar-cache", "--bd", db],
                doneText: "Caché vaciada", autoClose: true)
    }

    /// ⋮, Limpiar proyecto…: lo que tiene de caché, registros y restos de actualizaciones (gui-limpiar-proyecto),
    /// cada cosa con sus carpetas, lo que ocupa y su casilla (marcada); se confirma con lo que se va a hacer y se
    /// lanza limpiar-proyecto con lo marcado. Si no tiene nada, se dice
    func cleanProject(_ x: Project) {
        let name = x.name
        runQuick(["gui-limpiar-proyecto", name]) { _, out in
            var found: [(key: String, size: CleanSize, paths: String)] = []
            for f in parseLines(out) where f.count >= 5 && f[0] == "P" {
                if let b = Int64(f[2]), let n = Int(f[3]), n > 0 {
                    found.append((key: f[1], size: CleanSize(bytes: b, files: n), paths: f[4]))
                }
            }
            guard !found.isEmpty else {
                message("Nada que limpiar", "No hay cachés ni registros que limpiar en \(name).")
                return
            }
            // Una casilla por cosa (marcadas), con sus carpetas debajo, y el aviso en rojo
            let alert = NSAlert()
            alert.messageText = "Limpiar «\(name)»"
            alert.informativeText = "Marca lo que quieres limpiar. Las carpetas se quedan, vacías; nada de las imágenes ni de lo que se sube a la web."
            alert.alertStyle = .informational
            let ok = alert.addButton(withTitle: "Limpiar lo marcado…")
            ok.hasDestructiveAction = true
            ok.keyEquivalent = ""
            let cancel = alert.addButton(withTitle: "Cancelar")
            cancel.keyEquivalent = "\u{1b}"
            let validator = DialogValidator()
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 4
            var made: [NSButton] = []
            for it in found {
                let title = PROJECT_CLEAN_ITEMS.first(where: { $0.key == it.key })?.title ?? it.key
                let b = NSButton(checkboxWithTitle: "\(title) · \(cleanSizeText(it.size))", target: validator,
                                 action: #selector(DialogValidator.changed(_:)))
                b.state = .on
                stack.addArrangedSubview(b)
                let p = NSTextField(wrappingLabelWithString: it.paths.split(separator: ",").joined(separator: ", "))
                p.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                p.textColor = .secondaryLabelColor
                p.preferredMaxLayoutWidth = DIALOG_WIDTH - 22
                let row = NSStackView(views: [p])
                row.edgeInsets = NSEdgeInsets(top: 0, left: 22, bottom: 6, right: 0)
                stack.addArrangedSubview(row)
                made.append(b)
            }
            let boxes = made
            let w = NSTextField(wrappingLabelWithString: CLEAN_WARNING)
            w.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            w.textColor = .systemRed
            w.preferredMaxLayoutWidth = DIALOG_WIDTH
            stack.addArrangedSubview(w)
            validator.update = { ok.isEnabled = boxes.contains { $0.state == .on } }
            validator.update()
            stack.layoutSubtreeIfNeeded()
            stack.frame = NSRect(x: 0, y: 0, width: DIALOG_WIDTH, height: max(stack.fittingSize.height, 24))
            alert.accessoryView = stack
            // (el validador, vivo mientras se ve el diálogo: el botón no lo retiene)
            let resp = withExtendedLifetime(validator) { alert.runStyled() }
            guard resp == .alertFirstButtonReturn else { return }
            let chosen = zip(found, boxes).filter { $0.1.state == .on }.map { $0.0 }
            guard !chosen.isEmpty else { return }
            let steps = chosen.map { it -> String in
                let info = PROJECT_CLEAN_ITEMS.first(where: { $0.key == it.key })
                return "\(info?.title ?? it.key) (\(cleanSizeText(it.size))): \(info?.step ?? "se limpia") (\(it.paths.split(separator: ",").joined(separator: ", ")))."
            }
            guard confirm("¿Limpiar «\(name)»?", "Si algo es del administrador (lo que creó Apache), se pide su contraseña.",
                          "Limpiar", destructive: true, steps: steps, warning: CLEAN_WARNING) else { return }
            self.runTask("Limpiando \(name)", ["limpiar-proyecto", name] + chosen.map { $0.key },
                         doneText: "\(name) limpio", autoClose: true)
        }
    }

    /// Dominio de producción para las imágenes que faltan: el campo con el que había o el propuesto;
    /// vacío (si ya había uno), deja de pedirlas. done(dominio o "" para quitar)
    private func askMedia(_ title: String, _ text: String, saved: String, value: String,
                          _ done: (String) -> Void) {
        func clean(_ s: String) -> String {
            var d = s.trimmingCharacters(in: .whitespaces).lowercased()
            for p in ["https://", "http://"] where d.hasPrefix(p) { d = String(d.dropFirst(p.count)) }
            while d.hasSuffix("/") { d = String(d.dropLast()) }
            return d
        }
        let r = runDialog(title: title, text: text, okLabel: "Guardar", hasField: true,
                          fieldLabel: "Dominio de la web real (ejemplo.com)", placeholder: "ejemplo.com", value: value,
                          validate: { _, typed in
                              let d = clean(typed)
                              if d.isEmpty {
                                  return (!saved.isEmpty, saved.isEmpty ? "Dominio de la web real (ejemplo.com)"
                                          : "Vacío: deja de pedir nada a producción", false)
                              }
                              // (el mismo de antes también: se vuelve a aplicar, en web.local y en el Apache de Docker)
                              let ok = matches(DOMAIN_RX, d) && !d.hasSuffix(".local") && !d.hasSuffix(".test")
                              return (ok, ok ? "Dominio de la web real (ejemplo.com)" : "No es un dominio de la web real", !ok)
                          })
        if r.ok { done(clean(r.text)) }
    }

    /// media-produccion: lo que falte en un .local de wp-content/uploads o img se pide a la web real
    /// (uploads e img no van en git). Se propone el dominio real del vhost de su carpeta
    func mediaProxy(_ h: HostEntry) {
        if busy { return }
        let guess = h.media.isEmpty
            ? ((hosts ?? []).first(where: { !h.folder.isEmpty && $0.folder == h.folder
                                            && !$0.name.lowercased().hasSuffix(".local") })?.name ?? "")
            : h.media
        askMedia("Imágenes de producción en \(h.name)",
                 "Las imágenes, vídeos y PDF de wp-content/uploads o img que no estén en la carpeta se piden a la web real (redirección 302): no hace falta descargarlas. Solo en los .local; lo que ya está en local se sigue sirviendo desde aquí.",
                 saved: h.media, value: guess) { prod in
            if prod.isEmpty {
                runTask("Quitando las imágenes de producción de \(h.name)", ["media-produccion", h.name, "quitar"],
                        doneText: "\(h.name) ya no pide nada a producción", autoClose: true)
            } else {
                runTask("Imágenes de producción en \(h.name)", ["media-produccion", h.name, prod],
                        doneText: "\(h.name) pide a \(prod) las imágenes que faltan", autoClose: true)
            }
        }
    }

    /// media-proyecto: lo que le falte a un WordPress de wp-content/uploads se pide a su web real
    /// mientras esté cargado (por web.local). Se propone el dominio de su base (home o siteurl)
    func wpMedia(_ x: Project) {
        if busy { return }
        runQuick(["gui-wp-produccion", x.name], env: dbEnv()) { _, out in
            var f: [String: String] = [:]
            for l in parseLines(out) where l.count >= 2 { f[l[0]] = l[1] }
            let saved = f["G"] ?? "", guess = f["D"] ?? ""
            self.askMedia("Imágenes de producción de \(x.name)",
                          "Mientras esté cargado (y, si está en el Apache de Docker, también allí), lo que falte en su carpeta wp-content/uploads (imágenes, vídeos y PDF) se pide a su web real: no hace falta descargarlo. Lo que ya está en local se sigue sirviendo desde aquí."
                              + (saved.isEmpty && !guess.isEmpty ? "\n\n\(guess) es el dominio de su BBDD: compruébalo antes de guardar." : ""),
                          saved: saved, value: saved.isEmpty ? guess : saved) { prod in
                if prod.isEmpty {
                    self.runTask("Quitando las imágenes de producción de \(x.name)", ["media-proyecto", x.name, "quitar"],
                                 doneText: "\(x.name) ya no pide nada a producción", autoClose: true)
                } else {
                    self.runTask("Imágenes de producción de \(x.name)", ["media-proyecto", x.name, prod],
                                 doneText: "\(x.name) pide a \(prod) las imágenes que le faltan", autoClose: true)
                }
            }
        }
    }

    /// ps-imagenes: una tienda se ve con su dominio real falseado (una redirección volvería aquí), así
    /// que las imágenes que faltan se descargan de la web real, con la lista de su BBDD
    func psImages(_ x: Project) {
        if busy { return }
        guard confirm("¿Descargar las imágenes que le faltan a \(x.name)?",
                      "Se descargan de su web real las imágenes de productos, categorías y marcas que no están en su carpeta img (la lista sale de su BBDD: la de la versión activa o, si no está allí, la de su proyecto del Apache de Docker). Van a su carpeta img, la misma con XAMPP-X y con Docker. Lo que ya está en local no se toca. Con muchos productos puede tardar y ocupar bastante.\n\nSu dominio está falseado en este Mac: se busca con DNS cifrado (Cloudflare) y se comprueba su certificado real.",
                      "Descargar") else { return }
        checkDbAccess {
            _ = self.runTask("Descargando las imágenes de \(x.name)", ["ps-imagenes", x.name],
                             doneText: "Imágenes de \(x.name) descargadas", env: self.dbEnv())
        }
    }

    /// Importar imágenes de producción: un WordPress las pide a su web real; una tienda las descarga
    func importImages(_ x: Project) {
        if x.kind == "wp" { wpMedia(x) } else { psImages(x) }
    }

    /// borrar-proyecto: su carpeta, sus vhosts y dominios, lo de Docker y, si se quiere, su BBDD de la
    /// versión activa (la de phpMyAdmin), con copia si se marca. Hay que escribir el nombre de la carpeta
    /// para confirmar: la carpeta no se puede recuperar
    func deleteProject(_ x: Project) {
        guard let d = data, !busy else { return }
        let db = projectPairs(x).first(where: { $0.0.folder == d.active })?.1
        let docker = dockerOf(x.name)
        var what = ["su carpeta \(HTDOCS)/\(x.name)", "sus vhosts y las líneas de sus dominios en /etc/hosts"]
        if !docker.isEmpty {
            what.append("sus contenedores de Docker (\(docker.map { $0.domain }.joined(separator: ", ")))")
        }
        let r = runDialog(title: "¿Borrar el proyecto «\(x.name)»?",
                          text: "Se borran " + what.dropLast().joined(separator: ", ") + " y " + (what.last ?? "")
                              + ". La carpeta no se puede recuperar.",
                          okLabel: "Borrar el proyecto", style: .critical, destructive: true, hasField: true,
                          fieldLabel: "Escribe \(x.name) para confirmar:",
                          validate: { _, typed in (typed.trimmingCharacters(in: .whitespaces) == x.name, nil, false) })
        if !r.ok { return }
        var args = ["borrar-proyecto", x.name]
        var withDb = false, copy = false
        if let db = db {
            let r2 = runDialog(title: "¿Borrar también su BBDD «\(db)»?",
                               text: "Es la de XAMPP-\(d.active), la que se ve en phpMyAdmin. Si no, solo se borra el proyecto y la BBDD se queda.",
                               okLabel: "Borrar también la BBDD", style: .critical, destructive: true,
                               checkbox: "Guardar antes una copia en ~/nexum-backups (se puede volver a cargar)", checked: false,
                               cancelLabel: "Solo el proyecto",
                               copyWarning: "Sin copia, la BBDD no se podrá recuperar.")
            if r2.ok {
                withDb = true
                copy = r2.checked
                args += ["--bd", db] + (copy ? ["--copia"] : [])
            }
        }
        let finalArgs = args, useDb = withDb
        let done = "Proyecto «\(x.name)» borrado" + (useDb ? " con su BBDD" : "") + (useDb && copy ? " (copia en ~/nexum-backups)" : "")
        let go: () -> Void = {
            _ = self.runTask("Borrando el proyecto \(x.name)", finalArgs, doneText: done,
                             env: useDb ? self.dbEnv() : [:])
        }
        if useDb { checkDbAccess { go() } } else { go() }
    }

    /// Versiones a las que se puede copiar una base: las que no la tienen
    /// Versiones a las que se puede copiar la base: todas las demás (las que ya la tienen también:
    /// se sustituye, con copia antes)
    func copyTargets(_ db: String, _ folder: String) -> [Install] {
        guard let d = data else { return [] }
        return d.installs.filter { $0.folder != folder }
    }

    func hasDb(_ folder: String, _ db: String) -> Bool {
        return (data?.dbs[folder] ?? []).contains(db)
    }

    /// Copia la base, con el mismo nombre, de la versión pulsada a otra (copiar-bd). Siempre se
    /// avisa antes. (Con otro nombre o con otra carpeta: Replicar, en Cargar proyecto)
    func copyDb(_ db: String, _ folder: String) {
        // (primero las que no la tienen; dentro, de la más nueva a la más antigua)
        let targets = copyTargets(db, folder).sorted { a, b in
            let ha = hasDb(a.folder, db), hb = hasDb(b.folder, db)
            if ha != hb { return !ha }
            return a.php.compare(b.php, options: .numeric) == .orderedDescending
        }
        guard !targets.isEmpty, let src = data?.installs.first(where: { $0.folder == folder }) else { return }
        let alert = NSAlert()
        alert.messageText = "¿A qué versión de PHP copias \(db)?"
        alert.addButton(withTitle: "Copiar la BBDD")
        alert.addButton(withTitle: "Cancelar")
        let group = RadioGroup()
        var options: [NSView] = []
        var views: [NSView] = [dialogLabel("Se copia con el mismo nombre; la de XAMPP-\(folder) no se toca. Con otro nombre o carpeta: Replicar (Proyectos, Añadir entorno).", color: .secondaryLabelColor)]
        for (n, i) in targets.enumerated() {
            let active = i.folder == data?.active ? "  ·  la activa" : ""
            let has = hasDb(i.folder, db) ? "  ·  ya la tiene: se sustituye" : ""
            let b = NSButton(radioButtonWithTitle: "PHP \(i.php)  (XAMPP-\(i.folder))" + active + has,
                             target: group, action: #selector(RadioGroup.pick(_:)))
            b.state = n == 0 ? .on : .off
            group.buttons.append(b)
            options.append(b)
        }
        views.append(dialogOptions(options))
        alert.accessoryView = dialogStack(views, spacing: 14)
        guard alert.runStyled() == .alertFirstButtonReturn else { return }
        let chosen = targets[group.buttons.firstIndex(where: { $0.state == .on }) ?? 0]
        let dst = chosen.folder
        var args = ["copiar-bd", db, folder, dst]
        var notes = ["De XAMPP-\(folder) (PHP \(src.php)) a XAMPP-\(dst) (PHP \(chosen.php)), con el mismo nombre. La de XAMPP-\(folder) no se toca."]
        if dst != data?.active {
            notes.append("XAMPP-\(dst) no es la activa: su MariaDB se arranca solo para la copia (pide la contraseña de administrador).")
        }
        let replace = hasDb(dst, db)
        if replace {
            notes.append("XAMPP-\(dst) ya tiene \(db): se sustituye. Lo que tenía se pierde, salvo que guardes antes una copia.")
            args.append("--sustituir")
        }
        if replace {
            let c = confirmCopy("¿Sustituir \(db) en XAMPP-\(dst)?", "", "Sustituir \(db)", destructive: true, steps: notes)
            if !c.ok { return }
            if c.copy { args.append("--copia") }
        } else {
            guard confirm("¿Copiar \(db) a XAMPP-\(dst)?", "", "Copiar a XAMPP-\(dst)", steps: notes) else { return }
        }
        runTask("Copiando \(db) a XAMPP-\(dst)", args, doneText: "\(db) copiada a XAMPP-\(dst)", autoClose: true)
    }

    /// Replicar un proyecto en otra versión de PHP: copia su BBDD de una versión a otra con el nombre
    /// que se elija (se propone el de la de destino: wp_x_8_4 → wp_x_8_5) y la vincula allí a la
    /// carpeta que se elija (la misma, otra o ninguna)
    func replicate(_ project: Project? = nil) {
        guard let d = data, let p = projects, !busy else { return }
        let list = p.list.filter { !projectPairs($0).isEmpty }
        if list.isEmpty {
            message("No hay proyectos que replicar", "Ningún proyecto de htdocs tiene su BBDD en una versión instalada.")
            return
        }
        if d.installs.count < 2 {
            message("No hay otra versión de PHP", "Instala otra versión de PHP para replicar un proyecto en ella.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Replicar un proyecto en otra versión de PHP"
        alert.addButton(withTitle: "Replicar")
        alert.addButton(withTitle: "Cancelar")
        let okButton = alert.buttons[0]
        let width: CGFloat = 380
        func popup() -> NSPopUpButton {
            let b = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: width, height: 26), pullsDown: false)
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: width).isActive = true
            return b
        }
        func line(_ title: String, _ view: NSView) -> NSView {
            let t = NSTextField(labelWithString: title)
            t.textColor = .secondaryLabelColor
            t.translatesAutoresizingMaskIntoConstraints = false
            t.widthAnchor.constraint(equalToConstant: 130).isActive = true
            let row = NSStackView(views: [t, view])
            row.orientation = .horizontal
            row.spacing = 10
            return row
        }
        let pPop = popup(), sPop = popup(), tPop = popup(), fPop = popup()
        for x in list { pPop.addItem(withTitle: x.name) }
        let field = NSTextField(string: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        let hint = dialogLabel("", color: .secondaryLabelColor, align: .left)
        let folders = p.list.map { $0.name }
        fPop.addItem(withTitle: "— Ninguna: vincúlala después —")
        for f in folders { fPop.addItem(withTitle: f) }
        var pairs: [(Install, String)] = []
        var targets: [Install] = []
        var auto = true, setting = false
        func source() -> (Install, String)? {
            let n = sPop.indexOfSelectedItem
            return n >= 0 && n < pairs.count ? pairs[n] : nil
        }
        func target() -> Install? {
            let n = tPop.indexOfSelectedItem
            return n >= 0 && n < targets.count ? targets[n] : nil
        }
        func update() {
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            let valid = !cleanDbName(name).isEmpty && cleanDbName(name) == name
                && !["information_schema", "mysql", "performance_schema", "phpmyadmin", "sys", "test"].contains(name.lowercased())
            if !valid {
                hint.stringValue = "Letras sin acentos, números, _ y - (sin - delante)."
                hint.textColor = .secondaryLabelColor
            } else if let t = target(), hasDb(t.folder, name) {
                hint.stringValue = "XAMPP-\(t.folder) ya tiene una BBDD \(name): se sustituye (al confirmar puedes guardar antes una copia suya)."
                hint.textColor = .systemRed
            } else {
                hint.stringValue = target().map { "Se crea \(name) en XAMPP-\($0.folder)." } ?? ""
                hint.textColor = .secondaryLabelColor
            }
            okButton.isEnabled = valid && target() != nil && source() != nil
        }
        func onTarget() {
            // (mientras no se escriba otro, el nombre sigue a la versión elegida)
            if let s = source(), let t = target(), auto {
                setting = true
                field.stringValue = copyName(s.1, t.php)
                setting = false
            }
            update()
        }
        func onSource() {
            let s = source()
            tPop.removeAllItems()
            targets = d.installs.filter { s != nil && $0.folder != s!.0.folder }
                .sorted { $0.php.compare($1.php, options: .numeric) == .orderedDescending }
            for i in targets { tPop.addItem(withTitle: "PHP \(i.php)  (XAMPP-\(i.folder))") }
            if !targets.isEmpty { tPop.selectItem(at: 0) }
            onTarget()
        }
        func onProject() {
            let x = list.indices.contains(pPop.indexOfSelectedItem) ? list[pPop.indexOfSelectedItem] : nil
            sPop.removeAllItems()
            pairs = x.map { projectPairs($0).sorted { $0.0.php.compare($1.0.php, options: .numeric) == .orderedDescending } } ?? []
            for (i, db) in pairs { sPop.addItem(withTitle: "PHP \(i.php)  (XAMPP-\(i.folder))  ·  BBDD \(db)") }
            // (la de la versión activa, si la tiene)
            if !pairs.isEmpty { sPop.selectItem(at: pairs.firstIndex(where: { $0.0.folder == d.active }) ?? 0) }
            if let x = x, let n = folders.firstIndex(of: x.name) { fPop.selectItem(at: n + 1) }
            onSource()
        }
        let pAct = DialogValidator(), sAct = DialogValidator(), tAct = DialogValidator(), fieldAct = DialogValidator()
        pAct.update = { onProject() }
        sAct.update = { onSource() }
        tAct.update = { onTarget() }
        fieldAct.update = { if !setting { auto = false }; update() }
        for (pop, act) in [(pPop, pAct), (sPop, sAct), (tPop, tAct)] {
            pop.target = act
            pop.action = #selector(DialogValidator.changed(_:))
        }
        field.delegate = fieldAct
        // (el de la fila desde la que se pide o, si no, el cargado)
        if let x = project ?? loadedEntry(), let n = list.firstIndex(where: { $0.name == x.name }) { pPop.selectItem(at: n) } else { pPop.selectItem(at: 0) }
        onProject()
        let views: [NSView] = [
            dialogLabel("Se copia su BBDD a otra versión, con el nombre y la carpeta que elijas, y Cargar proyecto ya lo monta con ella. La de origen no se toca.", color: .secondaryLabelColor),
            line("Proyecto", pPop), line("Desde", sPop), line("A la versión", tPop),
            line("Nombre de la BBDD", field), line("", hint), line("Carpeta", fPop),
            line("", dialogLabel("La carpeta con la que se carga en esa versión.", color: .secondaryLabelColor, align: .left)),
        ]
        alert.accessoryView = dialogStack(views, spacing: 10)
        alert.window.initialFirstResponder = field
        let resp = alert.runStyled()
        // (los objetos de las acciones viven hasta aquí)
        withExtendedLifetime([pAct, sAct, tAct, fieldAct]) {}
        guard resp == .alertFirstButtonReturn, let s = source(), let t = target() else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, cleanDbName(name) == name else { return }
        let (src, db) = s
        let dst = t.folder
        let fi = fPop.indexOfSelectedItem
        let folder = fi >= 1 && fi <= folders.count ? folders[fi - 1] : ""
        var args = ["copiar-bd", db, src.folder, dst, "--como", name, "--carpeta", folder.isEmpty ? "-" : folder]
        var notes = ["\(db) de XAMPP-\(src.folder) (PHP \(src.php)) se copia a XAMPP-\(dst) (PHP \(t.php)) como \(name), vinculada a \(folder.isEmpty ? "ninguna carpeta" : folder)."]
        if dst != d.active {
            notes.append("XAMPP-\(dst) no es la activa: su MariaDB se arranca solo para la copia (pide la contraseña de administrador).")
        }
        let replace = hasDb(dst, name)
        if replace {
            notes.append("XAMPP-\(dst) ya tiene \(name): se sustituye. Lo que tenía se pierde, salvo que guardes antes una copia.")
            args.append("--sustituir")
        }
        if replace {
            let c = confirmCopy("¿Replicar en XAMPP-\(dst)?", "", "Sustituir y replicar", destructive: true, steps: notes)
            if !c.ok { return }
            if c.copy { args.append("--copia") }
        } else {
            guard confirm("¿Replicar en XAMPP-\(dst)?", "", "Replicar en XAMPP-\(dst)", steps: notes) else { return }
        }
        runTask("Replicando en XAMPP-\(dst)", args, doneText: "\(db) replicada en XAMPP-\(dst) como \(name)", autoClose: true)
    }

    func downloadDb(_ db: String, _ folder: String) {
        guard let d = data else { return }
        let running = d.running && folder == d.active
        let panel = NSSavePanel()
        panel.title = "Descargar la BBDD \(db)"
        panel.prompt = "Descargar"
        panel.allowedContentTypes = fileTypes(["zip"])
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmm"
        panel.nameFieldStringValue = "\(db)-XAMPP-\(folder)-\(stamp.string(from: Date())).zip"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if !running {
            panel.message = "XAMPP-\(folder) no está en marcha: se arranca un MariaDB temporal solo para la copia (pide la contraseña de administrador)."
        }
        if panel.runModal() != .OK { return }
        guard let url = panel.url else { return }
        let start = {
            _ = self.runTask("Descargando \(db)", ["exportar-bd", db, url.path, folder],
                             doneText: "Copia de «\(db)» guardada: \(url.lastPathComponent)",
                             env: running ? self.dbEnv() : [:],
                             cancelText: ("¿Cancelar la descarga?", "No se guarda nada.", "Cancelar la descarga")) { ok, task, _ in
                if ok { task.offer("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
            }
        }
        if running { checkDbAccess(start) } else { start() }
    }

    /// /etc/hosts es de root: se edita una copia en ~/.lvm-instalador y, al pulsar Aplicar, el script
    /// la escribe encima con sudo (guardando antes el anterior en ~/nexum-backups, si está el ajuste)
    func editHosts() {
        let src = (data ?? AppData()).hosts
        let copy = LOG_DIR + "/hosts"
        do {
            try FileManager.default.createDirectory(atPath: LOG_DIR, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: copy) { try FileManager.default.removeItem(atPath: copy) }
            try FileManager.default.copyItem(atPath: src, toPath: copy)
        } catch {
            message("No se ha podido leer \(src)", error.localizedDescription, error: true)
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-t", copy]
        try? p.run()
        guard confirm("Editar hosts",
                      "\(src) es del administrador: se ha abierto una copia en el editor. Guarda los cambios y pulsa «Aplicar los cambios»"
                          + (FileManager.default.fileExists(atPath: COPIES_FILES_FLAG) ? ": el anterior queda en ~/nexum-backups" : "")
                          + ". Pide la contraseña de administrador.",
                      "Aplicar los cambios") else { return }
        if FileManager.default.contentsEqual(atPath: src, andPath: copy) {
            toast("No has cambiado nada en \(src) (¿guardaste los cambios?)")
            return
        }
        _ = runTask("Guardando \(src)", ["hosts", "--aplicar", copy], doneText: "\(src) actualizado", autoClose: true)
    }

    /// Los vhosts son del administrador (Apache los lee como root al arrancar): se edita una copia en
    /// ~/.lvm-instalador y, al pulsar Aplicar, el script la comprueba, la escribe con sudo (guardando
    /// antes la anterior en ~/nexum-backups, si está el ajuste) y recarga Apache. Si Apache no la acepta, se deja como estaba
    func editVhosts() {
        let path = (data ?? AppData()).vhosts
        let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard FileManager.default.fileExists(atPath: real) else {
            message("No se encuentra el fichero de vhosts", "\(path) no existe. Se crea al instalar la primera versión de PHP.", error: true)
            return
        }
        let copy = LOG_DIR + "/httpd-vhosts.conf"
        do {
            try FileManager.default.createDirectory(atPath: LOG_DIR, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: copy) { try FileManager.default.removeItem(atPath: copy) }
            try FileManager.default.copyItem(atPath: real, toPath: copy)
        } catch {
            message("No se ha podido leer \(real)", error.localizedDescription, error: true)
            return
        }
        openInEditor(copy)
        guard confirm("Editar vhosts",
                      "Son del administrador (Apache los lee como root): se ha abierto una copia en el editor. Guarda los cambios y pulsa «Aplicar los cambios»: se comprueban, "
                          + (FileManager.default.fileExists(atPath: COPIES_FILES_FLAG) ? "los de ahora quedan en ~/nexum-backups " : "se escriben ")
                          + "y se recarga Apache. Si Apache no los acepta, se quedan como estaban. Pide la contraseña de administrador.",
                      "Aplicar los cambios") else { return }
        if FileManager.default.contentsEqual(atPath: real, andPath: copy) {
            toast("No has cambiado nada en los vhosts (¿guardaste los cambios?)")
            return
        }
        runTask("Guardando los vhosts", ["vhosts", "--aplicar", copy], doneText: "Vhosts actualizados", autoClose: true)
    }

    func openTerminal() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Terminal", LOG_DIR + "/abrir.command"]
        try? p.run()
    }

    /// Ayuda (menú ☰): el manual, que va dentro del script, en el navegador; en el capítulo de la pestaña abierta
    /// (en Configuración, el de su apartado). Los capítulos son los id de ayuda/index.html
    func showHelp() {
        let tabs = ["proyectos": "proyectos", "repos": "repositorios", "versiones": "versiones", "bbdd": "bbdd",
                    "docker": "docker", "node": "node", "dominios": "dominios", "config": "configuracion"]
        let sections = ["general": "general", "hosts": "vhosts", "seguridad": "seguridad-webs", "correo": "correo",
                        "docker": "docker-config", "tunel": "tunel-config", "apariencia": "apariencia",
                        "github": "github-config", "limpieza": "limpieza", "carpetas": "carpetas",
                        "oficial": "configuracion-xampp-oficial", "info": "informacion"]
        var chapter = tabs[tab] ?? "ventana"
        if tab == "config" { chapter = sections[toolsSection] ?? chapter }
        runQuick(["manual", "--ruta", chapter]) { code, out in
            let path = out.split(separator: "\n").last.map(String.init) ?? ""
            if code == 0 && path.hasPrefix("/") && FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            } else {
                showLongText("No se ha podido abrir el manual", out.isEmpty ? "Error al sacar el manual." : out)
            }
        }
    }

    func showChanges() {
        runQuick(["novedades"]) { _, out in showLongText("Novedades", out, markdown: true) }
    }

    func showAbout() {
        let d = data ?? AppData()
        let alert = NSAlert()
        alert.messageText = d.name
        alert.addButton(withTitle: "Cerrar")
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        let lines: [(String, NSFont, NSColor)] = [
            ("Versión \(d.version)", NSFont.systemFont(ofSize: NSFont.systemFontSize), .secondaryLabelColor),
            ("Herramientas de desarrollo web en local.",
             NSFont.systemFont(ofSize: NSFont.systemFontSize + 1), .labelColor),
            ("\(d.signature)\n© \(Calendar.current.component(.year, from: Date()))",
             NSFont.systemFont(ofSize: NSFont.systemFontSize), .secondaryLabelColor),
        ]
        for (text, font, color) in lines {
            let l = dialogLabel(text, font: font, color: color)
            l.translatesAutoresizingMaskIntoConstraints = false
            l.widthAnchor.constraint(equalToConstant: DIALOG_WIDTH).isActive = true
            stack.addArrangedSubview(l)
        }
        stack.layoutSubtreeIfNeeded()
        stack.frame = NSRect(x: 0, y: 0, width: DIALOG_WIDTH, height: stack.fittingSize.height)
        alert.accessoryView = stack
        NSApp.activate(ignoringOtherApps: true)
        alert.runStyled()
    }
}
