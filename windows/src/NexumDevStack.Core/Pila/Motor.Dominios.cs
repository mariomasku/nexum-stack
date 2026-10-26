using NexumDevStack.Core.Configuracion;
using NexumDevStack.Core.Proyectos;
using NexumDevStack.Core.Tareas;
using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.Pila;

/// <summary>Lo compartido (vhosts, seguridad, certificados), hosts y los dominios falseados.</summary>
public sealed partial class Motor
{
    /// <summary>¿Está encendida la barrera entre webs? (encendida salvo que exista su fichero)</summary>
    public bool CrossSiteOn => !File.Exists(L.CrossSiteOffFile);

    /// <summary>
    /// Lo compartido por todas las versiones (con tu usuario): config\httpd-vhosts.conf, config\nexum-seguridad.conf,
    /// el certificado de localhost y la página de «ningún proyecto cargado».
    /// </summary>
    public void EnsureShared(ISalida o)
    {
        RequirePrepared();
        Directory.CreateDirectory(L.SslDir);
        Directory.CreateDirectory(L.PendingDir);
        Directory.CreateDirectory(L.EmptyProjectDir);
        if (!File.Exists(L.VhostsFile))
            Ficheros.WriteAtomic(L.VhostsFile, Vhosts.InitialFile(L));
        var crt = Path.Combine(L.SslDir, "localhost.crt");
        var key = Path.Combine(L.SslDir, "localhost.key");
        if (!File.Exists(crt) || !File.Exists(key))
        {
            o.Line("Creando el certificado autofirmado de localhost...");
            Certificados.Write(L.SslDir, "localhost.crt", "localhost.key", Certificados.Create("localhost", null));
        }
        var security = Apache.SecurityConf(L, P, CrossSiteOn);
        if (Ficheros.ReadSmallText(L.SecurityConf) != security)
            Ficheros.WriteAtomic(L.SecurityConf, security);
        var page = Path.Combine(L.EmptyProjectDir, "index.html");
        if (!File.Exists(page))
            Ficheros.WriteAtomic(page, """
<!doctype html>
<html lang="es"><head><meta charset="utf-8"><title>Sin proyecto</title>
<style>body{font-family:"Segoe UI",sans-serif;background:#2b2b2b;color:#ddd;display:flex;align-items:center;
justify-content:center;height:90vh;margin:0}div{text-align:center}h1{font-weight:500}p{color:#999}</style>
</head><body><div><h1>No hay ningún proyecto cargado</h1>
<p>Carga uno en Nexum Dev Stack: Proyectos, Cargar.</p></div></body></html>
""");
    }

    /// <summary>barrera-web si|no: encender o apagar la barrera entre webs (recarga Apache).</summary>
    public void CrossSite(bool on, ISalida o)
    {
        Directory.CreateDirectory(L.UserDir);
        if (on) { if (File.Exists(L.CrossSiteOffFile)) File.Delete(L.CrossSiteOffFile); }
        else File.WriteAllText(L.CrossSiteOffFile, "La barrera entre webs está apagada (Nexum Dev Stack)\n");
        EnsureShared(o);
        if (Active is { } a && ApacheRunning(a))
            ReloadApache(a, o);
        o.Line(on ? "Barrera entre webs encendida: otra web no puede mandar nada a tus proyectos."
                  : "Barrera entre webs apagada: enciéndela cuando acabes de probar los pagos.");
    }

    // ------------------------------------------------------------------ hosts
    public List<string> LocalOff()
    {
        var text = Ficheros.ReadSmallText(L.LocalOffFile) ?? "";
        return text.Replace("\r\n", "\n").Split('\n').Where(Validacion.IsDomain).ToList();
    }

    void SetLocalOff(bool on, params string[] domains)
    {
        var rest = LocalOff().Where(d => !domains.Contains(d)).ToList();
        if (!on) rest.AddRange(domains);
        Directory.CreateDirectory(L.UserDir);
        Ficheros.WriteAtomic(L.LocalOffFile, string.Join("\n", rest) + "\n");
    }

    /// <summary>Escribe un hosts nuevo: se deja en config\pendiente\hosts y lo escribe el proceso elevado (lo comprueba antes).</summary>
    public void ApplyHosts(string text, ISalida o, string what)
    {
        var problem = Hosts.Problem(text);
        if (problem != null)
            throw new NexumException($"El hosts nuevo no es válido: {problem}. No se ha cambiado nada.");
        var current = Ficheros.ReadSmallText(Pf.HostsFilePath, 4_000_000);
        if (current != null && current.Replace("\r\n", "\n") == text.Replace("\r\n", "\n"))
            return;
        Directory.CreateDirectory(L.PendingDir);
        if (Ficheros.IsLink(L.PendingHosts))
            File.Delete(L.PendingHosts);
        File.WriteAllText(L.PendingHosts, text.Replace("\r\n", "\n").Replace("\n", "\r\n"));
        try
        {
            Elevated("hosts", null, o, what);
        }
        finally
        {
            try { File.Delete(L.PendingHosts); } catch (IOException) { }
        }
    }

    /// <summary>hosts-falsear &lt;dominio&gt; si|no: el interruptor de la pestaña Dominios y hosts.</summary>
    public void FakeDomain(string domain, bool on, ISalida o)
    {
        domain = domain.ToLowerInvariant();
        if (!Validacion.IsDomain(domain))
            throw new NexumException("Uso: NexumDevStack.exe hosts-falsear <dominio> si|no");
        if (domain is "localhost" || domain == Disposicion.ProjectVhost || domain == "www." + Disposicion.ProjectVhost)
            throw new NexumException($"{domain} no se falsea ni se deja de falsear desde aquí: es el de los proyectos o el del equipo");
        var vhosts = VhostList();
        if (!vhosts.Any(v => v.Name == domain || v.Aliases.Contains(domain)))
            throw new NexumException($"{domain} no es el dominio de ningún vhost de {L.VhostsFile}");
        var hosts = Ficheros.ReadSmallText(Pf.HostsFilePath, 4_000_000) ?? "";
        var local = domain.EndsWith(".local", StringComparison.Ordinal);
        var bare = domain.StartsWith("www.", StringComparison.Ordinal) ? domain[4..] : domain;
        var previousOff = LocalOff();
        if (local)
            SetLocalOff(on, bare, "www." + bare);
        try
        {
            var (text, changes) = Hosts.Fake(hosts, vhosts, on ? Hosts.Modo.Si : Hosts.Modo.No, new[] { domain }, LocalOff());
            foreach (var c in changes) o.Line(c);
            ApplyHosts(text, o, "Cambiar hosts");
        }
        catch
        {
            if (local)
                Ficheros.WriteAtomic(L.LocalOffFile, string.Join("\n", previousOff) + "\n");
            throw;
        }
        if (local)
            o.Line(on ? $"{domain} encendido: lleva a este equipo (127.0.0.1) y se vuelve a mantener en hosts"
                      : $"{domain} apagado: su línea de hosts queda comentada y no se vuelve a añadir. Mientras esté apagado, Windows lo pregunta a la red.");
        else
        {
            o.Line(on ? $"{domain} falseado: lleva a este equipo (127.0.0.1)" : $"{domain} ya no está falseado: lleva a la web real");
            if (on) TrustDomain(domain, o);
            else UntrustStale(o);
        }
    }

    /// <summary>hosts-enlace: web.local pasa a 127.0.0.1 en hosts.</summary>
    public void FixProjectHost(ISalida o)
    {
        var hosts = Ficheros.ReadSmallText(Pf.HostsFilePath, 4_000_000) ?? "";
        var (text, changes) = Hosts.FixLink(hosts, Disposicion.ProjectVhost);
        if (text == hosts)
        {
            o.Line($"{Disposicion.ProjectVhost} ya lleva a este equipo (127.0.0.1)");
            return;
        }
        foreach (var c in changes) o.Line(c);
        ApplyHosts(text, o, "Cambiar hosts");
    }

    /// <summary>Editar hosts: aplica la copia editada (comprobada).</summary>
    public void ApplyHostsFile(string candidate, ISalida o)
    {
        var text = Ficheros.ReadSmallText(candidate, 1_000_000) ?? throw new NexumException($"No se puede leer {candidate}");
        ApplyHosts(text, o, "Guardar hosts");
        o.Line($"{Pf.HostsFilePath} actualizado");
    }

    /// <summary>
    /// Editar vhosts: aplica la copia editada. Se guarda el actual en nexum-copias, se escribe el nuevo, se
    /// comprueba con Apache y, si no lo acepta, se deja como estaba.
    /// </summary>
    public void ApplyVhostsFile(string candidate, ISalida o)
    {
        var text = Ficheros.ReadSmallText(candidate) ?? throw new NexumException($"No se puede leer {candidate}");
        var before = ReadVhosts();
        if (before.Replace("\r\n", "\n") == text.Replace("\r\n", "\n"))
        {
            o.Line("No has cambiado nada en los vhosts.");
            return;
        }
        BackupVhosts();
        Ficheros.WriteAtomic(L.VhostsFile, text);
        var a = Active;
        if (a != null)
        {
            var test = ApacheConfigTest(a);
            if (test != null)
            {
                Ficheros.WriteAtomic(L.VhostsFile, before);
                throw new NexumException("Apache no acepta los vhosts nuevos: se dejan como estaban.\n" + test);
            }
            if (ApacheRunning(a))
                ReloadApache(a, o);
        }
        o.Line($"Vhosts actualizados (los anteriores, en {L.CopiesDir}).");
    }

    // ------------------------------------------------------------------ proyecto nuevo con dominio falseado
    /// <summary>
    /// nuevo-dominio &lt;dominio&gt; &lt;carpeta&gt; [base]: carpeta (la usa si existe), vhost con certificado, base
    /// vacía en la versión activa (si no existe) y el dominio falseado. Cargar proyecto lo vuelve a falsear.
    /// </summary>
    public void NewCustomDomain(string domain, string folder, string? db, ISalida o)
    {
        domain = domain.ToLowerInvariant();
        if (!Validacion.IsDomain(domain))
            throw new NexumException($"Dominio no válido: {domain} (por ejemplo: mitienda.com)");
        if (domain is "localhost" || domain == Disposicion.ProjectVhost || domain == "www." + Disposicion.ProjectVhost || folder == Disposicion.ProjectVhost)
            throw new NexumException($"{Disposicion.ProjectVhost} es el de los proyectos o el del equipo: elige otro dominio y otra carpeta");
        if (!Validacion.IsNewFolder(folder) || Validacion.IsReservedWindowsName(folder))
            throw new NexumException($"Carpeta no válida: {folder} (solo letras sin acentos, números, punto, _ y -)");
        RequirePrepared();
        var path = Path.Combine(L.Htdocs, folder);
        if (Ficheros.IsLink(path))
            throw new NexumException($"{path} es un enlace, no una carpeta de proyecto");
        var owner = VhostList().FirstOrDefault(v => v.Name == domain || v.Aliases.Contains(domain));
        if (owner != null)
            throw new NexumException($"Ya hay un vhost para {domain} (carpeta {(owner.Folder.Length > 0 ? owner.Folder : "desconocida")}). Para falsearlo usa su interruptor en la pestaña Dominios y hosts.");
        if (db != null && Validacion.DbNameProblem(db) is { } p)
            throw new NexumException(p);
        EnsureShared(o);
        if (Directory.Exists(path))
            o.Line($"Se usa la carpeta que ya existe: {path}");
        else
        {
            o.Line($"Creando la carpeta {path}...");
            Directory.CreateDirectory(path);
        }
        var changed = DomainVhost(folder, domain, o);
        CustomDomains.Set(domain, folder);
        if (db != null)
        {
            try
            {
                var (af, c) = ActiveDb();
                if (c.Scalar(BaseDatos.Sql.Exists(db)) is { } n && n != "0")
                    o.Line($"La base de datos {db} ya existe en {af}: se deja como está");
                else
                    CreateDatabase(db, o);
                Links.Remember(db, folder, af);
            }
            catch (NexumException ex)
            {
                o.Line($"Aviso: no se ha creado la base {db} ({ex.Message}). Créala después en la pestaña Bases de datos.");
            }
        }
        var hosts = Ficheros.ReadSmallText(Pf.HostsFilePath, 4_000_000) ?? "";
        var (text, changes) = Hosts.Fake(hosts, VhostList(), Hosts.Modo.Cargar, new[] { domain }, LocalOff());
        foreach (var c in changes) o.Line(c);
        ApplyHosts(text, o, "Cambiar hosts");
        if (changed && Active is { } a && ApacheRunning(a))
        {
            o.Line("Recargando Apache para aplicar el vhost y el certificado...");
            ReloadApache(a, o);
        }
        TrustDomain(domain, o);
        UntrustStale(o);
        o.Line($"Proyecto nuevo listo: https://{domain} -> {path}{(db != null ? $" (base {db})" : "")}");
    }

    // ------------------------------------------------------------------ certificados de confianza
    /// <summary>Certificado (PEM) del vhost https de un dominio, si está en la carpeta de certificados.</summary>
    string? CertOf(string domain)
    {
        var v = VhostList().FirstOrDefault(x => x.Port == P.Https && x.Name == domain && x.Crt.Length > 0);
        if (v == null) return null;
        var crt = Path.GetFullPath(v.Crt.Replace('/', Path.DirectorySeparatorChar));
        if (!string.Equals(Path.GetDirectoryName(crt), Path.GetFullPath(L.SslDir), StringComparison.OrdinalIgnoreCase))
            return null;
        var pem = Ficheros.ReadSmallText(crt, 100_000);
        return pem != null && !Certificados.IsCa(pem) ? pem : null;
    }

    /// <summary>El navegador (Edge, Chrome) acepta el certificado propio de ese dominio: Windows pregunta.</summary>
    public void TrustDomain(string domain, ISalida o)
    {
        var pem = CertOf(domain);
        if (pem == null)
            return;
        var thumb = Certificados.Thumbprint(pem);
        if (thumb == null || Pf.Certificates.IsTrusted(thumb))
            return;
        o.Line($"El navegador va a aceptar el certificado de {domain} (solo vale para ese dominio): Windows pregunta antes.");
        if (Pf.Certificates.Trust(pem, out var detail))
            o.Line($"Certificado de {domain}: de confianza para tu usuario.");
        else
            o.Line($"Aviso: el certificado de {domain} no se ha añadido ({detail}). El navegador avisará al abrirlo; puedes confiar en él desde los avisos.");
    }

    /// <summary>
    /// Los certificados de dominios reales (no .local) que ya no están falseados dejan de ser de confianza: con
    /// su clave se podría suplantar la web de verdad (Windows pregunta antes).
    /// </summary>
    public void UntrustStale(ISalida o)
    {
        foreach (var (thumb, domain) in StaleCertificates())
        {
            o.Line($"{domain} ya no está falseado: el navegador deja de aceptar su certificado (Windows pregunta antes).");
            if (!Pf.Certificates.Untrust(thumb, out var detail))
                o.Line($"Aviso: no se ha quitado ({detail}). Quítalo desde los avisos.");
        }
    }

    /// <summary>Certificados de Nexum de confianza para dominios reales que ya no están falseados.</summary>
    public List<(string Thumbprint, string Domain)> StaleCertificates()
    {
        var result = new List<(string, string)>();
        var active = Hosts.ActiveLoopbackNames(Ficheros.ReadSmallText(Pf.HostsFilePath, 4_000_000) ?? "");
        foreach (var (thumb, subject) in Pf.Certificates.NexumTrusted())
        {
            var cn = System.Text.RegularExpressions.Regex.Match(subject, @"CN=([^,]+)").Groups[1].Value.Trim().ToLowerInvariant();
            if (cn.Length == 0 || cn == "localhost" || cn.EndsWith(".local", StringComparison.Ordinal))
                continue;
            if (!active.Contains(cn))
                result.Add((thumb, cn));
        }
        return result;
    }

    /// <summary>Dominios https (falseados o .local) cuyo certificado aún no acepta el navegador.</summary>
    public List<string> UntrustedDomains()
    {
        var result = new List<string>();
        var active = Hosts.ActiveLoopbackNames(Ficheros.ReadSmallText(Pf.HostsFilePath, 4_000_000) ?? "");
        foreach (var v in VhostList().Where(x => x.Port == P.Https && x.Crt.Length > 0).GroupBy(x => x.Name).Select(g => g.First()))
        {
            if (!active.Contains(v.Name))
                continue;
            var pem = CertOf(v.Name);
            var thumb = pem != null ? Certificados.Thumbprint(pem) : null;
            if (thumb != null && !Pf.Certificates.IsTrusted(thumb))
                result.Add(v.Name);
        }
        return result;
    }

    /// <summary>confiar-certificados [dominio|--quitar]</summary>
    public void TrustCertificates(string? domain, bool removeOnly, ISalida o)
    {
        if (!removeOnly)
        {
            var list = domain != null ? new List<string> { domain.ToLowerInvariant() } : UntrustedDomains();
            if (list.Count == 0)
                o.Line("El navegador ya acepta los certificados de los proyectos falseados.");
            foreach (var d in list)
                TrustDomain(d, o);
        }
        UntrustStale(o);
    }
}
