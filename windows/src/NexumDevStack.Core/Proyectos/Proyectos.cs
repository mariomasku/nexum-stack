using System.Text.RegularExpressions;
using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.Proyectos;

/// <summary>Un proyecto de htdocs: su carpeta, la BBDD de su configuración, su .php-version y su tipo (wp, ps o "").</summary>
public sealed record Proyecto(string Name, string Db, string PhpVersion, string Kind);

/// <summary>Las carpetas de htdocs (sin ocultas ni enlaces) y lo que se sabe de cada una, como gui_projects de Linux.</summary>
public static class Escaner
{
    /// <summary>Dónde está el nombre de la BBDD en la configuración de cada tipo de proyecto.</summary>
    static readonly (string Rel, Regex Rx)[] DbRules =
    {
        ("wp-config.php", new Regex(@"^[ \t]*define\(\s*['""]DB_NAME['""]\s*,\s*['""]([^'""]+)", RegexOptions.Multiline)),
        ("app/config/parameters.php", new Regex(@"['""]database_name['""]\s*=>\s*['""]([^'""]+)")),
        ("config/settings.inc.php", new Regex(@"define\(\s*['""]_DB_NAME_['""]\s*,\s*['""]([^'""]+)")),
        (".env", new Regex(@"^\s*DB_DATABASE\s*=\s*[""']?([^""'\s#]+)", RegexOptions.Multiline)),
    };

    public static List<string> Folders(string htdocs)
    {
        try
        {
            return Directory.EnumerateDirectories(htdocs)
                .Select(Path.GetFileName)
                .Where(n => n != null && !n.StartsWith('.') && !Regex.IsMatch(n, @"[|\x00-\x1f]") &&
                            !Ficheros.IsLink(Path.Combine(htdocs, n)))
                .Select(n => n!)
                .OrderBy(n => n, StringComparer.OrdinalIgnoreCase)
                .ToList();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return new List<string>();
        }
    }

    /// <summary>BBDD de la configuración de un proyecto (vacío si no tiene o no es un nombre válido).</summary>
    public static string ProjectDb(string htdocs, string folder)
    {
        foreach (var (rel, rx) in DbRules)
        {
            var text = Ficheros.ReadSmallText(Path.Combine(htdocs, folder, rel.Replace('/', Path.DirectorySeparatorChar)));
            if (text == null)
                continue;
            var m = rx.Match(text);
            if (m.Success)
                return Validacion.IsDbName(m.Groups[1].Value) ? m.Groups[1].Value : "";
        }
        return "";
    }

    /// <summary>ps (tienda PrestaShop), wp (WordPress) o "".</summary>
    public static string Kind(string htdocs, string folder)
    {
        var path = Path.Combine(htdocs, folder);
        if (IsPrestaShop(htdocs, folder))
            return "ps";
        if (File.Exists(Path.Combine(path, "wp-config.php")) || Directory.Exists(Path.Combine(path, "wp-includes")))
            return "wp";
        return "";
    }

    /// <summary>¿Es una tienda PrestaShop? Por su configuración, sus carpetas o «prestashop» en el nombre.</summary>
    public static bool IsPrestaShop(string htdocs, string folder)
    {
        var path = Path.Combine(htdocs, folder);
        return folder.Contains("prestashop", StringComparison.OrdinalIgnoreCase) ||
               Directory.Exists(Path.Combine(path, "src", "PrestaShopBundle")) ||
               File.Exists(Path.Combine(path, "classes", "PrestaShopAutoload.php")) ||
               PrestaShop.ReadConfig(path) != null;
    }

    public static bool IsWordPress(string htdocs, string folder)
    {
        var path = Path.Combine(htdocs, folder);
        return File.Exists(Path.Combine(path, "wp-config.php")) || Directory.Exists(Path.Combine(path, "wp-includes"));
    }

    public static List<Proyecto> Scan(string htdocs)
    {
        var list = new List<Proyecto>();
        foreach (var name in Folders(htdocs))
        {
            var ver = "";
            var pv = Ficheros.ReadSmallText(Path.Combine(htdocs, name, ".php-version"), 4096);
            if (pv != null)
                ver = Regex.Replace(pv.Trim(), "[^0-9.]", "");
            if (ver.Length > 16) ver = ver[..16];
            list.Add(new Proyecto(name, ProjectDb(htdocs, name), ver, Kind(htdocs, name)));
        }
        return list;
    }

    /// <summary>
    /// ¿Se parece el dominio a la carpeta? Su nombre registrable (mitienda en www.mitienda.com, cliente en
    /// cliente.com.es), de 4 letras o más, va en el nombre de la carpeta sin sus palabras genéricas (dob,
    /// prestashop, wordpress…): así prestashop.com no vale para dob-prestashop-x.
    /// </summary>
    public static bool DomainFitsFolder(string domain, string folder)
    {
        var d = domain.ToLowerInvariant();
        if (d.StartsWith("www.", StringComparison.Ordinal)) d = d[4..];
        var f = folder.ToLowerInvariant();
        foreach (var w in new[] { "dob", "prestashop", "wordpress", "tienda", "shop", "html", "php", "web", "wp", "ps" })
            f = f.Replace(w, "");
        f = f.Replace(".", "").Replace("_", "").Replace("-", "");
        var parts = d.Split('.');
        if (parts.Length < 2)
            return false;
        var label = parts[^2];
        if (parts.Length >= 3 && Regex.IsMatch(label, "^(com|co|org|net|gob|edu|ac|nom)$"))
            label = parts[^3];
        label = label.Replace("_", "").Replace("-", "");
        return label.Length >= 4 && f.Contains(label, StringComparison.Ordinal);
    }

    /// <summary>
    /// Carpeta que se llama como la base: wp_tienda → dob-wordpress-tienda (la base sin wp_ ni ps_, al final
    /// del nombre). Si hay varias, la del mismo tipo.
    /// </summary>
    public static string? NameMatch(string htdocs, string db, IReadOnlyList<string> folders)
    {
        var low = db.ToLowerInvariant();
        var tails = new HashSet<string> { low };
        if (low.Length > 3 && (low.StartsWith("wp_") || low.StartsWith("ps_")))
            tails.Add(low[3..]);
        var hits = folders.Where(f =>
        {
            var fl = f.ToLowerInvariant();
            return tails.Any(v => fl == v || fl.EndsWith("-" + v) || fl.EndsWith("." + v) || fl.EndsWith("_" + v));
        }).ToList();
        if (hits.Count > 1 && (low.StartsWith("wp_") || low.StartsWith("ps_")))
        {
            var same = hits.Where(f => Kind(htdocs, f) == low[..2]).ToList();
            if (same.Count > 0) hits = same;
        }
        return hits.Count == 1 ? hits[0] : null;
    }
}
