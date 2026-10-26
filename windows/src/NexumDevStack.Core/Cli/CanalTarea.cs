using NexumDevStack.Core.Elevacion;
using NexumDevStack.Core.Tareas;

namespace NexumDevStack.Core.Cli;

/// <summary>
/// Cuando la ventana lanza una tarea (este programa con NEXUM_TAREA=1), le habla por la entrada estándar:
/// «cancelar» la cancela; «elevado ok|no …» responde a una petición de lanzar algo con permisos de
/// administrador (la lanza la ventana, que está delante, para que el aviso de UAC salga encima de ella) y
/// «elevado-fin &lt;código&gt;», cuando ese proceso termina.
/// </summary>
public sealed class CanalTarea : ILanzadorElevado
{
    readonly TextWriter _out;
    readonly CancellationTokenSource _cts = new();
    readonly object _gate = new();
    string? _answer;
    int? _exit;

    public const string ElevateRequest = Protocolo.Mark + "E|";

    public CanalTarea(TextReader input, TextWriter output)
    {
        _out = output;
        var t = new Thread(() =>
        {
            try
            {
                string? line;
                while ((line = input.ReadLine()) != null)
                {
                    line = line.Trim();
                    if (line == "cancelar")
                        _cts.Cancel();
                    else if (line.StartsWith("elevado-fin ", StringComparison.Ordinal))
                        lock (_gate)
                        {
                            _exit = int.TryParse(line["elevado-fin ".Length..], out var c) ? c : -1;
                            Monitor.PulseAll(_gate);
                        }
                    else if (line.StartsWith("elevado ", StringComparison.Ordinal))
                        lock (_gate)
                        {
                            _answer = line["elevado ".Length..];
                            Monitor.PulseAll(_gate);
                        }
                }
            }
            catch (IOException) { }
            catch (ObjectDisposedException) { }
            // (sin entrada: la ventana se ha cerrado o ha cortado la tarea)
            _cts.Cancel();
        }) { IsBackground = true, Name = "canal-tarea" };
        t.Start();
    }

    public CancellationToken Cancel => _cts.Token;

    public bool Launch(IReadOnlyList<string> args, out string detail, out Func<int?>? exitCode)
    {
        lock (_gate)
        {
            _answer = null;
            _exit = null;
        }
        lock (_out)
        {
            _out.WriteLine(ElevateRequest + string.Join("\u001f", args));
            _out.Flush();
        }
        lock (_gate)
        {
            while (_answer == null && !_cts.IsCancellationRequested)
                Monitor.Wait(_gate, 500);
            var a = _answer ?? "no cancelado";
            detail = a.StartsWith("no", StringComparison.Ordinal) ? a.Length > 3 ? a[3..] : "cancelado" : "";
            exitCode = () => { lock (_gate) return _exit; };
            return a.StartsWith("ok", StringComparison.Ordinal);
        }
    }

    /// <summary>Lee una petición de elevación de una línea de la salida de la tarea (null si no lo es).</summary>
    public static string[]? ParseRequest(string line) =>
        line.StartsWith(ElevateRequest, StringComparison.Ordinal) ? line[ElevateRequest.Length..].Split('\u001f') : null;
}
