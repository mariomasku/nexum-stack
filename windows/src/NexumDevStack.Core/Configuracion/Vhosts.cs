using System.Text;
using System.Text.RegularExpressions;
using NexumDevStack.Core.Pila;

namespace NexumDevStack.Core.Configuracion;

/// <summary>Un vhost sin comentar de httpd-vhosts.conf.</summary>
public sealed record VhostInfo(int Port, string Folder, string Name, IReadOnlyList<string> Aliases, string Crt, string Key,
    string DocumentRoot, int StartLine, int EndLine)
{
    public bool Https => Crt.Length > 0;
    public IEnumerable<string> AllNames => new[] { Name }.Concat(Aliases);
}

/// <summary>
/// httpd-vhosts.conf compartido por todas las versiones (config\httpd-vhosts.conf): leer sus vhosts (como
/// vhosts_info de Linux), el de los proyectos (web.local) y añadir los de las tiendas y proyectos nuevos.
/// </summary>
public static class Vhosts
{
    static readonly Regex OpenRx = new(@"^<VirtualHost\s+[^>]*:(\d+)\s*>", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    static readonly Regex CloseRx = new(@"^</VirtualHost>", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    static readonly Regex FolderRx = new(@"[/\\]htdocs[/\\]([^/\\\s""]+)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    public static List<VhostInfo> Parse(string? text)
    {
        var result = new List<VhostInfo>();
        if (string.IsNullOrEmpty(text))
            return result;
        var lines = text.Replace("\r\n", "\n").Split('\n');
        int? start = null;
        int port = 0;
        string folder = "", name = "", crt = "", key = "", root = "";
        var aliases = new List<string>();
        for (int i = 0; i < lines.Length; i++)
        {
            var raw = lines[i];
            var line = raw.TrimStart().StartsWith('#') ? "" : raw.Trim();
            if (line.Length == 0)
                continue;
            var m = OpenRx.Match(line);
            if (m.Success)
            {
                start = i;
                port = int.TryParse(m.Groups[1].Value, out var pp) ? pp : 0;
                folder = name = crt = key = root = "";
                aliases = new List<string>();
                continue;
            }
            if (start == null)
                continue;
            if (CloseRx.IsMatch(line))
            {
                if (name.Length > 0)
                    result.Add(new VhostInfo(port, folder, name.ToLowerInvariant(),
                        aliases.Select(a => a.ToLowerInvariant()).ToList(), crt, key, root, start.Value, i));
                start = null;
                continue;
            }
            var parts = Regex.Split(line, @"\s+", RegexOptions.CultureInvariant);
            var k = parts[0].ToLowerInvariant();
            var value = line.Length > parts[0].Length ? line[parts[0].Length..].Trim().Trim('"') : "";
            switch (k)
            {
                case "documentroot":
                    root = value;
                    var fm = FolderRx.Match(value);
                    folder = fm.Success ? fm.Groups[1].Value : "";
                    break;
                case "servername":
                    name = value.Split(':')[0];
                    break;
                case "serveralias":
                    aliases.AddRange(value.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
                    break;
                case "sslcertificatefile":
                    crt = value;
                    break;
                case "sslcertificatekeyfile":
                    key = value;
                    break;
            }
        }
        return result;
    }

    /// <summary>Carpeta a la que apunta ahora el vhost de los proyectos (web.local): null si no hay vhost, "" si ninguna.</summary>
    public static string? ProjectFolder(IEnumerable<VhostInfo> vhosts)
    {
        var v = vhosts.FirstOrDefault(x => x.Name == Disposicion.ProjectVhost);
        if (v == null)
            return null;
        return v.Folder == Disposicion.EmptyProject ? "" : v.Folder;
    }

    public static bool HasProjectVhost(IEnumerable<VhostInfo> vhosts) => vhosts.Any(x => x.Name == Disposicion.ProjectVhost);

    /// <summary>
    /// Los vhosts de web.local (http y https), que apuntan al proyecto cargado. Sin caché en el navegador: al
    /// cambiar de proyecto no sale el anterior.
    /// </summary>
    public static string ProjectVhostBlock(Disposicion l, Puertos p, string admin)
    {
        var name = Disposicion.ProjectVhost;
        var root = Apache.Fwd(l.EmptyProjectDir);
        var crt = Apache.Fwd(Path.Combine(l.SslDir, name + ".crt"));
        var key = Apache.Fwd(Path.Combine(l.SslDir, name + ".key"));
        return $"""

# {name}: apunta al proyecto cargado (Cargar proyecto cambia su DocumentRoot), creado por Nexum Dev Stack
<VirtualHost *:{p.Http}>
    ServerAdmin {admin}
    DocumentRoot "{root}"
    ServerName {name}
    ServerAlias www.{name}
    ErrorLog "${"{"}NEXUM_REGISTROS{"}"}/{name}-error.log"
    # Sin caché en el navegador: al cambiar de proyecto no sale el anterior
    <IfModule headers_module>
        Header always set Cache-Control "no-store"
    </IfModule>
</VirtualHost>

<VirtualHost *:{p.Https}>
    ServerAdmin {admin}
    DocumentRoot "{root}"
    ServerName {name}
    ServerAlias www.{name}
    ErrorLog "${"{"}NEXUM_REGISTROS{"}"}/{name}-error.log"
    SSLEngine on
    SSLCertificateFile "{crt}"
    SSLCertificateKeyFile "{key}"
    <IfModule headers_module>
        Header always set Cache-Control "no-store"
    </IfModule>
</VirtualHost>

""";
    }

    /// <summary>
    /// Cambia el DocumentRoot de los vhosts de web.local a la carpeta del proyecto (o a la página vacía con
    /// null). Devuelve el texto nuevo (igual si no hay vhost de web.local).
    /// </summary>
    public static string SetProjectRoot(string text, Disposicion l, string? folder)
    {
        var target = folder == null ? l.EmptyProjectDir : Path.Combine(l.Htdocs, folder);
        var nl = text.Contains("\r\n") ? "\r\n" : "\n";
        var lines = text.Replace("\r\n", "\n").Split('\n');
        foreach (var v in Parse(text).Where(x => x.Name == Disposicion.ProjectVhost))
        {
            for (int i = v.StartLine + 1; i < v.EndLine; i++)
            {
                var m = Regex.Match(lines[i], @"^(\s*)DocumentRoot\s+", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                if (m.Success && !lines[i].TrimStart().StartsWith('#'))
                    lines[i] = $"{m.Groups[1].Value}DocumentRoot \"{Apache.Fwd(target)}\"";
            }
        }
        return string.Join(nl, lines);
    }

    /// <summary>Alias del dominio: www.dominio, o el dominio sin www si ya lo lleva.</summary>
    public static string DomainAlias(string domain) => domain.StartsWith("www.", StringComparison.Ordinal) ? domain[4..] : "www." + domain;

    /// <summary>Bloques http y/o https de un dominio (tienda PrestaShop o proyecto nuevo) que apuntan a su carpeta.</summary>
    public static string DomainBlocks(Disposicion l, Puertos p, string folder, string domain, string admin, bool http, bool https,
        string crt, string key)
    {
        var alias = DomainAlias(domain);
        var root = Apache.Fwd(Path.Combine(l.Htdocs, folder));
        var sb = new StringBuilder();
        sb.Append($"\n\n######################### URL {domain.ToUpperInvariant()} (Nexum Dev Stack) #########################\n");
        if (http)
            sb.Append($"""

<VirtualHost *:{p.Http}>
    ServerAdmin {admin}
    DocumentRoot "{root}"
    ServerName {domain}
    ServerAlias {alias}
    ErrorLog "${"{"}NEXUM_REGISTROS{"}"}/{domain}-error.log"
</VirtualHost>

""");
        if (https)
            sb.Append($"""

<VirtualHost *:{p.Https}>
    ServerAdmin {admin}
    DocumentRoot "{root}"
    ServerName {domain}
    ServerAlias {alias}
    ErrorLog "${"{"}NEXUM_REGISTROS{"}"}/{domain}-error.log"

    SSLEngine on
    SSLCertificateFile "{Apache.Fwd(crt)}"
    SSLCertificateKeyFile "{Apache.Fwd(key)}"
</VirtualHost>

""");
        return sb.ToString();
    }

    /// <summary>Texto inicial de httpd-vhosts.conf (vacío, con su explicación).</summary>
    public static string InitialFile(Disposicion l) => $"""
# Virtual hosts de Nexum Dev Stack, compartidos por todas las versiones de PHP.
# Se editan desde Configuración (Editar vhosts): se comprueban con Apache antes de aplicarlos.
# Las rutas, con barras normales: {Apache.Fwd(l.Htdocs)}/<carpeta>.
# ${"{"}NEXUM_REGISTROS{"}"} es la carpeta de registros de la versión activa.

""";
}
