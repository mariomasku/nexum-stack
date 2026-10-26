using System.Text;
using System.Text.RegularExpressions;

namespace NexumDevStack.Core.Tareas;

/// <summary>
/// El registro de una tarea como lo pinta una terminal (como Console de la ventana de Linux): \r vuelve al
/// principio de la línea (las barras de las descargas se quedan en una línea que avanza), ESC[nA sube n
/// líneas y ESC[K / ESC[2K las borran, y las líneas seguidas que solo cambian en sus números y llevan un %
/// se quedan en una sola, que va subiendo. Solo las últimas líneas se pueden reescribir: las de antes
/// pasan al texto fijo.
/// </summary>
public sealed class Consola
{
    public const int Live = 80;

    static readonly Regex Token = new(@"\x1b\[([0-9;?]*)([A-Za-z])|\x1b[78()][0-9A-Za-z]?|\r\n|\r|\n|\x08", RegexOptions.CultureInvariant);
    static readonly Regex Numbers = new(@"\d+(?:[.,]\d+)?", RegexOptions.CultureInvariant);

    readonly StringBuilder _fixed = new();
    readonly List<string> _lines = new() { "" };
    int _row, _col;

    /// <summary>Texto que ya no cambia (las líneas de antes de las últimas <see cref="Live"/>).</summary>
    public string FixedText => _fixed.ToString();

    /// <summary>Las últimas líneas, que todavía se pueden reescribir.</summary>
    public string LiveText => string.Join("\n", _lines);

    public string Text => FixedText + LiveText;

    void Put(string s)
    {
        var line = _lines[_row];
        if (line.Length < _col)
            line += new string(' ', _col - line.Length);
        var tail = _col + s.Length < line.Length ? line[(_col + s.Length)..] : "";
        _lines[_row] = line[.._col] + s + tail;
        _col += s.Length;
    }

    void NewLine()
    {
        // Un contador (12 %, 13 %, …) en líneas seguidas: se queda la última
        if (_row > 0 && _lines[_row].Contains('%'))
        {
            var shape = Numbers.Replace(_lines[_row].Trim(), "#");
            if (shape == Numbers.Replace(_lines[_row - 1].Trim(), "#"))
            {
                _lines.RemoveAt(_row - 1);
                _row--;
            }
        }
        _row++;
        _col = 0;
        if (_row == _lines.Count)
            _lines.Add("");
    }

    /// <summary>Añade texto (con sus \r, \n y secuencias de escape).</summary>
    public void Write(string text)
    {
        int pos = 0;
        foreach (Match m in Token.Matches(text))
        {
            if (m.Index > pos)
                Put(text[pos..m.Index]);
            pos = m.Index + m.Length;
            var tok = m.Value;
            if (tok is "\n" or "\r\n")
                NewLine();
            else if (tok == "\r")
                _col = 0;
            else if (tok == "\x08")
                _col = Math.Max(0, _col - 1);
            else if (m.Groups[2].Success)
            {
                var arg = m.Groups[1].Value;
                var n = int.TryParse(arg, out var v) ? v : 1;
                switch (m.Groups[2].Value)
                {
                    case "A": _row = Math.Max(0, _row - n); break;
                    case "B": _row = Math.Min(_lines.Count - 1, _row + n); break;
                    case "G": _col = Math.Max(0, n - 1); break;
                    case "K":
                        var line = _lines[_row];
                        _lines[_row] = arg == "2" ? "" :
                            arg == "1" ? new string(' ', Math.Min(_col, line.Length)) + (line.Length > _col ? line[_col..] : "") :
                            line[..Math.Min(_col, line.Length)];
                        break;
                }
            }
        }
        if (pos < text.Length)
            Put(text[pos..]);
        Freeze();
    }

    void Freeze()
    {
        while (_row > Live)
        {
            _fixed.Append(_lines[0]).Append('\n');
            _lines.RemoveAt(0);
            _row--;
        }
    }
}
