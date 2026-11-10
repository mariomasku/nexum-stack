// MARK: - Instalar nuevas versiones (dentro de Versiones)

struct InstallSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if let err = model.branchesError {
                Card("Instalar nuevas versiones de PHP") {
                    Row(err) { Button("Reintentar") { model.reload(branches: true) } }
                }
            } else if let list = model.branches {
                let nuevas = list.filter { $0.state == "nueva" }.count
                FoldCard("instalar", "Instalar nuevas versiones de PHP",
                     "Pulsa el título para plegar o desplegar la lista. Cada versión se compila en tu Mac (unos 20-40 min) con su propio Apache, MariaDB, ProFTPD, Perl y phpMyAdmin, y sus propias BBDD, vacías al instalar. Según php.net: Estable recibe correcciones de errores y de seguridad (la mejor opción para proyectos nuevos), Solo seguridad recibe únicamente parches de seguridad hasta la fecha indicada y Sin soporte ya no recibe parches.",
                     summary: nuevas > 0 ? plural(nuevas, "versión nueva", "versiones nuevas") : "") {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, b in
                        VStack(spacing: 0) {
                            if i > 0 { Divider() }
                            branchRow(b)
                        }
                    }
                }
                patchCard(list)
                VStack(spacing: 6) {
                    Button(model.selected.isEmpty ? "Instalar" : "Instalar \(plural(model.selected.count, "versión", "versiones"))") {
                        model.install()
                    }
                    .buttonStyle(OutlineButton(kind: "primary", big: true))
                    .disabled(model.selected.isEmpty || model.busy)
                    Text("La versión activa no cambia. Las nuevas se activan en la tabla de Versiones de PHP.")
                        .font(.callout).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                Loading(text: "Consultando las versiones de PHP en php.net…")
            }
        }
    }

    /// Otro parche concreto (como en Linux): una versión anterior de cualquier rama, en su propia carpeta
    /// (XAMPP-X.Y.Z). Se elige la rama y se marcan sus parches; se instalan con los de arriba
    func patchCard(_ list: [Branch]) -> some View {
        let marked = model.selected.filter { $0.components(separatedBy: ".").count == 3 }
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        let names = ["stable": "estable", "security": "solo seguridad", "eol": "sin soporte"]
        return FoldCard("parche", "Otro parche concreto",
                        "Una versión anterior de cualquier rama, en su propia carpeta (XAMPP-X.Y.Z), con el Apache, MariaDB, ProFTPD y Perl de su rama. Las versiones de php.net son todas definitivas, pero los parches anteriores al último no llevan sus correcciones de seguridad: úsalos solo si un proyecto necesita esa versión.",
                        summary: marked.isEmpty ? "" : plural(marked.count, "parche marcado", "parches marcados")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("Rama:")
                    SearchPicker(selection: Binding(get: { model.patchBranch }, set: { model.loadPatches($0) }),
                                 items: [("", "Elige una rama")] + list.map { b in
                                     (b.branch, "PHP \(b.branch)" + (names[b.phpState].map { "  (\($0))" } ?? ""))
                                 }, width: 240)
                    .disabled(model.busy)
                    Spacer(minLength: 8)
                }
                if !marked.isEmpty {
                    // (los marcados de cualquier rama, para quitarlos aunque se mire otra)
                    HStack(spacing: 6) {
                        Text("Marcados:").font(.caption).foregroundColor(.secondary)
                        ForEach(marked, id: \.self) { v in
                            Button(action: { model.selected.remove(v) }) {
                                HStack(spacing: 3) {
                                    Text("PHP \(v)").font(.caption)
                                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .tip("Quitar de la lista")
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if let err = model.patchesError {
                Divider()
                Text(err).foregroundColor(RED).padding(.horizontal, 14).padding(.vertical, 10)
            } else if let ps = model.patches {
                ForEach(ps) { p in
                    Divider()
                    patchRow(p)
                }
            } else if !model.patchBranch.isEmpty {
                Divider()
                Loading(text: "Consultando los parches de PHP \(model.patchBranch)…").padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
    }

    func patchRow(_ p: PatchItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("PHP \(p.version)")
                    if !p.date.isEmpty {
                        Text(fmtDay(p.date)).font(.caption).foregroundColor(.secondary)
                    }
                    ReleaseTag(security: p.security)
                }
                Text(p.latest ? "El último de su rama: márcalo en la lista de arriba"
                     : p.state == "instalada" ? "Ya instalada"
                     : p.state == "existe" ? "Ya existe XAMPP-\(p.version)"
                     : "→ /Library/Nexum/XAMPP-\(p.version)")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            if p.state == "nueva" && !p.latest {
                Toggle("", isOn: Binding(get: { model.selected.contains(p.version) },
                                         set: { on in
                                             if on { model.selected.insert(p.version) } else { model.selected.remove(p.version) }
                                         }))
                    .labelsHidden()
                    .disabled(model.busy)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .opacity(p.state == "nueva" && !p.latest ? 1 : 0.55)
    }

    /// Fila de una rama: «PHP 8.5.12», a su lado la fecha en que se publicó y si es un parche de
    /// seguridad; debajo su pila. Como Row (mismas medidas), pero con la fecha junto a la versión
    func branchRow(_ b: Branch) -> some View {
        HStack(spacing: 10) {
            if let ic = rowIcon("PHP \(b.branch)") {
                ColorIcon(symbol: ic.0, color: ic.1, size: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("PHP \(b.latest)")
                    if !b.date.isEmpty {
                        Text(fmtDay(b.date)).font(.caption).foregroundColor(.secondary)
                        ReleaseTag(security: b.security)
                    }
                }
                Text("MariaDB \(b.mariadb)  ·  Perl \(b.perl)"
                     + (b.phpState == "security" && !b.securityEnd.isEmpty
                        ? "  ·  seguridad hasta \(fmtMonth(b.securityEnd))" : ""))
                    .font(.caption).foregroundColor(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                StatePill(b: b)
                stateView(b)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    func stateView(_ b: Branch) -> some View {
        switch b.state {
        case "nueva":
            Toggle("", isOn: Binding(get: { model.selected.contains(b.branch) },
                                     set: { on in
                                         if on { model.selected.insert(b.branch) } else { model.selected.remove(b.branch) }
                                     }))
                .labelsHidden()
                .disabled(model.busy)
        case "instalada":
            Text("Instalada").foregroundColor(.secondary)
        default:
            Text("Hay un parche nuevo").foregroundColor(.secondary)
                .tip("Actualízala en Versiones de PHP (⋯)")
        }
    }
}
