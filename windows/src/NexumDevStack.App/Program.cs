using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using Microsoft.Win32.SafeHandles;
using NexumDevStack.Core.Cli;
using NexumDevStack.Core.Pila;
using NexumDevStack.Core.Tareas;
using NexumDevStack.Windows;

namespace NexumDevStack.App;

/// <summary>
/// Entrada del programa. Un solo .exe con tres formas de uso:
///   NexumDevStack.exe                       la ventana
///   NexumDevStack.exe &lt;comando&gt; …           la consola (los mismos comandos que la ventana lanza en sus tareas)
///   NexumDevStack.exe --elevado &lt;op&gt; …      lo que se hace con permisos de administrador (lo lanza el programa)
/// </summary>
public static class Program
{
    public static Motor NewMotor() => new(Disposicion.ForCurrentUser(), new PlataformaWindows());

    [STAThread]
    public static int Main(string[] args)
    {
        if (args.Length > 0 && args[0] == "--elevado")
            return NewMotor().ElevatedMain(args.Skip(1).ToList());
        if (Comandos.IsCommand(args))
            return RunConsole(args);
        var app = new App();
        return app.Start();
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetStdHandle(int n);

    [DllImport("kernel32.dll")]
    static extern int GetFileType(IntPtr h);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sa, uint creation, uint flags, IntPtr template);

    static bool Usable(int std)
    {
        var h = GetStdHandle(std);
        return h != IntPtr.Zero && h != new IntPtr(-1) && GetFileType(h) != 0;
    }

    /// <summary>
    /// La consola. El programa es de ventana (no abre una consola al hacer doble clic): para escribir en la
    /// consola desde la que se lanza, se engancha a ella. Desde la ventana (NEXUM_TAREA=1), la salida va por
    /// la tubería, con el protocolo de avance, y la entrada trae «cancelar» y las respuestas de UAC.
    /// </summary>
    static int RunConsole(string[] args)
    {
        var task = Environment.GetEnvironmentVariable("NEXUM_TAREA") == "1";
        TextWriter writer;
        TextReader? reader = null;
        if (Usable(-11))
        {
            writer = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false)) { AutoFlush = true };
            if (task && Usable(-10))
                reader = new StreamReader(Console.OpenStandardInput(), Encoding.UTF8);
        }
        else if (Nativo2.AttachConsole(-1))
        {
            var h = CreateFileW("CONOUT$", 0x40000000 | 0x80000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
            if (h.IsInvalid)
                return 1;
            Console.OutputEncoding = Encoding.UTF8;
            writer = new StreamWriter(new FileStream(h, FileAccess.Write), new UTF8Encoding(false)) { AutoFlush = true };
            writer.WriteLine();
        }
        else
            writer = TextWriter.Null;
        writer = TextWriter.Synchronized(writer);

        var motor = NewMotor();
        CancellationToken cancel;
        if (task && reader != null)
        {
            var canal = new CanalTarea(reader, writer);
            motor.Launcher = canal;
            cancel = canal.Cancel;
        }
        else
        {
            var cts = new CancellationTokenSource();
            Console.CancelKeyPress += (_, e) =>
            {
                e.Cancel = true;
                cts.Cancel();
            };
            cancel = cts.Token;
        }
        var o = new SalidaTexto(writer, protocol: task, cancel);
        var code = Comandos.Run(motor, args, o);
        writer.Flush();
        return code;
    }

    static class Nativo2
    {
        [DllImport("kernel32.dll")]
        public static extern bool AttachConsole(int pid);
    }
}

/// <summary>La aplicación WPF: estilos, tema y la ventana.</summary>
public sealed class App : Application
{
    public int Start()
    {
        ShutdownMode = ShutdownMode.OnMainWindowClose;
        Resources.MergedDictionaries.Add((ResourceDictionary)LoadComponent(new Uri("/NexumDevStack;component/Estilos.xaml", UriKind.Relative)));
        var motor = Program.NewMotor();
        Tema.Apply(Tema.LoadPreference(motor.L));
        DispatcherUnhandledException += (_, e) =>
        {
            e.Handled = true;
            try
            {
                Directory.CreateDirectory(motor.L.UserLogs);
                File.AppendAllText(Path.Combine(motor.L.UserLogs, "ventana-errores.log"), $"{DateTime.Now:s} {e.Exception}\n\n");
            }
            catch (Exception) { }
            Dialogo.Message(MainWindow, "Algo ha fallado en la ventana", e.Exception.Message +
                $"\n\nEl detalle está en {Path.Combine(motor.L.UserLogs, "ventana-errores.log")}.", error: true);
        };
        var win = new VentanaPrincipal(motor);
        MainWindow = win;
        return Run(win);
    }
}
