using System.Text.RegularExpressions;
using NexumDevStack.Core.Pila;

namespace NexumDevStack.Core.Configuracion;

/// <summary>Un dominio de los vhosts para la pestaña Dominios y hosts (como gui_hosts de Linux).</summary>
public sealed record DominioVhost(string Name, string Alias, string Folder, bool Faked, bool Https, bool HasCert, bool PrestaShop, bool Custom);

/// <summary>
/// El fichero hosts de Windows: falsear (127.0.0.1) o dejar de falsear los dominios de los vhosts, como
/// hosts_fake de Linux. Solo toca líneas 127.0.0.1 cuyos nombres sean todos dominios de vhosts de proyectos
/// (nunca localhost ni web.local): las comenta o les quita el #, y añade la línea si no existía.
/// </summary>
public static class Hosts
{
    static readonly Regex LineRx = new(@"^(\s*)(#+\s*)?(127\.0\.0\.1)(\s+)(.*?)\s*$", RegexOptions.CultureInvariant);

    public enum Modo { Cargar, Si, No }

    /// <summary>
    /// Nuevo hosts. <paramref name="mode"/> Cargar: falsea los indicados (puede no haber ninguno) y deja de
    /// falsear el resto de dominios de los vhosts. Si / No: solo falsea o deja de falsear esos.
    /// Los .local se quedan siempre (sin su línea, Windows los pregunta a la red por mDNS), salvo los apagados.
    /// </summary>
    public static (string Text, List<string> Changes) Fake(string hosts, IReadOnlyList<VhostInfo> vhosts, Modo mode,
        IEnumerable<string> wanted, IEnumerable<string> localOff)
    {
        var skip = new HashSet<string> { "localhost", Disposicion.ProjectVhost, "www." + Disposicion.ProjectVhost };
        var managed = new HashSet<string>();
        foreach (var v in vhosts)
            foreach (var n in v.AllNames)
                if (n.Length > 0)
                    managed.Add(n.ToLowerInvariant());
        managed.ExceptWith(skip);
        var off = new HashSet<string>(localOff.Select(x => x.ToLowerInvariant()));
        var always = new HashSet<string>(managed.Where(n => n.EndsWith(".local", StringComparison.Ordinal)));
        always.ExceptWith(off);
        managed.ExceptWith(always);
        var wantedList = wanted.Select(d => d.ToLowerInvariant()).ToList();
        var target = new HashSet<string>();
        foreach (var d in wantedList)
        {
            target.Add(d);
            target.Add(d.StartsWith("www.", StringComparison.Ordinal) ? d[4..] : "www." + d);
        }
        wantedList = wantedList.Where(d => !skip.Contains(d)).ToList();
        target.ExceptWith(skip);
        if (mode == Modo.No)
            managed.UnionWith(target.Except(always));

        var nl = hosts.Contains("\r\n") ? "\r\n" : "\n";
        var lines = hosts.Replace("\r\n", "\n").Split('\n').ToList();
        if (lines.Count > 0 && lines[^1].Length == 0)
            lines.RemoveAt(lines.Count - 1);
        var done = new HashSet<string>();
        var changes = new List<string>();
        var output = new List<string>();
        foreach (var raw in lines)
        {
            var line = raw;
            var m = LineRx.Match(line);
            var names = m.Success ? m.Groups[5].Value.Split('#')[0].Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries) : Array.Empty<string>();
            var lnames = new HashSet<string>(names.Select(n => n.ToLowerInvariant()));
            var ours = names.Length > 0 && lnames.IsSubsetOf(managed.Union(always).Union(target)) && lnames.Except(always).Any();
            if (!ours)
            {
                output.Add(line);
                continue;
            }
            var active = !m.Groups[2].Success;
            bool on;
            if (lnames.Overlaps(target))
                // Se falsea (sin quitar el # a una segunda línea repetida) o se deja de falsear
                on = mode != Modo.No && (active || !lnames.IsSubsetOf(done));
            else
                // Al cargar un proyecto, el resto de dominios vuelve a la web real
                on = active && mode != Modo.Cargar;
            if (on && !active)
            {
                line = m.Groups[1].Value + m.Groups[3].Value + m.Groups[4].Value + m.Groups[5].Value;
                changes.Add("Falseado en hosts: " + string.Join(" ", names));
            }
            else if (!on && active)
            {
                line = m.Groups[1].Value + "#" + m.Groups[3].Value + m.Groups[4].Value + m.Groups[5].Value;
                // Los .local de esa línea no se comentan: se quedan activos en otra
                var keep = names.Where(n => always.Contains(n.ToLowerInvariant())).ToList();
                if (keep.Count > 0)
                {
                    line = m.Groups[1].Value + "#" + m.Groups[3].Value + m.Groups[4].Value +
                           string.Join(" ", names.Where(n => !always.Contains(n.ToLowerInvariant())));
                    output.Add(m.Groups[1].Value + m.Groups[3].Value + m.Groups[4].Value + string.Join(" ", keep));
                }
                if (names.All(n => n.EndsWith(".local", StringComparison.OrdinalIgnoreCase)))
                    changes.Add("Apagado en hosts: " + string.Join(" ", names));
                else
                    changes.Add("Ya no está falseado (lleva a la web real): " + string.Join(" ", names));
            }
            if (on)
                done.UnionWith(lnames);
            output.Add(line);
        }
        var activeNames = new HashSet<string>();
        foreach (var l in output)
        {
            var mm = LineRx.Match(l);
            if (mm.Success && !mm.Groups[2].Success)
                foreach (var n in mm.Groups[5].Value.Split('#')[0].Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries))
                    activeNames.Add(n.ToLowerInvariant());
        }
        int LastLoopback()
        {
            var idx = -1;
            for (int i = 0; i < output.Count; i++)
                if (LineRx.IsMatch(output[i]))
                    idx = i;
            return idx < 0 ? output.Count - 1 : idx;
        }
        // (también los que estén comentados: se vuelven a añadir)
        foreach (var d in always.Except(activeNames).OrderBy(x => x, StringComparer.Ordinal))
        {
            output.Insert(LastLoopback() + 1, "127.0.0.1 " + d);
            changes.Add("En hosts, para que no se pregunte a la red: " + d);
        }
        if (mode is Modo.Cargar or Modo.Si)
            foreach (var d in wantedList)
            {
                if (done.Contains(d))
                    continue;
                var alias = d.StartsWith("www.", StringComparison.Ordinal) ? d[4..] : "www." + d;
                output.Insert(LastLoopback() + 1, $"127.0.0.1 {d} {alias}");
                done.Add(d);
                done.Add(alias);
                changes.Add($"Falseado en hosts: {d} {alias}");
            }
        return (string.Join(nl, output) + nl, changes);
    }

    /// <summary>
    /// El vhost de los proyectos (web.local) pasa a 127.0.0.1: se quita de las líneas que lo llevaban a otra
    /// dirección y se añade su línea (como hosts_fix_link de Linux).
    /// </summary>
    public static (string Text, List<string> Changes) FixLink(string hosts, string name)
    {
        name = name.ToLowerInvariant();
        var nl = hosts.Contains("\r\n") ? "\r\n" : "\n";
        var lines = hosts.Replace("\r\n", "\n").Split('\n').ToList();
        if (lines.Count > 0 && lines[^1].Length == 0)
            lines.RemoveAt(lines.Count - 1);
        var output = new List<string>();
        var changes = new List<string>();
        var ok = false;
        foreach (var raw in lines)
        {
            var line = raw;
            var hash = line.IndexOf('#');
            var body = hash >= 0 ? line[..hash] : line;
            var comment = hash >= 0 ? line[hash..] : "";
            var w = body.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (w.Length >= 2 && w.Skip(1).Any(x => x.ToLowerInvariant() == name))
            {
                if (w[0] == "127.0.0.1")
                    ok = true;
                else
                {
                    var rest = w.Skip(1).Where(x => x.ToLowerInvariant() != name).ToList();
                    changes.Add($"{name} ya no lleva a {w[0]}");
                    line = rest.Count > 0
                        ? string.Join(" ", new[] { w[0] }.Concat(rest)) + (comment.Length > 0 ? " " + comment : "")
                        : $"# (Nexum Dev Stack: {name} pasa a 127.0.0.1) {line}";
                }
            }
            output.Add(line);
        }
        if (!ok)
        {
            var last = -1;
            for (int i = 0; i < output.Count; i++)
                if (Regex.IsMatch(output[i], @"^\s*127\.0\.0\.1\s"))
                    last = i;
            output.Insert(last < 0 ? output.Count : last + 1, $"127.0.0.1 {name} www.{name}");
            changes.Add($"{name} lleva a este equipo (127.0.0.1)");
        }
        return (string.Join(nl, output) + nl, changes);
    }

    /// <summary>Nombres que ahora llevan a 127.0.0.1 (líneas sin comentar).</summary>
    public static HashSet<string> ActiveLoopbackNames(string hosts)
    {
        var set = new HashSet<string>();
        foreach (var line in hosts.Replace("\r\n", "\n").Split('\n'))
        {
            var m = Regex.Match(line, @"^\s*127\.0\.0\.1\s+(.*)");
            if (m.Success)
                foreach (var n in m.Groups[1].Value.Split('#')[0].Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries))
                    set.Add(n.ToLowerInvariant());
        }
        return set;
    }

    /// <summary>Dirección a la que lleva ahora un nombre en hosts ("" si no está).</summary>
    public static string AddressOf(string hosts, string name)
    {
        foreach (var line in hosts.Replace("\r\n", "\n").Split('\n'))
        {
            var w = line.Split('#')[0].Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (w.Length >= 2 && w.Skip(1).Any(x => x.Equals(name, StringComparison.OrdinalIgnoreCase)))
                return Regex.Replace(w[0], "[^0-9A-Fa-f.:]", "");
        }
        return "";
    }

    /// <summary>Dominios de los vhosts (sin web.local) con si están falseados, su https y su certificado.</summary>
    public static List<DominioVhost> Domains(IReadOnlyList<VhostInfo> vhosts, string hosts, Func<string, bool> isPrestaShopFolder,
        ISet<string> custom, Func<string, bool> fileExists, int httpsPort)
    {
        var active = ActiveLoopbackNames(hosts);
        var rows = new SortedDictionary<string, (string Alias, string Folder, bool Https, bool Crt)>(StringComparer.Ordinal);
        foreach (var v in vhosts)
        {
            if (v.Name is "localhost" || v.Name == Disposicion.ProjectVhost || v.Name == "www." + Disposicion.ProjectVhost)
                continue;
            rows.TryGetValue(v.Name, out var r);
            r.Alias ??= "";
            r.Folder ??= "";
            // El alias www.<dominio> si lo hay
            r.Alias = v.Aliases.Contains("www." + v.Name) ? "www." + v.Name : (r.Alias.Length > 0 ? r.Alias : v.Aliases.FirstOrDefault() ?? "");
            if (r.Folder.Length == 0)
                r.Folder = v.Folder;
            if (v.Port == httpsPort)
            {
                r.Https = true;
                r.Crt = v.Crt.Length > 0 && fileExists(v.Crt);
            }
            rows[v.Name] = r;
        }
        return rows.Select(kv => new DominioVhost(kv.Key, kv.Value.Alias, kv.Value.Folder, active.Contains(kv.Key), kv.Value.Https,
            kv.Value.Crt, kv.Value.Folder.Length > 0 && isPrestaShopFolder(kv.Value.Folder), custom.Contains(kv.Key))).ToList();
    }

    /// <summary>
    /// ¿Es un hosts aceptable? Lo comprueba el proceso con permisos de administrador antes de escribirlo:
    /// solo texto, comentarios y líneas «dirección nombre…» (con nombres de dominio normales).
    /// </summary>
    public static string? Problem(string text)
    {
        if (text.Length > 1_000_000)
            return "el fichero es demasiado grande";
        if (text.Contains('\0'))
            return "el fichero no es de texto";
        var n = 0;
        foreach (var raw in text.Replace("\r\n", "\n").Split('\n'))
        {
            n++;
            var line = raw.Trim();
            if (line.Length == 0 || line.StartsWith('#'))
                continue;
            var body = line.Split('#')[0].Trim();
            var w = body.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (w.Length < 2)
                return $"la línea {n} no tiene dirección y nombre: {Clip(raw)}";
            if (!Regex.IsMatch(w[0], @"^([0-9]{1,3}(\.[0-9]{1,3}){3}|[0-9A-Fa-f:]+(%[A-Za-z0-9]+)?)$"))
                return $"la línea {n} no empieza por una dirección IP: {Clip(raw)}";
            foreach (var name in w.Skip(1))
                if (!Regex.IsMatch(name, @"^[A-Za-z0-9_]([A-Za-z0-9_.-]{0,252})$"))
                    return $"la línea {n} tiene un nombre no válido: {Clip(name)}";
        }
        return null;
    }

    static string Clip(string s) => s.Length > 60 ? s[..60] + "…" : s;
}
