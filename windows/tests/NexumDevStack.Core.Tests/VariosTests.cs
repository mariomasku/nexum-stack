using NexumDevStack.Core.Pila;
using NexumDevStack.Core.Proyectos;
using NexumDevStack.Core.Util;
using Xunit;

namespace NexumDevStack.Core.Tests;

public class RutaSvgTests
{
    [Fact]
    public void ArcosConIndicadoresPegados() =>
        Assert.Equal("M 13.983 11.078 h 2.119 a 0.186 0.186 0 0 0 0.186 -0.185 V 9.006 Z",
            RutaSvg.Normalize("M13.983 11.078h2.119a.186.186 0 00.186-.185V9.006z".Replace("z", "Z")));

    [Fact]
    public void NumerosSeguidosYMoveRepetido() =>
        Assert.Equal("m 1 2 l 3 4 l 0.5 0.5", RutaSvg.Normalize("m1 2 3 4 .5.5"));

    [Fact]
    public void TodosLosLogotiposSeLeen()
    {
        foreach (var (name, d) in Logotipos.Paths)
        {
            var n = RutaSvg.Normalize(d);
            Assert.False(string.IsNullOrWhiteSpace(n), name);
            Assert.True(Logotipos.Colors.ContainsKey(name), name);
        }
        Assert.Contains("php", Logotipos.Paths.Keys);
        Assert.Contains("wordpress", Logotipos.Paths.Keys);
    }

    [Fact]
    public void TrazoMalo() => Assert.Throws<FormatException>(() => RutaSvg.Normalize("M 1 x"));
}

public class AccesoPanelTests
{
    [Fact]
    public void PaginaConLosDatosEscapados()
    {
        var (title, action, fields) = AccesoPanel.LoginFor("wp", "web.local", "wp-admin", "local@local.test", "lo\"cal");
        var page = AccesoPanel.Page(title, "<proyecto>", action, fields, "http://web.local/wp-admin/");
        Assert.Contains("action=\"http://web.local/wp-login.php\"", page);
        Assert.Contains("type=\"password\" name=\"pwd\" value=\"lo&quot;cal\"", page);
        Assert.Contains("&lt;proyecto&gt;", page);
        Assert.Contains("type=\"hidden\" name=\"redirect_to\"", page);
        var ps = AccesoPanel.LoginFor("ps", "web.local", "admin123", "u", "p");
        Assert.Equal("http://web.local/admin123/index.php?controller=AdminLogin", ps.Action);
    }

    [Fact]
    public async Task SeSirveSoloEnSuRuta()
    {
        var url = AccesoPanel.ServeOnce("<p>hola</p>", 10);
        Assert.NotNull(url);
        Assert.StartsWith("http://127.0.0.1:", url);
        using var http = new HttpClient();
        var other = new Uri(new Uri(url!), "/otra");
        Assert.Equal(System.Net.HttpStatusCode.NotFound, (await http.GetAsync(other)).StatusCode);
        var r = await http.GetAsync(url);
        Assert.Equal("<p>hola</p>", await r.Content.ReadAsStringAsync());
        Assert.Equal("no-store", r.Headers.CacheControl?.ToString());
    }
}

public class ManifiestoTests
{
    [Fact]
    public void IdaYVuelta()
    {
        var m = new Manifiesto { Folder = "php-8.4.27", Php = "8.4.27", Apache = "2.4.69", MariaDb = "11.8.9", Pma = "5.2.3", Verified = { "a: b" } };
        var back = Manifiesto.Parse(m.ToJson())!;
        Assert.Equal(("php-8.4.27", "8.4.27", "11.8.9"), (back.Folder, back.Php, back.MariaDb));
        Assert.Equal(8, back.PhpMajor);
        Assert.Equal("8.4", back.Branch);
    }

    [Fact]
    public void RechazaLoRaro()
    {
        Assert.Null(Manifiesto.Parse("""{"folder": "..\\..", "php": "8.4.27"}"""));
        Assert.Null(Manifiesto.Parse("no es json"));
        var m = Manifiesto.Parse("""{"folder": "php-8.4.27", "php": "8.4.27", "apache": "2.4.69\n<script>"}""")!;
        Assert.Equal("", m.Apache);
    }
}
