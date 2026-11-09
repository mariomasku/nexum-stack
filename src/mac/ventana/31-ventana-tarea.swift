// MARK: - Ventana de una tarea

struct TaskView: View {
    @ObservedObject var task: TaskRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // «Terminado» en gris no se ve de un vistazo: check azul grande y el título en azul
            if task.succeeded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(ACCENT)
                    .frame(maxWidth: .infinity)
            }
            Text(task.head).font(.title3.weight(.semibold))
                .foregroundColor(task.succeeded ? ACCENT : .primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
            // Encima de la barra: lo que se hace (a la izquierda) y el porcentaje con lo que queda
            HStack(spacing: 12) {
                Text(task.barText).foregroundColor(.secondary).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
                Text(task.pctText).font(Font.system(size: 13, weight: .bold).monospacedDigit())
            }
            .padding(.top, 4)
            TaskBar(fraction: task.fraction, failed: task.failed)
            if !task.info.isEmpty {
                Text(task.info).font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
            }
            if !task.parts.isEmpty {
                Card {
                    ForEach(Array(task.parts.enumerated()), id: \.offset) { i, part in
                        VStack(spacing: 0) {
                            if i > 0 { Divider() }
                            Row(part) { partState(i + 1) }
                        }
                    }
                }
            }
            // El registro, como una terminal (sin DisclosureGroup: su botón tomaría el estilo de la ventana)
            Button(action: { task.showLog.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: task.showLog ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold)).frame(width: 12)
                    Text("Ver registro")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .hoverPointer()
            if task.showLog {
                TaskConsole(log: task.log, height: task.withProgress ? 220 : 180)
            }
            HStack(spacing: 10) {
                Spacer()
                if task.failed {
                    Button("Ver el log del error") { task.showReport = true }
                        .buttonStyle(OutlineButton(big: true))
                }
                if let label = task.extraLabel {
                    Button(label) { task.extraAction?() }
                        .buttonStyle(OutlineButton(kind: "primary", big: true))
                }
                if !task.finished {
                    Button("Seguir en segundo plano") { task.model?.taskHidden = true }
                        .buttonStyle(OutlineButton(big: true))
                        .tip("Esconder esta ventana y seguir usando el programa")
                }
                Button(task.finished ? "Cerrar" : "Cancelar") { task.closeTapped() }
                    .buttonStyle(OutlineButton(big: true))
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 620)
        .interactiveDismissDisabled(true)
        .sheet(isPresented: $task.showReport) { ReportView(task: task).buttonStyle(PointerButtonStyle()) }
    }

    @ViewBuilder
    func partState(_ i: Int) -> some View {
        if task.finished && task.failedPart == i && task.head != task.doneText {
            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        } else if i < task.cur {
            Image(systemName: "checkmark.circle.fill").foregroundColor(ACCENT)
        } else if i == task.cur && !task.finished {
            ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
        } else {
            Text("…").foregroundColor(.secondary)
        }
    }
}

/// Barra de una tarea: gruesa (12 de alto), redondeada y azul; roja si ha fallado. Sin porcentaje
/// (fraction nil), un trozo que va y viene
struct TaskBar: View {
    let fraction: Double?
    let failed: Bool

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(failed ? RED.opacity(0.22) : Color.primary.opacity(0.10))
                if let f = fraction {
                    Capsule().fill(failed ? RED : ACCENT)
                        .frame(width: g.size.width * CGFloat(max(0, min(1, f))))
                        .animation(.easeOut(duration: 0.3), value: f)
                } else {
                    TimelineView(.animation) { ctx in
                        Capsule().fill(ACCENT)
                            .frame(width: g.size.width * 0.3)
                            .offset(x: swing(ctx.date) * g.size.width * 0.7)
                    }
                    .frame(width: g.size.width, alignment: .leading)
                }
            }
        }
        .frame(height: 12)
    }

    /// De 0 a 1 y vuelta, suave (cada 2,8 s)
    func swing(_ date: Date) -> CGFloat {
        return CGFloat((sin(date.timeIntervalSinceReferenceDate * 2.25) + 1) / 2)
    }
}

/// El registro de una tarea como una terminal: fondo oscuro, letra clara de ancho fijo que salta de
/// línea y siempre al final
struct TaskConsole: View {
    let log: String
    let height: CGFloat
    /// (el informe del error se lee desde el principio)
    var toEnd = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(log)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(CONSOLE_TEXT)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("fin")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .frame(height: height)
            .background(CONSOLE_BG)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.25), lineWidth: 1))
            // (la barra de desplazamiento, la de un fondo oscuro)
            .environment(\.colorScheme, .dark)
            .onAppear { if toEnd { proxy.scrollTo("fin", anchor: .bottom) } }
            .onChange(of: log) { _ in if toEnd { proxy.scrollTo("fin", anchor: .bottom) } }
        }
    }
}

// Informe del error para copiarlo y buscar la solución
struct ReportView: View {
    @ObservedObject var task: TaskRunner
    @State private var copied = false

    var body: some View {
        let (text, folder, isReport) = task.report()
        return VStack(alignment: .leading, spacing: 12) {
            Text("Log del error").font(.title3.weight(.semibold)).frame(maxWidth: .infinity)
            Text("Cópialo para buscar la solución o enviarlo. "
                 + (isReport ? "Lleva el sistema, el paso que ha fallado y sus errores. " : "")
                 + "Los logs completos están en \(folder).")
                .foregroundColor(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
            TaskConsole(log: text, height: 420, toEnd: false)
            HStack(spacing: 10) {
                Spacer()
                Button(copied ? "Copiado" : "Copiar todo") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
                .buttonStyle(OutlineButton(kind: "primary", big: true))
                Button("Abrir la carpeta de logs") { showFolder(folder) }
                    .buttonStyle(OutlineButton(big: true))
                Button("Cerrar") { task.showReport = false }
                    .buttonStyle(OutlineButton(big: true))
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 760)
    }
}
