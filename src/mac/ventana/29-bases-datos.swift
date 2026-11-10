// MARK: - Pestaña Bases de datos

struct DatabasesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        WidePage {
            if let d = model.data {
                head(d)
                cards(d)
                // Subir o actualizar una BBDD: antes de la tabla, en un visor hundido
                importCard(d)
                HStack(spacing: 10) {
                    SearchField(text: $model.dbQuery, placeholder: "Buscar una BBDD o su proyecto").frame(width: 300)
                    Spacer(minLength: 8)
                    Text("Solo la versión activa").font(.caption).foregroundColor(.secondary)
                    Toggle("", isOn: $model.dbOnlyActive).toggleStyle(SwitchToggleStyle()).labelsHidden().controlSize(.small)
                }
                dbTable(d)
            } else {
                Loading()
            }
        }
        .sheet(item: $model.projectReq) { req in
            ProjectSheet(req: req).environmentObject(model).buttonStyle(PointerButtonStyle())
        }
        .onAppear {
            // (desde la 1.39.5 ninguna versión se ve desplegada al entrar, tampoco la activa)
            if model.backups == nil { model.refreshBackups() }
        }
    }

    func head(_ d: AppData) -> some View {
        let act = d.installs.first(where: { $0.folder == d.active })
        return HStack(spacing: 10) {
            PageTitle(title: "Bases de datos", sub: "Cada versión con su MariaDB y sus BBDD (sin las del sistema)")
            Spacer(minLength: 8)
            Button(action: { openURL("http://127.0.0.1/phpmyadmin/") }) {
                HStack(spacing: 6) {
                    LogoShape(d: LOGO_PATHS["phpmyadmin"] ?? "").fill(brand("phpmyadmin")).frame(width: 15, height: 15)
                    Text("phpMyAdmin")
                }
            }
            .buttonStyle(OutlineButton())
            .disabled(act == nil || !d.running)
            .tip("phpMyAdmin de la versión activa")
            Button(action: { model.createDb() }) { Label("Nueva BBDD…", systemImage: "plus") }
                .buttonStyle(OutlineButton(kind: "primary"))
                .disabled(act == nil || model.busy)
                .tip("Crear una BBDD vacía")
        }
    }

    /// Cuántas hay, en la activa, la última que ha cambiado y lo que ocupan (y lo libre del disco). Las
    /// copias de seguridad, en Configuración
    func cards(_ d: AppData) -> some View {
        let act = d.installs.first(where: { $0.folder == d.active })
        let all = d.installs.flatMap { i in (d.dbs[i.folder] ?? []).map { (i.folder, $0) } }
        let latest = all.max { (d.dbDates[$0.0 + "|" + $0.1]?.when ?? 0) < (d.dbDates[$1.0 + "|" + $1.1]?.when ?? 0) }
        let latestWhen = latest.flatMap { d.dbDates[$0.0 + "|" + $0.1]?.when } ?? 0
        let now = Int(Date().timeIntervalSince1970)
        let dbTotal = all.compactMap { model.dbSizes[$0.0 + "|" + $0.1]?.first }
        let disk = diskSpace("/Applications")
        return HStack(spacing: 12) {
            StatCard(title: "BBDD", value: "\(all.count)",
                     sub: "en " + plural(Set(all.map { $0.0 }).count, "versión", "versiones"))
            StatCard(title: "En la versión activa", value: act == nil ? "—" : "\((d.dbs[d.active] ?? []).count)",
                     sub: act.map { "XAMPP-\($0.folder) · MariaDB \($0.mariadb)" } ?? "ninguna activa")
            StatCard(title: "La última que ha cambiado", value: latestWhen > 0 ? (latest?.1 ?? "—") : "—",
                     sub: latestWhen > 0 ? "XAMPP-\(latest?.0 ?? "") · \(fmtAge(max(0, now - latestWhen)))" : "")
            // Lo que ocupan las BBDD de todas las versiones y lo que queda libre en el disco de /Applications
            StatCard(title: "Ocupan las BBDD", value: dbTotal.isEmpty ? "—" : fmtSize(dbTotal.reduce(0, +)),
                     sub: disk.map { "Disco: \(fmtSize($0.free)) libres de \(fmtSize($0.total))" } ?? "",
                     progress: disk.map { 1 - Double($0.free) / Double($0.total) })
                .tip(dbTotal.count < all.count
                      ? plural(all.count - dbTotal.count, "BBDD", "BBDD") + " sin medir"
                      : "Tamaño de las BBDD de todas las versiones")
        }
    }

    /// Una fila por versión (se pliega al pulsarla) y, debajo, sus BBDD con su proyecto, la fecha
    /// exacta del último cambio y sus acciones
    func dbTable(_ d: AppData) -> some View {
        let q = model.dbQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let insts = d.installs.sorted { verParts($1.php).lexicographicallyPrecedes(verParts($0.php)) }
            .filter { !model.dbOnlyActive || $0.folder == d.active }
        var groups: [(Install, [(String, String)])] = []
        for inst in insts {
            let rows = (d.dbs[inst.folder] ?? []).map { ($0, model.dbProject($0, inst.folder)) }
                .filter { q.isEmpty || $0.0.lowercased().contains(q) || $0.1.lowercased().contains(q) }
            if !q.isEmpty && rows.isEmpty { continue }
            groups.append((inst, rows))
        }
        return TableBox {
            TableHead(cols: [("Nombre", 270), ("Proyecto", 180), ("Tamaño", 90), ("Cambiada", 160), ("Acciones", 0)])
            ForEach(Array(groups.enumerated()), id: \.element.0.folder) { _, g in
                Divider()
                versionRow(g.0, g.1.count, d)
                if !q.isEmpty || model.expanded.contains("@db" + g.0.folder) {
                    ForEach(Array(g.1.enumerated()), id: \.element.0) { _, r in
                        Divider()
                        dbRow(r.0, r.1, g.0, d)
                    }
                }
            }
            if groups.isEmpty {
                Divider()
                Text(q.isEmpty ? "No hay versiones con BBDD" : "Ninguna BBDD con «\(q)»")
                    .foregroundColor(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    func versionRow(_ inst: Install, _ n: Int, _ d: AppData) -> some View {
        let key = "@db" + inst.folder
        let open = model.expanded.contains(key) || !model.dbQuery.trimmingCharacters(in: .whitespaces).isEmpty
        let active = inst.folder == d.active
        // Lo que ocupan todas sus BBDD (las que se han medido)
        let total = (d.dbs[inst.folder] ?? []).reduce(Int64(0)) { $0 + (model.dbSizes[inst.folder + "|" + $1]?.first ?? 0) }
        // (una versión abierta cada vez: abrir otra cierra la que estaba; pulsar la abierta la cierra)
        return HoverRow(action: {
            if model.expanded.contains(key) {
                model.expanded.remove(key)
            } else {
                model.expanded = model.expanded.filter { !$0.hasPrefix("@db") }
                model.expanded.insert(key)
            }
        }) { _ in
            HStack(spacing: 8) {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary).frame(width: 10)
                LogoIcon("mariadb", size: 18)
                Text("XAMPP-\(inst.folder)").font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                if active { SmallTag(text: "Activa", blue: true) }
            }
            .col(270)
            Text("PHP \(inst.php) · MariaDB \(inst.mariadb)").font(.caption).foregroundColor(.secondary)
                .lineLimit(1).col(180)
            Text(total > 0 ? fmtSize(total) : "—").font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(.secondary).col(90)
            Text(plural(n, "BBDD", "BBDD")).font(.caption).foregroundColor(.secondary).col(160)
            HStack(spacing: 6) {
                if active {
                    logoAction("phpmyadmin", "Abrir phpMyAdmin") { openURL("http://127.0.0.1/phpmyadmin/") }
                        .disabled(!d.running)
                    iconAction("plus", "Crear una BBDD vacía aquí") { model.createDb() }
                        .disabled(model.busy)
                }
            }
            .col(0)
        }
    }

    func dbRow(_ db: String, _ proj: String, _ inst: Install, _ d: AppData) -> some View {
        let folder = inst.folder
        let active = folder == d.active
        let loaded = model.loadedEntry()
        let isUsed = active && loaded != nil && db == model.loadedProjectDb()
        let date = d.dbDates[folder + "|" + db]
        return HoverRow { _ in
            HStack(spacing: 8) {
                // Punto verde: la usa el proyecto cargado (invisible en las demás: así quedan alineadas)
                Circle().fill(GREEN).frame(width: 7, height: 7).opacity(isUsed ? 1 : 0)
                    .tip(isUsed ? "La usa el proyecto cargado (\(loaded?.name ?? ""))" : "")
                if isPsDb(db) {
                    LogoShape(d: LOGO_PATHS["prestashop"] ?? "").fill(brand("prestashop")).frame(width: 13, height: 13)
                } else if db.lowercased().hasPrefix("wp_") {
                    LogoShape(d: LOGO_PATHS["wordpress"] ?? "").fill(brand("wordpress")).frame(width: 13, height: 13)
                }
                Text(db).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle).tip(db)
            }
            .padding(.leading, 26)
            .col(270)
            Text(proj.isEmpty ? "—" : proj).font(.caption).foregroundColor(proj.isEmpty ? Color.secondary : Color.primary)
                .lineLimit(1).truncationMode(.middle).col(180)
            sizeCell(db, folder).col(90)
            changed(date).col(160)
            HStack(spacing: 6) {
                if isPsDb(db) {
                    iconAction("sparkles", "Vaciar la caché (var/cache) de la tienda de \(db)") { model.clearCache(db) }
                        .disabled(model.busy)
                }
                if !model.copyTargets(db, folder).isEmpty {
                    iconAction("doc.on.doc", "Copiar \(db) a otra versión de PHP (para probar el proyecto con ella)") {
                        model.copyDb(db, folder)
                    }
                    .disabled(model.busy)
                }
                iconAction("square.and.arrow.down", "Descargar una copia de \(db) (.zip)") { model.downloadDb(db, folder) }
                    .disabled(model.busy)
                iconAction("folder", "Cargar su proyecto (en XAMPP-\(folder))") { model.openProject(db, inst) }
                    .disabled(model.busy)
                if active {
                    iconAction("trash", "Borrar la BBDD \(db)") { model.dropDb(db) }
                        .disabled(model.busy)
                }
            }
            .col(0)
        }
    }

    /// Lo que ocupa (datos e índices), medido la última vez que su versión estuvo activa y en marcha
    @ViewBuilder
    func sizeCell(_ db: String, _ folder: String) -> some View {
        if let z = model.dbSizes[folder + "|" + db], z.count >= 2 {
            Text(fmtSize(z[0])).font(.system(size: 11.5, design: .monospaced))
                .tip("Datos e índices, medido el " + fmtMeasured(Int(z[1])))
        } else {
            Text("—").foregroundColor(.secondary).tip("Se mide con su versión en marcha")
        }
    }

    func fmtMeasured(_ when: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy 'a las' HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(when)))
    }

    /// La fecha del cambio: la de su carga con el gestor o la del último cambio de sus tablas
    @ViewBuilder
    func changed(_ date: DbDate?) -> some View {
        if let dt = date, dt.when > 0 {
            Text(fmtStamp(dt.when) + (dt.imported ? " · importada" : ""))
                .font(.system(size: 11.5, design: .monospaced))
                .tip((dbDateText(dt) ?? "") + (dt.imported ? "" : "\n\n" + DB_DATE_HELP))
        } else {
            Text("—").foregroundColor(.secondary)
        }
    }

    func fmtStamp(_ when: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(when)))
    }

    /// Subir o actualizar una BBDD, compacto (como en Linux): el fichero, la BBDD de destino, el proyecto y
    /// Cargar en columnas, dentro de un visor hundido, antes de la tabla
    func importCard(_ d: AppData) -> some View {
        let act = d.installs.first(where: { $0.folder == d.active })
        let desc = "Carga una copia .sql, .sql.gz o .zip (como las que se descargan del servidor) en el MariaDB de la versión activa. "
            + "Antes se borran todas las tablas de la BBDD de destino (si quieres, con una copia en ~/nexum-backups), para que no quede nada de lo anterior."
        let dbs = d.dbs[d.active] ?? []
        let hint = model.importHint()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up").foregroundColor(.secondary)
                Text("Subir o actualizar una BBDD").font(.system(size: 13, weight: .semibold))
                Image(systemName: "info.circle").foregroundColor(.secondary).tip(desc)
                if let a = act {
                    Text("en XAMPP-\(a.folder) · MariaDB \(a.mariadb)").font(.caption).foregroundColor(.secondary)
                }
            }
            if act == nil {
                Text("Activa una versión en Versiones de PHP para cargar BBDD.").font(.caption).foregroundColor(.secondary)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    importColumn("Fichero SQL") {
                        HStack(spacing: 6) {
                            Button("Elegir…") { model.pickSql() }
                            Text(fileSubtitle()).font(.caption).foregroundColor(model.impFile == nil ? Color.secondary : Color.primary)
                                .lineLimit(1).truncationMode(.middle).tip(model.impFile ?? "")
                        }
                        // (lo que falta para poder cargar: debajo del fichero, que tiene sitio)
                        if let h = hint {
                            Text(h).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    importColumn("BBDD de destino") {
                        HStack(spacing: 4) {
                            Picker("", selection: Binding(get: { model.impDb ?? "" },
                                                          set: { model.impDb = $0.isEmpty ? nil : $0 })) {
                                if model.impDb == nil { Text("Elige una BBDD").tag("") }
                                ForEach(dbs, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .frame(minWidth: 150, maxWidth: 260)
                            IconButton(symbol: "plus", help: "Crear una BBDD nueva") { model.createDb() }
                                .disabled(model.busy)
                            IconButton(symbol: "trash", help: "Borrar la BBDD elegida") {
                                if let db = model.impDb { model.dropDb(db) }
                            }
                            .disabled(model.impDb == nil || model.busy)
                        }
                    }
                    importColumn("Proyecto (opcional)") {
                        Picker("", selection: Binding(get: { model.impProject ?? "" },
                                                      set: { model.impProject = $0.isEmpty ? nil : $0 })) {
                            Text("Ninguno").tag("")
                            ForEach(model.impProjects, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(minWidth: 150, maxWidth: 260)
                        Text(model.importProjectHint()).font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .onAppear { if model.impProjects.isEmpty { model.refreshImpProjects() } }
                    Button("Cargar") { model.importDb() }
                        .buttonStyle(OutlineButton(kind: "primary"))
                        .disabled(hint != nil || model.busy)
                        .padding(.top, 20)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SoftSunken(radius: 12))
    }

    /// Una columna del formulario de carga: su título en pequeño y lo de debajo
    func importColumn<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).foregroundColor(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func fileSubtitle() -> String {
        guard let f = model.impFile else { return "Ningún fichero elegido" }
        let name = (f as NSString).lastPathComponent
        if let attrs = try? FileManager.default.attributesOfItem(atPath: f), let size = attrs[.size] as? NSNumber {
            return "\(name)  ·  \(fmtSize(size.int64Value))"
        }
        return "\(name)  ·  ya no existe"
    }
}
