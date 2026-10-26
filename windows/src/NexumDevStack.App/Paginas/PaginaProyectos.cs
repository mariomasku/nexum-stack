using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using NexumDevStack.Core.Pila;
using NexumDevStack.Core.Proyectos;
using NexumDevStack.Core.Util;

namespace NexumDevStack.App.Paginas;

/// <summary>
/// Proyectos (como nv_build_projects de Linux): arriba, el proyecto cargado en grande (o el que se pulse en la
/// lista) con su entorno y su BBDD y sus botones; debajo, la lista de todos los proyectos de htdocs.
/// </summary>
public sealed class PaginaProyectos : Pagina
{
    string? _selected;
    string _query = "";
    string _kind = "all";
    TextBox? _search;
    Grid? _searchBox;
    StackPanel? _list;
    StackPanel? _hero;
    TextBlock? _count;

    public PaginaProyectos(VentanaPrincipal w) : base(w, 940) { }

    public override void Build()
    {
        Content.Children.Clear();
        if (W.State == null)
        {
            Loading();
            return;
        }
        if (!Prepared)
        {
            Content.Children.Add(Ui.PageTitle(Ui.Icon(Ico.Carpeta, 24), "Proyectos", "Las carpetas de htdocs: WordPress, PrestaShop y lo demás"));
            NotPrepared();
            return;
        }
        _hero = new StackPanel();
        Content.Children.Add(_hero);

        var head = new Grid { Margin = new Thickness(0, 24, 0, 12) };
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        head.Children.Add(Ui.VStack(2, Ui.Text("Proyectos", "titulo"),
            Ui.Text("Pulsa uno para verlo arriba; «Cargar» lo monta en el vhost con su versión y su BBDD.", "chico", "tenue")));
        var right = new StackPanel { Orientation = Orientation.Horizontal };
        if (_searchBox == null)
        {
            (_searchBox, _search) = Ui.SearchBox("Buscar proyecto", 220);
            _search.TextChanged += OnSearch;
        }
        right.Children.Add(Ui.Detach(_searchBox));
        var kind = Ui.Combo(new[] { ("all", "Todos"), ("wp", "WordPress"), ("ps", "PrestaShop"), ("otros", "Otros") }, _kind, 140);
        kind.Margin = new Thickness(8, 0, 0, 0);
        kind.SelectionChanged += (_, _) => { _kind = kind.SelectedId() ?? "all"; List(); };
        right.Children.Add(kind);
        var nuevo = Ui.Button(Ico.Mas, "Nuevo", "Proyecto nuevo: una carpeta en htdocs, con su dominio falseado si quieres", NewProject);
        nuevo.Margin = new Thickness(8, 0, 0, 0);
        right.Children.Add(nuevo);
        Grid.SetColumn(right, 1);
        head.Children.Add(right);
        Content.Children.Add(head);
        _list = new StackPanel();
        Content.Children.Add(Ui.Card(_list));
        _count = Ui.Text("", "chico", "tenue");
        _count.Margin = new Thickness(4, 8, 0, 0);
        Content.Children.Add(_count);
        var loaded = W.LoadedProject();
        var p = W.Projects;
        if (p != null && (_selected == null || !p.List.Any(x => x.Name == _selected)))
            _selected = loaded?.Name;
        Hero();
        List();
    }

    void OnSearch(object? s, TextChangedEventArgs e)
    {
        _query = _search!.Text.Trim().ToLowerInvariant();
        List();
    }

    void Select(Proyecto x)
    {
        _selected = x.Name;
        Hero();
        List();
    }

    // ------------------------------------------------------------------ la lista
    void List()
    {
        if (_list == null) return;
        _list.Children.Clear();
        var p = W.Projects;
        if (p == null)
            return;
        var loaded = W.LoadedProject();
        var widths = new double[] { 30, 270, 200, 0, 110 };
        _list.Children.Add(Ui.TableRow(widths, new UIElement[]
        {
            new TextBlock(), Ui.Text("PROYECTO", "cab"), Ui.Text("BBDD", "cab"), Ui.Text("VERSIONES", "cab"), new TextBlock(),
        }, true));
        var shown = 0;
        foreach (var x in p.List)
        {
            var pairs = W.ProjectPairs(x);
            var dbs = pairs.Select(t => t.Db).Append(x.Db).Where(d => d.Length > 0).ToList();
            if (_query.Length > 0 && !x.Name.ToLowerInvariant().Contains(_query) && !dbs.Any(d => d.ToLowerInvariant().Contains(_query)))
                continue;
            if (_kind != "all" && !(_kind == "otros" && x.Kind.Length == 0) && x.Kind != _kind)
                continue;
            shown++;
            var isLoaded = loaded?.Name == x.Name;
            var db = pairs.Count > 0 ? pairs[0].Db : W.ProjectBase(x);
            var chips = new WrapPanel();
            foreach (var (v, d) in pairs)
            {
                var c = Ui.Tag(Versiones.Branch(v.M.Php));
                ((TextBlock)c.Child).FontFamily = Ui.Mono;
                c.ToolTip = $"{v.Folder} · {d}";
                c.Margin = new Thickness(0, 0, 4, 0);
                chips.Children.Add(c);
            }
            UIElement action;
            if (isLoaded)
                action = Ui.Tag("Cargado", blue: true);
            else
            {
                var load = Ui.TextButton("Cargar", () => LoadFolder(x), "BotonAzul");
                load.IsEnabled = !W.Busy;
                load.Opacity = 0;
                action = load;
            }
            var name = Ui.Text(x.Name);
            name.ToolTip = x.Name;
            var row = Ui.TableRow(widths, new UIElement[]
            {
                Ui.KindIcon(x.Kind, 18), name, Ui.Text(db.Length > 0 ? db : "sin BBDD", "mono", "chico", "tenue"), chips, action,
            }, margin: new Thickness(12, 6, 10, 6));
            var b = new Border { Child = row, BorderThickness = new Thickness(0, 1, 0, 0), Cursor = Cursors.Hand };
            b.SetResourceReference(Border.BorderBrushProperty, "BordeSuave");
            if (isLoaded) b.SetResourceReference(Border.BackgroundProperty, "FondoCargado");
            else if (x.Name == _selected) b.SetResourceReference(Border.BackgroundProperty, "FondoElegido");
            else b.Background = System.Windows.Media.Brushes.Transparent;
            if (action is Button lb)
            {
                b.MouseEnter += (_, _) => lb.Opacity = 1;
                b.MouseLeave += (_, _) => lb.Opacity = 0;
            }
            b.MouseLeftButtonUp += (_, e) =>
            {
                if (e.OriginalSource is DependencyObject d && IsInButton(d)) return;
                Select(x);
            };
            _list.Children.Add(b);
        }
        if (shown == 0)
        {
            var t = Ui.Text(p.List.Count == 0 ? $"No hay proyectos en {W.Motor.L.Htdocs}: crea uno con «Nuevo» o copia su carpeta ahí." : "Ningún proyecto con ese nombre o esa BBDD", "tenue");
            t.Margin = new Thickness(14, 10, 14, 12);
            _list.Children.Add(t);
        }
        if (_count != null)
            _count.Text = $"{Texto.Plural(p.List.Count, "proyecto", "proyectos")} en {W.Motor.L.Htdocs}";
    }

    static bool IsInButton(DependencyObject d)
    {
        while (d != null)
        {
            if (d is Button) return true;
            d = System.Windows.Media.VisualTreeHelper.GetParent(d);
        }
        return false;
    }

    // ------------------------------------------------------------------ el proyecto de arriba
    void Hero()
    {
        if (_hero == null) return;
        _hero.Children.Clear();
        var p = W.Projects;
        var st = W.State!;
        var loaded = W.LoadedProject();
        var x = p?.List.FirstOrDefault(y => y.Name == _selected) ?? loaded;
        var isLoaded = x != null && loaded != null && x.Name == loaded.Name;
        var head = new Grid { Margin = new Thickness(2, 0, 2, 8) };
        head.Children.Add(Ui.HStack(8, Ui.Dot(isLoaded, 9, pulse: isLoaded), Ui.Text(isLoaded ? "PROYECTO CARGADO" : x != null ? "PROYECTO ELEGIDO" : "NINGÚN PROYECTO CARGADO", "seccion")));
        var where = Ui.Text(isLoaded ? $"en {Disposicion.ProjectVhost}"
            : p?.Create == true ? $"{Disposicion.ProjectVhost} se crea al cargar el primero" : $"{Disposicion.ProjectVhost} → {(loaded?.Name ?? "nada")}", "chico", "tenue");
        where.HorizontalAlignment = HorizontalAlignment.Right;
        head.Children.Add(where);
        _hero.Children.Add(head);
        var card = new StackPanel();
        if (x == null)
        {
            card.Children.Add(Ui.Text("Elige un proyecto de la lista para cargarlo.", "tenue"));
            _hero.Children.Add(Ui.Card(card, 20, 14));
            return;
        }
        var top = new Grid();
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var avatar = new Border { Width = 68, Height = 68, CornerRadius = new CornerRadius(12), Child = Ui.KindIcon(x.Kind, 40), Margin = new Thickness(0, 0, 20, 0) };
        avatar.SetResourceReference(Border.BackgroundProperty, "FondoElegido");
        top.Children.Add(avatar);
        var title = Ui.Wrap(x.Name, "titulo-grande");
        title.MaxWidth = 460;
        var tl = new WrapPanel();
        tl.Children.Add(title);
        if (x.Kind.Length > 0)
        {
            var tag = Ui.Tag(x.Kind == "wp" ? "WordPress" : "PrestaShop");
            tag.Margin = new Thickness(10, 4, 0, 0);
            tl.Children.Add(tag);
        }
        var path = new TextBox
        {
            Text = Path.Combine(W.Motor.L.Htdocs, x.Name), IsReadOnly = true, BorderThickness = new Thickness(0), Background = System.Windows.Media.Brushes.Transparent,
            FontFamily = Ui.Mono, FontSize = 11.5, Padding = new Thickness(0), MinHeight = 0, Margin = new Thickness(0, 4, 0, 0),
        };
        path.SetResourceReference(Control.ForegroundProperty, "TextoTenue");
        path.Template = BareTextBox();
        var info = Ui.VStack(4, tl, path);
        info.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(info, 1);
        top.Children.Add(info);

        // Selectores: el entorno (la versión y su BBDD) y la BBDD de ese entorno
        var pairs = W.ProjectPairs(x);
        var sel = new Grid();
        sel.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        sel.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(190) });
        sel.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        sel.RowDefinitions.Add(new RowDefinition());
        sel.RowDefinitions.Add(new RowDefinition());
        var l1 = Ui.Text("Entorno (versión de PHP)", "chico", "tenue");
        var l2 = Ui.Text("BBDD", "chico", "tenue");
        l2.Margin = new Thickness(12, 0, 0, 4);
        l1.Margin = new Thickness(0, 0, 0, 4);
        sel.Children.Add(l1);
        Grid.SetColumn(l2, 1);
        sel.Children.Add(l2);
        var env = Ui.Combo(pairs.Count > 0 ? pairs.Select((t, i) => (i.ToString(), $"PHP {t.Ver.M.Php} · {t.Ver.Folder}")) : new[] { ("-", "Sin entornos") },
            pairs.Count > 0 ? Math.Max(0, isLoaded ? pairs.FindIndex(t => t.Ver.Folder == st.Active) : 0).ToString() : "-", 240);
        env.IsEnabled = pairs.Count > 0 && !W.Busy;
        Grid.SetRow(env, 1);
        sel.Children.Add(env);
        var dbl = Ui.Text("—", "mono");
        dbl.Margin = new Thickness(12, 0, 0, 0);
        void ShowDb()
        {
            var i = int.TryParse(env.SelectedId(), out var n) ? n : -1;
            dbl.Text = i >= 0 && i < pairs.Count ? pairs[i].Db : "—";
            dbl.ToolTip = dbl.Text;
        }
        ShowDb();
        var initial = env.SelectedId();
        env.SelectionChanged += (_, _) =>
        {
            ShowDb();
            var i = int.TryParse(env.SelectedId(), out var n) ? n : -1;
            if (i < 0 || i >= pairs.Count || env.SelectedId() == initial) return;
            var (v, db) = pairs[i];
            if (!(isLoaded && v.Folder == st.Active))
                DoLoad(x.Name, db, v, confirmSwitch: true, remember: false);
        };
        Grid.SetRow(dbl, 1);
        Grid.SetColumn(dbl, 1);
        sel.Children.Add(dbl);
        var link = Ui.Button(Ico.Enlace, null, "Cambiar la BBDD de cada versión (vincular)", () => LinkDialog(x), "BotonPlano");
        Grid.SetRow(link, 1);
        Grid.SetColumn(link, 2);
        sel.Children.Add(link);
        var sunken = Ui.Sunken(sel, new Thickness(14, 12, 14, 12));
        sunken.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(sunken, 2);
        top.Children.Add(sunken);
        card.Children.Add(top);
        var sep = Ui.Separator();
        sep.Margin = new Thickness(0, 16, 0, 14);
        card.Children.Add(sep);

        var acts = new Grid();
        acts.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        acts.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var left = new WrapPanel();
        Button Add(Button b)
        {
            b.Margin = new Thickness(0, 0, 8, 0);
            left.Children.Add(b);
            return b;
        }
        if (isLoaded)
        {
            Add(Ui.Button(Ui.Logo("globo", 17), "Abrir web", $"Abrir http://{Disposicion.ProjectVhost}/", () => W.OpenUri($"http://{Disposicion.ProjectVhost}/")));
            if (VentanaPrincipal.VsCode() != null)
                Add(Ui.Button(Ui.Icon(Ico.Codigo, 15, "Azul"), "VS Code", "Abrir la carpeta en Visual Studio Code",
                    () => W.OpenInVsCode(Path.Combine(W.Motor.L.Htdocs, x.Name))));
            var db = W.LoadedProjectDb();
            var pma = Add(Ui.Button(Ui.Logo("phpmyadmin", 17), "phpMyAdmin", db.Length > 0 ? $"Abrir la BBDD {db} en phpMyAdmin" : $"No se sabe qué BBDD usa {x.Name}",
                () => W.OpenUri($"http://127.0.0.1/phpmyadmin/index.php?route=/database/structure&db={db}")));
            pma.IsEnabled = db.Length > 0 && st.Running;
            var (kind, admin) = AdminOf(x);
            var panel = Add(Ui.Button(Ui.Logo(kind == "ps" ? "prestashop" : "wordpress", 17), "Panel",
                admin != null ? "Con el administrador de pruebas ya escrito (local@local.test, contraseña local): solo hay que pulsar Entrar"
                    : $"{x.Name} no es un WordPress ni una tienda PrestaShop con su carpeta de administración", () => OpenPanel(x, kind, admin!)));
            panel.IsEnabled = admin != null && st.Running;
            var docker = Add(Ui.Button(Ui.Logo("docker", 17), "Docker", "Montar el proyecto en Docker: llega en la fase 2", null));
            docker.IsEnabled = false;
            Add(Ui.Button(Ico.Expulsar, null, $"Desmontar: {Disposicion.ProjectVhost} deja de apuntar aquí", Unload, "BotonPlano"));
        }
        else
        {
            var load = Add(Ui.Button(Ico.Arrancar, "Cargar", null, () => LoadFolder(x), "BotonAzul"));
            load.IsEnabled = !W.Busy;
        }
        acts.Children.Add(left);
        var rightActs = new StackPanel { Orientation = Orientation.Horizontal };
        rightActs.Children.Add(Ui.MenuButton(Ico.Mas, "Añadir entorno…", "Llevar el proyecto a otra versión de PHP", new (string, string?, Action?)[]
        {
            ("En otra versión de PHP (copiar su BBDD)…", Ico.Copiar, () => Replicate(x)),
            ("En Docker… (llega en la fase 2)", Ico.Info, null),
        }));
        var moreItems = new List<(string, string?, Action?)>
        {
            ("Vincular la BBDD de cada versión…", Ico.Enlace, () => LinkDialog(x)),
            ("Abrir la carpeta", Ico.CarpetaAbierta, () => W.OpenFolder(Path.Combine(W.Motor.L.Htdocs, x.Name))),
        };
        var baseDb = W.ProjectBase(x);
        if (x.Kind == "ps" && baseDb.Length > 0)
            moreItems.Add(("Vaciar la caché de la tienda", Ico.Limpiar, () => W.RunTask($"Vaciando la caché de la tienda de {x.Name}",
                new[] { "vaciar-cache", x.Name }, new OpcionesTarea { DoneText = "Caché vaciada", AutoClose = true })));
        var more = Ui.MenuButton(Ico.Puntos, null, null, moreItems);
        more.Margin = new Thickness(8, 0, 0, 0);
        rightActs.Children.Add(more);
        var imp = Ui.Button(Ico.Subir, "Importar SQL", "Subir un .sql, .sql.gz o .zip a su BBDD (Bases de datos)",
            () => W.PageOf<PaginaBbdd>("bbdd").PrepareImport(x));
        imp.Margin = new Thickness(8, 0, 0, 0);
        imp.BorderThickness = new Thickness(1);
        imp.SetResourceReference(Control.BorderBrushProperty, "BordeBoton");
        rightActs.Children.Add(imp);
        Grid.SetColumn(rightActs, 1);
        acts.Children.Add(rightActs);
        card.Children.Add(acts);
        _hero.Children.Add(Ui.Card(card, 20, 14));
    }

    static ControlTemplate BareTextBox()
    {
        var t = new ControlTemplate(typeof(TextBox));
        t.VisualTree = new FrameworkElementFactory(typeof(ScrollViewer), "PART_ContentHost");
        return t;
    }

    /// <summary>(tipo, carpeta del panel) del proyecto: wp-admin en WordPress; en PrestaShop, su carpeta de administración.</summary>
    (string Kind, string? Admin) AdminOf(Proyecto x)
    {
        var dir = Path.Combine(W.Motor.L.Htdocs, x.Name);
        if (File.Exists(Path.Combine(dir, "wp-config.php")) && Directory.Exists(Path.Combine(dir, "wp-admin")))
            return ("wp", "wp-admin");
        var ps = PrestaShop.AdminFolder(dir);
        return ps != null ? ("ps", ps) : ("", null);
    }

    /// <summary>
    /// Panel: deja al día el administrador de pruebas y abre una página con el usuario y la contraseña ya escritos
    /// (servida una vez en 127.0.0.1): basta con pulsar Entrar. Si no se puede, el panel como siempre.
    /// </summary>
    void OpenPanel(Proyecto x, string kind, string admin)
    {
        var link = Disposicion.ProjectVhost;
        var basePanel = $"http://{link}/{admin}/";
        var db = W.LoadedProjectDb();
        if (db.Length == 0)
        {
            W.OpenUri(basePanel);
            return;
        }
        W.Toast("Preparando el administrador de pruebas…");
        var pwd = W.PageOf<PaginaBbdd>("bbdd").DbEnv()?["MYSQL_PWD"];
        Task.Run(() =>
        {
            List<string>? kinds = null;
            try
            {
                var m = Program.NewMotor();
                m.RootPassword = pwd ?? m.RootPassword;
                kinds = m.TestAdmin(db, x.Name, new Core.Tareas.SalidaMemoria());
            }
            catch (Exception) { }
            W.Dispatcher.BeginInvoke(() =>
            {
                if (kinds == null || !kinds.Contains(kind))
                {
                    W.OpenUri(basePanel);
                    return;
                }
                var (title, action, fields) = AccesoPanel.LoginFor(kind, link, admin, Core.BaseDatos.Sql.TestAdminUser, Core.BaseDatos.Sql.TestAdminPass);
                var url = AccesoPanel.ServeOnce(AccesoPanel.Page(title, x.Name, action, fields, basePanel));
                W.OpenUri(url ?? basePanel);
            });
        });
    }

    void Unload()
    {
        var current = W.Projects?.Current ?? "";
        W.RunTask($"Desmontando el proyecto {current}", new[] { "desmontar-proyecto" },
            new OpcionesTarea { DoneText = $"{Disposicion.ProjectVhost} ya no apunta a {current}", AutoClose = true });
    }

    // ------------------------------------------------------------------ cargar
    void LoadFolder(Proyecto x)
    {
        var st = W.State!;
        if (st.Versions.Count == 0)
        {
            Dialogo.Message(W, "No hay ninguna versión instalada", "Instala una versión de PHP en Versiones de PHP para cargar proyectos.");
            return;
        }
        var db = W.ProjectBase(x);
        var cands = W.ProjectPairs(x);
        var found = cands.Count > 0;
        if (!found)
            cands = st.Versions.Select(v => (v, db)).ToList();
        (VersionInfo Ver, string Db)? chosen = cands.Count > 1 ? PickVersion(x, db, cands, found) : cands[0];
        if (chosen == null)
            return;
        DoLoad(x.Name, chosen.Value.Db, chosen.Value.Ver, confirmSwitch: cands.Count <= 1, remember: false);
    }

    (VersionInfo, string)? PickVersion(Proyecto x, string db, List<(VersionInfo Ver, string Db)> cands, bool found)
    {
        var st = W.State!;
        var pre = cands.FindIndex(c => c.Ver.Folder == st.Active);
        if (pre < 0 && x.PhpVersion.Length > 0) pre = cands.FindIndex(c => c.Ver.M.Php.StartsWith(x.PhpVersion));
        if (pre < 0) pre = 0;
        var why = found
            ? $"{x.Name} está vinculado a una BBDD en {cands.Count} versiones de PHP y cada una guarda su propia copia. Elige cuál cargar (cámbialas con el botón de vincular):"
            : db.Length > 0 ? $"La BBDD de {x.Name} ({db}) no está en ninguna versión: súbela después en Bases de datos. Elige con qué versión de PHP cargarlo:"
            : $"No se sabe qué BBDD usa {x.Name}. Elige con qué versión de PHP cargarlo:";
        var d = new Dialogo(W, found ? "¿Qué versión del proyecto y de PHP quieres?" : "¿Con qué versión de PHP quieres cargar el proyecto?", why, 540);
        var radios = new List<RadioButton>();
        for (int i = 0; i < cands.Count; i++)
        {
            var (v, cdb) = cands[i];
            var notes = new List<string>();
            if (found) notes.Add($"BBDD {cdb}");
            if (v.Folder == st.Active) notes.Add("la activa");
            if (x.PhpVersion.Length > 0 && v.M.Php.StartsWith(x.PhpVersion)) notes.Add("la de su .php-version");
            var dbInfo = found ? v.Dbs.FirstOrDefault(b => b.Name == cdb) : null;
            var sub = dbInfo != null && dbInfo.When > 0 ? "BBDD: " + Texto.DbDate(dbInfo.When, dbInfo.Kind) : "";
            var (card, rb) = Dialogo.Option($"PHP {v.M.Php}  ({v.Folder})" + (notes.Count > 0 ? "  ·  " + string.Join(", ", notes) : ""), sub, "version", i == pre);
            radios.Add(rb);
            d.Add(card);
        }
        d.Buttons("Cargar proyecto");
        if (!d.Run())
            return null;
        var n = radios.FindIndex(r => r.IsChecked == true);
        return n >= 0 ? cands[n] : null;
    }

    /// <summary>Carga una carpeta en una versión. Avisa cuando hay que cambiar de versión o crear el vhost.</summary>
    public void DoLoad(string folder, string db, VersionInfo v, bool confirmSwitch, bool remember)
    {
        var st = W.State!;
        var act = st.ActiveInfo;
        var notes = new List<string>();
        var where = db.Length > 0 && v.Dbs.Any(b => b.Name == db) ? $", donde está la BBDD {db}" : "";
        if (v.Folder != st.Active && confirmSwitch)
            notes.Add(act != null
                ? $"Se va a cambiar de versión de PHP: se para {act.Folder} (PHP {act.M.Php}) y se activa {v.Folder} (PHP {v.M.Php}){where}."
                : $"Se activa {v.Folder} (PHP {v.M.Php}){where}.");
        if (W.Projects?.Create == true)
            notes.Add($"Todavía no hay un vhost para cargar proyectos: se crea {Disposicion.ProjectVhost} (http y https, con su certificado y su línea en hosts, que pide permiso de administrador).");
        if (v.P2S == Core.Catalogo.Php2Shell.Estado.Vulnerable && v.Folder != st.Active)
            notes.Add($"{v.Folder} es vulnerable a PHP2Shell: {v.P2SWhy}.");
        if (notes.Count > 0)
        {
            var title = v.Folder != st.Active && confirmSwitch ? $"¿Cambiar a PHP {v.M.Php}?" : $"¿Crear {Disposicion.ProjectVhost}?";
            if (!Dialogo.Confirm(W, title, string.Join("\n\n", notes) + $"\n\n{Disposicion.ProjectVhost} apuntará a {folder}.", $"Cargar {folder}"))
                return;
        }
        if (remember && db.Length > 0)
        {
            try { W.Motor.Links.Write(new[] { (db, v.Folder, folder) }); }
            catch (Exception ex) { W.Toast("No se ha podido recordar la carpeta: " + ex.Message); }
        }
        var args = new List<string> { "cargar-proyecto", folder, v.Folder };
        if (db.Length > 0 && Validacion.IsDbName(db)) args.Add(db);
        W.RunTask($"Cargando el proyecto {folder}", args.ToArray(), new OpcionesTarea
        {
            DoneText = $"{Disposicion.ProjectVhost} apunta a {folder} (PHP {v.M.Php})", AutoClose = true, Env = W.PageOf<PaginaBbdd>("bbdd").DbEnv(),
            CancelText = ("¿Cancelar la carga?", "Se deja todo como estaba (el proyecto y la versión de antes).", "Cancelar la carga"),
            OnDone = (ok, _) => { if (ok) _selected = folder; },
        });
    }

    // ------------------------------------------------------------------ vincular
    /// <summary>Con qué BBDD va la carpeta en cada versión (o con ninguna). Cada BBDD es de un solo proyecto en cada versión.</summary>
    void LinkDialog(Proyecto x)
    {
        var st = W.State!;
        var versions = st.Versions.OrderByDescending(v => v.M.Php, Versiones.Comparer).ToList();
        if (versions.Count == 0) return;
        var pairs = W.ProjectPairs(x);
        var d = new Dialogo(W, $"BBDD de {x.Name} en cada versión",
            "Cargar proyecto monta la versión con la BBDD que elijas aquí. Con «Ninguna», la carpeta deja de ir con esa versión (la BBDD no se toca). " +
            "Cada BBDD es de un solo proyecto en cada versión: si era de otro, deja de serlo.", 600);
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var combos = new List<(VersionInfo V, ComboBox C, List<string> Mine)>();
        for (int i = 0; i < versions.Count; i++)
        {
            var v = versions[i];
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var l = Ui.Text($"PHP {v.M.Php}  ({v.Folder})");
            l.Margin = new Thickness(0, 4, 12, 4);
            Grid.SetRow(l, i);
            grid.Children.Add(l);
            var mine = pairs.Where(t => t.Ver.Folder == v.Folder).Select(t => t.Db).ToList();
            var items = new List<(string, string)> { ("@ninguna", "— Ninguna —") };
            foreach (var db in v.Dbs.Select(b => b.Name).OrderBy(n => n, StringComparer.OrdinalIgnoreCase))
            {
                var other = W.Projects?.LinkOf(db, v.Folder);
                items.Add((db, other is null or "" || other == x.Name ? db : $"{db}  (de {other})"));
            }
            var c = Ui.Combo(items, mine.FirstOrDefault() ?? "@ninguna", 320);
            c.IsEnabled = v.Dbs.Count > 0;
            c.Margin = new Thickness(0, 4, 0, 4);
            Grid.SetRow(c, i);
            Grid.SetColumn(c, 1);
            grid.Children.Add(c);
            combos.Add((v, c, mine));
        }
        d.Add(grid);
        d.Buttons("Guardar");
        if (!d.Run())
            return;
        var changes = new List<(string, string, string)>();
        foreach (var (v, c, mine) in combos)
        {
            var neu = c.SelectedId() is { } id && id != "@ninguna" ? id : "";
            foreach (var old in mine.Where(o => o != neu))
                changes.Add((old, v.Folder, ""));
            // (también la que solo venía de su configuración: así queda fija)
            if (neu.Length > 0 && W.Projects?.LinkOf(neu, v.Folder) != x.Name)
                changes.Add((neu, v.Folder, x.Name));
        }
        if (changes.Count == 0) return;
        try
        {
            W.Motor.Links.Write(changes);
            W.Toast($"Vínculos de {x.Name} guardados");
        }
        catch (Exception ex)
        {
            Dialogo.Message(W, "No se han podido guardar los vínculos", ex.Message, error: true);
        }
        W.Reload();
    }

    // ------------------------------------------------------------------ replicar en otra versión
    /// <summary>
    /// Copia la BBDD de un proyecto a otra versión con el nombre que se elija (se propone el de la de destino:
    /// wp_x_8_4 → wp_x_8_5) y la vincula allí a la carpeta que se elija.
    /// </summary>
    void Replicate(Proyecto x)
    {
        var st = W.State!;
        var pairs = W.ProjectPairs(x).OrderByDescending(t => t.Ver.M.Php, Versiones.Comparer).ToList();
        if (pairs.Count == 0)
        {
            Dialogo.Message(W, "No hay nada que replicar", $"{x.Name} no tiene su BBDD en ninguna versión instalada.");
            return;
        }
        if (st.Versions.Count < 2)
        {
            Dialogo.Message(W, "No hay otra versión de PHP", "Instala otra versión de PHP (con sus propias BBDD) para replicar un proyecto en ella.");
            return;
        }
        var d = new Dialogo(W, "Replicar un proyecto en otra versión de PHP",
            "Se copia su BBDD a la otra versión, con el nombre que elijas, y allí queda vinculada a la carpeta que elijas: después, Cargar proyecto lo " +
            "monta con esa versión. La versión de origen no se toca.", 620);
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        int row = 0;
        T Field<T>(string label, T w) where T : FrameworkElement
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var l = Ui.Text(label, "tenue");
            l.Margin = new Thickness(0, 6, 12, 6);
            Grid.SetRow(l, row);
            grid.Children.Add(l);
            w.Margin = new Thickness(0, 5, 0, 5);
            Grid.SetRow(w, row);
            Grid.SetColumn(w, 1);
            grid.Children.Add(w);
            row++;
            return w;
        }
        var src = Field("Desde", Ui.Combo(pairs.Select((t, i) => (i.ToString(), $"PHP {t.Ver.M.Php}  ({t.Ver.Folder})  ·  BBDD {t.Db}")),
            Math.Max(0, pairs.FindIndex(t => t.Ver.Folder == st.Active)).ToString(), 380));
        var dst = Field("A la versión", Ui.Combo(Array.Empty<(string, string)>(), null, 380));
        var name = Field("Nombre de la BBDD", new TextBox { MaxLength = 64 });
        var hint = Field("", Ui.Wrap("", "chico", "tenue"));
        var folders = Escaner.Folders(W.Motor.L.Htdocs);
        var folder = Field("Carpeta", Ui.Combo(new[] { ("@ninguna", "— Ninguna: vincúlala después —") }.Concat(folders.Select(f => (f, f))), x.Name, 380));
        Field("", Ui.Wrap("La carpeta del proyecto con la que se cargará en esa versión (si tiene una propia para ella, elígela).", "chico", "tenue"));
        d.Add(grid);
        d.Buttons("Replicar");
        var targets = new List<VersionInfo>();
        var auto = true;
        var setting = false;
        (VersionInfo Ver, string Db)? Source() => int.TryParse(src.SelectedId(), out var i) && i >= 0 && i < pairs.Count ? pairs[i] : null;
        VersionInfo? Target() => int.TryParse(dst.SelectedId(), out var i) && i >= 0 && i < targets.Count ? targets[i] : null;
        void Update()
        {
            var t = Target();
            var n = name.Text.Trim();
            var valid = Validacion.DbNameProblem(n) == null;
            if (!valid) { hint.Text = "Letras sin acentos, números, _ y - (sin - delante)."; hint.SetResourceReference(TextBlock.ForegroundProperty, "TextoTenue"); }
            else if (t != null && t.Dbs.Any(b => b.Name == n))
            {
                hint.Text = $"{t.Folder} ya tiene una BBDD {n}: se sustituye (antes se guarda una copia suya en {W.Motor.L.CopiesDir}).";
                hint.SetResourceReference(TextBlock.ForegroundProperty, "Rojo");
            }
            else { hint.Text = t != null ? $"Se crea {n} en {t.Folder}." : ""; hint.SetResourceReference(TextBlock.ForegroundProperty, "TextoTenue"); }
            d.OkEnabled = valid && t != null && Source() != null;
        }
        void OnTarget()
        {
            var s = Source();
            var t = Target();
            if (s != null && t != null && auto)
            {
                setting = true;
                name.Text = CopyName(s.Value.Db, t.M.Php);
                setting = false;
            }
            Update();
        }
        void OnSource()
        {
            var s = Source();
            targets = st.Versions.Where(v => s != null && v.Folder != s.Value.Ver.Folder).OrderByDescending(v => v.M.Php, Versiones.Comparer).ToList();
            dst.Items.Clear();
            for (int i = 0; i < targets.Count; i++)
                dst.Items.Add(new ComboBoxItem { Content = $"PHP {targets[i].M.Php}  ({targets[i].Folder})", Tag = i.ToString() });
            dst.SelectedIndex = targets.Count > 0 ? 0 : -1;
            OnTarget();
        }
        src.SelectionChanged += (_, _) => OnSource();
        dst.SelectionChanged += (_, _) => OnTarget();
        name.TextChanged += (_, _) => { if (!setting) auto = false; Update(); };
        OnSource();
        if (!d.Run())
            return;
        var s = Source()!.Value;
        var t = Target()!;
        var newName = name.Text.Trim();
        var f = folder.SelectedId() is { } id && id != "@ninguna" ? id : null;
        var args = new List<string> { "copiar-bd", s.Db, s.Ver.Folder, t.Folder, "--como", newName, "--carpeta", f ?? "-" };
        var notes = new List<string> { $"Se copia {s.Db} de {s.Ver.Folder} (PHP {s.Ver.M.Php}) a {t.Folder} (PHP {t.M.Php}) como {newName}, y allí queda vinculada a {f ?? "ninguna carpeta"}." };
        if (t.Folder != st.Active)
            notes.Add($"{t.Folder} no es la activa: se arranca su MariaDB solo para la copia.");
        var replace = t.Dbs.Any(b => b.Name == newName);
        if (replace)
        {
            notes.Add($"{t.Folder} ya tiene una BBDD {newName}: se guarda antes una copia suya en {W.Motor.L.CopiesDir} y se pone en su lugar. Lo que tuviera se pierde (salvo en esa copia).");
            args.Add("--sustituir");
        }
        if (!Dialogo.Confirm(W, $"¿Replicar en {t.Folder}?", string.Join("\n\n", notes), replace ? $"Sustituir en {t.Folder}" : $"Replicar en {t.Folder}", destructive: replace))
            return;
        W.RunTask($"Replicando en {t.Folder}", args.ToArray(), new OpcionesTarea
        {
            DoneText = $"{s.Db} replicada en {t.Folder} como {newName}", AutoClose = true, Env = W.PageOf<PaginaBbdd>("bbdd").DbEnv(),
        });
    }

    /// <summary>Nombre propuesto para la copia en otra versión: sin el sufijo de versión que traiga y con el de la de destino.</summary>
    public static string CopyName(string db, string php)
    {
        var b = Regex.Replace(db, @"[_-]\d+_\d+(_\d+)?$", "");
        if (b.Length == 0) b = db;
        var parts = php.Split('.');
        var name = $"{b}_{parts[0]}_{(parts.Length > 1 ? parts[1] : "0")}";
        return name.Length <= 64 ? name : db;
    }

    // ------------------------------------------------------------------ nuevo
    /// <summary>Proyecto nuevo: una carpeta en htdocs; con dominio, el de producción falseado (como en Dominios y hosts).</summary>
    void NewProject()
    {
        var d = new Dialogo(W, "Proyecto nuevo",
            $"Una carpeta nueva en {W.Motor.L.Htdocs}. Si le pones su dominio de producción, se crea también su vhost con certificado y se falsea en hosts " +
            "(como «Nuevo proyecto con dominio falseado» en Dominios y hosts). Para clonar un repositorio, clónalo en htdocs y aparecerá en la lista.", 540);
        var folders = Escaner.Folders(W.Motor.L.Htdocs);
        var folder = new TextBox { MaxLength = 64 };
        var domain = new TextBox { MaxLength = 120 };
        var hint = Ui.Wrap("", "chico", "tenue");
        d.Add(Ui.Text("Carpeta", "tenue"));
        d.Add(folder);
        d.Add(Ui.Text("Dominio de producción (opcional)", "tenue"));
        d.Add(domain);
        d.Add(hint);
        d.Buttons("Crear");
        void Update()
        {
            var f = folder.Text.Trim();
            var dom = domain.Text.Trim().ToLowerInvariant();
            var ok = Validacion.IsNewFolder(f) && !Validacion.IsReservedWindowsName(f) && !folders.Contains(f, StringComparer.OrdinalIgnoreCase);
            var domOk = dom.Length == 0 || Validacion.IsDomain(dom);
            hint.Text = f.Length > 0 && folders.Contains(f, StringComparer.OrdinalIgnoreCase) ? "Ya existe esa carpeta." :
                !domOk ? "Dominio no válido (por ejemplo: mitienda.com)." : "Letras sin acentos, números, punto, _ y -";
            d.OkEnabled = ok && domOk;
        }
        folder.TextChanged += (_, _) => Update();
        domain.TextChanged += (_, _) => Update();
        d.Loaded += (_, _) => folder.Focus();
        Update();
        if (!d.Run())
            return;
        var name = folder.Text.Trim();
        var dom2 = domain.Text.Trim().ToLowerInvariant();
        if (dom2.Length > 0)
        {
            W.RunTask($"Creando {dom2}", new[] { "nuevo-dominio", dom2, name }, new OpcionesTarea
            {
                DoneText = $"{dom2} listo", OnDone = (ok, _) => { if (ok) _selected = name; },
            });
            return;
        }
        try
        {
            Directory.CreateDirectory(Path.Combine(W.Motor.L.Htdocs, name));
            _selected = name;
            W.Toast($"Carpeta {name} creada en htdocs");
            W.Reload();
        }
        catch (Exception ex)
        {
            Dialogo.Message(W, "No se ha podido crear la carpeta", ex.Message, error: true);
        }
    }
}
