using NexumDevStack.Core.Proyectos;
using Xunit;

namespace NexumDevStack.Core.Tests;

public class EscanerTests
{
    [Fact]
    public void ReconoceWordPressYPrestaShop()
    {
        using var e = new Entorno();
        e.Project("dob-wordpress-tienda", ("wp-config.php", "<?php\ndefine( 'DB_NAME', 'wp_tienda' );\n"));
        e.Project("tienda17", ("app/config/parameters.php", "<?php return array ('parameters' => array ('database_name' => 'ps_tienda17', 'database_prefix' => 'ps_'));"));
        e.Project("tienda16", ("config/settings.inc.php", "<?php\ndefine('_DB_NAME_', 'ps16');\ndefine('_DB_PREFIX_', 'ps_');\n"));
        e.Project("laravel", (".env", "APP_NAME=x\nDB_DATABASE=\"lara_db\"\n"), (".php-version", "8.3\n"));
        e.Project("rara", ("wp-config.php", "<?php\ndefine('DB_NAME', 'nombre; DROP');\n"));
        e.Project(".oculta");
        var list = Escaner.Scan(e.L.Htdocs);
        Assert.Equal(new[] { "dob-wordpress-tienda", "laravel", "rara", "tienda16", "tienda17" }, list.Select(x => x.Name));
        var wp = list[0];
        Assert.Equal(("wp_tienda", "wp"), (wp.Db, wp.Kind));
        Assert.Equal(("lara_db", "8.3", ""), (list[1].Db, list[1].PhpVersion, list[1].Kind));
        Assert.Equal("", list[2].Db);
        Assert.Equal(("ps16", "ps"), (list[3].Db, list[3].Kind));
        Assert.Equal(("ps_tienda17", "ps"), (list[4].Db, list[4].Kind));
    }

    [Fact]
    public void ComentadoNoCuenta()
    {
        using var e = new Entorno();
        e.Project("wp", ("wp-config.php", "<?php\n// define( 'DB_NAME', 'mala' );\ndefine('DB_NAME', 'buena');\n"));
        Assert.Equal("buena", Escaner.ProjectDb(e.L.Htdocs, "wp"));
    }

    [Theory]
    [InlineData("ajoselpajizo.com", "dob-prestashop-ajoselpajizo", true)]
    [InlineData("www.ajoselpajizo.es", "ajoselpajizo", true)]
    // (como en Linux: «tienda» es una palabra genérica y se quita del nombre de la carpeta)
    [InlineData("mitienda.com", "dob-prestashop-mitienda", false)]
    [InlineData("tienda.ejemplo.com", "ejemplo-tienda", true)]
    [InlineData("cliente.com.es", "dob-cliente", true)]
    [InlineData("prestashop.com", "dob-prestashop-x", false)]
    [InlineData("github.com", "dob-prestashop-mitienda", false)]
    [InlineData("abc.com", "abc", false)]
    public void DominioQueSeParece(string domain, string folder, bool fits) => Assert.Equal(fits, Escaner.DomainFitsFolder(domain, folder));

    [Fact]
    public void CarpetaPorElNombreDeLaBase()
    {
        using var e = new Entorno();
        e.Project("dob-wordpress-ajos", ("wp-config.php", "<?php"));
        e.Project("otra");
        var folders = Escaner.Folders(e.L.Htdocs);
        Assert.Equal("dob-wordpress-ajos", Escaner.NameMatch(e.L.Htdocs, "wp_ajos", folders));
        Assert.Null(Escaner.NameMatch(e.L.Htdocs, "wp_nada", folders));
    }
}

public class VinculosTests
{
    [Fact]
    public void PorVersionYDeTodas()
    {
        using var e = new Entorno();
        var v = new Vinculos(e.L.ProjectsFile);
        File.WriteAllText(e.L.ProjectsFile, "wp_x=proyecto-x\n");
        Assert.Equal("proyecto-x", v.LinkOf("wp_x", "php-8.4.27"));
        v.Remember("wp_x", "otra", "php-8.5.12");
        Assert.Equal("otra", v.LinkOf("wp_x", "php-8.5.12"));
        Assert.Equal("proyecto-x", v.LinkOf("wp_x", "php-8.4.27"));
        v.Remember("wp_x", "", "php-8.4.27");
        Assert.Equal("", v.LinkOf("wp_x", "php-8.4.27"));
        Assert.Null(v.LinkOf("wp_y", "php-8.4.27"));
        Assert.Equal("wp_x", v.SavedDb("otra", "php-8.5.12"));
        Assert.Null(v.SavedDb("proyecto-x", "php-8.4.27"));
    }

    [Fact]
    public void UnicaQuitaLasDemasDeEsaVersion()
    {
        using var e = new Entorno();
        var v = new Vinculos(e.L.ProjectsFile);
        v.Remember("wp_vieja", "web", "php-8.4.27");
        v.Remember("wp_vieja", "web", "php-8.5.12");
        v.Remember("wp_nueva", "web", "php-8.4.27", only: true);
        Assert.Null(v.LinkOf("wp_vieja", "php-8.4.27"));
        Assert.Equal("web", v.LinkOf("wp_vieja", "php-8.5.12"));
        Assert.Equal("wp_nueva", v.SavedDb("web", "php-8.4.27"));
        v.Write(new[] { ("wp_a", "php-8.4.27", "a"), ("wp_b", "php-8.4.27", "") });
        Assert.Equal("a", v.LinkOf("wp_a", "php-8.4.27"));
        Assert.Throws<ArgumentException>(() => v.Remember("mal nombre", "x", "php-8.4.27"));
    }

    [Fact]
    public void DominiosPropios()
    {
        using var e = new Entorno();
        var d = new DominiosPropios(e.L.CustomDomainsFile);
        d.Set("MiTienda.com", "tienda");
        Assert.Equal("mitienda.com", d.Of("tienda"));
        File.AppendAllText(e.L.CustomDomainsFile, "malo..com=x\nbien.com=car\"peta\n");
        Assert.Single(d.All());
    }
}

public class WordPressTests
{
    const string Config = "<?php\r\n// ** Database settings ** //\r\ndefine( 'DB_NAME', 'produccion' );\r\ndefine( 'DB_USER', 'usuario_prod' );\r\n" +
                          "define( 'DB_PASSWORD', 'cl\\'ave' );\r\ndefine( 'DB_HOST', 'db.servidor.com' );\r\n" +
                          "define( 'AUTH_KEY', 'put your unique phrase here' );\r\n$table_prefix = 'wpx_';\r\n/* That's all, stop editing! */\r\n";

    [Fact]
    public void Lee()
    {
        var w = WordPress.Read(Config);
        Assert.Equal(("produccion", "usuario_prod", "db.servidor.com", "wpx_", "cl'ave"), (w.Name, w.User, w.Host, w.Prefix, w.Password));
    }

    [Fact]
    public void RehaceConLaBaseLocal()
    {
        var t = WordPress.Rewrite(Config, "wp_local", "wpx_", true, "", "https://web.local");
        var w = WordPress.Read(t);
        Assert.Equal(("wp_local", "root", "127.0.0.1", "wpx_", ""), (w.Name, w.User, w.Host, w.Prefix, w.Password));
        Assert.Contains("define('WP_SITEURL', 'https://web.local');\r\n", t);
        Assert.Contains("define('WP_HOME', 'https://web.local');\r\n", t);
        Assert.True(t.IndexOf("WP_SITEURL", StringComparison.Ordinal) < t.IndexOf("Database settings", StringComparison.Ordinal));
        Assert.Contains("DISALLOW_FILE_EDIT', true", t);
        Assert.DoesNotContain("put your unique phrase here", t);
        Assert.DoesNotContain("\r\r", t);
        Assert.DoesNotContain("\n", t.Replace("\r\n", ""));
    }

    [Fact]
    public void ConservaElUsuarioSiEntra()
    {
        var t = WordPress.Rewrite(Config, "wp_local", "wpx_", false, "", "https://web.local");
        Assert.Equal("usuario_prod", WordPress.Read(t).User);
        // (una segunda vez no repite nada)
        var t2 = WordPress.Rewrite(t, "wp_local", "wpx_", false, "", "https://web.local");
        Assert.Single(System.Text.RegularExpressions.Regex.Matches(t2, "WP_SITEURL"));
        Assert.Single(System.Text.RegularExpressions.Regex.Matches(t2, "DISALLOW_FILE_EDIT"));
    }

    [Theory]
    [InlineData("localhost", true)]
    [InlineData("127.0.0.1:3306", true)]
    [InlineData("db.servidor.com", false)]
    [InlineData("localhost.malo.com", false)]
    public void ServidorLocal(string host, bool ok) => Assert.Equal(ok, WordPress.IsLocalHost(host));
}

public class PrestaShopTests
{
    [Fact]
    public void ParametersNuevoSeLeeBien()
    {
        var text = PrestaShop.NewParameters("ps_tienda", "ps_");
        var d = PrestaShop.ReadText(text, "app/config/parameters.php")!;
        Assert.Equal(("ps_tienda", "root", "127.0.0.1", "ps_", ""), (d.Name, d.User, d.Host, d.Prefix, d.Password));
        Assert.True(PrestaShop.HasDatabase(text));
        Assert.Matches("'new_cookie_key' => 'def00000[0-9a-f]{128}'", text);
        Assert.Matches("'cookie_key' => '[A-Za-z0-9]{64}'", text);
    }

    [Fact]
    public void CambiaLaBase()
    {
        var prod = "<?php return array ('parameters' => array ('database_host' => 'db.prod', 'database_port' => '3307', 'database_name' => 'prod', " +
                   "'database_user' => 'u', 'database_password' => 'p', 'database_prefix' => 'ps_'));";
        var t = PrestaShop.SetDb(prod, "app/config/parameters.php", "ps_local", "pre_", true, "");
        var d = PrestaShop.ReadText(t, "app/config/parameters.php")!;
        Assert.Equal(("ps_local", "root", "127.0.0.1", "pre_", ""), (d.Name, d.User, d.Host, d.Prefix, d.Password));
        Assert.Contains("'database_port' => ''", t);
        var s16 = "<?php\ndefine('_DB_SERVER_', 'db');\ndefine('_DB_NAME_', 'prod');\ndefine('_DB_USER_', 'u');\ndefine('_DB_PASSWD_', 'p');\ndefine('_DB_PREFIX_', 'ps_');\n";
        var t16 = PrestaShop.SetDb(s16, "config/settings.inc.php", "ps16", "ps_", true, "");
        var d16 = PrestaShop.ReadText(t16, "config/settings.inc.php")!;
        Assert.Equal(("ps16", "root", "127.0.0.1"), (d16.Name, d16.User, d16.Host));
    }

    [Fact]
    public void PrefijoPorDefecto()
    {
        var d = PrestaShop.ReadText("<?php return array('parameters' => array('database_name' => 'x'));", "app/config/parameters.php")!;
        Assert.Equal("ps_", d.Prefix);
        Assert.Null(PrestaShop.ReadText("<?php return array('parameters' => NULL);", "app/config/parameters.php"));
    }

    [Fact]
    public void CarpetaDeAdministracionYClave()
    {
        using var e = new Entorno();
        var dir = e.Project("tienda", ("admin123abc/index.php", "<?php"), ("admin123abc/ajax-tab.php", "<?php"), ("otra/index.php", "<?php"),
            ("config/settings.inc.php", "<?php define('_COOKIE_KEY_', 'AbC123');"));
        Assert.Equal("admin123abc", PrestaShop.AdminFolder(dir));
        Assert.Equal("AbC123", PrestaShop.CookieKey(dir));
    }
}
