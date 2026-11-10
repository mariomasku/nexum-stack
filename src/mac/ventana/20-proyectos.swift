// MARK: - Proyectos

/// Registro de errores del vhost de los proyectos (web.local), sacado de su ErrorLog: con PHP-FPM,
/// los errores de PHP de la web cargada van ahí y no al error_log general de Apache
func projectErrorLogPath(link: String, vhosts: String) -> String? {
    guard !link.isEmpty else { return nil }
    let text = (try? String(contentsOfFile: vhosts, encoding: .utf8)) ?? ""
    let ns = text as NSString
    let blocks = (try? NSRegularExpression(pattern: "(?is)<VirtualHost\\b[^>]*>(.*?)</VirtualHost>"))?
        .matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []
    for b in blocks {
        let body = ns.substring(with: b.range(at: 1))
        let bns = body as NSString
        let names = ((try? NSRegularExpression(pattern: "(?im)^[ \\t]*Server(?:Name|Alias)[ \\t]+(.+)$"))?
            .matches(in: body, range: NSRange(location: 0, length: bns.length)) ?? [])
            .flatMap { bns.substring(with: $0.range(at: 1)).lowercased().split(separator: " ").map(String.init) }
        if names.contains(link.lowercased()),
           let e = (try? NSRegularExpression(pattern: "(?im)^[ \\t]*ErrorLog[ \\t]+\"?([^\"\\s]+)\"?"))?
            .firstMatch(in: body, range: NSRange(location: 0, length: bns.length)) {
            let path = bns.substring(with: e.range(at: 1))
            if path.hasPrefix("|") || path.hasPrefix("syslog") { continue }
            return path.hasPrefix("/") ? path : "/Applications/XAMPP/xamppfiles/" + path
        }
    }
    // (sin ErrorLog propio, sus errores van al general: no hay otro registro que enseñar)
    let path = "/Applications/XAMPP/xamppfiles/logs/\(link)-error_log"
    return FileManager.default.fileExists(atPath: path) ? path : nil
}

/// Actualizar proyecto: la BBDD y el código de producción, arrastrados o elegidos
struct UpdateProjectSheet: View {
    @EnvironmentObject var model: AppModel
    @State private var overSql = false
    @State private var overCode = false

    var body: some View {
        let dbOk = validDbName(model.upDb.trimmingCharacters(in: .whitespaces))
        let can = (!model.upSql.isEmpty || !model.upCode.isEmpty) && (model.upSql.isEmpty || dbOk) && !model.busy
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Actualizar proyecto").font(.headline)
                Text(model.upFolder).font(.caption).foregroundColor(.secondary)
            }
            zone("Base de datos de producción", ".sql, .sql.gz o .zip", symbol: "cylinder.split.1x2", path: model.upSql, error: model.upSqlError,
                 over: $overSql, code: false, folders: false)
            // (sin fichero de BBDD no se toca: se sigue usando la misma)
            if model.upDbKnown || !model.upSql.isEmpty {
                HStack(spacing: 8) {
                    Text(model.upSql.isEmpty ? "Se sigue usando la BBDD" : "Se carga en la BBDD").foregroundColor(.secondary)
                    // (su nombre, como texto; solo si el proyecto no tiene ninguna hay que escribirlo)
                    if model.upDbKnown {
                        Text(model.upDb).fontWeight(.bold).foregroundColor(.blue)
                    } else {
                        TextField("", text: $model.upDb).frame(width: 220)
                    }
                    if !model.upSql.isEmpty {
                        Text("(al confirmar, puedes guardar antes una copia de la actual)").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            zone("Código de producción", ".zip, .tar.gz o carpeta", symbol: "folder", path: model.upCode, error: model.upCodeError,
                 over: $overCode, code: true, folders: true)
            // Qué hacer con la carpeta: siempre a la vista, para saber lo que va a pasar
            VStack(alignment: .leading, spacing: 6) {
                Picker("", selection: $model.upMode) {
                    Text("Fusionar: copia lo que trae y deja lo demás de la carpeta").tag("fusionar")
                    Text("Sobrescribir: además borra lo que no traiga").tag("sobrescribir")
                }
                .pickerStyle(RadioGroupPickerStyle())
                .labelsHidden()
                Text("Se escribe sobre \(HTDOCS)/\(model.upFolder). Su .git no se toca; lo sustituido o borrado solo se puede recuperar si al confirmar guardas antes una copia en ~/nexum-backups.")
                    .font(.caption).foregroundColor(RED).fixedSize(horizontal: false, vertical: true)
            }
            .disabled(model.upCode.isEmpty)
            HStack {
                Spacer()
                Button("Cancelar") { model.upShown = false }.buttonStyle(OutlineButton(big: true))
                Button("Actualizar…") { model.upAsk() }
                    .buttonStyle(OutlineButton(kind: "primary", big: true))
                    .disabled(!can)
            }
        }
        .padding(22)
        .frame(width: 640)
    }

    func zone(_ title: String, _ formats: String, symbol: String, path: String, error: String, over: Binding<Bool>, code: Bool, folders: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(!error.isEmpty ? error : (path.isEmpty ? "Arrástralo aquí: \(formats)" : path))
                    .font(.caption).foregroundColor(!error.isEmpty ? RED : .secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if !path.isEmpty {
                Button(action: { model.upSet(code: code, "") }) { Image(systemName: "xmark.circle") }
                    .buttonStyle(LinkHoverButton())
                    .tip("Quitar")
            }
            Button("Elegir fichero…") { model.upPick(code: code, folder: false) }
            if folders {
                Button("Elegir carpeta…") { model.upPick(code: code, folder: true) }
            }
        }
        .padding(.horizontal, 20)
        // (alta: es donde se suelta, tiene que verse bien)
        .frame(minHeight: 112)
        .background(RoundedRectangle(cornerRadius: 12).fill(over.wrappedValue ? Color.blue.opacity(0.30)
                                                            : !path.isEmpty ? Color.blue.opacity(0.10) : Color.primary.opacity(0.06)))
        // (el recuadro azul, solo con algo incorporado o al arrastrar encima)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(over.wrappedValue || !path.isEmpty ? Color.blue : Color.primary.opacity(0.28),
                    style: StrokeStyle(lineWidth: 2, dash: over.wrappedValue || !path.isEmpty ? [] : [5])))
        .onDrop(of: [UTType.fileURL], isTargeted: over) { providers in
            guard let item = providers.first else { return false }
            _ = item.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    DispatchQueue.main.async { model.upSet(code: code, url.path) }
                }
            }
            return true
        }
    }
}

struct ProjectsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        // (al menos tan ancha como la tabla de proyectos: si no, se aprietan el proyecto cargado y la tabla)
        // (el visor y la cabecera de la lista, fijos arriba: solo la tabla se desplaza)
        SplitPage(width: Swift.max(980, model.projectsTableWidth), top: model.scrollTop, head: {
            if let p = model.projects, let d = model.data {
                hero(p, d)
                listHead()
            }
        }, content: {
            if let p = model.projects, model.data != nil {
                projectTable(p)
                Text(plural(p.list.count, "proyecto", "proyectos") + " en \(HTDOCS)")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Loading()
            }
        })
        .sheet(isPresented: $model.upShown) {
            UpdateProjectSheet().environmentObject(model).buttonStyle(PointerButtonStyle())
        }
    }

    // MARK: el proyecto de arriba

    /// Arriba, siempre el cargado, con sus botones: elegir otro en la lista no lo cambia. Sin ninguno
    /// cargado, el elegido
    func shown(_ p: ProjectsData) -> Project? {
        if let x = model.loadedEntry() { return x }
        if let n = model.selProject, let x = p.list.first(where: { $0.name == n }) { return x }
        return nil
    }

    func hero(_ p: ProjectsData, _ d: AppData) -> some View {
        let x = shown(p)
        let loadedName = model.loadedEntry()?.name
        let isLoaded = x != nil && x?.name == loadedName
        let current = ((p.current) as NSString).lastPathComponent
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusDot(on: isLoaded, blink: false)
                Text(isLoaded ? "PROYECTO CARGADO" : (x != nil ? "PROYECTO ELEGIDO" : "NINGÚN PROYECTO CARGADO"))
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                Spacer()
                // (el correo de la web cargada va a Mailpit: discreto, al lado)
                if isLoaded, let m = d.mail, m.on, m.installed {
                    HStack(spacing: 4) {
                        LogoShape(d: LOGO_PATHS["mailpit"] ?? "").fill(Color.secondary).frame(width: 12, height: 12)
                        Text("su correo va a Mailpit").font(.caption).foregroundColor(.secondary)
                    }
                    .tip(mailHint(x, m))
                    .padding(.trailing, 8)
                }
                if !p.link.isEmpty {
                    Text(isLoaded ? "en \(p.link)" : "\(p.link) → \(current.isEmpty ? "nada" : current)")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            heroCard(x, isLoaded, p, d)
            if let warn = projectWarning(p, d) {
                Text(warn).font(.callout.weight(.semibold)).foregroundColor(RED)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func mailHint(_ x: Project?, _ m: MailState) -> String {
        let base = "Se ve en Correo, arriba"
        return base
    }

    func heroCard(_ x: Project?, _ isLoaded: Bool, _ p: ProjectsData, _ d: AppData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let x = x {
                HStack(alignment: .center, spacing: 18) {
                    // (el logotipo solo, sin recuadro: con el visor de la derecha más alto, se estiraba)
                    KindIcon(kind: x.kind, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            // (los nombres largos, en dos líneas, no cortados)
                            Text(x.name).font(.system(size: 22, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                            if x.kind == "wp" {
                                SmallTag(text: "WordPress")
                            } else if x.kind == "ps" {
                                SmallTag(text: "PrestaShop")
                            }
                        }
                        Text("\(HTDOCS)/\(x.name)").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 12)
                    envBox(x, isLoaded, d)
                }
                Divider()
                actions(x, isLoaded, p)
            } else {
                Text("Elige un proyecto de la lista para cargarlo.").foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }

    /// El entorno (versión de PHP o Docker) y su BBDD, en un recuadro hundido. Elegir otro entorno lo
    /// carga en esa versión (o lleva a Docker)
    func envBox(_ x: Project, _ isLoaded: Bool, _ d: AppData) -> some View {
        let pairs = model.projectPairs(x)
        var envs: [(String, String, String)] = pairs.map { ("x:" + $0.0.folder, "PHP \($0.0.php) · XAMPP-\($0.0.folder)", $0.1) }
        envs += model.dockerOf(x.name).map { ("d:" + $0.slug, "PHP \($0.php) · Docker", $0.db) }
        let active = pairs.first(where: { $0.0.folder == d.active }).map { "x:" + $0.0.folder }
        let current = (isLoaded ? active : nil) ?? envs.first?.0 ?? ""
        let db = envs.first(where: { $0.0 == current })?.2 ?? ""
        return VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .bottom, spacing: 12) {
            // Llevarlo a otro entorno: el +, a la izquierda del entorno (su SQL se importa en la
            // pestaña Bases de datos; la fila de abajo queda para los accesos directos del proyecto)
            OutlineMenu(nil, symbol: "plus") {
                Button("En otra versión de PHP (copiar su BBDD)…") { model.replicate(x) }
                Button("En Docker…") { model.openDockerForm(folder: x.name) }
            }
            .disabled(model.busy)
            .tip("Añadir entorno")
            VStack(alignment: .leading, spacing: 4) {
                Text("Entorno (versión de PHP)").font(.caption).foregroundColor(.secondary)
                SearchPicker(selection: Binding(get: { current }, set: { model.chooseEnv(x, $0) }),
                             items: envs.isEmpty ? [("", "Sin entornos")] as [(String, String)] : envs.map { ($0.0, $0.1) })
                .disabled(envs.isEmpty || model.busy)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("BBDD").font(.caption).foregroundColor(.secondary)
                Text(db.isEmpty ? "—" : db).font(.system(size: 12.5, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(width: 170, alignment: .leading)
                    .padding(.vertical, 3)
            }
            Button(action: { model.linkProject(x) }) { Image(systemName: "link") }
                .buttonStyle(LinkHoverButton())
                .disabled(model.busy || model.data == nil)
                .tip("Vincular su BBDD")
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(SoftSunken())
    }

    func actions(_ x: Project, _ isLoaded: Bool, _ p: ProjectsData) -> some View {
        HStack(spacing: 8) {
            if isLoaded {
                loadedButtons(x, p)
            } else {
                Button(action: { model.loadFolder(x) }) { Label("Cargar", systemImage: "play.fill") }
                    .buttonStyle(OutlineButton(kind: "primary"))
                    .disabled(model.busy)
                    .tip("Cargar \(x.name)")
            }
            Spacer(minLength: 8)
            // Si su carpeta tiene un dominio en los vhosts: falsearlo o dejar de falsearlo desde aquí,
            // como en Dominios y hosts
            if isLoaded {
                ForEach(model.projectHosts(x.name), id: \.name) { h in
                    HStack(spacing: 10) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(h.fake ? "Host falseado" : "Falsear Host")
                            Text(h.name).font(.caption).foregroundColor(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Toggle("", isOn: Binding(get: { h.fake }, set: { model.setHostFake(h, $0) }))
                            .toggleStyle(SwitchToggleStyle()).labelsHidden().tint(GREEN)
                            .disabled(model.busy)
                    }
                    .padding(.trailing, 6)
                    .tip(h.fake ? "Host falseado" : "Falsear Host")
                }
            }
            // (⋮, pegado a la derecha)
            moreMenu(x, square: isLoaded)
        }
    }

    /// Botones del proyecto cargado, con sus logotipos (los que se ven, en su orden y con su estilo:
    /// Botones del proyecto) y, siempre, desmontar
    @ViewBuilder
    func loadedButtons(_ x: Project, _ p: ProjectsData) -> some View {
        let c = model.visorConf
        let items = loadedItems(x, p, c)
        ForEach(c.order.filter { !c.hidden.contains($0) && items[$0] != nil }, id: \.self) { k in
            items[k]!
        }
        if c.square {
            VisorButton(conf: c, name: "Desmontar", icon: .symbol("eject.fill", Color.secondary),
                        tip: "Desmontar el proyecto") {
                model.unloadProject()
            }
            .disabled(model.busy)
        } else {
            Button(action: { model.unloadProject() }) { Image(systemName: "eject.fill") }
                .buttonStyle(LinkHoverButton())
                .disabled(model.busy)
                .tip("Desmontar el proyecto")
        }
    }

    /// Los botones que se pueden ordenar y ocultar del proyecto cargado, por su clave
    func loadedItems(_ x: Project, _ p: ProjectsData, _ c: VisorConf) -> [String: AnyView] {
        let folder = loadedProjectFolder(p.current)
        let db = cleanDbName(model.loadedDb(x))
        let admin = folder.map { projectAdmin($0) } ?? ("", "")
        let link = p.link
        var items: [String: AnyView] = [:]
        items["web"] = AnyView(VisorButton(conf: c, name: "Abrir web", icon: .symbol("globe", Color.blue),
                                           tip: "Abrir http://\(link)/") { openURL("http://\(link)/") })
        if let code = vscodeURL(), let f = folder {
            items["vscode"] = AnyView(VisorButton(conf: c, name: "VS Code", icon: .image(NSWorkspace.shared.icon(forFile: code.path)),
                                                  tip: "Abrir en Visual Studio Code") {
                openInVSCode(f)
            })
        }
        items["pma"] = AnyView(VisorButton(conf: c, name: "phpMyAdmin", icon: .logo("phpmyadmin"),
                                           tip: db.isEmpty ? "Sin BBDD" : "Abrir \(db) en phpMyAdmin") {
            openURL("http://127.0.0.1/phpmyadmin/index.php?route=/database/structure&db=\(db)")
        }.disabled(db.isEmpty))
        items["panel"] = AnyView(VisorButton(conf: c, name: "Panel", icon: .logo(admin.0 == "ps" ? "prestashop" : "wordpress"),
                                             tip: admin.1.isEmpty ? "No tiene panel de administración"
                                                : "Abrir el panel de administración") {
            openProjectAdmin(kind: admin.0, admin: admin.1, link: link, db: db, folder: folder)
        }.disabled(admin.1.isEmpty))
        items["docker"] = AnyView(VisorButton(conf: c, name: "Docker", icon: .logo("docker"),
                                              tip: model.dockerOf(x.name).isEmpty ? "Montar en Docker"
                                                : "Arrancar en Docker") {
            model.dockerForLoaded(x)
        }.disabled(model.busy))
        items["compartir"] = AnyView(model.shareButton("http://\(link)", folder: HTDOCS + "/" + x.name, name: x.name, conf: c)
            .disabled(model.busy))
        // El registro general de Apache: lo primero que se mira con un error (el del vhost, en Herramientas)
        let hasLog = FileManager.default.fileExists(atPath: ERROR_LOG)
        items["log"] = AnyView(VisorButton(conf: c, name: "Log", icon: .logo("log"),
                                           tip: hasLog ? "Ver el log de Apache" : "Aún no hay log de Apache") {
            model.showLogTail(ERROR_LOG)
        }.disabled(!hasLog))
        items["actualizar"] = AnyView(VisorButton(conf: c, name: "Actualizar", icon: .logo("actualizar"),
                                                  tip: "Actualizar proyecto") {
            model.upOpen(x)
        }.disabled(model.busy))
        if x.kind == "wp" || x.kind == "ps" {
            items["imagenes"] = AnyView(VisorButton(conf: c, name: "Importar", icon: .logo("imagenes"),
                                                    tip: "Importar imágenes de producción") {
                model.importImages(x)
            }.disabled(model.busy))
        }
        return items
    }

    /// Opciones del menú ⋮ de un proyecto
    func moreItems(_ x: Project) -> [(String, () -> Void)] {
        let db = model.projectBase(x)
        var items: [(String, () -> Void)] = [("Vincular la BBDD de cada versión…", { model.linkProject(x) }),
                                             ("Abrir la carpeta", { showFolder(HTDOCS + "/" + x.name) })]
        for dp in model.dockerOf(x.name) {
            items.append(("Eliminar de Docker…", { model.dockerDelete(dp) }))
        }
        if x.kind == "ps" && !db.isEmpty {
            items.append(("Vaciar la caché de la tienda", { model.clearCache(db) }))
        }
        items.append(("Limpiar proyecto…", { model.cleanProject(x) }))
        if x.kind == "ps" {
            items.append(("Descargar de producción las imágenes que faltan…", { model.psImages(x) }))
        } else if x.kind == "wp" {
            items.append(("Imágenes de producción…", { model.wpMedia(x) }))
        }
        items.append(("Personalizar los botones…", { model.panel = .buttons }))
        items.append(("Borrar el proyecto…", { model.deleteProject(x) }))
        return items
    }

    /// ⋮ (con un proyecto cargado y los botones cuadrados, del mismo tamaño que los demás)
    @ViewBuilder
    func moreMenu(_ x: Project, square: Bool = false) -> some View {
        let items = moreItems(x)
        if square && model.visorConf.square {
            VisorButton(conf: model.visorConf, name: "Más", icon: .symbol("ellipsis", Color.primary), tip: "Más") {
                popMenu(items)
            }
            .disabled(model.busy)
        } else {
            OutlineMenu(nil, symbol: "ellipsis") {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    Button(it.0) { it.1() }
                }
            }
            .disabled(model.busy)
        }
    }

    /// Aviso en rojo: la versión montada no tiene la BBDD del proyecto cargado
    func projectWarning(_ p: ProjectsData, _ d: AppData) -> String? {
        let current = (p.current as NSString).lastPathComponent
        guard !current.isEmpty, !d.active.isEmpty else { return nil }
        guard let entry = p.list.first(where: { $0.name == current }) else { return nil }
        let db: String = cleanDbName(model.loadedDb(entry))
        let pairs = model.projectPairs(entry)
        if db.isEmpty || pairs.contains(where: { $0.0.folder == d.active }) || (d.dbs[d.active] ?? []).contains(db) { return nil }
        let other = pairs.map { "XAMPP-\($0.0.folder) (\($0.1))" }
        return "El proyecto vinculado a \(p.link) no está disponible para esa versión: XAMPP-\(d.active) no tiene su BBDD \(db)"
            + (other.isEmpty ? "." : " (está en \(other.joined(separator: ", ")); vuelve a cargarlo para cambiar de versión).")
    }

    // MARK: la lista

    func listHead() -> some View {
        HStack(spacing: 10) {
            PageTitle(title: "Proyectos", sub: "")
            Spacer(minLength: 8)
            SearchField(text: $model.projQuery, placeholder: "Buscar proyecto o BBDD").frame(width: 220)
            SearchPicker(selection: $model.projKind,
                         items: [("all", "Todos"), ("wp", "WordPress"), ("ps", "PrestaShop"), ("", "Otros")], width: 120)
            // (en azul, como «Nueva BBDD…»: el asistente de clonar de git, con su versión y su BBDD)
            Button(action: { model.newProject(true) }) { Label("Nuevo proyecto…", systemImage: "plus") }
                .buttonStyle(OutlineButton(kind: "primary"))
                .disabled(model.busy)
                .tip("Clonar y montar un repositorio")
        }
        .padding(.top, 10)
    }

    /// Busca por el nombre de la carpeta o por el de cualquiera de sus BBDD («tienda» encuentra
    /// wordpress-ejemplo, cuya BBDD es wp_tienda)
    func shows(_ x: Project, _ q: String) -> Bool {
        if model.projKind != "all" && x.kind != model.projKind { return false }
        if q.isEmpty || x.name.lowercased().contains(q) || x.db.lowercased().contains(q) { return true }
        if model.projectPairs(x).contains(where: { $0.1.lowercased().contains(q) }) { return true }
        return model.dockerOf(x.name).contains { $0.db.lowercased().contains(q) }
    }

    func projectTable(_ p: ProjectsData) -> some View {
        let loaded = model.loadedEntry()?.name
        let q = model.projQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let rows = p.list.filter { shows($0, q) }
        // (la columna Proyecto, tan ancha como el nombre más largo: se ve entero)
        let nameW = model.projectNameWidth()
        return TableBox {
            TableHead(cols: [("", 20), ("Proyecto", nameW), ("Tamaño", 80), ("BBDD", 190), ("Versiones", 0), ("", 90)])
            LazyVStack(spacing: 0) {
                ForEach(rows, id: \.name) { x in
                    Divider()
                    projectRow(x, x.name == loaded, nameW)
                }
            }
            if rows.isEmpty {
                Divider()
                Text(q.isEmpty ? "No hay proyectos en htdocs" : "Ningún proyecto con «\(q)» en su nombre o en el de su BBDD")
                    .foregroundColor(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    func projectRow(_ x: Project, _ isLoaded: Bool, _ nameW: CGFloat) -> some View {
        let pairs = model.projectPairs(x)
        let db = pairs.first?.1 ?? model.projectBase(x)
        let dockers = model.dockerOf(x.name)
        // (con algún proyecto en Docker, hueco para «Montar en Docker»: las filas no cambian de ancho)
        let anyDocker = !(model.docker?.projects.isEmpty ?? true)
        return HoverRow(selected: isLoaded || model.selProject == x.name, action: { model.selProject = x.name }) { hover in
            KindIcon(kind: x.kind).col(20)
            Text(x.name).lineLimit(1).col(nameW).tip(x.name)
            Text(model.projectSizes[x.name].map { fmtSize($0[0]) } ?? "…")
                .font(.system(size: 11.5, design: .monospaced)).foregroundColor(.secondary).lineLimit(1).col(80)
                .tip(model.projectSizes[x.name].map { "Tamaño en disco, medido " + fmtAge(max(0, Int(Date().timeIntervalSince1970) - Int($0[1]))) }
                     ?? "Midiendo lo que ocupa en el disco…")
            Text(db.isEmpty ? "sin BBDD" : db).font(.system(size: 11.5, design: .monospaced)).foregroundColor(.secondary)
                .lineLimit(1).truncationMode(.middle).col(190)
            HStack(spacing: 4) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pr in
                    Chip(text: shortPhp(pr.0.php)).tip("XAMPP-\(pr.0.folder) · \(pr.1)")
                }
                ForEach(dockers) { dp in
                    Chip(text: "Docker \(dp.php)", docker: true).tip("https://\(dp.domain) · \(dp.db)")
                }
            }
            // (cada etiqueta en una línea: nunca «8», «.», «5» una encima de otra)
            .fixedSize()
            .col(0)
            HStack {
                Spacer(minLength: 0)
                // Al pasar el ratón: Montar en Docker (si tiene contenedores: con varios pregunta cuál),
                // Cargar y su menú ⋮
                if !dockers.isEmpty {
                    Button(action: { model.dockerForLoaded(x) }) {
                        HStack(spacing: 5) {
                            LogoShape(d: LOGO_PATHS["docker"] ?? "").fill(brand("docker")).frame(width: 14, height: 14)
                            Text("Montar en Docker").lineLimit(1)
                        }
                    }
                    .buttonStyle(OutlineButton(compact: true))
                    .disabled(model.busy)
                    .tip("Arrancar \(x.name) en Docker")
                    .opacity(hover ? 1 : 0)
                    .allowsHitTesting(hover)
                }
                if isLoaded {
                    SmallTag(text: "Cargado", blue: true)
                } else {
                    // «Cargar» solo al pasar el ratón por el proyecto (el hueco se guarda: la fila no salta)
                    Button("Cargar") { model.loadFolder(x) }
                        .buttonStyle(OutlineButton(kind: "primary", compact: true))
                        .disabled(model.busy)
                        .opacity(hover ? 1 : 0)
                        .allowsHitTesting(hover)
                    // (lo que antes solo se hacía arriba con el proyecto elegido, sin cambiar el de arriba)
                    OutlineMenu(nil, symbol: "ellipsis") {
                        Button("Añadir entorno en otra versión de PHP…") { model.replicate(x) }
                        Button("Añadir entorno en Docker…") { model.dockerForLoaded(x) }
                        Button("Importar SQL…") { model.importFor(x) }
                        Button("Vincular la BBDD de cada versión…") { model.linkProject(x) }
                        Button("Abrir la carpeta") { showFolder(HTDOCS + "/" + x.name) }
                        ForEach(model.dockerOf(x.name)) { dp in
                            Button("Eliminar de Docker…") { model.dockerDelete(dp) }
                        }
                        if x.kind == "ps" && !model.projectBase(x).isEmpty {
                            Button("Vaciar la caché de la tienda") { model.clearCache(model.projectBase(x)) }
                        }
                        Button("Limpiar proyecto…") { model.cleanProject(x) }
                        if x.kind == "ps" {
                            Button("Descargar de producción las imágenes que faltan…") { model.psImages(x) }
                        } else if x.kind == "wp" {
                            Button("Imágenes de producción…") { model.wpMedia(x) }
                        }
                        Button("Borrar el proyecto…") { model.deleteProject(x) }
                    }
                    .disabled(model.busy)
                    .opacity(hover ? 1 : 0)
                    .allowsHitTesting(hover)
                }
            }
            .frame(width: anyDocker ? 270 : 130)
        }
    }
}
