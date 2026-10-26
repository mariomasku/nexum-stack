using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shell;
using System.Windows.Threading;
using NexumDevStack.App.Paginas;
using NexumDevStack.Core;
using NexumDevStack.Core.Pila;
using NexumDevStack.Core.Proyectos;
using NexumDevStack.Core.Util;
using NexumDevStack.Windows;

namespace NexumDevStack.App;

/// <summary>
/// La ventana (como App2 de Linux, desde la 1.54): arriba, la marca, los avisos, el visor de la versión
/// activa (sus servicios en la flecha), el menú ☰ y Localhost; a la izquierda, los apartados (ENTORNO:
/// Proyectos, Versiones de PHP, Bases de datos, Docker; SISTEMA: Dominios y hosts, Configuración).
/// </summary>
public sealed class VentanaPrincipal : Window
{
    public Motor Motor { get; }

    // Lo que se lee (en segundo plano) y enseñan las páginas
    public Estado? State { get; private set; }
    public EstadoProyectos? Projects { get; private set; }
    public EstadoHosts? HostsState { get; private set; }
    public List<RamaInfo>? Branches { get; private set; }
    public string? BranchesError { get; private set; }
    public Dictionary<string, (string Php, string Date)> PhpDates { get; private set; } = new();
    public Dictionary<(string Folder, string Db), (long Bytes, long When)> DbSizes { get; private set; } = new();
    public bool Busy { get; private set; }

    readonly Dictionary<string, (Button Nav, Pagina Page)> _tabs = new();
    readonly Grid _pages = new();
    string _tab = "proyectos";
    readonly DispatcherTimer _tick;
    bool _loading;

    // Cabecera
    TextBlock _brandSub = null!, _statusLbl = null!, _statusSub = null!, _warnNum = null!;
    Button _warnBtn = null!, _powerBtn = null!;
    Popup _warnPop = null!, _servicesPop = null!;
    StackPanel _warnBox = null!, _servicesBox = null!;
    readonly Dictionary<string, Border> _dots = new();
    Border _root = null!;
    Button _maxBtn = null!;
    Border _toast = null!;
    TextBlock _toastText = null!;
    DispatcherTimer? _toastTimer;

    public VentanaPrincipal(Motor motor)
    {
        Motor = motor;
        Title = "Nexum Dev Stack";
        Width = 1240;
        Height = 840;
        MinWidth = 980;
        MinHeight = 600;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        FontFamily = (FontFamily)Application.Current.Resources["Letra"];
        FontSize = 13;
        SetResourceReference(ForegroundProperty, "Texto");
        SetResourceReference(BackgroundProperty, "Fondo");
        try
        {
            Icon = BitmapFrame.Create(new Uri("pack://application:,,,/nexum.ico"));
        }
        catch (Exception) { }
        WindowChrome.SetWindowChrome(this, new WindowChrome
        {
            CaptionHeight = 64, ResizeBorderThickness = new Thickness(6), GlassFrameThickness = new Thickness(0), CornerRadius = new CornerRadius(0),
            UseAeroCaptionButtons = false,
        });
        BuildUi();
        StateChanged += (_, _) =>
        {
            // (maximizada, Windows la pone un poco más grande que la pantalla: el borde lo compensa)
            _root.BorderThickness = WindowState == WindowState.Maximized ? new Thickness(7) : new Thickness(1);
            _maxBtn.Content = WindowState == WindowState.Maximized ? Ico.Restaurar : Ico.Maximizar;
        };
        Tema.Changed += () => Rebuild();
        _tick = new DispatcherTimer { Interval = TimeSpan.FromSeconds(20) };
        _tick.Tick += (_, _) =>
        {
            if (!Busy && IsActive)
                Reload();
        };
        Loaded += (_, _) =>
        {
            ElevacionWindows.OwnerWindow = new System.Windows.Interop.WindowInteropHelper(this).Handle;
            Motor.Launcher = new LanzadorVentana(this);
            Reload(branches: true);
            _tick.Start();
        };
        Activated += (_, _) =>
        {
            if (!Busy && State != null)
                Reload();
        };
    }

    /// <summary>Las operaciones elevadas que la ventana hace sin tarea (pocas): con su ventana como dueña.</summary>
    sealed class LanzadorVentana : Core.Elevacion.ILanzadorElevado
    {
        readonly VentanaPrincipal _w;
        public LanzadorVentana(VentanaPrincipal w) => _w = w;

        public bool Launch(IReadOnlyList<string> args, out string detail, out Func<int?>? exitCode)
        {
            exitCode = null;
            if (!_w.Motor.Pf.Elevation.Launch(_w.Motor.ElevatedExe(args), args, out detail, out var p))
                return false;
            if (p != null)
                exitCode = () => { try { return p.HasExited ? p.ExitCode : null; } catch (InvalidOperationException) { return null; } };
            return true;
        }
    }

    // ------------------------------------------------------------------ ventana
    void BuildUi()
    {
        var grid = new Grid();
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(64) });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var header = BuildHeader();
        grid.Children.Add(header);
        var body = new Grid();
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(232) });
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        body.Children.Add(BuildSidebar());
        Grid.SetColumn(_pages, 1);
        body.Children.Add(_pages);
        _toastText = Ui.Text("", "negrita");
        _toastText.SetResourceReference(TextBlock.ForegroundProperty, "Texto");
        _toast = new Border
        {
            CornerRadius = new CornerRadius(12), Padding = new Thickness(18, 10, 18, 10), Child = _toastText, HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 0, 40), Visibility = Visibility.Collapsed, BorderThickness = new Thickness(1),
            Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 16, ShadowDepth = 2, Opacity = 0.4 },
        };
        _toast.SetResourceReference(Border.BackgroundProperty, "FondoMenu");
        _toast.SetResourceReference(Border.BorderBrushProperty, "Borde");
        Grid.SetColumn(_toast, 1);
        body.Children.Add(_toast);
        Grid.SetRow(body, 1);
        grid.Children.Add(body);
        _root = new Border { Child = grid, BorderThickness = new Thickness(1) };
        _root.SetResourceReference(Border.BackgroundProperty, "Fondo");
        _root.SetResourceReference(Border.BorderBrushProperty, "Borde");
        Content = _root;

        foreach (var (key, page) in new (string, Pagina)[]
                 {
                     ("proyectos", new PaginaProyectos(this)), ("versiones", new PaginaVersiones(this)), ("bbdd", new PaginaBbdd(this)),
                     ("docker", new PaginaDocker(this)), ("dominios", new PaginaDominios(this)), ("config", new PaginaConfiguracion(this)),
                 })
        {
            page.View.Visibility = key == _tab ? Visibility.Visible : Visibility.Collapsed;
            _pages.Children.Add(page.View);
            _tabs[key] = (_tabs.TryGetValue(key, out var t) ? t.Nav : null!, page);
        }
        PaintNav();
    }

    static void Chrome(UIElement e) => WindowChrome.SetIsHitTestVisibleInChrome((IInputElement)e, true);

    Grid BuildHeader()
    {
        var hb = new Grid();
        hb.SetResourceReference(Panel.BackgroundProperty, "FondoCabecera");
        hb.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        hb.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        hb.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var line = new Border { BorderThickness = new Thickness(0, 0, 0, 1), VerticalAlignment = VerticalAlignment.Bottom };
        line.SetResourceReference(Border.BorderBrushProperty, "Borde");
        Grid.SetColumnSpan(line, 3);
        hb.Children.Add(line);

        // Marca: el logotipo, «Nexum» en negrita y «Dev Stack» sin negrita en azul, y debajo lo que es y su versión
        var brand = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(16, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        var img = new Image { Width = 32, Height = 32, Margin = new Thickness(0, 0, 10, 0) };
        try { img.Source = new BitmapImage(new Uri("pack://application:,,,/nexum.png")); } catch (Exception) { }
        brand.Children.Add(img);
        var name = new StackPanel { Orientation = Orientation.Horizontal };
        var n1 = Ui.Text("Nexum", "titulo");
        var n2 = Ui.Text("Dev Stack", "titulo");
        n2.FontWeight = FontWeights.Normal;
        n2.SetResourceReference(TextBlock.ForegroundProperty, "Marca");
        n2.Margin = new Thickness(5, 0, 0, 0);
        name.Children.Add(n1);
        name.Children.Add(n2);
        _brandSub = Ui.Text($"{AppInfo.Subtitle}  ·  v{AppInfo.Version}", "chico", "tenue");
        brand.Children.Add(Ui.VStack(0, name, _brandSub));
        hb.Children.Add(brand);

        // En medio: los avisos, el visor de la versión activa y el menú ☰
        var center = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        _warnNum = Ui.Text("0", "chico", "negrita");
        _warnNum.Foreground = Brushes.White;
        var badge = new Border { CornerRadius = new CornerRadius(9), Padding = new Thickness(6, 0, 6, 1), Child = _warnNum, Margin = new Thickness(5, 0, 0, 0) };
        badge.SetResourceReference(Border.BackgroundProperty, "Rojo");
        _warnBtn = Ui.Button(Ui.HStack(0, Ui.Icon(Ico.Aviso, 14, "Naranja"), badge), null, "Avisos", null, "BotonPlano");
        _warnBtn.Visibility = Visibility.Collapsed;
        _warnBox = new StackPanel { Margin = new Thickness(14), Width = 560 };
        _warnPop = Pop(_warnBtn, new ScrollViewer { Content = _warnBox, MaxHeight = 560, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        Ui.Toggle(_warnBtn, _warnPop);
        Chrome(_warnBtn);
        center.Children.Add(_warnBtn);

        var pill = new StackPanel { Orientation = Orientation.Horizontal };
        pill.Children.Add(Ui.Logo("php", 20));
        _statusLbl = Ui.Text("…", "negrita");
        _statusLbl.Margin = new Thickness(8, 0, 0, 0);
        pill.Children.Add(_statusLbl);
        _statusSub = Ui.Text("", "mono", "chico", "tenue");
        _statusSub.Margin = new Thickness(8, 0, 0, 0);
        pill.Children.Add(_statusSub);
        pill.Children.Add(Ui.Separator(vertical: true));
        foreach (var svc in new[] { "Apache", "MariaDB" })
        {
            var dot = new Border { Width = 9, Height = 9, CornerRadius = new CornerRadius(5), Margin = new Thickness(6, 0, 5, 0), VerticalAlignment = VerticalAlignment.Center };
            dot.SetResourceReference(Border.BackgroundProperty, "Gris");
            _dots[svc] = dot;
            pill.Children.Add(dot);
            pill.Children.Add(Ui.Text(svc, "chico"));
        }
        _powerBtn = Ui.Button(Ico.Encender, "…", null, OnPower);
        _powerBtn.Margin = new Thickness(10, 0, 0, 0);
        _powerBtn.Padding = new Thickness(10, 3, 10, 3);
        _powerBtn.MinHeight = 28;
        pill.Children.Add(_powerBtn);
        var svcBtn = Ui.Button(Ico.Abajo, null, "Servicios de la versión activa", null, "BotonPlano");
        svcBtn.MinHeight = 28;
        svcBtn.Margin = new Thickness(2, 0, 0, 0);
        _servicesBox = new StackPanel { Margin = new Thickness(14), Width = 540 };
        _servicesPop = Pop(svcBtn, _servicesBox);
        _servicesPop.Opened += (_, _) => BuildServices();
        Ui.Toggle(svcBtn, _servicesPop);
        pill.Children.Add(svcBtn);
        var sunken = Ui.Sunken(pill, new Thickness(10, 3, 4, 3));
        Chrome(sunken);
        center.Children.Add(sunken);

        var menu = Ui.MenuButton(Ui.Icon(Ico.Menu, 16), null, "Menú", MenuItems(), "BotonPlano");
        menu.Margin = new Thickness(8, 0, 0, 0);
        Chrome(menu);
        center.Children.Add(menu);
        Grid.SetColumn(center, 1);
        hb.Children.Add(center);

        // A la derecha: Localhost y los botones de la ventana
        var right = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var local = Ui.Button(Ui.Logo("globo", 16), "Localhost", "Abrir http://localhost/", () => OpenUri("http://localhost/"), "BotonPlano");
        local.Margin = new Thickness(0, 0, 14, 0);
        Chrome(local);
        right.Children.Add(local);
        var min = new Button { Content = Ico.Minimizar };
        min.SetResourceReference(StyleProperty, "BotonTitulo");
        min.Click += (_, _) => WindowState = WindowState.Minimized;
        _maxBtn = new Button { Content = Ico.Maximizar };
        _maxBtn.SetResourceReference(StyleProperty, "BotonTitulo");
        _maxBtn.Click += (_, _) => WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
        var close = new Button { Content = Ico.CerrarVentana };
        close.SetResourceReference(StyleProperty, "BotonCerrar");
        close.Click += (_, _) => Close();
        foreach (var b in new[] { min, _maxBtn, close })
        {
            b.VerticalAlignment = VerticalAlignment.Top;
            Chrome(b);
            right.Children.Add(b);
        }
        local.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(right, 2);
        hb.Children.Add(right);
        hb.MouseLeftButtonDown += (_, e) =>
        {
            if (e.ClickCount == 2)
                WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
        };
        return hb;
    }

    static Popup Pop(UIElement target, UIElement content)
    {
        var border = new Border
        {
            CornerRadius = new CornerRadius(12), BorderThickness = new Thickness(1), Child = content, Margin = new Thickness(8),
            Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 16, ShadowDepth = 3, Opacity = 0.4 },
        };
        border.SetResourceReference(Border.BackgroundProperty, "FondoMenu");
        border.SetResourceReference(Border.BorderBrushProperty, "Borde");
        return new Popup
        {
            PlacementTarget = target, Placement = PlacementMode.Bottom, StaysOpen = false, AllowsTransparency = true, Child = border,
            PopupAnimation = PopupAnimation.Fade,
        };
    }

    IEnumerable<(string, string?, Action?)> MenuItems() => new (string, string?, Action?)[]
    {
        (Tema.Dark ? "Tema claro" : "Tema oscuro", Tema.Dark ? Ico.Sol : Ico.Luna, ToggleTheme),
        ("-", null, null),
        ("Editar vhosts", Ico.Editar, () => EditVhosts()),
        ("Editar hosts", Ico.Red, () => EditHosts()),
        ("-", null, null),
        ("Volver a leer las versiones", Ico.Recargar, () => Reload(branches: true)),
        ("Buscar actualizaciones", Ico.Descargar, () => Dialogo.Message(this, "Buscar actualizaciones",
            "La actualización firmada del programa llega en la fase 3. Mientras, descarga la versión nueva y ábrela: copia la nueva a C:\\NexumDevStack\\programa al pedir permiso de administrador.")),
        ("Abrir PowerShell", Ico.Terminal, OpenPowerShell),
        ("Carpeta de registros", Ico.Documento, () => OpenFolder(Motor.L.UserLogs)),
        ("-", null, null),
        ("Novedades", Ico.Estrella, ShowChanges),
        ("Acerca de Nexum Dev Stack", Ico.Info, ShowAbout),
    };

    void ToggleTheme()
    {
        Tema.Apply(!Tema.Dark);
        Tema.SavePreference(Motor.L);
    }

    /// <summary>Al cambiar de tema, lo que lleva logotipos (en su color) se vuelve a hacer.</summary>
    void Rebuild()
    {
        var keepTab = _tab;
        var header = (Grid)((Grid)_root.Child).Children[0];
        ((Grid)_root.Child).Children.Remove(header);
        var newHeader = BuildHeader();
        ((Grid)_root.Child).Children.Insert(0, newHeader);
        UpdateHeader();
        foreach (var (_, (_, page)) in _tabs)
            page.Build();
        ShowTab(keepTab);
    }

    StackPanel BuildSidebar()
    {
        var box = new StackPanel();
        box.SetResourceReference(Panel.BackgroundProperty, "FondoLateral");
        foreach (var (group, items) in new (string, (string Key, string Text, string Icon)[])[]
                 {
                     ("ENTORNO", new[] { ("proyectos", "Proyectos", Ico.Carpeta), ("versiones", "Versiones de PHP", "logo:php"),
                         ("bbdd", "Bases de datos", Ico.Biblioteca), ("docker", "Docker", "logo:docker") }),
                     ("SISTEMA", new[] { ("dominios", "Dominios y hosts", Ico.Red), ("config", "Configuración", Ico.Ajustes) }),
                 })
        {
            var t = Ui.Text(group, "seccion");
            t.Margin = new Thickness(24, 18, 0, 6);
            box.Children.Add(t);
            foreach (var (key, text, icon) in items)
            {
                var btn = new Button { Tag = key, Cursor = Cursors.Hand, FocusVisualStyle = null, HorizontalContentAlignment = HorizontalAlignment.Left };
                btn.Template = NavTemplate();
                btn.Click += (_, _) => ShowTab(key);
                var content = new StackPanel { Orientation = Orientation.Horizontal };
                FrameworkElement ic = icon.StartsWith("logo:") ? Ui.Logo(icon[5..], 18, "Texto") : Ui.Icon(icon, 16);
                ic.Width = 20;
                content.Children.Add(ic);
                var label = Ui.Text(text);
                label.Margin = new Thickness(12, 0, 0, 0);
                content.Children.Add(label);
                btn.Content = content;
                box.Children.Add(btn);
                _tabs[key] = (btn, _tabs.TryGetValue(key, out var old) ? old.Page : null!);
            }
        }
        var line = new Border { BorderThickness = new Thickness(0, 0, 1, 0) };
        line.SetResourceReference(Border.BorderBrushProperty, "Borde");
        return box;
    }

    static ControlTemplate NavTemplate()
    {
        var t = new ControlTemplate(typeof(Button));
        var border = new FrameworkElementFactory(typeof(Border), "Caja");
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(10));
        border.SetValue(Border.PaddingProperty, new Thickness(14, 12, 14, 12));
        border.SetValue(Border.MarginProperty, new Thickness(10, 2, 10, 2));
        border.SetValue(Border.BackgroundProperty, new TemplateBindingExtension(BackgroundProperty));
        var cp = new FrameworkElementFactory(typeof(ContentPresenter));
        border.AppendChild(cp);
        t.VisualTree = border;
        return t;
    }

    void PaintNav()
    {
        foreach (var (key, (nav, _)) in _tabs)
        {
            if (nav == null) continue;
            var on = key == _tab;
            if (on)
                nav.SetResourceReference(BackgroundProperty, "Azul");
            else
                nav.Background = Brushes.Transparent;
            var content = (StackPanel)nav.Content;
            foreach (var child in content.Children)
            {
                if (child is TextBlock tb)
                    tb.SetResourceReference(TextBlock.ForegroundProperty, on ? "Blanco" : "Texto");
                else if (child is System.Windows.Shapes.Path p)
                    p.SetResourceReference(System.Windows.Shapes.Shape.FillProperty, on ? "Blanco" : "Texto");
            }
            nav.MouseEnter -= NavHover;
            nav.MouseLeave -= NavLeave;
            if (!on)
            {
                nav.MouseEnter += NavHover;
                nav.MouseLeave += NavLeave;
            }
        }
    }

    void NavHover(object sender, MouseEventArgs e) => ((Button)sender).SetResourceReference(BackgroundProperty, "FondoHover");
    void NavLeave(object sender, MouseEventArgs e) => ((Button)sender).Background = Brushes.Transparent;

    public void ShowTab(string key)
    {
        if (!_tabs.ContainsKey(key))
            return;
        _tab = key;
        foreach (var (k, (_, page)) in _tabs)
            page.View.Visibility = k == key ? Visibility.Visible : Visibility.Collapsed;
        PaintNav();
        _tabs[key].Page.Shown();
    }

    public T PageOf<T>(string key) where T : Pagina => (T)_tabs[key].Page;

    // ------------------------------------------------------------------ datos
    /// <summary>Vuelve a leer todo (en segundo plano) y rehace las páginas. Con branches, también php.net.</summary>
    public void Reload(bool branches = false, bool force = false)
    {
        if (_loading && !branches && !force)
            return;
        _loading = true;
        force |= branches || Busy;
        Task.Run(() =>
        {
            Estado? st = null;
            EstadoProyectos? pr = null;
            EstadoHosts? hs = null;
            Dictionary<(string, string), (long, long)>? sizes = null;
            try { st = Motor.ReadState(); } catch (Exception ex) { Log(ex); }
            try { pr = Motor.ReadProjects(); } catch (Exception ex) { Log(ex); }
            try { hs = Motor.ReadHosts(); } catch (Exception ex) { Log(ex); }
            try { if (st?.Prepared == true) sizes = Motor.DatabaseSizes(); } catch (Exception ex) { Log(ex); }
            var sig = Signature(st, pr, hs, sizes);
            Dispatcher.BeginInvoke(() =>
            {
                _loading = false;
                // (si no ha cambiado nada, no se redibuja: no se cierra un desplegable abierto ni se pierde lo escrito)
                if (sig == _signature && !force)
                    return;
                _signature = sig;
                if (st != null) State = st;
                if (pr != null) Projects = pr;
                if (hs != null) HostsState = hs;
                if (sizes != null) DbSizes = sizes;
                UpdateHeader();
                foreach (var (_, (_, page)) in _tabs)
                    page.Build();
            });
        });
        if (branches)
        {
            Branches = null;
            BranchesError = null;
            Task.Run(() =>
            {
                List<RamaInfo>? b = null;
                string? err = null;
                Dictionary<string, (string, string)>? dates = null;
                try { b = Motor.Branches(CancellationToken.None); }
                catch (Exception ex) { err = "No se ha podido consultar windows.php.net y php.net. Comprueba la conexión a internet. (" + ex.Message + ")"; }
                try { dates = Motor.PhpDates(CancellationToken.None); } catch (Exception) { }
                Dispatcher.BeginInvoke(() =>
                {
                    Branches = b;
                    BranchesError = err;
                    if (dates != null) PhpDates = dates;
                    PageOf<PaginaVersiones>("versiones").Build();
                });
            });
        }
    }

    string _signature = "";

    /// <summary>Resumen de lo leído, para saber si ha cambiado algo.</summary>
    static string Signature(Estado? st, EstadoProyectos? pr, EstadoHosts? hs, Dictionary<(string, string), (long, long)>? sizes)
    {
        var sb = new System.Text.StringBuilder();
        var o = new System.Text.Json.JsonSerializerOptions { IncludeFields = true };
        try
        {
            if (st != null) sb.Append(System.Text.Json.JsonSerializer.Serialize(st, o));
            if (pr != null)
            {
                sb.Append('|').Append(pr.Current).Append(pr.Create);
                foreach (var x in pr.List) sb.Append('|').Append(x.Name).Append(x.Db).Append(x.Kind).Append(x.PhpVersion);
                foreach (var (k, v) in pr.Saved) sb.Append('|').Append(k).Append('=').Append(v);
                foreach (var (k, v) in pr.VLinks) sb.Append('|').Append(k.Db).Append('@').Append(k.Ver).Append('=').Append(v);
            }
            if (hs != null) sb.Append(System.Text.Json.JsonSerializer.Serialize(hs, o));
            if (sizes != null)
                foreach (var (k, v) in sizes.OrderBy(k => k.Key.Item1).ThenBy(k => k.Key.Item2)) sb.Append('|').Append(k.Item1).Append(k.Item2).Append(v.Item1);
        }
        catch (Exception)
        {
            sb.Append(Guid.NewGuid());
        }
        return sb.ToString();
    }

    void Log(Exception ex)
    {
        try
        {
            Directory.CreateDirectory(Motor.L.UserLogs);
            File.AppendAllText(Path.Combine(Motor.L.UserLogs, "ventana-errores.log"), $"{DateTime.Now:s} {ex}\n\n");
        }
        catch (Exception) { }
    }

    void UpdateHeader()
    {
        var st = State;
        var act = st?.ActiveInfo;
        _statusLbl.Text = act != null ? $"PHP {act.M.Php}" : "Ninguna versión activa";
        _statusSub.Text = act != null ? act.Folder : "";
        foreach (var (svc, dot) in _dots)
        {
            var on = svc == "Apache" ? st?.ApacheOn == true : st?.MariaDbOn == true;
            dot.SetResourceReference(Border.BackgroundProperty, on ? "Verde" : "Gris");
            if (on)
                dot.BeginAnimation(OpacityProperty, new System.Windows.Media.Animation.DoubleAnimation(1, 0.3, TimeSpan.FromSeconds(0.8))
                    { AutoReverse = true, RepeatBehavior = System.Windows.Media.Animation.RepeatBehavior.Forever });
            else
                dot.BeginAnimation(OpacityProperty, null);
        }
        var running = st?.Running == true;
        var label = ((StackPanel)_powerBtn.Content).Children.OfType<TextBlock>().Last();
        label.Text = running ? "Encendidos" : "Parados";
        _powerBtn.SetResourceReference(ForegroundProperty, running ? "Verde" : "Rojo");
        _powerBtn.SetResourceReference(BackgroundProperty, running ? "VerdeSuave" : "RojoSuave");
        _powerBtn.BorderBrush = Brushes.Transparent;
        foreach (var t in ((StackPanel)_powerBtn.Content).Children.OfType<TextBlock>())
            t.SetResourceReference(TextBlock.ForegroundProperty, running ? "Verde" : "Rojo");
        _powerBtn.ToolTip = st?.Active == null ? "Activa una versión" : running ? $"Parar y desactivar {st.Active}" : $"Arrancar {st.Active}";
        _brandSub.Text = $"{AppInfo.Subtitle}  ·  v{AppInfo.Version}";
        BuildWarnings();
    }

    void OnPower()
    {
        var st = State;
        if (st?.Active == null)
        {
            ShowTab("versiones");
            return;
        }
        if (st.Running)
            RunTask($"Parando y desactivando {st.Active}", new[] { "desactivar" }, new OpcionesTarea { DoneText = $"{st.Active} parada y desactivada", AutoClose = true });
        else
            RunTask($"Arrancando {st.Active}", new[] { "arrancar" }, new OpcionesTarea { DoneText = "Versión activa arrancada", AutoClose = true });
    }

    // ------------------------------------------------------------------ avisos
    void BuildWarnings()
    {
        _warnBox.Children.Clear();
        var st = State;
        if (st == null)
        {
            _warnBtn.Visibility = Visibility.Collapsed;
            return;
        }
        void Add(string title, string desc, string rowTitle, string rowSub, string? button, Action? action)
        {
            var (box, list) = Ui.Group(title, null);
            var d = Ui.Wrap(desc, "chico", "tenue");
            d.Margin = new Thickness(2, 0, 0, 8);
            box.Children.Insert(1, d);
            var (row, suffix, _, sub) = Ui.Row(rowTitle, rowSub);
            sub.TextWrapping = TextWrapping.Wrap;
            if (button != null && action != null)
                suffix.Children.Add(Ui.TextButton(button, () => { _warnPop.IsOpen = false; action(); }, "BotonAzul"));
            Ui.AddRow(list, row);
            _warnBox.Children.Add(box);
        }
        if (st.Prepared && st.ProgramOutdated)
            Add("El programa de administrador es más antiguo",
                $"Lo que se hace con permisos de administrador lo hace la copia de {Motor.L.ProgramExe}, que tu usuario no puede cambiar. Es la {st.ProgramVersion ?? "(ninguna)"} y esta es la {AppInfo.Version}: actualízala (pide permiso de administrador).",
                "Copia del programa", Motor.L.ProgramExe, "Actualizarla",
                () => RunTask("Actualizando el programa de administrador", new[] { "actualizar-programa" }, new OpcionesTarea { DoneText = "Programa actualizado", AutoClose = true }));
        if (!st.VcOk)
            Add("Falta el runtime de Visual C++",
                $"Apache (de Apache Lounge, compilado con Visual Studio 2026) y PHP lo necesitan: sin él no arrancan. " +
                $"{(st.VcRuntime == null ? "No está instalado." : $"Tienes el {st.VcRuntime.Major}.{st.VcRuntime.Minor} y hace falta el {Core.Catalogo.Catalogo.MinVcRuntime.Major}.{Core.Catalogo.Catalogo.MinVcRuntime.Minor} o posterior.")} " +
                "Se descarga de Microsoft, se comprueba su firma y se instala (Windows pide permiso).",
                "Visual C++ 2015-2026 (x64)", "De Microsoft: aka.ms/vc14/vc_redist.x64.exe", "Instalarlo",
                () => RunTask("Instalando el runtime de Visual C++", new[] { "instalar-vcredist" }, new OpcionesTarea { DoneText = "Runtime de Visual C++ instalado" }));
        if (st.Stray.Count > 0)
            Add("Hay procesos de otras versiones en memoria",
                $"Solo debería estar en memoria la versión activa{(st.Active != null ? $" ({st.Active})" : "")}. Ocupan memoria y pueden bloquear los puertos 80, 443 y 3306.",
                "Procesos que sobran", string.Join("; ", st.Stray.Select(s => $"{s.Folder}: {s.Programs}")), "Cerrarlos",
                () => RunTask("Cerrando los procesos que sobran", new[] { "cerrar-procesos" }, new OpcionesTarea { DoneText = "Solo queda en memoria la versión activa", AutoClose = true }));
        if (st.Ports.Count > 0)
            Add("Otro programa usa los puertos de Nexum",
                "Apache necesita el 80 y el 443 y MariaDB el 3306 de este equipo. Cierra o para ese programa (otro XAMPP, IIS, MySQL, Skype…) y vuelve a arrancar la versión activa.",
                "Puertos ocupados", string.Join("; ", st.Ports.Select(p => $"{p.Port}: {p.ProcessName} (PID {p.Pid})")), null, null);
        if (st.Untrusted.Count > 0)
            Add("El navegador avisa al abrir estos proyectos",
                "Edge y Chrome no aceptan todavía su certificado: sale «La conexión no es privada». Confiar hace que acepten el certificado propio de cada proyecto, que solo vale para su dominio (Windows pregunta por cada uno). El de una tienda con dominio real, solo mientras esté falseada en hosts. Firefox: activa security.enterprise_roots.enabled en about:config.",
                "Proyectos que avisan en el navegador", string.Join(", ", st.Untrusted.Take(6)) + (st.Untrusted.Count > 6 ? $" y {st.Untrusted.Count - 6} más" : ""), "Confiar",
                () => RunTask("Confiando en los certificados de los proyectos", new[] { "confiar-certificados" }, new OpcionesTarea { DoneText = "El navegador acepta los certificados de los proyectos" }));
        if (st.Stale.Count > 0)
            Add("El navegador acepta webs reales que ya no están falseadas",
                "El navegador aceptaba su certificado mientras estaban falseadas en hosts. Ya no lo están, y con la clave de ese certificado se podría suplantar la web de verdad. Quitar hace que deje de aceptarlo (Windows pregunta).",
                "Webs reales que acepta el navegador", string.Join(", ", st.Stale.Select(s => s.Domain)), "Quitar",
                () => RunTask("Quitando los certificados de las webs reales", new[] { "confiar-certificados", "--quitar" }, new OpcionesTarea { DoneText = "El navegador ya no acepta esos certificados" }));
        var n = _warnBox.Children.Count;
        _warnNum.Text = n.ToString();
        _warnBtn.Visibility = n > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    // ------------------------------------------------------------------ servicios
    void BuildServices()
    {
        _servicesBox.Children.Clear();
        var st = State;
        if (st?.Active == null)
        {
            var (box, list) = Ui.Group("Servicios");
            var (row, _, _, _) = Ui.Row("Ninguna versión activa", "Activa una versión en Versiones de PHP para ver sus servicios.", Ui.Dot(false));
            Ui.AddRow(list, row);
            _servicesBox.Children.Add(box);
            return;
        }
        var running = (st.ApacheOn ? 1 : 0) + (st.MariaDbOn ? 1 : 0);
        var head = new Grid { Margin = new Thickness(0, 0, 0, 12) };
        head.Children.Add(Ui.VStack(2, Ui.Text($"Servicios de {st.Active}", "titulo"), Ui.Text($"{running} de 2 en marcha", "tenue")));
        var safe = Ui.Tag("Solo desde este equipo", fg: "Verde", bg: "VerdeSuave");
        safe.HorizontalAlignment = HorizontalAlignment.Right;
        safe.ToolTip = "Solo se puede entrar en ellos desde este equipo (127.0.0.1 y ::1): los demás equipos de la red no ven los proyectos ni las BBDD.";
        head.Children.Add(safe);
        _servicesBox.Children.Add(head);
        foreach (var (key, title, help, logo, on, ports) in new[]
                 {
                     ("apache", "Apache", "Servidor web: las webs de htdocs y phpMyAdmin (con PHP)", "apache", st.ApacheOn, new[] { Motor.P.Http, Motor.P.Https }),
                     ("mariadb", "MariaDB", "Servidor de BBDD", "mariadb", st.MariaDbOn, new[] { Motor.P.MariaDb }),
                 })
        {
            var g = new Grid { Margin = new Thickness(16, 14, 16, 14) };
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var icon = Ui.Logo(logo, 26);
            icon.Margin = new Thickness(0, 0, 14, 0);
            g.Children.Add(icon);
            var mid = Ui.VStack(4,
                Ui.HStack(8, Ui.Text(title, "negrita"), on ? Ui.Tag("En marcha", fg: "Verde", bg: "VerdeSuave") : Ui.Tag("Parado")),
                Ui.Wrap(help, "chico", "tenue"),
                Ui.HStack(6, ports.Select(p => (UIElement)Ui.Tag($"Puerto {p}")).ToArray()));
            Grid.SetColumn(mid, 1);
            g.Children.Add(mid);
            var acts = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            void Svc(string cmd, string doing, string done) => RunTask($"{doing} {title}", new[] { "servicio", key, cmd },
                new OpcionesTarea { DoneText = $"{title} {done}", AutoClose = true });
            if (on)
            {
                acts.Children.Add(Ui.Button(Ico.Recargar, "Reiniciar", null, () => { _servicesPop.IsOpen = false; Svc("reiniciar", "Reiniciando", "reiniciado"); }));
                var stop = Ui.Button(Ico.Parar, "Parar", null, () => { _servicesPop.IsOpen = false; Svc("parar", "Parando", "parado"); });
                stop.Margin = new Thickness(8, 0, 0, 0);
                acts.Children.Add(stop);
            }
            else
                acts.Children.Add(Ui.Button(Ico.Arrancar, "Arrancar", null, () => { _servicesPop.IsOpen = false; Svc("arrancar", "Arrancando", "arrancado"); }, "BotonAzul"));
            Grid.SetColumn(acts, 2);
            g.Children.Add(acts);
            var card = Ui.Card(g, 0, 14);
            card.Margin = new Thickness(0, 0, 0, 10);
            _servicesBox.Children.Add(card);
        }
    }

    // ------------------------------------------------------------------ tareas
    /// <summary>Lanza una tarea (este programa con el comando) en su ventana; al terminar se vuelve a leer todo.</summary>
    public VentanaTarea RunTask(string title, string[] args, OpcionesTarea opts, bool reloadBranches = false)
    {
        Busy = true;
        var t = new VentanaTarea(this, title, args, opts);
        t.Closed += (_, _) =>
        {
            Busy = false;
            Reload(reloadBranches, force: true);
        };
        t.ShowDialog();
        return t;
    }

    public void Toast(string text)
    {
        _toastText.Text = text;
        _toast.Visibility = Visibility.Visible;
        _toastTimer?.Stop();
        _toastTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
        _toastTimer.Tick += (_, _) =>
        {
            _toast.Visibility = Visibility.Collapsed;
            _toastTimer?.Stop();
        };
        _toastTimer.Start();
    }

    // ------------------------------------------------------------------ abrir cosas
    public void OpenUri(string uri)
    {
        try
        {
            Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            Dialogo.Message(this, $"No se ha podido abrir {uri}", ex.Message);
        }
    }

    public void OpenFolder(string dir)
    {
        try
        {
            Directory.CreateDirectory(dir);
            Process.Start(new ProcessStartInfo("explorer.exe") { ArgumentList = { dir }, UseShellExecute = false });
        }
        catch (Exception ex)
        {
            Dialogo.Message(this, $"No se ha podido abrir {dir}", ex.Message);
        }
    }

    /// <summary>Abre un fichero de texto con el Bloc de notas (aunque no tenga extensión, como hosts).</summary>
    public void OpenText(string path)
    {
        try
        {
            Process.Start(new ProcessStartInfo("notepad.exe") { ArgumentList = { path }, UseShellExecute = false });
        }
        catch (Exception ex)
        {
            Dialogo.Message(this, $"No se ha podido abrir {path}", ex.Message);
        }
    }

    void OpenPowerShell()
    {
        try
        {
            var dir = Path.GetDirectoryName(Motor.SelfPath)!;
            Process.Start(new ProcessStartInfo("powershell.exe") { WorkingDirectory = dir, UseShellExecute = true, ArgumentList = { "-NoExit", "-Command", ".\\NexumDevStack.exe --ayuda | Out-Default" } });
        }
        catch (Exception ex)
        {
            Dialogo.Message(this, "No se ha podido abrir PowerShell", ex.Message);
        }
    }

    /// <summary>Visual Studio Code (Code.exe), donde suele instalarse; null si no está.</summary>
    public static string? VsCode()
    {
        var candidates = new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Microsoft VS Code", "Code.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Microsoft VS Code", "Code.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Microsoft VS Code", "Code.exe"),
        };
        return candidates.FirstOrDefault(File.Exists);
    }

    public void OpenInVsCode(string folder)
    {
        var code = VsCode();
        if (code == null)
        {
            Dialogo.Message(this, "Visual Studio Code no está instalado", "Instálalo desde code.visualstudio.com.");
            return;
        }
        try
        {
            Process.Start(new ProcessStartInfo(code) { ArgumentList = { folder }, UseShellExecute = false });
        }
        catch (Exception ex)
        {
            Dialogo.Message(this, "No se ha podido abrir Visual Studio Code", ex.Message);
        }
    }

    // ------------------------------------------------------------------ editar vhosts y hosts
    /// <summary>
    /// Editar vhosts: se abre una copia en el Bloc de notas y, al pulsar Aplicar, se comprueba con Apache, se guarda
    /// la anterior en nexum-copias y se recarga Apache (si no la acepta, se queda como estaba).
    /// </summary>
    public void EditVhosts()
    {
        if (!Motor.L.IsPrepared)
        {
            Dialogo.Message(this, "Nexum Dev Stack no está preparado", "Prepáralo primero (Proyectos o Versiones de PHP).");
            return;
        }
        var copy = Path.Combine(Motor.L.EditCopiesDir, "httpd-vhosts.conf");
        try
        {
            Directory.CreateDirectory(Motor.L.EditCopiesDir);
            File.WriteAllText(copy, Motor.ReadVhosts());
        }
        catch (Exception ex)
        {
            Dialogo.Message(this, "No se han podido leer los vhosts", ex.Message, error: true);
            return;
        }
        OpenText(copy);
        if (!Dialogo.Confirm(this, "Editar vhosts",
                $"Se abre una copia ({copy}) en el Bloc de notas.\n\nHaz los cambios, guárdalos y pulsa Aplicar: se comprueban con Apache, se guarda una copia de los actuales en {Motor.L.CopiesDir} y se recarga Apache. Si Apache no los acepta, se dejan como estaban.",
                "Aplicar"))
            return;
        RunTask("Guardando los vhosts", new[] { "vhosts", "--aplicar", copy }, new OpcionesTarea { DoneText = "Vhosts actualizados", AutoClose = true });
    }

    /// <summary>Editar hosts: una copia en el Bloc de notas; al aplicarla, la escribe el proceso de administrador (comprobada).</summary>
    public void EditHosts()
    {
        if (!Motor.L.IsPrepared)
        {
            Dialogo.Message(this, "Nexum Dev Stack no está preparado", "Prepáralo primero (Proyectos o Versiones de PHP).");
            return;
        }
        var copy = Path.Combine(Motor.L.EditCopiesDir, "hosts");
        try
        {
            Directory.CreateDirectory(Motor.L.EditCopiesDir);
            File.WriteAllText(copy, Ficheros.ReadSmallText(Motor.Pf.HostsFilePath, 4_000_000) ?? "");
        }
        catch (Exception ex)
        {
            Dialogo.Message(this, "No se ha podido leer hosts", ex.Message, error: true);
            return;
        }
        OpenText(copy);
        if (!Dialogo.Confirm(this, "Editar hosts",
                $"{Motor.Pf.HostsFilePath} es del administrador, así que se abre una copia ({copy}) en el Bloc de notas.\n\nHaz los cambios, guárdalos y pulsa Aplicar: se guarda una copia del actual y se escribe el nuevo (pide permiso de administrador).",
                "Aplicar"))
            return;
        RunTask("Guardando hosts", new[] { "hosts", "--aplicar", copy }, new OpcionesTarea { DoneText = "hosts actualizado", AutoClose = true });
    }

    // ------------------------------------------------------------------ información
    public void ShowChanges()
    {
        var d = new Dialogo(this, "Novedades", null, 720);
        var doc = new RichTextBox { IsReadOnly = true, BorderThickness = new Thickness(0), Background = Brushes.Transparent, Height = 480, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        doc.SetResourceReference(ForegroundProperty, "Texto");
        doc.Document = Markdown.ToDocument(AppInfo.Changes);
        d.Add(doc);
        d.Buttons("Cerrar", null);
        d.Run();
    }

    public void ShowAbout()
    {
        var d = new Dialogo(this, null, null, 460);
        var img = new Image { Width = 72, Height = 72, Margin = new Thickness(0, 4, 0, 10) };
        try { img.Source = new BitmapImage(new Uri("pack://application:,,,/nexum.png")); } catch (Exception) { }
        d.Add(img);
        var name = Ui.Text(AppInfo.Name, "titulo-grande");
        name.HorizontalAlignment = HorizontalAlignment.Center;
        d.Add(name);
        var v = Ui.Text("Versión " + AppInfo.Version + " para Windows", "tenue");
        v.HorizontalAlignment = HorizontalAlignment.Center;
        d.Add(v);
        var about = Ui.Wrap(AppInfo.About);
        about.TextAlignment = TextAlignment.Center;
        about.Margin = new Thickness(0, 12, 0, 8);
        d.Add(about);
        var sig = Ui.Text($"{AppInfo.Signature}\n© {DateTime.Now.Year}", "chico", "tenue");
        sig.TextAlignment = TextAlignment.Center;
        sig.HorizontalAlignment = HorizontalAlignment.Center;
        d.Add(sig);
        d.Buttons("Cerrar", null);
        d.Run();
    }

    public void ShowCommands()
    {
        var d = new Dialogo(this, "Comandos de NexumDevStack.exe", "En PowerShell: .\\NexumDevStack.exe --ayuda | Out-Default", 820);
        var box = new TextBox
        {
            Text = Core.Cli.Comandos.Help, IsReadOnly = true, FontFamily = Ui.Mono, FontSize = 12, Height = 480,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
        };
        d.Add(box);
        d.Add(Ui.TextButton("Copiar todo", () => { Clipboard.SetText(Core.Cli.Comandos.Help); Toast("Copiado al portapapeles"); }));
        d.Buttons("Cerrar", null);
        d.Run();
    }

    /// <summary>Últimas líneas de un registro (lo más reciente al final), sin leer el fichero entero.</summary>
    public void ShowLogTail(string path, int lines = 400)
    {
        var text = Motor.L.IsPrepared ? Core.Pila.Motor.Tail(path, lines) : "";
        text = string.Join("\n", text.Split('\n').Select(l => l.StartsWith("  ") ? l[2..] : l)).Replace("\\n", "\n    ");
        var d = new Dialogo(this, Path.GetFileName(path), $"Últimas {lines} líneas de {path}", 940);
        var box = new TextBox
        {
            Text = text.Length > 0 ? text : "(vacío)", IsReadOnly = true, FontFamily = Ui.Mono, FontSize = 12, Height = 480, TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        };
        box.Loaded += (_, _) => box.ScrollToEnd();
        d.Add(box);
        d.Add(Ui.HStack(8, Ui.TextButton("Copiar todo", () => { Clipboard.SetText(text); Toast("Copiado al portapapeles"); }),
            Ui.TextButton("Abrir", () => OpenText(path))));
        d.Buttons("Cerrar", null);
        d.Run();
    }

    // ------------------------------------------------------------------ proyectos (lo que usan varias páginas)
    /// <summary>(versión, BBDD) de un proyecto: las vinculadas a su carpeta en cada versión o la de su configuración.</summary>
    public List<(VersionInfo Ver, string Db)> ProjectPairs(Proyecto x)
    {
        var st = State;
        var p = Projects;
        if (st == null || p == null)
            return new();
        var pairs = st.Versions.SelectMany(v => v.Dbs.Select(d => (v, d.Name))).Where(t => p.LinkOf(t.Name, t.v.Folder) == x.Name).ToList();
        if (pairs.Count > 0 || x.Db.Length == 0)
            return pairs;
        return st.Versions.Where(v => v.Dbs.Any(d => d.Name.Equals(x.Db, StringComparison.OrdinalIgnoreCase)) && p.LinkOf(x.Db, v.Folder) == null)
            .Select(v => (v, x.Db)).ToList();
    }

    /// <summary>BBDD de un proyecto que no está en ninguna versión: la recordada o la de su configuración.</summary>
    public string ProjectBase(Proyecto x)
    {
        var pairs = ProjectPairs(x);
        if (pairs.Count > 0) return pairs[0].Db;
        var saved = (Projects?.Saved ?? new()).Where(kv => kv.Value == x.Name).Select(kv => kv.Key).ToList();
        return x.Db.Length > 0 ? x.Db : saved.LastOrDefault() ?? "";
    }

    public Proyecto? LoadedProject() =>
        Projects is { Current.Length: > 0 } p ? p.List.FirstOrDefault(x => x.Name == p.Current) : null;

    /// <summary>BBDD del proyecto cargado en la versión activa.</summary>
    public string LoadedProjectDb()
    {
        var x = LoadedProject();
        if (x == null || State == null) return "";
        var pairs = ProjectPairs(x);
        var db = pairs.FirstOrDefault(t => t.Ver.Folder == State.Active).Db ?? (pairs.Count > 0 ? pairs[0].Db : ProjectBase(x));
        return Validacion.IsDbName(db) ? db : "";
    }
}
