namespace NexumDevStack.Core.Pila;

/// <summary>
/// Dónde va cada cosa. Por defecto en C:\NexumDevStack:
/// <code>
///   programa\NexumDevStack.exe        copia del programa que se ejecuta con permisos de administrador
///   versiones\php-8.4.27\{apache,php,mariadb,phpmyadmin,conf}   de administrador: tu usuario no las cambia
///   descargas\                        lo descargado y comprobado (de administrador)
///   tareas\                           registros de las tareas con permisos de administrador
///   datos\php-8.4.27\                 las BBDD de cada versión (MariaDB corre con tu usuario)
///   config\httpd-vhosts.conf, ssl\    compartidos por todas las versiones
///   htdocs\                           los proyectos
///   registros\php-8.4.27\             los de Apache y MariaDB de cada versión
///   tmp\                              sesiones y subidas de PHP, temporales de phpMyAdmin
/// </code>
/// Tus preferencias, en %LOCALAPPDATA%\NexumDevStack; tus copias de BBDD, en %USERPROFILE%\nexum-copias.
/// </summary>
public sealed class Disposicion
{
    public const string DefaultRoot = @"C:\NexumDevStack";
    public const string ProjectVhost = "web.local";
    public const string EmptyProject = ".nexum-sin-proyecto";

    public Disposicion(string root, string userDir, string copiesDir)
    {
        // (sin GetFullPath: C:\NexumDevStack ya es absoluta, y así las pruebas generan las mismas rutas en Linux)
        Root = root.TrimEnd('\\', '/');
        UserDir = userDir;
        CopiesDir = copiesDir;
    }

    /// <summary>La de este equipo: C:\NexumDevStack (o NEXUM_RAIZ solo con NEXUM_PRUEBA=1, para probar).</summary>
    public static Disposicion ForCurrentUser()
    {
        var root = DefaultRoot;
        if (Environment.GetEnvironmentVariable("NEXUM_PRUEBA") == "1" &&
            Environment.GetEnvironmentVariable("NEXUM_RAIZ") is { Length: > 3 } custom)
            root = custom;
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return new Disposicion(root, Path.Combine(local, "NexumDevStack"), Path.Combine(home, "nexum-copias"));
    }

    public string Root { get; }
    public string UserDir { get; }
    public string CopiesDir { get; }

    public string Program => Path.Combine(Root, "programa");
    public string ProgramExe => Path.Combine(Program, "NexumDevStack.exe");
    public string Versions => Path.Combine(Root, "versiones");
    public string Downloads => Path.Combine(Root, "descargas");
    public string Tasks => Path.Combine(Root, "tareas");
    public string Data => Path.Combine(Root, "datos");
    public string Config => Path.Combine(Root, "config");
    public string Htdocs => Path.Combine(Root, "htdocs");
    public string Logs => Path.Combine(Root, "registros");
    public string Tmp => Path.Combine(Root, "tmp");

    /// <summary>Carpetas de administrador (tu usuario solo las lee).</summary>
    public string[] AdminDirs => new[] { Program, Versions, Downloads, Tasks };

    /// <summary>Carpetas de tu usuario (y de nadie más del equipo).</summary>
    public string[] UserDirs => new[] { Data, Config, Htdocs, Logs, Tmp };

    public string VhostsFile => Path.Combine(Config, "httpd-vhosts.conf");
    public string SecurityConf => Path.Combine(Config, "nexum-seguridad.conf");
    public string SslDir => Path.Combine(Config, "ssl");
    public string PendingDir => Path.Combine(Config, "pendiente");
    public string PendingHosts => Path.Combine(PendingDir, "hosts");
    public string EmptyProjectDir => Path.Combine(Htdocs, EmptyProject);

    public string VersionDir(string folder) => Path.Combine(Versions, folder);
    public string ApacheDir(string folder) => Path.Combine(VersionDir(folder), "apache");
    public string PhpDir(string folder) => Path.Combine(VersionDir(folder), "php");
    public string MariaDbDir(string folder) => Path.Combine(VersionDir(folder), "mariadb");
    public string PmaDir(string folder) => Path.Combine(VersionDir(folder), "phpmyadmin");
    public string ConfDir(string folder) => Path.Combine(VersionDir(folder), "conf");
    public string HttpdConf(string folder) => Path.Combine(ConfDir(folder), "httpd.conf");
    public string MyIni(string folder) => Path.Combine(ConfDir(folder), "my.ini");
    public string NoFilesDir(string folder) => Path.Combine(ConfDir(folder), "sin-ficheros");
    public string Manifest(string folder) => Path.Combine(VersionDir(folder), "nexum-version.json");
    public string DataDir(string folder) => Path.Combine(Data, folder);
    public string LogDir(string folder) => Path.Combine(Logs, folder);
    public string TmpDir(string folder) => Path.Combine(Tmp, folder);
    public string ApachePid(string folder) => Path.Combine(LogDir(folder), "httpd.pid");
    public string MariaDbPid(string folder) => Path.Combine(LogDir(folder), "mariadb.pid");
    public string ApacheErrorLog(string folder) => Path.Combine(LogDir(folder), "apache-error.log");
    public string MariaDbErrorLog(string folder) => Path.Combine(LogDir(folder), "mariadb.err");

    // Lo de tu usuario (como ~/.lvm-instalador en Linux)
    public string SettingsFile => Path.Combine(UserDir, "ajustes.json");
    public string ProjectsFile => Path.Combine(UserDir, "proyectos");
    public string CustomDomainsFile => Path.Combine(UserDir, "dominios");
    public string ImportsFile => Path.Combine(UserDir, "importaciones");
    public string LocalOffFile => Path.Combine(UserDir, "locales-apagados");
    public string CrossSiteOffFile => Path.Combine(UserDir, "sin-barrera-entre-webs");
    public string ThemeFile => Path.Combine(UserDir, "ventana-tema");
    public string DbSizesCache => Path.Combine(UserDir, "cache", "bbdd-tamanos");
    public string PsParamsDir => Path.Combine(UserDir, "prestashop");
    public string PsLoadedFile => Path.Combine(UserDir, "prestashop-cargados");
    public string WpConfigDir => Path.Combine(UserDir, "wordpress");
    public string UserLogs => Path.Combine(UserDir, "registros");
    public string EditCopiesDir => Path.Combine(UserDir, "ediciones");
    public string ProcessesFile => Path.Combine(UserDir, "procesos.json");

    public bool IsPrepared => Directory.Exists(Root) && Directory.Exists(Versions) && Directory.Exists(Config);
}
