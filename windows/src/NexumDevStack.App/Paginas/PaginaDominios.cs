using System.Windows;
using System.Windows.Controls;
using NexumDevStack.Core.Configuracion;
using NexumDevStack.Core.Pila;
using NexumDevStack.Core.Proyectos;
using NexumDevStack.Core.Util;

namespace NexumDevStack.App.Paginas;

/// <summary>
/// Dominios y hosts: los dominios de los vhosts y si están falseados en hosts (llevan a este equipo), el
/// formulario de proyecto nuevo con dominio falseado y el arreglo de web.local si no lleva a 127.0.0.1.
/// </summary>
public sealed class PaginaDominios : Pagina
{
    // Formulario de proyecto nuevo (se conserva al redibujar)
    string _domain = "", _folder = "", _db = "";

    public PaginaDominios(VentanaPrincipal w) : base(w) { }

    public override void Build()
    {
        Content.Children.Clear();
        Content.Children.Add(Ui.PageTitle(Ui.Icon(Ico.Red, 24), "Dominios y hosts", "Los dominios de los vhosts y los que se llevan a este equipo en hosts"));
        if (!Prepared)
        {
            NotPrepared();
            return;
        }
        var h = W.HostsState;
        if (h == null)
        {
            Loading();
            return;
        }
        if (h.LinkFix != null)
        {
            var (box, list) = Ui.Group($"{Disposicion.ProjectVhost} no lleva a este equipo",
                $"Apache solo escucha en 127.0.0.1 y en hosts {(h.LinkFix.Length > 0 ? "apunta a " + h.LinkFix : "no está")}. El navegador no puede abrirlo. " +
                $"Arreglarlo hace que {Disposicion.ProjectVhost} lleve a 127.0.0.1 (pide permiso de administrador).");
            var (row, suffix, _, _) = Ui.Row($"{Disposicion.ProjectVhost} → {(h.LinkFix.Length > 0 ? h.LinkFix : "sin línea en hosts")}",
                "Tiene que ir a 127.0.0.1, donde escucha Apache");
            suffix.Children.Add(Ui.TextButton("Arreglarlo", () => W.RunTask("Arreglando hosts", new[] { "hosts-enlace" },
                new OpcionesTarea { DoneText = $"{Disposicion.ProjectVhost} ya lleva a este equipo", AutoClose = true }), "BotonAzul"));
            Ui.AddRow(list, row);
            Content.Children.Add(box);
        }
        // Un .local siempre está en hosts (sin su línea se preguntaría a la red): va con los demás
        var fake = h.Domains.Where(d => d.Faked && !d.Name.EndsWith(".local", StringComparison.Ordinal)).ToList();
        var rest = h.Domains.Where(d => !fake.Contains(d)).ToList();
        var (fbox, flist) = Ui.Group("Host falseado",
            "Al cargar una tienda PrestaShop se crea lo que le falte (su vhost y su certificado) y su dominio se falsea en hosts: el navegador " +
            "la abre en este equipo. Al cargar otro proyecto deja de estar falseado y vuelve a llevar a la web real.");
        if (fake.Count == 0)
            Ui.AddRow(flist, Ui.Row("Ningún dominio falseado", "Los dominios de los vhosts llevan a sus webs reales").Row);
        foreach (var d in fake)
            Ui.AddRow(flist, HostRow(d));
        Content.Children.Add(fbox);
        Content.Children.Add(NewDomain());
        var (rbox, rlist) = Ui.Group("Dominios de los vhosts",
            "Encendido, el dominio lleva a este equipo (127.0.0.1); apagado, a la web real. Cambiar hosts pide permiso de administrador.");
        if (rest.Count == 0)
            Ui.AddRow(rlist, Ui.Row("No hay más dominios", $"Los vhosts están en {W.Motor.L.VhostsFile}").Row);
        foreach (var d in rest)
            Ui.AddRow(rlist, HostRow(d));
        Content.Children.Add(rbox);
    }

    Border HostRow(DominioVhost h)
    {
        var info = new List<string> { h.Folder.Length > 0 ? h.Folder : "sin carpeta en htdocs" };
        if (!h.Https) info.Add("sin https");
        else if (!h.HasCert) info.Add("falta el certificado");
        FrameworkElement icon = h.PrestaShop ? Ui.Logo("prestashop", 16) : h.Folder.Contains("wordpress", StringComparison.OrdinalIgnoreCase)
            ? Ui.Logo("wordpress", 16) : Ui.Logo("globo", 16);
        var (row, suffix, title, _) = Ui.Row(h.Name, string.Join("  ·  ", info), icon);
        if (h.PrestaShop || h.Custom)
        {
            var parent = (StackPanel)title.Parent;
            var tagged = Ui.HStack(10, Ui.Text(h.Name), Ui.Text(h.PrestaShop ? "PrestaShop" : "Proyecto nuevo", "chico", "tenue"));
            parent.Children.Remove(title);
            parent.Children.Insert(0, tagged);
        }
        if (h.Faked)
        {
            var open = Ui.TextButton("Abrir", () => W.OpenUri($"{(h.Https ? "https" : "http")}://{h.Name}"));
            open.Margin = new Thickness(0, 0, 10, 0);
            open.ToolTip = $"https://{h.Name}";
            suffix.Children.Add(open);
        }
        var local = h.Name.EndsWith(".local", StringComparison.Ordinal);
        var sw = Ui.Switch(h.Faked, on =>
        {
            if (local && !on && !Dialogo.Confirm(W, $"¿Apagar {h.Name}?",
                    $"Su línea de hosts queda comentada. Mientras esté apagado, al abrir {h.Name} cualquiera de tu misma wifi podría contestar con una web suya. " +
                    "Se puede volver a encender cuando quieras.", $"Apagar {h.Name}"))
            {
                Build();
                return;
            }
            var title2 = local ? $"{(on ? "Encendiendo" : "Apagando")} {h.Name}" : on ? $"Falseando {h.Name}" : $"Dejando de falsear {h.Name}";
            var done = local ? $"{h.Name} {(on ? "lleva a este equipo" : "apagado")}" : on ? $"{h.Name} lleva a este equipo" : $"{h.Name} lleva a la web real";
            W.RunTask(title2, new[] { "hosts-falsear", h.Name, on ? "si" : "no" }, new OpcionesTarea { DoneText = done, AutoClose = true });
        });
        sw.IsEnabled = !W.Busy;
        if (local)
            sw.ToolTip = "Un .local no existe fuera de este equipo: encendido, se mantiene en hosts; apagado, Windows lo pregunta a la red";
        suffix.Children.Add(sw);
        return row;
    }

    /// <summary>Nuevo proyecto con el dominio de producción falseado (como build_new_domain de Linux).</summary>
    StackPanel NewDomain()
    {
        var st = W.State;
        var active = st?.Active;
        var (box, list) = Ui.Group("Nuevo proyecto con dominio falseado",
            "Para construir en local un proyecto nuevo con su dominio y su BBDD de producción, sin tocar nada en producción. Elige su carpeta de htdocs " +
            "(por ejemplo, la de un git clone) o crea una, y su BBDD. Se crea su vhost http y https con certificado, lo que falte de la carpeta y la " +
            "BBDD, y se falsea el dominio. Al terminar se exporta a producción tal cual.");
        Button create = null!;
        void Update() => create.IsEnabled = Validacion.IsDomain(_domain) && _folder.Length > 0 && !W.Busy;

        var (r1, s1, _, _) = Ui.Row("Dominio", "El de producción", Ui.Logo("globo", 16));
        var entry = new TextBox { Text = _domain, Width = 260, ToolTip = "mitienda.com" };
        entry.TextChanged += (_, _) => { _domain = entry.Text.Trim(); Update(); };
        s1.Children.Add(entry);
        Ui.AddRow(list, r1);

        var folders = Escaner.Folders(W.Motor.L.Htdocs);
        var withDomain = (W.HostsState?.Domains ?? new()).Where(d => d.Folder.Length > 0).GroupBy(d => d.Folder).ToDictionary(g => g.Key, g => g.First().Name);
        var (r2, s2, _, sub2) = Ui.Row("Carpeta", withDomain.TryGetValue(_folder, out var dom) ? $"Ya tiene el dominio {dom}" : "En htdocs (git clone) o nueva",
            Ui.Icon(Ico.Carpeta, 15));
        var items = folders.Select(f => (f, f)).ToList();
        if (_folder.Length > 0 && !folders.Contains(_folder))
            items.Add((_folder, _folder + " (nueva)"));
        items.Insert(0, ("@ninguna", "Elige una carpeta"));
        var fcombo = Ui.Combo(items, _folder.Length > 0 ? _folder : "@ninguna", 260);
        fcombo.SelectionChanged += (_, _) =>
        {
            var id = fcombo.SelectedId();
            _folder = id is null or "@ninguna" ? "" : id;
            // Si el proyecto ya trae su configuración, se propone su BBDD
            var db = _folder.Length > 0 ? Escaner.ProjectDb(W.Motor.L.Htdocs, _folder) : "";
            if (db.Length > 0 && _db.Length == 0)
            {
                _db = db;
                W.Toast($"BBDD de su configuración: {db}");
            }
            W.Dispatcher.BeginInvoke(Build);
        };
        s2.Children.Add(fcombo);
        var addFolder = Ui.Button(Ico.Mas, null, "Crear una carpeta nueva", () =>
        {
            var name = Dialogo.Input(W, "Carpeta nueva",
                "Se crea en htdocs al pulsar «Crear y falsear». Si vas a clonar el proyecto con git, clónalo antes y elige su carpeta en la lista.",
                _domain.Length > 0 ? _domain : "carpeta-del-proyecto", "Elegir",
                v => folders.Contains(v) ? (false, "Ya existe: elígela en la lista.", true)
                    : Validacion.IsNewFolder(v) && !Validacion.IsReservedWindowsName(v) ? (true, "Letras sin acentos, números, punto, _ y -", false)
                    : (false, "Letras sin acentos, números, punto, _ y -", v.Length > 0), _domain);
            if (name != null)
            {
                _folder = name;
                Build();
            }
        });
        addFolder.Margin = new Thickness(8, 0, 0, 0);
        s2.Children.Add(addFolder);
        Ui.AddRow(list, r2);

        var dbs = active != null ? st!.ActiveInfo?.Dbs.Select(d => d.Name).ToList() ?? new() : new List<string>();
        var (r3, s3, _, _) = Ui.Row("BBDD", active != null ? $"En {active}" : "No hay ninguna versión activa", Ui.Logo("mariadb", 16));
        var ditems = new List<(string, string)> { ("@sin", "Sin BBDD") };
        ditems.AddRange(dbs.Select(d => (d, d)));
        if (_db.Length > 0 && !dbs.Contains(_db))
            ditems.Add((_db, _db + " (nueva)"));
        var dcombo = Ui.Combo(ditems, _db.Length > 0 ? _db : "@sin", 260);
        dcombo.IsEnabled = active != null;
        dcombo.SelectionChanged += (_, _) => _db = dcombo.SelectedId() is { } id && id != "@sin" ? id : "";
        s3.Children.Add(dcombo);
        var addDb = Ui.Button(Ico.Mas, null, "Crear una BBDD nueva", () =>
        {
            var name = Dialogo.Input(W, "BBDD nueva", $"Pon el nombre de la BBDD de producción. Se crea vacía en {active} al pulsar «Crear y falsear».",
                "nombre_de_la_base", "Elegir",
                v => dbs.Contains(v) ? (false, "Ya existe: elígela en la lista.", true)
                    : Validacion.DbNameProblem(v) == null ? (true, "Letras sin acentos, números, _ y -", false)
                    : (false, "Letras sin acentos, números, _ y -", v.Length > 0));
            if (name != null)
            {
                _db = name;
                Build();
            }
        });
        addDb.IsEnabled = active != null;
        addDb.Margin = new Thickness(8, 0, 0, 0);
        s3.Children.Add(addDb);
        Ui.AddRow(list, r3);

        var (r4, s4, _, _) = Ui.Row("");
        create = Ui.TextButton("Crear y falsear", OnCreate, "BotonAzul");
        s4.Children.Add(create);
        Ui.AddRow(list, r4);
        Update();
        return box;
    }

    void OnCreate()
    {
        var domain = _domain.ToLowerInvariant();
        var active = W.State?.Active;
        var exists = Directory.Exists(Path.Combine(W.Motor.L.Htdocs, _folder));
        var steps = new List<string>
        {
            $"Carpeta {Path.Combine(W.Motor.L.Htdocs, _folder)}{(exists ? "" : " (se crea)")}.",
            $"Vhost http y https de {domain} con su certificado autofirmado.",
        };
        if (_db.Length > 0)
        {
            var have = W.State?.ActiveInfo?.Dbs.Any(d => d.Name == _db) == true;
            steps.Add($"BBDD {_db} en {active}{(have ? " (ya existe: se deja como está)" : " (se crea vacía)")}.");
        }
        steps.Add($"{domain} se falsea en hosts; los demás dominios dejan de estarlo.");
        if (!Dialogo.Confirm(W, $"¿Crear {domain}?", string.Join("\n", steps.Select(s => "• " + s)) + "\n\nSe pide permiso de administrador para hosts.", "Crear y falsear"))
            return;
        var args = new List<string> { "nuevo-dominio", domain, _folder };
        if (_db.Length > 0) args.Add(_db);
        var folder = _folder;
        W.RunTask($"Creando {domain}", args.ToArray(), new OpcionesTarea
        {
            DoneText = $"{domain} listo",
            Env = W.PageOf<PaginaBbdd>("bbdd").DbEnv(),
            OnDone = (ok, _) =>
            {
                if (!ok) return;
                _domain = _folder = _db = "";
                W.Toast($"{domain} falseado: https://{domain} → {folder}");
            },
        });
    }
}
