// MARK: - Icono en la barra de menús (junto al reloj)

/// «no» si se ha quitado en Configuración (sin el fichero, puesto)
let TRAY_FILE = LOG_DIR + "/ventana-bandeja"

func trayWanted() -> Bool {
    let s = (try? String(contentsOfFile: TRAY_FILE, encoding: .utf8)) ?? ""
    return s.trimmingCharacters(in: .whitespacesAndNewlines) != "no"
}

// MARK: - Abrir al iniciar sesión (Configuración, Programa)

/// Un LaunchAgent tuyo que abre la aplicación de ~/Applications (la que crea el gestor) al entrar en la
/// sesión, con --al-iniciar: con el icono de la barra de menús puesto, arranca sin ventana, solo en él.
/// Se carga en el próximo inicio de sesión (no se llama a launchctl)
let LOGIN_LABEL = "io.github.mariomasku.nexum.inicio"
let LOGIN_ARG = "--al-iniciar"
let LOGIN_PLIST = NSHomeDirectory() + "/Library/LaunchAgents/" + LOGIN_LABEL + ".plist"
let APP_BUNDLE_PATH = NSHomeDirectory() + "/Applications/Nexum Dev Stack.app"

/// Arrancada por el LaunchAgent con el icono puesto: la primera ventana se esconde nada más salir
var startHidden = false

/// El plist de inicio es nuestro: un fichero normal (no un enlace) con nuestro Label
func loginItemOurs() -> Bool {
    let fd = open(LOGIN_PLIST, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard fd >= 0 else { return false }
    var st = stat()
    guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_size < 65536 else {
        close(fd)
        return false
    }
    let data = FileHandle(fileDescriptor: fd, closeOnDealloc: true).readDataToEndOfFile()
    guard let p = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
        return false
    }
    return (p["Label"] as? String) == LOGIN_LABEL
}

/// Pone el plist de inicio (644, sin seguir enlaces, en una ~/Library/LaunchAgents tuya). nil si ha ido bien;
/// si no, el motivo
func loginItemWrite() -> String? {
    let dir = (LOGIN_PLIST as NSString).deletingLastPathComponent
    var st = stat()
    if lstat(dir, &st) != 0 {
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o755])
        } catch {
            return error.localizedDescription
        }
    } else if (st.st_mode & S_IFMT) != S_IFDIR || st.st_uid != getuid() {
        return "~/Library/LaunchAgents no es una carpeta tuya: no se escribe nada en ella."
    }
    let plist: [String: Any] = [
        "Label": LOGIN_LABEL,
        "ProgramArguments": ["/usr/bin/open", "-g", "-a", APP_BUNDLE_PATH, "--args", LOGIN_ARG],
        "RunAtLoad": true,
    ]
    guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
        return "No se ha podido preparar el fichero."
    }
    let fd = open(LOGIN_PLIST, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, mode_t(0o644))
    guard fd >= 0 else { return String(cString: strerror(errno)) }
    defer { close(fd) }
    _ = fchmod(fd, mode_t(0o644))
    let wrote = data.withUnsafeBytes { buf -> Int in Darwin.write(fd, buf.baseAddress, buf.count) }
    return wrote == data.count ? nil : String(cString: strerror(errno))
}

/// Quita el plist de inicio, solo si es nuestro (un fichero normal con nuestro Label). nil si ha ido bien
func loginItemRemove() -> String? {
    var st = stat()
    guard lstat(LOGIN_PLIST, &st) == 0 else { return nil }
    guard loginItemOurs() else { return "\(LOGIN_PLIST) no es de Nexum Dev Stack: no se borra." }
    return unlink(LOGIN_PLIST) == 0 ? nil : String(cString: strerror(errno))
}

/// Dentro de la ventana: si se ha arrancado sin ventana (startHidden), la esconde en cuanto está en pantalla
/// (transparente hasta entonces, sin parpadeo). Vuelve como al cerrarla con el icono: desde su menú o el Dock
struct StartHiddenWindow: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window, startHidden else { return }
            startHidden = false
            w.alphaValue = 0
            Probe.hide(w, 40)
        }

        /// (SwiftUI la pone delante justo después: se espera a que esté a la vista, como mucho 2 s)
        static func hide(_ w: NSWindow, _ tries: Int) {
            if w.isVisible || tries <= 0 {
                w.orderOut(nil)
                w.alphaValue = 1
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Probe.hide(w, tries - 1) }
        }
    }

    func makeNSView(context: Context) -> NSView { return Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}
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
        if let web = AppModel.current?.projects?.webURL, !web.isEmpty { openURL(web) }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}
