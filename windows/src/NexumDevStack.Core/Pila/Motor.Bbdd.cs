using System.Diagnostics;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using NexumDevStack.Core.BaseDatos;
using NexumDevStack.Core.Plataforma;
using NexumDevStack.Core.Proyectos;
using NexumDevStack.Core.Tareas;
using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.Pila;

/// <summary>Las BBDD: crear, borrar, subir (con la carga protegida), descargar y copiar entre versiones.</summary>
public sealed partial class Motor
{
    /// <summary>
    /// Hace algo con el MariaDB de una versión: el que esté en marcha o, si no, uno temporal solo para esto (en
    /// un puerto libre de 127.0.0.1, con sus usuarios y con tu usuario), que se para al terminar.
    /// </summary>
    public void WithServer(string folder, ISalida o, Action<ClienteMariaDb> action)
    {
        if (Find(folder) == null)
            throw new NexumException($"No existe la versión {folder}");
        if (MariaDbRunning(folder))
        {
            action(Client(folder));
            return;
        }
        RequireNotElevated();
        EnsureRuntimeDirs(folder);
        var port = FreePort();
        var tmp = Path.Combine(L.TmpDir(folder), "mariadb");
        var pid = Path.Combine(tmp, "temporal.pid");
        var log = Path.Combine(tmp, "temporal.err");
        o.Line($"Arrancando un MariaDB temporal de {folder} (solo en 127.0.0.1:{port}, para esto)...");
        var serverPid = Pf.Processes.StartDetached(MariaDbdExe(folder), new[]
        {
            "--defaults-file=" + L.MyIni(folder), "--port=" + port, "--bind-address=127.0.0.1", "--pid-file=" + pid,
            "--log-error=" + log, "--skip-log-bin",
        }, Path.Combine(L.MariaDbDir(folder), "bin"));
        var client = Client(folder, port);
        try
        {
            var ready = WaitUntil(() => PortOpen(port) && client.Check().State is "ok" or "clave", 60);
            if (!ready)
                throw new NexumException("El MariaDB temporal no ha arrancado. Últimas líneas de su registro:\n" + Tail(log, 15));
            action(client);
        }
        finally
        {
            var args = client.Connection();
            args.Add("shutdown");
            Pf.Processes.Run(client.AdminExe, args, TimeSpan.FromSeconds(60), client.BinDir, client.Env(RootPassword));
            if (!WaitUntil(() => !Pf.Processes.IsRunning(serverPid, MariaDbdExe(folder)), 30))
                Pf.Processes.Kill(serverPid, MariaDbdExe(folder));
            o.Line("MariaDB temporal parado.");
        }
    }

    /// <summary>El MariaDB de la versión activa en marcha (si no, NexumException con el motivo).</summary>
    public (string Folder, ClienteMariaDb Client) ActiveDb()
    {
        var a = Active ?? throw new NexumException("No hay ninguna versión activa.");
        if (!MariaDbRunning(a))
            throw new NexumException($"El MariaDB de {a} no está en marcha. Arráncalo en la pestaña Versiones de PHP.");
        var c = Client(a);
        var (state, detail) = c.Check();
        if (state == "clave")
            throw new NexumException("MariaDB pide la contraseña de root: ponla en la variable MYSQL_PWD", 3);
        if (state != "ok")
            throw new NexumException($"No se puede entrar en el MariaDB de {a}: {detail}");
        return (a, c);
    }

    static bool Exists(ClienteMariaDb c, string db) => c.Scalar(Sql.Exists(db)) is { } n && n != "0";

    public void CreateDatabase(string db, ISalida o)
    {
        if (Validacion.DbNameProblem(db) is { } p) throw new NexumException(p);
        var (folder, c) = ActiveDb();
        if (Exists(c, db))
            throw new NexumException($"Ya hay una base de datos {db} en {folder}");
        var r = c.Run(Sql.CreateDb(db));
        if (r.ExitCode != 0) throw new NexumException(ClienteMariaDb.Clean(r.Output));
        ListaBbdd.NoteImport(L.ImportsFile, L.DataDir(folder), db, null);
        o.Line($"Base de datos {db} creada en {folder}");
    }

    /// <summary>Tablas y tamaño de una base de la activa.</summary>
    public (int Tables, long Bytes) DatabaseInfo(string db)
    {
        if (Validacion.DbNameProblem(db) is { } p) throw new NexumException(p);
        var (folder, c) = ActiveDb();
        if (!Exists(c, db))
            throw new NexumException($"No hay ninguna base de datos {db} en {folder}");
        var row = c.Rows(Sql.Info(db)).FirstOrDefault() ?? new[] { "0", "0" };
        return (int.TryParse(row[0], out var t) ? t : 0, long.TryParse(row.ElementAtOrDefault(1), out var b) ? b : 0);
    }

    public void DropDatabase(string db, bool backup, ISalida o)
    {
        if (Validacion.DbNameProblem(db) is { } p) throw new NexumException(p);
        var (folder, c) = ActiveDb();
        if (!Exists(c, db))
            throw new NexumException($"No hay ninguna base de datos {db} en {folder}");
        if (backup)
        {
            var dest = Path.Combine(Ficheros.EnsureDir(L.CopiesDir), $"{folder}-{db}-{Ficheros.Stamp()}.sql.gz");
            o.Line($"Guardando copia de {db}...");
            try
            {
                ExportDatabase(db, dest, folder, o);
            }
            catch (NexumException ex)
            {
                throw new NexumException(ex.Message + "\nNo se ha podido guardar la copia, así que NO se borra nada.");
            }
        }
        o.Line($"Borrando la base de datos {db} de {folder}...");
        var r = c.Run(Sql.DropDb(db));
        if (r.ExitCode != 0) throw new NexumException(ClienteMariaDb.Clean(r.Output));
        ListaBbdd.NoteImport(L.ImportsFile, L.DataDir(folder), db, null);
        o.Line($"Base de datos {db} borrada");
    }

    /// <summary>Tamaño de cada BBDD de la versión activa en marcha (se guarda para enseñarlo también con otras).</summary>
    public Dictionary<(string Folder, string Db), (long Bytes, long When)> DatabaseSizes()
    {
        var cache = new Dictionary<(string, string), (long, long)>();
        var text = Ficheros.ReadSmallText(L.DbSizesCache);
        if (text != null)
            foreach (var line in text.Replace("\r\n", "\n").Split('\n'))
                if (line.Split('|') is [var f, var d, var b, var w] && Validacion.IsVersionFolder(f) && Validacion.IsDbName(d) &&
                    long.TryParse(b, out var bytes) && long.TryParse(w, out var when))
                    cache[(f, d)] = (bytes, when);
        var a = Active;
        if (a != null && MariaDbRunning(a))
        {
            var c = Client(a);
            var r = c.Run(Sql.Sizes, timeout: TimeSpan.FromSeconds(30));
            if (r.ExitCode == 0)
            {
                var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
                foreach (var k in cache.Keys.Where(k => k.Item1 == a).ToList())
                    cache.Remove(k);
                foreach (var line in r.Output.Replace("\r\n", "\n").Split('\n'))
                    if (line.Split('\t') is [var d, var b] && Validacion.IsDbName(d) && long.TryParse(b, out var bytes))
                        cache[(a, d)] = (bytes, now);
                try
                {
                    Ficheros.WriteAtomic(L.DbSizesCache, string.Join("\n", cache.Select(kv => $"{kv.Key.Item1}|{kv.Key.Item2}|{kv.Value.Item1}|{kv.Value.Item2}")) + "\n");
                }
                catch (IOException) { }
            }
        }
        return cache;
    }

    // ------------------------------------------------------------------ descargar (exportar-bd)
    /// <summary>
    /// Descarga una copia de una base (estructura, datos, rutinas y disparadores) a .sql, .sql.gz o .zip, sin el
    /// administrador de pruebas. De la versión indicada (en marcha o con un MariaDB temporal).
    /// </summary>
    public void ExportDatabase(string db, string dest, string? version, ISalida o)
    {
        if (Validacion.DbNameProblem(db) is { } p) throw new NexumException(p);
        var folder = version != null ? Require(version).Folder : Active ?? throw new NexumException("No hay ninguna versión activa.");
        if (!Databases(folder).Any(x => x.Name.Equals(db, StringComparison.OrdinalIgnoreCase)))
            throw new NexumException($"No hay ninguna base de datos {db} en {folder}");
        dest = Path.GetFullPath(dest);
        var dir = Path.GetDirectoryName(dest)!;
        if (!Directory.Exists(dir))
            throw new NexumException($"No se puede escribir en {dir}");
        o.Line($"Base de datos: {db} ({folder})");
        o.Line($"Destino: {dest}");
        WithServer(folder, o, c => Dump(c, db, dest, o));
    }

    void Dump(ClienteMariaDb c, string db, string dest, ISalida o)
    {
        // El administrador de pruebas no sale en la copia: sus filas se quedan fuera (la BBDD no se toca)
        var skip = new List<string>();
        var only = new List<(string Table, string Where)>();
        foreach (var row in c.Rows(Sql.TestAdminTables(db)))
        {
            if (row.Length < 2 || !Sql.IsIdent(row[0])) continue;
            var (t, col) = (row[0], row[1]);
            if (col == "user_login")
            {
                if (c.Scalar($"SELECT COUNT(*) FROM `{t}` WHERE user_login = '{Sql.TestAdminUser}'", db) is not { } n || n == "0") continue;
                skip.Add(t);
                only.Add((t, $"NOT (user_login <=> '{Sql.TestAdminUser}')"));
                var pfx = t[..^"users".Length];
                if (c.Scalar(Sql.IsBaseTable(db, pfx + "usermeta")) == "1")
                {
                    skip.Add(pfx + "usermeta");
                    only.Add((pfx + "usermeta", $"user_id IS NULL OR user_id NOT IN (SELECT ID FROM `{t}` WHERE user_login = '{Sql.TestAdminUser}')"));
                }
            }
            else
            {
                if (c.Scalar($"SELECT COUNT(*) FROM `{t}` WHERE email = '{Sql.TestAdminUser}'", db) is not { } n || n == "0") continue;
                skip.Add(t);
                only.Add((t, $"NOT (email <=> '{Sql.TestAdminUser}')"));
                var pfx = t[..^"employee".Length];
                if (c.Scalar(Sql.IsBaseTable(db, pfx + "employee_shop")) == "1")
                {
                    skip.Add(pfx + "employee_shop");
                    only.Add((pfx + "employee_shop", $"id_employee IS NULL OR id_employee NOT IN (SELECT id_employee FROM `{t}` WHERE email = '{Sql.TestAdminUser}')"));
                }
            }
        }
        if (only.Count > 0)
            o.Line($"El administrador de pruebas ({Sql.TestAdminUser}) no va en la copia");
        var part = dest + ".parte";
        var routines = true;
        o.Line("Descargando...");
        while (true)
        {
            try
            {
                using (var file = new FileStream(part, FileMode.Create, FileAccess.Write, FileShare.Read))
                {
                    var lower = dest.ToLowerInvariant();
                    Stream sink;
                    ZipArchive? zip = null;
                    if (lower.EndsWith(".zip"))
                    {
                        zip = new ZipArchive(file, ZipArchiveMode.Create, true);
                        var inner = Path.GetFileNameWithoutExtension(dest);
                        if (!inner.EndsWith(".sql", StringComparison.OrdinalIgnoreCase)) inner += ".sql";
                        sink = zip.CreateEntry(inner, CompressionLevel.Optimal).Open();
                    }
                    else if (lower.EndsWith(".gz"))
                        sink = new GZipStream(file, CompressionLevel.Optimal, true);
                    else
                        sink = file;
                    try
                    {
                        var baseArgs = c.Connection();
                        baseArgs.AddRange(new[] { "--default-character-set=utf8mb4", "--single-transaction", "--quick", "--triggers", "--max-allowed-packet=1G" });
                        var args = new List<string>(baseArgs);
                        if (routines) args.Add("--routines");
                        args.AddRange(skip.Select(t => $"--ignore-table={db}.{t}"));
                        args.Add(db);
                        RunDump(c, args, sink, file, o);
                        foreach (var (t, where) in only)
                        {
                            var a = new List<string>(baseArgs) { "--where=" + where, db, t };
                            RunDump(c, a, sink, file, o);
                        }
                    }
                    finally
                    {
                        if (!ReferenceEquals(sink, file)) sink.Dispose();
                        zip?.Dispose();
                    }
                }
                File.Move(part, dest, true);
                o.Line($"Copia guardada: {dest} ({Texto.Size(new FileInfo(dest).Length)})");
                return;
            }
            catch (DumpException ex) when (routines && ex.Message.Contains("mysql.proc"))
            {
                // MariaDB sin las tablas del sistema al día: sin rutinas (las tablas y los datos van completos)
                o.Line("Aviso: no se pueden leer sus funciones y procedimientos (la tabla mysql.proc es de un MariaDB anterior); se descarga sin ellos.");
                routines = false;
                TryDelete(part);
            }
            catch (Exception ex)
            {
                TryDelete(part);
                if (ex is OperationCanceledException) throw;
                throw new NexumException("No se ha podido descargar la base de datos.\n" + ex.Message);
            }
        }
    }

    sealed class DumpException : Exception
    {
        public DumpException(string m) : base(m) { }
    }

    static void TryDelete(string f)
    {
        try { if (File.Exists(f)) File.Delete(f); } catch (IOException) { }
    }

    void RunDump(ClienteMariaDb c, List<string> args, Stream sink, FileStream file, ISalida o)
    {
        using var p = c.StartStreaming(c.DumpExe, args, RootPassword, redirectStdin: false, redirectStdout: true);
        var errTask = p.StandardError.ReadToEndAsync();
        var src = p.StandardOutput.BaseStream;
        var buf = new byte[1 << 16];
        int n;
        var shown = DateTime.UtcNow;
        try
        {
            while ((n = src.Read(buf, 0, buf.Length)) > 0)
            {
                if (o.Cancel.IsCancellationRequested)
                {
                    try { p.Kill(true); } catch (Exception) { }
                    o.Cancel.ThrowIfCancellationRequested();
                }
                sink.Write(buf, 0, n);
                if ((DateTime.UtcNow - shown).TotalSeconds >= 2)
                {
                    shown = DateTime.UtcNow;
                    o.Line($"  {Texto.Size(file.Length)} escritos");
                }
            }
        }
        finally
        {
            p.WaitForExit();
        }
        var err = errTask.Result;
        if (p.ExitCode != 0)
            throw new DumpException(ClienteMariaDb.Clean(err));
    }

    // ------------------------------------------------------------------ subir (importar-bd)
    /// <summary>
    /// Carga un .sql, .sql.gz o .zip en una base de la versión activa (o de <paramref name="target"/>, con el
    /// cliente de ese MariaDB). Si ya existe, antes se vacía (con copia en nexum-copias si tiene tablas). El
    /// volcado se carga con el usuario de esa base (nexum_bd_&lt;base&gt;), que solo puede tocarla; después se
    /// bloquea y root repasa que no quede nada peligroso (vistas o rutinas INVOKER, eventos, DATA DIRECTORY).
    /// </summary>
    public void ImportDatabase(string file, string db, bool create, bool backup, string? project, ISalida o,
        (string Folder, ClienteMariaDb Client)? target = null)
    {
        if (!File.Exists(file))
            throw new NexumException($"No se puede leer el fichero {file}");
        if (Validacion.DbNameProblem(db) is { } p) throw new NexumException(p);
        if (project != null && !Validacion.IsProjectFolder(project))
            throw new NexumException($"Carpeta de proyecto no válida: {project}");
        var (folder, c) = target ?? ActiveDb();
        var version = c.Scalar("SELECT VERSION()")?.Split('-')[0] ?? "";
        long size = new FileInfo(file).Length;
        var name = Path.GetFileName(file).Replace('|', '_');
        bool sandbox;
        string kind, inner;
        long innerSize;
        using (var v = Volcado.Open(file))
        {
            kind = v.Kind;
            inner = v.Inner;
            innerSize = v.InnerSize;
        }
        sandbox = Volcado.StartsWithSandbox(file);
        o.Line($"Fichero: {file} ({Texto.Size(size)})");
        if (kind == "zip")
            o.Line($"Dentro del zip: {inner} ({Texto.Size(innerSize)}, se descomprime al vuelo)");
        o.Line($"Destino: base {db} en {folder} (MariaDB {version})");
        if (sandbox)
            o.Line("Se quita la primera línea (/*M!999999\\- enable the sandbox mode */), que los MariaDB antiguos no entienden");
        var engines = c.Scalar(Sql.DangerousEngines);
        if (!string.IsNullOrEmpty(engines) && engines != "NULL")
            throw new NexumException($"No se carga: MariaDB tiene activos los motores {engines}, con los que una tabla del volcado podría entrar como root en este MariaDB. Desactívalos (UNINSTALL SONAME) y vuelve a cargarlo.");
        string? saved = null;
        if (!Exists(c, db))
        {
            if (!create)
                throw new NexumException($"La base {db} no existe en {folder} (con --crear se crea)");
            o.Line($"Creando la base de datos {db}...");
            Check(c.Run(Sql.CreateDb(db)));
        }
        else
        {
            var tables = c.Scalar(Sql.Tables(db));
            if (tables == null || !int.TryParse(tables, out var nt))
                throw new NexumException($"No se pueden ver las tablas de {db}: no se ha cambiado nada.");
            if (nt > 0 && backup)
            {
                saved = Path.Combine(Ficheros.EnsureDir(L.CopiesDir), $"{folder}-{db}-antes-de-cargar-{Ficheros.Stamp()}.sql.gz");
                o.Line($"{db} ya tiene {Texto.Plural(nt, "tabla", "tablas")}: se borran todas antes de cargar.");
                o.Line($"Antes se guarda una copia suya en {saved}");
                try { Dump(c, db, saved, o); }
                catch (NexumException ex) { throw new NexumException(ex.Message + $"\nNo se ha podido guardar la copia de {db}, así que no se ha cambiado nada."); }
            }
            o.Line($"Vaciando la base de datos {db}...");
            var charset = c.Scalar(Sql.Charset(db)) ?? "utf8mb4 COLLATE utf8mb4_general_ci";
            if (!System.Text.RegularExpressions.Regex.IsMatch(charset, "^[A-Za-z0-9_]+ COLLATE [A-Za-z0-9_]+$"))
                charset = "utf8mb4 COLLATE utf8mb4_general_ci";
            Check(c.Run($"DROP DATABASE `{db}`; CREATE DATABASE `{db}` CHARACTER SET {charset}"));
        }
        c.Run("SET GLOBAL max_allowed_packet = GREATEST(@@GLOBAL.max_allowed_packet, 1073741824)");

        var user = Sql.ImportUser(db);
        var pass = Convert.ToBase64String(RandomNumberGenerator.GetBytes(18)).Replace("/", "").Replace("+", "").Replace("=", "");
        DropImportUsers(c);
        if (c.Run(Sql.PrepareImportUser(db, Sql.NativeHash(pass))).ExitCode != 0)
            throw new NexumException("No se ha podido preparar el usuario de la base para cargar el volcado");
        var start = DateTime.UtcNow;
        var rc = 0;
        string errors = "";
        var cancelled = false;
        o.Line("Cargando...");
        o.Parts(new[] { $"Cargando {name} en {db}" }, 1);
        try
        {
            var args = c.Connection(user);
            args.AddRange(new[] { "--default-character-set=utf8mb4", "--binary-mode", "--local-infile=0", "--max-allowed-packet=1G", db });
            using var proc = c.StartStreaming(c.ClientExe, args, pass, redirectStdin: true, redirectStdout: false);
            var errTask = proc.StandardError.ReadToEndAsync();
            using var v = Volcado.Open(file);
            using var progressTimer = new Timer(_ =>
            {
                var (done, total) = v.Position();
                o.Bytes(done, total);
                if (total > 0) o.Progress((int)(done * 100 / Math.Max(1, total)), "cargando");
            }, null, 500, 1000);
            try
            {
                FiltroVolcado.Copy(v.Content, proc.StandardInput.BaseStream, o.Cancel);
            }
            catch (OperationCanceledException)
            {
                cancelled = true;
            }
            catch (IOException)
            {
                // (el cliente se ha cerrado: su error va en stderr)
            }
            try { proc.StandardInput.Close(); } catch (IOException) { }
            if (cancelled)
            {
                try { proc.Kill(true); } catch (Exception) { }
            }
            proc.WaitForExit();
            errors = errTask.Result;
            rc = proc.ExitCode;
        }
        finally
        {
            // Primero se cortan sus conexiones; después eventos y tablas con DIRECTORY, luego lo INVOKER; se
            // bloquea y root repasa que no quede nada
            c.Run(Sql.KillUser(user));
            NeutralizeExtras(c, db, user, pass, o);
            NeutralizeInvoker(c, db, user, pass, o);
            LockImportUser(c, user);
            RootCleanup(c, db, o);
        }
        if (cancelled)
        {
            o.Line($"Carga interrumpida. Lo anterior ya está en {db}.");
            if (saved != null) o.Line($"Lo que tenía antes está en {saved} (se vuelve a cargar con importar-bd).");
            throw new OperationCanceledException();
        }
        var secs = (int)(DateTime.UtcNow - start).TotalSeconds;
        if (rc != 0)
        {
            o.Line(ClienteMariaDb.Clean(errors));
            var msg = $"Error al cargar {name}. Lo anterior al error ya está en {db}.\n" +
                      "Si el error es «Access denied», el volcado intenta tocar otra base o crear usuarios: solo se carga lo que va en " +
                      $"{db} (un volcado de una sola base, como los de phpMyAdmin).";
            if (saved != null) msg += $"\nLo que tenía antes está en {saved} (se vuelve a cargar con importar-bd).";
            throw new NexumException(msg);
        }
        var nTables = c.Scalar(Sql.Tables(db)) ?? "?";
        o.Line($"Cargado en {secs / 60} min {secs % 60} s. La base {db} tiene ahora {nTables} {(nTables == "1" ? "tabla" : "tablas")}.");
        ListaBbdd.NoteImport(L.ImportsFile, L.DataDir(folder), db, DateTimeOffset.UtcNow.ToUnixTimeSeconds());
        // Administrador de pruebas para el botón del panel (WordPress o PrestaShop)
        var admins = TestAdmin(c, db, project ?? Links.LinkOf(db, folder), o);
        if (admins.Count > 0)
            o.Line($"Administrador de pruebas del panel: {Sql.TestAdminUser}, contraseña {Sql.TestAdminPass}");
        if (project != null)
            ImportProject(c, folder, db, project, o);
    }

    static void Check(ResultadoProceso r)
    {
        if (r.ExitCode != 0) throw new NexumException(ClienteMariaDb.Clean(r.Output));
    }

    void NeutralizeExtras(ClienteMariaDb c, string db, string user, string pass, ISalida o)
    {
        var events = c.Run(Sql.EventNames, db, raw: true, user: user, password: pass);
        if (events.ExitCode == 0 && events.Output.Trim().Length > 0)
        {
            var drops = c.Run(Sql.EventDrop, db, raw: true, user: user, password: pass);
            c.Run("", db, force: true, user: user, password: pass, stdin: drops.Output);
            o.Line("Aviso: el volcado traía eventos programados (se ejecutan solos en el servidor). Se han borrado: " +
                   Sql.NamesForWarning(events.Output));
        }
        var direct = c.Run(Sql.DirectoryTablesDrop, db, raw: true, user: user, password: pass).Output;
        var partitioned = c.Run(Sql.PartitionedShowCreate, db, raw: true, user: user, password: pass).Output;
        var more = partitioned.Trim().Length > 0
            ? Sql.DirectoryDrops(c.Run("", db, force: true, user: user, password: pass, stdin: partitioned).Output)
            : new List<string>();
        var all = direct.Replace("\r\n", "\n").Split('\n').Where(l => l.StartsWith("DROP TABLE", StringComparison.Ordinal)).Concat(more).Distinct().ToList();
        if (all.Count == 0)
            return;
        c.Run("", db, force: true, user: user, password: pass, stdin: string.Join("\n", all) + "\n");
        o.Line("Aviso: el volcado traía tablas con DATA DIRECTORY o INDEX DIRECTORY, que guardan sus ficheros fuera de la carpeta de MariaDB. Se han borrado (con sus ficheros): " +
               Sql.NamesForWarning(string.Join("\n", all.Select(x => x.Replace("DROP TABLE IF EXISTS `", "").TrimEnd(';').TrimEnd('`')))));
        if (c.Run(Sql.DirectoryLeft, db, user: user, password: pass).Output.Trim().Length > 0)
            o.Line($"ATENCIÓN: siguen quedando tablas con DATA DIRECTORY en {db}.");
    }

    void NeutralizeInvoker(ClienteMariaDb c, string db, string user, string pass, ISalida o)
    {
        var alters = c.Run(Sql.InvokerToDefiner, db, raw: true, user: user, password: pass);
        if (alters.Output.Trim().Length > 0)
            c.Run("", db, force: true, user: user, password: pass, stdin: alters.Output);
        var left = c.Run(Sql.InvokerLeft, db, raw: true, user: user, password: pass).Output;
        if (left.Trim().Length == 0)
            return;
        var drops = c.Run(Sql.InvokerDrop, db, raw: true, user: user, password: pass).Output;
        c.Run("", db, force: true, user: user, password: pass, stdin: drops);
        o.Line("Aviso: el volcado traía vistas o rutinas SQL SECURITY INVOKER que no se han podido pasar a DEFINER (rotas o mal hechas). " +
               "Se han borrado, porque se ejecutarían con los permisos de quien las usara: " + Sql.NamesForWarning(left));
    }

    static void LockImportUser(ClienteMariaDb c, string user)
    {
        var pass = Convert.ToBase64String(RandomNumberGenerator.GetBytes(18)).Replace("/", "").Replace("+", "").Replace("=", "");
        c.Run(Sql.KillUser(user));
        c.Run(Sql.LockImportUser(user, pass));
        c.Run(Sql.KillUser(user));
    }

    void RootCleanup(ClienteMariaDb c, string db, ISalida o)
    {
        var drops = c.Run(Sql.RootCleanup(db), raw: true, force: true).Output;
        var partitioned = c.Run(Sql.PartitionedShowCreateRoot(db), raw: true).Output;
        var more = partitioned.Trim().Length > 0
            ? Sql.DirectoryDrops(c.Run("", force: true, stdin: partitioned).Output, db)
            : new List<string>();
        var all = drops.Replace("\r\n", "\n").Split('\n').Where(l => l.Contains("DROP ", StringComparison.Ordinal)).Concat(more).ToList();
        if (all.Count == 0)
            return;
        c.Run("", force: true, stdin: string.Join("\n", all) + "\n");
        var left = c.Run(Sql.RootCleanupLeft(db), raw: true, force: true).Output;
        o.Line($"Aviso: en {db} quedaban {all.Count} cosas del volcado que no deben estar (vistas o rutinas INVOKER, eventos o tablas con DATA DIRECTORY): las ha borrado root.");
        if (left.Trim().Length > 0)
            o.Line($"ATENCIÓN: siguen en {db}: {Sql.NamesForWarning(left, 10)}. No abras esa base como root en phpMyAdmin hasta quitarlas.");
    }

    /// <summary>Bloquea los usuarios de bases que hayan quedado abiertos (una carga que no terminó).</summary>
    void DropImportUsers(ClienteMariaDb c)
    {
        var r = c.Run(Sql.OpenImportUsers);
        if (r.ExitCode != 0) return;
        foreach (var u in r.Output.Replace("\r\n", "\n").Split('\n'))
            if (System.Text.RegularExpressions.Regex.IsMatch(u, "^nexum_bd_[A-Za-z0-9_-]+$"))
            {
                LockImportUser(c, u);
                var db = u["nexum_bd_".Length..];
                if (Validacion.IsDbName(db))
                    RootCleanup(c, db, new SalidaMemoria());
            }
    }

    // ------------------------------------------------------------------ administrador de pruebas
    /// <summary>
    /// Crea o deja al día el administrador de pruebas (local@local.test / local) en los WordPress y la tienda
    /// PrestaShop de la base. Devuelve los que hay (wp, ps) y los anuncia como resultado A|tipo|usuario|clave.
    /// </summary>
    public List<string> TestAdmin(ClienteMariaDb c, string db, string? folder, ISalida o)
    {
        var done = new List<string>();
        bool HasTable(string t) => c.Scalar(Sql.IsBaseTable(db, t)) == "1";
        foreach (var row in c.Rows(Sql.WpPrefixes(db)))
        {
            var p = row[0];
            if (p.Length > 0 && !Sql.IsIdent(p)) continue;
            if (!HasTable(p + "usermeta")) continue;
            var r = c.Run(Sql.WpTestAdmin(p), db);
            var last = r.Output.Replace("\r\n", "\n").Split('\n').LastOrDefault(l => l.Length > 0);
            if (r.ExitCode == 0 && long.TryParse(last, out var id) && id > 0 && !done.Contains("wp"))
            {
                done.Add("wp");
                o.Result("A", $"wp|{Sql.TestAdminUser}|{Sql.TestAdminPass}");
            }
        }
        var prefix = c.Scalar(Sql.PsPrefix(db, "")) ?? "";
        if (prefix.Length > 0 && !Sql.IsIdent(prefix)) prefix = "";
        if (HasTable(prefix + "employee") && HasTable(prefix + "employee_shop") && HasTable(prefix + "shop") && HasTable(prefix + "shop_url"))
        {
            var src = c.Scalar(Sql.PsSuperAdminPassword(prefix), db);
            string? hash = null;
            if (src != null && src.StartsWith('$'))
                hash = Sql.TestAdminBcrypt;
            else if (!string.IsNullOrEmpty(src))
            {
                var key = folder != null && Validacion.IsProjectFolder(folder) ? PrestaShop.CookieKey(Path.Combine(L.Htdocs, folder)) : null;
                if (key != null) hash = Sql.Ps16Hash(key);
                else o.Line("Aviso: no se sabe la _COOKIE_KEY_ de la tienda (PrestaShop 1.6): sin administrador de pruebas. Cárgala con su carpeta (Cargar proyecto).");
            }
            if (hash != null)
            {
                var cols = c.Rows(Sql.Columns(db, prefix + "employee")).Select(r => r[0]).ToList();
                var sql = Sql.PsTestAdmin(prefix, cols, hash);
                if (sql != null)
                {
                    var r = c.Run(sql, db);
                    var last = r.Output.Replace("\r\n", "\n").Split('\n').LastOrDefault(l => l.Length > 0);
                    if (r.ExitCode == 0 && long.TryParse(last, out var id) && id > 0)
                    {
                        done.Add("ps");
                        o.Result("A", $"ps|{Sql.TestAdminUser}|{Sql.TestAdminPass}");
                    }
                }
            }
        }
        return done;
    }

    /// <summary>usuario-pruebas &lt;base&gt; [carpeta]: en la versión activa.</summary>
    public List<string> TestAdmin(string db, string? folder, ISalida o)
    {
        if (Validacion.DbNameProblem(db) is { } p) throw new NexumException(p);
        var (_, c) = ActiveDb();
        if (!Exists(c, db))
            throw new NexumException($"No hay ninguna base de datos {db} en la versión activa");
        var done = TestAdmin(c, db, folder ?? Links.LinkOf(db, Active!), o);
        if (done.Count == 0)
            throw new NexumException($"{db} no es de un WordPress ni de una tienda PrestaShop: sin administrador de pruebas.");
        return done;
    }

    // ------------------------------------------------------------------ copiar entre versiones
    /// <summary>
    /// Copia una BBDD a otra versión (para probar el proyecto con otro PHP); la de origen no se toca. Con
    /// <paramref name="newName"/>, con otro nombre; con <paramref name="link"/>, la vincula allí a esa carpeta ("-":
    /// a ninguna). Si la de destino ya la tiene, solo con <paramref name="replace"/> (antes, copia en nexum-copias).
    /// </summary>
    public void CopyDatabase(string db, string from, string to, string? newName, string? link, bool replace, ISalida o)
    {
        var src = Require(from);
        var dst = Require(to);
        newName ??= db;
        if (Validacion.DbNameProblem(db) is { } p1) throw new NexumException(p1);
        if (Validacion.DbNameProblem(newName) is { } p2) throw new NexumException(p2);
        if (link != null && link != "-" && link.Length > 0 && !Directory.Exists(Path.Combine(L.Htdocs, link)))
            throw new NexumException($"No existe el proyecto {Path.Combine(L.Htdocs, link)}");
        if (src.Folder == dst.Folder)
            throw new NexumException("La versión de origen y la de destino son la misma.");
        if (!Databases(src.Folder).Any(x => x.Name == db))
            throw new NexumException($"No hay ninguna BBDD {db} en {src.Folder}");
        var exists = Databases(dst.Folder).Any(x => x.Name == newName);
        if (exists && !replace)
            throw new NexumException($"{dst.Folder} ya tiene una BBDD {newName}: no se toca (con --sustituir se guarda una copia suya en {L.CopiesDir} y se pone la de {src.Folder} en su lugar; o cópiala con otro nombre: --como)");
        var shown = newName != db ? $"{db} (como {newName})" : db;
        o.Line($"Copia de la BBDD {shown}: de {src.Folder} a {dst.Folder} ({src.Folder} no se toca)");
        if (exists)
        {
            var backup = Path.Combine(Ficheros.EnsureDir(L.CopiesDir), $"{dst.Folder}-{newName}-antes-de-copiar-{Ficheros.Stamp()}.sql.gz");
            o.Line($"{dst.Folder} ya tiene {newName}: antes se guarda una copia suya en {backup}");
            ExportDatabase(newName, backup, dst.Folder, o);
        }
        Directory.CreateDirectory(L.UserDir);
        var tmp = Path.Combine(L.UserDir, $"copia-{db}-{Guid.NewGuid():N}.sql.gz");
        try
        {
            ExportDatabase(db, tmp, src.Folder, o);
            WithServer(dst.Folder, o, client =>
                ImportDatabase(tmp, newName, create: true, backup: false, project: null, o, (dst.Folder, client)));
        }
        finally
        {
            TryDelete(tmp);
        }
        if (link == "-")
        {
            Links.Remember(newName, "", dst.Folder);
            o.Line($"{newName} no queda vinculada a ningún proyecto en {dst.Folder} (vincúlala en Proyectos).");
        }
        else if (!string.IsNullOrEmpty(link))
        {
            Links.Remember(newName, link, dst.Folder);
            o.Line($"{newName} queda vinculada al proyecto {link} en {dst.Folder}.");
        }
        o.Line($"{newName} está ahora en {dst.Folder}. Para probar el proyecto con PHP {dst.Php}, cárgalo con esa versión.");
    }
}
