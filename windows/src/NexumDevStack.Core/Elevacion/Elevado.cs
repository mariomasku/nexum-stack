using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using NexumDevStack.Core.Pila;
using NexumDevStack.Core.Plataforma;
using NexumDevStack.Core.Tareas;
using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.Elevacion;

/// <summary>
/// Lo único que se hace con permisos de administrador, con sus argumentos comprobados: el programa se
/// relanza (UAC) como «NexumDevStack.exe --elevado &lt;operación&gt; &lt;tarea&gt; [dato]». Nada de rutas ni
/// órdenes libres: las rutas salen de la disposición fija (C:\NexumDevStack) y los datos se comprueban aquí
/// y otra vez en el proceso elevado.
/// </summary>
public static class ProtocoloElevado
{
    public const string Flag = "--elevado";

    /// <summary>Operaciones permitidas y si llevan un dato.</summary>
    public static readonly IReadOnlyDictionary<string, string?> Ops = new Dictionary<string, string?>
    {
        // Crea C:\NexumDevStack con sus permisos y copia el programa a programa\ (dato: SID de tu usuario)
        ["preparar"] = "sid",
        // Copia este programa (más nuevo) a programa\
        ["actualizar-programa"] = null,
        // Descarga, comprueba e instala los programas de una versión en versiones\php-X.Y.Z
        ["instalar"] = "version",
        // Borra versiones\php-X.Y.Z
        ["desinstalar"] = "version",
        // Vuelve a escribir la configuración de una versión instalada
        ["reconfigurar"] = "version",
        // Escribe en hosts el de config\pendiente\hosts (comprobado)
        ["hosts"] = null,
    };

    public sealed record Orden(string Op, string TaskId, string? Arg);

    /// <summary>Lee los argumentos que van detrás de --elevado. null si no valen (y por qué).</summary>
    public static Orden? Parse(IReadOnlyList<string> args, out string error)
    {
        error = "";
        if (args.Count < 2 || !Ops.TryGetValue(args[0], out var kind))
        {
            error = "Operación con permisos de administrador desconocida";
            return null;
        }
        if (!Validacion.IsTaskId(args[1]))
        {
            error = "Identificador de tarea no válido";
            return null;
        }
        var expected = kind == null ? 2 : 3;
        if (args.Count != expected)
        {
            error = "Número de argumentos no válido";
            return null;
        }
        string? arg = kind == null ? null : args[2];
        if (kind == "sid" && !Validacion.IsUserSid(arg))
        {
            error = "SID de usuario no válido";
            return null;
        }
        if (kind == "version" && !Validacion.IsVersionFolder(arg))
        {
            error = "Versión no válida";
            return null;
        }
        return new Orden(args[0], args[1], arg);
    }

    public static List<string> Build(Orden o)
    {
        var l = new List<string> { Flag, o.Op, o.TaskId };
        if (o.Arg != null) l.Add(o.Arg);
        return l;
    }

    public static string NewTaskId() => Convert.ToHexString(RandomNumberGenerator.GetBytes(8)).ToLowerInvariant();
}

/// <summary>
/// Cómo se lanza una operación con permisos de administrador desde el lado de tu usuario. La ventana pone
/// aquí su forma de lanzarla (con su ventana como dueña, para que el aviso de UAC salga delante); la
/// consola usa la de la plataforma.
/// </summary>
public interface ILanzadorElevado
{
    /// <summary>
    /// Lanza la operación elevada. <paramref name="exitCode"/> dice su código de salida cuando ha terminado
    /// (null mientras sigue, o si no se puede saber).
    /// </summary>
    bool Launch(IReadOnlyList<string> args, out string detail, out Func<int?>? exitCode);
}

/// <summary>
/// Lado de tu usuario: lanza la operación elevada, sigue su registro (tareas\&lt;id&gt;.log, en una carpeta de
/// administrador que tu usuario solo lee) y lo pasa a la salida, con su avance. Si este proceso ya es
/// administrador, la hace aquí mismo.
/// </summary>
public sealed class Elevador
{
    readonly Disposicion _l;
    readonly IPlataforma _pf;
    readonly ILanzadorElevado _launcher;
    readonly Action<ProtocoloElevado.Orden, ISalida> _inProcess;

    public Elevador(Disposicion l, IPlataforma pf, ILanzadorElevado launcher, Action<ProtocoloElevado.Orden, ISalida> inProcess)
    {
        _l = l;
        _pf = pf;
        _launcher = launcher;
        _inProcess = inProcess;
    }

    public string LogFile(string id) => Path.Combine(_l.Tasks, id + ".log");
    public string DoneFile(string id) => Path.Combine(_l.Tasks, id + ".fin");
    public string CancelFile(string id) => Path.Combine(_l.PendingDir, "cancelar-" + id);

    /// <summary>Ejecuta la operación; si falla o se cancela, NexumException con su motivo.</summary>
    public void Run(string op, string? arg, ISalida o, string what)
    {
        var order = new ProtocoloElevado.Orden(op, ProtocoloElevado.NewTaskId(), arg);
        if (_pf.IsElevated)
        {
            _inProcess(order, o);
            return;
        }
        o.Line($"{what}: se pide permiso de administrador (aviso de Windows)...");
        // (preparar: la carpeta de tareas aún no existe; su registro va en la tuya)
        if (!_launcher.Launch(ProtocoloElevado.Build(order), out var detail, out var exitCode))
            throw new NexumException($"Cancelado: no se ha dado permiso de administrador ({detail}). No se ha cambiado nada.", 130);
        Follow(order, exitCode, o);
    }

    void Follow(ProtocoloElevado.Orden order, Func<int?>? exitCode, ISalida o)
    {
        var log = LogFile(order.TaskId);
        var done = DoneFile(order.TaskId);
        long pos = 0;
        var pending = new StringBuilder();
        var decoder = new UTF8Encoding(false).GetDecoder();
        var cancelled = false;
        var started = DateTime.UtcNow;
        while (true)
        {
            if (o.Cancel.IsCancellationRequested && !cancelled)
            {
                cancelled = true;
                try
                {
                    // (solo si ya existe config: no se crea nada en C:\NexumDevStack con tu usuario)
                    if (Directory.Exists(_l.Config))
                    {
                        Directory.CreateDirectory(_l.PendingDir);
                        File.WriteAllText(CancelFile(order.TaskId), "cancelar");
                    }
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
                o.Line("Cancelando...");
            }
            pos = Relay(log, pos, pending, decoder, o);
            if (File.Exists(done))
            {
                Thread.Sleep(150);
                Relay(log, pos, pending, decoder, o);
                if (pending.Length > 0) Emit(pending.ToString(), o);
                var code = int.TryParse(File.ReadAllText(done).Trim(), out var c) ? c : 1;
                TryDelete(CancelFile(order.TaskId));
                if (code == 130)
                    throw new NexumException("Cancelado.", 130);
                if (code != 0)
                    throw new NexumException("La parte con permisos de administrador no ha terminado bien (mira el registro de arriba).", code);
                return;
            }
            if (exitCode?.Invoke() is { } code2 && (DateTime.UtcNow - started).TotalSeconds > 2)
            {
                Thread.Sleep(700);
                if (File.Exists(done))
                    continue;
                Relay(log, pos, pending, decoder, o);
                TryDelete(CancelFile(order.TaskId));
                throw new NexumException(code2 switch
                {
                    2 or 3 => "El proceso con permisos de administrador no ha aceptado la orden.",
                    4 => $"{_l.Root} no está preparada (o no es de administrador): vuelve a prepararla.",
                    _ => $"El proceso con permisos de administrador se ha cerrado sin terminar (código {code2}).",
                });
            }
            Thread.Sleep(250);
        }
    }

    static void TryDelete(string f)
    {
        try { if (File.Exists(f)) File.Delete(f); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }

    static long Relay(string log, long pos, StringBuilder pending, Decoder decoder, ISalida o)
    {
        try
        {
            if (!File.Exists(log))
                return pos;
            using var fs = new FileStream(log, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            if (fs.Length <= pos)
                return pos;
            fs.Position = pos;
            var buf = new byte[fs.Length - pos];
            var n = fs.Read(buf, 0, buf.Length);
            // (con su decodificador: un carácter de varios bytes puede quedar partido entre dos lecturas)
            var chars = new char[decoder.GetCharCount(buf, 0, n)];
            decoder.GetChars(buf, 0, n, chars, 0);
            pending.Append(chars);
            pos += n;
            var text = pending.ToString();
            var last = text.LastIndexOf('\n');
            if (last >= 0)
            {
                Emit(text[..(last + 1)], o);
                pending.Clear();
                pending.Append(text[(last + 1)..]);
            }
        }
        catch (IOException) { }
        return pos;
    }

    static void Emit(string text, ISalida o)
    {
        foreach (var line in text.Replace("\r\n", "\n").Split('\n'))
        {
            if (line.Length == 0) continue;
            var a = Protocolo.Parse(line);
            if (a == null) { o.Line(line); continue; }
            switch (a.Kind)
            {
                case 'P': o.Progress(a.Number, a.Text ?? ""); break;
                case 'C': o.Parts(a.Parts ?? Array.Empty<string>(), a.Number); break;
                case 'B': o.Bytes(a.Done, a.Total); break;
                case 'R':
                    var t = a.Text ?? "";
                    var bar = t.IndexOf('|');
                    o.Result(bar < 0 ? t : t[..bar], bar < 0 ? "" : t[(bar + 1)..]);
                    break;
            }
        }
    }
}
