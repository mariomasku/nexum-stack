using System.Security.Cryptography;
using System.Text;
using NexumDevStack.Core.Catalogo;
using NexumDevStack.Core.Pila;
using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.Configuracion;

/// <summary>php.ini, my.ini y config.inc.php de phpMyAdmin de cada versión.</summary>
public static class PhpMariaDb
{
    /// <summary>
    /// Extensiones de PHP que se activan si su DLL está (las que piden WordPress y PrestaShop). mbstring va
    /// antes que exif (en PHP 7 exif la necesita cargada).
    /// </summary>
    public static readonly string[] Extensions =
    {
        "bz2", "curl", "fileinfo", "gd", "gd2", "gettext", "intl", "mbstring", "exif", "mysqli", "openssl",
        "pdo_mysql", "soap", "sodium", "zip", "ftp", "sockets", "xsl",
    };

    /// <summary>Zona horaria (NEXUM_ZONA_HORARIA, por defecto Europe/Madrid): solo un nombre válido.</summary>
    public static string TimeZone()
    {
        var tz = Environment.GetEnvironmentVariable("NEXUM_ZONA_HORARIA");
        return tz != null && System.Text.RegularExpressions.Regex.IsMatch(tz, @"^[A-Za-z][A-Za-z0-9_+/-]{0,63}$") ? tz : "Europe/Madrid";
    }

    /// <summary>
    /// php.ini: el php.ini-production de la versión con, al final, lo de Nexum (los mismos valores que en
    /// Linux, las mitigaciones de PHP2Shell y las carpetas de Windows). En php.ini manda la última aparición.
    /// </summary>
    public static string PhpIni(Disposicion l, Manifiesto m, string productionIni, IEnumerable<string> extFiles, Puertos p,
        bool hasCaBundle)
    {
        var php = Apache.Fwd(l.PhpDir(m.Folder));
        var tmp = Apache.Fwd(l.TmpDir(m.Folder));
        var have = new HashSet<string>(extFiles, StringComparer.OrdinalIgnoreCase);
        var sb = new StringBuilder(productionIni.Replace("\r\n", "\n").TrimEnd('\n'));
        sb.Append($"""


; ============================================================================================
; Nexum Dev Stack: lo de abajo manda sobre lo de arriba (en php.ini vale la última aparición).
; Lo escribe el programa al instalar la versión: los cambios a mano se pierden al actualizarla.
; ============================================================================================
extension_dir = "{php}/ext"

""");
        foreach (var ext in Extensions)
        {
            // (gd2 es el nombre de gd en PHP 7; si están las dos, gd)
            if (ext == "gd2" && have.Contains("php_gd.dll"))
                continue;
            if (have.Contains($"php_{ext}.dll"))
                sb.Append($"extension={ext}\n");
        }
        if (have.Contains("php_opcache.dll"))
            sb.Append("zend_extension=opcache\n");
        sb.Append($"""

; Mismos valores que el php.ini de XAMPP y que Linux. Sin error_log: los errores van al registro de
; Apache (registros\{m.Folder}\apache-error.log)
memory_limit = 512M
max_execution_time = 120
max_input_time = 60
max_input_vars = 3000
date.timezone = {TimeZone()}
error_reporting = E_ALL & ~E_DEPRECATED
display_errors = Off
display_startup_errors = Off
log_errors = On
opcache.enable = 1
opcache.revalidate_freq = 0
mysqli.default_host = 127.0.0.1
mysqli.default_port = {p.MariaDb}
pdo_mysql.default_socket =

; Carpetas de tu usuario para las sesiones, las subidas y los temporales
session.save_path = "{tmp}/sesiones"
upload_tmp_dir = "{tmp}/subidas"
sys_temp_dir = "{tmp}/temporal"

; El correo no sale de este equipo: va a 127.0.0.1:1025 (el correo de pruebas, Mailpit, llega en la
; siguiente fase; mientras, mail() falla sin mandar nada)
SMTP = 127.0.0.1
smtp_port = 1025
sendmail_from = local@local.test

""");
        if (hasCaBundle)
            sb.Append($"""
; Certificados de CA de Mozilla (curl.se/ca), para comprobar las webs https
curl.cainfo = "{php}/extras/ssl/cacert.pem"
openssl.cafile = "{php}/extras/ssl/cacert.pem"

""");
        sb.Append("; Mitigaciones de PHP2Shell (CVE-2026-109618 y CVE-2026-109619)\n");
        sb.Append(Php2Shell.SecureIni.Replace("\r\n", "\n").TrimEnd('\n')).Append('\n');
        if (Versiones.Compare(m.Branch, "8.5") >= 0)
            sb.Append(Php2Shell.SecureIni85).Append('\n');
        return sb.ToString().Replace("\n", "\r\n");
    }

    /// <summary>my.ini de MariaDB: solo en 127.0.0.1, sin leer ni escribir ficheros del equipo desde SQL.</summary>
    public static string MyIni(Disposicion l, Manifiesto m, Puertos p)
    {
        string F(string path) => Apache.Fwd(path);
        return $"""
# MariaDB {m.MariaDb} de {m.Folder} (Nexum Dev Stack). Lo escribe el programa al instalar la versión.
[client]
port = {p.MariaDb}
host = 127.0.0.1
protocol = TCP
default-character-set = utf8mb4

[mysqld]
port = {p.MariaDb}
# Solo desde este equipo (y sin tuberías con nombre ni memoria compartida)
bind-address = 127.0.0.1
loose-named_pipe = OFF
loose-shared_memory = OFF
# Sin leer ni escribir ficheros del equipo desde SQL (la carpeta está vacía y es de administrador)
secure-file-priv = "{F(l.NoFilesDir(m.Folder))}"
local-infile = 0
basedir = "{F(l.MariaDbDir(m.Folder))}"
datadir = "{F(l.DataDir(m.Folder))}"
plugin_dir = "{F(Path.Combine(l.MariaDbDir(m.Folder), "lib", "plugin"))}"
pid-file = "{F(l.MariaDbPid(m.Folder))}"
log-error = "{F(l.MariaDbErrorLog(m.Folder))}"
tmpdir = "{F(Path.Combine(l.TmpDir(m.Folder), "mariadb"))}"
max_allowed_packet = 512M
table_open_cache = 640
sort_buffer_size = 5120K
read_buffer_size = 2560K
read_rnd_buffer_size = 5120K
myisam_sort_buffer_size = 80M
innodb_lock_wait_timeout = 50
innodb_buffer_pool_size = 256M
# Mismo cotejamiento que XAMPP, para que los volcados se puedan importar en versiones anteriores y en
# los servidores (desde MariaDB 11.2 el de por defecto es uca1400)
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
loose-character-set-collations = utf8mb4=utf8mb4_general_ci

[mysqldump]
max_allowed_packet = 512M

""".Replace("\n", "\r\n");
    }

    static readonly string[] PmaTables =
    {
        "bookmark", "relation", "table_info", "table_coords", "pdf_pages", "column_info", "history", "table_uiprefs",
        "tracking", "userconfig", "recent", "users", "usergroups", "navigationhiding", "savedsearches",
        "central_columns", "designer_settings", "export_templates", "favorite",
    };

    /// <summary>config.inc.php de phpMyAdmin: como en XAMPP, entra como root sin contraseña (solo por 127.0.0.1).</summary>
    public static string PmaConfig(Disposicion l, Manifiesto m, Puertos p)
    {
        var secret = Convert.ToHexString(RandomNumberGenerator.GetBytes(16)).ToLowerInvariant();
        var tmp = Apache.Fwd(Path.Combine(l.TmpDir(m.Folder), "phpmyadmin"));
        var sb = new StringBuilder();
        sb.Append($$"""
<?php
// phpMyAdmin {{m.Pma}} de {{m.Folder}} (Nexum Dev Stack). Lo escribe el programa al instalar la versión.
declare(strict_types=1);

$cfg['blowfish_secret'] = '{{secret}}';

$i = 1;
$cfg['Servers'][$i]['auth_type'] = 'config';
$cfg['Servers'][$i]['user'] = 'root';
$cfg['Servers'][$i]['password'] = '';
$cfg['Servers'][$i]['host'] = '127.0.0.1';
$cfg['Servers'][$i]['port'] = '{{p.MariaDb}}';
$cfg['Servers'][$i]['connect_type'] = 'tcp';
$cfg['Servers'][$i]['AllowNoPassword'] = true;
$cfg['Servers'][$i]['controluser'] = 'pma';
$cfg['Servers'][$i]['controlpass'] = '';
$cfg['Servers'][$i]['pmadb'] = 'phpmyadmin';

""");
        foreach (var t in PmaTables)
            sb.Append($"$cfg['Servers'][$i]['{(t == "bookmark" ? "bookmarktable" : t)}'] = 'pma__{t}';\n");
        sb.Append($"""

$cfg['TempDir'] = '{tmp}';
$cfg['UploadDir'] = '';
$cfg['SaveDir'] = '';
$cfg['VersionCheck'] = false;

""");
        return sb.ToString().Replace("\n", "\r\n");
    }

    /// <summary>Usuario pma de phpMyAdmin (sin contraseña, solo en su base), como en Linux.</summary>
    public const string PmaUserSql =
        "CREATE USER IF NOT EXISTS 'pma'@'localhost'; GRANT SELECT, INSERT, UPDATE, DELETE ON phpmyadmin.* TO 'pma'@'localhost'; FLUSH PRIVILEGES;";
}
