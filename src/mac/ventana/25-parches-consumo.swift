// MARK: parches nuevos de los componentes

/// Lo que dice componentes: lo que tiene un parche nuevo (para enseñarlo), lo que no se pone al día solo y
/// lo que no se ha podido consultar
/// (el mismo fichero que en Linux)
let IGNORED_UPDATES_FILE = LOG_DIR + "/parches-para-luego"

struct ComponentsState: Equatable {
    var items: [String] = []
    var notes: [String] = []
    var errors: [String] = []
}

func parseComponents(_ out: String) -> ComponentsState {
    var c = ComponentsState()
    for f in parseLines(out) {
        switch f.first ?? "" {
        case "L" where f.count >= 5: c.items.append("XAMPP-\(f[1]): \(f[2]) \(f[3]) → \(f[4])")
        case "K" where f.count >= 3: c.items.append("\(f[1]) (\(f[2])): versión nueva en Docker Hub")
        case "X" where f.count >= 4: c.items.append("\(f[1]): \(f[2]) → \(f[3])")
        case "F" where f.count >= 3 && f[2].contains("→"): c.notes.append("XAMPP-\(f[1]): \(f[2])")
        case "E" where f.count >= 2: c.errors.append(f[1])
        default: break
        }
    }
    return c
}

// MARK: consumo de Nexum y sus servicios

/// CPU (en % de un núcleo, como ps) y memoria residente de una parte
struct UsagePart: Equatable {
    var cpu = 0.0
    var mem: Int64 = 0
}

let USAGE_GROUPS: [(String, String)] = [("ventana", "Nexum Dev Stack (la ventana y sus tareas)"),
                                        ("xampp", "XAMPP-X (Apache, MariaDB y PHP)"),
                                        ("docker", "Docker Desktop (su máquina virtual con los contenedores)"),
                                        ("mailpit", "Mailpit (correo de pruebas)"),
                                        ("tunel", "Túnel de Cloudflare")]

/// A qué parte de Nexum es un proceso (nil: a ninguna). Sin los hijos: esos van con su padre
func usageGroup(_ pid: Int, _ cmd: String, _ own: Int) -> String? {
    if pid == own { return "ventana" }
    if cmd.contains("/xamppfiles/") { return "xampp" }
    if cmd.contains("/mailpit/mailpit") { return "mailpit" }
    if cmd.contains("nexum-tunel") || cmd.contains("/.nexum/tunel/cloudflared") || cmd.contains("/.lvm-instalador/tunel/cloudflared") { return "tunel" }
    if cmd.contains("/Applications/Docker.app/") || cmd.contains("com.apple.Virtualization.VirtualMachine") { return "docker" }
    return nil
}

/// Lo que gastan ahora Nexum y sus servicios (ps; tarda unos milisegundos: fuera de la interfaz)
func sampleUsage() -> [String: UsagePart] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-axww", "-o", "pid=,ppid=,pcpu=,rss=,command="]
    p.environment = ["LC_ALL": "C"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return [:] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let own = Int(ProcessInfo.processInfo.processIdentifier)
    var ppid: [Int: Int] = [:], group: [Int: String] = [:], cmds: [Int: String] = [:]
    var cpu: [Int: Double] = [:], rss: [Int: Int64] = [:]
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        let f = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
        guard f.count == 5, let pid = Int(f[0]), let pp = Int(f[1]) else { continue }
        ppid[pid] = pp
        cpu[pid] = Double(f[2]) ?? 0
        rss[pid] = (Int64(f[3]) ?? 0) * 1024
        cmds[pid] = String(f[4])
        if let g = usageGroup(pid, String(f[4]), own) { group[pid] = g }
    }
    // Los hijos van con su padre (los PHP-FPM y los hijos de Apache; de la ventana, solo sus tareas)
    for pid in ppid.keys where group[pid] == nil {
        var q = ppid[pid] ?? 0
        var depth = 0
        while q > 1 && depth < 6 {
            if let g = group[q] {
                if g != "ventana" || (cmds[pid] ?? "").contains("lvm-instalador") { group[pid] = g }
                break
            }
            q = ppid[q] ?? 0
            depth += 1
        }
    }
    var out: [String: UsagePart] = [:]
    for (k, _) in USAGE_GROUPS { out[k] = UsagePart() }
    for (pid, g) in group {
        out[g]?.cpu += cpu[pid] ?? 0
        out[g]?.mem += rss[pid] ?? 0
    }
    return out
}

// MARK: actualizaciones al abrir

/// Al abrir la ventana se busca una versión nueva el primer arranque de cada día y, después, cada tantos
let UPDATE_EVERY = 4

/// ¿Toca buscar una versión nueva al abrir? Se lleva en ~/.nexum/actualizaciones-arranques:
/// la fecha y los arranques desde la última vez que se buscó (el mismo fichero que en Linux)
func updateCheckDue() -> Bool {
    if SIMULATE { return true }
    let path = LOG_DIR + "/actualizaciones-arranques"
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    let today = f.string(from: Date())
    let parts = ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map(String.init)
    let day = parts.first ?? ""
    let n = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
    let due = day != today || n + 1 >= UPDATE_EVERY
    try? FileManager.default.createDirectory(atPath: LOG_DIR, withIntermediateDirectories: true,
                                             attributes: [.posixPermissions: 0o700])
    try? "\(today) \(due ? 0 : n + 1)\n".write(toFile: path, atomically: true, encoding: .utf8)
    return due
}
