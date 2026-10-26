using NexumDevStack.Core.Catalogo;
using NexumDevStack.Core.Tareas;
using NexumDevStack.Core.Util;
using Xunit;
using Cat = NexumDevStack.Core.Catalogo.Catalogo;

namespace NexumDevStack.Core.Tests;

public class TextoTests
{
    [Theory]
    [InlineData(1, "1 BBDD")]
    [InlineData(3, "3 BBDD")]
    public void Plural(int n, string expected) => Assert.Equal(expected, Texto.Plural(n, "BBDD", "BBDD"));

    [Fact]
    public void PluralDistingueUnoDeVarios()
    {
        Assert.Equal("1 versión", Texto.Plural(1, "versión", "versiones"));
        Assert.Equal("0 versiones", Texto.Plural(0, "versión", "versiones"));
    }

    [Theory]
    [InlineData(0, "0 B")]
    [InlineData(512, "512 B")]
    [InlineData(1536, "1,5 KB")]
    [InlineData(10L * 1024 * 1024, "10,0 MB")]
    [InlineData(3L * 1024 * 1024 * 1024, "3,0 GB")]
    public void Tamano(long bytes, string expected) => Assert.Equal(expected, Texto.Size(bytes));

    [Fact]
    public void Fechas()
    {
        Assert.Equal("21 de octubre de 2026", Texto.Day("2026-10-21"));
        Assert.Equal("diciembre de 2026", Texto.Month("2026-12-31"));
        Assert.Equal("cosa", Texto.Day("cosa"));
    }

    [Fact]
    public void Reloj()
    {
        Assert.Equal("0:42", Texto.Clock(42));
        Assert.Equal("3:05", Texto.Clock(185));
        Assert.Equal("1:02:10", Texto.Clock(3730));
    }

    [Fact]
    public void LoQueQueda()
    {
        Assert.Equal("calculando lo que queda…", Texto.TimeLeft(2, 10, 90));
        Assert.Equal("quedan unos 10 s", Texto.TimeLeft(10, 50, 50));
        Assert.Equal("queda 1 min", Texto.TimeLeft(60, 50, 50));
        Assert.Equal("quedan unos 5 min", Texto.TimeLeft(300, 50, 50));
        Assert.Equal("quedan unas 2 h 20 min", Texto.TimeLeft(3600, 30, 70));
    }

    [Fact]
    public void Antiguedad()
    {
        Assert.Equal("hace 5 min", Texto.Age(300));
        Assert.Equal("hace 1 hora", Texto.Age(3600));
        Assert.Equal("hace 3 días", Texto.Age(3 * 86400));
        Assert.Equal("hace 2 años", Texto.Age(2 * 365 * 86400));
    }

    [Fact]
    public void QuitaCaracteresDeControl() => Assert.Equal("a?b", Texto.Clean("a\u001bb"));
}

public class ValidacionTests
{
    [Theory]
    [InlineData("wp_tienda", true)]
    [InlineData("ps-mi_tienda2", true)]
    [InlineData("-h", false)]
    [InlineData("a b", false)]
    [InlineData("tienda`; DROP", false)]
    [InlineData("ñandu", false)]
    [InlineData("", false)]
    public void NombresDeBbdd(string name, bool ok) => Assert.Equal(ok, Validacion.IsDbName(name));

    [Fact]
    public void BbddDelSistema()
    {
        Assert.NotNull(Validacion.DbNameProblem("MySQL"));
        Assert.NotNull(Validacion.DbNameProblem("phpmyadmin"));
        Assert.Null(Validacion.DbNameProblem("wp_x"));
    }

    [Theory]
    [InlineData("dob-wordpress-tienda", true)]
    [InlineData("Mi proyecto 2", true)]
    [InlineData("..", false)]
    [InlineData("a/b", false)]
    [InlineData("a\"b", false)]
    [InlineData("acabado.", false)]
    [InlineData(".oculta", false)]
    public void Carpetas(string name, bool ok) => Assert.Equal(ok, Validacion.IsProjectFolder(name));

    [Theory]
    [InlineData("mitienda.com", true)]
    [InlineData("www.mi-tienda.es", true)]
    [InlineData("localhost", false)]
    [InlineData("-mal.com", false)]
    [InlineData("mal..com", false)]
    [InlineData("a b.com", false)]
    public void Dominios(string d, bool ok) => Assert.Equal(ok, Validacion.IsDomain(d));

    [Fact]
    public void VersionesSidYTareas()
    {
        Assert.True(Validacion.IsVersionFolder("php-8.4.27"));
        Assert.False(Validacion.IsVersionFolder("php-8.4"));
        Assert.False(Validacion.IsVersionFolder("php-8.4.27\\..\\x"));
        Assert.True(Validacion.IsUserSid("S-1-5-21-1111111111-2222222222-3333333333-1001"));
        Assert.False(Validacion.IsUserSid("S-1-5-18"));
        Assert.True(Validacion.IsTaskId("0123456789abcdef"));
        Assert.False(Validacion.IsTaskId("0123456789ABCDEF"));
        Assert.True(Validacion.IsReservedWindowsName("con"));
        Assert.True(Validacion.IsReservedWindowsName("COM1.txt"));
        Assert.False(Validacion.IsReservedWindowsName("consola"));
    }
}

public class VersionesTests
{
    [Fact]
    public void OrdenNumerico()
    {
        Assert.True(Versiones.Compare("8.4.9", "8.4.27") < 0);
        Assert.True(Versiones.Compare("8.10.0", "8.9.9") > 0);
        Assert.Equal(0, Versiones.Compare("8.4", "8.4.0"));
        Assert.Equal("8.4", Versiones.Branch("8.4.27"));
    }
}

public class Php2ShellTests
{
    [Theory]
    [InlineData("8.2.35", Php2Shell.Estado.Ok)]
    [InlineData("8.2.34", Php2Shell.Estado.Vulnerable)]
    [InlineData("8.3.36", Php2Shell.Estado.Ok)]
    [InlineData("8.4.26", Php2Shell.Estado.Vulnerable)]
    [InlineData("8.4.27", Php2Shell.Estado.Ok)]
    [InlineData("8.5.12", Php2Shell.Estado.Ok)]
    [InlineData("8.5.11", Php2Shell.Estado.Vulnerable)]
    [InlineData("8.6.0", Php2Shell.Estado.Ok)]
    [InlineData("8.1.34", Php2Shell.Estado.Vulnerable)]
    [InlineData("7.4.33", Php2Shell.Estado.Vulnerable)]
    [InlineData("7.1.33", Php2Shell.Estado.Vulnerable)]
    public void Estado(string php, Php2Shell.Estado expected) => Assert.Equal(expected, Php2Shell.State(php).State);

    [Fact]
    public void LasDeWindowsSinSoporteNoSePuedenArreglar() =>
        Assert.Contains("no se pueden arreglar", Php2Shell.State("8.0.30").Why);

    [Fact]
    public void Mitigaciones()
    {
        Assert.Contains("session.upload_progress.enabled = Off", Php2Shell.SecureIni);
        Assert.Contains("max_input_nesting_level = 6", Php2Shell.SecureIni);
        Assert.Contains("expose_php = Off", Php2Shell.SecureIni);
    }
}

public class CatalogoTests
{
    [Theory]
    [InlineData("7.1", "10.11")]
    [InlineData("8.2", "10.11")]
    [InlineData("8.3", "11.4")]
    [InlineData("8.4", "11.8")]
    [InlineData("8.5", "12.3")]
    [InlineData("8.6", "12.3")]
    public void MariaDbDeCadaRama(string php, string maria) => Assert.Equal(maria, Cat.MariaDbBranch(php));

    [Fact]
    public void RamasAntiguasNoSeOfrecen() => Assert.Null(Cat.MariaDbBranch("7.0"));

    [Theory]
    [InlineData("7.1", "vc14")]
    [InlineData("7.4", "vc15")]
    [InlineData("8.0", "vs16")]
    [InlineData("8.3", "vs16")]
    [InlineData("8.4", "vs17")]
    [InlineData("8.5", "vs17")]
    public void Compilacion(string branch, string tag) => Assert.Equal(tag, Cat.BuildTag(branch));

    [Fact]
    public void PhpMyAdminDeCadaPhp()
    {
        Assert.Equal("5.2.3", Cat.PmaFor("8.4.27").Version);
        Assert.Equal("5.1.4", Cat.PmaFor("7.1.33").Version);
        Assert.Equal("4.9.11", Cat.PmaFor("7.0.33").Version);
        Assert.True(Cat.PmaOutdated("8.4.27", "5.2.1"));
        Assert.False(Cat.PmaOutdated("8.4.27", "5.2.3"));
        var d = Cat.PmaDownload("8.4.27");
        Assert.StartsWith("https://files.phpmyadmin.net/", d.Url);
        Assert.Equal(64, d.Sha256.Length);
        Assert.True(d.Signed);
    }

    [Fact]
    public void LoFijadoEsHttpsYConSuma()
    {
        Assert.StartsWith("https://", Cat.PinnedApache.Url);
        Assert.True(Cat.PinnedApache.Signed);
        foreach (var (_, pin) in Cat.PinnedOldPhp)
            Assert.Matches("^[0-9a-f]{64}$", pin.Sha256);
        foreach (var (_, pin) in Cat.PinnedMariaDb)
            Assert.Matches("^[0-9a-f]{64}$", pin.Sha256);
        Assert.True(Cat.MinVcRuntime >= new Version(14, 50));
    }
}

public class ConsolaTests
{
    [Fact]
    public void RetornoDeCarroReescribeLaLinea()
    {
        var c = new Consola();
        c.Write("Descargando\n  10 %\r  50 %\r 100 %\nhecho\n");
        Assert.Equal("Descargando\n 100 %\nhecho\n", c.Text);
    }

    [Fact]
    public void ContadoresSeguidosSeQuedanEnUno()
    {
        var c = new Consola();
        c.Write("[ 10%] compilando\n[ 20%] compilando\n[ 30%] compilando\nfin\n");
        Assert.Equal("[ 30%] compilando\nfin\n", c.Text);
    }

    [Fact]
    public void SecuenciasDeEscape()
    {
        var c = new Consola();
        c.Write("a\nb\n\x1b[1Aborrada\x1b[K\n");
        Assert.Equal("a\nborrada\n", c.Text);
    }

    [Fact]
    public void LasLineasViejasPasanAlTextoFijo()
    {
        var c = new Consola();
        for (int i = 0; i < 200; i++)
            c.Write($"línea {i}\n");
        Assert.Contains("línea 0", c.FixedText);
        Assert.Contains("línea 199", c.LiveText);
    }
}

public class ProtocoloTests
{
    [Fact]
    public void LasLineasDelProtocoloEmpiezanEnLineaNueva()
    {
        var w = new StringWriter();
        var o = new SalidaTexto(w, true, CancellationToken.None);
        o.Raw("\r   10 %");
        o.Progress(5, "descargando");
        o.Raw("\r   20 %");
        o.Raw("\n");
        o.Progress(6, "x");
        var lines = w.ToString().Replace("\r\n", "\n").Split('\n');
        Assert.Equal(2, lines.Count(l => l.StartsWith(Protocolo.Mark)));
        Assert.DoesNotContain(lines, l => l.Contains(Protocolo.Mark) && !l.StartsWith(Protocolo.Mark));
        // (sin protocolo, en la consola, no se escriben)
        var c = new StringWriter();
        new SalidaTexto(c, false, CancellationToken.None).Progress(5, "x");
        Assert.Equal("", c.ToString());
    }

    [Fact]
    public void LineasDelProtocolo()
    {
        var p = Protocolo.Parse(Protocolo.ProgressLine(42, "descargando\nPHP"));
        Assert.NotNull(p);
        Assert.Equal('P', p!.Kind);
        Assert.Equal(42, p.Number);
        Assert.Equal("descargando PHP", p.Text);
        var c = Protocolo.Parse(Protocolo.PartsLine(new[] { "PHP 8.4", "Apache" }, 2))!;
        Assert.Equal(new[] { "PHP 8.4", "Apache" }, c.Parts);
        Assert.Equal(2, c.Number);
        var b = Protocolo.Parse(Protocolo.BytesLine(10, 100))!;
        Assert.Equal(10, b.Done);
        Assert.Equal(100, b.Total);
        var r = Protocolo.Parse(Protocolo.ResultLine("A", "wp|local@local.test|local"))!;
        Assert.Equal("A|wp|local@local.test|local", r.Text);
        Assert.Null(Protocolo.Parse("una línea normal"));
        Assert.Null(Protocolo.Parse(Protocolo.Mark + "P|no-es-numero|x"));
        Assert.Equal(100, Protocolo.Parse(Protocolo.ProgressLine(250, "x"))!.Number);
    }
}
