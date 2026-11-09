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
