using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace NexumDevStack.Core.Proyectos;

/// <summary>Datos de la BBDD de un wp-config.php.</summary>
public sealed record WpDatos(string Name, string User, string Host, string Prefix, string Password);

/// <summary>
/// wp-config.php: leer sus datos y rehacerlo con la base cargada en local (como wp_config de Linux). De la
/// plantilla solo cambian la base, el prefijo, WP_SITEURL/WP_HOME y, si sus datos no entran en el MariaDB
/// local, el usuario, la contraseña y el servidor.
/// </summary>
public static class WordPress
{
    static string Const(string text, string name)
    {
        // Solo las que no están comentadas (// define( 'DB_USER', 'development' );)
        var m = Regex.Match(text, @"(?m)^[ \t]*define\(\s*['""]" + name + @"['""]\s*,\s*(?:'((?:[^'\\]|\\.)*)'|""((?:[^""\\]|\\.)*)"")");
        if (!m.Success)
            return "";
        var v = m.Groups[1].Success ? m.Groups[1].Value : m.Groups[2].Value;
        return Regex.Replace(v, @"\\(.)", "$1");
    }

    public static WpDatos Read(string text)
    {
        var m = Regex.Match(text, @"(?m)^[ \t]*\$table_prefix\s*=\s*['""]([^'""]*)['""]");
        string Clean(string s) => Regex.Replace(s, @"[\x00-\x1f\x7f-\x9f]", "?");
        return new WpDatos(Clean(Const(text, "DB_NAME")), Clean(Const(text, "DB_USER")), Clean(Const(text, "DB_HOST")),
            Clean(m.Success ? m.Groups[1].Value : ""), Const(text, "DB_PASSWORD").Replace("\n", " "));
    }

    public static string Php(string v) => "'" + v.Replace("\\", "\\\\").Replace("'", "\\'") + "'";

    static string Put(string text, string name, string value)
    {
        var rx = new Regex(@"(?m)^([ \t]*define\(\s*['""]" + name + @"['""]\s*,\s*)(?:'(?:[^'\\]|\\.)*'|""(?:[^""\\]|\\.)*"")");
        return rx.Replace(text, m => m.Groups[1].Value + Php(value), 1);
    }

    /// <summary>
    /// wp-config.php con la base <paramref name="db"/> y el prefijo <paramref name="prefix"/>, la web en
    /// <paramref name="url"/> y, con <paramref name="localDb"/>, root y 127.0.0.1. Claves nuevas si es la
    /// plantilla de wp-config-sample.php. Conserva los finales de línea.
    /// </summary>
    public static string Rewrite(string text, string db, string prefix, bool localDb, string password, string url)
    {
        text = Put(text, "DB_NAME", db);
        if (localDb)
        {
            text = Put(text, "DB_USER", "root");
            text = Put(text, "DB_PASSWORD", password);
            text = Put(text, "DB_HOST", "127.0.0.1");
        }
        text = new Regex(@"(?m)^([ \t]*\$table_prefix\s*=\s*)(['""])[^'""]*\2").Replace(text, m => m.Groups[1].Value + Php(prefix), 1);
        // La web en este equipo (si no, WordPress redirige al dominio de producción guardado en la base)
        var nl = text.Contains("\r\n") ? "\r\n" : "\n";
        var missing = new List<string>();
        foreach (var name in new[] { "WP_SITEURL", "WP_HOME" })
        {
            var rx = new Regex(@"(?m)^([ \t]*define\(\s*['""]" + name + @"['""]\s*,\s*)(?:'(?:[^'\\]|\\.)*'|""(?:[^""\\]|\\.)*"")");
            if (rx.IsMatch(text))
                text = rx.Replace(text, m => m.Groups[1].Value + Php(url), 1);
            else
                missing.Add(name);
        }
        if (missing.Count > 0)
        {
            var lines = string.Concat(missing.Select(n => $"define('{n}', {Php(url)});{nl}")) + nl;
            // Delante de los datos de la base, como en la plantilla del equipo; si no, detrás de <?php
            var m = Regex.Match(text, @"(?m)^[ \t]*(?://[^\r\n]*Database settings|define\(\s*['""]DB_NAME['""])");
            if (m.Success)
                text = text[..m.Index] + lines + text[m.Index..];
            else
            {
                var p = Regex.Match(text, @"<\?php[^\n]*\n");
                var at = p.Success ? p.Index + p.Length : 0;
                text = text[..at] + nl + lines + text[at..];
            }
        }
        // Sin editor de plugins y temas en el escritorio de WordPress: todos los proyectos van en el mismo
        // origen (localhost), y un fallo XSS en uno podría usar ese editor en otro para ejecutar PHP
        if (!Regex.IsMatch(text, @"(?m)^[ \t]*define\(\s*['""]DISALLOW_FILE_EDIT['""]"))
        {
            var line = "define('DISALLOW_FILE_EDIT', true); // Nexum Dev Stack: sin editor de plugins en local" + nl;
            var m = Regex.Match(text, @"(?m)^[ \t]*(?:/\*[^\n]*stop editing|\$table_prefix\b)");
            if (m.Success)
                text = text[..m.Index] + line + nl + text[m.Index..];
            else
            {
                var p = Regex.Match(text, @"<\?php[^\n]*\n");
                var at = p.Success ? p.Index + p.Length : 0;
                text = text[..at] + line + text[at..];
            }
        }
        // wp-config-sample.php: claves nuevas
        const string chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&()*+,-./:;<=>?@[]^_{|}~";
        foreach (var key in new[] { "AUTH_KEY", "SECURE_AUTH_KEY", "LOGGED_IN_KEY", "NONCE_KEY",
                     "AUTH_SALT", "SECURE_AUTH_SALT", "LOGGED_IN_SALT", "NONCE_SALT" })
        {
            var rx = new Regex(@"(?m)^([ \t]*define\(\s*['""]" + key + @"['""]\s*,\s*)['""]put your unique phrase here['""]");
            text = rx.Replace(text, m =>
            {
                var sb = new StringBuilder(64);
                for (int i = 0; i < 64; i++)
                    sb.Append(chars[RandomNumberGenerator.GetInt32(chars.Length)]);
                return m.Groups[1].Value + Php(sb.ToString());
            }, 1);
        }
        return text;
    }

    /// <summary>¿Es un servidor de este equipo? (nunca se prueba a entrar en uno de producción)</summary>
    public static bool IsLocalHost(string host) => Regex.IsMatch(host ?? "", @"^(localhost|127\.0\.0\.1)(:.*)?$");
}
