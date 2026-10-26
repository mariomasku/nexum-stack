using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.Catalogo;

/// <summary>Una versión de PHP para Windows (Thread Safe, x64) con su fichero y su sha256.</summary>
public sealed record PhpWindows(string Version, string File, string Sha256, string Url);

/// <summary>Estado de una rama en php.net: stable, security o eol, con sus fechas.</summary>
public sealed record EstadoRama(string Branch, string State, string ActiveEnd, string SecurityEnd);

/// <summary>Un parche publicado en php.net: fecha (AAAA-MM-DD) y si es de seguridad.</summary>
public sealed record ParchePhp(string Version, string Date, bool Security);

/// <summary>
/// Lectura de lo que publican windows.php.net, php.net, Apache Lounge y MariaDB. Solo se acepta lo que
/// tiene la forma esperada (versiones X.Y.Z, sumas de 64 caracteres, URL https): lo que sale de aquí va a
/// rutas, URL y ficheros de configuración.
/// </summary>
public static class Fuentes
{
    static readonly Regex Sha = new("^[0-9a-f]{64}$", RegexOptions.CultureInvariant);
    static readonly Regex Version3 = new(@"^\d+\.\d+\.\d+$", RegexOptions.CultureInvariant);
    static readonly Regex Branch = new(@"^\d+\.\d+$", RegexOptions.CultureInvariant);

    /// <summary>releases.json de windows.php.net: el último parche de cada rama, Thread Safe x64.</summary>
    public static Dictionary<string, PhpWindows> ParseWindowsReleases(string json)
    {
        var result = new Dictionary<string, PhpWindows>();
        using var doc = JsonDocument.Parse(json);
        foreach (var branch in doc.RootElement.EnumerateObject())
        {
            if (!Branch.IsMatch(branch.Name) || branch.Value.ValueKind != JsonValueKind.Object)
                continue;
            if (!branch.Value.TryGetProperty("version", out var ver) || ver.GetString() is not { } version || !Version3.IsMatch(version))
                continue;
            foreach (var build in branch.Value.EnumerateObject())
            {
                // ts-vs17-x64, ts-vc15-x64 (sin nts: con Apache va el Thread Safe)
                if (!Regex.IsMatch(build.Name, @"^ts-v[cs]\d+-x64$") || build.Value.ValueKind != JsonValueKind.Object)
                    continue;
                if (!build.Value.TryGetProperty("zip", out var zip) || !zip.TryGetProperty("path", out var path) ||
                    !zip.TryGetProperty("sha256", out var sha))
                    continue;
                var file = path.GetString() ?? "";
                var sum = (sha.GetString() ?? "").ToLowerInvariant();
                if (!IsPhpZipName(file, version) || !Sha.IsMatch(sum))
                    continue;
                result[branch.Name] = new PhpWindows(version, file, sum, Catalogo.PhpReleasesBase + file);
            }
        }
        return result;
    }

    /// <summary>php-8.4.27-Win32-vs17-x64.zip (la versión de su nombre tiene que ser la suya).</summary>
    public static bool IsPhpZipName(string file, string version) =>
        Regex.IsMatch(file, @"^php-" + Regex.Escape(version) + @"-Win32-(vc|VC|vs|VS)\d+-x64\.zip$", RegexOptions.CultureInvariant);

    /// <summary>Ficheros de PHP (Thread Safe x64) del archivo de windows.php.net: versión → (fichero, tiene SBOM).</summary>
    public static Dictionary<string, (string File, bool HasSbom)> ParseArchiveListing(string html)
    {
        var files = new Dictionary<string, (string, bool)>();
        var sboms = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (Match m in Regex.Matches(html, @"href=""(php-(\d+\.\d+\.\d+)-Win32-(?:vc|VC|vs|VS)\d+-x64\.zip)(\.spdx\.json)?""",
                     RegexOptions.CultureInvariant))
        {
            if (m.Groups[3].Success)
                sboms.Add(m.Groups[1].Value);
            else
                files[m.Groups[2].Value] = (m.Groups[1].Value, false);
        }
        foreach (var key in files.Keys.ToList())
            files[key] = (files[key].Item1, sboms.Contains(files[key].Item1));
        return files;
    }

    /// <summary>sha256 del zip de PHP en su SBOM (SPDX) del archivo de windows.php.net.</summary>
    public static string? ParseSpdxSha(string json, string file)
    {
        using var doc = JsonDocument.Parse(json);
        if (!doc.RootElement.TryGetProperty("packages", out var packages))
            return null;
        foreach (var p in packages.EnumerateArray())
        {
            if (!p.TryGetProperty("packageFileName", out var name) || name.GetString() != file)
                continue;
            if (!p.TryGetProperty("checksums", out var sums))
                continue;
            foreach (var s in sums.EnumerateArray())
                if (s.TryGetProperty("algorithm", out var alg) && alg.GetString() == "SHA256" &&
                    s.TryGetProperty("checksumValue", out var val) && val.GetString() is { } v && Sha.IsMatch(v.ToLowerInvariant()))
                    return v.ToLowerInvariant();
        }
        return null;
    }

    /// <summary>branches.php de php.net: estado y fechas de cada rama.</summary>
    public static Dictionary<string, EstadoRama> ParseBranches(string json)
    {
        var result = new Dictionary<string, EstadoRama>();
        using var doc = JsonDocument.Parse(json);
        if (doc.RootElement.ValueKind != JsonValueKind.Array)
            return result;
        foreach (var b in doc.RootElement.EnumerateArray())
        {
            var branch = b.TryGetProperty("branch", out var br) ? br.ToString() : "";
            var state = b.TryGetProperty("state", out var st) ? st.GetString() ?? "" : "";
            if (!Branch.IsMatch(branch) || state is not ("stable" or "security" or "eol"))
                continue;
            static string Date(JsonElement e, string name) =>
                e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String && (v.GetString() ?? "").Length >= 10
                    ? v.GetString()![..10] : "";
            result[branch] = new EstadoRama(branch, state, Date(b, "active_support_end"), Date(b, "security_support_end"));
        }
        return result;
    }

    /// <summary>active.php de php.net: ramas con soporte.</summary>
    public static HashSet<string> ParseActive(string json)
    {
        var result = new HashSet<string>();
        using var doc = JsonDocument.Parse(json);
        foreach (var major in doc.RootElement.EnumerateObject())
            if (major.Value.ValueKind == JsonValueKind.Object)
                foreach (var branch in major.Value.EnumerateObject())
                    if (Branch.IsMatch(branch.Name))
                        result.Add(branch.Name);
        return result;
    }

    /// <summary>releases/index.php?json&amp;version=N&amp;max=1000 de php.net: todos los parches con su fecha.</summary>
    public static List<ParchePhp> ParsePhpNetReleases(string json)
    {
        var result = new List<ParchePhp>();
        using var doc = JsonDocument.Parse(json);
        if (doc.RootElement.ValueKind != JsonValueKind.Object || doc.RootElement.TryGetProperty("error", out _))
            return result;
        foreach (var r in doc.RootElement.EnumerateObject())
        {
            if (!Version3.IsMatch(r.Name) || r.Value.ValueKind != JsonValueKind.Object)
                continue;
            var date = "-";
            if (r.Value.TryGetProperty("date", out var d) && DateTime.TryParseExact(d.GetString(), "d MMM yyyy",
                    CultureInfo.InvariantCulture, DateTimeStyles.None, out var when))
                date = when.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
            var sec = r.Value.TryGetProperty("tags", out var tags) && tags.ValueKind == JsonValueKind.Array &&
                      tags.EnumerateArray().Any(t => t.GetString() == "security");
            result.Add(new ParchePhp(r.Name, date, sec));
        }
        result.Sort((a, b) => Versiones.Compare(b.Version, a.Version));
        return result;
    }

    /// <summary>Página de descargas de Apache Lounge: el zip de Apache 2.4 Win64 con su firma (.asc) y sus sumas (.txt).</summary>
    public static (string Zip, string Asc, string Txt, string Version)? ParseApacheLounge(string html)
    {
        var m = Regex.Match(html, @"href=""(/download/VS\d+/binaries/httpd-(2\.4\.\d+)-\d+-Win64-VS\d+\.zip)""",
            RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);
        if (!m.Success)
            return null;
        var zip = m.Groups[1].Value;
        // (la firma y las sumas, con el mismo nombre)
        var asc = Regex.Match(html, @"href=""(" + Regex.Escape(zip) + @"\.asc)""", RegexOptions.IgnoreCase);
        var txt = Regex.Match(html, @"href=""(" + Regex.Escape(zip) + @"\.txt)""", RegexOptions.IgnoreCase);
        return (Catalogo.ApacheLoungeBase + zip,
            Catalogo.ApacheLoungeBase + (asc.Success ? asc.Groups[1].Value : zip + ".asc"),
            Catalogo.ApacheLoungeBase + (txt.Success ? txt.Groups[1].Value : zip + ".txt"),
            m.Groups[2].Value);
    }

    /// <summary>Fichero de sumas de Apache Lounge (.txt): su SHA256.</summary>
    public static string? ParseApacheLoungeSha(string text, string file)
    {
        var m = Regex.Match(text, @"SHA256-Checksum for:\s*" + Regex.Escape(file) + @":\s*([0-9A-Fa-f]{64})", RegexOptions.CultureInvariant);
        return m.Success ? m.Groups[1].Value.ToLowerInvariant() : null;
    }

    /// <summary>API de MariaDB (…/rest-api/mariadb/&lt;rama&gt;/latest/): el zip de Windows x64 con su sha256 y su firma.</summary>
    public static (string Version, Descarga Download)? ParseMariaDbLatest(string json)
    {
        using var doc = JsonDocument.Parse(json);
        if (!doc.RootElement.TryGetProperty("releases", out var releases))
            return null;
        foreach (var rel in releases.EnumerateObject())
        {
            if (!Version3.IsMatch(rel.Name) || !rel.Value.TryGetProperty("files", out var files))
                continue;
            foreach (var f in files.EnumerateArray())
            {
                var name = f.TryGetProperty("file_name", out var fn) ? fn.GetString() ?? "" : "";
                if (name != $"mariadb-{rel.Name}-winx64.zip")
                    continue;
                var url = f.TryGetProperty("file_download_url", out var u) ? u.GetString() ?? "" : "";
                if (url.StartsWith("http://", StringComparison.Ordinal))
                    url = "https://" + url["http://".Length..];
                var sha = f.TryGetProperty("checksum", out var cs) && cs.ValueKind == JsonValueKind.Object &&
                          cs.TryGetProperty("sha256sum", out var s) ? (s.GetString() ?? "").ToLowerInvariant() : "";
                var sig = f.TryGetProperty("signature", out var sg) ? sg.GetString() : null;
                if (!url.StartsWith("https://", StringComparison.Ordinal) || url.Contains('|') || !Sha.IsMatch(sha))
                    continue;
                var signed = sig != null && sig.Contains("BEGIN PGP SIGNATURE", StringComparison.Ordinal);
                return (rel.Name, new Descarga(name, url, sha, null, signed ? sig : null, Catalogo.FprMariaDb,
                    signed ? "sha256 y firma GPG de MariaDB" : "sha256 de MariaDB (HTTPS, sin firma)"));
            }
        }
        return null;
    }

    /// <summary>cacert.pem.sha256 de curl.se: «suma  cacert.pem».</summary>
    public static string? ParseShaLine(string text)
    {
        var m = Regex.Match(text ?? "", @"^\s*([0-9a-fA-F]{64})\b", RegexOptions.Multiline);
        return m.Success ? m.Groups[1].Value.ToLowerInvariant() : null;
    }
}
