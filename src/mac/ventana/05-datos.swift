// MARK: - Datos

struct Install: Identifiable, Equatable {
    let folder, php, apache, mariadb, ftp, perl, pma, blocker: String
    var id: String { return folder }
}

struct DbDate: Equatable {
    let when: Int
    /// true: importada con nexum (fecha exacta); false: último cambio de sus tablas
    let imported: Bool
}

/// Tipo c de la fecha de una base: no se ha importado con nexum
let DB_DATE_HELP = "Fecha en la que cambiaron por última vez las tablas de la BBDD (al importarla desde phpMyAdmin, por ejemplo). Las que se suben desde esta versión guardan la fecha exacta de la importación."

/// Antigüedad aproximada: hace 5 min, hace 3 horas, hace 12 días, hace 4 meses, hace 2 años
func fmtAge(_ secs: Int) -> String {
    if secs < 3600 { return "hace \(plural(max(1, secs / 60), "min", "min"))" }
    if secs < 86400 { return "hace \(plural(secs / 3600, "hora", "horas"))" }
    if secs < 60 * 86400 { return "hace \(plural(secs / 86400, "día", "días"))" }
    if secs < 365 * 86400 { return "hace \(plural(secs / (30 * 86400), "mes", "meses"))" }
    return "hace \(plural(secs / (365 * 86400), "año", "años"))"
}

/// Fecha de una base para su fila: la de su importación o la del último cambio de sus tablas
func dbDateText(_ date: DbDate?) -> String? {
    guard let d = date, d.when > 0 else { return nil }
    let f = DateFormatter()
    f.locale = Locale(identifier: "es_ES")
    f.dateFormat = "dd/MM/yyyy 'a las' HH:mm"
    let stamp = f.string(from: Date(timeIntervalSince1970: TimeInterval(d.when)))
    let age = fmtAge(max(0, Int(Date().timeIntervalSince1970) - d.when))
    return (d.imported ? "Importada el " : "Tablas cambiadas el ") + stamp + "  ·  " + age
}

/// Un proyecto https cuyo certificado es de confianza para todo el Mac (motivo: ca o firmado)
struct CertIssue: Equatable {
    let domain: String
    let why: String
}

struct AppData: Equatable {
    var name = "Nexum Dev Stack", version = "", signature = "", active = ""
    var running = false, official = false
    var vhosts = "/Library/Nexum/XAMPP-compartido/httpd-vhosts.conf", hosts = "/etc/hosts"
    /// Copias de las bases del XAMPP oficial (carpeta -> número de .zip) y XAMPP oficiales apartados
    var copies: [String: Int] = [:]
    var asides: [String] = []
    var installs: [Install] = []
    var dbs: [String: [String]] = [:]
    /// Fecha de cada base («versión|base»): la de su importación o la del último cambio de sus tablas
    var dbDates: [String: DbDate] = [:]
    /// Procesos de XAMPP en memoria que no son de la versión montada (resumen)
    var stray = ""
    /// Servicios de la versión montada a los que se puede entrar desde otros equipos de la red
    var exposed = ""
    /// Versiones a las que les falta algo para ser solo de este Mac (asegurar --todas)
    var unsecured: [String] = []
    /// Versión montada con las tablas del sistema de MariaDB antiguas y el tamaño de su registro de
    /// errores (reparar-bd-sistema)
    var dbsysVersion = ""
    var dbsysLog: Int64 = 0
    /// Certificados de proyectos en los que confía todo el Mac (dominio, motivo) y las CAs locales
    /// sin límite de dominios que los firman (nexum arreglar-certificados)
    var certs: [CertIssue] = []
    var cas: [String] = []
    /// Proyectos https cuyo certificado propio aún no acepta el navegador (G|dominio)
    var untrusted: [String] = []
    /// Tiendas con dominio real cuyo certificado acepta el navegador y ya no están falseadas (Q|dominio)
    var stale: [String] = []
    /// Estado de cada versión frente a PHP2Shell (X|carpeta|estado): ok, parche, parcheable,
    /// actualizable o sin-arreglo
    var php2shell: [String: String] = [:]
    /// Barrera entre webs puesta (T|1) o apagada (T|0)
    var barrier = true
    /// Correo de pruebas (E|…): nil si el script no lo trae
    var mail: MailState? = nil
}

/// Correo de pruebas (Mailpit): instalado, encendido, modo de los plugins de correo de WordPress
/// (mailpit, desactivar o nada), en marcha, versión instalada, dirección de su web y versión que
/// instala el gestor
struct MailState: Equatable {
    var installed = false
    var on = true
    var wp = "mailpit"
    var running = false
    var version = ""
    var url = "http://127.0.0.1:8025/"
    var offer = ""
}

/// Fecha del parche de seguridad oficial contra PHP2Shell de PHP 7.4.33, 8.0.30 y 8.1.34
let PHP2SHELL_DATE = "oct 2026"

/// ¿Es vulnerable a PHP2Shell (CVE-2026-109618 y CVE-2026-109619) una versión con ese estado?
func php2shellVulnerable(_ state: String) -> Bool {
    return state == "parcheable" || state == "actualizable" || state == "sin-arreglo"
}

/// Explicación del aviso de PHP2Shell de una versión (para el mensaje al pasar el ratón y los diálogos)
func php2shellText(_ state: String, _ php: String) -> String {
    switch state {
    case "parcheable":
        return "PHP \(php) es vulnerable a PHP2Shell (CVE-2026-109618 y CVE-2026-109619): un formulario de un proyecto puede acabar ejecutando código en tu Mac. Su rama ya no tiene versiones nuevas, pero sí el parche oficial de seguridad: actualízala (menú ⋯) y se le pone, con sus BBDD."
    case "actualizable":
        return "PHP \(php) es vulnerable a PHP2Shell (CVE-2026-109618 y CVE-2026-109619): un formulario de un proyecto puede acabar ejecutando código en tu Mac. Lo corrige el último parche de su rama: actualízala (menú ⋯)."
    case "sin-arreglo":
        return "PHP \(php) es vulnerable a PHP2Shell (CVE-2026-109618 y CVE-2026-109619) y su rama no tiene arreglo: úsala solo con proyectos de confianza."
    default:
        return ""
    }
}

/// Apache, MariaDB o el FTP de la versión montada (pestaña Servicios)
struct Service: Equatable, Identifiable {
    let name: String
    let running: Bool
    let ports: String
    let open: Bool
    let auto: Bool
    let user: String
    var id: String { return name }
}

/// Un parche de una rama (gui-parches), para «Otro parche concreto» de Instalar
struct PatchItem: Identifiable, Equatable {
    let version, date, state: String
    let security, latest: Bool
    var id: String { return version }
}

struct Branch: Identifiable, Equatable {
    let branch, latest: String
    let supported: Bool
    let mariadb, perl, state: String
    // Estado en php.net: stable, security o eol, y las fechas de fin del soporte activo y de seguridad
    let phpState, activeEnd, securityEnd: String
    // Fecha del último parche (AAAA-MM-DD) y si php.net lo marca como parche de seguridad
    let date: String
    let security: Bool
    var id: String { return branch }
}
