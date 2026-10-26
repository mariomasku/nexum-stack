using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using NexumDevStack.Core.Cli;
using NexumDevStack.Core.Elevacion;
using NexumDevStack.Core.Tareas;
using NexumDevStack.Core.Util;
using NexumDevStack.Windows;

namespace NexumDevStack.App;

/// <summary>Cómo se enseña una tarea.</summary>
public sealed class OpcionesTarea
{
    /// <summary>Tarea larga (instalar, subir una BBDD): partes, porcentaje y confirmar antes de cancelar.</summary>
    public bool Progress { get; init; }
    public string? DoneText { get; init; }
    /// <summary>Si termina bien, la ventana se cierra sola y sale un aviso abajo.</summary>
    public bool AutoClose { get; init; }
    public Action<bool, VentanaTarea>? OnDone { get; init; }
    public (string Title, string Text, string Ok)? CancelText { get; init; }
    public Dictionary<string, string?>? Env { get; init; }
}

/// <summary>
/// La ventana de una tarea (como Task de Linux): ejecuta este mismo programa con el comando (NEXUM_TAREA=1) y
/// enseña su avance: la barra gruesa azul con «NN % · quedan unos X», el tiempo, las partes y el registro
/// como una terminal (con los \r de las descargas y los contadores). Las peticiones de permiso de
/// administrador de la tarea las lanza esta ventana, que está delante, para que el aviso de UAC salga encima.
/// </summary>
public sealed class VentanaTarea : Window
{
    readonly VentanaPrincipal _main;
    readonly OpcionesTarea _opts;
    readonly string[] _args;
    readonly Consola _console = new();
    readonly TextBox _log;
    readonly TextBlock _head, _what, _pct, _info;
    readonly ProgressBar _bar;
    readonly StackPanel _parts;
    readonly Border _partsCard;
    readonly Expander _expander;
    readonly Button _report, _extra, _close;
    readonly TextBlock _doneIcon;
    readonly DispatcherTimer _timer;
    readonly StringBuilder _pending = new();
    readonly DateTime _started = DateTime.UtcNow;
    Process? _proc;
    Process? _elevated;
    bool _elevatedReported;
    bool _finished, _cancelled;
    int? _percent;
    long _bytesDone, _bytesTotal;
    (int First, int Last, DateTime Since)? _seenPct;
    List<string> _partNames = new();
    int _partCurrent;
    public List<(string Key, string Value)> Results { get; } = new();

    public VentanaTarea(VentanaPrincipal main, string title, string[] args, OpcionesTarea opts)
    {
        _main = main;
        _args = args;
        _opts = opts;
        Owner = main;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.Height;
        Width = 700;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ShowInTaskbar = false;
        Title = title;
        FontFamily = (FontFamily)Application.Current.Resources["Letra"];
        FontSize = 13;
        SetResourceReference(ForegroundProperty, "Texto");

        var box = new StackPanel { Margin = new Thickness(30, 26, 30, 24) };
        _doneIcon = Ui.Icon(Ico.Hecho, 54, "Azul");
        _doneIcon.Visibility = Visibility.Collapsed;
        _doneIcon.Margin = new Thickness(0, 0, 0, 8);
        box.Children.Add(_doneIcon);
        _head = Ui.Wrap(title, "titulo");
        _head.TextAlignment = TextAlignment.Center;
        _head.HorizontalAlignment = HorizontalAlignment.Center;
        box.Children.Add(_head);

        var top = new Grid { Margin = new Thickness(0, 16, 0, 6) };
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        _what = Ui.Text("", "tenue");
        _pct = Ui.Text("", "negrita");
        Grid.SetColumn(_pct, 1);
        top.Children.Add(_what);
        top.Children.Add(_pct);
        box.Children.Add(top);
        _bar = new ProgressBar { Minimum = 0, Maximum = 100 };
        _bar.SetResourceReference(StyleProperty, "BarraGruesa");
        box.Children.Add(_bar);
        _info = Ui.Wrap("", "chico", "tenue");
        _info.Margin = new Thickness(0, 6, 0, 0);
        box.Children.Add(_info);

        _parts = new StackPanel();
        _partsCard = Ui.Card(_parts);
        _partsCard.Margin = new Thickness(0, 14, 0, 0);
        _partsCard.Visibility = Visibility.Collapsed;
        box.Children.Add(_partsCard);

        _log = new TextBox
        {
            IsReadOnly = true, FontFamily = Ui.Mono, FontSize = 12, TextWrapping = TextWrapping.Wrap, BorderThickness = new Thickness(0),
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(12, 10, 12, 10), Height = opts.Progress ? 240 : 200,
            Background = Brushes.Transparent,
        };
        _log.SetResourceReference(ForegroundProperty, "TextoConsola");
        _log.Template = ConsoleTemplate();
        var consoleFrame = new Border { CornerRadius = new CornerRadius(10), Child = _log, Margin = new Thickness(0, 8, 0, 0), BorderThickness = new Thickness(1) };
        consoleFrame.SetResourceReference(Border.BackgroundProperty, "Consola");
        consoleFrame.BorderBrush = new SolidColorBrush(Color.FromArgb(64, 0, 0, 0));
        _expander = new Expander { Header = "Ver registro", Content = consoleFrame, IsExpanded = !opts.Progress, Margin = new Thickness(0, 14, 0, 0) };
        box.Children.Add(_expander);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 18, 0, 0) };
        _report = Ui.TextButton("Ver el log del error", ShowReport);
        _report.Visibility = Visibility.Collapsed;
        _extra = Ui.TextButton("", () => { }, "BotonAzul");
        _extra.Visibility = Visibility.Collapsed;
        _close = Ui.TextButton("Cancelar", OnClose);
        foreach (var b in new[] { _report, _extra, _close })
        {
            b.Margin = new Thickness(5, 0, 5, 0);
            b.MinWidth = 110;
            buttons.Children.Add(b);
        }
        box.Children.Add(buttons);

        var frame = new Border
        {
            CornerRadius = new CornerRadius(14), BorderThickness = new Thickness(1), Margin = new Thickness(20), Child = box,
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
        Closing += (_, e) =>
        {
            if (!_finished)
            {
                e.Cancel = true;
                OnClose();
            }
        };
        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(opts.Progress ? 1000 : 150) };
        _timer.Tick += (_, _) => Tick();
        Loaded += (_, _) => Start();
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    static extern bool AllowSetForegroundWindow(int pid);

    static ControlTemplate ConsoleTemplate()
    {
        // (sin el borde ni el fondo de los campos: va dentro del recuadro oscuro de la consola)
        var t = new ControlTemplate(typeof(TextBox));
        var sv = new FrameworkElementFactory(typeof(ScrollViewer), "PART_ContentHost");
        sv.SetValue(MarginProperty, new TemplateBindingExtension(PaddingProperty));
        t.VisualTree = sv;
        return t;
    }

    // ------------------------------------------------------------------ proceso
    void Start()
    {
        var psi = new ProcessStartInfo(_main.Motor.SelfPath)
        {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8, WorkingDirectory = Path.GetDirectoryName(_main.Motor.SelfPath)!,
        };
        foreach (var a in _args)
            psi.ArgumentList.Add(a);
        psi.Environment["NEXUM_TAREA"] = "1";
        if (_opts.Env != null)
            foreach (var (k, v) in _opts.Env)
                if (v == null) psi.Environment.Remove(k);
                else psi.Environment[k] = v;
        try
        {
            _proc = Process.Start(psi);
        }
        catch (Exception ex)
        {
            Append($"No se ha podido lanzar la tarea: {ex.Message}\n");
            Finish(127);
            return;
        }
        if (_proc == null)
        {
            Finish(127);
            return;
        }
        _proc.StandardInput.AutoFlush = true;
        // (lo que enseñe la tarea, como el aviso de Windows al confiar en un certificado, puede salir delante)
        try { AllowSetForegroundWindow(_proc.Id); } catch (Exception) { }
        Reader(_proc.StandardOutput);
        Reader(_proc.StandardError);
        _proc.EnableRaisingEvents = true;
        _proc.Exited += (_, _) => Dispatcher.BeginInvoke(() =>
        {
            // (lo que quede en las tuberías llega antes: se espera un momento)
            var t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(300) };
            t.Tick += (_, _) =>
            {
                t.Stop();
                Flush();
                Finish(SafeExit(_proc));
            };
            t.Start();
        });
        _timer.Start();
        Tick();
    }

    static int SafeExit(Process? p)
    {
        try { return p?.ExitCode ?? 1; } catch (InvalidOperationException) { return 1; }
    }

    void Reader(StreamReader r)
    {
        var t = new Thread(() =>
        {
            var buf = new char[8192];
            try
            {
                int n;
                while ((n = r.Read(buf, 0, buf.Length)) > 0)
                {
                    var text = new string(buf, 0, n);
                    Dispatcher.BeginInvoke(() => Feed(text));
                }
            }
            catch (Exception) { }
        }) { IsBackground = true };
        t.Start();
    }

    /// <summary>Lo que llega de la tarea: las líneas del protocolo van a la barra; el resto, a la consola.</summary>
    void Feed(string text)
    {
        _pending.Append(text);
        var s = _pending.ToString();
        int nl;
        while ((nl = s.IndexOf('\n')) >= 0)
        {
            var line = s[..nl].TrimEnd('\r');
            s = s[(nl + 1)..];
            HandleLine(line);
        }
        _pending.Clear();
        // Un trozo sin \n (una descarga que avanza con \r) va ya a la consola, salvo que pueda ser el principio
        // de una línea del protocolo
        if (s.Length > 0 && !s.StartsWith(Protocolo.Mark[..Math.Min(s.Length, Protocolo.Mark.Length)], StringComparison.Ordinal))
            Append(s);
        else
            _pending.Append(s);
    }

    void Flush()
    {
        if (_pending.Length > 0)
        {
            var rest = _pending.ToString();
            _pending.Clear();
            HandleLine(rest);
        }
    }

    void HandleLine(string line)
    {
        if (CanalTarea.ParseRequest(line) is { } req)
        {
            Elevate(req);
            return;
        }
        var a = Protocolo.Parse(line);
        if (a == null)
        {
            Append(line + "\n");
            return;
        }
        switch (a.Kind)
        {
            case 'P':
                _percent = a.Number;
                _what.Text = Texto.Capitalize(a.Text ?? "");
                break;
            case 'C':
                ShowParts(a.Parts!.ToList(), a.Number);
                break;
            case 'B':
                _bytesDone = a.Done;
                _bytesTotal = a.Total;
                break;
            case 'R':
                var t = a.Text ?? "";
                var bar = t.IndexOf('|');
                Results.Add((bar < 0 ? t : t[..bar], bar < 0 ? "" : t[(bar + 1)..]));
                break;
        }
    }

    void Append(string text)
    {
        _console.Write(text);
        var full = _console.Text;
        _log.Text = full.Length > 400_000 ? full[^400_000..] : full;
        _log.ScrollToEnd();
        if (!_opts.Progress && _percent == null)
        {
            var found = Regex.Matches(Regex.Replace(text, @"\x1b\[[0-9;?]*[A-Za-z]", ""), @"(?<![\d.,])(\d{1,3})(?:[.,]\d+)?\s?%")
                .Select(m => int.Parse(m.Groups[1].Value)).Where(n => n <= 100).ToList();
            if (found.Count > 0)
            {
                var last = found[^1];
                _seenPct = _seenPct == null || last < _seenPct.Value.Last - 30
                    ? (last, last, DateTime.UtcNow)
                    : (_seenPct.Value.First, last, _seenPct.Value.Since);
            }
        }
    }

    /// <summary>La tarea pide hacer algo con permisos de administrador: lo lanza esta ventana (comprobado).</summary>
    void Elevate(string[] args)
    {
        string reply;
        if (args.Length < 1 || args[0] != ProtocoloElevado.Flag || ProtocoloElevado.Parse(args.Skip(1).ToList(), out var why) == null)
        {
            reply = "no petición no válida";
            Append("Aviso: la tarea ha pedido algo con permisos de administrador que no se reconoce. No se ha lanzado.\n");
        }
        else
        {
            ElevacionWindows.OwnerWindow = new WindowInteropHelper(this).Handle;
            Activate();
            if (_main.Motor.Pf.Elevation.Launch(_main.Motor.ElevatedExe(args), args, out var detail, out var p))
            {
                _elevated = p;
                _elevatedReported = false;
                reply = "ok";
            }
            else
                reply = "no " + detail;
        }
        try { _proc?.StandardInput.WriteLine("elevado " + reply); }
        catch (Exception) { }
    }

    void ShowParts(List<string> parts, int current)
    {
        if (!parts.SequenceEqual(_partNames))
        {
            _partNames = parts;
            _parts.Children.Clear();
        }
        _partCurrent = current;
        _partsCard.Visibility = parts.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        _parts.Children.Clear();
        for (int i = 0; i < parts.Count; i++)
        {
            var n = i + 1;
            UIElement state = n < current || (_finished && !_cancelled && n <= current)
                ? Ui.Icon(Ico.Hecho, 13, "Verde")
                : n == current ? (_finished ? Ui.Icon(Ico.Error, 13, "Rojo") : Ui.Dot(true, 8, pulse: true))
                : Ui.Text("…", "tenue");
            var (row, suffix, _, _) = Ui.Row(parts[i]);
            suffix.Children.Add(state);
            Ui.AddRow(_parts, row);
        }
    }

    void Tick()
    {
        if (_finished)
            return;
        if (_elevated != null && !_elevatedReported)
        {
            try
            {
                if (_elevated.HasExited)
                {
                    _elevatedReported = true;
                    _proc?.StandardInput.WriteLine("elevado-fin " + SafeExit(_elevated));
                }
            }
            catch (Exception) { }
        }
        var elapsed = (DateTime.UtcNow - _started).TotalSeconds;
        if (_percent is { } pct)
        {
            _bar.IsIndeterminate = false;
            _bar.Value = pct;
            _pct.Text = $"{pct} %" + (pct < 100 ? "   ·   " + Texto.TimeLeft(elapsed, pct, 100 - pct) : "");
            _info.Text = (_bytesTotal > 0 ? $"{Texto.Size(Math.Min(_bytesDone, _bytesTotal))} de {Texto.Size(_bytesTotal)}   ·   " : "") +
                         $"Tiempo: {Texto.Clock(elapsed)}";
        }
        else if (_seenPct is { } seen)
        {
            _bar.IsIndeterminate = false;
            _bar.Value = seen.Last;
            _what.Text = "Trabajando…";
            _pct.Text = $"{seen.Last} %   ·   " + Texto.TimeLeft((DateTime.UtcNow - seen.Since).TotalSeconds, seen.Last - seen.First, 100 - seen.Last);
            _info.Text = $"Tiempo: {Texto.Clock(elapsed)}";
        }
        else
        {
            _bar.IsIndeterminate = true;
            if (_what.Text.Length == 0) _what.Text = "Trabajando…";
            _pct.Text = "";
            _info.Text = $"Tiempo: {Texto.Clock(elapsed)}  ·  sin porcentaje: esta tarea no dice cuánto le queda";
        }
    }

    void Finish(int code)
    {
        if (_finished)
            return;
        _finished = true;
        _timer.Stop();
        var ok = code == 0 && !_cancelled;
        if (code == 130) _cancelled = true;
        _bar.IsIndeterminate = false;
        _info.Text = $"Tiempo total: {Texto.Clock((DateTime.UtcNow - _started).TotalSeconds)}";
        _close.Content = "Cerrar";
        SaveLog(ok);
        if (_cancelled)
        {
            _head.Text = "Cancelado";
            _what.Text = "Cancelado";
            _pct.Text = "";
        }
        else if (ok)
        {
            _bar.Value = 100;
            _head.Text = _opts.DoneText ?? "Terminado";
            _what.Text = "Terminado";
            _pct.Text = "100 %";
            _doneIcon.Visibility = Visibility.Visible;
        }
        else
        {
            _head.Text = "No se ha podido completar";
            _what.Text = "Error";
            _bar.SetResourceReference(ForegroundProperty, "Rojo");
            _expander.IsExpanded = true;
            _report.Visibility = Visibility.Visible;
        }
        if (_partNames.Count > 0)
            ShowParts(_partNames, ok ? _partNames.Count + 1 : _partCurrent);
        _opts.OnDone?.Invoke(ok, this);
        if (ok && _opts.AutoClose)
        {
            Close();
            _main.Toast(_opts.DoneText ?? "Terminado");
        }
    }

    void SaveLog(bool ok)
    {
        try
        {
            Directory.CreateDirectory(_main.Motor.L.UserLogs);
            var file = Path.Combine(_main.Motor.L.UserLogs, $"tarea-{DateTime.Now:yyyyMMdd-HHmmss}-{(ok ? "bien" : "error")}.log");
            File.WriteAllText(file, $"{Title}\nNexumDevStack.exe {string.Join(" ", _args)}\nNexum Dev Stack {Core.AppInfo.Version}\n\n{_console.Text}");
        }
        catch (Exception) { }
    }

    /// <summary>Botón extra al terminar (Activar la versión instalada, Abrir la carpeta…).</summary>
    public void Offer(string text, Action action)
    {
        _extra.Content = text;
        _extra.Click += (_, _) => { Close(); action(); };
        _extra.Visibility = Visibility.Visible;
    }

    void OnClose()
    {
        if (_finished)
        {
            Close();
            return;
        }
        if (_opts.Progress)
        {
            var (title, text, okLabel) = _opts.CancelText ?? ("¿Cancelar la instalación?", "Se pierde lo descargado. Las versiones instaladas no se tocan.", "Cancelar la instalación");
            if (!Dialogo.Confirm(this, title, text, okLabel, destructive: true))
                return;
        }
        _cancelled = true;
        _close.IsEnabled = false;
        _what.Text = "Cancelando…";
        try { _proc?.StandardInput.WriteLine("cancelar"); }
        catch (Exception) { }
        // Si no termina en 30 s, se cierra (solo la tarea: Apache y MariaDB, si se han arrancado, siguen)
        var t = new DispatcherTimer { Interval = TimeSpan.FromSeconds(30) };
        t.Tick += (_, _) =>
        {
            t.Stop();
            if (!_finished)
            {
                try { _proc?.Kill(false); } catch (Exception) { }
            }
        };
        t.Start();
    }

    void ShowReport()
    {
        var text = _console.Text.Trim();
        var d = new Dialogo(this, "Log del error",
            $"Copia el texto para buscar la solución o para enviarlo. Los registros de las tareas están en {_main.Motor.L.UserLogs}.", 760);
        var box = new TextBox
        {
            Text = text, IsReadOnly = true, FontFamily = Ui.Mono, FontSize = 12, TextWrapping = TextWrapping.Wrap, Height = 380,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        };
        d.Add(box);
        var copy = Ui.TextButton("Copiar todo", () => { Clipboard.SetText(text); _main.Toast("Copiado al portapapeles"); }, "BotonAzul");
        var folder = Ui.TextButton("Abrir la carpeta de registros", () => _main.OpenFolder(_main.Motor.L.UserLogs));
        folder.Margin = new Thickness(8, 0, 0, 0);
        d.Add(Ui.HStack(8, copy, folder));
        d.Buttons("Cerrar", null);
        d.Run();
    }
}
