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
/// nombre. Desmontar, ⋮ y los propios de Docker (Versiones de PHP, Arrancar o Parar) se ven siempre
let VISOR_BUTTONS: [(String, String)] = [("web", "Abrir web"), ("vscode", "VS Code"), ("pma", "phpMyAdmin"),
                                         ("panel", "Panel"), ("docker", "Docker"), ("compartir", "Compartir"),
                                         ("log", "Log"), ("actualizar", "Actualizar"), ("imagenes", "Importar")]
let VISOR_STYLES: [(String, String)] = [("nombre", "Con su nombre"), ("icono", "Solo el icono (cuadrado)"),
                                        ("grande", "Icono y nombre (cuadrado)")]
/// Lado del cuadrado de cada estilo si no se ha elegido otro, y lo que deja el deslizador (con el nombre
/// debajo hace falta algo más de sitio)
let VISOR_SIZES: [String: Int] = ["icono": 44, "grande": 88]
let VISOR_SIZE_MIN = 32
let VISOR_SIZE_MAX = 128
let VISOR_SIZE_NAMED = 72
/// El mismo fichero que en Linux (JSON con order, hidden, style y size)
let VISOR_FILE = LOG_DIR + "/botones-visor"

struct VisorConf: Equatable {
    var order: [String] = VISOR_BUTTONS.map { $0.0 }
    var hidden: Set<String> = []
    var style = "nombre"
    var size = 44
    var square: Bool { return style != "nombre" }
    /// Lado del cuadrado: sin nombre, igual de alto que de ancho; con el nombre, al menos VISOR_SIZE_NAMED
    var side: CGFloat { return CGFloat(style == "grande" ? Swift.max(size, VISOR_SIZE_NAMED) : size) }
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
    c.order = order + keys.filter { !seen.contains($0) }
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

/// Icono de un botón del visor: un símbolo del sistema con su color, un logotipo o una imagen (VS Code)
enum VisorIcon {
    case symbol(String, Color)
    case logo(String)
    case image(NSImage)
}

/// Icono de cada botón que se puede ordenar (el del diálogo de los botones y su vista previa)
func visorIcon(_ key: String) -> VisorIcon {
    switch key {
    case "web": return .symbol("globe", Color.blue)
    case "vscode":
        if let code = vscodeURL() { return .image(NSWorkspace.shared.icon(forFile: code.path)) }
        return .symbol("chevron.left.forwardslash.chevron.right", Color.primary)
    case "pma": return .logo("phpmyadmin")
    case "panel": return .logo("wordpress")
    case "docker": return .logo("docker")
    case "compartir": return .logo("cloudflare")
    case "actualizar": return .logo("actualizar")
    case "imagenes": return .logo("imagenes")
    default: return .logo("log")
    }
}

struct VisorIconView: View {
    let icon: VisorIcon
    let size: CGFloat
    var body: some View {
        switch icon {
        case .symbol(let s, let c):
            Image(systemName: s).font(.system(size: size * 0.8)).foregroundColor(c).frame(width: size, height: size)
        case .logo(let l):
            if LOGO_STROKED.contains(l) {
                LogoShape(d: LOGO_PATHS[l] ?? "")
                    .stroke(brand(l), style: StrokeStyle(lineWidth: size * 1.5 / 24, lineCap: .round, lineJoin: .round))
                    .frame(width: size, height: size)
            } else {
                LogoShape(d: LOGO_PATHS[l] ?? "").fill(brand(l)).frame(width: size, height: size)
            }
        case .image(let i):
            Image(nsImage: i).resizable().frame(width: size, height: size)
        }
    }
}

/// Lo de dentro de un botón cuadrado: solo el icono, o el icono con el nombre debajo
struct VisorSquareLabel: View {
    let conf: VisorConf
    let name: String
    let icon: VisorIcon
    var body: some View {
        if conf.style == "grande" {
            VStack(spacing: 4) {
                VisorIconView(icon: icon, size: Swift.max(18, conf.side * 2 / 5))
                Text(name).font(.system(size: 11)).lineLimit(1).truncationMode(.tail).frame(maxWidth: conf.side - 8)
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
        let tint: Color = kind == "stop" ? RED : (kind == "play" ? GREEN : (share ? CLOUDFLARE : ACCENT))
        let shape = RoundedRectangle(cornerRadius: 12)
        let fill: Color = share ? CLOUDFLARE.opacity(0.10) : Color.primary.opacity(configuration.isPressed ? 0.10 : 0.03)
        let border: Color = on ? tint : (share ? CLOUDFLARE : Color.primary.opacity(0.16))
        return configuration.label
            .foregroundColor(on ? ACCENT : Color.primary)
            .frame(width: side, height: side)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: 1))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(shape)
            .animation(.easeOut(duration: 0.12), value: on)
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

    var body: some View {
        if conf.square {
            Button(action: action) { VisorSquareLabel(conf: conf, name: name, icon: icon) }
                .buttonStyle(SquareButton(side: conf.side, kind: kind))
                .tip(conf.style == "icono" ? (tip.isEmpty ? name : tip.hasPrefix(name) ? tip : name + ": " + tip) : tip)
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
            Text("Los que se ven y en qué orden (el del proyecto cargado y el de Docker). Desmontar, ⋮ y los propios de Docker (Versiones de PHP, Arrancar o Parar) se ven siempre.")
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
                            VisorIconView(icon: visorIcon(key), size: 18)
                            Text(names[key] ?? key)
                            Spacer()
                            Button(action: { move(i, -1) }) { Image(systemName: "chevron.up") }
                                .buttonStyle(OutlineButton(compact: true)).disabled(i == 0).tip("Antes")
                            Button(action: { move(i, 1) }) { Image(systemName: "chevron.down") }
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
                    Picker("", selection: Binding(get: { conf.style }, set: { s in
                        conf.style = s
                        if !sizeTouched { conf.size = VISOR_SIZES[s] ?? conf.size }
                    })) {
                        ForEach(VISOR_STYLES, id: \.0) { st in Text(st.1).tag(st.0) }
                    }
                    .labelsHidden()
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

    /// Los botones que se ven, como quedarán (con Desmontar y ⋮), en varias filas si no caben
    func preview(_ names: [String: String]) -> some View {
        let keys = conf.order.filter { !conf.hidden.contains($0) }
        let width: CGFloat = conf.square ? conf.side : 120
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: width, maximum: width + 40), spacing: 8, alignment: .leading)],
                         alignment: .leading, spacing: 8) {
            ForEach(keys, id: \.self) { k in
                VisorButton(conf: conf, name: names[k] ?? k, icon: visorIcon(k), tip: "", action: {})
            }
            VisorButton(conf: conf, name: "Desmontar", icon: .symbol("eject.fill", Color.secondary), tip: "", action: {})
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
