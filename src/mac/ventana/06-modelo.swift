final class AppModel: ObservableObject {
    @Published var data: AppData? = nil
    @Published var loadError: String? = nil
    @Published var branches: [Branch]? = nil
    @Published var branchesError: String? = nil
    /// Versión -> [php, fecha de publicación en php.net] (gui-fechas: llega después)
    @Published var phpDates: [String: [String]] = [:]
    /// Lo que se va a instalar: ramas (8.4, su último parche) y parches concretos (8.3.10)
    @Published var selected: Set<String> = []
    /// Otro parche concreto: la rama elegida y sus parches (nil mientras se consultan)
    @Published var patchBranch = ""
    @Published var patches: [PatchItem]? = nil
    @Published var patchesError: String? = nil
    @Published var expanded: Set<String> = []
    /// Apartados plegados (Instaladas, Instalar): se guardan en FOLDED_FILE
    @Published var folded: Set<String> = Set(((try? String(contentsOfFile: FOLDED_FILE, encoding: .utf8)) ?? "")
        .split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    /// La tarea sigue sin su hoja («Seguir en segundo plano»): al lado del visor, su aviso la trae de vuelta
    @Published var taskHidden = false
    /// Apariencia (Configuración): se guarda al cambiarla; si se oculta el apartado abierto, a Proyectos
    @Published var look = loadLook() {
        didSet {
            guard look != oldValue else { return }
            saveLook(look)
            if look.ocultos.contains(tab) { openTab("proyectos") }
        }
    }
    @Published var task: TaskRunner? = nil {
        // (si se cerró la ventana con una tarea en marcha, la aplicación se cierra al acabar la tarea)
        didSet {
            if task == nil && taskHidden { taskHidden = false }
            if task == nil && oldValue != nil && !TrayIcon.shared.on
                && !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }
    }
    /// El modelo de la aplicación, para el delegado (que no lo ve de otro modo)
    static weak var current: AppModel?
    @Published var toastText: String? = nil
    // Formulario «Subir o actualizar una base de datos»
    @Published var impFile: String? = nil
    @Published var impDb: String? = nil {
        didSet { if impDb != oldValue { refreshImpProjects() } }
    }
    // Proyecto de la base que se sube: queda como su base y, si es un WordPress, su wp-config.php la usa
    @Published var impProject: String? = nil
    @Published var impProjects: [String] = []
    // Tipo de cada carpeta: ps (tienda PrestaShop) o wp (WordPress)
    var impKind: [String: String] = [:]
    // Buscador de bases de datos y hoja «Cargar proyecto»
    @Published var dbQuery = ""
    @Published var projectReq: ProjectRequest? = nil
    // Dominios de los vhosts (pestaña Hosts): nil hasta leerlos
    @Published var hosts: [HostEntry]? = nil
    /// El vhost de los proyectos (web.local) que no lleva a 127.0.0.1: (nombre, dirección de ahora)
    @Published var hostsLinkFix: [[String]] = []
    // Apache, MariaDB y el FTP de la versión montada (pestaña Servicios): nil hasta leerlos
    @Published var services: [Service]? = nil
    // Proyectos de htdocs y búsqueda del bloque «Cargar proyecto» (Versiones)
    @Published var projects: ProjectsData? = nil
    @Published var projQuery = ""
    // Montar nuevo proyecto (asistente de tres pasos dentro de Cargar proyecto)
    @Published var npOpen = false
    @Published var npStep = 1
    /// Asistente: los repositorios de GitHub (los de la pestaña Repositorios), lo que se busca, el elegido, y
    /// el dominio de producción (falsearlo o no)
    /// Actualizar proyecto: si se ve su diálogo, el proyecto, la BBDD, el código, qué hacer con la carpeta
    /// (fusionar o sobrescribir) y lo que no vale de lo arrastrado
    @Published var upShown = false
    @Published var upFolder = ""
    @Published var upSql = ""
    @Published var upCode = ""
    @Published var upMode = "fusionar"
    @Published var upDb = ""
    var upDbKnown = false
    @Published var upSqlError = ""
    @Published var upCodeError = ""
    @Published var npRepos: [RepoItem] = []
    /// ¿Ya se ha leído alguna vez?, ¿se está preguntando a GitHub? y cuándo contestó por última vez
    var npReposLoaded = false
    var npReposBusy = false
    var npReposWhen = Date.distantPast
    @Published var npRepoQuery = ""
    @Published var npRepoNote = ""
    @Published var npFake = false
    @Published var npDomain = ""
    @Published var npUrl = ""
    @Published var npFolder = ""
    @Published var npFolderAuto = true
    @Published var npVersion = ""
    @Published var npDb = ""
    @Published var npFile: String? = nil
    // Formulario «Nuevo proyecto con dominio falseado»
    @Published var newDomain = ""
    @Published var newFolder = ""
    @Published var newDb = ""
    // Ventana: apartado de la barra lateral, proyecto elegido en Proyectos (se ve arriba) y su filtro
    @Published var tab = "proyectos"
    /// Apartado elegido en Configuración (su clave de ToolsView.sections)
    @Published var toolsSection = "general"
    /// Sube cada vez que una tarea empieza o acaba: Configuración, General, vuelve a leer el registro de tareas
    @Published var taskLogsChanged = 0
    @Published var selProject: String? = nil
    @Published var projKind = "all"
    // Bases de datos: «solo la versión activa» (la activa se ve desplegada al abrir) y lo que ocupan
    // las copias de ~/nexum-backups ([bytes, ficheros])
    @Published var dbOnlyActive = false
    @Published var backups: [Int64]? = nil
    /// Copias de los ficheros que cambia el programa por su cuenta (Configuración, Carpetas; copias-ficheros si|no)
    @Published var copiesFiles = FileManager.default.fileExists(atPath: COPIES_FILES_FLAG)
    /// Configuración, Limpieza: las casillas que se han cambiado (clave → marcada); las demás, como vienen
    /// en CLEAN_ITEMS. Se recuerdan mientras la ventana está abierta, como en Linux
    @Published var cleanMarks: [String: Bool] = [:]
    /// Lo que ocupa cada BBDD («versión|base» → [bytes, cuándo se midió]; gui-bbdd-tamanos)
    @Published var dbSizes: [String: [Int64]] = [:]
    /// Lo que ocupa cada proyecto en el disco: carpeta → [bytes, cuándo se midió]
    @Published var projectSizes: [String: [Int64]] = [:]
    var projSizesBusy = false
    var projSizesAt = Date.distantPast
    // Docker (gui-docker): nil hasta leerlo. Uso de CPU y memoria, vista, filtros y proyectos plegados
    @Published var docker: DockerData? = nil
    @Published var dkStats: DockerStats? = nil
    @Published var dkView = "cont"
    @Published var dkQuery = ""
    @Published var dkOnlyUp = false
    /// El proyecto de Docker desplegado (desde la 1.39.5, plegados al entrar y solo uno a la vez)
    @Published var dkOpen: Set<String> = []
    @Published var dkForm = DockerForm()
    // Ventana encima de la página (Componentes, Instalar versión, Proyecto en Docker)
    @Published var panel: Panel? = nil
    // Tema de la ventana elegido en el menú (nil: el del Mac)
    @Published var dark: Bool? = nil
    /// Correos sin leer en Mailpit (nil: parado o sin saberlo)
    @Published var mailUnread: Int? = nil
    /// Botones del visor de los proyectos (cuáles, en qué orden y cómo)
    @Published var visorConf = loadVisorConf()
    /// Lo que gastan Nexum y sus servicios (cada 3 s; nil hasta la primera lectura)
    @Published var usage: [String: UsagePart]? = nil
    var usageBusy = false
    /// El túnel de Cloudflare abierto, cloudflared (I|instalado|versión|la del programa) y su configuración
    @Published var tunnel: TunnelState? = nil
    @Published var tunnelInfo: [String]? = nil
    /// Lo que tiene un parche nuevo (componentes): nil mientras no se ha mirado
    @Published var components: ComponentsState? = nil
    /// Parches nuevos dejados para luego («Ahora no»): la lista de entonces; el aviso vuelve si cambia
    @Published var updatesIgnored = (try? String(contentsOfFile: IGNORED_UPDATES_FILE, encoding: .utf8)) ?? ""
    /// Los parches nuevos que van en los avisos de arriba (no si se han dejado para luego)
    var updatesPending: ComponentsState? {
        guard let c = components, !c.items.isEmpty, c.items.sorted().joined(separator: "\n") != updatesIgnored else { return nil }
        return c
    }

    func ignoreUpdates(_ c: ComponentsState) {
        let text = c.items.sorted().joined(separator: "\n")
        updatesIgnored = text
        if SIMULATE { return }
        try? FileManager.default.createDirectory(atPath: LOG_DIR, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? text.write(toFile: IGNORED_UPDATES_FILE, atomically: true, encoding: .utf8)
    }
    /// La terminal de abajo: a la vista o no (sigue abierta al esconderla), su alto y la sesión
    @Published var termOpen = false {
        didSet { if termOpen { termStart() } }
    }
    @Published var termHeight: CGFloat = 260
    @Published var termCwd = ""
    let term = TermSession()

    /// La carpeta del proyecto cargado (o la de los proyectos)
    /// Icono en la barra de menús (Configuración, Programa): con él, cerrar la ventana no cierra la aplicación
    @Published var trayOn = trayWanted()
    private var trayTicks = 0

    func setTray(_ on: Bool) {
        try? FileManager.default.createDirectory(atPath: LOG_DIR, withIntermediateDirectories: true)
        do {
            try (on ? "si\n" : "no\n").write(toFile: TRAY_FILE, atomically: true, encoding: .utf8)
        } catch {
            message("No se ha podido guardar", error.localizedDescription, error: true)
            return
        }
        trayOn = on
        TrayIcon.shared.show(on)
    }

    var termProject: String {
        // (gui-proyectos da la carpeta como la tiene el enlace de web.local: su nombre, dentro de los proyectos)
        var cur = projects?.current ?? ""
        if !cur.isEmpty && !cur.hasPrefix("/") { cur = (HTDOCS as NSString).appendingPathComponent(cur) }
        var dir: ObjCBool = false
        return !cur.isEmpty && FileManager.default.fileExists(atPath: cur, isDirectory: &dir) && dir.boolValue ? cur : HTDOCS
    }

    func termStart(restart: Bool = false) {
        let cwd = termProject
        term.onExit = { [weak self] in self?.termOpen = false }
        // (Terminal nueva: se cierra la de ahora y, cuando se ha cerrado, se abre la nueva aquí mismo)
        if restart && term.running {
            _ = term.restart(cwd: cwd)
            termCwd = cwd
            return
        }
        guard !term.running else { return }
        if term.start(cwd: cwd) {
            termCwd = cwd
        } else {
            termOpen = false
            message("No se ha podido abrir la terminal", "No se ha podido crear su pseudoterminal.", error: true)
        }
    }

    /// cd a la carpeta del proyecto cargado (escrito en la terminal, como si lo tecleara)
    func termCd() {
        let cwd = termProject
        let quoted = "'" + cwd.replacingOccurrences(of: "'", with: "'\\''") + "'"
        term.write(Data("cd \(quoted)\r".utf8))
        termCwd = cwd
    }

    /// Vaciar la caché DNS del sistema (escrito en la terminal: la contraseña de sudo se pide ahí)
    func termFlushDns() {
        term.write(Data("sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder\r".utf8))
    }
    /// Repositorios de GitHub (pestaña Repositorios) y la conexión (Configuración)
    @Published var repos: ReposData? = nil
    /// Proyectos de Node (pestaña Node)
    @Published var nodeItems: [NodeItem]? = nil
    @Published var reposAll = false
    @Published var reposLoading = false
    @Published var github: GitHubState? = nil
    /// Al cargar un proyecto, la página de Proyectos sube hasta el visor (cambia y WidePage se desliza)
    @Published var scrollTop = 0
    private var fastTimer: Timer? = nil
    private var mailPolling = false
    var impFolder: String? = nil
    var dbPwd: [String: String] = [:]
    private var toastWork: DispatchWorkItem? = nil
    private var sized = false
    private var timer: Timer? = nil

    var busy: Bool { return task != nil }

    /// Pliega o despliega un apartado y lo recuerda
    func setFolded(_ key: String, _ fold: Bool) {
        if fold { folded.insert(key) } else { folded.remove(key) }
        try? FileManager.default.createDirectory(atPath: LOG_DIR, withIntermediateDirectories: true)
        try? folded.sorted().map { $0 + "\n" }.joined().write(toFile: FOLDED_FILE, atomically: true, encoding: .utf8)
    }

    init() {
        AppModel.current = self
        reload(branches: true)
        // Los repositorios del buscador de Nuevo proyecto, ya cargados cuando se abra: los de la última
        // vez y, en cuanto la ventana ha cargado lo suyo, los de GitHub
        loadNpRepos(cache: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.loadNpRepos() }
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            // (sin ventana y con el icono de la barra de menús: solo lo que enseña su menú, cada minuto)
            if let self = self, !self.busy, TrayIcon.shared.on,
               !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
                self.trayTicks = (self.trayTicks + 1) % 3
                if self.trayTicks == 0 { runQuick(["gui-datos"]) { rc, out in self.onData(rc, out) } }
                return
            }
            // (con la ventana cerrada, la aplicacion sigue abierta: sin ventana no hace falta leer nada)
            guard let self = self, !self.busy, NSApp.isActive,
                  NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
            // (las cuatro en una sola orden: el script se lee una vez y no cuatro)
            runQuick(["gui-vuelta"]) { rc, out in self.onRound(rc, out) }
            if self.tab == "docker" { self.reloadDocker(stats: true) }
        }
        // (al volver a la ventana, los correos sin leer al momento)
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.pollMail() }
        // Lo que gastan Nexum y sus servicios (arriba) y el túnel abierto: cada 3 s, con la ventana a la vista
        fastTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self = self, NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
            self.usageTick()
        }
        usageTick()
        // Al abrir: si toca (el primer arranque del día y después cada UPDATE_EVERY), si hay una versión
        // nueva del programa (con los datos ya leídos: la versión actual)
        autoCheckUpdates()
    }

    func autoCheckUpdates() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self = self else { return }
            if self.data == nil || self.busy { self.autoCheckUpdates(); return }
            if updateCheckDue() {
                self.checkUpdates(auto: true)
                // (y los parches de los componentes, un poco después: sin juntarse con el aviso del programa)
                DispatchQueue.main.asyncAfter(deadline: .now() + 25) { self.autoCheckComponents() }
            }
        }
    }

    /// Lo que tiene un parche nuevo: cada versión de PHP (PHP, Apache, MariaDB, phpMyAdmin…), las
    /// imágenes de Docker, Mailpit y cloudflared
    func reloadComponents(_ then: ((ComponentsState) -> Void)? = nil) {
        runQuick(["componentes"]) { _, out in
            let c = parseComponents(out)
            self.components = c
            then?(c)
        }
    }

    /// Al abrir (cuando toca buscar una versión nueva del programa): si algo tiene un parche nuevo, se
    /// dice y se ofrece actualizarlo todo
    func autoCheckComponents() {
        reloadComponents { c in
            // (sin preguntar: el aviso de arriba lo dice, y se puede dejar para luego)
            if self.updatesPending != nil { self.toast("Hay parches nuevos: míralos en los avisos de arriba") }
        }
    }

    /// El visor de la bandeja, siempre el mismo: al cambiar de apartado no se pierde el correo abierto
    lazy var mailWeb = MailWebHost()
}
