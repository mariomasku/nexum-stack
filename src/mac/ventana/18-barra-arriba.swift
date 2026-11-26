// MARK: - Barra de arriba

/// Siempre a la vista: el nombre, el menú, el visor de la versión montada (PHP, Apache y MariaDB con su
/// punto, encender o apagar y, en la flecha, sus servicios), Localhost y los avisos (phpMyAdmin, desde
/// la 1.39.5, en Bases de datos y en el menú Gestor)
/// Tarea en segundo plano: una flecha verde que baja y late, con su porcentaje; al pulsarla, su hoja
struct TaskBadge: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var task: TaskRunner
    @State private var pulse = false

    var body: some View {
        Button(action: { model.taskHidden = false }) {
            HStack(spacing: 5) {
                UIIcon("arrow.down.circle.fill", size: 15, weight: .semibold)
                    .opacity(pulse ? 0.35 : 1)
                    .offset(y: pulse ? 2 : -2)
                // (lo que hace, con la primera palabra del título: «Actualizando…», «Instalando…»)
                Text((task.title.split(separator: " ").first.map(String.init) ?? "En marcha") + "…")
                    .font(.system(size: 11.5, weight: .semibold))
                if let r = task.pctText.range(of: "%") {
                    Text(String(task.pctText[..<r.upperBound])).font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                }
                if !model.taskQueue.isEmpty {
                    Text("· \(model.taskQueue.count) en la cola").font(.system(size: 11.5, weight: .semibold))
                }
            }
            .foregroundColor(.green)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.green.opacity(0.13)))
            .overlay(Capsule().stroke(Color.green.opacity(0.5), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .hoverPointer()
        .tip("\(task.title)\n\(task.barText)\nPulsa para ver la ventana")
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

struct TopBar: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) var scheme
    @State private var menuOpen = false
    @State private var warnOpen = false
    @State private var warnHover = false
    /// Visor arriba: lo que ocupan, a la izquierda, el nombre y, a la derecha, la tarea, los avisos y ☰ (medido al
    /// dibujarse): el visor deja ese mismo hueco a los dos lados, así queda centrado en la ventana, como en Linux
    @State private var leftWidth: CGFloat = 0
    @State private var rightWidth: CGFloat = 0

    var body: some View {
        if model.look.visor == "clasico" {
            classicBar()
        } else {
            // Visor arriba (Apariencia): el proyecto cargado y sus botones, con Correo y Terminal iguales que ellos,
            // centrados en la ventana (si no caben, se desplazan); el nombre a la izquierda y la tarea, los avisos
            // y el menú ☰, pegados a la derecha del todo
            ZStack {
                HStack(spacing: 12) {
                    brand().background(widthReader { leftWidth = $0 })
                    Spacer(minLength: 0)
                    HStack(spacing: 12) {
                        if model.taskHidden, let t = model.task {
                            TaskBadge(task: t)
                        }
                        // (los avisos, justo a la izquierda del menú ☰)
                        warnings()
                        menuButton()
                    }
                    .background(widthReader { rightWidth = $0 })
                }
                TopVisorBar()
                    .padding(.horizontal, Swift.max(leftWidth, rightWidth) + 12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
    }

    /// El logotipo y el nombre del programa, con su versión
    func brand() -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                title(model.data?.name ?? "Nexum Dev Stack")
                // (con la versión del programa detrás)
                Text("Entornos PHP y Docker" + ((model.data?.version).map { $0.isEmpty ? "" : "  ·  v\($0)" } ?? ""))
                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
        }
    }

    /// El ancho de una vista, cada vez que cambia (por detrás, sin dibujar nada)
    func widthReader(_ set: @escaping (CGFloat) -> Void) -> some View {
        GeometryReader { g in
            Color.clear
                .onAppear { set(g.size.width) }
                .onChange(of: g.size.width) { w in set(w) }
        }
    }

    /// La barra de siempre (visor clásico): el nombre, el recuadro de la versión con los avisos y ☰, y Correo y
    /// Terminal a la derecha
    func classicBar() -> some View {
        HStack(spacing: 12) {
            brand()
            Group {
                Spacer(minLength: 12)
                // (la tarea en segundo plano, a la izquierda del visor; el menú, justo a su derecha, como en Linux)
                if model.taskHidden, let t = model.task {
                    TaskBadge(task: t)
                }
                visor()
                // (los avisos, justo a la izquierda del menú ☰)
                warnings()
                menuButton()
                Spacer(minLength: 12)
                mailButton()
                // (la terminal de abajo de la ventana: se enseña y se esconde; en lugar de Localhost)
                Button(action: { model.termOpen.toggle() }) {
                    Label { Text("Terminal") } icon: { TintIcon("terminal") }
                }
                .buttonStyle(OutlineButton(kind: model.termOpen ? "primary" : ""))
                .tip("Mostrar u ocultar la terminal")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    /// El nombre: «NEXUM» en Goldman y lo demás («Dev Stack») normal y en azul, que se lea sobre el
    /// gris de la ventana (más claro en el tema oscuro, más oscuro en el claro). Goldman va en la
    /// aplicación (Resources/fuentes); sin ella, la del sistema
    func title(_ name: String) -> Text {
        guard name.hasPrefix("Nexum "), name.count > 6 else { return Text(name).font(.system(size: 14, weight: .bold)) }
        let blue = scheme == .dark ? hexColor(0x4C9DFF) : hexColor(0x0A6FD6)
        return Text("NEXUM").font(.custom("Goldman", size: 15)).kerning(1)
            + Text(String(name.dropFirst(5))).font(.system(size: 14)).foregroundColor(blue)
    }

    /// Menú (☰), sin recuadro, con un icono en cada opción y el tema claro u oscuro
    func menuButton() -> some View {
        Button(action: { menuOpen.toggle() }) {
            UIIcon("line.3.horizontal", size: 17, weight: .medium)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .hoverPointer()
        .tip("Menú")
        .popover(isPresented: $menuOpen, arrowEdge: .bottom) {
            MainMenu(close: { menuOpen = false }).environmentObject(model)
        }
    }

    /// El recuadro de la versión montada (visor clásico): lo de VersionVisor, en su recuadro hundido
    func visor() -> some View {
        VersionVisor()
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(SoftSunken(radius: 12))
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
    }

    /// Correo de pruebas: la bandeja de Mailpit, con los correos sin leer (se pregunta solo con la
    /// ventana a la vista). Con el correo de pruebas apagado no sale
    @ViewBuilder
    func mailButton() -> some View {
        if let m = model.data?.mail, m.on {
            Button(action: { model.openMail() }) {
                HStack(spacing: 6) {
                    BrandLogo(name: "mailpit", size: 15)
                    Text("Correo")
                    if let n = model.mailUnread, n > 0 {
                        MailBadge(n: n)
                    }
                }
            }
            .buttonStyle(OutlineButton())
            .tip(model.mailTip(m))
        }
    }

    /// Los avisos (lo que antes iba arriba de Versiones) en un solo botón con cuántos hay
    @ViewBuilder
    func warnings() -> some View {
        let n = (model.data.map { warningCount($0) } ?? 0) + (model.updatesPending != nil ? 1 : 0)
        if model.data != nil, n > 0 {
            // (sin recuadro, plano como ☰: un fondo suave solo al pasar el ratón, siempre del mismo tamaño)
            Button(action: { warnOpen.toggle() }) {
                HStack(spacing: 5) {
                    // (en amarillo: avisa, no es un error)
                    UIIcon("exclamationmark.triangle.fill").foregroundColor(.yellow)
                    Text("\(n)").font(.system(size: 12, weight: .bold))
                }
                .padding(.horizontal, 7)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(warnHover || warnOpen ? 0.10 : 0)))
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { warnHover = $0 }
            .hoverPointer()
            .tip("Avisos")
            .popover(isPresented: $warnOpen, arrowEdge: .bottom) {
                ScrollView {
                    WarningsView().environmentObject(model).buttonStyle(PointerButtonStyle()).padding(18)
                }
                .frame(width: dialogWidth(620), height: dialogHeight(480))
            }
        }
    }
}

/// Lo de la versión montada: el logotipo de PHP y su versión, Apache y MariaDB con su punto (al pulsarlos, sus
/// servicios), ▶ / ■ y lo que gasta Nexum. En la barra de arriba, en su recuadro (visor clásico; TopBar.visor) o,
/// con el visor arriba (Apariencia), en la barra de estado, sin recuadro, en una línea y con sus recuadros
/// abriéndose hacia arriba (bottom)
struct VersionVisor: View {
    @EnvironmentObject var model: AppModel
    var bottom = false
    @State private var servicesOpen = false
    @State private var powerOpen = false
    @State private var powerHover = false
    @State private var servicesHover = false
    @State private var versionsOpen = false
    @State private var versionHover = false

    var body: some View {
        let d = model.data
        let act = d.flatMap { dd in dd.installs.first(where: { $0.folder == dd.active }) }
        let running = d?.running ?? false
        let svc = Dictionary((model.services ?? []).map { ($0.name, $0.running) }, uniquingKeysWith: { a, _ in a })
        let edge: Edge = bottom ? .top : .bottom
        return HStack(spacing: bottom ? 8 : 9) {
            // La versión (su logotipo, PHP x.y y XAMPP-carpeta): al pulsarla, las instaladas para cambiar de versión
            Button(action: { versionsOpen.toggle() }) {
                versionLabel(act)
                    .padding(.horizontal, 5)
                    .padding(.vertical, bottom ? 1 : 2)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(versionHover || versionsOpen ? 0.10 : 0)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(d == nil || (d?.installs.isEmpty ?? true))
            .onHover { versionHover = $0 }
            .hoverPointer()
            .tip("Cambiar de versión de PHP")
            .popover(isPresented: $versionsOpen, arrowEdge: edge) {
                VersionsFan(fromBottom: bottom, close: { versionsOpen = false }).environmentObject(model)
            }
            Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: bottom ? 14 : 22)
            // Apache y MariaDB con su punto: al pulsarlos, sus servicios (arrancarlos, pararlos o reiniciarlos,
            // y la versión entera)
            Button(action: { servicesOpen.toggle() }) {
                HStack(spacing: 9) {
                    ForEach(["apache", "mariadb"], id: \.self) { s in
                        HStack(spacing: 5) {
                            StatusDot(on: act != nil && (svc[s] ?? running))
                            Text(s == "apache" ? "Apache" : "MariaDB").font(.system(size: bottom ? 11.5 : 12))
                        }
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, bottom ? 1 : 3)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(servicesHover || servicesOpen ? 0.10 : 0)))
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { servicesHover = $0 }
            .hoverPointer()
            .tip("Servicios de la versión activa")
            .popover(isPresented: $servicesOpen, arrowEdge: edge) {
                // (los recuadros de arriba no heredan el estilo de los botones de la ventana)
                ServicesView(close: { servicesOpen = false }).environmentObject(model).buttonStyle(PointerButtonStyle()).frame(width: dialogWidth(660), height: dialogHeight(470))
            }
            // (a la derecha de los servicios)
            powerButton(edge)
            Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: bottom ? 14 : 22)
            usageText()
        }
    }

    /// Lo de la versión: el logotipo de PHP, «PHP x.y» y «XAMPP-carpeta» (en la barra de estado, en una línea)
    @ViewBuilder
    func versionLabel(_ act: Install?) -> some View {
        HStack(spacing: bottom ? 8 : 9) {
            BrandLogo(name: "php", size: bottom ? 16 : 22)
            if bottom {
                // (en una línea: «PHP 8.4  XAMPP-8.4»)
                HStack(spacing: 6) {
                    Text(act.map { "PHP \($0.php)" } ?? "Ninguna versión activa").font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1).fixedSize()
                    Text(act.map { "XAMPP-\($0.folder)" } ?? "pulsa ▶ para arrancar una")
                        .font(act == nil ? Font.system(size: 10.5) : Font.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1).fixedSize()
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    // (siempre en una línea: el visor se ensancha antes que partir «XAMPP-8.5»)
                    Text(act.map { "PHP \($0.php)" } ?? "Ninguna versión activa").font(.system(size: 13, weight: .semibold))
                        .lineLimit(1).fixedSize()
                    if let a = act {
                        Text("XAMPP-\(a.folder)").font(.system(size: 10.5, design: .monospaced)).foregroundColor(.secondary)
                            .lineLimit(1).fixedSize()
                    } else {
                        Text("pulsa ▶ para arrancar una").font(.system(size: 10.5)).foregroundColor(.secondary)
                            .lineLimit(1).fixedSize()
                    }
                }
            }
        }
    }

    /// ▶ / ■ del visor: arranca la versión activa o la para y desactiva; sin ninguna activa, ▶ despliega
    /// las versiones instaladas para elegir cuál arrancar
    func powerButton(_ edge: Edge) -> some View {
        let d = model.data
        let active = d?.active ?? ""
        let on = !active.isEmpty && (d?.running ?? false)
        let tip = on ? "Parar y desactivar XAMPP-\(active)" : active.isEmpty ? "Arrancar una versión" : "Arrancar XAMPP-\(active)"
        let side: CGFloat = bottom ? 22 : 28
        return Button(action: {
            if active.isEmpty { powerOpen.toggle() } else { model.power() }
        }) {
            // (solo el icono, verde o rojo, sin recuadro; al pasar el ratón, un fondo suave)
            UIIcon(on ? "stop.fill" : "play.fill", size: bottom ? 13 : 17, weight: .semibold)
                .foregroundColor(on ? RED : GREEN)
                .frame(width: side, height: side)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(powerHover || powerOpen ? 0.10 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(d == nil || (active.isEmpty && (d?.installs.isEmpty ?? true)))
        .onHover { powerHover = $0 }
        .hoverPointer()
        .tip(tip)
        .popover(isPresented: $powerOpen, arrowEdge: edge) {
            let c = model.powerChoices()
            VStack(alignment: .leading, spacing: 2) {
                Text("Arrancar una versión").font(.system(size: 11)).foregroundColor(.secondary)
                    .padding(.horizontal, 8).padding(.bottom, 4)
                ForEach(c.installs) { i in
                    Button(action: { powerOpen = false; model.activate(i.folder) }) {
                        HStack(spacing: 10) {
                            BrandLogo(name: "php", size: 16)
                            Text("PHP \(i.php)").font(.system(size: 13))
                            Text("XAMPP-\(i.folder)").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                            Spacer(minLength: 12)
                            if i.folder == c.last {
                                Text("la última").font(.system(size: 11)).foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverPointer()
                }
            }
            .padding(8)
            .frame(minWidth: 280)
        }
    }

    /// Lo que gastan Nexum y sus servicios juntos: la CPU en % de todo el Mac (todos los núcleos son el
    /// 100 %) y la memoria en % de la del Mac. Al pasar el ratón, cada parte
    func usageText() -> some View {
        let u = model.usage ?? [:]
        let cores = Double(Swift.max(1, ProcessInfo.processInfo.activeProcessorCount))
        let total = Double(Swift.max(1, ProcessInfo.processInfo.physicalMemory))
        let cpu = u.values.reduce(0.0) { $0 + $1.cpu } / cores
        let mem = u.values.reduce(Int64(0)) { $0 + $1.mem }
        var lines = ["CPU \(fmtPercent(cpu)) · RAM \(fmtSize(mem))", ""]
        for (k, text) in USAGE_GROUPS {
            if let part = u[k], part.mem > 0 || part.cpu > 0 {
                lines.append("\(text): CPU \(fmtPercent(part.cpu / cores)) · \(fmtSize(part.mem))")
            }
        }
        return Text(model.usage == nil ? "CPU — · RAM —" : "CPU \(fmtPercent(cpu)) · RAM \(fmtPercent(100 * Double(mem) / total))")
            .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
            .lineLimit(1).fixedSize()
            .tip(lines.joined(separator: "\n"))
    }
}

/// «Cambiar de versión de PHP»: las instaladas, de la más nueva a la más vieja; la activa, marcada («● en marcha» o
/// «● activa») y sin acción; al pulsar otra, se activa (model.activate, que confirma lo que haga falta). Las filas
/// salen en abanico desde el lado de la barra, una tras otra (como nv_versions_fan de Linux)
struct VersionsFan: View {
    @EnvironmentObject var model: AppModel
    /// En la barra de estado: se abre hacia arriba y la fila más cercana es la de abajo
    let fromBottom: Bool
    let close: () -> Void

    var body: some View {
        let d = model.data
        let installs = (d?.installs ?? []).sorted { $0.php.compare($1.php, options: .numeric) == .orderedDescending }
        let count = installs.count
        return VStack(alignment: .leading, spacing: 2) {
            Text("Cambiar de versión de PHP").font(.system(size: 11)).foregroundColor(.secondary)
                .padding(.horizontal, 8).padding(.bottom, 4)
            ForEach(Array(installs.enumerated()), id: \.element.id) { n, i in
                // (la más cercana a la barra, primero)
                let step: Int = fromBottom ? count - 1 - n : n
                let delay: Double = 0.028 * Double(step)
                let from: CGFloat = fromBottom ? 5 : -5
                FanRow(delay: delay, from: from) {
                    row(i, active: i.folder == (d?.active ?? ""), running: d?.running ?? false)
                }
            }
        }
        .padding(8)
        .frame(minWidth: 300)
    }

    @ViewBuilder
    func row(_ i: Install, active: Bool, running: Bool) -> some View {
        let line = HStack(spacing: 10) {
            BrandLogo(name: "php", size: 16)
            Text("PHP \(i.php)").font(.system(size: 13))
            Text("XAMPP-\(i.folder)").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
            Spacer(minLength: 12)
            if active {
                Text(running ? "● en marcha" : "● activa").font(.system(size: 11))
                    .foregroundColor(running ? GREEN : Color.secondary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .contentShape(Rectangle())
        if active {
            line
        } else {
            Button(action: {
                close()
                DispatchQueue.main.async { model.activate(i.folder) }
            }) { line }
            .buttonStyle(PlainButtonStyle())
            .hoverPointer()
        }
    }
}

/// Una fila del abanico: aparece con su retardo, de transparente a opaca y deslizándose unos puntos hasta su sitio
/// (con offset: el recuadro no cambia de tamaño)
struct FanRow<Content: View>: View {
    let delay: Double
    let from: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var shown = false

    var body: some View {
        content()
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : from)
            .onAppear {
                withAnimation(.easeOut(duration: 0.15).delay(delay)) { shown = true }
            }
    }
}

/// Los correos sin leer, al lado del icono de Correo
struct MailBadge: View {
    let n: Int
    var body: some View {
        Text(n > 99 ? "99+" : "\(n)")
            .font(.system(size: 10.5, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(brand("mailpit")))
    }
}

/// Visor arriba (Apariencia), en la barra de arriba: el proyecto cargado (su logotipo y su nombre, sin recuadro: al
/// pulsarlo, Proyectos; a dónde apunta web.local ya lo dice la barra de abajo), sus botones (los de Personalizar
/// los botones, en su orden) en cuadrados pequeños con el nombre debajo, Unlink y ⋮, y Correo y Terminal iguales
/// que ellos. Todo el ancho que deje la barra; si no caben, se desplazan en horizontal sin ensanchar la ventana
struct TopVisorBar: View {
    @EnvironmentObject var model: AppModel
    @State private var whoHover = false

    var body: some View {
        let x = model.data != nil ? model.loadedEntry() : nil
        var c = model.visorConf
        c.compact = true
        // (los botones del cargado, Unlink, Correo y Terminal, como en Personalizar los botones: cuáles se ven y en
        // qué orden; ⋮, el último de todos. Sin proyecto cargado, solo Correo y Terminal)
        let items: [String: AnyView] = (x != nil && model.projects != nil) ? model.loadedItems(x!, model.projects!, c) : [:]
        let keys = c.order.filter { !c.hidden.contains($0) && (items[$0] != nil || $0 == "correo" || $0 == "terminal") }
        // (centrados en el hueco que les deja la barra; si no caben, se desplazan)
        return GeometryReader { geo in
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                who(x)
                separator()
                ForEach(keys, id: \.self) { k in
                    topItem(k, items)
                }
                if let x = x {
                    VisorButton(conf: c, name: "Más", icon: .symbol("ellipsis", Color.primary), tip: "") {
                        popMenu(model.moreItems(x))
                    }
                    .busyGuard(model.busy)
                }
            }
            .padding(.horizontal, 2)
            .frame(height: TOP_VISOR_SIDE + 4)
            .frame(minWidth: geo.size.width)
          }
        }
        .frame(maxWidth: .infinity)
        .frame(height: TOP_VISOR_SIDE + 4)
    }

    /// El proyecto cargado, sin borde ni fondo (un fondo suave al pasar el ratón, sin cambiar de tamaño ni de borde:
    /// los demás botones no se mueven): al pulsarlo, Proyectos
    func who(_ x: Project?) -> some View {
        let logo = x.flatMap { projectBrand($0) }
        return Button(action: { model.openTab("proyectos") }) {
            HStack(spacing: 8) {
                if let l = logo {
                    BrandLogo(name: l, size: 24)
                } else {
                    UIIcon("folder", size: 19).foregroundColor(.secondary).frame(width: 24, height: 24)
                }
                // (su nombre entero, sin cortar y sin el prefijo de su tipo: el logotipo ya lo dice)
                Text(x.map { shortProjectName($0.name) } ?? "Sin proyecto")
                    .font(.system(size: 13, weight: x == nil ? .regular : .bold))
                    .foregroundColor(x == nil ? Color.secondary : Color.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(whoHover ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { whoHover = $0 }
        .hoverPointer()
        .tip(x?.name ?? "Ningún proyecto cargado: elige uno en Proyectos")
    }

    /// Un botón del visor de arriba por su clave: Correo, Terminal o uno de los del proyecto cargado
    @ViewBuilder
    func topItem(_ k: String, _ items: [String: AnyView]) -> some View {
        if k == "correo" {
            mailSquare()
        } else if k == "terminal" {
            termSquare()
        } else if let v = items[k] {
            v
        }
    }

    func separator() -> some View {
        Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 30).padding(.horizontal, 4)
    }

    /// Correo, cuadrado como los botones, con su número de sin leer al lado del icono. Con el correo de pruebas
    /// apagado no sale
    /// (con «Solo el icono» en Personalizar los botones, sin el nombre y con el icono algo mayor, como los demás)
    @ViewBuilder
    func mailSquare() -> some View {
        let named = model.visorConf.style != "icono"
        if let m = model.data?.mail, m.on {
            Button(action: { model.openMail() }) {
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        BrandLogo(name: "mailpit", size: named ? TOP_VISOR_ICON : TOP_VISOR_ICON + 4)
                        if let n = model.mailUnread, n > 0 {
                            MailBadge(n: n)
                        }
                    }
                    if named {
                        Text("Correo").font(.system(size: TOP_VISOR_NAME)).lineLimit(1)
                    }
                }
            }
            .buttonStyle(SquareButton(side: TOP_VISOR_SIDE))
            .tip(model.mailTip(m))
        }
    }

    /// Terminal, cuadrado como los botones; marcado mientras la terminal de abajo está abierta (con «Solo el
    /// icono», sin el nombre)
    func termSquare() -> some View {
        let named = model.visorConf.style != "icono"
        let side: CGFloat = named ? TOP_VISOR_ICON : TOP_VISOR_ICON + 4
        return Button(action: { model.termOpen.toggle() }) {
            VStack(spacing: 3) {
                TintIcon("terminal", size: side * 0.8)
                    .frame(width: side, height: side)
                if named {
                    Text("Terminal").font(.system(size: TOP_VISOR_NAME)).lineLimit(1)
                }
            }
        }
        .buttonStyle(SquareButton(side: TOP_VISOR_SIDE, kind: model.termOpen ? "marcado" : ""))
        .tip("Mostrar u ocultar la terminal")
    }
}

/// Prefijos que se quitan del nombre del proyecto en el visor de arriba (el logotipo ya dice su tipo), como
/// PROJECT_NAME_PREFIXES de Linux
let PROJECT_NAME_PREFIXES = ["dob-prestashop-", "dob-wordpress-"]

/// El nombre de un proyecto para el visor de arriba, sin el prefijo de su tipo (en Proyectos, entero)
func shortProjectName(_ name: String) -> String {
    for p in PROJECT_NAME_PREFIXES where name.hasPrefix(p) && name.count > p.count {
        return String(name.dropFirst(p.count))
    }
    return name
}

/// El logotipo del tipo de proyecto (visor de arriba y Proyectos), por sus ficheros, como project_brand de Linux:
/// WordPress y PrestaShop (su tipo); con composer.json, Laravel, Drupal, Magento, Joomla o Symfony; con package.json,
/// Astro, Next.js, Nuxt, Angular, Svelte, Vue o React, y si no, Node. nil si no se sabe (se pone la carpeta). Solo lee
/// ficheros: no ejecuta nada
func projectBrand(_ x: Project) -> String? {
    if x.kind == "wp" { return "wordpress" }
    if x.kind == "ps" { return "prestashop" }
    // (la ventana se redibuja a menudo: lo leído vale medio minuto)
    if let c = projectBrandCache[x.name], Date().timeIntervalSince(c.0) < 30 { return c.1 }
    let found = projectBrandRead(x)
    projectBrandCache[x.name] = (Date(), found)
    return found
}

private var projectBrandCache: [String: (Date, String?)] = [:]

func projectBrandRead(_ x: Project) -> String? {
    let path = HTDOCS + "/" + x.name
    let fm = FileManager.default
    func isFile(_ rel: String) -> Bool {
        var dir: ObjCBool = false
        return fm.fileExists(atPath: path + "/" + rel, isDirectory: &dir) && !dir.boolValue
    }
    func isDir(_ rel: String) -> Bool {
        var dir: ObjCBool = false
        return fm.fileExists(atPath: path + "/" + rel, isDirectory: &dir) && dir.boolValue
    }
    /// (las claves de esas secciones de un JSON pequeño del proyecto; vacío si no se puede leer)
    func keys(_ rel: String, _ sections: [String]) -> Set<String> {
        guard let h = FileHandle(forReadingAtPath: path + "/" + rel) else { return [] }
        let data = h.readData(ofLength: 400_000)
        h.closeFile()
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        var out = Set<String>()
        for s in sections {
            if let m = o[s] as? [String: Any] { out.formUnion(m.keys) }
        }
        return out
    }
    let req = keys("composer.json", ["require", "require-dev"])
    if isFile("artisan") || req.contains("laravel/framework") { return "laravel" }
    if req.contains("drupal/core") || req.contains("drupal/core-recommended") || isFile("core/lib/Drupal.php") { return "drupal" }
    if req.contains(where: { $0.hasPrefix("magento/") }) || isFile("app/etc/env.php") { return "magento" }
    if isFile("libraries/src/Version.php") && isDir("administrator") { return "joomla" }
    if req.contains("symfony/framework-bundle") || (isFile("bin/console") && isFile("symfony.lock")) { return "symfony" }
    if isFile("package.json") {
        let deps = keys("package.json", ["dependencies", "devDependencies"])
        let order: [(String, String)] = [("astro", "astro"), ("next", "nextdotjs"), ("nuxt", "nuxtdotjs"),
                                         ("@angular/core", "angular"), ("@sveltejs/kit", "svelte"), ("svelte", "svelte"),
                                         ("vue", "vuedotjs"), ("react", "react")]
        for (dep, name) in order where deps.contains(dep) { return name }
        return "node"
    }
    return nil
}

extension AppModel {
    /// El mensaje del botón Correo (arriba, en los dos visores)
    func mailTip(_ m: MailState) -> String {
        if !m.installed { return "Mailpit no está instalado" }
        if !m.running { return "Arranca la versión activa para ver el correo" }
        if let n = mailUnread, n > 0 { return "Correo de las webs (Mailpit): \(n) sin leer" }
        return "Correo de las webs (Mailpit)"
    }
}

struct MainMenu: View {
    @EnvironmentObject var model: AppModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            item(model.isDark ? "Tema claro" : "Tema oscuro", model.isDark ? "sun.max" : "moon") { model.toggleTheme() }
            Divider().padding(.vertical, 4)
            item("Editar vhosts", "doc.text") { model.editVhosts() }
            item("Editar /etc/hosts", "network") { model.editHosts() }
            Divider().padding(.vertical, 4)
            item("Volver a leer las versiones", "arrow.clockwise") { model.reload(branches: true) }
            item("Buscar actualizaciones", "arrow.down.circle") { model.checkUpdates() }
            item("Abrir el panel en Terminal", "terminal") { model.openTerminal() }
            item("Carpeta de registros", "folder") { showFolder(LOG_DIR) }
            Divider().padding(.vertical, 4)
            item("Ayuda", "questionmark.circle") { model.showHelp() }
            item("Novedades", "star") { model.showChanges() }
            item("Acerca de \(model.data?.name ?? "Nexum Dev Stack")", "info.circle") { model.showAbout() }
        }
        .padding(6)
        .frame(width: 270)
    }

    /// (se cierra el menú antes: las opciones pueden abrir un diálogo)
    func item(_ text: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        MenuRow(text: text, symbol: symbol) {
            close()
            DispatchQueue.main.async { action() }
        }
    }
}

struct MenuRow: View {
    let text: String
    let symbol: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                UIIcon(symbol).frame(width: 18)
                Text(text)
                Spacer(minLength: 0)
            }
            .foregroundColor(hover ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 5).fill(hover ? ACCENT : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover = $0 }
    }
}

/// Avisos: XAMPP oficial, tablas del sistema, phpMyAdmin antiguo, protecciones, certificados y
/// procesos de otras versiones
struct WarningsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let c = model.updatesPending {
                Card("Hay parches nuevos (\(c.items.count))",
                     "Lo de ahora sigue funcionando mientras se actualiza (se puede seguir en segundo plano). Si no quieres cambiar nada, «Ahora no» lo deja hasta que salga otro parche; siguen en Sistema, General, Parches nuevos.") {
                    WideRow("Conviene ponerlos: son parches de seguridad",
                        (c.items.prefix(6).map { "• " + $0 } + (c.items.count > 6 ? ["…y \(c.items.count - 6) más"] : [])).joined(separator: "\n")) {
                            Button("Ahora no") { model.ignoreUpdates(c) }
                            Button("Actualizar todo") { model.updateComponents(c) }
                                .buttonStyle(OutlineButton(kind: "primary"))
                                .busyGuard(model.busy)
                        }
                }
            }
            if let d = model.data {
                if warningCount(d) == 0 && model.updatesPending == nil {
                    Text("No hay avisos.").foregroundColor(.secondary)
                }
                if d.official {
                    Card("Hay un XAMPP oficial en /Applications/XAMPP",
                         "Este gestor necesita que /Applications/XAMPP sea un enlace a la versión activa. Al apartarlo se copian sus BBDD, sus proyectos y sus vhosts, y se mueve a /Applications/XAMPP-oficial-<fecha>, sin borrar nada.") {
                        Row("XAMPP oficial") {
                            Button("Apartar…") { model.setAside() }.busyGuard(model.busy)
                        }
                    }
                }
                // (en un Group: el bloque pasaria de las 10 vistas que admite SwiftUI en macOS 12)
                Group {
                    if !d.dbsysVersion.isEmpty {
                        Card("Tablas del sistema de MariaDB antiguas",
                             "Las tablas del sistema (mysql.*) son de una MariaDB anterior y el servidor escribe un error cada vez que las usa: su registro de errores no para de crecer. Repararlas las pone al día con el mariadb-upgrade de la versión, sin tocar las BBDD de los proyectos (si quieres, después de guardar una copia en ~/nexum-backups), y vacía el registro si es grande.") {
                            Row("MariaDB de XAMPP-\(d.dbsysVersion)", "Registro de errores: \(fmtSize(d.dbsysLog))", trailing: {
                                Button("Repararlas") { model.repairDbSystem() }
                                    .buttonStyle(OutlineButton(kind: "primary"))
                                    .busyGuard(model.busy)
                            })
                        }
                    }
                    let oldPma = d.installs.filter { pmaOutdated($0.php, $0.pma) }
                    if !oldPma.isEmpty {
                        Card("phpMyAdmin antiguo",
                             "Estas versiones tienen un phpMyAdmin con fallos de seguridad que ya están corregidos. Actualizarlo pone el más nuevo que admite su PHP, con la misma configuración; el anterior queda en phpmyadmin.anterior.") {
                            Row("phpMyAdmin con fallos corregidos después",
                                oldPma.map { "XAMPP-\($0.folder) (\($0.pma))" }.joined(separator: ", "), trailing: {
                                Button("Actualizarlos") { model.updatePma("--todas") }
                                    .buttonStyle(OutlineButton(kind: "primary"))
                                    .busyGuard(model.busy)
                            })
                        }
                    }
                    Group {
                        if !d.unsecured.isEmpty {
                            Card("A algunas versiones les faltan protecciones",
                                 "Les falta algo de lo que pone el gestor: solo para este Mac, phpMyAdmin cerrado a otras webs, MariaDB sin acceso a los ficheros del Mac... (o su carpeta no es de root y no se arrancarían). Protegerlas lo pone, como en la activa; pide la contraseña de administrador.") {
                                Row("Versiones sin proteger", d.unsecured.map { "XAMPP-" + $0 }.joined(separator: ", "), trailing: {
                                    Button("Protegerlas") { model.secureAll() }
                                        .buttonStyle(OutlineButton(kind: "primary"))
                                        .busyGuard(model.busy)
                                })
                            }
                        }
                        if !d.apacheOld.isEmpty {
                            Card("Apache sigue con la configuración de antes",
                                 "Se ha cambiado su configuración (la seguridad, la barrera entre webs...) y Apache no se ha recargado: hasta reiniciarlo, sigue con lo de antes.") {
                                Row("XAMPP-\(d.apacheOld)", "Reiniciar Apache para que la use", trailing: {
                                    Button("Reiniciar Apache") { model.reloadApacheConfig() }
                                        .buttonStyle(OutlineButton(kind: "primary"))
                                        .busyGuard(model.busy)
                                })
                            }
                        }
                    }
                }
                Group {
                    if !d.certs.isEmpty || !d.cas.isEmpty {
                        Card(certsTitle(d), certsText(d)) {
                            Row("Proyectos con https", certsNames(d), trailing: {
                                Button("Arreglarlos") { model.fixCerts() }
                                    .buttonStyle(OutlineButton(kind: "primary"))
                                    .busyGuard(model.busy)
                            })
                        }
                    }
                    // Su certificado propio no lo acepta el navegador: avisa al abrirlos y las
                    // herramientas que lo manejan (Claude in Chrome) no pueden pasar del aviso
                    if !d.untrusted.isEmpty {
                        Card("El navegador avisa al abrir estos proyectos",
                             "Safari y Chrome no aceptan todavía su certificado: sale «La conexión no es privada» y las herramientas que manejan el navegador (como Claude in Chrome) no pueden abrirlos. Confiar hace que acepte el certificado propio de cada proyecto, que solo vale para su dominio: no sirve para falsificar ninguna otra web. El de una tienda con dominio real, solo mientras esté falseada en /etc/hosts: al dejar de falsearla, deja de aceptarlo (con su clave se podría suplantar la web de verdad). El Mac pide tu contraseña una vez por proyecto. Después, si Chrome estaba abierto, ciérralo y vuelve a abrirlo.") {
                            Row("Proyectos que avisan en el navegador",
                                d.untrusted.prefix(6).joined(separator: ", ") + (d.untrusted.count > 6 ? " y \(d.untrusted.count - 6) más" : ""),
                                trailing: {
                                Button("Confiar") { model.trustCerts() }
                                    .buttonStyle(OutlineButton(kind: "primary"))
                                    .busyGuard(model.busy)
                            })
                        }
                    }
                    // Tiendas con dominio real cuyo certificado aún acepta el navegador y ya no están
                    // falseadas (hosts cambiado a mano o contraseña cancelada)
                    if !d.stale.isEmpty {
                        Card("El navegador acepta webs reales que ya no están falseadas",
                             "El navegador aceptaba su certificado mientras estaban falseadas en /etc/hosts. Ya no lo están, así que el navegador va a la web de verdad, y con la clave de ese certificado (Apache la tiene en memoria) se la podría suplantar. Quitar hace que deje de aceptarlo; el Mac pide tu contraseña una vez por web. Después, si Chrome estaba abierto, ciérralo y vuelve a abrirlo.") {
                            Row("Webs reales que acepta el navegador",
                                d.stale.prefix(6).joined(separator: ", ") + (d.stale.count > 6 ? " y \(d.stale.count - 6) más" : ""),
                                trailing: {
                                Button("Quitar") { model.untrustCerts() }
                                    .buttonStyle(OutlineButton(kind: "primary"))
                                    .busyGuard(model.busy)
                            })
                        }
                    }
                    let vulnerable = d.installs.filter { php2shellVulnerable(d.php2shell[$0.folder] ?? "ok") }
                    if !vulnerable.isEmpty {
                        Card("Versiones vulnerables a PHP2Shell",
                             "CVE-2026-109618 y CVE-2026-109619: un formulario de un proyecto puede acabar ejecutando código en tu Mac. Las de 8.2 a 8.5 se arreglan con el último parche de su rama; las 7.4, 8.0 y 8.1, con el parche oficial de seguridad. Actualízalas en el menú ⋯ de cada versión (Versiones de PHP).") {
                            Row("PHP vulnerable",
                                vulnerable.map { "XAMPP-\($0.folder) (PHP \($0.php))" }.joined(separator: ", "), trailing: {
                                Button("Ver las versiones") { model.openTab("versiones") }
                                    .buttonStyle(OutlineButton(kind: "primary"))
                            })
                        }
                    }
                    if !d.stray.isEmpty {
                        Card("Hay procesos de otras versiones en memoria",
                             "Solo debería estar en memoria la versión montada\(d.active.isEmpty ? "" : " (XAMPP-\(d.active))"). Ocupan memoria y pueden bloquear los puertos 80, 443 y 3306.") {
                            Row("Procesos que sobran", d.stray) {
                                Button("Cerrarlos") { model.closeStray() }.busyGuard(model.busy)
                            }
                        }
                    }
                    if !d.orphans.isEmpty {
                        Card("Hay vhosts de carpetas que ya no existen",
                             "Estos proyectos tienen su vhost, pero su carpeta ya no está en \(HTDOCS) (se borró, se movió o no se ha vuelto a clonar). Apache arranca igual, pero avisa de cada uno al arrancar («DocumentRoot … does not exist»). Quitarlos solo cambia el fichero de vhosts: las carpetas, las BBDD y /etc/hosts no se tocan.") {
                            ForEach(d.orphans, id: \.folder) { o in
                                Row(o.folder, o.domains.isEmpty ? "sin dominio" : o.domains)
                            }
                            Row("Quitar sus vhosts", "Pide la contraseña de administrador") {
                                Button("Quitarlos") { model.removeOrphanVhosts() }.busyGuard(model.busy)
                            }
                        }
                    }
                }
            }
        }
    }
}
