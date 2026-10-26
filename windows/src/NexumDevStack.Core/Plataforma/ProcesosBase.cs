using System.Diagnostics;
using System.Text;

namespace NexumDevStack.Core.Plataforma;

/// <summary>
/// Lo que se puede hacer con procesos sin depender de Windows (ejecutar y esperar, o con la entrada y la
/// salida como flujos). NexumDevStack.Windows añade arrancar sin ventana y buscar por su ruta.
/// </summary>
public abstract class ProcesosBase : IProcesos
{
    /// <summary>Variables que cambiarían lo que leen MariaDB o PHP: no pasan a los programas que se lanzan.</summary>
    public static readonly string[] UnsafeEnv =
    {
        "MYSQL_HOME", "MARIADB_HOME", "MYSQL_HOST", "MYSQL_TCP_PORT", "MYSQL_UNIX_PORT", "MYSQL_PWD", "MYSQL_PS1",
        "MYSQL_HISTFILE", "MYSQL_GROUP_SUFFIX", "MARIADB_GROUP_SUFFIX", "LIBMYSQL_PLUGIN_DIR", "LIBMYSQL_PLUGINS",
        "PHPRC", "PHP_INI_SCAN_DIR", "OPENSSL_CONF", "OPENSSL_ENGINES", "OPENSSL_MODULES", "SSL_CERT_FILE", "SSL_CERT_DIR",
        "CURL_CA_BUNDLE", "AP_PARENT_PID",
    };

    public abstract int StartDetached(string exe, IReadOnlyList<string> args, string workDir,
        IReadOnlyDictionary<string, string?>? env = null);

    public abstract IReadOnlyList<ProcesoEncontrado> FindUnder(string folder);

    public abstract bool IsRunning(int pid, string expectedImage);

    public abstract bool Kill(int pid, string expectedImage);

    public static ProcessStartInfo StartInfo(string exe, IReadOnlyList<string> args, string? workDir,
        IReadOnlyDictionary<string, string?>? env)
    {
        var psi = new ProcessStartInfo(exe)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = workDir ?? Path.GetDirectoryName(exe) ?? Environment.CurrentDirectory,
        };
        foreach (var a in args)
            psi.ArgumentList.Add(a);
        foreach (var k in UnsafeEnv)
            psi.Environment.Remove(k);
        if (env != null)
            foreach (var (k, v) in env)
            {
                if (v == null) psi.Environment.Remove(k);
                else psi.Environment[k] = v;
            }
        return psi;
    }

    public virtual ResultadoProceso Run(string exe, IReadOnlyList<string> args, TimeSpan timeout, string? workDir = null,
        IReadOnlyDictionary<string, string?>? env = null, string? stdin = null)
    {
        var psi = StartInfo(exe, args, workDir, env);
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError = true;
        psi.RedirectStandardInput = true;
        psi.StandardOutputEncoding = Encoding.UTF8;
        psi.StandardErrorEncoding = Encoding.UTF8;
        using var p = new Process { StartInfo = psi };
        var output = new StringBuilder();
        var gate = new object();
        p.OutputDataReceived += (_, e) => { if (e.Data != null) lock (gate) output.AppendLine(e.Data); };
        p.ErrorDataReceived += (_, e) => { if (e.Data != null) lock (gate) output.AppendLine(e.Data); };
        try
        {
            p.Start();
        }
        catch (Exception ex)
        {
            return new ResultadoProceso(127, $"No se ha podido ejecutar {Path.GetFileName(exe)}: {ex.Message}", false);
        }
        p.BeginOutputReadLine();
        p.BeginErrorReadLine();
        try
        {
            if (stdin != null)
                p.StandardInput.Write(stdin);
            p.StandardInput.Close();
        }
        catch (IOException)
        {
            // (el programa ha terminado sin leer la entrada)
        }
        if (!p.WaitForExit((int)Math.Min(int.MaxValue, timeout.TotalMilliseconds)))
        {
            try { p.Kill(true); } catch (Exception) { }
            lock (gate) return new ResultadoProceso(124, output.ToString(), true);
        }
        p.WaitForExit();
        lock (gate) return new ResultadoProceso(p.ExitCode, output.ToString(), false);
    }
}
