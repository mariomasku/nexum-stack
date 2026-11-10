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
/// Copias de seguridad (COPIES_DIR del script): solo las que se piden, y las de los ficheros que cambia el
/// programa si está el ajuste COPIES_FILES_FLAG (lvm-instalador copias-ficheros si|no)
let COPIES_DIR = NSHomeDirectory() + "/nexum-backups"
let COPIES_FILES_FLAG = LOG_DIR + "/copias-ficheros"
/// La casilla de los diálogos que pueden guardar antes una copia (desmarcada de partida: marcada, --copia) y
/// el aviso en rojo que sale debajo mientras está desmarcada
let COPY_CHECKBOX = "Guardar antes una copia en ~/nexum-backups"
let COPY_WARNING = "Sin copia, lo que se sustituya no se podrá recuperar."
/// (al actualizar una versión en su carpeta: solo hace falta si MariaDB cambia de rama)
let UPDATE_COPY_WARNING = "Sin copia, si su MariaDB cambia de rama, sus BBDD no se podrán recuperar."
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

/// Caché de descargas de las pilas propias (lvm-instalador descargas)
let DL_CACHE_DIR = "/Library/Nexum/descargas"

/// Ficheros de la caché de descargas y lo que ocupan (sin sus .sha256)
func downloadsCacheSize() -> (files: Int, size: Int64) {
    var files = 0
    var size: Int64 = 0
    let fm = FileManager.default
    for name in (try? fm.contentsOfDirectory(atPath: DL_CACHE_DIR)) ?? [] where !name.hasSuffix(".sha256") {
        guard let a = try? fm.attributesOfItem(atPath: DL_CACHE_DIR + "/" + name),
              a[.type] as? FileAttributeType == .typeRegular else { continue }
        files += 1
        size += (a[.size] as? NSNumber)?.int64Value ?? 0
    }
    return (files, size)
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
