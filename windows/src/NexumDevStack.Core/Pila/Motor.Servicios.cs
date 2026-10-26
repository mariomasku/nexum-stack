using System.Net;
using System.Net.Sockets;
using NexumDevStack.Core.BaseDatos;
using NexumDevStack.Core.Configuracion;
using NexumDevStack.Core.Plataforma;
using NexumDevStack.Core.Tareas;
using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.Pila;

/// <summary>
/// Apache y MariaDB de una versión: con tu usuario, sin ventana, solo en 127.0.0.1 y ::1, y siguen en marcha
/// al cerrar el programa. Se reconocen por su ruta (dentro de versiones\php-X), no por un PID guardado.
/// </summary>
public sealed partial class Motor
{
    string HttpdExe(string folder) => Path.Combine(L.ApacheDir(folder), "bin", "httpd.exe");
    string MariaDbdExe(string folder) => Path.Combine(L.MariaDbDir(folder), "bin", "mariadbd.exe");

    /// <summary>Procesos de una versión (por la ruta de su programa).</summary>
    public IReadOnlyList<ProcesoEncontrado> VersionProcesses(string folder) => Pf.Processes.FindUnder(L.VersionDir(folder));

    public bool ApacheRunning(string folder) =>
        VersionProcesses(folder).Any(p => SamePath(p.ImagePath, HttpdExe(folder)));

    public bool MariaDbRunning(string folder) =>
        VersionProcesses(folder).Any(p => SamePath(p.ImagePath, MariaDbdExe(folder)) ||
                                          SamePath(p.ImagePath, Path.Combine(L.MariaDbDir(folder), "bin", "mysqld.exe")));

    static bool SamePath(string a, string b) =>
        string.Equals(Path.GetFullPath(a), Path.GetFullPath(b), StringComparison.OrdinalIgnoreCase);

    /// <summary>¿Está en marcha la versión activa (Apache o MariaDB)?</summary>
    public bool ActiveRunning()
    {
        var a = Active;
        return a != null && (ApacheRunning(a) || MariaDbRunning(a));
    }

    /// <summary>Procesos de otras versiones que se han quedado en memoria (versión → programas).</summary>
    public List<(string Folder, string Programs)> StrayProcesses()
    {
        var active = Active;
        var result = new List<(string, string)>();
        if (!Directory.Exists(L.Versions))
            return result;
        foreach (var g in Pf.Processes.FindUnder(L.Versions).GroupBy(p => VersionOf(p.ImagePath)))
        {
            if (g.Key == null || g.Key == active)
                continue;
            var names = g.GroupBy(p => Path.GetFileName(p.ImagePath)).Select(x => x.Count() > 1 ? $"{x.Key} ×{x.Count()}" : x.Key);
            result.Add((g.Key, string.Join(", ", names)));
        }
        return result;
    }

    string? VersionOf(string image)
    {
        var rel = Path.GetRelativePath(L.Versions, image);
        var first = rel.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)[0];
        return Validacion.IsVersionFolder(first) ? first : null;
    }

    /// <summary>Quién ocupa los puertos de los servicios y no es de Nexum (IIS, otro XAMPP, MySQL…).</summary>
    public List<PuertoOcupado> ForeignPortOwners()
    {
        var mine = Directory.Exists(L.Versions)
            ? new HashSet<int>(Pf.Processes.FindUnder(L.Versions).Select(p => p.Pid))
            : new HashSet<int>();
        return Pf.PortOwners(new[] { P.Http, P.Https, P.MariaDb })
            .Where(x => !mine.Contains(x.Pid) && x.Pid > 0)
            .GroupBy(x => (x.Port, x.Pid)).Select(g => g.First())
            .ToList();
    }

    static string PortText(PuertoOcupado x) =>
        x.Pid == 4
            ? $"El puerto {x.Port} lo usa Windows (System, PID 4): suele ser IIS (Servicio de publicación World Wide Web) u otro servicio de HTTP.sys. Páralo en Servicios de Windows."
            : $"El puerto {x.Port} lo usa {x.ProcessName} (PID {x.Pid}{(x.ImagePath != null ? ", " + x.ImagePath : "")}). Ciérralo o páralo (otro XAMPP, MySQL, Skype…).";

    // ------------------------------------------------------------------ carpetas de cada versión
    /// <summary>Carpetas de tu usuario que necesita una versión para arrancar (registros, temporales, datos).</summary>
    void EnsureRuntimeDirs(string folder)
    {
        Directory.CreateDirectory(L.LogDir(folder));
        foreach (var d in new[] { "sesiones", "subidas", "temporal", "phpmyadmin", "mariadb" })
            Directory.CreateDirectory(Path.Combine(L.TmpDir(folder), d));
    }

    /// <summary>Entorno de Apache: PHP en el PATH (sus DLL: ICU, libsasl…) y su php.ini.</summary>
    Dictionary<string, string?> ApacheEnv(string folder)
    {
        var sys = Environment.GetFolderPath(Environment.SpecialFolder.System);
        var win = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        return new Dictionary<string, string?>
        {
            ["PATH"] = string.Join(";", L.PhpDir(folder), Path.Combine(L.ApacheDir(folder), "bin"), sys, win,
                Path.Combine(sys, "Wbem")),
            ["PHPRC"] = L.PhpDir(folder),
            ["PHP_INI_SCAN_DIR"] = null,
            ["AP_PARENT_PID"] = null,
            ["TMP"] = Path.Combine(L.TmpDir(folder), "temporal"),
            ["TEMP"] = Path.Combine(L.TmpDir(folder), "temporal"),
        };
    }

    // ------------------------------------------------------------------ comprobar la configuración
    /// <summary>httpd -t con la configuración de la versión. null si está bien; si no, lo que dice Apache.</summary>
    public string? ApacheConfigTest(string folder)
    {
        var r = Pf.Processes.Run(HttpdExe(folder), new[] { "-t", "-f", L.HttpdConf(folder) }, TimeSpan.FromSeconds(60),
            Path.Combine(L.ApacheDir(folder), "bin"), ApacheEnv(folder));
        return r.ExitCode == 0 ? null : r.Output.Trim();
    }

    /// <summary>Solo para las pruebas: arrancar servicios aunque este proceso sea administrador.</summary>
    public bool AllowElevatedServices { get; set; }

    /// <summary>
    /// Apache y MariaDB corren con tu usuario: si este proceso es administrador (Nexum abierto con «Ejecutar como
    /// administrador»), no se arrancan, porque correrían como administrador.
    /// </summary>
    void RequireNotElevated()
    {
        if (Pf.IsElevated && !AllowElevatedServices)
            throw new NexumException("Nexum Dev Stack está abierto con permisos de administrador: Apache y MariaDB no se arrancan así " +
                                     "(correrían como administrador). Ciérralo y ábrelo normal, sin «Ejecutar como administrador».");
    }

    // ------------------------------------------------------------------ arrancar y parar
    public void StartMariaDb(string folder, ISalida o)
    {
        RequireNotElevated();
        if (MariaDbRunning(folder))
        {
            o.Line("MariaDB ya estaba arrancado.");
            return;
        }
        if (!Directory.Exists(L.DataDir(folder)))
            throw new NexumException($"{folder} no tiene sus BBDD ({L.DataDir(folder)}). Vuelve a instalarla o usa: NexumDevStack.exe preparar-datos {folder}");
        var busy = ForeignPortOwners().FirstOrDefault(x => x.Port == P.MariaDb);
        if (busy != null)
            throw new NexumException("MariaDB no puede arrancar. " + PortText(busy));
        EnsureRuntimeDirs(folder);
        var exe = MariaDbdExe(folder);
        Pf.Processes.StartDetached(exe, new[] { "--defaults-file=" + L.MyIni(folder) }, Path.Combine(L.MariaDbDir(folder), "bin"),
            new Dictionary<string, string?> { ["TMP"] = Path.Combine(L.TmpDir(folder), "mariadb"), ["TEMP"] = Path.Combine(L.TmpDir(folder), "mariadb") });
        var client = Client(folder);
        var until = DateTime.UtcNow.AddSeconds(60);
        while (DateTime.UtcNow < until)
        {
            o.Cancel.ThrowIfCancellationRequested();
            if (PortOpen(P.MariaDb))
            {
                var (state, _) = client.Check();
                if (state is "ok" or "clave")
                {
                    o.Line("MariaDB arrancado.");
                    return;
                }
            }
            if (!MariaDbRunning(folder) && DateTime.UtcNow > until.AddSeconds(-55))
                break;
            Thread.Sleep(500);
        }
        throw new NexumException($"MariaDB no ha arrancado. Revisa {L.MariaDbErrorLog(folder)}:\n" + Tail(L.MariaDbErrorLog(folder), 15));
    }

    public void StopMariaDb(string folder, ISalida o)
    {
        if (!MariaDbRunning(folder))
            return;
        var client = Client(folder);
        var args = client.Connection();
        args.Add("shutdown");
        Pf.Processes.Run(client.AdminExe, args, TimeSpan.FromSeconds(60), client.BinDir, client.Env(RootPassword));
        if (!WaitUntil(() => !MariaDbRunning(folder), 60))
        {
            o.Line("MariaDB no se para solo: se cierra.");
            KillVersion(folder, "mariadbd.exe", "mysqld.exe");
        }
        o.Line("MariaDB parado.");
    }

    public void StartApache(string folder, ISalida o)
    {
        RequireNotElevated();
        if (ApacheRunning(folder))
        {
            o.Line("Apache ya estaba arrancado.");
            return;
        }
        var busy = ForeignPortOwners().FirstOrDefault(x => x.Port == P.Http || x.Port == P.Https);
        if (busy != null)
            throw new NexumException("Apache no puede arrancar. " + PortText(busy));
        EnsureRuntimeDirs(folder);
        EnsureShared(o);
        var test = ApacheConfigTest(folder);
        if (test != null)
            throw new NexumException("Apache no acepta la configuración:\n" + test);
        var pid = L.ApachePid(folder);
        if (File.Exists(pid))
            File.Delete(pid);
        Pf.Processes.StartDetached(HttpdExe(folder), new[] { "-f", L.HttpdConf(folder) }, Path.Combine(L.ApacheDir(folder), "bin"),
            ApacheEnv(folder));
        if (WaitUntil(() => ApacheRunning(folder) && PortOpen(P.Http), 15))
        {
            o.Line("Apache arrancado.");
            return;
        }
        throw new NexumException($"Apache no ha arrancado. Revisa {L.ApacheErrorLog(folder)}:\n" + Tail(L.ApacheErrorLog(folder), 15));
    }

    public void StopApache(string folder, ISalida o)
    {
        if (!ApacheRunning(folder))
            return;
        // (como la consola de Windows: httpd -k shutdown avisa al Apache de su PidFile)
        Pf.Processes.Run(HttpdExe(folder), new[] { "-f", L.HttpdConf(folder), "-k", "shutdown" }, TimeSpan.FromSeconds(30),
            Path.Combine(L.ApacheDir(folder), "bin"), ApacheEnv(folder));
        if (!WaitUntil(() => !ApacheRunning(folder), 20))
        {
            o.Line("Apache no se para solo: se cierra.");
            KillVersion(folder, "httpd.exe");
        }
        o.Line("Apache parado.");
    }

    /// <summary>
    /// Reinicio suave de Apache (httpd -k restart: en Windows el proceso hijo termina lo que tiene y se crea
    /// otro): lee de nuevo los vhosts y PHP deja de recordar el proyecto anterior.
    /// </summary>
    public void ReloadApache(string folder, ISalida o)
    {
        if (!ApacheRunning(folder))
            return;
        var test = ApacheConfigTest(folder);
        if (test != null)
            throw new NexumException("Apache no acepta la configuración (sigue con la de antes):\n" + test);
        var wasOpen = PortOpen(P.Http);
        var r = Pf.Processes.Run(HttpdExe(folder), new[] { "-f", L.HttpdConf(folder), "-k", "restart" }, TimeSpan.FromSeconds(30),
            Path.Combine(L.ApacheDir(folder), "bin"), ApacheEnv(folder));
        if (r.ExitCode != 0)
        {
            o.Line("No se ha podido recargar Apache: se reinicia.");
            StopApache(folder, o);
            StartApache(folder, o);
            return;
        }
        if (wasOpen)
            WaitUntil(() => PortOpen(P.Http), 15);
        o.Line("Apache recargado.");
    }

    void KillVersion(string folder, params string[] exeNames)
    {
        foreach (var p in VersionProcesses(folder))
            if (exeNames.Any(n => Path.GetFileName(p.ImagePath).Equals(n, StringComparison.OrdinalIgnoreCase)))
                Pf.Processes.Kill(p.Pid, p.ImagePath);
        WaitUntil(() => !VersionProcesses(folder).Any(p => exeNames.Any(n =>
            Path.GetFileName(p.ImagePath).Equals(n, StringComparison.OrdinalIgnoreCase))), 10);
    }

    /// <summary>Arranca la versión activa (MariaDB y después Apache).</summary>
    public void Start(ISalida o)
    {
        var a = Active ?? throw new NexumException("No hay ninguna versión activa: activa una (NexumDevStack.exe usar <versión>).");
        o.Line($"Arrancando {a}...");
        CheckVcRuntime(o, warnOnly: false);
        StartMariaDb(a, o);
        StartApache(a, o);
    }

    /// <summary>Para la versión activa: no queda ningún proceso suyo en memoria.</summary>
    public void Stop(ISalida o, bool deactivate = false)
    {
        var a = Active;
        if (a == null)
        {
            o.Line("No hay ninguna versión activa.");
            return;
        }
        o.Line($"Parando {a}...");
        StopApache(a, o);
        StopMariaDb(a, o);
        if (deactivate)
        {
            SetActive(null);
            o.Line($"{a} parada y desactivada.");
        }
    }

    public void Restart(ISalida o)
    {
        var a = Active ?? throw new NexumException("No hay ninguna versión activa.");
        StopApache(a, o);
        StopMariaDb(a, o);
        StartMariaDb(a, o);
        StartApache(a, o);
    }

    /// <summary>Un servicio de la versión activa: apache o mariadb, arrancar, parar o reiniciar.</summary>
    public void Service(string name, string action, ISalida o)
    {
        var a = Active ?? throw new NexumException("No hay ninguna versión activa.");
        Action start, stop;
        switch (name)
        {
            case "apache": start = () => StartApache(a, o); stop = () => StopApache(a, o); break;
            case "mariadb": start = () => StartMariaDb(a, o); stop = () => StopMariaDb(a, o); break;
            default: throw new NexumException("Uso: NexumDevStack.exe servicio apache|mariadb arrancar|parar|reiniciar");
        }
        switch (action)
        {
            case "arrancar": start(); break;
            case "parar": stop(); break;
            case "reiniciar": stop(); start(); break;
            default: throw new NexumException("Uso: NexumDevStack.exe servicio apache|mariadb arrancar|parar|reiniciar");
        }
    }

    /// <summary>
    /// Monta una versión (usar): para la actual, cierra lo que quede de otras versiones y arranca la nueva.
    /// </summary>
    public void Use(string version, ISalida o)
    {
        var m = Require(version);
        var current = Active;
        if (current != null && current != m.Folder)
        {
            o.Line($"Parando {current}...");
            StopApache(current, o);
            StopMariaDb(current, o);
        }
        CloseStray(o, except: m.Folder);
        SetActive(m.Folder);
        o.Line($"{m.Folder} es ahora la versión activa (PHP {m.Php}).");
        CheckVcRuntime(o, warnOnly: false);
        StartMariaDb(m.Folder, o);
        StartApache(m.Folder, o);
    }

    /// <summary>Cierra los procesos de las versiones que no son la activa (o todas menos <paramref name="except"/>).</summary>
    public void CloseStray(ISalida o, string? except = null)
    {
        if (!Directory.Exists(L.Versions))
            return;
        var keep = except ?? Active;
        var others = Pf.Processes.FindUnder(L.Versions).Where(p => VersionOf(p.ImagePath) is { } v && v != keep).ToList();
        foreach (var g in others.GroupBy(p => VersionOf(p.ImagePath)!))
        {
            o.Line($"Cerrando lo que queda de {g.Key} en memoria...");
            StopApache(g.Key, o);
            StopMariaDb(g.Key, o);
        }
    }

    // ------------------------------------------------------------------ utilidades
    public static bool WaitUntil(Func<bool> cond, int seconds)
    {
        var until = DateTime.UtcNow.AddSeconds(seconds);
        while (DateTime.UtcNow < until)
        {
            if (cond()) return true;
            Thread.Sleep(250);
        }
        return cond();
    }

    public static bool PortOpen(int port)
    {
        try
        {
            using var c = new TcpClient();
            var t = c.ConnectAsync(IPAddress.Loopback, port);
            return t.Wait(500) && c.Connected;
        }
        catch (Exception)
        {
            return false;
        }
    }

    public static int FreePort()
    {
        var l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        var port = ((IPEndPoint)l.LocalEndpoint).Port;
        l.Stop();
        return port;
    }

    /// <summary>Últimas líneas de un registro (sin leerlo entero).</summary>
    public static string Tail(string path, int lines)
    {
        try
        {
            using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            fs.Seek(Math.Max(0, fs.Length - 64 * 1024), SeekOrigin.Begin);
            using var r = new StreamReader(fs);
            var text = r.ReadToEnd().Replace("\r\n", "\n").TrimEnd('\n').Split('\n');
            return string.Join("\n", text.Skip(Math.Max(0, text.Length - lines)).Select(l => "  " + Texto.Clean(l)));
        }
        catch (Exception)
        {
            return "  (no se puede leer)";
        }
    }

    /// <summary>
    /// Runtime de Visual C++: Apache Lounge y PHP lo necesitan (sin él, httpd.exe no arranca: falta
    /// VCRUNTIME140.dll). Con <paramref name="warnOnly"/>, solo avisa.
    /// </summary>
    public bool CheckVcRuntime(ISalida o, bool warnOnly)
    {
        var v = Pf.VcRuntimeVersion();
        if (v != null && v >= Catalogo.Catalogo.MinVcRuntime)
            return true;
        var text = v == null
            ? "Falta el runtime de Visual C++ 2015-2026 (x64): sin él, Apache y PHP no arrancan."
            : $"El runtime de Visual C++ es el {v.Major}.{v.Minor}: Apache necesita el {Catalogo.Catalogo.MinVcRuntime.Major}.{Catalogo.Catalogo.MinVcRuntime.Minor} o posterior.";
        text += " Instálalo desde el aviso de la ventana o con: NexumDevStack.exe instalar-vcredist";
        if (warnOnly)
        {
            o.Line("Aviso: " + text);
            return false;
        }
        throw new NexumException(text);
    }
}
