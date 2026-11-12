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

    // (lo primero, antes de que nada lea o cree LOG_DIR: ~/.lvm-instalador pasa a ~/.nexum)
    init() {
        settingsMigrate()
    }

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
