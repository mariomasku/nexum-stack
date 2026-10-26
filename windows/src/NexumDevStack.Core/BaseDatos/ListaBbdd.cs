using System.Globalization;
using System.Text.RegularExpressions;
using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.BaseDatos;

/// <summary>Una BBDD de una versión, con su fecha: i (la de su última importación con el programa) o c (la de su carpeta).</summary>
public sealed record Bbdd(string Name, long When, char Kind);

/// <summary>
/// Las BBDD de una versión, leídas de su carpeta de datos (sin necesidad de que MariaDB esté en marcha),
/// como db_dates de Linux, y las fechas de sus importaciones.
/// </summary>
public static class ListaBbdd
{
    static readonly string[] Skip = { "mysql", "performance_schema", "phpmyadmin", "test", "sys" };

    /// <summary>MariaDB guarda los caracteres especiales del nombre como @XXXX (wp_mi@002dweb es wp_mi-web).</summary>
    public static string Decode(string raw) =>
        Regex.Replace(raw, "@([0-9a-f]{4})", m => ((char)int.Parse(m.Groups[1].Value, NumberStyles.HexNumber)).ToString());

    public static List<Bbdd> FromDataDir(string dataDir, string importsFile)
    {
        var done = Imports(importsFile, dataDir);
        var rows = new List<Bbdd>();
        IEnumerable<string> dirs;
        try
        {
            dirs = Directory.EnumerateDirectories(dataDir).ToList();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return rows;
        }
        foreach (var path in dirs)
        {
            var raw = Path.GetFileName(path);
            if (Skip.Contains(raw, StringComparer.OrdinalIgnoreCase) || raw.StartsWith('#') || Ficheros.IsLink(path))
                continue;
            var name = Decode(raw);
            // Solo nombres que se pueden usar: uno con | o un salto de línea metería líneas falsas
            if (!Validacion.IsDbName(name))
                continue;
            if (done.TryGetValue(name, out var when))
                rows.Add(new Bbdd(name, when, 'i'));
            else
            {
                long t = 0;
                try { t = new DateTimeOffset(Directory.GetLastWriteTimeUtc(path), TimeSpan.Zero).ToUnixTimeSeconds(); }
                catch (IOException) { }
                rows.Add(new Bbdd(name, t, 'c'));
            }
        }
        rows.Sort((a, b) => string.Compare(a.Name, b.Name, StringComparison.OrdinalIgnoreCase));
        return rows;
    }

    static string Key(string dataDir) => Path.GetFullPath(dataDir).TrimEnd('\\', '/').ToLowerInvariant();

    /// <summary>Importaciones hechas con el programa: carpeta de datos|base|fecha (segundos).</summary>
    public static Dictionary<string, long> Imports(string importsFile, string dataDir)
    {
        var d = new Dictionary<string, long>();
        var text = Ficheros.ReadSmallText(importsFile);
        if (text == null) return d;
        var key = Key(dataDir);
        foreach (var line in text.Replace("\r\n", "\n").Split('\n'))
        {
            var p = line.Split('|');
            if (p.Length == 3 && p[0] == key && long.TryParse(p[2], out var t))
                d[p[1]] = t;
        }
        return d;
    }

    /// <summary>Apunta la fecha de la importación de una base (sin fecha: la olvida, al borrarla o crearla vacía).</summary>
    public static void NoteImport(string importsFile, string dataDir, string db, long? when)
    {
        var key = Key(dataDir);
        var text = Ficheros.ReadSmallText(importsFile) ?? "";
        var lines = text.Replace("\r\n", "\n").Split('\n')
            .Where(l => l.Length > 0 && !(l.Split('|') is [var a, var b, _] && a == key && b == db)).ToList();
        if (when != null)
            lines.Add($"{key}|{db}|{when}");
        Ficheros.WriteAtomic(importsFile, string.Join("\n", lines) + "\n");
    }
}
