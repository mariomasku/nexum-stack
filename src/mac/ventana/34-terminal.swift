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
    /// Las columnas y filas que caben en la caja de la terminal (las que se le dicen a la pseudoterminal: con
    /// otras, zsh y ls cortan las líneas donde no es y el prompt sale fuera de su sitio)
    private var cols: UInt16 = 120
    private var rows: UInt16 = 20
    /// «Terminal nueva»: la carpeta en la que abrir la nueva cuando se cierre la de ahora
    private var restartIn: String? = nil

    init() {
        view.send = { [weak self] d in self?.write(d) }
        view.onSize = { [weak self] c, r in self?.resize(cols: c, rows: r) }
    }

    /// Cierra la de ahora y, cuando se ha cerrado, abre otra en cwd (sin esperar, la nueva no se abría:
    /// la de ahora aún estaba en marcha)
    func restart(cwd: String) -> Bool {
        guard pid > 0 else { return start(cwd: cwd) }
        restartIn = cwd
        stop()
        return true
    }

    /// El tamaño de la caja ha cambiado: se le dice a la pseudoterminal (y esta avisa a la shell con SIGWINCH)
    func resize(cols c: Int, rows r: Int) {
        let nc = UInt16(Swift.max(20, Swift.min(c, 1000)))
        let nr = UInt16(Swift.max(4, Swift.min(r, 500)))
        if nc == cols && nr == rows { return }
        cols = nc
        rows = nr
        guard master >= 0 else { return }
        var ws = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, UInt(0x80087467), &ws)
    }

    func start(cwd: String) -> Bool {
        guard pid == 0 else { return true }
        let m = posix_openpt(O_RDWR | O_NOCTTY)
        guard m >= 0 else { return false }
        guard grantpt(m) == 0, unlockpt(m) == 0, let name = ptsname(m) else { close(m); return false }
        let slave = String(cString: name)
        var ws = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
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
        // (el «dumb» con clear: `clear` y Ctrl+L borran la terminal; con el del sistema no hacían nada)
        if let ti = termInfoDir() { env["TERMINFO"] = ti }
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
        guard pid > 0 else { return }
        let p = pid
        kill(p, SIGHUP)
        // (si no se cierra con SIGHUP, a la fuerza)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if let s = self, s.pid == p { kill(p, SIGKILL) }
        }
    }

    private func exited() {
        source?.cancel()
        source = nil
        if master >= 0 { close(master) }
        master = -1
        pid = 0
        if let cwd = restartIn {
            restartIn = nil
            if start(cwd: cwd) { return }
        }
        onExit?()
    }
}

/// Un «dumb» como el del sistema (am, cols#80, bel, cr, cud1, ind) y, además, clear (\e[H\e[2J), compilado
/// como lo deja tic (el formato clásico de terminfo), en una carpeta temporal: con TERMINFO apuntando a
/// ella, `clear` y Ctrl+L borran la terminal y TERM sigue siendo «dumb» para todo lo demás
func termInfoDir() -> String? {
    let dir = NSTemporaryDirectory() + "nexum-terminfo"
    var b: [UInt8] = []
    func short(_ v: Int) {
        let u = UInt16(bitPattern: Int16(v))
        b.append(UInt8(u & 0xFF))
        b.append(UInt8(u >> 8))
    }
    let names: [UInt8] = Array("dumb|80-column dumb tty".utf8) + [0]
    // (su número en la lista de terminfo: bel 1, cr 2, clear 5, cud1 11, ind 129)
    let strs: [(Int, [UInt8])] = [(1, [7]), (2, [13]), (5, Array("\u{1b}[H\u{1b}[2J".utf8)), (11, [10]), (129, [10])]
    var table: [UInt8] = []
    var offs = [Int](repeating: -1, count: 130)
    for (i, s) in strs {
        offs[i] = table.count
        table += s + [0]
    }
    short(0o432)
    short(names.count)
    short(2)
    short(1)
    short(offs.count)
    short(table.count)
    b += names
    b += [0, 1]
    if b.count % 2 == 1 { b.append(0) }
    short(80)
    for o in offs { short(o) }
    b += table
    // (en el Mac, la carpeta de cada letra va en hexadecimal: «64»; «d», por si acaso)
    for sub in ["64", "d"] {
        let d = dir + "/" + sub
        do {
            try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
            try Data(b).write(to: URL(fileURLWithPath: d + "/dumb"))
        } catch {
            return nil
        }
    }
    return dir
}

/// El texto de la terminal: enseña lo que sale (sin los códigos de color ni de cursor) y manda lo que
/// se teclea a la pseudoterminal
final class TermTextView: NSTextView {
    var send: ((Data) -> Void)?
    /// Las columnas y filas que caben (al cambiar el tamaño de la caja)
    var onSize: ((Int, Int) -> Void)?
    private var pending: [UInt8] = []
    private let font0 = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private let fg = NSColor(calibratedRed: 0xD7 / 255.0, green: 0xDE / 255.0, blue: 0xE6 / 255.0, alpha: 1)
    /// El ancho de una letra y el alto de una línea (la letra es de ancho fijo)
    private lazy var charW: CGFloat = ("M" as NSString).size(withAttributes: [.font: font0]).width
    private lazy var lineH: CGFloat = NSLayoutManager().defaultLineHeight(for: font0)
    /// Las columnas de la caja: una línea más larga sigue en la siguiente, como en cualquier terminal
    private var cols = 120
    private var rows = 20
    /// Dónde se ha dibujado el cursor (para borrarlo al moverse)
    private var lastCaret = NSRect.zero

    // (los códigos que sí se entienden, cambiados antes por un carácter propio: borrar la pantalla y
    // borrar hasta el final de la línea)
    private static let CLEAR_MARK: Character = "\u{E000}"
    private static let EOL_MARK: Character = "\u{E001}"

    override var acceptsFirstResponder: Bool { return true }

    func reset() {
        pending = []
        line = []
        col = 0
        lineStart = 0
        textStorage?.setAttributedString(NSAttributedString(string: ""))
        refreshCaret()
    }

    /// Las columnas y filas que caben en lo que se ve de la caja (size: el de la parte visible)
    func fit(_ size: NSSize) {
        let padX = (textContainer?.lineFragmentPadding ?? 5) * 2 + textContainerInset.width * 2
        let c = Swift.max(20, Int(floor((size.width - padX) / Swift.max(1, charW))))
        let r = Swift.max(4, Int(floor((size.height - textContainerInset.height * 2) / Swift.max(1, lineH))))
        if c == cols && r == rows { return }
        cols = c
        rows = r
        onSize?(c, r)
        refreshCaret()
    }

    /// ⌘K (como en Terminal): borra lo de arriba y deja la línea de ahora
    func clearScrollback() {
        guard let ts = textStorage, lineStart > 0 else { return }
        ts.deleteCharacters(in: NSRange(location: 0, length: Swift.min(lineStart, ts.length)))
        lineStart = 0
        needsDisplay = true
        refreshCaret()
    }

    // MARK: el cursor

    /// Un bloque donde está el cursor de la shell (lleno con el foco, solo el borde sin él). El de
    /// NSTextView no sirve: va donde se pulsa con el ratón, no donde escribe la shell
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let r = caretRect() else { return }
        lastCaret = r
        let focused = window?.firstResponder === self && window?.isKeyWindow == true
        if focused {
            fg.withAlphaComponent(0.55).setFill()
            NSBezierPath(rect: r).fill()
        } else {
            fg.withAlphaComponent(0.55).setStroke()
            NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        refreshCaret()
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        refreshCaret()
        return ok
    }

    /// Vuelve a dibujar el cursor: donde estaba y donde está
    private func refreshCaret() {
        setNeedsDisplay(lastCaret.insetBy(dx: -2, dy: -2))
        if let r = caretRect() { setNeedsDisplay(r.insetBy(dx: -2, dy: -2)) }
    }

    /// Dónde está el cursor: en la última línea, en su columna (pasado el final del texto, los espacios
    /// que no se guardan cuentan igual)
    private func caretRect() -> NSRect? {
        guard let lm = layoutManager, let tc = textContainer, let ts = textStorage else { return nil }
        let tail = trimmed(line)
        let shown = Swift.min(col, tail.count)
        let idx = Swift.min(ts.length, lineStart + (String(tail.prefix(shown)) as NSString).length)
        let extra = CGFloat(Swift.max(0, Swift.min(col, cols - 1) - shown)) * charW
        lm.ensureLayout(for: tc)
        var x: CGFloat = tc.lineFragmentPadding
        var y: CGFloat = 0
        var h: CGFloat = lineH
        if ts.length == 0 {
            // (vacía: arriba del todo)
        } else if idx < ts.length {
            let g = lm.glyphIndexForCharacter(at: idx)
            let frag = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
            x = frag.minX + lm.location(forGlyphAt: g).x
            y = frag.minY
            h = frag.height
        } else if (ts.string as NSString).character(at: ts.length - 1) == 10 {
            // (la línea de ahora, vacía: la de después del último salto de línea)
            let frag = lm.extraLineFragmentRect
            x = frag.minX + tc.lineFragmentPadding
            y = frag.minY
            if frag.height > 0 { h = frag.height }
        } else {
            let g = lm.glyphIndexForCharacter(at: ts.length - 1)
            let r = lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc)
            x = r.maxX
            y = r.minY
            h = r.height
        }
        let o = textContainerOrigin
        return NSRect(x: o.x + x + extra, y: o.y + y, width: charW, height: h)
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
        case "k": clearScrollback(); return true
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
        // Lo que se entiende (lo demás se quita): borrar la pantalla (\e[H\e[2J de `clear` y Ctrl+L, \e[3J,
        // o ^L) y borrar hasta el final de la línea (\e[K). Antes de quitar los códigos: si no, ^L se
        // quedaba como una letra más y el cursor de la shell, una columna más allá de donde se veía
        text = text.replacingOccurrences(of: "\u{1b}\\[[0-9;]*H\u{1b}\\[[0-9]?J|\u{1b}\\[[23]J|\u{0C}",
                                         with: String(TermTextView.CLEAR_MARK), options: .regularExpression)
        text = text.replacingOccurrences(of: "\u{1b}\\[0?K", with: String(TermTextView.EOL_MARK), options: .regularExpression)
        text = text.replacingOccurrences(of: "\u{1b}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\u{1b}[()][0-9A-Za-z]|\u{1b}[=>78]", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{07}", with: "")
        guard let ts = textStorage else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: font0, .foregroundColor: fg]
        // La línea de ahora se lleva aparte, con su cursor: \r vuelve al principio y lo que sigue escribe
        // encima (zsh, antes del prompt, pone «%» y espacios hasta el borde y vuelve con \r: sin esto, el
        // prompt salía a la derecha); \b retrocede. Al acabar, solo se cambia esa última línea
        if lineStart > ts.length { lineStart = ts.length }
        var done = ""
        // (borrada la pantalla: se cambia todo el texto, no solo la última línea)
        var wipe = false
        for ch in text {
            if ch == "\n" {
                done += trimmed(line) + "\n"
                line = []
                col = 0
            } else if ch == "\r" {
                col = 0
            } else if ch == "\u{08}" {
                col = max(0, col - 1)
            } else if ch == TermTextView.CLEAR_MARK {
                wipe = true
                done = ""
                line = []
                col = 0
            } else if ch == TermTextView.EOL_MARK {
                if col < line.count { line.removeSubrange(col...) }
            } else if ch == "\t" {
                // (al siguiente tope, cada 8 columnas, sin escribir nada)
                col = Swift.min(cols - 1, (col / 8 + 1) * 8)
            } else {
                // (en la última columna, la letra siguiente va a la línea de abajo)
                if col >= cols {
                    done += trimmed(line) + "\n"
                    line = []
                    col = 0
                }
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
        let from = wipe ? 0 : lineStart
        ts.replaceCharacters(in: NSRange(location: from, length: ts.length - from),
                             with: NSAttributedString(string: done + tail, attributes: attrs))
        lineStart = ts.length - (tail as NSString).length
        // (como mucho las últimas 200.000 letras)
        if ts.length > 250_000 {
            let cut = ts.length - 200_000
            ts.deleteCharacters(in: NSRange(location: 0, length: cut))
            lineStart = max(0, lineStart - cut)
        }
        if wipe { needsDisplay = true }
        scrollToEndOfDocument(nil)
        refreshCaret()
    }
}

/// La caja de la terminal: al cambiar de tamaño (al arrastrar su borde o la ventana) dice cuántas
/// columnas y filas caben y, si se veía el final, lo sigue enseñando
final class TermScrollView: NSScrollView {
    var onTile: ((NSSize) -> Void)?
    private var lastSize = NSSize.zero

    override func tile() {
        let atEnd: Bool = {
            guard let d = documentView else { return true }
            return contentView.bounds.maxY >= d.frame.height - 4
        }()
        super.tile()
        let s = contentSize
        guard s != lastSize, s.width > 0, s.height > 0 else { return }
        lastSize = s
        onTile?(s)
        if atEnd {
            DispatchQueue.main.async { [weak self] in self?.documentView?.scrollToEndOfDocument(nil) }
        }
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
        let sv = TermScrollView()
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
        sv.onTile = { [weak tv] size in tv?.fit(size) }
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
