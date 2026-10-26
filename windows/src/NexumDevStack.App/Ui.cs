using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Shapes;
using NexumDevStack.Core.Util;

namespace NexumDevStack.App;

/// <summary>Iconos de Segoe Fluent Icons (los «simbólicos» de la ventana de Linux).</summary>
public static class Ico
{
    public const string Menu = "", Abajo = "", Derecha = "", Mas = "", Cerrar = "", Puntos = "",
        Ajustes = "", Parar = "", Buscar = "", Recargar = "", Estrella = "", Hecho = "",
        Papelera = "", Arrancar = "", Globo = "", Aviso = "", Encender = "", CarpetaAbierta = "",
        Carpeta = "", Copiar = "", Descargar = "", Subir = "", Documento = "", Info = "",
        Sol = "", Luna = "", Enlace = "", Editar = "", Limpiar = "", Codigo = "", Candado = "",
        Red = "", Biblioteca = "", Expulsar = "", Escudo = "", Error = "", Minimizar = "",
        Maximizar = "", Restaurar = "", CerrarVentana = "", Terminal = "", Base = "";
}

/// <summary>Piezas de la interfaz (como los label(), group() y nv_button() de la ventana de Linux).</summary>
public static class Ui
{
    public static FontFamily Mono => (FontFamily)Application.Current.Resources["LetraMono"];
    public static FontFamily Icons => (FontFamily)Application.Current.Resources["LetraIconos"];

    public static T Res<T>(this T e, string property, string key) where T : FrameworkElement
    {
        var dp = property switch
        {
            "Foreground" => e is Control ? Control.ForegroundProperty : TextBlock.ForegroundProperty,
            "Background" => e is Control ? Control.BackgroundProperty : e is Border ? Border.BackgroundProperty : Panel.BackgroundProperty,
            "BorderBrush" => e is Control ? Control.BorderBrushProperty : Border.BorderBrushProperty,
            "Fill" => Shape.FillProperty,
            _ => throw new ArgumentException(property),
        };
        e.SetResourceReference(dp, key);
        return e;
    }

    // ------------------------------------------------------------------ textos
    /// <summary>Texto con estilo: titulo, titulo-grande, tenue, chico, mono, seccion, verde, rojo, azul.</summary>
    public static TextBlock Text(string text, params string[] classes)
    {
        var t = new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
        t.SetResourceReference(TextBlock.ForegroundProperty, "Texto");
        foreach (var c in classes)
        {
            switch (c)
            {
                case "titulo": t.FontSize = 16; t.FontWeight = FontWeights.SemiBold; break;
                case "titulo-grande": t.FontSize = 22; t.FontWeight = FontWeights.SemiBold; break;
                case "tenue": t.SetResourceReference(TextBlock.ForegroundProperty, "TextoTenue"); break;
                case "chico": t.FontSize = 11.5; break;
                case "mono": t.FontFamily = Mono; break;
                case "negrita": t.FontWeight = FontWeights.SemiBold; break;
                case "seccion": t.FontSize = 10.5; t.FontWeight = FontWeights.Bold; t.SetResourceReference(TextBlock.ForegroundProperty, "TextoSeccion"); break;
                case "verde": t.SetResourceReference(TextBlock.ForegroundProperty, "Verde"); break;
                case "rojo": t.SetResourceReference(TextBlock.ForegroundProperty, "Rojo"); break;
                case "azul": t.SetResourceReference(TextBlock.ForegroundProperty, "Azul"); break;
                case "naranja": t.SetResourceReference(TextBlock.ForegroundProperty, "Naranja"); break;
                case "envolver": t.TextWrapping = TextWrapping.Wrap; t.TextTrimming = TextTrimming.None; break;
                case "cab": t.FontSize = 10.5; t.FontWeight = FontWeights.Bold; t.SetResourceReference(TextBlock.ForegroundProperty, "TextoSeccion"); break;
            }
        }
        return t;
    }

    public static TextBlock Wrap(string text, params string[] classes) => Text(text, classes.Append("envolver").ToArray());

    /// <summary>Icono de la fuente de iconos.</summary>
    public static TextBlock Icon(string glyph, double size = 14, string brush = "Texto")
    {
        var t = new TextBlock
        {
            Text = glyph, FontFamily = Icons, FontSize = size, VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        t.SetResourceReference(TextBlock.ForegroundProperty, brush);
        return t;
    }

    /// <summary>Punto de estado: verde si está en marcha, gris si no (con latido si se pide).</summary>
    public static Ellipse Dot(bool on, double size = 9, bool pulse = false)
    {
        var e = new Ellipse { Width = size, Height = size, VerticalAlignment = VerticalAlignment.Center };
        e.SetResourceReference(Shape.FillProperty, on ? "Verde" : "Gris");
        if (on && pulse)
        {
            var anim = new System.Windows.Media.Animation.DoubleAnimation(1, 0.25, TimeSpan.FromSeconds(0.8))
            {
                AutoReverse = true, RepeatBehavior = System.Windows.Media.Animation.RepeatBehavior.Forever,
            };
            e.BeginAnimation(UIElement.OpacityProperty, anim);
        }
        return e;
    }

    /// <summary>Etiqueta redondeada (Activa, Cargado, PrestaShop…).</summary>
    public static Border Tag(string text, bool blue = false, string? fg = null, string? bg = null)
    {
        var t = Text(text, "chico");
        t.SetResourceReference(TextBlock.ForegroundProperty, fg ?? (blue ? "Azul" : "TextoTenue"));
        var b = new Border { CornerRadius = new CornerRadius(10), Padding = new Thickness(8, 1, 8, 2), Child = t, VerticalAlignment = VerticalAlignment.Center };
        b.SetResourceReference(Border.BackgroundProperty, bg ?? (blue ? "AzulSuave" : "FondoElegido"));
        return b;
    }

    // ------------------------------------------------------------------ botones
    /// <summary>Botón con icono (de la fuente o un logotipo) y texto. style: Boton, BotonAzul, BotonPlano, BotonRojo…</summary>
    public static Button Button(object? icon, string? text, string? tip, Action? click, string style = "Boton")
    {
        var sp = new StackPanel { Orientation = Orientation.Horizontal };
        if (icon is string glyph)
            sp.Children.Add(Icon(glyph, 13, style is "BotonAzul" or "BotonRojo" ? "Blanco" : "Texto"));
        else if (icon is UIElement el)
            sp.Children.Add(el);
        if (text != null)
        {
            var t = new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(sp.Children.Count > 0 ? 7 : 0, 0, 0, 0) };
            sp.Children.Add(t);
        }
        var b = new Button { Content = sp };
        b.SetResourceReference(FrameworkElement.StyleProperty, style);
        if (tip != null) b.ToolTip = tip;
        if (click != null) b.Click += (_, _) => click();
        return b;
    }

    public static Button TextButton(string text, Action click, string style = "Boton", string? tip = null) => Button(null, text, tip, click, style);

    /// <summary>Botón con un menú (☰, ⋯, Añadir entorno…): las opciones en un Popup redondeado.</summary>
    public static Button MenuButton(object? icon, string? text, string? tip, IEnumerable<(string Text, string? Glyph, Action? Click)> items,
        string style = "Boton")
    {
        var b = Button(icon, text, tip, null, style);
        var popup = new Popup { PlacementTarget = b, Placement = PlacementMode.Bottom, StaysOpen = false, AllowsTransparency = true, PopupAnimation = PopupAnimation.Fade };
        var list = new StackPanel { Margin = new Thickness(4) };
        foreach (var (t, g, click) in items)
        {
            if (t == "-")
            {
                var sep = new Border { Height = 1, Margin = new Thickness(6, 4, 6, 4) };
                sep.SetResourceReference(Border.BackgroundProperty, "Separador");
                list.Children.Add(sep);
                continue;
            }
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            if (g != null)
            {
                var ic = new TextBlock { Text = g, FontFamily = Icons, FontSize = 13, Width = 22, VerticalAlignment = VerticalAlignment.Center };
                row.Children.Add(ic);
            }
            row.Children.Add(new TextBlock { Text = t, VerticalAlignment = VerticalAlignment.Center });
            var mb = new Button { Content = row, IsEnabled = click != null };
            mb.SetResourceReference(FrameworkElement.StyleProperty, "BotonMenu");
            mb.Click += (_, _) => { popup.IsOpen = false; click?.Invoke(); };
            list.Children.Add(mb);
        }
        var border = new Border
        {
            CornerRadius = new CornerRadius(12), BorderThickness = new Thickness(1), Child = list, Margin = new Thickness(0, 4, 8, 8),
            MinWidth = 220, Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 14, ShadowDepth = 3, Opacity = 0.35 },
        };
        border.SetResourceReference(Border.BackgroundProperty, "FondoMenu");
        border.SetResourceReference(Border.BorderBrushProperty, "Borde");
        popup.Child = border;
        Toggle(b, popup);
        return b;
    }

    /// <summary>
    /// El botón abre y cierra su menú. Con StaysOpen=false, pulsar el botón con el menú abierto lo cierra al
    /// bajar el ratón y el clic lo volvería a abrir: se ignora el clic justo después de cerrarse.
    /// </summary>
    public static void Toggle(Button b, Popup popup)
    {
        var closedAt = DateTime.MinValue;
        popup.Closed += (_, _) => closedAt = DateTime.UtcNow;
        b.Click += (_, _) =>
        {
            if ((DateTime.UtcNow - closedAt).TotalMilliseconds < 250)
                return;
            popup.IsOpen = !popup.IsOpen;
        };
    }

    /// <summary>Buscador con su lupa y su texto de ayuda (se crea una vez y se vuelve a poner al redibujar).</summary>
    public static (Grid Box, TextBox Entry) SearchBox(string placeholder, double width)
    {
        var entry = new TextBox { Width = width, Padding = new Thickness(30, 6, 8, 6) };
        var box = new Grid { HorizontalAlignment = HorizontalAlignment.Left };
        box.Children.Add(entry);
        var lens = Icon(Ico.Buscar, 13, "TextoTenue");
        lens.HorizontalAlignment = HorizontalAlignment.Left;
        lens.Margin = new Thickness(10, 0, 0, 0);
        lens.IsHitTestVisible = false;
        box.Children.Add(lens);
        var holder = Text(placeholder, "tenue");
        holder.IsHitTestVisible = false;
        holder.Margin = new Thickness(32, 0, 0, 0);
        box.Children.Add(holder);
        entry.TextChanged += (_, _) => holder.Visibility = entry.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        return (box, entry);
    }

    /// <summary>Quita un elemento de donde esté (para volver a ponerlo en la página redibujada).</summary>
    public static T Detach<T>(T e) where T : FrameworkElement
    {
        switch (e.Parent)
        {
            case Panel p: p.Children.Remove(e); break;
            case Decorator d: d.Child = null; break;
            case ContentControl c: c.Content = null; break;
        }
        return e;
    }

    // ------------------------------------------------------------------ cajas
    /// <summary>Tarjeta redondeada con borde (nv-tarjeta / nv-grupo).</summary>
    public static Border Card(UIElement child, double padding = 0, double radius = 12, string bg = "FondoTarjeta")
    {
        var b = new Border { CornerRadius = new CornerRadius(radius), BorderThickness = new Thickness(1), Padding = new Thickness(padding), Child = child };
        b.SetResourceReference(Border.BackgroundProperty, bg);
        b.SetResourceReference(Border.BorderBrushProperty, "BordeSuave");
        return b;
    }

    /// <summary>Recuadro hundido (el visor de la versión activa, los selectores del proyecto).</summary>
    public static Border Sunken(UIElement child, Thickness padding)
    {
        var b = new Border
        {
            CornerRadius = new CornerRadius(12), BorderThickness = new Thickness(1), Padding = padding, Child = child,
        };
        b.SetResourceReference(Border.BackgroundProperty, "FondoHundido");
        b.SetResourceReference(Border.BorderBrushProperty, "Borde");
        return b;
    }

    /// <summary>Línea separadora.</summary>
    public static Border Separator(bool vertical = false)
    {
        var b = vertical
            ? new Border { Width = 1, Margin = new Thickness(4, 6, 4, 6) }
            : new Border { Height = 1, Margin = new Thickness(0, 4, 0, 4) };
        b.SetResourceReference(Border.BackgroundProperty, "Separador");
        return b;
    }

    /// <summary>Apartado con título (y su explicación al pasar el ratón por la i) y una lista de filas en una tarjeta.</summary>
    public static (StackPanel Box, StackPanel List) Group(string? title, string? description = null)
    {
        var box = new StackPanel { Margin = new Thickness(0, 0, 0, 22) };
        if (title != null || description != null)
        {
            var head = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(2, 0, 0, 8) };
            if (title != null)
                head.Children.Add(Text(title, "negrita"));
            if (description != null)
            {
                var i = Icon(Ico.Info, 13, "TextoTenue");
                i.Margin = new Thickness(7, 1, 0, 0);
                i.ToolTip = description;
                i.Cursor = System.Windows.Input.Cursors.Help;
                head.Children.Add(i);
            }
            box.Children.Add(head);
        }
        var list = new StackPanel();
        box.Children.Add(Card(list));
        return (box, list);
    }

    /// <summary>Fila de un apartado: icono, título y subtítulo a la izquierda y lo que se añada a la derecha.</summary>
    public static (Border Row, StackPanel Suffix, TextBlock Title, TextBlock Sub) Row(string title, string? subtitle = null, UIElement? prefix = null,
        bool first = false)
    {
        var grid = new Grid { Margin = new Thickness(14, 9, 12, 9), MinHeight = 34 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        if (prefix != null)
        {
            if (prefix is FrameworkElement fe) fe.Margin = new Thickness(0, 0, 12, 0);
            grid.Children.Add(prefix);
        }
        var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        var t = Text(title);
        var s = Text(subtitle ?? "", "tenue", "chico");
        s.Visibility = string.IsNullOrEmpty(subtitle) ? Visibility.Collapsed : Visibility.Visible;
        texts.Children.Add(t);
        texts.Children.Add(s);
        Grid.SetColumn(texts, 1);
        grid.Children.Add(texts);
        var suffix = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(10, 0, 0, 0) };
        Grid.SetColumn(suffix, 2);
        grid.Children.Add(suffix);
        var row = new Border { Child = grid, BorderThickness = new Thickness(0, first ? 0 : 1, 0, 0) };
        row.SetResourceReference(Border.BorderBrushProperty, "BordeSuave");
        return (row, suffix, t, s);
    }

    /// <summary>Añade filas a una lista con su separador (la primera sin línea encima).</summary>
    public static void AddRow(StackPanel list, Border row)
    {
        row.BorderThickness = new Thickness(0, list.Children.Count == 0 ? 0 : 1, 0, 0);
        list.Children.Add(row);
    }

    public static StackPanel HStack(double spacing, params UIElement[] children)
    {
        var sp = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var c in children)
        {
            if (sp.Children.Count > 0 && c is FrameworkElement fe && fe.Margin == default)
                fe.Margin = new Thickness(spacing, 0, 0, 0);
            sp.Children.Add(c);
        }
        return sp;
    }

    public static StackPanel VStack(double spacing, params UIElement[] children)
    {
        var sp = new StackPanel();
        foreach (var c in children)
        {
            if (sp.Children.Count > 0 && c is FrameworkElement fe && fe.Margin == default)
                fe.Margin = new Thickness(0, spacing, 0, 0);
            sp.Children.Add(c);
        }
        return sp;
    }

    /// <summary>Desplegable de textos (id → texto).</summary>
    public static ComboBox Combo(IEnumerable<(string Id, string Text)> items, string? selected, double width = 220)
    {
        var c = new ComboBox { Width = width, VerticalAlignment = VerticalAlignment.Center };
        foreach (var (id, text) in items)
            c.Items.Add(new ComboBoxItem { Content = text, Tag = id, ToolTip = text.Length > 30 ? text : null });
        foreach (ComboBoxItem it in c.Items)
            if ((string)it.Tag == selected)
                c.SelectedItem = it;
        if (c.SelectedIndex < 0 && c.Items.Count > 0)
            c.SelectedIndex = 0;
        return c;
    }

    public static string? SelectedId(this ComboBox c) => (c.SelectedItem as ComboBoxItem)?.Tag as string;

    public static CheckBox Switch(bool on, Action<bool> changed)
    {
        var c = new CheckBox { IsChecked = on };
        c.SetResourceReference(FrameworkElement.StyleProperty, "Interruptor");
        c.Click += (_, _) => changed(c.IsChecked == true);
        return c;
    }

    // ------------------------------------------------------------------ logotipos
    static readonly Dictionary<string, Geometry> Geometries = new();

    public static Geometry? LogoGeometry(string name)
    {
        if (Geometries.TryGetValue(name, out var g))
            return g;
        if (!Logotipos.Paths.TryGetValue(name, out var d))
            return null;
        try
        {
            g = Geometry.Parse(RutaSvg.Normalize(d));
            g.Freeze();
        }
        catch (FormatException)
        {
            return null;
        }
        Geometries[name] = g;
        return g;
    }

    /// <summary>Logotipo de un paquete en su color (más claro con el tema oscuro), o de un color dado (mono).</summary>
    public static FrameworkElement Logo(string name, double size = 18, string? monoBrush = null)
    {
        var g = LogoGeometry(name);
        if (g == null)
            return Icon(Ico.Documento, size * 0.8);
        var path = new System.Windows.Shapes.Path { Data = g, Stretch = Stretch.Uniform, Width = size, Height = size, VerticalAlignment = VerticalAlignment.Center };
        if (monoBrush != null)
            path.SetResourceReference(Shape.FillProperty, monoBrush);
        else
        {
            var (light, dark) = Logotipos.Colors.TryGetValue(name, out var c) ? c : ("#888888", "#AAAAAA");
            path.Fill = new SolidColorBrush((Color)ColorConverter.ConvertFromString(Tema.Dark ? dark : light));
        }
        return path;
    }

    /// <summary>Icono de un proyecto por su tipo: WordPress, PrestaShop o una carpeta.</summary>
    public static FrameworkElement KindIcon(string kind, double size = 18) =>
        kind == "wp" ? Logo("wordpress", size) : kind == "ps" ? Logo("prestashop", size) : Icon(Ico.Carpeta, size * 0.85, "TextoTenue");

    /// <summary>Página con un ancho mínimo que crece con la ventana hasta 1500 y después se centra.</summary>
    public static (ScrollViewer Scroll, StackPanel Content) Page(double minWidth = 860)
    {
        var content = new StackPanel { Margin = new Thickness(26), MinWidth = minWidth };
        var sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, Content = content };
        sv.SizeChanged += (_, e) =>
        {
            var side = Math.Max(26, (e.NewSize.Width - 1500) / 2);
            content.Margin = new Thickness(side, 26, side, 26);
        };
        return (sv, content);
    }

    /// <summary>Cabecera de una página: título grande con su icono y la explicación debajo.</summary>
    public static Grid PageTitle(FrameworkElement icon, string title, string sub, params UIElement[] right)
    {
        var g = new Grid { Margin = new Thickness(0, 0, 0, 18) };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        icon.Margin = new Thickness(0, 0, 10, 0);
        var t = VStack(2, HStack(0, icon, Text(title, "titulo-grande")), Text(sub, "chico", "tenue"));
        g.Children.Add(t);
        var r = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        foreach (var e in right)
        {
            if (e is FrameworkElement fe) fe.Margin = new Thickness(8, 0, 0, 0);
            r.Children.Add(e);
        }
        Grid.SetColumn(r, 1);
        g.Children.Add(r);
        return g;
    }

    /// <summary>Tabla sencilla: una fila de cabecera y filas con columnas de ancho fijo (la última se estira).</summary>
    public static Grid TableRow(double[] widths, IEnumerable<UIElement> cells, bool header = false, Thickness? margin = null)
    {
        var g = new Grid { Margin = margin ?? new Thickness(14, header ? 8 : 7, 14, header ? 8 : 7) };
        for (int i = 0; i < widths.Length; i++)
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = widths[i] > 0 ? new GridLength(widths[i]) : new GridLength(1, GridUnitType.Star) });
        var n = 0;
        foreach (var c in cells)
        {
            if (c is FrameworkElement fe)
            {
                fe.VerticalAlignment = VerticalAlignment.Center;
                if (fe.Margin == default) fe.Margin = new Thickness(0, 0, 12, 0);
            }
            Grid.SetColumn(c, n++);
            g.Children.Add(c);
        }
        return g;
    }

    public static UIElement Cell(string text, params string[] classes) =>
        text.Length > 0 ? Text(text, classes) : Text("—", "tenue");
}
