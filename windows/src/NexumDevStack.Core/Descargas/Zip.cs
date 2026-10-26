using System.IO.Compression;
using NexumDevStack.Core.Tareas;

namespace NexumDevStack.Core.Descargas;

/// <summary>Descomprimir sin salirse de la carpeta de destino (nada de «..», rutas absolutas ni unidades).</summary>
public static class Zip
{
    /// <summary>
    /// Saca de <paramref name="zipPath"/> lo que hay dentro de <paramref name="prefix"/> (por ejemplo
    /// «Apache24/»; vacío: todo) en <paramref name="dest"/>, sin el prefijo. Devuelve cuántos ficheros.
    /// </summary>
    public static int Extract(string zipPath, string dest, string prefix, ISalida? o = null, long maxBytes = 4L << 30)
    {
        var root = Path.GetFullPath(dest);
        Directory.CreateDirectory(root);
        var rootSep = root.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        int count = 0;
        long total = 0;
        using var zip = ZipFile.OpenRead(zipPath);
        foreach (var e in zip.Entries)
        {
            o?.Cancel.ThrowIfCancellationRequested();
            var name = e.FullName.Replace('\\', '/');
            if (prefix.Length > 0)
            {
                if (!name.StartsWith(prefix, StringComparison.Ordinal))
                    continue;
                name = name[prefix.Length..];
            }
            if (name.Length == 0)
                continue;
            if (!IsSafeEntry(name))
                throw new NexumException($"El zip {Path.GetFileName(zipPath)} trae una ruta no válida: {e.FullName}");
            var target = Path.GetFullPath(Path.Combine(root, name.Replace('/', Path.DirectorySeparatorChar)));
            if (!target.StartsWith(rootSep, StringComparison.OrdinalIgnoreCase))
                throw new NexumException($"El zip {Path.GetFileName(zipPath)} intenta escribir fuera de su carpeta: {e.FullName}");
            if (name.EndsWith('/'))
            {
                Directory.CreateDirectory(target);
                continue;
            }
            total += e.Length;
            if (total > maxBytes)
                throw new NexumException($"El zip {Path.GetFileName(zipPath)} ocupa demasiado al descomprimirlo");
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            e.ExtractToFile(target, true);
            count++;
        }
        return count;
    }

    /// <summary>¿Ruta relativa normal? Sin «..», sin unidad (C:), sin \\servidor, sin caracteres de control.</summary>
    public static bool IsSafeEntry(string name)
    {
        if (name.StartsWith('/') || name.Contains(':') || name.Contains('\0'))
            return false;
        foreach (var part in name.TrimEnd('/').Split('/'))
        {
            if (part is "" or "." or "..")
                return false;
            if (part.Any(c => c < 0x20))
                return false;
        }
        return true;
    }

    /// <summary>Primera carpeta de un zip (la que lo contiene todo, como «mariadb-11.8.9-winx64/»).</summary>
    public static string? TopFolder(string zipPath, string startsWith)
    {
        using var zip = ZipFile.OpenRead(zipPath);
        foreach (var e in zip.Entries)
        {
            var name = e.FullName.Replace('\\', '/');
            var slash = name.IndexOf('/');
            if (slash > 0 && name.StartsWith(startsWith, StringComparison.OrdinalIgnoreCase))
                return name[..(slash + 1)];
        }
        return null;
    }
}
