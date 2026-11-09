extension AppModel {
    // MARK: acciones

    @discardableResult
    func runTask(_ title: String, _ args: [String], progress: Bool = false, doneText: String = "Terminado",
                 autoClose: Bool = false, env: [String: String] = [:],
                 cancelText: (String, String, String)? = nil, reloadBranches: Bool = false,
                 onDone: ((Bool, TaskRunner, InstallProgress?) -> Void)? = nil) -> TaskRunner {
        // (otra tarea en segundo plano: no van dos a la vez, que tocarían lo mismo)
        if let cur = task, !cur.finished {
            taskHidden = false
            toast("Hay una tarea en marcha: espera a que acabe")
            return cur
        }
        // (la ventana que hubiera encima de la página se cierra: la tarea va en su hoja)
        panel = nil
        taskHidden = false
        let t = TaskRunner(title: title, args: args, withProgress: progress, doneText: doneText,
                           autoClose: autoClose, env: env, cancelText: cancelText)
        t.model = self
        t.onDone = { [weak self] ok, task, p in
            onDone?(ok, task, p)
            self?.reload(branches: reloadBranches)
        }
        task = t
        t.start()
        return t
    }

    func control(_ cmd: String, _ what: String) {
        let folder = data?.active ?? ""
        if cmd == "parar" {
            // Parar = lvm disable: para y quita el enlace /Applications/XAMPP (php deja de responder)
            runTask("Parando y desactivando XAMPP-\(folder)", ["disable"],
                    doneText: "XAMPP-\(folder) parada y desactivada", autoClose: true)
            return
        }
        let texts = ["arrancar": "Versión activa arrancada", "reiniciar": "Versión activa reiniciada"]
        runTask("\(what) XAMPP-\(folder)", [cmd], doneText: texts[cmd] ?? "Terminado", autoClose: true)
    }

    func activate(_ folder: String) {
        // Una versión vulnerable a PHP2Shell, solo si se confirma
        let st = data?.php2shell[folder] ?? "ok"
        if php2shellVulnerable(st) {
            let php = data?.installs.first(where: { $0.folder == folder })?.php ?? folder
            if !runDialog(title: "PHP \(php) es vulnerable (PHP2Shell)", text: php2shellText(st, php),
                          okLabel: "Activar XAMPP-\(folder) igualmente", style: .warning, destructive: true).ok { return }
        }
        runTask("Activando XAMPP-\(folder)", ["use", folder], doneText: "XAMPP-\(folder) activada", autoClose: true)
    }

    /// Actualizar una XAMPP-X.Y.Z al último parche de su rama: se instala a su lado (la de ahora no se
    /// toca) y, al terminar, un botón le pasa sus BBDD con sus vínculos y la activa si esta era la activa
    func upgradePinned(_ inst: Install, _ newPhp: String) {
        let branch = shortPhp(newPhp)
        guard confirm("¿Actualizar a PHP \(newPhp)?",
                      "Se instala XAMPP-\(newPhp) a su lado (20-40 min); XAMPP-\(inst.folder) no se toca. Al terminar, «Pasar las BBDD» le copia sus BBDD con sus vínculos y la activa si esta era la activa. Pide la contraseña de administrador.",
                      "Instalar PHP \(newPhp)") else { return }
        runTask("Instalando PHP \(newPhp)", ["instalar", "--php", branch, "--si"], progress: true,
                doneText: "XAMPP-\(newPhp) instalada", reloadBranches: true) { [weak self] ok, task, _ in
            guard let self = self, ok, !SIMULATE else { return }
            task.offer("Pasar las BBDD a XAMPP-\(newPhp)") {
                self.task = nil
                self.moveToVersion(inst.folder, newPhp)
            }
        }
    }

    /// Las BBDD de una versión, con sus vínculos, a otra (pasar-version); la activa si era la activa
    func moveToVersion(_ from: String, _ to: String) {
        runTask("Pasando las BBDD de XAMPP-\(from) a XAMPP-\(to)", ["pasar-version", from, to],
                doneText: "BBDD en XAMPP-\(to). Cuando compruebes que va bien, desinstala XAMPP-\(from)", env: dbEnv())
    }

    /// Barrera entre webs (Configuración): pone o quita en todas las versiones el bloqueo de lo que
    /// mandan otras webs a los proyectos
    func setBarrier(_ on: Bool) {
        guard let d = data, d.barrier != on, !busy else { return }
        if !on && !confirm("¿Apagar la barrera entre webs?",
                           "Otras webs podrán volver a mandar formularios y peticiones a tus proyectos (como la vuelta de una pasarela de pago). Se aplica a todas las versiones y se recarga Apache. Pide la contraseña de administrador.",
                           "Apagar la barrera", destructive: true) { return }
        runTask(on ? "Poniendo la barrera entre webs" : "Apagando la barrera entre webs", ["barrera-web", on ? "si" : "no"],
                doneText: on ? "Barrera entre webs puesta" : "Barrera entre webs apagada", autoClose: true)
    }
}
