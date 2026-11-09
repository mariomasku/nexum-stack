// MARK: - Montar nuevo proyecto (asistente de tres pasos dentro de Cargar proyecto)

let GIT_URL_RX = try! NSRegularExpression(pattern: "^(https://[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]{1,5})?/|git@[A-Za-z0-9][A-Za-z0-9.-]*:|ssh://git@[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]{1,5})?/)[A-Za-z0-9_~][A-Za-z0-9._~/-]*$")
let NEW_FOLDER_RX = try! NSRegularExpression(pattern: "^[A-Za-z0-9_][A-Za-z0-9._-]{0,99}$")

/// Carpeta que se propone para un repositorio: su nombre sin .git
func folderFromGitURL(_ url: String) -> String {
    var name = url.trimmingCharacters(in: .whitespaces)
    while name.hasSuffix("/") { name = String(name.dropLast()) }
    name = name.components(separatedBy: "/").last ?? ""
    name = name.components(separatedBy: ":").last ?? ""
    if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
    name = name.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
    while name.hasPrefix(".") || name.hasPrefix("-") { name = String(name.dropFirst()) }
    return String(name.prefix(100))
}

struct NewProjectWizard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let check = model.npCheck()
        return VStack(alignment: .leading, spacing: 12) {
            Text(["", "Paso 1 de 4: el repositorio", "Paso 2 de 4: versión de PHP", "Paso 3 de 4: BBDD nueva",
                  "Paso 4 de 4: dominio de producción"][model.npStep])
                .font(.headline).frame(maxWidth: .infinity)
            Group {
                if model.npStep == 1 {
                    stepRepo()
                } else if model.npStep == 2 {
                    stepVersion()
                } else if model.npStep == 3 {
                    stepDb()
                } else {
                    stepDomain()
                }
            }
            if !check.1.isEmpty {
                Text(check.1).font(.callout.weight(.semibold)).foregroundColor(RED)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancelar") { model.newProject(false) }.buttonStyle(OutlineButton(big: true))
                Spacer()
                if model.npStep > 1 {
                    Button("Atrás") { model.npGo(-1) }.buttonStyle(OutlineButton(big: true))
                }
                Button(model.npStep == 4 ? "Montar proyecto" : "Siguiente") { model.npGo(1) }
                    .buttonStyle(OutlineButton(kind: "primary", big: true))
                    .disabled(!check.0 || model.busy)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }

    func stepRepo() -> some View {
        let q = repoQuery(model.npRepoQuery)
        let hits = q.count < 2 || model.npRepos.contains(where: { $0.full.lowercased() == q }) ? []
            : Array(model.npRepos.filter { $0.full.lowercased().contains(q) }.prefix(6))
        return VStack(alignment: .leading, spacing: 8) {
            Text("¿De qué repositorio de GitHub? (escribe parte de su nombre)")
            TextField("dob-wordpress-…", text: Binding(get: { model.npRepoQuery }, set: { model.npRepoTyped($0) }))
                .textFieldStyle(RoundedBorderTextFieldStyle())
            if !hits.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(hits) { r in
                        Button(action: { model.npPickRepo(r) }) {
                            HStack {
                                Text(r.full).lineLimit(1)
                                Spacer()
                                if !r.web.isEmpty { Text(r.web).font(.caption).foregroundColor(.secondary).lineLimit(1) }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            }
            if !model.npRepoNote.isEmpty {
                Text(model.npRepoNote).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("o la dirección de otro repositorio (GitHub u otro servidor):")
            TextField("https://github.com/usuario/repositorio.git", text: Binding(
                get: { model.npUrl },
                set: { v in
                    model.npUrl = v
                    if model.npFolderAuto { model.npFolder = folderFromGitURL(v) }
                }))
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("Carpeta en htdocs:")
            TextField("nombre-del-proyecto", text: Binding(
                get: { model.npFolder },
                set: { v in
                    model.npFolder = v
                    model.npFolderAuto = v.isEmpty
                }))
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("Se clona con tu usuario (sin sudo). Los de la lista, por SSH con tu clave; una dirección https de un privado de GitHub, GitLab o Bitbucket se prueba sola por SSH.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func stepVersion() -> some View {
        let d = model.data ?? AppData()
        let insts = d.installs.sorted { a, b in a.php.compare(b.php, options: .numeric) == .orderedDescending }
        return VStack(alignment: .leading, spacing: 8) {
            Text("¿En qué versión de PHP quieres crear el proyecto?")
            if insts.isEmpty {
                Text("No hay ninguna versión instalada: instala una en Versiones de PHP.").foregroundColor(RED)
            } else {
                Picker("", selection: $model.npVersion) {
                    ForEach(insts) { i in
                        Text("PHP \(i.php)  ·  XAMPP-\(i.folder)" + (i.folder == d.active ? "  (activa)" : "")).tag(i.folder)
                    }
                }
                .pickerStyle(RadioGroupPickerStyle())
                .labelsHidden()
            }
        }
    }

    func stepDomain() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("¿Falsear su dominio de producción en este Mac?", isOn: $model.npFake)
                .toggleStyle(SwitchToggleStyle())
            Text("Dominio de producción:")
            TextField("midominio.com", text: $model.npDomain)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .disabled(!model.npFake)
            Text("Falseado, el navegador abre el proyecto en local con su dominio de verdad (con su certificado), como en Dominios y hosts: lo que necesitan las tiendas PrestaShop y los WordPress con el dominio en su BBDD. Si no, se abre en web.local.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func stepDb() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nombre de la BBDD nueva:")
            TextField("wp_proyecto", text: $model.npDb)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("Volcado que se sube a la BBDD (.sql, .sql.gz o .zip):")
            HStack {
                Button("Elegir…") { model.npPickDump() }
                if let f = model.npFile {
                    Text((f as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Button(action: { model.npFile = nil }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .tip("Quitar el volcado: la BBDD se crea vacía")
                } else {
                    Text("Ninguno").foregroundColor(.secondary)
                }
            }
            Text("Si no eliges ninguno, la BBDD se crea vacía. El volcado se carga con la carga protegida (con el usuario de la BBDD y sin DEFINER).")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
