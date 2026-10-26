using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.BaseDatos;

/// <summary>
/// Las sentencias SQL del programa (las mismas que en Linux). Lo que va dentro de ellas son siempre nombres
/// ya comprobados (bases, prefijos y columnas de letras, números y _).
/// </summary>
public static class Sql
{
    public static bool IsIdent(string s) => Regex.IsMatch(s, "^[A-Za-z0-9_]+$");

    public static string Exists(string db) =>
        $"SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='{Check(db)}'";

    public static string CreateDb(string db) =>
        $"CREATE DATABASE `{Check(db)}` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci";

    public static string DropDb(string db) => $"DROP DATABASE `{Check(db)}`";

    public static string Info(string db) =>
        $"SELECT COUNT(*), COALESCE(SUM(DATA_LENGTH + INDEX_LENGTH), 0) FROM information_schema.TABLES WHERE TABLE_SCHEMA='{Check(db)}'";

    public const string Sizes =
        "SELECT table_schema, SUM(data_length + index_length) FROM information_schema.tables GROUP BY table_schema";

    public static string Tables(string db) => $"SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='{Check(db)}'";

    public static string Charset(string db) =>
        $"SELECT CONCAT(DEFAULT_CHARACTER_SET_NAME, ' COLLATE ', DEFAULT_COLLATION_NAME) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='{Check(db)}'";

    /// <summary>¿Es <paramref name="table"/> de <paramref name="db"/> una tabla de verdad (no una vista)?</summary>
    public static string IsBaseTable(string db, string table) =>
        $"SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='{Check(db)}' AND TABLE_NAME='{CheckIdent(table)}' AND TABLE_TYPE='BASE TABLE'";

    /// <summary>Motores con los que una tabla del volcado podría conectarse a este mismo MariaDB.</summary>
    public const string DangerousEngines =
        "SELECT GROUP_CONCAT(ENGINE) FROM information_schema.ENGINES WHERE ENGINE IN ('FEDERATED', 'CONNECT', 'SPIDER', 'OQGRAPH') AND SUPPORT IN ('YES', 'DEFAULT')";

    public static string Check(string db)
    {
        if (!Validacion.IsDbName(db))
            throw new ArgumentException("Nombre de base no válido: " + db);
        return db;
    }

    static string CheckIdent(string s)
    {
        if (!IsIdent(s) && !Validacion.IsDbName(s))
            throw new ArgumentException("Nombre no válido: " + s);
        return s;
    }

    // ------------------------------------------------------------------ WordPress y PrestaShop
    /// <summary>Prefijos de los WordPress de una base: los de sus tablas &lt;prefijo&gt;options con &lt;prefijo&gt;users.</summary>
    public static string WpPrefixes(string db) =>
        $"SELECT LEFT(TABLE_NAME, LENGTH(TABLE_NAME) - 7) AS p FROM information_schema.TABLES WHERE TABLE_SCHEMA='{Check(db)}' " +
        $"AND TABLE_TYPE='BASE TABLE' AND TABLE_NAME LIKE '%options' AND CONCAT(LEFT(TABLE_NAME, LENGTH(TABLE_NAME) - 7), 'users') " +
        $"IN (SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='{db}' AND TABLE_TYPE='BASE TABLE') ORDER BY LENGTH(p)";

    /// <summary>Prefijo de una tienda: el de su tabla &lt;prefijo&gt;shop_url (el preferido si lo tiene; si no, el más corto).</summary>
    public static string PsPrefix(string db, string preferred)
    {
        if (!IsIdent(preferred)) preferred = "";
        return $"SELECT LEFT(TABLE_NAME, LENGTH(TABLE_NAME) - 8) FROM information_schema.TABLES WHERE TABLE_SCHEMA='{Check(db)}' " +
               $"AND TABLE_TYPE='BASE TABLE' AND TABLE_NAME LIKE '%shop\\_url' ORDER BY TABLE_NAME = '{preferred}shop_url' DESC, LENGTH(TABLE_NAME) LIMIT 1";
    }

    /// <summary>Dominio de la tienda principal (al que redirige PrestaShop).</summary>
    public static string PsDomain(string db, string prefix) =>
        $"SELECT domain FROM `{Check(db)}`.`{CheckPrefix(prefix)}shop_url` ORDER BY main DESC, active DESC, id_shop_url LIMIT 1";

    static string CheckPrefix(string p)
    {
        if (p.Length > 0 && !IsIdent(p))
            throw new ArgumentException("Prefijo no válido");
        return p;
    }

    public const string TestAdminUser = "local@local.test";
    public const string TestAdminPass = "local";

    /// <summary>Huella bcrypt de «local» (PrestaShop 1.7 o posterior).</summary>
    public const string TestAdminBcrypt = "$2y$12$IqVkFsJq4UhjbzLfagfW9eU5V6iIauQCbfMJDY26MoM8ETz6ZKgxG";

    /// <summary>Administrador de pruebas en un WordPress (prefijo de sus tablas). La última fila: su ID (0 si no).</summary>
    public static string WpTestAdmin(string prefix)
    {
        var p = CheckPrefix(prefix);
        return $"""
SET @id := (SELECT ID FROM `{p}users` WHERE user_login = 'local@local.test' ORDER BY ID LIMIT 1);
INSERT INTO `{p}users` (user_login, user_pass, user_nicename, user_email, user_url, user_registered, user_activation_key, user_status, display_name)
    SELECT 'local@local.test', MD5('local'), 'local-pruebas', 'local@local.test', '', NOW(), '', 0, 'Local (pruebas)' FROM DUAL WHERE @id IS NULL;
SET @id := IFNULL(@id, LAST_INSERT_ID());
UPDATE `{p}users` SET user_pass = MD5('local'), user_activation_key = '' WHERE ID = @id;
DELETE FROM `{p}usermeta` WHERE user_id = @id AND meta_key IN ('{p}capabilities', '{p}user_level');
INSERT INTO `{p}usermeta` (user_id, meta_key, meta_value) SELECT @id, '{p}capabilities', 'a:1:{"{"}s:13:"administrator";b:1;{"}"}' FROM DUAL WHERE @id > 0;
INSERT INTO `{p}usermeta` (user_id, meta_key, meta_value) SELECT @id, '{p}user_level', '10' FROM DUAL WHERE @id > 0;
SELECT CAST(IFNULL(@id, 0) AS UNSIGNED);
""";
    }

    public static string PsSuperAdminPassword(string prefix) =>
        $"SELECT passwd FROM `{CheckPrefix(prefix)}employee` WHERE id_profile = 1 ORDER BY active DESC, id_employee LIMIT 1";

    public static string Columns(string db, string table) =>
        $"SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='{Check(db)}' AND TABLE_NAME='{CheckIdent(table)}' ORDER BY ORDINAL_POSITION";

    /// <summary>
    /// Administrador de pruebas en una tienda: una copia del primer SuperAdmin (mismas columnas, sea cual sea
    /// la versión) con el correo y la contraseña de pruebas, en todas las tiendas. null si las columnas no valen.
    /// </summary>
    public static string? PsTestAdmin(string prefix, IReadOnlyList<string> columns, string hash)
    {
        var p = CheckPrefix(prefix);
        if (columns.Count == 0 || columns.Any(c => !IsIdent(c)) || hash.Contains('\'') || hash.Contains('\\'))
            return null;
        var list = new List<string>();
        var sel = new List<string>();
        foreach (var col in columns)
        {
            string expr;
            switch (col)
            {
                case "id_employee": continue;
                case "email": expr = "'local@local.test'"; break;
                case "passwd": expr = $"'{hash}'"; break;
                case "firstname": expr = "'Pruebas'"; break;
                case "lastname": expr = "'Local'"; break;
                case "active" or "id_profile": expr = "1"; break;
                case "last_passwd_gen": expr = "NOW()"; break;
                case "reset_password_token" or "reset_password_validity": expr = "NULL"; break;
                default: expr = $"`{col}`"; break;
            }
            list.Add($"`{col}`");
            sel.Add(expr);
        }
        return $"""
SET @src := (SELECT id_employee FROM `{p}employee` WHERE id_profile = 1 ORDER BY active DESC, id_employee LIMIT 1);
SET @id := (SELECT id_employee FROM `{p}employee` WHERE email = 'local@local.test' ORDER BY id_employee LIMIT 1);
INSERT INTO `{p}employee` ({string.Join(", ", list)}) SELECT {string.Join(", ", sel)} FROM `{p}employee` WHERE id_employee = @src AND @id IS NULL;
SET @id := IFNULL(@id, LAST_INSERT_ID());
UPDATE `{p}employee` SET passwd = '{hash}', active = 1, id_profile = 1 WHERE id_employee = @id AND @src IS NOT NULL;
INSERT IGNORE INTO `{p}employee_shop` (id_employee, id_shop) SELECT @id, id_shop FROM `{p}shop` WHERE @id > 0 AND @src IS NOT NULL;
SELECT CAST(IF(@src IS NULL, 0, @id) AS UNSIGNED);
""";
    }

    /// <summary>Contraseña de pruebas para PrestaShop 1.6: md5(_COOKIE_KEY_ + contraseña).</summary>
    public static string Ps16Hash(string cookieKey) =>
        Convert.ToHexString(MD5.HashData(Encoding.UTF8.GetBytes(cookieKey + TestAdminPass))).ToLowerInvariant();

    /// <summary>Tablas con el administrador de pruebas (para dejarlo fuera de las copias).</summary>
    public static string TestAdminTables(string db) =>
        $"SELECT c.TABLE_NAME, c.COLUMN_NAME FROM information_schema.COLUMNS c JOIN information_schema.TABLES t " +
        $"ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME WHERE c.TABLE_SCHEMA = '{Check(db)}' " +
        "AND t.TABLE_TYPE = 'BASE TABLE' AND ((c.TABLE_NAME LIKE '%users' AND c.COLUMN_NAME = 'user_login') " +
        "OR (c.TABLE_NAME LIKE '%employee' AND c.COLUMN_NAME = 'email'))";

    // ------------------------------------------------------------------ carga protegida
    /// <summary>Huella mysql_native_password de una contraseña: *SHA1(SHA1(clave)) en mayúsculas.</summary>
    public static string NativeHash(string password) =>
        "*" + Convert.ToHexString(SHA1.HashData(SHA1.HashData(Encoding.UTF8.GetBytes(password))));

    public static string ImportUser(string db) => "nexum_bd_" + Check(db);

    /// <summary>La base con el _ escapado para los permisos (si no, wp_x valdría también para wpYx).</summary>
    public static string GrantDb(string db) => Check(db).Replace("_", "\\_");

    public static string PrepareImportUser(string db, string hash) =>
        $"CREATE USER IF NOT EXISTS '{ImportUser(db)}'@'localhost' IDENTIFIED BY PASSWORD '{hash}'; " +
        $"ALTER USER '{ImportUser(db)}'@'localhost' IDENTIFIED BY PASSWORD '{hash}' ACCOUNT UNLOCK; " +
        $"GRANT ALL PRIVILEGES ON `{GrantDb(db)}`.* TO '{ImportUser(db)}'@'localhost'";

    /// <summary>Bloquea el usuario de la base: ya no puede entrar, pero lo suyo (vistas, disparadores) sigue funcionando.</summary>
    public static string LockImportUser(string user, string password)
    {
        if (!Regex.IsMatch(user, "^nexum_bd_[A-Za-z0-9_-]+$") || password.Contains('\''))
            throw new ArgumentException("Usuario no válido");
        var gdb = user["nexum_bd_".Length..].Replace("_", "\\_");
        return $"DROP USER IF EXISTS '{user}'@'localhost'; " +
               $"CREATE USER '{user}'@'localhost' IDENTIFIED BY '{password}' ACCOUNT LOCK; " +
               $"GRANT ALL PRIVILEGES ON `{gdb}`.* TO '{user}'@'localhost'; " +
               $"REVOKE CREATE VIEW, CREATE ROUTINE, ALTER ROUTINE, EVENT ON `{gdb}`.* FROM '{user}'@'localhost'";
    }

    public static string KillUser(string user) =>
        Regex.IsMatch(user, "^nexum_bd_[A-Za-z0-9_-]+$") ? $"KILL USER '{user}'@'localhost'" : throw new ArgumentException("Usuario no válido");

    /// <summary>Usuarios de bases que han quedado sin bloquear (una carga que no terminó).</summary>
    public const string OpenImportUsers =
        "SELECT User FROM mysql.global_priv WHERE User LIKE 'nexum\\_bd\\_%' AND Host='localhost' " +
        "AND IFNULL(JSON_VALUE(Priv, '$.account_locked'), 'false') <> 'true'";

    const string ViewsInvoker = "FROM information_schema.VIEWS WHERE TABLE_SCHEMA = DATABASE() AND SECURITY_TYPE = 'INVOKER'";
    const string RoutinesInvoker = "FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND SECURITY_TYPE = 'INVOKER'";

    /// <summary>Genera los ALTER que pasan vistas y rutinas INVOKER a DEFINER (lo ejecuta el usuario de la base).</summary>
    public const string InvokerToDefiner =
        "SELECT CONCAT('ALTER SQL SECURITY DEFINER VIEW `', REPLACE(TABLE_NAME, '`', '``'), '` AS ', VIEW_DEFINITION, ';') " + ViewsInvoker + "; " +
        "SELECT CONCAT('ALTER ', ROUTINE_TYPE, ' `', REPLACE(ROUTINE_NAME, '`', '``'), '` SQL SECURITY DEFINER;') " + RoutinesInvoker;

    public const string InvokerLeft =
        "SELECT CONCAT('vista ', TABLE_NAME) " + ViewsInvoker + "; SELECT CONCAT(LOWER(ROUTINE_TYPE), ' ', ROUTINE_NAME) " + RoutinesInvoker;

    public const string InvokerDrop =
        "SELECT CONCAT('DROP VIEW IF EXISTS `', REPLACE(TABLE_NAME, '`', '``'), '`;') " + ViewsInvoker + "; " +
        "SELECT CONCAT('DROP ', ROUTINE_TYPE, ' IF EXISTS `', REPLACE(ROUTINE_NAME, '`', '``'), '`;') " + RoutinesInvoker;

    const string Events = "FROM information_schema.EVENTS WHERE EVENT_SCHEMA = DATABASE()";
    public const string EventNames = "SELECT EVENT_NAME " + Events;
    public const string EventDrop = "SELECT CONCAT('DROP EVENT IF EXISTS `', REPLACE(EVENT_NAME, '`', '``'), '`;') " + Events;

    const string BaseTables = "FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE'";
    public const string DirectoryTablesDrop =
        "SELECT CONCAT('DROP TABLE IF EXISTS `', REPLACE(TABLE_NAME, '`', '``'), '`;') " + BaseTables + " AND CREATE_OPTIONS LIKE '%DIRECTORY%'";
    public const string PartitionedShowCreate =
        "SELECT CONCAT('SHOW CREATE TABLE `', REPLACE(TABLE_NAME, '`', '``'), '`;') " + BaseTables + " AND CREATE_OPTIONS LIKE '%partitioned%'";
    public const string DirectoryLeft = "SELECT 1 " + BaseTables + " AND CREATE_OPTIONS LIKE '%DIRECTORY%' LIMIT 1";

    /// <summary>Repaso de root al final de una carga: lo que no debe quedar (solo DROP: nunca se ejecuta nada).</summary>
    public static string RootCleanup(string db)
    {
        var d = Check(db);
        var w = $"TABLE_SCHEMA = '{d}'";
        return $"SELECT CONCAT('DROP VIEW IF EXISTS `{d}`.`', REPLACE(TABLE_NAME, '`', '``'), '`;') FROM information_schema.VIEWS WHERE {w} AND SECURITY_TYPE = 'INVOKER'; " +
               $"SELECT CONCAT(IF(ROUTINE_TYPE LIKE 'PACKAGE%', 'SET sql_mode = ORACLE; ', ''), 'DROP ', ROUTINE_TYPE, ' IF EXISTS `{d}`.`', REPLACE(ROUTINE_NAME, '`', '``'), '`; SET sql_mode = DEFAULT;') " +
               $"FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = '{d}' AND SECURITY_TYPE = 'INVOKER' ORDER BY ROUTINE_TYPE = 'PACKAGE'; " +
               $"SELECT CONCAT('DROP EVENT IF EXISTS `{d}`.`', REPLACE(EVENT_NAME, '`', '``'), '`;') FROM information_schema.EVENTS WHERE EVENT_SCHEMA = '{d}'; " +
               $"SELECT CONCAT('DROP TABLE IF EXISTS `{d}`.`', REPLACE(TABLE_NAME, '`', '``'), '`;') FROM information_schema.TABLES WHERE {w} AND TABLE_TYPE = 'BASE TABLE' AND CREATE_OPTIONS LIKE '%DIRECTORY%'";
    }

    public static string RootCleanupLeft(string db)
    {
        var d = Check(db);
        return $"SELECT CONCAT('vista ', TABLE_NAME) FROM information_schema.VIEWS WHERE TABLE_SCHEMA = '{d}' AND SECURITY_TYPE = 'INVOKER'; " +
               $"SELECT CONCAT(LOWER(ROUTINE_TYPE), ' ', ROUTINE_NAME) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = '{d}' AND SECURITY_TYPE = 'INVOKER'; " +
               $"SELECT CONCAT('evento ', EVENT_NAME) FROM information_schema.EVENTS WHERE EVENT_SCHEMA = '{d}'";
    }

    public static string PartitionedShowCreateRoot(string db) =>
        $"SELECT CONCAT('SHOW CREATE TABLE `{Check(db)}`.`', REPLACE(TABLE_NAME, '`', '``'), '`;') FROM information_schema.TABLES " +
        $"WHERE TABLE_SCHEMA = '{db}' AND TABLE_TYPE = 'BASE TABLE' AND CREATE_OPTIONS LIKE '%partitioned%'";

    /// <summary>
    /// De la salida de SHOW CREATE TABLE con -N --batch (nombre&lt;TAB&gt;sentencia, con \n \t \\ escapados), los
    /// DROP de las tablas con DATA DIRECTORY o INDEX DIRECTORY de verdad (no un COMMENT ni un DEFAULT que lo diga).
    /// </summary>
    public static List<string> DirectoryDrops(string showCreateOutput, string? dbPrefix = null)
    {
        static string Unescape(string s) => Regex.Replace(s, @"\\(.)", m => m.Groups[1].Value switch
        {
            "n" => "\n", "t" => "\t", "0" => "\0", var x => x,
        });
        static string Options(string sql)
        {
            sql = Regex.Replace(sql, @"'(?:[^'\\]|\\.|'')*'", " Q ");
            sql = Regex.Replace(sql, @"`(?:[^`]|``)*`", " I ");
            return Regex.Replace(sql, @"/\*.*?\*/", " ", RegexOptions.Singleline);
        }
        var drops = new SortedSet<string>(StringComparer.Ordinal);
        foreach (var line in showCreateOutput.Replace("\r\n", "\n").Split('\n'))
        {
            var tab = line.IndexOf('\t');
            if (tab < 0) continue;
            var name = Unescape(line[..tab]);
            var create = Unescape(line[(tab + 1)..]);
            if (Regex.IsMatch(Options(create), @"\b(DATA|INDEX)\s+DIRECTORY\s*=?\s*Q", RegexOptions.IgnoreCase))
                drops.Add($"DROP TABLE IF EXISTS {(dbPrefix != null ? $"`{dbPrefix}`." : "")}`{name.Replace("`", "``")}`;");
        }
        return drops.ToList();
    }

    /// <summary>Lista de nombres para un aviso: sin caracteres raros, hasta 20, separados por comas.</summary>
    public static string NamesForWarning(string output, int max = 20) =>
        string.Join(", ", output.Replace("\r\n", "\n").Split('\n').Where(l => l.Length > 0).Take(max)
            .Select(l => Regex.Replace(l, @"[^\p{L}\p{N}_ \-.()]", "?")));
}
