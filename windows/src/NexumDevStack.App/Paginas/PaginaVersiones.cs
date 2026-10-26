using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using NexumDevStack.Core.Catalogo;
using NexumDevStack.Core.Pila;
using NexumDevStack.Core.Util;

namespace NexumDevStack.App.Paginas;

/// <summary>
/// Versiones de PHP (como nv_build_versions de Linux): una tabla con cada versión, si está en marcha, su soporte
/// en php.net, su último parche y sus BBDD; Activar al pasar el ratón y el menú ⋯; Componentes e Instalar versión…
/// </summary>
public sealed class PaginaVersiones : Pagina
{
    static readonly double[] Widths = { 250, 92, 230, 230, 60, 0 };
    readonly List<string> _extraPatches = new();

    public PaginaVersiones(VentanaPrincipal w) : base(w, 900) { }

    public override void Build()
    {
        Content.Children.Clear();
        var components = Ui.Button(Ui.Logo("apache", 15), "Componentes", "Apache, MariaDB y phpMyAdmin de cada versión", () => Components(null));
        var install = Ui.Button(Ico.Mas, "Instalar versión…", null, InstallDialog, "BotonAzul");
        install.IsEnabled = Prepared && !W.Busy;
        Content.Children.Add(Ui.PageTitle(Ui.Logo("php", 34), "Versiones de PHP",
            "Cada versión con su Apache, MariaDB y sus propias BBDD. Soporte y parches, según php.net", components, install));
        if (W.State == null)
        {
            Loading();
            return;
        }
        if (!Prepared)
        {
            NotPrepared();
            return;
        }
        var st = W.State;
        var list = new StackPanel();
        list.Children.Add(Ui.TableRow(Widths, new UIElement[]
        {
            Ui.Text("VERSIÓN", "cab"), Ui.Text("PHP", "cab"), Ui.Text("SOPORTE", "cab"), Ui.Text("ÚLTIMO PARCHE", "cab"), Ui.Text("BBDD", "cab"), new TextBlock(),
        }, header: true));
        foreach (var v in st.Versions)
            list.Children.Add(VersionRow(v, st));
        if (st.Versions.Count == 0)
        {
            var empty = Ui.Text("Ninguna versión instalada: instala la primera con «Instalar versión…»", "tenue");
            empty.Margin = new Thickness(14, 12, 14, 14);
            list.Children.Add(Line(empty));
        }
        Content.Children.Add(Ui.Card(list));
        if (W.BranchesError != null)
        {
            var e = Ui.Wrap(W.BranchesError, "chico", "rojo");
            e.Margin = new Thickness(4, 10, 0, 0);
            Content.Children.Add(e);
        }
    }

    static Border Line(UIElement e)
    {
        var b = new Border { Child = e, BorderThickness = new Thickness(0, 1, 0, 0) };
        b.SetResourceReference(Border.BorderBrushProperty, "BordeSuave");
        return b;
    }

    RamaInfo? BranchOf(string php) => W.Branches?.FirstOrDefault(b => b.Branch == Versiones.Branch(php));

    UIElement VersionRow(VersionInfo v, Estado st)
    {
        var active = v.Folder == st.Active;
        var name = new StackPanel { Orientation = Orientation.Horizontal };
        name.Children.Add(Ui.Dot(active && st.Running, 9, pulse: true));
        var nt = new StackPanel { Margin = new Thickness(9, 0, 0, 0) };
        var tl = Ui.HStack(6, Ui.Text(v.Folder, "mono"), Ui.Tag(v.M.PhpBuild.Length > 0 ? v.M.PhpBuild : "oficial"));
        nt.Children.Add(tl);
        var date = W.PhpDates.TryGetValue(v.Folder, out var d) && d.Php == v.M.Php ? Texto.Day(d.Date) : W.Motor.L.VersionDir(v.Folder);
        nt.Children.Add(Ui.Text(date, "chico", "tenue"));
        name.Children.Add(nt);
        name.ToolTip = W.Motor.L.VersionDir(v.Folder);

        var b = BranchOf(v.M.Php);
        var sup = new StackPanel();
        var patch = new StackPanel();
        string? newer = null;
        if (b != null)
        {
            var (pill, tip) = b.PhpNetState switch
            {
                "stable" => (Ui.Text("Estable", "chico", "negrita", "verde"), "Recibe correcciones de errores y de seguridad. Es la mejor opción para proyectos nuevos."),
                "security" => (Ui.Text("Solo seguridad", "chico", "negrita", "naranja"), "Ya no recibe correcciones de errores, solo parches de seguridad. Sirve para proyectos que aún no funcionan con las estables."),
                _ => (Ui.Text("Sin soporte", "chico", "negrita", "rojo"), "php.net ya no publica parches, ni de seguridad. Solo para proyectos antiguos."),
            };
            pill.ToolTip = tip;
            sup.Children.Add(pill);
            var when = b.PhpNetState == "security" ? b.SecurityEnd : b.PhpNetState == "stable" ? b.ActiveEnd : "";
            if (when.Length > 0)
                sup.Children.Add(Ui.Text((b.PhpNetState == "security" ? "seguridad hasta " : "hasta ") + Texto.Month(when), "chico", "tenue"));
            if (b.Latest == v.M.Php)
                patch.Children.Add(Ui.Text("Actualizado", "chico", "verde"));
            else if (Versiones.Compare(b.Latest, v.M.Php) > 0)
            {
                newer = b.Latest;
                patch.Children.Add(Ui.Text($"PHP {b.Latest} disponible", "chico", "azul"));
                if (b.Date.Length > 1)
                    patch.Children.Add(Ui.Text(Texto.Day(b.Date), "chico", "tenue"));
            }
            else
                patch.Children.Add(Ui.Text("—", "tenue"));
        }
        else
        {
            sup.Children.Add(Ui.Text(W.Branches == null && W.BranchesError == null ? "consultando php.net…" : "—", "chico", "tenue"));
            patch.Children.Add(Ui.Text("—", "tenue"));
        }
        if (v.P2S == Php2Shell.Estado.Vulnerable)
        {
            var vul = Ui.Text("Vulnerable (PHP2Shell)", "chico", "negrita", "rojo");
            vul.ToolTip = v.P2SWhy + ".\nCVE-2026-109618 y CVE-2026-109619: una petición preparada puede ejecutar código con tu usuario. " +
                          (newer != null ? "Pasa a la versión con el arreglo en el menú ⋯ («Actualizar a PHP…»)." : "Usa una versión de PHP 8.2.35, 8.3.36, 8.4.27, 8.5.12 o posterior.");
            patch.Children.Insert(0, vul);
            foreach (var t in patch.Children.OfType<TextBlock>().Where(t => t.Text == "Actualizado").ToList())
                patch.Children.Remove(t);
        }
        var right = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        Button act;
        if (active)
        {
            act = Ui.TextButton("Activa", () => { }, "BotonActiva");
            act.IsHitTestVisible = false;
        }
        else
        {
            act = Ui.TextButton("Activar", () => Activate(v), "BotonAzul");
            act.IsEnabled = !W.Busy;
            act.Opacity = 0;
        }
        act.MinWidth = 96;
        right.Children.Add(act);
        right.Children.Add(VersionMenu(v, newer));
        var row = Ui.TableRow(Widths, new UIElement[]
        {
            name, Ui.Text(v.M.Php, "mono"), sup, patch, Ui.Text(v.Dbs.Count.ToString(), "mono", "tenue"), right,
        });
        var holder = new Border { Child = row, Background = System.Windows.Media.Brushes.Transparent, BorderThickness = new Thickness(0, 1, 0, 0) };
        holder.SetResourceReference(Border.BorderBrushProperty, "BordeSuave");
        if (!active)
        {
            // (como «Cargar» en Proyectos: solo en la versión con el ratón encima)
            holder.MouseEnter += (_, _) => act.Opacity = 1;
            holder.MouseLeave += (_, _) => act.Opacity = 0;
        }
        return holder;
    }

    Button VersionMenu(VersionInfo v, string? newer)
    {
        var items = new List<(string, string?, Action?)> { ("Componentes…", Ico.Info, () => Components(v)) };
        if (newer != null)
            items.Add(($"Actualizar a PHP {newer}", Ico.Descargar, () => UpgradeTo(v, newer)));
        else if (BranchOf(v.M.Php) == null)
            items.Add(("Buscar parches nuevos", Ico.Recargar, () => CheckUpdate(v)));
        if (Catalogo.PmaOutdated(v.M.Php, v.M.Pma))
            items.Add(("phpMyAdmin antiguo: reinstala la versión", Ico.Aviso, null));
        items.Add(("-", null, null));
        items.Add(("Desinstalar…", Ico.Papelera, () =>
        {
            if (v.Blocker.Length > 0)
                Dialogo.Message(W, "No se puede desinstalar", v.Blocker);
            else
                Remove(v);
        }));
        var m = Ui.MenuButton(Ico.Puntos, null, null, items, "BotonPlano");
        m.Margin = new Thickness(4, 0, 0, 0);
        return m;
    }

    void Activate(VersionInfo v)
    {
        if (v.P2S == Php2Shell.Estado.Vulnerable && !Dialogo.Confirm(W, $"{v.Folder} es vulnerable a PHP2Shell",
                $"{v.P2SWhy}. Una petición preparada puede ejecutar código con tu usuario. Mejor usa una versión con el arreglo.",
                $"Activar {v.Folder} igualmente", destructive: true))
            return;
        W.RunTask($"Activando {v.Folder}", new[] { "usar", v.Folder }, new OpcionesTarea { DoneText = $"{v.Folder} activada", AutoClose = true });
    }

    void CheckUpdate(VersionInfo v)
    {
        W.Toast("Comprobando si hay una versión más nueva…");
        Task.Run(() =>
        {
            (string State, string Latest) r;
            try { r = W.Motor.UpToDate(v.Folder, CancellationToken.None); }
            catch (Exception) { r = ("error", ""); }
            W.Dispatcher.BeginInvoke(() =>
            {
                if (r.State == "si")
                    Dialogo.Message(W, $"{v.Folder} ya está actualizada", $"Tiene el último parche de su rama ({r.Latest}).");
                else if (r.State == "no")
                    UpgradeTo(v, r.Latest);
                else
                    Dialogo.Message(W, "No se ha podido comprobar la versión", "No se ha podido consultar windows.php.net. Comprueba la conexión a internet.");
            });
        });
    }

    /// <summary>Actualizar a PHP X.Y.Z: la nueva al lado, con las BBDD copiadas y sus vínculos.</summary>
    void UpgradeTo(VersionInfo v, string target)
    {
        var st = W.State!;
        var dbs = v.Dbs.Count;
        var have = st.Versions.FirstOrDefault(x => x.M.Php == target);
        var activeNote = v.Folder == st.Active ? " y, como es la activa, se activa la nueva" : "";
        var text = have != null
            ? $"PHP {target} ya está en {have.Folder}: se le copian {(dbs > 0 ? Texto.Plural(dbs, "BBDD", "BBDD") : "las BBDD (ahora no tiene ninguna)")} de {v.Folder} con sus vínculos a las carpetas de los proyectos{activeNote}. {v.Folder} no se toca: desinstálala cuando compruebes que todo va bien."
            : $"Se instala PHP {target} en php-{target}, al lado de {v.Folder}, que no se toca. Después se le copian {(dbs > 0 ? Texto.Plural(dbs, "BBDD", "BBDD") : "sus BBDD (ahora no tiene ninguna)")} con sus vínculos a las carpetas de los proyectos{activeNote}. Cuando compruebes que todo va bien con php-{target}, desinstala {v.Folder} (menú ⋯, Desinstalar). Pide permiso de administrador.";
        if (!Dialogo.Confirm(W, $"¿Actualizar {v.Folder} a PHP {target}?", text, "Actualizar"))
            return;
        W.RunTask($"{v.Folder} → PHP {target}", new[] { "actualizar-a", v.Folder, target }, new OpcionesTarea
        {
            Progress = true, DoneText = $"PHP {target} instalada con las BBDD de {v.Folder}",
        }, reloadBranches: true);
    }

    void Remove(VersionInfo v)
    {
        var dbs = v.Dbs.Count;
        var text = $"Se borrará la carpeta {W.Motor.L.VersionDir(v.Folder)} (PHP {v.M.Php})" +
                   (dbs > 0 ? $" y sus {Texto.Plural(dbs, "BBDD propia", "BBDD propias")} ({W.Motor.L.DataDir(v.Folder)})" : "") +
                   ". Los proyectos de htdocs y los vhosts no se tocan. Pide permiso de administrador.";
        var d = new Dialogo(W, $"¿Desinstalar {v.Folder}?", text);
        CheckBox? copy = null;
        TextBox? confirm = null;
        StackPanel? warn = null;
        if (dbs > 0)
        {
            copy = new CheckBox { Content = $"Guardar antes una copia de sus BBDD en {W.Motor.L.CopiesDir}", IsChecked = true };
            d.Add(copy);
            warn = new StackPanel { Visibility = Visibility.Collapsed };
            warn.Children.Add(Ui.Wrap($"Sin copia, las BBDD no se podrán recuperar. Escribe {v.Folder} para confirmar:", "rojo"));
            confirm = new TextBox { Margin = new Thickness(0, 6, 0, 0) };
            warn.Children.Add(confirm);
            d.Add(warn);
        }
        d.Buttons("Desinstalar", destructive: true);
        void Update()
        {
            var withCopy = copy?.IsChecked != false;
            if (warn != null) warn.Visibility = withCopy ? Visibility.Collapsed : Visibility.Visible;
            d.OkEnabled = withCopy || confirm?.Text.Trim() == v.Folder;
        }
        if (copy != null) copy.Click += (_, _) => Update();
        if (confirm != null) confirm.TextChanged += (_, _) => Update();
        Update();
        if (!d.Run())
            return;
        var withBackup = copy?.IsChecked == true;
        var args = new List<string> { "desinstalar", v.Folder };
        if (withBackup) args.Add("--copia");
        W.RunTask($"Desinstalando {v.Folder}", args.ToArray(), new OpcionesTarea
        {
            DoneText = $"{v.Folder} desinstalada" + (withBackup ? $" (copia en {W.Motor.L.CopiesDir})" : ""),
            Env = W.PageOf<PaginaBbdd>("bbdd").DbEnv(),
        }, reloadBranches: true);
    }

    /// <summary>Componentes de cada versión en una tabla, con el logotipo de cada uno.</summary>
    void Components(VersionInfo? only)
    {
        var d = new Dialogo(W, "Componentes", "Todo es de su web oficial y comprobado al instalarlo (pasa el ratón por la versión para ver cómo).", 860);
        var widths = new double[] { 150, 96, 120, 110, 120, 0 };
        UIElement H(string text, string? logo) => logo != null
            ? Ui.HStack(6, Ui.Logo(logo, 14), Ui.Text(text.ToUpperInvariant(), "cab"))
            : Ui.Text(text.ToUpperInvariant(), "cab");
        var list = new StackPanel();
        list.Children.Add(Ui.TableRow(widths, new[] { H("Versión", null), H("PHP", "php"), H("Apache", "apache"), H("MariaDB", "mariadb"),
            H("phpMyAdmin", "phpmyadmin"), H("Compilación", null) }, true));
        foreach (var v in (W.State?.Versions ?? new()).Where(v => only == null || v.Folder == only.Folder))
        {
            var name = Ui.Text(v.Folder, "mono");
            name.ToolTip = string.Join("\n", v.M.Verified.Prepend($"Instalada el {v.M.InstalledAt} con Nexum Dev Stack {v.M.InstalledBy}"));
            var pma = Ui.Text(v.M.Pma, "mono", "chico");
            if (Catalogo.PmaOutdated(v.M.Php, v.M.Pma))
            {
                pma.SetResourceReference(TextBlock.ForegroundProperty, "Rojo");
                pma.ToolTip = "phpMyAdmin antiguo";
            }
            list.Children.Add(Line(Ui.TableRow(widths, new UIElement[]
            {
                name, Ui.Text(v.M.Php, "mono"), Ui.Text(v.M.Apache, "mono", "chico"), Ui.Text(v.M.MariaDb, "mono", "chico"), pma,
                Ui.Text($"PHP {v.M.PhpBuild} TS · Apache {v.M.ApacheBuild}", "chico", "tenue"),
            })));
        }
        d.Add(Ui.Card(list));
        d.Buttons("Cerrar", null);
        d.Run();
    }

    // ------------------------------------------------------------------ instalar
    void InstallDialog()
    {
        var d = new Dialogo(W, "Instalar versión",
            "Cada versión lleva su propio Apache (Apache Lounge), MariaDB y phpMyAdmin, con los binarios oficiales de Windows, y sus propias BBDD. " +
            "Según php.net: Estable recibe correcciones de errores y de seguridad (la mejor opción para proyectos nuevos), Solo seguridad recibe " +
            "únicamente parches de seguridad hasta la fecha indicada y Sin soporte ya no recibe parches.", 720);
        var checks = new List<(CheckBox Check, string Version)>();
        var list = new StackPanel();
        Button? ok = null;
        void Update()
        {
            var n = checks.Count(c => c.Check.IsChecked == true);
            d.OkEnabled = n > 0;
            if (ok != null) ok.Content = n == 0 ? "Marca una o más versiones" : $"Instalar {Texto.Plural(n, "versión", "versiones")}";
        }
        if (W.BranchesError != null || W.Branches == null)
        {
            var (row, suffix, _, sub) = Ui.Row(W.Branches == null && W.BranchesError == null ? "Consultando las versiones de PHP en php.net…" : "No se han podido consultar las versiones",
                W.BranchesError ?? "", Ui.Icon(Ico.Aviso, 15, "Naranja"));
            sub.TextWrapping = TextWrapping.Wrap;
            suffix.Children.Add(Ui.TextButton("Reintentar", () => { d.Close(false); W.Reload(branches: true); }));
            Ui.AddRow(list, row);
        }
        else
        {
            foreach (var b in W.Branches)
            {
                FrameworkElement prefix;
                string sub;
                CheckBox? chk = null;
                if (b.State == "nueva")
                {
                    chk = new CheckBox();
                    chk.Click += (_, _) => Update();
                    checks.Add((chk, b.Latest));
                    prefix = chk;
                    sub = $"Apache 2.4  ·  MariaDB {b.MariaDb}  ·  → {W.Motor.L.VersionDir(b.Folder)}";
                }
                else
                {
                    prefix = Ui.Icon(b.State == "instalada" ? Ico.Hecho : Ico.Info, 14, b.State == "instalada" ? "Verde" : "TextoTenue");
                    sub = b.State == "instalada" ? $"Ya instalada en {W.Motor.L.VersionDir(b.Folder)}" : $"Ya existe {W.Motor.L.VersionDir(b.Folder)}";
                }
                if (b.PhpNetState == "security" && b.SecurityEnd.Length > 0)
                    sub += $"  ·  seguridad hasta {Texto.Month(b.SecurityEnd)}";
                var (p2s, _) = Php2Shell.State(b.Latest);
                if (p2s == Php2Shell.Estado.Vulnerable)
                    sub += "  ·  vulnerable a PHP2Shell (sin arreglo en Windows)";
                var (row, suffix, title, subT) = Ui.Row($"PHP {b.Latest}", sub, prefix);
                subT.TextWrapping = TextWrapping.Wrap;
                var parent = (StackPanel)title.Parent;
                var tags = Ui.HStack(10, Ui.Text($"PHP {b.Latest}"));
                if (b.Date.Length > 1) tags.Children.Add(Ui.Text(Texto.Day(b.Date), "chico", "tenue"));
                var sec = b.Security ? Ui.Text("Parche de seguridad", "chico", "negrita", "azul") : Ui.Text("Corrección de errores", "chico", "tenue");
                tags.Children.Add(sec);
                parent.Children.Remove(title);
                parent.Children.Insert(0, tags);
                suffix.Children.Add(b.PhpNetState switch
                {
                    "stable" => Ui.Text("Estable", "chico", "negrita", "verde"),
                    "security" => Ui.Text("Solo seguridad", "chico", "negrita", "naranja"),
                    _ => Ui.Text("Sin soporte", "chico", "negrita", "rojo"),
                });
                if (chk == null)
                    row.Opacity = 0.6;
                else
                {
                    row.Cursor = Cursors.Hand;
                    row.Background = System.Windows.Media.Brushes.Transparent;
                    row.MouseLeftButtonUp += (_, e) =>
                    {
                        if (e.OriginalSource is not CheckBox) { chk.IsChecked = chk.IsChecked != true; Update(); }
                    };
                }
                Ui.AddRow(list, row);
            }
            foreach (var p in _extraPatches)
            {
                var chk = new CheckBox { IsChecked = true };
                chk.Click += (_, _) => Update();
                checks.Add((chk, p));
                var (row, suffix, _, _) = Ui.Row($"PHP {p}", $"Parche concreto  ·  → {W.Motor.L.VersionDir("php-" + p)}", chk);
                Ui.AddRow(list, row);
            }
            var (other, osuffix, _, _) = Ui.Row("Otro parche concreto…", "Una versión anterior de cualquier rama, en su propia carpeta", Ui.Icon(Ico.Puntos, 14));
            osuffix.Children.Add(Ui.Icon(Ico.Derecha, 12, "TextoTenue"));
            other.Cursor = Cursors.Hand;
            other.Background = System.Windows.Media.Brushes.Transparent;
            other.MouseLeftButtonUp += (_, _) =>
            {
                var picked = PickPatch(d);
                if (picked != null && !_extraPatches.Contains(picked))
                {
                    _extraPatches.Add(picked);
                    d.Close(false);
                    W.Dispatcher.BeginInvoke(InstallDialog);
                }
            };
            Ui.AddRow(list, other);
        }
        var sv = new ScrollViewer { Content = Ui.Card(list), MaxHeight = 460, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        d.Add(sv);
        d.Buttons("Marca una o más versiones");
        ok = FindOk(d);
        Update();
        if (!d.Run())
            return;
        var selected = checks.Where(c => c.Check.IsChecked == true).Select(c => c.Version).ToList();
        if (selected.Count == 0)
            return;
        var names = selected.Select(v => "PHP " + v).ToList();
        var vulnerable = selected.Where(v => Php2Shell.State(v).State == Php2Shell.Estado.Vulnerable).ToList();
        var text = string.Join(", ", names) + ". Se descargan y se comprueban los binarios oficiales de Windows (varios minutos). Las versiones instaladas no se tocan. Pide permiso de administrador.";
        if (vulnerable.Count > 0)
            text += $"\n\n{string.Join(", ", vulnerable.Select(v => "PHP " + v))}: vulnerable a PHP2Shell y sin arreglo en Windows. Úsala solo para proyectos que no funcionen con otra.";
        if (!Dialogo.Confirm(W, $"¿Instalar {Texto.Plural(names.Count, "versión", "versiones")}?", text,
                names.Count == 1 ? $"Instalar {names[0]}" : $"Instalar {Texto.Plural(names.Count, "versión", "versiones")}"))
            return;
        W.RunTask("Instalando", new[] { "instalar" }.Concat(selected).ToArray(), new OpcionesTarea
        {
            Progress = true, DoneText = "Instalación terminada",
            OnDone = (ok2, task) =>
            {
                var done = task.Results.Where(r => r.Key == "I").Select(r => r.Value).ToList();
                _extraPatches.RemoveAll(p => done.Contains("php-" + p));
                if (ok2 && done.Count == 1)
                {
                    var folder = done[0];
                    task.Offer($"Activar {folder}", () =>
                    {
                        var v = W.State?.Versions.FirstOrDefault(x => x.Folder == folder);
                        if (v != null) Activate(v);
                        else W.RunTask($"Activando {folder}", new[] { "usar", folder }, new OpcionesTarea { DoneText = $"{folder} activada", AutoClose = true });
                    });
                }
            },
        }, reloadBranches: true);
    }

    static Button? FindOk(Dialogo d)
    {
        var frame = (Border)d.Content;
        var outer = (StackPanel)frame.Child;
        var buttons = (StackPanel)outer.Children[1];
        return buttons.Children.OfType<Button>().LastOrDefault();
    }

    /// <summary>Otro parche de PHP: la rama y la lista de parches con su fecha (solo los que tienen su suma publicada).</summary>
    string? PickPatch(Window owner)
    {
        var branches = (W.Branches ?? new()).Select(b => b.Branch).ToList();
        if (branches.Count == 0)
            return null;
        var d = new Dialogo(owner, "Otro parche de PHP",
            "Las versiones publicadas en php.net son todas definitivas, pero los parches anteriores al último no tienen sus correcciones de seguridad: " +
            "úsalos solo si un proyecto necesita esa versión. En Windows solo se pueden instalar los que tienen su suma sha256 publicada.", 620);
        var combo = Ui.Combo(branches.Select(b => (b, $"PHP {b}")), branches[0], 200);
        d.Add(Ui.HStack(10, Ui.Text("Rama:"), combo));
        var status = Ui.Text("", "chico", "tenue");
        d.Add(status);
        var list = new StackPanel();
        d.Add(new ScrollViewer { Content = Ui.Card(list), Height = 340, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        string? chosen = null;
        d.Buttons("Añadir");
        d.OkEnabled = false;
        void Load()
        {
            var branch = combo.SelectedId()!;
            list.Children.Clear();
            status.Text = $"Consultando los parches de PHP {branch}…";
            d.OkEnabled = false;
            chosen = null;
            Task.Run(() =>
            {
                List<ParcheInfo>? rows = null;
                try { rows = W.Motor.Patches(branch, CancellationToken.None); } catch (Exception) { }
                d.Dispatcher.BeginInvoke(() =>
                {
                    if (combo.SelectedId() != branch) return;
                    if (rows == null || rows.Count == 0)
                    {
                        status.Text = "No se ha podido consultar php.net.";
                        return;
                    }
                    status.Text = $"PHP {branch}: {rows.Count(r => r.Installable)} de {rows.Count} parches con binario de Windows comprobable";
                    var group = "parche-" + branch;
                    foreach (var r in rows)
                    {
                        var can = r.Installable && r.State == "nueva" && !_extraPatches.Contains(r.Version);
                        var sub = !r.Installable ? "sin suma sha256 publicada para Windows: no se puede comprobar"
                            : r.State == "instalada" ? "Ya instalada" : r.State == "existe" ? $"Ya existe {W.Motor.L.VersionDir(r.Folder)}"
                            : _extraPatches.Contains(r.Version) ? "Ya en la lista" : $"→ {W.Motor.L.VersionDir(r.Folder)}";
                        var rb = new RadioButton { GroupName = group, IsEnabled = can };
                        rb.Checked += (_, _) => { chosen = r.Version; d.OkEnabled = true; };
                        var (row, suffix, _, _) = Ui.Row($"PHP {r.Version}   {(r.Date.Length > 1 ? Texto.Day(r.Date) : "")}", sub, rb);
                        suffix.Children.Add(r.Security ? Ui.Text("Parche de seguridad", "chico", "azul") : Ui.Text("Corrección de errores", "chico", "tenue"));
                        if (!can) row.Opacity = 0.55;
                        Ui.AddRow(list, row);
                    }
                });
            });
        }
        combo.SelectionChanged += (_, _) => Load();
        d.Loaded += (_, _) => Load();
        return d.Run() ? chosen : null;
    }
}
