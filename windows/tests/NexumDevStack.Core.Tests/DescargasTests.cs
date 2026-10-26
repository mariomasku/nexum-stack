using System.IO.Compression;
using System.Text;
using NexumDevStack.Core.Catalogo;
using NexumDevStack.Core.Descargas;
using NexumDevStack.Core.Tareas;
using Xunit;
using Cat = NexumDevStack.Core.Catalogo.Catalogo;

namespace NexumDevStack.Core.Tests;

public class FuentesTests
{
    [Fact]
    public void ReleasesDeWindowsPhpNet()
    {
        var r = Fuentes.ParseWindowsReleases(Datos.Text("windows-php-releases.json"));
        Assert.Equal("8.4.27", r["8.4"].Version);
        Assert.Equal("php-8.4.27-Win32-vs17-x64.zip", r["8.4"].File);
        Assert.Equal("7902fe891ff4b035d431fd429a2ec1df193ba1f6fedba425d861790465c64e6b", r["8.4"].Sha256);
        Assert.StartsWith("https://downloads.php.net/~windows/releases/", r["8.4"].Url);
        Assert.Equal("php-7.4.33-Win32-vc15-x64.zip", r["7.4"].File);
        Assert.DoesNotContain(r.Values, x => x.File.Contains("nts"));
    }

    [Fact]
    public void ReleasesRaros()
    {
        // Una versión con | o un fichero que no es el suyo no pasa
        var json = """
{"8.4": {"version": "8.4.27|x", "ts-vs17-x64": {"zip": {"path": "php-8.4.27-Win32-vs17-x64.zip", "sha256": "aa"}}},
 "8.3": {"version": "8.3.36", "ts-vs16-x64": {"zip": {"path": "otro.zip", "sha256": "0606810ff8fc232406aaab677b760e06af93a63a366d33ff738d4ce90501dfa5"}}}}
""";
        Assert.Empty(Fuentes.ParseWindowsReleases(json));
    }

    [Fact]
    public void ArchivoYSbom()
    {
        var html = """
<a href="php-8.2.33-Win32-vs16-x64.zip">x</a> <a href="php-8.2.33-Win32-vs16-x64.zip.spdx.json">x</a>
<a href="php-7.1.33-Win32-VC14-x64.zip">x</a> <a href="php-8.2.33-nts-Win32-vs16-x64.zip">x</a>
""";
        var l = Fuentes.ParseArchiveListing(html);
        Assert.True(l["8.2.33"].HasSbom);
        Assert.False(l["7.1.33"].HasSbom);
        Assert.Equal("php-7.1.33-Win32-VC14-x64.zip", l["7.1.33"].File);
        Assert.Equal(2, l.Count);
        Assert.Equal("7d2568dfaad6ac1391e57994f52c8aed835baf9e6d89f4328770e2843311291c",
            Fuentes.ParseSpdxSha(Datos.Text("php-8.2.33-Win32-vs16-x64.zip.spdx.json"), "php-8.2.33-Win32-vs16-x64.zip"));
        Assert.Null(Fuentes.ParseSpdxSha(Datos.Text("php-8.2.33-Win32-vs16-x64.zip.spdx.json"), "otro.zip"));
    }

    [Fact]
    public void EstadoDeLasRamasEnPhpNet()
    {
        var b = Fuentes.ParseBranches(Datos.Text("php-branches.json"));
        Assert.Equal("stable", b["8.5"].State);
        Assert.Equal("security", b["8.3"].State);
        Assert.Equal("2028-12-31", b["8.4"].SecurityEnd);
        var active = Fuentes.ParseActive(Datos.Text("php-active.json"));
        Assert.Contains("8.4", active);
        Assert.DoesNotContain("7.4", active);
    }

    [Fact]
    public void ParchesDePhpNet()
    {
        var r = Fuentes.ParsePhpNetReleases(Datos.Text("php-releases-8.json"));
        var p = r.First(x => x.Version == "8.4.27");
        Assert.Matches(@"^\d{4}-\d{2}-\d{2}$", p.Date);
        Assert.True(r.IndexOf(r.First(x => x.Version == "8.4.27")) < r.IndexOf(r.First(x => x.Version == "8.4.1")));
        Assert.Empty(Fuentes.ParsePhpNetReleases("""{"error": "Unknown version"}"""));
    }

    [Fact]
    public void ApacheLounge()
    {
        var page = Fuentes.ParseApacheLounge(Datos.Text("apachelounge-download.html"));
        Assert.NotNull(page);
        Assert.Equal("https://www.apachelounge.com/download/VS18/binaries/httpd-2.4.69-261002-Win64-VS18.zip", page!.Value.Zip);
        Assert.EndsWith(".zip.asc", page.Value.Asc);
        Assert.EndsWith(".zip.txt", page.Value.Txt);
        Assert.Equal("2.4.69", page.Value.Version);
        Assert.Equal(Cat.PinnedApache.Sha256,
            Fuentes.ParseApacheLoungeSha(Datos.Text("apachelounge-httpd.zip.txt"), "httpd-2.4.69-261002-Win64-VS18.zip"));
    }

    [Fact]
    public void MariaDb()
    {
        var r = Fuentes.ParseMariaDbLatest(Datos.Text("mariadb-11.8-latest.json"));
        Assert.NotNull(r);
        Assert.Equal("11.8.9", r!.Value.Version);
        var d = r.Value.Download;
        Assert.Equal("mariadb-11.8.9-winx64.zip", d.Name);
        Assert.StartsWith("https://", d.Url);
        Assert.Equal(Cat.PinnedMariaDb["11.8"].Sha256, d.Sha256);
        Assert.True(d.Signed);
        Assert.Equal(Cat.FprMariaDb, d.Fingerprints);
    }

    [Fact]
    public void SumaDeCurl() =>
        Assert.Equal(new string('a', 64), Fuentes.ParseShaLine(new string('a', 64) + "  cacert.pem\n"));
}

public class FirmasTests
{
    static Firmas Prueba()
    {
        using var s = File.OpenRead(Datos.Path("claves-prueba.gpg"));
        return new Firmas(s);
    }

    static string Fpr(string name) => Datos.Text(name).Trim();

    [Theory]
    [InlineData("firmado.txt.asc")]
    [InlineData("firmado.txt.sig")]
    public void FirmaBuena(string sig)
    {
        var f = Prueba();
        using var data = File.OpenRead(Datos.Path("firmado.txt"));
        using var s = File.OpenRead(Datos.Path(sig));
        Assert.Equal(Fpr("huella-a.txt"), f.Verify(data, s, new[] { Fpr("huella-a.txt") }, out _));
    }

    [Fact]
    public void FirmaDeOtraClaveNoVale()
    {
        var f = Prueba();
        using var data = File.OpenRead(Datos.Path("firmado.txt"));
        using var s = File.OpenRead(Datos.Path("firmado-por-b.txt.asc"));
        Assert.Null(f.Verify(data, s, new[] { Fpr("huella-a.txt") }, out var why));
        Assert.Contains("no publica", why);
    }

    [Fact]
    public void FicheroCambiado()
    {
        var f = Prueba();
        using var data = new MemoryStream(Encoding.UTF8.GetBytes("Fichero de prueba de Nexum Dev Stack\nlinea 3\n"));
        using var s = File.OpenRead(Datos.Path("firmado.txt.asc"));
        Assert.Null(f.Verify(data, s, new[] { Fpr("huella-a.txt") }, out var why));
        Assert.Contains("no coincide", why);
    }

    [Fact]
    public void FirmaQueNoEsFirma()
    {
        var f = Prueba();
        using var data = File.OpenRead(Datos.Path("firmado.txt"));
        using var s = new MemoryStream(Encoding.ASCII.GetBytes("esto no es una firma"));
        Assert.Null(f.Verify(data, s, new[] { Fpr("huella-a.txt") }, out _));
    }

    [Fact]
    public void ClavesDelProgramaTienenLasHuellasFijadas()
    {
        var f = Firmas.Embedded();
        var all = f.Fingerprints().ToHashSet();
        foreach (var fpr in Cat.FprMariaDb.Concat(Cat.FprApacheLounge).Concat(Cat.FprPma.Take(1)))
            Assert.Contains(fpr, all);
    }

    [Theory]
    [InlineData("mariadb-11.8.9-winx64.zip.asc", "177F4010FE56CA3336300305F1656F24C74CD1D8")]
    [InlineData("httpd-2.4.69-261002-Win64-VS18.zip.asc", "3D49885EADE8BC399F46D5DDBEE88A7829C17558")]
    [InlineData("phpMyAdmin-5.2.3-all-languages.zip.asc", "3D06A59ECE730EB71B511C17CE752F178259BD92")]
    public void FirmasDeVerdadSonDeQuienPublica(string sig, string fpr)
    {
        using var s = File.OpenRead(Datos.Path(sig));
        Assert.Equal(fpr, Firmas.Embedded().Issuer(s));
    }
}

public class ZipTests
{
    static string MakeZip(params (string Name, string Text)[] entries)
    {
        var path = Path.Combine(Path.GetTempPath(), "nexum-zip-" + Guid.NewGuid().ToString("N") + ".zip");
        using var z = ZipFile.Open(path, ZipArchiveMode.Create);
        foreach (var (n, t) in entries)
        {
            var e = z.CreateEntry(n);
            if (!n.EndsWith('/'))
            {
                using var w = new StreamWriter(e.Open());
                w.Write(t);
            }
        }
        return path;
    }

    [Fact]
    public void SacaSoloLoDelPrefijo()
    {
        var zip = MakeZip(("ReadMe.txt", "x"), ("Apache24/", ""), ("Apache24/bin/httpd.exe", "exe"), ("Apache24/conf/httpd.conf", "conf"));
        var dest = Path.Combine(Path.GetTempPath(), "nexum-dest-" + Guid.NewGuid().ToString("N"));
        try
        {
            Assert.Equal(2, Zip.Extract(zip, dest, "Apache24/"));
            Assert.True(File.Exists(Path.Combine(dest, "bin", "httpd.exe")));
            Assert.False(File.Exists(Path.Combine(dest, "ReadMe.txt")));
            Assert.Equal("Apache24/", Zip.TopFolder(zip, "Apache"));
        }
        finally
        {
            File.Delete(zip);
            if (Directory.Exists(dest)) Directory.Delete(dest, true);
        }
    }

    [Theory]
    [InlineData("../fuera.txt")]
    [InlineData("a/../../fuera.txt")]
    [InlineData("/absoluta.txt")]
    [InlineData("C:/windows/x.txt")]
    public void NoSeSaleDeLaCarpeta(string bad)
    {
        var zip = MakeZip(("bien.txt", "x"), (bad, "malo"));
        var dest = Path.Combine(Path.GetTempPath(), "nexum-dest-" + Guid.NewGuid().ToString("N"));
        try
        {
            Assert.Throws<NexumException>(() => Zip.Extract(zip, dest, ""));
        }
        finally
        {
            File.Delete(zip);
            if (Directory.Exists(dest)) Directory.Delete(dest, true);
        }
    }
}
