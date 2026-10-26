using System.Text;

namespace NexumDevStack.Core.Util;

/// <summary>Lectura y escritura con cuidado: sin seguir enlaces, con tamaño máximo y escritura atómica.</summary>
public static class Ficheros
{
    public const long MaxConfig = 2_000_000;

    /// <summary>¿Es un enlace (simbólico o unión de carpetas)?</summary>
    public static bool IsLink(string path)
    {
        try
        {
            var info = new FileInfo(path);
            if (!info.Exists && !Directory.Exists(path))
                return false;
            var attrs = File.GetAttributes(path);
            return (attrs & FileAttributes.ReparsePoint) != 0;
        }
        catch (Exception)
        {
            return false;
        }
    }

    /// <summary>Texto de un fichero normal (no un enlace) de hasta <paramref name="max"/> bytes; null si no.</summary>
    public static string? ReadSmallText(string path, long max = MaxConfig)
    {
        try
        {
            var info = new FileInfo(path);
            if (!info.Exists || IsLink(path) || info.Length > max)
                return null;
            using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            var buf = new byte[Math.Min(max, info.Length)];
            int read = 0, n;
            while (read < buf.Length && (n = fs.Read(buf, read, buf.Length - read)) > 0)
                read += n;
            return DecodeText(buf.AsSpan(0, read));
        }
        catch (Exception)
        {
            return null;
        }
    }

    /// <summary>UTF-8 (con o sin BOM); si no lo es, Windows-1252 como Latin-1 (los hosts antiguos).</summary>
    public static string DecodeText(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
            bytes = bytes[3..];
        try
        {
            return new UTF8Encoding(false, true).GetString(bytes);
        }
        catch (DecoderFallbackException)
        {
            return Encoding.Latin1.GetString(bytes);
        }
    }

    /// <summary>
    /// Escribe un fichero de una vez: primero en uno temporal de la misma carpeta y después lo cambia por el
    /// de destino (si se corta a medias, el de antes sigue entero). Sin BOM.
    /// </summary>
    public static void WriteAtomic(string path, string text, bool keepBackup = false)
    {
        var dir = Path.GetDirectoryName(Path.GetFullPath(path))!;
        Directory.CreateDirectory(dir);
        var tmp = Path.Combine(dir, "." + Path.GetFileName(path) + "." + Guid.NewGuid().ToString("N")[..8] + ".nuevo");
        File.WriteAllText(tmp, text, new UTF8Encoding(false));
        try
        {
            if (File.Exists(path))
            {
                if (keepBackup)
                    File.Copy(path, path + ".anterior", true);
                File.Replace(tmp, path, null, true);
            }
            else
            {
                File.Move(tmp, path);
            }
        }
        catch (PlatformNotSupportedException)
        {
            File.Move(tmp, path, true);
        }
        catch (IOException) when (File.Exists(tmp))
        {
            File.Move(tmp, path, true);
        }
        finally
        {
            if (File.Exists(tmp))
                File.Delete(tmp);
        }
    }

    /// <summary>
    /// ¿Se puede escribir este fichero sin salirse de la carpeta del proyecto? Ni el fichero ni las carpetas
    /// de su ruta pueden ser enlaces (un repositorio podría traer wp-config.php como enlace a otro fichero).
    /// </summary>
    public static bool InsideWithoutLinks(string root, string path)
    {
        var fullRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var full = Path.GetFullPath(path);
        if (!full.StartsWith(fullRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            return false;
        if (IsLink(fullRoot))
            return false;
        var rel = full[(fullRoot.Length + 1)..];
        var cur = fullRoot;
        foreach (var part in rel.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar))
        {
            if (part is "" or "." or "..")
                return false;
            cur = Path.Combine(cur, part);
            if (IsLink(cur))
                return false;
        }
        return true;
    }

    /// <summary>Carpeta personal con las copias (%USERPROFILE%\nexum-copias), creada si falta.</summary>
    public static string EnsureDir(string dir)
    {
        Directory.CreateDirectory(dir);
        return dir;
    }

    /// <summary>Marca de tiempo para los nombres de las copias: 20261025-213000</summary>
    public static string Stamp() => DateTime.Now.ToString("yyyyMMdd-HHmmss");
}
