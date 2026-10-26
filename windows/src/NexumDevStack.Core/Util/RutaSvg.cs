using System.Globalization;
using System.Text;

namespace NexumDevStack.Core.Util;

/// <summary>
/// Trazos SVG (los logotipos de Simple Icons) en la sintaxis de WPF: SVG deja escribir los indicadores de los
/// arcos pegados («a.5.5 0 00.5.5») y números seguidos sin separador («.5.5»), que WPF no entiende. Aquí se
/// leen con las reglas de SVG y se escriben con espacios.
/// </summary>
public static class RutaSvg
{
    static readonly Dictionary<char, int> Arity = new()
    {
        ['M'] = 2, ['L'] = 2, ['H'] = 1, ['V'] = 1, ['C'] = 6, ['S'] = 4, ['Q'] = 4, ['T'] = 2, ['A'] = 7, ['Z'] = 0,
    };

    public static string Normalize(string d)
    {
        var sb = new StringBuilder();
        int i = 0;
        char cmd = ' ';
        while (true)
        {
            SkipSeparators(d, ref i);
            if (i >= d.Length)
                break;
            if (char.IsLetter(d[i]))
            {
                cmd = d[i++];
                if (!Arity.ContainsKey(char.ToUpperInvariant(cmd)))
                    throw new FormatException($"Orden SVG desconocida: {cmd}");
                if (char.ToUpperInvariant(cmd) == 'Z')
                {
                    sb.Append(cmd).Append(' ');
                    continue;
                }
            }
            else if (cmd == ' ')
                throw new FormatException("El trazo no empieza por una orden");
            var upper = char.ToUpperInvariant(cmd);
            var n = Arity[upper];
            sb.Append(cmd);
            for (int k = 0; k < n; k++)
            {
                SkipSeparators(d, ref i);
                string num;
                // Los indicadores de un arco (4.º y 5.º) son un solo dígito: 0 o 1
                if (upper == 'A' && (k == 3 || k == 4))
                {
                    if (i >= d.Length || (d[i] != '0' && d[i] != '1'))
                        throw new FormatException("Indicador de arco no válido");
                    num = d[i++].ToString();
                }
                else
                    num = ReadNumber(d, ref i);
                sb.Append(' ').Append(num);
            }
            sb.Append(' ');
            // Tras un M, los pares siguientes son L (como dice SVG)
            if (cmd == 'M') cmd = 'L';
            else if (cmd == 'm') cmd = 'l';
        }
        return sb.ToString().Trim();
    }

    static void SkipSeparators(string d, ref int i)
    {
        while (i < d.Length && (char.IsWhiteSpace(d[i]) || d[i] == ','))
            i++;
    }

    static string ReadNumber(string d, ref int i)
    {
        int start = i;
        if (i < d.Length && (d[i] == '-' || d[i] == '+')) i++;
        bool dot = false, digits = false;
        while (i < d.Length)
        {
            var c = d[i];
            if (char.IsDigit(c)) { digits = true; i++; }
            else if (c == '.' && !dot) { dot = true; i++; }
            else break;
        }
        if (i < d.Length && (d[i] == 'e' || d[i] == 'E'))
        {
            i++;
            if (i < d.Length && (d[i] == '-' || d[i] == '+')) i++;
            while (i < d.Length && char.IsDigit(d[i])) i++;
        }
        if (!digits)
            throw new FormatException($"Número no válido en la posición {start}");
        var s = d[start..i];
        return double.Parse(s, NumberStyles.Float, CultureInfo.InvariantCulture).ToString("R", CultureInfo.InvariantCulture);
    }
}
