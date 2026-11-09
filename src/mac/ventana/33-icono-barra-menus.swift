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
