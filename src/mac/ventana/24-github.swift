// MARK: repositorios de GitHub

struct GitHubState: Equatable {
    var on = false
    var login = "", source = "", account = "", prefixes = ""
}

struct RepoItem: Equatable, Identifiable {
    var id: String { full }
    let full, name: String
    let isPrivate: Bool
    let date, branch, prefix, web, desc, state, folder: String
}

/// Lo que dice repos: la cabecera (C|usuario|cuenta|tipo|cuántos|cuántos se ven), los repositorios y el error
struct ReposData: Equatable {
    var head: [String] = []
    var items: [RepoItem] = []
    var error: String? = nil
}

/// Buscador de Nuevo proyecto: al abrir el asistente, si hace más de estos segundos que no se pregunta a
/// GitHub, se le pregunta por detrás
let NP_REPOS_FRESH: TimeInterval = 300

/// Lo que se busca en la lista de repositorios: dueño/repo si es una dirección de GitHub
func repoQuery(_ text: String) -> String {
    var q = text.trimmingCharacters(in: .whitespaces).lowercased()
    for p in ["git@github.com:", "ssh://git@github.com/", "https://github.com/", "http://github.com/"] where q.hasPrefix(p) {
        q = String(q.dropFirst(p.count))
        break
    }
    if q.hasSuffix("/") { q = String(q.dropLast()) }
    if q.hasSuffix(".git") { q = String(q.dropLast(4)) }
    return q
}

func parseRepos(_ out: String) -> ReposData {
    var r = ReposData()
    for f in parseLines(out) {
        switch f.first ?? "" {
        case "C" where f.count >= 6: r.head = f
        case "R" where f.count >= 11:
            r.items.append(RepoItem(full: f[1], name: f[2], isPrivate: f[3] == "1", date: f[4], branch: f[5],
                                    prefix: f[6], web: f[7], desc: f[8], state: f[9], folder: f[10]))
        case "E" where f.count >= 2: r.error = f[1]
        default: break
        }
    }
    return r
}

/// Configuración, Docker: los proyectos sin visitas se paran solos (docker-reposo): cuántas horas (0:
/// nunca; 3 si no se ha dicho) y lo último que se ha parado
struct IdleStopCard: View {
    @EnvironmentObject var model: AppModel
    @State private var hours = "3"
    @State private var last = ""
    let choices = ["0", "1", "2", "3", "4", "6", "8", "12", "24"]

    var body: some View {
        TileCard(wide: true) {
            Tile("Parar los proyectos sin visitas",
                 (hours != "0" ? "Un proyecto de Docker que lleva esas horas sin ninguna visita (tampoco por el túnel) se para solo, y con él lo común que ya no use nadie (su MariaDB, el Apache de Docker): no gasta memoria ni CPU de la máquina virtual. Se mira cada 15 minutos, también con la ventana cerrada. Al entrar en uno parado, la web lo dice: se arranca en la pestaña Docker."
                  : "Apagado: los proyectos de Docker siguen en marcha hasta que se paren a mano")
                 + (hours != "0" && !last.isEmpty ? "\nLo último: " + last : "")) {
                SearchPicker(selection: Binding(get: { hours }, set: { h in
                    guard h != hours else { return }
                    hours = h
                    runQuick(["docker-reposo", "horas", h]) { _, out in
                        model.toast(out.split(separator: "\n").last.map(String.init) ?? "Hecho")
                        read()
                    }
                }), items: (choices + (choices.contains(hours) ? [] : [hours])).map { h in
                    (h, h == "0" ? "Nunca" : h == "1" ? "A la hora sin visitas" : "A las \(h) h sin visitas")
                }, width: 210)
                .busyGuard(model.busy)
            }
        }
        .onAppear { read() }
    }

    func read() {
        let v = ((try? String(contentsOfFile: LOG_DIR + "/docker/reposo", encoding: .utf8)) ?? "3")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        hours = v.range(of: "^([0-9]|1[0-9]|2[0-4])$", options: .regularExpression) != nil ? v : "3"
        last = ((try? String(contentsOfFile: LOG_DIR + "/docker-reposo.log", encoding: .utf8)) ?? "")
            .split(separator: "\n").last.map(String.init) ?? ""
    }
}

/// Configuración, Docker: WP-CLI en los contenedores de PHP (docker-wp-cli), apagado de serie. La imagen de una
/// versión de PHP es la de todos sus proyectos: al cambiarlo pregunta si se rehacen ya las que hay
/// Configuración, Docker: la PostgreSQL común de Docker (docker-postgres: G|versión|estado|puerto|contenedor, O|las que se ofrecen)
struct PgCard: View {
    @EnvironmentObject var model: AppModel
    @State private var have: [[String]] = []
    @State private var offer: [String] = []
    @State private var pick = ""

    var body: some View {
        TileCard(wide: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text("PostgreSQL de Docker").font(.system(size: 13, weight: .semibold))
                Text("Una común por versión, como las MariaDB, para todos los proyectos de Docker: desde sus PHP, nexum-postgres-<versión>, puerto 5432; desde este Mac (tus herramientas de BBDD), 127.0.0.1 y su puerto. Usuario postgres. Con alguna, las imágenes de PHP de Docker traen pgsql y pdo_pgsql." + (have.isEmpty ? " Aún no hay ninguna." : ""))
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(have, id: \.self) { f in
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Text("PostgreSQL \(f[1]) · \(f[2] == "marcha" ? "en marcha" : f[2] == "parado" ? "parada" : f[2]) · 127.0.0.1:\(f[3])").font(.caption)
                        Button("Copiar contraseña") { copyPass(f[1]) }
                        Button(f[2] == "marcha" ? "Parar" : "Arrancar") {
                            let act = f[2] == "marcha" ? "parar" : "arrancar"
                            _ = model.runTask("PostgreSQL \(f[1]) de Docker", ["docker-postgres", act, f[1]], progress: act == "arrancar",
                                              doneText: "PostgreSQL \(f[1]) " + (act == "parar" ? "parada" : "en marcha"), autoClose: true) { _, _, _ in load() }
                        }
                        .busyGuard(model.busy)
                        Button("Borrar") {
                            guard confirm("¿Borrar la PostgreSQL \(f[1]) de Docker?", "Se borran su contenedor y todas sus BBDD. No se puede deshacer.",
                                          "Borrar", destructive: true) else { return }
                            _ = model.runTask("Borrando la PostgreSQL \(f[1]) de Docker", ["docker-postgres", "borrar", f[1]],
                                              doneText: "PostgreSQL \(f[1]) borrada", autoClose: true) { _, _, _ in load() }
                        }
                        .busyGuard(model.busy)
                    }
                }
                let free = offer.filter { v in !have.contains { $0[1] == v } }
                if !free.isEmpty {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        SearchPicker(selection: $pick, items: free.map { ($0, $0) }, width: 80)
                        Button("Crear") { create(free.contains(pick) ? pick : free[0]) }
                            .buttonStyle(OutlineButton(kind: "primary"))
                            .busyGuard(model.busy)
                    }
                }
            }
            .padding(14)
        }
        .onAppear { load() }
    }

    func load() {
        runQuick(["docker-postgres"]) { _, out in
            let lines = parseLines(out)
            have = lines.filter { $0.first == "G" && $0.count >= 5 }
            offer = lines.first { $0.first == "O" && $0.count >= 2 }?[1].split(separator: " ").map(String.init) ?? []
            if pick.isEmpty || have.contains(where: { $0[1] == pick }) { pick = offer.first { v in !have.contains { $0[1] == v } } ?? "" }
        }
    }

    func create(_ v: String) {
        guard confirm("¿Crear la PostgreSQL \(v) de Docker?",
                      "Una común para todos los proyectos de Docker, con el usuario postgres y una contraseña al azar («Copiar contraseña»). Se descarga su imagen oficial y, si tienes imágenes de PHP de Docker, se rehacen con pgsql y pdo_pgsql (unos minutos cada una).",
                      "Crear") else { return }
        _ = model.runTask("Creando la PostgreSQL \(v) de Docker", ["docker-postgres", "arrancar", v], progress: true,
                          doneText: "PostgreSQL \(v) en marcha", autoClose: true) { _, _, _ in load() }
    }

    /// La contraseña del usuario postgres, al portapapeles (de su .env, solo tuyo)
    func copyPass(_ v: String) {
        let text = (try? String(contentsOfFile: LOG_DIR + "/docker/postgres-\(v)/.env", encoding: .utf8)) ?? ""
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("PG_PASS=") }) else {
            model.toast("No se ha podido leer su contraseña")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(line.dropFirst(8)), forType: .string)
        model.toast("Contraseña de postgres copiada")
    }
}

/// Configuración, Docker: el Nginx común de Docker (docker-nginx: X|estado|dirección|http|https, Y|proyecto|1 si va por Nginx|direcciones)
struct DockerNginxCard: View {
    @EnvironmentObject var model: AppModel
    @State private var x: [String] = []
    @State private var projects: [[String]] = []
    @State private var http = ""
    @State private var https = ""

    var body: some View {
        TileCard(wide: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nginx de Docker").font(.system(size: 13, weight: .semibold))
                Text(desc()).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                if x.count >= 5 && x[1] != "?" {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        port("HTTP", $http)
                        port("HTTPS", $https)
                        Button("Guardar puertos") { save() }.busyGuard(model.busy)
                        Button(x[1] == "marcha" ? "Parar" : "Arrancar") {
                            let act = x[1] == "marcha" ? "parar" : "arrancar"
                            _ = model.runTask("Nginx de Docker", ["docker-nginx", act], progress: act == "arrancar",
                                              doneText: "Nginx de Docker " + (act == "parar" ? "parado" : "en marcha"), autoClose: true) { _, _, _ in load() }
                        }
                        .buttonStyle(OutlineButton(kind: x[1] == "marcha" ? "" : "primary"))
                        .busyGuard(model.busy)
                    }
                    Divider().padding(.vertical, 4)
                    Text("Proyectos en el Nginx de Docker").font(.system(size: 13, weight: .semibold))
                    Text(projects.isEmpty ? "Aún no hay proyectos de Docker: créalos en la pestaña Docker"
                                          : "Marca los que van también por el Nginx de Docker (con el Apache de Docker siguen igual)")
                        .font(.caption).foregroundColor(.secondary)
                    ForEach(projects, id: \.self) { f in
                        Toggle(isOn: Binding(get: { f[2] == "1" }, set: { v in
                            _ = model.runTask("Nginx de Docker: \(f[1])", ["docker-nginx", v ? "anadir" : "quitar", f[1]],
                                              doneText: "\(f[1]) " + (v ? "en el Nginx de Docker" : "fuera del Nginx de Docker"), autoClose: true) { _, _, _ in load() }
                        })) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f[1])
                                if f[2] == "1" && !f[3].isEmpty { Text(f[3]).font(.caption).foregroundColor(.secondary) }
                            }
                        }
                        .toggleStyle(CheckboxToggleStyle())
                        .busyGuard(model.busy)
                    }
                }
            }
            .padding(14)
        }
        .onAppear { load() }
    }

    func desc() -> String {
        guard x.count >= 5 else { return "Consultando…" }
        if x[1] == "?" { return "Docker no está en marcha: arráncalo en la pestaña Docker" }
        let st = ["marcha": "En marcha.", "parado": "Parado.", "nuevo": "Aún no se ha creado: «Arrancar» lo crea (imagen oficial de Nginx)."][x[1]] ?? ""
        return "Uno común, al lado del Apache de Docker, para los proyectos de Docker que le añadas: en \(x[2]), con los mismos dominios, en los puertos \(x[3]) (http) y \(x[4]) (https). Delante del Apache del contenedor de PHP de cada proyecto (en el Mac, las imágenes de PHP de Docker llevan Apache). \(st)"
    }

    func load() {
        runQuick(["docker-nginx"]) { _, out in
            let lines = parseLines(out)
            x = lines.first { $0.first == "X" && $0.count >= 5 } ?? []
            projects = lines.filter { $0.first == "Y" && $0.count >= 4 }
            if x.count >= 5 {
                if http.isEmpty { http = x[3] }
                if https.isEmpty { https = x[4] }
            }
        }
    }

    func save() {
        let h = http.trimmingCharacters(in: .whitespaces), s = https.trimmingCharacters(in: .whitespaces)
        guard let a = Int(h), let b = Int(s), (1024...65535).contains(a), (1024...65535).contains(b), a != b else {
            message("Puertos no válidos", "Dos números distintos, de 1024 a 65535 (como 8081 y 8444).", error: true)
            return
        }
        _ = model.runTask("Puertos del Nginx de Docker", ["docker-nginx", "puertos", h, s], doneText: "Nginx de Docker en los puertos \(h) y \(s)",
                          autoClose: true) { _, _, _ in load() }
    }

    func port(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField("", text: text).textFieldStyle(PlainTextFieldStyle())
                .padding(.horizontal, 8)
                .frame(width: 60, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.2), lineWidth: 1))
        }
    }
}

struct WpCliCard: View {
    @EnvironmentObject var model: AppModel
    @State private var on = false

    var body: some View {
        TileCard(wide: true) {
            Tile("WP-CLI en los contenedores de PHP",
                 on ? "Puesto: wp dentro de los contenedores, con la base de datos de Docker (docker exec <contenedor> wp …). Vale para todos los proyectos de Docker"
                    : "Apagado: los contenedores de PHP no traen wp. Al ponerlo, vale para todos los proyectos de Docker") {
                Toggle("", isOn: Binding(get: { on }, set: { v in if v != on { change(v) } }))
                    .toggleStyle(SwitchToggleStyle()).labelsHidden()
                    .busyGuard(model.busy)
            }
        }
        .onAppear { read() }
    }

    func read() {
        on = FileManager.default.fileExists(atPath: LOG_DIR + "/docker/wp-cli")
    }

    func change(_ v: Bool) {
        if let guardTask = TASK_GUARD, guardTask() { return }
        let r = runDialog(title: v ? "¿Poner WP-CLI en los contenedores de PHP?" : "¿Quitar WP-CLI de los contenedores de PHP?",
                          text: v ? "Las imágenes de PHP de Docker traerán WP-CLI: podrás ejecutar wp en el contenedor de cada proyecto, con su base de datos de Docker. La imagen de una versión de PHP es la de todos sus proyectos, así que vale para todos. Los proyectos en marcha se vuelven a crear con la imagen nueva; sus bases de datos y su configuración no cambian."
                                  : "Las imágenes de PHP de Docker dejarán de traer WP-CLI, en todos los proyectos. Los que estén en marcha se vuelven a crear con la imagen nueva; sus bases de datos y su configuración no cambian.",
                          okLabel: v ? "Poner" : "Quitar", style: .informational, destructive: false,
                          checkbox: "Rehacer ya las imágenes de PHP que tienes (unos minutos cada una)", checked: true)
        guard r.ok else { return }
        _ = model.runTask(v ? "Poniendo WP-CLI en Docker" : "Quitando WP-CLI de Docker",
                          ["docker-wp-cli", v ? "si" : "no"] + (r.checked ? ["--rehacer"] : []),
                          doneText: "WP-CLI en Docker " + (v ? "puesto" : "quitado"), autoClose: !r.checked) { _, _, _ in read() }
    }
}

/// Configuración, GitHub: la conexión (un token en el Llavero o la sesión de gh), la organización o cuenta
/// y los prefijos de los repositorios que se ven en Repositorios
struct GitHubCard: View {
    @EnvironmentObject var model: AppModel
    @State private var account = ""
    @State private var prefixes = ""
    @State private var loaded = false

    var body: some View {
        let g = model.github
        let how = ["llavero": "con el token del Llavero", "gh": "con tu sesión de gh"][g?.source ?? ""] ?? ""
        return TileCard("GitHub (Repositorios)", "Para la pestaña Repositorios: la lista de una organización o cuenta de GitHub, para clonarlos por SSH (con tu clave) en \(HTDOCS). La lista se lee con un token de GitHub, que se guarda en el Llavero (no en un fichero), o con tu sesión de gh. Solo se ven los repositorios que empiezan por alguno de los prefijos (en la pestaña, «Mostrar todos» enseña el resto).") {
            Tile("Conexión", g == nil ? "Comprobando…" : g!.on ? "Conectado como \(g!.login), \(how)"
                 : !(g!.source.isEmpty) ? "⚠ El token ya no vale (¿caducado?): conéctalo de nuevo"
                 : "Sin conectar: hace falta para ver la lista de repositorios (también los privados)") {
                Button("Conectar con un token…") { model.githubToken() }
                    .buttonStyle(OutlineButton(kind: g?.on == true ? "" : "primary"))
                    .busyGuard(model.busy)
                if g?.source != "gh" && ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                    Button("Usar la sesión de gh") { runQuick(["github-conectar", "--gh"]) { rc, out in model.githubDone(rc, out) } }
                        .busyGuard(model.busy)
                        .tip("Usar la sesión de gh auth login")
                }
                if !(g?.source ?? "").isEmpty {
                    Button("Desconectar") { runQuick(["github-desconectar"]) { rc, out in model.githubDone(rc, out) } }
                        .busyGuard(model.busy)
                }
            }
            Tile("Organización o cuenta", "La de los repositorios que se ven (por ejemplo, mi-empresa)") {
                TextField("", text: $account).textFieldStyle(RoundedBorderTextFieldStyle()).frame(width: 170)
                Button("Guardar") { model.githubSet("cuenta", account.trimmingCharacters(in: .whitespaces)) }
                    .disabled(account.trimmingCharacters(in: .whitespaces) == (g?.account ?? "")).busyGuard(model.busy)
            }
            Tile("Prefijos de los repositorios", "Separados por espacios (wordpress- tienda- …); vacío: todos") {
                TextField("", text: $prefixes).textFieldStyle(RoundedBorderTextFieldStyle()).frame(width: 240)
                Button("Guardar") { model.githubSet("prefijos", prefixes.trimmingCharacters(in: .whitespaces)) }
                    .disabled(prefixes.trimmingCharacters(in: .whitespaces) == (g?.prefixes ?? "")).busyGuard(model.busy)
            }
        }
        .onAppear { if model.github == nil { model.reloadGithub() } else { fill() } }
        .onChange(of: model.github) { _ in fill() }
    }

    func fill() {
        account = model.github?.account ?? ""
        prefixes = model.github?.prefixes ?? ""
    }
}

/// Pestaña Repositorios: los de la organización o cuenta de GitHub (Configuración), para clonarlos por SSH
/// Un proyecto de Node (gui-node: P|carpeta|tipo|parado o marcha|modo|dirección|Node que pide|dependencias|scripts)
struct NodeItem: Equatable, Identifiable {
    var id: String { folder }
    let folder, kind: String
    let running: Bool
    let mode, url, need: String
    let deps: Bool
}

func parseNode(_ out: String) -> [NodeItem] {
    parseLines(out).compactMap { f in
        guard f.first == "P", f.count >= 9 else { return nil }
        return NodeItem(folder: f[1], kind: f[2], running: f[3] == "marcha", mode: f[4], url: f[5], need: f[6], deps: f[7] == "1")
    }
}

struct NodeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        WidePage {
            PageTitle(title: "Node",
                      sub: "Proyectos de \(HTDOCS) hechos con Astro, Next, Nuxt, SvelteKit o Vite. Cada uno con su servidor en este Mac, con tu usuario y con la versión de Node que pide.",
                      symbol: "chevron.left.forwardslash.chevron.right", brandTitle: "node")
            let items = model.nodeItems ?? []
            Card {
                if items.isEmpty {
                    Text(model.nodeItems == nil ? "Cargando…" : "Ningún proyecto de Node: se buscan las carpetas con su package.json")
                        .foregroundColor(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        row(item)
                        if item != items.last { Divider().padding(.leading, 34) }
                    }
                }
            }
        }
    }

    func row(_ p: NodeItem) -> some View {
        var bits = [p.kind, p.need.isEmpty ? "" : "Node \(p.need)"]
        if p.running {
            bits.append("en marcha (\(p.mode)): \(p.url)")
        } else if !p.deps {
            bits.append("sin dependencias instaladas: se instalan al arrancar")
        }
        let text = bits.filter { !$0.isEmpty }.joined(separator: " · ")
        let path = HTDOCS + "/" + p.folder
        let c = VisorConf()
        let sharing = p.running && model.tunnel?.target == p.url
        return HStack(spacing: 8) {
            Circle().fill(p.running ? Color.green : Color.secondary.opacity(0.4)).frame(width: 9, height: 9)
                .padding(.trailing, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.folder).font(.system(size: 13, weight: .medium))
                Text(text).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            // (los de siempre, solo con su icono: el proyecto en el editor, en su carpeta y lo que dice su servidor)
            if let code = vscodeURL() {
                iconButton(.image(NSWorkspace.shared.icon(forFile: code.path)), "Abrir en Visual Studio Code") { openInVSCode(path) }
            }
            iconButton(.symbol("folder", Color.primary), "Abrir su carpeta") { showFolder(path) }
            iconButton(.logo("log"), "Registro: lo último que ha dicho su servidor") {
                model.runTask("Registro de \(p.folder)", ["node-registro", p.folder])
            }
            .busyGuard(model.busy)
            if p.running {
                iconButton(.symbol("arrow.clockwise", Color.primary), p.mode == "compilado" ? "Volver a compilar y arrancar" : "Reiniciar su servidor") {
                    model.startNode(p, mode: p.mode)
                }
                .busyGuard(model.busy)
                VisorButton(conf: c, name: "Abrir web", icon: .symbol("globe", Color.blue), tip: "Abrir \(p.url)") { openURL(p.url) }
            } else {
                VisorButton(conf: c, name: "Arrancar", icon: .symbol("play.fill", Color.green), tip: "En desarrollo: los cambios se ven al momento") {
                    model.startNode(p, mode: "desarrollo")
                }
                .busyGuard(model.busy)
                VisorButton(conf: c, name: "Compilar", icon: .symbol("hammer.fill", Color.primary), tip: "Compilar y arrancar, como en producción") {
                    model.startNode(p, mode: "compilado")
                }
                .busyGuard(model.busy)
            }
            if sharing {
                VisorButton(conf: c, name: "Compartiendo", icon: .logo("cloudflare"), tip: "Ver dirección y contraseña del túnel", kind: "compartiendo") {
                    model.shareDialog()
                }
            } else {
                VisorButton(conf: c, name: "Túnel", icon: .logo("cloudflare"),
                            tip: p.running && p.mode == "compilado" ? "Compartir con un túnel de Cloudflare" : "Compilar, arrancar y compartir con un túnel de Cloudflare") {
                    model.shareNode(p)
                }
                .busyGuard(model.busy)
            }
            if p.running {
                VisorButton(conf: c, name: "Parar", icon: .symbol("stop.fill", Color.red), tip: "Parar su servidor (y su túnel, si se está compartiendo)") {
                    model.stopNode(p)
                }
                .busyGuard(model.busy)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    func iconButton(_ icon: VisorIcon, _ tip: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { VisorIconView(icon: icon, size: 16) }
            .buttonStyle(OutlineButton())
            .tip(tip)
    }
}

/// Nginx (gui-nginx): N|instalado|versión|la de este gestor|en marcha|http|https|PHP (ok, parado, sin-fpm),
/// P|carpeta|raíz|nombre|carpeta existe y C|carpeta (las de htdocs que aún no están)
struct NginxProject: Equatable, Identifiable {
    var id: String { folder }
    let folder, root, host: String
    let exists: Bool
}

struct NginxInfo: Equatable {
    var installed = false, running = false
    var version = "", latest = "", http = "8080", https = "8443", php = ""
    var projects: [NginxProject] = []
    var candidates: [String] = []
    func url(_ p: NginxProject) -> String { "https://\(p.host):\(https)/" }
}

func parseNginx(_ out: String) -> NginxInfo {
    var n = NginxInfo()
    for f in parseLines(out) {
        if f.first == "N", f.count >= 8 {
            n.installed = f[1] == "1"
            n.version = f[2]
            n.latest = f[3]
            n.running = f[4] == "1"
            n.http = f[5]
            n.https = f[6]
            n.php = f[7]
        } else if f.first == "P", f.count >= 5 {
            n.projects.append(NginxProject(folder: f[1], root: f[2], host: f[3], exists: f[4] == "1"))
        } else if f.first == "C", f.count >= 2 {
            n.candidates.append(f[1])
        }
    }
    return n
}

/// Pestaña Nginx: otro servidor web, aparte de Apache, para los proyectos que se le añaden. Solo en este Mac
/// y con tu usuario: cada uno por su nombre (<carpeta>.localhost), con el PHP de la versión activa
struct NginxView: View {
    @EnvironmentObject var model: AppModel
    @State private var pick = ""
    @State private var sub = ""

    var body: some View {
        WidePage {
            PageTitle(title: "Nginx",
                      sub: "Otro servidor web, aparte de Apache, para los proyectos de \(HTDOCS) que le añadas (Laravel, Symfony, PHP...). Solo en este Mac y con tu usuario: cada uno por su nombre, con el PHP de la versión activa y sus BBDD.",
                      logo: "nginx")
            if let n = model.nginx {
                Card { status(n) }
                if n.installed {
                    Text("Proyectos").font(.system(size: 13, weight: .semibold)).padding(.top, 8)
                    Card {
                        if n.projects.isEmpty {
                            Text("Ningún proyecto en Nginx: añade uno abajo. Se sirve en http://<carpeta>.localhost:\(n.http) y https://<carpeta>.localhost:\(n.https)")
                                .foregroundColor(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        LazyVStack(spacing: 0) {
                            ForEach(n.projects) { p in
                                row(p, n)
                                if p != n.projects.last { Divider().padding(.leading, 34) }
                            }
                        }
                    }
                    if !n.candidates.isEmpty { Card { addRow(n) } }
                }
            } else {
                Card { Text("Cargando…").foregroundColor(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
    }

    func status(_ n: NginxInfo) -> some View {
        var text: String
        if !n.installed {
            text = "Aún no está instalado: se compila de su código, con tu usuario, en ~/.nexum/nginx (menos de un minuto; con pcre2 y openssl@3 de Homebrew)"
        } else if n.running {
            text = "En marcha en este Mac: puertos \(n.http) (http) y \(n.https) (https)"
        } else {
            text = "Parado. Puertos \(n.http) (http) y \(n.https) (https), en Configuración, Nginx"
        }
        if n.installed && n.php == "parado" { text += ". El PHP de la versión activa no está en marcha: arráncala para que sirva PHP" }
        if n.installed && n.php == "sin-fpm" { text += ". La versión activa no tiene PHP-FPM (un XAMPP oficial): solo sirve ficheros" }
        let c = VisorConf()
        return HStack(spacing: 8) {
            Circle().fill(n.running ? Color.green : Color.secondary.opacity(0.4)).frame(width: 9, height: 9).padding(.trailing, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nginx \(n.installed ? n.version : n.latest)").font(.system(size: 13, weight: .medium))
                Text(text).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !n.installed {
                Button("Instalar") { model.nginxInstall() }
                    .buttonStyle(OutlineButton(kind: "primary"))
                    .busyGuard(model.busy)
            } else {
                if n.version != n.latest {
                    Button("Actualizar a la \(n.latest)") { model.nginxInstall() }.busyGuard(model.busy)
                }
                Button(action: { model.runTask("Registro de Nginx", ["nginx-registro"]) }) { VisorIconView(icon: .logo("log"), size: 16) }
                    .buttonStyle(OutlineButton()).tip("Registro: sus errores").busyGuard(model.busy)
                if n.running {
                    Button(action: { model.nginxDo("nginx-reiniciar", "Reiniciando Nginx", "Nginx en marcha") }) {
                        VisorIconView(icon: .symbol("arrow.clockwise", Color.primary), size: 16)
                    }
                    .buttonStyle(OutlineButton()).tip("Reiniciar Nginx").busyGuard(model.busy)
                    VisorButton(conf: c, name: "Parar", icon: .symbol("stop.fill", Color.red), tip: "Parar Nginx (Apache sigue igual)") {
                        model.nginxDo("nginx-parar", "Parando Nginx", "Nginx parado")
                    }
                    .busyGuard(model.busy)
                } else {
                    VisorButton(conf: c, name: "Arrancar", icon: .symbol("play.fill", Color.green), tip: "Arrancar Nginx en este Mac") {
                        model.nginxDo("nginx-arrancar", "Arrancando Nginx", "Nginx en marcha")
                    }
                    .busyGuard(model.busy)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    func row(_ p: NginxProject, _ n: NginxInfo) -> some View {
        let path = HTDOCS + "/" + p.folder
        let text = p.exists ? "\(n.url(p)) · sirve \(p.root.isEmpty ? "la carpeta entera" : p.root + "/")" : "Su carpeta ya no está en \(HTDOCS)"
        let c = VisorConf()
        return HStack(spacing: 8) {
            Circle().fill(n.running && p.exists ? Color.green : Color.secondary.opacity(0.4)).frame(width: 9, height: 9)
                .padding(.trailing, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.folder).font(.system(size: 13, weight: .medium))
                Text(text).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if p.exists {
                if let code = vscodeURL() {
                    Button(action: { openInVSCode(path) }) { VisorIconView(icon: .image(NSWorkspace.shared.icon(forFile: code.path)), size: 16) }
                        .buttonStyle(OutlineButton()).tip("Abrir en Visual Studio Code")
                }
                Button(action: { showFolder(path) }) { VisorIconView(icon: .symbol("folder", Color.primary), size: 16) }
                    .buttonStyle(OutlineButton()).tip("Abrir su carpeta")
                if n.running {
                    VisorButton(conf: c, name: "Abrir web", icon: .symbol("globe", Color.blue), tip: "Abrir \(n.url(p))") { openURL(n.url(p)) }
                }
            }
            VisorButton(conf: c, name: "Quitar", icon: .symbol("minus", Color.primary), tip: "Dejar de servirlo con Nginx (su carpeta no se toca)") {
                model.nginxRemove(p)
            }
            .busyGuard(model.busy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    /// Añadir: el proyecto (de los de htdocs que aún no están) y la subcarpeta que se sirve (vacía: public si
    /// la tiene, web o la carpeta entera)
    func addRow(_ n: NginxInfo) -> some View {
        HStack(spacing: 10) {
            Text("Añadir proyecto").font(.system(size: 13, weight: .medium))
            SearchPicker(selection: $pick, items: n.candidates.map { ($0, $0) }, width: 260)
            TextField("subcarpeta (vacía: la que parezca)", text: $sub)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(maxWidth: 220)
            Spacer(minLength: 8)
            Button("Añadir") {
                let folder = n.candidates.contains(pick) ? pick : (n.candidates.first ?? "")
                guard !folder.isEmpty else { return }
                model.nginxAdd(folder, sub.trimmingCharacters(in: CharacterSet(charactersIn: " /")))
                sub = ""
            }
            .buttonStyle(OutlineButton(kind: "primary"))
            .busyGuard(model.busy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear { if !n.candidates.contains(pick) { pick = n.candidates.first ?? "" } }
    }
}

/// Configuración, Nginx: sus puertos (8080 y 8443 de serie) y que el navegador acepte sus certificados
struct NginxCard: View {
    @EnvironmentObject var model: AppModel
    @State private var http = ""
    @State private var https = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TileCard("Nginx", "Otro servidor web, aparte de Apache: solo en este Mac y con tu usuario. Apagado de serie; encendido, sale su pestaña y desde ella se instala y se le añaden proyectos, en http://<carpeta>.localhost y https://<carpeta>.localhost con estos puertos.", wide: true, tiles: true) {
                Tile("Usar Nginx", model.nginxUsed ? "Encendido: su pestaña sale en el menú lateral" : "Apagado: su pestaña no sale. Apagarlo lo para, sin borrar sus proyectos ni sus ajustes") {
                    Toggle("", isOn: Binding(get: { model.nginxUsed }, set: { v in if v != model.nginxUsed { model.nginxUse(v) } }))
                        .toggleStyle(SwitchToggleStyle()).labelsHidden()
                        .busyGuard(model.busy)
                }
            }
            if model.nginxUsed {
            TileCard(tiles: true) {
                Tile("Puertos", "De 1024 en adelante (los de abajo son de root), distintos de los de Apache. Si está en marcha, los usa al momento.") {
                    VStack(alignment: .trailing, spacing: 10) {
                        HStack(spacing: 8) {
                            portField("HTTP", $http)
                            portField("HTTPS", $https)
                        }
                        Button("Guardar") { model.nginxPorts(http, https) }
                            .buttonStyle(OutlineButton(kind: "primary"))
                            .busyGuard(model.busy)
                    }
                }
            }
            TileCard(tiles: true) {
                Tile("Certificados", "Que el navegador acepte sin aviso el https de cada proyecto (se hace solo al añadirlo: esto, si lo has quitado)") {
                    Button("Confiar") { model.runTask("Certificados de Nginx", ["nginx-confiar"], doneText: "Certificados de Nginx", autoClose: true) }
                        .busyGuard(model.busy)
                }
            }
            }
        }
        .onAppear {
            if model.nginx == nil { model.reloadNginx() }
            fill()
        }
        .onChange(of: model.nginx) { _ in fill() }
    }

    func fill() {
        guard let n = model.nginx else { return }
        if http.isEmpty { http = n.http }
        if https.isEmpty { https = n.https }
    }

    func portField(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField("", text: text).textFieldStyle(PlainTextFieldStyle())
                .padding(.horizontal, 8)
                .frame(width: 60, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.2), lineWidth: 1))
        }
    }
}

struct ReposView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""

    var body: some View {
        WidePage {
            let r = model.repos
            let h = r?.head ?? []
            PageTitle(title: "Repositorios",
                      sub: h.count >= 6 ? "\(h[2]) en GitHub: \(h[5]) de \(h[4]) repositorios" + (model.reposAll ? "" : " (los de sus prefijos)")
                        : "Los repositorios de tu organización en GitHub, para clonarlos por SSH en \(HTDOCS)",
                      logo: "github")
            if let e = r?.error, h.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(e)
                    Button("Ir a Configuración") { model.openTools("github") }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            } else {
                HStack(spacing: 10) {
                    TextField("Buscar por nombre, descripción o web", text: $query)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 320)
                    Toggle("Mostrar todos", isOn: Binding(get: { model.reposAll }, set: {
                        model.reposAll = $0
                        model.reloadRepos(cache: true)
                        model.reloadRepos()
                    }))
                    .toggleStyle(SwitchToggleStyle())
                    .tip("Incluir los que no tienen prefijo")
                    Spacer()
                    if let e = r?.error { Text("⚠ " + e).font(.caption).foregroundColor(.secondary).lineLimit(2) }
                    if model.reposLoading || r == nil {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Button(action: { model.reloadRepos() }) { Image(systemName: "arrow.clockwise") }
                            .tip("Leer de nuevo la lista de GitHub")
                    }
                }
                let q = query.trimmingCharacters(in: .whitespaces).lowercased()
                let items = (r?.items ?? []).filter { q.isEmpty || ($0.full + " " + $0.desc + " " + $0.web).lowercased().contains(q) }
                Card {
                    if items.isEmpty {
                        Text(r == nil || model.reposLoading ? "Cargando la lista de GitHub…" : "Ningún repositorio")
                            .foregroundColor(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            row(item)
                            if item != items.last { Divider().padding(.leading, 46) }
                        }
                    }
                }
            }
        }
    }

    func row(_ item: RepoItem) -> some View {
        let kind = ["wordpress", "prestashop"].first { item.prefix.contains($0) || item.name.contains($0) }
        let bits = [item.state == "clonado" ? "clonado en \(item.folder)" : "", item.desc, item.web,
                    item.date.isEmpty ? "" : "actualizado el \(item.date)"].filter { !$0.isEmpty }
        return HStack(spacing: 12) {
            LogoShape(d: LOGO_PATHS[kind ?? "github"] ?? "")
                .fill(kind.map { brand($0) } ?? Color.primary)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.name).font(.system(size: 13, weight: .medium))
                    if item.isPrivate { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundColor(.secondary) }
                }
                Text(bits.joined(separator: " · ")).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if item.state == "clonado" {
                Button("Traer cambios") { model.fetchRepo(item) }
                    .buttonStyle(OutlineButton())
                    .busyGuard(model.busy)
                    .tip("Actualizar con git pull")
            } else if item.state == "ocupado" {
                Button("Clonar") {}
                    .buttonStyle(OutlineButton())
                    .disabled(true)
                    .tip("Ya hay una carpeta con ese nombre")
            } else {
                Button("Clonar") { model.fetchRepo(item) }
                    .buttonStyle(OutlineButton(kind: "primary"))
                    .busyGuard(model.busy)
                    .tip("Clonar por SSH en htdocs")
            }
            // (para pegarlo en Nuevo proyecto)
            Button(action: {
                copyText("git@github.com:\(item.full).git")
                model.toast("Repositorio copiado: \(item.name)")
            }) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(OutlineButton())
            .tip("Copiar repositorio")
            // (detrás, el repositorio en GitHub: sus cambios, ramas y pull requests; solo el logotipo)
            Button(action: { openURL("https://github.com/" + item.full) }) {
                LogoShape(d: LOGO_PATHS["github"] ?? "").fill(Color.primary).frame(width: 16, height: 16)
            }
            .buttonStyle(OutlineButton())
            .tip("Abrir en GitHub")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
