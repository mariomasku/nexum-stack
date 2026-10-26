using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.Catalogo;

/// <summary>
/// PHP2Shell (CVE-2026-109618 y CVE-2026-109619, oct 2026): las peticiones con muchas variables anidadas o
/// con el progreso de las subidas en la sesión pueden ejecutar código en PHP. Primer parche de cada rama
/// con soporte que lo arregla. En Linux, 7.4.33, 8.0.30 y 8.1.34 se compilan con el arreglo de php-src; en
/// Windows no se compila nada: los binarios oficiales de esas ramas no lo tienen y no se pueden arreglar.
/// </summary>
public static class Php2Shell
{
    public static readonly IReadOnlyDictionary<string, string> Fixed = new Dictionary<string, string>
    {
        ["8.2"] = "8.2.35",
        ["8.3"] = "8.3.36",
        ["8.4"] = "8.4.27",
        ["8.5"] = "8.5.12",
    };

    public enum Estado { Ok, Vulnerable }

    /// <summary>Estado de una versión de PHP de Windows y, si es vulnerable, por qué (el texto de la ventana).</summary>
    public static (Estado State, string Why) State(string php)
    {
        var branch = Versiones.Branch(php);
        if (Fixed.TryGetValue(branch, out var min))
            return Versiones.Compare(php, min) >= 0
                ? (Estado.Ok, "")
                : (Estado.Vulnerable, $"PHP {php}: el arreglo está en PHP {min}");
        // (una rama posterior a la 8.5 ya sale con el arreglo)
        if (Versiones.Compare(branch, "8.5") > 0)
            return (Estado.Ok, "");
        return (Estado.Vulnerable,
            $"PHP {php} de Windows: los binarios oficiales de la rama {branch} no tienen el arreglo y en Windows no se pueden arreglar (no se compila)");
    }

    /// <summary>Mitigaciones en el php.ini de todas las versiones (también las que ya tienen el arreglo).</summary>
    public const string SecureIni = """
session.upload_progress.enabled = Off
max_input_nesting_level = 6
post_max_size = 64M
upload_max_filesize = 64M
expose_php = Off
""";

    /// <summary>Solo desde PHP 8.5: sin la traza de las llamadas en los errores fatales.</summary>
    public const string SecureIni85 = "fatal_error_backtraces = 0";
}
