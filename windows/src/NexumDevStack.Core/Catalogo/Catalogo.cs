using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.Catalogo;

/// <summary>Una descarga: de dónde, su sha256 y cómo se ha sabido (para la ventana y el registro).</summary>
public sealed record Descarga(string Name, string Url, string Sha256, string? SignatureUrl, string? SignatureText,
    string[] Fingerprints, string HowVerified)
{
    public bool Signed => SignatureUrl != null || SignatureText != null;
}

/// <summary>
/// Versiones que se ofrecen y la pila de cada rama, como STACK_MATRIX de Linux. En Windows no se compila
/// nada: PHP de windows.php.net (Thread Safe, para cargarlo como módulo de Apache, como XAMPP), Apache de
/// Apache Lounge, MariaDB oficial y phpMyAdmin oficial.
/// </summary>
public static class Catalogo
{
    /// <summary>rama de PHP → rama de MariaDB (la misma escalera que Linux; 7.1-7.3 como 7.4).</summary>
    public static readonly IReadOnlyList<(string Php, string MariaDb)> StackMatrix = new[]
    {
        ("7.1", "10.11"), ("7.2", "10.11"), ("7.3", "10.11"), ("7.4", "10.11"),
        ("8.0", "10.11"), ("8.1", "10.11"), ("8.2", "10.11"),
        ("8.3", "11.4"), ("8.4", "11.8"), ("8.5", "12.3"),
    };

    /// <summary>Rama de MariaDB de una rama de PHP (una más nueva que la tabla, la última fila; una más vieja, ninguna).</summary>
    public static string? MariaDbBranch(string phpBranch)
    {
        foreach (var (php, maria) in StackMatrix)
            if (php == phpBranch)
                return maria;
        var last = StackMatrix[^1];
        return Versiones.Compare(phpBranch, last.Php) > 0 ? last.MariaDb : null;
    }

    public static IEnumerable<string> OfferedBranches => StackMatrix.Select(r => r.Php);

    // ------------------------------------------------------------------ claves de quien firma
    /// <summary>MariaDB Signing Key.</summary>
    public static readonly string[] FprMariaDb = { "177F4010FE56CA3336300305F1656F24C74CD1D8" };

    /// <summary>Isaac Bennetch, Marc Delisle, Michal Čihař y el equipo de seguridad de phpMyAdmin.</summary>
    public static readonly string[] FprPma =
    {
        "3D06A59ECE730EB71B511C17CE752F178259BD92", "436FF1884B1A0C3FDCBF0D79FEFC65D181AF644A",
        "63CB1DF1EF12CF2AC0EE5A329C27B31342B7511D", "5BAD38CFB98050B94BD7FB5BDA68AB39218AB947",
    };

    /// <summary>Steffen Land (Apache Lounge), que firma los binarios de Apache para Windows.</summary>
    public static readonly string[] FprApacheLounge = { "3D49885EADE8BC399F46D5DDBEE88A7829C17558" };

    // ------------------------------------------------------------------ PHP
    /// <summary>
    /// Último parche de las ramas sin versiones nuevas que ya no están en releases.json de windows.php.net
    /// (en su archivo). windows.php.net no publica sus sumas: estas se sacaron el 25/10/2026 descargándolos
    /// por HTTPS (y no cambian: son versiones cerradas).
    /// </summary>
    public static readonly IReadOnlyDictionary<string, (string Version, string File, string Sha256, string Date)> PinnedOldPhp =
        new Dictionary<string, (string, string, string, string)>
        {
            ["7.1"] = ("7.1.33", "php-7.1.33-Win32-VC14-x64.zip", "2f6b0c6b62de88cf5cc16e68ac6d5e3b73fc01bcb03b51fe8c8534965b8e808c", "2019-10-24"),
            ["7.2"] = ("7.2.34", "php-7.2.34-Win32-VC15-x64.zip", "3a3d026aacf8da57ff01ace2f78f8f57494744bfb669f8545cc8f9c4ff0450a5", "2020-10-01"),
            ["7.3"] = ("7.3.33", "php-7.3.33-Win32-VC15-x64.zip", "eabf265d817ea534eeeeb51995693a8fd215bc6cfc42d5fcd5e5cd56a1d5da53", "2021-11-18"),
        };

    public const string PhpReleasesUrl = "https://downloads.php.net/~windows/releases/releases.json";
    public const string PhpReleasesBase = "https://downloads.php.net/~windows/releases/";
    public const string PhpArchivesBase = "https://downloads.php.net/~windows/releases/archives/";

    /// <summary>Compilación de Windows de cada rama de PHP: vc14 (7.0-7.1), vc15 (7.2-7.4), vs16 (8.0-8.3), vs17 (8.4…).</summary>
    public static string BuildTag(string branch) =>
        Versiones.Compare(branch, "8.4") >= 0 ? "vs17" :
        Versiones.Compare(branch, "8.0") >= 0 ? "vs16" :
        Versiones.Compare(branch, "7.2") >= 0 ? "vc15" : "vc14";

    /// <summary>
    /// Runtime de Visual C++ que hace falta. Apache Lounge compila con Visual Studio 2026 (VS18) y pide el
    /// 14.50 o posterior; con él funcionan también los PHP vc14, vc15, vs16 y vs17.
    /// </summary>
    public static readonly Version MinVcRuntime = new(14, 50);

    public const string VcRedistUrl = "https://aka.ms/vc14/vc_redist.x64.exe";

    // ------------------------------------------------------------------ Apache
    public const string ApacheLoungePage = "https://www.apachelounge.com/download/";
    public const string ApacheLoungeBase = "https://www.apachelounge.com";

    /// <summary>
    /// Apache de Apache Lounge conocido: si la página de descargas no se puede leer, se usa este (su firma se
    /// comprueba igual).
    /// </summary>
    public static readonly Descarga PinnedApache = new(
        "httpd-2.4.69-261002-Win64-VS18.zip",
        "https://www.apachelounge.com/download/VS18/binaries/httpd-2.4.69-261002-Win64-VS18.zip",
        "77d715d0d9cee731e2251e7ddc2090a7a8e6d41fedef2e9827cd918593c5a652",
        "https://www.apachelounge.com/download/VS18/binaries/httpd-2.4.69-261002-Win64-VS18.zip.asc", null,
        FprApacheLounge, "sha256 fijada en Nexum y firma GPG de Apache Lounge");

    // ------------------------------------------------------------------ MariaDB
    public static string MariaDbApi(string branch) => $"https://downloads.mariadb.org/rest-api/mariadb/{branch}/latest/";

    /// <summary>MariaDB conocidos (si la API de MariaDB no responde). Su firma va en la API: sin ella, solo el sha256 fijado.</summary>
    public static readonly IReadOnlyDictionary<string, (string Version, string Sha256)> PinnedMariaDb =
        new Dictionary<string, (string, string)>
        {
            ["10.11"] = ("10.11.19", "398ea30e5036010bbebe01d2b1804280424dcc2626e36d8e95155c04d25a0490"),
            ["11.4"] = ("11.4.13", "d62986d433eeebfde218560b276103831604a61e929e87f1a17f5aebd80257e2"),
            ["11.8"] = ("11.8.9", "830c46727d9278eae212ae3eca44eeb9e71b2a68704e95f344a64fba7b1963f5"),
            ["12.3"] = ("12.3.3", "4b5706b47148b47c8f36963c8352d1ddee37a1287b4690428f631a74b09b85a0"),
        };

    // ------------------------------------------------------------------ phpMyAdmin
    /// <summary>
    /// phpMyAdmin que admite cada PHP (como pma_for_php de Linux): 5.2 desde PHP 7.2.5, 5.1.4 desde la 7.1.3 y
    /// 4.9.11 antes. Las sumas del .zip, comprobadas con su firma GPG el 25/10/2026.
    /// </summary>
    public static (string Version, string Sha256) PmaFor(string php) =>
        Versiones.Compare(php, "7.2.5") >= 0 ? ("5.2.3", "2d2e13c735366d318425c78e4ee2cc8fc648d77faba3ddea2cd516e43885733f") :
        Versiones.Compare(php, "7.1.3") >= 0 ? ("5.1.4", "7f11a4018e9ee72667d4d63b5863750e0117c5694b9421a57c43454b3903e0d1") :
        ("4.9.11", "d17c762d312b85ae3a8a2c452633372f686502c7c2682f9ef0e8a844fa0ff1b0");

    public static Descarga PmaDownload(string php)
    {
        var (v, sha) = PmaFor(php);
        var url = $"https://files.phpmyadmin.net/phpMyAdmin/{v}/phpMyAdmin-{v}-all-languages.zip";
        return new Descarga($"phpMyAdmin-{v}-all-languages.zip", url, sha, url + ".asc", null, FprPma,
            "sha256 fijada en Nexum y firma GPG de phpMyAdmin");
    }

    /// <summary>¿Tiene la versión un phpMyAdmin con fallos de seguridad ya corregidos?</summary>
    public static bool PmaOutdated(string php, string pma)
    {
        if (Versiones.Parts(php).Length == 0) return false;
        if (Versiones.Parts(pma).Length == 0) return true;
        var need = Versiones.Compare(php, "7.2.5") >= 0 ? "5.2.2" : Versiones.Compare(php, "7.1.3") >= 0 ? "5.1.4" : "4.9.11";
        return Versiones.Compare(pma, need) < 0;
    }

    // ------------------------------------------------------------------ certificados de CA para PHP
    /// <summary>
    /// Certificados de CA de Mozilla para curl y openssl de PHP (como el cacert.pem de XAMPP): sin ellos, PHP
    /// de Windows no puede comprobar ninguna web https. curl.se publica su sha256 (solo HTTPS, sin firma).
    /// </summary>
    public const string CaBundleUrl = "https://curl.se/ca/cacert.pem";
    public const string CaBundleShaUrl = "https://curl.se/ca/cacert.pem.sha256";

    // ------------------------------------------------------------------ php.net
    public const string PhpNetBranches = "https://www.php.net/releases/branches.php";
    public const string PhpNetActive = "https://www.php.net/releases/active.php";
    public static string PhpNetReleases(int major) => $"https://www.php.net/releases/index.php?json&version={major}&max=1000";
}
