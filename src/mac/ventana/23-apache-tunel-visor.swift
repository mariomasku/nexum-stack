// MARK: - Apache de Docker, túnel de Cloudflare, botones del visor y consumo (1.40)

/// El Apache de Docker (gui-docker, W): su dirección, sus puertos, su estado (marcha, parado o nuevo) y
/// si la dirección ya está en este Mac
struct DockerWeb: Equatable {
    var ip = "127.0.0.2", http = "80", https = "443", state = ""
    var ok = false
    /// Final de sus dominios (docker.local o, con el DNS comodín, docker.test) y si va el DNS
    var tld = "docker.local"
    var dns = false
}

/// Final de los dominios del Apache de Docker
func dockerTLD(_ k: DockerData?) -> String {
    return k?.web?.tld ?? "docker.local"
}

/// Dirección https de un dominio del Apache de Docker (con el puerto si no es el 443)
func dockerWebURL(_ k: DockerData?, _ domain: String) -> String {
    let port = k?.web?.https ?? "443"
    return "https://" + domain + (port == "443" ? "" : ":" + port)
}

/// Dominio de una versión de PHP de un proyecto del Apache de Docker (una tienda va con uno solo)
func dockerWebDomain(_ p: DockerProject, _ v: String, _ tld: String) -> String {
    if p.kind == "ps" { return p.slug + "." + tld }
    return p.slug + "-php" + v.replacingOccurrences(of: ".", with: "") + "." + tld
}

/// Contenedor de PHP de una versión de un proyecto del Apache de Docker
func dockerWebContainer(_ p: DockerProject, _ v: String) -> String {
    return "nexum-\(p.slug)-php" + v.replacingOccurrences(of: ".", with: "")
}

func copyText(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// Destino de las opciones de un menú hecho a mano (popMenu)
final class MenuTarget: NSObject {
    var actions: [() -> Void] = []
    @objc func run(_ sender: NSMenuItem) {
        if sender.tag >= 0 && sender.tag < actions.count { actions[sender.tag]() }
    }
}

/// Menú en el sitio del ratón: el botón que lo abre lleva un logotipo, y los menús de SwiftUI solo
/// enseñan texto e iconos del sistema
func popMenu(_ items: [(String, () -> Void)]) {
    let menu = NSMenu()
    let target = MenuTarget()
    for (i, it) in items.enumerated() {
        let m = NSMenuItem(title: it.0, action: #selector(MenuTarget.run(_:)), keyEquivalent: "")
        m.target = target
        m.tag = i
        menu.addItem(m)
        target.actions.append(it.1)
    }
    menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    withExtendedLifetime(target) {}
}

// MARK: túnel de Cloudflare

let TUNNEL_DIR = LOG_DIR + "/tunel"
let CLOUDFLARE = hexColor(0xF38020)

/// El túnel abierto (tunel-abrir): su dirección, la web de este Mac que enseña, su carpeta, su hora de
/// cierre y lo suyo: su contraseña, sus horas y si bloquea el panel de administración
struct TunnelState: Equatable {
    let url, target, folder: String
    let expires: Int
    var password = ""
    var hours = 2
    var block = true
}

/// El túnel abierto, o nil si no hay ninguno, si su proceso ya no está o si ha pasado su hora
func readTunnel() -> TunnelState? {
    guard let data = FileManager.default.contents(atPath: TUNNEL_DIR + "/estado"),
          let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let pid = o["pid"] as? Int, let url = o["url"] as? String, let target = o["target"] as? String else { return nil }
    let expires = o["expires"] as? Int ?? 0
    guard pid > 1, kill(pid_t(pid), 0) == 0, expires > Int(Date().timeIntervalSince1970) else { return nil }
    return TunnelState(url: url, target: target, folder: o["folder"] as? String ?? "", expires: expires,
                       password: o["password"] as? String ?? "", hours: o["hours"] as? Int ?? 2,
                       block: (o["admin"] as? String ?? "bloquear") != "permitir")
}

/// Hora (HH:mm) de un instante en segundos
func clockTime(_ t: Int) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f.string(from: Date(timeIntervalSince1970: TimeInterval(t)))
}

// MARK: botones del visor

/// Botones del visor de un proyecto (el cargado y los de Docker) que se pueden ocultar y ordenar: clave y
/// nombre. ⋮ (el último) y los propios de Docker (Versiones de PHP, Arrancar o Parar) se ven siempre. Unlink es solo
/// del proyecto cargado, y Correo y Terminal, del visor de arriba (en el clásico siguen en la cabecera)
let VISOR_BUTTONS: [(String, String)] = [("web", "Abrir web"), ("vscode", "VS Code"), ("repo", "Repositorio"),
                                         ("pma", "phpMyAdmin"),
                                         ("panel", "Panel"), ("docker", "Docker"), ("compartir", "Compartir"),
                                         ("log", "Log"), ("actualizar", "Actualizar"),
                                         ("imagenes", "Imágenes de producción"),
                                         ("unlink", "Unlink"), ("correo", "Correo"), ("terminal", "Terminal")]
/// (los que antes no se elegían e iban al final: en una configuración guardada sin ellos, al final)
let VISOR_LATE_KEYS: Set<String> = ["unlink", "correo", "terminal"]
let VISOR_STYLES: [(String, String)] = [("nombre", "Icono y nombre en horizontal (solo en el visor clásico)"),
                                        ("icono", "Solo el icono (cuadrado)"), ("grande", "Icono y nombre (cuadrado)")]
/// Apariencia: dos iconos a elegir (de Reicon) para Actualizar, Log y Unlink (~/.nexum/apariencia, «iconos»)
let VISOR_ICON_CHOICES: [String: (String, String)] = ["actualizar": ("upload", "refresh-circle"),
                                                      "log": ("file-text", "code-file"),
                                                      "unlink": ("link-broken", "logout")]

/// El icono elegido en Apariencia para Actualizar, Log o Unlink (1 si no se ha elegido)
func visorChoice(_ key: String, _ iconos: [String: Int]) -> VisorIcon {
    let pair = VISOR_ICON_CHOICES[key] ?? ("file-text", "file-text")
    return .reicon(iconos[key] == 2 ? pair.1 : pair.0, Color.primary)
}
/// Lado del cuadrado de cada estilo si no se ha elegido otro, y lo que deja el deslizador (con el nombre
/// debajo hace falta algo más de sitio)
let VISOR_SIZES: [String: Int] = ["icono": 44, "grande": 88]
let VISOR_SIZE_MIN = 32
let VISOR_SIZE_MAX = 128
let VISOR_SIZE_NAMED = 72
/// El mismo fichero que en Linux (JSON con order, hidden, style y size)
let VISOR_FILE = LOG_DIR + "/botones-visor"
/// Visor arriba (Apariencia): sus botones, cuadrados y con el nombre debajo, siempre de este lado (pt), con el icono
/// de este tamaño y el nombre en letra pequeña (como en Linux: 56 y 20, el nombre a 0,7 del tamaño normal), para
/// que no crezcan con el tamaño elegido para el visor de Proyectos
let TOP_VISOR_SIDE: CGFloat = 56
let TOP_VISOR_ICON: CGFloat = 20
let TOP_VISOR_NAME: CGFloat = 9.5
/// «Unlink»: el botón de desmontar el proyecto cargado (el de expulsar)
let UNLINK_TIP = "Unlink: desmontar el proyecto (web.local deja de apuntar a él)"

struct VisorConf: Equatable {
    var order: [String] = VISOR_BUTTONS.map { $0.0 }
    var hidden: Set<String> = []
    var style = "nombre"
    var size = 44
    /// Los del visor de arriba (TopVisorBar): cuadrados de TOP_VISOR_SIDE, con el nombre debajo en letra pequeña.
    /// No se guarda: lo pone la barra de arriba sobre lo elegido (el orden y los ocultos)
    var compact = false
    var square: Bool { return compact || style != "nombre" }
    /// Lado del cuadrado: sin nombre, igual de alto que de ancho; con el nombre, al menos VISOR_SIZE_NAMED
    var side: CGFloat {
        if compact { return TOP_VISOR_SIDE }
        return CGFloat(style == "grande" ? Swift.max(size, VISOR_SIZE_NAMED) : size)
    }
}

func loadVisorConf() -> VisorConf {
    var c = VisorConf()
    let keys = VISOR_BUTTONS.map { $0.0 }
    guard let data = FileManager.default.contents(atPath: VISOR_FILE),
          let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return c }
    var seen = Set<String>()
    var order: [String] = []
    for k in (o["order"] as? [String] ?? []) where keys.contains(k) && !seen.contains(k) {
        seen.insert(k)
        order.append(k)
    }
    // (los que no estaban en lo guardado, como un botón nuevo: detrás del que les precede en VISOR_BUTTONS; Unlink,
    // Correo y Terminal, que antes no se elegían e iban al final, al final)
    for (i, k) in keys.enumerated() where !seen.contains(k) {
        if VISOR_LATE_KEYS.contains(k) {
            order.append(k)
        } else if let before = keys[..<i].last(where: { order.contains($0) }), let at = order.firstIndex(of: before) {
            order.insert(k, at: at + 1)
        } else {
            order.insert(k, at: 0)
        }
        seen.insert(k)
    }
    c.order = order
    c.hidden = Set((o["hidden"] as? [String] ?? []).filter { keys.contains($0) })
    if let s = o["style"] as? String, VISOR_STYLES.contains(where: { $0.0 == s }) { c.style = s }
    if let n = o["size"] as? Int, n >= VISOR_SIZE_MIN, n <= VISOR_SIZE_MAX {
        c.size = n
    } else {
        c.size = VISOR_SIZES[c.style] ?? 44
    }
    return c
}

/// Guarda los botones (en la simulación no se escribe nada: valen mientras la ventana siga abierta)
func saveVisorConf(_ c: VisorConf) -> Bool {
    if SIMULATE { return true }
    let o: [String: Any] = ["order": c.order, "hidden": c.hidden.sorted(), "style": c.style, "size": c.size]
    guard let data = try? JSONSerialization.data(withJSONObject: o) else { return false }
    try? FileManager.default.createDirectory(atPath: LOG_DIR, withIntermediateDirectories: true,
                                             attributes: [.posixPermissions: 0o700])
    return FileManager.default.createFile(atPath: VISOR_FILE, contents: data)
}

/// La web del repositorio de una carpeta (su remote origin, de .git/config, sin ejecutar git): (dirección,
/// servidor) o nil. Solo https o ssh, sin usuario ni contraseña en la dirección (nunca se enseña un token)
func projectRepoURL(_ folder: String) -> (String, String)? {
    // (la ventana se redibuja a menudo, y cada fila de Proyectos lo pide: lo leído vale medio minuto)
    if let c = repoURLCache[folder], Date().timeIntervalSince(c.0) < 30 { return c.1 }
    let found = projectRepoURLRead(folder)
    repoURLCache[folder] = (Date(), found)
    return found
}

private var repoURLCache: [String: (Date, (String, String)?)] = [:]

func projectRepoURLRead(_ folder: String) -> (String, String)? {
    func match(_ pattern: String, _ s: String) -> [String]? {
        guard let rx = try? NSRegularExpression(pattern: "^(?:" + pattern + ")$"),
              let m = rx.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: s).map { String(s[$0]) } ?? ""
        }
    }
    var git = folder + "/.git"
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: git, isDirectory: &isDir) else { return nil }
    if !isDir.boolValue {
        // (un worktree o un submódulo: .git es un fichero con «gitdir: <carpeta>»)
        guard let t = try? String(contentsOfFile: git, encoding: .utf8),
              let m = match("gitdir:\\s*(.+)", t.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let dir = m[1].trimmingCharacters(in: .whitespaces)
        git = dir.hasPrefix("/") ? dir : folder + "/" + dir
    }
    guard let data = FileManager.default.contents(atPath: git + "/config"), data.count < 200_000 else { return nil }
    var url = ""
    var inside = false
    for raw in String(decoding: data, as: UTF8.self).components(separatedBy: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("[") {
            inside = match("\\[\\s*remote\\s+\"origin\"\\s*\\]", line) != nil
        } else if inside, let m = match("url\\s*=\\s*(.+)", line) {
            url = m[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            break
        }
    }
    guard let m = match("(?:https?|ssh|git\\+ssh)://(?:[^@/]*@)?([A-Za-z0-9.-]+)(?::\\d+)?/(.+?)(?:\\.git)?/?", url)
            ?? match("(?:[A-Za-z0-9._-]+@)?([A-Za-z0-9.-]+):(?!/)(.+?)(?:\\.git)?/?", url),
          match("[A-Za-z0-9._~/-]+", m[2]) != nil, !m[2].split(separator: "/").contains("..") else { return nil }
    let host = m[1].lowercased()
    return ("https://\(host)/\(m[2])", host)
}

/// Icono de un botón del visor: un símbolo del sistema con su color, un logotipo o una imagen (VS Code)
enum VisorIcon {
    case symbol(String, Color)
    case logo(String)
    case image(NSImage)
    /// (un icono de Reicon por su nombre, de ese color)
    case reicon(String, Color)
}

/// Icono de cada botón que se puede ordenar (el del diálogo de los botones y su vista previa)
func visorIcon(_ key: String, _ iconos: [String: Int] = [:]) -> VisorIcon {
    switch key {
    case "actualizar", "log", "unlink": return visorChoice(key, iconos)
    case "correo": return .logo("mailpit")
    case "terminal": return .symbol("terminal", Color.primary)
    case "web": return .symbol("globe", Color.blue)
    case "vscode":
        if let code = vscodeURL() { return .image(vscodeIcon(code)) }
        return .symbol("chevron.left.forwardslash.chevron.right", Color.primary)
    case "repo": return .logo("github")
    case "pma": return .logo("phpmyadmin")
    case "panel": return .logo("wordpress")
    case "docker": return .logo("docker")
    case "compartir": return .logo("cloudflare")
    case "imagenes": return .logo("imagenes")
    default: return .logo("log")
    }
}

struct VisorIconView: View {
    let icon: VisorIcon
    let size: CGFloat
    @Environment(\.iconsTinted) var tinted
    @Environment(\.colorScheme) var scheme

    /// (con los iconos en color, los que no tienen color propio: los de Reicon y los símbolos del color del texto)
    func iconColor(_ name: String, _ c: Color) -> Color {
        guard tinted, c == Color.primary || c == Color.secondary else { return c }
        return iconTint(name, dark: scheme == .dark)
    }

    var body: some View {
        switch icon {
        case .symbol(let s, let c):
            // (casi todo el recuadro, como los logotipos, que llenan el suyo: más pequeño, la bola del mundo no
            // tenía el tamaño del círculo de WordPress)
            UIIcon(s, size: size * 0.77).foregroundColor(iconColor(s, c)).frame(width: size, height: size)
        case .logo(let l):
            if LOGO_STROKED.contains(l) {
                LogoShape(d: LOGO_PATHS[l] ?? "")
                    .stroke(brand(l), style: StrokeStyle(lineWidth: size * 1.5 / 24, lineCap: .round, lineJoin: .round))
                    .frame(width: size, height: size)
            } else {
                BrandLogo(name: l, size: size)
            }
        case .image(let i):
            Image(nsImage: i).resizable().frame(width: size, height: size)
        case .reicon(let n, let c):
            ReiconImage(name: n, size: size).foregroundColor(iconColor(n, c))
        }
    }
}

/// Lo de dentro de un botón cuadrado: solo el icono, o el icono con el nombre debajo
struct VisorSquareLabel: View {
    let conf: VisorConf
    let name: String
    let icon: VisorIcon
    var body: some View {
        if conf.compact {
            // (el visor de arriba: pequeños, siempre del mismo lado, con el nombre en letra pequeña; ⋮, solo el icono.
            // Con «Solo el icono» en Personalizar los botones, sin el nombre y con el icono algo mayor)
            VStack(spacing: 3) {
                VisorIconView(icon: icon, size: conf.style == "icono" ? TOP_VISOR_ICON + 4 : TOP_VISOR_ICON)
                if name != "Más" && conf.style != "icono" {
                    // (si no cabe entero: «PMA», «Imágenes»)
                    Text(squareName(name, conf.side - 6, TOP_VISOR_NAME)).font(.system(size: TOP_VISOR_NAME)).lineLimit(1).truncationMode(.tail).frame(maxWidth: conf.side - 6)
                }
            }
        } else if conf.style == "grande" {
            VStack(spacing: 4) {
                VisorIconView(icon: icon, size: Swift.max(18, conf.side * 2 / 5))
                // (⋮, solo el icono)
                if name != "Más" {
                    Text(squareName(name, conf.side - 8, 11)).font(.system(size: 11)).lineLimit(1).truncationMode(.tail).frame(maxWidth: conf.side - 8)
                }
            }
        } else {
            VisorIconView(icon: icon, size: Swift.max(16, conf.side / 2))
        }
    }
}

/// Botón cuadrado del visor: el lado que se haya elegido, igual de alto que de ancho
struct SquareButton: ButtonStyle {
    let side: CGFloat
    var kind = ""
    func makeBody(configuration: Configuration) -> some View {
        SquareBody(configuration: configuration, side: side, kind: kind)
    }
}

struct SquareBody: View {
    let configuration: ButtonStyleConfiguration
    let side: CGFloat
    let kind: String
    @Environment(\.isEnabled) var enabled
    @State private var hover = false

    var body: some View {
        let on = hover && enabled
        let share = kind == "compartiendo"
        // («marcado»: Terminal con la terminal abierta, en el visor de arriba)
        let marked = kind == "marcado"
        let tint: Color = kind == "stop" ? RED : (kind == "play" ? GREEN : (share ? CLOUDFLARE : ACCENT))
        let shape = RoundedRectangle(cornerRadius: 12)
        let fill: Color = share ? CLOUDFLARE.opacity(0.10) : (marked ? ACCENT.opacity(0.13)
                                                                     : Color.primary.opacity(configuration.isPressed ? 0.10 : 0.03))
        let border: Color = on ? tint : (share ? CLOUDFLARE : (marked ? ACCENT : Color.primary.opacity(0.16)))
        return configuration.label
            .foregroundColor(on ? ACCENT : Color.primary)
            .frame(width: side, height: side)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: 1))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(shape)
            // (sin transición de color: al momento)
            .onHover { hover = $0 }
            .hoverPointer()
    }
}

/// Botón del visor de un proyecto con el estilo elegido: con su nombre (como siempre), solo el icono o el
/// icono con el nombre debajo, en un cuadrado del tamaño elegido
struct VisorButton: View {
    let conf: VisorConf
    let name: String
    let icon: VisorIcon
    let tip: String
    var kind = ""
    let action: () -> Void

    /// El mensaje al pasar el ratón por un botón cuadrado (en una función: la expresión, con todo seguido, tardaba en
    /// comprobarse al compilar)
    func tipText() -> String {
        if name == "Más" { return "" }
        if conf.compact && conf.style != "icono" { return tip.isEmpty ? name : tip }
        if conf.style == "icono" { return tip.isEmpty ? name : (tip.hasPrefix(name) ? tip : name + ": " + tip) }
        return tip
    }

    var body: some View {
        if conf.square {
            // (⋮ «Más», sin mensaje: solo despliega su menú)
            Button(action: action) { VisorSquareLabel(conf: conf, name: name, icon: icon) }
                .buttonStyle(SquareButton(side: conf.side, kind: kind))
                .tip(tipText())
        } else {
            Button(action: action) {
                HStack(spacing: 6) {
                    VisorIconView(icon: icon, size: 16)
                    Text(name)
                }
            }
            .buttonStyle(OutlineButton(kind: kind))
            .tip(tip)
        }
    }
}

/// «Botones del proyecto»: cuáles se ven, en qué orden y cómo (con una vista previa)
struct ButtonsPanel: View {
    @EnvironmentObject var model: AppModel
    @State private var conf = VisorConf()
    @State private var loaded = false
    @State private var sizeTouched = false

    var body: some View {
        let names = Dictionary(uniqueKeysWithValues: VISOR_BUTTONS)
        // (en horizontal: la lista a la izquierda y el estilo, el tamaño y la vista previa a la derecha, para
        // que quepa en la altura de un portátil)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Los que se ven y en qué orden (el del proyecto cargado y el de Docker). ⋮, el último, y los propios de Docker (Versiones de PHP, Arrancar o Parar) se ven siempre. Unlink es solo del proyecto cargado, y Correo y Terminal, del visor de arriba. «Icono y nombre en horizontal», solo en el visor clásico: en el de arriba van siempre cuadrados.")
                .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 0) {
                    ForEach(Array(conf.order.enumerated()), id: \.element) { i, key in
                        if i > 0 { Divider() }
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(get: { !conf.hidden.contains(key) }, set: { on in
                                if on { conf.hidden.remove(key) } else { conf.hidden.insert(key) }
                            }))
                            .toggleStyle(CheckboxToggleStyle()).labelsHidden()
                            .tip("Verlo en el visor")
                            VisorIconView(icon: visorIcon(key, model.look.iconos), size: 18)
                            Text(names[key] ?? key)
                            Spacer()
                            Button(action: { move(i, -1) }) { TintIcon("chevron.up") }
                                .buttonStyle(OutlineButton(compact: true)).disabled(i == 0).tip("Antes")
                            Button(action: { move(i, 1) }) { TintIcon("chevron.down") }
                                .buttonStyle(OutlineButton(compact: true)).disabled(i == conf.order.count - 1).tip("Después")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                .frame(width: 320)
              VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("Estilo").frame(width: 70, alignment: .leading)
                    SearchPicker(selection: Binding(get: { conf.style }, set: { s in
                        conf.style = s
                        if !sizeTouched { conf.size = VISOR_SIZES[s] ?? conf.size }
                    }), items: VISOR_STYLES, width: 220)
                }
                HStack(spacing: 12) {
                    Text("Tamaño").frame(width: 70, alignment: .leading)
                    Slider(value: Binding(get: { Double(conf.size) }, set: { v in
                        conf.size = Int(v)
                        sizeTouched = true
                    }), in: Double(VISOR_SIZE_MIN)...Double(VISOR_SIZE_MAX), step: 4)
                    .disabled(!conf.square)
                    Text(conf.square ? "\(Int(conf.side))×\(Int(conf.side)) px" : "—")
                        .font(.system(size: 11.5, design: .monospaced)).foregroundColor(.secondary)
                        .frame(width: 90, alignment: .trailing)
                }
                Text("Así quedan").font(.caption).foregroundColor(.secondary)
                preview(names)
              }
            }
            HStack {
                    Button("Como al principio") {
                        conf = VisorConf()
                        sizeTouched = false
                    }
                    .buttonStyle(OutlineButton())
                    .tip("Volver a los botones de siempre")
                    Spacer()
                    Button("Cancelar") { model.panel = nil }.buttonStyle(OutlineButton())
                    Button("Guardar") { model.saveVisor(conf) }.buttonStyle(OutlineButton(kind: "primary"))
            }
        }
        .onAppear {
            if !loaded {
                conf = model.visorConf
                loaded = true
            }
        }
    }

    /// Los botones que se ven, como quedarán (con ⋮ al final), en varias filas si no caben
    func preview(_ names: [String: String]) -> some View {
        let keys = conf.order.filter { !conf.hidden.contains($0) }
        let width: CGFloat = conf.square ? conf.side : 120
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: width, maximum: width + 40), spacing: 8, alignment: .leading)],
                         alignment: .leading, spacing: 8) {
            ForEach(keys, id: \.self) { k in
                VisorButton(conf: conf, name: names[k] ?? k, icon: visorIcon(k, model.look.iconos), tip: "", action: {})
            }
            VisorButton(conf: conf, name: "Más", icon: .symbol("ellipsis", Color.primary), tip: "", action: {})
        }
        .padding(4)
    }

    func move(_ i: Int, _ d: Int) {
        let j = i + d
        guard j >= 0 && j < conf.order.count else { return }
        conf.order.swapAt(i, j)
    }
}
