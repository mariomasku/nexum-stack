using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using NexumDevStack.Core.BaseDatos;
using NexumDevStack.Core.Tareas;
using Xunit;

namespace NexumDevStack.Core.Tests;

public class FiltroVolcadoTests
{
    static string Run(string input)
    {
        using var i = new MemoryStream(Encoding.Latin1.GetBytes(input));
        using var o = new MemoryStream();
        FiltroVolcado.Copy(i, o, CancellationToken.None);
        return Encoding.Latin1.GetString(o.ToArray());
    }

    [Fact]
    public void QuitaLaLineaDelModoSandboxSoloAlPrincipio()
    {
        var sandbox = "/*M!999999\\- enable the sandbox mode */ \n";
        Assert.Equal("SELECT 1;\n", Run(sandbox + "SELECT 1;\n"));
        Assert.Equal("SELECT 1;\n" + sandbox, Run("SELECT 1;\n" + sandbox));
    }

    [Fact]
    public void QuitaLosDefiner()
    {
        var t = Run("/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */\nCREATE DEFINER=`u`@`%` TRIGGER x\n");
        Assert.DoesNotContain("DEFINER=`", t);
        Assert.Contains("SQL SECURITY DEFINER", t);
    }

    [Theory]
    [InlineData("SQL SECURITY INVOKER", "SQL SECURITY DEFINER")]
    [InlineData("sql security invoker", "sql security definer")]
    [InlineData("SQL SECURITY Invoker */", "SQL SECURITY Definer */")]
    [InlineData("/*!50013 INVOKER */", "/*!50013 DEFINER */")]
    [InlineData("INSERT INTO t VALUES ('invoker_id')", "INSERT INTO t VALUES ('invoker_id')")]
    [InlineData("$invoker = 1", "$invoker = 1")]
    [InlineData("php-di/invoker", "php-di/invoker")]
    [InlineData("Vendor\\Invoker", "Vendor\\Invoker")]
    [InlineData("x.invoker", "x.invoker")]
    [InlineData("@invoker", "@invoker")]
    public void InvokerPasaADefiner(string input, string expected) => Assert.Equal(expected + "\n", Run(input + "\n"));

    [Fact]
    public void NoCambiaNingunByte()
    {
        var bytes = new byte[300_000];
        new Random(1).NextBytes(bytes);
        // (sin la primera línea del sandbox ni DEFINER/INVOKER: sale igual)
        bytes[0] = (byte)'A';
        var text = Encoding.Latin1.GetString(bytes).Replace("DEFINER", "xxxxxxx").Replace("nvoker", "nvokxr").Replace("NVOKER", "NVOKXR")
            .Replace("nVoker", "x").Replace("INVOKER", "x");
        var input = Encoding.Latin1.GetBytes(text);
        using var i = new MemoryStream(input);
        using var o = new MemoryStream();
        FiltroVolcado.Copy(i, o, CancellationToken.None);
        Assert.Equal(SHA256.HashData(input), SHA256.HashData(o.ToArray()));
    }

    [Fact]
    public void LineasLargas()
    {
        var big = "INSERT INTO t VALUES " + string.Concat(Enumerable.Repeat("('x'),", 400_000)) + "('y');";
        Assert.Equal(big + "\n", Run(big + "\n"));
        Assert.Equal("sin salto", Run("sin salto"));
    }

    [Fact]
    public void SeCancela()
    {
        using var cts = new CancellationTokenSource();
        cts.Cancel();
        using var i = new MemoryStream(Encoding.ASCII.GetBytes("a\nb\n"));
        Assert.Throws<OperationCanceledException>(() => FiltroVolcado.Copy(i, new MemoryStream(), cts.Token));
    }
}

public class VolcadoTests
{
    static string Temp(string ext) => Path.Combine(Path.GetTempPath(), "nexum-volcado-" + Guid.NewGuid().ToString("N") + ext);

    static string ReadAll(Volcado v) => new StreamReader(v.Content).ReadToEnd();

    [Fact]
    public void SqlGzYZip()
    {
        var sql = Temp(".sql");
        File.WriteAllText(sql, "/*M!999999\\- enable the sandbox mode */\nSELECT 1;\n");
        var gz = Temp(".sql.gz");
        using (var f = File.Create(gz))
        using (var g = new GZipStream(f, CompressionLevel.Fastest))
            g.Write(Encoding.ASCII.GetBytes("SELECT 2;\n"));
        var zip = Temp(".zip");
        using (var z = ZipFile.Open(zip, ZipArchiveMode.Create))
        {
            z.CreateEntry("__MACOSX/._copia.sql");
            using var w = new StreamWriter(z.CreateEntry("copia.sql").Open());
            w.Write("SELECT 3;\n");
        }
        try
        {
            using (var v = Volcado.Open(sql)) { Assert.Equal("sql", v.Kind); Assert.Contains("SELECT 1", ReadAll(v)); }
            using (var v = Volcado.Open(gz)) { Assert.Equal("gz", v.Kind); Assert.Equal("SELECT 2;\n", ReadAll(v)); }
            using (var v = Volcado.Open(zip)) { Assert.Equal(("zip", "copia.sql"), (v.Kind, v.Inner)); Assert.Equal("SELECT 3;\n", ReadAll(v)); Assert.Equal(v.InnerSize, v.Position().Done); }
            Assert.True(Volcado.StartsWithSandbox(sql));
            Assert.False(Volcado.StartsWithSandbox(gz));
        }
        finally
        {
            File.Delete(sql); File.Delete(gz); File.Delete(zip);
        }
    }

    [Fact]
    public void ZipsQueNoValen()
    {
        var two = Temp(".zip");
        using (var z = ZipFile.Open(two, ZipArchiveMode.Create))
        {
            z.CreateEntry("a.sql");
            z.CreateEntry("b.sql");
        }
        var none = Temp(".zip");
        using (var z = ZipFile.Open(none, ZipArchiveMode.Create))
            z.CreateEntry("leeme.txt");
        var fake = Temp(".zip");
        File.WriteAllText(fake, "no soy un zip");
        try
        {
            Assert.Contains("varios .sql", Assert.Throws<NexumException>(() => Volcado.Open(two)).Message);
            Assert.Contains("ningun fichero .sql", Assert.Throws<NexumException>(() => Volcado.Open(none)).Message);
            Assert.Contains("no es un .zip", Assert.Throws<NexumException>(() => Volcado.Open(fake)).Message);
        }
        finally
        {
            File.Delete(two); File.Delete(none); File.Delete(fake);
        }
    }
}

public class SqlTests
{
    [Fact]
    public void AdministradorDePruebasDeWordPress()
    {
        var sql = Sql.WpTestAdmin("wpx_");
        Assert.Contains("INSERT INTO `wpx_users`", sql);
        Assert.Contains("'a:1:{s:13:\"administrator\";b:1;}'", sql);
        Assert.Contains("'wpx_capabilities'", sql);
        Assert.Contains("MD5('local')", sql);
        Assert.Throws<ArgumentException>(() => Sql.WpTestAdmin("x`; DROP"));
    }

    [Fact]
    public void AdministradorDePruebasDePrestaShop()
    {
        var cols = new[] { "id_employee", "id_profile", "lastname", "firstname", "email", "passwd", "last_passwd_gen", "active", "id_lang" };
        var sql = Sql.PsTestAdmin("ps_", cols, Sql.TestAdminBcrypt)!;
        Assert.Contains("INSERT INTO `ps_employee` (`id_profile`, `lastname`, `firstname`, `email`, `passwd`, `last_passwd_gen`, `active`, `id_lang`)", sql);
        Assert.Contains("SELECT 1, 'Local', 'Pruebas', 'local@local.test', '$2y$12$", sql);
        Assert.Contains("`id_lang` FROM `ps_employee` WHERE id_employee = @src", sql);
        Assert.Null(Sql.PsTestAdmin("ps_", new[] { "rara columna" }, Sql.TestAdminBcrypt));
        Assert.Null(Sql.PsTestAdmin("ps_", cols, "x'y"));
        Assert.Equal(32, Sql.Ps16Hash("CLAVE").Length);
    }

    [Fact]
    public void HuellaDeContrasena() =>
        // mysql_native_password de «local» (como PASSWORD('local') en MariaDB)
        Assert.Equal("*" + Convert.ToHexString(SHA1.HashData(SHA1.HashData(Encoding.UTF8.GetBytes("local")))), Sql.NativeHash("local"));

    [Fact]
    public void PermisosDelUsuarioDeLaBase()
    {
        var sql = Sql.PrepareImportUser("wp_tienda", "*ABC");
        Assert.Contains("'nexum_bd_wp_tienda'@'localhost'", sql);
        Assert.Contains("ON `wp\\_tienda`.*", sql);
        var lockSql = Sql.LockImportUser("nexum_bd_wp_tienda", "Zz9");
        Assert.Contains("ACCOUNT LOCK", lockSql);
        Assert.Contains("REVOKE CREATE VIEW, CREATE ROUTINE, ALTER ROUTINE, EVENT ON `wp\\_tienda`.*", lockSql);
        Assert.Throws<ArgumentException>(() => Sql.LockImportUser("root", "x"));
        Assert.Throws<ArgumentException>(() => Sql.KillUser("root"));
        Assert.Throws<ArgumentException>(() => Sql.Exists("x'; DROP DATABASE y; --"));
    }

    [Fact]
    public void TablasConDataDirectory()
    {
        var output = "mala\tCREATE TABLE `mala` (\\n  `id` int\\n) ENGINE=InnoDB DATA DIRECTORY='C:\\\\\\\\Windows'\n" +
                     "buena\tCREATE TABLE `buena` (\\n  `c` varchar(10) DEFAULT 'DATA DIRECTORY=x'\\n) COMMENT='index directory = \\'y\\''\n" +
                     "rara`x\tCREATE TABLE `rara``x` (`a` int) /*!50100 PARTITION BY HASH (a) */ INDEX DIRECTORY = 'C:/tmp'\n";
        var drops = Sql.DirectoryDrops(output);
        Assert.Equal(new[] { "DROP TABLE IF EXISTS `mala`;", "DROP TABLE IF EXISTS `rara``x`;" }, drops);
        Assert.Equal(new[] { "DROP TABLE IF EXISTS `base`.`mala`;", "DROP TABLE IF EXISTS `base`.`rara``x`;" },
            Sql.DirectoryDrops(output, "base"));
    }

    [Fact]
    public void NombresParaUnAviso() => Assert.Equal("vista v1, funcion f?x", Sql.NamesForWarning("vista v1\nfuncion f\u001bx\n"));
}

public class ListaBbddTests
{
    [Fact]
    public void LeeLaCarpetaDeDatos()
    {
        using var e = new Entorno();
        var data = e.L.DataDir("php-8.4.27");
        foreach (var d in new[] { "mysql", "performance_schema", "phpmyadmin", "sys", "wp_tienda", "wp_mi@002dweb", "raro@007cx", "#innodb_temp" })
            Directory.CreateDirectory(Path.Combine(data, d));
        var list = ListaBbdd.FromDataDir(data, e.L.ImportsFile);
        Assert.Equal(new[] { "wp_mi-web", "wp_tienda" }, list.Select(x => x.Name));
        Assert.All(list, x => Assert.Equal('c', x.Kind));
        ListaBbdd.NoteImport(e.L.ImportsFile, data, "wp_tienda", 1700000000);
        var again = ListaBbdd.FromDataDir(data, e.L.ImportsFile);
        Assert.Equal(('i', 1700000000L), (again[1].Kind, again[1].When));
        ListaBbdd.NoteImport(e.L.ImportsFile, data, "wp_tienda", null);
        Assert.Equal('c', ListaBbdd.FromDataDir(data, e.L.ImportsFile)[1].Kind);
    }
}
