using System.Security.Cryptography.X509Certificates;
using System.Text.RegularExpressions;
using NexumDevStack.Core.Configuracion;
using NexumDevStack.Core.Pila;
using Xunit;

namespace NexumDevStack.Core.Tests;

public class ApacheTests
{
    static readonly Disposicion L = new(@"C:\NexumDevStack", @"C:\Users\u\AppData\Local\NexumDevStack", @"C:\Users\u\nexum-copias");

    static Manifiesto M(string php) => new() { Folder = "php-" + php, Php = php, Apache = "2.4.69", MariaDb = "11.8.9", Pma = "5.2.3" };

    static readonly string[] Mods = { "mod_ssl.so", "mod_rewrite.so", "mod_headers.so", "mod_cgi.so", "mod_unixd.so", "mod_dir.so" };

    [Fact]
    public void SoloEnEsteEquipo()
    {
        var conf = Apache.HttpdConf(L, M("8.4.27"), Puertos.Default, true, Mods, "php8apache2_4.dll");
        var listens = Regex.Matches(conf, @"(?m)^Listen\s+(\S+)").Select(m => m.Groups[1].Value).ToList();
        Assert.Equal(new[] { "127.0.0.1:80", "[::1]:80", "127.0.0.1:443", "[::1]:443" }, listens);
        Assert.DoesNotContain("0.0.0.0", conf);
    }

    [Fact]
    public void ModulosSinCgi()
    {
        var conf = Apache.HttpdConf(L, M("8.4.27"), Puertos.Default, false, Mods, "php8apache2_4.dll");
        Assert.Contains("LoadModule ssl_module modules/mod_ssl.so", conf);
        Assert.Contains("LoadModule rewrite_module modules/mod_rewrite.so", conf);
        Assert.DoesNotContain("mod_cgi", conf);
        Assert.DoesNotContain("unixd", conf);
        // (sin el módulo en la carpeta, no se carga)
        Assert.DoesNotContain("mod_http2", conf);
        Assert.DoesNotContain("ExecCGI", conf);
    }

    [Fact]
    public void PhpComoModulo()
    {
        var c8 = Apache.HttpdConf(L, M("8.4.27"), Puertos.Default, true, Mods, "php8apache2_4.dll");
        Assert.Contains("LoadModule php_module \"${NEXUM_VERSION}/php/php8apache2_4.dll\"", c8);
        Assert.Contains("PHPIniDir \"${NEXUM_VERSION}/php\"", c8);
        Assert.Contains("Define NEXUM_VERSION \"C:/NexumDevStack/versiones/php-8.4.27\"", c8);
        var c7 = Apache.HttpdConf(L, M("7.4.33"), Puertos.Default, true, Mods, "php7apache2_4.dll");
        Assert.Contains("LoadModule php7_module", c7);
        Assert.DoesNotContain('\\', c8.Replace("\\.php", "").Replace("\\\"", ""));
    }

    [Fact]
    public void RegistrosYSeguridadIncluidos()
    {
        var conf = Apache.HttpdConf(L, M("8.4.27"), Puertos.Default, true, Mods, "php8apache2_4.dll");
        Assert.Contains("ErrorLog \"${NEXUM_REGISTROS}/apache-error.log\"", conf);
        Assert.Contains("PidFile \"${NEXUM_REGISTROS}/httpd.pid\"", conf);
        var sec = conf.IndexOf("nexum-seguridad.conf", StringComparison.Ordinal);
        var vh = conf.IndexOf("httpd-vhosts.conf\"", StringComparison.Ordinal);
        Assert.True(sec > 0 && vh > sec, "La seguridad va antes que los vhosts");
        Assert.Contains("Require local", conf);
    }

    [Fact]
    public void BarreraEntreWebs()
    {
        var on = Apache.SecurityConf(L, Puertos.Default, true);
        var off = Apache.SecurityConf(L, Puertos.Default, false);
        Assert.Contains(Apache.CrossSiteStart, on);
        Assert.Contains("Sec-Fetch-Site} =~ /^cross-site$/i", on);
        Assert.DoesNotContain(Apache.CrossSiteStart, off);
        Assert.DoesNotContain("barrera entre webs de Nexum", off);
        foreach (var t in new[] { on, off })
        {
            Assert.Contains("LimitRequestBody 67108864", t);
            Assert.Contains("TraceEnable Off", t);
            Assert.Contains("Redirect 302 \"http://127.0.0.1/phpmyadmin/?\"", t);
            Assert.Contains("phpmyadmin/setup", t);
            // Las mismas etiquetas abiertas que cerradas
            Assert.Equal(Regex.Matches(t, "<If ").Count, Regex.Matches(t, "</If>").Count);
            Assert.Equal(Regex.Matches(t, "<VirtualHost ").Count, Regex.Matches(t, "</VirtualHost>").Count);
            Assert.Equal(Regex.Matches(t, "<FilesMatch ").Count, Regex.Matches(t, "</FilesMatch>").Count);
            Assert.Contains("SSLCertificateFile \"C:/NexumDevStack/config/ssl/localhost.crt\"", t);
            Assert.DoesNotContain("'\"'\"'", t);
        }
    }

    [Fact]
    public void NoSeSirvenFicherosDeConfiguracion()
    {
        var t = Apache.SecurityConf(L, Puertos.Default, true);
        var rx = new Regex(Regex.Match(t, "<FilesMatch \"\\(\\?i\\)(.*)\">").Groups[1].Value, RegexOptions.IgnoreCase);
        foreach (var bad in new[] { ".env", ".env.local", "copia.sql", "x.sql.gz", "debug.log", "wp-config.php.bak", "wp-config.old", "id_rsa", "auth.json", "docker-compose.yml", "backup-2024.zip", "customers_export_1.csv" })
            Assert.True(rx.IsMatch(bad), bad);
        foreach (var good in new[] { "index.php", "wp-config.php", "wp-config-sample.php", "style.css", "logo.png" })
            Assert.False(rx.IsMatch(good), good);
    }
}

public class PhpMariaDbTests
{
    static readonly Disposicion L = new(@"C:\NexumDevStack", @"C:\u", @"C:\c");

    static Manifiesto M(string php) => new() { Folder = "php-" + php, Php = php, MariaDb = "11.8.9", Pma = "5.2.3" };

    [Fact]
    public void PhpIniConLoDeNexumAlFinal()
    {
        var exts = new[] { "php_curl.dll", "php_mbstring.dll", "php_exif.dll", "php_gd.dll", "php_gd2.dll", "php_opcache.dll", "php_mysqli.dll" };
        var ini = PhpMariaDb.PhpIni(L, M("8.4.27"), "[PHP]\nmemory_limit = 128M\n", exts, Puertos.Default, true);
        Assert.StartsWith("[PHP]\r\nmemory_limit = 128M", ini);
        Assert.True(ini.LastIndexOf("memory_limit = 512M", StringComparison.Ordinal) > ini.IndexOf("memory_limit = 128M", StringComparison.Ordinal));
        Assert.Contains("extension=curl", ini);
        Assert.Contains("extension=gd\r\n", ini);
        Assert.DoesNotContain("extension=gd2", ini);
        Assert.DoesNotContain("extension=intl", ini);
        Assert.True(ini.IndexOf("extension=mbstring", StringComparison.Ordinal) < ini.IndexOf("extension=exif", StringComparison.Ordinal));
        Assert.Contains("zend_extension=opcache", ini);
        Assert.Contains("extension_dir = \"C:/NexumDevStack/versiones/php-8.4.27/php/ext\"", ini);
        Assert.Contains("session.upload_progress.enabled = Off", ini);
        Assert.Contains("expose_php = Off", ini);
        Assert.DoesNotContain("fatal_error_backtraces", ini);
        Assert.Contains("curl.cainfo", ini);
        Assert.Contains("SMTP = 127.0.0.1", ini);
        Assert.Contains("display_errors = Off", ini);
        Assert.DoesNotContain("\n\n\n\n", ini.Replace("\r\n", "\n"));
    }

    [Fact]
    public void Php85SinTrazas()
    {
        var ini = PhpMariaDb.PhpIni(L, M("8.5.12"), "", Array.Empty<string>(), Puertos.Default, false);
        Assert.Contains("fatal_error_backtraces = 0", ini);
        Assert.DoesNotContain("curl.cainfo", ini);
    }

    [Fact]
    public void Php7ConGd2()
    {
        var ini = PhpMariaDb.PhpIni(L, M("7.4.33"), "", new[] { "php_gd2.dll" }, Puertos.Default, false);
        Assert.Contains("extension=gd2", ini);
    }

    [Fact]
    public void MyIniSoloLocal()
    {
        var ini = PhpMariaDb.MyIni(L, M("8.4.27"), Puertos.Default);
        Assert.Contains("bind-address = 127.0.0.1", ini);
        Assert.Contains("local-infile = 0", ini);
        Assert.Contains("secure-file-priv = \"C:/NexumDevStack/versiones/php-8.4.27/conf/sin-ficheros\"", ini);
        Assert.Contains("datadir = \"C:/NexumDevStack/datos/php-8.4.27\"", ini);
        Assert.Contains("collation-server = utf8mb4_general_ci", ini);
        Assert.Contains("loose-named_pipe = OFF", ini);
        Assert.DoesNotContain("skip-name-resolve", ini);
    }

    [Fact]
    public void PhpMyAdminPorTcp()
    {
        var a = PhpMariaDb.PmaConfig(L, M("8.4.27"), Puertos.Default);
        var b = PhpMariaDb.PmaConfig(L, M("8.4.27"), Puertos.Default);
        Assert.Contains("$cfg['Servers'][$i]['host'] = '127.0.0.1';", a);
        Assert.Contains("$cfg['Servers'][$i]['connect_type'] = 'tcp';", a);
        Assert.Contains("$cfg['Servers'][$i]['bookmarktable'] = 'pma__bookmark';", a);
        Assert.Contains("C:/NexumDevStack/tmp/php-8.4.27/phpmyadmin", a);
        // (la clave de las cookies, nueva cada vez)
        Assert.NotEqual(Regex.Match(a, "blowfish_secret'] = '([0-9a-f]+)'").Groups[1].Value,
            Regex.Match(b, "blowfish_secret'] = '([0-9a-f]+)'").Groups[1].Value);
    }
}

public class VhostsTests
{
    static readonly Disposicion L = new(@"C:\NexumDevStack", @"C:\u", @"C:\c");

    const string Sample = """
# Comentario
<VirtualHost *:80>
    ServerAdmin yo@ejemplo.com
    DocumentRoot "C:/NexumDevStack/htdocs/.nexum-sin-proyecto"
    ServerName web.local
    ServerAlias www.web.local
</VirtualHost>
<VirtualHost *:443>
    DocumentRoot "C:/NexumDevStack/htdocs/.nexum-sin-proyecto"
    ServerName web.local
    SSLEngine on
    SSLCertificateFile "C:/NexumDevStack/config/ssl/web.local.crt"
    SSLCertificateKeyFile "C:/NexumDevStack/config/ssl/web.local.key"
</VirtualHost>
#<VirtualHost *:80>
#    ServerName comentado.com
#</VirtualHost>
<VirtualHost *:443>
    DocumentRoot "C:/NexumDevStack/htdocs/dob-prestashop-mitienda"
    ServerName MiTienda.com:443
    ServerAlias www.mitienda.com
    SSLCertificateFile C:/NexumDevStack/config/ssl/mitienda.com-selfsigned.crt
    SSLCertificateKeyFile C:/NexumDevStack/config/ssl/mitienda.com-selfsigned.key
</VirtualHost>
""";

    [Fact]
    public void Lee()
    {
        var v = Vhosts.Parse(Sample);
        Assert.Equal(3, v.Count);
        Assert.Equal("web.local", v[0].Name);
        Assert.Equal(".nexum-sin-proyecto", v[0].Folder);
        Assert.Equal(443, v[2].Port);
        Assert.Equal("mitienda.com", v[2].Name);
        Assert.Equal("dob-prestashop-mitienda", v[2].Folder);
        Assert.Contains("www.mitienda.com", v[2].Aliases);
        Assert.True(v[2].Https);
        Assert.Equal("", Vhosts.ProjectFolder(v));
        Assert.Null(Vhosts.ProjectFolder(Vhosts.Parse("")));
    }

    [Fact]
    public void CambiaElProyectoDeWebLocal()
    {
        var t = Vhosts.SetProjectRoot(Sample.Replace("\n", "\r\n"), L, "mi-proyecto");
        var v = Vhosts.Parse(t);
        Assert.Equal("mi-proyecto", Vhosts.ProjectFolder(v));
        Assert.All(v.Where(x => x.Name == "web.local"), x => Assert.Equal("C:/NexumDevStack/htdocs/mi-proyecto", x.DocumentRoot));
        // (los demás vhosts no se tocan, ni los finales de línea)
        Assert.Equal("dob-prestashop-mitienda", v[2].Folder);
        Assert.Contains("\r\n", t);
        Assert.Equal("", Vhosts.ProjectFolder(Vhosts.Parse(Vhosts.SetProjectRoot(t, L, null))));
    }

    [Fact]
    public void BloquesNuevos()
    {
        var web = Vhosts.ProjectVhostBlock(L, Puertos.Default, "admin@localhost");
        var v = Vhosts.Parse(web);
        Assert.Equal(2, v.Count);
        Assert.Contains("Cache-Control \"no-store\"", web);
        Assert.Contains("ErrorLog \"${NEXUM_REGISTROS}/web.local-error.log\"", web);
        var d = Vhosts.DomainBlocks(L, Puertos.Default, "tienda", "mitienda.com", "admin@localhost", true, true,
            @"C:\NexumDevStack\config\ssl\mitienda.com-selfsigned.crt", @"C:\NexumDevStack\config\ssl\mitienda.com-selfsigned.key");
        var dv = Vhosts.Parse(d);
        Assert.Equal(new[] { 80, 443 }, dv.Select(x => x.Port));
        Assert.All(dv, x => Assert.Equal("tienda", x.Folder));
        Assert.Contains("www.mitienda.com", dv[0].Aliases);
        Assert.Equal("C:/NexumDevStack/config/ssl/mitienda.com-selfsigned.crt", dv[1].Crt);
        Assert.Equal("mitienda.com", Vhosts.DomainAlias("www.mitienda.com"));
    }
}

public class HostsTests
{
    static List<VhostInfo> V(params (string Name, string Alias, string Folder)[] v) =>
        v.SelectMany(x => new[]
        {
            new VhostInfo(80, x.Folder, x.Name, new[] { x.Alias }, "", "", "", 0, 0),
            new VhostInfo(443, x.Folder, x.Name, new[] { x.Alias }, "c.crt", "c.key", "", 0, 0),
        }).ToList();

    static readonly List<VhostInfo> Two = V(("tienda.com", "www.tienda.com", "dob-tienda"), ("otra.es", "www.otra.es", "dob-otra"),
        ("proyecto.local", "www.proyecto.local", "proyecto"), ("web.local", "www.web.local", ".nexum-sin-proyecto"));

    [Fact]
    public void CargarFalseaUnoYApagaLosDemas()
    {
        var hosts = "127.0.0.1 localhost\n127.0.0.1 otra.es www.otra.es\n# 127.0.0.1 tienda.com www.tienda.com\n10.0.0.5 servidor\n";
        var (t, changes) = Hosts.Fake(hosts, Two, Hosts.Modo.Cargar, new[] { "tienda.com" }, Array.Empty<string>());
        Assert.Contains("\n127.0.0.1 tienda.com www.tienda.com\n", t);
        Assert.Contains("#127.0.0.1 otra.es www.otra.es", t);
        Assert.Contains("10.0.0.5 servidor", t);
        Assert.StartsWith("127.0.0.1 localhost\n", t);
        // (los .local, siempre: se añade su línea)
        Assert.Contains("127.0.0.1 proyecto.local", t);
        Assert.DoesNotContain("web.local", t);
        Assert.Contains(changes, c => c.StartsWith("Falseado"));
        Assert.Contains(changes, c => c.StartsWith("Ya no está falseado"));
    }

    [Fact]
    public void SinLineaSeAnade()
    {
        var (t, _) = Hosts.Fake("127.0.0.1 localhost\r\n", Two, Hosts.Modo.Cargar, new[] { "www.tienda.com" }, new[] { "proyecto.local", "www.proyecto.local" });
        Assert.Contains("127.0.0.1 www.tienda.com tienda.com\r\n", t);
        Assert.DoesNotContain("proyecto.local", t);
        Assert.EndsWith("\r\n", t);
    }

    [Fact]
    public void SiYNoSoloTocanEse()
    {
        var hosts = "127.0.0.1 tienda.com www.tienda.com\n127.0.0.1 otra.es www.otra.es\n127.0.0.1 proyecto.local www.proyecto.local\n";
        var (no, _) = Hosts.Fake(hosts, Two, Hosts.Modo.No, new[] { "tienda.com" }, Array.Empty<string>());
        Assert.Contains("#127.0.0.1 tienda.com www.tienda.com", no);
        Assert.Contains("\n127.0.0.1 otra.es www.otra.es", no);
        var (si, _) = Hosts.Fake(no, Two, Hosts.Modo.Si, new[] { "tienda.com" }, Array.Empty<string>());
        Assert.Equal(hosts, si);
    }

    [Fact]
    public void NuncaTocaLineasQueNoSonSuyas()
    {
        // Una línea con un dominio que no es de ningún vhost (o el nombre del equipo) se queda como está
        var hosts = "127.0.0.1 tienda.com mi-equipo\n";
        var (t, _) = Hosts.Fake(hosts, Two, Hosts.Modo.Cargar, Array.Empty<string>(), Array.Empty<string>());
        Assert.StartsWith(hosts, t);
    }

    [Fact]
    public void ArreglaWebLocal()
    {
        var (t, ch) = Hosts.FixLink("127.0.1.1 equipo web.local\n127.0.0.1 localhost\n", "web.local");
        Assert.Contains("127.0.1.1 equipo\n", t);
        Assert.Contains("127.0.0.1 web.local www.web.local", t);
        Assert.Equal(2, ch.Count);
        var (same, none) = Hosts.FixLink("127.0.0.1 web.local\n", "web.local");
        Assert.Equal("127.0.0.1 web.local\n", same);
        Assert.Empty(none);
        Assert.Equal("127.0.1.1", Hosts.AddressOf("127.0.1.1 web.local", "web.local"));
    }

    [Theory]
    [InlineData("127.0.0.1 localhost\n# comentario\n\n::1 localhost\n", true)]
    [InlineData("127.0.0.1 tienda.com www.tienda.com # falseado\n", true)]
    [InlineData("fe80::1%lo0 localhost\n", true)]
    [InlineData("hola\n", false)]
    [InlineData("127.0.0.1 nombre/raro\n", false)]
    [InlineData("contraseña: secreto 123\n", false)]
    [InlineData("127.0.0.1\n", false)]
    public void ComprobacionDelProcesoElevado(string text, bool ok) => Assert.Equal(ok, Hosts.Problem(text) == null);

    [Fact]
    public void DominiosParaLaVentana()
    {
        var d = Hosts.Domains(Two, "127.0.0.1 tienda.com www.tienda.com\n", f => f == "dob-tienda", new HashSet<string> { "otra.es" }, _ => true, 443);
        Assert.Equal(new[] { "otra.es", "proyecto.local", "tienda.com" }, d.Select(x => x.Name));
        var t = d.Single(x => x.Name == "tienda.com");
        Assert.True(t.Faked && t.Https && t.HasCert && t.PrestaShop);
        Assert.Equal("www.tienda.com", t.Alias);
        Assert.True(d.Single(x => x.Name == "otra.es").Custom);
    }
}

public class CertificadosTests
{
    [Fact]
    public void AutofirmadoDeUnSoloDominioYNoDeCa()
    {
        var p = Certificados.Create("mitienda.com", "www.mitienda.com");
        Assert.False(Certificados.IsCa(p.CertPem));
        using var c = X509Certificate2.CreateFromPem(p.CertPem);
        Assert.Equal(p.Thumbprint, c.Thumbprint);
        Assert.Contains("CN=mitienda.com", c.Subject);
        Assert.Contains(Certificados.Organization, c.Subject);
        var san = c.Extensions.OfType<X509SubjectAlternativeNameExtension>().Single();
        Assert.Equal(new[] { "mitienda.com", "www.mitienda.com" }, san.EnumerateDnsNames());
        var eku = c.Extensions.OfType<X509EnhancedKeyUsageExtension>().Single();
        Assert.Equal("1.3.6.1.5.5.7.3.1", eku.EnhancedKeyUsages[0].Value);
        Assert.StartsWith("-----BEGIN PRIVATE KEY-----", p.KeyPem);
        Assert.Equal(p.Thumbprint, Certificados.Thumbprint(p.CertPem));
    }

    [Fact]
    public void Localhost()
    {
        var p = Certificados.Create("localhost", null);
        using var c = X509Certificate2.CreateFromPem(p.CertPem);
        Assert.Contains("localhost", c.Extensions.OfType<X509SubjectAlternativeNameExtension>().Single().EnumerateDnsNames());
    }

    [Fact]
    public void NombresSeguros()
    {
        Assert.True(Certificados.IsSafeFileName("web.local.crt"));
        Assert.False(Certificados.IsSafeFileName("..\\x.crt"));
        Assert.False(Certificados.IsSafeFileName("x.exe"));
        Assert.Throws<NexumDevStack.Core.Tareas.NexumException>(() => Certificados.Create("no válido", null));
    }
}
