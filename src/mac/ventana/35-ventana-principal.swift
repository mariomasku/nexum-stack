// MARK: - Ventana principal

/// Arriba, la barra con el visor de la versión montada; a la izquierda, los apartados (ENTORNO y
/// SISTEMA); a la derecha, el elegido
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
                // (con el cristal, la barra del visor sólida: azul oscuro con el tema oscuro y blanca con el claro)
                .background(model.look.cristal ? (scheme == .dark ? Color(red: 0.078, green: 0.129, blue: 0.239)
                                                                  : Color.white) : Color.clear)
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
            // (abajo, a lo ancho de la ventana, la barra de estado: a dónde apunta web.local)
            Divider()
            StatusBar()
        }
        // Todos los botones: con borde, la mano y el borde azul al pasar el ratón (como en Linux)
        .buttonStyle(PointerButtonStyle())
        .overlay(panel())
        .overlay(toastView(), alignment: .bottom)
        // (escondida en segundo plano, la hoja no se ve; la tarea sigue y su aviso está al lado del visor)
        .sheet(item: Binding(get: { model.taskHidden ? nil : model.task },
                             set: { t in if t == nil && !model.taskHidden { model.task = nil } })) { t in
            TaskView(task: t).environmentObject(model).buttonStyle(PointerButtonStyle())
        }
        // (Apariencia, cristal: el escritorio desenfocado detrás de la ventana)
        .background(GlassBackground(on: model.look.cristal))
        .onAppear { model.applyTheme() }
        // (abierta al iniciar sesión con el icono puesto: se esconde nada más salir)
        .background(StartHiddenWindow())
    }

    @ViewBuilder
    func detail() -> some View {
        switch model.tab {
        case "versiones": VersionsView()
        case "bbdd": DatabasesView()
        case "docker": DockerView()
        case "repos": ReposView()
        case "node": NodeView()
        case "nginx": NginxView()
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
        // (grande, con el logotipo de Nexum al principio y un borde con los colores de su icono; en forma de
        // píldora: los extremos redondos del todo y el centro recto)
        if let t = model.toastText {
            let shape = Capsule()
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
                Text(t).font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 30)
            .padding(.trailing, 36)
            .padding(.vertical, 12)
            .frame(maxWidth: 620)
            .background(shape.fill(Color(NSColor.windowBackgroundColor)))
            .overlay(shape.strokeBorder(LinearGradient(colors: NEXUM_COLORS, startPoint: .leading, endPoint: .trailing),
                                        lineWidth: 3))
            .shadow(color: Color.black.opacity(0.30), radius: 9, y: 4)
            .padding(.bottom, 24)
        }
    }
}

/// La barra de abajo: «web.local >>>>> proyecto» (los chevrones en verde, con su onda), «web.local >>>>>
/// dominio falseado · tienda.com» si el dominio del proyecto cargado está falseado o, sin proyecto cargado,
/// «web.local >>>>> sin enlace» (chevrones y texto en gris)
struct StatusBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let link = (model.projects?.link ?? "").isEmpty ? "web.local" : model.projects!.link
        let folder = loadedProjectFolder(model.projects?.current ?? "")
        // (con el dominio del proyecto falseado, se dice: sus visitas van a esta copia y no a la web real)
        let fakes = folder.map { f in model.projectHosts((f as NSString).lastPathComponent).filter { $0.fake }.map { $0.name } } ?? []
        let text = !fakes.isEmpty ? "dominio falseado · " + fakes.joined(separator: ", ")
            : folder.map { ($0 as NSString).lastPathComponent } ?? "sin enlace"
        let tip = folder.map { f in fakes.isEmpty ? f : "\(f), con \(fakes.joined(separator: ", ")) falseado: va a esta copia y no a la web real" }
            ?? "Ningún proyecto cargado: \(link) enseña una página vacía"
        HStack(spacing: 6) {
            Text(link)
            LinkChevrons(linked: folder != nil)
            Text(text)
                .foregroundColor(folder == nil ? .secondary : .primary)
                .lineLimit(1).truncationMode(.middle)
                .help(tip)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.035))
    }
}

/// Los chevrones de la barra de estado: enlazado, en verde, con una onda de luz que va de izquierda a derecha;
/// sin enlace, grises y quietos. El paso de uno a otro, fundido (como en Linux)
struct LinkChevrons: View {
    let linked: Bool
    @State private var from: Double = 0
    @State private var goal: Double = 0
    @State private var changed = Date.distantPast
    @State private var still = true
    static let count = 5, step: CGFloat = 9, period = 1.6, fade = 0.45
    static let dim = (0.10, 0.45, 0.25), bright = (0.19, 0.82, 0.35)

    func level(_ now: Date) -> Double {
        let k = min(1, max(0, now.timeIntervalSince(changed) / Self.fade))
        return from + (goal - from) * k
    }

    var body: some View {
        // (unos 30 dibujos por segundo bastan para la onda; quieto y sin enlace, no se dibuja más)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still && !linked)) { ctx in
            Canvas { g, size in
                let lv = level(ctx.date)
                let t = ctx.date.timeIntervalSinceReferenceDate
                for i in 0..<Self.count {
                    // (la onda: cada chevrón, algo después que el de su izquierda)
                    let wave = 0.5 + 0.5 * sin(2 * Double.pi * (t / Self.period - Double(i) / Double(Self.count)))
                    let r = Self.dim.0 + (Self.bright.0 - Self.dim.0) * wave
                    let gr = Self.dim.1 + (Self.bright.1 - Self.dim.1) * wave
                    let b = Self.dim.2 + (Self.bright.2 - Self.dim.2) * wave
                    let gray = Color.secondary.opacity(1 - lv)
                    let green = Color(red: r, green: gr, blue: b).opacity(lv * (0.55 + 0.45 * wave))
                    let x = 3 + CGFloat(i) * Self.step, y = size.height / 2
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y - 4.5))
                    path.addLine(to: CGPoint(x: x + 4.5, y: y))
                    path.addLine(to: CGPoint(x: x, y: y + 4.5))
                    let style = StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                    g.stroke(path, with: .color(gray), style: style)
                    g.stroke(path, with: .color(green), style: style)
                }
            }
        }
        .frame(width: CGFloat(Self.count - 1) * Self.step + 10, height: 14)
        .onAppear { from = linked ? 1 : 0; goal = from }
        .onChange(of: linked) { on in
            // (desde donde iba el fundido, hacia el nuevo)
            let now = Date()
            from = level(now)
            goal = on ? 1 : 0
            changed = now
            still = false
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.fade + 0.1) { still = true }
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
        // Abierta al iniciar sesión (el LaunchAgent, con --al-iniciar): con el icono de la barra de menús
        // puesto, sin ventana, solo el icono; sin él, la ventana de siempre
        startHidden = CommandLine.arguments.contains(LOGIN_ARG) && trayWanted()
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

/// Apariencia, tamaño: lo de dentro se coloca en una ventana 1/zoom más grande (o más pequeña) y se pinta a
/// escala, así todo (letras, márgenes, iconos) cambia a la vez y los clics van donde se ve. Al 100 %, tal cual
struct ZoomBox<Content: View>: View {
    let zoom: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if zoom == 1 {
            content()
        } else {
            GeometryReader { g in
                content()
                    .frame(width: g.size.width / zoom, height: g.size.height / zoom)
                    .scaleEffect(zoom, anchor: .topLeading)
            }
        }
    }
}

/// Apariencia, cristal: detrás de todo, el material de macOS que deja ver el escritorio desenfocado (lo
/// calcula el sistema con la tarjeta gráfica). La ventana deja de ser opaca mientras está puesto
struct GlassBackground: NSViewRepresentable {
    let on: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.isHidden = !on
        let apply = { [weak v] in
            guard let w = v?.window else { return }
            w.isOpaque = !on
            w.backgroundColor = on ? .clear : .windowBackgroundColor
        }
        if v.window != nil { apply() } else { DispatchQueue.main.async(execute: apply) }
    }
}

@main
struct GestorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var model = AppModel()

    // (lo primero, antes de que nada lea o cree LOG_DIR: ~/.lvm-instalador pasa a ~/.nexum)
    init() {
        settingsMigrate()
    }

    var body: some Scene {
        WindowGroup {
            // (Apariencia, tamaño: la ventana entera a escala; el mínimo, también)
            ZoomBox(zoom: CGFloat(model.look.zoom) / 100) {
                ContentView()
                    .environmentObject(model)
            }
            .frame(minWidth: model.minWindowWidth * CGFloat(model.look.zoom) / 100,
                   minHeight: 680 * CGFloat(model.look.zoom) / 100)
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
