using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.Proyectos;

/// <summary>Datos de la BBDD en la configuración de una tienda (app/config/parameters.php o config/settings.inc.php).</summary>
public sealed record PsDatos(string Rel, string Name, string User, string Host, string Prefix, string Password);

/// <summary>Configuración de las tiendas PrestaShop (como ps_db_read, ps_parameters y ps_set_db de Linux).</summary>
public static class PrestaShop
{
    const string Quoted = @"(?:'((?:[^'\\]|\\.)*)'|""((?:[^""\\]|\\.)*)"")";

    static readonly (string Rel, string Pattern, string[] Keys)[] Rules =
    {
        ("app/config/parameters.php", @"['""]{0}['""]\s*=>\s*" + Quoted,
            new[] { "database_name", "database_user", "database_host", "database_prefix", "database_password" }),
        ("config/settings.inc.php", @"(?m)^[ \t]*define\(\s*['""]{0}['""]\s*,\s*" + Quoted,
            new[] { "_DB_NAME_", "_DB_USER_", "_DB_SERVER_", "_DB_PREFIX_", "_DB_PASSWD_" }),
    };

    /// <summary>Datos de la tienda en <paramref name="projectPath"/>; null si no tiene configuración con base.</summary>
    public static PsDatos? ReadConfig(string projectPath)
    {
        foreach (var (rel, pattern, keys) in Rules)
        {
            var text = Ficheros.ReadSmallText(Path.Combine(projectPath, rel.Replace('/', Path.DirectorySeparatorChar)));
            if (text == null)
                continue;
            var r = ReadText(text, rel);
            if (r != null)
                return r;
        }
        return null;
    }

    public static PsDatos? ReadText(string text, string rel)
    {
        var rule = Rules.First(r => r.Rel == rel);
        var values = new List<string>();
        for (int i = 0; i < rule.Keys.Length; i++)
        {
            var m = Regex.Match(text, rule.Pattern.Replace("{0}", Regex.Escape(rule.Keys[i])));
            var v = m.Success ? (m.Groups[1].Success ? m.Groups[1].Value : m.Groups[2].Value) : "";
            v = Regex.Replace(v, @"\\(.)", "$1");
            values.Add(i == 4 ? v.Replace("\n", " ") : Regex.Replace(v, @"[\x00-\x1f\x7f-\x9f]", "?"));
        }
        if (values[0].Length == 0)
            return null;
        // (sin prefijo en parameters.php: el de PrestaShop por defecto)
        var prefix = values[3];
        if (!Regex.IsMatch(text, rule.Pattern.Replace("{0}", Regex.Escape(rule.Keys[3]))))
            prefix = "ps_";
        return new PsDatos(rel, values[0], values[1], values[2], prefix, values[4]);
    }

    /// <summary>¿Tiene ya la base en parameters.php?</summary>
    public static bool HasDatabase(string parametersText) =>
        Regex.IsMatch(parametersText, @"['""]database_name['""]\s*=>\s*['""][^'""]");

    static string Php(object? v) => v switch
    {
        null => "NULL",
        bool b => b ? "true" : "false",
        string s => "'" + s.Replace("\\", "\\\\").Replace("'", "\\'") + "'",
        _ => throw new ArgumentException(),
    };

    static string Gen(int n)
    {
        const string alnum = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        var sb = new StringBuilder(n);
        for (int i = 0; i < n; i++)
            sb.Append(alnum[RandomNumberGenerator.GetInt32(alnum.Length)]);
        return sb.ToString();
    }

    /// <summary>
    /// app/config/parameters.php nuevo (tienda 1.7 o posterior recién clonada) con la base cargada en local y
    /// claves nuevas.
    /// </summary>
    public static string NewParameters(string db, string prefix)
    {
        // Clave de defuse/php-encryption (new_cookie_key): cabecera, 32 bytes y su sha256, en hexadecimal
        var head = new byte[] { 0xde, 0xf0, 0x00, 0x00 };
        var key = RandomNumberGenerator.GetBytes(32);
        var hk = head.Concat(key).ToArray();
        var defuse = Convert.ToHexString(hk.Concat(SHA256.HashData(hk)).ToArray()).ToLowerInvariant();
        var p = new (string, object?)[]
        {
            ("database_host", "127.0.0.1"), ("database_port", ""), ("database_name", db),
            ("database_user", "root"), ("database_password", ""), ("database_prefix", prefix),
            ("database_engine", "InnoDB"), ("mailer_transport", "smtp"), ("mailer_host", "127.0.0.1"),
            ("mailer_user", null), ("mailer_password", null), ("secret", Gen(64)),
            ("ps_caching", "CacheMemcache"), ("ps_cache_enable", false),
            ("ps_creation_date", DateTime.Now.ToString("yyyy-MM-dd")), ("locale", "es-ES"),
            ("use_debug_toolbar", true), ("cookie_key", Gen(64)), ("cookie_iv", Gen(32)),
            ("new_cookie_key", defuse),
        };
        return "<?php return array (\n  'parameters' => \n  array (\n" +
               string.Concat(p.Select(x => $"    '{x.Item1}' => {Php(x.Item2)},\n")) + "  ),\n);\n";
    }

    /// <summary>
    /// La configuración pasa a la base <paramref name="db"/> con el prefijo <paramref name="prefix"/> y, con
    /// <paramref name="localDb"/>, root y 127.0.0.1 (como ps_set_db de Linux). Conserva los finales de línea.
    /// </summary>
    public static string SetDb(string text, string rel, string db, string prefix, bool localDb, string password)
    {
        const string value = @"(?:'(?:[^'\\]|\\.)*'|""(?:[^""\\]|\\.)*""|NULL|null)";
        bool parameters = rel.EndsWith("parameters.php", StringComparison.Ordinal);
        string rx(string key) => parameters
            ? @"(['""]" + key + @"['""]\s*=>\s*)" + value
            : @"(?m)^([ \t]*define\(\s*['""]" + key + @"['""]\s*,\s*)" + value;
        var keys = parameters
            ? new Dictionary<string, string> { ["name"] = "database_name", ["prefix"] = "database_prefix", ["user"] = "database_user",
                ["password"] = "database_password", ["host"] = "database_host", ["port"] = "database_port" }
            : new Dictionary<string, string> { ["name"] = "_DB_NAME_", ["prefix"] = "_DB_PREFIX_", ["user"] = "_DB_USER_",
                ["password"] = "_DB_PASSWD_", ["host"] = "_DB_SERVER_" };
        string Put(string t, string k, string v) => new Regex(rx(keys[k])).Replace(t, m => m.Groups[1].Value + Php(v), 1);
        text = Put(text, "name", db);
        text = Put(text, "prefix", prefix);
        if (localDb)
        {
            text = Put(text, "user", "root");
            text = Put(text, "password", password);
            text = Put(text, "host", "127.0.0.1");
            if (keys.ContainsKey("port"))
                text = Put(text, "port", "");
        }
        return text;
    }

    /// <summary>_COOKIE_KEY_ de config/settings.inc.php (PrestaShop 1.6), para la contraseña del administrador de pruebas.</summary>
    public static string? CookieKey(string projectPath)
    {
        var text = Ficheros.ReadSmallText(Path.Combine(projectPath, "config", "settings.inc.php"), 1_000_000);
        if (text == null) return null;
        var m = Regex.Match(text, @"define\(\s*['""]_COOKIE_KEY_['""]\s*,\s*['""]([A-Za-z0-9]+)['""]");
        return m.Success ? m.Groups[1].Value : null;
    }

    /// <summary>
    /// Carpeta de administración de una tienda (cada una la llama de una forma; se reconoce por lo que tiene:
    /// index.php y ajax-tab.php o get-file-admin.php).
    /// </summary>
    public static string? AdminFolder(string projectPath)
    {
        try
        {
            var names = Directory.EnumerateDirectories(projectPath).Select(Path.GetFileName).Where(n => n != null).Select(n => n!)
                .OrderBy(n => !n.StartsWith("admin", StringComparison.OrdinalIgnoreCase)).ThenBy(n => n, StringComparer.Ordinal);
            foreach (var n in names)
            {
                var d = Path.Combine(projectPath, n);
                if (Regex.IsMatch(n, "^[A-Za-z0-9_-]+$") && !Ficheros.IsLink(d) && File.Exists(Path.Combine(d, "index.php")) &&
                    (File.Exists(Path.Combine(d, "ajax-tab.php")) || File.Exists(Path.Combine(d, "get-file-admin.php"))))
                    return n;
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
        }
        return null;
    }
}
