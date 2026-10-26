using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace NexumDevStack.App;

/// <summary>
/// Diálogo de Nexum: centrado sobre la ventana, redondeado, con el título y la explicación centrados y los
/// botones abajo (Cancelar y el principal, que dice lo que hace). Como los de la ventana de Linux.
/// </summary>
public sealed class Dialogo : Window
{
    readonly StackPanel _body;
    readonly StackPanel _buttons;
    Button? _ok;

    public Dialogo(Window? owner, string? title, string? text, double width = 480)
    {
        Owner = owner;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.Height;
        Width = width + 40;
        ShowInTaskbar = owner == null;
        WindowStartupLocation = owner != null ? WindowStartupLocation.CenterOwner : WindowStartupLocation.CenterScreen;
        FontFamily = (FontFamily)Application.Current.Resources["Letra"];
        FontSize = 13;
        Title = title ?? "Nexum Dev Stack";
        SetResourceReference(ForegroundProperty, "Texto");

        _body = new StackPanel { Margin = new Thickness(28, 24, 28, 8) };
        if (title != null)
        {
            var t = Ui.Wrap(title, "titulo");
            t.TextAlignment = TextAlignment.Center;
            t.HorizontalAlignment = HorizontalAlignment.Center;
            t.Margin = new Thickness(0, 0, 0, 10);
            _body.Children.Add(t);
        }
        if (!string.IsNullOrEmpty(text))
        {
            var p = Ui.Wrap(text, "tenue");
            p.TextAlignment = TextAlignment.Center;
            p.HorizontalAlignment = HorizontalAlignment.Center;
            p.Margin = new Thickness(0, 0, 0, 14);
            p.LineHeight = 19;
            _body.Children.Add(p);
        }
        _buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(28, 8, 28, 22) };
        var outer = new StackPanel();
        outer.Children.Add(_body);
        outer.Children.Add(_buttons);
        var frame = new Border
        {
            CornerRadius = new CornerRadius(14), BorderThickness = new Thickness(1), Margin = new Thickness(20), Child = outer,
            Effect = new DropShadowEffect { BlurRadius = 24, ShadowDepth = 4, Opacity = 0.45 },
        };
        frame.SetResourceReference(Border.BackgroundProperty, "Fondo");
        frame.SetResourceReference(Border.BorderBrushProperty, "Borde");
        frame.MouseLeftButtonDown += (_, e) =>
        {
            if (e.OriginalSource is Border or StackPanel or TextBlock)
                try { DragMove(); } catch (InvalidOperationException) { }
        };
        Content = frame;
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape) { Close(false); e.Handled = true; }
        };
    }

    /// <summary>Cierra con ese resultado (si sigue abierto).</summary>
    public void Close(bool result)
    {
        try
        {
            DialogResult = result;
        }
        catch (InvalidOperationException)
        {
            Close();
        }
    }

    /// <summary>Añade algo debajo del texto (campos, listas, casillas).</summary>
    public Dialogo Add(UIElement e)
    {
        if (e is FrameworkElement fe && fe.Margin == default)
            fe.Margin = new Thickness(0, 4, 0, 8);
        _body.Children.Add(e);
        return this;
    }

    /// <summary>Botones: el de cancelar (si hay) y el principal, que dice lo que hace.</summary>
    public Dialogo Buttons(string okLabel, string? cancelLabel = "Cancelar", bool destructive = false)
    {
        if (cancelLabel != null)
        {
            var c = Ui.TextButton(cancelLabel, () => Close(false));
            c.MinWidth = 96;
            _buttons.Children.Add(c);
        }
        _ok = Ui.TextButton(okLabel, () => Close(true), destructive ? "BotonRojo" : "BotonAzul");
        _ok.MinWidth = 110;
        _ok.Margin = new Thickness(10, 0, 0, 0);
        _ok.IsDefault = !destructive;
        _buttons.Children.Add(_ok);
        return this;
    }

    public bool OkEnabled
    {
        set { if (_ok != null) _ok.IsEnabled = value; }
    }

    public bool Run()
    {
        try
        {
            return ShowDialog() == true;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }

    // ------------------------------------------------------------------ los de siempre
    public static bool Confirm(Window? owner, string title, string text, string okLabel, bool destructive = false, UIElement? extra = null)
    {
        var d = new Dialogo(owner, title, text);
        if (extra != null) d.Add(extra);
        return d.Buttons(okLabel, destructive: destructive).Run();
    }

    public static void Message(Window? owner, string title, string text = "", bool error = false)
    {
        var d = new Dialogo(owner, title, text, text.Length > 300 ? 620 : 480);
        if (error && text.Length > 300)
        {
            // (un error largo, en un cuadro con desplazamiento que se puede copiar)
            var box = new TextBox
            {
                Text = text, IsReadOnly = true, TextWrapping = TextWrapping.Wrap, FontFamily = Ui.Mono, FontSize = 12, MaxHeight = 320,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            };
            d = new Dialogo(owner, title, null, 620);
            d.Add(box);
        }
        d.Buttons("Cerrar", null).Run();
    }

    /// <summary>
    /// Pregunta un nombre. validate(texto) → (vale, pista, es un error). Devuelve el texto o null si se cancela.
    /// </summary>
    public static string? Input(Window? owner, string title, string text, string placeholder, string okLabel,
        Func<string, (bool Ok, string Hint, bool Error)> validate, string initial = "")
    {
        var d = new Dialogo(owner, title, text);
        var box = new TextBox { Text = initial, ToolTip = placeholder, MaxLength = 64 };
        var hint = Ui.Wrap("", "chico", "tenue");
        hint.Margin = new Thickness(2, 6, 0, 4);
        var holder = Ui.Text(placeholder, "tenue");
        holder.IsHitTestVisible = false;
        holder.Margin = new Thickness(10, 0, 0, 0);
        var grid = new Grid();
        grid.Children.Add(box);
        grid.Children.Add(holder);
        d.Add(grid);
        d.Add(hint);
        d.Buttons(okLabel);
        void Update()
        {
            holder.Visibility = box.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
            var (ok, h, err) = validate(box.Text.Trim());
            hint.Text = h;
            hint.SetResourceReference(TextBlock.ForegroundProperty, err ? "Rojo" : "TextoTenue");
            d.OkEnabled = ok;
        }
        box.TextChanged += (_, _) => Update();
        d.Loaded += (_, _) => box.Focus();
        Update();
        return d.Run() ? box.Text.Trim() : null;
    }

    /// <summary>Opción en su tarjeta (la elegida, con el borde azul), como .opcion de Linux.</summary>
    public static (Border Card, RadioButton Radio) Option(string text, string? sub, string group, bool selected)
    {
        var rb = new RadioButton { GroupName = group, IsChecked = selected };
        var content = new StackPanel();
        content.Children.Add(Ui.Text(text));
        if (!string.IsNullOrEmpty(sub))
            content.Children.Add(Ui.Text(sub, "chico", "tenue"));
        rb.Content = content;
        var card = new Border { CornerRadius = new CornerRadius(10), BorderThickness = new Thickness(1), Padding = new Thickness(14, 10, 14, 10), Child = rb, Margin = new Thickness(0, 0, 0, 8) };
        void Paint()
        {
            card.SetResourceReference(Border.BorderBrushProperty, rb.IsChecked == true ? "Azul" : "Borde");
            card.SetResourceReference(Border.BackgroundProperty, rb.IsChecked == true ? "AzulHover" : "FondoFila");
        }
        rb.Checked += (_, _) => Paint();
        rb.Unchecked += (_, _) => Paint();
        card.MouseLeftButtonUp += (_, _) => rb.IsChecked = true;
        Paint();
        return (card, rb);
    }
}
