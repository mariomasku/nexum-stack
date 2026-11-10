// MARK: - Dialogos (NSAlert)

/// Ancho del texto de los dialogos. Va en una vista propia: NSAlert lo pondria en una columna
/// estrecha que parte en cuatro lineas cualquier frase
let DIALOG_WIDTH: CGFloat = 460

/// (centrado, como el título: los diálogos llevan el título y la explicación en el centro)
func dialogLabel(_ text: String, font: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize),
                 color: NSColor = .labelColor, align: NSTextAlignment = .center) -> NSTextField {
    let l = NSTextField(wrappingLabelWithString: text)
    l.font = font
    l.textColor = color
    l.alignment = align
    l.preferredMaxLayoutWidth = DIALOG_WIDTH
    l.isSelectable = true
    // Más aire: interlineado y separación entre párrafos
    let p = NSMutableParagraphStyle()
    p.alignment = align
    p.lineSpacing = 3
    p.paragraphSpacing = 8
    l.attributedStringValue = NSAttributedString(string: text, attributes: [
        .font: font, .foregroundColor: color, .paragraphStyle: p])
    return l
}

/// Lo que va a hacer un diálogo que pide confirmar varios cambios: «Qué se va a realizar» y los
/// cambios numerados, a la izquierda y separados entre sí (cada uno con sangría francesa)
func dialogSteps(_ steps: [String]) -> NSTextField {
    let out = NSMutableAttributedString()
    let body = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let bold = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
    let green = NSColor(red: 0x45 / 255.0, green: 0xA5 / 255.0, blue: 0x7C / 255.0, alpha: 1)
    let head = NSMutableParagraphStyle()
    head.paragraphSpacing = 4
    out.append(NSAttributedString(string: "Qué se va a realizar\n", attributes: [
        .font: bold, .foregroundColor: NSColor.labelColor, .paragraphStyle: head]))
    for (i, step) in steps.enumerated() {
        let p = NSMutableParagraphStyle()
        p.tabStops = [NSTextTab(textAlignment: .left, location: 28)]
        p.defaultTabInterval = 28
        p.firstLineHeadIndent = 6
        p.headIndent = 28
        p.lineSpacing = 3
        p.paragraphSpacingBefore = 10
        let end = i == steps.count - 1 ? "" : "\n"
        out.append(NSAttributedString(string: "\(i + 1).", attributes: [
            .font: bold, .foregroundColor: green, .paragraphStyle: p]))
        out.append(NSAttributedString(string: "\t" + step + end, attributes: [
            .font: body, .foregroundColor: NSColor.labelColor, .paragraphStyle: p]))
    }
    let l = NSTextField(wrappingLabelWithString: "")
    l.alignment = .left
    l.preferredMaxLayoutWidth = DIALOG_WIDTH
    l.isSelectable = true
    // (sin esto, al seleccionar se pierden los colores y las sangrías)
    l.allowsEditingTextAttributes = true
    l.attributedStringValue = out
    return l
}

/// Accesorio de un diálogo: las vistas en columna, centradas y con aire entre ellas
func dialogStack(_ views: [NSView], spacing: CGFloat = 16) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = spacing
    stack.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 8, right: 0)
    for v in views {
        if let l = v as? NSTextField, !l.isEditable {
            l.translatesAutoresizingMaskIntoConstraints = false
            l.widthAnchor.constraint(equalToConstant: DIALOG_WIDTH).isActive = true
        }
        stack.addArrangedSubview(v)
    }
    stack.layoutSubtreeIfNeeded()
    stack.frame = NSRect(x: 0, y: 0, width: DIALOG_WIDTH, height: stack.fittingSize.height)
    return stack
}

/// Opciones (botones de opción con su nota debajo) alineadas entre sí a la izquierda: en un diálogo,
/// el bloque va centrado, pero cada opción no (quedarían a distintas alturas del borde)
func dialogOptions(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = spacing
    return stack
}

/// Botones de opción que van en columnas distintas y aun así se excluyen entre sí
final class RadioGroup: NSObject {
    var buttons: [NSButton] = []
    /// (opcional) se llama con el índice del elegido
    var onPick: ((Int) -> Void)? = nil
    @objc func pick(_ sender: NSButton) {
        for b in buttons { b.state = b === sender ? .on : .off }
        if let i = buttons.firstIndex(where: { $0 === sender }) { onPick?(i) }
    }
}

/// Ancho de un desplegable o un campo para que se vea entero el texto más largo (con la flecha y
/// los márgenes), entre min y max
func fitWidth(_ texts: [String], min lo: CGFloat, max hi: CGFloat) -> CGFloat {
    let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let widest = texts.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
    return Swift.min(hi, Swift.max(lo, (widest + 48).rounded(.up)))
}

struct DialogResult {
    var ok = false
    var checked = false
    var text = ""
}

final class DialogValidator: NSObject, NSTextFieldDelegate {
    var update: () -> Void = {}
    @objc func changed(_ sender: Any?) { update() }
    func controlTextDidChange(_ obj: Notification) { update() }
}

/// Ventana modal con casilla y campo de texto opcionales.
/// validate(casilla marcada, texto) -> (se puede aceptar, texto de la nota, la nota es un error).
/// Si hay casilla y campo, el campo solo se puede usar con la casilla desmarcada (confirmar sin copia).
/// copyWarning: con casilla, el aviso en rojo que sale debajo de ella mientras está desmarcada (marcada, dónde
/// queda la copia).
@discardableResult
/// okLabel dice lo que hace («Borrar la BBDD»), no «Aceptar»; cancelLabel, lo que hace el otro
/// botón (Cancelar, o «Seguir» si lo que se confirma es cancelar una tarea)
func runDialog(title: String, text: String, okLabel: String, style: NSAlert.Style = .informational,
               destructive: Bool = false, checkbox: String? = nil, checked: Bool = true,
               hasField: Bool = false, fieldLabel: String? = nil, placeholder: String = "",
               value: String = "", secure: Bool = false, cancelLabel: String = "Cancelar",
               steps: [String] = [], copyWarning: String? = nil, warning: String? = nil,
               validate: ((Bool, String) -> (Bool, String?, Bool))? = nil) -> DialogResult {
    let alert = NSAlert()
    alert.messageText = title
    alert.alertStyle = style
    let ok = alert.addButton(withTitle: okLabel)
    let cancel = alert.addButton(withTitle: cancelLabel)
    if destructive {
        ok.hasDestructiveAction = true
        // En las acciones destructivas Intro no acepta
        // (con Escape y no con Intro: si no, Cancelar sale con el color de acento, como si fuera el
        // principal)
        ok.keyEquivalent = ""
        cancel.keyEquivalent = "\u{1b}"
    }

    let width = DIALOG_WIDTH
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 16
    stack.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 8, right: 0)
    if !steps.isEmpty {
        let l = dialogSteps(steps)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: width).isActive = true
        stack.addArrangedSubview(l)
    }
    if !text.isEmpty {
        // (con los cambios numerados encima, el texto es una nota: a la izquierda, como ellos)
        let l = steps.isEmpty ? dialogLabel(text) : dialogLabel(text, color: .secondaryLabelColor, align: .left)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: width).isActive = true
        stack.addArrangedSubview(l)
    }
    // (warning: un aviso en rojo debajo del texto, como «no se puede recuperar» de la limpieza)
    if let w = warning {
        let n = NSTextField(wrappingLabelWithString: w)
        n.preferredMaxLayoutWidth = width
        n.alignment = .center
        n.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        n.textColor = .systemRed
        stack.addArrangedSubview(n)
    }
    let validator = DialogValidator()
    var box: NSButton? = nil
    var input: NSTextField? = nil
    var note: NSTextField? = nil

    if let c = checkbox {
        let b = NSButton(checkboxWithTitle: c, target: validator, action: #selector(DialogValidator.changed(_:)))
        b.state = checked ? .on : .off
        stack.addArrangedSubview(b)
        box = b
    }
    var copyNote: NSTextField? = nil
    if let w = copyWarning, box != nil {
        let n = NSTextField(wrappingLabelWithString: w)
        n.preferredMaxLayoutWidth = width
        n.alignment = .center
        n.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        n.textColor = .systemRed
        stack.addArrangedSubview(n)
        copyNote = n
    }
    if hasField {
        if let l = fieldLabel {
            let n = NSTextField(wrappingLabelWithString: l)
            n.preferredMaxLayoutWidth = width
            n.alignment = .center
            n.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            n.textColor = .secondaryLabelColor
            stack.addArrangedSubview(n)
            note = n
        }
        let f: NSTextField = secure ? NSSecureTextField() : NSTextField()
        // Campo algo más alto, como los de Ajustes del Sistema
        f.controlSize = .large
        f.font = NSFont.systemFont(ofSize: 13)
        f.placeholderString = placeholder
        f.stringValue = value
        f.delegate = validator
        f.translatesAutoresizingMaskIntoConstraints = false
        f.widthAnchor.constraint(equalToConstant: width).isActive = true
        stack.addArrangedSubview(f)
        input = f
    }
    if !stack.arrangedSubviews.isEmpty {
        stack.layoutSubtreeIfNeeded()
        let h = max(stack.fittingSize.height, 24)
        stack.frame = NSRect(x: 0, y: 0, width: width, height: h)
        alert.accessoryView = stack
    }

    validator.update = {
        let isChecked = box?.state == .on
        if let n = copyNote, let w = copyWarning {
            // (el mismo sitio con otro texto: el diálogo no cambia de alto al marcarla)
            n.stringValue = isChecked ? "La copia queda en ~/nexum-backups: se puede volver a cargar." : w
            n.textColor = isChecked ? .secondaryLabelColor : .systemRed
        }
        if let f = input, box != nil { f.isEnabled = !isChecked }
        if let v = validate {
            let (enabled, message, isError) = v(isChecked, input?.stringValue ?? "")
            ok.isEnabled = enabled
            if let n = note, let m = message {
                n.stringValue = m
                n.textColor = isError ? .systemRed : .secondaryLabelColor
            }
        }
    }
    validator.update()
    if let f = input, f.isEnabled { alert.window.initialFirstResponder = f }

    let resp = alert.runStyled()
    return DialogResult(ok: resp == .alertFirstButtonReturn, checked: box?.state == .on,
                        text: (input?.stringValue ?? "").trimmingCharacters(in: .whitespaces))
}

/// Contraseña de administrador, como el diálogo de autorización de macOS: centrado, con aire, el
/// icono de la aplicación con un candado, un campo estrecho y alto y botones grandes
struct PasswordView: View {
    let user: String
    let retry: Bool
    let onDone: (String?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.gray))
                    .overlay(Circle().stroke(Color(NSColor.windowBackgroundColor), lineWidth: 2))
                    .offset(x: 6, y: 4)
            }
            .padding(.bottom, 18)
            Text("Contraseña de administrador")
                .font(.system(size: 15, weight: .bold))
                .padding(.bottom, 8)
            Text("Esta acción necesita permisos de administrador. Escribe la contraseña de \(user) para continuar.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if retry {
                Text("Contraseña incorrecta. Vuelve a intentarlo.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(RED)
                    .padding(.top, 10)
            }
            SecureField("Contraseña", text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { if !text.isEmpty { onDone(text) } }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(NSColor.textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(focused ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.18),
                            lineWidth: focused ? 2 : 1))
                .frame(width: 236)
                .padding(.top, 22)
            HStack(spacing: 10) {
                Button(action: { onDone(nil) }) { Text("Cancelar").frame(maxWidth: .infinity) }
                    .keyboardShortcut(.cancelAction)
                    .hoverPointer()
                Button(action: { onDone(text) }) { Text("Continuar").frame(maxWidth: .infinity) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.isEmpty)
                    .hoverPointer()
            }
            .controlSize(.large)
            .frame(width: 236)
            .padding(.top, 22)
        }
        .padding(.horizontal, 32)
        .padding(.top, 30)
        .padding(.bottom, 24)
        .frame(width: 320)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true }
        }
    }
}

enum PasswordPanel {
    /// Pide la contraseña en una ventana propia (modal). nil si se cancela
    static func ask(user: String, retry: Bool) -> String? {
        var result: String? = nil
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 300),
                            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(b)?.isHidden = true
        }
        let host = NSHostingView(rootView: PasswordView(user: user, retry: retry, onDone: { text in
            result = text
            NSApp.stopModal()
        }))
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return result
    }
}

extension NSAlert {
    /// Como runModal, pero con los botones de la ventana: grandes y el principal (el primero) en
    /// azul, o en rojo si borra; no con el color de acento del sistema (gris con el acento grafito)
    @discardableResult
    func runStyled() -> NSApplication.ModalResponse {
        let blue = NSColor(srgbRed: 0x0A / 255.0, green: 0x84 / 255.0, blue: 1, alpha: 1)
        for (i, b) in buttons.enumerated() {
            b.controlSize = .large
            if i == 0 {
                b.bezelColor = b.hasDestructiveAction ? .systemRed : blue
            }
        }
        // (después de layout() se pueden mover sus vistas: NSAlert ya no las vuelve a colocar)
        layout()
        centerTexts()
        return runModal()
    }

    /// El título y el texto informativo, centrados. Con una vista accesoria ancha, NSAlert los pone
    /// a la izquierda, en una columna estrecha: se les da el ancho de la vista accesoria (que va
    /// debajo, en la misma columna) y se centran
    func centerTexts() {
        guard let content = window.contentView else { return }
        let acc = accessoryView
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        func walk(_ v: NSView) {
            for s in v.subviews {
                if let a = acc, s === a { continue }
                if let t = s as? NSTextField, !t.isEditable, !t.stringValue.isEmpty,
                   t.stringValue == messageText || t.stringValue == informativeText {
                    t.alignment = .center
                    let m = NSMutableAttributedString(attributedString: t.attributedStringValue)
                    m.addAttribute(.paragraphStyle, value: center, range: NSRange(location: 0, length: m.length))
                    t.attributedStringValue = m
                    if let a = acc, let sup = t.superview, let asup = a.superview {
                        let r = sup.convert(a.frame, from: asup)
                        if r.width > t.frame.width {
                            t.frame = NSRect(x: r.minX, y: t.frame.minY, width: r.width, height: t.frame.height)
                        }
                    }
                }
                walk(s)
            }
        }
        walk(content)
    }
}

func message(_ title: String, _ text: String = "", error: Bool = false) {
    let alert = NSAlert()
    alert.messageText = title
    alert.alertStyle = error ? .warning : .informational
    alert.addButton(withTitle: "Cerrar")
    let l = dialogLabel(text)
    let h = text.isEmpty ? 1 : l.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: DIALOG_WIDTH, height: 10000)).height
    l.frame = NSRect(x: 0, y: 0, width: DIALOG_WIDTH, height: ceil(h))
    alert.accessoryView = l
    alert.runStyled()
}

/// steps: los cambios que se van a hacer (numerados, con «Qué se va a realizar»); text va entonces
/// debajo, como nota. warning: un aviso en rojo debajo de todo
func confirm(_ title: String, _ text: String, _ okLabel: String, destructive: Bool = false,
             steps: [String] = [], warning: String? = nil) -> Bool {
    return runDialog(title: title, text: text, okLabel: okLabel, style: destructive ? .warning : .informational,
                     destructive: destructive, steps: steps, warning: warning).ok
}

/// La casilla de guardar antes una copia en ~/nexum-backups (desmarcada) con el aviso en rojo debajo, para un
/// NSAlert hecho a mano. El validador hay que retenerlo mientras se ve el diálogo (el botón no lo retiene)
func copyCheckViews(warning: String = COPY_WARNING) -> (box: NSButton, note: NSTextField, validator: DialogValidator) {
    let validator = DialogValidator()
    let b = NSButton(checkboxWithTitle: COPY_CHECKBOX, target: validator, action: #selector(DialogValidator.changed(_:)))
    b.state = .off
    let n = NSTextField(wrappingLabelWithString: warning)
    n.preferredMaxLayoutWidth = DIALOG_WIDTH
    n.alignment = .center
    n.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    n.textColor = .systemRed
    validator.update = { [weak b, weak n] in
        guard let b = b, let n = n else { return }
        let on = b.state == .on
        n.stringValue = on ? "La copia queda en ~/nexum-backups: se puede volver a cargar." : warning
        n.textColor = on ? .secondaryLabelColor : .systemRed
    }
    return (b, n, validator)
}

/// Como confirm, con la casilla de guardar antes una copia en ~/nexum-backups (desmarcada) y, mientras lo
/// esté, el aviso en rojo (warning). copy: si se ha marcado (se pasa --copia)
func confirmCopy(_ title: String, _ text: String, _ okLabel: String, destructive: Bool = false,
                 steps: [String] = [], warning: String = COPY_WARNING) -> (ok: Bool, copy: Bool) {
    let r = runDialog(title: title, text: text, okLabel: okLabel, style: destructive ? .warning : .informational,
                      destructive: destructive, checkbox: COPY_CHECKBOX, checked: false, steps: steps,
                      copyWarning: warning)
    return (r.ok, r.ok && r.checked)
}

/// Markdown de «lvm-instalador novedades»: «## versión · fecha», viñetas «- » (con dos espacios
/// delante, dentro de la anterior), **negrita** y `código`
func markdownAttributed(_ text: String) -> NSAttributedString {
    let out = NSMutableAttributedString()
    let body = NSFont.systemFont(ofSize: 13)
    let bold = NSFont.boldSystemFont(ofSize: 13)
    let code = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let green = NSColor(red: 0x45 / 255.0, green: 0xA5 / 255.0, blue: 0x7C / 255.0, alpha: 1)
    // (con aire: espacio entre versiones, entre puntos y entre las líneas de un mismo punto)
    func para(indent: CGFloat, hanging: CGFloat, before: CGFloat, after: CGFloat) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.firstLineHeadIndent = indent
        p.headIndent = indent + hanging
        p.paragraphSpacingBefore = before
        p.paragraphSpacing = after
        p.lineSpacing = 4
        return p
    }
    func add(_ s: String, _ font: NSFont, _ color: NSColor, _ style: NSParagraphStyle, background: NSColor? = nil) {
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        if let bg = background { attrs[.backgroundColor] = bg }
        out.append(NSAttributedString(string: s, attributes: attrs))
    }
    let pieces = try! NSRegularExpression(pattern: "(\\*\\*[^*]+\\*\\*|`[^`]+`)")
    var first = true
    for line in text.components(separatedBy: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
        if !first { add("\n", body, .labelColor, NSParagraphStyle.default) }
        let top = first
        first = false
        if line.hasPrefix("## ") {
            let parts = String(line.dropFirst(3)).components(separatedBy: " · ")
            let style = para(indent: 0, hanging: 0, before: top ? 0 : 28, after: 10)
            add(parts[0], NSFont.boldSystemFont(ofSize: 17), .labelColor, style)
            if parts.count > 1 {
                add("   " + parts[1], NSFont.systemFont(ofSize: 11), .secondaryLabelColor, style)
            }
            continue
        }
        var style = para(indent: 0, hanging: 0, before: 6, after: 8)
        var rest = line
        let spaces = line.prefix(while: { $0 == " " }).count
        if line.dropFirst(spaces).hasPrefix("- ") {
            let depth = min(spaces / 2, 1)
            style = para(indent: depth == 0 ? 8 : 28, hanging: 14, before: depth == 0 ? 10 : 6, after: 2)
            add(depth == 0 ? "•  " : "◦  ", bold, green, style)
            rest = String(line.dropFirst(spaces + 2))
        }
        let ns = rest as NSString
        var pos = 0
        for m in pieces.matches(in: rest, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > pos {
                add(ns.substring(with: NSRange(location: pos, length: m.range.location - pos)), body, .labelColor, style)
            }
            let s = ns.substring(with: m.range)
            if s.hasPrefix("**") {
                add(String(s.dropFirst(2).dropLast(2)), bold, .labelColor, style)
            } else {
                add(String(s.dropFirst().dropLast()), code, .labelColor, style,
                    background: NSColor.gray.withAlphaComponent(0.16))
            }
            pos = m.range.location + m.range.length
        }
        if pos < ns.length { add(ns.substring(from: pos), body, .labelColor, style) }
    }
    return out
}

/// Texto largo con desplazamiento (Novedades en Markdown, comandos, registros)
/// Ayuda de los comandos: cada sección («=== TÍTULO ===») en verde y grande y cada orden en negrita,
/// para distinguirlas de su explicación (con sangría, debajo)
func commandsAttributed(_ text: String) -> NSAttributedString {
    let out = NSMutableAttributedString()
    let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let monoBold = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    let green = NSColor(red: 0x45 / 255.0, green: 0xA5 / 255.0, blue: 0x7C / 255.0, alpha: 1)
    for (n, line) in text.components(separatedBy: "\n").enumerated() {
        let p = NSMutableParagraphStyle()
        var font = mono, color = NSColor.labelColor
        if line.hasPrefix("=== ") {
            font = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .bold)
            color = green
            p.paragraphSpacingBefore = 10
            p.paragraphSpacing = 4
        } else if line.hasPrefix("  lvm-instalador") {
            font = monoBold
            p.paragraphSpacingBefore = 4
        }
        out.append(NSAttributedString(string: (n > 0 ? "\n" : "") + line,
                                      attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p]))
    }
    return out
}

func showLongText(_ title: String, _ text: String, subtitle: String = "", toEnd: Bool = false,
                  markdown: Bool = false, commands: Bool = false) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = subtitle
    alert.addButton(withTitle: "Cerrar")
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 720, height: 560))
    scroll.hasVerticalScroller = true
    let tv = NSTextView(frame: scroll.bounds)
    tv.isEditable = false
    tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    tv.textContainerInset = NSSize(width: 10, height: 10)
    if markdown {
        tv.textContainerInset = NSSize(width: 18, height: 14)
        tv.textStorage?.setAttributedString(markdownAttributed(text))
    } else if commands {
        tv.textContainerInset = NSSize(width: 16, height: 12)
        tv.textStorage?.setAttributedString(commandsAttributed(text))
    } else {
        tv.string = text
    }
    tv.autoresizingMask = [.width]
    scroll.documentView = tv
    alert.accessoryView = scroll
    // Registros: lo más reciente está al final
    if toEnd { DispatchQueue.main.async { tv.scrollToEndOfDocument(nil) } }
    alert.runStyled()
}

// Proyectos (htdocs compartido; LVM_HTDOCS solo para pruebas) y dominio de un proyecto nuevo
let HTDOCS = ProcessInfo.processInfo.environment["LVM_HTDOCS"] ?? "/Library/Nexum/XAMPP-compartido/htdocs"
let DOMAIN_RX = try! NSRegularExpression(pattern: "^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$")
/// Dominio escrito o pegado como dirección (https://www.mitienda.com/tienda): solo el nombre
func cleanDomain(_ text: String) -> String {
    var d = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let r = d.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) { d.removeSubrange(r) }
    if let cut = d.firstIndex(where: { "/?#:".contains($0) || $0.isWhitespace }) { d = String(d[..<cut]) }
    while d.hasSuffix(".") { d.removeLast() }
    return d
}
let FOLDER_RX = try! NSRegularExpression(pattern: "^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$")
let ERROR_LOG = "/Applications/XAMPP/xamppfiles/logs/error_log"
// Registros mayores que esto no se abren en el editor de textos (solo «Ver el final»)
let LOG_OPEN_MAX: Int64 = 20 * 1024 * 1024

/// Carpetas de proyectos de htdocs (sin enlaces como web.local ni ocultas)
func projectFolders() -> [String] {
    let fm = FileManager.default
    let names = (try? fm.contentsOfDirectory(atPath: HTDOCS)) ?? []
    return names.filter { n in
        if n.hasPrefix(".") { return false }
        let path = HTDOCS + "/" + n
        let attrs = try? fm.attributesOfItem(atPath: path)
        if (attrs?[.type] as? FileAttributeType) == .typeSymbolicLink { return false }
        var dir: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
    }.sorted { $0.lowercased() < $1.lowercased() }
}

/// Base de datos de la configuración de un proyecto (wp-config.php, PrestaShop o .env)
func projectDb(_ folder: String) -> String {
    let rules: [(String, String)] = [
        ("wp-config.php", "define\\(\\s*['\"]DB_NAME['\"]\\s*,\\s*['\"]([^'\"]+)"),
        ("app/config/parameters.php", "['\"]database_name['\"]\\s*=>\\s*['\"]([^'\"]+)"),
        ("config/settings.inc.php", "define\\(\\s*['\"]_DB_NAME_['\"]\\s*,\\s*['\"]([^'\"]+)"),
        (".env", "^\\s*DB_DATABASE\\s*=\\s*[\"']?([^\"'\\s#]+)"),
    ]
    for (rel, pattern) in rules {
        let path = HTDOCS + "/" + folder + "/" + rel
        // Solo un fichero normal de hasta 2 MB y sin enlaces: un FIFO o un enlace a /dev/zero de un
        // proyecto colgarian la ventana
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              (attrs[.type] as? FileAttributeType) == .typeRegular,
              let size = attrs[.size] as? NSNumber, size.intValue <= 2_000_000,
              let text = try? String(contentsOfFile: path, encoding: .utf8),
              let rx = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines),
              let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { continue }
        // Solo nombres de BBDD validos (la configuracion la trae el proyecto)
        let db = String(text[r])
        return db.range(of: "^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil ? db : ""
    }
    return ""
}
