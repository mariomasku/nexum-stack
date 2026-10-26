using System.Globalization;
using System.Text.RegularExpressions;

namespace NexumDevStack.Core.Util;

/// <summary>Textos en español como los de la ventana de Linux (plural, tamaños, fechas, lo que queda).</summary>
public static class Texto
{
    static readonly string[] Months =
    {
        "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
        "septiembre", "octubre", "noviembre", "diciembre",
    };

    public static string Plural(long n, string one, string many) => $"{n} {(n == 1 ? one : many)}";

    /// <summary>Tamaño legible: 512 B, 1,5 KB, 23,4 MB, 1,2 GB (con coma decimal).</summary>
    public static string Size(long bytes)
    {
        double n = bytes;
        foreach (var unit in new[] { "B", "KB", "MB", "GB" })
        {
            if (n < 1024 || unit == "GB")
                return unit == "B"
                    ? $"{(long)n} {unit}"
                    : n.ToString("0.0", CultureInfo.InvariantCulture).Replace('.', ',') + " " + unit;
            n /= 1024;
        }
        return $"{bytes} B";
    }

    /// <summary>2026-12-31 → diciembre de 2026</summary>
    public static string Month(string date)
    {
        var p = (date ?? "").Split('-');
        if (p.Length >= 2 && int.TryParse(p[1], out var m) && m is >= 1 and <= 12)
            return $"{Months[m - 1]} de {p[0]}";
        return date ?? "";
    }

    /// <summary>2026-10-21 → 21 de octubre de 2026</summary>
    public static string Day(string date)
    {
        var p = (date ?? "").Split('-');
        if (p.Length >= 3 && int.TryParse(p[1], out var m) && m is >= 1 and <= 12 && int.TryParse(p[2], out var d))
            return $"{d} de {Months[m - 1]} de {p[0]}";
        return date ?? "";
    }

    /// <summary>Tiempo como un reloj: 0:42, 3:05, 1:02:10</summary>
    public static string Clock(double seconds)
    {
        var s = (long)Math.Max(0, seconds);
        return s >= 3600 ? $"{s / 3600}:{s / 60 % 60:00}:{s % 60:00}" : $"{s / 60}:{s % 60:00}";
    }

    /// <summary>Lo que queda, al ritmo de hasta ahora (done % en elapsed segundos; quedan left %).</summary>
    public static string TimeLeft(double elapsed, double done, double left)
    {
        if (done < 3 || elapsed < 3)
            return "calculando lo que queda…";
        var secs = (long)(elapsed * left / done);
        if (secs < 60)
            return $"quedan unos {Math.Max(5, (secs + 4) / 5 * 5)} s";
        if (secs < 90)
            return "queda 1 min";
        if (secs < 3600)
            return $"quedan unos {(secs + 30) / 60} min";
        return $"quedan unas {secs / 3600} h {secs / 60 % 60:00} min";
    }

    /// <summary>Antigüedad aproximada: hace 5 min, hace 3 horas, hace 12 días…</summary>
    public static string Age(long secs)
    {
        if (secs < 3600) return "hace " + Plural(Math.Max(1, secs / 60), "min", "min");
        if (secs < 86400) return "hace " + Plural(secs / 3600, "hora", "horas");
        if (secs < 60 * 86400) return "hace " + Plural(secs / 86400, "día", "días");
        if (secs < 365 * 86400) return "hace " + Plural(secs / (30 * 86400), "mes", "meses");
        return "hace " + Plural(secs / (365 * 86400), "año", "años");
    }

    public static string Stamp(DateTimeOffset when) => when.ToLocalTime().ToString("dd/MM/yyyy HH:mm", CultureInfo.InvariantCulture);

    /// <summary>Fecha de una BBDD para su fila: la de su importación (i) o la del último cambio de sus tablas (c).</summary>
    public static string DbDate(long unix, char kind)
    {
        if (unix <= 0) return "";
        var when = DateTimeOffset.FromUnixTimeSeconds(unix).ToLocalTime();
        var stamp = when.ToString("dd/MM/yyyy 'a las' HH:mm", CultureInfo.InvariantCulture);
        var age = Age(Math.Max(0, DateTimeOffset.UtcNow.ToUnixTimeSeconds() - unix));
        return (kind == 'i' ? "Importada el " : "Tablas cambiadas el ") + stamp + "  ·  " + age;
    }

    /// <summary>Quita los caracteres de control (lo que sale en la consola o en la ventana).</summary>
    public static string Clean(string? text) =>
        Regex.Replace(text ?? "", @"[\x00-\x08\x0b-\x1f\x7f-\x9f]", "?");

    /// <summary>Primera letra en mayúscula.</summary>
    public static string Capitalize(string s) => string.IsNullOrEmpty(s) ? s : char.ToUpper(s[0], CultureInfo.GetCultureInfo("es-ES")) + s[1..];
}
