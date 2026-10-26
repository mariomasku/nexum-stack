using System.Globalization;
using System.Text;

namespace NexumDevStack.Core.Tareas;

/// <summary>
/// Adónde va lo que cuenta una operación (la consola, la ventana de tareas o un registro) y cómo se
/// cancela. Las operaciones largas también dicen su avance (porcentaje, partes y bytes).
/// </summary>
public interface ISalida
{
    /// <summary>Una línea del registro.</summary>
    void Line(string text);

    /// <summary>Texto tal cual (con \r para las líneas que avanzan, como una descarga).</summary>
    void Raw(string text);

    /// <summary>Avance de la tarea: porcentaje (0-100) y lo que se hace.</summary>
    void Progress(int percent, string what);

    /// <summary>Partes de la tarea (para la lista de la ventana) y la que está en marcha (1…n).</summary>
    void Parts(IReadOnlyList<string> parts, int current);

    /// <summary>Bytes hechos de un total (subir una BBDD: «134 MB de 302 MB»).</summary>
    void Bytes(long done, long total);

    /// <summary>Resultado para la ventana (por ejemplo, el administrador de pruebas: A|wp|usuario|clave).</summary>
    void Result(string key, string value);

    CancellationToken Cancel { get; }
}

/// <summary>
/// Protocolo de la salida de una tarea: las líneas normales van tal cual y el avance en líneas que
/// empiezan por <see cref="Mark"/> (la ventana no las enseña).
/// </summary>
public static class Protocolo
{
    public const string Mark = "@@NEXUM@@|";

    public static string ProgressLine(int pct, string what) => $"{Mark}P|{Math.Clamp(pct, 0, 100)}|{Sanitize(what)}";
    public static string PartsLine(IReadOnlyList<string> parts, int current) =>
        $"{Mark}C|{current}|{string.Join(";", parts.Select(p => Sanitize(p).Replace(";", ",")))}";
    public static string BytesLine(long done, long total) => $"{Mark}B|{done}|{total}";
    public static string ResultLine(string key, string value) => $"{Mark}R|{Sanitize(key)}|{Sanitize(value)}";

    static string Sanitize(string s) => (s ?? "").Replace('\r', ' ').Replace('\n', ' ');

    /// <summary>Lo que dice una línea del protocolo, o null si es una línea normal.</summary>
    public static Aviso? Parse(string line)
    {
        if (!line.StartsWith(Mark, StringComparison.Ordinal))
            return null;
        var f = line[Mark.Length..].Split('|');
        if (f.Length < 2)
            return null;
        try
        {
            return f[0] switch
            {
                "P" when f.Length >= 3 => new Aviso('P', int.Parse(f[1], CultureInfo.InvariantCulture), 0, string.Join("|", f[2..]), null),
                "C" when f.Length >= 3 => new Aviso('C', int.Parse(f[1], CultureInfo.InvariantCulture), 0, null,
                    string.Join("|", f[2..]).Split(';', StringSplitOptions.RemoveEmptyEntries)),
                "B" when f.Length >= 3 => new Aviso('B', 0, 0, null, null)
                {
                    Done = long.Parse(f[1], CultureInfo.InvariantCulture),
                    Total = long.Parse(f[2], CultureInfo.InvariantCulture),
                },
                "R" when f.Length >= 3 => new Aviso('R', 0, 0, f[1] + "|" + string.Join("|", f[2..]), null),
                _ => null,
            };
        }
        catch (FormatException)
        {
            return null;
        }
        catch (OverflowException)
        {
            return null;
        }
    }

    public sealed record Aviso(char Kind, int Number, int Unused, string? Text, string[]? Parts)
    {
        public long Done { get; init; }
        public long Total { get; init; }
    }
}

/// <summary>Salida a un TextWriter (la consola o la tubería que lee la ventana), con el protocolo de avance.</summary>
public sealed class SalidaTexto : ISalida
{
    readonly TextWriter _out;
    readonly bool _protocol;
    readonly object _gate = new();
    // (después de un trozo sin salto de línea, como el avance de una descarga con \r, las líneas del
    // protocolo empiezan en una línea nueva: si no, la ventana no las reconocería)
    bool _midLine;

    public SalidaTexto(TextWriter output, bool protocol, CancellationToken cancel)
    {
        _out = output;
        _protocol = protocol;
        Cancel = cancel;
    }

    public CancellationToken Cancel { get; }

    public void Line(string text)
    {
        lock (_gate)
        {
            _out.WriteLine(text);
            _out.Flush();
            _midLine = false;
        }
    }

    public void Raw(string text)
    {
        lock (_gate)
        {
            _out.Write(text);
            _out.Flush();
            if (text.Length > 0)
                _midLine = text[^1] != '\n';
        }
    }

    void ProtocolLine(string line)
    {
        if (!_protocol)
            return;
        lock (_gate)
        {
            if (_midLine)
                _out.WriteLine();
            _out.WriteLine(line);
            _out.Flush();
            _midLine = false;
        }
    }

    public void Progress(int percent, string what) => ProtocolLine(Protocolo.ProgressLine(percent, what));

    public void Parts(IReadOnlyList<string> parts, int current) => ProtocolLine(Protocolo.PartsLine(parts, current));

    public void Bytes(long done, long total) => ProtocolLine(Protocolo.BytesLine(done, total));

    public void Result(string key, string value) => ProtocolLine(Protocolo.ResultLine(key, value));
}

/// <summary>Salida que se guarda en memoria (pruebas y operaciones rápidas de la ventana).</summary>
public sealed class SalidaMemoria : ISalida
{
    readonly StringBuilder _text = new();
    readonly object _gate = new();

    public SalidaMemoria(CancellationToken cancel = default) => Cancel = cancel;

    public CancellationToken Cancel { get; }
    public List<(string Key, string Value)> Results { get; } = new();
    public int LastPercent { get; private set; }

    public string Text
    {
        get { lock (_gate) return _text.ToString(); }
    }

    public void Line(string text) { lock (_gate) _text.AppendLine(text); }
    public void Raw(string text) { lock (_gate) _text.Append(text); }
    public void Progress(int percent, string what) => LastPercent = percent;
    public void Parts(IReadOnlyList<string> parts, int current) { }
    public void Bytes(long done, long total) { }
    public void Result(string key, string value) { lock (_gate) Results.Add((key, value)); }
}

/// <summary>Una operación que no se puede hacer: el mensaje va tal cual a la consola o a la ventana.</summary>
public sealed class NexumException : Exception
{
    public NexumException(string message, int exitCode = 1) : base(message) => ExitCode = exitCode;

    public int ExitCode { get; }
}
