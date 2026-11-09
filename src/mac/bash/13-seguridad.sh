# ===========================================================================
# Seguridad: los servicios, solo para este Mac
# ===========================================================================
# Las versiones instaladas antes de la 1.16.0 escuchan en todas las interfaces: cualquier equipo de
# la red (la de la oficina o una wifi publica) veria los proyectos de los clientes, llegaria a
# MariaDB (root sin contraseña) y entraria por FTP en htdocs con la contraseña del Mac, que viaja
# sin cifrar. Se dejan solo para este Mac (127.0.0.1 y ::1), el FTP deja de arrancar con la version
# (se activa en la pestaña Servicios cuando haga falta) y los vhosts vuelven a ser de root. Solo
# se cambia lo que falta; lo anterior queda en ~/lvm-copias.
SECURE_MARK=xamppfiles/etc/lvm-seguridad

# Primer vhost del puerto 80: Apache le pasa las peticiones cuyo dominio no tiene ningun vhost. Una web
# cualquiera puede hacer que su dominio apunte a 127.0.0.1 (DNS rebinding) y entonces su JavaScript
# leeria phpMyAdmin (root sin contraseña) y los proyectos desde el navegador. Solo deja pasar
# localhost, 127.0.0.1 y [::1] (la carpeta htdocs y phpMyAdmin); el resto recibe un 403. Los vhosts
# por nombre (web.local, los dominios falseados) no pasan por aqui. HTTPS no lo necesita: el
# certificado no vale para el dominio de fuera y el navegador corta la conexion.
UNKNOWN_HOST_CONF=etc/extra/lvm-dominio-desconocido.conf
UNKNOWN_HOST_VHOST='# lvm-instalador: dominios que no tienen ningun vhost (va antes de httpd-vhosts.conf)
# Solo deja pasar localhost, 127.0.0.1 y [::1]. Cualquier otro dominio que apunte a este Mac
# (una web que intenta leer phpMyAdmin o los proyectos desde el navegador) recibe un 403.
# Para usar otro dominio, crea su vhost (pestaña Hosts o httpd-vhosts.conf).
<VirtualHost *:80>
    ServerName localhost
    ServerAlias 127.0.0.1 [::1]
    <If "%{HTTP_HOST} !~ /^(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?$/">
        Require all denied
        ErrorDocument 403 "Este dominio no tiene vhost en este Mac (lvm-instalador): crea su vhost o entra con localhost."
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
TraceEnable Off
# Peticiones de como mucho 64 MB (PHP2Shell, CVE-2026-109618/109619: cuerpos enormes para PHP).
# Un vhost puede subirlo con su propio LimitRequestBody
LimitRequestBody 67108864
# lvm-barrera-web: lo que manda otra web a cualquier proyecto (se apaga en Configuración o con
# lvm-instalador barrera-web no). Desde otra web solo se puede abrir una pagina (un enlace: GET o
# HEAD de la pagina entera); un formulario, un fetch, un iframe o una imagen de otra web no llega.
# Y un POST (o PUT, DELETE...) con el Origin de otra web, tampoco. Ojo: la vuelta de una pasarela de
# pago que hace un POST desde su web se corta mientras este puesta
<If "(%{HTTP:Sec-Fetch-Site} =~ /^cross-site$/i && !(%{REQUEST_METHOD} =~ /^(GET|HEAD)$/ && %{HTTP:Sec-Fetch-Mode} =~ /^(navigate)?$/i && %{HTTP:Sec-Fetch-Dest} =~ /^(document)?$/i)) || (%{REQUEST_METHOD} !~ /^(GET|HEAD)$/ && -n %{HTTP:Origin} && %{HTTP:Origin} != '"'"'http://'"'"' . %{HTTP_HOST} && %{HTTP:Origin} != '"'"'https://'"'"' . %{HTTP_HOST})">
    Require all denied
    ErrorDocument 403 "Otra web ha intentado mandar algo a este proyecto: no se ha hecho nada (barrera entre webs de lvm-instalador; se apaga en Configuracion)."
</If>
# /lvm-barrera-web
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
        ErrorDocument 403 "Este dominio no tiene vhost en este Mac (lvm-instalador): crea su vhost o entra con localhost."
    </If>
    # En 127.0.0.1 y [::1] solo phpMyAdmin: los proyectos van en localhost
    <If "%{HTTP_HOST} =~ /^(127\.0\.0\.1|\[::1\])(:[0-9]+)?$/ && %{REQUEST_URI} !~ m#^/phpmyadmin(/|$)#">
        Require all denied
        ErrorDocument 403 "En 127.0.0.1 solo esta phpMyAdmin: los proyectos van en http://localhost/ (lvm-instalador)"
    </If>
</VirtualHost>
</IfModule>
'

# Barrera entre webs (el bloque lvm-barrera-web de UNKNOWN_HOST_VHOST): puesta salvo que se haya
# apagado. Lo apagado es un fichero de root en XAMPP-compartido: lo que lleva el Apache de todas las
# versiones (que arranca como root) no lo puede cambiar un programa tuyo
WEB_BARRIER_OFF=$COMMON/lvm-sin-barrera-web
function web_barrier_on() {
    [ -f "$WEB_BARRIER_OFF" ] && [ ! -L "$WEB_BARRIER_OFF" ] || return 0
    # (en las pruebas sin sudo vale cualquier fichero)
    [ -n "$TEST_DIR" ] && return 1
    [ "$(stat -f %u "$WEB_BARRIER_OFF" 2> /dev/null)" == 0 ] && return 1
    return 0
}

# UNKNOWN_HOST_VHOST tal cual o, con la barrera apagada, sin su bloque (siempre acaba en salto de linea)
function unknown_host_vhost() {
    if web_barrier_on; then
        printf '%s' "$UNKNOWN_HOST_VHOST"
    else
        awk '/^# lvm-barrera-web:/ { skip = 1 } !skip { print } /^# \/lvm-barrera-web$/ { skip = 0 }' <<< "${UNKNOWN_HOST_VHOST%$'\n'}"
    fi
}

# barrera-web si|no: pone o quita la barrera entre webs en todas las versiones (y reinicia Apache
# de la activa si esta en marcha). Sin argumento, dice como esta
function web_barrier_command() {
    # (si hay que cambiarla: la contraseña antes de nada; cancelarla la deja como estaba)
    if { [ "$1" == si ] && ! web_barrier_on; } || { [ "$1" == no ] && web_barrier_on; }; then
        sudo_first || return 1
    fi
    case "$1" in
        "")
            web_barrier_on && echo "Barrera entre webs: puesta" || echo "Barrera entre webs: apagada"
            return 0 ;;
        si|no) ;;
        *) echo "Uso: lvm-instalador barrera-web [si|no]"; return 1 ;;
    esac
    if [ "$1" == si ]; then
        web_barrier_on && { echo "La barrera entre webs ya esta puesta"; return 0; }
        echo "Barrera entre webs: se pone en todas las versiones"
        run $SUDO rm -f "$WEB_BARRIER_OFF" || return 1
    else
        web_barrier_on || { echo "La barrera entre webs ya esta apagada"; return 0; }
        echo "Barrera entre webs: se apaga en todas las versiones (otras webs podran volver a mandar"
        echo "formularios a tus proyectos, como la vuelta de una pasarela de pago)"
        if [ "$DRY" -eq 0 ]; then
            [ -d "$COMMON" ] || { echo "No existe $COMMON (se crea al instalar la primera version)"; return 1; }
            echo "Apagada con lvm-instalador barrera-web no" | $SUDO tee "$WEB_BARRIER_OFF" > /dev/null || return 1
            [ -z "$SUDO" ] || $SUDO chmod 644 "$WEB_BARRIER_OFF" || return 1
        fi
    fi
    [ "$DRY" -eq 1 ] && return 0
    secure_all
    if [ $? -eq 2 ]; then
        # (no se ha podido aplicar: el interruptor vuelve a como estaba)
        if [ "$1" == si ]; then
            echo "Apagada con lvm-instalador barrera-web no" | $SUDO tee "$WEB_BARRIER_OFF" > /dev/null
            [ -z "$SUDO" ] || $SUDO chmod 644 "$WEB_BARRIER_OFF"
        else
            $SUDO rm -f "$WEB_BARRIER_OFF"
        fi
        secure_all > /dev/null 2>&1
        echo "No se ha podido cambiar en todas las versiones: se deja como estaba"
        return 1
    fi
    if [ -n "$(active_dir)" ] && [ -f "$LINK/xamppfiles/logs/httpd.pid" ]; then
        echo "Recargando Apache de la version activa..."
        xampp_ctl reloadapache > /dev/null || { echo "No se ha podido recargar Apache: reinicia la version activa."; return 1; }
    fi
    echo "Listo"
}

# PHP de las pilas propias contra PHP2Shell (CVE-2026-109618 y CVE-2026-109619): la subida de
# ficheros con el progreso de la sesion, los arrays muy anidados y los cuerpos enormes, sin decir la
# version de PHP. Lo escriben install_stack y SECURE_PY (las versiones ya instaladas)
PHP_SECURITY_INI='; lvm-instalador: PHP2Shell (CVE-2026-109618 y CVE-2026-109619)
; Va despues de 99-xampp.ini: estos valores mandan. Lo rehace lvm-instalador asegurar
session.upload_progress.enabled = Off
max_input_nesting_level = 6
post_max_size = 64M
upload_max_filesize = 64M
expose_php = Off
'
# (desde PHP 8.5: sin la traza de los errores fatales, que llevaria los argumentos)
PHP_SECURITY_INI_85='fatal_error_backtraces = 0
'

