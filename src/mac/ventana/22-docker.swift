// MARK: - Docker

struct DockerView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        WidePage {
            if let k = model.docker {
                header(k)
                if k.ready {
                    ready(k)
                } else {
                    notReady(k)
                }
            } else {
                Loading(text: "Comprobando Docker…")
            }
        }
    }

    func header(_ k: DockerData) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                // (de título, el logotipo de Docker: la ballena y sus letras, en su color)
                BrandImage(key: "docker", height: 34)
                Text(k.ready ? "Docker Desktop \(k.version) · los contenedores van en su máquina virtual, apartados del Mac"
                     : "Docker Desktop · proyectos con cualquier versión de PHP, a la vez que XAMPP-X")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            if k.ready {
                // Parar todo lo de Nexum de una vez (proyectos, MariaDB comunes y el Apache de Docker)
                let running = k.containers.filter { $0.state == "running" && ownContainer($0.name) }.count
                Button(action: { model.dockerStopAll() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill").foregroundColor(RED)
                        Text("Parar todos")
                    }
                }
                .buttonStyle(OutlineButton())
                .disabled(running == 0 || model.busy)
                .tip(running > 0 ? "Parar \(running) contenedores de Nexum"
                     : "No hay ningún contenedor de Nexum en marcha")
                Button(action: { model.openDockerForm(folder: nil) }) { Label("Proyecto en Docker…", systemImage: "plus") }
                    .buttonStyle(OutlineButton(kind: "primary"))
                    .disabled(model.busy)
            }
        }
    }

    func notReady(_ k: DockerData) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Card("Docker Desktop",
                 "Cada proyecto en Docker lleva su propio PHP (cualquier versión), su MariaDB con una copia de su BBDD y su phpMyAdmin, en contenedores de Docker Desktop. Se abre por su dominio (carpeta.docker.local) desde el Apache de la versión activa, que lo pasa a la web del contenedor (con sus .htaccess): XAMPP-X y Docker funcionan a la vez.") {
                if !k.installed && !k.app {
                    Row("Docker Desktop no está instalado",
                        "En el Mac no se instala desde aquí: se descarga de docker.com y se instala como cualquier aplicación.",
                        leading: { StatusDot(on: false) }, trailing: {
                        Button("Instalar Docker…") { model.dockerInstall() }
                            .buttonStyle(OutlineButton(kind: "primary"))
                        Button("Comprobar") { model.reloadDocker(stats: true) }
                            .buttonStyle(OutlineButton())
                    })
                } else {
                    Row("Docker Desktop no está en marcha",
                        "Está instalado pero no responde. Al abrirlo, la primera vez pide aceptar su licencia.",
                        leading: { StatusDot(on: false) }, trailing: {
                        Button("Abrir Docker Desktop") { model.dockerInstall() }
                            .buttonStyle(OutlineButton(kind: "primary"))
                            .disabled(model.busy)
                        Button("Comprobar") { model.reloadDocker(stats: true) }
                            .buttonStyle(OutlineButton())
                    })
                }
            }
            sharingNote()
        }
    }

    func sharingNote() -> some View {
        Text("Docker Desktop solo deja a los contenedores usar las carpetas de su lista (Settings › Resources › File sharing), y /Library no está: añade \(HTDOCS) y pulsa Apply. Los proyectos nuevos van con el Apache de Docker (en 127.0.0.2: sin XAMPP-X y con varias versiones de PHP a la vez); su BBDD, en una MariaDB común, y su phpMyAdmin, en https://pma.docker.local (o pma.docker.test, con el DNS de Docker de Configuración; la llave de su fila copia la contraseña). Los de antes siguen con XAMPP-X delante hasta que los pasas.")
            .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    func ready(_ k: DockerData) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            // (solo con proyectos de antes: los del Apache de Docker no necesitan XAMPP-X)
            if !k.xampp && k.projects.contains(where: { !$0.isWeb }) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("La versión XAMPP-X activa está parada")
                        Text("Los proyectos en Docker de antes se abren por su Apache (los del Apache de Docker, no).").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Arrancarla") { model.power() }.buttonStyle(OutlineButton()).disabled(model.busy)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            }
            let old = k.projects.filter { $0.old }
            if !old.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(RED)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("PHP-FPM abierto en 127.0.0.1: " + old.map { $0.folder }.joined(separator: ", "))
                        Text("Sin clave: cualquier programa del Mac puede ejecutar PHP con él. Se cierra solo al arrancarlos, o ahora.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Cerrarlo") { model.dockerMigrateAll() }.buttonStyle(OutlineButton(kind: "primary")).disabled(model.busy)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(RED.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(RED.opacity(0.3), lineWidth: 1))
            }
            webStrip(k)
            cards(k)
            tools()
            if model.dkView == "img" {
                imagesTable(k)
            } else if model.dkView == "vol" {
                volumesTable(k)
            } else {
                containersTable(k)
            }
            Text("Para llevar un proyecto a Docker: «Proyecto en Docker…» o, en Proyectos, «Añadir entorno».")
                .font(.caption).foregroundColor(.secondary)
            sharingNote()
        }
    }

    /// El Apache de Docker: si está en marcha, su dirección y arrancarlo o pararlo; si su dirección aún no
    /// está en este Mac, el aviso con «Permitir»
    @ViewBuilder
    func webStrip(_ k: DockerData) -> some View {
        if let w = k.web, !w.ok || w.state != "nuevo" {
            HStack(spacing: 10) {
                if w.ok {
                    StatusDot(on: w.state == "marcha", size: 8)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(!w.ok ? "La dirección \(w.ip) del Apache de Docker aún no está en este Mac"
                         : (w.state == "marcha" ? "Apache de Docker en marcha" : "Apache de Docker parado"))
                    Text(!w.ok ? "macOS solo tiene 127.0.0.1: se da de alta una vez (pide la contraseña) y queda puesta en cada arranque. O elige otra en Configuración, Docker."
                         : "En \(w.ip) (http \(w.http), https \(w.https)): sirve los proyectos de Docker sin XAMPP-X, con las mismas reglas de seguridad. phpMyAdmin: \(dockerWebURL(k, "pma." + dockerTLD(k)))")
                        .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !w.ok {
                    Button("Permitir") { model.dockerWebCommand("permitir") }
                        .buttonStyle(OutlineButton(kind: "primary")).disabled(model.busy)
                } else if w.state == "marcha" {
                    Button("Parar") {
                        if model.stopSharedOK(["nexum-web"], "el Apache de Docker") { model.dockerWebCommand("parar") }
                    }
                    .buttonStyle(OutlineButton()).disabled(model.busy)
                } else {
                    Button("Arrancar") { model.dockerWebCommand("arrancar") }.buttonStyle(OutlineButton()).disabled(model.busy)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill((w.ok ? Color.primary : Color.orange).opacity(w.ok ? 0.03 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke((w.ok ? Color.primary.opacity(0.12) : Color.orange.opacity(0.3)), lineWidth: 1))
        }
    }

    /// CPU y memoria (docker stats, llegan aparte) y cuántos están en marcha
    func cards(_ k: DockerData) -> some View {
        let up = k.containers.filter { $0.state == "running" }.count
        let s = model.dkStats
        let cpu = s.map { $0.cpu.values.reduce(0, +) } ?? 0
        let mem = s.map { $0.mem.values.reduce(0, +) } ?? 0
        return HStack(spacing: 12) {
            StatCard(title: "Uso de CPU de los contenedores", value: s == nil ? "…" : fmtPercent(cpu),
                     sub: s.map { "de \(100 * $0.cores) % (\(plural($0.cores, "núcleo", "núcleos")))" } ?? "",
                     progress: s.map { cpu / Double(100 * $0.cores) } ?? 0)
            StatCard(title: "Memoria de los contenedores", value: s == nil ? "…" : fmtSize(Int64(mem)),
                     sub: s.map { $0.total > 0 ? "de \(fmtSize($0.total))" : "" } ?? "",
                     progress: s.map { $0.total > 0 ? mem / Double($0.total) : 0 } ?? 0)
            StatCard(title: "En marcha", value: "\(up) de \(k.containers.count)",
                     sub: plural(k.projects.count, "proyecto", "proyectos"),
                     progress: k.containers.isEmpty ? 0 : Double(up) / Double(k.containers.count))
        }
        // (todas las tarjetas, tan altas como la más alta)
        .fixedSize(horizontal: false, vertical: true)
    }

    func tools() -> some View {
        HStack(spacing: 10) {
            Picker("", selection: $model.dkView) {
                Text("Contenedores").tag("cont")
                Text("Imágenes").tag("img")
                Text("Volúmenes").tag("vol")
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()
            .frame(width: 330)
            Spacer(minLength: 8)
            SearchField(text: $model.dkQuery, placeholder: "Buscar").frame(width: 200)
            Text("Solo en marcha").font(.caption).foregroundColor(.secondary)
            Toggle("", isOn: $model.dkOnlyUp).toggleStyle(SwitchToggleStyle()).labelsHidden().controlSize(.small)
        }
    }

    // MARK: tablas

    func groups(_ k: DockerData) -> [DockerGroup] {
        let q = model.dkQuery.trimmingCharacters(in: .whitespaces).lowercased()
        var out: [DockerGroup] = []
        for proj in Set(k.containers.map { $0.project }).sorted() {
            let items = k.containers.filter { $0.project == proj }.sorted { $0.name < $1.name }
            let slug = proj.hasPrefix("nexum-") ? String(proj.dropFirst(6)) : ""
            let p = k.projects.first { $0.slug == slug }
            var title = p?.folder ?? (proj.isEmpty ? "(sin proyecto)" : proj)
            // (lo común del Apache de Docker)
            if p == nil && proj == "nexum-web" {
                title = "Apache de Docker y phpMyAdmin"
            } else if p == nil && proj.range(of: "^nexum-mariadb-[0-9]+-[0-9]+$", options: .regularExpression) != nil {
                title = "MariaDB " + String(proj.dropFirst(14)).replacingOccurrences(of: "-", with: ".") + " (común)"
            } else if p == nil && proj.range(of: "^nexum-lampp-bd-[0-9]+-[0-9]+(-[0-9]+)?$", options: .regularExpression) != nil {
                title = "Puente a la BBDD de XAMPP-" + String(proj.dropFirst(15)).replacingOccurrences(of: "-", with: ".") + " (en vivo)"
            }
            let visible = items.filter { c in
                (!model.dkOnlyUp || c.state == "running")
                    && (q.isEmpty || c.name.lowercased().contains(q) || title.lowercased().contains(q))
            }
            if !visible.isEmpty {
                out.append(DockerGroup(id: proj, title: title, project: p, items: items, visible: visible))
            }
        }
        return out
    }

    func cpuText(_ names: [String]) -> String {
        let vals = names.compactMap { model.dkStats?.cpu[$0] }
        return vals.isEmpty ? "—" : fmtPercent(vals.reduce(0, +))
    }

    func containersTable(_ k: DockerData) -> some View {
        let list = groups(k)
        return TableBox {
            // (los puertos, con el ancho que quede; las acciones, pegadas a la derecha. Sin columna de
            // estado desde la 1.39.4: lo dice el punto junto al nombre)
            TableHead(cols: [("Nombre", 230), ("ID", 100), ("Imagen", 130), ("Puertos", 0), ("CPU", 55),
                             ("Acciones", DK_ACTIONS_WIDTH)], lastRight: true)
            ForEach(list) { g in
                Divider()
                groupRow(g)
                if dkIsOpen(g) {
                    // (desplegado: su visor, con sus accesos directos, encima de sus contenedores)
                    if let p = g.project {
                        Divider()
                        visor(p, g)
                    }
                    ForEach(g.visible) { c in
                        Divider()
                        containerRow(c, g)
                    }
                }
            }
            if list.isEmpty {
                Divider()
                Text("Ningún contenedor" + (model.dkOnlyUp ? " en marcha" : "") + (model.dkQuery.isEmpty ? "" : " con «\(model.dkQuery)»"))
                    .foregroundColor(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Fila de un proyecto (se pliega al pulsarla): su versión de PHP (se cambia al pulsarla) y sus acciones
    /// ¿Se ve desplegado? El que se ha abierto o, con una búsqueda, todos los que la cumplen
    func dkIsOpen(_ g: DockerGroup) -> Bool {
        return model.dkOpen.contains(g.id) || !model.dkQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func groupRow(_ g: DockerGroup) -> some View {
        let up = g.items.allSatisfy { $0.state == "running" }
        let open = dkIsOpen(g)
        // (uno abierto cada vez: abrir otro cierra el que estaba; pulsar el abierto lo cierra)
        return HoverRow(action: {
            model.dkOpen = model.dkOpen.contains(g.id) ? [] : [g.id]
        }) { _ in
            HStack(spacing: 8) {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary).frame(width: 10)
                LogoShape(d: LOGO_PATHS["docker"] ?? "").fill(brand("docker")).frame(width: 16, height: 16)
                Text(g.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                if up { StatusDot(on: true, size: 7).tip("Todos sus contenedores en marcha") }
            }
            .col(230)
            Text("").col(100)
            Group {
                if let p = g.project, p.isWeb {
                    Button("PHP " + p.versions.joined(separator: " · ")) { model.dockerVersions(p) }
                        .buttonStyle(OutlineButton(compact: true))
                        .disabled(model.busy)
                        .tip("Gestionar sus versiones de PHP")
                } else if let p = g.project {
                    Button("PHP \(p.php)") { model.dockerSetPhp(p) }
                        .buttonStyle(OutlineButton(compact: true))
                        .disabled(model.busy)
                        .tip("Cambiar la versión de PHP")
                } else {
                    Text(plural(g.items.count, "contenedor", "contenedores")).font(.caption).foregroundColor(.secondary)
                }
            }
            .col(130)
            Text(g.project.map { $0.isWeb ? "pma." + dockerTLD(model.docker) : ($0.pma.isEmpty ? "—" : "\($0.pma):80") } ?? "")
                .font(.system(size: 11.5, design: .monospaced)).foregroundColor(ACCENT).col(0)
            Text(cpuText(g.items.map { $0.name })).font(.system(size: 11.5, design: .monospaced)).foregroundColor(.secondary).col(55)
            HStack(spacing: 4) {
                if let p = g.project {
                    // (primero: arrancar o parar todos sus servicios a la vez)
                    iconAction(up ? "stop.fill" : "play.fill", up ? "Parar todos sus contenedores" : "Arrancar todos sus contenedores",
                               kind: up ? "stop" : "play") { model.dockerAction(p, start: !up) }
                        .disabled(model.busy)
                    iconAction("globe", "Abrir \(model.dockerSite(p))") { openURL(model.dockerSite(p) + "/") }
                        .disabled(!up)
                    logoAction("phpmyadmin", p.isWeb ? "Abrir phpMyAdmin (\(model.dockerPmaURL)): usuario root; la contraseña se copia al pulsar"
                               : "Abrir su phpMyAdmin (http://127.0.0.1:\(p.pma)/): pide usuario y contraseña") { model.dockerOpenPma(p) }
                        .disabled(!up || (!p.isWeb && p.pma.isEmpty))
                    iconAction("key", "Ver y copiar el usuario y la contraseña de su phpMyAdmin") { model.dockerPassword(p) }
                    iconAction("arrow.triangle.2.circlepath", p.isWeb && p.versions.count > 1
                               ? "Actualizar las imágenes de PHP " + p.versions.joined(separator: ", ") + " (las descarga otra vez, con sus últimos parches)"
                               : "Actualizar la imagen de PHP " + (p.isWeb ? p.versions.joined(separator: ", ") : p.php) + " (la descarga otra vez, con sus últimos parches)") {
                        model.dockerUpdateImage(p)
                    }
                    .disabled(model.busy)
                    iconAction("doc.text", "Ver los registros de sus contenedores") { model.dockerLogs(p) }
                        .disabled(model.busy)
                    if p.isWeb && p.kind == "wp" {
                        iconAction("arrow.left.arrow.right", "BBDD: la de XAMPP-X en vivo (la misma que web.local) o su copia de Docker") {
                            model.dockerDbMode(p)
                        }
                        .disabled(model.busy)
                    }
                    iconAction("trash", "Eliminar el proyecto de Docker: sus contenedores y la copia de su BBDD (la carpeta y la BBDD de XAMPP-X no se tocan)") {
                        model.dockerDelete(p)
                    }
                    .disabled(model.busy)
                } else if g.id == "nexum-web" {
                    iconAction(up ? "stop.fill" : "play.fill", up ? "Parar el Apache de Docker y su phpMyAdmin (los proyectos del Apache de Docker dejan de verse)"
                               : "Arrancar el Apache de Docker y su phpMyAdmin", kind: up ? "stop" : "play") {
                        if !up || model.stopSharedOK(["nexum-web"], "el Apache de Docker") {
                            model.dockerWebCommand(up ? "parar" : "arrancar")
                        }
                    }
                    .disabled(model.busy)
                } else if g.id.hasPrefix("nexum-lampp-bd-"), g.items.count == 1, let c = g.items.first {
                    // (el puente de los proyectos que usan en vivo la BBDD de esa versión XAMPP-X)
                    let users = model.sharedUsers(c.name)
                    iconAction(up ? "stop.fill" : "play.fill", up ? "Parar el puente (\(users.isEmpty ? "ningún proyecto" : users.joined(separator: ", ")) se \(users.count > 1 ? "quedan" : "queda") sin BBDD)"
                               : "Arrancar el puente", kind: up ? "stop" : "play") {
                        model.containerAction(c, up ? "parar" : "arrancar")
                    }
                    .disabled(model.busy)
                } else if g.id.hasPrefix("nexum-mariadb-"), g.items.count == 1, let c = g.items.first {
                    iconAction(up ? "stop.fill" : "play.fill", up ? "Parar \(g.title) (los proyectos que van con ella se quedan sin BBDD)"
                               : "Arrancar \(g.title)", kind: up ? "stop" : "play") {
                        model.containerAction(c, up ? "parar" : "arrancar")
                    }
                    .disabled(model.busy)
                }
            }
            .col(DK_ACTIONS_WIDTH, align: .trailing)
        }
    }

    /// Visor de un proyecto en Docker, como el del proyecto cargado: su nombre y su logotipo, sus
    /// versiones, su dominio, si está en marcha y sus accesos directos (los que se ven, en su orden y con
    /// su estilo: Botones del proyecto) y, siempre, sus versiones de PHP (o pasarlo al Apache de Docker)
    /// y arrancar o parar
    func visor(_ p: DockerProject, _ g: DockerGroup) -> some View {
        let up = !g.items.isEmpty && g.items.allSatisfy { $0.state == "running" }
        let some = g.items.contains { $0.state == "running" }
        let kind = model.projects?.list.first(where: { $0.name == p.folder })?.kind ?? ""
        let site = model.dockerSite(p)
        let c = model.visorConf
        let items = visorItems(p, g, up)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                // (el logotipo solo, sin recuadro, como arriba en Proyectos)
                KindIcon(kind: kind, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 10) {
                        Text(p.folder).font(.system(size: 16, weight: .bold)).lineLimit(1).truncationMode(.middle)
                        if kind == "wp" {
                            SmallTag(text: "WordPress")
                        } else if kind == "ps" {
                            SmallTag(text: "PrestaShop")
                        }
                    }
                    Text(p.isWeb ? "PHP \(p.versions.joined(separator: " · ")) · \(p.lampp.isEmpty ? "MariaDB \(p.maria) común" : "BBDD de XAMPP-\(p.lampp) en vivo (la de web.local)") · \(site)"
                         : "PHP \(p.php) · MariaDB \(p.maria) · \(site)")
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    StatusDot(on: up, size: 7)
                    Text(up ? "En marcha" : (some ? "A medias" : "Parado")).font(.caption)
                        .foregroundColor(up ? Color.primary : Color.secondary)
                }
            }
            Divider()
            HStack(spacing: 8) {
                ForEach(c.order.filter { !c.hidden.contains($0) && items[$0] != nil }, id: \.self) { k in
                    items[k]!
                }
                if p.isWeb {
                    VisorButton(conf: c, name: "Versiones de PHP…", icon: .symbol("plus", Color.primary),
                                tip: "Gestionar sus versiones de PHP") {
                        model.dockerVersions(p)
                    }
                    .disabled(model.busy)
                } else {
                    VisorButton(conf: c, name: "Pasar al Apache de Docker", icon: .symbol("arrow.up.circle", Color.primary),
                                tip: "Varias versiones de PHP a la vez") {
                        model.dockerPass(p)
                    }
                    .disabled(model.busy)
                }
                Spacer(minLength: 8)
                VisorButton(conf: c, name: up ? "Parar" : "Arrancar", icon: .symbol(up ? "stop.fill" : "play.fill", up ? RED : GREEN),
                            tip: up ? "Parar sus contenedores" : "Arrancar sus contenedores") {
                    model.dockerAction(p, start: !up)
                }
                .disabled(model.busy)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .padding(.leading, 38)
        .padding(.trailing, 14)
        .padding(.vertical, 8)
    }

    /// Los botones que se pueden ordenar y ocultar del visor de un proyecto en Docker, por su clave
    func visorItems(_ p: DockerProject, _ g: DockerGroup, _ up: Bool) -> [String: AnyView] {
        let c = model.visorConf
        let k = model.docker
        let folder = HTDOCS + "/" + p.folder
        let admin = projectAdmin(folder)
        let site = model.dockerSite(p)
        let stopped = "Está parado: arráncalo antes"
        // (el contenedor de su web: el de la versión elegida, o el de antes, php-1)
        let webC: String? = p.isWeb ? g.items.first(where: { $0.name == dockerWebContainer(p, p.php) })?.name
            : g.items.first(where: { $0.name.range(of: "^nexum-[a-z0-9-]+-php-[0-9]+$", options: .regularExpression) != nil })?.name
        // (un WordPress con varias versiones a la vez: cada una con su dominio)
        let targets: [(String, String)] = p.isWeb && p.kind != "ps" && p.versions.count > 1
            ? p.versions.map { ($0, dockerWebURL(k, dockerWebDomain(p, $0, dockerTLD(k)))) } : [(p.php, site)]
        var items: [String: AnyView] = [:]
        items["web"] = AnyView(VisorButton(conf: c, name: "Abrir web", icon: .symbol("globe", Color.blue),
                                           tip: up ? (targets.count > 1 ? "Abrir una de sus versiones de PHP" : "Abrir \(site)/") : stopped) {
            if targets.count > 1 {
                popMenu(targets.map { t in ("PHP \(t.0)  ·  \(t.1)", { openURL(t.1 + "/") }) })
            } else {
                openURL(site + "/")
            }
        }.disabled(!up))
        let mine = targets.first { model.tunnel?.target == $0.1 }
        if let m = mine {
            items["compartir"] = AnyView(model.shareButton(m.1, folder: folder, name: p.folder, conf: c).disabled(model.busy))
        } else if targets.count > 1 {
            items["compartir"] = AnyView(VisorButton(conf: c, name: "Compartir", icon: .logo("cloudflare"),
                                                     tip: up ? "Compartir con un túnel de Cloudflare" : stopped) {
                popMenu(targets.map { t in ("PHP \(t.0)  ·  \(t.1)", { model.share(t.1, folder: folder, name: p.folder) }) })
            }.disabled(!up || model.busy))
        } else {
            items["compartir"] = AnyView(model.shareButton(site, folder: folder, name: p.folder, conf: c).disabled(!up || model.busy))
        }
        items["panel"] = AnyView(VisorButton(conf: c, name: "Panel", icon: .logo(admin.0 == "ps" ? "prestashop" : "wordpress"),
                                             tip: !up ? stopped : (admin.1.isEmpty
                                                ? "No tiene panel de administración"
                                                : "Abrir el panel de administración")) {
            model.dockerPanel(p, kind: admin.0, admin: admin.1)
        }.disabled(!up || admin.1.isEmpty))
        items["pma"] = AnyView(VisorButton(conf: c, name: "phpMyAdmin", icon: .logo("phpmyadmin"),
                                           tip: !up ? stopped : "Abrir phpMyAdmin (copia la contraseña)") {
            model.dockerOpenPma(p)
        }.disabled(!up || (!p.isWeb && p.pma.isEmpty)))
        if let code = vscodeURL() {
            items["vscode"] = AnyView(VisorButton(conf: c, name: "VS Code", icon: .image(NSWorkspace.shared.icon(forFile: code.path)),
                                                  tip: "Abrir en Visual Studio Code") {
                openInVSCode(folder)
            })
        }
        items["log"] = AnyView(VisorButton(conf: c, name: "Log", icon: .logo("log"),
                                           tip: webC.map { _ in "Ver el log de errores" }
                                            ?? "Aún no tiene contenedor de la web: arráncalo") {
            if let n = webC { model.dockerWebLog(p, n) }
        }.disabled(webC == nil))
        if let x = model.projects?.list.first(where: { $0.name == p.folder }), x.kind == "wp" || x.kind == "ps" {
            items["imagenes"] = AnyView(VisorButton(conf: c, name: "Imágenes de producción", icon: .logo("imagenes"),
                                                    tip: "Traer de producción las imágenes que falten") {
                model.importImages(x)
            }.disabled(model.busy))
        }
        return items
    }

    func containerRow(_ c: DockerContainer, _ g: DockerGroup) -> some View {
        let on = c.state == "running"
        let own = ownContainer(c.name)
        // (dentro de su proyecto, solo su parte: db-1, php-1, pma-1)
        let short = !g.id.isEmpty && c.name.hasPrefix(g.id + "-") ? String(c.name.dropFirst(g.id.count + 1)) : c.name
        let ports = c.ports.components(separatedBy: ", ").filter { $0.contains("->") }
            .map { $0.replacingOccurrences(of: "/tcp", with: "").replacingOccurrences(of: "127.0.0.1:", with: "")
                .replacingOccurrences(of: "->", with: ":") }
            .joined(separator: ", ")
        return HoverRow { _ in
            HStack(spacing: 8) {
                StatusDot(on: on, size: 7)
                Text(short).font(.system(size: 11.5, design: .monospaced)).lineLimit(1)
                    .tip("\(c.name) · \(dockerStatusText(c.status))")
            }
            .padding(.leading, 26)
            .col(230)
            Text(c.cid.isEmpty ? "—" : c.cid).font(.system(size: 11.5, design: .monospaced)).foregroundColor(.secondary)
                .lineLimit(1).col(100)
            Text(c.image).font(.system(size: 11.5, design: .monospaced)).foregroundColor(ACCENT).lineLimit(1).truncationMode(.middle)
                .col(130).tip(c.image)
            Text(ports.isEmpty ? "—" : ports).font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(ports.isEmpty ? Color.secondary : ACCENT).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true).col(0)
            Text(cpuText([c.name])).font(.system(size: 11.5, design: .monospaced)).foregroundColor(.secondary).col(55)
            HStack(spacing: 4) {
                iconAction(on ? "stop.fill" : "play.fill", on ? "Parar" : "Arrancar", kind: on ? "stop" : "play") {
                    model.containerAction(c, on ? "parar" : "arrancar")
                }
                .disabled(!own || model.busy)
                iconAction("arrow.clockwise", "Reiniciar") { model.containerAction(c, "reiniciar") }
                    .disabled(!own || !on || model.busy)
                iconAction("doc.text", "Registros") { model.containerAction(c, "registros") }
                    .disabled(!own || model.busy)
                iconAction("trash", "Eliminar este contenedor") { model.containerAction(c, "borrar") }
                    .disabled(!own || model.busy)
            }
            .col(DK_ACTIONS_WIDTH, align: .trailing)
        }
    }

    func imagesTable(_ k: DockerData) -> some View {
        let q = model.dkQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let rows = k.images.filter { q.isEmpty || "\($0.name) \($0.cid)".lowercased().contains(q) }
        // (la usa un contenedor, aunque esté parado, si su imagen es imagen:etiqueta, su ID o, con
        // :latest, solo la imagen)
        let used = Set(k.containers.map { $0.image })
        return TableBox {
            TableHead(cols: [("Imagen", 0), ("Etiqueta", 120), ("ID", 110), ("Tamaño", 90), ("Creada", 110),
                             ("Acciones", DK_IMAGE_ACTIONS_WIDTH)], lastRight: true)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, i in
                Divider()
                imageRow(i, inUse: used.contains(i.name) || (!i.cid.isEmpty && used.contains(i.cid))
                            || (i.tag == "latest" && used.contains(i.repo)))
            }
            if rows.isEmpty {
                Divider()
                Text("No hay imágenes").foregroundColor(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Fila de una imagen: volver a descargarla de Docker Hub y borrarla (si no la usa ningún contenedor)
    func imageRow(_ i: DockerImage, inUse: Bool) -> some View {
        let own = i.repo.hasPrefix("nexum-")
        let pullable = i.tagged && !own
        let pullTip = pullable ? "Volver a descargarla de Docker Hub (lo último de \(i.name))"
            : own ? "Es del gestor: se rehace con «Actualizar imagen» de su proyecto"
            : "Sin etiqueta: no se puede volver a descargar"
        return HoverRow { _ in
            Text(i.repo).font(.system(size: 11.5, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                .col(0).tip(i.repo)
            Text(i.tag.isEmpty ? "—" : i.tag).font(.system(size: 11.5, design: .monospaced)).foregroundColor(ACCENT)
                .lineLimit(1).truncationMode(.middle).col(120)
            Text(i.cid.isEmpty ? "—" : i.cid).font(.system(size: 11.5, design: .monospaced)).foregroundColor(.secondary)
                .lineLimit(1).textSelection(.enabled).col(110)
            Text(i.size).font(.system(size: 11.5, design: .monospaced)).foregroundColor(.secondary).lineLimit(1).col(90)
            Text("hace " + dockerUnits(i.created.replacingOccurrences(of: " ago", with: ""))).foregroundColor(.secondary)
                .lineLimit(1).col(110)
            HStack(spacing: 4) {
                iconAction("icloud.and.arrow.down", pullTip) { model.imagePull(i) }
                    .disabled(!pullable || model.busy)
                iconAction("trash", inUse ? "La usa un contenedor: bórralo antes" : "Borrar la imagen") { model.imageDelete(i) }
                    .disabled(inUse || model.busy)
            }
            .col(DK_IMAGE_ACTIONS_WIDTH, align: .trailing)
        }
    }

    func volumesTable(_ k: DockerData) -> some View {
        let q = model.dkQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let rows = k.volumes.filter { q.isEmpty || $0.name.lowercased().contains(q) }
        // (el de la BBDD de un proyecto lo usa su contenedor db, aunque esté parado)
        let used = Set(k.containers.filter { !$0.project.isEmpty }.map { $0.project + "_db" })
        return TableBox {
            TableHead(cols: [("Volumen", 420), ("Driver", 120), ("De", 0), ("Acciones", DK_VOLUME_ACTIONS_WIDTH)],
                      lastRight: true)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, v in
                Divider()
                HoverRow { _ in
                    Text(v.name).font(.system(size: 11.5, design: .monospaced)).lineLimit(1).col(420)
                    Text(v.driver).foregroundColor(.secondary).col(120)
                    Text(v.name.hasPrefix("nexum-") && v.name.hasSuffix("_db")
                         ? String(v.name.dropFirst(6).dropLast(3)) + " (BBDD)" : "—")
                        .foregroundColor(.secondary).col(0)
                    volumeActions(v, inUse: used.contains(v.name))
                }
            }
            if rows.isEmpty {
                Divider()
                Text("No hay volúmenes").foregroundColor(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    func volumeActions(_ v: DockerVolume, inUse: Bool) -> some View {
        HStack(spacing: 4) {
            iconAction("trash", inUse ? "Lo usa un contenedor: bórralo antes (o el proyecto entero)" : "Borrar el volumen") {
                model.volumeDelete(v)
            }
            .disabled(inUse || model.busy)
        }
        .col(DK_VOLUME_ACTIONS_WIDTH, align: .trailing)
    }
}

/// Ancho de las acciones de las tablas de imágenes (2 botones) y volúmenes (1)
let DK_IMAGE_ACTIONS_WIDTH: CGFloat = 2 * 28 + 4
let DK_VOLUME_ACTIONS_WIDTH: CGFloat = 28

/// Ancho de las acciones de la tabla de contenedores: los 7 botones de la fila de un proyecto (28 cada
/// uno, con 4 entre ellos), pegados a la derecha
let DK_ACTIONS_WIDTH: CGFloat = 7 * 28 + 6 * 4

/// Contenedores de un proyecto de compose en la tabla de Docker
struct DockerGroup: Identifiable {
    let id: String
    let title: String
    let project: DockerProject?
    let items: [DockerContainer]
    let visible: [DockerContainer]
}
