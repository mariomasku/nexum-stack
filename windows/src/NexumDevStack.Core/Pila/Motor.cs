using NexumDevStack.Core.BaseDatos;
using NexumDevStack.Core.Catalogo;
using NexumDevStack.Core.Configuracion;
using NexumDevStack.Core.Descargas;
using NexumDevStack.Core.Elevacion;
using NexumDevStack.Core.Plataforma;
using NexumDevStack.Core.Proyectos;
using NexumDevStack.Core.Tareas;
using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.Pila;

/// <summary>
/// Todas las operaciones de Nexum Dev Stack (las de la consola y las de la ventana). Lo que depende de
/// Windows va por <see cref="IPlataforma"/>.
/// </summary>
public sealed partial class Motor
{
    public Motor(Disposicion layout, IPlataforma platform, Puertos? ports = null, ILanzadorElevado? launcher = null)
    {
        L = layout;
        Pf = platform;
        P = ports ?? Puertos.Default;
        Launcher = launcher ?? new LanzadorPlataforma(this);
    }

    public Disposicion L { get; }
    public IPlataforma Pf { get; }
    public Puertos P { get; }

    /// <summary>Cómo se lanzan las operaciones con permisos de administrador (la ventana pone el suyo).</summary>
    public ILanzadorElevado Launcher { get; set; }

    /// <summary>Contraseña de root de MariaDB si la tiene (MYSQL_PWD), como en Linux.</summary>
    public string? RootPassword { get; set; } = Environment.GetEnvironmentVariable("MYSQL_PWD");

    /// <summary>Ruta de este programa (para relanzarlo).</summary>
    public string SelfPath { get; set; } = Environment.ProcessPath ?? "NexumDevStack.exe";

    public Vinculos Links => new(L.ProjectsFile);
    public DominiosPropios CustomDomains => new(L.CustomDomainsFile);

    Firmas? _firmas;
    public Firmas Signatures => _firmas ??= Firmas.Embedded();

    // ------------------------------------------------------------------ versiones instaladas
    /// <summary>Versiones instaladas (versiones\php-X.Y.Z con su nexum-version.json), de la más nueva a la más antigua.</summary>
    public List<Manifiesto> Installed()
    {
        var list = new List<Manifiesto>();
        if (!Directory.Exists(L.Versions))
            return list;
        foreach (var dir in Directory.EnumerateDirectories(L.Versions))
        {
            var name = Path.GetFileName(dir);
            if (!Validacion.IsVersionFolder(name) || Ficheros.IsLink(dir))
                continue;
            var m = Manifiesto.Load(L, name);
            if (m != null)
                list.Add(m);
        }
        list.Sort((a, b) => Versiones.Compare(b.Php, a.Php));
        return list;
    }

    public Manifiesto? Find(string folder) =>
        Validacion.IsVersionFolder(folder) ? Manifiesto.Load(L, folder) : null;

    /// <summary>La versión por su carpeta (php-8.4.27) o por su PHP (8.4.27); si no existe, NexumException.</summary>
    public Manifiesto Require(string version)
    {
        var folder = version.StartsWith("php-", StringComparison.Ordinal) ? version : "php-" + version;
        return Find(folder) ?? throw new NexumException($"No existe la versión {folder} (en {L.Versions})");
    }

    /// <summary>La versión activa (si sigue instalada).</summary>
    public string? Active
    {
        get
        {
            var a = Ajustes.Load(L).Active;
            return a != null && Find(a) != null ? a : null;
        }
    }

    void SetActive(string? folder)
    {
        var a = Ajustes.Load(L);
        a.Active = folder;
        a.Save(L);
    }

    public ClienteMariaDb Client(string folder, int? port = null) =>
        new(Pf.Processes, Path.Combine(L.MariaDbDir(folder), "bin"), port ?? P.MariaDb, RootPassword);

    /// <summary>Por qué no se puede desinstalar una versión ("" si se puede).</summary>
    public string RemoveBlocker(string folder)
    {
        if (Find(folder) == null)
            return $"No existe la versión {folder}.";
        if (Active == folder)
            return $"{folder} es la versión activa. Cambia antes a otra versión (o desactívala) y vuelve a intentarlo.";
        return "";
    }

    /// <summary>Las BBDD de una versión (de su carpeta de datos).</summary>
    public List<Bbdd> Databases(string folder) => ListaBbdd.FromDataDir(L.DataDir(folder), L.ImportsFile);

    /// <summary>Lanzador por defecto: el del sistema, con la copia del programa de administrador.</summary>
    sealed class LanzadorPlataforma : ILanzadorElevado
    {
        readonly Motor _m;
        public LanzadorPlataforma(Motor m) => _m = m;

        public bool Launch(IReadOnlyList<string> args, out string detail, out Func<int?>? exitCode)
        {
            exitCode = null;
            if (!_m.Pf.Elevation.Launch(_m.ElevatedExe(args), args, out detail, out var process))
                return false;
            if (process != null)
                exitCode = () =>
                {
                    try { return process.HasExited ? process.ExitCode : null; }
                    catch (InvalidOperationException) { return null; }
                };
            return true;
        }
    }

    /// <summary>
    /// Programa que se lanza con permisos de administrador: la copia de programa\ (de administrador: tu usuario
    /// no la puede cambiar). Solo preparar y actualizar-programa usan este mismo (todavía no hay copia, o es
    /// más vieja).
    /// </summary>
    public string ElevatedExe(IReadOnlyList<string> args)
    {
        var op = args.Count > 1 ? args[1] : "";
        if (op is "preparar" or "actualizar-programa" || !File.Exists(L.ProgramExe))
            return SelfPath;
        // (si la copia es más vieja que este programa, este: al terminar se copia a sí mismo en programa\)
        var installed = InstalledProgramVersion();
        if (installed == null || Versiones.Compare(installed, AppInfo.Version) < 0)
            return SelfPath;
        return L.ProgramExe;
    }

    Elevador Elevator => new(L, Pf, Launcher, (order, o) => RunElevated(order, o));

    /// <summary>Hace una operación con permisos de administrador (con el aviso de UAC si hace falta).</summary>
    public void Elevated(string op, string? arg, ISalida o, string what) => Elevator.Run(op, arg, o, what);
}
