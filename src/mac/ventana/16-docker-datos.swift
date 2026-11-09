// MARK: - Docker (datos de gui-docker)

struct DockerProject: Equatable, Identifiable {
    let slug, folder, php, maria, domain, state, db, pma, web: String
    /// De antes de la 1.39.2: su PHP-FPM sigue abierto en 127.0.0.1 (docker-migrar lo cambia)
    var old = false
    /// Del Apache de Docker (1.40): su tipo (wp, ps u otro) y sus versiones de PHP (php: la elegida)
    var isWeb = false
    var kind = ""
    var versions: [String] = []
    /// La versión XAMPP-X cuya BBDD usa en vivo (vacío: su copia en la MariaDB común)
    var lampp = ""
    var id: String { return slug }
}

struct DockerContainer: Equatable, Identifiable {
    let name, image, state, status, ports, project: String
    /// ID corto (12 cifras hexadecimales; vacío con el gui-docker de antes de la 1.39.4)
    var cid = ""
    var id: String { return name }
}

struct DockerImage: Equatable {
    /// Imagen (repositorio), etiqueta («<none>» si no tiene) e ID corto (vacío con el gui-docker de
    /// antes, que la daba como imagen:etiqueta)
    let repo, tag, cid, size, created: String
    /// imagen:etiqueta
    var name: String { return repo + ":" + tag }
    var tagged: Bool { return tag != "<none>" && !tag.isEmpty }
}

struct DockerVolume: Equatable {
    let name, driver: String
}

struct DockerData: Equatable {
    /// docker instalado, Docker Desktop responde, su versión, la versión XAMPP-X activa en marcha y si
    /// está la aplicación Docker Desktop
    var installed = false, ready = false, xampp = false, app = false
    var version = ""
    var php: [String] = [], maria: [String] = []
    var projects: [DockerProject] = []
    var containers: [DockerContainer] = []
    var images: [DockerImage] = []
    var volumes: [DockerVolume] = []
    /// El Apache de Docker (desde la 1.40)
    var web: DockerWeb? = nil
}

/// Uso de CPU (%) y memoria (bytes) de cada contenedor en marcha, con los núcleos y la memoria de la
/// máquina virtual de Docker Desktop
struct DockerStats: Equatable {
    var cores = 1
    var total: Int64 = 0
    var cpu: [String: Double] = [:]
    var mem: [String: Double] = [:]
}

/// Formulario «Proyecto en Docker»: source es «versión|BBDD» de la que se copia ("" = vacía); live: en un
/// WordPress, esa BBDD de XAMPP-X en vivo en vez de copiarla
struct DockerForm: Equatable {
    var folder = "", php = "", maria = "", source = "", domain = ""
    var domainSet = false
    var live = true
}

/// Nombre corto de un proyecto en Docker (como docker_slug del script)
func dockerSlug(_ folder: String) -> String {
    let s = folder.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    let cut = String(s.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return cut.isEmpty ? "proyecto" : cut
}

/// Unidades de tiempo de Docker en español (2 minutes → 2 min)
func dockerUnits(_ s: String) -> String {
    var t = s
    let reps: [(String, String)] = [
        ("(\\d+) seconds?", "$1 s"), ("Less than a second", "1 s"), ("(\\d+) minutes?", "$1 min"),
        ("About a minute", "1 min"), ("About an hour", "1 h"), ("(\\d+) hours?", "$1 h"),
        ("(\\d+) days?", "$1 días"), ("(\\d+) weeks?", "$1 semanas"), ("(\\d+) months?", "$1 meses"),
        ("(\\d+) years?", "$1 años"), ("\\s*\\((healthy|unhealthy|health: starting)\\)", ""),
    ]
    for (rx, rep) in reps { t = t.replacingOccurrences(of: rx, with: rep, options: .regularExpression) }
    return t
}

/// Estado de un contenedor en español: «Up 2 minutes» → «en marcha · 2 min»
func dockerStatusText(_ status: String) -> String {
    let t = dockerUnits(status)
    if t.hasPrefix("Up ") { return "en marcha · " + t.dropFirst(3) }
    let ns = t as NSString
    if let m = (try? NSRegularExpression(pattern: "^Exited \\((\\d+)\\) (.+) ago$"))?
        .firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) {
        let code = ns.substring(with: m.range(at: 1))
        return "parado hace " + ns.substring(with: m.range(at: 2)) + (code == "0" ? "" : " (error \(code))")
    }
    switch t.split(separator: " ").first.map(String.init) ?? "" {
    case "Created": return "creado"
    case "Restarting": return "reiniciándose"
    case "Paused": return "en pausa"
    default: return t
    }
}

/// ¿Es uno de los contenedores del gestor? (los únicos con acciones: los de los proyectos, de antes y
/// del Apache de Docker, las MariaDB comunes, el Apache de Docker y su phpMyAdmin)
func ownContainer(_ name: String) -> Bool {
    return name.range(of: "^nexum-[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?-((php|db|pma)-[0-9]{1,3}|php[0-9]{2})$",
                      options: .regularExpression) != nil
        || name.range(of: "^nexum-(web|pma|mariadb-[0-9]{1,2}-[0-9]{1,2}|lampp-bd-[0-9]{1,2}-[0-9]{1,2}(-[0-9]{1,3})?)$",
                      options: .regularExpression) != nil
}
