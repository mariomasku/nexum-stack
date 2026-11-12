// MARK: - Progreso (mismo calculo que progress_screen del script)

struct InstallProgress {
    var k = 1, n = 1, started = 0, cur = 0, pct = 0
    var name = "", what = "", mode = ""
    var parts: [String] = []
    var done: Int64 = 0, total: Int64 = 0
    var results: [(String, String)] = []
}

/// Explicación del aviso de certificados (lo que tienen mal y qué hace Arreglarlos)
func certsText(_ d: AppData) -> String {
    var why: [String] = []
    if d.certs.contains(where: { $0.why == "falta" }) {
        why.append("no tienen el certificado (Apache no arrancaría)")
    }
    if d.certs.contains(where: { $0.why == "ca" }) {
        why.append("son de CA (con su clave se puede firmar cualquier web)")
    }
    if !d.cas.isEmpty {
        why.append("los firma una CA de confianza sin límite de dominios (\(d.cas.joined(separator: ", "))) cuya clave puede leer cualquier programa tuyo, como el PHP de una web")
    }
    return "Los certificados https de estos proyectos " + why.joined(separator: "; ")
        + ". Arreglarlos les pone uno propio, que solo vale para su dominio, y quita esa confianza. Después el navegador avisará una vez en cada proyecto: acepta el aviso. Pide la contraseña de administrador."
}

/// Dominios del aviso de certificados (los seis primeros)
func certsNames(_ d: AppData) -> String {
    let names = d.certs.map { $0.domain }
    if names.isEmpty { return "Ninguno: solo la CA" }
    return names.prefix(6).joined(separator: ", ") + (names.count > 6 ? " y \(names.count - 6) más" : "")
}

/// Cierra la aplicación y la vuelve a abrir con el script nuevo («nexum ventana» la rehace
/// y la abre cuando esta ya se ha cerrado)
func relaunchApp() {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = ["-c", "sleep 2; exec /bin/bash \"$0\" ventana", SCRIPT]
    p.environment = scriptEnv()
    p.standardInput = FileHandle.nullDevice
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { message("Vuelve a abrir Nexum Dev Stack", "La versión nueva está instalada."); return }
    NSApp.terminate(nil)
}

/// Muestra una carpeta en el Finder (NSWorkspace.open ejecutaría una carpeta que se llame .app)
func showFolder(_ path: String) {
    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
}

/// El zip más reciente de Exportar proyecto en su carpeta (<carpeta>_php…_nexum.zip), señalado en el Finder; si
/// no está, la carpeta
func revealExport(_ dir: String, _ name: String) {
    let fm = FileManager.default
    var best: (path: String, when: Date)? = nil
    for f in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where f.hasPrefix(name + "_php") && f.hasSuffix("_nexum.zip") {
        let path = dir + "/" + f
        let when: Date = ((try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date) ?? .distantPast
        if best == nil || when > best!.when { best = (path: path, when: when) }
    }
    if let b = best {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: b.path)])
    } else {
        showFolder(dir)
    }
}

/// Salida de un programa (vacía si falla o no termina bien)
func captureOutput(_ path: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : ""
}

/// Posicion de lectura de un descriptor ("pid:fd") con lsof: 0t<decimal> o 0x<hexadecimal>
func fdOffset(_ spec: String) -> Int64 {
    let parts = spec.components(separatedBy: ":")
    if parts.count != 2 { return 0 }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    p.arguments = ["-a", "-p", parts[0], "-d", parts[1], "-o", "-Fo"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return 0 }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    for line in String(decoding: data, as: UTF8.self).components(separatedBy: "\n") where line.hasPrefix("o") {
        let v = String(line.dropFirst())
        if v.hasPrefix("0t") { return Int64(v.dropFirst(2)) ?? 0 }
        if v.hasPrefix("0x") { return Int64(v.dropFirst(2), radix: 16) ?? 0 }
    }
    return 0
}

func readProgress(_ path: String) -> InstallProgress? {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    let lines = text.components(separatedBy: "\n")
    guard let start = lines.lastIndex(where: { $0.hasPrefix("I|") }) else { return nil }
    var p = InstallProgress()
    let f = lines[start].components(separatedBy: "|")
    p.k = Int(field(f, 1)) ?? 1
    p.n = Int(field(f, 2)) ?? 1
    p.name = field(f, 3)
    p.started = Int(field(f, 4)) ?? 0
    let section = Array(lines[start...])
    if let c = section.last(where: { $0.hasPrefix("C|") }) {
        p.parts = String(c.dropFirst(2)).components(separatedBy: ";")
    }
    if let s = section.last(where: { $0.hasPrefix("S|") }) {
        let g = s.components(separatedBy: "|")
        p.cur = Int(field(g, 1)) ?? 0
        let from = Int(field(g, 2)) ?? 0, to = Int(field(g, 3)) ?? 0
        p.what = field(g, 4)
        p.mode = field(g, 5)
        let file = field(g, 6)
        p.total = Int64(field(g, 7)) ?? 0
        let t0 = Int(field(g, 8)) ?? 0
        var done: Int64 = 0
        switch p.mode {
        case "lines":
            if let d = FileManager.default.contents(atPath: file) {
                done = Int64(d.reduce(0) { $1 == 10 ? $0 + 1 : $0 })
            }
        case "bytes":
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file),
               let size = attrs[.size] as? NSNumber {
                done = size.int64Value
            }
        case "time":
            done = Int64(Int(Date().timeIntervalSince1970) - t0)
        case "percent":
            if let h = FileHandle(forReadingAtPath: file) {
                let end = h.seekToEndOfFile()
                h.seek(toFileOffset: end > 8000 ? end - 8000 : 0)
                let tail = String(decoding: h.readDataToEndOfFile(), as: UTF8.self).components(separatedBy: "\n")
                h.closeFile()
                for t in tail.suffix(40) {
                    if let m = PERCENT.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                       let r = Range(m.range(at: 1), in: t) {
                        done = Int64(t[r]) ?? done
                    }
                }
            }
        case "lsof":
            done = fdOffset(file)
        default:
            break
        }
        p.done = done
        var frac: Int64 = 0
        if !p.mode.isEmpty && p.total > 0 { frac = min(done * 1000 / p.total, 990) }
        p.pct = from + (to - from) * Int(frac) / 1000
    }
    p.results = lines.filter { $0.hasPrefix("R|") }
        .map { $0.components(separatedBy: "|") }
        .filter { $0.count > 2 }
        .map { ($0[1], $0[2]) }
    if section.contains(where: { $0.hasPrefix("R|") }) {
        p.pct = 100
        p.cur = 999
    }
    return p
}

/// Carpeta (XAMPP-<version>) de un elemento del plan, como en install_stack: php:8.4.26 -> 8.4.26 (desde
/// la 1.38, cada versión en su carpeta con la versión entera; también un parche concreto, php:8.3.10, y
/// parchear:7.4.33); rehacer:8.4.26 -> 8.4 (rehace una XAMPP-X.Y de antes de la 1.38, la de su rama)
func itemFolder(_ item: String) -> String {
    let name = item.components(separatedBy: ":").last ?? item
    if !item.hasPrefix("rehacer:") { return name }
    var parts = name.components(separatedBy: ".")
    if parts.count > 2 { parts.removeLast() }
    return parts.joined(separator: ".")
}
