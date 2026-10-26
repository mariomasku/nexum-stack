using System.Text.RegularExpressions;
using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.Proyectos;

/// <summary>
/// Vínculos entre las BBDD y las carpetas de los proyectos (%LOCALAPPDATA%\NexumDevStack\proyectos), uno por
/// línea: base@versión=carpeta (en esa versión; sin carpeta, la base no es de ningún proyecto en ella) o
/// base=carpeta (en todas las versiones). El de la versión manda. Las versiones son las carpetas
/// (php-8.4.27). El mismo formato que ~/.lvm-instalador/proyectos de Linux.
/// </summary>
public sealed class Vinculos
{
    readonly string _file;

    public Vinculos(string file) => _file = file;

    static readonly Regex GlobalRx = new(@"^([A-Za-z0-9_][A-Za-z0-9_-]*)=([^|]+)$", RegexOptions.CultureInvariant);
    static readonly Regex PerRx = new(@"^([A-Za-z0-9_][A-Za-z0-9_-]*)@([A-Za-z0-9._-]+)=([^|]*)$", RegexOptions.CultureInvariant);

    List<string> Lines()
    {
        var text = Ficheros.ReadSmallText(_file);
        return text == null ? new List<string>() : text.Replace("\r\n", "\n").Split('\n').Where(l => l.Length > 0).ToList();
    }

    /// <summary>base → carpeta (los de todas las versiones; la última línea manda).</summary>
    public Dictionary<string, string> Global()
    {
        var d = new Dictionary<string, string>();
        foreach (var l in Lines())
        {
            var m = GlobalRx.Match(l);
            if (m.Success) d[m.Groups[1].Value] = m.Groups[2].Value;
        }
        return d;
    }

    /// <summary>(base, versión) → carpeta ("" = desvinculada en esa versión).</summary>
    public Dictionary<(string Db, string Ver), string> PerVersion()
    {
        var d = new Dictionary<(string, string), string>();
        foreach (var l in Lines())
        {
            var m = PerRx.Match(l);
            if (m.Success) d[(m.Groups[1].Value, m.Groups[2].Value)] = m.Groups[3].Value;
        }
        return d;
    }

    /// <summary>Carpeta vinculada a una BBDD en una versión: la de esa versión ("" = ninguna), la de todas o null.</summary>
    public string? LinkOf(string db, string ver)
    {
        if (PerVersion().TryGetValue((db, ver), out var f))
            return f;
        return Global().TryGetValue(db, out var g) ? g : null;
    }

    /// <summary>Base vinculada a una carpeta en una versión: la última que se vinculó.</summary>
    public string? SavedDb(string folder, string ver)
    {
        string? best = null;
        int bestLine = -1;
        var per = new Dictionary<string, (string Folder, int Line)>();
        var all = new Dictionary<string, (string Folder, int Line)>();
        var lines = Lines();
        for (int i = 0; i < lines.Count; i++)
        {
            var mp = PerRx.Match(lines[i]);
            if (mp.Success)
            {
                if (mp.Groups[2].Value == ver)
                    per[mp.Groups[1].Value] = (mp.Groups[3].Value, i);
                continue;
            }
            var mg = GlobalRx.Match(lines[i]);
            if (mg.Success)
                all[mg.Groups[1].Value] = (mg.Groups[2].Value, i);
        }
        foreach (var db in per.Keys.Union(all.Keys))
        {
            var v = per.TryGetValue(db, out var p) ? p : all[db];
            var last = Math.Max(per.TryGetValue(db, out var p2) ? p2.Line : -1, all.TryGetValue(db, out var a2) ? a2.Line : -1);
            if (v.Folder == folder && last > bestLine)
            {
                bestLine = last;
                best = db;
            }
        }
        return best;
    }

    /// <summary>
    /// Vincula la base a la carpeta en esa versión (sin carpeta, la desvincula). Con <paramref name="only"/>,
    /// en esa versión la carpeta deja de estar vinculada a otras bases.
    /// </summary>
    public void Remember(string db, string folder, string ver, bool only = false)
    {
        if (!Validacion.IsDbName(db) || !Regex.IsMatch(ver, @"^[A-Za-z0-9._-]+$") || folder.Contains('\n') || folder.Contains('|'))
            throw new ArgumentException("Vínculo no válido");
        var key = $"{db}@{ver}";
        var output = new List<string>();
        foreach (var l in Lines())
        {
            var k = l.Split('=', 2)[0];
            if (k == key)
                continue;
            if (only && folder.Length > 0 && l.Split('=', 2) is [var lk, var lf] && lf == folder && lk != db)
            {
                if (!lk.Contains('@'))
                {
                    // (la de todas las versiones se queda para las demás y en esta se desvincula)
                    output.Add(l);
                    output.Add($"{lk}@{ver}=");
                    continue;
                }
                if (lk[(lk.IndexOf('@') + 1)..] == ver)
                    continue;
            }
            output.Add(l);
        }
        output.Add($"{key}={folder}");
        Ficheros.WriteAtomic(_file, string.Join("\n", output) + "\n");
    }

    /// <summary>Guarda varios vínculos (base, versión, carpeta; carpeta vacía = ninguna) de una vez.</summary>
    public void Write(IEnumerable<(string Db, string Ver, string Folder)> changes)
    {
        var list = changes.ToList();
        var keys = new HashSet<string>(list.Select(c => $"{c.Db}@{c.Ver}"));
        var lines = Lines().Where(l => !keys.Contains(l.Split('=', 2)[0])).ToList();
        lines.AddRange(list.Select(c => $"{c.Db}@{c.Ver}={c.Folder}"));
        Ficheros.WriteAtomic(_file, string.Join("\n", lines) + "\n");
    }
}

/// <summary>Proyectos nuevos con dominio falseado: dominio=carpeta, uno por línea.</summary>
public sealed class DominiosPropios
{
    readonly string _file;

    public DominiosPropios(string file) => _file = file;

    public Dictionary<string, string> All()
    {
        var d = new Dictionary<string, string>();
        var text = Ficheros.ReadSmallText(_file);
        if (text == null) return d;
        foreach (var l in text.Replace("\r\n", "\n").Split('\n'))
        {
            var p = l.Split('=', 2);
            if (p.Length == 2 && Validacion.IsDomain(p[0]) && Validacion.IsProjectFolder(p[1]))
                d[p[0].ToLowerInvariant()] = p[1];
        }
        return d;
    }

    /// <summary>Dominio propio de una carpeta (null si no tiene).</summary>
    public string? Of(string folder) => All().Where(kv => kv.Value == folder).Select(kv => kv.Key).LastOrDefault();

    public void Set(string domain, string folder)
    {
        var all = All();
        all[domain.ToLowerInvariant()] = folder;
        Ficheros.WriteAtomic(_file, string.Join("\n", all.Select(kv => $"{kv.Key}={kv.Value}")) + "\n");
    }
}
