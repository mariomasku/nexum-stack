using System.IO.Compression;
using System.Text;
using System.Text.RegularExpressions;
using NexumDevStack.Core.Tareas;

namespace NexumDevStack.Core.BaseDatos;

/// <summary>
/// Lo que se le hace a un volcado antes de cargarlo (como la tubería de importar-bd de Linux): sin la
/// primera línea del modo sandbox (/*M!999999\- …*/, que los MariaDB antiguos no entienden), sin los
/// DEFINER de vistas, disparadores y rutinas (son de otro usuario) y con INVOKER cambiado por DEFINER (lo
/// INVOKER se ejecutaría con los permisos de quien lo use: root en phpMyAdmin). Por líneas y en bytes
/// (Latin-1, que no cambia ningún byte): los volcados no tienen por qué ser UTF-8.
/// </summary>
public static class FiltroVolcado
{
    static readonly Encoding Bytes = Encoding.Latin1;
    static readonly Regex Definer = new(@"DEFINER=`[^`]*`@`[^`]*`", RegexOptions.CultureInvariant);

    // La palabra INVOKER suelta (no dentro de un nombre: invoker_id, $invoker, php-di/invoker, Vendor\Invoker,
    // x.invoker), en mayúsculas o minúsculas, pasa a DEFINER con las mismas mayúsculas
    static readonly Regex Invoker = new(@"(?<![A-Za-z0-9_$@.\\])(?<![^*]/)INVOKER(?![A-Za-z0-9_$.\\])",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    public const string SandboxPrefix = "/*M!999999\\-";

    static string Swap(string w)
    {
        const string neu = "DEFINER";
        var sb = new StringBuilder(7);
        for (int i = 0; i < 7; i++)
            sb.Append(char.IsUpper(w[i]) ? neu[i] : char.ToLowerInvariant(neu[i]));
        return sb.ToString();
    }

    /// <summary>Una línea (sin su \n) ya filtrada. <paramref name="first"/>: es la primera del volcado.</summary>
    public static string? FilterLine(string line, bool first)
    {
        if (first && line.StartsWith(SandboxPrefix, StringComparison.Ordinal))
            return null;
        if (line.Contains("DEFINER=", StringComparison.Ordinal))
            line = Definer.Replace(line, "");
        if (line.Contains("nvoker", StringComparison.OrdinalIgnoreCase) || line.Contains("NVOKER", StringComparison.Ordinal))
        {
            // (con el \n de la línea anterior delante, como si fuera todo seguido)
            var ctx = first ? line : "\n" + line;
            ctx = Invoker.Replace(ctx, m => Swap(m.Value));
            line = first ? ctx : ctx[1..];
        }
        return line;
    }

    /// <summary>Copia el volcado de <paramref name="input"/> a <paramref name="output"/> filtrado.</summary>
    public static void Copy(Stream input, Stream output, CancellationToken ct)
    {
        var reader = new LineReader(input);
        bool first = true;
        byte[]? line;
        var nl = new[] { (byte)'\n' };
        while ((line = reader.ReadLine(out var hadNewline)) != null)
        {
            ct.ThrowIfCancellationRequested();
            var text = Bytes.GetString(line);
            var filtered = FilterLine(text, first);
            first = false;
            if (filtered == null)
                continue;
            var bytes = ReferenceEquals(filtered, text) ? line : Bytes.GetBytes(filtered);
            output.Write(bytes, 0, bytes.Length);
            if (hadNewline)
                output.Write(nl, 0, 1);
        }
        output.Flush();
    }

    /// <summary>Lee líneas en bytes (con cualquier tamaño de línea).</summary>
    sealed class LineReader
    {
        readonly Stream _s;
        readonly byte[] _buf = new byte[1 << 16];
        int _pos, _len;

        public LineReader(Stream s) => _s = s;

        public byte[]? ReadLine(out bool newline)
        {
            newline = false;
            var acc = new MemoryStream();
            while (true)
            {
                if (_pos >= _len)
                {
                    _len = _s.Read(_buf, 0, _buf.Length);
                    _pos = 0;
                    if (_len <= 0)
                        return acc.Length > 0 ? acc.ToArray() : null;
                }
                var idx = Array.IndexOf(_buf, (byte)'\n', _pos, _len - _pos);
                if (idx >= 0)
                {
                    acc.Write(_buf, _pos, idx - _pos);
                    _pos = idx + 1;
                    newline = true;
                    return acc.ToArray();
                }
                acc.Write(_buf, _pos, _len - _pos);
                _pos = _len;
            }
        }
    }
}

/// <summary>Un volcado para cargar: .sql, .sql.gz o .zip (con un solo .sql dentro), por su contenido.</summary>
public sealed class Volcado : IDisposable
{
    readonly FileStream _file;
    readonly ZipArchive? _zip;

    Volcado(FileStream file, Stream content, string kind, string inner, long innerSize, ZipArchive? zip)
    {
        _file = file;
        Content = content;
        Kind = kind;
        Inner = inner;
        InnerSize = innerSize;
        _zip = zip;
    }

    /// <summary>sql, gz o zip.</summary>
    public string Kind { get; }
    /// <summary>El .sql de dentro del zip (sin caracteres de control).</summary>
    public string Inner { get; }
    public long InnerSize { get; }
    /// <summary>El .sql (descomprimido al vuelo).</summary>
    public Stream Content { get; }
    public long FileSize => _file.Length;

    /// <summary>Bytes hechos y total para la barra: del fichero (sql, gz) o del .sql de dentro (zip).</summary>
    public (long Done, long Total) Position()
    {
        try
        {
            return Kind == "zip" ? (((CountingStream)Content).Count, InnerSize) : (_file.Position, _file.Length);
        }
        catch (ObjectDisposedException)
        {
            return (0, 0);
        }
    }

    public static Volcado Open(string path)
    {
        var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16);
        try
        {
            var head = new byte[4];
            var n = fs.Read(head, 0, 4);
            fs.Position = 0;
            var lower = path.ToLowerInvariant();
            var isGz = n >= 2 && head[0] == 0x1f && head[1] == 0x8b;
            var isZip = n == 4 && head[0] == 0x50 && head[1] == 0x4b && head[2] == 0x03 && head[3] == 0x04;
            if (lower.EndsWith(".zip") && !isZip)
                throw new NexumException($"{Path.GetFileName(path)} no es un .zip valido");
            if (lower.EndsWith(".gz") && !isGz)
                throw new NexumException($"{Path.GetFileName(path)} no es un .gz valido");
            if (isGz)
                return new Volcado(fs, new GZipStream(fs, CompressionMode.Decompress), "gz", "", 0, null);
            if (isZip)
            {
                ZipArchive zip;
                try
                {
                    zip = new ZipArchive(fs, ZipArchiveMode.Read, true);
                }
                catch (InvalidDataException ex)
                {
                    throw new NexumException("El fichero .zip no es valido: " + ex.Message);
                }
                var sqls = zip.Entries.Where(e => !e.FullName.EndsWith('/') && !e.FullName.StartsWith("__MACOSX/") &&
                                                  e.FullName.EndsWith(".sql", StringComparison.OrdinalIgnoreCase)).ToList();
                string Clean(string s) => Regex.Replace(s, @"[\x00-\x1f\x7f-\x9f]", "?");
                if (sqls.Count == 0)
                    throw new NexumException("El .zip no tiene ningun fichero .sql dentro");
                if (sqls.Count > 1)
                    throw new NexumException("El .zip tiene varios .sql (" + string.Join(", ", sqls.Select(e => Clean(e.FullName))) +
                                             "): deja solo el que quieras cargar");
                var entry = sqls[0];
                return new Volcado(fs, new CountingStream(entry.Open()), "zip", Clean(entry.FullName).Replace("|", " "), entry.Length, zip);
            }
            return new Volcado(fs, fs, "sql", "", 0, null);
        }
        catch
        {
            fs.Dispose();
            throw;
        }
    }

    public void Dispose()
    {
        if (!ReferenceEquals(Content, _file))
            Content.Dispose();
        _zip?.Dispose();
        _file.Dispose();
    }

    /// <summary>¿Empieza por la línea del modo sandbox?</summary>
    public static bool StartsWithSandbox(string path)
    {
        using var v = Open(path);
        var buf = new byte[200];
        int read = 0, n;
        while (read < buf.Length && (n = v.Content.Read(buf, read, buf.Length - read)) > 0)
            read += n;
        return Encoding.Latin1.GetString(buf, 0, read).StartsWith(FiltroVolcado.SandboxPrefix, StringComparison.Ordinal);
    }
}

/// <summary>Flujo que cuenta lo que se lee.</summary>
public sealed class CountingStream : Stream
{
    readonly Stream _inner;
    long _count;

    public CountingStream(Stream inner) => _inner = inner;

    public long Count => Interlocked.Read(ref _count);
    public override bool CanRead => true;
    public override bool CanSeek => false;
    public override bool CanWrite => false;
    public override long Length => throw new NotSupportedException();
    public override long Position { get => Count; set => throw new NotSupportedException(); }
    public override void Flush() { }

    public override int Read(byte[] buffer, int offset, int count)
    {
        var n = _inner.Read(buffer, offset, count);
        Interlocked.Add(ref _count, n);
        return n;
    }

    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();
    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

    protected override void Dispose(bool disposing)
    {
        if (disposing) _inner.Dispose();
        base.Dispose(disposing);
    }
}
