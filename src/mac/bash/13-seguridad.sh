# ===========================================================================
# Seguridad: los servicios, solo para este Mac
# ===========================================================================
# Las versiones instaladas antes de la 1.16.0 escuchan en todas las interfaces: cualquier equipo de
# la red (la de la oficina o una wifi publica) veria los proyectos de los clientes, llegaria a
# MariaDB (root sin contraseña) y entraria por FTP en htdocs con la contraseña del Mac, que viaja
# sin cifrar. Se dejan solo para este Mac (127.0.0.1 y ::1), el FTP deja de arrancar con la version
# (se activa en la pestaña Servicios cuando haga falta) y los vhosts vuelven a ser de root. Solo
# se cambia lo que falta; lo anterior queda en ~/nexum-backups
# si esta el ajuste copias-ficheros.
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
    # direccion, desde nexum o dentro de phpMyAdmin, todo funciona igual
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
    <If "-n %{HTTP:Origin} && %{HTTP:Origin} != '"'"'http://'"'"' . %{HTTP_HOST} && %{HTTP:Origin} != '"'"'https://'"'"' . %{HTTP_HOST} && %{HTTP:Origin} !~ m#^https?://(lvm-permitidas\.invalid)(:[0-9]+)?$#i">
        Header unset Access-Control-Allow-Origin
        Header always unset Access-Control-Allow-Origin
        Header unset Access-Control-Allow-Credentials
        Header always unset Access-Control-Allow-Credentials
    </If>
    # Las tipografias de un proyecto, para su copia en Docker y al reves (las de Elementor llevan la
    # direccion de la web que genero sus CSS: la de LAMPP o la de Docker). Solo tipografias, y solo con
    # una de las dos webs en Docker (*.docker.test, *.docker.local), como lo que deja pasar la barrera
    <If "%{REQUEST_URI} =~ m#\.(woff2?|ttf|otf|eot)$#i && %{HTTP:Origin} =~ m#^https?://[a-z0-9.-]+(:[0-9]+)?$#i && (%{HTTP:Origin} =~ m#^https://[a-z0-9.-]+\.docker\.(test|local)(:[0-9]+)?$#i || %{HTTP_HOST} =~ m#\.docker\.(test|local)(:[0-9]+)?$#i)">
        Header always set Access-Control-Allow-Origin "expr=%{HTTP:Origin}"
        Header always merge Vary Origin
    </If>
</IfModule>

# Dominios reales (los que no son .local, .test ni localhost): sin falsear son la web de produccion.
# Lo que el navegador reciba de tu copia con ese nombre mientras esta falseado (una redireccion 301 a
# web.local, una pagina) no lo guarda: si no, al dejar de falsearlo seguiria yendo a tu copia (o a
# web.local) en vez de a la web de verdad
<IfModule headers_module>
    <If "%{HTTP_HOST} !~ /(^|\.)(local|localhost|test)(:[0-9]+)?$/ && %{HTTP_HOST} !~ /^(127\.0\.0\.1|\[::1\])(:[0-9]+)?$/">
        Header set Cache-Control "no-store"
        Header always set Cache-Control "no-store"
        Header unset Expires
        Header always unset Expires
    </If>
</IfModule>
TraceEnable Off
# Peticiones de como mucho 64 MB (PHP2Shell, CVE-2026-109618/109619: cuerpos enormes para PHP).
# Un vhost puede subirlo con su propio LimitRequestBody
LimitRequestBody 67108864
# lvm-barrera-web: lo que manda otra web a cualquier proyecto (se apaga en Configuración o con
# nexum barrera-web no). Desde otra web solo se puede abrir una pagina (un enlace: GET o
# HEAD de la pagina entera); un formulario, un fetch, un iframe o una imagen de otra web no llega.
# Y un POST (o PUT, DELETE...) con el Origin de otra web, tampoco. Ojo: la vuelta de una pasarela de
# pago que hace un POST desde su web se corta mientras este puesta
# Lo unico que pasa de otra web ademas: enviar el formulario de acceso (POST de pagina entera a
# /wp-login.php o a index.php?controller=AdminLogin), que es lo que hace la pagina del boton Panel
# (un fichero: Origin null); sin la contraseña no entra nadie
# Y lo que se piden un proyecto y su copia en Docker: tipografias, imagenes y CSS (GET o HEAD, de un
# fichero con esa extension y que el navegador pide como tal), con una de las dos webs en Docker
# (*.docker.test, *.docker.local). Elementor guarda en sus CSS la direccion de la web que los genero
<If "((%{HTTP:Sec-Fetch-Site} =~ /^cross-site$/i && !(%{REQUEST_METHOD} =~ /^(GET|HEAD)$/ && %{HTTP:Sec-Fetch-Mode} =~ /^(navigate)?$/i && %{HTTP:Sec-Fetch-Dest} =~ /^(document)?$/i)) || (%{REQUEST_METHOD} !~ /^(GET|HEAD)$/ && -n %{HTTP:Origin} && %{HTTP:Origin} != '"'"'http://'"'"' . %{HTTP_HOST} && %{HTTP:Origin} != '"'"'https://'"'"' . %{HTTP_HOST})) && !(%{REQUEST_METHOD} =~ /^POST$/ && %{HTTP:Sec-Fetch-Mode} =~ /^navigate$/i && %{HTTP:Sec-Fetch-Dest} =~ /^document$/i && ((%{REQUEST_URI} =~ m#/wp-login\.php$# && -z %{QUERY_STRING}) || (%{REQUEST_URI} =~ m#/index\.php$# && %{QUERY_STRING} =~ /^controller=AdminLogin$/))) && !(%{REQUEST_METHOD} =~ /^(GET|HEAD)$/ && %{HTTP:Sec-Fetch-Dest} =~ /^(font|image|style)$/i && %{REQUEST_URI} =~ m#\.(woff2?|ttf|otf|eot|css|png|jpe?g|gif|webp|avif|svg|ico)$#i && (%{HTTP:Origin} =~ m#^https://[a-z0-9.-]+\.docker\.(test|local)(:[0-9]+)?$#i || %{HTTP_REFERER} =~ m#^https://[a-z0-9.-]+\.docker\.(test|local)(:[0-9]+)?/#i || %{HTTP_HOST} =~ m#\.docker\.(test|local)(:[0-9]+)?$#i)) && !(%{HTTP:Origin} =~ m#^https?://(lvm-permitidas\.invalid)(:[0-9]+)?$#i || %{HTTP_REFERER} =~ m#^https?://(lvm-permitidas\.invalid)(:[0-9]+)?(/|$)#i)">
    Require all denied
    ErrorDocument 403 "Otra web ha intentado mandar algo a este proyecto: no se ha hecho nada (barrera entre webs de lvm-instalador; se apaga en Configuracion). Si es una web tuya de confianza (tu ERP), añadela en Configuracion, Webs permitidas."
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

# Webs permitidas (Configuracion, Seguridad entre webs; nexum barrera-web permitir <dominio>): las tuyas
# de confianza, como el ERP de la empresa, que si pueden mandar formularios a tus proyectos, llevarte a su
# back office con un POST, abrirlos en un iframe o hacerles peticiones (fetch). Un dominio por linea; *.empresa.com
# vale para empresa.com y todos sus subdominios. Es del administrador, como el de la barrera apagada (un
# programa tuyo no puede añadir la suya). Sin ninguna, el hueco de la barrera lleva un dominio que no
# existe (lvm-permitidas.invalid)
WEB_BARRIER_ALLOW=$COMMON/lvm-barrera-permitidas
WEB_BARRIER_SLOT='lvm-permitidas\.invalid'
WEB_BARRIER_ALLOW_RE='^(\*\.)?[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$'
function web_barrier_allowed() {
    [ -f "$WEB_BARRIER_ALLOW" ] && [ ! -L "$WEB_BARRIER_ALLOW" ] || return 0
    # (en las pruebas sin sudo vale cualquier fichero)
    [ -n "$TEST_DIR" ] || [ "$(stat -f %u "$WEB_BARRIER_ALLOW" 2> /dev/null)" == 0 ] || return 0
    grep -E "$WEB_BARRIER_ALLOW_RE" "$WEB_BARRIER_ALLOW" 2> /dev/null | LC_ALL=C sort -u
}

# Un dominio tal como se escribe (o pegado de la barra del navegador: https://erp.empresa.com/login) en la
# forma de la lista: sin el protocolo, la ruta, el puerto ni el punto final, en minusculas. Vacio si no vale
function web_barrier_domain() {
    local d
    d=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    d=${d#*://}
    d=${d%%/*}
    d=${d%%\?*}
    d=${d%%:*}
    d=${d%.}
    [[ $d =~ $WEB_BARRIER_ALLOW_RE ]] && printf '%s' "$d"
}

# Los dominios permitidos como expresion para Apache: erp\.empresa\.com|([a-z0-9-]+\.)*empresa\.com
function web_barrier_allow_regex() {
    local d w out=""
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        w=""
        [ "${d#\*.}" != "$d" ] && { w='([a-z0-9-]+\.)*'; d=${d#\*.}; }
        out=${out:+$out|}$w$(printf '%s' "$d" | sed 's/\./\\./g')
    done < <(web_barrier_allowed)
    printf '%s' "${out:-$WEB_BARRIER_SLOT}"
}

# Un texto con el hueco de las webs permitidas relleno con las de la lista
function web_barrier_fill() {
    local text=$1 re out=""
    re=$(web_barrier_allow_regex)
    while [[ $text == *"$WEB_BARRIER_SLOT"* ]]; do
        out+=${text%%"$WEB_BARRIER_SLOT"*}$re
        text=${text#*"$WEB_BARRIER_SLOT"}
    done
    printf '%s' "$out$text"
}

# UNKNOWN_HOST_VHOST tal cual o, con la barrera apagada, sin su bloque (siempre acaba en salto de linea),
# con las webs permitidas
function unknown_host_vhost() {
    local text
    if web_barrier_on; then
        text=$UNKNOWN_HOST_VHOST
    else
        text=$(awk '/^# lvm-barrera-web:/ { skip = 1 } !skip { print } /^# \/lvm-barrera-web$/ { skip = 0 }' <<< "${UNKNOWN_HOST_VHOST%$'\n'}"; printf x)
        text=${text%x}
    fi
    web_barrier_fill "$text"
}

# barrera-web si|no: pone o quita la barrera entre webs en todas las versiones (y reinicia Apache
# de la activa si esta en marcha). Sin argumento, dice como esta
function web_barrier_command() {
    case "$1" in
        permitidas) web_barrier_allowed; return 0 ;;
        permitir|quitar) web_barrier_allow_command "$1" "$2"; return ;;
    esac
    # (si hay que cambiarla: la contraseña antes de nada; cancelarla la deja como estaba)
    if { [ "$1" == si ] && ! web_barrier_on; } || { [ "$1" == no ] && web_barrier_on; }; then
        sudo_first || return 1
    fi
    case "$1" in
        "")
            web_barrier_on && echo "Barrera entre webs: puesta" || echo "Barrera entre webs: apagada"
            [ -n "$(web_barrier_allowed)" ] && echo "Webs permitidas: $(web_barrier_allowed | paste -sd ' ' -)"
            return 0 ;;
        si|no) ;;
        *) echo "Uso: nexum barrera-web [si|no] | permitir <dominio> | quitar <dominio> | permitidas"; return 1 ;;
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
            echo "Apagada con nexum barrera-web no" | $SUDO tee "$WEB_BARRIER_OFF" > /dev/null || return 1
            [ -z "$SUDO" ] || $SUDO chmod 644 "$WEB_BARRIER_OFF" || return 1
        fi
    fi
    [ "$DRY" -eq 1 ] && return 0
    if ! web_barrier_apply; then
        # (no se ha podido aplicar: el interruptor vuelve a como estaba)
        if [ "$1" == si ]; then
            echo "Apagada con nexum barrera-web no" | $SUDO tee "$WEB_BARRIER_OFF" > /dev/null
            [ -z "$SUDO" ] || $SUDO chmod 644 "$WEB_BARRIER_OFF"
        else
            $SUDO rm -f "$WEB_BARRIER_OFF"
        fi
        secure_all > /dev/null 2>&1
        echo "No se ha podido cambiar en todas las versiones: se deja como estaba"
        return 1
    fi
    echo "Listo"
}

# barrera-web permitir|quitar <dominio>: añade o quita una web de las permitidas y lo aplica en todas las
# versiones (y en el Apache de Docker), como al poner o apagar la barrera
function web_barrier_allow_command() {
    local d list old
    d=$(web_barrier_domain "$2")
    if [ -z "$d" ]; then
        echo "«$2» no es un dominio: escribe uno como erp.empresa.com (o *.empresa.com para todos sus subdominios)"
        return 1
    fi
    list=$(web_barrier_allowed)
    if [ "$1" == permitir ]; then
        grep -qxF -- "$d" <<< "$list" && { echo "$d ya estaba entre las webs permitidas"; return 0; }
    else
        grep -qxF -- "$d" <<< "$list" || { echo "$d no estaba entre las webs permitidas"; return 0; }
    fi
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $d $([ "$1" == permitir ] && echo "pasa a estar permitida" || echo "deja de estar permitida") en todas las versiones"
        return 0
    fi
    [ -d "$COMMON" ] || { echo "No existe $COMMON (se crea al instalar la primera version)"; return 1; }
    sudo_first || return 1
    old=$list
    {
        if [ "$1" == permitir ]; then
            printf '%s\n' "$list" "$d"
        else
            grep -vxF -- "$d" <<< "$list"
        fi
    } | grep -E "$WEB_BARRIER_ALLOW_RE" | LC_ALL=C sort -u | $SUDO tee "$WEB_BARRIER_ALLOW" > /dev/null || return 1
    [ -z "$SUDO" ] || $SUDO chmod 644 "$WEB_BARRIER_ALLOW" || return 1
    if ! web_barrier_apply; then
        # (no se ha podido aplicar: la lista vuelve a como estaba)
        printf '%s\n' "$old" | grep -E "$WEB_BARRIER_ALLOW_RE" | $SUDO tee "$WEB_BARRIER_ALLOW" > /dev/null
        secure_all > /dev/null 2>&1
        echo "No se ha podido cambiar en todas las versiones: se deja como estaba"
        return 1
    fi
    if [ "$1" == permitir ]; then
        echo "$d, permitida: la barrera entre webs la deja pasar (formularios, su vuelta a tus proyectos, iframes)"
    else
        echo "$d ya no esta permitida: la barrera entre webs la para como a cualquier otra web"
    fi
}

# Lo que cambia la barrera o sus webs permitidas, en todas las versiones: su lvm-dominio-desconocido.conf,
# el Apache de la activa (recargado si esta en marcha) y el de Docker. 1 si no se ha podido escribir
function web_barrier_apply() {
    secure_all
    [ $? -eq 2 ] && return 1
    if [ -n "$(active_dir)" ] && [ -f "$LINK/xamppfiles/logs/httpd.pid" ]; then
        echo "Recargando Apache de la version activa..."
        xampp_ctl reloadapache > /dev/null || echo "No se ha podido recargar Apache: reinicia la version activa."
    fi
    # (y el Apache de Docker, si lo hay: lleva las mismas reglas de seguridad. Se rehace su configuracion y,
    # si esta en marcha, se recarga sin cortar las conexiones; parado, la toma al arrancar)
    if [ -f "$DOCKER_WEB_DIR/conf/httpd.conf" ]; then
        docker_web_reload || echo "Aviso: el Apache de Docker no se ha podido poner al dia; la tomara al arrancar"
    fi
    return 0
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

