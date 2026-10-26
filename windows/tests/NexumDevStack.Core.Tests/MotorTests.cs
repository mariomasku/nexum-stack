using NexumDevStack.Core.Cli;
using NexumDevStack.Core.Configuracion;
using NexumDevStack.Core.Elevacion;
using NexumDevStack.Core.Pila;
using NexumDevStack.Core.Plataforma;
using NexumDevStack.Core.Tareas;
using Xunit;

namespace NexumDevStack.Core.Tests;

public class ProtocoloElevadoTests
{
    [Fact]
    public void SoloLasOperacionesPermitidas()
    {
        var id = ProtocoloElevado.NewTaskId();
        Assert.NotNull(ProtocoloElevado.Parse(new[] { "hosts", id }, out _));
        Assert.NotNull(ProtocoloElevado.Parse(new[] { "instalar", id, "php-8.4.27" }, out _));
        Assert.NotNull(ProtocoloElevado.Parse(new[] { "preparar", id, "S-1-5-21-1-2-3-1001" }, out _));
        Assert.Null(ProtocoloElevado.Parse(new[] { "ejecutar", id, "cmd.exe" }, out _));
        Assert.Null(ProtocoloElevado.Parse(new[] { "instalar", id, "..\\..\\Windows" }, out _));
        Assert.Null(ProtocoloElevado.Parse(new[] { "instalar", id }, out _));
        Assert.Null(ProtocoloElevado.Parse(new[] { "hosts", id, "C:\\otro" }, out _));
        Assert.Null(ProtocoloElevado.Parse(new[] { "hosts", "../x" }, out _));
        Assert.Null(ProtocoloElevado.Parse(new[] { "preparar", id, "S-1-5-18" }, out _));
        var built = ProtocoloElevado.Build(new ProtocoloElevado.Orden("desinstalar", id, "php-7.4.33"));
        Assert.Equal(new[] { "--elevado", "desinstalar", id, "php-7.4.33" }, built);
    }
}

public class ElevadorTests
{
    /// <summary>Lanzador que hace de proceso elevado: escribe su registro y su .fin como lo haría él.</summary>
    sealed class LanzadorQueEscribe : ILanzadorElevado
    {
        readonly Disposicion _l;
        readonly int _code;
        public LanzadorQueEscribe(Disposicion l, int code) { _l = l; _code = code; }

        public bool Launch(IReadOnlyList<string> args, out string detail, out Func<int?>? exitCode)
        {
            var id = args[2];
            var log = Path.Combine(_l.Tasks, id + ".log");
            File.WriteAllText(log, "Descargando PHP...\n" + Protocolo.ProgressLine(40, "descargando") + "\n" +
                                   Protocolo.ResultLine("A", "wp|u|p") + "\nhecho\n");
            File.WriteAllText(Path.Combine(_l.Tasks, id + ".fin"), _code.ToString());
            detail = "";
            exitCode = () => _code;
            return true;
        }
    }

    [Fact]
    public void SigueElRegistroDelProcesoElevado()
    {
        using var e = new Entorno();
        e.Pf.IsElevated = false;
        var o = new SalidaMemoria();
        new Elevador(e.L, e.Pf, new LanzadorQueEscribe(e.L, 0), (_, _) => throw new InvalidOperationException()).Run("hosts", null, o, "Cambiar hosts");
        Assert.Contains("Descargando PHP...", o.Text);
        Assert.Contains("hecho", o.Text);
        Assert.DoesNotContain(Protocolo.Mark, o.Text);
        Assert.Equal(40, o.LastPercent);
        Assert.Contains(("A", "wp|u|p"), o.Results);
    }

    [Fact]
    public void FalloYCancelacion()
    {
        using var e = new Entorno();
        e.Pf.IsElevated = false;
        var ex = Assert.Throws<NexumException>(() =>
            new Elevador(e.L, e.Pf, new LanzadorQueEscribe(e.L, 1), (_, _) => { }).Run("hosts", null, new SalidaMemoria(), "x"));
        Assert.Contains("no ha terminado bien", ex.Message);
        var c = Assert.Throws<NexumException>(() =>
            new Elevador(e.L, e.Pf, new LanzadorCancelado(), (_, _) => { }).Run("hosts", null, new SalidaMemoria(), "x"));
        Assert.Equal(130, c.ExitCode);
    }

    [Fact]
    public void YaElevadoLoHaceAquiMismo()
    {
        using var e = new Entorno();
        var done = false;
        new Elevador(e.L, e.Pf, new LanzadorCancelado(), (order, _) => done = order.Op == "hosts").Run("hosts", null, new SalidaMemoria(), "x");
        Assert.True(done);
    }
}

public class MotorTests
{
    static void ApacheOk(Entorno e) =>
        // httpd -t: bien; el cliente de MariaDB contesta como un 11.8
        e.Pf.Fake.Rules.Add((exe, args, _) => exe.EndsWith("mariadb.exe") && args.Contains("SELECT VERSION()")
            ? new ResultadoProceso(0, "11.8.9-MariaDB\n", false) : null);

    [Fact]
    public void VersionesInstaladasYEstado()
    {
        using var e = new Entorno();
        e.AddVersion("8.4.27", running: true);
        e.AddVersion("7.4.33");
        e.Activate("php-8.4.27");
        Directory.CreateDirectory(Path.Combine(e.L.DataDir("php-8.4.27"), "wp_tienda"));
        var st = e.M.ReadState();
        Assert.True(st.Prepared);
        Assert.Equal("php-8.4.27", st.Active);
        Assert.True(st.ApacheOn && st.MariaDbOn);
        Assert.Equal(new[] { "php-8.4.27", "php-7.4.33" }, st.Versions.Select(v => v.Folder));
        Assert.Equal(Catalogo.Php2Shell.Estado.Vulnerable, st.Versions[1].P2S);
        Assert.Single(st.Versions[0].Dbs);
        Assert.Contains("versión activa", st.Versions[0].Blocker);
        Assert.Equal("", st.Versions[1].Blocker);
        Assert.True(st.VcOk);
        Assert.True(st.ProgramOutdated);
    }

    [Fact]
    public void ProcesosDeOtrasVersionesYPuertos()
    {
        using var e = new Entorno();
        e.AddVersion("8.4.27");
        e.AddVersion("8.3.36", running: true);
        e.Activate("php-8.4.27");
        e.Pf.Ports.Add(new PuertoOcupado(e.Ports.Http, "0.0.0.0", 4, "System", null));
        e.Pf.Ports.Add(new PuertoOcupado(e.Ports.MariaDb, "127.0.0.1", e.Pf.Fake.Running[1].Pid, "mariadbd", e.Pf.Fake.Running[1].ImagePath));
        var st = e.M.ReadState();
        Assert.Equal("php-8.3.36", Assert.Single(st.Stray).Folder);
        // (el 3306 lo tiene una versión de Nexum: no es de otro programa)
        Assert.Equal(e.Ports.Http, Assert.Single(st.Ports).Port);
        var ex = Assert.Throws<NexumException>(() => e.M.StartApache("php-8.4.27", new SalidaMemoria()));
        Assert.Contains("IIS", ex.Message);
    }

    [Fact]
    public void SinRuntimeDeVisualCNoArranca()
    {
        using var e = new Entorno();
        e.AddVersion("8.4.27");
        e.Activate("php-8.4.27");
        e.Pf.Vc = new Version(14, 29);
        var ex = Assert.Throws<NexumException>(() => e.M.Start(new SalidaMemoria()));
        Assert.Contains("Visual C++", ex.Message);
    }

    [Fact]
    public void CargarProyectoCreaWebLocalYFalseaLaTienda()
    {
        using var e = new Entorno();
        e.AddVersion("8.4.27", running: true);
        e.Activate("php-8.4.27");
        ApacheOk(e);
        e.Project("mi-web", ("index.php", "<?php echo 1;"));
        var o = new SalidaMemoria();
        e.M.LoadProject("mi-web", null, null, o);
        Assert.Equal("mi-web", e.M.LoadedProject());
        Assert.True(File.Exists(Path.Combine(e.L.SslDir, "web.local.crt")));
        Assert.True(File.Exists(e.L.SecurityConf));
        Assert.True(File.Exists(Path.Combine(e.L.EmptyProjectDir, "index.html")));
        var hosts = File.ReadAllText(e.HostsPath);
        Assert.Contains("127.0.0.1 web.local www.web.local", hosts);
        Assert.Contains("\r\n", hosts);
        Assert.Equal(1, e.Pf.Flushes);
        // Apache se recarga (httpd -k restart) y el certificado de web.local pasa a ser de confianza
        Assert.Contains(e.Pf.Fake.Ran, r => r.Exe.EndsWith("httpd.exe") && r.Args.Contains("restart"));
        Assert.Single(e.Pf.Certs.Store);
        Assert.Contains("Proyecto cargado: web.local -> mi-web (php-8.4.27)", o.Text);

        // Otro proyecto: solo cambia el DocumentRoot (sin otro vhost ni otro certificado)
        e.Project("otra-web");
        e.M.LoadProject("otra-web", null, null, new SalidaMemoria());
        Assert.Equal("otra-web", e.M.LoadedProject());
        Assert.Equal(2, e.M.VhostList().Count);
        Assert.Single(e.Pf.Certs.Store);

        // Desmontar: la página vacía
        e.M.UnloadProject(new SalidaMemoria());
        Assert.Equal("", e.M.LoadedProject());
    }

    [Fact]
    public void SiNoSeDaPermisoQuedaComoEstaba()
    {
        using var e = new Entorno();
        e.AddVersion("8.4.27", running: true);
        e.Activate("php-8.4.27");
        ApacheOk(e);
        e.Project("mi-web");
        e.Pf.IsElevated = false;
        var launcher = new LanzadorCancelado();
        e.M.Launcher = launcher;
        var before = e.M.ReadVhosts();
        var hostsBefore = File.ReadAllText(e.HostsPath);
        var ex = Assert.Throws<NexumException>(() => e.M.LoadProject("mi-web", null, null, new SalidaMemoria()));
        Assert.Equal(130, ex.ExitCode);
        Assert.Equal(1, launcher.Calls);
        Assert.Equal(before, e.M.ReadVhosts());
        Assert.Null(e.M.LoadedProject());
        Assert.Equal(hostsBefore, File.ReadAllText(e.HostsPath));
        Assert.Equal("php-8.4.27", e.M.Active);
    }

    [Fact]
    public void CancelarAntesDeHostsTambienDeshace()
    {
        using var e = new Entorno();
        e.AddVersion("8.4.27", running: true);
        e.Activate("php-8.4.27");
        ApacheOk(e);
        e.Project("a");
        e.Project("b");
        e.M.LoadProject("a", null, null, new SalidaMemoria());
        using var cts = new CancellationTokenSource();
        cts.Cancel();
        Assert.Throws<NexumException>(() => e.M.LoadProject("b", null, null, new SalidaMemoria(cts.Token)));
        Assert.Equal("a", e.M.LoadedProject());
    }

    [Fact]
    public void ProyectoNuevoConDominioFalseado()
    {
        using var e = new Entorno();
        e.AddVersion("8.4.27", running: true);
        e.Activate("php-8.4.27");
        ApacheOk(e);
        var o = new SalidaMemoria();
        e.M.NewCustomDomain("MiTienda.com", "mitienda", null, o);
        Assert.True(Directory.Exists(Path.Combine(e.L.Htdocs, "mitienda")));
        var v = e.M.VhostList();
        Assert.Equal(2, v.Count(x => x.Name == "mitienda.com" && x.Folder == "mitienda"));
        Assert.Contains("127.0.0.1 mitienda.com www.mitienda.com", File.ReadAllText(e.HostsPath));
        Assert.Equal("mitienda.com", e.M.CustomDomains.Of("mitienda"));
        Assert.Single(e.Pf.Certs.Store);
        // Dejar de falsearlo: el navegador deja de aceptar su certificado
        e.M.FakeDomain("mitienda.com", false, new SalidaMemoria());
        Assert.Contains("#127.0.0.1 mitienda.com", File.ReadAllText(e.HostsPath));
        Assert.Empty(e.Pf.Certs.Store);
        Assert.Throws<NexumException>(() => e.M.NewCustomDomain("mitienda.com", "otra", null, new SalidaMemoria()));
        Assert.Throws<NexumException>(() => e.M.NewCustomDomain("web.local", "x", null, new SalidaMemoria()));
        Assert.Throws<NexumException>(() => e.M.FakeDomain("web.local", true, new SalidaMemoria()));
    }

    [Fact]
    public void HostsNoValidoNoSeEscribe()
    {
        using var e = new Entorno();
        var bad = Path.Combine(e.Dir, "hosts-editado");
        File.WriteAllText(bad, "esto no es un hosts\n");
        Assert.Throws<NexumException>(() => e.M.ApplyHostsFile(bad, new SalidaMemoria()));
        File.WriteAllText(bad, "127.0.0.1 localhost\n127.0.0.1 cosa.local\n");
        e.M.ApplyHostsFile(bad, new SalidaMemoria());
        Assert.Contains("cosa.local", File.ReadAllText(e.HostsPath));
        Assert.False(File.Exists(e.L.PendingHosts));
        Assert.Single(Directory.GetFiles(Path.Combine(e.L.Tasks, "hosts-copias")));
    }

    [Fact]
    public void EditarVhostsQueApacheNoAceptaSeDeshace()
    {
        using var e = new Entorno();
        e.AddVersion("8.4.27", running: true);
        e.Activate("php-8.4.27");
        e.M.EnsureShared(new SalidaMemoria());
        var before = e.M.ReadVhosts();
        e.Pf.Fake.Rules.Add((exe, args, _) => exe.EndsWith("httpd.exe") && args.Contains("-t")
            ? new ResultadoProceso(1, "Syntax error on line 3", false) : null);
        var cand = Path.Combine(e.Dir, "vhosts");
        File.WriteAllText(cand, before + "\n<VirtualHost *:80>\nMalo\n");
        var ex = Assert.Throws<NexumException>(() => e.M.ApplyVhostsFile(cand, new SalidaMemoria()));
        Assert.Contains("Syntax error", ex.Message);
        Assert.Equal(before, e.M.ReadVhosts());
    }

    [Fact]
    public void BarreraEntreWebs()
    {
        using var e = new Entorno();
        e.M.CrossSite(false, new SalidaMemoria());
        Assert.False(e.M.CrossSiteOn);
        Assert.DoesNotContain(Apache.CrossSiteStart, File.ReadAllText(e.L.SecurityConf));
        e.M.CrossSite(true, new SalidaMemoria());
        Assert.Contains(Apache.CrossSiteStart, File.ReadAllText(e.L.SecurityConf));
    }

    [Fact]
    public void UsarParaLaAnteriorYArrancaLaNueva()
    {
        using var e = new Entorno();
        e.AddVersion("8.4.27", running: true);
        e.AddVersion("8.5.12");
        e.Activate("php-8.4.27");
        // (al pararse con -k shutdown o mariadb-admin, sus procesos desaparecen)
        e.Pf.Fake.Rules.Add((exe, args, _) =>
        {
            if (exe.EndsWith("httpd.exe") && args.Contains("shutdown") || exe.EndsWith("mariadb-admin.exe") && args.Contains("shutdown"))
                e.Pf.Fake.Running.RemoveAll(p => p.ImagePath.Contains("php-8.4.27"));
            return null;
        });
        ApacheOk(e);
        // (los «servidores» de la nueva escuchan en sus puertos)
        var maria = new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, e.Ports.MariaDb);
        var web = new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, e.Ports.Http);
        maria.Start();
        web.Start();
        try
        {
            e.M.Use("8.5.12", new SalidaMemoria());
        }
        finally
        {
            maria.Stop();
            web.Stop();
        }
        Assert.Equal("php-8.5.12", e.M.Active);
        Assert.True(e.M.ApacheRunning("php-8.5.12"));
        Assert.Empty(e.M.VersionProcesses("php-8.4.27"));
        Assert.Contains(e.Pf.Fake.Started, s => s.Exe.EndsWith("mariadbd.exe") && s.Exe.Contains("php-8.5.12"));
    }

    [Fact]
    public void ComoAdministradorNoSeArrancanLosServicios()
    {
        using var e = new Entorno();
        e.AddVersion("8.4.27");
        e.Activate("php-8.4.27");
        e.M.AllowElevatedServices = false;
        var ex = Assert.Throws<NexumException>(() => e.M.Start(new SalidaMemoria()));
        Assert.Contains("permisos de administrador", ex.Message);
        Assert.Empty(e.Pf.Fake.Started);
    }

    [Fact]
    public void DesinstalarLaActivaNo()
    {
        using var e = new Entorno();
        e.AddVersion("8.4.27");
        e.Activate("php-8.4.27");
        Assert.Throws<NexumException>(() => e.M.Uninstall("8.4.27", false, new SalidaMemoria()));
        e.AddVersion("8.3.36");
        Directory.CreateDirectory(e.L.LogDir("php-8.3.36"));
        e.M.Uninstall("php-8.3.36", false, new SalidaMemoria());
        Assert.False(Directory.Exists(e.L.VersionDir("php-8.3.36")));
        Assert.False(Directory.Exists(e.L.DataDir("php-8.3.36")));
    }

    [Fact]
    public void ProyectosParaLaVentana()
    {
        using var e = new Entorno();
        e.Project("wp", ("wp-config.php", "<?php define('DB_NAME', 'wp_x');"));
        e.M.Links.Remember("wp_x", "wp", "php-8.4.27");
        var p = e.M.ReadProjects();
        Assert.True(p.Create);
        Assert.Equal("wp", Assert.Single(p.List).Name);
        Assert.Equal("wp", p.LinkOf("wp_x", "php-8.4.27"));
        Assert.Null(p.LinkOf("wp_x", "php-8.5.12"));
    }

    [Fact]
    public void ElevadoPrepararCreaLasCarpetasConSusPermisos()
    {
        using var e = new Entorno(prepared: false);
        e.Pf.IsElevated = true;
        File.WriteAllText(e.M.SelfPath, "programa");
        e.M.RunElevated(new ProtocoloElevado.Orden("preparar", ProtocoloElevado.NewTaskId(), e.Pf.CurrentUserSid), new SalidaMemoria());
        Assert.True(e.L.IsPrepared);
        foreach (var d in e.L.AdminDirs) Assert.Contains(d, e.Pf.Perms.AdminOnly);
        foreach (var d in e.L.UserDirs) Assert.Contains(d, e.Pf.Perms.UserPrivate);
        Assert.Equal("programa", File.ReadAllText(e.L.ProgramExe));
    }

    [Fact]
    public void ElevadoRechazaOrdenesRaras()
    {
        using var e = new Entorno();
        Assert.Equal(2, e.M.ElevatedMain(new[] { "borrar-todo", ProtocoloElevado.NewTaskId() }));
        e.Pf.IsElevated = false;
        Assert.Equal(3, e.M.ElevatedMain(new[] { "hosts", ProtocoloElevado.NewTaskId() }));
    }

    [Fact]
    public void ElevadoEscribeHostsYSuRegistro()
    {
        using var e = new Entorno();
        Directory.CreateDirectory(e.L.PendingDir);
        File.WriteAllText(e.L.PendingHosts, "127.0.0.1 localhost\n127.0.0.1 nuevo.local\n");
        var id = ProtocoloElevado.NewTaskId();
        Assert.Equal(0, e.M.ElevatedMain(new[] { "hosts", id }));
        Assert.Contains("nuevo.local", File.ReadAllText(e.HostsPath));
        Assert.Equal("0", File.ReadAllText(Path.Combine(e.L.Tasks, id + ".fin")));
        Assert.Contains("actualizado", File.ReadAllText(Path.Combine(e.L.Tasks, id + ".log")));
        File.WriteAllText(e.L.PendingHosts, "malo\n");
        var id2 = ProtocoloElevado.NewTaskId();
        Assert.Equal(1, e.M.ElevatedMain(new[] { "hosts", id2 }));
        Assert.Contains("no es válido", File.ReadAllText(Path.Combine(e.L.Tasks, id2 + ".log")));
    }
}

public class ComandosTests
{
    [Fact]
    public void AyudaVersionYDesconocido()
    {
        using var e = new Entorno();
        var o = new SalidaMemoria();
        Assert.Equal(0, Comandos.Run(e.M, new[] { "--ayuda" }, o));
        Assert.Contains("cargar-proyecto <carpeta>", o.Text);
        o = new SalidaMemoria();
        Assert.Equal(0, Comandos.Run(e.M, new[] { "version" }, o));
        Assert.Equal(AppInfo.Version, o.Text.Trim());
        Assert.Equal(2, Comandos.Run(e.M, new[] { "no-existe" }, new SalidaMemoria()));
        Assert.Equal(2, Comandos.Run(e.M, new[] { "crear-bd" }, new SalidaMemoria()));
        Assert.True(Comandos.IsCommand(new[] { "estado" }));
        Assert.False(Comandos.IsCommand(Array.Empty<string>()));
    }

    [Fact]
    public void EstadoSinPreparar()
    {
        using var e = new Entorno(prepared: false);
        var o = new SalidaMemoria();
        Assert.Equal(0, Comandos.Run(e.M, new[] { "estado" }, o));
        Assert.Contains("no está preparado", o.Text);
        Assert.Equal(1, Comandos.Run(e.M, new[] { "cargar-proyecto", "x" }, new SalidaMemoria()));
    }

    [Fact]
    public void VersionDelProgramaYNovedades()
    {
        Assert.Equal("0.1.0", AppInfo.Version);
        Assert.StartsWith("## 0.1.0 · ", AppInfo.Changes.TrimStart());
    }

    sealed class Cola : TextReader
    {
        public readonly System.Collections.Concurrent.BlockingCollection<string> Lines = new();

        public override string? ReadLine()
        {
            try { return Lines.Take(); }
            catch (InvalidOperationException) { return null; }
        }
    }

    [Fact]
    public async Task CanalDeLaVentana()
    {
        var input = new Cola();
        var output = new StringWriter();
        var c = new CanalTarea(input, TextWriter.Synchronized(output));
        // La ventana: ve la petición, la lanza y contesta
        var window = Task.Run(() =>
        {
            SpinWait.SpinUntil(() => output.ToString().Contains(CanalTarea.ElevateRequest), 5000);
            input.Lines.Add("elevado ok");
            Thread.Sleep(100);
            input.Lines.Add("elevado-fin 0");
            Thread.Sleep(100);
            input.Lines.CompleteAdding();
        });
        Assert.True(c.Launch(new[] { "--elevado", "hosts", "0123456789abcdef" }, out _, out var exit));
        Assert.Equal(new[] { "--elevado", "hosts", "0123456789abcdef" }, CanalTarea.ParseRequest(output.ToString().Trim()));
        Assert.True(SpinWait.SpinUntil(() => exit!() == 0, 3000));
        await window;
        // (sin entrada, la tarea se cancela)
        Assert.True(SpinWait.SpinUntil(() => c.Cancel.IsCancellationRequested, 3000));
    }

    [Fact]
    public void CanalCancelar()
    {
        var input = new Cola();
        var c = new CanalTarea(input, new StringWriter());
        Assert.False(c.Cancel.IsCancellationRequested);
        input.Lines.Add("cancelar");
        Assert.True(SpinWait.SpinUntil(() => c.Cancel.IsCancellationRequested, 3000));
    }
}
