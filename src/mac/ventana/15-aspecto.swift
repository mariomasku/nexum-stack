// MARK: - Aspecto de la ventana (desde la 1.39: como la de Linux 1.54)

/// Azul de los botones principales, de lo elegido y del borde de los botones al pasar el ratón
let ACCENT = hexColor(0x0A84FF)
/// Tema de la ventana elegido en el menú: claro u oscuro (sin fichero, el del Mac)
let THEME_FILE = LOG_DIR + "/ventana-tema"
/// Lo que puede durar un túnel de Cloudflare: minutos y cómo se dice
let TUNNEL_TIMES: [(Int, String)] = [(15, "15 minutos"), (30, "30 minutos"), (60, "1 hora"), (120, "2 horas"), (180, "3 horas"),
                                     (240, "4 horas"), (360, "6 horas"), (480, "8 horas"), (720, "12 horas")]
/// Los colores del icono de Nexum (el borde del aviso de abajo): azul, verde, amarillo, rojo y magenta
let NEXUM_COLORS: [Color] = [hexColor(0x006CB7), hexColor(0x88BB1D), hexColor(0xFFB608), hexColor(0xFF0000), hexColor(0xF20093)]
/// La última versión que estuvo activa (al parar y desactivar): la primera que ofrece ▶ en el visor
let LAST_VERSION_FILE = LOG_DIR + "/ultima-version"
/// Página de descarga de Docker Desktop (en el Mac no se instala desde aquí)
let DOCKER_DOWNLOAD = "https://www.docker.com/products/docker-desktop/"

/// Botón con un borde gris claro que se pone azul al pasar el ratón, sin relieve. kind: "" (normal),
/// primary (azul con letras blancas), stop (rojo), play (verde) o dashed (borde discontinuo). big: los
/// de los diálogos y las tareas (34 de alto, como en Linux)
struct OutlineButton: ButtonStyle {
    var kind = ""
    var compact = false
    var big = false
    func makeBody(configuration: Configuration) -> some View {
        OutlineBody(configuration: configuration, kind: kind, compact: compact, big: big)
    }
}

struct OutlineBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: String
    let compact: Bool
    var big = false
    @Environment(\.isEnabled) var enabled
    @Environment(\.colorScheme) var scheme
    @State private var hover = false

    var body: some View {
        let on = hover && enabled
        let primary = kind == "primary"
        // («encendido», el de los servicios de arriba: verde, salvo en el tema claro, donde el verde no se
        // ve sobre el gris: azul)
        let colored = kind == "stop" || kind == "play" || kind == "encendido"
        let tint: Color = kind == "stop" ? RED : (kind == "play" ? GREEN
            : (kind == "encendido" ? (scheme == .dark ? GREEN : ACCENT) : ACCENT))
        let text: Color = primary ? Color.white : (colored ? tint : (on ? ACCENT : Color.primary))
        // («compartiendo»: un túnel de Cloudflare abierto, con el borde y el fondo en su naranja)
        let share = kind == "compartiendo"
        let fill: Color = primary ? ACCENT.opacity(configuration.isPressed ? 0.75 : (on ? 0.88 : 1))
            : (share ? CLOUDFLARE.opacity(0.10) : Color.primary.opacity(configuration.isPressed ? 0.10 : 0.03))
        let border: Color = primary ? Color.clear : (on ? tint : (share ? CLOUDFLARE : Color.primary.opacity(0.16)))
        let shape = RoundedRectangle(cornerRadius: big ? 8 : 7)
        return configuration.label
            .font(.system(size: big ? 13 : 12.5, weight: primary ? .semibold : .regular))
            .foregroundColor(text)
            .padding(.horizontal, big ? 18 : (compact ? 7 : 12))
            .padding(.vertical, big ? 4 : (compact ? 4 : 6))
            .frame(minHeight: big ? 34 : nil)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, style: StrokeStyle(lineWidth: 1, dash: kind == "dashed" ? [4, 3] : [])))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(shape)
            .animation(.easeOut(duration: 0.12), value: on)
            .onHover { hover = $0 }
            .hoverPointer()
    }
}

/// Botón sin borde (vincular) cuyo icono se pone azul al pasar el ratón
struct LinkHoverButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LinkHoverBody(configuration: configuration)
    }
}

struct LinkHoverBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) var enabled
    @State private var hover = false

    var body: some View {
        let on = hover && enabled
        return configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(on ? ACCENT : Color.secondary)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(ACCENT.opacity(on ? 0.12 : 0)))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .hoverPointer()
    }
}

/// Menú desplegable con el aspecto de OutlineButton. Sin borde (bordered: false), solo al pasar el ratón
struct OutlineMenu<Items: View>: View {
    let title: String?
    let symbol: String
    let bordered: Bool
    let items: Items
    @State private var hover = false

    init(_ title: String?, symbol: String, bordered: Bool = true, @ViewBuilder items: () -> Items) {
        self.title = title
        self.symbol = symbol
        self.bordered = bordered
        self.items = items()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7)
        return Menu {
            items
        } label: {
            if let t = title {
                Label(t, systemImage: symbol)
            } else {
                Image(systemName: symbol)
            }
        }
        .menuStyle(BorderlessButtonMenuStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, title == nil ? 7 : 11)
        .padding(.vertical, 5)
        .background(shape.fill(Color.primary.opacity(bordered || hover ? 0.03 : 0)))
        .overlay(shape.stroke(hover ? ACCENT : Color.primary.opacity(bordered ? 0.16 : 0), lineWidth: 1))
        .contentShape(shape)
        .onHover { hover = $0 }
        .hoverPointer()
    }
}

/// Botón de una tabla con solo un icono
func iconAction(_ symbol: String, _ tip: String, kind: String = "", _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: symbol).frame(width: 14, height: 14)
    }
    .buttonStyle(OutlineButton(kind: kind, compact: true))
    .tip(tip)
}

/// Botón de una tabla con el logotipo de un paquete
func logoAction(_ logo: String, _ tip: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        LogoShape(d: LOGO_PATHS[logo] ?? "").fill(brand(logo)).frame(width: 14, height: 14)
    }
    .buttonStyle(OutlineButton(compact: true))
    .tip(tip)
}

/// Punto de estado: verde y latiendo despacio si está en marcha, gris si no
struct StatusDot: View {
    let on: Bool
    var size: CGFloat = 8
    var blink = true
    @State private var dim = false

    var body: some View {
        Circle().fill(on ? GREEN : Color.secondary.opacity(0.45))
            .frame(width: size, height: size)
            .opacity(on && blink && dim ? 0.3 : 1)
            .onAppear { pulse() }
            .onChange(of: on) { _ in pulse() }
    }

    func pulse() {
        guard on && blink else {
            dim = false
            return
        }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { dim = true }
    }
}

/// Recuadro hundido suave (el visor de arriba, el entorno y la BBDD del proyecto): algo más oscuro
/// que la ventana, con una sombra fina por dentro
struct SoftSunken: View {
    var radius: CGFloat = 10
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        return shape.fill(Color.primary.opacity(0.05))
            .overlay(shape.stroke(Color.black.opacity(0.16), lineWidth: 2).blur(radius: 1.5).offset(y: 1).mask(shape))
            .overlay(shape.stroke(Color.primary.opacity(0.10), lineWidth: 1))
    }
}

/// Etiqueta pequeña (WordPress, Activa, Cargado), gris o azul
struct SmallTag: View {
    let text: String
    var blue = false
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(blue ? ACCENT : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill((blue ? ACCENT : Color.secondary).opacity(0.14)))
    }
}

/// Versión en una fila de proyectos (8.4) o su entorno de Docker
struct Chip: View {
    let text: String
    var docker = false
    var body: some View {
        HStack(spacing: 4) {
            if docker {
                LogoShape(d: LOGO_PATHS["docker"] ?? "").fill(brand("docker")).frame(width: 11, height: 11)
            }
            Text(text)
        }
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundColor(docker ? brand("docker") : Color.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill((docker ? brand("docker") : Color.primary).opacity(0.08)))
    }
}

/// «En marcha» en verde con su punto latiendo, o «Parado» en gris
struct RunPill: View {
    let on: Bool
    var body: some View {
        HStack(spacing: 6) {
            if on { StatusDot(on: true, size: 7) }
            Text(on ? "En marcha" : "Parado")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(on ? GREEN : Color.secondary)
        }
    }
}

/// Logotipo del tipo de proyecto: WordPress, PrestaShop o una carpeta
struct KindIcon: View {
    let kind: String
    var size: CGFloat = 18
    @ViewBuilder
    var body: some View {
        if kind == "wp" || kind == "ps" {
            let name = kind == "wp" ? "wordpress" : "prestashop"
            LogoShape(d: LOGO_PATHS[name] ?? "").fill(brand(name)).frame(width: size, height: size)
        } else {
            Image(systemName: "folder").font(.system(size: size * 0.8)).foregroundColor(.secondary)
                .frame(width: size, height: size)
        }
    }
}

/// Tarjeta con una cifra (arriba de Bases de datos y de Docker)
struct StatCard: View {
    let title: String
    let value: String
    let sub: String
    var progress: Double? = nil
    var action: (String, () -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(title).font(.caption).foregroundColor(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                if let a = action {
                    Button(a.0, action: a.1).buttonStyle(OutlineButton(compact: true))
                }
            }
            Text(value).font(.system(size: 22, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            if let p = progress {
                ProgressView(value: max(0, min(1, p))).progressViewStyle(LinearProgressViewStyle(tint: ACCENT))
            }
            Text(sub).font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
        }
        .padding(14)
        // (todo el alto que le den: en una fila con .fixedSize(horizontal: false, vertical: true), todas tan
        // altas como la más alta)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

/// Buscador con lupa y botón de borrar
struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField(placeholder, text: $text).textFieldStyle(PlainTextFieldStyle())
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
                .hoverPointer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15), lineWidth: 1))
    }
}

/// Los desplegables de la ventana, con buscador como en Linux: con COMBO_SEARCH_MIN opciones o más, al pulsarlo sale
/// la lista con un campo «Buscar…»; se escribe y se queda solo lo que lleva ese texto (como la barra de búsqueda de
/// los proyectos), las flechas eligen, Intro la escoge y Esc cierra sin cambiar nada. Con menos, el Picker de siempre.
/// items: (valor, texto)
let COMBO_SEARCH_MIN = 8

struct SearchPicker: View {
    @Binding var selection: String
    let items: [(String, String)]
    var width: CGFloat = 230
    @State private var open = false
    @State private var query = ""
    @State private var mark = 0
    @State private var hover = false
    @Environment(\.isEnabled) var enabled

    var body: some View {
        if items.count < COMBO_SEARCH_MIN {
            Picker("", selection: $selection) {
                ForEach(items, id: \.0) { Text($0.1).tag($0.0) }
            }
            .labelsHidden()
            .frame(width: width)
        } else {
            Button(action: { query = ""; mark = shown().firstIndex(where: { $0.0 == selection }) ?? 0; open = true }) {
                HStack(spacing: 6) {
                    Text(items.first(where: { $0.0 == selection })?.1 ?? "").lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .frame(width: width, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(NSColor.controlColor)))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(hover && enabled ? 0.30 : 0.18), lineWidth: 1))
                .contentShape(Rectangle())
                .opacity(enabled ? 1 : 0.5)
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hover = $0 }
            .hoverPointer()
            .popover(isPresented: $open, arrowEdge: .bottom) { list() }
        }
    }

    func shown() -> [(String, String)] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? items : items.filter { $0.1.lowercased().contains(q) }
    }

    func choose(_ i: Int) {
        let rows = shown()
        if i >= 0 && i < rows.count { selection = rows[i].0 }
        open = false
    }

    func list() -> some View {
        let rows = shown()
        return VStack(alignment: .leading, spacing: 6) {
            KeySearchField(text: $query, placeholder: "Buscar…",
                           onMove: { step in
                               let n = shown().count
                               if n > 0 { mark = Swift.min(Swift.max(mark + step, 0), n - 1) }
                           },
                           onEnter: { choose(mark) }, onEscape: { open = false })
                .frame(height: 24)
                .onChange(of: query) { _ in mark = 0 }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if rows.isEmpty {
                            Text("Sin resultados").foregroundColor(.secondary).frame(maxWidth: .infinity).padding(10)
                        }
                        ForEach(Array(rows.enumerated()), id: \.element.0) { n, r in
                            Text(r.1).lineLimit(1).truncationMode(.tail)
                                .foregroundColor(n == mark ? .white : .primary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 5).fill(n == mark ? ACCENT : Color.clear))
                                .contentShape(Rectangle())
                                .onTapGesture { choose(n) }
                                .onHover { if $0 { mark = n } }
                                .id(n)
                        }
                    }
                }
                .frame(maxHeight: 340)
                .onChange(of: mark) { m in proxy.scrollTo(m) }
                .onAppear { proxy.scrollTo(mark, anchor: .center) }
            }
        }
        .padding(8)
        .frame(width: listWidth())
    }

    /// Como poco, tan ancha como el desplegable; si los nombres son más largos, lo que haga falta para verlos
    /// enteros, hasta 640 (solo los larguísimos se cortan con «…»)
    func listWidth() -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let longest = items.map { ($0.1 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return Swift.min(Swift.max(width, 260, longest + 48), 640)
    }
}

/// Campo de búsqueda que pasa las flechas, Intro y Esc (el TextField de SwiftUI de macOS 12 no los da)
struct KeySearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onMove: (Int) -> Void
    let onEnter: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let f = NSSearchField()
        f.placeholderString = placeholder
        f.delegate = context.coordinator
        f.sendsSearchStringImmediately = true
        // (con el foco ya puesto: se escribe nada más abrir)
        DispatchQueue.main.async { f.window?.makeFirstResponder(f) }
        return f
    }

    func updateNSView(_ f: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if f.stringValue != text { f.stringValue = text }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: KeySearchField
        init(_ p: KeySearchField) { parent = p }

        func controlTextDidChange(_ n: Notification) {
            if let f = n.object as? NSSearchField { parent.text = f.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.pageDown(_:)), #selector(NSResponder.scrollPageDown(_:)): parent.onMove(8)
            case #selector(NSResponder.pageUp(_:)), #selector(NSResponder.scrollPageUp(_:)): parent.onMove(-8)
            case #selector(NSResponder.insertNewline(_:)): parent.onEnter()
            // (Esc con texto lo vacía; vacío, cierra)
            case #selector(NSResponder.cancelOperation(_:)):
                if parent.text.isEmpty { parent.onEscape() } else { parent.text = "" }
            default: return false
            }
            return true
        }
    }
}

extension View {
    /// Celda de una tabla: ancho fijo (0: el que quede), a la izquierda o, con align, donde se diga
    @ViewBuilder
    func col(_ w: CGFloat, align: Alignment = .leading) -> some View {
        if w > 0 {
            frame(width: w, alignment: align)
        } else {
            frame(maxWidth: .infinity, alignment: align)
        }
    }
}

/// Tabla: un recuadro con las filas separadas por líneas
struct TableBox<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.025)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

/// Cabecera de una tabla: los títulos en mayúsculas pequeñas, cada uno con su ancho (0: el resto).
/// lastRight: el último, a la derecha (sobre unas acciones pegadas al borde)
struct TableHead: View {
    let cols: [(String, CGFloat)]
    var lastRight = false
    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(cols.enumerated()), id: \.offset) { i, c in
                Text(c.0.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.secondary)
                    .col(c.1, align: lastRight && i == cols.count - 1 ? .trailing : .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }
}

/// Fila de una tabla: algo más clara al pasar el ratón (content recibe si lo está, para enseñar
/// entonces «Cargar» o «Activar») y azul si es la elegida. Al pulsarla, action
struct HoverRow<Content: View>: View {
    let selected: Bool
    let action: (() -> Void)?
    let content: (Bool) -> Content
    @State private var hover = false

    init(selected: Bool = false, action: (() -> Void)? = nil, @ViewBuilder content: @escaping (Bool) -> Content) {
        self.selected = selected
        self.action = action
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        let row = HStack(spacing: 12) { content(hover) }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(selected ? ACCENT.opacity(0.10) : Color.primary.opacity(hover ? 0.035 : 0))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
        if let a = action {
            row.onTapGesture(perform: a)
        } else {
            row
        }
    }
}

/// Página ancha (las tablas): con desplazamiento y centrada
struct WidePage<Content: View>: View {
    let width: CGFloat
    /// Al cambiar, la página sube hasta arriba poco a poco (como al deslizar)
    let top: Int
    let content: Content
    init(width: CGFloat = 980, top: Int = 0, @ViewBuilder content: () -> Content) {
        self.width = width
        self.top = top
        self.content = content()
    }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) { content }
                    .frame(maxWidth: width, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .id("arriba")
            }
            .onChange(of: top) { _ in
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("arriba", anchor: .top) }
            }
        }
    }
}

/// Como WidePage, en dos partes: arriba, fija (no se va al desplazar: el visor de Proyectos), y debajo lo que
/// se desplaza (la lista)
struct SplitPage<Head: View, Content: View>: View {
    let width: CGFloat
    /// Al cambiar, la lista sube hasta arriba poco a poco
    let top: Int
    let head: Head
    let content: Content
    init(width: CGFloat = 980, top: Int = 0, @ViewBuilder head: () -> Head, @ViewBuilder content: () -> Content) {
        self.width = width
        self.top = top
        self.head = head()
        self.content = content()
    }
    /// Lo que ocupa la barra de desplazamiento de la lista (0 si flota encima): lo de arriba deja ese mismo
    /// hueco a la derecha, para que el visor y la tabla tengan el mismo ancho y los mismos márgenes
    @State private var gutter: CGFloat = 0
    @State private var outerW: CGFloat = 0
    @State private var innerW: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) { head }
                .frame(maxWidth: width, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity)
                .padding(.trailing, gutter)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) { content }
                        .frame(maxWidth: width, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: SplitInnerWidthKey.self, value: g.size.width)
                        })
                        .id("arriba")
                }
                .onChange(of: top) { _ in
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("arriba", anchor: .top) }
                }
            }
            .background(GeometryReader { g in
                Color.clear.preference(key: SplitOuterWidthKey.self, value: g.size.width)
            })
        }
        .onPreferenceChange(SplitInnerWidthKey.self) { w in innerW = w; fitGutter() }
        .onPreferenceChange(SplitOuterWidthKey.self) { w in outerW = w; fitGutter() }
    }

    private func fitGutter() {
        guard outerW > 0, innerW > 0 else { return }
        // (como mucho lo de una barra; medio punto arriba o abajo no se cuenta, para que no tiemble)
        let g = Swift.min(24, Swift.max(0, (outerW - innerW).rounded()))
        if abs(g - gutter) >= 1 { gutter = g }
    }
}

private struct SplitInnerWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = Swift.max(value, nextValue()) }
}

private struct SplitOuterWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = Swift.max(value, nextValue()) }
}

/// Título grande de una página, con su explicación debajo. Delante, un símbolo (Dominios y hosts,
/// Configuración) o el logotipo de un paquete en su color (Versiones de PHP, como la ballena de Docker)
struct PageTitle: View {
    let title: String
    let sub: String
    var symbol: String? = nil
    var logo: String? = nil
    /// (Docker y Node: de título, su logotipo entero, con el icono y sus letras, en lugar del texto)
    var brandTitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let b = brandTitle {
                BrandImage(key: b, height: 34)
            } else {
            HStack(spacing: 10) {
                if let l = logo {
                    LogoShape(d: LOGO_PATHS[l] ?? "").fill(brand(l)).frame(width: 30, height: 30)
                } else if let sym = symbol {
                    Image(systemName: sym).font(.system(size: 22, weight: .medium)).frame(width: 30, height: 30)
                }
                Text(title).font(.system(size: 22, weight: .bold))
            }
            }
            if !sub.isEmpty {
                Text(sub).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}

/// Número con coma decimal (12,5 %)
func fmtPercent(_ v: Double) -> String {
    return String(format: "%.1f %%", v).replacingOccurrences(of: ".", with: ",")
}

/// Versión corta de PHP para las etiquetas (8.4.12 → 8.4)
func shortPhp(_ php: String) -> String {
    let parts = php.split(separator: ".")
    return parts.count >= 3 ? parts.prefix(2).joined(separator: ".") : php
}

/// Avisos que van en el botón de avisos de arriba (los mismos que pone WarningsView)
func warningCount(_ d: AppData) -> Int {
    var n = 0
    if d.official { n += 1 }
    if !d.dbsysVersion.isEmpty { n += 1 }
    if d.installs.contains(where: { pmaOutdated($0.php, $0.pma) }) { n += 1 }
    if !d.unsecured.isEmpty { n += 1 }
    if !d.certs.isEmpty || !d.cas.isEmpty { n += 1 }
    if !d.untrusted.isEmpty { n += 1 }
    if !d.stale.isEmpty { n += 1 }
    if !d.stray.isEmpty { n += 1 }
    if !d.orphans.isEmpty { n += 1 }
    if d.installs.contains(where: { php2shellVulnerable(d.php2shell[$0.folder] ?? "ok") }) { n += 1 }
    return n
}

/// Ventanas que se abren encima de la página (Componentes, Instalar versión, Proyecto en Docker): no
/// son hojas de SwiftUI, para que la de la tarea pueda abrirse en cuanto se pulse su botón
enum Panel: Identifiable, Equatable {
    case components(String)
    case install
    case dockerNew
    case buttons

    var id: String {
        switch self {
        case .components(let f): return "c" + f
        case .install: return "i"
        case .dockerNew: return "d"
        case .buttons: return "b"
        }
    }
    var title: String {
        switch self {
        case .components: return "Componentes"
        case .install: return "Instalar versión"
        case .dockerNew: return "Proyecto en Docker"
        case .buttons: return "Botones del proyecto"
        }
    }
    var width: CGFloat {
        switch self {
        case .components: return 760
        case .install: return 720
        case .dockerNew: return 620
        case .buttons: return 900
        }
    }
}

/// Recuadro de una de esas ventanas, centrado sobre la página oscurecida
struct PanelBox<Content: View>: View {
    let title: String
    let width: CGFloat
    let close: () -> Void
    let content: Content
    init(title: String, width: CGFloat, close: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.width = width
        self.close = close
        self.content = content()
    }
    var body: some View {
        ZStack {
            // (pulsar fuera no la cierra: se cierra con su botón o con Esc)
            Color.black.opacity(0.28).contentShape(Rectangle()).onTapGesture {}
            VStack(alignment: .leading, spacing: 0) {
                // (el título, centrado, como en los diálogos; el botón de cerrar, a la derecha)
                ZStack {
                    Text(title).font(.headline).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    HStack {
                        Spacer()
                        Button(action: close) { Image(systemName: "xmark") }
                            .buttonStyle(OutlineButton(compact: true))
                            .keyboardShortcut(.cancelAction)
                            .tip("Cerrar")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                Divider()
                content.padding(18)
            }
            .frame(width: width)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.3), radius: 24, y: 8)
        }
    }
}
