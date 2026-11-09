// Ventana nativa de Nexum Dev Stack para macOS (SwiftUI, macOS 12 o posterior).
// La escribe y la compila "lvm-instalador" dentro de la aplicacion de ~/Applications. No repite la
// logica del instalador: lo ejecuta con los comandos gui-* (datos) y con los de siempre (use,
// instalar, actualizar, desinstalar, importar-bd...). Las acciones van dentro de una pseudoterminal
// (/usr/bin/script) para que sudo funcione igual que en Terminal; la contraseña se pide en una
// ventana y se escribe en esa terminal.
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

// MARK: - Constantes y utilidades

// El gestor, siempre el de root (1.39.3): la aplicacion es de tu usuario, y la ruta de su Info.plist
// la podria cambiar cualquier programa tuyo para que la contraseña fuera a otro script
let TRUSTED_SCRIPT = "/Library/Nexum/gestor/lvm-instalador.sh"
let SCRIPT: String = TRUSTED_SCRIPT
let SIMULATE = ProcessInfo.processInfo.environment["LVM_SIMULAR"] == "1"
// Marcas de la pseudoterminal (contraseña de sudo y fin de la tarea): distintas en cada ejecución,
// para que un volcado o un fichero de un proyecto que salga en el registro no pueda imitarlas
let RUN_TOKEN = UUID().uuidString.replacingOccurrences(of: "-", with: "")
let SUDO_MARK = "@@LVM-SUDO-\(RUN_TOKEN)@@"
let LOG_DIR = NSHomeDirectory() + "/.lvm-instalador"
/// Apartados de la ventana que se han plegado (uno por línea): siguen plegados al volver a abrirla
let FOLDED_FILE = LOG_DIR + "/ventana-plegados"
let GREEN = Color(red: 0x45 / 255.0, green: 0xA5 / 255.0, blue: 0x7C / 255.0)
let BLUE = Color(red: 0x35 / 255.0, green: 0x84 / 255.0, blue: 0xE4 / 255.0)
let RED = Color(red: 0.88, green: 0.11, blue: 0.14)
let ANSI = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[A-Za-z]|\u{1B}[78()][0-9A-Za-z]?")
// La marca de fin lleva otro codigo al azar (no el de la contraseña)
let FIN_TOKEN = UUID().uuidString.replacingOccurrences(of: "-", with: "")
let FIN = try! NSRegularExpression(pattern: "@@LVM-FIN-\(FIN_TOKEN) ([0-9]+)@@\\n?")
let REPORT = try! NSRegularExpression(pattern: "^Informe del error: (.+?)\\s*$", options: .anchorsMatchLines)
let PERCENT = try! NSRegularExpression(pattern: "^\\[ *([0-9]+)%\\]")
/// Un porcentaje en la salida de una tarea sin progreso propio (12 %, 45.3%): el de una descarga
let SEEN_PCT = try! NSRegularExpression(pattern: "(?<![\\d.,])(\\d{1,3})(?:[.,]\\d+)?\\s?%")
/// Colores del registro de las tareas (como una terminal)
let CONSOLE_BG = Color(red: 0x1D / 255.0, green: 0x22 / 255.0, blue: 0x28 / 255.0)
let CONSOLE_TEXT = Color(red: 0xD7 / 255.0, green: 0xDE / 255.0, blue: 0xE6 / 255.0)
let DB_NAME = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]{1,64}$")
let SYSTEM_DBS: Set<String> = ["information_schema", "mysql", "performance_schema", "phpmyadmin", "sys", "test"]

func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
    return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
}

func validDbName(_ s: String) -> Bool { return matches(DB_NAME, s) }

func scriptEnv(_ extra: [String: String] = [:]) -> [String: String] {
    // Solo estas variables de la sesion: el resto podria cambiar lo que hace bash (funciones
    // exportadas BASH_FUNC_*, SHELLOPTS con PS4, BASH_ENV), cargar librerias (DYLD_*) o cambiar lo que
    // toca el gestor con sudo (las LVM_* de prueba)
    // (SSH_AUTH_SOCK: para clonar por SSH con tu clave en Montar nuevo proyecto)
    let keep: Set<String> = ["HOME", "USER", "LOGNAME", "LANG", "TMPDIR", "SHELL", "LVM_PRUEBA", "SSH_AUTH_SOCK",
                             "PHP_TIMEZONE", "__CF_USER_TEXT_ENCODING", "http_proxy", "https_proxy",
                             "no_proxy", "all_proxy", "HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "ALL_PROXY"]
    let all = ProcessInfo.processInfo.environment
    // (en las pruebas, con LVM_PRUEBA, tambien las LVM_* que cambian las carpetas)
    let test = !(all["LVM_PRUEBA"] ?? "").isEmpty
    var env: [String: String] = [:]
    for (k, v) in all where keep.contains(k) || k.hasPrefix("LC_")
        || (test && k.hasPrefix("LVM_") && k != "LVM_SIMULAR") {
        env[k] = v
    }
    // Abierta desde Finder, la aplicacion no tiene el PATH de la terminal. Primero los programas del
    // sistema: los de Homebrew son de tu usuario (el script los añade despues para compilar)
    env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin"
    env["LVM_UI"] = "text"
    env["LVM_SIN_PREGUNTAS"] = "1"
    env["SUDO_PROMPT"] = SUDO_MARK
    env["TERM"] = "dumb"
    env.removeValue(forKey: "LVM_SIMULAR")
    for (k, v) in extra { env[k] = v }
    return env
}

func scriptArgs(_ args: [String]) -> [String] {
    return [SCRIPT] + (SIMULATE ? ["--simular"] : []) + args
}

/// Comando sin sudo ni preguntas, en segundo plano. done(codigo, salida) en el hilo principal.
func runQuick(_ args: [String], env: [String: String] = [:], input: String? = nil,
              _ done: @escaping (Int32, String) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = scriptArgs(args)
        p.environment = scriptEnv(env)
        p.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        // (lo de input, por la entrada: un token en la línea de órdenes se vería con ps)
        let inPipe = input == nil ? nil : Pipe()
        p.standardInput = inPipe ?? FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            DispatchQueue.main.async { done(1, "ERROR|\(error.localizedDescription)") }
            return
        }
        if let w = inPipe, let text = input {
            w.fileHandleForWriting.write(text.data(using: .utf8) ?? Data())
            try? w.fileHandleForWriting.close()
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(decoding: data, as: UTF8.self)
        DispatchQueue.main.async { done(p.terminationStatus, out) }
    }
}

func parseLines(_ out: String) -> [[String]] {
    return out.components(separatedBy: "\n").filter { $0.contains("|") }.map { $0.components(separatedBy: "|") }
}

func field(_ f: [String], _ i: Int) -> String { return i < f.count ? f[i] : "" }

/// Lo que queda libre y el total del disco donde está la ruta (lo libre como lo cuenta el Finder,
/// con lo que macOS puede liberar)
func diskSpace(_ path: String) -> (free: Int64, total: Int64)? {
    guard let v = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                                          .volumeTotalCapacityKey]),
          let free = v.volumeAvailableCapacityForImportantUsage, let total = v.volumeTotalCapacity, total > 0 else { return nil }
    return (free, Int64(total))
}

func fmtSize(_ n: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var v = Double(n)
    var i = 0
    while v >= 1024 && i < units.count - 1 {
        v /= 1024
        i += 1
    }
    if i == 0 { return "\(n) B" }
    return String(format: "%.1f ", v).replacingOccurrences(of: ".", with: ",") + units[i]
}

/// Número con dos cifras (los minutos y segundos de un reloj)
func twoDigits(_ n: Int) -> String { return n < 10 ? "0\(n)" : "\(n)" }

/// Tiempo transcurrido como un reloj: 0:42, 3:05, 1:02:10
func fmtClock(_ secs: Int) -> String {
    let s = max(0, secs)
    return s >= 3600 ? "\(s / 3600):\(twoDigits(s / 60 % 60)):\(twoDigits(s % 60))" : "\(s / 60):\(twoDigits(s % 60))"
}

/// Lo que queda, al ritmo de hasta ahora (done % en elapsed segundos; quedan left %)
func timeLeft(_ elapsed: Double, _ done: Int, _ left: Int) -> String {
    if done < 3 || elapsed < 3 { return "calculando lo que queda…" }
    let secs = Int(elapsed * Double(left) / Double(done))
    if secs < 60 { return "quedan unos \(max(5, (secs + 4) / 5 * 5)) s" }
    if secs < 90 { return "queda 1 min" }
    if secs < 3600 { return "quedan unos \((secs + 30) / 60) min" }
    return "quedan unas \(secs / 3600) h \(twoDigits(secs / 60 % 60)) min"
}

/// El registro de una tarea como lo pinta una terminal (como en Linux): \r vuelve al principio de
/// la línea (las barras de las descargas se quedan en una línea que avanza), ESC[nA sube n líneas,
/// ESC[nB las baja, ESC[nG va a la columna n y ESC[K / ESC[1K / ESC[2K borran (docker pull), y las
/// líneas seguidas que solo cambian en sus números y llevan un % se quedan en una sola, que va
/// subiendo. Solo las últimas líneas se pueden reescribir: las de antes pasan al texto fijo
final class Console {
    static let LIVE = 80
    static let TOKEN = try! NSRegularExpression(
        pattern: "\\x1B\\[([0-9;?]*)([A-Za-z])|\\x1B[78()][0-9A-Za-z]?|\\r\\n|\\r|\\n|\\x08")
    static let NUMBER = try! NSRegularExpression(pattern: "\\d+(?:[.,]\\d+)?")
    /// Lo que ya no se puede reescribir (el principio del registro)
    private var fixed = ""
    private var lines: [[Character]] = [[]]
    private var row = 0
    private var col = 0
    /// Una secuencia de escape cortada al final de lo leído: se termina con lo siguiente
    private var cut = ""

    /// Todo el registro, como se ve
    var text: String { return fixed + lines.map { String($0) }.joined(separator: "\n") }

    func write(_ input: String) {
        var chunk = cut + input
        cut = ""
        if let r = chunk.range(of: "\\x1B(\\[[0-9;?]*)?$", options: .regularExpression) {
            cut = String(chunk[r])
            chunk = String(chunk[..<r.lowerBound])
        }
        let ns = chunk as NSString
        var pos = 0
        for m in Console.TOKEN.matches(in: chunk, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > pos {
                put(ns.substring(with: NSRange(location: pos, length: m.range.location - pos)))
            }
            pos = m.range.location + m.range.length
            let tok = ns.substring(with: m.range)
            if tok == "\n" || tok == "\r\n" {
                newline()
            } else if tok == "\r" {
                col = 0
            } else if tok == "\u{08}" {
                col = max(0, col - 1)
            } else if m.range(at: 2).location != NSNotFound {
                let arg = ns.substring(with: m.range(at: 1))
                let n = Int(arg) ?? 1
                switch ns.substring(with: m.range(at: 2)) {
                case "A":
                    row = max(0, row - n)
                case "B":
                    row = min(lines.count - 1, row + n)
                case "G":
                    col = max(0, n - 1)
                case "K":
                    let line = lines[row]
                    if arg == "2" {
                        lines[row] = []
                    } else if arg == "1" {
                        lines[row] = Array(repeating: Character(" "), count: min(col, line.count)) + Array(line.dropFirst(col))
                    } else {
                        lines[row] = Array(line.prefix(col))
                    }
                default:
                    break
                }
            }
        }
        if pos < ns.length { put(ns.substring(from: pos)) }
        freeze()
    }

    private func put(_ s: String) {
        let chars = Array(s)
        var line = lines[row]
        if line.count < col { line += Array(repeating: Character(" "), count: col - line.count) }
        line.replaceSubrange(col..<min(line.count, col + chars.count), with: chars)
        lines[row] = line
        col += chars.count
    }

    private func newline() {
        // Un contador (12 %, 13 %, …) en líneas seguidas: se queda la última
        if row > 0 && lines[row].contains(Character("%")) && shape(lines[row]) == shape(lines[row - 1]) {
            lines.remove(at: row - 1)
            row -= 1
        }
        row += 1
        col = 0
        if row == lines.count { lines.append([]) }
    }

    /// La línea con sus números cambiados por # (para ver si solo cambian en ellos)
    private func shape(_ line: [Character]) -> String {
        let s = String(line).trimmingCharacters(in: .whitespaces)
        return Console.NUMBER.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length),
                                                       withTemplate: "#")
    }

    /// Las líneas de antes de las últimas LIVE pasan al texto fijo (y la ventana solo guarda el final)
    private func freeze() {
        var frozen: [String] = []
        while row > Console.LIVE {
            frozen.append(String(lines.removeFirst()))
            row -= 1
        }
        if !frozen.isEmpty { fixed += frozen.joined(separator: "\n") + "\n" }
        if fixed.utf8.count > 200_000 { fixed = String(fixed.suffix(150_000)) }
    }
}

// 2026-12-31 -> diciembre de 2026
// 2026-10-21 -> 21 de octubre de 2026
func fmtDay(_ date: String) -> String {
    let months = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
                  "septiembre", "octubre", "noviembre", "diciembre"]
    let p = date.components(separatedBy: "-")
    guard p.count >= 3, let m = Int(p[1]), m >= 1, m <= 12, let d = Int(p[2]) else { return date }
    return "\(d) de \(months[m - 1]) de \(p[0])"
}

func fmtMonth(_ date: String) -> String {
    let months = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
                  "septiembre", "octubre", "noviembre", "diciembre"]
    let p = date.components(separatedBy: "-")
    guard p.count >= 2, let m = Int(p[1]), m >= 1, m <= 12 else { return date }
    return "\(months[m - 1]) de \(p[0])"
}

func plural(_ n: Int, _ one: String, _ many: String) -> String {
    return "\(n) \(n == 1 ? one : many)"
}

func openURL(_ s: String) {
    if let url = URL(string: s) { NSWorkspace.shared.open(url) }
}

/// Panel de administración del proyecto cargado (tipo "wp" o "ps", carpeta del panel). Antes deja
/// al día su administrador de pruebas (usuario-pruebas) y abre una página con el usuario y la
/// contraseña ya escritos: basta con pulsar Entrar. Si no se puede, el panel como siempre.
func openProjectAdmin(kind: String, admin: String, link: String, db: String, folder: String?) {
    let name = folder.map { ($0 as NSString).lastPathComponent } ?? ""
    openAdminLogin(kind: kind, admin: admin, site: "http://\(link)", name: name,
                   command: db.isEmpty ? nil : ["usuario-pruebas", db, name])
}

/// Panel (wp-admin o el de la tienda) de la web site (http://web.local, https://x.docker.local) con el
/// administrador de pruebas: command lo deja al día (usuario-pruebas o docker-usuario-pruebas, que dicen
/// A|tipo|usuario|contraseña) y se abre una página con el usuario y la contraseña ya escritos. Sin
/// command, o si no sale, el panel como siempre
func openAdminLogin(kind: String, admin: String, site: String, name: String, command: [String]?) {
    let base = "\(site)/\(admin)/"
    guard let cmd = command, !SIMULATE else { openURL(base); return }
    runQuick(cmd) { rc, out in
        let mine = out.components(separatedBy: "\n").filter { $0.hasPrefix("A|\(kind)|") }
            .map { $0.components(separatedBy: "|") }
        guard rc == 0, let f = mine.first, f.count >= 4 else { openURL(base); return }
        let page: String
        if kind == "wp" {
            page = loginPage(title: "Panel de WordPress", project: name, action: "\(site)/wp-login.php",
                             fields: [("log", f[2], "Usuario o correo"), ("pwd", f[3], "Contraseña"),
                                      ("rememberme", "forever", nil), ("redirect_to", base, nil)], panel: base)
        } else {
            page = loginPage(title: "Back office de PrestaShop", project: name,
                             action: base + "index.php?controller=AdminLogin",
                             fields: [("email", f[2], "Correo"), ("passwd", f[3], "Contraseña"),
                                      ("stay_logged_in", "1", nil), ("submitLogin", "1", nil),
                                      ("redirect", "AdminDashboard", nil)], panel: base)
        }
        // En la carpeta temporal de tu usuario (solo tuya), con un nombre al azar
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lvm-acceso-\(UUID().uuidString).html")
        do {
            try page.write(to: file, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(file)
            // (se borra al rato: el navegador ya la ha leído)
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { try? FileManager.default.removeItem(at: file) }
        } catch {
            openURL(base)
        }
    }
}

func htmlEscape(_ s: String) -> String {
    return s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

/// Página de acceso al panel de un proyecto con el administrador de pruebas ya escrito: un
/// formulario que va a la pantalla de acceso del proyecto; solo hay que pulsar Entrar.
func loginPage(title: String, project: String, action: String, fields: [(String, String, String?)], panel: String) -> String {
    let e = htmlEscape
    var rows = "", hidden = ""
    for (name, value, text) in fields {
        if let text = text {
            let type = (name == "pwd" || name == "passwd") ? "password" : "text"
            rows += "<label>\(e(text))<input type=\"\(type)\" name=\"\(e(name))\" value=\"\(e(value))\" autocomplete=\"off\"></label>"
        } else {
            hidden += "<input type=\"hidden\" name=\"\(e(name))\" value=\"\(e(value))\">"
        }
    }
    let style = """
    :root { color-scheme: light dark; --bg: #f4f4f6; --card: #fff; --line: #d8d8dc; --muted: #6b6b72; --accent: #2a7ae2; }
    @media (prefers-color-scheme: dark) { :root { --bg: #1e1e20; --card: #2a2a2d; --line: #444; --muted: #a0a0a6; } }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: var(--bg);
           font: 15px/1.45 -apple-system, system-ui, sans-serif; }
    form { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 28px 32px;
           width: min(380px, calc(100vw - 32px)); box-sizing: border-box; }
    h1 { font-size: 19px; margin: 0 0 4px; } p { margin: 0 0 18px; color: var(--muted); font-size: 13px; }
    label { display: block; font-size: 13px; color: var(--muted); margin-bottom: 14px; }
    input[type=text], input[type=password] { display: block; width: 100%; box-sizing: border-box; margin-top: 4px;
           padding: 8px 10px; font: inherit; border: 1px solid var(--line); border-radius: 8px; background: transparent; }
    button { width: 100%; margin-top: 6px; padding: 10px; font: inherit; font-weight: 600; color: #fff;
             background: var(--accent); border: 0; border-radius: 8px; cursor: pointer; }
    small { display: block; margin-top: 14px; color: var(--muted); font-size: 12px; }
    """
    let shownProject = e(project.isEmpty ? "proyecto" : project)
    return [
        "<!doctype html><html lang=\"es\"><head><meta charset=\"utf-8\"><meta name=\"referrer\" content=\"no-referrer\">",
        "<title>\(e(title)) · \(shownProject)</title><style>\(style)</style></head><body>",
        "<form method=\"post\" action=\"\(e(action))\"><h1>\(e(title))</h1>",
        "<p>\(shownProject) · administrador de pruebas de este Mac</p>",
        rows + hidden + "<button type=\"submit\" autofocus>Entrar</button>",
        "<small>Si no entra, el panel normal está en <a href=\"\(e(panel))\">\(e(panel))</a>.</small>",
        "</form></body></html>"
    ].joined()
}

/// Visual Studio Code, si está instalado (para abrir con él y para su icono)
func vscodeURL() -> URL? {
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode")
}

/// Carpeta del proyecto cargado (a la que apunta el enlace del vhost), solo si es una carpeta de htdocs
func loadedProjectFolder(_ current: String) -> String? {
    guard !current.isEmpty else { return nil }
    let path = current.hasPrefix("/") ? current : HTDOCS + "/" + current
    let real = (path as NSString).resolvingSymlinksInPath
    var isDir: ObjCBool = false
    guard (real as NSString).deletingLastPathComponent == (HTDOCS as NSString).resolvingSymlinksInPath,
          FileManager.default.fileExists(atPath: real, isDirectory: &isDir), isDir.boolValue else { return nil }
    return real
}

/// Nombre propuesto para la copia de una BBDD en otra versión: sin el sufijo de versión que traiga
/// y con el de la de destino (wp_tienda_8_4 → wp_tienda_8_5)
func copyName(_ db: String, _ php: String) -> String {
    var base = db.replacingOccurrences(of: "[_-][0-9]+_[0-9]+(_[0-9]+)?$", with: "", options: .regularExpression)
    if base.isEmpty { base = db }
    let name = base + "_" + php.split(separator: ".").prefix(2).joined(separator: "_")
    return name.count <= 64 ? name : db
}

/// Guarda vínculos (base, versión, carpeta; carpeta vacía = ninguna) en ~/.lvm-instalador/proyectos,
/// como base@versión=carpeta. Devuelve el error o nil
func writeLinks(_ changes: [(String, String, String)]) -> String? {
    let path = LOG_DIR + "/proyectos"
    let keys = Set(changes.map { $0.0 + "@" + $0.1 })
    var lines = ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").components(separatedBy: "\n")
        .filter { !$0.isEmpty && !keys.contains($0.components(separatedBy: "=")[0]) }
    lines += changes.map { "\($0.0)@\($0.1)=\($0.2)" }
    do {
        try FileManager.default.createDirectory(atPath: LOG_DIR, withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    } catch {
        return error.localizedDescription
    }
    return nil
}

/// Nombre de BBDD válido (vacío si no lo es: la configuración la trae el proyecto)
func cleanDbName(_ db: String) -> String {
    return db.range(of: "^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil ? db : ""
}

/// (tipo, carpeta del panel) de un proyecto: wp-admin en WordPress y, en PrestaShop, su carpeta de
/// administración (cada tienda la llama de una forma: se reconoce por lo que tiene dentro)
func projectAdmin(_ folder: String) -> (String, String) {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    if fm.fileExists(atPath: folder + "/wp-config.php"),
       fm.fileExists(atPath: folder + "/wp-admin", isDirectory: &isDir), isDir.boolValue {
        return ("wp", "wp-admin")
    }
    let names = ((try? fm.contentsOfDirectory(atPath: folder)) ?? [])
        .sorted { a, b in
            let sa = a.lowercased().hasPrefix("admin"), sb = b.lowercased().hasPrefix("admin")
            return sa != sb ? sa : a < b
        }
    for n in names where n.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil {
        let d = folder + "/" + n
        guard let attrs = try? fm.attributesOfItem(atPath: d),
              (attrs[.type] as? FileAttributeType) == .typeDirectory else { continue }
        if fm.fileExists(atPath: d + "/index.php")
            && (fm.fileExists(atPath: d + "/ajax-tab.php") || fm.fileExists(atPath: d + "/get-file-admin.php")) {
            return ("ps", n)
        }
    }
    return ("", "")
}

/// Abre una carpeta en Visual Studio Code. Si ya tiene una ventana con ella, VS Code la trae delante
/// en lugar de abrir otra
func openInVSCode(_ folder: String) {
    guard let app = vscodeURL() else {
        message("Visual Studio Code no está instalado", "Descárgalo de code.visualstudio.com y muévelo a Aplicaciones.", error: true)
        return
    }
    let conf = NSWorkspace.OpenConfiguration()
    conf.activates = true
    NSWorkspace.shared.open([URL(fileURLWithPath: folder, isDirectory: true)], withApplicationAt: app,
                            configuration: conf) { _, error in
        guard let error = error else { return }
        DispatchQueue.main.async {
            message("No se ha podido abrir Visual Studio Code", error.localizedDescription, error: true)
        }
    }
}

/// Los tipos de fichero que se pueden elegir en un panel de abrir, por su extensión (en mayúsculas o
/// minúsculas: el tipo es el mismo). allowedFileTypes, con las extensiones, está obsoleto desde macOS 12
func fileTypes(_ exts: [String]) -> [UTType] {
    var out: [UTType] = []
    for e in exts {
        if let t = UTType(filenameExtension: e.lowercased()), !out.contains(t) { out.append(t) }
    }
    return out
}

// MARK: - Dialogos (NSAlert)

/// Ancho del texto de los dialogos. Va en una vista propia: NSAlert lo pondria en una columna
/// estrecha que parte en cuatro lineas cualquier frase
let DIALOG_WIDTH: CGFloat = 460

/// (centrado, como el título: los diálogos llevan el título y la explicación en el centro)
func dialogLabel(_ text: String, font: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize),
                 color: NSColor = .labelColor, align: NSTextAlignment = .center) -> NSTextField {
    let l = NSTextField(wrappingLabelWithString: text)
    l.font = font
    l.textColor = color
    l.alignment = align
    l.preferredMaxLayoutWidth = DIALOG_WIDTH
    l.isSelectable = true
    // Más aire: interlineado y separación entre párrafos
    let p = NSMutableParagraphStyle()
    p.alignment = align
    p.lineSpacing = 3
    p.paragraphSpacing = 8
    l.attributedStringValue = NSAttributedString(string: text, attributes: [
        .font: font, .foregroundColor: color, .paragraphStyle: p])
    return l
}

/// Lo que va a hacer un diálogo que pide confirmar varios cambios: «Qué se va a realizar» y los
/// cambios numerados, a la izquierda y separados entre sí (cada uno con sangría francesa)
func dialogSteps(_ steps: [String]) -> NSTextField {
    let out = NSMutableAttributedString()
    let body = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let bold = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
    let green = NSColor(red: 0x45 / 255.0, green: 0xA5 / 255.0, blue: 0x7C / 255.0, alpha: 1)
    let head = NSMutableParagraphStyle()
    head.paragraphSpacing = 4
    out.append(NSAttributedString(string: "Qué se va a realizar\n", attributes: [
        .font: bold, .foregroundColor: NSColor.labelColor, .paragraphStyle: head]))
    for (i, step) in steps.enumerated() {
        let p = NSMutableParagraphStyle()
        p.tabStops = [NSTextTab(textAlignment: .left, location: 28)]
        p.defaultTabInterval = 28
        p.firstLineHeadIndent = 6
        p.headIndent = 28
        p.lineSpacing = 3
        p.paragraphSpacingBefore = 10
        let end = i == steps.count - 1 ? "" : "\n"
        out.append(NSAttributedString(string: "\(i + 1).", attributes: [
            .font: bold, .foregroundColor: green, .paragraphStyle: p]))
        out.append(NSAttributedString(string: "\t" + step + end, attributes: [
            .font: body, .foregroundColor: NSColor.labelColor, .paragraphStyle: p]))
    }
    let l = NSTextField(wrappingLabelWithString: "")
    l.alignment = .left
    l.preferredMaxLayoutWidth = DIALOG_WIDTH
    l.isSelectable = true
    // (sin esto, al seleccionar se pierden los colores y las sangrías)
    l.allowsEditingTextAttributes = true
    l.attributedStringValue = out
    return l
}

/// Accesorio de un diálogo: las vistas en columna, centradas y con aire entre ellas
func dialogStack(_ views: [NSView], spacing: CGFloat = 16) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = spacing
    stack.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 8, right: 0)
    for v in views {
        if let l = v as? NSTextField, !l.isEditable {
            l.translatesAutoresizingMaskIntoConstraints = false
            l.widthAnchor.constraint(equalToConstant: DIALOG_WIDTH).isActive = true
        }
        stack.addArrangedSubview(v)
    }
    stack.layoutSubtreeIfNeeded()
    stack.frame = NSRect(x: 0, y: 0, width: DIALOG_WIDTH, height: stack.fittingSize.height)
    return stack
}

/// Opciones (botones de opción con su nota debajo) alineadas entre sí a la izquierda: en un diálogo,
/// el bloque va centrado, pero cada opción no (quedarían a distintas alturas del borde)
func dialogOptions(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = spacing
    return stack
}

/// Botones de opción que van en columnas distintas y aun así se excluyen entre sí
final class RadioGroup: NSObject {
    var buttons: [NSButton] = []
    /// (opcional) se llama con el índice del elegido
    var onPick: ((Int) -> Void)? = nil
    @objc func pick(_ sender: NSButton) {
        for b in buttons { b.state = b === sender ? .on : .off }
        if let i = buttons.firstIndex(where: { $0 === sender }) { onPick?(i) }
    }
}

/// Ancho de un desplegable o un campo para que se vea entero el texto más largo (con la flecha y
/// los márgenes), entre min y max
func fitWidth(_ texts: [String], min lo: CGFloat, max hi: CGFloat) -> CGFloat {
    let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let widest = texts.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
    return Swift.min(hi, Swift.max(lo, (widest + 48).rounded(.up)))
}

struct DialogResult {
    var ok = false
    var checked = false
    var text = ""
}

final class DialogValidator: NSObject, NSTextFieldDelegate {
    var update: () -> Void = {}
    @objc func changed(_ sender: Any?) { update() }
    func controlTextDidChange(_ obj: Notification) { update() }
}

/// Ventana modal con casilla y campo de texto opcionales.
/// validate(casilla marcada, texto) -> (se puede aceptar, texto de la nota, la nota es un error).
/// Si hay casilla y campo, el campo solo se puede usar con la casilla desmarcada (confirmar sin copia).
@discardableResult
/// okLabel dice lo que hace («Borrar la BBDD»), no «Aceptar»; cancelLabel, lo que hace el otro
/// botón (Cancelar, o «Seguir» si lo que se confirma es cancelar una tarea)
func runDialog(title: String, text: String, okLabel: String, style: NSAlert.Style = .informational,
               destructive: Bool = false, checkbox: String? = nil, checked: Bool = true,
               hasField: Bool = false, fieldLabel: String? = nil, placeholder: String = "",
               value: String = "", secure: Bool = false, cancelLabel: String = "Cancelar",
               steps: [String] = [],
               validate: ((Bool, String) -> (Bool, String?, Bool))? = nil) -> DialogResult {
    let alert = NSAlert()
    alert.messageText = title
    alert.alertStyle = style
    let ok = alert.addButton(withTitle: okLabel)
    let cancel = alert.addButton(withTitle: cancelLabel)
    if destructive {
        ok.hasDestructiveAction = true
        // En las acciones destructivas Intro no acepta
        // (con Escape y no con Intro: si no, Cancelar sale con el color de acento, como si fuera el
        // principal)
        ok.keyEquivalent = ""
        cancel.keyEquivalent = "\u{1b}"
    }

    let width = DIALOG_WIDTH
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 16
    stack.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 8, right: 0)
    if !steps.isEmpty {
        let l = dialogSteps(steps)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: width).isActive = true
        stack.addArrangedSubview(l)
    }
    if !text.isEmpty {
        // (con los cambios numerados encima, el texto es una nota: a la izquierda, como ellos)
        let l = steps.isEmpty ? dialogLabel(text) : dialogLabel(text, color: .secondaryLabelColor, align: .left)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: width).isActive = true
        stack.addArrangedSubview(l)
    }
    let validator = DialogValidator()
    var box: NSButton? = nil
    var input: NSTextField? = nil
    var note: NSTextField? = nil

    if let c = checkbox {
        let b = NSButton(checkboxWithTitle: c, target: validator, action: #selector(DialogValidator.changed(_:)))
        b.state = checked ? .on : .off
        stack.addArrangedSubview(b)
        box = b
    }
    if hasField {
        if let l = fieldLabel {
            let n = NSTextField(wrappingLabelWithString: l)
            n.preferredMaxLayoutWidth = width
            n.alignment = .center
            n.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            n.textColor = .secondaryLabelColor
            stack.addArrangedSubview(n)
            note = n
        }
        let f: NSTextField = secure ? NSSecureTextField() : NSTextField()
        // Campo algo más alto, como los de Ajustes del Sistema
        f.controlSize = .large
        f.font = NSFont.systemFont(ofSize: 13)
        f.placeholderString = placeholder
        f.stringValue = value
        f.delegate = validator
        f.translatesAutoresizingMaskIntoConstraints = false
        f.widthAnchor.constraint(equalToConstant: width).isActive = true
        stack.addArrangedSubview(f)
        input = f
    }
    if !stack.arrangedSubviews.isEmpty {
        stack.layoutSubtreeIfNeeded()
        let h = max(stack.fittingSize.height, 24)
        stack.frame = NSRect(x: 0, y: 0, width: width, height: h)
        alert.accessoryView = stack
    }

    validator.update = {
        let isChecked = box?.state == .on
        if let f = input, box != nil { f.isEnabled = !isChecked }
        if let v = validate {
            let (enabled, message, isError) = v(isChecked, input?.stringValue ?? "")
            ok.isEnabled = enabled
            if let n = note, let m = message {
                n.stringValue = m
                n.textColor = isError ? .systemRed : .secondaryLabelColor
            }
        }
    }
    validator.update()
    if let f = input, f.isEnabled { alert.window.initialFirstResponder = f }

    let resp = alert.runStyled()
    return DialogResult(ok: resp == .alertFirstButtonReturn, checked: box?.state == .on,
                        text: (input?.stringValue ?? "").trimmingCharacters(in: .whitespaces))
}

/// Contraseña de administrador, como el diálogo de autorización de macOS: centrado, con aire, el
/// icono de la aplicación con un candado, un campo estrecho y alto y botones grandes
struct PasswordView: View {
    let user: String
    let retry: Bool
    let onDone: (String?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.gray))
                    .overlay(Circle().stroke(Color(NSColor.windowBackgroundColor), lineWidth: 2))
                    .offset(x: 6, y: 4)
            }
            .padding(.bottom, 18)
            Text("Contraseña de administrador")
                .font(.system(size: 15, weight: .bold))
                .padding(.bottom, 8)
            Text("Esta acción necesita permisos de administrador. Escribe la contraseña de \(user) para continuar.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if retry {
                Text("Contraseña incorrecta. Vuelve a intentarlo.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(RED)
                    .padding(.top, 10)
            }
            SecureField("Contraseña", text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { if !text.isEmpty { onDone(text) } }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(NSColor.textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(focused ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.18),
                            lineWidth: focused ? 2 : 1))
                .frame(width: 236)
                .padding(.top, 22)
            HStack(spacing: 10) {
                Button(action: { onDone(nil) }) { Text("Cancelar").frame(maxWidth: .infinity) }
                    .keyboardShortcut(.cancelAction)
                    .hoverPointer()
                Button(action: { onDone(text) }) { Text("Continuar").frame(maxWidth: .infinity) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.isEmpty)
                    .hoverPointer()
            }
            .controlSize(.large)
            .frame(width: 236)
            .padding(.top, 22)
        }
        .padding(.horizontal, 32)
        .padding(.top, 30)
        .padding(.bottom, 24)
        .frame(width: 320)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true }
        }
    }
}

enum PasswordPanel {
    /// Pide la contraseña en una ventana propia (modal). nil si se cancela
    static func ask(user: String, retry: Bool) -> String? {
        var result: String? = nil
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 300),
                            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(b)?.isHidden = true
        }
        let host = NSHostingView(rootView: PasswordView(user: user, retry: retry, onDone: { text in
            result = text
            NSApp.stopModal()
        }))
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return result
    }
}

extension NSAlert {
    /// Como runModal, pero con los botones de la ventana: grandes y el principal (el primero) en
    /// azul, o en rojo si borra; no con el color de acento del sistema (gris con el acento grafito)
    @discardableResult
    func runStyled() -> NSApplication.ModalResponse {
        let blue = NSColor(srgbRed: 0x0A / 255.0, green: 0x84 / 255.0, blue: 1, alpha: 1)
        for (i, b) in buttons.enumerated() {
            b.controlSize = .large
            if i == 0 {
                b.bezelColor = b.hasDestructiveAction ? .systemRed : blue
            }
        }
        // (después de layout() se pueden mover sus vistas: NSAlert ya no las vuelve a colocar)
        layout()
        centerTexts()
        return runModal()
    }

    /// El título y el texto informativo, centrados. Con una vista accesoria ancha, NSAlert los pone
    /// a la izquierda, en una columna estrecha: se les da el ancho de la vista accesoria (que va
    /// debajo, en la misma columna) y se centran
    func centerTexts() {
        guard let content = window.contentView else { return }
        let acc = accessoryView
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        func walk(_ v: NSView) {
            for s in v.subviews {
                if let a = acc, s === a { continue }
                if let t = s as? NSTextField, !t.isEditable, !t.stringValue.isEmpty,
                   t.stringValue == messageText || t.stringValue == informativeText {
                    t.alignment = .center
                    let m = NSMutableAttributedString(attributedString: t.attributedStringValue)
                    m.addAttribute(.paragraphStyle, value: center, range: NSRange(location: 0, length: m.length))
                    t.attributedStringValue = m
                    if let a = acc, let sup = t.superview, let asup = a.superview {
                        let r = sup.convert(a.frame, from: asup)
                        if r.width > t.frame.width {
                            t.frame = NSRect(x: r.minX, y: t.frame.minY, width: r.width, height: t.frame.height)
                        }
                    }
                }
                walk(s)
            }
        }
        walk(content)
    }
}

func message(_ title: String, _ text: String = "", error: Bool = false) {
    let alert = NSAlert()
    alert.messageText = title
    alert.alertStyle = error ? .warning : .informational
    alert.addButton(withTitle: "Cerrar")
    let l = dialogLabel(text)
    let h = text.isEmpty ? 1 : l.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: DIALOG_WIDTH, height: 10000)).height
    l.frame = NSRect(x: 0, y: 0, width: DIALOG_WIDTH, height: ceil(h))
    alert.accessoryView = l
    alert.runStyled()
}

/// steps: los cambios que se van a hacer (numerados, con «Qué se va a realizar»); text va entonces
/// debajo, como nota
func confirm(_ title: String, _ text: String, _ okLabel: String, destructive: Bool = false,
             steps: [String] = []) -> Bool {
    return runDialog(title: title, text: text, okLabel: okLabel, style: destructive ? .warning : .informational,
                     destructive: destructive, steps: steps).ok
}

/// Markdown de «lvm-instalador novedades»: «## versión · fecha», viñetas «- » (con dos espacios
/// delante, dentro de la anterior), **negrita** y `código`
func markdownAttributed(_ text: String) -> NSAttributedString {
    let out = NSMutableAttributedString()
    let body = NSFont.systemFont(ofSize: 13)
    let bold = NSFont.boldSystemFont(ofSize: 13)
    let code = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let green = NSColor(red: 0x45 / 255.0, green: 0xA5 / 255.0, blue: 0x7C / 255.0, alpha: 1)
    // (con aire: espacio entre versiones, entre puntos y entre las líneas de un mismo punto)
    func para(indent: CGFloat, hanging: CGFloat, before: CGFloat, after: CGFloat) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.firstLineHeadIndent = indent
        p.headIndent = indent + hanging
        p.paragraphSpacingBefore = before
        p.paragraphSpacing = after
        p.lineSpacing = 4
        return p
    }
    func add(_ s: String, _ font: NSFont, _ color: NSColor, _ style: NSParagraphStyle, background: NSColor? = nil) {
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        if let bg = background { attrs[.backgroundColor] = bg }
        out.append(NSAttributedString(string: s, attributes: attrs))
    }
    let pieces = try! NSRegularExpression(pattern: "(\\*\\*[^*]+\\*\\*|`[^`]+`)")
    var first = true
    for line in text.components(separatedBy: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
        if !first { add("\n", body, .labelColor, NSParagraphStyle.default) }
        let top = first
        first = false
        if line.hasPrefix("## ") {
            let parts = String(line.dropFirst(3)).components(separatedBy: " · ")
            let style = para(indent: 0, hanging: 0, before: top ? 0 : 28, after: 10)
            add(parts[0], NSFont.boldSystemFont(ofSize: 17), .labelColor, style)
            if parts.count > 1 {
                add("   " + parts[1], NSFont.systemFont(ofSize: 11), .secondaryLabelColor, style)
            }
            continue
        }
        var style = para(indent: 0, hanging: 0, before: 6, after: 8)
        var rest = line
        let spaces = line.prefix(while: { $0 == " " }).count
        if line.dropFirst(spaces).hasPrefix("- ") {
            let depth = min(spaces / 2, 1)
            style = para(indent: depth == 0 ? 8 : 28, hanging: 14, before: depth == 0 ? 10 : 6, after: 2)
            add(depth == 0 ? "•  " : "◦  ", bold, green, style)
            rest = String(line.dropFirst(spaces + 2))
        }
        let ns = rest as NSString
        var pos = 0
        for m in pieces.matches(in: rest, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > pos {
                add(ns.substring(with: NSRange(location: pos, length: m.range.location - pos)), body, .labelColor, style)
            }
            let s = ns.substring(with: m.range)
            if s.hasPrefix("**") {
                add(String(s.dropFirst(2).dropLast(2)), bold, .labelColor, style)
            } else {
                add(String(s.dropFirst().dropLast()), code, .labelColor, style,
                    background: NSColor.gray.withAlphaComponent(0.16))
            }
            pos = m.range.location + m.range.length
        }
        if pos < ns.length { add(ns.substring(from: pos), body, .labelColor, style) }
    }
    return out
}

/// Texto largo con desplazamiento (Novedades en Markdown, comandos, registros)
/// Ayuda de los comandos: cada sección («=== TÍTULO ===») en verde y grande y cada orden en negrita,
/// para distinguirlas de su explicación (con sangría, debajo)
func commandsAttributed(_ text: String) -> NSAttributedString {
    let out = NSMutableAttributedString()
    let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let monoBold = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    let green = NSColor(red: 0x45 / 255.0, green: 0xA5 / 255.0, blue: 0x7C / 255.0, alpha: 1)
    for (n, line) in text.components(separatedBy: "\n").enumerated() {
        let p = NSMutableParagraphStyle()
        var font = mono, color = NSColor.labelColor
        if line.hasPrefix("=== ") {
            font = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .bold)
            color = green
            p.paragraphSpacingBefore = 10
            p.paragraphSpacing = 4
        } else if line.hasPrefix("  lvm-instalador") {
            font = monoBold
            p.paragraphSpacingBefore = 4
        }
        out.append(NSAttributedString(string: (n > 0 ? "\n" : "") + line,
                                      attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p]))
    }
    return out
}

func showLongText(_ title: String, _ text: String, subtitle: String = "", toEnd: Bool = false,
                  markdown: Bool = false, commands: Bool = false) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = subtitle
    alert.addButton(withTitle: "Cerrar")
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 720, height: 560))
    scroll.hasVerticalScroller = true
    let tv = NSTextView(frame: scroll.bounds)
    tv.isEditable = false
    tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    tv.textContainerInset = NSSize(width: 10, height: 10)
    if markdown {
        tv.textContainerInset = NSSize(width: 18, height: 14)
        tv.textStorage?.setAttributedString(markdownAttributed(text))
    } else if commands {
        tv.textContainerInset = NSSize(width: 16, height: 12)
        tv.textStorage?.setAttributedString(commandsAttributed(text))
    } else {
        tv.string = text
    }
    tv.autoresizingMask = [.width]
    scroll.documentView = tv
    alert.accessoryView = scroll
    // Registros: lo más reciente está al final
    if toEnd { DispatchQueue.main.async { tv.scrollToEndOfDocument(nil) } }
    alert.runStyled()
}

// Proyectos (htdocs compartido; LVM_HTDOCS solo para pruebas) y dominio de un proyecto nuevo
let HTDOCS = ProcessInfo.processInfo.environment["LVM_HTDOCS"] ?? "/Library/Nexum/XAMPP-compartido/htdocs"
let DOMAIN_RX = try! NSRegularExpression(pattern: "^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$")
/// Dominio escrito o pegado como dirección (https://www.mitienda.com/tienda): solo el nombre
func cleanDomain(_ text: String) -> String {
    var d = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let r = d.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) { d.removeSubrange(r) }
    if let cut = d.firstIndex(where: { "/?#:".contains($0) || $0.isWhitespace }) { d = String(d[..<cut]) }
    while d.hasSuffix(".") { d.removeLast() }
    return d
}
let FOLDER_RX = try! NSRegularExpression(pattern: "^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$")
let ERROR_LOG = "/Applications/XAMPP/xamppfiles/logs/error_log"
// Registros mayores que esto no se abren en el editor de textos (solo «Ver el final»)
let LOG_OPEN_MAX: Int64 = 20 * 1024 * 1024

/// Carpetas de proyectos de htdocs (sin enlaces como web.local ni ocultas)
func projectFolders() -> [String] {
    let fm = FileManager.default
    let names = (try? fm.contentsOfDirectory(atPath: HTDOCS)) ?? []
    return names.filter { n in
        if n.hasPrefix(".") { return false }
        let path = HTDOCS + "/" + n
        let attrs = try? fm.attributesOfItem(atPath: path)
        if (attrs?[.type] as? FileAttributeType) == .typeSymbolicLink { return false }
        var dir: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
    }.sorted { $0.lowercased() < $1.lowercased() }
}

/// Base de datos de la configuración de un proyecto (wp-config.php, PrestaShop o .env)
func projectDb(_ folder: String) -> String {
    let rules: [(String, String)] = [
        ("wp-config.php", "define\\(\\s*['\"]DB_NAME['\"]\\s*,\\s*['\"]([^'\"]+)"),
        ("app/config/parameters.php", "['\"]database_name['\"]\\s*=>\\s*['\"]([^'\"]+)"),
        ("config/settings.inc.php", "define\\(\\s*['\"]_DB_NAME_['\"]\\s*,\\s*['\"]([^'\"]+)"),
        (".env", "^\\s*DB_DATABASE\\s*=\\s*[\"']?([^\"'\\s#]+)"),
    ]
    for (rel, pattern) in rules {
        let path = HTDOCS + "/" + folder + "/" + rel
        // Solo un fichero normal de hasta 2 MB y sin enlaces: un FIFO o un enlace a /dev/zero de un
        // proyecto colgarian la ventana
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              (attrs[.type] as? FileAttributeType) == .typeRegular,
              let size = attrs[.size] as? NSNumber, size.intValue <= 2_000_000,
              let text = try? String(contentsOfFile: path, encoding: .utf8),
              let rx = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines),
              let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { continue }
        // Solo nombres de BBDD validos (la configuracion la trae el proyecto)
        let db = String(text[r])
        return db.range(of: "^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil ? db : ""
    }
    return ""
}

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

/// Cierra la aplicación y la vuelve a abrir con el script nuevo («lvm-instalador ventana» la rehace
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

// MARK: - Tareas (acciones del script en una pseudoterminal)

final class TaskRunner: ObservableObject, Identifiable {
    let id = UUID()
    /// El título con que se lanzó (head cambia al acabar)
    let title: String
    let args: [String]
    let withProgress: Bool
    let doneText: String
    let autoClose: Bool
    let env: [String: String]
    let cancelText: (String, String, String)?
    weak var model: AppModel?
    var onDone: ((Bool, TaskRunner, InstallProgress?) -> Void)?

    @Published var head: String
    @Published var fraction: Double? = nil
    // Encima de la barra: lo que se hace (a la izquierda) y el porcentaje con lo que queda (a la derecha)
    @Published var barText = "Preparando…"
    @Published var pctText = ""
    @Published var info = ""
    @Published var log = ""
    @Published var parts: [String] = []
    @Published var cur = 0
    @Published var failedPart = 0
    @Published var finished = false
    @Published var showLog: Bool
    @Published var extraLabel: String? = nil
    var extraAction: (() -> Void)? = nil
    // Si falla: botón para ver el informe del error (o el registro) y copiarlo
    @Published var failed = false
    @Published var showReport = false
    // Al terminar bien: check verde grande en la ventana de la tarea
    @Published var succeeded = false

    private var proc: Process?
    private var input: FileHandle?
    private var outPipe: Pipe?
    private var pfile: String?
    private var timer: Timer?
    private var pending = ""
    private var finSeen = false
    private var sincePrompt = ""
    private var prompts = 0
    private var askingPassword = false
    private var cancelled = false
    private let started = Date()
    private let console = Console()
    // Porcentaje que se lee en la salida (tareas sin progreso propio): primero, último y cuándo empezó
    private var seenPct: (Int, Int, Date)? = nil

    init(title: String, args: [String], withProgress: Bool, doneText: String, autoClose: Bool,
         env: [String: String], cancelText: (String, String, String)?) {
        self.head = title
        self.title = title
        self.args = args
        self.withProgress = withProgress
        self.doneText = doneText
        self.autoClose = autoClose
        self.env = env
        self.cancelText = cancelText
        self.showLog = !withProgress
    }

    func start() {
        var extra = env
        if withProgress {
            let path = NSTemporaryDirectory() + "lvm-progreso-" + UUID().uuidString
            FileManager.default.createFile(atPath: path, contents: nil)
            pfile = path
            extra["LVM_PROGRESO"] = path
        }
        let p = Process()
        // script crea la pseudoterminal; bash -c deja al final el codigo de salida del instalador
        p.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        // La marca de fin va en el entorno, no en los argumentos: estos los ve cualquier usuario del
        // Mac con ps (el entorno, solo tu usuario)
        p.arguments = ["-q", "/dev/null", "/bin/bash", "-c",
                       // Lo primero, la terminal exclusiva (TIOCEXCL): ningun otro programa de tu
                       // usuario puede abrirla para leer la contraseña o escribir la marca de sudo
                       // Si no se puede, la tarea no sigue (la contraseña iria por una terminal abierta)
                       "/usr/bin/python3 -I -c 'import fcntl, termios; fcntl.ioctl(0, termios.TIOCEXCL)' 2> /dev/null "
                       + "|| { echo 'No se ha podido reservar la terminal de la tarea (python3 de Xcode)'; "
                       + "echo \"@@LVM-FIN-$LVM_FIN 97@@\"; exit 97; }; "
                       + "/bin/bash \"$0\" \"$@\"; echo \"@@LVM-FIN-$LVM_FIN $?@@\""] + scriptArgs(args)
        extra["LVM_FIN"] = FIN_TOKEN
        // (lo que cambia algo pide la contraseña al empezar: cancelarla no deja nada a medias)
        extra["LVM_TAREA"] = "1"
        p.environment = scriptEnv(extra)
        p.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        let inPipe = Pipe(), out = Pipe()
        p.standardInput = inPipe
        p.standardOutput = out
        p.standardError = out
        input = inPipe.fileHandleForWriting
        outPipe = out
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty {
                h.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.feed(text) }
        }
        p.terminationHandler = { [weak self] proc in
            let rc = proc.terminationStatus
            // Lo que quede por leer llega antes que el final
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.finish(rc) }
        }
        do {
            try p.run()
        } catch {
            log += "No se ha podido ejecutar el instalador: \(error.localizedDescription)\n"
            finish(1)
            return
        }
        proc = p
        timer = Timer.scheduledTimer(withTimeInterval: withProgress ? 1 : 0.15, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    private func feed(_ text: String) {
        pending += text
        while let r = pending.range(of: SUDO_MARK) {
            let before = String(pending[..<r.lowerBound])
            pending = String(pending[r.upperBound...])
            append(before)
            sincePrompt += before
            askPassword()
        }
        // Se guarda un trozo que pueda ser el principio de la marca
        var keep = 0
        for i in 1..<SUDO_MARK.count where pending.hasSuffix(String(SUDO_MARK.prefix(i))) { keep = i }
        let out = String(pending.dropLast(keep))
        pending = String(pending.suffix(keep))
        sincePrompt += out
        append(out)
        // La marca de fin la escribe bash al acabar el instalador: la tarea ha terminado aunque
        // script siga abierto (un servicio arrancado por la tarea puede seguir con su terminal)
        // (finish saca el código de salida de la propia marca)
        if !finished && !finSeen, FIN.firstMatch(in: log, range: NSRange(log.startIndex..., in: log)) != nil {
            finSeen = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.finish(0) }
        }
    }

    private func append(_ text: String) {
        if text.isEmpty { return }
        // El registro, como lo pintaría una terminal (las barras de las descargas en una línea)
        console.write(text)
        log = console.text
        if !withProgress {
            let plain = ANSI.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
            let ns = plain as NSString
            let found = SEEN_PCT.matches(in: plain, range: NSRange(location: 0, length: ns.length))
                .compactMap { Int(ns.substring(with: $0.range(at: 1))) }
                .filter { $0 <= 100 }
            if let last = found.last {
                // (si baja mucho, es otra descarga: se empieza a contar de nuevo)
                if let s = seenPct, last >= s.1 - 30 {
                    seenPct = (s.0, last, s.2)
                } else {
                    seenPct = (last, last, Date())
                }
            }
        }
    }

    private func askPassword() {
        // Un panel cada vez: mientras esta abierto, la tarea sigue escribiendo y otra marca (que
        // puede poner cualquier programa de la tarea) abriria otro encima
        if askingPassword { return }
        askingPassword = true
        defer { askingPassword = false }
        let lower = sincePrompt.lowercased()
        let retry = prompts > 0 && (lower.contains("sorry") || lower.contains("lo siento")
            || lower.contains("incorrect") || lower.contains("try again"))
        prompts += 1
        sincePrompt = ""
        // La marca la puede escribir cualquier programa de la tarea: la contraseña solo se envía si
        // hay un sudo de esta tarea esperando, con el eco de su terminal apagado (como en Linux)
        guard sudoAsking() else {
            append("\nAviso: se ha pedido la contraseña, pero no la pide sudo. No se ha enviado y se cancela la tarea.\n")
            cancel()
            return
        }
        let user = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()
        if let pass = PasswordPanel.ask(user: user, retry: retry) {
            // Mientras el panel estaba abierto, sudo ha podido dejar de esperar (o la tarea acabar):
            // se vuelve a comprobar antes de escribirla
            guard !finished, sudoAsking() else {
                append("\nAviso: sudo ya no esperaba la contraseña. No se ha enviado.\n")
                cancel()
                return
            }
            input?.write((pass + "\n").data(using: .utf8) ?? Data())
        } else {
            cancel()
        }
    }

    /// ¿Hay un sudo de root de esta tarea (descendiente de su proceso) leyendo de su terminal? Es lo
    /// que hace al pedir la contraseña, con el eco apagado (si solo espera a la orden que ejecuta, no)
    private func sudoAsking() -> Bool {
        guard let root = proc?.processIdentifier else { return false }
        var children: [Int32: [Int32]] = [:]
        var info: [Int32: (String, String)] = [:]
        var ttys: [Int32: String] = [:]
        // Solo cuenta un sudo de root (el de verdad es setuid): un programa de tu usuario que se
        // llame sudo no vale
        for line in captureOutput("/bin/ps", ["-axo", "pid=,ppid=,uid=,tty=,comm="]).components(separatedBy: "\n") {
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            guard f.count >= 5, let pid = Int32(f[0]), let ppid = Int32(f[1]) else { continue }
            children[ppid, default: []].append(pid)
            ttys[pid] = String(f[3])
            let path = f[4...].joined(separator: " ")
            if f[2] == "0" && (path == "sudo" || path == "/usr/bin/sudo") {
                info[pid] = (String(f[3]), "sudo")
            }
        }
        var stack = [root]
        var sudoPid: Int32? = nil
        var found = false
        var seen = Set<Int32>()
        while let p = stack.popLast() {
            guard !seen.contains(p) else { continue }
            seen.insert(p)
            for c in children[p] ?? [] {
                stack.append(c)
                if let i = info[c], i.1 == "sudo" {
                    found = true
                    sudoPid = c
                }
            }
        }
        // Mientras pide la contraseña, sudo no tiene hijos: los tiene cuando ya esta ejecutando la
        // orden (entonces la contraseña iria a esa orden, no a sudo)
        guard found, let pid = sudoPid, (children[pid] ?? []).isEmpty else { return false }
        // Y en la terminal de la tarea (la del bash que lanza script): un programa de la tarea que
        // abriera otra terminal con su propio sudo no recibe la contraseña
        guard let first = children[root]?.first, let taskTty = ttys[first], taskTty != "??",
              info[pid]?.0 == taskTty else { return false }
        // Con la terminal exclusiva (TIOCEXCL) stty ya no puede abrirla; ps dice donde espera el
        // proceso: «ttyin» es leyendo de la terminal. macOS suele dar «-» (sin dato): se acepta
        let wchan = captureOutput("/bin/ps", ["-o", "wchan=", "-p", String(pid)])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return wchan.isEmpty || wchan == "-" || wchan.hasPrefix("ttyin")
    }

    private func tick() {
        if finished { return }
        let clock = fmtClock(Int(Date().timeIntervalSince(started)))
        if withProgress {
            if let path = pfile, let p = readProgress(path) {
                show(p)
            } else {
                update(nil, "Preparando…", "0 %", "Tiempo: \(clock)")
            }
        } else if let s = seenPct {
            // Sin progreso propio, pero la salida da un porcentaje (una descarga, por ejemplo)
            update(Double(s.1) / 100, "Trabajando…",
                   pctLine(s.1, timeLeft(Date().timeIntervalSince(s.2), s.1 - s.0, 100 - s.1)), "Tiempo: \(clock)")
        } else {
            update(nil, "Trabajando…", "", "Tiempo: \(clock)  ·  sin porcentaje: esta tarea no dice cuánto le queda")
        }
    }

    /// La barra y sus textos (solo lo que cambia: el reloj va cada 0,15 s y redibujaría el registro)
    private func update(_ f: Double?, _ what: String, _ pct: String, _ text: String) {
        if fraction != f { fraction = f }
        if barText != what { barText = what }
        if pctText != pct { pctText = pct }
        if info != text { info = text }
    }

    /// «45 %   ·   quedan unos 3 min»
    private func pctLine(_ pct: Int, _ left: String) -> String {
        return "\(pct) %" + (left.isEmpty ? "" : "   ·   " + left)
    }

    private func show(_ p: InstallProgress) {
        let total = ((p.k - 1) * 100 + p.pct) / max(p.n, 1)
        let name = p.name + (p.n > 1 ? "   (\(p.k) de \(p.n))" : "")
        if head != name { head = name }
        let what = p.what.isEmpty ? (p.pct >= 100 ? "terminado" : "") : p.what
        let since = Int(Date().timeIntervalSince1970) - (p.started > 0 ? p.started : Int(started.timeIntervalSince1970))
        var text = "Tiempo: \(fmtClock(since))"
        if p.mode == "lsof" && p.total > 0 {
            text = "\(fmtSize(min(p.done, p.total))) de \(fmtSize(p.total))   ·   " + text
        }
        update(Double(total) / 100, String(what.prefix(1)).uppercased() + String(what.dropFirst()),
               pctLine(total, p.pct < 100 ? timeLeft(Double(since), p.pct, 100 - p.pct) : ""), text)
        if !p.parts.isEmpty && p.parts != parts { parts = p.parts }
        if cur != p.cur { cur = p.cur }
    }

    private func finish(_ status: Int32) {
        if finished { return }
        finished = true
        timer?.invalidate()
        outPipe?.fileHandleForReading.readabilityHandler = nil
        append(pending)
        pending = ""
        // Codigo de salida del instalador (el de script no siempre es el del comando)
        var rc = status
        let range = NSRange(log.startIndex..., in: log)
        if let m = FIN.matches(in: log, range: range).last, let r = Range(m.range(at: 1), in: log) {
            rc = Int32(log[r]) ?? status
        }
        let text = console.text
        log = FIN.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")

        let p = pfile.flatMap { readProgress($0) }
        if let path = pfile { try? FileManager.default.removeItem(atPath: path) }
        let ok = rc == 0 && !cancelled
        info = "Tiempo total: \(fmtClock(Int(Date().timeIntervalSince(started))))"
        if cancelled {
            head = "Cancelado"
            barText = "Cancelado"
            pctText = ""
        } else if ok {
            head = doneText
            barText = "Terminado"
            pctText = "100 %"
            fraction = 1
            cur = 999
            succeeded = true
        } else {
            head = "No se ha podido completar"
            barText = "Error"
            pctText = ""
            if fraction == nil { fraction = 0 }
            showLog = true
            failed = true
            if let pr = p { failedPart = pr.cur }
        }
        if let pr = p { showResults(pr, ok) }
        onDone?(ok, self, p)
        if ok && autoClose {
            model?.task = nil
            model?.toast(doneText)
        } else if model?.taskHidden == true {
            // (en segundo plano: vuelve para enseñar cómo ha ido; si ha fallado, con su registro)
            model?.taskHidden = false
        }
    }

    private func showResults(_ p: InstallProgress, _ ok: Bool) {
        let res = p.results.filter { !$0.0.hasPrefix("bd:") }
        if res.count > 1 || (!res.isEmpty && !ok) {
            let good = res.filter { $0.1 == "0" }.map { "XAMPP-" + itemFolder($0.0) }
            let bad = res.filter { $0.1 != "0" }.map { "XAMPP-" + itemFolder($0.0) }
            var lines: [String] = []
            if !good.isEmpty { lines.append("Instaladas: " + good.joined(separator: ", ")) }
            if !bad.isEmpty { lines.append("Con error: " + bad.joined(separator: ", ") + ". No se ha instalado nada de ellas; mira el registro.") }
            info = lines.joined(separator: "\n")
            if !res.isEmpty && bad.isEmpty { head = doneText }
        }
    }

    // El informe que deja el script al fallar una instalación (uno por versión con error) o, si no
    // lo hay, el final del registro. Devuelve el texto, la carpeta de los logs y si es un informe
    func report() -> (String, String, Bool) {
        var paths: [String] = []
        // Solo los informes de la carpeta de registros: la línea podría escribirla otro programa para
        // mostrar (y copiar) cualquier fichero
        let logs = URL(fileURLWithPath: LOG_DIR).resolvingSymlinksInPath().path + "/"
        for m in REPORT.matches(in: log, range: NSRange(log.startIndex..., in: log)) {
            guard let r = Range(m.range(at: 1), in: log) else { continue }
            let path = String(log[r])
            let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            if real.hasPrefix(logs) && (path as NSString).lastPathComponent == "informe-error.txt"
                && !paths.contains(path) {
                paths.append(path)
            }
        }
        let parts = paths.compactMap { try? String(contentsOfFile: $0, encoding: .utf8) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.isEmpty {
            return (String(log.trimmingCharacters(in: .whitespacesAndNewlines).suffix(60_000)), LOG_DIR, false)
        }
        let sep = "\n\n" + String(repeating: "=", count: 70) + "\n\n"
        return (parts.joined(separator: sep), (paths.last! as NSString).deletingLastPathComponent, true)
    }

    func offer(_ label: String, _ action: @escaping () -> Void) {
        extraLabel = label
        extraAction = action
    }

    func cancel() {
        guard !finished, let p = proc else { return }
        cancelled = true
        // El instalador va en su propia sesion (la de la pseudoterminal): se para su grupo de procesos
        let pg = Process()
        pg.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pg.arguments = ["-P", String(p.processIdentifier)]
        let pipe = Pipe()
        pg.standardOutput = pipe
        if (try? pg.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            pg.waitUntilExit()
            for s in String(decoding: data, as: UTF8.self).components(separatedBy: "\n") {
                if let pid = Int32(s.trimmingCharacters(in: .whitespaces)) {
                    kill(-pid, SIGTERM)
                    kill(pid, SIGTERM)
                }
            }
        }
        p.terminate()
    }

    func closeTapped() {
        if finished {
            model?.task = nil
            return
        }
        if withProgress {
            let t = cancelText ?? ("¿Cancelar la instalación?",
                                   "Se pierde lo descargado y compilado hasta ahora. Las versiones instaladas no se tocan.",
                                   "Cancelar la instalación")
            if !runDialog(title: t.0, text: t.1, okLabel: t.2, style: .warning, destructive: true,
                          cancelLabel: "Seguir").ok { return }
        }
        cancel()
    }
}

// MARK: - Datos

struct Install: Identifiable, Equatable {
    let folder, php, apache, mariadb, ftp, perl, pma, blocker: String
    var id: String { return folder }
}

struct DbDate: Equatable {
    let when: Int
    /// true: importada con lvm-instalador (fecha exacta); false: último cambio de sus tablas
    let imported: Bool
}

/// Tipo c de la fecha de una base: no se ha importado con lvm-instalador
let DB_DATE_HELP = "Fecha en la que cambiaron por última vez las tablas de la BBDD (al importarla desde phpMyAdmin, por ejemplo). Las que se suben desde esta versión guardan la fecha exacta de la importación."

/// Antigüedad aproximada: hace 5 min, hace 3 horas, hace 12 días, hace 4 meses, hace 2 años
func fmtAge(_ secs: Int) -> String {
    if secs < 3600 { return "hace \(plural(max(1, secs / 60), "min", "min"))" }
    if secs < 86400 { return "hace \(plural(secs / 3600, "hora", "horas"))" }
    if secs < 60 * 86400 { return "hace \(plural(secs / 86400, "día", "días"))" }
    if secs < 365 * 86400 { return "hace \(plural(secs / (30 * 86400), "mes", "meses"))" }
    return "hace \(plural(secs / (365 * 86400), "año", "años"))"
}

/// Fecha de una base para su fila: la de su importación o la del último cambio de sus tablas
func dbDateText(_ date: DbDate?) -> String? {
    guard let d = date, d.when > 0 else { return nil }
    let f = DateFormatter()
    f.locale = Locale(identifier: "es_ES")
    f.dateFormat = "dd/MM/yyyy 'a las' HH:mm"
    let stamp = f.string(from: Date(timeIntervalSince1970: TimeInterval(d.when)))
    let age = fmtAge(max(0, Int(Date().timeIntervalSince1970) - d.when))
    return (d.imported ? "Importada el " : "Tablas cambiadas el ") + stamp + "  ·  " + age
}

/// Un proyecto https cuyo certificado es de confianza para todo el Mac (motivo: ca o firmado)
struct CertIssue: Equatable {
    let domain: String
    let why: String
}

struct AppData: Equatable {
    var name = "Nexum Dev Stack", version = "", signature = "", active = ""
    var running = false, official = false
    var vhosts = "/Library/Nexum/XAMPP-compartido/httpd-vhosts.conf", hosts = "/etc/hosts"
    /// Copias de las bases del XAMPP oficial (carpeta -> número de .zip) y XAMPP oficiales apartados
    var copies: [String: Int] = [:]
    var asides: [String] = []
    var installs: [Install] = []
    var dbs: [String: [String]] = [:]
    /// Fecha de cada base («versión|base»): la de su importación o la del último cambio de sus tablas
    var dbDates: [String: DbDate] = [:]
    /// Procesos de XAMPP en memoria que no son de la versión montada (resumen)
    var stray = ""
    /// Servicios de la versión montada a los que se puede entrar desde otros equipos de la red
    var exposed = ""
    /// Versiones a las que les falta algo para ser solo de este Mac (asegurar --todas)
    var unsecured: [String] = []
    /// Versión montada con las tablas del sistema de MariaDB antiguas y el tamaño de su registro de
    /// errores (reparar-bd-sistema)
    var dbsysVersion = ""
    var dbsysLog: Int64 = 0
    /// Certificados de proyectos en los que confía todo el Mac (dominio, motivo) y las CAs locales
    /// sin límite de dominios que los firman (lvm-instalador arreglar-certificados)
    var certs: [CertIssue] = []
    var cas: [String] = []
    /// Proyectos https cuyo certificado propio aún no acepta el navegador (G|dominio)
    var untrusted: [String] = []
    /// Tiendas con dominio real cuyo certificado acepta el navegador y ya no están falseadas (Q|dominio)
    var stale: [String] = []
    /// Estado de cada versión frente a PHP2Shell (X|carpeta|estado): ok, parche, parcheable,
    /// actualizable o sin-arreglo
    var php2shell: [String: String] = [:]
    /// Barrera entre webs puesta (T|1) o apagada (T|0)
    var barrier = true
    /// Correo de pruebas (E|…): nil si el script no lo trae
    var mail: MailState? = nil
}

/// Correo de pruebas (Mailpit): instalado, encendido, modo de los plugins de correo de WordPress
/// (mailpit, desactivar o nada), en marcha, versión instalada, dirección de su web y versión que
/// instala el gestor
struct MailState: Equatable {
    var installed = false
    var on = true
    var wp = "mailpit"
    var running = false
    var version = ""
    var url = "http://127.0.0.1:8025/"
    var offer = ""
}

/// Fecha del parche de seguridad oficial contra PHP2Shell de PHP 7.4.33, 8.0.30 y 8.1.34
let PHP2SHELL_DATE = "oct 2026"

/// ¿Es vulnerable a PHP2Shell (CVE-2026-109618 y CVE-2026-109619) una versión con ese estado?
func php2shellVulnerable(_ state: String) -> Bool {
    return state == "parcheable" || state == "actualizable" || state == "sin-arreglo"
}

/// Explicación del aviso de PHP2Shell de una versión (para el mensaje al pasar el ratón y los diálogos)
func php2shellText(_ state: String, _ php: String) -> String {
    switch state {
    case "parcheable":
        return "PHP \(php) es vulnerable a PHP2Shell (CVE-2026-109618 y CVE-2026-109619): un formulario de un proyecto puede acabar ejecutando código en tu Mac. Su rama ya no tiene versiones nuevas, pero sí el parche oficial de seguridad: actualízala (menú ⋯) y se le pone, con sus BBDD."
    case "actualizable":
        return "PHP \(php) es vulnerable a PHP2Shell (CVE-2026-109618 y CVE-2026-109619): un formulario de un proyecto puede acabar ejecutando código en tu Mac. Lo corrige el último parche de su rama: actualízala (menú ⋯)."
    case "sin-arreglo":
        return "PHP \(php) es vulnerable a PHP2Shell (CVE-2026-109618 y CVE-2026-109619) y su rama no tiene arreglo: úsala solo con proyectos de confianza."
    default:
        return ""
    }
}

/// Apache, MariaDB o el FTP de la versión montada (pestaña Servicios)
struct Service: Equatable, Identifiable {
    let name: String
    let running: Bool
    let ports: String
    let open: Bool
    let auto: Bool
    let user: String
    var id: String { return name }
}

/// Un parche de una rama (gui-parches), para «Otro parche concreto» de Instalar
struct PatchItem: Identifiable, Equatable {
    let version, date, state: String
    let security, latest: Bool
    var id: String { return version }
}

struct Branch: Identifiable, Equatable {
    let branch, latest: String
    let supported: Bool
    let mariadb, perl, state: String
    // Estado en php.net: stable, security o eol, y las fechas de fin del soporte activo y de seguridad
    let phpState, activeEnd, securityEnd: String
    // Fecha del último parche (AAAA-MM-DD) y si php.net lo marca como parche de seguridad
    let date: String
    let security: Bool
    var id: String { return branch }
}

final class AppModel: ObservableObject {
    @Published var data: AppData? = nil
    @Published var loadError: String? = nil
    @Published var branches: [Branch]? = nil
    @Published var branchesError: String? = nil
    /// Versión -> [php, fecha de publicación en php.net] (gui-fechas: llega después)
    @Published var phpDates: [String: [String]] = [:]
    /// Lo que se va a instalar: ramas (8.4, su último parche) y parches concretos (8.3.10)
    @Published var selected: Set<String> = []
    /// Otro parche concreto: la rama elegida y sus parches (nil mientras se consultan)
    @Published var patchBranch = ""
    @Published var patches: [PatchItem]? = nil
    @Published var patchesError: String? = nil
    @Published var expanded: Set<String> = []
    /// Apartados plegados (Instaladas, Instalar): se guardan en FOLDED_FILE
    @Published var folded: Set<String> = Set(((try? String(contentsOfFile: FOLDED_FILE, encoding: .utf8)) ?? "")
        .split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    /// La tarea sigue sin su hoja («Seguir en segundo plano»): al lado del visor, su aviso la trae de vuelta
    @Published var taskHidden = false
    /// Apariencia (Configuración): se guarda al cambiarla; si se oculta el apartado abierto, a Proyectos
    @Published var look = loadLook() {
        didSet {
            guard look != oldValue else { return }
            saveLook(look)
            if look.ocultos.contains(tab) { openTab("proyectos") }
        }
    }
    @Published var task: TaskRunner? = nil {
        // (si se cerró la ventana con una tarea en marcha, la aplicación se cierra al acabar la tarea)
        didSet {
            if task == nil && taskHidden { taskHidden = false }
            if task == nil && oldValue != nil && !TrayIcon.shared.on
                && !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }
    }
    /// El modelo de la aplicación, para el delegado (que no lo ve de otro modo)
    static weak var current: AppModel?
    @Published var toastText: String? = nil
    // Formulario «Subir o actualizar una base de datos»
    @Published var impFile: String? = nil
    @Published var impDb: String? = nil {
        didSet { if impDb != oldValue { refreshImpProjects() } }
    }
    // Proyecto de la base que se sube: queda como su base y, si es un WordPress, su wp-config.php la usa
    @Published var impProject: String? = nil
    @Published var impProjects: [String] = []
    // Tipo de cada carpeta: ps (tienda PrestaShop) o wp (WordPress)
    var impKind: [String: String] = [:]
    // Buscador de bases de datos y hoja «Cargar proyecto»
    @Published var dbQuery = ""
    @Published var projectReq: ProjectRequest? = nil
    // Dominios de los vhosts (pestaña Hosts): nil hasta leerlos
    @Published var hosts: [HostEntry]? = nil
    /// El vhost de los proyectos (web.local) que no lleva a 127.0.0.1: (nombre, dirección de ahora)
    @Published var hostsLinkFix: [[String]] = []
    // Apache, MariaDB y el FTP de la versión montada (pestaña Servicios): nil hasta leerlos
    @Published var services: [Service]? = nil
    // Proyectos de htdocs y búsqueda del bloque «Cargar proyecto» (Versiones)
    @Published var projects: ProjectsData? = nil
    @Published var projQuery = ""
    // Montar nuevo proyecto (asistente de tres pasos dentro de Cargar proyecto)
    @Published var npOpen = false
    @Published var npStep = 1
    /// Asistente: los repositorios de GitHub (los de la pestaña Repositorios), lo que se busca, el elegido, y
    /// el dominio de producción (falsearlo o no)
    /// Actualizar proyecto: si se ve su diálogo, el proyecto, la BBDD, el código, qué hacer con la carpeta
    /// (fusionar o sobrescribir) y lo que no vale de lo arrastrado
    @Published var upShown = false
    @Published var upFolder = ""
    @Published var upSql = ""
    @Published var upCode = ""
    @Published var upMode = "fusionar"
    @Published var upDb = ""
    var upDbKnown = false
    @Published var upSqlError = ""
    @Published var upCodeError = ""
    @Published var npRepos: [RepoItem] = []
    /// ¿Ya se ha leído alguna vez?, ¿se está preguntando a GitHub? y cuándo contestó por última vez
    var npReposLoaded = false
    var npReposBusy = false
    var npReposWhen = Date.distantPast
    @Published var npRepoQuery = ""
    @Published var npRepoNote = ""
    @Published var npFake = false
    @Published var npDomain = ""
    @Published var npUrl = ""
    @Published var npFolder = ""
    @Published var npFolderAuto = true
    @Published var npVersion = ""
    @Published var npDb = ""
    @Published var npFile: String? = nil
    // Formulario «Nuevo proyecto con dominio falseado»
    @Published var newDomain = ""
    @Published var newFolder = ""
    @Published var newDb = ""
    // Ventana: apartado de la barra lateral, proyecto elegido en Proyectos (se ve arriba) y su filtro
    @Published var tab = "proyectos"
    /// Apartado elegido en Configuración (su clave de ToolsView.sections)
    @Published var toolsSection = "parches"
    @Published var selProject: String? = nil
    @Published var projKind = "all"
    // Bases de datos: «solo la versión activa» (la activa se ve desplegada al abrir) y lo que ocupan
    // las copias de ~/lvm-copias ([bytes, ficheros])
    @Published var dbOnlyActive = false
    @Published var backups: [Int64]? = nil
    /// Lo que ocupa cada BBDD («versión|base» → [bytes, cuándo se midió]; gui-bbdd-tamanos)
    @Published var dbSizes: [String: [Int64]] = [:]
    /// Lo que ocupa cada proyecto en el disco: carpeta → [bytes, cuándo se midió]
    @Published var projectSizes: [String: [Int64]] = [:]
    var projSizesBusy = false
    var projSizesAt = Date.distantPast
    // Docker (gui-docker): nil hasta leerlo. Uso de CPU y memoria, vista, filtros y proyectos plegados
    @Published var docker: DockerData? = nil
    @Published var dkStats: DockerStats? = nil
    @Published var dkView = "cont"
    @Published var dkQuery = ""
    @Published var dkOnlyUp = false
    /// El proyecto de Docker desplegado (desde la 1.39.5, plegados al entrar y solo uno a la vez)
    @Published var dkOpen: Set<String> = []
    @Published var dkForm = DockerForm()
    // Ventana encima de la página (Componentes, Instalar versión, Proyecto en Docker)
    @Published var panel: Panel? = nil
    // Tema de la ventana elegido en el menú (nil: el del Mac)
    @Published var dark: Bool? = nil
    /// Correos sin leer en Mailpit (nil: parado o sin saberlo)
    @Published var mailUnread: Int? = nil
    /// Botones del visor de los proyectos (cuáles, en qué orden y cómo)
    @Published var visorConf = loadVisorConf()
    /// Lo que gastan Nexum y sus servicios (cada 3 s; nil hasta la primera lectura)
    @Published var usage: [String: UsagePart]? = nil
    var usageBusy = false
    /// El túnel de Cloudflare abierto, cloudflared (I|instalado|versión|la del programa) y su configuración
    @Published var tunnel: TunnelState? = nil
    @Published var tunnelInfo: [String]? = nil
    /// Lo que tiene un parche nuevo (componentes): nil mientras no se ha mirado
    @Published var components: ComponentsState? = nil
    /// Parches nuevos dejados para luego («Ahora no»): la lista de entonces; el aviso vuelve si cambia
    @Published var updatesIgnored = (try? String(contentsOfFile: IGNORED_UPDATES_FILE, encoding: .utf8)) ?? ""
    /// Los parches nuevos que van en los avisos de arriba (no si se han dejado para luego)
    var updatesPending: ComponentsState? {
        guard let c = components, !c.items.isEmpty, c.items.sorted().joined(separator: "\n") != updatesIgnored else { return nil }
        return c
    }

    func ignoreUpdates(_ c: ComponentsState) {
        let text = c.items.sorted().joined(separator: "\n")
        updatesIgnored = text
        if SIMULATE { return }
        try? FileManager.default.createDirectory(atPath: LOG_DIR, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? text.write(toFile: IGNORED_UPDATES_FILE, atomically: true, encoding: .utf8)
    }
    /// La terminal de abajo: a la vista o no (sigue abierta al esconderla), su alto y la sesión
    @Published var termOpen = false {
        didSet { if termOpen { termStart() } }
    }
    @Published var termHeight: CGFloat = 260
    @Published var termCwd = ""
    let term = TermSession()

    /// La carpeta del proyecto cargado (o la de los proyectos)
    /// Icono en la barra de menús (Configuración, Programa): con él, cerrar la ventana no cierra la aplicación
    @Published var trayOn = trayWanted()
    private var trayTicks = 0

    func setTray(_ on: Bool) {
        try? FileManager.default.createDirectory(atPath: LOG_DIR, withIntermediateDirectories: true)
        do {
            try (on ? "si\n" : "no\n").write(toFile: TRAY_FILE, atomically: true, encoding: .utf8)
        } catch {
            message("No se ha podido guardar", error.localizedDescription, error: true)
            return
        }
        trayOn = on
        TrayIcon.shared.show(on)
    }

    var termProject: String {
        // (gui-proyectos da la carpeta como la tiene el enlace de web.local: su nombre, dentro de los proyectos)
        var cur = projects?.current ?? ""
        if !cur.isEmpty && !cur.hasPrefix("/") { cur = (HTDOCS as NSString).appendingPathComponent(cur) }
        var dir: ObjCBool = false
        return !cur.isEmpty && FileManager.default.fileExists(atPath: cur, isDirectory: &dir) && dir.boolValue ? cur : HTDOCS
    }

    func termStart(restart: Bool = false) {
        if restart { term.stop() }
        guard !term.running else { return }
        let cwd = termProject
        term.onExit = { [weak self] in self?.termOpen = false }
        if term.start(cwd: cwd) {
            termCwd = cwd
        } else {
            termOpen = false
            message("No se ha podido abrir la terminal", "No se ha podido crear su pseudoterminal.", error: true)
        }
    }

    /// cd a la carpeta del proyecto cargado (escrito en la terminal, como si lo tecleara)
    func termCd() {
        let cwd = termProject
        let quoted = "'" + cwd.replacingOccurrences(of: "'", with: "'\\''") + "'"
        term.write(Data("cd \(quoted)\r".utf8))
        termCwd = cwd
    }

    /// Vaciar la caché DNS del sistema (escrito en la terminal: la contraseña de sudo se pide ahí)
    func termFlushDns() {
        term.write(Data("sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder\r".utf8))
    }
    /// Repositorios de GitHub (pestaña Repositorios) y la conexión (Configuración)
    @Published var repos: ReposData? = nil
    /// Proyectos de Node (pestaña Node)
    @Published var nodeItems: [NodeItem]? = nil
    @Published var reposAll = false
    @Published var reposLoading = false
    @Published var github: GitHubState? = nil
    /// Al cargar un proyecto, la página de Proyectos sube hasta el visor (cambia y WidePage se desliza)
    @Published var scrollTop = 0
    private var fastTimer: Timer? = nil
    private var mailPolling = false
    var impFolder: String? = nil
    var dbPwd: [String: String] = [:]
    private var toastWork: DispatchWorkItem? = nil
    private var sized = false
    private var timer: Timer? = nil

    var busy: Bool { return task != nil }

    /// Pliega o despliega un apartado y lo recuerda
    func setFolded(_ key: String, _ fold: Bool) {
        if fold { folded.insert(key) } else { folded.remove(key) }
        try? FileManager.default.createDirectory(atPath: LOG_DIR, withIntermediateDirectories: true)
        try? folded.sorted().map { $0 + "\n" }.joined().write(toFile: FOLDED_FILE, atomically: true, encoding: .utf8)
    }

    init() {
        AppModel.current = self
        reload(branches: true)
        // Los repositorios del buscador de Nuevo proyecto, ya cargados cuando se abra: los de la última
        // vez y, en cuanto la ventana ha cargado lo suyo, los de GitHub
        loadNpRepos(cache: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.loadNpRepos() }
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            // (sin ventana y con el icono de la barra de menús: solo lo que enseña su menú, cada minuto)
            if let self = self, !self.busy, TrayIcon.shared.on,
               !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
                self.trayTicks = (self.trayTicks + 1) % 3
                if self.trayTicks == 0 { runQuick(["gui-datos"]) { rc, out in self.onData(rc, out) } }
                return
            }
            // (con la ventana cerrada, la aplicacion sigue abierta: sin ventana no hace falta leer nada)
            guard let self = self, !self.busy, NSApp.isActive,
                  NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
            // (las cuatro en una sola orden: el script se lee una vez y no cuatro)
            runQuick(["gui-vuelta"]) { rc, out in self.onRound(rc, out) }
            if self.tab == "docker" { self.reloadDocker(stats: true) }
        }
        // (al volver a la ventana, los correos sin leer al momento)
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.pollMail() }
        // Lo que gastan Nexum y sus servicios (arriba) y el túnel abierto: cada 3 s, con la ventana a la vista
        fastTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self = self, NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
            self.usageTick()
        }
        usageTick()
        // Al abrir: si toca (el primer arranque del día y después cada UPDATE_EVERY), si hay una versión
        // nueva del programa (con los datos ya leídos: la versión actual)
        autoCheckUpdates()
    }

    func autoCheckUpdates() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self = self else { return }
            if self.data == nil || self.busy { self.autoCheckUpdates(); return }
            if updateCheckDue() {
                self.checkUpdates(auto: true)
                // (y los parches de los componentes, un poco después: sin juntarse con el aviso del programa)
                DispatchQueue.main.asyncAfter(deadline: .now() + 25) { self.autoCheckComponents() }
            }
        }
    }

    /// Lo que tiene un parche nuevo: cada versión de PHP (PHP, Apache, MariaDB, phpMyAdmin…), las
    /// imágenes de Docker, Mailpit y cloudflared
    func reloadComponents(_ then: ((ComponentsState) -> Void)? = nil) {
        runQuick(["componentes"]) { _, out in
            let c = parseComponents(out)
            self.components = c
            then?(c)
        }
    }

    /// Al abrir (cuando toca buscar una versión nueva del programa): si algo tiene un parche nuevo, se
    /// dice y se ofrece actualizarlo todo
    func autoCheckComponents() {
        reloadComponents { c in
            // (sin preguntar: el aviso de arriba lo dice, y se puede dejar para luego)
            if self.updatesPending != nil { self.toast("Hay parches nuevos: míralos en los avisos de arriba") }
        }
    }

    // MARK: repositorios de GitHub

    func reloadGithub() {
        runQuick(["github"]) { _, out in
            if let g = parseLines(out).first(where: { $0.first == "G" && $0.count >= 6 }) {
                self.github = GitHubState(on: g[1] == "1", login: g[2], source: g[3], account: g[4], prefixes: g[5])
            }
        }
    }

    /// Después de conectar o cambiar algo: lo dice, y la lista de antes ya no vale (otra cuenta o prefijos)
    func githubDone(_ rc: Int32, _ out: String) {
        let lines = out.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        toast(lines.last ?? (rc == 0 ? "Hecho" : "No se ha podido"))
        repos = nil
        reloadGithub()
    }

    func githubToken() {
        let r = runDialog(title: "Conectar con GitHub",
                          text: "Solo para leer la lista de repositorios (también los privados): se clonan por SSH, con tu clave. Créalo en GitHub (Settings, Developer settings, Personal access tokens) con el permiso «repo» (y «read:org» para los de una organización) y pégalo aquí. Se guarda en el Llavero, no en un fichero.",
                          okLabel: "Conectar", hasField: true, placeholder: "ghp_… o github_pat_…", secure: true,
                          validate: { _, t in (t.trimmingCharacters(in: .whitespaces).count >= 20, nil, false) })
        guard r.ok else { return }
        toast("Comprobando el token con GitHub…")
        runQuick(["github-conectar"], input: r.text.trimmingCharacters(in: .whitespaces) + "\n") { rc, out in self.githubDone(rc, out) }
    }

    /// Guardar la cuenta o los prefijos: si no vale, se dice en una ventana y lo escrito se queda
    func githubSet(_ key: String, _ value: String) {
        runQuick(["github", key, value]) { rc, out in
            if rc != 0 {
                let lines = out.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                message("No se ha guardado", lines.last ?? "No se ha podido guardar", error: true)
                return
            }
            self.githubDone(rc, out)
        }
    }

    func reloadNode() {
        runQuick(["gui-node"]) { _, out in
            let items = parseNode(out)
            if items != self.nodeItems { self.nodeItems = items }
        }
    }

    func startNode(_ p: NodeItem, mode: String) {
        runTask("Arrancando \(p.folder)", ["node-arrancar", p.folder, mode], progress: true,
                doneText: "\(p.folder) en marcha", autoClose: true) { _, _, _ in self.reloadNode() }
    }

    /// Túnel: solo se comparte lo compilado (el túnel no deja pasar /node_modules/.vite y así el código
    /// fuente no sale del Mac). Si no lo está, se compila y arranca antes
    func shareNode(_ p: NodeItem) {
        let path = HTDOCS + "/" + p.folder
        if p.running && p.mode == "compilado" {
            share(p.url, folder: path, name: p.folder, live: false)
            return
        }
        if p.running {
            guard confirm("¿Compilar \(p.folder) para compartirlo?",
                          "Está en desarrollo, y lo que se comparte es la versión compilada. Se para y arranca compilado: los cambios ya no se verán al momento.",
                          "Compilar y compartir") else { return }
        }
        runTask("Arrancando \(p.folder)", ["node-arrancar", p.folder, "compilado"], progress: true,
                doneText: "\(p.folder) en marcha", autoClose: true) { ok, _, _ in
            guard ok else {
                self.reloadNode()
                return
            }
            runQuick(["gui-node"]) { _, out in
                let items = parseNode(out)
                self.nodeItems = items
                if let now = items.first(where: { $0.folder == p.folder }), now.running {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.share(now.url, folder: path, name: p.folder, live: false)
                    }
                }
            }
        }
    }

    func stopNode(_ p: NodeItem) {
        runTask("Parando \(p.folder)", ["node-parar", p.folder],
                doneText: "\(p.folder) parado", autoClose: true) { _, _, _ in
            self.reloadNode()
            self.refreshTunnel()
        }
    }

    func reloadRepos(cache: Bool = false) {
        let args = ["repos"] + (reposAll ? ["--todos"] : []) + (cache ? ["--cache"] : [])
        if !cache { reposLoading = true }
        runQuick(args) { _, out in
            if !cache { self.reposLoading = false }
            let r = parseRepos(out)
            if cache && r.head.isEmpty { return }
            if !cache, let e = r.error, !(self.repos?.head ?? []).isEmpty {
                // (sin conexión con GitHub: se queda la lista de la última vez, y se dice)
                self.repos?.error = e
            } else {
                self.repos = r
            }
        }
    }

    /// Clonar (por SSH) o, si ya está clonado, traer sus cambios con git pull, preguntando antes
    func fetchRepo(_ r: RepoItem) {
        var args = ["repo-traer", r.full]
        var title = "Clonando \(r.name)"
        if r.state == "clonado" {
            guard confirm("¿Aplastar \(r.folder) con lo de GitHub?",
                          "Este repositorio ya está clonado en \(HTDOCS)/\(r.folder). Se traen sus cambios de GitHub (git pull) y se juntan con los tuyos. Si chocan con lo que tienes sin subir o sin guardar, no se toca nada y se dice.",
                          "Traer los cambios") else { return }
            args.append("--actualizar")
            title = "Trayendo los cambios de \(r.name)"
        }
        _ = runTask(title, args, doneText: "Hecho", autoClose: true) { ok, _, _ in
            self.reloadRepos(cache: true)
            if ok && r.state != "clonado" { self.toast("\(r.name), en Proyectos") }
        }
    }

    func updateComponents(_ c: ComponentsState) {
        guard confirm("¿Actualizar todo?", "Las versiones de PHP se rehacen con lo último de su rama (varios minutos; la de ahora sigue funcionando mientras se compila). Los contenedores de Docker en marcha se rehacen en unos segundos: sus BBDD y su configuración no cambian.",
                      "Actualizar todo", steps: c.items) else { return }
        components = nil
        _ = runTask("Actualizando los componentes", ["componentes-actualizar"], progress: true,
                    doneText: "Componentes al día", reloadBranches: true) { _, _, _ in self.reloadComponents() }
    }

    func toast(_ text: String) {
        toastText = text
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toastText = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    func reload(branches withBranches: Bool = false) {
        runQuick(["gui-datos"]) { rc, out in self.onData(rc, out) }
        reloadHosts()
        reloadServices()
        reloadProjects()
        reloadDocker()
        reloadDbSizes()
        reloadProjectSizes()
        if withBranches {
            branches = nil
            branchesError = nil
            runQuick(["gui-ramas"]) { rc, out in self.onBranches(rc, out) }
        }
        runQuick(["gui-fechas"]) { _, out in
            var dates: [String: [String]] = [:]
            for f in parseLines(out) where f[0] == "F" && f.count >= 4 { dates[f[1]] = [f[2], f[3]] }
            if !dates.isEmpty && dates != self.phpDates { self.phpDates = dates }
        }
    }

    /// gui-vuelta: cada parte («@@<orden>|<código>» y sus líneas) a lo de siempre
    private func onRound(_ rc: Int32, _ out: String) {
        var parts: [String: (Int32, [String])] = [:]
        var name = ""
        for line in out.components(separatedBy: "\n") {
            if line.hasPrefix("@@gui-"), let bar = line.firstIndex(of: "|") {
                name = String(line[line.index(line.startIndex, offsetBy: 2)..<bar])
                parts[name] = (Int32(line[line.index(after: bar)...]) ?? 1, [])
            } else if !name.isEmpty {
                parts[name]?.1.append(line)
            }
        }
        // (sin ninguna parte, algo ha ido mal antes de empezar: la siguiente vuelta)
        let text = { (key: String) -> (Int32, String)? in
            parts[key].map { ($0.0, $0.1.joined(separator: "\n") + "\n") }
        }
        if let p = text("gui-datos") { onData(p.0, p.1) }
        if let p = text("gui-hosts") { onHosts(p.0, p.1) }
        if let p = text("gui-servicios") { onServices(p.0, p.1) }
        if let p = text("gui-proyectos") { onProjects(p.0, p.1) }
    }

    private func onData(_ rc: Int32, _ out: String) {
        var d = AppData()
        for f in parseLines(out) {
            switch f[0] {
            case "M" where f.count >= 4:
                d.name = f[1]
                d.version = f[2]
                d.signature = f[3]
            case "A" where f.count >= 4:
                d.active = f[1]
                d.running = f[2] == "1"
                d.official = f[3] == "1"
            case "V" where f.count >= 8:
                d.installs.append(Install(folder: f[1], php: f[2], apache: f[3], mariadb: f[4], ftp: f[5],
                                          perl: f[6], pma: f[7],
                                          blocker: f.count > 8 ? f[8...].joined(separator: "|").trimmingCharacters(in: .whitespaces) : ""))
            case "D" where f.count >= 3:
                d.dbs[f[1], default: []].append(f[2])
                if f.count >= 5, let when = Int(f[3]) {
                    d.dbDates[f[1] + "|" + f[2]] = DbDate(when: when, imported: f[4] == "i")
                }
            case "H" where f.count >= 3:
                d.vhosts = f[1]
                d.hosts = f[2]
            case "Z" where f.count >= 2:
                d.stray = f[1...].joined(separator: "|")
            case "N" where f.count >= 2:
                d.exposed = f[1...].joined(separator: "|")
            case "U" where f.count >= 2:
                d.unsecured = f[1].split(separator: " ").map(String.init)
            case "Y" where f.count >= 3:
                d.dbsysVersion = f[1]
                d.dbsysLog = Int64(f[2]) ?? 0
            case "C" where f.count >= 3:
                d.certs.append(CertIssue(domain: f[1], why: f[2]))
            case "W" where f.count >= 2:
                d.cas.append(f[1...].joined(separator: "|"))
            case "G" where f.count >= 2:
                d.untrusted.append(f[1])
            case "Q" where f.count >= 2:
                d.stale.append(f[1])
            case "X" where f.count >= 3:
                d.php2shell[f[1]] = f[2]
            case "T" where f.count >= 2:
                d.barrier = f[1] != "0"
            case "E" where f.count >= 8:
                var m = MailState()
                m.installed = f[1] == "1"
                m.on = f[2] == "1"
                m.wp = f[3]
                m.running = f[4] == "1"
                m.version = f[5]
                m.url = f[6].hasPrefix("http://127.0.0.1:") ? f[6] : "http://127.0.0.1:8025/"
                m.offer = f[7]
                d.mail = m
            case "O" where f.count >= 3:
                d.copies[f[1]] = Int(f[2]) ?? 0
            case "R" where f.count >= 2:
                d.asides.append(f[1])
            default:
                break
            }
        }
        if rc != 0 && d.installs.isEmpty && d.version.isEmpty {
            loadError = String(out.suffix(600))
            return
        }
        loadError = nil
        if impFolder != d.active {
            impFolder = d.active
            impDb = nil
        }
        if let db = impDb, !(d.dbs[d.active] ?? []).contains(db) { impDb = nil }
        if d != data { data = d }
        // (los correos sin leer, solo con Mailpit en marcha)
        pollMail()
        if !sized {
            sized = true
            DispatchQueue.main.async { self.fitWindow(installs: d.installs.count) }
        }
    }

    /// Alto para que la pestaña Bases de datos se vea entera sin agrandar la ventana (sin pasar del
    /// alto de la pantalla). SwiftUI de macOS 12 no deja fijar el tamaño inicial: se agranda al llegar
    /// los datos, con una estimación por número de versiones (cabecera, buscador, carga y una fila por versión)
    func fitWindow(installs n: Int) {
        guard let w = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }),
              let screen = w.screen ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let want = CGFloat(720 + 57 * max(n, 1))
        let h = min(max(w.frame.height, want), area.height)
        guard h > w.frame.height + 1 else { return }
        var f = w.frame
        f.origin.y -= h - f.height
        f.size.height = h
        if f.minY < area.minY { f.origin.y = area.minY }
        w.setFrame(f, display: true, animate: false)
    }

    private func onBranches(_ rc: Int32, _ out: String) {
        let rows = parseLines(out)
        if let err = rows.first(where: { $0[0] == "ERROR" }) {
            branchesError = field(err, 1)
            return
        }
        // De la rama mas nueva a la mas antigua. Si php.net no dio el estado de la rama, se deduce de
        // la lista de ramas con soporte
        let list = rows.filter { $0[0] == "B" && $0.count >= 7 }.map { f -> Branch in
            let st = field(f, 7)
            return Branch(branch: f[1], latest: f[2], supported: f[3] == "1", mariadb: f[4], perl: f[5], state: f[6],
                          phpState: st.isEmpty ? (f[3] == "1" ? "stable" : "eol") : st,
                          activeEnd: field(f, 8), securityEnd: field(f, 9),
                          date: field(f, 10) == "-" ? "" : field(f, 10), security: field(f, 11) == "1")
        }.sorted { a, b in
            a.branch.compare(b.branch, options: .numeric) == .orderedDescending
        }
        if rc != 0 && list.isEmpty {
            branchesError = out.trimmingCharacters(in: .whitespacesAndNewlines).suffix(400).description
            return
        }
        branches = list
        selected = selected.filter { b in list.contains(where: { $0.branch == b && $0.state == "nueva" }) }
    }

    // MARK: actualizaciones

    /// Busca una versión nueva: en GitHub (firmada; se instala desde aquí y la ventana se vuelve a
    /// abrir) o, si no se puede, un .dmg más nuevo en Descargas (se abre para ejecutar su instalador)
    /// Buscar una versión nueva (menú) o, con auto, al abrir la ventana (updateCheckDue): sin avisar si
    /// no hay y solo la firmada de GitHub. Si se dice que no, se vuelve a ofrecer la próxima vez que toque
    func checkUpdates(auto: Bool = false) {
        if !auto { toast("Buscando actualizaciones…") }
        runQuick(["gui-paquete"]) { _, out in
            let current = self.data?.version ?? ""
            let lines = parseLines(out)
            let notes = lines.filter { $0[0] == "I" && $0.count >= 2 }.map { $0[1...].joined(separator: "|") }
            if let u = lines.first(where: { $0[0] == "U" && $0.count >= 5 }) {
                let path = u[4...].joined(separator: "|")
                guard confirm("Hay una versión nueva de Nexum Dev Stack",
                              "Tienes la \(current); en GitHub está la \(u[1]) (\(u[2])), firmada por quien hace el programa. Huella SHA-256:\n\(u[3])\n\nSe cambia el gestor y la ventana se vuelve a abrir. Tus versiones de PHP, proyectos y BBDD no se tocan.",
                              "Actualizar a la \(u[1])") else { return }
                self.runTask("Actualizando Nexum Dev Stack a la \(u[1])", ["actualizar-gestor", path], progress: true,
                             doneText: "Instalada la \(u[1])", autoClose: true) { ok, _, _ in
                    if !ok { self.toast("No se ha actualizado"); return }
                    if !SIMULATE { relaunchApp() }
                }
                return
            }
            // (al abrir, solo la firmada de GitHub: la de Descargas, sin firma, solo desde el menú)
            if auto { return }
            guard let f = lines.first(where: { $0[0] == "N" && $0.count >= 5 }) else {
                if notes.isEmpty {
                    self.toast("Tienes la última versión (\(current))")
                } else {
                    message("No hay ninguna versión nueva para instalar desde aquí",
                            "Tienes la \(current).\n\n" + notes.joined(separator: "\n\n"))
                }
                return
            }
            let path = f[4...].joined(separator: "|")
            let origin = lines.first(where: { $0[0] == "O" && $0.count >= 2 })
                .map { $0[1...].joined(separator: "|") } ?? "desconocido"
            guard confirm("Hay una versión nueva de Nexum Dev Stack en Descargas",
                          "Tienes la \(current); en Descargas está la \(f[1]) (\((path as NSString).lastPathComponent), del \(f[2]), de \(origin)).\n\nNo lleva firma: ábrela solo si te la ha pasado quien hace el programa y su huella SHA-256 es esta:\n\(f[3])\n\nSe abre el .dmg para ejecutar su instalador. Tus versiones de PHP, proyectos y BBDD no se tocan.",
                          "Abrir el instalador") else { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    // MARK: cargar un proyecto (Versiones)

    func reloadProjects() {
        runQuick(["gui-proyectos"]) { rc, out in self.onProjects(rc, out) }
    }

    func onProjects(_ rc: Int32, _ out: String) {
        var p = ProjectsData()
        for f in parseLines(out) {
            switch f[0] {
            case "E" where f.count >= 3:
                p.link = f[1]
                p.current = f[2]
                p.create = f.count >= 4 && f[3] == "N"
            case "P" where f.count >= 4:
                p.list.append(Project(name: f[1], db: f[2], php: f[3], kind: field(f, 4)))
            case "R" where f.count >= 3:
                p.saved[f[1]] = f[2...].joined(separator: "|")
            case "V" where f.count >= 4:
                p.vlinks[f[1] + "@" + f[2]] = f[3...].joined(separator: "|")
            default:
                break
            }
        }
        let next: ProjectsData? = (rc != 0 && p.list.isEmpty) ? nil : p
        if next != projects { projects = next }
    }

    /// Carpeta vinculada a una BBDD en una versión: la de esa versión ("" = ninguna), la de todas
    /// las versiones (como se guardaba hasta la 1.36) o nil si no tiene
    func linkOf(_ db: String, _ ver: String) -> String? {
        let p = projects ?? ProjectsData()
        if let v = p.vlinks[db + "@" + ver] { return v }
        return p.saved[db]
    }

    /// (versión, BBDD) de un proyecto: las BBDD vinculadas a su carpeta en cada versión o, si no
    /// tiene ninguna, la de su configuración en las versiones donde no es de otro proyecto
    func projectPairs(_ x: Project) -> [(Install, String)] {
        let d = data ?? AppData()
        var pairs: [(Install, String)] = []
        for i in d.installs {
            for db in d.dbs[i.folder] ?? [] where linkOf(db, i.folder) == x.name { pairs.append((i, db)) }
        }
        if !pairs.isEmpty || x.db.isEmpty { return pairs }
        return d.installs.filter { (d.dbs[$0.folder] ?? []).contains(x.db) && linkOf(x.db, $0.folder) == nil }
            .map { ($0, x.db) }
    }

    /// Proyecto cargado (al que apunta el vhost), o nil
    func loadedEntry() -> Project? {
        guard let p = projects, !p.current.isEmpty else { return nil }
        let name = (p.current as NSString).lastPathComponent
        return p.list.first { $0.name == name }
    }

    /// BBDD que usa el proyecto cargado en la versión activa (vacío si no hay)
    func loadedProjectDb() -> String {
        guard let x = loadedEntry() else { return "" }
        return cleanDbName(loadedDb(x))
    }

    /// BBDD del proyecto en la versión activa (la vinculada o la de su configuración)
    func loadedDb(_ x: Project) -> String {
        let pairs = projectPairs(x)
        if let p = pairs.first(where: { $0.0.folder == data?.active }) { return p.1 }
        return pairs.first?.1 ?? projectBase(x)
    }

    /// Base de un proyecto que no está en ninguna versión (para los textos): la recordada para su
    /// carpeta o la de su configuración
    func projectBase(_ x: Project) -> String {
        if let first = projectPairs(x).first { return first.1 }
        let d = data ?? AppData()
        let all = Set(d.installs.flatMap { d.dbs[$0.folder] ?? [] })
        let saved = (projects?.saved ?? [:]).filter { $0.value == x.name }.map { $0.key }.sorted()
        if let s = saved.first(where: { all.contains($0) }) { return s }
        return x.db.isEmpty ? (saved.first ?? "") : x.db
    }

    /// Carga la carpeta de un proyecto en la versión donde está su base. Si está en varias (o en
    /// ninguna), pregunta cuál montar
    func loadFolder(_ x: Project) {
        guard let p = projects, !p.link.isEmpty else {
            message("No hay un vhost para cargar proyectos",
                    "Ningún vhost compartido tiene como DocumentRoot un enlace de htdocs (como web.local).",
                    error: true)
            return
        }
        let d = data ?? AppData()
        var db = projectBase(x)
        var cands = projectPairs(x)
        let found = !cands.isEmpty
        if cands.isEmpty { cands = d.installs.map { ($0, db) } }
        guard !cands.isEmpty else {
            message("No hay ninguna versión instalada", "Instala una versión de PHP en Versiones de PHP para cargar proyectos.", error: true)
            return
        }
        var inst = cands[0].0
        db = cands[0].1
        if cands.count > 1 {
            guard let chosen = askVersion(x, db, cands, found) else { return }
            inst = chosen.0
            db = chosen.1
        }
        let req = ProjectRequest(db: db, inst: inst, link: p.link, current: p.current, create: p.create,
                                 projects: p.list, saved: p.saved)
        loadProject(req, folder: x.name, version: inst.folder, manual: false, confirmSwitch: cands.count == 1)
    }

    /// Versión de PHP (y su BBDD) en la que se carga un proyecto, cuando puede ir en varias (nil si
    /// se cancela)
    func askVersion(_ x: Project, _ db: String, _ cands: [(Install, String)], _ found: Bool) -> (Install, String)? {
        let active = data?.active ?? ""
        let pre = cands.firstIndex(where: { $0.0.folder == active })
            ?? cands.firstIndex(where: { !x.php.isEmpty && $0.0.php.hasPrefix(x.php) }) ?? 0
        let alert = NSAlert()
        alert.messageText = found ? "¿Qué versión del proyecto y de PHP quieres?"
            : "¿Con qué versión de PHP quieres cargar el proyecto?"
        let why: String
        if found {
            why = "\(x.name) tiene BBDD en \(cands.count) versiones de PHP, cada una con su copia. Elige cuál cargar:"
        } else if !db.isEmpty {
            why = "Su BBDD (\(db)) no está en ninguna versión: súbela después en Bases de datos. Elige la versión de PHP:"
        } else {
            why = "No se sabe qué BBDD usa \(x.name). Elige la versión de PHP:"
        }
        alert.addButton(withTitle: "Cargar proyecto")
        alert.addButton(withTitle: "Cancelar")
        // Una opción por versión; con la base en varias, la fecha de cada copia debajo
        let group = RadioGroup()
        var views: [NSView] = [dialogLabel(why, color: .secondaryLabelColor)]
        var options: [NSView] = []
        for (n, c) in cands.enumerated() {
            let i = c.0, cdb = c.1
            var notes: [String] = []
            if found { notes.append("BBDD \(cdb)") }
            if i.folder == active { notes.append("la activa") }
            if !x.php.isEmpty && i.php.hasPrefix(x.php) { notes.append("la de su .php-version") }
            let title = "PHP \(i.php)  (XAMPP-\(i.folder))" + (notes.isEmpty ? "" : "  ·  " + notes.joined(separator: ", "))
            let b = NSButton(radioButtonWithTitle: title, target: group, action: #selector(RadioGroup.pick(_:)))
            b.state = n == pre ? .on : .off
            group.buttons.append(b)
            let option = NSStackView()
            option.orientation = .vertical
            option.alignment = .leading
            option.spacing = 3
            option.addArrangedSubview(b)
            if found {
                let when = dbDateText(data?.dbDates[i.folder + "|" + cdb]) ?? "sin fecha"
                let sub = NSTextField(labelWithString: "BBDD: " + when)
                sub.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                sub.textColor = .secondaryLabelColor
                // alineado con el texto del botón, no con el círculo
                let indent = NSStackView(views: [sub])
                indent.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)
                option.addArrangedSubview(indent)
            }
            options.append(option)
        }
        views.append(dialogOptions(options, spacing: 14))
        alert.accessoryView = dialogStack(views, spacing: 14)
        guard alert.runStyled() == .alertFirstButtonReturn else { return nil }
        let chosen = group.buttons.firstIndex(where: { $0.state == .on }) ?? pre
        return cands[chosen]
    }

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

    /// Arranca, para o reinicia un servicio de la versión montada (lvm-instalador servicio ...)
    func service(_ name: String, _ cmd: String, _ title: String) {
        let verbs = ["arrancar": ("Arrancando", "arrancado"), "parar": ("Parando", "parado"),
                     "reiniciar": ("Reiniciando", "reiniciado")]
        let v = verbs[cmd] ?? ("", "")
        runTask("\(v.0) \(title)", ["servicio", name, cmd], doneText: "\(title) \(v.1)", autoClose: true)
    }

    /// Deja la versión montada solo para este Mac y la reinicia (lvm-instalador asegurar)
    func secure() {
        runTask("Cerrando a la red", ["asegurar"], doneText: "Solo se puede entrar desde este Mac", autoClose: true)
    }

    /// phpMyAdmin más nuevo que admite el PHP de una versión ("--todas": todas las que lo necesiten)
    func updatePma(_ folder: String) {
        runTask("Actualizando phpMyAdmin", ["actualizar-phpmyadmin", folder], progress: true,
                doneText: "phpMyAdmin actualizado", autoClose: true)
    }

    /// Certificados propios para los proyectos https y sin la CA local (lvm-instalador arreglar-certificados)
    func fixCerts() {
        runTask("Arreglando los certificados", ["arreglar-certificados"], doneText: "Certificados arreglados")
    }

    /// Que el navegador acepte el certificado propio de cada proyecto https (lvm-instalador confiar-certificados)
    func trustCerts() {
        runTask("Confiando en los certificados de los proyectos", ["confiar-certificados"],
                doneText: "El navegador acepta los certificados de los proyectos")
    }

    /// Que deje de aceptar los de las tiendas que ya no están falseadas (confiar-certificados --quitar)
    func untrustCerts() {
        runTask("Quitando los certificados de las webs reales", ["confiar-certificados", "--quitar"],
                doneText: "El navegador ya no acepta esos certificados")
    }

    /// Todas las versiones solo para este Mac (lvm-instalador asegurar --todas)
    func secureAll() {
        runTask("Protegiendo las versiones", ["asegurar", "--todas"],
                doneText: "Todas las versiones son solo para este Mac", autoClose: true)
    }

    func repairDbSystem() {
        runTask("Reparando las tablas del sistema de MariaDB", ["reparar-bd-sistema"],
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
            showLongText("Comandos de lvm-instalador", out, subtitle: "En la terminal: lvm-instalador --ayuda",
                         commands: true)
        }
    }

    // MARK: acciones

    @discardableResult
    func runTask(_ title: String, _ args: [String], progress: Bool = false, doneText: String = "Terminado",
                 autoClose: Bool = false, env: [String: String] = [:],
                 cancelText: (String, String, String)? = nil, reloadBranches: Bool = false,
                 onDone: ((Bool, TaskRunner, InstallProgress?) -> Void)? = nil) -> TaskRunner {
        // (otra tarea en segundo plano: no van dos a la vez, que tocarían lo mismo)
        if let cur = task, !cur.finished {
            taskHidden = false
            toast("Hay una tarea en marcha: espera a que acabe")
            return cur
        }
        // (la ventana que hubiera encima de la página se cierra: la tarea va en su hoja)
        panel = nil
        taskHidden = false
        let t = TaskRunner(title: title, args: args, withProgress: progress, doneText: doneText,
                           autoClose: autoClose, env: env, cancelText: cancelText)
        t.model = self
        t.onDone = { [weak self] ok, task, p in
            onDone?(ok, task, p)
            self?.reload(branches: reloadBranches)
        }
        task = t
        t.start()
        return t
    }

    func control(_ cmd: String, _ what: String) {
        let folder = data?.active ?? ""
        if cmd == "parar" {
            // Parar = lvm disable: para y quita el enlace /Applications/XAMPP (php deja de responder)
            runTask("Parando y desactivando XAMPP-\(folder)", ["disable"],
                    doneText: "XAMPP-\(folder) parada y desactivada", autoClose: true)
            return
        }
        let texts = ["arrancar": "Versión activa arrancada", "reiniciar": "Versión activa reiniciada"]
        runTask("\(what) XAMPP-\(folder)", [cmd], doneText: texts[cmd] ?? "Terminado", autoClose: true)
    }

    func activate(_ folder: String) {
        // Una versión vulnerable a PHP2Shell, solo si se confirma
        let st = data?.php2shell[folder] ?? "ok"
        if php2shellVulnerable(st) {
            let php = data?.installs.first(where: { $0.folder == folder })?.php ?? folder
            if !runDialog(title: "PHP \(php) es vulnerable (PHP2Shell)", text: php2shellText(st, php),
                          okLabel: "Activar XAMPP-\(folder) igualmente", style: .warning, destructive: true).ok { return }
        }
        runTask("Activando XAMPP-\(folder)", ["use", folder], doneText: "XAMPP-\(folder) activada", autoClose: true)
    }

    /// Actualizar una XAMPP-X.Y.Z al último parche de su rama: se instala a su lado (la de ahora no se
    /// toca) y, al terminar, un botón le pasa sus BBDD con sus vínculos y la activa si esta era la activa
    func upgradePinned(_ inst: Install, _ newPhp: String) {
        let branch = shortPhp(newPhp)
        guard confirm("¿Actualizar a PHP \(newPhp)?",
                      "Se instala XAMPP-\(newPhp) a su lado (20-40 min); XAMPP-\(inst.folder) no se toca. Al terminar, «Pasar las BBDD» le copia sus BBDD con sus vínculos y la activa si esta era la activa. Pide la contraseña de administrador.",
                      "Instalar PHP \(newPhp)") else { return }
        runTask("Instalando PHP \(newPhp)", ["instalar", "--php", branch, "--si"], progress: true,
                doneText: "XAMPP-\(newPhp) instalada", reloadBranches: true) { [weak self] ok, task, _ in
            guard let self = self, ok, !SIMULATE else { return }
            task.offer("Pasar las BBDD a XAMPP-\(newPhp)") {
                self.task = nil
                self.moveToVersion(inst.folder, newPhp)
            }
        }
    }

    /// Las BBDD de una versión, con sus vínculos, a otra (pasar-version); la activa si era la activa
    func moveToVersion(_ from: String, _ to: String) {
        runTask("Pasando las BBDD de XAMPP-\(from) a XAMPP-\(to)", ["pasar-version", from, to],
                doneText: "BBDD en XAMPP-\(to). Cuando compruebes que va bien, desinstala XAMPP-\(from)", env: dbEnv())
    }

    /// Barrera entre webs (Configuración): pone o quita en todas las versiones el bloqueo de lo que
    /// mandan otras webs a los proyectos
    func setBarrier(_ on: Bool) {
        guard let d = data, d.barrier != on, !busy else { return }
        if !on && !confirm("¿Apagar la barrera entre webs?",
                           "Otras webs podrán volver a mandar formularios y peticiones a tus proyectos (como la vuelta de una pasarela de pago). Se aplica a todas las versiones y se recarga Apache. Pide la contraseña de administrador.",
                           "Apagar la barrera", destructive: true) { return }
        runTask(on ? "Poniendo la barrera entre webs" : "Apagando la barrera entre webs", ["barrera-web", on ? "si" : "no"],
                doneText: on ? "Barrera entre webs puesta" : "Barrera entre webs apagada", autoClose: true)
    }

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

    /// El visor de la bandeja, siempre el mismo: al cambiar de apartado no se pierde el correo abierto
    lazy var mailWeb = MailWebHost()

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
                    "/Applications/XAMPP tiene que ser un enlace a la versión activa. Sin borrar nada, se para, se copian sus BBDD (.zip, a ~/lvm-copias), sus proyectos y sus vhosts, y se mueve a /Applications/XAMPP-oficial-<fecha>.\n\nDespués, carga sus BBDD en Configuración (ahí también puedes volver a él). Pide la contraseña de administrador.",
                    "Apartar el XAMPP oficial") { return }
        runTask("Apartando el XAMPP oficial", ["apartar"], doneText: "XAMPP oficial apartado. Sus BBDD están copiadas en ~/lvm-copias")
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
                // (si la rama de MariaDB cambia, sus BBDD no se pueden conservar: se guardan en ~/lvm-copias)
                var keep = "Sus BBDD, proyectos y vhosts se conservan."
                if let i = inst, let b = self.branch(i.php), !b.mariadb.isEmpty, !i.mariadb.hasPrefix(b.mariadb + ".") {
                    keep = "MariaDB pasa de la \(shortPhp(i.mariadb)) a la \(b.mariadb): sus BBDD se guardan en ~/lvm-copias y empieza vacía. Proyectos y vhosts se conservan."
                }
                if !confirm(patch ? "¿Poner el parche de seguridad a XAMPP-\(folder)?" : "¿Actualizar XAMPP-\(folder)?",
                            (patch ? "Se vuelve a compilar PHP \(field(res, 1)) con el parche oficial contra PHP2Shell (\(PHP2SHELL_DATE)), y su pila con los últimos parches (unos minutos). "
                                   : "Se vuelve a compilar con PHP \(field(res, 1)) y los últimos parches de su pila (unos minutos). ")
                            + keep + " Pide la contraseña de administrador.",
                            patch ? "Poner el parche" : "Actualizar a PHP \(field(res, 1))") { return }
                self.runTask("Actualizando XAMPP-\(folder)", ["actualizar", folder], progress: true,
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
                              checkbox: "Guardar antes una copia de sus BBDD en ~/lvm-copias", checked: true,
                              hasField: true,
                              fieldLabel: "Sin copia, las BBDD no se podrán recuperar. Escribe \(folder) para confirmar:",
                              validate: { checked, typed in (checked || typed.trimmingCharacters(in: .whitespaces) == folder, nil, false) })
            if !r.ok { return }
            copy = r.checked
        }
        expanded.remove(folder)
        runTask("Desinstalando XAMPP-\(folder)", ["desinstalar", folder] + (copy ? ["--copia"] : []),
                doneText: "XAMPP-\(folder) desinstalada" + (copy ? " (copia en ~/lvm-copias)" : ""),
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

    // MARK: bases de datos (siempre en la version activa)

    func dbEnv() -> [String: String] {
        if let d = data, let pwd = dbPwd[d.active] { return ["MYSQL_PWD": pwd] }
        return [:]
    }

    /// Comprueba que se puede entrar en el MariaDB activo; si root tiene contraseña la pide
    func checkDbAccess(_ then: @escaping () -> Void) {
        guard let d = data else { return }
        let folder = d.active
        runQuick(["gui-bd-comprobar"], env: dbEnv()) { _, out in
            let last = out.components(separatedBy: "\n").filter { !$0.isEmpty }.last ?? "no|Sin respuesta del instalador"
            let res = last.components(separatedBy: "|")
            switch res[0] {
            case "ok":
                then()
            case "clave":
                let retry = self.dbPwd[folder] != nil
                let r = runDialog(title: "Contraseña de MariaDB",
                                  text: "root del MariaDB de XAMPP-\(folder) tiene contraseña: escríbela para seguir."
                                      + (retry ? "\n\nContraseña incorrecta. Vuelve a intentarlo." : ""),
                                  okLabel: "Entrar en MariaDB", hasField: true, secure: true)
                if r.ok {
                    self.dbPwd[folder] = r.text
                    self.checkDbAccess(then)
                }
            default:
                message("No se puede usar la BBDD", res.dropFirst().joined(separator: "|"), error: true)
            }
        }
    }

    func createDb() {
        checkDbAccess { self.askNewDb() }
    }

    private func askNewDb() {
        guard let d = data else { return }
        let existing = d.dbs[d.active] ?? []
        let hint = "Letras sin acentos, números, _ y -"
        let r = runDialog(title: "Crear BBDD",
                          text: "Se crea vacía en XAMPP-\(d.active) (utf8mb4_general_ci).",
                          okLabel: "Crear la BBDD", hasField: true, fieldLabel: hint, placeholder: "nombre_de_la_base",
                          validate: { _, typed in
                              let name = typed.trimmingCharacters(in: .whitespaces)
                              if existing.contains(name) || SYSTEM_DBS.contains(name.lowercased()) {
                                  return (false, "Ya hay una BBDD con ese nombre.", true)
                              }
                              let valid = validDbName(name)
                              return (valid, hint, !valid && !name.isEmpty)
                          })
        if !r.ok { return }
        let name = r.text
        runQuick(["crear-bd", name], env: dbEnv()) { rc, out in
            if rc == 0 {
                self.impDb = name
                self.toast("BBDD «\(name)» creada")
                self.reload()
            } else {
                message("No se ha podido crear la BBDD", String(out.suffix(600)), error: true)
            }
        }
    }

    func dropDb(_ db: String) {
        checkDbAccess {
            runQuick(["gui-bd-info", db], env: self.dbEnv()) { rc, out in
                guard rc == 0, let info = parseLines(out).first(where: { $0[0] == "I" && $0.count >= 3 }) else {
                    message("No se puede borrar la BBDD", String(out.suffix(600)), error: true)
                    return
                }
                self.confirmDrop(db, Int(info[1]) ?? 0, Int64(info[2]) ?? 0)
            }
        }
    }

    private func confirmDrop(_ db: String, _ tables: Int, _ size: Int64) {
        let folder = data?.active ?? ""
        var copy = false
        if tables > 0 {
            let r = runDialog(title: "¿Borrar la BBDD «\(db)»?",
                              text: "Está en XAMPP-\(folder) y tiene \(plural(tables, "tabla", "tablas")) (\(fmtSize(size))). Se borra todo su contenido y no se puede deshacer.",
                              okLabel: "Borrar la BBDD", style: .critical, destructive: true,
                              checkbox: "Guardar antes una copia en ~/lvm-copias (se puede volver a cargar)", checked: true,
                              hasField: true,
                              fieldLabel: "Sin copia, el contenido no se podrá recuperar. Escribe \(db) para confirmar:",
                              validate: { checked, typed in (checked || typed.trimmingCharacters(in: .whitespaces) == db, nil, false) })
            if !r.ok { return }
            copy = r.checked
        } else {
            if !confirm("¿Borrar la BBDD «\(db)»?",
                        "Está en XAMPP-\(folder) y está vacía (sin tablas). No se puede deshacer.",
                        "Borrar la BBDD", destructive: true) { return }
        }
        runTask("Borrando la BBDD \(db)", ["borrar-bd", db] + (copy ? ["--copia"] : []),
                doneText: "BBDD «\(db)» borrada" + (copy ? " (copia en ~/lvm-copias)" : ""),
                autoClose: true, env: dbEnv()) { ok, _, _ in
            if ok && self.impDb == db {
                self.impDb = nil
            }
        }
    }

    func pickSql() {
        let panel = NSOpenPanel()
        panel.title = "Elegir el fichero SQL"
        panel.prompt = "Elegir"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = fileTypes(["sql", "gz", "zip"])
        if let f = impFile {
            panel.directoryURL = URL(fileURLWithPath: f).deletingLastPathComponent()
        } else {
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        }
        if panel.runModal() != .OK { return }
        guard let url = panel.url else { return }
        impFile = url.path
        // Si hay una base que se llama como el fichero (mi_web.sql -> mi_web), se propone
        var stem = url.lastPathComponent
        for ext in [".zip", ".ZIP", ".gz", ".GZ", ".sql", ".SQL"] where stem.hasSuffix(ext) { stem = String(stem.dropLast(ext.count)) }
        if impDb == nil, let d = data, (d.dbs[d.active] ?? []).contains(stem) { impDb = stem }
    }

    /// Carpetas de htdocs para el formulario y, si se sabe, la del proyecto de la base elegida (la
    /// recordada o la única cuya configuración la usa)
    func refreshImpProjects() {
        let db = impDb
        runQuick(["gui-proyectos"]) { rc, out in
            var names: [String] = []
            var kind: [String: String] = [:]
            var users: [String] = []
            var saved: String? = nil
            for f in parseLines(out) {
                if f[0] == "P" && f.count >= 4 {
                    names.append(f[1])
                    if f.count >= 5 && !f[4].isEmpty { kind[f[1]] = f[4] }
                    if let d = db, f[2] == d { users.append(f[1]) }
                } else if f[0] == "R" && f.count >= 3, let d = db, f[1] == d {
                    saved = f[2]
                }
            }
            guard rc == 0 else { return }
            self.impProjects = names
            self.impKind = kind
            if let s = saved, names.contains(s) {
                self.impProject = s
            } else if users.count == 1 {
                self.impProject = users[0]
            } else if let d = db, let m = self.nameMatchProject(d, names, kind) {
                self.impProject = m
            } else if let p = self.impProject, !names.contains(p) {
                self.impProject = nil
            }
        }
    }

    /// Carpeta que se llama como la base: wp_ajoselpajizo → dob-wordpress-ajoselpajizo (la base sin
    /// wp_ ni ps_, al final del nombre). Si hay varias, la del mismo tipo (WordPress o tienda)
    func nameMatchProject(_ db: String, _ folders: [String], _ kind: [String: String]) -> String? {
        let low = db.lowercased()
        let pre = String(low.prefix(3))
        var tails: Set<String> = [low]
        if (pre == "wp_" || pre == "ps_") && low.count > 3 { tails.insert(String(low.dropFirst(3))) }
        var hits = folders.filter { f in
            let n = f.lowercased()
            return tails.contains { v in n == v || n.hasSuffix("-" + v) || n.hasSuffix("." + v) || n.hasSuffix("_" + v) }
        }
        if hits.count > 1 && (pre == "wp_" || pre == "ps_") {
            let same = hits.filter { kind[$0] == String(pre.prefix(2)) }
            if !same.isEmpty { hits = same }
        }
        return hits.count == 1 ? hits[0] : nil
    }

    /// Ancho del desplegable de Proyecto: el del nombre más largo, para verlo entero al elegirlo
    func importProjectWidth() -> CGFloat {
        let longest = impProjects.map { $0.count }.max() ?? 0
        return max(230, min(440, CGFloat(longest) * 7.5 + 50))
    }

    func importProjectHint() -> String {
        guard let p = impProject else { return "Opcional: si es la BBDD nueva de un proyecto, elige su carpeta." }
        if let what = projectConfigText(p) { return what.prefix(1).uppercased() + String(what.dropFirst()) + "." }
        return "La BBDD queda asociada a esta carpeta (Cargar proyecto la usa)."
    }

    /// Lo que se hace con la configuración del proyecto al subirle una base nueva
    func projectConfigText(_ folder: String) -> String? {
        switch impKind[folder] {
        case "wp": return "su wp-config.php se rehace con la plantilla de este equipo para usar esta BBDD"
        case "ps": return "su parameters.php (o settings.inc.php) pasa a usar esta BBDD y se vacía su caché"
        default: return nil
        }
    }

    func importHint() -> String? {
        guard let d = data else { return nil }
        if !d.running { return "La versión activa está parada: arráncala con el botón de arriba (Parados)." }
        if impFile == nil { return "Elige el fichero SQL." }
        if impDb == nil { return "Elige la BBDD de destino o crea una con +." }
        return nil
    }

    func importDb() {
        guard let d = data, let path = impFile, let db = impDb else { return }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber else {
            message("No se encuentra el fichero", path, error: true)
            return
        }
        let name = (path as NSString).lastPathComponent
        var text = "Se carga en XAMPP-\(d.active). Antes se BORRAN todas las tablas de «\(db)» (si tiene alguna, con una copia en ~/lvm-copias)."
        let project = impProject
        if let p = project {
            text += "\n\nDespués, «\(db)» pasa a ser la BBDD de \(p)" + (projectConfigText(p).map { ": \($0)" } ?? "") + "."
        }
        if !confirm("¿Cargar \(name) (\(fmtSize(size.int64Value))) en \(db)?", text,
                    "Vaciar y cargar", destructive: true) { return }
        checkDbAccess {
            self.runTask("Cargando \(name) en \(db)",
                         ["importar-bd", path, db] + (project.map { ["--proyecto", $0] } ?? []),
                         progress: true, doneText: "BBDD «\(db)» cargada" + (project.map { " en \($0)" } ?? ""),
                         env: self.dbEnv(),
                         cancelText: ("¿Cancelar la carga?",
                                      "«\(db)» se queda a medias, con lo cargado hasta ahora.",
                                      "Cancelar la carga")) { ok, _, _ in
                if ok {
                    self.impFile = nil
                }
            }
        }
    }

    // MARK: menu

    // MARK: cargar el proyecto de una base

    func openProject(_ db: String, _ inst: Install) {
        runQuick(["gui-proyectos"]) { rc, out in
            var link = "", current = ""
            var create = false
            var projects: [Project] = []
            var saved: [String: String] = [:]
            for f in parseLines(out) {
                switch f[0] {
                case "E" where f.count >= 3:
                    link = f[1]
                    current = f[2]
                    create = f.count >= 4 && f[3] == "N"
                case "P" where f.count >= 4:
                    projects.append(Project(name: f[1], db: f[2], php: f[3]))
                case "R" where f.count >= 3:
                    saved[f[1]] = f[2]
                case "V" where f.count >= 4 && f[1] == db && f[2] == inst.folder:
                    // (el vínculo de la versión manda sobre el de todas; "" = desvinculada en ella.
                    // gui-proyectos saca las V después de las R)
                    saved[db] = f[3...].joined(separator: "|")
                default:
                    break
                }
            }
            if rc != 0 || projects.isEmpty {
                message("No se han podido leer los proyectos",
                        "No se ha podido leer la carpeta \(HTDOCS).", error: true)
            } else if link.isEmpty {
                message("No hay un vhost para cargar proyectos",
                        "Ningún vhost compartido tiene como DocumentRoot un enlace de htdocs (como web.local).",
                        error: true)
            } else {
                let req = ProjectRequest(db: db, inst: inst, link: link, current: current, create: create,
                                         projects: projects, saved: saved)
                let matches = projects.filter { $0.db == db }.map { $0.name }
                // Carpeta conocida (elegida antes o la unica que usa la base): se carga sin preguntar
                if let s = saved[db], projects.contains(where: { $0.name == s }) {
                    self.loadProject(req, folder: s, version: inst.folder, manual: false)
                } else if matches.count == 1 && saved[db] != "" {
                    self.loadProject(req, folder: matches[0], version: inst.folder, manual: false)
                } else {
                    self.projectReq = req
                }
            }
        }
    }

    /// Guarda en ~/.lvm-instalador/proyectos la carpeta elegida a mano para una base en una versión
    func rememberProject(_ db: String, _ folder: String, _ version: String) {
        if SIMULATE { return }
        if let err = writeLinks([(db, version, folder)]) {
            toast("No se ha podido recordar la carpeta: \(err)")
        }
    }

    /// Elige con qué BBDD va la carpeta en cada versión (o con ninguna): Cargar proyecto monta la
    /// versión con esa BBDD. Cada BBDD es de un solo proyecto en cada versión
    func linkProject(_ x: Project) {
        let d = data ?? AppData()
        let installs = d.installs.sorted { $0.php.compare($1.php, options: .numeric) == .orderedDescending }
        guard !installs.isEmpty else { return }
        let pairs = projectPairs(x)
        let alert = NSAlert()
        alert.messageText = "BBDD de \(x.name) en cada versión"
        alert.addButton(withTitle: "Guardar los vínculos")
        alert.addButton(withTitle: "Cancelar")
        var views: [NSView] = [dialogLabel("Cargar proyecto monta cada versión con la BBDD que elijas. «Ninguna»: la carpeta deja de ir con esa versión (la BBDD no se toca). Cada BBDD es de un solo proyecto por versión.", color: .secondaryLabelColor)]
        var popups: [(Install, NSPopUpButton, [String], [String])] = []
        for i in installs {
            let dbs = (d.dbs[i.folder] ?? []).sorted { $0.lowercased() < $1.lowercased() }
            let mine = pairs.filter { $0.0.folder == i.folder }.map { $0.1 }
            let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
            pop.addItem(withTitle: "— Ninguna —")
            for db in dbs {
                let other = linkOf(db, i.folder)
                pop.addItem(withTitle: other == nil || other == "" || other == x.name ? db : "\(db)  (de \(other!))")
            }
            if let m = mine.first, let n = dbs.firstIndex(of: m) { pop.selectItem(at: n + 1) } else { pop.selectItem(at: 0) }
            pop.isEnabled = !dbs.isEmpty
            let title = NSTextField(labelWithString: "PHP \(i.php)  (XAMPP-\(i.folder))")
            title.translatesAutoresizingMaskIntoConstraints = false
            title.widthAnchor.constraint(equalToConstant: 190).isActive = true
            let row = NSStackView(views: [title, pop])
            row.orientation = .horizontal
            row.spacing = 10
            views.append(row)
            popups.append((i, pop, dbs, mine))
        }
        alert.accessoryView = dialogStack(views, spacing: 10)
        guard alert.runStyled() == .alertFirstButtonReturn else { return }
        var changes: [(String, String, String)] = []
        for (i, pop, dbs, mine) in popups {
            let idx = pop.indexOfSelectedItem
            let new = idx >= 1 && idx <= dbs.count ? dbs[idx - 1] : ""
            for db in mine where db != new { changes.append((db, i.folder, "")) }
            // (también la que solo venía de su configuración: así queda fija)
            if !new.isEmpty && linkOf(new, i.folder) != x.name { changes.append((new, i.folder, x.name)) }
        }
        if changes.isEmpty { return }
        if SIMULATE { toast("[simulación] no se cambian los vínculos"); return }
        if let err = writeLinks(changes) {
            message("No se han podido guardar los vínculos", err, error: true)
            return
        }
        toast("Vínculos de \(x.name) guardados")
        reloadProjects()
    }

    /// Carga el proyecto en la versión del resultado pulsado. Solo pregunta si hay que cambiar de
    /// versión de PHP o crear el vhost
    func loadProject(_ req: ProjectRequest, folder: String, version: String, manual: Bool,
                     confirmSwitch: Bool = true) {
        let php = data?.installs.first(where: { $0.folder == version })?.php ?? req.inst.php
        let wasSheet = projectReq != nil
        projectReq = nil
        // Se espera a que se cierre la hoja antes de abrir la de la tarea
        DispatchQueue.main.asyncAfter(deadline: .now() + (wasSheet ? 0.4 : 0)) {
            let d = self.data ?? AppData()
            var notes: [String] = []
            let place = !req.db.isEmpty && (d.dbs[version] ?? []).contains(req.db) ? ", donde está la BBDD \(req.db)" : ""
            if version != d.active && confirmSwitch {
                if let act = d.installs.first(where: { $0.folder == d.active }) {
                    notes.append("Se va a cambiar de versión de PHP: se para XAMPP-\(act.folder) (PHP \(act.php)) y se activa XAMPP-\(version) (PHP \(php))\(place).")
                } else {
                    notes.append("Se activa XAMPP-\(version) (PHP \(php))\(place).")
                }
            }
            if req.create {
                notes.append("Todavía no hay un vhost para cargar proyectos: se crea \(req.link) (http y https, con su certificado y sus líneas en /etc/hosts).")
            }
            let st = d.php2shell[version] ?? "ok"
            if version != d.active && php2shellVulnerable(st) {
                notes.append("Ojo: " + php2shellText(st, php))
            }
            if !notes.isEmpty {
                let title = version != d.active && confirmSwitch ? "¿Cambiar a PHP \(php)?" : "¿Crear \(req.link)?"
                if !confirm(title, "Se pide la contraseña de administrador.", "Cargar proyecto",
                            steps: notes + ["\(req.link) apuntará a \(folder)."]) { return }
            }
            if manual { self.rememberProject(req.db, folder, version) }
            var env: [String: String] = [:]
            if let pwd = self.dbPwd[version] { env["MYSQL_PWD"] = pwd }
            self.runTask("Cargando el proyecto \(folder)", ["cargar-proyecto", folder, version, req.db],
                         doneText: "\(req.link) apunta a \(folder) (PHP \(php))", autoClose: true, env: env) { ok, _, _ in
                guard ok else { return }
                // El visor pasa al proyecto nuevo al momento, con sus botones: lo que se acaba de hacer
                // se sabe sin preguntarlo (gui-datos tarda unos segundos; la lectura completa sigue detrás)
                self.projects?.link = req.link
                self.projects?.current = folder
                self.projects?.create = false
                // (la página sube sola hasta el visor, arriba: sin desplazarla a mano)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.scrollTop += 1 }
                if let a = self.data?.active, a != version { self.data?.active = version }
                // Tienda PrestaShop: su dominio queda falseado (se ve en la pestaña Hosts)
                runQuick(["gui-hosts"]) { rc, out in
                    self.onHosts(rc, out)
                    let fake = (self.hosts ?? []).first { $0.folder == folder && $0.fake }
                    self.toast("Proyecto cargado: \(req.link) → \(folder) (PHP \(php))"
                               + (fake.map { "  ·  \($0.name) falseado (Dominios y hosts)" } ?? ""))
                }
            }
        }
    }

    /// Descarga una copia .zip de una base de cualquier versión (exportar-bd). Si no es la activa en
    /// marcha, el script arranca un MariaDB temporal y pide la contraseña de administrador
    /// Desmonta el proyecto cargado: el vhost (web.local) deja de apuntar a él y enseña una página vacía
    func unloadProject() {
        guard let p = projects, !p.current.isEmpty else { return }
        let name = (p.current as NSString).lastPathComponent
        runTask("Desmontando el proyecto \(name)", ["desmontar-proyecto"],
                doneText: "\(p.link) ya no apunta a \(name)", autoClose: true)
    }

    /// Abre (vacío) o cierra el asistente de Montar nuevo proyecto
    func newProject(_ show: Bool) {
        if show {
            npUrl = ""
            npFolder = ""
            npFolderAuto = true
            npVersion = data?.active ?? ""
            npDb = ""
            npFile = nil
            npStep = 1
            projQuery = ""
            npRepoQuery = ""
            npRepoNote = ""
            npFake = false
            npDomain = ""
            // (la lista ya está en memoria: loadNpRepos, al abrir el programa. Si hace rato que no se
            // pregunta a GitHub, se pone al día por detrás)
            showNpReposNote()
            if !npReposLoaded { loadNpRepos(cache: true) }
            if Date().timeIntervalSince(npReposWhen) > NP_REPOS_FRESH { loadNpRepos() }
        }
        npOpen = show
    }

    /// Los repositorios para el buscador de Nuevo proyecto, en segundo plano: los de la última vez (cache:
    /// al momento) o los de GitHub. Sin conexión, se queda la lista que había
    func loadNpRepos(cache: Bool = false) {
        if cache && npReposWhen != .distantPast { return }
        if !cache {
            if npReposBusy { return }
            npReposBusy = true
        }
        runQuick(["repos", "--todos"] + (cache ? ["--cache"] : [])) { _, out in
            let rows = parseRepos(out).items
            if !cache {
                self.npReposBusy = false
                if !rows.isEmpty { self.npReposWhen = Date() }
            }
            // (una respuesta de la última vez que llega tarde no pisa la de GitHub)
            if !rows.isEmpty && !(cache && self.npReposWhen != .distantPast) { self.npRepos = rows }
            self.npReposLoaded = true
            self.showNpReposNote()
        }
    }

    /// Debajo del buscador, cuántos hay (con uno ya elegido, sigue lo que se va a clonar)
    func showNpReposNote() {
        if !npReposLoaded || !npUrl.isEmpty { return }
        npRepoNote = npRepos.isEmpty ? "Sin la lista de GitHub (conéctalo en Configuración, GitHub): escribe la dirección abajo"
            : "\(npRepos.count) repositorios de GitHub"
    }

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
        if !sql.isEmpty { what.append("La BBDD \(db) se vacía y se carga «\((sql as NSString).lastPathComponent)» (antes se guarda una copia).") }
        runQuick(["gui-proyecto-git", folder]) { _, out in
            let f = parseLines(out).first(where: { $0.first == "G" && $0.count >= 6 })
            guard !code.isEmpty, let g = f, g[1] == "1" else {
                if confirm("¿Actualizar \(folder)?", "", "Actualizar", steps: what) {
                    self.upStart(folder, sql, db, code, mode, pull: false)
                }
                return
            }
            let dirty = Int(g[3]) ?? 0, ahead = Int(g[4]) ?? 0
            var state = ["Rama " + (g[2].isEmpty ? "sin rama (HEAD suelto)" : g[2])]
            if dirty > 0 { state.append(plural(dirty, "cambio", "cambios") + " sin commit") }
            if ahead > 0 { state.append(plural(ahead, "commit", "commits") + " sin subir") }
            var text = [state.joined(separator: "  ·  ")]
            if dirty > 0 || ahead > 0 { text.append("Revisa antes lo que estás trabajando: lo sustituido queda en ~/lvm-copias, pero no en git.") }
            let canPull = g[5] == "1" && !g[2].isEmpty
            text.append(canPull ? "Con el pull, la carpeta se equipara antes al repositorio. Si choca con tus cambios, se para sin tocar nada."
                        : "No se puede hacer pull: no tiene origin o no está en una rama.")
            let alert = NSAlert()
            alert.messageText = "¿Hacer git pull antes de copiar?"
            let steps = dialogSteps(what)
            let note = dialogLabel(text.joined(separator: "\n\n"), color: .secondaryLabelColor, align: .left)
            alert.accessoryView = dialogStack([steps, note])
            if canPull { alert.addButton(withTitle: "Hacer pull y copiar") }
            alert.addButton(withTitle: "Copiar sin pull")
            alert.addButton(withTitle: "Cancelar")
            let resp = alert.runModal()
            if canPull && resp == .alertFirstButtonReturn {
                self.upStart(folder, sql, db, code, mode, pull: true)
            } else if resp == (canPull ? .alertSecondButtonReturn : .alertFirstButtonReturn) {
                self.upStart(folder, sql, db, code, mode, pull: false)
            }
        }
    }

    func upStart(_ folder: String, _ sql: String, _ db: String, _ code: String, _ mode: String, pull: Bool) {
        var args = ["actualizar-proyecto", folder]
        if !code.isEmpty { args += ["--codigo", code, "--modo", mode] + (pull ? ["--pull"] : []) }
        if !sql.isEmpty { args += ["--bd", sql] }
        // (también solo con el código: al volver a cargarlo, su configuración vuelve a esta BBDD)
        if !db.isEmpty { args += ["--base", db] }
        let go = {
            _ = self.runTask("Actualizando \(folder)", args, progress: true, doneText: "\(folder) actualizado", env: self.dbEnv(),
                             cancelText: ("¿Cancelar la actualización?",
                                          "El proyecto se queda a medias, con lo hecho hasta ahora. Lo sustituido sigue en ~/lvm-copias.",
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
    /// versión activa (la de phpMyAdmin), con copia por defecto. Hay que escribir el nombre de la carpeta
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
                               checkbox: "Guardar antes una copia en ~/lvm-copias (se puede volver a cargar)", checked: true,
                               cancelLabel: "Solo el proyecto")
            if r2.ok {
                withDb = true
                copy = r2.checked
                args += ["--bd", db] + (copy ? ["--copia"] : [])
            }
        }
        let finalArgs = args, useDb = withDb
        let done = "Proyecto «\(x.name)» borrado" + (useDb ? " con su BBDD" : "") + (useDb && copy ? " (copia en ~/lvm-copias)" : "")
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
            notes.append("XAMPP-\(dst) ya tiene \(db): se guarda una copia suya en ~/lvm-copias y se sustituye. Lo que tenía se pierde (salvo en esa copia).")
            args.append("--sustituir")
        }
        guard confirm(replace ? "¿Sustituir \(db) en XAMPP-\(dst)?" : "¿Copiar \(db) a XAMPP-\(dst)?",
                      "", replace ? "Sustituir \(db)" : "Copiar a XAMPP-\(dst)", destructive: replace, steps: notes) else { return }
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
                hint.stringValue = "XAMPP-\(t.folder) ya tiene una BBDD \(name): se sustituye (antes se guarda una copia suya en ~/lvm-copias)."
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
            notes.append("XAMPP-\(dst) ya tiene \(name): se guarda una copia suya en ~/lvm-copias y se sustituye. Lo que tenía se pierde (salvo en esa copia).")
            args.append("--sustituir")
        }
        guard confirm("¿Replicar en XAMPP-\(dst)?", "",
                      replace ? "Sustituir y replicar" : "Replicar en XAMPP-\(dst)", destructive: replace, steps: notes) else { return }
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
    /// la escribe encima con sudo (guardando antes el anterior en ~/lvm-copias)
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
                      "\(src) es del administrador: se ha abierto una copia en el editor. Guarda los cambios y pulsa «Aplicar los cambios»: el anterior queda en ~/lvm-copias. Pide la contraseña de administrador.",
                      "Aplicar los cambios") else { return }
        if FileManager.default.contentsEqual(atPath: src, andPath: copy) {
            toast("No has cambiado nada en \(src) (¿guardaste los cambios?)")
            return
        }
        _ = runTask("Guardando \(src)", ["hosts", "--aplicar", copy], doneText: "\(src) actualizado", autoClose: true)
    }

    /// Los vhosts son del administrador (Apache los lee como root al arrancar): se edita una copia en
    /// ~/.lvm-instalador y, al pulsar Aplicar, el script la comprueba, la escribe con sudo (guardando
    /// antes la anterior en ~/lvm-copias) y recarga Apache. Si Apache no la acepta, se deja como estaba
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
                      "Son del administrador (Apache los lee como root): se ha abierto una copia en el editor. Guarda los cambios y pulsa «Aplicar los cambios»: se comprueban, los de ahora quedan en ~/lvm-copias y se recarga Apache. Si Apache no los acepta, se quedan como estaban. Pide la contraseña de administrador.",
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

// MARK: - Piezas de interfaz

/// Botón con solo un icono, del alto de OutlineButton (Abrir en Visual Studio Code)
struct IconCompactButton: ButtonStyle {
    @Environment(\.isEnabled) var enabled
    /// (más grandes: los de Cargar proyecto)
    var big = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, big ? 9 : 8)
            .padding(.vertical, big ? 6 : 3)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.18), lineWidth: 1))
            .opacity(enabled ? 1 : 0.5)
    }
}

/// Fondo hundido (Cargar proyecto): más oscuro que la ventana, con sombra por dentro
struct SunkenBackground: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14)
        return shape.fill(Color.black.opacity(0.10))
            .overlay(shape.stroke(Color.black.opacity(0.35), lineWidth: 4).blur(radius: 3)
                .offset(y: 1.5).mask(shape))
            .overlay(shape.stroke(Color.primary.opacity(0.10), lineWidth: 1))
    }
}

/// Al pasar el ratón por un botón: la mano y un poco más de luz, con una transición corta
struct HoverPointer: ViewModifier {
    @Environment(\.isEnabled) var enabled
    @Environment(\.colorScheme) var scheme
    @State private var hover = false
    @State private var pushed = false
    func body(content: Content) -> some View {
        content
            .brightness(hover && enabled ? (scheme == .dark ? 0.08 : -0.05) : 0)
            .animation(.easeOut(duration: 0.12), value: hover)
            .onHover { inside in
                hover = inside
                if inside && enabled && !pushed {
                    NSCursor.pointingHand.push()
                    pushed = true
                } else if !inside && pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onDisappear {
                if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}

extension View {
    func hoverPointer() -> some View { modifier(HoverPointer()) }
    /// En vez de .help(): el mensaje al dejar el ratón encima con el aspecto de la ventana
    func tip(_ text: String) -> some View { modifier(Tip(text: text)) }
}

/// Mensaje al dejar el ratón encima: gris oscuro y con las esquinas redondeadas, como el resto de la
/// ventana (el de .help() es el del sistema y no se puede cambiar). Es una ventanita propia, encima
/// de todo: no la recorta la vista en la que está
final class TipWindow {
    static let shared = TipWindow()
    private var panel: NSPanel? = nil
    private var work: DispatchWorkItem? = nil

    func schedule(_ text: String) {
        cancel()
        if text.isEmpty { return }
        let w = DispatchWorkItem { [weak self] in self?.show(text) }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
    }

    func cancel() {
        work?.cancel()
        work = nil
        panel?.orderOut(nil)
    }

    private func show(_ text: String) {
        let host = NSHostingView(rootView: TipBubble(text: text))
        let size = host.fittingSize
        let p: NSPanel
        if let old = panel {
            p = old
        } else {
            p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .popUpMenu
            p.ignoresMouseEvents = true
            panel = p
        }
        p.contentView = host
        let mouse = NSEvent.mouseLocation
        // (justo debajo de la punta de la flecha y a su derecha, no 20 puntos más abajo)
        var origin = NSPoint(x: mouse.x + 10, y: mouse.y - size.height - 6)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            let vf = screen.visibleFrame
            origin.x = min(max(origin.x, vf.minX + 4), vf.maxX - size.width - 4)
            if origin.y < vf.minY + 4 { origin.y = mouse.y + 8 }
        }
        p.setFrame(NSRect(origin: origin, size: size), display: true)
        p.orderFront(nil)
    }
}

struct TipBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundColor(Color(white: 0.93))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 360, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.24, green: 0.24, blue: 0.26)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
}

struct Tip: ViewModifier {
    let text: String
    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside { TipWindow.shared.schedule(text) } else { TipWindow.shared.cancel() }
            }
            .onDisappear { TipWindow.shared.cancel() }
    }
}

/// Estilo de todos los botones normales (se pone en ContentView, en las hojas y en los recuadros
/// que salen de arriba): el de OutlineButton, con borde, la mano y el borde azul al pasar el ratón,
/// no el botón gris pequeño de macOS. Los que tienen su propio estilo llevan .hoverPointer()
struct PointerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OutlineBody(configuration: configuration, kind: "", compact: false)
    }
}

// Estado de una rama según php.net: Estable (verde), Solo seguridad (ámbar) o Sin soporte (rojo)
struct StatePill: View {
    let b: Branch
    // Texto, color y explicación al pasar el ratón
    var info: (String, Color, String) {
        switch b.phpState {
        case "stable":
            return ("Estable", GREEN,
                    "Con soporte completo"
                    + (b.activeEnd.isEmpty ? "" : " (hasta \(fmtMonth(b.activeEnd)))"))
        case "security":
            return ("Solo seguridad", Color(red: 0.78, green: 0.53, blue: 0.0),
                    "Solo parches de seguridad"
                    + (b.securityEnd.isEmpty ? "" : " hasta \(fmtMonth(b.securityEnd))"))
        default:
            return ("Sin soporte", RED,
                    "Sin parches"
                    + (b.securityEnd.isEmpty ? "" : " (desde \(fmtMonth(b.securityEnd)))"))
        }
    }
    var body: some View {
        Text(info.0)
            .font(.caption.weight(.bold))
            .foregroundColor(info.1)
            .tip(info.2)
    }
}

/// Último parche de una rama: de seguridad (php.net lo marca así: corrige vulnerabilidades) o solo
/// de errores
struct ReleaseTag: View {
    let security: Bool
    var body: some View {
        Text(security ? "Parche de seguridad" : "Corrección de errores")
            .font(.caption.weight(.bold))
            .foregroundColor(security ? Color(red: 0.21, green: 0.52, blue: 0.89) : .secondary)
            .tip(security ? "Parche de seguridad"
                          : "Corrige errores")
    }
}

struct Pill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(ACCENT))
    }
}

/// «Activa» como texto azul junto a un titulo (sin aspecto de boton), como en Linux
struct ActiveTag: View {
    var text = "Activa"
    var body: some View {
        Text(text).font(.body.weight(.bold)).foregroundColor(ACCENT)
    }
}

/// Texto con la parte buscada en negrita
func highlighted(_ s: String, _ q: String) -> Text {
    guard !q.isEmpty, let r = s.range(of: q, options: .caseInsensitive) else { return Text(s) }
    return Text(String(s[..<r.lowerBound])) + Text(String(s[r])).bold() + Text(String(s[r.upperBound...]))
}

struct Page<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { content }
                .frame(maxWidth: 640)
                .padding(24)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Logotipos de los paquetes (Simple Icons, CC0; cada marca es de su dueño y solo se usa para
/// identificar su paquete). El trazo, pasado a M, L, C y Z absolutos en una caja de 24x24
// Iconos actualizar e imagenes (upload3 y gallery-import, en outline): de Reicon, https://reicon.dev
// MIT License
//
// Copyright (c) 2025 REICON
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
let LOGO_PATHS: [String: String] = [
    // (bases de datos: discos apilados; Node: su hexágono)
    "bbdd": "M 3.5 7 C 3.5 5.34 7.31 4 12 4 C 16.69 4 20.5 5.34 20.5 7 C 20.5 8.66 16.69 10 12 10 C 7.31 10 3.5 8.66 3.5 7 Z M 3.5 8.4 C 3.5 10.06 7.31 11.4 12 11.4 C 16.69 11.4 20.5 10.06 20.5 8.4 L 20.5 12 C 20.5 13.66 16.69 15 12 15 C 7.31 15 3.5 13.66 3.5 12 Z M 3.5 13.4 C 3.5 15.06 7.31 16.4 12 16.4 C 16.69 16.4 20.5 15.06 20.5 13.4 L 20.5 17 C 20.5 18.66 16.69 20 12 20 C 7.31 20 3.5 18.66 3.5 17 Z",
    "node": "M 10.61 2.8 C 12 2 12 2 13.39 2.8 L 19.27 6.2 C 20.66 7 20.66 7 20.66 8.6 L 20.66 15.4 C 20.66 17 20.66 17 19.27 17.8 L 13.39 21.2 C 12 22 12 22 10.61 21.2 L 4.73 17.8 C 3.34 17 3.34 17 3.34 15.4 L 3.34 8.6 C 3.34 7 3.34 7 4.73 6.2 Z",
    "actualizar": "M 17.53 7.53 C 17.823 7.237 17.823 6.763 17.53 6.47 L 12.53 1.47 C 12.39 1.329 12.199 1.25 12 1.25 C 11.801 1.25 11.61 1.329 11.47 1.47 L 6.47 6.47 C 6.177 6.763 6.177 7.237 6.47 7.53 C 6.763 7.823 7.237 7.823 7.53 7.53 L 11.25 3.811 L 11.25 15 C 11.25 15.414 11.586 15.75 12 15.75 C 12.414 15.75 12.75 15.414 12.75 15 L 12.75 3.811 L 16.47 7.53 C 16.763 7.823 17.237 7.823 17.53 7.53 Z M 21.212 19.109 C 21.249 18.647 21.25 18.052 21.25 17.2 L 21.25 14 C 21.25 13.586 21.586 13.25 22 13.25 C 22.414 13.25 22.75 13.586 22.75 14 L 22.75 17.232 C 22.75 18.045 22.75 18.701 22.707 19.232 C 22.662 19.778 22.568 20.258 22.341 20.703 C 21.982 21.408 21.408 21.982 20.703 22.341 C 20.258 22.568 19.778 22.662 19.232 22.707 C 18.701 22.75 18.045 22.75 17.232 22.75 L 6.768 22.75 C 5.955 22.75 5.299 22.75 4.769 22.707 C 4.222 22.662 3.742 22.568 3.298 22.341 C 2.592 21.982 2.018 21.408 1.659 20.703 C 1.432 20.258 1.338 19.778 1.293 19.232 C 1.25 18.701 1.25 18.045 1.25 17.232 L 1.25 14 C 1.25 13.586 1.586 13.25 2 13.25 C 2.414 13.25 2.75 13.586 2.75 14 L 2.75 17.2 C 2.75 18.052 2.751 18.647 2.788 19.109 C 2.825 19.563 2.895 19.824 2.995 20.021 C 3.211 20.445 3.555 20.789 3.979 21.005 C 4.176 21.105 4.437 21.174 4.891 21.212 C 5.353 21.249 5.948 21.25 6.8 21.25 L 17.2 21.25 C 18.052 21.25 18.647 21.249 19.109 21.212 C 19.563 21.174 19.824 21.105 20.021 21.005 C 20.445 20.789 20.789 20.445 21.005 20.021 C 21.105 19.824 21.174 19.563 21.212 19.109 Z",
    "imagenes": "M 9 10 C 10.105 10 11 9.105 11 8 C 11 6.895 10.105 6 9 6 C 7.895 6 7 6.895 7 8 C 7 9.105 7.895 10 9 10 Z M 13 2 L 9 2 C 4 2 2 4 2 9 L 2 15 C 2 20 4 22 9 22 L 15 22 C 20 22 22 20 22 15 L 22 10 M 18 2 L 18 8 L 20 6 M 18 8 L 16 6 M 2.67 18.95 L 7.6 15.64 C 8.39 15.11 9.53 15.17 10.24 15.78 L 10.57 16.07 C 11.35 16.74 12.61 16.74 13.39 16.07 L 17.55 12.5 C 18.33 11.83 19.59 11.83 20.37 12.5 L 22 13.9",
    // (el del botón Log: un folio con «LOG» en hueco, dibujado para Nexum)
    "log": "M 2 1 L 15 1 L 15 8 L 22 8 L 22 23 L 2 23 Z M 16.5 1 L 22 6.5 L 16.5 6.5 Z M 3.6 11 L 3.6 20 L 8.6 20 L 8.6 18.3 L 5.3 18.3 L 5.3 11 Z M 9.5 11 L 9.5 20 L 14.5 20 L 14.5 11 Z M 11.2 12.7 L 12.8 12.7 L 12.8 18.3 L 11.2 18.3 Z M 20.4 11 L 15.4 11 L 15.4 20 L 20.4 20 L 20.4 15.1 L 17.9 15.1 L 17.9 16.8 L 18.7 16.8 L 18.7 18.3 L 17.1 18.3 L 17.1 12.7 L 20.4 12.7 Z",
    "github": "M 12 0.297 C 5.37 0.297 0 5.67 0 12.297 C 0 17.6 3.438 22.097 8.205 23.682 C 8.805 23.795 9.025 23.424 9.025 23.105 C 9.025 22.82 9.015 22.065 9.01 21.065 C 5.672 21.789 4.968 19.455 4.968 19.455 C 4.422 18.07 3.633 17.7 3.633 17.7 C 2.546 16.956 3.717 16.971 3.717 16.971 C 4.922 17.055 5.555 18.207 5.555 18.207 C 6.625 20.042 8.364 19.512 9.05 19.205 C 9.158 18.429 9.467 17.9 9.81 17.6 C 7.145 17.3 4.344 16.268 4.344 11.67 C 4.344 10.36 4.809 9.29 5.579 8.45 C 5.444 8.147 5.039 6.927 5.684 5.274 C 5.684 5.274 6.689 4.952 8.984 6.504 C 9.944 6.237 10.964 6.105 11.984 6.099 C 13.004 6.105 14.024 6.237 14.984 6.504 C 17.264 4.952 18.269 5.274 18.269 5.274 C 18.914 6.927 18.509 8.147 18.389 8.45 C 19.154 9.29 19.619 10.36 19.619 11.67 C 19.619 16.28 16.814 17.295 14.144 17.59 C 14.564 17.95 14.954 18.686 14.954 19.81 C 14.954 21.416 14.939 22.706 14.939 23.096 C 14.939 23.411 15.149 23.786 15.764 23.666 C 20.565 22.092 24 17.592 24 12.297 C 24 5.67 18.627 0.297 12 0.297",
    // (Cloudflare: Simple Icons 13.21.0, CC0; sus arcos, pasados a curvas)
    "cloudflare": "M 16.5088 16.8447 C 16.6563 16.3379 16.5996 15.874 16.3535 15.5293 C 16.1289 15.2129 15.749 15.0303 15.292 15.0088 L 6.6328 14.8965 C 6.579 14.8973 6.5287 14.8704 6.4995 14.8252 C 6.4712 14.7832 6.4644 14.7266 6.4785 14.6699 C 6.5063 14.5859 6.5908 14.5215 6.6821 14.5137 L 15.418 14.4014 C 16.4531 14.3525 17.5781 13.5146 17.9717 12.4878 L 18.4707 11.1865 C 18.4922 11.1304 18.5 11.0737 18.4854 11.0185 C 17.9229 8.4722 15.6504 6.5732 12.9355 6.5732 C 10.4316 6.5732 8.3071 8.1909 7.5479 10.4346 C 7.0552 10.0688 6.4292 9.8721 5.7539 9.9356 C 4.5513 10.0546 3.5874 11.0186 3.4678 12.2212 C 3.4395 12.5312 3.4609 12.834 3.5313 13.1152 C 1.5683 13.171 0 14.7754 0 16.752 C 0 16.9268 0.0142 17.1035 0.0352 17.2793 C 0.0493 17.3623 0.1196 17.4268 0.2041 17.4268 L 16.1855 17.4268 C 16.2764 17.4268 16.3613 17.3623 16.3887 17.2715 L 16.5087 16.8447 Z M 19.2656 11.2813 C 19.1885 11.2813 19.1045 11.2813 19.0273 11.2925 C 18.9707 11.2925 18.9219 11.334 18.9003 11.3901 L 18.5625 12.5645 C 18.415 13.0713 18.4707 13.5352 18.7168 13.8809 C 18.9424 14.1973 19.3223 14.3789 19.7793 14.4004 L 21.623 14.5137 C 21.6787 14.5137 21.7285 14.54 21.7559 14.584 C 21.7842 14.627 21.791 14.6914 21.7773 14.7402 C 21.749 14.8242 21.6641 14.8887 21.5733 14.8955 L 19.6523 15.0078 C 18.6113 15.0566 17.4941 15.8945 17.0996 16.9218 L 16.959 17.2803 C 16.9307 17.3516 16.9805 17.4219 17.0576 17.4219 L 23.6553 17.4219 C 23.7324 17.4219 23.8027 17.373 23.8243 17.2959 C 23.9365 16.8877 24 16.4589 24 16.0156 C 24 13.4131 21.875 11.2886 19.2656 11.2886",
    "php": "M 7.01 10.207 L 6.066 10.207 L 5.551 12.855 L 6.389 12.855 C 6.945 12.855 7.359 12.75 7.631 12.541 C 7.903 12.331 8.086 11.982 8.181 11.492 C 8.273 11.022 8.231 10.69 8.057 10.497 C 7.882 10.304 7.534 10.207 7.01 10.207 Z M 12 5.688 C 5.373 5.688 0 8.514 0 12 C 0 15.486 5.373 18.313 12 18.313 C 18.627 18.313 24 15.486 24 12 C 24 8.514 18.627 5.688 12 5.688 Z M 8.74 13.139 C 8.479 13.389 8.165 13.577 7.823 13.69 C 7.487 13.798 7.058 13.854 6.538 13.854 L 5.357 13.854 L 5.03 15.535 L 3.652 15.535 L 4.882 9.209 L 7.532 9.209 C 8.329 9.209 8.91 9.418 9.276 9.837 C 9.642 10.255 9.752 10.839 9.606 11.589 C 9.55 11.886 9.447 12.172 9.301 12.436 C 9.158 12.691 8.971 12.926 8.74 13.139 Z M 12.764 13.854 L 13.307 11.055 C 13.37 10.737 13.346 10.519 13.239 10.404 C 13.132 10.288 12.903 10.23 12.552 10.23 L 11.46 10.23 L 10.756 13.855 L 9.388 13.855 L 10.618 7.528 L 11.985 7.528 L 11.658 9.21 L 12.876 9.21 C 13.643 9.21 14.171 9.344 14.462 9.611 C 14.753 9.878 14.84 10.311 14.725 10.91 L 14.153 13.854 L 12.764 13.854 Z M 20.361 11.589 C 20.306 11.886 20.203 12.172 20.056 12.436 C 19.913 12.691 19.726 12.926 19.495 13.139 C 19.234 13.388 18.921 13.576 18.578 13.69 C 18.242 13.798 17.813 13.854 17.292 13.854 L 16.112 13.854 L 15.785 15.536 L 14.407 15.536 L 15.637 9.21 L 18.286 9.21 C 19.083 9.21 19.664 9.419 20.03 9.838 C 20.396 10.255 20.507 10.839 20.361 11.589 Z M 17.766 10.207 L 16.823 10.207 L 16.307 12.855 L 17.145 12.855 C 17.702 12.855 18.116 12.75 18.387 12.541 C 18.659 12.331 18.842 11.982 18.938 11.492 C 19.03 11.022 18.987 10.69 18.813 10.497 C 18.639 10.304 18.289 10.207 17.766 10.207 Z",
    "apache": "M 17.805 2.197 L 17.805 2.263 L 17.961 2.263 L 17.961 2.703 L 18.033 2.703 L 18.033 2.263 L 18.189 2.263 L 18.189 2.197 Z M 18.705 2.197 L 18.53 2.55 L 18.358 2.197 L 18.271 2.197 L 18.271 2.703 L 18.338 2.703 L 18.338 2.3 L 18.51 2.65 L 18.555 2.65 L 18.727 2.3 L 18.727 2.704 L 18.793 2.704 L 18.793 2.198 Z M 14.448 3.197 C 14.244 3.507 14.024 3.857 13.788 4.257 L 13.748 4.319 C 13.304 5.07 12.882 5.833 12.483 6.609 C 12.296 6.969 12.103 7.351 11.906 7.755 L 14.173 7.505 C 14.833 7.203 15.128 6.927 15.415 6.529 C 15.493 6.416 15.57 6.302 15.645 6.187 C 15.875 5.824 16.105 5.424 16.308 5.027 C 16.505 4.641 16.678 4.26 16.813 3.917 C 16.896 3.697 16.963 3.495 17.011 3.317 C 17.053 3.159 17.085 3.01 17.111 2.867 C 16.227 3.017 15.146 3.162 14.443 3.197 Z M 11.894 7.78 L 11.817 7.94 C 11.739 8.1 11.66 8.26 11.581 8.428 C 11.495 8.608 11.409 8.792 11.321 8.98 L 11.189 9.267 C 10.687 10.355 10.211 11.456 9.762 12.567 C 9.599 12.964 9.435 13.374 9.269 13.797 C 9.119 14.177 8.972 14.562 8.819 14.961 L 8.799 15.021 C 8.649 15.417 8.499 15.823 8.346 16.241 L 8.336 16.268 L 9.056 16.188 C 9.042 16.187 9.028 16.185 9.014 16.182 C 9.877 16.076 11.024 15.432 11.764 14.635 C 12.106 14.268 12.416 13.835 12.704 13.329 C 12.917 12.952 13.117 12.534 13.308 12.071 C 13.476 11.666 13.636 11.228 13.788 10.753 C 13.592 10.858 13.365 10.933 13.115 10.988 C 13.025 11.009 12.934 11.024 12.842 11.034 C 13.648 10.724 14.156 10.129 14.525 9.394 C 14.232 9.597 13.904 9.742 13.557 9.822 C 13.497 9.834 13.441 9.844 13.383 9.852 L 13.34 9.858 L 13.342 9.858 C 13.62 9.74 13.856 9.61 14.06 9.455 C 14.314 9.264 14.53 9.027 14.697 8.757 L 14.76 8.653 L 14.837 8.499 C 14.975 8.223 15.098 7.939 15.204 7.649 L 15.234 7.561 C 15.287 7.41 15.328 7.255 15.357 7.098 C 15.327 7.122 15.296 7.144 15.263 7.163 C 15.02 7.308 14.603 7.44 14.267 7.503 L 14.93 7.429 L 14.266 7.502 L 14.249 7.502 L 14.149 7.519 C 14.155 7.516 14.159 7.513 14.166 7.511 L 11.901 7.761 L 11.888 7.783 Z M 8.27 16.45 C 8.153 16.773 8.034 17.104 7.915 17.442 L 7.91 17.457 C 7.894 17.503 7.878 17.551 7.86 17.599 C 7.78 17.826 7.71 18.031 7.55 18.499 C 7.814 18.619 8.025 18.934 8.225 19.292 C 8.206 18.914 8.039 18.558 7.759 18.302 C 9.052 18.362 10.169 18.032 10.749 17.085 C 10.799 17.001 10.845 16.912 10.889 16.817 C 10.629 17.15 10.299 17.291 9.689 17.257 C 9.689 17.257 9.685 17.257 9.684 17.259 L 9.688 17.257 C 10.588 16.853 11.042 16.467 11.442 15.824 C 11.536 15.671 11.628 15.504 11.722 15.321 C 10.934 16.131 10.02 16.361 9.058 16.186 L 8.338 16.264 C 8.315 16.325 8.292 16.386 8.271 16.447 Z M 15.42 0.112 C 15.044 0.334 14.42 0.962 13.672 1.875 L 14.358 3.169 C 14.838 2.482 15.328 1.862 15.82 1.333 L 15.878 1.271 C 15.858 1.291 15.838 1.311 15.821 1.333 C 15.661 1.509 15.177 2.073 14.446 3.196 C 15.149 3.161 16.23 3.016 17.112 2.866 C 17.374 1.396 16.854 0.724 16.854 0.724 C 16.854 0.724 16.194 -0.346 15.418 0.114 Z M 12.336 6.514 C 12.747 5.747 13.182 4.993 13.642 4.254 L 13.682 4.19 C 13.906 3.838 14.132 3.497 14.359 3.17 L 13.674 1.877 L 13.517 2.069 C 13.32 2.314 13.114 2.579 12.904 2.859 C 12.188 3.818 11.515 4.809 10.888 5.829 L 10.866 5.867 L 11.759 7.63 C 11.949 7.252 12.139 6.878 12.334 6.512 Z M 8.606 14.834 C 8.764 14.428 8.925 14.024 9.089 13.609 C 9.245 13.215 9.409 12.819 9.573 12.419 C 10.08 11.206 10.614 10.005 11.173 8.815 L 11.378 8.391 C 11.498 8.148 11.615 7.906 11.738 7.667 C 11.742 7.653 11.749 7.639 11.758 7.627 L 10.863 5.864 L 10.819 5.934 C 10.612 6.274 10.405 6.621 10.202 6.976 C 9.817 7.645 9.453 8.325 9.11 9.016 L 9.016 9.209 C 8.527 10.208 8.107 11.24 7.758 12.296 C 7.548 12.951 7.374 13.618 7.238 14.293 L 8.134 16.063 C 8.251 15.746 8.374 15.425 8.498 15.1 Z M 7.23 14.358 C 7.116 14.916 7.038 15.482 6.996 16.05 C 6.996 16.07 6.992 16.09 6.991 16.11 C 6.711 15.66 5.961 15.222 5.965 15.226 C 6.502 16.004 6.909 16.776 6.97 17.536 C 6.68 17.594 6.286 17.509 5.83 17.341 C 6.305 17.777 6.66 17.897 6.8 17.929 C 6.366 17.959 5.91 18.257 5.454 18.599 C 6.122 18.329 6.664 18.219 7.05 18.309 C 6.44 20.049 5.82 21.964 5.207 23.999 C 5.38 23.949 5.516 23.816 5.571 23.645 C 5.681 23.277 6.411 20.859 7.549 17.68 L 7.646 17.41 L 7.674 17.332 C 7.794 17 7.92 16.66 8.048 16.312 L 8.138 16.075 L 8.138 16.071 L 7.24 14.3 C 7.237 14.32 7.23 14.34 7.228 14.36 Z",
    "mariadb": "M 23.157 4.412 C 22.481 4.696 22.367 4.722 21.484 4.784 C 20.834 4.829 20.727 4.841 20.272 4.993 C 19.522 5.239 18.877 5.743 18.252 6.583 C 17.956 6.981 17.003 8.496 17.003 8.571 C 17.003 8.628 16.353 9.569 16.088 9.891 C 15.514 10.604 15.008 10.97 13.948 11.481 C 13.178 11.841 12.724 12.005 9.846 12.958 C 8.773 13.311 7.713 13.696 7.479 13.822 C 6.627 14.271 5.964 14.858 5.276 15.76 C 4.273 17.08 4.304 17.073 2.234 16.707 C 2.01 16.68 1.785 16.659 1.559 16.644 C 0.915 16.594 0.536 16.688 0.227 16.978 L 0 17.193 L 0.177 17.281 C 0.271 17.331 0.53 17.515 0.738 17.679 C 0.953 17.849 1.199 18.026 1.288 18.07 C 1.376 18.114 1.458 18.158 1.471 18.171 C 1.483 18.184 1.382 18.341 1.243 18.524 C 0.808 19.105 0.65 19.395 0.669 19.572 C 0.688 19.736 0.701 19.742 1.099 19.742 C 1.616 19.736 1.925 19.686 2.36 19.534 C 3.01 19.301 4.418 18.594 5.144 18.134 C 5.92 17.634 6.861 17.136 7.1 17.092 C 7.182 17.072 7.454 17.022 7.694 16.978 C 8.274 16.871 9.158 16.883 10.281 17.028 C 10.389 17.041 10.654 17.073 10.881 17.092 C 11.108 17.117 11.311 17.149 11.335 17.168 C 11.361 17.18 11.809 17.205 12.333 17.224 C 13.267 17.25 13.437 17.231 13.633 17.035 C 13.759 16.902 14.018 16.404 14.131 16.05 C 14.34 15.407 14.548 15.129 14.497 15.558 C 14.384 16.524 14.175 17.25 13.784 17.969 C 13.525 18.468 13.121 19.061 12.85 19.364 C 12.528 19.711 12.535 19.724 12.938 19.679 C 13.557 19.616 14.409 19.282 15.034 18.859 C 15.861 18.297 16.681 17.168 17.224 15.829 C 17.331 15.559 17.444 15.609 17.407 15.912 C 17.394 16.006 17.369 16.227 17.35 16.41 L 17.319 16.738 L 17.672 16.536 C 18.505 16.056 19.086 15.274 19.799 13.652 C 20.026 13.134 20.676 10.73 20.872 9.676 C 20.943 9.324 21.033 8.976 21.143 8.634 C 21.27 8.205 21.339 8.079 21.623 7.776 C 21.806 7.586 22.248 7.221 22.601 6.968 C 23.321 6.463 23.554 6.218 23.788 5.763 C 23.996 5.346 24.072 4.633 23.92 4.406 C 23.788 4.204 23.636 4.21 23.157 4.412 Z",
    "phpmyadmin": "M 5.463 3.476 C 6.69 5.225 7.497 7.399 7.68 9.798 C 7.822 11.577 7.593 13.366 7.008 15.052 C 7.752 14.164 8.822 13.615 9.977 13.529 C 10.027 13.525 10.076 13.523 10.125 13.521 C 10.205 13.03 10.595 10.071 9.148 6.841 C 8.08 4.455 6.148 3.681 5.463 3.476 Z M 7.24 3.513 C 7.24 3.513 9.646 4.579 10.566 9.06 C 11.173 12.015 10.615 13.896 10.164 14.833 C 11.392 13.669 12.983 12.965 14.67 12.839 C 15.53 12.774 16.365 12.859 17.152 13.072 C 17.052 12.331 16.559 9.658 14.42 7.152 C 11.157 3.329 7.24 3.512 7.24 3.512 Z M 22.057 13.214 L 4.137 16.263 C 5.09 16.593 5.714 17.509 5.672 18.517 C 5.664 18.724 5.629 18.929 5.566 19.127 C 5.621 19.1 8.255 17.852 11.908 17.093 C 15.146 16.42 17.631 16.733 18.193 16.82 C 18.908 15.122 20.314 13.81 22.057 13.214 Z M 15.844 17.292 C 13.526 17.292 11.203 17.787 9.23 18.458 C 6.362 19.434 6.279 19.806 3.68 19.501 C 1.844 19.286 0 18.386 0 18.386 C 0 18.386 2.406 20.356 4.914 20.513 C 6.9 20.638 8.419 19.691 10.229 19.099 C 12.89 18.228 14.74 18.129 16.482 18.124 C 19.361 18.116 24 19.353 24 19.353 C 24 19.353 21.89 18.309 18.967 17.633 C 17.942 17.402 16.895 17.288 15.844 17.293 Z",
    "perl": "M 11.638 0 C 11.49 0 11.431 0.689 11.386 2.925 C 11.328 5.785 11.316 5.874 10.876 6.839 C 10.516 7.632 9.253 9.515 8.839 9.879 C 8.466 10.207 7.656 11.439 7.259 12.28 C 6.549 13.784 6.6 15.8 7.219 17.327 C 7.737 18.521 8.481 19.483 9.679 20.509 C 10.619 21.314 10.909 21.428 11.054 21.053 C 11.103 20.925 10.892 20.481 10.571 20.035 C 10.258 19.599 9.728 18.673 9.393 17.976 C 8.011 15.05 8.693 12.619 10.295 9.931 C 11.185 8.538 11.698 7.289 11.874 6.079 C 12.094 4.564 11.917 0 11.638 0 Z M 10.881 1.215 C 10.695 1.215 10.653 1.475 10.653 2.637 C 10.653 3.419 10.573 4.291 10.476 4.575 C 10.164 5.489 9.322 6.312 6.994 7.979 C 5.31 9.184 3.898 10.631 3.354 11.711 C 1.688 15.01 3.159 19.022 6.774 21.044 C 8.387 21.946 9.74 22.297 9.74 21.812 C 9.74 21.686 9.686 21.584 9.619 21.584 C 9.552 21.584 8.987 21.252 8.365 20.846 C 5.675 19.091 4.418 16.919 4.618 14.364 C 4.768 12.454 5.491 11.284 8.414 8.229 C 10.936 5.593 11.104 5.259 11.107 2.925 C 11.108 1.505 11.071 1.215 10.881 1.215 Z M 12.389 1.847 C 12.286 1.864 12.249 2.752 12.247 4.75 L 12.243 7.676 L 11.499 10.488 C 10.669 13.028 10.545 15.621 11.154 18.213 C 11.712 20.415 11.95 20.851 12.721 21.07 C 13.064 21.168 13.611 21.425 13.937 21.642 C 14.673 22.132 15.332 22.077 16.652 21.41 C 18.572 20.44 19.861 19.188 20.719 17.457 C 21.464 15.809 21.575 13.747 20.787 12.107 C 20.087 10.693 18.905 9.553 16.429 7.91 C 14.267 6.474 13.812 6.09 13.279 5.258 C 12.957 4.755 12.91 4.534 12.971 3.814 C 13.011 3.346 13.097 2.836 13.163 2.68 C 13.264 2.441 13.232 2.412 12.961 2.498 C 12.701 2.58 12.621 2.525 12.541 2.212 C 12.48 1.967 12.429 1.84 12.389 1.847 Z M 13.103 6.433 C 13.137 6.426 13.238 6.546 13.355 6.739 C 13.499 6.976 14.377 7.739 15.307 8.436 C 18.195 10.625 20.577 12.814 19.394 16.636 C 18.989 17.782 18.404 18.706 17.431 19.734 C 16.887 20.309 16.165 20.824 15.901 20.824 C 15.854 20.824 16.153 20.394 16.565 19.87 C 17.902 18.17 18.537 16.152 18.355 14.196 C 18.187 12.4 16.798 10.221 14.602 8.306 C 13.69 7.51 13.084 6.77 13.09 6.46 C 13.09 6.444 13.095 6.435 13.103 6.433 Z M 12.014 21.925 C 11.806 21.919 11.717 22.274 11.717 23.046 C 11.717 23.986 11.735 24.034 12.059 23.988 C 12.361 23.946 12.406 23.838 12.446 23.089 C 12.478 22.476 12.427 22.187 12.263 22.05 C 12.166 21.97 12.083 21.927 12.014 21.925 Z M 10.962 22.205 C 10.838 22.203 10.736 22.345 10.635 22.635 C 10.55 22.88 10.382 23.116 10.262 23.162 C 9.94 23.286 9.998 23.712 10.337 23.712 C 10.499 23.712 10.739 23.603 10.871 23.472 C 11.312 23.03 11.45 22.648 11.253 22.41 C 11.142 22.276 11.047 22.207 10.963 22.205 Z M 13.036 22.268 C 12.724 22.268 12.756 22.878 13.089 23.302 C 13.398 23.694 13.997 23.869 13.997 23.566 C 13.997 23.314 13.222 22.268 13.036 22.268 Z",
    "xampp": "M 16.792 11.923 C 16.905 11.966 17.018 12.002 17.126 12.051 C 17.576 12.254 17.841 12.604 17.874 13.095 C 17.915 13.729 17.918 14.366 17.876 15 C 17.827 15.732 17.151 16.292 16.393 16.271 C 15.658 16.25 15.024 15.651 14.996 14.93 C 14.979 14.489 14.993 14.046 14.99 13.604 C 14.989 13.365 14.987 13.362 14.745 13.361 C 13.382 13.36 12.019 13.369 10.656 13.358 C 9.768 13.351 9.235 13.84 9.185 14.818 C 9.166 15.198 9.085 15.545 8.828 15.836 C 8.431 16.287 7.93 16.437 7.356 16.302 C 6.802 16.171 6.489 15.78 6.321 15.254 C 6.204 14.887 6.265 14.517 6.333 14.16 C 6.674 12.363 7.699 11.154 9.458 10.605 C 9.815 10.493 10.189 10.439 10.563 10.439 C 11.503 10.44 12.444 10.44 13.384 10.438 C 13.512 10.438 13.641 10.426 13.769 10.417 C 14.471 10.366 14.935 9.906 14.989 9.065 C 14.993 9.001 14.989 8.936 14.99 8.872 C 15.001 8.084 15.595 7.476 16.383 7.447 C 17.17 7.418 17.821 7.974 17.876 8.765 C 17.952 9.848 17.611 10.811 16.963 11.672 C 16.903 11.751 16.819 11.816 16.792 11.923 Z M 8.249 10.436 C 7.991 10.428 7.678 10.454 7.367 10.401 C 6.831 10.311 6.491 10.011 6.347 9.485 C 6.19 8.912 6.25 8.388 6.698 7.96 C 7.154 7.526 7.694 7.4 8.285 7.645 C 8.805 7.861 9.144 8.376 9.175 8.938 C 9.2 9.382 9.178 9.828 9.182 10.272 C 9.183 10.388 9.139 10.439 9.021 10.437 C 8.781 10.434 8.542 10.436 8.249 10.436 Z M 21.682 0 L 2.318 0 C 1.102 0 0.116 0.986 0.116 2.202 L 0.116 21.519 C 0.116 22.889 1.227 24 2.597 24 L 21.404 24 C 22.774 24 23.885 22.889 23.885 21.519 L 23.885 2.202 C 23.884 0.986 22.898 0 21.682 0 Z M 20.125 12.473 C 20.644 13.277 20.858 14.163 20.802 15.13 C 20.694 17.016 19.389 18.604 17.552 19.046 C 14.967 19.669 12.986 18.123 12.319 16.252 C 12.21 15.948 12.159 15.63 12.095 15.267 C 12.027 15.681 11.98 16.056 11.831 16.401 C 11.134 18.018 9.947 19.004 8.166 19.2 C 6.062 19.432 4.118 18.133 3.534 16.116 C 3.284 15.253 3.359 14.369 3.466 13.491 C 3.546 12.838 3.787 12.223 4.098 11.643 C 4.155 11.537 4.155 11.459 4.088 11.358 C 3.527 10.513 3.309 9.581 3.388 8.574 C 3.43 8.035 3.56 7.52 3.805 7.038 C 4.52 5.626 6.09 4.427 8.193 4.626 C 10.042 4.801 11.755 6.396 12.023 8.19 C 12.036 8.28 12.062 8.368 12.091 8.501 C 12.135 8.26 12.167 8.062 12.209 7.865 C 12.553 6.235 14.149 4.53 16.41 4.508 C 18.702 4.487 20.4 6.284 20.72 7.954 C 20.89 8.842 20.809 9.73 20.617 10.617 C 20.505 11.134 20.307 11.625 20.093 12.109 C 20.034 12.245 20.043 12.345 20.125 12.473 Z",
    "wordpress": "M 21.469 6.825 C 22.309 8.362 22.787 10.125 22.787 12 C 22.787 15.979 20.631 19.456 17.424 21.325 L 20.719 11.798 C 21.334 10.258 21.539 9.027 21.539 7.934 C 21.539 7.529 21.513 7.154 21.469 6.824 M 13.488 6.929 C 14.135 6.899 14.72 6.824 14.72 6.824 C 15.302 6.749 15.234 5.894 14.653 5.925 C 14.653 5.925 12.898 6.06 11.773 6.06 C 10.709 6.06 8.923 5.91 8.923 5.91 C 8.338 5.88 8.262 6.765 8.848 6.795 C 8.848 6.795 9.388 6.856 9.973 6.885 L 11.653 11.49 L 9.283 18.57 L 5.354 6.9 C 6.003 6.87 6.588 6.8 6.588 6.8 C 7.173 6.725 7.104 5.87 6.523 5.904 C 6.523 5.904 4.777 6.042 3.649 6.042 C 3.449 6.042 3.211 6.034 2.959 6.027 C 4.911 3.15 8.235 1.215 12 1.215 C 14.809 1.215 17.365 2.287 19.286 4.048 C 19.24 4.045 19.195 4.039 19.145 4.039 C 18.085 4.039 17.333 4.962 17.333 5.953 C 17.333 6.843 17.846 7.596 18.393 8.484 C 18.804 9.204 19.283 10.127 19.283 11.461 C 19.283 12.376 18.929 13.455 18.462 14.94 L 17.387 18.525 L 13.487 6.915 L 13.488 6.929 Z M 12 22.784 C 10.941 22.784 9.919 22.631 8.952 22.347 L 12.189 12.941 L 15.504 22.028 C 15.528 22.081 15.554 22.129 15.582 22.177 C 14.462 22.57 13.257 22.786 12 22.786 M 1.211 12 C 1.211 10.436 1.547 8.95 2.146 7.61 L 7.29 21.709 C 3.694 19.96 1.212 16.271 1.211 12 M 12 0 C 5.385 0 0 5.385 0 12 C 0 18.615 5.385 24 12 24 C 18.615 24 24 18.615 24 12 C 24 5.385 18.615 0 12 0",
    "prestashop": "M 11.558 1.034 C 5.174 1.034 0 6.21 0 12.592 C 0 13.85 0.201 15.062 0.574 16.189 L 0.576 16.182 C 0.708 15.574 0.885 14.977 1.106 14.395 L 1.117 14.365 C 1.202 14.143 1.296 13.923 1.394 13.705 L 1.478 13.524 C 1.558 13.353 1.643 13.184 1.731 13.017 C 1.767 12.949 1.801 12.881 1.839 12.814 C 1.859 12.776 1.883 12.741 1.903 12.704 C 1.997 12.538 2.093 12.372 2.193 12.211 L 2.268 12.097 C 2.393 11.902 2.524 11.711 2.661 11.524 L 2.696 11.474 C 2.84 11.281 2.991 11.094 3.147 10.911 L 3.247 10.793 C 3.402 10.616 3.562 10.443 3.728 10.276 L 3.827 10.179 C 4.003 10.005 4.185 9.837 4.373 9.676 C 5.113 7.196 7.378 5.391 10.059 5.391 C 11.138 5.391 12.211 5.701 13.13 6.264 C 14.075 6.847 14.84 7.68 15.341 8.671 L 15.348 8.686 L 15.388 8.76 L 15.388 8.763 L 15.392 8.765 C 15.953 9.111 16.478 9.513 16.959 9.963 C 16.999 10 17.04 10.034 17.079 10.072 C 17.081 10.072 17.085 10.077 17.086 10.078 L 17.084 10.072 L 17.083 10.068 L 17.083 10.065 L 17.125 9.981 C 17.502 7.597 18.555 5.879 19.795 5.879 C 20.729 5.879 21.557 6.854 22.071 8.355 L 22.076 8.371 L 22.077 8.373 C 22.222 8.531 22.364 8.704 22.501 8.894 L 22.508 8.904 L 22.529 8.971 L 22.509 8.893 C 20.967 4.324 16.646 1.036 11.557 1.036 Z M 9.927 5.477 C 7.586 5.52 5.34 7.132 4.574 9.365 L 4.562 9.399 C 4.976 9.067 5.416 8.767 5.877 8.504 C 8.683 6.848 12.356 6.858 15.155 8.52 C 14.26 6.867 12.524 5.701 10.655 5.516 C 10.414 5.486 10.17 5.473 9.927 5.477 Z M 19.761 5.977 C 19.628 5.98 19.497 6.003 19.371 6.044 C 18.106 6.606 17.652 8.117 17.34 9.347 L 17.324 9.419 C 17.689 8.799 18.132 8.204 18.72 7.777 C 19.555 7.09 20.825 7.122 21.636 7.83 C 21.944 8.156 21.777 7.838 21.667 7.61 C 21.325 6.86 20.642 5.957 19.761 5.976 Z M 21.67 7.98 Z M 12.35 8.315 L 11.28 11.585 L 11.278 11.59 L 11.272 11.592 L 6.774 12.704 L 6.765 12.704 L 11.221 13.791 C 11.326 13.901 11.448 13.996 11.581 14.071 L 11.583 14.071 C 11.625 14.095 11.668 14.116 11.712 14.136 L 11.722 14.141 C 11.763 14.159 11.805 14.174 11.848 14.188 L 11.869 14.196 C 11.909 14.209 11.949 14.219 11.989 14.228 L 12.022 14.236 C 12.127 14.257 12.233 14.268 12.34 14.269 C 12.964 14.271 13.528 13.897 13.77 13.321 C 13.85 13.135 13.893 12.931 13.893 12.717 L 13.893 12.706 L 13.892 12.694 C 13.891 12.64 13.888 12.587 13.882 12.534 L 13.881 12.532 C 13.875 12.481 13.866 12.43 13.855 12.379 L 13.854 12.375 C 13.832 12.276 13.8 12.18 13.758 12.087 L 13.758 12.084 C 13.676 11.899 13.557 11.733 13.41 11.594 L 13.41 11.591 Z M 15.498 8.941 C 15.546 9.949 15.534 10.987 15.398 11.998 C 15.228 14.016 14.208 15.796 13.426 17.614 L 13.396 17.694 L 13.361 17.78 C 14.871 16.258 16.531 14.74 17.33 12.698 C 17.713 12.062 17.448 11.356 17.215 10.722 C 17.045 9.845 16.146 9.444 15.498 8.941 Z M 21.67 9.513 L 21.082 12.201 C 21.062 12.267 21.047 12.333 21.035 12.401 C 21.033 12.421 21.028 12.441 21.025 12.461 C 21.015 12.535 21.01 12.609 21.009 12.683 L 21.007 12.714 L 21.01 12.714 C 21.01 13.342 21.307 13.85 21.673 13.851 C 21.736 13.85 21.799 13.835 21.855 13.806 L 21.882 13.791 C 21.907 13.777 21.93 13.761 21.952 13.744 C 21.965 13.734 21.976 13.722 21.988 13.711 C 22.042 13.662 22.088 13.605 22.125 13.543 L 22.155 13.489 C 22.174 13.454 22.191 13.418 22.207 13.381 L 22.224 13.341 C 22.244 13.288 22.262 13.233 22.277 13.175 L 22.279 13.173 L 22.28 13.17 L 22.684 12.719 L 22.277 12.263 L 22.277 12.264 L 22.257 12.201 Z M 17.289 10.369 C 17.979 12.085 18.139 14.076 17.38 15.799 C 16.89 17.167 15.793 18.262 15.506 19.704 C 16.236 19.819 16.974 19.88 17.716 19.89 C 19.882 19.919 22.048 19.47 24 18.525 C 21.96 15.656 19.879 12.77 17.289 10.369 Z M 12.341 11.346 C 12.663 11.346 12.924 11.607 12.924 11.929 C 12.924 12.251 12.663 12.512 12.341 12.512 C 12.019 12.512 11.758 12.251 11.758 11.929 C 11.758 11.607 12.019 11.346 12.341 11.346 Z M 21.693 11.716 C 21.831 11.716 21.942 11.906 21.942 12.142 C 21.942 12.378 21.831 12.568 21.693 12.568 C 21.556 12.568 21.445 12.378 21.445 12.142 C 21.445 11.907 21.555 11.716 21.693 11.716 Z M 17.649 11.9 C 17.633 12.012 17.616 12.109 17.599 12.19 L 17.593 12.213 C 17.583 12.263 17.571 12.307 17.56 12.341 C 17.08 13.758 16.285 14.861 15.2 16.038 C 15.053 16.198 14.899 16.358 14.741 16.522 C 14.348 16.929 13.949 17.331 13.545 17.727 C 13.433 17.837 13.286 17.988 13.12 18.163 C 13.017 18.45 12.9 18.773 12.802 19.113 C 12.758 19.097 12.716 19.082 12.671 19.064 C 10.563 18.249 9.152 17.16 9.152 17.16 C 9.152 17.16 10.238 18.574 12.067 19.9 C 12.244 20.029 12.418 20.14 12.589 20.239 C 12.514 21.433 13.041 22.579 15.419 22.921 C 15.826 22.976 16.239 22.979 16.647 22.929 L 16.637 22.9 C 16.636 22.897 16.635 22.893 16.633 22.89 C 16.633 22.89 16.466 22.757 16.254 22.513 C 16.018 22.243 15.822 21.941 15.67 21.616 C 15.543 21.342 15.454 21.052 15.404 20.754 C 15.352 20.432 15.35 20.104 15.398 19.782 C 15.415 19.662 15.438 19.541 15.47 19.416 C 15.563 19.042 15.725 18.644 15.977 18.224 L 15.979 18.221 L 16.22 17.817 C 17.323 15.957 18.017 14.542 17.726 12.376 C 17.704 12.217 17.678 12.058 17.648 11.9 Z M 22.317 12.476 Z M 22.33 12.679 L 22.333 12.715 L 22.333 12.725 C 22.333 12.738 22.33 12.75 22.33 12.763 C 22.33 12.749 22.333 12.735 22.333 12.72 C 22.333 12.706 22.331 12.694 22.33 12.68 Z M 22.318 12.954 L 22.318 12.955 L 22.316 12.965 L 22.314 12.979 L 22.318 12.954 Z M 23.671 18.882 C 21.118 20.02 18.231 20.322 15.479 19.889 C 15.339 20.997 15.863 22.107 16.693 22.819 L 16.705 22.829 C 19.408 22.396 21.68 20.661 23.671 18.883 Z",
    "docker": "M 13.983 11.078 L 16.102 11.078 C 16.204 11.078 16.287 10.995 16.288 10.893 L 16.288 9.006 C 16.288 8.903 16.205 8.82 16.102 8.82 L 13.983 8.82 C 13.881 8.82 13.798 8.903 13.798 9.005 L 13.798 10.893 C 13.798 10.995 13.881 11.078 13.983 11.078 M 11.029 5.648 L 13.147 5.648 C 13.25 5.648 13.333 5.565 13.333 5.462 L 13.333 3.574 C 13.332 3.472 13.249 3.389 13.147 3.389 L 11.029 3.389 C 10.927 3.389 10.844 3.472 10.844 3.574 L 10.844 5.462 C 10.844 5.564 10.926 5.647 11.029 5.647 M 11.029 8.363 L 13.147 8.363 C 13.249 8.362 13.332 8.279 13.333 8.177 L 13.333 6.29 C 13.332 6.188 13.249 6.105 13.147 6.105 L 11.029 6.105 C 10.927 6.105 10.844 6.188 10.844 6.29 L 10.844 8.177 C 10.844 8.279 10.926 8.362 11.029 8.363 M 8.099 8.363 L 10.219 8.363 C 10.321 8.362 10.403 8.279 10.403 8.177 L 10.403 6.29 C 10.403 6.188 10.32 6.105 10.218 6.105 L 8.1 6.105 C 7.998 6.105 7.915 6.188 7.915 6.29 L 7.915 8.177 C 7.915 8.279 7.998 8.362 8.1 8.363 M 5.136 8.363 L 7.255 8.363 C 7.357 8.362 7.44 8.279 7.44 8.177 L 7.44 6.29 C 7.44 6.188 7.357 6.105 7.255 6.105 L 5.136 6.105 C 5.034 6.105 4.951 6.188 4.95 6.29 L 4.95 8.177 C 4.95 8.279 5.034 8.362 5.136 8.363 M 11.029 11.078 L 13.147 11.078 C 13.249 11.078 13.332 10.995 13.333 10.893 L 13.333 9.006 C 13.333 8.903 13.25 8.82 13.147 8.82 L 11.029 8.82 C 10.927 8.82 10.844 8.903 10.844 9.005 L 10.844 10.893 C 10.844 10.995 10.926 11.078 11.029 11.078 M 8.099 11.078 L 10.219 11.078 C 10.321 11.077 10.403 10.995 10.403 10.893 L 10.403 9.006 C 10.403 8.957 10.384 8.91 10.35 8.875 C 10.315 8.84 10.268 8.82 10.219 8.82 L 8.099 8.82 C 7.997 8.821 7.915 8.903 7.915 9.005 L 7.915 10.893 C 7.915 10.995 7.998 11.078 8.1 11.078 M 5.136 11.078 L 7.255 11.078 C 7.357 11.078 7.44 10.995 7.44 10.893 L 7.44 9.006 C 7.44 8.957 7.421 8.91 7.387 8.875 C 7.352 8.84 7.305 8.82 7.256 8.82 L 5.136 8.82 C 5.033 8.82 4.95 8.903 4.95 9.006 L 4.95 10.893 C 4.95 10.995 5.034 11.078 5.136 11.078 M 2.216 11.078 L 4.336 11.078 C 4.438 11.077 4.52 10.995 4.52 10.893 L 4.52 9.006 C 4.52 8.957 4.501 8.91 4.467 8.875 C 4.432 8.84 4.385 8.82 4.336 8.82 L 2.216 8.82 C 2.114 8.821 2.032 8.903 2.032 9.005 L 2.032 10.893 C 2.032 10.995 2.114 11.078 2.217 11.078 M 23.763 9.89 C 23.698 9.839 23.091 9.38 21.809 9.38 C 21.471 9.381 21.133 9.41 20.799 9.467 C 20.551 7.767 19.146 6.937 19.083 6.901 L 18.739 6.702 L 18.513 7.029 C 18.229 7.467 18.023 7.951 17.901 8.459 C 17.671 9.429 17.811 10.341 18.304 11.12 C 17.709 11.452 16.754 11.533 16.56 11.54 L 0.751 11.54 C 0.338 11.541 0.003 11.875 0.001 12.288 C -0.018 13.673 0.217 15.049 0.693 16.35 C 1.238 17.778 2.048 18.83 3.103 19.474 C 4.283 20.197 6.203 20.611 8.378 20.611 C 9.361 20.614 10.341 20.525 11.308 20.345 C 12.651 20.098 13.943 19.629 15.131 18.956 C 16.111 18.389 16.991 17.668 17.741 16.82 C 18.993 15.402 19.739 13.823 20.294 12.42 L 20.515 12.42 C 21.887 12.42 22.73 11.871 23.195 11.411 C 23.504 11.118 23.745 10.761 23.902 10.365 L 24 10.077 Z",
    // Mailpit (correo de pruebas): su logotipo (server/ui/mailpit.svg de la 1.32.0, MIT), con sus dos
    // trazos llevados a la caja de 24x24, en un solo color
    "mailpit": "M 2.235 0.96 L 12.006 10.742 L 21.836 0.96 Z M 0.935 2.597 L 11.973 13.423 L 23.078 2.631 L 23.044 9.313 L 12.141 13.757 L 14.892 16.046 L 13.416 17.132 L 5.867 17.165 C 4.989 17.161 1.172 13.838 0.935 9.681 Z M 14.22 14.031 L 24 10.098 L 22.543 20.496 L 20.394 18.839 C 16.452 23.043 12.184 23.608 8.058 22.619 C 3.932 21.63 2.228 18.81 0.935 16.163 C -0.358 13.516 -0.122 10.596 0.516 7.993 C 0.721 9.9 0.278 10.953 1.673 14.091 C 2.818 16.159 4.288 17.795 6.37 18.618 C 8.892 19.742 12.22 19.227 13.935 18.067 L 16.518 15.862 Z",
]

/// Números de una versión ("5.2.1" → [5, 2, 1])
func verParts(_ v: String) -> [Int] {
    return Array(v.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.prefix(3))
}

/// ¿Tiene la versión un phpMyAdmin con fallos de seguridad ya corregidos? Lo mínimo: 5.2.2 desde
/// PHP 7.2.5, 5.1.4 desde la 7.1.3 y 4.9.11 antes
func pmaOutdated(_ php: String, _ pma: String) -> Bool {
    let p = verParts(php), m = verParts(pma)
    if p.isEmpty { return false }
    if m.isEmpty { return true }
    let need: [Int] = p.lexicographicallyPrecedes([7, 2, 5]) ? (p.lexicographicallyPrecedes([7, 1, 3]) ? [4, 9, 11] : [5, 1, 4]) : [5, 2, 2]
    return m.lexicographicallyPrecedes(need)
}

func hexColor(_ v: UInt32) -> Color {
    return Color(red: Double((v >> 16) & 0xFF) / 255.0, green: Double((v >> 8) & 0xFF) / 255.0,
                 blue: Double(v & 0xFF) / 255.0)
}

/// Color de cada marca (el fondo de su icono)
let LOGO_COLORS: [String: Color] = [
    "log": hexColor(0x16A34A), "actualizar": hexColor(0x3584E4), "imagenes": hexColor(0x3584E4),
    "php": hexColor(0x777BB4), "apache": hexColor(0xD22128), "mariadb": hexColor(0x003545),
    "phpmyadmin": hexColor(0x6C78AF), "perl": hexColor(0x39457E), "xampp": hexColor(0xFB7A24),
    "wordpress": hexColor(0x21759B), "prestashop": hexColor(0xDF0067), "mailpit": hexColor(0x00A87B), "docker": hexColor(0x2496ED),
    "cloudflare": hexColor(0xF38020), "github": hexColor(0x181717),
    "bbdd": hexColor(0x0284C7), "node": hexColor(0x5FA04E),
]

/// Los que se dibujan con trazo, no rellenos
let LOGO_STROKED: Set<String> = ["imagenes"]

func brand(_ name: String) -> Color { return LOGO_COLORS[name] ?? .gray }

/// Dibuja el trazo de un logotipo (solo M, L, C y Z) escalado a su marco
struct LogoShape: Shape {
    let d: String
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let t = d.split(separator: " ")
        var i = 0
        func num(_ k: Int) -> CGFloat {
            return i + k < t.count ? CGFloat(Double(t[i + k]) ?? 0) : 0
        }
        while i < t.count {
            let c = t[i]
            i += 1
            if c == "M" {
                p.move(to: CGPoint(x: num(0), y: num(1)))
                i += 2
            } else if c == "L" {
                p.addLine(to: CGPoint(x: num(0), y: num(1)))
                i += 2
            } else if c == "C" {
                p.addCurve(to: CGPoint(x: num(4), y: num(5)), control1: CGPoint(x: num(0), y: num(1)),
                           control2: CGPoint(x: num(2), y: num(3)))
                i += 6
            } else if c == "Z" {
                p.closeSubpath()
            }
        }
        let k = min(rect.width, rect.height) / 24
        let move = CGAffineTransform(translationX: rect.minX + (rect.width - 24 * k) / 2,
                                     y: rect.minY + (rect.height - 24 * k) / 2)
        return p.applying(move.scaledBy(x: k, y: k))
    }
}

/// Icono de color, como en Ajustes del Sistema: símbolo blanco sobre un cuadrado redondeado. Con
/// «logo:<paquete>», el logotipo original del paquete en blanco sobre el color de su marca
struct ColorIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27)
            .fill(LinearGradient(colors: [color.opacity(0.8), color], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(glyph())
    }

    @ViewBuilder
    func glyph() -> some View {
        if symbol.hasPrefix("logo:") {
            LogoShape(d: LOGO_PATHS[String(symbol.dropFirst(5))] ?? "")
                .fill(Color.white)
                .frame(width: size * 0.64, height: size * 0.64)
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

/// Icono del logotipo de un paquete
func LogoIcon(_ name: String, size: CGFloat = 22) -> ColorIcon {
    return ColorIcon(symbol: "logo:" + name, color: brand(name), size: size)
}

/// Icono de cada apartado, por el principio de su título
let SECTION_ICONS: [(String, String, Color)] = [
    ("Cargar proyecto", "folder.fill", .blue),
    ("Versión activa", "logo:php", brand("php")),
    ("Instalar nuevas versiones de PHP", "logo:php", brand("php")),
    ("Instaladas", "logo:xampp", brand("xampp")),
    ("Hay procesos de otras versiones", "exclamationmark.triangle.fill", .orange),
    ("Hay un XAMPP oficial", "logo:xampp", brand("xampp")),
    ("XAMPP oficial", "logo:xampp", brand("xampp")),
    ("No se han podido leer", "xmark.octagon.fill", .red),
    ("BBDD por versión", "logo:mariadb", brand("mariadb")),
    ("Buscar una BBDD", "magnifyingglass", .gray),
    ("Subir o actualizar una BBDD", "square.and.arrow.up.fill", .blue),
    ("Se puede entrar desde otros equipos", "network", .red),
    ("phpMyAdmin antiguo", "logo:phpmyadmin", brand("phpmyadmin")),
    ("Servicios", "server.rack", GREEN),
    ("Host falseado", "lock.shield.fill", .indigo),
    ("Nuevo proyecto con dominio falseado", "folder.badge.plus", GREEN),
    ("Dominios de los vhosts", "logo:apache", brand("apache")),
    ("Configuración", "gearshape.fill", .gray),
    ("Carpetas", "folder.fill", .cyan),
    ("Registro de errores", "doc.text.fill", .pink),
    ("Información", "info", .gray),
]

/// Icono de cada fila, por su título: los títulos de los apartados no llevan icono, lo llevan las
/// filas que contienen. Exactos (títulos cortos) y por el principio
let ROW_ICONS_EXACT: [String: (String, Color)] = [
    "Dominio": ("globe", .blue),
    "Carpeta": ("folder.fill", .cyan),
    "BBDD": ("logo:mariadb", brand("mariadb")),
    "Proyecto": ("folder.fill", .blue),
    "Novedades": ("star.fill", .yellow),
    "Acerca de": ("info", .gray),
    "error_log": ("logo:apache", brand("apache")),
]
let ROW_ICONS: [(String, String, Color)] = [
    ("Versiones sin proteger", "network", .red),
    ("Abierto a la red", "network", .red),
    ("web.local → ", "exclamationmark.triangle.fill", .orange),
    ("phpMyAdmin con fallos", "logo:phpmyadmin", brand("phpmyadmin")),
    ("MariaDB de XAMPP-", "logo:mariadb", brand("mariadb")),
    ("Proyectos con https", "lock.trianglebadge.exclamationmark", .orange),
    ("Proyectos que avisan", "exclamationmark.shield", .orange),
    ("Webs reales que acepta", "exclamationmark.shield", .red),
    ("Procesos que sobran", "exclamationmark.triangle.fill", .orange),
    ("XAMPP oficial", "logo:xampp", brand("xampp")),
    ("Hay un XAMPP oficial", "logo:xampp", brand("xampp")),
    ("No hay ningún XAMPP oficial", "logo:xampp", brand("xampp")),
    ("PHP ", "logo:php", brand("php")),
    ("Ninguna versión activa", "logo:php", brand("php")),
    ("No hay ninguna versión", "logo:php", brand("php")),
    ("Ningún dominio falseado", "lock.shield.fill", .indigo),
    ("No hay más dominios", "logo:apache", brand("apache")),
    ("Fichero SQL", "doc.text.fill", .blue),
    ("BBDD de destino", "logo:mariadb", brand("mariadb")),
    ("BBDD de ", "logo:mariadb", brand("mariadb")),
    ("Virtual hosts", "logo:apache", brand("apache")),
    ("Hosts del sistema", "server.rack", .gray),
    ("Copias de seguridad", "externaldrive.fill", .gray),
    ("Registros de instalaciones", "clock.arrow.circlepath", .gray),
    ("error_log de ", "logo:apache", brand("apache")),
    ("Comandos de lvm-instalador", "terminal.fill", .black),
    // Los pasos de una instalación o actualización (la lista de la ventana de la tarea)
    ("Descargas", "arrow.down.circle.fill", .blue),
    ("Descarga de XAMPP", "logo:xampp", brand("xampp")),
    ("Instalador oficial de XAMPP", "logo:xampp", brand("xampp")),
    ("Apache ", "logo:apache", brand("apache")),
    ("Perl ", "logo:perl", brand("perl")),
    ("ProFTPD ", "arrow.up.arrow.down", .gray),
    ("MariaDB ", "logo:mariadb", brand("mariadb")),
    ("phpMyAdmin ", "logo:phpmyadmin", brand("phpmyadmin")),
    ("Configuracion", "gearshape.fill", .gray),
    // Correo de pruebas: el logotipo de Mailpit en todas sus filas
    ("Correo de pruebas", "logo:mailpit", brand("mailpit")),
    ("Mailpit", "logo:mailpit", brand("mailpit")),
    ("Bandeja de entrada", "logo:mailpit", brand("mailpit")),
    ("WordPress con plugins", "logo:wordpress", brand("wordpress")),
]

func rowIcon(_ title: String) -> (String, Color)? {
    if let hit = ROW_ICONS_EXACT[title] { return hit }
    guard let hit = ROW_ICONS.first(where: { title.hasPrefix($0.0) }) else { return nil }
    return (hit.1, hit.2)
}

func sectionIcon(_ title: String) -> (String, Color)? {
    guard let hit = SECTION_ICONS.first(where: { title.hasPrefix($0.0) }) else { return nil }
    return (hit.1, hit.2)
}

struct Card<Content: View>: View {
    let title: String?
    let description: String?
    let content: Content
    init(_ title: String? = nil, _ description: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.description = description
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // La explicación va en el símbolo de información: se ve al pasar el ratón
            if title != nil || description != nil {
                // (los títulos no llevan icono: lo llevan las filas)
                HStack(spacing: 6) {
                    if let t = title { Text(t).font(.headline) }
                    if let d = description {
                        Image(systemName: "info.circle").foregroundColor(.secondary).tip(d)
                    }
                }
            }
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                .padding(.top, 4)
        }
    }
}

/// Como Card, pero se pliega y se despliega al pulsar el título (se recuerda en FOLDED_FILE).
/// Plegada, al lado del título sale el resumen
struct FoldCard<Content: View>: View {
    @EnvironmentObject var model: AppModel
    let key: String
    let title: String
    let description: String?
    let summary: String
    let content: Content
    init(_ key: String, _ title: String, _ description: String? = nil, summary: String = "",
         @ViewBuilder content: () -> Content) {
        self.key = key
        self.title = title
        self.description = description
        self.summary = summary
        self.content = content()
    }
    var body: some View {
        let open = !model.folded.contains(key)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button(action: { model.setFolded(key, open) }) {
                    HStack(spacing: 6) {
                        Text(title).font(.headline).foregroundColor(.primary)
                        Image(systemName: open ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle()).hoverPointer()
                .tip(open ? "Plegar" : "Desplegar")
                if let d = description {
                    Image(systemName: "info.circle").foregroundColor(.secondary).tip(d)
                }
                if !open && !summary.isEmpty {
                    Text(summary).font(.callout).foregroundColor(.secondary)
                }
            }
            if open {
                VStack(spacing: 0) { content }
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .padding(.top, 4)
            }
        }
    }
}

struct Row<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    let leading: Leading
    let trailing: Trailing
    init(_ title: String, _ subtitle: String? = nil, @ViewBuilder leading: () -> Leading,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading()
        self.trailing = trailing()
    }
    var body: some View {
        HStack(spacing: 10) {
            // Su icono, por el título, si la fila no trae otro
            if Leading.self == EmptyView.self, let ic = rowIcon(title) {
                ColorIcon(symbol: ic.0, color: ic.1, size: 20)
            }
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let s = subtitle, !s.isEmpty {
                    Text(s).font(.caption).foregroundColor(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
    }
}

extension Row where Leading == EmptyView {
    init(_ title: String, _ subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(title, subtitle, leading: { EmptyView() }, trailing: trailing)
    }
}

extension Row where Leading == EmptyView, Trailing == EmptyView {
    init(_ title: String, _ subtitle: String? = nil) {
        self.init(title, subtitle, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

/// ¿Va un apartado de Configuración a lo ancho? (sus tarjetas, en horizontal y con los botones a la derecha)
private struct TileWideKey: EnvironmentKey {
    static let defaultValue = false
}

struct TileRowKey: EnvironmentKey {
    static let defaultValue = false
}

/// En Configuración, el nombre del apartado abierto: su tarjeta no repite el título (va arriba, en grande)
struct ToolsSectionKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

/// La explicación de la tarjeta del apartado abierto, para ponerla debajo del título grande
struct ToolsDescKey: PreferenceKey {
    static var defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) {
        if value == nil { value = nextValue() }
    }
}

extension EnvironmentValues {
    var tileRow: Bool {
        get { self[TileRowKey.self] }
        set { self[TileRowKey.self] = newValue }
    }
    var toolsSection: String? {
        get { self[ToolsSectionKey.self] }
        set { self[ToolsSectionKey.self] = newValue }
    }
    var tileWide: Bool {
        get { self[TileWideKey.self] }
        set { self[TileWideKey.self] = newValue }
    }
}

/// Apartado de Configuración con sus ajustes en tarjetas de dos en dos (Tile), como los visores de las
/// otras pestañas. wide: una tarjeta (o una lista) a lo ancho, con sus botones a la derecha
struct TileCard<Content: View>: View {
    let title: String?
    let description: String?
    let wide: Bool
    let columns: Int
    /// Con tiles, en tarjetas (Docker y el correo de pruebas); si no, en filas (desde la 1.41.0)
    let tiles: Bool
    let lead: AnyView?
    let tail: AnyView?
    let content: Content
    @Environment(\.toolsSection) var toolsSection
    init(_ title: String? = nil, _ description: String? = nil, wide: Bool = false, columns: Int = 2, tiles: Bool = false,
         lead: AnyView? = nil, tail: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.description = description
        self.wide = wide
        self.columns = columns
        self.tiles = tiles
        self.lead = lead
        self.tail = tail
        self.content = content()
    }
    /// La tarjeta del apartado abierto de Configuración: su título y su explicación van arriba, en grande
    var isSectionCard: Bool {
        guard let s = toolsSection, let t = title else { return false }
        return t.hasPrefix(s)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isSectionCard {
                // (su icono y su interruptor van con el título grande)
                EmptyView()
            } else if title != nil || description != nil {
                HStack(spacing: 6) {
                    if let l = lead { l }
                    if let t = title { Text(t).font(.headline) }
                    if let d = description {
                        Image(systemName: "info.circle").foregroundColor(.secondary).tip(d)
                    }
                    if let r = tail { r.padding(.leading, 6) }
                }
            }
            Group {
                if !tiles {
                    // (en filas: una lista con sus líneas, como en Linux)
                    VStack(spacing: 0) { content }
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                } else if wide {
                    VStack(spacing: 12) { content }
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: columns),
                              alignment: .leading, spacing: 12) { content }
                }
            }
            .environment(\.tileWide, wide || !tiles)
            .environment(\.tileRow, !tiles)
            .padding(.top, 4)
        }
        .preference(key: ToolsDescKey.self, value: isSectionCard ? description : nil)
    }
}

/// Un ajuste de Configuración en su tarjeta: el icono (por su título) y el título arriba, la explicación
/// entera debajo y sus botones abajo a la derecha. En un apartado a lo ancho, todo en una línea
struct Tile<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    let leading: Leading
    let trailing: Trailing
    @Environment(\.tileWide) var wide
    @Environment(\.tileRow) var row
    init(_ title: String, _ subtitle: String? = nil, @ViewBuilder leading: () -> Leading,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading()
        self.trailing = trailing()
    }
    var body: some View {
        Group {
            if wide {
                HStack(spacing: 12) {
                    icon
                    texts
                    Spacer(minLength: 8)
                    trailing
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        icon
                        texts
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        trailing
                    }
                }
            }
        }
        .padding(row ? 12 : 14)
        .frame(maxWidth: .infinity, minHeight: wide ? 0 : 118, alignment: .topLeading)
        .background(row ? nil : RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
        .overlay(row ? nil : RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12), lineWidth: 1))
        // (en filas, una línea debajo de cada una)
        .overlay(row ? Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) : nil, alignment: .bottom)
    }
    @ViewBuilder var icon: some View {
        if Leading.self == EmptyView.self, let ic = rowIcon(title) {
            ColorIcon(symbol: ic.0, color: ic.1, size: 20)
        }
        leading
    }
    var texts: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).fontWeight(.semibold).fixedSize(horizontal: false, vertical: true)
            if let sub = subtitle, !sub.isEmpty {
                Text(sub).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension Tile where Leading == EmptyView {
    init(_ title: String, _ subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(title, subtitle, leading: { EmptyView() }, trailing: trailing)
    }
}

extension Tile where Leading == EmptyView, Trailing == EmptyView {
    init(_ title: String, _ subtitle: String? = nil) {
        self.init(title, subtitle, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

/// Fila que despliega una lista anidada al pulsarla
struct Expander<Trailing: View, Inner: View>: View {
    @EnvironmentObject var model: AppModel
    let key: String
    let title: String
    let subtitle: String?
    let tag: String?
    /// Fecha (en gris, junto al título), como la de la lista de Instalar
    let date: String?
    let icon: (String, Color)?
    let trailing: Trailing
    let inner: Inner
    init(_ key: String, _ title: String, _ subtitle: String?, tag: String? = nil, date: String? = nil,
         icon: (String, Color)? = nil,
         @ViewBuilder trailing: () -> Trailing, @ViewBuilder inner: () -> Inner) {
        self.key = key
        self.title = title
        self.subtitle = subtitle
        self.tag = tag
        self.date = date
        self.icon = icon
        self.trailing = trailing()
        self.inner = inner()
    }
    var open: Bool { return model.expanded.contains(key) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let ic = icon {
                    ColorIcon(symbol: ic.0, color: ic.1, size: 20)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Text(title)
                            if let dt = date {
                                Text(fmtDay(dt)).font(.caption).foregroundColor(.secondary)
                                    .tip("Publicada en php.net el \(fmtDay(dt))")
                            }
                        }
                        if let t = tag { ActiveTag(text: t) }
                    }
                    if let s = subtitle { Text(s).font(.caption).foregroundColor(.secondary) }
                }
                Spacer(minLength: 8)
                trailing
                Image(systemName: open ? "chevron.up" : "chevron.down").foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .onTapGesture {
                if open { model.expanded.remove(key) } else { model.expanded.insert(key) }
            }
            if open {
                Divider()
                VStack(spacing: 0) { inner }.background(Color.primary.opacity(0.03))
            }
        }
    }
}

struct Loading: View {
    var text = "Leyendo…"
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.6)
            Text(text).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

/// Base de una tienda PrestaShop: suelen llamarse ps_<tienda>
func isPsDb(_ db: String) -> Bool { db.lowercased().hasPrefix("ps_") }

struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color? = nil
    /// Más grande (arrancar, reiniciar y parar la versión activa: los que más se usan)
    var big = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).foregroundColor(tint)
                .font(big ? .system(size: 20, weight: .medium) : .body)
                .frame(width: big ? 36 : nil, height: big ? 36 : nil)
                .contentShape(Rectangle())
        }
            .buttonStyle(BorderlessButtonStyle())
            .hoverPointer()
            .tip(help)
    }
}

// MARK: - Aspecto de la ventana (desde la 1.39: como la de Linux 1.54)

/// Azul de los botones principales, de lo elegido y del borde de los botones al pasar el ratón
let ACCENT = hexColor(0x0A84FF)
/// Tema de la ventana elegido en el menú: claro u oscuro (sin fichero, el del Mac)
let THEME_FILE = LOG_DIR + "/ventana-tema"
/// Página de descarga de Docker Desktop (en el Mac no se instala desde aquí)
let DOCKER_DOWNLOAD = "https://www.docker.com/products/docker-desktop/"

/// Botón con un borde gris claro que se pone azul al pasar el ratón, sin relieve. kind: "" (normal),
/// primary (azul con letras blancas), stop (rojo), play (verde) o dashed (borde discontinuo). big: los
/// de los diálogos y las tareas (34 de alto, como en Linux)
struct OutlineButton: ButtonStyle {
    var kind = ""
    var compact = false
    var big = false
    func makeBody(configuration: Configuration) -> some View {
        OutlineBody(configuration: configuration, kind: kind, compact: compact, big: big)
    }
}

struct OutlineBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: String
    let compact: Bool
    var big = false
    @Environment(\.isEnabled) var enabled
    @Environment(\.colorScheme) var scheme
    @State private var hover = false

    var body: some View {
        let on = hover && enabled
        let primary = kind == "primary"
        // («encendido», el de los servicios de arriba: verde, salvo en el tema claro, donde el verde no se
        // ve sobre el gris: azul)
        let colored = kind == "stop" || kind == "play" || kind == "encendido"
        let tint: Color = kind == "stop" ? RED : (kind == "play" ? GREEN
            : (kind == "encendido" ? (scheme == .dark ? GREEN : ACCENT) : ACCENT))
        let text: Color = primary ? Color.white : (colored ? tint : (on ? ACCENT : Color.primary))
        // («compartiendo»: un túnel de Cloudflare abierto, con el borde y el fondo en su naranja)
        let share = kind == "compartiendo"
        let fill: Color = primary ? ACCENT.opacity(configuration.isPressed ? 0.75 : (on ? 0.88 : 1))
            : (share ? CLOUDFLARE.opacity(0.10) : Color.primary.opacity(configuration.isPressed ? 0.10 : 0.03))
        let border: Color = primary ? Color.clear : (on ? tint : (share ? CLOUDFLARE : Color.primary.opacity(0.16)))
        let shape = RoundedRectangle(cornerRadius: big ? 8 : 7)
        return configuration.label
            .font(.system(size: big ? 13 : 12.5, weight: primary ? .semibold : .regular))
            .foregroundColor(text)
            .padding(.horizontal, big ? 18 : (compact ? 7 : 12))
            .padding(.vertical, big ? 4 : (compact ? 4 : 6))
            .frame(minHeight: big ? 34 : nil)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, style: StrokeStyle(lineWidth: 1, dash: kind == "dashed" ? [4, 3] : [])))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(shape)
            .animation(.easeOut(duration: 0.12), value: on)
            .onHover { hover = $0 }
            .hoverPointer()
    }
}

/// Botón sin borde (vincular) cuyo icono se pone azul al pasar el ratón
struct LinkHoverButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LinkHoverBody(configuration: configuration)
    }
}

struct LinkHoverBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) var enabled
    @State private var hover = false

    var body: some View {
        let on = hover && enabled
        return configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(on ? ACCENT : Color.secondary)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(ACCENT.opacity(on ? 0.12 : 0)))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .hoverPointer()
    }
}

/// Menú desplegable con el aspecto de OutlineButton. Sin borde (bordered: false), solo al pasar el ratón
struct OutlineMenu<Items: View>: View {
    let title: String?
    let symbol: String
    let bordered: Bool
    let items: Items
    @State private var hover = false

    init(_ title: String?, symbol: String, bordered: Bool = true, @ViewBuilder items: () -> Items) {
        self.title = title
        self.symbol = symbol
        self.bordered = bordered
        self.items = items()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7)
        return Menu {
            items
        } label: {
            if let t = title {
                Label(t, systemImage: symbol)
            } else {
                Image(systemName: symbol)
            }
        }
        .menuStyle(BorderlessButtonMenuStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, title == nil ? 7 : 11)
        .padding(.vertical, 5)
        .background(shape.fill(Color.primary.opacity(bordered || hover ? 0.03 : 0)))
        .overlay(shape.stroke(hover ? ACCENT : Color.primary.opacity(bordered ? 0.16 : 0), lineWidth: 1))
        .contentShape(shape)
        .onHover { hover = $0 }
        .hoverPointer()
    }
}

/// Botón de una tabla con solo un icono
func iconAction(_ symbol: String, _ tip: String, kind: String = "", _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: symbol).frame(width: 14, height: 14)
    }
    .buttonStyle(OutlineButton(kind: kind, compact: true))
    .tip(tip)
}

/// Botón de una tabla con el logotipo de un paquete
func logoAction(_ logo: String, _ tip: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        LogoShape(d: LOGO_PATHS[logo] ?? "").fill(brand(logo)).frame(width: 14, height: 14)
    }
    .buttonStyle(OutlineButton(compact: true))
    .tip(tip)
}

/// Punto de estado: verde y latiendo despacio si está en marcha, gris si no
struct StatusDot: View {
    let on: Bool
    var size: CGFloat = 8
    var blink = true
    @State private var dim = false

    var body: some View {
        Circle().fill(on ? GREEN : Color.secondary.opacity(0.45))
            .frame(width: size, height: size)
            .opacity(on && blink && dim ? 0.3 : 1)
            .onAppear { pulse() }
            .onChange(of: on) { _ in pulse() }
    }

    func pulse() {
        guard on && blink else {
            dim = false
            return
        }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { dim = true }
    }
}

/// Recuadro hundido suave (el visor de arriba, el entorno y la BBDD del proyecto): algo más oscuro
/// que la ventana, con una sombra fina por dentro
struct SoftSunken: View {
    var radius: CGFloat = 10
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        return shape.fill(Color.primary.opacity(0.05))
            .overlay(shape.stroke(Color.black.opacity(0.16), lineWidth: 2).blur(radius: 1.5).offset(y: 1).mask(shape))
            .overlay(shape.stroke(Color.primary.opacity(0.10), lineWidth: 1))
    }
}

/// Etiqueta pequeña (WordPress, Activa, Cargado), gris o azul
struct SmallTag: View {
    let text: String
    var blue = false
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(blue ? ACCENT : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill((blue ? ACCENT : Color.secondary).opacity(0.14)))
    }
}

/// Versión en una fila de proyectos (8.4) o su entorno de Docker
struct Chip: View {
    let text: String
    var docker = false
    var body: some View {
        HStack(spacing: 4) {
            if docker {
                LogoShape(d: LOGO_PATHS["docker"] ?? "").fill(brand("docker")).frame(width: 11, height: 11)
            }
            Text(text)
        }
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundColor(docker ? brand("docker") : Color.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill((docker ? brand("docker") : Color.primary).opacity(0.08)))
    }
}

/// «En marcha» en verde con su punto latiendo, o «Parado» en gris
struct RunPill: View {
    let on: Bool
    var body: some View {
        HStack(spacing: 6) {
            if on { StatusDot(on: true, size: 7) }
            Text(on ? "En marcha" : "Parado")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(on ? GREEN : Color.secondary)
        }
    }
}

/// Logotipo del tipo de proyecto: WordPress, PrestaShop o una carpeta
struct KindIcon: View {
    let kind: String
    var size: CGFloat = 18
    @ViewBuilder
    var body: some View {
        if kind == "wp" || kind == "ps" {
            let name = kind == "wp" ? "wordpress" : "prestashop"
            LogoShape(d: LOGO_PATHS[name] ?? "").fill(brand(name)).frame(width: size, height: size)
        } else {
            Image(systemName: "folder").font(.system(size: size * 0.8)).foregroundColor(.secondary)
                .frame(width: size, height: size)
        }
    }
}

/// Tarjeta con una cifra (arriba de Bases de datos y de Docker)
struct StatCard: View {
    let title: String
    let value: String
    let sub: String
    var progress: Double? = nil
    var action: (String, () -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(title).font(.caption).foregroundColor(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                if let a = action {
                    Button(a.0, action: a.1).buttonStyle(OutlineButton(compact: true))
                }
            }
            Text(value).font(.system(size: 22, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            if let p = progress {
                ProgressView(value: max(0, min(1, p))).progressViewStyle(LinearProgressViewStyle(tint: ACCENT))
            }
            Text(sub).font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

/// Buscador con lupa y botón de borrar
struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField(placeholder, text: $text).textFieldStyle(PlainTextFieldStyle())
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
                .hoverPointer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15), lineWidth: 1))
    }
}

extension View {
    /// Celda de una tabla: ancho fijo (0: el que quede), a la izquierda o, con align, donde se diga
    @ViewBuilder
    func col(_ w: CGFloat, align: Alignment = .leading) -> some View {
        if w > 0 {
            frame(width: w, alignment: align)
        } else {
            frame(maxWidth: .infinity, alignment: align)
        }
    }
}

/// Tabla: un recuadro con las filas separadas por líneas
struct TableBox<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.025)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

/// Cabecera de una tabla: los títulos en mayúsculas pequeñas, cada uno con su ancho (0: el resto).
/// lastRight: el último, a la derecha (sobre unas acciones pegadas al borde)
struct TableHead: View {
    let cols: [(String, CGFloat)]
    var lastRight = false
    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(cols.enumerated()), id: \.offset) { i, c in
                Text(c.0.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.secondary)
                    .col(c.1, align: lastRight && i == cols.count - 1 ? .trailing : .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }
}

/// Fila de una tabla: algo más clara al pasar el ratón (content recibe si lo está, para enseñar
/// entonces «Cargar» o «Activar») y azul si es la elegida. Al pulsarla, action
struct HoverRow<Content: View>: View {
    let selected: Bool
    let action: (() -> Void)?
    let content: (Bool) -> Content
    @State private var hover = false

    init(selected: Bool = false, action: (() -> Void)? = nil, @ViewBuilder content: @escaping (Bool) -> Content) {
        self.selected = selected
        self.action = action
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        let row = HStack(spacing: 12) { content(hover) }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(selected ? ACCENT.opacity(0.10) : Color.primary.opacity(hover ? 0.035 : 0))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
        if let a = action {
            row.onTapGesture(perform: a)
        } else {
            row
        }
    }
}

/// Página ancha (las tablas): con desplazamiento y centrada
struct WidePage<Content: View>: View {
    let width: CGFloat
    /// Al cambiar, la página sube hasta arriba poco a poco (como al deslizar)
    let top: Int
    let content: Content
    init(width: CGFloat = 980, top: Int = 0, @ViewBuilder content: () -> Content) {
        self.width = width
        self.top = top
        self.content = content()
    }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) { content }
                    .frame(maxWidth: width, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .id("arriba")
            }
            .onChange(of: top) { _ in
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("arriba", anchor: .top) }
            }
        }
    }
}

/// Título grande de una página, con su explicación debajo. Delante, un símbolo (Dominios y hosts,
/// Configuración) o el logotipo de un paquete en su color (Versiones de PHP, como la ballena de Docker)
struct PageTitle: View {
    let title: String
    let sub: String
    var symbol: String? = nil
    var logo: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                if let l = logo {
                    LogoShape(d: LOGO_PATHS[l] ?? "").fill(brand(l)).frame(width: 30, height: 30)
                } else if let sym = symbol {
                    Image(systemName: sym).font(.system(size: 22, weight: .medium)).frame(width: 30, height: 30)
                }
                Text(title).font(.system(size: 22, weight: .bold))
            }
            if !sub.isEmpty {
                Text(sub).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}

/// Número con coma decimal (12,5 %)
func fmtPercent(_ v: Double) -> String {
    return String(format: "%.1f %%", v).replacingOccurrences(of: ".", with: ",")
}

/// Versión corta de PHP para las etiquetas (8.4.12 → 8.4)
func shortPhp(_ php: String) -> String {
    let parts = php.split(separator: ".")
    return parts.count >= 3 ? parts.prefix(2).joined(separator: ".") : php
}

/// Avisos que van en el botón de avisos de arriba (los mismos que pone WarningsView)
func warningCount(_ d: AppData) -> Int {
    var n = 0
    if d.official { n += 1 }
    if !d.dbsysVersion.isEmpty { n += 1 }
    if d.installs.contains(where: { pmaOutdated($0.php, $0.pma) }) { n += 1 }
    if !d.unsecured.isEmpty { n += 1 }
    if !d.certs.isEmpty || !d.cas.isEmpty { n += 1 }
    if !d.untrusted.isEmpty { n += 1 }
    if !d.stale.isEmpty { n += 1 }
    if !d.stray.isEmpty { n += 1 }
    if d.installs.contains(where: { php2shellVulnerable(d.php2shell[$0.folder] ?? "ok") }) { n += 1 }
    return n
}

/// Ventanas que se abren encima de la página (Componentes, Instalar versión, Proyecto en Docker): no
/// son hojas de SwiftUI, para que la de la tarea pueda abrirse en cuanto se pulse su botón
enum Panel: Identifiable, Equatable {
    case components(String)
    case install
    case dockerNew
    case buttons

    var id: String {
        switch self {
        case .components(let f): return "c" + f
        case .install: return "i"
        case .dockerNew: return "d"
        case .buttons: return "b"
        }
    }
    var title: String {
        switch self {
        case .components: return "Componentes"
        case .install: return "Instalar versión"
        case .dockerNew: return "Proyecto en Docker"
        case .buttons: return "Botones del proyecto"
        }
    }
    var width: CGFloat {
        switch self {
        case .components: return 760
        case .install: return 720
        case .dockerNew: return 620
        case .buttons: return 900
        }
    }
}

/// Recuadro de una de esas ventanas, centrado sobre la página oscurecida
struct PanelBox<Content: View>: View {
    let title: String
    let width: CGFloat
    let close: () -> Void
    let content: Content
    init(title: String, width: CGFloat, close: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.width = width
        self.close = close
        self.content = content()
    }
    var body: some View {
        ZStack {
            // (pulsar fuera no la cierra: se cierra con su botón o con Esc)
            Color.black.opacity(0.28).contentShape(Rectangle()).onTapGesture {}
            VStack(alignment: .leading, spacing: 0) {
                // (el título, centrado, como en los diálogos; el botón de cerrar, a la derecha)
                ZStack {
                    Text(title).font(.headline).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    HStack {
                        Spacer()
                        Button(action: close) { Image(systemName: "xmark") }
                            .buttonStyle(OutlineButton(compact: true))
                            .keyboardShortcut(.cancelAction)
                            .tip("Cerrar")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                Divider()
                content.padding(18)
            }
            .frame(width: width)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.3), radius: 24, y: 8)
        }
    }
}

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

// MARK: - Acciones de la ventana nueva

extension AppModel {
    /// Cambia de apartado y lee lo que haga falta
    /// Abre Configuración en ese apartado (su clave de ToolsView.sections)
    func openTools(_ section: String) {
        toolsSection = section
        openTab("config")
    }

    func openTab(_ key: String) {
        tab = key
        // Al entrar en un apartado, sus desplegables aparecen plegados (las versiones de Bases de datos
        // y los proyectos de Docker; con una búsqueda se siguen viendo desplegados)
        expanded = expanded.filter { !$0.hasPrefix("@db") }
        dkOpen = []
        if key == "docker" { reloadDocker(stats: true) }
        if key == "node" { reloadNode() }
        if key == "repos" {
            if repos == nil { reloadRepos(cache: true) }
            reloadRepos()
        }
        if key == "bbdd" {
            refreshBackups()
            reloadDbSizes()
        }
    }

    var isDark: Bool {
        return dark ?? (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }

    /// Pone el tema guardado (solo en esta ventana)
    func applyTheme() {
        if dark == nil {
            let saved = ((try? String(contentsOfFile: THEME_FILE, encoding: .utf8)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if saved == "oscuro" { dark = true } else if saved == "claro" { dark = false }
        }
        if let dk = dark { NSApp.appearance = NSAppearance(named: dk ? .darkAqua : .aqua) }
    }

    func toggleTheme() {
        dark = !isDark
        applyTheme()
        try? FileManager.default.createDirectory(atPath: LOG_DIR, withIntermediateDirectories: true)
        try? ((dark ?? false) ? "oscuro\n" : "claro\n").write(toFile: THEME_FILE, atomically: true, encoding: .utf8)
    }

    /// Botón de encender o apagar del visor: arranca la versión activa o la para y desactiva
    func power() {
        guard let d = data, !d.active.isEmpty else {
            openTab("versiones")
            return
        }
        control(d.running ? "parar" : "arrancar", d.running ? "Parando" : "Arrancando")
    }

    /// Rama de php.net de una versión de PHP (8.4.12 → la de 8.4), nil si no se ha consultado
    func branch(_ php: String) -> Branch? {
        let b = php.split(separator: ".").prefix(2).joined(separator: ".")
        return branches?.first { $0.branch == b }
    }

    /// Último parche de su rama, si es más nuevo que el que tiene
    func newerPatch(_ inst: Install) -> String? {
        guard let b = branch(inst.php), !b.latest.isEmpty else { return nil }
        return verParts(inst.php).lexicographicallyPrecedes(verParts(b.latest)) ? b.latest : nil
    }

    /// Proyecto de una BBDD en una versión: el vinculado o, si no tiene, el único que la usa en su
    /// configuración
    func dbProject(_ db: String, _ folder: String) -> String {
        if let f = linkOf(db, folder) { return f }
        let users = (projects?.list ?? []).filter { $0.db == db }.map { $0.name }
        return users.count == 1 ? users[0] : ""
    }

    /// Proyectos en Docker de una carpeta de htdocs
    /// Columna Proyecto de la tabla de proyectos: tan ancha como el nombre más largo (se ve entero),
    /// entre 260 y 320 (uno más largo se corta con «…» y se ve entero al pasar el ratón)
    func projectNameWidth() -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let widest = (projects?.list ?? []).map { ceil(($0.name as NSString).size(withAttributes: [.font: font]).width) }.max() ?? 0
        return Swift.min(320, Swift.max(260, widest + 8))
    }

    /// Lo que necesita la tabla de proyectos para que no se apriete nada: los márgenes y los espacios
    /// de la fila, sus columnas fijas y, en Versiones, sitio para dos versiones y una de Docker
    var projectsTableWidth: CGFloat {
        let anyDocker = !(docker?.projects.isEmpty ?? true)
        return 28 + 5 * 12 + 20 + projectNameWidth() + 80 + 190 + 170 + (anyDocker ? 270 : 130)
    }

    /// Ancho mínimo de la ventana: la barra lateral (220 y su línea), los márgenes de la página (24 a
    /// cada lado), la barra de desplazamiento y la tabla de proyectos. Así no se puede hacer tan
    /// estrecha que se rompan los textos y las etiquetas (como mucho unos 1425: cabe en un portátil de 13")
    var minWindowWidth: CGFloat {
        return Swift.max(1140, 220 + 1 + 48 + 16 + projectsTableWidth)
    }

    func dockerOf(_ folder: String) -> [DockerProject] {
        return (docker?.projects ?? []).filter { $0.folder == folder }
    }

    /// Entorno elegido en el proyecto de arriba: x:<versión> lo carga en esa versión; d:<nombre> lleva
    /// a la pestaña Docker (el proyecto se abre por su dominio)
    func chooseEnv(_ x: Project, _ key: String) {
        if key.hasPrefix("d:") {
            openTab("docker")
            if let dp = dockerOf(x.name).first(where: { $0.slug == String(key.dropFirst(2)) }) {
                toast("\(x.name) en Docker: https://\(dp.domain)")
            }
            return
        }
        let folder = String(key.dropFirst(2))
        guard let p = projects, let d = data, let inst = d.installs.first(where: { $0.folder == folder }) else { return }
        if loadedEntry()?.name == x.name && folder == d.active { return }
        let db = projectPairs(x).first(where: { $0.0.folder == folder })?.1 ?? projectBase(x)
        let req = ProjectRequest(db: db, inst: inst, link: p.link, current: p.current, create: p.create,
                                 projects: p.list, saved: p.saved)
        loadProject(req, folder: x.name, version: folder, manual: false, confirmSwitch: true)
    }

    /// Importar SQL del proyecto de arriba: el formulario de Bases de datos con su BBDD y su carpeta
    func importFor(_ x: Project) {
        if let db = projectPairs(x).first(where: { $0.0.folder == data?.active })?.1 { impDb = db }
        impProject = x.name
        if !impProjects.contains(x.name) { refreshImpProjects() }
        openTab("bbdd")
        toast("Elige el fichero en «Subir o actualizar una BBDD»: proyecto \(x.name)")
    }

    /// Lo que ocupan las copias de seguridad (~/lvm-copias) y cuántos ficheros hay
    func refreshBackups() {
        DispatchQueue.global(qos: .utility).async {
            var size: Int64 = 0
            var n = 0
            let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
            if let en = FileManager.default.enumerator(at: URL(fileURLWithPath: NSHomeDirectory() + "/lvm-copias"),
                                                       includingPropertiesForKeys: keys) {
                for case let u as URL in en {
                    if let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true {
                        size += Int64(v.fileSize ?? 0)
                        n += 1
                    }
                }
            }
            DispatchQueue.main.async { self.backups = [size, Int64(n)] }
        }
    }

    /// Lo que ocupa cada proyecto en el disco: du en segundo plano, de 10 en 10 proyectos y como mucho una
    /// vez por minuto (cada uno se vuelve a medir cada 6 horas). Si quedan por medir, la siguiente tanda
    func reloadProjectSizes(now: Bool = false) {
        if projSizesBusy || (!now && Date().timeIntervalSince(projSizesAt) < 60) { return }
        projSizesBusy = true
        runQuick(["gui-proyectos-tamanos"]) { _, out in
            var sizes: [String: [Int64]] = [:]
            var more = false
            for f in parseLines(out) {
                if f.count >= 4 && f[0] == "T", let bytes = Int64(f[2]), let when = Int64(f[3]) { sizes[f[1]] = [bytes, when] }
                if f[0] == "F" { more = true }
            }
            self.projSizesBusy = false
            self.projSizesAt = Date()
            if sizes != self.projectSizes { self.projectSizes = sizes }
            if more { self.reloadProjectSizes(now: true) }
        }
    }

    /// Lo que ocupa cada BBDD: se mide en la versión activa si su MariaDB está en marcha y se recuerda
    /// lo medido en las demás (sus carpetas de datos no se pueden leer sin sudo)
    func reloadDbSizes() {
        runQuick(["gui-bbdd-tamanos"], env: dbEnv()) { _, out in
            var sizes: [String: [Int64]] = [:]
            for f in parseLines(out) where f.count >= 5 && f[0] == "Z" {
                if let bytes = Int64(f[3]), let when = Int64(f[4]) { sizes[f[1] + "|" + f[2]] = [bytes, when] }
            }
            if sizes != self.dbSizes { self.dbSizes = sizes }
        }
    }

    // MARK: Docker

    func reloadDocker(stats: Bool = false) {
        runQuick(["gui-docker"]) { _, out in self.onDocker(out) }
        if stats { runQuick(["gui-docker-estadisticas"]) { _, out in self.onDockerStats(out) } }
    }

    func onDocker(_ out: String) {
        var k = DockerData()
        for f in parseLines(out) {
            switch f[0] {
            case "S" where f.count >= 5:
                k.installed = f[1] == "1"
                k.ready = f[2] == "1"
                k.version = f[3]
                k.xampp = f[4] == "1"
                k.app = field(f, 5) == "1"
            case "V" where f.count >= 3:
                k.php = f[1].split(separator: " ").map(String.init)
                k.maria = f[2].split(separator: " ").map(String.init)
            case "P" where f.count >= 9:
                // (los del Apache de Docker: web en vez de los puertos, y su tipo y sus versiones al final)
                let isWeb = f[8] == "web"
                k.projects.append(DockerProject(slug: f[1], folder: f[2], php: f[3], maria: f[4], domain: f[5],
                                                state: f[6], db: f[7], pma: isWeb ? "" : f[8], web: field(f, 9),
                                                old: field(f, 10) == "1", isWeb: isWeb, kind: field(f, 11),
                                                versions: isWeb ? field(f, 12).split(separator: " ").map(String.init) : [],
                                                lampp: isWeb ? field(f, 13) : ""))
            case "W" where f.count >= 6:
                k.web = DockerWeb(ip: f[1], http: f[2], https: f[3], state: f[4], ok: f[5] == "1",
                                  tld: field(f, 6) == "docker.test" ? "docker.test" : "docker.local", dns: field(f, 7) == "1")
            case "C" where f.count >= 7:
                k.containers.append(DockerContainer(name: f[1], image: f[2], state: f[3], status: f[4],
                                                    ports: f[5], project: f[6],
                                                    cid: String(field(f, 7).prefix(12))))
            case "I" where f.count >= 6:
                // (imagen|etiqueta|ID|tamaño|creada)
                k.images.append(DockerImage(repo: f[1], tag: f[2], cid: String(f[3].prefix(12)), size: f[4], created: f[5]))
            case "I" where f.count >= 4:
                // (el de antes: imagen:etiqueta|tamaño|creada; la etiqueta, tras los últimos dos puntos
                // que no sean los del puerto de un registro)
                var repo = f[1], tag = ""
                if let r = f[1].range(of: ":", options: .backwards), !f[1][r.upperBound...].contains("/") {
                    repo = String(f[1][..<r.lowerBound])
                    tag = String(f[1][r.upperBound...])
                }
                k.images.append(DockerImage(repo: repo, tag: tag, cid: "", size: f[2], created: f[3]))
            case "O" where f.count >= 3:
                k.volumes.append(DockerVolume(name: f[1], driver: f[2]))
            default:
                break
            }
        }
        if k != docker { docker = k }
    }

    func onDockerStats(_ out: String) {
        var s = DockerStats()
        let units: [String: Double] = ["B": 1, "KiB": 1024, "MiB": 1048576, "GiB": 1073741824, "TiB": 1099511627776,
                                       "kB": 1000, "KB": 1000, "MB": 1000000, "GB": 1000000000]
        for f in parseLines(out) {
            if f[0] == "T" && f.count >= 3, let c = Int(f[1]), let t = Int64(f[2]) {
                s.cores = max(1, c)
                s.total = t
            } else if f[0] == "K" && f.count >= 4 {
                s.cpu[f[1]] = Double(f[2].replacingOccurrences(of: "%", with: "")) ?? 0
                let used = (f[3].components(separatedBy: "/").first ?? "").trimmingCharacters(in: .whitespaces)
                let num = String(used.prefix { "0123456789.".contains($0) })
                let unit = String(used.dropFirst(num.count)).trimmingCharacters(in: .whitespaces)
                s.mem[f[1]] = (Double(num) ?? 0) * (units[unit] ?? 1)
            }
        }
        if s != dkStats { dkStats = s }
    }

    /// Instalar Docker: en el Mac se explica y se abre la página de descarga de Docker Desktop. Si ya
    /// está, se abre y se espera a que responda
    func dockerInstall() {
        let k = docker ?? DockerData()
        if !k.installed && !k.app {
            guard confirm("Instalar Docker Desktop",
                          "En el Mac, Docker es Docker Desktop: se descarga de docker.com (Apple Silicon) y se arrastra a Aplicaciones. Ábrelo una vez, acepta su licencia y vuelve aquí.\n\nDespués añade \(HTDOCS) en su Settings › Resources › File sharing.",
                          "Abrir la descarga") else { return }
            openURL(DOCKER_DOWNLOAD)
            return
        }
        runTask("Abriendo Docker Desktop", ["docker-instalar"], progress: true, doneText: "Docker Desktop listo", autoClose: true)
    }

    func openDockerForm(folder: String?) {
        dkForm = DockerForm()
        if let f = folder {
            dkForm.folder = f
            dkForm.domain = dockerSlug(f) + ".docker.local"
        }
        openTab("docker")
        panel = .dockerNew
    }

    /// Valores por omisión del formulario: la primera carpeta libre y las versiones más nuevas
    func fillDockerForm(_ folders: [String]) {
        let k = docker ?? DockerData()
        if dkForm.folder.isEmpty || !folders.contains(dkForm.folder), let f = folders.first {
            dkForm.folder = f
            dkForm.source = ""
            if !dkForm.domainSet { dkForm.domain = dockerSlug(f) + ".docker.local" }
        }
        if dkForm.php.isEmpty, let v = k.php.first { dkForm.php = v }
        if dkForm.maria.isEmpty, let v = k.maria.first { dkForm.maria = v }
    }

    func dockerCreate() {
        let f = dkForm
        guard !f.folder.isEmpty, !f.php.isEmpty, !f.maria.isEmpty else { return }
        var args = ["docker-nuevo", f.folder, f.php, f.maria]
        let slug = dockerSlug(f.folder)
        let tld = dockerTLD(docker)
        let site = dockerWebURL(docker, (projects?.list.first(where: { $0.name == f.folder })?.kind == "ps")
                                ? slug + "." + tld : slug + "-php" + f.php.replacingOccurrences(of: ".", with: "") + "." + tld)
        var text = "Con el Apache de Docker (sin XAMPP-X): su PHP \(f.php) y su BBDD en la MariaDB \(f.maria) común. Se abrirá en \(site)."
        let src = f.source.split(separator: "|", maxSplits: 1).map(String.init)
        let wp = projects?.list.first(where: { $0.name == f.folder })?.kind == "wp"
        if src.count == 2 && wp && f.live {
            args += ["--bd", src[1], "--desde", src[0], "--en-vivo"]
            text += " Usa en vivo \(src[1]) de XAMPP-\(src[0]): la misma BBDD que web.local, sin copias."
        } else if src.count == 2 {
            args += ["--bd", src[1], "--desde", src[0]]
            text += " Se copia \(src[1]) de XAMPP-\(src[0]) (esa no se toca)."
        } else {
            text += " La BBDD empieza vacía."
        }
        text += " La primera vez con cada PHP se prepara su imagen (unos minutos). Pide la contraseña de administrador.\n\n\(HTDOCS) tiene que estar en Docker Desktop, Settings › Resources › File sharing."
        guard confirm("¿Crear \(f.folder) en Docker?", text, "Crear en Docker") else { return }
        runTask("Creando \(f.folder) en Docker", args, progress: true, doneText: "\(f.folder) en Docker: \(site)") { ok, _, _ in
            if ok { self.dkForm = DockerForm() }
            self.reloadDocker()
        }
    }

    /// La BBDD de un WordPress de Docker: en vivo la de una versión XAMPP-X (la misma que web.local) o su
    /// copia en la MariaDB común de Docker
    func dockerDbMode(_ p: DockerProject) {
        var versions: [String] = []
        if let x = projects?.list.first(where: { $0.name == p.folder }) {
            for (i, _) in projectPairs(x) where !versions.contains(i.folder) { versions.append(i.folder) }
        }
        var choices: [(String, String)] = versions.map { ("lampp|" + $0, "En vivo: la de XAMPP-\($0) (la de web.local)") }
        choices.append(("docker", "Su copia en la MariaDB común de Docker"))
        let now = p.lampp.isEmpty ? "docker" : "lampp|" + p.lampp
        let alert = NSAlert()
        alert.messageText = "BBDD de \(p.folder) en Docker"
        alert.addButton(withTitle: "Usarla")
        alert.addButton(withTitle: "Cancelar")
        let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 380, height: 26), pullsDown: false)
        pop.addItems(withTitles: choices.map { $0.1 })
        pop.selectItem(at: choices.firstIndex(where: { $0.0 == now }) ?? 0)
        alert.accessoryView = dialogStack([
            dialogLabel("En vivo, Docker usa la misma BBDD que web.local: lo que cambies en un lado se ve en el otro, sin copias. Si la MariaDB de esa versión no está en marcha, se arranca solo ella, en otro puerto. La copia de Docker no se borra: se puede volver a ella."
                        + (versions.isEmpty ? " Su BBDD no está en ninguna versión de XAMPP-X." : ""), color: .secondaryLabelColor),
            pop,
        ], spacing: 10)
        guard alert.runStyled() == .alertFirstButtonReturn else { return }
        let i = pop.indexOfSelectedItem
        guard i >= 0, i < choices.count, choices[i].0 != now else { return }
        let c = choices[i].0
        let args = ["docker-bd", p.slug] + (c.hasPrefix("lampp|") ? ["lampp", String(c.dropFirst(6))] : ["docker"])
        _ = runTask("BBDD de \(p.folder)", args, doneText: "Hecho", autoClose: true) { _, _, _ in self.reloadDocker() }
    }

    func dockerAction(_ p: DockerProject, start: Bool) {
        runTask((start ? "Arrancando " : "Parando ") + p.folder, [start ? "docker-arrancar" : "docker-parar", p.slug],
                doneText: "\(p.folder) \(start ? "en marcha" : "parado")", autoClose: true)
    }

    func dockerLogs(_ p: DockerProject) {
        runTask("Registros de \(p.folder)", ["docker-registros", p.slug])
    }

    func dockerDelete(_ p: DockerProject) {
        guard confirm("¿Borrar \(p.folder) de Docker?",
                      p.isWeb ? "Se borran sus contenedores, su BBDD (\(p.db)) y su usuario de la MariaDB común y sus dominios; no se puede deshacer. La carpeta y las BBDD de XAMPP-X no se tocan. Pide la contraseña de administrador."
                        : "Se borran sus contenedores, su copia de la BBDD (\(p.db)) y su vhost (\(p.domain)); no se puede deshacer. La carpeta y las BBDD de XAMPP-X no se tocan. Pide la contraseña de administrador.",
                      "Borrar de Docker", destructive: true) else { return }
        runTask("Borrando \(p.folder) de Docker", ["docker-borrar", p.slug],
                doneText: "\(p.folder) borrado de Docker", autoClose: true)
    }

    /// Cambiar la versión de PHP de un proyecto en Docker (solo su contenedor de PHP)
    func dockerSetPhp(_ p: DockerProject) {
        guard let k = docker, !busy, !k.php.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "¿Con qué versión de PHP quieres \(p.folder)?"
        alert.informativeText = "Solo cambia su contenedor de PHP: su BBDD y su configuración se quedan. La primera vez con cada versión se prepara su imagen. Si no arranca, vuelve a PHP \(p.php)."
        alert.addButton(withTitle: "Cambiar de PHP")
        alert.addButton(withTitle: "Cancelar")
        let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26), pullsDown: false)
        pop.addItems(withTitles: k.php.map { "PHP \($0)" + ($0 == p.php ? "  (ahora)" : "") })
        if let i = k.php.firstIndex(of: p.php) { pop.selectItem(at: i) }
        alert.accessoryView = pop
        guard alert.runStyled() == .alertFirstButtonReturn else { return }
        let i = pop.indexOfSelectedItem
        guard i >= 0 && i < k.php.count && k.php[i] != p.php else { return }
        let v = k.php[i]
        runTask("\(p.folder): PHP \(p.php) → \(v)", ["docker-php", p.slug, v],
                doneText: "\(p.folder) funciona ya con PHP \(v)", autoClose: true)
    }

    /// Los proyectos en Docker de antes de la 1.39.2 (PHP-FPM abierto en 127.0.0.1, sin clave) pasan a
    /// la web del contenedor con clave (docker-migrar --todos)
    func dockerMigrateAll() {
        guard confirm("¿Cerrar el PHP-FPM de los proyectos en Docker?",
                      "Estaba abierto en 127.0.0.1 sin clave: cualquier programa del Mac podía ejecutar PHP con él. Su web pasa al contenedor (Apache con PHP), con una clave que solo tiene el Apache del Mac. Sus BBDD, configuración y dominios se conservan. Pide la contraseña de administrador.",
                      "Cerrarlo") else { return }
        runTask("Cerrando el PHP-FPM de los proyectos en Docker", ["docker-migrar", "--todos"],
                doneText: "Proyectos en Docker con su clave", autoClose: true)
    }

    /// Rehace la imagen de PHP de un proyecto con la última de Docker Hub (parches de seguridad)
    func dockerUpdateImage(_ p: DockerProject) {
        let vs = p.isWeb ? p.versions.joined(separator: ", ") : p.php
        guard confirm("¿Actualizar la imagen de PHP \(vs)?",
                      "Se descarga otra vez la imagen oficial (php:<versión>-apache, con sus últimos parches), se rehace y se vuelve a crear el contenedor de PHP de \(p.folder). Su BBDD y su configuración no se tocan. Tarda unos minutos.",
                      "Actualizar la imagen") else { return }
        runTask("Actualizando la imagen de PHP \(vs)", ["docker-imagen", p.slug], progress: true,
                doneText: "\(p.folder) con la imagen nueva de PHP \(vs)")
    }

    /// Usuario y contraseña del phpMyAdmin de un proyecto (ya no entra solo como root)
    func dockerPassword(_ p: DockerProject) {
        runQuick(["docker-clave", p.slug]) { rc, out in
            guard rc == 0, let k = parseLines(out).first(where: { $0[0] == "K" && $0.count >= 4 }) else {
                message("No se encuentra la contraseña", String(out.suffix(400)), error: true)
                return
            }
            let pass = k[2]
            let r = runDialog(title: "phpMyAdmin de \(p.folder)",
                              text: "Usuario: \(k[1])\nContraseña: \(pass)\n\n\(k[3...].joined(separator: "|"))",
                              okLabel: "Copiar la contraseña", cancelLabel: "Cerrar")
            if r.ok {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pass, forType: .string)
                self.toast("Contraseña de \(p.folder) copiada")
            }
        }
    }

    /// phpMyAdmin de un proyecto en Docker (el visor): antes copia la contraseña de root, que pide
    func dockerOpenPma(_ p: DockerProject) {
        runQuick(["docker-clave", p.slug]) { rc, out in
            if rc == 0, let k = parseLines(out).first(where: { $0[0] == "K" && $0.count >= 4 }) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(k[2], forType: .string)
                self.toast(p.isWeb ? "Contraseña de root de la MariaDB \(p.maria) de Docker copiada: en phpMyAdmin, usuario root"
                           : "Contraseña de root de \(p.folder) copiada: en su phpMyAdmin, usuario root")
            }
            openURL(p.isWeb ? self.dockerPmaURL : "http://127.0.0.1:\(p.pma)/")
        }
    }

    /// Panel del WordPress o la tienda de un proyecto en Docker, por su dominio, con el administrador de
    /// pruebas en la BBDD del contenedor (docker-usuario-pruebas lo pone si falta: la copia no lo lleva)
    func dockerPanel(_ p: DockerProject, kind: String, admin: String) {
        openAdminLogin(kind: kind, admin: admin, site: dockerSite(p), name: p.folder,
                       command: ["docker-usuario-pruebas", p.slug])
    }

    /// Lo último del contenedor de la web de un proyecto en Docker (Apache con PHP: ahí van los errores
    /// de PHP de la web)
    func dockerWebLog(_ p: DockerProject, _ name: String) {
        runQuick(["docker-contenedor", "registros", name]) { rc, out in
            if rc != 0 && out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                message("No se han podido leer los registros de \(name)", "", error: true)
                return
            }
            let tail = out.components(separatedBy: "\n").suffix(400).joined(separator: "\n")
                .replacingOccurrences(of: "\\n", with: "\n    ")
            showLongText("PHP de \(p.folder)", tail.isEmpty ? "(vacío)" : tail,
                         subtitle: "Últimas líneas del contenedor \(name) (los errores de PHP de https://\(p.domain))",
                         toEnd: true)
        }
    }

    // MARK: Docker desde el proyecto cargado

    /// Botón Docker del proyecto cargado. Sin Docker Desktop en marcha, primero se abre (o se explica
    /// cómo instalarlo). Si el proyecto no está en Docker, se monta con la versión de PHP que se elija;
    /// si está con una, se arranca; con varias, se pregunta cuál (o se monta con otra)
    func dockerForLoaded(_ x: Project) {
        runQuick(["gui-docker"]) { _, out in
            self.onDocker(out)
            let k = self.docker ?? DockerData()
            let envs = self.dockerOf(x.name)
            if !k.ready || k.php.isEmpty {
                if !k.installed && !k.app {
                    self.dockerInstall()
                    return
                }
                guard confirm("Docker Desktop no está en marcha",
                              "Se abre Docker Desktop y, cuando responda, se sigue con \(x.name).",
                              "Abrir Docker Desktop") else { return }
                self.runTask("Abriendo Docker Desktop", ["docker-instalar"], progress: true, doneText: "Docker Desktop listo",
                             autoClose: true) { ok, _, _ in
                    if ok { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.dockerForLoaded(x) } }
                }
            } else if envs.isEmpty {
                self.dockerMountDialog(x)
            } else if envs.count == 1 {
                self.dockerMount(envs[0])
            } else {
                self.dockerChoose(x, envs)
            }
        }
    }

    /// Arranca un proyecto de Docker y lleva a la pestaña Docker
    func dockerMount(_ dp: DockerProject) {
        if dp.state == "marcha" {
            openTab("docker")
            toast("\(dp.folder) ya está en marcha en Docker: \(dockerSite(dp))")
            return
        }
        runTask("Arrancando \(dp.folder) en Docker (PHP \(dp.php))", ["docker-arrancar", dp.slug],
                doneText: "\(dp.folder) en Docker: \(dockerSite(dp))", autoClose: true) { ok, _, _ in
            if ok { self.openTab("docker") }
        }
    }

    /// El proyecto está en Docker con varias versiones de PHP: cuál se monta, u otra nueva
    func dockerChoose(_ x: Project, _ envs: [DockerProject]) {
        let list = envs.sorted { $0.php.compare($1.php, options: .numeric) == .orderedDescending }
        let alert = NSAlert()
        alert.messageText = "¿Qué versión de \(x.name) montas?"
        alert.addButton(withTitle: "Montar")
        alert.addButton(withTitle: "Cancelar")
        let group = RadioGroup()
        var options: [NSView] = []
        for (n, dp) in list.enumerated() {
            let b = NSButton(radioButtonWithTitle: "PHP \(dp.php)  ·  \(dp.domain)" + (dp.state == "marcha" ? "  ·  en marcha" : ""),
                             target: group, action: #selector(RadioGroup.pick(_:)))
            b.state = n == 0 ? .on : .off
            group.buttons.append(b)
            options.append(b)
        }
        let other = NSButton(radioButtonWithTitle: "Otra versión de PHP…", target: group, action: #selector(RadioGroup.pick(_:)))
        other.state = .off
        group.buttons.append(other)
        options.append(other)
        alert.accessoryView = dialogStack([dialogLabel("Está en Docker con varias versiones de PHP.", color: .secondaryLabelColor),
                                           dialogOptions(options)], spacing: 14)
        guard alert.runStyled() == .alertFirstButtonReturn else { return }
        let i = group.buttons.firstIndex(where: { $0.state == .on }) ?? 0
        if i < list.count {
            dockerMount(list[i])
        } else if let w = envs.first(where: { $0.isWeb }) {
            dockerVersions(w)
        } else {
            dockerMountDialog(x)
        }
    }

    /// «Montar <proyecto> en Docker»: PHP (la rama de la versión activa), MariaDB (la de la activa,
    /// si se ofrece), la BBDD que se copia (la del proyecto en la activa) y el dominio. Si la carpeta
    /// ya está en Docker, el nuevo va con otro nombre (<carpeta>-php84)
    func dockerMountDialog(_ x: Project) {
        guard let k = docker, !k.php.isEmpty, !k.maria.isEmpty, !busy else { return }
        let d = data ?? AppData()
        let act = d.installs.first(where: { $0.folder == d.active })
        let phpNow = act.map { shortPhp($0.php) } ?? ""
        let mariaNow = act?.mariadb ?? ""
        let pairs = projectPairs(x)
        let alert = NSAlert()
        alert.messageText = "Montar \(x.name) en Docker"
        alert.addButton(withTitle: "Montar en Docker")
        alert.addButton(withTitle: "Cancelar")
        // (ancho del nombre más largo: la BBDD con su versión, entera)
        let width = fitWidth(pairs.map { "\($0.1) (XAMPP-\($0.0.folder))" }, min: 300, max: 520)
        func popup(_ items: [String], _ selected: Int) -> NSPopUpButton {
            let b = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: width, height: 26), pullsDown: false)
            b.addItems(withTitles: items)
            if selected >= 0 && selected < items.count { b.selectItem(at: selected) }
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: width).isActive = true
            return b
        }
        func line(_ title: String, _ view: NSView) -> NSView {
            let t = NSTextField(labelWithString: title)
            t.textColor = .secondaryLabelColor
            t.translatesAutoresizingMaskIntoConstraints = false
            t.widthAnchor.constraint(equalToConstant: 140).isActive = true
            let row = NSStackView(views: [t, view])
            row.orientation = .horizontal
            row.spacing = 10
            return row
        }
        let phpPop = popup(k.php.map { "PHP \($0)" }, k.php.firstIndex(of: phpNow) ?? 0)
        let mariaPop = popup(k.maria.map { "MariaDB \($0)" },
                             k.maria.firstIndex(where: { mariaNow == $0 || mariaNow.hasPrefix($0 + ".") }) ?? 0)
        var sources: [(String, String)] = [("", "Ninguna: empieza vacía")]
        sources += pairs.map { ("\($0.0.folder)|\($0.1)", "\($0.1) (XAMPP-\($0.0.folder))") }
        let srcSel = sources.firstIndex(where: { !d.active.isEmpty && $0.0.hasPrefix(d.active + "|") }) ?? (sources.count - 1)
        let srcPop = popup(sources.map { $0.1 }, srcSel)
        let wp = x.kind == "wp"
        let modePop = popup(["En vivo: la misma que web.local (sin copias)", "Una copia en Docker"], 0)
        alert.accessoryView = dialogStack([
            dialogLabel("Con el Apache de Docker (sin XAMPP-X). Se descargan las imágenes que falten y se abre por su dominio (\(dockerSlug(x.name)).\(dockerTLD(k))). La carpeta y sus BBDD de XAMPP-X no se tocan.",
                        color: .secondaryLabelColor),
            line("PHP", phpPop), line("MariaDB", mariaPop), line(wp ? "BBDD" : "BBDD que se copia", srcPop),
        ] + (wp ? [line("Cómo", modePop)] : []), spacing: 10)
        guard alert.runStyled() == .alertFirstButtonReturn else { return }
        let pi = phpPop.indexOfSelectedItem, mi = mariaPop.indexOfSelectedItem, si = srcPop.indexOfSelectedItem
        guard pi >= 0, pi < k.php.count, mi >= 0, mi < k.maria.count else { return }
        var args = ["docker-nuevo", x.name, k.php[pi], k.maria[mi]]
        if si > 0, si < sources.count {
            let src = sources[si].0.split(separator: "|", maxSplits: 1).map(String.init)
            if src.count == 2 { args += ["--bd", src[1], "--desde", src[0]] + (wp && modePop.indexOfSelectedItem == 0 ? ["--en-vivo"] : []) }
        }
        runTask("Montando \(x.name) en Docker", args, progress: true, doneText: "\(x.name) en Docker") { ok, _, _ in
            self.reloadDocker()
            if ok { self.openTab("docker") }
        }
    }

    /// Acción sobre un contenedor suelto de un proyecto en Docker
    func containerAction(_ c: DockerContainer, _ action: String) {
        if action == "parar" && !stopSharedOK([c.name], c.name) { return }
        if action == "borrar" {
            guard confirm("¿Eliminar el contenedor \(c.name)?",
                          "Al arrancar el proyecto se vuelve a crear; los datos de la BBDD siguen en su volumen. Para quitar el proyecto entero, usa la papelera de su fila.",
                          "Eliminar el contenedor", destructive: true) else { return }
        }
        let titles = ["arrancar": "Arrancando", "parar": "Parando", "reiniciar": "Reiniciando",
                      "registros": "Registros de", "borrar": "Eliminando"]
        runTask("\(titles[action] ?? action) \(c.name)", ["docker-contenedor", action, c.name],
                autoClose: action != "registros")
    }

    /// Volver a descargar una imagen de Docker Hub (las nexum-* del gestor se rehacen con «Actualizar
    /// imagen» de su proyecto)
    func imagePull(_ i: DockerImage) {
        guard i.tagged, !i.repo.hasPrefix("nexum-") else { return }
        runTask("Descargando \(i.name)", ["docker-imagenes", "descargar", i.name], doneText: "\(i.name) descargada")
    }

    /// Borrar una imagen (sin -f: si la usa un contenedor, Docker no la borra)
    func imageDelete(_ i: DockerImage) {
        // (sin etiqueta, por su ID)
        let ref = i.tagged || i.cid.isEmpty ? i.name : i.cid
        guard confirm("¿Borrar la imagen \(ref)?",
                      "Ocupa \(i.size). Si hace falta, se vuelve a descargar o a preparar.",
                      "Borrar la imagen", destructive: true) else { return }
        runTask("Borrando \(ref)", ["docker-imagenes", "borrar", ref], doneText: "Imagen borrada", autoClose: true)
    }

    func volumeDelete(_ v: DockerVolume) {
        guard confirm("¿Borrar el volumen \(v.name)?", "Se pierden sus datos. No se puede deshacer.",
                      "Borrar el volumen", destructive: true) else { return }
        runTask("Borrando \(v.name)", ["docker-volumen-borrar", v.name], doneText: "Volumen borrado", autoClose: true)
    }
}

// MARK: - Barra de arriba

/// Siempre a la vista: el nombre, el menú, el visor de la versión montada (PHP, Apache y MariaDB con su
/// punto, encender o apagar y, en la flecha, sus servicios), Localhost y los avisos (phpMyAdmin, desde
/// la 1.39.5, en Bases de datos y en el menú Gestor)
/// Tarea en segundo plano: una flecha verde que baja y late, con su porcentaje; al pulsarla, su hoja
struct TaskBadge: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var task: TaskRunner
    @State private var pulse = false

    var body: some View {
        Button(action: { model.taskHidden = false }) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .opacity(pulse ? 0.35 : 1)
                    .offset(y: pulse ? 2 : -2)
                // (lo que hace, con la primera palabra del título: «Actualizando…», «Instalando…»)
                Text((task.title.split(separator: " ").first.map(String.init) ?? "En marcha") + "…")
                    .font(.system(size: 11.5, weight: .semibold))
                if let r = task.pctText.range(of: "%") {
                    Text(String(task.pctText[..<r.upperBound])).font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                }
            }
            .foregroundColor(.green)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.green.opacity(0.13)))
            .overlay(Capsule().stroke(Color.green.opacity(0.5), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .hoverPointer()
        .tip("\(task.title)\n\(task.barText)\nPulsa para ver la ventana")
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

struct TopBar: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) var scheme
    @State private var menuOpen = false
    @State private var servicesOpen = false
    @State private var servicesHover = false
    @State private var warnOpen = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 0) {
                    title(model.data?.name ?? "Nexum Dev Stack")
                    // (con la versión del programa detrás)
                    Text("Entornos PHP y Docker" + ((model.data?.version).map { $0.isEmpty ? "" : "  ·  v\($0)" } ?? ""))
                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            // (la tarea en segundo plano, a la izquierda del visor; el menú, justo a su derecha, como en Linux)
            if model.taskHidden, let t = model.task {
                TaskBadge(task: t)
            }
            visor()
            menuButton()
            Spacer(minLength: 12)
            mailButton()
            // (la terminal de abajo de la ventana: se enseña y se esconde; en lugar de Localhost)
            Button(action: { model.termOpen.toggle() }) {
                Label("Terminal", systemImage: "terminal")
            }
            .buttonStyle(OutlineButton(kind: model.termOpen ? "primary" : ""))
            .tip("Mostrar u ocultar la terminal")
            warnings()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    /// El nombre: «NEXUM» en Goldman y lo demás («Dev Stack») normal y en azul, que se lea sobre el
    /// gris de la ventana (más claro en el tema oscuro, más oscuro en el claro). Goldman va en la
    /// aplicación (Resources/fuentes); sin ella, la del sistema
    func title(_ name: String) -> Text {
        guard name.hasPrefix("Nexum "), name.count > 6 else { return Text(name).font(.system(size: 14, weight: .bold)) }
        let blue = scheme == .dark ? hexColor(0x4C9DFF) : hexColor(0x0A6FD6)
        return Text("NEXUM").font(.custom("Goldman", size: 15)).kerning(1)
            + Text(String(name.dropFirst(5))).font(.system(size: 14)).foregroundColor(blue)
    }

    /// Menú (☰), sin recuadro, con un icono en cada opción y el tema claro u oscuro
    func menuButton() -> some View {
        Button(action: { menuOpen.toggle() }) {
            Image(systemName: "line.3.horizontal").font(.system(size: 17, weight: .medium))
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .hoverPointer()
        .tip("Menú")
        .popover(isPresented: $menuOpen, arrowEdge: .bottom) {
            MainMenu(close: { menuOpen = false }).environmentObject(model)
        }
    }

    func visor() -> some View {
        let d = model.data
        let act = d.flatMap { dd in dd.installs.first(where: { $0.folder == dd.active }) }
        let running = d?.running ?? false
        let svc = Dictionary((model.services ?? []).map { ($0.name, $0.running) }, uniquingKeysWith: { a, _ in a })
        return HStack(spacing: 9) {
            LogoShape(d: LOGO_PATHS["php"] ?? "").fill(brand("php")).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                // (siempre en una línea: el visor se ensancha antes que partir «XAMPP-8.5»)
                Text(act.map { "PHP \($0.php)" } ?? "Ninguna versión activa").font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).fixedSize()
                if let a = act {
                    Text("XAMPP-\(a.folder)").font(.system(size: 10.5, design: .monospaced)).foregroundColor(.secondary)
                        .lineLimit(1).fixedSize()
                }
            }
            Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 22)
            // Apache y MariaDB con su punto: al pulsarlos, sus servicios (arrancarlos, pararlos o reiniciarlos,
            // y la versión entera)
            Button(action: { servicesOpen.toggle() }) {
                HStack(spacing: 9) {
                    ForEach(["apache", "mariadb"], id: \.self) { s in
                        HStack(spacing: 5) {
                            StatusDot(on: act != nil && (svc[s] ?? running))
                            Text(s == "apache" ? "Apache" : "MariaDB").font(.system(size: 12))
                        }
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(servicesHover || servicesOpen ? 0.10 : 0)))
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { servicesHover = $0 }
            .hoverPointer()
            .tip("Servicios de la versión activa")
            .popover(isPresented: $servicesOpen, arrowEdge: .bottom) {
                // (los recuadros de arriba no heredan el estilo de los botones de la ventana)
                ServicesView(close: { servicesOpen = false }).environmentObject(model).buttonStyle(PointerButtonStyle()).frame(width: 660, height: 470)
            }
            Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 22)
            usageText()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(SoftSunken(radius: 12))
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
    }

    /// Lo que gastan Nexum y sus servicios juntos: la CPU en % de todo el Mac (todos los núcleos son el
    /// 100 %) y la memoria en % de la del Mac. Al pasar el ratón, cada parte
    func usageText() -> some View {
        let u = model.usage ?? [:]
        let cores = Double(Swift.max(1, ProcessInfo.processInfo.activeProcessorCount))
        let total = Double(Swift.max(1, ProcessInfo.processInfo.physicalMemory))
        let cpu = u.values.reduce(0.0) { $0 + $1.cpu } / cores
        let mem = u.values.reduce(Int64(0)) { $0 + $1.mem }
        var lines = ["CPU \(fmtPercent(cpu)) · RAM \(fmtSize(mem))", ""]
        for (k, text) in USAGE_GROUPS {
            if let part = u[k], part.mem > 0 || part.cpu > 0 {
                lines.append("\(text): CPU \(fmtPercent(part.cpu / cores)) · \(fmtSize(part.mem))")
            }
        }
        return Text(model.usage == nil ? "CPU — · RAM —" : "CPU \(fmtPercent(cpu)) · RAM \(fmtPercent(100 * Double(mem) / total))")
            .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
            .lineLimit(1).fixedSize()
            .tip(lines.joined(separator: "\n"))
    }

    /// Correo de pruebas: la bandeja de Mailpit, con los correos sin leer (se pregunta solo con la
    /// ventana a la vista). Con el correo de pruebas apagado no sale
    @ViewBuilder
    func mailButton() -> some View {
        if let m = model.data?.mail, m.on {
            Button(action: { model.openMail() }) {
                HStack(spacing: 6) {
                    LogoShape(d: LOGO_PATHS["mailpit"] ?? "").fill(brand("mailpit")).frame(width: 15, height: 15)
                    Text("Correo")
                    if let n = model.mailUnread, n > 0 {
                        Text(n > 99 ? "99+" : "\(n)")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(brand("mailpit")))
                    }
                }
            }
            .buttonStyle(OutlineButton())
            .tip(mailTip(m))
        }
    }

    func mailTip(_ m: MailState) -> String {
        if !m.installed { return "Mailpit no está instalado" }
        if !m.running { return "Arranca la versión activa para ver el correo" }
        if let n = model.mailUnread, n > 0 { return "Correo de las webs (Mailpit): \(n) sin leer" }
        return "Correo de las webs (Mailpit)"
    }

    /// Los avisos (lo que antes iba arriba de Versiones) en un solo botón con cuántos hay
    @ViewBuilder
    func warnings() -> some View {
        let n = (model.data.map { warningCount($0) } ?? 0) + (model.updatesPending != nil ? 1 : 0)
        if model.data != nil, n > 0 {
            Button(action: { warnOpen.toggle() }) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text("\(n)").font(.system(size: 12, weight: .bold))
                }
            }
            .buttonStyle(OutlineButton())
            .tip("Avisos")
            .popover(isPresented: $warnOpen, arrowEdge: .bottom) {
                ScrollView {
                    WarningsView().environmentObject(model).buttonStyle(PointerButtonStyle()).padding(18)
                }
                .frame(width: 620, height: 480)
            }
        }
    }
}

struct MainMenu: View {
    @EnvironmentObject var model: AppModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            item(model.isDark ? "Tema claro" : "Tema oscuro", model.isDark ? "sun.max" : "moon") { model.toggleTheme() }
            Divider().padding(.vertical, 4)
            item("Editar vhosts", "doc.text") { model.editVhosts() }
            item("Editar /etc/hosts", "network") { model.editHosts() }
            Divider().padding(.vertical, 4)
            item("Volver a leer las versiones", "arrow.clockwise") { model.reload(branches: true) }
            item("Buscar actualizaciones", "arrow.down.circle") { model.checkUpdates() }
            item("Abrir el panel en Terminal", "terminal") { model.openTerminal() }
            item("Carpeta de registros", "folder") { showFolder(LOG_DIR) }
            Divider().padding(.vertical, 4)
            item("Novedades", "star") { model.showChanges() }
            item("Acerca de \(model.data?.name ?? "Nexum Dev Stack")", "info.circle") { model.showAbout() }
        }
        .padding(6)
        .frame(width: 270)
    }

    /// (se cierra el menú antes: las opciones pueden abrir un diálogo)
    func item(_ text: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        MenuRow(text: text, symbol: symbol) {
            close()
            DispatchQueue.main.async { action() }
        }
    }
}

struct MenuRow: View {
    let text: String
    let symbol: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 18)
                Text(text)
                Spacer(minLength: 0)
            }
            .foregroundColor(hover ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 5).fill(hover ? ACCENT : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover = $0 }
    }
}

/// Avisos: XAMPP oficial, tablas del sistema, phpMyAdmin antiguo, protecciones, certificados y
/// procesos de otras versiones
struct WarningsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let c = model.updatesPending {
                Card("Hay parches nuevos (\(c.items.count))",
                     "Lo de ahora sigue funcionando mientras se actualiza (se puede seguir en segundo plano). Si no quieres cambiar nada, «Ahora no» lo deja hasta que salga otro parche; siguen en Configuración, Parches nuevos.") {
                    Row("Conviene ponerlos: son parches de seguridad",
                        (c.items.prefix(6).map { "• " + $0 } + (c.items.count > 6 ? ["…y \(c.items.count - 6) más"] : [])).joined(separator: "\n"),
                        trailing: {
                            Button("Ahora no") { model.ignoreUpdates(c) }
                            Button("Actualizar todo") { model.updateComponents(c) }
                                .buttonStyle(OutlineButton(kind: "primary"))
                                .disabled(model.busy)
                        })
                }
            }
            if let d = model.data {
                if warningCount(d) == 0 && model.updatesPending == nil {
                    Text("No hay avisos.").foregroundColor(.secondary)
                }
                if d.official {
                    Card("Hay un XAMPP oficial en /Applications/XAMPP",
                         "Este gestor necesita que /Applications/XAMPP sea un enlace a la versión activa. Al apartarlo se copian sus BBDD, sus proyectos y sus vhosts, y se mueve a /Applications/XAMPP-oficial-<fecha>, sin borrar nada.") {
                        Row("XAMPP oficial") {
                            Button("Apartar…") { model.setAside() }.disabled(model.busy)
                        }
                    }
                }
                // (en un Group: el bloque pasaria de las 10 vistas que admite SwiftUI en macOS 12)
                Group {
                    if !d.dbsysVersion.isEmpty {
                        Card("Tablas del sistema de MariaDB antiguas",
                             "Las tablas del sistema (mysql.*) son de una MariaDB anterior y el servidor escribe un error cada vez que las usa: su registro de errores no para de crecer. Repararlas las pone al día con el mariadb-upgrade de la versión, sin tocar las BBDD de los proyectos, después de guardar una copia en ~/lvm-copias, y vacía el registro si es grande.") {
                            Row("MariaDB de XAMPP-\(d.dbsysVersion)", "Registro de errores: \(fmtSize(d.dbsysLog))", trailing: {
                                Button("Repararlas") { model.repairDbSystem() }
                                    .buttonStyle(OutlineButton(kind: "primary"))
                                    .disabled(model.busy)
                            })
                        }
                    }
                    let oldPma = d.installs.filter { pmaOutdated($0.php, $0.pma) }
                    if !oldPma.isEmpty {
                        Card("phpMyAdmin antiguo",
                             "Estas versiones tienen un phpMyAdmin con fallos de seguridad que ya están corregidos. Actualizarlo pone el más nuevo que admite su PHP, con la misma configuración; el anterior queda en phpmyadmin.anterior.") {
                            Row("phpMyAdmin con fallos corregidos después",
                                oldPma.map { "XAMPP-\($0.folder) (\($0.pma))" }.joined(separator: ", "), trailing: {
                                Button("Actualizarlos") { model.updatePma("--todas") }
                                    .buttonStyle(OutlineButton(kind: "primary"))
                                    .disabled(model.busy)
                            })
                        }
                    }
                    if !d.unsecured.isEmpty {
                        Card("A algunas versiones les faltan protecciones",
                             "Les falta algo de lo que pone el gestor: solo para este Mac, phpMyAdmin cerrado a otras webs, MariaDB sin acceso a los ficheros del Mac... (o su carpeta no es de root y no se arrancarían). Protegerlas lo pone, como en la activa; pide la contraseña de administrador.") {
                            Row("Versiones sin proteger", d.unsecured.map { "XAMPP-" + $0 }.joined(separator: ", "), trailing: {
                                Button("Protegerlas") { model.secureAll() }
                                    .buttonStyle(OutlineButton(kind: "primary"))
                                    .disabled(model.busy)
                            })
                        }
                    }
                }
                Group {
                    if !d.certs.isEmpty || !d.cas.isEmpty {
                        Card("Certificados en los que confía todo el Mac", certsText(d)) {
                            Row("Proyectos con https", certsNames(d), trailing: {
                                Button("Arreglarlos") { model.fixCerts() }
                                    .buttonStyle(OutlineButton(kind: "primary"))
                                    .disabled(model.busy)
                            })
                        }
                    }
                    // Su certificado propio no lo acepta el navegador: avisa al abrirlos y las
                    // herramientas que lo manejan (Claude in Chrome) no pueden pasar del aviso
                    if !d.untrusted.isEmpty {
                        Card("El navegador avisa al abrir estos proyectos",
                             "Safari y Chrome no aceptan todavía su certificado: sale «La conexión no es privada» y las herramientas que manejan el navegador (como Claude in Chrome) no pueden abrirlos. Confiar hace que acepte el certificado propio de cada proyecto, que solo vale para su dominio: no sirve para falsificar ninguna otra web. El de una tienda con dominio real, solo mientras esté falseada en /etc/hosts: al dejar de falsearla, deja de aceptarlo (con su clave se podría suplantar la web de verdad). El Mac pide tu contraseña una vez por proyecto. Después, si Chrome estaba abierto, ciérralo y vuelve a abrirlo.") {
                            Row("Proyectos que avisan en el navegador",
                                d.untrusted.prefix(6).joined(separator: ", ") + (d.untrusted.count > 6 ? " y \(d.untrusted.count - 6) más" : ""),
                                trailing: {
                                Button("Confiar") { model.trustCerts() }
                                    .buttonStyle(OutlineButton(kind: "primary"))
                                    .disabled(model.busy)
                            })
                        }
                    }
                    // Tiendas con dominio real cuyo certificado aún acepta el navegador y ya no están
                    // falseadas (hosts cambiado a mano o contraseña cancelada)
                    if !d.stale.isEmpty {
                        Card("El navegador acepta webs reales que ya no están falseadas",
                             "El navegador aceptaba su certificado mientras estaban falseadas en /etc/hosts. Ya no lo están, así que el navegador va a la web de verdad, y con la clave de ese certificado (Apache la tiene en memoria) se la podría suplantar. Quitar hace que deje de aceptarlo; el Mac pide tu contraseña una vez por web. Después, si Chrome estaba abierto, ciérralo y vuelve a abrirlo.") {
                            Row("Webs reales que acepta el navegador",
                                d.stale.prefix(6).joined(separator: ", ") + (d.stale.count > 6 ? " y \(d.stale.count - 6) más" : ""),
                                trailing: {
                                Button("Quitar") { model.untrustCerts() }
                                    .buttonStyle(OutlineButton(kind: "primary"))
                                    .disabled(model.busy)
                            })
                        }
                    }
                    let vulnerable = d.installs.filter { php2shellVulnerable(d.php2shell[$0.folder] ?? "ok") }
                    if !vulnerable.isEmpty {
                        Card("Versiones vulnerables a PHP2Shell",
                             "CVE-2026-109618 y CVE-2026-109619: un formulario de un proyecto puede acabar ejecutando código en tu Mac. Las de 8.2 a 8.5 se arreglan con el último parche de su rama; las 7.4, 8.0 y 8.1, con el parche oficial de seguridad. Actualízalas en el menú ⋯ de cada versión (Versiones de PHP).") {
                            Row("PHP vulnerable",
                                vulnerable.map { "XAMPP-\($0.folder) (PHP \($0.php))" }.joined(separator: ", "), trailing: {
                                Button("Ver las versiones") { model.openTab("versiones") }
                                    .buttonStyle(OutlineButton(kind: "primary"))
                            })
                        }
                    }
                    if !d.stray.isEmpty {
                        Card("Hay procesos de otras versiones en memoria",
                             "Solo debería estar en memoria la versión montada\(d.active.isEmpty ? "" : " (XAMPP-\(d.active))"). Ocupan memoria y pueden bloquear los puertos 80, 443 y 3306.") {
                            Row("Procesos que sobran", d.stray) {
                                Button("Cerrarlos") { model.closeStray() }.disabled(model.busy)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Barra lateral

/// Apartados: clave, texto e icono (logo:<paquete> o un símbolo)
let NAV: [(String, [(String, String, String)])] = [
    ("ENTORNO", [("proyectos", "Proyectos", "folder"), ("repos", "Repositorios", "logo:github"),
                 ("versiones", "Versiones de PHP", "logo:php"),
                 ("bbdd", "Bases de datos", "logo:bbdd"), ("docker", "Docker", "logo:docker"),
                 ("node", "Node", "logo:node")]),
    ("SISTEMA", [("dominios", "Dominios y hosts", "network"), ("config", "Configuración", "gearshape")]),
]

/// Apariencia (~/.lvm-instalador/apariencia, el mismo fichero que en Linux): iconos en color, Docker, Node
/// y PHP con su logotipo, y qué apartados no salen en el menú lateral (Proyectos y Configuración, siempre)
let LOOK_FILE = LOG_DIR + "/apariencia"
let NAV_FIXED: Set<String> = ["proyectos", "config"]
/// Color de los símbolos del sistema con los iconos en color
let NAV_TINTS: [String: Color] = ["proyectos": hexColor(0xE8A23A), "dominios": hexColor(0x1C9C6B), "config": hexColor(0x7C6FD8)]

struct LookConf: Equatable {
    var color = false
    var marcas = false
    var ocultos: Set<String> = []
}

func loadLook() -> LookConf {
    var c = LookConf()
    guard let data = FileManager.default.contents(atPath: LOOK_FILE),
          let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return c }
    let keys = Set(NAV.flatMap { $0.1.map { $0.0 } }).subtracting(NAV_FIXED)
    c.color = o["color"] as? Bool ?? false
    c.marcas = o["marcas"] as? Bool ?? false
    c.ocultos = Set((o["ocultos"] as? [String] ?? []).filter { keys.contains($0) })
    return c
}

func saveLook(_ c: LookConf) {
    if SIMULATE { return }
    let o: [String: Any] = ["color": c.color, "marcas": c.marcas, "ocultos": c.ocultos.sorted()]
    guard let data = try? JSONSerialization.data(withJSONObject: o) else { return }
    try? FileManager.default.createDirectory(atPath: LOG_DIR, withIntermediateDirectories: true,
                                             attributes: [.posixPermissions: 0o700])
    let tmp = LOOK_FILE + ".nuevo"
    if FileManager.default.createFile(atPath: tmp, contents: data) {
        _ = try? FileManager.default.replaceItemAt(URL(fileURLWithPath: LOOK_FILE), withItemAt: URL(fileURLWithPath: tmp))
        if !FileManager.default.fileExists(atPath: LOOK_FILE) { try? FileManager.default.moveItem(atPath: tmp, toPath: LOOK_FILE) }
    }
}

/// Los logotipos con su tipografía: los oficiales de Docker (docker.com), Node.js (nodejs.org; letra oscura en
/// el tema claro y clara en el oscuro) y PHP (php.net), en PDF (vectoriales, nítidos a cualquier tamaño)
let BRAND_PDF: [String: String] = [
    "docker": "JVBERi0xLjcKJbXtrvsKNCAwIG9iago8PCAvTGVuZ3RoIDUgMCBSCiAgIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCj4+CnN0cmVhbQp4nIVXS44jNwzd6xS6wDgi9SnpGLPKOjDi6YUdYCb3B8LPo6rc6SBooKv4SqTIR4qiKRf5+0byj8fM91f6mcqNWi9r5nKrx2gHZcq/fuTf/ij5x9+p1paJZE3h/MqV+22slam0W8+11Nsssr6wfed53KYYojJuVZ53RfIqt1E4ZT6mfT2OG4kJHtXE0fWzru3TtAYZ/hSg2WbjkL1EbPoUI11stWZrV3Vbrcsn3baroSbbq1vk+tyWrSL2HcMuVXgmKhplY/OERc2iqAvPYnuFfBfy4v2Zv+FjXzmxm13OEY/M3N2j6ZblqXxVMh2unKvyyLUbf/fcq4riH6lfE7RKpoi7PrGMlu8aiEXsFm0DnkX5EMKUhyQOLHLfjMPK5AQJMfqssr/lEfhdkAHKinss8faciJxBF0PS5SgSUXnmjzS7vS4n5JWbJC2kp0vEy1x+Ziw+gY9E1VOxDQilutM2AfnUCY03K8e6ar0k3nr167mBix3oXO0wO4+nHS/pix0Ap1boXO3Uw7g8zVjuTiMmngpYfrUAqlDf4BUSeJ31pNTeTza3GtjbipBteSwOXfCxdYOyrRyAa2P5J+1yUSwXHakyxI6FG3jXfaSmZ1grvUYrauReB1KntxeW1mS2IZP0E28wQJKUqvhPw+mvFkfDUYB4FzJZaxZfJ6oCjbBJ0mSPZC3GjySg3Io1q16h+S5GWTxtvXUJR9IVKtMkP09M7JaOY8cq3u73u3DVtGdarcyojMZvSKuo0KZhbUn0tD+16IRkjWMrL2+U2zxkZae8r1jQEHwoMRuIHUJuiGbGiYF/nyL4OqpHGkv9j5y+sstcnPxhuzGiG4wuCVna6+FZ5oi3NzcdBkI+i2YjTKqebb+wbMLdtp2aQ//oLnLxy+vNYQ1rdJz0M4hAwPuoKF3GjYjtQpYdC6GUAfXpXcJMXOUzkECEeQ3ITCCF5vzexQHdpa4tbR9D/VMUX0f2SMeIyzeSeHR+Q45GO3J7R8nY+/RDAJ2kl2tWk+6oLZvDK0m/7DJshh3ivCVvhpOzVhAHSJqldDw3h96F+z/K5hjzUxkdTNcVQp2o2gUvA5ElDPJJzkZoeaC84grRgHxuSqinWUbcU9rQCcXg3QERCGWENB0LYxiQZ07HQnKlkoy/fcl6LG9ZsYr6+CJTjzQxQlgbe+U5fTm6Wog2aNgVteSLXbkd49HynpYuCDsD1AcSsNbwNggTno4TsW3sUE6v1BO6LGoYK/+FwNmPz8E8ZJxh1M7guN5OaI8E5SvIJzqaHeVUGmp/wdnS1xsgU1vR0fdtzYyRsWBwlsLtWpyetrv603FsJ8Yr0jnWGCo1biUv96hQ31tZP2uWCnmVBLSmX4BcfDQMOY7fln0o1BDJhjjzpvQRHdDrh8ra442tMCI1NlqYxh1IxrZHJ7d8iUGptUhBiWIFpHxPuo7sSiXZiehwxRxkPz6WC79cfEEte5B3llEjscF/OPJI3/NPKZJWpHo1QFip+def+ff81//8ciJtMTMqGdXV/N4854ANrY7Du/UcSVeIaEQJWo8zfgv4RbNbPYJHYvEDSwlqKyz70dsIYeBXCGP9BbL6tHYyYu4Jh5pfDycgP+tiLPmCAeE0/QOrDdcYCmVuZHN0cmVhbQplbmRvYmoKNSAwIG9iagogICAxMjE5CmVuZG9iagozIDAgb2JqCjw8CiAgIC9FeHRHU3RhdGUgPDwKICAgICAgL2EwIDw8IC9DQSAxIC9jYSAxID4+CiAgID4+Cj4+CmVuZG9iago3IDAgb2JqCjw8IC9UeXBlIC9PYmpTdG0KICAgL0xlbmd0aCA4IDAgUgogICAvTiAxCiAgIC9GaXJzdCA0CiAgIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCj4+CnN0cmVhbQp4nDNTMOCK5orlAgAGOAFdCmVuZHN0cmVhbQplbmRvYmoKOCAwIG9iagogICAxNgplbmRvYmoKOSAwIG9iago8PCAvVHlwZSAvT2JqU3RtCiAgIC9MZW5ndGggMTIgMCBSCiAgIC9OIDQKICAgL0ZpcnN0IDIzCiAgIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCj4+CnN0cmVhbQp4nFWRwWrDMBBE7/6KuZTaFOJdu05CMDnEgVBKwTi9lR6EIhxDsYwkl+bvKzlxStFpHzOaWZZBERMKijJwwREz8lURlSXS98ugkNaiVTYCkL52J4sPZCA0+JxQpcfegaPtdnLURp9GqQxiKTqjwQteLwjx2bnBbtJ0oq0Rw7mTdqFNmyTXb4wSrtP9XjiFeL/JKFsy04qXVFD+RPxIlMwhf7Xw4KODvxZGhR6h2QTe1KkTO/3j65J/nBWEbLm+t+6d11s83w0Ho8cBZRmGMF9DJjqjo6dG9HYIYfIy4xc4M6p5qrxqr747qZrDLkBfOvBGWT0aqSzye+bRG6W7drf+DP/2q4QTX7q9redPcNvOi34BbpZu9AplbmRzdHJlYW0KZW5kb2JqCjEyIDAgb2JqCiAgIDI3OAplbmRvYmoKMTMgMCBvYmoKPDwgL1R5cGUgL1hSZWYKICAgL0xlbmd0aCA1OQogICAvRmlsdGVyIC9GbGF0ZURlY29kZQogICAvU2l6ZSAxNAogICAvVyBbMSAyIDJdCiAgIC9Sb290IDExIDAgUgogICAvSW5mbyAxMCAwIFIKPj4Kc3RyZWFtCnicY2Bg+P+fiYGTgQFEMDGymjEwMDLwAwlWeZAYO4hVByTYGECEKEQdI4hgZmSfDxRj38bAAAC+7gS3CmVuZHN0cmVhbQplbmRvYmoKc3RhcnR4cmVmCjE5NzQKJSVFT0YK",
    "node-claro": "JVBERi0xLjcKJbXtrvsKNCAwIG9iago8PCAvTGVuZ3RoIDUgMCBSCiAgIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCj4+CnN0cmVhbQp4nDNUMABCXUMgYWGgkJzLVQiE+okGCunFCvoV5gou+VyBQAgAnvAIYwplbmRzdHJlYW0KZW5kb2JqCjUgMCBvYmoKICAgNDEKZW5kb2JqCjMgMCBvYmoKPDwKICAgL0V4dEdTdGF0ZSA8PAogICAgICAvYTAgPDwgL0NBIDEgL2NhIDEgPj4KICAgPj4KICAgL1hPYmplY3QgPDwgL3g3IDcgMCBSID4+Cj4+CmVuZG9iago3IDAgb2JqCjw8IC9MZW5ndGggMTAgMCBSCiAgIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCiAgIC9UeXBlIC9YT2JqZWN0CiAgIC9TdWJ0eXBlIC9Gb3JtCiAgIC9CQm94IFsgMCAwIDI2NyA4MCBdCiAgIC9Hcm91cCA8PAogICAgICAvVHlwZSAvR3JvdXAKICAgICAgL1MgL1RyYW5zcGFyZW5jeQogICAgICAvSSB0cnVlCiAgICAgIC9DUyAvRGV2aWNlUkdCCiAgID4+CiAgIC9SZXNvdXJjZXMgOSAwIFIKPj4Kc3RyZWFtCnicK+TSTy82UEgv5ipU0C82NASyFPQrDI0UXPIVArkCuQCNoQgbCmVuZHN0cmVhbQplbmRvYmoKMTAgMCBvYmoKICAgMzgKZW5kb2JqCjkgMCBvYmoKPDwKICAgL0V4dEdTdGF0ZSA8PAogICAgICAvZ3MwIDw8IC9CTSAvTm9ybWFsIC9TTWFzayAvTm9uZSAvQ0EgMS4wIC9jYSAxLjAgPj4KICAgICAgL3MxMSAxMSAwIFIKICAgPj4KICAgL1hPYmplY3QgPDwgL3gxMiAxMiAwIFIgPj4KPj4KZW5kb2JqCjEzIDAgb2JqCjw8IC9UeXBlIC9YT2JqZWN0CiAgIC9MZW5ndGggNDIKICAgL0ZpbHRlciAvRmxhdGVEZWNvZGUKICAgL1N1YnR5cGUgL0Zvcm0KICAgL0JCb3ggWyAwIDAgMjY3IDc5IF0KICAgL0dyb3VwIDw8CiAgICAgIC9UeXBlIC9Hcm91cAogICAgICAvUyAvVHJhbnNwYXJlbmN5CiAgICAgIC9JIHRydWUKICAgICAgL0NTIC9EZXZpY2VSR0IKICAgPj4KICAgL1Jlc291cmNlcwo8PAogICAvRXh0R1N0YXRlIDw8CiAgICAgIC9nczAgPDwgL0JNIC9Ob3JtYWwgL1NNYXNrIC9Ob25lIC9DQSAxLjAgL2NhIDEuMCA+PgogICAgICAvYTAgPDwgL0NBIDEgL2NhIDEgPj4KICAgPj4KICAgL1hPYmplY3QgPDwgL3gxNCAxNCAwIFIgPj4KPj4KPj4Kc3RyZWFtCnicK+QyMjNXMABCXQsQCSSSc7n0Ew0U0osV9CsMTRRc8rkCuQCgEwhgCmVuZHN0cmVhbQplbmRvYmoKMTIgMCBvYmoKPDwgL1R5cGUgL1hPYmplY3QKICAgL0xlbmd0aCAyOAogICAvRmlsdGVyIC9GbGF0ZURlY29kZQogICAvU3VidHlwZSAvRm9ybQogICAvQkJveCBbIDAgMCAyNjcgNzkgXQogICAvR3JvdXAgPDwKICAgICAgL1R5cGUgL0dyb3VwCiAgICAgIC9TIC9UcmFuc3BhcmVuY3kKICAgICAgL0kgdHJ1ZQogICAgICAvQ1MgL0RldmljZVJHQgogICA+PgogICAvUmVzb3VyY2VzCjw8CiAgIC9FeHRHU3RhdGUgPDwKICAgICAgL2dzMCA8PCAvQk0gL05vcm1hbCAvU01hc2sgL05vbmUgL0NBIDEuMCAvY2EgMS4wID4+CiAgICAgIC9hMCA8PCAvQ0EgMSAvY2EgMSA+PgogICA+PgogICAvWE9iamVjdCA8PCAveDE1IDE1IDAgUiA+Pgo+Pgo+PgpzdHJlYW0KeJwr5NJPNFBIL1bQrzA0VXDJ5wrkAgAwiwSbCmVuZHN0cmVhbQplbmRvYmoKMTYgMCBvYmoKPDwgL1R5cGUgL01hc2sKICAgL1MgL0FscGhhCiAgIC9HIDEzIDAgUgo+PgplbmRvYmoKMTEgMCBvYmoKPDwgL1R5cGUgL0V4dEdTdGF0ZQogICAvU01hc2sgMTYgMCBSCiAgIC9jYSAxCiAgIC9DQSAxCiAgIC9BSVMgZmFsc2UKPj4KZW5kb2JqCjE3IDAgb2JqCjw8IC9MZW5ndGggMTggMCBSCiAgIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCiAgIC9UeXBlIC9YT2JqZWN0CiAgIC9TdWJ0eXBlIC9JbWFnZQogICAvV2lkdGggMjY3CiAgIC9IZWlnaHQgODAKICAgL0NvbG9yU3BhY2UgL0RldmljZUdyYXkKICAgL0ludGVycG9sYXRlIHRydWUKICAgL0JpdHNQZXJDb21wb25lbnQgOAo+PgpzdHJlYW0KeJztwTENAAAMAyCt8y+iuyqiCZAAAAAAAAAAAAAAAAAAAAAAAAAAADDvqAdqbnyVCmVuZHN0cmVhbQplbmRvYmoKMTggMCBvYmoKICAgNDgKZW5kb2JqCjE0IDAgb2JqCjw8IC9MZW5ndGggMTkgMCBSCiAgIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCiAgIC9UeXBlIC9YT2JqZWN0CiAgIC9TdWJ0eXBlIC9JbWFnZQogICAvV2lkdGggMjY3CiAgIC9IZWlnaHQgODAKICAgL0NvbG9yU3BhY2UgL0RldmljZUdyYXkKICAgL0ludGVycG9sYXRlIHRydWUKICAgL0JpdHNQZXJDb21wb25lbnQgMQogICAvU01hc2sgMTcgMCBSCj4+CnN0cmVhbQp4nO3BMQEAAADCoPVPbQ0PoAAA4McACqAAAQplbmRzdHJlYW0KZW5kb2JqCjE5IDAgb2JqCiAgIDI2CmVuZG9iagoxNSAwIG9iago8PCAvTGVuZ3RoIDIxIDAgUgogICAvRmlsdGVyIC9GbGF0ZURlY29kZQogICAvVHlwZSAvWE9iamVjdAogICAvU3VidHlwZSAvRm9ybQogICAvQkJveCBbIDAgMCAyNjcgODAgXQogICAvUmVzb3VyY2VzIDIwIDAgUgo+PgpzdHJlYW0KeJztWcvK3sgR3esptA6M3PfLY8wq6yDG9kJ/wOP3h5xzqlqSPTOEQCCbYGy+U+qurqqua/vb9unL97B/+b6FI/dUy9zD0VIvNeJHDnWMtP/+Zf/0Dy1KuRxzlL2Po9eyf+wkYJURgPLRSiSqvQiGKphK2889pXbMvPdy1NG2/RIhhEFK6EOwtLn3fIwZBTs2Eoao/R3HDxLyyIBgHOdGnMYEnkclt3TUausn5KkklNoFR7LvoQjOpq91DiyXeg3n1aOkRPGARykk1JgAK8T8AaYY13IcV7P0buXoKUs/UHodpLScBUdNhAVivWCK1RmQUNIxWvf9IGyktNxvfoAFV7UOBMxVDFykHI8exIAip05Ci9k07PPGrrAvx/7YjoTPzvASIWLhOhAwJME2tjekvOdNcI2uNyHDxovdsocdt7nFdGPxyLBt63IkekiRAm0eIdMl6tEzP5cH4F/c/ukYxgK3OLVZCwrNbctni4SxFXlXGnXBU+5EqZxwbaLM0J4d84jw/kJl6hvyuPMmuEDXImyUXhcO/00BARBxbXT3rDBySAawKzjf36PsumCEe8MXelj+FmFGhMNjrJiPQgLDjBsSoxLiNDiVIXlnati+3RRc37TtjnFeysZtwhvDAcHv0zKkyIouD+8NVhq5ebzECTcZUHvI+Trc64YQK5bdl9Pd4a29L440eEUCAIVHZqysXX60BBKMLu95Y9fougkbVS7D2WXZQ/Fm57m9zlsiJCicdgnnli1/SfzWaXDLdj8lv3P/vCUI2qYkYGJgPrRAdULK4Zg8kdk13pBimrsbYdurS4hITIhEwEaHA6RlHJrJJ+7eCY/FnaD4LpmQeWShfsQkB/XorzD4sAQ2EOaQriMQqEyHHQxuXA/XbiE9CxAxyD7Yzqi4YUdWlXSLAGEStC2Vp0E5RiHvfx5Uvh4x9yUNDFlxCMSjstzGnBbbDcuUS5+LgPBe7Gx7Wesh1WwLnjqeVWR9L0NRCSqLQwLfWFGEim07nQLbhiPSdwhR2QATahZh0McSTVekhtRIYMlx7hsxLUZMD3TotoFrOuGSeBO1jgym2ao5/2EwZLFjRjFtKF3pVgigVUdQgusI1ZSveUErBExKTthWYYBYzHk3nMpkT+GowW0L2wUIF2kknBZlQ8Ax3TPgUx0Ur0tgNKhuptgPhLAuvRFalJY0Bi51u8PkxzDCeoQo3RrnIn98PBj9BdVFfFddpRJTy0xw28LcHsVPBIgD/+VVcneqDhfz8/4MGzYmL9u87XmI7OwJg9oEnY6wcsKSjdt7+kl0447Q3F66iEBpcuL2xApiW6neXNBOSq093xudZ+PWNOLCr6MMeySs3ZDT9DLuDs1Kc0jPHs0sPAV3EXJ9xLyZoydIS8sPseNdO+GCjzWWyccO6DxG+hl6jjkfQlTG52aFOxsT5AziXHR8j8rVIAyYmwQmY8BZVAui7rSoM/Q+ydnnqs6JRf8+zrMBIP2XLuHG8POMcL0J3CDtmJrZCcm4DyyLAdYBo04L2VeTDraa2aHiB5QY0lpwPYSslvda9r7x141LQpVnwfs+bsc0fN0SCEo+q+WBEbdgOEZ3CW5KNtcbo7+QOAuZtCEufD2YR21/KtxnDBRpX38xQdCwXdIxUX28cExK0ir0OCDLiMX6gmnJ1o5LLMs2NqgTAc6Dbb1kHpanjX+6R47ImuOQLY71ocLsgKyrdEZBvqZjsBWSTWWF0dkdITMzw3IqivsvCJJg1p0ou2HpdWJZKJ0zRZapbshbDGo/MK2wmww2miALlKHToKJGGZbmqL7lBnSeZyV+MFki2AdOQFtGFwJksMeiLeyAWDYJp9rtwjRvkEUm207eGJoB6BCrmjkUCCb+WFXxgTJT4blsw+qZzI507ypjABT2wdXavGg9c5X5Tr8eg2ypFf/MzJzY6DTVuWIpxzs/lIdYYpJICCLUY6Yn9S6bwea6nAu6pteNq2WXaV2Z2SizG6tmwELlcHmja+zM0o5BbHMnbQnE6WihbDOgrT2Ji91jVJY3t/YLf1BWIH3d0PpgxK07m4yIMCBmFfnFHCWiA6WkL8hxyFbz6qv6RLWTmyAthLsp6UZWs88bs6es8hQRNB1WXDxhrfqOfty48TqBrSMiIbDQJXVskQ3XD4g++qxO5kibXxTOY6ffFH0cWiOvt/8AaWVfDgahm28E87EtBiUkjjIxNNVclYNqME9eDTU5bwLTutL3TWhWBsgLvxlNfgzqdMqKJxeEXf8wuU1QuMRSQT+l37bWMZqmGgnndInA9wI/SK2jjqUVCflU4iJi/loUmyeuG3dlnMUM/jHacxaq8XBP0njCJouu9rG/CJRe14uxsQ5WBV0u4hEoaXiJiq6JTIH7VMiQwmkDBKpDqFH8gczUvpwMokqfc8T0Rgrjy08Eii5OfqNemm/3eOYjzPUm4Hoebgx4JKZ1HOcBS88uEJNHay4/BS5VjunqbG+sltjWn7dJnON1W2yd6PakQOi2themxLyDFJLqiS9BTQ5Z0cHGGoMkYbWsqgexBbsC9lwEdSlJNXyt8DoFyIYw2GvNOi14ao0j63WFTjqrQmYk+RwozHtxwGghPTAoH/l6MEALyFrEebvI9ZvyKQ/kcBQ56vVsVb0YbAo7FrLzJrD70ovZTagW42SXwKhZ+K7zOJA3JTRIxDBFTDGrXpI4dY3gql8jaRpzKP1sBLdBIc4iy/aoruwSgX1ht3ck2ElO1YM0fsEyNu2/CWyT1u5m74aLO59vTNxebGgbesa6RFBLziF4ZGFO+oB8InxBmx1uQlBHc90Er8KbMyTGHLjO47A5lXJGlEOYS5u56LyspywBgLwIg5vMpzcuW8/9MCSrszG8ROhdDstRKY6pB9nVFBjclrznvaAyVLT/xnwbIeTLDR9eQhLkwAZYkcSY84Z5VLUUOYMc60F86F2r/yzAPv/t37xU0wQecqwUHyJoGBya/giZXm+YrJW15VRQzwtSeagNIYXtAQimog/u1rm+YA7TGYhQOTgxLT6EkZOxg6vIYmOdR6WDHgGXRCuvLok3UtgBLoVekAo/mb3bg4xzvERo4z4QSHVsyWPY5T0fbApdbwIbTeM2bnPYaW4vS4t/uAPc2retN+sWp1qbDz2jdz0H8vmHfj9ukK2Lt6Unn4iUmIM9F198aGBt5DSJA4CsN7h/Js0Rp0OOjqPbtmIPxigEVSOP5SZ6sJ3B1JS41WVAqmEjebmALP6zLNkXkmbbWnvusyrPOq9rn43v1X7QbLoel2IhE/F0vC0VrrVA2k17n3S1/RSzigz/s4n/vv9zQ3jgj97VShohRDMyXO1js//W2T99/4qk8f3r9uv26/5t0/y0F974/vtvYvL/u/uf3B2CpurtFh0pe84PctH/UQTpcO3+vU9/tqg2pdhso8n8Zw7/gU9k84k/SuGn/KUULuV/R4rinrn9C6hJkPcKZW5kc3RyZWFtCmVuZG9iagoyMSAwIG9iagogICAyNTg4CmVuZG9iagoyMCAwIG9iago8PAogICAvRXh0R1N0YXRlIDw8CiAgICAgIC9nczAgPDwgL0JNIC9Ob3JtYWwgL1NNYXNrIC9Ob25lIC9DQSAxLjAgL2NhIDEuMCA+PgogICAgICAvYTAgPDwgL0NBIDEgL2NhIDEgPj4KICAgPj4KICAgL1NoYWRpbmcgPDwgL3NoMjIgMjIgMCBSIC9zaDIzIDIzIDAgUiAvc2gyNCAyNCAwIFIgPj4KPj4KZW5kb2JqCjI1IDAgb2JqCjw8IC9GdW5jdGlvblR5cGUgMgogICAvRG9tYWluIFsgMCAxIF0KICAgL0MwIFsgMC4yNDcwNTkgMC41NDUwOTggMC4yMzkyMTYgXQogICAvQzEgWyAwLjI0NzA1OSAwLjUyOTQxMiAwLjI0NzA1OSBdCiAgIC9OIDEKPj4KZW5kb2JqCjI2IDAgb2JqCjw8IC9GdW5jdGlvblR5cGUgMgogICAvRG9tYWluIFsgMCAxIF0KICAgL0MwIFsgMC4yNDcwNTkgMC41Mjk0MTIgMC4yNDcwNTkgXQogICAvQzEgWyAwLjIzOTIxNiAwLjY2Mjc0NSAwLjE4MDM5MiBdCiAgIC9OIDEKPj4KZW5kb2JqCjI3IDAgb2JqCjw8IC9GdW5jdGlvblR5cGUgMgogICAvRG9tYWluIFsgMCAxIF0KICAgL0MwIFsgMC4yMzkyMTYgMC42NjI3NDUgMC4xODAzOTIgXQogICAvQzEgWyAwLjIzOTIxNiAwLjY4MjM1MyAwLjE2ODYyNyBdCiAgIC9OIDEKPj4KZW5kb2JqCjI4IDAgb2JqCjw8IC9GdW5jdGlvblR5cGUgMwogICAvRG9tYWluIFsgMCAxIF0KICAgL0Z1bmN0aW9ucyBbIDI1IDAgUiAyNiAwIFIgMjcgMCBSIF0KICAgL0JvdW5kcyBbIDAuNjQgMC45MyBdCiAgIC9FbmNvZGUgWyAwIDEgMCAxIDAgMSBdCj4+CmVuZG9iagoyMiAwIG9iagogICAgICA8PCAvU2hhZGluZ1R5cGUgMgogICAgICAgICAvQ29sb3JTcGFjZSAvRGV2aWNlUkdCCiAgICAgICAgIC9Db29yZHMgWyAzMC4zMyA4LjU2IDE0LjkgNDQuNzAwMDAxIF0KICAgICAgICAgL0RvbWFpbiBbIDAgMSBdCiAgICAgICAgIC9FeHRlbmQgWyB0cnVlIHRydWUgXQogICAgICAgICAvRnVuY3Rpb24gMjggMCBSCiAgICAgID4+CmVuZG9iagoyOSAwIG9iago8PCAvRnVuY3Rpb25UeXBlIDIKICAgL0RvbWFpbiBbIDAgMSBdCiAgIC9DMCBbIDAuMjQ3MDU5IDAuNTI5NDEyIDAuMjQ3MDU5IF0KICAgL0MxIFsgMC4zMjE1NjkgMC42Mjc0NTEgMC4yNjY2NjcgXQogICAvTiAxCj4+CmVuZG9iagozMCAwIG9iago8PCAvRnVuY3Rpb25UeXBlIDIKICAgL0RvbWFpbiBbIDAgMSBdCiAgIC9DMCBbIDAuMzIxNTY5IDAuNjI3NDUxIDAuMjY2NjY3IF0KICAgL0MxIFsgMC4zOTIxNTcgMC43MTc2NDcgMC4yODYyNzUgXQogICAvTiAxCj4+CmVuZG9iagozMSAwIG9iago8PCAvRnVuY3Rpb25UeXBlIDIKICAgL0RvbWFpbiBbIDAgMSBdCiAgIC9DMCBbIDAuMzkyMTU3IDAuNzE3NjQ3IDAuMjg2Mjc1IF0KICAgL0MxIFsgMC40MTU2ODYgMC43NDkwMiAwLjI5NDExOCBdCiAgIC9OIDEKPj4KZW5kb2JqCjMyIDAgb2JqCjw8IC9GdW5jdGlvblR5cGUgMwogICAvRG9tYWluIFsgMC4xNCAwLjkxIF0KICAgL0Z1bmN0aW9ucyBbIDI5IDAgUiAzMCAwIFIgMzEgMCBSIF0KICAgL0JvdW5kcyBbIDAuNCAwLjcxIF0KICAgL0VuY29kZSBbIDAgMSAwIDEgMCAxIF0KPj4KZW5kb2JqCjIzIDAgb2JqCiAgICAgIDw8IC9TaGFkaW5nVHlwZSAyCiAgICAgICAgIC9Db2xvclNwYWNlIC9EZXZpY2VSR0IKICAgICAgICAgL0Nvb3JkcyBbIDI1LjY4Nzk5OSAyMy4xMDM5OTkgNjMuNTcyMDAxIDIuNzc1OTk5IF0KICAgICAgICAgL0RvbWFpbiBbIDAuMTQgMC45MSBdCiAgICAgICAgIC9FeHRlbmQgWyB0cnVlIHRydWUgXQogICAgICAgICAvRnVuY3Rpb24gMzIgMCBSCiAgICAgID4+CmVuZG9iagozMyAwIG9iago8PCAvRnVuY3Rpb25UeXBlIDIKICAgL0RvbWFpbiBbIDAgMSBdCiAgIC9DMCBbIDAuNDE1Njg2IDAuNzQ5MDIgMC4yOTQxMTggXQogICAvQzEgWyAwLjM5MjE1NyAwLjcxNzY0NyAwLjI4NjI3NSBdCiAgIC9OIDEKPj4KZW5kb2JqCjM0IDAgb2JqCjw8IC9GdW5jdGlvblR5cGUgMgogICAvRG9tYWluIFsgMCAxIF0KICAgL0MwIFsgMC4zOTIxNTcgMC43MTc2NDcgMC4yODYyNzUgXQogICAvQzEgWyAwLjMyMTU2OSAwLjYyNzQ1MSAwLjI2NjY2NyBdCiAgIC9OIDEKPj4KZW5kb2JqCjM1IDAgb2JqCjw8IC9GdW5jdGlvblR5cGUgMgogICAvRG9tYWluIFsgMCAxIF0KICAgL0MwIFsgMC4zMjE1NjkgMC42Mjc0NTEgMC4yNjY2NjcgXQogICAvQzEgWyAwLjI0NzA1OSAwLjUyOTQxMiAwLjI0NzA1OSBdCiAgIC9OIDEKPj4KZW5kb2JqCjM2IDAgb2JqCjw8IC9GdW5jdGlvblR5cGUgMwogICAvRG9tYWluIFsgMC4wOSAwLjg2IF0KICAgL0Z1bmN0aW9ucyBbIDMzIDAgUiAzNCAwIFIgMzUgMCBSIF0KICAgL0JvdW5kcyBbIDAuMjkgMC42IF0KICAgL0VuY29kZSBbIDAgMSAwIDEgMCAxIF0KPj4KZW5kb2JqCjI0IDAgb2JqCiAgICAgIDw8IC9TaGFkaW5nVHlwZSAyCiAgICAgICAgIC9Db2xvclNwYWNlIC9EZXZpY2VSR0IKICAgICAgICAgL0Nvb3JkcyBbIDQuMTg3NSAyNC41IDM3Ljg3NTAwMSAyNC41IF0KICAgICAgICAgL0RvbWFpbiBbIDAuMDkgMC44NiBdCiAgICAgICAgIC9FeHRlbmQgWyB0cnVlIHRydWUgXQogICAgICAgICAvRnVuY3Rpb24gMzYgMCBSCiAgICAgID4+CmVuZG9iago4IDAgb2JqCjw8IC9UeXBlIC9PYmpTdG0KICAgL0xlbmd0aCAzNyAwIFIKICAgL04gMQogICAvRmlyc3QgNAogICAvRmlsdGVyIC9GbGF0ZURlY29kZQo+PgpzdHJlYW0KeJwzUzDgiuaK5QIABjgBXQplbmRzdHJlYW0KZW5kb2JqCjM3IDAgb2JqCiAgIDE2CmVuZG9iagozOCAwIG9iago8PCAvVHlwZSAvT2JqU3RtCiAgIC9MZW5ndGggNDEgMCBSCiAgIC9OIDQKICAgL0ZpcnN0IDIzCiAgIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCj4+CnN0cmVhbQp4nFWRwWrDMBBE7/qKuZTGFOKVnThpMDnEhlBKISS9lR6EIhxBsYwkl+bvKzmxS9FpH7OaGZaDWP6MJbEMfMnZgpCvclaWSN+vnUJ6EI1yDED6qs8OH8hAOOJzQJXpWw/Ottth42DNuZfKYiaFtgZ8ztdzwuzifec2aTrQxoruoqWbG9skye0bq4TXpq2FV5jVm4yygnNa8YKWlD8RfyRKRpO/WHgI1nH/IKyKOWKyAbypsxY78xPiUnhZscKapsytD2qHxSTfW9N3KMs4xPlmMdARnQK1onVdtJLXEb/A216NUxVUtfrWUh33uwhD5MiPypneSuWQT56nsCj9LbkLR/jXrhJefJnmXi4c4N4tiH4BvtJungplbmRzdHJlYW0KZW5kb2JqCjQxIDAgb2JqCiAgIDI3OAplbmRvYmoKNDIgMCBvYmoKPDwgL1R5cGUgL1hSZWYKICAgL0xlbmd0aCAxNDgKICAgL0ZpbHRlciAvRmxhdGVEZWNvZGUKICAgL1NpemUgNDMKICAgL1cgWzEgMiAyXQogICAvUm9vdCA0MCAwIFIKICAgL0luZm8gMzkgMCBSCj4+CnN0cmVhbQp4nCXOuw4BURSF4XXGhOlE3G8ziUKhVuj1el5EpeMBtAqNRq0TDdET7yDxEBKsP5ov56y1d7Ilfb+R+hJEQRspqAgrsoTXx3TPJhpBz+RnJl7wvZnC3SQvihQOZEeyhymfYGdqFM2r6TBcmZtqDGtadutL0yjBluGBae1NewgXdicmHcP0f3iAXMiezrK39AOkKBjYCmVuZHN0cmVhbQplbmRvYmoKc3RhcnR4cmVmCjgxODcKJSVFT0YK",
    "node-oscuro": "JVBERi0xLjcKJbXtrvsKNCAwIG9iago8PCAvTGVuZ3RoIDUgMCBSCiAgIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCj4+CnN0cmVhbQp4nDNUMABCXUMgYWGgkJzLVQiE+okGCunFCvoV5gou+VyBQAgAnvAIYwplbmRzdHJlYW0KZW5kb2JqCjUgMCBvYmoKICAgNDEKZW5kb2JqCjMgMCBvYmoKPDwKICAgL0V4dEdTdGF0ZSA8PAogICAgICAvYTAgPDwgL0NBIDEgL2NhIDEgPj4KICAgPj4KICAgL1hPYmplY3QgPDwgL3g3IDcgMCBSID4+Cj4+CmVuZG9iago3IDAgb2JqCjw8IC9MZW5ndGggMTAgMCBSCiAgIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCiAgIC9UeXBlIC9YT2JqZWN0CiAgIC9TdWJ0eXBlIC9Gb3JtCiAgIC9CQm94IFsgMCAwIDI2NyA4MCBdCiAgIC9Hcm91cCA8PAogICAgICAvVHlwZSAvR3JvdXAKICAgICAgL1MgL1RyYW5zcGFyZW5jeQogICAgICAvSSB0cnVlCiAgICAgIC9DUyAvRGV2aWNlUkdCCiAgID4+CiAgIC9SZXNvdXJjZXMgOSAwIFIKPj4Kc3RyZWFtCnicK+TSTy82UEgv5ipU0C82NASyFPQrDI0UXPIVArkCuQCNoQgbCmVuZHN0cmVhbQplbmRvYmoKMTAgMCBvYmoKICAgMzgKZW5kb2JqCjkgMCBvYmoKPDwKICAgL0V4dEdTdGF0ZSA8PAogICAgICAvZ3MwIDw8IC9CTSAvTm9ybWFsIC9TTWFzayAvTm9uZSAvQ0EgMS4wIC9jYSAxLjAgPj4KICAgICAgL3MxMSAxMSAwIFIKICAgPj4KICAgL1hPYmplY3QgPDwgL3gxMiAxMiAwIFIgPj4KPj4KZW5kb2JqCjEzIDAgb2JqCjw8IC9UeXBlIC9YT2JqZWN0CiAgIC9MZW5ndGggNDIKICAgL0ZpbHRlciAvRmxhdGVEZWNvZGUKICAgL1N1YnR5cGUgL0Zvcm0KICAgL0JCb3ggWyAwIDAgMjY3IDc5IF0KICAgL0dyb3VwIDw8CiAgICAgIC9UeXBlIC9Hcm91cAogICAgICAvUyAvVHJhbnNwYXJlbmN5CiAgICAgIC9JIHRydWUKICAgICAgL0NTIC9EZXZpY2VSR0IKICAgPj4KICAgL1Jlc291cmNlcwo8PAogICAvRXh0R1N0YXRlIDw8CiAgICAgIC9nczAgPDwgL0JNIC9Ob3JtYWwgL1NNYXNrIC9Ob25lIC9DQSAxLjAgL2NhIDEuMCA+PgogICAgICAvYTAgPDwgL0NBIDEgL2NhIDEgPj4KICAgPj4KICAgL1hPYmplY3QgPDwgL3gxNCAxNCAwIFIgPj4KPj4KPj4Kc3RyZWFtCnicK+QyMjNXMABCXQsQCSSSc7n0Ew0U0osV9CsMTRRc8rkCuQCgEwhgCmVuZHN0cmVhbQplbmRvYmoKMTIgMCBvYmoKPDwgL1R5cGUgL1hPYmplY3QKICAgL0xlbmd0aCAyOAogICAvRmlsdGVyIC9GbGF0ZURlY29kZQogICAvU3VidHlwZSAvRm9ybQogICAvQkJveCBbIDAgMCAyNjcgNzkgXQogICAvR3JvdXAgPDwKICAgICAgL1R5cGUgL0dyb3VwCiAgICAgIC9TIC9UcmFuc3BhcmVuY3kKICAgICAgL0kgdHJ1ZQogICAgICAvQ1MgL0RldmljZVJHQgogICA+PgogICAvUmVzb3VyY2VzCjw8CiAgIC9FeHRHU3RhdGUgPDwKICAgICAgL2dzMCA8PCAvQk0gL05vcm1hbCAvU01hc2sgL05vbmUgL0NBIDEuMCAvY2EgMS4wID4+CiAgICAgIC9hMCA8PCAvQ0EgMSAvY2EgMSA+PgogICA+PgogICAvWE9iamVjdCA8PCAveDE1IDE1IDAgUiA+Pgo+Pgo+PgpzdHJlYW0KeJwr5NJPNFBIL1bQrzA0VXDJ5wrkAgAwiwSbCmVuZHN0cmVhbQplbmRvYmoKMTYgMCBvYmoKPDwgL1R5cGUgL01hc2sKICAgL1MgL0FscGhhCiAgIC9HIDEzIDAgUgo+PgplbmRvYmoKMTEgMCBvYmoKPDwgL1R5cGUgL0V4dEdTdGF0ZQogICAvU01hc2sgMTYgMCBSCiAgIC9jYSAxCiAgIC9DQSAxCiAgIC9BSVMgZmFsc2UKPj4KZW5kb2JqCjE3IDAgb2JqCjw8IC9MZW5ndGggMTggMCBSCiAgIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCiAgIC9UeXBlIC9YT2JqZWN0CiAgIC9TdWJ0eXBlIC9JbWFnZQogICAvV2lkdGggMjY3CiAgIC9IZWlnaHQgODAKICAgL0NvbG9yU3BhY2UgL0RldmljZUdyYXkKICAgL0ludGVycG9sYXRlIHRydWUKICAgL0JpdHNQZXJDb21wb25lbnQgOAo+PgpzdHJlYW0KeJztwTENAAAMAyCt8y+iuyqiCZAAAAAAAAAAAAAAAAAAAAAAAAAAADDvqAdqbnyVCmVuZHN0cmVhbQplbmRvYmoKMTggMCBvYmoKICAgNDgKZW5kb2JqCjE0IDAgb2JqCjw8IC9MZW5ndGggMTkgMCBSCiAgIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCiAgIC9UeXBlIC9YT2JqZWN0CiAgIC9TdWJ0eXBlIC9JbWFnZQogICAvV2lkdGggMjY3CiAgIC9IZWlnaHQgODAKICAgL0NvbG9yU3BhY2UgL0RldmljZUdyYXkKICAgL0ludGVycG9sYXRlIHRydWUKICAgL0JpdHNQZXJDb21wb25lbnQgMQogICAvU01hc2sgMTcgMCBSCj4+CnN0cmVhbQp4nO3BMQEAAADCoPVPbQ0PoAAA4McACqAAAQplbmRzdHJlYW0KZW5kb2JqCjE5IDAgb2JqCiAgIDI2CmVuZG9iagoxNSAwIG9iago8PCAvTGVuZ3RoIDIxIDAgUgogICAvRmlsdGVyIC9GbGF0ZURlY29kZQogICAvVHlwZSAvWE9iamVjdAogICAvU3VidHlwZSAvRm9ybQogICAvQkJveCBbIDAgMCAyNjcgODAgXQogICAvUmVzb3VyY2VzIDIwIDAgUgo+PgpzdHJlYW0KeJztWcvK3sgR3esptA6M3PfLY8wq6yDG9kJ/wOP3h5xzqlqSPTOEQCCbYDDfKXVXV1XXtf9v26cv38P+5fsWjtxTLXMPR0u91IgfOdQx0v77l/3TP7Qo5XLMUfY+jl7L/rGTgFVGAMpHK5Go9iIYqmAqbT/3lNox897LUUfb9kuEEAYpoQ/B0ube8zFmFOzYSBii9nccP0jIIwOCcZwbcRoTeB6V3NJRq62fkKeSUGoXHMm+hyI4m77WObBc6jWcV4+SEsUDHqWQUGMCrBDzB5hiXMtxXM3Su5Wjpyz9QOl1kNJyFhw1ERaI9YIpVmdAQknHaN33g7CR0nK/+QEWXNU6EDBXMXCRcjx6EAOKnDoJLWbTsM8bu8K+HPtjOxI+O8NLhIiF60DAkATb2N6Q8p43wTW63oQMGy92yx523OYW043FI8O2rcuR6CFFCrR5hEyXqEfP/FwegP9x+6djGAvc4tRmLSg0ty2fLRLGVuRdadQFT7kTpXLCtYkyQ3t2zCPC+wuVqW/I486b4AJdi7BRel04/DcFBEDEtdHds8LIIRnAruB8f4+y64IR7g1f6GH5W4QZEQ6PsWI+CgkMM25IjEqI0+BUhuSdqWH7dlNwfdO2O8Z5KRu3CW8MBwS/T8uQIiu6PLw3WGnk5vESJ9xkQO0h5+twrxtCrFh2X053h7f2vjjS4BUJABQembGydvnREkgwurznjV2j6yZsVLkMZ5dlD8Wbnef2Om+JkKBw2iWcW7b8JfFbp8Et2/2U/M7985YgaJuSgImB+dAC1Qkph2PyRGbXeEOKae5uhG2vLiEiMSESARsdDpCWcWgmn7h7JzwWd4Liu2RC5pGF+hGTHNSjv8LgwxLYQJhDuo5AoDIddjC4cT1cu4X0LEDEIPtgO6Pihh1ZVdItAoRJ0LZUngblGIW8/3lQ+XrE3Jc0MGTFIRCPynIbc1psNyxTLn0uAsJ7sbPtZa2HVLMteOp4VpH1vQxFJagsDgl8Y0URKrbtdApsG45I3yFEZQNMqFmEQR9LNF2RGlIjgSXHuW/EtBgxPdCh2wau6YRL4k3UOjKYZqvm/IfBkMWOGcW0oXSlWyGAVh1BCa4jVFO+5gWtEDApOWFbhQFiMefdcCqTPYWjBrctbBcgXKSRcFqUDQHHdM+AT3VQvC6B0aC6mWI/EMK69EZoUVrSGLjU7Q6TH8MI6xGidGuci/zx8WD0F1QX8V11lUpMLTPBbQtzexQ/ESAO/JdXyd2pOlzMz/szbNiYvGzztuchsrMnDGoTdDrCyglLNm7v6SfRjTtCc3vpIgKlyYnbEyuIbaV6c0E7KbX2fG90no1b04gLv44y7JGwdkNO08u4OzQrzSE9ezSz8BTcRcj1EfNmjp4gLS0/xI537YQLPtZYJh87oPMY6WfoOeZ8CFEZn5sV7mxMkDOIc9HxPSpXgzBgbhKYjAFnUS2IutOiztD7JGefqzonFv37OM8GgPRfuoQbw88zwvUmcIO0Y2pmJyTjPrAsBlgHjDotZF9NOthqZoeKH1BiSGvB9RCyWt5r2fvGXzcuCVWeBe/7uB3T8HVLICj5rJYHRtyC4RjdJbgp2VxvjP5C4ixk0oa48PVgHrX9qXCft7jzH2YHmrRLLqaojxeOSelZJR6ss8xXrCOYlmbtoMSCbAODehDgPNjQS9phGdr4p3vYiKw2DtncWAcqzN7H+klnFORlOgZbIdlUPhidfRFyMnMr56G4/4LwCGbXiYIbll4nloXSOU1kGemGvL+gxgNzCvvIYEMJ4r8MnQYVNcSwKEd1LDeg2zwr8YNpEmE+cAIaMjoPIMM8Fm1h78OCSTjVaBcmeIMsL9l28q7QBkCHWNXGoTQw5ceqWg+UmQTPZRvWzWR2pGNXGQOgsAOu1uBF65arzHf69RhkM63IZ07mrEZ3qc4VSznY+aE8xFKSREL4oBIzMalr2Qw21+Vc0DW9blwtr0zrx8xGmX1YNQMWKofLG10DZ5Z2DF+bOGlLIM5FC2Wb/mztSVzsHqPyu7m1X/iDskLo64amB8Nt3dleRIQBMevHL+YoEb0nJX1BDkK2mldf1SGqkdwEaSHcTUk3smp93pjdZJWniKC5sOLiCWvVd3Tixo3XCWy9EAmBJS6pV4tstX5A9NFndTJH2vyicB57/Kbo47gaeb39B0gr+3IwCN18I5iPbTEoFXGIiaGp2qoQVIN58mqoyXkTmNCVuG9CswJAXvjNaPJjUKFTVjy5IOz3h8ltgsIllgr6Kf22tY7RNNVCOKdLBL4U+EFqGnUsrUjIRxIXEZPXotgkcd24K+MsZvCP0Z6zUIeHe5IGE7ZXdLWP/UWg9LpeDIx1sB7ochGPQEljS1R0TWQK3KdChhTOGSBQHUIN4Q9kpvblZBBV9Jwj5jZSGF9+IlB0cfIb9dJ8u8czn1+uNwHX83BjwCMxreM4CVh6doGYPFpz+SlwqXJMV2d7YzXDtv68TeIcr9ti60S3JwVCn7W9MCXmHaSQVE98CapxyIoOttQYIQmrZVU9hS3YFbDnIqg/Sarea4XXKUC2gsHeadZpwVNrHFnvKnTSWRUyI8nnQGHeiwNGC+mBQfnI14MBmj/WIk7aRa7flE95IMeiyCGvZ6vnxWBT2LGQnTeBfZfeym5CtRgnuwRGzcJ3ncdRvCmhQSKGKWKKWfWSxKlr+Fb9GklzmEPpZ8O3jQhxFlm2R/VjlwjsCLu9IMFOcqoepPELlrFp/01gg7R2N3sxXNz5cGPi9mLj2tAD1iWCmnGOvyMLc8YH5OPgC9rUcBOCOprrJngV3pwhMSbAdR7HzKmUM6IcwlzazEXnZT1lCQDkRRjcZD69btl67ochWZ2N4SVC73JYDklxTD3FrqbA4LbkPe8FlaGi/Tfmqwgh32z45BKSIEc1wIokxpw3zKOqpcgZ5FgP4hPvWv1nAfb5b//mjZom8JBjpfgQQWPg0NxHyPR6w2RNrC2ngnpYkMpDbQgpbA9AMBV9ZLfO9QVzmM5AhMqRiWnxIYycjB1cRRYb6zwqHfT8tyRaeXVJvJHCDnAp9IJU+Mns3Z5inOMlQhv3gUCqY0sewy7v+WBT6HoT2Ggat3Gbw05ze1la/MMd4Na+bb1ZtzjV2nzoAb3rIZAPP/T7cYNsXbwtPfk4pMQc7KH44hMDayPnSBwAZL3B/TNpjjgdcmgc3bYVeypGIagadiw30YPtDKamxK0uA1ING8nLBWTxn2XJvpA029bac59VedZ5XftsfKn2g2bT9bgUC5mIp+NtqXCtBdJu2sukq+2nmFVk+J9N/Pf9n5jAAv7pRa2kEUI0I8PVPjb7g87+6ftXJI3vX7dft1/3b5vmp73wxvfffxOT/9/d/+TuEDRVr7boSNlzfpCL/joRpMO1+/c+/cGi2pRis41m8p85/Ac+kc0n/iiFn/KXUriU/x0pinvm9i8yi4/aCmVuZHN0cmVhbQplbmRvYmoKMjEgMCBvYmoKICAgMjU4NgplbmRvYmoKMjAgMCBvYmoKPDwKICAgL0V4dEdTdGF0ZSA8PAogICAgICAvZ3MwIDw8IC9CTSAvTm9ybWFsIC9TTWFzayAvTm9uZSAvQ0EgMS4wIC9jYSAxLjAgPj4KICAgICAgL2EwIDw8IC9DQSAxIC9jYSAxID4+CiAgID4+CiAgIC9TaGFkaW5nIDw8IC9zaDIyIDIyIDAgUiAvc2gyMyAyMyAwIFIgL3NoMjQgMjQgMCBSID4+Cj4+CmVuZG9iagoyNSAwIG9iago8PCAvRnVuY3Rpb25UeXBlIDIKICAgL0RvbWFpbiBbIDAgMSBdCiAgIC9DMCBbIDAuMjQ3MDU5IDAuNTQ1MDk4IDAuMjM5MjE2IF0KICAgL0MxIFsgMC4yNDcwNTkgMC41Mjk0MTIgMC4yNDcwNTkgXQogICAvTiAxCj4+CmVuZG9iagoyNiAwIG9iago8PCAvRnVuY3Rpb25UeXBlIDIKICAgL0RvbWFpbiBbIDAgMSBdCiAgIC9DMCBbIDAuMjQ3MDU5IDAuNTI5NDEyIDAuMjQ3MDU5IF0KICAgL0MxIFsgMC4yMzkyMTYgMC42NjI3NDUgMC4xODAzOTIgXQogICAvTiAxCj4+CmVuZG9iagoyNyAwIG9iago8PCAvRnVuY3Rpb25UeXBlIDIKICAgL0RvbWFpbiBbIDAgMSBdCiAgIC9DMCBbIDAuMjM5MjE2IDAuNjYyNzQ1IDAuMTgwMzkyIF0KICAgL0MxIFsgMC4yMzkyMTYgMC42ODIzNTMgMC4xNjg2MjcgXQogICAvTiAxCj4+CmVuZG9iagoyOCAwIG9iago8PCAvRnVuY3Rpb25UeXBlIDMKICAgL0RvbWFpbiBbIDAgMSBdCiAgIC9GdW5jdGlvbnMgWyAyNSAwIFIgMjYgMCBSIDI3IDAgUiBdCiAgIC9Cb3VuZHMgWyAwLjY0IDAuOTMgXQogICAvRW5jb2RlIFsgMCAxIDAgMSAwIDEgXQo+PgplbmRvYmoKMjIgMCBvYmoKICAgICAgPDwgL1NoYWRpbmdUeXBlIDIKICAgICAgICAgL0NvbG9yU3BhY2UgL0RldmljZVJHQgogICAgICAgICAvQ29vcmRzIFsgMzAuMzMgOC41NiAxNC45IDQ0LjcwMDAwMSBdCiAgICAgICAgIC9Eb21haW4gWyAwIDEgXQogICAgICAgICAvRXh0ZW5kIFsgdHJ1ZSB0cnVlIF0KICAgICAgICAgL0Z1bmN0aW9uIDI4IDAgUgogICAgICA+PgplbmRvYmoKMjkgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAyCiAgIC9Eb21haW4gWyAwIDEgXQogICAvQzAgWyAwLjI0NzA1OSAwLjUyOTQxMiAwLjI0NzA1OSBdCiAgIC9DMSBbIDAuMzIxNTY5IDAuNjI3NDUxIDAuMjY2NjY3IF0KICAgL04gMQo+PgplbmRvYmoKMzAgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAyCiAgIC9Eb21haW4gWyAwIDEgXQogICAvQzAgWyAwLjMyMTU2OSAwLjYyNzQ1MSAwLjI2NjY2NyBdCiAgIC9DMSBbIDAuMzkyMTU3IDAuNzE3NjQ3IDAuMjg2Mjc1IF0KICAgL04gMQo+PgplbmRvYmoKMzEgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAyCiAgIC9Eb21haW4gWyAwIDEgXQogICAvQzAgWyAwLjM5MjE1NyAwLjcxNzY0NyAwLjI4NjI3NSBdCiAgIC9DMSBbIDAuNDE1Njg2IDAuNzQ5MDIgMC4yOTQxMTggXQogICAvTiAxCj4+CmVuZG9iagozMiAwIG9iago8PCAvRnVuY3Rpb25UeXBlIDMKICAgL0RvbWFpbiBbIDAuMTQgMC45MSBdCiAgIC9GdW5jdGlvbnMgWyAyOSAwIFIgMzAgMCBSIDMxIDAgUiBdCiAgIC9Cb3VuZHMgWyAwLjQgMC43MSBdCiAgIC9FbmNvZGUgWyAwIDEgMCAxIDAgMSBdCj4+CmVuZG9iagoyMyAwIG9iagogICAgICA8PCAvU2hhZGluZ1R5cGUgMgogICAgICAgICAvQ29sb3JTcGFjZSAvRGV2aWNlUkdCCiAgICAgICAgIC9Db29yZHMgWyAyNS42ODc5OTkgMjMuMTAzOTk5IDYzLjU3MjAwMSAyLjc3NTk5OSBdCiAgICAgICAgIC9Eb21haW4gWyAwLjE0IDAuOTEgXQogICAgICAgICAvRXh0ZW5kIFsgdHJ1ZSB0cnVlIF0KICAgICAgICAgL0Z1bmN0aW9uIDMyIDAgUgogICAgICA+PgplbmRvYmoKMzMgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAyCiAgIC9Eb21haW4gWyAwIDEgXQogICAvQzAgWyAwLjQxNTY4NiAwLjc0OTAyIDAuMjk0MTE4IF0KICAgL0MxIFsgMC4zOTIxNTcgMC43MTc2NDcgMC4yODYyNzUgXQogICAvTiAxCj4+CmVuZG9iagozNCAwIG9iago8PCAvRnVuY3Rpb25UeXBlIDIKICAgL0RvbWFpbiBbIDAgMSBdCiAgIC9DMCBbIDAuMzkyMTU3IDAuNzE3NjQ3IDAuMjg2Mjc1IF0KICAgL0MxIFsgMC4zMjE1NjkgMC42Mjc0NTEgMC4yNjY2NjcgXQogICAvTiAxCj4+CmVuZG9iagozNSAwIG9iago8PCAvRnVuY3Rpb25UeXBlIDIKICAgL0RvbWFpbiBbIDAgMSBdCiAgIC9DMCBbIDAuMzIxNTY5IDAuNjI3NDUxIDAuMjY2NjY3IF0KICAgL0MxIFsgMC4yNDcwNTkgMC41Mjk0MTIgMC4yNDcwNTkgXQogICAvTiAxCj4+CmVuZG9iagozNiAwIG9iago8PCAvRnVuY3Rpb25UeXBlIDMKICAgL0RvbWFpbiBbIDAuMDkgMC44NiBdCiAgIC9GdW5jdGlvbnMgWyAzMyAwIFIgMzQgMCBSIDM1IDAgUiBdCiAgIC9Cb3VuZHMgWyAwLjI5IDAuNiBdCiAgIC9FbmNvZGUgWyAwIDEgMCAxIDAgMSBdCj4+CmVuZG9iagoyNCAwIG9iagogICAgICA8PCAvU2hhZGluZ1R5cGUgMgogICAgICAgICAvQ29sb3JTcGFjZSAvRGV2aWNlUkdCCiAgICAgICAgIC9Db29yZHMgWyA0LjE4NzUgMjQuNSAzNy44NzUwMDEgMjQuNSBdCiAgICAgICAgIC9Eb21haW4gWyAwLjA5IDAuODYgXQogICAgICAgICAvRXh0ZW5kIFsgdHJ1ZSB0cnVlIF0KICAgICAgICAgL0Z1bmN0aW9uIDM2IDAgUgogICAgICA+PgplbmRvYmoKOCAwIG9iago8PCAvVHlwZSAvT2JqU3RtCiAgIC9MZW5ndGggMzcgMCBSCiAgIC9OIDEKICAgL0ZpcnN0IDQKICAgL0ZpbHRlciAvRmxhdGVEZWNvZGUKPj4Kc3RyZWFtCnicM1Mw4IrmiuUCAAY4AV0KZW5kc3RyZWFtCmVuZG9iagozNyAwIG9iagogICAxNgplbmRvYmoKMzggMCBvYmoKPDwgL1R5cGUgL09ialN0bQogICAvTGVuZ3RoIDQxIDAgUgogICAvTiA0CiAgIC9GaXJzdCAyMwogICAvRmlsdGVyIC9GbGF0ZURlY29kZQo+PgpzdHJlYW0KeJxVkcFqwzAQRO/6irmUxhTilZ04aTA5xIZQSiEkvZUehCIcQbGMJJfm7ys5sUvRaR+zmhmWg1j+jCWxDHzJ2YKQr3JWlkjfr51CehCNcgxA+qrPDh/IQDjic0CV6VsPzrbbYeNgzbmXymImhbYGfM7Xc8Ls4n3nNmk60MaK7qKlmxvbJMntG6uE16athVeY1ZuMsoJzWvGClpQ/EX8kSkaTv1h4CNZx/yCsijlisgG8qbMWO/MT4lJ4WbHCmqbMrQ9qh8Uk31vTdyjLOMT5ZjHQEZ0CtaJ1XbSS1xG/wNtejVMVVLX61lId97sIQ+TIj8qZ3krlkE+ep7Ao/S25C0f4164SXnyZ5l4uHODeLYh+Ab7Sbp4KZW5kc3RyZWFtCmVuZG9iago0MSAwIG9iagogICAyNzgKZW5kb2JqCjQyIDAgb2JqCjw8IC9UeXBlIC9YUmVmCiAgIC9MZW5ndGggMTU0CiAgIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCiAgIC9TaXplIDQzCiAgIC9XIFsxIDIgMl0KICAgL1Jvb3QgNDAgMCBSCiAgIC9JbmZvIDM5IDAgUgo+PgpzdHJlYW0KeJwlzqEKwmAUBeDz/4quGeZ0bnODBTGbrHa74HssWgTz+rBYlofNovgCE19BkD2DxXkOlo97z70XLoC2tZgBwhoUgMFAHJQ5qr5keiV2KVLS25LuTm1N+g/iNBrE4qzsouxJXFXuiYwqMrmT6E2GGfGsyDWNyHhPfH3gH7U8J0FJwoW46XZN4pXY/B83omOSF7PkA/wAmKAYrAplbmRzdHJlYW0KZW5kb2JqCnN0YXJ0eHJlZgo4MTg1CiUlRU9GCg==",
    "php": "JVBERi0xLjcKJbXtrvsKNCAwIG9iago8PCAvTGVuZ3RoIDUgMCBSCiAgIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCj4+CnN0cmVhbQp4nNVZS7Iktw3c1ynqAi7xB36OoZXXjg7bWrxxhKT7RzgzwU+9kS/g0YS6iS6ySCCRAHPiHfDf3yL+l3t+bDS7Pz+u369f79+vGG78rSPduZb7j3/ef7//I+OITxvt/sGf00hPCvmOtTwtlzs3LtPvbPbUkPb4c1upT6m2LNfdQtTUtcQar/U/2wJDHrZXwGvX8vh6ffbLfcfz6ddOP9r67//Pmy+Wn55SrorYGaXYHgshpHJjayOWnhTCX/4R7n//ef/y52/t/vO361dFNGAH+NNufOkpW8YXbHPUeP/x79unXPvwNTwBh/9xWx5PiMdSe3vqGHfq2Lnt4dnwtFz36E8vfS+Q8lNG3eefQ7igpSf2vgz4sDVV36+ztMbzxWva2tfPO//c/7qC/IXTxdGe1uCv9FTA+Ye+6Q3TklJ5YsCpwnh6R2Qz4oePUJ6CRfnq/qTWLizVn8G1Sn7g8Dv28VjDCsXcEY2hjpxS+hNaV4yFltIe7PqO3GmxS0uEgOBbfEJq8y2t1DsCL5nbSVg8Y9Gi8GK7nBr3+CO/44lrm76wg4731H22r/u3K0bsOuO8cES2xAwAdnrahhgrvMoH6tPnOBQcc9gzOt0Z8e6c6yVTBNBo8EeyHuE4aQn4tvM40QJ2wF+CfPPlR41Ev/aDbVt6zIj5ps1GK76fOaZP5iLT8nUnPFNfzyRAwULBYhFRxAbAZg3+jKnBr5lrYMshYA1g0d3QATaGomnraZQnwBux410NZ/x4bndTfIcWHU8U0PsE4SCKQxUK8TynBvwSkZ0NoWt4ItFdKd6pAgoRIcGOctHjNhRpJOLDQMNTuRNVTMqszxRhL0UQ+dwX/YD4C0apJiV/blEwEzZCekK2PWZmxSfmvC1wf03E1aUDZ2yIpvgMUBMDLxcgf0p6AcP6U9PY48//RNO/LoDyjp5rRRNiaTvZFmp3BHN6Cna0LMqukgQP+kfHT5nwyEqAj5LFGEKELPYiz0S+BtnVKw+Z5OLYjPRA3AymGQLYHGp0dWJy4aSGvEwJp8ADCVxdhJKUhAoGNQ8nBzo/Bfefs8i1x/BwT0LasjDVDl49IX84psuxfCkxmG3LIj+QGoKTB/MfuMT5wUej61Ux+q6BS7LIlyxIH48lgMCxNoPz6eBAov/e8btdWqRokRwC6M6znImZ4QIf0yVxjz87/MviGAI0rzOpghiIfGaGDY09qUyAJBALwwmUL0baYHXLRRPw3Ijr+RApWN6Hr0ZhKgAb3WnURJZ4MHACkcBcBJLB3ZejicnTgrsssyRwRuMrmIaoNS2LKOpACi2y65M5g9J10YB4aXggeKiOKeRdcgtTgLuOnbWbtJ9xtBKqgGrR3V8zsYxtKcc78GdYAjWH/vqIK6xX8WQ3sgEwTO6Z8PgJUookCr7SElsvjrJV49zwJSZ6GVJCFjIsMBcVYCRUIpqdRz7uYQImMAuZYpU711mTSt7AkyxxTW6aIWAFq9hNZmogWB2+JuTJJqyKrZMMgI2oKWS4yhKXPKw4W4t8ApCsu8Rd28AsA1sT0NPy9ZfTfx0XIQncH8n0zLVNhENm5wCgFYCcjE0OB4so7RlsMUGEH6xkJRY7QOZArgTWCCKG2AAGr/HYmhIXn91YF8wL+KieA4CFNhpY1hYGwWNYjOmaVbyijoJD0snIHn0SHZpAHHHpPNkIrmwcogzAsxd5ztMAxJ1VW9LQQUWZoyizvDKYu3hXClseZn1iF7FMXy/ez+qrvjY5vCyL2KaHdxiul+nVhmV4hx3RKkg/dPEY1rYlg1D78CfKHKs5ZNKb0gseRe5ejk42gDB4QTA9kpWJXbRQCj2YkRn0EFHauaUspkIGWiWXXjJwDTUsCGdmMWQHgW0wE7gGus7QnJkT2lhAobFi4S0sUMgLzLj2GDO4lqqeW/DavJjM1CK4RU0D+R8Iz2nFsnui58RiX19FPaGckYBOUSeftONCQTDG7UK1KoONyPYhTextlgvJg4O993ShftcS24URxRSNDLm/JtI1LcwBtAvcd1RxRlODFgfDjIoQ1xDTMQ991TJgNkKBnv7aM1jFAXd2RRoaOZ5r6+21Yr94F0JvTUP+moRujpBa112dzOl5uCimV8eYO+P4MhRW03GaysLGDHcj1dAKZ5W8SDqo7fvcYCCv1WgbOmJW4N+encgMMePviS/BLv0CUvBko7dOwGkqse+Al4R2u52mraTvGcJu669Z8+q2tmedNX4c37vBA0U8TENmyUf3jvRm/cqgW3VHlZzXZiNryS84vJp+yaICSw/k4q2u7wfFA0PkqEA8fKmPAKU10M+pluMI7Nh3bV8gnuPPAfpuEZgboNRrmzIKlvo1JFYEFnP2RpMo9os6LrV+m+bOuhJMabkMwi0TN+X9TAabxe4d2Ryy1nHcfdF1vdFZRAQjMdPhUCKDv6sqAn+8FmEG24xoLw/SwpctD3Lca1suvLRP8OryoXgu+CLThWLGcpyxQLE9OKFzvVxItLEoLktBS6VL3vRgYRtORt8eLBNjBHFnB4RFMLn1qKooiGKLbJ5iquqICuvP2FWVGxnyaFDOFTTR1tTK5knxMxfXFZYQZm087XFGpUY5ukEKWNHHlE/UeaI1yHUIPjbcm6he/Nkcj1yxaT7ovXRxC29wKwG+Zcz1Yid8DM8h4IhXrFPE1qa3oaBVK3Eb6Hw1QLoEAyYF4NR1BHcKbxUKeELqjkok/ehXSF7cY24YR78JV10FrxPSV1U+XLAsJcxCVIum0wKPE+E4oRYq6Oc6LwiIHFsNVrvGCLI5G1kYZ28oKuP1I3eGtKjhUlLs4uZjTJi1ZFm+XpVq7exUqr1756ZrefrrZ9d/6xYM3MzCeVQbgzNrPDqO5XnXnqqNEctbsjHqL+Ul2RiQLHBPycYIgfqWbIyVoxzJxoAgtjxbsuESct2WbGx2tkuyodzFz6XHGGL4TbExdtfhm2JTeEUls70UGxUP1uB9x2aNsnMRZ+mwed3rGhtT9qXY0AJiPopNQU/pjzilCV9aYik2pXoTeRQbWpT+S7EpTNd0immpRWRyFBubnegpt8ZMTqciG8gssYmbio0NF/+OYlMRxkYenopNxeuVklOxqSAL6VRHsalsa+0oNsaw16XYGGWJ9lZsbPh9YCk2hq6nDnPFxsjhbJG2YmMgHQZ6KjYGv6B/3IqNkbl7fys2hILujFOxQbSU6auQG8ijh7diU+aV5DR3BdcDZ/Wt2JQWVVaWYlMaWxQ7wAAdqgF+KTZ/RdOrhzBeTtgMbcVmg3YHsCRvkKdFuRWPYKPTj/QWbMxWJXXBhmNW1CXYgD78ktv8yvTRIlKFlmJjYA6R6FRsjPJofCk2lpNrYVOxMfSh7cgxk0Heig0uei4zvxSbg9el2BxM7xRlL5qPBX2o30mnYlNM+ulbsSlpillbsSloJkc6ig2fsK3XFJaK9E2vYcJyiaXXMOfJWEt6WWE9es0K/tFrCBdpSXtSYw0pW6/hWMLL1muK7gPp1UlsqB69hmimR9ZD9CKpcek1jK/kp6XXGHuKfPQaw8aq1aPXGNAvh1Gv6UJEnyVgCjbiCWtbsLExifMINmSBko9gg+sV27al19Tguz56TY1Jaob0muBMU1Ttpl5jiE9OU64x7YqXedtyjfG2Ykeu+QlP1/SoS4pLrjnVbUkYlvI3i4Fo/LAu2BjqhZrYo9jIx9SXp2LDesVHl2KD8Po/UmzFhkEQry7Fhjxm1H2nYsOiKBVvKzZmhL5txUbHY0M85Rgni7dgU0aXVH0Em5/P/3WctAUbq3zGjnZAPMRyBBsStsSWLdhUQpqi/FRsWDV0jVuKTWXi1Ldiw6rAxZZiY0C9xaPY2JjywVZsCEL9089UbAzQkUYxFRtrritvxcbQfrJCLsXGsBsmwlJsTDfHt2LDSsGTLsXGeC0MR6E5lWIpNoU3iPBNsTm8v/SZw/rbsohtN7IzDt8Vm1+v/wLoEtXoCmVuZHN0cmVhbQplbmRvYmoKNSAwIG9iagogICAyOTc3CmVuZG9iagozIDAgb2JqCjw8CiAgIC9FeHRHU3RhdGUgPDwKICAgICAgL2EwIDw8IC9DQSAxIC9jYSAxID4+CiAgID4+CiAgIC9TaGFkaW5nIDw8IC9zaDcgNyAwIFIgPj4KPj4KZW5kb2JqCjkgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAyCiAgIC9Eb21haW4gWyAwIDEgXQogICAvQzAgWyAwLjY4MjM1MyAwLjY5ODAzOSAwLjgzNTI5NCBdCiAgIC9DMSBbIDAuNjgyMzUzIDAuNjk4MDM5IDAuODM1Mjk0IF0KICAgL04gMQo+PgplbmRvYmoKMTAgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAyCiAgIC9Eb21haW4gWyAwIDEgXQogICAvQzAgWyAwLjY4MjM1MyAwLjY5ODAzOSAwLjgzNTI5NCBdCiAgIC9DMSBbIDAuMjgyMzUzIDAuMjk4MDM5IDAuNTM3MjU1IF0KICAgL04gMQo+PgplbmRvYmoKMTEgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAyCiAgIC9Eb21haW4gWyAwIDEgXQogICAvQzAgWyAwLjI4MjM1MyAwLjI5ODAzOSAwLjUzNzI1NSBdCiAgIC9DMSBbIDAuMjgyMzUzIDAuMjk4MDM5IDAuNTM3MjU1IF0KICAgL04gMQo+PgplbmRvYmoKMTIgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAzCiAgIC9Eb21haW4gWyAwIDEgXQogICAvRnVuY3Rpb25zIFsgOSAwIFIgMTAgMCBSIDExIDAgUiBdCiAgIC9Cb3VuZHMgWyAwLjMgMC43NSBdCiAgIC9FbmNvZGUgWyAwIDEgMCAxIDAgMSBdCj4+CmVuZG9iago3IDAgb2JqCiAgICAgIDw8IC9TaGFkaW5nVHlwZSAzCiAgICAgICAgIC9Db2xvclNwYWNlIC9EZXZpY2VSR0IKICAgICAgICAgL0Nvb3JkcyBbIDAgMCAwIDAgMCAxIF0KICAgICAgICAgL0RvbWFpbiBbIDAgMSBdCiAgICAgICAgIC9FeHRlbmQgWyB0cnVlIHRydWUgXQogICAgICAgICAvRnVuY3Rpb24gMTIgMCBSCiAgICAgID4+CmVuZG9iago4IDAgb2JqCjw8IC9UeXBlIC9PYmpTdG0KICAgL0xlbmd0aCAxMyAwIFIKICAgL04gMQogICAvRmlyc3QgNAogICAvRmlsdGVyIC9GbGF0ZURlY29kZQo+PgpzdHJlYW0KeJwzUzDgiuaK5QIABjgBXQplbmRzdHJlYW0KZW5kb2JqCjEzIDAgb2JqCiAgIDE2CmVuZG9iagoxNCAwIG9iago8PCAvVHlwZSAvT2JqU3RtCiAgIC9MZW5ndGggMTcgMCBSCiAgIC9OIDQKICAgL0ZpcnN0IDIzCiAgIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCj4+CnN0cmVhbQp4nFWRwWrDMBBE7/qKvZTGFOxduXLSYHJIAqGUgnFyKz0IRTiGYhlJLs3fV3Jil6LTPnY0MywBMhIgkHEgQYwKyFeClSVkp2uvIatkox0DgOytPTv4AA4INXyOaGeGzgOxzWZUVNacB6UtLJRsrQFKaZUiLC7e926dZSNtrOwvrXKpsU2S3L6xWvrWdHvpNSz2a468IMIlFSgwf0J6REwmk79Y8BCso76SVsccMdkI3vW5lVvzE+JieEuilCPxPHTLU/GyFHP+zgelg+dZerBm6KEs4xDnm91IJ3QM1MrO9dFWXSf8Ct4Oepp2YWuvv1ul68M2whA/8lo7M1ilHeSz5zEIlb+1cOEg/5rupJdfprkXDce49wxLv2tOcPwKZW5kc3RyZWFtCmVuZG9iagoxNyAwIG9iagogICAyODUKZW5kb2JqCjE4IDAgb2JqCjw8IC9UeXBlIC9YUmVmCiAgIC9MZW5ndGggNzcKICAgL0ZpbHRlciAvRmxhdGVEZWNvZGUKICAgL1NpemUgMTkKICAgL1cgWzEgMiAyXQogICAvUm9vdCAxNiAwIFIKICAgL0luZm8gMTUgMCBSCj4+CnN0cmVhbQp4nGNgYPj/n4mBj4EBRDAx8ogwMDAy8AMJ7r8gMQ4gi28jkOAvARI8lUCClxVETAJJyIMkvgMJAV6IAYwggplRcD5QTHAbAwMAxKII0gplbmRzdHJlYW0KZW5kb2JqCnN0YXJ0eHJlZgo0NTM0CiUlRU9GCg==",
]
private var brandImages: [String: NSImage] = [:]

func brandImage(_ key: String) -> NSImage? {
    if let i = brandImages[key] { return i }
    guard let b = BRAND_PDF[key], let d = Data(base64Encoded: b), let i = NSImage(data: d) else { return nil }
    brandImages[key] = i
    return i
}

/// Configuración, Apariencia: el menú lateral (iconos en color, logotipos y qué apartados salen) y los
/// botones del proyecto. Se guarda al momento
/// Configuración, Seguridad entre webs: qué es, en cuatro puntos (el mismo texto que en Linux)
let CROSS_SITE_HELP: [(String, String, String)] = [
    ("exclamationmark.triangle", "El problema",
     "Mientras trabajas, el navegador tiene abierta tu sesión en tus proyectos (el panel de WordPress, el de PrestaShop…). Cualquier otra web que abras a la vez podría mandarles a escondidas un formulario o una petición, y el navegador la enviaría con tu sesión: crear un administrador, cambiar una contraseña, borrar productos…"),
    ("lock.shield", "Lo que hace la barrera",
     "Apache rechaza lo que llega a tus proyectos desde otra web, salvo abrir una página con un enlace normal. Lo que hagas dentro del propio proyecto, o escribiendo su dirección, funciona igual."),
    ("info.circle", "Cuándo apagarla",
     "Al probar una pasarela de pago (Redsys, PayPal, Stripe…): al acabar el pago, el banco te devuelve a la tienda mandando un formulario desde su web, y la barrera lo para (sale «Otra web ha intentado mandar algo a esta»). Apágala mientras pruebas los pagos y vuelve a encenderla al acabar."),
    ("network", "Dónde se aplica",
     "En todas tus versiones de PHP: localhost, los dominios falseados y los vhosts de los proyectos. Al cambiarla se reinicia Apache."),
]

struct AppearanceCard: View {
    @EnvironmentObject var model: AppModel

    /// En tres bloques, cada uno con su título, porque hacen cosas distintas: cómo se ven los iconos del menú
    /// lateral, qué apartados salen en él y los botones del visor de los proyectos
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            block("Iconos del menú lateral", "Cómo se dibujan los iconos de la columna de la izquierda") {
                Tile("Iconos en color", "Cada apartado con su color; apagado, de un color, como el texto") {
                    Toggle("", isOn: Binding(get: { model.look.color }, set: { model.look.color = $0 }))
                        .toggleStyle(SwitchToggleStyle()).labelsHidden()
                }
                Tile("Logotipos de Docker, Node y PHP", "Con su logotipo y su tipografía en lugar del nombre") {
                    Toggle("", isOn: Binding(get: { model.look.marcas }, set: { model.look.marcas = $0 }))
                        .toggleStyle(SwitchToggleStyle()).labelsHidden()
                }
            }
            block("Apartados del menú lateral", "Cuáles se ven en la columna de la izquierda (Proyectos y Configuración salen siempre)") {
                ForEach(NAV.flatMap { $0.1 }.filter { !NAV_FIXED.contains($0.0) }, id: \.0) { item in
                    Tile(item.1) {
                        Toggle("", isOn: Binding(get: { !model.look.ocultos.contains(item.0) }, set: { on in
                            if on { model.look.ocultos.remove(item.0) } else { model.look.ocultos.insert(item.0) }
                        }))
                        .toggleStyle(SwitchToggleStyle()).labelsHidden()
                    }
                }
            }
            block("Visor de los proyectos", "Los botones de cada proyecto: cuáles se ven, en qué orden y cómo") {
                Tile("Botones", buttonsSummary()) {
                    Button("Personalizar…") { model.panel = .buttons }
                }
            }
        }
        // (debajo del título grande de Configuración)
        .preference(key: ToolsDescKey.self, value: "Cómo se ve la ventana. Se guarda al momento y vale también para la versión de Linux.")
    }

    /// Un bloque: su título y lo que hace, y sus filas en una lista
    func block<C: View>(_ title: String, _ sub: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13.5, weight: .semibold))
            Text(sub).font(.caption).foregroundColor(.secondary)
            TileCard(wide: true) { content() }
                .padding(.top, 6)
        }
    }

    func buttonsSummary() -> String {
        let c = model.visorConf
        let names = Dictionary(uniqueKeysWithValues: VISOR_BUTTONS)
        let shown = c.order.filter { !c.hidden.contains($0) }.map { names[$0] ?? $0 }
        let style = (VISOR_STYLES.first(where: { $0.0 == c.style })?.1 ?? "").lowercased()
        return (shown.isEmpty ? "ninguno" : shown.joined(separator: ", ")) + " · " + style + (c.square ? " de \(Int(c.side)) px" : "")
    }
}

/// Un logotipo con su tipografía; con tint, de ese color (PHP, siempre en el suyo: de un color, su óvalo
/// taparía las letras)
struct BrandImage: View {
    let key: String
    let height: CGFloat
    var tint: Color? = nil
    @Environment(\.colorScheme) var scheme

    var body: some View {
        let k = key == "node" ? (scheme == .dark ? "node-oscuro" : "node-claro") : key
        if let img = brandImage(k) {
            if let c = tint, key != "php" {
                Image(nsImage: img).renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                    .frame(height: height).foregroundColor(c)
            } else {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(height: height)
            }
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(NAV.filter { g in g.1.contains { NAV_FIXED.contains($0.0) || !model.look.ocultos.contains($0.0) } }, id: \.0) { group in
                Text(group.0)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 12)
                    .padding(.top, 14)
                    .padding(.bottom, 3)
                ForEach(group.1.filter { NAV_FIXED.contains($0.0) || !model.look.ocultos.contains($0.0) }, id: \.0) { item in
                    NavRow(key: item.0, text: item.1, icon: item.2)
                }
            }
            Spacer()
            Text(footer())
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(10)
        }
        .padding(.horizontal, 10)
        .frame(width: 220)
        .background(Color.primary.opacity(0.035))
    }

    /// Abajo, solo el aviso de la simulación: la versión va arriba, detrás de «Entornos PHP y
    /// Docker», y la firma en Acerca de
    func footer() -> String {
        return SIMULATE ? "SIMULACIÓN: no se cambia nada" : ""
    }
}

struct NavRow: View {
    @EnvironmentObject var model: AppModel
    let key: String
    let text: String
    let icon: String
    @State private var hover = false

    var body: some View {
        let on = model.tab == key
        return Button(action: { model.openTab(key) }) {
            HStack(spacing: 10) {
                let look = model.look
                if look.marcas && (key == "docker" || key == "node") {
                    // (el logotipo con su nombre, en su tipografía: ya dice qué es)
                    BrandImage(key: key, height: key == "docker" ? 21 : 19,
                               tint: look.color ? nil : (on ? ACCENT : Color.primary))
                } else {
                    if look.marcas && look.color && key == "versiones" {
                        BrandImage(key: "php", height: 19)
                    } else {
                        navIcon(on, color: look.color)
                    }
                    Text(text).font(.system(size: 13, weight: on ? .semibold : .regular))
                }
                Spacer(minLength: 0)
            }
            .foregroundColor(on ? ACCENT : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? ACCENT.opacity(0.13) : Color.primary.opacity(hover ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover = $0 }
        .hoverPointer()
    }

    /// (los logotipos de un color, como los símbolos; desde la 1.39.4 también la ballena de Docker,
    /// como en Linux). Algo más grandes desde la 1.39, como en Linux (de 16 a 20)
    @ViewBuilder
    func navIcon(_ on: Bool, color: Bool) -> some View {
        // (en color, cada uno el suyo; GitHub, el del texto, que en el tema oscuro su negro no se vería)
        if icon.hasPrefix("logo:") {
            let name = String(icon.dropFirst(5))
            LogoShape(d: LOGO_PATHS[name] ?? "")
                .fill(color ? (name == "github" ? Color.primary : brand(name)) : (on ? ACCENT : Color.secondary))
                .frame(width: 21, height: 21)
        } else {
            Image(systemName: icon).font(.system(size: 17)).frame(width: 21, height: 21)
                .foregroundColor(color ? (NAV_TINTS[key] ?? ACCENT) : (on ? ACCENT : Color.secondary))
        }
    }
}

/// Fila de la columna de apartados de Configuración: como las de la barra lateral, más pequeña
struct SubNavRow: View {
    @EnvironmentObject var model: AppModel
    let key: String
    let text: String
    let icon: String
    @State private var hover = false

    var body: some View {
        let on = model.toolsSection == key
        return Button(action: { model.toolsSection = key }) {
            HStack(spacing: 10) {
                Group {
                    if icon.hasPrefix("logo:") {
                        LogoShape(d: LOGO_PATHS[String(icon.dropFirst(5))] ?? "").fill(on ? ACCENT : Color.secondary)
                    } else {
                        Image(systemName: icon).font(.system(size: 14)).foregroundColor(on ? ACCENT : Color.secondary)
                    }
                }
                .frame(width: 17, height: 17)
                Text(text).font(.system(size: 12.5, weight: on ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(on ? ACCENT : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? ACCENT.opacity(0.13) : Color.primary.opacity(hover ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover = $0 }
        .hoverPointer()
    }
}

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
                        Text("(antes se guarda una copia de la actual)").font(.caption).foregroundColor(.secondary)
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
                Text("Se escribe sobre \(HTDOCS)/\(model.upFolder). Su .git no se toca y lo sustituido o borrado queda en ~/lvm-copias.")
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
        WidePage(width: Swift.max(980, model.projectsTableWidth), top: model.scrollTop) {
            if let p = model.projects, let d = model.data {
                hero(p, d)
                listHead()
                projectTable(p)
                Text(plural(p.list.count, "proyecto", "proyectos") + " en \(HTDOCS)")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Loading()
            }
        }
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
                Picker("", selection: Binding(get: { current }, set: { model.chooseEnv(x, $0) })) {
                    if envs.isEmpty { Text("Sin entornos").tag("") }
                    ForEach(envs, id: \.0) { e in Text(e.1).tag(e.0) }
                }
                .labelsHidden()
                .frame(width: 230)
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
            Picker("", selection: $model.projKind) {
                Text("Todos").tag("all")
                Text("WordPress").tag("wp")
                Text("PrestaShop").tag("ps")
                Text("Otros").tag("")
            }
            .labelsHidden()
            .frame(width: 120)
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

// MARK: - Versiones de PHP

struct VersionsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        WidePage {
            if let d = model.data {
                HStack(spacing: 10) {
                    PageTitle(title: "Versiones de PHP",
                              sub: "Cada versión con su Apache, MariaDB y sus propias BBDD. Soporte y parches, según php.net",
                              logo: "php")
                    Spacer(minLength: 8)
                    Button(action: { model.panel = .components("") }) {
                        HStack(spacing: 6) {
                            LogoShape(d: LOGO_PATHS["apache"] ?? "").fill(brand("apache")).frame(width: 15, height: 15)
                            Text("Componentes")
                        }
                    }
                    .buttonStyle(OutlineButton())
                    .tip("Componentes de cada versión")
                    Button(action: { model.panel = .install }) { Label("Instalar versión…", systemImage: "plus") }
                        .buttonStyle(OutlineButton(kind: "primary"))
                        .disabled(model.busy)
                }
                TableBox {
                    TableHead(cols: [("Versión", 200), ("PHP", 70), ("Soporte", 170), ("Último parche", 160), ("BBDD", 40), ("", 0)])
                    ForEach(d.installs) { inst in
                        Divider()
                        versionRow(inst, d)
                    }
                    if d.installs.isEmpty {
                        Divider()
                        Text("Ninguna versión instalada: instala la primera con «Instalar versión…».")
                            .foregroundColor(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let e = model.branchesError {
                    Text("No se ha podido consultar php.net: \(e)").font(.caption).foregroundColor(.secondary)
                }
            } else if let e = model.loadError {
                Card("No se han podido leer las versiones instaladas") {
                    Row(e) { Button("Reintentar") { model.reload(branches: true) } }
                }
            } else {
                Loading()
            }
        }
    }

    func versionRow(_ inst: Install, _ d: AppData) -> some View {
        let act = inst.folder == d.active
        let b = model.branch(inst.php)
        let newer = model.newerPatch(inst)
        let pd = model.phpDates[inst.folder]
        let date: String? = (pd?.count ?? 0) >= 2 && pd?[0] == inst.php ? pd?[1] : nil
        return HoverRow { hover in
            HStack(spacing: 8) {
                StatusDot(on: act && d.running)
                VStack(alignment: .leading, spacing: 1) {
                    Text("XAMPP-\(inst.folder)").font(.system(size: 12.5, design: .monospaced))
                    Text(date.map { "publicada el \(fmtDay($0))" } ?? "/Library/Nexum/XAMPP-\(inst.folder)")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .col(200)
            .tip("/Library/Nexum/XAMPP-\(inst.folder)")
            Text(inst.php).font(.system(size: 12.5, design: .monospaced)).col(70)
            supportCell(b).col(170)
            patchCell(inst, b, newer).col(160)
            Text("\((d.dbs[inst.folder] ?? []).count)").font(.system(size: 12.5, design: .monospaced))
                .foregroundColor(.secondary).col(40)
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                if act {
                    // (del mismo tamaño que «Activar»)
                    Text("Activa").font(.system(size: 12.5, weight: .semibold)).foregroundColor(ACCENT)
                        .frame(width: 64)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(ACCENT.opacity(0.13)))
                } else {
                    // (como «Cargar» en Proyectos: solo en la versión con el ratón encima)
                    Button(action: { model.activate(inst.folder) }) { Text("Activar").frame(width: 64) }
                        .buttonStyle(OutlineButton(kind: "primary"))
                        .disabled(model.busy || d.official)
                        .opacity(hover ? 1 : 0)
                        .allowsHitTesting(hover)
                }
                versionMenu(inst, newer)
            }
            .col(0)
        }
    }

    @ViewBuilder
    func supportCell(_ b: Branch?) -> some View {
        if let b = b {
            let when = b.phpState == "security" ? b.securityEnd : (b.phpState == "stable" ? b.activeEnd : "")
            VStack(alignment: .leading, spacing: 1) {
                StatePill(b: b)
                if !when.isEmpty {
                    Text((b.phpState == "security" ? "seguridad hasta " : "hasta ") + fmtMonth(when))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        } else {
            Text(model.branches == nil && model.branchesError == nil ? "consultando php.net…" : "—")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    /// Último parche: «Actualizado» en verde o el parche nuevo que hay; encima, en rojo, si es
    /// vulnerable a PHP2Shell (con la explicación al pasar el ratón)
    @ViewBuilder
    func patchCell(_ inst: Install, _ b: Branch?, _ newer: String?) -> some View {
        let st = model.data?.php2shell[inst.folder] ?? "ok"
        VStack(alignment: .leading, spacing: 1) {
            if php2shellVulnerable(st) {
                Text("Vulnerable (PHP2Shell)").font(.caption.weight(.bold)).foregroundColor(RED)
                    .tip(php2shellText(st, inst.php).isEmpty ? "" : "Vulnerable a PHP2Shell")
            }
            if let b = b, b.latest == inst.php {
                if st == "parcheable" {
                    Text("Parche de seguridad disponible").font(.caption).foregroundColor(ACCENT)
                } else if !php2shellVulnerable(st) {
                    // (vulnerable no está «Actualizado», aunque tenga el último parche de su rama)
                    Text("Actualizado").font(.caption.weight(.semibold)).foregroundColor(GREEN)
                }
                if st == "parche" {
                    Text("+ parche de seguridad (\(PHP2SHELL_DATE))").font(.caption).foregroundColor(.secondary)
                        .tip("Parche oficial contra PHP2Shell")
                }
            } else if let b = b, let n = newer {
                Text("PHP \(n) disponible").font(.caption).foregroundColor(ACCENT)
                if !b.date.isEmpty {
                    Text(fmtDay(b.date)).font(.caption).foregroundColor(.secondary)
                }
            } else if !php2shellVulnerable(st) {
                Text("—").foregroundColor(.secondary)
            }
        }
    }

    /// Menú ⋯ de una versión. Actualizar: las XAMPP-X.Y de antes se ponen al día en su carpeta; las
    /// XAMPP-X.Y.Z, instalando el parche nuevo a su lado (y pasándole después sus BBDD). Las 7.4.33,
    /// 8.0.30 y 8.1.34 sin el parche de seguridad se rehacen con él. Sin datos de php.net, se
    /// comprueba al pulsar
    func versionMenu(_ inst: Install, _ newer: String?) -> some View {
        let updatable = inst.folder.split(separator: ".").count == 2
        let st = model.data?.php2shell[inst.folder] ?? "ok"
        return OutlineMenu(nil, symbol: "ellipsis", bordered: false) {
            Button("Componentes…") { model.panel = .components(inst.folder) }
            if st == "parcheable" && newer == nil {
                Button("Poner el parche de seguridad (PHP2Shell)…") { model.update(inst.folder) }
            } else if updatable && (newer != nil || model.branch(inst.php) == nil) {
                Button(newer.map { "Actualizar a PHP \($0)" } ?? "Buscar parches nuevos") { model.update(inst.folder) }
            } else if let n = newer {
                Button("Actualizar a PHP \(n)…") { model.upgradePinned(inst, n) }
            }
            if pmaOutdated(inst.php, inst.pma) {
                Button("Actualizar phpMyAdmin") { model.updatePma(inst.folder) }
            }
            Button("Desinstalar…") {
                if inst.blocker.isEmpty { model.remove(inst) } else { message("No se puede desinstalar", inst.blocker) }
            }
        }
        .disabled(model.busy)
    }
}

/// Componentes de cada versión en una tabla, con el logotipo de cada uno
struct ComponentsPanel: View {
    @EnvironmentObject var model: AppModel
    let only: String

    var body: some View {
        let list = (model.data?.installs ?? []).filter { only.isEmpty || $0.folder == only }
        let heads: [(String, String)] = [("PHP", "logo:php"), ("Apache", "logo:apache"), ("MariaDB", "logo:mariadb"),
                                         ("FTP", "arrow.up.arrow.down"), ("Perl", "logo:perl"), ("PMA", "logo:phpmyadmin")]
        return TableBox {
            HStack(spacing: 12) {
                Text("VERSIÓN").font(.system(size: 10.5, weight: .semibold)).foregroundColor(.secondary).col(150)
                ForEach(heads, id: \.0) { h in
                    HStack(spacing: 5) {
                        if h.1.hasPrefix("logo:") {
                            let n = String(h.1.dropFirst(5))
                            LogoShape(d: LOGO_PATHS[n] ?? "").fill(brand(n)).frame(width: 14, height: 14)
                        } else {
                            Image(systemName: h.1).font(.system(size: 11)).foregroundColor(.orange)
                        }
                        Text(h.0.uppercased()).font(.system(size: 10.5, weight: .semibold)).foregroundColor(.secondary)
                    }
                    .col(78)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))
            ForEach(list) { inst in
                Divider()
                HStack(spacing: 12) {
                    Text("XAMPP-\(inst.folder)").font(.system(size: 12, design: .monospaced)).col(150)
                    ForEach(Array([inst.php, inst.apache, inst.mariadb, inst.ftp, inst.perl].enumerated()), id: \.offset) { _, v in
                        Text(v).font(.system(size: 11.5, design: .monospaced)).col(78)
                    }
                    Text(inst.pma).font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(pmaOutdated(inst.php, inst.pma) ? RED : Color.primary)
                        .col(78)
                        .tip(pmaOutdated(inst.php, inst.pma) ? "phpMyAdmin antiguo: actualízalo en ⋯" : "")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
    }
}

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
                HStack(spacing: 10) {
                    LogoShape(d: LOGO_PATHS["docker"] ?? "").fill(brand("docker")).frame(width: 30, height: 30)
                    Text("Contenedores Docker").font(.system(size: 22, weight: .bold))
                }
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
                    iconAction("arrow.triangle.2.circlepath", "Actualizar la imagen de PHP " + (p.isWeb ? p.versions.joined(separator: ", ") : p.php) + " (la descarga otra vez, con sus últimos parches)") {
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
            items["imagenes"] = AnyView(VisorButton(conf: c, name: "Importar", icon: .logo("imagenes"),
                                                    tip: "Importar imágenes de producción") {
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

// MARK: - Apache de Docker, túnel de Cloudflare, botones del visor y consumo (1.40)

/// El Apache de Docker (gui-docker, W): su dirección, sus puertos, su estado (marcha, parado o nuevo) y
/// si la dirección ya está en este Mac
struct DockerWeb: Equatable {
    var ip = "127.0.0.2", http = "80", https = "443", state = ""
    var ok = false
    /// Final de sus dominios (docker.local o, con el DNS comodín, docker.test) y si va el DNS
    var tld = "docker.local"
    var dns = false
}

/// Final de los dominios del Apache de Docker
func dockerTLD(_ k: DockerData?) -> String {
    return k?.web?.tld ?? "docker.local"
}

/// Dirección https de un dominio del Apache de Docker (con el puerto si no es el 443)
func dockerWebURL(_ k: DockerData?, _ domain: String) -> String {
    let port = k?.web?.https ?? "443"
    return "https://" + domain + (port == "443" ? "" : ":" + port)
}

/// Dominio de una versión de PHP de un proyecto del Apache de Docker (una tienda va con uno solo)
func dockerWebDomain(_ p: DockerProject, _ v: String, _ tld: String) -> String {
    if p.kind == "ps" { return p.slug + "." + tld }
    return p.slug + "-php" + v.replacingOccurrences(of: ".", with: "") + "." + tld
}

/// Contenedor de PHP de una versión de un proyecto del Apache de Docker
func dockerWebContainer(_ p: DockerProject, _ v: String) -> String {
    return "nexum-\(p.slug)-php" + v.replacingOccurrences(of: ".", with: "")
}

func copyText(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// Destino de las opciones de un menú hecho a mano (popMenu)
final class MenuTarget: NSObject {
    var actions: [() -> Void] = []
    @objc func run(_ sender: NSMenuItem) {
        if sender.tag >= 0 && sender.tag < actions.count { actions[sender.tag]() }
    }
}

/// Menú en el sitio del ratón: el botón que lo abre lleva un logotipo, y los menús de SwiftUI solo
/// enseñan texto e iconos del sistema
func popMenu(_ items: [(String, () -> Void)]) {
    let menu = NSMenu()
    let target = MenuTarget()
    for (i, it) in items.enumerated() {
        let m = NSMenuItem(title: it.0, action: #selector(MenuTarget.run(_:)), keyEquivalent: "")
        m.target = target
        m.tag = i
        menu.addItem(m)
        target.actions.append(it.1)
    }
    menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    withExtendedLifetime(target) {}
}

// MARK: túnel de Cloudflare

let TUNNEL_DIR = LOG_DIR + "/tunel"
let CLOUDFLARE = hexColor(0xF38020)

/// El túnel abierto (tunel-abrir): su dirección, la web de este Mac que enseña, su carpeta, su hora de
/// cierre y lo suyo: su contraseña, sus horas y si bloquea el panel de administración
struct TunnelState: Equatable {
    let url, target, folder: String
    let expires: Int
    var password = ""
    var hours = 2
    var block = true
}

/// El túnel abierto, o nil si no hay ninguno, si su proceso ya no está o si ha pasado su hora
func readTunnel() -> TunnelState? {
    guard let data = FileManager.default.contents(atPath: TUNNEL_DIR + "/estado"),
          let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let pid = o["pid"] as? Int, let url = o["url"] as? String, let target = o["target"] as? String else { return nil }
    let expires = o["expires"] as? Int ?? 0
    guard pid > 1, kill(pid_t(pid), 0) == 0, expires > Int(Date().timeIntervalSince1970) else { return nil }
    return TunnelState(url: url, target: target, folder: o["folder"] as? String ?? "", expires: expires,
                       password: o["password"] as? String ?? "", hours: o["hours"] as? Int ?? 2,
                       block: (o["admin"] as? String ?? "bloquear") != "permitir")
}

/// Hora (HH:mm) de un instante en segundos
func clockTime(_ t: Int) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f.string(from: Date(timeIntervalSince1970: TimeInterval(t)))
}

// MARK: botones del visor

/// Botones del visor de un proyecto (el cargado y los de Docker) que se pueden ocultar y ordenar: clave y
/// nombre. Desmontar, ⋮ y los propios de Docker (Versiones de PHP, Arrancar o Parar) se ven siempre
let VISOR_BUTTONS: [(String, String)] = [("web", "Abrir web"), ("vscode", "VS Code"), ("pma", "phpMyAdmin"),
                                         ("panel", "Panel"), ("docker", "Docker"), ("compartir", "Compartir"),
                                         ("log", "Log"), ("actualizar", "Actualizar"), ("imagenes", "Importar")]
let VISOR_STYLES: [(String, String)] = [("nombre", "Con su nombre"), ("icono", "Solo el icono (cuadrado)"),
                                        ("grande", "Icono y nombre (cuadrado)")]
/// Lado del cuadrado de cada estilo si no se ha elegido otro, y lo que deja el deslizador (con el nombre
/// debajo hace falta algo más de sitio)
let VISOR_SIZES: [String: Int] = ["icono": 44, "grande": 88]
let VISOR_SIZE_MIN = 32
let VISOR_SIZE_MAX = 128
let VISOR_SIZE_NAMED = 72
/// El mismo fichero que en Linux (JSON con order, hidden, style y size)
let VISOR_FILE = LOG_DIR + "/botones-visor"

struct VisorConf: Equatable {
    var order: [String] = VISOR_BUTTONS.map { $0.0 }
    var hidden: Set<String> = []
    var style = "nombre"
    var size = 44
    var square: Bool { return style != "nombre" }
    /// Lado del cuadrado: sin nombre, igual de alto que de ancho; con el nombre, al menos VISOR_SIZE_NAMED
    var side: CGFloat { return CGFloat(style == "grande" ? Swift.max(size, VISOR_SIZE_NAMED) : size) }
}

func loadVisorConf() -> VisorConf {
    var c = VisorConf()
    let keys = VISOR_BUTTONS.map { $0.0 }
    guard let data = FileManager.default.contents(atPath: VISOR_FILE),
          let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return c }
    var seen = Set<String>()
    var order: [String] = []
    for k in (o["order"] as? [String] ?? []) where keys.contains(k) && !seen.contains(k) {
        seen.insert(k)
        order.append(k)
    }
    c.order = order + keys.filter { !seen.contains($0) }
    c.hidden = Set((o["hidden"] as? [String] ?? []).filter { keys.contains($0) })
    if let s = o["style"] as? String, VISOR_STYLES.contains(where: { $0.0 == s }) { c.style = s }
    if let n = o["size"] as? Int, n >= VISOR_SIZE_MIN, n <= VISOR_SIZE_MAX {
        c.size = n
    } else {
        c.size = VISOR_SIZES[c.style] ?? 44
    }
    return c
}

/// Guarda los botones (en la simulación no se escribe nada: valen mientras la ventana siga abierta)
func saveVisorConf(_ c: VisorConf) -> Bool {
    if SIMULATE { return true }
    let o: [String: Any] = ["order": c.order, "hidden": c.hidden.sorted(), "style": c.style, "size": c.size]
    guard let data = try? JSONSerialization.data(withJSONObject: o) else { return false }
    try? FileManager.default.createDirectory(atPath: LOG_DIR, withIntermediateDirectories: true,
                                             attributes: [.posixPermissions: 0o700])
    return FileManager.default.createFile(atPath: VISOR_FILE, contents: data)
}

/// Icono de un botón del visor: un símbolo del sistema con su color, un logotipo o una imagen (VS Code)
enum VisorIcon {
    case symbol(String, Color)
    case logo(String)
    case image(NSImage)
}

/// Icono de cada botón que se puede ordenar (el del diálogo de los botones y su vista previa)
func visorIcon(_ key: String) -> VisorIcon {
    switch key {
    case "web": return .symbol("globe", Color.blue)
    case "vscode":
        if let code = vscodeURL() { return .image(NSWorkspace.shared.icon(forFile: code.path)) }
        return .symbol("chevron.left.forwardslash.chevron.right", Color.primary)
    case "pma": return .logo("phpmyadmin")
    case "panel": return .logo("wordpress")
    case "docker": return .logo("docker")
    case "compartir": return .logo("cloudflare")
    case "actualizar": return .logo("actualizar")
    case "imagenes": return .logo("imagenes")
    default: return .logo("log")
    }
}

struct VisorIconView: View {
    let icon: VisorIcon
    let size: CGFloat
    var body: some View {
        switch icon {
        case .symbol(let s, let c):
            Image(systemName: s).font(.system(size: size * 0.8)).foregroundColor(c).frame(width: size, height: size)
        case .logo(let l):
            if LOGO_STROKED.contains(l) {
                LogoShape(d: LOGO_PATHS[l] ?? "")
                    .stroke(brand(l), style: StrokeStyle(lineWidth: size * 1.5 / 24, lineCap: .round, lineJoin: .round))
                    .frame(width: size, height: size)
            } else {
                LogoShape(d: LOGO_PATHS[l] ?? "").fill(brand(l)).frame(width: size, height: size)
            }
        case .image(let i):
            Image(nsImage: i).resizable().frame(width: size, height: size)
        }
    }
}

/// Lo de dentro de un botón cuadrado: solo el icono, o el icono con el nombre debajo
struct VisorSquareLabel: View {
    let conf: VisorConf
    let name: String
    let icon: VisorIcon
    var body: some View {
        if conf.style == "grande" {
            VStack(spacing: 4) {
                VisorIconView(icon: icon, size: Swift.max(18, conf.side * 2 / 5))
                Text(name).font(.system(size: 11)).lineLimit(1).truncationMode(.tail).frame(maxWidth: conf.side - 8)
            }
        } else {
            VisorIconView(icon: icon, size: Swift.max(16, conf.side / 2))
        }
    }
}

/// Botón cuadrado del visor: el lado que se haya elegido, igual de alto que de ancho
struct SquareButton: ButtonStyle {
    let side: CGFloat
    var kind = ""
    func makeBody(configuration: Configuration) -> some View {
        SquareBody(configuration: configuration, side: side, kind: kind)
    }
}

struct SquareBody: View {
    let configuration: ButtonStyleConfiguration
    let side: CGFloat
    let kind: String
    @Environment(\.isEnabled) var enabled
    @State private var hover = false

    var body: some View {
        let on = hover && enabled
        let share = kind == "compartiendo"
        let tint: Color = kind == "stop" ? RED : (kind == "play" ? GREEN : (share ? CLOUDFLARE : ACCENT))
        let shape = RoundedRectangle(cornerRadius: 12)
        let fill: Color = share ? CLOUDFLARE.opacity(0.10) : Color.primary.opacity(configuration.isPressed ? 0.10 : 0.03)
        let border: Color = on ? tint : (share ? CLOUDFLARE : Color.primary.opacity(0.16))
        return configuration.label
            .foregroundColor(on ? ACCENT : Color.primary)
            .frame(width: side, height: side)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: 1))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(shape)
            .animation(.easeOut(duration: 0.12), value: on)
            .onHover { hover = $0 }
            .hoverPointer()
    }
}

/// Botón del visor de un proyecto con el estilo elegido: con su nombre (como siempre), solo el icono o el
/// icono con el nombre debajo, en un cuadrado del tamaño elegido
struct VisorButton: View {
    let conf: VisorConf
    let name: String
    let icon: VisorIcon
    let tip: String
    var kind = ""
    let action: () -> Void

    var body: some View {
        if conf.square {
            Button(action: action) { VisorSquareLabel(conf: conf, name: name, icon: icon) }
                .buttonStyle(SquareButton(side: conf.side, kind: kind))
                .tip(conf.style == "icono" ? (tip.isEmpty ? name : tip.hasPrefix(name) ? tip : name + ": " + tip) : tip)
        } else {
            Button(action: action) {
                HStack(spacing: 6) {
                    VisorIconView(icon: icon, size: 16)
                    Text(name)
                }
            }
            .buttonStyle(OutlineButton(kind: kind))
            .tip(tip)
        }
    }
}

/// «Botones del proyecto»: cuáles se ven, en qué orden y cómo (con una vista previa)
struct ButtonsPanel: View {
    @EnvironmentObject var model: AppModel
    @State private var conf = VisorConf()
    @State private var loaded = false
    @State private var sizeTouched = false

    var body: some View {
        let names = Dictionary(uniqueKeysWithValues: VISOR_BUTTONS)
        // (en horizontal: la lista a la izquierda y el estilo, el tamaño y la vista previa a la derecha, para
        // que quepa en la altura de un portátil)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Los que se ven y en qué orden (el del proyecto cargado y el de Docker). Desmontar, ⋮ y los propios de Docker (Versiones de PHP, Arrancar o Parar) se ven siempre.")
                .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 0) {
                    ForEach(Array(conf.order.enumerated()), id: \.element) { i, key in
                        if i > 0 { Divider() }
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(get: { !conf.hidden.contains(key) }, set: { on in
                                if on { conf.hidden.remove(key) } else { conf.hidden.insert(key) }
                            }))
                            .toggleStyle(CheckboxToggleStyle()).labelsHidden()
                            .tip("Verlo en el visor")
                            VisorIconView(icon: visorIcon(key), size: 18)
                            Text(names[key] ?? key)
                            Spacer()
                            Button(action: { move(i, -1) }) { Image(systemName: "chevron.up") }
                                .buttonStyle(OutlineButton(compact: true)).disabled(i == 0).tip("Antes")
                            Button(action: { move(i, 1) }) { Image(systemName: "chevron.down") }
                                .buttonStyle(OutlineButton(compact: true)).disabled(i == conf.order.count - 1).tip("Después")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                .frame(width: 320)
              VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("Estilo").frame(width: 70, alignment: .leading)
                    Picker("", selection: Binding(get: { conf.style }, set: { s in
                        conf.style = s
                        if !sizeTouched { conf.size = VISOR_SIZES[s] ?? conf.size }
                    })) {
                        ForEach(VISOR_STYLES, id: \.0) { st in Text(st.1).tag(st.0) }
                    }
                    .labelsHidden()
                }
                HStack(spacing: 12) {
                    Text("Tamaño").frame(width: 70, alignment: .leading)
                    Slider(value: Binding(get: { Double(conf.size) }, set: { v in
                        conf.size = Int(v)
                        sizeTouched = true
                    }), in: Double(VISOR_SIZE_MIN)...Double(VISOR_SIZE_MAX), step: 4)
                    .disabled(!conf.square)
                    Text(conf.square ? "\(Int(conf.side))×\(Int(conf.side)) px" : "—")
                        .font(.system(size: 11.5, design: .monospaced)).foregroundColor(.secondary)
                        .frame(width: 90, alignment: .trailing)
                }
                Text("Así quedan").font(.caption).foregroundColor(.secondary)
                preview(names)
              }
            }
            HStack {
                    Button("Como al principio") {
                        conf = VisorConf()
                        sizeTouched = false
                    }
                    .buttonStyle(OutlineButton())
                    .tip("Volver a los botones de siempre")
                    Spacer()
                    Button("Cancelar") { model.panel = nil }.buttonStyle(OutlineButton())
                    Button("Guardar") { model.saveVisor(conf) }.buttonStyle(OutlineButton(kind: "primary"))
            }
        }
        .onAppear {
            if !loaded {
                conf = model.visorConf
                loaded = true
            }
        }
    }

    /// Los botones que se ven, como quedarán (con Desmontar y ⋮), en varias filas si no caben
    func preview(_ names: [String: String]) -> some View {
        let keys = conf.order.filter { !conf.hidden.contains($0) }
        let width: CGFloat = conf.square ? conf.side : 120
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: width, maximum: width + 40), spacing: 8, alignment: .leading)],
                         alignment: .leading, spacing: 8) {
            ForEach(keys, id: \.self) { k in
                VisorButton(conf: conf, name: names[k] ?? k, icon: visorIcon(k), tip: "", action: {})
            }
            VisorButton(conf: conf, name: "Desmontar", icon: .symbol("eject.fill", Color.secondary), tip: "", action: {})
            VisorButton(conf: conf, name: "Más", icon: .symbol("ellipsis", Color.primary), tip: "", action: {})
        }
        .padding(4)
    }

    func move(_ i: Int, _ d: Int) {
        let j = i + d
        guard j >= 0 && j < conf.order.count else { return }
        conf.order.swapAt(i, j)
    }
}

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
                Picker("", selection: Binding(get: { hours }, set: { h in
                    guard h != hours else { return }
                    hours = h
                    runQuick(["docker-reposo", "horas", h]) { _, out in
                        model.toast(out.split(separator: "\n").last.map(String.init) ?? "Hecho")
                        read()
                    }
                })) {
                    ForEach(choices + (choices.contains(hours) ? [] : [hours]), id: \.self) { h in
                        Text(h == "0" ? "Nunca" : h == "1" ? "A la hora sin visitas" : "A las \(h) h sin visitas").tag(h)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
                .disabled(model.busy)
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
                    .disabled(model.busy)
                if g?.source != "gh" && ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                    Button("Usar la sesión de gh") { runQuick(["github-conectar", "--gh"]) { rc, out in model.githubDone(rc, out) } }
                        .disabled(model.busy)
                        .tip("Usar la sesión de gh auth login")
                }
                if !(g?.source ?? "").isEmpty {
                    Button("Desconectar") { runQuick(["github-desconectar"]) { rc, out in model.githubDone(rc, out) } }
                        .disabled(model.busy)
                }
            }
            Tile("Organización o cuenta", "La de los repositorios que se ven (por ejemplo, hexer-dev)") {
                TextField("", text: $account).textFieldStyle(RoundedBorderTextFieldStyle()).frame(width: 170)
                Button("Guardar") { model.githubSet("cuenta", account.trimmingCharacters(in: .whitespaces)) }
                    .disabled(account.trimmingCharacters(in: .whitespaces) == (g?.account ?? "") || model.busy)
            }
            Tile("Prefijos de los repositorios", "Separados por espacios (dob-wordpress- dob-prestashop- …); vacío: todos") {
                TextField("", text: $prefixes).textFieldStyle(RoundedBorderTextFieldStyle()).frame(width: 240)
                Button("Guardar") { model.githubSet("prefijos", prefixes.trimmingCharacters(in: .whitespaces)) }
                    .disabled(prefixes.trimmingCharacters(in: .whitespaces) == (g?.prefixes ?? "") || model.busy)
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
                      symbol: "chevron.left.forwardslash.chevron.right")
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
            .disabled(model.busy)
            if p.running {
                iconButton(.symbol("arrow.clockwise", Color.primary), p.mode == "compilado" ? "Volver a compilar y arrancar" : "Reiniciar su servidor") {
                    model.startNode(p, mode: p.mode)
                }
                .disabled(model.busy)
                VisorButton(conf: c, name: "Abrir web", icon: .symbol("globe", Color.blue), tip: "Abrir \(p.url)") { openURL(p.url) }
            } else {
                VisorButton(conf: c, name: "Arrancar", icon: .symbol("play.fill", Color.green), tip: "En desarrollo: los cambios se ven al momento") {
                    model.startNode(p, mode: "desarrollo")
                }
                .disabled(model.busy)
                VisorButton(conf: c, name: "Compilar", icon: .symbol("hammer.fill", Color.primary), tip: "Compilar y arrancar, como en producción") {
                    model.startNode(p, mode: "compilado")
                }
                .disabled(model.busy)
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
                .disabled(model.busy)
            }
            if p.running {
                VisorButton(conf: c, name: "Parar", icon: .symbol("stop.fill", Color.red), tip: "Parar su servidor (y su túnel, si se está compartiendo)") {
                    model.stopNode(p)
                }
                .disabled(model.busy)
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
                    .disabled(model.busy)
                    .tip("Actualizar con git pull")
            } else if item.state == "ocupado" {
                Button("Clonar") {}
                    .buttonStyle(OutlineButton())
                    .disabled(true)
                    .tip("Ya hay una carpeta con ese nombre")
            } else {
                Button("Clonar") { model.fetchRepo(item) }
                    .buttonStyle(OutlineButton(kind: "primary"))
                    .disabled(model.busy)
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
    if cmd.contains("nexum-tunel") || cmd.contains("/.lvm-instalador/tunel/cloudflared") { return "tunel" }
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

/// ¿Toca buscar una versión nueva al abrir? Se lleva en ~/.lvm-instalador/actualizaciones-arranques:
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

// MARK: acciones

extension AppModel {
    /// Dirección de la web de un proyecto en Docker: la del Apache de Docker o, en los de antes, la del
    /// Apache del Mac
    func dockerSite(_ p: DockerProject) -> String {
        return p.isWeb ? dockerWebURL(docker, p.domain) : "https://\(p.domain)"
    }

    var dockerPmaURL: String { return dockerWebURL(docker, "pma." + dockerTLD(docker)) + "/" }

    func saveVisor(_ c: VisorConf) {
        guard saveVisorConf(c) else {
            message("No se han podido guardar los botones", VISOR_FILE, error: true)
            return
        }
        visorConf = c
        panel = nil
        toast("Botones del proyecto guardados")
    }

    // Consumo (cada 3 s) y el túnel abierto

    func usageTick() {
        guard !usageBusy else { return }
        usageBusy = true
        DispatchQueue.global(qos: .utility).async {
            let u = sampleUsage()
            DispatchQueue.main.async {
                self.usageBusy = false
                if !u.isEmpty && u != self.usage { self.usage = u }
                self.refreshTunnel()
            }
        }
    }

    func refreshTunnel() {
        let t = readTunnel()
        if t != tunnel { tunnel = t }
    }

    /// Lo de cloudflared (tunel: I|instalado|versión|la del programa)
    func reloadTunnelInfo() {
        runQuick(["tunel"]) { _, out in
            let f = parseLines(out).first(where: { $0[0] == "I" && $0.count >= 4 })
            if f != self.tunnelInfo { self.tunnelInfo = f }
        }
    }

    /// «Compartir» del visor: abre un túnel de Cloudflare a esa dirección; si ya lo está, «Compartiendo»
    /// (con el borde naranja) enseña la dirección y la contraseña
    func shareButton(_ url: String, folder: String, name: String, conf: VisorConf) -> some View {
        let mine = tunnel?.target == url
        return VisorButton(conf: conf, name: mine ? "Compartiendo" : "Compartir", icon: .logo("cloudflare"),
                           tip: mine ? "Ver dirección y contraseña"
                                : "Compartir con un túnel de Cloudflare",
                           kind: mine ? "compartiendo" : "") {
            if mine { self.shareDialog() } else { self.share(url, folder: folder, name: name) }
        }
    }

    /// Abre un túnel a esa web, con lo suyo, que se elige ahora: cuánto dura y si se bloquea el panel de
    /// administración. Su contraseña, siempre una nueva al azar (se ve al abrirlo, para copiarla)
    func share(_ url: String, folder: String, name: String, live: Bool = true) {
        var text = "Cualquiera que tenga la dirección y la contraseña verá \(url) tal y como está en este Mac\(live ? " (lo que cambies, al momento)" : "") mientras el túnel esté abierto."
        if let t = tunnel { text += " Se cierra el que hay abierto (\(t.target))." }
        let installed = FileManager.default.isExecutableFile(atPath: TUNNEL_DIR + "/cloudflared")
        if !installed { text += " La primera vez se descarga cloudflared, el programa de Cloudflare (unos 20 MB)." }
        text += " Lleva una contraseña nueva al azar: se ve al abrirlo, para copiarla y mandarla."
        let alert = NSAlert()
        alert.messageText = "Compartir \(name)"
        alert.addButton(withTitle: "Compartir")
        alert.addButton(withTitle: "Cancelar")
        func line(_ title: String, _ views: [NSView]) -> NSView {
            let t = NSTextField(labelWithString: title)
            t.textColor = .secondaryLabelColor
            t.translatesAutoresizingMaskIntoConstraints = false
            t.widthAnchor.constraint(equalToConstant: 150).isActive = true
            let row = NSStackView(views: [t] + views)
            row.orientation = .horizontal
            row.spacing = 10
            return row
        }
        let hours = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 110, height: 26), pullsDown: false)
        hours.addItems(withTitles: (1...12).map { plural($0, "hora", "horas") })
        hours.selectItem(at: 1)
        let block = NSButton(checkboxWithTitle: "Bloquear el panel de administración (tus BBDD llevan el administrador de pruebas)",
                             target: nil, action: nil)
        block.state = .on
        alert.accessoryView = dialogStack([
            dialogLabel(text, color: .secondaryLabelColor),
            line("Se cierra solo en", [hours]), block,
        ], spacing: 12)
        guard alert.runStyled() == .alertFirstButtonReturn else { return }
        let args = ["tunel-abrir", url, folder, "--horas", String(hours.indexOfSelectedItem + 1),
                    "--admin", block.state == .on ? "bloquear" : "permitir"]
        let open: () -> Void = {
            _ = self.runTask("Abriendo el túnel de \(name)", args, doneText: "Túnel abierto", autoClose: true) { ok, _, _ in
                self.refreshTunnel()
                if ok && self.tunnel != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.shareDialog() }
                }
            }
        }
        if installed {
            open()
        } else {
            runTask("Instalando cloudflared", ["tunel-instalar"], progress: true, doneText: "cloudflared instalado", autoClose: true) { ok, _, _ in
                self.reloadTunnelInfo()
                if ok { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { open() } }
            }
        }
    }

    /// La dirección del túnel abierto y su contraseña, para copiarlas y mandarlas
    func shareDialog() {
        refreshTunnel()
        guard let t = tunnel else {
            toast("El túnel ya está cerrado")
            return
        }
        let hour = clockTime(t.expires)
        let alert = NSAlert()
        alert.messageText = "Compartiendo \(t.target)"
        alert.addButton(withTitle: "Listo")
        alert.addButton(withTitle: "Copiar para enviar")
        let close = alert.addButton(withTitle: "Cerrar el túnel")
        close.hasDestructiveAction = true
        let copyURL = DialogValidator()
        copyURL.update = { copyText(t.url); self.toast("Dirección copiada") }
        let copyPass = DialogValidator()
        copyPass.update = { copyText(t.password); self.toast("Contraseña copiada") }
        func line(_ title: String, _ value: String, _ v: DialogValidator) -> NSView {
            let l = NSTextField(labelWithString: title)
            l.textColor = .secondaryLabelColor
            l.translatesAutoresizingMaskIntoConstraints = false
            l.widthAnchor.constraint(equalToConstant: 90).isActive = true
            let val = NSTextField(labelWithString: value)
            val.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
            val.isSelectable = true
            let b = NSButton(title: "Copiar", target: v, action: #selector(DialogValidator.changed(_:)))
            let row = NSStackView(views: [l, val, b])
            row.orientation = .horizontal
            row.spacing = 10
            return row
        }
        alert.accessoryView = dialogStack([
            line("Dirección", t.url, copyURL), line("Contraseña", t.password, copyPass),
            dialogLabel("Se cierra solo a las \(hour). "
                        + (t.block ? "El panel de administración va bloqueado." : "⚠ El panel de administración no va bloqueado.")
                        + " Quién entra y lo que se bloquea queda en el registro del túnel (Configuración, Túnel de Cloudflare).",
                        color: .secondaryLabelColor),
        ], spacing: 12)
        let r = alert.runStyled()
        withExtendedLifetime([copyURL, copyPass]) {}
        if r == .alertSecondButtonReturn {
            copyText("Te paso la web en pruebas:\n\(t.url)\nContraseña: \(t.password)\n(Funciona hasta las \(hour).)")
            toast("Texto para enviar copiado")
        } else if r == .alertThirdButtonReturn {
            tunnelClose()
        }
    }

    func tunnelClose() {
        runQuick(["tunel-cerrar"]) { rc, _ in
            self.refreshTunnel()
            self.toast(rc == 0 ? "Túnel cerrado: la dirección ya no lleva a ningún sitio" : "No se ha podido cerrar el túnel")
        }
    }

    // Docker: lo común, parar todo y las versiones de PHP

    /// Proyectos del Apache de Docker en marcha que usan un contenedor común: el Apache de Docker o su
    /// phpMyAdmin (todos) o una MariaDB común (los que van con esa versión). Vacío si no es común
    func sharedUsers(_ name: String) -> [String] {
        guard let k = docker else { return [] }
        var maria: String? = nil
        var bridge: String? = nil
        if name.range(of: "^nexum-mariadb-[0-9]+-[0-9]+$", options: .regularExpression) != nil {
            maria = String(name.dropFirst(14)).replacingOccurrences(of: "-", with: ".")
        } else if name.range(of: "^nexum-lampp-bd-[0-9]+-[0-9]+(-[0-9]+)?$", options: .regularExpression) != nil {
            bridge = String(name.dropFirst(15)).replacingOccurrences(of: "-", with: ".")
        } else if name != "nexum-web" && name != "nexum-pma" {
            return []
        }
        let up = k.containers.filter { $0.state == "running" }.map { $0.name }
        return k.projects.filter { p in
            // (una MariaDB común no la usan los que van en vivo con XAMPP-X; el puente, solo esos)
            p.isWeb && (maria.map { p.maria == $0 && p.lampp.isEmpty } ?? true) && (bridge.map { p.lampp == $0 } ?? true) && up.contains { n in
                n.range(of: "^nexum-" + NSRegularExpression.escapedPattern(for: p.slug) + "-php[0-9]{2}$",
                        options: .regularExpression) != nil
            }
        }.map { $0.folder }
    }

    /// Antes de parar algo común: si lo usa algún proyecto en marcha, se dice cuáles y se pregunta
    func stopSharedOK(_ names: [String], _ what: String) -> Bool {
        let users = Array(Set(names.flatMap { sharedUsers($0) })).sorted()
        if users.isEmpty { return true }
        let many = users.count > 1
        let text: String
        if names.contains(where: { $0.hasPrefix("nexum-mariadb-") || $0.hasPrefix("nexum-lampp-bd-") }) {
            text = "Es común: ahora \(many ? "la usan" : "la usa") \(users.joined(separator: ", ")). \(many ? "Se quedarán" : "Se quedará") sin BBDD (errores de conexión) hasta que la vuelvas a arrancar; al arrancar un proyecto que va con ella, se arranca sola."
        } else {
            text = "Es común: ahora \(many ? "lo usan" : "lo usa") \(users.joined(separator: ", ")). \(many ? "Dejarán" : "Dejará") de verse hasta que lo vuelvas a arrancar; al arrancar un proyecto del Apache de Docker, se arranca solo."
        }
        return confirm("¿Parar \(what)?", text,
                       names.contains(where: { $0.hasPrefix("nexum-mariadb-") }) ? "Pararla igualmente" : "Pararlo igualmente",
                       destructive: true)
    }

    func dockerStopAll() {
        runTask("Parando todos los contenedores de Nexum", ["docker-parar-todo"], doneText: "Contenedores de Nexum parados",
                autoClose: true) { _, _, _ in self.reloadDocker(stats: true) }
    }

    /// docker-web arrancar|parar|permitir|confiar (el Apache de Docker)
    func dockerWebCommand(_ action: String) {
        let titles = ["arrancar": "Arrancando el Apache de Docker", "parar": "Parando el Apache de Docker",
                      "permitir": "Dando de alta la dirección del Apache de Docker",
                      "confiar": "Certificado de Docker en el navegador"]
        runTask(titles[action] ?? action, ["docker-web", action], doneText: "Listo", autoClose: true) { _, _, _ in
            self.reloadDocker(stats: true)
        }
    }

    /// docker-web dns activar|quitar: el DNS comodín de *.docker.test
    func dockerDNS(_ on: Bool) {
        if on {
            guard confirm("¿Activar el DNS de *.docker.test?",
                          "Un DNS mínimo, solo en este Mac (127.0.0.1), que contesta a cualquier <algo>.docker.test. Los proyectos del Apache de Docker pasan a .docker.test (su configuración, el dominio de las tiendas en su BBDD y el certificado) y sus líneas salen de /etc/hosts. Desde entonces, añadir proyectos o versiones de Docker no pide la contraseña por los dominios. web.local, los proyectos de siempre y los dominios falseados de las tiendas no cambian. Si no contesta, se quita y todo sigue como estaba. Pide la contraseña de administrador.",
                          "Activar") else { return }
        } else {
            guard confirm("¿Quitar el DNS de *.docker.test?",
                          "Los dominios de Docker siguen siendo .docker.test y vuelven a /etc/hosts. Pide la contraseña de administrador.",
                          "Quitar", destructive: true) else { return }
        }
        runTask(on ? "Activando el DNS de *.docker.test" : "Quitando el DNS de *.docker.test",
                ["docker-web", "dns", on ? "activar" : "quitar"],
                doneText: "DNS de *.docker.test " + (on ? "puesto" : "quitado")) { _, _, _ in self.reloadDocker() }
    }

    /// Dirección y puertos del Apache de Docker (docker-web puertos)
    func dockerWebPorts(_ ip: String, _ http: String, _ https: String) {
        let a = ip.trimmingCharacters(in: .whitespaces), h = http.trimmingCharacters(in: .whitespaces),
            s = https.trimmingCharacters(in: .whitespaces)
        if a.range(of: "^127\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$", options: .regularExpression) == nil
            || Int(h) == nil || Int(s) == nil {
            message("Dirección o puertos no válidos",
                    "La dirección tiene que ser de este Mac (127.x.x.x, como 127.0.0.2) y los puertos, números.", error: true)
            return
        }
        runTask("Dirección y puertos del Apache de Docker", ["docker-web", "puertos", a, h, s],
                doneText: "Apache de Docker en \(a) (\(h) y \(s))", autoClose: true) { _, _, _ in self.reloadDocker() }
    }

    /// Versiones de PHP de un proyecto del Apache de Docker: añadir, quitar y, en una tienda, elegir
    func dockerVersions(_ p: DockerProject) {
        guard let k = docker, !busy else { return }
        let ps = p.kind == "ps"
        let group = RadioGroup()
        var options: [NSView] = []
        var acts: [([String], String, String)] = []
        func add(_ text: String, _ args: [String], _ title: String, _ done: String) {
            let b = NSButton(radioButtonWithTitle: text, target: group, action: #selector(RadioGroup.pick(_:)))
            b.state = group.buttons.isEmpty ? .on : .off
            group.buttons.append(b)
            options.append(b)
            acts.append((args, title, done))
        }
        if ps {
            for v in p.versions where v != p.php {
                add("Elegir PHP \(v) (la tienda pasa a ir con ella)", ["docker-php-elegir", p.slug, v],
                    "\(p.folder) con PHP \(v)", "\(p.folder) ya va con PHP \(v)")
            }
        }
        if p.versions.count > 1 {
            for v in p.versions {
                add("Quitar PHP \(v) (su contenedor; la carpeta y la BBDD se quedan)", ["docker-php-quitar", p.slug, v],
                    "Quitando PHP \(v) de \(p.folder)", "PHP \(v) quitado de \(p.folder)")
            }
        }
        let rest = k.php.filter { !p.versions.contains($0) }
        let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 160, height: 26), pullsDown: false)
        pop.addItems(withTitles: rest.map { "PHP \($0)" })
        if !rest.isEmpty {
            let b = NSButton(radioButtonWithTitle: "Añadir otra:", target: group, action: #selector(RadioGroup.pick(_:)))
            b.state = group.buttons.isEmpty ? .on : .off
            group.buttons.append(b)
            let row = NSStackView(views: [b, pop])
            row.orientation = .horizontal
            row.spacing = 8
            options.append(row)
        }
        if options.isEmpty {
            message("Versiones de PHP de \(p.folder)", "Tiene PHP \(p.php) y no hay otra versión que añadir.")
            return
        }
        let now = ps ? "La tienda guarda su dominio en la BBDD: va con \(dockerSite(p)) y la versión que elijas (ahora PHP \(p.php))."
            : "Todas a la vez, cada una con su dominio (\(p.slug)-php83.\(dockerTLD(k))), con la misma carpeta y la misma BBDD."
        let alert = NSAlert()
        alert.messageText = "Versiones de PHP de \(p.folder)"
        alert.addButton(withTitle: "Hacerlo")
        alert.addButton(withTitle: "Cancelar")
        alert.accessoryView = dialogStack([
            dialogLabel(now + " Tiene: PHP " + p.versions.joined(separator: ", ") + ". La primera vez con cada versión se prepara su imagen (unos minutos).",
                        color: .secondaryLabelColor),
            dialogOptions(options),
        ], spacing: 14)
        guard alert.runStyled() == .alertFirstButtonReturn else { return }
        let i = group.buttons.firstIndex(where: { $0.state == .on }) ?? -1
        if i >= 0 && i < acts.count {
            let a = acts[i]
            runTask(a.1, a.0, doneText: a.2, autoClose: true) { _, _, _ in self.reloadDocker() }
        } else if i == acts.count && pop.indexOfSelectedItem >= 0 && pop.indexOfSelectedItem < rest.count {
            let v = rest[pop.indexOfSelectedItem]
            runTask("Añadiendo PHP \(v) a \(p.folder)", ["docker-php-anadir", p.slug, v], doneText: "\(p.folder) con PHP \(v)") { _, _, _ in
                self.reloadDocker()
            }
        }
    }

    /// Un proyecto de antes (con XAMPP-X delante) pasa al Apache de Docker (docker-pasar)
    func dockerPass(_ p: DockerProject) {
        guard confirm("¿Pasar \(p.folder) al Apache de Docker?",
                      "Ya no necesitará XAMPP-X y podrás añadirle más versiones de PHP. Antes se guarda una copia de su BBDD (\(p.db)) en ~/lvm-copias y se carga en la MariaDB común; después se quitan sus contenedores de ahora, su vhost de XAMPP-X, su clave y su línea de /etc/hosts. Pide la contraseña de administrador.",
                      "Pasarlo") else { return }
        runTask("Pasando \(p.folder) al Apache de Docker", ["docker-pasar", p.slug], progress: true,
                doneText: "\(p.folder) ya va con el Apache de Docker") { _, _, _ in self.reloadDocker() }
    }
}

/// Formulario «Proyecto en Docker»: la carpeta, su versión de PHP y de MariaDB y la BBDD de XAMPP-X que
/// se copia (si se quiere). Va con el Apache de Docker (desde la 1.40): sin dominio que elegir
struct DockerNewPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let k = model.docker ?? DockerData()
        let taken = Set(k.projects.map { $0.folder })
        let folders = projectFolders().filter { !taken.contains($0) }
        let x = model.projects?.list.first(where: { $0.name == model.dkForm.folder })
        let pairs = x.map { model.projectPairs($0) } ?? []
        // (ancho del nombre más largo, para verlo entero al elegirlo)
        let wide = fitWidth(folders + pairs.map { "\($0.1) (XAMPP-\($0.0.folder))" } + [model.dkForm.domain],
                            min: 320, max: 520)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Va con el Apache de Docker (sin XAMPP-X) y su BBDD, en una MariaDB común. Su configuración (wp-config.php o la de PrestaShop) cambia solo dentro del contenedor: la carpeta sigue sirviendo con XAMPP-X. Más versiones de PHP: «Versiones de PHP…» de su visor.")
                .font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
            formRow("Carpeta") {
                Picker("", selection: Binding(get: { model.dkForm.folder }, set: { v in
                    model.dkForm.folder = v
                    model.dkForm.source = ""
                    if !model.dkForm.domainSet { model.dkForm.domain = dockerSlug(v) + ".docker.local" }
                })) {
                    ForEach(folders, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: wide)
            }
            formRow("PHP") {
                Picker("", selection: $model.dkForm.php) {
                    ForEach(k.php, id: \.self) { Text("PHP \($0)").tag($0) }
                }
                .labelsHidden()
                .frame(width: 180)
                // (las imágenes oficiales de 8.1 y anteriores ya no reciben parches: siguen con PHP2Shell)
                if verParts(model.dkForm.php).lexicographicallyPrecedes([8, 2]) && !model.dkForm.php.isEmpty {
                    Text("Vulnerable (PHP2Shell)").font(.caption.weight(.bold)).foregroundColor(RED)
                        .tip("Imagen sin parches: solo con proyectos de confianza")
                }
            }
            formRow("MariaDB") {
                Picker("", selection: $model.dkForm.maria) {
                    ForEach(k.maria, id: \.self) { Text("MariaDB \($0)").tag($0) }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            formRow("BBDD") {
                Picker("", selection: $model.dkForm.source) {
                    Text("— Ninguna: vacía —").tag("")
                    ForEach(Array(pairs.enumerated()), id: \.offset) { _, pr in
                        Text("\(pr.1) (XAMPP-\(pr.0.folder))").tag("\(pr.0.folder)|\(pr.1)")
                    }
                }
                .labelsHidden()
                .frame(width: wide)
            }
            if !model.dkForm.source.isEmpty && x?.kind == "wp" {
                formRow("Cómo") {
                    Picker("", selection: $model.dkForm.live) {
                        Text("En vivo: la misma que web.local (sin copias)").tag(true)
                        Text("Una copia en Docker").tag(false)
                    }
                    .labelsHidden()
                    .frame(width: wide)
                }
            }
            if folders.isEmpty {
                Text("Todas las carpetas de htdocs están ya en Docker.").font(.callout).foregroundColor(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancelar") { model.panel = nil }.buttonStyle(OutlineButton())
                Button("Crear en Docker") { model.dockerCreate() }
                    .buttonStyle(OutlineButton(kind: "primary"))
                    .disabled(folders.isEmpty || model.dkForm.folder.isEmpty || model.busy)
            }
        }
        .onAppear { model.fillDockerForm(folders) }
    }

    func formRow<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 150, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Montar nuevo proyecto (asistente de tres pasos dentro de Cargar proyecto)

let GIT_URL_RX = try! NSRegularExpression(pattern: "^(https://[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]{1,5})?/|git@[A-Za-z0-9][A-Za-z0-9.-]*:|ssh://git@[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]{1,5})?/)[A-Za-z0-9_~][A-Za-z0-9._~/-]*$")
let NEW_FOLDER_RX = try! NSRegularExpression(pattern: "^[A-Za-z0-9_][A-Za-z0-9._-]{0,99}$")

/// Carpeta que se propone para un repositorio: su nombre sin .git
func folderFromGitURL(_ url: String) -> String {
    var name = url.trimmingCharacters(in: .whitespaces)
    while name.hasSuffix("/") { name = String(name.dropLast()) }
    name = name.components(separatedBy: "/").last ?? ""
    name = name.components(separatedBy: ":").last ?? ""
    if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
    name = name.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
    while name.hasPrefix(".") || name.hasPrefix("-") { name = String(name.dropFirst()) }
    return String(name.prefix(100))
}

struct NewProjectWizard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let check = model.npCheck()
        return VStack(alignment: .leading, spacing: 12) {
            Text(["", "Paso 1 de 4: el repositorio", "Paso 2 de 4: versión de PHP", "Paso 3 de 4: BBDD nueva",
                  "Paso 4 de 4: dominio de producción"][model.npStep])
                .font(.headline).frame(maxWidth: .infinity)
            Group {
                if model.npStep == 1 {
                    stepRepo()
                } else if model.npStep == 2 {
                    stepVersion()
                } else if model.npStep == 3 {
                    stepDb()
                } else {
                    stepDomain()
                }
            }
            if !check.1.isEmpty {
                Text(check.1).font(.callout.weight(.semibold)).foregroundColor(RED)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancelar") { model.newProject(false) }.buttonStyle(OutlineButton(big: true))
                Spacer()
                if model.npStep > 1 {
                    Button("Atrás") { model.npGo(-1) }.buttonStyle(OutlineButton(big: true))
                }
                Button(model.npStep == 4 ? "Montar proyecto" : "Siguiente") { model.npGo(1) }
                    .buttonStyle(OutlineButton(kind: "primary", big: true))
                    .disabled(!check.0 || model.busy)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }

    func stepRepo() -> some View {
        let q = repoQuery(model.npRepoQuery)
        let hits = q.count < 2 || model.npRepos.contains(where: { $0.full.lowercased() == q }) ? []
            : Array(model.npRepos.filter { $0.full.lowercased().contains(q) }.prefix(6))
        return VStack(alignment: .leading, spacing: 8) {
            Text("¿De qué repositorio de GitHub? (escribe parte de su nombre)")
            TextField("dob-wordpress-…", text: Binding(get: { model.npRepoQuery }, set: { model.npRepoTyped($0) }))
                .textFieldStyle(RoundedBorderTextFieldStyle())
            if !hits.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(hits) { r in
                        Button(action: { model.npPickRepo(r) }) {
                            HStack {
                                Text(r.full).lineLimit(1)
                                Spacer()
                                if !r.web.isEmpty { Text(r.web).font(.caption).foregroundColor(.secondary).lineLimit(1) }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            }
            if !model.npRepoNote.isEmpty {
                Text(model.npRepoNote).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("o la dirección de otro repositorio (GitHub u otro servidor):")
            TextField("https://github.com/usuario/repositorio.git", text: Binding(
                get: { model.npUrl },
                set: { v in
                    model.npUrl = v
                    if model.npFolderAuto { model.npFolder = folderFromGitURL(v) }
                }))
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("Carpeta en htdocs:")
            TextField("nombre-del-proyecto", text: Binding(
                get: { model.npFolder },
                set: { v in
                    model.npFolder = v
                    model.npFolderAuto = v.isEmpty
                }))
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("Se clona con tu usuario (sin sudo). Los de la lista, por SSH con tu clave; una dirección https de un privado de GitHub, GitLab o Bitbucket se prueba sola por SSH.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func stepVersion() -> some View {
        let d = model.data ?? AppData()
        let insts = d.installs.sorted { a, b in a.php.compare(b.php, options: .numeric) == .orderedDescending }
        return VStack(alignment: .leading, spacing: 8) {
            Text("¿En qué versión de PHP quieres crear el proyecto?")
            if insts.isEmpty {
                Text("No hay ninguna versión instalada: instala una en Versiones de PHP.").foregroundColor(RED)
            } else {
                Picker("", selection: $model.npVersion) {
                    ForEach(insts) { i in
                        Text("PHP \(i.php)  ·  XAMPP-\(i.folder)" + (i.folder == d.active ? "  (activa)" : "")).tag(i.folder)
                    }
                }
                .pickerStyle(RadioGroupPickerStyle())
                .labelsHidden()
            }
        }
    }

    func stepDomain() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("¿Falsear su dominio de producción en este Mac?", isOn: $model.npFake)
                .toggleStyle(SwitchToggleStyle())
            Text("Dominio de producción:")
            TextField("midominio.com", text: $model.npDomain)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .disabled(!model.npFake)
            Text("Falseado, el navegador abre el proyecto en local con su dominio de verdad (con su certificado), como en Dominios y hosts: lo que necesitan las tiendas PrestaShop y los WordPress con el dominio en su BBDD. Si no, se abre en web.local.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func stepDb() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nombre de la BBDD nueva:")
            TextField("wp_proyecto", text: $model.npDb)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("Volcado que se sube a la BBDD (.sql, .sql.gz o .zip):")
            HStack {
                Button("Elegir…") { model.npPickDump() }
                if let f = model.npFile {
                    Text((f as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Button(action: { model.npFile = nil }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .tip("Quitar el volcado: la BBDD se crea vacía")
                } else {
                    Text("Ninguno").foregroundColor(.secondary)
                }
            }
            Text("Si no eliges ninguno, la BBDD se crea vacía. El volcado se carga con la carga protegida (con el usuario de la BBDD y sin DEFINER).")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Instalar nuevas versiones (dentro de Versiones)

struct InstallSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if let err = model.branchesError {
                Card("Instalar nuevas versiones de PHP") {
                    Row(err) { Button("Reintentar") { model.reload(branches: true) } }
                }
            } else if let list = model.branches {
                let nuevas = list.filter { $0.state == "nueva" }.count
                FoldCard("instalar", "Instalar nuevas versiones de PHP",
                     "Pulsa el título para plegar o desplegar la lista. Cada versión se compila en tu Mac (unos 20-40 min) con su propio Apache, MariaDB, ProFTPD, Perl y phpMyAdmin, y sus propias BBDD, vacías al instalar. Según php.net: Estable recibe correcciones de errores y de seguridad (la mejor opción para proyectos nuevos), Solo seguridad recibe únicamente parches de seguridad hasta la fecha indicada y Sin soporte ya no recibe parches.",
                     summary: nuevas > 0 ? plural(nuevas, "versión nueva", "versiones nuevas") : "") {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, b in
                        VStack(spacing: 0) {
                            if i > 0 { Divider() }
                            branchRow(b)
                        }
                    }
                }
                patchCard(list)
                VStack(spacing: 6) {
                    Button(model.selected.isEmpty ? "Instalar" : "Instalar \(plural(model.selected.count, "versión", "versiones"))") {
                        model.install()
                    }
                    .buttonStyle(OutlineButton(kind: "primary", big: true))
                    .disabled(model.selected.isEmpty || model.busy)
                    Text("La versión activa no cambia. Las nuevas se activan en la tabla de Versiones de PHP.")
                        .font(.callout).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                Loading(text: "Consultando las versiones de PHP en php.net…")
            }
        }
    }

    /// Otro parche concreto (como en Linux): una versión anterior de cualquier rama, en su propia carpeta
    /// (XAMPP-X.Y.Z). Se elige la rama y se marcan sus parches; se instalan con los de arriba
    func patchCard(_ list: [Branch]) -> some View {
        let marked = model.selected.filter { $0.components(separatedBy: ".").count == 3 }
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        let names = ["stable": "estable", "security": "solo seguridad", "eol": "sin soporte"]
        return FoldCard("parche", "Otro parche concreto",
                        "Una versión anterior de cualquier rama, en su propia carpeta (XAMPP-X.Y.Z), con el Apache, MariaDB, ProFTPD y Perl de su rama. Las versiones de php.net son todas definitivas, pero los parches anteriores al último no llevan sus correcciones de seguridad: úsalos solo si un proyecto necesita esa versión.",
                        summary: marked.isEmpty ? "" : plural(marked.count, "parche marcado", "parches marcados")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("Rama:")
                    Picker("", selection: Binding(get: { model.patchBranch }, set: { model.loadPatches($0) })) {
                        Text("Elige una rama").tag("")
                        ForEach(list) { b in
                            Text("PHP \(b.branch)" + (names[b.phpState].map { "  (\($0))" } ?? "")).tag(b.branch)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                    .disabled(model.busy)
                    Spacer(minLength: 8)
                }
                if !marked.isEmpty {
                    // (los marcados de cualquier rama, para quitarlos aunque se mire otra)
                    HStack(spacing: 6) {
                        Text("Marcados:").font(.caption).foregroundColor(.secondary)
                        ForEach(marked, id: \.self) { v in
                            Button(action: { model.selected.remove(v) }) {
                                HStack(spacing: 3) {
                                    Text("PHP \(v)").font(.caption)
                                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .tip("Quitar de la lista")
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if let err = model.patchesError {
                Divider()
                Text(err).foregroundColor(RED).padding(.horizontal, 14).padding(.vertical, 10)
            } else if let ps = model.patches {
                ForEach(ps) { p in
                    Divider()
                    patchRow(p)
                }
            } else if !model.patchBranch.isEmpty {
                Divider()
                Loading(text: "Consultando los parches de PHP \(model.patchBranch)…").padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
    }

    func patchRow(_ p: PatchItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("PHP \(p.version)")
                    if !p.date.isEmpty {
                        Text(fmtDay(p.date)).font(.caption).foregroundColor(.secondary)
                    }
                    ReleaseTag(security: p.security)
                }
                Text(p.latest ? "El último de su rama: márcalo en la lista de arriba"
                     : p.state == "instalada" ? "Ya instalada"
                     : p.state == "existe" ? "Ya existe XAMPP-\(p.version)"
                     : "→ /Library/Nexum/XAMPP-\(p.version)")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            if p.state == "nueva" && !p.latest {
                Toggle("", isOn: Binding(get: { model.selected.contains(p.version) },
                                         set: { on in
                                             if on { model.selected.insert(p.version) } else { model.selected.remove(p.version) }
                                         }))
                    .labelsHidden()
                    .disabled(model.busy)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .opacity(p.state == "nueva" && !p.latest ? 1 : 0.55)
    }

    /// Fila de una rama: «PHP 8.5.12», a su lado la fecha en que se publicó y si es un parche de
    /// seguridad; debajo su pila. Como Row (mismas medidas), pero con la fecha junto a la versión
    func branchRow(_ b: Branch) -> some View {
        HStack(spacing: 10) {
            if let ic = rowIcon("PHP \(b.branch)") {
                ColorIcon(symbol: ic.0, color: ic.1, size: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("PHP \(b.latest)")
                    if !b.date.isEmpty {
                        Text(fmtDay(b.date)).font(.caption).foregroundColor(.secondary)
                        ReleaseTag(security: b.security)
                    }
                }
                Text("MariaDB \(b.mariadb)  ·  Perl \(b.perl)"
                     + (b.phpState == "security" && !b.securityEnd.isEmpty
                        ? "  ·  seguridad hasta \(fmtMonth(b.securityEnd))" : ""))
                    .font(.caption).foregroundColor(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                StatePill(b: b)
                stateView(b)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    func stateView(_ b: Branch) -> some View {
        switch b.state {
        case "nueva":
            Toggle("", isOn: Binding(get: { model.selected.contains(b.branch) },
                                     set: { on in
                                         if on { model.selected.insert(b.branch) } else { model.selected.remove(b.branch) }
                                     }))
                .labelsHidden()
                .disabled(model.busy)
        case "instalada":
            Text("Instalada").foregroundColor(.secondary)
        default:
            Text("Hay un parche nuevo").foregroundColor(.secondary)
                .tip("Actualízala en Versiones de PHP (⋯)")
        }
    }
}

// MARK: - Pestaña Bases de datos

struct DatabasesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        WidePage {
            if let d = model.data {
                head(d)
                cards(d)
                // Subir o actualizar una BBDD: antes de la tabla, en un visor hundido
                importCard(d)
                HStack(spacing: 10) {
                    SearchField(text: $model.dbQuery, placeholder: "Buscar una BBDD o su proyecto").frame(width: 300)
                    Spacer(minLength: 8)
                    Text("Solo la versión activa").font(.caption).foregroundColor(.secondary)
                    Toggle("", isOn: $model.dbOnlyActive).toggleStyle(SwitchToggleStyle()).labelsHidden().controlSize(.small)
                }
                dbTable(d)
            } else {
                Loading()
            }
        }
        .sheet(item: $model.projectReq) { req in
            ProjectSheet(req: req).environmentObject(model).buttonStyle(PointerButtonStyle())
        }
        .onAppear {
            // (desde la 1.39.5 ninguna versión se ve desplegada al entrar, tampoco la activa)
            if model.backups == nil { model.refreshBackups() }
        }
    }

    func head(_ d: AppData) -> some View {
        let act = d.installs.first(where: { $0.folder == d.active })
        return HStack(spacing: 10) {
            PageTitle(title: "Bases de datos", sub: "Cada versión con su MariaDB y sus BBDD (sin las del sistema)")
            Spacer(minLength: 8)
            Button(action: { openURL("http://127.0.0.1/phpmyadmin/") }) {
                HStack(spacing: 6) {
                    LogoShape(d: LOGO_PATHS["phpmyadmin"] ?? "").fill(brand("phpmyadmin")).frame(width: 15, height: 15)
                    Text("phpMyAdmin")
                }
            }
            .buttonStyle(OutlineButton())
            .disabled(act == nil || !d.running)
            .tip("phpMyAdmin de la versión activa")
            Button(action: { model.createDb() }) { Label("Nueva BBDD…", systemImage: "plus") }
                .buttonStyle(OutlineButton(kind: "primary"))
                .disabled(act == nil || model.busy)
                .tip("Crear una BBDD vacía")
        }
    }

    /// Cuántas hay, en la activa, la última que ha cambiado y lo que ocupan (y lo libre del disco). Las
    /// copias de seguridad, en Configuración
    func cards(_ d: AppData) -> some View {
        let act = d.installs.first(where: { $0.folder == d.active })
        let all = d.installs.flatMap { i in (d.dbs[i.folder] ?? []).map { (i.folder, $0) } }
        let latest = all.max { (d.dbDates[$0.0 + "|" + $0.1]?.when ?? 0) < (d.dbDates[$1.0 + "|" + $1.1]?.when ?? 0) }
        let latestWhen = latest.flatMap { d.dbDates[$0.0 + "|" + $0.1]?.when } ?? 0
        let now = Int(Date().timeIntervalSince1970)
        let dbTotal = all.compactMap { model.dbSizes[$0.0 + "|" + $0.1]?.first }
        let disk = diskSpace("/Applications")
        return HStack(spacing: 12) {
            StatCard(title: "BBDD", value: "\(all.count)",
                     sub: "en " + plural(Set(all.map { $0.0 }).count, "versión", "versiones"))
            StatCard(title: "En la versión activa", value: act == nil ? "—" : "\((d.dbs[d.active] ?? []).count)",
                     sub: act.map { "XAMPP-\($0.folder) · MariaDB \($0.mariadb)" } ?? "ninguna activa")
            StatCard(title: "La última que ha cambiado", value: latestWhen > 0 ? (latest?.1 ?? "—") : "—",
                     sub: latestWhen > 0 ? "XAMPP-\(latest?.0 ?? "") · \(fmtAge(max(0, now - latestWhen)))" : "")
            // Lo que ocupan las BBDD de todas las versiones y lo que queda libre en el disco de /Applications
            StatCard(title: "Ocupan las BBDD", value: dbTotal.isEmpty ? "—" : fmtSize(dbTotal.reduce(0, +)),
                     sub: disk.map { "Disco: \(fmtSize($0.free)) libres de \(fmtSize($0.total))" } ?? "",
                     progress: disk.map { 1 - Double($0.free) / Double($0.total) })
                .tip(dbTotal.count < all.count
                      ? plural(all.count - dbTotal.count, "BBDD", "BBDD") + " sin medir"
                      : "Tamaño de las BBDD de todas las versiones")
        }
    }

    /// Una fila por versión (se pliega al pulsarla) y, debajo, sus BBDD con su proyecto, la fecha
    /// exacta del último cambio y sus acciones
    func dbTable(_ d: AppData) -> some View {
        let q = model.dbQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let insts = d.installs.sorted { verParts($1.php).lexicographicallyPrecedes(verParts($0.php)) }
            .filter { !model.dbOnlyActive || $0.folder == d.active }
        var groups: [(Install, [(String, String)])] = []
        for inst in insts {
            let rows = (d.dbs[inst.folder] ?? []).map { ($0, model.dbProject($0, inst.folder)) }
                .filter { q.isEmpty || $0.0.lowercased().contains(q) || $0.1.lowercased().contains(q) }
            if !q.isEmpty && rows.isEmpty { continue }
            groups.append((inst, rows))
        }
        return TableBox {
            TableHead(cols: [("Nombre", 270), ("Proyecto", 180), ("Tamaño", 90), ("Cambiada", 160), ("Acciones", 0)])
            ForEach(Array(groups.enumerated()), id: \.element.0.folder) { _, g in
                Divider()
                versionRow(g.0, g.1.count, d)
                if !q.isEmpty || model.expanded.contains("@db" + g.0.folder) {
                    ForEach(Array(g.1.enumerated()), id: \.element.0) { _, r in
                        Divider()
                        dbRow(r.0, r.1, g.0, d)
                    }
                }
            }
            if groups.isEmpty {
                Divider()
                Text(q.isEmpty ? "No hay versiones con BBDD" : "Ninguna BBDD con «\(q)»")
                    .foregroundColor(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    func versionRow(_ inst: Install, _ n: Int, _ d: AppData) -> some View {
        let key = "@db" + inst.folder
        let open = model.expanded.contains(key) || !model.dbQuery.trimmingCharacters(in: .whitespaces).isEmpty
        let active = inst.folder == d.active
        // Lo que ocupan todas sus BBDD (las que se han medido)
        let total = (d.dbs[inst.folder] ?? []).reduce(Int64(0)) { $0 + (model.dbSizes[inst.folder + "|" + $1]?.first ?? 0) }
        // (una versión abierta cada vez: abrir otra cierra la que estaba; pulsar la abierta la cierra)
        return HoverRow(action: {
            if model.expanded.contains(key) {
                model.expanded.remove(key)
            } else {
                model.expanded = model.expanded.filter { !$0.hasPrefix("@db") }
                model.expanded.insert(key)
            }
        }) { _ in
            HStack(spacing: 8) {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary).frame(width: 10)
                LogoIcon("mariadb", size: 18)
                Text("XAMPP-\(inst.folder)").font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                if active { SmallTag(text: "Activa", blue: true) }
            }
            .col(270)
            Text("PHP \(inst.php) · MariaDB \(inst.mariadb)").font(.caption).foregroundColor(.secondary)
                .lineLimit(1).col(180)
            Text(total > 0 ? fmtSize(total) : "—").font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(.secondary).col(90)
            Text(plural(n, "BBDD", "BBDD")).font(.caption).foregroundColor(.secondary).col(160)
            HStack(spacing: 6) {
                if active {
                    logoAction("phpmyadmin", "Abrir phpMyAdmin") { openURL("http://127.0.0.1/phpmyadmin/") }
                        .disabled(!d.running)
                    iconAction("plus", "Crear una BBDD vacía aquí") { model.createDb() }
                        .disabled(model.busy)
                }
            }
            .col(0)
        }
    }

    func dbRow(_ db: String, _ proj: String, _ inst: Install, _ d: AppData) -> some View {
        let folder = inst.folder
        let active = folder == d.active
        let loaded = model.loadedEntry()
        let isUsed = active && loaded != nil && db == model.loadedProjectDb()
        let date = d.dbDates[folder + "|" + db]
        return HoverRow { _ in
            HStack(spacing: 8) {
                // Punto verde: la usa el proyecto cargado (invisible en las demás: así quedan alineadas)
                Circle().fill(GREEN).frame(width: 7, height: 7).opacity(isUsed ? 1 : 0)
                    .tip(isUsed ? "La usa el proyecto cargado (\(loaded?.name ?? ""))" : "")
                if isPsDb(db) {
                    LogoShape(d: LOGO_PATHS["prestashop"] ?? "").fill(brand("prestashop")).frame(width: 13, height: 13)
                } else if db.lowercased().hasPrefix("wp_") {
                    LogoShape(d: LOGO_PATHS["wordpress"] ?? "").fill(brand("wordpress")).frame(width: 13, height: 13)
                }
                Text(db).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle).tip(db)
            }
            .padding(.leading, 26)
            .col(270)
            Text(proj.isEmpty ? "—" : proj).font(.caption).foregroundColor(proj.isEmpty ? Color.secondary : Color.primary)
                .lineLimit(1).truncationMode(.middle).col(180)
            sizeCell(db, folder).col(90)
            changed(date).col(160)
            HStack(spacing: 6) {
                if isPsDb(db) {
                    iconAction("sparkles", "Vaciar la caché (var/cache) de la tienda de \(db)") { model.clearCache(db) }
                        .disabled(model.busy)
                }
                if !model.copyTargets(db, folder).isEmpty {
                    iconAction("doc.on.doc", "Copiar \(db) a otra versión de PHP (para probar el proyecto con ella)") {
                        model.copyDb(db, folder)
                    }
                    .disabled(model.busy)
                }
                iconAction("square.and.arrow.down", "Descargar una copia de \(db) (.zip)") { model.downloadDb(db, folder) }
                    .disabled(model.busy)
                iconAction("folder", "Cargar su proyecto (en XAMPP-\(folder))") { model.openProject(db, inst) }
                    .disabled(model.busy)
                if active {
                    iconAction("trash", "Borrar la BBDD \(db)") { model.dropDb(db) }
                        .disabled(model.busy)
                }
            }
            .col(0)
        }
    }

    /// Lo que ocupa (datos e índices), medido la última vez que su versión estuvo activa y en marcha
    @ViewBuilder
    func sizeCell(_ db: String, _ folder: String) -> some View {
        if let z = model.dbSizes[folder + "|" + db], z.count >= 2 {
            Text(fmtSize(z[0])).font(.system(size: 11.5, design: .monospaced))
                .tip("Datos e índices, medido el " + fmtMeasured(Int(z[1])))
        } else {
            Text("—").foregroundColor(.secondary).tip("Se mide con su versión en marcha")
        }
    }

    func fmtMeasured(_ when: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy 'a las' HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(when)))
    }

    /// La fecha del cambio: la de su carga con el gestor o la del último cambio de sus tablas
    @ViewBuilder
    func changed(_ date: DbDate?) -> some View {
        if let dt = date, dt.when > 0 {
            Text(fmtStamp(dt.when) + (dt.imported ? " · importada" : ""))
                .font(.system(size: 11.5, design: .monospaced))
                .tip((dbDateText(dt) ?? "") + (dt.imported ? "" : "\n\n" + DB_DATE_HELP))
        } else {
            Text("—").foregroundColor(.secondary)
        }
    }

    func fmtStamp(_ when: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(when)))
    }

    /// Subir o actualizar una BBDD, compacto (como en Linux): el fichero, la BBDD de destino, el proyecto y
    /// Cargar en columnas, dentro de un visor hundido, antes de la tabla
    func importCard(_ d: AppData) -> some View {
        let act = d.installs.first(where: { $0.folder == d.active })
        let desc = "Carga una copia .sql, .sql.gz o .zip (como las que se descargan del servidor) en el MariaDB de la versión activa. "
            + "Antes se borran todas las tablas de la BBDD de destino (con una copia en ~/lvm-copias), para que no quede nada de lo anterior."
        let dbs = d.dbs[d.active] ?? []
        let hint = model.importHint()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up").foregroundColor(.secondary)
                Text("Subir o actualizar una BBDD").font(.system(size: 13, weight: .semibold))
                Image(systemName: "info.circle").foregroundColor(.secondary).tip(desc)
                if let a = act {
                    Text("en XAMPP-\(a.folder) · MariaDB \(a.mariadb)").font(.caption).foregroundColor(.secondary)
                }
            }
            if act == nil {
                Text("Activa una versión en Versiones de PHP para cargar BBDD.").font(.caption).foregroundColor(.secondary)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    importColumn("Fichero SQL") {
                        HStack(spacing: 6) {
                            Button("Elegir…") { model.pickSql() }
                            Text(fileSubtitle()).font(.caption).foregroundColor(model.impFile == nil ? Color.secondary : Color.primary)
                                .lineLimit(1).truncationMode(.middle).tip(model.impFile ?? "")
                        }
                        // (lo que falta para poder cargar: debajo del fichero, que tiene sitio)
                        if let h = hint {
                            Text(h).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    importColumn("BBDD de destino") {
                        HStack(spacing: 4) {
                            Picker("", selection: Binding(get: { model.impDb ?? "" },
                                                          set: { model.impDb = $0.isEmpty ? nil : $0 })) {
                                if model.impDb == nil { Text("Elige una BBDD").tag("") }
                                ForEach(dbs, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .frame(minWidth: 150, maxWidth: 260)
                            IconButton(symbol: "plus", help: "Crear una BBDD nueva") { model.createDb() }
                                .disabled(model.busy)
                            IconButton(symbol: "trash", help: "Borrar la BBDD elegida") {
                                if let db = model.impDb { model.dropDb(db) }
                            }
                            .disabled(model.impDb == nil || model.busy)
                        }
                    }
                    importColumn("Proyecto (opcional)") {
                        Picker("", selection: Binding(get: { model.impProject ?? "" },
                                                      set: { model.impProject = $0.isEmpty ? nil : $0 })) {
                            Text("Ninguno").tag("")
                            ForEach(model.impProjects, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(minWidth: 150, maxWidth: 260)
                        Text(model.importProjectHint()).font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .onAppear { if model.impProjects.isEmpty { model.refreshImpProjects() } }
                    Button("Cargar") { model.importDb() }
                        .buttonStyle(OutlineButton(kind: "primary"))
                        .disabled(hint != nil || model.busy)
                        .padding(.top, 20)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SoftSunken(radius: 12))
    }

    /// Una columna del formulario de carga: su título en pequeño y lo de debajo
    func importColumn<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).foregroundColor(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func fileSubtitle() -> String {
        guard let f = model.impFile else { return "Ningún fichero elegido" }
        let name = (f as NSString).lastPathComponent
        if let attrs = try? FileManager.default.attributesOfItem(atPath: f), let size = attrs[.size] as? NSNumber {
            return "\(name)  ·  \(fmtSize(size.int64Value))"
        }
        return "\(name)  ·  ya no existe"
    }
}

// MARK: - Cargar proyecto

struct Project: Equatable {
    let name, db, php: String
    /// ps (tienda PrestaShop), wp (WordPress) o vacío
    var kind: String = ""
}

/// Proyectos de htdocs (gui-proyectos), para el bloque «Cargar proyecto» de Versiones
struct ProjectsData: Equatable {
    var link = "", current = ""
    /// No hay vhost para cargar proyectos: cargar-proyecto crea web.local
    var create = false
    var list: [Project] = []
    /// Base -> carpeta recordada (en todas las versiones, como se guardaba hasta la 1.36)
    var saved: [String: String] = [:]
    /// "base@versión" -> carpeta vinculada en esa versión ("" = desvinculada en ella)
    var vlinks: [String: String] = [:]
}

struct ProjectRequest: Identifiable {
    let db: String
    let inst: Install
    let link, current: String
    /// No hay vhost para cargar proyectos: cargar-proyecto crea web.local
    let create: Bool
    let projects: [Project]
    let saved: [String: String]
    var id: String { return db + "@" + inst.folder }
}

struct ProjectSheet: View {
    @EnvironmentObject var model: AppModel
    let req: ProjectRequest
    @State private var folder: String? = nil
    @State private var filter = ""

    var matches: [String] { return req.projects.filter { $0.db == req.db }.map { $0.name } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Proyecto de \(req.db)").font(.title3.weight(.semibold)).frame(maxWidth: .infinity)
            Text((matches.count > 1 ? "\(matches.count) carpetas usan «\(req.db)». Elige cuál cargar."
                  : "Ninguna carpeta usa «\(req.db)» en su configuración. Elige la del proyecto.")
                 + " Se recuerda para esta BBDD.")
                .foregroundColor(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Buscar una carpeta de htdocs", text: $filter).textFieldStyle(PlainTextFieldStyle())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(pickerList(), id: \.name) { p in
                        folderRow(p)
                    }
                }
            }
            .frame(height: 260)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))

            HStack {
                Spacer()
                Button("Cancelar") { model.projectReq = nil }
                    .buttonStyle(OutlineButton(big: true))
                    .keyboardShortcut(.cancelAction)
                Button("Cargar proyecto") { accept() }
                    .buttonStyle(OutlineButton(kind: "primary", big: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(folder == nil)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 580)
    }

    /// Primero las que usan esta base, luego el resto por nombre
    func pickerList() -> [Project] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return req.projects.filter { q.isEmpty || $0.name.lowercased().contains(q) }.sorted { a, b in
            if (a.db == req.db) != (b.db == req.db) { return a.db == req.db }
            return a.name.lowercased() < b.name.lowercased()
        }
    }

    func folderRow(_ p: Project) -> some View {
        var sub = p.db == req.db ? "Usa esta BBDD" : p.db.isEmpty ? "Sin BBDD detectada" : "BBDD: \(p.db)"
        if !p.php.isEmpty { sub += "  ·  .php-version \(p.php)" }
        let selected = p.name == folder
        return VStack(alignment: .leading, spacing: 2) {
            Text(p.name)
            Text(sub).font(.caption).foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(selected ? ACCENT.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            folder = p.name
            accept()
        }
        .onTapGesture { folder = p.name }
    }

    func accept() {
        guard let f = folder else { return }
        model.loadProject(req, folder: f, version: req.inst.folder, manual: true)
    }
}

// MARK: - Ventana de una tarea

struct TaskView: View {
    @ObservedObject var task: TaskRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // «Terminado» en gris no se ve de un vistazo: check azul grande y el título en azul
            if task.succeeded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(ACCENT)
                    .frame(maxWidth: .infinity)
            }
            Text(task.head).font(.title3.weight(.semibold))
                .foregroundColor(task.succeeded ? ACCENT : .primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
            // Encima de la barra: lo que se hace (a la izquierda) y el porcentaje con lo que queda
            HStack(spacing: 12) {
                Text(task.barText).foregroundColor(.secondary).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
                Text(task.pctText).font(Font.system(size: 13, weight: .bold).monospacedDigit())
            }
            .padding(.top, 4)
            TaskBar(fraction: task.fraction, failed: task.failed)
            if !task.info.isEmpty {
                Text(task.info).font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
            }
            if !task.parts.isEmpty {
                Card {
                    ForEach(Array(task.parts.enumerated()), id: \.offset) { i, part in
                        VStack(spacing: 0) {
                            if i > 0 { Divider() }
                            Row(part) { partState(i + 1) }
                        }
                    }
                }
            }
            // El registro, como una terminal (sin DisclosureGroup: su botón tomaría el estilo de la ventana)
            Button(action: { task.showLog.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: task.showLog ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold)).frame(width: 12)
                    Text("Ver registro")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .hoverPointer()
            if task.showLog {
                TaskConsole(log: task.log, height: task.withProgress ? 220 : 180)
            }
            HStack(spacing: 10) {
                Spacer()
                if task.failed {
                    Button("Ver el log del error") { task.showReport = true }
                        .buttonStyle(OutlineButton(big: true))
                }
                if let label = task.extraLabel {
                    Button(label) { task.extraAction?() }
                        .buttonStyle(OutlineButton(kind: "primary", big: true))
                }
                if !task.finished {
                    Button("Seguir en segundo plano") { task.model?.taskHidden = true }
                        .buttonStyle(OutlineButton(big: true))
                        .tip("Esconder esta ventana y seguir usando el programa")
                }
                Button(task.finished ? "Cerrar" : "Cancelar") { task.closeTapped() }
                    .buttonStyle(OutlineButton(big: true))
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 620)
        .interactiveDismissDisabled(true)
        .sheet(isPresented: $task.showReport) { ReportView(task: task).buttonStyle(PointerButtonStyle()) }
    }

    @ViewBuilder
    func partState(_ i: Int) -> some View {
        if task.finished && task.failedPart == i && task.head != task.doneText {
            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        } else if i < task.cur {
            Image(systemName: "checkmark.circle.fill").foregroundColor(ACCENT)
        } else if i == task.cur && !task.finished {
            ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
        } else {
            Text("…").foregroundColor(.secondary)
        }
    }
}

/// Barra de una tarea: gruesa (12 de alto), redondeada y azul; roja si ha fallado. Sin porcentaje
/// (fraction nil), un trozo que va y viene
struct TaskBar: View {
    let fraction: Double?
    let failed: Bool

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(failed ? RED.opacity(0.22) : Color.primary.opacity(0.10))
                if let f = fraction {
                    Capsule().fill(failed ? RED : ACCENT)
                        .frame(width: g.size.width * CGFloat(max(0, min(1, f))))
                        .animation(.easeOut(duration: 0.3), value: f)
                } else {
                    TimelineView(.animation) { ctx in
                        Capsule().fill(ACCENT)
                            .frame(width: g.size.width * 0.3)
                            .offset(x: swing(ctx.date) * g.size.width * 0.7)
                    }
                    .frame(width: g.size.width, alignment: .leading)
                }
            }
        }
        .frame(height: 12)
    }

    /// De 0 a 1 y vuelta, suave (cada 2,8 s)
    func swing(_ date: Date) -> CGFloat {
        return CGFloat((sin(date.timeIntervalSinceReferenceDate * 2.25) + 1) / 2)
    }
}

/// El registro de una tarea como una terminal: fondo oscuro, letra clara de ancho fijo que salta de
/// línea y siempre al final
struct TaskConsole: View {
    let log: String
    let height: CGFloat
    /// (el informe del error se lee desde el principio)
    var toEnd = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(log)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(CONSOLE_TEXT)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("fin")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .frame(height: height)
            .background(CONSOLE_BG)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.25), lineWidth: 1))
            // (la barra de desplazamiento, la de un fondo oscuro)
            .environment(\.colorScheme, .dark)
            .onAppear { if toEnd { proxy.scrollTo("fin", anchor: .bottom) } }
            .onChange(of: log) { _ in if toEnd { proxy.scrollTo("fin", anchor: .bottom) } }
        }
    }
}

// Informe del error para copiarlo y buscar la solución
struct ReportView: View {
    @ObservedObject var task: TaskRunner
    @State private var copied = false

    var body: some View {
        let (text, folder, isReport) = task.report()
        return VStack(alignment: .leading, spacing: 12) {
            Text("Log del error").font(.title3.weight(.semibold)).frame(maxWidth: .infinity)
            Text("Cópialo para buscar la solución o enviarlo. "
                 + (isReport ? "Lleva el sistema, el paso que ha fallado y sus errores. " : "")
                 + "Los logs completos están en \(folder).")
                .foregroundColor(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
            TaskConsole(log: text, height: 420, toEnd: false)
            HStack(spacing: 10) {
                Spacer()
                Button(copied ? "Copiado" : "Copiar todo") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
                .buttonStyle(OutlineButton(kind: "primary", big: true))
                Button("Abrir la carpeta de logs") { showFolder(folder) }
                    .buttonStyle(OutlineButton(big: true))
                Button("Cerrar") { task.showReport = false }
                    .buttonStyle(OutlineButton(big: true))
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 760)
    }
}

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
                         "Apache solo escucha en 127.0.0.1 y ::1, y en /etc/hosts \(f[1].isEmpty ? "no está" : "apunta a \(f[1])"). El navegador da «No se puede acceder a este sitio web». Arreglarlo hace que \(f[0]) lleve a 127.0.0.1 y ::1 (una sola vez; la copia del /etc/hosts anterior queda en ~/lvm-copias). Pide la contraseña de administrador.") {
                        Row("\(f[0]) → \(f[1].isEmpty ? "sin línea en /etc/hosts" : f[1])", "Tiene que ir a 127.0.0.1, donde escucha Apache", trailing: {
                            Button("Arreglarlo") { model.fixHostsLink() }
                                .buttonStyle(OutlineButton(kind: "primary"))
                                .disabled(model.busy)
                        })
                    }
                }
                // En la misma fila: el host falseado ocupa 1/3 y el proyecto nuevo, 2/3
                OneThirdTwoThirds(first: {
                    Card("Host falseado",
                         "Al cargar una tienda PrestaShop se crea lo que le falte (su vhost y su certificado) y su dominio se falsea en /etc/hosts: el navegador la abre en este Mac. Al cargar otro proyecto deja de estar falseado y vuelve a llevar a la web real.") {
                        if fakes(hosts).isEmpty {
                            Row("Ningún dominio falseado", "Los dominios de los vhosts llevan a sus webs reales")
                        }
                        ForEach(fakes(hosts), id: \.name) { h in
                            if h.name != fakes(hosts).first?.name { Divider() }
                            hostRow(h)
                        }
                    }
                }, second: {
                    newDomainCard(hosts)
                })
                Card("Dominios de los vhosts",
                     "Encendido, el dominio lleva a este Mac (127.0.0.1 y ::1); apagado, a la web real. Se pide la contraseña de administrador para cambiar /etc/hosts.") {
                    if rest(hosts).isEmpty {
                        Row("No hay más dominios", "Los vhosts están en XAMPP-compartido/httpd-vhosts.conf")
                    }
                    ForEach(rest(hosts), id: \.name) { h in
                        if h.name != rest(hosts).first?.name { Divider() }
                        hostRow(h)
                    }
                }
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
                Picker("", selection: Binding(get: { model.newFolder }, set: { model.pickNewFolder($0) })) {
                    if model.newFolder.isEmpty { Text("Elige una carpeta").tag("") }
                    ForEach(folderChoices, id: \.self) { f in
                        Text(folders.contains(f) ? f : "\(f) (nueva)").tag(f)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
                IconButton(symbol: "plus", help: "Crear una carpeta nueva") { model.askNewDomainName(db: false) }
                    .disabled(model.busy)
            }
            Divider()
            Row("BBDD", active.isEmpty ? "No hay ninguna versión activa" : "En XAMPP-\(active)") {
                Picker("", selection: $model.newDb) {
                    Text("Sin BBDD").tag("")
                    ForEach(dbChoices, id: \.self) { db in
                        Text(dbs.contains(db) ? db : "\(db) (nueva)").tag(db)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
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

    // Un .local siempre está en /etc/hosts (sin su línea se preguntaría a la red) y no hay ninguna
    // web real a la que devolverlo: no es un dominio falseado, va con los demás
    func fakes(_ hosts: [HostEntry]) -> [HostEntry] {
        return hosts.filter { $0.fake && !$0.name.lowercased().hasSuffix(".local") }
    }
    func rest(_ hosts: [HostEntry]) -> [HostEntry] {
        return hosts.filter { !$0.fake || $0.name.lowercased().hasSuffix(".local") }
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
        ("parches", "Parches nuevos", "arrow.down.circle"),
        ("hosts", "Vhosts y hosts", "network"),
        ("seguridad", "Seguridad entre webs", "lock.shield"),
        ("correo", "Correo de pruebas", "envelope"),
        ("docker", "Docker", "logo:docker"),
        ("tunel", "Túnel de Cloudflare", "cloud"),
        ("apariencia", "Apariencia", "paintpalette"),
        ("github", "GitHub", "logo:github"),
        ("errores", "Registro de errores", "exclamationmark.triangle"),
        ("carpetas", "Carpetas", "folder"),
        ("oficial", "XAMPP oficial", "externaldrive"),
        ("programa", "Programa", "menubar.rectangle"),
        ("info", "Información", "info.circle")]

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
        case "errores":
            TileCard("Registro de errores", "Si la web cargada da un error (el «error crítico» de WordPress), el motivo está en el registro de su vhost: ahí van los errores de PHP. Los de Apache (que no arranca, un vhost mal escrito…), en el general. Lo más reciente está al final.") {
                if let path = projectErrorLog(d) {
                    errorLogRow(d, path: path, title: "error_log de \(model.projects?.link ?? "")"
                                + ((model.projects?.current ?? "").isEmpty ? "" : "  (\(((model.projects?.current ?? "") as NSString).lastPathComponent))"))
                }
                errorLogRow(d, path: ERROR_LOG, title: d.active.isEmpty ? "error_log de Apache" : "error_log de Apache (XAMPP-\(d.active))")
            }
        case "carpetas":
            TileCard("Carpetas") {
                Tile("Copias de seguridad", "~/lvm-copias: BBDD borradas o desinstaladas, y las del XAMPP oficial") {
                    Button("Abrir") { openFolder(NSHomeDirectory() + "/lvm-copias") }
                }
                Tile("Registros de instalaciones", "~/.lvm-instalador: logs de las instalaciones y de la ventana") {
                    Button("Abrir") { openFolder(LOG_DIR) }
                }
            }
        case "oficial":
            officialCard(d)
        case "programa":
            TileCard("Programa", wide: true) {
                Tile("Dejar en la barra de menús al cerrar",
                     "Icono junto al reloj: al cerrar la ventana, la aplicación sigue en él. Desde ahí se abre otra vez, se arranca o para la versión, se abre web.local o se sale.") {
                    Toggle("", isOn: Binding(get: { model.trayOn }, set: { model.setTray($0) }))
                        .toggleStyle(SwitchToggleStyle()).labelsHidden()
                }
            }
        case "info":
            TileCard("Información") {
                Tile("Comandos de lvm-instalador", "Todos los comandos para la terminal y qué hace cada uno") {
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
            componentsCard()
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

    /// Parches nuevos: lo que tiene un parche publicado y «Actualizar todo»
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
        return TileCard("Parches nuevos", "Los parches de seguridad de todo lo que usa Nexum: cada versión de PHP (PHP, Apache, MariaDB, ProFTPD, Perl y phpMyAdmin, frente a lo último de su rama), las imágenes de Docker (las MariaDB comunes, phpMyAdmin y PHP, frente a Docker Hub), Mailpit y cloudflared. Se busca al abrir la ventana el primer arranque del día y cada pocos arranques. Las versiones XAMPP-X.Y se rehacen (la de ahora sigue funcionando mientras se compila); las XAMPP-X.Y.Z llevan su parche en el nombre: la nueva se instala a su lado. Los contenedores de Docker se rehacen en unos segundos, con sus BBDD.", wide: true) {
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
                    Picker("", selection: Binding(get: { m.wp }, set: { model.setMailWp($0) })) {
                        Text("Llevarlos a Mailpit").tag("mailpit")
                        Text("Desactivarlos en la copia local").tag("desactivar")
                        Text("No tocarlos").tag("nada")
                    }
                    .labelsHidden()
                    .frame(width: 250)
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
                    "\(plural(d.copies[folder] ?? 0, "copia", "copias")) en ~/lvm-copias. Las que ya existan en la versión activa no se tocan.") {
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

// MARK: - Icono en la barra de menús (junto al reloj)

/// «no» si se ha quitado en Configuración (sin el fichero, puesto)
let TRAY_FILE = LOG_DIR + "/ventana-bandeja"

func trayWanted() -> Bool {
    let s = (try? String(contentsOfFile: TRAY_FILE, encoding: .utf8)) ?? ""
    return s.trimmingCharacters(in: .whitespacesAndNewlines) != "no"
}

/// El icono de la barra de menús: abrir la ventana, arrancar o parar la versión activa, abrir web.local y
/// salir. Su menú se rehace cada vez que se abre, con lo último que se sabe
final class TrayIcon: NSObject, NSMenuDelegate {
    static let shared = TrayIcon()
    private var item: NSStatusItem?
    var on: Bool { return item != nil }

    func show(_ yes: Bool) {
        guard yes else {
            if let i = item { NSStatusBar.system.removeStatusItem(i) }
            item = nil
            return
        }
        guard item == nil else { return }
        let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = i.button {
            let img = (NSApp.applicationIconImage.copy() as? NSImage) ?? NSImage()
            img.size = NSSize(width: 18, height: 18)
            b.image = img
            b.toolTip = "Nexum Dev Stack"
        }
        let m = NSMenu()
        m.delegate = self
        // (se activan aquí, según lo que se sabe)
        m.autoenablesItems = false
        i.menu = m
        item = i
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let model = AppModel.current
        let d = model?.data
        let act = d?.active ?? ""
        let running = d?.running ?? false
        let link = model?.projects?.link ?? ""
        func add(_ title: String, _ sel: Selector?, _ enabled: Bool = true) {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            it.target = self
            it.isEnabled = enabled && sel != nil
            menu.addItem(it)
        }
        add("Abrir Nexum Dev Stack", #selector(openWindow))
        menu.addItem(.separator())
        add(act.isEmpty ? "Ninguna versión activa" : running ? "● XAMPP-\(act) en marcha" : "○ XAMPP-\(act) parada", nil)
        add(act.isEmpty ? "Elegir una versión…" : running ? "Parar y desactivar" : "Arrancar XAMPP-\(act)",
            #selector(power), d != nil && !(model?.busy ?? true))
        add("Abrir \(link.isEmpty ? "web.local" : link)", #selector(openWeb), !link.isEmpty && running)
        menu.addItem(.separator())
        add("Salir", #selector(quit))
    }

    /// Como al pulsar el icono del Dock: vuelve la ventana que hay; si no queda ninguna, SwiftUI abre otra
    @objc func openWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized) }) {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
            return
        }
        let ev = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication),
                                        targetDescriptor: NSAppleEventDescriptor(processIdentifier: ProcessInfo.processInfo.processIdentifier),
                                        returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        _ = try? ev.sendEvent(options: [.noReply], timeout: 5)
    }

    @objc func power() {
        if (AppModel.current?.data?.active ?? "").isEmpty { openWindow() }
        AppModel.current?.power()
    }

    @objc func openWeb() {
        if let link = AppModel.current?.projects?.link, !link.isEmpty { openURL("http://\(link)/") }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Terminal (abajo de la ventana)

/// Tu shell en una pseudoterminal (con su sesión y su terminal de control: Ctrl+C y los trabajos van
/// como en Terminal). Se ve como texto: sin colores ni programas a pantalla completa (vim, htop)
final class TermSession {
    let view = TermTextView(frame: .zero)
    private var master: Int32 = -1
    private var pid: pid_t = 0
    private var source: DispatchSourceRead?
    var onExit: (() -> Void)?
    var running: Bool { return pid > 0 }

    init() {
        view.send = { [weak self] d in self?.write(d) }
    }

    func start(cwd: String) -> Bool {
        guard pid == 0 else { return true }
        let m = posix_openpt(O_RDWR | O_NOCTTY)
        guard m >= 0 else { return false }
        guard grantpt(m) == 0, unlockpt(m) == 0, let name = ptsname(m) else { close(m); return false }
        let slave = String(cString: name)
        var ws = winsize(ws_row: 40, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)
        // (TIOCSWINSZ: en Swift no llega, es una macro de C; en macOS vale 0x80087467)
        _ = ioctl(m, UInt(0x80087467), &ws)
        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        // (una sesión nueva: al abrir la pseudoterminal, pasa a ser su terminal de control)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        var fa: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&fa)
        posix_spawn_file_actions_addopen(&fa, 0, slave, O_RDWR, 0)
        posix_spawn_file_actions_adddup2(&fa, 0, 1)
        posix_spawn_file_actions_adddup2(&fa, 0, 2)
        posix_spawn_file_actions_addchdir_np(&fa, cwd)
        let env0 = ProcessInfo.processInfo.environment
        var shell = env0["SHELL"] ?? "/bin/zsh"
        if !shell.hasPrefix("/") || !FileManager.default.isExecutableFile(atPath: shell) { shell = "/bin/zsh" }
        var env = env0
        // (sin colores ni redibujos: se ve como texto)
        env["TERM"] = "dumb"
        env["CLICOLOR"] = "0"
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup(shell), strdup("-l"), nil]
        let envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        var p: pid_t = 0
        let rc = posix_spawn(&p, shell, &fa, &attr, argv, envp)
        for a in argv { free(a) }
        for e in envp { free(e) }
        posix_spawn_file_actions_destroy(&fa)
        posix_spawnattr_destroy(&attr)
        guard rc == 0 else { close(m); return false }
        master = m
        pid = p
        view.reset()
        let src = DispatchSource.makeReadSource(fileDescriptor: m, queue: .main)
        src.setEventHandler { [weak self] in self?.readOut() }
        src.resume()
        source = src
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var st: Int32 = 0
            waitpid(p, &st, 0)
            DispatchQueue.main.async { self?.exited() }
        }
        return true
    }

    private func readOut() {
        guard master >= 0 else { return }
        var buf = [UInt8](repeating: 0, count: 16384)
        let n = read(master, &buf, buf.count)
        if n > 0 { view.feed(Array(buf[0..<n])) }
    }

    func write(_ d: Data) {
        guard master >= 0 else { return }
        d.withUnsafeBytes { raw in _ = Darwin.write(master, raw.baseAddress, raw.count) }
    }

    func stop() {
        if pid > 0 { kill(pid, SIGHUP) }
    }

    private func exited() {
        source?.cancel()
        source = nil
        if master >= 0 { close(master) }
        master = -1
        pid = 0
        onExit?()
    }
}

/// El texto de la terminal: enseña lo que sale (sin los códigos de color ni de cursor) y manda lo que
/// se teclea a la pseudoterminal
final class TermTextView: NSTextView {
    var send: ((Data) -> Void)?
    private var pending: [UInt8] = []
    private let font0 = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    override var acceptsFirstResponder: Bool { return true }

    func reset() {
        pending = []
        line = []
        col = 0
        lineStart = 0
        textStorage?.setAttributedString(NSAttributedString(string: ""))
    }

    private func trimmed(_ l: [Character]) -> String {
        var end = l.count
        while end > 0 && l[end - 1] == " " { end -= 1 }
        return String(l[..<end])
    }

    /// La última línea (la que se escribe ahora), su cursor y dónde empieza en el texto
    private var line: [Character] = []
    private var col = 0
    private var lineStart = 0

    // (⌘C, ⌘V y ⌘A aquí mismo: con el texto no editable, el menú Edición deja Pegar desactivado)
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        guard window?.firstResponder === self,
              e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock) == .command else {
            return super.performKeyEquivalent(with: e)
        }
        switch e.charactersIgnoringModifiers?.lowercased() {
        case "c": copy(nil); return true
        case "v": paste(nil); return true
        case "a": selectAll(nil); return true
        default: return super.performKeyEquivalent(with: e)
        }
    }

    /// Botón derecho: Copiar, Pegar y Seleccionar todo
    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: "Copiar", action: #selector(copy(_:)), keyEquivalent: "c")
        m.addItem(withTitle: "Pegar", action: #selector(paste(_:)), keyEquivalent: "v")
        m.addItem(.separator())
        m.addItem(withTitle: "Seleccionar todo", action: #selector(selectAll(_:)), keyEquivalent: "a")
        // (se activan aquí: NSTextView deja Pegar desactivado si el texto no es editable)
        m.autoenablesItems = false
        m.items[0].isEnabled = selectedRange().length > 0
        m.items[1].isEnabled = NSPasteboard.general.string(forType: .string) != nil
        for i in m.items { i.target = self }
        return m
    }

    override func keyDown(with e: NSEvent) {
        // (⌘: lo del menú, como copiar)
        if e.modifierFlags.contains(.command) { super.keyDown(with: e); return }
        var out: [UInt8]? = nil
        switch e.keyCode {
        case 36, 76: out = [13]
        case 51: out = [127]
        case 48: out = [9]
        case 53: out = [27]
        case 123: out = Array("\u{1b}[D".utf8)
        case 124: out = Array("\u{1b}[C".utf8)
        case 125: out = Array("\u{1b}[B".utf8)
        case 126: out = Array("\u{1b}[A".utf8)
        default:
            if e.modifierFlags.contains(.control), let c = e.charactersIgnoringModifiers?.lowercased().unicodeScalars.first,
               c.value >= 97 && c.value <= 122 {
                out = [UInt8(c.value - 96)]
            } else if let s = e.characters, !s.isEmpty {
                out = Array(s.utf8)
            }
        }
        if let o = out { send?(Data(o)) }
    }

    override func paste(_ sender: Any?) {
        // (como en Terminal, cada salto de línea llega como Intro)
        guard let s = NSPasteboard.general.string(forType: .string) else { return }
        send?(Data(s.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r").utf8))
    }

    /// Lo que sale de la terminal: sin los códigos de escape; \r vuelve al principio de la línea y \b retrocede
    func feed(_ bytes: [UInt8]) {
        var data = pending + bytes
        pending = []
        // (un carácter de varios bytes a medias: espera al resto)
        var cut = data.count
        var i = data.count - 1
        var back = 0
        while i >= 0 && back < 4 && (data[i] & 0xC0) == 0x80 { i -= 1; back += 1 }
        if i >= 0 && data[i] >= 0xC0 {
            let need = data[i] >= 0xF0 ? 4 : data[i] >= 0xE0 ? 3 : 2
            if data.count - i < need { cut = i }
        }
        if cut < data.count { pending = Array(data[cut...]); data = Array(data[..<cut]) }
        var text = String(decoding: data, as: UTF8.self)
        text = text.replacingOccurrences(of: "\u{1b}\\][^\u{07}\u{1b}]*(\u{07}|\u{1b}\\\\)", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\u{1b}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\u{1b}[()][0-9A-Za-z]|\u{1b}[=>78]", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{07}", with: "")
        guard let ts = textStorage else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: font0, .foregroundColor: NSColor(calibratedRed: 0xD7 / 255.0, green: 0xDE / 255.0, blue: 0xE6 / 255.0, alpha: 1)]
        // La línea de ahora se lleva aparte, con su cursor: \r vuelve al principio y lo que sigue escribe
        // encima (zsh, antes del prompt, pone «%» y espacios hasta el borde y vuelve con \r: sin esto, el
        // prompt salía a la derecha); \b retrocede. Al acabar, solo se cambia esa última línea
        if lineStart > ts.length { lineStart = ts.length }
        var done = ""
        for ch in text {
            if ch == "\n" {
                done += trimmed(line) + "\n"
                line = []
                col = 0
            } else if ch == "\r" {
                col = 0
            } else if ch == "\u{08}" {
                col = max(0, col - 1)
            } else {
                if col < line.count {
                    line[col] = ch
                } else {
                    if col > line.count { line += Array(repeating: Character(" "), count: col - line.count) }
                    line.append(ch)
                }
                col += 1
            }
        }
        // (sin los espacios del final: los de zsh hasta el borde harían saltar una línea vacía)
        let tail = trimmed(line)
        ts.replaceCharacters(in: NSRange(location: lineStart, length: ts.length - lineStart),
                             with: NSAttributedString(string: done + tail, attributes: attrs))
        lineStart = ts.length - (tail as NSString).length
        // (como mucho las últimas 200.000 letras)
        if ts.length > 250_000 {
            let cut = ts.length - 200_000
            ts.deleteCharacters(in: NSRange(location: 0, length: cut))
            lineStart = max(0, lineStart - cut)
        }
        scrollToEndOfDocument(nil)
    }
}

/// El texto de la terminal en su caja con barra de desplazamiento
/// La bandeja de Mailpit dentro de la ventana, sin nada en disco. Solo se navega dentro de Mailpit: un
/// enlace de un correo va al navegador, y solo si se ha pulsado
final class MailWebHost: NSObject, WKNavigationDelegate, WKUIDelegate {
    let view: WKWebView
    private var loaded = ""

    override init() {
        let conf = WKWebViewConfiguration()
        conf.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        view = WKWebView(frame: .zero, configuration: conf)
        super.init()
        view.navigationDelegate = self
        view.uiDelegate = self
    }

    func show(_ url: String) {
        guard loaded != url, let u = URL(string: url) else { return }
        loaded = url
        view.load(URLRequest(url: u))
    }

    private func external(_ url: URL?) {
        if let u = url, u.scheme == "http" || u.scheme == "https" { openURL(u.absoluteString) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let target = action.request.url?.absoluteString ?? ""
        if !loaded.isEmpty && (target.hasPrefix(loaded) || target.hasPrefix("about:") || target.hasPrefix("blob:" + loaded)) {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if action.navigationType == .linkActivated { external(action.request.url) }
    }

    /// Un adjunto que no se puede enseñar: lo descarga el navegador, que pregunta dónde guardarlo
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if response.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            external(response.response.url)
        }
    }

    /// target=_blank: nada de ventanas nuevas; al navegador si se ha pulsado
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.navigationType == .linkActivated { external(action.request.url) }
        return nil
    }

    // (parado o sin responder: se vuelve a pedir la próxima vez que se vea en marcha)
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loaded = ""
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

struct MailWebView: NSViewRepresentable {
    let host: MailWebHost
    let url: String

    func makeNSView(context: Context) -> WKWebView {
        host.show(url)
        return host.view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        host.show(url)
    }
}

struct TermHost: NSViewRepresentable {
    let session: TermSession

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.scrollerStyle = .overlay
        sv.drawsBackground = true
        sv.backgroundColor = NSColor(calibratedRed: 0x1D / 255.0, green: 0x22 / 255.0, blue: 0x28 / 255.0, alpha: 1)
        sv.borderType = .noBorder
        let tv = session.view
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = true
        tv.backgroundColor = NSColor(calibratedRed: 0x1D / 255.0, green: 0x22 / 255.0, blue: 0x28 / 255.0, alpha: 1)
        tv.textContainerInset = NSSize(width: 8, height: 6)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        sv.documentView = tv
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return sv
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

/// La terminal de abajo, pegada a la ventana: una barra con sus botones y, debajo, la terminal de lado a
/// lado. El borde de arriba se arrastra para cambiar su alto
struct TermPanel: View {
    @EnvironmentObject var model: AppModel
    @State private var dragStart: CGFloat? = nil

    var body: some View {
        VStack(spacing: 0) {
            // (el borde de arriba: se arrastra para cambiar el alto)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
                .overlay(Color.clear.frame(height: 7).contentShape(Rectangle())
                    .gesture(DragGesture().onChanged { v in
                        if dragStart == nil { dragStart = model.termHeight }
                        model.termHeight = min(700, max(140, (dragStart ?? 260) - v.translation.height))
                    }.onEnded { _ in dragStart = nil })
                    .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } })
            HStack(spacing: 8) {
                Image(systemName: "terminal").foregroundColor(.secondary)
                Text("Terminal").font(.caption)
                Text(model.termCwd).font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(action: { model.termCd() }) { Label("Proyecto cargado", systemImage: "folder") }
                    .buttonStyle(OutlineButton())
                    .tip("Ir a la carpeta del proyecto cargado (cd)")
                Button(action: { model.termFlushDns() }) { Label("Vaciar DNS", systemImage: "network") }
                    .buttonStyle(OutlineButton())
                    .tip("Vaciar la caché DNS")
                Button(action: { model.termStart(restart: true) }) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(OutlineButton())
                    .tip("Terminal nueva (cierra la de ahora)")
                Button(action: { model.termOpen = false }) { Image(systemName: "xmark") }
                    .buttonStyle(OutlineButton())
                    .tip("Esconder la terminal (sigue abierta)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            TermHost(session: model.term)
        }
        .frame(height: model.termHeight)
    }
}

// MARK: - Ventana principal

/// Arriba, la barra con el visor de la versión montada; a la izquierda, los apartados (ENTORNO y
/// SISTEMA); a la derecha, el elegido
struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Divider()
            HStack(spacing: 0) {
                Sidebar()
                Divider()
                VStack(spacing: 0) {
                    detail()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if model.termOpen {
                        TermPanel()
                    }
                }
            }
        }
        // Todos los botones: con borde, la mano y el borde azul al pasar el ratón (como en Linux)
        .buttonStyle(PointerButtonStyle())
        .overlay(panel())
        .overlay(toastView(), alignment: .bottom)
        // (escondida en segundo plano, la hoja no se ve; la tarea sigue y su aviso está al lado del visor)
        .sheet(item: Binding(get: { model.taskHidden ? nil : model.task },
                             set: { t in if t == nil && !model.taskHidden { model.task = nil } })) { t in
            TaskView(task: t).buttonStyle(PointerButtonStyle())
        }
        .onAppear { model.applyTheme() }
    }

    @ViewBuilder
    func detail() -> some View {
        switch model.tab {
        case "versiones": VersionsView()
        case "bbdd": DatabasesView()
        case "docker": DockerView()
        case "repos": ReposView()
        case "node": NodeView()
        case "dominios": HostsView()
        case "config": ToolsView()
        default: ProjectsView()
        }
    }

    /// Ventana encima de la página (no mientras hay una tarea: la tarea va en su hoja). El asistente
    /// de proyecto nuevo sigue abierto si su tarea falla, para corregirlo
    @ViewBuilder
    func panel() -> some View {
        if model.task == nil {
            if model.npOpen {
                PanelBox(title: "Nuevo proyecto", width: 660, close: { model.newProject(false) }) {
                    NewProjectWizard()
                }
            } else if let p = model.panel {
                PanelBox(title: p.title, width: p.width, close: { model.panel = nil }) {
                    switch p {
                    case .components(let only):
                        ComponentsPanel(only: only)
                    case .install:
                        VStack(spacing: 12) {
                            Text("Elige las versiones: cada una se compila en tu Mac (20-40 min) con su Apache, MariaDB y BBDD propias. «Instalar» pide la contraseña de administrador; las instaladas no se tocan.")
                                .font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                            ScrollView {
                                VStack(alignment: .leading, spacing: 18) { InstallSection() }.padding(.trailing, 8)
                            }
                            .frame(height: 490)
                        }
                    case .dockerNew:
                        DockerNewPanel()
                    case .buttons:
                        ButtonsPanel()
                    }
                }
            }
        }
    }

    @ViewBuilder
    func toastView() -> some View {
        if let t = model.toastText {
            Text(t)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(NSColor.windowBackgroundColor)).shadow(radius: 4))
                .padding(.bottom, 24)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Sin depuradores (como PR_SET_DUMPABLE en Linux): la contraseña de administrador pasa por
        // la memoria de la aplicacion. ptrace no esta en el modulo Darwin de Swift: se busca con
        // dlsym (RTLD_DEFAULT es -2 en macOS). 31 es PT_DENY_ATTACH
        typealias Ptrace = @convention(c) (Int32, Int32, UnsafeMutableRawPointer?, Int32) -> Int32
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "ptrace") {
            _ = unsafeBitCast(sym, to: Ptrace.self)(31, 0, nil, 0)
        }
    }
    // Al cerrar la ventana (el boton rojo) la aplicacion se cierra del todo: sin procesos que sigan
    // gastando sin ventana. Con una tarea en marcha (instalar, cargar...) espera a que acabe y se cierra
    // entonces (el didSet de task)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // (con el icono de la barra de menús, sigue abierta en él: se vuelve a abrir o se sale desde ahí)
        return !(AppModel.current?.busy ?? false) && !TrayIcon.shared.on
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        TrayIcon.shared.show(trayWanted())
    }
    // Al pulsar su icono del Dock sin ninguna ventana a la vista: vuelve la que estaba (oculta o en el
    // Dock); si no queda ninguna, SwiftUI abre una nueva (por eso se devuelve true)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let w = sender.windows.first(where: { $0.canBecomeMain }) {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
        }
        return true
    }
}

@main
struct GestorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: model.minWindowWidth, minHeight: 680)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Acerca de \(model.data?.name ?? "Nexum Dev Stack")") { model.showAbout() }
            }
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Gestor") {
                Button("Abrir localhost") { openURL("http://localhost/") }
                Button("Abrir phpMyAdmin") { openURL("http://127.0.0.1/phpmyadmin/") }
                Button("Editar vhosts") { model.editVhosts() }
                Button("Editar hosts") { model.editHosts() }
                Divider()
                Button("Volver a leer las versiones") { model.reload(branches: true) }
                    .keyboardShortcut("r")
                Button("Buscar actualizaciones") { model.checkUpdates() }
                Button("Abrir el panel en Terminal") { model.openTerminal() }
                Button("Carpeta de registros") { showFolder(LOG_DIR) }
                Divider()
                Button("Novedades") { model.showChanges() }
            }
        }
    }
}
