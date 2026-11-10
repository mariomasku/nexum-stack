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
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .opacity(pulse ? 0.35 : 1)
                    .offset(y: pulse ? 2 : -2)
                // (lo que hace, con la primera palabra del título: «Actualizando…», «Instalando…»)
                Text((task.title.split(separator: " ").first.map(String.init) ?? "En marcha") + "…")
                    .font(.system(size: 11.5, weight: .semibold))
                if let r = task.pctText.range(of: "%") {
                    Text(String(task.pctText[..<r.upperBound])).font(.system(size: 11.5, weight: .semibold).monospacedDigit())
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
    @State private var servicesOpen = false
    @State private var powerOpen = false
    @State private var powerHover = false
    @State private var servicesHover = false
    @State private var warnOpen = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 0) {
                    title(model.data?.name ?? "Nexum Dev Stack")
                    // (con la versión del programa detrás)
                    Text("Entornos PHP y Docker" + ((model.data?.version).map { $0.isEmpty ? "" : "  ·  v\($0)" } ?? ""))
                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            // (la tarea en segundo plano, a la izquierda del visor; el menú, justo a su derecha, como en Linux)
            if model.taskHidden, let t = model.task {
                TaskBadge(task: t)
            }
            visor()
            menuButton()
            Spacer(minLength: 12)
            mailButton()
            // (la terminal de abajo de la ventana: se enseña y se esconde; en lugar de Localhost)
            Button(action: { model.termOpen.toggle() }) {
                Label("Terminal", systemImage: "terminal")
            }
            .buttonStyle(OutlineButton(kind: model.termOpen ? "primary" : ""))
            .tip("Mostrar u ocultar la terminal")
            warnings()
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
            Image(systemName: "line.3.horizontal").font(.system(size: 17, weight: .medium))
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .hoverPointer()
        .tip("Menú")
        .popover(isPresented: $menuOpen, arrowEdge: .bottom) {
            MainMenu(close: { menuOpen = false }).environmentObject(model)
        }
    }

    func visor() -> some View {
        let d = model.data
        let act = d.flatMap { dd in dd.installs.first(where: { $0.folder == dd.active }) }
        let running = d?.running ?? false
        let svc = Dictionary((model.services ?? []).map { ($0.name, $0.running) }, uniquingKeysWith: { a, _ in a })
        return HStack(spacing: 9) {
            LogoShape(d: LOGO_PATHS["php"] ?? "").fill(brand("php")).frame(width: 22, height: 22)
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
            Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 22)
            // Apache y MariaDB con su punto: al pulsarlos, sus servicios (arrancarlos, pararlos o reiniciarlos,
            // y la versión entera)
            Button(action: { servicesOpen.toggle() }) {
                HStack(spacing: 9) {
                    ForEach(["apache", "mariadb"], id: \.self) { s in
                        HStack(spacing: 5) {
                            StatusDot(on: act != nil && (svc[s] ?? running))
                            Text(s == "apache" ? "Apache" : "MariaDB").font(.system(size: 12))
                        }
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(servicesHover || servicesOpen ? 0.10 : 0)))
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { servicesHover = $0 }
            .hoverPointer()
            .tip("Servicios de la versión activa")
            .popover(isPresented: $servicesOpen, arrowEdge: .bottom) {
                // (los recuadros de arriba no heredan el estilo de los botones de la ventana)
                ServicesView(close: { servicesOpen = false }).environmentObject(model).buttonStyle(PointerButtonStyle()).frame(width: 660, height: 470)
            }
            // (a la derecha de los servicios)
            powerButton()
            Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 22)
            usageText()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(SoftSunken(radius: 12))
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
    }

    /// ▶ / ■ del visor: arranca la versión activa o la para y desactiva; sin ninguna activa, ▶ despliega
    /// las versiones instaladas para elegir cuál arrancar
    func powerButton() -> some View {
        let d = model.data
        let active = d?.active ?? ""
        let on = !active.isEmpty && (d?.running ?? false)
        let tip = on ? "Parar y desactivar XAMPP-\(active)" : active.isEmpty ? "Arrancar una versión" : "Arrancar XAMPP-\(active)"
        return Button(action: {
            if active.isEmpty { powerOpen.toggle() } else { model.power() }
        }) {
            // (solo el icono, verde o rojo, sin recuadro; al pasar el ratón, un fondo suave)
            Image(systemName: on ? "stop.fill" : "play.fill").font(.system(size: 17, weight: .semibold))
                .foregroundColor(on ? RED : GREEN)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(powerHover || powerOpen ? 0.10 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(d == nil || (active.isEmpty && (d?.installs.isEmpty ?? true)))
        .onHover { powerHover = $0 }
        .hoverPointer()
        .tip(tip)
        .popover(isPresented: $powerOpen, arrowEdge: .bottom) {
            let c = model.powerChoices()
            VStack(alignment: .leading, spacing: 2) {
                Text("Arrancar una versión").font(.system(size: 11)).foregroundColor(.secondary)
                    .padding(.horizontal, 8).padding(.bottom, 4)
                ForEach(c.installs) { i in
                    Button(action: { powerOpen = false; model.activate(i.folder) }) {
                        HStack(spacing: 10) {
                            LogoShape(d: LOGO_PATHS["php"] ?? "").fill(brand("php")).frame(width: 16, height: 16)
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

    /// Correo de pruebas: la bandeja de Mailpit, con los correos sin leer (se pregunta solo con la
    /// ventana a la vista). Con el correo de pruebas apagado no sale
    @ViewBuilder
    func mailButton() -> some View {
        if let m = model.data?.mail, m.on {
            Button(action: { model.openMail() }) {
                HStack(spacing: 6) {
                    LogoShape(d: LOGO_PATHS["mailpit"] ?? "").fill(brand("mailpit")).frame(width: 15, height: 15)
                    Text("Correo")
                    if let n = model.mailUnread, n > 0 {
                        Text(n > 99 ? "99+" : "\(n)")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(brand("mailpit")))
                    }
                }
            }
            .buttonStyle(OutlineButton())
            .tip(mailTip(m))
        }
    }

    func mailTip(_ m: MailState) -> String {
        if !m.installed { return "Mailpit no está instalado" }
        if !m.running { return "Arranca la versión activa para ver el correo" }
        if let n = model.mailUnread, n > 0 { return "Correo de las webs (Mailpit): \(n) sin leer" }
        return "Correo de las webs (Mailpit)"
    }

    /// Los avisos (lo que antes iba arriba de Versiones) en un solo botón con cuántos hay
    @ViewBuilder
    func warnings() -> some View {
        let n = (model.data.map { warningCount($0) } ?? 0) + (model.updatesPending != nil ? 1 : 0)
        if model.data != nil, n > 0 {
            Button(action: { warnOpen.toggle() }) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text("\(n)").font(.system(size: 12, weight: .bold))
                }
            }
            .buttonStyle(OutlineButton())
            .tip("Avisos")
            .popover(isPresented: $warnOpen, arrowEdge: .bottom) {
                ScrollView {
                    WarningsView().environmentObject(model).buttonStyle(PointerButtonStyle()).padding(18)
                }
                .frame(width: 620, height: 480)
            }
        }
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
                Image(systemName: symbol).frame(width: 18)
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
                     "Lo de ahora sigue funcionando mientras se actualiza (se puede seguir en segundo plano). Si no quieres cambiar nada, «Ahora no» lo deja hasta que salga otro parche; siguen en Configuración, General, Parches nuevos.") {
                    Row("Conviene ponerlos: son parches de seguridad",
                        (c.items.prefix(6).map { "• " + $0 } + (c.items.count > 6 ? ["…y \(c.items.count - 6) más"] : [])).joined(separator: "\n"),
                        trailing: {
                            Button("Ahora no") { model.ignoreUpdates(c) }
                            Button("Actualizar todo") { model.updateComponents(c) }
                                .buttonStyle(OutlineButton(kind: "primary"))
                                .disabled(model.busy)
                        })
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
                            Button("Apartar…") { model.setAside() }.disabled(model.busy)
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
                                    .disabled(model.busy)
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
                                    .disabled(model.busy)
                            })
                        }
                    }
                    if !d.unsecured.isEmpty {
                        Card("A algunas versiones les faltan protecciones",
                             "Les falta algo de lo que pone el gestor: solo para este Mac, phpMyAdmin cerrado a otras webs, MariaDB sin acceso a los ficheros del Mac... (o su carpeta no es de root y no se arrancarían). Protegerlas lo pone, como en la activa; pide la contraseña de administrador.") {
                            Row("Versiones sin proteger", d.unsecured.map { "XAMPP-" + $0 }.joined(separator: ", "), trailing: {
                                Button("Protegerlas") { model.secureAll() }
                                    .buttonStyle(OutlineButton(kind: "primary"))
                                    .disabled(model.busy)
                            })
                        }
                    }
                }
                Group {
                    if !d.certs.isEmpty || !d.cas.isEmpty {
                        Card("Certificados en los que confía todo el Mac", certsText(d)) {
                            Row("Proyectos con https", certsNames(d), trailing: {
                                Button("Arreglarlos") { model.fixCerts() }
                                    .buttonStyle(OutlineButton(kind: "primary"))
                                    .disabled(model.busy)
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
                                    .disabled(model.busy)
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
                                    .disabled(model.busy)
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
                                Button("Cerrarlos") { model.closeStray() }.disabled(model.busy)
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
                                Button("Quitarlos") { model.removeOrphanVhosts() }.disabled(model.busy)
                            }
                        }
                    }
                }
            }
        }
    }
}
