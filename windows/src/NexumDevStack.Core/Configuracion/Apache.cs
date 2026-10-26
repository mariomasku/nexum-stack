using System.Text;
using NexumDevStack.Core.Pila;

namespace NexumDevStack.Core.Configuracion;

/// <summary>Puertos de los servicios (solo en 127.0.0.1 y ::1).</summary>
public sealed record Puertos(int Http = 80, int Https = 443, int MariaDb = 3306)
{
    public static readonly Puertos Default = new();
}

/// <summary>Configuración de Apache: httpd.conf de cada versión y la parte de seguridad compartida.</summary>
public static class Apache
{
    /// <summary>Ruta con barras normales, como la quiere Apache en Windows.</summary>
    public static string Fwd(string path) => path.Replace('\\', '/');

    /// <summary>Módulos que se cargan (los que existan en la carpeta modules de esa versión). Sin CGI.</summary>
    public static readonly string[] Modules =
    {
        "access_compat", "actions", "alias", "allowmethods", "auth_basic", "authn_core", "authn_file", "authz_core",
        "authz_groupfile", "authz_host", "authz_user", "autoindex", "brotli", "deflate", "dir", "env", "expires",
        "filter", "headers", "http2", "include", "log_config", "mime", "negotiation", "proxy", "proxy_fcgi",
        "proxy_http", "remoteip", "reqtimeout", "rewrite", "setenvif", "socache_shmcb", "ssl", "status", "version",
    };

    /// <summary>httpd.conf de una versión (va en versiones\php-X\conf, de administrador).</summary>
    public static string HttpdConf(Disposicion l, Manifiesto m, Puertos p, bool ipv6, IEnumerable<string> availableModules, string phpModuleDll)
    {
        var folder = m.Folder;
        var root = Fwd(l.Root);
        var ver = Fwd(l.VersionDir(folder));
        var logs = Fwd(l.LogDir(folder));
        var htdocs = Fwd(l.Htdocs);
        var available = new HashSet<string>(availableModules, StringComparer.OrdinalIgnoreCase);
        var sb = new StringBuilder();
        sb.Append($"""
# Apache {m.Apache} de {folder} (Nexum Dev Stack). Lo escribe el programa al instalar la versión: los
# cambios a mano se pierden al actualizarla. Lo compartido (vhosts, certificados, seguridad) está en
# {root}/config.
Define NEXUM_RAIZ "{root}"
Define NEXUM_VERSION "{ver}"
Define NEXUM_REGISTROS "{logs}"
ServerRoot "{ver}/apache"
# Solo desde este equipo
Listen 127.0.0.1:{p.Http}

""");
        if (ipv6)
            sb.Append($"Listen [::1]:{p.Http}\n");
        sb.Append('\n');
        foreach (var mod in Modules)
            if (available.Contains($"mod_{mod}.so"))
                sb.Append($"LoadModule {mod}_module modules/mod_{mod}.so\n");
        sb.Append($$"""

ServerAdmin admin@localhost
ServerName localhost:{{p.Http}}
PidFile "${NEXUM_REGISTROS}/httpd.pid"
# (lo que Apache crea al funcionar, en la carpeta de registros: la de la versión es de administrador)
DefaultRuntimeDir "${NEXUM_REGISTROS}"
Timeout 300
KeepAlive On
# Windows (mpm_winnt): lo mismo que XAMPP para que sea estable
ThreadsPerChild 150
MaxConnectionsPerChild 0
AcceptFilter http none
AcceptFilter https none
EnableSendfile Off
EnableMMAP Off

<Directory />
    AllowOverride None
    Require all denied
</Directory>

DocumentRoot "{{htdocs}}"
<Directory "{{htdocs}}">
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

DirectoryIndex index.php index.html index.htm

<Files ".ht*">
    Require all denied
</Files>

ErrorLog "${NEXUM_REGISTROS}/apache-error.log"
LogLevel warn
LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combined
LogFormat "%h %l %u %t \"%r\" %>s %b" common
CustomLog "${NEXUM_REGISTROS}/apache-access.log" common

TypesConfig conf/mime.types
AddType application/x-compress .Z
AddType application/x-gzip .gz .tgz
# Sin CGI: en los proyectos, un .cgi o un .pl no se ejecuta

<IfModule http2_module>
    Protocols h2 h2c http/1.1
</IfModule>

# PHP {{m.Php}} como módulo de Apache (Thread Safe, como XAMPP)
LoadModule {{(m.PhpMajor >= 8 ? "php_module" : "php7_module")}} "${NEXUM_VERSION}/php/{{phpModuleDll}}"
PHPIniDir "${NEXUM_VERSION}/php"
<FilesMatch "\.php$">
    SetHandler application/x-httpd-php
</FilesMatch>

# phpMyAdmin {{m.Pma}}, solo desde este equipo
Alias /phpmyadmin "${NEXUM_VERSION}/phpmyadmin"
<Directory "${NEXUM_VERSION}/phpmyadmin">
    AllowOverride AuthConfig Limit
    Require local
</Directory>

# HTTPS con un certificado autofirmado para localhost (los vhosts usan los suyos)
<IfModule ssl_module>
Listen 127.0.0.1:{{p.Https}}

""");
        if (ipv6)
            sb.Append($"Listen [::1]:{p.Https}\n");
        sb.Append("""
SSLCipherSuite HIGH:MEDIUM:!aNULL:!MD5
SSLProtocol all -SSLv3
SSLPassPhraseDialog builtin
SSLSessionCache "shmcb:${NEXUM_REGISTROS}/ssl_scache(512000)"
SSLSessionCacheTimeout 300
</IfModule>

# Antes de los vhosts: los dominios que no tienen ninguno solo pasan si son localhost, y las reglas de
# seguridad de todas las webs (barrera entre webs incluida)
Include "${NEXUM_RAIZ}/config/nexum-seguridad.conf"
Include "${NEXUM_RAIZ}/config/httpd-vhosts.conf"

""");
        return sb.ToString().Replace("\r\n", "\n");
    }

    // ------------------------------------------------------------------ seguridad (compartida)
    public const string CrossSiteStart = "# >>> barrera entre webs";
    public const string CrossSiteEnd = "# <<< barrera entre webs";

    /// <summary>
    /// config\nexum-seguridad.conf: el vhost de los dominios desconocidos (el primero del 80 y del 443), phpMyAdmin
    /// solo por 127.0.0.1 con sus comprobaciones de Host y Origin, lo que no se sirve (.env, .git, copias de BBDD…),
    /// la barrera entre webs y el límite de las peticiones. El mismo texto que lvm-dominio-desconocido.conf de Linux.
    /// </summary>
    public static string SecurityConf(Disposicion l, Puertos p, bool crossSite)
    {
        var crt = Fwd(Path.Combine(l.SslDir, "localhost.crt"));
        var key = Fwd(Path.Combine(l.SslDir, "localhost.key"));
        var empty = Fwd(l.EmptyProjectDir);
        var pmaPort = p.Http == 80 ? "" : ":" + p.Http;
        var text = $$"""
# Nexum Dev Stack: dominios que no tienen ningún vhost y seguridad de todas las webs. Lo escribe el
# programa (Configuración, barrera entre webs): los cambios a mano se pierden.
# Solo deja pasar localhost, 127.0.0.1 y [::1]. Cualquier otro dominio que apunte a este equipo (una web
# que intenta leer phpMyAdmin o los proyectos desde el navegador) recibe un 403.
# Para usar otro dominio, crea su vhost (pestaña Dominios y hosts o httpd-vhosts.conf).
<VirtualHost *:{{p.Http}}>
    ServerName localhost
    ServerAlias 127.0.0.1 [::1]
    <If "%{HTTP_HOST} !~ /^(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?$/">
        Require all denied
        ErrorDocument 403 "Este dominio no tiene vhost en este equipo (Nexum Dev Stack): crea su vhost o entra con localhost."
    </If>
    # En 127.0.0.1 y [::1] solo phpMyAdmin: los proyectos van en localhost
    <If "%{HTTP_HOST} =~ /^(127\.0\.0\.1|\[::1\])(:[0-9]+)?$/ && %{REQUEST_URI} !~ m#^/phpmyadmin(/|$)#">
        Require all denied
        ErrorDocument 403 "En 127.0.0.1 solo esta phpMyAdmin: los proyectos van en http://localhost/ (Nexum Dev Stack)"
    </If>
</VirtualHost>

# Lo mismo en HTTPS, con el certificado de localhost
<IfModule ssl_module>
<VirtualHost *:{{p.Https}}>
    ServerName localhost
    ServerAlias 127.0.0.1 [::1]
    SSLEngine on
    SSLCertificateFile "{{crt}}"
    SSLCertificateKeyFile "{{key}}"
    <If "%{HTTP_HOST} !~ /^(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?$/">
        Require all denied
        ErrorDocument 403 "Este dominio no tiene vhost en este equipo (Nexum Dev Stack): crea su vhost o entra con localhost."
    </If>
    <If "%{HTTP_HOST} =~ /^(127\.0\.0\.1|\[::1\])(:[0-9]+)?$/ && %{REQUEST_URI} !~ m#^/phpmyadmin(/|$)#">
        Require all denied
        ErrorDocument 403 "En 127.0.0.1 solo esta phpMyAdmin: los proyectos van en http://localhost/ (Nexum Dev Stack)"
    </If>
</VirtualHost>
</IfModule>

# phpMyAdmin tiene su propio origen: solo en http://127.0.0.1/phpmyadmin/ (o [::1]), donde no hay nada más.
# Los proyectos van en localhost/<carpeta>, web.local o sus dominios: un fallo XSS en uno de ellos no puede
# leer phpMyAdmin (es otro origen para el navegador)
<Location "/phpmyadmin">
    # Por localhost (un marcador antiguo, la costumbre de XAMPP), a su portada en 127.0.0.1: siempre la
    # misma dirección, sin lo que llevara detrás. Por cualquier otro dominio, un 403 con el aviso
    <If "%{HTTP_HOST} =~ /^localhost(:[0-9]+)?$/i">
        # (el ? del final: Redirect añadiría la consulta de antes)
        Redirect 302 "http://127.0.0.1{{pmaPort}}/phpmyadmin/?"
    </If>
    <ElseIf "%{HTTP_HOST} !~ /^(127\.0\.0\.1|\[::1\])(:[0-9]+)?$/">
        Require all denied
        ErrorDocument 403 "phpMyAdmin esta en http://127.0.0.1/phpmyadmin/ (Nexum Dev Stack)"
    </ElseIf>
    # Lo que manda otra web (un formulario o un fetch a 127.0.0.1): el navegador pone ese dominio y
    # phpMyAdmin, que entra como root sin contraseña, lo ejecutaría aunque la web no pueda leer la
    # respuesta. Desde otra web solo se puede abrir la portada con un enlace; escribiendo la dirección,
    # desde Nexum Dev Stack o dentro de phpMyAdmin, todo funciona igual
    <If "(%{HTTP:Sec-Fetch-Site} =~ /^(cross-site|same-site)$/i && !(%{REQUEST_METHOD} =~ /^(GET|HEAD)$/ && -z %{QUERY_STRING} && %{REQUEST_URI} =~ m#^/phpmyadmin/?(index\.php)?$#)) || (%{REQUEST_METHOD} !~ /^(GET|HEAD)$/ && -n %{HTTP:Origin} && %{HTTP:Origin} != 'http://' . %{HTTP_HOST} && %{HTTP:Origin} != 'https://' . %{HTTP_HOST})">
        Require all denied
        ErrorDocument 403 "Otra web ha intentado usar phpMyAdmin: no se ha hecho nada. Abrelo escribiendo http://127.0.0.1/phpmyadmin/ o desde Nexum Dev Stack."
    </If>
</Location>
# Su asistente setup y su configuración, cerrados (sin distinguir mayúsculas: Windows no las distingue y
# /phpmyadmin/Setup/ abriría setup/)
<LocationMatch "(?i)^/phpmyadmin/setup(/|$)">
    Require all denied
</LocationMatch>
<Files "config.inc.php">
    Require all denied
</Files>

# La página de «ningún proyecto cargado» (web.local sin proyecto)
<Directory "{{empty}}">
    Options None
    AllowOverride None
    Require all granted
</Directory>

# Configuración, repositorios, copias de bases y registros de los proyectos (.env, .git, .sql, .dump, .old,
# copias~, debug.log, error_log, auth.json de composer...): no se sirven. Sin distinguir mayúsculas (.ENV o
# .GIT en Windows). Tampoco los registros (.log), los .yml (docker-compose lleva las claves de la BBDD), las
# copias de wp-config.php ni las copias de seguridad de las webs (Duplicator, UpdraftPlus, All-in-One...), ni
# claves y certificados con su clave (.pem, .key, .p12), .ini, .conf o las exportaciones de clientes del
# módulo de boletín de PrestaShop (customers_export_*.csv) y de WP All Import/Export (su carpeta wpallimport,
# con los .zip y .xml de clientes). Tampoco claves de otros programas (.my.cnf, .netrc, .pgpass,
# credentials*.json, .aws, .docker)
<DirectoryMatch "(?i)/\.(git|svn|hg|vscode|idea|ssh|aws|docker)(/|$)">
    Require all denied
</DirectoryMatch>
<DirectoryMatch "(?i)/wp-content/uploads/(sites/[0-9]+/)?wpall(import|export)(/|$)">
    Require all denied
</DirectoryMatch>
<FilesMatch "(?i)(^\.(env.*|git.*|ht.*|envrc|ds_store|npmrc|my\.cnf|netrc|pgpass|s3cfg|mysql_history|bash_history)$|^(credentials|service-account|gcloud-credentials)[^/]*\.json$|\.(sql|sql\.(gz|zip|bz2|xz)|dump|bak|old|orig|save|swp|log|ya?ml|wpress)$|~$|^(debug\.log|error_log|auth\.json)$|^wp-config(?!(\.php|-sample\.php)$)|^(backup|copia|respaldo|bkp)([-_.][^/]*)?\.(zip|tar|tgz|gz|bz2|xz|7z|rar)$|_archive\.(zip|daf)$|wpvivid[^/]*\.(zip|tar|gz)$|\.(pem|key|p12|pfx|jks|ini|conf|sqlite|sqlite3|db)$|^id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$|^customers_export_[^/]*\.(csv|zip|xml|xlsx?)$)">
    Require all denied
</FilesMatch>

# Una web de fuera no puede leer las respuestas de tus proyectos: WordPress responde a cualquier origen
# en su API (Access-Control-Allow-Origin), y se quita si el origen no es la propia web
<IfModule headers_module>
    <If "-n %{HTTP:Origin} && %{HTTP:Origin} != 'http://' . %{HTTP_HOST} && %{HTTP:Origin} != 'https://' . %{HTTP_HOST}">
        Header unset Access-Control-Allow-Origin
        Header always unset Access-Control-Allow-Origin
        Header unset Access-Control-Allow-Credentials
        Header always unset Access-Control-Allow-Credentials
    </If>
</IfModule>

# Barrera entre webs, en todas (localhost, web.local, los dominios falseados y los vhosts de los proyectos):
# otra web abierta en el navegador no puede mandar nada a tus proyectos con tus sesiones (un formulario o
# un fetch a https://tienda.local/admin/...). Desde otro sitio (Sec-Fetch-Site: cross-site) solo se puede
# abrir una página con un enlace (GET o HEAD, de navegación), y un POST, PUT o DELETE solo vale desde la
# propia web (su Origin). Una pasarela de pago que vuelve a la tienda con un POST no pasa: se apaga en
# Configuración (o NexumDevStack.exe barrera-web no) mientras se prueba (los navegadores mandan
# Sec-Fetch-Mode y Sec-Fetch-Dest con Sec-Fetch-Site: si faltan, cuenta como enlace)
{{CrossSiteStart}}
<If "(%{HTTP:Sec-Fetch-Site} =~ /^cross-site$/i && !(%{REQUEST_METHOD} =~ /^(GET|HEAD)$/ && (-z %{HTTP:Sec-Fetch-Mode} || %{HTTP:Sec-Fetch-Mode} =~ /^navigate$/i) && (-z %{HTTP:Sec-Fetch-Dest} || %{HTTP:Sec-Fetch-Dest} =~ /^document$/i))) || (%{REQUEST_METHOD} !~ /^(GET|HEAD)$/ && -n %{HTTP:Origin} && %{HTTP:Origin} != 'http://' . %{HTTP_HOST} && %{HTTP:Origin} != 'https://' . %{HTTP_HOST})">
    Require all denied
    ErrorDocument 403 "Otra web ha intentado mandar algo a esta: no se ha hecho nada (barrera entre webs de Nexum Dev Stack). Si es una pasarela de pago que vuelve a la tienda, apaga la barrera en Configuracion mientras la pruebas."
</If>
{{CrossSiteEnd}}
# Peticiones de 64 MB como mucho (lo mismo que post_max_size y upload_max_filesize de PHP)
LimitRequestBody 67108864
TraceEnable Off

""";
        text = text.Replace("\r\n", "\n");
        if (!crossSite)
        {
            var start = text.IndexOf(CrossSiteStart, StringComparison.Ordinal);
            var end = text.IndexOf(CrossSiteEnd, StringComparison.Ordinal);
            if (start >= 0 && end > start)
                text = text[..start] + text[(end + CrossSiteEnd.Length + 1)..];
        }
        return text;
    }
}
