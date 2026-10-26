using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Microsoft.Win32;
using NexumDevStack.Core.Pila;
using NexumDevStack.Core.Proyectos;
using NexumDevStack.Core.Util;

namespace NexumDevStack.App.Paginas;

/// <summary>
/// Bases de datos (como la pestaña de Linux desde la 1.54): tarjetas, una tabla plegable por versión (una
/// desplegada a la vez) con el proyecto, el tamaño y la fecha de cada BBDD y sus acciones, y «Subir o
/// actualizar una BBDD» debajo.
/// </summary>
public sealed class PaginaBbdd : Pagina
{
    static readonly double[] Widths = { 280, 210, 100, 220, 0 };
    readonly Dictionary<string, string> _dbPwd = new();
    readonly HashSet<string> _expanded = new();
    string _query = "";
    bool _onlyActive;
    TextBox? _search;
    Grid? _searchBox;
    StackPanel? _table;

    // Formulario de subir una BBDD (se conserva al redibujar)
    public string? ImportFile { get; set; }
    public string? ImportDb { get; set; }
    public string? ImportProject { get; set; }
    string? _importFor;

    public PaginaBbdd(VentanaPrincipal w) : base(w, 900) { }

    public override void Shown()
    {
        // Al entrar en el apartado, las versiones aparecen plegadas (salvo la activa)
        _expanded.Clear();
        if (W.State?.Active is { } a) _expanded.Add(a);
        Table();
    }

    /// <summary>MYSQL_PWD si root de la versión activa tiene contraseña (se pide una vez).</summary>
    public Dictionary<string, string?>? DbEnv()
    {
        var a = W.State?.Active;
        return a != null && _dbPwd.TryGetValue(a, out var p) ? new Dictionary<string, string?> { ["MYSQL_PWD"] = p } : null;
    }

    public override void Build()
    {
        Content.Children.Clear();
        var st = W.State;
        var act = st?.ActiveInfo;
        var pma = Ui.Button(Ui.Logo("phpmyadmin", 15), "phpMyAdmin", "phpMyAdmin de la versión activa", () => W.OpenUri("http://127.0.0.1/phpmyadmin/"));
        pma.IsEnabled = act != null && st!.Running;
        var create = Ui.Button(Ico.Mas, "Nueva BBDD…", act != null ? $"Crear una BBDD vacía en {act.Folder}" : "No hay ninguna versión activa", OnCreate, "BotonAzul");
        create.IsEnabled = act != null && !W.Busy;
        Content.Children.Add(Ui.PageTitle(Ui.Logo("mariadb", 30), "Bases de datos", "Cada versión con su MariaDB y sus BBDD (sin las del sistema)", pma, create));
        if (st == null)
        {
            Loading();
            return;
        }
        if (!Prepared)
        {
            NotPrepared();
            return;
        }
        // Tarjetas: cuántas hay, en la activa y la última que ha cambiado
        var all = st.Versions.SelectMany(v => v.Dbs.Select(d => (v, d))).ToList();
        var latest = all.OrderByDescending(x => x.d.When).FirstOrDefault();
        var cards = new UniformGridish(3);
        cards.Add(Stat("BBDD", all.Count.ToString(), Texto.Plural(st.Versions.Count(v => v.Dbs.Count > 0), "versión", "versiones")));
        cards.Add(Stat("En la versión activa", act != null ? act.Dbs.Count.ToString() : "—", act != null ? $"{act.Folder} · MariaDB {act.M.MariaDb}" : "ninguna activa"));
        cards.Add(Stat("La última que ha cambiado", latest.d?.Name ?? "—",
            latest.d != null ? $"{latest.v.Folder} · {Texto.Age(Math.Max(0, DateTimeOffset.UtcNow.ToUnixTimeSeconds() - latest.d.When))}" : ""));
        cards.Panel.Margin = new Thickness(0, 0, 0, 16);
        Content.Children.Add(cards.Panel);

        var tools = new Grid { Margin = new Thickness(0, 0, 0, 10) };
        if (_searchBox == null)
        {
            (_searchBox, _search) = Ui.SearchBox("Buscar una BBDD o su proyecto", 320);
            _search.TextChanged += OnSearch;
        }
        tools.Children.Add(Ui.Detach(_searchBox));
        var onlyBox = Ui.HStack(10, Ui.Text("Solo la versión activa", "chico", "tenue"), Ui.Switch(_onlyActive, v => { _onlyActive = v; Table(); }));
        onlyBox.HorizontalAlignment = HorizontalAlignment.Right;
        tools.Children.Add(onlyBox);
        Content.Children.Add(tools);
        _table = new StackPanel();
        Content.Children.Add(_table);
        Table();
        Content.Children.Add(ImportForm());
    }

    void OnSearch(object? sender, TextChangedEventArgs e)
    {
        _query = _search!.Text.Trim().ToLowerInvariant();
        Table();
    }

    static Border Stat(string title, string value, string sub)
    {
        var sp = new StackPanel();
        sp.Children.Add(Ui.Text(title, "chico", "tenue"));
        var v = Ui.Text(value);
        v.FontSize = 20;
        v.FontWeight = FontWeights.SemiBold;
        v.Margin = new Thickness(0, 4, 0, 2);
        sp.Children.Add(v);
        sp.Children.Add(Ui.Text(sub, "chico", "tenue"));
        return Ui.Card(sp, 14, 12);
    }

    /// <summary>Tres tarjetas del mismo ancho.</summary>
    sealed class UniformGridish
    {
        public Grid Panel { get; } = new();
        int _n;
        public UniformGridish(int columns)
        {
            for (int i = 0; i < columns; i++)
                Panel.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        }
        public void Add(FrameworkElement e)
        {
            e.Margin = new Thickness(_n == 0 ? 0 : 6, 0, _n == Panel.ColumnDefinitions.Count - 1 ? 0 : 6, 0);
            Grid.SetColumn(e, _n++);
            Panel.Children.Add(e);
        }
    }

    /// <summary>Proyecto de una BBDD en una versión: el vinculado o el único que la usa en su configuración.</summary>
    string ProjectOf(string db, string folder)
    {
        var f = W.Projects?.LinkOf(db, folder);
        if (f != null) return f;
        var users = (W.Projects?.List ?? new()).Where(x => x.Db == db).Select(x => x.Name).ToList();
        return users.Count == 1 ? users[0] : "";
    }

    void Table()
    {
        if (_table == null || W.State == null)
            return;
        _table.Children.Clear();
        var st = W.State;
        var q = _query;
        var usedDb = W.LoadedProjectDb();
        var loaded = W.LoadedProject();
        var list = new StackPanel();
        list.Children.Add(Ui.TableRow(Widths, new UIElement[]
        {
            Ui.Text("NOMBRE", "cab"), Ui.Text("PROYECTO", "cab"), Ui.Text("TAMAÑO", "cab"), Ui.Text("CAMBIADA", "cab"), Ui.Text("ACCIONES", "cab"),
        }, true));
        var shown = 0;
        foreach (var v in st.Versions.OrderByDescending(v => v.M.Php, Versiones.Comparer))
        {
            var active = v.Folder == st.Active;
            if (_onlyActive && !active) continue;
            var rows = v.Dbs.Select(d => (d, proj: ProjectOf(d.Name, v.Folder)))
                .Where(r => q.Length == 0 || r.d.Name.ToLowerInvariant().Contains(q) || r.proj.ToLowerInvariant().Contains(q)).ToList();
            if (q.Length > 0 && rows.Count == 0) continue;
            shown++;
            var opened = q.Length > 0 || _expanded.Contains(v.Folder);
            var name = new StackPanel { Orientation = Orientation.Horizontal };
            name.Children.Add(Ui.Icon(opened ? Ico.Abajo : Ico.Derecha, 11, "TextoTenue"));
            var ic = new Border { CornerRadius = new System.Windows.CornerRadius(8), Padding = new Thickness(5), Margin = new Thickness(8, 0, 8, 0), Child = Ui.Logo("mariadb", 14) };
            ic.SetResourceReference(Border.BackgroundProperty, "AzulSuave");
            name.Children.Add(ic);
            name.Children.Add(Ui.Text(v.Folder, "mono", "negrita"));
            if (active)
            {
                var t = Ui.Tag("Activa", blue: true);
                t.Margin = new Thickness(8, 0, 0, 0);
                name.Children.Add(t);
            }
            long total = v.Dbs.Sum(d => W.DbSizes.TryGetValue((v.Folder, d.Name), out var s) ? s.Bytes : 0);
            var acts = new StackPanel { Orientation = Orientation.Horizontal };
            if (active)
            {
                var b1 = Ui.Button(Ui.Logo("phpmyadmin", 14), null, "Abrir phpMyAdmin", () => W.OpenUri("http://127.0.0.1/phpmyadmin/"), "BotonPlano");
                b1.IsEnabled = st.Running;
                acts.Children.Add(b1);
                var b2 = Ui.Button(Ico.Mas, null, "Crear una BBDD vacía aquí", OnCreate, "BotonPlano");
                b2.IsEnabled = !W.Busy;
                acts.Children.Add(b2);
            }
            var head = Ui.TableRow(Widths, new UIElement[]
            {
                name, Ui.Text($"PHP {v.M.Php} · MariaDB {v.M.MariaDb}", "chico", "tenue"),
                total > 0 ? Ui.Text(Texto.Size(total), "chico", "mono") : Ui.Text("—", "chico", "tenue"),
                Ui.Text(Texto.Plural(v.Dbs.Count, "BBDD", "BBDD"), "chico", "tenue"), acts,
            });
            var headBorder = new Border { Child = head, BorderThickness = new Thickness(0, 1, 0, 0), Cursor = Cursors.Hand, Background = System.Windows.Media.Brushes.Transparent };
            headBorder.SetResourceReference(Border.BorderBrushProperty, "BordeSuave");
            var folder = v.Folder;
            headBorder.MouseLeftButtonUp += (_, e) =>
            {
                if (e.OriginalSource is FrameworkElement fe && FindButton(fe) != null) return;
                // (una desplegada a la vez: al abrir otra, se cierra la anterior)
                if (!_expanded.Remove(folder))
                {
                    _expanded.Clear();
                    _expanded.Add(folder);
                }
                Table();
            };
            list.Children.Add(headBorder);
            if (!opened) continue;
            foreach (var (d, proj) in rows)
                list.Children.Add(DbRow(v, d, proj, active && loaded != null && d.Name == usedDb, loaded?.Name));
        }
        if (shown == 0)
        {
            var empty = Ui.Text(q.Length > 0 ? $"Ninguna BBDD con «{q}»" : "No hay versiones con BBDD", "tenue");
            empty.Margin = new Thickness(14);
            list.Children.Add(empty);
        }
        _table.Children.Add(Ui.Card(list));
        _table.Margin = new Thickness(0, 0, 0, 24);
    }

    static Button? FindButton(DependencyObject? d)
    {
        while (d != null)
        {
            if (d is Button b) return b;
            d = System.Windows.Media.VisualTreeHelper.GetParent(d);
        }
        return null;
    }

    UIElement DbRow(VersionInfo v, Core.BaseDatos.Bbdd d, string proj, bool used, string? loadedName)
    {
        var active = v.Folder == W.State?.Active;
        var n = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(26, 0, 0, 0) };
        var dot = Ui.Dot(used, 8);
        if (!used) dot.Opacity = 0.25;
        else dot.ToolTip = $"La usa el proyecto cargado ({loadedName})";
        n.Children.Add(dot);
        if (d.Name.StartsWith("ps_", StringComparison.OrdinalIgnoreCase))
            n.Children.Add(Margin(Ui.Logo("prestashop", 14)));
        else if (d.Name.StartsWith("wp_", StringComparison.OrdinalIgnoreCase))
            n.Children.Add(Margin(Ui.Logo("wordpress", 14)));
        var name = Ui.Text(d.Name, "mono", "chico");
        name.Margin = new Thickness(8, 0, 0, 0);
        name.ToolTip = d.Name;
        n.Children.Add(name);
        var size = W.DbSizes.TryGetValue((v.Folder, d.Name), out var s)
            ? new TextBlock { Text = Texto.Size(s.Bytes), ToolTip = $"Datos e índices, medido el {Texto.Stamp(DateTimeOffset.FromUnixTimeSeconds(s.When))}" }
            : new TextBlock { Text = "—", ToolTip = "Se mide cuando su versión está activa y en marcha" };
        size.FontSize = 11.5;
        size.FontFamily = Ui.Mono;
        size.SetResourceReference(TextBlock.ForegroundProperty, s.Bytes > 0 ? "Texto" : "TextoTenue");
        var changed = d.When > 0
            ? Ui.Text(Texto.Stamp(DateTimeOffset.FromUnixTimeSeconds(d.When)) + (d.Kind == 'i' ? " · importada" : ""), "chico", "mono")
            : Ui.Text("—", "chico", "tenue");
        if (d.When > 0)
            changed.ToolTip = Texto.DbDate(d.When, d.Kind) + (d.Kind == 'c'
                ? "\nFecha en la que cambiaron por última vez las tablas de la BBDD (al importarla desde phpMyAdmin, por ejemplo). Las que se suben desde aquí guardan la fecha exacta de la importación."
                : "");
        var acts = new StackPanel { Orientation = Orientation.Horizontal };
        if (d.Name.StartsWith("ps_", StringComparison.OrdinalIgnoreCase))
            acts.Children.Add(Plain(Ico.Limpiar, $"Vaciar la caché (var/cache) de la tienda de {d.Name}", () => W.RunTask($"Vaciando la caché de la tienda de {d.Name}",
                new[] { "vaciar-cache", "--bd", d.Name }, new OpcionesTarea { DoneText = "Caché vaciada", AutoClose = true })));
        if ((W.State?.Versions.Count ?? 0) > 1)
            acts.Children.Add(Plain(Ico.Copiar, $"Copiar {d.Name} a otra versión de PHP (para probar el proyecto con ella)", () => CopyDb(d.Name, v)));
        acts.Children.Add(Plain(Ico.Descargar, $"Descargar una copia de {d.Name} (.zip)", () => Download(d.Name, v)));
        acts.Children.Add(Plain(Ico.CarpetaAbierta, $"Cargar su proyecto (en {v.Folder})", () => LoadProject(d.Name, v)));
        if (active)
            acts.Children.Add(Plain(Ico.Papelera, $"Borrar la BBDD {d.Name}", () => Drop(d.Name)));
        var row = Ui.TableRow(Widths, new UIElement[]
        {
            n, Ui.Text(proj.Length > 0 ? proj : "—", "chico", proj.Length > 0 ? "negrita" : "tenue"), size, changed, acts,
        });
        var b = new Border { Child = row, BorderThickness = new Thickness(0, 1, 0, 0) };
        b.SetResourceReference(Border.BorderBrushProperty, "BordeSuave");
        b.SetResourceReference(Border.BackgroundProperty, "FondoFila");
        return b;
    }

    static FrameworkElement Margin(FrameworkElement e)
    {
        e.Margin = new Thickness(8, 0, 0, 0);
        return e;
    }

    Button Plain(string glyph, string tip, Action click)
    {
        var b = Ui.Button(glyph, null, tip, click, "BotonPlano");
        b.IsEnabled = !W.Busy;
        b.Padding = new Thickness(7, 4, 7, 4);
        b.MinHeight = 28;
        return b;
    }

    // ------------------------------------------------------------------ acceso a MariaDB
    /// <summary>Comprueba que se puede entrar en el MariaDB activo; si root tiene contraseña, la pide. Después, then().</summary>
    public void CheckDbAccess(Action then, bool retry = false)
    {
        var st = W.State;
        var a = st?.Active;
        if (a == null)
        {
            Dialogo.Message(W, "No hay ninguna versión activa", "Activa una en Versiones de PHP.");
            return;
        }
        if (!st!.MariaDbOn)
        {
            Dialogo.Message(W, "No se puede entrar en MariaDB", $"El MariaDB de {a} no está en marcha. Arráncalo arriba (Parados → Encendidos).");
            return;
        }
        _dbPwd.TryGetValue(a, out var pwd);
        Task.Run(() =>
        {
            var c = W.Motor.Client(a);
            var client = new Core.BaseDatos.ClienteMariaDb(W.Motor.Pf.Processes, c.BinDir, c.Port, pwd);
            var (state, detail) = client.Check();
            W.Dispatcher.BeginInvoke(() =>
            {
                if (state == "ok")
                    then();
                else if (state == "clave")
                {
                    var p = AskPassword(a, pwd != null);
                    if (p != null)
                    {
                        _dbPwd[a] = p;
                        CheckDbAccess(then, true);
                    }
                }
                else
                    Dialogo.Message(W, "No se puede entrar en MariaDB", detail, error: true);
            });
        });
    }

    string? AskPassword(string folder, bool retry)
    {
        var d = new Dialogo(W, "Contraseña de MariaDB", $"El usuario root del MariaDB de {folder} tiene contraseña. Escríbela para continuar.", 420);
        if (retry)
            d.Add(Ui.Text("Contraseña incorrecta. Vuelve a intentarlo.", "rojo"));
        var box = new PasswordBox();
        d.Add(box);
        d.Buttons("Continuar");
        d.Loaded += (_, _) => box.Focus();
        return d.Run() ? box.Password : null;
    }

    // ------------------------------------------------------------------ crear y borrar
    void OnCreate() => CheckDbAccess(AskNewDb);

    void AskNewDb()
    {
        var st = W.State!;
        var act = st.ActiveInfo!;
        var existing = act.Dbs.Select(d => d.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var name = Dialogo.Input(W, "Crear BBDD", $"Se crea vacía en el MariaDB de {act.Folder}, con juego de caracteres utf8mb4 (utf8mb4_general_ci).",
            "nombre_de_la_base", "Crear", v =>
            {
                if (v.Length == 0) return (false, "Letras sin acentos, números, _ y -", false);
                if (existing.Contains(v) || Validacion.IsSystemDb(v)) return (false, "Ya hay una BBDD con ese nombre.", true);
                if (Validacion.DbNameProblem(v) != null) return (false, "Letras sin acentos, números, _ y - (sin - delante)", true);
                var others = st.Versions.Where(x => x.Folder != act.Folder && x.Dbs.Any(d => d.Name == v)).Select(x => $"{x.Folder} (PHP {x.M.Php})").ToList();
                return others.Count > 0 ? (true, $"Ya existe en {string.Join(", ", others)}. Si sigues, se crea también en {act.Folder}.", false)
                    : (true, "Letras sin acentos, números, _ y -", false);
            });
        if (name == null)
            return;
        W.RunTask($"Creando la BBDD {name}", new[] { "crear-bd", name }, new OpcionesTarea
        {
            DoneText = $"BBDD «{name}» creada", AutoClose = true, Env = DbEnv(),
            OnDone = (ok, _) => { if (ok) ImportDb = name; },
        });
    }

    void Drop(string db) => CheckDbAccess(() =>
    {
        var folder = W.State!.Active!;
        (int Tables, long Bytes) info;
        try
        {
            var pwd = DbEnv()?["MYSQL_PWD"];
            var m = W.Motor;
            var old = m.RootPassword;
            m.RootPassword = pwd ?? old;
            info = m.DatabaseInfo(db);
            m.RootPassword = old;
        }
        catch (Exception ex)
        {
            Dialogo.Message(W, "No se puede borrar la BBDD", ex.Message, error: true);
            return;
        }
        var d = new Dialogo(W, $"¿Borrar la BBDD «{db}»?", info.Tables > 0
            ? $"En {folder}, con {Texto.Plural(info.Tables, "tabla", "tablas")} ({Texto.Size(info.Bytes)}). No se puede deshacer."
            : $"En {folder}, vacía (sin tablas). No se puede deshacer.");
        CheckBox? copy = null;
        TextBox? confirm = null;
        StackPanel? warn = null;
        if (info.Tables > 0)
        {
            copy = new CheckBox { Content = $"Guardar antes una copia en {W.Motor.L.CopiesDir} (se puede volver a cargar)", IsChecked = true };
            d.Add(copy);
            warn = new StackPanel { Visibility = Visibility.Collapsed };
            warn.Children.Add(Ui.Wrap($"Sin copia, el contenido no se podrá recuperar. Escribe {db} para confirmar:", "rojo"));
            confirm = new TextBox { Margin = new Thickness(0, 6, 0, 0) };
            warn.Children.Add(confirm);
            d.Add(warn);
        }
        d.Buttons("Borrar la BBDD", destructive: true);
        void Update()
        {
            var withCopy = copy?.IsChecked != false;
            if (warn != null) warn.Visibility = withCopy ? Visibility.Collapsed : Visibility.Visible;
            d.OkEnabled = withCopy || confirm?.Text.Trim() == db;
        }
        if (copy != null) copy.Click += (_, _) => Update();
        if (confirm != null) confirm.TextChanged += (_, _) => Update();
        Update();
        if (!d.Run())
            return;
        var backup = copy?.IsChecked == true;
        var args = new List<string> { "borrar-bd", db };
        if (backup) args.Add("--copia");
        W.RunTask($"Borrando la BBDD {db}", args.ToArray(), new OpcionesTarea
        {
            DoneText = $"BBDD «{db}» borrada" + (backup ? $" (copia en {W.Motor.L.CopiesDir})" : ""), AutoClose = true, Env = DbEnv(),
            OnDone = (ok, _) => { if (ok && ImportDb == db) ImportDb = null; },
        });
    });

    // ------------------------------------------------------------------ descargar y copiar
    void Download(string db, VersionInfo v)
    {
        var st = W.State!;
        var running = v.Folder == st.Active && st.MariaDbOn;
        var dlg = new SaveFileDialog
        {
            Title = $"Descargar la BBDD {db}", FileName = $"{db}-{v.Folder}-{DateTime.Now:yyyyMMdd-HHmm}.zip",
            Filter = "Copia comprimida (*.zip)|*.zip|SQL comprimido (*.sql.gz)|*.sql.gz|SQL (*.sql)|*.sql",
            InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) is { } home ? Path.Combine(home, "Downloads") : null,
            OverwritePrompt = true,
        };
        if (dlg.ShowDialog(W) != true)
            return;
        var path = dlg.FileName;
        if (!System.Text.RegularExpressions.Regex.IsMatch(path, @"(?i)(\.sql(\.gz)?|\.zip)$"))
            path += ".zip";
        void Start() => W.RunTask($"Descargando {db}", new[] { "exportar-bd", db, path, v.Folder }, new OpcionesTarea
        {
            DoneText = $"Copia de «{db}» guardada: {Path.GetFileName(path)}", Env = DbEnv(),
            CancelText = ("¿Cancelar la descarga?", "No se guarda nada.", "Cancelar la descarga"),
            OnDone = (ok, t) => { if (ok) t.Offer("Abrir la carpeta", () => W.OpenFolder(Path.GetDirectoryName(path)!)); },
        });
        if (running) CheckDbAccess(Start);
        else Start();
    }

    /// <summary>Copia la BBDD, con el mismo nombre, a otra versión (con otro nombre o carpeta: Replicar).</summary>
    void CopyDb(string db, VersionInfo src)
    {
        var st = W.State!;
        var targets = st.Versions.Where(x => x.Folder != src.Folder)
            .OrderBy(x => x.Dbs.Any(d => d.Name == db)).ThenByDescending(x => x.M.Php, Versiones.Comparer).ToList();
        if (targets.Count == 0)
            return;
        var d = new Dialogo(W, $"¿A qué versión de PHP copias {db}?",
            $"Se copia con el mismo nombre desde {src.Folder}, que no se toca. Para copiarla con otro nombre o con otra carpeta de proyecto, usa «Añadir entorno… En otra versión de PHP» en Proyectos.", 540);
        var radios = new List<(RadioButton Rb, VersionInfo V)>();
        foreach (var t in targets)
        {
            var has = t.Dbs.Any(x => x.Name == db);
            var (card, rb) = Dialogo.Option($"PHP {t.M.Php}  ({t.Folder})",
                (t.Folder == st.Active ? "la activa" : "") + (has ? (t.Folder == st.Active ? " · " : "") + "ya la tiene: se sustituye" : ""), "copiar", radios.Count == 0);
            radios.Add((rb, t));
            d.Add(card);
        }
        d.Buttons("Copiar");
        if (!d.Run())
            return;
        var chosen = radios.First(r => r.Rb.IsChecked == true).V;
        var replace = chosen.Dbs.Any(x => x.Name == db);
        var notes = new List<string> { $"Se copia {db} de {src.Folder} (PHP {src.M.Php}) a {chosen.Folder} (PHP {chosen.M.Php}), con el mismo nombre. La de {src.Folder} no se toca." };
        if (chosen.Folder != st.Active)
            notes.Add($"{chosen.Folder} no es la activa: se arranca su MariaDB solo para la copia.");
        if (replace)
            notes.Add($"{chosen.Folder} ya tiene una BBDD {db}: se guarda antes una copia suya en {W.Motor.L.CopiesDir} y después se pone en su lugar la de {src.Folder}.");
        if (!Dialogo.Confirm(W, replace ? $"¿Sustituir {db} en {chosen.Folder}?" : $"¿Copiar {db} a {chosen.Folder}?", string.Join("\n\n", notes),
                replace ? $"Sustituir en {chosen.Folder}" : $"Copiar a {chosen.Folder}", destructive: replace))
            return;
        var args = new List<string> { "copiar-bd", db, src.Folder, chosen.Folder };
        if (replace) args.Add("--sustituir");
        W.RunTask($"Copiando {db} a {chosen.Folder}", args.ToArray(), new OpcionesTarea { DoneText = $"{db} copiada a {chosen.Folder}", AutoClose = true, Env = DbEnv() });
    }

    // ------------------------------------------------------------------ cargar el proyecto de una BBDD
    void LoadProject(string db, VersionInfo v)
    {
        var p = W.Projects;
        if (p == null)
            return;
        var matches = p.List.Where(x => x.Db == db).Select(x => x.Name).ToList();
        var saved = p.LinkOf(db, v.Folder);
        string? folder;
        var manual = false;
        if (saved != null && p.List.Any(x => x.Name == saved))
            folder = saved;
        else if (matches.Count == 1 && saved != "")
            folder = matches[0];
        else
        {
            folder = PickProjectFolder(db, p.List, matches);
            manual = true;
        }
        if (folder == null)
            return;
        W.PageOf<PaginaProyectos>("proyectos").DoLoad(folder, db, v, confirmSwitch: true, remember: manual);
    }

    string? PickProjectFolder(string db, List<Proyecto> projects, List<string> matches)
    {
        var d = new Dialogo(W, $"Proyecto de {db}", matches.Count > 1
            ? $"Hay {matches.Count} carpetas que usan «{db}». Elige la que quieres cargar (se recuerda para esta BBDD):"
            : $"No hay ninguna carpeta cuya configuración use «{db}». Elige la del proyecto (se recuerda para esta BBDD):", 560);
        var find = new TextBox { ToolTip = "Buscar una carpeta de htdocs" };
        d.Add(find);
        var list = new ListBox { Height = 280, BorderThickness = new Thickness(1), Background = System.Windows.Media.Brushes.Transparent };
        list.SetResourceReference(Control.BorderBrushProperty, "Borde");
        list.SetResourceReference(Control.ForegroundProperty, "Texto");
        foreach (var x in projects.OrderBy(x => x.Db != db).ThenBy(x => x.Name, StringComparer.OrdinalIgnoreCase))
        {
            var sub = x.Db == db ? "Usa esta BBDD" : x.Db.Length > 0 ? $"BBDD: {x.Db}" : "Sin BBDD detectada";
            list.Items.Add(new ListBoxItem { Content = Ui.VStack(2, Ui.Text(x.Name), Ui.Text(sub, "chico", "tenue")), Tag = x.Name, Padding = new Thickness(8, 6, 8, 6) });
        }
        find.TextChanged += (_, _) =>
        {
            var q = find.Text.Trim().ToLowerInvariant();
            foreach (ListBoxItem it in list.Items)
                it.Visibility = ((string)it.Tag).ToLowerInvariant().Contains(q) ? Visibility.Visible : Visibility.Collapsed;
        };
        d.Add(list);
        d.Buttons("Cargar proyecto");
        d.OkEnabled = false;
        list.SelectionChanged += (_, _) => d.OkEnabled = list.SelectedItem != null;
        list.MouseDoubleClick += (_, _) => { if (list.SelectedItem != null) d.Close(true); };
        d.Loaded += (_, _) => find.Focus();
        return d.Run() ? (list.SelectedItem as ListBoxItem)?.Tag as string : null;
    }

    // ------------------------------------------------------------------ subir o actualizar una BBDD
    StackPanel ImportForm()
    {
        var st = W.State!;
        var act = st.ActiveInfo;
        var (box, list) = Ui.Group("Subir o actualizar una BBDD",
            "Carga una copia .sql, .sql.gz o .zip en el MariaDB de la versión activa" + (act != null ? $", {act.Folder} (MariaDB {act.M.MariaDb})" : "") +
            $". Antes se borran todas las tablas de la BBDD de destino (con una copia en {W.Motor.L.CopiesDir}), para que no quede nada de lo anterior. " +
            "Los .zip se descomprimen solos. Se carga con un usuario que solo puede tocar esa BBDD.");
        if (act == null)
        {
            Ui.AddRow(list, Ui.Row("No hay ninguna versión activa", "Activa una versión en Versiones de PHP para cargar BBDD.").Row);
            return box;
        }
        if (ImportDb != null && !act.Dbs.Any(d => d.Name == ImportDb))
            ImportDb = null;
        var sub = "Ningún fichero elegido";
        if (ImportFile != null)
            sub = File.Exists(ImportFile) ? $"{Path.GetFileName(ImportFile)}  ·  {Texto.Size(new FileInfo(ImportFile).Length)}" : $"{Path.GetFileName(ImportFile)}  ·  ya no existe";
        var (r1, s1, _, _) = Ui.Row("Fichero SQL", sub, Ui.Icon(Ico.Documento, 15));
        r1.ToolTip = ImportFile;
        s1.Children.Add(Ui.TextButton("Elegir…", PickSql));
        Ui.AddRow(list, r1);

        var (r2, s2, _, _) = Ui.Row("BBDD de destino", $"En {act.Folder}", Ui.Logo("mariadb", 16));
        var items = act.Dbs.Select(d => (d.Name, d.Name)).ToList();
        if (ImportDb == null) items.Insert(0, ("@ninguna", "Elige una BBDD"));
        var combo = Ui.Combo(items, ImportDb ?? "@ninguna", 240);
        combo.SelectionChanged += (_, _) =>
        {
            var id = combo.SelectedId();
            if (id == null || id == "@ninguna") return;
            ImportDb = id;
            var guess = Guess(id, act.Folder);
            if (guess != null) ImportProject = guess;
            _importFor = id;
            W.Dispatcher.BeginInvoke(Build);
        };
        s2.Children.Add(combo);
        var add = Ui.Button(Ico.Mas, null, "Crear una BBDD nueva", OnCreate);
        add.Margin = new Thickness(8, 0, 0, 0);
        s2.Children.Add(add);
        var drop = Ui.Button(Ico.Papelera, null, "Borrar la BBDD elegida", () => { if (ImportDb != null) Drop(ImportDb); });
        drop.Margin = new Thickness(8, 0, 0, 0);
        drop.IsEnabled = ImportDb != null;
        s2.Children.Add(drop);
        Ui.AddRow(list, r2);

        var folders = Escaner.Folders(W.Motor.L.Htdocs);
        if (ImportProject != null && !folders.Contains(ImportProject)) ImportProject = null;
        if (ImportDb != null && _importFor != ImportDb)
        {
            ImportProject = Guess(ImportDb, act.Folder) ?? ImportProject;
            _importFor = ImportDb;
        }
        var (r3, s3, _, sub3) = Ui.Row("Proyecto", ProjectHint(), Ui.Icon(Ico.CarpetaAbierta, 15));
        var pitems = new List<(string, string)> { ("@ninguno", "Ninguno") };
        pitems.AddRange(folders.Select(f => (f, f)));
        var pcombo = Ui.Combo(pitems, ImportProject ?? "@ninguno", 300);
        pcombo.SelectionChanged += (_, _) =>
        {
            var id = pcombo.SelectedId();
            ImportProject = id is null or "@ninguno" ? null : id;
            _importFor = ImportDb;
            sub3.Text = ProjectHint();
        };
        s3.Children.Add(pcombo);
        Ui.AddRow(list, r3);

        string hint = !st.MariaDbOn ? "La versión activa está parada: arráncala arriba." : ImportFile == null ? "Elige el fichero SQL." :
            ImportDb == null ? "Elige la BBDD de destino o crea una con +." : "";
        var load = Ui.TextButton("Cargar", OnImport, "BotonAzul");
        load.MinWidth = 160;
        load.IsEnabled = hint.Length == 0 && !W.Busy;
        load.HorizontalAlignment = HorizontalAlignment.Center;
        load.Margin = new Thickness(0, 14, 0, 0);
        box.Children.Add(load);
        if (hint.Length > 0)
        {
            var h = Ui.Text(hint, "chico", "tenue");
            h.HorizontalAlignment = HorizontalAlignment.Center;
            h.Margin = new Thickness(0, 6, 0, 0);
            box.Children.Add(h);
        }
        return box;
    }

    string? Guess(string db, string ver)
    {
        var p = W.Projects;
        var link = p?.LinkOf(db, ver);
        if (link == "") return null;
        var folders = Escaner.Folders(W.Motor.L.Htdocs);
        if (link != null && folders.Contains(link)) return link;
        var users = (p?.List ?? new()).Where(x => x.Db == db).Select(x => x.Name).ToList();
        if (users.Count == 1) return users[0];
        return Escaner.NameMatch(W.Motor.L.Htdocs, db, folders);
    }

    string ProjectHint()
    {
        if (ImportProject == null)
            return "Opcional: si es la BBDD nueva de un proyecto, elige su carpeta.";
        return Escaner.Kind(W.Motor.L.Htdocs, ImportProject) switch
        {
            "wp" => "Su wp-config.php se rehace con la plantilla de este equipo para usar esta BBDD.",
            "ps" => "Su parameters.php (o settings.inc.php) pasa a usar esta BBDD y se vacía su caché.",
            _ => "La BBDD queda asociada a esta carpeta (Cargar proyecto la usa).",
        };
    }

    void PickSql()
    {
        var dlg = new OpenFileDialog
        {
            Title = "Elegir el fichero SQL", Filter = "Copias SQL (*.sql, *.sql.gz, *.zip)|*.sql;*.sql.gz;*.gz;*.zip|Todos los ficheros|*.*",
            InitialDirectory = ImportFile != null ? Path.GetDirectoryName(ImportFile) : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads"),
        };
        if (dlg.ShowDialog(W) != true)
            return;
        ImportFile = dlg.FileName;
        // Si hay una BBDD que se llama como el fichero (mi_web.sql → mi_web), se propone
        var stem = System.Text.RegularExpressions.Regex.Replace(Path.GetFileName(ImportFile), @"(?i)(\.sql)?(\.gz|\.zip)?$", "");
        var act = W.State?.ActiveInfo;
        if (ImportDb == null && act != null && act.Dbs.Any(d => d.Name == stem))
        {
            ImportDb = stem;
            ImportProject = Guess(stem, act.Folder) ?? ImportProject;
            _importFor = stem;
        }
        else if (act != null && !act.Dbs.Any(d => d.Name == stem))
        {
            var others = (W.State?.Versions ?? new()).Where(v => v.Dbs.Any(d => d.Name == stem)).Select(v => v.Folder).ToList();
            if (others.Count > 0)
                W.Toast($"«{stem}» está en {string.Join(", ", others)}, no en la versión activa");
        }
        Build();
    }

    void OnImport()
    {
        var db = ImportDb!;
        var path = ImportFile!;
        var st = W.State!;
        var act = st.ActiveInfo!;
        string size;
        try { size = Texto.Size(new FileInfo(path).Length); }
        catch (IOException) { Dialogo.Message(W, "No se encuentra el fichero", path); return; }
        var others = st.Versions.Where(v => v.Folder != act.Folder && v.Dbs.Any(d => d.Name == db)).ToList();
        var title = $"¿Cargar {Path.GetFileName(path)} ({size}) en {db}?";
        var text = $"Se carga en el MariaDB de {act.Folder}. ";
        var ok = "Vaciar y cargar";
        if (others.Count > 0)
        {
            var where = string.Join(", ", others.Select(v => $"{v.Folder} (PHP {v.M.Php})"));
            title = $"«{db}» ya existe en {where}";
            text = $"¿Quieres introducirla también en {act.Folder} (PHP {act.M.Php}), la versión activa? Cada versión tiene su propio MariaDB: la de {where} no se toca.\n\nFichero: {Path.GetFileName(path)} ({size}).\n\n";
            ok = $"Cargar también en {act.Folder}";
        }
        text += $"Antes se BORRAN todas las tablas de «{db}», para que no quede nada de lo anterior. Si tiene alguna, primero se guarda una copia en {W.Motor.L.CopiesDir}.";
        var project = ImportProject;
        if (project != null)
            text += $"\n\nDespués, «{db}» pasa a ser la BBDD de {project}: {ProjectHint().TrimEnd('.').ToLowerInvariant()}.";
        if (!Dialogo.Confirm(W, title, text, ok, destructive: true))
            return;
        CheckDbAccess(() =>
        {
            var args = new List<string> { "importar-bd", path, db };
            if (project != null) { args.Add("--proyecto"); args.Add(project); }
            W.RunTask($"Cargando {Path.GetFileName(path)} en {db}", args.ToArray(), new OpcionesTarea
            {
                Progress = true, DoneText = $"BBDD «{db}» cargada" + (project != null ? $" en {project}" : ""), Env = DbEnv(),
                CancelText = ("¿Cancelar la carga?", $"La BBDD «{db}» se queda a medias: tendrá lo que se haya cargado hasta ahora.", "Cancelar la carga"),
                OnDone = (ok2, _) => { if (ok2) ImportFile = null; },
            });
        });
    }

    /// <summary>Desde Proyectos (Importar SQL): el formulario con ese proyecto y su BBDD.</summary>
    public void PrepareImport(Proyecto x)
    {
        var pairs = W.ProjectPairs(x);
        var act = pairs.FirstOrDefault(p => p.Ver.Folder == W.State?.Active).Db;
        ImportProject = x.Name;
        ImportDb = act ?? ImportDb;
        _importFor = ImportDb;
        Build();
        W.ShowTab("bbdd");
        W.Toast($"Elige el fichero en «Subir o actualizar una BBDD»: proyecto {x.Name}");
        W.Dispatcher.BeginInvoke(() => Scroll.ScrollToEnd(), System.Windows.Threading.DispatcherPriority.Background);
    }
}
