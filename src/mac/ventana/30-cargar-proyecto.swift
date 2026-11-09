// MARK: - Cargar proyecto

struct Project: Equatable {
    let name, db, php: String
    /// ps (tienda PrestaShop), wp (WordPress) o vacío
    var kind: String = ""
}

/// Proyectos de htdocs (gui-proyectos), para el bloque «Cargar proyecto» de Versiones
struct ProjectsData: Equatable {
    var link = "", current = ""
    /// No hay vhost para cargar proyectos: cargar-proyecto crea web.local
    var create = false
    var list: [Project] = []
    /// Base -> carpeta recordada (en todas las versiones, como se guardaba hasta la 1.36)
    var saved: [String: String] = [:]
    /// "base@versión" -> carpeta vinculada en esa versión ("" = desvinculada en ella)
    var vlinks: [String: String] = [:]
}

struct ProjectRequest: Identifiable {
    let db: String
    let inst: Install
    let link, current: String
    /// No hay vhost para cargar proyectos: cargar-proyecto crea web.local
    let create: Bool
    let projects: [Project]
    let saved: [String: String]
    var id: String { return db + "@" + inst.folder }
}

struct ProjectSheet: View {
    @EnvironmentObject var model: AppModel
    let req: ProjectRequest
    @State private var folder: String? = nil
    @State private var filter = ""

    var matches: [String] { return req.projects.filter { $0.db == req.db }.map { $0.name } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Proyecto de \(req.db)").font(.title3.weight(.semibold)).frame(maxWidth: .infinity)
            Text((matches.count > 1 ? "\(matches.count) carpetas usan «\(req.db)». Elige cuál cargar."
                  : "Ninguna carpeta usa «\(req.db)» en su configuración. Elige la del proyecto.")
                 + " Se recuerda para esta BBDD.")
                .foregroundColor(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Buscar una carpeta de htdocs", text: $filter).textFieldStyle(PlainTextFieldStyle())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(pickerList(), id: \.name) { p in
                        folderRow(p)
                    }
                }
            }
            .frame(height: 260)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))

            HStack {
                Spacer()
                Button("Cancelar") { model.projectReq = nil }
                    .buttonStyle(OutlineButton(big: true))
                    .keyboardShortcut(.cancelAction)
                Button("Cargar proyecto") { accept() }
                    .buttonStyle(OutlineButton(kind: "primary", big: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(folder == nil)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 580)
    }

    /// Primero las que usan esta base, luego el resto por nombre
    func pickerList() -> [Project] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return req.projects.filter { q.isEmpty || $0.name.lowercased().contains(q) }.sorted { a, b in
            if (a.db == req.db) != (b.db == req.db) { return a.db == req.db }
            return a.name.lowercased() < b.name.lowercased()
        }
    }

    func folderRow(_ p: Project) -> some View {
        var sub = p.db == req.db ? "Usa esta BBDD" : p.db.isEmpty ? "Sin BBDD detectada" : "BBDD: \(p.db)"
        if !p.php.isEmpty { sub += "  ·  .php-version \(p.php)" }
        let selected = p.name == folder
        return VStack(alignment: .leading, spacing: 2) {
            Text(p.name)
            Text(sub).font(.caption).foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(selected ? ACCENT.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            folder = p.name
            accept()
        }
        .onTapGesture { folder = p.name }
    }

    func accept() {
        guard let f = folder else { return }
        model.loadProject(req, folder: f, version: req.inst.folder, manual: true)
    }
}
