using NexumDevStack.Core.BaseDatos;
using NexumDevStack.Core.Configuracion;
using NexumDevStack.Core.Proyectos;
using NexumDevStack.Core.Tareas;
using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.Pila;

/// <summary>Cargar y desmontar proyectos (web.local), y la configuración de WordPress y PrestaShop.</summary>
public sealed partial class Motor
{
    /// <summary>Carpeta de proyecto válida: existe en htdocs, no es un enlace y su nombre es aceptable.</summary>
    public void ValidProject(string folder)
    {
        var path = Path.Combine(L.Htdocs, folder ?? "");
        if (string.IsNullOrEmpty(folder) || folder.Contains('/') || folder.Contains('\\') || !Directory.Exists(path) || Ficheros.IsLink(path))
            throw new NexumException($"No existe el proyecto {path}");
        if (!Validacion.IsProjectFolder(folder))
            throw new NexumException($"El nombre de la carpeta {folder} lleva caracteres que no se admiten (solo letras sin acentos, números, espacios, punto, _ y -). Cámbiale el nombre y vuelve a intentarlo.");
    }

    public string ReadVhosts() => Ficheros.ReadSmallText(L.VhostsFile) ?? Vhosts.InitialFile(L);

    public List<VhostInfo> VhostList() => Vhosts.Parse(ReadVhosts());

    /// <summary>Carpeta del proyecto cargado en web.local ("" ninguno, null si no hay vhost de proyectos).</summary>
    public string? LoadedProject() => Vhosts.ProjectFolder(VhostList());

    string ServerAdmin() => "admin@localhost";

    /// <summary>
    /// cargar-proyecto: apunta web.local a htdocs\&lt;carpeta&gt; (y monta antes esa versión). Tienda
    /// PrestaShop o proyecto con dominio propio: crea lo que falte de su vhost y su certificado y falsea su
    /// dominio en hosts; los demás dominios dejan de estar falseados. Todo o nada: si algo falla o se cancela,
    /// queda como estaba (el vhost de los proyectos y la versión activa).
    /// </summary>
    public void LoadProject(string folder, string? version, string? db, ISalida o)
    {
        folder = folder.TrimEnd('/', '\\');
        ValidProject(folder);
        RequirePrepared();
        if (folder == Disposicion.ProjectVhost)
            throw new NexumException($"{folder} es el propio vhost, no un proyecto");
        string? target = version != null ? Require(version).Folder : Active;
        if (target == null)
        {
            var installed = Installed();
            target = installed.Count == 1 ? installed[0].Folder
                : throw new NexumException("No hay ninguna versión activa: elige con qué versión cargar el proyecto.");
        }
        if (db != null && !Validacion.IsDbName(db))
            db = null;

        EnsureShared(o);
        var vhostsBefore = ReadVhosts();
        var activeBefore = Active;
        var runningBefore = ActiveRunning();
        var hostsPath = Pf.HostsFilePath;
        string? domain = null;
        var createdLink = false;
        try
        {
            var text = vhostsBefore;
            if (!Vhosts.HasProjectVhost(Vhosts.Parse(text)))
            {
                o.Line($"Creando el vhost {Disposicion.ProjectVhost} (http y https) en {L.VhostsFile}...");
                MakeCert(Disposicion.ProjectVhost, "www." + Disposicion.ProjectVhost,
                    Path.Combine(L.SslDir, Disposicion.ProjectVhost + ".crt"), Path.Combine(L.SslDir, Disposicion.ProjectVhost + ".key"));
                text = text.TrimEnd('\r', '\n') + "\n" + Vhosts.ProjectVhostBlock(L, P, ServerAdmin());
                createdLink = true;
            }
            text = Vhosts.SetProjectRoot(text, L, folder);
            Ficheros.WriteAtomic(L.VhostsFile, text);
            o.Cancel.ThrowIfCancellationRequested();

            if (target != Active)
            {
                o.Line($"Activando {target}...");
                Use(target, o);
            }
            else if (!ActiveRunning())
            {
                o.Line($"Arrancando {target}...");
                Start(o);
            }
            else
            {
                // PHP recuerda la carpeta de cada script: recarga suave para que no siga sirviendo el anterior
                o.Line("Recargando Apache para que PHP no siga sirviendo el proyecto anterior...");
                ReloadApache(target, o);
            }
            o.Cancel.ThrowIfCancellationRequested();

            if (db != null)
                Links.Remember(db, folder, target);
            domain = ProjectDomain(folder, db, target, o);
            o.Cancel.ThrowIfCancellationRequested();

            // hosts, lo último (pide permiso de administrador): el dominio de la tienda falseado, el resto no
            var hosts = Ficheros.ReadSmallText(hostsPath, 4_000_000) ?? "";
            var (newHosts, changes) = Hosts.Fake(hosts, VhostList(), Hosts.Modo.Cargar, domain == null ? Array.Empty<string>() : new[] { domain },
                LocalOff());
            var (fixedHosts, fixChanges) = Hosts.FixLink(newHosts, Disposicion.ProjectVhost);
            if (Hosts.AddressOf(newHosts, Disposicion.ProjectVhost) == "127.0.0.1")
                fixedHosts = newHosts;
            else
                changes.AddRange(fixChanges);
            if (fixedHosts != hosts)
            {
                foreach (var c in changes) o.Line(c);
                ApplyHosts(fixedHosts, o, "Cambiar hosts");
            }
        }
        catch (Exception ex)
        {
            o.Line(ex is OperationCanceledException ? "Cancelado: se deja todo como estaba." : "No se ha podido cargar: se deja todo como estaba.");
            try
            {
                Ficheros.WriteAtomic(L.VhostsFile, vhostsBefore);
                var undo = new SalidaTexto(TextWriter.Null, false, CancellationToken.None);
                if (Active != activeBefore)
                {
                    if (Active != null)
                    {
                        StopApache(Active, undo);
                        StopMariaDb(Active, undo);
                    }
                    SetActive(activeBefore);
                    if (activeBefore != null && runningBefore)
                    {
                        StartMariaDb(activeBefore, undo);
                        StartApache(activeBefore, undo);
                    }
                }
                else if (activeBefore != null && ApacheRunning(activeBefore))
                    ReloadApache(activeBefore, undo);
                o.Line($"{Disposicion.ProjectVhost} vuelve a apuntar a {(Vhosts.ProjectFolder(Vhosts.Parse(vhostsBefore)) is { Length: > 0 } f ? f : "lo de antes")}" +
                       (activeBefore != null ? $" ({activeBefore})" : ""));
            }
            catch (Exception undoError)
            {
                o.Line("Aviso: no se ha podido dejar todo como estaba: " + undoError.Message);
            }
            if (ex is OperationCanceledException)
                throw new NexumException("Cancelado.", 130);
            throw;
        }

        // Certificados: el navegador acepta el de web.local y el de la tienda falseada (Windows pregunta)
        if (createdLink)
            TrustDomain(Disposicion.ProjectVhost, o);
        if (domain != null)
            TrustDomain(domain, o);
        UntrustStale(o);
        o.Line($"Proyecto cargado: {Disposicion.ProjectVhost} -> {folder} ({target})");
    }

    /// <summary>desmontar-proyecto: web.local enseña una página vacía; los dominios falseados dejan de estarlo.</summary>
    public void UnloadProject(ISalida o)
    {
        var text = ReadVhosts();
        var current = Vhosts.ProjectFolder(Vhosts.Parse(text));
        if (current == null)
            throw new NexumException($"No hay ningún vhost de proyectos ({Disposicion.ProjectVhost}): no hay nada que desmontar");
        if (current.Length == 0)
        {
            o.Line($"No hay ningún proyecto cargado en {Disposicion.ProjectVhost}");
            return;
        }
        EnsureShared(o);
        Ficheros.WriteAtomic(L.VhostsFile, Vhosts.SetProjectRoot(text, L, null));
        var hosts = Ficheros.ReadSmallText(Pf.HostsFilePath, 4_000_000) ?? "";
        var (newHosts, changes) = Hosts.Fake(hosts, VhostList(), Hosts.Modo.Cargar, Array.Empty<string>(), LocalOff());
        if (newHosts != hosts)
        {
            foreach (var c in changes) o.Line(c);
            try
            {
                ApplyHosts(newHosts, o, "Cambiar hosts");
            }
            catch (NexumException ex)
            {
                o.Line("Aviso: " + ex.Message);
            }
        }
        if (Active is { } a && ApacheRunning(a))
        {
            o.Line("Recargando Apache para que PHP deje de servir el proyecto...");
            ReloadApache(a, o);
        }
        UntrustStale(o);
        o.Line($"Proyecto desmontado: {Disposicion.ProjectVhost} ya no apunta a ningún proyecto");
    }

    // ------------------------------------------------------------------ dominio del proyecto
    /// <summary>
    /// Lo que falta al cargar un proyecto (como load_project_domain de Linux): si es PrestaShop, su
    /// parameters.php, su base y su caché, y su dominio con vhost y certificado; si es WordPress, su
    /// wp-config.php. Devuelve el dominio que hay que falsear (o null).
    /// </summary>
    string? ProjectDomain(string folder, string? db, string version, ISalida o)
    {
        var path = Path.Combine(L.Htdocs, folder);
        ClienteMariaDb? c = MariaDbRunning(version) ? Client(version) : null;
        if (Escaner.IsPrestaShop(L.Htdocs, folder) && c != null)
        {
            var newParams = PsParameters(c, folder, db, version, o);
            newParams |= PsSetDb(c, folder, db ?? Links.SavedDb(folder, version), o);
            PsFirstLoad(folder, newParams, o);
        }
        else if (Escaner.IsWordPress(L.Htdocs, folder) && c != null)
            WpConfig(c, folder, db, version, o);

        string? domain;
        if (PrestaShop.ReadConfig(path) != null)
        {
            domain = c != null ? PsDomain(c, folder) : null;
            domain ??= VhostList().FirstOrDefault(v => v.Folder == folder && v.Name != Disposicion.ProjectVhost)?.Name;
            if (domain == null)
            {
                o.Line($"Aviso: {folder} es una tienda PrestaShop, pero no se ha podido saber su dominio: su base no se puede leer");
                o.Line("(¿MariaDB parado o root con contraseña?) y ningún vhost apunta a la carpeta. Crea su vhost (Editar vhosts) y vuelve a cargar el proyecto.");
                return null;
            }
            if (!VhostPointsTo(domain, folder) && !Escaner.DomainFitsFolder(domain, folder))
            {
                // El dominio viene de la base (shop_url): un volcado manipulado podría llevar uno real (de un
                // banco, de github…) para que este equipo lo mande aquí. Sin vhost suyo, solo si se parece
                o.Line($"Aviso: el dominio de la base ({domain}) no se parece al nombre de la carpeta {folder}: no se le crea vhost ni se falsea.");
                o.Line("Si es el correcto, créalo en la pestaña Dominios y hosts (Nuevo proyecto con dominio falseado) o en los vhosts.");
                return null;
            }
            o.Line($"Tienda PrestaShop: dominio {domain}");
        }
        else if (CustomDomains.Of(folder) is { } custom)
        {
            if (!VhostPointsTo(custom, folder) && !Escaner.DomainFitsFolder(custom, folder))
            {
                o.Line($"Aviso: el dominio guardado para {folder} ({custom}) no tiene vhost ni se parece al nombre de la carpeta: no se crea ni se falsea.");
                return null;
            }
            domain = custom;
            o.Line($"Proyecto con dominio propio: {domain}");
        }
        else
            return null;
        if (DomainVhost(folder, domain, o))
            ReloadApache(version, o);
        return domain;
    }

    bool VhostPointsTo(string domain, string folder) => VhostList().Any(v => v.Name == domain && v.Folder == folder);

    /// <summary>
    /// Comprueba que el dominio tiene vhost http y https apuntando a la carpeta y certificado; lo que falte se
    /// crea al final de httpd-vhosts.conf (con copia del anterior en nexum-copias). true si ha cambiado algo.
    /// </summary>
    public bool DomainVhost(string folder, string domain, ISalida o)
    {
        if (!Validacion.IsDomain(domain))
            throw new NexumException($"Dominio no válido: {domain}");
        var info = VhostList();
        var http = info.FirstOrDefault(v => v.Port == P.Http && v.Name == domain);
        var https = info.FirstOrDefault(v => v.Port == P.Https && v.Name == domain);
        var other = new[] { http, https }.FirstOrDefault(v => v != null && v.Folder != folder);
        if (other != null)
            o.Line($"Aviso: el vhost de {domain} apunta a {Path.Combine(L.Htdocs, other.Folder)}, no a {folder}. No se cambia: revísalo en Editar vhosts si no es lo que quieres.");
        var changed = false;
        string crt, key;
        if (https != null)
        {
            crt = https.Crt;
            key = https.Key;
        }
        else
        {
            crt = Path.Combine(L.SslDir, domain + "-selfsigned.crt");
            key = Path.Combine(L.SslDir, domain + "-selfsigned.key");
        }
        if (crt.Length > 0 && key.Length > 0 && !File.Exists(crt))
        {
            o.Line($"Creando el certificado autofirmado de {domain} ({crt})...");
            MakeCert(domain, Vhosts.DomainAlias(domain), crt, key);
            changed = true;
        }
        if (http == null || https == null)
        {
            var block = Vhosts.DomainBlocks(L, P, folder, domain, ServerAdmin(), http == null, https == null, crt, key);
            o.Line($"Añadiendo el vhost de {domain} ({(http == null ? "http " : "")}{(https == null ? "https" : "")}) a {L.VhostsFile}...");
            BackupVhosts();
            Ficheros.WriteAtomic(L.VhostsFile, ReadVhosts().TrimEnd('\r', '\n') + "\n" + block);
            changed = true;
        }
        return changed;
    }

    void BackupVhosts()
    {
        if (!File.Exists(L.VhostsFile)) return;
        Ficheros.EnsureDir(L.CopiesDir);
        File.Copy(L.VhostsFile, Path.Combine(L.CopiesDir, "httpd-vhosts.conf-" + Ficheros.Stamp()), true);
    }

    /// <summary>Certificado autofirmado, solo en la carpeta de certificados (las rutas de un vhost las puede escribir cualquiera).</summary>
    void MakeCert(string domain, string? alias, string crt, string key)
    {
        var ssl = Path.GetFullPath(L.SslDir);
        bool Inside(string p) => string.Equals(Path.GetDirectoryName(Path.GetFullPath(p)), ssl, StringComparison.OrdinalIgnoreCase);
        if (!Inside(crt) || !Inside(key) || !Certificados.IsSafeFileName(Path.GetFileName(crt)) || !Certificados.IsSafeFileName(Path.GetFileName(key)))
            throw new NexumException($"El certificado de {domain} ({crt}) no está en la carpeta de certificados ({ssl}): no se crea.");
        Certificados.Write(ssl, Path.GetFileName(crt), Path.GetFileName(key), Certificados.Create(domain, alias));
    }

    /// <summary>Dominio de una tienda: el de su base (shop_url, tienda principal), si se puede leer.</summary>
    string? PsDomain(ClienteMariaDb c, string folder)
    {
        var cfg = PrestaShop.ReadConfig(Path.Combine(L.Htdocs, folder));
        if (cfg == null || !Validacion.IsDbName(cfg.Name) || (cfg.Prefix.Length > 0 && !Sql.IsIdent(cfg.Prefix)))
            return null;
        if (c.Scalar(Sql.IsBaseTable(cfg.Name, cfg.Prefix + "shop_url")) != "1")
            return null;
        var d = c.Scalar(Sql.PsDomain(cfg.Name, cfg.Prefix), cfg.Name)?.Split(':')[0].ToLowerInvariant();
        return d != null && Validacion.IsDomain(d) ? d : null;
    }

    // ------------------------------------------------------------------ PrestaShop
    /// <summary>Base de una tienda cuya configuración no la dice: la indicada, la vinculada o la única ps_&lt;final de la carpeta&gt;.</summary>
    string? PsGuessDb(ClienteMariaDb c, string folder, string? db, string version)
    {
        db ??= Links.SavedDb(folder, version);
        if (db == null)
        {
            var tail = folder.Split('-', '.').Last().ToLowerInvariant();
            if (System.Text.RegularExpressions.Regex.IsMatch(tail, "^[a-z0-9_]+$"))
            {
                var rows = c.Rows($"SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE LOWER(SCHEMA_NAME) IN ('ps_{tail}', '{tail}')");
                if (rows.Count == 1) db = rows[0][0];
            }
        }
        return db != null && Validacion.IsDbName(db) ? db : null;
    }

    /// <summary>Tienda 1.7 o posterior sin base en app/config/parameters.php: lo crea con la base cargada. true si es nuevo.</summary>
    bool PsParameters(ClienteMariaDb c, string folder, string? db, string version, ISalida o)
    {
        var dir = Path.Combine(L.Htdocs, folder);
        var file = Path.Combine(dir, "app", "config", "parameters.php");
        if (!File.Exists(Path.Combine(dir, "app", "config", "set_parameters.php")) && !Directory.Exists(Path.Combine(dir, "src", "PrestaShopBundle")))
            return false;
        var current = Ficheros.ReadSmallText(file);
        if (current != null && PrestaShop.HasDatabase(current))
            return false;
        db = PsGuessDb(c, folder, db, version);
        if (db == null || !Exists(c, db))
        {
            o.Line($"Aviso: {folder} no tiene la base de datos en app/config/parameters.php y no se sabe cuál es{(db != null ? $" ({db} no está en la versión activa)" : "")}.");
            o.Line("Cárgala desde Bases de datos (Cargar proyecto) o pon database_name a mano en ese fichero.");
            return false;
        }
        var prefix = c.Scalar(Sql.PsPrefix(db, ""));
        if (string.IsNullOrEmpty(prefix) || !Sql.IsIdent(prefix))
        {
            o.Line($"Aviso: la base {db} no tiene la tabla shop_url de PrestaShop: no se crea parameters.php");
            return false;
        }
        if (!Ficheros.InsideWithoutLinks(dir, file))
        {
            o.Line($"Aviso: app/config/parameters.php de {folder} es un enlace o está fuera de la carpeta: no se toca");
            return false;
        }
        var saved = Path.Combine(L.PsParamsDir, folder + ".parameters.php");
        var savedText = Ficheros.ReadSmallText(saved);
        if (savedText != null && savedText.Contains($"'database_name' => '{db}'"))
        {
            o.Line($"app/config/parameters.php no tiene la base: se pone la copia guardada ({db})");
            File.WriteAllText(file, savedText);
            return true;
        }
        o.Line($"Creando app/config/parameters.php con la base {db} (prefijo {prefix}) y claves nuevas...");
        if (current != null)
            File.Copy(file, Path.Combine(Ficheros.EnsureDir(L.CopiesDir), $"parameters.php-{folder}-{Ficheros.Stamp()}"), true);
        var text = PrestaShop.NewParameters(db, prefix);
        File.WriteAllText(file, text);
        Ficheros.WriteAtomic(saved, text);
        return true;
    }

    /// <summary>
    /// La configuración de la tienda pasa a la base de la carpeta (base nueva o código de producción pegado
    /// encima) y, si sus datos no entran en el MariaDB local, a root y 127.0.0.1. true si ha cambiado.
    /// </summary>
    bool PsSetDb(ClienteMariaDb c, string folder, string? db, ISalida o)
    {
        if (db == null || !Validacion.IsDbName(db)) return false;
        var dir = Path.Combine(L.Htdocs, folder);
        var cfg = PrestaShop.ReadConfig(dir);
        if (cfg == null) return false;
        var file = Path.Combine(dir, cfg.Rel.Replace('/', Path.DirectorySeparatorChar));
        if (!Ficheros.InsideWithoutLinks(dir, file))
        {
            o.Line($"Aviso: {cfg.Rel} de {folder} es un enlace o está fuera de la carpeta: no se toca");
            return false;
        }
        if (!Exists(c, db))
        {
            o.Line($"Aviso: la base {db} de {folder} no está en la versión activa: no se toca {cfg.Rel}");
            return false;
        }
        var newPrefix = c.Scalar(Sql.PsPrefix(db, Sql.IsIdent(cfg.Prefix) ? cfg.Prefix : ""));
        if (string.IsNullOrEmpty(newPrefix) || !Sql.IsIdent(newPrefix))
        {
            o.Line($"Aviso: la base {db} no tiene la tabla shop_url de PrestaShop: no se toca {cfg.Rel}");
            return false;
        }
        var loginOk = LoginOk(c, cfg.User, cfg.Password, cfg.Host, db, newPrefix + "shop_url");
        if (cfg.Name == db && cfg.Prefix == newPrefix && loginOk)
            return false;
        o.Line(cfg.Name != db
            ? $"PrestaShop: {cfg.Rel} de {folder} usa la base {cfg.Name}{(cfg.Host.Length > 0 ? " en " + cfg.Host : "")}; la de la carpeta es {db}"
            : $"PrestaShop: {cfg.Rel} de {folder} no entra en el MariaDB local{(cfg.Host.Length > 0 ? $" (servidor {cfg.Host}, usuario {cfg.User})" : "")}");
        o.Line($"Se cambia a la base {db}");
        if (!loginOk) o.Line("  Usuario root y servidor 127.0.0.1 (los de MariaDB local)");
        if (newPrefix != cfg.Prefix) o.Line($"  Prefijo de las tablas: {newPrefix} (era {(cfg.Prefix.Length > 0 ? cfg.Prefix : "ninguno")})");
        var text = File.ReadAllText(file);
        File.Copy(file, Path.Combine(Ficheros.EnsureDir(L.CopiesDir), $"{Path.GetFileName(cfg.Rel)}-{folder}-{Ficheros.Stamp()}"), true);
        o.Line($"  El anterior queda en {L.CopiesDir}");
        var neu = PrestaShop.SetDb(text, cfg.Rel, db, newPrefix, !loginOk, RootPassword ?? "");
        File.WriteAllText(file, neu);
        if (cfg.Rel.EndsWith("parameters.php", StringComparison.Ordinal))
            Ficheros.WriteAtomic(Path.Combine(L.PsParamsDir, folder + ".parameters.php"), neu);
        o.Line($"{cfg.Rel} de {folder} listo: base {db}");
        return true;
    }

    /// <summary>¿Entra la web en la base con estos datos? Solo si el servidor es este equipo.</summary>
    bool LoginOk(ClienteMariaDb c, string user, string pass, string host, string db, string table)
    {
        if (user.Length == 0 || !WordPress.IsLocalHost(host) || !Validacion.IsDbName(db) || !Sql.IsIdent(table))
            return false;
        // Sin leer la tabla: podría ser una vista del volcado. Basta con que la vea como tabla de verdad
        var r = c.Run(Sql.IsBaseTable(db, table), user: user, password: pass, timeout: TimeSpan.FromSeconds(15));
        return r.ExitCode == 0 && r.Output.Trim() == "1";
    }

    /// <summary>Primera carga de una tienda en este equipo (o parameters.php nuevo): vacía su caché y la apunta.</summary>
    void PsFirstLoad(string folder, bool newParams, ISalida o)
    {
        var loaded = (Ficheros.ReadSmallText(L.PsLoadedFile) ?? "").Replace("\r\n", "\n").Split('\n');
        if (!newParams && loaded.Contains(folder))
            return;
        if (!loaded.Contains(folder))
            o.Line($"Primera carga de la tienda {folder} en este equipo");
        try { ClearCache(folder, o); }
        catch (NexumException ex) { o.Line("Aviso: " + ex.Message); return; }
        if (!loaded.Contains(folder))
            Ficheros.WriteAtomic(L.PsLoadedFile, string.Join("\n", loaded.Where(x => x.Length > 0).Append(folder)) + "\n");
    }

    /// <summary>vaciar-cache &lt;carpeta&gt;: borra el contenido de var/cache de una tienda, sin seguir enlaces.</summary>
    public void ClearCache(string folder, ISalida o)
    {
        ValidProject(folder);
        var dir = Path.Combine(L.Htdocs, folder);
        var cache = Path.Combine(dir, "var", "cache");
        if (!Directory.Exists(cache))
        {
            o.Line($"{folder} no tiene la carpeta var/cache: no hay caché que vaciar");
            return;
        }
        if (!Ficheros.InsideWithoutLinks(dir, cache))
            throw new NexumException($"var/cache de {folder} es un enlace a otra carpeta: no se vacía");
        o.Line($"Vaciando la caché de {folder} (var/cache)...");
        foreach (var e in Directory.EnumerateFileSystemEntries(cache))
        {
            try
            {
                if (Ficheros.IsLink(e)) { if (Directory.Exists(e)) Directory.Delete(e); else File.Delete(e); }
                else if (Directory.Exists(e)) DeleteTree(e);
                else { File.SetAttributes(e, FileAttributes.Normal); File.Delete(e); }
            }
            catch (IOException ex)
            {
                o.Line($"  No se ha podido borrar {e}: {ex.Message}");
            }
        }
        o.Line($"Caché de {folder} vaciada");
    }

    /// <summary>vaciar-cache --bd &lt;base&gt;: la carpeta de la tienda de una base (la vinculada o la única que la usa).</summary>
    public void ClearCacheDb(string db, ISalida o)
    {
        if (!Validacion.IsDbName(db)) throw new NexumException($"Base de datos no válida: {db}");
        var folder = Active != null ? Links.LinkOf(db, Active) : null;
        if (string.IsNullOrEmpty(folder) || !Directory.Exists(Path.Combine(L.Htdocs, folder)))
        {
            var users = Escaner.Scan(L.Htdocs).Where(x => x.Db == db).Select(x => x.Name).ToList();
            folder = users.Count == 1 ? users[0] : Escaner.NameMatch(L.Htdocs, db, Escaner.Folders(L.Htdocs));
        }
        if (string.IsNullOrEmpty(folder))
            throw new NexumException($"No se sabe cuál es la carpeta de la tienda de {db}. Cárgala una vez con Cargar proyecto (se recuerda) o usa: NexumDevStack.exe vaciar-cache <carpeta>");
        ClearCache(folder, o);
    }

    // ------------------------------------------------------------------ WordPress
    /// <summary>URL con la que se ve un proyecto: su dominio propio o el vhost de los proyectos (https si tiene certificado).</summary>
    public string LocalUrl(string folder)
    {
        if (CustomDomains.Of(folder) is { } d)
            return "https://" + d;
        var link = VhostList().Where(v => v.Name == Disposicion.ProjectVhost).ToList();
        var https = link.FirstOrDefault(v => v.Crt.Length > 0);
        if (https != null) return "https://" + https.Name + (https.Port == 443 ? "" : ":" + https.Port);
        var http = link.FirstOrDefault();
        if (http != null) return "http://" + http.Name + (http.Port == 80 ? "" : ":" + http.Port);
        return "https://" + Disposicion.ProjectVhost;
    }

    /// <summary>
    /// wp-config &lt;carpeta&gt; [base]: comprueba que wp-config.php usa la base de la carpeta y entra en el
    /// MariaDB local; si no (código de producción pegado encima), lo rehace con la plantilla de este equipo.
    /// </summary>
    void WpConfig(ClienteMariaDb c, string folder, string? db, string version, ISalida o)
    {
        var dir = Path.Combine(L.Htdocs, folder);
        var file = Path.Combine(dir, "wp-config.php");
        var sample = Path.Combine(dir, "wp-config-sample.php");
        if (!Ficheros.InsideWithoutLinks(dir, file) || (File.Exists(sample) && !Ficheros.InsideWithoutLinks(dir, sample)))
        {
            o.Line($"Aviso: wp-config.php de {folder} es un enlace o está fuera de la carpeta: no se toca");
            return;
        }
        var saved = Path.Combine(L.WpConfigDir, folder + ".wp-config.php");
        var current = Ficheros.ReadSmallText(file);
        var w = current != null ? WordPress.Read(current) : new WpDatos("", "", "", "", "");
        db ??= Links.SavedDb(folder, version);
        if (db == null && Validacion.IsDbName(w.Name) && Exists(c, w.Name))
            db = w.Name;
        if (db == null)
        {
            o.Line($"Aviso: el wp-config.php de {folder} usa la base {(w.Name.Length > 0 ? w.Name : "(ninguna)")}, que no está en la versión activa, y la carpeta");
            o.Line("no tiene una base asociada. Cárgala desde Bases de datos (Cargar proyecto) o al subirla elige el proyecto, y se corrige sola.");
            return;
        }
        if (!Validacion.IsDbName(db) || !Exists(c, db))
        {
            o.Line($"Aviso: la base {db} de {folder} no está en la versión activa: no se toca su wp-config.php");
            return;
        }
        var prefixes = c.Rows(Sql.WpPrefixes(db)).Select(r => r[0]).Where(p => p.Length == 0 || Sql.IsIdent(p)).ToList();
        if (prefixes.Count == 0)
        {
            o.Line($"Aviso: la base {db} no tiene las tablas de WordPress: no se toca el wp-config.php de {folder}");
            return;
        }
        // Funciona en este equipo con la base asociada: es la plantilla para la próxima vez
        if (current != null && w.Name == db && prefixes.Contains(w.Prefix) && LoginOk(c, w.User, w.Password, w.Host, db, w.Prefix + "options"))
        {
            if (Ficheros.ReadSmallText(saved) != current)
                Ficheros.WriteAtomic(saved, current);
            o.Line($"WordPress: wp-config.php usa la base {db}");
            return;
        }
        string? srcText = Ficheros.ReadSmallText(saved);
        string src = saved;
        if (srcText == null && current != null) { srcText = current; src = file; }
        if (srcText == null) { srcText = Ficheros.ReadSmallText(sample); src = sample; }
        if (srcText == null)
        {
            o.Line($"Aviso: {folder} no tiene wp-config.php ni wp-config-sample.php: no se puede crear");
            return;
        }
        var s = WordPress.Read(srcText);
        string newPrefix;
        if (current != null && prefixes.Contains(w.Prefix)) newPrefix = w.Prefix;
        else if (prefixes.Contains(s.Prefix)) newPrefix = s.Prefix;
        else if (prefixes.Count == 1) newPrefix = prefixes[0];
        else
        {
            o.Line($"Aviso: {db} tiene tablas de varios WordPress (prefijos {string.Join(" ", prefixes)})");
            o.Line($"y el wp-config.php de {folder} no usa ninguno: no se toca. Pon en $table_prefix el de su web y vuelve a cargar el proyecto.");
            return;
        }
        var localDb = !LoginOk(c, s.User, s.Password, s.Host, db, newPrefix + "options");
        o.Line(w.Name != db
            ? $"WordPress: el wp-config.php de {folder} usa la base {(w.Name.Length > 0 ? w.Name : "(ninguna)")}{(w.Host.Length > 0 ? " en " + w.Host : "")}; la de la carpeta es {db}"
            : $"WordPress: el wp-config.php de {folder} no entra en el MariaDB local{(w.Host.Length > 0 ? $" (servidor {w.Host}, usuario {w.User})" : "")}");
        o.Line(src == saved ? $"Se rehace con la plantilla de este equipo, con la base {db}"
            : src == sample ? $"Se crea a partir de wp-config-sample.php, con la base {db} y claves nuevas"
            : $"Se cambia a la base {db}");
        if (localDb) o.Line("  Usuario root y servidor 127.0.0.1 (los de MariaDB local)");
        if (newPrefix != s.Prefix) o.Line($"  Prefijo de las tablas: {newPrefix} (era {(s.Prefix.Length > 0 ? s.Prefix : "ninguno")})");
        var url = LocalUrl(folder);
        o.Line($"  WP_SITEURL y WP_HOME: {url}");
        if (current != null && current != Ficheros.ReadSmallText(saved))
        {
            File.Copy(file, Path.Combine(Ficheros.EnsureDir(L.CopiesDir), $"wp-config.php-{folder}-{Ficheros.Stamp()}"), true);
            o.Line($"  El anterior queda en {L.CopiesDir}");
        }
        var neu = WordPress.Rewrite(srcText, db, newPrefix, localDb, RootPassword ?? "", url);
        File.WriteAllText(file, neu);
        Ficheros.WriteAtomic(saved, neu);
        o.Line($"wp-config.php de {folder} listo: base {db} (plantilla guardada en {saved})");
    }

    /// <summary>
    /// Base subida para un proyecto: pasa a ser su base (sustituye a la anterior). WordPress: su wp-config.php;
    /// PrestaShop: su parameters.php (o settings.inc.php) y su caché.
    /// </summary>
    void ImportProject(ClienteMariaDb c, string version, string db, string folder, ISalida o)
    {
        ValidProject(folder);
        Links.Remember(db, folder, version, only: true);
        o.Line($"La base {db} queda asociada al proyecto {folder}");
        if (Escaner.IsPrestaShop(L.Htdocs, folder))
        {
            var n = PsParameters(c, folder, db, version, o);
            n |= PsSetDb(c, folder, db, o);
            PsFirstLoad(folder, n, o);
        }
        else if (Escaner.IsWordPress(L.Htdocs, folder))
            WpConfig(c, folder, db, version, o);
    }

    /// <summary>vincular-bd &lt;base&gt; &lt;versión&gt; &lt;carpeta|-&gt;</summary>
    public void LinkDatabase(string db, string version, string folder, ISalida o)
    {
        if (!Validacion.IsDbName(db)) throw new NexumException($"Base de datos no válida: {db}");
        var m = Require(version);
        if (folder == "-")
        {
            Links.Remember(db, "", m.Folder);
            o.Line($"{db} ya no está vinculada a ningún proyecto en {m.Folder}");
            return;
        }
        ValidProject(folder);
        Links.Remember(db, folder, m.Folder);
        o.Line($"{db} queda vinculada a {folder} en {m.Folder}");
    }
}
