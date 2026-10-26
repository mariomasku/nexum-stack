using System.Windows;
using System.Windows.Media;
using NexumDevStack.Core.Pila;
using NexumDevStack.Core.Util;

namespace NexumDevStack.App;

/// <summary>
/// Colores de la ventana (los mismos que la de Linux): tema oscuro por defecto y claro desde el menú ☰, azul
/// #0A84FF de acento y verde #30D158 solo para lo que está en marcha o bien. Se guardan como recursos con
/// nombre y los estilos los usan con DynamicResource: cambiar de tema cambia toda la ventana.
/// </summary>
public static class Tema
{
    public static readonly Color Blue = (Color)ColorConverter.ConvertFromString("#0A84FF");
    public static readonly Color Green = (Color)ColorConverter.ConvertFromString("#30D158");
    public static readonly Color Red = (Color)ColorConverter.ConvertFromString("#FF453A");
    public static readonly Color Orange = (Color)ColorConverter.ConvertFromString("#FF9F0A");

    public static bool Dark { get; private set; } = true;

    public static event Action? Changed;

    static Color C(string hex) => (Color)ColorConverter.ConvertFromString(hex);

    /// <summary>Mezcla dos colores (como mix() de GTK): t = cuánto del segundo.</summary>
    public static Color Mix(Color a, Color b, double t) => Color.FromArgb(255,
        (byte)(a.R + (b.R - a.R) * t), (byte)(a.G + (b.G - a.G) * t), (byte)(a.B + (b.B - a.B) * t));

    public static Color Alpha(Color c, double a) => Color.FromArgb((byte)(255 * a), c.R, c.G, c.B);

    public static void Apply(bool dark)
    {
        Dark = dark;
        var r = Application.Current.Resources;
        var fg = dark ? C("#ECECEE") : C("#1D1D1F");
        var bg = dark ? C("#1E1E20") : C("#F6F5F4");
        void Set(string key, Color c) => r[key] = Freeze(new SolidColorBrush(c));
        void SetC(string key, Color c) => r[key] = c;
        Set("Fondo", bg);
        Set("FondoLateral", dark ? C("#252527") : C("#EDECEA"));
        Set("FondoCabecera", dark ? C("#2B2B2E") : C("#E9E8E6"));
        Set("FondoTarjeta", dark ? C("#28282B") : C("#FFFFFF"));
        Set("FondoFila", dark ? C("#232325") : C("#FBFBFA"));
        Set("FondoHundido", dark ? C("#161618") : C("#E3E2E0"));
        Set("FondoCampo", dark ? C("#18181A") : C("#FFFFFF"));
        Set("FondoMenu", dark ? C("#2E2E31") : C("#FFFFFF"));
        Set("FondoHover", Alpha(fg, 0.06));
        Set("FondoElegido", Alpha(fg, 0.08));
        Set("FondoCargado", Alpha(Blue, 0.12));
        Set("Borde", dark ? C("#38383B") : C("#D9D8D6"));
        Set("BordeSuave", dark ? C("#2F2F32") : C("#E4E3E1"));
        Set("BordeBoton", Alpha(fg, 0.22));
        Set("Texto", fg);
        Set("TextoTenue", Alpha(fg, 0.58));
        Set("TextoSeccion", Alpha(fg, 0.45));
        Set("Separador", Alpha(fg, 0.10));
        Set("Azul", Blue);
        Set("AzulSuave", Alpha(Blue, dark ? 0.18 : 0.12));
        Set("AzulHover", Alpha(Blue, 0.10));
        Set("AzulClaro", Mix(Blue, C("#FFFFFF"), 0.12));
        Set("Marca", Mix(Blue, fg, 0.22));
        Set("Verde", Green);
        Set("VerdeSuave", Alpha(Green, 0.14));
        Set("Rojo", Red);
        Set("RojoSuave", Alpha(Red, 0.14));
        Set("Naranja", Orange);
        Set("Gris", Alpha(fg, 0.30));
        Set("Blanco", Colors.White);
        Set("Consola", C("#1D2228"));
        Set("TextoConsola", C("#D7DEE6"));
        Set("FondoToolTip", C("#3E3E43"));
        Set("FondoBarra", Alpha(fg, 0.10));
        SetC("ColorTexto", fg);
        SetC("ColorFondo", bg);
        Changed?.Invoke();
    }

    static Brush Freeze(Brush b)
    {
        b.Freeze();
        return b;
    }

    public static Brush Brush(string key) => (Brush)Application.Current.Resources[key];

    public static Color ColorOf(string key) => ((SolidColorBrush)Application.Current.Resources[key]).Color;

    // ------------------------------------------------------------------ preferencia guardada
    public static bool LoadPreference(Disposicion l)
    {
        var saved = Ficheros.ReadSmallText(l.ThemeFile, 100)?.Trim();
        return saved != "claro";
    }

    public static void SavePreference(Disposicion l)
    {
        try
        {
            Directory.CreateDirectory(l.UserDir);
            File.WriteAllText(l.ThemeFile, Dark ? "oscuro\n" : "claro\n");
        }
        catch (IOException) { }
    }
}
