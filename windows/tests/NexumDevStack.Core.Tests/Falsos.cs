using NexumDevStack.Core.Elevacion;
using NexumDevStack.Core.Pila;
using NexumDevStack.Core.Plataforma;

namespace NexumDevStack.Core.Tests;

/// <summary>Plataforma de mentira para probar el motor sin Windows.</summary>
sealed class PlataformaFalsa : IPlataforma
{
    public PlataformaFalsa(string hostsPath) => HostsFilePath = hostsPath;

    public string HostsFilePath { get; set; }
    public bool IsElevated { get; set; } = true;
    public string CurrentUserSid => "S-1-5-21-1111111111-2222222222-3333333333-1001";
    public string CurrentUserName => "pruebas";
    public ProcesosFalsos Fake { get; } = new();
    public IProcesos Processes => Fake;
    public CertificadosFalsos Certs { get; } = new();
    public ICertificados Certificates => Certs;
    public ElevacionFalsa Elev { get; } = new();
    public IElevacion Elevation => Elev;
    public PermisosFalsos Perms { get; } = new();
    public IPermisos Permissions => Perms;
    public Version? Vc { get; set; } = new(14, 51);
    public Version? VcRuntimeVersion() => Vc;
    public int Flushes;
    public void FlushDns() => Flushes++;
    public List<PuertoOcupado> Ports { get; } = new();
    public IReadOnlyList<PuertoOcupado> PortOwners(IEnumerable<int> ports) => Ports.Where(p => ports.Contains(p.Port)).ToList();

    public bool IsSignedByMicrosoft(string path, out string detail)
    {
        detail = "falso";
        return true;
    }
}

sealed class ProcesosFalsos : ProcesosBase
{
    /// <summary>Procesos «en marcha» (su ruta).</summary>
    public List<ProcesoEncontrado> Running { get; } = new();
    public List<(string Exe, IReadOnlyList<string> Args)> Started { get; } = new();
    public List<(string Exe, IReadOnlyList<string> Args, string? Stdin)> Ran { get; } = new();

    /// <summary>Respuestas de Run: (programa, argumentos) → resultado (null: la siguiente regla).</summary>
    public List<Func<string, IReadOnlyList<string>, string?, ResultadoProceso?>> Rules { get; } = new();

    int _pid = 1000;

    public override int StartDetached(string exe, IReadOnlyList<string> args, string workDir, IReadOnlyDictionary<string, string?>? env = null)
    {
        Started.Add((exe, args));
        var pid = ++_pid;
        Running.Add(new ProcesoEncontrado(pid, exe, DateTime.Now, 1));
        return pid;
    }

    public override IReadOnlyList<ProcesoEncontrado> FindUnder(string folder) =>
        Running.Where(p => p.ImagePath.StartsWith(Path.GetFullPath(folder) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)).ToList();

    public override bool IsRunning(int pid, string expectedImage) => Running.Any(p => p.Pid == pid);

    public override bool Kill(int pid, string expectedImage) => Running.RemoveAll(p => p.Pid == pid) > 0;

    public override ResultadoProceso Run(string exe, IReadOnlyList<string> args, TimeSpan timeout, string? workDir = null,
        IReadOnlyDictionary<string, string?>? env = null, string? stdin = null)
    {
        Ran.Add((exe, args, stdin));
        foreach (var r in Rules)
            if (r(exe, args, stdin) is { } res)
                return res;
        return new ResultadoProceso(0, "", false);
    }
}

sealed class CertificadosFalsos : ICertificados
{
    public Dictionary<string, string> Store { get; } = new();
    public bool Accept { get; set; } = true;

    public bool IsTrusted(string thumbprint) => Store.ContainsKey(thumbprint);

    public bool Trust(string pemCertificate, out string detail)
    {
        detail = Accept ? "" : "cancelado";
        if (!Accept) return false;
        using var c = System.Security.Cryptography.X509Certificates.X509Certificate2.CreateFromPem(pemCertificate);
        Store[c.Thumbprint] = c.Subject;
        return true;
    }

    public bool Untrust(string thumbprint, out string detail)
    {
        detail = "";
        return Store.Remove(thumbprint);
    }

    public IReadOnlyList<(string Thumbprint, string Subject)> NexumTrusted() => Store.Select(kv => (kv.Key, kv.Value)).ToList();
}

sealed class ElevacionFalsa : IElevacion
{
    public List<IReadOnlyList<string>> Launched { get; } = new();
    public bool Accept { get; set; }

    public bool Launch(string exe, IReadOnlyList<string> args, out string detail, out System.Diagnostics.Process? process)
    {
        Launched.Add(args);
        detail = Accept ? "" : "cancelado por el usuario";
        process = null;
        return Accept;
    }
}

sealed class PermisosFalsos : IPermisos
{
    public List<string> AdminOnly { get; } = new();
    public List<string> UserPrivate { get; } = new();
    public void SetAdminOnly(string dir, bool usersCanRead, bool recursive = false) => AdminOnly.Add(dir);
    public void SetUserPrivate(string dir, string userSid) => UserPrivate.Add(dir);

    public bool IsAdminOwned(string dir, out string detail)
    {
        detail = "";
        return true;
    }
}

/// <summary>Una carpeta temporal con una disposición de Nexum preparada.</summary>
sealed class Entorno : IDisposable
{
    public Entorno(bool prepared = true)
    {
        Dir = Path.Combine(Path.GetTempPath(), "nexum-pruebas-" + Guid.NewGuid().ToString("N")[..10]);
        Directory.CreateDirectory(Dir);
        L = new Disposicion(Path.Combine(Dir, "raiz"), Path.Combine(Dir, "usuario"), Path.Combine(Dir, "copias"));
        HostsPath = Path.Combine(Dir, "hosts");
        File.WriteAllText(HostsPath, "# hosts de Windows\r\n127.0.0.1 localhost\r\n::1 localhost\r\n");
        Pf = new PlataformaFalsa(HostsPath);
        // (puertos libres: en el equipo de pruebas puede haber un Apache o un MariaDB de verdad)
        Ports = new Configuracion.Puertos(Motor.FreePort(), Motor.FreePort(), Motor.FreePort());
        M = new Motor(L, Pf, Ports) { SelfPath = Path.Combine(Dir, "NexumDevStack.exe"), AllowElevatedServices = true };
        Directory.CreateDirectory(L.UserDir);
        if (prepared)
            foreach (var d in L.AdminDirs.Concat(L.UserDirs))
                Directory.CreateDirectory(d);
    }

    public string Dir { get; }
    public Disposicion L { get; }
    public Configuracion.Puertos Ports { get; }
    public string HostsPath { get; }
    public PlataformaFalsa Pf { get; }
    public Motor M { get; }

    /// <summary>Una versión «instalada» (solo su manifiesto, su my.ini y sus carpetas).</summary>
    public Manifiesto AddVersion(string php, bool running = false)
    {
        var folder = "php-" + php;
        var m = new Manifiesto { Folder = folder, Php = php, Apache = "2.4.69", MariaDb = "11.8.9", Pma = "5.2.3", PhpBuild = "vs17" };
        Directory.CreateDirectory(L.VersionDir(folder));
        File.WriteAllText(L.Manifest(folder), m.ToJson());
        Directory.CreateDirectory(L.ConfDir(folder));
        Directory.CreateDirectory(Path.Combine(L.MariaDbDir(folder), "bin"));
        Directory.CreateDirectory(Path.Combine(L.ApacheDir(folder), "bin"));
        Directory.CreateDirectory(L.DataDir(folder));
        if (running)
        {
            Pf.Fake.Running.Add(new ProcesoEncontrado(5000 + Pf.Fake.Running.Count, Path.Combine(L.ApacheDir(folder), "bin", "httpd.exe"), DateTime.Now, 1));
            Pf.Fake.Running.Add(new ProcesoEncontrado(6000 + Pf.Fake.Running.Count, Path.Combine(L.MariaDbDir(folder), "bin", "mariadbd.exe"), DateTime.Now, 1));
        }
        return m;
    }

    public void Activate(string folder)
    {
        var a = Ajustes.Load(L);
        a.Active = folder;
        a.Save(L);
    }

    public string Project(string name, params (string Rel, string Text)[] files)
    {
        var dir = Path.Combine(L.Htdocs, name);
        Directory.CreateDirectory(dir);
        foreach (var (rel, text) in files)
        {
            var p = Path.Combine(dir, rel.Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(p)!);
            File.WriteAllText(p, text);
        }
        return dir;
    }

    public void Dispose()
    {
        try { Directory.Delete(Dir, true); } catch (IOException) { }
    }
}

/// <summary>Lanzador que dice que el usuario ha cancelado el aviso de UAC.</summary>
sealed class LanzadorCancelado : ILanzadorElevado
{
    public int Calls;

    public bool Launch(IReadOnlyList<string> args, out string detail, out Func<int?>? exitCode)
    {
        Calls++;
        detail = "cancelado por el usuario";
        exitCode = null;
        return false;
    }
}

static class Datos
{
    public static string Path(string name) => System.IO.Path.Combine(AppContext.BaseDirectory, "Datos", name);
    public static string Text(string name) => File.ReadAllText(Path(name));
}
