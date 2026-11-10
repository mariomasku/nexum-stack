# ===========================================================================
# Seguridad: los servicios, solo para este equipo
# ===========================================================================
# XAMPP deja Apache, MariaDB y ProFTPD escuchando en todas las interfaces: cualquier equipo de la
# red veria los proyectos de los clientes, llegaria a MariaDB y entraria por FTP en htdocs (XAMPP
# trae el usuario daemon con la contraseña xampp). Se dejan solo para este equipo (127.0.0.1 y
# ::1), el FTP deja de arrancar con la version (se activa en la pestaña Servicios cuando haga
# falta, por ejemplo para que WordPress instale plugins) y los vhosts vuelven a ser de root. Como
# con User/Group, solo se cambia lo que falta; lo anterior queda en ~/nexum-backups
# si esta el ajuste copias-ficheros.
SECURE_MARK=etc/lvm-seguridad

# Mitigaciones de PHP2Shell (CVE-2026-109618 y CVE-2026-109619) en el PHP de todas las pilas, tambien
# en las que ya llevan el arreglo: sin el progreso de las subidas en la sesion, poco anidamiento en las
# variables de la peticion, peticiones de 64 MB como mucho y sin decir la version de PHP. SECURE_PY
# las pone en las versiones instaladas (las recibe en LVM_PHP_INI y LVM_PHP_INI_85)
PHP_SECURE_INI="session.upload_progress.enabled = Off
max_input_nesting_level = 6
post_max_size = 64M
upload_max_filesize = 64M
expose_php = Off"
# (solo desde PHP 8.5: sin la traza de las llamadas en los errores fatales)
PHP_SECURE_INI_85="fatal_error_backtraces = 0"

# ¿Es la rama X.Y de PHP la 8.5 o posterior?
function php_85_or_later() {
    [ "$(printf '%s\n' 8.5 "$1" | sort -V | head -1)" == 8.5 ]
}

# Fichero conf.d/99-lvm-seguridad.ini de una pila propia (el mismo que escribe SECURE_PY)
function php_secure_ini_file() {
    printf '; lvm-instalador: mitigaciones de PHP2Shell (CVE-2026-109618 y CVE-2026-109619)\n%s\n' "$PHP_SECURE_INI"
    php_85_or_later "${1%.*}" && printf '%s\n' "$PHP_SECURE_INI_85"
    return 0
}

# ¿Tiene el equipo la direccion ::1? (sin ella, Apache no arrancaria con Listen [::1]:80)
function has_ipv6_loopback() {
    grep -q '^0\{31\}1 ' /proc/net/if_inet6 2> /dev/null
}

# Primer vhost del puerto 80: Apache le pasa las peticiones cuyo dominio no tiene ningun vhost. Una web
# cualquiera puede hacer que su dominio apunte a 127.0.0.1 (DNS rebinding) y entonces su JavaScript
# leeria phpMyAdmin (root sin contraseña) y los proyectos desde el navegador. Solo deja pasar
# localhost, 127.0.0.1 y [::1] (la carpeta htdocs y phpMyAdmin); el resto recibe un 403. Los vhosts
# por nombre (web.local, los dominios falseados) no pasan por aqui. HTTPS no lo necesita: el
# certificado no vale para el dominio de fuera y el navegador corta la conexion.
UNKNOWN_HOST_CONF=etc/extra/lvm-dominio-desconocido.conf
# Ademas, para todas las webs: phpMyAdmin (root sin contraseña) solo desde localhost (un fallo XSS
# en un proyecto antiguo no puede usarlo desde su dominio), su asistente setup cerrado, y los .env
# y repositorios .git de los proyectos no se sirven. El vhost del 443 se añade (SECURE_PY) si la
# version tiene el certificado de localhost.
UNKNOWN_HOST_VHOST='# lvm-instalador: dominios que no tienen ningun vhost (va antes de httpd-vhosts.conf)
# Solo deja pasar localhost, 127.0.0.1 y [::1]. Cualquier otro dominio que apunte a este equipo
# (una web que intenta leer phpMyAdmin o los proyectos desde el navegador) recibe un 403.
# Para usar otro dominio, crea su vhost (pestaña Hosts o httpd-vhosts.conf).
<VirtualHost *:80>
    ServerName localhost
    ServerAlias 127.0.0.1 [::1]
    <If "%{HTTP_HOST} !~ /^(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?$/">
        Require all denied
        ErrorDocument 403 "Este dominio no tiene vhost en este equipo (lvm-instalador): crea su vhost o entra con localhost."
    </If>
    # En 127.0.0.1 y [::1] solo phpMyAdmin: los proyectos van en localhost
    <If "%{HTTP_HOST} =~ /^(127\.0\.0\.1|\[::1\])(:[0-9]+)?$/ && %{REQUEST_URI} !~ m#^/phpmyadmin(/|$)#">
        Require all denied
        ErrorDocument 403 "En 127.0.0.1 solo esta phpMyAdmin: los proyectos van en http://localhost/ (lvm-instalador)"
    </If>
</VirtualHost>

# phpMyAdmin tiene su propio origen: solo en http://127.0.0.1/phpmyadmin/ (o [::1]), donde no hay
# nada mas. Los proyectos van en localhost/<carpeta>, web.local o sus dominios: un fallo XSS en uno
# de ellos no puede leer phpMyAdmin (es otro origen para el navegador)
<Location "/phpmyadmin">
    # Por localhost (un marcador antiguo, la costumbre de XAMPP), a su portada en 127.0.0.1: siempre
    # la misma direccion, sin lo que llevara detras. Por cualquier otro dominio, un 403 con el aviso
    <If "%{HTTP_HOST} =~ /^localhost(:[0-9]+)?$/i">
        # (el ? del final: Redirect añadiria la consulta de antes)
        Redirect 302 "http://127.0.0.1/phpmyadmin/?"
    </If>
    <ElseIf "%{HTTP_HOST} !~ /^(127\.0\.0\.1|\[::1\])(:[0-9]+)?$/">
        Require all denied
        ErrorDocument 403 "phpMyAdmin esta en http://127.0.0.1/phpmyadmin/ (lvm-instalador)"
    </ElseIf>
    # Lo que manda otra web (un formulario o un fetch a 127.0.0.1): el navegador pone ese dominio y
    # phpMyAdmin, que entra como root sin contraseña, lo ejecutaria aunque la web no pueda leer la
    # respuesta. Desde otra web solo se puede abrir la portada con un enlace; escribiendo la
    # direccion, desde lvm-instalador o dentro de phpMyAdmin, todo funciona igual
    <If "(%{HTTP:Sec-Fetch-Site} =~ /^(cross-site|same-site)$/i && !(%{REQUEST_METHOD} =~ /^(GET|HEAD)$/ && -z %{QUERY_STRING} && %{REQUEST_URI} =~ m#^/phpmyadmin/?(index\.php)?$#)) || (%{REQUEST_METHOD} !~ /^(GET|HEAD)$/ && -n %{HTTP:Origin} && %{HTTP:Origin} != '"'"'http://'"'"' . %{HTTP_HOST} && %{HTTP:Origin} != '"'"'https://'"'"' . %{HTTP_HOST})">
        Require all denied
        ErrorDocument 403 "Otra web ha intentado usar phpMyAdmin: no se ha hecho nada. Abrelo escribiendo http://127.0.0.1/phpmyadmin/ o desde lvm-instalador."
    </If>
</Location>
# Su asistente setup y su configuracion, cerrados (sin distinguir mayusculas: en el Mac el disco
# no las distingue y /phpmyadmin/Setup/ abriria setup/)
<LocationMatch "(?i)^/phpmyadmin/setup(/|$)">
    Require all denied
</LocationMatch>
<Files "config.inc.php">
    Require all denied
</Files>

# Configuracion, repositorios, copias de bases y registros de los proyectos (.env, .git, .sql,
# .dump, .old, copias~, debug.log, error_log, auth.json de composer...): no se sirven. Sin distinguir mayusculas (.ENV o .GIT en el Mac)
# Tampoco los registros (.log), los .yml (docker-compose lleva las claves de la BBDD), las copias
# de wp-config.php ni las copias de seguridad de las webs (Duplicator, UpdraftPlus, All-in-One...),
# ni claves y certificados con su clave (.pem, .key, .p12), .ini, .conf o las exportaciones de clientes
# del modulo de boletin de PrestaShop (customers_export_*.csv) y de WP All Import/Export (su carpeta
# wpallimport, con los .zip y .xml de clientes). Tampoco claves de otros programas (.my.cnf, .netrc,
# .pgpass, credentials*.json, .aws, .docker)
<DirectoryMatch "(?i)/\.(git|svn|hg|vscode|idea|ssh|aws|docker)(/|$)">
    Require all denied
</DirectoryMatch>
<DirectoryMatch "(?i)/wp-content/uploads/(sites/[0-9]+/)?wpall(import|export)(/|$)">
    Require all denied
</DirectoryMatch>
<FilesMatch "(?i)(^\.(env.*|git.*|ht.*|envrc|ds_store|npmrc|my\.cnf|netrc|pgpass|s3cfg|mysql_history|bash_history)$|^(credentials|service-account|gcloud-credentials)[^/]*\.json$|\.(sql|sql\.(gz|zip|bz2|xz)|dump|bak|old|orig|save|swp|log|ya?ml|wpress)$|~$|^(debug\.log|error_log|auth\.json)$|^wp-config(?!(\.php|-sample\.php)$)|^(backup|copia|respaldo|bkp)([-_.][^/]*)?\.(zip|tar|tgz|gz|bz2|xz|7z|rar)$|_archive\.(zip|daf)$|wpvivid[^/]*\.(zip|tar|gz)$|\.(pem|key|p12|pfx|jks|ini|conf|sqlite|sqlite3|db)$|^id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$|^customers_export_[^/]*\.(csv|zip|xml|xlsx?)$)">
    Require all denied
</FilesMatch>

# Una web de fuera no puede leer las respuestas de tus proyectos: WordPress responde a cualquier
# origen en su API (Access-Control-Allow-Origin), y se quita si el origen no es la propia web
<IfModule headers_module>
    <If "-n %{HTTP:Origin} && %{HTTP:Origin} != '"'"'http://'"'"' . %{HTTP_HOST} && %{HTTP:Origin} != '"'"'https://'"'"' . %{HTTP_HOST}">
        Header unset Access-Control-Allow-Origin
        Header always unset Access-Control-Allow-Origin
        Header unset Access-Control-Allow-Credentials
        Header always unset Access-Control-Allow-Credentials
    </If>
</IfModule>

# Barrera entre webs, en todas (localhost, web.local, los dominios falseados y los vhosts de los
# proyectos): otra web abierta en el navegador no puede mandar nada a tus proyectos con tus sesiones
# (un formulario o un fetch a https://tienda.local/admin/...). Desde otro sitio (Sec-Fetch-Site:
# cross-site) solo se puede abrir una pagina con un enlace (GET o HEAD, de navegacion), y un POST,
# PUT o DELETE solo vale desde la propia web (su Origin). Una pasarela de pago que vuelve a la tienda
# con un POST no pasa: se apaga en Configuracion (o lvm-instalador barrera-web no) mientras se prueba
# (los navegadores mandan Sec-Fetch-Mode y Sec-Fetch-Dest con Sec-Fetch-Site: si faltan, cuenta como enlace)
# >>> barrera entre webs
<If "(%{HTTP:Sec-Fetch-Site} =~ /^cross-site$/i && !(%{REQUEST_METHOD} =~ /^(GET|HEAD)$/ && (-z %{HTTP:Sec-Fetch-Mode} || %{HTTP:Sec-Fetch-Mode} =~ /^navigate$/i) && (-z %{HTTP:Sec-Fetch-Dest} || %{HTTP:Sec-Fetch-Dest} =~ /^document$/i))) || (%{REQUEST_METHOD} !~ /^(GET|HEAD)$/ && -n %{HTTP:Origin} && %{HTTP:Origin} != '"'"'http://'"'"' . %{HTTP_HOST} && %{HTTP:Origin} != '"'"'https://'"'"' . %{HTTP_HOST})">
    Require all denied
    ErrorDocument 403 "Otra web ha intentado mandar algo a esta: no se ha hecho nada (barrera entre webs de lvm-instalador). Si es una pasarela de pago que vuelve a la tienda, apaga la barrera en Configuracion mientras la pruebas."
</If>
# <<< barrera entre webs
# Peticiones de 64 MB como mucho (lo mismo que post_max_size y upload_max_filesize de PHP)
LimitRequestBody 67108864
TraceEnable Off
'
UNKNOWN_HOST_SSL='
# Lo mismo en HTTPS, con el certificado de localhost de la version
<IfModule ssl_module>
<VirtualHost *:443>
    ServerName localhost
    ServerAlias 127.0.0.1 [::1]
    SSLEngine on
    SSLCertificateFile "etc/ssl.crt/server.crt"
    SSLCertificateKeyFile "etc/ssl.key/server.key"
    <If "%{HTTP_HOST} !~ /^(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?$/">
        Require all denied
        ErrorDocument 403 "Este dominio no tiene vhost en este equipo (lvm-instalador): crea su vhost o entra con localhost."
    </If>
    # En 127.0.0.1 y [::1] solo phpMyAdmin: los proyectos van en localhost
    <If "%{HTTP_HOST} =~ /^(127\.0\.0\.1|\[::1\])(:[0-9]+)?$/ && %{REQUEST_URI} !~ m#^/phpmyadmin(/|$)#">
        Require all denied
        ErrorDocument 403 "En 127.0.0.1 solo esta phpMyAdmin: los proyectos van en http://localhost/ (lvm-instalador)"
    </If>
</VirtualHost>
</IfModule>
'
# Barrera entre webs (Configuracion): encendida salvo que exista este fichero. Apagada, el
# lvm-dominio-desconocido.conf de cada version se escribe sin ella (SECURE_PY lo rehace al cambiarla)
CROSS_SITE_OFF="$LOG_DIR/sin-barrera-entre-webs"
function cross_site_on() {
    [ ! -e "$CROSS_SITE_OFF" ]
}

# Texto de lvm-dominio-desconocido.conf con la barrera entre webs o sin ella: lo deja en HOST_VHOST
function host_vhost() {
    HOST_VHOST=$UNKNOWN_HOST_VHOST
    cross_site_on && return 0
    HOST_VHOST=${UNKNOWN_HOST_VHOST%%"# >>> barrera entre webs"*}${UNKNOWN_HOST_VHOST#*"# <<< barrera entre webs"$'\n'}
}

