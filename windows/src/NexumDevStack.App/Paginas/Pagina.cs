using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;

namespace NexumDevStack.App.Paginas;

/// <summary>Un apartado de la ventana: se rehace entero con los datos de la ventana (Build).</summary>
public abstract class Pagina
{
    protected Pagina(VentanaPrincipal w, double minWidth = 860)
    {
        W = w;
        (Scroll, Content) = Ui.Page(minWidth);
    }

    protected VentanaPrincipal W { get; }
    protected ScrollViewer Scroll { get; }
    protected StackPanel Content { get; }
    public FrameworkElement View => Scroll;

    public abstract void Build();

    /// <summary>Al entrar en el apartado.</summary>
    public virtual void Shown() { }

    /// <summary>Mientras se lee: el giro y «Leyendo…».</summary>
    protected void Loading(string text = "Leyendo…")
    {
        Content.Children.Clear();
        var t = Ui.Text(text, "tenue");
        t.HorizontalAlignment = HorizontalAlignment.Center;
        t.Margin = new Thickness(0, 40, 0, 0);
        Content.Children.Add(t);
    }

    /// <summary>Tarjeta grande para preparar C:\NexumDevStack la primera vez.</summary>
    protected void NotPrepared()
    {
        var box = new StackPanel { Margin = new Thickness(28) };
        var img = new Image { Width = 64, Height = 64, Margin = new Thickness(0, 0, 0, 12) };
        try { img.Source = new System.Windows.Media.Imaging.BitmapImage(new Uri("pack://application:,,,/nexum.png")); } catch (Exception) { }
        box.Children.Add(img);
        var t = Ui.Text("Prepara Nexum Dev Stack en este equipo", "titulo-grande");
        t.HorizontalAlignment = HorizontalAlignment.Center;
        box.Children.Add(t);
        var p = Ui.Wrap($"Se crea {W.Motor.L.Root} con sus carpetas: versiones y programa, solo de administrador (tu usuario no puede cambiar " +
                        "los programas), y datos, config, htdocs, registros y tmp, solo de tu usuario. Windows pide permiso de administrador una vez. " +
                        "Después, instala la primera versión de PHP.", "tenue");
        p.TextAlignment = TextAlignment.Center;
        p.MaxWidth = 620;
        p.Margin = new Thickness(0, 10, 0, 18);
        box.Children.Add(p);
        var b = Ui.Button(Ico.Hecho, "Preparar", null, () => W.RunTask($"Preparando {W.Motor.L.Root}", new[] { "preparar" },
            new OpcionesTarea { DoneText = "Nexum Dev Stack está preparado" }), "BotonAzul");
        b.HorizontalAlignment = HorizontalAlignment.Center;
        b.MinWidth = 160;
        box.Children.Add(b);
        var card = Ui.Card(box, 0, 14);
        card.Margin = new Thickness(0, 0, 0, 22);
        Content.Children.Add(card);
    }

    protected bool Prepared => W.State?.Prepared == true;
}

/// <summary>Las novedades en Markdown («## versión · fecha», viñetas, **negrita** y `código`) en un documento.</summary>
public static class Markdown
{
    public static FlowDocument ToDocument(string text)
    {
        var doc = new FlowDocument { FontFamily = (FontFamily)Application.Current.Resources["Letra"], FontSize = 13, PagePadding = new Thickness(4) };
        foreach (var raw in text.Replace("\r\n", "\n").Split('\n'))
        {
            var line = raw.TrimEnd();
            if (line.Trim().Length == 0)
                continue;
            if (line.StartsWith("## "))
            {
                var parts = line[3..].Split(" · ", 2);
                var h = new Paragraph { Margin = new Thickness(0, 18, 0, 8) };
                h.Inlines.Add(new Run(parts[0]) { FontSize = 18, FontWeight = FontWeights.SemiBold });
                if (parts.Length > 1)
                {
                    var date = new Run("   " + parts[1]) { FontSize = 12 };
                    date.SetResourceReference(TextElement.ForegroundProperty, "TextoTenue");
                    h.Inlines.Add(date);
                }
                doc.Blocks.Add(h);
                continue;
            }
            var m = Regex.Match(line, @"^( *)- (.*)$");
            var p = new Paragraph { Margin = new Thickness(0, 4, 0, 4), LineHeight = 20 };
            string body;
            if (m.Success)
            {
                var depth = Math.Min(m.Groups[1].Value.Length / 2, 1);
                p.Margin = new Thickness(depth == 0 ? 18 : 40, 6, 0, 2);
                p.TextIndent = -14;
                var dot = new Run(depth == 0 ? "•  " : "◦  ") { FontWeight = FontWeights.Bold };
                dot.SetResourceReference(TextElement.ForegroundProperty, "Azul");
                p.Inlines.Add(dot);
                body = m.Groups[2].Value;
            }
            else
                body = line;
            foreach (var part in Regex.Split(body, @"(\*\*[^*]+\*\*|`[^`]+`)"))
            {
                if (part.Length == 0) continue;
                if (part.StartsWith("**") && part.EndsWith("**") && part.Length > 4)
                    p.Inlines.Add(new Run(part[2..^2]) { FontWeight = FontWeights.SemiBold });
                else if (part.StartsWith('`') && part.EndsWith('`') && part.Length > 2)
                {
                    var r = new Run(part[1..^1]) { FontFamily = Ui.Mono, FontSize = 12 };
                    r.SetResourceReference(TextElement.BackgroundProperty, "FondoElegido");
                    p.Inlines.Add(r);
                }
                else
                    p.Inlines.Add(new Run(part));
            }
            doc.Blocks.Add(p);
        }
        return doc;
    }
}

/// <summary>Docker: llega en la fase 2.</summary>
public sealed class PaginaDocker : Pagina
{
    public PaginaDocker(VentanaPrincipal w) : base(w) { }

    public override void Build()
    {
        Content.Children.Clear();
        Content.Children.Add(Ui.PageTitle(Ui.Logo("docker", 28), "Docker", "Proyectos con cualquier versión de PHP en contenedores, a la vez que las versiones LAMPP"));
        var box = new StackPanel { Margin = new Thickness(28) };
        var logo = Ui.Logo("docker", 56);
        logo.HorizontalAlignment = HorizontalAlignment.Center;
        logo.Margin = new Thickness(0, 0, 0, 14);
        box.Children.Add(logo);
        var t = Ui.Text("Próximamente", "titulo-grande");
        t.HorizontalAlignment = HorizontalAlignment.Center;
        box.Children.Add(t);
        var p = Ui.Wrap("Como en Linux y macOS: cada proyecto con su PHP (de la 5.6 a la 8.5), su MariaDB y su phpMyAdmin en " +
                        "contenedores de Docker Desktop, abierto por su dominio <carpeta>.docker.local con el Apache de la versión activa. " +
                        "Llega en la fase 2 de la versión para Windows, junto con el correo de pruebas (Mailpit).", "tenue");
        p.TextAlignment = TextAlignment.Center;
        p.MaxWidth = 620;
        p.Margin = new Thickness(0, 10, 0, 0);
        box.Children.Add(p);
        Content.Children.Add(Ui.Card(box, 0, 14));
    }
}
