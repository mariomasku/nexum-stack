using NexumDevStack.Core.BaseDatos;
using NexumDevStack.Core.Catalogo;
using NexumDevStack.Core.Configuracion;
using NexumDevStack.Core.Descargas;
using NexumDevStack.Core.Tareas;
using NexumDevStack.Core.Util;
using Cat = NexumDevStack.Core.Catalogo.Catalogo;

namespace NexumDevStack.Core.Pila;

/// <summary>Instalar, actualizar a otro parche y desinstalar versiones.</summary>
public sealed partial class Motor
{
    // ------------------------------------------------------------------ qué se descarga
    /// <summary>
    /// El zip de PHP de Windows (Thread Safe x64) de una versión: el último de su rama de releases.json, uno del
    /// archivo con su suma en su SBOM, o los fijados de 7.1-7.3. Sin suma publicada, no se instala.
    /// </summary>
    public Descarga ResolvePhp(string version, Descargador d, ISalida o)
    {
        var branch = Versiones.Branch(version);
        if (Cat.PinnedOldPhp.TryGetValue(branch, out var pin) && pin.Version == version)
            return new Descarga(pin.File, Cat.PhpArchivesBase + pin.File, pin.Sha256, null, null, Array.Empty<string>(),
                "sha256 fijada en Nexum (windows.php.net no publica firmas ni la suma de su archivo)");
        try
        {
            var rel = Fuentes.ParseWindowsReleases(d.GetText(Cat.PhpReleasesUrl, o.Cancel));
            if (rel.TryGetValue(branch, out var w) && w.Version == version)
                return new Descarga(w.File, w.Url, w.Sha256, null, null, Array.Empty<string>(),
                    "sha256 de windows.php.net (HTTPS; PHP de Windows no publica firmas)");
        }
        catch (Exception ex) when (ex is HttpRequestException or System.Text.Json.JsonException or TaskCanceledException)
        {
            o.Line($"  No se ha podido leer releases.json de windows.php.net ({ex.Message}); se mira su archivo");
        }
        var listing = Fuentes.ParseArchiveListing(d.GetText(Cat.PhpArchivesBase, o.Cancel));
        if (!listing.TryGetValue(version, out var arch))
            throw new NexumException($"windows.php.net no tiene PHP {version} para Windows x64 (Thread Safe).");
        if (!arch.HasSbom)
            throw new NexumException($"PHP {version}: windows.php.net no publica su suma sha256 (no tiene SBOM), así que no se puede comprobar la descarga. No se instala: elige otro parche.");
        var sha = Fuentes.ParseSpdxSha(d.GetText(Cat.PhpArchivesBase + arch.File + ".spdx.json", o.Cancel), arch.File)
                  ?? throw new NexumException($"PHP {version}: su SBOM no trae la suma sha256. No se instala.");
        return new Descarga(arch.File, Cat.PhpArchivesBase + arch.File, sha, null, null, Array.Empty<string>(),
            "sha256 del SBOM de windows.php.net (HTTPS; PHP de Windows no publica firmas)");
    }

    /// <summary>Apache 2.4 de Apache Lounge: el último de su página, con su sha256 (.txt) y su firma (.asc).</summary>
    public (Descarga Download, string Version, string Build) ResolveApache(Descargador d, ISalida o)
    {
        try
        {
            var page = Fuentes.ParseApacheLounge(d.GetText(Cat.ApacheLoungePage, o.Cancel));
            if (page != null)
            {
                var (zip, asc, txt, version) = page.Value;
                var name = zip[(zip.LastIndexOf('/') + 1)..];
                var sha = Fuentes.ParseApacheLoungeSha(d.GetText(txt, o.Cancel), name);
                if (sha != null)
                    return (new Descarga(name, zip, sha, asc, null, Cat.FprApacheLounge, "sha256 y firma GPG de Apache Lounge"),
                        version, BuildOf(name));
            }
            o.Line("  La página de Apache Lounge no tiene lo esperado: se usa el Apache fijado en Nexum");
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or NexumException)
        {
            o.Line($"  No se ha podido leer la página de Apache Lounge ({ex.Message}): se usa el Apache fijado en Nexum");
        }
        var pin = Cat.PinnedApache;
        var v = System.Text.RegularExpressions.Regex.Match(pin.Name, @"httpd-(2\.4\.\d+)").Groups[1].Value;
        return (pin, v, BuildOf(pin.Name));
    }

    static string BuildOf(string name)
    {
        var m = System.Text.RegularExpressions.Regex.Match(name, @"-(VS\d+)\.zip$", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        return m.Success ? m.Groups[1].Value.ToUpperInvariant() : "";
    }

    /// <summary>MariaDB de la rama: el último de la API de MariaDB (sha256 y firma) o el fijado.</summary>
    public (Descarga Download, string Version) ResolveMariaDb(string branch, Descargador d, ISalida o)
    {
        try
        {
            var r = Fuentes.ParseMariaDbLatest(d.GetText(Cat.MariaDbApi(branch), o.Cancel));
            if (r != null)
                return (r.Value.Download, r.Value.Version);
        }
        catch (Exception ex) when (ex is HttpRequestException or System.Text.Json.JsonException or TaskCanceledException)
        {
            o.Line($"  No se ha podido consultar la API de MariaDB ({ex.Message}): se usa el fijado en Nexum");
        }
        if (!Cat.PinnedMariaDb.TryGetValue(branch, out var pin))
            throw new NexumException($"No se sabe qué MariaDB {branch} descargar.");
        var file = $"mariadb-{pin.Version}-winx64.zip";
        return (new Descarga(file, $"https://archive.mariadb.org/mariadb-{pin.Version}/winx64-packages/{file}", pin.Sha256, null, null,
            Cat.FprMariaDb, "sha256 fijada en Nexum (comprobada con la firma de MariaDB el 25/10/2026)"), pin.Version);
    }

    /// <summary>Último parche de cada rama que se puede instalar en Windows (releases.json y los fijados).</summary>
    public Dictionary<string, PhpWindows> LatestPhp(Descargador d, CancellationToken ct)
    {
        var rel = Fuentes.ParseWindowsReleases(d.GetText(Cat.PhpReleasesUrl, ct));
        foreach (var (branch, pin) in Cat.PinnedOldPhp)
            if (!rel.ContainsKey(branch))
                rel[branch] = new PhpWindows(pin.Version, pin.File, pin.Sha256, Cat.PhpArchivesBase + pin.File);
        return rel;
    }

    // ------------------------------------------------------------------ instalar (con permisos de administrador)
    /// <summary>
    /// Descarga y comprueba PHP, Apache, MariaDB, phpMyAdmin y los certificados de CA, y los deja en
    /// versiones\php-X.Y.Z con su configuración. Se hace en versiones\php-X.Y.Z.parcial y solo al final pasa a
    /// su nombre: si algo falla, no queda nada a medias.
    /// </summary>
    void InstallBinaries(string folder, ISalida o)
    {
        var version = folder["php-".Length..];
        var branch = Versiones.Branch(version);
        var mariaBranch = Cat.MariaDbBranch(branch) ?? throw new NexumException($"PHP {branch} no se puede instalar en Windows.");
        var final = L.VersionDir(folder);
        if (Directory.Exists(final))
            throw new NexumException($"Ya existe {final}: desinstálala antes.");
        var parts = new[] { "PHP " + version, "Apache 2.4", "MariaDB " + mariaBranch, "phpMyAdmin", "Configuración" };
        o.Parts(parts, 1);
        o.Progress(1, "consultando las versiones");
        using var d = new Descargador(Signatures);
        var php = ResolvePhp(version, d, o);
        var (apache, apacheVersion, apacheBuild) = ResolveApache(d, o);
        var (maria, mariaVersion) = ResolveMariaDb(mariaBranch, d, o);
        var pma = Cat.PmaDownload(version);
        var verified = new List<string>();

        var work = final + ".parcial";
        if (Directory.Exists(work))
            Directory.Delete(work, true);
        Directory.CreateDirectory(work);
        try
        {
            o.Progress(3, "descargando PHP " + version);
            var phpZip = d.Fetch(php, L.Downloads, o, (3, 14));
            verified.Add($"{php.Name}: {php.HowVerified}");
            o.Progress(15, "descomprimiendo PHP");
            Zip.Extract(phpZip, Path.Combine(work, "php"), "", o);

            o.Parts(parts, 2);
            o.Progress(20, "descargando Apache " + apacheVersion);
            var apacheZip = d.Fetch(apache, L.Downloads, o, (20, 29));
            verified.Add($"{apache.Name}: {apache.HowVerified}");
            o.Progress(30, "descomprimiendo Apache");
            Zip.Extract(apacheZip, Path.Combine(work, "apache"), "Apache24/", o);

            o.Parts(parts, 3);
            o.Progress(35, "descargando MariaDB " + mariaVersion);
            var mariaZip = d.Fetch(maria, L.Downloads, o, (35, 64));
            verified.Add($"{maria.Name}: {maria.HowVerified}");
            o.Progress(65, "descomprimiendo MariaDB");
            var top = Zip.TopFolder(mariaZip, "mariadb-") ?? throw new NexumException("El zip de MariaDB no tiene lo esperado");
            Zip.Extract(mariaZip, Path.Combine(work, "mariadb"), top, o);

            o.Parts(parts, 4);
            o.Progress(80, "descargando phpMyAdmin");
            var pmaZip = d.Fetch(pma, L.Downloads, o, (80, 88));
            verified.Add($"{pma.Name}: {pma.HowVerified}");
            var pmaTop = Zip.TopFolder(pmaZip, "phpMyAdmin-") ?? throw new NexumException("El zip de phpMyAdmin no tiene lo esperado");
            Zip.Extract(pmaZip, Path.Combine(work, "phpmyadmin"), pmaTop, o);

            o.Parts(parts, 5);
            o.Progress(90, "certificados de CA para PHP");
            var hasCa = false;
            try
            {
                var caSha = Fuentes.ParseShaLine(d.GetText(Cat.CaBundleShaUrl, o.Cancel));
                if (caSha != null)
                {
                    var ca = d.Fetch(new Descarga("cacert.pem", Cat.CaBundleUrl, caSha, null, null, Array.Empty<string>(),
                        "sha256 de curl.se (HTTPS, sin firma)"), L.Downloads, o);
                    var dest = Path.Combine(work, "php", "extras", "ssl");
                    Directory.CreateDirectory(dest);
                    File.Copy(ca, Path.Combine(dest, "cacert.pem"), true);
                    hasCa = true;
                    verified.Add("cacert.pem: sha256 de curl.se (HTTPS, sin firma)");
                }
            }
            catch (Exception ex) when (ex is HttpRequestException or NexumException or TaskCanceledException)
            {
                o.Line($"  Aviso: sin los certificados de CA de curl.se ({ex.Message}): PHP no podrá comprobar las webs https.");
            }

            var m = new Manifiesto
            {
                Folder = folder, Php = version, PhpBuild = Cat.BuildTag(branch), Apache = apacheVersion, ApacheBuild = apacheBuild,
                MariaDb = mariaVersion, Pma = pma.Name.Split('-')[1], InstalledAt = DateTimeOffset.Now.ToString("yyyy-MM-dd HH:mm"),
                InstalledBy = AppInfo.Version, Verified = verified,
            };
            File.WriteAllText(Path.Combine(work, "nexum-version.json"), m.ToJson());
            Directory.Move(work, final);
            WriteVersionConfig(m, o, hasCa);
            o.Progress(100, "terminado");
            o.Line($"Instalados en {final}: PHP {version}, Apache {apacheVersion}, MariaDB {mariaVersion}, phpMyAdmin {m.Pma}");
        }
        catch
        {
            try { if (Directory.Exists(work)) Directory.Delete(work, true); } catch (IOException) { }
            throw;
        }
    }

    /// <summary>Escribe la configuración de una versión (httpd.conf, php.ini, my.ini y la de phpMyAdmin).</summary>
    void WriteVersionConfig(Manifiesto m, ISalida o, bool? hasCa = null)
    {
        var folder = m.Folder;
        Directory.CreateDirectory(L.ConfDir(folder));
        Directory.CreateDirectory(L.NoFilesDir(folder));
        var phpDir = L.PhpDir(folder);
        var dll = m.PhpMajor >= 8 ? "php8apache2_4.dll" : "php7apache2_4.dll";
        if (!File.Exists(Path.Combine(phpDir, dll)))
            throw new NexumException($"PHP {m.Php} no trae {dll}: no es una compilación Thread Safe para Apache.");
        var modules = Directory.EnumerateFiles(Path.Combine(L.ApacheDir(folder), "modules"), "mod_*.so").Select(Path.GetFileName).Select(x => x!);
        File.WriteAllText(L.HttpdConf(folder), Apache.HttpdConf(L, m, P, ipv6: Ipv6Loopback(), modules, dll));
        var production = Ficheros.ReadSmallText(Path.Combine(phpDir, "php.ini-production"), 1_000_000) ?? "";
        var exts = Directory.Exists(Path.Combine(phpDir, "ext"))
            ? Directory.EnumerateFiles(Path.Combine(phpDir, "ext"), "php_*.dll").Select(Path.GetFileName).Select(x => x!)
            : Enumerable.Empty<string>();
        var ca = hasCa ?? File.Exists(Path.Combine(phpDir, "extras", "ssl", "cacert.pem"));
        File.WriteAllText(Path.Combine(phpDir, "php.ini"), PhpMariaDb.PhpIni(L, m, production, exts, P, ca));
        File.WriteAllText(L.MyIni(folder), PhpMariaDb.MyIni(L, m, P));
        File.WriteAllText(Path.Combine(L.PmaDir(folder), "config.inc.php"), PhpMariaDb.PmaConfig(L, m, P));
        o.Line($"  Configuración de {folder}: {L.ConfDir(folder)}");
    }

    /// <summary>¿Tiene el equipo la dirección ::1? (sin ella, Apache no arrancaría con Listen [::1]:80)</summary>
    static bool Ipv6Loopback()
    {
        try
        {
            if (!System.Net.Sockets.Socket.OSSupportsIPv6)
                return false;
            using var s = new System.Net.Sockets.Socket(System.Net.Sockets.AddressFamily.InterNetworkV6, System.Net.Sockets.SocketType.Stream,
                System.Net.Sockets.ProtocolType.Tcp);
            s.Bind(new System.Net.IPEndPoint(System.Net.IPAddress.IPv6Loopback, 0));
            return true;
        }
        catch (System.Net.Sockets.SocketException)
        {
            return false;
        }
    }

    /// <summary>Borra versiones\php-X (con permisos de administrador), sin seguir enlaces.</summary>
    void RemoveBinaries(string folder, ISalida o)
    {
        var dir = L.VersionDir(folder);
        if (!Directory.Exists(dir))
        {
            o.Line($"{dir} ya no existe.");
            return;
        }
        if (Ficheros.IsLink(dir))
            throw new NexumException($"{dir} es un enlace: no se borra");
        if (VersionProcesses(folder).Count > 0)
            throw new NexumException($"{folder} sigue en marcha: párala antes.");
        DeleteTree(dir);
        o.Line($"{dir} borrada.");
    }

    /// <summary>Borra una carpeta entera sin seguir enlaces (un enlace se quita, no lo que hay detrás).</summary>
    public static void DeleteTree(string dir)
    {
        foreach (var e in Directory.EnumerateFileSystemEntries(dir))
        {
            if (Ficheros.IsLink(e))
            {
                if (Directory.Exists(e)) Directory.Delete(e);
                else File.Delete(e);
            }
            else if (Directory.Exists(e))
                DeleteTree(e);
            else
            {
                File.SetAttributes(e, FileAttributes.Normal);
                File.Delete(e);
            }
        }
        Directory.Delete(dir);
    }

    // ------------------------------------------------------------------ instalar (tu usuario)
    /// <summary>Carpeta y versión completa de lo que se pide: 8.4 (el último parche) u 8.4.26.</summary>
    public (string Folder, string Version) ResolveRequest(string request, Descargador d, CancellationToken ct)
    {
        request = request.Trim();
        if (request.StartsWith("php-", StringComparison.Ordinal)) request = request[4..];
        if (Validacion.IsPhpVersion(request))
            return ("php-" + request, request);
        if (System.Text.RegularExpressions.Regex.IsMatch(request, @"^\d+\.\d+$"))
        {
            if (Cat.MariaDbBranch(request) == null)
                throw new NexumException($"PHP {request} no se ofrece en Windows (de la 7.1 a la 8.5).");
            var latest = LatestPhp(d, ct);
            if (!latest.TryGetValue(request, out var w))
                throw new NexumException($"windows.php.net no tiene PHP {request} para Windows x64.");
            return ("php-" + w.Version, w.Version);
        }
        throw new NexumException($"Versión no válida: {request} (por ejemplo 8.4 u 8.4.27)");
    }

    /// <summary>Instala una versión: los programas (con permisos de administrador) y sus BBDD vacías (con tu usuario).</summary>
    public string Install(string request, ISalida o)
    {
        RequirePrepared();
        using var d = new Descargador(Signatures);
        var (folder, version) = ResolveRequest(request, d, o.Cancel);
        if (Find(folder) != null)
            throw new NexumException($"{folder} ya está instalada.");
        o.Line($"Instalando PHP {version} en {L.VersionDir(folder)}");
        Elevated("instalar", folder, o, "Instalar los programas de " + folder);
        InitData(folder, o);
        o.Line($"{folder} instalada. Actívala para usarla (NexumDevStack.exe usar {folder}).");
        CheckVcRuntime(o, warnOnly: true);
        return folder;
    }

    /// <summary>
    /// Crea las BBDD vacías de una versión (datos\php-X): solo las del sistema de MariaDB, root sin contraseña
    /// (como XAMPP) y la base phpmyadmin con su usuario pma. Con tu usuario (MariaDB corre con él).
    /// </summary>
    public void InitData(string folder, ISalida o)
    {
        var m = Find(folder) ?? throw new NexumException($"No existe {folder}");
        var data = L.DataDir(folder);
        if (Directory.Exists(data) && Directory.EnumerateFileSystemEntries(data).Any())
        {
            o.Line($"Ya existen sus BBDD ({data}): no se crean otras.");
            return;
        }
        RequireNotElevated();
        EnsureRuntimeDirs(folder);
        o.Line("Creando sus BBDD propias y vacías...");
        var bin = Path.Combine(L.MariaDbDir(folder), "bin");
        var install = File.Exists(Path.Combine(bin, "mariadb-install-db.exe")) ? Path.Combine(bin, "mariadb-install-db.exe")
            : Path.Combine(bin, "mysql_install_db.exe");
        var r = Pf.Processes.Run(install, new[] { "--datadir=" + data }, TimeSpan.FromMinutes(5), bin);
        if (r.ExitCode != 0)
            throw new NexumException("No se han podido crear sus BBDD:\n" + r.Output.Trim());
        // (el my.ini que deja mariadb-install-db en la carpeta de datos no se usa: va el de conf\)
        try { File.Delete(Path.Combine(data, "my.ini")); } catch (IOException) { }
        WithServer(folder, o, client =>
        {
            client.Run("DROP USER IF EXISTS ''@'localhost'; DROP USER IF EXISTS ''@'%'; DELETE FROM mysql.db WHERE Db IN ('test', 'test\\_%'); FLUSH PRIVILEGES");
            var sql = Ficheros.ReadSmallText(Path.Combine(L.PmaDir(folder), "sql", "create_tables.sql"), 1_000_000);
            var ok = sql != null && client.Run("", stdin: sql).ExitCode == 0 && client.Run(PhpMariaDb.PmaUserSql).ExitCode == 0;
            if (!ok)
                o.Line("  Aviso: no se pudo crear la base 'phpmyadmin'; phpMyAdmin funcionará pero avisará de que falta su almacenamiento");
        });
        o.Line("BBDD creadas.");
    }

    public void RequirePrepared()
    {
        if (!L.IsPrepared)
            throw new NexumException($"Nexum Dev Stack no está preparado en este equipo ({L.Root}). Ábrelo y pulsa Preparar, o usa: NexumDevStack.exe preparar");
    }

    /// <summary>Prepara C:\NexumDevStack (con permisos de administrador) y lo compartido (con tu usuario).</summary>
    public void Prepare(ISalida o)
    {
        Elevated("preparar", Pf.CurrentUserSid, o, "Preparar " + L.Root);
        EnsureShared(o);
        o.Line($"{L.Root} está listo. Instala la primera versión de PHP (Versiones de PHP, Instalar versión…).");
    }

    // ------------------------------------------------------------------ desinstalar
    /// <summary>Desinstala una versión (no la activa). Con copia, antes guarda sus BBDD en nexum-copias.</summary>
    public void Uninstall(string version, bool backup, ISalida o)
    {
        var m = Require(version);
        var blocker = RemoveBlocker(m.Folder);
        if (blocker.Length > 0)
            throw new NexumException(blocker);
        var dbs = Databases(m.Folder);
        if (backup && dbs.Count > 0)
        {
            o.Line($"Guardando una copia de sus {Texto.Plural(dbs.Count, "BBDD", "BBDD")} en {L.CopiesDir}...");
            Ficheros.EnsureDir(L.CopiesDir);
            foreach (var db in dbs)
                ExportDatabase(db.Name, Path.Combine(L.CopiesDir, $"{m.Folder}-{db.Name}-{Ficheros.Stamp()}.sql.gz"), m.Folder, o);
        }
        StopApache(m.Folder, o);
        StopMariaDb(m.Folder, o);
        Elevated("desinstalar", m.Folder, o, "Borrar los programas de " + m.Folder);
        foreach (var d in new[] { L.DataDir(m.Folder), L.LogDir(m.Folder), L.TmpDir(m.Folder) })
            if (Directory.Exists(d) && !Ficheros.IsLink(d))
            {
                try { DeleteTree(d); }
                catch (IOException ex) { o.Line($"Aviso: no se ha podido borrar {d} ({ex.Message})"); }
            }
        o.Line($"{m.Folder} desinstalada{(backup && dbs.Count > 0 ? $" (copia de sus BBDD en {L.CopiesDir})" : "")}.");
    }

    // ------------------------------------------------------------------ actualizar a otro parche
    /// <summary>
    /// Pasa una versión a otro parche: instala PHP <paramref name="target"/> al lado, le copia las BBDD con sus
    /// vínculos y, si era la activa, la activa. La de antes no se toca.
    /// </summary>
    public void UpgradeTo(string version, string target, ISalida o)
    {
        var src = Require(version);
        if (!Validacion.IsPhpVersion(target))
            throw new NexumException($"Versión de PHP no válida: {target}");
        var dstFolder = "php-" + target;
        var wasActive = Active == src.Folder;
        if (Find(dstFolder) == null)
            Install(target, o);
        else
            o.Line($"PHP {target} ya está en {dstFolder}: se le copian las BBDD.");
        var dbs = Databases(src.Folder);
        var have = Databases(dstFolder).Select(x => x.Name).ToHashSet();
        foreach (var db in dbs)
        {
            o.Cancel.ThrowIfCancellationRequested();
            if (have.Contains(db.Name))
            {
                o.Line($"{dstFolder} ya tiene {db.Name}: no se toca.");
                continue;
            }
            var link = Links.LinkOf(db.Name, src.Folder);
            CopyDatabase(db.Name, src.Folder, dstFolder, null, link ?? null, replace: false, o);
        }
        if (wasActive)
            Use(dstFolder, o);
        o.Line($"Listo: {dstFolder} tiene las BBDD de {src.Folder}. Cuando compruebes que todo va bien, desinstala {src.Folder}.");
    }
}
