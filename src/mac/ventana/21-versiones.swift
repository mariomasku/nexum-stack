// MARK: - Versiones de PHP

struct VersionsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        WidePage {
            if let d = model.data {
                HStack(spacing: 10) {
                    PageTitle(title: "Versiones de PHP",
                              sub: "Cada versión con su Apache, MariaDB y sus propias BBDD. Soporte y parches, según php.net",
                              logo: "php")
                    Spacer(minLength: 8)
                    Button(action: { model.panel = .components("") }) {
                        HStack(spacing: 6) {
                            LogoShape(d: LOGO_PATHS["apache"] ?? "").fill(brand("apache")).frame(width: 15, height: 15)
                            Text("Componentes")
                        }
                    }
                    .buttonStyle(OutlineButton())
                    .tip("Componentes de cada versión")
                    Button(action: { model.panel = .install }) { Label("Instalar versión…", systemImage: "plus") }
                        .buttonStyle(OutlineButton(kind: "primary"))
                        .disabled(model.busy)
                }
                TableBox {
                    TableHead(cols: [("Versión", 200), ("PHP", 70), ("Soporte", 170), ("Último parche", 160), ("BBDD", 40), ("", 0)])
                    ForEach(d.installs) { inst in
                        Divider()
                        versionRow(inst, d)
                    }
                    if d.installs.isEmpty {
                        Divider()
                        Text("Ninguna versión instalada: instala la primera con «Instalar versión…».")
                            .foregroundColor(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let e = model.branchesError {
                    Text("No se ha podido consultar php.net: \(e)").font(.caption).foregroundColor(.secondary)
                }
            } else if let e = model.loadError {
                Card("No se han podido leer las versiones instaladas") {
                    Row(e) { Button("Reintentar") { model.reload(branches: true) } }
                }
            } else {
                Loading()
            }
        }
    }

    func versionRow(_ inst: Install, _ d: AppData) -> some View {
        let act = inst.folder == d.active
        let b = model.branch(inst.php)
        let newer = model.newerPatch(inst)
        let pd = model.phpDates[inst.folder]
        let date: String? = (pd?.count ?? 0) >= 2 && pd?[0] == inst.php ? pd?[1] : nil
        return HoverRow { hover in
            HStack(spacing: 8) {
                StatusDot(on: act && d.running)
                VStack(alignment: .leading, spacing: 1) {
                    Text("XAMPP-\(inst.folder)").font(.system(size: 12.5, design: .monospaced))
                    Text(date.map { "publicada el \(fmtDay($0))" } ?? "/Library/Nexum/XAMPP-\(inst.folder)")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .col(200)
            .tip("/Library/Nexum/XAMPP-\(inst.folder)")
            Text(inst.php).font(.system(size: 12.5, design: .monospaced)).col(70)
            supportCell(b).col(170)
            patchCell(inst, b, newer).col(160)
            Text("\((d.dbs[inst.folder] ?? []).count)").font(.system(size: 12.5, design: .monospaced))
                .foregroundColor(.secondary).col(40)
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                if act {
                    // (del mismo tamaño que «Activar»)
                    Text("Activa").font(.system(size: 12.5, weight: .semibold)).foregroundColor(ACCENT)
                        .frame(width: 64)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(ACCENT.opacity(0.13)))
                } else {
                    // (como «Cargar» en Proyectos: solo en la versión con el ratón encima)
                    Button(action: { model.activate(inst.folder) }) { Text("Activar").frame(width: 64) }
                        .buttonStyle(OutlineButton(kind: "primary"))
                        .disabled(model.busy || d.official)
                        .opacity(hover ? 1 : 0)
                        .allowsHitTesting(hover)
                }
                versionMenu(inst, newer)
            }
            .col(0)
        }
    }

    @ViewBuilder
    func supportCell(_ b: Branch?) -> some View {
        if let b = b {
            let when = b.phpState == "security" ? b.securityEnd : (b.phpState == "stable" ? b.activeEnd : "")
            VStack(alignment: .leading, spacing: 1) {
                StatePill(b: b)
                if !when.isEmpty {
                    Text((b.phpState == "security" ? "seguridad hasta " : "hasta ") + fmtMonth(when))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        } else {
            Text(model.branches == nil && model.branchesError == nil ? "consultando php.net…" : "—")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    /// Último parche: «Actualizado» en verde o el parche nuevo que hay; encima, en rojo, si es
    /// vulnerable a PHP2Shell (con la explicación al pasar el ratón)
    @ViewBuilder
    func patchCell(_ inst: Install, _ b: Branch?, _ newer: String?) -> some View {
        let st = model.data?.php2shell[inst.folder] ?? "ok"
        VStack(alignment: .leading, spacing: 1) {
            if php2shellVulnerable(st) {
                Text("Vulnerable (PHP2Shell)").font(.caption.weight(.bold)).foregroundColor(RED)
                    .tip(php2shellText(st, inst.php).isEmpty ? "" : "Vulnerable a PHP2Shell")
            }
            if let b = b, b.latest == inst.php {
                if st == "parcheable" {
                    Text("Parche de seguridad disponible").font(.caption).foregroundColor(ACCENT)
                } else if !php2shellVulnerable(st) {
                    // (vulnerable no está «Actualizado», aunque tenga el último parche de su rama)
                    Text("Actualizado").font(.caption.weight(.semibold)).foregroundColor(GREEN)
                }
                if st == "parche" {
                    Text("+ parche de seguridad (\(PHP2SHELL_DATE))").font(.caption).foregroundColor(.secondary)
                        .tip("Parche oficial contra PHP2Shell")
                }
            } else if let b = b, let n = newer {
                Text("PHP \(n) disponible").font(.caption).foregroundColor(ACCENT)
                if !b.date.isEmpty {
                    Text(fmtDay(b.date)).font(.caption).foregroundColor(.secondary)
                }
            } else if !php2shellVulnerable(st) {
                Text("—").foregroundColor(.secondary)
            }
        }
    }

    /// Menú ⋯ de una versión. Actualizar: las XAMPP-X.Y de antes se ponen al día en su carpeta; las
    /// XAMPP-X.Y.Z, instalando el parche nuevo a su lado (y pasándole después sus BBDD). Las 7.4.33,
    /// 8.0.30 y 8.1.34 sin el parche de seguridad se rehacen con él. Sin datos de php.net, se
    /// comprueba al pulsar
    func versionMenu(_ inst: Install, _ newer: String?) -> some View {
        let updatable = inst.folder.split(separator: ".").count == 2
        let st = model.data?.php2shell[inst.folder] ?? "ok"
        return OutlineMenu(nil, symbol: "ellipsis", bordered: false) {
            Button("Componentes…") { model.panel = .components(inst.folder) }
            if st == "parcheable" && newer == nil {
                Button("Poner el parche de seguridad (PHP2Shell)…") { model.update(inst.folder) }
            } else if updatable && (newer != nil || model.branch(inst.php) == nil) {
                Button(newer.map { "Actualizar a PHP \($0)" } ?? "Buscar parches nuevos") { model.update(inst.folder) }
            } else if let n = newer {
                Button("Actualizar a PHP \(n)…") { model.upgradePinned(inst, n) }
            }
            if pmaOutdated(inst.php, inst.pma) {
                Button("Actualizar phpMyAdmin") { model.updatePma(inst.folder) }
            }
            Button("Desinstalar…") {
                if inst.blocker.isEmpty { model.remove(inst) } else { message("No se puede desinstalar", inst.blocker) }
            }
        }
        .disabled(model.busy)
    }
}

/// Componentes de cada versión en una tabla, con el logotipo de cada uno
struct ComponentsPanel: View {
    @EnvironmentObject var model: AppModel
    let only: String

    var body: some View {
        let list = (model.data?.installs ?? []).filter { only.isEmpty || $0.folder == only }
        let heads: [(String, String)] = [("PHP", "logo:php"), ("Apache", "logo:apache"), ("MariaDB", "logo:mariadb"),
                                         ("FTP", "arrow.up.arrow.down"), ("Perl", "logo:perl"), ("PMA", "logo:phpmyadmin")]
        return TableBox {
            HStack(spacing: 12) {
                Text("VERSIÓN").font(.system(size: 10.5, weight: .semibold)).foregroundColor(.secondary).col(150)
                ForEach(heads, id: \.0) { h in
                    HStack(spacing: 5) {
                        if h.1.hasPrefix("logo:") {
                            let n = String(h.1.dropFirst(5))
                            LogoShape(d: LOGO_PATHS[n] ?? "").fill(brand(n)).frame(width: 14, height: 14)
                        } else {
                            Image(systemName: h.1).font(.system(size: 11)).foregroundColor(.orange)
                        }
                        Text(h.0.uppercased()).font(.system(size: 10.5, weight: .semibold)).foregroundColor(.secondary)
                    }
                    .col(78)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))
            ForEach(list) { inst in
                Divider()
                HStack(spacing: 12) {
                    Text("XAMPP-\(inst.folder)").font(.system(size: 12, design: .monospaced)).col(150)
                    ForEach(Array([inst.php, inst.apache, inst.mariadb, inst.ftp, inst.perl].enumerated()), id: \.offset) { _, v in
                        Text(v).font(.system(size: 11.5, design: .monospaced)).col(78)
                    }
                    Text(inst.pma).font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(pmaOutdated(inst.php, inst.pma) ? RED : Color.primary)
                        .col(78)
                        .tip(pmaOutdated(inst.php, inst.pma) ? "phpMyAdmin antiguo: actualízalo en ⋯" : "")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
    }
}
