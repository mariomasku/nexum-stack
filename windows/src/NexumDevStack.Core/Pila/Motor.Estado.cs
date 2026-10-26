using NexumDevStack.Core.BaseDatos;
using NexumDevStack.Core.Catalogo;
using NexumDevStack.Core.Configuracion;
using NexumDevStack.Core.Descargas;
using NexumDevStack.Core.Plataforma;
using NexumDevStack.Core.Proyectos;
using NexumDevStack.Core.Util;
using Cat = NexumDevStack.Core.Catalogo.Catalogo;

namespace NexumDevStack.Core.Pila;

/// <summary>Una versión instalada con lo que enseña la ventana.</summary>
public sealed record VersionInfo(Manifiesto M, string Blocker, Php2Shell.Estado P2S, string P2SWhy, List<Bbdd> Dbs, bool ApacheOn, bool MariaDbOn)
{
    public string Folder => M.Folder;
}

/// <summary>Todo lo que enseña la ventana de una vez (como gui-datos de Linux).</summary>
public sealed class Estado
{
    public bool Prepared { get; init; }
    public string? ProgramVersion { get; init; }
    public bool ProgramOutdated { get; init; }
    public string? Active { get; init; }
    public bool ApacheOn { get; init; }
    public bool MariaDbOn { get; init; }
    public List<VersionInfo> Versions { get; init; } = new();
    public List<(string Folder, string Programs)> Stray { get; init; } = new();
    public List<PuertoOcupado> Ports { get; init; } = new();
    public Version? VcRuntime { get; init; }
    public bool VcOk { get; init; }
    public List<string> Untrusted { get; init; } = new();
    public List<(string Thumbprint, string Domain)> Stale { get; init; } = new();
    public bool CrossSite { get; init; }

    public bool Running => ApacheOn || MariaDbOn;
    public VersionInfo? ActiveInfo => Versions.FirstOrDefault(v => v.Folder == Active);
}

/// <summary>Los proyectos de htdocs y sus vínculos (como gui-proyectos de Linux).</summary>
public sealed class EstadoProyectos
{
    public string Link { get; init; } = Disposicion.ProjectVhost;
    /// <summary>Carpeta cargada ("" ninguna).</summary>
    public string Current { get; init; } = "";
    /// <summary>Todavía no hay vhost de proyectos: se crea al cargar el primero.</summary>
    public bool Create { get; init; }
    public List<Proyecto> List { get; init; } = new();
    public Dictionary<string, string> Saved { get; init; } = new();
    public Dictionary<(string Db, string Ver), string> VLinks { get; init; } = new();

    /// <summary>Carpeta vinculada a una BBDD en una versión ("" ninguna, null si no tiene).</summary>
    public string? LinkOf(string db, string ver) =>
        VLinks.TryGetValue((db, ver), out var f) ? f : Saved.TryGetValue(db, out var g) ? g : null;
}

/// <summary>Dominios de los vhosts y si web.local lleva a este equipo (como gui-hosts de Linux).</summary>
public sealed class EstadoHosts
{
    public List<DominioVhost> Domains { get; init; } = new();
    /// <summary>web.local no lleva a 127.0.0.1: la dirección a la que lleva ("" si no está), o null si está bien.</summary>
    public string? LinkFix { get; init; }
}

/// <summary>Una rama de PHP para instalar (como las líneas B de gui-ramas).</summary>
public sealed record RamaInfo(string Branch, string Latest, bool Supported, string MariaDb, string State, string Folder,
    string PhpNetState, string ActiveEnd, string SecurityEnd, string Date, bool Security);

/// <summary>Un parche de una rama (Otro parche concreto…): si se puede instalar en Windows (tiene su suma).</summary>
public sealed record ParcheInfo(string Version, string Date, bool Security, string Folder, string State, bool Installable);

public sealed partial class Motor
{
    public Estado ReadState(bool withCertificates = true)
    {
        var prepared = L.IsPrepared;
        var active = Active;
        var versions = new List<VersionInfo>();
        foreach (var m in Installed())
        {
            var (st, why) = Php2Shell.State(m.Php);
            var procs = VersionProcesses(m.Folder);
            versions.Add(new VersionInfo(m, RemoveBlocker(m.Folder), st, why, Databases(m.Folder),
                procs.Any(p => Path.GetFileName(p.ImagePath).Equals("httpd.exe", StringComparison.OrdinalIgnoreCase)),
                procs.Any(p => Path.GetFileName(p.ImagePath) is { } n && (n.Equals("mariadbd.exe", StringComparison.OrdinalIgnoreCase) ||
                                                                            n.Equals("mysqld.exe", StringComparison.OrdinalIgnoreCase)))));
        }
        var act = versions.FirstOrDefault(v => v.Folder == active);
        var vc = Pf.VcRuntimeVersion();
        var program = prepared ? InstalledProgramVersion() : null;
        List<string> untrusted = new();
        List<(string, string)> stale = new();
        if (withCertificates && prepared)
        {
            try
            {
                untrusted = UntrustedDomains();
                stale = StaleCertificates();
            }
            catch (Exception)
            {
                // (sin el almacén de certificados, sin avisos)
            }
        }
        return new Estado
        {
            Prepared = prepared,
            ProgramVersion = program,
            ProgramOutdated = prepared && (program == null || Versiones.Compare(program, AppInfo.Version) < 0),
            Active = active,
            ApacheOn = act?.ApacheOn ?? false,
            MariaDbOn = act?.MariaDbOn ?? false,
            Versions = versions,
            Stray = prepared ? StrayProcesses() : new(),
            Ports = SafePorts(),
            VcRuntime = vc,
            VcOk = vc != null && vc >= Cat.MinVcRuntime,
            Untrusted = untrusted,
            Stale = stale,
            CrossSite = CrossSiteOn,
        };
    }

    List<PuertoOcupado> SafePorts()
    {
        try { return ForeignPortOwners(); }
        catch (Exception) { return new(); }
    }

    public EstadoProyectos ReadProjects()
    {
        var vhosts = L.IsPrepared ? VhostList() : new List<VhostInfo>();
        var current = Vhosts.ProjectFolder(vhosts);
        var links = Links;
        return new EstadoProyectos
        {
            Current = current ?? "",
            Create = current == null,
            List = Directory.Exists(L.Htdocs) ? Escaner.Scan(L.Htdocs) : new(),
            Saved = links.Global(),
            VLinks = links.PerVersion(),
        };
    }

    public EstadoHosts ReadHosts()
    {
        var vhosts = L.IsPrepared ? VhostList() : new List<VhostInfo>();
        var hosts = Ficheros.ReadSmallText(Pf.HostsFilePath, 4_000_000) ?? "";
        var custom = new HashSet<string>(CustomDomains.All().Keys);
        var domains = Hosts.Domains(vhosts, hosts, f => Escaner.IsPrestaShop(L.Htdocs, f), custom,
            p => File.Exists(p.Replace('/', Path.DirectorySeparatorChar)), P.Https);
        string? fix = null;
        if (Vhosts.HasProjectVhost(vhosts) && !Hosts.ActiveLoopbackNames(hosts).Contains(Disposicion.ProjectVhost))
            fix = Hosts.AddressOf(hosts, Disposicion.ProjectVhost);
        return new EstadoHosts { Domains = domains, LinkFix = fix };
    }

    // ------------------------------------------------------------------ ramas para instalar
    /// <summary>
    /// Las ramas de PHP para instalar, con su último parche para Windows, su estado en php.net y si ya está
    /// instalada (como gui-ramas de Linux). Consulta windows.php.net y php.net.
    /// </summary>
    public List<RamaInfo> Branches(CancellationToken ct)
    {
        using var d = new Descargador(Signatures);
        var latest = LatestPhp(d, ct);
        Dictionary<string, EstadoRama> states = new();
        HashSet<string> supported = new();
        var releases = new List<ParchePhp>();
        try { states = Fuentes.ParseBranches(d.GetText(Cat.PhpNetBranches, ct)); } catch (Exception ex) when (ex is not OperationCanceledException) { }
        try { supported = Fuentes.ParseActive(d.GetText(Cat.PhpNetActive, ct)); } catch (Exception ex) when (ex is not OperationCanceledException) { }
        foreach (var major in new[] { 7, 8, 9 })
        {
            try { releases.AddRange(Fuentes.ParsePhpNetReleases(d.GetText(Cat.PhpNetReleases(major), ct))); }
            catch (Exception ex) when (ex is not OperationCanceledException) { }
        }
        var installed = Installed().Select(m => m.Folder).ToHashSet();
        var branches = Cat.OfferedBranches.Concat(supported.Where(b => latest.ContainsKey(b))).Distinct()
            .OrderByDescending(b => b, Versiones.Comparer).ToList();
        var rows = new List<RamaInfo>();
        foreach (var b in branches)
        {
            if (!latest.TryGetValue(b, out var w))
                continue;
            var folder = "php-" + w.Version;
            var state = installed.Contains(folder) ? "instalada" : Directory.Exists(L.VersionDir(folder)) ? "existe" : "nueva";
            states.TryGetValue(b, out var st);
            var rel = releases.FirstOrDefault(r => r.Version == w.Version);
            var date = rel?.Date ?? (Cat.PinnedOldPhp.TryGetValue(b, out var pin) ? pin.Date : "-");
            rows.Add(new RamaInfo(b, w.Version, supported.Contains(b), Cat.MariaDbBranch(b) ?? "", state, folder,
                st?.State ?? "", st?.ActiveEnd ?? "", st?.SecurityEnd ?? "", date, rel?.Security ?? false));
        }
        return rows;
    }

    /// <summary>Fecha de publicación del PHP de cada versión instalada (de php.net): carpeta → (php, fecha).</summary>
    public Dictionary<string, (string Php, string Date)> PhpDates(CancellationToken ct)
    {
        using var d = new Descargador(Signatures);
        var all = new List<ParchePhp>();
        foreach (var major in new[] { 7, 8 })
            all.AddRange(Fuentes.ParsePhpNetReleases(d.GetText(Cat.PhpNetReleases(major), ct)));
        var result = new Dictionary<string, (string, string)>();
        foreach (var m in Installed())
            if (all.FirstOrDefault(r => r.Version == m.Php) is { Date: not "-" } r)
                result[m.Folder] = (m.Php, r.Date);
        return result;
    }

    /// <summary>
    /// Parches de una rama (Otro parche concreto…): los de php.net con su fecha, si hay binario de Windows con
    /// suma publicada (el último, los fijados y los del archivo con SBOM) y si ya están instalados.
    /// </summary>
    public List<ParcheInfo> Patches(string branch, CancellationToken ct)
    {
        using var d = new Descargador(Signatures);
        var major = Versiones.Parts(branch).FirstOrDefault();
        var all = Fuentes.ParsePhpNetReleases(d.GetText(Cat.PhpNetReleases(major), ct))
            .Where(r => r.Version.StartsWith(branch + ".", StringComparison.Ordinal)).ToList();
        var listing = Fuentes.ParseArchiveListing(d.GetText(Cat.PhpArchivesBase, ct));
        var latest = LatestPhp(d, ct);
        var installed = Installed().Select(m => m.Folder).ToHashSet();
        var rows = new List<ParcheInfo>();
        foreach (var r in all)
        {
            var folder = "php-" + r.Version;
            var ok = latest.TryGetValue(branch, out var w) && w.Version == r.Version ||
                     listing.TryGetValue(r.Version, out var a) && a.HasSbom;
            var state = installed.Contains(folder) ? "instalada" : Directory.Exists(L.VersionDir(folder)) ? "existe" : "nueva";
            rows.Add(new ParcheInfo(r.Version, r.Date, r.Security, folder, state, ok));
        }
        return rows;
    }

    /// <summary>¿Está al día una versión? (si, no|última o error)</summary>
    public (string State, string Latest) UpToDate(string folder, CancellationToken ct)
    {
        var m = Require(folder);
        using var d = new Descargador(Signatures);
        var latest = LatestPhp(d, ct);
        if (!latest.TryGetValue(m.Branch, out var w))
            return ("error", "");
        return Versiones.Compare(w.Version, m.Php) > 0 ? ("no", w.Version) : ("si", m.Php);
    }
}
