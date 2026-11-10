// MARK: - Pestaña Herramientas

struct HostEntry: Equatable {
    var name: String
    var alias: String
    var folder: String
    var fake: Bool
    var https: Bool
    var crt: Bool
    var ps: Bool
    var custom: Bool
    var media: String = ""
}

/// Dominios de los vhosts y si están falseados en /etc/hosts (llevan a este Mac). Al cargar una
/// tienda PrestaShop se falsea su dominio y el resto vuelve a la web real.
// MARK: - Pestaña Servicios

/// Apache, MariaDB y el FTP de la versión montada, como el panel de XAMPP: si están en marcha, si se
/// puede entrar desde la red y botones para arrancarlos, pararlos o reiniciarlos. El FTP no arranca
/// con la versión: se arranca aquí cuando haga falta
struct ServicesView: View {
    @EnvironmentObject var model: AppModel
    /// Cierra el desplegable de arriba (al arrancar o parar la versión entera)
    var close: () -> Void = {}

    var body: some View {
        Page {
            if let d = model.data, let services = model.services {
                if d.active.isEmpty {
                    Card("Servicios") {
                        Row("Ninguna versión activa", "Activa una versión en Versiones de PHP para ver sus servicios.", leading: {
                            Circle().fill(Color.secondary.opacity(0.4)).frame(width: 9, height: 9)
                        }, trailing: { EmptyView() })
                    }
                } else {
                    servicesHeader(d, services)
                    VStack(spacing: 10) {
                        ForEach(services) { sv in serviceCard(sv) }
                    }
                    if services.contains(where: { $0.open }) {
                        Card("Se puede entrar desde otros equipos de la red") {
                            Row("Abierto a la red", d.exposed.isEmpty ? "Algún servicio escucha en toda la red" : d.exposed, trailing: {
                                Button("Cerrar a la red") { model.secure() }.disabled(model.busy)
                            })
                        }
                    }
                }
            } else {
                Loading()
            }
        }
    }

    /// Cabecera: versión, cuántos están en marcha y si solo se entra desde este Mac
    func servicesHeader(_ d: AppData, _ services: [Service]) -> some View {
        let running = services.filter { $0.running }.count
        let exposed = services.contains(where: { $0.open })
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Servicios de XAMPP-\(d.active)").font(.title2.bold())
                Text("\(running) de \(services.count) en marcha").foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            // Arrancar o parar la versión entera: lo que hacía el botón Encendidos del visor
            if d.running {
                Button("Parar y desactivar") { close(); model.power() }.disabled(model.busy)
            } else {
                Button("Arrancar XAMPP-\(d.active)") { close(); model.power() }
                    .buttonStyle(OutlineButton(kind: "primary"))
                    .disabled(model.busy)
            }
            if exposed {
                Badge(text: "Abierto a la red", symbol: "exclamationmark.triangle.fill", color: RED)
            } else {
                Badge(text: "Solo desde este Mac", symbol: "lock.shield.fill", color: GREEN)
                    .tip("Solo accesibles desde este Mac")
            }
        }
    }

    /// Una tarjeta por servicio: icono, estado, puertos y botones con texto
    func serviceCard(_ sv: Service) -> some View {
        let titles = ["apache": "Apache", "mariadb": "MariaDB", "ftp": "FTP (ProFTPD)"]
        let helps = ["apache": "Servidor web: las webs de htdocs y phpMyAdmin (con PHP)",
                     "mariadb": "Servidor de BBDD",
                     "ftp": "Acceso por FTP a htdocs. No arranca con la versión: arráncalo cuando lo necesites y páralo después."]
        let icons: [String: (String, Color)] = ["apache": ("logo:apache", brand("apache")),
                                                "mariadb": ("logo:mariadb", brand("mariadb")),
                                                "ftp": ("arrow.up.arrow.down", .orange)]
        let title = titles[sv.name] ?? sv.name
        let ic = icons[sv.name] ?? ("gearshape.fill", .gray)
        var chips = sv.ports.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { "Puerto " + $0 }
        if sv.name == "ftp" {
            if !sv.user.isEmpty { chips.append("usuario \(sv.user)") }
            if sv.auto { chips.append("arranca con la versión") }
        }
        return HStack(alignment: .center, spacing: 14) {
            ColorIcon(symbol: ic.0, color: ic.1, size: 44)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title).font(.headline)
                    if sv.running {
                        Badge(text: "En marcha", symbol: nil, color: GREEN)
                    } else {
                        Badge(text: "Parado", symbol: nil, color: .gray)
                    }
                    if sv.open {
                        Badge(text: "Abierto a la red", symbol: nil, color: RED)
                    }
                }
                Text(helps[sv.name] ?? "").font(.callout).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { c in
                        Text(c).font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }
            }
            Spacer(minLength: 8)
            if sv.running {
                Button(action: { model.service(sv.name, "reiniciar", title) }) {
                    Label("Reiniciar", systemImage: "arrow.clockwise")
                }
                .disabled(model.busy)
                Button(action: { model.service(sv.name, "parar", title) }) {
                    Label("Parar", systemImage: "stop.fill")
                }
                .disabled(model.busy)
            } else {
                Button(action: { model.service(sv.name, "arrancar", title) }) {
                    Label("Arrancar", systemImage: "play.fill")
                }
                .buttonStyle(OutlineButton(kind: "primary"))
                .disabled(model.busy)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

/// Etiqueta de estado en una cápsula de color suave (En marcha, Parado, Solo desde este Mac)
struct Badge: View {
    let text: String
    let symbol: String?
    let color: Color
    var body: some View {
        HStack(spacing: 4) {
            if let sym = symbol { Image(systemName: sym) }
            Text(text)
        }
        .font(.caption.weight(.bold))
        .foregroundColor(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.16)))
    }
}

/// Ancho disponible para OneThirdTwoThirds
private struct AvailableWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = Swift.max(value, nextValue()) }
}

/// Dos tarjetas en una fila: la primera ocupa 1/3 y la segunda, 2/3. (Sin Layout ni Grid, que no están
/// en macOS 12: se mide el ancho disponible y a cada una se le da el suyo)
struct OneThirdTwoThirds<First: View, Second: View>: View {
    let first: First
    let second: Second
    @State private var width: CGFloat = 0
    private let spacing: CGFloat = 18
    init(@ViewBuilder first: () -> First, @ViewBuilder second: () -> Second) {
        self.first = first()
        self.second = second()
    }
    private var unit: CGFloat { Swift.max(0, width - spacing) / 3 }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { g in
                Color.clear.preference(key: AvailableWidthKey.self, value: g.size.width)
            }
            .frame(height: 0)
            if width > 0 {
                HStack(alignment: .top, spacing: spacing) {
                    first.frame(width: unit, alignment: .topLeading)
                    second.frame(width: unit * 2, alignment: .topLeading)
                }
            }
        }
        .onPreferenceChange(AvailableWidthKey.self) { width = $0 }
    }
}

struct HostsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        WidePage {
            HStack(alignment: .top) {
                PageTitle(title: "Dominios y hosts",
                          sub: "Los dominios de los vhosts y los que se llevan a este equipo en /etc/hosts", symbol: "network")
                Spacer(minLength: 12)
                Button(action: { model.viewHostsFile() }) { Label("Ver fichero de hosts", systemImage: "doc.text") }
                    .buttonStyle(OutlineButton())
                    .tip("Ver \(model.data?.hosts ?? "/etc/hosts")")
            }
            if let hosts = model.hosts {
                // Primero, si el vhost de los proyectos no lleva a este Mac: el navegador no conecta
                ForEach(model.hostsLinkFix, id: \.self) { f in
                    Card("\(f[0]) no lleva a este Mac",
                         "Apache solo escucha en 127.0.0.1 y ::1, y en /etc/hosts \(f[1].isEmpty ? "no está" : "apunta a \(f[1])"). El navegador da «No se puede acceder a este sitio web». Arreglarlo hace que \(f[0]) lleve a 127.0.0.1 y ::1 (una sola vez\(FileManager.default.fileExists(atPath: COPIES_FILES_FLAG) ? "; la copia del /etc/hosts anterior queda en ~/nexum-backups" : "")). Pide la contraseña de administrador.") {
                        Row("\(f[0]) → \(f[1].isEmpty ? "sin línea en /etc/hosts" : f[1])", "Tiene que ir a 127.0.0.1, donde escucha Apache", trailing: {
                            Button("Arreglarlo") { model.fixHostsLink() }
                                .buttonStyle(OutlineButton(kind: "primary"))
                                .disabled(model.busy)
                        })
                    }
                }
                // Arriba, en un recuadro como el visor de Proyectos: todos los que llevan a este Mac (también
                // los .local), en dos columnas, cada uno con su interruptor
                hostsVisor(fakes(hosts))
                // Debajo, en la misma fila: los demás dominios de los vhosts ocupan 1/3 y el proyecto nuevo, 2/3
                OneThirdTwoThirds(first: {
                    Card("Dominios de los vhosts",
                         "Los que llevan a su web real. Encendido, el dominio lleva a este Mac (127.0.0.1 y ::1) y sube al recuadro de arriba. Se pide la contraseña de administrador para cambiar /etc/hosts.") {
                        if rest(hosts).isEmpty {
                            Row("No hay más dominios", "Los vhosts están en XAMPP-compartido/httpd-vhosts.conf")
                        }
                        ForEach(rest(hosts), id: \.name) { h in
                            if h.name != rest(hosts).first?.name { Divider() }
                            hostRow(h)
                        }
                    }
                }, second: {
                    newDomainCard(hosts)
                })
            } else {
                Loading()
            }
        }
    }

    /// Proyecto nuevo con el dominio de producción falseado: la carpeta se elige entre las de htdocs
    /// (por ejemplo, la de un git clone) o se crea; la base, entre las de la versión activa o se crea
    func newDomainCard(_ hosts: [HostEntry]) -> some View {
        let active = model.data?.active ?? ""
        let folders = projectFolders()
        let dbs = model.data?.dbs[active] ?? []
        let withDomain = Dictionary(hosts.filter { !$0.folder.isEmpty }.map { ($0.folder, $0.name) },
                                    uniquingKeysWith: { a, _ in a })
        let folderChoices = folders + (model.newFolder.isEmpty || folders.contains(model.newFolder) ? [] : [model.newFolder])
        let dbChoices = dbs + (model.newDb.isEmpty || dbs.contains(model.newDb) ? [] : [model.newDb])
        let domain = cleanDomain(model.newDomain)
        let canCreate = matches(DOMAIN_RX, domain) && !model.newFolder.isEmpty && !model.busy
        // (junto al botón, lo que falta para poder crearlo: sin eso no se puede pulsar)
        let why = domain.isEmpty ? "Escribe el dominio de producción"
            : !matches(DOMAIN_RX, domain) ? "«\(domain)» no es un dominio (por ejemplo: mitienda.com)"
            : model.newFolder.isEmpty ? "Elige su carpeta"
            : model.busy ? "Espera a que acabe la tarea en marcha"
            : "https://\(domain.lowercased()) → htdocs/\(model.newFolder)"
        return Card("Nuevo proyecto con dominio falseado",
                    "Para construir en local un proyecto nuevo con su dominio y su BBDD de producción, sin tocar nada en producción. Elige su carpeta de htdocs (por ejemplo, la de un git clone) o crea una, y su BBDD. Se crea su vhost http y https con certificado, lo que falte de la carpeta y la BBDD, y se falsea el dominio. Al terminar se exporta a producción tal cual.") {
            Row("Dominio", "El de producción") {
                TextField("mitienda.com", text: $model.newDomain).frame(width: 230)
            }
            Divider()
            Row("Carpeta", withDomain[model.newFolder].map { "Ya tiene el dominio \($0)" } ?? "En htdocs (git clone) o nueva") {
                SearchPicker(selection: Binding(get: { model.newFolder }, set: { model.pickNewFolder($0) }),
                             items: (model.newFolder.isEmpty ? [("", "Elige una carpeta")] : [] as [(String, String)])
                                 + folderChoices.map { f in (f, folders.contains(f) ? f : "\(f) (nueva)") })
                IconButton(symbol: "plus", help: "Crear una carpeta nueva") { model.askNewDomainName(db: false) }
                    .disabled(model.busy)
            }
            Divider()
            Row("BBDD", active.isEmpty ? "No hay ninguna versión activa" : "En XAMPP-\(active)") {
                SearchPicker(selection: $model.newDb,
                             items: [("", "Sin BBDD")] + dbChoices.map { db in (db, dbs.contains(db) ? db : "\(db) (nueva)") })
                .disabled(active.isEmpty)
                IconButton(symbol: "plus", help: "Crear una BBDD nueva") { model.askNewDomainName(db: true) }
                    .disabled(model.busy || active.isEmpty)
            }
            Divider()
            HStack {
                Text(why).font(.system(size: 11.5)).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Crear y falsear") { model.createNewDomain() }
                    .buttonStyle(OutlineButton(kind: "primary", big: true))
                    .disabled(!canCreate)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    // Falseados: los que llevan a este Mac en /etc/hosts. También los .local (siempre están, sin su línea
    // se preguntaría a la red), aunque no haya ninguna web real a la que devolverlos
    func fakes(_ hosts: [HostEntry]) -> [HostEntry] {
        return hosts.filter { $0.fake }
    }
    func rest(_ hosts: [HostEntry]) -> [HostEntry] {
        return hosts.filter { !$0.fake }
    }

    /// El recuadro de arriba, como el visor de Proyectos: su cabecera (el punto verde si hay alguno) y, en una
    /// tarjeta, los dominios falseados en dos columnas (de dos en dos, por filas), cada uno con su interruptor
    func hostsVisor(_ fake: [HostEntry]) -> some View {
        let left: [HostEntry] = fake.enumerated().filter { $0.offset % 2 == 0 }.map { $0.element }
        let right: [HostEntry] = fake.enumerated().filter { $0.offset % 2 == 1 }.map { $0.element }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusDot(on: !fake.isEmpty, blink: false)
                Text("DOMINIOS Y HOSTS FALSEADOS")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                Image(systemName: "info.circle").foregroundColor(.secondary)
                    .tip("Llevan a este Mac y no a internet. Los .local, siempre; el dominio de una tienda PrestaShop, mientras está cargada (al cargarla se crea lo que le falte, su vhost y su certificado, y al cargar otro proyecto vuelve a llevar a la web real), y los que falsees tú. Apagado, el dominio baja a «Dominios de los vhosts» y lleva a su web real.")
                Spacer()
                if !fake.isEmpty {
                    Text("\(fake.count) \(fake.count == 1 ? "lleva" : "llevan") a este Mac")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                if fake.isEmpty {
                    Text("Ningún dominio falseado: los dominios de los vhosts llevan a sus webs reales.")
                        .foregroundColor(.secondary)
                } else {
                    HStack(alignment: .top, spacing: 18) {
                        hostColumn(left)
                        hostColumn(right)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.12), lineWidth: 1))
        }
    }

    /// Una columna del recuadro de arriba: sus dominios en una lista con bordes redondeados (vacía, su hueco)
    @ViewBuilder
    func hostColumn(_ hs: [HostEntry]) -> some View {
        if hs.isEmpty {
            Color.clear.frame(height: 1).frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 0) {
                ForEach(hs, id: \.name) { h in
                    if h.name != hs.first?.name { Divider() }
                    hostRow(h)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .frame(maxWidth: .infinity)
        }
    }

    func info(_ h: HostEntry) -> String {
        var parts = [h.folder.isEmpty ? "sin carpeta en htdocs" : h.folder]
        if h.ps { parts.append("PrestaShop") } else if h.custom { parts.append("Proyecto nuevo") }
        if !h.https { parts.append("sin https") } else if !h.crt { parts.append("falta el certificado") }
        if !h.media.isEmpty { parts.append("imágenes que faltan de \(h.media)") }
        return parts.joined(separator: "  ·  ")
    }

    func hostRow(_ h: HostEntry) -> some View {
        Row(h.name, info(h), leading: {
            hostIcon(h)
        }, trailing: {
            if h.fake {
                Button("Abrir") {
                    if let url = URL(string: "\(h.https ? "https" : "http")://\(h.name)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .tip("\(h.https ? "https" : "http")://\(h.name)")
            }
            if h.name.lowercased().hasSuffix(".local") {
                Button(action: { model.mediaProxy(h) }) { Image(systemName: "photo") }
                    .disabled(model.busy)
                    .tip("Imágenes de producción"
                         + (h.media.isEmpty ? "" : ": \(h.media)"))
            }
            Toggle("", isOn: Binding(get: { h.fake }, set: { model.setHostFake(h, $0) }))
                .toggleStyle(SwitchToggleStyle()).labelsHidden().tint(GREEN)
                .disabled(model.busy)
                .tip(h.name.lowercased().hasSuffix(".local")
                     ? (h.fake ? "Apagar este .local" : "Encender este .local")
                     : (h.fake ? "Host falseado" : "Falsear Host"))
        })
    }

    /// Logotipo del dominio: PrestaShop, WordPress (por el nombre de su carpeta) o un globo
    func hostIcon(_ h: HostEntry) -> ColorIcon {
        if h.ps { return LogoIcon("prestashop", size: 20) }
        if h.folder.lowercased().contains("wordpress") { return LogoIcon("wordpress", size: 20) }
        return ColorIcon(symbol: "globe", color: .blue, size: 20)
    }
}

struct ToolsView: View {
    @EnvironmentObject var model: AppModel
    // Dirección y puertos del Apache de Docker (se rellenan con los de gui-docker)
    @State private var dkIP = ""
    @State private var dkHTTP = ""
    @State private var dkHTTPS = ""
    /// La explicación del apartado abierto (la de su tarjeta)
    @State private var toolsDesc: String? = nil

    /// Apartados de Configuración (como en Linux): su clave, su nombre en la columna de la izquierda y su icono
    static let sections: [(String, String, String)] = [
        ("general", "General", "slider.horizontal.3"),
        ("hosts", "Vhosts y hosts", "network"),
        ("seguridad", "Seguridad entre webs", "lock.shield"),
        ("correo", "Correo de pruebas", "envelope"),
        ("docker", "Docker", "logo:docker"),
        ("tunel", "Túnel de Cloudflare", "cloud"),
        ("apariencia", "Apariencia", "paintpalette"),
        ("github", "GitHub", "logo:github"),
        ("limpieza", "Limpieza", "sparkles"),
        ("carpetas", "Carpetas", "folder"),
        ("oficial", "XAMPP oficial", "externaldrive"),
        ("info", "Información", "info.circle")]
    /// La explicación de General (cada uno de sus bloques lleva la suya)
    static let generalDesc = "Los registros de errores de la web cargada y de Apache, el de las tareas que lanza la ventana, los parches nuevos de lo que usa Nexum y el propio programa"

    var body: some View {
        // Los apartados, en una columna pegada al menú lateral; a la derecha, lo que se puede cambiar del elegido
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CONFIGURACIÓN")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.leading, 12)
                        .padding(.top, 14)
                        .padding(.bottom, 3)
                    ForEach(ToolsView.sections, id: \.0) { sec in
                        SubNavRow(key: sec.0, text: sec.1, icon: sec.2)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .frame(width: 220)
            .background(Color.primary.opacity(0.018))
            .overlay(Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1), alignment: .trailing)
            WidePage {
                // (el título, el del apartado abierto: su icono, su nombre y su explicación)
                let sec = ToolsView.sections.first(where: { $0.0 == model.toolsSection })
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    PageTitle(title: sec?.1 ?? "Configuración", sub: toolsDesc ?? "Configuración",
                              symbol: (sec?.2 ?? "gearshape").hasPrefix("logo:") ? nil : (sec?.2 ?? "gearshape"),
                              logo: (sec?.2 ?? "").hasPrefix("logo:") ? String((sec?.2 ?? "").dropFirst(5)) : nil)
                    // (el correo se enciende con el interruptor de su título)
                    if model.toolsSection == "correo", let m = model.data?.mail { mailSwitch(m) }
                    Spacer(minLength: 0)
                }
                if let d = model.data {
                    VStack(alignment: .leading, spacing: 12) {
                        section(model.toolsSection, d)
                    }
                    .environment(\.toolsSection, sec?.1)
                    .onPreferenceChange(ToolsDescKey.self) { toolsDesc = $0 }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    Loading()
                }
            }
        }
    }

    /// Lo que se puede cambiar de un apartado
    @ViewBuilder
    func section(_ key: String, _ d: AppData) -> some View {
        switch key {
        case "hosts":
            TileCard("Vhosts y hosts", "Después de cambiar los vhosts, reinicia la versión activa para aplicarlos.") {
                Tile("Virtual hosts", d.vhosts) {
                    Button("Editar…") { model.editVhosts() }.disabled(model.busy)
                }
                Tile("Hosts del sistema", d.hosts) {
                    Button("Editar…") { model.editHosts() }.disabled(model.busy)
                }
            }
        case "seguridad":
            TileCard("Seguridad entre webs", "Impide que otra web abierta en tu navegador use tus proyectos locales sin que lo sepas.",
                     wide: true) {
                Tile("Barrera entre webs", d.barrier ? "Encendida: tus proyectos solo aceptan lo que llega desde ellos mismos"
                     : "Apagada: enciéndela cuando acabes de probar los pagos") {
                    Toggle("", isOn: Binding(get: { d.barrier }, set: { model.setBarrier($0) }))
                        .toggleStyle(SwitchToggleStyle()).labelsHidden()
                        .disabled(model.busy || d.installs.isEmpty)
                }
            }
            // Qué es, explicado: el problema, lo que hace, cuándo apagarla y dónde vale
            TileCard("Qué es", wide: true) {
                ForEach(CROSS_SITE_HELP, id: \.1) { h in
                    Tile(h.1, h.2, leading: { Image(systemName: h.0).font(.system(size: 15)).foregroundColor(.secondary).frame(width: 22) },
                         trailing: { EmptyView() })
                }
            }
            .padding(.top, 10)
        case "correo":
            mailCard(d)
        case "docker":
            dockerCard()
        case "tunel":
            tunnelCard()
        case "apariencia":
            AppearanceCard()
        case "github":
            GitHubCard()
        case "limpieza":
            CleanCard()
        case "carpetas":
            TileCard("Carpetas") {
                // Copias de seguridad: abrirlas y borrarlas (nexum copias vaciar)
                let bk = model.backups ?? [0, 0]
                Tile("Copias de seguridad", "~/nexum-backups: las copias que pides al borrar, sustituir o actualizar, y las del XAMPP oficial · "
                     + (bk[1] > 0 ? "\(fmtSize(bk[0])), \(bk[1]) \(bk[1] == 1 ? "fichero" : "ficheros")" : "vacía")) {
                    Button("Abrir") {
                        try? FileManager.default.createDirectory(atPath: COPIES_DIR, withIntermediateDirectories: true,
                                                                 attributes: [.posixPermissions: 0o700])
                        openFolder(COPIES_DIR)
                    }
                    Button("Borrar…") { model.clearCopies(Int(bk[1]), bk[0]) }.disabled(model.busy || bk[1] == 0)
                }
                .onAppear { model.refreshBackups() }
                // Copias de los ficheros que cambia el programa por su cuenta (nexum copias-ficheros si|no)
                Tile("Copias de los ficheros que cambia el programa",
                     "El fichero de hosts, los vhosts y la configuración de los proyectos, antes de cambiarlos") {
                    Toggle("", isOn: Binding(get: { model.copiesFiles }, set: { model.setCopiesFiles($0) }))
                        .toggleStyle(SwitchToggleStyle()).labelsHidden()
                        .disabled(model.busy)
                }
                Tile("Registros de instalaciones", "~/.lvm-instalador: logs de las instalaciones y de la ventana") {
                    Button("Abrir") { openFolder(LOG_DIR) }
                }
                // Caché de descargas de las pilas propias: lo que ocupa y vaciarla
                let cache = downloadsCacheSize()
                Tile("Caché de descargas", "\(DL_CACHE_DIR): lo ya descargado de PHP, Apache, MariaDB… · "
                     + (cache.files > 0 ? "\(fmtSize(cache.size)), \(cache.files) \(cache.files == 1 ? "fichero" : "ficheros")" : "vacía")) {
                    Button("Vaciar…") { model.clearDownloads(cache.size) }.disabled(model.busy || cache.files == 0)
                }
            }
        case "oficial":
            officialCard(d)
        case "info":
            TileCard("Información") {
                Tile("Comandos de nexum", "Todos los comandos para la terminal y qué hace cada uno") {
                    Button("Ver") { model.showCommands() }
                }
                Tile("Novedades", "Qué ha cambiado en cada versión") {
                    Button("Ver") { model.showChanges() }
                }
                Tile("Acerca de", "\(d.name) \(d.version)") {
                    Button("Ver") { model.showAbout() }
                }
            }
        default:
            generalSection(d)
        }
    }

    /// General: el registro de errores, el de tareas, los parches nuevos y el programa, cada uno en su bloque con
    /// su título y su explicación a la vista
    func generalSection(_ d: AppData) -> some View {
        VStack(alignment: .leading, spacing: 30) {
            generalBlock("Registro de errores", "Si la web cargada da un error (el «error crítico» de WordPress), el motivo está en el registro de su vhost: ahí van los errores de PHP. Los de Apache (que no arranca, un vhost mal escrito…), en el general. Lo más reciente está al final.") {
                TileCard {
                    if let path = projectErrorLog(d) {
                        errorLogRow(d, path: path, title: "error_log de \(model.projects?.link ?? "")"
                                    + ((model.projects?.current ?? "").isEmpty ? "" : "  (\(((model.projects?.current ?? "") as NSString).lastPathComponent))"))
                    }
                    errorLogRow(d, path: ERROR_LOG, title: d.active.isEmpty ? "error_log de Apache" : "error_log de Apache (XAMPP-\(d.active))")
                }
            }
            generalBlock("Registro de tareas", "Cada tarea que lanza la ventana (instalar, activar, arrancar, copiar una BBDD, limpiar…) guarda aquí su registro entero: la orden de nexum que se ha ejecutado, todo lo que ha dicho, lo mismo que en su ventana, y cómo acabó. Se guardan las \(TASKS_KEEP) últimas en ~/.lvm-instalador/tareas, solo para ti; las contraseñas y los tokens no se escriben.") {
                TaskLogsCard()
            }
            generalBlock("Parches nuevos", "Los parches de seguridad de todo lo que usa Nexum: cada versión de PHP (PHP, Apache, MariaDB, ProFTPD, Perl y phpMyAdmin, frente a lo último de su rama), las imágenes de Docker (las MariaDB comunes, phpMyAdmin y PHP, frente a Docker Hub), Mailpit y cloudflared. Se busca al abrir la ventana el primer arranque del día y cada pocos arranques. Las versiones XAMPP-X.Y se rehacen (la de ahora sigue funcionando mientras se compila); las XAMPP-X.Y.Z llevan su parche en el nombre: la nueva se instala a su lado. Los contenedores de Docker se rehacen en unos segundos, con sus BBDD.") {
                componentsCard()
            }
            generalBlock("Programa", "El propio Nexum Dev Stack: lo que hace al cerrar la ventana.") {
                TileCard(wide: true) {
                    Tile("Dejar en la barra de menús al cerrar",
                         "Icono junto al reloj: al cerrar la ventana, la aplicación sigue en él. Desde ahí se abre otra vez, se arranca o para la versión, se abre web.local o se sale.") {
                        Toggle("", isOn: Binding(get: { model.trayOn }, set: { model.setTray($0) }))
                            .toggleStyle(SwitchToggleStyle()).labelsHidden()
                    }
                }
            }
        }
        // (debajo del título grande de Configuración)
        .preference(key: ToolsDescKey.self, value: ToolsView.generalDesc)
    }

    /// Un bloque de General: su título, su explicación y lo suyo debajo
    func generalBlock<C: View>(_ title: String, _ sub: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(sub).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            content().padding(.top, 6)
        }
    }

    /// Docker: la dirección y los puertos del Apache de Docker, dar de alta la dirección en este Mac y que el
    /// navegador acepte el certificado de *.docker.local
    func dockerCard() -> some View {
        let w = model.docker?.web ?? DockerWeb()
        return VStack(alignment: .leading, spacing: 12) {
          TileCard("Docker", "Los proyectos de Docker van con su propio Apache, en otra dirección de este Mac (nunca abierta a la red): funcionan sin XAMPP-X y a la vez que él, con las mismas reglas de seguridad. Con los puertos 80 y 443, las direcciones van sin puerto. macOS solo tiene 127.0.0.1: la otra se da de alta una vez («Permitir», pide la contraseña).", wide: true, tiles: true) {
            Tile("Dirección y puertos", "De este Mac (127.x.x.x; 127.0.0.1 con 80 y 443 es la de XAMPP-X). HTTP lleva siempre a https; si HTTPS no es el 443, las direcciones lo llevan. "
                 + (w.ok ? "\(w.ip) ya está en este Mac." : "\(w.ip) aún no está: se da de alta una vez y queda puesta en cada arranque.")) {
                // (los campos en una línea y, debajo, a la derecha, Guardar y, si hace falta, Permitir)
                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 8) {
                        field("Dirección", $dkIP, 120)
                        field("HTTP", $dkHTTP, 60)
                        field("HTTPS", $dkHTTPS, 60)
                    }
                    HStack(spacing: 8) {
                        if !w.ok {
                            Button("Permitir") { model.dockerWebCommand("permitir") }.disabled(model.busy)
                        }
                        Button("Guardar") { model.dockerWebPorts(dkIP, dkHTTP, dkHTTPS) }
                            .buttonStyle(OutlineButton(kind: "primary"))
                            .disabled(model.busy)
                    }
                }
            }
          }
          TileCard(tiles: true) {
            Tile("DNS de *.docker.test", w.dns ? "Puesto: los dominios de Docker (<proyecto>-php83.docker.test) no van en /etc/hosts ni piden la contraseña"
                : "Los dominios de Docker pasan a .docker.test y dejan de ir en /etc/hosts: sin contraseña al añadir proyectos o versiones. web.local, los proyectos de siempre y las tiendas falseadas, igual") {
                Button(w.dns ? "Quitar" : "Activar") { model.dockerDNS(!w.dns) }.disabled(model.busy)
            }
            Tile("Certificado de *.docker.local y *.docker.test", "Safari y Chrome lo aceptan sin aviso: solo vale para esos dominios (no es de una CA)") {
                Button("Confiar") { model.dockerWebCommand("confiar") }.disabled(model.busy)
            }
          }
          IdleStopCard()
        }
        .onAppear {
            if model.docker == nil { model.reloadDocker() }
            fillDocker()
        }
        .onChange(of: model.docker?.web) { _ in fillDocker() }
    }

    /// Campo con su nombre encima (la dirección y los puertos de Docker), tan alto como los botones
    func field(_ title: String, _ text: Binding<String>, _ width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField("", text: text).textFieldStyle(PlainTextFieldStyle())
                .padding(.horizontal, 8)
                .frame(width: width, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.2), lineWidth: 1))
        }
    }

    func fillDocker() {
        guard let w = model.docker?.web else { return }
        if dkIP.isEmpty { dkIP = w.ip }
        if dkHTTP.isEmpty { dkHTTP = w.http }
        if dkHTTPS.isEmpty { dkHTTPS = w.https }
    }

    /// Túnel de Cloudflare: cloudflared, el túnel abierto (con Cerrar) y su registro. La contraseña, las horas
    /// y el admin de cada túnel se eligen al abrirlo («Compartir»)
    func tunnelCard() -> some View {
        let info = model.tunnelInfo
        let log = TUNNEL_DIR + "/registro"
        return VStack(alignment: .leading, spacing: 12) {
          TileCard("Túnel de Cloudflare", "Para enseñar una web de este Mac a un cliente o a un compañero: una dirección https://….trycloudflare.com (sin cuenta de Cloudflare; cambia cada vez) con contraseña, que se cierra sola. Sin abrir puertos del router. La web no se toca: su dominio local se cambia por el del túnel al pasar. Se abre con «Compartir» en el visor del proyecto, y ahí se elige su contraseña, cuánto dura y si se bloquea el admin.") {
            Tile("cloudflared", info == nil ? "…" : (info?[1] == "1" ? "Versión \(info?[2] ?? ""), en ~/.lvm-instalador/tunel"
                                                     : "Aún no está: se descarga de GitHub la primera vez que compartes (unos 20 MB)"),
                leading: { LogoShape(d: LOGO_PATHS["cloudflare"] ?? "").fill(brand("cloudflare")).frame(width: 20, height: 20) }) {
                if let f = info, f[1] != "1" || f[2] != f[3] {
                    Button(f[1] != "1" ? "Instalar" : "Actualizar a la \(f[3])") {
                        model.runTask("Instalando cloudflared", ["tunel-instalar"], progress: true, doneText: "cloudflared instalado", autoClose: true) { _, _, _ in
                            model.reloadTunnelInfo()
                        }
                    }
                    .disabled(model.busy)
                }
            }
            if FileManager.default.fileExists(atPath: log) {
                Tile("Registro del túnel", "Quién entra, las contraseñas equivocadas y lo que se bloquea (el último túnel)") {
                    Button("Ver") { model.showLogTail(log) }
                }
            }
          }
          if let t = model.tunnel {
            TileCard(wide: true) {
                Tile("Túnel abierto", "\(t.url) → \(t.target), hasta las \(clockTime(t.expires))") {
                    Button("Ver") { model.shareDialog() }
                    Button("Cerrar") { model.tunnelClose() }.buttonStyle(OutlineButton(kind: "stop"))
                }
            }
          }
        }
        .onAppear { model.reloadTunnelInfo() }
    }

    /// Parches nuevos (en General, con su título y su explicación): lo que tiene un parche publicado y «Actualizar todo»
    func componentsCard() -> some View {
        let c = model.components
        var text = "Buscando parches nuevos…"
        if let c = c {
            text = c.items.isEmpty ? (c.errors.isEmpty ? "Todo al día: no hay parches nuevos."
                                      : "No se ha podido consultar: " + c.errors.joined(separator: ", "))
                : c.items.map { "• " + $0 }.joined(separator: "\n")
            if !c.notes.isEmpty { text += "\n" + c.notes.map { "• " + $0 }.joined(separator: "\n") }
            if !c.items.isEmpty && !c.errors.isEmpty { text += "\n(No se ha podido consultar: " + c.errors.joined(separator: ", ") + ")" }
        }
        return TileCard(wide: true) {
            Tile("Componentes", text) {
                Button("Buscar de nuevo") { model.components = nil; model.reloadComponents() }.disabled(model.busy || c == nil)
                if let c = c, !c.items.isEmpty {
                    Button("Actualizar todo (\(c.items.count))") { model.updateComponents(c) }
                        .buttonStyle(OutlineButton(kind: "primary"))
                        .disabled(model.busy)
                }
            }
        }
        .onAppear { if model.components == nil { model.reloadComponents() } }
    }

    /// El interruptor del correo de pruebas (al lado del título del apartado)
    func mailSwitch(_ m: MailState) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { m.on }, set: { model.setMail($0) }))
                .toggleStyle(SwitchToggleStyle()).labelsHidden()
                .disabled(model.busy)
                .tip(m.on ? "Encendido: el correo de las webs va a Mailpit" : "Apagado: lo que manden las webs puede llegar de verdad a los clientes")
            if !m.on {
                Text("Apagado: lo que manden las webs puede llegar de verdad a los clientes")
                    .font(.caption).foregroundColor(.orange)
            }
        }
    }

    /// Correo de pruebas (Mailpit): encenderlo, los plugins de correo de WordPress y la bandeja
    @ViewBuilder
    func mailCard(_ d: AppData) -> some View {
        if let m = d.mail {
            TileCard("Correo de pruebas (Mailpit)", "Lo que mandan las webs de este Mac (formularios, pedidos, contraseñas) no llega a nadie: va a Mailpit, que lo enseña en su bandeja. PHP (mail()) en todas las versiones, PrestaShop por SMTP y WordPress según su opción. Lo que se cambia en las BBDD no va en las copias que descargas (exportar-bd, copiar-bd, Docker). Mailpit arranca y para con la versión activa y solo se ve desde este Mac.", tiles: true,
                     lead: AnyView(LogoShape(d: LOGO_PATHS["mailpit"] ?? "").fill(brand("mailpit")).frame(width: 20, height: 20)),
                     tail: AnyView(mailSwitch(m))) {
                Tile("WordPress con plugins de SMTP o Brevo", mailWpText(m.wp)) {
                    SearchPicker(selection: Binding(get: { m.wp }, set: { model.setMailWp($0) }),
                                 items: [("mailpit", "Llevarlos a Mailpit"), ("desactivar", "Desactivarlos en la copia local"),
                                         ("nada", "No tocarlos")], width: 250)
                    .disabled(!m.on || model.busy)
                    .tip("Qué hacer con sus plugins de correo")
                }
                if m.installed {
                    Tile("Bandeja de entrada", mailInboxText(m)) {
                        if !m.version.isEmpty && !m.offer.isEmpty && verParts(m.version).lexicographicallyPrecedes(verParts(m.offer)) {
                            Button("Actualizar a \(m.offer)") { model.installMail() }
                                .buttonStyle(OutlineButton(kind: "primary"))
                                .disabled(model.busy)
                        }
                        Button("Vaciar") { model.clearMail() }.disabled(!m.running || model.busy)
                    }
                } else {
                    Tile("Mailpit no está instalado",
                        "Sin él, el correo de las webs no sale ni se ve. Se descarga de GitHub (Mailpit \(m.offer)) y se comprueba antes de instalarlo") {
                        Button("Instalar Mailpit") { model.installMail() }
                            .buttonStyle(OutlineButton(kind: "primary"))
                            .disabled(model.busy)
                    }
                }
            }
            if m.installed {
                mailInbox(m)
            }
        }
    }

    /// Debajo de las tarjetas: la bandeja de Mailpit o por qué no se ve
    @ViewBuilder
    func mailInbox(_ m: MailState) -> some View {
        Group {
            if m.running {
                MailWebView(host: model.mailWeb, url: m.url)
                    // (mientras se ve, el número de sin leer de arriba sigue a lo que se lee o se borra aquí)
                    .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in model.pollMail() }
            } else {
                Text("Mailpit está parado: arranca con la versión activa.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 620)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 1))
    }

    func mailInboxText(_ m: MailState) -> String {
        let v = m.version.isEmpty ? "?" : m.version
        let state = m.running ? "en marcha: " + m.url : "parado: arranca con la versión activa"
        return "Mailpit " + v + " · " + state
    }

    /// Lo que pasa con los plugins de correo de WordPress en cada modo
    func mailWpText(_ mode: String) -> String {
        switch mode {
        case "desactivar": return "Se desactivan en la copia local: WordPress manda con mail(), a Mailpit"
        case "nada": return "⚠ No se tocan: lo que manden puede llegar de verdad a los clientes"
        default: return "Siguen funcionando, con su correo a Mailpit (los que usan una API, como Brevo, se desactivan en la copia local)"
        }
    }

    /// Registro de errores del vhost de los proyectos (web.local), sacado de su ErrorLog: con
    /// PHP-FPM, los errores de PHP de la web cargada van ahí y no al error_log general de Apache
    func projectErrorLog(_ d: AppData) -> String? {
        return projectErrorLogPath(link: model.projects?.link ?? "", vhosts: d.vhosts)
    }

    /// Fila de un registro de errores: dónde está, cuánto ocupa y cuándo se cambió
    func errorLogRow(_ d: AppData, path: String, title: String) -> some View {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? -1
        let date = attrs?[.modificationDate] as? Date ?? Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "dd/MM/yyyy HH:mm"
        let sizeText = ByteCountFormatter.string(fromByteCount: max(size, 0), countStyle: .file)
        let sub = size < 0 ? "\(path): no existe todavía (se crea con el primer error)"
            : "\(path)  ·  \(sizeText)  ·  modificado el \(fmt.string(from: date))"
        return Tile(title, sub) {
            Button("Ver el final") { model.showLogTail(path) }.disabled(size <= 0)
            Button("Abrir") { model.openInEditor(path) }
                .disabled(size < 0 || size > LOG_OPEN_MAX)
                .tip(size > LOG_OPEN_MAX ? "Ocupa \(sizeText): usa «Ver el final»" : path)
        }
    }

    func openFolder(_ path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        showFolder(path)
    }

    /// XAMPP oficial: apartarlo, volver a él y cargar las copias de sus bases
    func officialCard(_ d: AppData) -> some View {
        TileCard("XAMPP oficial",
             "Si este Mac tenía un XAMPP oficial en /Applications/XAMPP: al apartarlo se copian sus BBDD, sus proyectos y sus vhosts, sin borrar nada.", wide: true) {
            if d.official {
                Tile("Hay un XAMPP oficial en /Applications/XAMPP", "Hay que apartarlo para activar las versiones del gestor") {
                    Button("Apartar…") { model.setAside() }.disabled(model.busy)
                }
            } else if d.asides.isEmpty && d.copies.isEmpty {
                Tile("No hay ningún XAMPP oficial apartado")
            }
            ForEach(d.copies.keys.sorted(), id: \.self) { folder in
                Tile("BBDD de \((folder as NSString).lastPathComponent)",
                    "\(plural(d.copies[folder] ?? 0, "copia", "copias")) en ~/nexum-backups. Las que ya existan en la versión activa no se tocan.") {
                    Button("Carpeta") { showFolder(folder) }
                    Button(d.active.isEmpty ? "Cargar" : "Cargar en XAMPP-\(d.active)") { model.importBackups(folder) }
                        .disabled(model.busy || d.active.isEmpty || !d.running)
                        .tip(d.active.isEmpty || !d.running ? "Activa y arranca antes una versión" : "Carga estas BBDD en la versión activa")
                }
            }
            ForEach(d.asides, id: \.self) { a in
                Tile((a as NSString).lastPathComponent, "Si algo no va: se desactiva la versión del gestor y vuelve a /Applications/XAMPP") {
                    Button("Volver al XAMPP oficial…") { model.restoreOfficial(a) }.disabled(model.busy || d.official)
                }
            }
        }
    }
}

/// Configuración, General, Registro de tareas (como en Linux): las tareas que ha lanzado la ventana (las
/// TASKS_KEEP últimas de TASKS_DIR), cada una con su fecha y cómo acabó; con «Ver», entera
struct TaskLogsCard: View {
    @EnvironmentObject var model: AppModel
    @State private var logs: [TaskLogEntry] = []
    /// Cuántas se ven (las 15 más nuevas; «Ver más», de 50 en 50)
    @State private var shown = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TileCard(wide: true) {
                if logs.isEmpty {
                    Tile("Todavía no hay ninguna tarea", "Cada tarea que lances desde la ventana se guarda aquí")
                }
                ForEach(Array(logs.prefix(shown))) { e in
                    Tile(e.title, e.when + "  ·  " + e.result, leading: { mark(e.state) }) {
                        Button("Ver") { showTaskLog(e.path) }
                            .tip(e.command)
                    }
                }
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if logs.count > shown {
                    Button("Ver más (\(logs.count - shown))") { shown += 50 }
                }
                Button("Abrir la carpeta") {
                    _ = taskLogDir()
                    NSWorkspace.shared.open(URL(fileURLWithPath: TASKS_DIR))
                }
            }
        }
        .onAppear { logs = taskLogs() }
        .onChange(of: model.taskLogsChanged) { _ in logs = taskLogs() }
    }

    /// Cómo acabó: bien (verde), mal (rojo), cancelada o en marcha
    func mark(_ state: String) -> some View {
        let m: (String, Color, String) = state == "ok" ? ("checkmark.circle.fill", GREEN, "Terminada bien")
            : state == "error" ? ("xmark.octagon.fill", RED, "Ha fallado")
            : state == "cancel" ? ("stop.circle", Color.secondary, "Cancelada")
            : ("play.circle", Color.secondary, "En marcha")
        return Image(systemName: m.0).font(.system(size: 16)).foregroundColor(m.1).frame(width: 22).tip(m.2)
    }
}

/// Limpieza (nexum gui-limpieza y limpiar <clave>...), como en Linux: cada cosa, con su título, lo que
/// es y qué pasa si se limpia, lo que se hace (en la confirmación) y si va marcada de partida
struct CleanItem {
    let key: String
    let title: String
    let desc: String
    let step: String
    let on: Bool
}

let CLEAN_ITEMS: [CleanItem] = [
    CleanItem(key: "descargas", title: "Caché de descargas",
              desc: "Los paquetes de código de PHP, Apache, MariaDB, phpMyAdmin… que el programa descargó para instalar o actualizar tus versiones de PHP. Están en \(DL_CACHE_DIR). Solo sirven para no descargarlos otra vez si repites una instalación (o si la web de donde salen no responde). Las versiones ya instaladas no los usan: si se limpia, todo sigue igual y la próxima instalación los vuelve a descargar. No toca ningún proyecto.",
              step: "se vacía \(DL_CACHE_DIR): la próxima instalación lo vuelve a descargar", on: true),
    CleanItem(key: "copias", title: "Copias de seguridad",
              desc: "Las copias que guardó el programa cuando se lo pediste («Guardar antes una copia» al borrar, sustituir o actualizar una BBDD o una versión), las de las BBDD del XAMPP oficial al apartarlo y, si lo tienes encendido, las de los ficheros que cambia por su cuenta (hosts, vhosts…). Están en ~/nexum-backups. Sirven para volver atrás si algo salió mal. Tus proyectos y sus BBDD de ahora no las usan y siguen igual, pero lo que había antes ya no se podrá recuperar (las del XAMPP oficial que no hayas cargado siguen en el XAMPP apartado): por eso va sin marcar.",
              step: "se borra todo lo de ~/nexum-backups (la carpeta se queda): ya no se podrá volver atrás con ellas", on: false),
    CleanItem(key: "correo", title: "Correo de pruebas",
              desc: "Los correos que han mandado tus webs locales (formularios, pedidos, contraseñas olvidadas…) y que Mailpit ha recogido para que no lleguen a nadie: los de su bandeja, en Configuración, Correo de pruebas. Solo sirven para ver qué mandaron las webs. Si se limpia, la bandeja se queda vacía y Mailpit sigue recogiendo los nuevos; las webs no notan nada. Mailpit tiene que estar en marcha (va con la versión activa).",
              step: "se vacía la bandeja de Mailpit", on: false),
    CleanItem(key: "registros", title: "Registros del programa",
              desc: "Lo que el programa ha ido apuntando de sus tareas: las instalaciones y actualizaciones de las versiones (y lo que dejan las que fallan), el registro de tareas de la ventana, los de los servidores de Node parados y el de la compilación de la ventana. Están en ~/.lvm-instalador. Solo sirven para ver qué pasó en una tarea anterior o buscar por qué falló. Sus ajustes no se tocan, ni lo que esté usando una tarea o un servidor en marcha: el programa y tus proyectos siguen igual.",
              step: "se borran los registros de ~/.lvm-instalador (no sus ajustes ni lo que esté usando una tarea o un servidor de Node en marcha)", on: true),
    CleanItem(key: "registros-versiones", title: "Registros de las versiones",
              desc: "Lo que apunta cada versión de PHP: Apache (las visitas y los errores, también los de cada web), PHP-FPM, los errores de PHP y MariaDB. Están en xamppfiles/logs de cada /Library/Nexum/XAMPP-<versión> (el de MariaDB, con sus datos). Sirven para buscar por qué falla una web (Configuración, General, Registro de errores). Se vacían, no se borran: Apache, PHP y MariaDB siguen escribiendo en ellos sin pararse. Solo se pierde lo que decían hasta ahora; las webs y sus BBDD no cambian.",
              step: "se vacían los registros de Apache, PHP-FPM, PHP y MariaDB de cada versión (siguen en marcha)", on: true),
    CleanItem(key: "caches-proyectos", title: "Cachés de los proyectos",
              desc: "Las páginas y plantillas que WordPress (wp-content/cache, la de sus plugins de caché) y PrestaShop (var/cache y las de Smarty) guardan ya preparadas para ir más deprisa, en cada proyecto de \(HTDOCS). Son solo una copia que se rehace sola: si se limpia, la primera visita a cada página va algo más lenta mientras se vuelve a crear. Nada más del proyecto se toca: ni sus ficheros, ni sus imágenes, ni su BBDD.",
              step: "se vacían las cachés de los proyectos de \(HTDOCS) (se rehacen solas)", on: true),
    CleanItem(key: "temporales", title: "Temporales",
              desc: "Ficheros y carpetas de trabajo que dejan las tareas del programa cuando se cortan a medias (una descarga, el volcado de una BBDD que se iba a cargar, la lista de imágenes de una tienda…), en /tmp y en ~/.lvm-instalador. Ya no sirven para nada. Solo se borra lo que lleva más de un día sin cambiar y no está usando ningún programa (un MariaDB temporal en marcha, por ejemplo, se deja). No afecta a ningún proyecto ni a ninguna versión.",
              step: "se borran los temporales del programa de más de un día que nada usa", on: true),
    CleanItem(key: "sesiones", title: "Sesiones de PHP",
              desc: "Los ficheros con los que PHP recuerda quién ha entrado en una web local: tu sesión en phpMyAdmin y la de las webs o plugins que usan las sesiones de PHP (WordPress y PrestaShop guardan la suya en una cookie: esa no se cierra). Están en xamppfiles/temp de cada versión y en /tmp. Si se limpian, esas sesiones se cierran y hay que volver a entrar; las webs, sus ficheros y sus BBDD no cambian. Va sin marcar para no cerrarte nada sin querer.",
              step: "se borran las sesiones de PHP: hay que volver a entrar en phpMyAdmin y en lo que las use", on: false),
]

/// Limpiar proyecto (gui-limpiar-proyecto y limpiar-proyecto): cada clave, con su título y lo que se hace
let PROJECT_CLEAN_ITEMS: [(key: String, title: String, step: String)] = [
    ("cache", "Caché", "se vacía su caché"),
    ("registros", "Registros", "se borran sus registros"),
    ("actualizaciones", "Restos de actualizaciones", "se vacían los restos de las actualizaciones"),
]

/// El aviso en rojo de las confirmaciones de la limpieza
let CLEAN_WARNING = "Lo que se limpia no se puede recuperar: no se hacen copias."

/// Lo que ocupa una cosa que se puede limpiar (de gui-limpieza o gui-limpiar-proyecto)
struct CleanSize {
    let bytes: Int64
    let files: Int
}

func cleanSizeText(_ v: CleanSize) -> String {
    return "\(fmtSize(v.bytes)) · \(plural(v.files, "fichero", "ficheros"))"
}

/// Configuración, Limpieza: lo que Nexum va dejando con el uso, cada cosa con lo que ocupa y su casilla; arriba,
/// el total, y debajo «Limpiar lo marcado…». Se mide por detrás (gui-limpieza): hasta entonces, «Midiendo…»
struct CleanCard: View {
    @EnvironmentObject var model: AppModel
    /// Lo que ocupa cada cosa; nil mientras se mide
    @State private var sizes: [String: CleanSize]? = nil
    @State private var failed = ""

    func marked(_ it: CleanItem) -> Bool {
        return model.cleanMarks[it.key] ?? it.on
    }

    var body: some View {
        let s = sizes ?? [:]
        let picked = CLEAN_ITEMS.filter { marked($0) && (s[$0.key]?.files ?? 0) > 0 }.map { $0.key }
        let all = s.values.filter { $0.files > 0 }.reduce(Int64(0)) { $0 + $1.bytes }
        let sel = picked.reduce(Int64(0)) { $0 + (s[$1]?.bytes ?? 0) }
        let summary = sizes == nil ? (failed.isEmpty ? "Midiendo…" : failed)
            : (all > 0 ? "Total: \(fmtSize(all)) · marcado: \(fmtSize(sel))" : "Total: nada que limpiar")
        return VStack(alignment: .leading, spacing: 12) {
            TileCard("Limpieza", "Lo que Nexum va dejando con el uso y se puede borrar para recuperar espacio. Ningún proyecto ni ninguna versión de PHP lo necesita para funcionar: cada cosa dice qué es y qué pasa si se limpia. Lo que se limpia no se puede recuperar: no se hacen copias.") {
                Tile("Lo que se puede limpiar", summary)
                ForEach(CLEAN_ITEMS, id: \.key) { it in
                    let v = s[it.key] ?? CleanSize(bytes: 0, files: 0)
                    Tile(it.title, it.desc) {
                        Text(sizes == nil ? "…" : (v.files > 0 ? cleanSizeText(v) : "Vacío"))
                            .font(.caption).foregroundColor(.secondary)
                            .frame(minWidth: 150, alignment: .trailing)
                        Toggle("", isOn: Binding(get: { marked(it) }, set: { model.cleanMarks[it.key] = $0 }))
                            .toggleStyle(CheckboxToggleStyle()).labelsHidden()
                            .disabled(model.busy || v.files == 0)
                    }
                }
            }
            HStack {
                Spacer(minLength: 0)
                Button("Limpiar lo marcado…") { model.cleanRun(picked, s) { measure() } }
                    .buttonStyle(OutlineButton(kind: "stop"))
                    .disabled(model.busy || picked.isEmpty)
            }
        }
        .onAppear { measure() }
    }

    func measure() {
        runQuick(["gui-limpieza"]) { _, out in
            var got: [String: CleanSize] = [:]
            for f in parseLines(out) where f.count >= 4 && f[0] == "L" {
                if let b = Int64(f[2]), let n = Int(f[3]) {
                    got[f[1]] = CleanSize(bytes: b, files: n)
                }
            }
            if got.isEmpty {
                failed = "No se ha podido medir"
                sizes = nil
            } else {
                failed = ""
                sizes = got
            }
        }
    }
}
