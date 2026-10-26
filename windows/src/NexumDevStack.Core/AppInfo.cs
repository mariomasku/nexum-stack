using System.Reflection;

namespace NexumDevStack.Core;

/// <summary>Nombre, versión y firma del programa. La versión sale de Directory.Build.props (un solo sitio).</summary>
public static class AppInfo
{
    public const string Name = "Nexum Dev Stack";
    public const string Signature = "By M.Mascuñano - HEXER";
    public const string Subtitle = "Entornos LAMPP y Docker";

    /// <summary>Versión del programa (0.1.0): la de Directory.Build.props.</summary>
    public static string Version { get; } = ReadVersion();

    static string ReadVersion()
    {
        var attr = typeof(AppInfo).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
        if (string.IsNullOrEmpty(attr))
            return typeof(AppInfo).Assembly.GetName().Version?.ToString(3) ?? "0.0.0";
        // (sin el «+commit» que añade el SDK)
        var plus = attr.IndexOf('+');
        return plus > 0 ? attr[..plus] : attr;
    }

    /// <summary>Lo que hace el programa (Acerca de).</summary>
    public const string About =
        "Gestor de versiones de PHP con su Apache, MariaDB y phpMyAdmin para Windows 11, al estilo de XAMPP, " +
        "con varias versiones a la vez y una sola activa. Los mismos proyectos, BBDD y dominios que en Linux y macOS.";

    /// <summary>Lista de cambios de cada versión, en Markdown («## versión · fecha», viñetas «- »).</summary>
    public const string Changes = """
## 0.1.0 · 25 de octubre de 2026
- **Primera versión para Windows 11** (fase 1), en C# y WPF, con la misma ventana que en Linux y macOS: tema oscuro (o claro, en el menú ☰), los apartados a la izquierda y arriba el visor de la versión activa con sus avisos.
- **Versiones de PHP** de la 7.1 a la 8.5, con los binarios oficiales de Windows (no se compila nada): PHP de windows.php.net (Thread Safe, como módulo de Apache, como XAMPP), Apache de Apache Lounge, MariaDB y phpMyAdmin oficiales. Cada descarga se comprueba con su sha256 y, si quien la publica la firma, con su firma GPG (Apache Lounge, MariaDB y phpMyAdmin). PHP de Windows no publica firmas: solo su sha256 por HTTPS, y la ventana lo dice.
- Cada versión va en `C:\NexumDevStack\versiones\php-X.Y.Z`, de administrador (tu usuario no puede cambiar sus programas), con sus propias BBDD en `C:\NexumDevStack\datos\php-X.Y.Z`. Instalar, actualizar a otro parche (**Actualizar a PHP X.Y.Z**, al lado, copiando las BBDD) y desinstalar, desde la tabla de **Versiones de PHP**, con su soporte y su último parche según php.net.
- **PHP2Shell:** 8.2.35, 8.3.36, 8.4.27 y 8.5.12 o posteriores tienen el arreglo. Las 7.x, 8.0 y 8.1 de Windows no se pueden arreglar (no se compila): salen como «Vulnerable (PHP2Shell)» en rojo y piden confirmación al activarlas.
- **Proyectos** de `C:\NexumDevStack\htdocs`: WordPress y PrestaShop se reconocen solos. **Cargar** apunta `web.local` (http y https) a la carpeta, con su versión de PHP y su BBDD; si algo falla o se cancela, todo queda como estaba. Las tiendas PrestaShop, con su dominio real falseado en `hosts`, su vhost y su certificado. **Abrir web**, **VS Code**, **phpMyAdmin**, **Panel** (con el administrador de pruebas ya escrito) y **desmontar**.
- **Bases de datos** por versión con su tamaño: crear, borrar (con copia en `%USERPROFILE%\nexum-copias`), subir (`.sql`, `.sql.gz` o `.zip`, con la carga protegida de Linux), descargar y copiar a otra versión. El administrador de pruebas no sale en las copias.
- **Dominios y hosts**, **Configuración** (vhosts, hosts, barrera entre webs, registros) y la ventana de tareas con su barra, el tiempo que queda y la consola.
- Los servicios corren con tu usuario y solo en 127.0.0.1 y ::1. Solo se pide permiso de administrador (UAC) para preparar `C:\NexumDevStack`, instalar o desinstalar versiones y cambiar `hosts`.
- Docker, el correo de pruebas (Mailpit) y la actualización firmada del programa llegan en las próximas fases.
""";
}
