// MARK: - Barra lateral

/// Apartados: clave, texto e icono (logo:<paquete> o un símbolo)
let NAV: [(String, [(String, String, String)])] = [
    ("ENTORNO", [("proyectos", "Proyectos", "folder"), ("repos", "Repositorios", "logo:github"),
                 ("versiones", "Versiones de PHP", "logo:php"),
                 ("bbdd", "Bases de datos", "logo:bbdd"), ("docker", "Docker", "logo:docker"),
                 ("node", "Node", "logo:node")]),
    ("SISTEMA", [("dominios", "Dominios y hosts", "network"), ("config", "Configuración", "gearshape")]),
]

/// Apariencia (~/.nexum/apariencia, el mismo fichero que en Linux): iconos en color, Docker, Node
/// y PHP con su logotipo, y qué apartados no salen en el menú lateral (Proyectos y Configuración, siempre)
let LOOK_FILE = LOG_DIR + "/apariencia"
let NAV_FIXED: Set<String> = ["proyectos", "config"]
/// Color de los símbolos del sistema con los iconos en color
let NAV_TINTS: [String: Color] = ["proyectos": hexColor(0xE8A23A), "dominios": hexColor(0x1C9C6B), "config": hexColor(0x7C6FD8)]

struct LookConf: Equatable {
    var color = false
    var marcas = false
    var ocultos: Set<String> = []
}

func loadLook() -> LookConf {
    var c = LookConf()
    guard let data = FileManager.default.contents(atPath: LOOK_FILE),
          let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return c }
    let keys = Set(NAV.flatMap { $0.1.map { $0.0 } }).subtracting(NAV_FIXED)
    c.color = o["color"] as? Bool ?? false
    c.marcas = o["marcas"] as? Bool ?? false
    c.ocultos = Set((o["ocultos"] as? [String] ?? []).filter { keys.contains($0) })
    return c
}

func saveLook(_ c: LookConf) {
    if SIMULATE { return }
    let o: [String: Any] = ["color": c.color, "marcas": c.marcas, "ocultos": c.ocultos.sorted()]
    guard let data = try? JSONSerialization.data(withJSONObject: o) else { return }
    try? FileManager.default.createDirectory(atPath: LOG_DIR, withIntermediateDirectories: true,
                                             attributes: [.posixPermissions: 0o700])
    let tmp = LOOK_FILE + ".nuevo"
    if FileManager.default.createFile(atPath: tmp, contents: data) {
        _ = try? FileManager.default.replaceItemAt(URL(fileURLWithPath: LOOK_FILE), withItemAt: URL(fileURLWithPath: tmp))
        if !FileManager.default.fileExists(atPath: LOOK_FILE) { try? FileManager.default.moveItem(atPath: tmp, toPath: LOOK_FILE) }
    }
}

/// Los logotipos con su tipografía: los oficiales de Docker (docker.com), Node.js (nodejs.org; letra oscura en
/// el tema claro y clara en el oscuro) y PHP (php.net), en PDF (vectoriales, nítidos a cualquier tamaño).
/// docker-letras: solo las letras, sin la ballena (va al lado de su icono). Los de Node, sin la máscara del SVG
/// original (macOS no los dibujaba con ella)
let BRAND_PDF: [String: String] = [
    "docker": "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",
    "docker-letras": "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",
    "node-claro": "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NAplbmRvYmoKMyAwIG9iago8PAogICAvRXh0R1N0YXRlIDw8CiAgICAgIC9hMCA8PCAvQ0EgMSAvY2EgMSA+PgogICA+PgogICAvU2hhZGluZyA8PCAvc2g3IDcgMCBSIC9zaDggOCAwIFIgL3NoOSA5IDAgUiA+Pgo+PgplbmRvYmoKMTEgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAyCiAgIC9Eb21haW4gWyAwIDEgXQogICAvQzAgWyAwLjI0NzA1OSAwLjU0NTA5OCAwLjIzOTIxNiBdCiAgIC9DMSBbIDAuMjQ3MDU5IDAuNTI5NDEyIDAuMjQ3MDU5IF0KICAgL04gMQo+PgplbmRvYmoKMTIgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAyCiAgIC9Eb21haW4gWyAwIDEgXQogICAvQzAgWyAwLjI0NzA1OSAwLjUyOTQxMiAwLjI0NzA1OSBdCiAgIC9DMSBbIDAuMjM5MjE2IDAuNjYyNzQ1IDAuMTgwMzkyIF0KICAgL04gMQo+PgplbmRvYmoKMTMgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAyCiAgIC9Eb21haW4gWyAwIDEgXQogICAvQzAgWyAwLjIzOTIxNiAwLjY2Mjc0NSAwLjE4MDM5MiBdCiAgIC9DMSBbIDAuMjM5MjE2IDAuNjgyMzUzIDAuMTY4NjI3IF0KICAgL04gMQo+PgplbmRvYmoKMTQgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAzCiAgIC9Eb21haW4gWyAwIDEgXQogICAvRnVuY3Rpb25zIFsgMTEgMCBSIDEyIDAgUiAxMyAwIFIgXQogICAvQm91bmRzIFsgMC42NCAwLjkzIF0KICAgL0VuY29kZSBbIDAgMSAwIDEgMCAxIF0KPj4KZW5kb2JqCjcgMCBvYmoKICAgICAgPDwgL1NoYWRpbmdUeXBlIDIKICAgICAgICAgL0NvbG9yU3BhY2UgL0RldmljZVJHQgogICAgICAgICAvQ29vcmRzIFsgMzAuMzMgOC41NiAxNC45IDQ0LjcwMDAwMSBdCiAgICAgICAgIC9Eb21haW4gWyAwIDEgXQogICAgICAgICAvRXh0ZW5kIFsgdHJ1ZSB0cnVlIF0KICAgICAgICAgL0Z1bmN0aW9uIDE0IDAgUgogICAgICA+PgplbmRvYmoKMTUgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAyCiAgIC9Eb21haW4gWyAwIDEgXQogICAvQzAgWyAwLjI0NzA1OSAwLjUyOTQxMiAwLjI0NzA1OSBdCiAgIC9DMSBbIDAuMzIxNTY5IDAuNjI3NDUxIDAuMjY2NjY3IF0KICAgL04gMQo+PgplbmRvYmoKMTYgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAyCiAgIC9Eb21haW4gWyAwIDEgXQogICAvQzAgWyAwLjMyMTU2OSAwLjYyNzQ1MSAwLjI2NjY2NyBdCiAgIC9DMSBbIDAuMzkyMTU3IDAuNzE3NjQ3IDAuMjg2Mjc1IF0KICAgL04gMQo+PgplbmRvYmoKMTcgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAyCiAgIC9Eb21haW4gWyAwIDEgXQogICAvQzAgWyAwLjM5MjE1NyAwLjcxNzY0NyAwLjI4NjI3NSBdCiAgIC9DMSBbIDAuNDE1Njg2IDAuNzQ5MDIgMC4yOTQxMTggXQogICAvTiAxCj4+CmVuZG9iagoxOCAwIG9iago8PCAvRnVuY3Rpb25UeXBlIDMKICAgL0RvbWFpbiBbIDAuMTQgMC45MSBdCiAgIC9GdW5jdGlvbnMgWyAxNSAwIFIgMTYgMCBSIDE3IDAgUiBdCiAgIC9Cb3VuZHMgWyAwLjQgMC43MSBdCiAgIC9FbmNvZGUgWyAwIDEgMCAxIDAgMSBdCj4+CmVuZG9iago4IDAgb2JqCiAgICAgIDw8IC9TaGFkaW5nVHlwZSAyCiAgICAgICAgIC9Db2xvclNwYWNlIC9EZXZpY2VSR0IKICAgICAgICAgL0Nvb3JkcyBbIDI1LjY4Nzk5OSAyMy4xMDM5OTkgNjMuNTcyMDAxIDIuNzc1OTk5IF0KICAgICAgICAgL0RvbWFpbiBbIDAuMTQgMC45MSBdCiAgICAgICAgIC9FeHRlbmQgWyB0cnVlIHRydWUgXQogICAgICAgICAvRnVuY3Rpb24gMTggMCBSCiAgICAgID4+CmVuZG9iagoxOSAwIG9iago8PCAvRnVuY3Rpb25UeXBlIDIKICAgL0RvbWFpbiBbIDAgMSBdCiAgIC9DMCBbIDAuNDE1Njg2IDAuNzQ5MDIgMC4yOTQxMTggXQogICAvQzEgWyAwLjM5MjE1NyAwLjcxNzY0NyAwLjI4NjI3NSBdCiAgIC9OIDEKPj4KZW5kb2JqCjIwIDAgb2JqCjw8IC9GdW5jdGlvblR5cGUgMgogICAvRG9tYWluIFsgMCAxIF0KICAgL0MwIFsgMC4zOTIxNTcgMC43MTc2NDcgMC4yODYyNzUgXQogICAvQzEgWyAwLjMyMTU2OSAwLjYyNzQ1MSAwLjI2NjY2NyBdCiAgIC9OIDEKPj4KZW5kb2JqCjIxIDAgb2JqCjw8IC9GdW5jdGlvblR5cGUgMgogICAvRG9tYWluIFsgMCAxIF0KICAgL0MwIFsgMC4zMjE1NjkgMC42Mjc0NTEgMC4yNjY2NjcgXQogICAvQzEgWyAwLjI0NzA1OSAwLjUyOTQxMiAwLjI0NzA1OSBdCiAgIC9OIDEKPj4KZW5kb2JqCjIyIDAgb2JqCjw8IC9GdW5jdGlvblR5cGUgMwogICAvRG9tYWluIFsgMC4wOSAwLjg2IF0KICAgL0Z1bmN0aW9ucyBbIDE5IDAgUiAyMCAwIFIgMjEgMCBSIF0KICAgL0JvdW5kcyBbIDAuMjkgMC42IF0KICAgL0VuY29kZSBbIDAgMSAwIDEgMCAxIF0KPj4KZW5kb2JqCjkgMCBvYmoKICAgICAgPDwgL1NoYWRpbmdUeXBlIDIKICAgICAgICAgL0NvbG9yU3BhY2UgL0RldmljZVJHQgogICAgICAgICAvQ29vcmRzIFsgNC4xODc1IDI0LjUgMzcuODc1MDAxIDI0LjUgXQogICAgICAgICAvRG9tYWluIFsgMC4wOSAwLjg2IF0KICAgICAgICAgL0V4dGVuZCBbIHRydWUgdHJ1ZSBdCiAgICAgICAgIC9GdW5jdGlvbiAyMiAwIFIKICAgICAgPj4KZW5kb2JqCjEwIDAgb2JqCjw8IC9UeXBlIC9PYmpTdG0KICAgL0xlbmd0aCAyMyAwIFIKICAgL04gMQogICAvRmlyc3QgNAogICAvRmlsdGVyIC9GbGF0ZURlY29kZQo+PgpzdHJlYW0KeJwzUzDgiuaK5QIABjgBXQplbmRzdHJlYW0KZW5kb2JqCjIzIDAgb2JqCiAgIDE2CmVuZG9iagoyNCAwIG9iago8PCAvVHlwZSAvT2JqU3RtCiAgIC9MZW5ndGggMjcgMCBSCiAgIC9OIDQKICAgL0ZpcnN0IDIzCiAgIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCj4+CnN0cmVhbQp4nFWRQWuEMBCF7/6KdylVCprEqssie1iFpZSC7PZWeggxuEIxksTS/fdNdLWUwMB8vMl7w1CQgGXIXAXNaMBypEUalCWS99sokTS8kyYAkLz2rcEHGAjO+JxRpabBggaHwzzRaNVOQmqEgvdagcZ0FxOEV2tHs0+SmXaaj9demFjpLoqWb7TktldDza1EWO8ZYTmllDCSFTR9IvSRkGg1+YuFB2ft5xuupc/hk83gTbY9P6ofF5e4x/ICO7JlHqxTGzxv8pNW04iy9I3vF4uZrujiqOaDGb2VuK34BVZPcu0qp6rldy/k+XT00EX2/CyNmrSQBunmeXGDwi7JjTvCv+0qbvmX6u7LuQPcd3OiX7mkbpoKZW5kc3RyZWFtCmVuZG9iagoyNyAwIG9iagogICAyNzYKZW5kb2JqCjI4IDAgb2JqCjw8IC9UeXBlIC9YUmVmCiAgIC9MZW5ndGggMTA5CiAgIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCiAgIC9TaXplIDI5CiAgIC9XIFsxIDIgMl0KICAgL1Jvb3QgMjYgMCBSCiAgIC9JbmZvIDI1IDAgUgo+PgpzdHJlYW0KeJxjYGD4/5+JQYKBAUQwMXJNZWBgZOAHElx1IDEuIIvXG0gIRAMJYaAYo0gYkOAWABFzgQSPFojYDiT4ZEDESiDBbwYiDgEJQXsQcRpICEWAiKcgA26BiA8QKxlBBDOjWCVQTGwCAwMAIWYO6wplbmRzdHJlYW0KZW5kb2JqCnN0YXJ0eHJlZgo1Nzc2CiUlRU9GCg==",
    "node-oscuro": "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bmRvYmoKMyAwIG9iago8PAogICAvRXh0R1N0YXRlIDw8CiAgICAgIC9hMCA8PCAvQ0EgMSAvY2EgMSA+PgogICA+PgogICAvU2hhZGluZyA8PCAvc2g3IDcgMCBSIC9zaDggOCAwIFIgL3NoOSA5IDAgUiA+Pgo+PgplbmRvYmoKMTEgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAyCiAgIC9Eb21haW4gWyAwIDEgXQogICAvQzAgWyAwLjI0NzA1OSAwLjU0NTA5OCAwLjIzOTIxNiBdCiAgIC9DMSBbIDAuMjQ3MDU5IDAuNTI5NDEyIDAuMjQ3MDU5IF0KICAgL04gMQo+PgplbmRvYmoKMTIgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAyCiAgIC9Eb21haW4gWyAwIDEgXQogICAvQzAgWyAwLjI0NzA1OSAwLjUyOTQxMiAwLjI0NzA1OSBdCiAgIC9DMSBbIDAuMjM5MjE2IDAuNjYyNzQ1IDAuMTgwMzkyIF0KICAgL04gMQo+PgplbmRvYmoKMTMgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAyCiAgIC9Eb21haW4gWyAwIDEgXQogICAvQzAgWyAwLjIzOTIxNiAwLjY2Mjc0NSAwLjE4MDM5MiBdCiAgIC9DMSBbIDAuMjM5MjE2IDAuNjgyMzUzIDAuMTY4NjI3IF0KICAgL04gMQo+PgplbmRvYmoKMTQgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAzCiAgIC9Eb21haW4gWyAwIDEgXQogICAvRnVuY3Rpb25zIFsgMTEgMCBSIDEyIDAgUiAxMyAwIFIgXQogICAvQm91bmRzIFsgMC42NCAwLjkzIF0KICAgL0VuY29kZSBbIDAgMSAwIDEgMCAxIF0KPj4KZW5kb2JqCjcgMCBvYmoKICAgICAgPDwgL1NoYWRpbmdUeXBlIDIKICAgICAgICAgL0NvbG9yU3BhY2UgL0RldmljZVJHQgogICAgICAgICAvQ29vcmRzIFsgMzAuMzMgOC41NiAxNC45IDQ0LjcwMDAwMSBdCiAgICAgICAgIC9Eb21haW4gWyAwIDEgXQogICAgICAgICAvRXh0ZW5kIFsgdHJ1ZSB0cnVlIF0KICAgICAgICAgL0Z1bmN0aW9uIDE0IDAgUgogICAgICA+PgplbmRvYmoKMTUgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAyCiAgIC9Eb21haW4gWyAwIDEgXQogICAvQzAgWyAwLjI0NzA1OSAwLjUyOTQxMiAwLjI0NzA1OSBdCiAgIC9DMSBbIDAuMzIxNTY5IDAuNjI3NDUxIDAuMjY2NjY3IF0KICAgL04gMQo+PgplbmRvYmoKMTYgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAyCiAgIC9Eb21haW4gWyAwIDEgXQogICAvQzAgWyAwLjMyMTU2OSAwLjYyNzQ1MSAwLjI2NjY2NyBdCiAgIC9DMSBbIDAuMzkyMTU3IDAuNzE3NjQ3IDAuMjg2Mjc1IF0KICAgL04gMQo+PgplbmRvYmoKMTcgMCBvYmoKPDwgL0Z1bmN0aW9uVHlwZSAyCiAgIC9Eb21haW4gWyAwIDEgXQogICAvQzAgWyAwLjM5MjE1NyAwLjcxNzY0NyAwLjI4NjI3NSBdCiAgIC9DMSBbIDAuNDE1Njg2IDAuNzQ5MDIgMC4yOTQxMTggXQogICAvTiAxCj4+CmVuZG9iagoxOCAwIG9iago8PCAvRnVuY3Rpb25UeXBlIDMKICAgL0RvbWFpbiBbIDAuMTQgMC45MSBdCiAgIC9GdW5jdGlvbnMgWyAxNSAwIFIgMTYgMCBSIDE3IDAgUiBdCiAgIC9Cb3VuZHMgWyAwLjQgMC43MSBdCiAgIC9FbmNvZGUgWyAwIDEgMCAxIDAgMSBdCj4+CmVuZG9iago4IDAgb2JqCiAgICAgIDw8IC9TaGFkaW5nVHlwZSAyCiAgICAgICAgIC9Db2xvclNwYWNlIC9EZXZpY2VSR0IKICAgICAgICAgL0Nvb3JkcyBbIDI1LjY4Nzk5OSAyMy4xMDM5OTkgNjMuNTcyMDAxIDIuNzc1OTk5IF0KICAgICAgICAgL0RvbWFpbiBbIDAuMTQgMC45MSBdCiAgICAgICAgIC9FeHRlbmQgWyB0cnVlIHRydWUgXQogICAgICAgICAvRnVuY3Rpb24gMTggMCBSCiAgICAgID4+CmVuZG9iagoxOSAwIG9iago8PCAvRnVuY3Rpb25UeXBlIDIKICAgL0RvbWFpbiBbIDAgMSBdCiAgIC9DMCBbIDAuNDE1Njg2IDAuNzQ5MDIgMC4yOTQxMTggXQogICAvQzEgWyAwLjM5MjE1NyAwLjcxNzY0NyAwLjI4NjI3NSBdCiAgIC9OIDEKPj4KZW5kb2JqCjIwIDAgb2JqCjw8IC9GdW5jdGlvblR5cGUgMgogICAvRG9tYWluIFsgMCAxIF0KICAgL0MwIFsgMC4zOTIxNTcgMC43MTc2NDcgMC4yODYyNzUgXQogICAvQzEgWyAwLjMyMTU2OSAwLjYyNzQ1MSAwLjI2NjY2NyBdCiAgIC9OIDEKPj4KZW5kb2JqCjIxIDAgb2JqCjw8IC9GdW5jdGlvblR5cGUgMgogICAvRG9tYWluIFsgMCAxIF0KICAgL0MwIFsgMC4zMjE1NjkgMC42Mjc0NTEgMC4yNjY2NjcgXQogICAvQzEgWyAwLjI0NzA1OSAwLjUyOTQxMiAwLjI0NzA1OSBdCiAgIC9OIDEKPj4KZW5kb2JqCjIyIDAgb2JqCjw8IC9GdW5jdGlvblR5cGUgMwogICAvRG9tYWluIFsgMC4wOSAwLjg2IF0KICAgL0Z1bmN0aW9ucyBbIDE5IDAgUiAyMCAwIFIgMjEgMCBSIF0KICAgL0JvdW5kcyBbIDAuMjkgMC42IF0KICAgL0VuY29kZSBbIDAgMSAwIDEgMCAxIF0KPj4KZW5kb2JqCjkgMCBvYmoKICAgICAgPDwgL1NoYWRpbmdUeXBlIDIKICAgICAgICAgL0NvbG9yU3BhY2UgL0RldmljZVJHQgogICAgICAgICAvQ29vcmRzIFsgNC4xODc1IDI0LjUgMzcuODc1MDAxIDI0LjUgXQogICAgICAgICAvRG9tYWluIFsgMC4wOSAwLjg2IF0KICAgICAgICAgL0V4dGVuZCBbIHRydWUgdHJ1ZSBdCiAgICAgICAgIC9GdW5jdGlvbiAyMiAwIFIKICAgICAgPj4KZW5kb2JqCjEwIDAgb2JqCjw8IC9UeXBlIC9PYmpTdG0KICAgL0xlbmd0aCAyMyAwIFIKICAgL04gMQogICAvRmlyc3QgNAogICAvRmlsdGVyIC9GbGF0ZURlY29kZQo+PgpzdHJlYW0KeJwzUzDgiuaK5QIABjgBXQplbmRzdHJlYW0KZW5kb2JqCjIzIDAgb2JqCiAgIDE2CmVuZG9iagoyNCAwIG9iago8PCAvVHlwZSAvT2JqU3RtCiAgIC9MZW5ndGggMjcgMCBSCiAgIC9OIDQKICAgL0ZpcnN0IDIzCiAgIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCj4+CnN0cmVhbQp4nFWRQWuEMBCF7/6KdylVCprEqssie1iFpZSC7PZWeggxuEIxksTS/fdNdLWUwMB8vMl7w1CQgGXIXAXNaMBypEUalCWS99sokTS8kyYAkLz2rcEHGAjO+JxRpabBggaHwzzRaNVOQmqEgvdagcZ0FxOEV2tHs0+SmXaaj9demFjpLoqWb7TktldDza1EWO8ZYTmllDCSFTR9IvSRkGg1+YuFB2ft5xuupc/hk83gTbY9P6ofF5e4x/ICO7JlHqxTGzxv8pNW04iy9I3vF4uZrujiqOaDGb2VuK34BVZPcu0qp6rldy/k+XT00EX2/CyNmrSQBunmeXGDwi7JjTvCv+0qbvmX6u7LuQPcd3OiX7mkbpoKZW5kc3RyZWFtCmVuZG9iagoyNyAwIG9iagogICAyNzYKZW5kb2JqCjI4IDAgb2JqCjw8IC9UeXBlIC9YUmVmCiAgIC9MZW5ndGggMTA5CiAgIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlCiAgIC9TaXplIDI5CiAgIC9XIFsxIDIgMl0KICAgL1Jvb3QgMjYgMCBSCiAgIC9JbmZvIDI1IDAgUgo+PgpzdHJlYW0KeJxjYGD4/5+JQYKBAUQwMXJNYmBgZOAHElzVIDEuIIvXA0gIRAAJYaAYo0gwkODmBRGzgASPOojYAiT4JEHEMiDBbwwi9gMJQRsQcQJICIWCiEcgA66DiLcQKxlBBDOjWBlQTKyXgQEAEJIOqQplbmRzdHJlYW0KZW5kb2JqCnN0YXJ0eHJlZgo1NzczCiUlRU9GCg==",
    "php": "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",
]
private var brandImages: [String: NSImage] = [:]

func brandImage(_ key: String) -> NSImage? {
    if let i = brandImages[key] { return i }
    guard let b = BRAND_PDF[key], let d = Data(base64Encoded: b), let i = NSImage(data: d),
          i.size.width > 0, i.size.height > 0 else { return nil }
    brandImages[key] = i
    return i
}

/// El logotipo entero de un color (su forma, con su transparencia), dibujado aquí: sin .renderingMode(.template),
/// que con los PDF con degradados (el hexágono de Node) lo pintaba como un bloque o no lo pintaba, y cada color
/// con su propia imagen (la del título de la página, sin tinte, no comparte la de la barra lateral)
private var brandTinted: [String: NSImage] = [:]

func brandImage(_ key: String, tint: NSColor) -> NSImage? {
    guard let base = brandImage(key) else { return nil }
    // (en sRGB, para leer sus componentes; si no se puede, el azul de los acentos)
    let c: NSColor = tint.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0x0A / 255.0, green: 0x84 / 255.0, blue: 1, alpha: 1)
    let id = "\(key)|" + String(format: "%.3f|%.3f|%.3f|%.3f", Double(c.redComponent), Double(c.greenComponent),
                                Double(c.blueComponent), Double(c.alphaComponent))
    if let i = brandTinted[id] { return i }
    let i = NSImage(size: base.size, flipped: false) { rect in
        base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        c.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    brandTinted[id] = i
    return i
}

/// Configuración, Apariencia: el menú lateral (iconos en color, logotipos y qué apartados salen) y los
/// botones del proyecto. Se guarda al momento
/// Configuración, Seguridad entre webs: qué es, en cuatro puntos (el mismo texto que en Linux)
let CROSS_SITE_HELP: [(String, String, String)] = [
    ("exclamationmark.triangle", "El problema",
     "Mientras trabajas, el navegador tiene abierta tu sesión en tus proyectos (el panel de WordPress, el de PrestaShop…). Cualquier otra web que abras a la vez podría mandarles a escondidas un formulario o una petición, y el navegador la enviaría con tu sesión: crear un administrador, cambiar una contraseña, borrar productos…"),
    ("lock.shield", "Lo que hace la barrera",
     "Apache rechaza lo que llega a tus proyectos desde otra web, salvo abrir una página con un enlace normal. Lo que hagas dentro del propio proyecto, o escribiendo su dirección, funciona igual."),
    ("info.circle", "Cuándo apagarla",
     "Al probar una pasarela de pago (Redsys, PayPal, Stripe…): al acabar el pago, el banco te devuelve a la tienda mandando un formulario desde su web, y la barrera lo para (sale «Otra web ha intentado mandar algo a esta»). Apágala mientras pruebas los pagos y vuelve a encenderla al acabar."),
    ("network", "Dónde se aplica",
     "En todas tus versiones de PHP (localhost, los dominios falseados y los vhosts de los proyectos) y en el Apache de Docker. Al cambiarla se recargan, si están en marcha."),
]

struct AppearanceCard: View {
    @EnvironmentObject var model: AppModel

    /// En tres bloques, cada uno con su título, porque hacen cosas distintas: cómo se ven los iconos del menú
    /// lateral, qué apartados salen en él y los botones del visor de los proyectos
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            block("Iconos del menú lateral", "Cómo se dibujan los iconos de la columna de la izquierda") {
                Tile("Iconos en color", "Cada apartado con su color; apagado, de un color, como el texto") {
                    Toggle("", isOn: Binding(get: { model.look.color }, set: { model.look.color = $0 }))
                        .toggleStyle(SwitchToggleStyle()).labelsHidden()
                }
                Tile("Logotipos de Docker, Node y PHP", "Con su logotipo y su tipografía en lugar del nombre") {
                    Toggle("", isOn: Binding(get: { model.look.marcas }, set: { model.look.marcas = $0 }))
                        .toggleStyle(SwitchToggleStyle()).labelsHidden()
                }
            }
            // (en dos columnas: la primera mitad a la izquierda y el resto a la derecha)
            let items = NAV.flatMap { $0.1 }.filter { !NAV_FIXED.contains($0.0) }
            let half = (items.count + 1) / 2
            VStack(alignment: .leading, spacing: 2) {
                Text("Apartados del menú lateral").font(.system(size: 13.5, weight: .semibold))
                Text("Cuáles se ven en la columna de la izquierda (Proyectos y Configuración salen siempre)")
                    .font(.caption).foregroundColor(.secondary)
                HStack(alignment: .top, spacing: 12) {
                    TileCard(wide: true) { navSwitches(Array(items.prefix(half))) }
                        .frame(maxWidth: .infinity)
                    TileCard(wide: true) { navSwitches(Array(items.dropFirst(half))) }
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 6)
            }
            block("Visor de los proyectos", "Los botones de cada proyecto: cuáles se ven, en qué orden y cómo") {
                Tile("Botones", buttonsSummary()) {
                    Button("Personalizar…") { model.panel = .buttons }
                }
            }
        }
        // (debajo del título grande de Configuración)
        .preference(key: ToolsDescKey.self, value: "Cómo se ve la ventana. Se guarda al momento y vale también para la versión de Linux.")
    }

    /// Los interruptores de los apartados del menú lateral que se pueden ocultar
    func navSwitches(_ items: [(String, String, String)]) -> some View {
        ForEach(items, id: \.0) { item in
            Tile(item.1) {
                Toggle("", isOn: Binding(get: { !model.look.ocultos.contains(item.0) }, set: { on in
                    if on { model.look.ocultos.remove(item.0) } else { model.look.ocultos.insert(item.0) }
                }))
                .toggleStyle(SwitchToggleStyle()).labelsHidden()
            }
        }
    }

    /// Un bloque: su título y lo que hace, y sus filas en una lista
    func block<C: View>(_ title: String, _ sub: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13.5, weight: .semibold))
            Text(sub).font(.caption).foregroundColor(.secondary)
            TileCard(wide: true) { content() }
                .padding(.top, 6)
        }
    }

    func buttonsSummary() -> String {
        let c = model.visorConf
        let names = Dictionary(uniqueKeysWithValues: VISOR_BUTTONS)
        let shown = c.order.filter { !c.hidden.contains($0) }.map { names[$0] ?? $0 }
        let style = (VISOR_STYLES.first(where: { $0.0 == c.style })?.1 ?? "").lowercased()
        return (shown.isEmpty ? "ninguno" : shown.joined(separator: ", ")) + " · " + style + (c.square ? " de \(Int(c.side)) px" : "")
    }
}

/// Un logotipo con su tipografía; con tint, de ese color (PHP, siempre en el suyo: de un color, su óvalo
/// taparía las letras)
struct BrandImage: View {
    let key: String
    let height: CGFloat
    var tint: Color? = nil
    @Environment(\.colorScheme) var scheme

    var body: some View {
        let k = key == "node" ? (scheme == .dark ? "node-oscuro" : "node-claro") : key
        if let c = tint, key != "php", let img = brandImage(k, tint: brandTintColor(c)) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(height: height)
        } else if let img = brandImage(k) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(height: height)
        }
    }

    /// (el color del texto, resuelto con el tema: dentro del dibujo de la imagen no se sabe cuál es)
    func brandTintColor(_ c: Color) -> NSColor {
        if c == Color.primary { return scheme == .dark ? NSColor.white : NSColor.black }
        return NSColor(c)
    }
}

struct Sidebar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(NAV.filter { g in g.1.contains { NAV_FIXED.contains($0.0) || !model.look.ocultos.contains($0.0) } }, id: \.0) { group in
                Text(group.0)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 12)
                    .padding(.top, 14)
                    .padding(.bottom, 3)
                ForEach(group.1.filter { NAV_FIXED.contains($0.0) || !model.look.ocultos.contains($0.0) }, id: \.0) { item in
                    NavRow(key: item.0, text: item.1, icon: item.2)
                }
            }
            Spacer()
            Text(footer())
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(10)
        }
        .padding(.horizontal, 10)
        .frame(width: 220)
        .background(Color.primary.opacity(0.035))
    }

    /// Abajo, solo el aviso de la simulación: la versión va arriba, detrás de «Entornos PHP y
    /// Docker», y la firma en Acerca de
    func footer() -> String {
        return SIMULATE ? "SIMULACIÓN: no se cambia nada" : ""
    }
}

struct NavRow: View {
    @EnvironmentObject var model: AppModel
    let key: String
    let text: String
    let icon: String
    @State private var hover = false

    var body: some View {
        let on = model.tab == key
        return Button(action: { model.openTab(key) }) {
            HStack(spacing: 10) {
                let look = model.look
                if look.marcas && (key == "docker" || key == "node") {
                    // (su icono, como los demás, y al lado su logotipo de letras en lugar del nombre)
                    navIcon(on, color: look.color)
                    if brandImage(key == "docker" ? "docker-letras" : "node-claro") != nil {
                        BrandImage(key: key == "docker" ? "docker-letras" : key, height: key == "docker" ? 15 : 19,
                                   tint: look.color ? nil : (on ? ACCENT : Color.primary))
                    } else {
                        Text(text).font(.system(size: 13, weight: on ? .semibold : .regular))
                    }
                } else {
                    if look.marcas && look.color && key == "versiones" {
                        BrandImage(key: "php", height: 19)
                    } else {
                        navIcon(on, color: look.color)
                    }
                    Text(text).font(.system(size: 13, weight: on ? .semibold : .regular))
                }
                Spacer(minLength: 0)
            }
            .foregroundColor(on ? ACCENT : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? ACCENT.opacity(0.13) : Color.primary.opacity(hover ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover = $0 }
        .hoverPointer()
    }

    /// (los logotipos de un color, como los símbolos; desde la 1.39.4 también la ballena de Docker,
    /// como en Linux). Algo más grandes desde la 1.39, como en Linux (de 16 a 20)
    @ViewBuilder
    func navIcon(_ on: Bool, color: Bool) -> some View {
        // (en color, cada uno el suyo; GitHub, el del texto, que en el tema oscuro su negro no se vería)
        if icon.hasPrefix("logo:") {
            let name = String(icon.dropFirst(5))
            LogoShape(d: LOGO_PATHS[name] ?? "")
                .fill(color ? (name == "github" ? Color.primary : brand(name)) : (on ? ACCENT : Color.secondary))
                .frame(width: 21, height: 21)
        } else {
            Image(systemName: icon).font(.system(size: 17)).frame(width: 21, height: 21)
                .foregroundColor(color ? (NAV_TINTS[key] ?? ACCENT) : (on ? ACCENT : Color.secondary))
        }
    }
}

/// Fila de la columna de apartados de Configuración: como las de la barra lateral, más pequeña
struct SubNavRow: View {
    @EnvironmentObject var model: AppModel
    let key: String
    let text: String
    let icon: String
    @State private var hover = false

    var body: some View {
        let on = model.toolsSection == key
        return Button(action: { model.toolsSection = key }) {
            HStack(spacing: 10) {
                Group {
                    if icon.hasPrefix("logo:") {
                        LogoShape(d: LOGO_PATHS[String(icon.dropFirst(5))] ?? "").fill(on ? ACCENT : Color.secondary)
                    } else {
                        Image(systemName: icon).font(.system(size: 14)).foregroundColor(on ? ACCENT : Color.secondary)
                    }
                }
                .frame(width: 17, height: 17)
                Text(text).font(.system(size: 12.5, weight: on ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(on ? ACCENT : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? ACCENT.opacity(0.13) : Color.primary.opacity(hover ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover = $0 }
        .hoverPointer()
    }
}
