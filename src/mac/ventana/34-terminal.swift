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
