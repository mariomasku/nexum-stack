using System.Diagnostics;
using System.Text;
using NexumDevStack.Core.Plataforma;
using NexumDevStack.Core.Tareas;

namespace NexumDevStack.Core.BaseDatos;

/// <summary>
/// El cliente de MariaDB de una versión (mariadb.exe), siempre sin ficheros de opciones (--no-defaults: ni
/// C:\my.ini ni %MARIADB_HOME%) y por TCP a 127.0.0.1. La contraseña de root, si la tiene, va en MYSQL_PWD
/// (no en la línea de órdenes).
/// </summary>
public sealed class ClienteMariaDb
{
    readonly IProcesos _proc;

    public ClienteMariaDb(IProcesos proc, string binDir, int port, string? rootPassword = null)
    {
        _proc = proc;
        BinDir = binDir;
        Port = port;
        RootPassword = rootPassword;
    }

    public string BinDir { get; }
    public int Port { get; }
    public string? RootPassword { get; }

    public string ClientExe => Pick("mariadb.exe", "mysql.exe");
    public string DumpExe => Pick("mariadb-dump.exe", "mysqldump.exe");
    public string AdminExe => Pick("mariadb-admin.exe", "mysqladmin.exe");

    string Pick(string a, string b)
    {
        var pa = Path.Combine(BinDir, a);
        return File.Exists(pa) || !File.Exists(Path.Combine(BinDir, b)) ? pa : Path.Combine(BinDir, b);
    }

    public List<string> Connection(string user = "root") => new()
    {
        "--no-defaults", "--protocol=TCP", "-h", "127.0.0.1", "-P", Port.ToString(), "-u", user,
    };

    public Dictionary<string, string?> Env(string? password) => new() { ["MYSQL_PWD"] = password };

    /// <summary>Una consulta como root, sin cabeceras (-N -B); el resultado, tal cual.</summary>
    public ResultadoProceso Run(string sql, string? db = null, bool raw = false, bool force = false, string user = "root",
        string? password = null, TimeSpan? timeout = null, string? stdin = null, bool binaryMode = false)
    {
        var args = Connection(user);
        args.AddRange(new[] { "--default-character-set=utf8mb4", "-N", "-B" });
        if (raw) args.Add("--raw");
        if (force) args.Add("--force");
        if (binaryMode) args.AddRange(new[] { "--binary-mode", "--local-infile=0" });
        if (sql.Length > 0) { args.Add("-e"); args.Add(sql); }
        if (db != null) args.Add(db);
        return _proc.Run(ClientExe, args, timeout ?? TimeSpan.FromMinutes(5), BinDir,
            Env(user == "root" ? RootPassword : password), stdin);
    }

    /// <summary>Filas de una consulta (cada una, sus campos separados por tabuladores). Error → excepción.</summary>
    public List<string[]> Rows(string sql, string? db = null)
    {
        var r = Run(sql, db);
        if (r.ExitCode != 0)
            throw new NexumException(Clean(r.Output));
        return r.Output.Replace("\r\n", "\n").Split('\n').Where(l => l.Length > 0).Select(l => l.Split('\t')).ToList();
    }

    /// <summary>Un solo valor (o null).</summary>
    public string? Scalar(string sql, string? db = null)
    {
        var r = Run(sql, db);
        if (r.ExitCode != 0)
            return null;
        var line = r.Output.Replace("\r\n", "\n").Split('\n').FirstOrDefault(l => l.Length > 0);
        return line;
    }

    /// <summary>Lo que dice el cliente, sin sus avisos repetidos.</summary>
    public static string Clean(string output) =>
        string.Join("\n", output.Replace("\r\n", "\n").Split('\n').Where(l => l.Length > 0 && !l.Contains("Using a password on the command line")));

    /// <summary>¿Responde? ok, clave (pide contraseña) o no (con su motivo).</summary>
    public (string State, string Detail) Check()
    {
        var r = Run("SELECT VERSION()", timeout: TimeSpan.FromSeconds(15));
        if (r.ExitCode == 0)
            return ("ok", r.Output.Trim().Split('-')[0]);
        if (r.Output.Contains("1045") || r.Output.Contains("Access denied"))
            return ("clave", "");
        return ("no", Clean(r.Output));
    }

    /// <summary>Proceso del cliente con su entrada y salida como flujos (subir un volcado).</summary>
    public Process StartStreaming(string exe, IReadOnlyList<string> args, string? password, bool redirectStdin, bool redirectStdout)
    {
        var psi = ProcesosBase.StartInfo(exe, args, BinDir, Env(password));
        psi.RedirectStandardInput = redirectStdin;
        psi.RedirectStandardOutput = redirectStdout;
        psi.RedirectStandardError = true;
        psi.StandardErrorEncoding = Encoding.UTF8;
        var p = new Process { StartInfo = psi };
        p.Start();
        return p;
    }
}
