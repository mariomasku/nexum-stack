extension AppModel {
    // MARK: acciones

    /// Lanza una tarea del script en su hoja. Con otra en marcha (o acabada, con su hoja aún abierta) no van las dos
    /// a la vez, que tocarían lo mismo: va a la cola y empieza cuando se cierre la anterior (nil: en la cola)
    @discardableResult
    func runTask(_ title: String, _ args: [String], progress: Bool = false, doneText: String = "Terminado",
                 autoClose: Bool = false, env: [String: String] = [:],
                 cancelText: (String, String, String)? = nil, reloadBranches: Bool = false,
                 onDone: ((Bool, TaskRunner, InstallProgress?) -> Void)? = nil) -> TaskRunner? {
        let q = QueuedTask(title: title, args: args, progress: progress, doneText: doneText, autoClose: autoClose,
                           env: env, cancelText: cancelText, reloadBranches: reloadBranches, onDone: onDone)
        if task != nil {
            taskQueue.append(q)
            toast("En la cola: «\(title)». Empieza cuando acabe «\(task?.title ?? "la anterior")»")
            return nil
        }
        return launchTask(q)
    }

    /// Lo que puede ir al lado de la que sigue (taskFree, como traer los cambios de un repositorio): sin hoja (solo
    /// se ve una), y al acabar lo dice
    func runFree(_ title: String, _ args: [String], doneText: String, _ done: @escaping (Bool) -> Void) {
        runQuick(args) { [weak self] rc, out in
            guard let self = self else { return }
            done(rc == 0)
            if rc == 0 {
                self.toast("\(title): \(doneText.lowercased())")
            } else {
                let lines = out.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                message("No se ha podido completar «\(title)»", lines.suffix(8).joined(separator: "\n"))
            }
        }
    }

    @discardableResult
    func launchTask(_ q: QueuedTask) -> TaskRunner {
        // (la ventana que hubiera encima de la página se cierra: la tarea va en su hoja)
        panel = nil
        taskHidden = false
        let t = TaskRunner(title: q.title, args: q.args, withProgress: q.progress, doneText: q.doneText,
                           autoClose: q.autoClose, env: q.env, cancelText: q.cancelText)
        t.model = self
        t.onDone = { [weak self] ok, task, p in
            q.onDone?(ok, task, p)
            guard let self = self else { return }
            self.lastTaskOk = ok
            self.reload(branches: q.reloadBranches)
            // (con más en la cola, al acabar bien su hoja se cierra sola y sigue la siguiente, salvo si ofrece algo)
            DispatchQueue.main.async {
                if ok, !self.taskQueue.isEmpty, task.extraLabel == nil, self.task === task {
                    self.task = nil
                    self.toast(task.doneText)
                }
            }
        }
        lastTaskOk = true
        task = t
        t.start()
        return t
    }

    /// Cerrada la hoja de la que ha acabado (task pasa a nil): la siguiente de la cola. Si no ha acabado bien,
    /// antes se pregunta. Si su botón ha lanzado otra, esa va antes (ya está en marcha)
    func taskClosed(_ old: TaskRunner) {
        guard task == nil, !taskQueue.isEmpty else { return }
        if !lastTaskOk {
            let names = taskQueue.map { "«\($0.title)»" }.joined(separator: ", ")
            if !runDialog(title: "¿Seguir con la cola?",
                          text: "«\(old.title)» no ha terminado bien. Quedan en la cola: \(names). Mira antes lo que ha pasado: si sigues, cada una comprueba lo suyo al empezar; si no, se quitan de la cola sin hacer nada.",
                          okLabel: "Seguir con la cola", style: .warning, cancelLabel: "Vaciar la cola").ok {
                clearTaskQueue()
                return
            }
        }
        launchTask(taskQueue.removeFirst())
    }

    func clearTaskQueue() {
        let n = taskQueue.count
        taskQueue.removeAll()
        if n > 0 { toast("Cola vaciada: \(plural(n, "tarea", "tareas")) sin hacer") }
    }

    /// Lo que se añade a la pregunta de una tarea con otra en marcha: que va a la cola (nil si no hay)
    var taskNote: String? {
        guard let cur = task else { return nil }
        return "«\(cur.title)» sigue en marcha: esta se pone en la cola y empieza cuando acabe."
    }

    /// ¿Puede ir ya, al lado de la que sigue? Solo lo que no toca nada de lo de las tareas (XAMPP, los ficheros de
    /// root, Homebrew, Docker), y si la que sigue no es de esa carpeta
    func taskFree(_ folder: String) -> Bool {
        guard let cur = task, !cur.finished else { return task == nil }
        return !(cur.args + [cur.title]).contains(where: { $0.contains(folder) })
    }

    /// Al salir con tareas en la cola (que no se harían): ¿salir igual?
    func taskQueueQuit() -> Bool {
        if taskQueue.isEmpty { return true }
        let names = taskQueue.map { "«\($0.title)»" }.joined(separator: ", ")
        return runDialog(title: "¿Salir con tareas en la cola?",
                         text: "Quedan en la cola: \(names). Si sales ahora no se hacen (la que está en marcha sigue hasta acabar).",
                         okLabel: "Salir sin hacerlas", style: .warning, destructive: true).ok
    }

    /// La tarea que sigue en marcha (en su hoja o en segundo plano), o nil
    var runningTask: TaskRunner? {
        if let cur = task, !cur.finished { return cur }
        return nil
    }

    /// Lo poco que no va a la cola (crear una BBDD vacía, que no es una tarea): lo dice nombrando la que sigue, para
    /// que se espere a que acabe, y la enseña
    func refuseTask(_ cur: TaskRunner) {
        message("Hay una tarea en marcha",
                "«\(cur.title)» sigue en marcha. Espera a que acabe y vuelve a probar.")
        taskHidden = false
    }

    func control(_ cmd: String, _ what: String) {
        let folder = data?.active ?? ""
        if cmd == "parar" {
            // Parar = nexum disable: para y quita el enlace /Applications/XAMPP (php deja de responder)
            runTask("Parando y desactivando XAMPP-\(folder)", ["disable"],
                    doneText: "XAMPP-\(folder) parada y desactivada", autoClose: true)
            return
        }
        // (el aviso dice cuál: XAMPP-8.4 (PHP 8.4.14))
        let php = data?.installs.first(where: { $0.folder == folder })?.php ?? ""
        let name = "XAMPP-\(folder)" + (php.isEmpty ? "" : " (PHP \(php))")
        let texts = ["arrancar": "Versión activa arrancada: \(name)", "reiniciar": "Versión activa reiniciada: \(name)"]
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

    /// Webs permitidas (Configuración, Seguridad entre webs): una de confianza, como el ERP de la empresa,
    /// que la barrera deja pasar en todas las versiones. Se escribe el dominio o se pega la dirección entera
    func addBarrierAllowed() {
        guard let d = data else { return }
        let hint = "erp.empresa.com, o *.empresa.com para todos sus subdominios"
        let r = runDialog(title: "Permitir una web",
                          text: "Lo que mande esa web a tus proyectos (un formulario que te lleva a tu back office, su vuelta con un POST, un iframe, un fetch) pasa la barrera. Pon solo webs tuyas o de confianza. Se aplica a todas las versiones y pide la contraseña de administrador.",
                          okLabel: "Permitir", hasField: true, fieldLabel: hint, placeholder: "erp.empresa.com",
                          validate: { _, typed in
                              guard let dom = barrierDomain(typed) else {
                                  return (false, hint, !typed.trimmingCharacters(in: .whitespaces).isEmpty)
                              }
                              if d.barrierAllowed.contains(dom) { return (false, "Ya está en la lista.", true) }
                              return (true, "Se permite \(dom)", false)
                          })
        guard r.ok, let dom = barrierDomain(r.text) else { return }
        runTask("Permitiendo \(dom)", ["barrera-web", "permitir", dom], doneText: "\(dom), permitida", autoClose: true)
    }

    func removeBarrierAllowed(_ dom: String) {
        if !confirm("¿Quitar \(dom) de las webs permitidas?",
                    "La barrera vuelve a parar lo que mande a tus proyectos, como a cualquier otra web. Se aplica a todas las versiones y pide la contraseña de administrador.",
                    "Quitar", destructive: true) { return }
        runTask("Quitando \(dom) de las webs permitidas", ["barrera-web", "quitar", dom],
                doneText: "\(dom) ya no está permitida", autoClose: true)
    }
}

/// Un dominio de las webs permitidas tal como se escribe o se pega (https://erp.empresa.com/login): sin el
/// protocolo, la ruta ni el puerto, en minúsculas (lo mismo que web_barrier_domain). nil si no vale
func barrierDomain(_ typed: String) -> String? {
    var d = typed.trimmingCharacters(in: .whitespaces).lowercased()
    if let r = d.range(of: "://") { d = String(d[r.upperBound...]) }
    for c in ["/", "?", ":"] { if let r = d.range(of: c) { d = String(d[..<r.lowerBound]) } }
    if d.hasSuffix(".") { d.removeLast() }
    let ok = d.range(of: "^(\\*\\.)?[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$",
                     options: .regularExpression) != nil
    return ok ? d : nil
}
