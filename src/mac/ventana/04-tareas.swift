// MARK: - Tareas (acciones del script en una pseudoterminal)

// Registro de tareas (como en Linux): cada tarea de la ventana deja el suyo en TASKS_DIR (la carpeta y sus
// ficheros, solo tuyos), con su fecha, su título, la orden de nexum, toda su salida y cómo acabó. Se guardan
// las TASKS_KEEP últimas
let TASKS_DIR = LOG_DIR + "/tareas"
let TASKS_KEEP = 200
let TASK_LOG_RX = try! NSRegularExpression(pattern: "^\\d{8}-\\d{6}-\\d+\\.txt$")
/// El registro de una tarea muy larga, como mucho esto (en caracteres): se guarda el final
let TASK_LOG_MAX = 8 * 1024 * 1024
let TASK_LOG_SEP = String(repeating: "=", count: 72)
let HIDDEN = "••••••"
// Nada de secretos en el registro: el valor de las variables de la tarea que lo parecen (MYSQL_PWD…), lo que
// va detrás de «contraseña:», «token=»…, los tokens de GitHub y la contraseña de una dirección
let SECRET_NAME_RX = try! NSRegularExpression(pattern: "pass|pwd|token|secret|clave|key|auth", options: [.caseInsensitive])
let SECRET_RX = try! NSRegularExpression(
    pattern: "((?:contraseña|password|passwd|pwd|token|secret|clave)[\\w ]{0,16}?[ \\t]*[:=][ \\t]*)(?!••••••)[^\\s'\"]+",
    options: [.caseInsensitive])
let SECRET_TOKEN_RX = try! NSRegularExpression(pattern: "\\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})")
let SECRET_URL_RX = try! NSRegularExpression(pattern: "(://[^/\\s:@]+:)[^@\\s/]+@")

func isSecretName(_ name: String) -> Bool {
    return SECRET_NAME_RX.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
}

func taskLogRedact(_ text: String, env: [String: String]) -> String {
    var t = text
    for (k, v) in env where v.count >= 3 && isSecretName(k) {
        t = t.replacingOccurrences(of: v, with: HIDDEN)
    }
    t = SECRET_RX.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "$1" + HIDDEN)
    t = SECRET_TOKEN_RX.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: HIDDEN)
    return SECRET_URL_RX.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "$1" + HIDDEN + "@")
}

/// Un argumento como se escribiría en la terminal (entre comillas si hace falta)
func shellQuote(_ s: String) -> String {
    if !s.isEmpty && s.range(of: "^[A-Za-z0-9_@%+=:,./-]+$", options: .regularExpression) != nil { return s }
    return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// La orden de una tarea como se escribiría en la terminal
func taskLogCommand(_ args: [String]) -> String {
    return (["nexum"] + (SIMULATE ? ["--simular"] : []) + args.map { shellQuote($0) }).joined(separator: " ")
}

/// La carpeta del registro de tareas, creada y solo tuya (false si no se puede o es un enlace)
func taskLogDir() -> Bool {
    let fm = FileManager.default
    if let attrs = try? fm.attributesOfItem(atPath: TASKS_DIR),
       (attrs[.type] as? FileAttributeType) == .typeSymbolicLink { return false }
    do {
        try fm.createDirectory(atPath: TASKS_DIR, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: TASKS_DIR)
    } catch {
        return false
    }
    return true
}

/// Escribe el registro de una tarea (solo tuyo, 600; sin seguir enlaces)
func taskLogWrite(_ path: String, _ text: String) {
    let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, mode_t(0o600))
    guard fd >= 0 else { return }
    _ = fchmod(fd, mode_t(0o600))
    let h = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    h.write(Data(text.utf8))
}

/// Se quedan las TASKS_KEEP últimas: las más viejas se borran
func taskLogNames() -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: TASKS_DIR)) ?? []
    return names.filter { TASK_LOG_RX.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }.sorted()
}

func taskLogPrune() {
    let names = taskLogNames()
    guard names.count > TASKS_KEEP else { return }
    for n in names.prefix(names.count - TASKS_KEEP) {
        try? FileManager.default.removeItem(atPath: TASKS_DIR + "/" + n)
    }
}

/// Una tarea del registro: su cabecera (título, orden, fecha, cómo acabó) y su texto entero
struct TaskLogEntry: Identifiable {
    let path: String
    let title: String
    let when: String
    let result: String
    let command: String
    var id: String { return path }
    /// ok, error, cancel o run (en marcha)
    var state: String {
        if result.hasPrefix("Terminada") { return "ok" }
        if result.hasPrefix("Cancelada") { return "cancel" }
        if result.hasPrefix("En marcha") { return "run" }
        return "error"
    }
}

/// Lee un registro de tareas (solo un fichero normal, sin enlaces): su cabecera y su texto
func taskLogRead(_ path: String, limit: Int = TASK_LOG_MAX + 65536) -> ([String: String], String)? {
    let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard fd >= 0 else { return nil }
    let h = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    var st = stat()
    guard fstat(fd, &st) == 0, (Int(st.st_mode) & Int(S_IFMT)) == Int(S_IFREG) else { return nil }
    let text = String(decoding: h.readData(ofLength: limit), as: UTF8.self)
    var head: [String: String] = [:]
    let top = text.components(separatedBy: "\n" + TASK_LOG_SEP).first ?? ""
    for line in top.components(separatedBy: "\n") {
        if let r = line.range(of: ": ") {
            head[String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)] =
                String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
    }
    return (head, text)
}

/// Los registros de tareas, el más nuevo primero
func taskLogs() -> [TaskLogEntry] {
    var out: [TaskLogEntry] = []
    for n in taskLogNames().reversed().prefix(TASKS_KEEP) {
        let path = TASKS_DIR + "/" + n
        guard let got = taskLogRead(path, limit: 4096) else { continue }
        let h = got.0
        out.append(TaskLogEntry(path: path, title: h["Tarea"] ?? n, when: h["Fecha"] ?? "",
                                result: h["Resultado"] ?? "", command: h["Orden"] ?? ""))
    }
    return out
}

/// Una tarea del registro, entera (su orden y toda su salida), con «Copiar» y «Abrir la carpeta»
func showTaskLog(_ path: String) {
    guard let got = taskLogRead(path) else {
        showLongText("No se ha podido leer el registro de la tarea", path)
        return
    }
    let alert = NSAlert()
    alert.messageText = got.0["Tarea"] ?? "Tarea"
    alert.informativeText = (got.0["Fecha"] ?? "") + "  ·  " + (got.0["Resultado"] ?? "")
    alert.addButton(withTitle: "Cerrar")
    alert.addButton(withTitle: "Copiar")
    alert.addButton(withTitle: "Abrir la carpeta")
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 760, height: 560))
    scroll.hasVerticalScroller = true
    let tv = NSTextView(frame: scroll.bounds)
    tv.isEditable = false
    tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    tv.textContainerInset = NSSize(width: 10, height: 10)
    tv.string = got.1
    tv.autoresizingMask = [.width]
    scroll.documentView = tv
    alert.accessoryView = scroll
    let r = alert.runStyled()
    if r == .alertSecondButtonReturn {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(got.1, forType: .string)
    } else if r == .alertThirdButtonReturn {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

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
    /// Su fichero del registro de tareas (TASKS_DIR)
    private var logPath: String? = nil

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
        // (su registro, desde que empieza: si la ventana se cierra a medias, queda al menos qué se lanzó)
        if taskLogDir() {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyyMMdd-HHmmss"
            let ms = Int(started.timeIntervalSince1970 * 1000) % 1000
            logPath = TASKS_DIR + "/" + fmt.string(from: started) + "-" + String(ProcessInfo.processInfo.processIdentifier)
                + String(format: "%03d", ms) + ".txt"
            saveLog("En marcha (o la ventana se cerró antes de que acabara)")
            taskLogPrune()
            model?.taskLogsChanged += 1
        }
    }

    /// El registro de la tarea en TASKS_DIR: la cabecera (título, orden, fecha, cómo acabó) y su salida, la
    /// misma de su ventana, sin secretos
    private func saveLog(_ result: String, _ text: String = "") {
        guard let path = logPath else { return }
        let fmt = DateFormatter()
        fmt.dateFormat = "dd/MM/yyyy HH:mm:ss"
        var head = ["Tarea: " + title.replacingOccurrences(of: "\n", with: " "),
                    "Orden: " + taskLogCommand(args),
                    "Fecha: " + fmt.string(from: started),
                    "Resultado: " + result]
        if !text.isEmpty { head.append("Duración: " + fmtClock(Int(Date().timeIntervalSince(started)))) }
        if !env.isEmpty {
            head.append("Variables: " + env.keys.sorted().map { k in k + "=" + (isSecretName(k) ? HIDDEN : (env[k] ?? "")) }
                .joined(separator: " "))
        }
        var body = text
        if body.count > TASK_LOG_MAX {
            body = "(…se ha cortado el principio: solo se guarda el final)\n" + String(body.suffix(TASK_LOG_MAX))
        }
        let all = head.joined(separator: "\n") + "\n" + TASK_LOG_SEP + "\n"
            + body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        taskLogWrite(path, taskLogRedact(all, env: env))
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
        saveLog(cancelled ? "Cancelada" : (ok ? "Terminada bien" : "Ha fallado (código \(rc))"), log.isEmpty ? "(sin salida)" : log)
        // (Configuración, General: el registro de tareas, con esta ya acabada)
        model?.taskLogsChanged += 1
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
