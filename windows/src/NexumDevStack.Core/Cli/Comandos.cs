using System.Text;
using NexumDevStack.Core.Catalogo;
using NexumDevStack.Core.Pila;
using NexumDevStack.Core.Proyectos;
using NexumDevStack.Core.Tareas;
using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.Cli;

/// <summary>
/// La consola: NexumDevStack.exe &lt;comando&gt; [opciones], con los mismos nombres que lvm-instalador de Linux
/// donde tienen sentido en Windows. La ventana lanza estos mismos comandos para las tareas largas.
/// </summary>
public static class Comandos
{
    public const string Help = """
NexumDevStack.exe - Nexum Dev Stack para Windows: versiones de PHP con su Apache, MariaDB y phpMyAdmin.

Cada versión va en C:\NexumDevStack\versiones\php-X.Y.Z (de administrador) con sus propias BBDD en
C:\NexumDevStack\datos\php-X.Y.Z; solo una está activa. Los proyectos, en C:\NexumDevStack\htdocs.

<...> es un dato obligatorio y [...] uno opcional; a | b son alternativas. Desde PowerShell, para ver la
salida y esperar a que termine: .\NexumDevStack.exe estado | Out-Default

=== VENTANA ===================================================================================

  NexumDevStack.exe
      Sin comando: abre la ventana

=== VERSIONES =================================================================================

  NexumDevStack.exe preparar
      Crea C:\NexumDevStack con sus permisos (pide permiso de administrador una vez)

  NexumDevStack.exe estado
      Versión activa, si está en marcha y lo que tiene cada una

  NexumDevStack.exe versiones
      Versiones instaladas

  NexumDevStack.exe ramas
      Versiones de PHP que se pueden instalar, con su soporte en php.net

  NexumDevStack.exe instalar <8.4|8.4.27> [...]
      Instala versiones de PHP (8.4 = el último parche de la rama). Pide permiso de administrador

  NexumDevStack.exe usar <versión>
      Monta una versión: para la actual, cierra lo que quede en memoria y arranca la nueva (ej.: usar 8.4.27)

  NexumDevStack.exe arrancar | parar | reiniciar
      La versión activa. Parar no deja ningún proceso en memoria

  NexumDevStack.exe desactivar
      Para la versión activa y la desmonta

  NexumDevStack.exe servicio apache|mariadb arrancar|parar|reiniciar
      Un servicio de la versión activa

  NexumDevStack.exe procesos | cerrar-procesos
      Procesos de Nexum en memoria / cierra los que no son de la versión activa

  NexumDevStack.exe al-dia <versión>
      ¿Tiene el último parche de su rama?

  NexumDevStack.exe actualizar-a <versión> <php>
      Instala PHP <php> al lado, le copia las BBDD con sus vínculos y, si era la activa, la activa. La de
      antes no se toca: desinstálala cuando compruebes la nueva

  NexumDevStack.exe desinstalar <versión> [--copia]
      Borra una versión (no la activa); --copia guarda antes sus BBDD en %USERPROFILE%\nexum-copias

  NexumDevStack.exe instalar-vcredist
      Descarga e instala el runtime de Visual C++ de Microsoft (lo necesitan Apache y PHP)

  NexumDevStack.exe actualizar-programa
      Copia este programa (más nuevo) a C:\NexumDevStack\programa, el que se usa con permisos de administrador

=== BASES DE DATOS ============================================================================

  (en la versión activa en marcha; si root tiene contraseña: variable MYSQL_PWD)

  NexumDevStack.exe list-db
      BBDD de cada versión

  NexumDevStack.exe crear-bd <base>
      Crea una base vacía (utf8mb4_general_ci)

  NexumDevStack.exe borrar-bd <base> [--copia]
      Borra una base; --copia guarda antes una copia en %USERPROFILE%\nexum-copias

  NexumDevStack.exe importar-bd <fichero> <base> [--crear] [--sin-copia] [--proyecto <carpeta>]
      Carga un .sql, .sql.gz o .zip; --crear crea la base si no existe. Si ya existe, antes se borran todas
      sus tablas (con copia si tenía alguna; --sin-copia, sin ella); --proyecto la deja como base de esa
      carpeta (WordPress: wp-config.php; PrestaShop: parameters.php)

  NexumDevStack.exe exportar-bd <base> <fichero.zip|.sql|.sql.gz> [versión]
      Descarga una copia de una base (sin versión, de la activa)

  NexumDevStack.exe copiar-bd <base> <origen> <destino> [--como <nombre>] [--carpeta <carpeta|->] [--sustituir]
      Copia una BBDD a otra versión (la de origen no se toca)

  NexumDevStack.exe vincular-bd <base> <versión> <carpeta|->
      La carpeta del proyecto de esa BBDD en esa versión (- = ninguna)

  NexumDevStack.exe usuario-pruebas <base> [carpeta]
      Crea o deja al día el administrador de pruebas del panel: local@local.test, contraseña local

=== PROYECTOS Y DOMINIOS ======================================================================

  NexumDevStack.exe proyectos
      Proyectos de htdocs con su tipo y su BBDD

  NexumDevStack.exe cargar-proyecto <carpeta> [versión] [base]
      Apunta web.local a htdocs\<carpeta> (y monta antes esa versión). Tienda PrestaShop: crea lo que
      falte de su vhost y su certificado y falsea su dominio en hosts

  NexumDevStack.exe desmontar-proyecto
      web.local deja de apuntar al proyecto cargado

  NexumDevStack.exe vaciar-cache <carpeta> | --bd <base>
      Vacía var/cache de una tienda PrestaShop

  NexumDevStack.exe nuevo-dominio <dominio> <carpeta> [base]
      Proyecto nuevo con su dominio de producción falseado

  NexumDevStack.exe hosts-falsear <dominio> si|no
      Falsea (127.0.0.1) o deja de falsear el dominio de un vhost

  NexumDevStack.exe hosts-enlace
      web.local pasa a llevar a 127.0.0.1

  NexumDevStack.exe vhosts --aplicar <fichero> | hosts --aplicar <fichero>
      Aplica una copia editada de los vhosts (se comprueba con Apache) o de hosts

  NexumDevStack.exe barrera-web [si|no]
      Barrera entre webs (encendida si no se apaga)

  NexumDevStack.exe confiar-certificados [dominio|--quitar]
      El navegador acepta el certificado propio de cada proyecto falseado (Windows pregunta)

=== INFORMACIÓN ===============================================================================

  NexumDevStack.exe version | acerca | novedades
      Versión del programa / qué hace / lista de cambios

  NexumDevStack.exe --ayuda
      Esta ayuda
""";

    /// <summary>¿Es un comando de la consola (y no abrir la ventana)?</summary>
    public static bool IsCommand(string[] args) =>
        args.Length > 0 && args[0] is not ("ventana" or "--ventana");

    /// <summary>Ejecuta un comando. Devuelve el código de salida (0 bien, 1 error, 2 uso, 130 cancelado).</summary>
    public static int Run(Motor m, string[] args, ISalida o)
    {
        try
        {
            return Dispatch(m, args, o);
        }
        catch (OperationCanceledException)
        {
            o.Line("Cancelado.");
            return 130;
        }
        catch (NexumException ex)
        {
            o.Line(ex.Message);
            return ex.ExitCode == 0 ? 1 : ex.ExitCode;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or HttpRequestException)
        {
            o.Line("Error: " + ex.Message);
            return 1;
        }
    }

    static string Arg(string[] a, int i, string usage) =>
        i < a.Length ? a[i] : throw new NexumException("Uso: NexumDevStack.exe " + usage, 2);

    static bool Flag(List<string> a, string flag) => a.Remove(flag);

    static string? Option(List<string> a, string flag)
    {
        var i = a.IndexOf(flag);
        if (i < 0) return null;
        if (i + 1 >= a.Count) throw new NexumException($"Falta el valor de {flag}", 2);
        var v = a[i + 1];
        a.RemoveRange(i, 2);
        return v;
    }

    static int Dispatch(Motor m, string[] args, ISalida o)
    {
        var cmd = args.Length > 0 ? args[0] : "--ayuda";
        var rest = args.Skip(1).ToList();
        switch (cmd)
        {
            case "--ayuda" or "-h" or "--help" or "ayuda":
                o.Line(Help);
                return 0;
            case "version" or "--version":
                o.Line(AppInfo.Version);
                return 0;
            case "acerca":
                o.Line($"{AppInfo.Name} {AppInfo.Version}\n{AppInfo.About}\n{AppInfo.Signature}");
                return 0;
            case "novedades":
                o.Line(AppInfo.Changes);
                return 0;
            case "preparar":
                m.Prepare(o);
                return 0;
            case "estado":
                Status(m, o);
                return 0;
            case "versiones" or "list":
                foreach (var v in m.Installed())
                    o.Line($"{v.Folder}  PHP {v.Php}  Apache {v.Apache}  MariaDB {v.MariaDb}  phpMyAdmin {v.Pma}{(m.Active == v.Folder ? "  (activa)" : "")}");
                if (m.Installed().Count == 0) o.Line("No hay ninguna versión instalada.");
                return 0;
            case "ramas":
                foreach (var b in m.Branches(o.Cancel))
                    o.Line($"PHP {b.Branch,-5} {b.Latest,-8} {StateText(b.PhpNetState),-15} {b.State}{(b.State == "instalada" ? " en " + b.Folder : "")}");
                return 0;
            case "parches":
                foreach (var p in m.Patches(Arg(args, 1, "parches <rama>"), o.Cancel))
                    o.Line($"PHP {p.Version,-8} {p.Date}  {(p.Security ? "seguridad" : "errores  ")}  {(p.Installable ? p.State : "sin suma publicada para Windows")}");
                return 0;
            case "instalar":
            {
                var list = new List<string>();
                var php = Option(rest, "--php");
                if (php != null) list.AddRange(php.Split(',', StringSplitOptions.RemoveEmptyEntries));
                Flag(rest, "--si");
                list.AddRange(rest.SelectMany(x => x.Split(',', StringSplitOptions.RemoveEmptyEntries)));
                if (list.Count == 0) throw new NexumException("Uso: NexumDevStack.exe instalar <8.4|8.4.27> [...]", 2);
                var failed = 0;
                for (int i = 0; i < list.Count; i++)
                {
                    try
                    {
                        if (list.Count > 1) o.Line($"=== {i + 1} de {list.Count}: PHP {list[i]} ===");
                        var folder = m.Install(list[i], o);
                        o.Result("I", folder);
                    }
                    catch (NexumException ex) when (list.Count > 1 && ex.ExitCode != 130)
                    {
                        o.Line(ex.Message);
                        failed++;
                    }
                }
                return failed == 0 ? 0 : 1;
            }
            case "preparar-datos":
                m.InitData(m.Require(Arg(args, 1, "preparar-datos <versión>")).Folder, o);
                return 0;
            case "usar" or "use" or "activar":
                m.Use(Arg(args, 1, "usar <versión>"), o);
                return 0;
            case "arrancar" or "start":
                m.Start(o);
                return 0;
            case "parar" or "stop":
                m.Stop(o);
                return 0;
            case "desactivar" or "disable":
                m.Stop(o, deactivate: true);
                return 0;
            case "reiniciar" or "restart":
                m.Restart(o);
                return 0;
            case "servicio":
                m.Service(Arg(args, 1, "servicio apache|mariadb arrancar|parar|reiniciar"),
                    Arg(args, 2, "servicio apache|mariadb arrancar|parar|reiniciar"), o);
                return 0;
            case "procesos":
                foreach (var v in m.Installed())
                    foreach (var p in m.VersionProcesses(v.Folder))
                        o.Line($"{v.Folder}  {Path.GetFileName(p.ImagePath)}  PID {p.Pid}{(m.Active == v.Folder ? "" : "  (sobra)")}");
                return 0;
            case "cerrar-procesos":
                m.CloseStray(o);
                return 0;
            case "al-dia" or "gui-al-dia":
            {
                var (state, latest) = m.UpToDate(Arg(args, 1, "al-dia <versión>"), o.Cancel);
                o.Line($"{state}|{latest}");
                return 0;
            }
            case "actualizar-a":
                m.UpgradeTo(Arg(args, 1, "actualizar-a <versión> <php>"), Arg(args, 2, "actualizar-a <versión> <php>"), o);
                return 0;
            case "desinstalar":
            {
                var backup = Flag(rest, "--copia");
                m.Uninstall(rest.FirstOrDefault() ?? throw new NexumException("Uso: NexumDevStack.exe desinstalar <versión> [--copia]", 2), backup, o);
                return 0;
            }
            case "instalar-vcredist":
                m.InstallVcRedist(o);
                return 0;
            case "actualizar-programa":
                m.Elevated("actualizar-programa", null, o, "Copiar este programa a " + m.L.ProgramExe);
                return 0;
            case "list-db":
                foreach (var v in m.Installed())
                {
                    var dbs = m.Databases(v.Folder);
                    o.Line($"{v.Folder}: {Texto.Plural(dbs.Count, "BBDD", "BBDD")} (sin contar las del sistema)");
                    foreach (var db in dbs) o.Line("  " + db.Name);
                }
                return 0;
            case "crear-bd":
                m.CreateDatabase(Arg(args, 1, "crear-bd <base>"), o);
                return 0;
            case "bd-info" or "gui-bd-info":
            {
                var (t, b) = m.DatabaseInfo(Arg(args, 1, "bd-info <base>"));
                o.Line($"I|{t}|{b}");
                return 0;
            }
            case "borrar-bd":
            {
                var backup = Flag(rest, "--copia");
                m.DropDatabase(rest.FirstOrDefault() ?? throw new NexumException("Uso: NexumDevStack.exe borrar-bd <base> [--copia]", 2), backup, o);
                return 0;
            }
            case "importar-bd":
            {
                var create = Flag(rest, "--crear");
                Flag(rest, "--vaciar");
                var noCopy = Flag(rest, "--sin-copia");
                var project = Option(rest, "--proyecto")?.TrimEnd('/', '\\');
                if (rest.Count < 2) throw new NexumException("Uso: NexumDevStack.exe importar-bd <fichero> <base> [--crear] [--sin-copia] [--proyecto <carpeta>]", 2);
                m.ImportDatabase(rest[0], rest[1], create, !noCopy, project, o);
                return 0;
            }
            case "exportar-bd":
                m.ExportDatabase(Arg(args, 1, "exportar-bd <base> <fichero> [versión]"), Arg(args, 2, "exportar-bd <base> <fichero> [versión]"),
                    args.Length > 3 ? args[3] : null, o);
                return 0;
            case "copiar-bd":
            {
                var replace = Flag(rest, "--sustituir");
                var name = Option(rest, "--como");
                var link = Option(rest, "--carpeta");
                if (rest.Count < 3) throw new NexumException("Uso: NexumDevStack.exe copiar-bd <base> <origen> <destino> [--como <nombre>] [--carpeta <carpeta|->] [--sustituir]", 2);
                m.CopyDatabase(rest[0], m.Require(rest[1]).Folder, m.Require(rest[2]).Folder, name, link?.TrimEnd('/', '\\'), replace, o);
                return 0;
            }
            case "vincular-bd":
                m.LinkDatabase(Arg(args, 1, "vincular-bd <base> <versión> <carpeta|->"), Arg(args, 2, "vincular-bd <base> <versión> <carpeta|->"),
                    Arg(args, 3, "vincular-bd <base> <versión> <carpeta|->").TrimEnd('/', '\\'), o);
                return 0;
            case "usuario-pruebas":
                foreach (var k in m.TestAdmin(Arg(args, 1, "usuario-pruebas <base> [carpeta]"), args.Length > 2 ? args[2] : null, o))
                    o.Line($"A|{k}|{BaseDatos.Sql.TestAdminUser}|{BaseDatos.Sql.TestAdminPass}");
                return 0;
            case "proyectos":
                foreach (var p in m.ReadProjects().List)
                    o.Line($"{p.Name}  {(p.Kind == "wp" ? "WordPress" : p.Kind == "ps" ? "PrestaShop" : "-")}  {(p.Db.Length > 0 ? p.Db : "sin BBDD")}");
                return 0;
            case "cargar-proyecto":
                m.LoadProject(Arg(args, 1, "cargar-proyecto <carpeta> [versión] [base]"), args.Length > 2 && args[2].Length > 0 ? args[2] : null,
                    args.Length > 3 ? args[3] : null, o);
                return 0;
            case "desmontar-proyecto":
                m.UnloadProject(o);
                return 0;
            case "vaciar-cache":
            {
                var db = Option(rest, "--bd");
                if (db != null) m.ClearCacheDb(db, o);
                else m.ClearCache(rest.FirstOrDefault() ?? throw new NexumException("Uso: NexumDevStack.exe vaciar-cache <carpeta> | --bd <base>", 2), o);
                return 0;
            }
            case "nuevo-dominio":
                m.NewCustomDomain(Arg(args, 1, "nuevo-dominio <dominio> <carpeta> [base]"), Arg(args, 2, "nuevo-dominio <dominio> <carpeta> [base]"),
                    args.Length > 3 ? args[3] : null, o);
                return 0;
            case "hosts-falsear":
            {
                var state = Arg(args, 2, "hosts-falsear <dominio> si|no");
                if (state is not ("si" or "no")) throw new NexumException("Uso: NexumDevStack.exe hosts-falsear <dominio> si|no", 2);
                m.FakeDomain(Arg(args, 1, "hosts-falsear <dominio> si|no"), state == "si", o);
                return 0;
            }
            case "hosts-enlace":
                m.FixProjectHost(o);
                return 0;
            case "vhosts":
                m.ApplyVhostsFile(Option(rest, "--aplicar") ?? throw new NexumException("Uso: NexumDevStack.exe vhosts --aplicar <fichero> (para editarlos, Configuración en la ventana)", 2), o);
                return 0;
            case "hosts":
                m.ApplyHostsFile(Option(rest, "--aplicar") ?? throw new NexumException("Uso: NexumDevStack.exe hosts --aplicar <fichero> (para editarlo, Configuración en la ventana)", 2), o);
                return 0;
            case "barrera-web":
                if (args.Length < 2)
                {
                    o.Line(m.CrossSiteOn ? "encendida" : "apagada");
                    return 0;
                }
                if (args[1] is not ("si" or "no")) throw new NexumException("Uso: NexumDevStack.exe barrera-web [si|no]", 2);
                m.CrossSite(args[1] == "si", o);
                return 0;
            case "confiar-certificados":
            {
                var remove = Flag(rest, "--quitar");
                m.TrustCertificates(rest.FirstOrDefault(), remove, o);
                return 0;
            }
            default:
                o.Line($"Comando desconocido: {cmd}. NexumDevStack.exe --ayuda tiene la lista.");
                return 2;
        }
    }

    static string StateText(string s) => s switch
    {
        "stable" => "estable",
        "security" => "solo seguridad",
        "eol" => "sin soporte",
        _ => "",
    };

    static void Status(Motor m, ISalida o)
    {
        var st = m.ReadState(withCertificates: false);
        if (!st.Prepared)
        {
            o.Line($"Nexum Dev Stack no está preparado en este equipo ({m.L.Root}): NexumDevStack.exe preparar");
            return;
        }
        if (st.Active == null)
            o.Line("Ninguna versión activa.");
        else
            o.Line($"Activa: {st.Active} — Apache {(st.ApacheOn ? "en marcha" : "parado")}, MariaDB {(st.MariaDbOn ? "en marcha" : "parado")}");
        foreach (var v in st.Versions)
        {
            var sb = new StringBuilder();
            sb.Append($"  {v.Folder}: PHP {v.M.Php}, Apache {v.M.Apache}, MariaDB {v.M.MariaDb}, phpMyAdmin {v.M.Pma}, {Texto.Plural(v.Dbs.Count, "BBDD", "BBDD")}");
            if (v.P2S == Php2Shell.Estado.Vulnerable) sb.Append(" — VULNERABLE (PHP2Shell)");
            o.Line(sb.ToString());
        }
        foreach (var (f, p) in st.Stray)
            o.Line($"Aviso: procesos de {f} en memoria: {p} (NexumDevStack.exe cerrar-procesos)");
        foreach (var p in st.Ports)
            o.Line($"Aviso: el puerto {p.Port} lo usa {p.ProcessName} (PID {p.Pid})");
        if (!st.VcOk)
            o.Line("Aviso: falta el runtime de Visual C++ 2015-2026 (x64) o es antiguo: NexumDevStack.exe instalar-vcredist");
        var loaded = m.LoadedProject();
        o.Line(loaded switch
        {
            null => $"Sin vhost de proyectos ({Disposicion.ProjectVhost}): se crea al cargar el primero.",
            "" => $"{Disposicion.ProjectVhost}: ningún proyecto cargado.",
            _ => $"{Disposicion.ProjectVhost} -> {loaded}",
        });
    }
}
