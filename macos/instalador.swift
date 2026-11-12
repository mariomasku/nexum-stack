// Instalador del .dmg de Nexum Dev Stack para Mac (AppKit, macOS 12 o posterior): «Instalar Nexum Dev
// Stack.app». Una ventana pequeña con el logotipo y el botón Instalar; al pulsarlo ejecuta, sin que se vea,
// «lvm-instalador.sh instalar-gestor» del disco (Contents/Resources) con LVM_INSTALADOR=1, y enseña los pasos
// que escribe el script (NEXUM-PASO|<porcentaje>|<texto>) en una barra con su porcentaje. La pregunta de
// Homebrew (NEXUM-PREGUNTA|homebrew|<texto>) sale en un aviso Sí/No y la respuesta va por la entrada.
//
// Lo compila empaquetar-dmg.sh en el Mac donde se crea el .dmg (y la comprobación de GitHub):
//   swiftc -O -target arm64-apple-macos12.0 -o instalar main.swift -framework AppKit
// (copiado como main.swift: el código de arriba del todo es el programa)
//
// Con --simular (o LVM_SIMULAR=1) ejecuta «lvm-instalador.sh --simular instalar-gestor»: no cambia nada.
//   "/Volumes/Nexum Dev Stack <versión>/Instalar Nexum Dev Stack.app/Contents/MacOS/instalar" --simular
//
// El script va dentro de una pseudoterminal (/usr/bin/script), como las tareas de la ventana de Nexum: así
// sudo pide la contraseña como en Terminal. Su aviso (SUDO_PROMPT) es una marca al azar; al verla, la
// contraseña se pide en un panel y solo se escribe si un sudo de root descendiente de esta instalación está
// leyendo de su terminal con el eco apagado. Es la misma lógica de TaskRunner (src/mac/ventana/04-tareas.swift:
// feed, askPassword, sudoAsking y el arranque con TIOCEXCL), copiada aquí porque este es un programa aparte, sin
// SwiftUI ni el resto de la ventana: si se cambia allí, se cambia aquí.
//
// Las herramientas de Xcode se comprueban antes de empezar (la terminal exclusiva se reserva con su python3): si
// faltan, se abre la instalación de Apple y se espera, sondeando xcode-select -p, hasta que estén.
import AppKit
import Darwin

let APP_NAME = "Nexum Dev Stack"
let INSTALLER_NAME = "Instalar " + APP_NAME
let RES_DIR = Bundle.main.resourcePath ?? ((CommandLine.arguments[0] as NSString).deletingLastPathComponent + "/../Resources")
let SCRIPT = RES_DIR + "/lvm-instalador.sh"
let ENV = ProcessInfo.processInfo.environment
let SIMULATE = CommandLine.arguments.contains("--simular") || ENV["LVM_SIMULAR"] == "1"
let VERSION = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
// Marcas de la pseudoterminal (contraseña de sudo y fin del script): distintas en cada ejecución
let RUN_TOKEN = UUID().uuidString.replacingOccurrences(of: "-", with: "")
let SUDO_MARK = "@@LVM-SUDO-\(RUN_TOKEN)@@"
let FIN_TOKEN = UUID().uuidString.replacingOccurrences(of: "-", with: "")
let FIN_RX = try! NSRegularExpression(pattern: "@@LVM-FIN-\(FIN_TOKEN) ([0-9]+)@@")
let ANSI_RX = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[A-Za-z]|\u{1B}[78()][0-9A-Za-z]?")
let APP_BUNDLE = NSHomeDirectory() + "/Applications/" + APP_NAME + ".app"
let LOGS_DIR = NSHomeDirectory() + "/Library/Logs/Nexum"
/// Lo más que se espera a que terminen de instalarse las herramientas de Xcode
let TOOLS_WAIT_MAX: TimeInterval = 60 * 60
/// Los colores del logotipo de Nexum (los mismos de la ventana)
let NEXUM_COLORS: [NSColor] = [0x006CB7, 0x88BB1D, 0xFFB608, 0xFF0000, 0xF20093].map { (v: Int) -> NSColor in
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: 1)
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

/// ¿Están las herramientas de línea de comandos de Xcode (o Xcode)?
func toolsInstalled() -> Bool {
    let path = captureOutput("/usr/bin/xcode-select", ["-p"]).trimmingCharacters(in: .whitespacesAndNewlines)
    return !path.isEmpty && FileManager.default.fileExists(atPath: path)
}

/// Tiempo como un reloj: 0:42, 3:05, 1:02:10
func fmtClock(_ secs: Int) -> String {
    let s = max(0, secs)
    func two(_ n: Int) -> String { return n < 10 ? "0\(n)" : "\(n)" }
    return s >= 3600 ? "\(s / 3600):\(two(s / 60 % 60)):\(two(s % 60))" : "\(s / 60):\(two(s % 60))"
}

/// El disco del que se ha abierto el instalador («Nexum Dev Stack 1.57.15»), si es un disco
func volumeName() -> String? {
    let parts = (Bundle.main.bundlePath as NSString).pathComponents
    if parts.count > 2 && parts[1] == "Volumes" { return parts[2] }
    return nil
}

/// La franja de arriba con los colores del logotipo
final class ColorStrip: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(colors: NEXUM_COLORS)?.draw(in: bounds, angle: 0)
    }
}

/// La ventana y la instalación. No es el delegado de la aplicación (AppDelegate, abajo, le pasa lo suyo): así
/// no queda aislada en el hilo principal por la conformidad, y la lectura de la salida, en su hilo, la puede
/// usar (como TaskRunner en la ventana). Las vistas se crean en start(), ya en el hilo principal
final class Installer: NSObject {
    enum Phase { case idle, tools, running, done, failed }

    var window: NSWindow!
    var iconView: NSImageView!
    var titleLabel: NSTextField!
    var textLabel: NSTextField!
    var bar: NSProgressIndicator!
    var pctLabel: NSTextField!
    var stepLabel: NSTextField!
    var mainButton: NSButton!
    var otherButton: NSButton!
    var detailsButton: NSButton!
    var appIcon: NSImage? = nil

    var phase = Phase.idle
    private var proc: Process?
    private var input: FileHandle?
    private var outPipe: Pipe?
    /// Un trozo que puede ser el principio de la marca de sudo
    private var pending = ""
    /// La línea que aún no ha acabado
    private var lineBuf = ""
    /// Lo que llega mientras hay un aviso abierto (la contraseña, la pregunta): se lee al cerrarlo
    private var queued = ""
    private var modalOpen = false
    /// Bytes de un carácter cortado al final de lo leído (solo en el hilo de la lectura)
    private var rawTail = Data()
    private var log = ""
    private var lastLine = ""
    private var sincePrompt = ""
    private var prompts = 0
    private var cancelled = false
    private var finished = false
    private var finSeen = false
    private var exitCode: Int32? = nil
    private var percent = 0
    private var stepText = ""
    private var alreadyInstalled: String? = nil
    private var started = Date()
    private var clock: Timer?
    private var toolsTimer: Timer?
    private var toolsSince = Date()
    private var logPath: String?
    private var quitWhenDone = false

    // MARK: ventana

    func start(_ delegate: NSWindowDelegate) {
        buildMenu()
        appIcon = NSImage(contentsOfFile: RES_DIR + "/icono.icns") ?? NSApp.applicationIconImage
        iconView = NSImageView()
        titleLabel = NSTextField(labelWithString: "")
        textLabel = NSTextField(wrappingLabelWithString: "")
        bar = NSProgressIndicator()
        pctLabel = NSTextField(labelWithString: "")
        stepLabel = NSTextField(wrappingLabelWithString: "")
        mainButton = NSButton(title: "Instalar", target: nil, action: nil)
        otherButton = NSButton(title: "Cancelar", target: nil, action: nil)
        detailsButton = NSButton(title: "Ver detalles", target: nil, action: nil)
        let w: CGFloat = 560, h: CGFloat = 420
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = INSTALLER_NAME
        window.delegate = delegate
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        window.contentView = content

        let strip = ColorStrip(frame: NSRect(x: 0, y: h - 4, width: w, height: 4))
        strip.autoresizingMask = [.width, .minYMargin]
        content.addSubview(strip)

        iconView.frame = NSRect(x: (w - 96) / 2, y: 298, width: 96, height: 96)
        iconView.image = appIcon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(iconView)

        titleLabel.frame = NSRect(x: 30, y: 258, width: w - 60, height: 30)
        titleLabel.alignment = .center
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        content.addSubview(titleLabel)

        textLabel.frame = NSRect(x: 40, y: 160, width: w - 80, height: 92)
        textLabel.alignment = .center
        textLabel.font = NSFont.systemFont(ofSize: 13)
        textLabel.textColor = .secondaryLabelColor
        textLabel.isSelectable = false
        content.addSubview(textLabel)

        bar.frame = NSRect(x: 40, y: 128, width: w - 80 - 64, height: 20)
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 100
        bar.doubleValue = 0
        content.addSubview(bar)

        pctLabel.frame = NSRect(x: w - 40 - 58, y: 128, width: 58, height: 20)
        pctLabel.alignment = .right
        pctLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        content.addSubview(pctLabel)

        stepLabel.frame = NSRect(x: 40, y: 72, width: w - 80, height: 48)
        stepLabel.alignment = .left
        stepLabel.font = NSFont.systemFont(ofSize: 12)
        stepLabel.textColor = .secondaryLabelColor
        stepLabel.isSelectable = false
        content.addSubview(stepLabel)

        for b in [mainButton!, otherButton!, detailsButton!] {
            b.bezelStyle = .rounded
            b.controlSize = .large
            b.target = self
            content.addSubview(b)
        }
        mainButton.frame = NSRect(x: w - 20 - 210, y: 18, width: 210, height: 34)
        mainButton.action = #selector(mainTapped)
        mainButton.keyEquivalent = "\r"
        otherButton.frame = NSRect(x: w - 20 - 210 - 10 - 120, y: 18, width: 120, height: 34)
        otherButton.action = #selector(otherTapped)
        otherButton.keyEquivalent = "\u{1b}"
        detailsButton.frame = NSRect(x: 20, y: 18, width: 130, height: 34)
        detailsButton.action = #selector(showDetails)

        showIdle(nil)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Salir de " + INSTALLER_NAME, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        // (Edición: para pegar la contraseña con ⌘V)
        let editItem = NSMenuItem()
        menu.addItem(editItem)
        let editMenu = NSMenu(title: "Edición")
        editMenu.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        NSApp.mainMenu = menu
    }

    private func titleText() -> String {
        return INSTALLER_NAME + (VERSION.isEmpty ? "" : " " + VERSION) + (SIMULATE ? " (simulación)" : "")
    }

    private func showIdle(_ note: String?) {
        phase = .idle
        titleLabel.stringValue = titleText()
        textLabel.stringValue = note ?? ("Instala o actualiza " + APP_NAME + " en /Library/Nexum/gestor. La primera vez "
            + "prepara lo que haga falta (las herramientas de Xcode, Homebrew y el bash del gestor) y pide tu "
            + "contraseña de administrador. Tus proyectos y tus bases de datos no se tocan."
            + (SIMULATE ? "\nSimulación: no se cambia nada." : ""))
        bar.isHidden = true
        pctLabel.isHidden = true
        stepLabel.stringValue = ""
        mainButton.title = "Instalar"
        mainButton.isEnabled = true
        mainButton.isHidden = false
        otherButton.title = "Cancelar"
        otherButton.isHidden = false
        detailsButton.isHidden = log.isEmpty
    }

    private func showWorking() {
        titleLabel.stringValue = titleText()
        textLabel.stringValue = "Instalando. Puede tardar unos minutos (la primera vez, algo más). Si hace falta, "
            + "se pide tu contraseña de administrador en su ventana."
        bar.isHidden = false
        pctLabel.isHidden = false
        mainButton.isHidden = true
        otherButton.title = "Cancelar"
        otherButton.isHidden = false
        detailsButton.isHidden = false
    }

    private func refreshStep() {
        let secs = Int(Date().timeIntervalSince(phase == .tools ? toolsSince : started))
        let what = stepText.isEmpty ? "Preparando…" : stepText
        stepLabel.stringValue = what + "   ·   " + fmtClock(secs)
        if !bar.isIndeterminate {
            bar.doubleValue = Double(percent)
            pctLabel.stringValue = "\(percent) %"
        }
    }

    // MARK: botones

    @objc func mainTapped() {
        switch phase {
        case .idle:
            begin()
        case .done:
            openApp()
        case .failed:
            showDetails()
        default:
            break
        }
    }

    @objc func otherTapped() {
        switch phase {
        case .tools:
            stopTools()
            showIdle("Se ha dejado de esperar. Si la instalación de las herramientas de Xcode sigue, cuando termine "
                + "vuelve a pulsar Instalar.")
        case .running:
            if confirmCancel() { cancel() }
        default:
            NSApp.terminate(nil)
        }
    }

    private func confirmCancel() -> Bool {
        let a = NSAlert()
        a.messageText = "¿Cancelar la instalación?"
        a.informativeText = "Se para lo que se esté haciendo. Lo que ya estaba instalado no se toca; puedes volver a "
            + "abrir el instalador cuando quieras."
        a.alertStyle = .warning
        a.addButton(withTitle: "Cancelar la instalación")
        a.addButton(withTitle: "Seguir")
        if let i = appIcon { a.icon = i }
        return a.runModal() == .alertFirstButtonReturn
    }

    /// Al cerrar la ventana a medias: se pregunta antes de cortar
    func shouldClose() -> Bool {
        switch phase {
        case .tools:
            stopTools()
            return true
        case .running:
            if confirmCancel() {
                quitWhenDone = true
                cancel()
            }
            return false
        default:
            return true
        }
    }

    func shouldTerminate() -> NSApplication.TerminateReply {
        if phase == .running && !finished {
            if confirmCancel() {
                quitWhenDone = true
                cancel()
            }
            return .terminateCancel
        }
        return .terminateNow
    }

    // MARK: herramientas de Xcode

    private func begin() {
        log = ""
        lastLine = ""
        percent = 0
        stepText = ""
        alreadyInstalled = nil
        if toolsInstalled() {
            startScript()
            return
        }
        if SIMULATE {
            fail("Faltan las herramientas de Xcode", "En simulación no se instalan. Instálalas (xcode-select --install) "
                + "y vuelve a probar.")
            return
        }
        phase = .tools
        toolsSince = Date()
        showWorking()
        textLabel.stringValue = "Hacen falta las herramientas de línea de comandos de Xcode (compilador, make, python3). "
            + "Sigue las instrucciones de la ventana de Apple: cuando terminen, la instalación sigue sola."
        bar.isIndeterminate = true
        bar.startAnimation(nil)
        pctLabel.stringValue = ""
        stepText = "Instalando las herramientas de Xcode…"
        refreshStep()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        p.arguments = ["--install"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        toolsTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.checkTools() }
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshStep() }
    }

    private func checkTools() {
        guard phase == .tools else { return }
        if toolsInstalled() {
            stopTools()
            startScript()
        } else if Date().timeIntervalSince(toolsSince) > TOOLS_WAIT_MAX {
            stopTools()
            fail("No han terminado de instalarse las herramientas de Xcode",
                 "Se ha esperado una hora. Cuando terminen, vuelve a abrir el instalador.")
        }
    }

    private func stopTools() {
        toolsTimer?.invalidate()
        toolsTimer = nil
        clock?.invalidate()
        clock = nil
        bar.stopAnimation(nil)
        bar.isIndeterminate = false
    }

    // MARK: el script

    private func scriptEnv() -> [String: String] {
        // Solo estas variables de la sesión (como la ventana): el resto podría cambiar lo que hace bash
        // (BASH_FUNC_*, SHELLOPTS, BASH_ENV), cargar librerías (DYLD_*) o cambiar lo que toca el gestor (LVM_*)
        let keep: Set<String> = ["HOME", "USER", "LOGNAME", "LANG", "TMPDIR", "SHELL", "PHP_TIMEZONE",
                                 "__CF_USER_TEXT_ENCODING", "http_proxy", "https_proxy", "no_proxy", "all_proxy",
                                 "HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "ALL_PROXY"]
        var env: [String: String] = [:]
        for (k, v) in ENV where keep.contains(k) || k.hasPrefix("LC_") { env[k] = v }
        if env["HOME"] == nil { env["HOME"] = NSHomeDirectory() }
        if env["USER"] == nil { env["USER"] = NSUserName() }
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin"
        env["LVM_UI"] = "text"
        env["LVM_SIN_PREGUNTAS"] = "1"
        env["LVM_INSTALADOR"] = "1"
        env["LVM_FIN"] = FIN_TOKEN
        env["SUDO_PROMPT"] = SUDO_MARK
        env["TERM"] = "dumb"
        return env
    }

    private func startScript() {
        phase = .running
        cancelled = false
        finished = false
        finSeen = false
        exitCode = nil
        pending = ""
        lineBuf = ""
        queued = ""
        rawTail = Data()
        prompts = 0
        sincePrompt = ""
        started = Date()
        percent = 0
        stepText = "Preparando…"
        showWorking()
        refreshStep()
        let p = Process()
        // script crea la pseudoterminal; bash -c deja al final el código de salida del instalador
        p.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        p.arguments = ["-q", "/dev/null", "/bin/bash", "-c",
                       // Lo primero, la terminal exclusiva (TIOCEXCL): ningún otro programa de tu usuario
                       // puede abrirla para leer la contraseña o escribir la marca de sudo. Si no se puede,
                       // no sigue (la contraseña iría por una terminal abierta)
                       "/usr/bin/python3 -I -c 'import fcntl, termios; fcntl.ioctl(0, termios.TIOCEXCL)' 2> /dev/null "
                       + "|| { echo 'No se ha podido reservar la terminal de la instalación (python3 de Xcode)'; "
                       + "echo \"@@LVM-FIN-$LVM_FIN 97@@\"; exit 97; }; "
                       + "/bin/bash \"$0\" \"$@\"; echo \"@@LVM-FIN-$LVM_FIN $?@@\"",
                       SCRIPT] + (SIMULATE ? ["--simular"] : []) + ["instalar-gestor"]
        p.environment = scriptEnv()
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
            guard let self = self else { return }
            let text = self.decode(data)
            DispatchQueue.main.async { self.receive(text) }
        }
        p.terminationHandler = { [weak self] proc in
            let rc = proc.terminationStatus
            // (lo que quede por leer llega antes que el final)
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
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshStep() }
    }

    /// Texto de lo leído, sin cortar un carácter por la mitad (los bytes del final que no lo completan se
    /// guardan para la siguiente vez). Solo desde el hilo de la lectura
    private func decode(_ data: Data) -> String {
        var d = Data(rawTail)
        d.append(data)
        rawTail = Data()
        let bytes = [UInt8](d)
        let n = bytes.count
        var i = n - 1
        var back = 0
        while i >= 0 && back < 4 {
            let b = bytes[i]
            if b & 0xC0 == 0x80 {
                i -= 1
                back += 1
                continue
            }
            if b & 0x80 != 0 {
                let need = b >= 0xF0 ? 4 : (b >= 0xE0 ? 3 : 2)
                if n - i < need {
                    rawTail = Data(bytes[i...])
                    return String(decoding: bytes[..<i], as: UTF8.self)
                }
            }
            break
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func receive(_ text: String) {
        if modalOpen {
            queued += text
            return
        }
        feed(text)
    }

    /// Después de un aviso: lo que llegó mientras estaba abierto
    private func drainQueued() {
        let q = queued
        queued = ""
        if !q.isEmpty { DispatchQueue.main.async { [weak self] in self?.receive(q) } }
    }

    private func feed(_ text: String) {
        pending += text
        while let r = pending.range(of: SUDO_MARK) {
            let before = String(pending[..<r.lowerBound])
            pending = String(pending[r.upperBound...])
            take(before)
            askPassword()
            if modalOpen || finished { break }
        }
        // Se guarda un trozo que pueda ser el principio de la marca
        var keep = 0
        for i in 1..<SUDO_MARK.count where pending.hasSuffix(String(SUDO_MARK.prefix(i))) { keep = i }
        take(String(pending.dropLast(keep)))
        pending = String(pending.suffix(keep))
    }

    private func take(_ text: String) {
        if text.isEmpty { return }
        sincePrompt += text
        lineBuf += text
        var parts = lineBuf.components(separatedBy: "\n")
        lineBuf = parts.removeLast()
        for p in parts { handleLine(p) }
    }

    private func handleLine(_ raw: String) {
        var line = ANSI_RX.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
        // (\r: la línea se ha vuelto a escribir, como las barras de las descargas: se queda lo último)
        let pieces = line.components(separatedBy: "\r").filter { !$0.isEmpty }
        line = pieces.last ?? ""
        if let m = FIN_RX.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let r = Range(m.range(at: 1), in: line) {
            exitCode = Int32(line[r])
            // La marca la escribe bash al acabar: ha terminado aunque script siga abierto (un servicio que
            // haya arrancado puede seguir con su terminal)
            if !finSeen {
                finSeen = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.finish(0) }
            }
            return
        }
        if line.hasPrefix("NEXUM-PASO|") {
            let f = line.components(separatedBy: "|")
            if f.count >= 3, let p = Int(f[1].trimmingCharacters(in: .whitespaces)) {
                step(min(max(p, 0), 100), f[2...].joined(separator: "|"))
            }
            return
        }
        if line.hasPrefix("NEXUM-PREGUNTA|") {
            let f = line.components(separatedBy: "|")
            ask(f.count > 1 ? f[1] : "", f.count > 2 ? f[2...].joined(separator: "|") : "")
            return
        }
        log += line + "\n"
        let t = line.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { lastLine = t }
    }

    private func step(_ p: Int, _ text: String) {
        // (la barra no vuelve atrás)
        if p > percent { percent = p }
        stepText = text
        log += "» \(p) %  " + text + "\n"
        // («La 1.57.15 ya estaba instalada: se comprueba lo demás»: al acabar, lo de antes de los dos puntos)
        if text.lowercased().contains("ya estaba instalada") {
            alreadyInstalled = text.components(separatedBy: ":").first ?? text
        }
        refreshStep()
    }

    /// Una pregunta del script: la respuesta (s o n) va por la entrada
    private func ask(_ id: String, _ text: String) {
        guard id == "homebrew" else {
            log += "(pregunta desconocida: \(id); se responde que no)\n"
            input?.write("n\n".data(using: .utf8) ?? Data())
            return
        }
        modalOpen = true
        let a = NSAlert()
        a.messageText = "Hace falta Homebrew"
        a.informativeText = text.isEmpty ? "¿Instalar Homebrew (brew.sh) ahora?" : text
        a.addButton(withTitle: "Instalar Homebrew")
        a.addButton(withTitle: "Cancelar la instalación")
        if let i = appIcon { a.icon = i }
        NSApp.activate(ignoringOtherApps: true)
        let yes = a.runModal() == .alertFirstButtonReturn
        modalOpen = false
        log += "¿Instalar Homebrew? " + (yes ? "sí" : "no") + "\n"
        if !finished { input?.write((yes ? "s\n" : "n\n").data(using: .utf8) ?? Data()) }
        drainQueued()
    }

    // MARK: contraseña (como TaskRunner.askPassword y sudoAsking de la ventana)

    private func askPassword() {
        if modalOpen { return }
        let lower = sincePrompt.lowercased()
        let retry = prompts > 0 && (lower.contains("sorry") || lower.contains("lo siento")
            || lower.contains("incorrect") || lower.contains("try again"))
        prompts += 1
        sincePrompt = ""
        // La marca la puede escribir cualquier programa del script: la contraseña solo se envía si hay un
        // sudo de esta instalación esperando, con el eco de su terminal apagado
        guard sudoAsking() else {
            log += "\nAviso: se ha pedido la contraseña, pero no la pide sudo. No se ha enviado y se cancela la instalación.\n"
            cancel()
            return
        }
        modalOpen = true
        stepText = "Esperando la contraseña de administrador"
        refreshStep()
        let pass = passwordPanel(retry: retry)
        modalOpen = false
        if let pass = pass {
            // Mientras el panel estaba abierto, sudo ha podido dejar de esperar: se vuelve a comprobar
            guard !finished, sudoAsking() else {
                log += "\nAviso: sudo ya no esperaba la contraseña. No se ha enviado.\n"
                cancel()
                drainQueued()
                return
            }
            input?.write((pass + "\n").data(using: .utf8) ?? Data())
        } else {
            cancel()
        }
        drainQueued()
    }

    private func passwordPanel(retry: Bool) -> String? {
        let user = ENV["USER"] ?? NSUserName()
        let a = NSAlert()
        a.messageText = retry ? "La contraseña no es correcta" : "Contraseña de administrador"
        a.informativeText = (retry ? "Vuelve a escribirla. " : "") + "Para instalar " + APP_NAME + " en /Library/Nexum "
            + "hace falta la contraseña de «\(user)», la que usas para entrar en el Mac."
        a.addButton(withTitle: "Aceptar")
        a.addButton(withTitle: "Cancelar")
        if let i = appIcon { a.icon = i }
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Contraseña"
        a.accessoryView = field
        a.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        let ok = a.runModal() == .alertFirstButtonReturn
        let pass = field.stringValue
        field.stringValue = ""
        return ok ? pass : nil
    }

    /// ¿Hay un sudo de root de esta instalación (descendiente de su proceso) leyendo de su terminal? Es lo
    /// que hace al pedir la contraseña, con el eco apagado (si solo espera a la orden que ejecuta, no)
    private func sudoAsking() -> Bool {
        guard let root = proc?.processIdentifier else { return false }
        var children: [Int32: [Int32]] = [:]
        var info: [Int32: String] = [:]
        var ttys: [Int32: String] = [:]
        // Solo cuenta un sudo de root (el de verdad es setuid): un programa de tu usuario que se llame
        // sudo no vale
        for line in captureOutput("/bin/ps", ["-axo", "pid=,ppid=,uid=,tty=,comm="]).components(separatedBy: "\n") {
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            guard f.count >= 5, let pid = Int32(f[0]), let ppid = Int32(f[1]) else { continue }
            children[ppid, default: []].append(pid)
            ttys[pid] = String(f[3])
            let path = f[4...].joined(separator: " ")
            if f[2] == "0" && (path == "sudo" || path == "/usr/bin/sudo") {
                info[pid] = String(f[3])
            }
        }
        var stack = [root]
        var sudoPid: Int32? = nil
        var seen = Set<Int32>()
        while let p = stack.popLast() {
            guard !seen.contains(p) else { continue }
            seen.insert(p)
            for c in children[p] ?? [] {
                stack.append(c)
                if info[c] != nil { sudoPid = c }
            }
        }
        // Mientras pide la contraseña, sudo no tiene hijos: los tiene cuando ya está ejecutando la orden
        guard let pid = sudoPid, (children[pid] ?? []).isEmpty else { return false }
        // Y en la terminal de la instalación (la del bash que lanza script)
        guard let first = children[root]?.first, let taskTty = ttys[first], taskTty != "??",
              info[pid] == taskTty else { return false }
        // Con la terminal exclusiva, stty ya no puede abrirla; ps dice dónde espera el proceso: «ttyin»
        // es leyendo de la terminal. macOS suele dar «-» (sin dato): se acepta
        let wchan = captureOutput("/bin/ps", ["-o", "wchan=", "-p", String(pid)])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return wchan.isEmpty || wchan == "-" || wchan.hasPrefix("ttyin")
    }

    func cancel() {
        guard !finished, let p = proc else { return }
        cancelled = true
        // El script va en su propia sesión (la de la pseudoterminal): se para su grupo de procesos
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

    // MARK: al acabar

    private func finish(_ status: Int32) {
        if finished { return }
        finished = true
        clock?.invalidate()
        clock = nil
        outPipe?.fileHandleForReading.readabilityHandler = nil
        take(pending + queued)
        pending = ""
        queued = ""
        if !lineBuf.isEmpty {
            handleLine(lineBuf)
            lineBuf = ""
        }
        let rc = exitCode ?? status
        let ok = rc == 0 && !cancelled
        saveLog(cancelled ? "Cancelada" : (ok ? "Terminada bien" : "Ha fallado (código \(rc))"))
        if cancelled {
            showIdle("Se ha cancelado la instalación. Lo que ya estaba instalado no se ha tocado; puedes volver a "
                + "pulsar Instalar cuando quieras.")
        } else if ok {
            showDone()
        } else {
            var why = lastLine.hasPrefix("ERROR|") ? String(lastLine.dropFirst(6)) : lastLine
            if why.count > 300 { why = String(why.prefix(300)) + "…" }
            fail("No se ha podido terminar la instalación",
                 (why.isEmpty ? "" : why + "\n") + "Pulsa «Ver detalles» para ver qué ha pasado.")
        }
        if quitWhenDone { NSApp.terminate(nil) }
    }

    private func showDone() {
        phase = .done
        percent = 100
        titleLabel.stringValue = "Se ha finalizado la instalación"
        var text = ""
        if let a = alreadyInstalled { text = a + ". " }
        if SIMULATE {
            text += "Simulación: no se ha cambiado nada en el Mac."
        } else {
            text += "«" + APP_NAME + "» está en Launchpad y en ~/Applications, y en la terminal tienes la orden nexum."
        }
        var disk = ""
        if let v = volumeName() { disk = " «" + v + "»" }
        text += " Ya puedes expulsar el disco" + disk + "."
        textLabel.stringValue = text
        bar.isHidden = false
        bar.doubleValue = 100
        pctLabel.isHidden = false
        pctLabel.stringValue = "100 %"
        stepLabel.stringValue = "Terminado   ·   Tiempo total: " + fmtClock(Int(Date().timeIntervalSince(started)))
        mainButton.title = "Abrir " + APP_NAME
        mainButton.isHidden = false
        mainButton.isEnabled = FileManager.default.fileExists(atPath: APP_BUNDLE)
        otherButton.title = "Cerrar"
        otherButton.isHidden = false
        detailsButton.isHidden = false
        _ = NSApp.requestUserAttention(.informationalRequest)
    }

    private func fail(_ title: String, _ text: String) {
        phase = .failed
        titleLabel.stringValue = title
        textLabel.stringValue = text
        bar.isHidden = log.isEmpty
        pctLabel.isHidden = log.isEmpty
        stepLabel.stringValue = log.isEmpty ? "" : ("Se ha parado en: " + (stepText.isEmpty ? "el principio" : stepText))
        mainButton.title = "Ver detalles"
        mainButton.isHidden = log.isEmpty
        mainButton.isEnabled = true
        otherButton.title = "Cerrar"
        otherButton.isHidden = false
        detailsButton.isHidden = true
        _ = NSApp.requestUserAttention(.criticalRequest)
    }

    /// Abre la aplicación de ~/Applications (en simulación, su ejecutable con LVM_SIMULAR=1, como el script)
    private func openApp() {
        if SIMULATE {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: APP_BUNDLE + "/Contents/MacOS/lvm-app")
            var env = ENV
            env["LVM_SIMULAR"] = "1"
            p.environment = env
            try? p.run()
        } else {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: APP_BUNDLE),
                                               configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
    }

    /// La salida entera, en ~/Library/Logs/Nexum/instalador-<fecha>.log (solo tuyo; sin seguir enlaces).
    /// La contraseña no sale: sudo la lee con el eco apagado y no pasa por la salida
    private func saveLog(_ result: String) {
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: LOGS_DIR),
           (attrs[.type] as? FileAttributeType) == .typeSymbolicLink { return }
        do {
            try fm.createDirectory(atPath: LOGS_DIR, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            return
        }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let path = LOGS_DIR + "/instalador-" + f.string(from: started) + ".log"
        let shown = DateFormatter()
        shown.dateFormat = "dd/MM/yyyy HH:mm:ss"
        let head = [INSTALLER_NAME + (VERSION.isEmpty ? "" : " " + VERSION),
                    "Orden: bash " + SCRIPT + (SIMULATE ? " --simular" : "") + " instalar-gestor",
                    "Fecha: " + shown.string(from: started),
                    "Duración: " + fmtClock(Int(Date().timeIntervalSince(started))),
                    "Resultado: " + result].joined(separator: "\n")
        let text = head + "\n" + String(repeating: "=", count: 72) + "\n" + log
        let fd = Darwin.open(path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { return }
        _ = fchmod(fd, mode_t(0o600))
        let h = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        h.write(Data(text.utf8))
        logPath = path
    }

    /// La salida completa, desplazable, con «Copiar» y «Mostrar el registro»
    @objc func showDetails() {
        let a = NSAlert()
        a.messageText = "Detalles de la instalación"
        a.informativeText = logPath.map { "Registro: " + $0 } ?? "Lo que ha escrito el instalador hasta ahora."
        a.addButton(withTitle: "Cerrar")
        a.addButton(withTitle: "Copiar")
        if logPath != nil { a.addButton(withTitle: "Mostrar el registro") }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 720, height: 420))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.string = log.isEmpty ? "(sin salida)" : log
        tv.autoresizingMask = [.width]
        scroll.documentView = tv
        a.accessoryView = scroll
        tv.scrollToEndOfDocument(nil)
        let r = a.runModal()
        if r == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(log, forType: .string)
        } else if r == .alertThirdButtonReturn, let p = logPath {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let installer = Installer()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Sin depuradores (como la ventana de Nexum): la contraseña de administrador pasa por la memoria del
        // instalador. ptrace no está en el módulo Darwin de Swift: se busca con dlsym (RTLD_DEFAULT es -2 en
        // macOS). 31 es PT_DENY_ATTACH
        typealias Ptrace = @convention(c) (Int32, Int32, UnsafeMutableRawPointer?, Int32) -> Int32
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "ptrace") {
            _ = unsafeBitCast(sym, to: Ptrace.self)(31, 0, nil, 0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) { installer.start(self) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { return installer.shouldClose() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { return installer.shouldTerminate() }
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.regular)
app.run()
