using System.Text.RegularExpressions;

namespace NexumDevStack.Core.Util;

/// <summary>Comparación de versiones (8.4.9 &lt; 8.4.27), como sort -V del script.</summary>
public static class Versiones
{
    public static int[] Parts(string? v)
    {
        var m = Regex.Matches(v ?? "", @"\d+");
        return m.Take(4).Select(x => int.TryParse(x.Value, out var n) ? n : 0).ToArray();
    }

    public static int Compare(string? a, string? b)
    {
        var x = Parts(a);
        var y = Parts(b);
        for (int i = 0; i < Math.Max(x.Length, y.Length); i++)
        {
            int p = i < x.Length ? x[i] : 0, q = i < y.Length ? y[i] : 0;
            if (p != q) return p.CompareTo(q);
        }
        return 0;
    }

    /// <summary>Rama de una versión: 8.4.27 → 8.4</summary>
    public static string Branch(string version)
    {
        var p = version.Split('.');
        return p.Length >= 2 ? p[0] + "." + p[1] : version;
    }

    public static readonly IComparer<string> Comparer = Comparer<string>.Create(Compare);
}
