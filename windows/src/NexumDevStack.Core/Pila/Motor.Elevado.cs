using System.Diagnostics;
using System.Text;
using NexumDevStack.Core.Configuracion;
using NexumDevStack.Core.Elevacion;
using NexumDevStack.Core.Tareas;
using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.Pila;

/// <summary>Lo que se hace con permisos de administrador (lado elevado).</summary>
public sealed partial class Motor
{
    /// <summary>
    /// Entrada del proceso elevado (NexumDevStack.exe --elevado …): comprueba la orden, abre su registro en
    /// tareas\ y la ejecuta. Devuelve el código de salida (también en tareas\&lt;id&gt;.fin).
    /// </summary>
    public int ElevatedMain(IReadOnlyList<string> args)
    {
        var order = ProtocoloElevado.Parse(args, out var error);
        if (order == null)
            return 2;
        if (!Pf.IsElevated)
            return 3;
        // La carpeta de tareas, de administrador (en preparar, se crea aquí con sus permisos; en las demás
        // tiene que existir ya: no se crea nada fuera de preparar)
        try
        {
            if (order.Op == "preparar")
                EnsureRootAndTasks();
            else if (!Directory.Exists(L.Tasks) || Ficheros.IsLink(L.Tasks) || Ficheros.IsLink(L.Root))
                return 4;
        }
        catch (Exception)
        {
            return 4;
        }
        var log = Path.Combine(L.Tasks, order.TaskId + ".log");
        var done = Path.Combine(L.Tasks, order.TaskId + ".fin");
        int code;
        using var cts = new CancellationTokenSource();
        var cancelFile = Path.Combine(L.PendingDir, "cancelar-" + order.TaskId);
        using var watcher = new Timer(_ =>
        {
            // (solo se mira si existe: no se lee nada de esa carpeta, que es de tu usuario)
            if (File.Exists(cancelFile)) cts.Cancel();
        }, null, 500, 500);
        try
        {
            using var fs = new FileStream(log, FileMode.CreateNew, FileAccess.Write, FileShare.Read);
            using var w = new StreamWriter(fs, new UTF8Encoding(false)) { AutoFlush = true };
            var o = new SalidaTexto(w, true, cts.Token);
            try
            {
                RunElevated(order, o);
                code = 0;
            }
            catch (OperationCanceledException)
            {
                o.Line("Cancelado.");
                code = 130;
            }
            catch (NexumException ex)
            {
                o.Line(ex.Message);
                code = ex.ExitCode == 0 ? 1 : ex.ExitCode;
            }
            catch (Exception ex)
            {
                o.Line("Error: " + ex.Message);
                code = 1;
            }
        }
        catch (IOException)
        {
            code = 5;
        }
        try { File.WriteAllText(done, code.ToString()); } catch (IOException) { }
        CleanOldTasks();
        return code;
    }

    void CleanOldTasks()
    {
        try
        {
            foreach (var f in Directory.EnumerateFiles(L.Tasks))
                if (File.GetLastWriteTimeUtc(f) < DateTime.UtcNow.AddDays(-30) && !Ficheros.IsLink(f))
                    File.Delete(f);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }

    /// <summary>C:\NexumDevStack y tareas\, de administrador (lo primero de preparar; en las demás, ya existen).</summary>
    void EnsureRootAndTasks()
    {
        if (Ficheros.IsLink(L.Root))
            throw new NexumException($"{L.Root} es un enlace: no se usa");
        if (!Directory.Exists(L.Root))
            Directory.CreateDirectory(L.Root);
        Pf.Permissions.SetAdminOnly(L.Root, usersCanRead: true);
        if (Ficheros.IsLink(L.Tasks))
            Directory.Delete(L.Tasks);
        Directory.CreateDirectory(L.Tasks);
        Pf.Permissions.SetAdminOnly(L.Tasks, usersCanRead: true);
    }

    /// <summary>Ejecuta una orden elevada (aquí mismo, con la salida dada).</summary>
    public void RunElevated(ProtocoloElevado.Orden order, ISalida o)
    {
        if (order.Op != "preparar")
            CheckAdminTree();
        switch (order.Op)
        {
            case "preparar": PrepareElevated(order.Arg!, o); break;
            case "actualizar-programa": CopyProgram(o); break;
            case "instalar": InstallBinaries(order.Arg!, o); break;
            case "desinstalar": RemoveBinaries(order.Arg!, o); break;
            case "reconfigurar": WriteVersionConfig(Find(order.Arg!) ?? throw new NexumException($"No existe {order.Arg}"), o); break;
            case "hosts": WriteHostsElevated(o); break;
            default: throw new NexumException("Operación desconocida");
        }
    }

    /// <summary>
    /// Antes de cualquier operación elevada: la raíz y las carpetas de administrador son de administrador y no
    /// son enlaces (si tu usuario hubiera podido cambiarlas, un enlace llevaría lo que escribe el administrador
    /// a otro sitio).
    /// </summary>
    void CheckAdminTree()
    {
        if (!Directory.Exists(L.Root) || Ficheros.IsLink(L.Root))
            throw new NexumException($"{L.Root} no está preparada: usa Preparar primero.");
        foreach (var d in new[] { L.Root }.Concat(L.AdminDirs))
        {
            if (!Directory.Exists(d))
                continue;
            if (Ficheros.IsLink(d))
                throw new NexumException($"{d} es un enlace: no se sigue. Vuelve a preparar Nexum Dev Stack.");
            if (!Pf.Permissions.IsAdminOwned(d, out var why))
                throw new NexumException($"{d} no es solo de administrador ({why}). Vuelve a preparar Nexum Dev Stack.");
        }
    }

    // ------------------------------------------------------------------ preparar
    /// <summary>
    /// Crea C:\NexumDevStack con sus permisos: la raíz y programa, versiones, descargas y tareas, de
    /// administrador (tu usuario solo las lee); datos, config, htdocs, registros y tmp, solo de tu usuario (y de
    /// administradores y SYSTEM). Quita los enlaces que hubiera en las de administrador. Copia el programa.
    /// </summary>
    void PrepareElevated(string sid, ISalida o)
    {
        o.Line($"Preparando {L.Root}...");
        EnsureRootAndTasks();
        foreach (var d in L.AdminDirs)
        {
            if (Ficheros.IsLink(d))
            {
                o.Line($"  {d} era un enlace: se quita");
                Directory.Delete(d);
            }
            Directory.CreateDirectory(d);
            RemoveLinksInside(d, o);
            Pf.Permissions.SetAdminOnly(d, usersCanRead: true, recursive: true);
            o.Line($"  {d}: de administrador (tu usuario solo puede leerla)");
        }
        foreach (var d in L.UserDirs)
        {
            if (Ficheros.IsLink(d))
            {
                o.Line($"  {d} era un enlace: se quita");
                Directory.Delete(d);
            }
            Directory.CreateDirectory(d);
            Pf.Permissions.SetUserPrivate(d, sid);
            o.Line($"  {d}: solo de tu usuario (y de administradores)");
        }
        CopyProgram(o);
        o.Line("Preparado.");
    }

    static void RemoveLinksInside(string dir, ISalida o)
    {
        var stack = new Stack<string>();
        stack.Push(dir);
        while (stack.Count > 0)
        {
            var cur = stack.Pop();
            foreach (var e in Directory.EnumerateFileSystemEntries(cur))
            {
                if (Ficheros.IsLink(e))
                {
                    o.Line($"  Enlace dentro de una carpeta de administrador: se quita {e}");
                    if (Directory.Exists(e)) Directory.Delete(e);
                    else File.Delete(e);
                }
                else if (Directory.Exists(e))
                    stack.Push(e);
            }
        }
    }

    /// <summary>Copia este programa a programa\NexumDevStack.exe (si es más nuevo o no está).</summary>
    void CopyProgram(ISalida o)
    {
        var self = SelfPath;
        if (!File.Exists(self) || !self.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
        {
            o.Line("  (sin copia del programa: no se ejecuta desde un .exe)");
            return;
        }
        if (Path.GetFullPath(self).Equals(Path.GetFullPath(L.ProgramExe), StringComparison.OrdinalIgnoreCase))
            return;
        var installed = InstalledProgramVersion();
        if (installed != null && Versiones.Compare(installed, AppInfo.Version) > 0)
        {
            o.Line($"  El programa instalado ({installed}) es más nuevo que este ({AppInfo.Version}): no se cambia");
            return;
        }
        Directory.CreateDirectory(L.Program);
        var tmp = L.ProgramExe + ".nuevo";
        File.Copy(self, tmp, true);
        File.Move(tmp, L.ProgramExe, true);
        o.Line($"  Programa copiado a {L.ProgramExe} (versión {AppInfo.Version})");
    }

    /// <summary>Versión de la copia de programa\ (null si no hay).</summary>
    public string? InstalledProgramVersion()
    {
        try
        {
            if (!File.Exists(L.ProgramExe)) return null;
            var v = FileVersionInfo.GetVersionInfo(L.ProgramExe).ProductVersion;
            if (v == null) return null;
            var plus = v.IndexOf('+');
            return plus > 0 ? v[..plus] : v;
        }
        catch (Exception ex) when (ex is IOException or FileNotFoundException)
        {
            return null;
        }
    }

    // ------------------------------------------------------------------ hosts
    /// <summary>
    /// Escribe en hosts el de config\pendiente\hosts: solo si esa ruta no pasa por enlaces y el contenido es un
    /// hosts normal (líneas de dirección y nombres). Antes guarda una copia del actual en tareas\hosts-copias.
    /// </summary>
    void WriteHostsElevated(ISalida o)
    {
        foreach (var p in new[] { L.Root, L.Config, L.PendingDir, L.PendingHosts })
            if (Ficheros.IsLink(p))
                throw new NexumException($"{p} es un enlace: no se lee");
        var info = new FileInfo(L.PendingHosts);
        if (!info.Exists || info.Length > 1_000_000)
            throw new NexumException("No hay un hosts nuevo para aplicar (o es demasiado grande)");
        var bytes = File.ReadAllBytes(L.PendingHosts);
        var text = Ficheros.DecodeText(bytes);
        var problem = Hosts.Problem(text);
        if (problem != null)
            throw new NexumException($"El hosts nuevo no es válido: {problem}. No se ha cambiado nada.");
        var hosts = Pf.HostsFilePath;
        var copies = Path.Combine(L.Tasks, "hosts-copias");
        Directory.CreateDirectory(copies);
        if (File.Exists(hosts))
        {
            var copy = Path.Combine(copies, "hosts-" + Ficheros.Stamp());
            File.Copy(hosts, copy, true);
            o.Line($"Copia del hosts anterior: {copy}");
        }
        // En el sitio (sin cambiar el fichero por otro): conserva sus permisos
        using (var fs = new FileStream(hosts, FileMode.OpenOrCreate, FileAccess.Write, FileShare.Read))
        {
            var data = new UTF8Encoding(false).GetBytes(text.Replace("\r\n", "\n").Replace("\n", "\r\n"));
            fs.SetLength(0);
            fs.Write(data, 0, data.Length);
        }
        o.Line($"{hosts} actualizado");
        Pf.FlushDns();
    }
}
